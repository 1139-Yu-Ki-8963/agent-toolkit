#!/usr/bin/env bash
# check-viewpoint-coverage.sh — 観点網羅の機械ゲート
#
# 単体テスト観点表の観点キー集合と、テストコード内の観点キー言及を突合し、
# テストコードで言及されていない観点キー（未実装の疑い）を検出する。
# $1 = 単体テスト観点表.md, $2 = テストコードのパス（ファイル or ディレクトリ）
#
# 「言及＝実装」ではないため、本ゲートは「観点キーがテストコードに言及されているか」
# のみを機械保証する。実装済みかはテスト全件PASS（P5 の単体テスト仕様の検査）との
# 組み合わせで担保する。
#
# 終了コード: 未言及が1件でもあれば exit 1 / 全キー言及済みなら exit 0 /
#            引数不足・ファイル不在は exit 1（stderr にメッセージ）
#
# 設計判断（ADR）:
#   必要性: 観点表の各観点が実際にテストコードへ落ちたかは従来人手レビュー依存だった。
#           観点表が「テストコードがコメントで観点キーを参照する」規約を既に持つため、
#           キー言及の有無は機械照合でき、網羅漏れを preflight で機械的に落とせる。
#   代替案を採用しなかった理由:
#     - AST/カバレッジ計測: 言語・ランナー依存が重く、観点の粒度がカバレッジ行と不一致
#     - 観点キー→テスト名の完全一致要求: 命名自由度を奪い運用が硬直する
#     - frontmatter に手書き対応表: 二重管理で腐敗する
#   保守責任者: 人手（ユーザー）
#   廃棄条件: 観点対応づけが AST/カバレッジ由来で自動化された時、または観点表の
#             「コメント参照」規約が廃止された時
#
# 使い方:
#   ./check-viewpoint-coverage.sh <単体テスト観点表.md> <テストコードのパス>
#
# macOS bash 3.2 互換: mapfile 等の bash4 専用機能は使わない。

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "使い方: $0 <単体テスト観点表.md> <テストコードのパス>" >&2
  exit 1
fi

SHEET="$1"
CODE="$2"

if [ ! -f "$SHEET" ]; then
  echo "エラー: 観点表がありません: $SHEET" >&2
  exit 1
fi
if [ ! -e "$CODE" ]; then
  echo "エラー: テストコードパスがありません: $CODE" >&2
  exit 1
fi

# 観点表 col1 抽出（「## 観点表」セクション本文。ヘッダー行・区切り行スキップ。
# 角括弧 <> とバッククォートを除去して意味キーだけにする）
SHEET_KEYS="$(awk '
  $0 ~ /^## 観点表/ { ins=1; next }
  ins && /^## / { exit }
  ins && /^\|/ {
    row++
    if (row == 1) next
    if (row == 2 && $0 ~ /^\|[ \t:|\-]+$/) next
    n = split($0, c, "|"); v = c[2]
    gsub(/^[ \t]+|[ \t]+$/, "", v); gsub(/[`<>]/, "", v)
    if (v != "" && v !~ /^-+$/) print v
  }' "$SHEET" | sort -u)"
if [ -z "$SHEET_KEYS" ]; then
  echo "エラー: 観点表にキーがありません: $SHEET" >&2
  exit 1
fi

# テストコード内でリテラル言及されているキー集合（固定文字列マッチ）
MENTIONED="$(while IFS= read -r k; do
  [ -z "$k" ] && continue
  grep -RqF -- "$k" "$CODE" 2>/dev/null && printf '%s\n' "$k"
done <<<"$SHEET_KEYS" | sort -u)"

MISSING="$(comm -23 <(printf '%s\n' "$SHEET_KEYS") <(printf '%s\n' "$MENTIONED") || true)"
if [ -n "$MISSING" ]; then
  echo "違反: テストコードで言及されていない観点キー:" >&2
  printf '%s\n' "$MISSING" | sed 's/^/  - /' >&2
  exit 1
fi
echo "観点網羅 OK（全 $(printf '%s\n' "$SHEET_KEYS" | grep -c .) キーがテストコードで言及されています）"
