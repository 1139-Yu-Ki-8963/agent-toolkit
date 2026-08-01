#!/usr/bin/env bash
# 改善課題 1-138 の横断検収条件の対象外: 本ファイル自体が固定5サンプルに対する回帰試験
# （writing-rules.md の密度上限の再現確認）であり、--self-test フラグを持つ本番経路
# スクリプトではないため、追加の --self-test 実装は行わない（本ファイルの実行自体が
# 回帰検証にあたる）。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
TEMPLATE="$ROOT_DIR/shared/templates/リバース検証/画面/詳細設計/画面詳細設計書.md"
WRITING_RULES="$ROOT_DIR/.claude/skills/generating-reverse-detailed-design/references/writing-rules.md"
SAMPLES=(
  "$ROOT_DIR/shared/samples/画面/screen-home/詳細設計/画面詳細設計書.md"
  "$ROOT_DIR/shared/samples/画面/screen-member-edit/詳細設計/画面詳細設計書.md"
  "$ROOT_DIR/shared/samples/画面/screen-order-detail/詳細設計/画面詳細設計書.md"
  "$ROOT_DIR/shared/samples/画面/screen-order-list/詳細設計/画面詳細設計書.md"
  "$ROOT_DIR/shared/samples/画面/screen-sales-dashboard/詳細設計/画面詳細設計書.md"
)

# 元指摘の196回に対する上限は65回。リポジトリで再現可能な同一5サンプルの
# 変更前基準は45回なので、より厳しい上限15回も併せて検査する。
REPORTED_BASELINE_COUNT=196
REPORTED_MAX_COUNT=$((REPORTED_BASELINE_COUNT / 3))
BASELINE_COUNT=45
MAX_COUNT=$((BASELINE_COUNT / 3))
actual_count="$( { grep -h -o '該当なし' "${SAMPLES[@]}" 2>/dev/null || true; } | wc -l | tr -d ' ')"

if (( actual_count > REPORTED_MAX_COUNT || actual_count > MAX_COUNT )); then
  echo "[FAIL] 該当なし密度: ${actual_count}回（指摘基準上限${REPORTED_MAX_COUNT}回、同一サンプル上限${MAX_COUNT}回）" >&2
  exit 1
fi
echo "[PASS] 該当なし密度: 指摘基準${REPORTED_BASELINE_COUNT}回の上限${REPORTED_MAX_COUNT}回以下、同一5サンプル${BASELINE_COUNT}回 → ${actual_count}回（上限${MAX_COUNT}回）"

grep -qF '本領域は全項目非該当（根拠:' "$TEMPLATE"
grep -qF '非該当項目: §X.Y' "$TEMPLATE"
grep -qF '章内の全下位項目が対象外なら' "$WRITING_RULES"
grep -qF 'facts に項目が1件以上ある節、`measurement_pending`、未確認事項' "$WRITING_RULES"
echo "[PASS] テンプレートと執筆規律: 全項目・一部項目の集約書式と集約禁止条件を確認"

summary_count="$(
  awk '
    /^> (非該当項目:|本領域は全項目非該当)/ &&
      $0 ~ /measurement_pending|実測委譲|未確認/ {
      print "[FAIL] 集約禁止情報が非該当行へ混入: " $0 > "/dev/stderr"
      bad = 1
    }
    /^> 本領域は全項目非該当/ &&
      $0 !~ /全項目非該当[[:space:]]*[（(]根拠:[[:space:]]*[^[:space:]）)]/ {
      print "[FAIL] 全項目非該当の根拠が空です: " $0 > "/dev/stderr"
      bad = 1
    }
    /^> 非該当項目:/ {
      count++
      line = $0
      sub(/^> 非該当項目:[[:space:]]*/, "", line)
      item_count = split(line, items, ";")
      for (i = 1; i <= item_count; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", items[i])
        reason = items[i]
        if (index(reason, "（") > 0 && index(reason, "）") > 0) {
          sub(/^.*（/, "", reason)
          sub(/）.*$/, "", reason)
        } else if (index(reason, "(") > 0 && index(reason, ")") > 0) {
          sub(/^.*\(/, "", reason)
          sub(/\).*$/, "", reason)
        } else {
          reason = ""
        }
        gsub(/[[:space:]]/, "", reason)
        has_reason = length(reason) > 0
        if (items[i] !~ /^§[0-9]/ || !has_reason) {
          print "[FAIL] 非該当項目の節番号または理由が欠落: " items[i] > "/dev/stderr"
          bad = 1
        }
      }
    }
    END {
      if (count == 0) {
        print "[FAIL] 再生成サンプルに非該当項目の集約行がありません" > "/dev/stderr"
        exit 1
      }
      if (bad) exit 1
      print count
    }
  ' "${SAMPLES[@]}"
)"

# 変更前の理由から、再構築判断に影響する代表的な情報が集約後も残ることを確認する。
for reason in \
  'サイドナビ形式' \
  '下書き保持は §5.2' \
  '会員番号は取得APIの引数' \
  '全ロールが同一のUI' \
  '他画面と共有するストア参照'
do
  if ! awk -v needle="$reason" '
    /^> 非該当項目:/ && index($0, needle) { found = 1 }
    END { exit found ? 0 : 1 }
  ' "${SAMPLES[@]}"; then
    echo "[FAIL] 適用外理由が再生成文書から失われました: $reason" >&2
    exit 1
  fi
done
echo "[PASS] 意味保持: 集約行${summary_count}件に節番号と理由があり、代表的な適用外情報を保持"

AUDIT_SCRIPT="$ROOT_DIR/shared/scripts/audit-consistency.sh"
grep -qF 'mkdir -p "$tmp/t"' "$AUDIT_SCRIPT"
grep -qF 'mkdir -p "$tmp/u"' "$AUDIT_SCRIPT"
grep -qF 'mkdir -p "$tmp/v"' "$AUDIT_SCRIPT"
grep -qF 'mkdir -p "$tmp/w"' "$AUDIT_SCRIPT"
grep -qF 'if out_t="$(bash "$script_path" "$tmp/t" 2>&1)"' "$AUDIT_SCRIPT"
grep -qF 'if out_u="$(bash "$script_path" "$tmp/u" 2>&1)"' "$AUDIT_SCRIPT"
grep -qF 'if out_v="$(bash "$script_path" "$tmp/v" 2>&1)"' "$AUDIT_SCRIPT"
grep -qF 'if out_w="$(bash "$script_path" "$tmp/w" 2>&1)"' "$AUDIT_SCRIPT"
grep -qF '検査t陽性: 画面内状態の非該当集約と他節の状態語残存の矛盾を違反として検出する' "$AUDIT_SCRIPT"
grep -qF '検査t章全体集約: 全項目非該当でも他節の状態語残存を検出する' "$AUDIT_SCRIPT"
grep -qF '検査t旧個別書式: 旧「該当なし」でも他節の状態語残存を検出する' "$AUDIT_SCRIPT"
grep -qF '検査t参照誤認防止: 理由文中の§6.6参照を非該当宣言として扱わない' "$AUDIT_SCRIPT"
echo "[PASS] 書式互換: 章全体集約・一部集約・旧個別書式・参照誤認防止の監査fixture定義を確認"
