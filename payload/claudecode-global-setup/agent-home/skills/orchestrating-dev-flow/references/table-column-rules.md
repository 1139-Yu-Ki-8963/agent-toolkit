# Phase カード 5 列テーブルの記載ルール

orchestration.js の phaseSteps と ai-management-portal のフロー解説タブに表示される 5 列テーブルの、各列に何を書くべきかを定義する。

## 列定義

### # 列（id）
- Phase 番号-Step 番号（例: 1-1, 2-3, D-1, I5）
- 1 始まり。Step 0 は禁止

### Step 列（title + detail）
- title: Step の短い名前（動詞句）
- detail: Step の具体的な操作説明（1-2 文）
- 手順の参照先がある場合は detail に含める（例: 「phase-1-route-determination.md の手順に従う」）
- **手順参照は refs 列ではなくこの列に書く**

### タイミング列（timing）
- 実行タイミング（「Phase 開始直後」「前 Step 直後」「Step N-M 完了後」等）

### 参照列（refs）— rules / skills / context
- この Step で **参照するリソース** を書く
- type: "rule" — グローバル規約名（例: worktree-required-rules）
- type: "skill" — 呼び出すスキル名（例: frontend-design）
- type: "context" — flow-values.yml 由来の設定（例: プロジェクト基本情報、ルート判定の閾値設定）
- **手順書（phase-*.md Step N-M）はここに書かない**。手順書は「参照するリソース」ではなく「実行する手順」であり、Step 列の detail に書く
- **Step の動作（TaskUpdate / TaskCreate / ステータスライン更新）はここに書かない**。これらは参照リソースではなく Step 実行時の動作であり、書く場合は「ステータスライン更新:」「進捗登録:」等の明確なラベルを前置する

### 検査列（checks）— hooks / linter
- この Step で **発火する hook / linter** を書く
- type: "hook-block" — block する hook（exit 2）
- type: "hook-notify" — notify する hook（advisory）
- type: "hook-guard" — guard する hook（EnterPlanMode 等）

## flowSummary の書き方

Phase カードのバナーに表示される flowSummary は、Phase の **目的** を先頭に置き、その後に Step の流れを書く。

- 良い例: `「ルート確定」classify 閾値取得 → タスク内容確認 → ルート判定 → ルート提案`
- 悪い例: `classify 閾値取得 → タスク内容確認 → ルート判定 → ルート提案`（目的がない手順の羅列）

目的は「」で囲み、Phase が何を達成するかを 1 語〜短い句で示す。

## ツール名の表記

- Hook / Skill / Rule 等のツール名は原形を残す。勝手に日本語に置き換えない
- 良い例: `Hook（停止）: check-main-agent-direct-work.sh`
- 悪い例: `検査（停止）: check-main-agent-direct-work.sh`（Hook が消えている）
- 補足（停止 / 通知 / 制御）は括弧内に日本語で付けてよい

## flowSummary の UI 表示

- 「」で囲まれた目的は Phase 色のバッジとして表示される
- その後のテキストはグレーの流れ説明として表示される
- JS 側で正規表現 `/^「(.+?)」(.+)$/` で分離してレンダリングする

## モバイル表示（720px 以下）

- 5 列テーブルをカード形式（縦積み）に変換する
- colgroup / thead を非表示にし、tbody tr を display: block にする
- Phase カードの左ボーダー（border-left: 6px）は 1 本のみ。Step カードに別の border-left を付けない（二重ボーダー禁止）
- テーブル領域に左パディングを設け、テキストが左枠に被らないようにする
- 参照・検査列に「参照:」「検査:」のラベルを ::before で付加する

## pill 詳細ポップオーバー

refs・checks の各 pill（Hook / Rule / Skill / Context）にタップ/クリックで詳細を表示する。

### データ構造

orchestration.js の refs / checks エントリにオプショナルで以下を追加:
- `desc` — pill の目的・役割の説明（1-2 文）。desc がある pill はタップ可能になる
- `meta` — Hook 専用。対応規約と発火タイミング（例: "対応規約: subagent-delegation-rules | PreToolUse(Write|Edit|Bash)"）

### UI 動作

- デスクトップ（720px 超）: クリック位置の近くにポップオーバー表示。外側クリックで閉じる
- モバイル（720px 以下）: ボトムシート（画面下部からスライドアップ）。背景タップで閉じる
- desc がない pill はタップ不可（通常表示）
- desc がある pill は cursor: pointer + 下線で「タップ可能」を示す

### 表示内容

- タイトル: pill の text（括弧の補足を除く）
- 説明: desc の内容
- メタ情報: meta の内容（Hook のみ）
- 閉じるボタン

### text の記載ルール

- 内部キー名（context_a、scripts.flow_classify 等）を使わない
- 人間が読んでわかる日本語の表現にする
- 例: `context_a（地図と語彙）` → `プロジェクト基本情報（アーキテクチャ・用語集・技術スタック）`
- 注入タグ（[MAIN-AGENT-DIRECT-WORK-BLOCK] 等）を含めない
- flow-values.yml 等のファイル名が Step 内に登場する場合、refs に Context pill として追加し desc でタップ説明を付ける
- Phase 1 には起動前チェック Step（references/module-preflight-check.md の手順）を必ず含める

## Step 完了条件の表示

- orchestration.js の各 phaseSteps に `completionCondition` フィールドを持つ
- UI では Step 列の detail の下に「完了条件: 〜」タグとして表示（`::before` で「完了条件: 」ラベルを付与）
- CSS: `.odf-step-completion`（accent 色左ボーダー + 薄い accent 背景 + 太字ラベル）
- Phase ファイル（references/phase-*.md）の `**完了**: ` 行と内容を一致させる
- **文体**: 全文末を「〜であること」「〜していること」「〜されていること」で統一する（テスト項目と同じ形式）
- 悪い例: 「ルートが確定し、ユーザーに提示済み」（文末が「済み」）
- 良い例: 「ルートが確定し、ユーザーに提示されていること」（文末が「こと」）

## Step 番号の採番

- Phase 番号-連番（例: 1-1, 1-2, 6-1, 6-2, 6-3）
- 1 始まり。Step 0 は禁止
- **レターサフィックス（a, b, c）は禁止**。6-2a, 6-2b のような子 Step は使わず連番にする
- Step 数が 7 を超える Phase は Phase 分割を検討する

## Hook の説明に含めるべき情報

- Hook が内部で実行するツール（textlint、Playwright 等）がある場合、desc に明記する
- 良い例: 「コミットメッセージの命名規則を検査し、docs の追加行に textlint を実行する」
- 悪い例: 「コミットメッセージの命名規則・textlint・公開可否を検査する」（textlint が何をするか不明）

## 禁止事項

1. refs 列に手順書参照（phase-*.md Step N-M）を書かない
2. checks 列に「hook 強制なし」を書かない（全 Step に何らかの hook が該当する）
3. Step 番号に 0 を使わない（1 始まり）
4. refs 列に Step の動作（TaskUpdate / TaskCreate）を書かない
5. flowSummary に目的なしで手順だけ羅列しない
6. Hook / Skill 等のツール名を勝手に日本語に置き換えない
7. モバイルで Step カードに独自の border-left を付けない（Phase カードの左ボーダーと二重になる）
8. checks 列に注入タグ（`[MAIN-AGENT-DIRECT-WORK-BLOCK]` 等）を書かない。注入タグは AI 内部の識別子であり、人間向け UI には不要。Hook 名と日本語の説明だけを書く
9. refs・checks の text に flow-values.yml の内部キー名（context_a、scripts.xxx、review_gates.xxx 等）を使わない。人間が読んでわかる表現にする
10. Step 番号にレターサフィックス（6-2a, 5-1b 等）を使わない。連番にする
