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

# named import のシンボル計数規則（from以降除去→type除去→{}除去→* as除去→
# カンマ分割・空トークン除外）をawk関数に抽出し、単一行経路・複数行継続経路の
# 両方から共用する。複数行にまたがる named import（`import {` 開始行から
# `from` を含む終端行まで）はinmulti状態で継続行を連結してから一括計数する。
count_import() {
  awk '
    function count_symbols(line,    n, arr, i, tok, cnt) {
      sub(/from.*/, "", line)
      gsub(/type[ \t]+/, "", line)
      gsub(/[{}]/, "", line)
      gsub(/\*[ \t]+as[ \t]+/, "", line)
      n = split(line, arr, ",")
      cnt = 0
      for (i=1;i<=n;i++) {
        tok = arr[i]
        gsub(/^[ \t]+|[ \t]+$/, "", tok)
        if (tok != "") cnt++
      }
      return cnt
    }
    {
      if (inmulti) {
        buf = buf " " $0
        buflines++
        if ($0 ~ /from/) {
          count += count_symbols(buf)
          inmulti=0; buf=""; buflines=0
        } else if (buflines > 40) {
          count++
          inmulti=0; buf=""; buflines=0
        }
        next
      }
      if ($0 ~ /^import[ \t]/) {
        line=$0
        sub(/^import[ \t]+/, "", line)
        if (line !~ /from/) {
          if (line ~ /\{/ && line !~ /\}/) {
            inmulti=1; buf=line; buflines=1
            next
          }
          count++; next
        }
        count += count_symbols(line)
        next
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

# 値がオブジェクトリテラル（`{...}`または`as const`オブジェクト）の場合は宣言行1件ではなく、
# 最上位1階層（ブレース深度1）のフィールド行を1件ずつ数える（profile-screen.md③定数の分解規則）。
# 空オブジェクト・分解不能な場合は宣言1件にフォールバックする。値がスカラーの場合は従来どおり
# 宣言行を1件として数える。
count_const() {
  awk '
    # rest（= の右辺として抽出済みのオブジェクトリテラル開始文字列）が同一行内で
    # 閉じている場合（単一行オブジェクト定数）はgetlineせず、その場でカンマ区切り
    # により最上位フィールド数を計算する。閉じていない場合は従来どおりgetlineで
    # 継続行を読み進める。
    function count_object_fields(rest,   depth, line, opens, closes, fieldcount, body, n, arr, i, tok) {
      opens = gsub(/\{/, "{", rest)
      closes = gsub(/\}/, "}", rest)
      if (opens > 0 && opens == closes) {
        body = rest
        sub(/^[^{]*\{/, "", body)
        sub(/\}[^}]*$/, "", body)
        if (body ~ /^[ \t]*$/) { return 0 }
        n = split(body, arr, ",")
        fieldcount = 0
        for (i = 1; i <= n; i++) {
          tok = arr[i]
          gsub(/^[ \t]+|[ \t]+$/, "", tok)
          if (tok ~ /^["'"'"'`]?[A-Za-z_$][A-Za-z0-9_$]*["'"'"'`]?[ \t]*:/) fieldcount++
        }
        return fieldcount
      }
      depth = opens - closes
      fieldcount = 0
      while ((getline line) > 0) {
        if (depth == 1 && line ~ /^[ \t]*["'"'"'`]?[A-Za-z_$][A-Za-z0-9_$]*["'"'"'`]?[ \t]*:[ \t]*[^ \t]/) {
          fieldcount++
        }
        opens = gsub(/\{/, "{", line)
        closes = gsub(/\}/, "}", line)
        depth += opens - closes
        if (depth <= 0) break
      }
      return fieldcount
    }
    /^(export[ \t]+)?const[ \t]+[A-Za-z_][A-Za-z0-9_]*/ {
      if ($0 ~ /=[ \t]*styled\./) next
      if ($0 ~ /use(State|Reducer|Ref)\(/) next
      line = $0
      # 型注釈がオブジェクト型で複数行にまたがる宣言（`const X: {...} = {...}`で
      # 型注釈部分の"{"が改行を挟む場合）は、同一行に"="が現れるまで継続行を
      # 連結してから型注釈部分をスキップし、値部分の"{"を取り出す。
      contlines = 0
      while (line !~ /=/ && contlines < 40) {
        if ((getline nextline) <= 0) break
        line = line " " nextline
        contlines++
      }
      rest = line
      sub(/^(export[ \t]+)?const[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*(:[^=]*)?=[ \t]*/, "", rest)
      gsub(/^[ \t]+/, "", rest)
      if (rest ~ /^\{/) {
        n = count_object_fields(rest)
        if (n > 0) { count += n } else { count += 1 }
      } else {
        count++
      }
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
    # 分割代入パターンの括弧深度を計算する（gsubは渡された局所変数sのみを書き換え、
    # 呼び出し元のlineには影響しない）。開き"{"/"["と閉じ"}"/"]"の差分を返す。
    function count_brace_depth(s,   o, c, t) {
      t = s
      o = gsub(/\{/, "{", t)
      o += gsub(/\[/, "[", t)
      t = s
      c = gsub(/\}/, "}", t)
      c += gsub(/\]/, "]", t)
      return o - c
    }
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
      # `useParams<{ id: string }>()` のようなジェネリック型注釈は、注釈内の
      # `{`/`}` が分割代入の終端探索（process()の末尾"}"/"]"逆走査）を狂わせ、
      # かつ `=[ \t]*use...\(` パターンの直後に"("が来ないため呼出し自体を
      # 検知できなくする。フック呼出し直前の `<...>` 注釈は呼出し検知に無関係
      # なので、`(` に隣接する `<...>` を先に潰してから以降の判定に使う。
      gsub(/<[^>]*>\(/, "(", line)
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
          destr_depth = count_brace_depth(line)
          if (match(buf, /=[ \t]*use[A-Za-z0-9_]*\(/)) {
            process()
            indestr = 0; buf = ""; buflines = 0; destr_depth = 0
          } else if (destr_depth <= 0) {
            # 文の完結判定: 分割代入パターンが同一行内で閉じ、かつ代入先がフック
            # 呼出しでないと確定した（=単一行の非フック分割代入）。後続の無関係な
            # 行のフック呼出しに誤って巻き込まれないよう直ちにバッファを破棄する。
            indestr = 0; buf = ""; buflines = 0; destr_depth = 0
          }
        }
        next
      } else {
        buf = buf "\n" line
        buflines++
        destr_depth += count_brace_depth(line)
        if (match(line, /=[ \t]*use[A-Za-z0-9_]*\(/)) {
          process()
          indestr = 0; buf = ""; buflines = 0; destr_depth = 0
        } else if (destr_depth <= 0) {
          # 文の完結判定: 分割代入パターンの閉じ括弧まで到達済み（深度0以下）で、
          # かつ代入先がフック呼出しでないと確定した時点で、後続の無関係な行の
          # フック呼出しに誤って巻き込まれないよう直ちにバッファを破棄する
          # （旧実装は次にuse...(を含む行が現れるまで無条件に連結し続け、
          # 無関係な後続statementのフック呼出しを誤って合算していた）。
          indestr = 0; buf = ""; buflines = 0; destr_depth = 0
        } else if (buflines > 40) {
          process()
          indestr = 0; buf = ""; buflines = 0; destr_depth = 0
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
# 対象文字クラスは `[A-Za-z]` とし、ネイティブHTMLタグ（`<div>`等の小文字始まり）も
# PascalCaseコンポーネントと同様にカウント対象へ含める。
# ユニークタグ数に加え、早期return・三項演算子・`&&`短絡評価による複数レンダリングパスの
# 分岐数を加算する（`count_api`がawaitと.thenを合算する既存方式を踏襲）。
count_jsx() {
  tag_count="$(grep -oE '<[A-Za-z][A-Za-z0-9]*([[:blank:]/>]|$)' "$1" | sed -E 's/^<//; s/[[:blank:]\/>]$//' | sort -u | wc -l | tr -d ' ')"

  return_jsx_count="$( { grep -cE '(^|[^A-Za-z0-9_])return[ \t]*(\(|<[A-Za-z])' "$1" || true; } )"
  extra_return_branches=0
  if [ "$return_jsx_count" -gt 1 ]; then
    extra_return_branches=$((return_jsx_count - 1))
  fi

  ternary_count="$( { grep -oE '[^.][ \t]*\?[ \t]*\(?[ \t]*<[A-Za-z]' "$1" | wc -l | tr -d ' '; } || true )"
  ternary_branches=$((ternary_count * 2))

  and_render_count="$( { grep -oE '&&[ \t]*\(?[ \t]*<[A-Za-z]' "$1" | wc -l | tr -d ' '; } || true )"

  total=$((tag_count + extra_return_branches + ternary_branches + and_render_count))
  printf '%s' "$total"
}

count_style() {
  { grep -cE '=[ \t]*styled\.' "$1" || true; }
}

# await を伴わない Promise チェーン形式（`api.foo(...).then(...).catch(...)`）のAPI呼出しは
# 従来の `await <識別子>(` パターンでは構造的に検知できない（await自体が存在しないため）。
# `.then(` の出現数を1呼出しの起点とみなして加算する（`.catch`/`.finally` は継続部のため数えない）。
# さらに await/.then のいずれも伴わない直接呼出し（代入形 `const x = obj.method(...)` /
# 文頭ステートメント形 `obj.method(...)`）はawait/.thenパターンでは構造的に検知できないため、
# count_api_directで別途計上し合算する（重複計上防止のためawait/.then該当行は対象外にする）。
count_api() {
  awaitn="$( { grep -oE '(^|[^A-Za-z0-9_])await[[:blank:]]+[A-Za-z_][A-Za-z0-9_.]*\(' "$1" | wc -l | tr -d ' '; } || true )"
  thenn="$( { grep -oE '\.then[[:blank:]]*\(' "$1" | wc -l | tr -d ' '; } || true )"
  directn="$(count_api_direct "$1")"
  echo $((awaitn + thenn + directn))
}

# 一般的な組込みオブジェクト（console/Math/JSON等）へのレシーバ、配列・文字列の
# 汎用メソッド（map/filter/replace等）への呼出しは業務ロジック呼出しではないため除外する
# （除外リストはプロジェクト固有値を含まない一般的な語彙のみ）。
#
# 直接呼出しは「呼出し形式（レシーバ経由のドット連結 / レシーバを介さない裸の関数呼出し）」
# ×「代入形式（単純識別子への代入 / 波括弧の分割代入）」の2軸4パターンを検知する。
# 裸の関数呼出しは、英字接頭辞+数字のモジュール名規約（例: bl1DoSomething・api2FetchX）を
# 持つ名前のみを業務ロジック呼出しとみなす。数字を含まない一般的な語彙（ユーティリティ関数・
# 制御構文・フック等）まで拾うと誤検知が広がるため対象外とし、フック呼出し（use大文字…）と
# TypedArrayコンストラクタは明示的に除外する。
count_api_direct() {
  awk '
    BEGIN {
      split("console Math JSON Object Array Date Number String Promise window document localStorage sessionStorage navigator e event", robj, " ")
      for (i in robj) receiver_excl[robj[i]] = 1
      split("map filter reduce forEach find some every includes indexOf slice splice join concat sort push pop shift unshift split replace trim toString toFixed toLowerCase toUpperCase keys values entries preventDefault stopPropagation catch finally", rmeth, " ")
      for (i in rmeth) method_excl[rmeth[i]] = 1
      split("Int8Array Uint8Array Int16Array Uint16Array Int32Array Uint32Array Float32Array Float64Array BigInt64Array BigUint64Array", barr, " ")
      for (i in barr) bare_excl[barr[i]] = 1
    }
    function check_chain(chain,   n, parts, receiver, method) {
      n = split(chain, parts, ".")
      if (n < 2) return 0
      receiver = parts[1]
      method = parts[n]
      if (receiver in receiver_excl) return 0
      if (method in method_excl) return 0
      return 1
    }
    function check_bare(name) {
      if (name ~ /^use[A-Z]/) return 0
      if (name in bare_excl) return 0
      if (name !~ /^[A-Za-z]+[0-9]+[A-Za-z0-9_]*$/) return 0
      return 1
    }
    {
      line = $0
      if (line ~ /\.then[ \t]*\(/) next
      if (line ~ /(^|[^A-Za-z0-9_])await([ \t]|$)/) next
      # 代入形（LHSは単純識別子または分割代入{...}のいずれも許容）× レシーバ経由チェーン呼出し
      if (match(line, /^[ \t]*(export[ \t]+)?(const|let|var)[ \t]+([A-Za-z_][A-Za-z0-9_]*|\{[^{}]*\})[ \t]*(:[^=]*)?=[ \t]*[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)+[ \t]*\(/)) {
        chain = substr(line, RSTART, RLENGTH)
        sub(/[ \t]*\($/, "", chain)
        sub(/^.*=[ \t]*/, "", chain)
        if (check_chain(chain)) count++
        next
      }
      # 代入形（LHSは単純識別子または分割代入{...}のいずれも許容）× レシーバを介さない裸の関数呼出し
      if (match(line, /^[ \t]*(export[ \t]+)?(const|let|var)[ \t]+([A-Za-z_][A-Za-z0-9_]*|\{[^{}]*\})[ \t]*(:[^=]*)?=[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*\(/)) {
        callee = substr(line, RSTART, RLENGTH)
        sub(/[ \t]*\($/, "", callee)
        sub(/^.*=[ \t]*/, "", callee)
        if (check_bare(callee)) count++
        next
      }
      # 文頭ステートメント形（代入なし）× レシーバ経由チェーン呼出し
      if (match(line, /^[ \t]*[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)+[ \t]*\(/)) {
        chain = substr(line, RSTART, RLENGTH)
        sub(/[ \t]*\($/, "", chain)
        gsub(/^[ \t]+/, "", chain)
        if (check_chain(chain)) count++
        next
      }
    }
    END { print count+0 }
  ' "$1"
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
  targets_re="$(printf '%s\n' "$@" | awk 'BEGIN{ORS="|"} {gsub(/[].[^$*+?(){}|\\]/,"\\\\&"); print}' | sed -E 's/\|$//')"
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
  api.records.list({ filter }).then((res) => {
    setRecords(res.data);
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
    filter,
    setFilter,
    filters,
    isLoading,
    error,
    refetch,
  } = useCurrentFilter('first');
EOF
  hook_count="$(count_state "$hook_file")"
  if [ "$hook_count" = "6" ]; then
    echo "  [PASS] 追加陽性: カスタムフックの分割代入による状態変数を検知（6件）"
  else
    echo "  [FAIL] 追加陽性: カスタムフックの分割代入を検知できない（実測=${hook_count} 期待=6）" >&2
    rc=1
  fi

  # 追加陽性: ジェネリック型注釈付きフック呼出しの分割代入（例 useParams<{ id: string }>()）は、
  # 注釈内の"{"/"}"が分割代入終端の逆走査を狂わせ、かつ"=...use...\("パターンが
  # 直後に"("を要求するため検知できなかった構造的盲点として発見された。
  generic_destructure_file="$tmp/generic-destructure.txt"
  cat > "$generic_destructure_file" <<'EOF'
  const { id } = useParams<{ id: string }>()
EOF
  generic_destructure_count="$(count_state "$generic_destructure_file")"
  if [ "$generic_destructure_count" = "1" ]; then
    echo "  [PASS] 追加陽性: ジェネリック型注釈付きフック呼出しの分割代入を検知（1件）"
  else
    echo "  [FAIL] 追加陽性: ジェネリック型注釈付きフック呼出しの分割代入を検知できない（実測=${generic_destructure_count} 期待=1）" >&2
    rc=1
  fi

  # 追加陽性: フック直接呼出しの単純代入（分割代入なし・型注釈なし。例 const location = useLocation()）
  # は、単独では既存パターンで検知できていたが、直前行がジェネリック型注釈付き分割代入だと
  # buf継続状態に巻き込まれ独立して数えられなくなっていた事例が確認された。
  # 実ファイルの隣接行を模した組合せで、両方が合算して数えられることを検証する。
  simple_hook_file="$tmp/simple-hook-assignment.txt"
  cat > "$simple_hook_file" <<'EOF'
  const { id } = useParams<{ id: string }>()
  const location = useLocation()
EOF
  simple_hook_count="$(count_state "$simple_hook_file")"
  if [ "$simple_hook_count" = "2" ]; then
    echo "  [PASS] 追加陽性: フック単純代入がジェネリック型注釈行に続いても独立して検知（合算2件）"
  else
    echo "  [FAIL] 追加陽性: フック単純代入が独立して検知できない（実測=${simple_hook_count} 期待=2）" >&2
    rc=1
  fi

  # 回帰確認: 分割代入バッファリングの文の完結判定。複数行に折り返した非フックの
  # 分割代入（`const { a, b } = someRegularObject;`）は、閉じ括弧到達時点で
  # フックでないと確定した時点で直ちにバッファを破棄しなければならない。旧実装は
  # 次に use...( を含む行が現れるまで無条件にバッファを連結し続け、無関係な後続
  # statement（`const location = useLocation()`）のフック呼出しを誤って合算していた
  # （期待1件のところ実測2件になる構造的欠陥）。
  nonhook_destructure_file="$tmp/nonhook-destructure.txt"
  cat > "$nonhook_destructure_file" <<'EOF'
const {
  a,
  b
} = someRegularObject;

const location = useLocation()
EOF
  nonhook_destructure_count="$(count_state "$nonhook_destructure_file")"
  if [ "$nonhook_destructure_count" = "1" ]; then
    echo "  [PASS] 回帰確認: 非フック分割代入の文の完結判定で後続フック呼出しとの誤合算を防止（1件）"
  else
    echo "  [FAIL] 回帰確認: 非フック分割代入が後続フック呼出しと誤って合算されている（実測=${nonhook_destructure_count} 期待=1）" >&2
    rc=1
  fi

  # 回帰確認: 単一行で完結する非フック分割代入（`const { a, b } = someRegularObject;`単独行）
  # も同様に、同一行内で深度0に到達した時点で直ちにバッファを破棄する。
  single_line_nonhook_file="$tmp/single-line-nonhook-destructure.txt"
  cat > "$single_line_nonhook_file" <<'EOF'
const { a, b } = someRegularObject;
const location = useLocation()
EOF
  single_line_nonhook_count="$(count_state "$single_line_nonhook_file")"
  if [ "$single_line_nonhook_count" = "1" ]; then
    echo "  [PASS] 回帰確認: 単一行の非フック分割代入でも後続フック呼出しとの誤合算を防止（1件）"
  else
    echo "  [FAIL] 回帰確認: 単一行の非フック分割代入が後続フック呼出しと誤って合算されている（実測=${single_line_nonhook_count} 期待=1）" >&2
    rc=1
  fi

  # 回帰確認: 分割代入パターン内部にデフォルト値の"="が含まれても（例 `a = 1,`）、
  # 括弧深度がまだ閉じていない（>0）間は文の完結と誤判定せず、正規のフック
  # 呼出し（useFoo()）まで正しくバッファを継続できる。
  default_value_destructure_file="$tmp/default-value-destructure.txt"
  cat > "$default_value_destructure_file" <<'EOF'
const {
  a = 1,
  b
} = useFoo();
EOF
  default_value_destructure_count="$(count_state "$default_value_destructure_file")"
  if [ "$default_value_destructure_count" = "2" ]; then
    echo "  [PASS] 回帰確認: パターン内部のデフォルト値=を文の完結と誤判定せずフック分割代入を検知（2件）"
  else
    echo "  [FAIL] 回帰確認: パターン内部のデフォルト値=でフック分割代入の検知が壊れている（実測=${default_value_destructure_count} 期待=2）" >&2
    rc=1
  fi

  # 追加陽性: オブジェクト定数のフィールド分解（profile-screen.md③定数の分解規則）。
  # 最上位2フィールドのオブジェクトリテラルは宣言行1件ではなくフィールド数（2）で数える。
  object_const_file="$tmp/object-const.txt"
  cat > "$object_const_file" <<'EOF'
const cardStyle = {
  height: "48px",
  fontSize: "14px",
};
EOF
  object_const_count="$(count_const "$object_const_file")"
  if [ "$object_const_count" = "2" ]; then
    echo "  [PASS] 追加陽性: オブジェクト定数のフィールド分解を検知（2件）"
  else
    echo "  [FAIL] 追加陽性: オブジェクト定数のフィールド分解を検知できない（実測=${object_const_count} 期待=2）" >&2
    rc=1
  fi

  # 追加陽性: ネストオブジェクト定数（最上位1階層のみ分解し、ネスト内部までは再帰しない）。
  # 最上位フィールドは header・footer の2件。headerの値がさらにオブジェクトでも内部は数えない。
  nested_const_file="$tmp/nested-const.txt"
  cat > "$nested_const_file" <<'EOF'
const layout = {
  header: { height: "48px", color: "#fff" },
  footer: "bottom",
};
EOF
  nested_const_count="$(count_const "$nested_const_file")"
  if [ "$nested_const_count" = "2" ]; then
    echo "  [PASS] 追加陽性: ネストオブジェクト定数を最上位1階層のみで分解（2件）"
  else
    echo "  [FAIL] 追加陽性: ネストオブジェクト定数の分解粒度が誤り（実測=${nested_const_count} 期待=2）" >&2
    rc=1
  fi

  # 回帰確認: スカラー定数は従来どおり宣言1件のまま数える。
  scalar_const_file="$tmp/scalar-const.txt"
  cat > "$scalar_const_file" <<'EOF'
const MAX_ROWS = 100;
EOF
  scalar_const_count="$(count_const "$scalar_const_file")"
  if [ "$scalar_const_count" = "1" ]; then
    echo "  [PASS] 回帰確認: スカラー定数は宣言1件のまま（1件）"
  else
    echo "  [FAIL] 回帰確認: スカラー定数の件数が変化した（実測=${scalar_const_count} 期待=1）" >&2
    rc=1
  fi

  # 追加陽性: 単一行で完結するオブジェクト定数（`const x = { a: 1, b: 2 };`）。
  # count_object_fields()がgetlineで次行を読み始めるため同一行内のフィールドを
  # 見落としていた構造的欠陥の回帰確認。最上位2フィールドを検知する。
  single_line_const_file="$tmp/single-line-const.txt"
  cat > "$single_line_const_file" <<'EOF'
const singleLineObj = { height: "48px", fontSize: "14px" };
EOF
  single_line_const_count="$(count_const "$single_line_const_file")"
  if [ "$single_line_const_count" = "2" ]; then
    echo "  [PASS] 追加陽性: 単一行オブジェクト定数のフィールド分解を検知（2件）"
  else
    echo "  [FAIL] 追加陽性: 単一行オブジェクト定数のフィールド分解を検知できない（実測=${single_line_const_count} 期待=2）" >&2
    rc=1
  fi

  # 追加陽性: 型注釈がオブジェクト型で複数行にまたがる宣言（`const X: {...} = {...}`）。
  # 型注釈部分の"{...}"をスキップし、値部分の"{...}"のフィールド（a・bの2件）を数える。
  typed_multiline_const_file="$tmp/typed-multiline-const.txt"
  cat > "$typed_multiline_const_file" <<'EOF'
const config: {
  a: string;
  b: number;
} = {
  a: "1",
  b: 2,
};
EOF
  typed_multiline_const_count="$(count_const "$typed_multiline_const_file")"
  if [ "$typed_multiline_const_count" = "2" ]; then
    echo "  [PASS] 追加陽性: 型注釈が複数行にまたがる宣言の値部分フィールドを検知（2件）"
  else
    echo "  [FAIL] 追加陽性: 型注釈が複数行にまたがる宣言の値部分フィールドを検知できない（実測=${typed_multiline_const_count} 期待=2）" >&2
    rc=1
  fi

  # 追加陽性: 小文字ネイティブHTMLタグ（<div>等）もPascalCaseコンポーネントと同様に検知する。
  lowercase_tag_file="$tmp/lowercase-tag.txt"
  cat > "$lowercase_tag_file" <<'EOF'
  return (
    <div>
      <Header />
    </div>
  );
EOF
  lowercase_tag_count="$(count_jsx "$lowercase_tag_file")"
  if [ "$lowercase_tag_count" = "2" ]; then
    echo "  [PASS] 追加陽性: 小文字ネイティブタグを検知（div/Headerの2件）"
  else
    echo "  [FAIL] 追加陽性: 小文字ネイティブタグを検知できない（実測=${lowercase_tag_count} 期待=2）" >&2
    rc=1
  fi

  # 追加陽性: 早期returnによる複数レンダリングパス。ユニークタグ数（div/Spinner/Card/Content=4）に
  # 複数return文の分岐数（2件のreturn文 → 追加1件）を加算する。
  early_return_file="$tmp/early-return.txt"
  cat > "$early_return_file" <<'EOF'
function Foo() {
  if (isLoading) {
    return (
      <div className="spinner">
        <Spinner />
      </div>
    );
  }

  return (
    <Card>
      <Content />
    </Card>
  );
}
EOF
  early_return_count="$(count_jsx "$early_return_file")"
  if [ "$early_return_count" = "5" ]; then
    echo "  [PASS] 追加陽性: 早期returnの複数レンダリングパスを検知（4タグ+分岐1=5件）"
  else
    echo "  [FAIL] 追加陽性: 早期returnの分岐を検知できない（実測=${early_return_count} 期待=5）" >&2
    rc=1
  fi

  # 追加陽性: 三項演算子による複数レンダリングパス。ユニークタグ数（Wrapper/Spinner/Content=3）に
  # 三項2アーム分（2件）を加算する。
  ternary_file="$tmp/ternary.txt"
  cat > "$ternary_file" <<'EOF'
function Foo() {
  return (
    <Wrapper>
      {isLoading ? (<Spinner />) : (<Content />)}
    </Wrapper>
  );
}
EOF
  ternary_count_result="$(count_jsx "$ternary_file")"
  if [ "$ternary_count_result" = "5" ]; then
    echo "  [PASS] 追加陽性: 三項演算子の複数レンダリングパスを検知（3タグ+2アーム=5件）"
  else
    echo "  [FAIL] 追加陽性: 三項演算子の分岐を検知できない（実測=${ternary_count_result} 期待=5）" >&2
    rc=1
  fi

  # 追加陽性: `&&`短絡評価による条件付きレンダリング。ユニークタグ数（Wrapper/ErrorBanner=2）に
  # 短絡評価分（1件）を加算する。
  and_render_file="$tmp/and-render.txt"
  cat > "$and_render_file" <<'EOF'
function Foo() {
  return (
    <Wrapper>
      {hasError && (<ErrorBanner />)}
    </Wrapper>
  );
}
EOF
  and_render_count_result="$(count_jsx "$and_render_file")"
  if [ "$and_render_count_result" = "3" ]; then
    echo "  [PASS] 追加陽性: &&短絡評価の条件付きレンダリングを検知（2タグ+1=3件）"
  else
    echo "  [FAIL] 追加陽性: &&短絡評価の条件付きレンダリングを検知できない（実測=${and_render_count_result} 期待=3）" >&2
    rc=1
  fi

  # 追加陽性: 複数行にまたがるnamed import（開き`{`〜`from`行終端）はシンボル単位で
  # 継続追跡して数える。default import(React) 2 + 単一行(useMemo) + 複数行3シンボル
  # (fetchUser/updateUser/type UserPayload) + 副作用import 1 = 合計6件。
  multiline_import_file="$tmp/multiline-import.txt"
  cat > "$multiline_import_file" <<'EOF'
import React, { useMemo } from 'react';
import {
  fetchUser,
  updateUser,
  type UserPayload,
} from './userService';
import './styles.css';
EOF
  multiline_import_count="$(count_import "$multiline_import_file")"
  if [ "$multiline_import_count" = "6" ]; then
    echo "  [PASS] 追加陽性: 複数行named importをシンボル単位で検知（6件）"
  else
    echo "  [FAIL] 追加陽性: 複数行named importを検知できない（実測=${multiline_import_count} 期待=6）" >&2
    rc=1
  fi

  # 追加陽性: await/.thenを伴わない直接呼出し（代入形・文頭形）。
  # 業務ロジック呼出し（userService.getProfile / analytics.track）を2件計上し、
  # 汎用メソッド（items.map）・フック（useState分割代入）は除外、await行は
  # awaitn側で計上済みのためdirect側では重複させない（合算期待値3=await1+direct2）。
  direct_api_file="$tmp/direct-api.txt"
  cat > "$direct_api_file" <<'EOF'
const profile = userService.getProfile();
const rows = items.map((r) => r.id);
const [open, setOpen] = useState(false);
analytics.track('view');
const data = await api.fetch();
EOF
  direct_api_count="$(count_api "$direct_api_file")"
  if [ "$direct_api_count" = "3" ]; then
    echo "  [PASS] 追加陽性: await/.thenを伴わない直接API呼出しを検知（await1+direct2=3件）"
  else
    echo "  [FAIL] 追加陽性: await/.thenを伴わない直接API呼出しを検知できない（実測=${direct_api_count} 期待=3）" >&2
    rc=1
  fi

  # 追加陽性: 直接呼出し4パターン（呼出し形式×代入形式）を個別ケースで検証する。
  # いずれか1パターンでも検知が壊れれば当該ケースのみFAILし、合計件数の帳尻合わせでは
  # 隠れないようにする。

  bare_simple_file="$tmp/direct-bare-simple.txt"
  cat > "$bare_simple_file" <<'EOF'
const profile = svc1FetchProfile();
EOF
  bare_simple_count="$(count_api_direct "$bare_simple_file")"
  if [ "$bare_simple_count" = "1" ]; then
    echo "  [PASS] 直接呼出しパターン: 裸の関数呼出し×単純代入を検知（1件）"
  else
    echo "  [FAIL] 直接呼出しパターン: 裸の関数呼出し×単純代入を検知できない（実測=${bare_simple_count} 期待=1）" >&2
    rc=1
  fi

  bare_destructure_file="$tmp/direct-bare-destructure.txt"
  cat > "$bare_destructure_file" <<'EOF'
const { data, error } = svc2LoadItems();
EOF
  bare_destructure_count="$(count_api_direct "$bare_destructure_file")"
  if [ "$bare_destructure_count" = "1" ]; then
    echo "  [PASS] 直接呼出しパターン: 裸の関数呼出し×分割代入を検知（1件）"
  else
    echo "  [FAIL] 直接呼出しパターン: 裸の関数呼出し×分割代入を検知できない（実測=${bare_destructure_count} 期待=1）" >&2
    rc=1
  fi

  receiver_simple_file="$tmp/direct-receiver-simple.txt"
  cat > "$receiver_simple_file" <<'EOF'
const profile = userService.getProfile();
EOF
  receiver_simple_count="$(count_api_direct "$receiver_simple_file")"
  if [ "$receiver_simple_count" = "1" ]; then
    echo "  [PASS] 直接呼出しパターン: レシーバ経由呼出し×単純代入を検知（1件）"
  else
    echo "  [FAIL] 直接呼出しパターン: レシーバ経由呼出し×単純代入を検知できない（実測=${receiver_simple_count} 期待=1）" >&2
    rc=1
  fi

  receiver_destructure_file="$tmp/direct-receiver-destructure.txt"
  cat > "$receiver_destructure_file" <<'EOF'
const { data, error } = userService.loadItems();
EOF
  receiver_destructure_count="$(count_api_direct "$receiver_destructure_file")"
  if [ "$receiver_destructure_count" = "1" ]; then
    echo "  [PASS] 直接呼出しパターン: レシーバ経由呼出し×分割代入を検知（1件）"
  else
    echo "  [FAIL] 直接呼出しパターン: レシーバ経由呼出し×分割代入を検知できない（実測=${receiver_destructure_count} 期待=1）" >&2
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
