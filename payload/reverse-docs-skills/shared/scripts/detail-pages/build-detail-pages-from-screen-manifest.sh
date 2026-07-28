#!/usr/bin/env bash
# 拡張screen manifestから画面遷移page-dataとHTMLを決定的に生成するbridge。
set -euo pipefail

self_test() {
  local script="$0" tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/screen-detail-bridge-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/out"
  jq -n '{
    generatedAt:"2026-07-28T00:00:00Z",
    manifestContentHash:("a"*64),
    screens:[
      {screenKey:"admin",kind:"route",route:"/admin",confirmedScreenName:"管理",category:"管理"},
      {screenKey:"home",kind:"route",route:"/home",screenNameGuess:"ホーム",accountGroup:"user"},
      {screenKey:"missing",kind:"route",route:""}
    ]
  }' > "$tmp/ext.json"
  bash "$script" "$tmp/ext.json" "$tmp/out" --generated-at 2026-07-28T00:00:00Z
  jq -e '
    .manifestContentHash == ("a"*64)
    and [.nodes[].unitKey] == ["admin","home"]
    and .unresolved == [{label:"missing",reason:"routeが空文字列のため遷移解決不能"}]
    and ([.flowCategories[].screenCount] | add) == 2
  ' "$tmp/out/画面遷移図-data.json" >/dev/null
  test -f "$tmp/out/画面遷移図.html"
  echo "self-test 全項目 PASS"
}

if [ "${1:-}" = "--self-test" ]; then self_test; exit $?; fi
usage="Usage: build-detail-pages-from-screen-manifest.sh <screen-manifest.ext.json> <output-root> --generated-at <iso8601>"
manifest="${1:-}"; output_root="${2:-}"
[ -n "$manifest" ] && [ -n "$output_root" ] || { echo "$usage" >&2; exit 1; }
shift 2
generated_at=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --generated-at) generated_at="${2:-}"; shift 2 ;;
    *) echo "$usage" >&2; exit 1 ;;
  esac
done
[ -f "$manifest" ] && jq empty "$manifest" >/dev/null 2>&1 || { echo "ERROR: invalid manifest" >&2; exit 1; }
[ -n "$generated_at" ] || { echo "ERROR: --generated-at is required" >&2; exit 1; }
hash="$(jq -r '.manifestContentHash // ""' "$manifest")"
printf '%s' "$hash" | grep -Eq '^[0-9a-f]{64}$' || { echo "ERROR: manifestContentHash missing or invalid" >&2; exit 1; }
[ "$(jq -r '.generatedAt // ""' "$manifest")" = "$generated_at" ] \
  || { echo "ERROR: generatedAt mismatch" >&2; exit 1; }

mkdir -p "$output_root"
page_data="$output_root/画面遷移図-data.json"
tmp_data="$(mktemp "$output_root/.transition-data.XXXXXX")"
trap 'rm -f "$tmp_data"' EXIT
jq -S --arg generatedAt "$generated_at" --arg manifestContentHash "$hash" '
  def screen_label: (.confirmedScreenName // .screenNameGuess // .screenKey);
  def category:
    if ((.category // "") | length) > 0 then {value:.category, src:"url-segment"}
    elif ((.accountGroup // "") | length) > 0 then {value:.accountGroup, src:"account-group"}
    else {value:"その他", src:"fallback"} end;
  . as $manifest
  | [
    $manifest.screens[]?
    | select(.kind == "route" or .kind == "embedded-view")
    | select(((.route // "") | length) > 0)
    | category as $cat
    | {unitKey:.screenKey,label:screen_label,route:.route,category:$cat.value,categorySrc:$cat.src}
  ] | sort_by(.unitKey) as $nodes
  | [
      $manifest.screens[]?
      | select(.kind == "route" or .kind == "embedded-view")
      | select(((.route // "") | length) == 0)
      | {label:screen_label,reason:"routeが空文字列のため遷移解決不能"}
    ] | sort_by(.label) as $unresolved
  | {
      pageKind:"transition",
      generatedAt:$generatedAt,
      manifestContentHash:$manifestContentHash,
      title:"画面遷移図",
      description:"画面manifestから生成した画面一覧",
      legend:[{symbol:"□",meaning:"画面"}],
      nodes:$nodes,
      edges:[],
      unresolved:$unresolved,
      flowCategories:(
        $nodes | group_by([.category,.categorySrc])
        | map({name:.[0].category,source:.[0].categorySrc,screenCount:length})
        | sort_by([.name,.source])
      )
    }
' "$manifest" > "$tmp_data"

"$(dirname "$0")/validate-page-data.sh" "$tmp_data" >/dev/null
mv "$tmp_data" "$page_data"
trap - EXIT
bash "$(dirname "$0")/build-detail-page.sh" "$page_data" "$output_root" \
  --page transition --generated-at "$generated_at"
echo "OK: wrote $page_data and $output_root/画面遷移図.html" >&2
