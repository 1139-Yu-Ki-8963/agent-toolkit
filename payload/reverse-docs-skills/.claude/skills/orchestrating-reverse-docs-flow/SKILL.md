---
name: orchestrating-reverse-docs-flow
description: "リバース設計書往復検証フローを統括。 TRIGGER when: リバース検証の進行・工程統括・画面一覧から基準確立まで。 SKIP: 個別工程の単体実行。"
invocation: orchestrating-reverse-docs-flow
type: orchestration
allowed-tools: [Read, Bash, Grep, Glob, AskUserQuestion, TaskCreate, TaskUpdate, Skill, Agent]
---

# リバース設計書往復検証オーケストレーションスキル

リバース設計書往復検証フローの進行係（管理者）。自分では検証・比較・実装を行わず、状態判定 → 子スキルを args 全量指定で Skill 起動 → 返却ブロックの status で検収 → 次工程決定、というループで工程全体を統括する。

子スキル9つ（surveying-architecture-for-reverse-docs / generating-screen-list-for-reverse-docs / compiling-project-common-docs / syncing-reverse-env / unlocking-reverse-target-screens / extracting-unit-facts-from-code / authoring-screen-docs-from-code / rebuilding-screen-unit-from-docs / rebuilding-code-from-docs）は互いを知らず、工程間の受け渡しはすべて本スキルが仲介する（完全仲介方式）。契約の正本は `references/contract.md`。

## 使用タイミング

- リバース検証を工程統括したいとき（アーキテクチャ調査から基準タグ確立までの一連の流れ）
- 個別工程だけを動かしたい場合は各子スキルを単独起動する（各子スキルは同じ args を手渡せば単独でも動く契約）

## 基本ワークフロー

成果物の実在から現在の状態（アーキ未調査 / 画面未列挙 / 共通未採録 / 画面未開通 / 事実未封印 / 設計書未著述 / ファイル単位未検証 / 基準未確立 / 往復未検証 / 検証完了）を判定し、次に起動する子スキルを機械的に決定する。詳細な実在判定基準・args・返却フィールドの正本は `references/contract.md` の状態判定表を参照。

| 状態キー | 判定の要点 | 次に起動する子スキル |
|---|---|---|
| アーキ未調査 | アーキテクチャ調査書が不在、または機械ゲート再実行が失敗 | surveying-architecture-for-reverse-docs |
| 画面未列挙 | 画面一覧HTMLが不在 | generating-screen-list-for-reverse-docs |
| 共通未採録 | プロジェクト共通7文書のいずれか不在、または機械ゲート再実行が失敗 | compiling-project-common-docs（NG帰着(c)差し戻し時は mode=append） |
| 画面未開通 | 画面一覧HTML有・画面が未開通（設計書も基準タグも無い新規画面） | unlocking-reverse-target-screens（内部で基準タグ確立まで完走。`UNLOCKED`差し戻し時のみ`syncing-reverse-env(registry)`を管理者が直接起動） |
| 事実未封印 | facts.lock が不在、または封印検証が失敗 | extracting-unit-facts-from-code |
| 設計書未著述 | 画面開通済み・画面ディレクトリ不在 or §15.1に対象ファイル行なし or 著者スキルの完全性ゲート成果物不在 or facts更新後の再著述未実施（任意工程） | authoring-screen-docs-from-code |
| ファイル単位未検証 | 著述済み（設計書未著述の成果物実在）かつ当該ファイルの検証記録に再現一致なし（任意工程） | rebuilding-screen-unit-from-docs |
| 基準未確立 | 設計書有・baseline_tag 未確立 | syncing-reverse-env（mode=setup → sync） |
| 往復未検証 | baseline_tag有・reverse未実装 or 未突合 | rebuilding-code-from-docs（implement）→ syncing-reverse-env（sync,dry-run）→ rebuilding-code-from-docs（judge） |
| 検証完了 | judge の status=PASS | syncing-reverse-env（mode=sync 本番 / 依頼時 teardown） |

ファイル単位未検証が `status=差し戻し` を返した場合は設計書未著述へ戻す。設計書未著述/ファイル単位未検証は任意工程。設計書が揃い検証記録に再現一致がある画面はファイル単位工程をスキップし基準未確立/往復未検証から開始してよい。アーキ未調査・共通未採録はプロジェクト単位で1回だけ確定させればよく、画面ごとに繰り返さない。

## 実行手順

### Phase 1: 状態判定

preflight でアーキテクチャ調査書・画面一覧HTML・プロジェクト共通7文書・画面開通状態・facts封印・設計書/対象ファイル・著者スキルの完全性ゲート成果物・当該ファイルの検証記録・⑤setup返却の baseline_tag・⑨judge の status の実在を、上表の順（決定木）で確認し、10状態のいずれかを確定する。確定した状態から必要な工程だけを 1 つずつ TaskCreate する（一括登録禁止）。工程開始時は該当タスクを TaskUpdate で in_progress にし、完了時に completed へ更新する。

完了条件: 状態キー（10状態のいずれか）が確定し、次に起動すべき子スキルが1つ定まっている

### Phase 2: ①アーキ調査（アーキ未調査時）

状態がアーキ未調査の場合のみ実行する。Skill で surveying-architecture-for-reverse-docs を target_repo_path・docs_root・template_root・mode（既存調査書が無ければ survey、下流から検出手がかり欠落を指摘されて差し戻された場合は revise・revise_findings）で起動する。返却 status=調査確定 なら survey_doc_path（artifacts[0]と同値）を記録して次工程へ進む。status=中断 なら hint を確認しユーザーに報告して中断する。

完了条件: survey_doc_path が確定している

### Phase 3: ②画面一覧生成（画面未列挙時）

状態が画面未列挙の場合のみ実行する。Skill で generating-screen-list-for-reverse-docs を source_dir・output_dir 指定で起動する。返却 status=DONE なら screen_list_html（artifacts[0]）を記録して次工程へ進む。status=ERROR なら hint を確認しユーザーに報告して中断する。

完了条件: 画面一覧HTMLが生成され、status=DONE で検収済み

### Phase 4: ③共通採録（共通未採録時）

状態が共通未採録の場合のみ実行する。Skill で compiling-project-common-docs を target_repo_path・docs_root・template_root・survey_doc_path（Phase 2 で確定済み）・mode=v0 で起動する。返却 status=採録v0確定 なら common_docs_root を記録して次工程へ進む。status=中断 なら hint を確認しユーザーに報告して中断する。NG帰着(c)共通文書欠落からの差し戻しでは mode=append・append_findings（修正指示書.md からの抜粋）で再起動し、status=追記完了 を確認する（詳細は `references/contract.md` の「NG帰着3系統の配線」）。

完了条件: common_docs_root が確定している

### Phase 5: ④setup（環境ブロック取得）

Skill で syncing-reverse-env を design-doc・mode=setup で起動する。返却ブロックから env_block（docs_root / scope / ports / slot / baseline_tag / original_code / reverse_code）を抽出し、以降の Phase へ引き継ぐ。status が PASS 以外（FAIL / ERROR / INCOMPLETE）の場合は hint を確認して対応し、再実行する。

完了条件: env_block の7フィールドが確定している

### Phase 6: ユニット反復（画面未開通/事実未封印/設計書未著述/ファイル単位未検証・任意工程含む）

状態が画面未開通・事実未封印・設計書未著述・ファイル単位未検証のいずれかの場合に実行する。

**(a) 画面未開通の場合**: 先に Skill で ⑤unlocking-reverse-target-screens を system・screen_id・reverse_worktree・ports・docs_root・user-approved で起動する。返却 status=BASELINE-ESTABLISHED を受けたら、画面レジストリの記帳・基準タグ確立は本スキル内部で完了済みのため、管理者は追加作業なく次の状態判定（事実未封印等）へ進む。返却 status=UNLOCKED（画面開通は完了したが基準タグ未確立）の場合のみ、画面レジストリ（`~/agent-home/state/reverse-screen-registry.yml`）へ source_ref・verification_url・design_doc_path を記帳し（status=unlocked）、続けて Skill で syncing-reverse-env を mode=registry・system・screen_id・reverse_worktree・ports・user-approved で起動して基準タグ確立まで進める（PASS なら画面レジストリの該当エントリを status=baseline-established に更新）。status=BLOCKED / ERROR の場合は hint を確認しユーザーに報告する。

**(b) 事実未封印の場合**: 画面は開通済みだが対象ファイルの facts が未封印の場合、Skill で ⑥extracting-unit-facts-from-code を target_repo_path・target_file_paths・screen_dir・profile=screen・survey_doc_path・run_id で起動する。返却 status=封印済み を受けたら facts_ref を記録して (c) へ進む。status=中断 の場合は hint を確認しユーザーに報告する。

**(c) 設計書未著述の場合**: 画面は開通済み・facts は封印済みだが対象ファイルの契約が設計書に無い場合、Skill で ⑦authoring-screen-docs-from-code を screen_dir・docs_root・template_root・chapter_map_path・audit_script_path・facts_ref（(b) で取得、または既に封印済みなら流用）・common_docs_root（Phase 4 で取得）・mode・target_file_path で起動する。返却 status=AUTHORED を受けたら (d) へ進む。status=BLOCKED の場合は hint を確認しユーザーに報告する。

**(d) ファイル単位未検証の場合**: 著述済みの対象ファイルについて、Skill で ⑧rebuilding-screen-unit-from-docs を screen_dir・target_file_path・docs_root/template_root/audit_script_path/chapter_map_path（資産paths）・env_block・user-approved で起動する。白紙化を伴うため、起動前にユーザーから承認を取得し user-approved として args に含める（管理者が事前確認し、子スキルはユーザーに直接聞かない）。対象ファイル1件ごとに繰り返し、status=再現一致 まで進める。status=差し戻し（設計書に対象契約なし等の内容起因）の場合は (c) 設計書未著述（authoring-screen-docs-from-code）へ戻す。status=再現不一致 の場合は instruction_doc を確認しユーザーに報告する。target_repo_path 等の必須引数欠落による起動不可は status=差し戻し を返さない Skill 呼び出し失敗として扱われるため、設計書未著述への差し戻しではなく管理者自身の args 供給を見直す（このループの対象外）。

完了条件: 対象ファイルすべてが再現一致または NG 分類済み。対象が無ければ Phase 7 へ直行する

### Phase 7: ⑥sync（基準確立・基準未確立時）

状態が基準未確立の場合に実行する。Skill で syncing-reverse-env を design-doc・mode=sync で起動する。status=PASS なら基準タグ（baseline_tag）が確立する。FAIL の場合は hint を確認し、設計書修正が必要と判断して Phase 6 またはユーザー報告へ差し戻す。

完了条件: baseline_tag が確立済み（status=PASS）

### Phase 8: ⑦implement

状態が往復未検証の場合に実行する。Skill で rebuilding-code-from-docs を mode=implement・scope・reverse_worktree・ports・baseline_tag_status・docs_root・資産paths（template_root/audit_script_path/chapter_map_path）・user-approved で起動する。返却 status=NEED-COMPARE を受領し、拡張フィールド compare_request（scope / design_doc / freeze_commit / scenarios_ready）を取得する。INTERNAL-CONTRADICTION / ERROR / BLOCKED の場合は hint を確認してユーザーに報告し中断する。

完了条件: compare_request が取得済み（status=NEED-COMPARE）

### Phase 9: ⑧sync dry-run（比較）

Skill で syncing-reverse-env を design-doc・mode=sync・dry-run で起動する。返却される比較結果ブロック（static_diff / dynamic / env_check / status / hint を含む15フィールド全文）をそのまま保持し、次 Phase へ args として渡す。

完了条件: 比較結果ブロックが省略なく取得済み

### Phase 10: ⑨judge

Skill で rebuilding-code-from-docs を mode=judge・screen_dir・compare_result（Phase 9 の返却ブロック全文）・reverse_worktree・freeze_commit（Phase 8 完了時に compare_request から受け取り保持していた値）で起動する。status=PASS なら Phase 11 へ進む。status=FAIL なら `references/contract.md` の「NG帰着3系統の配線」に従い分類する。(c) 共通文書欠落なら Phase 4 を mode=append で再起動してから Phase 8 ④implement へ差し戻す。(a) 執筆規律不足・(b) facts欠落 はスキル資産の改訂が必要なためユーザーへ報告する。DESIGN-INCOMPLETE / DYNAMIC-UNVERIFIED の場合は hint に従い設計書修正または Phase 9 再実行を判断する。

完了条件: PASS / FAIL いずれかに確定している

### Phase 11: ⑩sync本番/teardown（検証完了・PASS時）

Phase 10 が PASS の場合のみ実行する。ユーザーから user-approved を取得し、Skill で syncing-reverse-env を design-doc・mode=sync・user-approved で起動して基準タグを本番更新する。検証終了の依頼があった場合は mode=teardown で環境を片付ける（user-approved 必須）。

完了条件: 基準タグが更新済み、または依頼時は teardown が完了している

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 状態キー（10状態のいずれか）が確定し、次に起動すべき子スキルが1つ定まっている |
| Phase 2 | survey_doc_path が確定している（アーキ未調査時のみ） |
| Phase 3 | 画面一覧HTMLが生成され、status=DONE で検収済み（画面未列挙時のみ） |
| Phase 4 | common_docs_root が確定している（共通未採録時のみ） |
| Phase 5 | env_block の7フィールドが確定している |
| Phase 6 | 画面未開通/事実未封印/設計書未著述/ファイル単位未検証 対象の全ファイルが再現一致または NG 分類済み（対象が無ければ直行） |
| Phase 7 | baseline_tag が確立済み（status=PASS） |
| Phase 8 | compare_request が取得済み（status=NEED-COMPARE） |
| Phase 9 | 比較結果ブロックが省略なく取得済み |
| Phase 10 | PASS / FAIL いずれかに確定している |
| Phase 11 | 基準タグが更新済み、または依頼時は teardown が完了している |
| **Goal** | 全対象画面が status=PASS で基準タグ確立、または NG分類済み修正指示書が保存されている |

## サブエージェント委任仕様

| 呼び出し箇所 | invocation | args骨格 | 期待返却status |
|---|---|---|---|
| Phase 2（アーキ未調査時） | surveying-architecture-for-reverse-docs | target_repo_path, docs_root, template_root, mode | 調査確定 |
| Phase 3（画面未列挙時） | generating-screen-list-for-reverse-docs | source_dir, output_dir | DONE |
| Phase 4（共通未採録時） | compiling-project-common-docs | target_repo_path, docs_root, template_root, survey_doc_path, mode | 採録v0確定 |
| Phase 5 | syncing-reverse-env | design-doc, mode=setup | PASS（env_block抽出） |
| Phase 6（画面未開通時） | unlocking-reverse-target-screens | system, screen_id, reverse_worktree, ports, docs_root, user-approved | BASELINE-ESTABLISHED |
| Phase 6（画面未開通・救済時のみ／UNLOCKED差し戻し時） | syncing-reverse-env | mode=registry, system, screen_id, reverse_worktree, ports, user-approved | PASS |
| Phase 6（事実未封印時） | extracting-unit-facts-from-code | target_repo_path, target_file_paths, screen_dir, profile=screen, survey_doc_path, run_id | 封印済み |
| Phase 6（設計書未著述時） | authoring-screen-docs-from-code | screen_dir, docs_root, template_root, chapter_map_path, audit_script_path, facts_ref, common_docs_root, mode, target_file_path | AUTHORED |
| Phase 6（ファイル単位未検証時） | rebuilding-screen-unit-from-docs | screen_dir, target_file_path, 資産paths, env_block, user-approved | 再現一致 |
| Phase 7 | syncing-reverse-env | design-doc, mode=sync | PASS |
| Phase 8 | rebuilding-code-from-docs | mode=implement, scope, reverse_worktree, ports, 資産paths, user-approved | NEED-COMPARE |
| Phase 9 | syncing-reverse-env | design-doc, mode=sync, dry-run | PASS/FAIL（比較結果） |
| Phase 10 | rebuilding-code-from-docs | mode=judge, screen_dir, compare_result, reverse_worktree, freeze_commit | PASS/FAIL |
| Phase 11 | syncing-reverse-env | design-doc, mode=sync／teardown, user-approved | PASS |

Agent（サブエージェント）は preflight の並行事実確認等に限定して用いる。実検証は子スキルへ委ねる。

## ループ設計

| 要素 | 内容 |
|---|---|
| 反復条件 | Phase 10 ⑨judge が FAIL → NG帰着3系統で分類し、(c) 共通文書欠落なら Phase 4（mode=append）を経て Phase 8 ⑦implement へ戻す。(a)/(b) はユーザー報告 |
| 上限回数 | max_loop（既定3。⑧の max_loop とは別軸の工程ループ） |
| 停止条件 | ① 収束停止: 全対象画面が PASS（2連続で確定）② リソース上限: max_loop 到達で FAIL 確定 ③ 発散検知: ⑨judge が2連続同一差分（compare_result の static_diff 署名一致）で上限前に打切り |
| 検証役の分離 | 各工程の判定は子スキルの返却ブロック（status）のみで行い、管理者は自然文で判定しない |

この外側ループ（発散判定2連続・上限）は、元々④（rebuilding-code-from-docs）が持っていた責務を管理者へ移管したものである。

### Phase 6 内: 設計書未著述⇄ファイル単位未検証 ループ

| 要素 | 内容 |
|---|---|
| 反復条件 | rebuilding-screen-unit-from-docs（ファイル単位未検証）が status=差し戻し を返したら authoring-screen-docs-from-code（設計書未著述）へ戻し、再著述後にファイル単位未検証を再実行する |
| 上限回数 | 5回目安（rebuilding-screen-unit-from-docs 自身の内側ループ上限と揃える） |
| 停止条件 | ① 収束停止: rebuilding-screen-unit-from-docs が status=再現一致 を返す ② リソース上限: 5回到達しても差し戻しが続く場合はユーザーに報告する |
| 検証役の分離 | 設計書未著述（著述）とファイル単位未検証（盲検検証）は別スキル・別セッションで実行され、判定は自身の完全性ゲート・6計測の決定的出力のみで行う |

## 重要な注意事項

- 子スキルは args 全量指定・対話ゼロで起動する（子は AskUserQuestion を発行しない契約）
- 白紙化などの破壊的操作のユーザー承認は管理者が事前に取り、user-approved として args で渡す（子はユーザーに直接聞かない）
- docs_root が null のときの展開先確認も管理者が担う
- 各子スキルは単独起動可能（ユーザーが同じ args を手渡せば動く）。工程順序を知るのは管理者だけ

## Gotchas

- 状態判定は「アーキテクチャ調査書の実在 → 画面一覧HTMLの実在 → プロジェクト共通7文書の実在 → 画面開通有無 → facts封印の実在 → 設計書/対象ファイル/著者スキルの完全性ゲート成果物の実在 → 検証記録の再現一致有無 → ⑤setup返却の baseline_tag → ⑨judge の status」の順の決定木。成果物の実在から毎回評価するので中断後も再開できる
- ⑨は mode で2分割される（implement=比較要求を返して停止 / judge=比較結果を受け取り判定）。管理者がこの2回を別々に起動し、間に⑧sync dry-run を挟む
- 画面未開通で画面が未開通の場合、`unlocking-reverse-target-screens` を1回起動するだけで開通〜レジストリ記帳〜基準タグ確立まで完了する（内部で `syncing-reverse-env(mode=registry)` を自ら呼ぶ、完全仲介方式の唯一の例外）。`status=UNLOCKED` で部分完了のまま差し戻された場合のみ、管理者が記帳と `syncing-reverse-env(mode=registry)` 起動を代行する
- 事実未封印〜ファイル単位未検証の間は、extracting-unit-facts-from-code（原本を読む唯一の役）→ authoring-screen-docs-from-code（設計書未著述・著述。原本を読まず facts のみを読む）→ rebuilding-screen-unit-from-docs（ファイル単位未検証・盲検検証。facts も原本も読まない）の順で情報アクセス規律が段階的に狭まる。3スキルを同一スキルに同居させない設計。rebuilding が status=差し戻し を返したら authoring へ戻る
- judge FAIL 時の NG帰着(c)共通文書欠落は管理者が compiling-project-common-docs を mode=append で自動再起動できるが、(a)執筆規律不足・(b)facts欠落 はスキル資産（reference・プロファイル）の改訂を要するため、管理者は自動配線せずユーザーに報告する（`references/contract.md` の「NG帰着3系統の配線」）

## 参照資料

- `references/contract.md` — 返却ブロック契約・args仕様・状態判定表・NG帰着3系統の配線の正本
- 共有資産（本スキル専有ではなくリポジトリ共通、`~/reverse-docs-skills/shared/` 配下）: `shared/templates/リバース検証/`（テンプレート一式）、`shared/scripts/audit-consistency.sh`（工程間ゲート）、`shared/scripts/seal-facts.sh`（facts封印・検証）、`shared/references/chapter-map.md`（章役割キー対応表）、`shared/references/facts-schema.md`（facts.ymlスキーマ正本）、`shared/references/リバース工程設計.md`（Phase/Step×スキル対応の正本）。各子スキルへは template_root / audit_script_path / chapter_map_path として絶対パスを渡す
- 画面レジストリ: `~/agent-home/state/reverse-screen-registry.yml`（正本定義は references/contract.md）
- `unlocking-reverse-target-screens/manifest.yml` — 同スキルが管理するプロジェクト固有値の正本（本スキルは関知しない）
