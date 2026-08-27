#!/usr/bin/env bash
set -euo pipefail

# scaffold-rule-definitions.sh — まっさらな対象リポジトリへ規約定義一式を配る
#
# 設計の定義: delivery-payload/references/規約定義と派生生成の設計.md
# 宣言データ: delivery-payload/references/rule-taxonomy.json（親7・子27の英語キー・表示名・既定値）
#
# 目的:
#   docs/rules/ が空、または未整備の対象リポジトリに、親7フォルダ・parent.yml、
#   子27フォルダ・rule.md（空雛形）を作る。rule-taxonomy.json で toolDefined を
#   宣言している子カテゴリはツール側が本文を書いて納品する規約のため、空雛形にせず
#   本文入りで作る。あわせて --with-skills 指定時は納品スキル3本、
#   検証と生成のスクリプト（docs/rules/agent-operations/ai-config-asset-management/）を配る。
#   実装フローのゲートが必須とする
#   .claude/rules/always/project-context/flow-values.yml・rule.md の2ファイルも
#   （既存なら上書きしない保護つきで）同時に配る。
#
# 使い方:
#   scaffold-rule-definitions.sh <出力先リポジトリルート> [--apply] [--with-skills]
#   scaffold-rule-definitions.sh --self-test
#
# 既定はdry-run。生成予定のパスを標準出力へ列挙するのみで書き込みをしない。
# --apply を付けたときだけ出力先リポジトリルートへ実際に書き込む。
#
# 既存ファイルの扱い:
#   parent.yml・design-notes.md・SKILL.md は、既に存在する場合は上書きしない
#   （現場が書き込んだ内容を保護する）。
#   rule.md は toolDefined の値で扱いが分かれる。
#     toolDefined: false（draft雛形）の子カテゴリ: 既存なら上書きしない（ファイル単位の保護）。
#     toolDefined: true（ツール側が本文を定める規約）の子カテゴリ: 「概要」「規則」
#       「違反時の手順」の3節は既存でも常にツールの本文で上書きする（改善課題1-48）。
#       「このプロジェクトの規則」節だけは節単位で保護する
#       （merge_project_rule_section を参照）。既存の当該節がプレースホルダ1行
#       （定義済みの未解析／対象なし、または旧出力の空欄行）だけの場合はツールの
#       本文で上書きし、現場がリバース解析の観測から書き足した内容を持つ場合は
#       その内容を保持する。上書きの単位をファイルからこの節だけへ下げたことで、
#       現場が退避・書き戻しの手作業をせずに配置を再実行できる。
#   存在した件数と新規に作った件数を最後に報告する（この件数は上記の保護判定を
#   経た「ファイルとして新規に書いたか・既存として扱ったか」を数え、節単位の
#   マージが起きたかどうかは区別しない）。
#
# --with-skills:
#   配る対象は delivery-payload/references/delivered-skill-catalog.json の
#   .skills[] のみを唯一の情報源とし、対象名をスクリプトへ直接書かない。
#   各スキルの各ファイルを2段で配る（規約の定義から派生への2段構成にスキルも揃える）。
#     1段目（定義）: delivery-payload/templates/delivered-skills/<name>/<file> を
#       <出力先>/<catalogのdefinitionRoot>/<name>/<file> へ複製する（既存なら上書きしない）。
#     2段目（派生）: 1段目で置いた定義ファイルを
#       <出力先>/<catalogのderiveRoot>/<name>/<file> へ複製する（既存でも常に上書きする）。
#       .md ファイルは front matter を保ったまま、front matter 直後に生成物notice comment
#       を入れる（build-derived-rules.sh の .mdc 生成と同じ配置規約）。.md 以外
#       （scripts/apply-confirmation-answers.mjs 等）は notice comment を入れずそのまま複製する。
#   あわせて delivery-payload/templates/delivered-agents/rule-reviewer.md を
#   <出力先>/.claude/agents/rule-reviewer.md へ同じ生成物notice comment規約で複製する
#   （こちらは1段のみ。dev-flow の Phase5（実装後はレビューを通してから統合する）が
#   使うレビュアーであり、スキル群と同じく dev-flow を支える配布物のため同じフラグで配る）。
#   加えて deploy-generation-engine.sh を呼び、<出力先>/reverse-docs-engine/ へ
#   生成器一式（generation-engine/scripts・delivery-payload/templates・
#   delivery-payload/references）を配る（maintaining-portal スキルが前提とする
#   生成器の再実行手段であり、スキル群と同じフラグで配る。重複実装しない）。
#
# docs/rules/agent-operations/ai-config-asset-management/ への検証・生成スクリプトの配備:
#   build-derived-rules.sh --deploy-rule-scripts を呼ぶだけで、重複実装しない
#   （--apply指定時のみ実行。dry-runでは呼ばず計画行のみ列挙する）。
#
# 終了コード:
#   0 = 生成（またはdry-runの列挙）が完了
#   1 = 引数不正、または taxonomy 読み込み失敗
#   --self-test のみ、期待どおりの生成ができなければ1
#
# 保守責任者・廃棄条件: generation-engine/scripts/rules/rule.md の「## 設計判断」を参照。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=./validate-rule-definitions.sh
. "${SCRIPT_DIR}/validate-rule-definitions.sh"
# shellcheck source=../output-layout.sh
. "${SCRIPT_DIR}/../output-layout.sh"
# shellcheck source=./rule-scope-overrides.sh
. "${SCRIPT_DIR}/rule-scope-overrides.sh"

TAXONOMY_JSON="${REPO_ROOT}/delivery-payload/references/rule-taxonomy.json"
BANNED_TERMS_JSON="${REPO_ROOT}/delivery-payload/references/rule-banned-terms.json"
BUILD_DERIVED_SCRIPT="${SCRIPT_DIR}/build-derived-rules.sh"
DEPLOY_GENERATION_ENGINE_SCRIPT="${SCRIPT_DIR}/deploy-generation-engine.sh"
SKILLS_TEMPLATE_DIR="${REPO_ROOT}/delivery-payload/templates/delivered-skills"
SKILL_CATALOG_JSON="${REPO_ROOT}/delivery-payload/references/delivered-skill-catalog.json"
AGENTS_TEMPLATE_DIR="${REPO_ROOT}/delivery-payload/templates/delivered-agents"
TOOLDEFINED_TEMPLATE_DIR="${REPO_ROOT}/delivery-payload/templates/rules/tool-defined"
CHECKERS_TEMPLATE_DIR="${REPO_ROOT}/delivery-payload/templates/rules/checkers"

APPLY=0
WITH_SKILLS=0
PLAN_LINES=""
RULE_NEW=0
RULE_EXIST=0
OTHER_NEW=0
OTHER_EXIST=0
SKILL_NEW=0
SKILL_EXIST=0
AGENT_NEW=0
AGENT_EXIST=0

plan_add() {
  PLAN_LINES="${PLAN_LINES}${1}
"
}

# 対象パスが既存なら書き込まずスキップする。新規なら（--apply時のみ）書き込む。
# ただし tool_defined が true のときは既存でもスキップせず常にファイルを書き直す
# （改善課題1-48: ツール側が本文を定める規約は他経路の本文で上書きされてはならない）。
# rule.md を tool_defined="true" で呼ぶ呼び出し元（run_scaffold）は、この関数へ
# 渡す $2（内容）自体を先に merge_project_rule_section へ通し、「このプロジェクトの
# 規則」節だけは既存の内容（プレースホルダでない場合）を保った状態にしてから渡す。
# つまり本関数はファイル単位の書き込み判定のみを担い、節単位の保護は
# merge_project_rule_section が呼び出し元側で担う（上書きの単位をファイルから
# 節へ下げる3.1の実装はこの2関数の分業で成立している）。
# $1: 出力パス  $2: 内容  $3: カウンタ種別（rule / other）  $4: tool_defined（省略可）
write_if_new() {
  local path="$1" content="$2" kind="$3" tool_defined="${4:-}"
  if [ -e "$path" ] && [ "$tool_defined" != "true" ]; then
    if [ "$kind" = "rule" ]; then
      RULE_EXIST=$((RULE_EXIST + 1))
    else
      OTHER_EXIST=$((OTHER_EXIST + 1))
    fi
    return 0
  fi
  if [ "$kind" = "rule" ]; then
    RULE_NEW=$((RULE_NEW + 1))
  else
    OTHER_NEW=$((OTHER_NEW + 1))
  fi
  plan_add "$path"
  if [ "$APPLY" -eq 1 ]; then
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" > "$path"
  fi
}

# 対象パスが既存なら書き込まずスキップする。新規なら（--apply時のみ）ソースファイルを
# 実行権限を保ったまま複製する。write_if_new のスキップ判定と同じだが、内容が
# 文字列ではなくファイル（checker本体・回帰テスト）のため cp + chmod を使う。
# $1: 出力パス  $2: ソースパス  $3: カウンタ種別（rule / other）
copy_if_new() {
  local path="$1" src="$2" kind="$3"
  if [ -e "$path" ]; then
    if [ "$kind" = "rule" ]; then
      RULE_EXIST=$((RULE_EXIST + 1))
    else
      OTHER_EXIST=$((OTHER_EXIST + 1))
    fi
    return 0
  fi
  if [ "$kind" = "rule" ]; then
    RULE_NEW=$((RULE_NEW + 1))
  else
    OTHER_NEW=$((OTHER_NEW + 1))
  fi
  plan_add "$path"
  if [ "$APPLY" -eq 1 ]; then
    mkdir -p "$(dirname "$path")"
    cp "$src" "$path"
    chmod +x "$path"
  fi
}

# projectRulePlaceholders の指定行を生成する。4列の定義が空またはnullなら、
# 壊れたプレースホルダを配らずに明示的に失敗する。
# $1: rule-taxonomy.json の projectRulePlaceholders にあるキー
project_rule_placeholder_row() {
  local placeholder_key="$1" values label content basis verification
  if ! values="$(jq -er --arg key "$placeholder_key" '
    .projectRulePlaceholders[$key]
    | select(type == "object")
    | [.label, .content, .basis, .verification]
    | if all(.[]; type == "string" and length > 0) then @tsv else empty end
  ' "$TAXONOMY_JSON")"; then
    echo "ERROR: taxonomyのprojectRulePlaceholders.${placeholder_key}にlabel/content/basis/verificationを空でない文字列として定義してください" >&2
    return 1
  fi
  local IFS=$'\t'
  read -r label content basis verification <<EOF
$values
EOF
  printf '| %s | %s | %s | %s |' "$label" "$content" "$basis" "$verification"
}

# projectRulePlaceholders の指定ラベルを取得する。認識用の条件も生成定義を唯一の
# 正本として使い、生成スクリプトへ表記を直書きしない。
project_rule_placeholder_label() {
  local placeholder_key="$1" label
  if ! label="$(jq -er --arg key "$placeholder_key" '
    .projectRulePlaceholders[$key].label
    | select(type == "string" and length > 0)
  ' "$TAXONOMY_JSON")"; then
    echo "ERROR: taxonomyのprojectRulePlaceholders.${placeholder_key}.labelを空でない文字列として定義してください" >&2
    return 1
  fi
  printf '%s' "$label"
}

# 「## このプロジェクトの規則」節が、ツールが置いたプレースホルダ1行だけかを判定する。
# プレースホルダ行は projectRulePlaceholders が定義する2種だけを既知の行として扱う。
# 現場が行の中身を書き換えていれば（1行のままでも）プレースホルダとはみなさない。
# $1: 節本文（見出し行を含む）。戻り値0=プレースホルダのみ、1=現場の内容を含む
is_placeholder_project_rule_section() {
  local section="$1" rows row_count unanalysed_label not_applicable_label
  # BSD grep（macOS標準）は -E なしのBREモードで \| をGNU拡張の交番として解釈し、
  # 「empty (sub)expression」エラーになる。3本とも -E を必ず付ける。
  rows="$(printf '%s\n' "$section" | grep -E '^\|' | grep -E -v '^\| 規則 \|' | grep -E -v '^\|---')"
  row_count="$(printf '%s\n' "$rows" | grep -c . || true)"
  [ "$row_count" -eq 1 ] || return 1
  unanalysed_label="$(project_rule_placeholder_label unanalysed)" || return 1
  not_applicable_label="$(project_rule_placeholder_label notApplicable)" || return 1
  case "$rows" in
    "| ${unanalysed_label} |"*) return 0 ;;
    "| ${not_applicable_label} |"*) return 0 ;;
    # 旧出力を置換対象として認識するだけで生成しない。
    '| （未記入） |'*) return 0 ;;
    *) return 1 ;;
  esac
}

# 上書き単位をファイルからこの節だけへ下げる（3.1）。
# 既存の rule.md が「## このプロジェクトの規則」節にプレースホルダ以外の内容
# （現場がリバース解析の観測から書き足した規則）を持つ場合、新しく組み立てた
# 本文（$1）の当該節を、既存ファイル（$2）の当該節でそのまま置き換えて返す。
# プレースホルダのみ、または既存ファイル自体が無い／節を持たない場合は $1 をそのまま返す。
# 「概要」「規則」「違反時の手順」の各節はこの関数を経由せず、常にツールの本文で上書きされる
# （3.1の表のとおり。この関数が触るのは「このプロジェクトの規則」節のみ）。
# $1: 新しく組み立てた rule.md 全文  $2: 既存の rule.md のパス
merge_project_rule_section() {
  local new_content="$1" existing_path="$2" existing_section
  if [ ! -f "$existing_path" ]; then
    printf '%s' "$new_content"
    return 0
  fi

  existing_section="$(awk '
    /^## このプロジェクトの規則$/ { f=1 }
    f && /^## / && !/^## このプロジェクトの規則$/ { exit }
    f { print }
  ' "$existing_path")"

  if [ -z "$existing_section" ] || is_placeholder_project_rule_section "$existing_section"; then
    printf '%s' "$new_content"
    return 0
  fi

  # macOS標準の awk（one-true-awk）は -v への複数行文字列の割り当てを
  # サポートしない（"newline in string" で構文解析エラーになる。gawk なら通るが
  # このリポジトリは macOS bash 3.2 互換を前提とするため使えない）。
  # そのため awk -v ではなく、行番号を求めて head/tail で継ぎ合わせる。
  local tmp_new
  tmp_new="$(mktemp "${TMPDIR:-/tmp}/scaffold-rule-definitions-merge.XXXXXX")"
  printf '%s\n' "$new_content" > "$tmp_new"

  local start_line end_line total_lines
  start_line="$(grep -n '^## このプロジェクトの規則$' "$tmp_new" | head -n1 | cut -d: -f1)"
  if [ -z "$start_line" ]; then
    cat "$tmp_new"
    rm -f "$tmp_new"
    return 0
  fi
  end_line="$(awk -v s="$start_line" 'NR>s && /^## /{print NR; exit}' "$tmp_new")"
  total_lines="$(wc -l < "$tmp_new" | tr -d ' ')"
  [ -n "$end_line" ] || end_line=$((total_lines + 1))

  # command substitution（$(...)）は末尾の改行をすべて剥がす。そのため
  # existing_section が元のファイルで持っていた「節の末尾の空行が何行か」は
  # ここまでの過程で失われており、正しく復元できない（既知の制約）。
  # 次の見出しへ続く場合は、既存の空行数に依存せず常に空行を1行だけ入れて
  # 区切る（全テンプレートの書式と同じ規約）。次の見出しが無い場合
  # （enforcement: none で節がファイル末尾になる場合）は空行を足さない。
  head -n $((start_line - 1)) "$tmp_new"
  printf '%s\n' "$existing_section"
  if [ "$end_line" -le "$total_lines" ]; then
    printf '\n'
    tail -n +"$end_line" "$tmp_new"
  fi
  rm -f "$tmp_new"
}

# ---------------------------------------------------------------------------
# コンテンツ組み立て
# ---------------------------------------------------------------------------

build_parent_yml() {
  local key="$1" title="$2"
  printf 'key: %s\ntitle: %s\n' "$key" "$title"
}

build_design_notes() {
  local title="$1" tool_defined="${2:-false}"
  if [ "$tool_defined" = "true" ]; then
    cat <<EOF
# 設計判断

「${title}」はツール側が本文を定めた規約であり、規約本文は確定している。

- 必要性: 規約の遵守を静的解析で判定する仕組みを持たない
- 今後の判断: 検査の手段が見つかった時点で checkable の要否を判断する
- 保守責任者: 人手（ユーザー）。ツール側の定義を保守する担当者
- 廃棄条件: この規約をツール側の定義から外し、現場が記入する空雛形へ戻した時
EOF
    return 0
  fi
  cat <<EOF
# 設計判断

「${title}」は雛形の段階であり、検査対象となる規則がまだ確定していない。

- 必要性: 規則本文が未記入のため、機械検査（linter）を書く対象が存在しない
- 今後の判断: 規則本文が確定した時点で、checkable の要否と checker の実装を判断する
- 保守責任者: 人手（ユーザー）。規則本文を記入する現場の担当者
- 廃棄条件: 規則本文が確定し、checkable: true として checker を実装した時
EOF
}

build_draft_rule_md() {
  local key="$1" title="$2" parent="$3" summary="$4"
  # $5・$6（省略可）: scope・paths。省略時は既定 always / ["**/*"]。
  # 3.3: 呼び出し元（run_scaffold）が対象側の上書き（rule-scope-overrides.json）を
  # 解決した値を渡す。宣言が無ければtaxonomyの既定値がそのまま渡ってくる。
  local scope="${5:-always}" paths="${6:-[\"**/*\"]}"
  # enforcement: このスキャフォールドが生成する空雛形は常に none（機械検知しない
  # 取り決め）として配る。設計（delivery-payload/references/規約定義と派生生成の設計.md
  # 3節）は「## 違反時の手順」節を enforcement: advisory のときのみ必須とし、
  # none のときは置かないと定める。値をローカル変数に持ち、下の分岐で判定する。
  local enforcement="none"
  cat <<EOF
---
key: ${key}
title: ${title}
parent: ${parent}
summary: ${summary}
scope: ${scope}
paths: ${paths}
enforcement: ${enforcement}
checkable: false
checker: null
uncheckableReason: （未記入）
formatter: none
status: draft
origin: template
---

# ${title}

## 概要

${summary}

（未記入）

## 規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| （未記入） | （未記入） | （未記入） | （未記入） |
<!-- 検査列には、その規則の違反を静的解析で見つける方法を書く。検査できない規則は「不可: <理由>」と書き、その理由を front matter の uncheckableReason へ写す。 -->

## このプロジェクトの規則

<!-- リバース解析が対象リポジトリの観測から起こした規則を置く。観測できるものが無かった場合は表を消さず、「観測なし」とその理由を書く。 -->

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| （未記入） | （未記入） | （未記入） | （未記入） |
EOF
  if [ "$enforcement" != "none" ]; then
    cat <<EOF

## 違反時の手順

1. （未記入）
EOF
  fi
}

# appliesWhen（rule-taxonomy.jsonの当該子カテゴリが持つ判定条件）を評価し、
# 「未解析」「対象なし」「観測あり」のいずれかを判定する。
# 判定の材料（マニフェスト）は出力先リポジトリ（$1 out_root）に置かれる。
# パス解決は output-layout.sh の resolve_output_layout / output_layout_get を使い、
# docs/manifests/ を直書きしない（build-deliverable-inventory.sh と同じ方式）。
# $3（省略可）: 呼び出し側が既に resolve_output_layout 済みのJSON。子カテゴリ数だけ
#   resolve_output_layout（内部でnode起動を伴う）を繰り返さないよう、
#   run_scaffold は1回だけ解決した結果を渡す（build-deliverable-inventory.shの
#   build_rows と同じ「1回解決・使い回し」方式）。省略時はこの関数の中で解決する
#   （self-testの直接呼び出し用のフォールバック）。
# 標準出力: "<状態>\t<対象の名前（対象なし文言で使うラベル。複数はと で連結）>"
#   状態は 未解析 / 対象なし / 観測あり のいずれか。
# 材料が全く解決できない場合（output-layout.json不在・jq失敗等）は安全側の
# 「未解析」を返す（fail-safe。ケース1のような出力先未作成の呼び出しでも
# set -euo pipefail 下で落ちないようにする）。
resolve_applies_when_state() {
  local out_root="$1" applies_when_json="$2" layout_json="${3:-}"

  if [ -z "$layout_json" ]; then
    layout_json="$(resolve_output_layout "$out_root" 2>/dev/null)" || { printf '未解析\t\n'; return 0; }
  fi

  local manifests_root
  manifests_root="$(output_layout_get "$layout_json" manifestsRoot 2>/dev/null)" || { printf '未解析\t\n'; return 0; }

  local entries entry manifest_name min_count kind label
  local labels="" any_manifest_found=0 satisfied=0
  entries="$(printf '%s' "$applies_when_json" | jq -c '.anyOf[]' 2>/dev/null)" || { printf '未解析\t\n'; return 0; }

  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    manifest_name="$(printf '%s' "$entry" | jq -r '.manifest')"
    min_count="$(printf '%s' "$entry" | jq -r '.minCount')"
    kind="${manifest_name%-manifest.json}"
    label="$(output_layout_kind_label "$layout_json" "$kind" 2>/dev/null)" || label="$kind"
    if [ -n "$labels" ]; then
      labels="${labels}と${label}"
    else
      labels="${label}"
    fi

    local manifest_path item_count
    manifest_path="${out_root}/${manifests_root}/${manifest_name}"
    [ -f "$manifest_path" ] || continue
    any_manifest_found=1
    item_count="$(jq '((.screens // .units // []) | length)' "$manifest_path" 2>/dev/null)" || item_count=0
    case "$item_count" in
      ''|*[!0-9]*) item_count=0 ;;
    esac
    if [ "$item_count" -ge "$min_count" ] 2>/dev/null; then
      satisfied=1
    fi
  done <<EOF
$entries
EOF

  if [ "$satisfied" -eq 1 ]; then
    printf '観測あり\t%s\n' "$labels"
  elif [ "$any_manifest_found" -eq 1 ]; then
    printf '対象なし\t%s\n' "$labels"
  else
    printf '未解析\t%s\n' "$labels"
  fi
}

# ツール側が本文を書いて納品する規約。既存テンプレートの本文（概要・規則表）を
# そのまま使い、front matterと見出しだけを規約定義の形式に合わせて差し替える。
# $5: uncheckable（rule-taxonomy.jsonの当該子カテゴリのuncheckableReason値）
# $7: scope（rule-taxonomy.jsonの当該子カテゴリの値）
# $8: paths（rule-taxonomy.jsonの当該子カテゴリのJSON配列。front matterへそのまま writes）
# $9: applies_state（resolve_applies_when_stateの状態。未解析/対象なし/観測あり。
#     appliesWhenを持たない子カテゴリは空文字を渡す）
# $10: applies_label（$9が対象なし/観測あり時に使う対象の名前）
# $11: checker（rule-taxonomy.jsonの当該子カテゴリのchecker値。宣言が無ければ空文字）
build_tooldefined_rule_md() {
  local key="$1" title="$2" parent="$3" summary="$4" uncheckable="$5" src_template="$6" scope="$7" paths="$8"
  local applies_state="${9:-}" applies_label="${10:-}" checker="${11:-}"
  local body
  # 1行目（テンプレート側の "# <旧見出し>"）を落とし、直後の空行だけを削る
  body="$(tail -n +2 "$src_template" | sed '/./,$!d')"

  # テンプレート内の <!-- uncheckableReason: ... --> 行から理由を取り出す。
  # 見つからなければ引数で渡された既定値をそのまま使う。
  local extracted_reason
  extracted_reason="$(printf '%s\n' "$body" | grep '<!-- uncheckableReason:' | head -n1 | sed -e 's/.*uncheckableReason:[[:space:]]*//' -e 's/[[:space:]]*-->.*//' || true)"
  if [ -n "$extracted_reason" ]; then
    uncheckable="$extracted_reason"
  fi
  # 本文からuncheckableReasonコメント行だけを取り除く（他のコメント行は残す）
  body="$(printf '%s\n' "$body" | sed '/<!-- uncheckableReason:/d')"

  # appliesWhenの判定結果に応じて、テンプレートの既定行を定義済みのプレースホルダ
  # へ必ず差し替える。対象なしだけはnotApplicable、他の状態はunanalysedを使う。
  local placeholder_key="unanalysed" placeholder_row unanalysed_label
  if [ "$applies_state" = "対象なし" ]; then
    placeholder_key="notApplicable"
  fi
  placeholder_row="$(project_rule_placeholder_row "$placeholder_key")" || return 1
  unanalysed_label="$(project_rule_placeholder_label unanalysed)" || return 1
  body="$(printf '%s\n' "$body" | awk -v repl="$placeholder_row" -v label="$unanalysed_label" '
    index($0, "| " label " |") == 1 { print repl; next }
    { print }
  ')"

  local enforcement="none" checkable="false" checker_out="null" uncheckable_out="${uncheckable}"
  if [ -n "$checker" ] && [ "$checker" != "null" ]; then
    enforcement="advisory"
    checkable="true"
    checker_out="${checker}"
    uncheckable_out="null"
  fi

  cat <<EOF
---
key: ${key}
title: ${title}
parent: ${parent}
summary: ${summary}
scope: ${scope}
paths: ${paths}
enforcement: ${enforcement}
checkable: ${checkable}
checker: ${checker_out}
uncheckableReason: ${uncheckable_out}
formatter: none
status: approved
origin: manual
---

# ${title}

EOF
  printf '%s\n' "$body"
}

TOOLDEFINED_UNCHECKABLE="定義と派生の対応関係はハッシュ台帳による突合で検知しており、この規約自体の遵守を静的解析で判定する仕組みを持たない。"

# 実装フローのゲートが必須とする
# .claude/rules/always/project-context/flow-values.yml の既定内容。
# 各キーの意味は本関数の直下に書く。
build_flow_values_yml() {
  cat <<'EOF'
# プロジェクト実装フロー設定。値はこのプロジェクトの実態に合わせて埋める。
domain_glossary: null  # 業務の用語をまとめた文書の場所
design_system: null  # 配色・書体・余白の定義の場所
test_conventions: null  # テストの書き方の取り決めの場所
adr_dir: null  # 設計判断の記録の置き場
design_docs: null  # 設計書の置き場
portal_dir: null  # 生成したポータルの置き場
review_gates: {}  # どの段階でレビューを挟むかの定義
review_agents: {}  # レビューを誰に任せるかの定義
pr: {}  # 変更依頼の作り方の定義
classify: {}  # 作業の種類を判別する条件
preflight: {}  # 着手前に確かめることの定義
EOF
}

# 同ゲートが前提とする .claude/rules/always/project-context/rule.md の既定雛形。
# ルート直下の実在ディレクトリを列挙し、用途欄は現場が後から記入する。
build_project_context_rule_md() {
  local out_root="$1" repo_name dir_rows d name
  repo_name="$(basename "$out_root")"
  dir_rows=""
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    name="$(basename "$d")"
    dir_rows="${dir_rows}| ${name} | （記入） |
"
  done < <(find "$out_root" -mindepth 1 -maxdepth 1 -type d ! -name '.*' 2>/dev/null | sort)

  cat <<EOF
# ${repo_name} プロジェクトコンテキスト（PROJECT-CONTEXT）

## 概要

（記入）このリポジトリの目的・役割を記入する。

## 技術スタック

（記入）

## 設定索引

- 実装フロー設定: \`.claude/rules/always/project-context/flow-values.yml\`

## ルート直下許可ディレクトリ

| ディレクトリ名 | 用途 |
|---|---|
EOF
  printf '%s' "$dir_rows"
}

# ---------------------------------------------------------------------------
# 生成本体
# ---------------------------------------------------------------------------

run_scaffold() {
  local out_root="$1"
  # $2（省略可）: 指定時はこの子カテゴリキー1件だけを作り直し、他の子カテゴリは
  # スキップする（build_tooldefined_rule_md・build_draft_rule_md・
  # merge_project_rule_sectionの呼び出しコストを1件分に抑える）。
  # 自己テストのうち「再実行のふるまい」だけを見るケース（既存の上書き保護・
  # 節単位マージ・プレースホルダ復元等）は元から1件のrule.mdしか検証しないため、
  # 残り26件を毎回作り直す必要がない（規約27件の全数生成が要るのは、基準となる
  # 1回目の生成と冪等性を見るケースの2回だけ）。省略時（空文字）は従来どおり
  # 全子カテゴリを処理する。
  local restrict_ckey="${2:-}"

  if [ ! -f "$TAXONOMY_JSON" ]; then
    echo "ERROR: taxonomy定義が見つかりません: ${TAXONOMY_JSON}" >&2
    return 1
  fi

  PLAN_LINES=""
  RULE_NEW=0; RULE_EXIST=0
  OTHER_NEW=0; OTHER_EXIST=0
  SKILL_NEW=0; SKILL_EXIST=0
  AGENT_NEW=0; AGENT_EXIST=0

  # appliesWhen判定用のoutput-layout解決は子カテゴリごとに繰り返さず、
  # このrun_scaffold呼び出しにつき1回だけ行う（node起動を伴う重い処理のため）。
  local scaffold_layout_json
  scaffold_layout_json="$(resolve_output_layout "$out_root" 2>/dev/null)" || scaffold_layout_json=""

  # 適用範囲（scope・paths）の対象側上書き（3.3）も同じ理由で1回だけ解決する。
  # out_root自体が未作成（--apply無しのdry-run初回呼び出し等）でも
  # resolve_rule_scope_overridesは宣言ファイル不在時にoverrides:{}を返すため落ちない。
  local scaffold_scope_overrides_json
  scaffold_scope_overrides_json="$(resolve_rule_scope_overrides "$out_root" 2>/dev/null)" || scaffold_scope_overrides_json='{"specVersion":1,"overrides":{}}'

  local parent_lines
  parent_lines="$(jq -c '.parents[]' "$TAXONOMY_JSON")"

  local pline
  while IFS= read -r pline; do
    [ -n "$pline" ] || continue
    local pkey ptitle
    pkey="$(printf '%s' "$pline" | jq -r '.key')"
    ptitle="$(printf '%s' "$pline" | jq -r '.title')"

    local parent_dir="${out_root}/docs/rules/${pkey}"
    local parent_yml_content
    parent_yml_content="$(build_parent_yml "$pkey" "$ptitle")"
    write_if_new "${parent_dir}/parent.yml" "$parent_yml_content" "other"

    local child_lines cline
    child_lines="$(printf '%s' "$pline" | jq -c '.children[]')"
    while IFS= read -r cline; do
      [ -n "$cline" ] || continue
      local ckey ctitle csummary ctool cscope cpaths cuncheckable cappliesWhen cchecker
      ckey="$(printf '%s' "$cline" | jq -r '.key')"
      if [ -n "$restrict_ckey" ] && [ "$ckey" != "$restrict_ckey" ]; then
        continue
      fi
      ctitle="$(printf '%s' "$cline" | jq -r '.title')"
      csummary="$(printf '%s' "$cline" | jq -r '.summary')"
      ctool="$(printf '%s' "$cline" | jq -r '.toolDefined')"
      cscope="$(printf '%s' "$cline" | jq -r '.scope')"
      cpaths="$(printf '%s' "$cline" | jq -c '.paths')"

      # 3.3: 対象側の宣言（docs/rules/rule-scope-overrides.json）に当該子カテゴリの
      # 上書きがあれば、taxonomyの既定値の代わりにそれを使う。宣言が無いキーは
      # taxonomyの既定値のまま（判定9: 宣言の無い子カテゴリは既定値を保つ）。
      # 毎回のrun_scaffold呼び出しで対象側ファイルを読み直すため、rule.mdの
      # front matterへ焼き込まれた値を保護するのではなく、再実行のたびに
      # 対象側の宣言から再計算する（判定8: 再実行で上書きが失われない）。
      local cscope_override
      if cscope_override="$(rule_scope_override_get "$scaffold_scope_overrides_json" "$ckey" scope 2>/dev/null)" && [ -n "$cscope_override" ]; then
        cscope="$cscope_override"
        cpaths="$(rule_scope_override_get "$scaffold_scope_overrides_json" "$ckey" paths 2>/dev/null)"
      fi

      cuncheckable="$(printf '%s' "$cline" | jq -r '.uncheckableReason // empty')"
      cappliesWhen="$(printf '%s' "$cline" | jq -c '.appliesWhen // empty')"
      cchecker="$(printf '%s' "$cline" | jq -r '.checker // empty')"

      local child_dir="${parent_dir}/${ckey}"
      local rule_content design_content

      if [ "$ctool" = "true" ]; then
        local src_template="${TOOLDEFINED_TEMPLATE_DIR}/${ckey}.md"
        if [ ! -f "$src_template" ]; then
          echo "ERROR: toolDefinedの本文テンプレートが見つかりません: ${ckey}" >&2
          return 1
        fi
        if [ "$cscope" = "null" ] || [ -z "$cscope" ] || [ "$cpaths" = "null" ]; then
          echo "ERROR: rule-taxonomy.jsonにscope/pathsが定義されていません: ${ckey}" >&2
          return 1
        fi
        # checker を宣言する子カテゴリは linter を持つため、検査できない理由を要求しない
        if [ -z "$cuncheckable" ] && { [ -z "$cchecker" ] || [ "$cchecker" = "null" ]; }; then
          echo "ERROR: rule-taxonomy.jsonにuncheckableReasonが定義されていません: ${ckey}" >&2
          return 1
        fi
        local applies_state="" applies_label=""
        if [ -n "$cappliesWhen" ]; then
          local state_reason
          state_reason="$(resolve_applies_when_state "$out_root" "$cappliesWhen" "$scaffold_layout_json")"
          applies_state="$(printf '%s' "$state_reason" | cut -f1)"
          applies_label="$(printf '%s' "$state_reason" | cut -f2)"
        fi
        rule_content="$(build_tooldefined_rule_md "$ckey" "$ctitle" "$pkey" "$csummary" "$cuncheckable" "$src_template" "$cscope" "$cpaths" "$applies_state" "$applies_label" "$cchecker")"
        rule_content="$(merge_project_rule_section "$rule_content" "${child_dir}/rule.md")"
      else
        rule_content="$(build_draft_rule_md "$ckey" "$ctitle" "$pkey" "$csummary" "$cscope" "$cpaths")"
      fi
      design_content="$(build_design_notes "$ctitle" "$ctool")"

      write_if_new "${child_dir}/rule.md" "$rule_content" "rule" "$ctool"
      write_if_new "${child_dir}/design-notes.md" "$design_content" "other"

      if [ -n "$cchecker" ] && [ "$cchecker" != "null" ]; then
        local checker_test="${cchecker%.sh}.test.sh"
        local checker_src="${CHECKERS_TEMPLATE_DIR}/${cchecker}"
        local checker_test_src="${CHECKERS_TEMPLATE_DIR}/${checker_test}"
        if [ ! -f "$checker_src" ] || [ ! -f "$checker_test_src" ]; then
          echo "ERROR: checkerテンプレートが見つかりません: ${cchecker}" >&2
          return 1
        fi
        copy_if_new "${child_dir}/${cchecker}" "$checker_src" "other"
        copy_if_new "${child_dir}/${checker_test}" "$checker_test_src" "other"
      fi
    done <<EOF
$child_lines
EOF
  done <<EOF
$parent_lines
EOF

  # 実装フローのゲートが必須とする2ファイル。既存なら上書きしない（write_if_new）。
  write_if_new "${out_root}/.claude/rules/always/project-context/flow-values.yml" "$(build_flow_values_yml)" "other"
  write_if_new "${out_root}/.claude/rules/always/project-context/rule.md" "$(build_project_context_rule_md "$out_root")" "other"

  if [ "$WITH_SKILLS" -eq 1 ]; then
    deliver_skills "$out_root" || return 1
    deliver_agent "$out_root" || return 1
    # maintaining-portal（deliver_skillsで配る納品スキルの1つ）が生成器の再実行を
    # 前提にするため、生成器一式の配布も --with-skills と同じ扱いにする
    # （--with-skills 無しの規約定義のみの配布では生成器一式は要らない）。
    if [ "$APPLY" -eq 1 ]; then
      plan_add "reverse-docs-engine/（generation-engine一式・deploy-generation-engine.shで配備）"
      bash "$DEPLOY_GENERATION_ENGINE_SCRIPT" "$out_root" --apply
    else
      plan_add "${out_root}/reverse-docs-engine/"
    fi
  fi

  if [ "$APPLY" -eq 1 ]; then
    plan_add "docs/rules/agent-operations/ai-config-asset-management/build-derived-rules.sh（--deploy-rule-scriptsで配備）"
    plan_add "docs/rules/agent-operations/ai-config-asset-management/validate-rule-definitions.sh（--deploy-rule-scriptsで配備）"
    bash "$BUILD_DERIVED_SCRIPT" --deploy-rule-scripts "$out_root"
  else
    plan_add "${out_root}/docs/rules/agent-operations/ai-config-asset-management/build-derived-rules.sh"
    plan_add "${out_root}/docs/rules/agent-operations/ai-config-asset-management/validate-rule-definitions.sh"
  fi

  if [ "$APPLY" -eq 1 ]; then
    echo "生成完了（--apply）:"
  else
    echo "DRY-RUN: 以下を生成予定（--apply未指定のため書き込みなし）:"
  fi
  printf '%s' "$PLAN_LINES"
  if [ "$APPLY" -eq 1 ]; then
    scan_banned_terms "${out_root}/docs/rules"
  fi
  echo "rule.md 新規: ${RULE_NEW} 件 / 既存(スキップ): ${RULE_EXIST} 件"
  echo "その他(parent.yml・design-notes.md) 新規: ${OTHER_NEW} 件 / 既存(スキップ): ${OTHER_EXIST} 件"
  if [ "$WITH_SKILLS" -eq 1 ]; then
    echo "SKILL.md 新規: ${SKILL_NEW} 件 / 既存(スキップ): ${SKILL_EXIST} 件"
    echo "rule-reviewer.md 新規: ${AGENT_NEW} 件 / 既存(スキップ): ${AGENT_EXIST} 件"
  fi
  return 0
}

# delivery-payload/references/delivered-skill-catalog.json の .skills[] だけを
# 唯一の情報源とし、対象名をスクリプトへ直接書かない。各スキルの各ファイルを
# 1段目（定義: <出力先>/<definitionRoot>/<name>/<file>）→
# 2段目（派生: <出力先>/<deriveRoot>/<name>/<file>）の順で deliver_skill_file へ渡す。
deliver_skills() {
  local out_root="$1"

  if [ ! -f "$SKILL_CATALOG_JSON" ]; then
    echo "ERROR: 納品スキルカタログが見つかりません: ${SKILL_CATALOG_JSON}" >&2
    return 1
  fi

  local definition_root derive_root
  definition_root="$(jq -r '.definitionRoot // empty' "$SKILL_CATALOG_JSON")"
  derive_root="$(jq -r '.deriveRoot // empty' "$SKILL_CATALOG_JSON")"
  if [ -z "$definition_root" ] || [ -z "$derive_root" ]; then
    echo "ERROR: 納品スキルカタログにdefinitionRoot/deriveRootが定義されていません: ${SKILL_CATALOG_JSON}" >&2
    return 1
  fi

  local skill_lines skill_count
  skill_lines="$(jq -c '.skills[]' "$SKILL_CATALOG_JSON" 2>/dev/null)" || skill_lines=""
  skill_count="$(printf '%s\n' "$skill_lines" | grep -c . || true)"
  if [ -z "$skill_lines" ] || [ "$skill_count" -eq 0 ]; then
    echo "ERROR: 納品スキルカタログに.skillsが定義されていません: ${SKILL_CATALOG_JSON}" >&2
    return 1
  fi

  local sline name file_lines file
  while IFS= read -r sline; do
    [ -n "$sline" ] || continue
    name="$(printf '%s' "$sline" | jq -r '.name')"
    file_lines="$(printf '%s' "$sline" | jq -r '.files[]')"
    while IFS= read -r file; do
      [ -n "$file" ] || continue
      deliver_skill_file "$out_root" "$name" "$file" "$definition_root" "$derive_root" || return 1
    done <<EOF
$file_lines
EOF
  done <<EOF
$skill_lines
EOF
  return 0
}

# 1本のスキルファイルを1段目（定義）・2段目（派生）の順で配る。
# $1: 出力先リポジトリルート  $2: スキル名  $3: カタログのfilesエントリ（相対パス）
# $4: カタログのdefinitionRoot  $5: カタログのderiveRoot
deliver_skill_file() {
  local out_root="$1" name="$2" file="$3" definition_root="$4" derive_root="$5"
  local src="${SKILLS_TEMPLATE_DIR}/${name}/${file}"
  if [ ! -f "$src" ]; then
    echo "ERROR: 納品スキルのテンプレートが見つかりません: ${src}" >&2
    return 1
  fi

  local def_dest="${out_root}/${definition_root}/${name}/${file}"
  local derived_dest="${out_root}/${derive_root}/${name}/${file}"

  # 1段目（定義）: 既存なら上書きしない（現場が書き込んだ内容を保護する）。
  if [ -e "$def_dest" ]; then
    SKILL_EXIST=$((SKILL_EXIST + 1))
  else
    SKILL_NEW=$((SKILL_NEW + 1))
    plan_add "$def_dest"
    if [ "$APPLY" -eq 1 ]; then
      mkdir -p "$(dirname "$def_dest")"
      cp "$src" "$def_dest"
    fi
  fi

  # 定義側はテンプレートの欠落ない複製でなければならない。既存ファイルを保護する
  # 場合も、古い版を残したまま派生側へ配らないよう、内容不一致を明示的に止める。
  if [ "$APPLY" -eq 1 ] && ! cmp -s "$src" "$def_dest"; then
    echo "ERROR: 納品スキルのテンプレートと定義側の内容が一致しません: ${src} ${def_dest}" >&2
    return 1
  fi

  # 2段目（派生）: 定義ファイルから複製する（派生物のため既存でも常に上書きする）。
  plan_add "$derived_dest"
  if [ "$APPLY" -eq 1 ]; then
    mkdir -p "$(dirname "$derived_dest")"
    case "$file" in
      *.md)
        # front matter は Claude Code のスキル発見に必須のため先頭を保つ。
        # front matter 直後に生成物notice commentを挟む
        # （build-derived-rules.shの.mdc生成と同じ配置規約）。
        local fm body
        fm="$(awk 'NR==1{print;next} /^---$/{print;exit} {print}' "$def_dest")"
        body="$(awk 'BEGIN{c=0} /^---$/{c++; next} c>=2{print}' "$def_dest")"
        {
          printf '%s\n' "$fm"
          printf '\n<!-- 生成物: %s/%s/%s から自動生成。直接編集しないこと -->\n' "$definition_root" "$name" "$file"
          printf '%s\n' "$body"
        } > "$derived_dest"
        ;;
      *)
        cp "$def_dest" "$derived_dest"
        chmod +x "$derived_dest" 2>/dev/null || true
        ;;
    esac
  fi
  return 0
}

# delivery-payload/templates/delivered-agents/rule-reviewer.md を
# <出力先>/.claude/agents/rule-reviewer.md へ複製する。deliver_skills と同じ
# 既存保護（write_if_new相当）・front matter直後の生成物notice comment挿入を行う。
deliver_agent() {
  local out_root="$1"
  local src="${AGENTS_TEMPLATE_DIR}/rule-reviewer.md"
  local dest="${out_root}/.claude/agents/rule-reviewer.md"
  if [ ! -f "$src" ]; then
    echo "ERROR: 納品レビュアーのテンプレートが見つかりません: ${src}" >&2
    return 1
  fi
  if [ -e "$dest" ]; then
    AGENT_EXIST=$((AGENT_EXIST + 1))
    return 0
  fi
  AGENT_NEW=$((AGENT_NEW + 1))
  plan_add "$dest"
  if [ "$APPLY" -eq 1 ]; then
    mkdir -p "$(dirname "$dest")"
    local fm body
    fm="$(awk 'NR==1{print;next} /^---$/{print;exit} {print}' "$src")"
    body="$(awk 'BEGIN{c=0} /^---$/{c++; next} c>=2{print}' "$src")"
    {
      printf '%s\n' "$fm"
      printf '\n<!-- 生成物: delivery-payload/templates/delivered-agents/rule-reviewer.md から複製。直接編集しないこと -->\n'
      printf '%s\n' "$body"
    } > "$dest"
  fi
  return 0
}

# 生成物（rule.md・rule.html）を禁止語一覧（delivery-payload/references/rule-banned-terms.json）
# で走査し、該当があれば標準出力へ報告する。報告のみで生成は中断しない
# （既存の他検査と同じ方針）。$1: 走査対象ディレクトリ（docs/rules 等）
# 戻り値は常に0。呼び出し側は出力を読んで対応を判断する。
#
# 除外（規則を定義する文書）: 一部の規則は、その規則自身が「禁止語を書かない」
# ことを定義しており、本文に禁止語を例示として含む（例:
# documentation-standards/document-writing）。この自己言及は term_file の
# exemptions（parent/key で指定）に一覧を持たせ、本スクリプトへは直書きしない
# （文体の検査における常体除外と同じ設計。除外の対象はrule-banned-terms.json
# の定義側が正であり、除外した件数を必ず報告する）。除外は指定した子カテゴリ
# の rule.md・rule.html への一致に限り、それ以外の文書は従来どおり対象とする。
scan_banned_terms() {
  local target_dir="$1"
  local term_file="${2:-$BANNED_TERMS_JSON}"
  if [ ! -d "$target_dir" ] || [ ! -f "$term_file" ]; then
    return 0
  fi

  # 明示テンプレート付きmktemp（"${TMPDIR:-/tmp}/<name>.XXXXXX"）を使う。裸のmktempは
  # ${TMPDIRを無視し書き込み許可の外にある既定領域を使うため}、サンドボックス実行環境では
  # 失敗する（改善課題「一時ディレクトリ-作成先」。手元の環境で動いても裸の形へ戻すな）。
  local patterns_file
  patterns_file="$(mktemp "${TMPDIR:-/tmp}/rule-banned-terms.XXXXXX")"
  jq -r '.terms[] | select(.scope | index("rule-definitions")) | .term' "$term_file" >"$patterns_file" 2>/dev/null || true
  if [ ! -s "$patterns_file" ]; then
    rm -f "$patterns_file"
    return 0
  fi

  local matches hit_count
  # -f patterns_file + -F で7語 × 全対象ファイルを1回のgrep呼び出しで走査する
  # （ファイル数×語数ぶんループすると自己テスト全体が数分規模に膨らむため）。
  matches="$(find "$target_dir" \( -name 'rule.md' -o -name 'rule.html' \) -type f -print0 2>/dev/null \
    | xargs -0 grep -n -F -f "$patterns_file" 2>/dev/null || true)"
  rm -f "$patterns_file"

  local excluded_count=0
  if [ -n "$matches" ]; then
    # exemptions（parent/key）を "<parent>/<key>/" の形へ変換し、matches の
    # 行（"<path>:<lineno>:<content>"）のうちパスにこの断片を含むものだけを除外する。
    local exempt_file
    exempt_file="$(mktemp "${TMPDIR:-/tmp}/rule-banned-terms-exempt.XXXXXX")"
    jq -r --arg scope "rule-definitions" \
      '(.exemptions // [])[] | select(.scope == $scope) | "\(.parent)/\(.key)/"' \
      "$term_file" >"$exempt_file" 2>/dev/null || true

    if [ -s "$exempt_file" ]; then
      local filtered_matches line is_exempt pat
      filtered_matches=""
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        is_exempt=0
        while IFS= read -r pat; do
          [ -n "$pat" ] || continue
          case "$line" in
            *"/${pat}"*) is_exempt=1; break ;;
          esac
        done <"$exempt_file"
        if [ "$is_exempt" -eq 1 ]; then
          excluded_count=$((excluded_count + 1))
        else
          filtered_matches="${filtered_matches}${line}"$'\n'
        fi
      done <<EOF
$matches
EOF
      matches="${filtered_matches%$'\n'}"
    fi
    rm -f "$exempt_file"
  fi

  if [ -z "$matches" ]; then
    echo "禁止語検査: 0件（除外 ${excluded_count}件）"
    return 0
  fi
  hit_count="$(printf '%s\n' "$matches" | grep -c .)"
  echo "禁止語検査: ${hit_count}件（除外 ${excluded_count}件）"
  printf '%s\n' "$matches" | sed 's/^/  /'
  return 0
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

self_test() {
  local rc=0
  local out1 out2
  local scaffold_out scaffold_rc

  capture_scaffold() {
    local captured
    if [ -n "${SELF_TEST_FORCE_SCAFFOLD_FAILURE:-}" ]; then
      captured="$SELF_TEST_FORCE_SCAFFOLD_FAILURE"
      scaffold_rc=97
    elif captured="$(run_scaffold "$@" 2>&1)"; then
      scaffold_rc=0
    else
      scaffold_rc=$?
    fi
    scaffold_out="$captured"
  }

  print_scaffold_failure() {
    printf '    run_scaffold exit=%s\n' "$scaffold_rc" >&2
    if [ -n "$scaffold_out" ]; then
      printf '%s\n' "$scaffold_out" | awk '{ print "    " $0 }' >&2
    fi
  }

  # ケース1: --apply なしでは書き込みが起きない
  out1="$(mktemp -d "${TMPDIR:-/tmp}/scaffold-rule-definitions-self-test-out1.XXXXXX")"
  rm -rf "$out1"
  APPLY=0
  WITH_SKILLS=0
  capture_scaffold "$out1"
  if [ "$scaffold_rc" -ne 0 ]; then
    echo "  [FAIL] ケース1: --apply なしの実行自体が失敗した" >&2
    print_scaffold_failure
    rc=1
  elif [ -d "$out1" ]; then
    echo "  [FAIL] ケース1: --apply なしで出力先ディレクトリが作成された" >&2
    print_scaffold_failure
    rc=1
  else
    echo "  [PASS] ケース1: --apply なしでは書き込みが起きない"
  fi

  # 以降は --apply --with-skills で実データを生成して検証する
  out1="$(mktemp -d "${TMPDIR:-/tmp}/scaffold-rule-definitions-self-test-out1.XXXXXX")"
  APPLY=1
  WITH_SKILLS=1
  local run1_log
  run1_log="$(mktemp "${TMPDIR:-/tmp}/scaffold-rule-definitions-bst-run1.XXXXXX")"
  run_scaffold "$out1" >"$run1_log" 2>&1
  local rc1=$?
  if [ "$rc1" -ne 0 ]; then
    echo "  [FAIL] 1回目の --apply 実行が失敗した (rc=$rc1)" >&2
    sed 's/^/    /' "$run1_log" >&2
    rc=1
  fi
  rm -f "$run1_log"

  # ケース2: 親7フォルダ・子27フォルダが作られる
  local parent_count child_count
  parent_count="$(find "${out1}/docs/rules" -mindepth 1 -maxdepth 1 -type d ! -name tooling 2>/dev/null | grep -c . || true)"
  child_count="$(find "${out1}/docs/rules" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | grep -c . || true)"
  if [ "$parent_count" -eq 7 ] && [ "$child_count" -eq 27 ]; then
    echo "  [PASS] ケース2: 親7フォルダ・子27フォルダが作られる"
  else
    echo "  [FAIL] ケース2: 親${parent_count}件・子${child_count}件（期待: 親7・子27）" >&2
    rc=1
  fi

  # ケース3: rule.mdが27件でき、front matterが13鍵であること
  local rule_files rule_count ok3
  rule_files="$(find "${out1}/docs/rules" -type f -name 'rule.md' | sort)"
  rule_count="$(printf '%s\n' "$rule_files" | grep -c . || true)"
  ok3=1
  [ "$rule_count" -eq 27 ] || ok3=0
  local rf
  while IFS= read -r rf; do
    [ -n "$rf" ] || continue
    local fm_body key_count
    fm_body="$(fm_extract "$rf" || true)"
    key_count="$(fm_all_key_lines "$fm_body" | sort -u | grep -c . || true)"
    [ "$key_count" -eq 13 ] || ok3=0
  done <<EOF
$rule_files
EOF
  if [ "$ok3" -eq 1 ]; then
    echo "  [PASS] ケース3: rule.mdが27件でき、front matterが13鍵である"
  else
    echo "  [FAIL] ケース3: rule.md件数またはfront matter鍵数が不正（件数=${rule_count}）" >&2
    rc=1
  fi

  # ケース4: toolDefinedの子カテゴリがstatus:approvedで本文入り、残りがstatus:draftで（未記入）を含む
  local ok4=1 approved_count=0 draft_count=0
  while IFS= read -r rf; do
    [ -n "$rf" ] || continue
    local fm_body v_status
    fm_body="$(fm_extract "$rf" || true)"
    v_status="$(fm_get_scalar "$fm_body" status)"
    if [ "$v_status" = "approved" ]; then
      approved_count=$((approved_count + 1))
      grep -q '（未記入）' "$rf" && ok4=0
    elif [ "$v_status" = "draft" ]; then
      draft_count=$((draft_count + 1))
      grep -q '（未記入）' "$rf" || ok4=0
    else
      ok4=0
    fi
  done <<EOF
$rule_files
EOF
  local expected_approved expected_draft total_children
  expected_approved="$(jq '[.parents[].children[] | select(.toolDefined == true)] | length' "$TAXONOMY_JSON")"
  total_children="$(jq '[.parents[].children[]] | length' "$TAXONOMY_JSON")"
  expected_draft=$((total_children - expected_approved))
  [ "$approved_count" -eq "$expected_approved" ] || ok4=0
  [ "$draft_count" -eq "$expected_draft" ] || ok4=0
  if [ "$ok4" -eq 1 ]; then
    echo "  [PASS] ケース4: approved ${expected_approved}件（本文入り・未記入なし）、draft ${expected_draft}件（未記入あり）"
  else
    echo "  [FAIL] ケース4: approved=${approved_count}件 draft=${draft_count}件（期待: ${expected_approved}件/${expected_draft}件）" >&2
    rc=1
  fi

  # ケース5: 生成した定義がvalidate-rule-definitions.shの検査を通る
  local validate_out
  validate_out="$(mktemp "${TMPDIR:-/tmp}/scaffold-rule-definitions-bst-validate.XXXXXX")"
  if run_validate "${out1}/docs/rules" >"$validate_out" 2>&1; then
    echo "  [PASS] ケース5: 生成した定義がvalidate-rule-definitions.shの検査を通る"
  else
    echo "  [FAIL] ケース5: validate-rule-definitions.shが不合格" >&2
    sed 's/^/    /' "$validate_out" >&2
    rc=1
  fi
  rm -f "$validate_out"

  # ケース6: --with-skillsでカタログ（delivered-skill-catalog.json）の全スキルの全ファイルが
  #   1段目（定義: docs/skills/）と2段目（派生: .claude/skills/）の両方へ配られ、
  #   派生側の.mdはfront matterを保ったまま生成物notice commentを持つ
  local ok6=1 skill6_lines sline6 name6 files6 file6 def6 der6
  skill6_lines="$(jq -c '.skills[]' "$SKILL_CATALOG_JSON")"
  while IFS= read -r sline6; do
    [ -n "$sline6" ] || continue
    name6="$(printf '%s' "$sline6" | jq -r '.name')"
    files6="$(printf '%s' "$sline6" | jq -r '.files[]')"
    while IFS= read -r file6; do
      [ -n "$file6" ] || continue
      def6="${out1}/docs/skills/${name6}/${file6}"
      der6="${out1}/.claude/skills/${name6}/${file6}"
      if [ ! -f "$def6" ]; then
        ok6=0
        echo "  [FAIL] ケース6詳細: 定義 ${def6} が無い" >&2
      fi
      if [ ! -f "$der6" ]; then
        ok6=0
        echo "  [FAIL] ケース6詳細: 派生 ${der6} が無い" >&2
      elif [ "$file6" != "${file6%.md}" ]; then
        head -n1 "$der6" | grep -qx -- '---' || { ok6=0; echo "  [FAIL] ケース6詳細: ${der6} の先頭がfront matterでない" >&2; }
        grep -q '<!-- 生成物:.*から自動生成。直接編集しないこと -->' "$der6" || { ok6=0; echo "  [FAIL] ケース6詳細: ${der6} に生成物notice commentが無い" >&2; }
      fi
    done <<EOF
$files6
EOF
  done <<EOF
$skill6_lines
EOF
  if [ "$ok6" -eq 1 ]; then
    echo "  [PASS] ケース6: --with-skillsでカタログの全スキルが定義(docs/skills/)と派生(.claude/skills/)の両方へ配られ、派生側のfront matterと生成物notice commentが正しい"
  else
    echo "  [FAIL] ケース6: 納品スキルの配備が不正" >&2
    rc=1
  fi

  # ケース6a: 配布後にひな形を1行変えた場合、既存の定義側との不一致を検出する
  local mismatch_src mismatch_backup mismatch_log mismatch_rc
  mismatch_src="${SKILLS_TEMPLATE_DIR}/dev-flow/SKILL.md"
  mismatch_backup="$(mktemp "${TMPDIR:-/tmp}/scaffold-rule-definitions-skill-backup.XXXXXX")"
  mismatch_log="$(mktemp "${TMPDIR:-/tmp}/scaffold-rule-definitions-skill-mismatch.XXXXXX")"
  cp "$mismatch_src" "$mismatch_backup"
  printf '\n<!-- self-test mismatch -->\n' >> "$mismatch_src"
  if run_scaffold "$out1" >"$mismatch_log" 2>&1; then
    mismatch_rc=0
  else
    mismatch_rc=$?
  fi
  cp "$mismatch_backup" "$mismatch_src"
  rm -f "$mismatch_backup"
  if [ "$mismatch_rc" -ne 0 ] && grep -q 'テンプレートと定義側の内容が一致しません' "$mismatch_log"; then
    echo "  [PASS] ケース6a: ひな形変更後の再配布が内容不一致を検出して非0で終了する"
  else
    echo "  [FAIL] ケース6a: ひな形変更後の内容不一致を検出できない (rc=$mismatch_rc)" >&2
    cat "$mismatch_log" >&2
    rc=1
  fi
  rm -f "$mismatch_log"

  # ケース6b: --with-skillsで.claude/agents/rule-reviewer.mdも配られる
  local ok6b=1
  if [ -f "${out1}/.claude/agents/rule-reviewer.md" ]; then
    head -n1 "${out1}/.claude/agents/rule-reviewer.md" | grep -qx -- '---' || ok6b=0
  else
    ok6b=0
  fi
  if [ "$ok6b" -eq 1 ]; then
    echo "  [PASS] ケース6b: --with-skillsで.claude/agents/rule-reviewer.mdが配られ、front matterが先頭にある"
  else
    echo "  [FAIL] ケース6b: 納品レビュアーの配備が不正" >&2
    rc=1
  fi

  # ケース7: docs/rules/agent-operations/ai-config-asset-management/の3本が配られ実行できる
  local ok7=1
  local deployed_dir7="${out1}/docs/rules/agent-operations/ai-config-asset-management"
  [ -x "${deployed_dir7}/build-derived-rules.sh" ] || ok7=0
  [ -x "${deployed_dir7}/validate-rule-definitions.sh" ] || ok7=0
  [ -x "${deployed_dir7}/resolve-applicable-rules.sh" ] || ok7=0
  local _gt_ok7_validate_out="" _gt_ok7_resolve_out=""
  if [ "$ok7" -eq 1 ]; then
    _gt_ok7_validate_out="$(bash "${deployed_dir7}/validate-rule-definitions.sh" "${out1}/docs/rules" 2>&1)" || ok7=0
  fi
  if [ "$ok7" -eq 1 ]; then
    _gt_ok7_resolve_out="$(bash "${deployed_dir7}/resolve-applicable-rules.sh" --self-test 2>&1)" || ok7=0
  fi
  if [ "$ok7" -eq 1 ]; then
    echo "  [PASS] ケース7: docs/rules/agent-operations/ai-config-asset-management/の3本が配られ、実行できる"
  else
    echo "  [FAIL] ケース7: docs/rules/agent-operations/ai-config-asset-management/の配備または実行が不正" >&2
    printf '%s\n%s\n' "$_gt_ok7_validate_out" "$_gt_ok7_resolve_out" | sed 's/^/    /' >&2
    rc=1
  fi

  # ケース8: 2回実行しても既存が壊れない（冪等性）
  out2="$(mktemp -d "${TMPDIR:-/tmp}/scaffold-rule-definitions-self-test-out2.XXXXXX")"
  rm -rf "$out2"
  cp -R "$out1" "$out2"
  APPLY=1
  WITH_SKILLS=1
  capture_scaffold "$out1"
  local diff_log
  diff_log="$(mktemp "${TMPDIR:-/tmp}/scaffold-rule-definitions-bst-diff.XXXXXX")"
  if [ "$scaffold_rc" -ne 0 ]; then
    echo "  [FAIL] ケース8: 冪等性確認の再実行自体が失敗した" >&2
    print_scaffold_failure
    rc=1
  elif diff -r "${out2}/docs/rules" "${out1}/docs/rules" >"$diff_log" 2>&1; then
    echo "  [PASS] ケース8: 2回実行しても既存の docs/rules が壊れない（冪等）"
  else
    echo "  [FAIL] ケース8: 再実行で既存の docs/rules が変化した" >&2
    print_scaffold_failure
    sed 's/^/    /' "$diff_log" >&2
    rc=1
  fi
  rm -f "$diff_log"

  # ケース9: enforcement の値ごとに「## 違反時の手順」節の有無が
  #   テンプレート・生成スクリプト出力・generation-engine/samples/docs/rules の三者で
  #   設計（規約定義と派生生成の設計.md 3節）どおりに揃っている（節構成の
  #   三者乖離の再発防止。改善課題1-3）
  local ok9=1

  # 9a. テンプレート: advisory時の雛形として「違反時の手順」節と、
  #     enforcement: none に変えた場合の削除注記を両方持つ（Option A）
  local template_file="${REPO_ROOT}/delivery-payload/templates/rules/rule-template.md"
  if [ ! -f "$template_file" ]; then
    echo "  [FAIL] ケース9a: テンプレートが見つからない: ${template_file}" >&2
    ok9=0
  else
    if ! grep -q '^## 違反時の手順$' "$template_file"; then
      echo "  [FAIL] ケース9a: テンプレートに『## 違反時の手順』節が無い" >&2
      ok9=0
    fi
    if ! grep -q 'enforcement: none に変えるならこの節ごと削除する' "$template_file"; then
      echo "  [FAIL] ケース9a: テンプレートに enforcement: none 時の削除注記が無い" >&2
      ok9=0
    fi
  fi

  # 9b. 生成スクリプト出力: enforcement の値と「違反時の手順」節の有無が対応する。
  #     none は節を持たず、advisory は節を持つ（設計 4 節が定める条件）。
  #     checker を宣言する子カテゴリだけが advisory になる。
  local gen_leak=0 gen_miss=0 rf9
  while IFS= read -r rf9; do
    [ -n "$rf9" ] || continue
    local fm9 v_enf9 has9
    fm9="$(fm_extract "$rf9" || true)"
    v_enf9="$(fm_get_scalar "$fm9" enforcement)"
    has9=0
    grep -q '^## 違反時の手順$' "$rf9" && has9=1
    if [ "$v_enf9" = "none" ] && [ "$has9" -eq 1 ]; then
      gen_leak=$((gen_leak + 1))
    fi
    if [ "$v_enf9" = "advisory" ] && [ "$has9" -eq 0 ]; then
      gen_miss=$((gen_miss + 1))
    fi
  done <<EOF
$rule_files
EOF
  if [ "$gen_leak" -ne 0 ]; then
    echo "  [FAIL] ケース9b: enforcement: none の rule.md に『違反時の手順』節が ${gen_leak} 件混入" >&2
    ok9=0
  fi
  if [ "$gen_miss" -ne 0 ]; then
    echo "  [FAIL] ケース9b: enforcement: advisory の rule.md に『違反時の手順』節が無いものが ${gen_miss} 件" >&2
    ok9=0
  fi

  # 9c. サンプル: generation-engine/samples/docs/rules 配下の全rule.mdで、enforcement の値と
  #     「違反時の手順」節の有無が一致する
  local sample_files sf9 sf9_enf sf9_has
  sample_files="$(find "${REPO_ROOT}/generation-engine/samples/docs/rules" -type f -name 'rule.md' 2>/dev/null | sort)"
  while IFS= read -r sf9; do
    [ -n "$sf9" ] || continue
    sf9_enf="$(sed -n 's/^enforcement: //p' "$sf9" | head -1)"
    sf9_has=0
    grep -q '^## 違反時の手順$' "$sf9" && sf9_has=1
    if [ "$sf9_enf" = "none" ] && [ "$sf9_has" -eq 1 ]; then
      echo "  [FAIL] ケース9c: ${sf9} は enforcement: none だが『違反時の手順』節がある" >&2
      ok9=0
    fi
    if [ "$sf9_enf" = "advisory" ] && [ "$sf9_has" -eq 0 ]; then
      echo "  [FAIL] ケース9c: ${sf9} は enforcement: advisory だが『違反時の手順』節が無い" >&2
      ok9=0
    fi
  done <<EOF
$sample_files
EOF

  if [ "$ok9" -eq 1 ]; then
    echo "  [PASS] ケース9: enforcement の値ごとに『違反時の手順』節の有無がテンプレート・生成出力・サンプルで一致する"
  else
    rc=1
  fi

  # ケース10: project-context/rule.md・flow-values.yml が生成され、既存を上書きしない
  local ok10=1
  local pc_rule="${out1}/.claude/rules/always/project-context/rule.md"
  local flow_yml="${out1}/.claude/rules/always/project-context/flow-values.yml"
  [ -f "$pc_rule" ] || ok10=0
  [ -f "$flow_yml" ] || ok10=0
  if [ "$ok10" -eq 1 ]; then
    grep -qE '^domain_glossary: null( |$)' "$flow_yml" || ok10=0
    grep -q 'ルート直下許可ディレクトリ' "$pc_rule" || ok10=0
  fi
  if [ "$ok10" -eq 1 ]; then
    # 現場が書き込んだ内容を装い、再実行しても上書きされないことを確認する
    printf '# 現場編集済み\n' > "$pc_rule"
    APPLY=1
    WITH_SKILLS=1
    # このケースが見るのはproject-context/rule.md・flow-values.ymlだけであり、
    # 27件の子カテゴリのどれとも無関係なため、実在しないキーを渡して0件に絞る。
    capture_scaffold "$out1" "__case10_no_child__"
    if [ "$scaffold_rc" -ne 0 ]; then
      ok10=0
    else
      grep -q '^# 現場編集済み$' "$pc_rule" || ok10=0
    fi
  fi
  if [ "$ok10" -eq 1 ]; then
    echo "  [PASS] ケース10: project-context/rule.md・flow-values.yml が生成され、既存を上書きしない"
  else
    echo "  [FAIL] ケース10: project-context/rule.md・flow-values.yml の生成または既存保護が不正" >&2
    print_scaffold_failure
    rc=1
  fi

  # ケース19（判定8・3.3）: 対象側の宣言（docs/rules/rule-scope-overrides.json）で
  #   適用範囲（scope・paths）を上書きでき、その上書きが再実行（複数回）で失われないこと。
  local ok19=1
  local override_key19="naming"
  mkdir -p "${out1}/docs/rules"
  cat > "${out1}/docs/rules/rule-scope-overrides.json" <<'EOF'
{
  "specVersion": 1,
  "overrides": {
    "naming": { "scope": "scoped", "paths": ["apps/custom-app/src/**"] }
  }
}
EOF
  APPLY=1
  WITH_SKILLS=1
  # このケースが見るのはoverride_key19（naming）1件だけであり、他の26件を
  # 作り直す必要はない。
  capture_scaffold "$out1" "$override_key19"
  local rule19
  rule19="$(find "${out1}/docs/rules" -type d -name "$override_key19" | head -n1)/rule.md"
  if [ "$scaffold_rc" -ne 0 ]; then
    ok19=0
    echo "  [FAIL] ケース19: 1回目の再実行自体が失敗した" >&2
    print_scaffold_failure
  elif ! grep -qF 'paths: ["apps/custom-app/src/**"]' "$rule19" || ! grep -q '^scope: scoped$' "$rule19"; then
    ok19=0
    echo "  [FAIL] ケース19: 1回目の再実行で対象側の上書きが反映されない" >&2
    print_scaffold_failure
  else
    # もう一度再実行しても失われないこと（判定8の核心: 再実行で失われない）
    capture_scaffold "$out1" "$override_key19"
    if [ "$scaffold_rc" -ne 0 ]; then
      ok19=0
      echo "  [FAIL] ケース19: 2回目の再実行自体が失敗した" >&2
      print_scaffold_failure
    elif ! grep -qF 'paths: ["apps/custom-app/src/**"]' "$rule19" || ! grep -q '^scope: scoped$' "$rule19"; then
      ok19=0
      echo "  [FAIL] ケース19: 2回目の再実行で対象側の上書きが失われた" >&2
      print_scaffold_failure
    fi
  fi
  if [ "$ok19" -eq 1 ]; then
    echo "  [PASS] ケース19: 対象側の宣言による適用範囲の上書きが複数回の再実行でも失われない"
  else
    rc=1
  fi

  # ケース20（判定9・3.3）: rule-scope-overrides.json に宣言の無い子カテゴリは、
  #   taxonomyの既定値（scope・paths）を保つ（上書き対象key以外へ波及しない）。
  local ok20=1
  local other_key20="ai-behavior"
  local expected_scope20 expected_paths20
  expected_scope20="$(jq -r --arg k "$other_key20" '.parents[].children[] | select(.key==$k) | .scope' "$TAXONOMY_JSON")"
  expected_paths20="$(jq -c --arg k "$other_key20" '.parents[].children[] | select(.key==$k) | .paths' "$TAXONOMY_JSON")"
  local rule20
  rule20="$(find "${out1}/docs/rules" -type d -name "$other_key20" | head -n1)/rule.md"
  if ! grep -q "^scope: ${expected_scope20}\$" "$rule20"; then
    ok20=0
    echo "  [FAIL] ケース20: 宣言の無いキー(${other_key20})のscopeがtaxonomy既定値と一致しない" >&2
  fi
  if ! grep -qF "paths: ${expected_paths20}" "$rule20"; then
    ok20=0
    echo "  [FAIL] ケース20: 宣言の無いキー(${other_key20})のpathsがtaxonomy既定値と一致しない" >&2
  fi
  if [ "$ok20" -eq 1 ]; then
    echo "  [PASS] ケース20: 宣言の無い子カテゴリはtaxonomyの既定値（scope・paths）を保つ"
  else
    rc=1
  fi
  rm -f "${out1}/docs/rules/rule-scope-overrides.json"

  # ケース15（改善課題1-48 4回目の指摘）: 空の雛形を先に置いてから --apply を実行すると、
  #   宣言（toolDefined）がツール側の規約は既存でもスキップされず上書きされること
  local ok15=1
  local pkey15 ckey15
  pkey15="$(jq -r '.parents[] | .key as $p | .children[] | select(.toolDefined == true) | $p' "$TAXONOMY_JSON" | head -n1)"
  ckey15="$(jq -r '.parents[] | .children[] | select(.toolDefined == true) | .key' "$TAXONOMY_JSON" | head -n1)"
  if [ -z "$pkey15" ] || [ -z "$ckey15" ]; then
    ok15=0
    echo "  [FAIL] ケース15: taxonomyにtoolDefined=trueの子カテゴリが見つからない" >&2
  else
    local rule15="${out1}/docs/rules/${pkey15}/${ckey15}/rule.md"
    [ -f "$rule15" ] || { ok15=0; echo "  [FAIL] ケース15: 検査対象 ${rule15} が存在しない" >&2; }
    if [ "$ok15" -eq 1 ]; then
      # 現場が空の雛形を置いた状態を装う
      : > "$rule15"
      APPLY=1
      WITH_SKILLS=1
      # このケースが見るのはckey15 1件だけであり、他の26件を作り直す必要はない。
      capture_scaffold "$out1" "$ckey15"
      if [ "$scaffold_rc" -ne 0 ]; then
        ok15=0
        echo "  [FAIL] ケース15: 再実行自体が失敗した" >&2
        print_scaffold_failure
      elif [ ! -s "$rule15" ]; then
        ok15=0
        echo "  [FAIL] ケース15: 空の雛形が再実行後も空のままである（上書きされていない）" >&2
        print_scaffold_failure
      elif ! grep -q "^key: ${ckey15}\$" "$rule15"; then
        ok15=0
        echo "  [FAIL] ケース15: 再実行後の本文がツール側テンプレート由来でない" >&2
        print_scaffold_failure
      fi
    fi
  fi
  if [ "$ok15" -eq 1 ]; then
    echo "  [PASS] ケース15: 空の雛形を先に置いてもtoolDefinedの規約は再実行で上書きされる"
  else
    rc=1
  fi

  # ケース16（判定1・3.1）: 現場が「このプロジェクトの規則」節へリバース解析の観測から
  #   規則を書き足した場合、その内容は配置の再実行で失われない（節単位の上書き）。
  local ok16=1
  if [ -z "$pkey15" ] || [ -z "$ckey15" ]; then
    ok16=0
    echo "  [FAIL] ケース16: taxonomyにtoolDefined=trueの子カテゴリが見つからない" >&2
  else
    local rule16="${out1}/docs/rules/${pkey15}/${ckey15}/rule.md"
    if [ ! -f "$rule16" ]; then
      ok16=0
      echo "  [FAIL] ケース16: 検査対象 ${rule16} が存在しない" >&2
    else
      local start16 end16
      start16="$(grep -n '^## このプロジェクトの規則$' "$rule16" | head -n1 | cut -d: -f1)"
      end16="$(awk -v s="$start16" 'NR>s && /^## /{print NR; exit}' "$rule16")"
      [ -n "$end16" ] || end16=$(($(wc -l < "$rule16") + 1))
      {
        head -n "$start16" "$rule16"
        echo
        echo '<!-- リバース解析が対象リポジトリの観測から起こした規則を置く。 -->'
        echo
        echo '| 規則 | 内容 | 根拠 | 検査 |'
        echo '|---|---|---|---|'
        echo '| 現場観測ルール16 | 現場が観測した実際の規則 | 現場のコード | レビュー: 現場が目視で確認する |'
        echo
        tail -n +"$end16" "$rule16"
      } > "${rule16}.tmp16"
      mv "${rule16}.tmp16" "$rule16"
      if ! grep -q '現場観測ルール16' "$rule16"; then
        ok16=0
        echo "  [FAIL] ケース16: 現場内容の差し替え自体に失敗した（テスト前提が崩れている）" >&2
      else
        APPLY=1
        WITH_SKILLS=1
        # このケースが見るのはckey15（=rule16の対象キー）1件だけであり、
        # 他の26件を作り直す必要はない。
        capture_scaffold "$out1" "$ckey15"
        if [ "$scaffold_rc" -ne 0 ]; then
          ok16=0
          echo "  [FAIL] ケース16: 再実行自体が失敗した" >&2
          print_scaffold_failure
        elif ! grep -q '現場観測ルール16' "$rule16"; then
          ok16=0
          echo "  [FAIL] ケース16: 再実行で現場が書き込んだ規則が消えた" >&2
          print_scaffold_failure
        fi
      fi
    fi
  fi
  if [ "$ok16" -eq 1 ]; then
    echo "  [PASS] ケース16: 現場が『このプロジェクトの規則』節へ書き込んだ内容は再実行で失われない"
  else
    rc=1
  fi

  # ケース17（判定2・3.1）: プレースホルダ行（ラベルが 未解析／対象なし／（未記入）のいずれか）は、
  #   行の説明文だけが書き換わっていても再実行で雛形の本文へ上書きされる（ケース16とは別カテゴリで検証する）。
  local ok17=1
  local pkey17 ckey17
  pkey17="$(jq -r '.parents[] | .key as $p | .children[] | select(.toolDefined == true) | $p' "$TAXONOMY_JSON" | sed -n '2p')"
  ckey17="$(jq -r '.parents[] | .children[] | select(.toolDefined == true) | .key' "$TAXONOMY_JSON" | sed -n '2p')"
  if [ -z "$pkey17" ] || [ -z "$ckey17" ]; then
    ok17=0
    echo "  [FAIL] ケース17: taxonomyにtoolDefined=trueの子カテゴリが2件見つからない" >&2
  else
    local rule17="${out1}/docs/rules/${pkey17}/${ckey17}/rule.md"
    if [ ! -f "$rule17" ]; then
      ok17=0
      echo "  [FAIL] ケース17: 検査対象 ${rule17} が存在しない" >&2
    else
      local orig_row17
      orig_row17="$(grep -E '^\| 未解析 \|' "$rule17" | head -n1 || true)"
      if [ -z "$orig_row17" ]; then
        ok17=0
        echo "  [FAIL] ケース17: 検査対象に『未解析』プレースホルダ行が無い（前提が崩れている）" >&2
      else
        # 説明文だけを書き換える（ラベルは 未解析 のまま保つ）
        local touched_row17='| 未解析 | 現場が説明文だけ書き換えた状態を装う（ラベルはプレースホルダのまま） | ダミー | ダミー |'
        local escaped_orig17
        escaped_orig17="$(printf '%s' "$orig_row17" | sed 's/[&/\]/\\&/g')"
        local escaped_new17
        escaped_new17="$(printf '%s' "$touched_row17" | sed 's/[&/\]/\\&/g')"
        sed "s/${escaped_orig17}/${escaped_new17}/" "$rule17" > "$rule17.tmp" && mv "$rule17.tmp" "$rule17"
        if ! grep -qF '現場が説明文だけ書き換えた状態を装う' "$rule17"; then
          ok17=0
          echo "  [FAIL] ケース17: 行の差し替え自体に失敗した（テスト前提が崩れている）" >&2
        else
          APPLY=1
          WITH_SKILLS=1
          # このケースが見るのはckey17 1件だけであり、他の26件を作り直す必要はない。
          capture_scaffold "$out1" "$ckey17"
          if [ "$scaffold_rc" -ne 0 ]; then
            ok17=0
            echo "  [FAIL] ケース17: 再実行自体が失敗した" >&2
            print_scaffold_failure
          elif grep -qF '現場が説明文だけ書き換えた状態を装う' "$rule17"; then
            ok17=0
            echo "  [FAIL] ケース17: プレースホルダ行が再実行後も書き換えたままである（上書きされていない）" >&2
            print_scaffold_failure
          elif ! grep -qF "$orig_row17" "$rule17"; then
            ok17=0
            echo "  [FAIL] ケース17: 再実行後の行が雛形の本文と一致しない" >&2
            print_scaffold_failure
          fi
        fi
      fi
    fi
  fi
  if [ "$ok17" -eq 1 ]; then
    echo "  [PASS] ケース17: プレースホルダ行（説明文を書き換えていても）は再実行で雛形の本文へ上書きされる"
  else
    rc=1
  fi

  # ケース18（判定3）: merge_project_rule_section を直接呼び、
  #   (a)「このプロジェクトの規則」以外の節（概要・規則・違反時の手順）が変化しないこと、
  #   (b) 現場が観測した内容が保持されること、
  #   (c) 節の最後の表行と次の見出しの間に空行がちょうど1行入ること（空行喪失の再発防止）
  #   を確かめる。full run_scaffold を経由しないため高速に検証できる。
  local ok18=1
  local pkey18="agent-operations" ckey18="ai-behavior"
  local title18 summary18 scope18 paths18 checker18 src18
  title18="$(jq -r --arg k "$ckey18" '.parents[].children[] | select(.key==$k) | .title' "$TAXONOMY_JSON")"
  summary18="$(jq -r --arg k "$ckey18" '.parents[].children[] | select(.key==$k) | .summary' "$TAXONOMY_JSON")"
  scope18="$(jq -r --arg k "$ckey18" '.parents[].children[] | select(.key==$k) | .scope' "$TAXONOMY_JSON")"
  paths18="$(jq -c --arg k "$ckey18" '.parents[].children[] | select(.key==$k) | .paths' "$TAXONOMY_JSON")"
  checker18="$(jq -r --arg k "$ckey18" '.parents[].children[] | select(.key==$k) | .checker // empty' "$TAXONOMY_JSON")"
  src18="${TOOLDEFINED_TEMPLATE_DIR}/${ckey18}.md"

  local new18
  new18="$(build_tooldefined_rule_md "$ckey18" "$title18" "$pkey18" "$summary18" "$TOOLDEFINED_UNCHECKABLE" "$src18" "$scope18" "$paths18" "未解析" "" "$checker18")"

  # 現場が「このプロジェクトの規則」節へ観測内容を書き足した既存ファイルを装う。
  local existing18_file
  existing18_file="$(mktemp "${TMPDIR:-/tmp}/scaffold-rule-definitions-case18-existing.XXXXXX")"
  printf '%s\n' "$new18" | awk '
    /^## このプロジェクトの規則$/ {
      print
      print ""
      print "<!-- リバース解析が対象リポジトリの観測から起こした規則を置く。 -->"
      print ""
      print "| 規則 | 内容 | 根拠 | 検査 |"
      print "|---|---|---|---|"
      print "| ケース18観測ルール | 現場が観測した実際の規則 | 現場のコード | レビュー: 現場が目視で確認する |"
      skip=1
      next
    }
    skip && /^## / { skip=0 }
    skip { next }
    { print }
  ' > "$existing18_file"

  local merged18
  merged18="$(merge_project_rule_section "$new18" "$existing18_file")"

  local other_new18 other_merged18
  other_new18="$(printf '%s\n' "$new18" | awk '
    /^## このプロジェクトの規則$/ { skip=1; next }
    skip && /^## / { skip=0 }
    skip { next }
    { print }
  ')"
  other_merged18="$(printf '%s\n' "$merged18" | awk '
    /^## このプロジェクトの規則$/ { skip=1; next }
    skip && /^## / { skip=0 }
    skip { next }
    { print }
  ')"
  if [ "$other_new18" != "$other_merged18" ]; then
    ok18=0
    echo "  [FAIL] ケース18: 『このプロジェクトの規則』以外の節がマージで変化した" >&2
  fi

  printf '%s\n' "$merged18" | grep -qF 'ケース18観測ルール' || { ok18=0; echo "  [FAIL] ケース18: 現場の観測内容が保持されない" >&2; }

  local sep_lines18
  sep_lines18="$(printf '%s\n' "$merged18" | awk '
    /^## このプロジェクトの規則$/ { f=1; next }
    f && /^## / { print blank+0; exit }
    f && /^\|/ { blank=0; next }
    f && /^$/ { blank++ }
  ')"
  if [ "$sep_lines18" != "1" ]; then
    ok18=0
    echo "  [FAIL] ケース18: 節と次の見出しの間の空行数が1でない（実際=${sep_lines18}）" >&2
  fi

  rm -f "$existing18_file"

  if [ "$ok18" -eq 1 ]; then
    echo "  [PASS] ケース18: 節単位のマージが他の節を変えず、空行1行で次の見出しに接続する"
  else
    rc=1
  fi

  # ケース11（改善課題1-42 検収方法1・4・5）: toolDefinedの生成物（rule.md）に
  #   禁止語（delivery-payload/references/rule-banned-terms.json）の機械検索が0件であること
  local ok11=1 scan_out11 hit11
  scan_out11="$(scan_banned_terms "${out1}/docs/rules")"
  hit11="$(printf '%s\n' "$scan_out11" | head -n1 | sed -n 's/^禁止語検査: \([0-9][0-9]*\)件.*$/\1/p')"
  if [ -z "$hit11" ] || [ "$hit11" != "0" ]; then
    ok11=0
  fi
  if [ "$ok11" -eq 1 ]; then
    echo "  [PASS] ケース11: toolDefinedの生成物（rule.md）に禁止語の機械検索が0件である"
  else
    echo "  [FAIL] ケース11: toolDefinedの生成物に禁止語が検出された" >&2
    printf '%s\n' "$scan_out11" | sed 's/^/    /' >&2
    rc=1
  fi

  # ケース12（改善課題1-42 検収方法2）: toolDefinedのrule.mdに、設計
  #   （規約定義と派生生成の設計.md 4節）が定める節以外の見出しが現れないこと。
  #   期待する節は enforcement で変わる。none は 3 節、advisory は「違反時の手順」を
  #   加えた 4 節である。
  local ok12=1 rf12 headings12 expected12 expected12_advisory
  expected12="$(printf '%s\n' '概要' '規則' 'このプロジェクトの規則' | sort)"
  expected12_advisory="$(printf '%s\n' '概要' '規則' 'このプロジェクトの規則' '違反時の手順' | sort)"
  while IFS= read -r rf12; do
    [ -n "$rf12" ] || continue
    local fm_body12 v_status12 v_enf12 want12
    fm_body12="$(fm_extract "$rf12" || true)"
    v_status12="$(fm_get_scalar "$fm_body12" status)"
    [ "$v_status12" = "approved" ] || continue
    v_enf12="$(fm_get_scalar "$fm_body12" enforcement)"
    if [ "$v_enf12" = "advisory" ]; then
      want12="$expected12_advisory"
    else
      want12="$expected12"
    fi
    headings12="$(grep '^## ' "$rf12" | sed 's/^## //' | sort)"
    if [ "$headings12" != "$want12" ]; then
      echo "  [FAIL] ケース12詳細: ${rf12} の見出しが設計外" >&2
      ok12=0
    fi
  done <<EOF
$rule_files
EOF
  if [ "$ok12" -eq 1 ]; then
    echo "  [PASS] ケース12: toolDefinedのrule.mdに設計が定める節以外の見出しが現れない"
  else
    echo "  [FAIL] ケース12: 設計が定めていない見出しを持つrule.mdがある" >&2
    rc=1
  fi

  # ケース14: checker を宣言する子カテゴリの生成先へ、linter 本体と回帰テストが
  #   実行権限つきで配られていること
  local ok14=1 ck14 ckey14 cparent14 cdir14 ctest14
  while IFS= read -r ck14; do
    [ -n "$ck14" ] || continue
    ckey14="$(printf '%s' "$ck14" | cut -f1)"
    cparent14="$(printf '%s' "$ck14" | cut -f2)"
    cdir14="${out1}/docs/rules/${cparent14}/${ckey14}"
    ctest14="$(printf '%s' "$ck14" | cut -f3)"
    if [ ! -x "${cdir14}/${ctest14}" ]; then
      echo "  [FAIL] ケース14詳細: ${cdir14}/${ctest14} が実行可能な形で配られていない" >&2
      ok14=0
    fi
    local tf14="${ctest14%.sh}.test.sh"
    if [ ! -x "${cdir14}/${tf14}" ]; then
      echo "  [FAIL] ケース14詳細: ${cdir14}/${tf14} が実行可能な形で配られていない" >&2
      ok14=0
    fi
  done <<EOF
$(jq -r '.parents[] | .key as $p | .children[] | select(.checker != null) | "\(.key)\t\($p)\t\(.checker)"' "$TAXONOMY_JSON")
EOF
  if [ "$ok14" -eq 1 ]; then
    echo "  [PASS] ケース14: checker を宣言する子カテゴリへ linter と回帰テストが配られる"
  else
    echo "  [FAIL] ケース14: checker または回帰テストが配られていない子カテゴリがある" >&2
    rc=1
  fi

  # ケース13（改善課題1-42 検収方法3）: 納品サンプル（generation-engine/samples/docs/rules）に
  #   対して同じ検索を行い0件であること
  local ok13=1 scan_out13 hit13
  scan_out13="$(scan_banned_terms "${REPO_ROOT}/generation-engine/samples/docs/rules")"
  hit13="$(printf '%s\n' "$scan_out13" | head -n1 | sed -n 's/^禁止語検査: \([0-9][0-9]*\)件.*$/\1/p')"
  if [ -z "$hit13" ] || [ "$hit13" != "0" ]; then
    ok13=0
  fi
  if [ "$ok13" -eq 1 ]; then
    echo "  [PASS] ケース13: 納品サンプル（generation-engine/samples/docs/rules）に禁止語の機械検索が0件である"
  else
    echo "  [FAIL] ケース13: 納品サンプルに禁止語が検出された" >&2
    printf '%s\n' "$scan_out13" | sed 's/^/    /' >&2
    rc=1
  fi

  rm -rf "$out1" "$out2"

  # ケース11: appliesWhenの3状態判定（未解析/対象なし/観測あり）が
  #   マニフェストの有無・件数に追従する。build-deliverable-inventory.shのケース5と
  #   同じ理由で、生成テキスト全体へのgrepではなく関数の戻り値（TAB区切り。
  #   状態ラベル自体は日本語だが1ファイル内のcut -f1判定のため
  #   複数ファイル横断grepの多バイト誤判定は起きない）で判定する。
  local ok11=1
  local layout_json11 manifests_root11
  layout_json11="$(resolve_output_layout "$REPO_ROOT")"
  manifests_root11="$(output_layout_get "$layout_json11" manifestsRoot)"

  local root11_none root11_zero root11_some root11_screen
  root11_none="$(mktemp -d "${TMPDIR:-/tmp}/scaffold-rule-definitions-applies-none.XXXXXX")"
  root11_zero="$(mktemp -d "${TMPDIR:-/tmp}/scaffold-rule-definitions-applies-zero.XXXXXX")"
  root11_some="$(mktemp -d "${TMPDIR:-/tmp}/scaffold-rule-definitions-applies-some.XXXXXX")"
  root11_screen="$(mktemp -d "${TMPDIR:-/tmp}/scaffold-rule-definitions-applies-screen.XXXXXX")"

  mkdir -p "${root11_zero}/${manifests_root11}"
  echo '{"units":[]}' > "${root11_zero}/${manifests_root11}/table-manifest.json"
  mkdir -p "${root11_some}/${manifests_root11}"
  echo '{"units":[{"tableKey":"t1"}]}' > "${root11_some}/${manifests_root11}/table-manifest.json"
  # screenManifestは件数ポインタが.screens（他6種別は.units）。
  # (.screens // .units // []) の一般化ポインタが両方の形を読めることを確かめる。
  mkdir -p "${root11_screen}/${manifests_root11}"
  echo '{"screens":[{"screenKey":"s1"}]}' > "${root11_screen}/${manifests_root11}/screen-manifest.json"

  local applies11_table applies11_screen
  applies11_table='{"anyOf":[{"manifest":"table-manifest.json","minCount":1}]}'
  applies11_screen='{"anyOf":[{"manifest":"screen-manifest.json","minCount":1}]}'

  local st_none st_zero st_some st_screen
  st_none="$(resolve_applies_when_state "$root11_none" "$applies11_table" | cut -f1)"
  st_zero="$(resolve_applies_when_state "$root11_zero" "$applies11_table" | cut -f1)"
  st_some="$(resolve_applies_when_state "$root11_some" "$applies11_table" | cut -f1)"
  st_screen="$(resolve_applies_when_state "$root11_screen" "$applies11_screen" | cut -f1)"

  [ "$st_none" = "未解析" ] || { ok11=0; echo "  [FAIL] ケース11: マニフェスト未生成が未解析にならない (実際=${st_none})" >&2; }
  [ "$st_zero" = "対象なし" ] || { ok11=0; echo "  [FAIL] ケース11: マニフェスト0件が対象なしにならない (実際=${st_zero})" >&2; }
  [ "$st_some" = "観測あり" ] || { ok11=0; echo "  [FAIL] ケース11: マニフェスト1件以上が観測ありにならない (実際=${st_some})" >&2; }
  [ "$st_screen" = "観測あり" ] || { ok11=0; echo "  [FAIL] ケース11: .screensポインタのマニフェストが観測ありにならない (実際=${st_screen})" >&2; }

  # build_tooldefined_rule_md() が3状態それぞれで「このプロジェクトの規則」の
  # 行を定義済みの2状態へ正しく差し替える（対象なしだけはnotApplicable、
  # 未解析と観測ありはunanalysed）ことを、実テンプレート(state-transitions.md)で確認する。
  local src11="${TOOLDEFINED_TEMPLATE_DIR}/state-transitions.md"
  local rc11_unanalyzed rc11_absent rc11_observed
  rc11_unanalyzed="$(build_tooldefined_rule_md state-transitions 状態遷移の制約 business-domain 概要 "$TOOLDEFINED_UNCHECKABLE" "$src11" scoped '["docs/**"]' "未解析" "")"
  rc11_absent="$(build_tooldefined_rule_md state-transitions 状態遷移の制約 business-domain 概要 "$TOOLDEFINED_UNCHECKABLE" "$src11" scoped '["docs/**"]' "対象なし" "テーブル")"
  rc11_observed="$(build_tooldefined_rule_md state-transitions 状態遷移の制約 business-domain 概要 "$TOOLDEFINED_UNCHECKABLE" "$src11" scoped '["docs/**"]' "観測あり" "テーブル")"

  local unanalysed_row11 not_applicable_row11
  unanalysed_row11="$(project_rule_placeholder_row unanalysed)" || ok11=0
  not_applicable_row11="$(project_rule_placeholder_row notApplicable)" || ok11=0
  printf '%s\n' "$rc11_unanalyzed" | grep -Fqx "$unanalysed_row11" || { ok11=0; echo "  [FAIL] ケース11: 未解析状態でunanalysed定義行にならない" >&2; }
  printf '%s\n' "$rc11_absent" | grep -Fqx "$not_applicable_row11" || { ok11=0; echo "  [FAIL] ケース11: 対象なし状態でnotApplicable定義行にならない" >&2; }
  printf '%s\n' "$rc11_observed" | grep -Fqx "$unanalysed_row11" || { ok11=0; echo "  [FAIL] ケース11: 観測あり状態でunanalysed定義行にならない" >&2; }

  rm -rf "$root11_none" "$root11_zero" "$root11_some" "$root11_screen"

  if [ "$ok11" -eq 1 ]; then
    echo "  [PASS] ケース11: appliesWhenの3状態判定（未解析/対象なし/観測あり）がマニフェストの有無・件数に追従する"
  else
    rc=1
  fi

  # ケース21（改善課題1-76）: プロジェクト固有規則のプレースホルダはtaxonomyの
  # 2状態定義だけから生成する。未解析相当の5件が同じ行になること、各行に次の一手が
  # あること、対象なしとの区別、定義変更への追従、現場内容の完全保持をまとめて確かめる。
  local ok21=1 unanalysed_row21 not_applicable_row21 unanalysed_label21 not_applicable_label21
  unanalysed_row21="$(project_rule_placeholder_row unanalysed)" || ok21=0
  not_applicable_row21="$(project_rule_placeholder_row notApplicable)" || ok21=0
  unanalysed_label21="$(project_rule_placeholder_label unanalysed)" || ok21=0
  not_applicable_label21="$(project_rule_placeholder_label notApplicable)" || ok21=0

  # (a) 未解析・観測あり・状態なしのいずれもunanalysed行となり、5回の生成で一致する。
  local generated21 row21 i21
  for i21 in 1 2 3 4 5; do
    generated21="$(build_tooldefined_rule_md state-transitions 状態遷移の制約 business-domain 概要 "$TOOLDEFINED_UNCHECKABLE" "$src11" scoped '["docs/**"]' "未解析" "")" || ok21=0
    row21="$(printf '%s\n' "$generated21" | awk -v label="$unanalysed_label21" 'index($0, "| " label " |") == 1 { print; exit }')"
    [ "$row21" = "$unanalysed_row21" ] || ok21=0
  done

  # (b) 両状態の行は次の一手を含み、旧い空欄語を生成しない。
  printf '%s\n' "$unanalysed_row21" | grep -qF 'リバース解析を実行' || ok21=0
  printf '%s\n' "$not_applicable_row21" | grep -qF '直接この節を記入' || ok21=0
  case "${unanalysed_row21}${not_applicable_row21}" in
    *'（未記入）'*) ok21=0 ;;
  esac

  # (c) 対象なしは未解析と別の定義行であり、繰り返し生成しても同じ行になる。
  [ "$unanalysed_row21" != "$not_applicable_row21" ] || ok21=0
  for i21 in 1 2 3 4 5; do
    generated21="$(build_tooldefined_rule_md state-transitions 状態遷移の制約 business-domain 概要 "$TOOLDEFINED_UNCHECKABLE" "$src11" scoped '["docs/**"]' "対象なし" "テーブル")" || ok21=0
    row21="$(printf '%s\n' "$generated21" | awk -v label="$not_applicable_label21" 'index($0, "| " label " |") == 1 { print; exit }')"
    [ "$row21" = "$not_applicable_row21" ] || ok21=0
  done

  # (d) taxonomyの複製で本文だけを変えても、スクリプトを変えずに生成行へ反映される。
  local taxonomy21 original_taxonomy21 changed21 unique_content21
  taxonomy21="$(mktemp "${TMPDIR:-/tmp}/scaffold-rule-definitions-placeholder-taxonomy.XXXXXX")"
  original_taxonomy21="$TAXONOMY_JSON"
  unique_content21='1-76自己テスト用の定義変更が生成行へ反映される'
  if jq --arg content "$unique_content21" '.projectRulePlaceholders.unanalysed.content = $content' "$original_taxonomy21" > "${taxonomy21}.next"; then
    mv "${taxonomy21}.next" "$taxonomy21"
    TAXONOMY_JSON="$taxonomy21"
    changed21="$(build_tooldefined_rule_md state-transitions 状態遷移の制約 business-domain 概要 "$TOOLDEFINED_UNCHECKABLE" "$src11" scoped '["docs/**"]' "観測あり" "テーブル")" || ok21=0
    TAXONOMY_JSON="$original_taxonomy21"
    printf '%s\n' "$changed21" | grep -qF "$unique_content21" || ok21=0
  else
    ok21=0
  fi
  TAXONOMY_JSON="$original_taxonomy21"
  rm -f "$taxonomy21" "${taxonomy21}.next"

  # (e) 内容の入った節はmerge_project_rule_sectionで1文字も変えずに保持される。
  local existing21_file expected_section21 merged21 merged_section21
  existing21_file="$(mktemp "${TMPDIR:-/tmp}/scaffold-rule-definitions-placeholder-existing.XXXXXX")"
  cat > "$existing21_file" <<'EOF'
## このプロジェクトの規則

<!-- 現場がリバース解析の観測から起こした規則。 -->

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 現場観測ルール21 | 現場固有の内容 | 対象コードの観測 | レビュー: 内容を確認する |
EOF
  expected_section21="$(cat "$existing21_file")"
  merged21="$(merge_project_rule_section "$rc11_unanalyzed" "$existing21_file")" || ok21=0
  merged_section21="$(printf '%s\n' "$merged21" | awk '
    /^## このプロジェクトの規則$/ { f=1 }
    f && /^## / && !/^## このプロジェクトの規則$/ { exit }
    f { print }
  ')"
  [ "$merged_section21" = "$expected_section21" ] || ok21=0
  rm -f "$existing21_file"

  if [ "$ok21" -eq 1 ]; then
    echo "  [PASS] ケース21: 1-76のプレースホルダ定義・生成・現場内容保護が要件どおりである"
  else
    echo "  [FAIL] ケース21: 1-76のプレースホルダ定義・生成・現場内容保護に不一致がある" >&2
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

  local out_root="" apply_flag=0 with_skills_flag=0
  local args=()
  for a in "$@"; do
    case "$a" in
      --apply) apply_flag=1 ;;
      --with-skills) with_skills_flag=1 ;;
      *) args+=("$a") ;;
    esac
  done

  if [ "${#args[@]}" -ne 1 ]; then
    echo "使い方: $(basename "$0") <出力先リポジトリルート> [--apply] [--with-skills]" >&2
    echo "        $(basename "$0") --self-test" >&2
    exit 1
  fi

  out_root="${args[0]}"
  APPLY="$apply_flag"
  WITH_SKILLS="$with_skills_flag"

  run_scaffold "$out_root"
  exit $?
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main "$@"
fi
