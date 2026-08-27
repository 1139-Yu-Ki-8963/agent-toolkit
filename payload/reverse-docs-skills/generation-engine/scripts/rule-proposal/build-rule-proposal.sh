#!/usr/bin/env bash
# generating-rule-proposal: 規約提案HTMLの決定的生成
#
# Usage: build-rule-proposal.sh <入力JSON> <出力HTML> [--generated-at <iso8601>]
#        build-rule-proposal.sh --self-test
#
# 入力JSONスキーマ(契約。delivery-payload/references/規約定義と派生生成の設計.md 4節の
# 「判定結果JSON」とは別物。こちらは「提案の中身」を表す):
# {
#   "proposalId": "string(ケバブケース。localStorageキー・ダウンロードファイル名・
#                  buildReportJson()のproposalIdフィールドにも使う)",
#   "title": "string", "lead": "string", "isSample": true|false,
#   "meta": {"positioning": "...", "scope": "...", "verification": "..."},
#   "flowDiagram": {任意。メイン冒頭・横断的所見の直前に図1として出す処理フロー図。
#     "caption": "...(figcaptionに使う)",
#     "nodes": [{"name": "...", "desc": "..."}]
#     (省略時は図1自体を出さない)
#   },
#   "crossFindings": [{"severity": "risk|caution|reference", "title": "...", "body": "..."}],
#   "chapters": [{
#     "index": 1, "title": "...", "slug": "...", "description": "...",
#     "categories": [{
#       "key": "...(ケバブケース。data-report-row/data-key/data-cat両方に使う)",
#       "title": "...", "state": "proposal|proposal-limited|na|common",
#       "summary": "...(1文。judgable状態のときdata-summary属性へ出力する)",
#       "observations": ["...(<code>タグを含む生HTMLを許容)"],
#       "proposedRule": "...", "sources": ["path:line"],
#       "scope": "always|scoped", "paths": ["glob"],
#       "enforcement": "advisory", "checkable": true|false,
#       "checkMethod": "...", "reason": "...(state=na|commonのとき必須)",
#       "figure": {任意。evidence-listの直後・proposalの直前に出すカテゴリ内図。
#         "kind": "layers|states",
#         "caption": "...(figcaptionに使う)",
#         "items": [
#           {"label": "...", "desc": "...", "tone": "green|amber|brick|violet"}
#           (kind=layersのときlabel/desc/tone全部使用。kind=statesのときlabelのみ使用し
#            pillノードを&#8594;でつなぐ)
#         ]
#         (省略時は図自体を出さない)
#       }
#     }]
#   }]
# }
#
# generatedAt は入力JSONに含めない。--generated-at で受け、未指定時は固定値
# (GENERATED_AT_DEFAULT)を使う。同じ入力JSON + 同じ --generated-at なら
# 出力は常にbyte一致する(決定的生成)。
#
# 出力: delivery-payload/templates/rule-proposal/rule-proposal-template.html を土台に
#   単一HTMLを書き出す。外部依存は一切ない(すべてインラインCSS/JS)。
#   書き出し後、node ~/agent-home/skills/reviewing-explanatory-html/scripts/
#   verify-html-static.mjs による静的検査を実行し、不合格ならexit 1で
#   止める(検査スクリプトが見つからない場合は警告のみでスキップする)。
#
# state値ごとの描画:
#   proposal / proposal-limited: 判定ボタン3個(採用/保留/却下) + evidence-list +
#     proposal(規約提案文) + source(出典)。pill--green(提案あり) /
#     pill--amber(提案あり(範囲限定))
#   na / common: 判定ボタンなし。reasonの1段落のみ。pill--na(対象外) /
#     pill--violet(→共通規約を参照)
#
# data-parent はカテゴリ側では持たず、所属するchapterのslugから導出する
# (規約定義と派生生成の設計.md 4節の判定結果JSONスキーマにもparentがあるが、
# こちらは提案の中身であり、取り込みスキルが書き込み先を決めるのに
# chapter.slugをそのまま使う設計とする)。
#
# CATSのJS実装: 原サンプル(手書き)ではカテゴリキーの配列を<script>内に
# ハードコードしていたが、テンプレート化にあたり
# `document.querySelectorAll("[data-report-row]")` からDOM経由で導出する形へ
# 変更した。これはCHAPTERS(可変部分)に応じてJS側の値も追従させる必要が
# あり、かつ規定のプレースホルダ表(タスク仕様)にCATS用のプレースホルダが
# 無いための最小限の一般化であり、判定UIの挙動(採用/保留/却下の切替・
# 進捗バー・コピー・ダウンロード)自体は1文字も変えていない。

set -euo pipefail

GENERATED_AT_DEFAULT="2026-01-01T00:00:00Z"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../../../delivery-payload/templates/rule-proposal/rule-proposal-template.html"
# 素直な形(静的検査スクリプトをこのリポジトリへ同梱する)を避け、実行マシン
# 固有の外部スキル置き場(このリポジトリの外)にあるreviewing-explanatory-html
# skillの検査器を、環境変数REVERSE_DOCS_RULE_PROPOSAL_VERIFY_SCRIPTで指す形にした。
# HTML静的検査(禁止色・box-shadow・未解決{{等)はこのリポジトリの他のHTML生成
# スクリプト(build-detail-page.sh等)が検査対象にする観点と重複するため、同梱して
# 二重保守するより既存の検査器を再利用する設計とした。固定の絶対パスを本体へ
# 直書きすると、このリポジトリ自身の自立の判定(check-self-contained.sh)が
# 「実行マシン固有のパスへ依存している」と検出してしまう(実測:
# docs/tasks/自立の判定の誤検知を減らす指示書.md)。環境変数を未設定にすれば
# 依存そのものが本体から消えるため、環境変数の既定値は空とする。
# run_static_verify()は環境変数が未設定、または指すパスが無い実行環境
# (agent-homeを持たないマシン・CI・納品先での再生成等)でも生成自体は止めず、
# 警告のみでスキップする(下記run_static_verify()内の各分岐参照)。
VERIFY_SCRIPT="${REVERSE_DOCS_RULE_PROPOSAL_VERIFY_SCRIPT:-}"

# --- 共通関数 ---

html_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g"
}

# state -> pillのCSSクラス
state_pill_class() {
  case "$1" in
    proposal) echo "pill--green" ;;
    proposal-limited) echo "pill--amber" ;;
    na) echo "pill--na" ;;
    common) echo "pill--violet" ;;
    *) echo "pill--na" ;;
  esac
}

# state -> pillの表示文言
state_pill_label() {
  case "$1" in
    proposal) echo "提案あり" ;;
    proposal-limited) echo "提案あり(範囲限定)" ;;
    na) echo "対象外" ;;
    common) echo "&#8594;共通規約を参照" ;;
    *) echo "対象外" ;;
  esac
}

# state -> TOCのtoc-tag文言(judgableは空文字)
toc_tag_label() {
  case "$1" in
    na) echo "対象外" ;;
    common) echo "&#8594;共通" ;;
    *) echo "" ;;
  esac
}

is_judgable_state() {
  case "$1" in
    proposal|proposal-limited) return 0 ;;
    *) return 1 ;;
  esac
}

# --- カテゴリ内図(figure)の <div class="layer-fig|state-fig"> + figcaption を組み立てる ---
render_figure() {
  local cat_json="$1"
  local has_figure
  has_figure="$(jq -r 'if .figure == null then "" else "yes" end' <<<"$cat_json")"
  [ -z "$has_figure" ] && return 0

  local kind caption items_count
  kind="$(jq -r '.figure.kind' <<<"$cat_json")"
  caption="$(jq -r '.figure.caption' <<<"$cat_json")"
  items_count="$(jq '.figure.items | length' <<<"$cat_json")"

  if [ "$kind" = "layers" ]; then
    printf '        <div class="layer-fig">\n'
    local i=0 label desc tone
    while [ "$i" -lt "$items_count" ]; do
      label="$(jq -r ".figure.items[$i].label" <<<"$cat_json")"
      desc="$(jq -r ".figure.items[$i].desc" <<<"$cat_json")"
      tone="$(jq -r ".figure.items[$i].tone" <<<"$cat_json")"
      printf '          <div class="layer-row" style="border-left-color:var(--%s)"><b>%s</b><span>%s</span></div>\n' \
        "$tone" "$(html_escape "$label")" "$(html_escape "$desc")"
      i=$((i + 1))
    done
    printf '        </div>\n'
    printf '        <p class="figcaption">%s</p>\n' "$(html_escape "$caption")"
  elif [ "$kind" = "states" ]; then
    printf '        <div class="state-fig">\n'
    local i=0 label
    while [ "$i" -lt "$items_count" ]; do
      label="$(jq -r ".figure.items[$i].label" <<<"$cat_json")"
      printf '          <span class="state-node">%s</span>' "$(html_escape "$label")"
      if [ "$i" -lt "$((items_count - 1))" ]; then
        printf '<span class="state-arrow">&#8594;</span>'
      fi
      printf '\n'
      i=$((i + 1))
    done
    printf '        </div>\n'
    printf '        <p class="figcaption">%s</p>\n' "$(html_escape "$caption")"
  fi
}

# --- 1カテゴリ分のTOC <li> を組み立てる ---
render_toc_item() {
  local key="$1" title="$2" state="$3"
  local title_esc
  title_esc="$(html_escape "$title")"
  if is_judgable_state "$state"; then
    printf '          <li><a href="#cat-%s"><span class="dot" id="dot-%s"></span><span class="toc-label">%s</span></a></li>\n' \
      "$key" "$key" "$title_esc"
  else
    local tag
    tag="$(toc_tag_label "$state")"
    printf '          <li><a href="#cat-%s"><span class="dot dot--na"></span><span class="toc-label">%s</span><span class="toc-tag">%s</span></a></li>\n' \
      "$key" "$title_esc" "$tag"
  fi
}

# --- 1カテゴリ分の <div class="category"> を組み立てる ---
render_category() {
  local cat_json="$1" chapter_index="$2" chapter_name="$3" parent_slug="$4"

  local key title state
  key="$(jq -r '.key' <<<"$cat_json")"
  title="$(jq -r '.title' <<<"$cat_json")"
  state="$(jq -r '.state' <<<"$cat_json")"

  local title_esc chapter_name_esc
  title_esc="$(html_escape "$title")"
  chapter_name_esc="$(html_escape "$chapter_name")"

  local pill_class pill_label
  pill_class="$(state_pill_class "$state")"
  pill_label="$(state_pill_label "$state")"

  if is_judgable_state "$state"; then
    local scope paths_json enforcement checkable check_method proposed_rule sources_json summary
    scope="$(jq -r '.scope' <<<"$cat_json")"
    paths_json="$(jq -c '.paths' <<<"$cat_json")"
    enforcement="$(jq -r '.enforcement' <<<"$cat_json")"
    checkable="$(jq -r '.checkable' <<<"$cat_json")"
    check_method="$(jq -r '.checkMethod' <<<"$cat_json")"
    proposed_rule="$(jq -r '.proposedRule' <<<"$cat_json")"
    sources_json="$(jq -c '.sources' <<<"$cat_json")"
    summary="$(jq -r '.summary' <<<"$cat_json")"

    # data-paths/data-sourcesだけ属性値の区切りを"(ダブルクォート)ではなく
    # \x27(printfの16進エスケープでシングルクォートを表す)にしている。
    # 値はjq -cで組み立てたJSON配列文字列であり、要素ごとに"を大量に含む。
    # html_escape()で"は&quot;へ変換済みのため二重引用符区切りでも壊れないが、
    # 出力後の生HTMLを人が読んだ/grepした時に"だらけの属性値を判別しやすくする
    # 目的で、この2属性だけシングルクォート区切りにしている(printfのformat文字列
    # 自体は単一引用符で囲むため、区切り文字そのものにシングルクォートを
    # 直接書けず\x27で書く必要がある)。
    printf '      <div class="category" id="cat-%s" data-report-row="%s" data-chapter-index="%s" data-chapter-name="%s" data-cat-name="%s" data-summary="%s" data-parent="%s" data-key="%s" data-scope="%s" data-paths=\x27%s\x27 data-enforcement="%s" data-checkable="%s" data-check-method="%s" data-proposed-rule="%s" data-sources=\x27%s\x27>\n' \
      "$key" "$key" "$chapter_index" "$chapter_name_esc" "$title_esc" "$(html_escape "$summary")" "$parent_slug" "$key" \
      "$scope" "$(html_escape "$paths_json")" "$enforcement" "$checkable" \
      "$(html_escape "$check_method")" "$(html_escape "$proposed_rule")" "$(html_escape "$sources_json")"
    printf '        <div class="cat-head">\n'
    printf '          <h3>%s</h3>\n' "$title_esc"
    printf '          <span class="pill %s">%s</span>\n' "$pill_class" "$pill_label"
    printf '          <div class="decision-buttons">\n'
    printf '          <button type="button" id="adopt-%s" class="decision-btn kind-adopt" data-decision="adopt" data-cat="%s">採用</button>\n' "$key" "$key"
    printf '          <button type="button" id="hold-%s" class="decision-btn kind-hold" data-decision="hold" data-cat="%s">保留</button>\n' "$key" "$key"
    printf '          <button type="button" id="reject-%s" class="decision-btn kind-reject" data-decision="reject" data-cat="%s">却下</button>\n' "$key" "$key"
    printf '          </div>\n'
    printf '        </div>\n'

    local obs_count
    obs_count="$(jq '.observations | length' <<<"$cat_json")"
    if [ "$obs_count" -gt 0 ]; then
      printf '        <ul class="evidence-list">\n'
      while IFS= read -r obs; do
        printf '          <li>%s</li>\n' "$obs"
      done < <(jq -r '.observations[]' <<<"$cat_json")
      printf '        </ul>\n'
    fi

    render_figure "$cat_json"

    if [ -n "$proposed_rule" ]; then
      printf '        <div class="proposal">\n'
      printf '          <p class="proposal-label">規約提案文(案)</p>\n'
      printf '          <p class="proposal-text">%s</p>\n' "$(html_escape "$proposed_rule")"
      printf '        </div>\n'
    fi

    local source_count
    source_count="$(jq '.sources | length' <<<"$cat_json")"
    if [ "$source_count" -gt 0 ]; then
      local source_line=""
      while IFS= read -r src; do
        local src_html="<code>$(html_escape "$src")</code>"
        if [ -z "$source_line" ]; then source_line="$src_html"; else source_line="${source_line}、${src_html}"; fi
      done < <(jq -r '.sources[]' <<<"$cat_json")
      printf '        <p class="source">出典: %s</p>\n' "$source_line"
    fi
    printf '      </div>\n'
  else
    local reason
    reason="$(jq -r '.reason' <<<"$cat_json")"
    printf '      <div class="category" id="cat-%s">\n' "$key"
    printf '        <div class="cat-head">\n'
    printf '          <h3>%s</h3>\n' "$title_esc"
    printf '          <span class="pill %s">%s</span>\n' "$pill_class" "$pill_label"
    printf '        </div>\n'
    if [ -n "$reason" ]; then
      printf '        <p class="reason">%s</p>\n' "$(html_escape "$reason")"
    fi
    printf '      </div>\n'
  fi
}

# --- 全チャプターぶんの <section class="chapter"> を組み立てる ---
build_chapters_and_toc() {
  local input="$1"
  CHAPTERS_HTML=""
  TOC_HTML=""
  TOTAL_JUDGABLE=0

  local chapter_json
  while IFS= read -r chapter_json; do
    local idx title slug description
    idx="$(jq -r '.index' <<<"$chapter_json")"
    title="$(jq -r '.title' <<<"$chapter_json")"
    slug="$(jq -r '.slug' <<<"$chapter_json")"
    description="$(jq -r '.description' <<<"$chapter_json")"
    local idx_padded
    idx_padded="$(printf '%02d' "$idx")"

    CHAPTERS_HTML="${CHAPTERS_HTML}    <section class=\"chapter\" id=\"chapter-${slug}\">
      <div class=\"chapter-head\">
        <span class=\"chapter-num\">${idx_padded}</span>
        <h2>$(html_escape "$title")</h2>
      </div>
      <p class=\"chapter-desc\">$(html_escape "$description")</p>
"
    TOC_HTML="${TOC_HTML}        <p class=\"toc-chapter\">${idx_padded} $(html_escape "$title")</p>
        <ul class=\"toc-list\">
"
    local cat_json
    while IFS= read -r cat_json; do
      local cat_state
      cat_state="$(jq -r '.state' <<<"$cat_json")"
      if is_judgable_state "$cat_state"; then
        TOTAL_JUDGABLE=$((TOTAL_JUDGABLE + 1))
      fi
      CHAPTERS_HTML="${CHAPTERS_HTML}$(render_category "$cat_json" "$idx" "$title" "$slug")
"
      local cat_key cat_title
      cat_key="$(jq -r '.key' <<<"$cat_json")"
      cat_title="$(jq -r '.title' <<<"$cat_json")"
      TOC_HTML="${TOC_HTML}$(render_toc_item "$cat_key" "$cat_title" "$cat_state")
"
    done < <(jq -c '.categories[]' <<<"$chapter_json")

    TOC_HTML="${TOC_HTML}        </ul>
"
    CHAPTERS_HTML="${CHAPTERS_HTML}    </section>
"
  done < <(jq -c '.chapters[]' "$input")
}

# --- 処理フロー図(flowDiagram)の <details class="fig"> を組み立てる ---
build_flow_diagram() {
  local input="$1"
  local has_flow
  has_flow="$(jq -r 'if .flowDiagram == null then "" else "yes" end' "$input")"
  if [ -z "$has_flow" ]; then
    FLOW_DIAGRAM_HTML=""
    return
  fi

  local caption node_count
  caption="$(jq -r '.flowDiagram.caption' "$input")"
  node_count="$(jq '.flowDiagram.nodes | length' "$input")"

  local html="    <details class=\"fig\">
      <summary>図1: リクエスト処理フロー</summary>
      <div class=\"flow\">
"
  local i=0 name desc
  while [ "$i" -lt "$node_count" ]; do
    name="$(jq -r ".flowDiagram.nodes[$i].name" "$input")"
    desc="$(jq -r ".flowDiagram.nodes[$i].desc" "$input")"
    html="${html}        <div class=\"flow-node\"><b>$(html_escape "$name")</b><span>$(html_escape "$desc")</span></div>
"
    if [ "$i" -lt "$((node_count - 1))" ]; then
      html="${html}        <span class=\"flow-arrow\">&#8594;</span>
"
    fi
    i=$((i + 1))
  done
  html="${html}      </div>
      <p class=\"figcaption\">$(html_escape "$caption")</p>
    </details>"
  FLOW_DIAGRAM_HTML="$html"
}

# --- 横断的所見(crossFindings)の <div class="notes"> を組み立てる ---
severity_note_class() {
  case "$1" in
    risk) echo "note--brick" ;;
    caution) echo "note--amber" ;;
    reference) echo "note--violet" ;;
    *) echo "note--violet" ;;
  esac
}

build_cross_findings() {
  local input="$1"
  local count
  count="$(jq '.crossFindings | length' "$input")"
  if [ "$count" -eq 0 ]; then
    CROSS_FINDINGS_HTML=""
    return
  fi
  local html="    <div class=\"notes\">
"
  local finding_json
  while IFS= read -r finding_json; do
    local severity title body note_class
    severity="$(jq -r '.severity' <<<"$finding_json")"
    title="$(jq -r '.title' <<<"$finding_json")"
    body="$(jq -r '.body' <<<"$finding_json")"
    note_class="$(severity_note_class "$severity")"
    html="${html}      <div class=\"note ${note_class}\">
        <p class=\"note-title\">$(html_escape "$title")</p>
        <p class=\"note-body\">${body}</p>
      </div>
"
  done < <(jq -c '.crossFindings[]' "$input")
  html="${html}    </div>"
  CROSS_FINDINGS_HTML="$html"
}

# 素直な形(VERIFY_SCRIPT・nodeが無ければ生成自体を失敗させるfail-closed)を避け、
# 警告のみでスキップしてreturn 0する(fail-open)。VERIFY_SCRIPTは環境変数
# REVERSE_DOCS_RULE_PROPOSAL_VERIFY_SCRIPT経由で実行マシン固有の外部スキル
# 置き場(このリポジトリの外)を指すため、環境変数を設定しない実行環境
# (他マシン・CI・納品先での再生成等)では常に空・不在扱いになる。この検査は
# このリポジトリの開発時の追加チェックであり、本体の生成契約(決定的なHTML生成)
# に必須の依存ではないため、不在を理由に生成そのものを止めない。
run_static_verify() {
  local html_path="$1"
  if [ -z "$VERIFY_SCRIPT" ]; then
    echo "WARN: 静的検査スクリプトの環境変数(REVERSE_DOCS_RULE_PROPOSAL_VERIFY_SCRIPT)が未設定のため静的検査をスキップしました" >&2
    return 0
  fi
  if [ ! -f "$VERIFY_SCRIPT" ]; then
    echo "WARN: verify-html-static.mjs が見つからないため静的検査をスキップしました: $VERIFY_SCRIPT" >&2
    return 0
  fi
  if ! command -v node >/dev/null 2>&1; then
    echo "WARN: node が見つからないため静的検査をスキップしました" >&2
    return 0
  fi
  node "$VERIFY_SCRIPT" "$html_path"
}

# --- メイン生成処理 ---
build_rule_proposal() {
  local input="$1" output="$2" generated_at="$3"

  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required but not found in PATH" >&2
    return 1
  fi
  if [ ! -f "$input" ]; then
    echo "ERROR: input not found: $input" >&2
    return 1
  fi
  if [ ! -f "$TEMPLATE" ]; then
    echo "ERROR: template not found: $TEMPLATE" >&2
    return 1
  fi
  if ! jq -e . "$input" >/dev/null 2>&1; then
    echo "ERROR: input is not valid JSON: $input" >&2
    return 1
  fi

  local proposal_id title lead is_sample
  proposal_id="$(jq -r '.proposalId' "$input")"
  title="$(jq -r '.title' "$input")"
  lead="$(jq -r '.lead' "$input")"
  is_sample="$(jq -r '.isSample' "$input")"

  local meta_positioning meta_scope meta_verification
  meta_positioning="$(jq -r '.meta.positioning' "$input")"
  meta_scope="$(jq -r '.meta.scope' "$input")"
  meta_verification="$(jq -r '.meta.verification' "$input")"

  local sample_badge=""
  if [ "$is_sample" = "true" ]; then
    sample_badge='    <span class="badge">SAMPLE</span>'
  fi

  build_chapters_and_toc "$input"
  build_flow_diagram "$input"
  build_cross_findings "$input"

  mkdir -p "$(dirname "$output")"

  source "$(cd "$SCRIPT_DIR/../.." && pwd)/scripts/render-template.sh"

  local out
  out="$(render_template "$(cat "$TEMPLATE")" \
    "{{PROPOSAL_ID}}" "$(html_escape "$proposal_id")" \
    "{{DOC_TITLE}}" "$(html_escape "$title")" \
    "{{LEAD}}" "$(html_escape "$lead")" \
    "{{META_POSITIONING}}" "$(html_escape "$meta_positioning")" \
    "{{META_SCOPE}}" "$(html_escape "$meta_scope")" \
    "{{META_VERIFICATION}}" "$(html_escape "$meta_verification")" \
    "{{SAMPLE_BADGE}}" "$sample_badge" \
    "{{FLOW_DIAGRAM}}" "$FLOW_DIAGRAM_HTML" \
    "{{CROSS_FINDINGS}}" "$CROSS_FINDINGS_HTML" \
    "{{CHAPTERS}}" "$CHAPTERS_HTML" \
    "{{TOC}}" "$TOC_HTML" \
    "{{TOTAL}}" "$TOTAL_JUDGABLE" \
    "{{GENERATED_AT}}" "$(html_escape "$generated_at")")"

  printf '%s\n' "$out" > "$output"

  if ! run_static_verify "$output"; then
    echo "ERROR: $output は静的検査(verify-html-static.mjs)に不合格でした" >&2
    return 1
  fi

  echo "OK: wrote $output" >&2
}

# --- --self-test モード ---
self_test() {
  local script_path="$0"
  local tmp rc=0
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/build-rule-proposal-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' RETURN

  # --- (1) 最小の入力JSONから生成し、文書骨格を持つこと ---
  local data_min="$tmp/min.json"
  jq -n '{
    proposalId: "self-test-min",
    title: "自己テスト用最小提案",
    lead: "自己テストのための最小データである。",
    isSample: false,
    meta: {positioning: "位置づけ", scope: "範囲", verification: "検証"},
    crossFindings: [],
    chapters: [{
      index: 1, title: "章1", slug: "chapter-one", description: "chapter-one",
      categories: [
        {key: "cat-a", title: "カテゴリA", state: "proposal", summary: "カテゴリAの要約文。", observations: ["<code>a.ts:1</code> の観測1件。"], proposedRule: "規約A案", sources: ["a.ts:1"], scope: "scoped", paths: ["a/**"], enforcement: "advisory", checkable: true, checkMethod: "検査方法A", reason: ""},
        {key: "cat-b", title: "カテゴリB", state: "na", summary: "", observations: [], proposedRule: "", sources: [], scope: "always", paths: [], enforcement: "advisory", checkable: false, checkMethod: "", reason: "対象外の理由B"},
        {key: "cat-c", title: "カテゴリC", state: "common", summary: "", observations: [], proposedRule: "", sources: [], scope: "always", paths: [], enforcement: "advisory", checkable: false, checkMethod: "", reason: "共通規約を参照する理由C"}
      ]
    }]
  }' > "$data_min"

  local out_min="$tmp/min.html"
  if bash "$script_path" "$data_min" "$out_min" --generated-at "2026-01-01T00:00:00Z" >/dev/null 2>&1 \
    && grep -q '<!doctype html>' "$out_min" \
    && grep -q '<h1>自己テスト用最小提案</h1>' "$out_min" \
    && grep -q 'id="cat-cat-a"' "$out_min"; then
    echo "  [PASS] 1: 最小入力JSONから文書骨格を持つHTMLを生成"
  else
    echo "  [FAIL] 1: 最小入力JSONからの生成、または文書骨格の確認に失敗した" >&2
    rc=1
  fi

  # --- (2) state=na/common に判定ボタンが出ないこと ---
  if ! grep -q 'id="adopt-cat-b"' "$out_min" \
    && ! grep -q 'id="adopt-cat-c"' "$out_min" \
    && grep -q 'id="adopt-cat-a"' "$out_min"; then
    echo "  [PASS] 2: state=na/common のカテゴリに判定ボタンが出ない(proposalには出る)"
  else
    echo "  [FAIL] 2: na/common への判定ボタン非表示、またはproposalへの表示に失敗した" >&2
    rc=1
  fi

  # --- (3) {{TOTAL}} が proposal/proposal-limited の数と一致すること(このケースは1件) ---
  if grep -q '判定 0/1' "$out_min"; then
    echo "  [PASS] 3: {{TOTAL}}がproposal/proposal-limitedの数(1件)と一致"
  else
    echo "  [FAIL] 3: {{TOTAL}}の値が期待(1件)と不一致" >&2
    rc=1
  fi

  # --- (4) 同じ入力で2回生成した結果がbyte一致すること ---
  local out_min_2="$tmp/min-2.html"
  bash "$script_path" "$data_min" "$out_min_2" --generated-at "2026-01-01T00:00:00Z" >/dev/null 2>&1 || true
  if _gt_out4="$(diff -q "$out_min" "$out_min_2" 2>&1)"; then
    echo "  [PASS] 4: 同一入力からの2回の生成がbyte一致(決定的生成)"
  else
    echo "  [FAIL] 4: 同一入力からの2回の生成がbyte不一致" >&2
    printf '%s\n' "$_gt_out4" | sed 's/^/    /' >&2
    rc=1
  fi

  # --- (5) 禁止色(#888・#ccc・gray)とbox-shadowが0件であること ---
  local forbidden_count
  forbidden_count="$(grep -ciE '#888|#ccc|:\s*gray|box-shadow' "$out_min" 2>/dev/null || true)"
  forbidden_count="${forbidden_count:-0}"
  if [ "$forbidden_count" -eq 0 ]; then
    echo "  [PASS] 5: 禁止色・box-shadowが0件"
  else
    echo "  [FAIL] 5: 禁止色・box-shadowが${forbidden_count}件検出された" >&2
    rc=1
  fi

  # --- (6) 未解決の{{が残らないこと(回帰確認) ---
  if grep -qF '{{' "$out_min"; then
    echo "  [FAIL] 6: 出力に未解決の{{が残存" >&2
    rc=1
  else
    echo "  [PASS] 6: 出力に未解決の{{が残らない"
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

INPUT="${1:?Usage: build-rule-proposal.sh <入力JSON> <出力HTML> [--generated-at <iso8601>]}"
OUTPUT="${2:?Usage: build-rule-proposal.sh <入力JSON> <出力HTML> [--generated-at <iso8601>]}"
shift 2 || true

GENERATED_AT="$GENERATED_AT_DEFAULT"
while [ $# -gt 0 ]; do
  case "$1" in
    --generated-at)
      GENERATED_AT="${2:-}"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

build_rule_proposal "$INPUT" "$OUTPUT" "$GENERATED_AT"
