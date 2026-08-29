#!/usr/bin/env bash
set -euo pipefail

# validate-rule-definitions.sh — docs/rules/ 配下の規約定義の整合性検査
#
# 設計の定義: delivery-payload/references/規約定義と派生生成の設計.md（3節・9節）
#
# 目的:
#   docs/rules/<親>/<子>/rule.md の front matter を読み、設計9節が定める7検査と
#   front matter 13鍵の必須・値域を検査する。1件でも不合格なら終了コード1で
#   不合格内容を標準エラーへ列挙する。
#
# 使い方:
#   validate-rule-definitions.sh <docs/rules のルート>
#   validate-rule-definitions.sh --self-test
#
# 検査キー（設計9節の7検査）:
#   鍵-対応整合     checkable:true なら checker が非null かつ実在。false なら
#                   uncheckableReason が非null かつ非空
#   検査-テスト同伴  checker があるなら <checkerのベース名>.test.sh が同フォルダに実在
#   適用範囲-必須   scope:scoped なら paths が非空の配列
#   階層-一致       parent が親フォルダ名、key が子フォルダ名と一致
#   矯正-矛盾なし   全rule.mdのformatter指定（none以外）が単一の値に揃っている
#   派生-未承認除外  status が draft/approved のいずれか（値域検査。除外自体はbuild側）
#   規則-検査列     '## 規則' 直後の表ヘッダが「規則・内容・検査」の3列、または
#                   「規則・内容・根拠・検査」の4列
#   検査-手段明示   '## 規則' の表の各行の検査列が手段（静的解析/テスト/レビュー/判定不能）で始まる
#
# 警告のみの検査（不合格でも終了コード0のまま通す）:
#   このプロジェクトの規則-存在  '## このプロジェクトの規則' の節が存在する。
#                               配布は rule.md を上書きしないため、既納品先には
#                               新しい節を持たない規約が残る。生成を止めると
#                               納品し直しただけで全件不合格になるため警告に留める。
#
# 終了コード:
#   0 = 全rule.mdが6検査とfront matter 13鍵の必須・値域を満たす
#   1 = 1件以上の不合格（内容は標準エラーへ列挙）
#   --self-test は上記に加え、期待どおりの検出ができなければ1
#
# 既知の制約:
#   YAMLパーサは使わない。front matterは "key: value" の1行表記のみ対応する。
#   配列（paths）は ["a", "b"] の1行表記のみ受け付け、複数行のブロック表記
#   （paths: のみ書いて次行以降に "- item" と続ける形）は不合格として明示的に報告する。
#   値に半角コロン+半角スペース（": "）を含む文字列は正しく分割できない（既知の限界）。
#
# 保守責任者: 人手（ユーザー）。front matterの鍵を増減する場合は本スクリプトの
#   EXPECTED_KEYS と delivery-payload/references/規約定義と派生生成の設計.md の3節を同時に更新する。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
TAXONOMY_JSON="${REPO_ROOT}/delivery-payload/references/rule-taxonomy.json"
CHECKERS_DIR="${REPO_ROOT}/delivery-payload/templates/rules/checkers"

EXPECTED_KEYS="key title parent summary scope paths enforcement checkable checker uncheckableReason formatter status origin workUnit"

FAILURES=""
FAIL_COUNT=0
WARNINGS=""
WARN_COUNT=0

add_failure() {
  # $1: file  $2: 検査キー  $3: 詳細
  FAILURES="${FAILURES}${1}: [${2}] ${3}
"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

add_warning() {
  # $1: file  $2: 検査キー  $3: 詳細
  # 警告は FAIL_COUNT を増やさない。終了コードにも影響しない。
  WARNINGS="${WARNINGS}${1}: [${2}] ${3}
"
  WARN_COUNT=$((WARN_COUNT + 1))
}

# 一時ファイルを作る。
#
# 実装判断: プロセス置換（<(...)）を diff・comm など外部コマンドの引数へ
# 渡すと /dev/fd/N が渡るが、実行環境によってはこれを開けない
# （実測 2026-08-24: diff: /dev/fd/11: Operation not permitted）。
# 比較そのものが失敗するため、失敗を「不合格」と読み違えると、中身に問題が
# 無いのに不合格を報告する。一時ファイルを経由してこの揺れを断つ。
#
# 置き場を明示するのは、引数なしの mktemp が既定の置き場へ書こうとして
# 失敗するためである（実測 2026-08-24:
# mktemp: mkstemp failed on /var/folders/.../T/tmp.XXXX: Operation not
# permitted）。TMPDIR を明示すると成功する。
# この形を素直な mktemp へ戻してはならない。手元で動いても環境が変われば
# 再び壊れる。
_mk_tmp() {
  mktemp "${TMPDIR:-/tmp}/$(basename "${BASH_SOURCE[0]}" .sh).XXXXXX" 2>/dev/null
}

# taxonomy が checker 本体を漏れなく宣言していることを検査する。
# parents[].children[] は配布する27規約、crossCuttingChecks[] は規約を横断して
# 顧客提示文書や作業指示書そのものを検査する補助的な宣言として分けて数える。
validate_checker_declarations() {
  local actual declared duplicates undeclared missing rc=0 _ta _tb mktemp_ok=1

  # 宣言データが無い環境では、宣言の網羅を判定する材料そのものが無い。
  # 配備先（対象プロジェクトの docs/rules/ 配下）へ配ったこのスクリプトは
  # delivery-payload を持たないため、この経路を必ず通る。
  # 材料が無いことを「値が不正」と報告すると、対象の欠陥と実行環境の不足を
  # 取り違える。宣言の検査だけを飛ばし、他の検査は続ける。
  # 判定不能の規約: .claude/rules/always/verification/indeterminate-result/rule.md
  if [ ! -f "$TAXONOMY_JSON" ]; then
    echo "[UNKNOWN] 宣言データが無いため checker の宣言を判定できません（参照したパス: ${TAXONOMY_JSON}。配備先には delivery-payload が無いため、この経路では宣言の検査を行いません）" >&2
    return 0
  fi

  if ! jq -e '
    (.crossCuttingChecks | type == "array") and
    (.crossCuttingChecks | all(
      (.key | type == "string" and length > 0) and
      (.title | type == "string" and length > 0) and
      (.rules | type == "array" and length > 0 and all(type == "string" and length > 0)) and
      (.checker | type == "string" and length > 0) and
      (.scope == "always" or .scope == "scoped") and
      (.paths | type == "array") and
      (.phases | type == "array" and length > 0)
    ))
  ' "$TAXONOMY_JSON" >/dev/null 2>&1; then
    echo "$TAXONOMY_JSON: [検査-宣言形式] crossCuttingChecks の必須項目または値域が不正" >&2
    return 1
  fi

  actual="$(find "$CHECKERS_DIR" -maxdepth 1 -type f -name 'check-*.sh' ! -name '*.test.sh' -exec basename {} \; | LC_ALL=C sort -u)"
  declared="$(jq -r '(.parents[].children[]), (.crossCuttingChecks[]?) | .checker // empty' "$TAXONOMY_JSON" | LC_ALL=C sort)"
  duplicates="$(printf '%s\n' "$declared" | LC_ALL=C uniq -d)"
  declared="$(printf '%s\n' "$declared" | LC_ALL=C sort -u)"

  if [ -n "$duplicates" ]; then
    echo "$TAXONOMY_JSON: [検査-宣言重複] 同じcheckerが複数回宣言されている: $(printf '%s' "$duplicates" | tr '\n' ' ')" >&2
    rc=1
  fi

  # undeclared/missing の突合は comm を一時ファイル経由で呼ぶ。プロセス置換
  # （<(...)）を渡すと実行環境によっては /dev/fd/N を開けず失敗し（実測
  # 2026-08-24: diff: /dev/fd/11: Operation not permitted）、この関数の
  # 呼び出し元（main の `|| exit 1`・self_test の `|| rc=1`）はどちらも
  # 「set -e が無効化される文脈」から呼ぶため、comm の失敗はシェルを
  # 止めずに空文字の undeclared/missing を返し、本来検出すべき欠落を
  # 「欠落なし」として見逃す。判定できない場合は、この関数の冒頭にある
  # 「宣言データが無い環境」と同じ扱い（[UNKNOWN] を出し、この検査だけを
  # 飛ばして呼び出し元の他の検査は続ける）に倣う。
  if ! _ta="$(_mk_tmp)" || [ -z "$_ta" ] || ! _tb="$(_mk_tmp)" || [ -z "$_tb" ]; then
    rm -f "${_ta:-}" "${_tb:-}"
    echo "[UNKNOWN] 一時ファイルを作れないためchecker宣言の欠落・実在を判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    mktemp_ok=0
  else
    printf '%s\n' "$actual" > "$_ta"
    printf '%s\n' "$declared" > "$_tb"
    undeclared="$(LC_ALL=C comm -23 "$_ta" "$_tb")"
    missing="$(LC_ALL=C comm -13 "$_ta" "$_tb")"
    rm -f "$_ta" "$_tb"

    if [ -n "$undeclared" ]; then
      echo "$TAXONOMY_JSON: [検査-宣言欠落] 宣言の無いchecker: $(printf '%s' "$undeclared" | tr '\n' ' ')" >&2
      rc=1
    fi
    if [ -n "$missing" ]; then
      echo "$TAXONOMY_JSON: [検査-実在] 宣言したcheckerが実在しない: $(printf '%s' "$missing" | tr '\n' ' ')" >&2
      rc=1
    fi
  fi

  if [ "$rc" -eq 0 ] && [ "$mktemp_ok" -eq 1 ]; then
    echo "検査宣言合格: $(printf '%s\n' "$actual" | grep -c . | tr -d ' ') 件のchecker本体を宣言済み"
  fi
  return "$rc"
}

# front matter本体（1行目と2行目の "---" に挟まれた範囲）を取り出す。
# 1行目が "---" でなければ空を返し、呼び出し側が不在として扱う。
fm_extract() {
  local file="$1"
  local first_line
  first_line="$(head -n1 "$file" 2>/dev/null || true)"
  if [ "$first_line" != "---" ]; then
    return 1
  fi
  awk 'NR==1{next} /^---$/{exit} {print}' "$file"
  return 0
}

# front matter本体からファイル末尾の "# <title>" 以降（本文）を取り出す。
body_extract() {
  local file="$1"
  awk 'BEGIN{c=0} /^---$/{c++; next} c>=2{print}' "$file"
}

# スカラー値（"key: value" 形式）を取り出す。無ければ空文字。
fm_get_scalar() {
  local body="$1" key="$2"
  printf '%s\n' "$body" | awk -v k="$key" '
    index($0, k ": ") == 1 { sub("^" k ": ", ""); print; exit }
    $0 == k ":" { print ""; exit }
  '
}

# key が front matter 本体に行として存在するかどうか（値が空でも存在扱い）。
fm_has_key() {
  local body="$1" key="$2"
  printf '%s\n' "$body" | grep -qE "^${key}:( |$)"
}

# 配列値（"key: [...]" の1行表記のみ対応）を取り出す。
# echo: 中身（角括弧含む）。戻り値: 0=取得成功 1=key不在 2=複数行ブロック表記（未対応）
fm_get_array() {
  local body="$1" key="$2"
  local line
  line="$(printf '%s\n' "$body" | grep -E "^${key}:" | head -n1 || true)"
  if [ -z "$line" ]; then
    return 1
  fi
  case "$line" in
    "${key}: ["*"]")
      printf '%s\n' "${line#"${key}: "}"
      return 0
      ;;
    *)
      return 2
      ;;
  esac
}

is_kebab() {
  printf '%s' "$1" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'
}

is_nonempty() {
  [ -n "$1" ]
}

# front matterに現れる全ての "先頭がidentifier:" のトップレベル鍵を抽出（重複含む）。
fm_all_key_lines() {
  local body="$1"
  printf '%s\n' "$body" | awk -F: '/^[A-Za-z0-9_]+:/{print $1}'
}

FORMATTER_VALUES=""  # ファイル横断でformatter値（none以外）を集める。 "file<TAB>value" 行

validate_one_rule() {
  local rule_file="$1"
  local child_dir parent_dir child_key_expected parent_key_expected
  child_dir="$(dirname "$rule_file")"
  parent_dir="$(dirname "$child_dir")"
  child_key_expected="$(basename "$child_dir")"
  parent_key_expected="$(basename "$parent_dir")"

  local body
  if ! body="$(fm_extract "$rule_file")"; then
    add_failure "$rule_file" "front-matter形式" "1行目が '---' ではないため front matter を認識できない"
    return
  fi

  # 鍵の過不足・重複検査
  local all_keys sorted_keys dup_keys key missing_keys extra_keys
  all_keys="$(fm_all_key_lines "$body")"
  dup_keys="$(printf '%s\n' "$all_keys" | sort | uniq -d || true)"
  if [ -n "$dup_keys" ]; then
    add_failure "$rule_file" "front-matter鍵-重複" "重複した鍵: $(printf '%s' "$dup_keys" | tr '\n' ' ')"
  fi
  missing_keys=""
  for key in $EXPECTED_KEYS; do
    if ! printf '%s\n' "$all_keys" | grep -qx "$key"; then
      missing_keys="${missing_keys}${key} "
    fi
  done
  if [ -n "$missing_keys" ]; then
    add_failure "$rule_file" "front-matter鍵-欠落" "必須14鍵のうち欠落: ${missing_keys}"
  fi
  extra_keys=""
  local ak
  for ak in $(printf '%s\n' "$all_keys" | sort -u); do
    local known=0
    for key in $EXPECTED_KEYS; do
      if [ "$ak" = "$key" ]; then
        known=1
        break
      fi
    done
    if [ "$known" -eq 0 ]; then
      extra_keys="${extra_keys}${ak} "
    fi
  done
  if [ -n "$extra_keys" ]; then
    add_failure "$rule_file" "front-matter鍵-未定義" "14鍵に無い未定義の鍵: ${extra_keys}"
  fi

  # スカラー値取得
  local v_key v_title v_parent v_summary v_scope v_enforcement v_checkable
  local v_checker v_uncheckable v_formatter v_status v_origin
  v_key="$(fm_get_scalar "$body" key)"
  v_title="$(fm_get_scalar "$body" title)"
  v_parent="$(fm_get_scalar "$body" parent)"
  v_summary="$(fm_get_scalar "$body" summary)"
  v_scope="$(fm_get_scalar "$body" scope)"
  v_enforcement="$(fm_get_scalar "$body" enforcement)"
  v_checkable="$(fm_get_scalar "$body" checkable)"
  v_checker="$(fm_get_scalar "$body" checker)"
  v_uncheckable="$(fm_get_scalar "$body" uncheckableReason)"
  v_formatter="$(fm_get_scalar "$body" formatter)"
  v_status="$(fm_get_scalar "$body" status)"
  v_origin="$(fm_get_scalar "$body" origin)"
  v_work_unit="$(fm_get_scalar "$body" workUnit)"

  # 値域検査（13鍵）
  if ! is_nonempty "$v_key" || ! is_kebab "$v_key"; then
    add_failure "$rule_file" "値域-key" "key はケバブケースの非空文字列である必要がある（値: '${v_key}'）"
  fi
  if ! is_nonempty "$v_title"; then
    add_failure "$rule_file" "値域-title" "title は非空である必要がある"
  fi
  if ! is_nonempty "$v_parent" || ! is_kebab "$v_parent"; then
    add_failure "$rule_file" "値域-parent" "parent はケバブケースの非空文字列である必要がある（値: '${v_parent}'）"
  fi
  if ! is_nonempty "$v_summary"; then
    add_failure "$rule_file" "値域-summary" "summary は非空である必要がある"
  fi
  case "$v_scope" in
    always|scoped) ;;
    *) add_failure "$rule_file" "値域-scope" "scope は always/scoped のいずれかである必要がある（値: '${v_scope}'）" ;;
  esac
  case "$v_enforcement" in
    advisory|none) ;;
    *) add_failure "$rule_file" "値域-enforcement" "enforcement は advisory/none のいずれかである必要がある（値: '${v_enforcement}'）" ;;
  esac
  case "$v_checkable" in
    true|false) ;;
    *) add_failure "$rule_file" "値域-checkable" "checkable は true/false のいずれかである必要がある（値: '${v_checkable}'）" ;;
  esac
  case "$v_formatter" in
    prettier|biome|editorconfig|none) ;;
    *) add_failure "$rule_file" "値域-formatter" "formatter は prettier/biome/editorconfig/none のいずれかである必要がある（値: '${v_formatter}'）" ;;
  esac
  case "$v_status" in
    draft|approved) ;;
    *) add_failure "$rule_file" "派生-未承認除外" "status は draft/approved のいずれかである必要がある（値: '${v_status}'）" ;;
  esac
  case "$v_origin" in
    template|proposal|manual) ;;
    *) add_failure "$rule_file" "値域-origin" "origin は template/proposal/manual のいずれかである必要がある（値: '${v_origin}'）" ;;
  esac
  # 改善課題1-281: 規約が対象とする作業の単位。file=ファイルの中身 / process=進め方 / artifact=成果物の形
  case "$v_work_unit" in
    file|process|artifact) ;;
    *) add_failure "$rule_file" "値域-workUnit" "workUnit は file/process/artifact のいずれかである必要がある（値: '${v_work_unit}'）" ;;
  esac

  # 鍵-対応整合（checkable と checker / uncheckableReason の対応）
  if [ "$v_checkable" = "true" ]; then
    if [ -z "$v_checker" ] || [ "$v_checker" = "null" ]; then
      add_failure "$rule_file" "鍵-対応整合" "checkable:true だが checker が null または未設定"
    else
      if [ ! -f "${child_dir}/${v_checker}" ]; then
        add_failure "$rule_file" "鍵-対応整合" "checker '${v_checker}' が同フォルダに実在しない"
      else
        # 検査-テスト同伴
        local checker_base test_file
        checker_base="${v_checker%.sh}"
        test_file="${child_dir}/${checker_base}.test.sh"
        if [ ! -f "$test_file" ]; then
          add_failure "$rule_file" "検査-テスト同伴" "checker '${v_checker}' に対応する回帰テスト '${checker_base}.test.sh' が同フォルダに実在しない"
        fi
      fi
    fi
    if [ -n "$v_uncheckable" ] && [ "$v_uncheckable" != "null" ]; then
      add_failure "$rule_file" "値域-uncheckableReason" "checkable:true のとき uncheckableReason は null である必要がある"
    fi
  elif [ "$v_checkable" = "false" ]; then
    if [ -z "$v_uncheckable" ] || [ "$v_uncheckable" = "null" ]; then
      add_failure "$rule_file" "鍵-対応整合" "checkable:false だが uncheckableReason が null または未設定"
    fi
    if [ -n "$v_checker" ] && [ "$v_checker" != "null" ]; then
      add_failure "$rule_file" "値域-checker" "checkable:false のとき checker は null である必要がある"
    fi
  fi

  # 適用範囲-必須（paths）
  local paths_raw paths_rc
  paths_rc=0
  paths_raw="$(fm_get_array "$body" paths)" || paths_rc=$?
  if [ "$paths_rc" -eq 1 ]; then
    add_failure "$rule_file" "適用範囲-必須" "paths 鍵が存在しない"
  elif [ "$paths_rc" -eq 2 ]; then
    add_failure "$rule_file" "front-matter配列形式" "paths が複数行のブロック表記であり未対応（[\"a\", \"b\"] の1行表記のみ対応）"
  else
    local paths_count
    paths_count="$(printf '%s' "$paths_raw" | jq 'length' 2>/dev/null || echo -1)"
    if [ "$paths_count" -lt 0 ]; then
      add_failure "$rule_file" "front-matter配列形式" "paths の値がJSON配列として解釈できない（値: ${paths_raw}）"
      paths_count=0
    fi
    if [ "$v_scope" = "scoped" ] && [ "$paths_count" -eq 0 ]; then
      add_failure "$rule_file" "適用範囲-必須" "scope:scoped だが paths が空配列"
    fi
  fi

  # 階層-一致
  if [ "$v_parent" != "$parent_key_expected" ]; then
    add_failure "$rule_file" "階層-一致" "front matter の parent '${v_parent}' が親フォルダ名 '${parent_key_expected}' と不一致"
  fi
  if [ "$v_key" != "$child_key_expected" ]; then
    add_failure "$rule_file" "階層-一致" "front matter の key '${v_key}' が子フォルダ名 '${child_key_expected}' と不一致"
  fi

  # 規則-検査列（根拠を別資料へ分ける3列と、従来の4列を受理する）
  local doc_body rule_table_header
  doc_body="$(body_extract "$rule_file")"
  rule_table_header="$(printf '%s\n' "$doc_body" | awk '
    /^## 規則/{found=1; next}
    found && /^\|/{print; exit}
  ')"
  if [ "$rule_table_header" != "| 規則 | 内容 | 検査 |" ] \
    && [ "$rule_table_header" != "| 規則 | 内容 | 根拠 | 検査 |" ]; then
    add_failure "$rule_file" "規則-検査列" "'## 規則' 直後の表ヘッダが規則・内容・検査の3列または規則・内容・根拠・検査の4列ではない（値: '${rule_table_header}'）"
  fi

  # 検査-手段明示（'## 規則' の表の各行の検査列が手段の接頭辞を持つこと）
  # 手段は 静的解析 / テスト / レビュー / 判定不能 の4つ。複数の手段を持つ行は
  # ' ／ ' で区切って並べるため、先頭の手段だけを見れば書式の判定になる。
  # '## このプロジェクトの規則' は対象外。リバース解析を実行するまでは
  # 「観測なし」の行しか置けず、その検査列は手段の接頭辞を持たないため。
  # LC_ALL=C: headやcellの比較・整形は日本語（多バイト）値を扱う。デフォルトロケールの
  # macOS標準awk（BSD awk）は多バイト文字列の等値比較を誤判定し、両辺が日本語だと
  # 比較が常に真になる不具合があるため、バイト単位の比較へ固定して回避する
  # （コミット eae9816d6f4a735a8881a592dab58db993b4f566 で本行を含む5箇所の
  # LC_ALL=C指定漏れが実際に発見・修正された。手元で問題が再現しないことを理由に外すな）。
  local unlabeled_cells
  unlabeled_cells="$(printf '%s\n' "$doc_body" | LC_ALL=C awk -F'|' '
    /^## 規則$/{in_rule=1; next}
    in_rule && /^## /{exit}
    in_rule && /^\|/{
      seen_table=1
      if ($0 ~ /^\|[-| ]+$/) next
      head=$2; gsub(/^[ \t]+|[ \t]+$/, "", head)
      if (head == "規則") {
        header_count++
        if (header_count >= 2) exit
        next
      }
      cell=$(NF-1); gsub(/^[ \t]+|[ \t]+$/, "", cell)
      if (cell !~ /^(静的解析|テスト|レビュー|判定不能):/) print cell
      next
    }
    in_rule && seen_table && NF && $0 !~ /^[ \t]*$/{exit}
  ')"
  if [ -n "$unlabeled_cells" ]; then
    add_failure "$rule_file" "検査-手段明示" "'## 規則' の表に検査の手段が明示されていない行がある。検査列は 静的解析: / テスト: / レビュー: / 判定不能: のいずれかで始める"
  fi

  # このプロジェクトの規則-存在（警告のみ。生成を止めない）
  if ! printf '%s\n' "$doc_body" | grep -q '^## このプロジェクトの規則$'; then
    add_warning "$rule_file" "このプロジェクトの規則-存在" "'## このプロジェクトの規則' の節が無い。リバース解析が起こした規則の置き場が存在しない"
  fi

  # 矯正-矛盾なし の材料収集（none は対象外）
  if [ -n "$v_formatter" ] && [ "$v_formatter" != "none" ]; then
    FORMATTER_VALUES="${FORMATTER_VALUES}${rule_file}	${v_formatter}
"
  fi
}

# 親宣言-実在: 各親フォルダに parent.yml が実在し、key がフォルダ名と一致し、
# title が非空であることを検査する。ルート直下の各サブディレクトリを親フォルダとみなす。
validate_parent_declarations() {
  local root="$1"
  local parent_dirs
  parent_dirs="$(find "$root" -mindepth 1 -maxdepth 1 -type d | sort)"

  local pdir
  while IFS= read -r pdir; do
    [ -n "$pdir" ] || continue
    local parent_key_expected parent_yml
    parent_key_expected="$(basename "$pdir")"
    if [ "$parent_key_expected" = "tooling" ]; then
      continue
    fi
    parent_yml="${pdir}/parent.yml"

    if [ ! -f "$parent_yml" ]; then
      add_failure "$parent_yml" "親宣言-実在" "親フォルダ '${parent_key_expected}' に parent.yml が実在しない"
      continue
    fi

    local pbody pkey ptitle
    pbody="$(cat "$parent_yml")"
    pkey="$(fm_get_scalar "$pbody" key)"
    ptitle="$(fm_get_scalar "$pbody" title)"

    if [ "$pkey" != "$parent_key_expected" ]; then
      add_failure "$parent_yml" "親宣言-実在" "parent.yml の key '${pkey}' が親フォルダ名 '${parent_key_expected}' と不一致"
    fi
    if ! is_nonempty "$ptitle"; then
      add_failure "$parent_yml" "親宣言-実在" "parent.yml の title が非空である必要がある"
    fi
  done <<EOF
$parent_dirs
EOF
}

# 矯正-矛盾なし: 全rule.md横断で、none以外のformatter値が複数種類あれば矛盾とする。
# 根拠: 設計7節「Prettier・Biome・.editorconfigのいずれも、1つのプロジェクトに
#   1つしか設定ファイルを置けない」。front matterにはformatterという1鍵しか
#   矯正設定を表す情報がないため、この鍵の値そのものを「同じ設定項目」として扱う。
check_formatter_conflict() {
  local distinct
  distinct="$(printf '%s' "$FORMATTER_VALUES" | awk -F'\t' 'NF{print $2}' | sort -u)"
  local distinct_count
  distinct_count="$(printf '%s' "$distinct" | grep -c . || true)"
  if [ "$distinct_count" -gt 1 ]; then
    local detail
    detail="$(printf '%s' "$FORMATTER_VALUES" | awk -F'\t' 'NF{printf "%s=%s ", $1, $2}')"
    add_failure "(横断検査)" "矯正-矛盾なし" "formatter指定が複数種類ある（1プロジェクトに1つしか設定ファイルを置けない）: ${detail}"
  fi
}

# 引数が docs/rules を指していないと疑われる場合（渡されたディレクトリの直下に
# parent.yml を持たないフォルダが1つでもある場合）に使い方を標準エラーへ出す。
# 誤検出で止めるのではなく、通常の検査はそのまま続ける（呼び出し元がexitしない）。
check_rules_root_hint() {
  local root="$1"
  local subdir suspect
  suspect=0
  for subdir in "$root"/*/; do
    [ -d "$subdir" ] || continue
    if [ "$(basename "$subdir")" = "tooling" ]; then
      continue
    fi
    if [ ! -f "${subdir}parent.yml" ]; then
      suspect=1
      break
    fi
  done
  if [ "$suspect" -eq 1 ]; then
    echo "使い方: $(basename "$0") <docs/rules のルート>" >&2
    echo "渡されたディレクトリの直下に parent.yml を持たないフォルダがあります。" >&2
    echo "リポジトリルートではなく docs/rules を指してください。" >&2
  fi
}

run_validate() {
  local root="$1"
  FAILURES=""
  FAIL_COUNT=0
  WARNINGS=""
  WARN_COUNT=0
  FORMATTER_VALUES=""

  if [ ! -d "$root" ]; then
    echo "ERROR: ルートディレクトリが存在しません: $root" >&2
    return 1
  fi

  local rule_files
  rule_files="$(find "$root" -type f -name 'rule.md' | sort)"
  if [ -z "$rule_files" ]; then
    echo "ERROR: rule.md が1件も見つかりません: $root" >&2
    return 1
  fi

  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    validate_one_rule "$f"
  done <<EOF
$rule_files
EOF

  check_formatter_conflict
  validate_parent_declarations "$root"

  if [ "$WARN_COUNT" -gt 0 ]; then
    echo "検査注意: ${WARN_COUNT} 件（生成は止めない）" >&2
    printf '%s' "$WARNINGS" >&2
  fi

  if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "検査不合格: ${FAIL_COUNT} 件" >&2
    printf '%s' "$FAILURES" >&2
    return 1
  fi

  echo "検査合格: $(printf '%s\n' "$rule_files" | grep -c .) 件の rule.md が全検査に合格"
  return 0
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

st_write_valid_pair() {
  # $1: ルートディレクトリ
  local root="$1"
  mkdir -p "${root}/agent-operations/ai-behavior"
  mkdir -p "${root}/code-standards/naming"

  cat > "${root}/agent-operations/parent.yml" <<'EOF'
key: agent-operations
title: AIエージェント運用
EOF

  cat > "${root}/code-standards/parent.yml" <<'EOF'
key: code-standards
title: コード規約
EOF

  cat > "${root}/agent-operations/ai-behavior/rule.md" <<'EOF'
---
key: ai-behavior
title: AIエージェント行動規約
parent: agent-operations
summary: AIエージェントへの作業委任の取り決め。
scope: always
paths: ["**/*"]
enforcement: advisory
checkable: false
checker: null
uncheckableReason: 行動の是非は静的解析では判定できない。
formatter: none
status: approved
origin: proposal
workUnit: file
---

# AIエージェント行動規約

## 概要

テスト用の概要。

## 規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 例 | 例 | 例 | 静的解析: 例 |

## このプロジェクトの規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 観測なし | 例 | 例 | 例 |

## 違反時の手順

1. 例
EOF

  cat > "${root}/code-standards/naming/rule.md" <<'EOF'
---
key: naming
title: 命名規約
parent: code-standards
summary: 変数・クラスの命名パターン。
scope: scoped
paths: ["src/**/*.ts"]
enforcement: advisory
checkable: true
checker: check-naming.sh
uncheckableReason: null
formatter: none
status: approved
origin: proposal
workUnit: file
---

# 命名規約

## 概要

テスト用の概要。

## 規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 例 | 例 | 例 | 静的解析: 例 |

## このプロジェクトの規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 観測なし | 例 | 例 | 例 |

## 違反時の手順

1. 例
EOF

  cat > "${root}/code-standards/naming/check-naming.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "${root}/code-standards/naming/check-naming.test.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${root}/code-standards/naming/check-naming.sh" "${root}/code-standards/naming/check-naming.test.sh"
}

st_case() {
  # $1: ケース名  $2: 期待exitコード  $3: 期待する検査キー(grep用。空なら未チェック)
  local name="$1" expected_rc="$2" expect_key="$3"
  local tmp
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/validate-rule-definitions-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  st_write_valid_pair "$tmp"

  case "$name" in
    pass) : ;;
    pass-three-columns)
      sed -i.bak 's/^| 規則 | 内容 | 根拠 | 検査 |$/| 規則 | 内容 | 検査 |/; s/^|---|---|---|---|$/|---|---|---|/; s/^| 例 | 例 | 例 | 静的解析: 例 |$/| 例 | 例 | 静的解析: 例 |/' "${tmp}/code-standards/naming/rule.md"
      rm -f "${tmp}/code-standards/naming/rule.md.bak"
      ;;
    key-consistency)
      sed -i.bak 's/^checker: check-naming.sh$/checker: null/' "${tmp}/code-standards/naming/rule.md"
      rm -f "${tmp}/code-standards/naming/rule.md.bak"
      ;;
    test-companion)
      rm -f "${tmp}/code-standards/naming/check-naming.test.sh"
      ;;
    scope-paths)
      sed -i.bak 's/^paths: \["src\/\*\*\/\*.ts"\]$/paths: []/' "${tmp}/code-standards/naming/rule.md"
      rm -f "${tmp}/code-standards/naming/rule.md.bak"
      ;;
    hierarchy)
      sed -i.bak 's/^parent: code-standards$/parent: wrong-parent/' "${tmp}/code-standards/naming/rule.md"
      rm -f "${tmp}/code-standards/naming/rule.md.bak"
      ;;
    formatter-conflict)
      sed -i.bak 's/^formatter: none$/formatter: prettier/' "${tmp}/agent-operations/ai-behavior/rule.md"
      rm -f "${tmp}/agent-operations/ai-behavior/rule.md.bak"
      sed -i.bak 's/^formatter: none$/formatter: biome/' "${tmp}/code-standards/naming/rule.md"
      rm -f "${tmp}/code-standards/naming/rule.md.bak"
      ;;
    status-domain)
      sed -i.bak 's/^status: approved$/status: pending/' "${tmp}/code-standards/naming/rule.md"
      rm -f "${tmp}/code-standards/naming/rule.md.bak"
      ;;
    parent-missing)
      rm -f "${tmp}/agent-operations/parent.yml"
      ;;
    parent-key-mismatch)
      sed -i.bak 's/^key: agent-operations$/key: wrong-key/' "${tmp}/agent-operations/parent.yml"
      rm -f "${tmp}/agent-operations/parent.yml.bak"
      ;;
    rule-table-columns)
      sed -i.bak 's/^| 規則 | 内容 | 根拠 | 検査 |$/| 規則 | 内容 |/' "${tmp}/code-standards/naming/rule.md"
      rm -f "${tmp}/code-standards/naming/rule.md.bak"
      ;;
    project-section-missing)
      # 見出し行だけを消す。表は残るが、検査は見出しの有無だけを見る
      sed -i.bak '/^## このプロジェクトの規則$/d' "${tmp}/code-standards/naming/rule.md"
      rm -f "${tmp}/code-standards/naming/rule.md.bak"
      ;;
    rule-check-unlabeled)
      # '## 規則' の表の検査列から手段の接頭辞を外す。生成を止める側の検査
      sed -i.bak 's/^| 例 | 例 | 例 | 静的解析: 例 |$/| 例 | 例 | 例 | 例を走査する |/' "${tmp}/code-standards/naming/rule.md"
      rm -f "${tmp}/code-standards/naming/rule.md.bak"
      ;;
    project-check-unlabeled-allowed)
      # '## このプロジェクトの規則' の表は手段の接頭辞を持たなくても通る
      sed -i.bak 's/^| 観測なし | 例 | 例 | 例 |$/| 観測なし | 例 | 例 | 観測の有無は解析の実行結果に依存する |/' "${tmp}/code-standards/naming/rule.md"
      rm -f "${tmp}/code-standards/naming/rule.md.bak"
      ;;
  esac

  local out rc
  out="$(run_validate "$tmp" 2>&1)"
  rc=$?
  rm -rf "$tmp"

  if [ "$rc" -ne "$expected_rc" ]; then
    echo "  [FAIL] ${name}: 終了コードが不正 (実際=${rc}, 期待=${expected_rc})" >&2
    echo "$out" | sed 's/^/    /' >&2
    return 1
  fi
  if [ -n "$expect_key" ] && ! printf '%s' "$out" | grep -q "\[${expect_key}\]"; then
    echo "  [FAIL] ${name}: 期待した検査キー '[${expect_key}]' が出力に含まれない" >&2
    echo "$out" | sed 's/^/    /' >&2
    return 1
  fi
  echo "  [PASS] ${name}"
  return 0
}

self_test() {
  local rc=0
  validate_checker_declarations || rc=1
  st_case "pass" 0 "" || rc=1
  st_case "pass-three-columns" 0 "" || rc=1
  st_case "key-consistency" 1 "鍵-対応整合" || rc=1
  st_case "test-companion" 1 "検査-テスト同伴" || rc=1
  st_case "scope-paths" 1 "適用範囲-必須" || rc=1
  st_case "hierarchy" 1 "階層-一致" || rc=1
  st_case "formatter-conflict" 1 "矯正-矛盾なし" || rc=1
  st_case "status-domain" 1 "派生-未承認除外" || rc=1
  st_case "parent-missing" 1 "親宣言-実在" || rc=1
  st_case "parent-key-mismatch" 1 "親宣言-実在" || rc=1
  st_case "rule-table-columns" 1 "規則-検査列" || rc=1
  # 警告のみの検査。終了コードは0のまま、検査キーが出力へ現れることを確かめる
  st_case "project-section-missing" 0 "このプロジェクトの規則-存在" || rc=1
  st_case "rule-check-unlabeled" 1 "検査-手段明示" || rc=1
  # '## このプロジェクトの規則' の検査列が手段を持たなくても通ることを確かめる
  st_case "project-check-unlabeled-allowed" 0 "" || rc=1

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi
  if [ "$#" -gt 1 ]; then
    echo "使い方: $(basename "$0") <docs/rules のルート>" >&2
    echo "        $(basename "$0") --self-test" >&2
    exit 1
  fi
  local rules_root="${1:-${REPO_ROOT}/generation-engine/samples/docs/rules}"
  validate_checker_declarations || exit 1
  check_rules_root_hint "$rules_root"
  run_validate "$rules_root"
  exit $?
}

# 直接実行時のみdispatchする（build-derived-rules.shがsourceしてrun_validate等の
# 関数を再利用できるよう、source時は呼び出し元の位置引数を誤読しない）
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main "$@"
fi
