#!/usr/bin/env bash
# check-delegation-completion-criteria.sh — 「完了条件を渡す」規則と「外への公開は人がする」規則の linter
#
# timing: PreToolUse(Agent|Bash)
# 対象規約: 人とAIの分担の決まり「完了条件を渡す」「外への公開は人がする」
#
# 判定の設計:
#   完了条件を渡す — 既存の check-evidence-checklist.sh（PreToolUse(Agent)）が、
#   同じ timing で prompt 内の見出し（## 調査チェックリスト）の有無を検査している。
#   本checkerは検査対象の見出し・語彙を「完了条件」に差し替えたものであり、機構は
#   既存実例とほぼ同一である。
#
#   外への公開は人がする — 実行しようとしている Bash コマンドが、外部の複製先へ
#   変更を送る操作かどうかを走査する。tool_name が Bash のときにこの判定だけを行い、
#   Agent の判定とは独立して扱う。
#
# 判定:
#   完了条件を渡す — Agent への委任 prompt に、完了条件を示す見出し（## 完了条件）
#   または完了条件を明示する語彙（「完了条件」を含む一文）が無ければ違反として
#   block（exit 2）する。
#
#   外への公開は人がする — 外部の複製先へ変更を送る操作（後述）であれば違反として
#   block（exit 2）する。
#
# 検査が見る操作の具体（外への公開は人がする）:
#   git push・npm publish・yarn publish・pnpm publish・docker push・
#   gh release create を止める対象とした。これらを代表として選んだ理由は、
#   具体のコマンドは対象プロジェクトによって変わるためであり、外部の複製先へ
#   変更を送るという性質を共有する代表的なものに絞った。
#
# 除外条件（誤検知回避）:
#   - tool_name が Agent・Bash のいずれでもない → 対象外
#   - （完了条件を渡す）サブエージェント内部からの再委任（agent_id が付与されている）
#     → 対象外（既存 check-evidence-checklist.sh と同じ判断: 孫委任まで強制すると
#     委任の連鎖のたびに書式強制が増殖する）
#   - （完了条件を渡す）prompt 冒頭 500 文字に [DELEGATION-EXEMPT] 明示 → 対象外
#     （緊急口）
#   - （完了条件を渡す）prompt が空 → 対象外（他 hook の検査対象）
#   - （外への公開は人がする）command が空 → 対象外（他 hook の検査対象）
#
# 止めるか知らせるか:
#   完了条件を渡す: 止める（完了条件を欠いた委任がそのまま実行されると、何を確認すれば完了かを後から復元できなくなるため）
#   外への公開は人がする: 止める（外部へ出た変更は取り消せないため）
#
# 逃げ道:
#   DELEGATION_COMPLETION_CRITERIA_SKIP_REASON に理由を書けば「完了条件を渡す」の
#   判定は通る。理由が空の場合は通らない。
#   外への公開は人がする の判定は、コマンド文字列の先頭に
#   DELEGATION_COMPLETION_CRITERIA_SKIP_REASON="<理由>" の割り当てが含まれる場合
#   だけ通る（修正2026-08-31）。理由が空、または先頭以外の位置にある場合は通らない。
#   このリポジトリの他の block hook がいずれも理由必須の緊急口を持つ慣行に
#   合わせた。以前は「境界が形骸化する」ことを理由に緊急口を一切設けない
#   判断だったが、誤検知時に AI 側で作業を止める以外の手段が無いという別の
#   問題を生んでいたため、理由必須という制約を保ったまま緊急口を追加する
#   判断へ改めた。
#
#   環境変数（シェルの `export` や代入によって hook プロセス自身の環境に
#   設定した DELEGATION_COMPLETION_CRITERIA_SKIP_REASON）は使えない。
#   PreToolUse hook はコマンドの実行前に動くサブプロセスであり、これから
#   実行されるコマンドの環境変数を hook プロセス自身は継承しない。この
#   ためコマンド文字列そのものの先頭を走査する方式を取る。
#
# 既知の限界:
#   異なる種類の操作を1つの照合の文字列へ並べた例は既存に無く、納品先で2種類とも
#   発火することは実機で確かめていない。
#   外への公開は人がする の緊急口は、コマンド文字列の「先頭」だけを見る単純な
#   走査であり、先頭以外の位置に割り当てを置いた場合は検出できない。
#
# 使い方:
#   フック本体として: PreToolUse(Agent|Bash) の入力 JSON を stdin から受け取る
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

judge_external_publish() {
  # $1: cmd
  # 標準出力: 判定理由。戻り値: 0=許可・2=拒否
  local cmd="$1"

  if { printf '%s' "$cmd" | grep -qF 'git' && printf '%s' "$cmd" | grep -qE '(^|[^a-zA-Z])push([^a-zA-Z]|$)'; } \
    || printf '%s' "$cmd" | grep -qE '(npm|yarn|pnpm)[[:space:]]+publish' \
    || printf '%s' "$cmd" | grep -qE 'docker[[:space:]]+push' \
    || printf '%s' "$cmd" | grep -qE 'gh[[:space:]]+release[[:space:]]+create'; then
    echo "拒否[外への公開は人がする]: 外部の複製先へ変更を送る操作です。この操作は人が行う決まりです。AI は記録（コミット）までを済ませて人へ渡してください"
    return 2
  fi

  echo "許可[外への公開は人がする]: 外部の複製先へ変更を送る操作は見当たりません"
  return 0
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

# 「外への公開は人がする」専用の緊急口。理由を hook 自身の環境変数ではなく
# コマンド文字列の先頭から読む（修正2026-08-31。上の「逃げ道」節を参照）。
# 理由が空、または割り当てが先頭に無ければ skip しない
should_skip_external_publish_with_reason() {
  # $1: command
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  local cmd="$1" reason=""
  if [[ "$cmd" =~ ^DELEGATION_COMPLETION_CRITERIA_SKIP_REASON=\"([^\"]+)\" ]]; then
    reason="${BASH_REMATCH[1]}"
  elif [[ "$cmd" =~ ^DELEGATION_COMPLETION_CRITERIA_SKIP_REASON=\'([^\']+)\' ]]; then
    reason="${BASH_REMATCH[1]}"
  fi
  if [ -n "$reason" ]; then
    echo "[DELEGATION-COMPLETION-CRITERIA-SKIP] 理由: ${reason}"
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

  if [ "$tool" = "Bash" ]; then
    local cmd msg code
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
    [ -z "$cmd" ] && exit 0

    local pub_skip_msg
    if pub_skip_msg="$(should_skip_external_publish_with_reason "$cmd")"; then
      printf '%s\n' "$pub_skip_msg" >&2
      exit 0
    fi

    if msg="$(judge_external_publish "$cmd")"; then code=0; else code=$?; fi

    [ "$code" -eq 0 ] && exit 0

    ctx="[EXTERNAL-PUBLISH-BLOCK] ${msg}。人が実行するまで、この操作は AI からは行いません。"
    jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
    printf '%s\n' "$ctx" >&2
    exit 2
  fi

  if [ "$tool" = "Agent" ]; then
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
  fi

  exit 0
}

self_test() {
  local rc=0 msg code

  # 系1: 見出し「## 完了条件」あり → 許可
  local p1='作業内容: ファイルAを修正する。
## 完了条件
テストが通ること。'
  if msg="$(judge "$p1")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系1: 見出しありは許可される（${msg}）"
  else
    echo "  [FAIL] 系1: 見出しがあるのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系2: 見出しは無いが文中に「完了条件は」の明示あり → 許可
  local p2='作業内容: ファイルBを調査する。完了条件は grep 結果が0件になることです。'
  if msg="$(judge "$p2")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系2: 文中の明示ありは許可される（${msg}）"
  else
    echo "  [FAIL] 系2: 明示があるのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系3: 完了条件の記述が一切ない → 拒否
  local p3='作業内容: ファイルCを直してください。'
  if msg="$(judge "$p3")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系3: 完了条件の記述なしは拒否される（${msg}）"
  else
    echo "  [FAIL] 系3: 記述がないのに許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系4: [DELEGATION-EXEMPT] 明示 → 対象外として許可
  local p4='[DELEGATION-EXEMPT] 作業内容: ログを確認するだけ。'
  if msg="$(judge "$p4")"; then code=0; else code=$?; fi
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
  local skip_code2
  if DELEGATION_COMPLETION_CRITERIA_SKIP_REASON="" should_skip_with_reason >/dev/null 2>&1; then skip_code2=0; else skip_code2=$?; fi
  if [ "$skip_code2" -eq 1 ]; then
    echo "  [PASS] 系6: 環境変数が空文字なら should_skip_with_reason は skip しない"
  else
    echo "  [FAIL] 系6: 空文字なのに skip した（exit=${skip_code2}）" >&2
    rc=1
  fi

  # 系7: git push origin main → 外への公開は人がする で拒否
  if msg="$(judge_external_publish "git push origin main")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '外への公開は人がする'; then
    echo "  [PASS] 系7: git push origin main は拒否される（${msg}）"
  else
    echo "  [FAIL] 系7: 拒否されなかった、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系8: npm publish → 外への公開は人がする で拒否
  if msg="$(judge_external_publish "npm publish")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系8: npm publish は拒否される（${msg}）"
  else
    echo "  [FAIL] 系8: npm publish なのに拒否されなかった（exit=${code}）" >&2
    rc=1
  fi

  # 系9: git commit -m "test" → 公開の操作ではないため許可
  if msg="$(judge_external_publish 'git commit -m "test"')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系9: git commit は公開の操作ではないため許可される（${msg}）"
  else
    echo "  [FAIL] 系9: 公開の操作ではないのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系10: ls -la → 公開の操作ではないため許可
  if msg="$(judge_external_publish "ls -la")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系10: ls -la は公開の操作ではないため許可される（${msg}）"
  else
    echo "  [FAIL] 系10: 公開の操作ではないのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系11: 逃げ道の環境変数に理由を設定していても、外への公開は人がする の判定は拒否のまま
  if msg="$(DELEGATION_COMPLETION_CRITERIA_SKIP_REASON="テスト理由" judge_external_publish "git push origin main")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系11: 逃げ道の環境変数を設定していても外への公開は人がする は拒否のまま（${msg}）"
  else
    echo "  [FAIL] 系11: 逃げ道の環境変数で公開の判定まで通ってしまった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系12: コマンド文字列の先頭に理由付きの割り当てがあれば skip する
  local pub_skip_out pub_skip_code
  if pub_skip_out="$(should_skip_external_publish_with_reason 'DELEGATION_COMPLETION_CRITERIA_SKIP_REASON="正当な理由" git push origin main')"; then pub_skip_code=0; else pub_skip_code=$?; fi
  if [ "$pub_skip_code" -eq 0 ] && printf '%s' "$pub_skip_out" | grep -qF 'DELEGATION-COMPLETION-CRITERIA-SKIP' && printf '%s' "$pub_skip_out" | grep -qF '正当な理由'; then
    echo "  [PASS] 系12: コマンド文字列先頭の理由付き割り当てで should_skip_external_publish_with_reason は skip する（${pub_skip_out}）"
  else
    echo "  [FAIL] 系12: 理由があるのに skip しない、またはタグ・理由が含まれない（exit=${pub_skip_code}, ${pub_skip_out}）" >&2
    rc=1
  fi

  # 系13: 割り当てが無ければ should_skip_external_publish_with_reason は skip しない
  local pub_skip_code2
  if should_skip_external_publish_with_reason "git push origin main" >/dev/null 2>&1; then pub_skip_code2=0; else pub_skip_code2=$?; fi
  if [ "$pub_skip_code2" -eq 1 ]; then
    echo "  [PASS] 系13: 割り当てが無ければ should_skip_external_publish_with_reason は skip しない"
  else
    echo "  [FAIL] 系13: 割り当てが無いのに skip した（exit=${pub_skip_code2}）" >&2
    rc=1
  fi

  # 系14: 理由が空文字であれば should_skip_external_publish_with_reason は skip しない
  local pub_skip_code3
  if should_skip_external_publish_with_reason 'DELEGATION_COMPLETION_CRITERIA_SKIP_REASON="" git push origin main' >/dev/null 2>&1; then pub_skip_code3=0; else pub_skip_code3=$?; fi
  if [ "$pub_skip_code3" -eq 1 ]; then
    echo "  [PASS] 系14: 理由が空文字なら should_skip_external_publish_with_reason は skip しない"
  else
    echo "  [FAIL] 系14: 理由が空文字なのに skip した（exit=${pub_skip_code3}）" >&2
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
