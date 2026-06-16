# イベント別フックレシピ

各イベントの「最小骨組み」と「典型例」を 1 か所に集めたカタログ。新規フックを追加する担当者は、このページで最も近いレシピを選んで下敷きにする。

---

## PreToolUse

ツール実行**前**に発火する。`matcher` でツールを絞り、`if` でコマンドパターンを更に絞る。

### 入力 stdin

```json
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "git commit -m '...'",
    "description": "Commit changes"
  }
}
```

### 最小レシピ（追加コンテキスト注入）

```json
{
  "matcher": "Bash",
  "hooks": [
    {
      "type": "command",
      "command": "printf '{\"systemMessage\":\"[フック発火] サンプル\",\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"[SAMPLE] ここに Claude への指示\"}}'",
      "if": "Bash(git commit *)",
      "timeout": 5
    }
  ]
}
```

### Bash 系フィルタ

`if` の書式は `Bash(<cmd> *)`（コロンなし・スペース区切り）。`Bash(git commit *)` のように書く。`Bash(git commit -m *)` のように細かくも書ける。複数コマンドに対応するには **同じ matcher 内に複数 hook を並べる**（OR 結合のシンタックスは無い）。

**注意**: `permissions.allow/deny` では `Bash(git commit:*)` のようにコロン区切りを使うが、`if` フィールドはコロンなしのグロブ構文を使う。混同しないこと。

settings.json の実例: `Bash(git commit *)` `Bash(git checkout *)` `Bash(git branch *)` `Bash(git switch *)` `Bash(mkdir *)` `Bash(rm *)` の 6 通り。

### Write / Edit 系で内容を覗く

```bash
jq -r '.tool_input.content // ""' \
  | grep -qiE '<禁止パターン>' \
  && echo '[<TAG>] <理由>' && exit 2 \
  || exit 0
```

`tool_input.content` は Write のみ。Edit では `new_string` を見る。

### ブロック動作

- exit 0: 通過
- exit 2: ツール呼び出しを停止し、stderr の文字列を Claude に渡す
- exit 2 を選ぶときは JSON ではなく **plain text を stderr に書く**

---

## UserPromptSubmit

ユーザーが Enter したプロンプトを送信する**前**に発火する。matcher は不要。

### 入力 stdin

```json
{
  "session_id": "abc123",
  "prompt": "ユーザーが入力した文字列"
}
```

### 最小レシピ

```json
{
  "hooks": [
    {
      "type": "command",
      "command": "jq -r '.prompt // \"\"' | grep -qiE '<キーワード>' && printf '<json>' || true",
      "timeout": 5
    }
  ]
}
```

### マッチ失敗時の `|| true`

`grep -q` は不一致で exit 1 を返すが、フックは exit 0 で終わる必要がある。`|| true` を **必ず** 末尾に付ける。`|| true` を省略するとセッションごとにフックがエラー扱いになる。

### 複数キーワードを OR で結合

```bash
grep -qiE '(skill|スキル).*(作成|作る|追加|書く|new)|(SKILL\.md)'
```

- `-i`: 大小文字無視
- `-E`: 拡張正規表現
- 日英の同義語を `|` で並べる
- 単語境界が必要なら `\b` を使う（`\bremove\b` など）

### 注入する additionalContext の例

settings.json 実例 3 件はすべて以下の形:

```
[<TAG>] <検出した状況>。<参照すべきスキル / ルール>。<具体的な行動指示>。
```

スキル参照は `~/.claude/skills/<name>/SKILL.md` のチルダパスで書く（絶対パス禁止）。

---

## PostToolUse

ツール実行**後**に発火する。matcher で対象ツールを絞る（`Write|Edit` のように正規表現可）。

### 入力 stdin

実際の stdin は以下のフォーマット（`tool_name`/`tool_input` だけでなくセッション情報も含む）:

```json
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../<session-id>.jsonl",
  "cwd": "/path/to/cwd",
  "permission_mode": "acceptEdits",
  "hook_event_name": "PostToolUse",
  "tool_name": "Write",
  "tool_input": { "file_path": "/abs/path.md", "content": "..." },
  "tool_response": { "filePath": "...", "..." : "..." },
  "tool_use_id": "toolu_...",
  "duration_ms": 7
}
```

`tool_input.file_path` で対象ファイルパスを取得できる（Write / Edit 両方）。

### 最小レシピ（ファイル走査型）

```bash
input=$(cat)
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$file" ] || [ ! -f "$file" ] && exit 0
case "${file##*.}" in
  md|txt) ;;
  *) exit 0 ;;
esac

# ここでファイルを走査
matches=$(grep -nE '<パターン>' "$file" 2>/dev/null | head -5)
[ -z "$matches" ] && exit 0

jq -n --arg file "$file" --arg matches "$matches" '{
  "systemMessage": "[フック発火] <カテゴリ>",
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": ("[<TAG>]\nfile=" + $file + "\n検出:\n" + $matches)
  }
}'
```

**`echo` でなく `printf '%s'` を使う**: `echo "$input"` は大きな JSON で jq エラーを起こす場合がある。`printf '%s' "$input" | jq -r '...' 2>/dev/null` が安全。

### PostToolUse で Node.js 系ツールを実行する場合

textlint など Node.js を使うツールを PostToolUse フック内で呼ぶ場合、以下の 3 点に注意する。

**1. stdin + Node.js = hook output 無配信**

`input=$(cat)` で stdin を読んだ後に Node.js を実行すると、フックの stdout が Claude Code に届かなくなる（実証済み）。
対処: `exec 0</dev/null` を Node.js 実行の直前に挿入し、bash の stdin を閉じる。

```bash
input=$(cat)
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
exec 0</dev/null          # ← Node.js 実行前に必ず入れる
result=$(node ... "$file") || true
```

**2. Node.js の PATH**

Claude Code のフック環境では nvm が有効でなく `node` が PATH に存在しない。必ず絶対パスで指定する。

```bash
~/.nvm/versions/node/v22.16.0/bin/node \
  /path/to/node_modules/textlint/bin/textlint.js ...
```

**3. exit 1 を返すツールへの `|| true`**

textlint は違反検出時に exit 1 を返す。`result=$(textlint ...) || true` としないと bash -e 環境でスクリプトが中断する。

**4. 複数フックの stdin 共有（stdin exhaustion）**

同一 matcher 内の複数 hook は stdin パイプを共有する。hook[0] が `input=$(cat)` で stdin を消費すると hook[1] の stdin が空になる。
対処: 複数の処理を 1 フックに統合し、stdin を 1 回だけ読む。

### サブエージェント委譲を指示する文の型

PostToolUse から重い修正処理を起動する場合、`additionalContext` に以下のテンプレートで書く。

```
[<TAG>]
file=<対象ファイル>
検出行:
<grep -n の出力>

Agent ツール（subagent_type: general-purpose）を即座に起動し、
このファイルを ~/.claude/skills/<scope-skill>/SKILL.md で修正すること（CLAUDE.md §N）。
```

CLAUDE.md 側に `[<TAG>]` を含む additionalContext が来たときの動作ルールを書いておく（既存例: §7 AMBIGUITY-AUTO-FIX、§8 TEXTLINT）。

### 出力 JSON は jq で組み立てる

PostToolUse は動的内容（ファイルパス、検出行）を含むため、`printf` だとエスケープを誤りやすい。**`jq -n --arg msg "..." '{...}'` を使う** こと。改行 (`\n`) も `--arg` 経由で安全に渡せる。

---

## SessionStart / Stop（参考）

settings.json には現在登録なし。仕様だけ記載:

| イベント | 発火タイミング | matcher | 主な用途 |
|---------|-------------|---------|---------|
| SessionStart | セッション開始直後 | 不要 | プロジェクトの状態を additionalContext に注入 |
| Stop | エージェントターン終了直後 | 不要 | 完了通知、ログ出力 |

入力は `session_id` のみ。出力スキーマは PreToolUse と同じ（`hookSpecificOutput.hookEventName` をイベント名に合わせる）。

---

## SessionEnd

`/clear` `/quit` `Ctrl+C` 等でセッションが終わる直前に発火する。`additionalContext` の注入先となる Claude セッションが既に終了しているため、本イベントは**ログ書き出し・外部プロセス起動**専用と考える。

### 入力 stdin

```json
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../<session-id>.jsonl",
  "reason": "clear",
  "cwd": "/path/to/cwd",
  "permission_mode": "acceptEdits",
  "hook_event_name": "SessionEnd"
}
```

`reason` の取りうる値:

| 値 | 発生条件 |
|----|---------|
| `clear` | ユーザーが `/clear` を実行 |
| `logout` | `/logout` 実行 |
| `prompt_input_exit` | プロンプト入力中に `Ctrl+D` 等で終了 |
| `other` | `clear` / `logout` / `prompt_input_exit` 以外（プロセス強制終了など） |

### 最小レシピ（生ログ保存のみ）

```json
{
  "SessionEnd": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "input=$(cat); printf '===%s===\\n%s\\n' \"$(date -u +%FT%TZ)\" \"$input\" >> /tmp/session-end.log; exit 0",
          "timeout": 10
        }
      ]
    }
  ]
}
```

### reason フィルタ

`matcher: "clear"` 構文の受理性は Claude Code バージョン依存。**確実に動かすには command 内で reason を判定する**:

```bash
reason=$(printf '%s' "$input" | jq -r '.reason // ""')
[ "$reason" != "clear" ] && exit 0
```

### claude -p で要約サブエージェントを起動するパターン

SessionEnd から `claude -p` を呼んでセッション要約を生成する場合の必須注意点:

1. **再帰防止**: 起動した子 claude プロセスが SessionEnd を再発火すると無限ループに陥る。`CLAUDE_HOOK_SUMMARY_RUNNING=1` のような環境変数を子プロセスに渡し、本フック先頭で `[ -n "$CLAUDE_HOOK_SUMMARY_RUNNING" ] && exit 0` をチェックする。同じガードを PreToolUse(Skill) など要約セッション内で発火しうる他フックにも入れる。
2. **`--bare` の罠**: `claude --bare` は hooks をスキップするが、認証は `ANTHROPIC_API_KEY` 限定で OAuth/keychain を読まない。OAuth ログイン環境では `--bare` を外し、ENV ガードで再帰を止める方針が安全。
3. **`--no-session-persistence`**: 要約用の子セッションをディスクに残さない。`~/.claude/projects/` がゴミセッションで膨れない。
4. **transcript の長さ**: jsonl が数 MB に達するため `jq` で user/assistant のみ抽出し `head -c 200000` で打ち切る。
5. **timeout**: claude -p は冷起動が遅い。timeout は **180 秒** が目安。
6. **二重フォークでバックグラウンド化する**: transcript の内容を変数に事前取得した上で、二重サブシェルパターンで `claude -p` を完全分離する。`( { printf ... } | ( claude -p ... ) & ) &; exit 0` — 外側の `( ) &` がすぐに終了し、内側のパイプラインが launchd に引き取られる。この二重サブシェルパターンにより `/clear` が即座に返る。単純な `& disown` は bash のジョブテーブルから外すだけでプロセスグループは変わらず、Claude Code ハーネスが子プロセスを待機し続ける。なお transcript_path の内容は **バックグラウンド起動前に変数へ展開**しておくこと（バックグラウンド起動後はフックのシェルプロセスが終了して変数スコープが消えるため展開できなくなる）。
7. **プロンプトは stdin 経由で渡す**: 抜粋本文（特殊文字を含みうる長文）をコマンドライン引数 `claude -p "..."` で渡すと、シェル引用符のエスケープが破綻する。`{ printf '%s' "$prompt"; } | claude -p` のようにパイプで stdin に流し、`-p` の引数は省略するか短い指示文だけにする。

### transcript jsonl のスキーマ最小例

`transcript_path` が指す jsonl は 1 行 1 イベントの JSON。要約フックで読むときは以下のキーを期待する:

```json
{"type": "user", "timestamp": "2026-04-29T05:00:00Z", "message": {"content": "ユーザー入力"}}
{"type": "assistant", "timestamp": "2026-04-29T05:00:01Z", "message": {"content": [{"type": "text", "text": "応答"}]}}
{"type": "tool_use", "timestamp": "2026-04-29T05:00:02Z", "message": {"content": [{"type": "tool_use", "name": "Read"}]}}
```

- `.type` がイベント種別（`"user"` / `"assistant"` / `"tool_use"` / `"file-history-snapshot"` 等）
- `.message.content` は文字列または配列（assistant は `[{type, text}]` の配列形式）
- `.timestamp` は ISO8601 UTC

抽出例（user/assistant のみ、content を 2000 文字で打ち切り）:

```bash
jq -c 'select(.type=="user" or .type=="assistant") | {
  type,
  ts: .timestamp,
  content: (.message.content | if type=="string" then .[0:2000] else (tostring | .[0:2000]) end)
}' "$transcript"
```

実例カタログ: `examples.md` の SessionEnd 要約フックを参照。

---

## 全イベント共通の戒め

| ルール | 理由 |
|-------|------|
| `timeout` を必ず明示 | デフォルトに頼ると遅いフックでセッションが止まる |
| 重い処理は CLAUDE.md とサブエージェントに委譲 | フック内で大規模処理をすると応答が劣化する |
| 機密ファイル保護はフックではなく `permissions.deny` | フックは万能ガードではない |
| 自分の Write / Edit が自分のフックに引っかかるパターンを書かない | DRAWIO BLOCK のような自己ロック現象が起きる |
