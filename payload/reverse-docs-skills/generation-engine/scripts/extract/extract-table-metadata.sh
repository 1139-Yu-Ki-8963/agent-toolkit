#!/usr/bin/env bash
# テーブルメタデータ抽出エンジン: table マニフェストの units[] にマイグレーション SQL 由来の
# メタデータ(foreignKeys/columnCount/mainColumns)をヒューリスティック抽出して追加した
# 拡張マニフェストを出力する。入力マニフェストの既存フィールドは一切変更しない。
#
# Usage: extract-table-metadata.sh <table-manifest.json> <source-dir> <output.json>
#        extract-table-metadata.sh --self-test
#
# 入出力契約:
#   入力: unitKind=table のユニットマニフェスト(validate-manifest.sh PASS 済み想定)と
#         マイグレーション SQL のディレクトリ
#   出力: units[] 各要素へ、抽出できたフィールドだけを追加した拡張マニフェスト JSON。
#         スキーマ正本: delivery-payload/references/manifest-schema-extensions.md「tables(テーブル)」節
#           - foreignKeys: string[] — FK 参照先テーブルの unitKey 配列。
#             空配列 [] は「REFERENCES を走査した結果 FK ゼロ件」という正の観測を意味し、
#             フィールド欠落は「走査自体ができなかった(sourceFile 不在・CREATE TABLE ブロック
#             未検出等)」を意味する
#           - columnCount: number  — 最終的な物理カラム数(後続マイグレーションの
#             ADD COLUMN/DROP COLUMN を反映した最終状態。制約行は除外)
#           - mainColumns: string[] — 最終的なカラム物理名(先頭 5 列)
#         検出根拠が弱い値は出力しない(誤った値より欠落を優先する fail-safe。
#         抽出できないフィールドは付けず、任意フィールドの欠落として扱われる)。
#         出力は validate-manifest.sh --unit-kind table で検証可能。
#
# 検出ヒューリスティック(grep/sed/awk ベース。何を検出するか):
#   1. CREATE TABLE ブロック検出: sourceFile 内を grep -niE 'create[[:space:]]+table' し、
#      テーブル名(引用符 ` " [ ] ・スキーマ修飾・IF NOT EXISTS を除去。大文字小文字無視)が
#      units[].identifier と一致する行から、カラム定義を囲む括弧の深さが 0 へ戻る行までを
#      ブロックとして切り出す(1-134: 終端判定は閉じ括弧の深さ復帰のみで行い、文末記号(;)の
#      有無・位置は問わない。MySQL 等、閉じ括弧に ENGINE=/DEFAULT CHARSET= 等の記憶域指定が
#      続き、文末記号(;)が数行後の別行に置かれる方言でも、閉じ括弧の行までを正しくブロックの
#      終端とみなす。閉じ括弧から文末記号までの間に置かれる記憶域指定行はブロックに含めず、
#      後続の無関係な定義を誤って取り込まない)。1 行完結の CREATE TABLE はカラム抽出の対象外
#      (欠落として扱う。ブロックが取れない場合、columnCount/mainColumns/foreignKeys の
#      3 フィールドとも付与しない。foreignKeys だけを block 抜きで走査すると、後述の
#      DROP COLUMN によるゴースト FK 除去(§4)の前提となる列一覧を持てず、誤って残存 FK を
#      観測済みと報告しうるため、3 フィールドは常に一体で欠落させる)
#   2. カラム定義の切り出し: CREATE TABLE ブロック本体を 1 本の文字列へ連結してから、
#      括弧の深さが 0 の位置にあるカンマだけで定義単位に分割する(改善課題該当: 列名と
#      外部キー句が別の行に分かれる記法。従来は 1 行 = 1 定義という前提で行走査していたため、
#      `col_name TYPE\n  REFERENCES other(id),` のように REFERENCES 句が次の行へ折れる記法で
#      予約語 REFERENCES を列名として取り込んでいた。深さ 0 のカンマ区切りへ変更したことで、
#      改行位置に関係なく 1 個の列定義/制約定義を 1 単位として扱う)。定義の先頭語が
#      PRIMARY/UNIQUE/CHECK/CONSTRAINT/INDEX/KEY/EXCLUDE の場合は列ではなく制約として除外し、
#      先頭語が FOREIGN の場合(または CONSTRAINT 名 FOREIGN KEY の場合)は列ではなく
#      テーブルレベル FK 制約として §3 で扱う。列の抽出前に行内コメント(-- 以降・# 以降。
#      文字列・ブロックコメント内の疑似コメント記号は sql_code_only で除去済み)を除去して
#      から抽出するため、コメント文言がカラム物理名へ連結されない(1-134)
#   3. カラム単位の FK 追跡: インライン `col TYPE ... REFERENCES target(...)` と、テーブル
#      レベル `[CONSTRAINT name] FOREIGN KEY (col[, col2]) REFERENCES target(...)` の両方を、
#      対象となるカラム物理名に紐づけて記録する(単純な REFERENCES の全文検索ではなく、
#      「どの列が参照しているか」を保持する。これにより後述 §4 の DROP COLUMN 追跡で、
#      同じ参照先テーブルへ複数列が参照している場合に、片方の列が削除されても他方の列が
#      持つ参照は残せる)
#   4. マイグレーション履歴への追随: CREATE TABLE の初期カラム一覧を起点に、<migrations-dir>
#      配下の全 .sql ファイルをファイル名の辞書順(タイムスタンプ接頭辞のため時系列順と一致)で
#      走査し、対象テーブルへの `ALTER TABLE ... ADD COLUMN [IF NOT EXISTS] col ... [REFERENCES
#      target]`(1 文中のカンマ区切り複数列指定を含む)・`ALTER TABLE ... DROP COLUMN [IF EXISTS]
#      col`・`ALTER TABLE ... ADD [CONSTRAINT name] FOREIGN KEY (col) REFERENCES target` を
#      時系列順に適用する。ADD は列を末尾へ追加し(Postgres の物理配置と一致)、DROP は列と
#      その列に紐づく FK 参照を一緒に取り除く。最終的な columnCount/mainColumns はこの適用後の
#      列一覧から、foreignKeys は適用後に残っている列が持つ参照先だけから算出する(改善課題
#      「テーブル一覧-列数追随なし」「テーブル一覧-外部キーの誤り」の根本原因はこの追随処理の
#      欠落だった。旧実装は sourceFile 1 本(CREATE TABLE を含むファイル)しか読まず、後続の
#      ALTER TABLE を別ファイルに置く運用(migrations ディレクトリの一般的な構成)では
#      ADD COLUMN による増加も DROP COLUMN によるゴースト FK 除去も一切反映されなかった)
#   5. RENAME COLUMN・名前を持たない DROP CONSTRAINT による FK 解除は追跡しない(既知の限界。
#      ヒューリスティック抽出であり完全な SQL 意味解析ではないため)
#   6. §4 のディレクトリ横断走査は <migrations-dir> 配下の全 .sql ファイルの ALTER TABLE を
#      対象とし、入力マニフェストの strategy.excludePatterns を考慮しない(既知の限界。
#      down/rollback/seed 等の除外指定ファイルにスキーマ変更(ADD/DROP COLUMN)が含まれる場合、
#      本来適用されないはずの操作が反映される)
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
        if (c == "#") break
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
  sql_code="$(sql_code_only_cached "$file")"
  # 1-134: 終端判定は文末記号(;)の有無・位置に依存せず、カラム定義を囲む括弧の深さが
  # 0 へ戻った行までをブロックとする。開始行の `CREATE TABLE ... (` が開く 1 段目の
  # 括弧を depth=1 として起点に取り、以降の行で depth が 0 へ戻った時点を終端とみなす。
  # これにより、閉じ括弧の直後に ENGINE=/DEFAULT CHARSET= 等の記憶域指定が続き、文末記号が
  # 数行後の別行に置かれる方言でも、後続の無関係な定義を取り込まずに正しく打ち切れる。
  LC_ALL=C awk -v target="$table_lc" '
    BEGIN { target = tolower(target); started = 0; depth = 0 }
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
        n = length(code)
        for (i = 1; i <= n; i++) {
          ch = substr(code, i, 1)
          if (ch == "(") depth++
          else if (ch == ")") {
            depth--
            if (depth == 0) exit
          }
        }
      }
    }
  ' <<< "$sql_code"
}

# --- 深さ0カンマ分割 + カラム/FK抽出の共通awk関数群(複数関数から source される) ---
# split_top_commas: 括弧の深さが0の位置にあるカンマだけで s を分割し arr[] へ格納する
_TOP_COMMA_SPLIT_AWK_FUNCS='
  function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
  function stripq(s) { gsub(/[`"\[\]]/, "", s); return s }
  function split_top_commas(s, arr,    n2, depth2, start2, i2, c2, cnt) {
    n2 = length(s); depth2 = 0; start2 = 1; cnt = 0
    for (i2 = 1; i2 <= n2; i2++) {
      c2 = substr(s, i2, 1)
      if (c2 == "(") depth2++
      else if (c2 == ")") depth2--
      else if (c2 == "," && depth2 == 0) {
        cnt++
        arr[cnt] = substr(s, start2, i2 - start2)
        start2 = i2 + 1
      }
    }
    cnt++
    arr[cnt] = substr(s, start2)
    return cnt
  }
'

# --- CREATE TABLE ブロックからのカラム/FK操作抽出: stdin=block → stdout=TSV(ADD|FK, col, fk) ---
# ADD col fk       : カラム定義(fk は REFERENCES を持つ場合のみ非空)
# FK  col target   : テーブルレベル FOREIGN KEY (col) REFERENCES target(1 列につき 1 行)
extract_create_table_ops() {
  awk "$_TOP_COMMA_SPLIT_AWK_FUNCS"'
    function process_def(def,   lc, first, colname, fk, m, colsstr, cols, ncols, k, cn, tgt) {
      if (def == "") return
      lc = tolower(def)

      if (match(lc, /foreign[[:space:]]+key[[:space:]]*\([^)]*\)[[:space:]]*references[[:space:]]+[^[:space:](,;]+/)) {
        m = substr(lc, RSTART, RLENGTH)
        colsstr = m; sub(/^[^(]*\(/, "", colsstr); sub(/\).*/, "", colsstr)
        ncols = split(colsstr, cols, ",")
        tgt = m; sub(/^.*references[[:space:]]+/, "", tgt); tgt = stripq(tgt); sub(/^.*\./, "", tgt)
        for (k = 1; k <= ncols; k++) {
          cn = stripq(trim(cols[k]))
          if (cn != "") printf "FK\t%s\t%s\n", cn, tgt
        }
      }

      first = lc
      sub(/[[:space:],(].*/, "", first)
      first = stripq(first)
      if (first ~ /^(primary|foreign|unique|check|constraint|index|key|exclude)$/) return

      colname = def
      sub(/[[:space:](].*/, "", colname)
      colname = tolower(stripq(colname))
      if (colname == "") return
      fk = ""
      if (match(lc, /references[[:space:]]+[^[:space:](,;]+/)) {
        fk = substr(lc, RSTART, RLENGTH)
        sub(/^references[[:space:]]+/, "", fk)
        fk = stripq(fk); sub(/^.*\./, "", fk)
      }
      printf "ADD\t%s\t%s\n", colname, fk
    }
    NR==1 { next }
    {
      line = $0
      t = trim(line)
      if (t == "") next
      if (t ~ /^\)/) next
      buf = buf " " t
    }
    END {
      n = split_top_commas(buf, defs)
      for (i = 1; i <= n; i++) process_def(trim(defs[i]))
    }
  '
}

# --- 全ファイル横断の ALTER TABLE 操作抽出: stdin=1ファイルのコード(sql_code_only済み)
#     → stdout=TSV(table, ADD|DROP|FK, col, fk)。対象テーブルを絞らず全テーブル分を出す ---
extract_alter_ops_all_tables() {
  awk "$_TOP_COMMA_SPLIT_AWK_FUNCS"'
    { buf = buf $0 "\n" }
    END {
      n = length(buf); depth = 0; start = 1
      for (i = 1; i <= n; i++) {
        c = substr(buf, i, 1)
        if (c == "(") depth++
        else if (c == ")") depth--
        else if (c == ";" && depth == 0) { handle(substr(buf, start, i - start)); start = i + 1 }
      }
      if (start <= n) handle(substr(buf, start))
    }
    function handle(raw,   stmt, name, rest, clauses, cnt, j, clause, colname, colpart, fk, tgt, colsstr, cols, ncols, k, m) {
      stmt = tolower(raw); gsub(/\n/, " ", stmt); stmt = trim(stmt)
      if (stmt == "") return
      if (stmt !~ /^alter[[:space:]]+table[[:space:]]+/) return

      name = stmt
      sub(/^alter[[:space:]]+table[[:space:]]+/, "", name)
      sub(/^if[[:space:]]+exists[[:space:]]+/, "", name)
      sub(/^only[[:space:]]+/, "", name)
      sub(/[[:space:]].*/, "", name)
      name = stripq(name); sub(/^.*\./, "", name)
      if (name == "") return

      rest = stmt
      sub(/^alter[[:space:]]+table[[:space:]]+/, "", rest)
      sub(/^if[[:space:]]+exists[[:space:]]+/, "", rest)
      sub(/^only[[:space:]]+/, "", rest)
      sub(/^[^[:space:]]+[[:space:]]*/, "", rest)

      cnt = split_top_commas(rest, clauses)
      for (j = 1; j <= cnt; j++) {
        clause = trim(clauses[j])
        if (clause == "") continue
        if (clause ~ /^add[[:space:]]+column[[:space:]]+/) {
          colpart = clause
          sub(/^add[[:space:]]+column[[:space:]]+/, "", colpart)
          sub(/^if[[:space:]]+not[[:space:]]+exists[[:space:]]+/, "", colpart)
          colname = colpart
          sub(/[[:space:]].*/, "", colname)
          colname = stripq(colname)
          if (colname == "") continue
          fk = ""
          if (match(clause, /references[[:space:]]+[^[:space:](,;]+/)) {
            fk = substr(clause, RSTART, RLENGTH)
            sub(/^references[[:space:]]+/, "", fk)
            fk = stripq(fk); sub(/^.*\./, "", fk)
          }
          printf "%s\tADD\t%s\t%s\n", name, colname, fk
        } else if (clause ~ /^drop[[:space:]]+column[[:space:]]+/) {
          colpart = clause
          sub(/^drop[[:space:]]+column[[:space:]]+/, "", colpart)
          sub(/^if[[:space:]]+exists[[:space:]]+/, "", colpart)
          colname = colpart
          sub(/[[:space:]].*/, "", colname)
          colname = stripq(colname)
          if (colname != "") printf "%s\tDROP\t%s\t\n", name, colname
        } else if (clause ~ /^(add[[:space:]]+constraint[[:space:]]+[^[:space:]]+[[:space:]]+)?foreign[[:space:]]+key[[:space:]]*\(/) {
          if (match(clause, /foreign[[:space:]]+key[[:space:]]*\([^)]*\)[[:space:]]*references[[:space:]]+[^[:space:](,;]+/)) {
            m = substr(clause, RSTART, RLENGTH)
            colsstr = m; sub(/^[^(]*\(/, "", colsstr); sub(/\).*/, "", colsstr)
            ncols = split(colsstr, cols, ",")
            tgt = m; sub(/^.*references[[:space:]]+/, "", tgt); tgt = stripq(tgt); sub(/^.*\./, "", tgt)
            for (k = 1; k <= ncols; k++) {
              colname = stripq(trim(cols[k]))
              if (colname != "") printf "%s\tFK\t%s\t%s\n", name, colname, tgt
            }
          }
        }
      }
    }
  '
}

# --- 操作ログの時系列適用: stdin=TSV(ADD|DROP|FK, col, fk) → stdout=TSV
#     COLCOUNT n / MAINCOL name(先頭5列) / FKTARGET name(残存列の参照先。重複除去・出現順) ---
apply_column_ops() {
  awk -F'\t' '
    {
      op = $1; col = $2; fk = $3
      if (col == "") next
      if (op == "ADD") {
        if (!(col in idx)) { ncols++; idx[col] = ncols; cols[ncols] = col }
        present[col] = 1
        if (fk != "") { fk_of[col] = (fk_of[col] == "" ? fk : fk_of[col] SUBSEP fk) }
      } else if (op == "DROP") {
        if (col in idx) { present[col] = 0; fk_of[col] = "" }
      } else if (op == "FK") {
        if (!(col in idx)) { ncols++; idx[col] = ncols; cols[ncols] = col; present[col] = 1 }
        if (present[col] == 1) { fk_of[col] = (fk_of[col] == "" ? fk : fk_of[col] SUBSEP fk) }
      }
    }
    END {
      m = 0
      for (i = 1; i <= ncols; i++) {
        c = cols[i]
        if (present[c] == 1) { m++; final_cols[m] = c }
      }
      printf "COLCOUNT\t%d\n", m
      for (i = 1; i <= m && i <= 5; i++) printf "MAINCOL\t%s\n", final_cols[i]
      for (i = 1; i <= m; i++) {
        c = final_cols[i]
        if (fk_of[c] == "") continue
        nfk = split(fk_of[c], fks, SUBSEP)
        for (k = 1; k <= nfk; k++) {
          t = fks[k]
          if (t == "" || (t in fkseen)) continue
          fkseen[t] = 1
          printf "FKTARGET\t%s\n", t
        }
      }
    }
  '
}

# --- <dir> 配下の全 .sql をファイル名の辞書順(タイムスタンプ接頭辞のため時系列順と一致)で
#     走査し、ALTER TABLE 操作ログを1回だけ構築する。$2=出力先ファイル ---
build_alter_ops_log() {
  local dir="$1" out="$2" f
  : > "$out"
  while IFS= read -r f; do
    sql_code_only_cached "$f" | extract_alter_ops_all_tables >> "$out"
  done < <(find "$dir" -type f -name '*.sql' 2>/dev/null | LC_ALL=C sort)
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
  jq -S '.units |= map(del(.foreignKeys, .columnCount, .mainColumns))
         | del(.detectionSummary.diagnostics.extensionExtraction)
         | if .detectionSummary.diagnostics == {} then del(.detectionSummary.diagnostics) else . end' "$out" > "$stripped" 2>/dev/null || true
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
      | .columnCount == 8
        and .mainColumns == ["real_id", "payload", "note", "escaped_note", "standard_note"]
        and .foreignKeys == ["users-master", "posts"]' "$commented_out" >/dev/null 2>&1; then
    echo "  [PASS] DDLコメント除外: 行・ブロックコメント、単一引用、ドル引用を無視して実DDLのみ抽出。"\
"末尾の実ALTER(post_id追加)は後続マイグレーション追随によりcolumnCount=8へ反映(mainColumnsは先頭5列のため不変)"
  else
    echo "  [FAIL] DDLコメント除外: コメントまたはSQL文字列内のCREATE TABLEを誤抽出、"\
"またはpost_id追加がcolumnCountへ反映されていない" >&2
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

  local stress_err="$tmp/stress-stderr.txt"
  if ! bash "$script_path" "$stress_manifest" "$tmp/migrations" "$stress_out" >"$stress_err" 2>&1; then
    echo "  [FAIL] stress: 900列または大規模パッチ集合で抽出コマンドが失敗した" >&2
    echo "$(tail -20 "$stress_err")" >&2
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

  # 1-134: 終端の閉じ括弧に記憶域指定(ENGINE=/DEFAULT CHARSET=/COLLATE=)が続き、
  # 文末記号(;)が数行後の別行に置かれる方言。実数7カラムに対し、旧ロジックは
  # 文末記号を持たない閉じ括弧行で打ち切れず後続の無関係な定義まで取り込んでいた。
  local dialect_file="$tmp/migrations/005_create_dialect_orders.sql"
  cat > "$dialect_file" <<'EOF'
CREATE TABLE dialect_orders (
  id BIGINT NOT NULL,
  customer_id BIGINT NOT NULL REFERENCES users(id),
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  total_amount DECIMAL(10,2) NOT NULL,
  note TEXT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  PRIMARY KEY (id)
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_unicode_ci;

CREATE TABLE dialect_shipments (
  id BIGINT NOT NULL,
  order_id BIGINT NOT NULL REFERENCES dialect_orders(id),
  address VARCHAR(255) NOT NULL,
  PRIMARY KEY (id)
);
EOF
  local dialect_manifest="$tmp/dialect-table-manifest.json" dialect_out="$tmp/dialect-out.json"
  jq -n \
    --arg sourceDir "$tmp/migrations" \
    --arg dialectFile "$dialect_file" \
    --arg usersFile "$tmp/migrations/001_create_users.sql" \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      unitKind: "table",
      strategy: {extractionMethod: "migration-sql", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
      detectionSummary: {unitCount: 2, unresolvedCount: 0},
      units: [
        {unitKey: "dialect-orders", kind: "table", identifier: "dialect_orders", unitNameGuess: "受注(方言)",
         sourceFile: $dialectFile, confidence: "high", fileCount: 1, detectionMethod: "create-table"},
        {unitKey: "users-master", kind: "table", identifier: "users", unitNameGuess: "ユーザー",
         sourceFile: $usersFile, confidence: "high", fileCount: 1, detectionMethod: "create-table"}
      ]
    }' > "$dialect_manifest"
  if bash "$script_path" "$dialect_manifest" "$tmp/migrations" "$dialect_out" >/dev/null 2>&1 \
    && jq -e '.units[0]
      | .columnCount == 7
        and .mainColumns == ["id", "customer_id", "status", "total_amount", "note"]
        and .foreignKeys == ["users-master"]' "$dialect_out" >/dev/null 2>&1; then
    echo "  [PASS] 1-134 終端判定: ENGINE=/CHARSET=等の記憶域指定を挟み文末記号が数行後にある方言でも実数どおりcolumnCount=7(後続の無関係なdialect_shipmentsの列を取り込まない)"
  else
    echo "  [FAIL] 1-134 終端判定: 方言定義ファイルでcolumnCountが実数7と不一致、または後続定義を誤って取り込んだ" >&2
    jq -c '.units[0] | {columnCount, mainColumns, foreignKeys}' "$dialect_out" 2>/dev/null >&2 || true
    rc=1
  fi

  # 1-134: 行内コメント(--・#いずれも)を除去してからカラムを抽出する。コメント行・
  # 行末コメントの文言が主要カラム欄(mainColumns)へ連結されないことを確認する。
  local commented_cols_file="$tmp/migrations/006_create_commented_columns.sql"
  cat > "$commented_cols_file" <<'EOF'
CREATE TABLE commented_columns (
  id BIGINT NOT NULL, -- 主キー
  name VARCHAR(100) NOT NULL, # 氏名
  # ここはコメント専用行
  status VARCHAR(20) DEFAULT 'active',
  PRIMARY KEY (id)
);
EOF
  local commented_cols_manifest="$tmp/commented-columns-manifest.json" commented_cols_out="$tmp/commented-columns-out.json"
  jq -n \
    --arg sourceDir "$tmp/migrations" \
    --arg sourceFile "$commented_cols_file" \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      unitKind: "table",
      strategy: {extractionMethod: "migration-sql", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
      detectionSummary: {unitCount: 1, unresolvedCount: 0},
      units: [
        {unitKey: "commented-columns", kind: "table", identifier: "commented_columns", unitNameGuess: "コメント混在",
         sourceFile: $sourceFile, confidence: "high", fileCount: 1, detectionMethod: "create-table"}
      ]
    }' > "$commented_cols_manifest"
  if bash "$script_path" "$commented_cols_manifest" "$tmp/migrations" "$commented_cols_out" >/dev/null 2>&1 \
    && jq -e '.units[0]
      | .columnCount == 3
        and .mainColumns == ["id", "name", "status"]' "$commented_cols_out" >/dev/null 2>&1; then
    echo "  [PASS] 1-134 行内コメント除去: --・#いずれの行内コメントもmainColumnsへ連結されずcolumnCount=3"
  else
    echo "  [FAIL] 1-134 行内コメント除去: コメント文言がmainColumnsへ混入、またはcolumnCountが不一致" >&2
    jq -c '.units[0] | {columnCount, mainColumns}' "$commented_cols_out" 2>/dev/null >&2 || true
    rc=1
  fi

  # --- 1-127: 500ユニットが同一の大きなスキーマファイルを共有する規模でも、
  # sql_code_only のファイル単位キャッシュにより単一走査で完了し、各ユニットの抽出結果が
  # 個々のCREATE TABLE定義と一致すること ---
  local scale_dir="$tmp/scale"
  mkdir -p "$scale_dir/migrations"
  local scale_schema="$scale_dir/migrations/schema.sql"
  : > "$scale_schema"
  local n
  for ((n = 1; n <= 500; n++)); do
    if [ "$n" -eq 1 ]; then
      printf 'CREATE TABLE scale_table_%04d (\n  id BIGINT NOT NULL,\n  name VARCHAR(100),\n  PRIMARY KEY (id)\n);\n\n' "$n" >> "$scale_schema"
    else
      printf 'CREATE TABLE scale_table_%04d (\n  id BIGINT NOT NULL,\n  parent_id BIGINT NOT NULL REFERENCES scale_table_%04d(id),\n  name VARCHAR(100),\n  PRIMARY KEY (id)\n);\n\n' "$n" "$((n - 1))" >> "$scale_schema"
    fi
  done

  local scale_units="$scale_dir/units.jsonl"
  : > "$scale_units"
  for ((n = 1; n <= 500; n++)); do
    printf '{"unitKey":"scale-table-%d","kind":"table","identifier":"scale_table_%04d","unitNameGuess":"table%d","sourceFile":"%s","confidence":"high","fileCount":1,"detectionMethod":"create-table"}\n' \
      "$n" "$n" "$n" "$scale_schema" >> "$scale_units"
  done

  local scale_manifest="$scale_dir/table-manifest.json" scale_out="$scale_dir/out.json"
  jq -n --arg sourceDir "$scale_dir/migrations" --slurpfile units "$scale_units" '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: $sourceDir,
    unitKind: "table",
    strategy: {extractionMethod: "migration-sql", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 500, unresolvedCount: 0},
    units: $units
  }' > "$scale_manifest"

  local scale_err="$scale_dir/stderr.txt"
  if ! bash "$script_path" "$scale_manifest" "$scale_dir/migrations" "$scale_out" >/dev/null 2>"$scale_err"; then
    echo "  [FAIL] 1-127-scale: 500ユニット(同一ファイル共有)規模の抽出コマンドが完了しなかった" >&2
    rc=1
  else
    local scale_diag
    scale_diag="$(grep '^SCAN-DIAGNOSTIC:' "$scale_err" || true)"
    # 500ユニットが同一ファイルを共有するフィクスチャでは、字句除去(sql_code_only)がユニークな
    # ファイル数(=1)に比例して1回だけ走ることを検収する(検収方法1「単一走査で完了する」の直訳。
    # マシン依存でflakyなwall-clock時間ではなく走査回数そのものを assert する)。
    if printf '%s' "$scale_diag" | grep -q 'unique_files_lexically_scanned=1 units=500'; then
      echo "  [PASS] 1-127-scale: 500ユニット(同一ファイル共有)規模でも字句除去はユニークファイル数(1件)分だけ実行される単一走査 (${scale_diag})"
    else
      echo "  [FAIL] 1-127-scale: 単一走査になっていない (${scale_diag:-診断行が出力されなかった})" >&2
      rc=1
    fi
    if jq -e '
        (.units[] | select(.unitKey=="scale-table-1") | .columnCount == 2 and .foreignKeys == [])
        and (.units[] | select(.unitKey=="scale-table-2") | .columnCount == 3 and .foreignKeys == ["scale-table-1"])
        and (.units[] | select(.unitKey=="scale-table-500") | .columnCount == 3 and .foreignKeys == ["scale-table-499"])
      ' "$scale_out" >/dev/null 2>&1; then
      echo "  [PASS] 1-127-scale: 共有ファイルのキャッシュ経由でも各ユニットの抽出結果(columnCount/foreignKeys)が個々のCREATE TABLE定義と一致"
    else
      echo "  [FAIL] 1-127-scale: 共有ファイルキャッシュ経由の抽出結果が期待値と不一致" >&2
      rc=1
    fi
  fi

  # --- 改修課題「テーブル一覧-列数追随なし」: 後続マイグレーションの ADD COLUMN(1文中の
  #     複数列指定を含む)が columnCount/mainColumns へ反映されること ---
  local followup_dir="$tmp/followup"
  mkdir -p "$followup_dir/migrations"
  cat > "$followup_dir/migrations/001_create_widget.sql" <<'EOF'
CREATE TABLE widget (
  id BIGINT NOT NULL,
  name VARCHAR(100) NOT NULL,
  PRIMARY KEY (id)
);
EOF
  cat > "$followup_dir/migrations/002_add_widget_columns.sql" <<'EOF'
ALTER TABLE widget
  ADD COLUMN weight_scale REAL NOT NULL DEFAULT 1.0,
  ADD COLUMN weight_offset REAL NOT NULL DEFAULT 0.0;
ALTER TABLE widget ADD COLUMN IF NOT EXISTS in_catalog BOOLEAN NOT NULL DEFAULT FALSE;
EOF
  local followup_manifest="$followup_dir/table-manifest.json" followup_out="$followup_dir/out.json"
  jq -n --arg sourceDir "$followup_dir/migrations" --arg widgetFile "$followup_dir/migrations/001_create_widget.sql" '{
    generatedAt: "2026-01-01T00:00:00Z", sourceDir: $sourceDir, unitKind: "table",
    strategy: {extractionMethod: "migration-sql", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 1, unresolvedCount: 0},
    units: [{unitKey: "widget", kind: "table", identifier: "widget", unitNameGuess: "ウィジェット",
             sourceFile: $widgetFile, confidence: "high", fileCount: 1, detectionMethod: "create-table"}]
  }' > "$followup_manifest"
  if bash "$script_path" "$followup_manifest" "$followup_dir/migrations" "$followup_out" >/dev/null 2>&1 \
    && jq -e '.units[0]
      | .columnCount == 5
        and .mainColumns == ["id", "name", "weight_scale", "weight_offset", "in_catalog"]' "$followup_out" >/dev/null 2>&1; then
    echo "  [PASS] 列数追随: 別ファイルの後続ALTER TABLE(1文中の複数ADD COLUMN・別文のIF NOT EXISTS)がcolumnCount=5へ反映"
  else
    echo "  [FAIL] 列数追随: 後続マイグレーションのADD COLUMNがcolumnCountへ反映されていない" >&2
    jq -c '.units[0] | {columnCount, mainColumns}' "$followup_out" 2>/dev/null >&2 || true
    rc=1
  fi

  # --- 改修課題「テーブル一覧-外部キーの誤り」(片方向1: 実在するのに欠落): 後続マイグレーションで
  #     ADD COLUMN ... REFERENCES によって初めて追加されるFKも検出されること ---
  local fkadd_dir="$tmp/fkadd"
  mkdir -p "$fkadd_dir/migrations"
  cat > "$fkadd_dir/migrations/001_create_season_and_battle.sql" <<'EOF'
CREATE TABLE season_like (
  id BIGINT NOT NULL,
  label VARCHAR(100) NOT NULL,
  PRIMARY KEY (id)
);
CREATE TABLE battle_like (
  id BIGINT NOT NULL,
  our_team_id BIGINT NOT NULL,
  PRIMARY KEY (id)
);
EOF
  cat > "$fkadd_dir/migrations/002_add_season_id_to_battle.sql" <<'EOF'
ALTER TABLE battle_like
    ADD COLUMN IF NOT EXISTS season_id INTEGER REFERENCES season_like(id) ON DELETE SET NULL;
EOF
  local fkadd_manifest="$fkadd_dir/table-manifest.json" fkadd_out="$fkadd_dir/out.json"
  jq -n --arg sourceDir "$fkadd_dir/migrations" --arg schemaFile "$fkadd_dir/migrations/001_create_season_and_battle.sql" '{
    generatedAt: "2026-01-01T00:00:00Z", sourceDir: $sourceDir, unitKind: "table",
    strategy: {extractionMethod: "migration-sql", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 2, unresolvedCount: 0},
    units: [
      {unitKey: "season-like", kind: "table", identifier: "season_like", unitNameGuess: "期間",
       sourceFile: $schemaFile, confidence: "high", fileCount: 1, detectionMethod: "create-table"},
      {unitKey: "battle-like", kind: "table", identifier: "battle_like", unitNameGuess: "対戦",
       sourceFile: $schemaFile, confidence: "high", fileCount: 1, detectionMethod: "create-table"}
    ]
  }' > "$fkadd_manifest"
  if bash "$script_path" "$fkadd_manifest" "$fkadd_dir/migrations" "$fkadd_out" >/dev/null 2>&1 \
    && jq -e '.units[] | select(.unitKey=="battle-like")
      | .columnCount == 3
        and .mainColumns == ["id", "our_team_id", "season_id"]
        and .foreignKeys == ["season-like"]' "$fkadd_out" >/dev/null 2>&1; then
    echo "  [PASS] 外部キー追随(欠落側): 別ファイルのALTER ADD COLUMN...REFERENCESが検出されforeignKeysに反映"
  else
    echo "  [FAIL] 外部キー追随(欠落側): 後続マイグレーションで追加されたFK(season_id)が検出されていない" >&2
    jq -c '.units[] | select(.unitKey=="battle-like") | {columnCount, mainColumns, foreignKeys}' "$fkadd_out" 2>/dev/null >&2 || true
    rc=1
  fi

  # --- 改修課題「テーブル一覧-外部キーの誤り」(片方向2: 実在しないのに記録): DROP COLUMNで
  #     削除された列が持っていたFKは除去され、同じ参照先を持つ別の残存列のFKは維持されること ---
  local fkdrop_dir="$tmp/fkdrop"
  mkdir -p "$fkdrop_dir/migrations"
  cat > "$fkdrop_dir/migrations/001_create_loadout_like.sql" <<'EOF'
CREATE TABLE helper_like (
  id BIGINT NOT NULL,
  PRIMARY KEY (id)
);
CREATE TABLE supporter_like (
  id BIGINT NOT NULL,
  PRIMARY KEY (id)
);
CREATE TABLE loadout_like (
  id BIGINT NOT NULL,
  player_id BIGINT NOT NULL,
  helper_id BIGINT REFERENCES helper_like(id),
  enemy_helper_id BIGINT REFERENCES helper_like(id),
  supporter_id BIGINT REFERENCES supporter_like(id),
  PRIMARY KEY (id)
);
EOF
  cat > "$fkdrop_dir/migrations/002_drop_helper_id.sql" <<'EOF'
ALTER TABLE loadout_like DROP COLUMN helper_id;
ALTER TABLE loadout_like DROP COLUMN supporter_id;
EOF
  local fkdrop_manifest="$fkdrop_dir/table-manifest.json" fkdrop_out="$fkdrop_dir/out.json"
  jq -n --arg sourceDir "$fkdrop_dir/migrations" --arg schemaFile "$fkdrop_dir/migrations/001_create_loadout_like.sql" '{
    generatedAt: "2026-01-01T00:00:00Z", sourceDir: $sourceDir, unitKind: "table",
    strategy: {extractionMethod: "migration-sql", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 3, unresolvedCount: 0},
    units: [
      {unitKey: "helper-like", kind: "table", identifier: "helper_like", unitNameGuess: "補助",
       sourceFile: $schemaFile, confidence: "high", fileCount: 1, detectionMethod: "create-table"},
      {unitKey: "supporter-like", kind: "table", identifier: "supporter_like", unitNameGuess: "支援",
       sourceFile: $schemaFile, confidence: "high", fileCount: 1, detectionMethod: "create-table"},
      {unitKey: "loadout-like", kind: "table", identifier: "loadout_like", unitNameGuess: "編成",
       sourceFile: $schemaFile, confidence: "high", fileCount: 1, detectionMethod: "create-table"}
    ]
  }' > "$fkdrop_manifest"
  # supporter_like は supporter_id という唯一の参照元列がDROPされ、他に参照する列が無いため
  # foreignKeysから完全に消える(実在しないFKの記録=ゴーストFKの再現)。helper_likeは
  # enemy_helper_idが残るため維持される(実在するFKを落とさないことの再現)。両方向を
  # 1ケースで検証する。
  if bash "$script_path" "$fkdrop_manifest" "$fkdrop_dir/migrations" "$fkdrop_out" >/dev/null 2>&1 \
    && jq -e '.units[] | select(.unitKey=="loadout-like")
      | .columnCount == 3
        and .mainColumns == ["id", "player_id", "enemy_helper_id"]
        and .foreignKeys == ["helper-like"]' "$fkdrop_out" >/dev/null 2>&1; then
    echo "  [PASS] 外部キー追随(ゴースト側): DROP COLUMNで削除された列のFKは除去され(supporter-likeが消える)、同一参照先を持つ残存列(enemy_helper_id)のFKは維持(helper-likeが残る)"
  else
    echo "  [FAIL] 外部キー追随(ゴースト側): DROP COLUMN後もゴーストFKが残存、または残存列のFKまで消えた" >&2
    jq -c '.units[] | select(.unitKey=="loadout-like") | {columnCount, mainColumns, foreignKeys}' "$fkdrop_out" 2>/dev/null >&2 || true
    rc=1
  fi

  # --- 改修課題「テーブル一覧-列名の誤読」: 列名とREFERENCES句が別の行に分かれる記法
  #     (battle_assignment型)で、予約語REFERENCESが列名として取り込まれないこと ---
  local misread_dir="$tmp/misread"
  mkdir -p "$misread_dir/migrations"
  cat > "$misread_dir/migrations/001_create_assignment_like.sql" <<'EOF'
CREATE TABLE participant_like (
  id BIGINT NOT NULL,
  PRIMARY KEY (id)
);
CREATE TABLE assignment_like (
    id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    our_participant_id   BIGINT NOT NULL
                           REFERENCES participant_like(id) ON DELETE CASCADE,
    enemy_participant_id BIGINT NOT NULL
                           REFERENCES participant_like(id) ON DELETE CASCADE,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
EOF
  local misread_manifest="$misread_dir/table-manifest.json" misread_out="$misread_dir/out.json"
  jq -n --arg sourceDir "$misread_dir/migrations" --arg schemaFile "$misread_dir/migrations/001_create_assignment_like.sql" '{
    generatedAt: "2026-01-01T00:00:00Z", sourceDir: $sourceDir, unitKind: "table",
    strategy: {extractionMethod: "migration-sql", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 2, unresolvedCount: 0},
    units: [
      {unitKey: "participant-like", kind: "table", identifier: "participant_like", unitNameGuess: "参加者",
       sourceFile: $schemaFile, confidence: "high", fileCount: 1, detectionMethod: "create-table"},
      {unitKey: "assignment-like", kind: "table", identifier: "assignment_like", unitNameGuess: "割当",
       sourceFile: $schemaFile, confidence: "high", fileCount: 1, detectionMethod: "create-table"}
    ]
  }' > "$misread_manifest"
  if bash "$script_path" "$misread_manifest" "$misread_dir/migrations" "$misread_out" >/dev/null 2>&1 \
    && jq -e '.units[] | select(.unitKey=="assignment-like")
      | .columnCount == 4
        and .mainColumns == ["id", "our_participant_id", "enemy_participant_id", "created_at"]
        and (.mainColumns | index("references")) == null
        and .foreignKeys == ["participant-like"]' "$misread_out" >/dev/null 2>&1; then
    echo "  [PASS] 列名誤読なし: 列名とREFERENCES句が別行に分かれる記法でもREFERENCESを列名として取り込まずcolumnCount=4"
  else
    echo "  [FAIL] 列名誤読: REFERENCESが列名として混入、またはcolumnCount/foreignKeysが期待値と不一致" >&2
    jq -c '.units[] | select(.unitKey=="assignment-like") | {columnCount, mainColumns, foreignKeys}' "$misread_out" 2>/dev/null >&2 || true
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

TABLE_USAGE="Usage: extract-table-metadata.sh <table-manifest.json> <source-dir> <output.json> [--rules-file <json>]"
MANIFEST="${1:?$TABLE_USAGE}"
MIGRATIONS_DIR="${2:?$TABLE_USAGE}"
OUTPUT="${3:?$TABLE_USAGE}"
EXTRACTION_RULES_FILE=""
if [ "$#" -eq 5 ] && [ "${4:-}" = "--rules-file" ]; then
  EXTRACTION_RULES_FILE="${5:-}"
elif [ "$#" -gt 3 ]; then
  echo "ERROR: $TABLE_USAGE" >&2
  exit 1
fi

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

# --- 非UTF-8原本の走査対応(改善課題1-131): detect-encoding.sh の走査ヘルパーを読み込む ---
_EXTRACT_TABLE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../detect-encoding.sh
source "$_EXTRACT_TABLE_SCRIPT_DIR/../detect-encoding.sh"
SCAN_WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/extract-table-metadata-scan.XXXXXX")"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/extract-table-metadata.XXXXXX")"
trap 'rm -rf "$WORK" "$SCAN_WORKDIR"' EXIT

# --- sql_code_only のファイル単位キャッシュ(1-127) ---
# sql_code_only は文字単位の字句除去処理でファイルサイズに比例して重い。複数ユニットが
# 同一sourceFile(例: 全テーブルを1本のスキーマファイルにまとめた構成)を共有する場合、
# ユニットごとに再計算するとファイルサイズ×ユニット数に比例して実行時間が膨らむ。
# キーは解決済みパス文字列のハッシュ(ファイル内容は読まない・軽量)とし、1ユニークパスにつき
# 1回だけ sql_code_only(ファイル内容の読み取りと字句除去)を実行してキャッシュへ書き出す。
# 以降の同一ファイルを参照するユニットはキャッシュを読むだけで済ませる(ユニット数に比例した
# 字句除去走査を、ユニークなファイル数に比例した単一走査へ集約する)。
CODE_CACHE_DIR="$WORK/code-cache"
mkdir -p "$CODE_CACHE_DIR"
CODE_CACHE_SCAN_COUNT_FILE="$WORK/code-cache-scan-count.txt"
: > "$CODE_CACHE_SCAN_COUNT_FILE"
sql_code_only_cached() {
  local file="$1" key cache_file scan_file
  key="$(printf '%s' "$file" | shasum -a 256 | awk '{print $1}')"
  cache_file="$CODE_CACHE_DIR/$key"
  if [ ! -f "$cache_file" ]; then
    # scan_file: 非UTF-8原本ならUTF-8一時コピー(改善課題1-131)。file自体はキャッシュキー算出に
    # 使うため変更しない。字句除去(sql_code_only)には常にscan_fileを使う
    scan_file="$(to_utf8_for_scan "$file" "$SCAN_WORKDIR")"
    sql_code_only "$scan_file" > "$cache_file"
    printf '.' >> "$CODE_CACHE_SCAN_COUNT_FILE"
  fi
  cat "$cache_file"
}

# identifier(小文字) → unitKey の突合表(1-127: FK解決のたびにjqを起動しないよう、TSVへ1回だけ書き出し
# awkで引く。ユニット数に比例したjq起動を無くす)
LOOKUP_TSV="$WORK/lookup.tsv"
jq -r '.units[] | [(.identifier // "" | ascii_downcase), (.unitKey // "")] | @tsv' "$MANIFEST" \
  | awk -F'\t' 'NF==2 && $1 != "" && $2 != ""' > "$LOOKUP_TSV"
lookup_unit_key() {
  awk -F'\t' -v k="$1" '$1 == k { print $2; exit }' "$LOOKUP_TSV"
}

# 全ユニットの基本フィールドを1回のjqでTSV化(1-127: ユニットごとにunitKey/kind/identifier/
# sourceFileを個別jq呼び出しで取り出すと、ユニット数に比例してjqプロセス起動が膨らむ。
# 1回のjq呼び出しでTSVへ書き出し、以降はプレーンなbashの行読みだけで処理する)
UNITS_TSV="$WORK/units.tsv"
jq -r '.units[]? | [(.unitKey // ""), (.kind // ""), (.identifier // ""), (.sourceFile // "")] | @tsv' "$MANIFEST" \
  > "$UNITS_TSV"

# 全マイグレーションファイルを対象に ALTER TABLE 操作ログを1回だけ構築する(1-127と同じ判断:
# ユニット数に比例した再走査を避け、ファイル数に比例した単一走査へ集約する)。
ALTER_OPS_LOG="$WORK/alter-ops.tsv"
build_alter_ops_log "$MIGRATIONS_DIR" "$ALTER_OPS_LOG"

PATCHES="$WORK/patches.jsonl"
: > "$PATCHES"

while IFS=$'\t' read -r unit_key kind identifier source_file; do
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
  # CREATE TABLE ブロックが取れない場合、3 フィールドとも欠落として扱う(欄外コメント §1 参照)。
  [ -z "$block" ] && continue

  identifier_lc="$(lc "$identifier")"
  # ops_tsv へ一度書き出してから apply_column_ops へ渡す(パイプの終了ステータスは最後の
  # コマンドのものになるため、extract_create_table_ops が異常終了しても
  # `{ ... } | apply_column_ops` の全体は正常終了に見えてしまう。中間ファイル化して
  # 各段の終了コードを個別に検査する)。
  ops_tsv="$WORK/ops-$unit_key.tsv"
  : > "$ops_tsv"
  if ! printf '%s\n' "$block" | extract_create_table_ops >> "$ops_tsv"; then
    echo "ERROR: extract_create_table_ops failed for unitKey=$unit_key (identifier=$identifier)" >&2
    exit 1
  fi
  if ! awk -F'\t' -v tbl="$identifier_lc" '$1==tbl{print $2"\t"$3"\t"$4}' "$ALTER_OPS_LOG" >> "$ops_tsv"; then
    echo "ERROR: ALTER_OPS_LOG filter failed for unitKey=$unit_key (identifier=$identifier)" >&2
    exit 1
  fi
  if ! ops_result="$(apply_column_ops < "$ops_tsv")"; then
    echo "ERROR: apply_column_ops failed for unitKey=$unit_key (identifier=$identifier)" >&2
    exit 1
  fi
  rm -f "$ops_tsv"

  add='{}'
  col_count=""
  main_cols=()
  fk_phys=()
  while IFS=$'\t' read -r rtype rval; do
    case "$rtype" in
      COLCOUNT) col_count="$rval" ;;
      MAINCOL) main_cols+=("$rval") ;;
      FKTARGET) fk_phys+=("$rval") ;;
    esac
  done <<< "$ops_result"

  # columnCount / mainColumns(最終的なカラムが 1 件以上のときのみ付与)。
  # mainColumns は列名一覧をコマンドライン引数(--argjson)へ直接展開せず、
  # $WORK 配下の一時ファイル経由で --slurpfile として渡す。列数の多い表では
  # 引数1つあたりの上限(実測 131,071 バイト)を超えて `jq: Argument list too long`
  # で失敗しうるため(970a9cc99d45bcbe51c437f3c4623aecb98012d5 で一度導入され、
  # ac9c6df82e51e3dc641c6b9154b2909940e3e0fb の書き換えで regress し、
  # eff91aa06a71f89072b7b525710173406f0f8098 で再対策した)。
  # 引数長の上限はOSに依存し(macOSには無くLinuxにはある)、手元(macOS)で素直な形に
  # 戻しても再現しないため、手元で動くことを理由に一時ファイル経由をやめるな。
  if [ -n "$col_count" ] && [ "$col_count" -gt 0 ] 2>/dev/null; then
    main_cols_json='[]'
    if [ "${#main_cols[@]}" -gt 0 ]; then
      main_cols_json="$(printf '%s\n' "${main_cols[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')"
    fi
    main_cols_file="$WORK/main-cols.json"
    printf '%s' "$main_cols_json" > "$main_cols_file"
    add="$(jq -c --argjson n "$col_count" --slurpfile m "$main_cols_file" \
      '. + {columnCount: $n, mainColumns: $m[0]}' <<<"$add")"
  fi

  # foreignKeys(identifier 突合で unitKey へ解決できたものだけ。走査済みのため
  # 0 件でも [] を明示出力する。空配列=FK なし観測済み、欠落=走査不能。
  # DROP COLUMN で削除された列の参照先は apply_column_ops の時点で既に除外済み)
  fk_keys='[]'
  for target in "${fk_phys[@]}"; do
    [ -z "$target" ] && continue
    resolved="$(lookup_unit_key "$target")"
    [ -z "$resolved" ] && continue
    fk_keys="$(jq -c --arg k "$resolved" 'if index($k) then . else . + [$k] end' <<<"$fk_keys")"
  done
  add="$(jq -c --argjson f "$fk_keys" '. + {foreignKeys: $f}' <<<"$add")"

  if [ "$add" != "{}" ]; then
    jq -c --arg k "$unit_key" '{key: $k, value: .}' <<<"$add" >> "$PATCHES"
  fi
done < "$UNITS_TSV"

mkdir -p "$(dirname "$OUTPUT")"
jq --slurpfile patches "$PATCHES" '
  (reduce $patches[] as $patch ({}; .[$patch.key] = $patch.value)) as $patch_map
  | .units |= map(. + ($patch_map[.unitKey] // {}))
' "$MANIFEST" > "$OUTPUT"

echo "OK: wrote $OUTPUT" >&2
unit_count_diag="$(wc -l < "$UNITS_TSV" | tr -d ' ')"
scan_count_diag="$(wc -c < "$CODE_CACHE_SCAN_COUNT_FILE" | tr -d ' ')"
echo "SCAN-DIAGNOSTIC: unique_files_lexically_scanned=$scan_count_diag units=$unit_count_diag" >&2
bash "$_EXTRACT_TABLE_SCRIPT_DIR/finalize-extension-manifest.sh" "$MANIFEST" "$OUTPUT" --rules-file "$EXTRACTION_RULES_FILE" --rule 'foreignKeys|CREATE TABLE と FOREIGN KEY 制約' --rule 'columnCount|最終状態の列定義' --rule 'mainColumns|主キーまたは主要列の定義'
