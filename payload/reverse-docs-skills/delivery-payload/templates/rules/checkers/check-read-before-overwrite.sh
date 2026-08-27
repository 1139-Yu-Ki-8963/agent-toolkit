#!/usr/bin/env bash
# check-read-before-overwrite.sh — 「上書きの前に既存を読む」規則の linter
#
# timing: PreToolUse(Write)
# 対象規約: 上書きの前に読む決まり「上書きの前に既存を読む」
#
# 判定:
#   Write の書き込み先 file_path が既にファイルシステム上に存在する場合（＝上書き）、
#   同一セッションの transcript 内に、その file_path を対象とした Read の tool_use が
#   1件でも記録されていなければ違反として block（exit 2）する。
#   file_path が存在しない（新規作成）場合は上書きではないため対象外（exit 0）。
#
# 入力（hooks標準形。stdin JSON）:
#   .tool_name        "Write" のときのみ判定対象
#   .tool_input.file_path  書き込み先の絶対パス
#   .transcript_path   セッション transcript（JSONL）のパス
#
# 判定の設計:
#   実際のセッション transcript（~/.claude/projects/*/*.jsonl）を jq で走査したところ、
#   Read tool_use は次の形で記録されており、file_path の一致判定が可能だった:
#     {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read",
#       "input":{"file_path":"/abs/path/to/file"}}]}}
#   この記録形式を根拠に、transcript から Read の有無を判定材料として使う。
#
# 除外条件（誤検知回避）:
#   - file_path が存在しない（新規作成）→ 上書きではないため対象外
#   - transcript_path が空・ファイル不在・jq 解析不能 → fail-open（判定不能を block しない）
#   - tool_name が Write 以外 → 対象外
#
# 使い方:
#   フック本体として: PreToolUse(Write) の入力 JSON を stdin から受け取る
#   単体実行: check-read-before-overwrite.sh --self-test
#
# 止めるか知らせるか:
#   上書きの前に既存を読む: 止める（既存ファイルの中身を読まずに上書きすると、失われた内容は後から復元できないため）
#
# 逃げ道:
#   READ_BEFORE_OVERWRITE_SKIP_REASON に理由を書けば通る。理由が空の場合は通らない
set -uo pipefail

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${READ_BEFORE_OVERWRITE_SKIP_REASON:-}" ]; then
    echo "[READ-BEFORE-OVERWRITE-SKIP] 理由: ${READ_BEFORE_OVERWRITE_SKIP_REASON}"
    return 0
  fi
  return 1
}

judge() {
  # $1: file_path, $2: transcript_path
  # 標準出力: 判定理由。戻り値: 0=許可・2=拒否
  local file_path="$1" tp="$2"

  if [ ! -e "$file_path" ]; then
    echo "対象外[上書きの前に既存を読む]: 新規作成のため上書きではありません（${file_path}）"
    return 0
  fi

  if [ -z "$tp" ] || [ ! -f "$tp" ]; then
    echo "対象外[上書きの前に既存を読む]: transcript を参照できないため判定不能（fail-open）"
    return 0
  fi

  local found
  found=$(jq -r --arg fp "$file_path" '
    select(.type=="assistant") | .message.content[]?
    | select(.type=="tool_use" and .name=="Read")
    | .input.file_path // empty
    | select(. == $fp)
  ' "$tp" 2>/dev/null | head -1)

  if [ -n "$found" ]; then
    echo "許可[上書きの前に既存を読む]: 上書き前に ${file_path} の Read 記録あり"
    return 0
  fi

  echo "拒否[上書きの前に既存を読む]: ${file_path} は既存ファイルだが、このセッションで Read された記録がない"
  return 2
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

  local file_path tp msg code
  file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
  [ -z "$file_path" ] && exit 0
  tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)

  if msg="$(judge "$file_path" "$tp")"; then code=0; else code=$?; fi

  if [ "$code" -eq 0 ]; then
    exit 0
  fi

  ctx="[READ-BEFORE-OVERWRITE-BLOCK] ${msg}。上書き前に対象ファイルを Read してから再実行してください。"
  jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  printf '%s\n' "$ctx" >&2
  exit 2
}

self_test() {
  local tmp rc=0
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-read-before-overwrite-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  trap 'rm -rf "$tmp"' RETURN

  # 系1: 新規作成（file_path 不在）は対象外として許可される
  local new_file="$tmp/new-file.txt"
  local msg code
  if msg="$(judge "$new_file" "$tmp/no-transcript.jsonl")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系1: 新規作成は対象外として許可される（${msg})"
  else
    echo "  [FAIL] 系1: 新規作成なのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系2: 既存ファイル + transcript に Read 記録あり → 許可
  local existing="$tmp/existing.txt"
  printf 'dummy\n' > "$existing"
  local tp_with_read="$tmp/with-read.jsonl"
  cat > "$tp_with_read" <<EOF
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"${existing}"}}]}}
EOF
  if msg="$(judge "$existing" "$tp_with_read")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系2: 既存ファイル + Read記録ありは許可される（${msg}）"
  else
    echo "  [FAIL] 系2: Read記録があるのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系3: 既存ファイル + transcript に Read 記録なし（別ファイルのみ）→ 拒否
  local tp_without_read="$tmp/without-read.jsonl"
  cat > "$tp_without_read" <<EOF
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"${tmp}/unrelated.txt"}}]}}
EOF
  if msg="$(judge "$existing" "$tp_without_read")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系3: 既存ファイル + Read記録なしは拒否される（${msg}）"
  else
    echo "  [FAIL] 系3: Read記録がないのに許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系4: transcript_path 不在・参照不能 → fail-open で許可
  if msg="$(judge "$existing" "$tmp/does-not-exist.jsonl")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系4: transcript参照不能はfail-openで許可される（${msg}）"
  else
    echo "  [FAIL] 系4: transcript参照不能なのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系5: 環境変数に理由を設定 → should_skip_with_reasonが戻り値0でタグと理由を返す
  local out5
  if out5="$(READ_BEFORE_OVERWRITE_SKIP_REASON="テスト用の理由" should_skip_with_reason)"; then
    if printf '%s' "$out5" | grep -qF '[READ-BEFORE-OVERWRITE-SKIP]' && printf '%s' "$out5" | grep -qF 'テスト用の理由'; then
      echo "  [PASS] 系5: 理由を設定するとタグと理由付きでskipされる（${out5}）"
    else
      echo "  [FAIL] 系5: skipされたがタグまたは理由が出力に含まれない（${out5}）" >&2
      rc=1
    fi
  else
    echo "  [FAIL] 系5: 理由を設定したのにskipされなかった" >&2
    rc=1
  fi

  # 系6: 環境変数が空文字 → should_skip_with_reasonが戻り値1を返す
  if READ_BEFORE_OVERWRITE_SKIP_REASON="" should_skip_with_reason >/dev/null 2>&1; then
    echo "  [FAIL] 系6: 空文字なのにskipされた" >&2
    rc=1
  else
    echo "  [PASS] 系6: 環境変数が空文字ならskipされない"
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
