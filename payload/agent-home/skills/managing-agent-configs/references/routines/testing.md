# ルーティン実機検証手順（testing）

`managing-agent-configs`（種別: routines） の **test モード** が参照する手順書。メインセッションが `ScheduleWakeup` で動的ペーシングしながら、RemoteTrigger → ポーリング → JSONL 分析 → 修正 → 再実行を収束するまで自律ループする。

このファイルは create / review モードからの **自動連鎖の終端** にあたる。test モード完了後は最終レポートを返す（さらなる連鎖はない）。

## 概要

クラウド環境固有の問題はローカルで再現できない。`RemoteTrigger` でクラウド即時実行し、`ScheduleWakeup` でクラウド完了を待ち、JSONL ログを機械判定し、問題があれば修正して再実行する。このループを **メインセッションが直接回す**（サブエージェントに委任しない。クラウド実行は 5〜30 分かかるためサブエージェントでは待機を維持できない）。

## 使用タイミング

- create / review からの自動連鎖で到達したとき
- 既存ルーティンのプロンプトを修正した後
- クラウド実行で失敗が報告され、原因調査 → 修正を行うとき

使用しないとき:
- 既存ルーティンの設定を閲覧するだけのとき → `cloud-operations.md` を直接参照
- 実行プロンプトの静的チェックのみ → review モードで十分

## ツール呼び出し手順（スキルが実行する全ステップ）

ユーザーは「ルーティンをテストして。カバレッジ自動改善」とだけ言う。以下はスキルが自律的に実行する手順。

### Step 1: テスト状態の初期化

内部状態を初期化する（会話コンテキスト内で管理）:

```
state = {
  routine_name: "<ルーティン名>",
  trigger_id: null,       // Phase 1 で特定
  slug: null,             // profile.md から取得
  repo_path: null,        // プロジェクトリポジトリのローカルパス
  iteration: 0,           // ループ回数
  consecutive_pass: 0,    // 連続クリア数（2 で収束）
  max_iterations: 5,      // 最大ループ回数（2 連続クリア含む）
  phase: "preflight",     // 現在のフェーズ
  results: []             // イテレーションごとの結果
}
```

### Step 2: Phase 1 プリフライト

1. `cloud-operations.md` の 7 項目チェックリストでクラウド設定を確認
2. 実行プロンプト.md が push 済みか確認:
   ```bash
   git diff origin/main -- routines/<name>/実行プロンプト.md
   ```
3. profile.md から trigger_id と slug を取得。trigger_id がなければ:
   ```
   ToolSearch select:RemoteTrigger
   RemoteTrigger({ action: "list" })
   ```
   で特定し、profile.md に記録

**Phase 1 で NG が検出された場合 → Step 2 に進む前に修正する:**

| 検出した問題 | 修正アクション |
|---|---|
| 実行プロンプトが未 push | `git add` → `git commit` → `git push origin main` |
| trigger_id が profile.md にない | RemoteTrigger list で特定し profile.md に記録 → commit + push |
| クラウド設定 7 項目に NG | `RemoteTrigger action=update` で修正（リポジトリ追加・allowed_tools 変更等） |
| profile.md のキーと実行プロンプトの参照に不整合 | 実行プロンプトを Edit → commit + push |
| 旧パスの実行プロンプトがプロジェクト側に残存 | ユーザーに旧ファイル削除を提案（AskUserQuestion） |

修正後、全 NG が解消されたことを再確認してから Step 3 に進む。

**完了条件:** 7 項目チェック全 OK。push 済み。trigger_id 特定済み。不整合が全て修正済み。

4. `state.phase = "trigger"`

### Step 3: RemoteTrigger で即時実行

```
RemoteTrigger({ action: "run", trigger_id: state.trigger_id })
```

実行後、`ScheduleWakeup` でクラウド完了を待つ:

```
ScheduleWakeup({
  delaySeconds: 270,
  reason: "<routine_name> のクラウド実行完了を待機（1 回目）",
  prompt: "managing-agent-configs（種別: routines） test: <routine_name> の JSONL を確認"
})
```

`state.phase = "polling"`

270 秒（4.5 分）はプロンプトキャッシュ TTL（5 分）内。クラウド実行は通常 5〜30 分のため、2〜7 回のポーリングで完了を検知する。

### Step 4: ポーリング（ScheduleWakeup 復帰時）

`ScheduleWakeup` から復帰したら、JSONL の出現を確認する:

```bash
SLUG="<slug>"
DATE=$(date -u +%Y-%m-%d)
REPO="<repo_path>"

git -C "$REPO" fetch origin main
git -C "$REPO" show "origin/main:logs/${SLUG}/${DATE}.jsonl" 2>/dev/null | grep -q '"event":"run_end"'
```

**run_end が見つからない場合:**
- 経過時間 < 35 分 → 再度 ScheduleWakeup(270s) でポーリング継続
- 経過時間 >= 35 分 → クラッシュと判定。`state.phase = "analyze"` に進む（run_end なし）

**run_end が見つかった場合:**
- `git -C "$REPO" pull origin main` で JSONL を取得
- `state.phase = "analyze"`

### Step 5: JSONL 構造チェック（Layer 1: 壊れていないか）

JSONL の形式・存在を jq で判定する。これは最低限の「クラッシュしていないか」の確認であり、テストの入口に過ぎない。

```bash
JSONL="$REPO/logs/${SLUG}/${DATE}.jsonl"

# 1. [critical] run_start
jq -r 'select(.event == "run_start")' "$JSONL" | head -1

# 2. [critical] run_end
jq -r 'select(.event == "run_end")' "$JSONL" | head -1

# 3. [critical] run_end.status = ok
jq -r 'select(.event == "run_end") | .status' "$JSONL"

# 4. [critical] phase 数一致
PHASE_COUNT=$(jq -r 'select(.event == "phase") | .phase' "$JSONL" | wc -l)

# 5. detail 非空
jq -r 'select(.event == "phase" and .detail == {}) | .phase' "$JSONL"

# 6. warn 0 件
jq -r 'select(.event == "phase" and (.status == "warn" or .status == "fail")) | .phase' "$JSONL"
```

### Step 5b: 行動検証 + 忠実度検証（Layer 2・3）

**Layer 1 が全 ○ でも、Layer 2・3 を省略してはならない。** JSONL が出力されていても、各 Phase が意図通りに動作したかは別の問題。

#### 手順

1. `routines/<name>/検証仕様.md` を Read する
2. 検証仕様の各 Phase セクションに記載された **検証コマンドを 1 つずつ実行** する
3. 各コマンドの exit code と出力を記録し、合格基準と照合する
4. 全項目の ○ / × を判定する

#### 検証仕様ファイルの構造

各ルーティンの `routines/<name>/検証仕様.md` に Phase ごとの具体的な検証コマンドと合格基準を定義する。

```
## Phase N: <タイトル>

### 期待する行動
<この Phase が何をすべきかの 1 行説明>

### Layer 2 検証（JSONL + 成果物の実在）
<bash コマンド: jq / grep / gh pr view 等>

### Layer 3 検証（成果物品質の実地調査）
<worker-sonnet サブエージェントへの委任指示>
例: PR diff を Read し、追加テストがトートロジーでないか判定
例: 削除シンボルを grep -r で未参照を裏取り
例: マイグレーション SQL を Read し、INDEX が妥当か判定

### 合格基準
<Layer 2 + Layer 3 の両方を満たして ○>
```

**Layer 3 はサブエージェント（worker-sonnet）による実地調査。** JSONL やメタデータだけでなく、diff の中身・コードの品質・変更の妥当性を判定する。検証仕様がないルーティンはテスト不可。create / review モードで検証仕様の作成を必須とする。

#### 検証仕様に含めるべき観点

| 観点 | 検証方法の例 |
|---|---|
| **Phase 内の行動証跡** | JSONL summary を grep し、期待キーワード（テーブル数・検出件数等）が含まれるか |
| **数値の妥当性** | 報告値をリポジトリの実値と比較（±許容範囲） |
| **Phase 間の整合性** | Phase N の検出件数 = Phase N+1 の処理件数 |
| **成果物の実在** | `gh pr view` / `gh issue view` / `git show origin/<branch>:<file>` |
| **マージ判断** | profile の PR 影響度と PR state の一致（影響あり→OPEN / 影響なし→MERGED） |
| **コミット規約** | コミットメッセージの prefix・文字数を grep |
| **ファイル上限** | 処理件数が profile の max_files_per_run 以内 |
| **成果物品質（PR diff）** | PR の diff を worker-sonnet に渡し、変更が実行プロンプトの意図通りか判定させる。例: テスト追加 PR なら「トートロジーでないか」「実装の分岐を実際にカバーしているか」、デッドコード削除 PR なら「削除したシンボルが本当に未参照か grep -r で裏取り」 |
| **成果物品質（Issue 本文）** | Issue 本文を Read し、規定フォーマットか・集計値が JSONL の値と一致するか検証 |
| **成果物品質（コード変更）** | マイグレーション SQL を Read し、INDEX が実際のクエリパターンに効くか判定。lint ルール変更を Read し、既存コードで `biome check` / `ruff check` が通過するか実行 |

**成果物品質の検証は worker-sonnet サブエージェントに委任する。** JSONL のフィールドだけ見て合格にしてはならない。PR の diff・Issue の本文・コード変更の中身を実際に調査し、ルーティンが「意味のある仕事をしたか」を判定する。

### 要件チェックリスト

#### Layer 1: 構造（壊れていないか）

| # | 要件 | 判定方法 |
|---|---|---|
| 1 | [critical] run_start 存在 | jq で抽出、1 行以上 |
| 2 | [critical] run_end 存在 | jq で抽出、1 行以上 |
| 3 | [critical] run_end.status = ok | status 値の一致 |
| 4 | [critical] phase 数一致 | 実行プロンプトの Phase 数と JSONL の phase イベント数が一致 |
| 5 | detail 非空 | 空 {} の phase が 0 件 |
| 6 | warn 0 件 | warn/fail の phase が 0 件 |

#### Layer 2・3: 行動 + 忠実度（検証仕様に基づく）

`routines/<name>/検証仕様.md` の全項目を実行し、合格基準を満たすか判定する。
検証仕様がないルーティンは Layer 2・3 を判定できないため、テスト不合格とする。

**収束条件**: Layer 1〜3 の全項目が ○ で 2 連続。1 つでも × があれば失敗。指示通りに動いていないルーティンを合格にしてはならない。

### Step 6: 判定と分岐

**[critical] 全 ○ の場合:**
```
state.consecutive_pass += 1
state.iteration += 1
```
- `consecutive_pass >= 2` → **収束。Step 8（レポート）へ**
- `consecutive_pass == 1` → 確認のため再実行。Step 3 に戻る

**[critical] に × がある場合:**
```
state.consecutive_pass = 0
state.iteration += 1
```
- `iteration > max_iterations` → **リソース上限。Step 8 へ（構造見直し提案）**
- それ以外 → Step 7（修正）へ

### Step 7: 修正 → push → 再実行

1. **失敗パターン台帳をスキャン**し、既知パターンか確認
2. 既知なら Fix Rule を適用。新規なら構造化リフレクションを記録:
   ```
   Issue: <JSONL で観察した事象>
   Cause: <実行プロンプトのどの記述が原因か>
   Fix Rule: <このクラスの問題を防ぐルール>
   ```
3. `routines/<name>/実行プロンプト.md` を Edit で修正
4. git commit + push:
   ```bash
   cd ~/agent-home
   git add routines/<name>/実行プロンプト.md
   git commit -m "【設定変更】<name> テスト修正: <修正内容 1 行>"
   git push origin main
   ```
5. Step 3 に戻る（RemoteTrigger run + ScheduleWakeup）

### Step 8: 最終レポート

```
## ルーティンテストレポート

対象: <ルーティン名>
trigger_id: <trigger_id>
実行回数: N 回
停止理由: 収束（2 連続クリア）/ 構造見直し必要

### イテレーション結果
| 回 | run_end.status | NG 項目 | 修正内容 |
|---|---|---|---|
| 1 | fail | JSONL 旧形式 | echo コマンドを具体化 |
| 2 | ok | なし | — |
| 3 | ok | なし | — (2 連続クリア) |

### 構造化リフレクション
- Issue: ...
- Cause: ...
- Fix Rule: ...

### 失敗パターン台帳更新
- 追加: <パターン名>

### 総合判定
<PASS / 構造見直し必要>
```

レポート出力後、ScheduleWakeup を **呼ばない**（ループ終了）。

## イテレーション提示フォーマット

各イテレーション完了時に以下を出力する:

```
## イテレーション N

### 変更内容（前回からの差分）
- <修正内容を 1 行で>
- 適用パターン: <台帳のパターン名、または「（新規）」>

### Layer 1: 構造チェック
| # | 要件 | 判定 | 備考 |
|---|---|---|---|
| 1 | [critical] run_start 存在 | ○ / × | |
| 2 | [critical] run_end 存在 | ○ / × | |
| 3 | [critical] run_end.status = ok | ○ / × | |
| 4 | [critical] phase 数一致 | ○ / × | 期待 N / 実際 M |
| 5 | detail 非空 | ○ / × | 空 Phase: ... |
| 6 | warn 0 件 | ○ / × | warn Phase: ... |

### Layer 2・3: 検証仕様の実行結果
| Phase | 検証項目 | コマンド出力 | 判定 |
|---|---|---|---|
| 1 | <検証仕様の項目名> | <コマンドの実際の出力> | ○ / × |
| 1 | <検証仕様の項目名> | <コマンドの実際の出力> | ○ / × |
| 2 | ... | ... | ... |
| ... | ... | ... | ... |

### 構造化リフレクション
- Issue: ...
- Cause: ...
- Fix Rule: ...

### 台帳更新
- 追加: <パターン名>

（収束チェック: X 連続クリア / 残り Y ラウンド）
```

## 3 シナリオ（2 連続クリア後に追加テスト）

| シナリオ | 条件 | 期待 |
|---|---|---|
| 正常実行 | 対象ファイルがある通常の状態 | 全 Phase 完走、run_end.status = ok |
| 空入力 | 対象 0 件（カバレッジ 100% 等） | 早期終了、run_end.status = ok |
| 異常系 | ツール未インストール・権限不足等 | run_end.status = fail、detail にエラー情報 |

初回のテストループは正常実行シナリオのみ。2 連続クリア達成後に時間的余裕があれば空入力・異常系も追加で検証する。

## 反復停止基準

- **収束（停止）**: [critical] 全 ○ が **2 連続**
- **発散（構造を疑う）**: 3 回以上のイテレーションで同じ NG 項目が再発 → reviewing.md の 12 観点で再レビュー
- **リソース上限**: 5 回反復で停止。ユーザーに構造見直しを提案

## 失敗パターン台帳（先行知見）

新パターンを発見したら台帳に追記する。

- **JSONL が旧 JSON 形式で出力される**
  - Fix Rule: JSONL 出力は具体的な echo コマンドを省略せず記載する

- **ログパスが旧形式（logs/test-quality/ 等）**
  - Fix Rule: oradora 側の旧ファイルを削除するか、実行プロンプト冒頭に「本ファイルのみに従え」を明記

- **Phase 全スキップ**
  - Fix Rule: 各 Phase に「この Phase をスキップしてはならない」ガードを追加

- **JSONL に run_end がない（クラッシュ）**
  - Fix Rule: try-finally パターンを追加

- **profile.md の Read 失敗**
  - Fix Rule: クラウド設定でリポジトリを追加

- **allowed_tools エラー**
  - Fix Rule: クラウド設定で権限を追加

- **品質検証 Phase のスキップ**
  - Fix Rule: Phase 完了条件に証跡出力を追加

- **クラウド環境で agent-home の実行プロンプトが見つからない**
  - Fix Rule: トリガープロンプトに `find /home -path '*/agent-home/routines/<name>/実行プロンプト.md' -type f 2>/dev/null | head -1` を含める。CWD はプロジェクトリポジトリのため相対パス `routines/` では agent-home 側が見つからない

- **旧実行の OPEN PR が重複チェックに干渉**
  - Fix Rule: テスト前に旧プロンプト由来の OPEN PR・リモートブランチをクリーンアップする

- **「影響あり」ルーティンの JSONL が main で見つからない**
  - Fix Rule: PR 影響度が「影響あり（PR まで）」のルーティンは JSONL が PR ブランチ上にしかない。`origin/main` だけでなく PR ブランチも確認する。profile.md の PR 影響度を参照して確認先を切り替える

## テスト後の反映

- `実行プロンプト.md`: 修正が push 済みか
- `ルーティン設計書.md`: 変更に伴う更新が必要か
- `profile.md`: trigger_id の記載が最新か
- 失敗パターン台帳: 新パターンが追記済みか

## レッドフラグ

| 浮上する合理化 | 現実 |
|---|---|
| 「ローカルサブエージェントで検証したから OK」 | クラウド固有の問題を見逃す |
| 「JSONL に run_end が出たから OK」 | Layer 1 しか見ていない。Layer 2（行動検証）・Layer 3（忠実度）を省略している |
| 「detail に値が入っているから OK」 | 値の妥当性を見ていない。coverage_after < coverage_before でも「非空」は ○ になる |
| 「PR が作成されたから OK」 | PR の中身（diff の妥当性・コミット規約・テンプレ準拠）を見ていない |
| 「push 忘れたが前回のプロンプトでも問題ない」 | 修正が反映されていない |
| 「1 回通ったから収束」 | 2 連続クリアが必要 |
| 「サブエージェントに委任しよう」 | クラウド実行 5〜30 分の待機はサブエージェントに不向き。メインが ScheduleWakeup で回す |
| 「ユーザーに /schedule run を案内しよう」 | RemoteTrigger で自動実行できる |

## Gotchas

- `RemoteTrigger action=run` で即時実行可能。ユーザー操作は不要
- `ScheduleWakeup` は 270 秒（キャッシュ TTL 内）でポーリング。35 分でタイムアウト
- push し忘れると前回のプロンプトで実行される
- oradora 側に旧実行プロンプトが残っている場合、エージェントがそちらを読む可能性がある
- test モードは create / review からの **連鎖の終端**
- ScheduleWakeup を呼ばなければループが終了する。収束後は意図的に呼ばない
