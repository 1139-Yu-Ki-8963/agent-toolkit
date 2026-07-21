#!/usr/bin/env bash
# 抽出エンジン(shared/scripts/extract): バッチ種別マニフェストへのメタデータ抽出。
# 入力マニフェスト(unitKind=batch)の units[] を走査し、検出できたフィールドだけを追加した
# 拡張マニフェストを出力する。既存フィールドは一切変更しない。検出根拠が弱い値は出力しない
# (誤った値より欠落を優先する fail-safe。任意フィールドの欠落として扱われる)。
#
# Usage: extract-batch-metadata.sh <batch-manifest.json> <source-dir> <output.json>
#            [--cron-file <path>] [--table-manifest <path>]
#        extract-batch-metadata.sh --self-test
#
# 出力フィールド(スキーマ正本: shared/references/manifest-schema-extensions.md「batches」節):
#   schedule       object {cron, readable}
#   targetTables   string[] (テーブルマニフェストの unitKey)
#   downstreamJobs string[] (同マニフェスト内の他バッチの unitKey)
#   execMethod     string (手動実行コマンド 1 行)
#
# 検出ヒューリスティック一覧(すべて grep/sed ベース):
#   schedule:       --cron-file 内で identifier(不在時は unitKey)を grep -F した行から、
#                   5 フィールドの cron 式を grep -oE '[0-9*,/-]+([[:space:]]+[0-9*,/-]+){4}' で抽出。
#                   readable は基本パターンのみ平易表記へ変換
#                   (分・時が数値かつ 日=月=曜=* → 「毎日 H:MM」/ 曜日 0-6 → 「毎週X曜 H:MM」/
#                    日が数値 → 「毎月D日 H:MM」/ 分=*/N かつ他=* → 「N分ごと」)。
#                   変換不能なら cron 式をそのまま readable に入れる
#   targetTables:   --table-manifest の各 unit の identifier を sourceFile 内で grep -F。
#                   ヒットしたテーブルの unitKey を配列で格納(0 件なら付けない)
#   execMethod:     sourceFile の shebang 行(#!...)からインタプリタ名を取得、shebang 不在でも
#                   if __name__ == '__main__' があれば python3 とみなし、
#                   「<インタプリタ> <sourceFile相対パス>」を生成(どちらも無ければ付けない)
#   downstreamJobs: sourceFile 内で「呼び出し・enqueue 系キーワード
#                   (enqueue|delay|apply_async|subprocess|run(|call|invoke|trigger|import)を含む行」に
#                   同マニフェストの他バッチの identifier/unitKey が grep -F でヒットしたものを格納
#                   (0 件なら付けない)
#
# 出力 JSON は unit-list/validate-manifest.sh --unit-kind batch で検証可能であること
# (self-test 内で validate-manifest.sh も実行して PASS を確認する)。

set -euo pipefail

# --- --self-test モード ---
# mktemp -d に最小フィクスチャ(バッチ 2 本 + crontab + テーブルマニフェスト)を生成し、
# schedule/targetTables/execMethod/downstreamJobs の各フィールドの値と、
# 検出根拠が無いユニットにフィールドが付かないこと(fail-safe)、既存フィールドの不変、
# validate-manifest.sh の PASS を検証する。
self_test() {
  local script_path="$0"
  local script_dir
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  local tmp rc=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/extract-batch-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/src/jobs"
  cat > "$tmp/src/jobs/daily_summary.py" <<'EOF'
#!/usr/bin/env python3
import subprocess
from app.models import users

def main():
    subprocess.run(["python3", "jobs/monthly_report.py"])

if __name__ == '__main__':
    main()
EOF
  cat > "$tmp/src/jobs/monthly_report.py" <<'EOF'
#!/usr/bin/env python3
def main():
    pass

if __name__ == '__main__':
    main()
EOF

  cat > "$tmp/crontab.txt" <<'EOF'
0 3 * * * python3 /app/jobs/daily_summary.py
30 1 1 * * python3 /app/jobs/monthly_report.py
EOF

  jq -n --arg sourceDir "$tmp/src" '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: $sourceDir,
    unitKind: "table",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 1, unresolvedCount: 0},
    units: [
      {unitKey: "users-table", kind: "table", identifier: "users",
       sourceFile: "jobs/daily_summary.py", confidence: "high"}
    ]
  }' > "$tmp/table-manifest.json"

  local manifest="$tmp/batch-manifest.json"
  jq -n --arg sourceDir "$tmp/src" '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: $sourceDir,
    unitKind: "batch",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 2, unresolvedCount: 0},
    units: [
      {unitKey: "daily-summary", kind: "job", identifier: "jobs/daily_summary.py",
       unitNameGuess: "日次集計", sourceFile: "jobs/daily_summary.py", confidence: "high",
       fileCount: 1, detectionMethod: "manual"},
      {unitKey: "monthly-report", kind: "job", identifier: "jobs/monthly_report.py",
       unitNameGuess: "月次レポート", sourceFile: "jobs/monthly_report.py", confidence: "high",
       fileCount: 1, detectionMethod: "manual"}
    ]
  }' > "$manifest"

  local out="$tmp/out.json"
  if ! bash "$script_path" "$manifest" "$tmp/src" "$out" \
        --cron-file "$tmp/crontab.txt" --table-manifest "$tmp/table-manifest.json" >/dev/null 2>&1; then
    echo "  [FAIL] 実行: 抽出コマンド自体が失敗した" >&2
    echo "self-test FAIL" >&2
    return 1
  fi

  check() {
    local label="$1" filter="$2"
    if jq -e "$filter" "$out" >/dev/null 2>&1; then
      echo "  [PASS] $label"
    else
      echo "  [FAIL] $label" >&2
      rc=1
    fi
  }

  check "schedule: 毎日パターンのcron式と平易表記" \
    '.units[0].schedule == {cron: "0 3 * * *", readable: "毎日 3:00"}'
  check "schedule: 毎月パターンのcron式と平易表記" \
    '.units[1].schedule == {cron: "30 1 1 * *", readable: "毎月1日 1:30"}'
  check "targetTables: テーブルidentifierヒットでunitKey配列" \
    '.units[0].targetTables == ["users-table"]'
  check "targetTables: ヒット無しユニットにはフィールドを付けない(fail-safe)" \
    '.units[1] | has("targetTables") | not'
  check "execMethod: shebangからコマンド1行生成" \
    '.units[0].execMethod == "python3 jobs/daily_summary.py"'
  check "downstreamJobs: 呼び出し記述ヒットで後続ジョブのunitKey配列" \
    '.units[0].downstreamJobs == ["monthly-report"]'
  check "downstreamJobs: ヒット無しユニットにはフィールドを付けない(fail-safe)" \
    '.units[1] | has("downstreamJobs") | not'

  # 既存フィールド不変: 追加フィールドを取り除くと入力と完全一致する
  jq -S 'del(.units[].schedule, .units[].targetTables, .units[].downstreamJobs, .units[].execMethod)' \
    "$out" > "$tmp/stripped.json"
  jq -S . "$manifest" > "$tmp/orig.json"
  if diff -q "$tmp/stripped.json" "$tmp/orig.json" >/dev/null 2>&1; then
    echo "  [PASS] 既存フィールド不変: 追加フィールド除去後は入力マニフェストと完全一致"
  else
    echo "  [FAIL] 既存フィールド不変: 入力マニフェストとの差分が発生した" >&2
    rc=1
  fi

  if bash "$script_dir/../unit-list/validate-manifest.sh" "$out" --unit-kind batch >/dev/null 2>&1; then
    echo "  [PASS] validate-manifest: 拡張マニフェストが全項目PASS"
  else
    echo "  [FAIL] validate-manifest: 拡張マニフェストが検証FAILした" >&2
    rc=1
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

USAGE="Usage: extract-batch-metadata.sh <batch-manifest.json> <source-dir> <output.json> [--cron-file <path>] [--table-manifest <path>]"
MANIFEST="${1:?$USAGE}"
SOURCE_DIR="${2:?$USAGE}"
OUTPUT_JSON="${3:?$USAGE}"
shift 3

CRON_FILE=""
TABLE_MANIFEST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --cron-file)
      CRON_FILE="${2:-}"
      shift 2
      ;;
    --table-manifest)
      TABLE_MANIFEST="${2:-}"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found in PATH" >&2
  exit 1
fi
if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: manifest not found: $MANIFEST" >&2
  exit 1
fi
if ! jq empty "$MANIFEST" >/dev/null 2>&1; then
  echo "ERROR: invalid JSON: $MANIFEST" >&2
  exit 1
fi
if [ ! -d "$SOURCE_DIR" ]; then
  echo "ERROR: source-dir not found: $SOURCE_DIR" >&2
  exit 1
fi

# --- sourceFile の絶対パス解決(相対なら source-dir 起点) ---
resolve_path() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    *) printf '%s' "${SOURCE_DIR%/}/$1" ;;
  esac
}

# --- cron 式の平易表記変換(基本パターンのみ。変換不能なら cron 式をそのまま返す) ---
cron_readable() {
  local cron="$1" min hour dom mon dow hm
  read -r min hour dom mon dow <<<"$cron" || true
  local days=(日 月 火 水 木 金 土)
  if [[ "$min" =~ ^[0-9]+$ ]] && [[ "$hour" =~ ^[0-9]+$ ]]; then
    hm="$((10#$hour)):$(printf '%02d' "$((10#$min))")"
    if [ "$dom" = "*" ] && [ "$mon" = "*" ] && [ "$dow" = "*" ]; then
      printf '毎日 %s' "$hm"
      return 0
    fi
    if [ "$dom" = "*" ] && [ "$mon" = "*" ] && [[ "$dow" =~ ^[0-6]$ ]]; then
      printf '毎週%s曜 %s' "${days[$dow]}" "$hm"
      return 0
    fi
    if [[ "$dom" =~ ^[0-9]+$ ]] && [ "$mon" = "*" ] && [ "$dow" = "*" ]; then
      printf '毎月%s日 %s' "$((10#$dom))" "$hm"
      return 0
    fi
  fi
  if [[ "$min" =~ ^\*/[0-9]+$ ]] && [ "$hour" = "*" ] && [ "$dom" = "*" ] && [ "$mon" = "*" ] && [ "$dow" = "*" ]; then
    printf '%s分ごと' "${min#\*/}"
    return 0
  fi
  printf '%s' "$cron"
}

mkdir -p "$(dirname "$OUTPUT_JSON")"

units_tmp="$(mktemp "${TMPDIR:-/tmp}/extract-batch-units.XXXXXX")"
trap 'rm -f "$units_tmp"' EXIT

while IFS= read -r row; do
  [ -z "$row" ] && continue
  kind="$(jq -r '.kind // ""' <<<"$row")"
  if [ "$kind" = "unresolved" ]; then
    printf '%s\n' "$row" >> "$units_tmp"
    continue
  fi

  unit_key="$(jq -r '.unitKey // ""' <<<"$row")"
  identifier="$(jq -r '.identifier // ""' <<<"$row")"
  source_file="$(jq -r '.sourceFile // ""' <<<"$row")"
  src_path="$(resolve_path "$source_file")"
  aug="$row"

  # --- schedule: cron ファイルから identifier/unitKey を含む行の cron 式を抽出 ---
  if [ -n "$CRON_FILE" ] && [ -f "$CRON_FILE" ]; then
    match_line=""
    if [ -n "$identifier" ]; then
      match_line="$(grep -F -- "$identifier" "$CRON_FILE" 2>/dev/null | head -n 1 || true)"
    fi
    if [ -z "$match_line" ] && [ -n "$unit_key" ]; then
      match_line="$(grep -F -- "$unit_key" "$CRON_FILE" 2>/dev/null | head -n 1 || true)"
    fi
    if [ -n "$match_line" ]; then
      cron_expr="$(printf '%s\n' "$match_line" \
        | grep -oE '[0-9*,/-]+([[:space:]]+[0-9*,/-]+){4}' \
        | head -n 1 | sed -E 's/[[:space:]]+/ /g' || true)"
      if [ -n "$cron_expr" ] && [ "$(printf '%s\n' "$cron_expr" | wc -w | tr -d ' ')" -eq 5 ]; then
        readable="$(cron_readable "$cron_expr")"
        aug="$(jq --arg c "$cron_expr" --arg r "$readable" '. + {schedule: {cron: $c, readable: $r}}' <<<"$aug")"
      fi
    fi
  fi

  # --- targetTables: テーブルマニフェストの identifier を sourceFile 内で grep -F ---
  if [ -n "$TABLE_MANIFEST" ] && [ -f "$TABLE_MANIFEST" ] && [ -f "$src_path" ]; then
    tables_json="[]"
    while IFS=$'\t' read -r t_key t_id; do
      [ -z "$t_key" ] && continue
      [ -z "$t_id" ] && continue
      if grep -Fq -- "$t_id" "$src_path" 2>/dev/null; then
        tables_json="$(jq --arg k "$t_key" '. + [$k]' <<<"$tables_json")"
      fi
    done < <(jq -r '.units[]? | select(.kind != "unresolved") | [(.unitKey // ""), (.identifier // "")] | @tsv' "$TABLE_MANIFEST")
    if [ "$(jq 'length' <<<"$tables_json")" -gt 0 ]; then
      aug="$(jq --argjson t "$tables_json" '. + {targetTables: $t}' <<<"$aug")"
    fi
  fi

  # --- execMethod: shebang / __main__ ガードからコマンド 1 行を生成 ---
  if [ -f "$src_path" ]; then
    shebang="$(head -n 1 "$src_path" 2>/dev/null || true)"
    interp=""
    case "$shebang" in
      '#!'*)
        interp="$(printf '%s' "$shebang" | sed -E 's|^#![[:space:]]*||; s|^/usr/bin/env[[:space:]]+||; s|^[^[:space:]]*/||; s|[[:space:]].*$||')"
        ;;
    esac
    if [ -z "$interp" ] && grep -Eq "if __name__ == ['\"]__main__['\"]" "$src_path" 2>/dev/null; then
      interp="python3"
    fi
    if [ -n "$interp" ]; then
      rel="$source_file"
      case "$rel" in
        "${SOURCE_DIR%/}/"*) rel="${rel#"${SOURCE_DIR%/}/"}" ;;
      esac
      aug="$(jq --arg e "$interp $rel" '. + {execMethod: $e}' <<<"$aug")"
    fi
  fi

  # --- downstreamJobs: 呼び出し/enqueue 系キーワード行 × 他バッチ identifier/unitKey ---
  if [ -f "$src_path" ]; then
    downstream_json="[]"
    while IFS=$'\t' read -r o_key o_id; do
      [ -z "$o_key" ] && continue
      hit=0
      if [ -n "$o_id" ]; then
        if grep -E 'enqueue|delay|apply_async|subprocess|run\(|call|invoke|trigger|import' "$src_path" 2>/dev/null \
             | grep -Fq -- "$o_id"; then
          hit=1
        fi
      fi
      if [ "$hit" -eq 0 ]; then
        if grep -E 'enqueue|delay|apply_async|subprocess|run\(|call|invoke|trigger|import' "$src_path" 2>/dev/null \
             | grep -Fq -- "$o_key"; then
          hit=1
        fi
      fi
      if [ "$hit" -eq 1 ]; then
        downstream_json="$(jq --arg k "$o_key" '. + [$k]' <<<"$downstream_json")"
      fi
    done < <(jq -r --arg self "$unit_key" '.units[]? | select(.kind != "unresolved" and (.unitKey // "") != $self) | [(.unitKey // ""), (.identifier // "")] | @tsv' "$MANIFEST")
    if [ "$(jq 'length' <<<"$downstream_json")" -gt 0 ]; then
      aug="$(jq --argjson d "$downstream_json" '. + {downstreamJobs: $d}' <<<"$aug")"
    fi
  fi

  printf '%s\n' "$aug" >> "$units_tmp"
done < <(jq -c '.units[]?' "$MANIFEST")

jq --slurpfile newunits "$units_tmp" '.units = $newunits' "$MANIFEST" > "$OUTPUT_JSON"

echo "OK: wrote $OUTPUT_JSON" >&2
