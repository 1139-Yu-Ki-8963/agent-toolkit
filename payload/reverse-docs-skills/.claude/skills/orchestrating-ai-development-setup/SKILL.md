---
name: orchestrating-ai-development-setup
日本語名: 検証工程全体の統括
description: 対象コードと実行範囲を入力に、調査・事実取り出し・設計書作成から再構築・実装照合・基準確立までを指定に応じて統括し、選んだ工程の結果を確定する。
invocation: orchestrating-ai-development-setup
type: orchestration
allowed-tools: [Agent, AskUserQuestion, Bash, Edit, Glob, Read, Skill, TaskCreate, TaskUpdate, Write]
---

## いつ使うか

元のコードと設計書を照合する検証の進行や工程全体の統括、画面一覧から基準を確立するまでを行いたい時に使う。

## いつ使わないか

個別工程だけを単体で実行したい時は使わない。

# 正本: reverse-docs-skills

# リバース設計書往復検証オーケストレーションスキル

リバース設計書往復検証フローの進行係（管理者）。自分では検証・比較・実装を行わず、状態判定 → 子スキルを args 全量指定で Skill 起動 → 返却ブロックの status で確認 → 次工程決定、というループで工程全体を統括する。

子スキル群は互いを知らず、工程間の受け渡しはすべて本スキルが仲介する（完全仲介方式）。契約の定義と内訳は `references/contract.md` 冒頭の「子スキルの内訳」節を正本とする。

## 使用タイミング

- リバース検証を工程統括したいとき（アーキテクチャ調査から基準タグ確立までの一連の流れ）
- 個別工程だけを動かしたい場合は各子スキルを単独起動する（各子スキルは同じ args を手渡せば単独でも動く契約）

## 起動引数

型・既定値の詳細な記法は `references/contract.md` の「args 仕様」節（子スキルへ渡す際の入力契約）を先に読むと、以下の表が読みやすい。

| 引数 | 必須 | 内容 |
|---|---|---|
| reverse_docs_root | 必須 | 配布されたreverse-docs-skillsルートの絶対パス。統括が実在確認して解決し、共有スクリプト・テンプレート・契約を使う全子スキルへ渡す |
| target_repo_path | 必須 | リバース対象プロジェクトの絶対パス。全工程・全子スキルへ渡す入力の正 |
| output_dir | 必須 | 納品物ルートの絶対パス。ポータル・一覧・設計書等すべての出力先の正（「納品物ルート（output_dir）の正本レイアウト」参照） |
| screen_scope | `facts_profile=auto|screen`時必須（`python`時は不要。画面範囲を問わないため）。両方を同時に指定した場合も、`facts_profile`が経路を先に確定するため screen_scope の値は参照されない（`python`は明示Python facts-only経路へ進み画面範囲を扱わない） | 対象画面範囲（全画面／個別画面ID列挙等）。種別ループ・画面状態判定の起点 |
| verification_dir | 任意（既定値なし） | プロジェクト内に `verification/` を作らない（このリポジトリ自身の開発構想文書が定める「検証出力の外部化」）。未指定の場合は推測せず `OUTPUT_PATH_REQUIRED` で中断する（`headless` の値によらず対話では確認しない。起動時に `target_repo_path` の外にある絶対パスを明示指定する）。facts・再計数・確定記録・修正指示書・最終報告・テストログの出力先。「プロジェクトの外」という指定だけでは、実行環境のグローバルな実装フローゲート（`${HOME}/Projects/` 配下全体を監視する）を回避できないため、`${HOME}/Projects/` の外にある絶対パスを明示的に必須とすることで、このゲートとの衝突を構造的に避けている |
| template_root | 任意 | 既定 `<reverse_docs_root>/delivery-payload/templates/リバース検証/`（`delivery-payload/templates/リバース検証/` 配下のテンプレート一式。「共有資産」節参照）。テンプレート一式を使う全子スキルへ絶対パスとして渡す |
| survey_doc_path | 任意 | 既定候補 `<output_dir>/<commonRoot>/アーキテクチャ調査書.md`（`commonRoot` は output-layout の物理配置キー）。候補が不在、または調査ゲート不合格の場合は surveying-architecture-for-reverse-docs を起動し、返却 `status=調査確定` の `artifacts[0]` を確定値として採用する（Step 3 参照） |
| headless | 任意（既定 false） | true の場合、無人モードで実行する。AskUserQuestion を発行せず、破壊的操作の承認は起動時に一括付与済みとして扱う |
| verification_mode | 任意（既定 `single-pass`） | `docs-only` は facts 抽出・基本設計・詳細設計まで、`single-pass` は動的検証を1回実行、`iterative` は FAIL 後の改善反復も行う |
| facts_profile | 任意（既定 `auto`） | `auto|screen|python`。`auto|screen`は通常の画面フローを`profile=screen`で実行する。`python`は明示指定時だけ、画面一覧・画面状態判定へ入る前のfacts-only経路を実行して終端する |
| target_file_paths | `facts_profile=python`時必須 | Python facts-only経路で抽出する、`target_repo_path`からの相対`.py`パス配列。全件`.py`でなければ中断する |
| facts_unit_id | `facts_profile=python`時必須 | Python facts-only出力を識別する論理ID。画面IDではなく、`<verification_dir>/screen-<facts_unit_id>/facts/<run_id>/`の識別子としてだけ使う |
| proposal_output_ref | 用語候補生成を要求する場合のみ必須 | `target_repo_path` の外にある、明示的な絶対 `.yaml` / `.yml` パス。省略・対象repo内・相対パスなら候補生成を開始しない。推測補完は禁止 |
| approved_glossary_ref | 承認済み用語ページを生成する場合のみ必須 | schema検証済みかつ承認済みの用語YAMLへの絶対パス。候補proposalを直接指定してはならない |

無人モード（headless=true）の詳細仕様（置き換え表・原本を見ない分離の必須要件・安全設計・実行レポートの置き場・前提事実）は `references/contract.md` の「無人モード仕様」節を正本とする。無人モード（headless=true）では工程の開始・完了のたびに `<verification_dir>/progress.jsonl` へ JSON 行を追記する（形式: `{"ts":"<ISO8601>","screen_id":"<画面ID>","phase":"<工程名>","status":"started|completed|failed"}`）。呼び出し元セッションや人間はこのファイルの監視で現在工程を把握できる。

## 基本ワークフロー

成果物の実在から現在の状態を判定し、次に起動する子スキルを機械的に決定する。状態一覧（16状態）の実在判定基準・args・返却フィールドの定義は `references/contract.md` の状態判定表を正本とする。

**状態判定の採用元**: `references/contract.md` の状態判定表は判定根拠の説明である。`scripts/resolve-flow-state.sh` は本スキルフォルダからの相対パスで参照する。本スキルフォルダは `.claude/skills/orchestrating-ai-development-setup/`（このSKILL.mdと同じ階層）を指す。下記コマンドは同フォルダを作業ディレクトリとして実行する。実際の状態判定は `bash scripts/resolve-flow-state.sh <output_dir> [<target_repo_path>] --screen-id <画面ID> [--system <システム名>] [--reverse-worktree <reverse_worktree>] [--target-file <対象ファイルbasename>]` を実行し、標準出力の状態キー1行をそのまま採用する（自然文の自己申告に代える機械判定）。空文字や未定義の状態キーは返さず、判定不能時は「未判定」を返す。「未判定」を受け取った場合は screen_id の解決状況（画面一覧マニフェストの実在・`--screen-id` 指定漏れ）を確認してから再実行する。

複数サイトの場合、`references/contract.md` の状態判定表にある `<output_dir>` は「当該サイトのサイトルート」と読み替える。

画面開通は facts 抽出・基本設計・詳細設計の前提条件ではない。原本コードと確定済み facts から静的リバースを先に完了し、画面開通はファイル単位検証・基準確立・往復検証へ進む直前にだけ要求する。開通できない場合も静的成果物は破棄せず「静的リバース完了・動的検証保留」として報告する。

ファイル単位未検証が `status=差し戻し` を返した場合、`verification_mode=iterative` のときだけ設計書未著述へ戻す。`single-pass` では差し戻し理由を記録して停止し、`docs-only` ではファイル単位検証自体を起動しない。アーキ未調査・共通未書き起こしはプロジェクト単位で1回だけ確定させればよく、画面ごとに繰り返さない。

## 実行手順

グローバル順序の正本は `delivery-payload/references/リバース工程設計.md` の Phase 1〜7 / global Step 1〜41 とする。本節の見出しは `Step <親Phase>-<Phase内連番>`、直下の `global_step` は全体で一意な実行順を表す。英字接尾辞・Phase 0・Step 0・重複番号は使用しない。

## 条件分岐メタデータ

条件分岐は新しいPhase・Step番号を増やさず、既存Stepの実行経路として表現する。詳細は正本（`delivery-payload/references/リバース工程設計.md`）の同名節を参照する。

| conditional_step_id | 判定Step | 条件 | 実行経路 |
|---|---:|---|---|
| screen-batch-route | Step 16 | 対象画面4件以上 | running-reverse-screen-batchへStep 17〜28・40〜41を委譲 |
| screen-batch-route | Step 16 | 対象画面3件以下 | 統括がStep 17〜28・40〜41を逐次仲介 |
| docs-only-terminal | Step 28 | verification_mode=docs-only | Step 29〜39の完了後、静的完了で終端しStep 40〜41を起動しない |
| dynamic-route | Step 28 | verification_mode=single-passまたはiterative | Step 29〜39を経てStep 40へ進む |

## Back-edgeメタデータ

反復は暗黙の「前工程へ戻る」ではなく、戻り先・条件・上限を次の意味語IDで記録する。global Step番号で記載し、正本（`delivery-payload/references/リバース工程設計.md`）の同名節とデータ行が完全一致する。列名も正本と同一の `from_step` / `to_step` を使う。

| back_edge_id | from_step | to_step | 条件 | 上限 | 停止条件 |
|---|---:|---:|---|---:|---|
| architecture-revise | 8 | 5 | 下流が検出手がかり不足を決定的に報告 | 3 | 調査ゲートPASS / 同一FAIL 2連続 |
| facts-reextract | 40 | 18 | iterativeかつファイル検証がfacts欠落へ分類 | 5 | 再現一致 / 5回到達 |
| detail-rewrite | 40 | 26 | iterativeかつファイル検証が著述不足へ分類 | 5 | 再現一致 / 5回到達 |
| common-docs-append | 41 | 14 | iterativeかつjudge FAILが共通文書欠落 | 3 | judge PASS / 同一差分2連続 |
| dynamic-retry | 41 | 40 | iterativeかつ再比較可能な一時FAIL | 3 | judge PASS / 同一差分2連続 |

## Phase 1: 準備

対話による確認は行わない。選択したprofileの必須引数が起動引数として不足していれば、値を推測せず中断する。`facts_profile=auto|screen`はtarget_repo_path・output_dir・screen_scopeが、`facts_profile=python`はtarget_repo_path・output_dir・target_file_paths・facts_unit_id・verification_dirが、いずれも起動引数として指定済みであることを要求する。Python経路ではscreen_scopeを要求せず、起動引数の確認完了後は Step 1-2 の明示Python facts-only経路へ分岐する。通常の画面フローだけが global Step 3 以降へ直行する。

## Step 1-1: 対象リポジトリと出力先を解決する

- global_step: 1
- tool: Read / Glob / TaskCreate
- condition: 常に実行

起動引数からprofileに応じた必須項目を確定する。`facts_profile`は起動引数として指定するか、未指定なら既定値`auto`を採用する（対話では選ばせない）。`facts_profile=auto|screen`では対象プロジェクトパス・出力先パス・画面範囲・実行モードの4項目が起動引数としてすべて指定済みであることを要求する。

起動引数の `reverse_docs_root`・`target_repo_path`・`output_dir`・`screen_scope` を解決する。`reverse_docs_root` は配布rootの絶対パスとして実在確認し、固定インストール先を仮定しない。いずれか1つでも未指定なら、不足している項目名を一覧で示して ERROR として終端する。`headless` の値によらず、値を推測せず対話でも補わない。成果物の実在から16状態を順に判定し、実行対象の global Step を TaskCreate で先出し登録する。

### 入口モードを判定する

target_repo_path が確定した直後に `bash scripts/resolve-flow-mode.sh <target_repo_path>` を実行する。サイト定義が既にある場合は `--output-dir <output_dir>` を付けて既存資産を優先させる。標準出力は `{"mode": ..., "reason": ..., "evidence": {...}, "sites": [...]}` 形式のJSON1件である。トップレベルの `.mode` フィールドの値（`setup-only|reverse-full|reverse-degraded`）をそのまま採用する。読み取りには `jq -r '.mode'` を使う。判定はサブプロジェクト単位でも行う。返却JSONの `sites` が2件以上ある場合、各要素の `.mode` がサイトごとの値であり、「サイトごとのループ（モノレポ・複数サイト時）」はサイトごとに確定したモードへ従う。

| モード | 動作 |
|---|---|
| setup-only | 下記「規約配布とAI設定資産生成の手順」を実行する。完了したら「セットアップ完了」として本フローを終端し、global Step 2以降（アーキテクチャ調査以下のリバース工程）へは進まない |
| reverse-degraded | 下記「規約配布とAI設定資産生成の手順」を先に実行したうえで、screen_scope を確認せずに進む。Step 5-1 の「screen種別はfacts工程へ、api種別はStep 5-13/5-15へ、table・batch・report・externalの4種別はStep 5-16〜5-23へ分岐する」という既存条件がそのまま画面依存工程を素通りさせ、Step 3-2 の excluded-kinds.json 記録とポータルの `disabledWhenEmpty` が画面カードを選べない状態で表示する。具体的には、screenがunit_kinds_presentに含まれないためStep 3-1は画面一覧（screen-manifest.json）を生成せず、Step 5-1以降の画面ループは対象画面0件のまま実行されない。画面に紐づくfacts抽出・基本設計・詳細設計（Step 5-2〜5-12）は着手されず、api・table・batch・report・externalの各種別はunit_kinds_presentに含まれる限りStep 5-13以降で通常どおり著述される。global Step 2以降は現行どおり進める |
| reverse-full | 下記「規約配布とAI設定資産生成の手順」を先に実行したうえで、global Step 2以降を現行どおり進める |

### 規約配布とAI設定資産生成の手順

3モードいずれも、入口モード確定直後にこの手順を1回だけ実行する。次の4手順をこの順序で実行する。手順1〜3の順序を逆にする、または省略すると `AGENTS.md` の `RULES-INDEX` マーカーを手順3が検出できない。この場合、規約索引や前半索引（目的・技術スタック等）が生成されない。手順4は手順1が配置した `docs/rules/` の実体を読むため、手順1より後に実行する。

1. `bash <reverse_docs_root>/generation-engine/scripts/rules/scaffold-rule-definitions.sh <target_repo_path> --apply --with-skills` で規約定義一式（`docs/rules/` の親7・子27）と納品スキル2本を対象リポジトリへ配る。既存の `docs/rules/**/rule.md` は上書きしない
2. `generating-agent-config-index-from-repo` を `target_repo_path`・`template_root=<reverse_docs_root>/delivery-payload/templates/ai-assets/`・`output_dir=<target_repo_path>` で起動し、`AGENTS.md`・`CLAUDE.md` へ前半索引（目的・技術スタック・実行コマンド等の事実）と、`RULES-INDEX` マーカーを含むテンプレートを複製する。手順3より前に実行しなければ、手順3が新規作成する `AGENTS.md` は前半索引を持たない
3. `bash <reverse_docs_root>/generation-engine/scripts/rules/build-derived-rules.sh <target_repo_path>/docs/rules <target_repo_path> --apply` で各AIツール設定（`.claude`・`.cursor`・`.codex`）を生成し、手順2が置いた `RULES-INDEX` マーカーの範囲を規約索引で埋める
4. `bash <reverse_docs_root>/generation-engine/scripts/rules/build-rule-flow-map.sh` で規約とフローの対応ページを生成する。第1引数は `rule-taxonomy.json`、第2引数は出力先（`<output_dir>/project-portal/foundation/規約とフローの対応.html`）とする。`--target-root <target_repo_path>` も渡す。`--target-root` は手順1が配置済みの `docs/rules/` の実体を読み、分類定義にあるが対象プロジェクトへ未配置の子カテゴリを索引から除く。

4つの呼び出しはいずれも絶対パス指定であり、スクリプト・スキル自身が自分の位置から依存ファイルを解決するため、作業ディレクトリはどこであってもよい。`docs/rules/` 配下の規約定義自体は `scaffold-rule-definitions.sh`（手順1）が生成する。この配布に合わせて、手順1は2ファイルも生成する。対象は `.claude/rules/always/project-context/` 配下の `flow-values.yml` と `rule.md` である。この2ファイルは実装フローのゲートが必須とし、既存保護つき（既存ファイルは上書きしない）で生成する。

`setup-only` の場合はここで本フローを終端し、以降の対象プロジェクトパス・出力先パス・画面範囲の確認へは進まない。

`facts_profile=python`では画面範囲を尋ねず、対象プロジェクトパス・出力先パス・実行モードに加えて以下の3項目を確定する:

| 項目 | 入力契約 | 既定値 |
|---|---|---|
| target_file_paths | `target_repo_path`からの相対`.py`パスの非空配列。全件の実在とリポジトリ内包を確認し、外部絶対パス・`..`・symlink脱出を拒否する | なし（必須） |
| facts_unit_id | facts出力を識別する論理ID。画面IDや実在画面ディレクトリを要求しない | なし（必須） |
| verification_dir | facts・再計数・確定記録の出力先 | 既定値なし。`target_repo_path` の外にある絶対パスを必須とする |

状態判定の冒頭で対象画面IDの実在を検証する。実在確認は永続raw正本（`<output_dir>/<manifestsRoot>/screen-manifest.json` の `screens[]` 配列）に対して行う（`manifestsRoot` は output-layout の物理配置キー。既定値 `docs/manifests`）。一覧外IDの場合は一覧へ `kind=route`・`route=""` として追記し、route空の未解決画面として工程を継続する（対話による確認は行わない。旧仕様が持っていたエラー終端の選択肢は廃止した）。画面レジストリの `verification_url` が未実施・エラーページ・プレースホルダの場合でも、facts 抽出・基本設計・詳細設計は続行する。実レンダリング確認済みURLは動的検証へ移る時点でのみ必須とする。

**完了**: `auto|screen`はtarget_repo_path・output_dir・screen_scope・実行モードが、`python`はtarget_repo_path・output_dir・target_file_paths・facts_unit_id・verification_dir・実行モードが確定し（`python`はscreen_scopeを要求しない）、現在状態の確定と実行対象タスクの登録が済んでいる。モードが `setup-only` の場合はここで「セットアップ完了」として終端している。

## Step 1-2: スコープと実行モードを確定する

- global_step: 2
- tool: Read
- condition: 常に実行

起動引数から `verification_mode=docs-only|single-pass|iterative`（既定 `single-pass`）、対象画面（screen_scope）、フル実行か個別スキル利用かを確定する。対話による確認は行わない。「複雑度層別サンプル」は既存の複雑度プロファイルから sampledScreenKeys の和集合を screen_ids に変換し、未生成なら画面一覧スキルのプロファイル工程を先行する。

- **フル実行（facts_profile=python）**: 確定したtarget_repo_path・output_dir・target_file_paths・facts_unit_id・verification_dirを使って後述の「明示Python facts-only経路」へ進む。global Step 3 以降へは進まない
- **フル実行（facts_profile=auto|screen）**: 確定したtarget_repo_path・output_dir・screen_scopeを使って global Step 3 以降を順に進行する
- **個別スキル利用**: 指定されたスキルを args 全量指定で単独起動し、完了をもって本フロー全体を終了する

### サイトを確定する（アーキテクチャ調査書 §10 が確定済みのとき）

本節と次節「サイトごとのループ」は `facts_profile=auto|screen` のフル実行にだけ適用する。`facts_profile=python` は前段の分岐で確定した時点で「明示Python facts-only経路」へ直接進む。global Step 3 以降へは進まないため、サイトのループが対象とする global Step 3〜16 には一度も入らず、本節・次節を評価しない。両方の条件が同時に成立することはなく、`facts_profile` の分岐が先に確定して以降の経路を一意に決める。

アーキテクチャ調査書 §10 のサイト一覧から対象サイトを確定する。単独プロジェクトならサイトは 1 件（キー `main`）。モノレポで 2 件以上ある場合も、対話による確認は行わず、§10 に列挙された全サイトを対象として確定する（一部サイトだけに絞りたい場合は `target_repo_path` に個別サイトのルートを指定して起動する。起動時に渡す引数の種類は増やさない）。§10 がまだ確定していない（初回起動でアーキ調査が未実施）場合は、global Step 7（調査確定の確認）直後にあらためて本段階を実行してから global Step 9 以降へ進む。

### サイトごとのループ（モノレポ・複数サイト時）

前段の「サイトを確定する」で複数サイトを対象に確定した場合、global Step 3〜16 を確定した対象サイトごとに繰り返す。各サイトのループでは `output_dir` を `<納品ルート>/<サイトのルートディレクトリ>` に差し替えて実行する。サイト間は独立しており、あるサイトの失敗が他サイトの成果物を壊すことはない。いずれかのサイトで中断した場合はそのまま停止し、以降のサイトへは進まない。次回起動時は状態判定がサイトごとに行われるため、未完了のサイトから自動的に再開される。サイトをまたぐ巻き戻しは行わない。

### 明示Python facts-only経路

- conditional_step_id: python-facts-only-route

`facts_profile=python`が明示された場合だけ、事前ヒアリング完了後かつ画面ID実在確認より前にこの経路へ分岐する。`target_repo_path`・`target_file_paths`・`facts_unit_id`・`verification_dir`を検証し、`target_file_paths`が非空かつ全件`.py`であることを確認する。論理パス`screen_dir=<verification_dir>/logical/<facts_unit_id>`を組み立てるが、そのディレクトリの実在や雛形の展開は要求しない。

facts抽出より先に`survey_doc_path`を解決する。起動引数のsurvey_doc_pathが実在しアーキテクチャ調査ゲートを通る場合はそれを使う。未指定なら`<output_dir>/<commonRoot>/アーキテクチャ調査書.md`を候補とし、候補が不在ならSkillでsurveying-architecture-for-reverse-docsをtarget_repo_path・output_dir・template_root・mode=surveyで起動する。候補が実在しても調査ゲートが不合格ならmode=revise・revise_findings付きで起動する。revise_findingsには、直前の`check-architecture-survey.sh`が標準エラーへ出力した検査別の失敗理由（`検査N失敗: ...`、最大7件）をそのまま用いる。返却`status=調査確定`のartifacts[0]をsurvey_doc_pathとして記録し、実在と調査ゲート通過を再確認する。この前処理は画面一覧・対象画面ID・画面状態を参照しない。

survey_doc_path確定後に限り、Skillでextracting-unit-facts-from-codeをtarget_repo_path・target_file_paths・上記screen_dir・verification_dir・profile=python・survey_doc_path・run_idで起動する。返却`status=封印済み`、`recount-report.txt`のexit 0相当結果、`facts.lock`の`seal-facts.sh verify`通過を確認し、「Python facts確定完了」で本フローを終端する。画面一覧生成・対象画面ID実在確認・画面雛形の展開・基本設計/詳細設計著述には進まない。

`facts_profile=auto|screen`はこの経路を通らず通常の画面フローへ進む。通常の画面フローでは対象ファイルの拡張子にかかわらず`profile=screen`を渡し、拡張子だけを根拠にpythonへ切り替えてはならない。

**完了**: 起動引数から実行モード（フル実行 / 個別スキル名）が確定し、対象サイト一覧（キー・ルートディレクトリ）も確定している（対話による確認は行わない）。`auto|screen`のフル実行は global Step 3 へ進める。`python`は明示Python facts-only経路でsurvey_doc_path確定後にfacts抽出・独立再計数・確定検証まで完了し、facts-only終端している。

## Phase 2: アーキテクチャ調査

## Step 2-1: 調査入力とテンプレートを確認する

- global_step: 3
- tool: Read / Skill
- condition: アーキ未調査または back_edge_id=architecture-revise のとき実行

surveying-architecture-for-reverse-docs へ target_repo_path・output_dir・template_root・mode を渡して、このブロックでは1回だけ起動する。既存調査書が無ければ mode=survey、下流の検出手がかり不足から戻った場合は mode=revise と revise_findings を渡す。返却ブロックと機械証拠を保持し、global Step 4〜7は同じ起動結果を順に確認する。部分起動modeがない子スキルをStepごとに再起動しない。

**完了**: 子スキルが調査に必要な入力を受理し、前提検査を通過している。

## Step 2-2: 決定的走査を実行する

- global_step: 4
- tool: Read
- condition: Step 2-1 通過時

global Step 3の同一起動が返した走査証拠から、技術スタック、ルーティング、6種別の検出根拠をReadで確認する。管理者は子スキルの走査手順を代行せず、再起動もしない。

**完了**: 走査結果が子スキルの返却候補へ含まれている。

## Step 2-3: アーキテクチャ調査書を著述する

- global_step: 5
- tool: Read
- condition: Step 2-2 通過時、または architecture-revise の戻り先

global Step 3の同一起動が生成した調査書をReadで確認する。revision では revise_findings の範囲だけが追記・修正され、既存の確定事実が保持されていることを確認する。

**完了**: survey_doc_path の候補が生成されている。

## Step 2-4: アーキテクチャ機械ゲートを実行する

- global_step: 6
- tool: Read
- condition: Step 2-3 完了時

global Step 3の同一起動が実行した check-architecture-survey.sh の終了コードと出力をReadで受領する。管理者の自然文判断で PASS を代替しない。

**完了**: 機械ゲートが PASS、または再修正に必要な決定的FAILが得られている。

## Step 2-5: 調査確定の返却を確認する

- global_step: 7
- tool: Read / TaskUpdate
- condition: Step 2-4 PASS時

global Step 3の同一起動から返された status=調査確定 と artifacts[0]=survey_doc_path を確認し、unit_kinds_present を保持する。status=中断は hint を報告して停止する。

**完了**: survey_doc_path と unit_kinds_present が確定し、global Step 9へ渡せる。

## Step 2-6: 検出手がかり不足を調査書へ差し戻す

- global_step: 8
- tool: TaskCreate / Skill
- condition: 下流がアーキテクチャ上の検出手がかり不足を決定的に報告した場合のみ

- back_edge_id: architecture-revise
- back_edge_target: global Step 5

revise_findings を固定し、Step 2-3へ戻す。既存タスクを巻き戻さず、差し戻しタスクを新規登録する。

**完了**: 戻り方向の依存 の理由・対象・上限が記録され、再調査が開始済みか停止判断済み。

## Step 2-7: 納品物の一覧を提示し対象範囲の承認を得る

- tool: Read / Write / AskUserQuestion
- condition: 常に実行

Step 2-5で確定した unit_kinds_present をもとに、excluded-kinds.json（`<output_dir>/<excludedKinds>`。`excludedKinds` は output-layout の物理配置キー。既定値 `docs/scope-and-progress/excluded-kinds.json`）を暫定生成する。allKindsは既定の6種別（screen・api・table・batch・report・external）とし、presentKindsはunit_kinds_present、excludedKindsはallKindsからpresentKindsを除いた各種別へアーキテクチャ調査書の判定理由を添えたものとする。スキーマ自体（generatedAt/surveyDocPath/allKinds/presentKinds/excludedKinds）は作り替えない。

続けて `bash generation-engine/scripts/build-deliverable-inventory.sh <output_dir> <output_dir>/project-portal/foundation/納品物一覧.html <output_dir>/docs/納品物一覧.md` を実行し、この時点の暫定的な一覧を作る（新しい生成器は作らない。既存の生成器の判定の中身も変えない）。この段階では大半の納品物が「未生成」になるが、欠陥として扱わず、これから作る予定として提示する。

一覧から次の2点を取り出してユーザーへ提示する。

1. 対象の性質: presentKinds（実在と判定した種別）と excludedKinds（対象外とした種別とその理由）
2. 納品物の件数: 種別ごとの出力件数（「出力あり」の件数）と対象外件数（「対象なし」の件数）

headless=false のときだけ、AskUserQuestionで選択肢「この範囲で進む」「範囲を変える」を示して選ばせる。headless=true のときはAskUserQuestionを発行せず、「この範囲で進む」を選んだものとして自動的に扱う。

- 「この範囲で進む」が選ばれた場合: 提示した presentKinds/excludedKinds をそのまま確定する
- 「範囲を変える」が選ばれた場合: 種別の名前（screen・api・table・batch・report・external）を並べて選ばせる形で対象範囲を手で指定してもらい、その場で excluded-kinds.json の presentKinds/excludedKinds を指定内容で上書きする

選んだ内容（選択肢・指定内容・日時）を、excluded-kinds.json と同じファイルの approvalHistory 配列（既存キーへの追記のみ。excluded-kinds.jsonのスキーマそのものは作り替えない）へ、承認の経緯として記録する。

Step 3-1以降が参照する unit_kinds_present は、本Step確定後は excluded-kinds.json の presentKinds と同義とする。Phase 3以降で対象範囲が変わった場合（例えばStep 5-1以降で新しい種別の実在が判明した場合）は、excluded-kinds.jsonへの記録だけで済ませず、本Stepの提示・承認を再度実行する。

**完了**: excluded-kinds.jsonのpresentKinds/excludedKindsが確定し、承認の経緯がapprovalHistoryへ記録されている。

## Phase 3: 目録

## Step 3-1: 実在種別の一覧を生成する

- global_step: 9
- tool: Agent / Skill
- condition: 一覧未生成時

unit_kinds_present（Step 2-7で承認されたexcluded-kinds.jsonのpresentKindsと同義）に含まれる種別だけ、対応する6一覧スキル（generating-screen-list-for-reverse-docs・generating-api-list-for-reverse-docs・generating-table-list-for-reverse-docs・generating-batch-list-for-reverse-docs・generating-report-list-for-reverse-docs・generating-external-list-for-reverse-docs）を起動する。対話モードは Agent で並列、headless は Skill で逐次実行する。各子へ source_dir・output_dir を渡し、status=DONE を確認する。画面については永続正本を `screen_manifest_path=<output_dir>/<manifestsRoot>/screen-manifest.json`、`screen_manifest_ext_path=<output_dir>/<manifestsRoot>/screen-manifest.ext.json` に固定し、検出直後の生マニフェストとメタデータ付与後マニフェストをそれぞれ原子的に保存する。

通常の再開実行は永続 screen_manifest_path を直接入力にする。旧成果物の明示的な移行・復元を行う場合に限り、画面一覧HTMLが存在して永続 screen_manifest_path が無ければ `bash generation-engine/scripts/unit-list/restore-screen-manifest.sh <output_dir>/<screenListHtml> <screen_manifest_path>` を実行して埋込 `#screen-manifest` から一度だけ復元する。続いて validate-manifest.sh を通し、固定した generated_at と raw の正規化SHA-256を `--generated-at`・`--manifest-content-hash` へ渡して extract-screen-metadata.sh で screen_manifest_ext_path を再生成する。復元・検証・メタデータ付与・hash一致のいずれかが失敗した場合は通常工程へ合流しない。`screenListDir`・`screenListHtml` は画面一覧の物理配置を持つ output-layout のキーである。

**注記**: 画面一覧.HTMLへ実際に埋め込まれているのは、build-unit-list.sh(内部でbuild-screen-list.shへ委譲)に渡した入力(`screen_manifest_ext_path`)そのものであり、派生フィールド(category/permissions/designDocStatus/existingTestCount/sourceHash等)を含む**拡張マニフェスト**である。したがって上記の復元手順で得られる内容も拡張マニフェスト相当であり、Phase 2の生検出結果そのものではない。extract-screen-metadata.shでのscreen_manifest_ext_path再生成は、この拡張マニフェストへgenerated_at・hashを確定付与し直す工程として扱う。

全種別の子スキルが status=DONE を返した後、`bash generation-engine/scripts/unit-list/check-manifest-persistence.sh <output_dir>` を実行し、生成済みの一覧フォルダ（画面一覧・API一覧・テーブル一覧・バッチ一覧・帳票一覧・外部連携一覧・機能一覧のうち生成済みのもの）すべてで一覧HTMLが `<output_dir>/<unitsRoot>/<種別>一覧/` 配下に実在し、対応する生マニフェスト・拡張マニフェストが `<output_dir>/<manifestsRoot>/` 配下へ実際に永続化されていることを機械検査する。各子スキルの SKILL.md 記述だけでは実際に永続化されたかを確認できないため（改善課題 1-136）、本 Step の完了条件として exit 0 を必須とする。FAIL 時は不足が報告されたフォルダの子スキルへ差し戻し、拡張マニフェストの永続先パス指定を確認する。

**画面とAPIの対応づけ（本Stepの担当）**: `screen_manifest_ext_path` は各子スキルが自分の一覧確立時点で単独に生成するため、api種別が画面種別と同時またはそれより後に確立する実行順では `relatedApis` を解決できない（api-manifest がまだ存在しないため）。screen種別とapi種別の両方が status=DONE の場合、本Stepが両者を結ぶ担当を持つ。`<output_dir>/<manifestsRoot>/api-manifest.json`（API raw正本）の実在を確認し、実在すれば次を実行して screen_manifest_ext_path の `relatedApis` を api-manifest の unitKey へ解決し、画面一覧.html・画面遷移図・マトリクス関連ファイルを整合させて再生成する。

```bash
bash generation-engine/scripts/unit-list/rebuild-screen-derived-pages.sh \
  --raw-manifest "<output_dir>/<manifestsRoot>/screen-manifest.json" \
  --target-repo "<target_repo_path>" \
  --api-manifest "<output_dir>/<manifestsRoot>/api-manifest.json" \
  --output-root "<output_dir>" \
  --generated-at "<固定ISO8601>" \
  --design-docs-dir "<output_dir>/<screenUnitRoot>"
```

api-manifest.json が存在しない場合（api が unit_kinds_present に含まれない等）は本手順をスキップし、スキップした理由を記録する。失敗時は rebuild-screen-derived-pages.sh 自身が開始前のtreeへrollbackするため、原因を解消してから再実行する。

**完了**: 実在種別の一覧HTMLがすべて存在し、画面一覧が存在する場合は永続 screen_manifest_path / screen_manifest_ext_path が実在して両方とも検証済み。`check-manifest-persistence.sh <output_dir>` が exit 0。screen種別とapi種別の両方が存在する場合は、`rebuild-screen-derived-pages.sh` による `relatedApis` 解決が exit 0 で完了しているか、スキップの理由が記録されている。

## Step 3-2: 対象外種別と派生一覧を確定する

- global_step: 10
- tool: Write / Edit / Skill
- condition: Step 3-1 完了時

対象外種別は、Step 2-7で承認された excluded-kinds.json（presentKinds/excludedKinds）を正として読み込む。承認を経ずに機械判定だけで対象種別を再確定させない。excludedKindsに記載の各種別について「該当なし」文書（`<output_dir>/<unitListAbsentMd>`）がまだ無ければここで生成する。`<output_dir>/<manifestsRoot>/screen-manifest.json`（raw画面正本）が存在する場合のみ generating-feature-list-for-reverse-docs を source_dir・output_dir（・任意で survey_doc_path）で起動する。raw画面正本が存在しない場合は機能一覧をスキップし、画面一覧の正本確立後に本Stepを再実行する。生成結果の空判定で対象外を再評価しない。画面一覧HTMLが存在するのに `<output_dir>/<unitListHtml>` が不在の場合、状態判定の16状態には追加しない。本Stepを再実行して補完する（派生一覧は16状態の判定フローの対象外）。`unitListHtml` は output-layout の物理配置キーで、{label} は「機能」である。

**完了**: 6種別の生成済み/対象外が復元可能で、生成可能な機能一覧が存在する。

## Step 3-3: マトリクスと対応表を生成する

- global_step: 11
- tool: Skill
- condition: 画面一覧とAPI一覧が存在する場合のみ

機能一覧確立後、`<output_dir>/<manifestsRoot>/screen-manifest.json`・同`screen-manifest.ext.json`・`<output_dir>/<unitListHtml>`（{label}=「API」）がすべて存在する場合のみ generating-cross-views-for-reverse-docs を target_repo_path・output_dir（・任意で portal_output_dir・sites_path・site_key）で起動し、生成可能なマトリクス・対応表4ページとAI設定資産ページを生成する。いずれか不在の場合はスキップし、raw・raw由来ext・API一覧の確立後に再実行する。既知の permission-function データ形状ギャップは skipped_pages として保持する。画面一覧HTML・API一覧HTMLが両方存在するのにマトリクス・対応表・AI設定資産ページが1つも存在しない場合は本Stepを再実行して補完する（派生補完は16状態の判定フローの対象外）。

**完了**: 生成可能な派生補完が存在し、未生成は理由付きで記録されている。

## Phase 4: 共通書き起こしとポータル

## Step 4-1: 共通文書の層化サンプルを確定する

- global_step: 12
- tool: Skill
- condition: 共通未書き起こしまたは common-docs-append のとき実行

survey_doc_path を渡して generating-reverse-common-docs をこのブロックで1回だけ起動する。初回は mode=v0、共通文書欠落の差し戻しは mode=append と append_findings を使う。返却ブロックと機械証拠を保持し、global Step 14〜15は同じ起動結果を確認する。

**完了**: 書き起こし対象の層化サンプルが確定している。

global_step 13（規約4種の書き起こし工程）は撤去済みで、統括に対応するStepを持たない。番号は退役番号として記録し、後続の番号を繰り上げない。

- global_step: 13
- 状態: 退役（規約4種の書き起こし工程撤去に伴う欠番。呼び出し先なし）

## Step 4-2: 共通設計文書を書き起こす

- global_step: 14
- tool: Read
- condition: Step 4-1 通過時、または common-docs-append の戻り先

global Step 12の同一起動が生成した共通設計書・メッセージ定義書・DESIGN.mdをReadで確認し、append時は指摘対象だけが追記された証拠を確認する。

**完了**: common_docs_root 配下の必須文書が生成済み。

## Step 4-3: 共通文書ゲートとv0確定を確認する

- global_step: 15
- tool: Read / TaskUpdate
- condition: Step 4-2 完了時

global Step 12の同一起動が返した機械ゲート証拠とstatus=採録v0確定または追記完了を確認し、common_docs_root を保持する。

**完了**: common_docs_root が確定している。

## Step 4-4: ポータルと任意基盤ページを確定する

- global_step: 16
- tool: Skill / Bash
- condition: 共通書き起こし完了後

- conditional_step_id: screen-batch-route

必要なら surveying-local-environment と counting-code-lines を起動し、Bashで generation-engine/scripts/build-portal.sh を実行する。

`bash generation-engine/scripts/build-portal.sh` の実行前に、`<output_dir>/project-portal/index.html` が既に実在するかを確認する。実在し、かつ `pt-nav-data` マーカー（`<script type="application/json" id="pt-nav-data">`。build-portal.sh 自身が生成物の判別に使うマーカーで、対象外HTMLはこのマーカーを持たない）を含まない場合、対象アプリが元から持つ既存資産との衝突とみなし、上書きしない。この場合は build-portal.sh を実行せず中断し、ユーザーへ別の出力先（`output_dir` の変更）を確認する。`pt-nav-data` マーカーを含む場合は自身が生成した資産の再生成のため、通常どおり上書きしてよい。`index.html` が不在の場合は衝突なしとしてそのまま生成する。

```bash
bash generation-engine/scripts/build-portal.sh \
  "$target_repo_path" \
  "$output_dir" \
  "$output_dir/project-portal" \
  --project-name "$project_display_name" \
  --catalog delivery-payload/references/portal-catalog.json
```

`project_display_name` は、この Step を実行する管理者が利用者に見せる正式なプロジェクト名として明示的に渡す必須の実行時値である。`target_repo_path` のフォルダ名や検証用 worktree 名から推測してはならず、値を確定できない場合は生成を開始せず確認する。

ポータルは納品物ルート（output_dir）配下の `project-portal/index.html` として出力する（正本レイアウト。`references/contract.md` の「納品物ルート（output_dir）の正本レイアウト」参照）。カテゴリ、カード、探索条件、件数単位は `delivery-payload/references/portal-catalog.json` から導出する。カテゴリや成果物種別を追加する場合は、`build-portal.sh` へ分岐を足さず catalog へ blueprint を登録する。画面manifestから派生物を一括再生成する工程では、同じ catalog に加えて `--portal-only`・`--generated-at`・`--screen-manifest` を渡し、複数サイトでは `--sites`・`--site-key` も保持して、既存成果物を再変換せず `index.html` だけを更新する。サイトが2件以上あり `<納品ルート>/sites.json` が不在なら、統括スキル自身が `sites.json` を書き出す。

データ源が揃う任意基盤ページだけ対応スキルで生成し、ポータルを再生成する。

- generating-tech-stack-for-reverse-docs（アーキテクチャ調査書 §2 が確定済みのとき）
- generating-env-guide-for-reverse-docs（アーキテクチャ調査書 §3 が確定済みのとき）
- generating-screen-transition-for-reverse-docs（raw画面正本とraw由来extが確定済みのとき）
- generating-er-diagram-for-reverse-docs（テーブル一覧.html が確定済みのとき）
- generating-release-notes-for-reverse-docs（コミット履歴が確定済みのとき。`<output_dir>/project-portal/foundation/リリースノート.html`）
- generating-design-system-for-reverse-docs（デザイントークンのデータ源が確定済みのとき。`<output_dir>/project-portal/foundation/デザインシステム.html`）
- generating-component-inventory-for-reverse-docs（コンポーネントのデータ源が確定済みのとき。`<output_dir>/project-portal/foundation/コンポーネント棚卸し.html`）
- generating-icon-catalog-for-reverse-docs（アイコンのデータ源が確定済みのとき。`<output_dir>/project-portal/foundation/アイコンカタログ.html`）
- generating-glossary-for-reverse-docs（互換入口。`proposal_output_ref` が対象repo外の絶対パスとして明示されたときだけ、`detected` 状態の提案YAMLとdiagnosticsを生成して `NEEDS_REVIEW` で停止する。用語辞書・HTML・承認済みYAMLは生成しない）
- managing-semantic-glossary（`approved_glossary_ref` がschema検証済みかつ承認済みのときだけ、portal publishとして `lists/用語辞書/用語辞書.html` を生成する）

generating-entity-state-for-reverse-docs は基盤ページではなく図ページであり、raw画面正本とraw由来extが確定済みのときに `<output_dir>/project-portal/diagrams/状態遷移図.html` を生成する。

結合テスト仕様書は、2つ以上の設計単位が存在するときに generating-integration-test-spec-for-reverse-docs を起動し、プロジェクト全体の `docs/test-cases/結合テスト仕様書.md` として生成する。メッセージ一覧・テスト観点表一覧・テストケース一覧は種別ループの対象外の派生一覧である。メッセージ定義書.md が存在する場合だけ generating-message-list-for-reverse-docs を起動する。いずれかの種別の `テスト設計/` 配下に2種類のテスト設計書の一方が存在する場合だけ、generating-test-viewpoint-list-for-reverse-docs と generating-test-case-list-for-reverse-docs を続けて起動し、画面が存在する場合だけテストケース一覧の集約元へ操作シナリオ仕様書を加える。到達状態は生成済み/未生成の2値で記録する（状態キー「派生一覧未生成（任意）」）。

対象画面が4件以上なら running-reverse-screen-batch に global Step 17〜28・40〜41の実行を委譲し、3件以下は本スキルが同じglobal Stepを逐次仲介する。global Step 29〜39（API・機能・テーブル・バッチ・帳票・外部連携の各設計書著述）は画面ループの外・画面バッチへの委譲の外で1回だけ実行する非画面の工程であり、この委譲範囲に含めない。条件分岐は新しいPhase番号を作らない。

**完了**: index.html と生成対象ページが存在し、screen-batch-route の選択と理由が記録されている。

## Phase 5: 静的ユニット処理

## Step 5-1: 対象ユニットと著述モードを確定する

- global_step: 17
- tool: Read / Bash
- condition: screen種別は本Step以降のfacts工程へ進む。api種別はfacts工程を経由せず原本だけを読み取る種類のStep 5-13（API詳細設計著述）と Step 5-15（API基本設計著述）へ分岐する。table・batch・report・external の4種別は、facts工程を経由せず原本だけを読み取る種類の基本設計と詳細設計（Step 5-16〜5-23）へ分岐する

対象画面IDを一覧マニフェストで検証し、`target_file_paths` の合計行数とファイル数を実測して authoring_mode を決定する（合計1,500行超または4ファイル超なら `large-two-pass`、それ以外は `standard`）。画面未開通は静的処理の阻害条件にしない。通常の画面ループは `facts_profile=auto|screen` のどちらでも常に `profile=screen` を渡し、対象ファイルが全件 `.py` でも python へ自動変更しない。`facts_profile=python` は global Step 2 の明示Python facts-only経路で終端済みのため本ループへ到達しない。雛形の展開は事実確定完了（facts_ref確定）後に1回だけ実施し（`bash <scaffold_script_path> <output_dir> <画面ID> [<画面名>]` を画面ディレクトリ未存在時のみ実行。既存の場合は `--verify` のみで健全性確認する）、facts抽出より前へ移動してはならない。

**完了**: 対象ユニット・対象ファイル・著述モードが確定している。

## Step 5-2: factsを抽出する

- global_step: 18
- tool: Skill
- condition: 事実未確定時

extracting-unit-facts-from-code を profile=screen と必要args全量で、このブロックでは1回だけ起動する。原本コードからfactsを抽出させ、返却ブロックと再計数・確定・再現性の機械証拠を保持する。global Step 19〜21は同じ起動結果を確認し、部分起動modeのない子スキルを再起動しない。

**完了**: facts_ref が返却候補として生成済み。

## Step 5-3: factsを独立再計数する

- global_step: 19
- tool: Read
- condition: Step 5-2 完了時

global Step 18の同一起動が返した独立再計数ゲートの終了コードと突合結果をReadで確認する。

**完了**: 再計数ゲートがPASSしている。

## Step 5-4: factsを確定する

- global_step: 20
- tool: Read
- condition: Step 5-3 PASS時

global Step 18の同一起動が返したfacts.lockの実在・ハッシュ・status=封印済みをReadで確認する。

**完了**: status=封印済み と facts_ref を受領している。

## Step 5-5: factsの再現性を検証する

- global_step: 21
- tool: Read
- condition: Step 5-4 完了時

global Step 18の同一起動が返した決定的再現性検査のPASS証拠をReadで確認する。

**完了**: 再現性検証がPASSしている。

## Step 5-6: 基本設計テンプレートとfactsを読み込む

- global_step: 22
- tool: Read / Bash
- condition: facts_ref と common_docs_root 確定後

画面ディレクトリを1回だけscaffoldまたはverifyし、generating-reverse-basic-designへ渡すテンプレート・facts・共通文書のargsを準備する。このStepでは子スキルを起動しない。

**完了**: 基本設計著述の入力が確認済み。

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

global Step 23の同一起動が返した実装用語混入検査の終了コード、基本設計書パス、status=基本設計著述完了をReadで確認する。

**完了**: 基本設計の機械ゲートがPASSしている。

## Step 5-9: 詳細設計用の確定済みfactsを確認する

- global_step: 25
- tool: Read
- condition: facts_ref と common_docs_root 確定後

generating-reverse-detailed-designへ渡す確定検証・章マップ・監査スクリプト・著述モードのargsを準備する。このStepでは子スキルを起動しない。

**完了**: 詳細設計著述の入力と確定状態が確認済み。

## Step 5-10: 詳細設計と周辺文書を著述する

- global_step: 26
- tool: Skill / Agent
- condition: authoring_modeに従う

準備済みargsでgenerating-reverse-detailed-designを起動する。standardはauthoring_pass=fullで1回だけ起動する。large-two-passはauthoring_pass=detail-onlyを1回起動してDETAIL_AUTHOREDと開始証跡を確認し、その証跡を渡してauthoring_pass=companion-docsを別のSkill/Agentとして2回目に起動する。2回目はbasicのlarge-pass2と並列化できるが、パス1返却前の起動は禁止する。

**完了**: 詳細設計と周辺文書の生成パスが返却候補として存在する。

## Step 5-11: 詳細設計の完全性と模範例を検査する

- global_step: 27
- tool: Read / Bash
- condition: Step 5-10 完了時。模範例不在は理由付きスキップ

global Step 26の該当起動（standardはfull、large-two-passはdetail-onlyとcompanion-docs）が返した完全性ゲート証拠をReadで確認し、模範例が存在する場合だけ backtest-facts-against-gold.sh と check-doc-coverage-against-gold.sh を実行する。ゲート確認だけを目的とした再起動はしない。

**完了**: 必須ゲートがPASSし、模範例の実行結果またはスキップ理由が記録済み。

## Step 5-12: 静的完了を確定する

- global_step: 28
- tool: Write / TaskUpdate
- condition: Step 5-7とStep 5-10の合流条件を満たした時

- conditional_step_id: docs-only-terminal

global Step 26の該当起動から、standardは最終返却status=AUTHORED、large-two-passはパス1のDETAIL_AUTHOREDとパス2のCOMPANION_AUTHOREDの双方を受領して合流条件を確認する。

**静的完了ゲート**: 続いて、永続 `screen_manifest_path=<output_dir>/<manifestsRoot>/screen-manifest.json` を直接解決し、validate-manifest.sh 通過を確認する。旧成果物の明示的な移行・復元で screen_manifest_path を作成する場合だけ、global Step 9 の復元経路を先に完了させる。output-layout の物理配置キー `layout.screenUnitRoot` を解決し、正本rawから `extract-screen-metadata.sh <screen_manifest_path> <source_dir> <screen_manifest_ext_path> --design-docs-dir <output_dir>/<screenUnitRoot> --link-base-dir <output_dir>/<screenListDir>` を再実行し、`build-unit-list.sh <screen_manifest_ext_path> <output_dir>/<screenListHtml> --unit-kind screen --portal-dir <output_dir>` で画面一覧を必ず再生成する。表示用 `kindLabels.screen` はpathに使わない。再実行時は固定した generated_at と raw の正規化SHA-256をそれぞれ `--generated-at`・`--manifest-content-hash` へ必ず渡し、ext の `manifestContentHash` 一致も静的完了条件に含める。raw検証・メタデータ付与・再生成のいずれかが失敗した場合は静的完了を宣言しない。再生成後、当該画面の実在成果物だけに4リンクが付与され、確定画面名がある場合は `confirmedScreenName` が表示源へ反映され、マニフェスト登録件数と表行数が一致することを確認する。

画面レジストリの定義ファイルは `<output_dir>/<screenRegistry>`（YAML。`screenRegistry` は output-layout の物理配置キー）である。キーは `<system>-<screen_id>`、値は `source_ref`/`verification_url`/`design_doc_path`/`status`である。形式の詳細は `references/contract.md` の「画面レジストリ」節を参照する。この後でのみ画面レジストリの当該エントリを作成または更新して status=authored とする。その後にURLの有無にかかわらず `verification_mode` を評価する。docs-onlyはここで「静的リバース完了」として終端し、global Step 40〜41（動的往復検証・判定）を起動しない。global Step 29〜39（画面ループの外で1回だけ実行する非画面の設計書著述）は `verification_mode` に依存せずdocs-onlyでも実行する。single-pass|iterativeだけ動的検証へ進む。

**完了**: facts・基本設計・詳細設計が完成し、docs-only終端または動的検証への分岐が確定している。

## Step 5-13: API詳細設計の著述

- global_step: 29
- tool: Skill
- condition: unit_kind=api。画面ループの外・画面バッチへの委譲の外で、全画面の処理が終わったあとに1回だけ実行する。`verification_mode` に依存せず、docs-onlyでも実行する

global Step 9（API一覧の確立）が完了していることを前提に、generating-api-detail-design-for-reverse-docs を起動する。API一覧マニフェスト（`<output_dir>/<manifestsRoot>/api-manifest.ext.json`）に載るAPI1本ごとにAPI詳細設計書.mdを生成する。本Stepはfacts工程を経由しない原本だけを読み取る種類であり、往復検証の対象にはならない。

**完了**: API一覧に載る全APIについてAPI詳細設計書.mdが生成されている。APIが0件の場合は生成せず完了とする。

## Step 5-14: 機能設計の著述

- global_step: 30
- tool: Skill
- condition: unit_kind=feature。画面ループの外・画面バッチへの委譲の外で、Step 5-13のあとに1回だけ実行する。`verification_mode` に依存せず、docs-onlyでも実行する

global Step 10（機能一覧の確立）とStep 5-12（画面詳細設計）・Step 5-13（API詳細設計）が先に完了していることを前提に、generating-feature-design-for-reverse-docs を起動する。機能一覧マニフェスト（`<output_dir>/<manifestsRoot>/feature-manifest.json`）に載る機能1件ごとに機能設計書.mdを生成する。機能設計書は構成要素の設計書をパスで参照する集約設計書のため、参照先が実在する状態で実行する。機能は派生一覧であり `unit_kinds_present` の判定対象外である。種別ループには載せず、機能一覧の確立を前提に単独で起動する。

**完了**: 機能一覧に載る全機能について機能設計書.mdが生成されている。機能が0件の場合は生成せず完了とする。

## Step 5-15: API基本設計の著述

- global_step: 31
- tool: Skill
- condition: unit_kind=api。画面ループの外・画面バッチへの委譲の外で、全画面の処理が終わったあとに1回だけ実行する。`verification_mode` に依存せず、docs-onlyでも実行する

global Step 9（API一覧の確立）が完了していることを前提に、generating-api-basic-design-for-reverse-docs を起動する。API一覧マニフェスト（`<output_dir>/<manifestsRoot>/api-manifest.ext.json`）に載るAPI1本ごとにAPI基本設計書.mdを生成する。本Stepは業務語彙のみで書く。実装の詳細はStep 5-13のAPI詳細設計が担う。両者は同じ情報源を読み、抽出する内容と出力の関門が異なる。

**完了**: API一覧に載る全APIについてAPI基本設計書.mdが生成されている。APIが0件の場合は生成せず完了とする。

## Step 5-16: テーブル基本設計（論理データモデル）の著述

- global_step: 32
- tool: Skill
- condition: unit_kind=table。画面ループの外・画面バッチへの委譲の外で、全画面の処理が終わったあとに1回だけ実行する。`verification_mode` に依存せず、docs-onlyでも実行する

global Step 9（テーブル一覧の確立）が完了していることを前提に、generating-table-logical-model-for-reverse-docs を起動する。テーブル一覧マニフェスト（`<output_dir>/<manifestsRoot>/table-manifest.ext.json`）に載るテーブル1件ごとに論理データモデル.mdを生成する。本Stepは業務語彙のみで書く。導出できない事項は要確認事項一覧へ移す。実装の詳細はStep 5-17のテーブル詳細設計が担う。

**完了**: テーブル一覧に載る全テーブルについて論理データモデル.mdが生成されている。テーブルが0件の場合は生成せず完了とする。

## Step 5-17: テーブル詳細設計（テーブル定義書）の著述

- global_step: 33
- tool: Skill
- condition: unit_kind=table。画面ループの外・画面バッチへの委譲の外で、全画面の処理が終わったあとに1回だけ実行する。`verification_mode` に依存せず、docs-onlyでも実行する

global Step 9（テーブル一覧の確立）が完了していることを前提に、generating-table-definition-for-reverse-docs を起動する。テーブル一覧マニフェスト（`<output_dir>/<manifestsRoot>/table-manifest.ext.json`）に載るテーブル1件ごとにテーブル定義書.mdを生成する。本Stepは実装用語を使ってよい。根拠を本文へ書く。本Stepはfacts工程を経由しない原本だけを読み取る種類であり、往復検証の対象にはならない。

**完了**: テーブル一覧に載る全テーブルについてテーブル定義書.mdが生成されている。テーブルが0件の場合は生成せず完了とする。

## Step 5-18: バッチ基本設計書の著述

- global_step: 34
- tool: Skill
- condition: unit_kind=batch。画面ループの外・画面バッチへの委譲の外で、全画面の処理が終わったあとに1回だけ実行する。`verification_mode` に依存せず、docs-onlyでも実行する

global Step 9（バッチ一覧の確立）が完了していることを前提に、generating-batch-basic-design-for-reverse-docs を起動する。バッチ一覧マニフェスト（`<output_dir>/<manifestsRoot>/batch-manifest.ext.json`）に載るバッチ1本ごとにバッチ基本設計書.mdを生成する。本Stepは業務語彙のみで書く。導出できない事項は要確認事項一覧へ移す。実装の詳細はStep 5-19のバッチ詳細設計が担う。

**完了**: バッチ一覧に載る全バッチについてバッチ基本設計書.mdが生成されている。バッチが0件の場合は生成せず完了とする。

## Step 5-19: バッチ詳細設計書の著述

- global_step: 35
- tool: Skill
- condition: unit_kind=batch。画面ループの外・画面バッチへの委譲の外で、全画面の処理が終わったあとに1回だけ実行する。`verification_mode` に依存せず、docs-onlyでも実行する

global Step 9（バッチ一覧の確立）が完了していることを前提に、generating-batch-detail-design-for-reverse-docs を起動する。バッチ一覧マニフェスト（`<output_dir>/<manifestsRoot>/batch-manifest.ext.json`）に載るバッチ1本ごとにバッチ詳細設計書.mdを生成する。本Stepは実装用語を使ってよい。根拠を本文へ書く。本Stepはfacts工程を経由しない原本だけを読み取る種類であり、往復検証の対象にはならない。

**完了**: バッチ一覧に載る全バッチについてバッチ詳細設計書.mdが生成されている。バッチが0件の場合は生成せず完了とする。

## Step 5-20: 帳票基本設計書の著述

- global_step: 36
- tool: Skill
- condition: unit_kind=report。画面ループの外・画面バッチへの委譲の外で、全画面の処理が終わったあとに1回だけ実行する。`verification_mode` に依存せず、docs-onlyでも実行する

global Step 9（帳票一覧の確立）が完了していることを前提に、generating-report-basic-design-for-reverse-docs を起動する。帳票一覧マニフェスト（`<output_dir>/<manifestsRoot>/report-manifest.ext.json`）に載る帳票1本ごとに帳票基本設計書.mdを生成する。本Stepは業務語彙のみで書く。導出できない事項は要確認事項一覧へ移す。実装の詳細はStep 5-21の帳票詳細設計が担う。

**完了**: 帳票一覧に載る全帳票について帳票基本設計書.mdが生成されている。帳票が0件の場合は生成せず完了とする。

## Step 5-21: 帳票詳細設計書の著述

- global_step: 37
- tool: Skill
- condition: unit_kind=report。画面ループの外・画面バッチへの委譲の外で、全画面の処理が終わったあとに1回だけ実行する。`verification_mode` に依存せず、docs-onlyでも実行する

global Step 9（帳票一覧の確立）が完了していることを前提に、generating-report-detail-design-for-reverse-docs を起動する。帳票一覧マニフェスト（`<output_dir>/<manifestsRoot>/report-manifest.ext.json`）に載る帳票1本ごとに帳票詳細設計書.mdを生成する。本Stepは実装用語を使ってよい。根拠を本文へ書く。本Stepはfacts工程を経由しない原本だけを読み取る種類であり、往復検証の対象にはならない。

**完了**: 帳票一覧に載る全帳票について帳票詳細設計書.mdが生成されている。帳票が0件の場合は生成せず完了とする。

## Step 5-22: 外部連携基本設計書の著述

- global_step: 38
- tool: Skill
- condition: unit_kind=external。画面ループの外・画面バッチへの委譲の外で、全画面の処理が終わったあとに1回だけ実行する。`verification_mode` に依存せず、docs-onlyでも実行する

global Step 9（外部連携一覧の確立）が完了していることを前提に、generating-external-basic-design-for-reverse-docs を起動する。外部連携一覧マニフェスト（`<output_dir>/<manifestsRoot>/external-manifest.ext.json`）に載る外部連携1本ごとに外部連携基本設計書.mdを生成する。本Stepは業務語彙のみで書く。導出できない事項は要確認事項一覧へ移す。実装の詳細はStep 5-23の外部連携詳細設計が担う。

**完了**: 外部連携一覧に載る全外部連携について外部連携基本設計書.mdが生成されている。外部連携が0件の場合は生成せず完了とする。

## Step 5-23: 外部連携詳細設計書の著述

- global_step: 39
- tool: Skill
- condition: unit_kind=external。画面ループの外・画面バッチへの委譲の外で、全画面の処理が終わったあとに1回だけ実行する。`verification_mode` に依存せず、docs-onlyでも実行する

global Step 9（外部連携一覧の確立）が完了していることを前提に、generating-external-detail-design-for-reverse-docs を起動する。外部連携一覧マニフェスト（`<output_dir>/<manifestsRoot>/external-manifest.ext.json`）に載る外部連携1本ごとに外部連携詳細設計書.mdを生成する。本Stepは実装用語を使ってよい。根拠を本文へ書く。本Stepはfacts工程を経由しない原本だけを読み取る種類であり、往復検証の対象にはならない。

**完了**: 外部連携一覧に載る全外部連携について外部連携詳細設計書.mdが生成されている。外部連携が0件の場合は生成せず完了とする。

## Phase 6: 動的往復検証

## Step 6-1: 開通から比較結果取得までを依存順に実行する

- global_step: 40
- tool: Skill
- condition: verification_mode=single-pass|iterative

実レンダリング確認済みURLが無ければ unlocking-reverse-target-screens を dynamic-only で起動する。次に syncing-reverse-env(mode=setup) でenv_blockを取得する。env_blockの承認は破壊的操作の承認委譲（起動時に一括付与済みの user-approved を子スキルへ渡す方式。「重要な注意事項」参照）で扱い、本Stepはユーザーへ個別に確認しない。取得したenv_blockを渡して rebuilding-screen-unit-from-docs でファイル単位検証を行う。続けて syncing-reverse-env(mode=sync) でbaseline_tagを確立し、rebuilding-code-from-docs(mode=implement)のcompare_requestを受領し、syncing-reverse-env(mode=sync,dry-run)の比較結果全文を保持する。順序は unlock → setup → file verify → baseline sync → implement → compare で固定する。

**完了**: compare_result全文とfreeze_commitが揃うか、静的成果物を保持した動的検証保留理由が確定している。

## Phase 7: 判定と確定

## Step 7-1: judgeして基準更新または差し戻しを確定する

- global_step: 41
- tool: Skill / TaskCreate / Read
- condition: Step 6-1でcompare_result取得済み

rebuilding-code-from-docs(mode=judge)へcompare_result全文とfreeze_commitを渡す。PASS時は承認を求めず syncing-reverse-env(mode=sync)で基準タグを本番更新し、依頼時だけteardownする。FAIL時はNG帰着3系統へ分類し、single-passは改善候補を報告して停止、iterativeだけ下記戻り方向の依存 metadataに従って戻す。

続けて、Step 2-7で承認した時点の一覧（excluded-kinds.json 承認時点のpresentKinds/excludedKinds・build-deliverable-inventory.sh の暫定件数）と、本Step完了時点で `bash generation-engine/scripts/build-deliverable-inventory.sh <output_dir> <output_dir>/project-portal/foundation/納品物一覧.html <output_dir>/docs/納品物一覧.md` を再実行して得られる完成時点の一覧とを突き合わせる。承認した範囲がそのまま満たされたかを見るだけであり、完了としてよいかを尋ねない。差があれば種別ごとの差（承認時の件数・完成時の件数）を表で示して終える。差が0件なら「差なし」と1行報告する。

**完了**: PASS・FAIL・動的検証保留のいずれかが確定し、PASS時は基準更新または依頼時teardownが完了している。承認時点の一覧と完成時点の一覧の突き合わせ結果が報告されている。

## 条件分岐メタデータ

各 conditional_step_id（screen-batch-route・docs-only-terminal・dynamic-route）の判定Step・条件・実行経路の対応表は `references/operations.md` の「条件分岐メタデータ」節を正本とする。宣言自体は各Stepブロックの `conditional_step_id` 行に本文として存在する。

## 戻り方向の依存メタデータ

戻り方向の依存は通常順序を上書きする唯一の例外であり、戻り先・条件・上限をprogress.jsonlとTaskCreateへ記録し、暗黙の「前工程へ戻る」表現を禁止する。詳細は `references/operations.md` の「戻り方向の依存メタデータ」節も参照するが、下表を正としてリバース工程設計.md（正本）と一致させる。列名も正本と同一の `from_step` / `to_step` を使う。

| back_edge_id | from_step | to_step | 条件 | 上限 | 停止条件 |
|---|---:|---:|---|---:|---|
| architecture-revise | 8 | 5 | 下流が検出手がかり不足を決定的に報告 | 3 | 調査ゲートPASS / 同一FAIL 2連続 |
| facts-reextract | 40 | 18 | iterativeかつファイル検証がfacts欠落へ分類 | 5 | 再現一致 / 5回到達 |
| detail-rewrite | 40 | 26 | iterativeかつファイル検証が著述不足へ分類 | 5 | 再現一致 / 5回到達 |
| common-docs-append | 41 | 14 | iterativeかつjudge FAILが共通文書欠落 | 3 | judge PASS / 同一差分2連続 |
| dynamic-retry | 41 | 40 | iterativeかつ再比較可能な一時FAIL | 3 | judge PASS / 同一差分2連続 |

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | `auto\|screen` は対象パス・出力先・画面範囲・実行モードが、`python` は target_repo_path・output_dir・target_file_paths・facts_unit_id・verification_dir・実行モードが確定し、状態キーの確定と TaskCreate 登録が済んでいる（`python` は明示Python facts-only経路で終端する。入口モードが `setup-only` の場合は規約定義とAIツール設定の生成をもって「セットアップ完了」として終端する） |
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

- 状態判定は「アーキテクチャ調査書の実在 → 各種別の一覧HTML + excluded-kinds.json の実在 → プロジェクト共通10文書の実在 → facts確定の実在 → 画面基本設計書の実在 → 設計書/対象ファイル/著者スキルの完全性ゲート成果物の実在 → 画面開通有無 → 検証記録の再現一致有無 → ⑤setup返却の baseline_tag → ⑨judge の status」の順の判定フロー。静的リバースを先行するため、画面未開通でも設計書著述まで進める。成果物の実在から毎回評価するので中断後も再開できる
- ⑨は mode で2分割される（implement=比較要求を返して停止 / judge=比較結果を受け取り判定）。管理者がこの2回を別々に起動し、間に⑧sync dry-run を挟む
- scaffold_script_path は管理者がリポジトリ展開先の `generation-engine/scripts/scaffold-screen.sh`（正本はこの1本のみ）を解決して generating-reverse-detailed-design / rebuilding-screen-unit-from-docs に渡す（audit_script_path と同型）
- 静的著述後の画面未開通では `unlocking-reverse-target-screens(invocation_mode=dynamic-only)` を起動し、開通・レジストリ記帳・設計書 frontmatter の実測項目補完まで行う。基準確立は後続の Phase 5/7 が担う。単独起動の `standalone` だけは従来どおり基準タグ確立まで完走する
- 事実未確定〜ファイル単位未検証の間は、extracting-unit-facts-from-code（原本を読む唯一の役）→著述モード別の basic/detailed design（原本を読まず facts を読む）→ rebuilding-screen-unit-from-docs（factsも原本も読まない）の順で情報アクセスを絞る。基本設計は詳細設計を内容の出典にはしない。大規模ユニットではパス1の詳細設計を開始証跡としてパス2へ渡す。`verification_mode=iterative` で rebuilding が status=差し戻し を返した場合だけ detailed-design の著述へ戻る
- judge FAIL 時の自動改善は `verification_mode=iterative` の場合だけ有効。NG帰着(c)共通文書欠落は管理者が generating-reverse-common-docs を mode=append で再起動できるが、(a)執筆規律不足・(b)facts欠落 はスキル資産（reference・プロファイル）の改訂を要するため、管理者は自動配線せずユーザーに報告する（`references/contract.md` の「NG帰着3系統の配線」）
- 2026-07-22 実測: 無人セッション内のサブエージェント経由で Phase 6 を実行し、ファイル検証工程のネスト委任不可で画面が failed 終端した

## 参照資料

- `references/contract.md` — 返却ブロック契約・args仕様・状態判定表・種別ループ・NG帰着3系統の配線・入口モード判定契約の正本
- `scripts/resolve-flow-mode.sh` — 入口モード（setup-only / reverse-full / reverse-degraded）の機械判定。Step 1-1 の「入口モードを判定する」節から呼ぶ
- 共有資産（本スキル専有ではなくリポジトリ共通、`<reverse_docs_root>/delivery-payload/` および `<reverse_docs_root>/generation-engine/` 配下）: `delivery-payload/templates/リバース検証/`（テンプレート一式）、`generation-engine/scripts/audit-consistency.sh`（工程間ゲート）、`generation-engine/scripts/scaffold-screen.sh`（画面ディレクトリのテンプレート展開。正本はこの1本のみ）、`generation-engine/scripts/seal-facts.sh`（facts確定・検証）、`delivery-payload/references/chapter-map.md`（章役割キー対応表）、`delivery-payload/references/facts-schema.md`（facts.ymlスキーマ正本）、`delivery-payload/references/リバース工程設計.md`（Phase/Step×スキル対応の正本）。各子スキルへは template_root / audit_script_path / scaffold_script_path / chapter_map_path として絶対パスを渡す
- 画面レジストリ: `<output_dir>/<screenRegistry>`（正本定義は references/contract.md）
- `unlocking-reverse-target-screens/manifest.yml` — 同スキルが管理するプロジェクト固有値の正本（本スキルは関知しない）

## 完了報告
`../../../delivery-payload/references/完了報告の書き方.md` の共通骨格（作業報告型）に従う。

固有の検証行:
- 通過 Phase 数・最終状態キーの確定

## 設計判断
詳細な設計判断は Read 済みの `references/operations.md` を参照する。
