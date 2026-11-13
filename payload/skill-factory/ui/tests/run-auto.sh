#!/usr/bin/env bash
# 毎回自動で流す 4 本のテスト(静的な検査、中継サーバーの 2 本、画面)を順に流す。AI はモックだけを使い、利用料はかからない。
# 使い方: skill-factory/ で `bash ui/tests/run-auto.sh`。終了コード 0 が全件合格。判定の記録を ui/tests/<実行日時>/判定の記録.md に書く。
set -u
tests=$(cd "$(dirname "$0")" && pwd) || exit 1
stamp=$(date +%Y-%m-%d-%H%M%S)
record_dir="$tests/$stamp"
mkdir -p "$record_dir"
record="${record_dir}/判定の記録.md"
export ARTIFACT_DIR="${record_dir}/写真"
overall=0
summary=""

run() {
  label=$1; limit=$2; shift 2
  log="${record_dir}/${label}.log"
  begun=$(date +%s)
  # 固まったテストがコミットを止め続けないように、時間の上限で止める
  perl -e 'alarm shift; exec @ARGV' "$limit" "$@" > "$log" 2>&1
  code=$?
  took=$(( $(date +%s) - begun ))
  counts=$(grep '^集計:' "$log" | tail -n 1)
  [ -z "$counts" ] && counts="集計: 合格 $(grep -c '^合格' "$log")、不合格 $(grep -c '^不合格' "$log")"
  echo "${label}: 終了コード ${code}、${took} 秒、${counts}"
  grep '^不合格' "$log"
  summary="${summary}| ${label} | ${code} | ${took} | ${counts#集計: } |
"
  if [ "$code" = 142 ]; then echo "${label}: 時間の上限 ${limit} 秒を超えた(判定できない)"; [ "$overall" = 0 ] && overall=2; elif [ "$code" != 0 ]; then overall=1; fi
  return "$code"
}

# 静的な検査が不合格なら、あとの 3 本を流さない
if run 静的な検査 60 node "$tests/test-static.mjs"; then
  PORT=$(node -e 'const s=require("net").createServer();s.listen(0,"127.0.0.1",()=>{console.log(s.address().port);s.close()})') run 中継サーバーのテスト 120 bash "$tests/test-relay.sh"
  run 中継サーバーの境界のテスト 300 node "$tests/test-relay-edge.mjs"
  run 画面のテスト 600 node "$tests/test-screen.mjs"
fi

# 合格した claude の版と今の版が違うときは、契約のテストを促す。ここでは流さない
baseline="$tests/contract-baseline.json"
current=$(claude --version 2>/dev/null | head -n 1)
checked=$(node -e 'try{console.log(require(process.argv[1]).version||"")}catch{console.log("")}' "$baseline")
if [ -n "$current" ] && [ "$current" != "$checked" ]; then
  echo "注意: 契約のテストが合格した claude の版(${checked:-なし})と今の版($current)が違います。ユーザーの指示で node ui/tests/test-real.mjs contract --yes を流してください。"
fi

{
  echo "# 毎回自動のテストの判定の記録"
  echo
  echo "- 実行日時: $stamp"
  # Stop の hook が、この 5 行と今のファイルを比べる
  for target in server.mjs index.html 段階ごとのスキルと規約.json はじめに.md デザイントークン.css; do
    echo "- SHA-256 ui/${target}: $(shasum -a 256 "$tests/../${target}" | cut -d' ' -f1)"
  done
  echo "- node の版: $(node --version)"
  echo "- 合否(既知の不合格を除く): $([ "$overall" = 0 ] && echo 新しい不合格なし || echo 不合格か判定できないものあり)"
  echo "- 既知の不合格の項目の数: $(node -e 'console.log(Object.keys(require(process.argv[1])).length)' "$tests/known-failures.json")"
  echo
  echo "| テスト | 終了コード | 秒 | 結果 |"
  echo "|---|---|---|---|"
  printf '%s' "$summary"
  echo
  echo "既知の不合格の理由は \`ui/tests/known-failures.json\` にある。項目ごとの結果は、同じフォルダの \`.log\` にある。"
} > "$record"
echo "判定の記録: ${record}"
[ "$overall" = 0 ] && echo "新しい不合格なし(既知の不合格は判定の記録を見る)" || echo "不合格か判定できないものあり"
exit "$overall"
