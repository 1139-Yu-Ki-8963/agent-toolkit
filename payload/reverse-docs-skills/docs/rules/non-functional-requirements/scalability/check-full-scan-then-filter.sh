#!/usr/bin/env bash
# check-full-scan-then-filter.sh — 利用が増えたときの決まりの linter
#
# timing: PreToolUse(Write)
# 対象規約: 利用が増えたときの決まり
#
# 対象の規則（検査列に「静的解析:」を含む5件すべてを検査する）:
#   1. 増加の見込みを数値で置く
#      — 要件定義書または基本設計書に増加の見込みの記述があるかを走査する
#   2. 増やす方向を決める
#      — 基本設計書に拡張の方向を述べた記述があるかを走査する
#   3. 処理の側に状態を残さない
#      — 処理を行う層に利用者ごとの状態を保持する記述が無いかを走査する
#   4. 件数に比例する処理を作らない
#      — 全件の取得の後に絞り込みを行う記述が無いかを走査する（唯一の
#        止める判定）
#   5. 上限に達したときの振る舞いを決める
#      — 受け付けの入口に流量の制限が設定されているかを走査する
#
# 判定の設計:
#   件数に比例する処理と処理の側の状態は、書き込み対象のコードファイル
#   自体の中身を走査する。全件取得の直後（3行以内）に絞り込みが続く記述、
#   session と globalThis/global./static の同一行での共起、という記号的な
#   特徴で機械的に判定する。増加の見込み・拡張の方向は、対象プロジェクトの
#   要件定義書・基本設計書という別文書の実在と中身を cwd から探して判定する
#   （check-currency-float-type.sh の「式を設計書へ書く」と同じ考え方）。
#   上限に達したときの振る舞いは、書き込み対象のコードに受け付けの入口ら
#   しい記述があるかをまず見て、無ければ対象外とし、あれば流量制限の語彙の
#   有無を判定する。
#
# 対象ファイル:
#   件数に比例する処理・処理の側の状態・上限に達したときの振る舞いは、
#   コードの拡張子（.ts/.tsx/.js/.jsx/.mjs/.cjs/.py/.java/.cs/.go/.rb/.php/
#   .kt/.swift）に限定する。増加の見込み・拡張の方向は書き込み対象ファイル
#   の拡張子に依存せず、cwd 配下の要件定義書・基本設計書という別文書を探す。
#
# 除外条件（誤検知回避）:
#   - tool_name が Write 以外 → 対象外
#   - file_path・content が空 → 対象外
#   - コードの拡張子でない → 件数に比例する処理・処理の側の状態・
#     上限に達したときの振る舞いの3規則は対象外
#   - cwd が空・存在しない → 増加の見込み・拡張の方向の2規則は対象外
#   - 要件定義書・基本設計書が見当たらない → 対応する規則は対象外
#   - 受け付けの入口らしい記述が無い → 上限に達したときの振る舞いは対象外
#
# 既知の限界:
#   - 全件取得と絞り込みの近接検査は同一ファイル内の後続3行以内でしか
#     見ない。別の関数・別のファイルをまたぐ絞り込みは検出できない
#   - 状態保持の検査は session と globalThis/global./static の同一行での
#     共起でしか判定しない。別行に分けて書かれた状態保持は検出できない
#   - 増加の見込み・拡張の方向はファイル名一致で最初に見つかった文書のみ
#     を見る。複数文書に分散した記述は最初の1件でしか判定されない
#   - 上限に達したときの振る舞いは受け付けの入口らしい記述の有無を先に見る
#     簡易な判定であり、実際にその入口が外部からの要求を受け付けるかまでは
#     確認しない
#
# 使い方:
#   フック本体として: PreToolUse(Write) の入力 JSON を stdin から受け取る
#   単体実行: check-full-scan-then-filter.sh --self-test
#
# 止めるか知らせるか:
#   件数に比例する処理を作らない: 止める（全件取得後の絞り込みが実装へ混入すると、データ量が増えてから遡って直すのは手戻りが大きいため）
#   増加の見込みを数値で置く: 知らせる（設計文書の整備が進めば自然に満たされる記述の不足のため）
#   増やす方向を決める: 知らせる（基本設計書の整備が進めば自然に満たされる記述の不足のため）
#   処理の側に状態を残さない: 知らせる（設計を見直す過程で解消できる整備上の指摘のため）
#   上限に達したときの振る舞いを決める: 知らせる（実装の途中でも流量制限を追加できる設定の不足のため）
#
# 逃げ道:
#   FULL_SCAN_THEN_FILTER_SKIP_REASON に理由を書けば通る。理由が空の場合は通らない
set -uo pipefail

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${FULL_SCAN_THEN_FILTER_SKIP_REASON:-}" ]; then
    echo "[FULL-SCAN-THEN-FILTER-SKIP] 理由: ${FULL_SCAN_THEN_FILTER_SKIP_REASON}"
    return 0
  fi
  return 1
}

FULL_SCAN_RE='(findAll\(|\.all\(\)|fetchAll\(|getAll\(|SELECT \*)'
FILTER_RE='(\.filter\(|\.find\(|\.where\()'
STATE_SESSION_RE='(session|Session)'
STATE_GLOBAL_RE='(globalThis|global\.|static )'
GROWTH_NUMBER_RE='(利用者数|データ件数|処理件数)'
DIRECTION_RE='(台数を増やす|台数の増加|1台を大きく|1 台を大きく|水平|垂直)'
ENTRYPOINT_RE='(router\.|route\(|@(Get|Post|Put|Delete|Patch)|app\.(get|post|put|delete|patch)|handler|Handler)'
RATE_LIMIT_RE='(rateLimit|rate_limit|rate-limit|throttle|Throttle|limiter)'

is_code_ext() {
  case "$1" in
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.py|*.java|*.cs|*.go|*.rb|*.php|*.kt|*.swift) return 0 ;;
    *) return 1 ;;
  esac
}

# cwd 配下（.git 配下を除く）からファイル名に needle を含む最初のファイルを返す
find_doc_by_name() {
  local cwd="$1" needle="$2"
  if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
    return 0
  fi
  find "$cwd" -type f -not -path '*/.git/*' -name "*${needle}*" 2>/dev/null | head -1
}

# 「件数に比例する処理を作らない」規則の判定
judge_full_scan_then_filter() {
  # $1: content
  local content="$1"
  local total_lines lineno full_line n window i target
  total_lines=$(printf '%s\n' "$content" | wc -l | tr -d ' ')
  local -a lines=()
  while IFS= read -r line; do
    lines+=("$line")
  done <<< "$content"

  n=${#lines[@]}
  for ((i = 0; i < n; i++)); do
    if printf '%s' "${lines[$i]}" | grep -qE "$FULL_SCAN_RE"; then
      lineno=$((i + 1))
      window=$((i + 3))
      [ "$window" -ge "$n" ] && window=$((n - 1))
      for ((target = i; target <= window; target++)); do
        if printf '%s' "${lines[$target]}" | grep -qE "$FILTER_RE"; then
          local snippet
          snippet="$(printf '%s' "${lines[$i]}" | cut -c1-60)"
          echo "拒否[件数に比例する処理を作らない]: 全件の取得の直後に絞り込みがあります（${lineno}行目: ${snippet}）"
          return 2
        fi
      done
    fi
  done

  echo "許可[件数に比例する処理を作らない]: 全件の取得の直後の絞り込みは見当たりません"
  return 0
}

# 「増加の見込みを数値で置く」規則の判定
judge_growth_estimate() {
  # $1: cwd
  local cwd="$1" found found2 relpath
  if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
    echo "対象外[増加の見込みを数値で置く]: 作業ディレクトリが分からないため判定していません"
    return 0
  fi

  found="$(find_doc_by_name "$cwd" "要件定義書")"
  found2="$(find_doc_by_name "$cwd" "基本設計書")"

  if [ -z "$found" ] && [ -z "$found2" ]; then
    echo "対象外[増加の見込みを数値で置く]: 要件定義書と基本設計書が見当たらないため判定していません"
    return 0
  fi

  local doc body
  for doc in "$found" "$found2"; do
    [ -z "$doc" ] && continue
    body="$(cat "$doc" 2>/dev/null)"
    if printf '%s\n' "$body" | grep -E "$GROWTH_NUMBER_RE" 2>/dev/null | grep -qE '[0-9]'; then
      relpath="${doc#"$cwd"/}"
      echo "許可[増加の見込みを数値で置く]: 増加の見込みの記述があります（${relpath}）"
      return 0
    fi
  done

  echo "通知[増加の見込みを数値で置く]: 要件定義書と基本設計書に増加の見込みを数値で置いた記述が見当たりません"
  return 0
}

# 「増やす方向を決める」規則の判定
judge_scaling_direction() {
  # $1: cwd
  local cwd="$1" found relpath body
  if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
    echo "対象外[増やす方向を決める]: 作業ディレクトリが分からないため判定していません"
    return 0
  fi

  found="$(find_doc_by_name "$cwd" "基本設計書")"
  if [ -z "$found" ]; then
    echo "対象外[増やす方向を決める]: 基本設計書が見当たらないため判定していません"
    return 0
  fi

  body="$(cat "$found" 2>/dev/null)"
  relpath="${found#"$cwd"/}"
  if printf '%s' "$body" | grep -qE "$DIRECTION_RE"; then
    echo "許可[増やす方向を決める]: 拡張の方向の記述があります（${relpath}）"
    return 0
  fi

  echo "通知[増やす方向を決める]: 基本設計書に拡張の方向を述べた記述が見当たりません"
  return 0
}

# 「処理の側に状態を残さない」規則の判定
judge_stateless_processing() {
  # $1: file_path, $2: content
  local file_path="$1" content="$2"

  if ! is_code_ext "$file_path"; then
    echo "対象外[処理の側に状態を残さない]: コードの拡張子ではありません（${file_path}）"
    return 0
  fi

  local hit
  hit=$(printf '%s\n' "$content" | grep -inE "$STATE_SESSION_RE" 2>/dev/null | grep -E "$STATE_GLOBAL_RE" 2>/dev/null | head -1)

  if [ -n "$hit" ]; then
    local snippet
    snippet="$(printf '%s' "$hit" | cut -c1-60)"
    echo "通知[処理の側に状態を残さない]: 処理の層に利用者ごとの状態を保持する記述があります（${snippet}）"
    return 0
  fi

  echo "許可[処理の側に状態を残さない]: 処理の層に利用者ごとの状態を保持する記述は見当たりません"
  return 0
}

# 「上限に達したときの振る舞いを決める」規則の判定
judge_rate_limit() {
  # $1: file_path, $2: content
  local file_path="$1" content="$2"

  if ! is_code_ext "$file_path"; then
    echo "対象外[上限に達したときの振る舞いを決める]: コードの拡張子ではありません（${file_path}）"
    return 0
  fi

  if ! printf '%s' "$content" | grep -qiE "$ENTRYPOINT_RE"; then
    echo "対象外[上限に達したときの振る舞いを決める]: 受け付けの入口らしい記述が見当たりません"
    return 0
  fi

  if printf '%s' "$content" | grep -qE "$RATE_LIMIT_RE"; then
    echo "許可[上限に達したときの振る舞いを決める]: 受け付けの入口に流量の制限があります"
    return 0
  fi

  echo "通知[上限に達したときの振る舞いを決める]: 受け付けの入口に流量の制限が見当たりません"
  return 0
}

judge() {
  # $1: file_path, $2: content, $3: cwd
  local file_path="$1" content="$2" cwd="$3"
  local msg code out_code=0

  if is_code_ext "$file_path"; then
    if msg="$(judge_full_scan_then_filter "$content")"; then code=0; else code=$?; fi
    echo "$msg"
    if [ "$code" -eq 2 ]; then
      out_code=2
    fi
  else
    echo "対象外[件数に比例する処理を作らない]: コードの拡張子ではありません（${file_path}）"
  fi

  judge_growth_estimate "$cwd"
  judge_scaling_direction "$cwd"
  judge_stateless_processing "$file_path" "$content"
  judge_rate_limit "$file_path" "$content"

  return "$out_code"
}

run_hook() {
  local skip_msg
  if skip_msg="$(should_skip_with_reason)"; then
    printf '%s\n' "$skip_msg" >&2
    exit 0
  fi

  local input
  input="$(cat)"
  [ -z "$input" ] && exit 0

  local tool
  tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
  [ "$tool" != "Write" ] && exit 0

  local file_path content cwd
  file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
  [ -z "$file_path" ] && exit 0
  content=$(printf '%s' "$input" | jq -r '.tool_input.content // empty' 2>/dev/null)
  [ -z "$content" ] && exit 0
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)

  local msg code
  if msg="$(judge "$file_path" "$content" "$cwd")"; then code=0; else code=$?; fi

  printf '%s\n' "$msg" >&2

  [ "$code" -ne 2 ] && exit 0

  local reject_line
  reject_line="$(printf '%s\n' "$msg" | grep -F '拒否[件数に比例する処理を作らない]' | head -1)"
  ctx="[FULL-SCAN-THEN-FILTER-BLOCK] ${reject_line}。データの側で絞り込んでから再実行してください。"
  jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  printf '%s\n' "$ctx" >&2
  exit 2
}

self_test() {
  local rc=0 msg code

  # 系1: 全件取得の直後に絞り込みがある → 拒否（件数に比例する処理を作らない）
  local c1='const users = await User.findAll();
const active = users.filter(u => u.active);'
  if msg="$(judge "list.js" "$c1" "")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '拒否[件数に比例する処理を作らない]'; then
    echo "  [PASS] 系1: 全件取得直後の絞り込みは拒否される（${msg}）"
  else
    echo "  [FAIL] 系1: 全件取得直後の絞り込みなのに拒否されない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系2: 全件取得のみで絞り込みが4行以上離れている → 許可（件数に比例する処理を作らない）
  local c2='const users = await User.findAll();
const a = 1;
const b = 2;
const c = 3;
const active = users.filter(u => u.active);'
  if msg="$(judge "list.js" "$c2" "")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '許可[件数に比例する処理を作らない]'; then
    echo "  [PASS] 系2: 4行以上離れた絞り込みは許可される（${msg}）"
  else
    echo "  [FAIL] 系2: 離れた絞り込みなのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系3（近傍事例）: データの側で絞り込むクエリ（全件取得の語彙自体が無い）→ 許可（件数に比例する処理を作らない）
  local c3='const active = await User.where({ active: true }).find();'
  if msg="$(judge "list.js" "$c3" "")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '許可[件数に比例する処理を作らない]'; then
    echo "  [PASS] 系3: データ側の絞り込みのみは許可される（${msg}）"
  else
    echo "  [FAIL] 系3: 全件取得が無いのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系4: コードの拡張子でない → 対象外（件数に比例する処理を作らない）
  local c4='# メモ
全件取得してから絞り込む。'
  if msg="$(judge "note.md" "$c4" "")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '対象外[件数に比例する処理を作らない]'; then
    echo "  [PASS] 系4: コードの拡張子でなければ対象外になる（${msg}）"
  else
    echo "  [FAIL] 系4: コードでないのに判定された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系5: cwd が空 → 対象外（増加の見込みを数値で置く）
  msg="$(judge_growth_estimate "")"
  if printf '%s' "$msg" | grep -qF '対象外[増加の見込みを数値で置く]: 作業ディレクトリが分からない'; then
    echo "  [PASS] 系5: cwd が空なら対象外になる（${msg}）"
  else
    echo "  [FAIL] 系5: cwd が空なのに判定された（${msg}）" >&2
    rc=1
  fi

  # 系6: 要件定義書・基本設計書が見当たらない → 対象外（増加の見込みを数値で置く）
  local tmp6
  if ! tmp6="$(mktemp -d "${TMPDIR:-/tmp}/check-full-scan-then-filter-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp6" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  mkdir -p "$tmp6/docs"
  printf '# メモ\n' > "$tmp6/docs/メモ.md"
  msg="$(judge_growth_estimate "$tmp6")"
  rm -rf "$tmp6"
  if printf '%s' "$msg" | grep -qF '対象外[増加の見込みを数値で置く]: 要件定義書と基本設計書が見当たらない'; then
    echo "  [PASS] 系6: 要件定義書・基本設計書が無ければ対象外になる（${msg}）"
  else
    echo "  [FAIL] 系6: 文書が無いのに判定された（${msg}）" >&2
    rc=1
  fi

  # 系7: 要件定義書はあるが増加の見込みの記述が無い → 通知（増加の見込みを数値で置く）
  local tmp7
  if ! tmp7="$(mktemp -d "${TMPDIR:-/tmp}/check-full-scan-then-filter-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp7" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  mkdir -p "$tmp7/docs"
  printf '# 注文機能要件定義書\n\n## 対象範囲\n注文機能を対象とする。\n' > "$tmp7/docs/注文機能要件定義書.md"
  msg="$(judge_growth_estimate "$tmp7")"
  rm -rf "$tmp7"
  if printf '%s' "$msg" | grep -qF '通知[増加の見込みを数値で置く]'; then
    echo "  [PASS] 系7: 増加の見込みの記述が無ければ通知される（${msg}）"
  else
    echo "  [FAIL] 系7: 記述が無いのに通知されない（${msg}）" >&2
    rc=1
  fi

  # 系8: 要件定義書に増加の見込みの記述がある → 許可（増加の見込みを数値で置く）
  local tmp8
  if ! tmp8="$(mktemp -d "${TMPDIR:-/tmp}/check-full-scan-then-filter-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp8" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  mkdir -p "$tmp8/docs"
  printf '# 注文機能要件定義書\n\n## 対象範囲\n利用者数は3年後に10万人まで増える見込み。\n' > "$tmp8/docs/注文機能要件定義書.md"
  msg="$(judge_growth_estimate "$tmp8")"
  rm -rf "$tmp8"
  if printf '%s' "$msg" | grep -qF '許可[増加の見込みを数値で置く]'; then
    echo "  [PASS] 系8: 増加の見込みの記述があれば許可される（${msg}）"
  else
    echo "  [FAIL] 系8: 記述があるのに許可されない（${msg}）" >&2
    rc=1
  fi

  # 系9: 基本設計書が見当たらない → 対象外（増やす方向を決める）
  local tmp9
  if ! tmp9="$(mktemp -d "${TMPDIR:-/tmp}/check-full-scan-then-filter-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp9" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  mkdir -p "$tmp9/docs"
  printf '# メモ\n' > "$tmp9/docs/メモ.md"
  msg="$(judge_scaling_direction "$tmp9")"
  rm -rf "$tmp9"
  if printf '%s' "$msg" | grep -qF '対象外[増やす方向を決める]'; then
    echo "  [PASS] 系9: 基本設計書が無ければ対象外になる（${msg}）"
  else
    echo "  [FAIL] 系9: 基本設計書が無いのに判定された（${msg}）" >&2
    rc=1
  fi

  # 系10: 基本設計書はあるが拡張の方向の記述が無い → 通知（増やす方向を決める）
  local tmp10
  if ! tmp10="$(mktemp -d "${TMPDIR:-/tmp}/check-full-scan-then-filter-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp10" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  mkdir -p "$tmp10/docs"
  printf '# 注文機能基本設計書\n\n## 外部仕様\n画面の項目を定める。\n' > "$tmp10/docs/注文機能基本設計書.md"
  msg="$(judge_scaling_direction "$tmp10")"
  rm -rf "$tmp10"
  if printf '%s' "$msg" | grep -qF '通知[増やす方向を決める]'; then
    echo "  [PASS] 系10: 拡張の方向の記述が無ければ通知される（${msg}）"
  else
    echo "  [FAIL] 系10: 記述が無いのに通知されない（${msg}）" >&2
    rc=1
  fi

  # 系11: 基本設計書に拡張の方向の記述がある → 許可（増やす方向を決める）
  local tmp11
  if ! tmp11="$(mktemp -d "${TMPDIR:-/tmp}/check-full-scan-then-filter-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp11" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  mkdir -p "$tmp11/docs"
  printf '# 注文機能基本設計書\n\n## 方式設計\n水平にサーバーの台数を増やして対応する。\n' > "$tmp11/docs/注文機能基本設計書.md"
  msg="$(judge_scaling_direction "$tmp11")"
  rm -rf "$tmp11"
  if printf '%s' "$msg" | grep -qF '許可[増やす方向を決める]'; then
    echo "  [PASS] 系11: 拡張の方向の記述があれば許可される（${msg}）"
  else
    echo "  [FAIL] 系11: 記述があるのに許可されない（${msg}）" >&2
    rc=1
  fi

  # 系12: コードの拡張子でない → 対象外（処理の側に状態を残さない）
  msg="$(judge_stateless_processing "note.md" "session と globalThis を同居させる")"
  if printf '%s' "$msg" | grep -qF '対象外[処理の側に状態を残さない]'; then
    echo "  [PASS] 系12: コードの拡張子でなければ対象外になる（${msg}）"
  else
    echo "  [FAIL] 系12: コードでないのに判定された（${msg}）" >&2
    rc=1
  fi

  # 系13: session と globalThis が同一行で共起する → 通知（処理の側に状態を残さない）
  local c13='globalThis.session = req.session;'
  msg="$(judge_stateless_processing "server.js" "$c13")"
  if printf '%s' "$msg" | grep -qF '通知[処理の側に状態を残さない]'; then
    echo "  [PASS] 系13: session と globalThis の共起は通知される（${msg}）"
  else
    echo "  [FAIL] 系13: 共起しているのに通知されない（${msg}）" >&2
    rc=1
  fi

  # 系14（近傍事例）: session はあるが同一行に globalThis/global./static が無い → 許可（処理の側に状態を残さない）
  local c14='const session = req.session;
console.log(session.id);'
  msg="$(judge_stateless_processing "server.js" "$c14")"
  if printf '%s' "$msg" | grep -qF '許可[処理の側に状態を残さない]'; then
    echo "  [PASS] 系14: 同一行での共起が無ければ許可される（${msg}）"
  else
    echo "  [FAIL] 系14: 共起していないのに通知された（${msg}）" >&2
    rc=1
  fi

  # 系15: コードの拡張子でない → 対象外（上限に達したときの振る舞いを決める）
  msg="$(judge_rate_limit "note.md" "app.get('/users', handler)")"
  if printf '%s' "$msg" | grep -qF '対象外[上限に達したときの振る舞いを決める]: コードの拡張子ではありません'; then
    echo "  [PASS] 系15: コードの拡張子でなければ対象外になる（${msg}）"
  else
    echo "  [FAIL] 系15: コードでないのに判定された（${msg}）" >&2
    rc=1
  fi

  # 系16（近傍事例）: 受け付けの入口らしい記述が無い → 対象外（上限に達したときの振る舞いを決める）
  local c16='function add(a, b) { return a + b; }'
  msg="$(judge_rate_limit "util.js" "$c16")"
  if printf '%s' "$msg" | grep -qF '対象外[上限に達したときの振る舞いを決める]: 受け付けの入口らしい記述が見当たりません'; then
    echo "  [PASS] 系16: 受け付けの入口が無ければ対象外になる（${msg}）"
  else
    echo "  [FAIL] 系16: 入口が無いのに判定された（${msg}）" >&2
    rc=1
  fi

  # 系17: 受け付けの入口はあるが流量の制限が無い → 通知（上限に達したときの振る舞いを決める）
  local c17="app.get('/users', (req, res) => { res.send(users); });"
  msg="$(judge_rate_limit "server.js" "$c17")"
  if printf '%s' "$msg" | grep -qF '通知[上限に達したときの振る舞いを決める]'; then
    echo "  [PASS] 系17: 流量の制限が無ければ通知される（${msg}）"
  else
    echo "  [FAIL] 系17: 制限が無いのに通知されない（${msg}）" >&2
    rc=1
  fi

  # 系18: 受け付けの入口に流量の制限がある → 許可（上限に達したときの振る舞いを決める）
  local c18="app.get('/users', rateLimit(), (req, res) => { res.send(users); });"
  msg="$(judge_rate_limit "server.js" "$c18")"
  if printf '%s' "$msg" | grep -qF '許可[上限に達したときの振る舞いを決める]'; then
    echo "  [PASS] 系18: 流量の制限があれば許可される（${msg}）"
  else
    echo "  [FAIL] 系18: 制限があるのに許可されない（${msg}）" >&2
    rc=1
  fi

  # 系19: run_hook 経由で全件取得直後の絞り込みがあると exit 2 で block される
  local out19 rc19
  out19="$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"list.js","content":"const users = await User.findAll();\nconst active = users.filter(u => u.active);"},"cwd":""}' | bash "$0" 2>&1 1>/dev/null)"
  rc19=$?
  if [ "$rc19" -eq 2 ] && printf '%s' "$out19" | grep -qF '[FULL-SCAN-THEN-FILTER-BLOCK]'; then
    echo "  [PASS] 系19: run_hook経由で全件取得直後の絞り込みはexit 2でblockされる"
  else
    echo "  [FAIL] 系19: block されるはずが exit=${rc19} だった（${out19}）" >&2
    rc=1
  fi

  # 系20: run_hook 経由でtool_nameがWrite以外は対象外
  local out20 rc20
  out20="$(printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"list.js","content":"x"},"cwd":""}' | bash "$0" 2>&1 1>/dev/null)"
  rc20=$?
  if [ "$rc20" -eq 0 ] && [ -z "$out20" ]; then
    echo "  [PASS] 系20: tool_nameがWrite以外は対象外になる"
  else
    echo "  [FAIL] 系20: Write以外なのに出力または異常終了した（rc=${rc20}, ${out20})" >&2
    rc=1
  fi

  # 系21: 環境変数に理由を設定 → should_skip_with_reasonが戻り値0でタグと理由を返す
  local out21
  if out21="$(FULL_SCAN_THEN_FILTER_SKIP_REASON="テスト用の理由" should_skip_with_reason)"; then
    if printf '%s' "$out21" | grep -qF '[FULL-SCAN-THEN-FILTER-SKIP]' && printf '%s' "$out21" | grep -qF 'テスト用の理由'; then
      echo "  [PASS] 系21: 理由を設定するとタグと理由付きでskipされる（${out21}）"
    else
      echo "  [FAIL] 系21: skipされたがタグまたは理由が出力に含まれない（${out21}）" >&2
      rc=1
    fi
  else
    echo "  [FAIL] 系21: 理由を設定したのにskipされなかった" >&2
    rc=1
  fi

  # 系22: 環境変数が空文字 → should_skip_with_reasonが戻り値1を返す
  if FULL_SCAN_THEN_FILTER_SKIP_REASON="" should_skip_with_reason >/dev/null 2>&1; then
    echo "  [FAIL] 系22: 空文字なのにskipされた" >&2
    rc=1
  else
    echo "  [PASS] 系22: 環境変数が空文字ならskipされない"
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

case "${1:-}" in
  --self-test) self_test; exit $? ;;
  *) run_hook ;;
esac
