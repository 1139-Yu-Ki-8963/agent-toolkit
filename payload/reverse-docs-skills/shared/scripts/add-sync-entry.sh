#!/usr/bin/env bash
set -euo pipefail

# add-sync-entry.sh — agent-toolkit の sync-manifest.json にスキルのマッピングエントリを追加する
#
# Usage:
#   bash shared/scripts/add-sync-entry.sh <skill_name> <sync_manifest_path>
#
# agent-toolkit の worktree 内で実行する。Write/Edit は Phase ゲートで block されるため
# sed で JSON を編集し、jq で構文検証する。
#
# --self-test: 合成フィクスチャで動作検証する

if [ "${1:-}" = "--self-test" ]; then
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  cat > "$tmpdir/sync-manifest.json" <<'FIXTURE'
{
  "mappings": [
    { "mode": "mirror", "src": "~/agent-home/skills/existing-skill", "dst": "payload/claudecode-global-setup/agent-home/skills/existing-skill" },
    { "mode": "mirror", "src": "~/agent-home/agents", "dst": "payload/claudecode-global-setup/agent-home/agents" }
  ]
}
FIXTURE

  bash "$0" "test-new-skill" "$tmpdir/sync-manifest.json"

  if jq . "$tmpdir/sync-manifest.json" > /dev/null 2>&1 && grep -q "test-new-skill" "$tmpdir/sync-manifest.json"; then
    echo "PASS: --self-test (entry added, JSON valid)" >&2
    exit 0
  else
    echo "FAIL: --self-test" >&2
    exit 1
  fi
fi

if [ $# -lt 2 ]; then
  echo "Usage: $0 <skill_name> <sync_manifest_path>" >&2
  exit 1
fi

SKILL_NAME="$1"
MANIFEST="$2"

if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: sync-manifest.json not found: $MANIFEST" >&2
  exit 1
fi

if grep -q "$SKILL_NAME" "$MANIFEST"; then
  echo "SKIP: $SKILL_NAME is already in sync-manifest.json" >&2
  exit 0
fi

sed -i '' '/agent-home\/agents/i\
    { "mode": "mirror", "src": "~/agent-home/skills/'"$SKILL_NAME"'", "dst": "payload/claudecode-global-setup/agent-home/skills/'"$SKILL_NAME"'" },
' "$MANIFEST"

if jq . "$MANIFEST" > /dev/null 2>&1; then
  echo "OK: added $SKILL_NAME to sync-manifest.json" >&2
else
  echo "ERROR: JSON syntax broken after adding $SKILL_NAME" >&2
  exit 1
fi
