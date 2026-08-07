---
name: orchestrating-reverse-docs-flow
description: "リバース設計書往復検証フローを統括。 TRIGGER when: リバース検証の進行・工程統括・画面一覧から基準確立まで。 SKIP: 個別工程の単体実行。"
invocation: orchestrating-reverse-docs-flow
type: orchestration
allowed-tools: [Agent, AskUserQuestion, Bash, Edit, Glob, Read, Skill, TaskCreate, TaskUpdate, Write]
---

# リバース設計書往復検証オーケストレーションスキル

リバース設計書往復検証フローの進行係（管理者）。自分では検証・比較・実装を行わず、状態判定 → 子スキルを args 全量指定で Skill 起動 → 返却ブロックの status で検収 → 次工程決定、というループで工程全体を統括する。

子スキル群は互いを知らず、工程間の受け渡しはすべて本スキルが仲介する（完全仲介方式）。契約の定義と内訳は `references/contract.md` 冒頭の「子スキルの内訳」節を正本とする。

## 使用タイミング

- リバース検証を工程統括したいとき（アーキテクチャ調査から基準タグ確立までの一連の流れ）
- 個別工程だけを動かしたい場合は各子スキルを単独起動する（各子スキルは同じ args を手渡せば単独でも動く契約）

## 起動引数

| 引数 | 必須 | 内容 |
|---|---|---|
| reverse_docs_root | 必須 | 配布されたreverse-docs-skillsルートの絶対パス。統括が実在確認して解決し、共有スクリプト・テンプレート・契約を使う全子スキルへ渡す |
| target_repo_path | 必須 | リバース対象プロジェクトの絶対パス。全工程・全子スキルへ渡す入力の正 |
| output_dir | 必須 | 納品物ルートの絶対パス。ポータル・一覧・設計書等すべての出力先の正（「納品物ルート（output_dir）の正本レイアウト」参照） |
| screen_scope | `facts_profile=auto|screen`時必須（`python`時は不要。画面範囲を問わないため） | 対象画面範囲（全画面／個別画面ID列挙等）。種別ループ・画面状態判定の起点 |
| verification_dir | 任意 | 既定 `<output_dirの親>/verification/`。facts・再計数・封印記録・修正指示書・最終報告・テストログの出力先 |
| template_root | 任意 | 既定 `<reverse_docs_root>/shared/templates/リバース検証/`（`shared/templates/リバース検証/` 配下のテンプレート一式。「共有資産」節参照）。テンプレート一式を使う全子スキルへ絶対パスとして渡す |
| survey_doc_path | 任意 | 既定候補 `<output_dir>/プロジェクト共通/アーキテクチャ調査書.md`。候補が不在、または調査ゲート不合格の場合は surveying-architecture-for-reverse-docs を起動し、返却 `status=調査確定` の `artifacts[0]` を確定値として採用する（Step 3 参照） |
| headless | 任意（既定 false） | true の場合、無人モードで実行する。AskUserQuestion を発行せず、破壊的操作の承認は起動時に一括付与済みとして扱う |
| verification_mode | 任意（既定 `single-pass`） | `docs-only` は facts 抽出・基本設計・詳細設計まで、`single-pass` は動的検証を1回実行、`iterative` は FAIL 後の改善反復も行う |
| facts_profile | 任意（既定 `auto`） | `auto|screen|python`。`auto|screen`は通常の画面フローを`profile=screen`で実行する。`python`は明示指定時だけ、画面一覧・画面状態判定へ入る前のfacts-only経路を実行して終端する |
| target_file_paths | `facts_profile=python`時必須 | Python facts-only経路で抽出する、`target_repo_path`からの相対`.py`パス配列。全件`.py`でなければ中断する |
| facts_unit_id | `facts_profile=python`時必須 | Python facts-only出力を識別する論理ID。画面IDではなく、`<verification_dir>/screen-<facts_unit_id>/facts/<run_id>/`の識別子としてだけ使う |
| proposal_output_ref | 用語候補生成を要求する場合のみ必須 | `target_repo_path` の外にある、明示的な絶対 `.yaml` / `.yml` パス。省略・対象repo内・相対パスなら候補生成を開始しない。推測補完は禁止 |
| approved_glossary_ref | 承認済み用語ページを生成する場合のみ必須 | schema検証済みかつ承認済みの用語YAMLへの絶対パス。候補proposalを直接指定してはならない |

無人モード（headless=true）の詳細仕様（置き換え表・盲検分離の必須要件・安全設計・実行レポートの置き場・前提事実）は `references/contract.md` の「無人モード仕様」節を正本とする。無人モード（headless=true）では工程の開始・完了のたびに `<verification_dir>/progress.jsonl` へ JSON 行を追記する（形式: `{"ts":"<ISO8601>","screen_id":"<画面ID>","phase":"<工程名>","status":"started|completed|failed"}`）。呼び出し元セッションや人間はこのファイルの監視で現在工程を把握できる。

## 基本ワークフロー

成果物の実在から現在の状態を判定し、次に起動する子スキルを機械的に決定する。状態一覧（16状態）の実在判定基準・args・返却フィールドの定義は `references/contract.md` の状態判定表を正本とする。

**状態判定の採用元**: `references/contract.md` の状態判定表は判定根拠の説明である。実際の状態判定は `bash scripts/resolve-flow-state.sh <output_dir> [<target_repo_path>] --screen-id <画面ID> [--system <システム名>] [--reverse-worktree <reverse_worktree>] [--target-file <対象ファイルbasename>]` を実行し、標準出力の状態キー1行をそのまま採用する（自然文の自己申告に代える機械判定）。空文字や未定義の状態キーは返さず、判定不能時は「未判定」を返す。「未判定」を受け取った場合は screen_id の解決状況（画面一覧マニフェストの実在・`--screen-id` 指定漏れ）を確認してから再実行する。

複数サイトの場合、`references/contract.md` の状態判定表にある `<output_dir>` は「当該サイトのサイトルート」と読み替える。

画面開通は facts 抽出・基本設計・詳細設計の前提条件ではない。原本コードと封印済み facts から静的リバースを先に完了し、画面開通はファイル単位検証・基準確立・往復検証へ進む直前にだけ要求する。開通できない場合も静的成果物は破棄せず「静的リバース完了・動的検証保留」として報告する。

ファイル単位未検証が `status=差し戻し` を返した場合、`verification_mode=iterative` のときだけ設計書未著述へ戻す。`single-pass` では差し戻し理由を記録して停止し、`docs-only` ではファイル単位検証自体を起動しない。アーキ未調査・共通未採録はプロジェクト単位で1回だけ確定させればよく、画面ごとに繰り返さない。

## 実行手順

グローバル順序の正本は `shared/references/リバース工程設計.md` の Phase 1〜7 / global Step 1〜30 とする。本節の見出しは `Step <親Phase>-<Phase内連番>`、直下の `global_step` は全体で一意な実行順を表す。英字接尾辞・Phase 0・Step 0・重複番号は使用しない。

## Phase 1: 準備

headless=trueではAskUserQuestionを使わず、選択したprofileの必須引数が不足していれば推測せず中断する。対話実行では、`facts_profile=auto|screen`かつtarget_repo_path・output_dir・screen_scopeが指定済みの場合、または`facts_profile=python`かつtarget_repo_path・output_dir・target_file_paths・facts_unit_id・verification_dirが指定済みの場合だけ確認を省略する。Python経路ではscreen_scopeを要求せず、事前ヒアリング完了後は Step 1-2 の明示Python facts-only経路へ分岐する。通常の画面フローだけが global Step 3 以降へ直行する。

## Step 1-1: 対象リポジトリと出力先を解決する

- global_step: 1
- tool: AskUserQuestion / Read / Glob / TaskCreate
- condition: 常に実行

AskUserQuestionツールでprofileに応じた必須項目を確定する。起動引数が空の対話実行では、最初に`facts_profile=auto|screen|python`を選ばせてから同じ規則を適用する。`facts_profile=auto|screen`では対象プロジェクトパス・出力先パス・画面範囲・実行モードの4項目を確定する。

起動引数の `reverse_docs_root`・`target_repo_path`・`output_dir`・`screen_scope` を解決する。`reverse_docs_root` は配布rootの絶対パスとして実在確認し、固定インストール先を仮定しない。未指定かつ `headless=false` の場合だけ AskUserQuestion で対象プロジェクト、出力先、画面範囲を確認する。`headless=true` では引数不足を ERROR として終端し、値を推測しない。成果物の実在から16状態を順に判定し、実行対象の global Step を TaskCreate で先出し登録する。

`facts_profile=python`では画面範囲を尋ねず、対象プロジェクトパス・出力先パス・実行モードに加えて以下の3項目を確定する:

| 項目 | 入力契約 | 既定値 |
|---|---|---|
| target_file_paths | `target_repo_path`からの相対`.py`パスの非空配列。全件の実在とリポジトリ内包を確認し、外部絶対パス・`..`・symlink脱出を拒否する | なし（必須） |
| facts_unit_id | facts出力を識別する論理ID。画面IDや実在画面ディレクトリを要求しない | なし（必須） |
| verification_dir | facts・再計数・封印記録の出力先 | `<output_dirの親>/verification/` |

状態判定の冒頭で対象画面IDの実在を検証する。実在確認は永続raw正本（`<output_dir>/一覧/画面一覧/screen-manifest.json` の `screens[]` 配列）に対して行う。一覧外IDの場合は AskUserQuestion で対応を確認する。選択肢は (a) 一覧へ `kind=route`・`route=""` として追記し、route空の未解決画面として工程を継続するか、(b) エラー終端するかの2択（headless=true 時は (a) を自動選択する）。画面レジストリの `verification_url` が未実施・エラーページ・プレースホルダの場合でも、facts 抽出・基本設計・詳細設計は続行する。実レンダリング確認済みURLは動的検証へ移る時点でのみ必須とする。

**完了**: `auto|screen`はtarget_repo_path・output_dir・screen_scope・実行モードが、`python`はtarget_repo_path・output_dir・target_file_paths・facts_unit_id・verification_dir・実行モードが確定し（`python`はscreen_scopeを要求しない）、現在状態の確定と実行対象タスクの登録が済んでいる。

## Step 1-2: スコープと実行モードを確定する

- global_step: 2
- tool: AskUserQuestion / Read
- condition: headless=true または全引数指定済みなら確認を省略

`verification_mode=docs-only|single-pass|iterative`、対象画面、フル実行か個別スキル利用かを確定する。「複雑度層別サンプル」は既存の複雑度プロファイルから sampledScreenKeys の和集合を screen_ids に変換し、未生成なら画面一覧スキルのプロファイル工程を先行する。

- **フル実行（facts_profile=python）**: 確定したtarget_repo_path・output_dir・target_file_paths・facts_unit_id・verification_dirを使って後述の「明示Python facts-only経路」へ進む。global Step 3 以降へは進まない
- **フル実行（facts_profile=auto|screen）**: 確定したtarget_repo_path・output_dir・screen_scopeを使って global Step 3 以降を順に進行する
- **個別スキル利用**: 指定されたスキルを args 全量指定で単独起動し、完了をもって本フロー全体を終了する

### サイトを確定する（アーキテクチャ調査書 §10 が確定済みのとき）

アーキテクチャ調査書 §10 のサイト一覧を提示し、どのサイトを対象にするかを確定する。単独プロジェクトならサイトは 1 件（キー `main`）で、確認は不要。モノレポで 2 件以上ある場合は、全サイトを対象にするか一部だけかをユーザーに確認する。§10 がまだ確定していない（初回起動でアーキ調査が未実施）場合は、global Step 7（調査確定の検収）直後にあらためて本段階を実行してから global Step 9 以降へ進む。

### サイトごとのループ（モノレポ・複数サイト時）

前段の「サイトを確定する」で複数サイトを対象に確定した場合、global Step 3〜16 を確定した対象サイトごとに繰り返す。各サイトのループでは `output_dir` を `<納品ルート>/<サイトのルートディレクトリ>` に差し替えて実行する。サイト間は独立しており、あるサイトの失敗が他サイトの成果物を壊すことはない。いずれかのサイトで中断した場合はそのまま停止し、以降のサイトへは進まない。次回起動時は状態判定がサイトごとに行われるため、未完了のサイトから自動的に再開される。サイトをまたぐ巻き戻しは行わない。

### 明示Python facts-only経路

- conditional_step_id: python-facts-only-route

`facts_profile=python`が明示された場合だけ、事前ヒアリング完了後かつ画面ID実在確認より前にこの経路へ分岐する。`target_repo_path`・`target_file_paths`・`facts_unit_id`・`verification_dir`を検証し、`target_file_paths`が非空かつ全件`.py`であることを確認する。論理パス`screen_dir=<verification_dir>/logical/<facts_unit_id>`を組み立てるが、そのディレクトリの実在やスキャフォールディングは要求しない。

facts抽出より先に`survey_doc_path`を解決する。起動引数のsurvey_doc_pathが実在しアーキテクチャ調査ゲートを通る場合はそれを使う。未指定なら`<output_dir>/プロジェクト共通/アーキテクチャ調査書.md`を候補とし、候補が不在ならSkillでsurveying-architecture-for-reverse-docsをtarget_repo_path・output_dir・template_root・mode=surveyで起動する。候補が実在しても調査ゲートが不合格ならmode=revise・revise_findings付きで起動する。返却`status=調査確定`のartifacts[0]をsurvey_doc_pathとして記録し、実在と調査ゲート通過を再検収する。この前処理は画面一覧・対象画面ID・画面状態を参照しない。

survey_doc_path確定後に限り、Skillでextracting-unit-facts-from-codeをtarget_repo_path・target_file_paths・上記screen_dir・verification_dir・profile=python・survey_doc_path・run_idで起動する。返却`status=封印済み`、`recount-report.txt`のexit 0相当結果、`facts.lock`の`seal-facts.sh verify`通過を検収し、「Python facts封印完了」で本フローを終端する。画面一覧生成・対象画面ID実在確認・画面スキャフォールディング・基本設計/詳細設計著述には進まない。

`facts_profile=auto|screen`はこの経路を通らず通常の画面フローへ進む。通常の画面フローでは対象ファイルの拡張子にかかわらず`profile=screen`を渡し、拡張子だけを根拠にpythonへ切り替えてはならない。

**完了**: 実行モード（フル実行 / 個別スキル名）とユーザー介在条件が確定し、対象サイト一覧（キー・ルートディレクトリ）も確定している。`auto|screen`のフル実行は global Step 3 へ進める。`python`は明示Python facts-only経路でsurvey_doc_path確定後にfacts抽出・独立再計数・封印検証まで完了し、facts-only終端している。

## Phase 2: アーキテクチャ調査

## Step 2-1: 調査入力とテンプレートを検収する

- global_step: 3
- tool: Read / Skill
- condition: アーキ未調査または back_edge_id=architecture-revise のとき実行

surveying-architecture-for-reverse-docs へ target_repo_path・output_dir・template_root・mode を渡して、このブロックでは1回だけ起動する。既存調査書が無ければ mode=survey、下流の検出手がかり不足から戻った場合は mode=revise と revise_findings を渡す。返却ブロックと機械証拠を保持し、global Step 4〜7は同じ起動結果を順に検収する。部分起動modeがない子スキルをStepごとに再起動しない。

**完了**: 子スキルが調査に必要な入力を受理し、前提検査を通過している。

## Step 2-2: 決定的走査を実行する

- global_step: 4
- tool: Read
- condition: Step 2-1 通過時

global Step 3の同一起動が返した走査証拠から、技術スタック、ルーティング、6種別の検出根拠をReadで検収する。管理者は子スキルの走査手順を代行せず、再起動もしない。

**完了**: 走査結果が子スキルの返却候補へ含まれている。

## Step 2-3: アーキテクチャ調査書を著述する

- global_step: 5
- tool: Read
- condition: Step 2-2 通過時、または architecture-revise の戻り先

global Step 3の同一起動が生成した調査書をReadで検収する。revision では revise_findings の範囲だけが追記・修正され、既存の確定事実が保持されていることを確認する。

**完了**: survey_doc_path の候補が生成されている。

## Step 2-4: アーキテクチャ機械ゲートを実行する

- global_step: 6
- tool: Read
- condition: Step 2-3 完了時

global Step 3の同一起動が実行した check-architecture-survey.sh の終了コードと出力をReadで受領する。管理者の自然文判断で PASS を代替しない。

**完了**: 機械ゲートが PASS、または再修正に必要な決定的FAILが得られている。

## Step 2-5: 調査確定の返却を検収する

- global_step: 7
- tool: Read / TaskUpdate
- condition: Step 2-4 PASS時

global Step 3の同一起動から返された status=調査確定 と artifacts[0]=survey_doc_path を検収し、unit_kinds_present を保持する。status=中断は hint を報告して停止する。

**完了**: survey_doc_path と unit_kinds_present が確定し、global Step 9へ渡せる。

## Step 2-6: 検出手がかり不足を調査書へ差し戻す

- global_step: 8
- tool: TaskCreate / Skill
- condition: 下流がアーキテクチャ上の検出手がかり不足を決定的に報告した場合のみ

- back_edge_id: architecture-revise
- back_edge_target: global Step 5

revise_findings を固定し、Step 2-3へ戻す。既存タスクを巻き戻さず、差し戻しタスクを新規登録する。

**完了**: back-edge の理由・対象・上限が記録され、再調査が開始済みか停止判断済み。

## Phase 3: 目録

## Step 3-1: 実在種別の一覧を生成する

- global_step: 9
- tool: Agent / Skill
- condition: 一覧未生成時

unit_kinds_present に含まれる種別だけ、対応する6一覧スキルを起動する。対話モードは Agent で並列、headless は Skill で逐次実行する。各子へ source_dir・output_dir を渡し、status=DONE を検収する。画面については永続正本を `screen_manifest_path=<output_dir>/一覧/画面一覧/screen-manifest.json`、`screen_manifest_ext_path=<output_dir>/一覧/画面一覧/screen-manifest.ext.json` に固定し、検出直後の生マニフェストとメタデータ付与後マニフェストをそれぞれ原子的に保存する。

通常の再開実行は永続 screen_manifest_path を直接入力にする。旧成果物の明示的な移行・復元を行う場合に限り、画面一覧HTMLが存在して永続 screen_manifest_path が無ければ `bash shared/scripts/unit-list/restore-screen-manifest.sh <output_dir>/一覧/画面一覧/画面一覧.html <screen_manifest_path>` を実行して埋込 `#screen-manifest` から一度だけ復元する。続いて validate-manifest.sh を通し、固定した generated_at と raw の正規化SHA-256を `--generated-at`・`--manifest-content-hash` へ渡して extract-screen-metadata.sh で screen_manifest_ext_path を再生成する。復元・検証・メタデータ付与・hash一致のいずれかが失敗した場合は通常工程へ合流しない。

**注記**: 画面一覧.HTMLへ実際に埋め込まれているのは、build-unit-list.sh(内部でbuild-screen-list.shへ委譲)に渡した入力(`screen_manifest_ext_path`)そのものであり、派生フィールド(category/permissions/designDocStatus/existingTestCount/sourceHash等)を含む**拡張マニフェスト**である。したがって上記の復元手順で得られる内容も拡張マニフェスト相当であり、Phase 2の生検出結果そのものではない。extract-screen-metadata.shでのscreen_manifest_ext_path再生成は、この拡張マニフェストへgenerated_at・hashを確定付与し直す工程として扱う。

全種別の子スキルが status=DONE を返した後、`bash shared/scripts/unit-list/check-manifest-persistence.sh <output_dir>` を実行し、生成済みの一覧フォルダ（画面一覧・API一覧・テーブル一覧・バッチ一覧・帳票一覧・外部連携一覧・機能一覧のうち生成済みのもの）すべてで生マニフェスト・拡張マニフェストが `<output_dir>/一覧/<種別>一覧/` 配下へ実際に永続化されていることを機械検査する。各子スキルの SKILL.md 記述だけでは実際に永続化されたかを確認できないため（改善課題 1-136）、本 Step の完了条件として exit 0 を必須とする。FAIL 時は不足が報告されたフォルダの子スキルへ差し戻し、拡張マニフェストの永続先パス指定を確認する。

**完了**: 実在種別の一覧HTMLがすべて存在し、画面一覧が存在する場合は永続 screen_manifest_path / screen_manifest_ext_path が実在して両方とも検証済み。`check-manifest-persistence.sh <output_dir>` が exit 0。

## Step 3-2: 対象外種別と派生一覧を確定する

- global_step: 10
- tool: Write / Edit / Skill
- condition: Step 3-1 完了時

unit_kinds_present に含まれない種別を excluded-kinds.json と「該当なし」文書へ記録する。`<output_dir>/一覧/画面一覧/screen-manifest.json`（raw画面正本）が存在する場合のみ generating-feature-list-for-reverse-docs を source_dir・output_dir（・任意で survey_doc_path）で起動する。raw画面正本が存在しない場合は機能一覧をスキップし、画面一覧の正本確立後に本Stepを再実行する。生成結果の空判定で対象外を再評価しない。画面一覧HTMLが存在するのに `一覧/機能一覧/機能一覧.html` が不在の場合、状態判定の16状態には追加せず本Stepを再実行して補完する（派生一覧は16状態の判定フローの対象外）。

**完了**: 6種別の生成済み/対象外が復元可能で、生成可能な機能一覧が存在する。

## Step 3-3: マトリクスと対応表を生成する

- global_step: 11
- tool: Skill
- condition: 画面一覧とAPI一覧が存在する場合のみ

機能一覧確立後、`<output_dir>/一覧/画面一覧/screen-manifest.json`・同`screen-manifest.ext.json`・`<output_dir>/一覧/API一覧/API一覧.html`がすべて存在する場合のみ generating-cross-views-for-reverse-docs を target_repo_path・output_dir（・任意で portal_output_dir・sites_path・site_key）で起動し、生成可能なマトリクス・対応表4ページとAI設定資産ページを生成する。いずれか不在の場合はスキップし、raw・raw由来ext・API一覧の確立後に再実行する。既知の permission-function データ形状ギャップは skipped_pages として保持する。画面一覧HTML・API一覧HTMLが両方存在するのにマトリクス・対応表・AI設定資産ページが1つも存在しない場合は本Stepを再実行して補完する（派生補完は16状態の判定フローの対象外）。

**完了**: 生成可能な派生補完が存在し、未生成は理由付きで記録されている。

## Phase 4: 共通採録とポータル

global_step 13 は規約4種の採録工程の撤去により欠番。

## Step 4-1: 共通文書の層化サンプルを確定する

- global_step: 12
- tool: Skill
- condition: 共通未採録または common-docs-append のとき実行

survey_doc_path を渡して generating-reverse-common-docs をこのブロックで1回だけ起動する。初回は mode=v0、共通文書欠落の差し戻しは mode=append と append_findings を使う。返却ブロックと機械証拠を保持し、global Step 14〜15は同じ起動結果を検収する。

**完了**: 採録対象の層化サンプルが確定している。

## Step 4-2: 共通設計文書を採録する

- global_step: 14
- tool: Read
- condition: Step 4-1 通過時、または common-docs-append の戻り先

global Step 12の同一起動が生成した共通設計書・メッセージ定義書・DESIGN.mdをReadで検収し、append時は指摘対象だけが追記された証拠を確認する。

**完了**: common_docs_root 配下の必須文書が生成済み。

## Step 4-3: 共通文書ゲートとv0確定を検収する

- global_step: 15
- tool: Read / TaskUpdate
- condition: Step 4-2 完了時

global Step 12の同一起動が返した機械ゲート証拠とstatus=採録v0確定または追記完了を検収し、common_docs_root を保持する。

**完了**: common_docs_root が確定している。

## Step 4-4: ポータルと任意基盤ページを確定する

- global_step: 16
- tool: Skill / Bash
- condition: 共通採録完了後

- conditional_step_id: screen-batch-route

必要なら surveying-local-environment と counting-code-lines を起動し、Bashで shared/scripts/build-portal.sh を実行する。

```bash
bash shared/scripts/build-portal.sh \
  "$target_repo_path" \
  "$output_dir" \
  "$output_dir" \
  --catalog shared/references/portal-catalog.json
```

ポータルは納品物ルート（output_dir）直下の `index.html` として出力する（正本レイアウト。`references/contract.md` の「納品物ルート（output_dir）の正本レイアウト」参照）。カテゴリ、カード、探索条件、件数単位は `shared/references/portal-catalog.json` から導出する。カテゴリや成果物種別を追加する場合は、`build-portal.sh` へ分岐を足さず catalog へ blueprint を登録する。画面manifestから派生物を一括再生成する工程では、同じ catalog に加えて `--portal-only`・`--generated-at`・`--screen-manifest` を渡し、複数サイトでは `--sites`・`--site-key` も保持して、既存成果物を再変換せず `index.html` だけを更新する。サイトが2件以上あり `<納品ルート>/sites.json` が不在なら、統括スキル自身が `sites.json` を書き出す。`target_repo_path` が本来のプロジェクトではなく検証用の複製（worktree等の一時ディレクトリ）を指す場合は、`--project-name <本来のプロジェクト名>` を明示指定し、複製のディレクトリ名がタイトル・ブランド名・見出し・フッターへ混入することを防ぐ。

データ源が揃う任意基盤ページだけ対応スキルで生成し、ポータルを再生成する。

- generating-tech-stack-for-reverse-docs（アーキテクチャ調査書 §2 が確定済みのとき）
- generating-env-guide-for-reverse-docs（アーキテクチャ調査書 §3 が確定済みのとき）
- generating-screen-transition-for-reverse-docs（raw画面正本とraw由来extが確定済みのとき）
- generating-er-diagram-for-reverse-docs（テーブル一覧.html が確定済みのとき）
- generating-glossary-for-reverse-docs（互換入口。`proposal_output_ref` が対象repo外の絶対パスとして明示されたときだけ、`detected` 状態の提案YAMLとdiagnosticsを生成して `NEEDS_REVIEW` で停止する。用語辞書・HTML・承認済みYAMLは生成しない）
- managing-semantic-glossary（`approved_glossary_ref` がschema検証済みかつ承認済みのときだけ、portal publishとして `一覧/用語辞書/用語辞書.html` を生成する）

対象画面が4件以上なら running-reverse-screen-batch に global Step 17〜30の実行を委譲し、3件以下は本スキルが同じglobal Stepを逐次仲介する。条件分岐は新しいPhase番号を作らない。

**完了**: index.html と生成対象ページが存在し、screen-batch-route の選択と理由が記録されている。

## Phase 5: 静的ユニット処理

## Step 5-1: 対象ユニットと著述モードを確定する

- global_step: 17
- tool: Read / Bash
- condition: screen種別は本Step以降のfacts工程へ進む。api種別はfacts工程を経由せず原本読解型のStep 5-13（API詳細設計著述）へ分岐する。table・batch・report・external の4種別は設計書生成スキルが実在しないため「後続未対応」で終端する

対象画面IDを一覧マニフェストで検証し、`target_file_paths` の合計行数とファイル数を実測して authoring_mode を決定する（合計1,500行超または4ファイル超なら `large-two-pass`、それ以外は `standard`）。画面未開通は静的処理の阻害条件にしない。通常の画面ループは `facts_profile=auto|screen` のどちらでも常に `profile=screen` を渡し、対象ファイルが全件 `.py` でも python へ自動変更しない。`facts_profile=python` は global Step 2 の明示Python facts-only経路で終端済みのため本ループへ到達しない。スキャフォールディングは事実封印完了（facts_ref確定）後に1回だけ実施し（`bash <scaffold_script_path> <output_dir> <画面ID> [<画面名>]` を画面ディレクトリ未存在時のみ実行。既存の場合は `--verify` のみで健全性確認する）、facts抽出より前へ移動してはならない。

**完了**: 対象ユニット・対象ファイル・著述モードが確定している。

## Step 5-2: factsを抽出する

- global_step: 18
- tool: Skill
- condition: 事実未封印時

extracting-unit-facts-from-code を profile=screen と必要args全量で、このブロックでは1回だけ起動する。原本コードからfactsを抽出させ、返却ブロックと再計数・封印・再現性の機械証拠を保持する。global Step 19〜21は同じ起動結果を検収し、部分起動modeのない子スキルを再起動しない。

**完了**: facts_ref が返却候補として生成済み。

## Step 5-3: factsを独立再計数する

- global_step: 19
- tool: Read
- condition: Step 5-2 完了時

global Step 18の同一起動が返した独立再計数ゲートの終了コードと突合結果をReadで検収する。

**完了**: 再計数ゲートがPASSしている。

## Step 5-4: factsを封印する

- global_step: 20
- tool: Read
- condition: Step 5-3 PASS時

global Step 18の同一起動が返したfacts.lockの実在・ハッシュ・status=封印済みをReadで検収する。

**完了**: status=封印済み と facts_ref を受領している。

## Step 5-5: factsの再現性を検証する

- global_step: 21
- tool: Read
- condition: Step 5-4 完了時

global Step 18の同一起動が返した決定的再現性検査のPASS証拠をReadで検収する。

**完了**: 再現性検証がPASSしている。

## Step 5-6: 基本設計テンプレートとfactsを読み込む

- global_step: 22
- tool: Read / Bash
- condition: facts_ref と common_docs_root 確定後

画面ディレクトリを1回だけscaffoldまたはverifyし、generating-reverse-basic-designへ渡すテンプレート・facts・共通文書のargsを準備する。このStepでは子スキルを起動しない。

**完了**: 基本設計著述の入力が検収済み。

## Step 5-7: factsを業務語彙へ転記する

- global_step: 23
- tool: Skill / Agent
- condition: standardは詳細設計と並列、large-two-passは詳細設計パス1後

準備済みargsでgenerating-reverse-basic-designをこのブロックで1回だけ起動する。standardはdetailedと同時起動し、large-two-passはdetail-onlyの開始証跡を受領してからbasicのlarge-pass2を起動する。

**完了**: 基本設計著述完了を受領している。

## Step 5-8: 基本設計の実装用語混入を検査する

- global_step: 24
- tool: Read
- condition: Step 5-7 完了時

global Step 23の同一起動が返した実装用語混入検査の終了コード、基本設計書パス、status=基本設計著述完了をReadで検収する。

**完了**: 基本設計の機械ゲートがPASSしている。

## Step 5-9: 詳細設計用の封印済みfactsを検収する

- global_step: 25
- tool: Read
- condition: facts_ref と common_docs_root 確定後

generating-reverse-detailed-designへ渡す封印検証・章マップ・監査スクリプト・著述モードのargsを準備する。このStepでは子スキルを起動しない。

**完了**: 詳細設計著述の入力と封印状態が検収済み。

## Step 5-10: 詳細設計と周辺文書を著述する

- global_step: 26
- tool: Skill / Agent
- condition: authoring_modeに従う

準備済みargsでgenerating-reverse-detailed-designを起動する。standardはauthoring_pass=fullで1回だけ起動する。large-two-passはauthoring_pass=detail-onlyを1回起動してDETAIL_AUTHOREDと開始証跡を検収し、その証跡を渡してauthoring_pass=companion-docsを別のSkill/Agentとして2回目に起動する。2回目はbasicのlarge-pass2と並列化できるが、パス1返却前の起動は禁止する。

**完了**: 詳細設計と周辺文書の生成パスが返却候補として存在する。

## Step 5-11: 詳細設計の完全性とgold標準を検査する

- global_step: 27
- tool: Read / Bash
- condition: Step 5-10 完了時。gold標準不在は理由付きスキップ

global Step 26の該当起動（standardはfull、large-two-passはdetail-onlyとcompanion-docs）が返した完全性ゲート証拠をReadで検収し、gold標準が存在する場合だけ backtest-facts-against-gold.sh と check-doc-coverage-against-gold.sh を実行する。ゲート検収だけを目的とした再起動はしない。

**完了**: 必須ゲートがPASSし、gold標準の実行結果またはスキップ理由が記録済み。

## Step 5-12: 静的完了を確定する

- global_step: 28
- tool: Write / TaskUpdate
- condition: Step 5-7とStep 5-10の合流条件を満たした時

- conditional_step_id: docs-only-terminal

global Step 26の該当起動から、standardは最終返却status=AUTHORED、large-two-passはパス1のDETAIL_AUTHOREDとパス2のCOMPANION_AUTHOREDの双方を受領して合流条件を検収する。

**静的完了ゲート**: 続いて、永続 `screen_manifest_path=<output_dir>/一覧/画面一覧/screen-manifest.json` を直接解決し、validate-manifest.sh 通過を確認する。旧成果物の明示的な移行・復元で screen_manifest_path を作成する場合だけ、global Step 9 の復元経路を先に完了させる。output-layout の物理配置キー `layout.screenUnitRoot` を解決し、正本rawから `extract-screen-metadata.sh <screen_manifest_path> <source_dir> <screen_manifest_ext_path> --design-docs-dir <output_dir>/<screenUnitRoot> --link-base-dir <output_dir>/一覧/画面一覧` を再実行し、`build-unit-list.sh <screen_manifest_ext_path> <output_dir>/一覧/画面一覧/画面一覧.html --unit-kind screen --portal-dir <output_dir>` で画面一覧を必ず再生成する。表示用 `kindLabels.screen` はpathに使わない。再実行時は固定した generated_at と raw の正規化SHA-256をそれぞれ `--generated-at`・`--manifest-content-hash` へ必ず渡し、ext の `manifestContentHash` 一致も静的完了条件に含める。raw検証・メタデータ付与・再生成のいずれかが失敗した場合は静的完了を宣言しない。再生成後、当該画面の実在成果物だけに4リンクが付与され、確定画面名がある場合は `confirmedScreenName` が表示源へ反映され、マニフェスト登録件数と表行数が一致することを検収する。

この後でのみ画面レジストリの当該エントリを作成または更新して status=authored とする。その後にURLの有無にかかわらず `verification_mode` を評価する。docs-onlyはここで「静的リバース完了」として終端し、global Step 29〜30を起動しない。single-pass|iterativeだけ動的検証へ進む。

**完了**: facts・基本設計・詳細設計が完成し、docs-only終端または動的検証への分岐が確定している。

## Step 5-13: API詳細設計の著述

- global_step: 31
- tool: Skill
- condition: unit_kind=api。画面ループの外・画面バッチへの委譲の外で、全画面の処理が終わったあとに1回だけ実行する。`verification_mode` に依存せず、docs-onlyでも実行する

global Step 9（API一覧の確立）が完了していることを前提に、generating-api-detail-design-for-reverse-docs を起動する。API一覧マニフェスト（`一覧/API一覧/api-manifest.ext.json`）に載るAPI1本ごとにAPI詳細設計書.mdを生成する。本Stepはfacts工程を経由しない原本読解型であり、往復検証の対象にはならない。

**完了**: API一覧に載る全APIについてAPI詳細設計書.mdが生成されている。APIが0件の場合は生成せず完了とする。

## Step 5-14: 機能設計の著述

- global_step: 32
- tool: Skill
- condition: unit_kind=feature。画面ループの外・画面バッチへの委譲の外で、Step 5-13のあとに1回だけ実行する。`verification_mode` に依存せず、docs-onlyでも実行する

global Step 10（機能一覧の確立）とStep 5-12（画面詳細設計）・Step 5-13（API詳細設計）が先に完了していることを前提に、generating-feature-design-for-reverse-docs を起動する。機能一覧マニフェスト（`一覧/機能一覧/feature-manifest.json`）に載る機能1件ごとに機能設計書.mdを生成する。機能設計書は構成要素の設計書をパスで参照する集約設計書のため、参照先が実在する状態で実行する。機能は派生一覧であり `unit_kinds_present` の判定対象外である。種別ループには載せず、機能一覧の確立を前提に単独で起動する。

**完了**: 機能一覧に載る全機能について機能設計書.mdが生成されている。機能が0件の場合は生成せず完了とする。

## Phase 6: 動的往復検証

## Step 6-1: 開通から比較結果取得までを依存順に実行する

- global_step: 29
- tool: AskUserQuestion / Skill
- condition: verification_mode=single-pass|iterative

実レンダリング確認済みURLが無ければ unlocking-reverse-target-screens を dynamic-only で起動する。次に syncing-reverse-env(mode=setup) でenv_blockを取得し、承認後に rebuilding-screen-unit-from-docs でファイル単位検証を行う。続けて syncing-reverse-env(mode=sync) でbaseline_tagを確立し、rebuilding-code-from-docs(mode=implement)のcompare_requestを受領し、syncing-reverse-env(mode=sync,dry-run)の比較結果全文を保持する。順序は unlock → setup → file verify → baseline sync → implement → compare で固定する。

**完了**: compare_result全文とfreeze_commitが揃うか、静的成果物を保持した動的検証保留理由が確定している。

## Phase 7: 判定と確定

## Step 7-1: judgeして基準更新または差し戻しを確定する

- global_step: 30
- tool: Skill / AskUserQuestion / TaskCreate
- condition: Step 6-1でcompare_result取得済み

rebuilding-code-from-docs(mode=judge)へcompare_result全文とfreeze_commitを渡す。PASS時は承認後に syncing-reverse-env(mode=sync)で基準タグを本番更新し、依頼時だけteardownする。FAIL時はNG帰着3系統へ分類し、single-passは改善候補を報告して停止、iterativeだけ下記back-edge metadataに従って戻す。

**完了**: PASS・FAIL・動的検証保留のいずれかが確定し、PASS時は基準更新または依頼時teardownが完了している。

## 条件分岐メタデータ

各 conditional_step_id（screen-batch-route・docs-only-terminal・dynamic-route）の判定Step・条件・実行経路の対応表は `references/operations.md` の「条件分岐メタデータ」節を正本とする。宣言自体は各Stepブロックの `conditional_step_id` 行に本文として存在する。

## Back-edgeメタデータ

各 back_edge_id（architecture-revise・facts-reextract・detail-rewrite・common-docs-append・dynamic-retry）の戻り先global Step・条件・上限・停止条件の対応表は `references/operations.md` の「Back-edgeメタデータ」節を正本とする。back-edgeは通常順序を上書きする唯一の例外であり、戻り先・条件・上限をprogress.jsonlとTaskCreateへ記録し、暗黙の「前工程へ戻る」表現を禁止する。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | `auto\|screen` は対象パス・出力先・画面範囲・実行モードが、`python` は target_repo_path・output_dir・target_file_paths・facts_unit_id・verification_dir・実行モードが確定し、状態キーの確定と TaskCreate 登録が済んでいる（`python` は明示Python facts-only経路で終端する） |
| Phase 2 | survey_doc_path と unit_kinds_present が確定している |
| Phase 3 | 6種別の生成済み/対象外と、生成可能な派生一覧・対応表が確定している |
| Phase 4 | common_docs_root、ポータル、任意ページの生成/スキップ理由、画面バッチ経路が確定している |
| Phase 5 | facts・基本設計・詳細設計が完成し、`docs-only` は静的リバース完了として終端している |
| Phase 6 | 動的検証ありでは compare_result と freeze_commit が取得済み、または動的検証保留理由が確定している |
| Phase 7 | 動的検証ありでは PASS / FAIL / 動的検証保留が確定し、PASS時は基準更新または依頼時teardownが完了している |
| **Goal** | `docs-only` は全対象画面の facts・基本設計・詳細設計が完成。動的検証ありは PASS、NG分類済み、または「静的リバース完了・動的検証保留」が確定。いずれも最終報告フォーマットの必須フィールドを含む |

## 運用契約の詳細
Phase 1 の開始前に Read で `references/operations.md` を全文読み込み、最終報告3表・サブエージェント委任・タスク一覧・ループ・設計判断を適用する。工程順序や子スキル責務は本体と `contract.md` を正とし、運用詳細側で重複定義しない。

## 重要な注意事項

子スキル起動の対話ゼロ契約・破壊的操作の承認委譲・output_dir null時の展開先確認・単独起動可能性・Skill起動の必須化（直接実行の禁止）の5項目は `references/operations.md` の「重要な注意事項」節を正本とする。

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
- 共有資産（本スキル専有ではなくリポジトリ共通、`<reverse_docs_root>/shared/` 配下）: `shared/templates/リバース検証/`（テンプレート一式）、`shared/scripts/audit-consistency.sh`（工程間ゲート）、`shared/scripts/scaffold-screen.sh`（画面ディレクトリのテンプレート展開。正本はこの1本のみ）、`shared/scripts/seal-facts.sh`（facts封印・検証）、`shared/references/chapter-map.md`（章役割キー対応表）、`shared/references/facts-schema.md`（facts.ymlスキーマ正本）、`shared/references/リバース工程設計.md`（Phase/Step×スキル対応の正本）。各子スキルへは template_root / audit_script_path / scaffold_script_path / chapter_map_path として絶対パスを渡す
- 画面レジストリ: `<output_dir>/一覧/reverse-screen-registry.yml`（正本定義は references/contract.md）
- `unlocking-reverse-target-screens/manifest.yml` — 同スキルが管理するプロジェクト固有値の正本（本スキルは関知しない）

## 完了報告
`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（作業報告型）に従う。

固有の検証行:
- 通過 Phase 数・最終状態キーの確定

## 設計判断
詳細な設計判断は Read 済みの `references/operations.md` を参照する。
