#!/usr/bin/env bash
# screenUnitRoot第1垂直スライスのproducer/consumer黒箱E2E。
set -euo pipefail

# 第1層の集約（generation-engine/scripts/verification/run-layer-machine-checks.sh）は、
# 本文に "--self-test)" を持つ .sh を対象として集める。このスクリプトは引数を取らず、
# 実行そのものが検査になる形のため、引数を見る分岐が無く集約から漏れていた。集約に
# 拾わせるための受け口であり、渡されても渡されなくても動きは変わらない。この分岐を
# 消すと集約から外れ、この検査は二度と走らなくなる。
case "${1:-}" in --self-test) ;; esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/unit-root-layout-e2e.XXXXXX")"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
docs="$tmp/docs"
portal="$tmp/portal"
mkdir -p "$docs" "$portal"
cat > "$docs/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": {
  "screenUnitRoot": "スクリーン",
  "screenViewRoot": "スクリーン",
  "commonRoot": "プロジェクト共通",
  "excludedKinds": "一覧/excluded-kinds.json",
  "screenManifest": "一覧/画面一覧/screen-manifest.json",
  "screenManifestExt": "一覧/画面一覧/screen-manifest.ext.json",
  "screenRegistry": "一覧/reverse-screen-registry.yml",
  "surveyDoc": "プロジェクト共通/アーキテクチャ調査書.md",
  "commonDesignDoc": "プロジェクト共通/共通設計書.md",
  "messageDoc": "プロジェクト共通/メッセージ定義書.md",
  "designDoc": "プロジェクト共通/DESIGN.md",
  "foundationDoc": "プロジェクト共通/基盤設計.md",
  "uiCommonDoc": "プロジェクト共通/UI共通設計.md",
  "dataDesignDoc": "プロジェクト共通/データ設計.md"
} }
JSON

bash "$REPO_ROOT/generation-engine/scripts/scaffold-screen.sh" "$docs" e2e-root "配置上書き画面" >/dev/null
bash "$REPO_ROOT/generation-engine/scripts/scaffold-screen.sh" --verify "$docs" e2e-root >/dev/null

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
cat > "$docs/スクリーン/screen-e2e-root/テスト設計/画面単体テスト設計書.md" <<'MD'
## テスト対象

対象は1プロセス内で完結する関数・フック・メソッド・コンポーネント単位の処理です。既存コードに実在する対象名で記載する。

## テストの粒度と自動化の方針

単体観点はすべて自動化し、TDD二重ループの内側（red、green、refactor）で消化する。実装後はテストコードをケースの正とし、各ケースのテスト参照へ `file::テスト名` を記録する。自動化できない観点は `画面テスト設計書.md` の手動観点へ移す。

## 本書が扱わない範囲

1画面の操作・表示・領域間連携・単画面ブラウザ検証は `画面テスト設計書.md`、単一画面内の操作の流れは `操作シナリオ仕様書.md` が扱う。複数の画面・機能・APIにまたがる結合テストはプロジェクト全体の `docs/test-cases/結合テスト仕様書.md` が担う。UIの見た目はモックと `DESIGN.md`、三点照合の手順と判定記録は往復検証レポートを正とする。

## §1 テスト観点

| キー | 対象 | 観点 | 由来する詳細設計書の章 | 区分 | 乖離分類 | テスト参照（実装後） |
|---|---|---|---|---|---|---|
| 配置上書き | fixture | 配置上書きの観点 | 詳細設計 | 正常 | 該当なし | fixture.test |

### 観点の導出元

見出し「観点の導出元」配下の表はfixtureの意図的な仕様（本コメントは--self-testが参照しないため触らない）。
データ行の1列目を `<...>` 形式にしているのはaggregate-test-viewpoints.shのプレースホルダ除外規則
（データ行の1列目が `<...>` 形式ならスキップ）を使い、totalCount==2の検査を壊さないための対応。

| 設計書セクション | 導出する観点 |
|---|---|
| `<業務ルール>` | `<モード切替、権限判定>` |
| `<状態管理>` | `<状態遷移、表示分岐>` |
| `<エラーハンドリング>` | `<入力検証、境界値、異常系>` |
| `<画面遷移仕様>` | `<遷移条件の判定>` |

## §2 テストケース一覧

| キー | 対応観点キー | 入力値・操作 | 期待結果（アサーション） | 実装後のテストファイル参照 |
|---|---|---|---|---|
| root-unit | 配置上書き | input | pass | fixture.test |

## §3 入力条件

| キー | データ | 用途 |
|---|---|---|
| root-input | input | root-unitケースの前提値 |

## §4 期待結果

期待結果は戻り値、状態変化、呼び出し、副作用、または描画結果として機械判定できる形で記載する。

## §5 異常系

| 観点のキー | 条件 | 期待結果 |
|---|---|---|
| 配置上書き | 不正入力 | 例外 |

## §6 境界値

| 観点のキー | 境界 | 期待結果 |
|---|---|---|
| 配置上書き | 下限 | 結果 |

## §7 網羅基準

画面詳細設計書の機能一覧にある各機能キーが、本書または `画面テスト設計書.md` のいずれかの観点キーに対応することをキー集合で突き合わせる。業務ルール、状態分岐、入力検証、異常系、境界値、遷移条件を網羅し、観点だけに存在するキーは設計書の記載漏れとして扱う。

| 分類 | 扱い |
|---|---|
| 記録されなかった仕様変更 | 実挙動を観点として採用する |
| 生きているバグ | 有識者判定で忠実再現対象と確定した場合だけ採用する |
| 文書の腐敗 | 現在の実挙動を観点として採用する |

## §8 前提条件と終了条件

| 区分 | 条件 |
|---|---|
| 前提条件 | 観点に対応する失敗テストを先行作成する |
| 終了条件 | 全観点が成功し、refactor後も成功し、全ケースにテスト参照がある |
MD
cat > "$docs/スクリーン/screen-e2e-root/テスト設計/画面テスト設計書.md" <<'MD'
## §1 テスト観点

| キー | 観点 | 由来する設計書の章 | 区分 | 受け入れ | 実施方法 | 乖離分類 | テスト参照・検証記録参照 |
|---|---|---|---|---|---|---|---|
| 配置連結 | 配置連結の観点 | 基本設計 | 正常 | ◯ | 自動 | 該当なし | fixture.test |

## §2 テストケース一覧

| キー | 対応観点キー | 操作手順 | 入力値 | 期待結果（アサーション） | 実装後のテストファイル参照 |
|---|---|---|---|---|---|
| root-integration | 配置連結 | click | input | pass | fixture.test |
MD
cat > "$docs/スクリーン/screen-e2e-root/テスト設計/操作シナリオ仕様書.md" <<'MD'
## シナリオ一覧表
| シナリオキー | シナリオ名 | 開始状態 | 操作数 | 対応往復検証観点キー | 対応画面テストケースキー |
|---|---|---|---|---|---|
| root-scenario | root-scenario | ready | 1 | 配置往復 | root-integration |

### root-scenario

#### 操作と期待結果

| 順序 | 操作 | 対象 | 値 | 期待結果 |
|---|---|---|---|---|
| 1 | click | root-button |  | pass |

## 機械実行用YAML

```yaml
scenarios:
  - key: root-scenario
    name: root-scenario
    start_state: ready
    roundtrip_viewpoint_key: 配置往復
    screen_test_case_key: root-integration
    operations:
      - action: click
        target: root-button
        expected: pass
```
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
cp "$docs/スクリーン/screen-e2e-root/詳細設計/画面詳細設計書.md" \
  "$docs/スクリーン/archive/詳細設計/画面詳細設計書.md"
sed -i.bak 's/source_ref: dddddddddddddddddddddddddddddddddddddddd/source_ref: eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee/' \
  "$docs/スクリーン/archive/詳細設計/画面詳細設計書.md"
rm -f "$docs/スクリーン/archive/詳細設計/画面詳細設計書.md.bak"
printf '\nsource_ref: gggggggggggggggggggggggggggggggggggggggg\n' \
  >> "$docs/スクリーン/archive/詳細設計/画面詳細設計書.md"
mkdir -p "$docs/スクリーン/screen-no-ref/詳細設計"
cp "$docs/スクリーン/screen-e2e-root/詳細設計/画面詳細設計書.md" \
  "$docs/スクリーン/screen-no-ref/詳細設計/画面詳細設計書.md"
sed -i.bak 's/source_ref: dddddddddddddddddddddddddddddddddddddddd/source_repo: sample/' \
  "$docs/スクリーン/screen-no-ref/詳細設計/画面詳細設計書.md"
rm -f "$docs/スクリーン/screen-no-ref/詳細設計/画面詳細設計書.md.bak"

cases="$tmp/cases.json"
viewpoints="$tmp/viewpoints.json"
bash "$REPO_ROOT/generation-engine/scripts/extract/aggregate-test-cases.sh" "$docs" "$cases"
bash "$REPO_ROOT/generation-engine/scripts/extract/aggregate-test-viewpoints.sh" "$docs" "$viewpoints"
jq -e '.summary.totalCount == 3 and ([.units[].screenKey] | unique == ["screen-e2e-root"])' "$cases" >/dev/null \
  || { echo "FAIL: aggregate-test-cases result" >&2; jq . "$cases" >&2; exit 1; }
jq -e '.summary.totalCount == 2 and ([.units[].screenKey] | unique == ["screen-e2e-root"])' "$viewpoints" >/dev/null \
  || { echo "FAIL: aggregate-test-viewpoints result" >&2; jq . "$viewpoints" >&2; exit 1; }

# build-portal.shの出力を>/dev/nullで握りつぶすと、失敗時の理由（例: 設計文書群の
# 必須節検査FAIL）が失われ、単独実行では通っているように見えてしまう
# （1-268が生んだ回帰の見落とし。detail: docs/tasks/作業課題一覧.md）。
# 成功時は静かにし、失敗時だけ出力を出す。
build_portal_log="$tmp/build-portal.log"
if ! bash "$REPO_ROOT/generation-engine/scripts/build-portal.sh" "$REPO_ROOT" "$docs" "$portal" \
  --generated-at 2026-08-02T00:00:00Z >"$build_portal_log" 2>&1; then
  echo "FAIL: build-portal.sh" >&2
  cat "$build_portal_log" >&2
  exit 1
fi
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
mkdir -p "$docs/規約" "$docs/一覧/画面一覧" "$docs/project-portal/lists/screens" "$docs/プロジェクト共通"
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
: > "$docs/project-portal/lists/screens/画面一覧.html"
for file in コーディング規約 命名規約 ディレクトリ構成規約 コンポーネント設計規約; do : > "$docs/規約/$file.md"; done
for file in 共通設計書 メッセージ定義書 DESIGN 基盤設計 UI共通設計 データ設計; do : > "$docs/プロジェクト共通/$file.md"; done
: > "$docs/index.html"
for file in 用語辞書 技術スタック 画面遷移図 ER図 環境構築手順 リリースノート デザインシステム コンポーネント棚卸し アイコンカタログ 状態遷移図; do : > "$docs/$file.html"; done
state="$(bash "$REPO_ROOT/.claude/skills/orchestrating-ai-development-setup/scripts/resolve-flow-state.sh" "$docs" --screen-id e2e-root)"
[ "$state" = "シーケンス図未生成（任意）" ] || { echo "FAIL: same fixture flow state: $state" >&2; exit 1; }

# 同じcustom rootへsample rawのscreen-home文書を置き、rebuildへ明示してext linkを検査する。
mkdir -p "$docs/スクリーン/screen-home/基本設計" "$docs/スクリーン/screen-home/詳細設計" "$docs/スクリーン/screen-home/テスト設計"
: > "$docs/スクリーン/screen-home/基本設計/画面基本設計書.html"
: > "$docs/スクリーン/screen-home/詳細設計/画面詳細設計書.html"
: > "$docs/スクリーン/screen-home/シーケンス図.html"
: > "$docs/スクリーン/screen-home/テスト設計/画面単体テスト設計書.md"
raw="$REPO_ROOT/generation-engine/samples/docs/manifests/screen-manifest.json"
api="$tmp/api-manifest.json"
node - "$REPO_ROOT/generation-engine/samples/project-portal/lists/apis/API一覧.html" "$api" <<'NODE'
const fs=require("fs"); const s=fs.readFileSync(process.argv[2],"utf8");
const m=s.match(/<script\b(?=[^>]*type=["']application\/json["'])(?=[^>]*id=["']unit-manifest["'])[^>]*>([\s\S]*?)<\/script>/i);
if(!m) throw new Error("unit-manifest not found");
fs.writeFileSync(process.argv[3],JSON.stringify(JSON.parse(m[1]),null,2)+"\n");
NODE
mkdir -p "$docs/一覧/画面一覧"
# sourceDir は見本のroot起点の相対パスで記録されている。そのまま複製すると
# entryFile-実在の判定がリポジトリルート基準になり、44件すべてが実在しないと
# 判定されて必ず落ちる（2026-08-19 実測。19件中18件合格・1件不合格）。
# sourceDir を見本の絶対パスへ書き換えると44件すべてが実在する。同じ問題を
# tests/unit-list/test-rebuild-screen-derived-pages.sh が既に同じ方法で解いており、
# その解き方に揃える。
jq --arg samples_root "$REPO_ROOT/generation-engine/samples" '
  .sourceDir = (if (.sourceDir // "") == "" or (.sourceDir | startswith("/"))
                then .sourceDir
                else ($samples_root + "/" + .sourceDir) end)
' "$raw" > "$docs/一覧/画面一覧/screen-manifest.json"
bash "$REPO_ROOT/generation-engine/scripts/unit-list/rebuild-screen-derived-pages.sh" \
  --raw-manifest "$docs/一覧/画面一覧/screen-manifest.json" --target-repo "$REPO_ROOT" \
  --api-manifest "$api" --output-root "$docs" --generated-at 2026-08-02T00:00:00Z \
  --project-name e2e --design-docs-dir "$docs/スクリーン" >/dev/null
jq -e '.screens[] | select(.screenKey == "home") | .designDocPath == "../../../スクリーン/screen-home/基本設計/画面基本設計書.html" and .detailDocPath == "../../../スクリーン/screen-home/詳細設計/画面詳細設計書.html" and .sequencePath == "../../../スクリーン/screen-home/シーケンス図.html" and .testCasePath == "../../../スクリーン/screen-home/テスト設計/画面単体テスト設計書.md"' \
  "$docs/一覧/画面一覧/screen-manifest.ext.json" >/dev/null
if jq -e '.. | strings | select(contains("../../画面/screen-home/"))' "$docs/一覧/画面一覧/screen-manifest.ext.json" >/dev/null; then
  echo "FAIL: ext manifest retained old 画面/screen-home links" >&2
  exit 1
fi

echo "PASS: screenUnitRoot=スクリーン scaffold→verify→aggregate2本→portal→state→rebuild E2E"
