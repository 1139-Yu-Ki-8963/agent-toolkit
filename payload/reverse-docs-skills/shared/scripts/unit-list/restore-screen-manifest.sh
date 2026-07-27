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

  printf '%s\n' '<html>missing manifest</html>' > "$invalid"
  if bash "$0" "$invalid" "$tmp/should-not-exist.json" >/dev/null 2>&1; then
    echo "FAIL: embedded manifestが無いHTMLを拒否しませんでした" >&2
    return 1
  fi
  echo "PASS: 埋込manifestから永続screen_manifest_pathを原子的に復元"
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

awk '
  /<script[^>]*type="application\/json"[^>]*id="screen-manifest"[^>]*>/ { in_manifest=1; next }
  in_manifest && /<\/script>/ { in_manifest=0; found=1; exit }
  in_manifest { print }
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
