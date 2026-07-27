#!/usr/bin/env bash
# check-mock-html.sh — PostToolUse(Write|Edit|MultiEdit) hook
#
# 仕様: ~/agent-home/skills/orchestrating-dev-flow/references/creating-screen-mock-conventions.md
# の 13 セクション定義を検査する。skill marker（先頭 1KB 以内の
# `generated-by: creating-mock`）を持つ HTML のみを対象とし、
# background / proposal / acceptance / placement / related / risks /
# db-schema / domain-logic / api-contract / role-visibility / screen-flow /
# acceptance-tests の id 属性、および header の
# `<h1 class="mock-title">` の存在を確認する。
#
## 設計判断
#
# 必要性: creating-screen-mock-conventions.md / module-creating-screen-mock.md は
# 「PostToolUse hook check-mock-html.sh が検証する」と記述していたが、当該スクリプトは
# 実在しなかった（doc rot）。目視レビューのみでは 13 セクションの徹底が保証されないため、
# 規約が参照している検査を実体化する。
#
# 代替案を採用しなかった理由:
# - Bash ツール直叩き: mock HTML の Write/Edit 発生ごとに手動 grep するのは非現実的で
#   継続的な機械強制にならない
# - 既存 Makefile 拡張 / package.json scripts 追加: 本リポジトリにビルド設定は存在せず、
#   新規導入は本チェック専用の依存を増やすだけになる
#
# 保守責任者: 人手（ユーザー）。必須セクションの追加・変更時は本スクリプトと
# creating-screen-mock-conventions.md / module-creating-screen-mock.md /
# creating-screen-mock-template.html を同時に更新する。
#
# 廃棄条件: creating-mock によるモック HTML 生成規約自体が廃止された時。

set -uo pipefail

input="$(cat)"
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$file" ] && exit 0

case "${file##*.}" in
  html) ;;
  *) exit 0 ;;
esac

[ -f "$file" ] || exit 0

head_bytes=$(head -c 1024 "$file" 2>/dev/null)
case "$head_bytes" in
  *"generated-by: creating-mock"*) ;;
  *) exit 0 ;;
esac

missing=()

for id in background proposal acceptance placement related risks db-schema domain-logic api-contract role-visibility screen-flow acceptance-tests; do
  if ! grep -q "id=\"${id}\"" "$file" 2>/dev/null; then
    missing+=("$id")
  fi
done

if ! grep -q '<h1 class="mock-title">' "$file" 2>/dev/null; then
  missing+=("header(h1.mock-title)")
fi

if [ "${#missing[@]}" -gt 0 ]; then
  joined=$(IFS=,; echo "${missing[*]}")
  echo "[MOCK-HTML-BLOCK] モック HTML に必須セクションが欠けています: ${joined}。~/agent-home/skills/orchestrating-dev-flow/references/creating-screen-mock-conventions.md の 13 セクション定義に従い追加してください。" >&2
  exit 2
fi

exit 0
