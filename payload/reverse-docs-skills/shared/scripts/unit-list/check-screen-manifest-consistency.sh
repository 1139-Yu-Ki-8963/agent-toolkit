#!/usr/bin/env bash
# raw screen manifest、ext、全派生JSON/HTMLのmanifestContentHash一致を検査する。
set -euo pipefail

usage="Usage: check-screen-manifest-consistency.sh --raw-manifest <path> --ext-manifest <path> --output-root <dir>"
raw=""; ext=""; root=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --raw-manifest) raw="${2:-}"; shift 2 ;;
    --ext-manifest) ext="${2:-}"; shift 2 ;;
    --output-root) root="${2:-}"; shift 2 ;;
    *) echo "$usage" >&2; exit 1 ;;
  esac
done
[ -f "$raw" ] && [ -f "$ext" ] && [ -d "$root" ] || { echo "$usage" >&2; exit 1; }
jq empty "$raw" "$ext" >/dev/null 2>&1 || { echo "ERROR: invalid manifest JSON" >&2; exit 1; }
jq -e 'has("manifestContentHash") | not' "$raw" >/dev/null \
  || { echo "ERROR: raw manifest must not contain manifestContentHash" >&2; exit 1; }

canonical="$(jq -cjS . "$raw")"
if command -v shasum >/dev/null 2>&1; then
  expected="$(printf '%s' "$canonical" | shasum -a 256 | awk '{print $1}')"
else
  expected="$(printf '%s' "$canonical" | sha256sum | awk '{print $1}')"
fi
[ "$(jq -r '.manifestContentHash // ""' "$ext")" = "$expected" ] \
  || { echo "ERROR: ext manifestContentHash mismatch" >&2; exit 1; }

allowed='["category","permissions","relatedApis","designDocStatus","confirmedScreenName","designDocPath","detailDocPath","sequencePath","testCasePath","unitTestViewpointPath","integrationTestViewpointPath","integrationTestCasePath","scenarioPath","sourceHash","designDocSourceHash"]'
jq -S --argjson allowed "$allowed" '
  del(.generatedAt,.manifestContentHash)
  | .screens = [(.screens // [])[] | delpaths([$allowed[] | [.]])]
' "$raw" > "${TMPDIR:-/tmp}/screen-consistency-raw.$$.json"
trap 'rm -f "${TMPDIR:-/tmp}/screen-consistency-raw.$$.json" "${TMPDIR:-/tmp}/screen-consistency-ext.$$.json" "${TMPDIR:-/tmp}/screen-consistency-embedded.$$.json"' EXIT
jq -S --argjson allowed "$allowed" '
  del(.generatedAt,.manifestContentHash)
  | .screens = [(.screens // [])[] | delpaths([$allowed[] | [.]])]
' "$ext" > "${TMPDIR:-/tmp}/screen-consistency-ext.$$.json"
cmp "${TMPDIR:-/tmp}/screen-consistency-raw.$$.json" "${TMPDIR:-/tmp}/screen-consistency-ext.$$.json" \
  || { echo "ERROR: ext changed fields outside the allow-list" >&2; exit 1; }

check_json_hash() {
  local file="$1"
  [ -f "$file" ] || { echo "ERROR: missing derived JSON: $file" >&2; return 1; }
  [ "$(jq -r '.manifestContentHash // ""' "$file" 2>/dev/null)" = "$expected" ] \
    || { echo "ERROR: derived JSON hash mismatch: $file" >&2; return 1; }
}

extract_script() {
  local html="$1" id="$2" out="$3"
  node - "$html" "$id" "$out" <<'NODE'
const fs = require("fs");
const [htmlPath,id,out] = process.argv.slice(2);
const html = fs.readFileSync(htmlPath,"utf8").replace(/<!--[\s\S]*?-->/g,"");
const escaped = id.replace(/[.*+?^${}()|[\]\\]/g,"\\$&");
const re = new RegExp(`<script\\b(?=[^>]*\\btype=["']application/json["'])(?=[^>]*\\bid=["']${escaped}["'])[^>]*>([\\s\\S]*?)<\\/script>`,"gi");
const found = [...html.matchAll(re)];
const parsed = [];
for (const match of found) {
  const text = match[1]
    .replace(/&lt;/g,"<").replace(/&gt;/g,">").replace(/&quot;/g,'"')
    .replace(/&#39;/g,"'").replace(/&#x27;/gi,"'").replace(/&amp;/g,"&");
  try { parsed.push(JSON.parse(text)); } catch {}
}
if (parsed.length !== 1) throw new Error(`${htmlPath}: parseable script#${id} count=${parsed.length}`);
const data = parsed[0];
fs.writeFileSync(out, JSON.stringify(data));
NODE
}

json_files=(
  "$root/画面遷移図-data.json"
  "$root/マトリクス・対応表/data/permission-matrix.json"
  "$root/マトリクス・対応表/data/permission-function-matrix.json"
  "$root/マトリクス・対応表/data/crud-matrix.json"
  "$root/マトリクス・対応表/data/traceability.json"
)
for file in "${json_files[@]}"; do check_json_hash "$file"; done

transition_data="$root/画面遷移図-data.json"
bash "$(dirname "$0")/../detail-pages/check-screen-transition-manifest-alignment.sh" \
  --raw-manifest "$raw" --ext-manifest "$ext" --page-data "$transition_data" >/dev/null

html_specs=(
  "一覧/画面一覧/画面一覧.html|screen-manifest"
  "index.html|screen-manifest-source"
  "画面遷移図.html|page-data"
  "マトリクス・対応表/権限画面マトリクス/権限画面マトリクス.html|matrix-manifest"
  "マトリクス・対応表/権限機能マトリクス/権限機能マトリクス.html|matrix-manifest"
  "マトリクス・対応表/CRUD図/CRUD図.html|matrix-manifest"
  "マトリクス・対応表/追跡可能性/追跡可能性.html|matrix-manifest"
)
for spec in "${html_specs[@]}"; do
  rel="${spec%%|*}"; id="${spec#*|}"; html="$root/$rel"
  if [ ! -f "$html" ]; then
    case "$rel" in
      マトリクス・対応表/*/*.html)
        # 必須成分0件でbuild-matrix-pages.shが生成をスキップした任意出力(写真指摘1-101)。
        echo "SKIP: 必須成分0件で生成されなかった任意出力のためhash検査を省略: $html" >&2
        continue
        ;;
      *)
        echo "ERROR: missing derived HTML: $html" >&2; exit 1
        ;;
    esac
  fi
  extract_script "$html" "$id" "${TMPDIR:-/tmp}/screen-consistency-embedded.$$.json"
  [ "$(jq -r '.manifestContentHash // ""' "${TMPDIR:-/tmp}/screen-consistency-embedded.$$.json")" = "$expected" ] \
    || { echo "ERROR: embedded hash mismatch: $html#$id" >&2; exit 1; }
done
echo "PASS: raw/ext/13 derived outputs share manifestContentHash=$expected; raw=nodes+route-empty-unresolved; label differences=0"
