---
name: managing-routines
description: |
  ルーティンの作成・レビュー・テストを一貫管理するハブ。
  TRIGGER when: 「ルーティンを作る/追加/設計」「ルーティンをレビュー/監査」「ルーティンをテスト/検証」「managing-routines」「/schedule 登録」「CronCreate 登録」「ルーティン整備」と言われた時。
  SKIP: スキル作成（→ managing-skills）、hooks 全般（→ managing-hooks）、既存ルーティンの確認・調査のみの時。
invocation: managing-routines
type: orchestration
allowed-tools: [Bash, Read, Write, Edit, Agent, AskUserQuestion, Grep, Glob]
---

# ルーティンライフサイクル管理ハブ

ルーティンの **作成 → レビュー → テスト** を 1 つの動線で担うオーケストレーター。既存の `registering-routines` を吸収し、クラウド Routines（`/schedule`）とローカル CronCreate の両方をカバーする。

## 設計思想

- **クラウドファースト**: Claude Code Routines（Anthropic クラウド）を一級市民とし、ローカル CronCreate はフォールバック
- **プロンプトはコードとして管理**: 実行指示は `実行プロンプト.md` に書く。クラウド UI へのインライン記述は禁止し、ディレクトリを正本とする
- **作りっぱなしを許さない**: 作成直後にレビュー → テストまで自動連鎖
- **完了条件の明示**: 全 Phase・Step に「何をもって完了とするか」を記載させる

## 実行環境の理解（必須前提知識）

| 項目 | クラウド Routines | ローカル CronCreate |
|---|---|---|
| 実行場所 | Anthropic クラウド | ローカルマシン |
| リポジトリ | 毎回 fresh clone | 既存ワーキングツリー |
| ローカルファイル | アクセス不可 | アクセス可 |
| MCP サーバー | コネクタのみ | ローカル設定 |
| 承認プロンプト | なし（完全自律） | セッション設定に従う |
| 最小間隔 | 1 時間 | 1 分 |
| 有効期限 | 永続 | 7 日（セッション依存） |
| 管理 URL | https://claude.ai/code/routines/ | CronList ツール |
| 日次上限 | 撤廃済み（2026年6月時点） | なし |

クラウド Routines の最新仕様は https://claude.ai/code/routines/ を確認すること。

## モード判定

ユーザー発話のキーワードからモードを 1 つ選ぶ。複数候補がある場合は `AskUserQuestion` で確認する。

| 動詞・キーワード | モード | ロードする references | 自動連鎖 |
|---|---|---|---|
| 作る・追加・設計・新規・/schedule・CronCreate | **create** | `conventions.md` + `creating.md` | → review → test |
| レビュー・監査・点検・観点チェック | **review** | `conventions.md` + `reviewing.md` | → test |
| テスト・発火検証・ドライラン | **test** | `conventions.md` + `testing.md` | （連鎖なし） |

判定が曖昧な場合や「全部やって」の場合は **create フル連鎖** に倒す。

## 共通の前段（必ず最初に実行）

1. **進捗の可視化**: 各モードの主要 Phase を `TaskCreate` で登録し、開始時に `in_progress`、完了時に `completed` に切り替える
2. **規約のロード**: `references/conventions.md` を Read する。ディレクトリ構造・プロンプト形式・実行環境判定基準の正本
3. **実行環境の判定**: クラウド Routines かローカル CronCreate かを確定する。判定基準は `conventions.md` に記載

## create モード

1. `references/conventions.md` を Read（規約をロード）
2. `references/creating.md` を Read（手順・チェックリスト）
3. 実行環境を判定（クラウド / ローカル）
4. 対象ルーティンのディレクトリ構造を作成
5. ルーティン設計書.md と 実行プロンプト.md を Write
6. 検証仕様.md を Write（Phase ごとの検証コマンド・合格基準を定義。テスト時にこれを実行して合否判定する）
7. クラウドの場合: `/schedule` の実行指示をユーザーに提示（Claude Code 組込コマンドのため Bash 実行不可）
7. ローカルの場合: CronCreate で登録
8. **自動連鎖**: 続けて review モードへ → test モードへ

連鎖をスキップしたい場合は `AskUserQuestion` で確認。デフォルトは **テストまで連鎖**。

## review モード

1. `references/conventions.md` を Read（規約をロード）
2. `references/reviewing.md` を Read（12 観点・Phase 1〜6）
3. 12 観点で検査を実行:

| 観点 | 検査内容 |
|---|---|
| A. クラウド実行適合性 | fresh clone 前提で動作するか、ローカル依存・allowed_tools 不足がないか |
| B. プロンプト構造 | Phase ごとに完了条件があるか、自律実行ガードがあるか |
| C. ツール依存の解決可能性 | ツール・スクリプトのパス存在確認、シェルコマンドの移植性 |
| D. プロンプト管理方式 | `実行プロンプト.md` が正本か、クラウド UI にインライン記述していないか |
| E. 冪等性 | 途中失敗 → 再実行で副作用・ログが重複しないか |
| F. スコープ逸脱検知 | プロンプトがリポジトリ外の操作を含む場合、コネクタ設定と整合するか |
| G. 実行コスト・時間 | 実行時間が妥当か、不要な頻度で実行されていないか |
| H. 失敗時リカバリ設計 | 通知先・リトライ戦略・手動介入手順・委任先の稼働確認 |
| I. エージェント制御性 | Phase スキップ防止・指示の実行可能性・証跡と未実施の区別 |
| J. ログ・追跡性 | ログフォーマット定義・設計書との整合・before/after 記録・証跡 |
| K. 成果物品質ゲート | lint/型チェック・テスト品質検証・モック方針の記載 |
| L. スコープ制御 | 1 回あたりの処理上限・選択ロジックの公平性・目標戦略の明確さ |

4. レポート出力（CRITICAL / WARN / INFO 件数）
5. 自動修正提案 → ユーザー承認
6. **自動連鎖**: 続けて test モードへ

## test モード

1. `references/testing.md` を Read（テスト手順）
2. Phase 1: プリフライト（push 確認 + trigger_id 特定）
3. `RemoteTrigger action=run` でクラウド即時実行
4. `ScheduleWakeup(270s)` でクラウド完了を待機
5. 復帰時に git fetch → JSONL の run_end 出現を確認（未完了なら再度 ScheduleWakeup）
6. **3 層チェック**:
   - **Layer 1（構造）**: JSONL 6 項目を jq で機械判定（壊れていないか）
   - **Layer 2（行動）**: 各 Phase の detail を実行プロンプトの完了条件と突合 + 成果物（PR/Issue）の実在確認（正しく動いているか）
   - **Layer 3（忠実度）**: コミット規約・マージ判断・ファイル上限の遵守を検査（指示通りか）
7. NG があれば修正 → push → RemoteTrigger 再実行 → ScheduleWakeup でループ
8. Layer 1 全 ○ + Layer 2 [critical] 全 ○ が 2 連続で収束 → 最終レポート出力

**メインセッションが ScheduleWakeup で動的ペーシングしながら直接回す。** クラウド実行は 5〜30 分かかるためサブエージェントでは待機を維持できない。ユーザー介入は正常系ではゼロ。

## 完了条件

| モード | 完了条件 |
|---|---|
| create | 設計書 + 実行プロンプト作成済み。クラウド設定 7 項目確認済み。review に連鎖 |
| review | CRITICAL 0 件。全修正が適用済み。test に連鎖 |
| test | Layer 1〜3 全項目 ○ が 2 連続クリア |

全モード連鎖の Goal: **対象ルーティンがクラウドで全 Phase を完走し、各 Phase が実行プロンプトの意図通りに動作し、成果物が正しく生成される状態を達成する**

## ループ設計（test モード）

| 要素 | 内容 |
|---|---|
| 何を回すか | RemoteTrigger run → ScheduleWakeup 待機 → 3 層チェック → 修正 → push → 再実行 |
| 停止条件 1: 収束 | Layer 1〜3 全項目 ○ が 2 連続 |
| 停止条件 2: 発散 | 同じ NG 項目が 3 回再発 → 構造見直しを提案 |
| 停止条件 3: リソース上限 | 5 回反復で停止 |
| ペーシング | ScheduleWakeup(270s) — キャッシュ TTL 内でポーリング |

## 連鎖の中断制御

各モード境界で自動連鎖する直前に、以下の条件のいずれかを満たす場合は `AskUserQuestion` を出す:

- 直前モードで CRITICAL 級の問題が検出され修正未完了
- 直前モードがユーザー承認待ちで止まった
- ユーザーが事前に「作るだけ」「レビューまで」を明示している

それ以外は **連鎖を継続** が既定動作。

## 連鎖の終端報告

最終モードまで完了したら、以下を日本語で 1 報告にまとめる:

- 対象ルーティン名・実行環境（クラウド / ローカル）
- create 結果: 作成したファイルのパス一覧
- review 結果: CRITICAL / WARN / INFO 件数、修正件数、未対応件数
- test 結果: ドライラン PASS / FAIL、検出された問題
- 健全性判定

## Gotchas

- クラウド Routines は fresh clone で実行される。`~/.claude/` やローカルファイルは一切参照できない
- `/schedule` は Claude Code 組込スラッシュコマンド。Bash からは実行不可だが、`RemoteTrigger` ツールでクラウド即時実行・設定変更は可能
- CronCreate のジョブは 7 日で自動期限切れ。長期運用には再登録が必要
- クラウド Routines のプロンプト値をプログラム的に検証する API は存在しない。skill + hook の予防的アプローチで担保する
- 日次上限は 2026 年 6 月時点で撤廃済み。ただし 5h グリッドは実行密度の最適化として維持する
- CronCreate / クラウド UI の `prompt` には実行手順を書かない。`routines/<name>/実行プロンプト.md を Read し、記載されている全 Phase を順番に実行してください。project は <project> です。` の参照形式のみ許可。クラウド共通プロンプト等の Read は実行プロンプト側の事前準備が担う
- 各ルーティンの結果は JSONL ログ（`logs/<slug>/YYYY-MM-DD.jsonl`）に出力する。issue 起票・Slack 通知は全面禁止。報告は `ルーティン統計レポート` ルーティンが日次 Issue で一元管理する。正本: `common-log-rules.md`

## 参照資料

### このスキルの詳細情報（必要時にロード）

- `references/conventions.md` — ディレクトリ構造・プロンプト形式・実行環境判定基準・命名規則
- `references/creating.md` — 作成手順・設計書テンプレ・実行プロンプトテンプレ・登録方法
- `references/reviewing.md` — 12 観点（A〜L）の詳細・Phase 1〜6・チェック項目・検出パターン
- `references/testing.md` — ScheduleWakeup 動的ループ・RemoteTrigger 即時実行・[critical] 要件・収束基準
- `references/cloud-operations.md` — クラウド Routine の登録・確認・変更手順（7 項目チェックリスト・/schedule コマンド）・検証項目

### ルーティン資産（<project>/routines/）

- `routines/_shared/common-log-rules.md` — JSONL エンベロープ仕様（全プロジェクト共通）
- `routines/<project>/profile.md` — プロジェクトプロファイル（技術スタック・パス・閾値・有効ルーティン一覧）
- `routines/<project>/共通ルール.md` — 12 観点定義・ルーティン一覧・prompt 登録形式
- `routines/<project>/クラウド共通プロンプト.md` — git author・コミット規約・lint 必須等
- `routines/<project>/routines/<name>/` — 各ルーティンの設計書・実行プロンプト

### Phase / Step / TaskCreate の正本

- `~/.claude/skills/skill-design-spec.md` §12 — Phase / Step の書式ルール（orchestration / gateway 型）
- `~/.claude/skills/skill-design-spec.md` §13 — TaskCreate / TaskUpdate の使用ルール（フロー系限定）

### 関連スキル

- `managing-skills` — スキル系の対応ハブ（本スキルと構造は同型・create → review → test 連鎖）
- `managing-hooks` — hooks 系の対応ハブ（同上）
- `naming-conventions` — 命名規則の正本
