#!/usr/bin/env bash
# 中継サーバー(ui/server.mjs)のテスト。偽の claude を PATH の先頭に置いて、次の 10 個を確かめる。
# ケース: 依頼で作業のフォルダが決まる
# ケース: 作業が /api/works に出る
# ケース: 起動し直して /api/resume で同じ会話を続ける
# ケース: 送る文の 1 行目に「画面: …」が付く
# ケース: Origin が違う POST と壊れた JSON を断る
# ケース: state.json が空か一瞬ないときも作業のフォルダを忘れない
# ケース: 読み直していない画面の送信が同じ会話に渡る
# ケース: session.json がない作業への送信を断る
# ケース: --resume の会話がないときに新しい ID に替える
# ケース: 聞き取りのキーを含む state.json を画面へそのまま渡す
# 使い方: skill-factory/ で `bash ui/tests/test-relay.sh`。終了コード 0 が全件合格。
# 一時フォルダの skill-factory の写しで動き、本物の ui/ と output/ を変えない。
set -u
source_ui=$(cd "$(dirname "$0")/.." && pwd) || exit 1
port=${PORT:-4199}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sf-test.XXXXXX")
factory="$tmp/sf"
mkdir -p "$factory/ui" "$factory/output"
cp "$source_ui/server.mjs" "$source_ui/index.html" "$source_ui/デザイントークン.css" "$source_ui/はじめに.md" "$source_ui/段階ごとのスキルと規約.json" "$factory/ui/"
cd "$factory" || exit 1
work="test-$(date +%Y-%m-%d-%H%M)-$$"
workDir="output/$work"
log="$tmp/claude-calls.log"
fail=0
pid=""

cleanup() {
  [ -n "$pid" ] && kill "$pid" 2>/dev/null
  cd /
  rm -rf "$tmp"
}
trap cleanup EXIT

ok()  { echo "合格: $1"; }
ng()  { echo "不合格: $1"; fail=1; }

# 偽の claude: 引数と標準入力を記録し、作業のフォルダに state.json を書き、stream-json の返事を出す
mkdir -p "$tmp/bin"
cat > "$tmp/bin/claude" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "--version" ]; then echo "fake 0.0.0"; exit 0; fi
printf 'ARGS: %s\n' "\$*" >> "${log}"
input=\$(cat)
printf 'STDIN: %s\n' "\$(printf '%s' "\$input" | head -n 1)" >> "${log}"
if [ -f "$tmp/no-conversation" ]; then
  rm "$tmp/no-conversation"
  echo '{"type":"result","is_error":true,"errors":["No conversation found with session ID: x"]}'
  exit 1
fi
mkdir -p "$factory/${workDir}/ui"
if [ ! -f "$factory/${workDir}/ui/state.json" ]; then
  cat > "$factory/${workDir}/ui/state.json" <<'JSON'
{"workName":"テストの作業","currentSkill":null,"stage":1,
 "artifacts":[{"stage":1,"name":"要件定義書","status":"下書き"},{"stage":2,"name":"分割設計書","status":"未着手"},{"stage":3,"name":"構成の案","status":"未着手"},{"stage":4,"name":"SKILL.md","status":"未着手"},{"stage":5,"name":"照合の指摘の一覧","status":"未着手"},{"stage":6,"name":"テスト計画書","status":"未着手"},{"stage":7,"name":"シナリオテストの表","status":"未着手"},{"stage":8,"name":"判定の記録","status":"未着手"}],
 "figures":[],"documentPath":"要件定義書.md","decision":null,"questions":null,"downloads":[]}
JSON
fi
echo '{"type":"system","subtype":"init","session_id":"x"}'
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"偽の返事です。"}]}}'
EOF
chmod +x "$tmp/bin/claude"
export PATH="$tmp/bin:$PATH"

start_server() {
  PORT=${port} node ui/server.mjs > "$tmp/server.out" 2>&1 &
  pid=$!
  for _ in $(seq 1 50); do
    curl -s -o /dev/null "http://127.0.0.1:${port}/api/status" && return 0
    sleep 0.1
  done
  echo "中継サーバーが起動しません:"; cat "$tmp/server.out"; exit 1
}
stop_server() { kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; pid=""; }
wait_idle() {
  for _ in $(seq 1 100); do
    curl -s "http://127.0.0.1:${port}/api/status" | grep -q '"busy":false' && return 0
    sleep 0.1
  done
  return 1
}

node --check ui/server.mjs || { ng "node --check ui/server.mjs"; exit 1; }
ok "node --check ui/server.mjs"

start_server

# 依頼を送ると作業のフォルダが決まる
curl -s -o /dev/null -w '%{http_code}' -X POST -H "Origin: http://127.0.0.1:${port}" -H 'Content-Type: application/json' \
  -d '{"text":"テストのスキルを作って"}' "http://127.0.0.1:${port}/api/prompt" | grep -q 202 || ng "依頼で作業のフォルダが決まる: /api/prompt が 202 を返さない"
wait_idle || ng "依頼で作業のフォルダが決まる: claude が終わらない"
status=$(curl -s "http://127.0.0.1:${port}/api/status")
if echo "$status" | grep -q "\"workDir\":\"${workDir}\""; then ok "依頼で作業のフォルダが決まる: workDir が ${workDir} に決まる"; else ng "依頼で作業のフォルダが決まる: workDir が決まらない: $status"; fi
[ -f "${workDir}/ui/session.json" ] && ok "依頼で作業のフォルダが決まる: ui/session.json が書かれる" || ng "依頼で作業のフォルダが決まる: ui/session.json がない"
grep -q '^ユーザー: テストのスキルを作って$' "${workDir}/ui/conversation.md" && ok "依頼で作業のフォルダが決まる: conversation.md には元の文だけが書かれる" || ng "依頼で作業のフォルダが決まる: conversation.md の文が違う"

# 1 行目に「画面: …」が付く
grep -q '^STDIN: 画面: 新規$' "${log}" && ok "送る文の 1 行目に「画面: …」が付く: 1 回目の 1 行目は「画面: 新規」" || ng "送る文の 1 行目に「画面: …」が付く: 1 回目の 1 行目が「画面: 新規」でない: $(grep STDIN "${log}")"
curl -s -o /dev/null -X POST -H "Origin: http://127.0.0.1:${port}" -H 'Content-Type: application/json' -d '{"text":"2 回目"}' "http://127.0.0.1:${port}/api/prompt"
wait_idle || ng "送る文の 1 行目に「画面: …」が付く: 2 回目の claude が終わらない"
grep -q "^STDIN: 画面: ${workDir}$" "${log}" && ok "送る文の 1 行目に「画面: …」が付く: 2 回目の 1 行目は「画面: ${workDir}」" || ng "送る文の 1 行目に「画面: …」が付く: 2 回目の 1 行目が違う: $(grep STDIN "${log}")"

# /api/works に出る
works=$(curl -s "http://127.0.0.1:${port}/api/works")
if echo "${works}" | grep -q "\"dir\":\"${workDir}\"" && echo "${works}" | grep -q '"workName":"テストの作業"' && echo "${works}" | grep -q '"artifact":{"name":"要件定義書","status":"下書き"}' && echo "${works}" | grep -q '"done":false'; then
  ok "作業が /api/works に出る: /api/works に作業が出る"; else ng "作業が /api/works に出る: /api/works の中身が違う: ${works}"; fi

# Origin が違う POST は 403
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "Origin: http://evil.example" -H 'Content-Type: application/json' -d '{"text":"x"}' "http://127.0.0.1:${port}/api/prompt")
[ "$code" = "403" ] && ok "Origin が違う POST と壊れた JSON を断る: Origin が違う POST は 403" || ng "Origin が違う POST と壊れた JSON を断る: Origin が違う POST が $code"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "Origin: http://127.0.0.1:${port}" -H 'Content-Type: application/json' -d '{"text":"' "http://127.0.0.1:${port}/api/prompt")
[ "$code" = "400" ] && ok "Origin が違う POST と壊れた JSON を断る: 壊れた JSON は 400" || ng "Origin が違う POST と壊れた JSON を断る: 壊れた JSON が $code"

# state.json が空か一瞬ないときも、中継サーバーは作業のフォルダを忘れない
cp "${workDir}/ui/state.json" "${workDir}/ui/state.json.bak"
: > "${workDir}/ui/state.json"
wd=$(curl -s "http://127.0.0.1:${port}/api/status" | node -pe 'JSON.parse(require("fs").readFileSync(0)).workDir')
[ "${wd}" = "${workDir}" ] && ok "state.json が空か一瞬ないときも作業のフォルダを忘れない: state.json が空でも workDir は ${workDir} のまま" || ng "state.json が空か一瞬ないときも作業のフォルダを忘れない: state.json が空で workDir が ${wd} になった"
rm "${workDir}/ui/state.json"
wd=$(curl -s "http://127.0.0.1:${port}/api/status" | node -pe 'JSON.parse(require("fs").readFileSync(0)).workDir')
[ "${wd}" = "${workDir}" ] && ok "state.json が空か一瞬ないときも作業のフォルダを忘れない: state.json が一瞬なくても workDir は ${workDir} のまま" || ng "state.json が空か一瞬ないときも作業のフォルダを忘れない: state.json がなくて workDir が ${wd} になった"
mv "${workDir}/ui/state.json.bak" "${workDir}/ui/state.json"

# 止めて起動し直し、/api/resume で同じ会話の ID が使われる
first_id=$(grep -o '"sessionId":"[^"]*"' "${workDir}/ui/session.json" | cut -d'"' -f4)
stop_server
start_server
curl -s -o /dev/null -w '%{http_code}' -X POST -H "Origin: http://127.0.0.1:${port}" -H 'Content-Type: application/json' -d "{\"dir\":\"${workDir}\"}" "http://127.0.0.1:${port}/api/resume" | grep -q 200 || ng "起動し直して /api/resume で同じ会話を続ける: /api/resume が 200 を返さない"
curl -s "http://127.0.0.1:${port}/api/status" | grep -q "\"workDir\":\"${workDir}\"" && ok "起動し直して /api/resume で同じ会話を続ける: 再起動後に workDir が決まる" || ng "起動し直して /api/resume で同じ会話を続ける: 再起動後に workDir が決まらない"
curl -s -o /dev/null -X POST -H "Origin: http://127.0.0.1:${port}" -H 'Content-Type: application/json' -d '{"text":"続き"}' "http://127.0.0.1:${port}/api/prompt"
wait_idle || ng "起動し直して /api/resume で同じ会話を続ける: 再開後の claude が終わらない"
if tail -n 2 "${log}" | grep -q "^ARGS: -p --resume $first_id "; then ok "起動し直して /api/resume で同じ会話を続ける: 再開後は --resume $first_id で呼ぶ"; else ng "起動し直して /api/resume で同じ会話を続ける: 再開後の引数が違う: $(tail -n 2 "${log}" | head -n 1)"; fi

# 中継サーバーだけを起動し直し、読み直していない画面から workDir を添えて送ると、同じ会話に渡る
stop_server
start_server
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "Origin: http://127.0.0.1:${port}" -H 'Content-Type: application/json' -d "{\"text\":\"1: 答え\",\"workDir\":\"${workDir}\"}" "http://127.0.0.1:${port}/api/prompt")
[ "$code" = "202" ] && ok "読み直していない画面の送信が同じ会話に渡る: 起動し直したあとの送信は 202" || ng "読み直していない画面の送信が同じ会話に渡る: 起動し直したあとの送信が $code"
wait_idle || ng "読み直していない画面の送信が同じ会話に渡る: claude が終わらない"
if tail -n 2 "${log}" | grep -q "^ARGS: -p --resume $first_id " && tail -n 1 "${log}" | grep -q "^STDIN: 画面: ${workDir}$"; then ok "読み直していない画面の送信が同じ会話に渡る: 同じ会話 $first_id に「画面: ${workDir}」で渡る"; else ng "読み直していない画面の送信が同じ会話に渡る: 渡り方が違う: $(tail -n 2 "${log}")"; fi

# session.json がない作業には答えを渡さず、state.json が書き直されるまで sessionLost を返す
stop_server
rm "${workDir}/ui/session.json"
start_server
calls=$(grep -c '^ARGS:' "${log}")
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "Origin: http://127.0.0.1:${port}" -H 'Content-Type: application/json' -d "{\"text\":\"1: 答え\",\"workDir\":\"${workDir}\"}" "http://127.0.0.1:${port}/api/prompt")
[ "$code" = "409" ] && ok "session.json がない作業への送信を断る: 会話の ID がない作業への送信は 409" || ng "session.json がない作業への送信を断る: 送信が $code"
[ "$(grep -c '^ARGS:' "${log}")" = "$calls" ] && ok "session.json がない作業への送信を断る: claude を呼ばない" || ng "session.json がない作業への送信を断る: claude を呼んだ"
curl -s "http://127.0.0.1:${port}/api/status" | grep -q '"sessionLost":true' && ok "session.json がない作業への送信を断る: sessionLost が true" || ng "session.json がない作業への送信を断る: sessionLost が true でない"
grep -q '^Claude Code: 前の会話を続けられないので' "${workDir}/ui/conversation.md" && ok "session.json がない作業への送信を断る: conversation.md に続けられないことを書く" || ng "session.json がない作業への送信を断る: conversation.md に書かれない"
sleep 0.1
touch "${workDir}/ui/state.json"
curl -s "http://127.0.0.1:${port}/api/status" | grep -q '"sessionLost":false' && ok "session.json がない作業への送信を断る: state.json が書き直されると sessionLost が false" || ng "session.json がない作業への送信を断る: sessionLost が false に戻らない"

# --resume の会話が見つからないときは、新しい会話の ID に替え、次の送信は --session-id で始める
curl -s -o /dev/null -X POST -H "Origin: http://127.0.0.1:${port}" -H 'Content-Type: application/json' -d '{"text":"新しい会話の 1 回目"}' "http://127.0.0.1:${port}/api/prompt"
wait_idle || ng "--resume の会話がないときに新しい ID に替える: claude が終わらない"
old_id=$(grep -o '"sessionId":"[^"]*"' "${workDir}/ui/session.json" | cut -d'"' -f4)
: > "$tmp/no-conversation"
curl -s -o /dev/null -X POST -H "Origin: http://127.0.0.1:${port}" -H 'Content-Type: application/json' -d '{"text":"1: 答え"}' "http://127.0.0.1:${port}/api/prompt"
wait_idle || ng "--resume の会話がないときに新しい ID に替える: claude が終わらない"
new_id=$(grep -o '"sessionId":"[^"]*"' "${workDir}/ui/session.json" | cut -d'"' -f4)
[ "$new_id" != "$old_id" ] && ok "--resume の会話がないときに新しい ID に替える: session.json の会話の ID が替わる" || ng "--resume の会話がないときに新しい ID に替える: 会話の ID が替わらない"
curl -s "http://127.0.0.1:${port}/api/status" | grep -q '"sessionLost":true' && ok "--resume の会話がないときに新しい ID に替える: sessionLost が true" || ng "--resume の会話がないときに新しい ID に替える: sessionLost が true でない"
curl -s -o /dev/null -X POST -H "Origin: http://127.0.0.1:${port}" -H 'Content-Type: application/json' -d '{"text":"要件定義書.md"}' "http://127.0.0.1:${port}/api/prompt"
wait_idle || ng "--resume の会話がないときに新しい ID に替える: 次の claude が終わらない"
if tail -n 2 "${log}" | grep -q "^ARGS: -p --session-id $new_id "; then ok "--resume の会話がないときに新しい ID に替える: 次の送信は --session-id $new_id で呼ぶ"; else ng "--resume の会話がないときに新しい ID に替える: 次の送信の引数が違う: $(tail -n 2 "${log}" | head -n 1)"; fi

# 聞き取りのキーを含む state.json は、書かれた中身のまま画面へ渡り、聞き取りの答えは書いたまま AI に渡る
cat > "${workDir}/ui/state.json" <<'JSON'
{"workName":"テストの作業","currentSkill":null,"stage":1,"artifacts":[],"figures":[],"documentPath":"要件定義書.md","decision":null,"questions":null,"downloads":[],"screen":"画面 2","summary":{"lines":["議事録を渡すと、","要約を書く"],"readings":[]},"research":null,"factCheck":null,"approvalSheet":null,"draftReview":null}
JSON
curl -s "http://127.0.0.1:${port}/files/ui/state.json" | node -e 'const s=JSON.parse(require("fs").readFileSync(0));process.exit(s.screen==="画面 2"&&s.summary.lines.length===2?0:1)' && ok "聞き取りのキーを含む state.json を画面へそのまま渡す: screen と summary が届く" || ng "聞き取りのキーを含む state.json を画面へそのまま渡す: 届かない"
curl -s -o /dev/null -X POST -H "Origin: http://127.0.0.1:${port}" -H 'Content-Type: application/json' -d '{"text":"はい(推奨)"}' "http://127.0.0.1:${port}/api/prompt"
wait_idle || ng "聞き取りのキーを含む state.json を画面へそのまま渡す: claude が終わらない"
tail -n 1 "${log}" | grep -q "^STDIN: 画面: ${workDir}$" && grep -q '^ユーザー: はい(推奨)$' "${workDir}/ui/conversation.md" && ok "聞き取りのキーを含む state.json を画面へそのまま渡す: 答えが会話の記録と AI に渡る" || ng "聞き取りのキーを含む state.json を画面へそのまま渡す: 答えの渡り方が違う"

stop_server
[ "$fail" = 0 ] && echo "全件合格" || echo "不合格あり"
exit $fail
