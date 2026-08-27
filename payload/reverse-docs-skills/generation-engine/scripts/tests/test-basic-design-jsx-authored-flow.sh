#!/usr/bin/env bash
set -euo pipefail

# 第1層の集約（generation-engine/scripts/verification/run-layer-machine-checks.sh）は、
# 本文に "--self-test)" を持つ .sh を対象として集める。このスクリプトは引数を取らず、
# 実行そのものが検査になる形のため、引数を見る分岐が無く集約から漏れていた。集約に
# 拾わせるための受け口であり、渡されても渡されなくても動きは変わらない。この分岐を
# 消すと集約から外れ、この検査は二度と走らなくなる。
case "${1:-}" in --self-test) ;; esac

# test-basic-design-jsx-authored-flow.sh — 写真指摘1-167の残作業（検収方法3）の決定的縦貫fixture
#
# 実データ（jsx構造を持つ画面・original.png）がこの検証環境に存在しない状況で、
# facts.yml に jsx 構造を持つ合成fixtureを与えたとき、
#   scaffold-screen.sh（展開・--verify）
#   → seal-facts.sh（seal・verify）
#   → validate-reverse-authoring-inputs.py screen-composition（route=facts-structure判定）
#   → 画面基本設計書.md 著述（Phase 3 実装用語・内部成果物名grep検査）
# の一気通貫が「基本設計著述完了」（AUTHORED相当）に到達することを検証する。
#
# facts 抽出そのもの（extracting-unit-facts-from-code）は AI 駆動のスキルであり
# 決定的スクリプトではないため、本テストは facts.yml を直接fixtureとして与える
# （schema準拠の12分類構造・jsxセクションにitemあり）。著述内容（画面基本設計書.md）も
# 同様に決定的スクリプトの出力ではなく執筆役スキルの成果物であるため、
# facts.yml から業務語彙で書き起こした golden文書を fixture として埋め込み、
# Phase 3 の実際の grep 検査式をそのまま本文へ通す。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SEAL="$SCRIPT_DIR/../seal-facts.sh"
SCAFFOLD="$SCRIPT_DIR/../scaffold-screen.sh"
AUTHORING_INPUTS="$SCRIPT_DIR/../validate-reverse-authoring-inputs.py"

# macOS では TMPDIR/tmp がsymlinkのため、scaffold-screen.sh の
# symlink拒否ガードに抵触しないよう実体パスへ解決してから使う。
if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/basic-design-jsx-authored.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
  echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
  exit 2
fi
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

facts_dir="$tmp/facts/extract-fixture-1"
output_dir="$tmp/output_dir"
mkdir -p "$facts_dir" "$output_dir"

fail=0
report() {
  if [ "$2" -eq 0 ]; then
    echo "PASS: $1"
  else
    echo "FAIL: $1" >&2
    fail=$((fail + 1))
  fi
}

# jsx構造（- key: を1件以上持つ）を含む facts.yml fixture。
# schema（delivery-payload/references/facts-schema.md）の12分類すべてを埋める。
cat > "$facts_dir/facts.yml" <<'YML'
run_id: extract-fixture-1
profile: screen
target_repo_path: /tmp/fixture-target-repo
target_file_paths:
  - src/screens/Sample/Sample.tsx
meta:
  source_repo: /tmp/fixture-target-repo
  source_ref: 0000000000000000000000000000000000000000
  route:
    value: "/sample"
    evidence: "src/router/routes.tsx:1"
  source_encoding: UTF-8
  source_line_ending: LF
sections:
  import:
    reason: ""
    items:
      - key: import-react-useState
        value: "react から useState"
        evidence: "src/screens/Sample/Sample.tsx:1"
  export_type:
    reason: "該当なし（原本に型宣言を伴うexportが存在しない）"
    items: []
  const:
    reason: "該当なし（原本にトップレベル定数が存在しない）"
    items: []
  state:
    reason: ""
    items:
      - key: state-count-0
        value: "number型、初期値0"
        evidence: "src/screens/Sample/Sample.tsx:5"
  handler:
    reason: ""
    items:
      - key: handler-onIncrementClick-カウント加算
        value: "ボタン押下でcountを1増やす"
        evidence: "src/screens/Sample/Sample.tsx:8"
  jsx:
    reason: ""
    items:
      - key: jsx-div-count-button
        value: "div > p(カウント表示) + button(押下で加算)"
        evidence: "src/screens/Sample/Sample.tsx:12"
  style:
    reason: "該当なし（原本にスタイル定数が存在しない）"
    items: []
  api:
    reason: "該当なし（原本にAPI呼出が存在しない）"
    items: []
  measurement_pending:
    reason: "該当なし（実測委譲対象の項目が存在しない）"
    items: []
  local_type:
    reason: "該当なし（原本に非exportの型宣言が存在しない）"
    items: []
  effect_trigger:
    reason: "該当なし（原本にuseEffect呼出が存在しない）"
    items: []
  error_handling:
    reason: "該当なし（原本にエラー処理が存在しない）"
    items: []
YML

# 1. 封印・直後verify（旧normalize世代ずれの検証は seal-facts.sh --self-test 側の担当。
#    本テストは新規抽出フローの封印が問題なくverifyを通過することの一気通貫確認）
seal_rc=0
bash "$SEAL" seal "$facts_dir" >/dev/null || seal_rc=$?
bash "$SEAL" verify "$facts_dir" >/dev/null || seal_rc=$?
report "1-167 新規抽出フローのfacts封印と直後verify" "$seal_rc"

# 2. scaffold展開・--verify
scaffold_rc=0
bash "$SCAFFOLD" "$output_dir" sample-screen "サンプル画面" >/dev/null || scaffold_rc=$?
bash "$SCAFFOLD" --verify "$output_dir" sample-screen >/dev/null || scaffold_rc=$?
report "1-167 scaffold展開と--verify" "$scaffold_rc"

screen_dir="$output_dir/画面/screen-sample-screen"
basic_dir="$screen_dir/基本設計"
doc="$basic_dir/画面基本設計書.md"
record="$basic_dir/画面構成入力判定.json"

# 3. screen-composition判定: original.png無し・jsx構造ありで route=facts-structure / status=PASS
composition_rc=0
python3 "$AUTHORING_INPUTS" screen-composition \
  --screen-dir "$screen_dir" --facts "$facts_dir/facts.yml" --record "$record" \
  >/dev/null || composition_rc=$?
if [ "$composition_rc" -eq 0 ] \
  && grep -q '"route": "facts-structure"' "$record" \
  && grep -q '"status": "PASS"' "$record" \
  && grep -q '"originalPngAvailable": false' "$record" \
  && grep -q '"factsJsxAvailable": true' "$record"; then
  composition_rc=0
else
  composition_rc=1
fi
report "1-167 original.png無し×jsx構造ありでroute=facts-structure判定" "$composition_rc"

# 4. facts.yml から業務語彙で書き起こしたgolden文書（§1〜§6全充足・実装用語なし）
cat > "$doc" <<'MD'
---
doc_id: screen-sample-screen
type: screen-basic-design
screen_name: サンプル画面
created: 2026-08-06
status: authored
---

# サンプル画面 画面基本設計書

## §1 画面の目的

利用者が任意の操作を繰り返した回数を、画面上で確認できるようにするための画面である。

## §2 画面構成（構造推定）

### 画面キャプチャ

<div class="screen-capture-placeholder" role="img" aria-label="画面キャプチャは未取得です。後続の画面確認で追加します。" style="box-sizing:border-box;display:flex;align-items:center;justify-content:center;min-height:180px;padding:24px;color:#64748b;background:#f8fafc;border:2px dashed #94a3b8;border-radius:0;text-align:center;">画面キャプチャは未取得です。後続の画面確認で追加します。</div>

### 部品構成（構造推定）

```
┌────────────────────────────────┐
│ 回数表示領域                     │
├────────────────────────────────┤
│  ┌──────────────────────────┐  │
│  │ 現在の回数の表示欄        │  │
│  └──────────────────────────┘  │
│  ┌──────────────────────────┐  │
│  │ 加算ボタン                │  │
│  └──────────────────────────┘  │
└────────────────────────────────┘
```

## §3 機能仕様（業務機能の一覧）

| キー | 機能名 | 業務上の目的 | 利用者 |
|---|---|---|---|
| `加算ボタン押下-回数加算` | 回数加算 | ボタン押下のたびに表示中の回数を1増やせる | 画面利用者 |

## §4 業務ルール

| キー | ルール内容 | 適用条件 | 例外 |
|---|---|---|---|
| `回数表示-初期値` | 画面表示時点の回数は0から開始する | 画面表示のたび | なし |
| `回数加算-増分` | 加算操作1回につき回数を1増やす | 加算ボタン押下時 | なし |

## §5 入出力の業務的意味

### 5.1 入力（利用者が入力・選択する情報）

該当なし（外部との情報のやり取りに関する事実が採録されておらず、利用者からの入力は加算ボタンの押下操作のみであり、値の入力・選択は発生しない）

### 5.2 出力（画面が提示する情報）

| キー | 項目名 | 業務上の意味 | 提示形式の業務要件 |
|---|---|---|---|
| `回数-表示` | 現在の回数 | 加算操作が行われた回数を表す | 単一の数値表示 |

## §6 画面遷移の業務文脈

該当なし（本画面自体の所在情報のみが採録されており、遷移元・遷移先に関する事実がいずれの分類にも存在しないため）
MD

# 5. Phase 3: 実装用語・内部成果物名grep検査（generating-reverse-basic-design/SKILL.md Phase 3と同一式）
grep_rc=0
grep -nE 'useState|useEffect|useReducer|\bProps\b|styled-components|\bReact\b|\bVue\b|\bAngular\b|interface [A-Z]|: *(string|number|boolean)\b|/[A-Za-z0-9_-]+\.(tsx|ts|jsx|js|css)\b|facts\.yml|facts-schema|facts_ref|const_declarations|handler_exports|type_definitions' "$doc" \
  >/dev/null && grep_rc=1
report "1-167 Phase3実装用語・内部成果物名grep検出0件" "$grep_rc"

# 6. HTMLコメント残存検査
comment_rc=0
grep -n '<!--' "$doc" >/dev/null && comment_rc=1
report "1-167 HTMLコメント残存0件" "$comment_rc"

# 7. §1〜§6全章の記述充足・frontmatter status=authored
sections_rc=0
for heading in '§1 画面の目的' '§2 画面構成' '§3 機能仕様' '§4 業務ルール' '§5 入出力の業務的意味' '§6 画面遷移の業務文脈'; do
  grep -q "## ${heading}" "$doc" || sections_rc=1
done
grep -q '^status: authored$' "$doc" || sections_rc=1
report "1-167 §1〜§6全章充足・status=authored" "$sections_rc"

# 8. seal-facts.shが版整合のverifyを提供していること自体は seal-facts.sh --self-test の担当。
#    本テストは新規抽出フローの封印を対象とし、対象を混同しないため再掲しない。

if [ "$fail" -eq 0 ]; then
  echo "self-test: 1-167 jsx構造fixtureでbasic-design AUTHORED相当到達 全項目 PASS"
  exit 0
fi
echo "self-test FAIL: ${fail}件" >&2
exit 1
