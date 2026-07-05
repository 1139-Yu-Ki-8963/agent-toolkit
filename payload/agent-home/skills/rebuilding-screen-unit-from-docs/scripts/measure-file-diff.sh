#!/usr/bin/env bash
# measure-file-diff.sh — Phase 5 の5計測のうち import diff / style diff / 全体diff /
# 実質diff の4項目を算出する。
#
# 「単体テスト仕様の検査」（禁止パターン・import・コンポーネント/API利用）は
# 本スクリプトの対象外。Phase 5 でメインが別途実施する。
#
# 用途:
#   rebuilding-screen-unit-from-docs スキル Phase 5 の差分比較。生成ファイルと原本ファイル
#   （Phase 2 の白紙化前コミットから git show で取り出した一時ファイル）を突合し、
#   import diff だけでの合格判定を防ぐため4計測を必ず一括出力する。
#
# 引数:
#   $1 = 生成ファイル（generated-file）
#   $2 = 原本ファイル（original-file）
#
# 標準出力（key=value を1行ずつ・機械可読）:
#   import_diff_lines=<整数>
#   style_diff_lines=<整数>
#   total_diff_lines=<整数>
#   substantive_diff_lines=<整数>
#   verdict=PASS|FAIL
#
# 合格条件（verdict=PASS）:
#   import_diff_lines == 0 && style_diff_lines == 0 && substantive_diff_lines <= 20
#
# 算出方法（heuristic）:
#   import_diff_lines      : 両ファイルから `^\s*import ` 行を抽出→前後空白除去→
#                            ソート→diff の差分行数（`^[<>]` 行の数）
#   style_diff_lines       : className / style 属性・`const *Style` 系変数・
#                            16進カラーコード・px/rem/em/vh/vw 数値を含む行を
#                            抽出→前後空白除去→ソート→diff の差分行数
#   total_diff_lines       : diff によるファイル全体の差分行数（参考値。
#                            合格判定には使わない）
#   substantive_diff_lines : コメント行（// ・/* ・*）と空行を除外し、前後空白を
#                            除去した上での diff 差分行数
#
# 前後空白除去について: 条件分岐の書き方（早期return vs 三項演算子等）の違いで
# ネスト段数がずれると、内容が同一の行でも行頭インデント幅だけが異なり、素朴な
# 文字列比較では誤って差分と判定される。行頭・行末の空白を除去してから比較する
# ことで、この誤検出を防ぐ（インデント自体の一致・不一致は判定対象にしない）。
#
# 終了コード:
#   引数不足・ファイル不在 = 1（stderr にメッセージ） / 正常時 = 0
#
# 使い方:
#   ./measure-file-diff.sh <generated-file> <original-file>
#
# macOS bash 3.2 互換: mapfile 等の bash4 専用機能は使わない。

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "使い方: $0 <generated-file> <original-file>" >&2
  exit 1
fi

GENERATED="$1"
ORIGINAL="$2"

if [ ! -f "$GENERATED" ]; then
  echo "エラー: 生成ファイルが存在しません: $GENERATED" >&2
  exit 1
fi
if [ ! -f "$ORIGINAL" ]; then
  echo "エラー: 原本ファイルが存在しません: $ORIGINAL" >&2
  exit 1
fi

# 行頭・行末の空白を除去する。インデント幅だけが異なる（条件分岐の書き方の違い等で
# ネスト段数がずれる）行を、内容が同一なら差分として誤検出しないための共通ヘルパー。
trim_whitespace() {
  sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

# --- import diff ---
extract_imports() {
  grep -E '^[[:space:]]*import ' "$1" 2>/dev/null | trim_whitespace | sort -u || true
}
IMPORT_DIFF_LINES=$(diff <(extract_imports "$ORIGINAL") <(extract_imports "$GENERATED") | grep -cE '^[<>]' || true)

# --- style diff ---
# className / style 属性、`const *Style` 系変数、16進カラーコード、
# px/rem/em/vh/vw 数値を含む行をスタイル定数行とみなす。
STYLE_PATTERN='className|style[[:space:]]*=|const .*[Ss]tyle|#[0-9a-fA-F]{3,8}|[0-9]+(px|rem|em|vh|vw)'
extract_style_lines() {
  grep -E "$STYLE_PATTERN" "$1" 2>/dev/null | trim_whitespace | sort -u || true
}
STYLE_DIFF_LINES=$(diff <(extract_style_lines "$ORIGINAL") <(extract_style_lines "$GENERATED") | grep -cE '^[<>]' || true)

# --- total diff（参考値） ---
TOTAL_DIFF_LINES=$(diff "$ORIGINAL" "$GENERATED" | grep -cE '^[<>]' || true)

# --- substantive diff（コメント・空行除外） ---
strip_noise() {
  grep -vE '^[[:space:]]*(//|/\*|\*)' "$1" 2>/dev/null | grep -vE '^[[:space:]]*$' | trim_whitespace || true
}
SUBSTANTIVE_DIFF_LINES=$(diff <(strip_noise "$ORIGINAL") <(strip_noise "$GENERATED") | grep -cE '^[<>]' || true)

# --- verdict ---
if [ "$IMPORT_DIFF_LINES" -eq 0 ] && [ "$STYLE_DIFF_LINES" -eq 0 ] && [ "$SUBSTANTIVE_DIFF_LINES" -le 20 ]; then
  VERDICT="PASS"
else
  VERDICT="FAIL"
fi

echo "import_diff_lines=$IMPORT_DIFF_LINES"
echo "style_diff_lines=$STYLE_DIFF_LINES"
echo "total_diff_lines=$TOTAL_DIFF_LINES"
echo "substantive_diff_lines=$SUBSTANTIVE_DIFF_LINES"
echo "verdict=$VERDICT"
