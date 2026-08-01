#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
ledger="$repo_root/docs/ledgers/改善反映台帳.md"
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

actual_ids="$(
  awk '
    /^## 第24回（2026-07-28・写真指摘29件）$/ { in_section=1; next }
    in_section && /^## / { exit }
    in_section && /^\| 1-[0-9]+ / {
      id=$0
      sub(/^\| /, "", id)
      sub(/ .*/, "", id)
      print id
    }
  ' "$ledger"
)"

if [ "$(printf '%s\n' "$actual_ids" | sed '/^$/d' | wc -l | tr -d ' ')" -ne 29 ]; then
  echo "FAIL: 第24回の記録件数が29件ではありません" >&2
  exit 1
fi

if [ "$(printf '%s\n' "$actual_ids" | sort -u | wc -l | tr -d ' ')" -ne 29 ]; then
  echo "FAIL: 第24回のIDに重複があります" >&2
  exit 1
fi

if ! diff -u \
  <(printf '%s\n' "$expected_ids" | sort -V) \
  <(printf '%s\n' "$actual_ids" | sort -V); then
  echo "FAIL: 写真指摘29件と台帳IDが一致しません" >&2
  exit 1
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-photo-findings-29.XXXXXX")"
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
    echo "FAIL: $id の番号付き検証出力がありません（suite=$suite pattern=$pattern）" >&2
    sed 's/^/  /' "$tmp/$suite.log" >&2
    return 1
  fi
}

# すべて合成fixtureまたは契約self-testであり、外部の実データパスは要求しない。
run_suite detect-screens bash "$repo_root/shared/scripts/unit-list/detect-screens.sh" --self-test
run_suite table-metadata bash "$repo_root/shared/scripts/extract/extract-table-metadata.sh" --self-test
run_suite test-viewpoints bash "$repo_root/shared/scripts/extract/aggregate-test-viewpoints.sh" --self-test
run_suite authoring-inputs python3 "$repo_root/shared/scripts/validate-reverse-authoring-inputs.py" --self-test
run_suite python-facts env PYTHONDONTWRITEBYTECODE=1 bash "$repo_root/shared/scripts/tests/test-python-facts-flow.sh"
run_suite seal-facts bash "$repo_root/shared/scripts/seal-facts.sh" --self-test
run_suite prefill-design bash "$repo_root/shared/scripts/prefill-design-from-facts.sh" --self-test
run_suite fact-coverage bash "$repo_root/.claude/skills/generating-reverse-detailed-design/scripts/check-fact-coverage.sh" --self-test
run_suite consistency-audit bash "$repo_root/shared/scripts/audit-consistency.sh" --self-test
run_suite screen-metadata bash "$repo_root/shared/scripts/extract/extract-screen-metadata.sh" --self-test
run_suite screen-list bash "$repo_root/shared/scripts/unit-list/build-screen-list.sh" --self-test

require_marker 1-9 detect-screens 'PASS: 1-9-' 'hasTemplateの1,001件超・UI分類fixture'
require_marker 1-10 detect-screens 'PASS: 1-10-' '分離テンプレートmodal/popup陽性・陰性fixture'
require_marker 1-16 table-metadata '\[PASS\] 1-16:' '複数DDLテーブルのSIGPIPE陰性fixture'
require_marker 1-19 test-viewpoints 'self-test PASS: テスト観点表の集約→検証→HTML→ポータル連結' 'test_viewpoint専用pipeline'
require_marker 1-23 authoring-inputs 'PASS: 1-23 ' 'original.png×facts jsxの4分岐'
require_marker 1-24 authoring-inputs 'PASS: 1-24 ' 'scenarios必須値・省略・証跡の実動分岐'
require_marker 1-25 detect-screens 'PASS: 1-25-' '末尾マーカー除去と業務語保持fixture'

if [ "$(grep -Fc 'name_guess="$(strip_ok_marker "$name_guess")"' \
    "$repo_root/shared/scripts/unit-list/detect-screens.sh")" -ge 2 ] \
  && grep -q '手作業で.*screenNameGuess.*末尾' "$screen_skill"; then
  pass_id 1-26 '再代入後の再正規化と手作業契約'
else
  echo "FAIL: 1-26 全生成経路の再正規化契約が不足" >&2
  exit 1
fi

require_marker 1-27 screen-list '回帰確認: 末尾4形式を除去し語頭・語中OKを保持' '一覧HTML出力境界fixture'
if grep -q '^| 1-28 .*呼出経路・後続破棄なし・self-testの3条件' "$ledger"; then
  pass_id 1-28 '完了記帳の実効性3条件'
else
  echo "FAIL: 1-28 完了記帳の3条件が台帳にありません" >&2
  exit 1
fi

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

if [ "$(wc -l < "$passed_ids" | tr -d ' ')" -ne 29 ] \
  || [ "$(sort -u "$passed_ids" | wc -l | tr -d ' ')" -ne 29 ] \
  || ! diff -u \
      <(printf '%s\n' "$expected_ids" | sort -V) \
      <(sort -V "$passed_ids"); then
  echo "FAIL: 実行済み番号付き検証が29件に一致しません" >&2
  exit 1
fi

echo "PASS: 写真指摘29件の番号付き検証を全件実行（29/29）"
