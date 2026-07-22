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
#   trigger: 2 段判定(パスは常に得られるため kind!=unresolved の全行に付与)
#            (a) sourceFile のパスに jobs/・batch/・batches/ セグメントが含まれれば「バッチ」
#            (b) それ以外は、<source-dir> 内の jobs 系ディレクトリ(jobs/・batch/・batches/)の
#                ファイルから当該モジュールが import されているかを grep し、
#                されていれば「バッチ」、いなければ「画面」
#                (バッチから import される帳票モジュール、例: app/reports/sales_csv.py を
#                 app/jobs/daily_report.py が import しているケースの誤判定を防ぐ)
#
# 出力 JSON は unit-list/validate-manifest.sh --unit-kind report で検証可能であること
# (self-test 内で validate-manifest.sh も実行して PASS を確認する)。

set -euo pipefail

# --- --self-test モード ---
# mktemp -d に最小フィクスチャ(PDF 帳票 / CSV 出力 / 複数形式混在 / jobs から import される
# バッチ帳票の 4 本)を生成し、format の値・複数ヒット時の欠落(fail-safe)・trigger の
# 2 段判定(パス判定 + import 判定)・既存フィールドの不変・validate-manifest.sh の PASS を検証する。
self_test() {
  local script_path="$0"
  local script_dir
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  local tmp rc=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/extract-report-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/src/jobs" "$tmp/src/views" "$tmp/src/reports"
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
  # jobs 配下ではないが、jobs のバッチから import される帳票モジュール(trigger=バッチ 期待)
  cat > "$tmp/src/reports/sales_csv.py" <<'EOF'
def export(df, buf):
    df.to_csv(buf)
EOF
  cat > "$tmp/src/jobs/daily_report.py" <<'EOF'
from reports.sales_csv import export

def run():
    export(None, None)
EOF

  local manifest="$tmp/report-manifest.json"
  jq -n --arg sourceDir "$tmp/src" '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: $sourceDir,
    unitKind: "report",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 4, unresolvedCount: 0},
    units: [
      {unitKey: "sales-report", kind: "report", identifier: "jobs/sales_report.py",
       unitNameGuess: "売上帳票", sourceFile: "jobs/sales_report.py", confidence: "high",
       fileCount: 1, detectionMethod: "manual"},
      {unitKey: "users-export", kind: "report", identifier: "views/export_users.py",
       unitNameGuess: "ユーザー出力", sourceFile: "views/export_users.py", confidence: "high",
       fileCount: 1, detectionMethod: "manual"},
      {unitKey: "mixed-output", kind: "report", identifier: "views/mixed_output.py",
       unitNameGuess: "混在出力", sourceFile: "views/mixed_output.py", confidence: "medium",
       fileCount: 1, detectionMethod: "manual"},
      {unitKey: "sales-csv", kind: "report", identifier: "reports/sales_csv.py",
       unitNameGuess: "売上CSV", sourceFile: "reports/sales_csv.py", confidence: "high",
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
  check "trigger: jobs/batch配下以外かつjobsからのimportなしは画面" \
    '.units[1].trigger == "画面" and .units[2].trigger == "画面"'
  check "trigger: jobs配下外でもjobsのバッチからimportされる帳票はバッチ" \
    '.units[3].trigger == "バッチ" and .units[3].format == "CSV"'

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

# --- ERE メタ文字エスケープ ---
escape_ere() { printf '%s' "$1" | sed -E 's/[.[\^$*+?(){}|\\]/\\&/g'; }

# --- trigger 判定(b 段): jobs 系ディレクトリのファイルから import されているか ---
# $1 = sourceFile(source-dir 相対 or 絶対の .py パス)。import されていれば exit 0。
imported_from_jobs_dirs() {
  local rel="$1"
  rel="${rel#"${SOURCE_DIR%/}/"}"
  local mod="${rel%.py}"
  [ "$mod" = "$rel" ] && return 1   # .py 以外は import 判定不能 → 画面扱い
  local base="${mod##*/}"
  [ -z "$base" ] && return 1

  local jobs_dirs=()
  while IFS= read -r d; do
    [ -n "$d" ] && jobs_dirs+=("$d")
  done < <(find "$SOURCE_DIR" -type d \( -name jobs -o -name batch -o -name batches \) 2>/dev/null)
  [ "${#jobs_dirs[@]}" -eq 0 ] && return 1

  local base_esc dotted alts="" s
  base_esc="$(escape_ere "$base")"
  dotted="$(printf '%s' "$mod" | tr '/' '.')"

  # ドット区切りサフィックス(2 セグメント以上)を alternation に集める
  # 例: app.reports.sales_csv → app\.reports\.sales_csv|reports\.sales_csv
  s="$dotted"
  while [ "${s#*.}" != "$s" ]; do
    alts="${alts:+$alts|}$(escape_ere "$s")"
    s="${s#*.}"
  done

  # パターン1: import a.b.c / from a.b.c import x(ドット付きモジュール参照)
  if [ -n "$alts" ] && \
     grep -rqE "(^|[^A-Za-z0-9_.])(${alts})([^A-Za-z0-9_]|\$)" "${jobs_dirs[@]}" 2>/dev/null; then
    return 0
  fi

  # パターン2: from <...親ディレクトリ名> import <...base...> / トップレベルは from|import <base>
  local parent="${mod%/*}" pat2
  if [ "$parent" != "$mod" ] && [ -n "$parent" ]; then
    pat2="from[[:space:]]+([A-Za-z0-9_.]*\\.)?$(escape_ere "${parent##*/}")[[:space:]]+import[[:space:]]+(.*[^A-Za-z0-9_])?${base_esc}([^A-Za-z0-9_]|\$)"
  else
    pat2="(^|[^A-Za-z0-9_.])(from|import)[[:space:]]+${base_esc}([^A-Za-z0-9_]|\$)"
  fi
  grep -rqE "$pat2" "${jobs_dirs[@]}" 2>/dev/null
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

  # --- trigger: 2 段判定。(a) パスが jobs 系配下 → バッチ
  #     (b) それ以外は jobs 系ディレクトリからの import 有無で バッチ / 画面 ---
  if [ -n "$source_file" ]; then
    case "/$source_file" in
      */jobs/* | */batch/* | */batches/*) trigger="バッチ" ;;
      *)
        if imported_from_jobs_dirs "$source_file"; then
          trigger="バッチ"
        else
          trigger="画面"
        fi
        ;;
    esac
    aug="$(jq --arg t "$trigger" '. + {trigger: $t}' <<<"$aug")"
  fi

  printf '%s\n' "$aug" >> "$units_tmp"
done < <(jq -c '.units[]?' "$MANIFEST")

jq --slurpfile newunits "$units_tmp" '.units = $newunits' "$MANIFEST" > "$OUTPUT_JSON"

echo "OK: wrote $OUTPUT_JSON" >&2
