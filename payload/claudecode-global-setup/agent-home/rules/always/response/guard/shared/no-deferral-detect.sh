#!/usr/bin/env bash
# Detects "残作業を別 PR/issue で先送り" patterns in a markdown body file.
# Usage: lib/no-deferral-detect.sh <body-file>
# Stdout: matching lines (when forbidden phrases found).
# Exit:   0 = clean, 1 = forbidden phrases detected, 2 = usage error.

set -euo pipefail

[ "$#" -ge 1 ] || exit 2
FILE="$1"
[ -r "$FILE" ] || exit 2

PATTERN='別[[:space:]]*(PR|issue|プルリク|チケット)[[:space:]]*(で|を|に)?[[:space:]]*(対応|起票|分割|切り出|作成|作る|実装)|別途[[:space:]]*(PR|issue|チケット)|次の[[:space:]]*PR|新規[[:space:]]*issue[[:space:]]*を?[[:space:]]*(起票|作成|起こ)|残(課題|作業|タスク)|将来[[:space:]]*課題|今後の?[[:space:]]*(課題|対応)|後日[[:space:]]*対応|Phase[[:space:]]*[2-9][[:space:]]*以降|次回[[:space:]]*(対応|実装|セッション)'

matches=$(grep -nE "$PATTERN" "$FILE" 2>/dev/null || true)
[ -z "$matches" ] && exit 0

# Exclude:
#   - "### 未実施・残課題" heading
#   - direct bullet under that heading whose value is "なし" / "特になし" / "<!-- ... -->"
filtered=$(printf '%s\n' "$matches" | grep -vE '^[0-9]+:### 未実施・残課題[[:space:]]*$|^[0-9]+:-[[:space:]]+(なし|特になし|<!--)' || true)

[ -z "$filtered" ] && exit 0

printf '%s\n' "$filtered"
exit 1
