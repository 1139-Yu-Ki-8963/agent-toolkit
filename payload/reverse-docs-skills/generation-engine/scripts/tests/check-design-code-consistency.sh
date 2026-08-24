#!/usr/bin/env bash
# 設計文書同士で完結する整合性を検査する。
#
# 対象コードの行番号を納品物へ保存すると、コード変更のたびに位置情報が腐る。
# そのため、対象コード・行を入力にする定数値検査と業務ルール近傍検査は廃止し、
# 次の2種類だけを残す。
#   1. 本文の件数と直後の表の実データ行数
#   2. 単体テスト設計書の境界値キーと詳細設計書の判定表キー
#
# 2種目の対象節（既定は「境界値」）は、このスクリプトへ直書きせず
# delivery-payload/references/design-code-consistency.json の
# categories.boundaryValueConsistency.targetSectionHeading から解決する。
# 単体テスト設計書はテストケース一覧・テスト観点・異常系・要確認事項など
# 「キー」列を持つ表を複数の節に持つため、節で絞らないと境界値以外の
# キーまで詳細設計書との突合対象に混ざる（1-267）。
#
# 使い方:
#   check-design-code-consistency.sh <project_root> [source_dir]
#   check-design-code-consistency.sh --self-test
#
# source_dir は旧呼び出しとの引数互換のため受理するが、読み取らない。
# 終了コード: 0=一致、1=不一致、2=判定不能（self-test用一時領域の作成失敗）
set -uo pipefail
export LC_ALL=C

check_count_consistency() {
  local doc_file="$1" rc=0
  local matches
  matches="$(grep -noE '[0-9]+(個|件|箇所|サブルーチン)' "$doc_file" 2>/dev/null || true)"
  [ -n "$matches" ] || return 0

  local line_no match number table_rows
  while IFS=: read -r line_no match; do
    [ -n "$line_no" ] || continue
    number="$(printf '%s' "$match" | grep -oE '^[0-9]+')"
    table_rows="$(awk -v start="$line_no" '
      BEGIN { state = 0; count = 0 }
      NR <= start { next }
      /^\|.*\|[[:space:]]*$/ {
        if (state == 0) { state = 1; next }
        if (state == 1) {
          if ($0 ~ /^\|[|: -]+\|[[:space:]]*$/ && $0 ~ /---/) { state = 2; next }
          state = 0; next
        }
        if (state == 2) { count++; next }
      }
      !/^\|.*\|[[:space:]]*$/ {
        if (state == 2) { exit }
        state = 0
      }
      END { print count }
    ' "$doc_file")"
    [ -n "$table_rows" ] || continue
    if [ "$table_rows" != "$number" ]; then
      echo "FAIL 件数不一致 ${doc_file}:${line_no}: 本文の記述「${number}」に対し直後の表の実数は${table_rows}"
      rc=1
    fi
  done <<< "$matches"
  return "$rc"
}

_repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd
}

# 境界値検査の対象節見出しを定義ファイルから読む。定義に値が無ければ空文字を返す。
# 「境界値」という文字列そのものをこの関数の外（呼び出し側の分岐条件）へ
# 書かないこと。書くと定義ファイルを直書きへ戻すのと同じ意味になる（1-267）。
_boundary_section_heading() {
  local repo_root="$1"
  jq -r '.categories.boundaryValueConsistency.targetSectionHeading // empty' \
    "$repo_root/delivery-payload/references/design-code-consistency.json" 2>/dev/null
}

# section_filter を渡すと、Markdownの見出し（# の連続で始まる行）で節を区切り、
# 見出しの文字列に section_filter を含む節の中にある表だけを対象にする。
# 見出し判定はASCIIの # 記号と空白だけを見るためLC_ALL=Cのままでよい
# （全角文字を負の文字クラスで除外する場合と異なり、ここでは部分一致
# index() と完全一致 == しか使わず、いずれも1-231の実測どおりLC_ALL=Cで
# 正しく動く。全角文字を含む負の文字クラスを使うときだけUTF-8ロケールが
# 要る。詳細は .claude/rules/always/design-record/implementation-decision/rule.md
# 「ロケールの使い分け」節を参照）。
_extract_key_column_values() {
  local file="$1" section_filter="${2:-}"
  awk -v target="$section_filter" '
    BEGIN { state = 0; in_section = (target == "") ? 1 : 0 }
    /^#+([ \t]|$)/ {
      if (target != "") {
        heading = $0
        sub(/^#+[ \t]*/, "", heading)
        gsub(/[ \t]+$/, "", heading)
        in_section = (index(heading, target) > 0) ? 1 : 0
      }
      state = 0
      next
    }
    !in_section { next }
    /^\|.*\|[[:space:]]*$/ {
      if (state == 0) {
        split($0, cells, "|")
        first = cells[2]
        gsub(/^[ \t]+|[ \t]+$/, "", first)
        if (first == "キー") { state = 1 } else { state = 0 }
        next
      }
      if (state == 1) {
        if ($0 ~ /^\|[|: -]+\|[[:space:]]*$/ && $0 ~ /---/) { state = 2; next }
        state = 0
        next
      }
      if (state == 2) {
        split($0, cells, "|")
        val = cells[2]
        gsub(/^[ \t]+|[ \t]+$/, "", val)
        if (val != "") print val
        next
      }
    }
    { if (state == 2) state = 0 }
  ' "$file"
}

check_boundary_value() {
  local unit_dir="$1" section_heading="${2:-}" rc=0
  local test_doc
  test_doc="$(find "$unit_dir" -type f -name '*単体テスト設計書.md' 2>/dev/null | sort | head -1)"
  [ -n "$test_doc" ] || return 0
  local test_keys
  test_keys="$(_extract_key_column_values "$test_doc" "$section_heading")"
  [ -n "$test_keys" ] || return 0

  local detail_docs all_detail_keys d
  detail_docs="$(find "$unit_dir" -type f -name '*詳細設計書.md' 2>/dev/null | sort)"
  all_detail_keys=""
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    all_detail_keys="${all_detail_keys}$(_extract_key_column_values "$d")"$'\n'
  done <<< "$detail_docs"

  local key
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    if ! printf '%s\n' "$all_detail_keys" | grep -qFx "$key"; then
      echo "FAIL 境界値-キー不整合 ${test_doc}: キー「${key}」が同一設計単位の詳細設計書の判定表に見つからない"
      rc=1
    fi
  done <<< "$test_keys"
  return "$rc"
}

run_check() {
  local project_root="$1" rc=0
  if [ ! -d "$project_root" ]; then
    echo "ERROR: ディレクトリが存在しません: $project_root" >&2
    return 1
  fi
  local repo_root section_heading
  repo_root="$(_repo_root)"
  section_heading="$(_boundary_section_heading "$repo_root")"
  if [ -z "$section_heading" ]; then
    echo "ERROR: 境界値検査の対象節見出しを定義ファイルから読めません（$repo_root/delivery-payload/references/design-code-consistency.json の categories.boundaryValueConsistency.targetSectionHeading）" >&2
    return 1
  fi
  local doc_file unit_dir
  while IFS= read -r doc_file; do
    [ -n "$doc_file" ] || continue
    check_count_consistency "$doc_file" || rc=1
  done < <(find "$project_root" -type f -name '*.md' 2>/dev/null | sort)
  while IFS= read -r unit_dir; do
    [ -n "$unit_dir" ] || continue
    check_boundary_value "$unit_dir" "$section_heading" || rc=1
  done < <(find "$project_root/docs/design" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | sort)
  return "$rc"
}

self_test() {
  local tmp
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/design-code-consistency-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] self-test用一時ディレクトリを作成できません"
    return 2
  fi
  trap 'rm -rf "$tmp"' RETURN
  local pass=0 fail=0 out rc

  assert_rc() {
    local name="$1" want="$2" actual="$3"
    if [ "$want" = "$actual" ]; then
      echo "  [PASS] $name"; pass=$((pass + 1))
    else
      # 全角文字との境界を明示し、LC_ALLの変更で変数名として誤読されるのを防ぐ。
      echo "  [FAIL] ${name}（期待=$want 実際=${actual}）" >&2; fail=$((fail + 1))
    fi
  }

  local saved_lc_all="$LC_ALL"
  LC_ALL=zh_CN.UTF-8
  out="$(assert_rc "全角文字に隣接する変数名" 0 1 2>&1)"
  LC_ALL="$saved_lc_all"
  if printf '%s' "$out" | grep -qF '  [FAIL] 全角文字に隣接する変数名（期待=0 実際=1）'; then
    echo "  [PASS] 失敗メッセージの変数境界を維持"; pass=$((pass + 1))
  else
    echo "  [FAIL] 失敗メッセージの変数境界が壊れている" >&2; fail=$((fail + 1))
  fi

  mkdir -p "$tmp/pass/docs/design/apis/api-order/detail-design" "$tmp/pass/docs/design/apis/api-order/テスト設計"
  cat > "$tmp/pass/docs/design/apis/api-order/detail-design/API詳細設計書.md" <<'MD'
# API詳細設計書
対象は2件です。
| キー | 条件 |
|---|---|
| lower-bound | 0以上 |
| upper-bound | 100以下 |
MD
  cat > "$tmp/pass/docs/design/apis/api-order/テスト設計/API単体テスト設計書.md" <<'MD'
# API単体テスト設計書

## §6 境界値

| キー | 境界値 |
|---|---|
| lower-bound | -1、0 |
| upper-bound | 100、101 |
MD
  run_check "$tmp/pass" >/dev/null 2>&1; rc=$?
  assert_rc "文書内の件数と境界値キーが一致" 0 "$rc"

  cp -R "$tmp/pass" "$tmp/count-fail"
  sed -i.bak 's/対象は2件/対象は3件/' "$tmp/count-fail/docs/design/apis/api-order/detail-design/API詳細設計書.md"
  rm -f "$tmp/count-fail/docs/design/apis/api-order/detail-design/API詳細設計書.md.bak"
  out="$(run_check "$tmp/count-fail" 2>&1)"; rc=$?
  assert_rc "本文件数の不一致を検出" 1 "$rc"
  if printf '%s' "$out" | grep -q 'FAIL 件数不一致'; then
    echo "  [PASS] 件数不一致の理由を出力"; pass=$((pass + 1))
  else
    echo "  [FAIL] 件数不一致の理由が無い" >&2; fail=$((fail + 1))
  fi

  cp -R "$tmp/pass" "$tmp/boundary-fail"
  sed -i.bak 's/upper-bound/missing-bound/' "$tmp/boundary-fail/docs/design/apis/api-order/テスト設計/API単体テスト設計書.md"
  rm -f "$tmp/boundary-fail/docs/design/apis/api-order/テスト設計/API単体テスト設計書.md.bak"
  out="$(run_check "$tmp/boundary-fail" 2>&1)"; rc=$?
  assert_rc "境界値キーの不一致を検出" 1 "$rc"
  if printf '%s' "$out" | grep -q 'missing-bound'; then
    echo "  [PASS] 不一致キーを出力"; pass=$((pass + 1))
  else
    echo "  [FAIL] 不一致キーが出力されない" >&2; fail=$((fail + 1))
  fi

  # 1-267: 境界値以外の節（テスト観点・テストケース一覧等）の「キー」列は
  # 対象から外れることを確認する。この節だけに存在するキーは詳細設計書に
  # 無くても不合格にしない。
  mkdir -p "$tmp/other-section/docs/design/apis/api-order/detail-design" "$tmp/other-section/docs/design/apis/api-order/テスト設計"
  cat > "$tmp/other-section/docs/design/apis/api-order/detail-design/API詳細設計書.md" <<'MD'
# API詳細設計書
| キー | 条件 |
|---|---|
| lower-bound | 0以上 |
| upper-bound | 100以下 |
MD
  cat > "$tmp/other-section/docs/design/apis/api-order/テスト設計/API単体テスト設計書.md" <<'MD'
# API単体テスト設計書

## §1 テスト観点

| キー | 観点 |
|---|---|
| off-topic-viewpoint | 詳細設計書に存在しない観点キー |

## §2 テストケース一覧

| キー | ケースの名前 |
|---|---|
| off-topic-case | 詳細設計書に存在しないケースキー |

## §5 異常系

| キー | 発生させる条件 |
|---|---|
| off-topic-error | 詳細設計書に存在しない異常系キー |

## §6 境界値

| キー | 境界値 |
|---|---|
| lower-bound | -1、0 |
| upper-bound | 100、101 |
MD
  out="$(run_check "$tmp/other-section" 2>&1)"; rc=$?
  assert_rc "境界値以外の節のキーは対象外" 0 "$rc"
  if printf '%s' "$out" | grep -qE 'off-topic-(viewpoint|case|error)'; then
    echo "  [FAIL] 境界値以外の節のキーが誤って照合対象になっている" >&2; fail=$((fail + 1))
  else
    echo "  [PASS] 境界値以外の節のキーを照合していない"; pass=$((pass + 1))
  fi

  # 様式（delivery-payload/templates/リバース検証/*/*単体テスト設計書.md）どおりに
  # 書いた文書は §6 境界値 の1列目が「観点のキー」であり「キー」ではない。
  # 様式どおりに書いた文書で0件になることを確認する。
  mkdir -p "$tmp/template-conformant/docs/design/apis/api-order/detail-design" "$tmp/template-conformant/docs/design/apis/api-order/テスト設計"
  cat > "$tmp/template-conformant/docs/design/apis/api-order/detail-design/API詳細設計書.md" <<'MD'
# API詳細設計書
| キー | 条件 |
|---|---|
| lower-bound | 0以上 |
MD
  cat > "$tmp/template-conformant/docs/design/apis/api-order/テスト設計/API単体テスト設計書.md" <<'MD'
# API単体テスト設計書

## §6 境界値

| 観点のキー | 関数・メソッド名 | 対象の引数・状態 | 境界の値 | 境界の直前と直後の扱い |
|---|---|---|---|---|
| view-1 | order.create | amount | 0 | 境界の直前は失敗、直後は成功 |
MD
  out="$(run_check "$tmp/template-conformant" 2>&1)"; rc=$?
  assert_rc "様式どおりの§6見出しで0件" 0 "$rc"

  # 節見出しをスクリプトの中に直書きしていないことを確認する。
  # _extract_key_column_values・check_boundary_value・run_check の本体
  # （コメントを除く）に、対象節見出しの値そのものである引用符付きの
  # 「"境界値"」というトークンが現れないこと。失敗メッセージのラベル
  # （「FAIL 境界値-キー不整合」等、値の一部ではなく地の文）は対象外。
  functional_body="$(sed -n '/^_extract_key_column_values() {/,/^run_check() {/p' "${BASH_SOURCE[0]}" | grep -v '^[[:space:]]*#')"
  if printf '%s' "$functional_body" | grep -qF '"境界値"'; then
    echo "  [FAIL] 対象節の見出しがスクリプトへ直書きされている" >&2; fail=$((fail + 1))
  else
    echo "  [PASS] 対象節の見出しを定義ファイルから解決している"; pass=$((pass + 1))
  fi

  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
  if jq -e '.categories | keys == ["boundaryValueConsistency", "countConsistency"]' \
    "$repo_root/delivery-payload/references/design-code-consistency.json" >/dev/null; then
    echo "  [PASS] 定義は文書内整合の2種類だけ"; pass=$((pass + 1))
  else
    echo "  [FAIL] 定義に廃止済みのコード位置検査が残る" >&2; fail=$((fail + 1))
  fi

  if [ "$(jq -r '.categories.boundaryValueConsistency.targetSectionHeading // empty' \
    "$repo_root/delivery-payload/references/design-code-consistency.json")" = "境界値" ]; then
    echo "  [PASS] 対象節見出しが定義ファイルに存在する"; pass=$((pass + 1))
  else
    echo "  [FAIL] 対象節見出しが定義ファイルから読めない" >&2; fail=$((fail + 1))
  fi

  echo "self-test: $pass PASS, $fail FAIL"
  [ "$fail" -eq 0 ]
}

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi
  if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "使い方: $(basename "$0") <project_root> [source_dir]" >&2
    echo "        $(basename "$0") --self-test" >&2
    exit 1
  fi
  run_check "$1"
}

main "$@"
