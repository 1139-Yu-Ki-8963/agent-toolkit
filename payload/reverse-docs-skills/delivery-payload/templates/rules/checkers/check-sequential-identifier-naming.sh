#!/usr/bin/env bash
# check-sequential-identifier-naming.sh — 名前の付け方の決まり linter
#
# timing: PreToolUse(Write)
# 対象規約: 名前の付け方の決まり（naming.md）
# 検査する規則（検査列に「静的解析」を含む規則すべて）:
#   - 通し番号を識別子にしない: 識別子が数字だけの語尾で区別されていないかを走査する
#   - 動くものは動詞から始める: 関数の名前が動詞から始まっているかを走査する
#     （既知の非動詞名詞の一覧に一致した場合のみ違反とする一覧照合方式）
#   - 表記の形式を対象ごとに固定する: 識別子の表記が対象の種類ごとに単一の形式へ
#     揃っているかを走査する（変数宣言の表記ゆれを検出する）
#   - 不透明な省略を使わない: 識別子に許可の一覧へ無い短い省略が含まれていないかを
#     走査する。対象プロジェクトが cwd 配下の docs/rules/**/rule.md へ許可する
#     省略の一覧を宣言している場合のみ判定する（宣言が無ければ通知のみで
#     判定は行わない。check-currency-float-type.sh と同じ「宣言待ち」方式）
#
# 判定:
#   書き込む内容から上記の各規則の違反を走査し、1件でも見つかれば
#   block（exit 2）する。違反メッセージには規則名を含める。
#   出力する各行は「動詞＋角括弧に囲んだ規則名＋コロン＋説明」の形式（動詞は
#   拒否・通知・許可・対象外のいずれか）とし、1行に1判定だけを出力する。
#
# 除外条件（誤検知回避）:
#   - tool_name が Write 以外 → 対象外
#   - content が空 → 各規則の判定が自然に「違反なし」側に倒れる
#     （grep 系の走査が空文字に対して何も一致しないため）
#   - 不透明な省略を使わない: cwd が空 → 判定関数自体を呼ばない
#     （宣言の有無を確認する docs/rules/ の走査基点が無いため）
#
# 既知の限界:
#   - 「動詞から始める」判定は、既知の非動詞名詞の一覧に一致する関数名だけを
#     違反として検出する片側判定であり、一覧に無い名詞の誤用は検出できない
#   - 表記ゆれ判定は `const`/`let`/`var` 宣言の識別子のみを対象とし、
#     関数引数・プロパティ名は対象に含めない
#   - 宣言から値を取り出す方式は、宣言が自由な文章のため最初に一致した組だけを見る
#   - 識別子の抽出は宣言に続く形だけを見るため、他の形で定義された識別子は見落とす
#     （名前の付け方の決まりのみ）
#
# 使い方:
#   フック本体として: PreToolUse(Write) の入力 JSON を stdin から受け取る
#   単体実行: check-sequential-identifier-naming.sh --self-test
#
# 止めるか知らせるか:
#   通し番号を識別子にしない: 止める（連番の識別子は意味を汲み取れず同じ命名が増殖して読解コストが膨らむため）
#   動くものは動詞から始める: 止める（名詞始まりの関数名は動作の有無を誤解させ呼び出し側の実装ミスにつながるため）
#   表記の形式を対象ごとに固定する: 止める（表記の混在は同一対象を別物と誤認させ参照ミスという実害につながるため）
#   不透明な省略を使わない: 知らせる（略語の許容範囲はプロジェクトの宣言に依存し宣言が無い段階では機械的に断定できないため）
#
# 逃げ道:
#   SEQUENTIAL_IDENTIFIER_NAMING_SKIP_REASON に理由を書けば通る。理由が空の場合は通らない
set -uo pipefail

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${SEQUENTIAL_IDENTIFIER_NAMING_SKIP_REASON:-}" ]; then
    echo "[SEQUENTIAL-IDENTIFIER-NAMING-SKIP] 理由: ${SEQUENTIAL_IDENTIFIER_NAMING_SKIP_REASON}"
    return 0
  fi
  return 1
}

# 「表示・保存・取得・計算」等の動作でよく使われる名詞のうち、関数名の先頭に
# 誤って使われがちなものの一覧。動詞の網羅的な一覧は持てないため、
# 判断に迷う場合は検出しない側に倒し、既知の非動詞名詞だけを対象にする。
NOUN_PREFIX_RE='^(data|info|information|user|config|configuration|options?|item|value|price|order|name|list|array|object|obj|count|total|result|response|request|status|state|flag|params?|payload)[A-Z_]'

# cwd 配下の docs/rules/**/rule.md の「## このプロジェクトの規則」表から、
# 規則名（第1列）が完全一致する行の内容列（第2列）を1件返す。無ければ空文字。
lookup_project_override_content() {
  # $1: cwd, $2: rule name
  local cwd="$1" name="$2" file
  [ -d "$cwd/docs/rules" ] || return 0
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    awk -v name="$name" '
      BEGIN { insec = 0 }
      /^## このプロジェクトの規則/ { insec = 1; next }
      /^## / && insec == 1 { insec = 0 }
      insec == 1 && /^\|/ {
        line = $0
        if (line ~ /^\| *規則 *\|/) next
        if (line ~ /^\|[-: ]+\|[-: ]+\|/) next
        n = split(line, cols, "|")
        rule = cols[2]; gsub(/^[ \t]+|[ \t]+$/, "", rule)
        if (rule == name) {
          content = cols[3]; gsub(/^[ \t]+|[ \t]+$/, "", content)
          print content
          exit
        }
      }
    ' "$file"
  done < <(find "$cwd/docs/rules" -name 'rule.md' 2>/dev/null) | head -1
}

# ---- 通し番号を識別子にしない（既存） ----
check_sequential_identifier() {
  local content="$1"

  local bases
  bases=$(printf '%s\n' "$content" \
    | grep -oE '[A-Za-z_][A-Za-z0-9_]*[0-9]+' \
    | sort -u \
    | sed -E 's/[0-9]+$//; s/_$//' \
    | grep -vE '^$' \
    | sort \
    | uniq -c \
    | awk '$1>=2 {$1=""; print}' \
    | sed -E 's/^[[:space:]]+//')

  if [ -z "$bases" ]; then
    echo "許可[通し番号を識別子にしない]: 連番だけで区別された識別子は見当たりません"
    return 0
  fi

  local list
  list=$(printf '%s' "$bases" | tr '\n' ',' | sed -E 's/,$//; s/,/、/g')
  echo "拒否[通し番号を識別子にしない]: 連番だけで区別された識別子があります（基底名: ${list}）"
  return 2
}

# ---- 動くものは動詞から始める ----
check_verb_start() {
  local content="$1"

  local hit
  hit=$(printf '%s\n' "$content" \
    | grep -oE '\bfunction[[:space:]]+[A-Za-z_][A-Za-z0-9_]*|\bdef[[:space:]]+[A-Za-z_][A-Za-z0-9_]*|\b(const|let|var)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*(async[[:space:]]*)?\([^)]*\)[[:space:]]*=>' \
    | grep -oE '[A-Za-z_][A-Za-z0-9_]*$' \
    | grep -iE "$NOUN_PREFIX_RE" \
    | head -1)

  if [ -z "$hit" ]; then
    echo "許可[動くものは動詞から始める]: 動作を表さない名詞から始まる関数名は見当たりません"
    return 0
  fi
  echo "拒否[動くものは動詞から始める]: 関数名が動作を表さない名詞から始まっています（${hit}）"
  return 2
}

# ---- 表記の形式を対象ごとに固定する ----
check_casing_consistency() {
  local content="$1"

  local names
  names=$(printf '%s\n' "$content" \
    | grep -oE '\b(const|let|var)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' \
    | grep -oE '[A-Za-z_][A-Za-z0-9_]*$')
  if [ -z "$names" ]; then
    echo "対象外[表記の形式を対象ごとに固定する]: 表記ゆれを判定できる変数宣言が見当たりません"
    return 0
  fi

  local has_camel=0 has_snake=0 name
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    # 全大文字（定数）は表記ゆれの対象外
    printf '%s' "$name" | grep -qE '^[A-Z_][A-Z0-9_]*$' && continue
    if printf '%s' "$name" | grep -qE '_'; then
      has_snake=1
    elif printf '%s' "$name" | grep -qE '[a-z][A-Z]'; then
      has_camel=1
    fi
  done <<EOF
$names
EOF

  if [ "$has_camel" -eq 1 ] && [ "$has_snake" -eq 1 ]; then
    echo "拒否[表記の形式を対象ごとに固定する]: 同じ書き込み内でキャメルケースとスネークケースの変数名が混在しています"
    return 2
  fi
  echo "許可[表記の形式を対象ごとに固定する]: キャメルケースとスネークケースの変数名の混在は見当たりません"
  return 0
}

# ---- 不透明な省略を使わない ----
judge_opaque_abbreviation() {
  # $1: cwd, $2: file_path, $3: content
  local cwd="$1" file_path="$2" content="$3"

  case "$file_path" in
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.py|*.java|*.cs|*.go|*.rb|*.php|*.kt|*.swift) ;;
    *)
      echo "対象外[不透明な省略を使わない]: 識別子を走査できるコードの拡張子ではありません（${file_path}）"
      return 0
      ;;
  esac

  local override
  override="$(lookup_project_override_content "$cwd" "不透明な省略を使わない")"
  if [ -z "$override" ]; then
    echo "通知[不透明な省略を使わない]: このプロジェクトの規則に許可する省略の一覧がないため判定していません。リバース解析を実行すると判定の対象になります"
    return 0
  fi

  local allowed
  allowed="$(printf '%s' "$override" | sed 's/、/\n/g; s/,/\n/g; s/・/\n/g; s/　/\n/g; s/ /\n/g' | sed '/^[[:space:]]*$/d')"
  if [ -z "$allowed" ]; then
    echo "通知[不透明な省略を使わない]: このプロジェクトの規則に宣言はありますが、許可する省略を読み取れません"
    return 0
  fi

  local idents
  idents="$(printf '%s\n' "$content" \
    | grep -oE '\b(var|let|const|function|def|class|func)[[:space:]]+[A-Za-z][A-Za-z0-9_]*' \
    | grep -oE '[A-Za-z][A-Za-z0-9_]*$' \
    | grep -E '^[a-z]{2,4}$')"

  local hitname="" name
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    if ! printf '%s\n' "$allowed" | grep -qxF "$name"; then
      hitname="$name"
      break
    fi
  done <<EOF
$idents
EOF

  if [ -n "$hitname" ]; then
    echo "通知[不透明な省略を使わない]: 許可の一覧に無い短い名前が識別子に使われています（${hitname}）"
    return 0
  fi

  echo "許可[不透明な省略を使わない]: 許可の一覧に無い短い名前は見当たりません"
  return 0
}

judge() {
  # $1: content, $2: file_path（省略可）, $3: cwd（省略可）
  # 標準出力: 判定理由（複数行）。戻り値: 0=許可・2=拒否
  local content="$1" file_path="${2:-}" cwd="${3:-}"
  local msg code

  if msg="$(check_sequential_identifier "$content")"; then code=0; else code=$?; fi
  echo "$msg"
  [ "$code" -eq 2 ] && return 2

  if msg="$(check_verb_start "$content")"; then code=0; else code=$?; fi
  echo "$msg"
  [ "$code" -eq 2 ] && return 2

  if msg="$(check_casing_consistency "$content")"; then code=0; else code=$?; fi
  echo "$msg"
  [ "$code" -eq 2 ] && return 2

  if [ -n "$cwd" ]; then
    if msg="$(judge_opaque_abbreviation "$cwd" "$file_path" "$content")"; then code=0; else code=$?; fi
    echo "$msg"
    [ "$code" -eq 2 ] && return 2
  fi

  return 0
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
  content=$(printf '%s' "$input" | jq -r '.tool_input.content // empty' 2>/dev/null)
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)

  local msg code
  if msg="$(judge "$content" "$file_path" "$cwd")"; then code=0; else code=$?; fi

  [ "$code" -eq 0 ] && exit 0

  ctx="[SEQUENTIAL-IDENTIFIER-NAMING-BLOCK] ${msg}"
  jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  printf '%s\n' "$ctx" >&2
  exit 2
}

self_test() {
  local rc=0 msg code

  # 系1: item1 / item2 が同居 → 拒否
  if msg="$(judge 'const item1 = 1;
const item2 = 2;')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -q '通し番号を識別子にしない'; then
    echo "  [PASS] 系1: item1/item2 の同居は拒否される"
  else
    echo "  [FAIL] 系1: 連番識別子があるのに許可された、または規則名が無い（exit=${code}）" >&2
    rc=1
  fi

  # 系2: step_1 / step_2（下線区切り）が同居 → 拒否
  if msg="$(judge 'run(step_1);
run(step_2);')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系2: step_1/step_2 の同居は拒否される"
  else
    echo "  [FAIL] 系2: 下線区切りの連番があるのに許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系3: item1 のみが複数回出現（サフィックス違いなし）→ 許可
  if msg="$(judge 'const item1 = 1;
console.log(item1);')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系3: 同一トークンの繰り返しのみは許可される"
  else
    echo "  [FAIL] 系3: サフィックス違いが無いのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系4: 数字を含まない通常の識別子のみ、かつ表記統一 → 許可
  if msg="$(judge 'const userName = "taro";
const orderTotal = 100;')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系4: 数字を含まない識別子は許可される"
  else
    echo "  [FAIL] 系4: 連番が無いのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系5: 動くものは動詞から始める — 名詞始まりの関数名 → 拒否
  if msg="$(judge 'function userData(id) {
  return fetchUser(id);
}')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -q '動くものは動詞から始める'; then
    echo "  [PASS] 系5: 名詞始まりの関数名は拒否される"
  else
    echo "  [FAIL] 系5: 名詞始まりの関数名があるのに許可された、または規則名が無い（exit=${code}）" >&2
    rc=1
  fi

  # 系6: 動詞始まりの関数名のみ → 許可
  if msg="$(judge 'function fetchUser(id) {
  return db.find(id);
}')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系6: 動詞始まりの関数名は許可される"
  else
    echo "  [FAIL] 系6: 動詞始まりなのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系7: 表記の形式を対象ごとに固定する — camelCase と snake_case の変数が混在 → 拒否
  if msg="$(judge 'const userName = "taro";
const order_total = 100;')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -q '表記の形式を対象ごとに固定する'; then
    echo "  [PASS] 系7: キャメルケースとスネークケースの混在は拒否される"
  else
    echo "  [FAIL] 系7: 表記が混在しているのに許可された、または規則名が無い（exit=${code}）" >&2
    rc=1
  fi

  # 系8: snake_case のみで統一 → 許可
  if msg="$(judge 'const user_name = "taro";
const order_total = 100;')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系8: 表記が統一されていれば許可される"
  else
    echo "  [FAIL] 系8: 表記が統一されているのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系9: 不透明な省略を使わない — 対象でない拡張子 → 対象外
  local tmp
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-sequential-identifier-naming-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  if msg="$(judge 'const value = 1;' "docs/notes.txt" "$tmp")"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -q '対象外\[不透明な省略を使わない\]'; then
    echo "  [PASS] 系9: 対象外の拡張子は対象外として通知される"
  else
    echo "  [FAIL] 系9: 対象外拡張子なのに対象外の判定が出なかった（exit=${code}）" >&2
    rc=1
  fi

  # 系10: 不透明な省略を使わない — 宣言が無い → 通知
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-sequential-identifier-naming-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  if msg="$(judge 'const value = 1;' "src/app.ts" "$tmp")"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -q '通知\[不透明な省略を使わない\]'; then
    echo "  [PASS] 系10: 宣言が無い場合は通知にとどまる"
  else
    echo "  [FAIL] 系10: 宣言が無いのに通知が出なかった（exit=${code}）" >&2
    rc=1
  fi

  # 系11: 不透明な省略を使わない — 宣言があり違反する場合 → 通知（止めない）
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-sequential-identifier-naming-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  mkdir -p "$tmp/docs/rules/naming/opaque-abbreviation"
  cat > "$tmp/docs/rules/naming/opaque-abbreviation/rule.md" <<'EOF'
# 規約

## このプロジェクトの規則

| 規則 | 内容 | 検査 |
|---|---|---|
| 不透明な省略を使わない | 許可する省略: idx、req、res | 静的解析 |
EOF
  if msg="$(judge 'const abc = 1;' "src/app.ts" "$tmp")"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -q '通知\[不透明な省略を使わない\]'; then
    echo "  [PASS] 系11: 許可の一覧に無い短い名前は通知される（止めない）"
  else
    echo "  [FAIL] 系11: 違反があるのに通知が出なかった、または誤って止められた（exit=${code}）" >&2
    rc=1
  fi

  # 系12: 不透明な省略を使わない — 宣言があり満たしている場合 → 許可
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-sequential-identifier-naming-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  mkdir -p "$tmp/docs/rules/naming/opaque-abbreviation"
  cat > "$tmp/docs/rules/naming/opaque-abbreviation/rule.md" <<'EOF'
# 規約

## このプロジェクトの規則

| 規則 | 内容 | 検査 |
|---|---|---|
| 不透明な省略を使わない | 許可する省略: idx、req、res | 静的解析 |
EOF
  if msg="$(judge 'const idx = 1;' "src/app.ts" "$tmp")"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -q '許可\[不透明な省略を使わない\]'; then
    echo "  [PASS] 系12: 許可の一覧にある短い名前は許可される"
  else
    echo "  [FAIL] 系12: 許可の一覧にあるのに許可されなかった（exit=${code}）" >&2
    rc=1
  fi

  # 系13: 環境変数に理由を書けば skip する
  local skip_msg13
  if skip_msg13="$(SEQUENTIAL_IDENTIFIER_NAMING_SKIP_REASON="点検済みのため" should_skip_with_reason)"; then
    if printf '%s' "$skip_msg13" | grep -qF "SEQUENTIAL-IDENTIFIER-NAMING-SKIP" && printf '%s' "$skip_msg13" | grep -qF "点検済みのため"; then
      echo "  [PASS] 系13: 理由付きの環境変数で skip される（${skip_msg13}）"
    else
      echo "  [FAIL] 系13: skip はされたがタグまたは理由が含まれない（${skip_msg13}）" >&2
      rc=1
    fi
  else
    echo "  [FAIL] 系13: 理由付きの環境変数なのに skip されない" >&2
    rc=1
  fi

  # 系14: 環境変数が空なら skip しない
  local skip_code14
  if SEQUENTIAL_IDENTIFIER_NAMING_SKIP_REASON="" should_skip_with_reason >/dev/null 2>&1; then skip_code14=0; else skip_code14=$?; fi
  if [ "$skip_code14" -eq 1 ]; then
    echo "  [PASS] 系14: 環境変数が空なら skip されない"
  else
    echo "  [FAIL] 系14: 環境変数が空なのに skip された（exit=${skip_code14}）" >&2
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
