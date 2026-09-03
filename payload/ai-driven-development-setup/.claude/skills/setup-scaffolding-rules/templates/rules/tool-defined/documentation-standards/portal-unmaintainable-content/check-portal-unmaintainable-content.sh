#!/usr/bin/env bash
# ポータルと設計書へ廃止した根拠の列または対象コードの写しを載せない。
#
# 判定メッセージに付けた規則名ラベルについて:
#   規約「生成した文書を直接編集しない決まり」（portal-maintenance）は
#   「保守できない参照を載せない」「対象コードの中身を写さない」の2規則を
#   持ち、どちらの検査列も本検査を名指しする。規則と検査の対応を測る検査
#   （validate-rule-judgment-coverage.sh）は、検査スクリプトの中で「拒否」
#   「通知」「許可」「対象外」のいずれかの語に続けて規則名を大括弧で囲んだ形
#   （下記 judge_content 関数の出力を参照）が出ている箇所を静的に数える
#   ため、ラベルが無いと判定が0件と数えられる。2026-08-28の実測で、本検査は
#   この形の出力を1件も持たず、規約全体で「不足」（規則4件/判定1件）に
#   数えられていた。廃止した「根拠」「根拠パス」の列見出しの検出は
#   「保守できない参照を載せない」、コード柵・pre code・演算子を含む
#   インラインの検出は「対象コードの中身を写さない」に対応する。規則名は
#   規約の「## 規則」表の値と一字一句同じに
#   する必要がある。
set -uo pipefail

STRICT=0

judge_content() {
  local content="$1" source="$2" hits=0
  if printf '%s\n' "$content" | LC_ALL=C grep -qE '\|[[:space:]]*(根拠|根拠パス)[[:space:]]*\|'; then
    printf '%s\n' "拒否[保守できない参照を載せない]: [FOUND] ${source}: 廃止した根拠の列または根拠パス列"
    hits=$((hits + 1))
  fi
  if printf '%s\n' "$content" | LC_ALL=C grep -qE '<pre[^>]*>[[:space:]]*<code|(^|[[:space:]])```[[:alnum:]_-]*[[:space:]]*$'; then
    printf '%s\n' "拒否[対象コードの中身を写さない]: [FOUND] ${source}: コード柵または pre code"
    hits=$((hits + 1))
  fi
  if printf '%s\n' "$content" | LC_ALL=C grep -qE '`[^`]*(=>|==|!=|[[:space:]]=[[:space:]]|;|\{|\})[^`]*`'; then
    printf '%s\n' "拒否[対象コードの中身を写さない]: [FOUND] ${source}: インラインまたは表セル内の実装断片"
    hits=$((hits + 1))
  fi
  return "$hits"
}

scan_path() {
  local target="$1" file found=0 code
  if [ -f "$target" ]; then
    if judge_content "$(cat "$target")" "$target"; then :; else found=1; fi
  elif [ -d "$target" ]; then
    while IFS= read -r file; do
      case "$file" in
        */rules/checkers/*|*/rules/tool-defined/*|*/docs/rules/*) continue ;;
      esac
      if judge_content "$(cat "$file")" "$file"; then code=0; else code=$?; fi
      [ "$code" -eq 0 ] || found=1
    done < <(find "$target" -type f \( -name '*.md' -o -name '*.html' \) -print)
  else
    printf '%s\n' "ERROR: 対象が見つからない: $target" >&2
    return 2
  fi
  return "$found"
}

self_test() {
  local failures=0 output code
  for value in "| 項目 | 根""拠 |" "| 項目 | 根""拠パス |" '```js
const copied = true;
```' '<pre><code>copied()</code></pre>' '| 算出 | `total = price * quantity` |'; do
    if output="$(judge_content "$value" fixture)"; then code=0; else code=$?; fi
    if [ "$code" -gt 0 ]; then printf '%s\n' '[PASS] 禁止対象を検出'; else printf '%s\n' "[FAIL] 未検出: $value"; failures=$((failures + 1)); fi
  done
  for value in '| 項目 | 参照先 |' '`src/service.ts` の processOrder 関数' '注文が有効なら処理を続ける'; do
    if output="$(judge_content "$value" fixture)"; then code=0; else code=$?; fi
    if [ "$code" -eq 0 ]; then printf '%s\n' '[PASS] 許可対象'; else printf '%s\n' "[FAIL] 誤検出: $value ($output)"; failures=$((failures + 1)); fi
  done
  printf '%s\n' "SELF-TEST: $((8 - failures)) PASS, ${failures} FAIL"
  [ "$failures" -eq 0 ]
}

run_hook() {
  local input content output code
  input="$(cat)"
  [ -z "$input" ] && return 0
  content="$(printf '%s' "$input" | jq -r '.tool_input.content // empty' 2>/dev/null)"
  [ -z "$content" ] && return 0
  if output="$(judge_content "$content" '書き込み内容')"; then code=0; else code=$?; fi
  [ "$code" -eq 0 ] && return 0
  printf '%s\n' "[PORTAL-UNMAINTAINABLE-CONTENT-BLOCK] ${output}" >&2
  return 2
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

if [ "${1:-}" = "--hook" ]; then
  run_hook
  exit $?
fi

if [ "${1:-}" = "--strict" ]; then
  STRICT=1
  shift
fi

if [ "$#" -eq 0 ]; then
  run_hook
  exit $?
fi

found=0
for target in "$@"; do
  if scan_path "$target"; then :; else code=$?; [ "$code" -eq 2 ] && exit 2; found=1; fi
done

if [ "$found" -eq 0 ]; then
  printf '%s\n' '合格: 廃止した根拠の列とコードの中身は無い'
  exit 0
fi
if [ "$STRICT" -eq 1 ]; then
  printf '%s\n' '不合格: ポータルで保守できない内容を検出した' >&2
  exit 2
fi
printf '%s\n' '報告: 既存違反を検出した。--strict では不合格になる'
exit 0
