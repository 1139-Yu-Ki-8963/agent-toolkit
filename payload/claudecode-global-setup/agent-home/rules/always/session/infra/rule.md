# セッション基盤（SESSION-INFRA）

セッション中のサイレントな基盤処理。スキル発火ログ記録とセルフ project-settings 自動削除。
いずれも注入タグを発行せず、Claude への通知なしで動作する。

## 1. スキル発火ログ記録

### 記録内容

- **発火ログ**: `{"ts":"<ISO8601>","skill":"<skill名>"}` を `~/agent-home/sessions/.skill-log/<session_id>.jsonl` に追記
- **impl-session マーカー**: `skill=parallel-dev-worktree` かつ cwd が git リポジトリ内の場合に限り、`marker_path` ヘルパーで `impl-session` マーカーを書き込む（書き出し先は `~/.claude/rules/always/placement/file-guard/rule.md` の規約に従い worktree 内または `/tmp` にフォールバック）

### スキップ条件

次の環境変数がセットされている場合は何もせず exit 0 する（再帰防止）。

- `CLAUDE_HOOK_SUMMARY_RUNNING=1`
- `CLAUDE_HOOK_FLOW_REPORT_RUNNING=1`

## 2. セルフ project-settings 自動削除

### 背景

Claude Code 本体は cwd を project root として扱い、project-scope settings の保存先を `${cwd}/.claude/settings.local.json` に決定する。
`cwd=$HOME/.claude` で起動されると `~/.claude/.claude/settings.local.json` が自動生成される仕様があり、これを設定や CLI フラグで抑制する公式機能は存在しない。
このまま放置すると `~/.claude/` 直下に意図しない `.claude/` ディレクトリが蓄積し、グローバル設定の汚染や `no-root-marker.md` 規約との混乱を招く。

### 削除対象

- `~/.claude/.claude`（ディレクトリ・ファイル・ダングリング symlink すべて）

### 対象外

- `~/.claude/cache/` — 永続キャッシュ（正規配置）
- `~/.claude/mock-archive/` — mock viewer archive（正規配置）
- その他 `~/.claude/` 配下の正規設定資産

## 機械強制

| timing | スクリプト | 注入タグ | 挙動 |
|---|---|---|---|
| PreToolUse(Skill) | `skill-log-recorder.sh` | なし | スキル発火を JSONL に追記し、`parallel-dev-worktree` 発火時は impl-session マーカーを書く。exit 0 のみ（block なし） |
| SessionStart | `delete-nested-claude-dir.sh` | なし | `~/.claude/.claude` が存在すれば `rm -rf` で削除。存在しなければ即 exit 0 |
| Stop | `delete-nested-claude-dir.sh` | なし | 同上。セッション終了時にも確実に清掃する |

## 違反検知時の手順

本規約の hook はいずれも block / warning を行わない。注入タグなし。

問題発生時の確認手順:

### ログが記録されていない場合

1. hook が settings.json の `PreToolUse` / `Skill` matcher に正しく登録されているか
2. `~/agent-home/sessions/.skill-log/` が存在するか（hook 内で `mkdir -p` するが、親ディレクトリの権限を確認）
3. `~/agent-home/tools/hooks/shared/marker-path.sh` が存在するか（`. "$HOME/agent-home/tools/hooks/shared/marker-path.sh"` で source している）

### `~/.claude/.claude` が消えていない場合

1. hook が settings.json に正しく登録されているか（SessionStart / Stop の両タイミング）
2. hook スクリプトが実行権限を持っているか（`chmod +x` 確認）
3. `rm -rf` が権限エラーで失敗していないか（スクリプトは `chmod -R u+rwx` を試みてから削除する）

## 3. セッションログの命名

### ログファイル名

- Transcript: `claude-code_<uuid>.md`（Claude Code 本体が自動生成。命名は変更不可）
- スキル発火ログ: `<session_id>.jsonl`（`~/agent-home/sessions/.skill-log/` 配下）
- 日付ディレクトリ: `YYYY-MM-DD/`（`~/agent-home/sessions/` 配下）

### エイリアス表

- `~/agent-home/sessions/.skill-log/skill-aliases.yml` — スキルのリネーム・統合・削除時に旧名→現行名を記録する対応表

## プロジェクト上書き

- 上書き可否: 一律適用
- 理由: セッション基盤のサイレント処理であり、上書きの対象になる値を持たないため受け口を設けない

設計判断・経緯の記録は同ディレクトリの `design-notes.txt` を参照（非注入サイドカー）。

## 関連

- `~/.claude/rules/always/placement/file-guard/rule.md` — マーカー書き出し先規約 / `$HOME/.claude/` 直下マーカー禁止規約（両 hook と相補）
- `~/agent-home/tools/hooks/shared/marker-path.sh` — `marker_path` ヘルパー本体
- `~/agent-home/skills/parallel-dev-worktree/SKILL.md` — impl-session マーカーの利用側
