---
name: orchestrating-reverse-docs-flow
description: "リバース設計書の往復検証フローを統括。 TRIGGER when: リバース検証の進行・工程統括・画面一覧から基準確立まで。 SKIP: 個別工程の単体実行。"
invocation: orchestrating-reverse-docs-flow
type: orchestration
allowed-tools: [Read, Bash, Grep, Glob, AskUserQuestion, TaskCreate, TaskUpdate, Skill, Agent]
---

# リバース設計書往復検証オーケストレーションスキル

リバース設計書往復検証フローの進行係（管理者）。自分では検証・比較・実装を行わず、状態判定 → 子スキルを args 全量指定で Skill 起動 → 返却ブロックの status で検収 → 次工程決定、というループで工程全体を統括する。

子スキル4つ（generating-screen-list-for-reverse-docs / syncing-reverse-env / rebuilding-screen-unit-from-docs / rebuilding-code-from-docs）は互いを知らず、工程間の受け渡しはすべて本スキルが仲介する（完全仲介方式）。契約の正本は `references/contract.md`。

## 使用タイミング

- リバース検証を工程統括したいとき（画面一覧生成から基準タグ確立までの一連の流れ）
- 個別工程だけを動かしたい場合は各子スキルを単独起動する（各子スキルは同じ args を手渡せば単独でも動く契約）

## 基本ワークフロー

成果物の実在から現在の状態（S0〜S4）を判定し、次に起動する子スキルを機械的に決定する。詳細な実在判定基準・args・返却フィールドの正本は `references/contract.md` の状態判定表を参照。

| 状態キー | 判定の要点 | 次に起動する子スキル |
|---|---|---|
| S0 画面未列挙 | 画面一覧HTMLが不在 | generating-screen-list-for-reverse-docs |
| S1 設計書不足 | 画面一覧HTML有・設計書/対象ファイルが不在（任意工程） | rebuilding-screen-unit-from-docs |
| S2 基準未確立 | 設計書有・baseline_tag 未確立 | syncing-reverse-env（mode=setup → sync） |
| S3 往復未検証 | baseline_tag有・reverse未実装 or 未突合 | rebuilding-code-from-docs（implement）→ syncing-reverse-env（sync,dry-run）→ rebuilding-code-from-docs（judge） |
| S4 検証完了 | judge の status=PASS | syncing-reverse-env（mode=sync 本番 / 依頼時 teardown） |

S1 は任意工程。設計書が揃った画面はファイル単位検証をスキップし S2/S3 から開始してよい。

## 実行手順

### Phase 1: 状態判定

preflight で画面一覧HTML・設計書/対象ファイル・②setup返却の baseline_tag・④judge の status の実在を、上表の順（決定木）で確認し S0〜S4 のいずれかを確定する。確定した状態から必要な工程だけを 1 つずつ TaskCreate する（一括登録禁止）。工程開始時は該当タスクを TaskUpdate で in_progress にし、完了時に completed へ更新する。

完了条件: 状態キー（S0〜S4）が確定し、次に起動すべき子スキルが1つ定まっている

### Phase 2: ①画面一覧生成（S0時）

状態が S0 の場合のみ実行する。Skill で generating-screen-list-for-reverse-docs を source_dir・output_dir 指定で起動する。返却 status=DONE なら screen_list_html（artifacts[0]）を記録して次工程へ進む。status=ERROR なら hint を確認しユーザーに報告して中断する。

完了条件: 画面一覧HTMLが生成され、status=DONE で検収済み

### Phase 3: ②setup（環境ブロック取得）

Skill で syncing-reverse-env を design-doc・mode=setup で起動する。返却ブロックから env_block（docs_root / scope / ports / slot / baseline_tag / original_code / reverse_code）を抽出し、以降の Phase へ引き継ぐ。status が PASS 以外（FAIL / ERROR / INCOMPLETE）の場合は hint を確認して対応し、再実行する。

完了条件: env_block の7フィールドが確定している

### Phase 4: ③ファイル単位検証（S1・任意工程）

状態が S1（from-zero 対象画面が残っている）の場合のみ実行する。Skill で rebuilding-screen-unit-from-docs を screen_dir・target_file_path・docs_root/template_root/audit_script_path/chapter_map_path（資産paths）・env_block・user-approved で起動する。白紙化を伴うため、起動前にユーザーから承認を取得し user-approved として args に含める（管理者が事前確認し、子スキルはユーザーに直接聞かない）。対象ファイル1件ごとに繰り返し、status=CONVERGED まで進める。DIVERGED / INTERNAL-CONTRADICTION / BLOCKED の場合は instruction_doc を確認しユーザーに報告する。

完了条件: from-zero 対象の全ファイルが CONVERGED または NG 分類済み。S1 対象が無ければ Phase 5 へ直行する

### Phase 5: ②sync（基準確立・S2時）

状態が S2 の場合に実行する。Skill で syncing-reverse-env を design-doc・mode=sync で起動する。status=PASS なら基準タグ（baseline_tag）が確立する。FAIL の場合は hint を確認し、設計書修正が必要と判断して Phase 4 またはユーザー報告へ差し戻す。

完了条件: baseline_tag が確立済み（status=PASS）

### Phase 6: ④implement

状態が S3 の場合に実行する。Skill で rebuilding-code-from-docs を mode=implement・scope・reverse_worktree・ports・baseline_tag_status・docs_root・資産paths（template_root/audit_script_path/chapter_map_path）・user-approved で起動する。返却 status=NEED-COMPARE を受領し、拡張フィールド compare_request（scope / design_doc / freeze_commit / scenarios_ready）を取得する。INTERNAL-CONTRADICTION / ERROR / BLOCKED の場合は hint を確認してユーザーに報告し中断する。

完了条件: compare_request が取得済み（status=NEED-COMPARE）

### Phase 7: ②sync dry-run（比較）

Skill で syncing-reverse-env を design-doc・mode=sync・dry-run で起動する。返却される比較結果ブロック（static_diff / dynamic / env_check / status / hint を含む15フィールド全文）をそのまま保持し、次 Phase へ args として渡す。

完了条件: 比較結果ブロックが省略なく取得済み

### Phase 8: ④judge

Skill で rebuilding-code-from-docs を mode=judge・screen_dir・compare_result（Phase 7 の返却ブロック全文）・reverse_worktree・freeze_commit（Phase 6 完了時に compare_request から受け取り保持していた値）で起動する。status=PASS なら Phase 9 へ進む。status=FAIL なら Phase 6 ④implement へ差し戻す（詳細は後述の `## ループ設計`）。DESIGN-INCOMPLETE / DYNAMIC-UNVERIFIED の場合は hint に従い設計書修正または Phase 7 再実行を判断する。

完了条件: PASS / FAIL いずれかに確定している

### Phase 9: ②sync本番/teardown（S4・PASS時）

Phase 8 が PASS の場合のみ実行する。ユーザーから user-approved を取得し、Skill で syncing-reverse-env を design-doc・mode=sync・user-approved で起動して基準タグを本番更新する。検証終了の依頼があった場合は mode=teardown で環境を片付ける（user-approved 必須）。

完了条件: 基準タグが更新済み、または依頼時は teardown が完了している

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 状態キー（S0〜S4）が確定し、次に起動すべき子スキルが1つ定まっている |
| Phase 2 | 画面一覧HTMLが生成され、status=DONE で検収済み |
| Phase 3 | env_block の7フィールドが確定している |
| Phase 4 | from-zero 対象の全ファイルが CONVERGED または NG 分類済み（S1 対象が無ければ直行） |
| Phase 5 | baseline_tag が確立済み（status=PASS） |
| Phase 6 | compare_request が取得済み（status=NEED-COMPARE） |
| Phase 7 | 比較結果ブロックが省略なく取得済み |
| Phase 8 | PASS / FAIL いずれかに確定している |
| Phase 9 | 基準タグが更新済み、または依頼時は teardown が完了している |
| **Goal** | 全対象画面が status=PASS で基準タグ確立、または NG分類済み修正指示書が保存されている |

## サブエージェント委任仕様

| 呼び出し箇所 | invocation | args骨格 | 期待返却status |
|---|---|---|---|
| Phase 2 | generating-screen-list-for-reverse-docs | source_dir, output_dir | DONE |
| Phase 3 | syncing-reverse-env | design-doc, mode=setup | PASS（env_block抽出） |
| Phase 4 | rebuilding-screen-unit-from-docs | screen_dir, target_file_path, 資産paths, env_block, user-approved | CONVERGED |
| Phase 5 | syncing-reverse-env | design-doc, mode=sync | PASS |
| Phase 6 | rebuilding-code-from-docs | mode=implement, scope, reverse_worktree, ports, 資産paths, user-approved | NEED-COMPARE |
| Phase 7 | syncing-reverse-env | design-doc, mode=sync, dry-run | PASS/FAIL（比較結果） |
| Phase 8 | rebuilding-code-from-docs | mode=judge, screen_dir, compare_result, reverse_worktree, freeze_commit | PASS/FAIL |
| Phase 9 | syncing-reverse-env | design-doc, mode=sync／teardown, user-approved | PASS |

Agent（サブエージェント）は preflight の並行事実確認等に限定して用いる。実検証は子スキルへ委ねる。

## ループ設計

| 要素 | 内容 |
|---|---|
| 反復条件 | Phase 8 ④judge が FAIL → Phase 6 ④implement へ戻す |
| 上限回数 | max_loop（既定3。②の max_loop とは別軸の工程ループ） |
| 停止条件 | ① 収束停止: 全対象画面が PASS（2連続で確定）② リソース上限: max_loop 到達で FAIL 確定 ③ 発散検知: ④judge が2連続同一差分（compare_result の static_diff 署名一致）で上限前に打切り |
| 検証役の分離 | 各工程の判定は子スキルの返却ブロック（status）のみで行い、管理者は自然文で判定しない |

この外側ループ（発散判定2連続・上限）は、元々④（rebuilding-code-from-docs）が持っていた責務を管理者へ移管したものである。

## 重要な注意事項

- 子スキルは args 全量指定・対話ゼロで起動する（子は AskUserQuestion を発行しない契約）
- 白紙化などの破壊的操作のユーザー承認は管理者が事前に取り、user-approved として args で渡す（子はユーザーに直接聞かない）
- docs_root が null のときの展開先確認も管理者が担う
- 各子スキルは単独起動可能（ユーザーが同じ args を手渡せば動く）。工程順序を知るのは管理者だけ

## Gotchas

- 状態判定は「画面一覧HTMLの実在 → 設計書/対象ファイルの実在 → ②setup返却の baseline_tag → ④judge の status」の順の決定木。成果物の実在から毎回評価するので中断後も再開できる
- ④は mode で2分割される（implement=比較要求を返して停止 / judge=比較結果を受け取り判定）。管理者がこの2回を別々に起動し、間に②sync dry-run を挟む

## 参照資料

- `references/contract.md` — 返却ブロック契約・args仕様・状態判定表の正本
- 移設済みの共有資産: `assets/リバース検証/`（テンプレート一式）、`scripts/audit-consistency.sh`（工程間ゲート）、`references/chapter-map.md`（章役割キー対応表）
