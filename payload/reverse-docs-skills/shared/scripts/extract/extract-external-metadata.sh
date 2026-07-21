#!/usr/bin/env bash
# 抽出エンジン(shared/scripts/extract): 外部連携種別マニフェストへのメタデータ抽出。
# 入力マニフェスト(unitKind=external)の units[] を走査し、検出できたフィールドだけを追加した
# 拡張マニフェストを出力する。既存フィールドは一切変更しない。検出根拠が弱い値
# (送信・受信の両パターンに同時ヒット等)は出力しない(誤った値より欠落を優先する fail-safe)。
#
# Usage: extract-external-metadata.sh <external-manifest.json> <source-dir> <output.json>
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

  # 既存フィールド不変: 追加フィールドを取り除くと入力と完全一致する
  jq -S 'del(.units[].direction, .units[].protocol, .units[].authMethod)' "$out" > "$tmp/stripped.json"
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

USAGE="Usage: extract-external-metadata.sh <external-manifest.json> <source-dir> <output.json>"
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

units_tmp="$(mktemp "${TMPDIR:-/tmp}/extract-external-units.XXXXXX")"
trap 'rm -f "$units_tmp"' EXIT

SEND_PATTERN='requests\.(get|post|put|patch|delete)|httpx|fetch\(|axios|paramiko|SFTPClient'
RECV_PATTERN='@app\.(get|post|put|patch|delete)|@router\.(get|post|put|patch|delete)|@app\.route'

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
    # --- direction: 送信クライアント記述 / 受け口定義の排他判定 ---
    send_hit=0
    recv_hit=0
    if grep -Eq "$SEND_PATTERN" "$src_path" 2>/dev/null; then
      send_hit=1
    fi
    if grep -Eq "$RECV_PATTERN" "$src_path" 2>/dev/null; then
      recv_hit=1
    fi
    if [ "$send_hit" -eq 1 ] && [ "$recv_hit" -eq 0 ]; then
      aug="$(jq '. + {direction: "送信"}' <<<"$aug")"
    elif [ "$send_hit" -eq 0 ] && [ "$recv_hit" -eq 1 ]; then
      aug="$(jq '. + {direction: "受信"}' <<<"$aug")"
    fi

    # --- protocol: SFTP > Webhook > REST の優先順で先勝ち判定 ---
    protocol=""
    if grep -Eiq 'paramiko|sftp' "$src_path" 2>/dev/null; then
      protocol="SFTP"
    elif grep -iq 'webhook' "$src_path" 2>/dev/null; then
      protocol="Webhook"
    elif grep -Eq 'requests\.|httpx|fetch\(|axios|urllib' "$src_path" 2>/dev/null; then
      protocol="REST"
    fi
    if [ -n "$protocol" ]; then
      aug="$(jq --arg p "$protocol" '. + {protocol: $p}' <<<"$aug")"
    fi

    # --- authMethod: OAuth2 > APIキー > Basic の優先順で先勝ち判定 ---
    auth_method=""
    if grep -Eq 'Authorization.*Bearer|OAuth' "$src_path" 2>/dev/null; then
      auth_method="OAuth2"
    elif grep -Eiq 'api_key|X-API-Key|apikey' "$src_path" 2>/dev/null; then
      auth_method="APIキー"
    elif grep -Eiq 'HTTPBasicAuth|basic_auth' "$src_path" 2>/dev/null; then
      auth_method="Basic"
    fi
    if [ -n "$auth_method" ]; then
      aug="$(jq --arg a "$auth_method" '. + {authMethod: $a}' <<<"$aug")"
    fi
  fi

  printf '%s\n' "$aug" >> "$units_tmp"
done < <(jq -c '.units[]?' "$MANIFEST")

jq --slurpfile newunits "$units_tmp" '.units = $newunits' "$MANIFEST" > "$OUTPUT_JSON"

echo "OK: wrote $OUTPUT_JSON" >&2
