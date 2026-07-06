# orchestrating-reverse-docs-flow 契約正本

この契約は管理者スキル orchestrating-reverse-docs-flow が正本を持つ。子スキル4つ（generating-screen-list-for-reverse-docs / syncing-reverse-env / rebuilding-screen-unit-from-docs / rebuilding-code-from-docs）は自分の SKILL.md 内で「この契約に準拠する」と宣言するのみで、contract.md 自体は読まず args だけで動く。管理者は各子スキルの返却ブロックを本契約の共通サブセットで検収し、状態判定表に従って次工程を機械的に決定する。これにより管理者と子スキルの間には契約書という単一の仲介点だけが存在し、子スキル同士が互いの内部仕様を知る必要がない完全仲介方式が成立する。

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

### generating-screen-list-for-reverse-docs

- status: `DONE | ERROR`
- 拡張: screen_list_html（= artifacts[0]）、embedded_json_ref（HTML内埋め込みマニフェストJSONへの参照）

### syncing-reverse-env

- status: `PASS | FAIL | ERROR | INCOMPLETE`
- 既存の15フィールド返却ブロックはそのまま正で改変しない。フィールドは: status / mode / scope / screen_id / slot / ports / original_code / reverse_code / baseline_tag / static_diff / dynamic / env_check / artifacts / docs_root / hint
- 管理者が読むのは status / scope / ports / baseline_tag / docs_root / artifacts / hint
- mode=setup の返却からは環境ブロック（env_block）として docs_root / scope / ports / slot / baseline_tag / original_code / reverse_code を抽出する
- mode=sync,dry-run の返却が「比較結果ブロック」= static_diff / dynamic / env_check / status / hint を含む15フィールドそのもの

### rebuilding-screen-unit-from-docs（ファイル単位検証）

- status: `CONVERGED | DIVERGED | INTERNAL-CONTRADICTION | BLOCKED`
- 拡張: instruction_doc（修正指示書.md のパス）、handoff_files（画面単位検証で要注意なファイル一覧）、saved_test_paths（本スキルが保存した最終テストコードのパス一覧。設計書リポジトリ `<画面ディレクトリ>/テスト項目書/テストコード/単体/<basename>/` 配下）
- 下流引き継ぎ契約: 画面単位検証（rebuilding-code-from-docs）は、上流 rebuilding-screen-unit-from-docs が `saved_test_paths` に保存した単体テストコードを **`reverse_worktree`（rebuilding-code-from-docs が操作する対象コードリポジトリ。rebuilding-screen-unit-from-docs の `target_repo_path` とは別物）へ配置して実行するのみ**とし、単体テストコードの新規作成は行わない

### rebuilding-code-from-docs（画面単位検証・mode分割）

- mode=implement: status = `NEED-COMPARE | INTERNAL-CONTRADICTION | ERROR | BLOCKED`。拡張フィールド compare_request { scope, design_doc（パス）, freeze_commit（凍結コミットのハッシュ）, scenarios_ready（真偽値）}。これは「比較してほしい」を表す専用フィールドで、管理者はこれを見て syncing-reverse-env を sync,dry-run で起動する
- mode=judge: status = `PASS | FAIL | DESIGN-INCOMPLETE | DYNAMIC-UNVERIFIED`。入力 args として compare_result（= syncing-reverse-env の sync,dry-run 返却ブロック全文）を受け取る。拡張: instruction_doc（修正指示書.md）、final_report（最終報告.md）、loop_verdict（発散 / 収束の判定）

## args 仕様

各子スキルが単独起動で受け取る引数の全量。単独起動時はユーザーが同じ args を手渡しすれば動く。

- generating-screen-list-for-reverse-docs: source_dir, output_dir
- syncing-reverse-env: design-doc, mode（setup|sync|teardown）, dry-run, reset-first, user-approved, scenarios, max-loop（既存契約のまま）
- rebuilding-screen-unit-from-docs: screen_dir, target_file_path, docs_root, template_root, audit_script_path, chapter_map_path, env_block, user-approved
- rebuilding-code-from-docs (mode=implement): screen_dir, scope, reverse_worktree, ports, baseline_tag_status, docs_root, template_root, audit_script_path, chapter_map_path, user-approved, saved_test_paths（上流 rebuilding-screen-unit-from-docs が保存した単体テストコードのパス一覧。管理者が転送する。上流未実施の画面では省略可）
- rebuilding-code-from-docs (mode=judge): screen_dir, compare_result, reverse_worktree, freeze_commit（Phase 6 の compare_request から管理者が保持して転送する。scripts/check-freeze.sh の入力に使う）

注記: user-approved（白紙化承認）と docs_root は管理者が事前に解決して args で渡す（完全仲介方式のため子スキルはユーザーに直接聞かない）。

## 状態判定表

成果物の実在から次工程を決める。S0〜S4を漏れなく被覆する。

| 状態キー | 実在判定 | 次に起動する子スキル | 渡す主要 args |
|---|---|---|---|
| S0 画面未列挙 | 画面一覧HTML が不在 | generating-screen-list-for-reverse-docs | source_dir, output_dir |
| S1 設計書不足 | 画面一覧HTML有・screen_dir/設計書が不在 or from-zero 対象ファイル未記載 | rebuilding-screen-unit-from-docs（任意工程） | screen_dir, target_file_path, 資産paths, env_block |
| S2 基準未確立 | 設計書有・baseline_tag 未確立（syncing setup の baseline_tag が未実施） | syncing-reverse-env（mode=setup → sync） | design-doc, mode=setup |
| S3 往復未検証 | baseline_tag有・reverse未実装 or 未突合 | rebuilding-code-from-docs（mode=implement）→ syncing-reverse-env（mode=sync,dry-run）→ rebuilding-code-from-docs（mode=judge） | screen_dir, scope, reverse_worktree, ports, docs_root（implement）／ design-doc, mode=sync, dry-run（sync,dry-run）／ screen_dir, compare_result, reverse_worktree, freeze_commit（judge） |
| S4 検証完了 | rebuilding-code-from-docs judge が status=PASS | syncing-reverse-env（mode=sync 本番で基準タグ更新 / 依頼時 teardown。user-approved 必須） | design-doc, mode=sync, user-approved |

判定は「画面一覧HTMLの実在 → 設計書/対象ファイルの実在 → syncing setup返却の baseline_tag → judge の status」の順に降りる決定木で、5状態を漏れなく被覆する。

S1 は任意工程である。設計書が揃った画面はファイル単位検証をスキップし S2/S3 から開始してよい。
