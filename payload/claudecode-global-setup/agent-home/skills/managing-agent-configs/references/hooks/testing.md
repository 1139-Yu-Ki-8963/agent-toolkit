# Hook 実機検証手順（testing）

`managing-agent-configs`（種別: hooks） の **test モード** が参照する手順書。`conventions.md` を前段で読んだ前提で、サブエージェントを使った hook の実機 bash 検証を実行する。

このファイルは create / review モードからの **自動連鎖の終端** にあたる。test モード完了後は最終レポートを返す（さらなる連鎖はない）。

## 概要

フックの書き手はその挙動を正確に判断できない。書き手が「これで動くはず」と思うほど、実機で別のシェル文脈で動かすとエッジで落ちる。このモードの核心は **バイアスのない実行者にフック command を実機 bash で叩かせ、出力 JSON とシェル exit を構造化評価し、繰り返す** こと。改善が横ばいになるまでやめない。

## 使用タイミング

- 新規フックを `~/.claude/settings.json` に追加した直後（create / review モードからの自動連鎖）
- 既存フックを編集した直後（command / if / timeout の変更）
- フックが期待どおりに発火しない、または期待しない時に発火しているとき
- 重要なフック（毎セッションで発火するもの）の挙動を固めたいとき

使用しないとき:
- 既存フックの読み取り・閲覧のみ
- settings.json の `permissions` / `env` / `statusLine` の検証（hooks 以外）
- 使い捨てフック（評価コストが見合わない）

## ワークフロー

### Step 1: 静的整合チェック（ディスパッチ不要）

- **配置アーキ準拠**（`conventions.md` §4 準拠）:
  - command path が flat `hooks/` バケットに無いか確認
  - 禁止 glob: `~/agent-home/tools/hooks/` / `~/.claude/hooks/` / `~/.claude/**/hooks/` / `<repo>/.claude/hooks/` / `<repo>/.claude/**/hooks/`
  - 違反検出時の対応: テストを **続行せず中断** し、ユーザーに次の選択肢を `AskUserQuestion` で提示
    - (A) 正しい象限に移動してからテスト再開（推奨）
    - (B) legacy として現状維持・テストのみ続行
  - 検出コマンド: `echo "$cmd" | grep -qE '(\.claude/hooks\|\.claude/.+/hooks\|agent-home/tools/hooks\|agent-home/hooks)/'`
- command 文字列の JSON 内ダブルクォートエスケープが揃っている（`\"`）
- `if` 条件の構文チェック（**`if` は bash では検証不可。静的チェックが唯一の手段**）:
  - `Bash(<tool> *)` 形式を使う（コロンなし・スペース区切り）
  - コロン区切り `Bash(<tool>:*)` は `permissions.allow/deny` 専用の別構文。`if` では動作しない
  - 誤ると fail-open（全 Bash コマンドで発火）になるため最優先で確認する
- timeout が `conventions.md` §6 の目安（5〜15 秒）内
- TAG プレフィックスが既存と重複していない（`conventions.md` §3 の重複禁止 TAG リスト参照）
- hookEventName が親 `<EventName>` と一致
- 配置先の rule.md / SKILL.md 内に `## 設計判断` セクションが存在する（新規 hook のみ。legacy は対象外）
- `~/agent-home/ai-management-portal/catalog/hooks.html` の `HOOKS` 配列に登録されている

ずれがあれば、Step 2 に進む前に command / if / timeout / 配置 を修正する。

### Step 2: ベースライン準備

対象フックを固定し、以下の 2 つを用意する。

- **評価シナリオ** 3 種を必ず用意:
  - **マッチケース**: フックが発火する条件（JSON が出る期待）
  - **非マッチケース**: フックが発火しない条件（stdout 空 + exit 0 が期待）
  - **エッジケース**: 特殊文字を含む引数 / 空ステージング / git 外ディレクトリ / 環境変数未設定 等
- **要件チェックリスト**:
  - [critical] マッチ時に有効な JSON が stdout に出力される（`jq -e .` で構文検証通過）
  - [critical] JSON が `systemMessage` と `hookSpecificOutput.{hookEventName, additionalContext}` の 3 キーを持つ
  - [critical] additionalContext の先頭が `[<TAG>]` プレフィックスで始まる
  - [critical] 非マッチ時は stdout が空かつ exit 0
  - timeout 内に完了（duration_ms < timeout × 1000）
  - hookEventName が親 EventName と一致
  - 副作用なし（意図しないファイル変更・プロセス起動なし）

### Step 2.5（新設）: 意地悪ケース考案（生成専任サブエージェント）

Step 2 の「エッジケース」を技術的エッジケース止まりにしないため、Step 3 の実行担当とは別の生成専任サブエージェントを起動する。

```
Agent(subagent_type: "investigator", prompt: """
対象 hook script: <path>（本文を Read して渡す）

このスクリプトが暗黙に前提としている実行環境（cwd・単一 git remote・単一 worktree・
環境変数・呼び出し順序等）を、正当な用途に見えるコマンドの書き方でどう裏切れるか、
最低 3 パターン提案せよ。

出力: パターン名 / 裏切り方 / 想定コマンド例 / 技術的再現性（可能/要検証/不可）
""")
```

採用基準: 技術的に再現可能かつ hook の実際の呼び出し経路内であるものを上位 2〜3 件採用し、Step 2 の「エッジケース」シナリオへ追加する。

### Step 3: バイアスなし実機実行

`Agent` ツールで新しいサブエージェントを **ディスパッチ** する。セルフ再読で代替しない（自分が書いた command を客観視するのは構造的に不可能）。複数フックを並行検証する場合は 1 メッセージに複数の Agent 呼び出しを並べる。

### Step 4: 実行

後述の「サブエージェント呼び出し規約」に従ったプロンプトを渡し、サブエージェントが:

- `jq -r '<JSONPath>' ~/.claude/settings.json` で対象フックの command を抽出
- 実機 bash で実行（PostToolUse / SessionEnd など stdin が必要な場合は擬似 input を渡す）
- stdout を `jq -e` で構文検証 → スキーマキー存在確認 → TAG プレフィックス確認
- exit code と所要時間を計測

### Step 5: 双方向評価

返ってきた結果から以下を記録する。

- 実行ログ（command 文字列 + stdout + exit code + duration_ms）
- 各 critical 要件の ○ / × / 部分判定
- 不明瞭な点（実行者のセルフレポート、`Issue / Cause / General Fix Rule` の 3 行）
- 独自補填（実行者が推察で補った箇所、暗黙仕様の浮き彫り）

### Step 6: 修正適用

不明瞭な点を解消する最小限の修正を command / if / timeout に加える。1 イテレーション 1 テーマ。

- 修正前に「失敗パターン台帳」をスキャンし、既知パターンか確認する
- 既知なら「なぜ既存の修正が再発を防げなかったか」を先に検討する

### Step 7: 再評価

新しいサブエージェントで Step 3〜6 を繰り返す（同じエージェントを再利用しない）。

### Step 8: 収束チェック

全 critical ○ かつ実行者の不明瞭点 0 が 2 連続したら停止。重要なフック（毎セッション発火）は 3 連続にする。
- 重要なフック（毎セッション発火するもの、または緊急回避/fail-closed回数のログ集計で閾値超過のもの）は Step 2.5 を必ず1回以上実行していることを収束条件に含める

## 評価軸

| 軸 | 取得方法 | 意味 |
|---|---|---|
| JSON valid | `jq -e .` の終了コード | 構文の最低基準 |
| スキーマ準拠 | `systemMessage` / `hookSpecificOutput.hookEventName` / `hookSpecificOutput.additionalContext` の 3 キー存在確認 | 規約の最低基準 |
| TAG プレフィックス | `additionalContext` の先頭が `[<TAG>]` で始まる | プロンプト注入の最低基準 |
| 非マッチ時の動作 | stdout の長さ 0 かつ exit code 0 | エッジ動作の最低基準 |
| timeout 内完了 | duration_ms が timeout × 1000 以下 | パフォーマンス |
| if マッチ精度 | **静的チェックのみ**（bash 直接実行は `if` をバイパスするため実機検証不可）。Step 1 の構文確認で代替 | フック発火条件の正確さ |
| 副作用 | command が意図しないファイル変更・プロセス起動・ネットワーク通信をしないか | 安全性 |

## サブエージェント呼び出し規約

実行者に渡すプロンプトは以下の構造に従う。

```
あなたは ~/.claude/settings.json の <対象フック識別子> の動作確認担当です。白紙状態で実機実行してください。

## 対象
- settings.json から `jq -r '<JSONPath>' ~/.claude/settings.json` で command を抽出
- 規約参照: ~/agent-home/skills/managing-agent-configs/references/hooks/conventions.md の「標準出力 JSON フォーマット」「プレフィックス規約」

## シナリオ
- マッチケース: <発火条件を 1 行で>
- 非マッチケース: <発火しない条件を 1 行で>
- エッジケース: <特殊条件を 1 行で>

## 要件チェックリスト
1. [critical] マッチ時に jq -e で構文検証通過
2. [critical] JSON が systemMessage / hookSpecificOutput.{hookEventName, additionalContext} の 3 キーを持つ
3. [critical] additionalContext の先頭が [<期待 TAG>]
4. [critical] 非マッチ時は stdout 空 + exit 0
5. timeout (<秒数>) 内に完了
6. hookEventName が <親 EventName> と一致

判定: [critical] がすべて○なら成功、1 つでも × か部分なら失敗。

## タスク
1. command を jq で抽出
2. bash -c '<command>' で各シナリオを実行（stdin が必要なら擬似 input をパイプで渡す）
3. stdout を jq -e で検証 / exit code 確認 / time コマンドで所要時間計測
4. レポート構造で回答

## レポート構造
- 実行ログ（コマンド + stdout + exit + duration の表）
- 要件達成: 各項目 ○ / × / 部分（理由付き）
- トレース: Understanding / Planning / Execution / Formatting に OK / stuck / skipped
- 不明瞭な点（構造化）: 問題ごとに Issue / Cause / General Fix Rule の 3 行
- 独自補填: 箇条書き
- リトライ: 何回どんな理由で
```

## 失敗パターン台帳（先行知見）

新規フック検証時にまず確認すべき頻出パターン。新パターンを発見したら台帳に追記する。

- **JSON 内ダブルクォートエスケープ漏れ**:
  - 例: `"command": "printf '{"systemMessage":...}'"` （内側の `"` が `\"` でない）
  - General Fix Rule: settings.json 全体を `jq empty` で構文検証してから保存する

- **シェル変数展開の誤エスケープ**:
  - 例: `jq -n --arg n "$name"` を JSON に入れる際 `\"$name\"` にし忘れる
  - General Fix Rule: 変数展開を含むフックは `jq -n --arg` 経由で組み立て、JSON リテラルに直接埋め込まない

- **`|| true` 忘れ**:
  - 例: PreToolUse で `grep -qE 'pattern' && printf '...'` のみ。非マッチで exit 1 が返り、フック全体が失敗扱い
  - General Fix Rule: キーワードマッチ系は必ず `... && printf '...' || true` で末尾を閉じる

- **hookEventName 不一致**:
  - 例: 親が `PostToolUse` なのに `"hookEventName": "PreToolUse"` と書いている
  - General Fix Rule: parent EventName を確認し、JSON 内 `hookEventName` を必ず一致させる

- **TAG プレフィックス漏れ**:
  - 例: `additionalContext: "曖昧表現を検出..."` で `[<TAG>]` プレフィックスがない
  - General Fix Rule: additionalContext の先頭は必ず `[<TAG>] <命令文>` の形

- **timeout 不足**:
  - 例: textlint 等の重い処理を `timeout: 5` で切ってしまう
  - General Fix Rule: 外部ツール起動は最初から 15 秒、`printf` のみは 5 秒

- **stdin 想定漏れ**:
  - 例: PostToolUse の command が `input=$(cat); ...` で stdin 待ちなのに、テスト時に stdin を渡さず無限待ち
  - General Fix Rule: PostToolUse / SessionEnd を実機テストする時は擬似 input を `printf '...' | bash -c '...'` で渡す

- **`if` 条件のパターンミス（コロン混入）**:
  - 例: `if: "Bash(git commit:*)"` — コロンがあると fail-open（全 Bash コマンドで発火）になる
  - Cause: `permissions.allow/deny` のコロン区切り構文 `Bash(<tool>:*)` と混同している
  - General Fix Rule: `if` は `Bash(<tool> *)` 形式（コロンなし・スペース区切り）。`if` の静的チェックは bash 実行では検証できないため Step 1 で必ず目視確認する

- **`if` 条件のパターンミス（ワイルドカード漏れ）**:
  - 例: `if: "Bash(git commit)"` — ワイルドカードなしだとサブコマンドや引数つき呼び出しにマッチしない
  - General Fix Rule: 引数が続く可能性があるコマンドは末尾に ` *` を付ける。例: `Bash(git commit *)`

## 環境制約

新しいサブエージェントを `Agent` ツールでディスパッチできない環境では、このモードを **適用しない**。
- 代替 1: 親セッションのユーザーに別の Claude Code セッションを開いて評価を委ねる
- 代替 2: 「empirical hook evaluation skipped: dispatch unavailable」と明示的に報告する
- **NG**: セルフ再読で代替する（バイアスが入るため、評価結果を信頼してはならない）

**構造レビューモード**: 経験的評価を実行せず command 文字列の構文・スキーマ整合だけ確認したい場合は、構造レビューモードとして明示的に切り出す。サブエージェントへのプロンプトに「今回は構造レビューモード: 静的整合チェックであり、実行ではない」と明記する。連続クリア収束判定にはカウントしない。

## 反復停止基準

- **収束（停止）**: 以下を **すべて** 満たす状態が 2 連続したとき:
  - 新しい不明瞭な点: 0
  - 全 critical 要件: ○
  - duration_ms: 前回比 ±20% 以内
- **発散（設計を疑う）**: 3 イテレーション以上 critical が × → command を構造から書き直す（パッチ修正をやめる）
- **リソース上限**: 重要度と改善コストが釣り合わなくなったら停止（80 点で出荷）

## 提示フォーマット

```
## イテレーション N

### 変更内容（前回からの差分）
- <command/if/timeout の修正内容を 1 行で>
- 適用パターン: <台帳のパターン名、または「（新規）」>

### 実行結果（シナリオごと）
| シナリオ | JSON valid | スキーマ | TAG | 非マッチ動作 | timeout 内 | 備考 |
|---|---|---|---|---|---|---|
| マッチ | ○ | ○ | ○ | — | ○ | — |
| 非マッチ | — | — | — | ○ | ○ | — |
| エッジ | ○ | ○ | ○ | — | ○ | — |

### 構造化リフレクション（今回新たに浮上したもの）
- <シナリオ X>: <Issue / Cause / General Fix Rule>

### 台帳更新
- 追加: <パターン名>
- 再発: <パターン名>（元はイテレーション K）

### 次の修正案
- <最小修正>

（収束チェック: X 連続クリア / 停止条件まで残り Y ラウンド）
```

## レッドフラグ（合理化に注意）

| 浮上する合理化 | 現実 |
|---|---|
| 「JSON valid なので OK」 | スキーマ準拠と TAG プレフィックスは別軸。3 段で確認する |
| 「マッチケースだけ確認した」 | 非マッチで exit 0 にならないと毎セッションでフックが落ちる。3 シナリオ必須 |
| 「自分で command を読み直せば十分」 | エスケープ系のバグは目視ではほぼ見逃す。実機で叩く |
| 「timeout は問題ない」 | 外部ツール起動は実機計測しないと真の所要時間が分からない |
| 「if 条件は bash で確認した」 | `bash -c '<command>'` は `if` フィルタをバイパスする。`if` の正確さは Step 1 の目視チェックでしか確認できない |
| 「`if: Bash(tool:*)` と書けばいい」 | `permissions` のコロン構文と `if` のスペース構文を混同している |
| 「同じサブエージェントを再利用しよう」 | 前の改善を学習してしまっている。必ず新しいサブエージェントをディスパッチ |

## よくある失敗

- **マッチケースしか試さない**: 非マッチで exit 1 が返るとフック自体が壊れて毎セッションでエラー
- **静的レビューだけで済ませる**: シェル変数展開・パイプ・エスケープのバグは実機でしか出ない
- **timeout を実機計測しない**: textlint 等は 15 秒境界で落ちることがある
- **副作用を確認しない**: command が `mkdir` `printf >> file` 等を含むと意図しないファイルが残る

## 予想を裏切る挙動

- hooks のテストは実際のツール呼び出しを伴う — サブエージェントを使わないとメインコンテキストの状態が汚染される
- test モードは create / review からの **連鎖の終端**。さらなる連鎖はなく、最終レポートで完了する

## 参照資料

- 共通規約: `conventions.md`
- 連鎖元の手順書: `creating.md` / `reviewing.md`
- 関連スキル: `managing-agent-configs（種別: skills）` の test モード（SKILL.md 専用版。評価軸と失敗パターンが異なる）
