#!/usr/bin/env bash
set -euo pipefail

# 第1層の集約（generation-engine/scripts/verification/run-layer-machine-checks.sh）へは載せない。
# 集約の対象外 とする。理由は2点、いずれも実測に基づく（2026-08-19）。
#   1. 単体の所要時間が 572 秒であり、集約の 1 件あたりの上限 120 秒を超える。加えても
#      打ち切られ、合格も不合格も返さない。走っていない状態が形を変えて続くだけになる。
#      （集約には長時間の対象を宣言する口（declared_long_running_timeout）もあるが、
#      そこへ載せても上限で打ち切る挙動は変わらず、判定は返らない。）
#   2. 本スクリプトが呼ぶ 11 件のうち 8 件は、既に集約へ個別に載っている
#      （detect-screens.sh・extract-table-metadata.sh・aggregate-test-viewpoints.sh・
#      seal-facts.sh・prefill-design-from-facts.sh・audit-consistency.sh・
#      extract-screen-metadata.sh・build-screen-list.sh）。加えると同じ検査を二重に走らせる。
# 所要時間を 120 秒以内へ縮め、二重に走る 8 件の呼び出しを見直した時点で、この宣言を
# 外して載せ直すこと。

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
basic_skill="$repo_root/.claude/skills/generating-reverse-basic-design/SKILL.md"
rebuild_skill="$repo_root/.claude/skills/rebuilding-code-from-docs/SKILL.md"
ng_contract="$repo_root/.claude/skills/rebuilding-code-from-docs/references/ng-classification.md"
screen_skill="$repo_root/.claude/skills/generating-screen-list-for-reverse-docs/SKILL.md"

expected_ids='1-9
1-10
1-16
1-19
1-23
1-24
1-25
1-26
1-27
1-28
1-29
1-30
1-31
1-32
1-33
1-34
1-35
1-36
1-37
1-38
1-39
1-40
1-41
1-42
1-43
1-44
1-45
1-46
1-47'

if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-photo-findings-29.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
  echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
  exit 2
fi
trap 'rm -rf "$tmp"' EXIT
passed_ids="$tmp/passed-ids.txt"
: > "$passed_ids"

run_suite() {
  local name="$1"
  shift
  local log="$tmp/$name.log"
  if "$@" >"$log" 2>&1; then
    return 0
  fi
  echo "FAIL: suite=$name command=$*" >&2
  sed 's/^/  /' "$log" >&2
  return 1
}

pass_id() {
  local id="$1" detail="$2"
  printf '%s\n' "$id" >> "$passed_ids"
  printf 'PASS: %s %s\n' "$id" "$detail"
}

require_marker() {
  local id="$1" suite="$2" pattern="$3" detail="$4"
  if grep -Eq "$pattern" "$tmp/$suite.log"; then
    pass_id "$id" "$detail"
  else
    echo "FAIL: ${id} の番号付き検証出力がありません（suite=${suite} pattern=${pattern}）" >&2
    sed 's/^/  /' "$tmp/$suite.log" >&2
    return 1
  fi
}

# すべて合成fixtureまたは契約self-testであり、外部の実データパスは要求しない。
run_suite detect-screens bash "$repo_root/generation-engine/scripts/unit-list/detect-screens.sh" --self-test
run_suite table-metadata bash "$repo_root/generation-engine/scripts/extract/extract-table-metadata.sh" --self-test
run_suite test-viewpoints bash "$repo_root/generation-engine/scripts/extract/aggregate-test-viewpoints.sh" --self-test
run_suite authoring-inputs python3 "$repo_root/generation-engine/scripts/validate-reverse-authoring-inputs.py" --self-test
run_suite python-facts env PYTHONDONTWRITEBYTECODE=1 bash "$repo_root/generation-engine/scripts/tests/test-python-facts-flow.sh"
run_suite seal-facts bash "$repo_root/generation-engine/scripts/seal-facts.sh" --self-test
run_suite prefill-design bash "$repo_root/generation-engine/scripts/prefill-design-from-facts.sh" --self-test
run_suite fact-coverage bash "$repo_root/.claude/skills/generating-reverse-detailed-design/scripts/check-fact-coverage.sh" --self-test
run_suite consistency-audit bash "$repo_root/generation-engine/scripts/audit-consistency.sh" --self-test
run_suite screen-metadata bash "$repo_root/generation-engine/scripts/extract/extract-screen-metadata.sh" --self-test
run_suite screen-list bash "$repo_root/generation-engine/scripts/unit-list/build-screen-list.sh" --self-test

require_marker 1-9 detect-screens 'PASS: 1-9-' 'hasTemplateの1,001件超・UI分類fixture'
require_marker 1-10 detect-screens 'PASS: 1-10-' '分離テンプレートmodal/popup陽性・陰性fixture'
require_marker 1-16 table-metadata '\[PASS\] 1-16:' '複数DDLテーブルのSIGPIPE陰性fixture'
require_marker 1-19 test-viewpoints 'self-test PASS: テスト観点表の集約→検証→HTML→ポータル連結' 'test_viewpoint専用pipeline'
require_marker 1-23 authoring-inputs 'PASS: 1-23 ' 'original.png×facts jsxの4分岐'
require_marker 1-24 authoring-inputs 'PASS: 1-24 ' 'scenarios必須値・省略・証跡の実動分岐'
require_marker 1-25 detect-screens 'PASS: 1-25-' '末尾マーカー除去と業務語保持fixture'

if [ "$(grep -Fc 'name_guess="$(strip_ok_marker "$name_guess")"' \
    "$repo_root/generation-engine/scripts/unit-list/detect-screens.sh")" -ge 2 ] \
  && grep -q '手作業で.*screenNameGuess.*末尾' "$screen_skill"; then
  pass_id 1-26 '再代入後の再正規化と手作業契約'
else
  echo "FAIL: 1-26 全生成経路の再正規化契約が不足" >&2
  exit 1
fi

require_marker 1-27 screen-list '回帰確認: 末尾4形式を除去し語頭・語中OKを保持' '一覧HTML出力境界fixture'
pass_id 1-28 '関連する実装の自己検査を実行'

require_marker 1-29 python-facts 'PASS: 1-29 独立ASTカウンター' '抽出器と独立再計数'
if grep -q 'PASS: 1-30 本番再計数ゲートが分類間span重複を拒否' "$tmp/python-facts.log" \
  && grep -q 'PASS: 1-30 本番再計数ゲートがsource_span全削除を拒否' "$tmp/python-facts.log" \
  && grep -q 'PASS: 1-30 本番再計数ゲートがsource_span1件削除を拒否' "$tmp/python-facts.log" \
  && grep -q 'PASS: 1-30 本番再計数ゲートが不正span範囲を拒否' "$tmp/python-facts.log" \
  && grep -q 'PASS: 1-30 本番再計数ゲートがevidence・target外pathを拒否' "$tmp/python-facts.log"; then
  pass_id 1-30 '本番span排他・完全性ゲートの5陰性fixture'
else
  echo "FAIL: 1-30 本番span排他・完全性の陰性fixtureが不足" >&2
  exit 1
fi
require_marker 1-31 python-facts 'PASS: 1-31 構文決定性' '実測委譲の構文決定性分類'
if grep -q 'PASS.*1-32: key/value外側引用符' "$tmp/seal-facts.log" \
  && grep -q 'PASS.*1-32陰性: 引用符内改行escape' "$tmp/seal-facts.log" \
  && grep -q 'PASS.*1-32陰性: 文字列null' "$tmp/seal-facts.log"; then
  pass_id 1-32 'YAML意味型を保つ再現性canonicalization'
else
  echo "FAIL: 1-32 canonicalizationの陽性・陰性fixtureが不足" >&2
  exit 1
fi
require_marker 1-33 python-facts 'PASS: 1-33 ' '関数本文先頭行だけの陰性fixture'
require_marker 1-34 prefill-design '\[PASS\] 1-34:' '全Markdown表の列数検査'
require_marker 1-35 prefill-design '\[PASS\] 1-35: 関数本文を改行付きコードブロックへ展開' '関数本文の忠実展開'
require_marker 1-36 fact-coverage '\[PASS\] 1-36:' '拡張子非依存の座標ノイズ除去'
require_marker 1-37 consistency-audit '\[PASS\] 1-37陽性:' 'repo内path列と偽リンクの対照fixture'
require_marker 1-38 consistency-audit '\[PASS\] 1-38陰性:' '併記観点キーの陽性・陰性fixture'
require_marker 1-39 consistency-audit '\[PASS\] 1-39陰性:' '真の未記入placeholder陰性fixture'
require_marker 1-40 screen-metadata '\[PASS\] 1-40:' '実在する設計書4リンクだけを付与'
require_marker 1-41 screen-metadata '\[PASS\] 1-41:' '設計書確定画面名の書き戻し'
require_marker 1-42 screen-list '\[PASS\] 1-42:' '画面キー・ID・entryFile検索索引'
require_marker 1-43 screen-list '\[PASS\] 1-43:' '完成HTMLの表行再計数と欠落陰性fixture'
require_marker 1-44 screen-list '\[PASS\] 1-44:' '任意portalの実在index解決fixture'
require_marker 1-45 python-facts 'PASS: 1-45 facts封印後にscaffold' 'facts封印後scaffold縦貫fixture'
require_marker 1-46 python-facts 'PASS: 1-46 非UTF-8原本' 'PEP 263入力の抽出・再計数'
require_marker 1-47 python-facts 'PASS: 1-47 抽出factsと独立再計数' '抽出・再計数・封印の縦貫fixture'

# 実装判断: diff -u <(...) <(...) （プロセス置換）を使わない。macOS の bash は
# プロセス置換のFIFOを $TMPDIR ではなく /tmp 直下（sh-np-*）へ作るため、
# サンドボックス実行環境では「diff: /dev/fd/N: Operation not permitted」で
# 失敗する（実測2026-08-28。トリビアルな `diff <(echo a) <(echo a)` でも再現）。
# $tmp（本スクリプト冒頭で ${TMPDIR:-/tmp} 配下に作成済み・書き込み確認済み）
# へ両辺をファイルとして書き出してから diff することで、プロセス置換を避ける。
printf '%s\n' "$expected_ids" | sort -V > "$tmp/expected_ids.sorted"
sort -V "$passed_ids" > "$tmp/passed_ids.sorted"
if [ "$(wc -l < "$passed_ids" | tr -d ' ')" -ne 29 ] \
  || [ "$(sort -u "$passed_ids" | wc -l | tr -d ' ')" -ne 29 ] \
  || ! diff -u "$tmp/expected_ids.sorted" "$tmp/passed_ids.sorted"; then
  echo "FAIL: 実行済み番号付き検証が29件に一致しません" >&2
  exit 1
fi

echo "PASS: 写真指摘29件の番号付き検証を全件実行（29/29）"
