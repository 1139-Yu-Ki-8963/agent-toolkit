---
name: generating-feature-list-for-reverse-docs
日本語名: 機能の一覧を作る
description: "既にある種別ごとの一覧をもとに、画面と接続窓口を業務の機能ごとにまとめた一覧を作る。"
invocation: generating-feature-list-for-reverse-docs
type: transform
allowed-tools: [AskUserQuestion, Bash, Glob, Grep, Read, TaskCreate, TaskUpdate, Write]
---

## いつ使うか

機能一覧を作りたいとき、機能一覧を生成したいとき、業務機能を横断した目録を作りたいとき。

## いつ使わないか

種別ごとの技術的な一覧を作るとき（→ 対応する種別別の一覧を作るスキルを使う）、往復の確かめ・同期・実装を行うとき。

# 正本: reverse-docs-skills

本スキルが生成する納品物は顧客提示の文書である。自由記述の本文（要約・説明文）は敬体（です・ます）で書く。記入規則・検証記録・作業記録は常体でもよい（`delivery-payload/references/設計書様式.md` §8）。

# 機能一覧生成スキル(派生一覧)

工程全体は orchestrating-ai-development-setup が案内する。本スキルは機能一覧の生成のみを担い、単独起動できる(起動引数 source_dir・output_dir の 2 つを渡せば動く)。`unit_kind` は **feature 固定** であり、引数では受け取らない。

既存の種別別一覧(画面を持つ対象では画面一覧が必須、画面を持たない対象では画面該当なしの記録で代替する。API・テーブル等の一覧は任意)を入力として、業務機能の単位(2階層: 大分類 + 機能)に画面・APIをグルーピングして **機能一覧.html** を作成する。**本スキルの仕事は機能一覧.html の作成のみ** であり、設計書の雛形展開・生成・記入は一切行わない。

機能は「コードから直接検出するユニット」ではなく **既存一覧の派生グルーピング(派生一覧)** である。アーキテクチャ調査の存在判定(unit_kinds_present)の対象にならず(機能は常に存在する)、excluded-kinds.json の allKinds にも含めない。

## 設計原則: 固定と可変の分離

マニフェストスキーマ・整合検証(`validate-manifest.sh`)・HTML生成(`build-unit-list.sh` → `build-feature-list.sh`)は決定的スクリプトに固定する。グルーピング(大分類境界の決定・機能分割・関連付け)はプロジェクトごとに可変である。

feature 種別に組み込み検出器はない。抽出は **カスタム抽出パスのみ**: Claude 自身が `references/feature-detection.md`(グルーピング規約の正本)に沿って解析を実行し、スキーマ準拠のマニフェスト JSON(配列キーは `units`)を出力する。機械処理は Phase 5 の検証と生成のみ。

## エンジンスクリプトの参照

エンジンスクリプトは本スキルフォルダからの相対パスで参照する。

- 整合検証: `../../../generation-engine/scripts/unit-list/validate-manifest.sh`
- HTML生成: `../../../generation-engine/scripts/unit-list/build-unit-list.sh`(unit_kind=feature を内部で `build-feature-list.sh` に委譲する)

正本リポジトリと公開先(payload)はディレクトリレイアウトが同一のため、この相対参照は両環境でそのまま成立する。

## 使用タイミング

- 既存コードベースの機能一覧(業務機能の横断目録)を作りたいとき
- 前提: raw画面正本(`<output_dir>/<manifestsRoot>/screen-manifest.json`)が生成済みであること
- 起動引数: `source_dir`(ソースコードディレクトリ)・`output_dir`(一覧の出力先。既存6種と同じ)・`survey_doc_path`(任意。アーキテクチャ調査書。ルート定義等の所在特定の参考)

## 出力

| 項目 | 値 |
|---|---|
| 出力フォルダ | `<output_dir>/<unitListDir>`（`unitListDir` は output-layout の物理配置キーで {label} は「機能」） |
| 出力ファイル | `機能一覧.html` |
| マニフェスト配列キー | `units` |

永続マニフェスト（`feature-manifest.json`・`feature-manifest.ext.json`）は HTML と同じフォルダではなく `<output_dir>/<manifestsRoot>/` に永続化する。`manifestsRoot` は output-layout の物理配置キー（既定値 `docs/manifests`）。

## 進捗管理(必須手順)

スキル開始時に `TaskCreate` で Phase 1〜6 のタスクを登録する。各 Phase 開始時に該当タスクを `in_progress` に、完了時に `completed` へ `TaskUpdate` で更新する。Phase 5 から Phase 2〜4 へ差し戻す場合は該当タスクを `in_progress` に戻す。実行環境に TaskCreate/TaskUpdate が存在しない場合は、出力先ディレクトリ内のタスク台帳ファイル(`task-ledger.md`)で同等の Phase 遷移記録を代替する。

## 動作フロー(Phase 1〜6)

グルーピング規約の詳細は `references/feature-detection.md` を参照する。

## Phase 1: 入力収集

## Step 1-1: 入力収集

- **Step 1**: raw画面正本`<output_dir>/<manifestsRoot>/screen-manifest.json`を直接入力にし、`validate-manifest.sh <raw> --unit-kind screen`を実行する。raw画面正本の扱いは画面種別の実在で分岐する。`<output_dir>/<unitListAbsentMd>`（`unitListAbsentMd` は output-layout の物理配置キー。`{label}` に「画面」を代入。既定値 `docs/manifests/画面一覧（該当なし）.md`）が実在する場合、画面を持たない対象と判定し、raw画面正本を要求せず `strategy.screenPresence` に `none` を記録して次へ進む。該当なしの記録が無く raw画面正本も不在、または schema 不合格なら status=ERROR で停止し、hintに「先にgenerating-screen-list-for-reverse-docsを実行」と記録する。raw画面正本が実在する場合は `strategy.screenPresence` に `present` を記録する。通常生成では画面一覧HTMLの埋め込みJSONを逆抽出しない。旧成果物からの移行・復元時だけ`restore-screen-manifest.sh`でrawを正規配置へ復元・検証してから本Phaseを再開する。他種別は`<output_dir>/<unitsRoot>/`配下に実在する一覧HTMLを機械的に列挙し、`id="unit-manifest"`からJSONを抽出する。raw画面正本と実在した他種別一覧のパスをすべて`strategy.inputManifests`に記録する(ユーザー指示は不要)。完了条件: raw画面正本がschema検証済みで、inputManifestsが確定している
- **Step 2**: `source_dir` からルート定義・ナビメニュー・バックエンドルーターの prefix/tags・ディレクトリ構造を Grep/Read で特定する。survey_doc_path があれば所在特定の参考にする。完了条件: 手がかり①〜④(feature-detection.md の優先度表)の抽出元ファイルが列挙済み

**完了**: 画面一覧マニフェスト抽出済み・inputManifests 確定・手がかり①〜④の抽出元が列挙済み・API/テーブル grep パターン特定済み

## Phase 2: 大分類候補の導出

## Step 2-1: 大分類候補の導出

**使用ツール**: Write

- **Step 1**: ルートprefix第1セグメント(手がかり①)で大分類の境界を引く。ナビメニュー・設定ハブの表示文言(手がかり②)は名前付けのみに使い、境界の決定には使わない。完了条件: 候補表(大分類キー・根拠・所属画面数)が作成済み
- **Step 2**: APIプレフィックス/tags(③)・ディレクトリ構造(④)で裏取りし、競合があれば feature-detection.md の競合解決フローに従う。完了条件: 全画面が大分類候補に割当済み、または割当根拠ゼロとして unresolved 候補に分類済み
- **Step 3**: 大分類が細分化しすぎる場合(機能1件のみの大分類が過半、または大分類数が10超)、`references/feature-detection.md` の「大分類の統合規則」に従い上位の業務領域へ統合する。境界(機能の分割)は変えない。完了条件: 大分類数が目安(5〜10)に収まっている、または収まらない理由が記録済み

**完了**: 候補表が作成済みで全画面が大分類候補または unresolved 候補に分類済み

## Phase 3: 画面→機能グルーピング + 完全性ゲート(Stage 1)

## Step 3-1: 画面→機能グルーピング + 完全性ゲート(Stage 1)

**使用ツール**: Bash / Write

- **Step 1**: 大分類内で画面群を機能単位(同一業務対象への操作一式。CRUD集約)に分割する。完了条件: グルーピングが完了し各画面に機能が割り当てられている

集約キー(`unitKey`)は機能一覧の全要素で一意にする。同一の集約キーが2件以上生じた場合、集約元の情報を付加して個別の値にするか、集約の単位そのものを見直す。重複したまま出力すると、権限マトリクス生成の入力検証で停止する(`generation-engine/scripts/unit-list/validate-manifest.sh` の一意性検査と `generation-engine/scripts/extract/build-matrix-data.sh` の重複検出が捕捉する)。

- **Step 2(完全性ゲート)**: 画面一覧の全 screenKey が「いずれかの機能の relatedScreens」または「unresolved 行」に載っているかを機械検査する。未割当が1件でもあれば Step 1 へ差し戻す。`strategy.screenPresence` が `none` の対象では、画面に関する照合を対象外とする。

```bash
# 未割当の screenKey を検出(空なら PASS、非空なら Step 1 へ差し戻し)
comm -13 \
  <(jq -r '.units[] | .relatedScreens[]?' feature-manifest.json | sort -u) \
  <(jq -r '.screens[].screenKey' screen-manifest.json | sort -u)
```

- **Step 3**: スキーマ準拠のマニフェスト JSON を一時ディレクトリ(`$CLAUDE_JOB_DIR/tmp/feature-manifest.json`、未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下)に Write する。確定後は `<output_dir>/<manifestsRoot>/feature-manifest.json` へ一時ファイル + rename で原子的に永続化する。一時ファイルを後続・再開処理の入力にしてはならない。この時点で `relatedApis`・`relatedTables` は空配列とする。機能を捏造しない。完了条件: マニフェスト JSON が生成済みで完全性ゲート PASS

**完了**: 全画面が relatedScreens または unresolved に載り(完全性ゲート PASS)、マニフェスト JSON が生成済み(relatedApis/relatedTables は空配列)

## Phase 4: API紐付け + テーブル紐付け(Stage 2 + Stage 3)

## Step 4-1: API紐付け + テーブル紐付け(Stage 2 + Stage 3)

**使用ツール**: Read / Bash / Write

Phase 1 で特定したプロジェクト固有の API 呼び出しパターンと ORM/モデル参照パターンを使い、構造化された手順で related* を埋める。手順の詳細は `references/feature-detection.md` の「Stage 2: API紐付け手順」「Stage 3: テーブル紐付け手順」を参照する。

- **Step 1(Stage 2: API紐付け)**: 各機能の relatedScreens に含まれる画面について、画面マニフェストの `files[]`(なければ `entryFile` にフォールバック)から API 呼び出しパターンを grep し、API一覧マニフェストの `units[].identifier` に照合する。一致した `unitKey` を当該機能の `relatedApis` に記録する。照合できない endpoint は残余リストに記録し、パスパラメータ差異等の曖昧一致のみ Claude が裁定する(推測禁止)。完了条件: 全機能の relatedApis が確定済み(空配列を含む)
- **Step 2(Stage 3: テーブル紐付け)**: Step 1 で紐付いた API unitKey について、API一覧マニフェストの `units[].sourceFile` からモデル/テーブル参照を grep し、テーブル一覧マニフェストの `units[].unitKey` に照合する。一致した `unitKey` を当該機能の `relatedTables` に記録する。照合できない参照は残余リストに記録し Claude が裁定する。**relatedApis が空のまま残った機能**(画面が API を経由せず直接データアクセスする構成。1-152)は、本 Step では手を出さず Phase 6 Step 1 の直接データアクセス経路(Stage 3b・`extract-feature-metadata.sh`)に委ねる。完了条件: 全機能の relatedTables が確定済み(空配列を含む)
- **Step 3(組み立て)**: Stage 2・Stage 3 の結果をマニフェスト JSON にマージする。各機能の confidence を確定する。完了条件: マニフェスト JSON の relatedApis・relatedTables・confidence が全機能分記録済み

Stage 2 → Stage 3 の実行順はデータ依存(Stage 3 は Stage 2 の出力する API unitKey を入力とする)により固定。ただし各画面・各 API の処理は独立しておりサブエージェント並列委任が可能。API一覧またはテーブル一覧が未生成の場合、該当する related* は空配列のまま PASS とする。

**完了**: 全機能の relatedApis・relatedTables・confidence が確定済み(直接データアクセス経路が必要な機能は Phase 6 Step 1 で確定)

## Phase 5: 戦略・構成のユーザー承認

## Step 5-1: 戦略・構成のユーザー承認

- **Step 1**: 大分類と機能の構成案(unresolved 行・relatedApis・relatedTables を含む)を AskUserQuestion で提示する。応答は (A) 構成案どおり承認 / (B) 修正指示(大分類・機能の統合/分割・unresolved の割当指示・related* の修正)の2系統で受け、(B) なら該当部分の Phase 2〜4 を再実行して再提示する。承認で `strategy.approvedByUser: true` をマニフェストに記録する。unresolved 行に割当指示がなければ unresolved のまま出力してよい(人間への引き継ぎ事項であり、残置もスキル完了とみなす)。完了条件: approvedByUser: true が記録済み

**完了**: 構成案がユーザー承認済み(approvedByUser: true)

## Phase 6: 検証とHTML生成(機械実行)

## Step 6-1: 検証とHTML生成(機械実行)

**使用ツール**: AskUserQuestion / Read / Bash / Write

- **Step 1**: マニフェストへメタデータを付与する。`../../../generation-engine/scripts/extract/extract-feature-metadata.sh <manifest.json> <output_dir>/<manifestsRoot>/feature-manifest.ext.json --screen-manifest <output_dir>/<manifestsRoot>/screen-manifest.json --table-manifest <output_dir>/<manifestsRoot>/table-manifest.json --source-dir <source_dir>` を実行する(テーブル一覧未生成の場合は `--table-manifest` を省略してよい。その場合は直接データアクセス経路がスキップされる)。各機能に `operationClass`(照会/登録/更新/削除/承認/その他)フィールドを追加し、`relatedApis`・`relatedTables` が両方空のまま残った機能について画面の直接データアクセス経路(1-152・feature-detection.md「Stage 3b」参照)で `relatedTables` を補完し、`detectionSummary.diagnostics.emptyRelation` に「関連が全件空の機能」の比率を機械算出した拡張マニフェストを一時ファイル + rename で `<output_dir>/<manifestsRoot>/feature-manifest.ext.json` へ原子的に永続化する。以降の Step では永続化した `feature-manifest.ext.json` を使用する。完了条件: 拡張マニフェストが `<output_dir>/<manifestsRoot>/feature-manifest.ext.json` に永続化済み・`diagnostics.emptyRelation` が算出済み。`strategy.screenPresence` が `none` の対象では `--screen-manifest` を渡さない。スクリプト側は当該引数の不在を許容する。
- **Step 2**: `../../../generation-engine/scripts/unit-list/validate-manifest.sh <manifest.ext.json> --unit-kind feature` を実行する。FAIL 時は指摘に応じて修正し再実行(3回失敗で Phase 3 へ差し戻し)。完了条件: 全項目 PASS
- **Step 3**: 両方向の参照検査を実行する。いずれかが非空なら該当 Phase へ差し戻す

```bash
# Gate A(既存): dangling reference — relatedScreens の参照先が画面一覧に実在するか。strategy.screenPresence が none の対象では、画面に関する照合を対象外とする。
# (relatedApis/relatedTables も対応一覧の units[].unitKey で同型。
# 参照先一覧が未生成の種別は related* が空配列のため自動的に PASS)
comm -23 \
  <(jq -r '.units[] | .relatedScreens[]?' feature-manifest.ext.json | sort -u) \
  <(jq -r '.screens[].screenKey' screen-manifest.json | sort -u)

# Gate B(新設): completeness — 画面一覧の全 screenKey が機能に割り当て済みか。strategy.screenPresence が none の対象では、画面に関する照合を対象外とする。
comm -13 \
  <(jq -r '.units[] | .relatedScreens[]?' feature-manifest.ext.json | sort -u) \
  <(jq -r '.screens[].screenKey' screen-manifest.json | sort -u)
# Gate A・B いずれも空 = PASS。1行でも出力があれば FAIL
```

- **Step 4**: `../../../generation-engine/scripts/unit-list/build-unit-list.sh <manifest.ext.json> <output_dir>/<unitListHtml> --unit-kind feature --portal-dir <output_dir>` を実行する。`--portal-dir` にはポータル（`index.html`）の配置先＝納品物ルート（output_dir=output_dir）を渡し、「ポータルへ戻る」リンクを実在パスに解決させる。build 側が内部で validate を再実行するため、検証を経ない manifest からは生成できない。完了条件: HTML 生成済み

**手作業でのプレースホルダ置換は禁止する**。HTML 生成は必ずスクリプト経由の決定的処理で行う。

**完了**: Step 1で拡張マニフェストに operationClass・`diagnostics.emptyRelation` が付与済み。validate 全項目 PASS・Gate A(dangling) PASS・Gate B(completeness) PASS・機能一覧.html 生成済み。永続マニフェストが `<output_dir>/<manifestsRoot>/feature-manifest.json` に実在する

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 画面一覧マニフェスト抽出済み・inputManifests 確定・手がかり①〜④の抽出元が列挙済み・API/テーブル grep パターン特定済み |
| Phase 2 | 候補表が作成済みで全画面が大分類候補または unresolved 候補に分類済み |
| Phase 3 | 全画面が relatedScreens または unresolved に載り(完全性ゲート PASS)、マニフェスト JSON が生成済み(relatedApis/relatedTables は空配列) |
| Phase 4 | 全機能の relatedApis・relatedTables・confidence が確定済み |
| Phase 5 | 構成案がユーザー承認済み(approvedByUser: true) |
| Phase 6 | Step 1で拡張マニフェストに operationClass・`diagnostics.emptyRelation` が付与済み。validate 全項目 PASS・Gate A(dangling) PASS・Gate B(completeness) PASS・機能一覧.html 生成済み。永続マニフェストが `<output_dir>/<manifestsRoot>/feature-manifest.json` に実在する |
| **Goal** | 検証済みマニフェストのみから HTML が生成され、大分類ごとの機能と関連画面・API・テーブルの対応、および要手動確認が可視化されている |

## 返却

本スキルは orchestrating-ai-development-setup の契約に準拠する。完了時に以下を返す。

- `status`: `DONE | ERROR`
- `artifacts`: 生成した機能一覧.html のパス
- `unit_list_html`: artifacts[0] の汎用名
- `embedded_json_ref`: HTML 内に埋め込んだマニフェスト JSON への参照
- `unit_kind`: `feature`(固定値)
- `feature_manifest_path`: 永続生マニフェスト（`<output_dir>/<manifestsRoot>/feature-manifest.json`）
- `feature_manifest_ext_path`: 永続拡張マニフェスト（`<output_dir>/<manifestsRoot>/feature-manifest.ext.json`）

## ツールリファレンス

| ツール | 用途 |
|---|---|
| Bash | `validate-manifest.sh`・`build-unit-list.sh`・jq 自前検査の実行 |
| Read | 既存一覧HTML・ルート定義・ナビ定義・`references/feature-detection.md` の参照 |
| Grep/Glob | ルート定義・APIプレフィックス・ディレクトリ構造の調査、データ取得コードの追跡 |
| Write | マニフェスト JSON の出力(機能一覧.html 本体はスクリプト経由で生成) |
| AskUserQuestion | Phase 4 の構成案承認 |
| TaskCreate/TaskUpdate | Phase 1〜5 の進捗管理 |

## 推奨手順

- source_dir は対象プロジェクトの実コードルートを指定する。ルート定義とAPIルーターの両方を読むため、モノレポの場合はアーキテクチャ調査書 §10 のサイト一覧で確定した当該サイトのルートディレクトリを渡す。そのサイト内でフロントエンドとバックエンドをまたぐ場合は両方を含む階層まで広げてよいが、サイト境界は越えない
- 大分類の期待数は 5〜10、機能は画面 1〜5 枚につき 1 件が目安。画面数と極端に乖離した場合は分割規約の適用を見直す
- 対象プロジェクトに人手の機能一覧・設計書目録(`docs/` 配下等)が既にある場合は、Phase 4 の承認前にその目録と突合し、大きな乖離を notes に記録する

## 重要な注意事項

- 設計書の雛形展開・生成・記入は一切行わない。本スキルの成果物は機能一覧.html のみ
- Phase 5 の HTML 手作業組み立てを禁止する。`build-unit-list.sh` を必ず経由する
- 機能・大分類を捏造しない。すべての割当に手がかり①〜④いずれかの根拠を持たせ、根拠ゼロは unresolved とする
- related* を推測で埋めない。突合で解決できないものは空のままとする
- 画面該当なしの記録が無い状態で画面一覧が空(screens が 0 件)の場合はハード停止しユーザーに報告する。手動リストを聞き出さない。画面該当なしが記録済みの対象では停止せず、API等の他種別だけで機能を立てる

## 予想を裏切る挙動

- `validate-manifest.sh`・`build-unit-list.sh` は jq に依存する。未インストール環境では事前に導入する
- 大分類の境界はルートprefix(手がかり①)のみで引く。ナビメニューが境界を示唆しても境界には使わない(ナビは全機能を網羅しないため。命名のみに使う)。なお境界を保ったまま大分類名を上位業務領域へ統合することは統合規則(feature-detection.md)で許可されている。画面を持たない対象ではルートprefixが存在しないため、feature-detection.md の「画面を持たない対象の境界決定」に従い APIプレフィックスまたはビルド定義の生成ターゲットへ読み替える
- unresolved が残った状態も status=DONE で完了とする(既存6種の「要手動確認」と同じ扱い。ERROR ではない)
- validate-manifest.sh は related* の参照実在を検査しない(参照整合検査は screen 専用)。Phase 5 Step 2 の jq 自前検査を省略すると不在参照が成果物に混入する
- detectionSummary.unitCount は units 配列の全要素数(unresolved 含む)。機能数として報告する場合は kind=feature 行のみを数える
- マニフェストの配列キーは `screens` ではなく `units` とする
- 出力先は `<output_dir>/<unitListHtml>`。他種別と独立したフォルダを作成する
- `sourceFile` は本スキルでは付与しない(1-254)。機能は複数の実装ファイル(画面・API・実行ファイル)を束ねる集約であり、代表となる単一のソースファイルを持たない。1 ファイルを代表として選ぶ・複数ファイルを一覧で持つのいずれも、根拠なく決めると捏造になる。`unitId` と同じ扱い(非必須フィールド。空のまま出力する)とし、値の確定は求めない
- 機能設計書の前付けでは、マニフェストの `unitId` が非空文字列なら、その値を `feature_id` に写す。`unitId` の鍵が無い場合、値が `null` の場合、または空文字列の場合は `feature_id` を空欄にし、推測で補わない。マニフェストの `sourceFile` が非空文字列なら、その値を `source_ref` に写す。`sourceFile` の鍵が無い場合、値が `null` の場合、または空文字列の場合は `source_ref` を空欄にし、他の情報から生成したり代表ファイルを選んだりしない
- ルート定義に載らない画面(認証ガード内で条件レンダリングされるログイン画面等)は前段の画面一覧の抽出品質に依存する。画面一覧に無い画面は本スキルでは補完しない(画面一覧側の再生成で対処する)

## 完了報告

`../../../delivery-payload/references/完了報告の書き方.md` の共通骨格（作業報告型）に従う。

固有の検証行:
- validate 全項目 PASS・related 参照実在検査 PASS・機能一覧.html の生成成功

## 設計判断

### build-feature-list.sh / feature-list-template.html

**必要性**: 機能一覧は関連画面・関連API・関連テーブルの3列と大分類ごとのセクション分割を持ち、汎用テンプレート(unit-list-template.html・9列固定)に収まらない。既存方針(手作業プレースホルダ置換の禁止・決定的生成)に従い、screen と同じ「専用ビルダー + 専用テンプレート」方式で `build-feature-list.sh` と `feature-list-template.html` に生成処理を固定する。`--self-test` は render_template の単一パス置換がマーカー衝突・バックスラッシュを含む値でも誤爆しないことを回帰検証する。

**代替案を採用しなかった理由**:
- 汎用 `build-unit-list.sh` の列拡張: 列構成とグルーピングが feature 固有であり、全種別共通テンプレートに条件分岐を持ち込むと他5種別の生成に回帰リスクを生む。screen の前例(専用ビルダー分離)に合わせた
- Bash ツール直叩き(Claude が都度プレースホルダ置換): 手作業組み立てによるデータ混入(entryFile=None 等)の実害が過去に発生しており、決定的スクリプト固定が確立済みの再発防止策
- 既存 Makefile ターゲット拡張・package.json scripts 追加: 本リポジトリに Makefile・package.json は存在しない

**保守責任者**: 人手(ユーザー)。マニフェストスキーマ変更時に validate-manifest.sh との整合を同時更新する

**廃棄条件**: generating-feature-list-for-reverse-docs スキルが廃止された時、またはHTML生成が別基盤へ移行した時

### extract-feature-metadata.sh

**必要性**: 機能一覧の各ユニットへ `operationClass`(照会/登録/更新/削除/承認/その他の6値)を付与する処理は、Phase 6 で毎回同じキーワード判定ロジック(優先順を持つ複数カテゴリのキーワード集合との突合)を繰り返し適用する必要があり、Bash ツール直叩きでは判定ロジックが都度手書きになり判定基準がユニット間・実行間でぶれる。他5種別(`extract-batch-metadata.sh` 等)と同じ「決定的スクリプト固定」方針に揃え、`--self-test` で分類ロジックの回帰(6カテゴリ全ての判定・キーワード不一致時の「その他」フォールバック・既存フィールド不変・validate-manifest.sh PASS)を機械保証する。

**代替案を採用しなかった理由**:
- Bash ツール直叩き(Claude が都度キーワード判定): 実行のたびに判定基準が微妙にぶれるリスクがあり、他5種別で確立した「抽出は決定的スクリプト」の方針から逸脱する
- 既存 Makefile ターゲット拡張・package.json scripts 追加: 本リポジトリに Makefile・package.json は存在しない
- `build-feature-list.sh` への処理統合: `build-feature-list.sh` は HTML 生成(検証済み manifest からの決定的変換)を担い、メタデータ抽出(manifest 自体の拡張)とは責務が異なる。他種別の `extract-*-metadata.sh` と `build-unit-list.sh` の分離方針に合わせた

**保守責任者**: 人手(ユーザー)。キーワード集合・優先順を変更する場合は `delivery-payload/references/manifest-schema-extensions.md`「features」節の値域定義と `delivery-payload/templates/unit-list/feature-list-template.html` のバッジ色分けを同時更新する

**廃棄条件**: `operationClass` フィールドがスキーマから廃止された時、または分類ロジックが機械抽出ではなく人手判定に一本化された時
