---
name: generating-sequence-diagram-for-reverse-docs
description: "画面フォルダに操作単位のシーケンス図HTMLを機械生成する。 TRIGGER when: シーケンス図生成、操作単位の呼び出し順序図化、sequence HTML作成。 SKIP: facts抽出（→extracting-unit-facts-from-code）、状態遷移図（→generating-entity-state-for-reverse-docs）、他種別詳細ページ生成。"
invocation: generating-sequence-diagram-for-reverse-docs
type: transform
allowed-tools: [Bash, Read, Write, Grep, Glob, AskUserQuestion, TaskCreate, TaskUpdate]
---

# シーケンス図生成スキル

画面ごとの操作（ボタン押下・フォーム送信等）を左サイドバーから選ぶと、画面→API→テーブル の呼び出し順序を表示するシーケンス図を生成する。左サイドバーは「画面 / 画面名」を親、「基本設計・詳細設計・シーケンス図」を子、「操作」を孫とする設計書共通の階層ナビゲーションであり、操作切り替えにドロップダウンを使わない。**本スキルは pageKind 体系（用語辞書・技術スタック・画面遷移図・ER図・環境構築手順・状態遷移図）には属さない**。1 pageKind = 1 固定ファイル名という pageKind 契約に対し、シーケンス図は画面ごとに複数生成される画面別ページであり、出力先も `画面/screen-<ID>/` 配下に画面ごとに存在するため、`shared/scripts/detail-pages/` の共通エンジン（`validate-page-data.sh` / `build-detail-page.sh`）は使わない。

## 使用タイミング

- 対象画面の facts.yml（`extracting-unit-facts-from-code` が確定済み）または手書きの page-data がある画面について、シーケンス図を生成・更新したいとき
- 起動引数: `output_dir`（`画面/screen-<ID>/` の所在）・対象画面 ID（複数可）

出力先は各画面ディレクトリ直下の `<output_dir>/画面/screen-<ID>/シーケンス図.html` に固定する（`build-portal.sh` の DOC_NAV 判定と同値。基本設計・詳細設計フォルダの 1 階層上）。

## page-data の形状

各画面の page-data（`<output_dir>/画面/screen-<ID>/シーケンス図-data.json`）は以下の形状を持つ。

```json
{
  "screenId": "screen-order-list",
  "screenLabel": "注文一覧",
  "generatedAt": "ISO8601",
  "operations": [
    {
      "key": "save-click",
      "label": "保存ボタン押下",
      "handler": "handler-onSave-保存",
      "steps": [
        {"seq": 1, "from": "screen", "to": "api", "label": "POST /orders", "sourceRef": "src/screens/Order.tsx:42"},
        {"seq": 2, "from": "api", "to": "table", "label": "INSERT orders", "sourceRef": "server/orders.ts:10"},
        {"seq": 3, "from": "api", "to": "screen", "label": "201 Created → 一覧再取得", "kind": "return"}
      ]
    }
  ]
}
```

- レーン（ライフライン）は固定 3 本: `screen`=画面 / `api`=API / `table`=テーブル。`steps[].from`/`to` はこの 3 値のみ
- `kind: "return"` のステップは破線で描画される。省略時は実線
- `sourceRef` は任意（無いステップはテンプレート側で根拠列を空表示する）

## エンジンスクリプトの所在

| スクリプト | パス（スキルフォルダ基点） |
|---|---|
| プレースホルダ置換 | `../../../shared/scripts/render-template.sh`（`render_template` 関数。用途に合わない場合のみ Phase 3 で手順記載の Bash ワンライナーに切り替える） |
| ポータル再生成（任意） | `../../../shared/scripts/build-portal.sh` |

テンプレートは `../../../shared/templates/screen-sequence-template.html` を使う。

## 進捗管理（必須手順）

スキル開始時に `TaskCreate` で Phase 1〜3 のタスクを登録する。各 Phase 開始時に該当タスクを `in_progress` に、完了時に `completed` へ `TaskUpdate` で更新する。実行環境に TaskCreate/TaskUpdate が存在しない場合は `$CLAUDE_JOB_DIR/tmp/task-ledger.md` で同等の Phase 遷移記録を代替する。

## 基本ワークフロー

## Phase 1: page-data の確保

## Step 1-1: 既存 page-data の確認

Read / Glob で対象画面ごとに `<output_dir>/画面/screen-<ID>/シーケンス図-data.json` の実在を確認する。存在すれば内容を読み、上記形状（`screenId`・`screenLabel`・`operations[].key`/`label`/`steps[]`）に合致するか確認する。

**完了**: 各対象画面について page-data の実在有無と形状を確認済み。

## Step 1-2: facts から page-data へ変換

不在の画面については、Read で同ディレクトリの facts.yml（`facts_ref`。`extracting-unit-facts-from-code` が確定済みの前提）を読む。⑤handler の各 item が持つ任意フィールド `call_order`（形式 `"<連番>:<api分類のkey>@<file:line>; ..."`。`shared/references/facts-schema.md` の「call_order（⑤handlerの任意フィールド）」節が正本）を持つ handler だけを対象に、Write で `operations[]` へ機械変換する。

  - `operations[].key`/`label` は handler item の `key`/`value`（発火要素・処理1行要約）から組み立てる
  - `call_order` の各エントリを `steps[]` に変換する: `from: "screen"`・`to: "api"`・`label` は参照先の⑧api分類 item の `value`（BL 名・リクエスト形）・`sourceRef` は `call_order` エントリの `file:line`
  - API 呼び出しに対応する DB アクセス（⑧api分類 item の value・evidence から読み取れる範囲）が facts 側に記録されている場合のみ `api→table` の step を追加する。記録がなければ `api→screen`（`kind: "return"`）で応答だけを 1 step として閉じる
  - facts.yml が実在し、`call_order` を持つ handler が 1 件もない画面は、推測で操作を補わず `operations: []` の page-data を機械生成する。テンプレートの空状態までレンダリングし、「呼び出し順序の記録なし」と報告する
  - facts.yml 自体が存在しない画面だけは変換不能として報告し、手書き page-data の作成をユーザーに依頼して当該画面をスキップする（捏造しない）

**完了**: facts.yml が実在する画面は、操作 0 件を含めすべて `シーケンス図-data.json` を書き出し済み。facts.yml 不在の画面は報告済み。

## Step 1-3: page-data の検証

Bash で組み立てた JSON を jq 検証する。必須キー（`screenId`/`screenLabel`/`operations`）の存在、`operations[].steps[].from`/`to` が `screen`/`api`/`table` の 3 値のみであること、`operations[].steps[].seq` が 1 始まりの連番であることを確認する。

```bash
jq -e '
  (.screenId and .screenLabel and .operations) and
  (.operations | all(.steps | all(.from as $f | .to as $t | (["screen","api","table"] | index($f)) != null and (["screen","api","table"] | index($t)) != null))) and
  (.operations | all((.steps | map(.seq)) as $seqs | $seqs == ([range(1; ($seqs | length) + 1)])))
' "<output_dir>/画面/screen-<ID>/シーケンス図-data.json"
```

**完了**: facts.yml が実在する対象画面すべてで jq 検証が通過済み。

## Phase 2: DOC_NAV の組み立て

## Step 2-1: 階層ナビゲーションの確定

Glob / Read で実在ファイルを確認し、対象画面の `<output_dir>/画面/screen-<ID>/` 配下で、設計書ビューアと同じ体裁の左サイドバー用 doc-nav を組み立てる。`build-portal.sh` セクション 3.5 の doc_nav 組み立てロジックと同一の判定を、シーケンス図.html 側の視点（アクティブ項目がシーケンス図）で行う。

- **戻るリンク**: `<a class="back-link" href="<画面一覧.htmlへの相対パス>">← 画面一覧へ戻る</a>`。`<output_dir>/一覧/画面一覧/画面一覧.html` への相対パスを算出する（出力先は `画面/screen-<ID>/` 直下なので `../../一覧/画面一覧/画面一覧.html` が典型値）
- **基本設計項目**: `${screen_dir}基本設計/画面基本設計書.html` が実在すれば `<a class="nav-item" href="基本設計/画面基本設計書.html">基本設計</a>`
- **詳細設計項目**: `${screen_dir}詳細設計/画面詳細設計書.html` が実在すれば `<a class="nav-item" href="詳細設計/画面詳細設計書.html">詳細設計</a>`
- **シーケンス図項目**: 自ページなので `<span class="nav-item active">シーケンス図</span>`
- 実在しない項目は追加しない（存在しない基本設計・詳細設計への空リンクを作らない）

**完了**: 対象画面ごとに doc_nav 文字列が確定済み。

## Phase 3: HTML 生成

## Step 3-1: テンプレートのレンダリング

以下のように Bash から `render_template` を呼び出し、Write で `<output_dir>/画面/screen-<ID>/シーケンス図.html` を生成する。`render-template.sh` は bash 関数を提供するのみで CLI エントリポイントを持たないため、Bash ツールから以下のようなインライン bash で実行する（新規 `.sh` ファイルは作らない）。他ページと共通の階層サイドバー・フッター（partials）も `shell-injection.sh` の `shell_injection_args` で注入する。

  ```bash
  bash -c '
    source "<スキルフォルダ>/../../../shared/scripts/render-template.sh"
    . "<スキルフォルダ>/../../../shared/scripts/shell-injection.sh"
    template="$(cat "<スキルフォルダ>/../../../shared/templates/screen-sequence-template.html")"
    tokens_css="$(cat "<スキルフォルダ>/../../../shared/templates/tokens.css")"
    page_data="$(cat "<output_dir>/画面/screen-<ID>/シーケンス図-data.json")"
    render_args=(
      "{{PROJECT_NAME}}" "<プロジェクト名>" \
      "{{GENERATED_DATE}}" "<YYYY-MM-DD>" \
      "{{COMMIT_SHORT}}" "<（空文字可）>" \
      "{{PORTAL_INDEX_HREF}}" "<ポータルindex.htmlへの相対パス>" \
      "{{DOC_NAV}}" "<Phase 2で確定したdoc_nav文字列>" \
      "{{SCREEN_LABEL}}" "<画面ラベル>" \
      "/* TOKENS_CSS */" "$tokens_css" \
      "{{PAGE_DATA_JSON}}" "$page_data"
    )
    shell_injection_args "<スキルフォルダ>/../../../shared/templates" "<スキルフォルダ>/../../../shared/templates/../references/portal-catalog.json" "<ポータルindex.htmlへの相対パス>" "<プロジェクト名>" "<YYYY-MM-DD>" "<（空文字可）>" "generating-sequence-diagram-for-reverse-docs" "list"
    if [ ${#SHELL_RENDER_ARGS[@]} -gt 0 ]; then
      render_args+=("${SHELL_RENDER_ARGS[@]}")
    fi
    out="$(render_template "$template" "${render_args[@]}")"
    printf "%s\n" "$out" > "<output_dir>/画面/screen-<ID>/シーケンス図.html"
  '
  ```

**手作業でのプレースホルダ置換（sed・perl 直書き等）は禁止する**。`render_template` は最短前方一致で置換するため、値の中に他プレースホルダ文字列が偶然含まれても誤爆しない。

**完了**: 対象画面すべてで `シーケンス図.html` が生成済み。

## Step 3-2: ポータルへの反映

`portal_output_dir` が指定されていれば Bash で `build-portal.sh` を再実行し、生成済み `シーケンス図.html` が設計書ビューアの DOC_NAV にシーケンス図項目として反映されることを確認する。未指定なら省略し完了報告に注記する。

**完了**: ポータルを再実行済み、または省略理由を注記済み。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | facts.yml が実在する対象画面は操作 0 件を含め `シーケンス図-data.json` が実在し jq 検証を通過済み。facts.yml 不在の画面は変換不能を報告済み |
| Phase 2 | 対象画面ごとに doc_nav 文字列（戻るリンク＋実在する設計書項目のみ）が確定済み |
| Phase 3 | 対象画面ごとに `シーケンス図.html` が生成済み。指定時は `build-portal.sh` の再実行が完了している |
| **Goal** | 画面ごとの操作単位について、画面→API→テーブル の呼び出し順序を階層サイドバーから切り替えて表示するシーケンス図.html が生成されている |

## 重要な注意事項

- 判定・評価はしない。呼び出し順序や処理内容の良否には踏み込まず、facts（call_order）または手書き page-data に記録された事実のみを転記する
- `call_order` を持つ handler が 0 件の画面で、AskUserQuestion を使って手動でステップを聞き出さない。`operations: []` として空状態を生成し、検出できない呼び出し順序を即興確定しない
- `shared/scripts/detail-pages/` 配下・`extracting-unit-facts-from-code` 配下・`seal-facts.sh` は変更しない（別スキルの管轄）
- 新規 `.sh` スクリプトファイルは作らない。`render-template.sh` の `render_template` 関数を Bash から直接 source して使う

## 予想を裏切る挙動

- 出力先はテンプレート名（`シーケンス図.html`）が pageKind の `FUTURE_FILES` と同名でも、`output_dir` 直下ではなく画面ごとのフォルダ（`画面/screen-<ID>/`）直下になる。pageKind 体系の「1 pageKind = 1 固定ファイル名」契約はここでは適用されない
- `build-portal.sh` は画面設計書（基本設計・詳細設計）側の DOC_NAV にのみシーケンス図項目を追加する。シーケンス図.html 自体の DOC_NAV は本スキルの Phase 2/3 が組み立てる（build-portal.sh の担当範囲外）

## 完了報告

`~/.claude/skills/managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（作業報告型）に従う。固有の検証行: 生成した画面数・操作数・データ源（手書き data / facts の call_order）。

## 参照資料

- `shared/references/facts-schema.md` — call_order（⑤handlerの任意フィールド）の形式定義
- `shared/templates/screen-sequence-template.html` — 設計書共通の階層サイドバーと操作メニューを備えたシーケンス図.html のテンプレート本体
- `shared/scripts/render-template.sh` — `render_template` 関数の実装
