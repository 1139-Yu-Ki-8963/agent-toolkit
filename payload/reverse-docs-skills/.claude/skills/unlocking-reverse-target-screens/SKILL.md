---
name: unlocking-reverse-target-screens
description: "設計書が無い画面をモックAPIで開通させ、リバース基準タグ確立まで単独で完走する。 TRIGGER when: 画面開通、設計書皆無画面の動作確認、設計書着手前の下準備、基準タグ確立まで含む一気通貫実行。 SKIP: 設計書がある画面の往復検証（→rebuilding-code-from-docs）。"
invocation: unlocking-reverse-target-screens
type: orchestration
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Skill, TaskCreate, TaskUpdate]
---

# 設計書なし画面の開通スキル

このスキルは開通からリバース基準タグ確立までを単独で完走する自己完結型スキルである。開通の事実（どのURLなら検証できるか）を知るのは本スキルだけであり、下流の管理者（orchestrating-reverse-docs-flow）はこの事実を能動的に検知できない。そのため本スキルは例外的に、画面レジストリへの直接読み書きと `syncing-reverse-env` の直接起動を自ら行う（他の子スキルは完全仲介方式に従い、この2点に触れない）。プロジェクト固有の値（パス・コマンド・API名・ポート・画面ID等）は本文に一切書かず、すべて同ディレクトリの `manifest.yml` の `projects.<system>` から取得する。起動経路は二重である。単独起動時はユーザー自身が起点となり、管理者経由時は `orchestrating-reverse-docs-flow` によるS0u（画面未開通）状態の判定が起点となる。これは意図した二重運用であり、単独起動条件・返却ブロック契約への参照は削除すべき旧設計の名残ではない。

## 使用タイミング

- 対象画面にまだ設計書が無く、既存コードがログインを要求するなどの理由でそのままでは動作確認できないとき
- 起動引数は system・screen_id・reverse_worktree・ports・docs_root・user-approved の全量（管理者から渡される。単独起動時はユーザーから直接取得してよい。`user-approved` は Phase 5 で `syncing-reverse-env(mode=registry)` へ転送するため必須）
- 対象プロジェクトの `manifest.yml` に `projects.<system>` エントリが無い、または未確定キー（`<FILL:...>`）が残っている場合は `assets/manifest-template.yml` を複製してまず埋める（前提ゲートで検出・差し戻し）
- 設計書が既にある画面はこのスキルの対象外（`rebuilding-screen-unit-from-docs` / `rebuilding-code-from-docs` を使う）

## 実行手順

### 前提ゲート

`manifest.yml` の `projects.<system>` を読み込む。エントリ不在、または値に未確定トークン（`<FILL:...>`）が1つでも残っていれば `status=ERROR` とし、hint に不足キー一覧と `assets/manifest-template.yml` への案内を記して停止する。値の穴埋めは実行者自身が推測して行わない。人間または呼び出し元が `assets/manifest-template.yml` を複製して実値を埋めてから前提ゲートを再実行する（本スキルの自己完結性は「開通〜基準タグ確立」の作業範囲に限られ、manifestのブートストラップ自体は対象外）。`manifest.<system>.repo_and_launch` に従い、対象リポジトリで dev サーバーを自分で起動する（稼働中の他エージェントのサーバーには接続・干渉しない）。画面レジストリ（`manifest.<system>.handoff.screen_registry_path`）を `<system>-` プレフィックスで検索し、該当エントリが1件も無い（今回が最初の1枚目である）ことを確認できた場合は、次の健全性確認を省略し、devサーバー起動確認のみで前提ゲートを通過してよい。それ以外の場合は `manifest.<system>.reference_screen`（開通済みの健全性確認用画面）を、自分が起動したサーバー上でブラウザ自動化により表示確認する。失敗したら環境自体の不備として `status=ERROR` で停止する（この画面自体の開通作業には進まない）。

TaskCreate で本前提ゲートを含む全Phase分のタスクを1つずつ登録し、各Phase開始時にTaskUpdateでin_progressに更新する。

完了条件: (a) manifest必須キー全確定 (b) devサーバー起動確認 (c) リファレンス画面の健全性確認PASS の3点がすべて満たされている（開通済み画面が1件も無い最初の1枚目の場合は(c)を省略可）

### Phase 1: API依存の特定

画面本体のソースコード一式（ルーティング定義・画面コンポーネント・APIクライアント）を Grep/Glob で特定する。画面が取り込む共有ゲート部品（年度・組織セレクタ等、`manifest.<system>.api_dependency_entrypoints.shared_gate_components` が示す箇所）を、実際の import 等の取り込み記述から辿り、これらが呼ぶAPIも対象に含める（推測で決めつけない）。各APIについて `manifest.<system>.api_source_of_truth.definition_root`（型定義・OpenAPI等の正本）でワイヤ上の実名を確認する（コード生成名と実名は大小文字が食い違うことがある点に注意）。URLパラメータ・ストア値・セッションキーを列挙する。セッションキーは「いつ埋まるか」（同期的初期投入 / 非同期処理）まで確認する。

完了条件: API一覧（画面本体分＋共有ゲート部品分）・実名対応表・URLパラメータ/ストア値/セッションキー（充足タイミング付き）の一覧が記録済み

### Phase 2: 認証・権限基盤の登録

セッションキーの存在確認はブラウザ自動化での実測とする（静的読解だけで済ませない）。`manifest.<system>.auth_session_permission.identifier_field_check` が指す、認証系APIが読む識別子フィールドについて、キーの存在だけでなく値が空でないことまで確認する。`manifest.<system>.auth_session_permission.permission_chain_layers`（route guard / APIミドルウェア / UI表示条件等）の各層に対象画面のエントリを登録する。

完了条件: セッションキー実測結果（充足済み・識別子フィールド非空を確認済み）、権限チェーン各層への登録完了

### Phase 3: 画面別モック実装

`manifest.<system>.mock_conventions`（有効化方法・配置規約・登録方法）に従い、Phase 1 で特定したAPI一覧にモックを実装する。実装後、登録した名前の一覧と `api_source_of_truth` の実名一覧を機械的に突合し、差分ゼロを完了条件とする（自然文の目視確認で済ませない）。モック変更はホットリロードで反映されないことがあるため、反映確認は必ずサーバー再起動後に行う。具体的な実装レシピ（正本からの書き写し方・消費側からの逆引き特定・型決定基準・同名API分岐の判断基準）は `references/mock-implementation-recipe.md` を参照する。

完了条件: 登録名一覧×実名一覧の突合差分ゼロ、サーバー再起動後の反映確認済み

### Phase 4: 検証ループ

ブラウザ自動化で実データ表示を確認する。失敗症状は「クエリ未発火」「権限エラー」に加え「画面全体のクラッシュ（エラー境界への遷移）」を明示する。クラッシュはクエリ記録では検知できないため、ページの `pageerror` イベントから診断する。差分が見つかれば原因のPhase（1/2/3）へ戻る。スクリーンショットまたはログ抜粋を伴わない合格判定は禁止。未検証項目は「未検証」と明記する。検証ループの反復規律は下記「ループ設計」に従う。

完了条件: 収束条件を満たすか、発散/上限到達により `status=BLOCKED` が確定している

### Phase 5: 基準確立への引き渡し

開通状態をコミットする（コミットメッセージ:「【機能追加】<画面名> をモックAPIで開通」）。開通確認時点のコミットハッシュを `source_ref` とする。画面を表示確認できたURLを `verification_url` とする（ローカル起動できず確認手段が無ければ「未実施」と明記する）。`docs_root` 起点で `<system>-<screen_id>` 相当のパスを組み立てて `design_doc_path`（今後の設計書の想定配置パス）とする。画面レジストリ（`manifest.<system>.handoff.screen_registry_path`。既定は `~/agent-home/state/reverse-screen-registry.yml`。contract.mdの正本と一致させる）へ `source_ref`・`verification_url`・`design_doc_path`・`status=unlocked` を記帳する。`Skill` で `syncing-reverse-env` を `mode=registry`・`system`・`screen_id`・`reverse_worktree`・`ports`・`user-approved` で起動する。

返却 `status=PASS` なら、画面レジストリの該当エントリを `status=baseline-established` に更新し、`git tag -l "reverse-baseline/<scope>"` 等の決定的コマンド出力でタグ確立を確認する（自然文の自己申告で完了と判定しない）。確認できたら `status=BASELINE-ESTABLISHED` で返却する（返却フィールドに `baseline_tag` を追加し、`syncing-reverse-env` の返却値をそのまま転記する）。返却が `PASS` 以外（`FAIL`/`ERROR`/`INCOMPLETE`）の場合は、画面レジストリを `status=unlocked` のまま残し、`status=UNLOCKED`（部分完了）で hint に理由を記して差し戻す。

完了条件: レジストリ登録済み、かつ（成功時のみ）`git tag -l` 等の決定的出力でタグ確立を確認済み

## 完了条件

| Phase | 完了条件 |
|---|---|
| 前提ゲート | manifest必須キー全確定・devサーバー起動確認・リファレンス画面健全性確認PASS（開通済み画面が1件も無い最初の1枚目の場合は健全性確認を省略可） |
| Phase 1 | API一覧（画面本体＋共有ゲート部品分）・実名対応表・URLパラメータ/ストア値/セッションキー一覧が記録済み |
| Phase 2 | セッションキー実測結果・識別子フィールド非空確認・権限チェーン各層への登録完了 |
| Phase 3 | 登録名一覧×実名一覧の突合差分ゼロ、サーバー再起動後の反映確認済み |
| Phase 4 | 収束条件を満たすか、発散/上限到達で status=BLOCKED 確定 |
| Phase 5 | 画面レジストリ登録済み、`git tag -l` 等の決定的出力でタグ確立を確認済み（PASS以外なら status=UNLOCKED で差し戻し） |
| **Goal** | `status=BASELINE-ESTABLISHED`（開通〜レジストリ登録〜基準タグ確立まで完走、決定的コマンド出力で確認済み）。Phase5でsyncing-reverse-envがPASS以外なら `status=UNLOCKED` で部分完了として差し戻す |

## ループ設計

| 要素 | 内容 |
|---|---|
| 反復対象 | Phase 4（検証ループ）。差分が見つかればPhase 1/2/3のいずれかへ戻り再実行 |
| 上限回数 | 3回（`rebuilding-code-from-docs` 外側ループ・`syncing-reverse-env/config.yml` の `max_loop` 既定と整合） |
| 収束条件 | 「画面が要求する値とモックデータの突合差分ゼロ」かつ「ブラウザ自動化での実データ表示確認PASS」が2連続で確認できた場合 |
| 発散条件 | 同一差分（同一クエリ未発火／同一権限エラー／同一エラー境界遷移）が2連続で再発した場合、原因と推定されるPhase（1/2/3）まで巻き戻し、それでも3回目に達したら発散確定 |
| 上限到達時の報告 | `status=BLOCKED` とし、hint に「未解消の差分内容」「試行履歴（何を変えて何度試したか）の要約」「推定原因Phase」を記してユーザーに報告する。TaskUpdate で該当タスクを進行中断状態に更新する |

## 「同一条件で成功と失敗が混在する」場合の対処

1. 直ちにレース条件と断定しない
2. まず「チェックが実行されれば確実に失敗するデータ欠落が、チェック自体のスキップというタイミングの穴で時々成功して見える」可能性を排除する: Phase 1 で列挙した画面要求値（URLパラメータ・ストア値・セッションキー）の一覧と、Phase 3 で実装したモックデータの一覧を機械的に突合する
3. 突合で不一致（画面が要求する値にモック側の対応が無い等）が見つかれば「データ欠落」と確定し、発散カウントには含めずPhase 3へ差し戻す（原因が特定できたやり直しのため）
4. 突合が完全一致してもなお混在する場合のみ、次の対処に進む: 同一シナリオを3回連続実行し多数決を取る。1回でも失敗が出たら「モック側の非同期タイミング（データ投入とクエリ発火の順序保証が無い）」を疑い、モックを固定遅延無し・即時応答型に修正して再検証する。それでも混在が解消しない場合は `status=BLOCKED` とし、hint に「モック実装ではなくアプリ側の真のレースコンディションの疑いあり」と明記してユーザーに報告する

## サブエージェント委任仕様

| 呼び出し箇所 | invocation | args骨格 | 期待返却status |
|---|---|---|---|
| Phase 5 | syncing-reverse-env | mode=registry, system, screen_id, reverse_worktree, ports, user-approved | PASS |

本スキルは唯一、他子スキル（syncing-reverse-env）を直接起動する子スキルである。これは完全仲介方式に対する意図的な例外として本スキル内でのみ許容される。

## 重要な注意事項

- **変更してよい範囲**: モックの実装・開発用の起動時初期化処理（devサーバー起動スクリプト等）・設定ファイル（`manifest.<system>` に記載された範囲、および Phase 2 で対象画面を権限チェーンの既存許可リストへ追記登録する作業を含む）のみ。画面・業務ロジック・共通処理などアプリケーション本体のコードを新規実装・改変することは対象外（リバース対象の原本性を損なうため）。検証がうまくいかない根本原因がアプリ本体側の実装にあると判明した場合は、コードを書き換えるのではなく、その事実を開通記録（`handoff.unlock_record_dir`）に書き残しユーザーの判断に委ねる。
- 本スキルは例外的に画面レジストリへの直接読み書きと `syncing-reverse-env` の直接起動を行う（理由: 開通の事実を知るのは本スキルだけであり、下流が能動的に検知できないため）
- プロジェクト固有値（パス・コマンド・API名・ポート・画面ID等）は本文・references に一切書かない。すべて `manifest.yml` の `projects.<system>` から取得する
- 健全性確認は自分が起動したサーバー上でのみ行う。稼働中の他エージェントの環境には触れない
- 合格判定は自然文の自己申告でなく、決定的コマンド出力（`git tag -l` 等）で行う
- 責務は「基準タグ確立まで」。往復検証（設計書との突合精度）自体は本スキルの対象外（それは `rebuilding-code-from-docs` の責務）

## 完了報告

`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（作業報告型）に従う。

固有の検証行:
- 前提ゲート通過状況（manifest全キー確定・devサーバー起動・リファレンス画面健全性、または最初の1枚目省略）
- Phase 3の登録名×実名突合差分件数
- Phase 4検証ループの収束/発散判定結果
- Phase 5のレジストリ登録状況と`baseline_tag`（`status=BASELINE-ESTABLISHED`到達時のみ）

## Gotchas

一般的な症状別の切り分け（詰まりパターン）は `references/troubleshooting-patterns.md` を参照する。以下は同ファイルに寄せていない個別の注意点。

- 設計書がある画面は対象外（`rebuilding-screen-unit-from-docs` / `rebuilding-code-from-docs` を使う）
- モック変更はホットリロードで反映されないことがある。反映確認は必ずサーバー再起動後に行う
- コード生成名とワイヤ上の実名は大小文字が食い違うことがある。実名は `api_source_of_truth.definition_root` で確認する
- manifest に未確定キー（`<FILL:...>`）が残ったまま作業を開始してはならない
- manifestの穴埋めは実行者ではなく人間・呼び出し元の責任。実行者が値を推測して埋めてはならない
- 対象プロジェクトの最初の1枚目を開通する場合、`reference_screen` による健全性確認は省略してよい（開通済み画面が存在しないため）

## 参照資料

- `~/reverse-docs-skills/.claude/skills/orchestrating-reverse-docs-flow/references/contract.md` — 返却ブロック契約・args仕様・画面レジストリの正本（例外条項含む）
- `manifest.yml`（本スキル同梱） — プロジェクト固有値の正本
- `manifest.local.yml`（同ディレクトリ・任意） — 存在する場合、`manifest.yml` を基底として `manifest.local.yml` を深いマージ（local 優先）で重ねた結果を有効値とする。実プロジェクトの絶対パス入り `projects` エントリは `manifest.local.yml` にのみ記載する（`.gitignore` 済みのため公開 payload に載らない）。`operating_rules` 等の枠組みキーの上書きは不可
- `assets/manifest-template.yml`（本スキル同梱） — manifest未整備プロジェクト向け雛形
- `references/mock-implementation-recipe.md`（本スキル同梱） — Phase 3のモック実装レシピ（正本からの書き写し・消費側からの逆引き特定・型決定基準・同名API分岐の判断基準）
- `references/troubleshooting-patterns.md`（本スキル同梱） — 症状・原因・対処の詰まりパターン集（プロジェクト非依存分。プロジェクト固有は `manifest.yml` の `known_gotchas`）
- `~/reverse-docs-skills/.claude/skills/syncing-reverse-env/config.yml` — Playwright実行系設定（`playwright_exec` 等）の共有正本。本スキルは重複定義しない

## 改訂完了時の機械チェック

編集完了後、以下のようなgrepコマンドを実行しゼロヒットを確認する。このリポジトリ自体は具体値を持たないため、実運用では配布先プロジェクトが実際に埋めた値を対象に同種のgrepを実施する。

```
grep -riE '<実プロジェクト名>|<実ポート番号>|<実API名>|<実画面ID>' \
  .claude/skills/unlocking-reverse-target-screens/SKILL.md \
  .claude/skills/unlocking-reverse-target-screens/references/*.html
```
