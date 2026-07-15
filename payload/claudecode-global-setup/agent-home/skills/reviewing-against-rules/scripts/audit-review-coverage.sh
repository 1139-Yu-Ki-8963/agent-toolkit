#!/usr/bin/env bash
# audit-review-coverage.sh — レビュー観点（rule）と専門家（reviewer）の網羅性を数える
#
# 使い方: audit-review-coverage.sh
# 終了コード: 0 = 全項目 PASS / 1 = 1件以上 FAIL
#
# 検証項目:
#   1. フォルダ⇄専門家の 1 対 1: scoped/review-checklist/<domain>/ の各ドメインについて、
#      対応するサブエージェント定義 ~/.claude/agents/<domain>-reviewer/<domain>-reviewer.md が
#      実在するか。各ドメイン配下に rule.md が 1 件以上あるか
#   2. always 横断観点: always/review-checklist/<name>/rule.md の各規約が、
#      少なくとも1つのレビュー専門家定義（~/.claude/agents/*-reviewer/*.md）内に
#      ~/ 形式パスの文字列として存在するか（＝専門家が実際に参照しているか）。
#      フォルダ位置が登録の代わり（登録リスト txt は持たない）
#   3. 全 rule 分類網羅: ディスク上の全 rule.md（always/ + scoped/）が
#      「review-checklist 配下（scoped / always とも）」または
#      「rule-classification.txt に分類記載」のどちらかに該当するか。
#      未分類 rule は FAIL。分類表の dead entry も FAIL
#
# 設計判断（ADR）:
#   必要性: rules のフォルダ分類と専門家へのディスパッチのズレ・観点の数え漏れは、
#     機械的に数えて突き合わせない限り再発する（2026-07-10 に実際に 3 度発覚）。
#     「フォルダ名 = 専門家名」の 1 対 1 対応・always 照合義務・全 rule 分類義務という
#     統治規約（scoped/agent-config/review-checklist/rule.md）の機械検証を本スクリプトが担う。
#   代替案を採用しなかった理由: managing-agent-configs の rules レビュー観点への恒久統合は、
#     review-checklist 固有の概念（ドメイン導出・台帳相互一致）の特殊分岐を汎用レビューに
#     持ち込むことになる。reviewing-against-rules 側の専用スクリプトの方が影響範囲が狭い。
#   保守責任者: 人手（ユーザー）。統治規約の構造・台帳の書式を変更する場合は本スクリプトも追従させる。
#   廃棄条件: reviewing-against-rules スキル自体が廃止された時。
set -u

CHECKLIST_ROOT="$HOME/.claude/rules/scoped/review-checklist"
ALWAYS_CHECKLIST_ROOT="$HOME/.claude/rules/always/review-checklist"
GOVERNANCE_ROOT="$HOME/.claude/rules/scoped/agent-config/review-checklist"
AGENTS_ROOT="$HOME/.claude/agents"
CLASSIFICATION="$GOVERNANCE_ROOT/rule-classification.txt"
ALL_RULES_ROOT="$HOME/.claude/rules"

fails=0
domain_count=0
rule_count=0

echo "=== review-checklist 網羅性監査 ==="
echo ""
echo "--- 1. フォルダ⇄専門家の 1 対 1 確認 ---"

for domain_dir in "$CHECKLIST_ROOT"/*/; do
  [ -d "$domain_dir" ] || continue
  domain=$(basename "$domain_dir")
  domain_count=$((domain_count + 1))
  agent_def="${AGENTS_ROOT}/${domain}-reviewer/${domain}-reviewer.md"
  if [ ! -f "$agent_def" ]; then
    echo "FAIL: ドメイン ${domain}/ に対応する専門家 ${domain}-reviewer が実在しない（${agent_def}）"
    fails=$((fails + 1))
  else
    domain_rules=$(find "$domain_dir" -name rule.md | wc -l | tr -d ' ')
    if [ "$domain_rules" -eq 0 ]; then
      echo "FAIL: ドメイン ${domain}/ に rule.md が 1 件もない（空ドメイン）"
      fails=$((fails + 1))
    else
      echo "PASS: ${domain}/ (${domain_rules} 観点) <-> ${domain}-reviewer 実在"
      rule_count=$((rule_count + domain_rules))
    fi
  fi
done
if [ "$domain_count" -eq 0 ]; then
  echo "FAIL: ${CHECKLIST_ROOT} にドメインフォルダが 1 つもない"
  fails=$((fails + 1))
fi

echo ""
echo "--- 2. always 横断観点（always/review-checklist/）の参照確認 ---"

always_count=0
if [ ! -d "$ALWAYS_CHECKLIST_ROOT" ]; then
  echo "FAIL: $ALWAYS_CHECKLIST_ROOT が実在しない"
  fails=$((fails + 1))
else
  for always_rule in "$ALWAYS_CHECKLIST_ROOT"/*/rule.md; do
    [ -f "$always_rule" ] || continue
    always_count=$((always_count + 1))
    rule_path_tilde="~${always_rule#"$HOME"}"
    referenced=0
    for agent_md in "$AGENTS_ROOT"/*-reviewer/*.md; do
      [ -f "$agent_md" ] || continue
      if grep -qF "$rule_path_tilde" "$agent_md"; then
        referenced=1
      fi
    done
    if [ "$referenced" -eq 1 ]; then
      echo "PASS: ${rule_path_tilde} は専門家定義から参照されている"
    else
      echo "FAIL: ${rule_path_tilde} はどの専門家定義（*-reviewer/*.md）からも参照されていない"
      fails=$((fails + 1))
    fi
  done
  if [ "$always_count" -eq 0 ]; then
    echo "FAIL: ${ALWAYS_CHECKLIST_ROOT} に観点 rule が 1 件もない"
    fails=$((fails + 1))
  fi
fi

echo ""
echo "--- 3. 全 rule 分類網羅の確認 ---"

classified_count=0
unclassified_count=0
if [ ! -f "$CLASSIFICATION" ]; then
  echo "FAIL: $CLASSIFICATION が実在しない"
  fails=$((fails + 1))
else
  # 3a: ディスク上の全 rule.md が分類済みか（review-checklist 配下は場所が分類）
  while IFS= read -r rule_abs; do
    rule_tilde="~${rule_abs#"$HOME"}"
    case "$rule_abs" in
      "$CHECKLIST_ROOT"/*|"$ALWAYS_CHECKLIST_ROOT"/*)
        classified_count=$((classified_count + 1))
        continue ;;
    esac
    if grep -qF "$rule_tilde" "$CLASSIFICATION"; then
      classified_count=$((classified_count + 1))
    else
      echo "FAIL: ${rule_tilde} が未分類（rule-classification.txt に分類を追記すること）"
      fails=$((fails + 1))
      unclassified_count=$((unclassified_count + 1))
    fi
  done <<EOF
$(find "$ALL_RULES_ROOT/always" "$ALL_RULES_ROOT/scoped" -name rule.md 2>/dev/null | sort)
EOF

  # 3b: 分類表の dead entry 検出
  while IFS=$'\t' read -r cls_path _cls_kind _cls_note; do
    case "$cls_path" in
      \#*|"") continue ;;
    esac
    cls_abs="${cls_path/#\~/$HOME}"
    if [ ! -f "$cls_abs" ]; then
      echo "FAIL: rule-classification.txt の ${cls_path} が実在しない（dead entry）"
      fails=$((fails + 1))
    fi
  done < "$CLASSIFICATION"
fi
[ "$unclassified_count" -eq 0 ] && [ -f "$CLASSIFICATION" ] && echo "PASS: ディスク上の全 rule.md が分類済み"

echo ""
echo "=== 集計 ==="
echo "ドメイン数（専門家と 1 対 1）: $domain_count"
echo "専門家別観点 rule 数（scoped）: $rule_count"
echo "横断観点 rule 数（always）: $always_count"
echo "全 rule 数（分類済み）: $classified_count"
echo "FAIL: $fails"

if [ "$fails" -gt 0 ]; then
  exit 1
fi
exit 0
