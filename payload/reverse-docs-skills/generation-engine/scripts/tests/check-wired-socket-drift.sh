#!/usr/bin/env bash
# 検査: ポータルカタログ(portal-catalog.json)に受け口が登録済み(= blueprints に kind として
# 存在する)種別について、対応するスキル(generator)の SKILL.md が自身の受け口を「未配線」と
# 記述したまま残っていないかを検査する。
#
# 背景: 「状態遷移図-配線済みの記述漏れの検査がない」改善課題。定義が「受け口は未配線」と書いた
# まま実装(portal-catalog.json)が先に配線され、記述が実態に追い越されていた事例
# (generating-entity-state-for-reverse-docs/SKILL.md が過去に「entity-stateのポータルカード
# 受け口は本スキル作成時点でbuild-portal.shに未配線であり」と書いていたが、2026-07-28時点で
# 既に配線済みだった)があり、同種のずれを機械で検知する検査がなかった。
#
# 判定方法(文字列一致): SKILL.md 内に「受け口」と「未配線」の両方を含む行があれば、その受け口を
# 自ら未配線と記述していると判定する。カタログに kind として登録されている = 受け口は配線済みの
# ため、そのスキルの SKILL.md がこの行を持つことは記述と実態の齟齬を意味する。
# 単独の「未配線」（例: generating-screen-list-for-reverse-docs の「ルート未配線の埋め込み
# ビュー」という別概念）を誤検出しないよう、同一行に「受け口」との共起を必須にする。
#
# Usage:
#   check-wired-socket-drift.sh [--catalog <portal-catalog.json>] [--skills-dir <dir>]
#   check-wired-socket-drift.sh --self-test
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DEFAULT_CATALOG="$SCRIPT_DIR/../../../delivery-payload/references/portal-catalog.json"
DEFAULT_SKILLS_DIR="$SCRIPT_DIR/../../../.claude/skills"
DRIFT_ERE='.*受け口.*未配線.*|.*未配線.*受け口.*'

run_check() {
  local catalog="$1" skills_dir="$2"
  local rc=0 kind generator skill_md hit

  while IFS=$'\t' read -r kind generator; do
    [ -z "$generator" ] && continue
    skill_md="$skills_dir/$generator/SKILL.md"
    [ -f "$skill_md" ] || continue
    hit="$(grep -nE -- "$DRIFT_ERE" "$skill_md" 2>/dev/null || true)"
    if [ -n "$hit" ]; then
      echo "FAIL: $generator(kind=$kind) の SKILL.md が配線済みの受け口を「未配線」と記述している" >&2
      echo "$hit" | sed "s|^|  ${skill_md}:|" >&2
      rc=1
    fi
  done < <(jq -r '.categories[].blueprints[] | [.kind, .generator] | @tsv' "$catalog")

  return "$rc"
}

self_test() {
  local tmp rc=0
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-wired-socket-drift-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' RETURN

  cat > "$tmp/catalog.json" <<'JSON'
{"schemaVersion":1,"categories":[{"key":"list","label":"一覧","group":"一覧","icon":"list","sub":"test","blueprints":[{"kind":"entity-state","label":"状態遷移図","group":"データ","icon":"sync","desc":"test","dir":"","generator":"fake-entity-state-skill","unit":"件","countFormat":"detail","discovery":{"artifactType":"entity-state-page","root":"output-dir","glob":"x.html","matchKind":"file","titleSource":"blueprint-label","dirSource":"blueprint","instanceKeySource":"relative-path","sort":"relative-path-bytewise"}},{"kind":"screen","label":"画面一覧","group":"画面","icon":"monitor","desc":"test","dir":"","generator":"fake-screen-list-skill","unit":"画面","countFormat":"unit-count","discovery":{"artifactType":"screen-list-page","root":"output-dir","glob":"y.html","matchKind":"file","titleSource":"blueprint-label","dirSource":"blueprint","instanceKeySource":"relative-path","sort":"relative-path-bytewise","embeddedScriptId":"screen-manifest","countJsonPointer":"/screens"}}]}]}
JSON

  # --- 修正前を模した固定: 配線済み(entity-state)の生成スキルが「受け口...未配線」と記述 ---
  mkdir -p "$tmp/skills-before/fake-entity-state-skill" "$tmp/skills-before/fake-screen-list-skill"
  cat > "$tmp/skills-before/fake-entity-state-skill/SKILL.md" <<'EOF'
# entity-state
状態遷移図のポータルカード受け口は本スキル作成時点で未配線である。
EOF
  # 別概念の「未配線」（受け口との共起なし）を誤検出しないことも同時に確認する対照フィクスチャ
  cat > "$tmp/skills-before/fake-screen-list-skill/SKILL.md" <<'EOF'
# screen-list
ルート未配線の埋め込みビュー・休眠画面は対象外とする。
EOF

  if run_check "$tmp/catalog.json" "$tmp/skills-before" >"$tmp/before.out" 2>&1; then
    echo "  [FAIL] 修正前フィクスチャ: 配線済みなのに「未配線」と記述した SKILL.md を検出できず通過した" >&2
    rc=1
  else
    echo "  [PASS] 修正前フィクスチャ: 配線済みの受け口を「未配線」と記述した SKILL.md を検出しexit 1"
  fi
  if grep -q 'fake-entity-state-skill' "$tmp/before.out"; then
    echo "  [PASS] 修正前フィクスチャ: FAIL対象として entity-state 側が報告される"
  else
    echo "  [FAIL] 修正前フィクスチャ: entity-state 側がFAIL報告に含まれない" >&2
    rc=1
  fi
  if grep -q 'fake-screen-list-skill' "$tmp/before.out"; then
    echo "  [FAIL] 誤検出: 受け口と無関係な「未配線」（ルート未配線の埋め込みビュー）が誤検出された" >&2
    rc=1
  else
    echo "  [PASS] 誤検出防止: 受け口と無関係な「未配線」の文言は検出対象にならない"
  fi

  # --- 修正後を模した固定: 「未配線」の記述を削除(実態=配線済みへ追従) ---
  mkdir -p "$tmp/skills-after/fake-entity-state-skill" "$tmp/skills-after/fake-screen-list-skill"
  cat > "$tmp/skills-after/fake-entity-state-skill/SKILL.md" <<'EOF'
# entity-state
本スキルはポータルの受け口のうち状態遷移図（T7）を担う。
EOF
  cp "$tmp/skills-before/fake-screen-list-skill/SKILL.md" "$tmp/skills-after/fake-screen-list-skill/SKILL.md"

  if _gt_out1="$(run_check "$tmp/catalog.json" "$tmp/skills-after" 2>&1)"; then
    echo "  [PASS] 修正後フィクスチャ: 記述を実態へ揃えた SKILL.md は検出されずexit 0"
  else
    echo "  [FAIL] 修正後フィクスチャ: 記述を揃えたはずなのにFAILになった" >&2
    printf '%s\n' "$_gt_out1" | sed 's/^/    /' >&2
    rc=1
  fi

  # --- 現行リポジトリの実データ: 現時点で配線済み記述ずれが無いことを確認する ---
  if _gt_out2="$(run_check "$DEFAULT_CATALOG" "$DEFAULT_SKILLS_DIR" 2>&1)"; then
    echo "  [PASS] 現行リポジトリ: 配線済み受け口を「未配線」と記述するSKILL.mdは存在しない"
  else
    echo "  [FAIL] 現行リポジトリ: 配線済み受け口を「未配線」と記述するSKILL.mdが存在する" >&2
    printf '%s\n' "$_gt_out2" | sed 's/^/    /' >&2
    rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

CATALOG="$DEFAULT_CATALOG"
SKILLS_DIR="$DEFAULT_SKILLS_DIR"

case "${1:-}" in
  --self-test) self_test; exit $? ;;
  "") : ;;
  --catalog|--skills-dir)
    while [ $# -gt 0 ]; do
      case "$1" in
        --catalog) CATALOG="${2:?}"; shift 2 ;;
        --skills-dir) SKILLS_DIR="${2:?}"; shift 2 ;;
        *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
      esac
    done
    ;;
  *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
esac

if run_check "$CATALOG" "$SKILLS_DIR"; then
  echo "PASS: 配線済み受け口を「未配線」と記述するSKILL.mdは存在しない"
  exit 0
else
  exit 1
fi
