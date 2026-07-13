# テスト完了マーカー（report必須・ハッシュ照合方式）

テスト全項目 PASS の場合、以下の手順で2つの成果物を書き出す（`<type>` は `skills` / `rules` / `routines` / `hooks` のいずれか）。

**Step 1: reportファイルの作成（Writeツール）**

`managing-agent-configs-${type}-report.md`（配置先はneededマーカーと同じディレクトリ）に、review Phaseのレポート（対象アセットごとのCRITICAL/WARN/INFO件数）とtest Phaseの実行検証結果（要件チェックリストの達成状況・シナリオ結果）を実際の内容で記載する。CRITICAL 0件かつtest実行検証で要件達成の場合のみ、末尾に以下の1行を含める:

```
REVIEW-TEST-VERDICT: PASS
```

CRITICALが残る、またはtest未実施の場合はこの行を書かない（この場合commitは許可されない）。

**Step 2: ハッシュ計算とマーカー書き出し（Bash）**

```bash
type=<type>   # skills / rules / routines / hooks のいずれか
needed=$(ls -t \
  "$(git rev-parse --show-toplevel 2>/dev/null)/.claude/markers/"*/managing-agent-configs-$type-needed \
  ${TMPDIR:-/tmp}/claude-hooks/*/managing-agent-configs-$type-needed \
  2>/dev/null | head -1)
if [ -n "$needed" ]; then
  . "$HOME/agent-home/tools/hooks/shared/marker-path.sh"
  root=$(git rev-parse --show-toplevel)
  report="${needed%-needed}-report.md"
  report_hash=$(shasum -a 256 "$report" | awk '{print $1}')
  {
    echo "REPORT_SHA256=${report_hash}"
    ( cd "$root" && git status --porcelain=v1 | sed 's/^...//' | sed 's/.* -> //' \
      | while IFS= read -r f; do
          [ "$(managed_asset_type "$f")" = "$type" ] && [ -f "$f" ] && shasum -a 256 "$f"
        done )
  } > "${needed%-needed}-test-passed"
fi
```

このコマンドは PostToolUse の `check-managing-configs-review-needed.sh` が編集検知時に作成した `-needed` マーカーと同一ディレクトリに、report ハッシュを先頭行に含む `-test-passed` を置く。`marker_path` の解決先（worktree では `<worktree_root>/.claude/markers/<session>/`、非 worktree では `${TMPDIR:-/tmp}/claude-hooks/<session>/`）と一致するため、置き場ズレによる commit の誤ブロックが起きない。

`-test-passed` マーカーは空 touch ではなく、`REPORT_SHA256=<hash>` の1行 + 当該種別の managed ファイルそれぞれの現在の内容ハッシュ（`shasum -a 256` 形式、`<sha256>  <relpath>` の行列挙）を記録する。`check-managing-configs-commit-gate.sh`（PreToolUse(Bash)）は commit 時に、report ファイルの実在・`REVIEW-TEST-VERDICT: PASS` 行の有無・report の鮮度（needed マーカーとの mtime 比較）・report のハッシュが `REPORT_SHA256=` 行と一致するか・staged 内容のハッシュ一致、の全てを検証する。いずれか1つでも欠ければ commit を block する（「stale」または「report欠落」として扱う）。

マーカー機構は2つの hook で成り立つ。`check-managing-configs-review-needed.sh`（PostToolUse(Write|Edit|MultiEdit)）が managed ファイルの編集を検知した時点で `-needed` マーカーを付与する（`-test-passed` / report の削除は行わない。stale 判定は commit-gate 側の検証が担う）。`check-managing-configs-commit-gate.sh`（PreToolUse(Bash)）がこれらのマーカー・reportの有無とハッシュ一致で `git commit` の許可を判定する。マーカーはセッション終了時に `cleanup-session-markers.sh` で自動削除される。`subagents` 種別は commit gate の対象外のためマーカー書き出し不要。

監視パスの正本は `~/agent-home/tools/hooks/shared/marker-path.sh` の `managed_asset_type()`。新しい managed ディレクトリを追加する場合はこの関数を更新する。
