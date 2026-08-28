#!/usr/bin/env bash
# 課題1-219: テスト設計書の名前・配置・検証粒度を合成フィクスチャで検査する。
set -uo pipefail

# 第1層の機械検証は `--self-test)` を持つスクリプトを収集する。
case "${1:-}" in
  --self-test|"") ;;
  *) echo "usage: $0 [--self-test]" >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LAYOUT="$REPO_ROOT/delivery-payload/references/design-unit-layout.json"
OUTPUT_LAYOUT="$REPO_ROOT/delivery-payload/references/output-layout.json"
DOC_EXTRACTION="$REPO_ROOT/delivery-payload/references/doc-extraction.json"
FOLDER_DOC="$REPO_ROOT/delivery-payload/references/納品物フォルダ体系.md"
TEMPLATES="$REPO_ROOT/delivery-payload/templates/リバース検証"
SCAFFOLD="$REPO_ROOT/generation-engine/scripts/scaffold-design-unit.sh"
SCREEN_SCAFFOLD="$REPO_ROOT/generation-engine/scripts/scaffold-screen.sh"
INVENTORY="$REPO_ROOT/delivery-payload/references/deliverable-inventory.json"
SCREEN_METADATA="$REPO_ROOT/generation-engine/scripts/extract/extract-screen-metadata.sh"
VIEWPOINT_AGGREGATOR="$REPO_ROOT/generation-engine/scripts/extract/aggregate-test-viewpoints.sh"
CASE_AGGREGATOR="$REPO_ROOT/generation-engine/scripts/extract/aggregate-test-cases.sh"
PORTAL_BUILDER="$REPO_ROOT/generation-engine/scripts/build-portal.sh"

if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-design-granularity.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
  echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
  exit 2
fi
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

fail=0
pass() { printf 'PASS: %s\n' "$1"; }
fail_case() { printf 'FAIL: %s\n' "$1" >&2; fail=$((fail + 1)); }

if jq -e '
  .kinds.api.phases.basic == ["API基本設計書.md"] and
  .kinds.api.phases.detail == ["API詳細設計書.md"] and
  .kinds.api.phases.test == ["API結合テスト設計書.md", "API単体テスト設計書.md"] and
  .kinds.feature.phases.test == ["機能結合テスト設計書.md", "機能単体テスト設計書.md"] and
  ([.kinds[] | .phases.basic[], .phases.detail[]] | all(contains("テスト設計書") | not))
' "$LAYOUT" >/dev/null; then
  pass "設計phaseとテストphaseの宣言が分離されている"
else
  fail_case "設計phaseにテスト文書が混在している"
fi

mkdir -p "$tmp/out"
if bash "$SCAFFOLD" api test "$tmp/out" bid "入札" "$TEMPLATES" >/dev/null \
  && bash "$SCAFFOLD" api test "$tmp/out" bid "入札" "$TEMPLATES" >/dev/null \
  && test -f "$tmp/out/docs/design/apis/api-bid/テスト設計/API結合テスト設計書.md" \
  && test -f "$tmp/out/docs/design/apis/api-bid/テスト設計/API単体テスト設計書.md" \
  && ! find "$tmp/out/docs/design/apis/api-bid/基本設計" "$tmp/out/docs/design/apis/api-bid/詳細設計" -type f -name '*テスト設計書.md' 2>/dev/null | grep -q .; then
  pass "テスト設計書がテスト設計/だけへ生成される"
else
  fail_case "テスト設計書の生成先が不正"
fi

unit_doc="$tmp/out/docs/design/apis/api-bid/テスト設計/API単体テスト設計書.md"
api_doc="$tmp/out/docs/design/apis/api-bid/テスト設計/API結合テスト設計書.md"
detail_fixture="$tmp/out/docs/design/apis/api-bid/詳細設計/API詳細設計書.md"
basic_fixture="$tmp/out/docs/design/apis/api-bid/基本設計/API基本設計書.md"
mkdir -p "$(dirname "$detail_fixture")" "$(dirname "$basic_fixture")"
cat > "$detail_fixture" <<'EOF'
## §2 メソッド設計
| 関数・メソッド名 | 役割 |
|---|---|
| placeBid | 入札額の下限を判定する |

## §3 ロジック設計
| 関数・メソッド名 | 分岐 |
|---|---|
| placeBid | 下限未満ならエラー |
EOF
cat > "$basic_fixture" <<'EOF'
## §2.3 業務ルール
| 条件 | 外部契約 |
|---|---|
| 入札額が下限未満 | HTTPステータス400を返す |
EOF

# 合成した設計書から、それぞれの生成スキルが担当する粒度だけを抽出し、
# テンプレートの§1テスト観点表へ記入する。文書末尾への追記では検査しない。
function_name="$(awk -F '|' '/^\| placeBid / {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}' "$detail_fixture")"
http_contract="$(awk -F '|' '/HTTPステータス/ {gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3; exit}' "$basic_fixture")"
insert_viewpoint_row() {
  local file="$1" row="$2" work_file
  work_file="${file}.work"
  awk -v row="$row" '
    /^## §1 テスト観点[ \t]*$/ { in_target=1 }
    in_target && /^##[ \t]/ && $0 !~ /^## §1 テスト観点[ \t]*$/ {
      print row
      in_target=0
    }
    { print }
    END { if (in_target) print row }
  ' "$file" > "$work_file"
  mv "$work_file" "$file"
}
insert_viewpoint_row "$unit_doc" "| function-place-bid | $function_name | 下限境界を判定する | §3 ロジック設計 |"
insert_viewpoint_row "$api_doc" "| http-status-lower-bound | $http_contract | §2.3 業務ルール |"

section_one() {
  awk '/^## §1 テスト観点[ \t]*$/ { in_target=1; next } in_target && /^##[ \t]/ { exit } in_target { print }' "$1"
}
unit_function_count="$(section_one "$unit_doc" | grep -c 'placeBid' || true)"
unit_http_count="$(section_one "$unit_doc" | grep -c 'HTTPステータス' || true)"
api_function_count="$(section_one "$api_doc" | grep -c 'placeBid' || true)"
api_http_count="$(section_one "$api_doc" | grep -c 'HTTPステータス' || true)"
if [ "$unit_function_count" -gt 0 ] && [ "$unit_http_count" -eq 0 ] \
  && [ "$api_function_count" -eq 0 ] && [ "$api_http_count" -gt 0 ]; then
  pass "関数単位とAPI外部契約の観点が入れ替わっていない（関数=${unit_function_count}/${api_function_count}, HTTP=${unit_http_count}/${api_http_count}）"
else
  fail_case "関数単位とAPI外部契約の観点が混在している"
fi

if grep -q '§2 メソッド設計・§3 ロジック設計・§6 エラー処理' "$TEMPLATES/API/API単体テスト設計書.md"; then
  pass "詳細設計に対応する関数単位の様式がある"
else
  fail_case "関数単位の様式に詳細設計由来の観点がない"
fi

if grep -q '^## 検証範囲と文書と単位の対応$' "$FOLDER_DOC" \
  && grep -q '単位ごとのテスト設計書は結合テストを扱いません' "$FOLDER_DOC"; then
  pass "検証範囲の対応表と結合テストの除外が定義されている"
else
  fail_case "検証範囲の対応表または結合テストの除外がない"
fi

if grep -q '観点は機能設計書の業務フロー' "$TEMPLATES/機能/機能結合テスト設計書.md"; then
  pass "機能結合テスト設計書の名前と業務フロー由来の観点が対応する"
else
  fail_case "機能結合テスト設計書の観点が業務フローに対応しない"
fi

if jq -e '.layout.unitTestDesignDir == "テスト設計"' "$OUTPUT_LAYOUT" >/dev/null; then
  pass "テスト設計ディレクトリがoutput-layoutに定義されている"
else
  fail_case "unitTestDesignDirの定義が不正"
fi

mkdir -p "$tmp/screen-out"
if bash "$SCREEN_SCAFFOLD" "$tmp/screen-out" orders "受注一覧" "$TEMPLATES" >/dev/null \
  && bash "$SCREEN_SCAFFOLD" --verify "$tmp/screen-out" orders >/dev/null \
  && test -f "$tmp/screen-out/docs/design/screens/screen-orders/テスト設計/画面結合テスト設計書.md" \
  && test -f "$tmp/screen-out/docs/design/screens/screen-orders/テスト設計/画面単体テスト設計書.md" \
  && test -f "$tmp/screen-out/docs/design/screens/screen-orders/テスト設計/操作シナリオ仕様書.md"; then
  pass "合成画面がAPIと同じテスト設計/の2文書体系で生成される"
else
  fail_case "合成画面のテスト設計体系が不正"
fi

if jq -e '
  [.kinds | to_entries[] | .value.phases.test | map(select(endswith("テスト設計書.md")))] as $sets
  | ($sets | length) == 7
  and all($sets[]; length == 2)
  and (.kinds.screen.screenOnlyTestDocuments == ["操作シナリオ仕様書.md"])
' "$LAYOUT" >/dev/null \
  && jq -e '
    [.items[] | select(.kind == "screen" or .kind == "api" or .kind == "table" or .kind == "batch" or .kind == "report" or .kind == "external" or .kind == "feature") | .unitTestDocuments | length] as $counts
    | ($counts | length) == 7 and all($counts[]; . == 2)
  ' "$INVENTORY" >/dev/null; then
  pass "7種の単位ごとのテスト設計書数が2件で一致する（画面固有1件を除く）"
else
  fail_case "7種のテスト設計書数が一致しない"
fi

if ! find "$TEMPLATES/画面" -type f \( -name '単体テスト観点表.md' -o -name '結合テスト観点表.md' -o -name '単体テスト仕様書.md' -o -name '結合テスト仕様書.md' \) | grep -q . \
  && test "$(find "$TEMPLATES" -mindepth 2 -maxdepth 2 -type f -name '*結合テスト仕様書*' | wc -l | tr -d ' ')" -eq 1 \
  && test -f "$TEMPLATES/プロジェクト共通/結合テスト仕様書.md"; then
  pass "旧4文書と単位配下の結合テスト文書がなく、上位の結合テスト仕様書だけがある"
else
  fail_case "結合テスト文書が上位1冊に限定されていない"
fi

screen_test="$TEMPLATES/画面/テスト設計/画面結合テスト設計書.md"
screen_unit_test="$TEMPLATES/画面/テスト設計/画面単体テスト設計書.md"
if grep -q '### 手動観点' "$screen_test" \
  && grep -q '### 往復検証観点' "$screen_test" \
  && grep -q 'L1起動、L2構造スナップショット、L3画素比較、L4コンソールエラー集合、L5操作シーケンス突合' "$screen_test" \
  && grep -q '乖離分類' "$screen_test" \
  && grep -q '実装後のテストファイル参照' "$screen_test" \
  && grep -q 'TDD二重ループの内側' "$screen_unit_test" \
  && grep -q '乖離分類' "$screen_unit_test" \
  && grep -q '実装後のテストファイル参照' "$screen_unit_test"; then
  pass "旧画面4文書の手動・往復・乖離・TDD・実装参照契約が新2文書へ統合されている"
else
  fail_case "旧画面4文書の重要な検証契約が新2文書へ統合されていない"
fi

scenario="$TEMPLATES/画面/テスト設計/操作シナリオ仕様書.md"
if grep -q '^screen_test_design: ./画面結合テスト設計書.md$' "$scenario" \
  && grep -q '対応往復検証観点キー' "$scenario" \
  && grep -q '対応画面テストケースキー' "$scenario" \
  && grep -q '^## シナリオ別仕様$' "$scenario" \
  && grep -q '^## 機械実行用YAML$' "$scenario" \
  && grep -q 'roundtrip_viewpoint_key:' "$scenario" \
  && grep -q 'screen_test_case_key:' "$scenario" \
  && grep -q 'click.*fill.*select.*check.*uncheck.*press.*navigate' "$scenario"; then
  pass "画面固有の操作シナリオが往復観点・ケース・手順・YAMLの機械契約を保持する"
else
  fail_case "画面固有の操作シナリオの機械契約が欠落している"
fi

frontmatter_ok=1
for unit_template in \
  "$TEMPLATES/API/API単体テスト設計書.md" \
  "$TEMPLATES/テーブル/テーブル単体テスト設計書.md" \
  "$TEMPLATES/バッチ/バッチ単体テスト設計書.md" \
  "$TEMPLATES/帳票/帳票単体テスト設計書.md" \
  "$TEMPLATES/外部連携/外部連携単体テスト設計書.md" \
  "$TEMPLATES/機能/機能単体テスト設計書.md"; do
  if [ "$(head -1 "$unit_template")" != '---' ] \
    || ! grep -q '^source_ref:' "$unit_template" \
    || ! grep -q '^unit_kind:' "$unit_template" \
    || ! grep -q '^status: draft$' "$unit_template"; then
    frontmatter_ok=0
  fi
done
if [ "$frontmatter_ok" -eq 1 ] \
  && grep -q '^source_design:' "$TEMPLATES/画面/テスト設計/画面単体テスト設計書.md" \
  && grep -q '^status: draft$' "$TEMPLATES/画面/テスト設計/画面単体テスト設計書.md"; then
  pass "7種の単体テスト設計書が対象・由来・状態を追跡するfrontmatterを持つ"
else
  fail_case "単体テスト設計書のfrontmatterが7種で揃っていない"
fi

skill_contract_ok=1
for skill in \
  "$REPO_ROOT/.claude/skills/generating-table-logical-model-for-reverse-docs/SKILL.md" \
  "$REPO_ROOT/.claude/skills/generating-batch-basic-design-for-reverse-docs/SKILL.md" \
  "$REPO_ROOT/.claude/skills/generating-report-basic-design-for-reverse-docs/SKILL.md" \
  "$REPO_ROOT/.claude/skills/generating-external-basic-design-for-reverse-docs/SKILL.md" \
  "$REPO_ROOT/.claude/skills/generating-feature-design-for-reverse-docs/SKILL.md"; do
  if ! grep -q '2文書とも本スキルの成果物' "$skill" \
    || ! grep -q '^## Phase 4: .*テスト設計書・.*単体テスト設計書の執筆$' "$skill" \
    || ! grep -q '`DONE`.*単体テスト設計書' "$skill" \
    || ! grep -q '| \*\*Goal\*\* |.*単体テスト設計書' "$skill"; then
    skill_contract_ok=0
  fi
done
api_basic_skill="$REPO_ROOT/.claude/skills/generating-api-basic-design-for-reverse-docs/SKILL.md"
api_detail_skill="$REPO_ROOT/.claude/skills/generating-api-detail-design-for-reverse-docs/SKILL.md"
if [ "$skill_contract_ok" -eq 1 ] \
  && grep -q '画面結合テスト設計書・画面単体テスト設計書・操作シナリオ仕様書' "$REPO_ROOT/.claude/skills/generating-reverse-detailed-design/SKILL.md" \
  && grep -q '^## Phase 4: API結合テスト設計書の執筆$' "$api_basic_skill" \
  && ! grep -q 'API単体テスト設計書' "$api_basic_skill" \
  && grep -q '| 出力ファイル | `API詳細設計書.md` | `API単体テスト設計書.md` |' "$api_detail_skill" \
  && grep -q '本スキルが執筆するのは後者だけ' "$api_detail_skill"; then
  pass "7種の2設計書に生成責務があり、APIは基本設計と詳細設計で一意に分担する"
else
  fail_case "7種の2設計書に生成責務の欠落または二重所有がある"
fi

if grep -q 'テスト設計/画面単体テスト設計書.md' "$SCREEN_METADATA" \
  && grep -q 'テスト項目書/単体テスト仕様書.md' "$SCREEN_METADATA" \
  && grep -q 'テスト設計/画面結合テスト設計書.md' "$VIEWPOINT_AGGREGATOR" \
  && grep -q '詳細設計/結合テスト観点表.md' "$VIEWPOINT_AGGREGATOR" \
  && grep -q 'テスト設計/画面単体テスト設計書.md' "$CASE_AGGREGATOR" \
  && grep -q 'テスト項目書/結合テスト仕様書.md' "$CASE_AGGREGATOR" \
  && grep -q 'テスト設計/画面結合テスト設計書.md' "$PORTAL_BUILDER" \
  && grep -q 'テスト項目書/単体テスト仕様書.md' "$PORTAL_BUILDER"; then
  pass "抽出・集約・ポータルが新配置を参照し、既存生成物の旧配置をfallbackする"
else
  fail_case "抽出・集約・ポータルの新配置参照または旧配置fallbackが欠落している"
fi

if jq -e '
  (.excluded.screen | type == "string" and length > 0)
  and .separateKindContracts.screen.testDocuments == {
    "externalBehavior": "画面結合テスト設計書.md",
    "functionUnit": "画面単体テスト設計書.md",
    "screenOnly": ["操作シナリオ仕様書.md"],
    "directoryKey": "unitTestDesignDir"
  }
  and (.kinds | has("screen") | not)
' "$DOC_EXTRACTION" >/dev/null; then
  pass "画面テスト文書は抽出契約へ定義され、画面マニフェストの別生成経路を維持する"
else
  fail_case "画面テスト文書の抽出契約または画面マニフェストの別生成経路が不正"
fi

if jq -e '.layout.projectIntegrationTest == "docs/test-cases/結合テスト仕様書.md"' "$OUTPUT_LAYOUT" >/dev/null \
  && grep -q 'docs/test-cases/結合テスト仕様書.md' "$FOLDER_DOC" \
  && ! grep -q 'テスト項目書/結合テスト仕様書.md' "$FOLDER_DOC"; then
  pass "複数単位の結合テスト配置が上位階層の同一パスで定義されている"
else
  fail_case "複数単位の結合テスト配置が定義間で一致しない"
fi

[ "$fail" -eq 0 ]
