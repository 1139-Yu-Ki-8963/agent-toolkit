# phase 突入タスクゲート（PHASE-STEP-TASK）

phase / step 構造を持つスキルフローで、次の phase に突入する前に当該 phase の全 step を step 単位で TaskCreate することを義務付け、hook で機械強制する規約。phase 粒度の雑なタスク登録（「Phase 3 をやる」1 件のみ等）を禁止する。各 SKILL.md への個別記載は行わず、本規約（常時注入）と hook が全スキル横断で強制する。

## 規約本文

### 1. 適用対象

- `## Phase` / `### Step` 見出しで段階進行するスキルフロー全般（orchestrating-dev-flow・rebuilding-code-from-docs・managing-agent-configs 等）
- 進行宣言に `update-flow-status.sh` を使う全フロー

### 2. phase 突入前の step タスク登録義務

Phase N の作業を開始する（= `update-flow-status.sh N ...` を初めて実行する）前に、Phase N の全 step を **1 step = 1 タスク** で TaskCreate する。phase をまたいだ一括登録は禁止しない（事前に全 phase 分を登録してもよい）が、突入時点で当該 phase の step 数が揃っていることが必須条件。

### 3. タスク subject の形式（粒度規約）

```
Phase <N> Step <N>-<M>: <具体的な作業内容>
```

- `<N>` は phase 番号（数値または D / I）、`<M>` は phase 内の step 連番（1 始まり）
- Step 番号の phase 部分は phase 番号と必ず一致させる（`Phase 3 Step 2-1:` は形式違反）
- `<作業内容>` は完了判定可能な動詞句で書く。「対応する」「進める」のような内容のない句は禁止
- phase 粒度 1 件のタスク（step 分解なし）は登録数不足として phase 突入時に block される

### 4. 進行宣言の統一（statusline 連携）

phase 開始時と step 完了ごとに以下を実行する。これが statusline（`~/.claude/statusline.py` の Phase/Step 進捗バー）の元データとなる。

```bash
bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh \
  <phase_num> "<phase名>" <current_step> <total_steps> "<step名>"
```

orchestrating-dev-flow 以外の phase/step スキルもこのスクリプトを共用する。`.flow-progress.json` が無い環境では statusline 用の `flow-status.json` 書き出しのみ行われ、Phase 順序検証はスキップされる（実装確認済み）。

## 機械強制

| timing | スクリプト | 注入タグ | 挙動 |
|---|---|---|---|
| PostToolUse(TaskCreate) | `record-step-tasks.sh` | `[STEP-TASK-FORMAT]` | subject が形式合致なら phase 別カウンタ（marker_path 配下 `phase-step-task-count-<N>`）を加算。フロー実行中（flow-status.json 存在）の形式違反 subject に advisory 注入（exit 0） |
| PreToolUse(Bash) | `check-phase-entry-tasks.sh`（`rules-bash-runner.sh` 経由） | `[PHASE-TASK-BLOCK]` | `update-flow-status.sh` の新 phase 宣言（前回宣言と異なる phase 番号）時にカウンタ < total_steps なら exit 2 で block |

check-phase-entry-tasks.sh の素通り条件（fail-safe）: `--init` / 同一 phase 内の step 更新 / Phase D・I（ドキュメント・インシデントは gate で止めない。flow-gate 規約と同判断）/ 引数パース不能。

## 違反検知時の手順

### `[PHASE-TASK-BLOCK]` 受信

1. block メッセージ内の不足数（登録 X / 必要 Y）を確認する
2. 当該 phase の step 定義（SKILL.md または references/phase-N-*.md）を読み、全 step を §3 の形式で TaskCreate する
3. 再度 `update-flow-status.sh` を実行する

### `[STEP-TASK-FORMAT]` 受信

1. 直前の TaskCreate の subject を確認し、TaskUpdate で §3 の形式に修正する（修正ではカウントされないため、削除して正しい形式で再作成する）
2. 形式違反のタスクはカウンタに加算されない。放置すると phase 突入時に `[PHASE-TASK-BLOCK]` で block される

## 制約・既知の限界

- カウンタは TaskCreate の発行回数ベース。同一 step の重複作成は重複カウントされ、タスク削除は減算されない
- `update-flow-status.sh` を呼ばないフローには phase 突入の観測点がなく gate は発火しない。§4 の進行宣言義務が前提
- TaskUpdate による subject 修正はカウンタに反映されない（PostToolUse の matcher は TaskCreate のみ）

## プロジェクト上書き

- 上書き可否: 一律適用
- 理由: タスク粒度と進行可視化はプロジェクトに依存しない行動規範であり、緩和口を作ると粒度規約が形骸化するため受け口を設けない

## 設計判断

設計判断・経緯の記録は同ディレクトリの `design-notes.txt` を参照（非注入サイドカー）。

## 関連

- `~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh` — 進行宣言の実行エンジン（flow-status.json 書き出し + Phase 順序検証）
- `~/.claude/statusline.py` — flow-status.json を読む Phase/Step 進捗バー（表示側。本規約で変更なし）
- `~/.claude/rules/scoped/dev-flow/gate/rule.md` — Phase 順序の実装ゲート（コード書き込み制御）。本規約はタスク分解の粒度を担当し、対象が異なる
- `~/.claude/rules/scoped/agent-config/hooks/rules-bash-runner.sh` — check-phase-entry-tasks.sh の起動元（9 本目）
- `~/.claude/rules/always/placement/file-guard/rule.md` — marker_path ヘルパーとカウンタの書き出し先規約
