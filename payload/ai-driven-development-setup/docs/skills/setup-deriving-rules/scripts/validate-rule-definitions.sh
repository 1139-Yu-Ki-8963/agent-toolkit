#!/usr/bin/env bash
set -euo pipefail

# validate-rule-definitions.sh — docs/rules/ 配下の規約定義の整合性検査
#
# 設計の定義: docs/skills/setup-deriving-rules/references/規約定義と派生生成の設計.md（3節・9節）
#
# 目的:
#   docs/rules/<親>/<子>/rule.md の front matter を読み、設計9節が定める7検査と
#   front matter 必須14鍵・任意鍵（docType・derivedPath）の値域を検査する。1件でも
#   不合格なら終了コード1で不合格内容を標準エラーへ列挙する。
#
# 使い方:
#   validate-rule-definitions.sh <docs/rules のルート> [--taxonomy <分類定義のパス>]
#   validate-rule-definitions.sh --self-test
#
# --taxonomy は任意。指定した場合だけ checker 宣言の網羅（宣言-重複・宣言-欠落・実在）を
# 検査する。指定しない場合はこの検査だけを [SKIP] で飛ばし、他の検査は続ける。
#
# 検査キー（設計9節の7検査）:
#   鍵-対応整合     checkable:true なら checker が非null かつ実在。false なら
#                   uncheckableReason が非null かつ非空
#   検査-テスト同伴  checker があるなら <checkerのベース名>.test.sh が同フォルダに実在
#   checker-専有    checkerを宣言する規約のフォルダに、宣言外のcheck-*.shが無い
#   checker-一意    同じcheckerを複数の規約が宣言していない（規約と検査の1対1）
#   適用範囲-必須   scope:scoped なら paths が非空の配列
#   階層-一致       parent が親フォルダ名、key が子フォルダ名と一致
#   矯正-矛盾なし   全rule.mdのformatter指定（none以外）が単一の値に揃っている
#   派生-未承認除外  status が draft/approved のいずれか（値域検査。除外自体はbuild側）
#   規則-検査列     '## 規則' 直後の表ヘッダが「規則・内容・検査」の3列、または
#                   「規則・内容・根拠・検査」の4列（docType: context は対象外）
#   検査-手段明示   '## 規則' の表の各行の検査列が手段（静的解析/テスト/レビュー/判定不能）で始まる
#                   （docType: context は対象外）
#
# 任意鍵（docType・derivedPath）の検査:
#   値域-docType     docType は rule/context のいずれか（未指定は rule 扱い）
#   docType-制約     docType: context の規約は checkable: false でなければならない
#   値域-derivedPath  derivedPath は指定するなら '.claude/rules/' で始まり '..' を含まない
#   派生先-重複      derivedPath が複数の規約で重複していない
#
# 警告のみの検査（不合格でも終了コード0のまま通す）:
#   このプロジェクトの規則-存在  '## このプロジェクトの規則' の節が存在する
#                               （docType: context は対象外）。配布は rule.md を
#                               上書きしないため、既納品先には新しい節を持たない
#                               規約が残る。生成を止めると納品し直しただけで
#                               全件不合格になるため警告に留める。
#
# 終了コード:
#   0 = 全rule.mdが7検査とfront matter 必須14鍵・任意鍵の値域を満たす
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
#   EXPECTED_KEYS と docs/skills/setup-deriving-rules/references/規約定義と派生生成の設計.md の3節を同時に更新する。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。

# パス解決は引数（docs/rules のルート・--taxonomy）と、各規約自身のフォルダ
# だけに限る。SCRIPT_DIR から固定の相対段数でリポジトリルートを算出する形は
# 取らない。本スクリプトの配置階層は納品先ごとに異なりうり、固定の上昇段数に
# 依存すると配置が変わるたびに誤ったパスを指す（実測: 旧リポジトリでは
# generation-engine/scripts/rules/ から3階層でリポジトリルートに届いたが、
# 新リポジトリの置き場 docs/skills/setup-deriving-rules/scripts/ は4階層深く、
# 同じ段数の算出が docs/ 配下の誤ったパスを指した）。

EXPECTED_KEYS="key title parent summary scope paths enforcement checkable checker uncheckableReason formatter status origin workUnit"
# docType・derivedPath は任意鍵。必須14鍵には含めないが、front-matter鍵-未定義の
# 対象にもしない。
OPTIONAL_KEYS="docType derivedPath"

# --deploy-rule-scripts（build-derived-rules.sh）が
# docs/rules/agent-operations/ai-config-asset-management/ へ配る派生のスクリプト4本。
# いずれもtaxonomyのcheckerとして宣言されない診断ツールだが、このうち
# check-rule-drift.shは検査本体の命名規則（check-*.sh）に一致するため、
# 何も除かないとvalidate_checker_declarationsが「宣言の無いchecker」として
# 誤検出する（実践で見つかった不具合: ai-work/records/2026-09-04-体系の再設計の経緯と不具合.md
# 「実践で見つかった欠点と不具合」）。4本まとめて除くのは、将来の改名や
# 追加時に同じ命名規則へ一致する可能性を個別に判断せずに済ませるため。
DEPLOYED_TOOL_NAMES="build-derived-rules.sh validate-rule-definitions.sh check-rule-drift.sh resolve-applicable-rules.sh"

# 派生のスクリプト4本が実際に配備される先は
# docs/rules/agent-operations/ai-config-asset-management/ の直下だけである。
# 除外を basename の一致だけで判定すると、無関係な規約フォルダへ
# 誤って複製・混入した同名ファイルまで除外してしまい、checker-専有・
# 宣言網羅の検査が機能しなくなる（実践で見つかった不具合）。配備先フォルダに
# 実在する場合だけ除外するため、親フォルダ名・子フォルダ名もあわせて固定する。
DEPLOYED_TOOL_DIR_PARENT="agent-operations"
DEPLOYED_TOOL_DIR_KEY="ai-config-asset-management"

# $1（basename）がDEPLOYED_TOOL_NAMESのいずれかと一致するかを判定する。
is_deployed_tool_name() {
  local name="$1" candidate
  for candidate in $DEPLOYED_TOOL_NAMES; do
    [ "$name" = "$candidate" ] && return 0
  done
  return 1
}

# $1（規約フォルダのパス。docs/rules/<親>/<子>）が派生のスクリプト4本の配備先
# （agent-operations/ai-config-asset-management/）と一致するかを判定する。
# checker-専有（同フォルダの宣言外check-*.sh検出）が、
# --deploy-rule-scriptsの配備先に混在するcheck-rule-drift.shだけを除外し、
# 他の規約フォルダへの混入は除外しないために使う。
is_deployed_tool_dir() {
  local dir="$1"
  [ "$(basename "$dir")" = "$DEPLOYED_TOOL_DIR_KEY" ] || return 1
  [ "$(basename "$(dirname "$dir")")" = "$DEPLOYED_TOOL_DIR_PARENT" ]
}

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
# $1: docs/rules のルート  $2: 分類定義ファイルのパス（--taxonomy。空なら検査を飛ばす）
# parents[].children[] が配布する規約すべての宣言である。
#
# 「実在しない」（検査-実在）の判定は、docs/rules/<親>/<子> が実在する
# （＝配置済みの）子カテゴリの宣言だけを対象にする。規約は分類定義の32件を
# 選んで docs/rules へ配置する運用であり、未配置の子は「実在しない」の
# 不具合ではなく単に「まだ配置していない」だけであるため、対象から外し
# [SKIP] 件数として報告する。「宣言欠落」（実在するのに宣言が無い）は
# 配置の有無に関わらず従来どおり検査する。
validate_checker_declarations() {
  local root="$1" taxonomy="${2:-}"
  local actual declared duplicates undeclared missing rc=0 _ta _tb mktemp_ok=1

  # 分類定義（--taxonomy）は任意である。指定が無い環境（このリポジトリ自身を
  # 含め、分類定義をまだ持たない docs/rules/ 配下）では、宣言の網羅を判定する
  # 材料そのものが無い。材料が無いことを「値が不正」と報告すると、対象の欠陥と
  # 入力の不足を取り違える。宣言の検査だけを飛ばし、他の検査は続ける。
  if [ -z "$taxonomy" ]; then
    echo "[SKIP] 分類定義が指定されていないため checker の宣言を判定しません（--taxonomy 未指定）"
    return 0
  fi

  # 判定不能の規約: .claude/rules/always/verification/indeterminate-result/rule.md
  if [ ! -f "$taxonomy" ]; then
    echo "[UNKNOWN] 宣言データが無いため checker の宣言を判定できません（参照したパス: ${taxonomy}）" >&2
    return 0
  fi

  # checker は各規約自身のフォルダ（docs/rules/<親>/<子>/check-<子>.sh）に置く。
  # 旧の単一ディレクトリ集約（delivery-payload/templates/rules/checkers/）は
  # 前提にせず、docs/rules のルート配下を深さ3（<親>/<子>/check-*.sh）で走査する。
  # --deploy-rule-scriptsが配る派生のスクリプト4本（DEPLOYED_TOOL_NAMES）は、
  # taxonomyに宣言されない配備物（診断ツール）であり、規約自身のcheckerとは
  # 別物のため、宣言網羅の対象から除く。ただし除外は basename の一致だけでは
  # 行わない。basename が一致していても、配備先（is_deployed_tool_dir）以外の
  # フォルダに存在するものは、無関係な規約フォルダへの混入として従来どおり
  # 検出する（実践で見つかった不具合: 除外を名前だけで判定すると、この混入を
  # 見逃していた）。プロセス置換は使わない（実測: 実行環境によっては
  # /dev/fd/N を開けず失敗する。同事情は本ファイル冒頭の_mk_tmpのコメントを
  # 参照）。
  local -a raw_paths=()
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    raw_paths+=("$f")
  done <<FINDEOF
$(find "$root" -mindepth 3 -maxdepth 3 -type f -name 'check-*.sh' ! -name '*.test.sh')
FINDEOF
  local actual_lines="" base
  for f in "${raw_paths[@]}"; do
    base="$(basename "$f")"
    if is_deployed_tool_name "$base" && is_deployed_tool_dir "$(dirname "$f")"; then
      continue
    fi
    actual_lines="${actual_lines}${base}
"
  done
  actual="$(printf '%s' "$actual_lines" | LC_ALL=C sort -u)"
  declared="$(jq -r '.parents[].children[] | .checker // empty' "$taxonomy" | LC_ALL=C sort)"
  duplicates="$(printf '%s\n' "$declared" | LC_ALL=C uniq -d)"
  declared="$(printf '%s\n' "$declared" | LC_ALL=C sort -u)"

  # 分類定義に無い自身の規約（taxonomyの32子カテゴリの外にある、対象
  # リポジトリ自身のためのrule.md）は、front matterの checker: 宣言でも
  # 宣言済みとして扱う（和集合）。分類定義に無い自身の規約は front matter
  # の宣言で足りる。走査は checker本体と同じ深さ（<root>/<親>/<子>/rule.md）。
  local fm_declared="" f_fm fm_body_fm fm_checker_fm
  while IFS= read -r f_fm; do
    [ -n "$f_fm" ] || continue
    fm_body_fm="$(fm_extract "$f_fm" || true)"
    fm_checker_fm="$(fm_get_scalar "$fm_body_fm" checker)"
    if [ -n "$fm_checker_fm" ] && [ "$fm_checker_fm" != "null" ]; then
      fm_declared="${fm_declared}${fm_checker_fm}
"
    fi
  done <<FINDEOF
$(find "$root" -mindepth 3 -maxdepth 3 -type f -name 'rule.md')
FINDEOF
  declared="$(printf '%s\n%s' "$declared" "$fm_declared" | LC_ALL=C sort -u)"

  # 「実在しない」（検査-実在）の判定材料は、taxonomy 全体ではなく配置済みの
  # 子カテゴリだけに絞る。docs/rules/<親>/<子> が実在しない子は、まだ選んで
  # 配置していないだけであり、「宣言したcheckerが実在しない」の不合格には
  # しない。件数だけ [SKIP] で報告する。
  local declared_placed="" skip_count=0 p_key c_key c_checker
  while IFS=$'\t' read -r p_key c_key c_checker; do
    [ -n "$c_checker" ] || continue
    if [ -d "${root}/${p_key}/${c_key}" ]; then
      declared_placed="${declared_placed}${c_checker}
"
    else
      skip_count=$((skip_count + 1))
    fi
  done <<FINDEOF
$(jq -r '.parents[] | .key as $p | .children[] | select(.checker) | [$p, .key, .checker] | @tsv' "$taxonomy")
FINDEOF
  declared_placed="$(printf '%s\n%s' "$declared_placed" "$fm_declared" | LC_ALL=C sort -u)"
  if [ "$skip_count" -gt 0 ]; then
    echo "[SKIP] 配置していないため実在の判定から除外したchecker宣言: ${skip_count} 件"
  fi

  if [ -n "$duplicates" ]; then
    echo "$taxonomy: [検査-宣言重複] 同じcheckerが複数回宣言されている: $(printf '%s' "$duplicates" | tr '\n' ' ')" >&2
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
    printf '%s\n' "$declared_placed" > "$_tb"
    missing="$(LC_ALL=C comm -13 "$_ta" "$_tb")"
    rm -f "$_ta" "$_tb"

    if [ -n "$undeclared" ]; then
      echo "$taxonomy: [検査-宣言欠落] 宣言の無いchecker: $(printf '%s' "$undeclared" | tr '\n' ' ')" >&2
      rc=1
    fi
    if [ -n "$missing" ]; then
      echo "$taxonomy: [検査-実在] 宣言したcheckerが実在しない: $(printf '%s' "$missing" | tr '\n' ' ')" >&2
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
DERIVED_PATH_VALUES=""  # ファイル横断でderivedPath値（非空）を集める。 "file<TAB>value" 行
CHECKER_VALUES=""  # ファイル横断でchecker値（checkable:true かつ実在確認済み）を集める。 "file<TAB>value" 行

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
    for key in $EXPECTED_KEYS $OPTIONAL_KEYS; do
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
    add_failure "$rule_file" "front-matter鍵-未定義" "14鍵と任意鍵（${OPTIONAL_KEYS}）に無い未定義の鍵: ${extra_keys}"
  fi

  # スカラー値取得
  local v_key v_title v_parent v_summary v_scope v_enforcement v_checkable
  local v_checker v_uncheckable v_formatter v_status v_origin
  local v_doc_type v_derived_path
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
  v_doc_type="$(fm_get_scalar "$body" docType)"
  [ -n "$v_doc_type" ] || v_doc_type="rule"
  v_derived_path="$(fm_get_scalar "$body" derivedPath)"
  [ "$v_derived_path" != "null" ] || v_derived_path=""

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

  # docType: 任意鍵。未指定なら rule 扱い。rule=規則の表を持つ規約 / context=規則の表を
  # 持たない説明文書（project-context 等）
  case "$v_doc_type" in
    rule|context) ;;
    *) add_failure "$rule_file" "値域-docType" "docType は rule/context のいずれかである必要がある（値: '${v_doc_type}'）" ;;
  esac
  # docType: context の規約は本文だけが派生対象であり、hooks への登録を持たない
  # 前提とする。checkable:true との組み合わせは、linter の存在を示唆するが
  # 検査対象の規則表を持たないため、意味が矛盾する。
  if [ "$v_doc_type" = "context" ] && [ "$v_checkable" = "true" ]; then
    add_failure "$rule_file" "docType-制約" "docType: context の規約は checkable: false である必要がある（値: checkable='${v_checkable}'）"
  fi

  # derivedPath: 任意鍵。既定の派生先（.claude/rules/<scope>/<parent>/<key>/rule.md）を
  # 上書きしたい規約（共通の hook が固定の場所を読む project-context 等）だけが持つ。
  if [ -n "$v_derived_path" ]; then
    case "$v_derived_path" in
      .claude/rules/*)
        case "$v_derived_path" in
          *..*) add_failure "$rule_file" "値域-derivedPath" "derivedPath に '..' を含めることはできない（値: '${v_derived_path}'）" ;;
        esac
        ;;
      *)
        add_failure "$rule_file" "値域-derivedPath" "derivedPath は '.claude/rules/' で始まる必要がある（値: '${v_derived_path}'）"
        ;;
    esac
    DERIVED_PATH_VALUES="${DERIVED_PATH_VALUES}${rule_file}	${v_derived_path}
"
  fi

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
        # checker-専有: 規約1件=checker1件の1対1を保つため、同フォルダに
        # 宣言外のcheck-*.sh（.test.shを除く）が無いことを確かめる。
        # --deploy-rule-scriptsが配る派生のスクリプト4本（is_deployed_tool_name）は
        # 実際の配備先（is_deployed_tool_dir が真を返す
        # agent-operations/ai-config-asset-management/）に限って対象外とする。
        # 同名のファイルが他の規約フォルダへ混入した場合は、配備先でないため
        # 従来どおり不合格として検出する。
        local other_checker other_checker_base
        while IFS= read -r other_checker; do
          [ -n "$other_checker" ] || continue
          other_checker_base="$(basename "$other_checker")"
          [ "$other_checker_base" = "$v_checker" ] && continue
          is_deployed_tool_name "$other_checker_base" && is_deployed_tool_dir "$child_dir" && continue
          add_failure "$rule_file" "checker-専有" "宣言外のcheck-*.shが同フォルダに存在する: ${other_checker_base}"
        done <<CHKEOF
$(find "$child_dir" -maxdepth 1 -type f -name "check-*.sh" ! -name "*.test.sh")
CHKEOF
        CHECKER_VALUES="${CHECKER_VALUES}${rule_file}	${v_checker}
"
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

  # 規則の表に関する3検査（規則-検査列・検査-手段明示・このプロジェクトの規則-存在）は
  # docType: rule（既定）の規約だけに適用する。docType: context の規約は
  # 「規則 | 内容 | 検査」の表を持たない説明文書（project-context 等）であり、
  # この形式を前提にしない。
  local doc_body
  doc_body="$(body_extract "$rule_file")"
  if [ "$v_doc_type" != "context" ]; then
    # 規則-検査列（根拠を別資料へ分ける3列と、従来の4列を受理する）
    local rule_table_header
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

# 派生先-重複: 全rule.md横断で、derivedPath の値が複数の規約で同じであれば不合格とする。
# derivedPath は既定の派生先（.claude/rules/<scope>/<parent>/<key>/rule.md）を上書きする
# ため、2件以上の規約が同じ値を持つと片方の生成結果がもう片方を上書きしてしまう。
check_derived_path_duplicates() {
  local dup
  dup="$(printf '%s' "$DERIVED_PATH_VALUES" | LC_ALL=C awk -F'\t' 'NF{print $2}' | LC_ALL=C sort | LC_ALL=C uniq -d)"
  if [ -n "$dup" ]; then
    local detail
    detail="$(printf '%s' "$DERIVED_PATH_VALUES" | awk -F'\t' 'NF{printf "%s=%s ", $1, $2}')"
    add_failure "(横断検査)" "派生先-重複" "derivedPath が複数の規約で重複している: ${detail}"
  fi
}

# checker-一意: 全rule.md横断で、宣言している checker（checkable:true かつ
# 実在確認済み）の値が複数の規約で同じであれば不合格とする。規約1件=checker1件の
# 1対1を保つため、同じ検査を2つの規約が自分のcheckerとして宣言することを禁じる。
check_checker_uniqueness() {
  local dup
  dup="$(printf '%s' "$CHECKER_VALUES" | LC_ALL=C awk -F'\t' 'NF{print $2}' | LC_ALL=C sort | LC_ALL=C uniq -d)"
  if [ -n "$dup" ]; then
    local detail
    detail="$(printf '%s' "$CHECKER_VALUES" | awk -F'\t' 'NF{printf "%s=%s ", $1, $2}')"
    add_failure "(横断検査)" "checker-一意" "同じcheckerを複数の規約が宣言している: ${detail}"
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
  DERIVED_PATH_VALUES=""
  CHECKER_VALUES=""

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
  check_derived_path_duplicates
  check_checker_uniqueness
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

# docType: context のケース専用フィクスチャ。project-context/rule.md のような
# 「規則 | 内容 | 検査」の表を持たない説明文書を模す。
# $1: ルートディレクトリ  $2: docType の値  $3: checkable の値
st_write_context_fixture() {
  local root="$1" doc_type="$2" checkable="$3"
  mkdir -p "${root}/repository-operations/project-context"

  cat > "${root}/repository-operations/parent.yml" <<'EOF'
key: repository-operations
title: リポジトリ運用
EOF

  local checker="null" uncheckable="値の記入は不要（説明文書のため）。"
  if [ "$checkable" = "true" ]; then
    checker="check-project-context.sh"
    uncheckable="null"
  fi

  cat > "${root}/repository-operations/project-context/rule.md" <<EOF
---
key: project-context
title: プロジェクトコンテキスト
parent: repository-operations
summary: 概要と設定索引をまとめた説明文書。
scope: always
paths: []
enforcement: advisory
checkable: ${checkable}
checker: ${checker}
uncheckableReason: ${uncheckable}
formatter: none
status: approved
origin: manual
workUnit: process
docType: ${doc_type}
---

# プロジェクトコンテキスト（テスト用）

## 概要

規則の表を持たない説明文書。docType の検査飛ばしを確認する。
EOF

  if [ "$checkable" = "true" ]; then
    cat > "${root}/repository-operations/project-context/check-project-context.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "${root}/repository-operations/project-context/check-project-context.test.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${root}/repository-operations/project-context/check-project-context.sh" \
      "${root}/repository-operations/project-context/check-project-context.test.sh"
  fi
}

st_case() {
  # $1: ケース名  $2: 期待exitコード  $3: 期待する検査キー(grep用。空なら未チェック)
  local name="$1" expected_rc="$2" expect_key="$3"
  local tmp
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/validate-rule-definitions-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  case "$name" in
    docType-context-pass)
      st_write_context_fixture "$tmp" "context" "false"
      ;;
    docType-context-checkable-conflict)
      st_write_context_fixture "$tmp" "context" "true"
      ;;
    docType-invalid-value)
      st_write_context_fixture "$tmp" "bogus" "false"
      ;;
    *)
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
        derived-path-outside)
          # derivedPath が '.claude/rules/' で始まらない値を持つ
          awk '{print} /^workUnit: file$/ && !d {print "derivedPath: docs/wrong/path/rule.md"; d=1}' \
            "${tmp}/code-standards/naming/rule.md" > "${tmp}/code-standards/naming/rule.md.new"
          mv "${tmp}/code-standards/naming/rule.md.new" "${tmp}/code-standards/naming/rule.md"
          ;;
        derived-path-dotdot)
          # derivedPath が '.claude/rules/' で始まるが '..' を含む
          awk '{print} /^workUnit: file$/ && !d {print "derivedPath: .claude/rules/../escape/rule.md"; d=1}' \
            "${tmp}/code-standards/naming/rule.md" > "${tmp}/code-standards/naming/rule.md.new"
          mv "${tmp}/code-standards/naming/rule.md.new" "${tmp}/code-standards/naming/rule.md"
          ;;
        derived-path-duplicate)
          # 2件の規約が同じ derivedPath を持つ
          local f
          for f in "${tmp}/agent-operations/ai-behavior/rule.md" "${tmp}/code-standards/naming/rule.md"; do
            awk '{print} /^workUnit: file$/ && !d {print "derivedPath: .claude/rules/always/shared/rule.md"; d=1}' \
              "$f" > "${f}.new"
            mv "${f}.new" "$f"
          done
          ;;
        checker-exclusive)
          # checkerを宣言する規約のフォルダに、宣言外のcheck-*.shが紛れ込む
          cat > "${tmp}/code-standards/naming/check-unrelated.sh" <<'INNEREOF'
#!/usr/bin/env bash
exit 0
INNEREOF
          ;;
        checker-duplicate)
          # 2件の規約が同じcheckerを自分のcheckerとして宣言する
          sed -i.bak 's/^checkable: false$/checkable: true/; s/^checker: null$/checker: check-naming.sh/; s/^uncheckableReason: .*$/uncheckableReason: null/' "${tmp}/agent-operations/ai-behavior/rule.md"
          rm -f "${tmp}/agent-operations/ai-behavior/rule.md.bak"
          cp "${tmp}/code-standards/naming/check-naming.sh" "${tmp}/agent-operations/ai-behavior/check-naming.sh"
          cp "${tmp}/code-standards/naming/check-naming.test.sh" "${tmp}/agent-operations/ai-behavior/check-naming.test.sh"
          ;;
      esac
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

  # --taxonomy 未指定は [SKIP] を返し終了コード0（分類定義の任意化）
  local skip_root skip_out skip_rc=0
  if ! skip_root="$(mktemp -d "${TMPDIR:-/tmp}/validate-rule-definitions-self-test-skip.XXXXXX" 2>/dev/null)" || [ -z "$skip_root" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  skip_out="$(validate_checker_declarations "$skip_root" "" 2>&1)" || skip_rc=$?
  rm -rf "$skip_root"
  if [ "$skip_rc" -eq 0 ] && printf '%s' "$skip_out" | grep -q '^\[SKIP\]'; then
    echo "  [PASS] taxonomy-skip: --taxonomy 未指定は [SKIP] で終了コード0"
  else
    echo "  [FAIL] taxonomy-skip: 期待どおり [SKIP] を返さない (rc=${skip_rc})" >&2
    printf '%s\n' "$skip_out" | sed 's/^/    /' >&2
    rc=1
  fi

  # --taxonomy を指定し、docs/rules 配下の実物と宣言が一致すれば合格する
  local decl_root decl_taxonomy decl_out decl_rc=0
  if ! decl_root="$(mktemp -d "${TMPDIR:-/tmp}/validate-rule-definitions-self-test-decl.XXXXXX" 2>/dev/null)" || [ -z "$decl_root" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  st_write_valid_pair "$decl_root"
  if ! decl_taxonomy="$(mktemp "${TMPDIR:-/tmp}/validate-rule-definitions-self-test-decl-taxonomy.XXXXXX" 2>/dev/null)" || [ -z "$decl_taxonomy" ]; then
    echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  cat > "$decl_taxonomy" <<'EOF'
{"parents": [{"key":"code-standards","children":[{"key":"naming","checker":"check-naming.sh"}]}]}
EOF
  decl_out="$(validate_checker_declarations "$decl_root" "$decl_taxonomy" 2>&1)" || decl_rc=$?
  rm -rf "$decl_root"
  rm -f "$decl_taxonomy"
  if [ "$decl_rc" -eq 0 ] && printf '%s' "$decl_out" | grep -q '検査宣言合格'; then
    echo "  [PASS] taxonomy-declared: 実在のcheckerが宣言と一致すれば合格（docs/rulesのルート配下を深さ3で走査）"
  else
    echo "  [FAIL] taxonomy-declared: 期待どおりに合格しない (rc=${decl_rc})" >&2
    printf '%s\n' "$decl_out" | sed 's/^/    /' >&2
    rc=1
  fi

  # --deploy-rule-scriptsが配る派生のスクリプト4本（check-rule-drift.shは
  # check-*.shの命名規則に一致する）が、実際の配備先
  # （agent-operations/ai-config-asset-management/）に置かれた場合だけ、
  # 宣言網羅の検査から「宣言の無いchecker」として検出されないことを確認する。
  # 配備先以外（他の規約フォルダ等）に同名ファイルが混入した場合は、
  # 除外せず従来どおり検出することも合わせて確認する（除外を名前だけで
  # 判定していた実践で見つかった不具合の回帰）。
  local tool_root tool_taxonomy tool_out tool_rc=0
  if ! tool_root="$(mktemp -d "${TMPDIR:-/tmp}/validate-rule-definitions-self-test-tool.XXXXXX" 2>/dev/null)" || [ -z "$tool_root" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  st_write_valid_pair "$tool_root"
  # st_write_valid_pairはagent-operations/ai-behavior/とcode-standards/naming/
  # の2フォルダを既に用意している。派生のスクリプト4本は実際の配備先
  # （agent-operations/ai-config-asset-management/）へ新たに置く。
  # 本ファイルはSCRIPT_DIRを定義しないため（validate-rule-definitions.shは
  # 他スクリプトからsourceされる前提でSCRIPT_DIRの定義自体を持たない）、
  # 自分自身の置き場をBASH_SOURCE[0]から都度求める。
  local self_dir
  self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  mkdir -p "${tool_root}/agent-operations/ai-config-asset-management"
  cp "${self_dir}/build-derived-rules.sh" "${tool_root}/agent-operations/ai-config-asset-management/build-derived-rules.sh"
  cp "${self_dir}/validate-rule-definitions.sh" "${tool_root}/agent-operations/ai-config-asset-management/validate-rule-definitions.sh"
  cp "${self_dir}/check-rule-drift.sh" "${tool_root}/agent-operations/ai-config-asset-management/check-rule-drift.sh"
  cp "${self_dir}/resolve-applicable-rules.sh" "${tool_root}/agent-operations/ai-config-asset-management/resolve-applicable-rules.sh"
  if ! tool_taxonomy="$(mktemp "${TMPDIR:-/tmp}/validate-rule-definitions-self-test-tool-taxonomy.XXXXXX" 2>/dev/null)" || [ -z "$tool_taxonomy" ]; then
    echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  cat > "$tool_taxonomy" <<'EOF'
{"parents": [{"key":"code-standards","children":[{"key":"naming","checker":"check-naming.sh"}]}]}
EOF
  tool_out="$(validate_checker_declarations "$tool_root" "$tool_taxonomy" 2>&1)" || tool_rc=$?
  if [ "$tool_rc" -eq 0 ] && printf '%s' "$tool_out" | grep -q '検査宣言合格'; then
    echo "  [PASS] tool-exclusion: 配備先（ai-config-asset-management/）に置かれた派生のスクリプト4本（check-rule-drift.sh含む）は宣言の無いcheckerとして検出しない"
  else
    echo "  [FAIL] tool-exclusion: 配備先に置かれた派生のスクリプト4本が誤って未宣言checkerとして検出された (rc=${tool_rc})" >&2
    printf '%s\n' "$tool_out" | sed 's/^/    /' >&2
    rc=1
  fi
  # 配備先以外（st_write_valid_pairが用意したagent-operations/ai-behavior/）へ
  # 同名ファイルが混入した場合は、除外せず従来どおり「宣言の無いchecker」
  # として検出する（除外を名前だけで判定していた実践で見つかった不具合の回帰）。
  cp "${self_dir}/check-rule-drift.sh" "${tool_root}/agent-operations/ai-behavior/check-rule-drift.sh"
  local tool_out2 tool_rc2=0
  tool_out2="$(validate_checker_declarations "$tool_root" "$tool_taxonomy" 2>&1)" || tool_rc2=$?
  if [ "$tool_rc2" -ne 0 ] && printf '%s' "$tool_out2" | grep -q '\[検査-宣言欠落\].*check-rule-drift\.sh'; then
    echo "  [PASS] tool-exclusion-scope: 配備先以外に混入した同名ファイルは従来どおり検出する"
  else
    echo "  [FAIL] tool-exclusion-scope: 配備先以外への混入を検出できない (rc=${tool_rc2})" >&2
    printf '%s\n' "$tool_out2" | sed 's/^/    /' >&2
    rc=1
  fi
  rm -rf "$tool_root"
  rm -f "$tool_taxonomy"

  # 分類定義に無い自身の規約（taxonomyの32子カテゴリの外にある、対象
  # リポジトリ自身のためのrule.md）は、rule.md自身のfront matterで
  # checker を宣言していれば「宣言欠落」にならないことを確認する。
  local fm_root fm_taxonomy fm_out fm_rc=0
  if ! fm_root="$(mktemp -d "${TMPDIR:-/tmp}/validate-rule-definitions-self-test-fm.XXXXXX" 2>/dev/null)" || [ -z "$fm_root" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  st_write_valid_pair "$fm_root"
  mkdir -p "${fm_root}/agent-operations/own-rule"
  cat > "${fm_root}/agent-operations/own-rule/rule.md" <<'EOF'
---
key: own-rule
title: 分類定義に無い自身の規約
parent: agent-operations
summary: taxonomyの32子カテゴリに含まれない、対象リポジトリ自身のための規約。
scope: always
paths: []
enforcement: advisory
checkable: true
checker: check-own-rule.sh
uncheckableReason: null
formatter: none
status: approved
origin: manual
workUnit: file
---

# 分類定義に無い自身の規約

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
  cat > "${fm_root}/agent-operations/own-rule/check-own-rule.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${fm_root}/agent-operations/own-rule/check-own-rule.sh"
  if ! fm_taxonomy="$(mktemp "${TMPDIR:-/tmp}/validate-rule-definitions-self-test-fm-taxonomy.XXXXXX" 2>/dev/null)" || [ -z "$fm_taxonomy" ]; then
    echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  cat > "$fm_taxonomy" <<'EOF'
{"parents": [{"key":"code-standards","children":[{"key":"naming","checker":"check-naming.sh"}]}]}
EOF
  fm_out="$(validate_checker_declarations "$fm_root" "$fm_taxonomy" 2>&1)" || fm_rc=$?
  rm -rf "$fm_root"
  rm -f "$fm_taxonomy"
  if [ "$fm_rc" -eq 0 ] && printf '%s' "$fm_out" | grep -q '検査宣言合格'; then
    echo "  [PASS] fm-checker-declared: 分類定義に無い自身の規約はfront matterのchecker宣言で宣言欠落にならない"
  else
    echo "  [FAIL] fm-checker-declared: 分類定義に無い自身の規約がfront matterで宣言しても宣言欠落として検出された (rc=${fm_rc})" >&2
    printf '%s\n' "$fm_out" | sed 's/^/    /' >&2
    rc=1
  fi

  # 分類定義に3件の子カテゴリの宣言があり、docs/rules へ実際に配置したのは
  # 1件だけの一時リポジトリで、--taxonomy 付きの検査が終了コード0になり、
  # [SKIP] に2件と出ることを確認する（未配置は「実在しない」ではない）。
  local skp_root skp_taxonomy skp_out skp_rc=0
  if ! skp_root="$(mktemp -d "${TMPDIR:-/tmp}/validate-rule-definitions-self-test-skp.XXXXXX" 2>/dev/null)" || [ -z "$skp_root" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  st_write_valid_pair "$skp_root"
  if ! skp_taxonomy="$(mktemp "${TMPDIR:-/tmp}/validate-rule-definitions-self-test-skp-taxonomy.XXXXXX" 2>/dev/null)" || [ -z "$skp_taxonomy" ]; then
    echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  cat > "$skp_taxonomy" <<'EOF'
{"parents": [{"key":"code-standards","children":[
  {"key":"naming","checker":"check-naming.sh"},
  {"key":"unplaced-one","checker":"check-unplaced-one.sh"},
  {"key":"unplaced-two","checker":"check-unplaced-two.sh"}
]}]}
EOF
  skp_out="$(validate_checker_declarations "$skp_root" "$skp_taxonomy" 2>&1)" || skp_rc=$?
  rm -rf "$skp_root"
  rm -f "$skp_taxonomy"
  if [ "$skp_rc" -eq 0 ] \
    && printf '%s' "$skp_out" | grep -q '^\[SKIP\] 配置していないため実在の判定から除外したchecker宣言: 2 件$' \
    && printf '%s' "$skp_out" | grep -q '検査宣言合格'; then
    echo "  [PASS] taxonomy-unplaced-skip: 未配置の子カテゴリの宣言は実在しない扱いにせず[SKIP]2件で合格する"
  else
    echo "  [FAIL] taxonomy-unplaced-skip: 期待どおり[SKIP]2件で合格しない (rc=${skp_rc})" >&2
    printf '%s\n' "$skp_out" | sed 's/^/    /' >&2
    rc=1
  fi

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

  # docType: context は規則の表を前提にする3検査を飛ばす（project-context 等の説明文書）
  st_case "docType-context-pass" 0 "" || rc=1
  st_case "docType-context-checkable-conflict" 1 "docType-制約" || rc=1
  st_case "docType-invalid-value" 1 "値域-docType" || rc=1

  # derivedPath は既定の派生先を上書きする任意鍵
  st_case "derived-path-outside" 1 "値域-derivedPath" || rc=1
  st_case "derived-path-dotdot" 1 "値域-derivedPath" || rc=1
  st_case "derived-path-duplicate" 1 "派生先-重複" || rc=1
  st_case "checker-exclusive" 1 "checker-専有" || rc=1
  st_case "checker-duplicate" 1 "checker-一意" || rc=1

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

  local taxonomy="" args=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --taxonomy)
        taxonomy="${2:-}"
        shift 2
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done

  if [ "${#args[@]}" -ne 1 ]; then
    echo "使い方: $(basename "$0") <docs/rules のルート> [--taxonomy <分類定義のパス>]" >&2
    echo "        $(basename "$0") --self-test" >&2
    exit 1
  fi

  local rules_root="${args[0]}"
  validate_checker_declarations "$rules_root" "$taxonomy" || exit 1
  check_rules_root_hint "$rules_root"
  run_validate "$rules_root"
  exit $?
}

# 直接実行時のみdispatchする（build-derived-rules.shがsourceしてrun_validate等の
# 関数を再利用できるよう、source時は呼び出し元の位置引数を誤読しない）
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main "$@"
fi
