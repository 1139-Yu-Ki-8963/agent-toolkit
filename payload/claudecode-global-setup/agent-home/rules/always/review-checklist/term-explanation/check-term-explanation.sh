#!/usr/bin/env bash
# Stop hook: scan the final assistant text for opaque abbreviations used without
# a gloss (full form / inline explanation). Block the turn via decision:block if
# found. Self-disables after 3 detections in the same session to avoid livelock.
#
# Blocklist entries are "TOKEN|GLOSS_REGEX":
#   - TOKEN is matched as an ASCII word (boundary-aware, case-insensitive).
#   - An occurrence is a violation only if NONE of these hold anywhere in the text:
#       * the token is immediately followed by a Japanese opening paren  TOKEN（
#       * the GLOSS_REGEX matches (full form / explanation present)
# So "コミット SHA（ハッシュ）" or text containing "ハッシュ" passes; a bare "SHA" blocks.
#
# 設計判断は同ディレクトリの design-notes.txt に記載。

set -uo pipefail

. "$HOME/agent-home/tools/hooks/shared/marker-path.sh"

# Recursion / summary guards (align with other response hooks)
[ -n "${CLAUDE_HOOK_TERM_EXPLANATION_RUNNING:-}" ] && exit 0
[ -n "${CLAUDE_HOOK_SUMMARY_RUNNING:-}" ] && exit 0
[ -n "${CLAUDE_HOOK_DICT_RUNNING:-}" ] && exit 0
[ -n "${CLAUDE_HOOK_AUTOCOMMIT_RUNNING:-}" ] && exit 0
[ -n "${CLAUDE_HOOK_FLOW_REPORT_RUNNING:-}" ] && exit 0

input="$(cat)"

stop_active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$stop_active" = "true" ] && exit 0

# Skip in plan mode (design discussion, not deliverable prose)
pmode=$(printf '%s' "$input" | jq -r '.permission_mode // empty' 2>/dev/null)
[ -z "$pmode" ] && {
  _tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
  [ -n "$_tp" ] && [ -f "$_tp" ] && \
    pmode=$(tail -c 10000 "$_tp" 2>/dev/null \
      | grep -o '"permissionMode":"[^"]*"' | tail -1 | cut -d'"' -f4 || true)
}
[ "$pmode" = "plan" ] && exit 0

tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -z "$tp" ] && exit 0
[ ! -f "$tp" ] && exit 0

last=$( { { tac "$tp" 2>/dev/null || tail -r "$tp" 2>/dev/null; } | jq -c 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' 2>/dev/null | head -1; } || true )
[ -z "$last" ] && exit 0

# Blocklist: opaque abbreviations that almost always need a gloss in JP prose.
# TOKEN|GLOSS_REGEX  (extend this list as new offenders are observed)
BLOCKLIST='
ref|参照|リファレンス
SHA|ハッシュ|コミット
drvfs|ファイルシステム
HMR|ホットリロード|ホットモジュール
MSW|モックサーバー|Mock Service Worker|モック[[:space:]]*サービス
'

offenders=""
while IFS= read -r line; do
  [ -z "$line" ] && continue
  token="${line%%|*}"
  gloss="${line#*|}"
  # token present as an ASCII word (not part of a longer word)?
  printf '%s' "$last" | grep -qiE "(^|[^A-Za-z])${token}([^A-Za-z]|\$)" || continue
  # inline gloss: TOKEN immediately followed by a Japanese opening paren?
  printf '%s' "$last" | grep -qE "${token}（" && continue
  # full-form / explanation present anywhere?
  printf '%s' "$last" | grep -qiE "${gloss}" && continue
  offenders="${offenders}${token} "
done <<EOF
$(printf '%s' "$BLOCKLIST")
EOF

[ -z "$offenders" ] && exit 0

session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session" ] && exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"
counter_file="$(marker_path "$cwd" "$session" term-explanation.count)"
hits=0
[ -f "$counter_file" ] && hits=$(cat "$counter_file" 2>/dev/null || echo 0)
hits=$((hits + 1))
printf '%d' "$hits" > "$counter_file"

if [ "$hits" -ge 3 ]; then
  # Livelock guard: third+ detection in same session — let it through.
  exit 0
fi

ctx="[TERM-EXPLANATION-BLOCK] 最終応答に説明なしの略称を検出: ${offenders}。~/.claude/rules/always/review-checklist/term-explanation/rule.md を参照。"
jq -n --arg ctx "$ctx" '{"decision":"block","systemMessage":$ctx}'
exit 0
