---
name: generating-sequence-diagram-for-reverse-docs
description: "画面フォルダに操作単位のシーケンス図HTMLを機械生成する。 TRIGGER when: シーケンス図生成、操作単位の呼び出し順序図化、sequence HTML作成。 SKIP: facts抽出（→extracting-unit-facts-from-code）、状態遷移図（→generating-entity-state-for-reverse-docs）、他種別詳細ページ生成。"
invocation: generating-sequence-diagram-for-reverse-docs
type: transform
allowed-tools: [Bash, Read, Write, Grep, Glob, AskUserQuestion, TaskCreate, TaskUpdate]
---

# シーケンス図生成スキル

画面ごとの操作（ボタン押下・フォーム送信等）を左サイドバーから選ぶと、利用者→画面→API／内部処理→テーブル の呼び出し順序を表示するシーケンス図を生成する。左サイドバーは「画面 / 画面名」を親、「基本設計・詳細設計・シーケンス図」を子、「操作」を孫とする設計書共通の階層ナビゲーションであり、操作切り替えにドロップダウンを使わない。**本スキルは pageKind 体系（用語辞書・技術スタック・画面遷移図・ER図・環境構築手順・状態遷移図）には属さない**。1 pageKind = 1 固定ファイル名という pageKind 契約に対し、シーケンス図は画面ごとに複数生成される画面別ページであり、出力先も `画面/screen-<ID>/` 配下に画面ごとに存在するため、`shared/scripts/detail-pages/` の共通エンジン（`validate-page-data.sh` / `build-detail-page.sh`）は使わない。

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
  "lanes": [
    {"key": "user", "label": "利用者"},
    {"key": "screen", "label": "画面"},
    {"key": "api", "label": "API"},
    {"key": "table", "label": "テーブル"}
  ],
  "operations": [
    {
      "key": "save-click",
      "label": "保存ボタン押下",
      "handler": "handler-onSave-保存",
      "lanes": [
        {"key": "user", "label": "利用者"},
        {"key": "screen", "label": "画面"},
        {"key": "api", "label": "API"},
        {"key": "table", "label": "テーブル"}
      ],
      "steps": [
        {"seq": 1, "from": "user", "to": "screen", "label": "操作開始", "kind": "trigger"},
        {"seq": 2, "from": "screen", "to": "api", "label": "注文登録", "sourceRef": "src/screens/Order.tsx:42"},
        {"seq": 3, "from": "api", "to": "table", "label": "注文レコード登録", "sourceRef": "server/orders.ts:10"},
        {"seq": 4, "from": "api", "to": "screen", "label": "登録完了 → 一覧再取得", "kind": "return", "sourceRef": "src/screens/Order.tsx:42"}
      ]
    }
  ]
}
```

- **レーン（ライフライン）**: `operations[].lanes` で操作ごとに任意定義できる。各要素は `key`（`steps[].from`/`to` が参照する識別子）と `label`（見出し表示名）を持つ。テンプレートは `operation.lanes`、page-data直下の`lanes`、固定4本（`user`=利用者 / `screen`=画面 / `api`=API / `table`=テーブル）の順で採用する。page-data直下の`lanes`は後方互換のfallbackである
- `kind: "return"` のステップは破線で描画される。省略時は実線
- 各operationの先頭は`{"seq":1,"from":"user","to":"screen","label":"操作開始","kind":"trigger"}`とする。これは利用者起点を決定的に表す合成stepであり、call_orderの業務内容を推測しない。原本上の対応行がないため`sourceRef`は付けない
- `sourceRef` は facts（`call_order`）由来のステップでは省略しない。`call_order` エントリは必ず `file:line` を持つため、対応する `steps[].sourceRef` に転記する。手書き page-data で根拠が無いステップに限り省略でき、その場合はテンプレート側で根拠列を空表示する

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

### ステップ表示文言の導出

- `steps[].label` に⑧api分類 item の `value` を生の文字列としてそのまま転記しない。`value` には代入式（`=`）・引数リテラル（丸括弧）・タブ区切りの分類タグが含まれ、そのまま表示すると呼び出しの意味が読み取れないため
- 表示文言は呼び出し先の**業務名**にする。導出根拠は優先順に (1) 原本の該当行に付いた日本語コメント（`value`/`evidence` から読み取れる範囲）、(2) 呼び出し先の関数名・BL 名（⑧api分類 item の識別子部分。代入・引数を除く）とする
- 代入演算子（`=`）・引数の丸括弧とその中身（`(...)`）・タブ区切りの分類タグは表示文言から落とす。これらは根拠欄（`sourceRef`）が追跡性を担うため、表示文言に原本の文字列を残す必要はない
- **根拠のない機能名を作らない**。日本語コメントからも関数名・BL 名からも業務名を導出できない呼び出しは、呼び出し先の識別子（BL 名そのもの）だけを表示文言にする。読み手に伝わりやすくするための推測で業務的な名前を捏造しない
- `sourceRef` は `call_order` エントリの `file:line` をそのまま転記する（facts 由来のステップでは省略しない）。`api→screen`（`kind: "return"`）の合成応答ステップは、対応する呼び出し元 `call_order` エントリと同一の `file:line` を `sourceRef` として引き継ぐ

### operations[] への組み立てと分割

- `operations[].key`/`label` は handler item の `key`/`value`（発火要素・処理1行要約）から組み立てる。1 handler の `call_order` から変換したステップ数が 15 を超える場合は、以下の基準の優先順で複数の `operations[]` へ分割する
  1. 同じ画面の設計文書（画面基本設計書等）が機能の一覧を持つ場合は、その機能単位へ対応付けて分割する
  2. 機能単位が無い、または分割後もなお 15 ステップを超える区分がある場合は、原本のコメント区切りのような根拠のある単位（関数内のブロックコメント境界等）で局面へ分ける
  3. 上記いずれも適用できない場合は、ソース出現順（`call_order` の連番順）に 15 ステップごとで機械的に区切る
  - 分割後の `operations[].key`/`label` は連番を使わない。各区切りの先頭ステップに導出できた業務名（導出できなければ先頭呼び出しの識別子）を局面名として使い、内容を要約した意味語で組み立てる（例: `save-click` の分割なら `save-click-validate` / `save-click-persist`）
  - 分割後も各operationの先頭に利用者→画面の「操作開始」を追加し、call_order由来stepの`seq`を1つ繰り下げる。各 `operations[].steps[].seq` は操作ごとに 1 始まりの連番へ振り直す（Step 1-3 の jq 検証は操作単位で連番性を見るため）
  - 分割は呼び出しの追加・削除・重複を行わない。分割前後で `call_order` から機械変換されたステップの総数（合成 return ステップを除く）は変わらない
  - 15 ステップ以下の handler は分割せず 1 handler = 1 operation のまま変換する
- 各operationの先頭へ`from: "user"`・`to: "screen"`・`label: "操作開始"`・`kind: "trigger"`の合成stepを追加する。ドメイン固有文言と`sourceRef`は付けず、call_order由来stepの`seq`はすべて1つ繰り下げる
- `call_order` の各エントリを `steps[]` に変換する: `from: "screen"`・`to: "api"`
- API 呼び出しに対応する DB アクセス（⑧api分類 item の value・evidence から読み取れる範囲）が facts 側に記録されている場合のみ `api→table` の step を追加する。記録がなければ `api→screen`（`kind: "return"`）で応答だけを 1 step として閉じる
- 合成した「操作開始」を除くstepに存在する`sourceRef`を行番号除去して正規化し、そのパスの一意数が1なら、そのoperationのstep endpointにある`api`を`internal`へ機械置換する。`operation.lanes`から`api`を除いて`{"key":"internal","label":"内部処理"}`を置き、table等の実際に使う他レーンは保持する。一意パス数が複数ならAPI endpointとレーンを維持する。0なら単一判定を適用せず、手書きpage-data等の既存endpointを変換しない
- `operation.lanes`は`user`を先頭にし、続けて`screen`、`internal`または`api`、`table`等を、そのoperationのstep endpointに最初に現れる順で定義する。根拠なしに「内部処理」より具体的な実体名を推測しない
- facts.yml が実在し、`call_order` を持つ handler が 1 件もない画面は、推測で操作を補わず `operations: []` の page-data を機械生成する。テンプレートの空状態までレンダリングし、「呼び出し順序の記録なし」と報告する
- facts.yml 自体が存在しない画面だけは変換不能として報告し、手書き page-data の作成をユーザーに依頼して当該画面をスキップする（捏造しない）

**完了**: facts.yml が実在する画面は、操作 0 件を含めすべて `シーケンス図-data.json` を書き出し済み。facts.yml 不在の画面は報告済み。

## Step 1-3: page-data の検証

Bash で組み立てた JSON を jq 検証する。必須キー、操作ごとの有効レーン、seq連番、先頭の利用者起点step、単一sourceRef時の内部処理レーンを確認する。レーン検証は`operation.lanes`、page-data直下の`lanes`、固定4本の順で採用する。

```bash
jq -e '
  def source_path:
    sub("(#[Ll][0-9]+(-[Ll]?[0-9]+)?|:[0-9]+(-[0-9]+)?)$"; "");
  (.screenId and .screenLabel and .operations) and
  . as $page |
  (.operations | all(
    . as $op |
    (if (($op.lanes // []) | length) > 0 then [$op.lanes[].key]
     elif (($page.lanes // []) | length) > 0 then [$page.lanes[].key]
     else ["user","screen","api","table"] end) as $lanes |
    ($op.steps | all(.from as $f | .to as $t |
      ($lanes | index($f)) != null and ($lanes | index($t)) != null)) and
    (($op.steps | map(.seq)) as $seqs |
      $seqs == ([range(1; ($seqs | length) + 1)])) and
    ($op.steps[0].from == "user" and
     $op.steps[0].to == "screen" and
     $op.steps[0].label == "操作開始" and
     $op.steps[0].kind == "trigger" and
     ($op.steps[0] | has("sourceRef") | not)) and
    ($op.steps | any(.from == "user")) and
    ([$op.steps[1:][]] as $derived |
     ([$derived[] | select((.sourceRef // "") != "") |
       .sourceRef | source_path] | unique) as $paths |
     (if (($paths | length) == 1)
      then (($op.steps | all(.from != "api" and .to != "api")) and
            ($op.steps | any(.from == "internal" or .to == "internal")) and
            (($lanes | index("api")) == null) and
            (($lanes | index("internal")) != null))
      elif (($paths | length) > 1)
      then (($op.steps | any(.from == "api" or .to == "api")) and
            (($lanes | index("api")) != null))
      else true end))
  ))
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
      "{{COMMIT_SHORT}}" "<短縮コミットハッシュ本体のみ。空文字可>" \
      "{{PORTAL_INDEX_HREF}}" "<ポータルindex.htmlへの相対パス>" \
      "{{DOC_NAV}}" "<Phase 2で確定したdoc_nav文字列>" \
      "{{SCREEN_LABEL}}" "<画面ラベル>" \
      "/* TOKENS_CSS */" "$tokens_css" \
      "{{PAGE_DATA_JSON}}" "$page_data"
    )
    shell_injection_args "<スキルフォルダ>/../../../shared/templates" "<スキルフォルダ>/../../../shared/templates/../references/portal-catalog.json" "<ポータルindex.htmlへの相対パス>" "<プロジェクト名>" "<YYYY-MM-DD>" "<短縮コミットハッシュ本体のみ。空文字可>" "generating-sequence-diagram-for-reverse-docs" "list"
    if [ ${#SHELL_RENDER_ARGS[@]} -gt 0 ]; then
      render_args+=("${SHELL_RENDER_ARGS[@]}")
    fi
    out="$(render_template "$template" "${render_args[@]}")"
    printf "%s\n" "$out" > "<output_dir>/画面/screen-<ID>/シーケンス図.html"
  '
  ```

**手作業でのプレースホルダ置換（sed・perl 直書き等）は禁止する**。`render_template` は最短前方一致で置換するため、値の中に他プレースホルダ文字列が偶然含まれても誤爆しない。

**`{{GENERATED_DATE}}`/`{{COMMIT_SHORT}}` の値の形**: `{{COMMIT_SHORT}}` には区切り文字・ラベル（「コミット」等）を含めず、短縮コミットハッシュ本体（例 `a1b2c3d4`）のみを渡す。日付との区切りとラベル表示は共通シェル（`shared/templates/partials/shell-sidebar.html`/`shell-footer.html`）側が担い、値が空文字の場合は当該シェルの実行時 JS（`removeIfEmptyCommit`）が空表示を自動で取り除く。呼び出し側で `" · コミット番号: <sha>"` のような区切り込みの値を渡すと二重表記になるため禁止する。

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
| **Goal** | 全operationが利用者→画面の「操作開始」を持ち、単一sourceRefのoperationはAPIでなく内部処理レーンを使い、それ以外はfactsに沿う呼び出し順序を階層サイドバーから切り替えて表示するシーケンス図.html が生成されている |

## 重要な注意事項

- 判定・評価はしない。呼び出し順序や処理内容の良否には踏み込まず、facts（call_order）または手書き page-data に記録された事実のみを転記する
- 「操作開始」は利用者起点を表す非ドメインの合成triggerであり、call_orderの内容を補わない。対応する原本行がないため`sourceRef`を付けない
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
