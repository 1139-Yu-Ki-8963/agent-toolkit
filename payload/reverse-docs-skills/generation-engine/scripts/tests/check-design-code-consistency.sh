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
# 1種目（件数の規則）の抽出位置は、表の直前にある本文の行に限る
# （表の行の中とコードの囲みの中を除く）。数値がその表を数えたものかは、
# 表への言及（「表」の文字を含む行、またはその直前の行）または表の直前の
# 行であることのいずれかで判定する。単純に「出現位置より後で最初に
# 現れる表」まで対象にすると、表の行の中の数値（例:「入札の結果1件を
# 含む配列」）や、本文中で別の対象を数えた数値（例:「1ページ20件」）を
# 拾ってしまい、対象プロジェクトの納品物で765件の偽の検出になった
# （1-266）。走査の範囲（既定は docs/design）も、このスクリプトへ
# 直書きせず design-code-consistency.json の
# categories.countConsistency.targetRootPath から解決する。
#
# 使い方:
#   check-design-code-consistency.sh <project_root> [source_dir]
#   check-design-code-consistency.sh --self-test
#
# source_dir は旧呼び出しとの引数互換のため受理するが、読み取らない。
# 終了コード: 0=一致、1=不一致、2=判定不能（self-test用一時領域の作成失敗）
set -uo pipefail
export LC_ALL=C

# 数値と、直後の表の実データ行数の対を1行1組で出力する（<行番号>:<数値>:<表の実数>）。
# 抽出位置は表の行の中とコードの囲みの中を除いた本文の行に限り、
# 表への言及（自分の行または直前の行に「表」を含む）または表の直前の行
# （空行を挟んでもよい）のいずれかを満たすものだけを対象にする。
# 対象になった数値の直後に完結した表が1つも見つからない場合は、その数値
# を対象から外す（従来の「見つからなければ実数0として不一致にする」動作
# は、対象を表の直前・表への言及に絞った後は不要になった。表が存在しない
# のに件数だけ書かれている状態は、この検査の対象外である）。
_count_consistency_candidates() {
  local doc_file="$1"
  awk '
    function is_table_row(l) { return (l ~ /^\|.*\|[[:space:]]*$/) }
    # 「表」の1文字だけでは「表示」（displayの意）を「表」への言及と誤認する
    # （1-266実測: 「未読件数が0件の場合はバッジ自体を表示しない。」を表への
    # 言及と誤判定した）。「表示」を取り除いてから残りに「表」があるかで
    # 判定する。
    function mentions_table(l,    t) {
      t = l
      gsub(/表示/, "", t)
      return (t ~ /表/)
    }
    {
      lines[NR] = $0
    }
    END {
      infence = 0
      for (i = 1; i <= NR; i++) {
        l = lines[i]
        marker = (l ~ /^```/)
        fenced[i] = infence || marker
        if (marker) infence = !infence
        tablerow[i] = is_table_row(l)
      }
      for (i = 1; i <= NR; i++) {
        l = lines[i]
        if (fenced[i]) continue
        if (tablerow[i]) continue
        if (l !~ /[0-9]+(個|件|箇所|サブルーチン)/) continue

        mentions = mentions_table(l)
        if (!mentions && i > 1 && mentions_table(lines[i - 1])) mentions = 1

        adjacent = 0
        p = i + 1
        while (p <= NR && lines[p] ~ /^[[:space:]]*$/) p++
        if (p <= NR && tablerow[p]) adjacent = 1

        if (!mentions && !adjacent) continue

        state = 0; count = 0; found = 0
        for (k = i + 1; k <= NR; k++) {
          if (tablerow[k]) {
            if (state == 0) { state = 1; continue }
            if (state == 1) {
              if (lines[k] ~ /^\|[|: -]+\|[[:space:]]*$/ && lines[k] ~ /---/) { state = 2; continue }
              state = 0; continue
            }
            if (state == 2) { count++; continue }
          } else {
            if (state == 2) { found = 1; break }
            state = 0
          }
        }
        if (state == 2) found = 1
        if (!found) continue

        ln = l
        while (match(ln, /[0-9]+(個|件|箇所|サブルーチン)/)) {
          numstr = substr(ln, RSTART, RLENGTH)
          num = numstr
          sub(/(個|件|箇所|サブルーチン)$/, "", num)
          print i ":" num ":" count
          ln = substr(ln, RSTART + RLENGTH)
        }
      }
    }
  ' "$doc_file"
}

check_count_consistency() {
  local doc_file="$1" rc=0
  local candidates
  candidates="$(_count_consistency_candidates "$doc_file")"
  [ -n "$candidates" ] || return 0

  local line_no number table_rows
  while IFS=: read -r line_no number table_rows; do
    [ -n "$line_no" ] || continue
    if [ "$table_rows" != "$number" ]; then
      echo "FAIL 件数不一致 ${doc_file}:${line_no}: 本文の記述「${number}」に対し直後の表の実数は${table_rows}"
      rc=1
    fi
  done <<< "$candidates"
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

# 件数検査の走査範囲（project_root からの相対パス）を定義ファイルから読む。
# 定義に値が無ければ空文字を返す。「docs/design」という文字列そのものを
# この関数の外（呼び出し側の走査条件）へ書かないこと。書くと定義ファイルを
# 直書きへ戻すのと同じ意味になる（1-266）。
_count_consistency_root() {
  local repo_root="$1"
  jq -r '.categories.countConsistency.targetRootPath // empty' \
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
  local repo_root section_heading count_root
  repo_root="$(_repo_root)"
  section_heading="$(_boundary_section_heading "$repo_root")"
  if [ -z "$section_heading" ]; then
    echo "ERROR: 境界値検査の対象節見出しを定義ファイルから読めません（$repo_root/delivery-payload/references/design-code-consistency.json の categories.boundaryValueConsistency.targetSectionHeading）" >&2
    return 1
  fi
  count_root="$(_count_consistency_root "$repo_root")"
  if [ -z "$count_root" ]; then
    echo "ERROR: 件数検査の走査範囲を定義ファイルから読めません（$repo_root/delivery-payload/references/design-code-consistency.json の categories.countConsistency.targetRootPath）" >&2
    return 1
  fi
  local doc_file unit_dir
  while IFS= read -r doc_file; do
    [ -n "$doc_file" ] || continue
    check_count_consistency "$doc_file" || rc=1
  done < <(find "$project_root/$count_root" -type f -name '*.md' 2>/dev/null | sort)
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

  # 1-266: 表の行の中にある数値は拾わない。
  # セル内の「1件」「99件」は表の実データ行数（2件）と一致しないが、
  # 表の行そのものは抽出位置から除外されるため不合格にならない。
  mkdir -p "$tmp/table-cell/docs/design/apis/api-cell/detail-design"
  cat > "$tmp/table-cell/docs/design/apis/api-cell/detail-design/API詳細設計書.md" <<'MD'
# API詳細設計書

| 項目 | 内容 |
|---|---|
| 対象範囲 | 入札の結果1件を含む配列（99件） |
| 備考 | 未使用 |
MD
  out="$(run_check "$tmp/table-cell" 2>&1)"; rc=$?
  assert_rc "表の行の中の数値を拾わない" 0 "$rc"

  # 1-266: 本文で別の対象を数えた数値は拾わない。
  # 表への言及が無く、表の直前の行でもない（間に無関係な文が挟まる）
  # 数値は、表の実数と食い違っても対象に含めない。
  mkdir -p "$tmp/off-topic/docs/design/apis/api-off/detail-design"
  cat > "$tmp/off-topic/docs/design/apis/api-off/detail-design/API詳細設計書.md" <<'MD'
# API詳細設計書

対象は3件です。

この節では上記と無関係な処理を説明する。

| キー | 条件 |
|---|---|
| lower-bound | 0以上 |
MD
  out="$(run_check "$tmp/off-topic" 2>&1)"; rc=$?
  assert_rc "本文で別の対象を数えた数値を拾わない" 0 "$rc"

  # 1-266: コードの囲みの中にある数値は拾わない。
  # フェンス内では数値の直後が表そのものでも対象にしない。
  mkdir -p "$tmp/fenced/docs/design/apis/api-fenced/detail-design"
  {
    printf '# API詳細設計書\n\n'
    printf '```\n'
    printf '対象は5件です。\n'
    printf '| キー | 条件 |\n'
    printf '|---|---|\n'
    printf '| lower-bound | 0以上 |\n'
    printf '```\n'
  } > "$tmp/fenced/docs/design/apis/api-fenced/detail-design/API詳細設計書.md"
  out="$(run_check "$tmp/fenced" 2>&1)"; rc=$?
  assert_rc "コードの囲みの中の数値を拾わない" 0 "$rc"

  # 1-266: 表の直前の行は、間に空行を挟んでも対象になる
  # （実例: docs/design/common/メッセージ定義書.md の「総件数: 4件」は
  # 空行を挟んで表が続く）。
  mkdir -p "$tmp/blank-adjacent/docs/design/apis/api-blank/detail-design"
  cat > "$tmp/blank-adjacent/docs/design/apis/api-blank/detail-design/API詳細設計書.md" <<'MD'
# API詳細設計書

総件数: 2件

| キー | 条件 |
|---|---|
| lower-bound | 0以上 |
| upper-bound | 100以下 |
MD
  out="$(run_check "$tmp/blank-adjacent" 2>&1)"; rc=$?
  assert_rc "空行を挟んだ表の直前の行が一致" 0 "$rc"

  cp -R "$tmp/blank-adjacent" "$tmp/blank-adjacent-fail"
  sed -i.bak 's/総件数: 2件/総件数: 3件/' "$tmp/blank-adjacent-fail/docs/design/apis/api-blank/detail-design/API詳細設計書.md"
  rm -f "$tmp/blank-adjacent-fail/docs/design/apis/api-blank/detail-design/API詳細設計書.md.bak"
  out="$(run_check "$tmp/blank-adjacent-fail" 2>&1)"; rc=$?
  assert_rc "空行を挟んだ表の直前の行の不一致も検出" 1 "$rc"

  # 1-266: 表への言及があれば、表の直前でなくても対象になる。
  mkdir -p "$tmp/mention/docs/design/apis/api-mention/detail-design"
  cat > "$tmp/mention/docs/design/apis/api-mention/detail-design/API詳細設計書.md" <<'MD'
# API詳細設計書

次の表に示す対象は2件である。

以下は補足の説明文であり、表そのものではない。

| キー | 条件 |
|---|---|
| lower-bound | 0以上 |
| upper-bound | 100以下 |
MD
  out="$(run_check "$tmp/mention" 2>&1)"; rc=$?
  assert_rc "表への言及がある離れた数値が一致" 0 "$rc"

  cp -R "$tmp/mention" "$tmp/mention-fail"
  sed -i.bak 's/対象は2件である/対象は3件である/' "$tmp/mention-fail/docs/design/apis/api-mention/detail-design/API詳細設計書.md"
  rm -f "$tmp/mention-fail/docs/design/apis/api-mention/detail-design/API詳細設計書.md.bak"
  out="$(run_check "$tmp/mention-fail" 2>&1)"; rc=$?
  assert_rc "表への言及がある離れた数値の不一致も検出" 1 "$rc"

  # 1-266実測: 「表示」は「表」への言及と誤認しない
  # （画面詳細設計書.md「未読件数が0件の場合はバッジ自体を表示しない。」）。
  mkdir -p "$tmp/display-word/docs/design/screens/screen-x/detail-design"
  cat > "$tmp/display-word/docs/design/screens/screen-x/detail-design/画面詳細設計書.md" <<'MD'
# 画面詳細設計書

未読件数が0件の場合はバッジ自体を表示しない。

---

## 定数

| 定数名 | 値 |
|---|---|
| MAX | 10 |
MD
  out="$(run_check "$tmp/display-word" 2>&1)"; rc=$?
  assert_rc "表示を表への言及と誤認しない" 0 "$rc"

  # 1-266: 走査の範囲は定義ファイルが指す docs/design 配下に限る。
  # docs/design の外にある不一致は対象外、配下にある不一致は引き続き検出する。
  mkdir -p "$tmp/scope/.claude/agents" "$tmp/scope/docs/design/apis/api-in-scope/detail-design"
  cat > "$tmp/scope/.claude/agents/note.md" <<'MD'
# メモ

対象は5件です。

| キー | 値 |
|---|---|
| a | 1 |
MD
  cat > "$tmp/scope/docs/design/apis/api-in-scope/detail-design/API詳細設計書.md" <<'MD'
# API詳細設計書

対象は9件です。

| キー | 値 |
|---|---|
| a | 1 |
MD
  out="$(run_check "$tmp/scope" 2>&1)"; rc=$?
  assert_rc "docs/design配下の不一致は引き続き検出" 1 "$rc"
  if printf '%s' "$out" | grep -q 'API詳細設計書.md' && ! printf '%s' "$out" | grep -q 'note.md'; then
    echo "  [PASS] 走査範囲がdocs/design配下に限定されている"; pass=$((pass + 1))
  else
    echo "  [FAIL] docs/design外のファイルが走査対象に混ざっている" >&2; fail=$((fail + 1))
  fi

  rm -f "$tmp/scope/docs/design/apis/api-in-scope/detail-design/API詳細設計書.md"
  out="$(run_check "$tmp/scope" 2>&1)"; rc=$?
  assert_rc "docs/design外のみの不一致は対象外" 0 "$rc"

  # 走査範囲をスクリプトへ直書きしていないことを確認する。
  count_root_body="$(sed -n '/^_count_consistency_root() {/,/^}/p' "${BASH_SOURCE[0]}" | grep -v '^[[:space:]]*#')"
  if printf '%s' "$count_root_body" | grep -qF '"docs/design"'; then
    echo "  [FAIL] 件数検査の走査範囲がスクリプトへ直書きされている" >&2; fail=$((fail + 1))
  else
    echo "  [PASS] 件数検査の走査範囲を定義ファイルから解決している"; pass=$((pass + 1))
  fi

  if [ "$(jq -r '.categories.countConsistency.targetRootPath // empty' \
    "$repo_root/delivery-payload/references/design-code-consistency.json")" = "docs/design" ]; then
    echo "  [PASS] 件数検査の走査範囲が定義ファイルに存在する"; pass=$((pass + 1))
  else
    echo "  [FAIL] 件数検査の走査範囲が定義ファイルから読めない" >&2; fail=$((fail + 1))
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
