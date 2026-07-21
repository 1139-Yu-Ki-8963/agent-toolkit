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
#           - foreignKeys: string[] — FK 参照先テーブルの unitKey 配列
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
#      解決できない参照先は捨てる。1 件も解決できなければフィールド自体を付けない
#
# sourceFile の解決: 記載パスが実在すればそれを使い、無ければ <migrations-dir>/ 相対で解決する。
# それでも不在のユニット、および kind=unresolved のユニットは抽出せずそのまま出力する。

set -euo pipefail

lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# --- CREATE TABLE ブロック切り出し: $1=file $2=テーブル物理名 → stdout(不検出なら空) ---
extract_create_block() {
  local file="$1" table_lc start="" lineno line name
  table_lc="$(lc "$2")"
  while IFS=: read -r lineno line; do
    name="$(printf '%s\n' "$line" | tr '[:upper:]' '[:lower:]' \
      | sed -E 's/.*create[[:space:]]+table[[:space:]]+//' \
      | sed -E 's/^if[[:space:]]+not[[:space:]]+exists[[:space:]]+//' \
      | sed -E 's/[[:space:](].*//' | tr -d '`"[]')"
    name="${name##*.}"
    if [ "$name" = "$table_lc" ]; then
      start="$lineno"
      break
    fi
  done < <(grep -niE 'create[[:space:]]+table[[:space:]]' "$file" 2>/dev/null || true)
  [ -z "$start" ] && return 0
  sed -n "${start},\$p" "$file" | awk '{print} /\)[[:space:]]*;[[:space:]]*$/{exit}'
}

# --- カラム物理名抽出: stdin=CREATE TABLE ブロック → stdout=物理名(1 行 1 名) ---
extract_columns() {
  awk '
    NR==1 { next }
    /\)[[:space:]]*;[[:space:]]*$/ { exit }
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
  local block="$1" file="$2" table_lc l tname
  table_lc="$(lc "$3")"
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
    done < <(grep -iE 'alter[[:space:]]+table[^;]*references' "$file" 2>/dev/null || true)
  } | awk '{print $2}' | tr -d '`"[]' | sed -E 's/.*\.//' \
    | tr '[:upper:]' '[:lower:]' | awk 'NF && !seen[$0]++'
}

# --- --self-test モード ---
# mktemp -d にフィクスチャ(users 5列 / posts 6列+FK の SQL と最小 table マニフェスト)を生成し、
# foreignKeys の unitKey 解決・columnCount・mainColumns・既存フィールド不変・
# validate-manifest.sh PASS を検証する。
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
        and (has("foreignKeys") | not)' "$out" >/dev/null 2>&1; then
    echo "  [PASS] users: columnCount=5・mainColumns 先頭5列・foreignKeys 欠落(FK なし)"
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
      main_cols_json="$(printf '%s\n' "$cols" | head -5 | jq -R . | jq -s -c .)"
      add="$(jq -c --argjson n "$col_count" --argjson m "$main_cols_json" \
        '. + {columnCount: $n, mainColumns: $m}' <<<"$add")"
    fi
  fi

  # foreignKeys(identifier 突合で unitKey へ解決できたものだけ。0 件ならフィールドを付けない)
  fk_keys='[]'
  while IFS= read -r target; do
    [ -z "$target" ] && continue
    resolved="$(jq -r --arg k "$target" '.[$k] // empty' <<<"$LOOKUP_JSON")"
    [ -z "$resolved" ] && continue
    fk_keys="$(jq -c --arg k "$resolved" 'if index($k) then . else . + [$k] end' <<<"$fk_keys")"
  done < <(collect_fk_targets "$block" "$file" "$identifier")
  if [ "$fk_keys" != "[]" ]; then
    add="$(jq -c --argjson f "$fk_keys" '. + {foreignKeys: $f}' <<<"$add")"
  fi

  if [ "$add" != "{}" ]; then
    jq -c -n --arg k "$unit_key" --argjson a "$add" '{key: $k, value: $a}' >> "$PATCHES"
  fi
done < <(jq -c '.units[]' "$MANIFEST")

PATCH_MAP="$(jq -s 'from_entries' "$PATCHES")"

mkdir -p "$(dirname "$OUTPUT")"
jq --argjson p "$PATCH_MAP" '.units |= map(. + ($p[.unitKey] // {}))' "$MANIFEST" > "$OUTPUT"

echo "OK: wrote $OUTPUT" >&2
