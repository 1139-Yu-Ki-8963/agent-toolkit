# コミット分割の手順

本 references の `module-fixing-review-findings.md` から「PR に無関係コミットが混入している」型の重大な指摘 (`[重大な問題]`) を受けたときに参照する。
PR の本来意図と無関係なコミットを別 PR に切り出し、元 PR をクリーンに戻す。

## 2 つのルート

| ルート | 概要 | 使う場面 |
|---|---|---|
| **R1: rebase + force-push** | 元 PR ブランチから無関係コミットを drop して force-push | force-push が許可される環境（自分の PR、保護ルールなし、`--force-with-lease` が通る） |
| **R2: PR 再起票（close → 新規 PR）** | 元 PR を close し、main 起点の新ブランチに必要コミットを cherry-pick して新規 PR | force-push が block される環境（Auto mode classifier・branch protection・他者承認待ちなど） |

R1 が通れば PR 番号を維持できるが、Auto mode は force-push を block しがち。R1 を 1 度試して block されたら R2 に切り替えるのが現実的。

---

## 共通の前提取得

```bash
WORKTREE="$WORKTREE_PATH"

# 元 PR ブランチのコミット履歴
git -C "$WORKTREE" log --oneline origin/main..HEAD
# → 本来意図のコミット（A）と、切り出したいコミット（B）を識別

# 元 PR の HEAD を origin から取り直して detached HEAD で開始（参照ずれ回避）
git -C "$WORKTREE" fetch origin "$HEADBRANCH"
git -C "$WORKTREE" checkout "origin/$HEADBRANCH"
```

> ローカルブランチをそのまま checkout すると `git push` 前の古い ref を取得することがある。
> 必ず `git fetch && git checkout origin/<branch>` を経由する。

---

## ルート R1: rebase + force-push

### R1-1. 切り出すコミットを別ブランチに保存

```bash
# 別ブランチを main 起点で作成し、切り出すコミットを cherry-pick
git -C "$WORKTREE" checkout -b "<split-branch>" origin/main
git -C "$WORKTREE" cherry-pick <split_sha>

# push（新規 ref 追加のみで非破壊）
git -C "$WORKTREE" push origin "<split-branch>"
```

### R1-2. 別 PR を作成

```bash
gh pr create --base main --head "<split-branch>" --title "..." --body "..."
```

### R1-3. 元ブランチから当該コミットを drop

```bash
# 元ブランチを最新の origin から取り直し（参照ずれ回避）
git -C "$WORKTREE" checkout "origin/$HEADBRANCH"

# rebase --onto で <split_sha> を skip
# 構文: git rebase --onto <親> <skip対象> <branch>
git -C "$WORKTREE" rebase --onto <split_sha_parent> <split_sha>

# branch ref を更新して force-push
git -C "$WORKTREE" branch -f "$HEADBRANCH"
git -C "$WORKTREE" checkout "$HEADBRANCH"
git -C "$WORKTREE" push --force-with-lease origin "$HEADBRANCH"
```

### R1 が block された場合

`git rebase` または `git push --force-with-lease` が Auto mode classifier 等で block されたら、
**作業を中断して R2 に切り替える**（中途半端な force-push を残さないため）。

---

## ルート R2: PR 再起票（close → 新規 PR）

force-push を一切使わず、元 PR を close して新規 PR を作る。

### R2-1. 必要コミットを別ブランチに cherry-pick

```bash
# main 起点で v2 ブランチを作成
git -C "$WORKTREE" checkout -b "<original-branch>-v2" origin/main

# 「本来意図のコミット」だけを順序通り cherry-pick
# （切り出したいコミットは含めない）
git -C "$WORKTREE" cherry-pick <commit_a> <commit_b> <commit_c>

# diff が想定通りか確認
git -C "$WORKTREE" diff origin/main..HEAD --stat
```

> cherry-pick の起点に注意。元ブランチで「コミット A → コミット B（無関係） → コミット C」の順なら、
> A と C を別々に cherry-pick すると C が main 起点で衝突する。**A → C の依存関係を満たす順序** で
> 必要コミット全てを cherry-pick すること（A も含めて取りこぼさない）。

### R2-2. push（新規 ref 追加のみで非破壊）

```bash
git -C "$WORKTREE" push origin "<original-branch>-v2"
```

### R2-3. 「無関係コミット」だけを切り出した別ブランチを別途作成（任意）

切り出すコミットが将来必要なら、main 起点でその commit のみ cherry-pick して push する。
不要なら省略してよい（commit は元 PR の close 後も `git log` で参照可能）。

```bash
git -C "$WORKTREE" checkout -b "<split-branch>" origin/main
git -C "$WORKTREE" cherry-pick <split_sha>
git -C "$WORKTREE" push origin "<split-branch>"
gh pr create --base main --head "<split-branch>" --title "..." --body "..."
```

### R2-4. 元 PR を close（理由をコメント付きで記録）

```bash
gh pr close NUMBER --comment "コミット分割のため再起票します。
- 本来意図のコミット → PR #<新番号> として再作成
- 無関係コミット → PR #<別番号> として切り出し（または \`git log <split_sha>\` で参照）

force-push を回避するため close → 新規作成の手順を採用。
レビューコメント履歴は本 PR で参照可能です。"
```

### R2-5. 新規 PR を作成（v2 ブランチから）

```bash
gh pr create \
  --base main \
  --head "<original-branch>-v2" \
  --title "<元タイトル>（再起票）" \
  --body "<元 PR 番号> のコミット分割再起票。<本来意図> のみを含む。"
```

---

## 共通: 完了確認

```bash
# v2（または rebase 後）の HEAD が想定通りか
git -C "$WORKTREE" log --oneline origin/main..HEAD

# 元 PR と新 PR の状態
gh pr view <元番号>     --json state   # closed (R2 のみ) / open (R1)
gh pr view <新番号>     --json state   # open
gh pr view <切り出し番号> --json state   # R1-2 / R2-3 で別 PR を作成した場合のみ確認
```

新 PR が `MERGEABLE` であること、CI が走っていれば pass していることを確認してから、
スキル本体の Phase 8-3（マージ確認）に戻る。

---

## Auto mode classifier への対応メモ

- `git push origin <new-branch>` の **新規** ref 追加は通常 block されない
- `git push --force-with-lease` は **既存 ref 上書き** として block されることが多い → R2 に逃げる
- `gh pr close` は外部書き込みとして block されることがある → 計画段階で `ExitPlanMode(allowedPrompts=...)` に含めるか、AskUserQuestion で個別承認
- `gh pr merge --admin` は critical 指摘が残っていると block されやすい → 切り出しで critical 解消後に再試行
