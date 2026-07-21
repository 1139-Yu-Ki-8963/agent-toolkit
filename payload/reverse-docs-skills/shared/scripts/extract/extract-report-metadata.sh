#!/usr/bin/env bash
# 抽出エンジン(shared/scripts/extract): 帳票種別マニフェストへのメタデータ抽出。
# 入力マニフェスト(unitKind=report)の units[] を走査し、検出できたフィールドだけを追加した
# 拡張マニフェストを出力する。既存フィールドは一切変更しない。検出根拠が弱い値
# (複数形式に同時ヒット等)は出力しない(誤った値より欠落を優先する fail-safe)。
#
# Usage: extract-report-metadata.sh <report-manifest.json> <source-dir> <output.json>
#        extract-report-metadata.sh --self-test
#
# 出力フィールド(スキーマ正本: shared/references/manifest-schema-extensions.md「reports」節):
#   format  string (PDF / CSV / Excel)
#   trigger string (画面 / バッチ の 2 値)
#
# 検出ヒューリスティック一覧(すべて grep ベース):
#   format:  sourceFile 内を帳票ライブラリ・拡張子で grep
#              - grep -Ei 'reportlab|fpdf|pdf'        → PDF
#              - grep -E  'csv\.writer|to_csv'        → CSV
#              - grep -Ei 'openpyxl|xlsxwriter'       → Excel
#            ちょうど 1 形式にヒットした場合のみ出力する(複数形式ヒット・0 件は根拠が
#            弱いため付けない = fail-safe)
#   trigger: sourceFile のパスに jobs/・batch/・batches/ セグメントが含まれれば「バッチ」、
#            それ以外は「画面」(パスは常に得られるため kind!=unresolved の全行に付与)
#
# 出力 JSON は unit-list/validate-manifest.sh --unit-kind report で検証可能であること
# (self-test 内で validate-manifest.sh も実行して PASS を確認する)。

set -euo pipefail

# --- --self-test モード ---
# mktemp -d に最小フィクスチャ(PDF 帳票 / CSV 出力 / 複数形式混在の 3 本)を生成し、
# format の値・複数ヒット時の欠落(fail-safe)・trigger の 2 値判定・既存フィールドの不変・
# validate-manifest.sh の PASS を検証する。
self_test() {
  local script_path="$0"
  local script_dir
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  local tmp rc=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/extract-report-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/src/jobs" "$tmp/src/views"
  cat > "$tmp/src/jobs/sales_report.py" <<'EOF'
from reportlab.pdfgen import canvas

def render(path):
    c = canvas.Canvas(path)
    c.save()
EOF
  cat > "$tmp/src/views/export_users.py" <<'EOF'
def export(df, buf):
    df.to_csv(buf)
EOF
  cat > "$tmp/src/views/mixed_output.py" <<'EOF'
from fpdf import FPDF

def export(df, buf):
    df.to_csv(buf)
EOF

  local manifest="$tmp/report-manifest.json"
  jq -n --arg sourceDir "$tmp/src" '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: $sourceDir,
    unitKind: "report",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 3, unresolvedCount: 0},
    units: [
      {unitKey: "sales-report", kind: "report", identifier: "jobs/sales_report.py",
       unitNameGuess: "売上帳票", sourceFile: "jobs/sales_report.py", confidence: "high",
       fileCount: 1, detectionMethod: "manual"},
      {unitKey: "users-export", kind: "report", identifier: "views/export_users.py",
       unitNameGuess: "ユーザー出力", sourceFile: "views/export_users.py", confidence: "high",
       fileCount: 1, detectionMethod: "manual"},
      {unitKey: "mixed-output", kind: "report", identifier: "views/mixed_output.py",
       unitNameGuess: "混在出力", sourceFile: "views/mixed_output.py", confidence: "medium",
       fileCount: 1, detectionMethod: "manual"}
    ]
  }' > "$manifest"

  local out="$tmp/out.json"
  if ! bash "$script_path" "$manifest" "$tmp/src" "$out" >/dev/null 2>&1; then
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

  check "format: reportlabヒットでPDF" '.units[0].format == "PDF"'
  check "format: to_csvヒットでCSV" '.units[1].format == "CSV"'
  check "format: 複数形式ヒットではフィールドを付けない(fail-safe)" \
    '.units[2] | has("format") | not'
  check "trigger: jobs/配下はバッチ" '.units[0].trigger == "バッチ"'
  check "trigger: jobs/batch配下以外は画面" \
    '.units[1].trigger == "画面" and .units[2].trigger == "画面"'

  # 既存フィールド不変: 追加フィールドを取り除くと入力と完全一致する
  jq -S 'del(.units[].format, .units[].trigger)' "$out" > "$tmp/stripped.json"
  jq -S . "$manifest" > "$tmp/orig.json"
  if diff -q "$tmp/stripped.json" "$tmp/orig.json" >/dev/null 2>&1; then
    echo "  [PASS] 既存フィールド不変: 追加フィールド除去後は入力マニフェストと完全一致"
  else
    echo "  [FAIL] 既存フィールド不変: 入力マニフェストとの差分が発生した" >&2
    rc=1
  fi

  if bash "$script_dir/../unit-list/validate-manifest.sh" "$out" --unit-kind report >/dev/null 2>&1; then
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

USAGE="Usage: extract-report-metadata.sh <report-manifest.json> <source-dir> <output.json>"
MANIFEST="${1:?$USAGE}"
SOURCE_DIR="${2:?$USAGE}"
OUTPUT_JSON="${3:?$USAGE}"
if [ $# -gt 3 ]; then
  echo "ERROR: unknown argument: $4" >&2
  exit 1
fi

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

mkdir -p "$(dirname "$OUTPUT_JSON")"

units_tmp="$(mktemp "${TMPDIR:-/tmp}/extract-report-units.XXXXXX")"
trap 'rm -f "$units_tmp"' EXIT

while IFS= read -r row; do
  [ -z "$row" ] && continue
  kind="$(jq -r '.kind // ""' <<<"$row")"
  if [ "$kind" = "unresolved" ]; then
    printf '%s\n' "$row" >> "$units_tmp"
    continue
  fi

  source_file="$(jq -r '.sourceFile // ""' <<<"$row")"
  src_path="$(resolve_path "$source_file")"
  aug="$row"

  # --- format: 帳票ライブラリ・拡張子の grep。ちょうど 1 形式ヒット時のみ出力 ---
  if [ -f "$src_path" ]; then
    fmt=""
    fmt_count=0
    if grep -Eiq 'reportlab|fpdf|pdf' "$src_path" 2>/dev/null; then
      fmt="PDF"
      fmt_count=$((fmt_count + 1))
    fi
    if grep -Eq 'csv\.writer|to_csv' "$src_path" 2>/dev/null; then
      fmt="CSV"
      fmt_count=$((fmt_count + 1))
    fi
    if grep -Eiq 'openpyxl|xlsxwriter' "$src_path" 2>/dev/null; then
      fmt="Excel"
      fmt_count=$((fmt_count + 1))
    fi
    if [ "$fmt_count" -eq 1 ]; then
      aug="$(jq --arg f "$fmt" '. + {format: $f}' <<<"$aug")"
    fi
  fi

  # --- trigger: sourceFile のパスセグメントで 2 値判定 ---
  if [ -n "$source_file" ]; then
    case "/$source_file" in
      */jobs/* | */batch/* | */batches/*) trigger="バッチ" ;;
      *) trigger="画面" ;;
    esac
    aug="$(jq --arg t "$trigger" '. + {trigger: $t}' <<<"$aug")"
  fi

  printf '%s\n' "$aug" >> "$units_tmp"
done < <(jq -c '.units[]?' "$MANIFEST")

jq --slurpfile newunits "$units_tmp" '.units = $newunits' "$MANIFEST" > "$OUTPUT_JSON"

echo "OK: wrote $OUTPUT_JSON" >&2
