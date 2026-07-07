# Hook 出力 JSON スキーマ完全リファレンス

`command` が標準出力に書く JSON の完全仕様。SKILL.md 本体で扱いきれない詳細を集約する。

## 基本スキーマ

```json
{
  "systemMessage": "string",
  "hookSpecificOutput": {
    "hookEventName": "string",
    "additionalContext": "string"
  }
}
```

| フィールド | 必須 | 型 | 用途 |
|----------|------|-----|------|
| `systemMessage` | 推奨 | string | チャット UI に 1 行で表示。発火事実の通知 |
| `hookSpecificOutput.hookEventName` | 必須 | string | 親イベント名と一致させる |
| `hookSpecificOutput.additionalContext` | 推奨 | string | Claude のプロンプトに注入される指示文 |

`systemMessage` も `additionalContext` も省略は可能だが、両方とも空にすると「フックが何のために発火したか」が誰にも分からなくなる。最低どちらか一方は埋める。

## hookEventName と matcher の関係

| EventName | 親 matcher の例 | hookSpecificOutput.hookEventName |
|-----------|---------------|--------------------------------|
| PreToolUse | `Bash` / `Write` / `Edit` | `"PreToolUse"` |
| PostToolUse | `Write|Edit` （正規表現可） | `"PostToolUse"` |
| UserPromptSubmit | matcher 不要 | `"UserPromptSubmit"` |
| SessionStart | matcher 不要 | `"SessionStart"` |
| Stop | matcher 不要 | `"Stop"` |

`matcher` は親イベントが流す対象を絞るだけで、hook 出力 JSON 内には現れない。出力 JSON の `hookEventName` は **親 EventName に揃える** こと。

## ブロック動作（PreToolUse のみ）

PreToolUse は exit code でツール実行を止められる。

| exit code | 効果 |
|----------|------|
| 0 | 通常通過。stdout の JSON は systemMessage / additionalContext として処理される |
| 2 | ツール実行をブロック。**stdout の JSON は使われず、stderr に書いた文字列がそのまま Claude に渡る**（systemMessage は出ない） |

実例は 2 件。1 件目は settings.json の Write フックで、図記述コードブロック（Mermaid / PlantUML / dot）または PlantUML 開始マーカーを検出すると exit 2 でブロックする。2 件目は `managing-commit-gate.sh`（`~/.claude/rules/always/agent-config/review/managing-commit-gate.sh`、rules-bash-runner 経由）で、managed ファイルのテスト完了マーカーが無い状態での `prh.yml` commit を検知すると `[MANAGING-COMMIT-BLOCK] 理由文` を stderr に出力して exit 2 でブロックする。

`exit 2` を選ぶ場合は JSON ではなく **stderr に直接 `[TAG] 理由文`** を書く。多用しないこと（ユーザーの操作を強制停止するため）。

## 入力 JSON（stdin）スキーマ

フックは stdin から JSON を受け取る。イベントごとに含まれるフィールドが異なる。

### PreToolUse / PostToolUse 共通

```json
{
  "session_id": "string",
  "transcript_path": "string",
  "tool_name": "Bash | Write | Edit ...",
  "tool_input": { "...": "..." }
}
```

`tool_input` の中身はツールごとに変わる:

| tool_name | 主な tool_input フィールド |
|-----------|------------------------|
| Bash | `command`, `description` |
| Write | `file_path`, `content` |
| Edit | `file_path`, `old_string`, `new_string` |
| Read | `file_path`, `offset`, `limit` |

PostToolUse は加えて `tool_output` を含む。

### UserPromptSubmit

```json
{
  "session_id": "string",
  "prompt": "string"
}
```

### SessionStart / Stop

`session_id` のみ。フィールドは少ないが将来追加される可能性があるので `// ""` などのデフォルト指定を使うこと。

## 複数フックが同じイベントに登録された場合

- `hooks` 配列に複数エントリがあると **すべてが順に実行** される
- 各フックの `additionalContext` は **連結** されて Claude に渡る
- 1 つでも `exit 2` を返せばその時点でブロック（PreToolUse）

衝突を避けるには TAG を分ける（NAMING vs NAMING-BRANCH など）か、`if` 条件で発火対象を分離する。

## 出力エンコーディングの注意

| 方法 | 利点 | 欠点 |
|-----|------|------|
| `printf '<json>'` | 最速・依存なし | エスケープが手作業。改行や `"` の埋め込みでミスりやすい |
| `jq -n --arg msg "..." '{...}'` | 安全に組み立てられる | jq 起動分のオーバーヘッド |

**動的な内容を含む場合は `jq -n` を使う。** 静的な短いメッセージのみなら `printf` で良い。settings.json の AMBIGUITY-AUTO-FIX / TEXTLINT は `jq -n` を採用している。

## ありがちなミス

| ミス | 症状 | 対処 |
|-----|------|------|
| `hookEventName` が親と不一致 | フック自体は動くが Claude が文脈を取り違える | 親 EventName と必ず揃える |
| `printf` 内の `"` を未エスケープ | `Invalid JSON` で出力が無視される | `\"` でエスケープ、または `jq -n` |
| `additionalContext` に絶対パスを直書き | 環境差で動かない | `~/agent-home/skills/<name>/SKILL.md` の形を使う |
| マッチ失敗時の `\|\| true` 忘れ | 失敗時にフックが exit 1 でエラー扱いになる | UserPromptSubmit / PostToolUse では必ず付ける |
| `systemMessage` が長文 | チャット UI で目立ちすぎる | 1 行・短い動詞句で要約 |
| 自己参照ブロック（DRAWIO BLOCK 系のフック対象文字列を文書中に直接書く） | 自分の Write がブロックされる | grep パターン例は具体トークンを書かず抽象表現にする |
