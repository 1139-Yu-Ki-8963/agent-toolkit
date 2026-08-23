#!/usr/bin/env bash
# raw、raw由来ext、画面遷移page-dataの件数・ラベル・hash整合を検査する。
set -euo pipefail

# 改善課題 1-138: 横断検収条件（本番経路スクリプトへの --self-test 実装）に対応する。
# 必要性: raw/ext/page-data 3資産のhash・件数・ラベル整合検査は generating-screen-transition
#   -for-reverse-docs の本番経路で使われる決定的チェックであり、正常系（3資産が整合）・
#   異常系（manifestContentHash不一致）を自己テストで固定しておく。
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-screen-transition-alignment-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT

  cat > "$tmp/raw.json" <<'JSON'
{"screens":[{"screenKey":"home","kind":"route","route":"/home","screenNameGuess":"ホーム"}]}
JSON
  canonical="$(jq -cjS . "$tmp/raw.json")"
  # sha256 コマンド解決(macOS: shasum -a 256 / Linux: sha256sum。
  # extract-screen-metadata.shのsha256_12()と同じ理由)
  if command -v shasum >/dev/null 2>&1; then
    expected="$(printf '%s' "$canonical" | shasum -a 256 | awk '{print $1}')"
  else
    expected="$(printf '%s' "$canonical" | sha256sum | awk '{print $1}')"
  fi
  # 1-170: valueProvenance/confirmedPermissions/confirmedScheduleをextのみに追加し、
  # del()登録漏れがあれば正常系がFAILすることを実測で保証する(2026-08-01時点の実測確認)。
  jq --arg h "$expected" --arg t "2026-07-31T00:00:00Z" \
    '. + {generatedAt: $t, manifestContentHash: $h}
     | .screens[0].confirmedScreenName = "ホーム画面"
     | .screens[0].valueProvenance = {permissions: "measured"}
     | .screens[0].confirmedPermissions = ["admin"]
     | .screens[0].confirmedSchedule = {cron: "0 3 * * *", readable: "毎日 3:00"}
     | .screens[0].integrationTestViewpointPath = "../../画面/home/結合テスト観点表.md"
     | .screens[0].integrationTestCasePath = "../../画面/home/結合テスト仕様書.md"
     | .screens[0].scenarioPath = "../../画面/home/操作シナリオ仕様書.md"
     | .screens[0].confirmationPath = "../../画面/home/要確認事項台帳.json"' \
    "$tmp/raw.json" > "$tmp/ext.json"
  jq -n --arg h "$expected" \
    '{manifestContentHash: $h, nodes: [{unitKey: "home", label: "ホーム画面"}], unresolved: []}' \
    > "$tmp/page.json"

  pass=0 fail=0
  if bash "${BASH_SOURCE[0]}" --raw-manifest "$tmp/raw.json" --ext-manifest "$tmp/ext.json" --page-data "$tmp/page.json" >/dev/null 2>&1; then
    echo "PASS: 正常系（raw/ext/page-data整合）で終了コード0"; pass=$((pass + 1))
  else
    echo "FAIL: 正常系で終了コード0になるべき"; fail=$((fail + 1))
  fi

  jq '.manifestContentHash = "0000000000000000000000000000000000000000000000000000000000000000"' "$tmp/page.json" > "$tmp/page.bad.json"
  if bash "${BASH_SOURCE[0]}" --raw-manifest "$tmp/raw.json" --ext-manifest "$tmp/ext.json" --page-data "$tmp/page.bad.json" >/dev/null 2>&1; then
    echo "FAIL: 異常系（manifestContentHash不一致）で終了コード1になるべき"; fail=$((fail + 1))
  else
    echo "PASS: 異常系（manifestContentHash不一致）で終了コード1"; pass=$((pass + 1))
  fi

  # 1-144再検証: kind:"unresolved"かつrouteが非空文字列の画面を含む合成フィクスチャ。
  # bridge(build-detail-pages-from-screen-manifest.sh)はkindを見ずroute有無だけで
  # nodes/unresolvedを振り分けるため、applicableもkindで絞り込んではならない
  # (kind制限が残っているとこの画面がapplicableから漏れ、raw.screens長との
  # 不一致でFAILする)。
  cat > "$tmp/raw2.json" <<'JSON'
{"screens":[{"screenKey":"home","kind":"route","route":"/home","screenNameGuess":"ホーム"},{"screenKey":"www2-animax_regist","kind":"unresolved","route":"/regist","screenNameGuess":"登録"}]}
JSON
  canonical2="$(jq -cjS . "$tmp/raw2.json")"
  if command -v shasum >/dev/null 2>&1; then
    expected2="$(printf '%s' "$canonical2" | shasum -a 256 | awk '{print $1}')"
  else
    expected2="$(printf '%s' "$canonical2" | sha256sum | awk '{print $1}')"
  fi
  jq --arg h "$expected2" --arg t "2026-08-06T00:00:00Z" \
    '. + {generatedAt: $t, manifestContentHash: $h}
     | .screens[0].confirmedScreenName = "ホーム画面"' \
    "$tmp/raw2.json" > "$tmp/ext2.json"
  jq -n --arg h "$expected2" \
    '{manifestContentHash: $h,
      nodes: [
        {unitKey: "home", label: "ホーム画面"},
        {unitKey: "www2-animax_regist", label: "登録"}
      ],
      unresolved: []}' \
    > "$tmp/page2.json"

  if bash "${BASH_SOURCE[0]}" --raw-manifest "$tmp/raw2.json" --ext-manifest "$tmp/ext2.json" --page-data "$tmp/page2.json" >/dev/null 2>&1; then
    echo "PASS: kind:unresolvedかつroute非空の画面をnodesとして整合判定"; pass=$((pass + 1))
  else
    echo "FAIL: kind:unresolvedかつroute非空の画面がapplicableから漏れkindで絞り込まれた"; fail=$((fail + 1))
  fi

  echo "self-test: $pass PASS, $fail FAIL"
  if [ "$fail" -eq 0 ]; then exit 0; else exit 1; fi
fi

usage="Usage: check-screen-transition-manifest-alignment.sh --raw-manifest <screen-manifest.json> --ext-manifest <screen-manifest.ext.json> --page-data <画面遷移図-data.json>"
raw=""; ext=""; page=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --raw-manifest) raw="${2:-}"; shift 2 ;;
    --ext-manifest) ext="${2:-}"; shift 2 ;;
    --page-data) page="${2:-}"; shift 2 ;;
    *) echo "$usage" >&2; exit 1 ;;
  esac
done
[ -f "$raw" ] && [ -f "$ext" ] && [ -f "$page" ] \
  && jq empty "$raw" "$ext" "$page" >/dev/null 2>&1 \
  || { echo "$usage" >&2; exit 1; }
jq -e 'has("manifestContentHash") | not' "$raw" >/dev/null \
  || { echo "ERROR: raw manifest must not contain manifestContentHash" >&2; exit 1; }

canonical="$(jq -cjS . "$raw")"
if command -v shasum >/dev/null 2>&1; then
  expected="$(printf '%s' "$canonical" | shasum -a 256 | awk '{print $1}')"
else
  expected="$(printf '%s' "$canonical" | sha256sum | awk '{print $1}')"
fi

jq -e -n \
  --arg expected "$expected" \
  --slurpfile raw "$raw" \
  --slurpfile ext "$ext" \
  --slurpfile page "$page" '
  def effective_label: (.confirmedScreenName // .screenNameGuess // .screenKey);
  # 1-144再検証: bridge(build-detail-pages-from-screen-manifest.sh)はnodes/unresolvedの
  # 振り分けをroute有無のみで行いkindを見ない。ここでもkindによる絞り込みをやめ、
  # 全screenをapplicableとして扱う(kind=unresolvedかつroute非空の画面も対象に含める)。
  def applicable: .screens;
  # 素直な形(rawとextを構造比較して差分ゼロを求める)を避け、ext側だけが
  # 持ちうるフィールドをdel()で明示的に取り除いてから比較する。extはraw由来の
  # 抽出処理(1-170のvalueProvenance等)がフィールドを追加する前提であり、
  # 「rawの値をextが書き換えていないか」だけを検査したい。del()の列挙漏れは
  # 正常系を誤ってFAILさせる形で顕在化する(1-170再検証の自己テストが保証)ため、
  # フィールドを追加するたびにこの列挙へ追従させる必要がある。
  def strip_ext_fields:
    del(.generatedAt,.manifestContentHash,.detectionSummary.diagnostics)
    | .screens = [(.screens // [])[] | del(
        .category,.permissions,.relatedApis,.designDocStatus,.confirmedScreenName,
        .designDocPath,.detailDocPath,.sequencePath,.testCasePath,.unitTestViewpointPath,.sourceHash,
        .designDocSourceHash,.integrationTestViewpointPath,.integrationTestCasePath,.scenarioPath,.confirmationPath,
        .valueProvenance,.confirmedPermissions,.confirmedSchedule
      )];
  ($raw[0] | applicable) as $raw_screens
  | ($ext[0] | applicable) as $ext_screens
  | ($page[0].nodes // []) as $nodes
  | ($page[0].unresolved // [] | map(select(.reason == "routeが空文字列のため遷移解決不能"))) as $route_empty
  | (($ext[0].manifestContentHash // "") == $expected)
    and (($page[0].manifestContentHash // "") == $expected)
    and (($raw[0] | strip_ext_fields) == ($ext[0] | strip_ext_fields))
    and (($raw[0].screens | length) == ($raw_screens | length))
    and (($raw_screens | length) == (($nodes | length) + ($route_empty | length)))
    and (all($nodes[];
      . as $node
      | any($ext_screens[];
          .screenKey == $node.unitKey
          and ((.route // "") | length) > 0
          and effective_label == $node.label
        )
    ))
    and (([$ext_screens[] | select(((.route // "") | length) == 0) | effective_label] | sort)
      == ([$route_empty[].label] | sort))
    and (([$nodes[].unitKey] | unique | length) == ($nodes | length))
' >/dev/null \
  || { echo "ERROR: raw/ext/page-data hash, coverage, or label alignment failed" >&2; exit 1; }

echo "PASS: raw=nodes+route-empty-unresolved; label differences=0; manifestContentHash=$expected"
