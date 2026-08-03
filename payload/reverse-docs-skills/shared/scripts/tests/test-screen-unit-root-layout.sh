#!/usr/bin/env bash
# screenUnitRoot第1垂直スライスのproducer/consumer黒箱E2E。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/unit-root-layout-e2e.XXXXXX")"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
docs="$tmp/docs"
portal="$tmp/portal"
mkdir -p "$docs" "$portal"
cat > "$docs/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "screenUnitRoot": "スクリーン" } }
JSON

bash "$REPO_ROOT/shared/scripts/scaffold-screen.sh" "$docs" e2e-root "配置上書き画面" >/dev/null
bash "$REPO_ROOT/shared/scripts/scaffold-screen.sh" --verify "$docs" e2e-root >/dev/null

# 旧既定rootには同型decoyを置く。consumerが両方を読むと件数・screenKey検査が失敗する。
mkdir -p "$docs/画面/screen-decoy"
cp -R "$docs/スクリーン/screen-e2e-root/." "$docs/画面/screen-decoy/"

cat > "$docs/スクリーン/screen-e2e-root/詳細設計/単体テスト観点表.md" <<'MD'
# 単体
| 観点 | 期待結果 |
|---|---|
| 配置上書き | 読み込まれる |
MD
cat > "$docs/スクリーン/screen-e2e-root/詳細設計/結合テスト観点表.md" <<'MD'
# 結合
| 観点 | 期待結果 |
|---|---|
| 配置連結 | 読み込まれる |
MD
cat > "$docs/スクリーン/screen-e2e-root/テスト項目書/単体テスト仕様書.md" <<'MD'
| キー | 対応観点キー | 入力値 | 期待結果（アサーション） |
|---|---|---|---|
| root-unit | 配置上書き | input | pass |
MD
cat > "$docs/スクリーン/screen-e2e-root/テスト項目書/結合テスト仕様書.md" <<'MD'
| キー | 対応観点キー | 操作手順 | 入力値 | 期待結果（アサーション） |
|---|---|---|---|---|
| root-integration | 配置連結 | click | input | pass |
MD
cat > "$docs/スクリーン/screen-e2e-root/テスト項目書/操作シナリオ仕様書.md" <<'MD'
## シナリオ一覧表
| シナリオ名 | 対応往復検証観点キー | 前提条件 |
|---|---|---|
| root-scenario | 配置往復 | ready |

### root-scenario
**期待結果**

pass
MD

# portal topのsource_ref集計はportal出力先ではなく定義側docsを読む。
sed -i.bak '1i\
---\
source_ref: dddddddddddddddddddddddddddddddddddddddd\
---' "$docs/スクリーン/screen-e2e-root/詳細設計/画面詳細設計書.md"
rm -f "$docs/スクリーン/screen-e2e-root/詳細設計/画面詳細設計書.md.bak"
# 通常のCRLF frontmatterでも実値を読む。
perl -pi -e 'if ($. <= 3) { s/\n/\r\n/ }' \
  "$docs/スクリーン/screen-e2e-root/詳細設計/画面詳細設計書.md"
printf '\nsource_ref: ffffffffffffffffffffffffffffffffffffffff\n' \
  >> "$docs/スクリーン/screen-e2e-root/詳細設計/画面詳細設計書.md"
mkdir -p "$docs/スクリーン/archive/詳細設計"
cat > "$docs/スクリーン/archive/詳細設計/画面詳細設計書.md" <<'MD'
---
source_ref: eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
---
# screen unitではないdecoy
MD
mkdir -p "$docs/スクリーン/screen-no-ref/詳細設計"
printf '%s' $'---\nsource_repo: sample\r\n---\r\n# source_refなし\nsource_ref: gggggggggggggggggggggggggggggggggggggggg\n' \
  > "$docs/スクリーン/screen-no-ref/詳細設計/画面詳細設計書.md"

cases="$tmp/cases.json"
viewpoints="$tmp/viewpoints.json"
bash "$REPO_ROOT/shared/scripts/extract/aggregate-test-cases.sh" "$docs" "$cases"
bash "$REPO_ROOT/shared/scripts/extract/aggregate-test-viewpoints.sh" "$docs" "$viewpoints"
jq -e '.summary.totalCount == 3 and ([.units[].screenKey] | unique == ["screen-e2e-root"])' "$cases" >/dev/null \
  || { echo "FAIL: aggregate-test-cases result" >&2; jq . "$cases" >&2; exit 1; }
jq -e '.summary.totalCount == 2 and ([.units[].screenKey] | unique == ["screen-e2e-root"])' "$viewpoints" >/dev/null \
  || { echo "FAIL: aggregate-test-viewpoints result" >&2; jq . "$viewpoints" >&2; exit 1; }

bash "$REPO_ROOT/shared/scripts/build-portal.sh" "$REPO_ROOT" "$docs" "$portal" \
  --generated-at 2026-08-02T00:00:00Z >/dev/null
test -f "$docs/スクリーン/screen-e2e-root/基本設計/画面基本設計書.html"
test -f "$docs/スクリーン/screen-e2e-root/詳細設計/画面詳細設計書.html"
test ! -f "$docs/画面/screen-decoy/基本設計/画面基本設計書.html"
test ! -f "$docs/画面/screen-decoy/詳細設計/画面詳細設計書.html"
grep -q 'コミット番号: ddddddd' "$portal/index.html"
! grep -q 'eeeeeee' "$portal/index.html"
! grep -q 'fffffff' "$portal/index.html"
! grep -q 'ggggggg' "$portal/index.html"
detail_footer="$(grep -o '<span id="pt-footer-commit">[^<]*</span>' \
  "$docs/スクリーン/screen-e2e-root/詳細設計/画面詳細設計書.html")"
printf '%s' "$detail_footer" | grep -q 'コミット番号: ddddddd'
! printf '%s' "$detail_footer" | grep -q 'fffffff'
no_ref_footer="$(grep -o '<span id="pt-footer-commit">[^<]*</span>' \
  "$docs/スクリーン/screen-no-ref/詳細設計/画面詳細設計書.html")"
! printf '%s' "$no_ref_footer" | grep -q 'コミット番号:'
! printf '%s' "$no_ref_footer" | grep -q 'ggggggg'

# 同じdocs fixtureを状態判定へ渡し、旧rootのdecoyではなくcustom rootの不足を判定する。
mkdir -p "$docs/規約" "$docs/一覧/画面一覧" "$docs/プロジェクト共通"
cat > "$docs/プロジェクト共通/アーキテクチャ調査書.md" <<'MD'
# アーキテクチャ調査書
### サイト一覧
| サイトキー | ルート |
|---|---|
| main | . |
MD
cat > "$docs/一覧/excluded-kinds.json" <<'JSON'
{"presentKinds":["screen"],"excludedKinds":[]}
JSON
: > "$docs/一覧/画面一覧/画面一覧.html"
for file in コーディング規約 命名規約 ディレクトリ構成規約 コンポーネント設計規約; do : > "$docs/規約/$file.md"; done
for file in 共通設計書 メッセージ定義書 DESIGN 基盤設計 UI共通設計 データ設計; do : > "$docs/プロジェクト共通/$file.md"; done
: > "$docs/index.html"
for file in 用語辞書 技術スタック 画面遷移図 ER図 環境構築手順 リリースノート デザインシステム コンポーネント棚卸し アイコンカタログ 状態遷移図; do : > "$docs/$file.html"; done
state="$(bash "$REPO_ROOT/.claude/skills/orchestrating-reverse-docs-flow/scripts/resolve-flow-state.sh" "$docs" --screen-id e2e-root)"
[ "$state" = "シーケンス図未生成（任意）" ] || { echo "FAIL: same fixture flow state: $state" >&2; exit 1; }

# 同じcustom rootへsample rawのscreen-home文書を置き、rebuildへ明示してext linkを検査する。
mkdir -p "$docs/スクリーン/screen-home/基本設計" "$docs/スクリーン/screen-home/詳細設計" "$docs/スクリーン/screen-home/テスト項目書"
: > "$docs/スクリーン/screen-home/基本設計/画面基本設計書.html"
: > "$docs/スクリーン/screen-home/詳細設計/画面詳細設計書.html"
: > "$docs/スクリーン/screen-home/シーケンス図.html"
: > "$docs/スクリーン/screen-home/テスト項目書/単体テスト仕様書.md"
raw="$REPO_ROOT/shared/samples/一覧/画面一覧/screen-manifest.json"
api="$tmp/api-manifest.json"
node - "$REPO_ROOT/shared/samples/一覧/API一覧/API一覧.html" "$api" <<'NODE'
const fs=require("fs"); const s=fs.readFileSync(process.argv[2],"utf8");
const m=s.match(/<script\b(?=[^>]*type=["']application\/json["'])(?=[^>]*id=["']unit-manifest["'])[^>]*>([\s\S]*?)<\/script>/i);
if(!m) throw new Error("unit-manifest not found");
fs.writeFileSync(process.argv[3],JSON.stringify(JSON.parse(m[1]),null,2)+"\n");
NODE
mkdir -p "$docs/一覧/画面一覧"
cp "$raw" "$docs/一覧/画面一覧/screen-manifest.json"
bash "$REPO_ROOT/shared/scripts/unit-list/rebuild-screen-derived-pages.sh" \
  --raw-manifest "$docs/一覧/画面一覧/screen-manifest.json" --target-repo "$REPO_ROOT" \
  --api-manifest "$api" --output-root "$docs" --generated-at 2026-08-02T00:00:00Z \
  --project-name e2e --design-docs-dir "$docs/スクリーン" >/dev/null
jq -e '.screens[] | select(.screenKey == "home") | .designDocPath == "../../スクリーン/screen-home/基本設計/画面基本設計書.html" and .detailDocPath == "../../スクリーン/screen-home/詳細設計/画面詳細設計書.html" and .sequencePath == "../../スクリーン/screen-home/シーケンス図.html" and .testCasePath == "../../スクリーン/screen-home/テスト項目書/単体テスト仕様書.md"' \
  "$docs/一覧/画面一覧/screen-manifest.ext.json" >/dev/null
if jq -e '.. | strings | select(contains("../../画面/screen-home/"))' "$docs/一覧/画面一覧/screen-manifest.ext.json" >/dev/null; then
  echo "FAIL: ext manifest retained old 画面/screen-home links" >&2
  exit 1
fi

echo "PASS: screenUnitRoot=スクリーン scaffold→verify→aggregate2本→portal→state→rebuild E2E"
