#!/usr/bin/env bash
# compare-with-previous.sh — 実行記録の台帳から最新2件を比べ、直った・壊れた・変わらないを出す
#
# 目的:
#   このリポジトリ自身の実行記録（配布対象外。または同形式の台帳）の最新2件の記録を読み、
#   判定（網羅・自立・再現・健全・第1層・第3層）ごとに前回と今回の合否を比べる。
#
# Usage:
#   compare-with-previous.sh --ledger <実行記録のパス>
#   compare-with-previous.sh --self-test
#
# オプション:
#   --ledger <path>   比較対象の実行記録ファイル（必須。--self-test 時は不要）
#   --self-test        自己テストを実行して終了する
#
# 合否の判定方法（集計行に含まれる不合格を示す数値を見る）:
#   網羅   : `欠落 <N> 件` の N が 0 なら合格
#   自立   : `違反 <N> 本` の N が 0 なら合格
#   再現   : `相違 <N> 件` の N が 0 なら合格
#   健全   : `失敗 <N> 本` の N が 0 なら合格
#   第1層 : `失敗 <N> 本` の N が 0 かつ `途中停止の疑い <M> 本` の M が 0 なら合格
#   第3層 : `失敗 <N>` の N が 0 なら合格
#   「未実行」は合否の判定から外し、変化列も「未実行」として出す。
#
# 出力:
#   前回・今回の日時、判定ごとの前回/今回/変化の表、
#   末尾に「直った: N件 / 壊れた: M件 / 変わらない: K件 / 未実行: U件」
#
# 終了コード: 壊れたものが1件でもあれば1。記録が2件未満なら「比較の対象が無い」と
#   出して0。--ledger 不在・引数不正は2。
#
# 保守責任者: 人手（ユーザー）。台帳の節の形式・判定の合否規則を変える場合は
#   本ファイルと record-verification-result.sh と self-test を同時に更新する。
# macOS bash 3.2 互換（連想配列は使わない）。
set -uo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"

# ---------------------------------------------------------------------------
# 台帳の解析
# ---------------------------------------------------------------------------

# $1: ledger  $2: 1始まりの節index（1=最新） → 節全文を標準出力へ
_cmp_extract_block() {
  local file="$1" idx="$2"
  awk -v idx="$idx" '
    /^### / { c++ }
    c==idx { print }
    c>idx { exit }
  ' "$file"
}

# $1: 行ラベル（例: 網羅）  $2: 節の全文 → 表の値セルを標準出力へ
#
# macOS 標準 awk（one true awk）は en_US.UTF-8 ロケール下で、多バイト文字列同士の
# `==` 比較が常に真を返す既知の不具合を持つ（strcoll ベースの比較が CJK 文字の
# 照合順位を区別できないため）。LC_ALL=C で awk を起動し、バイト単位の比較に
# 固定することでこの不具合を回避する。
_cmp_row_value() {
  local label="$1" block="$2"
  printf '%s\n' "$block" | LC_ALL=C awk -F'|' -v lbl="$label" '
    NF>=3 {
      col2=$2; gsub(/^ +| +$/, "", col2)
      if (col2==lbl) { val=$3; gsub(/^ +| +$/, "", val); print val; exit }
    }'
}

# $1: 数値ラベル（例: 欠落）  $2: 値文字列 → ラベル直後の整数を標準出力へ
_cmp_extract_num() {
  local label="$1" text="$2"
  printf '%s\n' "$text" | grep -oE "${label}[[:space:]]+[0-9]+" | head -1 | grep -oE '[0-9]+$'
}

_cmp_is_zero() {
  local v="$1"
  [ -n "$v" ] && [ "$v" -eq 0 ] 2>/dev/null
}

# $1: 判定ラベル  $2: 集計行の値 → 合格 / 不合格 / 未実行
_cmp_judge() {
  local label="$1" value="$2"
  if [ -z "$value" ] || [ "$value" = "未実行" ]; then
    echo "未実行"
    return
  fi

  local n m
  case "$label" in
    "網羅")
      n="$(_cmp_extract_num "欠落" "$value")"
      _cmp_is_zero "$n" && echo "合格" || echo "不合格"
      ;;
    "自立")
      n="$(_cmp_extract_num "違反" "$value")"
      _cmp_is_zero "$n" && echo "合格" || echo "不合格"
      ;;
    "再現")
      n="$(_cmp_extract_num "相違" "$value")"
      _cmp_is_zero "$n" && echo "合格" || echo "不合格"
      ;;
    "健全")
      n="$(_cmp_extract_num "失敗" "$value")"
      _cmp_is_zero "$n" && echo "合格" || echo "不合格"
      ;;
    "第 1 層")
      n="$(_cmp_extract_num "失敗" "$value")"
      m="$(_cmp_extract_num "途中停止の疑い" "$value")"
      if _cmp_is_zero "$n" && _cmp_is_zero "$m"; then echo "合格"; else echo "不合格"; fi
      ;;
    "第 3 層")
      n="$(_cmp_extract_num "失敗" "$value")"
      _cmp_is_zero "$n" && echo "合格" || echo "不合格"
      ;;
    *)
      echo "未実行"
      ;;
  esac
}

# $1: 前回の合否  $2: 今回の合否 → 直った / 壊れた / 変わらない / 未実行
_cmp_change() {
  local prev="$1" curr="$2"
  if [ "$prev" = "未実行" ] || [ "$curr" = "未実行" ]; then
    echo "未実行"
  elif [ "$prev" = "不合格" ] && [ "$curr" = "合格" ]; then
    echo "直った"
  elif [ "$prev" = "合格" ] && [ "$curr" = "不合格" ]; then
    echo "壊れた"
  else
    echo "変わらない"
  fi
}

# ---------------------------------------------------------------------------
# 比較の実行（CLI・self-test 共通の入口）
# ---------------------------------------------------------------------------

compare_run() {
  local ledger="$1"

  if [ ! -f "$ledger" ]; then
    echo "ERROR: 台帳が見つかりません: ${ledger}" >&2
    return 2
  fi

  local total
  total="$(grep -c '^### ' "$ledger" 2>/dev/null || true)"
  [ -n "$total" ] || total=0

  if [ "$total" -lt 2 ]; then
    echo "比較の対象が無い"
    return 0
  fi

  local block_new block_old ts_new ts_old
  block_new="$(_cmp_extract_block "$ledger" 1)"
  block_old="$(_cmp_extract_block "$ledger" 2)"
  ts_new="$(printf '%s\n' "$block_new" | head -1 | sed -E 's/^### *//')"
  ts_old="$(printf '%s\n' "$block_old" | head -1 | sed -E 's/^### *//')"

  local labels=("網羅" "自立" "再現" "健全" "第 1 層" "第 3 層")
  local naotta=0 kowareta=0 kawaranai=0 mijikko=0
  local rows=""
  local label prev_val curr_val prev_stat curr_stat chg

  for label in "${labels[@]}"; do
    prev_val="$(_cmp_row_value "$label" "$block_old")"
    curr_val="$(_cmp_row_value "$label" "$block_new")"
    [ -n "$prev_val" ] || prev_val="未実行"
    [ -n "$curr_val" ] || curr_val="未実行"

    prev_stat="$(_cmp_judge "$label" "$prev_val")"
    curr_stat="$(_cmp_judge "$label" "$curr_val")"
    chg="$(_cmp_change "$prev_stat" "$curr_stat")"

    case "$chg" in
      直った) naotta=$((naotta+1)) ;;
      壊れた) kowareta=$((kowareta+1)) ;;
      変わらない) kawaranai=$((kawaranai+1)) ;;
      *) mijikko=$((mijikko+1)) ;;
    esac

    rows="${rows}| ${label} | ${prev_stat} | ${curr_stat} | ${chg} |
"
  done

  echo "前回: ${ts_old}  今回: ${ts_new}"
  echo ""
  echo "| 判定 | 前回 | 今回 | 変化 |"
  echo "|---|---|---|---|"
  printf '%s' "$rows"
  echo ""
  echo "直った: ${naotta} 件 / 壊れた: ${kowareta} 件 / 変わらない: ${kawaranai} 件 / 未実行: ${mijikko} 件"

  [ "$kowareta" -eq 0 ]
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

_cmp_fixture_two() {
  local out="$1" ts_new="$2" cov_new="$3" ts_old="$4" cov_old="$5"
  cat > "$out" <<EOF
# リバース検証の実行記録（テスト用）

## 記録

### ${ts_new}

| 項目 | 値 |
|---|---|
| 版 | \`aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\` |
| 第 1 層 | 未実行 |
| 第 3 層 | 未実行 |
| 網羅 | ${cov_new} |
| 自立 | 未実行 |
| 再現 | 未実行 |
| 健全 | 未実行 |

### ${ts_old}

| 項目 | 値 |
|---|---|
| 版 | \`bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\` |
| 第 1 層 | 未実行 |
| 第 3 層 | 未実行 |
| 網羅 | ${cov_old} |
| 自立 | 未実行 |
| 再現 | 未実行 |
| 健全 | 未実行 |

この見出しの下へ、実行するたびに新しい節を追記する。
EOF
}

_cmp_fixture_one() {
  local out="$1"
  cat > "$out" <<'EOF'
# リバース検証の実行記録（テスト用）

## 記録

### 2026-08-14T00:00:00+0900

| 項目 | 値 |
|---|---|
| 版 | `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa` |
| 第 1 層 | 未実行 |
| 第 3 層 | 未実行 |
| 網羅 | 分母 82 件 / 存在 82 件 / 欠落 0 件 |
| 自立 | 未実行 |
| 再現 | 未実行 |
| 健全 | 未実行 |

この見出しの下へ、実行するたびに新しい節を追記する。
EOF
}

_cmp_self_test() {
  local run=0 ok=0 ng=0

  _case_pass() { run=$((run+1)); ok=$((ok+1)); echo "[PASS] $1 — $2"; }
  _case_fail() { run=$((run+1)); ng=$((ng+1)); echo "[FAIL] $1 — $2" >&2; }

  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/compare-with-previous-selftest.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT

  local out rc fixture

  # --- 比較-直った検出 ---
  fixture="${tmp}/naotta.md"
  _cmp_fixture_two "$fixture" "2026-08-14T10:00:00+0900" "分母 82 件 / 存在 82 件 / 欠落 0 件" \
                              "2026-08-14T09:00:00+0900" "分母 82 件 / 存在 80 件 / 欠落 2 件"
  out="$(compare_run "$fixture")"
  if printf '%s\n' "$out" | grep -qF "| 網羅 | 不合格 | 合格 | 直った |"; then
    _case_pass "比較-直った検出" "前回欠落あり・今回欠落0で「直った」になる"
  else
    _case_fail "比較-直った検出" "「直った」の行が見つからない"
  fi

  # --- 比較-壊れた検出 ---
  fixture="${tmp}/kowareta.md"
  _cmp_fixture_two "$fixture" "2026-08-14T10:00:00+0900" "分母 82 件 / 存在 79 件 / 欠落 3 件" \
                              "2026-08-14T09:00:00+0900" "分母 82 件 / 存在 82 件 / 欠落 0 件"
  out="$(compare_run "$fixture")"
  rc=$?
  if printf '%s\n' "$out" | grep -qF "| 網羅 | 合格 | 不合格 | 壊れた |"; then
    _case_pass "比較-壊れた検出" "前回欠落0・今回欠落ありで「壊れた」になる"
  else
    _case_fail "比較-壊れた検出" "「壊れた」の行が見つからない"
  fi

  # --- 終了コード-壊れた時 ---
  if [ "$rc" -eq 1 ]; then
    _case_pass "終了コード-壊れた時" "壊れたものがあれば終了コード1"
  else
    _case_fail "終了コード-壊れた時" "終了コードが1でない（rc=${rc}）"
  fi

  # --- 比較-変化なし ---
  fixture="${tmp}/kawaranai.md"
  _cmp_fixture_two "$fixture" "2026-08-14T10:00:00+0900" "分母 82 件 / 存在 82 件 / 欠落 0 件" \
                              "2026-08-14T09:00:00+0900" "分母 82 件 / 存在 82 件 / 欠落 0 件"
  out="$(compare_run "$fixture")"
  if printf '%s\n' "$out" | grep -qF "| 網羅 | 合格 | 合格 | 変わらない |"; then
    _case_pass "比較-変化なし" "前回と今回が同じなら「変わらない」になる"
  else
    _case_fail "比較-変化なし" "「変わらない」の行が見つからない"
  fi

  # --- 比較-未実行除外 ---
  fixture="${tmp}/mijikko.md"
  _cmp_fixture_two "$fixture" "2026-08-14T10:00:00+0900" "未実行" \
                              "2026-08-14T09:00:00+0900" "未実行"
  out="$(compare_run "$fixture")"
  if printf '%s\n' "$out" | grep -qF "直った: 0 件 / 壊れた: 0 件 / 変わらない: 0 件 / 未実行: 6 件"; then
    _case_pass "比較-未実行除外" "「未実行」は合否の判定から外れる"
  else
    _case_fail "比較-未実行除外" "未実行6件の集計が一致しない"
  fi

  # --- 記録1件-比較不能 ---
  fixture="${tmp}/single.md"
  _cmp_fixture_one "$fixture"
  out="$(compare_run "$fixture")"
  rc=$?
  if printf '%s\n' "$out" | grep -qF "比較の対象が無い" && [ "$rc" -eq 0 ]; then
    _case_pass "記録1件-比較不能" "記録が1件なら「比較の対象が無い」・終了コード0"
  else
    _case_fail "記録1件-比較不能" "1件時の出力または終了コードが期待と異なる（rc=${rc}）"
  fi

  rm -rf "$tmp"
  trap - EXIT

  echo "実行 ${run} 件 / 成功 ${ok} 件 / 失敗 ${ng} 件"
  [ "$ng" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 引数解析・ディスパッチ
# ---------------------------------------------------------------------------

LEDGER=""
SELF_TEST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --ledger)
      LEDGER="${2:-}"; shift 2 ;;
    --self-test)
      SELF_TEST=1; shift ;;
    *)
      echo "ERROR: 未知の引数です: $1" >&2
      exit 2
      ;;
  esac
done

if [ "$SELF_TEST" -eq 1 ]; then
  _cmp_self_test
  exit $?
fi

if [ -z "$LEDGER" ]; then
  echo "ERROR: --ledger は必須です" >&2
  echo "Usage: ${SCRIPT_NAME} --ledger <path> [--self-test]" >&2
  exit 2
fi

compare_run "$LEDGER"
exit $?
