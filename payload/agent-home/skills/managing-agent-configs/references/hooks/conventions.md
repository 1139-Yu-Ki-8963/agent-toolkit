# Hooks 共通規約（conventions）

`managing-agent-configs`（種別: hooks） の create / review / test 全モードが参照する **規約の単一正本**。JSON 出力スキーマ・TAG プレフィックス・event 別パターン・timeout 目安・配置 4 象限をここで定義する。旧 `creating-hooks` 本体に散在していた規約をここに集約した。

各モードは最初にこのファイルを Read してから役割別 references（`creating.md` / `reviewing.md` / `testing.md`）に進む。

## 1. フックの基本構造

`settings.json` の hooks エントリは以下の形を取る。

```json
{
  "hooks": {
    "<EventName>": [
      {
        "matcher": "<ToolName>",          // PreToolUse / PostToolUse のみ。任意
        "hooks": [
          {
            "type": "command",
            "command": "<シェルコマンド>",
            "if": "<ToolName>(<pattern> *)", // PreToolUse のみ。任意
            "timeout": <秒>
          }
        ]
      }
    ]
  }
}
```

| フィールド | 役割 |
|----------|------|
| `EventName` | `PreToolUse` / `PostToolUse` / `UserPromptSubmit` / `SessionStart` / `Stop` / `SessionEnd` / `PermissionRequest` / `PostToolUseFailure` |
| `matcher` | 親エントリの絞り込み。`Bash` / `Write` / `Edit` などツール名 |
| `if` | フック単位の追加条件。`Bash(git commit *)` のように tool+pattern で書く（コロンなし・スペース区切り） |
| `type` | `"command"` 固定（本スキル範囲では） |
| `command` | stdin から JSON を受け取り stdout に JSON を返すシェル一行 |
| `timeout` | 必須。秒単位 |

## 2. 標準出力 JSON フォーマット（最重要）

`command` が標準出力に書く JSON は以下の固定スキーマに従う。

```json
{
  "systemMessage": "[フック発火] <カテゴリ>: <短い動詞句>",
  "hookSpecificOutput": {
    "hookEventName": "<EventName>",
    "additionalContext": "[<TAG>] <Claude への命令文>"
  }
}
```

**2 つのフィールドの違いを必ず使い分ける**:

| フィールド | 表示先 | 用途 |
|----------|-------|------|
| `systemMessage` | チャット UI（ユーザーが目視） | 発火事実の通知。1 行・短く |
| `hookSpecificOutput.additionalContext` | Claude のプロンプトに注入 | Claude が次のターンで従うべき指示・参照すべきスキル名 |

`hookSpecificOutput.hookEventName` は親の `EventName` と必ず一致させる。詳細スキーマは `output-schema.md` を参照。

## 3. プレフィックス規約

| 出力先 | 必須プレフィックス | 形式 |
|-------|----------------|------|
| `systemMessage` | `[フック発火]` | `[フック発火] <カテゴリ>: <内容>` |
| `additionalContext` | `[<TAG>]` | `[<TAG>] <Claude への指示>` |

`<TAG>` は大文字英数字とハイフンのみ。原則として参照先スキル名や機能名と対応させる。

**`additionalContext` 本文の書き方**: Claude が次のターンで取るべき行動を **命令形** で書く。質問形を貼らず、行動指針として整える。

- 良い例: `[GIT-PUSH-GUARD] force push 系オプション（--force / --force-with-lease）が含まれていないか確認すること。共有ブランチへの force push は原則禁止。`
- 悪い例: `[GIT-PUSH-GUARD] force push してませんか？`

**重複禁止 TAG**（既存利用済みおよび予約済み）:

```
NAMING / DRAWIO / DRAWIO BLOCK / SKILL作成ルール
AMBIGUITY-AUTO-FIX / TEXTLINT / SESSION-SUMMARY
PUBLISH-AUTHOR / PUBLISH-SAFETY / PUBLISH-SAFETY-FULL
NO-DELEGATION / NO-DEFERRAL / NO-ROOT-MARKER-BLOCK
HOOKS-BUCKET-FORBIDDEN / WORKTREE-REQUIRED / WORKTREE-CLEANUP
FLOW-SELECT-REQUIRED / FLOW-SELECT-BLOCK / FLOW-SELFIMPROVE-PENDING
AUTO-COMMIT / PROD-SKILL-READ / ADR-REQUIRED / SHELL-EVASION-DETECTED
MAIN-DIRECT-WORK-BLOCK / SUBAGENT-DELEGATION-HINT
MERGE-APPROVAL-STALE / LOOP-DETECTED / SESSION-CONTEXT-LARGE / MERGE-APPROVAL-FETCH-FAILED
CURL-EGRESS-BLOCK / HAIKU-FILE-GUARD-BLOCK
PHASE-TASK-BLOCK / STEP-TASK-FORMAT
MANAGING-REVIEW-REQUIRED / MANAGING-COMMIT-BLOCK / MANAGING-GATE-DISABLED
```

新規 TAG は上記と被らない名前を選び、追加時はこの一覧にも追記する。

## 4. 配置 4 象限（hooks-architecture-rules 準拠）

新規 hook script の物理配置は `~/agent-home/ai-management-portal/design/hooks.html` の規約に従う。

### 配置決定の 2 軸

| 軸 | 分類 | 判定基準 |
|---|---|---|
| ownership | **skill 延長** | 特定 skill の前提や挙動を強制する。その skill が無ければ存在意義を失う |
| ownership | **独立規約** | 単一 skill に紐付かない system 全体のメタ規約を強制する |
| scope | **global** | 全プロジェクトで効かせる |
| scope | **project** | 単一プロジェクトのみで効かせる |

### 4 象限の置き場

| ownership × scope | 置き場 |
|---|---|
| skill × global | `~/agent-home/skills/<skill>/scripts/<hook>.sh` |
| skill × project | `<repo>/.claude/skills/<skill>/scripts/<hook>.sh` |
| 独立規約 × global | `~/.claude/rules/<rule>-rules/<hook>.sh` |
| 独立規約 × project | `<repo>/.claude/rules/<rule>-rules/<hook>.sh` |

### 禁止配置

以下に新規 hook を置くことは禁止する。`check-hooks-architecture.sh`（PreToolUse Write 強制）が `[HOOKS-BUCKET-FORBIDDEN]` で block する。

- `~/agent-home/tools/hooks/`（既存 31 ファイルは legacy。新規追加禁止）
- `~/.claude/hooks/`
- `~/.claude/**/hooks/`（plugin 含む）
- `<repo>/.claude/hooks/`
- `<repo>/.claude/**/hooks/`

例外（誤ブロック対象外）: React の `src/hooks/`、`.husky/`、`.git/hooks/`、`node_modules/**/hooks/` は `.claude/` も `agent-home/` も経由しないため自動的に対象外。

ゲート監視パスの正本は `~/agent-home/tools/hooks/shared/marker-path.sh` の `managed_asset_type()`。本表と乖離した場合は関数側を正とする。

### 配置後の必須登録

新規 hook を作成したら、同じターン内で次を実施する。

1. `~/agent-home/ai-management-portal/catalog/hooks.html` の `HOOKS` 配列に登録（file / group / matcher / role）
2. 配置先の rule.md 内に `## 設計判断` セクションを記載（必要性・代替案不採用理由・保守責任者・廃棄条件）
3. `settings.json` の対応イベントに command path を登録

## 5. イベント別パターン

要点のみ。完全なレシピは `event-recipes.md`。

### PreToolUse
- `matcher` でツールを絞り、`if` で更にコマンドパターンを絞る
- 単純通知: `printf '<json>'` を 1 行で書く
- ブロックする場合のみ `... && exit 2 || exit 0`（exit 2 で操作を停止）

### UserPromptSubmit
- 定型: `jq -r '.prompt // ""' | grep -qiE '<pattern>' && printf '<json>' || true`
- マッチ失敗時の `|| true` は必須（フック自身を必ず exit 0 にするため）

### PostToolUse
- 入力受け取り: `input=$(cat); file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)`（`echo` は不可）
- Node.js 系ツールを呼ぶ前に `exec 0</dev/null` を必ず挿入する（stdin + Node.js = output 無配信）
- 拡張子フィルタは `case "${file##*.}" in md|txt) ;; *) exit 0 ;; esac`
- 出力 JSON は `jq -n --arg file "$file" --arg result "$result" '{...}'` で安全に組み立てる

## 6. timeout の目安

| 処理内容 | 推奨 timeout（秒） |
|---------|-----------------|
| `printf` のみの即時返答 | 5 |
| `jq` + `grep` のキーワードマッチ | 5 |
| ファイル読み込み + 行マッチ | 10 |
| 外部ツール起動（textlint 等） | 15 |

短すぎるとファイル走査系が timeout で落ち、長すぎるとセッション全体の応答が遅くなる。

## 7. サブエージェント委譲パターン

フック自身は重い処理をしない。複雑な修正は以下の 2 段構成にする。

1. フック側: `additionalContext` に「Agent ツール（subagent_type: ...）を起動して〜」と明示
2. CLAUDE.md または rules 側: `[<TAG>]` を含む additionalContext が来たらサブエージェントを起動

既存例:

| TAG | 参照箇所 | 用途 |
|-----|---------|------|
| `AMBIGUITY-AUTO-FIX` | `~/.claude/rules/always/agent/subagent-selection/rule.md` | 曖昧表現を `clarifying-ambiguity` スキルで修正 |
| `TEXTLINT` | `~/agent-home/skills/writing-quality/SKILL.md` | textlint エラーを `writing-quality` スキルで修正 |

新しい委譲パターンを追加する時は、CLAUDE.md または rules にも対応するルールを必ず書き加える。

## 8. エラーハンドリングの定型

| 状況 | 対処 |
|-----|------|
| キーワードマッチ失敗 | `\|\| true` で exit 0 にする（フックでセッションをブロックしない） |
| 入力ファイルが存在しない | `[ ! -f "$file" ] && exit 0` で抜ける |
| 操作を本当にブロックしたい | `... && exit 2 \|\| exit 0`（PreToolUse のみ） |
| 機密ファイル保護 | フックではなく `permissions.deny` で守る（`.env`, `*token*`, `*key*` など） |

`exit 2` の実例は settings.json の Write フック（Mermaid/PlantUML 検出）が代表例。多用しないこと。

## 9. フックカテゴリ定義（A〜H）

旧 `diagnose-hooks` の分類軸。review モード（dry-run）でカテゴリ別整合性を診断する際に使う。

| カテゴリ | ラベル | 主目的 | 判定基準 |
|---------|--------|--------|---------|
| A | ガード系 | 危険な操作を強制停止する | `exit 2` / `decision: block` を使う |
| B | 規約系 | 命名・テンプレートの一貫性を維持する | `[NAMING]` / テンプレ検査を注入する |
| C | 品質系 | テキスト・コード品質をチェックする | lint ツールを実行して `[TAG]` を注入する |
| D | セキュリティ系 | 公開可否・機密情報をスキャンする | diff 解析後に Agent を起動する |
| E | 自動化系 | 繰り返し作業を自動実行する | Skill 起動指示を additionalContext に注入する |
| F | ログ・計測系 | 操作履歴を記録・可視化する | jsonl ファイルに追記する |
| G | 外部連携系 | 外部システムへ通知する | 外部スクリプトを呼び出す |
| H | ガイダンス注入系 | 文脈を補足して手順を提示する | additionalContext にテキストを注入する |

複数機能を持つフックは主要機能でカテゴリを判定する。副機能は括弧で補足する。

## 10. Gotchas（規約レベル）

- `event` 名は PreToolUse / PostToolUse / UserPromptSubmit / SessionStart / Stop / SessionEnd / PermissionRequest / PostToolUseFailure の 8 種に限定 — 存在しないイベント名を書いても hook が発火しない
- `if` のコロン区切り（`Bash(git commit:*)`）は fail-open（全 Bash コマンドで発火）の原因。`permissions.allow/deny` のコロン構文と混同しないこと
- `if` は bash 直接実行で検証不可。静的チェック（コロンなし・スペース区切り）が唯一の手段
- PreToolUse 以外で `decision: block` を使っても効かない。停止は PreToolUse の `exit 2` か Stop の `decision: block` のみ

## 11. 外部連携 hook の例外（timeout 未設定の許容）

外部サービス（Superset Home Manager 等）と連携する **短絡パターン** の hook は、`timeout` フィールドを意図的に省略してよい。外部サービス側が hook を自動再生成する場合、こちらで追記しても上書きされるため。

```bash
# 例: Superset Home の通知 hook（環境変数未設定なら短絡終了）
[ -n "$SUPERSET_HOME_DIR" ] && [ -x "$SUPERSET_HOME_DIR/hooks/notify.sh" ] && SUPERSET_AGENT_ID=claude "$SUPERSET_HOME_DIR/hooks/notify.sh" || true
```

判定基準（**全部満たすときのみ例外扱い**）:

- 環境変数チェック（`[ -n "$XXX_DIR" ]`）で開始する
- 失敗時に `|| true` で必ず exit 0 にする
- 外部サービスが hook を自動生成 / 自動更新する責任を持つ

これを満たさない hook で `timeout` 欠落は通常どおり **F1 CRITICAL** として検出する。
