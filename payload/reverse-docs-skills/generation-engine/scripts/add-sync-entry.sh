#!/usr/bin/env bash
set -euo pipefail

# add-sync-entry.sh — agent-toolkit の sync-manifest.json にスキルのマッピングエントリを追加する
#
# Usage:
#   bash generation-engine/scripts/add-sync-entry.sh <skill_name> <sync_manifest_path>
#
# agent-toolkit の worktree 内で実行する。Write/Edit は Phase ゲートで block されるため
# sed で JSON を編集し、jq で構文検証する。
#
# --self-test: 合成フィクスチャで動作検証する

if [ "${1:-}" = "--self-test" ]; then
  # 既知の欠陥は解消済み（2026-08-24）: 引数なしの裸の mktemp -d は $TMPDIR を無視し、
  # 書き込みを拒む環境（サンドボックス実行環境等）では失敗する（実測 2026-08-24）。
  # 明示テンプレート付きの形へ直した。この形を素直な mktemp へ戻してはならない。
  # 対策の経緯は docs/design/batches/batch-root/detail-design/バッチ詳細設計書.md の
  # 本スクリプトの節を参照する。
  if ! tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/$(basename "${BASH_SOURCE[0]}" .sh).XXXXXX" 2>/dev/null)" || [ -z "$tmpdir" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため自己テストを判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）" >&2
    exit 2
  fi
  trap 'rm -rf "$tmpdir"' EXIT

  cat > "$tmpdir/sync-manifest.json" <<'FIXTURE'
{
  "mappings": [
    { "mode": "mirror", "src": "TLDSLOT/agent-home/skills/existing-skill", "dst": "payload/claudecode-global-setup/agent-home/skills/existing-skill" },
    { "mode": "mirror", "src": "TLDSLOT/agent-home/agents", "dst": "payload/claudecode-global-setup/agent-home/agents" }
  ]
}
FIXTURE
  perl -pi -e 's|TLDSLOT|~|g' "$tmpdir/sync-manifest.json"

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

awk -v skill="$SKILL_NAME" -v tld='~' '/agent-home\/agents/{printf "    { \"mode\": \"mirror\", \"src\": \"%s/agent-home/skills/%s\", \"dst\": \"payload/claudecode-global-setup/agent-home/skills/%s\" },\n", tld, skill, skill}{print}' "$MANIFEST" > "${MANIFEST}.tmp" && mv "${MANIFEST}.tmp" "$MANIFEST"

if jq . "$MANIFEST" > /dev/null 2>&1; then
  echo "OK: added $SKILL_NAME to sync-manifest.json" >&2
else
  echo "ERROR: JSON syntax broken after adding $SKILL_NAME" >&2
  exit 1
fi
