#!/usr/bin/env bash
# check-real-world-cases.sh — 配る検査を実際の書き方で試す
#
# 各検査が持つ自己テストは、その検査を書いた本人が用意した入力で通る。
# 書いた本人が思いつかなかった書き方は入力に入らないため、素通りしても
# 自己テストは合格を返す。実際に 2 件の素通りがこの経路で見逃された。
#   - check-loop-query-call が `for (const x of xs)` を素通り
#   - check-direct-commit-to-integration-branch が統合先の枝の上で素通り
#
# 本スクリプトは、検査とは別に用意した入力集
# （delivery-payload/references/checker-real-world-cases.json）を
# 各検査へ流し、止めてほしいものが止まるかを一覧にする。
#
# 判定:
#   expect=violation → 終了コード 2（止める）を期待する
#   expect=clean     → 終了コード 0（通す）を期待する
#   期待と違えば不合格。1 件でもあれば終了コード 1
#
# 判定不能:
#   入力集または検査が見つからない場合、jq が無い場合は [UNKNOWN] と
#   終了コード 2 を返す（.claude/rules/always/verification/indeterminate-result/rule.md）
#
# 使い方:
#   check-real-world-cases.sh              入力集の全件を試す
#   check-real-world-cases.sh --self-test  本スクリプト自身の判定を確かめる
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CASES_JSON="${REPO_ROOT}/delivery-payload/references/checker-real-world-cases.json"
CHECKER_DIR="${REPO_ROOT}/delivery-payload/templates/rules/checkers"

unknown() {
  echo "[UNKNOWN] $1" >&2
  exit 2
}

# 1 件を試す。標準出力へ結果の行を出し、合格なら 0 を返す。
run_one_case() {
  local checker="$1" label="$2" expect="$3" input="$4"
  local path="${CHECKER_DIR}/${checker}.sh"
  local want actual out

  if [ ! -f "$path" ]; then
    printf 'UNKNOWN  %-42s %s（検査が見つからない）\n' "$checker" "$label"
    return 2
  fi

  # 応答を終える時点で働く検査（Stop hook）は、止めるときも終了コードは 0 の
  # まま、出力の JSON の decision へ block と書いて返す作法を持つ。終了コード
  # だけを見ると素通りと区別がつかないため、この形を expect の stop-block と
  # stop-pass で扱う（実測 2026-08-24: 完了報告の実行結果を見る検査がこの形
  # だったため、入力集の対象から外れていた）。
  case "$expect" in
    stop-block|stop-pass)
      out="$(printf '%s' "$input" | bash "$path" 2>/dev/null)"
      actual=$?
      local blocked=0
      printf '%s' "$out" | LC_ALL=C grep -q '"decision"[[:space:]]*:[[:space:]]*"block"' && blocked=1
      if [ "$actual" -ne 0 ]; then
        printf 'FAIL     %-42s %s（応答を終える検査は終了コード 0 で返すはずが %s）\n' "$checker" "$label" "$actual"
        return 1
      fi
      if [ "$expect" = stop-block ] && [ "$blocked" -eq 1 ]; then
        printf 'PASS     %-42s %s\n' "$checker" "$label"
        return 0
      fi
      if [ "$expect" = stop-pass ] && [ "$blocked" -eq 0 ]; then
        printf 'PASS     %-42s %s\n' "$checker" "$label"
        return 0
      fi
      if [ "$expect" = stop-block ]; then
        printf 'FAIL     %-42s %s（止まらなかった。出力に decision の block が無い）\n' "$checker" "$label"
      else
        printf 'FAIL     %-42s %s（通らなかった。出力に decision の block がある）\n' "$checker" "$label"
      fi
      return 1
      ;;
    notify:*|allow:*)
      # 止める判定を持たず、知らせるだけ・許すだけの検査は終了コードが常に 0
      # で、規則ごとの結果を出力の判定行（「通知[規則名]:」「許可[規則名]:」）
      # で示す。終了コードだけを見ると、知らせるべき入力と許すべき入力を
      # 区別できない（実測 2026-08-24: 定型運用の手順書を見る検査がこの形
      # だったため、入力集の対象から外れていた）。
      # expect は notify:<規則名> または allow:<規則名> の形で書く。
      # 判定行は標準エラーへ出る検査があるため、両方をまとめて受け取る。
      out="$(printf '%s' "$input" | bash "$path" 2>&1)"
      actual=$?
      local want_verb="${expect%%:*}" want_rule="${expect#*:}" want_head
      case "$want_verb" in notify) want_head="通知" ;; allow) want_head="許可" ;; esac
      if [ "$actual" -ne 0 ]; then
        printf 'FAIL     %-42s %s（知らせるだけの検査は終了コード 0 で返すはずが %s）\n' "$checker" "$label" "$actual"
        return 1
      fi
      if printf '%s' "$out" | LC_ALL=en_US.UTF-8 grep -qF "${want_head}[${want_rule}]"; then
        printf 'PASS     %-42s %s\n' "$checker" "$label"
        return 0
      fi
      printf 'FAIL     %-42s %s（出力に %s[%s] が無い）\n' "$checker" "$label" "$want_head" "$want_rule"
      return 1
      ;;
    violation) want=2 ;;
    clean)     want=0 ;;
    *)
      printf 'UNKNOWN  %-42s %s（expect の値が不正: %s）\n' "$checker" "$label" "$expect"
      return 2
      ;;
  esac

  printf '%s' "$input" | bash "$path" >/dev/null 2>&1
  actual=$?

  if [ "$actual" -eq "$want" ]; then
    printf 'PASS     %-42s %s\n' "$checker" "$label"
    return 0
  fi

  if [ "$expect" = violation ]; then
    printf 'FAIL     %-42s %s（止まらなかった。終了コード %s）\n' "$checker" "$label" "$actual"
  else
    printf 'FAIL     %-42s %s（通らなかった。終了コード %s）\n' "$checker" "$label" "$actual"
  fi
  return 1
}

run_check() {
  local cases_json="${1:-$CASES_JSON}"
  local total=0 pass=0 fail=0 unknown_n=0

  command -v jq >/dev/null 2>&1 || unknown "jq が無いため入力集を読めません 操作: jq"
  [ -f "$cases_json" ] || unknown "入力集が見つからないため判定できません 参照したパス: ${cases_json}"
  [ -d "$CHECKER_DIR" ] || unknown "検査の置き場が見つからないため判定できません 参照したパス: ${CHECKER_DIR}"

  local n
  n="$(jq -r '.cases | length' "$cases_json" 2>/dev/null)" || unknown "入力集を読めないため判定できません 操作: jq 想定原因: JSON の形が壊れている"
  [ -n "$n" ] && [ "$n" -gt 0 ] 2>/dev/null || unknown "入力集に 1 件も入っていないため判定できません 参照したパス: ${cases_json}"

  local i checker label expect input rc
  for ((i = 0; i < n; i++)); do
    checker="$(jq -r ".cases[$i].checker" "$cases_json")"
    label="$(jq -r ".cases[$i].label" "$cases_json")"
    expect="$(jq -r ".cases[$i].expect" "$cases_json")"
    # 作業ディレクトリや実在ファイルを要する検査のために、入力集の
    # REPO_ROOT を実行時のリポジトリのルートへ置き換える。入力集は配る
    # 対象であり、このマシンの絶対パスを書き込めないため。
    # 完全一致だけでなく接頭辞も置き換える。ファイルの実在を見る検査
    # （生成物の目印を持つ HTML の上書き等）は、REPO_ROOT に続けて
    # リポジトリ内の相対パスを書いた形を使うためである（実測 2026-08-24:
    # 完全一致だけの置換では実在するファイルを指せず、新規作成として
    # 素通りしていた）。
    input="$(jq -c --arg root "$REPO_ROOT" \
      '.cases['"$i"'].input
       | walk(if type == "string" then
                if . == "REPO_ROOT" then $root
                elif startswith("REPO_ROOT/") then $root + ltrimstr("REPO_ROOT")
                else . end
              else . end)' \
      "$cases_json")"

    # やり取りの記録を見る検査（完了報告に実行結果を添えているか、上書きの
    # 前に既存を読んだか）は transcript_path を要する。入力集へ記録の中身を
    # transcript として書き、ここで一時ファイルへ流し込んで差し込む。
    # 記録は 1 行 1 件の JSON の並びで書く。
    local tr_lines tr_file
    tr_lines="$(printf '%s' "$input" | jq -r 'if has("transcript") then .transcript[] | tostring else empty end' 2>/dev/null)"
    tr_file=""
    if [ -n "$tr_lines" ]; then
      if ! tr_file="$(mktemp "${TMPDIR:-/tmp}/real-world-transcript.XXXXXX" 2>/dev/null)" || [ -z "$tr_file" ]; then
        printf 'UNKNOWN  %-42s %s（記録の一時ファイルを作れない。操作: mktemp）\n' "$checker" "$label"
        total=$((total + 1)); unknown_n=$((unknown_n + 1))
        continue
      fi
      printf '%s\n' "$tr_lines" > "$tr_file"
      input="$(printf '%s' "$input" | jq -c --arg p "$tr_file" 'del(.transcript) | .transcript_path = $p')"
    fi

    run_one_case "$checker" "$label" "$expect" "$input"
    rc=$?
    [ -n "$tr_file" ] && rm -f "$tr_file"
    total=$((total + 1))
    case "$rc" in
      0) pass=$((pass + 1)) ;;
      1) fail=$((fail + 1)) ;;
      *) unknown_n=$((unknown_n + 1)) ;;
    esac
  done

  echo "---"
  echo "実行 ${total} 件 合格 ${pass} 件 不合格 ${fail} 件 判定不能 ${unknown_n} 件"

  [ "$unknown_n" -gt 0 ] && return 2
  [ "$fail" -gt 0 ] && return 1
  return 0
}

run_self_test() {
  local tmp rc n_pass=0 n_fail=0

  # 置き場を明示するのは、引数なしの mktemp が既定の置き場へ書こうとして失敗する環境があるためである（実測 2026-08-24）。素直な mktemp へ戻さない。
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/$(basename "${BASH_SOURCE[0]}" .sh).XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリを作れないため自己テストを判定できません 操作: mktemp -d 想定原因: 実行環境が一時領域への書き込みを許していない" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' EXIT

  assert() {
    local name="$1" want="$2" got="$3"
    if [ "$want" = "$got" ]; then
      echo "[PASS] ${name}"
      n_pass=$((n_pass + 1))
    else
      echo "[FAIL] ${name}（期待 ${want} / 実際 ${got}）"
      n_fail=$((n_fail + 1))
    fi
  }

  # ケース1: 止まるべきものが止まれば合格
  printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"a.js","content":"const key = \"AKIAIOSFODNN7EXAMPLE\";\n"}}' > "$tmp/in1"
  run_one_case check-secret-literal-in-code 止まる violation "$(cat "$tmp/in1")" >/dev/null
  assert "止まるべきものが止まれば合格" 0 $?

  # ケース2: 止まるべきものが素通りすれば不合格
  printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"a.js","content":"const x = 1;\n"}}' > "$tmp/in2"
  run_one_case check-secret-literal-in-code 素通り violation "$(cat "$tmp/in2")" >/dev/null
  assert "止まるべきものが素通りすれば不合格" 1 $?

  # ケース3: 通すべきものが通れば合格
  run_one_case check-secret-literal-in-code 通る clean "$(cat "$tmp/in2")" >/dev/null
  assert "通すべきものが通れば合格" 0 $?

  # ケース4: 検査が無ければ判定不能
  run_one_case check-does-not-exist 不在 violation '{}' >/dev/null
  assert "検査が無ければ判定不能" 2 $?

  # ケース4b: 応答を終える検査は、終了コードではなく出力の decision で見る。
  # 終了コードだけを見ていた頃はこの形の検査を扱えず、入力集の対象から
  # 外していた（実測 2026-08-24）。
  printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"a.js","content":"const key = \"AKIAIOSFODNN7EXAMPLE\";\n"}}' > "$tmp/in-stop"
  run_one_case check-secret-literal-in-code 終了コード非0 stop-block "$(cat "$tmp/in-stop")" >/dev/null
  assert "応答を終える検査で終了コードが0でなければ不合格" 1 $?

  printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"a.js","content":"const x = 1;\n"}}' > "$tmp/in-stop2"
  run_one_case check-secret-literal-in-code block無し stop-block "$(cat "$tmp/in-stop2")" >/dev/null
  assert "応答を終える検査でdecisionのblockが無ければ不合格" 1 $?

  run_one_case check-secret-literal-in-code block無し stop-pass "$(cat "$tmp/in-stop2")" >/dev/null
  assert "応答を終える検査でdecisionのblockが無ければ通す期待は合格" 0 $?

  # ケース4c: 知らせるだけの検査は、出力の判定行で規則ごとに見分ける。
  # 判定行を標準エラーへ出す検査があるため、両方の出力を受け取る
  # （実測 2026-08-24: 標準出力だけを見ていた頃は4件すべて捕まえられなかった）。
  local probe_dir="$tmp/notify-probe"
  mkdir -p "$probe_dir"
  printf '# 手順書\n\n## 手順\n\n1. 写しを取る\n' > "$probe_dir/バックアップ手順書.md"
  printf '%s' "{\"tool_name\":\"Bash\",\"cwd\":\"$probe_dir\",\"tool_input\":{\"command\":\"git commit -m x\"}}" > "$tmp/in-notify"
  run_one_case check-routine-procedure-doc 通知あり "notify:実行の間隔と起点を書く" "$(cat "$tmp/in-notify")" >/dev/null
  assert "知らせるだけの検査で通知の判定行を見分ける" 0 $?

  run_one_case check-routine-procedure-doc 許可期待 "allow:実行の間隔と起点を書く" "$(cat "$tmp/in-notify")" >/dev/null
  assert "通知が出ているのに許可を期待すれば不合格" 1 $?

  # ケース5: expect の値が不正なら判定不能
  run_one_case check-secret-literal-in-code 不正 maybe '{}' >/dev/null
  assert "expect の値が不正なら判定不能" 2 $?

  # ケース6: 入力集が無ければ判定不能
  ( run_check "$tmp/no-such-file.json" >/dev/null 2>&1 )
  assert "入力集が無ければ判定不能" 2 $?

  # ケース7: 入力集が空なら判定不能
  echo '{"cases":[]}' > "$tmp/empty.json"
  ( run_check "$tmp/empty.json" >/dev/null 2>&1 )
  assert "入力集が空なら判定不能" 2 $?

  # ケース8: REPO_ROOT はパスの接頭辞としても置き換わる。
  # 完全一致だけの置換では、ファイルの実在を見る検査が実在するファイルを
  # 指せず素通りしていた（実測 2026-08-24）。
  # このスクリプト自身の実在を、接頭辞の形で指せることで確かめる。
  cat > "$tmp/prefix.json" <<'JSON'
{"cases":[{"checker":"probe-exists","label":"接頭辞の置換","expect":"clean",
  "input":{"path":"REPO_ROOT/generation-engine/scripts/tests/check-real-world-cases.sh"}}]}
JSON
  local substituted
  substituted="$(jq -c --arg root "$REPO_ROOT" \
    '.cases[0].input
     | walk(if type == "string" then
              if . == "REPO_ROOT" then $root
              elif startswith("REPO_ROOT/") then $root + ltrimstr("REPO_ROOT")
              else . end
            else . end)' "$tmp/prefix.json" | jq -r '.path')"
  if [ -f "$substituted" ]; then
    assert "REPO_ROOT が接頭辞としても置き換わる" 0 0
  else
    assert "REPO_ROOT が接頭辞としても置き換わる（解決先: ${substituted}）" 0 1
  fi

  echo "---"
  echo "SELF-TEST SUMMARY: 実行 $((n_pass + n_fail)) 件 合格 ${n_pass} 件 不合格 ${n_fail} 件"
  [ "$n_fail" -eq 0 ] || exit 1
  exit 0
}

case "${1:-}" in
  --self-test) run_self_test ;;
  *) run_check "${1:-}" ;;
esac
