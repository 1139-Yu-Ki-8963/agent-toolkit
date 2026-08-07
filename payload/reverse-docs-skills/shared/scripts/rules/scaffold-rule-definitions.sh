#!/usr/bin/env bash
set -euo pipefail

# scaffold-rule-definitions.sh — まっさらな対象リポジトリへ規約定義一式を配る
#
# 設計の定義: shared/references/規約定義と派生生成の設計.md
# 宣言データ: shared/references/rule-taxonomy.json（親7・子27の英語キー・表示名・既定値）
#
# 目的:
#   docs/rules/ が空、または未整備の対象リポジトリに、親7フォルダ・parent.yml、
#   子27フォルダ・rule.md（空雛形）を作る。rule-taxonomy.json で toolDefined を
#   宣言している子カテゴリはツール側が本文を書いて納品する規約のため、空雛形にせず
#   本文入りで作る。あわせて --with-skills 指定時は納品スキル2本、
#   検証と生成のスクリプト（docs/rules/tooling/）を配る。
#
# 使い方:
#   scaffold-rule-definitions.sh <出力先リポジトリルート> [--apply] [--with-skills]
#   scaffold-rule-definitions.sh --self-test
#
# 既定はdry-run。生成予定のパスを標準出力へ列挙するのみで書き込みをしない。
# --apply を付けたときだけ出力先リポジトリルートへ実際に書き込む。
#
# 既存ファイルの扱い:
#   rule.md・parent.yml・design-notes.md・SKILL.md のいずれも、既に存在する場合は
#   上書きしない（現場が書き込んだ内容を保護する）。存在した件数と新規に作った
#   件数を最後に報告する。
#
# --with-skills:
#   shared/templates/delivered-skills/ の2本（importing-rule-proposals・
#   syncing-derived-artifacts）の SKILL.md を <出力先>/.claude/skills/<name>/SKILL.md
#   へ複製する。front matter は Claude Code のスキル発見に必須のため先頭を保ち、
#   front matter 直後に生成物notice comment を入れる
#   （build-derived-rules.sh の .mdc 生成と同じ配置規約）。
#
# docs/rules/tooling/ の配備:
#   build-derived-rules.sh --deploy-tooling を呼ぶだけで、重複実装しない
#   （--apply指定時のみ実行。dry-runでは呼ばず計画行のみ列挙する）。
#
# 終了コード:
#   0 = 生成（またはdry-runの列挙）が完了
#   1 = 引数不正、または taxonomy 読み込み失敗
#   --self-test のみ、期待どおりの生成ができなければ1
#
# 保守責任者・廃棄条件: shared/scripts/rules/rule.md の「## 設計判断」を参照。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=./validate-rule-definitions.sh
. "${SCRIPT_DIR}/validate-rule-definitions.sh"

TAXONOMY_JSON="${REPO_ROOT}/shared/references/rule-taxonomy.json"
BUILD_DERIVED_SCRIPT="${SCRIPT_DIR}/build-derived-rules.sh"
SKILLS_TEMPLATE_DIR="${REPO_ROOT}/shared/templates/delivered-skills"
TOOLDEFINED_TEMPLATE_DIR="${REPO_ROOT}/shared/templates/rules/tool-defined"

APPLY=0
WITH_SKILLS=0
PLAN_LINES=""
RULE_NEW=0
RULE_EXIST=0
OTHER_NEW=0
OTHER_EXIST=0
SKILL_NEW=0
SKILL_EXIST=0

plan_add() {
  PLAN_LINES="${PLAN_LINES}${1}
"
}

# 対象パスが既存なら書き込まずスキップする。新規なら（--apply時のみ）書き込む。
# $1: 出力パス  $2: 内容  $3: カウンタ種別（rule / other）
write_if_new() {
  local path="$1" content="$2" kind="$3"
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
    printf '%s\n' "$content" > "$path"
  fi
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
  # enforcement: このスキャフォールドが生成する空雛形は常に none（機械検知しない
  # 取り決め）として配る。設計（shared/references/規約定義と派生生成の設計.md
  # 3節）は「## 違反時の手順」節を enforcement: advisory のときのみ必須とし、
  # none のときは置かないと定める。値をローカル変数に持ち、下の分岐で判定する。
  local enforcement="none"
  cat <<EOF
---
key: ${key}
title: ${title}
parent: ${parent}
summary: ${summary}
scope: always
globs: ["**/*"]
enforcement: ${enforcement}
checkable: false
checker: null
uncheckableReason: 未記入の雛形のため検査対象がない。規約本文が確定してから検査の要否を判断する。
formatter: none
status: draft
origin: template
---

# ${title}

<!-- 未記入の雛形。この規約が扱う対象を、対象リポジトリの実態に即して具体的に書く。 -->

## 概要

${summary}

（未記入）

## 規則

| 規則 | 内容 | 根拠 |
|---|---|---|
| （未記入） | （未記入） | （未記入） |

記入規則: 各規則行には、対象リポジトリの実装から観測した根拠を添える。実装に現れない規則を発明しない。
EOF
  if [ "$enforcement" != "none" ]; then
    cat <<EOF

## 違反時の手順

1. （未記入）
EOF
  fi
}

# ツール側が本文を書いて納品する規約。既存テンプレートの本文（概要・規則表）を
# そのまま使い、front matterと見出しだけを規約定義の形式に合わせて差し替える。
build_tooldefined_rule_md() {
  local key="$1" title="$2" parent="$3" summary="$4" uncheckable="$5" src_template="$6"
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

  cat <<EOF
---
key: ${key}
title: ${title}
parent: ${parent}
summary: ${summary}
scope: always
globs: ["**/*"]
enforcement: none
checkable: false
checker: null
uncheckableReason: ${uncheckable}
formatter: none
status: approved
origin: manual
---

# ${title}

EOF
  printf '%s\n' "$body"
}

TOOLDEFINED_UNCHECKABLE="定義と派生の対応関係はハッシュ台帳による突合で検知しており、この規約自体の遵守を静的解析で判定する仕組みを持たない。"

# ---------------------------------------------------------------------------
# 生成本体
# ---------------------------------------------------------------------------

run_scaffold() {
  local out_root="$1"

  if [ ! -f "$TAXONOMY_JSON" ]; then
    echo "ERROR: taxonomy定義が見つかりません: ${TAXONOMY_JSON}" >&2
    return 1
  fi

  PLAN_LINES=""
  RULE_NEW=0; RULE_EXIST=0
  OTHER_NEW=0; OTHER_EXIST=0
  SKILL_NEW=0; SKILL_EXIST=0

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
      local ckey ctitle csummary ctool
      ckey="$(printf '%s' "$cline" | jq -r '.key')"
      ctitle="$(printf '%s' "$cline" | jq -r '.title')"
      csummary="$(printf '%s' "$cline" | jq -r '.summary')"
      ctool="$(printf '%s' "$cline" | jq -r '.toolDefined')"

      local child_dir="${parent_dir}/${ckey}"
      local rule_content design_content

      if [ "$ctool" = "true" ]; then
        local src_template="${TOOLDEFINED_TEMPLATE_DIR}/${ckey}.md"
        if [ ! -f "$src_template" ]; then
          echo "ERROR: toolDefinedの本文テンプレートが見つかりません: ${ckey}" >&2
          return 1
        fi
        rule_content="$(build_tooldefined_rule_md "$ckey" "$ctitle" "$pkey" "$csummary" "$TOOLDEFINED_UNCHECKABLE" "$src_template")"
      else
        rule_content="$(build_draft_rule_md "$ckey" "$ctitle" "$pkey" "$csummary")"
      fi
      design_content="$(build_design_notes "$ctitle" "$ctool")"

      write_if_new "${child_dir}/rule.md" "$rule_content" "rule"
      write_if_new "${child_dir}/design-notes.md" "$design_content" "other"
    done <<EOF
$child_lines
EOF
  done <<EOF
$parent_lines
EOF

  if [ "$WITH_SKILLS" -eq 1 ]; then
    deliver_skills "$out_root"
  fi

  if [ "$APPLY" -eq 1 ]; then
    plan_add "docs/rules/tooling/build-derived-rules.sh（--deploy-toolingで配備）"
    plan_add "docs/rules/tooling/validate-rule-definitions.sh（--deploy-toolingで配備）"
    bash "$BUILD_DERIVED_SCRIPT" --deploy-tooling "$out_root"
  else
    plan_add "${out_root}/docs/rules/tooling/build-derived-rules.sh"
    plan_add "${out_root}/docs/rules/tooling/validate-rule-definitions.sh"
  fi

  if [ "$APPLY" -eq 1 ]; then
    echo "生成完了（--apply）:"
  else
    echo "DRY-RUN: 以下を生成予定（--apply未指定のため書き込みなし）:"
  fi
  printf '%s' "$PLAN_LINES"
  echo "rule.md 新規: ${RULE_NEW} 件 / 既存(スキップ): ${RULE_EXIST} 件"
  echo "その他(parent.yml・design-notes.md) 新規: ${OTHER_NEW} 件 / 既存(スキップ): ${OTHER_EXIST} 件"
  if [ "$WITH_SKILLS" -eq 1 ]; then
    echo "SKILL.md 新規: ${SKILL_NEW} 件 / 既存(スキップ): ${SKILL_EXIST} 件"
  fi
  return 0
}

deliver_skills() {
  local out_root="$1"
  local name
  for name in importing-rule-proposals syncing-derived-artifacts; do
    local src="${SKILLS_TEMPLATE_DIR}/${name}/SKILL.md"
    local dest="${out_root}/.claude/skills/${name}/SKILL.md"
    if [ ! -f "$src" ]; then
      echo "ERROR: 納品スキルのテンプレートが見つかりません: ${src}" >&2
      return 1
    fi
    if [ -e "$dest" ]; then
      SKILL_EXIST=$((SKILL_EXIST + 1))
      continue
    fi
    SKILL_NEW=$((SKILL_NEW + 1))
    plan_add "$dest"
    if [ "$APPLY" -eq 1 ]; then
      mkdir -p "$(dirname "$dest")"
      # front matter は Claude Code のスキル発見に必須のため先頭を保つ。
      # front matter 直後に生成物notice commentを挟む
      # （build-derived-rules.shの.mdc生成と同じ配置規約）。
      local fm body
      fm="$(awk 'NR==1{print;next} /^---$/{print;exit} {print}' "$src")"
      body="$(awk 'BEGIN{c=0} /^---$/{c++; next} c>=2{print}' "$src")"
      {
        printf '%s\n' "$fm"
        printf '\n<!-- 生成物: shared/templates/delivered-skills/%s/SKILL.md から複製。直接編集しないこと -->\n' "$name"
        printf '%s\n' "$body"
      } > "$dest"
    fi
  done
  return 0
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

self_test() {
  local rc=0
  local out1 out2

  # ケース1: --apply なしでは書き込みが起きない
  out1="$(mktemp -d "${TMPDIR:-/tmp}/scaffold-rule-definitions-self-test-out1.XXXXXX")"
  rm -rf "$out1"
  APPLY=0
  WITH_SKILLS=0
  run_scaffold "$out1" >/dev/null 2>&1 || true
  if [ -d "$out1" ]; then
    echo "  [FAIL] ケース1: --apply なしで出力先ディレクトリが作成された" >&2
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

  # ケース6: --with-skillsで.claude/skills/の2本が配られる
  local ok6=1
  [ -f "${out1}/.claude/skills/importing-rule-proposals/SKILL.md" ] || ok6=0
  [ -f "${out1}/.claude/skills/syncing-derived-artifacts/SKILL.md" ] || ok6=0
  if [ "$ok6" -eq 1 ]; then
    head -n1 "${out1}/.claude/skills/importing-rule-proposals/SKILL.md" | grep -qx -- '---' || ok6=0
  fi
  if [ "$ok6" -eq 1 ]; then
    echo "  [PASS] ケース6: --with-skillsで.claude/skills/の2本が配られ、front matterが先頭にある"
  else
    echo "  [FAIL] ケース6: 納品スキルの配備が不正" >&2
    rc=1
  fi

  # ケース7: docs/rules/tooling/の2本が配られ実行できる
  local ok7=1
  [ -x "${out1}/docs/rules/tooling/build-derived-rules.sh" ] || ok7=0
  [ -x "${out1}/docs/rules/tooling/validate-rule-definitions.sh" ] || ok7=0
  if [ "$ok7" -eq 1 ]; then
    bash "${out1}/docs/rules/tooling/validate-rule-definitions.sh" "${out1}/docs/rules" >/dev/null 2>&1 || ok7=0
  fi
  if [ "$ok7" -eq 1 ]; then
    echo "  [PASS] ケース7: docs/rules/tooling/の2本が配られ、実行できる"
  else
    echo "  [FAIL] ケース7: docs/rules/tooling/の配備または実行が不正" >&2
    rc=1
  fi

  # ケース8: 2回実行しても既存が壊れない（冪等性）
  out2="$(mktemp -d "${TMPDIR:-/tmp}/scaffold-rule-definitions-self-test-out2.XXXXXX")"
  rm -rf "$out2"
  cp -R "$out1" "$out2"
  APPLY=1
  WITH_SKILLS=1
  run_scaffold "$out1" >/dev/null 2>&1
  local diff_log
  diff_log="$(mktemp "${TMPDIR:-/tmp}/scaffold-rule-definitions-bst-diff.XXXXXX")"
  if diff -r "${out2}/docs/rules" "${out1}/docs/rules" >"$diff_log" 2>&1; then
    echo "  [PASS] ケース8: 2回実行しても既存の docs/rules が壊れない（冪等）"
  else
    echo "  [FAIL] ケース8: 再実行で既存の docs/rules が変化した" >&2
    sed 's/^/    /' "$diff_log" >&2
    rc=1
  fi
  rm -f "$diff_log"

  # ケース9: enforcement の値ごとに「## 違反時の手順」節の有無が
  #   テンプレート・生成スクリプト出力・shared/samples/rules の三者で
  #   設計（規約定義と派生生成の設計.md 3節）どおりに揃っている（節構成の
  #   三者乖離の再発防止。改善課題1-3）
  local ok9=1

  # 9a. テンプレート: advisory時の雛形として「違反時の手順」節と、
  #     enforcement: none に変えた場合の削除注記を両方持つ（Option A）
  local template_file="${REPO_ROOT}/shared/templates/rules/rule-template.md"
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

  # 9b. 生成スクリプト出力: enforcement: none で生成した rule.md（ケース3で
  #     出力済みの $rule_files）に「違反時の手順」節が混入していない
  local gen_leak=0 rf9
  while IFS= read -r rf9; do
    [ -n "$rf9" ] || continue
    grep -q '^## 違反時の手順$' "$rf9" && gen_leak=$((gen_leak + 1))
  done <<EOF
$rule_files
EOF
  if [ "$gen_leak" -ne 0 ]; then
    echo "  [FAIL] ケース9b: 生成スクリプト出力の enforcement: none rule.md に『違反時の手順』節が ${gen_leak} 件混入" >&2
    ok9=0
  fi

  # 9c. サンプル: shared/samples/rules 配下の全rule.mdで、enforcement の値と
  #     「違反時の手順」節の有無が一致する
  local sample_files sf9 sf9_enf sf9_has
  sample_files="$(find "${REPO_ROOT}/shared/samples/rules" -type f -name 'rule.md' 2>/dev/null | sort)"
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

  rm -rf "$out1" "$out2"

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
