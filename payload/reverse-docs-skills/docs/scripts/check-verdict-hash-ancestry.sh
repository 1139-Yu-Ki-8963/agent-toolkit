#!/usr/bin/env bash
# check-verdict-hash-ancestry.sh — 判定表・記録のコミット欄が main の祖先かを見る
#
# 背景: 判定表のコミット欄が指す先を失う事象が5回起きた
# （docs/tasks/作業課題一覧.md「判定表のコミット欄が枝の取り込みで参照先を失う」）。
# 原因は取り込みの方式にある。作業枝を git cherry-pick で main へ取り込むと、
# コミットが作り直されてハッシュが変わる。担当が判定表へ書いたハッシュは、
# 取り込み後には存在しない。git merge --no-ff で取り込めばハッシュは保たれる
# （2026-08-26 実測: 9件すべてが merge-base --is-ancestor で祖先と判定された）。
#
# 本検査は、判定表の「コミット」欄と `**状態**: 完了（コミット: ...）` の
# 括弧内から7桁以上の16進を取り出し、各ハッシュが (1) main のコミットとして
# 存在し、(2) main の祖先であることを機械で確かめる。1件でも満たさなければ
# 不合格とし、どのファイルのどの行かを列挙する。
#
# 走査対象: docs/tasks/*.md・docs/tasks/done/*.md（台帳2件を含む。台帳を除外
# しない理由: commit-issue-trace/rule.md「台帳を対象外にする理由」は指示書
# 固有の要求（元の指摘行等）を台帳へ適用しない話であり、本検査が見るのは
# 「そこに書かれたハッシュが実在し main の祖先か」という、指示書か台帳かを
# 問わない事実である）。
#
# 実装判断: 判定の式を指示書の表へ直接書けない。式に含まれる縦棒を
#   片付けの判定器が列の区切りと読み違え、判定行そのものを壊す
#   （.claude/rules/always/tasks/instruction-format/rule.md の
#   check-broken-verdict-rows.sh の設計判断と同じ理由）。式をこのファイルへ
#   移し、表からはファイル名だけを呼ぶ形にする。
#
# 実装判断: 一時領域は ${TMPDIR:-/tmp} を明示して取る。裸の mktemp は既定の
#   置き場へ書けない環境で失敗する（実測: check-broken-verdict-rows.sh 等）。
#   失敗した場合は [UNKNOWN]・終了コード2で終える
#   （.claude/rules/always/verification/indeterminate-result/rule.md に従う）。
#
# 使い方:
#   bash docs/scripts/check-verdict-hash-ancestry.sh                docs/tasks 全体を走査
#   bash docs/scripts/check-verdict-hash-ancestry.sh <file...>       指定ファイルだけ走査
#   bash docs/scripts/check-verdict-hash-ancestry.sh --repo-root <path> [<file...>]
#                                                                     走査の起点を差し替える（自己テスト用）
#   bash docs/scripts/check-verdict-hash-ancestry.sh --self-test     このスクリプト自身の検査
#
# 終了コード:
#   0 = 抽出した全ハッシュが main のコミットであり祖先である
#   1 = main の祖先でない、またはコミットとして存在しないハッシュが1件以上ある
#   2 = 走査対象が無い・git が無い・main ブランチが無いなど判定不能
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# extract_hashes: 1ファイルから (行番号, ハッシュ, 由来) の組を1行1組で出す。
# 由来は "table"（判定表のコミット欄）または "state"（状態:完了の括弧内）。
#
# 判定表: 状態語（未着手|対応中|完了|対象外|未確認）のセルの直後のセルを
# コミット欄とみなす。「状態セル -> コミット欄セル」という隣接関係だけを
# 見るため、その手前に何列あっても、コマンド欄が逆引用符とパイプを含んでも
# 影響を受けない。
#
# 状態:完了の括弧: `**状態**: 完了（コミット: <hash>` の直後の16進だけを取る。
extract_hashes() {
  local file="$1"
  LC_ALL=C awk '
    {
      line = $0
      # 判定表のコミット欄
      if (match(line, /\|[ \t]*(未着手|対応中|完了|対象外|未確認)[ \t]*\|[ \t]*[0-9a-fA-F]{7,40}[ \t]*\|/)) {
        seg = substr(line, RSTART, RLENGTH)
        if (match(seg, /[0-9a-fA-F]{7,40}[ \t]*\|[ \t]*$/)) {
          hash = substr(seg, RSTART, RLENGTH)
          sub(/[ \t]*\|[ \t]*$/, "", hash)
          printf "%d\ttable\t%s\n", FNR, hash
        }
      }
      # 状態:完了（コミット: <hash>
      if (match(line, /\*\*状態\*\*: *完了（コミット: *[0-9a-fA-F]{7,40}/)) {
        seg = substr(line, RSTART, RLENGTH)
        if (match(seg, /[0-9a-fA-F]{7,40}$/)) {
          hash = substr(seg, RSTART, RLENGTH)
          printf "%d\tstate\t%s\n", FNR, hash
        }
      }
    }
  ' "$file"
}

# list_target_files: <repo_root> 配下の docs/tasks/*.md・docs/tasks/done/*.md を返す。
list_target_files() {
  local repo_root="$1"
  local -a files=()
  shopt -s nullglob
  files+=("$repo_root"/docs/tasks/*.md)
  files+=("$repo_root"/docs/tasks/done/*.md)
  shopt -u nullglob
  ((${#files[@]})) && printf '%s\n' "${files[@]}"
  return 0
}

# check_hash: <repo_root> <hash> を判定する。標準出力へ理由を書き、
# 0=祖先である / 1=祖先でない・存在しない を返す。
check_hash() {
  local repo_root="$1" hash="$2"
  local type
  type="$(git -C "$repo_root" cat-file -t "$hash" 2>/dev/null || true)"
  if [ "$type" != "commit" ]; then
    echo "コミットとして存在しない"
    return 1
  fi
  if git -C "$repo_root" merge-base --is-ancestor "$hash" main 2>/dev/null; then
    return 0
  fi
  echo "mainの祖先でない"
  return 1
}

run_check() {
  local repo_root="$1"
  shift
  local -a targets=("$@")

  if ! command -v git >/dev/null 2>&1; then
    echo "[UNKNOWN] gitが無いため判定できません" >&2
    return 2
  fi
  if ! git -C "$repo_root" rev-parse --verify -q main >/dev/null 2>&1; then
    echo "[UNKNOWN] mainブランチを解決できないため判定できません（参照したルート: ${repo_root}）" >&2
    return 2
  fi

  if [ "${#targets[@]}" -eq 0 ]; then
    local f
    while IFS= read -r f; do
      [ -n "$f" ] && targets+=("$f")
    done < <(list_target_files "$repo_root")
  fi

  if [ "${#targets[@]}" -eq 0 ]; then
    echo "[UNKNOWN] 走査対象（docs/tasks/*.md・docs/tasks/done/*.md）が1つも見つかりません（参照したルート: ${repo_root}）" >&2
    return 2
  fi

  local -a failures=()
  local total=0
  local file line kind hash reason

  for file in "${targets[@]}"; do
    [ -f "$file" ] || continue
    while IFS=$'\t' read -r line kind hash; do
      [ -n "$hash" ] || continue
      total=$((total + 1))
      if ! reason="$(check_hash "$repo_root" "$hash")"; then
        failures+=("$(printf '%s:%d: %s（由来: %s、理由: %s）' "$file" "$line" "$hash" "$kind" "$reason")")
      fi
    done < <(extract_hashes "$file")
  done

  if [ "${#failures[@]}" -gt 0 ]; then
    printf '%s\n' "${failures[@]}" >&2
    printf '[FAIL] mainの祖先でない・存在しないハッシュ=%d件（走査したハッシュ%d件中）\n' \
      "${#failures[@]}" "$total" >&2
    return 1
  fi

  echo "[PASS] mainの祖先でない・存在しないハッシュ=0件（走査したハッシュ${total}件）"
  return 0
}

# --- 自己テスト ---------------------------------------------------------

run_self_test() {
  local tmp rc=0 pass=0 fail=0
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/$(basename "${BASH_SOURCE[0]}" .sh).XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため自己テストを判定できません（mktemp -d が一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）" >&2
    return 2
  fi
  # RETURN トラップは関数単位ではなくシェル全体に効くため、ここで設定すると
  # main() が return する際にも発火し、tmp が未定義のまま参照されて
  # `set -u` の下でエラーになる。単一の出口（関数末尾）で明示的に rm -rf する。

  local repo="$tmp/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.name "self-test"
  git -C "$repo" config user.email "self-test@example.invalid"
  git -C "$repo" checkout -q -b main 2>/dev/null || git -C "$repo" checkout -q main 2>/dev/null

  echo "a" > "$repo/a.txt"
  git -C "$repo" add a.txt
  git -C "$repo" commit -q -m "初期コミット"
  local ancestor_hash
  ancestor_hash="$(git -C "$repo" rev-parse HEAD)"

  git -C "$repo" checkout -q -b side
  echo "b" > "$repo/b.txt"
  git -C "$repo" add b.txt
  git -C "$repo" commit -q -m "取り込まれない枝のコミット"
  local non_ancestor_hash
  non_ancestor_hash="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" checkout -q main

  local nonexistent_hash="0123456789ab"

  mkdir -p "$repo/docs/tasks/done"
  cat > "$repo/docs/tasks/ok.md" <<EOF
| 1. 例 | \`test -z ""\` | 完了 | ${ancestor_hash} | 説明 |
EOF
  cat > "$repo/docs/tasks/not-ancestor.md" <<EOF
**状態**: 完了（コミット: ${non_ancestor_hash}）。取り込み前の枝のハッシュを書いたままにした。
EOF
  cat > "$repo/docs/tasks/done/not-exist.md" <<EOF
| 1. 例 | \`test -z ""\` | 対象外 | ${nonexistent_hash} | 存在しないハッシュ |
EOF

  # ケース1: mainのコミットで祖先であるハッシュだけを走査 → 合格
  if run_check "$repo" "$repo/docs/tasks/ok.md" >/dev/null 2>&1; then
    echo "  [PASS] main の祖先であるハッシュは合格する"; pass=$((pass + 1))
  else
    echo "  [FAIL] main の祖先であるハッシュは合格する" >&2; fail=$((fail + 1)); rc=1
  fi

  # ケース2: 存在するがmainの祖先でないハッシュ → 不合格・理由に「祖先でない」
  if run_check "$repo" "$repo/docs/tasks/not-ancestor.md" >"$tmp/out2.txt" 2>"$tmp/err2.txt"; then
    echo "  [FAIL] main の祖先でないハッシュは不合格になる" >&2; fail=$((fail + 1)); rc=1
  else
    if grep -q "mainの祖先でない" "$tmp/err2.txt"; then
      echo "  [PASS] main の祖先でないハッシュは不合格になる（理由付き）"; pass=$((pass + 1))
    else
      echo "  [FAIL] main の祖先でないハッシュは不合格になる（理由付き）" >&2; fail=$((fail + 1)); rc=1
    fi
  fi

  # ケース3: 存在しないハッシュ → 不合格・理由に「存在しない」
  if run_check "$repo" "$repo/docs/tasks/done/not-exist.md" >"$tmp/out3.txt" 2>"$tmp/err3.txt"; then
    echo "  [FAIL] 存在しないハッシュは不合格になる" >&2; fail=$((fail + 1)); rc=1
  else
    if grep -q "コミットとして存在しない" "$tmp/err3.txt"; then
      echo "  [PASS] 存在しないハッシュは不合格になる（理由付き）"; pass=$((pass + 1))
    else
      echo "  [FAIL] 存在しないハッシュは不合格になる（理由付き）" >&2; fail=$((fail + 1)); rc=1
    fi
  fi

  # ケース4: 既定の走査（引数なし）で3ファイルすべてを対象にし、失敗2件を報告する
  if run_check "$repo" >"$tmp/out4.txt" 2>"$tmp/err4.txt"; then
    echo "  [FAIL] 既定の走査は3ファイル中2件の失敗を報告する" >&2; fail=$((fail + 1)); rc=1
  else
    if grep -q "不合格.*2件\|=2件" "$tmp/err4.txt"; then
      echo "  [PASS] 既定の走査は3ファイル中2件の失敗を報告する"; pass=$((pass + 1))
    else
      echo "  [FAIL] 既定の走査は3ファイル中2件の失敗を報告する（出力: $(cat "$tmp/err4.txt")）" >&2
      fail=$((fail + 1)); rc=1
    fi
  fi

  # ケース5: mainブランチが無いリポジトリは判定不能（終了コード2）
  local repo2="$tmp/repo-no-main"
  mkdir -p "$repo2/docs/tasks"
  git -C "$repo2" init -q
  git -C "$repo2" config user.name "self-test"
  git -C "$repo2" config user.email "self-test@example.invalid"
  git -C "$repo2" checkout -q -b other 2>/dev/null
  echo "x" > "$repo2/x.txt"
  git -C "$repo2" add x.txt
  git -C "$repo2" commit -q -m "mainではない枝"
  echo "| 1. 例 | \`true\` | 完了 | $(git -C "$repo2" rev-parse HEAD) | 説明 |" > "$repo2/docs/tasks/x.md"
  set +e
  run_check "$repo2" >/dev/null 2>/dev/null
  local rc2=$?
  set -e 2>/dev/null || true
  if [ "$rc2" -eq 2 ]; then
    echo "  [PASS] mainブランチが無い場合は判定不能(終了コード2)を返す"; pass=$((pass + 1))
  else
    echo "  [FAIL] mainブランチが無い場合は判定不能(終了コード2)を返す（実際: ${rc2}）" >&2
    fail=$((fail + 1)); rc=1
  fi

  echo "self-test: PASS=${pass} FAIL=${fail}"
  rm -rf "$tmp"
  return "$rc"
}

# --- エントリポイント ---------------------------------------------------

main() {
  local repo_root="$DEFAULT_REPO_ROOT"
  local -a targets=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --self-test)
        run_self_test
        return $?
        ;;
      --repo-root)
        [ "$#" -ge 2 ] || { echo "usage: $0 --repo-root <path> [<file...>]" >&2; return 2; }
        repo_root="$2"
        shift 2
        ;;
      *)
        targets+=("$1")
        shift
        ;;
    esac
  done

  run_check "$repo_root" "${targets[@]}"
}

main "$@"
