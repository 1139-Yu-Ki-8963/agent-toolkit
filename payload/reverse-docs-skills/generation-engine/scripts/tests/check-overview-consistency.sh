#!/usr/bin/env bash
set -euo pipefail

# 改善課題 1-138: 横断検収条件（本番経路スクリプトへの --self-test 実装）に対応する。
# 必要性: catalog/portal/overview/delivery 4資産の整合検査は build-portal.sh の生成物と
#   人間向けガイドの乖離を防ぐ決定的チェックであり、正常系（4資産が整合）・異常系（必須マーカー
#   欠落）を自己テストで固定しておくことで、検査条件を変更した際のリグレッションを検知できる。
#   本スクリプトは ROOT_DIR を自身の配置位置から算出するため、self-test は合成リポジトリ構造
#   （tmp配下に4資産一式を複製）を作り、本スクリプトのコピーをその中で実行する形にする。
if [ "${1:-}" = "--self-test" ]; then
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-overview-consistency-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' EXIT

  # shellcheck source=../output-layout.sh
  source "$(dirname "${BASH_SOURCE[0]}")/../output-layout.sh"
  self_test_layout_json="$(resolve_output_layout "")" || exit 1
  self_test_portal_root="$(output_layout_get "$self_test_layout_json" portalRoot)" || exit 1

  mkdir -p "$tmp/generation-engine/scripts/tests" "$tmp/generation-engine/samples/$self_test_portal_root" "$tmp/delivery-payload/references" "$tmp/docs/guides"
  cp "${BASH_SOURCE[0]}" "$tmp/generation-engine/scripts/tests/check-overview-consistency.sh"
  cp "$(dirname "${BASH_SOURCE[0]}")/../output-layout.sh" "$tmp/generation-engine/scripts/output-layout.sh"
  cp "$(dirname "${BASH_SOURCE[0]}")/../../../delivery-payload/references/output-layout.json" "$tmp/delivery-payload/references/output-layout.json"

  cat > "$tmp/delivery-payload/references/portal-catalog.json" <<'JSON'
{ "categories": [ { "key": "demo", "label": "デモカテゴリ" } ] }
JSON

  cat > "$tmp/generation-engine/samples/$self_test_portal_root/index.html" <<'HTML'
<html><body>
<script type="application/json" id="portal-categories">
[{"id":"demo","title":"デモカテゴリ","tools":[{"title":"デモツール","href":"/demo/demo.html"}]}]
</script>
</body></html>
HTML

  cat > "$tmp/delivery-payload/references/納品物フォルダ体系.md" <<'MD'
## ポータルカテゴリ対応表

| カテゴリキー | カテゴリ名 |
|---|---|
| `demo` | デモカテゴリ |
MD

  # スキル件数の検査を持つため、合成リポジトリにも .claude/skills/ の実体を置く。
  # ディレクトリ・表の行・見出し・バッジ・サイドバー・地図カード・冒頭ラベルは
  # すべて次の配列 1 箇所から導出し、フィクスチャ自体がずれないようにする。
  self_test_manage_skills=(demo-orchestrating-setup demo-running-batch)
  self_test_setup_skills=(demo-surveying-architecture)
  self_test_reverse_skills=(demo-generating-screen-list demo-generating-api-list)
  self_test_delivery_skills=(demo-syncing-derived-artifacts)

  for self_test_skill in \
    "${self_test_manage_skills[@]}" \
    "${self_test_setup_skills[@]}" \
    "${self_test_reverse_skills[@]}"; do
    mkdir -p "$tmp/.claude/skills/$self_test_skill"
  done

  self_test_linked_rows() {
    local name
    for name in "$@"; do
      printf '  <tr><td><a href=".claude/skills/%s/references/guide.html">%s</a></td><td>デモ説明</td></tr>\n' \
        "$name" "$name"
    done
  }

  self_test_plain_rows() {
    local name
    for name in "$@"; do
      printf '  <tr><td><span>%s</span></td><td>デモ説明</td></tr>\n' "$name"
    done
  }

  # 第2引数を渡すと §3.1 地図カード「管理する」の数値だけをずらしたフィクスチャになる
  self_test_write_overview() {
    local dest="$1"
    local map_manage="${2:-${#self_test_manage_skills[@]}}"
    local repo_total=$(( ${#self_test_manage_skills[@]} + ${#self_test_setup_skills[@]} + ${#self_test_reverse_skills[@]} ))
    local delivery_total=${#self_test_delivery_skills[@]}
    {
      cat <<'HTML'
<html><body>
<p>デモカテゴリ / デモツール / demo/demo.html</p>
<p>generating-reverse-basic-design ∥ generating-reverse-detailed-design</p>
<p>詳細設計パス1 → 基本設計・テスト資料パス2</p>
<p>通常の状態遷移:</p>
<p>project-portal/lists/test-cases/テストケース一覧.html</p>
HTML
      printf '<div>スキル構成 全%d本（リポジトリ内%d本＋納品専用%d本）</div>\n' \
        "$(( repo_total + delivery_total ))" "$repo_total" "$delivery_total"
      printf '<div><span>管理する</span><strong>%d</strong></div>\n' "${#self_test_manage_skills[@]}"
      printf '<div><span>セットアップと調査</span><strong>%d</strong></div>\n' "${#self_test_setup_skills[@]}"
      printf '<div><span>リバースする</span><strong>%d</strong></div>\n' "${#self_test_reverse_skills[@]}"
      printf '<div><span>保守する(納品側)</span><strong>%d</strong></div>\n' "$delivery_total"
      printf '<div data-sec="s3-1">\n'
      printf '  <div><span>管理する</span><span>%d</span></div>\n' "$map_manage"
      printf '  <div><span>セットアップと調査</span><span>%d</span></div>\n' "${#self_test_setup_skills[@]}"
      printf '  <div><span>リバースする</span><span>%d</span></div>\n' "${#self_test_reverse_skills[@]}"
      printf '  <div><span>保守する</span><span>%d</span></div>\n' "$delivery_total"
      printf '</div>\n'
      printf '<div data-sec="s3-2">\n  <div>3.2 管理するスキル(%d本)</div>\n  <table><tbody>\n' \
        "${#self_test_manage_skills[@]}"
      self_test_linked_rows "${self_test_manage_skills[@]}"
      printf '  </tbody></table>\n</div>\n'
      printf '<div data-sec="s3-3">\n  <div>3.3 セットアップと調査のスキル(%d本)</div>\n  <table><tbody>\n' \
        "${#self_test_setup_skills[@]}"
      self_test_linked_rows "${self_test_setup_skills[@]}"
      printf '  </tbody></table>\n</div>\n'
      printf '<div data-sec="s3-4">\n  <div>3.4 リバースするスキル(%d本) <span>— 1つの小分類</span></div>\n' \
        "${#self_test_reverse_skills[@]}"
      printf '  <div><span>一覧 %d</span></div>\n' "${#self_test_reverse_skills[@]}"
      printf '  <div>一覧(%d本)</div>\n  <table><tbody>\n' "${#self_test_reverse_skills[@]}"
      # 本番の §3.4 にはガイド HTML を持たず裸の span で書かれた行が実在する。
      # 1 行だけ span で書き、先頭セルの文字列から名前を読む代替経路を固定する。
      self_test_linked_rows "${self_test_reverse_skills[0]}"
      self_test_plain_rows "${self_test_reverse_skills[@]:1}"
      printf '  </tbody></table>\n</div>\n'
      printf '<div data-sec="s3-5">\n  <div>3.5 保守するスキル(%d本) <span>— 納品側</span></div>\n  <table><tbody>\n' \
        "$delivery_total"
      self_test_plain_rows "${self_test_delivery_skills[@]}"
      printf '  </tbody></table>\n</div>\n</body></html>\n'
    } > "$dest"
  }

  self_test_run() {
    ( cd "$tmp" && bash generation-engine/scripts/tests/check-overview-consistency.sh ) >"$tmp/self-test-output.txt" 2>&1
  }

  pass=0 fail=0

  self_test_write_overview "$tmp/docs/guides/reverse-docs-overview.html"
  if self_test_run; then
    echo "PASS: 正常系（4資産整合・スキル件数整合）で終了コード0"; pass=$((pass + 1))
  else
    echo "FAIL: 正常系で終了コード0になるべき"; cat "$tmp/self-test-output.txt"; fail=$((fail + 1))
  fi

  # 異常系: 必須マーカーの1つを overview.html から欠落させる（件数構造は保つ）
  self_test_write_overview "$tmp/docs/guides/reverse-docs-overview.html"
  grep -v 'generating-reverse-basic-design ∥ generating-reverse-detailed-design' \
    "$tmp/docs/guides/reverse-docs-overview.html" > "$tmp/docs/guides/reverse-docs-overview.html.tmp"
  mv "$tmp/docs/guides/reverse-docs-overview.html.tmp" "$tmp/docs/guides/reverse-docs-overview.html"
  if self_test_run; then
    echo "FAIL: 異常系（必須マーカー欠落）で終了コード1になるべき"; fail=$((fail + 1))
  elif grep -q "missing process markers" "$tmp/self-test-output.txt"; then
    echo "PASS: 異常系（必須マーカー欠落）で終了コード1"; pass=$((pass + 1))
  else
    echo "FAIL: 異常系（必須マーカー欠落）が別の理由で失敗している"; cat "$tmp/self-test-output.txt"; fail=$((fail + 1))
  fi

  # 異常系: 件数の数値を1つだけずらす（§3.1 地図カードの「管理する」）
  self_test_write_overview "$tmp/docs/guides/reverse-docs-overview.html" 9
  if self_test_run; then
    echo "FAIL: 異常系（件数のずれ）で終了コード1になるべき"; fail=$((fail + 1))
  elif grep -q "§3.1 map card 管理する says 9" "$tmp/self-test-output.txt"; then
    echo "PASS: 異常系（件数のずれ）で終了コード1"; pass=$((pass + 1))
  else
    echo "FAIL: 異常系（件数のずれ）が別の理由で失敗している"; cat "$tmp/self-test-output.txt"; fail=$((fail + 1))
  fi

  echo "self-test: $pass PASS, $fail FAIL"
  if [ "$fail" -eq 0 ]; then exit 0; else exit 1; fi
fi

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"

# shellcheck source=output-layout.sh
source "${ROOT_DIR}/generation-engine/scripts/output-layout.sh"
LAYOUT_JSON="$(resolve_output_layout "")" || exit 1
PORTAL_ROOT="$(output_layout_get "$LAYOUT_JSON" portalRoot)" || exit 1

OVERVIEW="${ROOT_DIR}/docs/guides/reverse-docs-overview.html"
SAMPLE="${ROOT_DIR}/generation-engine/samples/${PORTAL_ROOT}/index.html"
CATALOG="${ROOT_DIR}/delivery-payload/references/portal-catalog.json"
DELIVERY="${ROOT_DIR}/delivery-payload/references/納品物フォルダ体系.md"
SKILLS_DIR="${ROOT_DIR}/.claude/skills"

if [[ ! -f "${OVERVIEW}" || ! -f "${SAMPLE}" || ! -f "${CATALOG}" || ! -f "${DELIVERY}" ]]; then
  echo "FAIL: overview, sample index, catalog, or delivery inventory is missing" >&2
  exit 1
fi

if [[ ! -d "${SKILLS_DIR}" ]]; then
  echo "FAIL: skills directory is missing: ${SKILLS_DIR}" >&2
  exit 1
fi

TEST_CASE_LIST_HTML="$(output_layout_get "$LAYOUT_JSON" unitListHtml テストケース)" || exit 1

python3 - "${OVERVIEW}" "${SAMPLE}" "${CATALOG}" "${DELIVERY}" "${TEST_CASE_LIST_HTML}" "${SKILLS_DIR}" <<'PY'
import json
import re
import sys
from pathlib import Path

overview_path = Path(sys.argv[1])
sample_path = Path(sys.argv[2])
catalog_path = Path(sys.argv[3])
delivery_path = Path(sys.argv[4])
test_case_list_html = sys.argv[5]
skills_dir = Path(sys.argv[6])
overview = overview_path.read_text(encoding="utf-8")
sample = sample_path.read_text(encoding="utf-8")
catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
delivery = delivery_path.read_text(encoding="utf-8")

match = re.search(
    r'<script type="application/json" id="portal-categories">(.*?)</script>',
    sample,
    re.S,
)
if not match:
    raise SystemExit("FAIL: portal-categories JSON is missing from sample index")

portal_categories = json.loads(match.group(1))
catalog_keys = {category["key"] for category in catalog["categories"]}
catalog_labels = {category["label"] for category in catalog["categories"]}
portal_keys = {category["id"] for category in portal_categories}
portal_labels = {category["title"] for category in portal_categories}
expected_tools = [
    (category["title"], tool["title"], tool["href"])
    for category in portal_categories
    for tool in category["tools"]
]

table_match = re.search(
    r"^## ポータルカテゴリ対応表\s*$([\s\S]*?)(?=^##\s|\Z)",
    delivery,
    re.M,
)
if not table_match:
    raise SystemExit("FAIL: delivery inventory has no ポータルカテゴリ対応表")
delivery_keys = set(re.findall(r"^\|\s*`([a-z0-9-]+)`\s*\|", table_match.group(1), re.M))

differences = []
for left_name, left, right_name, right in (
    ("catalog", catalog_keys, "portal", portal_keys),
    ("catalog", catalog_keys, "delivery", delivery_keys),
):
    missing = sorted(left - right)
    unknown = sorted(right - left)
    if missing:
        differences.append(f"{right_name} missing keys from {left_name}: {', '.join(missing)}")
    if unknown:
        differences.append(f"{right_name} has unknown keys vs {left_name}: {', '.join(unknown)}")

visible = re.sub(
    r'<template id="legacy-(?:deliverables-table|process-flow)">.*?</template>',
    '',
    overview,
    flags=re.S,
)

overview_labels = {label for label in catalog_labels if label in visible}
missing_overview_labels = sorted(catalog_labels - overview_labels)
missing_portal_labels = sorted(catalog_labels - portal_labels)
unknown_portal_labels = sorted(portal_labels - catalog_labels)
if missing_overview_labels:
    differences.append("overview missing category labels: " + ", ".join(missing_overview_labels))
if missing_portal_labels:
    differences.append("portal missing category labels: " + ", ".join(missing_portal_labels))
if unknown_portal_labels:
    differences.append("portal has unknown category labels: " + ", ".join(unknown_portal_labels))

missing_tools = [
    f"{category}: {title} ({href})"
    for category, title, href in expected_tools
    if title not in visible or href[1:] not in visible
]
if missing_tools:
    differences.append("overview missing portal cards:\n  " + "\n  ".join(missing_tools))

# --- スキル本数の整合検査 ---
# 導出の一次情報は3つだけ: (a) .claude/skills/ のディレクトリ数、(b) §3.5 の行数、
# (c) 各表の <tr> の実数。表示されている件数はすべてこの3つから導いた値と突き合わせる。
# 構造が見つからない場合は「見つからない」ことを差分として積み FAIL させる（fail-open は禁止）。
skill_dirs = {entry.name for entry in skills_dir.iterdir() if entry.is_dir()}

# data-sec の値は JS 文字列にも現れるため、節キーの形（s3-2 等）だけを対象にする
section_marks = [
    (match.start(), match.group(1))
    for match in re.finditer(r'data-sec="([^"]+)"', visible)
    if re.fullmatch(r"s\d+(?:-\d+)?", match.group(1))
]


def section_body(key):
    for index, (start, name) in enumerate(section_marks):
        if name == key:
            end = section_marks[index + 1][0] if index + 1 < len(section_marks) else len(visible)
            return visible[start:end]
    return None


def count_rows(segment):
    # 節の直下に置かれた表と小分類の表を区別せず、その範囲にある行をすべて数える。
    # §3.4 は小分類の表しか持たない前提であり、見出し直下に別の表を足すと
    # 節の行数と小分類の合計が食い違って両方の検査が鳴る。
    return len(re.findall(r"<tr\b", segment))


def row_skill_names(key, segment):
    names = []
    for row in re.findall(r"<tr\b.*?</tr>", segment, re.S):
        first_cell = re.search(r"<td\b.*?</td>", row, re.S)
        if not first_cell:
            differences.append(f"{key}: a <tr> has no <td>")
            continue
        cell = first_cell.group(0)
        linked = re.search(r'href="\.claude/skills/([^/"]+)/', cell)
        name = linked.group(1) if linked else re.sub(r"<[^>]*>", "", cell).strip()
        if not re.fullmatch(r"[a-z0-9-]+", name):
            differences.append(f"{key}: unreadable skill name in first cell: {name!r}")
            continue
        names.append(name)
    return names


section_keys = ("s3-2", "s3-3", "s3-4", "s3-5")
bodies = {}
heading_counts = {}
row_counts = {}
declared_names = set()

for key in section_keys:
    body = section_body(key)
    if body is None:
        differences.append(f'overview has no section marked data-sec="{key}"')
        continue
    bodies[key] = body
    heading = re.search(r">(\d+\.\d+)[^<]*?\((\d+)本\)", body)
    if not heading:
        differences.append(f"{key}: heading with (N本) is missing")
        continue
    rows = count_rows(body)
    heading_counts[key] = int(heading.group(2))
    row_counts[key] = rows
    if heading_counts[key] != rows:
        differences.append(
            f"{key}: heading says {heading_counts[key]} but the tables have {rows} rows"
        )
    names = row_skill_names(key, body)
    if len(names) != rows:
        differences.append(f"{key}: {rows} rows but {len(names)} skill names could be read")
    if key != "s3-5":
        declared_names |= set(names)

# 主検査: §3.2〜§3.4 に並ぶスキル名の和集合が .claude/skills/ の実体と一致すること
undocumented = sorted(skill_dirs - declared_names)
unknown = sorted(declared_names - skill_dirs)
if undocumented:
    differences.append("overview §3.2-§3.4 missing skills that exist in .claude/skills/: " + ", ".join(undocumented))
if unknown:
    differences.append("overview §3.2-§3.4 lists skills absent from .claude/skills/: " + ", ".join(unknown))

# §3.2 + §3.3 + §3.4 の見出し値の合計 == .claude/skills/ のディレクトリ数
repo_section_keys = ("s3-2", "s3-3", "s3-4")
if all(key in heading_counts for key in repo_section_keys):
    repo_total = sum(heading_counts[key] for key in repo_section_keys)
    if repo_total != len(skill_dirs):
        differences.append(
            f"§3.2+§3.3+§3.4 headings total {repo_total} but .claude/skills/ has {len(skill_dirs)} directories"
        )

# §3.4 の小分類: バッジ・小見出し・表の行数をラベル名で対応付ける
if "s3-4" in bodies:
    body = bodies["s3-4"]
    sub_headings = [
        (match.start(), match.group(1).strip(), int(match.group(2)))
        for match in re.finditer(r">([^<>()]+)\((\d+)本\)</div>", body)
    ]
    if not sub_headings:
        differences.append("s3-4: no sub-group headings of the form ラベル(N本)")
    else:
        badge_region = body[: sub_headings[0][0]]
        badges = {
            match.group(1).strip(): int(match.group(2))
            for match in re.finditer(r">([^<>]+?)\s+(\d+)</span>", badge_region)
        }
        sub_counts = {}
        for index, (start, label, declared) in enumerate(sub_headings):
            end = sub_headings[index + 1][0] if index + 1 < len(sub_headings) else len(body)
            rows = count_rows(body[start:end])
            sub_counts[label] = declared
            if declared != rows:
                differences.append(
                    f"s3-4 sub-group {label}: heading says {declared} but its table has {rows} rows"
                )
        missing_badges = sorted(set(sub_counts) - set(badges))
        unknown_badges = sorted(set(badges) - set(sub_counts))
        if missing_badges:
            differences.append("s3-4: sub-groups without a badge: " + ", ".join(missing_badges))
        if unknown_badges:
            differences.append("s3-4: badges without a sub-group: " + ", ".join(unknown_badges))
        for label in sorted(set(sub_counts) & set(badges)):
            if badges[label] != sub_counts[label]:
                differences.append(
                    f"s3-4 badge {label} says {badges[label]} but the sub-group heading says {sub_counts[label]}"
                )
        if "s3-4" in heading_counts:
            sub_total = sum(sub_counts.values())
            if sub_total != heading_counts["s3-4"]:
                differences.append(
                    f"s3-4 sub-groups total {sub_total} but the section heading says {heading_counts['s3-4']}"
                )

# サイドバーの4値と §3.1 地図カードの4値（ラベルは互いに異なるので同一視しない）
sidebar_labels = {
    "管理する": "s3-2",
    "セットアップと調査": "s3-3",
    "リバースする": "s3-4",
    "保守する(納品側)": "s3-5",
}
for label, key in sidebar_labels.items():
    found = re.search(r">" + re.escape(label) + r"</span><strong[^>]*>(\d+)</strong>", visible)
    if not found:
        differences.append(f"sidebar has no count for {label}")
        continue
    if key in heading_counts and int(found.group(1)) != heading_counts[key]:
        differences.append(
            f"sidebar {label} says {found.group(1)} but {key} heading says {heading_counts[key]}"
        )

map_body = section_body("s3-1")
if map_body is None:
    differences.append('overview has no section marked data-sec="s3-1"')
else:
    map_labels = {
        "管理する": "s3-2",
        "セットアップと調査": "s3-3",
        "リバースする": "s3-4",
        "保守する": "s3-5",
    }
    for label, key in map_labels.items():
        found = re.search(r">" + re.escape(label) + r"</span><span[^>]*>(\d+)</span>", map_body)
        if not found:
            differences.append(f"§3.1 map card has no count for {label}")
            continue
        if key in heading_counts and int(found.group(1)) != heading_counts[key]:
            differences.append(
                f"§3.1 map card {label} says {found.group(1)} but {key} heading says {heading_counts[key]}"
            )

# 冒頭ラベル（括弧は全角）。52 == ディレクトリ数、3 == §3.5 の行数、55 == 52 + 3
summary = re.search(r"スキル構成 全(\d+)本（リポジトリ内(\d+)本＋納品専用(\d+)本）", visible)
if not summary:
    differences.append("overview has no スキル構成 summary label")
else:
    total, repo_shown, delivery_shown = (int(value) for value in summary.groups())
    if repo_shown != len(skill_dirs):
        differences.append(
            f"summary label says リポジトリ内{repo_shown}本 but .claude/skills/ has {len(skill_dirs)} directories"
        )
    if "s3-5" in row_counts and delivery_shown != row_counts["s3-5"]:
        differences.append(
            f"summary label says 納品専用{delivery_shown}本 but §3.5 has {row_counts['s3-5']} rows"
        )
    if total != repo_shown + delivery_shown:
        differences.append(
            f"summary label says 全{total}本 but {repo_shown} + {delivery_shown} = {repo_shown + delivery_shown}"
        )

if differences:
    raise SystemExit("FAIL: catalog/portal/overview/delivery mismatch:\n  " + "\n  ".join(differences))

required_markers = [
    "generating-reverse-basic-design ∥ generating-reverse-detailed-design",
    "詳細設計パス1 → 基本設計・テスト資料パス2",
    "通常の状態遷移:",
    test_case_list_html,
]
missing_markers = [marker for marker in required_markers if marker not in visible]
if missing_markers:
    raise SystemExit("FAIL: missing process markers:\n  " + "\n  ".join(missing_markers))

for forbidden in ("基本設計より先に詳細設計を書かない",):
    if forbidden in visible:
        raise SystemExit(f"FAIL: obsolete process statement remains: {forbidden}")

print(
    f"PASS: {len(portal_categories)} portal categories, "
    f"{len(expected_tools)} discovered cards, catalog/portal/overview/delivery sets aligned, "
    f"{len(skill_dirs)} skills in .claude/skills/ match every skill count shown in the overview"
)
PY
