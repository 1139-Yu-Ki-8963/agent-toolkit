#!/usr/bin/env bash
# extract-transition-page-data.sh — 画面基本設計書.md §6 画面遷移の業務文脈から transition 用の
# page-data.json（nodes[]/edges[]）を機械的に組み立てる
#
# 背景(docs/tasks/関連図の内製化の指示書.md 5節「段階3: 画面遷移図」):
# 指示書は段階3を「確信度の定義が先に要る」として完了条件から外し、着手する場合は
# 画面基本設計書.md §6へ「出典参照」「確信度」の2列を足す前提で書かれていた。
# ところが実測で、列を足さなくても矢印を作れることが分かった。根拠は2点。
# (1) page-data-schema.mdの「sourceRefの形式」節が、コード以外の根拠として文書参照形式
#     `<文書名>.md#<見出し>` を既に許可している。(2) §6の表は元々、遷移元画面・遷移先画面・
#     遷移する業務上の契機の3列を持ち、矢印(from/to/trigger)に要る情報が揃っている。
# 本スクリプトはこの中間案を実装する。sourceRefは行ごとの列値ではなく
# 「画面基本設計書.md#§6」という固定の文書参照文字列とし、confidenceは文書からは
# 確からしさを判定できないため常に空文字("")とする(捏造しない)。
# 画面基本設計書.mdテンプレート側(delivery-payload/templates/リバース検証/画面/基本設計/
# 画面基本設計書.md)には一切手を入れない(列を足さない)。
#
# Usage:
#   extract-transition-page-data.sh <output_dir> <出力page-data.jsonのパス>
#   extract-transition-page-data.sh --self-test
#
#   <output_dir>                画面基本設計書.md と screen-manifest.json が展開済みの
#                                プロジェクトルート(output-layout.json の screenUnitRoot・
#                                screenManifest を <output_dir> からの相対で解決する)
#   <出力page-data.jsonのパス>   組み立てた page-data.json を書き出すファイルパス
#
# nodes[]・manifestContentHash・manifestScreenCount・route空文字のunresolved[]は
# build-detail-pages-from-screen-manifest.sh(bridge)と同じ規則でraw screen-manifest.jsonから
# 組み立てる(validate-page-data.shのノード件数整合検査に適合させるため)。
# screen-manifest.json が不在・不正な場合は nodes[]/manifestContentHash を復元できないため
# exit 1 とする(entity-state/er抽出器と異なり、transitionはこの2キーが必須のため)。
#
# 画面基本設計書.md が0件、または §6 のデータ行が0件(雛形のプレースホルダ行のみ)の場合は、
# edges[]が空のpage-data.json(edgesStatus="未抽出")を書き出し、WARNをstderrへ出して
# exit 0で終える(捏造しない)。
#
# 設計判断の正本: docs/design/generation-engine/portal-input/詳細設計書.md
# 「## extract-transition-page-data.sh」節。
# 保守責任者: 人手(ユーザー)。画面基本設計書.md §6 の列構成を変える場合は本ファイルと
# self-test を同時に更新する。
# macOS bash 3.2 互換(mapfile / declare -A 不使用)。

set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found in PATH" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../output-layout.sh
. "$SCRIPT_DIR/../output-layout.sh"

# sha256 コマンド解決(macOS: shasum -a 256 / Linux: sha256sum)。
# build-detail-pages-from-screen-manifest.sh の manifest_hash() と同じ実装。
manifest_hash() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    jq -cjS . "$file" | shasum -a 256 | awk '{print $1}'
  else
    jq -cjS . "$file" | sha256sum | awk '{print $1}'
  fi
}

# 画面基本設計書.md から §6 画面遷移の業務文脈のデータ行を
# TSV(fromName\ttoName\ttrigger)として抽出する。
#
# 見出しの一致は「## §6 画面遷移の業務文脈」で始まる行の前方一致とする。次の見出し(##)で
# 節を抜ける。プレースホルダ行(いずれかの列に<実測: ...>を含む雛形の行)は除外する
# (既存抽出器(extract-entity-state-page-data.sh・extract-er-page-data.sh)と同じ扱い)。
extract_transition_rows() {
  local doc_file="$1"
  awk '
    function trim(s) {
      gsub(/^[ \t]+|[ \t]+$/, "", s)
      return s
    }
    function strip_backtick(s) {
      gsub(/^`+|`+$/, "", s)
      return s
    }
    BEGIN { in_section = 0; header_seen = 0 }
    /^## / {
      if (in_section == 1) { exit }
      in_section = ($0 ~ /^## §6 画面遷移の業務文脈/) ? 1 : 0
      next
    }
    in_section == 0 { next }
    /^\|---/ { header_seen = 1; next }
    /^\|/ {
      if (header_seen == 0) { next }  # 列名行(ヘッダ)はスキップ。区切り行の後だけデータ行を採る
      line = $0
      sub(/^\|/, "", line)
      sub(/\|[ \t]*$/, "", line)
      n = split(line, cols, "|")
      if (n < 5) { next }
      fromname = strip_backtick(trim(cols[1]))
      tocarry = strip_backtick(trim(cols[2]))
      toname = strip_backtick(trim(cols[3]))
      handoff = strip_backtick(trim(cols[4]))
      trigger = strip_backtick(trim(cols[5]))
      if (fromname ~ /<実測/ || tocarry ~ /<実測/ || toname ~ /<実測/ || handoff ~ /<実測/ || trigger ~ /<実測/) { next }
      if (fromname == "" || toname == "") { next }
      printf "%s\t%s\t%s\n", fromname, toname, trigger
    }
  ' "$doc_file"
}

run() {
  local output_dir="$1" dest_file="$2"
  local layout_json screen_unit_rel root_dir manifest_rel manifest_file
  local work
  work="$(mktemp -d "${TMPDIR:-/tmp}/extract-transition-page-data.XXXXXX")" || return 1
  trap 'rm -rf "$work"' RETURN
  layout_json="$(resolve_output_layout "$output_dir")" || return 1
  screen_unit_rel="$(output_layout_get "$layout_json" screenUnitRoot)" || return 1
  root_dir="$output_dir/$screen_unit_rel"
  manifest_rel="$(output_layout_get "$layout_json" screenManifest)" || return 1
  manifest_file="$output_dir/$manifest_rel"

  if [ ! -f "$manifest_file" ] || ! jq empty "$manifest_file" >/dev/null 2>&1; then
    echo "ERROR: screen-manifest.json が見つからないか不正です: $manifest_file" >&2
    return 1
  fi

  local hash
  hash="$(manifest_hash "$manifest_file")" || return 1

  # nodes[]・manifestScreenCount・route空文字unresolved[]・name/idの解決マップを
  # bridge(build-detail-pages-from-screen-manifest.sh)と同じ規則でrawマニフェストから組み立てる。
  local base_json
  base_json="$(jq -S '
    def screen_label: (.confirmedScreenName // .screenNameGuess // .screenKey);
    def category:
      if ((.category // "") | length) > 0 then {value:.category, src:"url-segment"}
      elif ((.accountGroup // "") | length) > 0 then {value:.accountGroup, src:"account-group"}
      else {value:"その他", src:"fallback"} end;
    . as $m
    | [
        $m.screens[]?
        | select(((.route // "") | length) > 0)
        | category as $cat
        | {unitKey:.screenKey,label:screen_label,route:.route,category:$cat.value,categorySrc:$cat.src}
      ] | sort_by(.unitKey) as $nodes
    | [
        $m.screens[]?
        | select(((.route // "") | length) == 0)
        | {label:screen_label,reason:"routeが空文字列のため遷移解決不能"}
      ] | sort_by(.label) as $unresolvedRoute
    | {
        manifestScreenCount: ($m.screens | length),
        nodes: $nodes,
        unresolvedRoute: $unresolvedRoute,
        nameMap: ( [ $m.screens[]? | {key: screen_label, value: .screenKey} ] | from_entries ),
        idMap: ( [ $m.screens[]? | select((.screenId // "") | length > 0) | {key: .screenId, value: .screenKey} ] | from_entries )
      }
  ' "$manifest_file")" || return 1

  local doc_files=""
  if [ -d "$root_dir" ]; then
    doc_files="$(find "$root_dir" -type f -name "画面基本設計書.md" | sort)"
  fi

  if [ -z "$doc_files" ]; then
    echo "WARN: 画面基本設計書.md が見つかりません: $root_dir" >&2
  fi

  # all_rows_tsv: ownKey\tfromName\ttoName\ttrigger
  local all_rows_tsv=""
  local file screen_dir screen_id own_key rows_tsv
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    screen_dir="$(dirname "$(dirname "$file")")"
    screen_id="$(basename "$screen_dir")"
    own_key="$(printf '%s' "$base_json" | jq -r --arg id "$screen_id" '.idMap[$id] // ""')"
    if [ -z "$own_key" ]; then
      echo "WARN: screenId がマニフェストに見つからないためスキップします: $file (screenId=$screen_id)" >&2
      continue
    fi

    rows_tsv="$(extract_transition_rows "$file")"
    if [ -n "$rows_tsv" ]; then
      while IFS=$'\t' read -r fromname toname trigger; do
        [ -z "$fromname" ] && continue
        all_rows_tsv="${all_rows_tsv}${own_key}	${fromname}	${toname}	${trigger}
"
      done < <(printf '%s\n' "$rows_tsv")
    fi
  done < <(printf '%s\n' "$doc_files")

  if [ -z "$all_rows_tsv" ]; then
    echo "WARN: §6 画面遷移の業務文脈のデータ行が0件でした(捏造せず空のedgesを書き出す): $root_dir" >&2
  fi

  # rows_json: [{ownKey,fromName,toName,trigger}]
  local rows_json
  rows_json="$(printf '%s' "$all_rows_tsv" | jq -R -s '
    split("\n") | map(select(length > 0)) | map(split("\t")) |
    map({ownKey: .[0], fromName: .[1], toName: .[2], trigger: (.[3] // "")})
  ')" || return 1

  # 「自画面」注記は当該文書自身のunitKey(ownKey)へ直接解決する(テキスト一致に頼らない)。
  # それ以外はnameMap(ラベル→unitKey)で解決する。どちらも解決できない側はunresolved[]へ回す。
  local name_map
  name_map="$(printf '%s' "$base_json" | jq '.nameMap')"

  # rows/nameMapは画面・遷移件数に比例する可変長の値であり、--argjson直渡しでは
  # jqの引数長上限を超えうる。一時ファイル経由の--slurpfileで渡す
  # (extract-table-metadata.shのmainColumns対策・extract-er-page-data.shと同じ設計)。
  local rows_file="$work/rows.json" name_map_file="$work/name-map.json"
  printf '%s' "$rows_json" > "$rows_file"
  printf '%s' "$name_map" > "$name_map_file"
  local result_json
  result_json="$(jq -n --slurpfile rows "$rows_file" --slurpfile nameMap "$name_map_file" --arg sourceRef "画面基本設計書.md#§6" '
    ($nameMap[0]) as $nameMap
    | def resolve(ownKey; name):
      if (name | test("自画面")) then
        (if (ownKey | length) > 0 then {ok:true, key:ownKey} else {ok:false} end)
      else
        ($nameMap[name]) as $k
        | if $k then {ok:true, key:$k} else {ok:false} end
      end;
    reduce $rows[0][] as $r (
      {edges: [], unresolved: []};
      (resolve($r.ownKey; $r.fromName)) as $fromR
      | (resolve($r.ownKey; $r.toName)) as $toR
      | if ($fromR.ok and $toR.ok) then
          .edges += [{from: $fromR.key, to: $toR.key, trigger: $r.trigger, sourceRef: $sourceRef, confidence: ""}]
        else
          .unresolved += [{
            label: ($r.fromName + " → " + $r.toName),
            reason: (
              if ((($fromR.ok) | not) and (($toR.ok) | not)) then
                "遷移元画面「" + $r.fromName + "」と遷移先画面「" + $r.toName + "」の両方が見つかりません(画面一覧未検出または未一致)"
              elif (($fromR.ok) | not) then
                "遷移元画面「" + $r.fromName + "」が見つかりません(画面一覧未検出または未一致)"
              else
                "遷移先画面「" + $r.toName + "」が見つかりません(画面一覧未検出または未一致)"
              end
            ),
            sourceRef: $sourceRef
          }]
        end
    )
  ')" || return 1

  local edge_count edges_status
  edge_count="$(printf '%s' "$result_json" | jq '.edges | length')"
  if [ "$edge_count" -gt 0 ]; then
    edges_status="抽出済み"
  else
    edges_status="未抽出"
  fi

  local generated_at
  generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # nodes/unresolvedRoute/edges/unresolvedRowsは画面・遷移件数に比例する可変長の値。
  # --argjson直渡しでは引数長上限を超えうるため一時ファイル経由の--slurpfileで渡す
  # (extract-table-metadata.shのmainColumns対策・extract-er-page-data.shと同じ設計)。
  # manifestScreenCountは数値1件の固定長だが、渡し方を統一するため同じ経路にする。
  local nodes_file="$work/nodes.json" screen_count_file="$work/screen-count.json" \
    unresolved_route_file="$work/unresolved-route.json" edges_file="$work/edges.json" \
    unresolved_rows_file="$work/unresolved-rows.json"
  printf '%s' "$base_json" | jq '.nodes' > "$nodes_file"
  printf '%s' "$base_json" | jq '.manifestScreenCount' > "$screen_count_file"
  printf '%s' "$base_json" | jq '.unresolvedRoute' > "$unresolved_route_file"
  printf '%s' "$result_json" | jq '.edges' > "$edges_file"
  printf '%s' "$result_json" | jq '.unresolved' > "$unresolved_rows_file"

  local page_data
  page_data="$(jq -n \
    --slurpfile nodes "$nodes_file" \
    --slurpfile screenCount "$screen_count_file" \
    --slurpfile unresolvedRoute "$unresolved_route_file" \
    --slurpfile edges "$edges_file" \
    --slurpfile unresolvedRows "$unresolved_rows_file" \
    --arg hash "$hash" \
    --arg generatedAt "$generated_at" \
    --arg edgesStatus "$edges_status" \
    '{
      pageKind: "transition",
      generatedAt: $generatedAt,
      manifestContentHash: $hash,
      manifestScreenCount: $screenCount[0],
      title: "画面遷移図",
      description: "画面基本設計書.md §6 画面遷移の業務文脈に記載された遷移を可視化する。",
      legend: [ { symbol: "□", meaning: "画面" } ],
      nodes: $nodes[0],
      edges: $edges[0],
      edgesStatus: $edgesStatus,
      unresolved: ($unresolvedRoute[0] + $unresolvedRows[0])
    }')" || return 1

  mkdir -p "$(dirname "$dest_file")"
  printf '%s\n' "$page_data" > "$dest_file"
}

self_test() {
  local tmp pass=0 fail=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/transition-page-data.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/docs/manifests"
  cat > "$tmp/docs/manifests/screen-manifest.json" <<'EOF'
{
  "screens": [
    {"screenId": "screen-order-list", "screenKey": "order-list", "route": "/orders", "screenNameGuess": "注文一覧"},
    {"screenId": "screen-order-detail", "screenKey": "order-detail", "route": "/orders/:id", "screenNameGuess": "注文詳細"},
    {"screenId": "screen-member-list", "screenKey": "member-list", "route": "/members", "screenNameGuess": "会員一覧"},
    {"screenId": "screen-sidebar-nav", "screenKey": "sidebar-nav", "route": "", "screenNameGuess": "サイドバーナビ"}
  ]
}
EOF

  mkdir -p "$tmp/docs/design/screens/screen-order-list/基本設計"
  cat > "$tmp/docs/design/screens/screen-order-list/基本設計/画面基本設計書.md" <<'EOF'
---
doc_id: screen-order-list
type: screen-basic-design
screen_name: 注文一覧
status: draft
---

# 注文一覧 画面基本設計書

## §6 画面遷移の業務文脈

| 遷移元画面 | 引き継ぐ業務情報 | 遷移先画面 | 引き渡す業務情報 | 遷移する業務上の契機 |
|---|---|---|---|---|
| なし（起点画面） | ― | 注文詳細 | 選択した注文番号 | 一覧の行をクリックしたとき |
| `<実測: 遷移元画面>` | `<実測: 情報>` | `<実測: 遷移先画面>` | `<実測: 情報>` | `<実測: 契機>` |
EOF

  mkdir -p "$tmp/docs/design/screens/screen-order-detail/基本設計"
  cat > "$tmp/docs/design/screens/screen-order-detail/基本設計/画面基本設計書.md" <<'EOF'
---
doc_id: screen-order-detail
type: screen-basic-design
screen_name: 注文詳細
status: draft
---

# 注文詳細 画面基本設計書

## §6 画面遷移の業務文脈

| 遷移元画面 | 引き継ぐ業務情報 | 遷移先画面 | 引き渡す業務情報 | 遷移する業務上の契機 |
|---|---|---|---|---|
| 注文一覧 | 選択した注文番号 | 注文詳細（自画面） | 表示対象の注文情報 | 一覧の行をクリックしたとき |
| 注文詳細（自画面） | 更新後のステータス | 会員一覧 | なし | 詳細から会員情報を確認する操作 |
| 注文詳細（自画面） | 更新後のステータス | 存在しない画面X | なし | 謎の操作 |
EOF

  local self_path
  self_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  local out="$tmp/out/page-data.json"
  if bash "$self_path" "$tmp" "$out" >/dev/null 2>"$tmp/stderr1.log"; then
    echo "  [PASS] 正常系: 2文書・有効行3件(+プレースホルダ1行)でexit 0" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 正常系: exit 0で終わらなかった" >&2
    cat "$tmp/stderr1.log" | sed 's/^/    /' >&2
    fail=$((fail + 1))
  fi

  # 検査1: nodesがroute非空の3画面(unitKey昇順)、manifestScreenCountが4であること
  local ok1=1
  [ "$(jq -r '[.nodes[].unitKey] | join(",")' "$out" 2>/dev/null)" = "member-list,order-detail,order-list" ] || ok1=0
  [ "$(jq -r '.manifestScreenCount' "$out" 2>/dev/null)" = "4" ] || ok1=0
  local hash1
  hash1="$(jq -r '.manifestContentHash' "$out" 2>/dev/null)"
  [[ "$hash1" =~ ^[0-9a-f]{64}$ ]] || ok1=0
  if [ "$ok1" -eq 1 ]; then
    echo "  [PASS] 検査1: nodesがroute非空3画面・manifestScreenCount=4・manifestContentHashが64桁hex" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査1: nodes/manifestScreenCount/manifestContentHashのいずれかが不正" >&2
    fail=$((fail + 1))
  fi

  # 検査2: edgesが2件(注文一覧→注文詳細(自画面解決)、注文詳細(自画面解決)→会員一覧)で、
  # sourceRef="画面基本設計書.md#§6"・confidence=""であること
  local ok2=1
  [ "$(jq -r '.edges | length' "$out" 2>/dev/null)" = "2" ] || ok2=0
  [ "$(jq -r '[.edges[] | select(.from=="order-list" and .to=="order-detail")] | length' "$out" 2>/dev/null)" = "1" ] || ok2=0
  [ "$(jq -r '[.edges[] | select(.from=="order-detail" and .to=="member-list")] | length' "$out" 2>/dev/null)" = "1" ] || ok2=0
  [ "$(jq -r '[.edges[].sourceRef] | unique | join(",")' "$out" 2>/dev/null)" = "画面基本設計書.md#§6" ] || ok2=0
  [ "$(jq -r '[.edges[].confidence] | unique | join(",")' "$out" 2>/dev/null)" = "" ] || ok2=0
  [ "$(jq -r '.edgesStatus' "$out" 2>/dev/null)" = "抽出済み" ] || ok2=0
  if [ "$ok2" -eq 1 ]; then
    echo "  [PASS] 検査2: edgesが2件・自画面解決・sourceRef固定値・confidence空文字・edgesStatus=抽出済み" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査2: edgesの組み立てに不一致がある" >&2
    fail=$((fail + 1))
  fi

  # 検査3: unresolvedが3件(route空文字1件+lookup失敗2件)であること
  # (labelsを変数へ捕捉してから[[ == *pattern* ]]で判定する。pipefail下でprintf|grep -qを使うと、
  #  grep -qが早期に一致してパイプを閉じた際に上流がSIGPIPEで非0終了し、pipefailにより
  #  誤ってok3=0になる既知の落とし穴があるため、パイプを使わない判定に統一する)
  local ok3=1
  local labels3
  labels3="$(jq -r '.unresolved[].label' "$out" 2>/dev/null)"
  [ "$(jq -r '.unresolved | length' "$out" 2>/dev/null)" = "3" ] || ok3=0
  [ "$(jq -r '[.unresolved[] | select(.reason=="routeが空文字列のため遷移解決不能")] | length' "$out" 2>/dev/null)" = "1" ] || ok3=0
  case "$labels3" in
    *"なし（起点画面） → 注文詳細"*) : ;;
    *) ok3=0 ;;
  esac
  case "$labels3" in
    *"注文詳細（自画面） → 存在しない画面X"*) : ;;
    *) ok3=0 ;;
  esac
  if [ "$ok3" -eq 1 ]; then
    echo "  [PASS] 検査3: unresolvedが3件(route空文字1件+lookup失敗2件)で理由が正しく記録される" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査3: unresolvedの組み立てに不一致がある" >&2
    fail=$((fail + 1))
  fi

  # 検査4: build-detail-page.sh --page transition に通し、実際にHTMLが生成されること
  local ok4=1
  local build_detail_page_sh="$SCRIPT_DIR/../detail-pages/build-detail-page.sh"
  local html_out_dir="$tmp/html-out"
  mkdir -p "$html_out_dir"
  if bash "$build_detail_page_sh" "$out" "$html_out_dir" --page transition >/dev/null 2>"$tmp/stderr4.log"; then
    [ -f "$html_out_dir/画面遷移図.html" ] || ok4=0
  else
    ok4=0
  fi
  if [ "$ok4" -eq 1 ]; then
    echo "  [PASS] 検査4: build-detail-page.sh --page transition で画面遷移図.htmlが生成される" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査4: 画面遷移図.htmlの生成に失敗した" >&2
    cat "$tmp/stderr4.log" | sed 's/^/    /' >&2
    fail=$((fail + 1))
  fi

  # 検査5: 画面基本設計書.mdが1件も無い場合、edges0件・edgesStatus=未抽出・WARNでexit 0であること
  local t5_root t5_dest t5_output t5_rc ok5=1
  t5_root="$(mktemp -d "${TMPDIR:-/tmp}/transition-page-data-t5.XXXXXX")"
  mkdir -p "$t5_root/docs/manifests"
  cp "$tmp/docs/manifests/screen-manifest.json" "$t5_root/docs/manifests/screen-manifest.json"
  local t5_dest_dir="$t5_root/out"
  mkdir -p "$t5_dest_dir"
  t5_dest="$t5_dest_dir/page-data.json"
  t5_output="$(bash "$self_path" "$t5_root" "$t5_dest" 2>&1)"
  t5_rc=$?
  [ "$t5_rc" -eq 0 ] || ok5=0
  case "$t5_output" in
    *WARN*) : ;;
    *) ok5=0 ;;
  esac
  [ "$(jq -r '.edges | length' "$t5_dest" 2>/dev/null)" = "0" ] || ok5=0
  [ "$(jq -r '.edgesStatus' "$t5_dest" 2>/dev/null)" = "未抽出" ] || ok5=0
  [ "$(jq -r '.pageKind' "$t5_dest" 2>/dev/null)" = "transition" ] || ok5=0
  rm -rf "$t5_root"
  if [ "$ok5" -eq 1 ]; then
    echo "  [PASS] 検査5: 画面基本設計書.md不在時はedges0件・edgesStatus=未抽出・WARNでexit 0" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査5: 画面基本設計書.md不在時の挙動が不正" >&2
    fail=$((fail + 1))
  fi

  # 検査6: screen-manifest.json自体が存在しない場合はexit 1であること(transitionはnodes/hashを
  # 復元できず、entity-state/erと異なり空page-dataでの継続を許さない)
  local t6_root t6_dest t6_rc ok6=1
  t6_root="$(mktemp -d "${TMPDIR:-/tmp}/transition-page-data-t6.XXXXXX")"
  t6_dest="$t6_root/out/page-data.json"
  bash "$self_path" "$t6_root" "$t6_dest" >/dev/null 2>"$t6_root/stderr.log"
  t6_rc=$?
  [ "$t6_rc" -eq 1 ] || ok6=0
  [ -f "$t6_dest" ] && ok6=0
  rm -rf "$t6_root"
  if [ "$ok6" -eq 1 ]; then
    echo "  [PASS] 検査6: screen-manifest.json不在時はexit 1で何も書き出さない" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査6: screen-manifest.json不在時の挙動が不正" >&2
    fail=$((fail + 1))
  fi

  echo "self-test: ${pass} PASS, ${fail} FAIL" >&2
  [ "$fail" -eq 0 ]
}

if [ "${1:-}" = "--self-test" ]; then
  if self_test; then exit 0; else exit 1; fi
fi

output_dir="${1:?引数1 output_dir が必要です}"
dest_file="${2:?引数2 出力page-data.jsonのパス が必要です}"

if [ ! -d "$output_dir" ]; then
  echo "ERROR: output_dir が存在しません: $output_dir" >&2
  exit 1
fi

run "$output_dir" "$dest_file"
