#!/usr/bin/env bash
# detail-pages系(用語辞書/技術スタック/画面遷移図/ER図/環境構築手順)共通ビルダー。
# page-data.json + --page 指定から、対応するテンプレートへ描画したHTMLを固定ファイル名で
# <output-dir> 直下に書き出す。出力ファイル名は build-portal.sh の FUTURE_FILES と同値。
#
# Usage: build-detail-page.sh <page-data.json> <output-dir> --page glossary|techstack|transition|er|env|entity-state|release-notes|design-system|component-inventory|icon-catalog [--portal-dir <path>] [--generated-at <iso8601>] [--project-name <name>] [--catalog <file>]
#        build-detail-page.sh --self-test
#
# page → (テンプレートファイル, 固定出力ファイル名) 対応は本スクリプト内の
# get_page_template/get_page_filename に固定する(build-unit-list.shの--unit-kindクロスチェックと同型)。
# data JSONのpageKindと--pageの不一致、不正なJSON、不正な--page値はexit 1とし、部分出力を残さない。
# validate-page-data.shを内部実行し、PASSしない限り生成しない。
# 出力は<output-dir>内の一時ファイル経由のatomic move(同一ファイルシステム内でmvする)。
#
# 正本スキーマ: generation-engine/scripts/detail-pages/page-data-schema.md
#
# 関連エンティティ(スキーマ拡張フィールド。delivery-payload/references/manifest-schema-extensions.md):
# page-data内の任意の要素が relatedApis/callers/targetTables/foreignKeys/downstreamJobs の
# いずれか(非空配列)を持つ場合のみ、テンプレートの受け口マーカー <!--RELATED_ENTITIES--> を
# 「関連エンティティ」セクションHTMLへ置換する。全て不在なら空文字へ置換され、マーカーは
# <div id="unresolved-mount"> と同一行に置いてあるため現行出力と完全一致する(後方互換)。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

get_page_template() { case "$1" in glossary) echo "detail-t2-dictionary.html";; techstack) echo "detail-t3-attributes.html";; transition) echo "detail-t4-diagram.html";; er) echo "detail-t6-er.html";; env) echo "detail-t5-procedure.html";; entity-state) echo "detail-t7-entity-state.html";; release-notes) echo "detail-t7-release-notes.html";; design-system) echo "detail-t8-design-system.html";; component-inventory) echo "detail-t9-component-inventory.html";; icon-catalog) echo "detail-t10-icon-catalog.html";; esac; }
get_page_filename() { case "$1" in glossary) echo "用語辞書.html";; techstack) echo "技術スタック.html";; transition) echo "画面遷移図.html";; er) echo "ER図.html";; env) echo "環境構築手順.html";; entity-state) echo "状態遷移図.html";; release-notes) echo "リリースノート.html";; design-system) echo "デザインシステム.html";; component-inventory) echo "コンポーネント棚卸し.html";; icon-catalog) echo "アイコンカタログ.html";; esac; }
get_page_category() { case "$1" in glossary) echo "project";; techstack) echo "project";; env) echo "project";; release-notes) echo "project";; transition) echo "list";; er) echo "list";; entity-state) echo "list";; design-system) echo "design-tools";; component-inventory) echo "design-tools";; icon-catalog) echo "design-tools";; esac; }

# --- --portal-dir 未指定時の既定値の保険(改善課題1-212) ---
# design-system・component-inventory・icon-catalogはproject-portal/foundationへ
# 出力されるにもかかわらず、--portal-dir未指定時の既定値はrelease-notes以外
# 一律「index.html」(同階層)だったため、戻るリンクが解決しなかった。
# OUTPUT_DIRのパス要素からproject-portalを探し、そこから何階層深いかを数えて
# 相対パスを機械的に組み立てる。project-portalを含まない、または同階層(深さ0)の
# 場合は従来どおり「index.html」を返す(判定できない場合は安全側に倒す)。
# 呼び出し元が未確認のまま増える可能性があるため、page種別ではなくOUTPUT_DIRの
# 実際の構造から判定する(release-notesの既存の特別扱いは変更しない)。
default_back_link_depth() {
  local output_dir="${1%/}"
  local IFS=/
  local -a parts
  read -r -a parts <<< "$output_dir"
  local idx=-1 i=0 part
  for part in "${parts[@]}"; do
    if [ "$part" = "project-portal" ]; then
      idx=$i
    fi
    i=$((i + 1))
  done
  if [ "$idx" -lt 0 ]; then
    echo "index.html"
    return
  fi
  local total=${#parts[@]}
  local depth=$((total - idx - 1))
  if [ "$depth" -le 0 ]; then
    echo "index.html"
    return
  fi
  local prefix="" j=0
  while [ "$j" -lt "$depth" ]; do
    prefix="../$prefix"
    j=$((j + 1))
  done
  echo "${prefix}index.html"
}

# --- --self-test モード ---
# (a) バックスラッシュ・実マーカー文字列(\d+・{{PAGE_DATA_JSON}}・<!--DETAIL_TILES-->)を含む
#     フィクスチャで、埋め込みJSON(script#page-data)が入力のjq -S正規化と完全一致することを
#     techstackページで検証する
# (b) 出力HTMLに未解決の{{が残らないことを検証する
# (c) validate-page-dataが正常系PASS/異常系(pageKind不正)FAILを正しく返し、
#     build-detail-page.sh自体もpageKind不一致データをexit 1で拒否することを検証する。
#     加えて、存在しないtoを1本混ぜたtransitionの孤児edgeが、validate-page-data.shの
#     孤児参照検査でFAILし、build-detail-page.sh自体もexit 1で拒否することを検証する
# (d) glossary/transition/er/env/entity-state/release-notes/design-system/component-inventory/
#     icon-catalog の9種別それぞれについて、ファイル名対応(PAGE_FILENAME)・埋め込みJSON完全一致・
#     未解決{{なしを検証する(techstackはケースa/bで検証済み。10種別全てのPASS行が出揃うことを
#     条件とする。改善課題1-150: 従来は6種別のみが対象で、release-notes/design-system/
#     component-inventory/icon-catalogの4種別が自己テスト対象から漏れていた)
# (h) delivery-payload/templates/detail-pages/配下のテンプレート数と、本自己テストが扱うページ種別数が
#     一致することを検証する(改善課題1-150: 新規ページ種別の追加時に自己テスト対象への
#     追加漏れを機械的に検知するためのガード)
# (e) 関連エンティティ(スキーマ拡張フィールド)の有/無:
#     有: 拡張フィールド(relatedApis/targetTables/downstreamJobs)を持つtransitionフィクスチャで
#         「関連エンティティ」セクションと日本語ラベル+値一覧が出力されることを検証する
#     無: 拡張フィールドを持たないケースaの出力に「関連エンティティ」文字列・
#         未置換マーカー(RELATED_ENTITIES)が含まれないことを検証する(後方互換の証拠)
# (g) env の environment[](linux_compat_env)の描画有無:
#     true: 互換環境である旨の表記が出力に含まれることを検証する
#     false: 同じ表記が出力に含まれないことを検証する
#     空配列: エラーにならず生成できることを検証する
self_test() {
  local script_path="$0"
  local script_dir
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  local tmp rc=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/build-detail-page-self-test.XXXXXX")"
  # 補助関数・コマンド置換でも発火する RETURN/EXIT trap は使わず、self_test の
  # 通常終了直前にだけ一時ディレクトリを削除する。

  extract_page_data_json() {
    sed -n '/<script type="application\/json" id="page-data">/,/<\/script>/p' "$1" | sed '1d;$d'
  }

  # --- ケースa/b共通フィクスチャ: バックスラッシュ・マーカー文字列衝突 ---
  local data_a="$tmp/page-data-a.json"
  jq -n \
    --arg note 'GET /api/users/\d+' \
    --arg itemVal '<div>値</div>{{PAGE_DATA_JSON}}<!--DETAIL_TILES-->' \
    '{
      pageKind: "techstack",
      generatedAt: "2026-01-01T00:00:00Z",
      title: "技術スタック",
      description: "self-test用フィクスチャ",
      tiles: [{label: "言語", value: "TypeScript", note: $note}],
      columns: {item: "項目", value: "値", sourceRef: "出所"},
      rows: [{item: $itemVal, value: "5.4", sourceRef: "package.json:1"}]
    }' > "$data_a"

  local outdir_a="$tmp/out-a"
  local _gt_build_a_out
  if _gt_build_a_out="$(bash "$script_path" "$data_a" "$outdir_a" --page techstack 2>&1)"; then
    local out_html="$outdir_a/技術スタック.html"
    if [ -f "$out_html" ]; then
      local embedded_a="$tmp/embedded-a.json"
      local expected_a="$tmp/expected-a.json"
      local _gt_diff_a
      extract_page_data_json "$out_html" | jq -c -S . > "$embedded_a" 2>/dev/null || true
      jq -c -S . "$data_a" > "$expected_a"
      if _gt_diff_a="$(diff -u "$expected_a" "$embedded_a" 2>&1)"; then
        echo "  [PASS] ケースa: バックスラッシュ・マーカー文字列衝突を含むpage-dataでも埋め込みJSONが原本と完全一致"
      else
        echo "  [FAIL] ケースa: 埋め込みJSONが原本と不一致(誤爆の疑い)" >&2
        printf '%s\n' "$_gt_diff_a" | sed 's/^/    /' >&2
        rc=1
      fi
      # page-data埋め込みブロック(意図的にマーカー衝突文字列を含む)を除いた範囲でのみ
      # 未解決{{を検査する(埋め込みJSON自体は原本の一部としてケースaで別途完全一致を確認済み)
      local outside_a="$tmp/outside-a.html"
      sed '/<script type="application\/json" id="page-data">/,/<\/script>/d' "$out_html" > "$outside_a"
      if grep -qF '{{' "$outside_a"; then
        echo "  [FAIL] ケースb: page-data埋め込み範囲外に未解決の{{が残存" >&2
        rc=1
      else
        echo "  [PASS] ケースb: page-data埋め込み範囲外に未解決の{{が残らない"
      fi
    else
      echo "  [FAIL] ケースa: 出力ファイル ${out_html} が生成されなかった" >&2
      echo "  [FAIL] ケースb: 出力ファイル不在のため判定不能" >&2
      rc=1
    fi
  else
    echo "  [FAIL] ケースa: 生成コマンド自体が失敗した" >&2
    echo "  [FAIL] ケースb: 生成コマンド自体が失敗したため判定不能" >&2
    printf '%s\n' "$_gt_build_a_out" | sed 's/^/    /' >&2
    rc=1
  fi

  # --- ケースc: validate-page-dataのPASS/FAIL判定 + build-detail-page.sh自体の拒否確認 ---
  local data_bad="$tmp/page-data-bad.json"
  jq '.pageKind = "unknown-kind"' "$data_a" > "$data_bad"

  if _gt_out2="$(bash "$script_dir/validate-page-data.sh" "$data_a" >/dev/null 2>&1 \
     && ! bash "$script_dir/validate-page-data.sh" "$data_bad" 2>&1)"; then
    echo "  [PASS] ケースc: validate-page-dataが正常系PASS・異常系(pageKind不正)FAILを正しく返す"
  else
    echo "  [FAIL] ケースc: validate-page-dataのPASS/FAIL判定が期待通りでない" >&2
    printf '%s\n' "$_gt_out2" | sed 's/^/    /' >&2
    rc=1
  fi

  local outdir_bad="$tmp/out-bad"
  if _gt_out3="$(bash "$script_path" "$data_bad" "$outdir_bad" --page techstack 2>&1)"; then
    echo "  [FAIL] ケースc補: pageKind不正データの生成が誤ってPASSした" >&2
    printf '%s\n' "$_gt_out3" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] ケースc補: pageKind不正データはbuild-detail-page.shでも正しくexit 1"
  fi

  # --- ケースc補2: 孤児edge(存在しないtoを1本混ぜたtransition)がvalidate-page-data.shでFAIL・
  #     build-detail-page.sh自体もexit 1で拒否することを確認 ---
  local data_orphan="$tmp/page-data-orphan.json"
  jq -n '{
    pageKind: "transition",
    manifestContentHash: ("a"*64),
    manifestScreenCount: 2,
    generatedAt: "2026-01-01T00:00:00Z",
    title: "画面遷移図",
    description: "self-test用フィクスチャ(孤児edge混入)",
    legend: [{symbol: "□", meaning: "画面"}],
    nodes: [{unitKey: "home", label: "ホーム"}, {unitKey: "detail", label: "詳細"}],
    edges: [
      {from: "home", to: "detail", trigger: "クリック", sourceRef: "src/router.tsx:10", confidence: "high", section: "メインコンテンツ", triggerType: "リンク遷移"},
      {from: "home", to: "ghost", trigger: "存在しない遷移", sourceRef: "src/router.tsx:20", confidence: "low", section: "メインコンテンツ", triggerType: "リンク遷移"}
    ],
    unresolved: []
  }' > "$data_orphan"

  if _gt_out4="$(bash "$script_dir/validate-page-data.sh" "$data_orphan" 2>&1)"; then
    echo "  [FAIL] ケースc補2: 孤児edge混入データがvalidate-page-data.shで誤ってPASSした" >&2
    printf '%s\n' "$_gt_out4" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] ケースc補2: 孤児edge混入データはvalidate-page-data.shで正しくexit 1"
  fi

  local outdir_orphan="$tmp/out-orphan"
  if _gt_out5="$(bash "$script_path" "$data_orphan" "$outdir_orphan" --page transition 2>&1)"; then
    echo "  [FAIL] ケースc補2: 孤児edge混入データの生成がbuild-detail-page.shで誤ってPASSした" >&2
    printf '%s\n' "$_gt_out5" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] ケースc補2: 孤児edge混入データはbuild-detail-page.shでも正しくexit 1"
  fi

  # --- ケースd: glossary/transition/er/env のファイル名対応・埋め込みJSON一致・未解決{{なし ---
  check_page_fixture() {
    local page="$1" data_file="$2"
    local outdir="$tmp/out-$page"
    local expected_filename="$(get_page_filename "$page")"
    if ! _gt_out6="$(bash "$script_path" "$data_file" "$outdir" --page "$page" 2>&1)"; then
      echo "  [FAIL] ケースd(${page}): 生成コマンド自体が失敗した" >&2
      printf '%s\n' "$_gt_out6" | sed 's/^/    /' >&2
      rc=1
      return
    fi
    local out_html="$outdir/$expected_filename"
    if [ ! -f "$out_html" ]; then
      echo "  [FAIL] ケースd(${page}): 出力ファイル ${out_html} が生成されなかった(ファイル名対応不一致の疑い)" >&2
      rc=1
      return
    fi
    echo "  [PASS] ケースd(${page}): ファイル名対応(${expected_filename})で出力"

    local embedded expected
    embedded="$tmp/embedded-${page}.json"
    expected="$tmp/expected-${page}.json"
    extract_page_data_json "$out_html" | jq -c -S . > "$embedded" 2>/dev/null || true
    jq -c -S . "$data_file" > "$expected"
    if _gt_out7="$(diff -q "$embedded" "$expected" 2>&1)"; then
      echo "  [PASS] ケースd(${page}): 埋め込みJSONが原本と完全一致"
    else
      echo "  [FAIL] ケースd(${page}): 埋め込みJSONが原本と不一致(誤爆の疑い)" >&2
      printf '%s\n' "$_gt_out7" | sed 's/^/    /' >&2
      rc=1
    fi

    local outside="$tmp/outside-${page}.html"
    sed '/<script type="application\/json" id="page-data">/,/<\/script>/d' "$out_html" > "$outside"
    if grep -qF '{{' "$outside"; then
      echo "  [FAIL] ケースd(${page}): page-data埋め込み範囲外に未解決の{{が残存" >&2
      rc=1
    else
      echo "  [PASS] ケースd(${page}): page-data埋め込み範囲外に未解決の{{が残らない"
    fi
  }

  local data_glossary="$tmp/page-data-glossary.json"
  jq -n '{
    pageKind: "glossary",
    generatedAt: "2026-01-01T00:00:00Z",
    title: "用語辞書",
    description: "self-test用フィクスチャ",
    categories: [{key: "business", label: "業務"}, {key: "tech", label: "技術"}],
    terms: [
      {term: "注文", definition: "顧客が商品を購入する行為", codeRefs: ["src/models/order.ts:10"], category: "business", sourceRef: "src/models/order.ts:10"},
      {term: "セッション", definition: "認証状態を保持する仕組み", codeRefs: ["src/auth/session.ts:5"], category: "tech", sourceRef: "src/auth/session.ts:5"}
    ],
    unresolved: []
  }' > "$data_glossary"
  check_page_fixture glossary "$data_glossary"

  local data_transition="$tmp/page-data-transition.json"
  jq -n '{
    pageKind: "transition",
    manifestContentHash: ("a"*64),
    manifestScreenCount: 2,
    generatedAt: "2026-01-01T00:00:00Z",
    title: "画面遷移図",
    description: "self-test用フィクスチャ",
    legend: [{symbol: "□", meaning: "画面"}],
    nodes: [{unitKey: "home", label: "ホーム", category: "メイン", categorySrc: "url-segment"}, {unitKey: "detail", label: "詳細", category: "メイン", categorySrc: "url-segment"}],
    edges: [{from: "home", to: "detail", trigger: "クリック", sourceRef: "src/router.tsx:10", confidence: "high", section: "メインコンテンツ", triggerType: "リンク遷移"}],
    unresolved: [{label: "旧画面(route欠落)", reason: "旧形式manifestのためroute情報なし", sourceRef: "src/legacy/old-screen.tsx"}]
  }' > "$data_transition"
  check_page_fixture transition "$data_transition"

  local data_er="$tmp/page-data-er.json"
  jq -n '{
    pageKind: "er",
    generatedAt: "2026-01-01T00:00:00Z",
    title: "ER図",
    description: "self-test用フィクスチャ",
    legend: [{symbol: "1:N", meaning: "一対多"}],
    entities: [{key: "users", label: "users"}, {key: "orders", label: "orders"}],
    relations: [{from: "users", to: "orders", cardinality: "1:N", sourceRef: "migrations/001_init.sql:12"}],
    unresolved: []
  }' > "$data_er"
  check_page_fixture er "$data_er"

  local out_er_html="$tmp/out-er/ER図.html"
  if [ -f "$out_er_html" ] && grep -qF 'execCommand' "$out_er_html"; then
    echo "  [PASS] ケースf(er): clipboard フォールバック(execCommand)が出力に含まれる"
  else
    echo "  [FAIL] ケースf(er): clipboard フォールバック(execCommand)が出力に含まれない" >&2
    rc=1
  fi

  if [ -f "$out_er_html" ] && ! grep -qF 'class="er-flat-list"' "$out_er_html"; then
    echo "  [PASS] ケースk(er-relations有): relations[]が非空の通常系ではer-flat-listセクションが出力されない(後方互換)"
  else
    echo "  [FAIL] ケースk(er-relations有): relations[]が非空なのにer-flat-listセクションが出力された" >&2
    rc=1
  fi

  # --- 改善課題 1-151: 外部キー(relations[])0件でもentities[]全件のエンティティ俯瞰ページを生成する ---
  local data_er_no_fk="$tmp/page-data-er-no-fk.json"
  jq -n '{
    pageKind: "er",
    generatedAt: "2026-01-01T00:00:00Z",
    title: "ER図",
    description: "self-test用フィクスチャ(外部キー0件)",
    legend: [],
    entities: [
      {key: "tbl_users", label: "tbl_users", columns: [{name: "id", type: "BIGINT", pk: true}]},
      {key: "tbl_orders", label: "tbl_orders"},
      {key: "tbl_products", label: "tbl_products"}
    ],
    relations: [],
    unresolved: []
  }' > "$data_er_no_fk"

  local outdir_er_no_fk="$tmp/out-er-no-fk"
  local out_er_no_fk_html="$outdir_er_no_fk/ER図.html"
  if bash "$script_path" "$data_er_no_fk" "$outdir_er_no_fk" --page er >/dev/null 2>&1 \
     && [ -f "$out_er_no_fk_html" ]; then
    local outside_er_no_fk="$tmp/outside-er-no-fk.html"
    sed '/<script type="application\/json" id="page-data">/,/<\/script>/d' "$out_er_no_fk_html" > "$outside_er_no_fk"
    if grep -qF 'tbl_users' "$outside_er_no_fk" \
       && grep -qF 'tbl_orders' "$outside_er_no_fk" \
       && grep -qF 'tbl_products' "$outside_er_no_fk"; then
      echo "  [PASS] ケースk(er-relations無): エンティティ全件がpage-data埋め込み範囲外の静的HTMLに描画される"
    else
      echo "  [FAIL] ケースk(er-relations無): エンティティが静的HTMLに全件描画されていない" >&2
      rc=1
    fi
    if grep -qF '外部キーが宣言されていません' "$outside_er_no_fk"; then
      echo "  [PASS] ケースk(er-relations無): 外部キー0件である旨の明示が出力に含まれる"
    else
      echo "  [FAIL] ケースk(er-relations無): 外部キー0件である旨の明示が出力に含まれない" >&2
      rc=1
    fi
  else
    echo "  [FAIL] ケースk(er-relations無): 生成コマンド自体が失敗した" >&2
    rc=1
  fi

  local data_env="$tmp/page-data-env.json"
  jq -n '{
    pageKind: "env",
    generatedAt: "2026-01-01T00:00:00Z",
    title: "環境構築手順",
    description: "self-test用フィクスチャ",
    prerequisites: [{name: "Node.js", note: "v18以上"}],
    environment: [
      {name: "OS", value: "linux"},
      {name: "linux_compat_env", value: "Linux 互換環境上での実行"}
    ],
    steps: [
      {order: 2, command: "npm run dev", note: "開発サーバー起動"},
      {order: 1, command: "npm install", note: "依存関係インストール"}
    ],
    allocations: [{target: "devサーバー", value: "8000", sourceRef: "アーキテクチャ調査書.md#§3"}],
    unresolved: []
  }' > "$data_env"
  check_page_fixture env "$data_env"

  # --- ケースg: environment[](linux_compat_env)の描画有無 ---
  local out_env_html="$tmp/out-env/環境構築手順.html"
  if [ -f "$out_env_html" ] && grep -qF 'Linux 互換環境上での実行' "$out_env_html"; then
    echo "  [PASS] ケースg(env-true): linux_compat_env=trueの表記がHTMLに出力される"
  else
    echo "  [FAIL] ケースg(env-true): linux_compat_env=trueの表記がHTMLに出力されない" >&2
    rc=1
  fi

  local data_env_false="$tmp/page-data-env-false.json"
  jq -n '{
    pageKind: "env",
    generatedAt: "2026-01-01T00:00:00Z",
    title: "環境構築手順",
    description: "self-test用フィクスチャ(linux_compat_env=false)",
    prerequisites: [],
    environment: [
      {name: "OS", value: "darwin"},
      {name: "linux_compat_env", value: "該当なし"}
    ],
    steps: [],
    allocations: [],
    unresolved: []
  }' > "$data_env_false"
  local outdir_env_false="$tmp/out-env-false"
  if bash "$script_path" "$data_env_false" "$outdir_env_false" --page env >/dev/null 2>&1; then
    local out_env_false_html="$outdir_env_false/環境構築手順.html"
    if [ -f "$out_env_false_html" ] && ! grep -qF 'Linux 互換環境上での実行' "$out_env_false_html"; then
      echo "  [PASS] ケースg(env-false): linux_compat_env=falseの表記は出力されない"
    else
      echo "  [FAIL] ケースg(env-false): linux_compat_env=falseなのに互換環境表記が出力された" >&2
      rc=1
    fi
  else
    echo "  [FAIL] ケースg(env-false): 生成コマンド自体が失敗した" >&2
    rc=1
  fi

  local data_env_empty="$tmp/page-data-env-empty.json"
  jq -n '{
    pageKind: "env",
    generatedAt: "2026-01-01T00:00:00Z",
    title: "環境構築手順",
    description: "self-test用フィクスチャ(environment[]空配列)",
    prerequisites: [],
    environment: [],
    steps: [],
    allocations: [],
    unresolved: []
  }' > "$data_env_empty"
  local outdir_env_empty="$tmp/out-env-empty"
  if bash "$script_path" "$data_env_empty" "$outdir_env_empty" --page env >/dev/null 2>&1 \
     && [ -f "$outdir_env_empty/環境構築手順.html" ]; then
    echo "  [PASS] ケースg(env-empty): environment[]が空配列でもエラーにならず生成できる"
  else
    echo "  [FAIL] ケースg(env-empty): environment[]が空配列の場合に生成が失敗した" >&2
    rc=1
  fi

  local data_entity_state="$tmp/page-data-entity-state.json"
  jq -n '{
    pageKind: "entity-state",
    generatedAt: "2026-01-01T00:00:00Z",
    title: "状態遷移図",
    description: "self-test用フィクスチャ",
    legend: [{symbol: "→", meaning: "状態遷移"}],
    nodes: [
      {key: "注文.下書き", label: "下書き", entity: "注文"},
      {key: "注文.確定", label: "確定", entity: "注文"},
      {key: "顧客.仮登録", label: "仮登録", entity: "顧客"}
    ],
    edges: [
      {from: "注文.下書き", to: "注文.確定", trigger: "確定ボタン", sourceRef: "src/order.ts:10", entity: "注文"},
      {from: "注文.確定", to: "注文.下書き", trigger: "編集に戻す", sourceRef: "src/order.ts:20", entity: "注文"}
    ],
    unresolved: []
  }' > "$data_entity_state"
  check_page_fixture entity-state "$data_entity_state"

  # --- 改善課題 1-150: release-notes/design-system/component-inventory/icon-catalog を
  #     ケースd相当の自己テスト対象へ追加する(従来はtechstack/glossary/transition/er/env/
  #     entity-stateの6種別のみが対象だった) ---
  local data_release_notes="$tmp/page-data-release-notes.json"
  jq -n '{
    pageKind: "release-notes",
    generatedAt: "2026-01-01T00:00:00Z",
    title: "リリースノート",
    description: "self-test用フィクスチャ",
    releases: [{
      id: "2026-01-01-demo", date: "2026-01-01", title: "デモ機能追加", pr: 1, prUrl: "https://example.com/pr/1",
      flow: "feature",
      summary: [{label: "概要", text: "デモ機能を追加した"}],
      changes: [{type: "feat", text: "デモ画面を追加"}],
      verifySteps: [{title: "動作確認", checks: ["デモ画面が表示される"]}]
    }]
  }' > "$data_release_notes"
  check_page_fixture release-notes "$data_release_notes"

  # --- 1-203: 基盤/リリースノート.html はポータル直下ではなく1階層下に出力されるため、
  #     --portal-dir 未指定時もTOPリンクと共通サイドバーをポータルindexへ戻す ---
  local release_portal="$tmp/release-portal"
  local release_notes_dir="$release_portal/基盤"
  local release_notes_html="$release_notes_dir/リリースノート.html"
  local expected_release_index resolved_release_index
  local release_html_exists=false top_link_matches=false sidebar_link_matches=false
  local resolved_path_matches=false resolved_index_exists=false
  mkdir -p "$release_notes_dir"
  : > "$release_portal/index.html"
  if bash "$script_path" "$data_release_notes" "$release_notes_dir" --page release-notes >/dev/null 2>&1; then
    expected_release_index="$(python3 -c 'import os, sys; print(os.path.abspath(os.path.join(sys.argv[1], sys.argv[2])))' "$release_portal" "index.html")"
    resolved_release_index="$(python3 -c 'import os, sys; print(os.path.abspath(os.path.join(sys.argv[1], sys.argv[2])))' "$release_notes_dir" "../index.html")"
    if [ -f "$release_notes_html" ]; then release_html_exists=true; fi
    if grep -Fq '<a href="../index.html">TOP</a>' "$release_notes_html"; then top_link_matches=true; fi
    if grep -Fq 'data-portal-href="../index.html"' "$release_notes_html"; then sidebar_link_matches=true; fi
    if [ "$resolved_release_index" = "$expected_release_index" ]; then resolved_path_matches=true; fi
    if [ -f "$resolved_release_index" ]; then resolved_index_exists=true; fi
    if [ "$release_html_exists" = true ] && [ "$top_link_matches" = true ] \
       && [ "$sidebar_link_matches" = true ] && [ "$resolved_path_matches" = true ] \
       && [ "$resolved_index_exists" = true ]; then
      echo "  [PASS] 1-203: 基盤/リリースノート.htmlのTOP・サイドバーリンクが../index.htmlでポータルindexへ解決"
    else
      echo "  [FAIL] 1-203: 基盤/リリースノート.htmlのTOP・サイドバーリンクがポータルindexへ解決しない (html=${release_html_exists}, top=${top_link_matches}, sidebar=${sidebar_link_matches}, path=${resolved_path_matches}, index=${resolved_index_exists})" >&2
      rc=1
    fi
  else
    echo "  [FAIL] 1-203: 基盤/リリースノート.htmlの生成に失敗した" >&2
    rc=1
  fi

  local data_design_system="$tmp/page-data-design-system.json"
  jq -n '{
    pageKind: "design-system",
    generatedAt: "2026-01-01T00:00:00Z",
    title: "デザインシステム",
    description: "self-test用フィクスチャ",
    tokens: [{category: "color", name: "accent", value: "#FF6E4F", usage: "強調表示"}]
  }' > "$data_design_system"
  check_page_fixture design-system "$data_design_system"

  local data_component_inventory="$tmp/page-data-component-inventory.json"
  jq -n '{
    pageKind: "component-inventory",
    generatedAt: "2026-01-01T00:00:00Z",
    title: "コンポーネント棚卸し",
    description: "self-test用フィクスチャ",
    components: [{name: "Foo", path: "src/components/Foo.tsx", props: 1, usageCount: 2, files: ["src/components/Foo.tsx"]}]
  }' > "$data_component_inventory"
  check_page_fixture component-inventory "$data_component_inventory"

  local data_icon_catalog="$tmp/page-data-icon-catalog.json"
  jq -n '{
    pageKind: "icon-catalog",
    generatedAt: "2026-01-01T00:00:00Z",
    title: "アイコンカタログ",
    description: "self-test用フィクスチャ",
    icons: [{name: "home", sourceType: "material", usageCount: 3, files: ["src/components/Foo.tsx"]}]
  }' > "$data_icon_catalog"
  check_page_fixture icon-catalog "$data_icon_catalog"

  # --- 改善課題 1-132: 実在しないと判定された項目もabsentRows[]で根拠(sourceRef)を保持して描画する ---
  local data_techstack_absent="$tmp/page-data-techstack-absent.json"
  jq -n '{
    pageKind: "techstack",
    generatedAt: "2026-01-01T00:00:00Z",
    title: "技術スタック",
    description: "self-test用フィクスチャ(absentRows有)",
    tiles: [{label: "言語", value: "TypeScript", note: "package.jsonから実測"}],
    columns: {item: "項目", value: "値", sourceRef: "出所"},
    rows: [{item: "言語", value: "TypeScript 5.4", sourceRef: "package.json:1"}],
    absentRows: [
      {item: "GraphQL", value: "実在しない（理由: schemaファイル未検出）", sourceRef: "アーキテクチャ調査書.md#§2"},
      {item: "gRPC", value: "実在しない（理由: protoファイル未検出）", sourceRef: "アーキテクチャ調査書.md#§2"}
    ]
  }' > "$data_techstack_absent"

  local outdir_techstack_absent="$tmp/out-techstack-absent"
  local out_techstack_absent_html="$outdir_techstack_absent/技術スタック.html"
  if bash "$script_path" "$data_techstack_absent" "$outdir_techstack_absent" --page techstack >/dev/null 2>&1 \
     && [ -f "$out_techstack_absent_html" ]; then
    local outside_absent="$tmp/outside-techstack-absent.html"
    sed '/<script type="application\/json" id="page-data">/,/<\/script>/d' "$out_techstack_absent_html" > "$outside_absent"
    if grep -qF 'GraphQL' "$outside_absent" \
       && grep -qF 'gRPC' "$outside_absent" \
       && grep -qF 'アーキテクチャ調査書.md#§2' "$outside_absent"; then
      echo "  [PASS] ケースj(techstack-absent): absentRows[]の項目名・根拠パスがpage-data埋め込み範囲外の静的HTMLに現れる"
    else
      echo "  [FAIL] ケースj(techstack-absent): absentRows[]の項目名または根拠パスが静的HTMLに現れない" >&2
      rc=1
    fi
  else
    echo "  [FAIL] ケースj(techstack-absent): 生成コマンド自体が失敗した" >&2
    rc=1
  fi

  # --- 改善課題 1-150: テンプレート数と自己テストが扱う種別数の一致を検査する ---
  # ページ種別を追加した際に自己テストの対象へ入れ忘れることを機械的に検知するためのガード。
  local template_dir="$script_dir/../../../delivery-payload/templates/detail-pages"
  local template_count
  template_count="$(find "$template_dir" -maxdepth 1 -name '*.html' -type f 2>/dev/null | wc -l | tr -d ' ')"
  local tested_kinds="glossary techstack transition er env entity-state release-notes design-system component-inventory icon-catalog"
  local tested_count
  tested_count="$(printf '%s\n' $tested_kinds | wc -l | tr -d ' ')"
  if [ "$template_count" = "$tested_count" ]; then
    echo "  [PASS] ケースh: テンプレート数(${template_count})と自己テスト対象種別数(${tested_count})が一致"
  else
    echo "  [FAIL] ケースh: テンプレート数(${template_count})と自己テスト対象種別数(${tested_count})が不一致。新規ページ種別が自己テスト対象から漏れている可能性がある" >&2
    rc=1
  fi

  # --- ケースe: 関連エンティティ(スキーマ拡張フィールド)の有/無 ---
  local data_rel="$tmp/page-data-rel.json"
  jq -n '{
    pageKind: "transition",
    manifestContentHash: ("a"*64),
    manifestScreenCount: 2,
    generatedAt: "2026-01-01T00:00:00Z",
    title: "画面遷移図",
    description: "self-test用フィクスチャ(関連エンティティ有)",
    legend: [{symbol: "□", meaning: "画面"}],
    nodes: [
      {unitKey: "home", label: "ホーム", relatedApis: ["api-users-list", "api-posts-list"]},
      {unitKey: "batch-view", label: "バッチ確認", targetTables: ["users"], downstreamJobs: ["job-cleanup"]}
    ],
    edges: [{from: "home", to: "batch-view", trigger: "クリック", sourceRef: "src/router.tsx:10", confidence: "high", section: "メインコンテンツ", triggerType: "リンク遷移"}],
    unresolved: []
  }' > "$data_rel"

  local outdir_rel="$tmp/out-rel"
  local out_rel_html="$outdir_rel/画面遷移図.html"
  if bash "$script_path" "$data_rel" "$outdir_rel" --page transition >/dev/null 2>&1 && [ -f "$out_rel_html" ]; then
    local outside_rel="$tmp/outside-rel.html"
    sed '/<script type="application\/json" id="page-data">/,/<\/script>/d' "$out_rel_html" > "$outside_rel"
    if grep -qF '関連エンティティ' "$outside_rel" \
       && grep -qF '<li>関連API: api-users-list、api-posts-list</li>' "$outside_rel" \
       && grep -qF '<li>対象テーブル: users</li>' "$outside_rel" \
       && grep -qF '<li>後続ジョブ: job-cleanup</li>' "$outside_rel"; then
      echo "  [PASS] ケースe(有): 拡張フィールドありで関連エンティティセクション(日本語ラベル+値一覧)が出力される"
    else
      echo "  [FAIL] ケースe(有): 関連エンティティセクションまたはラベル+値一覧が出力されていない" >&2
      rc=1
    fi
    local embedded_rel="$tmp/embedded-rel.json"
    local expected_rel="$tmp/expected-rel.json"
    local _gt_diff_rel
    extract_page_data_json "$out_rel_html" | jq -c -S . > "$embedded_rel" 2>/dev/null || true
    jq -c -S . "$data_rel" > "$expected_rel"
    if _gt_diff_rel="$(diff -u "$expected_rel" "$embedded_rel" 2>&1)"; then
      echo "  [PASS] ケースe(有): 拡張フィールド込みの埋め込みJSONが原本と完全一致"
    else
      echo "  [FAIL] ケースe(有): 埋め込みJSONが原本と不一致" >&2
      printf '%s\n' "$_gt_diff_rel" | sed 's/^/    /' >&2
      rc=1
    fi
  else
    echo "  [FAIL] ケースe(有): 生成コマンド自体が失敗した" >&2
    rc=1
  fi

  local out_a_html="$outdir_a/技術スタック.html"
  if [ -f "$out_a_html" ] \
     && ! grep -qF '関連エンティティ' "$out_a_html" \
     && ! grep -qF 'RELATED_ENTITIES' "$out_a_html"; then
    echo "  [PASS] ケースe(無): 拡張フィールド無しの出力に「関連エンティティ」・未置換マーカーが含まれない(後方互換)"
  else
    echo "  [FAIL] ケースe(無): 拡張フィールド無しの出力に「関連エンティティ」または未置換マーカーが残存" >&2
    rc=1
  fi

  # --- ケースi: --sites/--site-key 指定でプロジェクト切替(pt-sites-data)が描画される(改善課題1-44) ---
  local sites_json="$tmp/sites.json"
  jq -n '{
    specVersion: 1,
    sites: [
      {key: "site-a", label: "サイトA", root: "site-a"},
      {key: "site-b", label: "サイトB", root: "site-b"}
    ]
  }' > "$sites_json"

  local outdir_sites="$tmp/out-sites"
  local out_sites_html="$outdir_sites/技術スタック.html"
  local sites_build_out sites_build_rc
  if [ -n "${SELF_TEST_FORCE_SITE_BUILD_FAILURE:-}" ]; then
    sites_build_out="$SELF_TEST_FORCE_SITE_BUILD_FAILURE"
    sites_build_rc=97
  else
    sites_build_out="$(bash "$script_path" "$data_a" "$outdir_sites" --page techstack --sites "$sites_json" --site-key site-a 2>&1)"
    sites_build_rc=$?
  fi
  if [ "$sites_build_rc" -eq 0 ] && [ -f "$out_sites_html" ]; then
    local sites_data="$tmp/sites-data.json"
    python3 -c '
import re, sys
html = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"<script type=\"application/json\" id=\"pt-sites-data\">([\s\S]*?)</script>", html)
sys.stdout.write(m.group(1) if m else "")
' "$out_sites_html" > "$sites_data" 2>/dev/null || true
    local sites_jq_out
    if sites_jq_out="$(jq -e 'length == 2 and ([.[] | select(.current == true) | .key] == ["site-a"])' "$sites_data" 2>&1)"; then
      echo "  [PASS] ケースi: --sites/--site-key指定でpt-sites-dataに2件のサイトが描画され、現在のサイトが正しくマークされる"
    else
      echo "  [FAIL] ケースi: pt-sites-dataがサイト2件を含まない、または現在のサイトのマークが不正($(cat "$sites_data" 2>/dev/null))" >&2
      printf '%s\n' "$sites_jq_out" | sed 's/^/    /' >&2
      rc=1
    fi
  else
    echo "  [FAIL] ケースi: 生成コマンド自体が失敗した、または出力ファイルが生成されなかった" >&2
    printf '%s\n' "$sites_build_out" | sed 's/^/    /' >&2
    rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  rm -rf -- "$tmp"
  return "$rc"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

DATA="${1:?Usage: build-detail-page.sh <page-data.json> <output-dir> --page <kind> [--portal-dir <path>] [--generated-at <iso8601>] [--project-name <name>] [--catalog <file>]}"
OUTPUT_DIR="${2:?Usage: build-detail-page.sh <page-data.json> <output-dir> --page <kind> [--portal-dir <path>] [--generated-at <iso8601>] [--project-name <name>] [--catalog <file>]}"
shift 2 || true

PAGE=""
PORTAL_DIR_ARG=""
GENERATED_AT_ARG=""
PROJECT_NAME_ARG=""
CATALOG_FILE=""
SITES_FILE_ARG=""
SITE_KEY_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --page)
      PAGE="${2:-}"
      shift 2
      ;;
    --portal-dir)
      PORTAL_DIR_ARG="${2:-}"
      shift 2
      ;;
    --generated-at)
      GENERATED_AT_ARG="${2:-}"
      shift 2
      ;;
    --project-name)
      PROJECT_NAME_ARG="${2:-}"
      shift 2
      ;;
    --catalog)
      # ポータルカタログの JSON。省略時はリポジトリ既定を使う
      CATALOG_FILE="${2:-}"
      shift 2
      ;;
    --sites)
      # サイト一覧(sites.json)。省略時はプロジェクト切替を描画しない(build-portal.shと同じ挙動)
      SITES_FILE_ARG="${2:-}"
      shift 2
      ;;
    --site-key)
      # サイト一覧内で現在のサイトを示すkey
      SITE_KEY_ARG="${2:-}"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$PAGE" ] || [ -z "$(get_page_template "$PAGE")" ]; then
  echo "ERROR: --page must be one of: glossary techstack transition er env entity-state release-notes design-system component-inventory icon-catalog" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found in PATH" >&2
  exit 1
fi

if [ ! -f "$DATA" ]; then
  echo "ERROR: page-data not found: $DATA" >&2
  exit 1
fi
if [ -n "$GENERATED_AT_ARG" ] \
  && [ "$(jq -r '.generatedAt // ""' "$DATA")" != "$GENERATED_AT_ARG" ]; then
  echo "ERROR: page-data generatedAt does not match --generated-at" >&2
  exit 1
fi

if ! jq empty "$DATA" >/dev/null 2>&1; then
  echo "ERROR: invalid JSON: $DATA" >&2
  exit 1
fi

DATA_PAGE_KIND="$(jq -r '.pageKind // ""' "$DATA")"
if [ "$DATA_PAGE_KIND" != "$PAGE" ]; then
  echo "ERROR: page-dataのpageKind(${DATA_PAGE_KIND})と--page(${PAGE})が不一致です" >&2
  exit 1
fi

if ! "$SCRIPT_DIR/validate-page-data.sh" "$DATA"; then
  echo "ERROR: page-dataがvalidate-page-data.shの検証に失敗しました" >&2
  exit 1
fi

TEMPLATE_FILE="$(get_page_template "$PAGE")"
TEMPLATE="$SCRIPT_DIR/../../../delivery-payload/templates/detail-pages/$TEMPLATE_FILE"
TOKENS_CSS_FILE="$SCRIPT_DIR/../../../delivery-payload/templates/tokens.css"
if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: template not found: $TEMPLATE" >&2
  exit 1
fi

OUTPUT_FILENAME="$(get_page_filename "$PAGE")"
mkdir -p "$OUTPUT_DIR"
OUTPUT_PATH="$OUTPUT_DIR/$OUTPUT_FILENAME"

html_escape() {
  printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

# render_template — 共通関数を source（generation-engine/scripts/render-template.sh）
source "$(cd "$(dirname "$0")/.." && pwd)/render-template.sh"
if [ -f "$SCRIPT_DIR/../shell-injection.sh" ]; then
  . "$SCRIPT_DIR/../shell-injection.sh"
fi

# --project-name オプションを優先し、未指定ならpage-data.jsonのprojectNameへフォールバックする
PROJECT_NAME="${PROJECT_NAME_ARG:-$(jq -r '.projectName // ""' "$DATA")}"
TITLE="$(jq -r '.title // ""' "$DATA")"
DESCRIPTION="$(jq -r '.description // ""' "$DATA")"
GENERATED_AT="$(jq -r '.generatedAt // ""' "$DATA")"
# application/json script要素内でもHTML parserはscript終端を解釈する。
# JSONの意味を変えずに「<」とliteral U+2028/U+2029をUnicode escapeし、
# </script>注入とJavaScript行区切り文字の混入を防ぐ。入力page-dataは変更しない。
PAGE_DATA_JSON="$(python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as source:
    value = json.load(source)
text = json.dumps(value, ensure_ascii=False, indent=2)
sys.stdout.write(text.replace("<", "\\u003c").replace("\u2028", "\\u2028").replace("\u2029", "\\u2029"))
' "$DATA")"

# --- 関連エンティティ(スキーマ拡張フィールド)セクションの生成 ---
# page-data内の全オブジェクトを走査し、拡張フィールド(非空配列)を1つ以上持つ要素ごとに
# 「フィールドの日本語ラベル + 値の一覧」を列挙する。該当要素が0件なら空文字(後方互換)。
# 値・名称は jq の @html でエスケープする。
RELATED_ENTITIES_HTML="$(jq -r '
  [["relatedApis","関連API"],
   ["callers","呼び出し元画面"],
   ["targetTables","対象テーブル"],
   ["foreignKeys","FK参照先テーブル"],
   ["downstreamJobs","後続ジョブ"]] as $fields
  | [.. | objects
      | . as $o
      | [$fields[] | select((($o[.[0]] | type) == "array") and (($o[.[0]] | length) > 0))] as $present
      | select(($present | length) > 0)
      | {name: ($o.label // $o.unitKey // $o.key // $o.term // $o.item // $o.name // "(名称不明)"),
         present: $present, obj: $o}
    ] as $units
  | if ($units | length) == 0 then "" else
      "<section class=\"related-entities\">\n      <div class=\"sec-label\">関連エンティティ</div>\n"
      + ([$units[]
          | .obj as $o
          | "      <div class=\"related-entity\">\n        <div class=\"related-entity-name\"><strong>\(.name | tostring | @html)</strong></div>\n        <ul>\n"
            + ([.present[] | "          <li>\(.[1]): \([$o[.[0]][] | tostring] | join("、") | @html)</li>\n"] | join(""))
            + "        </ul>\n      </div>\n"
         ] | join(""))
      + "    </section>\n    "
    end
' "$DATA")"

# --- 実在しない判定の項目(absentRows[]。techstackのみ。1-132)セクションの生成 ---
# 調査書が「実在しない（理由: …）」と判定した項目も、根拠(sourceRef)を保持したまま
# 別表として静的にレンダリングする。absentRows[]が無い/空配列なら空文字(後方互換)。
ABSENT_ROWS_HTML="$(jq -r '
  (.absentRows // []) as $rows
  | if ($rows | length) == 0 then "" else
      "<section class=\"absent-rows-section\">\n      <div class=\"sec-label\">実在しない判定（根拠付き）</div>\n      <div class=\"pt-callout pt-callout--warning\">\n        <span class=\"material-symbols-outlined pt-callout__icon\" aria-hidden=\"true\">warning</span>\n        調査書が「実在しない」と判定した項目です。根拠パスとあわせて記録しています。\n      </div>\n      <table class=\"absent-table\">\n        <thead><tr><th>項目</th><th>値</th><th>出所</th></tr></thead>\n        <tbody>\n"
      + ([$rows[] | "          <tr><td>\(.item // "" | tostring | @html)</td><td>\(.value // "" | tostring | @html)</td><td><code>\(.sourceRef // "" | tostring | @html)</code></td></tr>\n"] | join(""))
      + "        </tbody>\n      </table>\n    </section>\n    "
    end
' "$DATA")"

# --- ERエンティティ俯瞰(relations[]が0件の場合のみ。1-151)セクションの生成 ---
# 外部キーが0件で関連図(クラスタ探索Canvas)を描けない場合、entities[]全件をサーバー側で
# 静的にレンダリングした一覧へ切り替える。pageKind!="er"、またはrelations[]が1件以上なら
# 空文字(後方互換)。
ER_FLAT_LIST_HTML="$(jq -r '
  if (.pageKind // "") != "er" then "" else
    (.entities // []) as $entities
    | (.relations // []) as $relations
    | if ($relations | length) > 0 then "" else
        "<section class=\"er-flat-list\">\n      <div class=\"pt-callout pt-callout--warning\">\n        <span class=\"material-symbols-outlined pt-callout__icon\" aria-hidden=\"true\">warning</span>\n        外部キーが宣言されていません（0件）。関連（リレーション）は未記載です。\n      </div>\n      <div class=\"sec-label\">エンティティ一覧（\($entities | length)件）</div>\n      <table class=\"er-flat-table\">\n        <thead><tr><th>テーブル</th><th>カラム数</th></tr></thead>\n        <tbody>\n"
        + ([$entities[] | "          <tr><td>\(.label // .key // "" | tostring | @html)</td><td>\((.columns // []) | length)</td></tr>\n"] | join(""))
        + "        </tbody>\n      </table>\n    </section>\n    "
      end
  end
' "$DATA")"

# --- テンプレートへの注入(単一パス方式。render_template()参照) ---
# page-dataのJSONはテンプレート内で物理的に最後に出現するため、単一パスの
# document-order走査により自動的に最後に処理される(JSON内容に他マーカー文字列が
# 偶然含まれた場合の誤爆を避けるため)。
# --- ポータルへの相対パス算出(--portal-dir 未指定時はrelease-notesだけ1階層上固定、
#     他はOUTPUT_DIRの実際の構造からdefault_back_link_depthが深さを判定する。改善課題1-212) ---
if [ -n "$PORTAL_DIR_ARG" ]; then
  back_link="$(python3 -c "import os; print(os.path.relpath('$PORTAL_DIR_ARG', '$OUTPUT_DIR'))" 2>/dev/null || echo ".")/index.html"
else
  case "$PAGE" in
    release-notes) back_link="../index.html" ;;
    *) back_link="$(default_back_link_depth "$OUTPUT_DIR")" ;;
  esac
fi

render_args=(
  "{{PROJECT_NAME}}" "$(html_escape "$PROJECT_NAME")"
  "{{TITLE}}" "$(html_escape "$TITLE")"
  "{{DESCRIPTION}}" "$(html_escape "$DESCRIPTION")"
  "{{GENERATED_AT}}" "$(html_escape "$GENERATED_AT")"
  "{{COMMIT_SHORT}}" ""
  "{{BACK_LINK}}" "$back_link"
  "<!--RELATED_ENTITIES-->" "$RELATED_ENTITIES_HTML"
  "<!--ABSENT_ROWS-->" "$ABSENT_ROWS_HTML"
  "<!--ER_FLAT_LIST-->" "$ER_FLAT_LIST_HTML"
  "{{PAGE_DATA_JSON}}" "$PAGE_DATA_JSON"
)
# トークンCSS注入（tokens.css が存在する場合のみ）
if [ -f "$TOKENS_CSS_FILE" ]; then
  render_args+=("/* TOKENS_CSS */" "$(cat "$TOKENS_CSS_FILE")")
fi
# 共通シェル注入（partials が存在する場合のみ）
catalog_path="${CATALOG_FILE:-$SCRIPT_DIR/../../../delivery-payload/references/portal-catalog.json}"
if type shell_injection_args >/dev/null 2>&1; then
  shell_injection_args "$SCRIPT_DIR/../../../delivery-payload/templates" "$catalog_path" "$back_link" "$PROJECT_NAME" "$GENERATED_AT" "" "generation-engine/scripts/detail-pages/build-detail-page.sh" "$(get_page_category "$PAGE")" "$SITES_FILE_ARG" "$SITE_KEY_ARG" "$OUTPUT_DIR"
  if [ ${#SHELL_RENDER_ARGS[@]} -gt 0 ]; then
    render_args+=("${SHELL_RENDER_ARGS[@]}")
  fi
fi
out="$(render_template "$(cat "$TEMPLATE")" "${render_args[@]}")"

TMP_OUT="$(mktemp "$OUTPUT_DIR/.build-detail-page.XXXXXX")"
printf '%s\n' "$out" > "$TMP_OUT"
mv "$TMP_OUT" "$OUTPUT_PATH"

echo "OK: wrote $OUTPUT_PATH" >&2
