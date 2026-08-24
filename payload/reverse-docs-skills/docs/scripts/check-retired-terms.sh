#!/usr/bin/env bash
# check-retired-terms.sh — 指示書の本文に廃止済みの語が残っていないかを見る
#
# 廃止した資料・節の名前は docs/references/retired-terms.json（正本）1本へ集める。
# 新しく指示書を書く担当は、この一覧を経由しない限り、ある語が既に廃止済みかを
# 知る手段を持たない。実測（2026-08-24）: 「要確認事項の記録先を根拠を記録する
# 資料へ向け直せ」という指示書を起票したところ、改善課題1-246（コミット
# bd5d2892426ef5341e259d20f13d887feebb0b1c）が既にその資料を廃止していた。
# 気づけたのは偶然であり、仕組みが止めたわけではなかった。
#
# generation-engine/scripts/tests/check-design-doc-section-consistency.sh と
# generation-engine/scripts/tests/test-api-design-decisions.sh も同じ一覧を
# 読む（4語を個別にハードコードしない）。3ファイルが同じ一覧を共有することで、
# 廃止語が増えても書き直す箇所を1つに保つ。
#
# 走査対象は docs/tasks/ の直下と docs/tasks/design/ の直下（.md、maxdepth 1）
# だけである。docs/tasks/done/ と docs/tasks/work-records/ は対象外とする
# （.claude/rules/always/tasks/instruction-format/rule.md「置き場は4つだけ」を
# 参照。片付いた指示書・履歴の記録は、今後の起票が古い前提を持ち込むことを
# 防ぐという本検査の目的の対象ではない）。このスクリプト自身（docs/scripts/）
# と一覧ファイル自身（docs/references/）は docs/tasks/ の外にあり、走査範囲の
# 構造そのものによって自己不合格にならない。
#
# 台帳（指摘改善一覧.md・作業課題一覧.md）は docs/tasks/ の直下に置かれるが
# 指示書ではない。.claude/rules/always/tasks/commit-issue-trace/rule.md
# 「台帳を対象外にする理由」が既に定める区別（台帳に偶発的に同名の記述が
# 残っていても、指示書向けの要求を適用してはならない）をそのまま再用し、
# 名前で除外する。台帳は起票の起点ではなく、起きた出来事の記録だからである。
LEDGER_BASENAMES=("指摘改善一覧.md" "作業課題一覧.md")

is_ledger_file() {
  local basename="$1" name
  for name in "${LEDGER_BASENAMES[@]}"; do
    [ "$basename" = "$name" ] && return 0
  done
  return 1
}

# strip_fences: コード柵（``` または ~~~ で始まる行）に挟まれた範囲を空行へ
# 置き換える。.claude/rules/always/tasks/instruction-format/rule.md 付属の
# check-instruction-format.sh の strip_fences と同じロジック（行番号を保つ
# ため行は消さず空文字へ置換）。柵の中は語の引用（例示）であり、今後の起票が
# 生きた参照として使う記述ではないため、対象から外す。
strip_fences() {
  local file="$1"
  LC_ALL=C awk '
    BEGIN { infence = 0 }
    /^[ ]{0,3}(```|~~~)/ {
      if (infence == 0) { infence = 1 } else { infence = 0 }
      print ""
      next
    }
    {
      if (infence == 1) { print "" } else { print }
    }
  ' "$file"
}
#
# 使い方:
#   check-retired-terms.sh                    docs/tasks/直下 と docs/tasks/design/ を走査する
#   check-retired-terms.sh --repo-root <path> 走査の起点を差し替える（自己テスト用）
#   check-retired-terms.sh --self-test        スクリプト自身の検査
#
# 環境変数:
#   RETIRED_TERMS_FILE  一覧JSONの差し替え先（自己テスト用）
#
# 終了コード:
#   0 = 廃止済みの語の残存が0件
#   1 = 廃止済みの語が1件以上残っている
#   2 = 一覧ファイルが無い・形式が不正・走査対象が1つも無いなど判定不能
#       （.claude/rules/always/verification/indeterminate-result/rule.md に従う）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEFAULT_TERMS_FILE="$REPO_ROOT/docs/references/retired-terms.json"

terms_file() {
  printf '%s\n' "${RETIRED_TERMS_FILE:-$DEFAULT_TERMS_FILE}"
}

# list_target_files: <repo_root> 配下の docs/tasks/直下・docs/tasks/design/直下の
# .md を改行区切りで返す（done/・work-records/ はここで自然に除外される。
# maxdepth 1 のため、それらのサブディレクトリの中へは降りない）。台帳2件
# （LEDGER_BASENAMES）は指示書ではないため除外する。
list_target_files() {
  local repo_root="$1" f base
  {
    if [ -d "$repo_root/docs/tasks" ]; then
      find "$repo_root/docs/tasks" -maxdepth 1 -type f -name '*.md' 2>/dev/null | LC_ALL=C sort
    fi
    if [ -d "$repo_root/docs/tasks/design" ]; then
      find "$repo_root/docs/tasks/design" -maxdepth 1 -type f -name '*.md' 2>/dev/null | LC_ALL=C sort
    fi
  } | while IFS= read -r f; do
    base="$(basename "$f")"
    is_ledger_file "$base" && continue
    printf '%s\n' "$f"
  done
}

# load_terms: 一覧JSONから語を1行1語で返す。呼び出し元が空・不正を判定する。
load_terms() {
  local terms_json="$1"
  jq -r '.terms[]?.term // empty' "$terms_json" 2>/dev/null
}

run_check() {
  local repo_root="$1" terms_json term
  local -a grep_args=()
  local -a target_files=()

  terms_json="$(terms_file)"

  if [ ! -f "$terms_json" ]; then
    echo "[UNKNOWN] 廃止語の一覧が存在しないため判定できません（参照先: ${terms_json}）" >&2
    return 2
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "[UNKNOWN] jqが無いため判定できません" >&2
    return 2
  fi
  if ! jq -e '.terms | type == "array" and length > 0 and all(.term? | type == "string" and length > 0)' \
    "$terms_json" >/dev/null 2>&1; then
    echo "[UNKNOWN] 廃止語の一覧の形式が不正です（参照先: ${terms_json}）" >&2
    return 2
  fi

  while IFS= read -r term; do
    [ -n "$term" ] || continue
    grep_args+=(-e "$term")
  done < <(load_terms "$terms_json")

  if [ "${#grep_args[@]}" -eq 0 ]; then
    echo "[UNKNOWN] 廃止語の一覧が0件のため判定できません（参照先: ${terms_json}）" >&2
    return 2
  fi

  if [ ! -d "$repo_root/docs/tasks" ] && [ ! -d "$repo_root/docs/tasks/design" ]; then
    echo "[UNKNOWN] 走査対象（docs/tasks・docs/tasks/design）が1つも見つからないため判定できません（参照したルート: ${repo_root}）" >&2
    return 2
  fi

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    target_files+=("$line")
  done < <(list_target_files "$repo_root")

  local file out hit_count=0
  for file in "${target_files[@]}"; do
    out="$(strip_fences "$file" | grep -n -F "${grep_args[@]}" 2>/dev/null || true)"
    [ -n "$out" ] || continue
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      echo "[FAIL] ${file}:${hit}"
      hit_count=$((hit_count + 1))
    done <<< "$out"
  done

  if [ "$hit_count" -gt 0 ]; then
    echo "[FAIL] 廃止済みの語が ${hit_count} 件残っている"
    return 1
  fi

  echo "[PASS] 廃止済みの語の残存は0件"
  return 0
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

run_self_test() {
  local pass=0 fail=0 tmp

  # 引数なしの mktemp は既定の置き場へ書こうとして失敗する環境がある
  # （.claude/rules/always/verification/indeterminate-result/rule.md）。
  # 置き場を明示し、失敗した場合は判定不能として扱う。
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/$(basename "${BASH_SOURCE[0]}" .sh).XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため自己テストを判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' RETURN

  assert_eq() {
    local name="$1" want="$2" actual="$3"
    if [ "$want" = "$actual" ]; then
      echo "  [PASS] $name"
      pass=$((pass + 1))
    else
      echo "  [FAIL] ${name}（期待 ${want}・実際 ${actual}）"
      fail=$((fail + 1))
    fi
  }

  assert_contains() {
    local name="$1" needle="$2" haystack="$3"
    case "$haystack" in
      *"$needle"*)
        echo "  [PASS] $name"
        pass=$((pass + 1))
        ;;
      *)
        echo "  [FAIL] ${name}（出力: ${haystack}）"
        fail=$((fail + 1))
        ;;
    esac
  }

  assert_not_contains() {
    local name="$1" needle="$2" haystack="$3"
    case "$haystack" in
      *"$needle"*)
        echo "  [FAIL] ${name}（出力: ${haystack}）"
        fail=$((fail + 1))
        ;;
      *)
        echo "  [PASS] $name"
        pass=$((pass + 1))
        ;;
    esac
  }

  write_terms() {
    cat > "$1" <<'JSON'
{
  "schemaVersion": 1,
  "terms": [
    { "term": "廃止語甲", "retiredBy": "0-000", "commit": "0000000000000000000000000000000000000000", "replacement": "後継語" },
    { "term": "廃止語乙", "retiredBy": "0-000", "commit": "0000000000000000000000000000000000000000", "replacement": null }
  ]
}
JSON
  }

  # ケース1: 一覧ファイルが無い → [UNKNOWN]・終了コード2。
  local case1="$tmp/case1" out1 rc1
  mkdir -p "$case1/docs/tasks"
  echo "本文に廃止語は無い" > "$case1/docs/tasks/a.md"
  out1="$(RETIRED_TERMS_FILE="$case1/no-such-file.json" run_check "$case1" 2>&1)"; rc1=$?
  assert_eq "ケース1-終了コード2" 2 "$rc1"
  assert_contains "ケース1-UNKNOWNラベル" '[UNKNOWN]' "$out1"

  # ケース2: 一覧はあるが docs/tasks 配下に廃止語が無い → [PASS]・終了コード0。
  local case2="$tmp/case2" terms2 out2 rc2
  mkdir -p "$case2/docs/tasks" "$case2/docs/tasks/design"
  terms2="$case2/retired-terms.json"
  write_terms "$terms2"
  echo "本文に廃止語は無い" > "$case2/docs/tasks/clean.md"
  echo "設計から始める指示書。廃止語も無い" > "$case2/docs/tasks/design/clean-design.md"
  out2="$(RETIRED_TERMS_FILE="$terms2" run_check "$case2" 2>&1)"; rc2=$?
  assert_eq "ケース2-終了コード0" 0 "$rc2"
  assert_contains "ケース2-PASSラベル" '[PASS]' "$out2"

  # ケース3: docs/tasks 直下に廃止語が1件 → [FAIL]・終了コード1・該当行を報告。
  local case3="$tmp/case3" terms3 out3 rc3
  mkdir -p "$case3/docs/tasks"
  terms3="$case3/retired-terms.json"
  write_terms "$terms3"
  printf '1行目\n記録先は廃止語甲を使う\n3行目\n' > "$case3/docs/tasks/bad.md"
  out3="$(RETIRED_TERMS_FILE="$terms3" run_check "$case3" 2>&1)"; rc3=$?
  assert_eq "ケース3-終了コード1" 1 "$rc3"
  assert_contains "ケース3-FAILラベル" '[FAIL]' "$out3"
  assert_contains "ケース3-該当行を報告" 'bad.md:2:記録先は廃止語甲を使う' "$out3"

  # ケース4: docs/tasks/design/ 配下の廃止語も検出する。
  local case4="$tmp/case4" terms4 out4 rc4
  mkdir -p "$case4/docs/tasks/design"
  terms4="$case4/retired-terms.json"
  write_terms "$terms4"
  printf '設計から始める指示書\n廃止語乙が残っている\n' > "$case4/docs/tasks/design/bad-design.md"
  out4="$(RETIRED_TERMS_FILE="$terms4" run_check "$case4" 2>&1)"; rc4=$?
  assert_eq "ケース4-design配下も検出-終了コード1" 1 "$rc4"
  assert_contains "ケース4-design配下の該当行を報告" 'bad-design.md:2:廃止語乙が残っている' "$out4"

  # ケース5: docs/tasks/done/ と docs/tasks/work-records/ は対象外。
  local case5="$tmp/case5" terms5 out5 rc5
  mkdir -p "$case5/docs/tasks/done" "$case5/docs/tasks/work-records"
  terms5="$case5/retired-terms.json"
  write_terms "$terms5"
  echo "廃止語甲を含む片付いた指示書" > "$case5/docs/tasks/done/old.md"
  echo "廃止語乙を含む作業記録" > "$case5/docs/tasks/work-records/log.md"
  out5="$(RETIRED_TERMS_FILE="$terms5" run_check "$case5" 2>&1)"; rc5=$?
  assert_eq "ケース5-done/work-recordsは対象外-終了コード0" 0 "$rc5"
  assert_contains "ケース5-PASSラベル" '[PASS]' "$out5"

  # ケース6: 一覧JSONの形式が不正（termsが配列でない）→ [UNKNOWN]・終了コード2。
  local case6="$tmp/case6" terms6 out6 rc6
  mkdir -p "$case6/docs/tasks"
  terms6="$case6/retired-terms.json"
  echo '{ "schemaVersion": 1, "terms": {} }' > "$terms6"
  out6="$(RETIRED_TERMS_FILE="$terms6" run_check "$case6" 2>&1)"; rc6=$?
  assert_eq "ケース6-不正形式-終了コード2" 2 "$rc6"
  assert_contains "ケース6-UNKNOWNラベル" '[UNKNOWN]' "$out6"

  # ケース7: 走査対象（docs/tasks・docs/tasks/design）が1つも無い → [UNKNOWN]・終了コード2。
  local case7="$tmp/case7" terms7 out7 rc7
  mkdir -p "$case7"
  terms7="$case7/retired-terms.json"
  write_terms "$terms7"
  out7="$(RETIRED_TERMS_FILE="$terms7" run_check "$case7" 2>&1)"; rc7=$?
  assert_eq "ケース7-走査対象なし-終了コード2" 2 "$rc7"
  assert_contains "ケース7-UNKNOWNラベル" '[UNKNOWN]' "$out7"

  # ケース8: --self-test 自身が実引数として処理される。
  if grep -q -- '--self-test' "$SCRIPT_DIR/check-retired-terms.sh"; then
    echo "  [PASS] ケース8-self-testの実装確認"
    pass=$((pass + 1))
  else
    echo "  [FAIL] ケース8-self-testの実装確認"
    fail=$((fail + 1))
  fi

  # ケース9: 台帳（指摘改善一覧.md）に廃止語があっても対象外。指示書には検出する。
  local case9="$tmp/case9" terms9 out9 rc9
  mkdir -p "$case9/docs/tasks"
  terms9="$case9/retired-terms.json"
  write_terms "$terms9"
  echo "台帳の記述に廃止語甲が残っている" > "$case9/docs/tasks/指摘改善一覧.md"
  echo "台帳の記述に廃止語乙が残っている" > "$case9/docs/tasks/作業課題一覧.md"
  printf '1行目\n本文に廃止語甲がある\n' > "$case9/docs/tasks/normal.md"
  out9="$(RETIRED_TERMS_FILE="$terms9" run_check "$case9" 2>&1)"; rc9=$?
  assert_eq "ケース9-台帳除外-終了コード1" 1 "$rc9"
  assert_not_contains "ケース9-台帳の指摘改善一覧は検出しない" '指摘改善一覧.md' "$out9"
  assert_not_contains "ケース9-台帳の作業課題一覧は検出しない" '作業課題一覧.md' "$out9"
  assert_contains "ケース9-通常の指示書は検出する" 'normal.md:2:本文に廃止語甲がある' "$out9"

  # ケース10: コード柵で囲んだ引用は対象外。柵の外の同語は検出する。
  local case10="$tmp/case10" terms10 out10 rc10
  mkdir -p "$case10/docs/tasks"
  terms10="$case10/retired-terms.json"
  write_terms "$terms10"
  printf '柵の外に廃止語甲がある\n\n```\n廃止語甲\n廃止語乙\n```\n' > "$case10/docs/tasks/fenced.md"
  out10="$(RETIRED_TERMS_FILE="$terms10" run_check "$case10" 2>&1)"; rc10=$?
  assert_eq "ケース10-終了コード1" 1 "$rc10"
  assert_eq "ケース10-柵外の1件のみ検出" 1 "$(printf '%s\n' "$out10" | grep -c '^\[FAIL\] .*fenced\.md:')"
  assert_contains "ケース10-柵外の該当行を報告" 'fenced.md:1:柵の外に廃止語甲がある' "$out10"

  # ケース11: このスクリプト自身（docs/scripts/）と一覧ファイル自身
  # （docs/references/）は走査範囲の構造そのものによって対象外になる。
  # 実リポジトリを走査した出力に、この2ファイルへの言及が現れないことを確かめる。
  local out11
  out11="$(run_check "$REPO_ROOT" 2>&1 || true)"
  assert_not_contains "ケース11-自スクリプトへの言及なし" 'check-retired-terms.sh:' "$out11"
  assert_not_contains "ケース11-一覧ファイルへの言及なし" 'retired-terms.json:' "$out11"

  echo "self-test: ${pass} PASS, ${fail} FAIL" >&2
  [ "$fail" -eq 0 ]
}

main() {
  if [ "${1:-}" = "--self-test" ]; then
    run_self_test
    exit $?
  fi

  local repo_root="$REPO_ROOT"
  if [ "${1:-}" = "--repo-root" ]; then
    repo_root="${2:-}"
  fi

  run_check "$repo_root"
  exit $?
}

main "$@"
