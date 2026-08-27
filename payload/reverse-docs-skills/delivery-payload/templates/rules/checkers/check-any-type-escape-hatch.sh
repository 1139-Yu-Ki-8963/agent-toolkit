#!/usr/bin/env bash
# check-any-type-escape-hatch.sh — コードの書き方と分割の決まり linter
#
# timing: PreToolUse(Write)
# 対象規約: コードの書き方と分割の決まり（coding-style.md）
# 検査する規則（検査列に「静的解析」を含む規則すべて）:
#   - 型の検査を骨抜きにしない: 何でも受け付ける型の使用箇所を走査する
#   - 数値と文字列に名前を付ける: 意味を持つ数値の直接の記述を走査する
#   - 試したままのコードを残さない: 出力のための一時的な呼び出しと、
#     注釈で消したコードの塊を走査する
#   - 関数を1つの責務に絞る: 50 行を超えていないかを走査する（既定値。上書き値の
#     動的読み込みは未実装で、既定値を固定で使う）
#   - 入れ子を深くしない: 4 段を超えていないかを走査する（既定値。同上）
#   - 整形は道具へ任せる: 整形の設定ファイルが実在し、統合の検査に整形の
#     確認が登録されているかを走査する
#
# 判定:
#   書き込み内容から上記の各規則の違反を走査し、1件でも見つかれば
#   block（exit 2）する。違反メッセージには規則名を含める。
#
# 「整形は道具へ任せる」の判定:
#   cwd 配下（.git 配下を除く）をファイル名で走査し、整形の設定ファイルらしい
#   名前（.prettierrc* / .editorconfig / biome.json）を探す。見つからなければ
#   対象外（その設定ファイルがまだ無いだけかもしれないため、素通しする）。
#   見つかった場合は、package.json / *.yml / *.yaml / Makefile のいずれかの
#   中身に整形の道具に関する語（prettier / editorconfig / biome / format）が
#   1つも無ければ、統合の検査への登録が見当たらないとして違反とする
#   （check-doc-heading-addendum.sh と同じ、ファイル名で対象文書を探す方式）。
#
# 除外条件（誤検知回避）:
#   - tool_name が Write 以外 → 対象外
#   - file_path の拡張子が対象言語（ts/tsx/mts/cts/js/jsx/mjs/cjs/py）以外 →
#     型検査ルールは対象外、他ルールも当該言語拡張子の判定をスキップ
#   - 整形は道具へ任せる: cwd が空・存在しない → 対象外（fail-open）。整形の
#     設定ファイルが見当たらない → 対象外（見つかった場合のみ中身を検査する）
#
# 既知の限界:
#   - 関数の行数・入れ子の深さの計測は、波かっこの対応（JS系）または
#     字下げ幅4スペース換算（Python）による近似であり、厳密な構文解析ではない
#   - 数値検出は比較演算子の右辺に現れる2桁以上の数値のみを対象とし、
#     代入・宣言行は除外する近似判定である
#   - 出力用の一時的な呼び出しは既知の不透明な関数名の一覧に基づく検出であり、
#     一覧に無い呼び出し（自作のロガー等）は検出できない
#   - 整形は道具へ任せる: 整形の設定ファイル名に一致する最初の1件のみを見る。
#     統合の検査への登録は、既知のファイル名（package.json / *.yml / *.yaml /
#     Makefile）の中身に整形の道具の語があるかという近似判定であり、実際に
#     CI 等で実行されているかまでは確認しない
#
# 止めるか知らせるか:
#   型の検査を骨抜きにしない: 止める（型検査を無効化する記述がそのままコミットされると、型安全性の欠落が履歴に残り事後に気付けなくなるため）
#   数値と文字列に名前を付ける: 止める（意味の無い数値がそのまま履歴に残ると、後から書いた意図を復元できなくなるため）
#   試したままのコードを残さない: 止める（一時的な出力や注釈で消したコードが履歴に残ると、後から消す判断ができなくなるため）
#   関数を1つの責務に絞る: 止める（肥大化した関数がそのままコミットされると、複雑度が履歴に固定され事後の分割コストが増え続けるため）
#   入れ子を深くしない: 止める（深い入れ子がそのままコミットされると、複雑度が履歴に固定され事後の分割コストが増え続けるため）
#   整形は道具へ任せる: 止める（設定ファイルだけ用意して統合の検査に登録しない状態が確定すると、整形の不統一が履歴に積み重なり事後に揃え直すコストが増すため）
#
# 逃げ道:
#   ANY_TYPE_ESCAPE_HATCH_SKIP_REASON に理由を書けば通る。理由が空の場合は通らない
#
# 使い方:
#   フック本体として: PreToolUse(Write) の入力 JSON を stdin から受け取る
#   単体実行: check-any-type-escape-hatch.sh --self-test
set -uo pipefail

TS_EXT_RE='\.(ts|tsx|mts|cts)$'
PY_EXT_RE='\.py$'
BRACE_EXT_RE='\.(ts|tsx|mts|cts|js|jsx|mjs|cjs)$'

FUNC_LEN_LIMIT=50
NEST_DEPTH_LIMIT=4

# ---- 型の検査を骨抜きにしない（既存） ----
check_any_type() {
  local file_path="$1" content="$2" is_ts=0 is_py=0 hit=""
  printf '%s' "$file_path" | grep -qE "$TS_EXT_RE" && is_ts=1
  printf '%s' "$file_path" | grep -qE "$PY_EXT_RE" && is_py=1
  [ "$is_ts" -eq 0 ] && [ "$is_py" -eq 0 ] && return 1

  if [ "$is_ts" -eq 1 ]; then
    printf '%s' "$content" | grep -qE ':[[:space:]]*any\b' && hit="\": any\" 型注釈"
    [ -z "$hit" ] && printf '%s' "$content" | grep -qE '\bas[[:space:]]+any\b' && hit="\"as any\" キャスト"
    [ -z "$hit" ] && printf '%s' "$content" | grep -qE '<any>' && hit="\"<any>\" ジェネリクス"
    [ -z "$hit" ] && printf '%s' "$content" | grep -qE '@ts-ignore' && hit="\"@ts-ignore\""
    [ -z "$hit" ] && printf '%s' "$content" | grep -qE '@ts-nocheck' && hit="\"@ts-nocheck\""
  fi
  if [ -z "$hit" ] && [ "$is_py" -eq 1 ]; then
    printf '%s' "$content" | grep -qE ':[[:space:]]*Any\b' && hit="\": Any\" 型注釈"
    [ -z "$hit" ] && printf '%s' "$content" | grep -qE '#[[:space:]]*type:[[:space:]]*ignore' && hit="\"# type: ignore\""
  fi

  if [ -n "$hit" ]; then
    echo "拒否[型の検査を骨抜きにしない]: 骨抜きにする記述があります（${hit}）"
    return 0
  fi
  return 1
}

# ---- 数値と文字列に名前を付ける ----
check_magic_number() {
  local file_path="$1" content="$2"
  printf '%s' "$file_path" | grep -qE "$BRACE_EXT_RE|$PY_EXT_RE" || return 1

  local hit
  hit=$(printf '%s\n' "$content" \
    | grep -nE '(==|===|!=|!==|>=|<=|[^=!<>-]>[^=]|[^=!<>-]<[^=])[[:space:]]*-?[0-9]{2,}\b' \
    | grep -viE '(const|let|var|final|static)[[:space:]]+[A-Z_][A-Z0-9_]*[[:space:]]*=' \
    | head -1)

  if [ -n "$hit" ]; then
    echo "拒否[数値と文字列に名前を付ける]: 比較式の中に意味を持つ数値が直接書かれています（${hit}）"
    return 0
  fi
  return 1
}

# ---- 試したままのコードを残さない ----
check_leftover_debug() {
  local file_path="$1" content="$2"
  printf '%s' "$file_path" | grep -qE "$BRACE_EXT_RE|$PY_EXT_RE" || return 1

  local hit=""
  printf '%s' "$content" | grep -qE '\bdebugger[[:space:]]*;' && hit="\"debugger;\""
  [ -z "$hit" ] && printf '%s' "$content" | grep -qE 'console\.(log|debug)\(' && hit="\"console.log/debug\""
  [ -z "$hit" ] && printf '%s' "$content" | grep -qE '\b(var_dump|print_r|dd)\(' && hit="出力用の一時関数呼び出し"
  [ -z "$hit" ] && printf '%s' "$content" | grep -qE 'pdb\.set_trace\(\)|binding\.pry' && hit="デバッガ起動コード"

  if [ -z "$hit" ]; then
    local commented
    commented=$(printf '%s\n' "$content" \
      | grep -cE '^[[:space:]]*(//|#)[[:space:]]*[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*(\(|=[^=]).*;?[[:space:]]*$')
    [ "${commented:-0}" -ge 2 ] && hit="注釈で消された連続2行以上のコードらしき記述"
  fi

  if [ -n "$hit" ]; then
    echo "拒否[試したままのコードを残さない]: 出力のための一時的な記述、または注釈で消したコードがあります（${hit}）"
    return 0
  fi
  return 1
}

# ---- 関数を1つの責務に絞る（50行）: JS系 ----
check_function_length_brace() {
  local content="$1" limit="$2"
  local result
  result=$(printf '%s\n' "$content" | awk -v limit="$limit" '
    BEGIN{instart=0}
    {
      o=gsub(/\{/,"{")
      c=gsub(/\}/,"}")
      isstart = ($0 ~ /^[ \t]*(export[ \t]+)?(default[ \t]+)?(async[ \t]+)?function[ \t(]/) \
        || ($0 ~ /=>[ \t]*\{[ \t]*$/) \
        || ($0 ~ /^[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*\([^)]*\)[ \t]*\{[ \t]*$/)
      if (!instart && isstart && o>0) {
        instart=1; start=NR; localdepth=0
      }
      if (instart) {
        localdepth += o - c
        if (localdepth<=0) {
          len = NR-start+1
          if (len>limit) { print start":"len; exit }
          instart=0
        }
      }
    }
  ')
  [ -z "$result" ] && return 1
  echo "${result}"
  return 0
}

# ---- 関数を1つの責務に絞る（50行）: Python ----
check_function_length_py() {
  local content="$1" limit="$2"
  local result
  result=$(printf '%s\n' "$content" | awk -v limit="$limit" '
    function indent_of(line,   n){ n=match(line,/[^ \t]/); if (n==0) return -1; return n-1 }
    BEGIN{indef=0}
    {
      line=$0
      cur = indent_of(line)
      if (!indef) {
        if (line ~ /^[ \t]*def[ \t]+[A-Za-z_]/) { defindent=cur; start=NR; indef=1 }
        next
      }
      if (cur == -1) next
      if (cur <= defindent) {
        len = NR - start
        if (len > limit) { print start":"len; exit }
        indef=0
        if (line ~ /^[ \t]*def[ \t]+[A-Za-z_]/) { defindent=cur; start=NR; indef=1 }
      }
    }
    END{
      if (indef) {
        len = NR - start + 1
        if (len > limit) print start":"len
      }
    }
  ')
  [ -z "$result" ] && return 1
  echo "${result}"
  return 0
}

check_function_length() {
  local file_path="$1" content="$2"
  local result
  if printf '%s' "$file_path" | grep -qE "$BRACE_EXT_RE"; then
    result="$(check_function_length_brace "$content" "$FUNC_LEN_LIMIT")" || return 1
  elif printf '%s' "$file_path" | grep -qE "$PY_EXT_RE"; then
    result="$(check_function_length_py "$content" "$FUNC_LEN_LIMIT")" || return 1
  else
    return 1
  fi
  local startline len
  startline="${result%%:*}"
  len="${result##*:}"
  echo "拒否[関数を1つの責務に絞る]: 関数（${startline}行目付近から）の行数が既定の上限（${FUNC_LEN_LIMIT}行）を超えています（${len}行）"
  return 0
}

# ---- 入れ子を深くしない（4段）: JS系 ----
check_nesting_depth_brace() {
  local content="$1" limit="$2"
  local max
  max=$(printf '%s\n' "$content" | awk '
    BEGIN{depth=0;max=0}
    {
      o=gsub(/\{/,"{")
      c=gsub(/\}/,"}")
      depth += o - c
      if (depth>max) max=depth
    }
    END{print max}
  ')
  [ -z "$max" ] && return 1
  [ "$max" -le "$limit" ] && return 1
  echo "$max"
  return 0
}

# ---- 入れ子を深くしない（4段）: Python（字下げ4スペース換算） ----
check_nesting_depth_py() {
  local content="$1" limit="$2"
  local max
  max=$(printf '%s\n' "$content" | awk -v unit=4 '
    BEGIN{max=0}
    {
      line=$0
      if (line ~ /^[ \t]*$/) next
      if (line ~ /^[ \t]*#/) next
      n=match(line, /[^ \t]/)
      indent = n - 1
      level = int(indent/unit)
      if (level>max) max=level
    }
    END{print max}
  ')
  [ -z "$max" ] && return 1
  [ "$max" -le "$limit" ] && return 1
  echo "$max"
  return 0
}

check_nesting_depth() {
  local file_path="$1" content="$2"
  local max
  if printf '%s' "$file_path" | grep -qE "$BRACE_EXT_RE"; then
    max="$(check_nesting_depth_brace "$content" "$NEST_DEPTH_LIMIT")" || return 1
    echo "拒否[入れ子を深くしない]: 波かっこの入れ子が既定の上限（${NEST_DEPTH_LIMIT}段）を超えています（最大${max}段）"
    return 0
  elif printf '%s' "$file_path" | grep -qE "$PY_EXT_RE"; then
    max="$(check_nesting_depth_py "$content" "$NEST_DEPTH_LIMIT")" || return 1
    echo "拒否[入れ子を深くしない]: 字下げの深さが既定の上限（${NEST_DEPTH_LIMIT}段。4スペース換算）を超えています（最大${max}段）"
    return 0
  fi
  return 1
}

# ---- 整形は道具へ任せる ----
# 指定した cwd 配下（.git 配下を除く）から、整形の設定ファイルらしい名前
# （.prettierrc* / .editorconfig / biome.json）の最初のファイルを返す。
# cwd が空・存在しない、または見つからない場合は空を返す
find_formatter_config() {
  local cwd="$1"
  if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
    return 0
  fi
  find "$cwd" -type f -not -path '*/.git/*' \( -iname '.prettierrc*' -o -iname '.editorconfig' -o -iname 'biome.json' \) 2>/dev/null | head -1
}

check_formatter_registration() {
  local cwd="$1"
  local cfg
  cfg="$(find_formatter_config "$cwd")"
  [ -z "$cfg" ] && return 1

  local hit
  hit="$(find "$cwd" -type f -not -path '*/.git/*' \( -iname 'package.json' -o -iname '*.yml' -o -iname '*.yaml' -o -iname 'Makefile' \) 2>/dev/null \
    | while IFS= read -r f; do grep -liE '(prettier|editorconfig|biome|format)' "$f" 2>/dev/null; done | head -1)"
  if [ -n "$hit" ]; then
    return 1
  fi

  echo "拒否[整形は道具へ任せる]: 整形の設定ファイル（${cfg#"$cwd"/}）は実在するが、統合の検査への登録が見当たりません"
  return 0
}

judge() {
  # $1: file_path, $2: content, $3: cwd（省略可。省略時は「整形は道具へ任せる」を対象外として扱う）
  # 標準出力: 判定理由（複数行）。戻り値: 0=許可・2=拒否
  local file_path="$1" content="$2" cwd="${3:-}"
  local violations="" msg

  if msg="$(check_any_type "$file_path" "$content")"; then
    violations="${violations}${msg}\n"
  fi
  if msg="$(check_magic_number "$file_path" "$content")"; then
    violations="${violations}${msg}\n"
  fi
  if msg="$(check_leftover_debug "$file_path" "$content")"; then
    violations="${violations}${msg}\n"
  fi
  if msg="$(check_function_length "$file_path" "$content")"; then
    violations="${violations}${msg}\n"
  fi
  if msg="$(check_nesting_depth "$file_path" "$content")"; then
    violations="${violations}${msg}\n"
  fi
  if msg="$(check_formatter_registration "$cwd")"; then
    violations="${violations}${msg}\n"
  fi

  if [ -n "$violations" ]; then
    printf '拒否: コードの書き方と分割の決まりに違反する記述があります。%b' "$violations"
    return 2
  fi

  echo "許可: コードの書き方と分割の決まりに反する記述は見当たりません"
  return 0
}

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${ANY_TYPE_ESCAPE_HATCH_SKIP_REASON:-}" ]; then
    echo "[ANY-TYPE-ESCAPE-HATCH-SKIP] 理由: ${ANY_TYPE_ESCAPE_HATCH_SKIP_REASON}"
    return 0
  fi
  return 1
}

run_hook() {
  local skip_msg
  if skip_msg="$(should_skip_with_reason)"; then
    printf '%s\n' "$skip_msg" >&2
    exit 0
  fi

  local input
  input="$(cat)"
  [ -z "$input" ] && exit 0

  local tool
  tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
  [ "$tool" != "Write" ] && exit 0

  local file_path content cwd
  file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
  [ -z "$file_path" ] && exit 0
  content=$(printf '%s' "$input" | jq -r '.tool_input.content // empty' 2>/dev/null)
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)

  local msg code
  if msg="$(judge "$file_path" "$content" "$cwd")"; then code=0; else code=$?; fi

  [ "$code" -eq 0 ] && exit 0

  ctx="[ANY-TYPE-ESCAPE-HATCH-BLOCK] ${msg}"
  jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  printf '%s\n' "$ctx" >&2
  exit 2
}

self_test() {
  local rc=0 msg code

  # 系1: TS + ": any" 型注釈 → 拒否
  if msg="$(judge "src/app.ts" 'function f(x: any) { return x; }')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系1: TSの \": any\" 型注釈は拒否される"
  else
    echo "  [FAIL] 系1: any型注釈があるのに許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系2: TS + "@ts-ignore" → 拒否
  if msg="$(judge "src/app.ts" '// @ts-ignore
const x: string = 1;')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系2: \"@ts-ignore\" は拒否される"
  else
    echo "  [FAIL] 系2: @ts-ignoreがあるのに許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系3: TS + 具体的な型のみ → 許可
  if msg="$(judge "src/app.ts" 'function f(x: number): string { return String(x); }')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系3: 具体的な型のみは許可される"
  else
    echo "  [FAIL] 系3: any型が無いのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系4: 対象外拡張子（.md）に "any" という単語が出現 → 許可（対象外）
  if msg="$(judge "docs/note.md" 'if any errors occur, retry.')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系4: 対象外拡張子は許可される"
  else
    echo "  [FAIL] 系4: 対象外拡張子なのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系5: Python + "# type: ignore" → 拒否
  if msg="$(judge "src/app.py" 'x = f()  # type: ignore')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系5: Pythonの \"# type: ignore\" は拒否される"
  else
    echo "  [FAIL] 系5: type: ignoreがあるのに許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系6: 数値と文字列に名前を付ける — 比較式に生数値 → 拒否
  if msg="$(judge "src/app.js" 'function check(age) {
  if (age >= 65) {
    return true;
  }
}')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -q '数値と文字列に名前を付ける'; then
    echo "  [PASS] 系6: 比較式の生数値は拒否される"
  else
    echo "  [FAIL] 系6: 生数値があるのに許可された、または規則名が無い（exit=${code}）" >&2
    rc=1
  fi

  # 系7: 数値が名前付き定数の宣言行のみ → 許可
  if msg="$(judge "src/app.js" 'const RETIREMENT_AGE = 65;
function check(age) {
  return age >= RETIREMENT_AGE;
}')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系7: 名前付き定数化された数値は許可される"
  else
    echo "  [FAIL] 系7: 定数化されているのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系8: 試したままのコード — console.log 残留 → 拒否
  if msg="$(judge "src/app.js" 'function f(x) {
  console.log(x);
  return x;
}')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -q '試したままのコードを残さない'; then
    echo "  [PASS] 系8: console.log の残留は拒否される"
  else
    echo "  [FAIL] 系8: console.log があるのに許可された、または規則名が無い（exit=${code}）" >&2
    rc=1
  fi

  # 系9: 一時的な出力・注釈コードが無い → 許可
  if msg="$(judge "src/app.js" 'function f(x) {
  return x + 1;
}')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系9: 一時的な出力が無ければ許可される"
  else
    echo "  [FAIL] 系9: 一時的な出力が無いのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系10: 関数の行数上限（50行）超過 → 拒否
  local longbody body_lines i
  body_lines=""
  for i in $(seq 1 60); do
    body_lines="${body_lines}  doSomething(${i});
"
  done
  if msg="$(judge "src/app.js" "function longFn() {
${body_lines}}")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -q '関数を1つの責務に絞る'; then
    echo "  [PASS] 系10: 50行を超える関数は拒否される"
  else
    echo "  [FAIL] 系10: 50行超の関数があるのに許可された、または規則名が無い（exit=${code}）" >&2
    rc=1
  fi

  # 系11: 50行以内の関数 → 許可
  if msg="$(judge "src/app.js" 'function shortFn() {
  return 1;
}')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系11: 50行以内の関数は許可される"
  else
    echo "  [FAIL] 系11: 短い関数なのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系12: 入れ子の深さ（4段）超過 → 拒否
  if msg="$(judge "src/app.js" 'function f() {
  if (a) {
    if (b) {
      if (c) {
        if (d) {
          doIt();
        }
      }
    }
  }
}')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -q '入れ子を深くしない'; then
    echo "  [PASS] 系12: 4段を超える入れ子は拒否される"
  else
    echo "  [FAIL] 系12: 深い入れ子があるのに許可された、または規則名が無い（exit=${code}）" >&2
    rc=1
  fi

  # 系13: 浅い入れ子 → 許可
  if msg="$(judge "src/app.js" 'function f() {
  if (a) {
    doIt();
  }
}')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系13: 浅い入れ子は許可される"
  else
    echo "  [FAIL] 系13: 浅い入れ子なのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系14: 整形の設定ファイルが cwd に無い → 対象外として許可
  local tmp14
  if ! tmp14="$(mktemp -d "${TMPDIR:-/tmp}/check-any-type-escape-hatch-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp14" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  printf 'function shortFn() {\n  return 1;\n}\n' > "$tmp14/app.js"
  if msg="$(judge "$tmp14/app.js" 'function shortFn() {
  return 1;
}' "$tmp14")"; then code=0; else code=$?; fi
  rm -rf "$tmp14"
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系14: 整形の設定ファイルが見当たらなければ対象外として許可される（${msg}）"
  else
    echo "  [FAIL] 系14: 整形の設定ファイルが無いのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系15: 整形の設定ファイルは実在するが統合の検査への登録が見当たらない → 拒否
  local tmp15
  if ! tmp15="$(mktemp -d "${TMPDIR:-/tmp}/check-any-type-escape-hatch-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp15" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  printf '{}\n' > "$tmp15/.prettierrc"
  printf '{"name": "app"}\n' > "$tmp15/package.json"
  if msg="$(judge "$tmp15/app.js" 'function shortFn() {
  return 1;
}' "$tmp15")"; then code=0; else code=$?; fi
  rm -rf "$tmp15"
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -q '整形は道具へ任せる'; then
    echo "  [PASS] 系15: 統合の検査への登録が無い整形の設定は拒否される（${msg}）"
  else
    echo "  [FAIL] 系15: 登録が無いのに許可、または規則名が無い（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系16: 整形の設定ファイルが実在し、統合の検査（package.json）に登録されている → 許可
  local tmp16
  if ! tmp16="$(mktemp -d "${TMPDIR:-/tmp}/check-any-type-escape-hatch-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp16" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  printf '{}\n' > "$tmp16/.prettierrc"
  printf '{"scripts": {"format": "prettier --check ."}}\n' > "$tmp16/package.json"
  if msg="$(judge "$tmp16/app.js" 'function shortFn() {
  return 1;
}' "$tmp16")"; then code=0; else code=$?; fi
  rm -rf "$tmp16"
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系16: 統合の検査へ登録された整形の設定は許可される（${msg}）"
  else
    echo "  [FAIL] 系16: 登録済みなのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系17: 環境変数に理由を設定すると should_skip_with_reason は skip する
  local skip_out skip_code
  if skip_out="$(ANY_TYPE_ESCAPE_HATCH_SKIP_REASON="テスト理由" should_skip_with_reason)"; then skip_code=0; else skip_code=$?; fi
  if [ "$skip_code" -eq 0 ] && printf '%s' "$skip_out" | grep -qF 'ANY-TYPE-ESCAPE-HATCH-SKIP' && printf '%s' "$skip_out" | grep -qF 'テスト理由'; then
    echo "  [PASS] 系17: 理由を設定すると should_skip_with_reason は skip する（${skip_out}）"
  else
    echo "  [FAIL] 系17: 理由があるのに skip しない、またはタグ・理由が含まれない（exit=${skip_code}, ${skip_out}）" >&2
    rc=1
  fi

  # 系18: 環境変数を空文字にすると should_skip_with_reason は skip しない
  local skip_code2
  if ANY_TYPE_ESCAPE_HATCH_SKIP_REASON="" should_skip_with_reason >/dev/null 2>&1; then skip_code2=0; else skip_code2=$?; fi
  if [ "$skip_code2" -eq 1 ]; then
    echo "  [PASS] 系18: 環境変数が空文字なら should_skip_with_reason は skip しない"
  else
    echo "  [FAIL] 系18: 空文字なのに skip した（exit=${skip_code2}）" >&2
    rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

case "${1:-}" in
  --self-test) self_test; exit $? ;;
  *) run_hook ;;
esac
