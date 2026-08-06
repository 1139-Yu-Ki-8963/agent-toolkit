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
#   targetTables:   --table-manifest の全 unit の identifier を 1 つのパターンファイルにまとめ、
#                   sourceFile ごとに grep -oFf を 1 回だけ実行してヒットしたテーブルの unitKey を
#                   配列で格納する(0 件なら付けない)。判定の意味は「identifier を sourceFile 内で
#                   grep -F」と同じ(1 unit あたりの grep 起動をテーブル数分ではなく 1 回にする最適化)
#   execMethod:     sourceFile の shebang 行(#!...)からインタプリタ名を取得、shebang 不在でも
#                   if __name__ == '__main__' があれば python3 とみなし、
#                   「<インタプリタ> <sourceFile相対パス>」を生成(どちらも無ければ付けない)
#   downstreamJobs: 同マニフェストの全バッチの identifier/unitKey を 1 つのパターンファイルに
#                   まとめ、sourceFile 内で「呼び出し・enqueue 系キーワード
#                   (enqueue|delay|apply_async|subprocess|run(|call|invoke|trigger|import)を含む行」に
#                   対して grep -oFf を 1 回だけ実行してヒットしたものを格納する(自ユニット自身への
#                   ヒットは除外。0 件なら付けない。1 unit あたりの grep 起動を他バッチ数×2 回では
#                   なく 1 回にする最適化)
#
# 定義と実装の突合(1-129・detectionSummary.diagnostics.definitionWithoutImplementation):
#   --cron-file に記載された定期実行の登録エントリのうち、現マニフェストのどのユニットにも
#   対応しないもの(定義はあるが実装が存在しないエントリ)を検出し、検出できなかった事実として
#   比率を記録する(誤検出より見落としの可視化を優先。定義ファイルの記法網羅は求めない)。
#   検出手順(1ルールに固定。grep ベース):
#     1. --cron-file の各行から先頭 5 フィールド(cron 式)を sed で取り除き、残りの文字列から
#        拡張子付きファイルパストークン(grep -oE '[[:alnum:]_./-]+\.(py|sh|js|ts)' の最後の一致)を
#        ジョブ指定子として抽出する。5 フィールドを取り除けない行(コメント・空行等)は対象外とし
#        total に含めない
#     2. 現マニフェストの kind!=unresolved な全ユニットの identifier/sourceFile を 1 つの
#        パターンファイルにまとめ、ジョブ指定子がそのいずれかを部分文字列として含むか
#        grep -qFf で判定する(1 エントリ 1 回の grep 呼び出し)
#     3. 一致すれば「実装あり」、一致しなければ definitionWithoutImplementation の count に加算する
#   出力: count(実装なしエントリ数)/total(判定可能だった登録エントリ総数)/
#         ratio(count/total。total=0ならratio=0)/threshold(0.5固定)/warning(ratio>threshold)。
#   --cron-file 未指定時はキー自体を付けない(比較対象の定義ファイルが無いため)。
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
0 4 * * * python3 /app/jobs/nonexistent_job.py
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
  check "1-170: cron検出schedule は valueProvenance=measured" \
    '.units[0].valueProvenance.schedule == "measured" and .units[1].valueProvenance.schedule == "measured"'
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

  # 1-129: 定義(crontab)にはあるが実装(ユニット)が存在しないエントリの検出
  check "definitionWithoutImplementation診断: count=1(nonexistent_jobのみ実装なし)" \
    '.detectionSummary.diagnostics.definitionWithoutImplementation.count == 1'
  check "definitionWithoutImplementation診断: total=3(crontab全登録エントリ数)" \
    '.detectionSummary.diagnostics.definitionWithoutImplementation.total == 3'
  check "definitionWithoutImplementation診断: threshold=0.5" \
    '.detectionSummary.diagnostics.definitionWithoutImplementation.threshold == 0.5'
  check "definitionWithoutImplementation診断: 実装ありエントリは一覧本体(units)に載らない" \
    '[.units[].identifier] | index("jobs/nonexistent_job.py") | not'

  # 既存フィールド不変: 追加フィールドを取り除くと入力と完全一致する
  # (detectionSummary.diagnostics.definitionWithoutImplementation は本スクリプトが新規に追加するため、
  #  ユニット単位の追加4フィールドと同様に除去してから比較する)
  jq -S 'del(.units[].schedule, .units[].targetTables, .units[].downstreamJobs, .units[].execMethod, .units[].valueProvenance)
         | del(.detectionSummary.diagnostics)' \
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

  # 1-127: 複数ユニット・複数テーブルでも抽出結果が単純比較と一致すること
  # (targetTables: 一部テーブルのみヒットし他は除外、downstreamJobs: identifier一致と
  #  unitKey一致の双方を検出しつつ自ユニット自身への言及は加算しない)を、
  # パターンファイルへの単一 grep 実装で確認する。
  mkdir -p "$tmp/multi/jobs"
  cat > "$tmp/multi/jobs/job_a.py" <<'EOF'
#!/usr/bin/env python3
import subprocess
from app.models import orders  # orders テーブル参照
from app.models import invoices  # invoices テーブル参照

def main():
    print("running jobs/job_a.py")
    # avoid recursive trigger of jobs/job_a.py
    subprocess.run(["python3", "jobs/job_b.py"])
    subprocess.run(["python3", "job-c"])

if __name__ == '__main__':
    main()
EOF
  cat > "$tmp/multi/jobs/job_b.py" <<'EOF'
#!/usr/bin/env python3
def main():
    pass

if __name__ == '__main__':
    main()
EOF
  cat > "$tmp/multi/jobs/job_c.py" <<'EOF'
#!/usr/bin/env python3
def main():
    pass

if __name__ == '__main__':
    main()
EOF

  jq -n --arg sourceDir "$tmp/multi" '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: $sourceDir,
    unitKind: "table",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 3, unresolvedCount: 0},
    units: [
      {unitKey: "orders-table", kind: "table", identifier: "orders", sourceFile: "jobs/job_a.py", confidence: "high"},
      {unitKey: "users-table2", kind: "table", identifier: "users", sourceFile: "jobs/job_a.py", confidence: "high"},
      {unitKey: "invoices-table", kind: "table", identifier: "invoices", sourceFile: "jobs/job_a.py", confidence: "high"}
    ]
  }' > "$tmp/multi/table-manifest.json"

  local multi_manifest="$tmp/multi/batch-manifest.json" multi_out="$tmp/multi/out.json"
  jq -n --arg sourceDir "$tmp/multi" '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: $sourceDir,
    unitKind: "batch",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 3, unresolvedCount: 0},
    units: [
      {unitKey: "job-a", kind: "job", identifier: "jobs/job_a.py", unitNameGuess: "ジョブA",
       sourceFile: "jobs/job_a.py", confidence: "high", fileCount: 1, detectionMethod: "manual"},
      {unitKey: "job-b", kind: "job", identifier: "jobs/job_b.py", unitNameGuess: "ジョブB",
       sourceFile: "jobs/job_b.py", confidence: "high", fileCount: 1, detectionMethod: "manual"},
      {unitKey: "job-c", kind: "job", identifier: "job-c", unitNameGuess: "ジョブC",
       sourceFile: "jobs/job_c.py", confidence: "high", fileCount: 1, detectionMethod: "manual"}
    ]
  }' > "$multi_manifest"

  if ! bash "$script_path" "$multi_manifest" "$tmp/multi" "$multi_out" \
        --table-manifest "$tmp/multi/table-manifest.json" >/dev/null 2>&1; then
    echo "  [FAIL] 1-127: 複数ユニット抽出コマンド自体が失敗した" >&2
    rc=1
  else
    if jq -e '.units[] | select(.unitKey=="job-a") | .targetTables == ["invoices-table","orders-table"]' \
        "$multi_out" >/dev/null 2>&1; then
      echo "  [PASS] 1-127 targetTables: 単一grepでも一部テーブルのみヒットし他は除外"
    else
      echo "  [FAIL] 1-127 targetTables: 期待値と不一致" >&2
      rc=1
    fi
    if jq -e '.units[] | select(.unitKey=="job-a") | .downstreamJobs == ["job-b","job-c"]' \
        "$multi_out" >/dev/null 2>&1; then
      echo "  [PASS] 1-127 downstreamJobs: identifier一致とunitKey一致の双方を検出し自ユニットは除外"
    else
      echo "  [FAIL] 1-127 downstreamJobs: 期待値と不一致" >&2
      rc=1
    fi
  fi

  # 1-127-scale: 500ユニット規模でも実行時間の上限内で完了すること。旧実装であれば
  # targetTables/downstreamJobs のループがユニット数の2乗に比例したgrep起動を伴う規模。
  local scale_dir="$tmp/scale" n padded
  mkdir -p "$scale_dir/jobs"
  for ((n = 1; n <= 500; n++)); do
    padded="$(printf '%04d' "$n")"
    printf '#!/usr/bin/env python3\ndef main():\n    pass\n\nif __name__ == "__main__":\n    main()\n' \
      > "$scale_dir/jobs/job_${padded}.py"
  done

  local scale_units="$scale_dir/units.jsonl" scale_table_units="$scale_dir/table-units.jsonl"
  : > "$scale_units"
  : > "$scale_table_units"
  for ((n = 1; n <= 500; n++)); do
    padded="$(printf '%04d' "$n")"
    printf '{"unitKey":"job-%d","kind":"job","identifier":"jobs/job_%s.py","unitNameGuess":"ジョブ%d","sourceFile":"jobs/job_%s.py","confidence":"high","fileCount":1,"detectionMethod":"manual"}\n' \
      "$n" "$padded" "$n" "$padded" >> "$scale_units"
    printf '{"unitKey":"table-%d","kind":"table","identifier":"table_%d","sourceFile":"jobs/job_0001.py","confidence":"high"}\n' \
      "$n" "$n" >> "$scale_table_units"
  done

  local scale_batch_manifest="$scale_dir/batch-manifest.json" scale_table_manifest="$scale_dir/table-manifest.json" \
    scale_out="$scale_dir/out.json"
  jq -n --arg sourceDir "$scale_dir" --slurpfile units "$scale_units" '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: $sourceDir,
    unitKind: "batch",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 500, unresolvedCount: 0},
    units: $units
  }' > "$scale_batch_manifest"
  jq -n --arg sourceDir "$scale_dir" --slurpfile units "$scale_table_units" '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: $sourceDir,
    unitKind: "table",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 500, unresolvedCount: 0},
    units: $units
  }' > "$scale_table_manifest"

  if bash "$script_path" "$scale_batch_manifest" "$scale_dir" "$scale_out" \
        --table-manifest "$scale_table_manifest" >/dev/null 2>&1; then
    echo "  [PASS] 1-127-scale: 500ユニット規模でも抽出コマンドが終了コード0で完了"
  else
    echo "  [FAIL] 1-127-scale: 500ユニット規模の抽出コマンドが完了しなかった" >&2
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

# --- 非UTF-8原本の走査対応(改善課題1-131): detect-encoding.sh の走査ヘルパーを読み込む ---
_EXTRACT_BATCH_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../detect-encoding.sh
source "$_EXTRACT_BATCH_SCRIPT_DIR/../detect-encoding.sh"
SCAN_WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/extract-batch-metadata-scan.XXXXXX")"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/extract-batch-work.XXXXXX")"
trap 'rm -rf "$work_dir" "$SCAN_WORKDIR"' EXIT
units_tmp="$work_dir/units.jsonl"
: > "$units_tmp"

# --- targetTables 用: --table-manifest の identifier↔unitKey 対応表とパターンファイルを
#     ループの外で 1 回だけ構築する(1 ユニットあたり grep を 1 回で済ませるため) ---
table_map="$work_dir/table-map.tsv"   # 1列目=identifier, 2列目=unitKey
table_pat="$work_dir/table-ids.txt"   # grep -oFf 用パターン(identifier のみ・重複排除)
: > "$table_map"
: > "$table_pat"
if [ -n "$TABLE_MANIFEST" ] && [ -f "$TABLE_MANIFEST" ]; then
  jq -r '.units[]? | select(.kind != "unresolved") | [(.identifier // ""), (.unitKey // "")] | @tsv' "$TABLE_MANIFEST" \
    | awk -F'\t' 'NF==2 && $1 != "" && $2 != ""' > "$table_map"
  cut -f1 "$table_map" | sort -u > "$table_pat"
fi

# --- downstreamJobs 用: 同マニフェスト内の全バッチの unitKey↔(identifier/unitKey) 対応表と
#     パターンファイルをループの外で 1 回だけ構築する。自ユニットの除外はパターンファイルではなく
#     照合結果側で行う(パターンファイルは全ユニット共通で 1 回だけ作るため) ---
other_map="$work_dir/downstream-map.tsv"   # 1列目=unitKey, 2列目=identifierまたはunitKey
other_pat="$work_dir/downstream-ids.txt"   # grep -oFf 用パターン(identifier/unitKeyの和集合・重複排除)
jq -r '.units[]? | select(.kind != "unresolved") | select((.unitKey // "") != "") |
    ({key: .unitKey, val: .unitKey},
     (if (.identifier // "") != "" then {key: .unitKey, val: .identifier} else empty end))
  | [.key, .val] | @tsv' "$MANIFEST" > "$other_map"
cut -f2 "$other_map" | sort -u > "$other_pat"

# --- definitionWithoutImplementation(1-129): --cron-file の登録エントリと現ユニットの突合 ---
diagnostics_json="{}"
if [ -n "$CRON_FILE" ] && [ -f "$CRON_FILE" ]; then
  cron_scan_file="$(to_utf8_for_scan "$CRON_FILE" "$SCAN_WORKDIR")"
  unit_refs_pat="$work_dir/unit-refs.txt"
  jq -r '.units[]? | select(.kind != "unresolved") | (.identifier // ""), (.sourceFile // "")' "$MANIFEST" \
    | awk 'NF' > "$unit_refs_pat"
  def_total=0
  def_missing=0
  while IFS= read -r cron_line; do
    rest="$(printf '%s\n' "$cron_line" | sed -E 's/^[[:space:]]*[^[:space:]]+([[:space:]]+[^[:space:]]+){4}[[:space:]]*//')"
    [ "$rest" = "$cron_line" ] && continue
    job_spec="$(printf '%s\n' "$rest" | grep -oE '[[:alnum:]_./-]+\.(py|sh|js|ts)' | tail -n 1 || true)"
    [ -z "$job_spec" ] && continue
    def_total=$((def_total + 1))
    if [ -s "$unit_refs_pat" ] && printf '%s\n' "$job_spec" | grep -qFf "$unit_refs_pat"; then
      continue
    fi
    def_missing=$((def_missing + 1))
  done < "$cron_scan_file"
  diagnostics_json="$(jq -n --argjson c "$def_missing" --argjson t "$def_total" '
    {definitionWithoutImplementation:
      {count: $c, total: $t,
       ratio: (if $t > 0 then ($c / $t) else 0 end),
       threshold: 0.5,
       warning: (if $t > 0 then (($c / $t) > 0.5) else false end)}}
  ')"
fi

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
  # scan_src_path: 非UTF-8原本ならUTF-8一時コピー(改善課題1-131)。src_path自体は出力・相対パス
  # 算出に使うため変更しない。走査(grep)には常にscan_src_pathを使う
  scan_src_path=""
  [ -f "$src_path" ] && scan_src_path="$(to_utf8_for_scan "$src_path" "$SCAN_WORKDIR")"

  # --- schedule: cron ファイルから identifier/unitKey を含む行の cron 式を抽出 ---
  if [ -n "$CRON_FILE" ] && [ -f "$CRON_FILE" ]; then
    match_line=""
    if [ -n "$identifier" ]; then
      match_line="$(grep -F -- "$identifier" "$cron_scan_file" 2>/dev/null | head -n 1 || true)"
    fi
    if [ -z "$match_line" ] && [ -n "$unit_key" ]; then
      match_line="$(grep -F -- "$unit_key" "$cron_scan_file" 2>/dev/null | head -n 1 || true)"
    fi
    if [ -n "$match_line" ]; then
      cron_expr="$(printf '%s\n' "$match_line" \
        | grep -oE '[0-9*,/-]+([[:space:]]+[0-9*,/-]+){4}' \
        | head -n 1 | sed -E 's/[[:space:]]+/ /g' || true)"
      if [ -n "$cron_expr" ] && [ "$(printf '%s\n' "$cron_expr" | wc -w | tr -d ' ')" -eq 5 ]; then
        readable="$(cron_readable "$cron_expr")"
        aug="$(jq --arg c "$cron_expr" --arg r "$readable" '. + {schedule: {cron: $c, readable: $r}}' <<<"$aug")"
        aug="$(jq '. + {valueProvenance: ((.valueProvenance // {}) + {schedule: "measured"})}' <<<"$aug")"
      fi
    fi
  fi

  # --- targetTables: パターンファイルへの単一 grep でヒットした identifier から unitKey を解決 ---
  if [ -s "$table_pat" ] && [ -f "$src_path" ]; then
    tables_json="[]"
    hit_ids="$(grep -oFf "$table_pat" "$scan_src_path" 2>/dev/null | sort -u || true)"
    if [ -n "$hit_ids" ]; then
      while IFS= read -r hid; do
        [ -z "$hid" ] && continue
        while IFS=$'\t' read -r m_id m_key; do
          [ "$m_id" = "$hid" ] || continue
          tables_json="$(jq --arg k "$m_key" '. + [$k]' <<<"$tables_json")"
        done < "$table_map"
      done <<<"$hit_ids"
      tables_json="$(jq 'unique' <<<"$tables_json")"
    fi
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
    if [ -z "$interp" ] && grep -Eq "if __name__ == ['\"]__main__['\"]" "$scan_src_path" 2>/dev/null; then
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

  # --- downstreamJobs: 呼び出し/enqueue 系キーワード行に対する単一 grep で他バッチを解決 ---
  if [ -f "$src_path" ] && [ -s "$other_pat" ]; then
    downstream_json="[]"
    hit_vals="$(grep -E 'enqueue|delay|apply_async|subprocess|run\(|call|invoke|trigger|import' "$scan_src_path" 2>/dev/null \
                | grep -oFf "$other_pat" 2>/dev/null | sort -u || true)"
    if [ -n "$hit_vals" ]; then
      while IFS= read -r hval; do
        [ -z "$hval" ] && continue
        while IFS=$'\t' read -r m_key m_val; do
          [ "$m_val" = "$hval" ] || continue
          [ "$m_key" = "$unit_key" ] && continue
          downstream_json="$(jq --arg k "$m_key" 'if index($k) then . else . + [$k] end' <<<"$downstream_json")"
        done < "$other_map"
      done <<<"$hit_vals"
      downstream_json="$(jq 'unique' <<<"$downstream_json")"
    fi
    if [ "$(jq 'length' <<<"$downstream_json")" -gt 0 ]; then
      aug="$(jq --argjson d "$downstream_json" '. + {downstreamJobs: $d}' <<<"$aug")"
    fi
  fi

  printf '%s\n' "$aug" >> "$units_tmp"
done < <(jq -c '.units[]?' "$MANIFEST")

jq --slurpfile newunits "$units_tmp" --argjson diag "$diagnostics_json" '
  .units = $newunits
  | if ($diag | length) > 0 then .detectionSummary.diagnostics = (.detectionSummary.diagnostics // {}) + $diag else . end
' "$MANIFEST" > "$OUTPUT_JSON"

echo "OK: wrote $OUTPUT_JSON" >&2
