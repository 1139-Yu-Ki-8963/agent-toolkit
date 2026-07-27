#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AGENTS_PATH="${1:-${ROOT}/shared/templates/ai-assets/AGENTS.md}"
CLAUDE_PATH="${2:-${ROOT}/shared/templates/ai-assets/CLAUDE.md}"

python3 - "${AGENTS_PATH}" "${CLAUDE_PATH}" <<'PY'
from pathlib import Path
import re
import sys

agents = Path(sys.argv[1])
claude = Path(sys.argv[2])
for path in (agents, claude):
    if not path.is_file():
        raise SystemExit(f"FAIL: missing {path}")

agents_text = agents.read_text()
claude_text = claude.read_text()
required = (
    "技術スタック",
    "実行コマンド",
    "ディレクトリ",
    "リバース対象",
    "正本",
    "派生",
    "調査入口",
    "検証",
)
for label in required:
    if label not in agents_text or label not in claude_text:
        raise SystemExit(f"FAIL: common index item missing: {label}")

if re.search(r"(?m)^.*docs/rules/", claude_text):
    raise SystemExit("FAIL: CLAUDE.md contains duplicated rule index/body")

if re.search(r"(?m)^## .*規約.*(一覧|読み込み)", claude_text):
    raise SystemExit("FAIL: CLAUDE.md contains a rule-loading section")

if "## 後半" not in agents_text or "正確な参照パス" not in agents_text:
    raise SystemExit("FAIL: AGENTS.md lacks the rule-reference section")

for raw_path in re.findall(r"`([^`]+)`", agents_text):
    if any(mark in raw_path for mark in ("{{", "<", ">", "*")):
        continue
    candidate = (agents.parent / raw_path).resolve()
    if raw_path.startswith((".claude/", "shared/", "README.md", "reverse-docs-overview.html")) and not candidate.exists():
        raise SystemExit(f"FAIL: AGENTS.md references missing path: {raw_path}")

print("PASS: AGENTS/CLAUDE common index and rule-loading split")
PY
