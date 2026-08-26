---
name: generating-sequence-diagram-for-reverse-docs
日本語名: シーケンス図の書き出し
description: "設計文書または確定済みの事実の記録から導ける呼び出し順序をシーケンス図にする。"
invocation: generating-sequence-diagram-for-reverse-docs
type: transform
allowed-tools: [Bash, Read, Write, Grep, Glob, AskUserQuestion, TaskCreate, TaskUpdate]
---

## いつ使うか

対象画面の事実の記録、API詳細設計書、機能設計書、または手書きの入力データがあり、呼び出し順序を図にしたいとき。

## いつ使わないか

コードから事実を抜き出すとき、状態遷移図を作るとき、他の種類の詳細ページを作るとき。

# 正本: reverse-docs-skills

本スキルが生成する納品物は顧客提示の文書である。自由記述の本文（要約・説明文）は敬体（です・ます）で書く。記入規則・検証記録・作業記録は常体でもよい（`delivery-payload/references/設計書様式.md` §8）。

# シーケンス図生成スキル

画面・API・機能の設計単位ごとに、設計文書または確定済みfactsが明示する呼び出し順序をシーケンス図にする。左サイドバーは設計単位を親、「基本設計・詳細設計・シーケンス図」を子、「操作／処理」を孫とする。切り替えにドロップダウンは使わない。

**本スキルは pageKind 体系（用語辞書・技術スタック・画面遷移図・ER図・環境構築手順・状態遷移図）には属さない**。シーケンス図は設計単位ごとに生成する。`generation-engine/scripts/detail-pages/` の共通エンジン（`validate-page-data.sh` / `build-detail-page.sh`）は使わない。

## 使用タイミング

- 次のいずれかからシーケンス図を生成・更新したいとき
  - `extracting-unit-facts-from-code` で確定した画面の facts.yml
  - API詳細設計書の§4.1
  - 機能設計書の§3.1
  - 手書きの page-data
- 起動引数: `output_dir`（output-layout を解決する基点）・対象種別（screen / api / feature）・対象ユニット ID（複数可）

出力先は次の決定表に固定する。screenの`unitId`は既存契約どおり`screen-<ID>`とし、policyの`screenUnitIdPattern`へ一致させる。

API・機能の`<unit-dir>`は、空でない`unitId`がpolicyの`unitIdPattern`に一致するときだけそのまま使う。不一致なら生成せず停止する。`unitId`が空なら`api-<unitKey>`または`feature-<unitKey>`とする。日本語の意味語を含む`unitKey`も無変換で保持する。空文字、path区切り（`/`・`\`）、制御文字を含む値は生成せず停止する。

API詳細設計書の`<unitPhaseDirNames.detail>/`や機能設計書の`<unitPhaseDirNames.basic>/`には置かない。その1階層上の設計単位ディレクトリへ置く。`unitPhaseDirNames.basic`・`unitPhaseDirNames.detail`はoutput-layoutの`unitPhaseDirNames.basic`・`.detail`の値（既定値`basic-design`・`detail-design`）であり、scaffold-design-unit.shが実際に展開する配置フォルダ名と一致させる（1-210）。

| 種別 | page-data | HTML |
|---|---|---|
| screen | `<output_dir>/<screenUnitRoot>/screen-<ID>/シーケンス図-data.json` | `<output_dir>/<screenViewRoot>/screen-<ID>/シーケンス図.html` |
| api | `<output_dir>/<apiUnitRoot>/<unit-dir>/シーケンス図-data.json` | `<output_dir>/<apiUnitRoot>/<unit-dir>/シーケンス図.html` |
| feature | `<output_dir>/<featureUnitRoot>/<unit-dir>/シーケンス図-data.json` | `<output_dir>/<featureUnitRoot>/<unit-dir>/シーケンス図.html` |

## 対象種別と一覧列の契約

`references/sequence-kind-policy.json` を本スキル内の生成可否定義として最初に読む。

| 種別 | 生成 | 順序の定義元 | 一覧の扱い |
|---|---|---|---|
| 画面 | する | facts.yml の `call_order` | HTML実在時だけ `sequencePath` を設定 |
| API | する | API詳細設計書 §4.1「処理順序」 | HTML実在時だけ `sequencePath` を設定 |
| 機能 | する | 機能設計書 §3.1「正常系フロー」 | HTML実在時だけ `sequencePath` を設定 |
| テーブル・バッチ・帳票・外部連携・メッセージ | しない | 設計文書に呼び出し順序表がない | マニフェストから `sequencePath` を省き、関連資料セルへシーケンス図の欄・未作成表示を出さない |

生成対象でも、順序表が空、プレースホルダだけ、順番号が欠落・重複・逆転している場合は推測せず生成しない。この場合も `sequencePath` は設定しない。`sequencePath` は `シーケンス図.html` の実在確認後にだけ、各一覧HTMLからの安全な相対URLとして設定する。非対象種別ではnullを入れるのではなくキー自体を省く。

## page-data の形状

各設計単位の page-data は以下の共通形状を持つ。既存画面dataの `screenId` / `screenLabel` は後方互換として受け入れるが、新規dataは `unitKind` / `unitId` / `unitLabel` を正とする。

```json
{
  "unitKind": "screen",
  "unitId": "screen-order-list",
  "unitKey": "order-list",
  "unitLabel": "注文一覧",
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
- operation先頭は種別ごとに異なる。screenは`user→screen`の「操作開始」、apiは`caller→api`の「リクエスト受信」を根拠行のない合成triggerとする。featureは§3.1の先頭行を`user→最初の構成要素`のtriggerへ変換する
- `sourceRef`はscreenのfacts由来step、apiの合成triggerを除くstep、featureの全stepで省略しない。手書きpage-dataで参照先が無いstepに限り省略でき、その場合はテンプレート側で参照先列を空表示する

## エンジンスクリプトの所在

| スクリプト | パス（スキルフォルダ基点） |
|---|---|
| プレースホルダ置換 | `../../../generation-engine/scripts/render-template.sh`（`render_template` 関数。用途に合わない場合のみ Phase 3 で手順記載の Bash ワンライナーに切り替える） |
| ポータル再生成（任意） | `../../../generation-engine/scripts/build-portal.sh` |

テンプレートは `../../../delivery-payload/templates/screen-sequence-template.html` を使う。

## 進捗管理（必須手順）

スキル開始時に `TaskCreate` で Phase 1〜3 のタスクを登録する。各 Phase 開始時に該当タスクを `in_progress` に、完了時に `completed` へ `TaskUpdate` で更新する。実行環境に TaskCreate/TaskUpdate が存在しない場合は `$CLAUDE_JOB_DIR/tmp/task-ledger.md` で同等の Phase 遷移記録を代替する。

## 基本ワークフロー

## Phase 1: page-data の確保

## Step 1-1: 既存 page-data の確認

**使用ツール**: Read / Glob / Grep / TaskCreate / TaskUpdate

本Stepの冒頭で `TaskCreate` により Phase 1〜3 のタスクを登録し、以降は各 Phase の開始・完了で `TaskUpdate` を発行する（詳細は上記「進捗管理（必須手順）」節）。

Read / Glob / Grep で対象単位ごとの `シーケンス図-data.json` の実在を確認する。存在すれば内容を読む。`unitKind`・`unitId`・`unitLabel`と、`operations[].key`・`label`・`steps[]`の形状を確認する。既存画面では`screenId`・`screenLabel`も受け入れる。

policyで`generate: false`の種別は、既存の`sequencePath`をマニフェストから除く。page-dataとHTMLは生成せず、Phase 3の一覧確認へ進む。

**完了**: 各対象単位についてpage-dataの実在有無・形状、またはpolicyによる非対象を確認済み。

## Step 1-2: facts から page-data へ変換

対象種別で変換元を分岐する。

- `screen`は、以下の既存手順どおりfacts.ymlの`call_order`から変換する
- `api`は、`API詳細設計書.md`の§4.1「処理順序」表だけを読む
  - `順`の昇順で1行を1stepへ変換する
  - 先頭は`caller→api`の「リクエスト受信」とする
  - 各処理行は`api→internal`、末尾は`api→caller`のreturnとする
  - 処理名をlabelへ転記し、`sourceRef`には設計書の相対パス・節・表行を記録する
  - 表の参照先列と関数名は参照先の確認と補助表示に使う
  - 順番号が正の整数で一意かつ連続しない場合は生成しない
- `feature`は、`機能設計書.md`の§3.1「正常系フロー」表だけを読む
  - `順`の昇順で1行を1stepへ変換する
  - `実行主体`と`構成要素`を出現順にlane化する
  - 直前行の構成要素から当該行の構成要素へ`処理`をlabelとして結ぶ
  - 先頭行の起点だけは`user`とする
  - §7.1は表示名と個別設計書への参照補助に使い、§3.1に無い順序を補わない
  - 順番号が正の整数で一意かつ連続しない場合は生成しない

API・機能の設計書由来stepは、設計書の相対パスと節・表行（例: `API詳細設計書.md#§4.1-row-2`）を`sourceRef`に必ず持つ。
APIの合成triggerだけは対応する表行がないため`sourceRef`を持たない。
空表や`<...>`だけのテンプレート行は0件として扱い、推測でstepを作らない。

不在の画面については、Read で同ディレクトリの facts.yml（`facts_ref`。`extracting-unit-facts-from-code` が確定済みの前提）を読む。⑤handler の各 item が持つ任意フィールド `call_order`（形式 `"<連番>:<api分類のkey>@<file:line>; ..."`。`delivery-payload/references/facts-schema.md` の「call_order（⑤handlerの任意フィールド）」節が正本）を持つ handler だけを対象に、Write で `operations[]` へ機械変換する。

### ステップ表示文言の導出

- `steps[].label` に⑧api分類 item の `value` を生の文字列としてそのまま転記しない。`value` には代入式（`=`）・引数リテラル（丸括弧）・タブ区切りの分類タグが含まれ、そのまま表示すると呼び出しの意味が読み取れないため
- 表示文言は呼び出し先の**業務名**にする。導出根拠は優先順に (1) 原本の該当行に付いた日本語コメント（`value`/`evidence` から読み取れる範囲）、(2) 呼び出し先の関数名・BL 名（⑧api分類 item の識別子部分。代入・引数を除く）とする
- 代入演算子（`=`）・引数の丸括弧とその中身（`(...)`）・タブ区切りの分類タグは表示文言から落とす。これらは根拠欄（`sourceRef`）が追跡性を担うため、表示文言に原本の文字列を残す必要はない
- **根拠のない機能名を作らない**。日本語コメントからも関数名・BL 名からも業務名を導出できない呼び出しは、呼び出し先の識別子（BL 名そのもの）だけを表示文言にする。読み手に伝わりやすくするための推測で業務的な名前を捏造しない
- `sourceRef` は `call_order` エントリの `file:line` をそのまま転記する（facts 由来のステップでは省略しない）。`api→screen`（`kind: "return"`）の合成応答ステップは、対応する呼び出し元 `call_order` エントリと同一の `file:line` を `sourceRef` として引き継ぐ

### operations[] への組み立てと分割

- `operations[].key`/`label` は handler item の `key`/`value`（実行される要素・処理1行要約）から組み立てる。1 handler の `call_order` から変換したステップ数が 15 を超える場合は、以下の基準の優先順で複数の `operations[]` へ分割する
  1. 同じ画面の設計文書（画面基本設計書等）が機能の一覧を持つ場合は、その機能単位へ対応付けて分割する
  2. 機能単位が無い、または分割後もなお 15 ステップを超える区分がある場合は、原本のコメント区切りのような根拠のある単位（関数内のブロックコメント境界等）で局面へ分ける
  3. 2 を適用してもなお 15 ステップを超える区分が残る場合は、その区分内に限り 3（機械的な15ステップ区切り）を併用してよい。2 と 3 は排他ではなく、2 で収束しない区分だけに 3 を重ねて適用し収束させる。1・2 のいずれも適用できない場合（コメント境界そのものが無い等）は、全体をソース出現順（`call_order` の連番順）に 15 ステップごとで機械的に区切る
  - **呼び出しが0件の区分の扱い**: コメント境界で区切った結果、呼び出し（`call_order` エントリ）を1件も含まない区分は、局面として生成しない。当該区分の見出し・コメント自体は局面名の根拠にせず、直前または直後の区分（呼び出しを含む側）へ吸収する。前後どちらに吸収するかはソース出現順で連続する側を優先する
  - **分断してはならない呼び出しの並びの扱い**: 単一のAPI呼び出しに対応する一連の呼び出し（例: データベース直接アクセスの準備・実行・取得のような、同一の呼び出し先に対する連続したstepの塊）は、3 の機械的な15ステップ区切りの境界で分断しない。3 を適用する場合、区切り境界はこの塊の直前・直後（塊全体が同じ局面に収まる位置）にのみ置く。塊の内部で15ステップに達した場合は、その塊を含む局面の上限を一時的に緩め、塊の終端まで含めてから次の局面へ区切る
  - 分割後の `operations[].key`/`label` は連番を使わない。各区切りの先頭ステップに導出できた業務名（導出できなければ先頭呼び出しの識別子）を局面名として使い、内容を要約した意味語で組み立てる（例: `save-click` の分割なら `save-click-validate` / `save-click-persist`）
  - 分割後も各operationの先頭に利用者→画面の「操作開始」を追加し、call_order由来stepの`seq`を1つ繰り下げる。各 `operations[].steps[].seq` は操作ごとに 1 始まりの連番へ振り直す（Step 1-3 の jq 検証は操作単位で連番性を見るため）
  - 分割は呼び出しの追加・削除・重複を行わない。分割前後で `call_order` から機械変換されたステップの総数（合成 return ステップを除く）は変わらない
  - 15 ステップ以下の handler は分割せず 1 handler = 1 operation のまま変換する
- 各operationの先頭へ`from: "user"`・`to: "screen"`・`label: "操作開始"`・`kind: "trigger"`の合成stepを追加する。ドメイン固有文言と`sourceRef`は付けず、call_order由来stepの`seq`はすべて1つ繰り下げる
- `call_order` の各エントリを `steps[]` に変換する: `from: "screen"`・`to: "api"`
- API 呼び出しに対応する DB アクセス（⑧api分類 item の value・evidence から読み取れる範囲）が facts 側に記録されている場合のみ `api→table` の step を追加する。記録がなければ `api→screen`（`kind: "return"`）で応答だけを 1 step として閉じる
- 合成した「操作開始」を除くstepに存在する`sourceRef`を行番号除去して正規化し、そのパスの一意数が1なら、そのoperationのstep endpointにある`api`を`internal`へ機械置換する。`operation.lanes`から`api`を除いて`{"key":"internal","label":"内部処理"}`を置き、table等の実際に使う他レーンは保持する。一意パス数が複数ならAPI endpointとレーンを維持する。0なら単一判定を適用せず、手書きpage-data等の既存endpointを変換しない
- `operation.lanes`は`user`を先頭にし、続けて`screen`、`internal`または`api`、`table`等を、そのoperationのstep endpointに最初に現れる順で定義する。根拠なしに「内部処理」より具体的な実体名を推測しない
- facts.yml が実在し、`call_order` を持つ handler が 1 件もない画面は、推測で操作を補わず `operations: []` の page-data を機械生成する。テンプレートの空状態までレンダリングし、「呼び出し順序の記録なし」と報告する。操作が0件になる主な原因は、対象画面のイベントハンドラがJSX属性への直接記述（インラインアロー関数等）のみで構成され、事実抽出の定義（`extracting-unit-facts-from-code` の⑤イベントハンドラ抽出）がこれを対象外とすることによる。バグではなく設計上の既知の限界であり、対象画面が名前付き関数（`handle`/`on`命名の関数宣言、またはJSXイベント属性から参照される関数宣言）を持つように改修された場合、事実抽出は当該ハンドラを自動的に対象へ含めるようになりこの限界は解消する
- facts.yml 自体が存在しない画面だけは変換不能として報告し、手書き page-data の作成をユーザーに依頼して当該画面をスキップする（捏造しない）

**完了**: facts.yml が実在する画面は、操作 0 件を含めすべて `シーケンス図-data.json` を書き出し済み。facts.yml 不在の画面は報告済み。

## Step 1-3: page-data の検証

Bash で組み立てた JSON を jq 検証する。必須キー、操作ごとの有効レーン、seq連番、先頭の利用者起点step、単一sourceRef時の内部処理レーンを確認する。レーン検証は`operation.lanes`、page-data直下の`lanes`、固定4本の順で採用する。

```bash
jq -e '
  def source_path:
    sub("(#[Ll][0-9]+(-[Ll]?[0-9]+)?|:[0-9]+(-[0-9]+)?)$"; "");
  ((if ((.unitKind // "screen") == "screen")
    then (.unitId // .screenId)
    else (.unitId // .unitKey)
    end) and (.unitLabel // .screenLabel) and .operations) and
  . as $page |
  ((($page.unitKind // "screen") == "screen") or (($page.operations | length) > 0)) and
  (.operations | all(
    . as $op |
    (if (($op.lanes // []) | length) > 0 then [$op.lanes[].key]
     elif (($page.lanes // []) | length) > 0 then [$page.lanes[].key]
     else ["user","screen","api","table"] end) as $lanes |
    ($op.steps | all(.from as $f | .to as $t |
      ($lanes | index($f)) != null and ($lanes | index($t)) != null)) and
    (($op.steps | map(.seq)) as $seqs |
      $seqs == ([range(1; ($seqs | length) + 1)])) and
    ($op.steps[0].kind == "trigger") and
    (if (($page.unitKind // "screen") == "screen") then
      ($op.steps[0].from == "user" and
       $op.steps[0].to == "screen" and
       $op.steps[0].label == "操作開始" and
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
    elif $page.unitKind == "api" then
      (($op.steps | length) >= 3) and
      ($op.steps[0].from == "caller" and
       $op.steps[0].to == "api" and
       $op.steps[0].label == "リクエスト受信" and
       ($op.steps[0] | has("sourceRef") | not)) and
      ($op.steps[1:-1] | all(
        .from == "api" and .to == "internal" and
        (.sourceRef // "") != "")) and
      ($op.steps[-1].from == "api" and
       $op.steps[-1].to == "caller" and
       $op.steps[-1].kind == "return" and
       $op.steps[-1].label == "レスポンス返却" and
       ($op.steps[-1].sourceRef // "") != "")
    elif $page.unitKind == "feature" then
      ($op.steps[0].from == "user") and
      ($op.steps | all((.sourceRef // "") != ""))
    else false end)
  ))
' "<対象単位のシーケンス図-data.json>"
```

**完了**: 順序の定義元が実在する対象単位すべてでjq検証が通過済み。順序を導けない単位は生成省略を記録済み。

## Phase 2: DOC_NAV の組み立て

## Step 2-1: 階層ナビゲーションの確定

Glob / Read で実在ファイルを確認し、対象単位の設計書ビューアと同じ体裁の左サイドバー用doc-navを組み立てる。画面は既存のscreenViewRoot経路、API・機能は対象設計書と同じ単位ディレクトリを基点にする。実在判定はシーケンス図.html側の視点（アクティブ項目がシーケンス図）で行う。

- **戻るリンク**: `<a class="back-link" href="<画面一覧.htmlへの相対パス>">← 画面一覧へ戻る</a>`。`<output_dir>/<screenListDir>/画面一覧.html`（既定 `project-portal/lists/screens/画面一覧.html`）への相対パスを算出する（出力先は `<screenViewRoot>/screen-<ID>/` 直下で、既定値どうしの組では `../../lists/screens/画面一覧.html` が典型値）
- 画面の基本設計・詳細設計のフォルダ名は`${screen_basic_dirname}`・`${screen_detail_dirname}`とする。値はそれぞれ`基本設計`・`詳細設計`固定であり、scaffold-screen.shが展開する画面専用の配置規約に従う（画面はunitPhaseDirNamesの対象外。1-210の対象外）
- **基本設計項目**: `${screen_view_dir}${screen_basic_dirname}/画面基本設計書.html` が実在すれば `<a class="nav-item" href="${screen_basic_dirname}/画面基本設計書.html">基本設計</a>`
- **詳細設計項目**: `${screen_view_dir}${screen_detail_dirname}/画面詳細設計書.html` が実在すれば `<a class="nav-item" href="${screen_detail_dirname}/画面詳細設計書.html">詳細設計</a>`
- **シーケンス図項目**: 自ページなので `<span class="nav-item active">シーケンス図</span>`
- 実在しない項目は追加しない（存在しない基本設計・詳細設計への空リンクを作らない）
- **API**: 戻るリンクはAPI一覧。`API基本設計書.html`・`API詳細設計書.html`の実在する方だけを追加する
- **機能**: 戻るリンクは機能一覧。`機能設計書.html`が実在するときだけ「機能設計書」を追加する

**完了**: 対象単位ごとにdoc_nav文字列が確定済み、かつWriteツールで`$CLAUDE_JOB_DIR/tmp/doc-nav-<種別>-<ID>.html`へ書き出し済み。doc_navは二重引用符を含むHTML属性（`href="..."`等）を持つため、Step 3-1の`bash -c '...'`内へ文字列結合で埋め込まない。

## Phase 3: HTML 生成

## Step 3-1: テンプレートのレンダリング

以下のようにBashから`render_template`を呼び出し、Writeで対象単位の`シーケンス図.html`を生成する。例はscreen経路である。apiでは`page_data`と出力先を`<apiUnitRoot>/<unit-dir>/`へ、featureでは`<featureUnitRoot>/<unit-dir>/`へ置き換え、`{{SCREEN_LABEL}}`へ`unitLabel`を渡す（テンプレートのプレースホルダ名は後方互換のため維持する）。`render-template.sh`はbash関数を提供するのみでCLIエントリポイントを持たないため、Bashツールからインラインで実行する（新規`.sh`ファイルは作らない）。

**doc_nav はファイル経由で渡す（必須）**: Step 2-1 で書き出した `$CLAUDE_JOB_DIR/tmp/doc-nav-<ID>.html` を、単一引用符のシェルブロック内で `cat` して読み込む。`page_data`／`template`／`tokens_css` と同じ「実体はファイルに置き、スクリプト本体には値を直接埋め込まない」形にする。doc_nav の文字列そのものをシェルブロック内の二重引用符代入へ文字列結合で埋め込むことを禁止する（引用符境界が壊れ、シェルが閉じない引用符を待って停止する）。

  ```bash
  bash -c '
    source "<スキルフォルダ>/../../../generation-engine/scripts/render-template.sh"
    . "<スキルフォルダ>/../../../generation-engine/scripts/shell-injection.sh"
    template="$(cat "<スキルフォルダ>/../../../delivery-payload/templates/screen-sequence-template.html")"
    tokens_css="$(cat "<スキルフォルダ>/../../../delivery-payload/templates/tokens.css")"
    page_data="$(cat "<output_dir>/<screenUnitRoot>/screen-<ID>/シーケンス図-data.json")"
    doc_nav="$(cat "$CLAUDE_JOB_DIR/tmp/doc-nav-<ID>.html")"
    operation_list="<div class=\"operation-list\" id=\"operation-list\"></div>"
    doc_sidebar_html="<nav class=\"pt-doc-nav\" aria-label=\"操作\"><div class=\"pt-doc-nav__group\">画面 / 設計書</div>${doc_nav}<div class=\"pt-doc-nav__group\">操作</div>${operation_list}</nav>"
    render_args=(
      "{{PROJECT_NAME}}" "<プロジェクト名>" \
      "{{GENERATED_DATE}}" "<YYYY-MM-DD>" \
      "{{COMMIT_SHORT}}" "<短縮コミットハッシュ本体のみ。空文字可>" \
      "{{PORTAL_INDEX_HREF}}" "<ポータルindex.htmlへの相対パス>" \
      "{{SCREEN_LABEL}}" "<画面ラベル>" \
      "/* TOKENS_CSS */" "$tokens_css" \
      "{{PAGE_DATA_JSON}}" "$page_data"
    )
    shell_injection_args "<スキルフォルダ>/../../../delivery-payload/templates" "<スキルフォルダ>/../../../delivery-payload/templates/../references/portal-catalog.json" "<ポータルindex.htmlへの相対パス>" "<プロジェクト名>" "<YYYY-MM-DD>" "<短縮コミットハッシュ本体のみ。空文字可>" "generating-sequence-diagram-for-reverse-docs" "list" "" "" "$(dirname "<output_dir>/<screenViewRoot>/screen-<ID>/シーケンス図.html")" "$doc_sidebar_html"
    if [ ${#SHELL_RENDER_ARGS[@]} -gt 0 ]; then
      render_args+=("${SHELL_RENDER_ARGS[@]}")
    fi
    out="$(render_template "$template" "${render_args[@]}")"
    printf "%s\n" "$out" > "<output_dir>/<screenViewRoot>/screen-<ID>/シーケンス図.html"
  '
  ```

**手作業でのプレースホルダ置換（sed・perl 直書き等）は禁止する**。`render_template` は最短前方一致で置換するため、値の中に他プレースホルダ文字列が偶然含まれても誤爆しない。`{{DOC_NAV}}` はテンプレート本体からは削除済みで、Phase 2 で確定した doc_nav 文字列は `doc_sidebar_html`（共通サイドバーの `{{DOC_SIDEBAR}}` へ注入される操作ナビ）の組み立てにのみ使う。

**`{{GENERATED_DATE}}`/`{{COMMIT_SHORT}}` の値の形**: `{{COMMIT_SHORT}}` には区切り文字・ラベル（「コミット」等）を含めず、短縮コミットハッシュ本体（例 `a1b2c3d4`）のみを渡す。日付との区切りとラベル表示は共通シェル（`delivery-payload/templates/partials/shell-sidebar.html`/`shell-footer.html`）側が担い、値が空文字の場合は当該シェルの実行時 JS（`removeIfEmptyCommit`）が空表示を自動で取り除く。呼び出し側で `" · コミット番号: <sha>"` のような区切り込みの値を渡すと二重表記になるため禁止する。

**完了**: 順序を導ける対象単位すべてで`シーケンス図.html`が生成済み。

## Step 3-2: ポータルへの反映

生成したHTMLの実在を確認してから、次の規則でrawマニフェストの対象`units[]`へ`sequencePath`を設定する。

1. apiは`<output_dir>/<apiManifest>`、featureは`<output_dir>/<featureManifest>`を更新する。入力単位の`unitId`が空でなければ`unitId`、空なら`unitKey`が対象値と完全一致する1要素だけを選ぶ。0件・複数件なら更新せず停止する
2. 一覧HTMLはoutput-layoutの`unitListHtml`へ`kindLabels.api`（API）または`kindLabels.feature`（機能）を渡して解決する。`sequencePath`は、そのHTMLの親ディレクトリから上表のHTMLまでのPOSIX相対pathとする
3. rawマニフェストを正として対象一覧スキルの抽出Phaseを再実行し、`<apiManifestExt>`または`<featureManifestExt>`を再生成する。派生マニフェストだけを直接編集しない
4. `validate-manifest.sh <manifest.ext.json> --unit-kind <api|feature>`を通し、対象一覧スキル記載の`build-unit-list.sh`コマンドで一覧を再生成する。関連資料セルにシーケンス図リンクが1件現れ、hrefが`sequencePath`と一致することを確認する

policyで`generate: false`の種別は、対応するrawマニフェストの全`units[]`から`sequencePath`キー自体を削除し、同じ一覧スキル経路で派生マニフェストと一覧を再生成する。関連資料セルは他の実在資料を維持しつつ、「シーケンス図」リンクも未作成表示も0件であることを確認する。

`portal_output_dir` が指定されていれば Bash で `build-portal.sh` を再実行する。未指定なら省略し完了報告に注記する。

**完了**: ポータルを再実行済み、または省略理由を注記済み。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | screen・api・featureは各定義元からpage-dataを組み立てて検証済み。非対象種別と順序を導けない単位は生成しない理由を確定済み |
| Phase 2 | 対象単位ごとにdoc_nav文字列（戻るリンク＋実在する設計書項目のみ）が確定済み |
| Phase 3 | 対象単位の`シーケンス図.html`が生成され、実在するHTMLだけが`sequencePath`に反映済み。非対象種別の一覧にシーケンス図欄がない |
| **Goal** | 画面・API・機能のうち順序を定義元から導ける単位にシーケンス図が生成され、導けない種別・単位の一覧にはシーケンス図欄が現れない |

## 重要な注意事項

- 判定・評価はしない。呼び出し順序や処理内容の良否には踏み込まず、facts（call_order）または手書き page-data に記録された事実のみを転記する
- API・機能では指定した順序表だけを順序の定義元にする。他の節や疑似コードから順序を推測して補わない
- 非対象種別へ空のシーケンス図や「未作成」欄を生成しない。`sequencePath`キー自体を省く
- 「操作開始」は利用者起点を表す非ドメインの合成triggerであり、call_orderの内容を補わない。対応する原本行がないため`sourceRef`を付けない
- `call_order` を持つ handler が 0 件の画面で、AskUserQuestion を使って手動でステップを聞き出さない。`operations: []` として空状態を生成し、検出できない呼び出し順序を即興確定しない
- `generation-engine/scripts/detail-pages/` 配下・`extracting-unit-facts-from-code` 配下・`seal-facts.sh` は変更しない（別スキルの管轄）
- 新規 `.sh` スクリプトファイルは作らない。`render-template.sh` の `render_template` 関数を Bash から直接 source して使う

## 予想を裏切る挙動

- 出力先は`output_dir`直下ではなく設計単位ごとのフォルダになる。screenは`<screenViewRoot>/screen-<ID>/`、api・featureは各UnitRoot配下の対象設計書ディレクトリであり、pageKind体系の「1 pageKind = 1固定ファイル名」契約は適用されない
- `build-portal.sh` は画面設計書（基本設計・詳細設計）側の DOC_NAV にのみシーケンス図項目を追加する。シーケンス図.html 自体の DOC_NAV は本スキルの Phase 2/3 が組み立てる（build-portal.sh の担当範囲外）

## 完了報告

`../../../delivery-payload/references/完了報告の書き方.md` の共通骨格（作業報告型）に従う。固有の検証行: 種別ごとの生成単位数・操作数・データ源（手書きdata / factsのcall_order / API§4.1 / 機能§3.1）・非対象種別の`sequencePath`残存件数。

## 参照資料

- `delivery-payload/references/facts-schema.md` — call_order（⑤handlerの任意フィールド）の形式定義
- `delivery-payload/templates/screen-sequence-template.html` — 設計書共通の階層サイドバーと操作メニューを備えたシーケンス図.html のテンプレート本体
- `generation-engine/scripts/render-template.sh` — `render_template` 関数の実装
- `references/sequence-kind-policy.json` — 生成対象種別・順序の定義元・非対象種別の一覧フィールド省略契約
- `scripts/test-sequence-kind-policy.mjs` — API・機能のHTML生成と非対象種別の一覧表示契約を再実行する自己テスト
