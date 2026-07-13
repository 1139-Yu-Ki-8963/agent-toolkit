#!/usr/bin/env bash
# check-worker-haiku-file-change.sh の単体テスト。
# 使い方: bash check-worker-haiku-file-change.test.sh
# 期待: 全ケース PASS で exit 0。FAIL があれば exit 1。
set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/check-worker-haiku-file-change.sh"
pass=0
fail=0

run_case() {
  desc="$1"; agent="$2"; command="$3"; expect="$4"
  if [ -n "$agent" ]; then
    json=$(jq -nc --arg a "$agent" --arg c "$command" '{agent_type: $a, tool_name: "Bash", tool_input: {command: $c}}')
  else
    json=$(jq -nc --arg c "$command" '{tool_name: "Bash", tool_input: {command: $c}}')
  fi
  printf '%s' "$json" | bash "$HOOK" >/dev/null 2>&1
  actual=$?
  if [ "$actual" -eq "$expect" ]; then
    pass=$((pass+1)); echo "PASS: $desc"
  else
    fail=$((fail+1)); echo "FAIL: $desc (expect=$expect actual=$actual)"
  fi
}

# --- 素通り系（block しない） ---
run_case "G1 メイン（agent_type なし）の rm は素通り" ""             "rm -rf /tmp/x"                          0
run_case "G2 worker-sonnet の rm は素通り"            "worker-sonnet" "rm -f a.txt"                            0
run_case "G3 haiku の npm test は許可"                "worker-haiku"  "npm test"                               0
run_case "G4 haiku の git 連結コマンドは許可"          "worker-haiku"  "git add -A && git commit -m 'x'"        0
run_case "G5 haiku の 2>&1 は許可"                    "worker-haiku"  "npm test 2>&1"                          0
run_case "G6 haiku の /dev/null リダイレクトは許可"    "worker-haiku"  "ls foo 2>/dev/null"                     0
run_case "G7 haiku の git rm は許可（git 定型操作）"   "worker-haiku"  "git rm old.txt"                         0
run_case "G8 haiku のスクリプト起動は許可"             "worker-haiku"  "./scripts/build.sh --prod"              0
run_case "G9 haiku の grep パイプは許可"               "worker-haiku"  "grep -r foo . | head -5"                0
run_case "G10 haiku の複数行コミットメッセージ内 <email> は許可" "worker-haiku" "git commit -m \"【機能追加】x

Co-Authored-By: C <noreply@anthropic.com>\"" 0
run_case "G11 haiku のメッセージ内セミコロン+変更語は許可" "worker-haiku" "git commit -m \"fix; touch base with team\"" 0
run_case "G12 haiku の引用内 > を含む grep は許可"        "worker-haiku" "grep -n \"a > b\" file.md" 0

# --- block 系（exit 2） ---
run_case "B1 haiku のファイルリダイレクトは block"     "worker-haiku"  "echo 'テストメモ' > memo.md"             2
run_case "B2 haiku の追記リダイレクトは block"         "worker-haiku"  "cat a >> b.txt"                         2
run_case "B3 haiku の touch は block"                 "worker-haiku"  "touch memo.md"                          2
run_case "B4 haiku の mkdir は block"                 "worker-haiku"  "mkdir -p newdir"                        2
run_case "B5 haiku の sed -i は block"                "worker-haiku"  "sed -i '' -e 's/a/b/' f.md"             2
run_case "B6 haiku の rm は block"                    "worker-haiku"  "rm -f memo.md"                          2
run_case "B7 haiku の tee は block"                   "worker-haiku"  "echo x | tee f.txt"                     2
run_case "B8 haiku の git 後段の非 git 変更は block"   "worker-haiku"  "git status; touch f"                    2
run_case "B9 haiku の mv は block"                    "worker-haiku"  "mv a b"                                 2
run_case "B10 haiku の cp は block"                   "worker-haiku"  "cp a b"                                 2

echo "----"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
