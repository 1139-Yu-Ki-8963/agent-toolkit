#!/usr/bin/env bash
# check-completion-evidence.sh — 「完了報告に実行結果を添える」規則の linter
#
# timing: Stop
# 対象規約: 完了報告に実行結果を添える決まり「完了報告に実行結果を添える」
#
# 判定:
#   最終応答の本文（transcript 内の直近の assistant text）に完了を示す表現
#   （「完了しました」等）が含まれるにもかかわらず、コマンド出力・生成物のパス・
#   差分のいずれの痕跡も本文中に見当たらなければ違反として block する
#   （Stop hook の作法に合わせ decision:block を JSON で返す。exit code は 0）。
#
# 判定の設計:
#   「実行結果が添えられている」の判定は、term-explanation の gloss 判定
#   （語のあとに説明が続いているか）と同型の operationalize が可能である。
#   証跡は以下いずれかの出現で判定する（機械的に検出可能な痕跡のみを見る。
#   証跡の「正しさ」までは判定できない＝あくまで痕跡の有無の検査）。
#     (a) コードフェンス ``` を含む（コマンド出力・diff の埋め込みを想定）
#     (b) PASS/FAIL・exit code・終了コード等のテスト結果語彙を含む
#     (c) 拡張子付きの絶対パスを含む（生成物・変更ファイルのパス提示を想定）
#     (d) 行頭が + / - で始まる diff 風の行を含む
#   この4痕跡はいずれも「本文中の文字列パターン」として grep で検出でき、
#   ツール実行結果を transcript から突合する必要はなかった（規則が要求するのは
#   「本文に添えられているか」であり、実行結果の真正性検証ではないため）。
#
# 除外条件（誤検知回避）:
#   - 最終応答に完了を示す表現が無い（質問・提案・進行中の報告等）→ 対象外
#   - stop_hook_active=true（Stop hook の再帰実行中）→ 対象外（無限ループ防止）
#   - plan mode → 対象外（計画段階の応答であり完了報告ではない）
#   - transcript_path が空・ファイル不在・assistant text 抽出不能 → fail-open
#
# 既知の限界:
#   - 痕跡の「有無」のみを見るため、無関係なコードフェンスやパスの言及でも
#     証跡ありと誤判定しうる（誤検知は許可方向にのみ倒れる設計）
#   - 完了表現の語彙リストは拡張可能な有限集合であり、リストに無い言い回しは
#     検出できない（term-explanation の BLOCKLIST と同種の限界）
#
# 止めるか知らせるか:
#   完了報告に実行結果を添える: 止める（証跡のない完了報告がそのまま記録されると、実際に何を確認したかを後から検証できなくなるため）
#
# 逃げ道:
#   COMPLETION_EVIDENCE_SKIP_REASON に理由を書けば通る。理由が空の場合は通らない
#
# 使い方:
#   フック本体として: Stop の入力 JSON を stdin から受け取る
#   単体実行: check-completion-evidence.sh --self-test
set -uo pipefail

COMPLETION_RE='(完了(しました|です|しています|した)|できました|終わりました|対応しました|修正しました|実装しました|反映しました)'

has_evidence() {
  # $1: 本文テキスト
  local text="$1"
  printf '%s' "$text" | grep -qF '```' && return 0
  printf '%s' "$text" | grep -qE '(PASS|FAIL|exit ?code|終了コード|exit [0-9])' && return 0
  printf '%s' "$text" | grep -qE '/[A-Za-z0-9_.:/-]+\.[A-Za-z0-9]{1,8}([[:space:]]|$|」|。)' && return 0
  while IFS= read -r line; do
    printf '%s' "$line" | grep -qE '^[+-][^+-]' && return 0
  done <<EOF
$text
EOF
  return 1
}

judge() {
  # $1: 本文テキスト
  # 標準出力: 判定理由。戻り値: 0=許可・2=拒否
  local text="$1"

  if ! printf '%s' "$text" | grep -qE "$COMPLETION_RE"; then
    echo "対象外[完了報告に実行結果を添える]: 完了を示す表現がない"
    return 0
  fi

  if has_evidence "$text"; then
    echo "許可[完了報告に実行結果を添える]: 完了表現と実行結果の痕跡（コード片/PASS-FAIL/パス/diff のいずれか）が両方ある"
    return 0
  fi

  echo "拒否[完了報告に実行結果を添える]: 完了表現があるが実行結果の痕跡が本文に見当たらない"
  return 2
}

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${COMPLETION_EVIDENCE_SKIP_REASON:-}" ]; then
    echo "[COMPLETION-EVIDENCE-SKIP] 理由: ${COMPLETION_EVIDENCE_SKIP_REASON}"
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

  local stop_active
  stop_active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)
  [ "$stop_active" = "true" ] && exit 0

  local pmode
  pmode=$(printf '%s' "$input" | jq -r '.permission_mode // empty' 2>/dev/null)
  [ "$pmode" = "plan" ] && exit 0

  local tp
  tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
  [ -z "$tp" ] || [ ! -f "$tp" ] && exit 0

  local last
  last=$( { { tac "$tp" 2>/dev/null || tail -r "$tp" 2>/dev/null; } | jq -c 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' 2>/dev/null | head -1; } || true )
  [ -z "$last" ] && exit 0

  local msg code
  if msg="$(judge "$last")"; then code=0; else code=$?; fi

  [ "$code" -eq 0 ] && exit 0

  ctx="[COMPLETION-EVIDENCE-BLOCK] ${msg}。コマンド出力・生成物のパス・差分のいずれかを本文に添えてから応答してください。"
  jq -n --arg ctx "$ctx" '{"decision":"block","systemMessage":$ctx}'
  exit 0
}

self_test() {
  local rc=0 msg code

  # 系1: 完了表現あり + 証跡なし → 拒否
  if msg="$(judge "作業が完了しました。")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系1: 完了表現のみ（証跡なし）は拒否される（${msg}）"
  else
    echo "  [FAIL] 系1: 証跡なしなのに許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系2: 完了表現あり + コードフェンス証跡 → 許可
  local text2='テストを実行し完了しました。
```
$ npm test
PASS 12 tests
```'
  if msg="$(judge "$text2")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系2: コードフェンス証跡ありは許可される（${msg}）"
  else
    echo "  [FAIL] 系2: 証跡があるのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系3: 完了表現あり + ファイルパス証跡 → 許可
  local text3="修正が完了しました。変更ファイル: src/app.ts"
  if msg="$(judge "$text3")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系3: ファイルパス証跡ありは許可される（${msg}）"
  else
    echo "  [FAIL] 系3: パス証跡があるのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系4: 完了表現なし（質問文）→ 対象外として許可
  local text4="この方針で進めてよいか確認させてください。"
  if msg="$(judge "$text4")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系4: 完了表現なしは対象外として許可される（${msg}）"
  else
    echo "  [FAIL] 系4: 完了表現がないのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系5: 完了表現あり + diff証跡 → 許可
  local text5='修正が完了しました。
+ const x = 1;
- const x = 0;'
  if msg="$(judge "$text5")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系5: diff証跡ありは許可される（${msg}）"
  else
    echo "  [FAIL] 系5: diff証跡があるのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系6: 環境変数に理由を設定すると should_skip_with_reason は skip する
  local skip_out skip_code
  if skip_out="$(COMPLETION_EVIDENCE_SKIP_REASON="テスト理由" should_skip_with_reason)"; then skip_code=0; else skip_code=$?; fi
  if [ "$skip_code" -eq 0 ] && printf '%s' "$skip_out" | grep -qF 'COMPLETION-EVIDENCE-SKIP' && printf '%s' "$skip_out" | grep -qF 'テスト理由'; then
    echo "  [PASS] 系6: 理由を設定すると should_skip_with_reason は skip する（${skip_out}）"
  else
    echo "  [FAIL] 系6: 理由があるのに skip しない、またはタグ・理由が含まれない（exit=${skip_code}, ${skip_out}）" >&2
    rc=1
  fi

  # 系7: 環境変数を空文字にすると should_skip_with_reason は skip しない
  local skip_code2
  if COMPLETION_EVIDENCE_SKIP_REASON="" should_skip_with_reason >/dev/null 2>&1; then skip_code2=0; else skip_code2=$?; fi
  if [ "$skip_code2" -eq 1 ]; then
    echo "  [PASS] 系7: 環境変数が空文字なら should_skip_with_reason は skip しない"
  else
    echo "  [FAIL] 系7: 空文字なのに skip した（exit=${skip_code2}）" >&2
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
