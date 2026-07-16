# orchestrating-reverse-docs-flow 契約正本

この契約は管理者スキル orchestrating-reverse-docs-flow が正本を持つ。子スキル17個（surveying-architecture-for-reverse-docs / 種別別一覧スキル6つ（`generating-<種別>-list-for-reverse-docs`、例: generating-screen-list-for-reverse-docs） / generating-feature-list-for-reverse-docs（機能一覧・派生一覧） / generating-reverse-common-docs / syncing-reverse-env / unlocking-reverse-target-screens / extracting-unit-facts-from-code / generating-reverse-basic-design / generating-reverse-detailed-design / rebuilding-screen-unit-from-docs / rebuilding-code-from-docs / running-reverse-screen-batch）は自分の SKILL.md 内で「この契約に準拠する」と宣言するのみで、contract.md 自体は読まず args だけで動く。管理者は各子スキルの返却ブロックを本契約の共通サブセットで検収し、状態判定表に従って次工程を機械的に決定する。これにより管理者と子スキルの間には契約書という単一の仲介点だけが存在し、子スキル同士が互いの内部仕様を知る必要がない完全仲介方式が成立する。

## プレースホルダ定義

- `verification_dir`: docs と同階層の `verification/`。修正指示書・最終報告・テストログ・facts の出力先。

## 返却ブロック共通サブセット

管理者が検収に読む4キーの表。

| キー | 型 | 意味 |
|---|---|---|
| status | enum | 各スキル固有の enum。管理者はこれで go / 差し戻しを判定する |
| scope | string | `<system>-<画面ID>`。工程を跨いだ同一性キー |
| artifacts | path[] | 生成物のパス（画面一覧HTML / 修正指示書.md / 最終報告.md / 証跡ディレクトリ 等） |
| hint | string | 次工程への申し送り（差し戻し理由・不足引数・後続工程への申し送り 等） |

注記: `next_request` という語は使わない。syncing-reverse-env の実返却ブロックに存在しないフィールドのため。次工程への依頼内容は hint または各スキル固有の拡張フィールドで表す。

## 各スキル固有の status enum と拡張フィールド

### surveying-architecture-for-reverse-docs（アーキテクチャ調査）

- status: `調査確定 | 中断`
- 拡張: survey_doc_path（調査書の絶対パス。`artifacts[0]` と同値）、unit_kinds_present（実在判定が「実在する」だった画面・API・テーブル・バッチ・帳票・外部連携の一覧）

### generating-<種別>-list-for-reverse-docs（種別別一覧スキル6つ共通）

- status: `DONE | ERROR`
- 拡張: unit_list_html（= artifacts[0]）、embedded_json_ref（HTML内埋め込みマニフェストJSONへの参照）、unit_kind（生成した種別）
- `unit_kind=screen` の場合、screen_list_html は unit_list_html のエイリアスとして有効
- `unit_kind=screen` かつ複雑度プロファイリング（Phase 5・`--profile`）を実行した場合のみ、拡張フィールド complexity_profile_path（複雑度プロファイル.json の絶対パス）を返す。未実行の場合は本フィールドを含めない

### generating-feature-list-for-reverse-docs（機能一覧・派生一覧）

- status: `DONE | ERROR`
- 拡張: unit_list_html（= artifacts[0]）、embedded_json_ref（HTML内埋め込みマニフェストJSONへの参照）、unit_kind（`feature` 固定）
- 機能は既存一覧の派生グルーピング（派生一覧）であり、unit_kinds_present の存在判定対象外。excluded-kinds.json の allKinds にも含めない
- 入力前提: `<output_dir>/一覧/画面一覧/画面一覧.html` が存在すること（不在時は status=ERROR で hint に前提スキルを記録して返す）

### generating-reverse-common-docs（プロジェクト共通採録）

- status: `採録v0確定 | 追記完了 | 中断`
- 拡張: common_docs_root（`プロジェクト共通/` の絶対パス）、sample_manifest_path（サンプル記録.md の絶対パス）
- `mode=v0` の初回起動では `採録v0確定`、NG帰着(c)共通文書欠落からの `mode=append` 再起動では `追記完了` を返す

### syncing-reverse-env

- status: `PASS | FAIL | ERROR | INCOMPLETE`
- 既存の15フィールド返却ブロックはそのまま正で改変しない。フィールドは: status / mode / scope / screen_id / slot / ports / original_code / reverse_code / baseline_tag / static_diff / dynamic / env_check / artifacts / docs_root / hint
- 管理者が読むのは status / scope / ports / baseline_tag / docs_root / artifacts / hint
- mode=setup の返却からは環境ブロック（env_block）として docs_root / scope / ports / slot / baseline_tag / original_code / reverse_code を抽出する
- mode=sync,dry-run の返却が「比較結果ブロック」= static_diff / dynamic / env_check / status / hint を含む15フィールドそのもの

### unlocking-reverse-target-screens

- status: `BASELINE-ESTABLISHED | UNLOCKED | BLOCKED | ERROR | CONFLICT-SKIPPED`
- `BASELINE-ESTABLISHED`（終端成功）: 開通〜画面レジストリ記帳〜`syncing-reverse-env(mode=registry)`起動〜基準タグ確立まで完走し、決定的コマンド出力（`git tag -l "reverse-baseline/<scope>"`等）で確認済み
- `UNLOCKED`（中間・部分完了）: 画面開通は完了したが `syncing-reverse-env(mode=registry)` がPASS以外で基準タグ未確立
- `CONFLICT-SKIPPED`（開通競合検知）: 対象画面の作業コピー・devサーバー等が既に他プロセスによって使用中と判明し、他プロセスの環境に触れず即座に処理を終了した状態。呼び出し元はこれを競合スキップとして扱い、failed とは別区分で失敗回数にカウントしない
- 拡張: source_ref（開通確認時点のコミットハッシュ等、追跡に使う参照）、verification_url（モックAPI経由で画面が表示確認できるURL。未実施なら「未実施」）、design_doc_path（今後の設計書の想定配置パス）、baseline_tag（`BASELINE-ESTABLISHED`時のみ確定。`syncing-reverse-env`返却の`baseline_tag`をそのまま転記）

### extracting-unit-facts-from-code（ユニット事実抽出）

- status: `封印済み | 中断 | 共通文書帰着`
- 拡張: facts_ref（facts ディレクトリの絶対パス＋facts.lock の sha256）、pending_measurements（⑨実測委譲キーの一覧）
- `profile=screen` のみ実装。他プロファイル指定時は `status=中断`

### generating-reverse-basic-design（基本設計書著述）

- status: `基本設計著述完了 | 基本設計著述失敗`
- 拡張: facts_ref（入力で受け取った facts ディレクトリの絶対パスをそのまま転記。下流工程への追跡用）
- 返却ブロック共通サブセット（status/scope/artifacts/hint）に準拠する
- `status=基本設計著述失敗` は facts 未封印（`seal-facts.sh verify` exit 1）・unit_kind が screen 以外（未実装）・実装用語混入がループ上限内で解消しない等で著述不能な場合
- `unit_kind`（`screen` のみ実装）。他の値を指定された場合も `status=基本設計著述失敗` を返す

### generating-reverse-detailed-design（設計書著述）

- status: `AUTHORED | BLOCKED`
- 拡張: facts_ref（入力で受け取った facts ディレクトリの絶対パスをそのまま転記。下流工程への追跡用）、measurement_pending（⑨実測系として設計書に確定せず画面単位検証へ委譲した項目の一覧）
- 返却ブロック共通サブセット（status/scope/artifacts/hint）に準拠する
- `status=BLOCKED` は facts 未封印（`seal-facts.sh verify` exit 1）・引数不足等で著述不能な場合

### rebuilding-screen-unit-from-docs（ファイル単位検証）

- status: `差し戻し | 再現一致 | 再現不一致`
- 拡張: instruction_doc（修正指示書.md のパス）、handoff_files（画面単位検証で要注意なファイル一覧）、saved_test_paths（本スキルが保存した最終テストコードのパス一覧。設計書リポジトリ `<画面ディレクトリ>/テスト項目書/テストコード/単体/<basename>/` 配下）
- `status=差し戻し` の場合、hint に「generating-reverse-detailed-design を実行してから再起動せよ」等の差し戻し理由を記録する（設計書に対象ファイルの契約が無い・観点表に契約が無い・画面ディレクトリ構造が壊れている等の**内容起因**の理由に限る）
- target_repo_path・target_branch・user-approved 等の必須引数欠落やチェックアウト失敗による**起動不可**は `status=差し戻し` を返さず、Skill 呼び出し自体の失敗として管理者へ即時報告する（generating-reverse-detailed-design の再著述では解消しないため、設計書未著述⇄ファイル単位未検証 ループの対象外）
- 下流引き継ぎ契約: 画面単位検証（rebuilding-code-from-docs）は、上流 rebuilding-screen-unit-from-docs が `saved_test_paths` に保存した単体テストコードを **`reverse_worktree`（rebuilding-code-from-docs が操作する対象コードリポジトリ。rebuilding-screen-unit-from-docs の `target_repo_path` とは別物）へ配置して実行するのみ**とし、単体テストコードの新規作成は行わない

### rebuilding-code-from-docs（画面単位検証・mode分割）

- mode=implement: status = `NEED-COMPARE | INTERNAL-CONTRADICTION | ERROR | BLOCKED`。拡張フィールド compare_request { scope, design_doc（パス）, freeze_commit（凍結コミットのハッシュ）, scenarios_ready（真偽値）}。これは「比較してほしい」を表す専用フィールドで、管理者はこれを見て syncing-reverse-env を sync,dry-run で起動する
- mode=judge: status = `PASS | FAIL | DESIGN-INCOMPLETE | DYNAMIC-UNVERIFIED`。入力 args として compare_result（= syncing-reverse-env の sync,dry-run 返却ブロック全文）を受け取る。拡張: instruction_doc（修正指示書.md）、final_report（最終報告.md）、loop_verdict（発散 / 収束の判定）

### running-reverse-screen-batch（画面単位バッチ実行）

- status: `BATCH-COMPLETE | BATCH-IN-PROGRESS | BATCH-ABORTED`
- `BATCH-COMPLETE`: 全画面の処理が完了（成功件数 + failed リスト退避件数 + conflict-skip リスト退避件数の合計が対象総数に一致）
- `BATCH-IN-PROGRESS`: バックグラウンドループが処理中（PID 生存中）
- `BATCH-ABORTED`: 異常終了（PID 消失かつ残件あり）
- 拡張: failed_screens（failed リストへ退避した画面ID一覧）、conflict_skip_screens（開通競合検知により競合スキップとして退避した画面ID一覧。failed_screens とは別区分で失敗回数にカウントしない）、remaining_count（未検証残数）、log_path（実行ログの絶対パス）
- 返却ブロック共通サブセット（status/scope/artifacts/hint）に準拠する。scope は起動対象画面群を代表する `<system>-batch` を用いる

## args 仕様

各子スキルが単独起動で受け取る引数の全量。単独起動時はユーザーが同じ args を手渡しすれば動く。

- surveying-architecture-for-reverse-docs: target_repo_path, docs_root, template_root, target_branch（任意）, source_ref（任意）, mode（`survey`|`revise`、既定 `survey`）, revise_findings（mode=revise 時のみ必須）
- generating-<種別>-list-for-reverse-docs（種別別一覧スキル6つ共通）: source_dir, output_dir（unit_kind はスキル名で固定されるため引数に無い）, survey_doc_path（任意。unit_kind=screen のみ、Phase 1 共有ファイル・エイリアス調査の裏取り元として使用。他種別は未使用）
- generating-feature-list-for-reverse-docs: source_dir, output_dir, survey_doc_path（任意。ルート定義等の所在特定の参考）
- generating-reverse-common-docs: target_repo_path, docs_root, template_root, survey_doc_path, mode（`v0`|`append`、既定 `v0`）, append_findings（mode=append 時のみ必須）
- syncing-reverse-env: design-doc, mode（setup|sync|teardown）, dry-run, reset-first, user-approved, scenarios, max-loop（既存契約のまま）
- unlocking-reverse-target-screens: system, screen_id, reverse_worktree, ports, docs_root, user-approved
- 注記: 通常経路では `unlocking-reverse-target-screens` が内部から本モードを起動する。管理者が本行を直接使うのは、`unlocking-reverse-target-screens` が `status=UNLOCKED`（部分完了）で差し戻した場合の救済経路のみ
- syncing-reverse-env (mode=registry): system, screen_id, reverse_worktree, ports, user-approved
- extracting-unit-facts-from-code: target_repo_path, target_file_paths, screen_dir, profile（`screen` のみ実装）, survey_doc_path, run_id（任意、既定 `extract-1`）
- generating-reverse-basic-design: screen_dir, docs_root, template_root, scaffold_script_path（管理者が shared/scripts/scaffold-screen.sh を解決して渡す。audit_script_path と同型）, facts_ref, common_docs_root, unit_kind（任意、既定 `screen`。`screen` のみ実装）
- generating-reverse-detailed-design: screen_dir, docs_root, template_root, chapter_map_path, audit_script_path, scaffold_script_path（管理者が shared/scripts/scaffold-screen.sh を解決して渡す。audit_script_path と同型）, facts_ref, common_docs_root, mode, target_file_path（mode=file時）, screenshot_dir（任意・補助情報源）, verification_url（任意・開通時に実レンダリング確認済みのURL。画面レジストリの値を管理者が解決して渡す。scenarios の query/path_params の確定転記に使用する）
- rebuilding-screen-unit-from-docs: screen_dir, target_file_path, docs_root, template_root, audit_script_path, scaffold_script_path（管理者が shared/scripts/scaffold-screen.sh を解決して渡す。audit_script_path と同型）, chapter_map_path, env_block, user-approved
- rebuilding-code-from-docs (mode=implement): screen_dir, scope, reverse_worktree, ports, baseline_tag_status, docs_root, template_root, audit_script_path, chapter_map_path, user-approved, saved_test_paths（上流 rebuilding-screen-unit-from-docs が保存した単体テストコードのパス一覧。管理者が転送する。上流未実施の画面では省略可）
- rebuilding-code-from-docs (mode=judge): screen_dir, compare_result, reverse_worktree, freeze_commit（Phase 8 の compare_request から管理者が保持して転送する。scripts/check-freeze.sh の入力に使う）
- running-reverse-screen-batch: target_repo_path, docs_root, screen_ids, template_root, common_docs_root, survey_doc_path, model（任意、既定 `claude-sonnet-5`）, wait_seconds（任意、既定 3600）, fail_limit_k（任意、既定 3）, log_path（任意、既定 `<verification_dir>/バッチ運転記録/batch-log.txt`）

注記: user-approved（白紙化承認）と docs_root は管理者が事前に解決して args で渡す（完全仲介方式のため子スキルはユーザーに直接聞かない）。

## 無人モード仕様

管理者は `headless: boolean`（既定 false）で無人モードを受け取る。無人モード時は下表の置き換えを適用する。詳細は `RUNBOOK.md`（運転規約）を参照。

### 置き換え表

| 通常モードの挙動 | 無人モードでの置き換え |
|---|---|
| 破壊的操作（白紙化等）のユーザー承認を都度取得する | 起動時フラグで一括付与済みとして扱い、各ゲートで子スキルへ承認済み（user-approved）として渡す |
| AskUserQuestion でユーザーに選択を仰ぐ | 使用しない。スキルと契約書の既定に従い判断を実行し、その判断内容を実行レポートに記録する |
| 「ユーザーに報告して中断」に該当する事象が起きる | 実行レポートに記録し、失敗ステータスで当該画面を終端する。バッチ実行時は次の画面へ進む |
| 設計書ルート（docs_root）が未指定 | 即エラー終端とする（推測補完しない） |
| generating-glossary-for-reverse-docs の二段承認（Phase 1 採録方針・Phase 3 候補一覧の取捨） | 既定値（層化サンプリングの既定分類軸・抽出済み候補の全採用）で自動承認し、承認内容と既定値を実行レポートに明記する |

### headless でも変えないもの

状態判定の決定木・子スキルへの引数全量指定・返却ブロックのステータスのみでの検収・ループ上限と発散検知は、無人モードでも変更しない。無人モードを含む全モードで、各工程は必ず Skill ツールで子スキルを起動する。子スキルの手順を管理者が直接実行することを禁止する。Skill 起動が失敗する場合は失敗として記録し、代替実行しない。

### 安全設計

単一フラグによる包括承認は将来セッションを誤誘導するリスクがあるため採用しない。`headless_approved_ops` をリスト方式で管理し、明示的に列挙された操作のみを承認済みとして扱う。

```yaml
headless_approved_ops: [白紙化, 再実装, タグ更新, 環境撤去]
```

スロット枯渇時の自動回収: headless_approved_ops に `環境撤去` が含まれている場合、スロットが上限に達した時点で「基準確立済み（status=baseline-established）で最も古い環境の軽量解放（プロセス・ポートのみ解放、タグ・成果物は保持する）」を自動実行してスロットを確保する。headless_approved_ops に `環境撤去` が含まれていない場合は従来どおり ERROR で停止する。

### 盲検分離の必須要件

「原本コードを読む工程（Phase 6 の extracting/authoring）」と「設計書のみから再実装・判定する工程（Phase 8-10 の rebuilding/judge）」は、無人モードでは別プロセス（別のヘッドレス呼び出し）に分離する。同一プロセス内で両工程を連続実行することを禁止する。ファイル単位盲検検証（rebuilding-screen-unit-from-docs）は、無人モードでは任意工程ではなく必須工程として扱う。

### 実行レポート

無人モードの実行結果は `<verification_dir>/screen-<画面ID>/<timestamp>/実行レポート.md` に保存する。

### 運転記録の標準配置

running-reverse-screen-batch の実行ログ（`log_path`）・failed リストの既定配置は `<verification_dir>/バッチ運転記録/` 配下とする（既定: `<verification_dir>/バッチ運転記録/batch-log.txt`。複数レーン運用時は `<verification_dir>/バッチ運転記録/batch-log-<lane_id>.txt` / `<verification_dir>/バッチ運転記録/failed-screens-<lane_id>.txt`）。運転記録は検証記録の一種であり docs_root 配下（納品物）には置かない。

### 進捗可視化

無人モード（headless=true）では工程の開始・完了のたびに `<verification_dir>/progress.jsonl` へ JSON 行を追記する（形式: `{"ts":"<ISO8601>","screen_id":"<画面ID>","phase":"<工程名>","status":"started|completed|failed"}`）。呼び出し元セッションや人間はこのファイルの監視で現在工程を把握できる。

### 開通競合検知時の対応

複数レーン・複数実行者が同一プロジェクトの画面群を並行処理する場合、他プロセスが同一画面の作業コピー・devサーバー・画面レジストリ等の共有資産を既に操作中であると検知することがある（開通競合）。開通競合を検知した場合は当該画面を**競合スキップ**として実行レポートに記録し、他プロセスの環境には一切触れず次の画面へ処理を続行する。競合スキップは失敗（failed）とは別区分とし、失敗回数にはカウントしない。

### 前提事実

- ヘッドレス実行では AskUserQuestion は許可指定してもモデルに提示されない（実測）
- TaskCreate と Skill はヘッドレス実行でも利用可能（実測）
- Agent(run_in_background: true) は headless 実行では `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS`（既定 600 秒）でバックグラウンドプロセスが切断される（実測）。headless 時の並列起動は Skill ツールによる逐次実行に切り替える
- **無人モードでは、いかなる工程・用途でも Agent ツールのバックグラウンド起動を使用してはならない。サブエージェントは必ず同期（フォアグラウンド）起動とする**（`CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS` による切断を待つのではなく、そもそもバックグラウンド起動自体を行わない）

## 共有資産の排他

複数レーン・複数実行者が同一プロジェクトを並行処理する場合、以下の2種の共有資産への書き込みを排他制御する。具体コマンドは全子スキル・呼び出し元で共通のこの仕様に従う。

- **ファイル排他（画面レジストリ・一覧配下・progress.jsonl）**: `flock -w 60 <ロックファイル> -c '<書き込みコマンド>'` で排他する（最大60秒待機。タイムアウトした場合は取得失敗としてリトライ、または該当画面を競合スキップとして扱う）
- **worktree 排他（`git worktree add`/`remove`）**: 同一リポジトリへの worktree 操作は `flock -w 120 <リポジトリルート>/.reverse-worktree-ops.lock -c '<git worktree add/remove コマンド>'` で直列化する（最大120秒待機。worktree の作成・削除はファイル排他より時間を要するため待機上限を長く取る）
- **担当画面の重複禁止**: レーン間で同一画面を重複処理しない。担当画面リストの事前分割が正本（分割・レーン別ファイル分離の規約は running-reverse-screen-batch の「並列レーン運用」節）。同一画面の作業中痕跡を検知した場合は「開通競合検知時の対応」の競合スキップに従う

## 状態判定表

成果物の実在から次工程を決める。13状態を漏れなく被覆する。

状態判定の冒頭で、対象画面IDが画面一覧のマニフェスト（`<docs>/一覧/画面一覧/画面一覧.html` 内の embedded JSON の `screens[]` 配列）に存在することを検証する。一覧外IDの場合は (a) 一覧へ kind=`unrouted` として追記してから工程を継続するか (b) エラー終端するかを AskUserQuestion で確認する（headless=true 時は (a) を自動選択する）。

| 状態キー | 実在判定 | 次に起動する子スキル | 渡す主要 args |
|---|---|---|---|
| アーキ未調査 | `<docs_root>/プロジェクト共通/アーキテクチャ調査書.md` が不在、または `check-architecture-survey.sh` の再実行が exit 1 | surveying-architecture-for-reverse-docs | target_repo_path, docs_root, template_root, mode（調査書が不在なら survey。調査書はあるが再実行 exit 1 なら revise・revise_findings必須）（期待返却 調査確定） |
| 一覧未生成 | unit_kinds_present のいずれかの実在種別について `一覧/<種別ラベル>一覧/<種別ラベル>一覧.html` が不在、または excluded-kinds.json に記載の対象外種別について `一覧/<種別ラベル>一覧（該当なし）.md` が不在 | generating-<種別>-list-for-reverse-docs（種別別一覧スキル） | source_dir, output_dir（不在種別ごとに対応スキルを起動） |
| 共通未採録 | プロジェクト共通の10文書（規約4種・共通設計書・メッセージ定義書・DESIGN.md・基盤設計.md・UI共通設計.md・データ設計.md）のいずれか不在、または `check-common-docs.sh` が exit 1 | generating-reverse-common-docs | target_repo_path, docs_root, template_root, survey_doc_path, mode（10文書が未採録なら v0。NG帰着(c)差し戻し時のみ append・append_findings必須）（期待返却 採録v0確定） |
| ポータル未生成 | `<target_repo_path>/project-portal/index.html` が不在 | bash shared/scripts/build-portal.sh | target_repo_path, docs_root, portal_output_dir（固定値: `<target_repo_path>/project-portal`） |
| 基盤ページ未生成（任意） | 用語辞書.html・技術スタック.html・画面遷移図.html・ER図.html・環境実行手順.html のいずれかが docs_root 直下に不在。データ源未整備時はスキップしてよい | generating-tech-stack-for-reverse-docs / generating-env-guide-for-reverse-docs / generating-screen-transition-for-reverse-docs / generating-er-diagram-for-reverse-docs / generating-glossary-for-reverse-docs（不在ページに対応するスキルのみ） | target_repo_path, docs_root, portal_output_dir（任意） |
| 画面未開通 | 画面一覧HTML有・画面が未開通（設計書も基準タグも無い新規画面） | unlocking-reverse-target-screens（内部で基準タグ確立まで完走。`UNLOCKED`差し戻し時のみ管理者がsyncing-reverse-env（mode=registry）を直接起動） | system, screen_id, reverse_worktree, ports, docs_root, user-approved（期待返却 BASELINE-ESTABLISHED） |
| 事実未封印 | `<verification_dir>/screen-<画面ID>/facts/*/facts.lock` が不在、または `seal-facts.sh verify` が exit 1 | extracting-unit-facts-from-code | target_repo_path, target_file_paths, screen_dir, profile=screen, survey_doc_path, run_id（期待返却 封印済み） |
| 基本設計未著述 | `<screen_dir>/基本設計/画面基本設計書.md` が不在 | generating-reverse-basic-design | screen_dir, docs_root, template_root, scaffold_script_path, facts_ref, common_docs_root, unit_kind（期待返却 基本設計著述完了） |
| 設計書未著述 | 画面開通済み・画面ディレクトリ不在 or §15.1 に対象ファイル行なし or 著者スキルの完全性ゲート成果物（画面詳細設計書.md 該当章 + check-fact-coverage 通過記録）不在 or 直近の AUTHORED 返却の facts_ref が現在の封印済み facts と不一致、もしくは `seal-facts.sh verify` が exit 1（facts が再抽出・改変され著述が陳腐化している） | generating-reverse-detailed-design（任意工程） | screen_dir, docs_root, template_root, chapter_map_path, audit_script_path, facts_ref, common_docs_root, mode, target_file_path |
| ファイル単位未検証 | 著述済み（設計書未著述=false）**かつ** 当該ファイルの `<verification_dir>/screen-<画面ID>/単体-<対象ファイルbasename>/` 配下に検証記録が1件以上実在する（＝rebuilding-screen-unit-from-docsに着手済み）**かつ** 直近の記録の `status` が「再現一致」でない。当該ファイルの検証記録が1件も無い場合は着手前（任意工程の未着手）であり本状態を確定させず、基準未確立/往復未検証の判定へ読み飛ばす | rebuilding-screen-unit-from-docs（任意工程。無人モードでは必須工程に上書きされる。「無人モード仕様」の「盲検分離の必須要件」を参照） | screen_dir, target_file_path, 資産paths, env_block, user-approved |
| 基準未確立 | 設計書有・baseline_tag 未確立（syncing setup の baseline_tag が未実施） | syncing-reverse-env（mode=setup → sync） | design-doc, mode=setup |
| 往復未検証 | baseline_tag有・judge の直近記録が PASS でない（judge 未実施の初回と、judge FAIL 後に再 implement 待ちの状態を区別せず同一状態として扱う。いずれも次に起動する子スキルは rebuilding-code-from-docs である）。**例外**: 直近の修正指示書.md が NG帰着(c)（共通文書欠落）に分類され、かつ対応する generating-reverse-common-docs の mode=append 再起動がまだ行われていない場合に限り、次に起動する子スキルを generating-reverse-common-docs（mode=append）に読み替える（詳細は下記「NG帰着3系統の配線」）。修正指示書.md 自体が無い、またはあっても NG帰着(c)以外・追記対応済みの場合はこの読み替えを評価せず、既定の rebuilding-code-from-docs を次に起動する（NG帰着(c)保留の証跡が無いことを「往復未検証＝未実施」の確定根拠とし、推測で個別分岐を補わない） | rebuilding-code-from-docs（mode=implement）→ syncing-reverse-env（mode=sync,dry-run）→ rebuilding-code-from-docs（mode=judge）。ただし上記例外時は generating-reverse-common-docs（mode=append）を先に起動する | screen_dir, scope, reverse_worktree, ports, docs_root（implement）／ design-doc, mode=sync, dry-run（sync,dry-run）／ screen_dir, compare_result, reverse_worktree, freeze_commit（judge）／ 例外時: target_repo_path, docs_root, template_root, survey_doc_path, mode=append, append_findings |
| 検証完了 | rebuilding-code-from-docs judge が status=PASS | syncing-reverse-env（mode=sync 本番で基準タグ更新 / 依頼時 teardown。user-approved 必須） | design-doc, mode=sync, user-approved |

判定は次の順に降りる判定フローで13状態を漏れなく被覆する。

1. アーキテクチャ調査書の実在
2. 各種別の一覧HTML + excluded-kinds.json の実在
3. プロジェクト共通10文書の実在
4. 画面開通有無
5. facts封印の実在
6. 画面基本設計書の実在
7. 設計書/対象ファイル/著者スキルの完全性ゲート成果物の実在
8. 当該ファイルの検証記録の実在有無および再現一致有無
9. syncing setup返却の baseline_tag
10. judge の直近記録および NG帰着(c)保留の有無

「次に起動する子スキル」列は起動する子スキル名のみを記す。mode の選択・分岐条件は必ず「渡す主要 args」列または実在判定列を参照する（子スキル名に mode を併記しない）。

**開通完全性ゲート**: 画面開通有無の判定に用いる画面レジストリの `verification_url` は、実レンダリング確認済みの実URL（「未実施」・エラーページ・プレースホルダでない）でなければならない。この条件を満たさない画面は画面未開通として扱い、facts封印（extracting-unit-facts-from-code）・画面基本設計書著述（generating-reverse-basic-design）・設計書著述（generating-reverse-detailed-design）のいずれにも進まず、先に⑤unlocking-reverse-target-screensによる開通完了を待つ。

アーキ未調査・共通未採録はプロジェクト単位で1回だけ確定させればよく、画面ごとに繰り返さない（一覧未生成以降は画面単位の反復対象）。

ファイル単位未検証が `status=差し戻し` を返した場合は設計書未著述（generating-reverse-detailed-design）へ戻す。

設計書未著述/ファイル単位未検証は任意工程である。設計書が揃い、当該ファイルについて検証記録が1件も無い、または検証記録があり直近の `status` が再現一致の画面は、ファイル単位工程を実行済み・不要のいずれとしてもスキップし基準未確立/往復未検証から開始してよい（実在しない検証記録を「未検証」と誤読しない）。

**無人モードでの上書き**: 上記「任意工程」の扱いは通常モードのものであり、無人モード（headless=true）ではファイル単位未検証（rebuilding-screen-unit-from-docs）を任意工程ではなく必須工程として扱う（正本は「無人モード仕様」の「盲検分離の必須要件」）。無人モードで当該ファイルの検証記録が1件も無い場合もスキップせず必ず実行する。

基本設計未著述は任意工程ではなく必須工程である。`<screen_dir>/基本設計/画面基本設計書.md` が不在のまま設計書未著述・ファイル単位未検証・基準未確立・往復未検証へ進むことを禁止する。管理者の完了条件および最終報告には、対象画面ごとに画面基本設計書.md の実在を含める。

### 種別ループ

管理者は excluded-kinds.json の presentKinds に記載された各種別についてループする。種別ごとの進み方は次のとおり。

- screen: 画面単位でユニット反復（画面未開通〜ファイル単位未検証）〜基準確立〜往復検証を回す
- screen 以外（api / table / batch / report / external）: facts抽出以降の工程（extracting-unit-facts-from-code から往復検証まで）が現時点で未対応のため、一覧確立をもって「後続未対応」の終端状態として記録する

「後続未対応」は excluded-kinds.json の「対象外」（アーキテクチャ調査書で実在しないと判定された種別。後述の3状態の区別を参照）とは別の状態である。「対象外＝そもそも実在しない」のに対し、「後続未対応＝実在し一覧化済みだが facts 抽出に進めない」という違いがある。

一覧生成は全種別について成果物を出す。unit_kinds_present に含まれる種別（present）は一覧HTMLを、含まれない種別（excluded）は `<種別>一覧（該当なし）.md`（判定理由を転記した1枚もの）を必ず生成する。成果物の実在有無だけで各種別の判定を後から復元できる状態を保つ。

管理者の最終報告（Goal）には、全6種別の到達状態レポートを必ず含める。到達状態は次の3値で記す。

| 到達状態 | 意味 |
|---|---|
| 生成済み | 一覧が生成・検証済み（screen はさらに画面単位の反復工程へ進む） |
| 対象外 | アーキテクチャ調査書で実在しないと判定（excluded-kinds.json に記載） |
| 後続未対応 | 実在し一覧化済みだが、facts抽出以降の工程が未対応のため一覧確立の時点で終端 |

管理者の最終報告には、全6種別それぞれについてアーキテクチャ調査書の実在判定（実在する／実在しない・理由）と対応する成果物パス（一覧HTML または `<種別>一覧（該当なし）.md`）を記す種別判定結果の報告義務を含める（書式は orchestrating-reverse-docs-flow SKILL.md の「報告書式（3表テンプレート）」表1を正とする）。

管理者の最終報告には、無人モード（headless=true）実行時に限り、盲検分離の充足状況（同一プロセス実行か・分離実行か）も併せて記載する（正本は「無人モード仕様」の「盲検分離の必須要件」）。

この種別ループは既存13状態の判定を変更しない（screen 以外の種別は一覧確立後に新しい状態へ遷移せず、終端状態の記録のみを行う）。

feature（機能一覧）は種別ループの対象外である。派生一覧のため presentKinds にも excludedKinds にも載らず、Phase 1.7（画面一覧確立後）で生成される。到達状態の報告は 生成済み / 未生成 の2値で行う（表1に feature（派生）行として記載する）。

### §16未解消の扱い（補足）

rebuilding-code-from-docsのPhase2が実行するaudit-consistency.shは§16要確認事項一覧の未解消行数をWARNとして記録する（既定）。既定挙動では管理者の状態判定・次工程遷移に影響しない。管理者が往復検証着手前に§16のゼロ解消を強制したい場合のみ、AUDIT_STRICT_P16=1を設定した上でaudit-consistency.shを実行するようrebuilding-code-from-docsへ指示する（この場合はexit 1となり、Phase2は「内部矛盾あり」としてPhase8へ直行する既存の分岐がそのまま適用される）。

### 基本設計・詳細設計の並列起動

Phase 6 の (b-2) generating-reverse-basic-design と (c) generating-reverse-detailed-design は Agent(run_in_background: true) で並列起動する。両スキルは互いの成果物を参照しない（SKILL.md「予想を裏切る挙動」節で明文化済み）。合流条件は両方の完了ステータス受領。(d) rebuilding-screen-unit-from-docs の `status=差し戻し` は詳細設計のみへ戻す（基本設計への差し戻しは発生しない）。

## 画面完了の定義

画面が「完了」したと判定するには、対象ファイル集合の完全性を満たす必要がある。

- **対象ファイル集合の網羅判定**: エントリ（画面本体）から辿れる画面専有コンポーネントの列挙結果と、画面詳細設計書 §15.1 のファイル分割表が一致していること（両者に取りこぼしが無いこと）
- **部分スコープの明示**: 対象ファイルの一部のみを著述した場合は「部分著述（対象ファイルn件/全m件）」を設計書・画面レジストリ・最終報告に明示し、完全著述と区別する。管理者は部分著述の画面を「検証完了」状態へ遷移させない
- **ルーティング定義ファイルの扱い**: 対象ファイル集合の列挙時、ルーティング定義ファイルは除外する。遷移設計はプロジェクト共通文書（共通設計書）に記載し、画面設計書からは参照で引く

## NG帰着3系統の配線

judge（rebuilding-code-from-docs mode=judge）が `status=FAIL` を返した場合、原因を `shared/references/リバース工程設計.md` の NG帰着3系統いずれかに帰着させる。

| 系統 | 原因 | 管理者の対応 |
|---|---|---|
| (a) 執筆規律不足 | 詳細設計書の執筆規律・転記精度に起因する不一致 | generating-reverse-detailed-design のスキル資産（`references/writing-rules.md` 等）の改訂が必要なため、管理者は自動配線せずユーザーに報告する |
| (b) facts欠落 | 事実抽出プロファイルが対象コードの挙動を捕捉できていない | extracting-unit-facts-from-code のスキル資産（`references/profile-screen.md` 等）の改訂が必要なため、管理者は自動配線せずユーザーに報告する |
| (c) 共通文書欠落 | 共通設計書・規約4種等のプロジェクト共通文書に該当挙動の記載が無い | 管理者が generating-reverse-common-docs を `mode=append`・`append_findings=`（修正指示書.md からの抜粋）で起動する。返却 `status=追記完了` を受けたら Phase 8 ⑦implement へ差し戻す |

(a)・(b) はスキル資産（reference・プロファイル）そのものの改訂を要するため、管理者が代わりに再実行しても解消しない。(c) のみ、管理者が既存の子スキルを再起動するだけで自動的に解消できる。

extracting-unit-facts-from-code が status=共通文書帰着 を返した場合、オーケストレーターは NG帰着(c)（共通文書欠落）と同じルーティングを適用する: generating-reverse-common-docs を mode=append で再起動し、追記完了後に extracting-unit-facts-from-code を再実行する。

## テスト・判定の責務分界

### E2Eテストの責務

E2E（RT-/SM-/IT-/CMP- 系）テストは、作成とベースライン実測を rebuilding-code-from-docs（mode=implement）が担い、実行を syncing-reverse-env の dynamic 検査が担う。この分担は compare_request.scenarios_ready（implement 返却の拡張フィールド）と syncing-reverse-env の scenarios 引数に整合する確定済みの正式仕様であり、未解決の設計課題ではない。

### compare_result.status の解釈責務

syncing-reverse-env は計測事実（static_diff / dynamic / env_check）の報告者であり、往復検証の PASS / FAIL の意味解釈は judge（rebuilding-code-from-docs mode=judge）が単独で担う。管理者は syncing-reverse-env の返却 status を往復検証の合否として扱わず、judge の返却 status のみを合否の正とする。

## 凍結検査の除外リスト

rebuilding-code-from-docs（mode=judge）Phase 9 の凍結検証（`scripts/check-freeze.sh`）は `freeze_commit` 時点の HEAD・作業ツリーとの一致を確認するが、契約はバージョン管理外の生成物配置を「作業ツリー汚染」の判定対象から除外する。除外対象は `node_modules/`・`.next/`・`dist/` 等、ビルド・依存解決の都度再生成される git 管理外ディレクトリに限る（`.gitignore` に列挙されている配置と整合させる）。凍結コミット対象（Phase 3 白紙化リスト内の実装ファイル）自体の変更は除外対象に含めない。

## 実行環境の代替

各子スキルは Skill ツールで起動する。実行環境に専用ワーカー種別（固有名を持つサブエージェント）が存在しない場合は、汎用エージェントにモデルを明示指定した上で代替起動してよい。この代替は契約の状態判定・返却ブロック仕様を変更しない。

## 画面レジストリ

`unlocking-reverse-target-screens` が開通を完了した画面の記帳台帳。原則は管理者が読み書きを担うが、`unlocking-reverse-target-screens` は自ら記帳し自ら `syncing-reverse-env(mode=registry)` を起動して基準タグ確立まで進める。これは完全仲介方式の例外ではなく、基準タグ確立まで単独完走するという設計要件に基づく意図した正式仕様である（理由: 開通の事実を知るのは本スキルだけであり、管理者が能動的に検知できないため）。他の子スキルはこのファイルに直接触れない。

- 正本ファイル: `<docs_root>/一覧/reverse-screen-registry.yml`（スキルフォルダ外の設計書リポジトリ側。スキル同期・上書きコピーの影響を受けない）
- キー: `<system>-<screen_id>`
- 値: `source_ref` / `verification_url` / `design_doc_path` / `status`（`unlocked` → `authored` → `baseline-established` の3段階）
- 管理者は unlocking-reverse-target-screens の返却が `status=BASELINE-ESTABLISHED` であれば追加の記帳作業は不要（既に完了済み）。`status=UNLOCKED`（部分完了）で差し戻された場合のみ、管理者が本ファイルへ記帳し（status=`unlocked`）、続けて syncing-reverse-env を `mode=registry` で起動して基準タグ確立まで進める。確立後は本ファイルの該当エントリの `status` を `baseline-established` に更新する
- `authored`: running-reverse-screen-batch の per-item 前半（unlocking → extracting → basic-design → detailed-design）完了時に書き込まれる中間状態。後半（rebuilding-screen-unit-from-docs → syncing-reverse-env(sync) → rebuilding-code-from-docs(implement/judge)）はこの状態の存在を前提条件として開始する。後半完了で `baseline-established` に上書きされる（正本は running-reverse-screen-batch SKILL.md の「画面1件の処理パイプライン」）

### レジストリ移行手順

前回改修までの一部実装では、画面レジストリの `status` に `verification-pass`（本契約では廃止）を用いていた。旧値が残っている台帳を扱う場合は以下の手順で読み替える。

1. 対象台帳（`<docs_root>/一覧/reverse-screen-registry.yml`）内の全エントリを走査し、`status: verification-pass` を検出する
2. 検出したエントリを `status: baseline-established` に書き換える（`verification-pass` は判定意味論上 `baseline-established` と同一であり、値の統合による情報損失は無い）
3. 書き換え後、旧値 `verification-pass` を格納する第二の台帳・キャッシュ・マーカーが別途存在しないことを確認する（二重台帳化の防止。正本は本ファイル1本のみであり、他ファイルへの転記コピーを残さない）
4. 移行完了後は本契約の状態判定表・マーカー判定（`baseline-established` のみで判定）をそのまま適用してよい。移行前の互換読み替えロジックを恒久的なコード分岐として残さない

## excluded-kinds.json

アーキテクチャ調査書で「実在しない」と判定された種別を記録する成果物。管理者が `一覧/` ディレクトリに書き出す。

### 形式

```json
{
  "generatedAt": "ISO8601",
  "surveyDocPath": "アーキテクチャ調査書の相対パス",
  "allKinds": ["screen", "api", "table", "batch", "report", "external"],
  "presentKinds": ["unit_kinds_present から転記"],
  "excludedKinds": [
    {
      "kind": "種別キー",
      "label": "日本語ラベル",
      "reason": "アーキテクチャ調査書の判定理由を転記"
    }
  ]
}
```

### 3状態の区別

| 状態 | 判定方法 | 意味 |
|---|---|---|
| 生成済み | `一覧/<種別ラベル>一覧/<種別ラベル>一覧.html` が存在 | 一覧が生成・検証済み |
| 対象外 | excluded-kinds.json の excludedKinds に記載あり | アーキテクチャ調査書で実在しないと判定。人間可読の成果物として `一覧/<種別ラベル>一覧（該当なし）.md` も併せて生成する |
| 未着手 | 上記いずれにも該当しない | 一覧生成が未実施 |

feature（機能一覧）は派生一覧のため本ファイルの管理対象外とする。allKinds は6種のまま維持し、feature を追加しない。

## 基盤ページ5枚の出力パス契約

基盤ページ生成スキル5本（下表）は、いずれも `<docs_root>` 直下に固定ファイル名で HTML を書き出す。ファイル名は `shared/scripts/build-portal.sh` の FUTURE_FILES と同値である。不一致はポータルカードが無言で出ない事故になるため機械保証する。

| スキル | 出力ファイル |
|---|---|
| generating-tech-stack-for-reverse-docs | `<docs_root>/技術スタック.html` |
| generating-env-guide-for-reverse-docs | `<docs_root>/環境実行手順.html` |
| generating-screen-transition-for-reverse-docs | `<docs_root>/画面遷移図.html` |
| generating-er-diagram-for-reverse-docs | `<docs_root>/ER図.html` |
| generating-glossary-for-reverse-docs | `<docs_root>/用語辞書.html` |

`portal_output_dir` を指定した場合、各スキルは生成後に `build-portal.sh` を再実行してカードへ反映する。

## スキル資産の修正規律

スキルファイル群は以下の3箇所に存在する。修正は正本のみで行い、配布先・実行先での直接修正を禁止する。

| 場所 | 役割 | 修正可否 |
|---|---|---|
| reverse-docs-skills リポジトリ | 正本 | 修正はここでのみ行う |
| agent-toolkit の payload/reverse-docs-skills/ | 配布中継 | 直接修正禁止（sync-payload.mjs が正本から転写） |
| 実走プロジェクトにデプロイされたコピー | 実行環境 | 直接修正禁止 |

実走中に不具合を発見した場合は、実行環境で応急処置した内容を正本リポジトリに持ち帰り、正本で修正してから再配布する。実行環境のみに留まる修正は次回配布で上書き消失する。

## 設計判断

### check-runbook-presence.sh

**必要性**: `RUNBOOK.md`（運転規約）は本契約文書・`syncing-reverse-env/SKILL.md`・`shared/scripts/check-worktree-commit-guard.sh` の複数箇所から相互参照されており、`RUNBOOK.md` 側の見出し構成変更や参照元の記述変更が起きると死に参照（存在しない見出しの参照・削除済みファイルへの言及）が発生しうる。これを目視レビューだけに委ねると見落としが発生するため、実在・5 見出しの構造・各参照元での言及有無を機械的に突合する self-test を固定化する。

**代替案を採用しなかった理由**:
- Bash ツール直叩き: 5 項目の突合を毎回手書きすると条件がぶれて回帰検証ができない
- 既存 Makefile ターゲット拡張: 本リポジトリに Makefile は存在せず、新規導入は本チェック専用の依存を増やすだけになる
- package.json scripts 追加: 同様に本リポジトリはビルド設定を持たない

**保守責任者**: 人手（ユーザー）。`RUNBOOK.md` の見出し構成、または参照元 3 ファイル（contract.md・syncing-reverse-env/SKILL.md・check-worktree-commit-guard.sh）の記述を変更した場合は本スクリプトも同時に更新する。

**廃棄条件**: `RUNBOOK.md` が廃止された時、または相互参照の整合性検査を別の機構（textlint 等）に統合した時。

## 関連

- `RUNBOOK.md` — 運転規約（推奨配置・起動規約・安全柵・無人モード厳守事項）
- `../../../shared/scripts/check-runbook-presence.sh` — RUNBOOK.md の実在・構造・死に参照解消を検査する self-test スクリプト
