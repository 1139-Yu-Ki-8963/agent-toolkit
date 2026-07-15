# Step 進捗管理

orchestrating-dev-flow 実行中の Step 進捗管理の手順・スクリプト仕様・呼び出し規約。

## update-flow-status.sh

### 用途

flow-status.json を書き込む（ステータスライン表示用）。
TaskUpdate の呼び出し（ユーザー向け進捗表示用）は Claude Code のツールであるためシェルから直接呼べない。
update-flow-status.sh 実行直後に TaskUpdate(in_progress) を呼ぶこと（後述）。

### 引数

```
bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh \
  <phase_num> "<phase_name>" <current_step> <total_steps> "<step_name>"
```

| 引数 | 型 | 例 | 説明 |
|---|---|---|---|
| phase_num | 数値 or 文字列 | 1, "D", "I" | Phase 番号 |
| phase_name | 文字列 | "ルート判定" | Phase の日本語名 |
| current_step | 数値 | 1 | 現在の Step 番号（1 始まり） |
| total_steps | 数値 | 4 | 当該 Phase の総 Step 数 |
| step_name | 文字列 | "classify 閾値の取得" | Step の日本語名 |

### 呼び出し例

```bash
bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh 1 "ルート判定" 1 4 "classify 閾値の取得"
```

## 呼び出しタイミング

### 各 Step 開始時

各 Phase ファイルの Step 見出し直後に記載された呼び出し行を実行する。
実行後、必ず TaskUpdate(in_progress) を呼ぶ。

```
# Step 開始時のセット
bash ~/agent-home/skills/orchestrating-dev-flow/scripts/update-flow-status.sh <phase_num> "<phase_name>" <current_step> <total_steps> "<step_name>"
TaskUpdate(in_progress, "<step_name>")
```

### Phase 開始時の TaskCreate

Phase N の最初の Step 実行前に、Phase N の全 Step を TaskCreate で登録する。
ただし Phase N の Step 一覧は Phase N-1 の最後の Step で先読み済み（次項参照）。

### Phase 切替時の次 Phase Step 先読み

Phase N の最後の Step 完了時に:
1. 次 Phase の references ファイルを Read する
2. Step 見出し（## Step N-M: タイトル）から Step 一覧を抽出する
3. 全 Step を TaskCreate で登録する

例外:
- Phase 1 の Step は SKILL.md の Phase テーブルから TaskCreate（Phase 0 がないため）
- Phase 13 は最終 Phase のため次 Phase の先読みなし
- ルートによって次 Phase が異なる（Phase 1-4, Phase 2 最後の Step を参照）

### ルート別の次 Phase 対応

| 現在の Phase | ルート | 次 Phase |
|---|---|---|
| Phase 1 | full / quick / refactor | Phase 2 |
| Phase 1 | config | Phase 2 |
| Phase 1 | incident | Incident |
| Phase 2 | full / refactor | Phase 3 |
| Phase 2 | quick | Phase 3（スキップ可） → Phase 4 |
| Phase 2 | config | Phase D |
| Phase D | - | Phase 9 |
| Incident | - | Phase 11 |

## 禁止事項

1. Step 番号に 0 を使わない（1 始まり）
2. Phase ファイルから呼び出し行を削除しない（SKILL.md の共通手順だけでは実行されなくなる）
3. TaskCreate を Phase 内の全 Step 実行後に一括登録しない（Phase 開始時に事前登録する）
4. update-flow-status.sh の直後に TaskUpdate(in_progress) を省略しない（ステータスラインとユーザー表示の 2 系統を同期させる）
