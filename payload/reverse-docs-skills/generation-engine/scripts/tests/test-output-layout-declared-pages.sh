#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/generation-engine/scripts/output-layout.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/output-layout-pages-test.XXXXXX")"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
root="$tmp/output"
mkdir -p "$root/docs/design/common" "$root/project-portal"

cat > "$root/output-layout.json" <<'JSON'
{
  "specVersion": 1,
  "layout": {
    "foundationDoc": "docs/design/common/platform/同名.md",
    "commonDesignDoc": "docs/design/common/common/同名.md",
    "platformDesignHtml": "custom/foundation/platform.html",
    "commonDesignHtml": "custom/foundation/common.html",
    "dataDesignHtml": "custom/foundation/data.html",
    "messageDesignHtml": "custom/foundation/message.html",
    "uiCommonDesignHtml": "custom/foundation/ui-common.html"
  }
}
JSON

mkdir -p "$root/docs/design/common/platform" "$root/docs/design/common/common"
mkdir -p "$root/docs/design/common/extra"
printf '# 基盤設計\n\n同名文書の基盤側。\n' > "$root/docs/design/common/platform/同名.md"
printf '# 共通設計\n\n同名文書の共通側。\n\n[基盤設計](../platform/同名.md)\n' > "$root/docs/design/common/common/同名.md"
printf '# 宣言外文書\n\n同名文書の宣言外側。\n' > "$root/docs/design/common/extra/同名.md"

for spec in \
  "基盤設計.md|基盤設計" \
  "共通設計書.md|共通設計" \
  "データ設計.md|データ設計" \
  "メッセージ定義書.md|メッセージ定義" \
  "UI共通設計.md|UI共通設計"; do
  IFS='|' read -r file title <<EOF
$spec
EOF
  printf '# %s\n\n合成フィクスチャ。\n' "$title" > "$root/docs/design/common/$file"
done

bash "$REPO_ROOT/generation-engine/scripts/build-portal.sh" \
  "$REPO_ROOT" "$root" "$root/project-portal" \
  --generated-at 2026-01-01T00:00:00Z --project-name fixture >/dev/null

for expected in \
  custom/foundation/platform.html \
  custom/foundation/common.html \
  custom/foundation/data.html \
  custom/foundation/message.html \
  custom/foundation/ui-common.html; do
  [ -f "$root/$expected" ] || { echo "FAIL: 合成定義先に生成されていない: $expected" >&2; exit 1; }
  grep -qF "../$expected" "$root/project-portal/index.html" \
    || { echo "FAIL: ポータルから合成定義先を発見できない: $expected" >&2; exit 1; }
done
grep -qF '[基盤設計](platform.html)' "$root/custom/foundation/common.html" \
  || { echo "FAIL: 文書間リンクが個別出力鍵の生成先へ解決されていない" >&2; exit 1; }
[ -f "$root/docs/design/common/extra/同名.html" ] \
  || { echo "FAIL: 宣言外の同名文書が入力文書と同じ場所へ生成されていない" >&2; exit 1; }

for undefined in \
  project-portal/foundation/基盤設計.html \
  project-portal/foundation/共通設計書.html \
  project-portal/foundation/データ設計.html \
  project-portal/foundation/メッセージ定義書.html \
  project-portal/foundation/UI共通設計.html; do
  [ ! -e "$root/$undefined" ] || { echo "FAIL: 定義に無い置き場が作られた: $undefined" >&2; exit 1; }
done

rm -f "$root/docs/design/common/common/同名.md"
bash "$REPO_ROOT/generation-engine/scripts/build-portal.sh" \
  "$REPO_ROOT" "$root" "$root/project-portal" \
  --generated-at 2026-01-01T00:00:00Z --project-name fixture >/dev/null
[ ! -e "$root/custom/foundation/common.html" ] \
  || { echo "FAIL: 入力削除後も個別出力鍵の孤児HTMLが残った" >&2; exit 1; }

echo "PASS: 共通設計文書5形式は合成した個別出力鍵の定義先だけへ生成される"
