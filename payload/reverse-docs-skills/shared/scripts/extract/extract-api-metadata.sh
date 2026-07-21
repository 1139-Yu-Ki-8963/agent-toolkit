#!/usr/bin/env bash
# 抽出エンジン: APIマニフェストへのメタデータ付与(拡張マニフェスト生成)。
# 入力マニフェストの既存フィールドは一切変更せず、抽出できたフィールドだけを units[] の
# 各要素へ追加した拡張マニフェストを出力する。検出根拠が弱い値は出力しない(誤った値より
# 欠落を優先する fail-safe。欠落は任意フィールドの不在として扱われる)。
#
# Usage: extract-api-metadata.sh <api-manifest.json> <source-dir> <output.json> \
#          [--screen-manifest <extended-screen-manifest.json>] [--table-manifest <table-manifest.json>]
#        extract-api-metadata.sh --self-test
#
# 入力契約:
#   <api-manifest.json>   : unitKind=api のユニットマニフェスト(validate-manifest.sh PASS 済み想定)
#   <source-dir>          : 原本コードのルート(現状は sourceFile が絶対/相対パスで解決できることの
#                           確認にのみ使用。sourceFile が相対パスの場合は source-dir 起点で解決する)
#   --screen-manifest     : relatedApis 抽出済みの拡張画面マニフェスト(callers 逆引きに使用。省略可)
#   --table-manifest      : テーブルマニフェスト(targetTables 抽出に使用。省略可)
#
# 出力契約:
#   <output.json> に拡張マニフェストを書き出す。追加されうるフィールド
#   (スキーマ正本: shared/references/manifest-schema-extensions.md「apis(API)」節):
#     method       : string   GET/POST/PUT/PATCH/DELETE のいずれか
#     authRequired : boolean  認証の要否
#     callers      : string[] 呼び出し元画面の screenKey 配列(空なら付けない)
#     targetTables : string[] 参照テーブルの unitKey 配列(空なら付けない)
#     ioSummary    : string   「<入力> → <出力>」形式の 1 行要約
#   既存フィールドと衝突した場合は既存値を保持する(上書きしない)。
#   出力は validate-manifest.sh <output.json> --unit-kind api で検証可能。
#
# 検出ヒューリスティック一覧(すべて grep/sed ベース):
#   1. method       : identifier の先頭語(空白区切り)が GET/POST/PUT/PATCH/DELETE に完全一致する
#                     場合のみ採用。それ以外は付けない
#   2. authRequired : identifier のパス部(先頭メソッド語を除去した残り)を sourceFile 内で
#                     grep -nF し、最初のヒット行の前 3 行〜後 20 行を「エンドポイント近傍窓」とする。
#                     窓内に認証パターン
#                       Depends(get_current_user / @login_required / requireAuth / verify_token / IsAuthenticated
#                     があれば true。窓内に認証除外パターン(単語境界付き)
#                       AllowAny / public
#                     があれば false。パス部がヒットしない・どちらのパターンも無い場合は付けない
#   3. callers      : --screen-manifest の screens[](または units[])の relatedApis[] が、この API の
#                     unitKey / identifier / パス部のいずれかに一致する要素の screenKey を収集。
#                     0 件なら付けない
#   4. targetTables : --table-manifest の各ユニット(kind=unresolved を除く)の identifier(物理名)を
#                     sourceFile 全体で grep -qwF(単語境界・固定文字列)し、ヒットしたテーブルの
#                     unitKey を収集。0 件なら付けない
#   5. ioSummary    : エンドポイント近傍窓内から
#                       出力: response_model=<Name>(FastAPI) または ): Promise<Name>(TypeScript)
#                       入力: 型注釈 : <Name> のうち接尾辞 Create/Update/Request/Input/Payload/Body/Form/Schema
#                             を持つもの(Pydantic リクエストモデル風)
#                     を sed -nE で抽出し、出力が取れた場合のみ「<入力> → <出力>」を付ける。
#                     入力が取れない場合の入力部は「なし」とする。出力が取れなければ付けない

set -euo pipefail

AUTH_POSITIVE_ERE='Depends\(get_current_user|@login_required|requireAuth|verify_token|IsAuthenticated'
AUTH_NEGATIVE_ERE='(^|[^A-Za-z0-9_])(AllowAny|public)([^A-Za-z0-9_]|$)'

# --- --self-test モード ---
# FastAPI 風フィクスチャ(認証付き GET /api/users が users テーブルを SELECT + 認証情報の無い
# POST /api/ping)で、method/authRequired/callers/targetTables/ioSummary の抽出値と、
# 根拠が無い場合のフィールド欠落(fail-safe)、既存フィールド無変更、validate-manifest.sh PASS を検証する。
self_test() {
  local script_path="$0"
  local script_dir
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  local validate="$script_dir/../unit-list/validate-manifest.sh"
  local tmp rc=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/extract-api-metadata-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/src/api"

  # 認証付きエンドポイント(users テーブルを SELECT)
  cat > "$tmp/src/api/users.py" <<'EOF'
from fastapi import APIRouter, Depends
router = APIRouter()

@router.get("/api/users", response_model=UserList)
def list_users(current_user=Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.execute("SELECT id, name FROM users")
    return rows
EOF

  # 認証情報もモデルも無いエンドポイント(fail-safe による欠落を検証)
  cat > "$tmp/src/api/ping.py" <<'EOF'
from fastapi import APIRouter
router = APIRouter()

@router.post("/api/ping")
def ping():
    return {"ok": True}
EOF

  # APIマニフェスト(2 ユニット)
  local api_manifest="$tmp/api-manifest.json"
  jq -n \
    --arg sourceDir "$tmp/src" \
    --arg usersFile "$tmp/src/api/users.py" \
    --arg pingFile "$tmp/src/api/ping.py" \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      unitKind: "api",
      strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
      detectionSummary: {unitCount: 2, unresolvedCount: 0},
      units: [
        {unitKey: "users-list", kind: "endpoint", identifier: "GET /api/users",
         unitNameGuess: "ユーザー一覧取得", sourceFile: $usersFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"},
        {unitKey: "ping", kind: "endpoint", identifier: "POST /api/ping",
         unitNameGuess: "疎通確認", sourceFile: $pingFile,
         confidence: "high", fileCount: 1, detectionMethod: "manual"}
      ]
    }' > "$api_manifest"

  # 拡張画面マニフェスト(relatedApis が users-list を参照)
  local screen_manifest="$tmp/screen-manifest.json"
  jq -n '{
    unitKind: "screen",
    screens: [
      {screenKey: "user-admin", relatedApis: ["users-list"]},
      {screenKey: "dashboard", relatedApis: ["orders-list"]}
    ]
  }' > "$screen_manifest"

  # テーブルマニフェスト(users テーブル)
  local table_manifest="$tmp/table-manifest.json"
  jq -n '{
    unitKind: "table",
    units: [
      {unitKey: "users", kind: "table", identifier: "users"},
      {unitKey: "orders", kind: "table", identifier: "orders"}
    ]
  }' > "$table_manifest"

  local out="$tmp/api-manifest-extended.json"
  if ! bash "$script_path" "$api_manifest" "$tmp/src" "$out" \
       --screen-manifest "$screen_manifest" --table-manifest "$table_manifest" >/dev/null 2>&1; then
    echo "  [FAIL] 実行: 抽出コマンド自体が失敗した" >&2
    echo "self-test FAIL" >&2
    return 1
  fi

  check() {
    local label="$1" jq_expr="$2"
    if [ "$(jq -r "$jq_expr" "$out")" = "true" ]; then
      echo "  [PASS] $label"
    else
      echo "  [FAIL] $label" >&2
      rc=1
    fi
  }

  check "method: GET /api/users から GET を抽出" '.units[0].method == "GET"'
  check "authRequired: Depends(get_current_user) 検出で true" '.units[0].authRequired == true'
  check "callers: relatedApis 逆引きで [\"user-admin\"]" '.units[0].callers == ["user-admin"]'
  check "targetTables: users テーブルの grep ヒットで [\"users\"]" '.units[0].targetTables == ["users"]'
  check "ioSummary: response_model=UserList から生成" '.units[0].ioSummary == "なし → UserList"'
  check "method: POST /api/ping から POST を抽出" '.units[1].method == "POST"'
  check "fail-safe: 根拠の無い authRequired/callers/targetTables/ioSummary は欠落" \
    '.units[1] | (has("authRequired") or has("callers") or has("targetTables") or has("ioSummary")) | not'

  # 既存フィールド無変更: 追加フィールドを除去すると入力と完全一致する
  local stripped="$tmp/stripped.json" expected="$tmp/expected.json"
  jq -S '.units = [.units[] | del(.method, .authRequired, .callers, .targetTables, .ioSummary)]' "$out" > "$stripped"
  jq -S . "$api_manifest" > "$expected"
  if diff -q "$stripped" "$expected" >/dev/null 2>&1; then
    echo "  [PASS] 既存フィールド無変更: 追加フィールド除去後に入力マニフェストと完全一致"
  else
    echo "  [FAIL] 既存フィールド無変更: 入力マニフェストとの差分が発生した" >&2
    rc=1
  fi

  if bash "$validate" "$out" --unit-kind api >/dev/null 2>&1; then
    echo "  [PASS] validate-manifest.sh: 拡張マニフェストが --unit-kind api で PASS"
  else
    echo "  [FAIL] validate-manifest.sh: 拡張マニフェストの検証が FAIL" >&2
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

USAGE="Usage: extract-api-metadata.sh <api-manifest.json> <source-dir> <output.json> [--screen-manifest <json>] [--table-manifest <json>]"
MANIFEST="${1:?$USAGE}"
SOURCE_DIR="${2:?$USAGE}"
OUTPUT="${3:?$USAGE}"
shift 3 || true

SCREEN_MANIFEST=""
TABLE_MANIFEST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --screen-manifest) SCREEN_MANIFEST="${2:-}"; shift 2 ;;
    --table-manifest)  TABLE_MANIFEST="${2:-}";  shift 2 ;;
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
if [ ! -d "$SOURCE_DIR" ]; then
  echo "ERROR: source-dir not found: $SOURCE_DIR" >&2
  exit 1
fi
if [ -n "$SCREEN_MANIFEST" ] && [ ! -f "$SCREEN_MANIFEST" ]; then
  echo "ERROR: screen-manifest not found: $SCREEN_MANIFEST" >&2
  exit 1
fi
if [ -n "$TABLE_MANIFEST" ] && [ ! -f "$TABLE_MANIFEST" ]; then
  echo "ERROR: table-manifest not found: $TABLE_MANIFEST" >&2
  exit 1
fi

# sourceFile を絶対パスへ解決する(相対パスなら source-dir 起点)。解決できなければ空を返す
resolve_source_file() {
  local sf="$1"
  [ -z "$sf" ] && return 0
  if [ -f "$sf" ]; then
    printf '%s' "$sf"
  elif [ -f "$SOURCE_DIR/$sf" ]; then
    printf '%s' "$SOURCE_DIR/$sf"
  fi
}

# identifier のパス部を sourceFile 内で grep -nF し、最初のヒット行の前3行〜後20行を出力する。
# ヒットしない場合は何も出力しない
endpoint_window() {
  local src="$1" path="$2"
  local line start
  [ -z "$path" ] && return 0
  line="$(grep -nF -- "$path" "$src" 2>/dev/null | head -1 | cut -d: -f1 || true)"
  [ -z "$line" ] && return 0
  start=$(( line > 3 ? line - 3 : 1 ))
  sed -n "${start},$((line + 20))p" "$src"
}

patches_jsonl="$(mktemp "${TMPDIR:-/tmp}/extract-api-patches.XXXXXX")"
patches_json="$(mktemp "${TMPDIR:-/tmp}/extract-api-patches-arr.XXXXXX")"
trap 'rm -f "$patches_jsonl" "$patches_json"' EXIT

while IFS= read -r row; do
  [ -z "$row" ] && continue
  unit_key="$(jq -r '.unitKey // ""' <<<"$row")"
  identifier="$(jq -r '.identifier // ""' <<<"$row")"
  source_file_raw="$(jq -r '.sourceFile // ""' <<<"$row")"
  src_file="$(resolve_source_file "$source_file_raw")"

  # --- 1. method: identifier の先頭語 ---
  method=""
  api_path="$identifier"
  head_word="${identifier%% *}"
  case "$head_word" in
    GET|POST|PUT|PATCH|DELETE)
      method="$head_word"
      api_path="${identifier#* }"
      ;;
  esac

  # --- エンドポイント近傍窓(authRequired / ioSummary 共用) ---
  window=""
  if [ -n "$src_file" ]; then
    window="$(endpoint_window "$src_file" "$api_path" || true)"
  fi

  # --- 2. authRequired: 近傍窓内の認証/認証除外パターン ---
  auth=""
  if [ -n "$window" ]; then
    if printf '%s\n' "$window" | grep -qE -- "$AUTH_POSITIVE_ERE"; then
      auth="true"
    elif printf '%s\n' "$window" | grep -qE -- "$AUTH_NEGATIVE_ERE"; then
      auth="false"
    fi
  fi

  # --- 3. callers: 拡張画面マニフェストの relatedApis 逆引き ---
  callers_json="[]"
  if [ -n "$SCREEN_MANIFEST" ]; then
    callers_json="$(jq -c \
      --arg uk "$unit_key" --arg ident "$identifier" --arg path "$api_path" \
      '[ (.screens // .units // [])[]
         | select((.relatedApis // []) | any(. == $uk or . == $ident or . == $path))
         | .screenKey // empty ]' "$SCREEN_MANIFEST")"
  fi

  # --- 4. targetTables: テーブル物理名の sourceFile 全体 grep ---
  tables_json="[]"
  if [ -n "$TABLE_MANIFEST" ] && [ -n "$src_file" ]; then
    while IFS= read -r trow; do
      [ -z "$trow" ] && continue
      t_key="$(jq -r '.unitKey // ""' <<<"$trow")"
      t_ident="$(jq -r '.identifier // ""' <<<"$trow")"
      if [ -z "$t_key" ] || [ -z "$t_ident" ]; then
        continue
      fi
      if grep -qwF -- "$t_ident" "$src_file" 2>/dev/null; then
        tables_json="$(jq -c --arg k "$t_key" '. + [$k]' <<<"$tables_json")"
      fi
    done < <(jq -c '(.units // [])[] | select(.kind != "unresolved")' "$TABLE_MANIFEST")
  fi

  # --- 5. ioSummary: 近傍窓内のレスポンス/リクエストモデル名 ---
  io_summary=""
  if [ -n "$window" ]; then
    resp="$(printf '%s\n' "$window" \
      | sed -nE 's/.*response_model *= *([A-Za-z_][A-Za-z0-9_]*).*/\1/p' | head -1)"
    if [ -z "$resp" ]; then
      resp="$(printf '%s\n' "$window" \
        | sed -nE 's/.*\) *: *Promise<([A-Za-z_][A-Za-z0-9_]*)>.*/\1/p' | head -1)"
    fi
    if [ -n "$resp" ]; then
      req="$(printf '%s\n' "$window" \
        | sed -nE 's/.*: *([A-Z][A-Za-z0-9_]*(Create|Update|Request|Input|Payload|Body|Form|Schema))([^A-Za-z0-9_].*)?$/\1/p' | head -1)"
      io_summary="${req:-なし} → ${resp}"
    fi
  fi

  # --- 抽出できたフィールドだけを持つ patch オブジェクトを 1 行追記 ---
  jq -nc \
    --arg method "$method" --arg auth "$auth" --arg io "$io_summary" \
    --argjson callers "$callers_json" --argjson tables "$tables_json" \
    '{}
     + (if $method != "" then {method: $method} else {} end)
     + (if $auth == "true" then {authRequired: true} elif $auth == "false" then {authRequired: false} else {} end)
     + (if ($callers | length) > 0 then {callers: $callers} else {} end)
     + (if ($tables | length) > 0 then {targetTables: $tables} else {} end)
     + (if $io != "" then {ioSummary: $io} else {} end)' >> "$patches_jsonl"
done < <(jq -c '(.units // [])[]' "$MANIFEST")

jq -s '.' "$patches_jsonl" > "$patches_json"

mkdir -p "$(dirname "$OUTPUT")"

# 既存フィールドは patch より優先する((patch + 原本) の合成順で原本値が常に勝つ)
jq --slurpfile P "$patches_json" \
  '.units = ([(.units // []), $P[0]] | transpose | map(((.[1]) // {}) + .[0]))' \
  "$MANIFEST" > "$OUTPUT"

echo "OK: wrote $OUTPUT" >&2
