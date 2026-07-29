---
name: orchestrating-reverse-docs-flow
description: "リバース設計書往復検証フローを統括。 TRIGGER when: リバース検証の進行・工程統括・画面一覧から基準確立まで。 SKIP: 個別工程の単体実行。"
invocation: orchestrating-reverse-docs-flow
type: orchestration
allowed-tools: [Read, Write, Bash, Grep, Glob, AskUserQuestion, TaskCreate, TaskUpdate, Skill, Agent]
---

# リバース設計書往復検証オーケストレーションスキル

リバース設計書往復検証フローの進行係（管理者）。自分では検証・比較・実装を行わず、状態判定 → 子スキルを args 全量指定で Skill 起動 → 返却ブロックの status で検収 → 次工程決定、というループで工程全体を統括する。

子スキル33個は互いを知らず、工程間の受け渡しはすべて本スキルが仲介する（完全仲介方式）。契約の定義は `references/contract.md`。内訳は以下のとおり。

- 一覧生成6: 種別別一覧スキル（`generating-<種別>-list-for-reverse-docs`、例: generating-screen-list-for-reverse-docs）
- 機能一覧1: generating-feature-list-for-reverse-docs（派生一覧）
- マトリクス・対応表生成1: generating-cross-views-for-reverse-docs（派生補完。機能一覧確立後にマトリクス・対応表4ページ+AI設定資産ページを生成）
- 基盤ページ生成5:
  - generating-tech-stack-for-reverse-docs
  - generating-env-guide-for-reverse-docs
  - generating-screen-transition-for-reverse-docs
  - generating-er-diagram-for-reverse-docs
  - generating-glossary-for-reverse-docs
- 工程10:
  - surveying-architecture-for-reverse-docs
  - generating-reverse-common-docs
  - syncing-reverse-env
  - unlocking-reverse-target-screens
  - extracting-unit-facts-from-code
  - generating-reverse-basic-design
  - generating-reverse-detailed-design
  - rebuilding-screen-unit-from-docs
  - rebuilding-code-from-docs
  - running-reverse-screen-batch

## 使用タイミング

- リバース検証を工程統括したいとき（アーキテクチャ調査から基準タグ確立までの一連の流れ）
- 個別工程だけを動かしたい場合は各子スキルを単独起動する（各子スキルは同じ args を手渡せば単独でも動く契約）

## 起動引数

| 引数 | 必須 | 内容 |
|---|---|---|
| headless | 任意（既定 false） | true の場合、無人モードで実行する。AskUserQuestion を発行せず、破壊的操作の承認は起動時に一括付与済みとして扱う |
| verification_mode | 任意（既定 `single-pass`） | `docs-only` は facts 抽出・基本設計・詳細設計まで、`single-pass` は動的検証を1回実行、`iterative` は FAIL 後の改善反復も行う |
| facts_profile | 任意（既定 `auto`） | `auto|screen|python`。`auto|screen`は通常の画面フローを`profile=screen`で実行する。`python`は明示指定時だけ、画面一覧・画面状態判定へ入る前のfacts-only経路を実行して終端する |
| target_file_paths | `facts_profile=python`時必須 | Python facts-only経路で抽出する、`target_repo_path`からの相対`.py`パス配列。全件`.py`でなければ中断する |
| facts_unit_id | `facts_profile=python`時必須 | Python facts-only出力を識別する論理ID。画面IDではなく、`<verification_dir>/screen-<facts_unit_id>/facts/<run_id>/`の識別子としてだけ使う |

無人モード（headless=true）の詳細仕様（置き換え表・盲検分離の必須要件・安全設計・実行レポートの置き場・前提事実）は `references/contract.md` の「無人モード仕様」節を正本とする。無人モード（headless=true）では工程の開始・完了のたびに `<verification_dir>/progress.jsonl` へ JSON 行を追記する（形式: `{"ts":"<ISO8601>","screen_id":"<画面ID>","phase":"<工程名>","status":"started|completed|failed"}`）。呼び出し元セッションや人間はこのファイルの監視で現在工程を把握できる。

## 基本ワークフロー

成果物の実在から現在の状態を判定し、次に起動する子スキルを機械的に決定する。状態一覧（16状態）は下表のとおり。詳細な実在判定基準・args・返却フィールドの定義は `references/contract.md` の状態判定表を参照。

| 状態キー | 判定の要点 | 次に起動する子スキル |
|---|---|---|
| アーキ未調査 | アーキテクチャ調査書が不在、または機械ゲート再実行が失敗 | surveying-architecture-for-reverse-docs |
| 一覧未生成 | unit_kinds_present のいずれかの種別について一覧HTMLが不在、または excluded-kinds.json が不在 | generating-<種別>-list-for-reverse-docs（不在種別に対応する種別別一覧スキル） |
| 共通未採録 | プロジェクト共通10文書のいずれか不在、または機械ゲート再実行が失敗 | generating-reverse-common-docs（NG帰着(c)差し戻し時は mode=append） |
| ポータル未生成 | `<output_dir>/index.html` が不在 | bash shared/scripts/build-portal.sh（Phase 4A） |
| サイト定義未生成 | サイトが2件以上あり `<納品ルート>/sites.json` が不在 | `sites.json` を書き出す（統括スキル自身が実行。子スキル起動なし） |
| 基盤ページ未生成（任意） | 用語辞書.html・技術スタック.html・画面遷移図.html・ER図.html・環境構築手順.html のいずれかが output_dir 直下に不在。任意工程のためデータ源未整備時はスキップしてよい（Phase 4B） | generating-tech-stack-for-reverse-docs / generating-env-guide-for-reverse-docs / generating-screen-transition-for-reverse-docs / generating-er-diagram-for-reverse-docs / generating-glossary-for-reverse-docs（不在ページに対応するスキルのみ） |
| 状態遷移図未生成（任意） | 状態遷移図.html が output_dir 直下に不在。任意工程のためデータ源未整備時はスキップしてよい | generating-entity-state-for-reverse-docs |
| シーケンス図未生成（任意） | 画面フォルダのシーケンス図.html が不在。任意工程のためデータ源未整備時はスキップしてよい | generating-sequence-diagram-for-reverse-docs |
| 事実未封印 | facts.lock が不在、または封印検証が失敗 | extracting-unit-facts-from-code |
| 基本設計未著述 | 画面基本設計書（`<screen_dir>/基本設計/画面基本設計書.md`）が不在 | generating-reverse-basic-design |
| 設計書未著述 | 画面ディレクトリ不在 or §15.1に対象ファイル行なし or 著者スキルの完全性ゲート成果物不在 or facts更新後の再著述未実施 | generating-reverse-detailed-design |
| 画面未開通 | 静的リバース成果物は著述済みだが、動的検証に必要な実レンダリング確認済みURLがない | unlocking-reverse-target-screens（`verification_mode=docs-only` では起動せず「静的リバース完了」で終端） |
| ファイル単位未検証 | 著述済み（設計書未著述の成果物実在）かつ当該ファイルの検証記録に再現一致なし（任意工程） | rebuilding-screen-unit-from-docs |
| 基準未確立 | 設計書有・baseline_tag 未確立 | syncing-reverse-env（mode=setup → sync） |
| 往復未検証 | baseline_tag有・reverse未実装 or 未突合 | rebuilding-code-from-docs（implement）→ syncing-reverse-env（sync,dry-run）→ rebuilding-code-from-docs（judge） |
| 検証完了 | judge の status=PASS | syncing-reverse-env（mode=sync 本番 / 依頼時 teardown） |

複数サイトの場合、上表の `<output_dir>` は「当該サイトのサイトルート」と読み替える。

画面開通は facts 抽出・基本設計・詳細設計の前提条件ではない。原本コードと封印済み facts から静的リバースを先に完了し、画面開通はファイル単位検証・基準確立・往復検証へ進む直前にだけ要求する。開通できない場合も静的成果物は破棄せず「静的リバース完了・動的検証保留」として報告する。

ファイル単位未検証が `status=差し戻し` を返した場合、`verification_mode=iterative` のときだけ設計書未著述へ戻す。`single-pass` では差し戻し理由を記録して停止し、`docs-only` ではファイル単位検証自体を起動しない。アーキ未調査・共通未採録はプロジェクト単位で1回だけ確定させればよく、画面ごとに繰り返さない。

## 実行手順

### 事前ヒアリング（初回起動時のみ）

headless=trueではAskUserQuestionを使わず、選択したprofileの必須引数が不足していれば推測せず中断する。対話実行では、`facts_profile=auto|screen`かつtarget_repo_path・output_dir・screen_scopeが指定済みの場合、または`facts_profile=python`かつtarget_repo_path・output_dir・target_file_paths・facts_unit_id・verification_dirが指定済みの場合だけ本Phaseをスキップする。Python経路ではscreen_scopeを要求せず、事前ヒアリング完了後の遷移先をPhase 0Pとする。通常の画面フローだけがPhase 1へ直行する。

#### Step 0-1: 実行パラメータをヒアリングする

AskUserQuestionツールでprofileに応じた必須項目を確定する。起動引数が空の対話実行では、最初に`facts_profile=auto|screen|python`を選ばせてから同じ規則を適用する。

`facts_profile=auto|screen`では以下の4項目を確定する:

| 項目 | 選択肢 | 既定値 |
|---|---|---|
| 対象プロジェクトパス | 自由記述（リポジトリルートのパス） | なし（必須） |
| 出力先パス | 自由記述（設計書の書き出し先ディレクトリ） | `<対象プロジェクト>/docs/リバース検証/` |
| 画面範囲 | 全画面 / 指定画面リスト / N画面制限 / 複雑度層別サンプル | 全画面 |
| 個別スキル利用 | フル実行 / 自由記述（特定スキル名） | フル実行 |

「複雑度層別サンプル」選択時は、`<output_dir>/一覧/画面一覧/複雑度プロファイル.json`（generating-screen-list-for-reverse-docs の任意Phase 5が生成）から複雑度層（G1〜G6。6層未満の実測件数ではALLに縮退）ごとに代表画面を抽出する。プロファイル未生成時は先に一覧生成スキルの `--profile` サブコマンドを起動してから抽出する。

screen_ids への変換規則: 複雑度プロファイル.json の `layers[*].sampledScreenKeys`（層ごとの代表画面キー配列。ALL縮退時は `layers.ALL.sampledScreenKeys`）の和集合を screen_ids とする。

`facts_profile=python`では画面範囲を尋ねず、対象プロジェクトパス・出力先パス・実行モードに加えて以下の3項目を確定する:

| 項目 | 入力契約 | 既定値 |
|---|---|---|
| target_file_paths | `target_repo_path`からの相対`.py`パスの非空配列。全件の実在とリポジトリ内包を確認し、外部絶対パス・`..`・symlink脱出を拒否する | なし（必須） |
| facts_unit_id | facts出力を識別する論理ID。画面IDや実在画面ディレクトリを要求しない | なし（必須） |
| verification_dir | facts・再計数・封印記録の出力先 | `<output_dirの親>/verification/` |

**完了**: `auto|screen`は対象プロジェクトパス・出力先パス・画面範囲・実行モードの4項目が確定済み。`python`はtarget_repo_path・output_dir・target_file_paths・facts_unit_id・verification_dir・実行モードが確定し、screen_scopeを要求していない。

#### Step 0-2: 実行モードを確定する

Step 0-1 の回答に基づき実行モードを決定する:

- **フル実行（facts_profile=python）**: 確定したtarget_repo_path・output_dir・target_file_paths・facts_unit_id・verification_dirを使ってPhase 0Pへ進む。Phase 1へは進まない
- **フル実行（facts_profile=auto|screen）**: 確定したtarget_repo_path・output_dir・screen_scopeを使ってPhase 1以降を順に進行する
- **個別スキル利用**: 指定されたスキルを args 全量指定で単独起動し、完了をもって本フロー全体を終了する

**完了**: 実行モード（フル実行 / 個別スキル名）が確定し、フル実行は`python`ならPhase 0P、`auto|screen`ならPhase 1、個別利用なら単独起動へ進む準備ができている。

#### サイトを確定する（アーキテクチャ調査書 §10 が確定済みのとき）

アーキテクチャ調査書 §10 のサイト一覧を提示し、どのサイトを対象にするかを確定する。単独プロジェクトならサイトは 1 件（キー `main`）で、確認は不要。モノレポで 2 件以上ある場合は、全サイトを対象にするか一部だけかをユーザーに確認する。§10 がまだ確定していない（初回起動でアーキ調査が未実施）場合は、Phase 2（アーキ調査）完了直後にあらためて本 Step を実行してから Phase 3 以降へ進む。

**完了**: 対象サイト一覧（キー・ルートディレクトリ）が確定している。

### サイトごとのループ（モノレポ・複数サイト時）

前段の「サイトを確定する」段階で複数サイトを対象に確定した場合、Phase 2（アーキ調査）〜Phase 4A（ポータル生成）を確定した対象サイトごとに繰り返す。各サイトのループでは `output_dir` を `<納品ルート>/<サイトのルートディレクトリ>` に差し替えて実行する。サイト間は独立しており、あるサイトの失敗が他サイトの成果物を壊すことはない。いずれかのサイトで中断した場合はそのまま停止し、以降のサイトへは進まない。次回起動時は状態判定がサイトごとに行われるため、未完了のサイトから自動的に再開される。サイトをまたぐ巻き戻しは行わない。

### Phase 0P: 明示Python facts-only経路

`facts_profile=python`が明示された場合だけ、事前ヒアリング完了後かつPhase 1の画面ID実在確認より前にこの経路へ分岐する。`target_repo_path`・`target_file_paths`・`facts_unit_id`・`verification_dir`を検証し、`target_file_paths`が非空かつ全件`.py`であることを確認する。論理パス`screen_dir=<verification_dir>/logical/<facts_unit_id>`を組み立てるが、そのディレクトリの実在やスキャフォールディングは要求しない。

facts抽出より先に`survey_doc_path`を解決する。起動引数のsurvey_doc_pathが実在しアーキテクチャ調査ゲートを通る場合はそれを使う。未指定なら`<output_dir>/プロジェクト共通/アーキテクチャ調査書.md`を候補とし、候補が不在ならSkillでsurveying-architecture-for-reverse-docsをtarget_repo_path・output_dir・template_root・mode=surveyで起動する。候補が実在しても調査ゲートが不合格ならmode=revise・revise_findings付きで起動する。返却`status=調査確定`のartifacts[0]をsurvey_doc_pathとして記録し、実在と調査ゲート通過を再検収する。この前処理は画面一覧・対象画面ID・画面状態を参照しない。

survey_doc_path確定後に限り、Skillで⑥extracting-unit-facts-from-codeをtarget_repo_path・target_file_paths・上記screen_dir・verification_dir・profile=python・survey_doc_path・run_idで起動する。返却`status=封印済み`、`recount-report.txt`のexit 0相当結果、`facts.lock`の`seal-facts.sh verify`通過を検収し、「Python facts封印完了」で本フローを終端する。画面一覧生成・対象画面ID実在確認・画面スキャフォールディング・基本設計/詳細設計著述には進まない。

`facts_profile=auto|screen`はこのPhaseを通らず通常の画面フローへ進む。通常の画面フローでは対象ファイルの拡張子にかかわらず`profile=screen`を渡し、拡張子だけを根拠にpythonへ切り替えてはならない。

完了条件: 明示python時はsurvey_doc_pathの既存解決または生成・検証後にfacts抽出・独立再計数・封印検証が完了してfacts-only終端、auto|screen時は副作用なくPhase 1へ進行

### Phase 1B: 並列一覧生成（Phase 1 でアーキ未調査が解消された後）

Phase 1 の状態判定で「一覧未生成」に到達した場合、従来の逐次起動に代わり Agent ツールで一覧生成スキルを並列起動する。ただし起動対象は Phase 2 で確定した unit_kinds_present に含まれる種別のみに限定する。

#### Step 1B-1: unit_kinds_present に含まれる種別のみ一覧スキルを並列起動する

Phase 2 で確定した unit_kinds_present を参照し、実在種別に対応する一覧生成スキルのみを Agent ツールで同時に起動する（run_in_background: true で並列実行）。対応する一覧生成スキルは以下の 6 種類だが、unit_kinds_present に含まれない種別は起動せず、Step 1B-2 の excluded-kinds.json への対象外記録のみを行う:

headless=true 時は Agent(run_in_background: true) を使用せず、unit_kinds_present の種別を 1 つずつ Skill ツールで逐次起動する（`CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS` 既定 600 秒でバックグラウンドプロセスが切断される実測バグを回避するため）。

1. generating-screen-list-for-reverse-docs
2. generating-api-list-for-reverse-docs
3. generating-table-list-for-reverse-docs
4. generating-batch-list-for-reverse-docs
5. generating-report-list-for-reverse-docs
6. generating-external-list-for-reverse-docs

各エージェントには source_dir・output_dir を args として渡す（Phase 3・`references/contract.md` の args 仕様と統一。unit_kind はスキル名で固定されるため引数に含まない）。

**完了**: unit_kinds_present に含まれる種別のスキルすべてが完了し、各種別の一覧HTMLが生成されている。失敗したスキルがある場合はエラー内容を報告し、残りの正常完了分で続行するか判断する。

#### Step 1B-2: excluded-kinds.json を確認する

対象外種別の判定は Phase 2 で確定済みのアーキテクチャ調査書の判定（`unit_kinds_present` に含まれない種別）をそのまま転記する。6 一覧の生成結果（一覧が空かどうか）を対象外判定の根拠として二重に評価しない（正本は `references/contract.md` の excluded-kinds.json 形式）。

**完了**: excluded-kinds.json が最新状態に更新されている。

### Phase 1C: 機能一覧生成（Phase 1B 完了後・派生一覧）

Phase 1B（または Phase 3）で画面一覧HTMLが確立した後に、機能一覧を生成する。機能は既存一覧の派生グルーピング（派生一覧）であり、unit_kinds_present の存在判定対象外のため、種別の実在判定は行わない。英字接尾辞化に伴い、旧来の十進小数採番にあった予約欠番は設けず、Phase 1B の次を Phase 1C とする。

#### Step 1C-1: 機能一覧スキルを起動する

`<output_dir>/一覧/画面一覧/画面一覧.html` が存在する場合のみ、Skill ツールで generating-feature-list-for-reverse-docs を source_dir・output_dir（・任意で survey_doc_path）で起動する。画面一覧が存在しない場合は本 Phase をスキップする（画面一覧の確立後に再実行する）。

返却 status=DONE なら `一覧/機能一覧/機能一覧.html` の実在を確認して次工程へ進む。status=ERROR なら hint を確認しユーザーに報告する。

**完了**: 機能一覧.html が存在する（画面一覧不在によるスキップ時はスキップ理由が記録されている）。

#### 再実行判定

画面一覧HTMLが存在するのに `一覧/機能一覧/機能一覧.html` が不在の場合、状態判定の16状態には追加せず、本 Phase を再実行して補完する（派生一覧は16状態の判定フローの対象外）。

### Phase 1D: マトリクス・対応表生成（Phase 1C 完了後・派生補完）

Phase 1C（機能一覧生成・派生一覧）が完了した後に、マトリクス・対応表生成スキル（generating-cross-views-for-reverse-docs）を起動してマトリクス・対応表4ページ（権限画面マトリクス・権限機能マトリクス・CRUD図・追跡可能性）とAI設定資産ページを生成する。マトリクス・対応表は既存一覧（画面・API・テーブル・機能）の派生補完であり、機能一覧と同様に unit_kinds_present の存在判定対象外のため、種別の実在判定は行わない。

#### Step 1D-1: マトリクス・対応表生成スキルを起動する

`<output_dir>/一覧/画面一覧/画面一覧.html` と `<output_dir>/一覧/API一覧/API一覧.html` の両方が存在する場合のみ、Skill ツールで generating-cross-views-for-reverse-docs を target_repo_path・output_dir（・任意で portal_output_dir）で起動する。いずれか不在の場合は本 Phase をスキップする（両一覧の確立後に再実行する）。

返却 status=DONE なら生成済みページ（generated_pages）を確認して次工程へ進む。status=STOPPED/ERROR なら hint を確認しユーザーに報告する。permission-function（権限機能マトリクス）はデータ形状ギャップにより未生成のまま skipped_pages に記録される場合があるが、これは既知の制約でありエラー扱いしない（詳細は generating-cross-views-for-reverse-docs/SKILL.md の「予想を裏切る挙動」参照）。

**完了**: 生成可能なマトリクス・対応表ページ・AI設定資産ページが存在する（画面一覧/API一覧不在によるスキップ時はスキップ理由が記録されている）。

#### 再実行判定

画面一覧HTML・API一覧HTMLが両方存在するのにマトリクス・対応表・AI設定資産ページが1つも存在しない場合、本 Phase を再実行して補完する。この再実行は状態判定の16状態には追加しない（派生補完は16状態の判定フローの対象外）。

### Phase 4A: ポータル生成（共通採録完了後）

Phase 4（共通採録）完了後に、リバース設計ポータルを生成する。コード行数・ファイル数の計測、各種別一覧からの件数抽出、共通文書リストの収集を行い、テンプレートからポータル HTML を出力する。

#### Step 4A-1: 環境調査（env-config.json 未存在時のみ）

`<output_dir>/env-config.json` が存在しない場合のみ、Skill ツールで surveying-local-environment を起動する。引数: `output_dir=$output_dir`。

#### Step 4A-2: コード行数計測

Skill ツールで counting-code-lines を起動する。引数: `target_dir=$target_repo_path`、`output_dir=$output_dir`、`env_config=$output_dir/env-config.json`。出力される `code-metrics.json` には、コード行数（total/fe/be/file_count/fe_files/be_files/method/measured_at）に加え、計測時コミット（`commit`。git 管理外は `null`）、テスト計測（`tests`。件数・FE/BE 内訳・ファイル数）、前回計測値（`previous`。total・tests.count・measured_at の転記。初回計測時は `null`）が含まれる。

#### Step 4A-3: ポータル HTML 生成

Bash で以下を実行する:

```bash
bash shared/scripts/build-portal.sh \
  "$target_repo_path" \
  "$output_dir" \
  "$output_dir" \
  --catalog shared/references/portal-catalog.json
```

ポータルは納品物ルート（output_dir）直下の `index.html` として出力する（正本レイアウト。`references/contract.md` の「納品物ルート（output_dir）の正本レイアウト」参照）。
カテゴリ、カード、探索条件、件数単位は`shared/references/portal-catalog.json`から導出する。カテゴリや成果物種別を追加する場合は、`build-portal.sh`へ分岐を足さずcatalogへblueprintを登録する。画面manifestから派生物を一括再生成する工程では、同じcatalogに加えて`--portal-only`、`--generated-at`、`--screen-manifest`を渡し、既存成果物を再変換せず`index.html`だけを更新する。

**完了**: `<output_dir>/index.html` が存在する。

### Phase 4B: 基盤情報ページ生成（任意）

ポータル生成完了後、任意工程として基盤情報ページ5枚（用語辞書・技術スタック・画面遷移図・ER図・環境構築手順）を生成する。データ源（画面一覧・テーブル一覧・調査書等）が未整備のページはスキップしてよい。

#### Step 4B-1: 基盤ページ生成スキルを任意で起動する

必要なページに対応するスキルを Skill ツールで起動する。各スキルは `target_repo_path`・`output_dir`・`portal_output_dir`（任意）を受け取り、`<output_dir>` 直下に固定ファイル名の HTML を書き出す。出力パス契約は `references/contract.md` の「基盤ページ5枚の出力パス契約」を参照する。

- generating-tech-stack-for-reverse-docs（アーキテクチャ調査書 §2 が確定済みのとき）
- generating-env-guide-for-reverse-docs（アーキテクチャ調査書 §3 が確定済みのとき）
- generating-screen-transition-for-reverse-docs（画面一覧.html が確定済みのとき）
- generating-er-diagram-for-reverse-docs（テーブル一覧.html が確定済みのとき）
- generating-glossary-for-reverse-docs（プロジェクト共通文書とアーキテクチャ調査書が確定済みのとき。二段承認を伴う）

#### Step 4B-2: ポータルを再実行する

生成したページをカードへ反映するため、Step「ポータル HTML 生成」と同一のコマンドで build-portal.sh を再実行する。

**完了**: 生成対象に選んだページについて `<output_dir>` 直下に HTML が存在し、ポータルのカードへ反映されている。データ源未整備でスキップしたページはスキップ理由を記録する。

### Phase 4C: 画面バッチ実行（共通採録完了後・画面数4件以上）

Phase 4（共通採録）完了後、対象画面が4件以上の場合に running-reverse-screen-batch スキルを起動する。`docs-only` はバッチ前半の facts→著述モード判定→標準著述または大規模2パスだけを実行して静的完了し、`single-pass|iterative` は動的検証まで進む。3件以下は Phase 6 で逐次処理する。headless=true で3件以下の場合、`docs-only` は動的検証・盲検分離・内部 Agent 委任を要しない静的逐次経路として完遂できるが、`single-pass|iterative` は通常セッションで実行する。

#### Step 4C-1: 画面バッチスキルを起動する

Skill ツールで running-reverse-screen-batch を以下の引数で起動する:

- target_repo_path: 事前ヒアリングで確定した値
- output_dir: 同上
- screen_ids: 事前ヒアリングの screen_scope に基づく（"all" または指定リスト）
- template_root: shared/templates/リバース検証/画面/
- common_docs_root: Phase 4 で確定した common_docs_root
- survey_doc_path: Phase 2 で確定した survey_doc_path
- verification_mode: 起動引数の値（`docs-only` / `single-pass` / `iterative`）

**完了**: running-reverse-screen-batch が完了報告を返し、全画面の検証状態（成功/failed）が確定している。

### Phase 1: 状態判定

preflight では上表の16状態を確認する。事実封印後、状態10より前に著述モードを確定する。large-two-passでは状態11のdetail-onlyを先に評価し、有効なパス1証跡を得てから状態10とcompanion-docsを評価する。

1. アーキ未調査
2. 一覧未生成
3. 共通未採録
4. ポータル未生成
5. サイト定義未生成
6. 基盤ページ未生成（任意）
7. 状態遷移図未生成（任意）
8. シーケンス図未生成（任意）
9. 事実未封印
10. 基本設計未著述（large-two-passはパス1証跡取得後）
11. 設計書未著述（large-two-passはdetail-onlyを先行し、その後companion-docs）
12. 画面未開通
13. ファイル単位未検証
14. 基準未確立
15. 往復未検証
16. 検証完了

任意状態は、データ源不足によるスキップ理由が記録済みなら次の状態へ進む。11の確認で facts・基本設計・詳細設計がすべて完成した直後の場合を扱う。`verification_mode=docs-only` なら画面レジストリの `verification_url` の有無を見ずに「静的リバース完了」で終端する。この場合は12〜16を実行対象として判定せず、Phase 5・Phase 6の動的部分・Phase 7〜11のタスクも作成しない。`single-pass|iterative` の場合だけ12以降を確認する。

状態判定の冒頭で対象画面IDの実在を検証する。実在確認は画面一覧のマニフェスト（`<docs>/一覧/画面一覧/画面一覧.html` 内の embedded JSON の `screens[]` 配列）に対して行う。一覧外IDの場合は AskUserQuestion で対応を確認する。選択肢は (a) 一覧へ kind=`unrouted` として追記してから工程を継続するか、(b) エラー終端するかの2択（headless=true 時は (a) を自動選択する）。画面レジストリの `verification_url` が未実施・エラーページ・プレースホルダの場合でも、facts 抽出・基本設計・詳細設計は続行する。実レンダリング確認済みURLは動的検証へ移る時点でのみ必須とする。状態判定完了後、残り全工程を Step 単位で一括 TaskCreate する（マニフェスト先出し方式）。対象画面数×工程で展開する（フォーマットは後述「タスク一覧フォーマット」節を参照）。各工程の実行開始時に該当タスクを TaskUpdate(in_progress) に更新し、完了時に TaskUpdate(completed) に更新する。

完了条件: 状態キー（16状態のいずれか）、または `docs-only` の静的リバース完了が確定し、実行対象に限った残り全工程のタスク一覧が TaskCreate で一括登録済み

### Phase 2: ①アーキ調査（アーキ未調査時）

Bash で `<verification_dir>/progress.jsonl` に phase="Phase 2" status="started" の行を追記する。状態がアーキ未調査の場合のみ実行する。Skill で surveying-architecture-for-reverse-docs を target_repo_path・output_dir・template_root・mode（既存調査書が無ければ survey、下流から検出手がかり欠落を指摘されて差し戻された場合は revise・revise_findings）で起動する。返却 status=調査確定 なら survey_doc_path（artifacts[0]と同値）を記録して次工程へ進む。status=中断 なら hint を確認しユーザーに報告して中断する。

完了条件: survey_doc_path が確定している。progress.jsonl に Phase 2 の completed 行が追記済み

### Phase 3: ②一覧生成（一覧未生成時）

Bash で `<verification_dir>/progress.jsonl` に phase="Phase 3" status="started" の行を追記する。状態が一覧未生成の場合に実行する。

1. アーキテクチャ調査の返却から `unit_kinds_present` を取得する
2. 6種別（screen/api/table/batch/report/external）のうち `unit_kinds_present` に含まれない種別について、`excluded-kinds.json` を `<output_dir>/一覧/` に書き出す（アーキテクチャ調査書から判定理由を転記）とともに、`<output_dir>/一覧/<種別ラベル>一覧（該当なし）.md`（判定理由を転記した1枚もの）を生成する
3. `unit_kinds_present` に含まれる各種別について、`一覧/<種別ラベル>一覧/<種別ラベル>一覧.html` の実在を確認する
4. 不在の種別ごとに、対応する種別別一覧スキル generating-<種別>-list-for-reverse-docs（例: screen なら generating-screen-list-for-reverse-docs）を Skill で `source_dir`・`output_dir` 指定で起動する（種別はスキル名に固定されるため unit_kind 引数は渡さない）。画面については永続正本を`screen_manifest_path=<output_dir>/一覧/画面一覧/screen-manifest.json`、`screen_manifest_ext_path=<output_dir>/一覧/画面一覧/screen-manifest.ext.json`に固定し、検出直後の生マニフェストとメタデータ付与後マニフェストをそれぞれ原子的に保存する
5. 返却 status=DONE なら次の種別へ進む。status=ERROR なら hint を確認しユーザーに報告する
6. 画面一覧HTMLが既に存在する再開実行では、上記の永続screen_manifest_pathが無ければ`bash shared/scripts/unit-list/restore-screen-manifest.sh <output_dir>/一覧/画面一覧/画面一覧.html <screen_manifest_path>`を必ず実行して埋込`#screen-manifest`から復元する。続いてextract-screen-metadata.shでscreen_manifest_ext_pathを再生成する。復元・validate-manifest.sh・メタデータ付与のいずれかが失敗した場合は静的著述へ進まない
7. 全種別の一覧が揃ったら（生成済みまたは対象外）、Phase 1C（機能一覧生成・派生一覧）を実行し、続けて Phase 1D（マトリクス・対応表生成・派生補完）を実行してから Phase 4 へ進む

一覧生成は全種別について成果物を出す。`unit_kinds_present` に含まれる種別（present）は一覧HTMLを、含まれない種別は `<種別>一覧（該当なし）.md` を必ず生成する（成果物の実在有無だけで「対象外」の判定を後から復元できるようにするため）。

完了条件: unit_kinds_present の全種別について一覧HTMLが存在し、画面一覧が存在する場合は永続screen_manifest_path/ext_pathが実在して両方とも検証済み、含まれない種別について `<種別>一覧（該当なし）.md` が存在し、excluded-kinds.json が存在する。progress.jsonl に Phase 3 の completed 行が追記済み

### Phase 4: ③共通採録（共通未採録時）

Bash で `<verification_dir>/progress.jsonl` に phase="Phase 4" status="started" の行を追記する。状態が共通未採録の場合のみ実行する。Skill で generating-reverse-common-docs を target_repo_path・output_dir・template_root・survey_doc_path（Phase 2 で確定済み）・mode=v0 で起動する。返却 status=採録v0確定 なら common_docs_root を記録して次工程へ進む。status=中断 なら hint を確認しユーザーに報告して中断する。NG帰着(c)共通文書欠落からの差し戻しでは mode=append・append_findings（修正指示書.md からの抜粋）で再起動し、status=追記完了 を確認する（詳細は `references/contract.md` の「NG帰着3系統の配線」）。

完了条件: common_docs_root が確定している。progress.jsonl に Phase 4 の completed 行が追記済み

### Phase 5: ④setup（動的検証用の環境ブロック取得）

`verification_mode=docs-only` では本 Phase をスキップする。`single-pass` / `iterative` では、静的リバース（facts・基本設計・詳細設計）が完了し、画面開通も確認できた後に実行する。Phase 番号より依存順を優先し、未開通時に Phase 6 の静的リバースを妨げてはならない。

Bash で `<verification_dir>/progress.jsonl` に phase="Phase 5" status="started" の行を追記する。Skill で syncing-reverse-env を design-doc・mode=setup で起動する。返却ブロックから env_block（output_dir / scope / ports / slot / baseline_tag / original_code / reverse_code）を抽出し、以降の動的検証 Phase へ引き継ぐ。status が PASS 以外（FAIL / ERROR / INCOMPLETE）の場合は静的成果物を保持し、「静的リバース完了・動的検証保留」として hint を報告する。`iterative` で明示的な再試行条件を満たす場合だけ再実行する。

完了条件: env_block の7フィールドが確定している。progress.jsonl に Phase 5 の completed 行が追記済み

### 種別ループ（Phase 6 以降の適用範囲）

excluded-kinds.json の presentKinds に記載された各種別についてループする。screen のみ Phase 6 以降のユニット反復（画面未開通〜ファイル単位未検証）〜基準確立〜往復検証に進む。screen 以外（api / table / batch / report / external）は facts抽出以降の工程が現時点で未対応のため、一覧確立をもって「後続未対応」の終端状態として記録し、Phase 6 以降を実行しない。最終報告には全6種別の到達状態（生成済み / 対象外 / 後続未対応 の3値）を必ず含める（正本は `references/contract.md` の「種別ループ」）。

### Phase 6: ユニット処理（事実未封印/基本設計未著述/設計書未著述/画面未開通/ファイル単位未検証・任意工程含む）

Bash で `<verification_dir>/progress.jsonl` に phase="Phase 6" status="started" の行を追記する。状態が事実未封印・基本設計未著述・設計書未著述・画面未開通・ファイル単位未検証のいずれかの場合に実行する。無人モード（headless=true）では、原本コードを読む本 Phase（(b)(c)）と、設計書のみで判定する Phase 8-10 を別プロセス（別のヘッドレス呼び出し）に分離する（詳細は `references/contract.md` の「無人モード仕様」）。

**(b) 事実未封印の場合**: 画面の開通有無と`screen_dir`の実在にかかわらず、先にfactsを抽出する。通常の画面ループは`facts_profile=auto|screen`のどちらでも常に`profile=screen`を渡す。対象ファイルが全件`.py`でもpythonへ自動変更しない。Skillで⑥extracting-unit-facts-from-codeをtarget_repo_path・target_file_paths・screen_dir・verification_dir・profile=screen・survey_doc_path・run_idで起動する。返却status=封印済みを受けたらfacts_refを記録して(b-2)へ進む。status=中断の場合はhintを確認し報告する。`facts_profile=python`はPhase 0Pで終端済みのため本画面ループへ到達しない。

**(b-2)(c) 著述モード判定と著述**: `profile=screen`の事実封印完了（facts_ref確定）後に限り、管理者がスキャフォールディングを1回だけ実施する（`bash <scaffold_script_path> <output_dir> <画面ID> [<画面名>]`を画面ディレクトリ未存在時のみ実行。既存の場合は`--verify`のみで健全性確認する）。scaffoldをfacts抽出より前へ移動してはならない。その後、`target_file_paths`の合計行数とファイル数を実測し、合計1,500行超または4ファイル超なら`authoring_mode=large-two-pass`、それ以外は`authoring_mode=standard`とする。

`authoring_mode=standard` では、Agent ツールで次の2スキルを同時に起動する（run_in_background: true、Phase 1B の並列パターンに準拠）。

- generating-reverse-basic-design（args: screen_dir・output_dir・template_root・scaffold_script_path・facts_ref・common_docs_root・unit_kind・authoring_pass=standard）→ 期待 status=基本設計著述完了
- generating-reverse-detailed-design（args: screen_dir・output_dir・template_root・chapter_map_path・audit_script_path・scaffold_script_path・facts_ref・common_docs_root・mode・target_file_path・verification_url・authoring_pass=full）→ 期待 status=AUTHORED

`authoring_mode=large-two-pass` では、次の2パスを必ず直列に実行する。

1. **パス1（詳細設計）**: generating-reverse-detailed-design を `authoring_pass=detail-only` で起動し、画面詳細設計書の著述と完全性ゲートを完了させる。期待 status は `DETAIL_AUTHORED`
2. **パス2（周辺文書）**: パス1の `DETAIL_AUTHORED`、`detail_design_path`、`pass1_receipt_path` を検収した後、generating-reverse-basic-design（`authoring_pass=large-pass2`）と generating-reverse-detailed-design（`authoring_pass=companion-docs`）へ3値を渡して別委任する。前者は基本設計書、後者は観点表・テスト仕様書を著述する。期待statusは `基本設計著述完了` と `COMPANION_AUTHORED`

大規模ユニットでは「基本設計未著述」の状態をパス1完了まで保留し、「設計書未著述」を先に解消する。パス1未完了のまま基本設計・観点表・テスト仕様書を著述してはならない。headless=true 時もパス境界は維持し、パス2内だけ基本設計→周辺文書の順で逐次起動する（Agent の並列起動が600秒で切断されるため）。

前提条件: facts_ref 確定済み（(b) で取得）・common_docs_root 確定済み（Phase 4 で取得）・画面ディレクトリのスキャフォールディング完了済み（管理者が並列起動前に実施）
合流条件: standard は基本設計著述完了と AUTHORED、large-two-pass は DETAIL_AUTHORED・基本設計著述完了・COMPANION_AUTHOREDをすべて受領した後に、下記「静的完了ゲート」を評価する
片方失敗時: 失敗側のみ再起動する（成功側の待機は不要）。基本設計著述失敗 / BLOCKED の場合は hint を確認しユーザーに報告する

**静的完了ゲート**: facts・基本設計・詳細設計が完成したら、管理者が両著述スキルの完了statusを検収する。続いて、永続`screen_manifest_path=<output_dir>/一覧/画面一覧/screen-manifest.json`を解決する。不在なら`restore-screen-manifest.sh`で既存画面一覧HTMLの埋込manifestから復元し、validate-manifest.sh通過を確認する。そこから`extract-screen-metadata.sh <screen_manifest_path> <source_dir> <screen_manifest_ext_path> --design-docs-dir <output_dir>/画面 --link-base-dir <output_dir>/一覧/画面一覧`を再実行し、`build-unit-list.sh <screen_manifest_ext_path> <output_dir>/一覧/画面一覧/画面一覧.html --unit-kind screen --portal-dir <output_dir>`で画面一覧を必ず再生成する。復元・検証・再生成のいずれかが失敗した場合は静的完了を宣言しない。再生成後、当該画面の実在成果物だけに4リンクが付与され、確定画面名がある場合は`confirmedScreenName`が表示源へ反映され、マニフェスト登録件数と表行数が一致することを検収する。この後でのみ画面レジストリの当該エントリを作成または更新して`status=authored`とする。その後にURLの有無にかかわらず`verification_mode`を評価する。`docs-only`は「静的リバース完了」として直ちに終端し、(a)・Phase 5・(d)・Phase 7〜11をすべてスキップする。`single-pass|iterative`だけ(a)へ進む。

**(a) 静的著述後に画面未開通の場合**: 実レンダリング確認済みURLが無い場合、Skill で ⑤unlocking-reverse-target-screens を `invocation_mode=dynamic-only`・system・screen_id・reverse_worktree・ports・output_dir・user-approved で起動する。返却 `status=UNLOCKED` かつ設計書 frontmatter の実測項目補完済みを確認する。既に実レンダリング確認済みURLがあり frontmatter の実測項目も確定済みなら本工程をスキップする。`dynamic-only` は基準確立を行わない。status=BLOCKED / ERROR の場合は静的成果物を保持し「静的リバース完了・動的検証保留」として報告する。開通済みまたは本工程完了後に Phase 5 の setup を実行し、env_block 確定後に (d) へ戻る。

**(c-2) gold標準によるスキーマ検証（gold標準が存在する場合のみ）**: 著述完了後・ファイル単位検証の前に、正解セットからの逆算検査を1回実行する。`bash shared/scripts/backtest-facts-against-gold.sh --code-root <target_repo_path> <facts_ref>/facts.yml shared/references/gold-standard/docs/` で抽出スキーマの不足を検出し、`bash shared/scripts/check-doc-coverage-against-gold.sh <設計書パス> shared/references/gold-standard/docs/ --threshold 95` で生成設計書のカバレッジを判定する。両方 exit 0 なら (d) へ進む。exit 1 の場合、`single-pass` は不足と改善候補を報告して停止し、`iterative` の場合だけ facts 抽出または詳細設計へ差し戻す。`shared/references/gold-standard/` が不在の場合はスキップする。

**(d) ファイル単位未検証の場合**: `verification_mode=docs-only` ではスキップする。`single-pass` / `iterative` では、著述済みの対象ファイルについて Skill で ⑧rebuilding-screen-unit-from-docs を screen_dir・target_file_path・output_dir/template_root/audit_script_path/scaffold_script_path/chapter_map_path（資産paths）・env_block・user-approved・verification_mode で起動する。白紙化を伴うため、起動前にユーザーから承認を取得し user-approved として args に含める（管理者が事前確認し、子スキルはユーザーに直接聞かない）。`single-pass` は対象ファイルごとに P2〜P5 を1回だけ実行し、P6 の修正を行わず status=差し戻し / 再現不一致なら instruction_doc と改善候補を報告して停止する。`iterative` の場合だけ、子スキル内部の P6 修正・再投入と、status=差し戻しを (c) 詳細設計へ戻す外側反復を許可する。target_repo_path 等の必須引数欠落による起動不可は管理者自身の args 供給を見直す（このループの対象外）。

完了条件: `docs-only` は静的リバース完了で終端。`single-pass|iterative` は対象ファイルすべてが再現一致または NG 分類済み。対象が無ければ Phase 7 へ直行する。progress.jsonl に Phase 6 の completed 行が追記済み

### 動的検証 Phase 共通ゲート

`verification_mode=docs-only` では Phase 7〜11をすべてスキップする。この判定は画面レジストリのURL・baseline_tag・過去のjudge結果より優先する。`single-pass` は1回の明示的な統括起動につき、各画面の judge を最大1回だけ実行して停止する。後日の明示的な再起動では、改めて最大1回の検証を実行してよい。`iterative` だけが設定された上限内で自動反復する。

### Phase 7: ⑥sync（基準確立・基準未確立時）

Bash で `<verification_dir>/progress.jsonl` に phase="Phase 7" status="started" の行を追記する。状態が基準未確立の場合に実行する。Skill で syncing-reverse-env を design-doc・mode=sync で起動する。status=PASS なら基準タグ（baseline_tag）が確立する。FAIL の場合、`single-pass` は理由と改善候補を報告して停止し、`iterative` の場合だけ hint に基づき Phase 6 への差し戻しを許可する。

完了条件: baseline_tag が確立済み（status=PASS）。progress.jsonl に Phase 7 の completed 行が追記済み

### Phase 8: ⑦implement

Bash で `<verification_dir>/progress.jsonl` に phase="Phase 8" status="started" の行を追記する。状態が往復未検証の場合に実行する。Skill で rebuilding-code-from-docs を mode=implement・scope・reverse_worktree・ports・baseline_tag_status・output_dir・資産paths（template_root/audit_script_path/chapter_map_path）・user-approved で起動する。返却 status=NEED-COMPARE を受領し、拡張フィールド compare_request（scope / design_doc / freeze_commit / scenarios_ready）を取得する。INTERNAL-CONTRADICTION / ERROR / BLOCKED の場合は hint を確認してユーザーに報告し中断する。

完了条件: compare_request が取得済み（status=NEED-COMPARE）。progress.jsonl に Phase 8 の completed 行が追記済み

### Phase 9: ⑧sync dry-run（比較）

Bash で `<verification_dir>/progress.jsonl` に phase="Phase 9" status="started" の行を追記する。Skill で syncing-reverse-env を design-doc・mode=sync・dry-run で起動する。返却される比較結果ブロック（static_diff / dynamic / env_check / status / hint を含む15フィールド全文）をそのまま保持し、次 Phase へ args として渡す。

完了条件: 比較結果ブロックが省略なく取得済み。progress.jsonl に Phase 9 の completed 行が追記済み

### Phase 10: ⑨judge

Bash で `<verification_dir>/progress.jsonl` に phase="Phase 10" status="started" の行を追記する。Skill で rebuilding-code-from-docs を mode=judge・screen_dir・compare_result（Phase 9 の返却ブロック全文）・reverse_worktree・freeze_commit（Phase 8 完了時に compare_request から受け取り保持していた値）で起動する。status=PASS なら Phase 11 へ進む。status=FAIL なら `references/contract.md` の「NG帰着3系統の配線」に従い分類する。`verification_mode=single-pass` では分類結果と改善候補を報告して停止する。`iterative` の場合だけ、(c) 共通文書欠落なら Phase 4 を mode=append で再起動してから Phase 8 ④implement へ差し戻す。(a) 執筆規律不足・(b) facts欠落 はスキル資産の改訂が必要なためユーザーへ報告する。DESIGN-INCOMPLETE / DYNAMIC-UNVERIFIED も `single-pass` では保留として停止し、`iterative` の場合だけ hint に従い設計書修正または Phase 9 再実行を判断する。

完了条件: PASS / FAIL いずれかに確定している。progress.jsonl に Phase 10 の completed 行が追記済み

### Phase 11: ⑩sync本番/teardown（検証完了・PASS時）

Bash で `<verification_dir>/progress.jsonl` に phase="Phase 11" status="started" の行を追記する。Phase 10 が PASS の場合のみ実行する。ユーザーから user-approved を取得し、Skill で syncing-reverse-env を design-doc・mode=sync・user-approved で起動して基準タグを本番更新する。PASSを決定的出力で確認した管理者が、画面レジストリの当該エントリを `status=baseline-established` に更新する。検証終了の依頼があった場合は mode=teardown で環境を片付ける（user-approved 必須）。

完了条件: 基準タグが更新済み、または依頼時は teardown が完了している。progress.jsonl に Phase 11 の completed 行が追記済み

## 完了条件

| Phase | 完了条件 |
|---|---|
| 事前ヒアリング | `auto|screen`は4項目（対象パス・出力先・画面範囲・実行モード）が確定済み。`python`はtarget_repo_path・output_dir・target_file_paths・facts_unit_id・verification_dir・実行モードが確定済みでscreen_scopeは不要。headless=trueはprofile別必須引数が指定済みの場合だけスキップ |
| Phase 1 | 状態キーが確定し、残り全工程のタスク一覧が TaskCreate で一括登録済み |
| Phase 2 | survey_doc_path が確定している（アーキ未調査時のみ） |
| Phase 3 | unit_kinds_present の全種別について一覧HTMLが存在し、excluded-kinds.json が存在する（一覧未生成時のみ） |
| Phase 1C | 機能一覧.html が存在する（画面一覧確立後。派生一覧のため unit_kinds_present の判定対象外） |
| Phase 1D | 生成可能なマトリクス・対応表ページ・AI設定資産ページが存在する（機能一覧確立後。派生補完のため unit_kinds_present の判定対象外） |
| Phase 4 | common_docs_root が確定している（共通未採録時のみ） |
| Phase 5 | `docs-only` はスキップ済み。動的検証ありでは env_block の7フィールドが確定、または取得不能理由を「動的検証保留」として記録済み |
| Phase 6 | 全モードで facts・基本設計・詳細設計が完成。`docs-only` は静的リバース完了、動的検証ありでは画面開通後の対象ファイルが再現一致または検証結果報告済み |
| Phase 7 | `docs-only` は対象外。動的検証ありでは baseline_tag が確立済み、または保留理由を記録済み |
| Phase 8 | `docs-only` は対象外。動的検証ありでは compare_request が取得済み、または保留理由を記録済み |
| Phase 9 | `docs-only` は対象外。動的検証ありでは比較結果ブロックが取得済み、または保留理由を記録済み |
| Phase 10 | `docs-only` は対象外。動的検証ありでは PASS / FAIL / 動的検証保留のいずれかに確定 |
| Phase 11 | `docs-only` または非PASSは対象外。PASS時は基準タグ更新済み、または依頼時 teardown 完了 |
| **Goal** | `docs-only` は全対象画面の facts・基本設計・詳細設計が完成。動的検証ありは PASS、NG分類済み、または「静的リバース完了・動的検証保留」が確定。いずれも最終報告フォーマットの必須フィールドを含む |

## 最終報告フォーマット

管理者が Goal 到達時（または中断報告時）に提示する最終報告には、以下7種の必須フィールドをすべて含める。

| フィールド | 内容 |
|---|---|
| 種別判定結果 | 全6種別それぞれについて、アーキテクチャ調査書の実在判定（実在する／実在しない・理由）と対応する成果物パス（一覧HTML または `<種別>一覧（該当なし）.md`）を記す |
| 6種別到達状態 | 全6種別（screen/api/table/batch/report/external）それぞれの到達状態を3値（生成済み / 対象外 / 後続未対応）で記す（正本は `references/contract.md` の「種別ループ」） |
| 盲検分離充足状況（無人時のみ） | headless=true 実行時に限り、原本を読む工程と設計書のみで判定する工程が同一プロセスか分離実行かを記す（正本は `references/contract.md` の「無人モード仕様」の「盲検分離の必須要件」） |
| 部分著述 | 画面ごとに「対象ファイルn件/全m件」の形式で著述完了対象ファイル数と当該画面の全対象ファイル数を記す（正本は `references/contract.md` の「画面完了の定義」） |
| テスト実行結果 | 保存済みテストコード（rebuilding-screen-unit-from-docs の saved_test_paths 由来）の実行結果一覧を画面ごとに記す |
| 進捗ファイルの行数と最終行 | `<verification_dir>/progress.jsonl` の総行数と最終1行の内容を記す（工程の進行が実際に記録されていたことの裏取り） |
| 各工程のSkill起動有無と返却status | 実行した全工程について、子スキルを Skill ツールで起動したか否かと、返却された status を工程ごとに記す（完全仲介方式の禁止形が遵守されたことの裏取り） |

## 報告書式（3表テンプレート）

最終報告フォーマットの各フィールドは、次の3表のいずれかに集約して記載する。表の列・凡例は削除せず、値が無い場合も列自体は残し「該当なし」等で埋める。

### 表1: 種別判定・納品物ルート表

「種別判定結果」フィールドの書式。全6種別を1行ずつ記載する。

| 種別 | 実在判定 | 成果物パス | 到達状態 |
|---|---|---|---|
| screen | 実在する | `一覧/画面一覧/画面一覧.html` | 生成済み |
| api | 実在する | `一覧/API一覧/API一覧.html` | 後続未対応 |
| table | 実在しない（理由: …） | `一覧/テーブル一覧（該当なし）.md` | 対象外 |
| feature（派生） | 判定対象外（派生一覧） | `一覧/機能一覧/機能一覧.html` | 生成済み |
| … | … | … | … |

feature（機能一覧）は派生一覧であり、実在判定（unit_kinds_present）の対象外。到達状態は 生成済み / 未生成 の2値で記す。

### 表2: 画面単位の工程進行表

「部分著述」「テスト実行結果」フィールドの書式。対象画面ごとに1行を記載する。

| 画面ID | 現在Phase | 状態キー | 部分著述（n件/m件） | テスト実行結果 |
|---|---|---|---|---|
| screen-<画面ID> | Phase 10 | 検証完了 | 5件/5件 | PASS 5/5 |
| … | … | … | … | … |

### 表3: フェーズ完了ごとの増分報告

「各工程のSkill起動有無と返却status」「進捗ファイルの行数と最終行」フィールドの書式。工程（Phase）ごとに1行を記載する。

| Phase | Skill起動有無 | 返却status | 増分成果物 |
|---|---|---|---|
| Phase 2 | 起動済み | 調査確定 | アーキテクチャ調査書.md |
| Phase 3 | 起動済み | DONE | 一覧HTML × unit_kinds_present件数 |
| … | … | … | … |

進捗ファイル（`<verification_dir>/progress.jsonl`）の総行数と最終1行の内容は表3の末尾に注記として添える。

### 適用規則

- チャット上の報告では3表をそのまま（Markdown表として）表示する。要約に潰さない
- 無人モード（headless=true）では、最終報告ファイル（`<verification_dir>/screen-<画面ID>/<timestamp>/実行レポート.md` 等）にも同じ3表をそのまま含める
- 列・凡例の削除を禁止する。プロジェクトによって値が無い列（例: 「後続未対応」種別が無いプロジェクトの表1）も列自体は残し、該当行が無ければ「該当なし」と明記する

## サブエージェント委任仕様

| 呼び出し箇所 | invocation | args骨格 | 期待返却status |
|---|---|---|---|
| Phase 2（アーキ未調査時） | surveying-architecture-for-reverse-docs | target_repo_path, output_dir, template_root, mode | 調査確定 |
| Phase 3（一覧未生成時） | generating-<種別>-list-for-reverse-docs（不在種別ごとに対応スキル） | source_dir, output_dir | DONE |
| Phase 1C（画面一覧確立後） | generating-feature-list-for-reverse-docs | source_dir, output_dir | DONE |
| Phase 1D（機能一覧確立後） | generating-cross-views-for-reverse-docs | target_repo_path, output_dir, portal_output_dir（任意） | DONE |
| Phase 4（共通未採録時） | generating-reverse-common-docs | target_repo_path, output_dir, template_root, survey_doc_path, mode | 採録v0確定 |
| Phase 5 | syncing-reverse-env | design-doc, mode=setup | PASS（env_block抽出） |
| Phase 6（静的著述後の画面未開通時） | unlocking-reverse-target-screens | invocation_mode=dynamic-only, system, screen_id, reverse_worktree, ports, output_dir, user-approved | UNLOCKED |
| Phase 0P（明示Python facts-only） | extracting-unit-facts-from-code | target_repo_path, target_file_paths, logical screen_dir, verification_dir, profile=python, survey_doc_path, run_id | 封印済み→Python facts封印完了 |
| Phase 6（画面の事実未封印時） | extracting-unit-facts-from-code | target_repo_path, target_file_paths, screen_dir, verification_dir, profile=screen, survey_doc_path, run_id | 封印済み |
| Phase 6（基本設計未著述時） | generating-reverse-basic-design | screen_dir, output_dir, template_root, scaffold_script_path, facts_ref, common_docs_root, unit_kind, authoring_pass, detail_design_path・pass1_receipt_path（large-pass2時） | 基本設計著述完了 |
| Phase 6（設計書未著述時） | generating-reverse-detailed-design | screen_dir, output_dir, template_root, chapter_map_path, audit_script_path, scaffold_script_path, facts_ref, common_docs_root, mode, target_file_path, verification_url, verification_dir, authoring_pass, detail_design_path・pass1_receipt_path（companion-docs時） | AUTHORED / DETAIL_AUTHORED / COMPANION_AUTHORED |
| Phase 6（ファイル単位未検証時） | rebuilding-screen-unit-from-docs | screen_dir, target_file_path, 資産paths, env_block, user-approved, verification_mode | 再現一致 / 再現不一致 / 差し戻し |
| Phase 7 | syncing-reverse-env | design-doc, mode=sync | PASS |
| Phase 8 | rebuilding-code-from-docs | mode=implement, scope, reverse_worktree, ports, 資産paths, user-approved | NEED-COMPARE |
| Phase 9 | syncing-reverse-env | design-doc, mode=sync, dry-run | PASS/FAIL（比較結果） |
| Phase 10 | rebuilding-code-from-docs | mode=judge, screen_dir, compare_result, reverse_worktree, freeze_commit | PASS/FAIL |
| Phase 11 | syncing-reverse-env | design-doc, mode=sync／teardown, user-approved | PASS |

Agent（サブエージェント）は preflight の並行事実確認等に限定して用いる。実検証は子スキルへ委ねる。

**並列起動**: `authoring_mode=standard` は generating-reverse-basic-design と generating-reverse-detailed-design を同時起動する。`authoring_mode=large-two-pass` は詳細設計のパス1を単独で完了させた後、パス2の基本設計と周辺文書を同時起動する。パス境界をまたぐ並列化は禁止する。

## タスク一覧フォーマット

Phase 1 の状態判定完了後に一括登録するタスク一覧の設計。

### subject 形式

`Phase <N>[-<N>]: [<画面ID>: ]<工程名>[ ← 並列グループ<G>]`

- 画面横断工程（アーキ調査・一覧生成・共通採録）: 画面IDなし
- 画面単位工程: 画面ID付きで画面数分展開
- 並列実行対象: 並列グループIDを末尾に付与し、同グループは Agent(run_in_background: true) で同時起動

### 展開例（画面 A・B の 2 件、アーキ〜一覧は完了済みの場合）

| subject | 並列 |
|---|---|
| Phase 4: 共通採録 | — |
| Phase 6: 画面A: 事実封印 | — |
| Phase 6: 画面A: 基本設計 | 並列グループ-画面A-設計 |
| Phase 6: 画面A: 詳細設計 | 並列グループ-画面A-設計 |
| Phase 6: 画面A: ファイル検証 | — |
| Phase 7: 画面A: 基準確立 | — |
| Phase 8-10: 画面A: 往復検証 | — |
| Phase 6: 画面B: 事実封印 | — |
| Phase 6: 画面B: 基本設計 | 並列グループ-画面B-設計 |
| Phase 6: 画面B: 詳細設計 | 並列グループ-画面B-設計 |
| Phase 6: 画面B: ファイル検証 | — |
| Phase 7: 画面B: 基準確立 | — |
| Phase 8-10: 画面B: 往復検証 | — |
| Phase 11: 基準更新 | — |

### ルール

- Phase 1B（6一覧並列）は「Phase 1B: 一覧生成-画面」「Phase 1B: 一覧生成-API」…と種別分展開し、全て同一並列グループ
- Phase 1C（機能一覧）は「Phase 1C: 機能一覧生成」の1タスクとして登録する（派生一覧のため種別展開しない）
- Phase 1D（マトリクス・対応表生成）は「Phase 1D: マトリクス・対応表生成」の1タスクとして登録する（派生補完のため種別展開しない）
- Phase 4C（画面バッチ）使用時は Phase 6〜10 を「Phase 4C: 画面バッチ実行」1タスクに集約する
- 差し戻し発生時は差し戻し先工程を新規 TaskCreate で末尾に追加（既存タスクの状態は変更しない）
- headless=true 時もタスク一覧は同じ形式で生成する（進捗の可視化用途。実行制御は per-item prompt が担う）

## ループ設計

| 要素 | 内容 |
|---|---|
| 反復条件 | `verification_mode=iterative` かつ Phase 10 ⑨judge が FAIL → NG帰着3系統で分類し、(c) 共通文書欠落なら Phase 4（mode=append）を経て Phase 8 ⑦implement へ戻す。(a)/(b) はユーザー報告 |
| 上限回数 | max_loop（既定3。⑧の max_loop とは別軸の工程ループ） |
| 停止条件 | ① 収束停止: 全対象画面が PASS（2連続で確定）② リソース上限: max_loop 到達で FAIL 確定 ③ 発散検知: ⑨judge が2連続同一差分（compare_result の static_diff 署名一致）で上限前に打切り |
| 検証役の分離 | 各工程の判定は子スキルの返却ブロック（status）のみで行い、管理者は自然文で判定しない |

この外側ループ（発散判定2連続・上限）は、元々④（rebuilding-code-from-docs）が持っていた責務を管理者へ移管したものである。

### Phase 6 内: 設計書未著述⇄ファイル単位未検証 ループ

| 要素 | 内容 |
|---|---|
| 反復条件 | `verification_mode=iterative` かつ rebuilding-screen-unit-from-docs（ファイル単位未検証）が status=差し戻し を返したら generating-reverse-detailed-design（設計書未著述）へ戻し、再著述後にファイル単位未検証を再実行する |
| 上限回数 | 5回目安（rebuilding-screen-unit-from-docs 自身の内側ループ上限と揃える） |
| 停止条件 | ① 収束停止: rebuilding-screen-unit-from-docs が status=再現一致 を返す ② リソース上限: 5回到達しても差し戻しが続く場合はユーザーに報告する |
| 検証役の分離 | 設計書未著述（著述）とファイル単位未検証（盲検検証）は別スキル・別セッションで実行され、判定は自身の完全性ゲート・6計測の決定的出力のみで行う |

## 重要な注意事項

- 子スキルは args 全量指定・対話ゼロで起動する（子は AskUserQuestion を発行しない契約）
- 白紙化などの破壊的操作のユーザー承認は管理者が事前に取り、user-approved として args で渡す（子はユーザーに直接聞かない）
- output_dir が null のときの展開先確認も管理者が担う
- 各子スキルは単独起動可能（ユーザーが同じ args を手渡せば動く）。工程順序を知るのは管理者だけ
- 無人モードを含む全モードで、各工程は必ず Skill ツールで子スキルを起動すること。子スキルの手順を管理者が直接実行することを禁止する。Skill 起動が失敗する場合は失敗として記録し、代替実行しない

## 予想を裏切る挙動

- 状態判定は「アーキテクチャ調査書の実在 → 各種別の一覧HTML + excluded-kinds.json の実在 → プロジェクト共通10文書の実在 → facts封印の実在 → 画面基本設計書の実在 → 設計書/対象ファイル/著者スキルの完全性ゲート成果物の実在 → 画面開通有無 → 検証記録の再現一致有無 → ⑤setup返却の baseline_tag → ⑨judge の status」の順の判定フロー。静的リバースを先行するため、画面未開通でも設計書著述まで進める。成果物の実在から毎回評価するので中断後も再開できる
- ⑨は mode で2分割される（implement=比較要求を返して停止 / judge=比較結果を受け取り判定）。管理者がこの2回を別々に起動し、間に⑧sync dry-run を挟む
- scaffold_script_path は管理者がリポジトリ展開先の `shared/scripts/scaffold-screen.sh`（正本はこの1本のみ）を解決して generating-reverse-detailed-design / rebuilding-screen-unit-from-docs に渡す（audit_script_path と同型）
- 静的著述後の画面未開通では `unlocking-reverse-target-screens(invocation_mode=dynamic-only)` を起動し、開通・レジストリ記帳・設計書 frontmatter の実測項目補完まで行う。基準確立は後続の Phase 5/7 が担う。単独起動の `standalone` だけは従来どおり基準タグ確立まで完走する
- 事実未封印〜ファイル単位未検証の間は、extracting-unit-facts-from-code（原本を読む唯一の役）→著述モード別の basic/detailed design（原本を読まず facts を読む）→ rebuilding-screen-unit-from-docs（factsも原本も読まない）の順で情報アクセスを絞る。基本設計は詳細設計を内容の出典にはしない。大規模ユニットではパス1の詳細設計を開始証跡としてパス2へ渡す。`verification_mode=iterative` で rebuilding が status=差し戻し を返した場合だけ detailed-design の著述へ戻る
- judge FAIL 時の自動改善は `verification_mode=iterative` の場合だけ有効。NG帰着(c)共通文書欠落は管理者が generating-reverse-common-docs を mode=append で再起動できるが、(a)執筆規律不足・(b)facts欠落 はスキル資産（reference・プロファイル）の改訂を要するため、管理者は自動配線せずユーザーに報告する（`references/contract.md` の「NG帰着3系統の配線」）
- 2026-07-22 実測: 無人セッション内のサブエージェント経由で Phase 6 を実行し、ファイル検証工程のネスト委任不可で画面が failed 終端した

## 参照資料

- `references/contract.md` — 返却ブロック契約・args仕様・状態判定表・種別ループ・NG帰着3系統の配線の正本
- 共有資産（本スキル専有ではなくリポジトリ共通、`~/reverse-docs-skills/shared/` 配下）: `shared/templates/リバース検証/`（テンプレート一式）、`shared/scripts/audit-consistency.sh`（工程間ゲート）、`shared/scripts/scaffold-screen.sh`（画面ディレクトリのテンプレート展開。正本はこの1本のみ）、`shared/scripts/seal-facts.sh`（facts封印・検証）、`shared/references/chapter-map.md`（章役割キー対応表）、`shared/references/facts-schema.md`（facts.ymlスキーマ正本）、`shared/references/リバース工程設計.md`（Phase/Step×スキル対応の正本）。各子スキルへは template_root / audit_script_path / scaffold_script_path / chapter_map_path として絶対パスを渡す
- 画面レジストリ: `<output_dir>/一覧/reverse-screen-registry.yml`（正本定義は references/contract.md）
- `unlocking-reverse-target-screens/manifest.yml` — 同スキルが管理するプロジェクト固有値の正本（本スキルは関知しない）

## 完了報告

`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（作業報告型）に従う。

固有の検証行:
- 通過 Phase 数・最終状態キーの確定

## 設計判断

### build-portal / render-template

**必要性**: ポータル生成はリバース設計フローの Phase 4A で毎回実行される。テンプレート置換ロジック（render_template）は build-unit-list.sh と build-screen-list.sh に既に重複定義されており、ポータル生成でも同じロジックが必要なため、共通関数として render-template.sh に抽出した。build-portal.sh はコード行数計測・一覧件数抽出・JSON組み立て・テンプレート置換の複合処理であり、Bash ツール直叩きでは毎回の実行でトークンを大量に浪費する。

**代替案を採用しなかった理由**:
- Bash ツール直叩き: 200行超のスクリプトを毎回トークンとして消費する。フロー内で Phase 4A として繰り返し呼ばれるため非効率
- 既存 Makefile ターゲット拡張: reverse-docs-skills リポジトリに Makefile は存在しない
- package.json scripts 追加: 同リポジトリに package.json は存在しない

**保守責任者**: 人手（ユーザー）。テンプレートのプレースホルダや一覧HTMLのJSON構造を変更する場合は build-portal.sh と portal-template.html を同時に更新する。METRICS_JSON は構造化オブジェクト形式である。形式変更時はテンプレート（portal-template.html）とスクリプト（build-portal.sh）を同一コミットで同時更新する。トークンブロックは portal-template.html と detail-pages テンプレ4本（`shared/templates/detail-pages/`）で複製している。色定義・テーマ切替を変更する場合は両方を同時に更新する

**廃棄条件**: リバース設計フロー自体が廃止された時、またはポータル生成が別の仕組み（専用スキル等）に置き換えられた時

### build-detail-page.sh / validate-page-data.sh

**必要性**: 基盤ページ5枚（用語辞書・技術スタック・画面遷移図・ER図・環境構築手順）は、生成スキルが抽出した page-data.json をテンプレ4本へ流し込む処理を共通で必要とする。この流し込みロジックを各スキルに複製すると、`build-portal.sh` の FUTURE_FILES と出力ファイル名がスキルごとにずれる事故が起こりうる。`build-detail-page.sh` は page 種別 → テンプレ・固定出力ファイル名の対応表を1箇所に固定し、FUTURE_FILES との一致を機械保証する。`validate-page-data.sh` は埋め込みJSONの `jq -S` 一致・マーカー衝突・未解決 `{{` の残存・sourceRef の実在確認を、抽出者（各スキル）非依存で検証する。いずれも複数の決定的処理を含み、Bash ツール直叩きでは self-test を持てず回帰検証ができない。

**代替案を採用しなかった理由**:
- Bash ツール直叩き: 5スキル × 生成のたびに同じ流し込み・検証手順を手書きすると条件がぶれ、FUTURE_FILES との不一致を機械的に検知できない
- 既存 Makefile ターゲット拡張: 本リポジトリに Makefile は存在せず、新規導入は本チェック専用の依存を増やすだけになる
- package.json scripts 追加: 同様に本リポジトリはビルド設定を持たない

**保守責任者**: 人手（ユーザー）。テンプレ4本を変更する場合は build-detail-page.sh の対応表・page-data-schema.md・validate-page-data.sh を同時に更新する

**廃棄条件**: 詳細ページ機構（基盤ページ5枚の生成）自体が廃止された時
