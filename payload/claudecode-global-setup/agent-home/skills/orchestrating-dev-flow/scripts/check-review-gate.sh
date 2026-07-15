#!/usr/bin/env bash
set -euo pipefail

# check-review-gate.sh
# git push / gh pr create 時に review_gates の PASS マーカーを検証。
# flow-values.yml に review_gates が未設定ならスキップ（exit 0）。

input="$(cat)"
command="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"

# git push / gh pr create 以外はスキップ
case "$command" in
  *"git push"*|*"gh pr create"*) ;;
  *) exit 0 ;;
esac

cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$cwd" ] && cwd="$PWD"

fc="$cwd/.claude/rules/always/project-context/flow-values.yml"
[ ! -f "$fc" ] && exit 0

# review_gates セクションを grep/awk で抽出（PyYAML 不要）
gates=""
in_section=false
while IFS= read -r line; do
  case "$line" in
    "review_gates:"*)
      in_section=true
      continue
      ;;
  esac
  if $in_section; then
    case "$line" in
      "  "*)
        key=$(printf '%s' "$line" | sed 's/^  //;s/:.*//')
        val=$(printf '%s' "$line" | sed 's/^[^:]*: *//')
        [ -n "$key" ] && [ -n "$val" ] && gates="${gates}${key}:${val}\n"
        ;;
      *)
        break
        ;;
    esac
  fi
done < "$fc"
gates=$(printf '%b' "$gates" | grep -v '^$' || true)

[ -z "$gates" ] && exit 0

. "$HOME/agent-home/tools/hooks/shared/marker-path.sh"
session="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-${SESSION_ID:-unknown}}}"

missing=""
while IFS=: read -r gate_name skill_name; do
  marker_a="$(marker_path "$cwd" "$session" "${skill_name}.pass")"
  marker_b="${TMPDIR:-/tmp}/claude-hooks/${session}/${skill_name}.pass"
  found=false
  if [ -f "$marker_a" ] || [ -f "$marker_b" ]; then
    found=true
  fi
  # マーカーを書く側（ハーネス環境）と検査する側（sandbox 化 Bash）で
  # session/TMPDIR の解決が食い違うことがあるため、全 session ディレクトリを
  # glob で横断検索するフォールバックを設ける（managing-agent-configs の
  # needed マーカー検索と同じ先例）。
  if ! $found; then
    for f in "$cwd"/.claude/markers/*/"${skill_name}.pass" \
             "${TMPDIR:-/tmp}"/claude-hooks/*/"${skill_name}.pass" \
             /tmp/claude-hooks/*/"${skill_name}.pass"; do
      if [ -f "$f" ]; then
        found=true
        break
      fi
    done
  fi
  if ! $found; then
    missing="${missing}${gate_name}(${skill_name}) "
  fi
done <<< "$gates"

if [ -n "$missing" ]; then
  printf '{"systemMessage":"[フック発火] レビューゲート: 未通過ゲートあり","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"[REVIEW-GATE-BLOCK] 以下のレビューゲートが未通過: %s。該当するレビュースキルを実行すること。"}}' "$missing"
  printf '[REVIEW-GATE-BLOCK] 以下のレビューゲートが未通過: %s。該当するレビュースキルを実行すること。\n' "$missing" >&2
  exit 2
fi

exit 0
