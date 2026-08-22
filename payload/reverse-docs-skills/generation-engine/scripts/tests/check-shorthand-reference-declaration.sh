#!/usr/bin/env bash
# 他文書への参照の短縮形が、宣言を伴わずに使われていないかを検査する。
#
# document-writing.md「他文書への参照の短縮」節が定める記法（（<短縮ラベル>:
# <キー名>）の形で短縮参照を書く前に、初出で宣言する）に基づき、生成物本文
# 中の短縮形参照（例:「（要確認: 冪等性欠如の業務上の許容）」）を検出し、
# 同じ文書内に対応する宣言文（「この参照を（<ラベル>」を含む文）があるかを
# 確認する。宣言が無い短縮ラベルが1件でもあれば不合格とする。
#
# 使い方:
#   check-shorthand-reference-declaration.sh <project_root>
#   check-shorthand-reference-declaration.sh --self-test
#
# 終了コード:
#   0 = 宣言なし短縮形の使用なし
#   1 = 宣言なし短縮形の使用あり
#   2 = 判定不能（mktemp失敗）
#
# ロケールについて（実測に基づく判断）:
#   本スクリプトは LC_ALL=C ではなく LC_ALL=en_US.UTF-8 を明示する。実測:
#   LC_ALL=C を設定すると awk の match() が全角文字（マルチバイトUTF-8）を
#   含む正規表現（（[^（）:：]+: [^（）]*） 等）を正しく認識できなくなり、
#   本来検出できるはずの短縮形参照が0件になる現象を確認した
#   （bash 5.3.15 / macOS）。1-231 で得た教訓「多バイト文字列の完全一致
#   比較には LC_ALL=C を明示する」は、本スクリプトが行う「全角文字を含む
#   正規表現によるパターン抽出」には当てはまらない。両者は性質が異なり、
#   後者は UTF-8 ロケールでなければ正しく動作しない。呼び出し元の環境変数
#   に LC_ALL=C が既に設定されていても本スクリプト内では上書きされるよう、
#   自身で明示的に UTF-8 ロケールを設定する。
set -uo pipefail
export LC_ALL=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ファイル本文中に、指定ラベルの宣言文（「この参照を（<ラベル>」を含む行）
# があるかを判定する。
_has_declaration() {
  local file="$1" label="$2"
  grep -qF "この参照を（${label}" "$file" 2>/dev/null
}

# ファイル本文中の短縮形参照「（<ラベル>: <値>）」のラベル部分を、重複を
# まとめて1行1レコードで返す。awk の match()/substr() で抽出する（ファイル
# 冒頭の「ロケールについて」の注記のとおり、LC_ALL=C は設定しない）。
# awk 呼び出し自体にも LC_ALL=en_US.UTF-8 を明示する。呼び出し元の環境変数
# に LC_ALL=C が既に設定されている場合、スクリプト先頭の export だけでは
# `LC_ALL=C run_check ...` のようにコマンド前置きで上書きされてしまうため
# （bash の環境変数割り当ての仕様上、前置き代入は関数呼び出し全体に効く）、
# awk コマンドの実行そのものへ都度ロケールを明示することで、呼び出し方に
# 依存せず常に UTF-8 として解釈させる。
_extract_shorthand_labels() {
  local file="$1"
  LC_ALL=en_US.UTF-8 awk '{
    while (match($0, /（[^（）:：]+: [^（）]*）/)) {
      s = substr($0, RSTART, RLENGTH)
      print s
      $0 = substr($0, RSTART + RLENGTH)
    }
  }' "$file" 2>/dev/null | sed -E 's/^（([^:：]+): .*/\1/' | sort -u
}

check_document() {
  local file="$1" rc=0 label labels
  labels="$(_extract_shorthand_labels "$file")"
  while IFS= read -r label; do
    [ -n "$label" ] || continue
    if ! _has_declaration "$file" "$label"; then
      echo "FAIL 短縮参照-宣言なし ${file}: 短縮ラベル「${label}」の宣言（「この参照を（${label}」を含む文）が本文に無い"
      rc=1
    fi
  done <<< "$labels"
  return "$rc"
}

run_check() {
  local project_root="$1" rc=0 checked_count=0 file
  if [ ! -d "$project_root" ]; then
    echo "ERROR: ディレクトリが存在しません: $project_root" >&2
    return 1
  fi
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    checked_count=$((checked_count + 1))
    check_document "$file" || rc=1
  done < <(find "$project_root" -type f -name '*.md' 2>/dev/null | sort)

  if [ "$checked_count" -eq 0 ]; then
    echo "ERROR: 検査対象の設計文書が0件です: project_root=$project_root" >&2
    return 1
  fi
  return "$rc"
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

SELF_TEST_DIRS=()

cleanup_self_test_dirs() {
  local dir
  for dir in "${SELF_TEST_DIRS[@]}"; do
    [ -n "$dir" ] || continue
    case "$dir" in
      "${TMPDIR:-/tmp}"/shorthand-reference-self-test.*)
        [ ! -e "$dir" ] || rm -rf -- "$dir"
        ;;
    esac
  done
}

self_test() {
  local pass=0 fail=0
  trap cleanup_self_test_dirs EXIT

  assert_eq() {
    local name="$1" want="$2" actual="$3"
    if [ "$want" = "$actual" ]; then
      echo "  [PASS] $name"; pass=$((pass + 1))
    else
      echo "  [FAIL] ${name}（期待 ${want}・実際 ${actual}）"; fail=$((fail + 1))
    fi
  }
  assert_contains() {
    local name="$1" needle="$2" haystack="$3"
    case "$haystack" in
      *"$needle"*) echo "  [PASS] $name"; pass=$((pass + 1)) ;;
      *) echo "  [FAIL] ${name}（出力: ${haystack}）"; fail=$((fail + 1)) ;;
    esac
  }
  new_tmp_dir() {
    local dir
    if ! dir="$(mktemp -d "${TMPDIR:-/tmp}/shorthand-reference-self-test.XXXXXX" 2>/dev/null)" || [ -z "$dir" ]; then
      echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）"
      exit 2
    fi
    SELF_TEST_DIRS+=("$dir")
    printf '%s\n' "$dir"
  }

  # 検収1: 宣言があれば短縮形の使用は合格。
  local tmp_1 doc_1 out_1 rc_1
  tmp_1="$(new_tmp_dir)"
  doc_1="$tmp_1/API詳細設計書.md"
  cat > "$doc_1" <<'DOC'
# 注文API API詳細設計書

確定できなかった事項は要確認事項の節が持つ（以下、この参照を（要確認: キー名）と表記する）。

| 項目 | 参照 |
|---|---|
| 冪等性 | （要確認: 冪等性欠如の業務上の許容） |
DOC
  out_1="$(run_check "$tmp_1")"; rc_1=$?
  assert_eq "検収1-終了コード" 0 "$rc_1"
  assert_eq "検収1-出力0件" '' "$out_1"
  rm -rf "$tmp_1"

  # 検収2: 宣言なしに短縮形だけを使うと不合格。
  local tmp_2 doc_2 out_2 rc_2
  tmp_2="$(new_tmp_dir)"
  doc_2="$tmp_2/API詳細設計書.md"
  cat > "$doc_2" <<'DOC'
# 注文API API詳細設計書

| 項目 | 参照 |
|---|---|
| 冪等性 | （要確認: 冪等性欠如の業務上の許容） |
DOC
  out_2="$(run_check "$tmp_2")"; rc_2=$?
  assert_eq "検収2-終了コード" 1 "$rc_2"
  assert_contains "検収2-宣言なしをFAIL" 'FAIL 短縮参照-宣言なし' "$out_2"
  rm -rf "$tmp_2"

  # 検収3: 短縮形参照そのものが無い文書は合格（対象外）。
  local tmp_3 doc_3 out_3 rc_3
  tmp_3="$(new_tmp_dir)"
  doc_3="$tmp_3/API詳細設計書.md"
  cat > "$doc_3" <<'DOC'
# 注文API API詳細設計書

参照を一切持たない本文。
DOC
  out_3="$(run_check "$tmp_3")"; rc_3=$?
  assert_eq "検収3-終了コード" 0 "$rc_3"
  assert_eq "検収3-出力0件" '' "$out_3"
  rm -rf "$tmp_3"

  # 追加回帰1: 複数の短縮ラベルのうち1つだけ宣言が無い場合、その1件だけFAIL。
  local tmp_4 doc_4 out_4 rc_4
  tmp_4="$(new_tmp_dir)"
  doc_4="$tmp_4/API詳細設計書.md"
  cat > "$doc_4" <<'DOC'
# 注文API API詳細設計書

要確認事項の節を参照する（以下、この参照を（要確認: キー名）と表記する）。

| 項目 | 参照 |
|---|---|
| 冪等性 | （要確認: 冪等性欠如の業務上の許容） |
| 上限 | （境界: 上限価格の判定） |
DOC
  out_4="$(run_check "$tmp_4")"; rc_4=$?
  assert_eq "追加回帰1-終了コード" 1 "$rc_4"
  assert_contains "追加回帰1-未宣言ラベルのみFAIL" 'FAIL 短縮参照-宣言なし' "$out_4"
  if [[ "$out_4" == *'「要確認」'* ]]; then
    echo "  [FAIL] 追加回帰1-宣言済みラベルは報告しない（出力: ${out_4}）"; fail=$((fail + 1))
  else
    echo "  [PASS] 追加回帰1-宣言済みラベルは報告しない"; pass=$((pass + 1))
  fi
  rm -rf "$tmp_4"

  # 追加回帰2: 実行環境のロケールが既定（LC_ALL未設定）と LC_ALL=C の
  # 両方で、検出結果が一致することを確認する。ファイル冒頭の「ロケールに
  # ついて」の注記のとおり、LC_ALL=C は awk の全角文字マッチングを壊すため
  # 本スクリプト自身は設定しないが、呼び出し環境が LC_ALL=C を既に持って
  # いる場合に壊れないかは別途確認が要る。
  local tmp_locale doc_locale out_default out_forced_c rc_default rc_forced_c
  tmp_locale="$(new_tmp_dir)"
  doc_locale="$tmp_locale/API詳細設計書.md"
  cat > "$doc_locale" <<'DOC'
# 注文API API詳細設計書

| 項目 | 参照 |
|---|---|
| 冪等性 | （要確認: 冪等性欠如の業務上の許容） |
DOC
  out_default="$(run_check "$tmp_locale")"; rc_default=$?
  out_forced_c="$(LC_ALL=C run_check "$tmp_locale")"; rc_forced_c=$?
  assert_eq "追加回帰2-既定ロケールは終了コード1" 1 "$rc_default"
  assert_eq "追加回帰2-呼び出し元LC_ALL=C下でも終了コード1" 1 "$rc_forced_c"
  assert_contains "追加回帰2-既定ロケールで宣言なしを検出" 'FAIL 短縮参照-宣言なし' "$out_default"
  assert_contains "追加回帰2-呼び出し元LC_ALL=C下でも宣言なしを検出" 'FAIL 短縮参照-宣言なし' "$out_forced_c"
  rm -rf "$tmp_locale"

  echo "self-test: $pass PASS, $fail FAIL"
  [ "$fail" -eq 0 ]
}

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi
  if [ "$#" -ne 1 ]; then
    echo "使い方: $(basename "$0") <project_root>" >&2
    echo "        $(basename "$0") --self-test" >&2
    exit 1
  fi
  run_check "$1"
  exit $?
}

main "$@"
