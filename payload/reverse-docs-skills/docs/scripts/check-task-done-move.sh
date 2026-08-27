#!/usr/bin/env bash
# check-task-done-move.sh — git commit 直前に、staged の変更が docs/tasks/done/ へ
# ファイルを追加(A)またはリネーム(R)で入れていないかを見る。入れている場合は
# judge-task-done.sh の3条件（記録が済んでいる・main へ入っている・公開が済んでいる）を
# 対象ファイルごとに満たしているか確かめ、満たさないものがあれば止める（exit 1）。
#
# 判定の実装は持たない。judge-task-done.sh を呼び出し、その出力をそのまま使う。
# 両者がずれると、どちらが正か分からなくなるため。
#
# 使い方:
#   bash docs/scripts/check-task-done-move.sh              staged を判定し、exit code で結果を返す
#   bash docs/scripts/check-task-done-move.sh --self-test   自己テスト（6ケース）を実行する
#
# 緊急口: TASK_DONE_MOVE_SKIP_REASON="<理由>" git commit ... で通す。理由なしでは通らない。
#
# 実装方針（使い捨ての git worktree を使う理由）:
#   judge-task-done.sh は docs/tasks/*.md（直下）だけを走査する。staged で
#   docs/tasks/done/ へ移された対象はもう直下に無いため、そのままでは判定できない。
#   git worktree add で HEAD からの使い捨てのworktreeを作る（.git オブジェクトを
#   共有するため、コミットの実在確認や main 祖先判定はそのまま機能する）。その
#   worktree の docs/tasks/直下へ、staged content（git show ":<path>"）を書き戻して
#   から judge-task-done.sh を実行し、出力の「移せる:」一覧に対象が含まれるかを見る。
#   元のリポジトリ（作業ツリー・インデックス・HEAD）は一切書き換えない。使い捨ての
#   worktree は判定後に必ず削除する。
#
#   簡易な代替（関数だけを source して呼ぶ・「公開の状態:」の1行だけを読む）は
#   採らなかった。上記の worktree 方式で該当ファイルをそのまま judge-task-done.sh に
#   渡せたため、簡易な代替へ落とす必要が無かった。設計判断の全文は
#   docs/design/指示書の片付け方.md の「設計判断」節を参照する。
#
# 制約: mktemp と git worktree を使うため、実行にはリポジトリへの書き込み権限が要る
#   （sandbox環境では dangerouslyDisableSandbox 相当の許可が要る）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 実装判断: 配布物の境界を先に探す。git の祖先探索だけに頼ると、公開先
#   （agent-toolkit/payload/reverse-docs-skills/）へ埋め込まれたとき、外側の
#   リポジトリのルートを掴んでしまう。実測（2026-08-27）で配布先の第1層集約が
#   外側の docs/scripts/judge-task-done.sh を探して失敗した。
#   generation-engine/DESIGN.md を配布物の目印とし、それが見つかった時点で探索を止める。
REPO_ROOT=""
_probe="$SCRIPT_DIR"
while [ "$_probe" != "/" ] && [ -n "$_probe" ]; do
  if [ -f "$_probe/generation-engine/DESIGN.md" ]; then
    REPO_ROOT="$_probe"
    break
  fi
  _probe="$(dirname "$_probe")"
done
if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"
fi
if [ -z "$REPO_ROOT" ]; then
  echo "ERROR: 配布物の境界も git リポジトリも見つからない" >&2
  exit 1
fi

SELF_PATH="$SCRIPT_DIR/check-task-done-move.sh"
JUDGE_SCRIPT_REL="docs/scripts/judge-task-done.sh"
JUDGE="$REPO_ROOT/$JUDGE_SCRIPT_REL"
SHARED_CONTENT_LINE="check-task-done-move selftest shared content"

command -v git >/dev/null 2>&1 || { echo "ERROR: git が無い" >&2; exit 1; }

# ---------- 判定本体（repo_root を引数に取り、自己テストからも使い回す） ----------
# 戻り値: 0 = 移してよい（対象なし、または全対象が3条件を満たす）
#         1 = 移せない対象がある、またはエラー
run_check_for_repo() {
  local repo_root="$1"
  local judge="$repo_root/$JUDGE_SCRIPT_REL"

  if [ ! -f "$judge" ]; then
    echo "ERROR: $judge が無い" >&2
    return 1
  fi

  local diff_output
  diff_output="$(git -C "$repo_root" diff --cached --name-status -M -- docs/tasks/ 2>/dev/null || true)"

  local -a targets=()
  local status p1 p2
  while IFS=$'\t' read -r status p1 p2; do
    [ -z "$status" ] && continue
    case "$status" in
      A*)
        case "$p1" in
          docs/tasks/done/*.md) targets+=("$p1") ;;
        esac
        ;;
      R*)
        case "$p2" in
          docs/tasks/done/*.md) targets+=("$p2") ;;
        esac
        ;;
    esac
  done <<< "$diff_output"

  if [ "${#targets[@]}" -eq 0 ]; then
    return 0
  fi

  local tmp_wt
  tmp_wt="$(mktemp -d "${TMPDIR:-/tmp}/check-task-done-move-wt.XXXXXX")"
  rmdir "$tmp_wt"
  if ! git -C "$repo_root" worktree add --detach "$tmp_wt" HEAD >/dev/null 2>&1; then
    echo "ERROR: 判定用の使い捨て worktree を作成できなかった" >&2
    return 1
  fi

  local t base
  local setup_failed=0
  for t in "${targets[@]}"; do
    base="$(basename "$t")"
    mkdir -p "$tmp_wt/docs/tasks"
    if ! git -C "$repo_root" show ":$t" > "$tmp_wt/docs/tasks/$base" 2>/dev/null; then
      echo "ERROR: staged 内容(${t})を読めなかった" >&2
      setup_failed=1
    fi
  done

  if [ "$setup_failed" -eq 1 ]; then
    git -C "$repo_root" worktree remove --force "$tmp_wt" >/dev/null 2>&1
    rm -rf "$tmp_wt" 2>/dev/null
    return 1
  fi

  local out
  out="$(bash "$tmp_wt/$JUDGE_SCRIPT_REL" 2>&1)"

  git -C "$repo_root" worktree remove --force "$tmp_wt" >/dev/null 2>&1
  rm -rf "$tmp_wt" 2>/dev/null

  local movable_section
  movable_section="$(printf '%s\n' "$out" | LC_ALL=C awk '/^移せる:/{f=1;next} /^$/{if(f)exit} f')"

  local fail=0
  for t in "${targets[@]}"; do
    base="$(basename "$t")"
    if ! printf '%s\n' "$movable_section" | grep -qF -- "- $base"; then
      fail=1
      local reason
      reason="$(printf '%s\n' "$out" | grep -F -- "- ${base}:" | head -1)"
      echo "ERROR: docs/tasks/done/${base} は judge-task-done.sh の条件を満たしていない" >&2
      if [ -n "$reason" ]; then
        echo "  ${reason}" >&2
      fi
    fi
  done

  [ "$fail" -eq 0 ]
}

# ---------- 自己テスト用のヘルパー ----------

_setup_base_repo() {
  local repo="$1"
  mkdir -p "$repo/docs/scripts" "$repo/docs/tasks"
  git -C "$repo" init -q
  git -C "$repo" config user.email "selftest@example.com"
  git -C "$repo" config user.name "Self Test"
  git -C "$repo" config commit.gpgsign false
  cp "$JUDGE" "$repo/docs/scripts/judge-task-done.sh"
  printf '%s\n' "$SHARED_CONTENT_LINE" > "$repo/README.md"
  : > "$repo/docs/tasks/.gitkeep"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m base
  local cur
  cur="$(git -C "$repo" symbolic-ref --short HEAD 2>/dev/null || echo main)"
  if [ "$cur" != "main" ]; then
    git -C "$repo" branch -M main
  fi
}

_setup_toolkit_mirror() {
  local toolkit="$1"
  mkdir -p "$toolkit/payload/reverse-docs-skills"
  git -C "$toolkit" init -q
  git -C "$toolkit" config user.email "selftest@example.com"
  git -C "$toolkit" config user.name "Self Test"
  git -C "$toolkit" config commit.gpgsign false
  printf '%s\n' "$SHARED_CONTENT_LINE" > "$toolkit/payload/reverse-docs-skills/README.md"
  git -C "$toolkit" add -A
  git -C "$toolkit" commit -q -m base
  local cur
  cur="$(git -C "$toolkit" symbolic-ref --short HEAD)"
  # @{u}（追跡先）の解決には branch.<name>.remote が指す名前が
  # 実在する remote として登録されている必要がある（実測で確認済み）。
  # 実際に fetch はしないため URL はダミーでよい。
  git -C "$toolkit" remote add origin "file:///dev/null" >/dev/null 2>&1 || true
  git -C "$toolkit" update-ref refs/remotes/origin/main "$(git -C "$toolkit" rev-parse HEAD)"
  git -C "$toolkit" config "branch.${cur}.remote" origin
  git -C "$toolkit" config "branch.${cur}.merge" refs/heads/main
}

_write_doc() {
  local path="$1" status="$2" commit="$3"
  # judge-task-done.sh は段階2（実測）で「確かめる手段」列を必須とする（列が無い
  # 表は一律に「確かめる手段の列が無い」として満たさない扱いになる。同スクリプトの
  # 「既知の副作用」コメントを参照）。3列の表（項目|状態|コミット）のままでは
  # 「3条件充足-通る」ケースが常に段階2で止まってしまうため、5列の表
  # （判定|確かめる手段|状態|コミット|確かめた内容）へ揃え、確かめる手段には
  # 常に終了コード0を返す `true` を置く。
  {
    echo "# タイトル"
    echo
    echo "## 対応の記録"
    echo
    echo "### 判定の充足状況"
    echo
    echo "| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |"
    echo "|---|---|---|---|---|"
    echo "| 動作確認 | true | ${status} | ${commit} | 済 |"
  } > "$path"
}

_stage_done_move() {
  local repo="$1" filename="$2"
  mkdir -p "$repo/docs/tasks/done"
  git -C "$repo" mv "docs/tasks/$filename" "docs/tasks/done/$filename"
}

run_self_test() {
  if [ ! -f "$JUDGE" ]; then
    echo "ERROR: judge-task-done.sh が見当たらない: $JUDGE" >&2
    return 1
  fi

  local base_tmp
  base_tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-task-done-move-selftest.XXXXXX")"
  local no_toolkit="$base_tmp/no-toolkit"

  local -a NAMES=()
  local -a RESULTS=()
  local rc

  # ケース1: staged に done/ への追加が無い → 通る
  local repo1="$base_tmp/repo1"
  _setup_base_repo "$repo1"
  TASK_DONE_TOOLKIT_DIR="$no_toolkit" run_check_for_repo "$repo1" >/dev/null 2>&1
  rc=$?
  NAMES+=("staged空-通る")
  if [ "$rc" -eq 0 ]; then RESULTS+=("PASS"); else RESULTS+=("FAIL"); fi

  # ケース2: 3条件を満たす1件が done/ へ入る → 通る
  local repo2="$base_tmp/repo2"
  _setup_base_repo "$repo2"
  local c1
  c1="$(git -C "$repo2" rev-parse HEAD)"
  _write_doc "$repo2/docs/tasks/plan-a.md" "完了" "$c1"
  git -C "$repo2" add docs/tasks/plan-a.md
  git -C "$repo2" commit -q -m "add plan"
  _stage_done_move "$repo2" "plan-a.md"
  local toolkit2="$base_tmp/toolkit2"
  _setup_toolkit_mirror "$toolkit2"
  TASK_DONE_TOOLKIT_DIR="$toolkit2" run_check_for_repo "$repo2" >/dev/null 2>&1
  rc=$?
  NAMES+=("3条件充足-通る")
  if [ "$rc" -eq 0 ]; then RESULTS+=("PASS"); else RESULTS+=("FAIL"); fi

  # ケース3: 記録が無い1件が done/ へ入る → 止まる
  local repo3="$base_tmp/repo3"
  _setup_base_repo "$repo3"
  {
    echo "# タイトル"
    echo
    echo "内容だけで対応の記録の節が無い。"
  } > "$repo3/docs/tasks/plan-c.md"
  git -C "$repo3" add docs/tasks/plan-c.md
  git -C "$repo3" commit -q -m "add plan"
  _stage_done_move "$repo3" "plan-c.md"
  TASK_DONE_TOOLKIT_DIR="$no_toolkit" run_check_for_repo "$repo3" >/dev/null 2>&1
  rc=$?
  NAMES+=("記録なし-止まる")
  if [ "$rc" -ne 0 ]; then RESULTS+=("PASS"); else RESULTS+=("FAIL"); fi

  # ケース4: コミット欄が空の1件が done/ へ入る → 止まる
  local repo4="$base_tmp/repo4"
  _setup_base_repo "$repo4"
  _write_doc "$repo4/docs/tasks/plan-d.md" "完了" ""
  git -C "$repo4" add docs/tasks/plan-d.md
  git -C "$repo4" commit -q -m "add plan"
  _stage_done_move "$repo4" "plan-d.md"
  TASK_DONE_TOOLKIT_DIR="$no_toolkit" run_check_for_repo "$repo4" >/dev/null 2>&1
  rc=$?
  NAMES+=("コミット欄空-止まる")
  if [ "$rc" -ne 0 ]; then RESULTS+=("PASS"); else RESULTS+=("FAIL"); fi

  # ケース5: 公開が未反映のときに1件が done/ へ入る → 止まる
  local repo5="$base_tmp/repo5"
  _setup_base_repo "$repo5"
  local c5
  c5="$(git -C "$repo5" rev-parse HEAD)"
  _write_doc "$repo5/docs/tasks/plan-e.md" "完了" "$c5"
  git -C "$repo5" add docs/tasks/plan-e.md
  git -C "$repo5" commit -q -m "add plan"
  _stage_done_move "$repo5" "plan-e.md"
  TASK_DONE_TOOLKIT_DIR="$no_toolkit" run_check_for_repo "$repo5" >/dev/null 2>&1
  rc=$?
  NAMES+=("公開未反映-止まる")
  if [ "$rc" -ne 0 ]; then RESULTS+=("PASS"); else RESULTS+=("FAIL"); fi

  # ケース6: 緊急口が設定されている → 通り、理由が記録される
  local stderr_file="$base_tmp/skip-stderr.txt"
  TASK_DONE_MOVE_SKIP_REASON="テスト用の緊急口" bash "$SELF_PATH" >/dev/null 2>"$stderr_file"
  rc=$?
  NAMES+=("緊急口-通り理由を記録")
  if [ "$rc" -eq 0 ] && grep -q "テスト用の緊急口" "$stderr_file"; then
    RESULTS+=("PASS")
  else
    RESULTS+=("FAIL")
  fi

  rm -rf "$base_tmp" 2>/dev/null

  local total="${#NAMES[@]}"
  local pass=0
  local i=0
  echo "実行 ${total} 件"
  while [ "$i" -lt "$total" ]; do
    echo "[${RESULTS[$i]}] ${NAMES[$i]}"
    if [ "${RESULTS[$i]}" = "PASS" ]; then
      pass=$((pass + 1))
    fi
    i=$((i + 1))
  done
  local fail=$((total - pass))
  echo "合格 ${pass} 件 / 不合格 ${fail} 件"
  [ "$fail" -eq 0 ]
}

# ---------- エントリポイント ----------

if [ "${1:-}" = "--self-test" ]; then
  run_self_test
  exit $?
fi

if [ -n "${TASK_DONE_MOVE_SKIP_REASON:-}" ]; then
  echo "[TASK-DONE-MOVE-SKIP] ${TASK_DONE_MOVE_SKIP_REASON}" >&2
  exit 0
fi

if run_check_for_repo "$REPO_ROOT"; then
  exit 0
fi

echo "ERROR: docs/tasks/done/ への移動には judge-task-done.sh の3条件充足が必要。" >&2
echo "対応:" >&2
echo "  1. bash docs/scripts/judge-task-done.sh で該当指示書の理由を確認する" >&2
echo "  2. 条件を満たしてから改めて git add / git commit する" >&2
echo "  3. 緊急時のみ TASK_DONE_MOVE_SKIP_REASON=\"<理由>\" git commit ... で通す" >&2
exit 1
