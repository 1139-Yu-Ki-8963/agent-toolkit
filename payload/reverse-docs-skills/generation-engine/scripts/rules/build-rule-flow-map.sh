#!/usr/bin/env bash
set -euo pipefail

# build-rule-flow-map.sh — 「規約とフローの対応」ページを rule-taxonomy.json から生成する
#
# 目的:
#   納品先ポータルへ「規約とフローの対応」ページを1枚生成する。読み手は納品先で動く
#   AIエージェントと人間のエンジニア。「いま基本設計をしている。どの規約を見ればよいか」
#   「この規約はいつ効くのか」を引ける形にする。
#
#   ページは2つの見方を1枚に持つ。
#     (1) フェーズから引く見方: 全フェーズ / 1-要件すり合わせ / 2-基本設計 /
#         3-詳細設計 / 4-実装プラン策定 / 5-実装と動作確認 / フロー外 の7区分ごとに、
#         そこで読む規約(表示名・要約)を並べる。
#     (2) 規約から引く見方: 27件を親カテゴリごとにまとめ、各件の表示名・scope・paths・
#         効くフェーズを表で示す。
#   どちらも delivery-payload/references/rule-taxonomy.json から jq で導出する。件数・行を
#   固定値でハードコードしない(--self-test のケース5が、入力データを1件増やした
#   一時コピーで再生成し、件数が追従することを検証する)。
#
# 使い方:
#   build-rule-flow-map.sh <rule-taxonomy.json> <output-html-path>
#     [--project-name <name>] [--generated-at <ISO-8601>] [--catalog <portal-catalog.json>]
#   build-rule-flow-map.sh --self-test
#
# 出力: 単一ファイル自己完結のHTML。共通シェル(サイドバー・フッター・方眼紙背景・
#   全画面フィットレイアウト)を delivery-payload/templates/partials 経由で注入し、
#   delivery-payload/templates/tokens.css の正本全文も注入する
#   (.claude/rules/scoped/portal/page-conventions/rule.md 準拠)。
#   表の内容はテンプレートへ直書きせず、すべて rule-taxonomy.json から本スクリプトが
#   都度組み立てる。
#
# 終了コード: 0 = 生成完了。1 = 引数不正・入力不正・self-test 失敗。
#
# 保守責任者・廃棄条件:
#   .claude/rules/scoped/portal/page-conventions/rule.md の「## 設計判断」
#   「### build-rule-flow-map.sh」を参照。
#
# macOS bash 3.2 互換(連想配列・mapfileは不使用)。

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required but not installed" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/../../../delivery-payload/templates"
TOKENS_CSS_FILE="$TEMPLATES_DIR/tokens.css"
DEFAULT_CATALOG="$SCRIPT_DIR/../../../delivery-payload/references/portal-catalog.json"

# shellcheck source=../render-template.sh
. "$SCRIPT_DIR/../render-template.sh"
# shellcheck source=../shell-injection.sh
. "$SCRIPT_DIR/../shell-injection.sh"

# フェーズ区分の固定順序(rule-taxonomy.json の各childの phases 配列が取りうる値の全域)。
# ここは「規約が効くタイミングの語彙」という構造の宣言であり、件数(集計値)ではない
# (matrix系ページが列定義を宣言するのと同じ扱い)。
PHASE_ORDER=("全フェーズ" "1-要件すり合わせ" "2-基本設計" "3-詳細設計" "4-実装プラン策定" "5-実装と動作確認" "フロー外")

# --- rule-taxonomy.json の phases 値が PHASE_ORDER の語彙に収まっているかを検査する ---
validate_phase_vocabulary() {
  local taxonomy="$1"
  local known_json
  known_json="$(printf '%s\n' "${PHASE_ORDER[@]}" | jq -R . | jq -s .)"
  local unknown
  unknown="$(jq -r --argjson known "$known_json" '
    [.parents[].children[].phases[]] | unique
    | map(select(. as $p | ($known | index($p)) == null)) | .[]
  ' "$taxonomy")"
  if [ -n "$unknown" ]; then
    echo "ERROR: rule-taxonomy.json に未知のphases値がある(PHASE_ORDERへの追記が必要):" >&2
    printf '%s\n' "$unknown" >&2
    return 1
  fi
  return 0
}

# --- フェーズから引くビューのHTMLを組み立てる ---
build_phase_view() {
  local taxonomy="$1"
  local phase count rows html=""
  for phase in "${PHASE_ORDER[@]}"; do
    count="$(jq --arg p "$phase" '[.parents[].children[] | select(.phases | index($p))] | length' "$taxonomy")"
    html="${html}
<div class=\"rfm-block\">
<h3>$(printf '%s' "$phase" | jq -Rr '@html')（${count}件）</h3>"
    if [ "$count" -eq 0 ]; then
      html="${html}
<p class=\"rfm-empty\">該当する規約なし</p>"
    else
      rows="$(jq -r --arg p "$phase" '
        [.parents[].children[] | select(.phases | index($p))]
        | map("<tr><td>\(.title|@html)</td><td>\(.summary|@html)</td></tr>")
        | join("\n")
      ' "$taxonomy")"
      html="${html}
<div class=\"pt-tablewrap\">
<table class=\"rfm\">
<thead><tr><th>規約名</th><th>要約</th></tr></thead>
<tbody>
${rows}
</tbody>
</table>
</div>"
    fi
    html="${html}
</div>"
  done
  printf '%s' "$html"
}

# --- 対象側リポジトリの実在する規約フォルダ件数を数える(3.4/判定10・11) ---
# target_root が空文字の場合はtaxonomyの定義件数をそのまま返す(後方互換の既定値)。
# build_rule_view はコマンド置換(サブシェル)経由で呼ばれるため、内部で
# グローバル変数へ件数を書いても呼び出し元(run_build)には伝わらない。
# そのため件数の算出は本関数へ切り出し、run_build が個別に呼ぶ。
count_actual_rules() {
  local taxonomy="$1" target_root="$2"
  if [ -z "$target_root" ]; then
    jq '[.parents[].children[]] | length' "$taxonomy"
    return 0
  fi
  local total=0 pkey ckey
  while IFS= read -r pkey; do
    [ -n "$pkey" ] || continue
    while IFS= read -r ckey; do
      [ -n "$ckey" ] || continue
      [ -f "${target_root}/docs/rules/${pkey}/${ckey}/rule.md" ] && total=$((total + 1))
    done <<CHILDEOF
$(jq -r --arg k "$pkey" '.parents[] | select(.key==$k) | .children[].key' "$taxonomy")
CHILDEOF
  done <<PARENTEOF
$(jq -r '.parents[].key' "$taxonomy")
PARENTEOF
  printf '%s' "$total"
}

# --- 規約から引くビューのHTMLを組み立てる(親カテゴリごと) ---
# $2（省略可・3.4/判定10・11）: 対象側リポジトリのルート。指定時は
# <target_root>/docs/rules/<親key>/<子key>/rule.md の実在を情報源に含め、
# 実在しない子カテゴリは索引へ載せない（決めていないこと3の選択:
# 実体が無い規約は載せない側を採る）。件数（見出し・{{RULE_COUNT}}）は
# taxonomyの定義件数ではなく実在件数を報告する（判定10）。
# 差の報告（判定11）は run_build 側が count_actual_rules の結果を使って報告する。
build_rule_view() {
  local taxonomy="$1" target_root="${2:-}"
  local pkey ptitle count rows html=""
  while IFS= read -r pkey; do
    [ -n "$pkey" ] || continue
    ptitle="$(jq -r --arg k "$pkey" '.parents[] | select(.key==$k) | .title' "$taxonomy")"

    if [ -z "$target_root" ]; then
      # target_root未指定時は従来どおりtaxonomyの定義をそのまま全件出す（後方互換）。
      count="$(jq -r --arg k "$pkey" '.parents[] | select(.key==$k) | .children | length' "$taxonomy")"
      rows="$(jq -r --arg k "$pkey" '
        .parents[] | select(.key==$k) | .children
        | map(
            "<tr><td>\(.title|@html)</td>" +
            "<td>\(.scope|@html)</td>" +
            "<td>\(((.paths // []) | if length == 0 then "—" else join("、") end)|@html)</td>" +
            "<td>\(((.phases // []) | join("・"))|@html)</td></tr>"
          )
        | join("\n")
      ' "$taxonomy")"
    else
      # target_root指定時は各子カテゴリの実在（<target_root>/docs/rules/<pkey>/<ckey>/rule.md）を
      # 走査し、実在するものだけを行として組み立てる。件数は実在件数（judged_count）にする。
      local child_lines cline ckey ctitle cscope cpaths cphases judged_count=0
      rows=""
      child_lines="$(jq -c --arg k "$pkey" '.parents[] | select(.key==$k) | .children[]' "$taxonomy")"
      while IFS= read -r cline; do
        [ -n "$cline" ] || continue
        ckey="$(printf '%s' "$cline" | jq -r '.key')"
        [ -f "${target_root}/docs/rules/${pkey}/${ckey}/rule.md" ] || continue
        judged_count=$((judged_count + 1))
        ctitle="$(printf '%s' "$cline" | jq -r '.title|@html')"
        cscope="$(printf '%s' "$cline" | jq -r '.scope|@html')"
        cpaths="$(printf '%s' "$cline" | jq -r '((.paths // []) | if length == 0 then "—" else join("、") end)|@html')"
        cphases="$(printf '%s' "$cline" | jq -r '((.phases // []) | join("・"))|@html')"
        rows="${rows}
<tr><td>${ctitle}</td><td>${cscope}</td><td>${cpaths}</td><td>${cphases}</td></tr>"
      done <<CHILDEOF
$child_lines
CHILDEOF
      count="$judged_count"
    fi

    html="${html}
<div class=\"rfm-block\">
<h3>$(printf '%s' "$ptitle" | jq -Rr '@html')（${count}件）</h3>"
    if [ "$count" -eq 0 ]; then
      html="${html}
<p class=\"rfm-empty\">該当する規約なし</p>"
    else
      html="${html}
<div class=\"pt-tablewrap\">
<table class=\"rfm\">
<thead><tr><th>規約名</th><th>適用範囲</th><th>対象ファイル</th><th>効くフェーズ</th></tr></thead>
<tbody>
${rows}
</tbody>
</table>
</div>"
    fi
    html="${html}
</div>"
  done <<EOF
$(jq -r '.parents[].key' "$taxonomy")
EOF
  printf '%s' "$html"
}

PAGE_TEMPLATE='<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>規約とフローの対応</title>
<style>
/* TOKENS_CSS */
/* SHELL_CSS */

* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }

.rfm-lead { flex: none; margin: 16px 0 20px; font-size: 0.85rem; color: var(--sub); max-width: 72ch; }

.table-area { flex: 1; min-height: 0; overflow-y: auto; display: flex; flex-direction: column; gap: 28px; padding-bottom: 24px; }

.rfm-view { margin: 0; }
.rfm-view > h2 { font-size: 1.05rem; margin: 0 0 14px; padding-bottom: 8px; border-bottom: 1.5px solid var(--line2); }

.rfm-block { margin: 0 0 18px; }
.rfm-block h3 { font-size: 0.92rem; margin: 0 0 8px; color: var(--sub); }

.rfm-empty { margin: 0; padding: 8px 0; font-size: 0.85rem; color: var(--muted); }

table.rfm { width: 100%; table-layout: fixed; border-collapse: separate; border-spacing: 0; font-size: 0.85rem; }
table.rfm th, table.rfm td { border-top: 1px solid var(--line); padding: 7px 10px; text-align: left; vertical-align: top; word-break: break-word; }
table.rfm thead th { font-size: 11px; font-weight: 600; color: var(--muted); }
</style>
</head>
<body>
<div class="pt">
  <div class="pt-grid"></div>
  <div class="pt-row">
    <!--SHELL_SIDEBAR-->
    <main class="pt-main is-fixed">
      <div class="pt-head">
        <div class="pt-crumb"><a href="{{BACK_LINK}}">TOP</a> ／ {{ACTIVE_CATEGORY_LABEL}} ／ <span class="pt-crumb-current">規約とフローの対応</span></div>
        <div class="pt-title-row">
          <h1 class="pt-title">規約とフローの対応</h1>
          <span class="pt-title-sub">更新 {{GENERATED_AT}} ／ 規約 {{RULE_COUNT}} 件</span>
        </div>
      </div>

      <p class="rfm-lead">いま取り組んでいるフェーズから読むべき規約を引く一覧と、27件の規約それぞれの適用範囲・対象ファイル・効くフェーズを引く一覧の2通りを、同じ rule-taxonomy.json から生成する。</p>

      <div class="table-area">
        <section class="rfm-view">
          <h2>フェーズから引く</h2>
          {{PHASE_VIEW_HTML}}
        </section>
        <section class="rfm-view">
          <h2>規約から引く</h2>
          {{RULE_VIEW_HTML}}
        </section>
      </div>
    </main>
  </div>
  <!--SHELL_FOOTER-->
</div>

<script type="application/json" id="rule-taxonomy-data">
{{RULE_TAXONOMY_JSON}}
</script>
</body>
</html>
'

USAGE="Usage: build-rule-flow-map.sh <rule-taxonomy.json> <output-html-path> [--project-name <name>] [--generated-at <iso8601>] [--catalog <file>] [--target-root <dir>]
       build-rule-flow-map.sh --self-test"

run_build() {
  local taxonomy="$1" output="$2"
  shift 2

  local project_name="" generated_at="" catalog="" target_root=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --project-name) project_name="${2:-}"; shift 2 ;;
      --generated-at) generated_at="${2:-}"; shift 2 ;;
      --catalog) catalog="${2:-}"; shift 2 ;;
      --target-root) target_root="${2:-}"; shift 2 ;;
      *) echo "ERROR: unknown argument: $1" >&2; echo "$USAGE" >&2; return 1 ;;
    esac
  done

  if [ ! -f "$taxonomy" ]; then
    echo "ERROR: rule-taxonomy.json not found: $taxonomy" >&2
    return 1
  fi
  if [ ! -f "$TOKENS_CSS_FILE" ]; then
    echo "ERROR: tokens.css not found: $TOKENS_CSS_FILE" >&2
    return 1
  fi
  if ! jq -e '(type == "object") and (.parents | type == "array")' "$taxonomy" >/dev/null 2>&1; then
    echo "ERROR: rule-taxonomy.json は .parents 配列を持つオブジェクトである必要がある: $taxonomy" >&2
    return 1
  fi

  validate_phase_vocabulary "$taxonomy" || return 1

  [ -z "$generated_at" ] && generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  catalog="${catalog:-$DEFAULT_CATALOG}"

  local rule_count phase_view_html rule_view_html taxonomy_json
  phase_view_html="$(build_phase_view "$taxonomy")"
  rule_view_html="$(build_rule_view "$taxonomy" "$target_root")"
  taxonomy_json="$(cat "$taxonomy")"

  # 判定10: {{RULE_COUNT}}（ページ見出しの件数）は、target_root指定時は
  # 実際に実在する規約フォルダの件数を使う。未指定時はtaxonomyの定義件数のまま
  # （後方互換。count_actual_rulesがtarget_root空文字の場合に定義件数を返す）。
  local taxonomy_count actual_count
  taxonomy_count="$(jq '[.parents[].children[]] | length' "$taxonomy")"
  actual_count="$(count_actual_rules "$taxonomy" "$target_root")"
  rule_count="$actual_count"

  # 判定11: 分類の定義件数と対象側の実体件数が食い違う場合、生成のときに件数の差を
  # 標準出力へ報告する（buildを失敗させない。advisory）。target_root未指定時は
  # 定義件数=実体件数として扱われるため差は出ない。
  if [ -n "$target_root" ] && [ "$taxonomy_count" -ne "$actual_count" ]; then
    echo "件数差異: 分類の定義 ${taxonomy_count} 件 / 対象側の実体 ${actual_count} 件（差 $((taxonomy_count - actual_count)) 件）"
  fi

  mkdir -p "$(dirname "$output")"

  local render_args=(
    "{{GENERATED_AT}}" "$generated_at"
    "{{RULE_COUNT}}" "$rule_count"
  )
  render_args+=("/* TOKENS_CSS */" "$(cat "$TOKENS_CSS_FILE")")

  if type shell_injection_args >/dev/null 2>&1; then
    shell_injection_args "$TEMPLATES_DIR" "$catalog" "../index.html" "$project_name" "$generated_at" "" \
      "build-rule-flow-map" "project"
    if [ ${#SHELL_RENDER_ARGS[@]} -gt 0 ]; then
      render_args+=("${SHELL_RENDER_ARGS[@]}")
    fi
  fi

  # BACK_LINK はサイドバー注入と同じ値を使う(project カテゴリ配下・project-portal/foundation 直下のページ)
  render_args+=("{{BACK_LINK}}" "../index.html")
  # PHASE_VIEW_HTML / RULE_VIEW_HTML / RULE_TAXONOMY_JSON はテンプレート内で最後に
  # 出現するため、単一パス走査により他マーカーとの誤爆を避けて最後に処理される
  render_args+=("{{PHASE_VIEW_HTML}}" "$phase_view_html")
  render_args+=("{{RULE_VIEW_HTML}}" "$rule_view_html")
  render_args+=("{{RULE_TAXONOMY_JSON}}" "$taxonomy_json")

  local out
  out="$(render_template "$PAGE_TEMPLATE" "${render_args[@]}")"
  printf '%s\n' "$out" > "$output"

  echo "OK: wrote $output" >&2
  return 0
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

self_test() {
  local script_path="$0"
  local tmp rc=0
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/build-rule-flow-map-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' RETURN

  local taxonomy="$SCRIPT_DIR/../../../delivery-payload/references/rule-taxonomy.json"
  local out="$tmp/out.html"
  local build_log="$tmp/build.log"

  # ケース1: 生成コマンド自体が成功する
  if bash "$script_path" "$taxonomy" "$out" --project-name "テストプロジェクト" --generated-at "2026-01-01T00:00:00Z" >"$build_log" 2>&1; then
    echo "  [PASS] ケース1: 生成コマンドが成功する"
  else
    echo "  [FAIL] ケース1: 生成コマンドが失敗した" >&2
    sed 's/^/    /' "$build_log" >&2
    rc=1
  fi

  # ケース2: 出力HTMLが実在する
  if [ -f "$out" ]; then
    echo "  [PASS] ケース2: 出力HTMLが実在する"
  else
    echo "  [FAIL] ケース2: 出力HTMLが実在しない" >&2
    rc=1
    echo "self-test FAIL(ケース2で打ち切り)" >&2
    return 1
  fi

  # ケース3: rule-taxonomy.json の全件(規約名)が出力に現れる
  local expected_count missing=0 title
  expected_count="$(jq '[.parents[].children[]] | length' "$taxonomy")"
  while IFS= read -r title; do
    [ -n "$title" ] || continue
    grep -qF "$title" "$out" || { missing=$((missing + 1)); echo "    欠落: $title" >&2; }
  done < <(jq -r '.parents[].children[].title' "$taxonomy")
  if [ "$missing" -eq 0 ]; then
    echo "  [PASS] ケース3: rule-taxonomy.json 全${expected_count}件の規約名が出力に現れる"
  else
    echo "  [FAIL] ケース3: ${missing}件の規約名が出力に欠落している" >&2
    rc=1
  fi

  # ケース4: test-portal-conventions.sh が不合格0件で通る
  local conv_script conv_log conv_fail
  conv_script="$SCRIPT_DIR/../tests/test-portal-conventions.sh"
  conv_log="$tmp/conventions.log"
  bash "$conv_script" "$out" >"$conv_log" 2>&1 || true
  conv_fail="$(grep -c '^  FAIL:' "$conv_log" || true)"
  if [ "$conv_fail" -eq 0 ]; then
    echo "  [PASS] ケース4: test-portal-conventions.sh が不合格0件で通る"
  else
    echo "  [FAIL] ケース4: test-portal-conventions.sh が${conv_fail}件不合格" >&2
    grep '^  FAIL:' "$conv_log" | sed 's/^/    /' >&2
    rc=1
  fi

  # ケース5: 件数が固定値でなく、入力の増減に追従する
  # (rule-taxonomy.json を1件増やした一時コピーで再生成し、規約件数バッジと本文の両方が
  # 追従することを確認する。ハードコードなら27件のまま変化しないはず)
  local taxonomy_plus out_plus build_plus_log expected_plus actual_plus
  taxonomy_plus="$tmp/rule-taxonomy-plus1.json"
  jq '.parents[0].children += [{
        "key": "self-test-extra",
        "title": "自己テスト追加規約",
        "summary": "self-test用に一時追加した規約。",
        "toolDefined": true,
        "scope": "always",
        "paths": [],
        "phases": ["全フェーズ"]
      }]' "$taxonomy" > "$taxonomy_plus"
  out_plus="$tmp/out-plus1.html"
  build_plus_log="$tmp/build-plus1.log"
  bash "$script_path" "$taxonomy_plus" "$out_plus" --project-name "テストプロジェクト" --generated-at "2026-01-01T00:00:00Z" >"$build_plus_log" 2>&1 || true
  expected_plus="$((expected_count + 1))"
  actual_plus="$(grep -oE '規約 [0-9]+ 件' "$out_plus" 2>/dev/null | head -1 | grep -oE '[0-9]+' || true)"
  if [ "$actual_plus" = "$expected_plus" ] && grep -qF "自己テスト追加規約" "$out_plus" 2>/dev/null; then
    echo "  [PASS] ケース5: 件数が固定値でなく入力データの増減(${expected_count}→${expected_plus})に追従する"
  else
    echo "  [FAIL] ケース5: 件数が入力データの増減に追従しない(期待=${expected_plus} 実際=${actual_plus:-なし})" >&2
    rc=1
  fi

  # ケース6: 未知のphases値を検出してERRORで停止する
  local taxonomy_bad out_bad bad_rc
  taxonomy_bad="$tmp/rule-taxonomy-bad-phase.json"
  jq '.parents[0].children[0].phases = ["存在しないフェーズ"]' "$taxonomy" > "$taxonomy_bad"
  out_bad="$tmp/out-bad.html"
  bad_rc=0
  bash "$script_path" "$taxonomy_bad" "$out_bad" >/dev/null 2>&1 || bad_rc=$?
  if [ "$bad_rc" -ne 0 ] && [ ! -f "$out_bad" ]; then
    echo "  [PASS] ケース6: 未知のphases値を検出しエラー終了する"
  else
    echo "  [FAIL] ケース6: 未知のphases値を検出できない(rc=${bad_rc})" >&2
    rc=1
  fi

  # ケース7（判定10・3.4）: --target-root 指定時、載る件数が対象側の実体件数と一致する
  # （分類の定義より少ない件数の規約フォルダを持つ疑似入力で検証する）。
  local target_root7 out7 build_log7 actual7 first_pkey7 first_ckey7
  target_root7="$tmp/target-root-fewer"
  first_pkey7="$(jq -r '.parents[0].key' "$taxonomy")"
  first_ckey7="$(jq -r '.parents[0].children[0].key' "$taxonomy")"
  mkdir -p "${target_root7}/docs/rules/${first_pkey7}/${first_ckey7}"
  printf 'dummy\n' > "${target_root7}/docs/rules/${first_pkey7}/${first_ckey7}/rule.md"
  out7="$tmp/out-target-root.html"
  build_log7="$tmp/build-target-root.log"
  bash "$script_path" "$taxonomy" "$out7" --project-name "テストプロジェクト" --generated-at "2026-01-01T00:00:00Z" --target-root "$target_root7" >"$build_log7" 2>&1
  actual7="$(grep -oE '規約 [0-9]+ 件' "$out7" 2>/dev/null | head -1 | grep -oE '[0-9]+' || true)"
  if [ "$actual7" = "1" ]; then
    echo "  [PASS] ケース7: --target-root 指定時、載る件数(${actual7})が対象側の実体件数(1)と一致する"
  else
    echo "  [FAIL] ケース7: 載る件数が対象側の実体件数と一致しない(実際=${actual7:-なし}・期待=1)" >&2
    rc=1
  fi

  # ケース8（判定11・3.4）: 同じ疑似入力で、分類の定義件数と対象側の実体件数の差が
  # 生成のときの標準出力へ報告される。
  if grep -qE '件数差異: 分類の定義 [0-9]+ 件 / 対象側の実体 1 件' "$build_log7"; then
    echo "  [PASS] ケース8: 分類の定義と対象側の実体の件数差が生成の出力へ報告される"
  else
    echo "  [FAIL] ケース8: 件数差異の報告が出力に見つからない" >&2
    cat "$build_log7" | sed 's/^/    /' >&2
    rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi

  if [ $# -lt 2 ]; then
    echo "$USAGE" >&2
    exit 1
  fi

  local taxonomy="$1" output="$2"
  shift 2
  run_build "$taxonomy" "$output" "$@"
  exit $?
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main "$@"
fi
