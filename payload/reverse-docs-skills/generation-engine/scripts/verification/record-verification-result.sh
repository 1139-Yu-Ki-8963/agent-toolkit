#!/usr/bin/env bash
# record-verification-result.sh — 検証1回分の結果を実行記録の台帳へ追記する
#
# 目的:
#   このリポジトリ自身の実行記録（配布対象外。または同形式の台帳）へ、検証1回分の結果を
#   版（コミットハッシュ）付きで追記する。既存の節は一切書き換えず、
#   `## 記録` の見出し直後へ新しい節を差し込む（新しい記録が上に来る）。
#
# Usage:
#   record-verification-result.sh --ledger <実行記録のパス> --version <コミットハッシュ> \
#     [--layer1 <集計行>] [--layer3 <集計行>] [--coverage <集計行>] \
#     [--self-contained <集計行>] [--reproducible <集計行>] [--sound <集計行>]
#   record-verification-result.sh --self-test
#
# オプション:
#   --ledger <path>        追記先の実行記録ファイル（必須。--self-test 時は不要）
#   --version <hash>       検証した版。40文字の16進でなければ終了コード1
#   --layer1 <line>        第1層の集計行（省略時は「未実行」と記録）
#   --layer3 <line>        第3層の段の集計行（省略時は「未実行」と記録）
#   --coverage <line>      網羅の集計行（省略時は「未実行」と記録）
#   --self-contained <line> 自立の集計行（省略時は「未実行」と記録）
#   --reproducible <line>  再現の集計行（省略時は「未実行」と記録）
#   --sound <line>         健全の集計行（省略時は「未実行」と記録）
#   --self-test             自己テストを実行して終了する
#
# 追記する節の形式:
#   ### <日時（ISO 8601）>
#
#   | 項目 | 値 |
#   |---|---|
#   | 版 | `<コミットハッシュ全長>` |
#   | 第 1 層 | <集計行 または 未実行> |
#   | 第 3 層 | <集計行 または 未実行> |
#   | 網羅 | <集計行 または 未実行> |
#   | 自立 | <集計行 または 未実行> |
#   | 再現 | <集計行 または 未実行> |
#   | 健全 | <集計行 または 未実行> |
#
# 終了コード: 版の形式不正は1。--ledger 不在・引数不正は2。追記成功は0。
#
# 保守責任者: 人手（ユーザー）。台帳の節の形式を変える場合は本ファイルと
#   このリポジトリ自身の実行記録（配布対象外）の「記録の形式」節と self-test を同時に更新する。
# macOS bash 3.2 互換（連想配列は使わない）。
set -uo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"
UNRUN="未実行"

# ---------------------------------------------------------------------------
# 版の形式検査
# ---------------------------------------------------------------------------

_record_version_valid() {
  local v="$1"
  [[ "$v" =~ ^[0-9A-Fa-f]{40}$ ]]
}

# ---------------------------------------------------------------------------
# 節の組み立て
# ---------------------------------------------------------------------------

_record_build_block() {
  local ts="$1" version="$2" layer1="$3" layer3="$4" coverage="$5" sc="$6" rep="$7" snd="$8"

  [ -n "$layer1" ] || layer1="$UNRUN"
  [ -n "$layer3" ] || layer3="$UNRUN"
  [ -n "$coverage" ] || coverage="$UNRUN"
  [ -n "$sc" ] || sc="$UNRUN"
  [ -n "$rep" ] || rep="$UNRUN"
  [ -n "$snd" ] || snd="$UNRUN"

  printf '### %s\n\n| 項目 | 値 |\n|---|---|\n| 版 | `%s` |\n| 第 1 層 | %s |\n| 第 3 層 | %s |\n| 網羅 | %s |\n| 自立 | %s |\n| 再現 | %s |\n| 健全 | %s |\n' \
    "$ts" "$version" "$layer1" "$layer3" "$coverage" "$sc" "$rep" "$snd"
}

# ---------------------------------------------------------------------------
# `## 記録` の見出し直後へ節を差し込む
# ---------------------------------------------------------------------------

_record_insert() {
  local ledger="$1" block="$2"

  if ! grep -q '^## 記録$' "$ledger"; then
    echo "ERROR: 台帳に \`## 記録\` の見出しが見つかりません: ${ledger}" >&2
    return 1
  fi

  local tmp blockfile
  tmp="$(mktemp "${TMPDIR:-/tmp}/record-verification-result.XXXXXX")" || return 1
  blockfile="$(mktemp "${TMPDIR:-/tmp}/record-verification-result-block.XXXXXX")" || { rm -f "$tmp"; return 1; }
  printf '%s\n' "$block" > "$blockfile"

  # awk -v は値内の改行を扱えない（BSD/macOS awk で "newline in string" エラー）ため、
  # 差し込む節は別ファイルに書き出し、getline で読み込んで挿入する。
  awk -v blockfile="$blockfile" '
    { print }
    /^## 記録$/ && !done {
      print ""
      while ((getline line < blockfile) > 0) print line
      close(blockfile)
      done=1
    }
  ' "$ledger" > "$tmp" || { rm -f "$tmp" "$blockfile"; return 1; }

  rm -f "$blockfile"
  mv "$tmp" "$ledger"
}

# ---------------------------------------------------------------------------
# 実行1回分の記録（CLI・self-test 共通の入口）
# ---------------------------------------------------------------------------

record_append() {
  local ledger="$1" version="$2" layer1="$3" layer3="$4" coverage="$5" sc="$6" rep="$7" snd="$8"

  if [ ! -f "$ledger" ]; then
    echo "ERROR: 台帳が見つかりません: ${ledger}" >&2
    return 2
  fi

  if ! _record_version_valid "$version"; then
    echo "ERROR: --version は40文字の16進でなければなりません: ${version}" >&2
    return 1
  fi

  local ts block
  ts="$(date +"%Y-%m-%dT%H:%M:%S%z")"
  block="$(_record_build_block "$ts" "$version" "$layer1" "$layer3" "$coverage" "$sc" "$rep" "$snd")"

  _record_insert "$ledger" "$block"
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

_record_self_test() {
  local run=0 ok=0 ng=0

  _case_pass() { run=$((run+1)); ok=$((ok+1)); echo "[PASS] $1 — $2"; }
  _case_fail() { run=$((run+1)); ng=$((ng+1)); echo "[FAIL] $1 — $2" >&2; }

  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/record-verification-result-selftest.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT

  local fixture="${tmp}/ledger.md"
  local v1="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  local v2="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

  # --- 追記-末尾保持 ---
  cat > "$fixture" <<'EOF'
# リバース検証の実行記録（テスト用）

## 記録

この見出しの下へ、実行するたびに新しい節を追記する。
EOF

  record_append "$fixture" "$v1" "" "" "分母 82 件 / 存在 80 件 / 欠落 2 件" "" "" "" >/dev/null
  if grep -qF "この見出しの下へ、実行するたびに新しい節を追記する。" "$fixture"; then
    _case_pass "追記-末尾保持" "既存の説明文がそのまま残る"
  else
    _case_fail "追記-末尾保持" "既存の説明文が消えた"
  fi

  # --- 未指定-未実行表記 ---
  # coverage のみ指定し、残り5項目（layer1/layer3/self-contained/reproducible/sound）を省略している。
  local unrun_count
  unrun_count="$(grep -o "未実行" "$fixture" | wc -l | tr -d ' ')"
  if [ "$unrun_count" -eq 5 ]; then
    _case_pass "未指定-未実行表記" "省略した5項目すべてが「未実行」になる"
  else
    _case_fail "未指定-未実行表記" "「未実行」の出現数が5でない（${unrun_count}）"
  fi

  # --- 見出し-位置 ---
  local next_line
  next_line="$(awk '/^## 記録$/ { getline; while ($0=="") getline; print; exit }' "$fixture")"
  if [[ "$next_line" =~ ^###\  ]]; then
    _case_pass "見出し-位置" "\`## 記録\` の直後に \`### \` の節が入る"
  else
    _case_fail "見出し-位置" "\`## 記録\` の直後が節見出しでない（${next_line}）"
  fi

  # --- 追記-新しい順 ---
  sleep 1
  record_append "$fixture" "$v2" "" "" "分母 82 件 / 存在 82 件 / 欠落 0 件" "" "" "" >/dev/null
  local line_v1 line_v2
  line_v1="$(grep -n "\`${v1}\`" "$fixture" | head -1 | cut -d: -f1)"
  line_v2="$(grep -n "\`${v2}\`" "$fixture" | head -1 | cut -d: -f1)"
  if [ -n "$line_v1" ] && [ -n "$line_v2" ] && [ "$line_v2" -lt "$line_v1" ]; then
    _case_pass "追記-新しい順" "2回目に追記した節が1回目より上に来る"
  else
    _case_fail "追記-新しい順" "追記の順序が新しい順でない（v1行=${line_v1} v2行=${line_v2}）"
  fi

  # --- 版-形式検査 ---
  local rc
  record_append "$fixture" "not-a-hash" "" "" "" "" "" "" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 1 ]; then
    _case_pass "版-形式検査" "40文字の16進でない版は終了コード1"
  else
    _case_fail "版-形式検査" "終了コードが1でない（rc=${rc}）"
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
VERSION=""
LAYER1=""
LAYER3=""
COVERAGE=""
SELF_CONTAINED=""
REPRODUCIBLE=""
SOUND=""
SELF_TEST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --ledger)
      LEDGER="${2:-}"; shift 2 ;;
    --version)
      VERSION="${2:-}"; shift 2 ;;
    --layer1)
      LAYER1="${2:-}"; shift 2 ;;
    --layer3)
      LAYER3="${2:-}"; shift 2 ;;
    --coverage)
      COVERAGE="${2:-}"; shift 2 ;;
    --self-contained)
      SELF_CONTAINED="${2:-}"; shift 2 ;;
    --reproducible)
      REPRODUCIBLE="${2:-}"; shift 2 ;;
    --sound)
      SOUND="${2:-}"; shift 2 ;;
    --self-test)
      SELF_TEST=1; shift ;;
    *)
      echo "ERROR: 未知の引数です: $1" >&2
      exit 2
      ;;
  esac
done

if [ "$SELF_TEST" -eq 1 ]; then
  _record_self_test
  exit $?
fi

if [ -z "$LEDGER" ] || [ -z "$VERSION" ]; then
  echo "ERROR: --ledger と --version は必須です" >&2
  echo "Usage: ${SCRIPT_NAME} --ledger <path> --version <hash> [--layer1 <line>] [--layer3 <line>] [--coverage <line>] [--self-contained <line>] [--reproducible <line>] [--sound <line>] [--self-test]" >&2
  exit 2
fi

record_append "$LEDGER" "$VERSION" "$LAYER1" "$LAYER3" "$COVERAGE" "$SELF_CONTAINED" "$REPRODUCIBLE" "$SOUND"
exit $?
