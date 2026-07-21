#!/usr/bin/env bash
# 抽出エンジン: 画面マニフェスト(screen-manifest.json)へのメタデータ追加抽出。
# 入力マニフェストの既存フィールドは一切変更せず、ヒューリスティックで抽出できた
# フィールドだけを screens[] の各要素に追加した拡張マニフェストを出力する。
# 検出根拠が弱い値は出力しない(誤った値より欠落を優先する fail-safe)。
#
# Usage: extract-screen-metadata.sh <screen-manifest.json> <source-dir> <output.json> \
#          [--api-manifest <api-manifest.json>] [--design-docs-dir <dir>]
#
# 入力契約:
#   <screen-manifest.json> : validate-manifest.sh --unit-kind screen をPASSする画面マニフェスト
#   <source-dir>           : 原本ソースのルート。screens[].entryFile 等の相対パスの解決基点
#   --api-manifest         : unitKind=api のマニフェスト。relatedApis を unitKey に解決する
#   --design-docs-dir      : 設計書リポジトリ側のディレクトリ。designDocStatus の判定元
#
# 出力契約(<output.json>):
#   入力マニフェストと同一構造 + screens[] 各要素への追加フィールド。
#   スキーマ正本: shared/references/manifest-schema-extensions.md「screens(画面)」表。
#   出力は validate-manifest.sh --unit-kind screen で検証可能(全8項目PASS)。
#
# 追加フィールドと検出ヒューリスティック(何を grep するか):
#   category      : route の先頭 prefix 判定。route が "/admin" または "/admin/..." なら「管理」、
#                   それ以外の非空 route なら「一般」。route 不在(unresolved 等)なら付けない
#   permissions   : 構成ファイル(files[] があればそれ、無ければ entryFile/sourceFile/mainFile)内を grep:
#                     - requireRole('x') / requireRole("x")
#                     - hasRole('x') / hasRole("x")
#                     - roles: ['x', 'y'] / roles: ["x"]
#                     - @RolesAllowed("x") / @RolesAllowed({"x","y"})
#                   からロール名を収集。検出なし かつ category=管理 なら ["admin"] を推定値として
#                   付与、category=一般 で検出なしなら [] を付与。category 不明かつ検出なしなら付けない
#   relatedApis   : 構成ファイル内の fetch( / axios. / apiClient. を含む行から
#                   '/api/...' のパス文字列(クォート囲み)を収集(クエリ文字列 ?以降 は除去)。
#                   --api-manifest 指定時は units[].identifier のパス部(空白区切りで '/' 始まりの
#                   トークン)と完全一致で突合して unitKey に解決する(解決できないパスは捨てる)。
#                   未指定なら収集パスをそのまま格納。収集 0 件ならフィールド自体を付けない
#   designDocStatus: --design-docs-dir 配下に <screenKey> 名のフォルダ/ファイル
#                   (または <screenKey>.* ファイル)が実在すれば「着手済」、無ければ「未着手」。
#                   オプション未指定ならフィールド自体を付けない
#   sourceHash    : 構成ファイル(実在するもの)を列挙順に連結した sha256 の先頭12桁。
#                   実在ファイル 0 件ならフィールド自体を付けない
#
# 全追加フィールドは任意フィールド(manifest-schema-extensions.md の段階的移行方針)。
# 抽出できないフィールドは付けない = 任意フィールドの欠落として扱われる。

set -euo pipefail

# ---------------------------------------------------------------------------
# sha256 コマンド解決(macOS: shasum -a 256 / Linux: sha256sum)
# ---------------------------------------------------------------------------
sha256_12() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -c1-12
  else
    sha256sum | cut -c1-12
  fi
}

# ---------------------------------------------------------------------------
# ロール名収集。引数: 実在する構成ファイル群。標準出力: 1行1ロール(重複排除済み)
# ---------------------------------------------------------------------------
extract_roles() {
  [ $# -eq 0 ] && return 0
  {
    grep -hoE "requireRole\([[:space:]]*['\"][A-Za-z0-9_-]+['\"]" "$@" 2>/dev/null || true
    grep -hoE "hasRole\([[:space:]]*['\"][A-Za-z0-9_-]+['\"]" "$@" 2>/dev/null || true
    grep -hoE "roles[[:space:]]*:[[:space:]]*\[[^]]*\]" "$@" 2>/dev/null || true
    grep -hoE "@RolesAllowed\([^)]*\)" "$@" 2>/dev/null || true
  } | { grep -oE "['\"][A-Za-z0-9_-]+['\"]" || true; } \
    | sed "s/^['\"]//; s/['\"]\$//" | sort -u
}

# ---------------------------------------------------------------------------
# API パス収集。引数: 実在する構成ファイル群。標準出力: 1行1パス(重複排除済み)
# ---------------------------------------------------------------------------
extract_api_paths() {
  [ $# -eq 0 ] && return 0
  { grep -hE 'fetch\(|axios\.|apiClient\.' "$@" 2>/dev/null || true; } \
    | { grep -oE "[\"'\`]/api/[^\"'\`]+[\"'\`]" || true; } \
    | sed -e "s/^[\"'\`]//" -e "s/[\"'\`]\$//" -e 's/[?].*$//' \
    | sort -u
}

# ---------------------------------------------------------------------------
# --self-test モード
# mktemp -d にフィクスチャ(React 風 tsx 2画面 + 最小 screen-manifest + api-manifest +
# 設計書ディレクトリ)を生成して本体を実行し、jq で期待フィールド値を検証する。
# ---------------------------------------------------------------------------
self_test() {
  local script_path="$0"
  local script_dir
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  local tmp rc=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/extract-screen-metadata-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  # --- フィクスチャ: React 風 tsx 2画面 ---
  mkdir -p "$tmp/src/screens/admin" "$tmp/src/screens"
  cat > "$tmp/src/screens/admin/UserAdmin.tsx" <<'EOF'
import { requireRole } from "../auth";
export function UserAdmin() {
  requireRole('admin');
  const load = () => fetch('/api/users').then((r) => r.json());
  return null;
}
EOF
  cat > "$tmp/src/screens/Home.tsx" <<'EOF'
export function Home() {
  return null;
}
EOF

  # --- フィクスチャ: 最小 screen-manifest ---
  local manifest="$tmp/screen-manifest.json"
  cat > "$manifest" <<JSON
{
  "generatedAt": "2026-01-01T00:00:00Z",
  "sourceDir": "$tmp/src",
  "strategy": {
    "extractionMethod": "custom",
    "approvedByUser": true,
    "screenIdRegex": null,
    "excludePatterns": []
  },
  "detectionSummary": {
    "screenCount": 2,
    "clusterCount": 0,
    "sharedScreenCount": 0,
    "embeddedCandidateCount": 0,
    "unresolvedCount": 0
  },
  "screens": [
    {
      "screenKey": "user-admin",
      "kind": "route",
      "route": "/admin/users",
      "entryFile": "screens/admin/UserAdmin.tsx",
      "confidence": "high"
    },
    {
      "screenKey": "home",
      "kind": "route",
      "route": "/home",
      "entryFile": "screens/Home.tsx",
      "confidence": "high"
    }
  ]
}
JSON

  # --- フィクスチャ: api-manifest(unitKey 解決用) / 設計書ディレクトリ ---
  local api_manifest="$tmp/api-manifest.json"
  cat > "$api_manifest" <<'JSON'
{
  "unitKind": "api",
  "units": [
    {"unitKey": "users-list", "kind": "endpoint", "identifier": "GET /api/users"}
  ]
}
JSON
  mkdir -p "$tmp/design-docs/user-admin"

  check() {
    local label="$1" expr="$2" file="$3"
    if [ "$(jq -r "$expr" "$file")" = "true" ]; then
      echo "  [PASS] $label"
    else
      echo "  [FAIL] $label — jq: $expr" >&2
      rc=1
    fi
  }

  # --- ケースa: オプションなし(relatedApis は生パス格納) ---
  local out_a="$tmp/out-a.json"
  if bash "$script_path" "$manifest" "$tmp/src" "$out_a" >/dev/null 2>&1; then
    check "ケースa: 管理画面 category=管理" '.screens[0].category == "管理"' "$out_a"
    check "ケースa: 管理画面 permissions=[\"admin\"](requireRole検出)" '.screens[0].permissions == ["admin"]' "$out_a"
    check "ケースa: 管理画面 relatedApis=[\"/api/users\"](生パス)" '.screens[0].relatedApis == ["/api/users"]' "$out_a"
    check "ケースa: 管理画面 sourceHash が12桁hex" '.screens[0].sourceHash | test("^[0-9a-f]{12}$")' "$out_a"
    check "ケースa: 一般画面 category=一般" '.screens[1].category == "一般"' "$out_a"
    check "ケースa: 一般画面 permissions=[](検出なし)" '.screens[1].permissions == []' "$out_a"
    check "ケースa: 一般画面 relatedApis 欠落(fetchなし)" '.screens[1] | has("relatedApis") | not' "$out_a"
    check "ケースa: designDocStatus 欠落(オプション未指定)" '[.screens[] | has("designDocStatus")] | any | not' "$out_a"
    check "ケースa: 既存フィールド無変更" '(.screens[0].route == "/admin/users") and (.screens[1].entryFile == "screens/Home.tsx") and (.detectionSummary.screenCount == 2)' "$out_a"
  else
    echo "  [FAIL] ケースa: 抽出コマンド自体が失敗した" >&2
    rc=1
  fi

  # --- ケースb: --api-manifest + --design-docs-dir 指定 ---
  local out_b="$tmp/out-b.json"
  if bash "$script_path" "$manifest" "$tmp/src" "$out_b" \
      --api-manifest "$api_manifest" --design-docs-dir "$tmp/design-docs" >/dev/null 2>&1; then
    check "ケースb: relatedApis が unitKey に解決" '.screens[0].relatedApis == ["users-list"]' "$out_b"
    check "ケースb: 管理画面 designDocStatus=着手済" '.screens[0].designDocStatus == "着手済"' "$out_b"
    check "ケースb: 一般画面 designDocStatus=未着手" '.screens[1].designDocStatus == "未着手"' "$out_b"
  else
    echo "  [FAIL] ケースb: 抽出コマンド自体が失敗した" >&2
    rc=1
  fi

  # --- 出力が validate-manifest.sh で検証可能であること ---
  local validator="$script_dir/../unit-list/validate-manifest.sh"
  if bash "$validator" "$out_b" --unit-kind screen >/dev/null 2>&1; then
    echo "  [PASS] validate-manifest.sh: 拡張マニフェストが全項目PASS"
  else
    echo "  [FAIL] validate-manifest.sh: 拡張マニフェストが検証FAIL" >&2
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

# ---------------------------------------------------------------------------
# 引数パース
# ---------------------------------------------------------------------------
USAGE="Usage: extract-screen-metadata.sh <screen-manifest.json> <source-dir> <output.json> [--api-manifest <api-manifest.json>] [--design-docs-dir <dir>]"
MANIFEST="${1:?$USAGE}"
SOURCE_DIR="${2:?$USAGE}"
OUTPUT="${3:?$USAGE}"
shift 3 || true

API_MANIFEST=""
DESIGN_DOCS_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --api-manifest)
      API_MANIFEST="${2:-}"
      shift 2
      ;;
    --design-docs-dir)
      DESIGN_DOCS_DIR="${2:-}"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      echo "$USAGE" >&2
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
if [ ! -d "$SOURCE_DIR" ]; then
  echo "ERROR: source-dir not found: $SOURCE_DIR" >&2
  exit 1
fi
if [ -n "$API_MANIFEST" ] && [ ! -f "$API_MANIFEST" ]; then
  echo "ERROR: api-manifest not found: $API_MANIFEST" >&2
  exit 1
fi
if [ -n "$DESIGN_DOCS_DIR" ] && [ ! -d "$DESIGN_DOCS_DIR" ]; then
  echo "ERROR: design-docs-dir not found: $DESIGN_DOCS_DIR" >&2
  exit 1
fi

TMP_WORK="$(mktemp -d "${TMPDIR:-/tmp}/extract-screen-metadata.XXXXXX")"
trap 'rm -rf "$TMP_WORK"' EXIT
ADDS_FILE="$TMP_WORK/adds.jsonl"
: > "$ADDS_FILE"

# ---------------------------------------------------------------------------
# 画面ごとの抽出ループ(1行1JSONオブジェクトで受け取り、jqで各フィールドを引く)
# ---------------------------------------------------------------------------
index=0
while IFS= read -r row; do
  [ -z "$row" ] && { index=$((index + 1)); continue; }

  screen_key="$(jq -r '.screenKey // ""' <<<"$row")"
  route="$(jq -r '.route // ""' <<<"$row")"

  # --- 構成ファイルの解決(files[] 優先、無ければ entryFile/sourceFile/mainFile) ---
  existing_files=()
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if [ "${f#/}" != "$f" ]; then
      resolved="$f"
    else
      resolved="$SOURCE_DIR/$f"
    fi
    [ -f "$resolved" ] && existing_files+=("$resolved")
  done < <(jq -r 'if ((.files // []) | length) > 0 then .files[] else (.entryFile // .sourceFile // .mainFile // empty) end' <<<"$row")

  add='{}'

  # --- 1. category: route の先頭 prefix 判定 ---
  category=""
  if [ -n "$route" ]; then
    case "$route" in
      /admin | /admin/*) category="管理" ;;
      *)                 category="一般" ;;
    esac
    add="$(jq --arg v "$category" '. + {category: $v}' <<<"$add")"
  fi

  # --- 2. permissions: ロール名 grep 収集 + category ベースの推定 ---
  roles="$(extract_roles ${existing_files[@]+"${existing_files[@]}"})"
  if [ -n "$roles" ]; then
    roles_json="$(printf '%s\n' "$roles" | jq -R 'select(length > 0)' | jq -s .)"
    add="$(jq --argjson v "$roles_json" '. + {permissions: $v}' <<<"$add")"
  elif [ "$category" = "管理" ]; then
    add="$(jq '. + {permissions: ["admin"]}' <<<"$add")"
  elif [ "$category" = "一般" ]; then
    add="$(jq '. + {permissions: []}' <<<"$add")"
  fi

  # --- 3. relatedApis: '/api/...' パス収集(+ api-manifest 突合で unitKey 解決) ---
  api_paths="$(extract_api_paths ${existing_files[@]+"${existing_files[@]}"})"
  if [ -n "$api_paths" ]; then
    paths_json="$(printf '%s\n' "$api_paths" | jq -R 'select(length > 0)' | jq -s .)"
    if [ -n "$API_MANIFEST" ]; then
      related_json="$(jq -n --argjson paths "$paths_json" --slurpfile api "$API_MANIFEST" '
        [ $api[0].units[]?
          | {p: (((.identifier // "") | split(" ") | map(select(startswith("/"))) | .[0]) // ""), k: (.unitKey // "")}
          | select((.p | length) > 0 and (.k | length) > 0)
        ] as $map
        | [ $paths[] as $p | $map[] | select(.p == $p) | .k ] | unique
      ')"
    else
      related_json="$paths_json"
    fi
    if [ "$(jq 'length' <<<"$related_json")" -gt 0 ]; then
      add="$(jq --argjson v "$related_json" '. + {relatedApis: $v}' <<<"$add")"
    fi
  fi

  # --- 4. designDocStatus: 設計書ディレクトリ配下の screenKey 実在判定 ---
  if [ -n "$DESIGN_DOCS_DIR" ] && [ -n "$screen_key" ]; then
    doc_status="未着手"
    if [ -e "$DESIGN_DOCS_DIR/$screen_key" ]; then
      doc_status="着手済"
    else
      for cand in "$DESIGN_DOCS_DIR/$screen_key".*; do
        [ -e "$cand" ] && { doc_status="着手済"; break; }
      done
    fi
    add="$(jq --arg v "$doc_status" '. + {designDocStatus: $v}' <<<"$add")"
  fi

  # --- 5. sourceHash: 実在構成ファイル連結の sha256 先頭12桁 ---
  if [ "${#existing_files[@]}" -gt 0 ]; then
    source_hash="$(cat "${existing_files[@]}" | sha256_12)"
    add="$(jq --arg v "$source_hash" '. + {sourceHash: $v}' <<<"$add")"
  fi

  jq -n -c --argjson i "$index" --argjson add "$add" '{index: $i, add: $add}' >> "$ADDS_FILE"
  index=$((index + 1))
done < <(jq -c '.screens[]?' "$MANIFEST")

# ---------------------------------------------------------------------------
# マージ出力(既存フィールドは無変更。追加フィールドだけを各要素へ合成)
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$OUTPUT")"
jq --slurpfile adds "$ADDS_FILE" '
  (reduce $adds[] as $a ({}; .[($a.index | tostring)] = $a.add)) as $m
  | .screens = [ .screens // [] | to_entries[] | .value + ($m[(.key | tostring)] // {}) ]
' "$MANIFEST" > "$OUTPUT"

echo "OK: wrote $OUTPUT" >&2
