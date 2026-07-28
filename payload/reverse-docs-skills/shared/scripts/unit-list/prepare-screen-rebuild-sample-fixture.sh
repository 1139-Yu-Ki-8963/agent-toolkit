#!/usr/bin/env bash
# 指定commitのchecked-in HTMLからraw screen/API manifest fixtureを復元する。
set -euo pipefail
usage="Usage: prepare-screen-rebuild-sample-fixture.sh --repo-root <path> --commit <sha> --output <dir>"
repo=""; commit=""; output=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo-root) repo="${2:-}"; shift 2 ;;
    --commit) commit="${2:-}"; shift 2 ;;
    --output) output="${2:-}"; shift 2 ;;
    *) echo "$usage" >&2; exit 1 ;;
  esac
done
[ -d "$repo/.git" ] || git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 \
  || { echo "ERROR: invalid repo" >&2; exit 1; }
[ -n "$commit" ] && [ -n "$output" ] || { echo "$usage" >&2; exit 1; }
git -C "$repo" cat-file -e "$commit^{commit}" 2>/dev/null || { echo "ERROR: commit not found" >&2; exit 1; }

stage="$(mktemp -d "$(dirname "$output")/.screen-fixture.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/raw"
git -C "$repo" show "$commit:shared/samples/一覧/画面一覧/画面一覧.html" > "$stage/screen.html"
git -C "$repo" show "$commit:shared/samples/一覧/API一覧/API一覧.html" > "$stage/api.html"
node - "$stage/screen.html" screen-manifest "$stage/raw/screen-manifest.json" \
  "$stage/api.html" unit-manifest "$stage/raw/api-manifest.json" <<'NODE'
const fs=require("fs");
function extract(file,id,out){
 const html=fs.readFileSync(file,"utf8").replace(/<!--[\s\S]*?-->/g,""), esc=id.replace(/[.*+?^${}()|[\]\\]/g,"\\$&");
 const found=[...html.matchAll(new RegExp(`<script\\b(?=[^>]*\\btype=["']application/json["'])(?=[^>]*\\bid=["']${esc}["'])[^>]*>([\\s\\S]*?)<\\/script>`,"gi"))];
 if(found.length!==1) throw new Error(`${file}#${id} count=${found.length}`);
 const text=found[0][1].replace(/&lt;/g,"<").replace(/&gt;/g,">").replace(/&quot;/g,'"')
   .replace(/&#39;/g,"'").replace(/&#x27;/gi,"'").replace(/&amp;/g,"&");
 fs.writeFileSync(out,JSON.stringify(JSON.parse(text),null,2)+"\n");
}
const a=process.argv.slice(2); extract(a[0],a[1],a[2]); extract(a[3],a[4],a[5]);
NODE
jq '
  del(.manifestContentHash)
  | .strategy.extractionMethod = (.strategy.extractionMethod // "custom")
  | .strategy.approvedByUser = true
  | .strategy.screenIdRegex = (.strategy.screenIdRegex // null)
  | .strategy.excludePatterns = (.strategy.excludePatterns // [])
  | .screens = [.screens[] |
      .screenType = (.screenType // "top")
      | .accountGroup = (.accountGroup // "common")
      | .accountSubType = (.accountSubType // "common")
      | .hasTemplate = (.hasTemplate // true)
      | .parentScreen = (.parentScreen // null)
      | .childComponents = (.childComponents // [])
      | .isProcessingEndpoint = (.isProcessingEndpoint // false)
    ]
' "$stage/raw/screen-manifest.json" > "$stage/raw/screen-manifest.clean.json"
mv "$stage/raw/screen-manifest.clean.json" "$stage/raw/screen-manifest.json"
mkdir -p "$output"
cp -a "$stage/raw" "$output/"
echo "PASS: prepared fixture at $output"
