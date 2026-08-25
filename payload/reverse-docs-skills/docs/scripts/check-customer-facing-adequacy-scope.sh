#!/usr/bin/env bash
# check-customer-facing-adequacy-scope.sh — 1-265の判定表の判定1・3・4を、
# 対象外の語・対象外のファイルを除いた不合格0件の判定に絞り込む。
#
# 背景:
# 顧客提示適合検査（check-customer-facing-adequacy.sh）を見本の出力へ
# そのまま当てると、この指示書（1-265）が対象としない語（対象コード・顧客・
# 調査範囲・ためである）でも不合格になる。加えて、指示書の「対応の記録」
# 節（判断の記録）が既に対象外と決めた作例フィクスチャ4件（アーキテク
# チャ調査書.html・画面遷移図.html・シーケンス図.html・規約提案配下）でも
# 「原本」「抽出」が不合格になる。判定表へ生の呼び出しを書くと、これらの
# 既存の不合格に埋もれて、様式・定義・生成物側の言い換え（やること1〜3）
# が完了したかを見分けられない。
#
# 判断の記録が既に決めた対象外の内訳:
#   - 「対象コード」「顧客」「調査範囲」「ためである」の4語（見本全体）
#   - アーキテクチャ調査書.html・画面遷移図.html・シーケンス図.html・
#     規約提案配下の作例フィクスチャ（対応の記録の判断の記録3行目・
#     5行目。原本・抽出がここに残ることは既に据え置くと決めている）
#
# 本スクリプトは、上記4語のFAILを除外したうえで、残るFAIL（原本・
# 納品物・抽出のいずれか）の全件が上記4ファイルの内側に閉じているかを
# 確認する。ファイルを一律に除外の対象にはしない。閉じていない
# （＝様式・定義・生成物側に新しく混入した）FAILが1件でもあれば不合格に
# する。これにより、既に対象外と決めた作例フィクスチャの中身が今後
# 変わっても検査は反応せず、やること1〜3が対象とする様式・定義・生成物
# 側の再混入だけを検知し続ける。
#
# 判定式に縦棒(|)を書けないため（片付けの判定器が列の区切りと読み違える。
# check-broken-verdict-rows.sh の設計判断と同じ理由）、判定表からは本
# ファイル名だけを呼ぶ。
#
# 先例: docs/scripts/check-boundary-value-scope.sh・
#       docs/scripts/check-case49-orphan-html.sh
#       （いずれも generation-engine/scripts/tests/ 側のラッパーを持たない。
#       第1層の集約は docs/scripts/ を走査対象に含めないため、この2件に
#       倣い本スクリプトもラッパーを新設しない）
#
# 使い方:
#   bash docs/scripts/check-customer-facing-adequacy-scope.sh <dir> [<dir> ...]
#   bash docs/scripts/check-customer-facing-adequacy-scope.sh --pp <name> [<name> ...]
#     （generation-engine/samples/project-portal/<name> への短縮記法。
#     判定表のセル内でパスを短く保つために使う）
#   bash docs/scripts/check-customer-facing-adequacy-scope.sh --self-test
#
# 終了コード:
#   0 = 対象外の語を除いた残存FAILが0件、または全件が対象外の4ファイルの
#       内側に閉じている
#   1 = 対象外の語・対象外のファイルの外側に不合格が1件以上残る
#   2 = 引数不正、または判定不能（mktemp失敗。実行環境のサンドボックス
#       制約等）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECKER="$REPO_ROOT/delivery-payload/templates/rules/checkers/check-customer-facing-adequacy.sh"

# 対象外の語（見本全体を通じて除外するFAILラベル。1-265の範囲外の語）
EXCLUDED_WORD_RE='第三者呼称-顧客|作る側の事情語-対象コード|作る側の事情語-調査範囲|作る側の事情語-ためである'

# 対象外のファイル（判断の記録が既に決めた作例フィクスチャ4件）
EXCLUDED_FILE_RE='アーキテクチャ調査書\.html|画面遷移図\.html|シーケンス図\.html|/規約提案/'

# 与えられた各ディレクトリへ検査本体を実行し、標準出力を連結して返す。
_scan_dirs() {
  local dir out
  out=""
  for dir in "$@"; do
    if [ ! -d "$dir" ]; then
      echo "ERROR: 対象ディレクトリが存在しません: $dir" >&2
      return 2
    fi
    out="${out}$(bash "$CHECKER" "$dir" 2>&1)"$'\n'
  done
  printf '%s' "$out"
}

# 1個以上のディレクトリを検査し、対象外の語・対象外のファイルを除いた
# 不合格の有無を判定する。標準出力へ根拠を出し、終了コードで合否を返す。
run_check() {
  if [ "$#" -eq 0 ]; then
    echo "usage: $0 <dir> [<dir> ...]" >&2
    return 2
  fi

  local combined remaining outside
  combined="$(_scan_dirs "$@")"
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    return "$rc"
  fi

  remaining="$(printf '%s\n' "$combined" | grep '^FAIL ' | grep -Ev "$EXCLUDED_WORD_RE" || true)"

  if [ -z "$remaining" ]; then
    echo "PASS: 対象外の語を除いた不合格は0件です"
    return 0
  fi

  outside="$(printf '%s\n' "$remaining" | grep -Ev "$EXCLUDED_FILE_RE" || true)"

  if [ -z "$outside" ]; then
    echo "PASS: 残存FAILは対象外の4ファイルの内側に閉じています"
    printf '%s\n' "$remaining"
    return 0
  fi

  echo "FAIL: 対象外の語・対象外のファイルの外側に不合格が残っています"
  printf '%s\n' "$outside"
  return 1
}

# --- self-test ---

run_self_test() {
  local pass=0 fail=0
  local tmp

  if ! tmp="$(mktemp -d 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）"
    return 2
  fi
  trap 'rm -rf "$tmp"' RETURN

  assert_pass() {
    local label="$1" out="$2" rc="$3"
    if [ "$rc" -eq 0 ]; then
      pass=$((pass + 1))
    else
      echo "  [FAIL] ${label}（終了コード ${rc}・出力: ${out}）"
      fail=$((fail + 1))
    fi
  }

  assert_fail() {
    local label="$1" out="$2" rc="$3"
    if [ "$rc" -ne 0 ]; then
      pass=$((pass + 1))
    else
      echo "  [FAIL] ${label}（終了コード0で通過してしまった）"
      fail=$((fail + 1))
    fi
  }

  assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    case "$haystack" in
      *"$needle"*) pass=$((pass + 1)) ;;
      *) echo "  [FAIL] ${label}（出力に含まれない: ${needle}）"; fail=$((fail + 1)) ;;
    esac
  }

  # ケース1: 対象外の語（顧客・対象コード）だけを含むディレクトリはPASS
  local d1="$tmp/case1"
  mkdir -p "$d1"
  cat > "$d1/x基本設計書.md" <<'EOF'
| 項目 | 内容 |
|---|---|
| 対象コード | server/x.ts |
| 顧客 | 注文した顧客の氏名 |
EOF
  local out1 rc1
  out1="$(run_check "$d1" 2>&1)"; rc1=$?
  assert_pass "ケース1-対象外の語だけならPASS" "$out1" "$rc1"

  # ケース2: 対象外の4ファイル以外に「原本」が残るとFAIL
  local d2="$tmp/case2"
  mkdir -p "$d2"
  cat > "$d2/y詳細設計書.md" <<'EOF'
本項目は原本コードの記載に基づく。
EOF
  local out2 rc2
  out2="$(run_check "$d2" 2>&1)"; rc2=$?
  assert_fail "ケース2-対象外ファイル外の原本はFAIL" "$out2" "$rc2"
  assert_contains "ケース2-出力に原本が含まれる" "原本" "$out2"

  # ケース3: 対象外の4ファイル（アーキテクチャ調査書.html）の中の「原本」はPASS
  local d3="$tmp/case3"
  mkdir -p "$d3"
  cat > "$d3/アーキテクチャ調査書.html" <<'EOF'
<p>原本コードから確定できない。抽出元として使える。</p>
EOF
  local out3 rc3
  out3="$(run_check "$d3" 2>&1)"; rc3=$?
  assert_pass "ケース3-対象外ファイル内の原本抽出はPASS" "$out3" "$rc3"

  # ケース4: 対象外の4ファイル（規約提案配下）の中の「抽出」はPASS
  local d4="$tmp/case4/規約提案"
  mkdir -p "$d4"
  cat > "$d4/サンプル規約提案.html" <<'EOF'
<dd>サンプルアプリのAPI実装から抽出した規約候補</dd>
EOF
  local out4 rc4
  out4="$(run_check "$tmp/case4" 2>&1)"; rc4=$?
  assert_pass "ケース4-規約提案配下の抽出はPASS" "$out4" "$rc4"

  # ケース5: 対象ディレクトリが存在しない場合は終了コード2
  local out5 rc5
  out5="$(run_check "$tmp/does-not-exist" 2>&1)"; rc5=$?
  if [ "$rc5" -eq 2 ]; then
    pass=$((pass + 1))
  else
    echo "  [FAIL] ケース5-存在しないディレクトリは終了コード2（実際: ${rc5}）"
    fail=$((fail + 1))
  fi

  # ケース6: 実在の見本（project-portal/matrices）はPASS（既に0件）
  local matrices_dir="$REPO_ROOT/generation-engine/samples/project-portal/matrices"
  if [ -d "$matrices_dir" ]; then
    local out6 rc6
    out6="$(run_check "$matrices_dir" 2>&1)"; rc6=$?
    assert_pass "ケース6-project-portal/matricesはPASS" "$out6" "$rc6"
  fi

  # ケース7: 実在の見本（project-portal/foundation）はPASS
  # （原本・抽出はアーキテクチャ調査書.html内に閉じているため）
  local foundation_dir="$REPO_ROOT/generation-engine/samples/project-portal/foundation"
  if [ -d "$foundation_dir" ]; then
    local out7 rc7
    out7="$(run_check "$foundation_dir" 2>&1)"; rc7=$?
    assert_pass "ケース7-project-portal/foundationはPASS" "$out7" "$rc7"
  fi

  # ケース8: 実在の見本（lists と matrices の2ディレクトリ同時指定）はPASS
  local lists_dir="$REPO_ROOT/generation-engine/samples/project-portal/lists"
  if [ -d "$lists_dir" ] && [ -d "$matrices_dir" ]; then
    local out8 rc8
    out8="$(run_check "$lists_dir" "$matrices_dir" 2>&1)"; rc8=$?
    assert_pass "ケース8-lists+matricesの同時指定はPASS" "$out8" "$rc8"
  fi

  # ケース9: 見本全体（generation-engine/samples）はPASS
  local samples_dir="$REPO_ROOT/generation-engine/samples"
  if [ -d "$samples_dir" ]; then
    local out9 rc9
    out9="$(run_check "$samples_dir" 2>&1)"; rc9=$?
    assert_pass "ケース9-見本全体はPASS" "$out9" "$rc9"
  fi

  # ケース10: --pp 短縮記法（foundation単体）が実ディレクトリ指定と同じ結果になる
  if [ -d "$foundation_dir" ]; then
    local out10 rc10
    out10="$(cd "$REPO_ROOT" && bash docs/scripts/check-customer-facing-adequacy-scope.sh --pp foundation 2>&1)"; rc10=$?
    assert_pass "ケース10--pp foundationはPASS" "$out10" "$rc10"
  fi

  # ケース11: --pp 短縮記法（lists・matrices の2件同時指定）が実ディレクトリ指定と同じ結果になる
  if [ -d "$lists_dir" ] && [ -d "$matrices_dir" ]; then
    local out11 rc11
    out11="$(cd "$REPO_ROOT" && bash docs/scripts/check-customer-facing-adequacy-scope.sh --pp lists matrices 2>&1)"; rc11=$?
    assert_pass "ケース11--pp lists matricesはPASS" "$out11" "$rc11"
  fi

  # ケース12: --pp に名前を1つも渡さない場合は終了コード2
  local out12 rc12
  out12="$(cd "$REPO_ROOT" && bash docs/scripts/check-customer-facing-adequacy-scope.sh --pp 2>&1)"; rc12=$?
  if [ "$rc12" -eq 2 ]; then
    pass=$((pass + 1))
  else
    echo "  [FAIL] ケース12-引数無しの--ppは終了コード2（実際: ${rc12}）"
    fail=$((fail + 1))
  fi

  echo "self-test: $pass PASS, $fail FAIL"
  if [ "$fail" -gt 0 ]; then
    return 1
  fi
  return 0
}

# --pp <name> [<name> ...] は generation-engine/samples/project-portal/<name>
# への短縮記法である。判定表のセル内では、この短縮記法を使わないと
# パス文字列が長く、textlintの1文100字上限（ja-technical-writing/
# sentence-length）に抵触する（1-265の判定3・4で実測）。
expand_pp_args() {
  local name
  for name in "$@"; do
    printf '%s\n' "$REPO_ROOT/generation-engine/samples/project-portal/$name"
  done
}

case "${1:-}" in
  --self-test)
    run_self_test
    exit $?
    ;;
  --pp)
    shift
    if [ "$#" -eq 0 ]; then
      echo "usage: $0 --pp <name> [<name> ...]" >&2
      exit 2
    fi
    mapfile -t _pp_dirs < <(expand_pp_args "$@")
    run_check "${_pp_dirs[@]}"
    exit $?
    ;;
  "")
    echo "usage: $0 <dir> [<dir> ...]" >&2
    echo "       $0 --pp <name> [<name> ...]" >&2
    echo "       $0 --self-test" >&2
    exit 2
    ;;
  *)
    run_check "$@"
    exit $?
    ;;
esac
