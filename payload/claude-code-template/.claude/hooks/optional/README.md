# オプション hooks 配線ガイド

## 配線方法

`.claude/settings.json` の `hooks` セクションに以下の JSON を追記する。

注意事項:
- settings.json は厳密な JSON（コメント・末尾カンマ不可）
- 編集後は `node -e "JSON.parse(require('fs').readFileSync('.claude/settings.json','utf8'))"` で検証する
- hooks は設定ファイル間で加算マージされる。`~/.claude/settings.json` に同種の hook があると二重実行になる

## 各 hook の配線スニペット

### user-prompt-submit（秘密情報の送信ブロック）
```json
"UserPromptSubmit": [{"matcher": "", "hooks": [{"type": "command", "command": "node ${CLAUDE_PROJECT_DIR}/.claude/hooks/optional/user-prompt-submit.mjs", "timeout": 10}]}]
```

### permission-request（権限ダイアログの監査ログ）
```json
"PermissionRequest": [{"matcher": "", "hooks": [{"type": "command", "command": "node ${CLAUDE_PROJECT_DIR}/.claude/hooks/optional/permission-request.mjs", "timeout": 10}]}]
```

### post-tool-use（成功実行の監査ログ）
```json
"PostToolUse": [{"matcher": "", "hooks": [{"type": "command", "command": "node ${CLAUDE_PROJECT_DIR}/.claude/hooks/optional/post-tool-use.mjs", "timeout": 10}]}]
```

### post-tool-use-failure（失敗の監査ログ）
```json
"PostToolUseFailure": [{"matcher": "", "hooks": [{"type": "command", "command": "node ${CLAUDE_PROJECT_DIR}/.claude/hooks/optional/post-tool-use-failure.mjs", "timeout": 10}]}]
```

### config-change（設定変更の監査ログ）
```json
"ConfigChange": [{"matcher": "", "hooks": [{"type": "command", "command": "node ${CLAUDE_PROJECT_DIR}/.claude/hooks/optional/config-change.mjs", "timeout": 10}]}]
```

### session-end（終了記録）
```json
"SessionEnd": [{"matcher": "", "hooks": [{"type": "command", "command": "node ${CLAUDE_PROJECT_DIR}/.claude/hooks/optional/session-end.mjs", "timeout": 5}]}]
```

## 不採用イベント

- PostToolBatch: PostToolUse と二重になるため不採用（乗り換えは可・両方配線は不可）
- Stop / SubagentStop / PreCompact 等: 汎用テンプレとしての既定用途がないため未同梱

## 新規 hook の実装規約

1. `node:` ビルトインのみ使用する
2. 入力不正・内部エラーは黙って exit 0 する
3. additionalContext は事実を書く（命令口調のシステム指示風の文は prompt-injection 防御に引っかかり逆効果）
4. `lib/common.mjs` を使い、テストを `tests/` に足す
