#!/usr/bin/env bash
# check-delegation-completion-criteria.sh — 「完了条件を渡す」規則の linter
#
# timing: PreToolUse(Agent)
# 対象規約: 人とAIの分担の決まり「完了条件を渡す」
#
# 判定の設計:
#   既存の check-evidence-checklist.sh（PreToolUse(Agent)）が、同じ timing で
#   prompt 内の見出し（## 調査チェックリスト）の有無を検査している。本checkerは
#   検査対象の見出し・語彙を「完了条件」に差し替えたものであり、機構は既存実例と
#   ほぼ同一である。
#
# 判定:
#   Agent への委任 prompt に、完了条件を示す見出し（## 完了条件）または完了条件を
#   明示する語彙（「完了条件」を含む一文）が無ければ違反として block（exit 2）する。
#
# 除外条件（誤検知回避）:
#   - tool_name が Agent でない → 対象外
#   - サブエージェント内部からの再委任（agent_id が付与されている）→ 対象外
#     （既存 check-evidence-checklist.sh と同じ判断: 孫委任まで強制すると委任の
#     連鎖のたびに書式強制が増殖する）
#   - prompt 冒頭 500 文字に [DELEGATION-EXEMPT] 明示 → 対象外（緊急口）
#   - prompt が空 → 対象外（他 hook の検査対象）
#
# 止めるか知らせるか:
#   止める（完了条件を欠いた委任がそのまま実行されると、何を確認すれば完了かを
#   後から復元できなくなるため）
#
# 逃げ道:
#   DELEGATION_COMPLETION_CRITERIA_SKIP_REASON に理由を書けば判定は通る。理由が
#   空の場合は通らない。
#
# 経緯:
#   以前は外部への公開の操作を止める判定も本checkerが担っていたが、その規則は
#   廃止された。本checkerは委任 prompt の完了条件の検査だけを行う。
#
# 使い方:
#   フック本体として: PreToolUse(Agent) の入力 JSON を stdin から受け取る
#   単体実行: check-delegation-completion-criteria.sh --self-test
set -uo pipefail

judge() {
  # $1: prompt
  # 標準出力: 判定理由。戻り値: 0=許可・2=拒否
  local prompt="$1"

  if printf '%s' "$prompt" | head -c 500 | grep -q '\[DELEGATION-EXEMPT\]'; then
    echo "対象外[完了条件を渡す]: [DELEGATION-EXEMPT] が明示されている"
    return 0
  fi

  if printf '%s' "$prompt" | grep -qE '## 完了条件'; then
    echo "許可[完了条件を渡す]: 見出し「## 完了条件」がある"
    return 0
  fi

  if printf '%s' "$prompt" | grep -qE '完了条件(は|:|：)'; then
    echo "許可[完了条件を渡す]: 「完了条件」を明示する記述がある"
    return 0
  fi

  echo "拒否[完了条件を渡す]: prompt に完了条件の見出しまたは明示的な記述がない"
  return 2
}

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${DELEGATION_COMPLETION_CRITERIA_SKIP_REASON:-}" ]; then
    echo "[DELEGATION-COMPLETION-CRITERIA-SKIP] 理由: ${DELEGATION_COMPLETION_CRITERIA_SKIP_REASON}"
    return 0
  fi
  return 1
}

run_hook() {
  local input
  input="$(cat)"
  [ -z "$input" ] && exit 0

  local tool
  tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
  [ "$tool" = "Agent" ] || exit 0

  local skip_msg
  if skip_msg="$(should_skip_with_reason)"; then
    printf '%s\n' "$skip_msg" >&2
    exit 0
  fi

  local agent_id
  agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
  [ -n "$agent_id" ] && exit 0

  local prompt
  prompt=$(printf '%s' "$input" | jq -r '.tool_input.prompt // empty' 2>/dev/null)
  [ -z "$prompt" ] && exit 0

  local msg code
  if msg="$(judge "$prompt")"; then code=0; else code=$?; fi

  [ "$code" -eq 0 ] && exit 0

  ctx="[DELEGATION-COMPLETION-CRITERIA-BLOCK] ${msg}。prompt に完了条件（判定基準）を明示してから再実行してください。"
  jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  printf '%s\n' "$ctx" >&2
  exit 2
}

self_test() {
  local rc=0 msg code

  # 系1: 見出し「## 完了条件」あり → 許可
  local prompt_with_heading='作業内容: ファイルAを修正する。
## 完了条件
テストが通ること。'
  if msg="$(judge "$prompt_with_heading")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系1: 見出しありは許可される（${msg}）"
  else
    echo "  [FAIL] 系1: 見出しがあるのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系2: 見出しは無いが文中に「完了条件は」の明示あり → 許可
  local prompt_with_inline='作業内容: ファイルBを調査する。完了条件は grep 結果が0件になることです。'
  if msg="$(judge "$prompt_with_inline")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系2: 文中の明示ありは許可される（${msg}）"
  else
    echo "  [FAIL] 系2: 明示があるのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系3: 完了条件の記述が一切ない → 拒否
  local prompt_without='作業内容: ファイルCを直してください。'
  if msg="$(judge "$prompt_without")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系3: 完了条件の記述なしは拒否される（${msg}）"
  else
    echo "  [FAIL] 系3: 記述がないのに許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系4: [DELEGATION-EXEMPT] 明示 → 対象外として許可
  local prompt_exempt='[DELEGATION-EXEMPT] 作業内容: ログを確認するだけ。'
  if msg="$(judge "$prompt_exempt")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系4: [DELEGATION-EXEMPT] 明示は対象外として許可される（${msg}）"
  else
    echo "  [FAIL] 系4: 緊急口が効かず拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系5: 環境変数に理由を設定すると should_skip_with_reason は skip する
  local skip_out skip_code
  if skip_out="$(DELEGATION_COMPLETION_CRITERIA_SKIP_REASON="テスト理由" should_skip_with_reason)"; then skip_code=0; else skip_code=$?; fi
  if [ "$skip_code" -eq 0 ] && printf '%s' "$skip_out" | grep -qF 'DELEGATION-COMPLETION-CRITERIA-SKIP' && printf '%s' "$skip_out" | grep -qF 'テスト理由'; then
    echo "  [PASS] 系5: 理由を設定すると should_skip_with_reason は skip する（${skip_out}）"
  else
    echo "  [FAIL] 系5: 理由があるのに skip しない、またはタグ・理由が含まれない（exit=${skip_code}, ${skip_out}）" >&2
    rc=1
  fi

  # 系6: 環境変数を空文字にすると should_skip_with_reason は skip しない
  local skip_code_empty
  if DELEGATION_COMPLETION_CRITERIA_SKIP_REASON="" should_skip_with_reason >/dev/null 2>&1; then skip_code_empty=0; else skip_code_empty=$?; fi
  if [ "$skip_code_empty" -eq 1 ]; then
    echo "  [PASS] 系6: 環境変数が空文字なら should_skip_with_reason は skip しない"
  else
    echo "  [FAIL] 系6: 空文字なのに skip した（exit=${skip_code_empty}）" >&2
    rc=1
  fi

  # 系7: tool_name が Bash の入力は対象外として素通りする（exit 0・出力なし）
  local bash_out bash_code
  bash_out="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}' | bash "$0" 2>&1)"; bash_code=$?
  if [ "$bash_code" -eq 0 ] && [ -z "$bash_out" ]; then
    echo "  [PASS] 系7: Bash の入力は対象外として素通りする"
  else
    echo "  [FAIL] 系7: Bash の入力を止めた、または出力がある（exit=${bash_code}, ${bash_out}）" >&2
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
