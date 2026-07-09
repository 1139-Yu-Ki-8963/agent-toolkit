# orchestrating-reverse-docs-flow 契約正本

この契約は管理者スキル orchestrating-reverse-docs-flow が正本を持つ。子スキル9つ（surveying-architecture-for-reverse-docs / generating-screen-list-for-reverse-docs / compiling-project-common-docs / syncing-reverse-env / unlocking-reverse-target-screens / extracting-unit-facts-from-code / authoring-screen-docs-from-code / rebuilding-screen-unit-from-docs / rebuilding-code-from-docs）は自分の SKILL.md 内で「この契約に準拠する」と宣言するのみで、contract.md 自体は読まず args だけで動く。管理者は各子スキルの返却ブロックを本契約の共通サブセットで検収し、状態判定表に従って次工程を機械的に決定する。これにより管理者と子スキルの間には契約書という単一の仲介点だけが存在し、子スキル同士が互いの内部仕様を知る必要がない完全仲介方式が成立する。

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

### generating-screen-list-for-reverse-docs

- status: `DONE | ERROR`
- 拡張: screen_list_html（= artifacts[0]）、embedded_json_ref（HTML内埋め込みマニフェストJSONへの参照）

### compiling-project-common-docs（プロジェクト共通採録）

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

- status: `BASELINE-ESTABLISHED | UNLOCKED | BLOCKED | ERROR`
- `BASELINE-ESTABLISHED`（終端成功）: 開通〜画面レジストリ記帳〜`syncing-reverse-env(mode=registry)`起動〜基準タグ確立まで完走し、決定的コマンド出力（`git tag -l "reverse-baseline/<scope>"`等）で確認済み
- `UNLOCKED`（中間・部分完了）: 画面開通は完了したが `syncing-reverse-env(mode=registry)` がPASS以外で基準タグ未確立
- 拡張: source_ref（開通確認時点のコミットハッシュ等、追跡に使う参照）、verification_url（モックAPI経由で画面が表示確認できるURL。未実施なら「未実施」）、design_doc_path（今後の設計書の想定配置パス）、baseline_tag（`BASELINE-ESTABLISHED`時のみ確定。`syncing-reverse-env`返却の`baseline_tag`をそのまま転記）

### extracting-unit-facts-from-code（ユニット事実抽出）

- status: `封印済み | 中断`
- 拡張: facts_ref（facts ディレクトリの絶対パス＋facts.lock の sha256）、pending_measurements（⑨実測委譲キーの一覧）
- `profile=screen` のみ実装。他プロファイル指定時は `status=中断`

### authoring-screen-docs-from-code（設計書著述）

- status: `AUTHORED | BLOCKED`
- 拡張: facts_ref（入力で受け取った facts ディレクトリの絶対パスをそのまま転記。下流工程への追跡用）、measurement_pending（⑨実測系として設計書に確定せず画面単位検証へ委譲した項目の一覧）
- 返却ブロック共通サブセット（status/scope/artifacts/hint）に準拠する
- `status=BLOCKED` は facts 未封印（`seal-facts.sh verify` exit 1）・引数不足等で著述不能な場合

### rebuilding-screen-unit-from-docs（ファイル単位検証）

- status: `差し戻し | 再現一致 | 再現不一致`
- 拡張: instruction_doc（修正指示書.md のパス）、handoff_files（画面単位検証で要注意なファイル一覧）、saved_test_paths（本スキルが保存した最終テストコードのパス一覧。設計書リポジトリ `<画面ディレクトリ>/テスト項目書/テストコード/単体/<basename>/` 配下）
- `status=差し戻し` の場合、hint に「authoring-screen-docs-from-code を実行してから再起動せよ」等の差し戻し理由を記録する（設計書に対象ファイルの契約が無い・観点表に契約が無い・画面ディレクトリ構造が壊れている等の**内容起因**の理由に限る）
- target_repo_path・target_branch・user-approved 等の必須引数欠落やチェックアウト失敗による**起動不可**は `status=差し戻し` を返さず、Skill 呼び出し自体の失敗として管理者へ即時報告する（authoring-screen-docs-from-code の再著述では解消しないため、設計書未著述⇄ファイル単位未検証 ループの対象外）
- 下流引き継ぎ契約: 画面単位検証（rebuilding-code-from-docs）は、上流 rebuilding-screen-unit-from-docs が `saved_test_paths` に保存した単体テストコードを **`reverse_worktree`（rebuilding-code-from-docs が操作する対象コードリポジトリ。rebuilding-screen-unit-from-docs の `target_repo_path` とは別物）へ配置して実行するのみ**とし、単体テストコードの新規作成は行わない

### rebuilding-code-from-docs（画面単位検証・mode分割）

- mode=implement: status = `NEED-COMPARE | INTERNAL-CONTRADICTION | ERROR | BLOCKED`。拡張フィールド compare_request { scope, design_doc（パス）, freeze_commit（凍結コミットのハッシュ）, scenarios_ready（真偽値）}。これは「比較してほしい」を表す専用フィールドで、管理者はこれを見て syncing-reverse-env を sync,dry-run で起動する
- mode=judge: status = `PASS | FAIL | DESIGN-INCOMPLETE | DYNAMIC-UNVERIFIED`。入力 args として compare_result（= syncing-reverse-env の sync,dry-run 返却ブロック全文）を受け取る。拡張: instruction_doc（修正指示書.md）、final_report（最終報告.md）、loop_verdict（発散 / 収束の判定）

## args 仕様

各子スキルが単独起動で受け取る引数の全量。単独起動時はユーザーが同じ args を手渡しすれば動く。

- surveying-architecture-for-reverse-docs: target_repo_path, docs_root, template_root, target_branch（任意）, source_ref（任意）, mode（`survey`|`revise`、既定 `survey`）, revise_findings（mode=revise 時のみ必須）
- generating-screen-list-for-reverse-docs: source_dir, output_dir
- compiling-project-common-docs: target_repo_path, docs_root, template_root, survey_doc_path, mode（`v0`|`append`、既定 `v0`）, append_findings（mode=append 時のみ必須）
- syncing-reverse-env: design-doc, mode（setup|sync|teardown）, dry-run, reset-first, user-approved, scenarios, max-loop（既存契約のまま）
- unlocking-reverse-target-screens: system, screen_id, reverse_worktree, ports, docs_root, user-approved
- 注記: 通常経路では `unlocking-reverse-target-screens` が内部から本モードを起動する。管理者が本行を直接使うのは、`unlocking-reverse-target-screens` が `status=UNLOCKED`（部分完了）で差し戻した場合の救済経路のみ
- syncing-reverse-env (mode=registry): system, screen_id, reverse_worktree, ports, user-approved
- extracting-unit-facts-from-code: target_repo_path, target_file_paths, screen_dir, profile（`screen` のみ実装）, survey_doc_path, run_id（任意、既定 `extract-1`）
- authoring-screen-docs-from-code: screen_dir, docs_root, template_root, chapter_map_path, audit_script_path, facts_ref, common_docs_root, mode, target_file_path（mode=file時）, screenshot_dir（任意・補助情報源）, registry値（任意・補助情報源）
- rebuilding-screen-unit-from-docs: screen_dir, target_file_path, docs_root, template_root, audit_script_path, chapter_map_path, env_block, user-approved
- rebuilding-code-from-docs (mode=implement): screen_dir, scope, reverse_worktree, ports, baseline_tag_status, docs_root, template_root, audit_script_path, chapter_map_path, user-approved, saved_test_paths（上流 rebuilding-screen-unit-from-docs が保存した単体テストコードのパス一覧。管理者が転送する。上流未実施の画面では省略可）
- rebuilding-code-from-docs (mode=judge): screen_dir, compare_result, reverse_worktree, freeze_commit（Phase 8 の compare_request から管理者が保持して転送する。scripts/check-freeze.sh の入力に使う）

注記: user-approved（白紙化承認）と docs_root は管理者が事前に解決して args で渡す（完全仲介方式のため子スキルはユーザーに直接聞かない）。

## 状態判定表

成果物の実在から次工程を決める。10状態を漏れなく被覆する。

| 状態キー | 実在判定 | 次に起動する子スキル | 渡す主要 args |
|---|---|---|---|
| アーキ未調査 | `<docs_root>/プロジェクト共通/アーキテクチャ調査書.md` が不在、または `check-architecture-survey.sh` の再実行が exit 1 | surveying-architecture-for-reverse-docs | target_repo_path, docs_root, template_root, mode（調査書が不在なら survey。調査書はあるが再実行 exit 1 なら revise・revise_findings必須）（期待返却 調査確定） |
| 画面未列挙 | 画面一覧HTML が不在 | generating-screen-list-for-reverse-docs | source_dir, output_dir |
| 共通未採録 | プロジェクト共通の7文書（規約4種・共通設計書・メッセージ定義書・DESIGN.md）のいずれか不在、または `check-common-docs.sh` が exit 1 | compiling-project-common-docs | target_repo_path, docs_root, template_root, survey_doc_path, mode（7文書が未採録なら v0。NG帰着(c)差し戻し時のみ append・append_findings必須）（期待返却 採録v0確定） |
| 画面未開通 | 画面一覧HTML有・画面が未開通（設計書も基準タグも無い新規画面） | unlocking-reverse-target-screens（内部で基準タグ確立まで完走。`UNLOCKED`差し戻し時のみ管理者がsyncing-reverse-env（mode=registry）を直接起動） | system, screen_id, reverse_worktree, ports, docs_root, user-approved（期待返却 BASELINE-ESTABLISHED） |
| 事実未封印 | `<screen_dir>/検証記録/facts/*/facts.lock` が不在、または `seal-facts.sh verify` が exit 1 | extracting-unit-facts-from-code | target_repo_path, target_file_paths, screen_dir, profile=screen, survey_doc_path, run_id（期待返却 封印済み） |
| 設計書未著述 | 画面開通済み・画面ディレクトリ不在 or §15.1 に対象ファイル行なし or 著者スキルの完全性ゲート成果物（画面詳細設計書.md 該当章 + check-fact-coverage 通過記録）不在 or 直近の AUTHORED 返却の facts_ref が現在の封印済み facts と不一致、もしくは `seal-facts.sh verify` が exit 1（facts が再抽出・改変され著述が陳腐化している） | authoring-screen-docs-from-code（任意工程） | screen_dir, docs_root, template_root, chapter_map_path, audit_script_path, facts_ref, common_docs_root, mode, target_file_path |
| ファイル単位未検証 | 著述済み（設計書未著述=false）**かつ** 当該ファイルの `<画面ディレクトリ>/検証記録/単体-<対象ファイルbasename>/` 配下に検証記録が1件以上実在する（＝rebuilding-screen-unit-from-docsに着手済み）**かつ** 直近の記録の `status` が「再現一致」でない。当該ファイルの検証記録が1件も無い場合は着手前（任意工程の未着手）であり本状態を確定させず、基準未確立/往復未検証の判定へ読み飛ばす | rebuilding-screen-unit-from-docs（任意工程） | screen_dir, target_file_path, 資産paths, env_block |
| 基準未確立 | 設計書有・baseline_tag 未確立（syncing setup の baseline_tag が未実施） | syncing-reverse-env（mode=setup → sync） | design-doc, mode=setup |
| 往復未検証 | baseline_tag有・judge の直近記録が PASS でない（judge 未実施の初回と、judge FAIL 後に再 implement 待ちの状態を区別せず同一状態として扱う。いずれも次に起動する子スキルは rebuilding-code-from-docs である）。**例外**: 直近の修正指示書.md が NG帰着(c)（共通文書欠落）に分類され、かつ対応する compiling-project-common-docs の mode=append 再起動がまだ行われていない場合に限り、次に起動する子スキルを compiling-project-common-docs（mode=append）に読み替える（詳細は下記「NG帰着3系統の配線」）。修正指示書.md 自体が無い、またはあっても NG帰着(c)以外・追記対応済みの場合はこの読み替えを評価せず、既定の rebuilding-code-from-docs を次に起動する（NG帰着(c)保留の証跡が無いことを「往復未検証＝未実施」の確定根拠とし、推測で個別分岐を補わない） | rebuilding-code-from-docs（mode=implement）→ syncing-reverse-env（mode=sync,dry-run）→ rebuilding-code-from-docs（mode=judge）。ただし上記例外時は compiling-project-common-docs（mode=append）を先に起動する | screen_dir, scope, reverse_worktree, ports, docs_root（implement）／ design-doc, mode=sync, dry-run（sync,dry-run）／ screen_dir, compare_result, reverse_worktree, freeze_commit（judge）／ 例外時: target_repo_path, docs_root, template_root, survey_doc_path, mode=append, append_findings |
| 検証完了 | rebuilding-code-from-docs judge が status=PASS | syncing-reverse-env（mode=sync 本番で基準タグ更新 / 依頼時 teardown。user-approved 必須） | design-doc, mode=sync, user-approved |

判定は「アーキテクチャ調査書の実在 → 画面一覧HTMLの実在 → プロジェクト共通7文書の実在 → 画面開通有無 → facts封印の実在 → 設計書/対象ファイル/著者スキルの完全性ゲート成果物の実在 → 当該ファイルの検証記録の実在有無および再現一致有無 → syncing setup返却の baseline_tag → judge の直近記録および NG帰着(c)保留の有無」の順に降りる決定木で、10状態を漏れなく被覆する。「次に起動する子スキル」列は起動する子スキル名のみを記す。mode の選択・分岐条件は必ず「渡す主要 args」列または実在判定列を参照する（子スキル名に mode を併記しない）。

アーキ未調査・共通未採録はプロジェクト単位で1回だけ確定させればよく、画面ごとに繰り返さない（画面未列挙以降は画面単位の反復対象）。

ファイル単位未検証が `status=差し戻し` を返した場合は設計書未著述（authoring-screen-docs-from-code）へ戻す。

設計書未著述/ファイル単位未検証は任意工程である。設計書が揃い、当該ファイルについて検証記録が1件も無い、または検証記録があり直近の `status` が再現一致の画面は、ファイル単位工程を実行済み・不要のいずれとしてもスキップし基準未確立/往復未検証から開始してよい（実在しない検証記録を「未検証」と誤読しない）。

### §16未解消の扱い（補足）

rebuilding-code-from-docsのPhase2が実行するaudit-consistency.shは§16要確認事項一覧の未解消行数をWARNとして記録する（既定）。既定挙動では管理者の状態判定・次工程遷移に影響しない。管理者が往復検証着手前に§16のゼロ解消を強制したい場合のみ、AUDIT_STRICT_P16=1を設定した上でaudit-consistency.shを実行するようrebuilding-code-from-docsへ指示する（この場合はexit 1となり、Phase2は「内部矛盾あり」としてPhase8へ直行する既存の分岐がそのまま適用される）。

## NG帰着3系統の配線

judge（rebuilding-code-from-docs mode=judge）が `status=FAIL` を返した場合、原因を `shared/references/リバース工程設計.md` の NG帰着3系統いずれかに帰着させる。

| 系統 | 原因 | 管理者の対応 |
|---|---|---|
| (a) 執筆規律不足 | 詳細設計書の執筆規律・転記精度に起因する不一致 | authoring-screen-docs-from-code のスキル資産（`references/writing-rules.md` 等）の改訂が必要なため、管理者は自動配線せずユーザーに報告する |
| (b) facts欠落 | 事実抽出プロファイルが対象コードの挙動を捕捉できていない | extracting-unit-facts-from-code のスキル資産（`references/profile-screen.md` 等）の改訂が必要なため、管理者は自動配線せずユーザーに報告する |
| (c) 共通文書欠落 | 共通設計書・規約4種等のプロジェクト共通文書に該当挙動の記載が無い | 管理者が compiling-project-common-docs を `mode=append`・`append_findings=`（修正指示書.md からの抜粋）で起動する。返却 `status=追記完了` を受けたら Phase 8 ⑦implement へ差し戻す |

(a)・(b) はスキル資産（reference・プロファイル）そのものの改訂を要するため、管理者が代わりに再実行しても解消しない。(c) のみ、管理者が既存の子スキルを再起動するだけで自動的に解消できる。

## 画面レジストリ

`unlocking-reverse-target-screens` が開通を完了した画面の記帳台帳。原則は管理者が読み書きを担うが、`unlocking-reverse-target-screens` のみ例外として自ら記帳し自ら `syncing-reverse-env(mode=registry)` を起動して基準タグ確立まで進める（理由: 開通の事実を知るのは本スキルだけであり、管理者が能動的に検知できないため）。他の子スキルはこのファイルに直接触れない。

- 正本ファイル: `~/agent-home/state/reverse-screen-registry.yml`（スキルフォルダ外。スキル同期・上書きコピーの影響を受けない）
- キー: `<system>-<screen_id>`
- 値: `source_ref` / `verification_url` / `design_doc_path` / `status`（`unlocked` | `baseline-established`）
- 管理者は unlocking-reverse-target-screens の返却が `status=BASELINE-ESTABLISHED` であれば追加の記帳作業は不要（既に完了済み）。`status=UNLOCKED`（部分完了）で差し戻された場合のみ、管理者が本ファイルへ記帳し（status=`unlocked`）、続けて syncing-reverse-env を `mode=registry` で起動して基準タグ確立まで進める。確立後は本ファイルの該当エントリの `status` を `baseline-established` に更新する
