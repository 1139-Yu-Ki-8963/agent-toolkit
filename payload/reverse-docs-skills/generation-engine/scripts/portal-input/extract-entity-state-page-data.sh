#!/usr/bin/env bash
# extract-entity-state-page-data.sh — データ設計.md §6 状態遷移表から entity-state 用の
# page-data.json（nodes[]/edges[]）を機械的に組み立てる
#
# 背景(改善課題1-26 段階1。docs/tasks/関連図の内製化の指示書.md 5節 段階1):
# 状態遷移図の生成(build-detail-page.sh --page entity-state)はpage-data.jsonを要求するが、
# これまでこの入力データを組み立てる決定的な経路が存在せず、
# generating-entity-state-for-reverse-docsスキルの対話的な抽出(Claude自身のRead/Write)にのみ
# 依存していた。本スクリプトはデータ設計.md §6状態遷移表（エンティティ/状態/遷移前/契機/
# 遷移後の5列）を機械的に読み、page-data.jsonを組み立てる決定的な処理を提供する。
# データ設計.mdテンプレート側(delivery-payload/templates/リバース検証/プロジェクト共通/データ設計.md)
# には一切手を入れない(段階1の禁止事項)。
#
# 列構成の変遷(改善課題1-240): 段階1新設時点のテンプレートは6列(末尾に「根拠パス」列)
# だったが、改善課題1-234でテンプレートの§6状態遷移表から根拠パス列が削除され、現行は
# 5列(エンティティ/状態/遷移前/契機/遷移後)のみになった。現行テンプレートに証跡パスを
# 持つ列は存在しないため、edges[].sourceRefは値を持たない設計(常に空文字列)とする。
# 別の列から証跡パス相当の情報を拾う設計は採らない(5列のいずれも証跡パスの性質を
# 持たないため)。sourceRefキー自体はpage-data-schema.mdのT7スキーマ・
# build-detail-page.shの表示側(detail-t7-entity-state.html。`e.sourceRef || ''`で
# 空文字列を許容する)と整合させるため残す。
#
# Usage:
#   extract-entity-state-page-data.sh <output_dir> <出力page-data.jsonのパス>
#   extract-entity-state-page-data.sh --self-test
#
#   <output_dir>                データ設計.md が展開済みのプロジェクトルート
#                                (output-layout.json の dataDesignDoc を <output_dir> からの
#                                相対で解決する)
#   <出力page-data.jsonのパス>   組み立てた page-data.json を書き出すファイルパス
#
# データ設計.md が不在、§6 状態遷移表の見出しが不在、またはデータ行が0件(雛形のプレースホルダ
# 行<実測: ...>のみを含む状態)の場合は、nodes/edgesが空のpage-data.jsonを書き出し、WARNを
# stderrへ出してexit 0で終える(build-manifests-from-docs.shの0件時フェイルセーフと同じ設計。
# 遷移を捏造しない)。
#
# 設計判断の正本: docs/design/generation-engine/portal-input/詳細設計書.md
# 「## extract-entity-state-page-data.sh」節。
# 保守責任者: 人手(ユーザー)。データ設計.md §6 の列構成を変える場合は本ファイルと
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

# データ設計.md から §6 状態遷移表のデータ行を
# TSV(entity\tstate\tbefore\ttrigger\tafter)として抽出する(改善課題1-240: 現行テンプレートは
# 5列で「根拠パス」列を持たないため、抽出対象も5列とする)。
#
# 見出しの一致は「## §6 状態遷移表」で始まる行の前方一致とする(テンプレート側の
# 「（実測）」サフィックスの有無を問わない。指示書4.3節の実測どおり、生成済み文書では
# サフィックスが落ちる場合があるため)。
# プレースホルダ行(いずれかの列に<実測: ...>を含む雛形の行)は除外する(捏造しない)。
extract_state_transition_rows() {
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
      in_section = ($0 ~ /^## §6 状態遷移表/) ? 1 : 0
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
      entity = strip_backtick(trim(cols[1]))
      state = strip_backtick(trim(cols[2]))
      before = strip_backtick(trim(cols[3]))
      trigger = strip_backtick(trim(cols[4]))
      after = strip_backtick(trim(cols[5]))
      if (entity ~ /<実測/ || state ~ /<実測/ || before ~ /<実測/ || trigger ~ /<実測/ || after ~ /<実測/) { next }
      if (entity == "" || state == "" || before == "" || after == "") { next }
      printf "%s\t%s\t%s\t%s\t%s\n", entity, state, before, trigger, after
    }
  ' "$doc_file"
}

# TSV行(entity/state/before/trigger/after)からnodes[]/edges[]を組み立てる。
# 現行テンプレート(5列)は証跡パスに相当する列を持たないため、edges[].sourceRefは
# 常に空文字列とする(改善課題1-240)。
#
# nodes[] の集め方は generating-entity-state-for-reverse-docs スキル(Phase 2 Step 1)と
# 同じ規則にする(既存の生成済みサンプル generation-engine/samples/project-portal/diagrams/状態遷移図.html
# の埋め込みJSONと突き合わせて確認済み): 各行について「状態」列 → 「遷移前」列 → 「遷移後」列の
# 順で(エンティティ, 状態)の組を集め、初出順を保ったまま重複を除く。この順序でなければ、
# 対応スキルが既に生成した実測サンプルの並びと一致しない。
#
# jqのオブジェクトはキー挿入順序を仕様上保証しないため、`seen`はメンバーシップ判定にのみ使い、
# 並び順は別配列`order`で明示的に保持する(判定と順序保持を分離する設計)。
build_page_data_from_rows() {
  local rows_tsv="$1"
  local rows_json
  rows_json="$(printf '%s' "$rows_tsv" | jq -R -s '
    split("\n") | map(select(length > 0)) | map(split("\t")) |
    map({entity: .[0], state: .[1], before: .[2], trigger: .[3], after: .[4]})
  ')" || return 1

  printf '%s' "$rows_json" | jq '
    (reduce .[] as $r (
      {order: [], seen: {}, edges: []};
      ([$r.entity + "" + $r.state, $r.entity + "" + $r.before, $r.entity + "" + $r.after]) as $cands
      | reduce $cands[] as $c (.;
          if (.seen[$c] // false) then .
          else .order += [$c] | .seen[$c] = true
          end
        )
      | .edges += [{
          from: ($r.entity + "." + $r.before),
          to: ($r.entity + "." + $r.after),
          trigger: $r.trigger,
          sourceRef: "",
          entity: $r.entity
        }]
    )) as $acc
    | {
        nodes: [ $acc.order[] | split("") as $p | {key: ($p[0] + "." + $p[1]), label: $p[1], entity: $p[0]} ],
        edges: $acc.edges
      }
  '
}

run() {
  local output_dir="$1" dest_file="$2"
  local layout_json data_design_rel data_design_file
  layout_json="$(resolve_output_layout "$output_dir")" || return 1
  data_design_rel="$(output_layout_get "$layout_json" dataDesignDoc)" || return 1
  data_design_file="$output_dir/$data_design_rel"

  local rows_tsv=""
  if [ -f "$data_design_file" ]; then
    rows_tsv="$(extract_state_transition_rows "$data_design_file")"
  else
    echo "WARN: データ設計.md が見つかりません: $data_design_file" >&2
  fi

  if [ -z "$rows_tsv" ]; then
    echo "WARN: §6 状態遷移表のデータ行が0件でした(捏造せず空のnodes/edgesを書き出す): $data_design_file" >&2
  fi

  local nodes_edges_json
  nodes_edges_json="$(build_page_data_from_rows "$rows_tsv")" || return 1

  local generated_at
  generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local page_data
  page_data="$(printf '%s' "$nodes_edges_json" | jq \
    --arg generatedAt "$generated_at" \
    '{
      pageKind: "entity-state",
      generatedAt: $generatedAt,
      title: "状態遷移図",
      description: "データ設計.md §6 状態遷移表に記載されたエンティティの状態遷移を可視化する。",
      unresolved: [],
      legend: [ { symbol: "→", meaning: "状態遷移" } ],
      nodes: .nodes,
      edges: .edges
    }')" || return 1

  mkdir -p "$(dirname "$dest_file")"
  printf '%s\n' "$page_data" > "$dest_file"
}

self_test() {
  local tmp pass=0 fail=0
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/extract-entity-state-selftest.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/docs/design/common"
  cat > "$tmp/docs/design/common/データ設計.md" <<'EOF'
---
doc_id: data-design
type: data-design
status: draft
updated: 2026-08-17
---

# データ設計書（リバース版）

## §6 状態遷移表（実測）

| エンティティ | 状態 | 遷移前 | 契機 | 遷移後 |
|---|---|---|---|---|
| 注文 | 確定 | 下書き | 注文確認画面の確定操作 | 確定 |
| 注文 | 出荷済 | 確定 | 出荷バッチ（日次） | 出荷済 |
| 注文 | キャンセル | 確定 | POST /api/orders/:id/cancel | キャンセル |

---

## traced の条件

- 全節の実測値が埋まっていること
EOF

  local self_path
  self_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  local out="$tmp/out/page-data.json"
  if bash "$self_path" "$tmp" "$out" >/dev/null 2>"$tmp/stderr1.log"; then
    echo "  [PASS] 正常系: 3行のデータ行でexit 0" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 正常系: exit 0で終わらなかった" >&2
    fail=$((fail + 1))
  fi

  # 検査1: nodesの並びが「状態→遷移前→遷移後」の初出順(重複除去)と一致すること
  # (実サンプル generation-engine/samples/project-portal/diagrams/状態遷移図.html の埋め込みJSONと
  #  同じ並び規則であることを確認済み)
  local ok1=1
  local nodes_keys
  nodes_keys="$(jq -r '[.nodes[].key] | join(",")' "$out" 2>/dev/null)"
  [ "$nodes_keys" = "注文.確定,注文.下書き,注文.出荷済,注文.キャンセル" ] || ok1=0
  if [ "$ok1" -eq 1 ]; then
    echo "  [PASS] 検査1: nodesが状態→遷移前→遷移後の初出順で重複なく並ぶ" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査1: nodesの並びが不一致(実際: $nodes_keys)" >&2
    fail=$((fail + 1))
  fi

  # 検査2: edgesのfrom/toが正しく組み立ち、sourceRefは値を持たない設計(常に空文字列)
  # であること(改善課題1-240: 現行テンプレート5列に証跡パス列が無いため)
  local ok2=1
  [ "$(jq -r '.edges[0].from' "$out" 2>/dev/null)" = "注文.下書き" ] || ok2=0
  [ "$(jq -r '.edges[0].to' "$out" 2>/dev/null)" = "注文.確定" ] || ok2=0
  [ "$(jq -r '.edges[0].sourceRef' "$out" 2>/dev/null)" = "" ] || ok2=0
  [ "$(jq -r '.edges | length' "$out" 2>/dev/null)" = "3" ] || ok2=0
  [ "$(jq -r '.pageKind' "$out" 2>/dev/null)" = "entity-state" ] || ok2=0
  if [ "$ok2" -eq 1 ]; then
    echo "  [PASS] 検査2: edgesのfrom/toが正しく組み立ち、sourceRefは空文字列である" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査2: edgesの組み立てに不一致がある" >&2
    fail=$((fail + 1))
  fi

  # 検査3: build-detail-page.sh --page entity-state に通し、実際にHTMLが生成されること
  # (段階1の完了条件: 状態遷移図が実測で生成されることを確かめる)
  local ok3=1
  local build_detail_page_sh="$SCRIPT_DIR/../detail-pages/build-detail-page.sh"
  local html_out_dir="$tmp/html-out"
  mkdir -p "$html_out_dir"
  if bash "$build_detail_page_sh" "$out" "$html_out_dir" --page entity-state >/dev/null 2>"$tmp/stderr3.log"; then
    [ -f "$html_out_dir/状態遷移図.html" ] || ok3=0
  else
    ok3=0
  fi
  if [ "$ok3" -eq 1 ]; then
    echo "  [PASS] 検査3: build-detail-page.sh --page entity-state で状態遷移図.htmlが生成される" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査3: 状態遷移図.htmlの生成に失敗した" >&2
    cat "$tmp/stderr3.log" | sed 's/^/    /' >&2
    fail=$((fail + 1))
  fi

  # 検査4: データ設計.mdが雛形のまま(プレースホルダ行のみ)の場合、0件のpage-data.jsonを
  # 書き出しWARNを出しつつexit 0であること(捏造しない)
  local t4_root t4_out t4_output t4_rc ok4=1
  if ! t4_root="$(mktemp -d "${TMPDIR:-/tmp}/extract-entity-state-t4.XXXXXX" 2>/dev/null)" || [ -z "$t4_root" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼" >&2
    exit 2
  fi
  mkdir -p "$t4_root/docs/design/common"
  cat > "$t4_root/docs/design/common/データ設計.md" <<'EOF'
## §6 状態遷移表（実測）

| エンティティ | 状態 | 遷移前 | 契機 | 遷移後 |
|---|---|---|---|---|
| `<実測: エンティティ名>` | `<実測: 状態名>` | `<実測: 遷移前の状態>` | `<実測: 遷移の契機（イベント・操作）>` | `<実測: 遷移後の状態>` |
EOF
  local t4_dest="$t4_root/out/page-data.json"
  t4_output="$(bash "$self_path" "$t4_root" "$t4_dest" 2>&1)"
  t4_rc=$?
  [ "$t4_rc" -eq 0 ] || ok4=0
  printf '%s' "$t4_output" | grep -q "WARN" || ok4=0
  [ "$(jq -r '.nodes | length' "$t4_dest" 2>/dev/null)" = "0" ] || ok4=0
  [ "$(jq -r '.edges | length' "$t4_dest" 2>/dev/null)" = "0" ] || ok4=0
  rm -rf "$t4_root"
  if [ "$ok4" -eq 1 ]; then
    echo "  [PASS] 検査4: プレースホルダ行のみの場合0件のpage-data.jsonとWARNでexit 0" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査4: プレースホルダ行のみの場合の挙動が不正" >&2
    fail=$((fail + 1))
  fi

  # 検査5: データ設計.md自体が存在しない場合も0件のpage-data.jsonとWARNでexit 0であること
  local t5_root t5_out t5_output t5_rc ok5=1
  if ! t5_root="$(mktemp -d "${TMPDIR:-/tmp}/extract-entity-state-t5.XXXXXX" 2>/dev/null)" || [ -z "$t5_root" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼" >&2
    exit 2
  fi
  local t5_dest="$t5_root/out/page-data.json"
  t5_output="$(bash "$self_path" "$t5_root" "$t5_dest" 2>&1)"
  t5_rc=$?
  [ "$t5_rc" -eq 0 ] || ok5=0
  printf '%s' "$t5_output" | grep -q "WARN" || ok5=0
  [ "$(jq -r '.nodes | length' "$t5_dest" 2>/dev/null)" = "0" ] || ok5=0
  rm -rf "$t5_root"
  if [ "$ok5" -eq 1 ]; then
    echo "  [PASS] 検査5: データ設計.md不在でも0件のpage-data.jsonとWARNでexit 0" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査5: データ設計.md不在時の挙動が不正" >&2
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
