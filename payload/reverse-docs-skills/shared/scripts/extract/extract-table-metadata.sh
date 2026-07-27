#!/usr/bin/env bash
# テーブルメタデータ抽出エンジン: table マニフェストの units[] にマイグレーション SQL 由来の
# メタデータ(foreignKeys/columnCount/mainColumns)をヒューリスティック抽出して追加した
# 拡張マニフェストを出力する。入力マニフェストの既存フィールドは一切変更しない。
#
# Usage: extract-table-metadata.sh <table-manifest.json> <migrations-dir> <output.json>
#        extract-table-metadata.sh --self-test
#
# 入出力契約:
#   入力: unitKind=table のユニットマニフェスト(validate-manifest.sh PASS 済み想定)と
#         マイグレーション SQL のディレクトリ
#   出力: units[] 各要素へ、抽出できたフィールドだけを追加した拡張マニフェスト JSON。
#         スキーマ正本: shared/references/manifest-schema-extensions.md「tables(テーブル)」節
#           - foreignKeys: string[] — FK 参照先テーブルの unitKey 配列。
#             空配列 [] は「REFERENCES を走査した結果 FK ゼロ件」という正の観測を意味し、
#             フィールド欠落は「走査自体ができなかった(sourceFile 不在等)」を意味する
#           - columnCount: number  — カラム定義行数(制約行は除外)
#           - mainColumns: string[] — カラム定義の先頭 5 列の物理名
#         検出根拠が弱い値は出力しない(誤った値より欠落を優先する fail-safe。
#         抽出できないフィールドは付けず、任意フィールドの欠落として扱われる)。
#         出力は validate-manifest.sh --unit-kind table で検証可能。
#
# 検出ヒューリスティック(grep/sed ベース。何を grep するか):
#   1. CREATE TABLE ブロック検出: sourceFile 内を grep -niE 'create[[:space:]]+table' し、
#      テーブル名(引用符 ` " [ ] ・スキーマ修飾・IF NOT EXISTS を除去。大文字小文字無視)が
#      units[].identifier と一致する行から `);` で終わる行までをブロックとして切り出す。
#      1 行完結の CREATE TABLE はカラム抽出の対象外(欠落として扱う)
#   2. columnCount / mainColumns: ブロックの中間行(先頭行と閉じ行を除く)のうち、空行・
#      コメント行(--)・先頭語が制約キーワード(PRIMARY/FOREIGN/UNIQUE/CHECK/CONSTRAINT/
#      INDEX/KEY/EXCLUDE)の行を除いた行をカラム定義とみなし、行頭トークン(引用符除去)を
#      物理名として採取する
#   3. foreignKeys: ブロック内の `REFERENCES <table>` (カラムインライン・FOREIGN KEY 句の両方)を
#      grep -oiE 'references[[:space:]]+[^[:space:](,;]+' で採取し、加えて sourceFile 内の
#      同一行完結 `ALTER TABLE <対象テーブル> ... REFERENCES <table>` 行からも採取する。
#      参照先物理名をマニフェスト内 identifier と大文字小文字無視で突合して unitKey へ解決し、
#      解決できない参照先は捨てる。走査できたユニットには解決結果が 0 件でも foreignKeys: [] を
#      明示出力する(空配列=FK なし観測済み、欠落=走査不能)
#
# sourceFile の解決: 記載パスが実在すればそれを使い、無ければ <migrations-dir>/ 相対で解決する。
# それでも不在のユニット、および kind=unresolved のユニットは抽出せずそのまま出力する。

set -euo pipefail

lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# --- SQL字句除去: コメント・文字列を空白化し、コードと括弧構造だけをstdoutへ出す ---
sql_code_only() {
  awk '
    BEGIN { block_depth = 0; in_string = 0; e_string = 0; dollar_tag = ""; quote = sprintf("%c", 39) }
    function code_only(source,    result, i, c, next_c, rest, prev_c, prev_prev_c) {
      result = ""
      for (i = 1; i <= length(source); i++) {
        c = substr(source, i, 1)
        next_c = substr(source, i + 1, 1)
        if (dollar_tag != "") {
          if (substr(source, i, length(dollar_tag)) == dollar_tag) {
            i += length(dollar_tag) - 1
            dollar_tag = ""
          }
          result = result " "
          continue
        }
        if (block_depth > 0) {
          if (c == "/" && next_c == "*") {
            block_depth++
            i++
          } else if (c == "*" && next_c == "/") {
            block_depth--
            i++
          }
          result = result " "
          continue
        }
        if (in_string) {
          if (e_string && c == "\\") {
            i++
          } else if (c == quote && next_c == quote) {
            i++
          } else if (c == quote) {
            in_string = 0
            e_string = 0
          }
          result = result " "
          continue
        }
        if (c == "-" && next_c == "-") break
        if (c == "/" && next_c == "*") {
          block_depth = 1
          result = result " "
          i++
          continue
        }
        if (c == quote) {
          prev_c = (i > 1 ? substr(source, i - 1, 1) : "")
          prev_prev_c = (i > 2 ? substr(source, i - 2, 1) : "")
          e_string = (prev_c ~ /[Ee]/ && prev_prev_c !~ /[[:alnum:]_]/)
          in_string = 1
          result = result " "
          continue
        }
        if (c == "$") {
          rest = substr(source, i)
          if (match(rest, /^\$\$/) || match(rest, /^\$[A-Za-z_][A-Za-z0-9_]*\$/)) {
            dollar_tag = substr(rest, 1, RLENGTH)
            i += RLENGTH - 1
            result = result " "
            continue
          }
        }
        result = result c
      }
      return result
    }
    {
      code = code_only($0)
      print code
    }
  ' "$1"
}

# --- CREATE TABLE ブロック切り出し: $1=file $2=テーブル物理名 → stdout(不検出なら空) ---
extract_create_block() {
  local file="$1" table_lc sql_code
  table_lc="$(lc "$2")"
  # 字句除去結果を先に読み切ってから対象ブロックを切り出す。早期終了する下流へ
  # ファイル読込をパイプしないため、pipefail下でもSIGPIPE(141)を発生させない。
  sql_code="$(sql_code_only "$file")"
  awk -v target="$table_lc" '
    BEGIN { target = tolower(target); started = 0 }
    {
      code = $0
      lower = tolower(code)
      if (!started && lower ~ /create[[:space:]]+table[[:space:]]+/) {
        name = lower
        sub(/.*create[[:space:]]+table[[:space:]]+/, "", name)
        sub(/^if[[:space:]]+not[[:space:]]+exists[[:space:]]+/, "", name)
        sub(/[[:space:](].*/, "", name)
        gsub(/[`"\[\]]/, "", name)
        sub(/^.*\./, "", name)
        if (name == target) started = 1
      }
      if (started) {
        print code
        if (code ~ /\)[^;]*;[[:space:]]*$/) exit
      }
    }
  ' <<< "$sql_code"
}

# --- カラム物理名抽出: stdin=CREATE TABLE ブロック → stdout=物理名(1 行 1 名) ---
extract_columns() {
  awk '
    NR==1 { next }
    /\)[^;]*;[[:space:]]*$/ { exit }
    {
      line=$0
      sub(/^[[:space:]]+/, "", line)
      if (line == "" || line ~ /^--/ || line ~ /^\(/) next
      first=tolower(line)
      sub(/[[:space:],(].*/, "", first)
      gsub(/[`"\[\]]/, "", first)
      if (first ~ /^(primary|foreign|unique|check|constraint|index|key|exclude)$/) next
      name=line
      sub(/[[:space:],(].*/, "", name)
      gsub(/[`"\[\]]/, "", name)
      if (name != "") print name
    }
  '
}

# --- FK 参照先物理名の収集: $1=block $2=file $3=対象テーブル物理名 → stdout=小文字物理名(重複除去) ---
collect_fk_targets() {
  local block="$1" file="$2" table_lc l tname alter_code
  table_lc="$(lc "$3")"
  alter_code="$(sql_code_only "$file")"
  {
    if [ -n "$block" ]; then
      printf '%s\n' "$block" | grep -oiE 'references[[:space:]]+[^[:space:](,;]+' || true
    fi
    while IFS= read -r l; do
      tname="$(printf '%s\n' "$l" | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/.*alter[[:space:]]+table[[:space:]]+//' \
        | sed -E 's/^(if[[:space:]]+exists[[:space:]]+)?(only[[:space:]]+)?//' \
        | sed -E 's/[[:space:]].*//' | tr -d '`"[]')"
      tname="${tname##*.}"
      [ "$tname" = "$table_lc" ] || continue
      printf '%s\n' "$l" | grep -oiE 'references[[:space:]]+[^[:space:](,;]+' || true
    done < <(grep -iE 'alter[[:space:]]+table[^;]*references' <<< "$alter_code" 2>/dev/null || true)
  } | awk '{print $2}' | tr -d '`"[]' | sed -E 's/.*\.//' \
    | tr '[:upper:]' '[:lower:]' | awk 'NF && !seen[$0]++'
}

# --- --self-test モード ---
# mktemp -d にフィクスチャ(users 5列 / posts 6列+FK の SQL と最小 table マニフェスト)を生成し、
# foreignKeys の unitKey 解決・FK なしテーブルの foreignKeys: [] 明示出力・columnCount・
# mainColumns・既存フィールド不変・validate-manifest.sh PASS を検証する。
self_test() {
  local script_path="$0" script_dir
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  local tmp rc=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/extract-table-metadata-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/migrations"
  cat > "$tmp/migrations/001_create_users.sql" <<'EOF'
CREATE TABLE users (
  id BIGINT NOT NULL,
  email VARCHAR(255) NOT NULL,
  name VARCHAR(100),
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE (email)
);
EOF
  cat > "$tmp/migrations/002_create_posts.sql" <<'EOF'
CREATE TABLE posts (
  id BIGINT NOT NULL,
  user_id BIGINT NOT NULL REFERENCES users(id),
  title VARCHAR(200) NOT NULL,
  body TEXT,
  published_at TIMESTAMP,
  created_at TIMESTAMP,
  PRIMARY KEY (id),
  FOREIGN KEY (user_id) REFERENCES users(id)
);
EOF

  # unitKey(users-master) と identifier(users) を意図的に変え、突合による解決を検証する
  local manifest="$tmp/table-manifest.json"
  jq -n \
    --arg sourceDir "$tmp/migrations" \
    --arg usersFile "$tmp/migrations/001_create_users.sql" \
    --arg postsFile "$tmp/migrations/002_create_posts.sql" \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      unitKind: "table",
      strategy: {extractionMethod: "migration-sql", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
      detectionSummary: {unitCount: 2, unresolvedCount: 0},
      units: [
        {unitKey: "users-master", kind: "table", identifier: "users", unitNameGuess: "ユーザー",
         sourceFile: $usersFile, confidence: "high", fileCount: 1, detectionMethod: "create-table"},
        {unitKey: "posts", kind: "table", identifier: "posts", unitNameGuess: "投稿",
         sourceFile: $postsFile, confidence: "high", fileCount: 1, detectionMethod: "create-table"}
      ]
    }' > "$manifest"

  local out="$tmp/out.json"
  if ! bash "$script_path" "$manifest" "$tmp/migrations" "$out" >/dev/null 2>&1; then
    echo "  [FAIL] 実行: 抽出コマンド自体が失敗した" >&2
    echo "self-test FAIL" >&2
    return 1
  fi

  if jq -e '.units[] | select(.unitKey=="users-master")
      | .columnCount == 5
        and .mainColumns == ["id","email","name","created_at","updated_at"]
        and .foreignKeys == []' "$out" >/dev/null 2>&1; then
    echo "  [PASS] users: columnCount=5・mainColumns 先頭5列・foreignKeys=[](FK なし観測済み)"
  else
    echo "  [FAIL] users: columnCount/mainColumns/foreignKeys が期待値と不一致" >&2
    rc=1
  fi

  if jq -e '.units[] | select(.unitKey=="posts")
      | .columnCount == 6
        and .foreignKeys == ["users-master"]
        and .mainColumns == ["id","user_id","title","body","published_at"]' "$out" >/dev/null 2>&1; then
    echo "  [PASS] posts: columnCount=6・foreignKeys が unitKey(users-master) へ解決・mainColumns 先頭5列"
  else
    echo "  [FAIL] posts: columnCount/foreignKeys/mainColumns が期待値と不一致" >&2
    rc=1
  fi

  local stripped="$tmp/stripped.json" expected="$tmp/expected.json"
  jq -S '.units |= map(del(.foreignKeys, .columnCount, .mainColumns))' "$out" > "$stripped" 2>/dev/null || true
  jq -S . "$manifest" > "$expected"
  if diff -q "$stripped" "$expected" >/dev/null 2>&1; then
    echo "  [PASS] 既存フィールド: 追加フィールドを除くと入力マニフェストと完全一致"
  else
    echo "  [FAIL] 既存フィールド: 入力マニフェストからの変化を検出した" >&2
    rc=1
  fi

  if bash "$script_dir/../unit-list/validate-manifest.sh" "$out" --unit-kind table >/dev/null 2>&1; then
    echo "  [PASS] validate-manifest.sh: 拡張マニフェストが --unit-kind table で PASS"
  else
    echo "  [FAIL] validate-manifest.sh: 拡張マニフェストの検証が FAIL" >&2
    rc=1
  fi

  # 1-16: 同一DDL内の3表以上を順に抽出しても、早期終了する抽出器が上流を
  # SIGPIPE(141)にしないことを確認する。
  local multi_file="$tmp/migrations/003_create_multi.sql"
  cat > "$multi_file" <<'EOF'
CREATE TABLE audit_logs (
  id BIGINT NOT NULL,
  user_id BIGINT NOT NULL REFERENCES users(id),
  message TEXT,
  PRIMARY KEY (id)
);
CREATE TABLE tags (
  id BIGINT NOT NULL,
  label VARCHAR(100) NOT NULL,
  PRIMARY KEY (id)
);
CREATE TABLE post_tags (
  post_id BIGINT NOT NULL REFERENCES posts(id),
  tag_id BIGINT NOT NULL REFERENCES tags(id),
  PRIMARY KEY (post_id, tag_id)
);
EOF
  local multi_manifest="$tmp/multi-table-manifest.json" multi_out="$tmp/multi-out.json"
  jq -n \
    --arg sourceDir "$tmp/migrations" \
    --arg multiFile "$multi_file" \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      unitKind: "table",
      strategy: {extractionMethod: "migration-sql", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
      detectionSummary: {unitCount: 3, unresolvedCount: 0},
      units: [
        {unitKey: "audit-logs", kind: "table", identifier: "audit_logs", unitNameGuess: "監査", sourceFile: $multiFile, confidence: "high", fileCount: 1, detectionMethod: "create-table"},
        {unitKey: "tags", kind: "table", identifier: "tags", unitNameGuess: "タグ", sourceFile: $multiFile, confidence: "high", fileCount: 1, detectionMethod: "create-table"},
        {unitKey: "post-tags", kind: "table", identifier: "post_tags", unitNameGuess: "投稿タグ", sourceFile: $multiFile, confidence: "high", fileCount: 1, detectionMethod: "create-table"}
      ]
    }' > "$multi_manifest"
  if ! bash "$script_path" "$multi_manifest" "$tmp/migrations" "$multi_out" >/dev/null 2>&1; then
    echo "  [FAIL] 1-16: 同一DDLの3表抽出がSIGPIPEを含む異常終了" >&2
    rc=1
  elif jq -e '
      (.units[] | select(.unitKey == "audit-logs") | .columnCount == 3)
      and (.units[] | select(.unitKey == "tags") | .columnCount == 2)
      and (.units[] | select(.unitKey == "post-tags") | .columnCount == 2)
    ' "$multi_out" >/dev/null 2>&1; then
    echo "  [PASS] 1-16: 同一DDLの3表抽出がpipefail下で完走"
  else
    echo "  [FAIL] 1-16: 同一DDLの3表抽出結果が不正" >&2
    rc=1
  fi

  # コメントやSQL文字列内のCREATE TABLEを抽出開始位置として扱わない。
  local commented_file="$tmp/migrations/004_commented_create.sql"
  local commented_manifest="$tmp/commented-table-manifest.json" commented_out="$tmp/commented-out.json"
  cat > "$commented_file" <<'EOF'
-- CREATE TABLE actual_table (
--   ghost_line TEXT
-- );
/*
CREATE TABLE actual_table (
  ghost_block TEXT
);
*/
SELECT 'CREATE TABLE actual_table (ghost_string TEXT);';
SELECT $$
CREATE TABLE actual_table (
  ghost_dollar TEXT
);
$$;
SELECT $body$
CREATE TABLE actual_table (
  ghost_tagged_dollar TEXT
);
$body$;
CREATE TABLE actual_table (
  real_id BIGINT NOT NULL,
  -- ghost_line TEXT REFERENCES ghost_line_table(id),
  /*
  ghost_block TEXT REFERENCES ghost_block_table(id),
    /*
    ghost_nested TEXT REFERENCES ghost_nested_table(id),
    */
  ghost_after_nested TEXT REFERENCES ghost_after_nested_table(id),
  */
  payload TEXT DEFAULT $$
  ghost_dollar TEXT REFERENCES ghost_dollar_table(id),
  $$,
  note TEXT DEFAULT $body$
  ghost_tagged_dollar TEXT REFERENCES ghost_tagged_table(id),
  $body$,
  escaped_note TEXT DEFAULT E'prefix\' ghost_escape TEXT REFERENCES ghost_escape_table(id)',
  standard_note TEXT DEFAULT 'abc\',
  user_id BIGINT REFERENCES users(id),
  real_name TEXT
) ENGINE=InnoDB;
CREATE TABLE trailing_noise (
  trailing_id BIGINT,
  trailing_user_id BIGINT REFERENCES ghost_trailing_table(id)
);
-- ALTER TABLE actual_table ADD COLUMN ghost_line_id BIGINT REFERENCES ghost_alter_line(id);
/* ALTER TABLE actual_table ADD COLUMN ghost_block_id BIGINT REFERENCES ghost_alter_block(id); */
SELECT 'ALTER TABLE actual_table ADD COLUMN ghost_string_id BIGINT REFERENCES ghost_alter_string(id);';
SELECT E'ALTER TABLE actual_table ADD COLUMN ghost_e_id BIGINT REFERENCES ghost_alter_e(id);';
SELECT $$ALTER TABLE actual_table ADD COLUMN ghost_dollar_id BIGINT REFERENCES ghost_alter_dollar(id);$$;
ALTER TABLE actual_table ADD COLUMN post_id BIGINT REFERENCES posts(id);
EOF
  jq -n \
    --arg sourceDir "$tmp/migrations" \
    --arg sourceFile "$commented_file" \
    --arg usersFile "$tmp/migrations/001_create_users.sql" \
    --arg postsFile "$tmp/migrations/002_create_posts.sql" \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      unitKind: "table",
      strategy: {extractionMethod: "migration-sql", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
      detectionSummary: {unitCount: 3, unresolvedCount: 0},
      units: [
        {unitKey: "actual-table", kind: "table", identifier: "actual_table", unitNameGuess: "実表",
         sourceFile: $sourceFile, confidence: "high", fileCount: 1, detectionMethod: "create-table"},
        {unitKey: "users-master", kind: "table", identifier: "users", unitNameGuess: "ユーザー",
         sourceFile: $usersFile, confidence: "high", fileCount: 1, detectionMethod: "create-table"},
        {unitKey: "posts", kind: "table", identifier: "posts", unitNameGuess: "投稿",
         sourceFile: $postsFile, confidence: "high", fileCount: 1, detectionMethod: "create-table"}
      ]
    }' > "$commented_manifest"
  if bash "$script_path" "$commented_manifest" "$tmp/migrations" "$commented_out" >/dev/null 2>&1 \
    && jq -e '.units[0]
      | .columnCount == 7
        and .mainColumns == ["real_id", "payload", "note", "escaped_note", "standard_note"]
        and .foreignKeys == ["users-master", "posts"]' "$commented_out" >/dev/null 2>&1; then
    echo "  [PASS] DDLコメント除外: 行・ブロックコメント、単一引用、ドル引用を無視して実DDLのみ抽出"
  else
    echo "  [FAIL] DDLコメント除外: コメントまたはSQL文字列内のCREATE TABLEを誤抽出" >&2
    rc=1
  fi

  # 900列超の入力では、head -5 が上流を SIGPIPE にしないことを確認する。
  # あわせて、PATCHES の合計が ARG_MAX を超える程度まで大きくしても、
  # パッチ集合をコマンドライン引数へ展開せずに適用できることを確認する。
  local stress_manifest="$tmp/stress-table-manifest.json" stress_out="$tmp/stress-out.json"
  local wide_file="$tmp/migrations/003_create_wide_columns.sql"
  local arg_file="$tmp/migrations/004_create_arg_payload.sql"
  local arg_max large_count=16 bytes_per_patch padding_length padding out_size n comma
  arg_max="$(getconf ARG_MAX 2>/dev/null || printf '%s' 262144)"
  case "$arg_max" in
    ''|*[!0-9]*) arg_max=262144 ;;
  esac
  bytes_per_patch=$((arg_max / large_count + 4096))
  padding_length=$((bytes_per_patch / 5))
  padding="$(printf '%*s' "$padding_length" '' | tr ' ' x)"

  {
    echo 'CREATE TABLE wide_columns ('
    for ((n = 1; n <= 900; n++)); do
      if [ "$n" -eq 900 ]; then comma=''; else comma=','; fi
      printf '  wide_column_%04d_padding_for_pipefail_regression VARCHAR(20)%s\n' "$n" "$comma"
    done
    echo ');'
  } > "$wide_file"
  {
    echo 'CREATE TABLE arg_payload ('
    for n in $(seq 1 5); do
      if [ "$n" -eq 5 ]; then comma=''; else comma=','; fi
      printf '  arg_column_%d_%s VARCHAR(20)%s\n' "$n" "$padding" "$comma"
    done
    echo ');'
  } > "$arg_file"

  jq -n \
    --arg sourceDir "$tmp/migrations" \
    --arg wideFile "$wide_file" \
    --arg argFile "$arg_file" \
    --argjson largeCount "$large_count" \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      unitKind: "table",
      strategy: {extractionMethod: "migration-sql", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
      detectionSummary: {unitCount: ($largeCount + 1), unresolvedCount: 0},
      units: (
        [{unitKey: "wide-columns", kind: "table", identifier: "wide_columns", unitNameGuess: "wide",
          sourceFile: $wideFile, confidence: "high", fileCount: 1, detectionMethod: "create-table"}]
        + [range(0; $largeCount) | {
          unitKey: ("arg-large-" + ((. + 1) | tostring)), kind: "table", identifier: "arg_payload", unitNameGuess: "arg",
          sourceFile: $argFile, confidence: "high", fileCount: 1, detectionMethod: "create-table"
        }]
      )
    }' > "$stress_manifest"

  if ! bash "$script_path" "$stress_manifest" "$tmp/migrations" "$stress_out" >/dev/null 2>&1; then
    echo "  [FAIL] stress: 900列または大規模パッチ集合で抽出コマンドが失敗した" >&2
    rc=1
  elif jq -e --argjson n "$large_count" '
      (.units[] | select(.unitKey == "wide-columns")
        | .columnCount == 900
          and .mainColumns == [
            "wide_column_0001_padding_for_pipefail_regression",
            "wide_column_0002_padding_for_pipefail_regression",
            "wide_column_0003_padding_for_pipefail_regression",
            "wide_column_0004_padding_for_pipefail_regression",
            "wide_column_0005_padding_for_pipefail_regression"
          ])
      and ([.units[] | select(.unitKey | startswith("arg-large-"))] | length == $n)
      and all(.units[] | select(.unitKey | startswith("arg-large-"));
        .columnCount == 5 and (.mainColumns | length == 5) and .foreignKeys == [])
    ' "$stress_out" >/dev/null 2>&1; then
    out_size="$(wc -c < "$stress_out" | tr -d ' ')"
    if [ "$out_size" -gt "$arg_max" ]; then
      echo "  [PASS] stress: 900列を全読込し、ARG_MAX超の大規模パッチ集合を適用"
    else
      echo "  [FAIL] stress: 出力が ARG_MAX を超えず、大規模パッチ回帰条件を満たさない" >&2
      rc=1
    fi
  else
    echo "  [FAIL] stress: 900列または大規模パッチ集合の出力内容が不正" >&2
    rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

MANIFEST="${1:?Usage: extract-table-metadata.sh <table-manifest.json> <migrations-dir> <output.json>}"
MIGRATIONS_DIR="${2:?Usage: extract-table-metadata.sh <table-manifest.json> <migrations-dir> <output.json>}"
OUTPUT="${3:?Usage: extract-table-metadata.sh <table-manifest.json> <migrations-dir> <output.json>}"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found in PATH" >&2
  exit 1
fi
if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: manifest not found: $MANIFEST" >&2
  exit 1
fi
if [ ! -d "$MIGRATIONS_DIR" ]; then
  echo "ERROR: migrations dir not found: $MIGRATIONS_DIR" >&2
  exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/extract-table-metadata.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# identifier(小文字) → unitKey の突合表
LOOKUP_JSON="$(jq -c '[.units[] | {key: (.identifier // "" | ascii_downcase), value: .unitKey}] | from_entries' "$MANIFEST")"

PATCHES="$WORK/patches.jsonl"
: > "$PATCHES"

while IFS= read -r row; do
  [ -z "$row" ] && continue
  unit_key="$(jq -r '.unitKey // ""' <<<"$row")"
  kind="$(jq -r '.kind // ""' <<<"$row")"
  identifier="$(jq -r '.identifier // ""' <<<"$row")"
  source_file="$(jq -r '.sourceFile // ""' <<<"$row")"
  [ "$kind" = "unresolved" ] && continue
  [ -z "$unit_key" ] && continue
  [ -z "$identifier" ] && continue

  file=""
  if [ -f "$source_file" ]; then
    file="$source_file"
  elif [ -n "$source_file" ] && [ -f "$MIGRATIONS_DIR/$source_file" ]; then
    file="$MIGRATIONS_DIR/$source_file"
  fi
  [ -z "$file" ] && continue

  block="$(extract_create_block "$file" "$identifier")"

  add='{}'

  # columnCount / mainColumns(ブロックが取れてカラムが 1 件以上のときのみ付与)
  if [ -n "$block" ]; then
    cols="$(printf '%s\n' "$block" | extract_columns)"
    if [ -n "$cols" ]; then
      col_count="$(printf '%s\n' "$cols" | grep -c .)"
      main_cols_json="$(printf '%s\n' "$cols" | jq -Rsc 'split("\n") | map(select(length > 0)) | .[:5]')"
      add="$(jq -c --argjson n "$col_count" --argjson m "$main_cols_json" \
        '. + {columnCount: $n, mainColumns: $m}' <<<"$add")"
    fi
  fi

  # foreignKeys(identifier 突合で unitKey へ解決できたものだけ。走査済みのため
  # 0 件でも [] を明示出力する。空配列=FK なし観測済み、欠落=走査不能)
  fk_keys='[]'
  while IFS= read -r target; do
    [ -z "$target" ] && continue
    resolved="$(jq -r --arg k "$target" '.[$k] // empty' <<<"$LOOKUP_JSON")"
    [ -z "$resolved" ] && continue
    fk_keys="$(jq -c --arg k "$resolved" 'if index($k) then . else . + [$k] end' <<<"$fk_keys")"
  done < <(collect_fk_targets "$block" "$file" "$identifier")
  add="$(jq -c --argjson f "$fk_keys" '. + {foreignKeys: $f}' <<<"$add")"

  if [ "$add" != "{}" ]; then
    jq -c -n --arg k "$unit_key" --argjson a "$add" '{key: $k, value: $a}' >> "$PATCHES"
  fi
done < <(jq -c '.units[]' "$MANIFEST")

mkdir -p "$(dirname "$OUTPUT")"
jq --slurpfile patches "$PATCHES" '
  (reduce $patches[] as $patch ({}; .[$patch.key] = $patch.value)) as $patch_map
  | .units |= map(. + ($patch_map[.unitKey] // {}))
' "$MANIFEST" > "$OUTPUT"

echo "OK: wrote $OUTPUT" >&2
