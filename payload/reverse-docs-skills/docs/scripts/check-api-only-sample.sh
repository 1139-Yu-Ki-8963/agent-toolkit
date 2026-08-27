#!/usr/bin/env bash
# 画面を持たず API だけを持つ対象の見本(generation-engine/samples-api-only)へ、
# 既存の検査を短い名前で当てる。
#
# なぜ要るか: 台帳の検収コマンドは1文が100字を超えると文長の検査に掛かる。
#   見本のパスと検査本体のパスを並べると100字を超えるものがあるため、
#   処理をここへ移し、表からは短い名前だけを呼ぶ(check-boundary-value-scope.sh と同じ理由)。
#
# 使い方:
#   bash docs/scripts/check-api-only-sample.sh <検査名>
#   検査名: shorthand | style | adequacy | conventions | cross-reference | persistence | survey | loop | shorthand-self | adequacy-self | instruction-writing-self | line-refs | feature-count | test-docs
#
# 終了コード: 各検査本体の終了コードをそのまま返す。line-refs は行番号の記録が
#   記入規則の禁止文だけ(3件以下)なら0、それ以外は1。feature-count は機能の元データが
#   1件以上なら0。test-docs は API の単位がテスト設計書を2件持てば0。
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
S="$REPO_ROOT/generation-engine/samples-api-only"
cd "$REPO_ROOT" || exit 2
case "${1:-}" in
  shorthand) exec bash generation-engine/scripts/tests/check-shorthand-reference-declaration.sh "$S" ;;
  style) exec bash generation-engine/scripts/check-document-style-register.sh "$S" ;;
  adequacy) exec bash docs/scripts/check-customer-facing-adequacy-scope.sh "$S" ;;
  conventions) exec bash generation-engine/scripts/tests/test-portal-conventions.sh "$S" ;;
  cross-reference) exec bash generation-engine/scripts/tests/check-doc-cross-reference.sh "$S" ;;
  persistence) exec bash generation-engine/scripts/unit-list/check-manifest-persistence.sh "$S" ;;
  survey) exec bash .claude/skills/surveying-architecture-for-reverse-docs/scripts/check-architecture-survey.sh --self-test ;;
  loop) exec bash generation-engine/scripts/verification/run-verification-loop.sh --skip-layer1 --profile api-only ;;
  shorthand-self) exec bash generation-engine/scripts/tests/check-shorthand-reference-declaration.sh --self-test ;;
  adequacy-self) exec bash delivery-payload/templates/rules/checkers/check-customer-facing-adequacy.sh --self-test ;;
  instruction-writing-self) exec bash delivery-payload/templates/rules/checkers/check-instruction-writing.sh --self-test ;;
  line-refs)
    n="$(grep -r -n -E '対象コード.*行|行番号' "$S/docs/design" | grep -v -E '記載しない|記録しない|記録されていない|無い' | wc -l | tr -d ' ')"
    echo "行番号の記録(禁止文を除く): ${n} 件"; [ "$n" -eq 0 ] ;;
  feature-count)
    n="$(jq '.units|length' "$S/docs/manifests/feature-manifest.json")"; echo "機能の元データ: ${n} 件"; [ "$n" -ge 1 ] ;;
  test-docs)
    n="$(find "$S/docs/design/apis" -path '*テスト設計*' -name '*.md' | wc -l | tr -d ' ')"; echo "API のテスト設計書: ${n} 件"; [ "$n" -eq 2 ] ;;
  *) echo "usage: $0 <shorthand|style|adequacy|conventions|cross-reference|persistence|survey|loop|shorthand-self|adequacy-self|instruction-writing-self|line-refs|feature-count|test-docs>" >&2; exit 2 ;;
esac
