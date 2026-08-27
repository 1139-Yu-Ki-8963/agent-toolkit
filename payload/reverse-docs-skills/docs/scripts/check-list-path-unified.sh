#!/usr/bin/env bash
# check-list-path-unified.sh — 一覧の置き場が project-portal/一覧（日本語）へ
# 逆戻りしていないかを見る
#
# 判定の式を指示書の表へ直接書けないためスクリプトへ切り出した。式に含まれる
# 縦棒を片付けの判定器が列の区切りと読み違え、判定行そのものを壊すためである
# （.claude/rules/always/tasks/instruction-format/rule.md の設計判断を参照）。
#
# 背景: 一覧の置き場は project-portal/lists（英字）を正とする。日本語の
# ディレクトリは3つの不具合を起こすと実測で確かめたため
# （docs/tasks/work-records/2026-08-24-日本語のフォルダ名の実測.md）、
# project-portal/一覧 への統一（一覧の置き場が三者三様になっている問題を直す
# 指示書.md）を差し戻した。定義（output-layout.json）・カタログ
# （portal-catalog.json）・生成器の既定・見本（generation-engine/samples/）が
# すべてこの形へ揃った。旧来の日本語ルート project-portal/一覧 への逆戻りを、
# generation-engine/・delivery-payload/・docs/・.claude/ の4ディレクトリ配下で
# 検出する。
#
# 除外対象（走査から外す。理由は各項目を参照）:
#   1. このスクリプト自身（自己言及）
#   2. docs/tasks/ 配下すべて — 指示書・台帳・作業記録・片付け済み指示書
#      （docs/tasks/done/）を含む。指示書の本文は経緯の説明であり書き換えの
#      対象外（.claude/rules/always/tasks/instruction-format/rule.md・
#      .claude/rules/always/tasks/commit-issue-trace/rule.md「台帳を対象外に
#      する理由」と同じ考え方）。旧配置(project-portal/一覧)への言及は
#      「直す前の状態の記録」であり、対象範囲を個別ファイルで列挙すると
#      docs/tasks/ 配下が増えるたびに追従漏れが起こる（実測: done/ 配下の
#      片付け済み指示書4件・work-records配下2件が個別列挙から漏れていた）。
#      ディレクトリ単位の除外に改めた
#   3. generation-engine/scripts/portal-catalog.mjs の自己テスト2件
#      （resolveDefaultRootPrefix の後方互換動作を検証する合成フィクスチャ。
#      対象プロジェクト側が unitsRoot を project-portal/一覧 のような旧来の
#      日本語ルートへ独自に上書きした場合の変換を確かめるための、意図的に
#      作った legacy な入力値であり、当プロジェクトの定義とは無関係）
#   4. docs/rules/portal/page-conventions/rule.md — 本検査自身の設計判断を
#      記載する正本。本節や「設計判断」節の説明文が project-portal/一覧 と
#      いう文字列そのものへ言及するため（本検査を導入する理由の説明に
#      旧値を書かざるを得ない）、自己言及として対象外にする
#   5. .claude/rules/scoped/portal/page-conventions/rule.md — 上記4の生成物
#      （build-derived-rules.sh --apply の出力）。4と同じ理由・同じ文言が
#      複製されるため、同様に自己言及として対象外にする
#
# 除外3・4・5はファイル単位（そのファイル全体を走査対象から外す）で行う。
# 行単位の除外にすると、判定式が指示書の表の縦棒問題と同様に複雑化するため、
# ファイル単位の方が保守しやすいと判断した。この3ファイルへ新たに
# project-portal/一覧 への言及（自己テスト以外の用途）が入り込んだ場合、
# 本スクリプトでは検知できない既知の限界がある。
#
# 使い方:
#   check-list-path-unified.sh             project-portal/一覧 への言及が0件かを見る
#   check-list-path-unified.sh --self-test このスクリプト自身の判定を確かめる
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TARGET_DIRS=(
  "generation-engine"
  "delivery-payload"
  "docs"
  ".claude"
)

# scan_dirs: <root> 配下の TARGET_DIRS を走査し、project-portal/一覧 を含む行を
# 「ファイル:行番号:内容」の形で標準出力へ書く。除外対象は含めない。
scan_dirs() {
  local root="$1"
  local self_rel="docs/scripts/check-list-path-unified.sh"
  local d
  for d in "${TARGET_DIRS[@]}"; do
    [ -d "$root/$d" ] || continue
    grep -rn 'project-portal/一覧' "$root/$d" 2>/dev/null | while IFS= read -r line; do
      local file="${line%%:*}"
      local rel="${file#"$root"/}"
      case "$rel" in
        "$self_rel") continue ;;
        docs/tasks/*) continue ;;
        generation-engine/scripts/portal-catalog.mjs) continue ;;
        docs/rules/portal/page-conventions/rule.md) continue ;;
        .claude/rules/scoped/portal/page-conventions/rule.md) continue ;;
      esac
      printf '%s\n' "$line"
    done
  done
  return 0
}

run_self_test() {
  local pass=0 fail=0
  local tmp
  # 明示テンプレート付き mktemp。引数なしの mktemp は $TMPDIR を無視し書き込みを
  # 拒む環境で失敗する（.claude/rules/always/verification/indeterminate-result/rule.md）。
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-list-path-unified.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため自己テストを判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' RETURN

  # ケース1: 4つの置き場すべてが揃い、違反が0件 → exit 0
  mkdir -p "$tmp/case_clean/generation-engine/scripts" "$tmp/case_clean/delivery-payload/references" "$tmp/case_clean/docs/tasks" "$tmp/case_clean/.claude/skills"
  printf '%s\n' 'const path = "project-portal/lists/apis/API一覧.html";' \
    > "$tmp/case_clean/generation-engine/scripts/good.mjs"
  if out="$(_run_scan_over "$tmp/case_clean")" && [ -z "$out" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "[FAIL] ケース1(違反なし): ${out}" >&2
  fi

  # ケース2: project-portal/一覧 への言及が1件 → 検出される
  mkdir -p "$tmp/case_bad/generation-engine/scripts"
  printf '%s\n' 'const path = "project-portal/一覧/API一覧/API一覧.html";' \
    > "$tmp/case_bad/generation-engine/scripts/bad.mjs"
  if out="$(_run_scan_over "$tmp/case_bad")" && printf '%s' "$out" | grep -q 'bad.mjs:1:'; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "[FAIL] ケース2(project-portal/一覧の検出): ${out}" >&2
  fi

  # ケース3: 除外対象（docs/tasks/ 配下は指示書・台帳・作業記録・done/ を
  # 問わず全件対象外）は検出しない
  mkdir -p "$tmp/case_exempt/docs/tasks/work-records" "$tmp/case_exempt/docs/tasks/done" "$tmp/case_exempt/docs/tasks/design"
  printf '%s\n' '旧配置は project-portal/一覧 だった。' \
    > "$tmp/case_exempt/docs/tasks/work-records/記録.md"
  printf '%s\n' '旧配置は project-portal/一覧 だった。' \
    > "$tmp/case_exempt/docs/tasks/指摘改善一覧.md"
  printf '%s\n' '配置の定義（output-layout.json） project-portal/一覧/screens/画面一覧.html' \
    > "$tmp/case_exempt/docs/tasks/一覧の置き場が三者三様になっている問題を直す指示書.md"
  printf '%s\n' '片付け済み。旧配置は project-portal/一覧 だった。' \
    > "$tmp/case_exempt/docs/tasks/done/片付け済み指示書.md"
  printf '%s\n' '設計中。旧配置は project-portal/一覧 だった。' \
    > "$tmp/case_exempt/docs/tasks/design/設計中の指示書.md"
  if out="$(_run_scan_over "$tmp/case_exempt")" && [ -z "$out" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "[FAIL] ケース3(docs/tasks/配下全件の非検出): ${out}" >&2
  fi

  # ケース4: 除外対象（portal-catalog.mjs・docs/rules/portal/page-conventions/
  # rule.md・その派生の.claude/rules/scoped版）は検出しない
  mkdir -p "$tmp/case_exempt2/generation-engine/scripts" \
    "$tmp/case_exempt2/docs/rules/portal/page-conventions" "$tmp/case_exempt2/.claude/rules/scoped/portal/page-conventions"
  printf '%s\n' 'unitsRoot: "project-portal/一覧",' \
    > "$tmp/case_exempt2/generation-engine/scripts/portal-catalog.mjs"
  printf '%s\n' '旧来の日本語ルート project-portal/一覧 への逆戻りを検出する。' \
    > "$tmp/case_exempt2/docs/rules/portal/page-conventions/rule.md"
  printf '%s\n' '旧来の日本語ルート project-portal/一覧 への逆戻りを検出する。' \
    > "$tmp/case_exempt2/.claude/rules/scoped/portal/page-conventions/rule.md"
  if out="$(_run_scan_over "$tmp/case_exempt2")" && [ -z "$out" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "[FAIL] ケース4(portal-catalog.mjs等の非検出): ${out}" >&2
  fi

  # ケース5: .claude/ 配下（page-conventions/rule.md 以外）の言及は検出される
  mkdir -p "$tmp/case_claude/.claude/skills/dummy-skill"
  printf '%s\n' "既定 project-portal/一覧/画面一覧/画面一覧.html" \
    > "$tmp/case_claude/.claude/skills/dummy-skill/SKILL.md"
  if out="$(_run_scan_over "$tmp/case_claude")" && printf '%s' "$out" | grep -q 'SKILL.md:1:'; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "[FAIL] ケース5(.claude/配下の検出): ${out}" >&2
  fi

  # ケース6: 走査対象の置き場が1つも無い → [UNKNOWN]・終了コード2
  mkdir -p "$tmp/case_empty"
  if out="$(cd "$tmp/case_empty" && bash "$SCRIPT_DIR/check-list-path-unified.sh" --repo-root "$tmp/case_empty" 2>&1)"; then
    fail=$((fail + 1))
    echo "[FAIL] ケース6(置き場なしでUNKNOWNを返す): exit 0 だった" >&2
  else
    rc=$?
    if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q '^\[UNKNOWN\]'; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
      echo "[FAIL] ケース6(置き場なしでUNKNOWNを返す): rc=${rc} out=${out}" >&2
    fi
  fi

  # ケース7: --self-test 自身が実引数として処理される
  if grep -q -- '--self-test' "$SCRIPT_DIR/check-list-path-unified.sh"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "[FAIL] ケース7(--self-testの実装確認)" >&2
  fi

  # 追加回帰: 実ディレクトリの名前が旧い日本語の置き場になっていれば検知する。
  # 中身の言及が0件でも検知することを確かめる（2026-08-28実測。
  # 画面0件の見本が中身の言及0件のまま日本語の置き場を持っていた）。
  mkdir -p "$tmp/case_legacy_dir/generation-engine/x/project-portal/一覧"
  if out="$(scan_legacy_dirs "$tmp/case_legacy_dir")" && [ -n "$out" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "[FAIL] 追加回帰(日本語の置き場): 検知できなかった" >&2
  fi

  mkdir -p "$tmp/case_ascii_dir/generation-engine/x/project-portal/lists"
  if out="$(scan_legacy_dirs "$tmp/case_ascii_dir")" && [ -z "$out" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "[FAIL] 追加回帰(英字の置き場): 誤って検知した: ${out}" >&2
  fi

  echo "self-test: ${pass} PASS, ${fail} FAIL" >&2
  [ "$fail" -eq 0 ]
}

# _run_scan_over: 自己テスト用に、指定した疑似リポジトリ配下を走査した結果
# （違反行の一覧）を返す。
# scan_legacy_dirs: 実ディレクトリの名前そのものが旧い日本語の置き場に
# なっていないかを見る。中身の言及を走査するだけでは、実ディレクトリが
# 日本語のままでも中身に言及が無ければ検知できない
# （2026-08-28実測。画面0件の見本の置き場が日本語のまま残っていた）。
scan_legacy_dirs() {
  local root="$1" d
  for d in "${TARGET_DIRS[@]}"; do
    [ -d "$root/$d" ] || continue
    find "$root/$d" -type d -name '一覧' 2>/dev/null \
      | grep -v '/node_modules/' | grep -v '/\.venv/' || true
  done
}

_run_scan_over() {
  local root="$1"
  scan_dirs "$root"
}

main() {
  local repo_root="$REPO_ROOT"
  local i=1
  local args=("$@")
  while [ $i -le $# ]; do
    case "${args[$((i-1))]}" in
      --repo-root)
        i=$((i + 1))
        repo_root="${args[$((i-1))]}"
        ;;
    esac
    i=$((i + 1))
  done

  local missing=0
  local d
  for d in "${TARGET_DIRS[@]}"; do
    [ -d "$repo_root/$d" ] || missing=$((missing + 1))
  done
  if [ "$missing" -eq "${#TARGET_DIRS[@]}" ]; then
    echo "[UNKNOWN] 走査対象の置き場が1つも見つからないため判定できません（参照したルート: ${repo_root}）" >&2
    exit 2
  fi

  local out dirs
  out="$(scan_dirs "$repo_root")"
  dirs="$(scan_legacy_dirs "$repo_root")"

  if [ -z "$out" ] && [ -z "$dirs" ]; then
    echo "[PASS] project-portal/一覧 への言及は0件"
    echo "[PASS] 旧い日本語の置き場は0件"
    exit 0
  fi

  local rc=0
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
    local violations
    violations="$(printf '%s\n' "$out" | grep -c .)"
    echo "[FAIL] project-portal/一覧 への言及が ${violations} 件ある"
    rc=1
  else
    echo "[PASS] project-portal/一覧 への言及は0件"
  fi

  if [ -n "$dirs" ]; then
    printf '%s\n' "$dirs"
    local dir_count
    dir_count="$(printf '%s\n' "$dirs" | grep -c .)"
    echo "[FAIL] 旧い日本語の置き場が ${dir_count} 件ある"
    rc=1
  else
    echo "[PASS] 旧い日本語の置き場は0件"
  fi

  exit "$rc"
}

if [ "${1:-}" = "--self-test" ]; then
  run_self_test
  exit $?
fi

main "$@"
