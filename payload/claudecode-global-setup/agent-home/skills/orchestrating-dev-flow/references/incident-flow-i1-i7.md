# インシデント独自フロー（I1〜I7）

P0 障害（本番ダウン・全員ログイン不能・データ消失）の緊急復旧専用フロー。worktree 儀式・設計書・モック・並列レビューを省き、復旧速度を最優先する。

Phase 1-2（ルート判定・ブランチ準備）の後、本フローに分岐する。

## I1: 障害状況の確認

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh I "インシデント独自フロー（I1-I7）" 1 7 "障害状況の確認"`

- 何が壊れているか（症状）
- いつから壊れているか
- 影響範囲（ユーザー数・機能範囲）
- 直前のデプロイ・変更との関連

**完了**: 障害状況（症状・発生時期・影響範囲・直前変更との関連）が把握されていること

## I2: 再現確認

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh I "インシデント独自フロー（I1-I7）" 2 7 "再現確認"`

- ローカル環境での再現を試みる
- 再現できない場合はログ・メトリクスから根本原因を推定する
- 共通 handoff の userCorrections・priorFailures・actionable findings を全件、既存 I2 の指摘対応表へ入れる
- priorFailures を先に再現し回帰テスト化する。再現不能なら証拠と理由を対応表へ記録する
- handoff と対応表を正規 artifact `.claude/dev-flow/handoff-and-coverage.json` に保存する
- `validate-handoff-coverage.mjs implementation .claude/dev-flow/handoff-and-coverage.json` が PASS するまで I3 を開始しない

**完了**: ローカルでの再現確認または根本原因の推定が完了していること

## I3: 修正実装

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh I "インシデント独自フロー（I1-I7）" 3 7 "修正実装"`

- 最小限の修正で復旧を目指す
- TDD サイクル自体は省略可だが、I2 の既知 FAIL 回帰テストは省略不可
- 新 FAIL は原因を対応表へ追加し、回帰テストを追加した後だけ再実装する
- 恒久対策ではなく暫定復旧を優先する

**完了**: 最小限の修正が実装されていること

## I4: 本番操作承認（唯一の停止点）

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh I "インシデント独自フロー（I1-I7）" 4 7 "本番操作承認"`

EnterPlanMode でプランモードに入り、操作計画をユーザーに提示する。ExitPlanMode で承認を得る。

本番操作は安全な手段のみ許可する。生コマンドの直接実行は禁止。

**完了**: 操作計画が ExitPlanMode でユーザーに承認されていること

## I5: デプロイ・適用

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh I "インシデント独自フロー（I1-I7）" 5 7 "デプロイ・適用"`

承認された修正をデプロイする。

**本番操作の制約:**
- 本番環境への操作は `prod-op-plan.sh` 等のプロジェクト側が用意した安全な手段のみ許可する
- 生コマンド（`psql` 直叩き、`curl` で API 直接呼び出し等）の直接実行は禁止
- 操作計画を事前に提示し、承認を得てから実行する

**完了**: 承認済みの修正がデプロイされていること

## I6: 復旧確認（停止チェックポイント）

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh I "インシデント独自フロー（I1-I7）" 6 7 "復旧確認"`

復旧を確認できたら、以降の手続きを構造的に停止してよい。

確認項目:
- 障害症状が解消しているか
- メトリクスが正常値に戻っているか
- 影響を受けたユーザーが復旧しているか

**完了**: 障害症状が解消し、メトリクスが正常値に戻っていることが確認されていること

## I7: 事後処理

> `bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh I "インシデント独自フロー（I1-I7）" 7 7 "事後処理"`

復旧確認後、以下を実行する:
- I2/I3 で追加した全回帰テストの実行と PASS 確認（完了前必須）
- 指摘対応表の全行を verified にし、coverage-completion validator を通過
- ポストモーテムの起票（任意）

完了後は Phase 7（完了チェック）へ合流し、Phase 8 で commit・push と、`publication.required: true` の場合の publication validator を必ず通過する。その後 Phase 9（PR 作成）、Phase 10（マージ後処理）、Phase 11（メイン同期）へ進む。

**完了**: 全回帰テストと coverage-completion validator が PASS し、Phase 7 に合流していること

## 完了条件

| Step | 完了条件 |
|---|---|
| I1 | 障害状況（症状・影響範囲・直前変更）が把握されていること |
| I2 | 対応表・既知 FAIL 回帰テスト・implementation validator が完了 |
| I3 | 新 FAIL も対応表と回帰テストへ反映し、最小修正が実装済み |
| I4 | 本番操作が承認されていること（ExitPlanMode 通過） |
| I5 | デプロイが完了していること |
| I6 | 復旧が確認されていること（メトリクス正常） |
| I7 | 全回帰テスト PASS・全行 verified・Phase 7 への合流準備が完了 |
| **Goal** | **障害が復旧し、修正が main にマージされていること** |

## 設計思想

- 2026-06-05 の P0 障害（8 時間超の膨張）を教訓に設計
- 平時フローの Phase を流用せず、独自の I1〜I7 で最短経路を確保する
- I6 の停止チェックポイントにより、復旧確認後に不要な手続きを省略できる

## 参照コンテキスト

### プロジェクト固有（flow-values.yml）
（なし）

### グローバル規約
- response-guard-rules — ユーザー操作依頼禁止・先送り禁止
- no-premature-deferral-rules — 作業先送り禁止

### グローバル hook
- check-no-delegation-pre-bash.sh [NO-DELEGATION-BLOCK] — 対話必須コマンド block（PreToolUse）

### 進捗管理
- Phase I 開始時: 全 7 Step（I1〜I7）を TaskCreate
- 各 Step 開始時: TaskUpdate(in_progress)
- 各 Step 完了時: TaskUpdate(completed)
- I7 完了時: Phase 7 の references を先読みし、Phase 7 の全 Step を TaskCreate
