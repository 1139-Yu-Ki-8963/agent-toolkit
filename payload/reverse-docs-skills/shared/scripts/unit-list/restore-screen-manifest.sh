#!/usr/bin/env bash
set -euo pipefail

# Existing screen-list HTML is a durable resume source. Restore its embedded
# application/json block into the canonical manifest path atomically.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_self_test() {
  local tmp html restored invalid
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/restore-screen-manifest.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN
  html="$tmp/画面一覧.html"
  restored="$tmp/screen-manifest.json"
  invalid="$tmp/invalid.html"
  mkdir -p "$tmp/src/screens"
  printf '%s\n' 'export default function Home() { return null }' > "$tmp/src/screens/Home.tsx"

  jq -n \
    --arg sourceDir "$tmp/src" \
    --arg entryFile "$tmp/src/screens/Home.tsx" \
    '{
    generatedAt: "2026-07-28T00:00:00Z",
    sourceDir: $sourceDir,
    strategy: {
      extractionMethod: "custom",
      approvedByUser: true,
      screenIdRegex: null,
      excludePatterns: []
    },
    detectionSummary: {
      screenCount: 1,
      clusterCount: 0,
      sharedScreenCount: 0,
      embeddedCandidateCount: 0,
      unresolvedCount: 0
    },
    screens: [{
      screenKey: "home-screen",
      kind: "route",
      route: "/home",
      entryFile: $entryFile,
      detectionMethod: "manual",
      confidence: "high",
      screenNameGuess: "Home",
      parentScreen: null,
      childComponents: [],
      accountGroup: "common",
      accountSubType: "common",
      screenType: "detail",
      hasTemplate: true,
      isProcessingEndpoint: false
    }],
  }' > "$tmp/expected.json"

  {
    printf '%s\n' '<!doctype html><html><body>'
    printf '%s\n' '<script type="application/json" id="screen-manifest">'
    jq -c . "$tmp/expected.json" | sed 's/</\\u003c/g; s/>/\\u003e/g; s/\&/\\u0026/g'
    printf '%s\n' '</script></body></html>'
  } > "$html"

  bash "$0" "$html" "$restored" >/dev/null
  jq -S . "$tmp/expected.json" > "$tmp/expected.sorted.json"
  jq -S . "$restored" > "$tmp/restored.sorted.json"
  diff -u "$tmp/expected.sorted.json" "$tmp/restored.sorted.json"

  # 開始タグ・JSON本体・終了タグが同一行に収まる入力(build-screen-list.shの
  # 単一パステンプレート置換が生む形式)も復元できることを確認する。
  local html_oneline restored_oneline
  html_oneline="$tmp/画面一覧_同一行.html"
  restored_oneline="$tmp/screen-manifest_同一行.json"
  {
    printf '%s\n' '<!doctype html><html><body>'
    printf '%s<script type="application/json" id="screen-manifest">%s</script>\n' \
      '<p>prefix</p>' \
      "$(jq -c . "$tmp/expected.json" | sed 's/</\\u003c/g; s/>/\\u003e/g; s/\&/\\u0026/g')"
    printf '%s\n' '</body></html>'
  } > "$html_oneline"

  bash "$0" "$html_oneline" "$restored_oneline" >/dev/null
  jq -S . "$restored_oneline" > "$tmp/restored_oneline.sorted.json"
  diff -u "$tmp/expected.sorted.json" "$tmp/restored_oneline.sorted.json"

  # 半分結合形式: 開始タグは単独行、JSON本体+終了タグが同一行(旧実装が
  # in_manifest && /<\/script>/ にexit; していたため本体を出力せず落ちていた形)。
  local html_half restored_half
  html_half="$tmp/画面一覧_半結合.html"
  restored_half="$tmp/screen-manifest_半結合.json"
  {
    printf '%s\n' '<!doctype html><html><body>'
    printf '%s\n' '<script type="application/json" id="screen-manifest">'
    printf '%s</script>\n' "$(jq -c . "$tmp/expected.json" | sed 's/</\\u003c/g; s/>/\\u003e/g; s/\&/\\u0026/g')"
    printf '%s\n' '</body></html>'
  } > "$html_half"

  bash "$0" "$html_half" "$restored_half" >/dev/null
  jq -S . "$restored_half" > "$tmp/restored_half.sorted.json"
  diff -u "$tmp/expected.sorted.json" "$tmp/restored_half.sorted.json"

  printf '%s\n' '<html>missing manifest</html>' > "$invalid"
  if bash "$0" "$invalid" "$tmp/should-not-exist.json" >/dev/null 2>&1; then
    echo "FAIL: embedded manifestが無いHTMLを拒否しませんでした" >&2
    return 1
  fi
  echo "PASS: 埋込manifestから永続screen_manifest_pathを原子的に復元(複数行・同一行の両形式)"
}

if [ "${1:-}" = "--self-test" ]; then
  run_self_test
  exit $?
fi

HTML_PATH="${1:?Usage: restore-screen-manifest.sh <screen-list.html> <manifest-out.json>}"
MANIFEST_OUT="${2:?Usage: restore-screen-manifest.sh <screen-list.html> <manifest-out.json>}"

if [ ! -f "$HTML_PATH" ]; then
  echo "ERROR: screen-list HTML not found: $HTML_PATH" >&2
  exit 1
fi

mkdir -p "$(dirname "$MANIFEST_OUT")"
tmp_out="$(mktemp "$(dirname "$MANIFEST_OUT")/.screen-manifest.XXXXXX")"
trap 'rm -f "$tmp_out"' EXIT

# 開始タグ・JSON本体・終了タグが同一行に収まる入力(build-screen-list.shの単一パス
# テンプレート置換が生む形式)と、従来の行をまたぐ入力の両方から本体のみを抜き出す。
# 開始タグの行末に本体が続く場合はその残りを起点として同一行内の終了タグも探す。
awk '
  {
    line = $0
    if (!in_manifest) {
      if (match(line, /<script[^>]*type="application\/json"[^>]*id="screen-manifest"[^>]*>/)) {
        in_manifest = 1
        line = substr(line, RSTART + RLENGTH)
      } else {
        next
      }
    }
    if (match(line, /<\/script>/)) {
      body = substr(line, 1, RSTART - 1)
      if (length(body) > 0) print body
      found = 1
      exit
    }
    if (length(line) > 0) print line
  }
  END { if (!found) exit 3 }
' "$HTML_PATH" > "$tmp_out" || {
  echo "ERROR: embedded screen-manifest block not found: $HTML_PATH" >&2
  exit 1
}

if ! jq -e '.screens | type == "array"' "$tmp_out" >/dev/null; then
  echo "ERROR: embedded screen-manifest is invalid JSON or has no screens array" >&2
  exit 1
fi
if ! "$SCRIPT_DIR/validate-manifest.sh" "$tmp_out" >/dev/null; then
  echo "ERROR: restored screen-manifest failed schema validation" >&2
  exit 1
fi

mv "$tmp_out" "$MANIFEST_OUT"
trap - EXIT
echo "$MANIFEST_OUT"
