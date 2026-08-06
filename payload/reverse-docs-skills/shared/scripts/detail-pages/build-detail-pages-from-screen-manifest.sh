#!/usr/bin/env bash
# rawとraw由来の拡張screen manifestから画面遷移page-dataとHTMLを決定的に生成するbridge。
set -euo pipefail

manifest_hash() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    jq -cjS . "$file" | shasum -a 256 | awk '{print $1}'
  else
    jq -cjS . "$file" | sha256sum | awk '{print $1}'
  fi
}

self_test() {
  local script="$0" tmp hash
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/screen-detail-bridge-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/out"
  jq -n '{
    screens:[
      {screenKey:"admin",kind:"route",route:"/admin",screenNameGuess:"管理画面"},
      {screenKey:"home",kind:"route",route:"/home",screenNameGuess:"ホーム",accountGroup:"user"},
      {screenKey:"missing",kind:"unresolved",route:""}
    ]
  }' > "$tmp/raw.json"
  hash="$(manifest_hash "$tmp/raw.json")"
  jq --arg hash "$hash" '
    .generatedAt = "2026-07-28T00:00:00Z"
    | .manifestContentHash = $hash
    | .screens[0].confirmedScreenName = "管理"
    | .screens[0].category = "管理"
  ' "$tmp/raw.json" > "$tmp/ext.json"
  bash "$script" "$tmp/ext.json" "$tmp/out" \
    --raw-manifest "$tmp/raw.json" --generated-at 2026-07-28T00:00:00Z
  jq -e --arg hash "$hash" '
    .manifestContentHash == $hash
    and [.nodes[].unitKey] == ["admin","home"]
    and [.nodes[].label] == ["管理","ホーム"]
    and .unresolved == [{label:"missing",reason:"routeが空文字列のため遷移解決不能"}]
    and ((.nodes | length) + (.unresolved | length) == 3)
    and ([.flowCategories[].screenCount] | add) == 2
  ' "$tmp/out/画面遷移図-data.json" >/dev/null
  test -f "$tmp/out/画面遷移図.html"
  jq '.screens[0].screenNameGuess = "改変"' "$tmp/raw.json" > "$tmp/tampered-raw.json"
  if bash "$script" "$tmp/ext.json" "$tmp/rejected" \
    --raw-manifest "$tmp/tampered-raw.json" --generated-at 2026-07-28T00:00:00Z >/dev/null 2>&1; then
    echo "FAIL: rawとextのhash不一致を受理した" >&2
    return 1
  fi
  echo "self-test 全項目 PASS"
}

if [ "${1:-}" = "--self-test" ]; then self_test; exit $?; fi
usage="Usage: build-detail-pages-from-screen-manifest.sh <screen-manifest.ext.json> <output-root> --raw-manifest <screen-manifest.json> --generated-at <iso8601>"
manifest="${1:-}"; output_root="${2:-}"
[ -n "$manifest" ] && [ -n "$output_root" ] || { echo "$usage" >&2; exit 1; }
shift 2
generated_at=""; raw=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --raw-manifest) raw="${2:-}"; shift 2 ;;
    --generated-at) generated_at="${2:-}"; shift 2 ;;
    *) echo "$usage" >&2; exit 1 ;;
  esac
done
[ -f "$manifest" ] && [ -f "$raw" ] \
  && jq empty "$manifest" "$raw" >/dev/null 2>&1 \
  || { echo "ERROR: invalid raw or extended manifest" >&2; exit 1; }
jq -e 'has("manifestContentHash") | not' "$raw" >/dev/null \
  || { echo "ERROR: raw manifest must not contain manifestContentHash" >&2; exit 1; }
[ -n "$generated_at" ] || { echo "ERROR: --generated-at is required" >&2; exit 1; }
hash="$(jq -r '.manifestContentHash // ""' "$manifest")"
printf '%s' "$hash" | grep -Eq '^[0-9a-f]{64}$' || { echo "ERROR: manifestContentHash missing or invalid" >&2; exit 1; }
[ "$hash" = "$(manifest_hash "$raw")" ] \
  || { echo "ERROR: extended manifest is not derived from the supplied raw manifest" >&2; exit 1; }
[ "$(jq -r '.generatedAt // ""' "$manifest")" = "$generated_at" ] \
  || { echo "ERROR: generatedAt mismatch" >&2; exit 1; }

mkdir -p "$output_root"
page_data="$output_root/画面遷移図-data.json"

# 既存page-dataのedges引き継ぎ判定: 同一manifestContentHashの場合のみ既存edgesを
# 信頼できるとみなして引き継ぐ(bridgeは検出器を持たないため、遷移抽出スキルが
# 過去に書き込んだedgesを一括再生成で失わないための決定的な照合)。
existing_edges="[]"
existing_edges_status="未抽出"
if [ -f "$page_data" ] && jq empty "$page_data" >/dev/null 2>&1; then
  existing_hash="$(jq -r '.manifestContentHash // ""' "$page_data")"
  if [ "$existing_hash" = "$hash" ]; then
    existing_edges="$(jq -c '.edges // []' "$page_data")"
    existing_edges_status="$(jq -r '.edgesStatus // "抽出済み"' "$page_data")"
    edge_count="$(jq 'length' <<<"$existing_edges")"
    echo "INFO: 既存の edges ${edge_count}件を引き継ぎました" >&2
  else
    echo "INFO: manifest が変化したため edges を空にしました" >&2
  fi
else
  echo "INFO: 既存の画面遷移図-data.jsonが無いため edges を空にしました" >&2
fi

tmp_data="$(mktemp "$output_root/.transition-data.XXXXXX")"
trap 'rm -f "$tmp_data"' EXIT
jq -S --arg generatedAt "$generated_at" --arg manifestContentHash "$hash" \
  --argjson edgesArg "$existing_edges" --arg edgesStatusArg "$existing_edges_status" '
  def screen_label: (.confirmedScreenName // .screenNameGuess // .screenKey);
  def category:
    if ((.category // "") | length) > 0 then {value:.category, src:"url-segment"}
    elif ((.accountGroup // "") | length) > 0 then {value:.accountGroup, src:"account-group"}
    else {value:"その他", src:"fallback"} end;
  . as $manifest
  | [
    $manifest.screens[]?
    | select(((.route // "") | length) > 0)
    | category as $cat
    | {unitKey:.screenKey,label:screen_label,route:.route,category:$cat.value,categorySrc:$cat.src}
  ] | sort_by(.unitKey) as $nodes
  | [
      $manifest.screens[]?
      | select(((.route // "") | length) == 0)
      | {label:screen_label,reason:"routeが空文字列のため遷移解決不能"}
    ] | sort_by(.label) as $unresolved
  | {
      pageKind:"transition",
      generatedAt:$generatedAt,
      manifestContentHash:$manifestContentHash,
      manifestScreenCount:($manifest.screens | length),
      title:"画面遷移図",
      description:"画面manifestから生成した画面一覧",
      legend:[{symbol:"□",meaning:"画面"}],
      nodes:$nodes,
      edges:$edgesArg,
      edgesStatus:$edgesStatusArg,
      unresolved:$unresolved,
      flowCategories:(
        $nodes | group_by([.category,.categorySrc])
        | map({name:.[0].category,source:.[0].categorySrc,screenCount:length})
        | sort_by([.name,.source])
      )
    }
' "$manifest" > "$tmp_data"

"$(dirname "$0")/validate-page-data.sh" "$tmp_data" >/dev/null
bash "$(dirname "$0")/check-screen-transition-manifest-alignment.sh" \
  --raw-manifest "$raw" --ext-manifest "$manifest" --page-data "$tmp_data" >/dev/null
mv "$tmp_data" "$page_data"
trap - EXIT
bash "$(dirname "$0")/build-detail-page.sh" "$page_data" "$output_root" \
  --page transition --generated-at "$generated_at"
echo "OK: wrote $page_data and $output_root/画面遷移図.html" >&2
