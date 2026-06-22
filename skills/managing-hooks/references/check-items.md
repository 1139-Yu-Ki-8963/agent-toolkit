# 26 項目チェック詳細

各項目の検出方法（jq 式・grep パターン）と修正前後サンプル。SKILL.md から参照される詳細リファレンス。

## A. command 書式

### A1 — CRITICAL: command 500 文字超

検出:
```bash
jq -r '.hooks | to_entries[] | .key as $event |
  .value[] | (.matcher // "*") as $matcher |
  .hooks[] | select((.command | length) > 500) |
  "\($event)\t\($matcher)\t\(.command | length)文字"' <settings.json>
```

修正前:
```json
{
  "type": "command",
  "command": "input=$(cat); file=$(printf '%s' \"$input\" | jq -r '.tool_input.file_path'); case \"$file\" in *.md) ... 1800文字続く ... ;; esac"
}
```

修正後:
```json
{
  "type": "command",
  "command": "該当スクリプトがない場合は削除"
}
```

外部スクリプトファイル本体は既存の配置先に該当ロジックがあれば参照する。無い場合は **ユーザーへ事実報告し** 当該修正をスキップする（CLAUDE.md「スクリプトファイル作成禁止」ルール）。注: `textlint-postwrite.sh` は 2026-06 の hook 移行で削除されました。

### A2 — WARN: command 200 文字超

検出:
```bash
jq -r '.hooks | to_entries[] | .key as $event |
  .value[] | .hooks[] |
  select((.command | length) > 200 and (.command | length) <= 500) |
  "\($event)\t\(.command | length)文字"' <settings.json>
```

修正方針: A1 と同じ、または `jq -n --arg k "$v" '{...}'` で JSON 組立を整理。

### A3 — WARN: command に改行混入

検出:
```bash
jq -r '.hooks | to_entries[] | .key as $event |
  .value[] | .hooks[] | select(.command | test("\n")) |
  "\($event)\t改行混入"' <settings.json>
```

修正方針: `.sh` ファイルへ移動。1 行で書けない複雑度なら必ず外部化。

### A4 — WARN: `echo "$(cat)"` パターン

検出:
```bash
jq -r '.hooks | to_entries[] | .key as $event |
  .value[] | .hooks[] |
  select(.command | test("echo +\"?\\$\\(cat\\)")) |
  "\($event)\techo $(cat) 検出"' <settings.json>
```

修正前: `input=$(cat); echo "$input" | jq -r '.tool_input'`
修正後: `input=$(cat); printf '%s' "$input" | jq -r '.tool_input'`

理由: 大きな JSON で `echo` がエスケープ処理する可能性があり、後段 `jq` がパースエラーになる。

### A5 — INFO: 動的 JSON の `printf` ハードコード

検出:
```bash
jq -r '.hooks | to_entries[] | .key as $event |
  .value[] | .hooks[] |
  select(.command | test("printf +'\\''\\{.*\\$")) |
  "\($event)\tprintf 動的部分検出"' <settings.json>
```

修正前: `printf '{"systemMessage":"%s"}' "$msg"`
修正後: `jq -n --arg msg "$msg" '{systemMessage:$msg}'`

理由: `$msg` に `"` や改行が含まれると JSON が壊れる。`jq -n` は自動エスケープする。

## B. 配置場所（公式仕様準拠のみ）

### B1 — CRITICAL: 相対パス `./` `../`

検出:
```bash
jq -r '.hooks | to_entries[] | .key as $event |
  .value[] | .hooks[] |
  select(.command | test("(^| )(\\./|\\.\\./)")) |
  "\($event)\t相対パス検出: \(.command)"' <settings.json>
```

修正前: `"command": "./scripts/check.sh"`
修正後: `"command": "${CLAUDE_PROJECT_DIR}/scripts/check.sh"` または絶対パス `"<project>/tools/hooks/check.sh"`

理由: worktree や `cd` 後の CWD 変更で破綻する。

### B2 — INFO: スクリプト未存在

検出:
```bash
# command から ~/path や /path や ${CLAUDE_PROJECT_DIR}/path を抽出
grep -oE '(~/|/|\$\{CLAUDE_PROJECT_DIR\}/)[A-Za-z0-9_./-]+\.sh' <command> |
  while read p; do
    expanded=$(echo "$p" | sed "s|^~|$HOME|; s|\${CLAUDE_PROJECT_DIR}|$PWD|")
    [ -f "$expanded" ] || echo "B2: 未存在 $p"
  done
```

### B3 — INFO: 実行ビットなし

検出:
```bash
[ -x "$expanded_path" ] || echo "B3: 実行ビットなし $expanded_path"
```

修正: `chmod +x <path>`

## C. type / matcher

### C1 — CRITICAL: `.type` が `"command"` 以外

検出:
```bash
jq -r '.hooks | to_entries[] | .key as $event |
  .value[] | .hooks[] | select(.type != "command") |
  "\($event)\ttype=\(.type)"' <settings.json>
```

修正: `"type": "command"` 固定（2026 年現在の公式サポート唯一）。

### C2 — CRITICAL: matcher に正規表現メタ文字

検出:
```bash
jq -r '.hooks | to_entries[] | .key as $event |
  .value[] | select(.matcher != null and (.matcher | test("[()\\.\\*\\+\\?\\[\\]]"))) |
  "\($event)\tmatcher=\(.matcher)"' <settings.json>
```

例外: パイプ区切り `Write|Edit` は許可。

修正前: `"matcher": "Write.*"`
修正後: `"matcher": "Write|Edit"` または `"matcher": "Write"`

### C3 — CRITICAL: `if` フィールドのコロン区切り

検出:
```bash
jq -r '.hooks | to_entries[] | .key as $event |
  .value[] | .hooks[] |
  select(.if != null and (.if | test("[A-Za-z]+\\([^)]*:[^)]*\\)"))) |
  "\($event)\tif=\(.if)"' <settings.json>
```

修正前: `"if": "Bash(git commit:*)"` （fail-open）
修正後: `"if": "Bash(git commit *)"` （スペース区切り）

理由: `if` フィールドはグロブ構文。`permissions.allow/deny` のコロン区切りとは別仕様。

### C4 — WARN: PreToolUse/PostToolUse で matcher 未指定

検出:
```bash
jq -r '.hooks | to_entries[] | select(.key == "PreToolUse" or .key == "PostToolUse") |
  .key as $event | .value[] | select(.matcher == null) |
  "\($event)\tmatcher未指定"' <settings.json>
```

修正方針: 対象ツール名を明示（全ツール対象が意図でも明示推奨）。

## D. event 種別

### D1 — CRITICAL: 標準 8 種外の EventName

検出:
```bash
jq -r '.hooks | keys[] |
  select(. != "PreToolUse" and . != "PostToolUse" and
         . != "UserPromptSubmit" and . != "SessionStart" and
         . != "Stop" and . != "SessionEnd" and
         . != "PermissionRequest" and . != "PostToolUseFailure")' <settings.json>
```

修正: typo を訂正（`PreToolse` → `PreToolUse` など）。標準 8 種は PreToolUse / PostToolUse / UserPromptSubmit / SessionStart / Stop / SessionEnd / PermissionRequest / PostToolUseFailure。

### D2 — CRITICAL: `decision:"block"` を PreToolUse 以外で使用

検出: hook スクリプト本体を grep。
```bash
grep -lE '"decision"\s*:\s*"block"' <referenced_scripts> |
  xargs -I{} sh -c 'event=$(jq ... 親イベント名); [ "$event" != "PreToolUse" ] && echo "D2: {}"'
```

修正方針: PreToolUse へ移動するか、`exit 2` で stderr に出すパターンに置換。

### D3 — WARN: `hookEventName` 不一致

検出: スクリプト出力を実際にテスト実行し、`.hookSpecificOutput.hookEventName` が親 EventName と一致するか確認。
```bash
event=$(jq -r '<親 EventName>' <settings.json>)
actual=$(echo '{}' | <hook command> | jq -r '.hookSpecificOutput.hookEventName')
[ "$event" = "$actual" ] || echo "D3: 不一致 expected=$event got=$actual"
```

## E. exit code

### E1 — CRITICAL: PostToolUse/UserPromptSubmit で `|| true` なし

検出:
```bash
jq -r '.hooks | to_entries[] |
  select(.key == "PostToolUse" or .key == "UserPromptSubmit") |
  .key as $event | .value[] | .hooks[] |
  select(.command | test("\\|\\| +true *$") | not) |
  "\($event)\t|| true なし: \(.command)"' <settings.json>
```

修正前: `"command": "<path-to-script>"` (exit 0 のみ)
修正後: `"command": "<path-to-script> || true"` (exit 0 または 1 を許容)

理由: PostToolUse/UserPromptSubmit で exit 1 が出るとセッションログにエラーが残る。

### E2 — WARN: `exit 2` 使用箇所が 3 件以上

検出:
```bash
grep -rln 'exit 2' <project>/tools/hooks/ | wc -l
```

修正方針: 本当に止める必要があるか再評価。多用するとユーザーの作業を妨げる。

### E3 — INFO: `exit 1` 使用箇所

検出: 同上 `exit 1` で。意図が「ログ目的」「エラー伝搬」「単なる typo」のどれか確認。

## F. timeout / 性能

### F1 — CRITICAL: `timeout` フィールド不在

検出:
```bash
jq -r '.hooks | to_entries[] | .key as $event |
  .value[] | .hooks[] | select(.timeout == null) |
  "\($event)\ttimeout未指定: \(.command)"' <settings.json>
```

修正方針: 5〜15 秒で明示。`printf` / `grep` のみなら 5 秒、外部ツール呼び出しなら 10〜15 秒。

**例外**: `conventions.md` §11「外部連携 hook の例外」の判定基準（環境変数チェックで開始 + `|| true` で短絡 + 外部サービスが自動再生成）を全て満たす hook は対象外。Superset Home Manager 等の外部連携を想定。

### F2 — WARN: `timeout > 30` 秒

検出:
```bash
jq -r '.hooks | to_entries[] | .key as $event |
  .value[] | .hooks[] | select(.timeout != null and .timeout > 30) |
  "\($event)\ttimeout=\(.timeout)秒"' <settings.json>
```

修正方針: 30 秒超は同期 hook として長すぎる。非同期化（`nohup ... & disown` は G2 で別途禁止）か、処理分割を検討。

### F3 — WARN: 同一 matcher 配下に複数 hook（stdin 競合）

検出:
```bash
jq -r '.hooks | to_entries[] | .key as $event |
  .value[] | .matcher as $m |
  select((.hooks | length) > 1) |
  "\($event)\t\($m)\thooks数=\(.hooks | length)"' <settings.json>
```

修正方針: 1 hook に統合するか、別 matcher に分離。stdin パイプは複数 hook で共有されるため `input=$(cat)` した hook の後続 hook は空 stdin を受け取る。

### F4 — WARN: Node 実行前に `exec 0</dev/null` なし

検出:
```bash
grep -lE '(^|[^a-zA-Z])node ' <project>/tools/hooks/*.sh |
  xargs -I{} grep -L 'exec +0</dev/null' {} |
  while read f; do echo "F4: $f に exec 0</dev/null なし"; done
```

修正前:
```bash
node <project>/tools/linter/run.js
```

修正後:
```bash
exec 0</dev/null
node <project>/tools/linter/run.js
```

理由: Node は stdin を inherit するため、hook の stdin（JSON）を Node が消費して出力が壊れる。

### F5 — WARN: `claude -p` 起動時に再帰防止 env なし

検出:
```bash
grep -lE 'claude +-p' <project>/tools/hooks/*.sh |
  xargs -I{} grep -L 'CLAUDE_HOOK_.*_RUNNING' {} |
  while read f; do echo "F5: $f に再帰防止 env なし"; done
```

修正前:
```bash
claude -p "summarize this session"
```

修正後:
```bash
[ -n "$CLAUDE_HOOK_SUMMARY_RUNNING" ] && exit 0
CLAUDE_HOOK_SUMMARY_RUNNING=1 claude -p "summarize this session"
```

## G. セキュリティ

### G1 — CRITICAL: `/tmp/.allow-*` 等のワンショットフラグ

検出:
```bash
grep -rEn '/tmp/\.allow-[a-z-]+' ~/.claude/settings.json <project>/tools/hooks/ |
  grep -v 'rm -f' || true
```

理由: TOCTOU 脆弱性（フラグ check と削除の間に他プロセスが書き込める）、cleanup 漏れ、複数セッション競合。

修正方針: `permissions.allow` / `permissions.deny` に該当パターンを移行、または `AskUserQuestion` で都度確認。

### G2 — CRITICAL: `nohup ... & disown` で監視不可起動

検出:
```bash
grep -rEn 'nohup .* & *disown' ~/.claude/settings.json <project>/tools/hooks/
```

理由: 失敗時にエラー検知不可、プロセス重複起動、ログ消失。

修正方針: foreground 化（timeout 内に収める）、または `routines/` の cron 起動へ移行。

### G3 — WARN: 機密 glob を hook で守っている

検出:
```bash
grep -rEn '\.env|token|key|secret|credential' <project>/tools/hooks/*.sh |
  grep -E '(deny|block|reject)'
```

修正方針: `settings.json` の `permissions.deny` リストへ移行（hook より優先・確実）。

例: `"deny": ["Read(./.env)", "Read(*token*)", "Bash(cat *secret*)"]`

### G4 — WARN: TAG 名が既存と重複

既存 TAG 一覧（`conventions.md` の §3 重複禁止 TAG リスト参照）:
- NAMING
- AMBIGUITY-AUTO-FIX / AMBIGUITY-AUTO-FIX-STALE（廃止）
- TEXTLINT / TEXTLINT-BLOCK / TEXTLINT-CLEAN
- PUBLISH-AUTHOR / PUBLISH-SAFETY / PUBLISH-SAFETY-FULL
- LINT-REVIEW-NEEDED
- TEST-FAILED
- WORKTREE-REQUIRED
- AUTO-COMMIT
- NO-DELEGATION / NO-DELEGATION-BLOCK / NO-DELEGATION-ABORT
- NO-DEFERRAL / NO-DEFERRAL-BLOCK / NO-DEFERRAL-RESPONSE
- AUTHOR-BLOCK / AUTHOR-PUSH-BLOCK
- FLOW-SELECT-REQUIRED / FLOW-SELECT-BLOCK
- PLAYWRIGHT-WORKTREE-REQUIRED
- PROD-SKILL-READ-REQUIRED

検出:
```bash
grep -rEn '\[(NAMING|AMBIGUITY|TEXTLINT|PUBLISH|LINT-REVIEW|TEST-FAILED|WORKTREE|AUTO-COMMIT|NO-DELEGATION|NO-DEFERRAL|AUTHOR|FLOW-SELECT|PLAYWRIGHT|PROD-SKILL)[A-Z-]*\]' \
  <project>/tools/hooks/ |
  awk -F: '{print $1, $3}' |
  sort -u
```

新規 TAG を追加する場合は上記リストを更新し、3〜5 文字以内の動詞句で重複しない名前にする。
