#!/usr/bin/env bash
set -euo pipefail

# Existing screen-list HTML is a durable resume source. Restore its embedded
# application/json block into the canonical manifest path atomically.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_self_test() {
  local tmp html restored invalid
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/restore-screen-manifest.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼" >&2
    exit 2
  fi
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

  # --- 1-102随伴修正: --repo-root の指定あり/なし ---
  # build-screen-list.shが1-102対応でsourceDirをbasename化・entryFileをsourceDir
  # プレフィックス除去した「サニタイズ済み」埋め込みJSONを模したHTMLで検証する。
  # --repo-root未指定ケースは、validate-manifest.shのentryFile-実在チェックが
  # (Git祖先が見つからない場合の)フォールバック先としてmanifest自身の所在ディレクトリを
  # 使うため、他ケース用に作成済みの"$tmp/src/screens/Home.tsx"と同じ祖先に置くと
  # sourceDir="src"がその実在ファイルへ偶然一致して検証が成功してしまう。専用の
  # 空ディレクトリに隔離し、意図どおり解決失敗することを保証する。
  local no_root_dir sanitized_html sanitized_out_no_root sanitized_out_with_root
  no_root_dir="$tmp/no-root-case"
  mkdir -p "$no_root_dir"
  sanitized_html="$no_root_dir/画面一覧_sanitized.html"
  sanitized_out_no_root="$no_root_dir/restored-no-root.json"
  sanitized_out_with_root="$tmp/restored-with-root.json"
  jq -n '{
    generatedAt: "2026-07-28T00:00:00Z",
    sourceDir: "src",
    strategy: {extractionMethod: "custom", approvedByUser: true, screenIdRegex: null, excludePatterns: []},
    detectionSummary: {screenCount: 1, clusterCount: 0, sharedScreenCount: 0, embeddedCandidateCount: 0, unresolvedCount: 0},
    screens: [{
      screenKey: "home-screen", kind: "route", route: "/home", entryFile: "screens/Home.tsx",
      detectionMethod: "manual", confidence: "high", screenNameGuess: "Home",
      parentScreen: null, childComponents: [], accountGroup: "common", accountSubType: "common",
      screenType: "detail", hasTemplate: true, isProcessingEndpoint: false
    }]
  }' > "$tmp/sanitized-expected.json"
  {
    printf '%s\n' '<!doctype html><html><body>'
    printf '%s\n' '<script type="application/json" id="screen-manifest">'
    jq -c . "$tmp/sanitized-expected.json" | sed 's/</\\u003c/g; s/>/\\u003e/g; s/\&/\\u0026/g'
    printf '%s\n' '</script></body></html>'
  } > "$sanitized_html"

  # --repo-root 未指定: サニタイズ済みsourceDir("src")のままentryFile-実在検査へ渡され、
  # 実ファイルへ解決できず検証失敗する(1-102の設計上のトレードオフとして期待される挙動)
  if bash "$0" "$sanitized_html" "$sanitized_out_no_root" >/dev/null 2>&1; then
    echo "FAIL: --repo-root未指定でもsourceDir='src'がentryFile解決に成功してしまった(想定外)" >&2
    return 1
  fi

  # --repo-root 指定: sourceDirを実リポジトリの場所へ上書きしてから検証するため、
  # entryFile-実在が正しく解決できる
  if ! bash "$0" "$sanitized_html" "$sanitized_out_with_root" --repo-root "$tmp/src" >/dev/null 2>&1; then
    echo "FAIL: --repo-root指定時にentryFile-実在の解決へ失敗した" >&2
    return 1
  fi
  if [ "$(jq -r '.sourceDir' "$sanitized_out_with_root")" != "$tmp/src" ]; then
    echo "FAIL: --repo-root指定時にsourceDirが上書きされていない" >&2
    return 1
  fi
  echo "PASS: --repo-root未指定はサニタイズ済みsourceDirのまま検証失敗・指定時はsourceDirを実パスへ上書きして検証成功"
}

if [ "${1:-}" = "--self-test" ]; then
  run_self_test
  exit $?
fi

HTML_PATH="${1:?Usage: restore-screen-manifest.sh <screen-list.html> <manifest-out.json> [--repo-root <path>]}"
MANIFEST_OUT="${2:?Usage: restore-screen-manifest.sh <screen-list.html> <manifest-out.json> [--repo-root <path>]}"
shift 2 || true

# --repo-root <path>(任意・1-102随伴修正): 埋め込みJSONのsourceDirは1-102対応で
# basename化されたサニタイズ済みの値であり、実ファイルパスとしては解決できない。
# 呼び出し側が実リポジトリの場所を把握している場合は --repo-root で明示することで、
# 復元後manifestのsourceDirをその実パスへ上書きしてから検証する(entryFile-実在の
# 解決を可能にする)。未指定時は従来どおり埋め込み値(サニタイズ済み)をそのまま使い、
# entryFile-実在が解決できない可能性を許容する(生成HTMLに絶対パスを残さないという
# 1-102の設計上のトレードオフ)。
REPO_ROOT_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo-root)
      REPO_ROOT_ARG="${2:-}"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ ! -f "$HTML_PATH" ]; then
  echo "ERROR: screen-list HTML not found: $HTML_PATH" >&2
  exit 1
fi

mkdir -p "$(dirname "$MANIFEST_OUT")"
# tmp_outは${TMPDIR:-/tmp}ではなく${MANIFEST_OUTと同じディレクトリへ作る}。244行目で
# ${MANIFEST_OUTへmvするが}、別ファイルシステムだとmvがcopy+deleteへ縮退し、検証済み
# JSONへの原子的な置き換え(冒頭コメント「Restore...atomically」)が崩れるため。
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

if [ -n "$REPO_ROOT_ARG" ]; then
  tmp_out_repo_root="$(mktemp "$(dirname "$MANIFEST_OUT")/.screen-manifest-repo-root.XXXXXX")"
  jq --arg sd "$REPO_ROOT_ARG" '.sourceDir = $sd' "$tmp_out" > "$tmp_out_repo_root"
  mv "$tmp_out_repo_root" "$tmp_out"
fi

if ! "$SCRIPT_DIR/validate-manifest.sh" "$tmp_out" >/dev/null; then
  echo "ERROR: restored screen-manifest failed schema validation" >&2
  exit 1
fi

mv "$tmp_out" "$MANIFEST_OUT"
trap - EXIT
echo "$MANIFEST_OUT"
