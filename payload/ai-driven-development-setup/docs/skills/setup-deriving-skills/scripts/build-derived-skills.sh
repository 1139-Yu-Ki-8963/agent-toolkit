#!/usr/bin/env bash
set -euo pipefail

# build-derived-skills.sh — docs/skills/ の機能定義から .claude/skills/ を生成する
#
# 目的:
#   docs/skills/<機能名>/ 配下の tests/・samples/ を除く全ファイルを
#   <出力先リポジトリルート>/.claude/skills/<機能名>/ へ複製する。SKILL.md は
#   front matter の直後（閉じる "---" の次の行）に生成物である旨の1行コメントを
#   挿入する。他のファイルは内容を変えない。
#
#   名前が "-shared" で終わるフォルダ（SKILL.md を持たない、単位内で共有する
#   部品）も同じ規則（tests/・samples/ を除く全ファイルを複製）で派生する。
#   SKILL.md が無いため生成物マーカーは挿入しない。
#
# 使い方:
#   build-derived-skills.sh <docs/skills のルート> <出力先リポジトリルート> [--apply]
#   build-derived-skills.sh --self-test
#
# 実行の最初に validate-skill-definitions.sh（同ディレクトリ）を呼び、
# 不合格なら何も生成せず終了コード1で止まる。
#
# 既定はdry-run。生成予定のパスを標準出力へ列挙するのみで書き込みをしない。
# --apply を付けたときだけ出力先リポジトリルートへ実際に書き込む。
#
# 派生先（<出力先リポジトリルート>/.claude/skills/）に、定義に無い機能フォルダが
# あれば削除する（--apply時。dry-runでは削除予定として出す）。
#
# 終了コード:
#   0 = 生成（またはdry-runの列挙）が完了
#   1 = validate-skill-definitions.sh が不合格、または引数不正
#   2 = --self-test で一時領域の作成に失敗
#
# 保守責任者: 人手（ユーザー）。除外対象（tests/・samples/）を増減する場合は
#   本スクリプトの copy_skill_files と
#   docs/skills/setup-deriving-skills/SKILL.md を同時に更新する。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE_SCRIPT="${SCRIPT_DIR}/validate-skill-definitions.sh"

APPLY=0
PLAN_LINES=""

plan_add() {
  PLAN_LINES="${PLAN_LINES}${1}
"
}

# front matterの直後（閉じる"---"の次の行）に生成物マーカーを挿入して書き出す。
insert_marker_and_write() {
  local src="$1" dest="$2" name="$3"
  awk -v marker="<!-- 生成物: 定義は支援ツールの正本リポジトリの docs/skills/${name}/ にある（この配布物には含まれない）。直接編集しないこと -->" '
    BEGIN { c = 0; inserted = 0 }
    /^---$/ {
      c++
      print
      if (c == 2 && inserted == 0) {
        print marker
        inserted = 1
      }
      next
    }
    { print }
  ' "$src" > "$dest"
}

# 1機能のtests/・samples/を除く全ファイルを dest_dir へ複製する（計画・適用の両方）。
copy_skill_files() {
  local skill_dir="$1" dest_dir="$2" name="$3"
  local files f rel dest
  files="$(find "$skill_dir" -type f | sort)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel="${f#"${skill_dir}/"}"
    case "$rel" in
      tests/*|samples/*) continue ;;
    esac
    dest="${dest_dir}/${rel}"
    if [ "$rel" = "SKILL.md" ]; then
      plan_add "${dest}（front matterへ生成物マーカーを挿入）"
      if [ "$APPLY" -eq 1 ]; then
        mkdir -p "$(dirname "$dest")"
        insert_marker_and_write "$f" "$dest" "$name"
      fi
    else
      plan_add "$dest"
      if [ "$APPLY" -eq 1 ]; then
        mkdir -p "$(dirname "$dest")"
        cp "$f" "$dest"
      fi
    fi
  done <<FILELIST
$files
FILELIST
}

run_build() {
  local root="$1" out_root="$2"

  # 明示テンプレート付きmktemp（"${TMPDIR:-/tmp}/<name>.XXXXXX"）を使う。裸のmktempは
  # サンドボックス実行環境で失敗しうるため（設計判断: validate-skill-definitions.shと同じ）。
  local validate_out
  if ! validate_out="$(mktemp "${TMPDIR:-/tmp}/build-derived-skills-validate.XXXXXX" 2>/dev/null)" || [ -z "$validate_out" ]; then
    echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  if ! "$VALIDATE_SCRIPT" "$root" >"$validate_out" 2>&1; then
    cat "$validate_out" >&2
    rm -f "$validate_out"
    echo "ERROR: validate-skill-definitions.sh が不合格のため生成を中止しました" >&2
    return 1
  fi
  rm -f "$validate_out"

  PLAN_LINES=""

  local skill_dirs defined_names="" d name
  skill_dirs="$(find "$root" -mindepth 1 -maxdepth 1 -type d | sort)"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    name="$(basename "$d")"
    case "$name" in
      *-shared) ;;
      *) [ -f "${d}/SKILL.md" ] || continue ;;
    esac
    defined_names="${defined_names}${name}
"
    copy_skill_files "$d" "${out_root}/.claude/skills/${name}" "$name"
  done <<DIRLIST
$skill_dirs
DIRLIST

  # 派生先にあるが定義に無い機能フォルダを削除する
  if [ -d "${out_root}/.claude/skills" ]; then
    local existing e ename
    existing="$(find "${out_root}/.claude/skills" -mindepth 1 -maxdepth 1 -type d | sort)"
    while IFS= read -r e; do
      [ -n "$e" ] || continue
      ename="$(basename "$e")"
      if ! printf '%s\n' "$defined_names" | grep -qx "$ename"; then
        plan_add "削除予定: ${e}"
        if [ "$APPLY" -eq 1 ]; then
          rm -rf "$e"
        fi
      fi
    done <<EXISTLIST
$existing
EXISTLIST
  fi

  if [ "$APPLY" -eq 1 ]; then
    echo "生成完了（--apply）:"
  else
    echo "DRY-RUN: 以下を生成予定（--apply未指定のため書き込みなし）:"
  fi
  printf '%s' "$PLAN_LINES"
  return 0
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

bst_write_skill() {
  # $1: root  $2: name  $3: unit
  local root="$1" name="$2" unit="$3"
  local dir="${root}/${name}"
  mkdir -p "${dir}/tests" "${dir}/scripts" "${dir}/samples"
  cat > "${dir}/SKILL.md" <<SKILLEOF
---
name: ${name}
日本語名: テスト用機能
description: "self-test用の機能定義。"
invocation: ${name}
type: transform
allowed-tools: [Bash]
unit: ${unit}
category: ${unit}
kind: none
inputs: [docs/skills/${name}/dummy-input]
outputs: [docs/skills/${name}/dummy-output]
requires: []
---

## いつ使うか

self-test用。
SKILLEOF
  cat > "${dir}/tests/test-dummy.sh" <<'TESTEOF'
#!/usr/bin/env bash
exit 0
TESTEOF
  chmod +x "${dir}/tests/test-dummy.sh"
  cat > "${dir}/scripts/dummy.sh" <<'SCRIPTEOF2'
#!/usr/bin/env bash
echo dummy
SCRIPTEOF2
  echo "サンプルの中身" > "${dir}/samples/sample.txt"
}

# -shared フォルダ（SKILL.md を持たない共有部品）のフィクスチャを作る。
bst_write_shared() {
  # $1: root  $2: name（"-shared" で終わる名前を渡す）
  local root="$1" name="$2"
  local dir="${root}/${name}"
  mkdir -p "${dir}/tests" "${dir}/scripts"
  cat > "${dir}/scripts/shared-dummy.sh" <<'SCRIPTEOF3'
#!/usr/bin/env bash
echo shared-dummy
SCRIPTEOF3
  cat > "${dir}/tests/test-shared-dummy.sh" <<'TESTEOF2'
#!/usr/bin/env bash
exit 0
TESTEOF2
  chmod +x "${dir}/tests/test-shared-dummy.sh"
}

self_test() {
  local pass=0 fail=0

  local root out
  if ! root="$(mktemp -d "${TMPDIR:-/tmp}/build-derived-skills-self-test-root.XXXXXX" 2>/dev/null)" || [ -z "$root" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  if ! out="$(mktemp -d "${TMPDIR:-/tmp}/build-derived-skills-self-test-out.XXXXXX" 2>/dev/null)" || [ -z "$out" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi

  # category の値は unit と同名にしていないため（category はsetup/operateしか無い）、
  # bst_write_skillは常にsetup単位のみで使う（operate以外はcategory:setup想定と食い違うため）。
  bst_write_skill "$root" "setup-alpha" "setup"

  # ケース1（dry-run・書き込みなし）
  local out1 rc1=0
  out1="$("$0" "$root" "$out" 2>&1)" || rc1=$?
  if [ "$rc1" -eq 0 ] && printf '%s' "$out1" | grep -q '^DRY-RUN:' && [ ! -f "${out}/.claude/skills/setup-alpha/SKILL.md" ]; then
    pass=$((pass+1)); echo "  [PASS] ケース1: dry-runは書き込みをしない（exit 0）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース1: dry-runの挙動が不正 (exit ${rc1})" >&2
    printf '%s\n' "$out1" | sed 's/^/    /' >&2
  fi

  # ケース2（--apply・SKILL.mdへマーカー挿入・tests/samples除外）
  local out2 rc2=0
  out2="$("$0" "$root" "$out" --apply 2>&1)" || rc2=$?
  local dest="${out}/.claude/skills/setup-alpha"
  if [ "$rc2" -eq 0 ] \
    && [ -f "${dest}/SKILL.md" ] \
    && grep -q '^<!-- 生成物: 定義は支援ツールの正本リポジトリの docs/skills/setup-alpha/ にある' "${dest}/SKILL.md" \
    && [ -f "${dest}/scripts/dummy.sh" ] \
    && [ ! -d "${dest}/tests" ] \
    && [ ! -d "${dest}/samples" ]; then
    pass=$((pass+1)); echo "  [PASS] ケース2: --applyでSKILL.mdへマーカーを挿入し、tests/samplesを除外して複製する（exit 0）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース2: --applyの生成結果が不正 (exit ${rc2})" >&2
    printf '%s\n' "$out2" | sed 's/^/    /' >&2
  fi

  # ケース3（scripts/の内容が変わらないこと）
  local content
  content="$(cat "${dest}/scripts/dummy.sh")"
  if printf '%s' "$content" | grep -q '^echo dummy$'; then
    pass=$((pass+1)); echo "  [PASS] ケース3: scripts配下は内容を変えずに複製する"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース3: scripts配下の内容が変わっている" >&2
  fi

  # ケース4（定義に無い機能フォルダを削除する）
  mkdir -p "${out}/.claude/skills/setup-orphan"
  echo dummy > "${out}/.claude/skills/setup-orphan/SKILL.md"
  local out4 rc4=0
  out4="$("$0" "$root" "$out" --apply 2>&1)" || rc4=$?
  if [ "$rc4" -eq 0 ] && [ ! -d "${out}/.claude/skills/setup-orphan" ]; then
    pass=$((pass+1)); echo "  [PASS] ケース4: 定義に無い派生フォルダを削除する（exit 0）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース4: 定義に無い派生フォルダの削除に失敗 (exit ${rc4})" >&2
    printf '%s\n' "$out4" | sed 's/^/    /' >&2
  fi

  # ケース5（検査不合格なら何も書かず終了コード1）
  local root_bad
  if ! root_bad="$(mktemp -d "${TMPDIR:-/tmp}/build-derived-skills-self-test-bad.XXXXXX" 2>/dev/null)" || [ -z "$root_bad" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  bst_write_skill "$root_bad" "setup-broken" "setup"
  sed -i.bak '/^kind: /d' "${root_bad}/setup-broken/SKILL.md" && rm -f "${root_bad}/setup-broken/SKILL.md.bak"
  local out_bad
  if ! out_bad="$(mktemp -d "${TMPDIR:-/tmp}/build-derived-skills-self-test-badout.XXXXXX" 2>/dev/null)" || [ -z "$out_bad" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  local out5 rc5=0
  out5="$("$0" "$root_bad" "$out_bad" --apply 2>&1)" || rc5=$?
  if [ "$rc5" -eq 1 ] && [ ! -d "${out_bad}/.claude" ]; then
    pass=$((pass+1)); echo "  [PASS] ケース5: 検査不合格なら何も書かず終了コード1"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース5: 検査不合格時の扱いが不正 (exit ${rc5})" >&2
    printf '%s\n' "$out5" | sed 's/^/    /' >&2
  fi
  rm -rf "$root_bad" "$out_bad"

  # ケース6（-shared フォルダが派生され、tests/ を除外して複製する）
  bst_write_shared "$root" "setup-example-shared"
  local out6 rc6=0
  out6="$("$0" "$root" "$out" --apply 2>&1)" || rc6=$?
  local shared_dest="${out}/.claude/skills/setup-example-shared"
  if [ "$rc6" -eq 0 ] &&
     [ -f "${shared_dest}/scripts/shared-dummy.sh" ] &&
     [ ! -d "${shared_dest}/tests" ]; then
    pass=$((pass+1)); echo "  [PASS] ケース6: -shared フォルダを派生し tests/ を除外する（exit 0）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース6: -shared フォルダの派生が不正 (exit ${rc6})" >&2
    printf '%s\n' "$out6" | sed 's/^/    /' >&2
  fi

  rm -rf "$root" "$out"

  if [ "$fail" -eq 0 ]; then
    echo "self-test 全項目 PASS（PASS=${pass} FAIL=${fail}）"
    return 0
  fi
  echo "self-test FAIL（PASS=${pass} FAIL=${fail}）" >&2
  return 1
}

# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi

  local root="" out_root="" apply_flag=0
  local args=()
  for a in "$@"; do
    if [ "$a" = "--apply" ]; then
      apply_flag=1
    else
      args+=("$a")
    fi
  done

  if [ "${#args[@]}" -ne 2 ]; then
    echo "usage: $(basename "$0") <docs/skills のルート> <出力先リポジトリルート> [--apply]" >&2
    echo "       $(basename "$0") --self-test" >&2
    exit 1
  fi

  root="${args[0]}"
  out_root="${args[1]}"
  APPLY="$apply_flag"

  if [ ! -d "$root" ]; then
    echo "ERROR: docs/skills のルートが存在しない: $root" >&2
    exit 1
  fi
  if [ ! -d "$out_root" ]; then
    echo "ERROR: 出力先リポジトリルートが存在しない: $out_root" >&2
    exit 1
  fi

  run_build "$root" "$out_root"
  exit $?
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main "$@"
fi
