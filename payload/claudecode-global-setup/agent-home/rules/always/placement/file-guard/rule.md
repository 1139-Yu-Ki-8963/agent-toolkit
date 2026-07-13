# ファイル配置・書き出し先ガード（FILE-GUARD）

ファイルの配置先と書き出し先を機械強制する規約。CWD 直下への撒き散らし禁止と `$HOME/.claude/` 直下へのマーカー禁止の 2 軸。

## 1. ファイル配置規約

### 3 大禁止

1. **root に一時ファイルを作らない** — スクラッチ・ドラフト・調査メモは `$CLAUDE_JOB_DIR/tmp/` に置く
2. **Playwright 出力は `~/agent-home/tools/MCP/playwright/` に集約** — プロジェクト root に `.playwright-mcp/` を作らない
3. **許可リスト外の root 直下ファイル/フォルダの新規作成は禁止** — README.md / package.json / src 等の既知の設計資産以外を root に作らない

### 正規退避先

| 用途 | 退避先 |
|---|---|
| 一時ファイル（スクラッチ・調査メモ） | `$CLAUDE_JOB_DIR/tmp/<name>` |
| Playwright 自動生成物（screenshot / trace 等） | `$HOME/agent-home/tools/MCP/playwright/<name>` |
| 永続キャッシュ | `$HOME/.claude/cache/<feature>/<key>` |
| hook の状態マーカー | `<worktree_root>/.claude/markers/<session>/<name>` または `${TMPDIR:-/tmp}/claude-hooks/<session>/<name>` |
| ドキュメント成果物（明示的に commit するもの） | `<repo>/docs/<feature>/screenshots/<name>` 等の **明示パス** |

`$CLAUDE_JOB_DIR` が未設定の場合は `${TMPDIR:-/tmp}/claude-job-${session}/` をフォールバックに使う。

### Playwright MCP の罠

`mcp__playwright__browser_take_screenshot` の `filename` 引数は **CWD 相対で解釈される**。CWD は通常リポジトリルートのため、`filename: "foo.png"` のような相対指定は **リポジトリ root に直接 PNG を書き出す**。

**対策: 絶対パス必須**。

```text
# ✗ 違反（CWD = リポジトリ root に直書き）
mcp__playwright__browser_take_screenshot { filename: "foo.png" }
mcp__playwright__browser_take_screenshot { filename: "screenshots/foo.png" }

# ✓ 許可（絶対パス、3 種類いずれか）
mcp__playwright__browser_take_screenshot { filename: "/Users/MacPro/.claude/jobs/<job>/tmp/foo.png" }
mcp__playwright__browser_take_screenshot { filename: "/Users/MacPro/agent-home/tools/MCP/playwright/foo.png" }
mcp__playwright__browser_take_screenshot { filename: "/Users/MacPro/Projects/<repo>/docs/<feature>/screenshots/foo.png" }
```

`Write` / `Edit` の `file_path` も、相対パスはリポジトリ root を起点として解決される可能性がある。新規ファイル作成では常に絶対パスを使う。

## 2. ルート直下マーカー禁止

### 背景

過去、グローバル hook 10 本とプロジェクト hook 8 本が `$HOME/.claude/.<name>-${session}` 形式のマーカーをルート直下に touch し続け、最大 821 件のドットファイルが蓄積した。本規約はこの再発を機械強制で防ぎ、**マーカーが main ブランチに持ち込まれることも禁止** する。

セッション ID に紐付くマーカー（カウンター・スティッキー・disable フラグ）は当該セッション中だけ意味があり、セッションが終わったら hook 自身も二度と参照しない。永続化する必要は一切無く、保存場所は揮発で十分。

### 書き出し先規約

`marker_path "$cwd" "$session" "<name>"` ヘルパーが次のロジックで書き出し先を決定する。

| cwd の状態 | 書き出し先 |
|---|---|
| worktree（`.git` がファイル） | `${worktree_root}/.claude/markers/${session}/<name>` |
| メインツリー、git 管理外、または cwd 不明 | `${TMPDIR:-/tmp}/claude-hooks/${session}/<name>` にフォールバック |
| ワンショット例外（人間が手で touch） | `/tmp/.allow-<name>` |
| 永続キャッシュ | `$HOME/.claude/cache/<feature>/<key>` |
| mock-viewer archive（issue#1587） | `$HOME/.claude/mock-archive/issue-<N>/<sha8>-mockup.html` |

`mock-archive/` は永続的な mock HTML 保管ディレクトリで、ルート直下ドットファイル禁止対象には含まれない（ドット始まりではないため `check-claude-home-root-marker.sh` の検出パターン外）。

### main ブランチへの持ち込み禁止（三重保証）

1. **`.gitignore`** に `.claude/markers/` を追加（worktree と main ツリーは同一の `.gitignore` を共有するので commit に絶対入らない）
2. **メインツリーでは hook が markers/ を作らない**（cwd 判定で `/tmp` にフォールバック）
3. **pre-commit hook** で `.claude/markers/` を含む commit を block（保険）

### 共通テンプレート

全 hook（グローバル・プロジェクト共通）:

```sh
. "$HOME/agent-home/tools/hooks/shared/marker-path.sh"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$cwd" ] && cwd="$PWD"
counter="$(marker_path "$cwd" "$session" pr-progress-gate.count)"
```

`marker_path` は親ディレクトリを `mkdir -p` してからフルパスを echo するヘルパー。cwd が worktree なら worktree 内、それ以外は `/tmp/claude-hooks/${session}/` を返す。

### 例外（check-claude-home-root-marker.sh が block しないパス）

- `${TMPDIR:-/tmp}/claude-hooks/**`（正規の揮発書き出し先）
- `**/.claude/markers/**`（worktree 内の正規書き出し先）
- `$HOME/.claude/cache/**`（永続キャッシュ）
- `/tmp/.allow-*`（ワンショット例外）
- `$HOME/.claude/.last-cleanup`、`$HOME/.claude/.last-update-result.json`、`$HOME/.claude/.gitignore`、`$HOME/.claude/.gcs-sha`（既存メタファイル）

## 機械強制

| timing | hook | 注入タグ | 挙動 |
|---|---|---|---|
| PreToolUse(mcp__playwright__browser_take_screenshot) | `~/.claude/rules/always/placement/file-guard/check-playwright-filename.sh` | `[FILE-PLACEMENT-BLOCK]` | `tool_input.filename` を抽出し、絶対パスかつ許可ロケーション配下でなければ exit 2 で block |
| PreToolUse(Bash) | `~/.claude/rules/always/placement/file-guard/check-claude-home-root-marker.sh`（rules-bash-runner 経由） | `[CLAUDE-HOME-ROOT-MARKER-BLOCK]` | `touch "$HOME/.claude/.<word>"` / `> "$HOME/.claude/.<word>"` パターンを検出して exit 2 で block |
| SessionEnd | `~/.claude/rules/always/placement/file-guard/cleanup-session-markers.sh` | — | `${TMPDIR:-/tmp}/claude-hooks/${session}` と worktree 内 `.claude/markers/${session}` を `rm -rf` |
| SessionStart | `~/.claude/rules/always/placement/file-guard/cleanup-stale-hook-sessions.sh` | — | `/tmp/claude-hooks/` 直下の 7 日超 orphan セッションディレクトリを掃除 |

### 既知ギャップ

`Write` ツールでリポジトリ root に新規ファイルを作成する経路は機械強制されていない。root への一般的な新規ファイル創出を block する hook は将来課題。本規約遵守と Playwright 専用 hook が当面の防衛線となる。

## 違反検知時の手順

### `[FILE-PLACEMENT-BLOCK]` 受信

1. 3 大禁止と退避先表で正解の置き場を確定する
2. block された Playwright 呼び出しの `filename` を絶対パスに書き換える（`$CLAUDE_JOB_DIR/tmp/` 展開後の絶対パスを使う）
3. 既に CWD 直下に出力済みのファイルがあれば清掃:
   - `git rm --cached <file>` で staging から除外
   - 必要なら `mv <file> $CLAUDE_JOB_DIR/tmp/<file>` で正規退避先へ移動
   - 不要なら `rm <file>`

### `[CLAUDE-HOME-ROOT-MARKER-BLOCK]` 受信

1. ブロックされたコマンドの touch 先を `${TMPDIR:-/tmp}/claude-hooks/${session}/<name>` または `${worktree_root}/.claude/markers/${session}/<name>` に書き換える
2. 該当 hook スクリプト自体がベタ書きしている場合は、共通テンプレートに沿って hook を改修する
3. 既存マーカーの移行が必要な場合は、書き出し先ディレクトリだけ修正し、古いセッション ID のものは触らない（SessionEnd hook が自動清掃する）

## プロジェクト上書き

- 上書き可否: 一律適用
- 理由: 配置・マーカー規約はマシン全体のファイルシステム衛生であり、プロジェクトに依存しないため受け口を設けない

設計判断・経緯の記録は同ディレクトリの `design-notes.txt` を参照（非注入サイドカー）。

## 関連

- `~/.claude/rules/scoped/agent-config/hooks/rule.md` — hook 配置 4 象限（本 hook の配置根拠）
