#!/usr/bin/env bash
# raw screen manifest、ext、全派生JSON/HTMLのmanifestContentHash一致を検査する。
set -euo pipefail

# 改善課題 1-138: 横断検収条件（本番経路スクリプトへの --self-test 実装）に対応する。
# 必要性: raw/ext/13派生出力のmanifestContentHash一致検査は画面一覧確立の完全性ゲート（本番経路）
#   で使われる決定的チェックであり、正常系（全出力が同一hashを共有）・異常系（派生JSONの
#   hash不一致）を自己テストで固定しておく。マトリクス・対応表4HTMLは必須成分0件時にSKIPされる
#   任意出力のため、self-testの正常系フィクスチャからは意図的に省く（SKIP経路も同時に検証する）。
if [ "${1:-}" = "--self-test" ]; then
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-screen-manifest-consistency-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' EXIT

  SCRIPT_DIR_ST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=../output-layout.sh
  source "$SCRIPT_DIR_ST/../output-layout.sh"

  cat > "$tmp/raw.json" <<'JSON'
{"screens":[{"screenKey":"home","kind":"route","route":"/home","screenNameGuess":"ホーム"}]}
JSON
  canonical="$(jq -cjS . "$tmp/raw.json")"
  if command -v shasum >/dev/null 2>&1; then
    expected="$(printf '%s' "$canonical" | shasum -a 256 | awk '{print $1}')"
  else
    expected="$(printf '%s' "$canonical" | sha256sum | awk '{print $1}')"
  fi
  # 1-170: valueProvenance/confirmedPermissions/confirmedScheduleをextのみに追加し、
  # 許可リスト登録漏れがあれば正常系がFAILすることを実測で保証する(2026-08-01時点の実測確認)。
  jq --arg h "$expected" --arg t "2026-07-31T00:00:00Z" \
    '. + {generatedAt: $t, manifestContentHash: $h}
     | .screens[0].confirmedScreenName = "ホーム画面"
     | .screens[0].valueProvenance = {permissions: "measured"}
     | .screens[0].confirmedPermissions = ["admin"]
     | .screens[0].confirmedSchedule = {cron: "0 3 * * *", readable: "毎日 3:00"}
     | .screens[0].confirmationPath = "../../画面/home/要確認事項台帳.json"' \
    "$tmp/raw.json" > "$tmp/ext.json"

  root="$tmp/output-root"
  # 主本体（本ファイル下部）はSCREEN_LIST_HTMLをoutput-layout.sh経由で解決するため、
  # フィクスチャも同じ解決結果（既定: project-portal/lists/screens/画面一覧.html）に
  # 合わせて配置する。ハードコードした「一覧/画面一覧」に置くと本体の解決結果と
  # 一致せずmissing derived HTMLで失敗する。
  LAYOUT_JSON_ST="$(resolve_output_layout "$root")"
  SCREEN_LIST_HTML_ST="$(output_layout_get "$LAYOUT_JSON_ST" screenListHtml)"
  mkdir -p "$root/$(dirname "$SCREEN_LIST_HTML_ST")" "$root/マトリクス・対応表/data"
  jq -n --arg h "$expected" '{manifestContentHash: $h, nodes: [{unitKey: "home", label: "ホーム画面"}], unresolved: []}' \
    > "$root/画面遷移図-data.json"
  for f in permission-matrix.json permission-function-matrix.json crud-matrix.json traceability.json; do
    jq -n --arg h "$expected" '{manifestContentHash: $h}' > "$root/マトリクス・対応表/data/$f"
  done
  embed() {
    local out="$1" id="$2"
    printf '<html><body><script type="application/json" id="%s">{"manifestContentHash":"%s"}</script></body></html>' \
      "$id" "$expected" > "$out"
  }
  embed "$root/$SCREEN_LIST_HTML_ST" "screen-manifest"
  embed "$root/index.html" "screen-manifest-source"
  embed "$root/画面遷移図.html" "page-data"

  pass=0 fail=0
  if _csm_out="$(bash "${BASH_SOURCE[0]}" --raw-manifest "$tmp/raw.json" --ext-manifest "$tmp/ext.json" --output-root "$root" 2>&1)"; then
    echo "PASS: 正常系（raw/ext/13派生出力がhash共有・任意4HTMLはSKIP）で終了コード0"; pass=$((pass + 1))
  else
    echo "FAIL: 正常系で終了コード0になるべき"; fail=$((fail + 1))
    printf '%s\n' "$_csm_out" | sed 's/^/  /'
  fi

  jq '.manifestContentHash = "0000000000000000000000000000000000000000000000000000000000000000"' \
    "$root/マトリクス・対応表/data/crud-matrix.json" > "$root/マトリクス・対応表/data/crud-matrix.bad.json"
  mv "$root/マトリクス・対応表/data/crud-matrix.bad.json" "$root/マトリクス・対応表/data/crud-matrix.json"
  if bash "${BASH_SOURCE[0]}" --raw-manifest "$tmp/raw.json" --ext-manifest "$tmp/ext.json" --output-root "$root" >/dev/null 2>&1; then
    echo "FAIL: 異常系（派生JSONのhash不一致）で終了コード1になるべき"; fail=$((fail + 1))
  else
    echo "PASS: 異常系（派生JSONのhash不一致）で終了コード1"; pass=$((pass + 1))
  fi

  echo "self-test: $pass PASS, $fail FAIL"
  if [ "$fail" -eq 0 ]; then exit 0; else exit 1; fi
fi

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

allowed='["category","permissions","relatedApis","designDocStatus","confirmedScreenName","designDocPath","detailDocPath","sequencePath","testCasePath","unitTestViewpointPath","integrationTestViewpointPath","integrationTestCasePath","scenarioPath","confirmationPath","sourceHash","designDocSourceHash","valueProvenance","confirmedPermissions","confirmedSchedule"]'
jq -S --argjson allowed "$allowed" '
  del(.generatedAt,.manifestContentHash,.detectionSummary.diagnostics)
  | .screens = [(.screens // [])[] | delpaths([$allowed[] | [.]])]
' "$raw" > "${TMPDIR:-/tmp}/screen-consistency-raw.$$.json"
trap 'rm -f "${TMPDIR:-/tmp}/screen-consistency-raw.$$.json" "${TMPDIR:-/tmp}/screen-consistency-ext.$$.json" "${TMPDIR:-/tmp}/screen-consistency-embedded.$$.json"' EXIT
jq -S --argjson allowed "$allowed" '
  del(.generatedAt,.manifestContentHash,.detectionSummary.diagnostics)
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../output-layout.sh
source "$SCRIPT_DIR/../output-layout.sh"
LAYOUT_JSON="$(resolve_output_layout "$root")" || exit 1
SCREEN_LIST_HTML="$(output_layout_get "$LAYOUT_JSON" screenListHtml)" || exit 1

html_specs=(
  "${SCREEN_LIST_HTML}|screen-manifest"
  "index.html|screen-manifest-source"
  "画面遷移図.html|page-data"
  "マトリクス・対応表/権限画面マトリクス/権限画面マトリクス.html|matrix-manifest"
  "マトリクス・対応表/権限機能マトリクス/権限機能マトリクス.html|matrix-manifest"
  "マトリクス・対応表/CRUD図/CRUD図.html|matrix-manifest"
  "マトリクス・対応表/画面-API-テーブル対応表/画面-API-テーブル対応表.html|matrix-manifest"
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
