#!/usr/bin/env bash
set -euo pipefail

# 改善課題 1-138: 横断検収条件（本番経路スクリプトへの --self-test 実装）に対応する。
# 必要性: AGENTS.md/CLAUDE.md の共通索引・規約読み込み分離検査は creating-new-project 系の
#   本番経路で使われる決定的チェックであり、正常系（索引語すべて揃う）・異常系（索引語欠落）を
#   自己テストで固定しておくことで、検査条件を変更した際のリグレッションを検知できる。
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-agent-config-index-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT

  mkdir -p "$tmp/docs"
  echo "example" > "$tmp/docs/example.md"
  cat > "$tmp/AGENTS.valid.md" <<'MD'
# AGENTS.md

技術スタック / 実行コマンド / ディレクトリ / リバース対象 / 正本 / 派生 / 調査入口 / 検証

## 後半

正確な参照パス: `docs/example.md`
MD
  cat > "$tmp/CLAUDE.valid.md" <<'MD'
# CLAUDE.md

技術スタック / 実行コマンド / ディレクトリ / リバース対象 / 正本 / 派生 / 調査入口 / 検証
MD

  pass=0 fail=0
  if bash "${BASH_SOURCE[0]}" "$tmp/AGENTS.valid.md" "$tmp/CLAUDE.valid.md" >/dev/null 2>&1; then
    echo "PASS: 正常系（索引語すべて揃う）で終了コード0"; pass=$((pass + 1))
  else
    echo "FAIL: 正常系で終了コード0になるべき"; fail=$((fail + 1))
  fi

  cat > "$tmp/AGENTS.invalid.md" <<'MD'
# AGENTS.md

技術スタック / 実行コマンド / ディレクトリ / リバース対象 / 正本 / 派生 / 調査入口

## 後半

正確な参照パス: `README.md`
MD
  if bash "${BASH_SOURCE[0]}" "$tmp/AGENTS.invalid.md" "$tmp/CLAUDE.valid.md" >/dev/null 2>&1; then
    echo "FAIL: 異常系（索引語「検証」欠落）で終了コード1になるべき"; fail=$((fail + 1))
  else
    echo "PASS: 異常系（索引語欠落）で終了コード1"; pass=$((pass + 1))
  fi

  # 1-143: 実在確認の基準ディレクトリを、索引の記載対象の帰属先に応じて切り替えられること。
  # 対象リポジトリのパスは対象リポジトリ（第3引数 TARGET_ROOT）を基準に実在確認する。
  mkdir -p "$tmp/target-repo/app"
  echo "config = {}" > "$tmp/target-repo/app/config.py"

  cat > "$tmp/AGENTS.target-present.md" <<'MD'
# AGENTS.md

技術スタック / 実行コマンド / ディレクトリ / リバース対象 / 正本 / 派生 / 調査入口 / 検証

## 後半

正確な参照パス: `app/config.py`
MD
  if bash "${BASH_SOURCE[0]}" "$tmp/AGENTS.target-present.md" "$tmp/CLAUDE.valid.md" "$tmp/target-repo" >/dev/null 2>&1; then
    echo "PASS: 対象リポジトリを基準に実在するパスは終了コード0"; pass=$((pass + 1))
  else
    echo "FAIL: 対象リポジトリを基準に実在するパスは終了コード0になるべき"; fail=$((fail + 1))
  fi

  cat > "$tmp/AGENTS.target-missing.md" <<'MD'
# AGENTS.md

技術スタック / 実行コマンド / ディレクトリ / リバース対象 / 正本 / 派生 / 調査入口 / 検証

## 後半

正確な参照パス: `app/missing_module.py`
MD
  if bash "${BASH_SOURCE[0]}" "$tmp/AGENTS.target-missing.md" "$tmp/CLAUDE.valid.md" "$tmp/target-repo" >/dev/null 2>&1; then
    echo "FAIL: 対象リポジトリに存在しないパスで終了コード1になるべき"; fail=$((fail + 1))
  else
    echo "PASS: 対象リポジトリに存在しないパスで終了コード1"; pass=$((pass + 1))
  fi

  echo "self-test: $pass PASS, $fail FAIL"
  if [ "$fail" -eq 0 ]; then exit 0; else exit 1; fi
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AGENTS_PATH="${1:-${ROOT}/shared/templates/ai-assets/AGENTS.md}"
CLAUDE_PATH="${2:-${ROOT}/shared/templates/ai-assets/CLAUDE.md}"
# 1-143: 索引が列挙するパスの帰属先。既定は AGENTS.md 自身の配置ディレクトリ（後方互換）。
# 対象リポジトリ向けに生成された索引を検証する場合は、対象リポジトリのルートを渡す。
TARGET_ROOT="${3:-$(dirname "${AGENTS_PATH}")}"

python3 - "${AGENTS_PATH}" "${CLAUDE_PATH}" "${TARGET_ROOT}" <<'PY'
from pathlib import Path
import re
import sys

agents = Path(sys.argv[1])
claude = Path(sys.argv[2])
target_root = Path(sys.argv[3])
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

# 1-143: 索引に列挙されたパスは帰属先に応じて基準ディレクトリを切り替えて実在確認する。
# reverse-docs-skills 自身の資産（4接頭辞）は AGENTS.md の配置ディレクトリを基準にし、
# それ以外（対象リポジトリのディレクトリ構成を列挙するパス）は target_root を基準にする。
# 旧実装は4接頭辞に一致しないパスを実在確認の対象外としていたため、対象リポジトリの
# パス（本来の索引記載対象の大半）が一度も検証されていなかった。
own_prefixes = (".claude/", "shared/", "README.md", "docs/reverse-docs-overview.html")
for raw_path in re.findall(r"`([^`]+)`", agents_text):
    if any(mark in raw_path for mark in ("{{", "<", ">", "*")):
        continue
    base = agents.parent if raw_path.startswith(own_prefixes) else target_root
    candidate = (base / raw_path).resolve()
    if not candidate.exists():
        raise SystemExit(f"FAIL: AGENTS.md references missing path: {raw_path} (base={base})")

print("PASS: AGENTS/CLAUDE common index and rule-loading split")
PY
