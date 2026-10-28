#!/usr/bin/env bash
# 中継サーバー(ui/server.mjs)のテスト。偽の claude を PATH の先頭に置いて、次の 5 つを確かめる。
# (a) 依頼を送ると、output/<日時>/ui/state.json を置いた作業が見つかり、/api/status の workDir が決まる
# (b) その作業が /api/works に出る
# (c) 中継サーバーを止めて起動し直し、/api/resume で同じ会話の ID が使われる(偽の claude に渡った引数で確かめる)
# (d) claude に渡す文の 1 行目に「画面: …」が付く
# (e) Origin が Host と違う POST は 403
# 使い方: skill-factory/ で `bash ui/test.sh`。終了コード 0 が全件合格。
set -u
cd "$(dirname "$0")/.." || exit 1
factory=$(pwd)
port=${PORT:-4199}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sf-test.XXXXXX")
work="test-$(date +%Y-%m-%d-%H%M)-$$"
workDir="output/$work"
log="$tmp/claude-calls.log"
fail=0
pid=""

cleanup() {
  [ -n "$pid" ] && kill "$pid" 2>/dev/null
  rm -rf "${workDir}" "$tmp"
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

# (a) 依頼を送ると作業のフォルダが決まる
curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
  -d '{"text":"テストのスキルを作って"}' "http://127.0.0.1:${port}/api/prompt" | grep -q 202 || ng "(a) /api/prompt が 202 を返さない"
wait_idle || ng "(a) claude が終わらない"
status=$(curl -s "http://127.0.0.1:${port}/api/status")
if echo "$status" | grep -q "\"workDir\":\"${workDir}\""; then ok "(a) workDir が ${workDir} に決まる"; else ng "(a) workDir が決まらない: $status"; fi
[ -f "${workDir}/ui/session.json" ] && ok "(a) ui/session.json が書かれる" || ng "(a) ui/session.json がない"
grep -q '^ユーザー: テストのスキルを作って$' "${workDir}/ui/conversation.md" && ok "(a) conversation.md には元の文だけが書かれる" || ng "(a) conversation.md の文が違う"

# (d) 1 行目に「画面: …」が付く
grep -q '^STDIN: 画面: 新規$' "${log}" && ok "(d) 1 回目の 1 行目は「画面: 新規」" || ng "(d) 1 回目の 1 行目が「画面: 新規」でない: $(grep STDIN "${log}")"
curl -s -o /dev/null -X POST -H 'Content-Type: application/json' -d '{"text":"2 回目"}' "http://127.0.0.1:${port}/api/prompt"
wait_idle || ng "(d) 2 回目の claude が終わらない"
grep -q "^STDIN: 画面: ${workDir}$" "${log}" && ok "(d) 2 回目の 1 行目は「画面: ${workDir}」" || ng "(d) 2 回目の 1 行目が違う: $(grep STDIN "${log}")"

# (b) /api/works に出る
works=$(curl -s "http://127.0.0.1:${port}/api/works")
if echo "${works}" | grep -q "\"dir\":\"${workDir}\"" && echo "${works}" | grep -q '"workName":"テストの作業"' && echo "${works}" | grep -q '"artifact":{"name":"要件定義書","status":"下書き"}' && echo "${works}" | grep -q '"done":false'; then
  ok "(b) /api/works に作業が出る"; else ng "(b) /api/works の中身が違う: ${works}"; fi

# (e) Origin が違う POST は 403
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "Origin: http://evil.example" -H 'Content-Type: application/json' -d '{"text":"x"}' "http://127.0.0.1:${port}/api/prompt")
[ "$code" = "403" ] && ok "(e) Origin が違う POST は 403" || ng "(e) Origin が違う POST が $code"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "Origin: http://127.0.0.1:${port}" -H 'Content-Type: application/json' -d '{"text":"' "http://127.0.0.1:${port}/api/prompt")
[ "$code" = "400" ] && ok "(e) 壊れた JSON は 400" || ng "(e) 壊れた JSON が $code"

# (c) 止めて起動し直し、/api/resume で同じ会話の ID が使われる
first_id=$(grep -o '"sessionId":"[^"]*"' "${workDir}/ui/session.json" | cut -d'"' -f4)
stop_server
start_server
curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"dir\":\"${workDir}\"}" "http://127.0.0.1:${port}/api/resume" | grep -q 200 || ng "(c) /api/resume が 200 を返さない"
curl -s "http://127.0.0.1:${port}/api/status" | grep -q "\"workDir\":\"${workDir}\"" && ok "(c) 再起動後に workDir が決まる" || ng "(c) 再起動後に workDir が決まらない"
curl -s -o /dev/null -X POST -H 'Content-Type: application/json' -d '{"text":"続き"}' "http://127.0.0.1:${port}/api/prompt"
wait_idle || ng "(c) 再開後の claude が終わらない"
if tail -n 2 "${log}" | grep -q "^ARGS: -p --resume $first_id "; then ok "(c) 再開後は --resume $first_id で呼ぶ"; else ng "(c) 再開後の引数が違う: $(tail -n 2 "${log}" | head -n 1)"; fi

stop_server
[ "$fail" = 0 ] && echo "全件合格" || echo "不合格あり"
exit $fail
