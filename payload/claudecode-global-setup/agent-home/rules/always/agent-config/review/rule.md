# managing スキル実行ゲート（MANAGING-REVIEW-GATE）

managed ディレクトリ（skills/、rules/、routines/、tools/hooks/）のファイル編集時に、統合スキル `managing-agent-configs` の該当種別でのレビュー・テスト実行を機械強制する規約。

## 対象ディレクトリと種別の対応

`managing-agent-configs` は種別（asset_type）を引数に取る統合ハブ。旧 `managing-skills` / `managing-hooks` / `managing-rules` / `managing-routines` / `managing-subagents` を吸収した。

監視パスの定義は `~/agent-home/tools/hooks/shared/marker-path.sh` の `managed_asset_type()`。下表と乖離した場合は関数側を正とする。

| ファイルパターン | 対応する asset_type | 実行コマンド |
|---|---|---|
| `skills/*/SKILL.md` | skills | `Skill("managing-agent-configs")` を種別 skills で実行 |
| `skills/*/scripts/*.sh` | skills | 同上 |
| `skills/*/references/**` | skills | 同上 |
| `.claude/rules/*/rule.md` | rules | `Skill("managing-agent-configs")` を種別 rules で実行 |
| `.claude/rules/*/*.sh` | rules | 同上 |
| `.claude/rules/**/prh.yml`（グローバル・プロジェクト両方） | rules | 同上 |
| `routines/*/ルーティン設計書.md` | routines | `Skill("managing-agent-configs")` を種別 routines で実行 |
| `tools/hooks/*.sh` | hooks | `Skill("managing-agent-configs")` を種別 hooks で実行 |

## 機械強制

| timing | スクリプト | 注入タグ | 挙動 |
|---|---|---|---|
| PostToolUse(Write\|Edit\|MultiEdit) | `check-managing-configs-review-needed.sh` | `[MANAGING-REVIEW-REQUIRED]` | managed ファイル編集を検知し advisory 注入。同一セッション内で対応する managing スキルが発火済みならスキップ（exit 0） |
| PostToolUse(Write\|Edit\|MultiEdit) | `check-managing-configs-review-needed.sh` | `[MANAGING-GATE-DISABLED]` | `marker-path.sh` が見つからない場合、マーカー処理をスキップした旨を自己申告して exit 0（fail-open） |

## 再帰防止

PostToolUse hook は `~/agent-home/sessions/.skill-log/${session}.jsonl` を参照し、`"skill":"managing-agent-configs"` が当該セッション内で既に発火済みであれば advisory を抑制する。managing-agent-configs 実行中の自身のファイル編集で advisory が繰り返し注入されることを防ぐ。

## 違反検知時の手順

### `[MANAGING-REVIEW-REQUIRED]` 受信

1. 注入メッセージ内の種別（asset_type）を確認する
2. `Skill("managing-agent-configs")` を該当種別で実行する（create → review → test の 3 モード連鎖がデフォルトで走る）
3. テスト PASS を確認する

### `[MANAGING-GATE-DISABLED]` 受信

1. `~/agent-home/tools/hooks/shared/marker-path.sh` が存在するか確認する（agent-home の配置崩れの可能性）
2. review-gate（PostToolUse）からの場合は fail-open のため作業は継続できるが、マーカー処理がスキップされている旨を認識する

## プロジェクト上書き

- 上書き可否: 一律適用
- 理由: managed ディレクトリのレビュー強制は agent-home / グローバル設定資産に対する枠組みであり、受け口の対象外

設計判断・経緯の記録は同ディレクトリの `design-notes.txt` を参照（非注入サイドカー）。

## 関連

- `~/agent-home/skills/managing-agent-configs/SKILL.md` — スキル/hooks/rules/ルーティン/サブエージェント統合管理ハブ（旧 managing-skills / managing-hooks / managing-rules / managing-routines / managing-subagents を統合）
- `~/.claude/rules/always/placement/file-guard/rule.md` — マーカー書き出し先規約
- `~/.claude/rules/always/session/infra/rule.md` — スキル発火ログ記録
