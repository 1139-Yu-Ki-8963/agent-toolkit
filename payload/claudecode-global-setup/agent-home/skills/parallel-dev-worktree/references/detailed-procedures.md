# parallel-dev-worktree 詳細手順

SKILL.md の各 Phase を、実機で動かすときに必要な完全版コマンドと例外処理にまで踏み込んで補足する読み物。

## 共通変数の取得（完全版）

```bash
# メイン作業ツリーの絶対パス
REPO=$(git rev-parse --show-toplevel) || { echo "ここは git リポジトリではない"; exit 1; }

# デフォルトブランチ名（origin/HEAD のシンボリックリンクから取得）
DEFAULT_BRANCH=$(git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's@^origin/@@')
if [ -z "$DEFAULT_BRANCH" ]; then
  # origin/HEAD が未設定 → リモートから取得を試みる
  git -C "$REPO" remote set-head origin --auto >/dev/null 2>&1
  DEFAULT_BRANCH=$(git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's@^origin/@@')
fi
# どうしても取れない場合のフォールバック
[ -z "$DEFAULT_BRANCH" ] && DEFAULT_BRANCH=main

REPO_NAME=$(basename "$REPO")
WORKTREE_ROOT="$HOME/Projects/worktrees/$REPO_NAME"
mkdir -p "$WORKTREE_ROOT"

# GitHub リモートかどうかを判定
if gh repo view --json url >/dev/null 2>&1; then
  HAS_GH=yes
else
  HAS_GH=no
fi
```

## Phase 1: 着手前チェックの完全版

```bash
# 1) 作業ツリーの汚れチェック
DIRTY=$(git -C "$REPO" status --short)
if [ -n "$DIRTY" ]; then
  echo "[STOP] メイン作業ツリーに未コミット変更があります:"
  echo "$DIRTY"
  echo "ユーザーに stash するか・先にコミットするか確認してください"
  exit 1
fi

# 2) 現在ブランチの確認
CURRENT_BRANCH=$(git -C "$REPO" branch --show-current)
if [ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ]; then
  echo "[INFO] 現在 $CURRENT_BRANCH にいます（期待: $DEFAULT_BRANCH）"
  echo "ユーザーに理由を確認してください"
fi

# 3) OPEN PR の取得（GitHub のみ）
if [ "$HAS_GH" = yes ]; then
  OPEN_PRS=$(gh pr list --state open --json number,title,headRefName,files --limit 30)
fi

# 4) origin の最新化（ローカルの $DEFAULT_BRANCH ブランチには触らない）
git -C "$REPO" fetch origin "$DEFAULT_BRANCH" --prune
```

## Phase 2: コンフリクトしたファイル衝突予測の完全版

```bash
# プロジェクト側 CLAUDE.md にコンフリクトしたファイル定義があるか
HAS_HOTFILES=no
if grep -nE '^#{1,3}\s*コンフリクトしたファイル' "$REPO/CLAUDE.md" 2>/dev/null; then
  HAS_HOTFILES=yes
fi

# これから触る予定のファイル（ユーザー指示から決定済みとする）
PLANNED_FILES=(
  "frontend/src/api/client.ts"
  "backend/app/routers/battles.py"
)

# OPEN PR との突合（jq が前提）
if [ "$HAS_GH" = yes ] && [ -n "$OPEN_PRS" ]; then
  for f in "${PLANNED_FILES[@]}"; do
    CONFLICT=$(echo "$OPEN_PRS" | jq -r --arg f "$f" '
      .[] | select(.files[]?.path == $f) |
      "PR #\(.number) (\(.headRefName)): \(.title)"
    ')
    if [ -n "$CONFLICT" ]; then
      echo "[CONFLICT] $f は次の OPEN PR と競合します:"
      echo "$CONFLICT"
      # → ユーザーに「先方 PR のマージ待ち / 並走 / 統合」のどれを取るか確認
    fi
  done
fi
```

## Phase 3: worktree 作成の完全版と失敗パターン

```bash
BRANCH="feature/profile-cache-headers"   # 命名規約（rules: always/naming/commit-branch）に従う
WT="$WORKTREE_ROOT/$BRANCH"

# 既に同名ブランチが存在する場合
if git -C "$REPO" show-ref --verify --quiet "refs/heads/$BRANCH"; then
  echo "[STOP] ブランチ $BRANCH は既にローカルに存在します"
  echo "選択肢:"
  echo "  A) 別名にする（推奨）"
  echo "  B) 既存ブランチを Phase 7 の手順で再利用する"
  echo "  C) ユーザーが手動で削除指示を出す"
  exit 1
fi

# 既に同名 worktree パスが存在する場合
if [ -d "$WT" ]; then
  echo "[STOP] worktree パス $WT は既に存在します"
  echo "  → ls -la \"$WT\" で中身を確認しユーザーに判断を仰ぐ"
  exit 1
fi

# worktree 作成
git -C "$REPO" worktree add -b "$BRANCH" "$WT" "origin/$DEFAULT_BRANCH"
```

## Phase 6: worktree remove 失敗時の復旧

`git worktree remove` が失敗するケースと対処:

| 失敗メッセージ | 原因 | 対処 |
|------|------|------|
| `contains modified or untracked files` | worktree 内に未コミット変更がある | `cd "$WT" && git status` で内容確認 → ユーザーに「コミット・stash・破棄」を選んでもらう。**勝手に破棄しない** |
| `is locked` | `git worktree lock` で意図的にロックされている | `git worktree unlock "$WT"` を提案する前にロックの理由をユーザーに確認 |
| `submodule` 関連 | submodule の状態が dirty | submodule 内で `git status` を実行し、ユーザーに対処を仰ぐ |
| `nested worktree found` | worktree 内にさらに worktree がある（pr-review-daily 等） | 内側の worktree を先に `git worktree remove` してから外側を畳む |

通常の手順:

```bash
cd "$REPO"
git -C "$REPO" worktree remove "$WT"
git -C "$REPO" worktree prune
git -C "$REPO" branch --show-current   # → $DEFAULT_BRANCH であるべき
```

ローカルブランチを残したくない場合（ユーザーが明示指定した場合のみ）:

```bash
git -C "$REPO" branch -d "$BRANCH"   # マージ済みであれば削除可能
# マージ前に削除したい場合は -D（強制削除、確認後のみ）
```

## 非 GitHub リモートでのフォールバック

| 状況 | 挙動 |
|------|------|
| GitLab / Bitbucket / 自前 git サーバー | Phase 1-3 の `gh pr list` を skip。Phase 5 は `git push -u origin "$BRANCH"` で停止し、ユーザーに「リモートはこのリポジトリの web UI で PR を作ってください」と通知する |
| リモート設定なし（ローカルのみ）| Phase 1-3 の `gh pr list` を skip。Phase 5 で `git push` 自体が失敗するため、ユーザーに「`origin` リモートが未設定です。push 前に `git remote add origin <URL>` を実行してください」と通知する |
| `origin/HEAD` 未設定 | Phase 共通変数取得時に `git remote set-head origin --auto` で自動設定を試行。失敗したら `main` をフォールバックに使い、ユーザーに「`origin/HEAD` が設定されていないため `main` を仮定しました」と通知する |

## カスタマイズ方法

`~/Projects/worktrees/` 以外を使いたい場合、各 Phase の冒頭で:

```bash
WORKTREE_ROOT="${PARALLEL_DEV_WORKTREE_ROOT:-$HOME/Projects/worktrees/$REPO_NAME}"
```

として環境変数 `PARALLEL_DEV_WORKTREE_ROOT` で上書きできる。

## デバッグコマンド

```bash
# 現存 worktree 一覧
git -C "$REPO" worktree list

# 孤児 worktree のクリーンアップ（実体ディレクトリが消えているもの）
git -C "$REPO" worktree prune --dry-run
git -C "$REPO" worktree prune

# .git/worktrees/ の生データ（緊急時のみ）
ls -la "$REPO/.git/worktrees/"
```

## よくある誤操作と防御

| 誤操作 | 防御 |
|------|------|
| メイン作業ツリーで `git pull origin main` | Phase 1 で「fetch のみ」と明記。pull は使わない |
| 既存 worktree がある状態で同名 `worktree add` | Phase 3 の存在チェックで停止 |
| PR 作成前に worktree を畳む | Phase 6 の発動条件を「PR 作成完了時点」に固定 |
| Phase 7 で `-b` を付けて再 checkout | Phase 7 の手順に「`-b` は付けない」と明記 |
| worktree 内の未コミット変更ごと remove | Phase 6 の失敗時は強制削除しない |
