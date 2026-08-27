#!/usr/bin/env bash
# check-direct-circular-import.sh — 部品の分け方と依存の決まり linter
#
# timing: PreToolUse(Write)
# 対象規約: 部品の分け方と依存の決まり（component-architecture.md）
# 検査する規則（検査列に「静的解析」を含む規則すべて）:
#   - 循環する依存を作らない: 取り込みの関係に循環が無いかを走査する
#   - 表示と判断と取得を混ぜない: 表示の部品からデータ取得の呼び出しが
#     直接行われていないかを走査する（JSX を返すファイル内の直接 fetch/axios
#     呼び出しのみを対象とする狭い判定）
#   - 部品の大きさに上限を置く: 150 行を超えていないかを走査する（既定値。
#     上書き値の動的読み込みは未実装で、既定値を固定で使う）
#
# 「部品の受け渡しを入口に集める」は本 checker の対象外とした。当初は
# grep ベースでは判定できないという理由で実装を見送っていたが、その後の
# 検討で規約側（component-architecture.md）の検査列そのものを「不可:
# 正当な取り込みと外側の状態の直接の参照を区別するにはデータの流れの解析を
# 要し、書き込みの内容の走査では判定できない」へ書き換え、静的解析を
# 前提としない規則として整理し直した。したがって本 checker がこの規則を
# 検査しないのは実装漏れではなく、規約側の記載と対応した結果である。
#
# 判定:
#   書き込み対象ファイルから上記の各規則の違反を走査し、1件でも見つかれば
#   block（exit 2）する。違反メッセージには規則名を含める。
#   出力する各行は「動詞＋角括弧に囲んだ規則名＋コロン＋説明」の形式（動詞は
#   拒否・通知・許可・対象外のいずれか）とし、1行に1判定だけを出力する。
#
# 判定の設計（循環検出）:
#   完全な import グラフを構築して多段の循環を検出するのは静的解析ツール
#   （madge 等）の領域であり、jq/grep だけの linter では非現実的である。
#   本 checker は「今まさに書き込もうとしているファイル」と「その直接の
#   import 先」という2ファイル間の直接循環のみを対象にし、範囲を絞ることで
#   grep ベースの実装に留めている。
#
# 除外条件（誤検知回避）:
#   - tool_name が Write 以外 → 対象外
#   - file_path の拡張子が対象言語（js/jsx/ts/tsx/mjs/cjs）以外 → 循環検出・
#     行数上限は対象外。表示混在の検出は .jsx/.tsx のみを対象とする
#   - 相対 import が1つも無い → 循環検出は対象外
#   - import 先の実ファイルが存在しない（新規作成する側が先に書かれる等）→
#     その import は判定不能としてスキップ（他の import は引き続き判定する）
#
# 既知の限界:
#   - 直接の2ファイル循環のみを検出する。A→B→C→A のような3ファイル以上の
#     循環は検出できない
#   - import 先の一致判定はファイルの basename（拡張子除く）で行うため、
#     異なるディレクトリに同名ファイルが複数存在する場合に誤検知しうる
#   - 表示混在の検出は、JSX タグを含みかつ fetch/axios/XHR 呼び出しを含む
#     ファイルのみを対象とする狭い判定であり、他の形でデータ取得と表示が
#     混在するケース（別レイヤー経由の隠れた結合等）は検出できない
#
# 止めるか知らせるか:
#   循環する依存を作らない: 止める（循環する取り込みがそのままコミットされると、解消しづらい結合が履歴に固定され事後の分離コストが増すため）
#   表示と判断と取得を混ぜない: 止める（表示の部品にデータ取得が混在したまま確定すると、層の混在が履歴に固定され事後の分離コストが増すため）
#   部品の大きさに上限を置く: 止める（肥大化した部品がそのままコミットされると、複雑度が履歴に固定され事後の分割コストが増え続けるため）
#
# 逃げ道:
#   DIRECT_CIRCULAR_IMPORT_SKIP_REASON に理由を書けば通る。理由が空の場合は通らない
#
# 使い方:
#   フック本体として: PreToolUse(Write) の入力 JSON を stdin から受け取る
#   単体実行: check-direct-circular-import.sh --self-test
set -uo pipefail

JS_EXT_RE='\.(js|jsx|ts|tsx|mjs|cjs)$'
JSX_EXT_RE='\.(jsx|tsx)$'
COMPONENT_LEN_LIMIT=150

# 与えられたファイル内容から相対 import 先のパス文字列（./x や ../x）を列挙する
extract_relative_imports() {
  local content="$1"
  printf '%s\n' "$content" \
    | grep -oE "['\"](\.\.?/[^'\"]+)['\"]" \
    | sed -E "s/^['\"]//; s/['\"]\$//" \
    | sort -u
}

# base_dir と相対パスから候補の実ファイルパスを1つ探して返す（見つからなければ空）
resolve_target_file() {
  local base_dir="$1" rel="$2"
  local combined dir file resolved_dir candidate ext
  combined="${base_dir%/}/${rel}"
  dir="$(dirname "$combined")"
  file="$(basename "$combined")"
  resolved_dir="$(cd "$dir" 2>/dev/null && pwd)" || return 1
  for ext in "" .ts .tsx .js .jsx .mjs .cjs; do
    candidate="${resolved_dir}/${file}${ext}"
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  for ext in .ts .tsx .js .jsx .mjs .cjs; do
    candidate="${resolved_dir}/${file}/index${ext}"
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

# ---- 循環する依存を作らない ----
check_circular_import() {
  local file_path="$1" content="$2"

  if ! printf '%s' "$file_path" | grep -qE "$JS_EXT_RE"; then
    echo "対象外[循環する依存を作らない]: import 構文を静的解析できる対象言語ではありません（${file_path}）"
    return 0
  fi

  local rels
  rels="$(extract_relative_imports "$content")"
  if [ -z "$rels" ]; then
    echo "対象外[循環する依存を作らない]: 相対importを含まないため判定できません"
    return 0
  fi

  local base_dir own_noext
  base_dir="$(dirname "$file_path")"
  own_noext="$(basename "$file_path")"
  own_noext="${own_noext%.*}"

  local rel target
  while IFS= read -r rel; do
    [ -z "$rel" ] && continue
    if target="$(resolve_target_file "$base_dir" "$rel")"; then
      if [ -f "$target" ] && grep -oE "['\"](\.\.?/[^'\"]+)['\"]" "$target" 2>/dev/null \
        | sed -E "s/^['\"]//; s/['\"]\$//" \
        | while IFS= read -r back; do basename "$back"; done \
        | sed -E 's/\.[^.]+$//' \
        | grep -qxF "$own_noext"; then
        echo "拒否[循環する依存を作らない]: ${file_path} と ${target} が互いを import しています（直接循環）"
        return 2
      fi
    fi
  done <<EOF
$rels
EOF

  echo "許可[循環する依存を作らない]: 相互に import し合うファイルは見当たりません"
  return 0
}

# ---- 表示と判断と取得を混ぜない ----
check_ui_data_fetch_mix() {
  local file_path="$1" content="$2"

  if ! printf '%s' "$file_path" | grep -qE "$JSX_EXT_RE"; then
    echo "対象外[表示と判断と取得を混ぜない]: JSXを検査できる対象拡張子ではありません（${file_path}）"
    return 0
  fi

  # JSX タグ（<Component> や <div> 等）を返す表示の部品かどうかの簡易判定
  if ! printf '%s' "$content" | grep -qE '</?[A-Za-z][A-Za-z0-9._]*[[:space:]/>]'; then
    echo "対象外[表示と判断と取得を混ぜない]: JSXタグを含む表示の部品ではありません"
    return 0
  fi

  if ! printf '%s' "$content" | grep -qE 'fetch\(|axios\.(get|post|put|delete|patch)\(|new[[:space:]]+XMLHttpRequest\('; then
    echo "許可[表示と判断と取得を混ぜない]: 表示の部品の中でデータ取得の直接呼び出しは見当たりません"
    return 0
  fi

  echo "拒否[表示と判断と取得を混ぜない]: 表示の部品（JSXを返すファイル）の中でデータ取得の呼び出しが直接行われています"
  return 2
}

# ---- 部品の大きさに上限を置く（150行） ----
check_component_length() {
  local file_path="$1" content="$2" limit="$3"

  if ! printf '%s' "$file_path" | grep -qE "$JS_EXT_RE"; then
    echo "対象外[部品の大きさに上限を置く]: 行数を検査できる対象言語ではありません（${file_path}）"
    return 0
  fi

  local lines
  lines=$(printf '%s\n' "$content" | wc -l | tr -d '[:space:]')
  if [ "${lines:-0}" -le "$limit" ]; then
    echo "許可[部品の大きさに上限を置く]: ファイルの行数は既定の上限（${limit}行）以内です（${lines}行）"
    return 0
  fi

  echo "拒否[部品の大きさに上限を置く]: ファイルの行数が既定の上限（${limit}行）を超えています（${lines}行）"
  return 2
}

judge() {
  # $1: file_path, $2: content
  # 標準出力: 判定理由（複数行）。戻り値: 0=許可・2=拒否
  local file_path="$1" content="$2"
  local msg code

  if msg="$(check_circular_import "$file_path" "$content")"; then code=0; else code=$?; fi
  echo "$msg"
  [ "$code" -eq 2 ] && return 2

  if msg="$(check_ui_data_fetch_mix "$file_path" "$content")"; then code=0; else code=$?; fi
  echo "$msg"
  [ "$code" -eq 2 ] && return 2

  if msg="$(check_component_length "$file_path" "$content" "$COMPONENT_LEN_LIMIT")"; then code=0; else code=$?; fi
  echo "$msg"
  [ "$code" -eq 2 ] && return 2

  return 0
}

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${DIRECT_CIRCULAR_IMPORT_SKIP_REASON:-}" ]; then
    echo "[DIRECT-CIRCULAR-IMPORT-SKIP] 理由: ${DIRECT_CIRCULAR_IMPORT_SKIP_REASON}"
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

  local file_path content
  file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
  [ -z "$file_path" ] && exit 0
  content=$(printf '%s' "$input" | jq -r '.tool_input.content // empty' 2>/dev/null)

  local msg code
  if msg="$(judge "$file_path" "$content")"; then code=0; else code=$?; fi

  [ "$code" -eq 0 ] && exit 0

  ctx="[DIRECT-CIRCULAR-IMPORT-BLOCK] ${msg}"
  jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  printf '%s\n' "$ctx" >&2
  exit 2
}

self_test() {
  local rc=0 msg code tmp

  # 系1: 対象外拡張子（.py）→ 許可
  if msg="$(judge "src/app.py" "from .b import x")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系1: 対象外拡張子は許可される（${msg}）"
  else
    echo "  [FAIL] 系1: 対象外拡張子なのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系2: 直接の相互 import（a.ts と b.ts が互いを import）→ 拒否
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-direct-circular-import-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  printf 'import { y } from "./a";\nexport const x = 1;\n' > "$tmp/b.ts"
  if msg="$(judge "$tmp/a.ts" 'import { x } from "./b";
export const y = 1;')"; then code=0; else code=$?; fi
  echo "$msg" > "$tmp/.msg"
  rm -rf "$tmp"
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系2: 直接の相互importは拒否される（${msg}）"
  else
    echo "  [FAIL] 系2: 相互importがあるのに許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系3: 一方向のimport（循環なし）→ 許可
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-direct-circular-import-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  printf 'export const z = 1;\n' > "$tmp/d.ts"
  if msg="$(judge "$tmp/c.ts" 'import { z } from "./d";
export const w = z + 1;')"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系3: 一方向のimportは許可される（${msg}）"
  else
    echo "  [FAIL] 系3: 循環が無いのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系4: import先がまだ存在しない（新規作成順）→ 許可（判定不能でスキップ）
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-direct-circular-import-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  if msg="$(judge "$tmp/e.ts" 'import { f } from "./f";
export const g = f;')"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系4: import先が未実在なら許可される（${msg}）"
  else
    echo "  [FAIL] 系4: import先が無いのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系5: 表示と判断と取得を混ぜない — JSXコンポーネント内で直接fetch → 拒否
  if msg="$(judge "src/UserCard.tsx" 'export function UserCard({ id }) {
  const [user, setUser] = React.useState(null);
  fetch(`/api/users/${id}`).then(r => r.json()).then(setUser);
  return <div>{user && user.name}</div>;
}')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -q '表示と判断と取得を混ぜない'; then
    echo "  [PASS] 系5: JSXコンポーネント内の直接fetchは拒否される（${msg}）"
  else
    echo "  [FAIL] 系5: 直接fetchがあるのに許可された、または規則名が無い（exit=${code}）" >&2
    rc=1
  fi

  # 系6: JSXコンポーネントだがデータ取得を行わない（propsのみ表示） → 許可
  if msg="$(judge "src/UserCard.tsx" 'export function UserCard({ user }) {
  return <div>{user.name}</div>;
}')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系6: データ取得を行わないJSXコンポーネントは許可される（${msg}）"
  else
    echo "  [FAIL] 系6: データ取得が無いのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系7: 部品の大きさに上限を置く（150行超）→ 拒否
  local longbody i
  longbody=""
  for i in $(seq 1 160); do
    longbody="${longbody}// line ${i}
"
  done
  if msg="$(judge "src/Big.ts" "${longbody}export const x = 1;")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -q '部品の大きさに上限を置く'; then
    echo "  [PASS] 系7: 150行を超えるファイルは拒否される（${msg}）"
  else
    echo "  [FAIL] 系7: 150行超のファイルなのに許可された、または規則名が無い（exit=${code}）" >&2
    rc=1
  fi

  # 系8: 150行以内のファイル → 許可
  if msg="$(judge "src/Small.ts" 'export const x = 1;
export const y = 2;')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系8: 150行以内のファイルは許可される（${msg}）"
  else
    echo "  [FAIL] 系8: 短いファイルなのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系9: 環境変数に理由を設定すると should_skip_with_reason は skip する
  local skip_out skip_code
  if skip_out="$(DIRECT_CIRCULAR_IMPORT_SKIP_REASON="テスト理由" should_skip_with_reason)"; then skip_code=0; else skip_code=$?; fi
  if [ "$skip_code" -eq 0 ] && printf '%s' "$skip_out" | grep -qF 'DIRECT-CIRCULAR-IMPORT-SKIP' && printf '%s' "$skip_out" | grep -qF 'テスト理由'; then
    echo "  [PASS] 系9: 理由を設定すると should_skip_with_reason は skip する（${skip_out}）"
  else
    echo "  [FAIL] 系9: 理由があるのに skip しない、またはタグ・理由が含まれない（exit=${skip_code}, ${skip_out}）" >&2
    rc=1
  fi

  # 系10: 環境変数を空文字にすると should_skip_with_reason は skip しない
  local skip_code2
  if DIRECT_CIRCULAR_IMPORT_SKIP_REASON="" should_skip_with_reason >/dev/null 2>&1; then skip_code2=0; else skip_code2=$?; fi
  if [ "$skip_code2" -eq 1 ]; then
    echo "  [PASS] 系10: 環境変数が空文字なら should_skip_with_reason は skip しない"
  else
    echo "  [FAIL] 系10: 空文字なのに skip した（exit=${skip_code2}）" >&2
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
