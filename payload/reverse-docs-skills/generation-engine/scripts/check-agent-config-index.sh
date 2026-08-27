#!/usr/bin/env bash
set -euo pipefail

# 改善課題 1-138: 横断検収条件（本番経路スクリプトへの --self-test 実装）に対応する。
# 必要性: AGENTS.md/CLAUDE.md の共通索引・規約読み込み分離検査は creating-new-project 系の
#   本番経路で使われる決定的チェックであり、正常系（索引語すべて揃う）・異常系（索引語欠落）を
#   自己テストで固定しておくことで、検査条件を変更した際のリグレッションを検知できる。
if [ "${1:-}" = "--self-test" ]; then
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-agent-config-index-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼" >&2
    exit 2
  fi
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

  # 1-80: `不在: ` 印は、受領していない資料・除外資料・パスではない文言を
  # 正しく記録するためのもの。印付きの対象は実在してはならない。
  cat > "$tmp/AGENTS.marked-missing.md" <<'MD'
# AGENTS.md

技術スタック / 実行コマンド / ディレクトリ / リバース対象 / 正本 / 派生 / 調査入口 / 検証

## 後半

正確な参照パス: `不在: app/not_received.py`
MD
  marked_missing_out="$(bash "${BASH_SOURCE[0]}" "$tmp/AGENTS.marked-missing.md" "$tmp/CLAUDE.valid.md" "$tmp/target-repo" 2>&1)" || marked_missing_rc=$?
  if [ "${marked_missing_rc:-0}" -eq 0 ] && grep -qF '不在記録 1 件 / 不在確認 1 件' <<< "$marked_missing_out"; then
    echo "PASS: 不在印付きの不在パスは合格し、件数を出力する"; pass=$((pass + 1))
  else
    echo "FAIL: 不在印付きの不在パスは合格し、件数を出力するべき"; echo "$marked_missing_out"; fail=$((fail + 1))
  fi

  cat > "$tmp/AGENTS.marked-present.md" <<'MD'
# AGENTS.md

技術スタック / 実行コマンド / ディレクトリ / リバース対象 / 正本 / 派生 / 調査入口 / 検証

## 後半

正確な参照パス: `不在: app/config.py`
MD
  if bash "${BASH_SOURCE[0]}" "$tmp/AGENTS.marked-present.md" "$tmp/CLAUDE.valid.md" "$tmp/target-repo" >/dev/null 2>&1; then
    echo "FAIL: 不在印付きの実在パスで終了コード1になるべき"; fail=$((fail + 1))
  else
    echo "PASS: 不在印付きの実在パスで終了コード1"; pass=$((pass + 1))
  fi

  echo "self-test: $pass PASS, $fail FAIL"
  if [ "$fail" -eq 0 ]; then exit 0; else exit 1; fi
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AGENTS_PATH="${1:-${ROOT}/delivery-payload/templates/ai-assets/AGENTS.md}"
CLAUDE_PATH="${2:-${ROOT}/delivery-payload/templates/ai-assets/CLAUDE.md}"
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

# 判定対象は「規約本文または規約一覧の複製」に限定する。ディレクトリ構造の記載として
# `docs/rules/` というフォルダ名を1回書くのは正当であり（旧実装の行単位一致は
# ディレクトリ構造の記載と衝突していた）、複製とみなすのは次の3条件のいずれかのみとする。
# (1) RULES-INDEX マーカー（規約索引そのもの）を CLAUDE.md が持っている
# (2) 規約本文の見出し（## 規則 / ## 違反時の手順）がある
# (3) 具体的な規約ファイルへのパス（docs/rules/<親>/<子>/rule.md 形式）が2件以上並んでいる
if re.search(r"(?m)^\s*<!--\s*RULES-INDEX:(START|END)\s*-->", claude_text):
    raise SystemExit("FAIL: CLAUDE.md contains duplicated rule index/body")

if len(re.findall(r"docs/rules/[^\s`]+/[^\s`]+/rule\.md", claude_text)) >= 2:
    raise SystemExit("FAIL: CLAUDE.md contains duplicated rule index/body")

if re.search(r"(?m)^## .*規約.*(一覧|読み込み)", claude_text):
    raise SystemExit("FAIL: CLAUDE.md contains a rule-loading section")

if re.search(r"(?m)^##\s*(規則|違反時の手順)\b", claude_text):
    raise SystemExit("FAIL: CLAUDE.md contains a rule-loading section")

# AGENTS.md の規約読み込み節は、build-derived-rules.sh が生成する RULES-INDEX マーカー、
# または（自己テスト等の）明示的な参照パス記載のいずれかを持てば有効とみなす。
agents_has_marker = (
    "<!-- RULES-INDEX:START -->" in agents_text and "<!-- RULES-INDEX:END -->" in agents_text
)
agents_has_manual_ref = "正確な参照パス" in agents_text
if "## 後半" not in agents_text or not (agents_has_marker or agents_has_manual_ref):
    raise SystemExit("FAIL: AGENTS.md lacks the rule-reference section")

# 1-144: バッククォートで囲まれた文字列は「実在すべきファイルパス」とは限らない。
# フォルダ名の言及（`docs/rules/`）・front matter の項目説明（`status: approved`）・
# コマンド名（`npm run build`）・JSONキー参照（`scripts.build`）等、パスではない
# 説明的表記を無条件に実在チェックすると、正当な記述が誤って不合格になる
# （前回の `docs/rules` 行単位一致がディレクトリ構造の記載と衝突した問題と同種）。
# 次の7条件をすべて満たす文字列だけを「ファイルパスらしい」対象として絞り込む。
def looks_like_file_path(raw_path: str) -> bool:
    if "/" not in raw_path:  # (1) スラッシュを1つ以上含む
        return False
    if re.search(r"\s", raw_path):  # (3) 空白を含まない
        return False
    if raw_path.startswith("/"):  # (4) 先頭が / でない（絶対パスは対象外）
        return False
    if "://" in raw_path:  # (5) URL は対象外
        return False
    if any(ch in raw_path for ch in "*?[]"):  # (6) glob は対象外
        return False
    if any(ch in raw_path for ch in "<>"):  # (7) プレースホルダは対象外
        return False
    last_segment = raw_path.rsplit("/", 1)[-1]
    if "." not in last_segment:  # (2) 拡張子を持つ
        return False
    ext = last_segment.rsplit(".", 1)[-1]
    if not ext or not ext.isalnum():  # (2) 拡張子は1文字以上の英数字
        return False
    return True

# 1-143: 索引に列挙されたパスは帰属先に応じて基準ディレクトリを切り替えて実在確認する。
# reverse-docs-skills 自身の資産（5接頭辞）は AGENTS.md の配置ディレクトリを基準にし、
# それ以外（対象リポジトリのディレクトリ構成を列挙するパス）は target_root を基準にする。
# 旧実装は5接頭辞に一致しないパスを実在確認の対象外としていたため、対象リポジトリの
# パス（本来の索引記載対象の大半）が一度も検証されていなかった。
own_prefixes = (".claude/", "delivery-payload/", "generation-engine/", "README.md", "docs/guides/reverse-docs-overview.html")
marked_absent = 0
confirmed_absent = 0
for raw_path in re.findall(r"`([^`]+)`", agents_text):
    # 1-80: `不在: <相対パスまたは文言>` は、除外・未受領を明示する印である。
    # 通常のパス候補判定から外し、印と実態が食い違う（対象が存在する）場合だけ不合格にする。
    if raw_path.startswith("不在: "):
        marked_absent += 1
        absent_path = raw_path.removeprefix("不在: ")
        base = agents.parent if absent_path.startswith(own_prefixes) else target_root
        candidate = (base / absent_path).resolve()
        if candidate.exists():
            raise SystemExit(f"FAIL: AGENTS.md marks an existing path as absent: {absent_path} (base={base})")
        confirmed_absent += 1
        continue
    if "{{" in raw_path:
        continue
    if not looks_like_file_path(raw_path):
        continue
    base = agents.parent if raw_path.startswith(own_prefixes) else target_root
    candidate = (base / raw_path).resolve()
    if not candidate.exists():
        raise SystemExit(f"FAIL: AGENTS.md references missing path: {raw_path} (base={base})")

print(f"不在記録 {marked_absent} 件 / 不在確認 {confirmed_absent} 件")
print("PASS: AGENTS/CLAUDE common index and rule-loading split")
PY
