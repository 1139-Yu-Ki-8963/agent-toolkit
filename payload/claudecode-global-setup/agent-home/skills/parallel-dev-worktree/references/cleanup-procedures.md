# cleanup-procedures — Phase 6 後片付け詳細 / Phase 7 再 checkout 手順

`parallel-dev-worktree/SKILL.md` の Phase 6・Phase 7 から参照される詳細手順。

## Phase 6: 後片付け詳細

worktree 専用のポート・コンテナ・ボリュームを起動していた場合、`git worktree remove` の前に後始末する（ポート管理規約: `~/.claude/rules/always/local-environment/port-management/rule.md`）。

1. ポートの後始末: 当該 worktree の `.port-slot` を読んでスロット番号 N を確定し、ベース+N*10 〜 +9 のレンジで LISTEN 中のプロセスを検出して kill する
   ```bash
   N=$(cat "$WT/.port-slot" 2>/dev/null)
   if [ -n "$N" ]; then
     BASE=8000   # プロジェクト別ベースポート。port-values.txt の割当表に従う
     for p in $(seq $((BASE + N*10)) $((BASE + N*10 + 9))); do
       lsof -ti :"$p" 2>/dev/null | xargs kill -9 2>/dev/null
     done
   fi
   ```
2. コンテナ・ボリュームの後始末: worktree 専用の compose project（例: `<project>-wt<N>`）でコンテナを起動していた場合、
   ```bash
   supabase stop --project-id "<project>" \
     || docker ps -a --filter "label=com.docker.compose.project=<project>" -q | xargs -r docker rm -f
   docker volume ls --format '{{.Name}}' | grep "<project>$" | xargs -r docker volume rm
   ```

上記 1・2 が完了してから `git worktree remove` する。

## Phase 7: 再 checkout 手順

PR 作成済みで worktree を畳んだ後にレビュー指摘が来た場合:

```bash
BRANCH="feature/profile-cache-headers"
WT="$WORKTREE_ROOT/$BRANCH"
git -C "$REPO" fetch origin "$BRANCH"
git -C "$REPO" worktree add "$WT" "$BRANCH"
cd "$WT"
```

- 既に push 済みのブランチを再 checkout する形。**`-b` は付けない**
- 修正 → push → Phase 6 を再実行
