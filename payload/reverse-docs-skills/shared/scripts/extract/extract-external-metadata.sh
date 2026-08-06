#!/usr/bin/env bash
# 抽出エンジン(shared/scripts/extract): 外部連携種別マニフェストへのメタデータ抽出。
# 入力マニフェスト(unitKind=external)の units[] を走査し、検出できたフィールドだけを追加した
# 拡張マニフェストを出力する。既存フィールドは一切変更しない。検出根拠が弱い値
# (送信・受信の両パターンに同時ヒット等)は出力しない(誤った値より欠落を優先する fail-safe)。
#
# Usage: extract-external-metadata.sh <external-manifest.json> <source-dir> <output.json>
#            [--definition-file <path>] [--declaration-candidates <path>]
#        extract-external-metadata.sh --self-test
#
# 出力フィールド(スキーマ正本: shared/references/manifest-schema-extensions.md「externals」節):
#   direction  string (送信 / 受信 の 2 値)
#   protocol   string (REST / SFTP / Webhook 等)
#   authMethod string (APIキー / OAuth2 / Basic 等)
#
# 検出ヒューリスティック一覧(すべて grep ベース):
#   direction:  送信 = grep -E 'requests\.(get|post|put|patch|delete)|httpx|fetch\(|axios|paramiko|SFTPClient'
#               受信 = grep -E '@app\.(get|post|put|patch|delete)|@router\.(get|post|put|patch|delete)|@app\.route'
#               送信のみヒット → 送信、受信のみヒット → 受信。
#               両方ヒット・どちらも 0 件は根拠が弱いため付けない(fail-safe)
#   protocol:   優先順に判定(先勝ち)
#                 - grep -Eiq 'paramiko|sftp'                        → SFTP
#                 - grep -iq  'webhook'                              → Webhook
#                 - grep -Eq  'requests\.|httpx|fetch\(|axios|urllib' → REST
#               どれにもヒットしなければ付けない
#   authMethod: 優先順に判定(先勝ち)
#                 - grep -Eq  'Authorization.*Bearer|OAuth'          → OAuth2
#                 - grep -Eiq 'api_key|X-API-Key|apikey'             → APIキー
#                 - grep -Eiq 'HTTPBasicAuth|basic_auth'             → Basic
#               どれにもヒットしなければ付けない
#
# 定義と実装の突合(1-129・detectionSummary.diagnostics.definitionWithoutImplementation):
#   --definition-file(連携先定義ファイル。1行1エントリ、`#`始まりはコメント扱いで除外)の各行が、
#   source-dir 配下のいずれかのファイルで実際に参照されているかを検出する(定義ファイルの記法
#   網羅は求めない。1ルールに固定)。
#     1. 定義ファイルの非コメント・非空行をパターンファイルにする
#     2. source-dir 配下(拡張子 py/js/ts/json/yml/yaml に限定)を grep -rhoFf で 1 回だけ走査し、
#        ヒットしたエントリ文字列の集合を得る(全エントリ×全ファイルの総当りgrepを避ける最適化)
#     3. パターンファイルの各行がヒット集合に含まれるかを照合し、含まれないものを
#        definitionWithoutImplementation の count に加算する
#   出力: count/total(判定対象の定義エントリ数)/ratio/threshold(0.5固定)/warning。
#   --definition-file 未指定時はキー自体を付けない。
#
# 宣言のみと実呼び出しの区別(1-139・detectionSummary.diagnostics.declarationOnly):
#   --declaration-candidates(通信モジュールの読み込み宣言を持つ候補ファイルパス一覧。1行1パス。
#   source-dir 起点の相対パスまたは絶対パス)の各ファイルについて、宣言(IMPORT_PATTERN)はあるが
#   実呼び出し(既存の SEND_PATTERN/RECV_PATTERN)が無いものを検出する。
#   宣言のみのファイルは units[] に含めない(Phase 2 の抽出時点で除外する運用が前提)。
#   出力: count(宣言のみのファイル数)/total(候補ファイル総数)/ratio/threshold(0.5固定)/warning。
#   --declaration-candidates 未指定時はキー自体を付けない。
#
# 出力 JSON は unit-list/validate-manifest.sh --unit-kind external で検証可能であること
# (self-test 内で validate-manifest.sh も実行して PASS を確認する)。

set -euo pipefail

# --- --self-test モード ---
# mktemp -d に最小フィクスチャ(送信 REST+OAuth2 / 受信 Webhook+APIキー / SFTP の 3 本)を生成し、
# direction/protocol/authMethod の値・検出根拠が無い場合の欠落(fail-safe)・既存フィールドの不変・
# validate-manifest.sh の PASS を検証する。
self_test() {
  local script_path="$0"
  local script_dir
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  local tmp rc=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/extract-external-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/src/clients" "$tmp/src/hooks" "$tmp/src/transfer"
  cat > "$tmp/src/clients/payment_client.py" <<'EOF'
import requests

def send_payment(url, token):
    headers = {"Authorization": "Bearer " + token}
    return requests.post(url, json={}, headers=headers)
EOF
  cat > "$tmp/src/hooks/receive_payment.py" <<'EOF'
from fastapi import FastAPI, Request

app = FastAPI()

@app.post("/webhook/payment")
def receive_payment(request: Request):
    key = request.headers.get("X-API-Key")
    return {"ok": True}
EOF
  cat > "$tmp/src/transfer/bank_upload.py" <<'EOF'
import paramiko

def upload(host, path):
    client = paramiko.SSHClient()
    sftp = client.open_sftp()
    sftp.put(path, "/inbox/")
EOF

  local manifest="$tmp/external-manifest.json"
  jq -n --arg sourceDir "$tmp/src" '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: $sourceDir,
    unitKind: "external",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 3, unresolvedCount: 0},
    units: [
      {unitKey: "payment-api-client", kind: "external", identifier: "clients/payment_client.py",
       unitNameGuess: "決済API連携", sourceFile: "clients/payment_client.py", confidence: "high",
       fileCount: 1, detectionMethod: "manual"},
      {unitKey: "payment-webhook-receiver", kind: "external", identifier: "hooks/receive_payment.py",
       unitNameGuess: "決済Webhook受信", sourceFile: "hooks/receive_payment.py", confidence: "high",
       fileCount: 1, detectionMethod: "manual"},
      {unitKey: "bank-sftp-upload", kind: "external", identifier: "transfer/bank_upload.py",
       unitNameGuess: "銀行SFTP連携", sourceFile: "transfer/bank_upload.py", confidence: "high",
       fileCount: 1, detectionMethod: "manual"}
    ]
  }' > "$manifest"

  # --- 1-129: 定義ファイル(連携先定義)に実装が無いエントリを検出するフィクスチャ ---
  cat > "$tmp/src/clients/payment_gateway_consumer.py" <<'EOF'
CONSUMES_TARGET = "payment-gateway"
EOF
  local definition_file="$tmp/definitions.txt"
  cat > "$definition_file" <<'EOF'
# 連携先定義(コメント行は除外対象)
payment-gateway
unused-shipping-api
EOF

  # --- 1-139: 読み込み宣言のみで実呼び出しが無いファイルを検出するフィクスチャ ---
  cat > "$tmp/src/clients/unused_client.py" <<'EOF'
import requests

UNUSED_BASE_URL = "https://example.invalid"
EOF
  local declaration_candidates="$tmp/declaration-candidates.txt"
  cat > "$declaration_candidates" <<EOF
clients/payment_client.py
clients/unused_client.py
EOF

  local out="$tmp/out.json"
  if ! bash "$script_path" "$manifest" "$tmp/src" "$out" \
        --definition-file "$definition_file" --declaration-candidates "$declaration_candidates" >/dev/null 2>&1; then
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

  check "direction: requests.postヒットで送信" '.units[0].direction == "送信"'
  check "direction: @app.postヒットで受信" '.units[1].direction == "受信"'
  check "direction: paramikoクライアントは送信" '.units[2].direction == "送信"'
  check "protocol: HTTPクライアントのみはREST" '.units[0].protocol == "REST"'
  check "protocol: webhook文字列でWebhook" '.units[1].protocol == "Webhook"'
  check "protocol: paramiko/sftpでSFTP" '.units[2].protocol == "SFTP"'
  check "authMethod: Authorization BearerでOAuth2" '.units[0].authMethod == "OAuth2"'
  check "authMethod: X-API-KeyでAPIキー" '.units[1].authMethod == "APIキー"'
  check "authMethod: 検出根拠が無ければフィールドを付けない(fail-safe)" \
    '.units[2] | has("authMethod") | not'

  # 1-129: 定義ファイルにはあるが実装から参照されないエントリの検出
  check "definitionWithoutImplementation診断: count=1(unused-shipping-apiのみ実装なし)" \
    '.detectionSummary.diagnostics.definitionWithoutImplementation.count == 1'
  check "definitionWithoutImplementation診断: total=2(コメント行を除いた定義エントリ数)" \
    '.detectionSummary.diagnostics.definitionWithoutImplementation.total == 2'

  # 1-139: 読み込み宣言のみで実呼び出しの無いファイルの検出
  check "declarationOnly診断: count=1(unused_client.pyのみ宣言のみ)" \
    '.detectionSummary.diagnostics.declarationOnly.count == 1'
  check "declarationOnly診断: total=2(候補ファイル総数)" \
    '.detectionSummary.diagnostics.declarationOnly.total == 2'
  check "宣言のみのファイルは一覧本体(units)に載らない" \
    '[.units[].sourceFile] | index("clients/unused_client.py") | not'

  # 既存フィールド不変: 追加フィールドを取り除くと入力と完全一致する
  # (detectionSummary.diagnostics.definitionWithoutImplementation/declarationOnly は本スクリプトが
  #  新規に追加するため、ユニット単位の追加3フィールドと同様に除去してから比較する)
  jq -S 'del(.units[].direction, .units[].protocol, .units[].authMethod)
         | del(.detectionSummary.diagnostics)' "$out" > "$tmp/stripped.json"
  jq -S . "$manifest" > "$tmp/orig.json"
  if diff -q "$tmp/stripped.json" "$tmp/orig.json" >/dev/null 2>&1; then
    echo "  [PASS] 既存フィールド不変: 追加フィールド除去後は入力マニフェストと完全一致"
  else
    echo "  [FAIL] 既存フィールド不変: 入力マニフェストとの差分が発生した" >&2
    rc=1
  fi

  if bash "$script_dir/../unit-list/validate-manifest.sh" "$out" --unit-kind external >/dev/null 2>&1; then
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

USAGE="Usage: extract-external-metadata.sh <external-manifest.json> <source-dir> <output.json> [--definition-file <path>] [--declaration-candidates <path>]"
MANIFEST="${1:?$USAGE}"
SOURCE_DIR="${2:?$USAGE}"
OUTPUT_JSON="${3:?$USAGE}"
shift 3

DEFINITION_FILE=""
DECLARATION_CANDIDATES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --definition-file) DEFINITION_FILE="${2:-}"; shift 2 ;;
    --declaration-candidates) DECLARATION_CANDIDATES="${2:-}"; shift 2 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
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

mkdir -p "$(dirname "$OUTPUT_JSON")"

units_tmp="$(mktemp "${TMPDIR:-/tmp}/extract-external-units.XXXXXX")"

# --- 非UTF-8原本の走査対応(改善課題1-131): detect-encoding.sh の走査ヘルパーを読み込む ---
_EXTRACT_EXTERNAL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../detect-encoding.sh
source "$_EXTRACT_EXTERNAL_SCRIPT_DIR/../detect-encoding.sh"
SCAN_WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/extract-external-metadata-scan.XXXXXX")"

trap 'rm -f "$units_tmp"; rm -rf "$SCAN_WORKDIR"' EXIT

SEND_PATTERN='requests\.(get|post|put|patch|delete)|httpx|fetch\(|axios|paramiko|SFTPClient'
RECV_PATTERN='@app\.(get|post|put|patch|delete)|@router\.(get|post|put|patch|delete)|@app\.route'
# 通信モジュールの読み込み宣言(実呼び出しの有無は問わない。1-139 declarationOnly 判定専用)
IMPORT_PATTERN='import[[:space:]]+requests|from[[:space:]]+requests|import[[:space:]]+httpx|from[[:space:]]+httpx|import[[:space:]]+paramiko|from[[:space:]]+paramiko|require\((\x27|")axios|import[^;]*axios'

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

  if [ -f "$src_path" ]; then
    # scan_path: 非UTF-8原本ならUTF-8一時コピー(改善課題1-131)。src_pathは出力に使う
    # パスのため変更しない。走査(grep)には常にscan_pathを使う
    scan_path="$(to_utf8_for_scan "$src_path" "$SCAN_WORKDIR")"

    # --- direction: 送信クライアント記述 / 受け口定義の排他判定 ---
    send_hit=0
    recv_hit=0
    if grep -Eq "$SEND_PATTERN" "$scan_path" 2>/dev/null; then
      send_hit=1
    fi
    if grep -Eq "$RECV_PATTERN" "$scan_path" 2>/dev/null; then
      recv_hit=1
    fi
    if [ "$send_hit" -eq 1 ] && [ "$recv_hit" -eq 0 ]; then
      aug="$(jq '. + {direction: "送信"}' <<<"$aug")"
    elif [ "$send_hit" -eq 0 ] && [ "$recv_hit" -eq 1 ]; then
      aug="$(jq '. + {direction: "受信"}' <<<"$aug")"
    fi

    # --- protocol: SFTP > Webhook > REST の優先順で先勝ち判定 ---
    protocol=""
    if grep -Eiq 'paramiko|sftp' "$scan_path" 2>/dev/null; then
      protocol="SFTP"
    elif grep -iq 'webhook' "$scan_path" 2>/dev/null; then
      protocol="Webhook"
    elif grep -Eq 'requests\.|httpx|fetch\(|axios|urllib' "$scan_path" 2>/dev/null; then
      protocol="REST"
    fi
    if [ -n "$protocol" ]; then
      aug="$(jq --arg p "$protocol" '. + {protocol: $p}' <<<"$aug")"
    fi

    # --- authMethod: OAuth2 > APIキー > Basic の優先順で先勝ち判定 ---
    auth_method=""
    if grep -Eq 'Authorization.*Bearer|OAuth' "$scan_path" 2>/dev/null; then
      auth_method="OAuth2"
    elif grep -Eiq 'api_key|X-API-Key|apikey' "$scan_path" 2>/dev/null; then
      auth_method="APIキー"
    elif grep -Eiq 'HTTPBasicAuth|basic_auth' "$scan_path" 2>/dev/null; then
      auth_method="Basic"
    fi
    if [ -n "$auth_method" ]; then
      aug="$(jq --arg a "$auth_method" '. + {authMethod: $a}' <<<"$aug")"
    fi
  fi

  printf '%s\n' "$aug" >> "$units_tmp"
done < <(jq -c '.units[]?' "$MANIFEST")

diagnostics_json="{}"

# --- definitionWithoutImplementation(1-129): --definition-file の各エントリが source-dir 配下の
#     実装コードから参照されているかを、パターンファイルへの単一 grep -rhoFf 走査で判定する ---
if [ -n "$DEFINITION_FILE" ] && [ -f "$DEFINITION_FILE" ]; then
  def_entries="$(mktemp "${TMPDIR:-/tmp}/extract-external-defs.XXXXXX")"
  grep -vE '^[[:space:]]*(#|$)' "$DEFINITION_FILE" > "$def_entries" || true
  def_total="$(wc -l < "$def_entries" | tr -d ' ')"
  def_missing=0
  if [ "$def_total" -gt 0 ]; then
    # ディレクトリ横断の再帰走査は1ファイルずつのUTF-8変換を適用できないため、
    # LC_ALL=C でバイト単位走査にし、非UTF-8原本でも「不正なマルチバイト列」警告と
    # 誤ったバイナリ判定を避ける(改善課題1-131。エントリはASCII識別子のためバイト一致で足りる)。
    hit_entries="$(LC_ALL=C grep -rhoFf "$def_entries" \
      --include='*.py' --include='*.js' --include='*.ts' --include='*.json' --include='*.yml' --include='*.yaml' \
      "$SOURCE_DIR" 2>/dev/null | sort -u || true)"
    while IFS= read -r entry; do
      [ -z "$entry" ] && continue
      if ! printf '%s\n' "$hit_entries" | grep -qFx -- "$entry"; then
        def_missing=$((def_missing + 1))
      fi
    done < "$def_entries"
  fi
  rm -f "$def_entries"
  diagnostics_json="$(jq --argjson c "$def_missing" --argjson t "$def_total" '
    . + {definitionWithoutImplementation:
      {count: $c, total: $t,
       ratio: (if $t > 0 then ($c / $t) else 0 end),
       threshold: 0.5,
       warning: (if $t > 0 then (($c / $t) > 0.5) else false end)}}
  ' <<<"$diagnostics_json")"
fi

# --- declarationOnly(1-139): --declaration-candidates の各ファイルが、通信モジュールの読み込み
#     宣言を持ちながら実呼び出し(SEND_PATTERN/RECV_PATTERN)を持たないかを判定する ---
if [ -n "$DECLARATION_CANDIDATES" ] && [ -f "$DECLARATION_CANDIDATES" ]; then
  decl_total=0
  decl_only=0
  while IFS= read -r cand; do
    [ -z "$cand" ] && continue
    decl_total=$((decl_total + 1))
    cand_path="$(resolve_path "$cand")"
    [ -f "$cand_path" ] || continue
    if grep -Eq "$IMPORT_PATTERN" "$cand_path" 2>/dev/null \
      && ! grep -Eq "$SEND_PATTERN" "$cand_path" 2>/dev/null \
      && ! grep -Eq "$RECV_PATTERN" "$cand_path" 2>/dev/null; then
      decl_only=$((decl_only + 1))
    fi
  done < "$DECLARATION_CANDIDATES"
  diagnostics_json="$(jq --argjson c "$decl_only" --argjson t "$decl_total" '
    . + {declarationOnly:
      {count: $c, total: $t,
       ratio: (if $t > 0 then ($c / $t) else 0 end),
       threshold: 0.5,
       warning: (if $t > 0 then (($c / $t) > 0.5) else false end)}}
  ' <<<"$diagnostics_json")"
fi

jq --slurpfile newunits "$units_tmp" --argjson diag "$diagnostics_json" '
  .units = $newunits
  | if ($diag | length) > 0 then .detectionSummary.diagnostics = (.detectionSummary.diagnostics // {}) + $diag else . end
' "$MANIFEST" > "$OUTPUT_JSON"

echo "OK: wrote $OUTPUT_JSON" >&2
