#!/usr/bin/env bash
set -euo pipefail

# recount-facts.sh — facts.yml の分類別件数を対象コードから独立再計数し突合する完全性ゲート（Phase 3）
#
# 使い方:
#   recount-facts.sh <facts.yml> <target_repo_path> <target_file相対パス...>
#   recount-facts.sh --self-test
#
# 検査（いずれか1件でも違反があれば exit 1。fail-closed）:
#   1. 分類別件数の乖離検査: facts.yml を読まずに①〜⑧の8分類を対象コードから独立再計数し、
#      facts.yml内の記載件数との乖離率 |再計数-記載|/max(両者,1) が0.05を超える分類が1つでもあれば違反。
#      ⑨measurement_pendingは再計数対象外（動的値のため）。
#   2. 必須フィールド空欄検査: 全9分類の各項目についてkey・evidence（file:line形式）の空欄率が
#      30%を超えれば違反。
#   3. 孤児参照検査: evidenceのファイル部分がtarget_file_pathsの集合に含まれない項目が
#      1件でもあれば違反。
#
# 分類別の抽出粒度・再計数パターンの定義は本スキル同梱 references/profile-screen.md を正本とする。
# facts.ymlのスキーマ（構造・必須フィールド・孤児参照の定義・normalize規則）は
# shared/references/facts-schema.md を正本とする。
#
# 設計判断（ADR）の正本は本スキルの SKILL.md「## 設計判断」に記載する。
# 保守責任者: 人手（ユーザー）。再計数パターン・閾値を変更した時に更新する。
# macOS bash 3.2 互換（mapfile 不使用）。ugrep/BSD grep 両対応のため \b は使わない。

DEVIATION_THRESHOLD_NUM=5
DEVIATION_THRESHOLD_DEN=100
BLANK_RATE_THRESHOLD_NUM=30
BLANK_RATE_THRESHOLD_DEN=100
SECTIONS="import export_type const state handler jsx style api"
ALL_SECTIONS="import export_type const state handler jsx style api measurement_pending"

# ---- コード側の分類別独立再計数（facts.yml を読まない） ----
#
# 全カウント関数は「連結済み対象ファイルの実体パス」を引数に取る（パイプ経由のstdinは使わない）。
# grep実装（ugrep/BSD grep/GNU grep）によってはstdinストリームと通常ファイルとで
# 正規表現マッチングの挙動が異なる場合があるため、常に実ファイルを渡して再現性を担保する。

count_import() {
  awk '
    /^import[ \t]/ {
      line=$0
      sub(/^import[ \t]+/, "", line)
      if (line !~ /from/) { count++; next }
      sub(/from.*/, "", line)
      gsub(/type[ \t]+/, "", line)
      gsub(/[{}]/, "", line)
      gsub(/\*[ \t]+as[ \t]+/, "", line)
      n = split(line, arr, ",")
      for (i=1;i<=n;i++) {
        tok = arr[i]
        gsub(/^[ \t]+|[ \t]+$/, "", tok)
        if (tok != "") count++
      }
    }
    END { print count+0 }
  ' "$1"
}

count_export_type() {
  awk '
    /^export[ \t]/ { count++ }
    /^(export[ \t]+)?(interface|type)[ \t]+[A-Za-z_][A-Za-z0-9_]*.*\{[ \t]*$/ { intype=1; next }
    intype && /^[ \t]*\}[ \t]*;?[ \t]*$/ { intype=0; next }
    intype && /^[ \t]*[A-Za-z_][A-Za-z0-9_]*\??:[ \t]*[^ \t]/ { count++ }
    END { print count+0 }
  ' "$1"
}

count_const() {
  awk '
    /^(export[ \t]+)?const[ \t]+[A-Za-z_][A-Za-z0-9_]*/ {
      if ($0 ~ /=[ \t]*styled\./) next
      if ($0 ~ /use(State|Reducer|Ref)\(/) next
      count++
    }
    END { print count+0 }
  ' "$1"
}

# useState/useReducer/useRef の直接呼出しは1呼出し=1件。それ以外の `use<大文字>...` 形の
# カスタムフック（store参照フック等）への分割代入は、分割代入された識別子ごとに1件を数える
# （import のシンボル単位カウントと同じ考え方）。多くの店舗参照フックは
# `const { a, b, c } = useFoo();` の形で複数の状態を1回で公開するため、呼出し単位で数えると
# 実在する状態変数が code_count に現れず構造的に検知できなくなる。
count_state() {
  awk '
    function process(   hookmatch, hookname, inner, posb, posk, posmin, i, c, lastclose, n, tok, cnt, arr) {
      if (!match(buf, /=[ \t]*use[A-Za-z0-9_]*\(/)) { return }
      hookmatch = substr(buf, RSTART, RLENGTH)
      hookname = hookmatch
      sub(/^=[ \t]*/, "", hookname)
      sub(/\($/, "", hookname)
      if (hookname == "useState" || hookname == "useReducer" || hookname == "useRef") {
        directcount++
        return
      }
      if (hookname !~ /^use[A-Z]/) { return }
      inner = substr(buf, 1, RSTART - 1)
      posb = index(inner, "{")
      posk = index(inner, "[")
      if (posb == 0 && posk == 0) { return }
      if (posb == 0) { posmin = posk } else if (posk == 0) { posmin = posb } else { posmin = (posb < posk ? posb : posk) }
      inner = substr(inner, posmin + 1)
      lastclose = 0
      for (i = length(inner); i >= 1; i--) {
        c = substr(inner, i, 1)
        if (c == "}" || c == "]") { lastclose = i; break }
      }
      if (lastclose > 0) { inner = substr(inner, 1, lastclose - 1) }
      gsub(/\n/, " ", inner)
      n = split(inner, arr, ",")
      cnt = 0
      for (i = 1; i <= n; i++) {
        tok = arr[i]
        sub(/:.*/, "", tok)
        sub(/=.*/, "", tok)
        gsub(/^[ \t]+|[ \t]+$/, "", tok)
        if (tok ~ /^[A-Za-z_][A-Za-z0-9_]*$/) { cnt++ }
      }
      statecount += cnt
    }
    {
      line = $0
      if (indestr == 0) {
        if (match(line, /(^|[^A-Za-z0-9_])(useState|useReducer|useRef)(<[^>]*>)?\(/)) { directcount++ }
        if (line !~ /(useState|useReducer|useRef)(<[^>]*>)?\(/ && match(line, /^[ \t]*(export[ \t]+)?const[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*use[A-Z][A-Za-z0-9_]*\(/)) {
          statecount++
          next
        }
        rest = line
        sub(/^[ \t]*(export[ \t]+)?const[ \t]+/, "", rest)
        firstchar = substr(rest, 1, 1)
        if ((firstchar == "{" || firstchar == "[") && line !~ /(useState|useReducer|useRef)(<[^>]*>)?\(/) {
          indestr = 1
          buf = line
          buflines = 1
          if (match(buf, /=[ \t]*use[A-Za-z0-9_]*\(/)) {
            process()
            indestr = 0; buf = ""; buflines = 0
          }
        }
        next
      } else {
        buf = buf "\n" line
        buflines++
        if (match(line, /=[ \t]*use[A-Za-z0-9_]*\(/) || buflines > 40) {
          process()
          indestr = 0; buf = ""; buflines = 0
        }
        next
      }
    }
    END { print (directcount + statecount) + 0 }
  ' "$1"
}

count_handler() {
  { grep -oE '(^|[^A-Za-z0-9_])on[A-Z][A-Za-z0-9]*=\{' "$1" | wc -l | tr -d ' '; } || true
}

# JSX開始タグは属性を複数行に折り返すと `<Header` の直後が改行になり、従来の
# 「タグ名直後に同一行内で空白/スラッシュ/> が続く」条件に一致しなくなる。行末（$）も
# 終端条件に加えることで、属性が次行以降に続く開始タグを検知対象に含める。
count_jsx() {
  { grep -oE '<[A-Z][A-Za-z0-9]*([[:blank:]/>]|$)' "$1" | sed -E 's/^<//; s/[[:blank:]\/>]$//' | sort -u | wc -l | tr -d ' '; } || true
}

count_style() {
  { grep -cE '=[ \t]*styled\.' "$1" || true; }
}

# await を伴わない Promise チェーン形式（`api.foo(...).then(...).catch(...)`）のAPI呼出しは
# 従来の `await <識別子>(` パターンでは構造的に検知できない（await自体が存在しないため）。
# `.then(` の出現数を1呼出しの起点とみなして加算する（`.catch`/`.finally` は継続部のため数えない）。
count_api() {
  awaitn="$( { grep -oE '(^|[^A-Za-z0-9_])await[[:blank:]]+[A-Za-z_][A-Za-z0-9_.]*\(' "$1" | wc -l | tr -d ' '; } || true )"
  thenn="$( { grep -oE '\.then[[:blank:]]*\(' "$1" | wc -l | tr -d ' '; } || true )"
  echo $((awaitn + thenn))
}

# 対象ファイル群を連結して一時ファイルへ書き出し、そのパスを標準出力へ返す。
# 呼び出し側が使用後に rm すること。
build_content_file() {
  repo="$1"
  shift
  tmpfile="$(mktemp "${TMPDIR:-/tmp}/recount-facts-content.XXXXXX")"
  for f in "$@"; do
    cat "$repo/$f" >> "$tmpfile"
    echo >> "$tmpfile"
  done
  printf '%s' "$tmpfile"
}

# コード側の分類別件数を「<セクション> <件数>」の形式で全8行出力する。
recount_from_code() {
  repo="$1"
  shift
  contentfile="$(build_content_file "$repo" "$@")"
  trap 'rm -f "$contentfile"' RETURN
  printf '%s %s\n' import "$(count_import "$contentfile")"
  printf '%s %s\n' export_type "$(count_export_type "$contentfile")"
  printf '%s %s\n' const "$(count_const "$contentfile")"
  printf '%s %s\n' state "$(count_state "$contentfile")"
  printf '%s %s\n' handler "$(count_handler "$contentfile")"
  printf '%s %s\n' jsx "$(count_jsx "$contentfile")"
  printf '%s %s\n' style "$(count_style "$contentfile")"
  printf '%s %s\n' api "$(count_api "$contentfile")"
}

# ---- facts.yml 側の解析 ----

# facts.yml の各セクションの記載件数を「<セクション> <件数>」の形式で出力する。
declared_counts() {
  awk '
    /^sections:/ { in_sections=1; next }
    in_sections && /^  [A-Za-z_]+:[ \t]*$/ {
      sec=$0
      sub(/^  /, "", sec)
      sub(/:[ \t]*$/, "", sec)
      cursec=sec
      next
    }
    in_sections && /^      - key:/ {
      counts[cursec]++
    }
    END {
      for (s in counts) print s, counts[s]
    }
  ' "$1"
}

get_declared_count() {
  facts="$1"
  section="$2"
  declared_counts "$facts" | awk -v s="$section" '$1==s{print $2; found=1} END{if(!found) print 0}'
}

# 全セクションの各項目について key/evidence の欠損有無を判定し「空欄数 総フィールド数」を出力する。
blank_field_stats() {
  awk '
    /^sections:/ { in_sections=1; next }
    in_sections && /^  [A-Za-z_]+:[ \t]*$/ { next }
    in_sections && /^      - key:[ \t]*(.*)$/ {
      if (havekey) { emit() }
      key=$0
      sub(/^      - key:[ \t]*/, "", key)
      gsub(/^"|"$/, "", key)
      value=""
      evidence=""
      havekey=1
      next
    }
    in_sections && /^        evidence:[ \t]*(.*)$/ {
      evidence=$0
      sub(/^        evidence:[ \t]*/, "", evidence)
      gsub(/^"|"$/, "", evidence)
      next
    }
    in_sections && /^        value:[ \t]*(.*)$/ { next }
    function emit() {
      total += 2
      if (key == "") blank++
      if (evidence !~ /^[^ \t:]+:[0-9]+$/) blank++
      havekey=0
    }
    END {
      if (havekey) emit()
      print blank+0, total+0
    }
  ' "$1"
}

# 孤児参照（evidenceのファイル部分がtarget_file_pathsに含まれない項目）の一覧を出力する。
orphan_refs() {
  facts="$1"
  shift
  targets_re="$(printf '%s\n' "$@" | awk 'BEGIN{ORS="|"} {gsub(/[.[\]^$*+?(){}|\\]/,"\\\\&"); print}' | sed -E 's/\|$//')"
  awk -v key_ok="^($targets_re):[0-9]+\$" '
    /^sections:/ { in_sections=1; next }
    in_sections && /^      - key:[ \t]*(.*)$/ {
      key=$0
      sub(/^      - key:[ \t]*/, "", key)
      gsub(/^"|"$/, "", key)
      next
    }
    in_sections && /^        evidence:[ \t]*(.*)$/ {
      evidence=$0
      sub(/^        evidence:[ \t]*/, "", evidence)
      gsub(/^"|"$/, "", evidence)
      if (evidence != "" && evidence !~ key_ok) {
        print key ": " evidence
      }
      next
    }
  ' "$facts"
}

# ---- 突合本体 ----

run_check() {
  facts="$1"
  repo="$2"
  shift 2
  targets=("$@")
  violations=0

  echo "== 検査1: 分類別件数の乖離検査 =="
  recount_out="$(recount_from_code "$repo" "${targets[@]}")"
  while IFS=' ' read -r sec code_count; do
    [ -z "$sec" ] && continue
    dec_count="$(get_declared_count "$facts" "$sec")"
    max="$code_count"
    [ "$dec_count" -gt "$max" ] && max="$dec_count"
    [ "$max" -lt 1 ] && max=1
    diff=$((code_count - dec_count))
    [ "$diff" -lt 0 ] && diff=$((-diff))
    # 乖離率 diff/max > 0.05 を整数演算で判定: diff*100 > 5*max
    if [ "$((diff * DEVIATION_THRESHOLD_DEN))" -gt "$((DEVIATION_THRESHOLD_NUM * max))" ]; then
      echo "  乖離超過: ${sec}（再計数=${code_count} 記載=${dec_count}）" >&2
      violations=$((violations + 1))
    else
      echo "  OK: ${sec}（再計数=${code_count} 記載=${dec_count}）"
    fi
  done <<EOF
$recount_out
EOF

  echo "== 検査2: 必須フィールド空欄検査 =="
  blank_total=0
  field_total=0
  for sec in $ALL_SECTIONS; do
    stats="$(awk -v target_sec="$sec" '
      /^sections:/ { in_sections=1; next }
      in_sections && /^  [A-Za-z_]+:[ \t]*$/ {
        sec=$0
        sub(/^  /, "", sec)
        sub(/:[ \t]*$/, "", sec)
        cursec=sec
        next
      }
      cursec != target_sec { next }
      /^      - key:[ \t]*(.*)$/ {
        if (havekey) { total+=2; if (key=="") blank++; if (evidence !~ /^[^ \t:]+:[0-9]+$/) blank++ }
        key=$0
        sub(/^      - key:[ \t]*/, "", key)
        gsub(/^"|"$/, "", key)
        evidence=""
        havekey=1
        next
      }
      /^        evidence:[ \t]*(.*)$/ {
        evidence=$0
        sub(/^        evidence:[ \t]*/, "", evidence)
        gsub(/^"|"$/, "", evidence)
        next
      }
      END {
        if (havekey) { total+=2; if (key=="") blank++; if (evidence !~ /^[^ \t:]+:[0-9]+$/) blank++ }
        print blank+0, total+0
      }
    ' "$facts")"
    b="$(printf '%s' "$stats" | awk '{print $1}')"
    t="$(printf '%s' "$stats" | awk '{print $2}')"
    blank_total=$((blank_total + b))
    field_total=$((field_total + t))
  done
  if [ "$field_total" -eq 0 ]; then
    echo "  対象フィールドが0件（facts.ymlに項目が1件も無い）" >&2
    violations=$((violations + 1))
  else
    if [ "$((blank_total * BLANK_RATE_THRESHOLD_DEN))" -gt "$((BLANK_RATE_THRESHOLD_NUM * field_total))" ]; then
      echo "  空欄率超過: ${blank_total}/${field_total} 件が空欄" >&2
      violations=$((violations + 1))
    else
      echo "  OK: 空欄 ${blank_total}/${field_total} 件"
    fi
  fi

  echo "== 検査3: 孤児参照検査 =="
  orphans="$(orphan_refs "$facts" "${targets[@]}")"
  orphan_count=0
  if [ -n "$orphans" ]; then
    orphan_count="$(printf '%s\n' "$orphans" | grep -c . || true)"
    echo "  孤児参照検出:" >&2
    printf '%s\n' "$orphans" | sed 's/^/    /' >&2
    violations=$((violations + 1))
  else
    echo "  OK: 孤児参照0件"
  fi

  if [ "$violations" -gt 0 ]; then
    echo "再計数ゲート失敗: ${violations} 検査で違反を検出しました" >&2
    return 1
  fi
  echo "再計数ゲート通過: 全3検査PASS"
  return 0
}

# ---- 自己テスト ----

self_test() {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/recount-facts-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  repo="$tmp/repo/src/screens/Foo"
  mkdir -p "$repo"
  cat > "$repo/Foo.tsx" <<'TSX'
import React, { useState } from 'react';
import styled from 'styled-components';

export const MAX_ROWS = 100;

export interface FooRow {
  id: string;
  amount: number;
}

export function Foo() {
  const [rows, setRows] = useState<FooRow[]>([]);

  const handleRowClick = () => {};

  return (
    <Wrapper>
      <Table onClick={handleRowClick}>
        <Row />
      </Table>
    </Wrapper>
  );
}

const Wrapper = styled.div`
  padding: 16px;
`;
TSX

  # 期待値: import=3(React,useState,styled) export_type=4(export const, export interface, id, amount, export function=5と数えると齟齬が出るため下のfacts.ymlは実測に合わせて記載する)
  # ここでは自己テストの目的上、まずrecount_from_codeの実測値を確定させてからfacts.ymlを組み立てる。
  actual="$(recount_from_code "$tmp/repo" "src/screens/Foo/Foo.tsx")"

  get_actual() {
    printf '%s\n' "$actual" | awk -v s="$1" '$1==s{print $2}'
  }

  # 陽性フィクスチャ: 各分類の記載件数を実測値に厳密一致させる（乖離0）。
  build_pass_facts() {
    out="$1"
    {
      echo "run_id: extract-1"
      echo "profile: screen"
      echo "target_repo_path: $tmp/repo"
      echo "target_file_paths:"
      echo "  - src/screens/Foo/Foo.tsx"
      echo "sections:"
      echo "  import:"
      echo "    reason: \"\""
      echo "    items:"
      n="$(get_actual import)"
      i=0
      while [ "$i" -lt "$n" ]; do
        echo "      - key: import-dummy-$i"
        echo "        value: \"dummy\""
        echo "        evidence: \"src/screens/Foo/Foo.tsx:1\""
        i=$((i + 1))
      done
      for sec in export_type const state handler jsx style api; do
        echo "  $sec:"
        echo "    reason: \"\""
        echo "    items:"
        n="$(get_actual "$sec")"
        i=0
        while [ "$i" -lt "$n" ]; do
          echo "      - key: ${sec}-dummy-$i"
          echo "        value: \"dummy\""
          echo "        evidence: \"src/screens/Foo/Foo.tsx:1\""
          i=$((i + 1))
        done
      done
      echo "  measurement_pending:"
      echo "    reason: \"\""
      echo "    items:"
      echo "      - key: 初期表示-件数"
      echo "        evidence: \"src/screens/Foo/Foo.tsx:12\""
    } > "$out"
  }

  rc=0

  pos="$tmp/pos-facts.yml"
  build_pass_facts "$pos"
  if run_check "$pos" "$tmp/repo" "src/screens/Foo/Foo.tsx" >/dev/null 2>&1; then
    echo "  [PASS] 陽性: 全分類が実測値と一致しゲート通過"
  else
    echo "  [FAIL] 陽性: 実測値と一致しているのにゲート失敗した" >&2
    rc=1
  fi

  # 陰性1: 乖離超過（importの記載件数を実測から大きくずらす）
  dev="$tmp/dev-facts.yml"
  build_pass_facts "$dev"
  awk '
    BEGIN{done=0}
    /^  import:$/{print; getline; print; print "    items:"; print "      - key: import-only-one"; print "        value: \"dummy\""; print "        evidence: \"src/screens/Foo/Foo.tsx:1\""; skip=1; next}
    skip==1 && /^  export_type:$/{skip=0}
    skip==1{next}
    {print}
  ' "$dev" > "$dev.tmp" && mv "$dev.tmp" "$dev"
  if run_check "$dev" "$tmp/repo" "src/screens/Foo/Foo.tsx" >/dev/null 2>&1; then
    echo "  [FAIL] 陰性1: 乖離超過があるのにゲート通過した" >&2
    rc=1
  else
    echo "  [PASS] 陰性1: 乖離超過でゲート失敗"
  fi

  # 陰性2: 空欄超過（evidenceを大量に空にする）
  blank="$tmp/blank-facts.yml"
  build_pass_facts "$blank"
  sed -E 's/evidence: "src\/screens\/Foo\/Foo\.tsx:1"/evidence: ""/g' "$blank" > "$blank.tmp" && mv "$blank.tmp" "$blank"
  if run_check "$blank" "$tmp/repo" "src/screens/Foo/Foo.tsx" >/dev/null 2>&1; then
    echo "  [FAIL] 陰性2: 空欄超過があるのにゲート通過した" >&2
    rc=1
  else
    echo "  [PASS] 陰性2: 空欄超過でゲート失敗"
  fi

  # 陰性3: 孤児参照（target_file_paths外のファイルをevidenceに記載）
  orphan="$tmp/orphan-facts.yml"
  build_pass_facts "$orphan"
  awk '
    /evidence: "src\/screens\/Foo\/Foo\.tsx:1"/ && !done {
      sub(/Foo\/Foo\.tsx:1/, "Foo/Unknown.tsx:1")
      done = 1
    }
    { print }
  ' "$orphan" > "$orphan.tmp" && mv "$orphan.tmp" "$orphan"
  if run_check "$orphan" "$tmp/repo" "src/screens/Foo/Foo.tsx" >/dev/null 2>&1; then
    echo "  [FAIL] 陰性3: 孤児参照があるのにゲート通過した" >&2
    rc=1
  else
    echo "  [PASS] 陰性3: 孤児参照でゲート失敗"
  fi

  # 追加陽性: recount-facts.shが構造的に検知できていなかった実在構文（Promiseチェーン形式の
  # API呼出し・複数行に折り返したJSX開始タグ・カスタムフックの分割代入による状態変数）を
  # 単体パターンで直接検知できることを確認する（数値の自己整合性ではなく実測値そのものを検証する）。

  promise_file="$tmp/promise-chain.txt"
  cat > "$promise_file" <<'EOF'
  api.battles.list({ season }).then((res) => {
    setBattles(res.data);
  }).catch((err) => {
    console.error(err);
  }).finally(() => {
    setLoading(false);
  });
EOF
  api_count="$(count_api "$promise_file")"
  if [ "$api_count" = "1" ]; then
    echo "  [PASS] 追加陽性: Promiseチェーン形式のAPI呼出しを検知（.then基準で1件）"
  else
    echo "  [FAIL] 追加陽性: Promiseチェーン形式のAPI呼出しを検知できない（実測=${api_count} 期待=1）" >&2
    rc=1
  fi

  jsx_file="$tmp/multiline-jsx.txt"
  cat > "$jsx_file" <<'EOF'
    <Header
      title="Foo"
      onBack={handleBack}
    >
      <Content />
    </Header>
EOF
  jsx_count="$(count_jsx "$jsx_file")"
  if [ "$jsx_count" = "2" ]; then
    echo "  [PASS] 追加陽性: 複数行に折り返したJSX開始タグを検知（Header/Contentの2件）"
  else
    echo "  [FAIL] 追加陽性: 複数行JSX開始タグを検知できない（実測=${jsx_count} 期待=2）" >&2
    rc=1
  fi

  hook_file="$tmp/hook-destructure.txt"
  cat > "$hook_file" <<'EOF'
  const {
    season,
    setSeason,
    seasons,
    isLoading,
    error,
    refetch,
  } = useCurrentSeason('first');
EOF
  hook_count="$(count_state "$hook_file")"
  if [ "$hook_count" = "6" ]; then
    echo "  [PASS] 追加陽性: カスタムフックの分割代入による状態変数を検知（6件）"
  else
    echo "  [FAIL] 追加陽性: カスタムフックの分割代入を検知できない（実測=${hook_count} 期待=6）" >&2
    rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

facts="${1:?使い方: recount-facts.sh <facts.yml> <target_repo_path> <target_file相対パス...>}"
repo="${2:?使い方: recount-facts.sh <facts.yml> <target_repo_path> <target_file相対パス...>}"
shift 2 || true
if [ "$#" -lt 1 ]; then
  echo "エラー: target_file相対パスを1つ以上指定してください" >&2
  exit 2
fi
if [ ! -f "$facts" ]; then
  echo "エラー: facts.yml が見つかりません: $facts" >&2
  exit 2
fi
if [ ! -d "$repo" ]; then
  echo "エラー: target_repo_path が見つかりません: $repo" >&2
  exit 2
fi
for f in "$@"; do
  if [ ! -f "$repo/$f" ]; then
    echo "エラー: 対象ファイルが見つかりません: $repo/$f" >&2
    exit 2
  fi
done

run_check "$facts" "$repo" "$@"
