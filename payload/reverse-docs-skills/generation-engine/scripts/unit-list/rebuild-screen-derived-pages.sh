#!/usr/bin/env bash
# raw screen-manifest.jsonから13派生成果物をsibling transactionで一括再生成する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 書き込み先の判定を1箇所へ寄せた共通モジュール。インラインの Node.js から require する。
export SAFE_WRITE_PATH_LIB="${SCRIPT_DIR}/../lib/safe-write-path.cjs"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=../output-layout.sh
source "$REPO_ROOT/generation-engine/scripts/output-layout.sh"

usage() {
  echo "Usage: rebuild-screen-derived-pages.sh --raw-manifest <path> --target-repo <path> --api-manifest <path> --output-root <path> (--generated-at <iso8601> | SOURCE_DATE_EPOCH=<epoch>) [--table-manifest <path>] [--feature-manifest <path>] [--roles <csv>] [--design-docs-dir <path>] [--doc-view-dir <path>] [--catalog <path>] [--project-name <name>] [--sites <file>] [--site-key <key>]" >&2
}

if [ "${1:-}" = "--self-test" ]; then
  bash "$SCRIPT_DIR/../tests/unit-list/test-rebuild-screen-derived-pages.sh" --self-test
  exit $?
fi

raw=""; target_repo=""; api=""; output_root=""; generated_at=""
table=""; feature=""; roles=""; design_docs=""; doc_view_dir=""; catalog=""; project_name=""
sites=""; site_key=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --raw-manifest) raw="${2:-}"; shift 2 ;;
    --target-repo) target_repo="${2:-}"; shift 2 ;;
    --api-manifest) api="${2:-}"; shift 2 ;;
    --output-root) output_root="${2:-}"; shift 2 ;;
    --generated-at) generated_at="${2:-}"; shift 2 ;;
    --table-manifest) table="${2:-}"; shift 2 ;;
    --feature-manifest) feature="${2:-}"; shift 2 ;;
    --roles) roles="${2:-}"; shift 2 ;;
    --design-docs-dir) design_docs="${2:-}"; shift 2 ;;
    --doc-view-dir) doc_view_dir="${2:-}"; shift 2 ;;
    --catalog) catalog="${2:-}"; shift 2 ;;
    --project-name) project_name="${2:-}"; shift 2 ;;
    --sites) sites="${2:-}"; shift 2 ;;
    --site-key) site_key="${2:-}"; shift 2 ;;
    *) usage; exit 1 ;;
  esac
done

[ -n "$raw" ] && [ -n "$target_repo" ] && [ -n "$api" ] && [ -n "$output_root" ] \
  || { usage; exit 1; }
[ -f "$raw" ] && [ -f "$api" ] && [ -d "$target_repo" ] \
  || { echo "ERROR: required input missing" >&2; exit 1; }

LAYOUT_JSON="$(resolve_output_layout "$output_root")" || exit 1
SCREEN_MANIFEST="$(output_layout_get "$LAYOUT_JSON" screenManifest)" || exit 1
SCREEN_MANIFEST_EXT="$(output_layout_get "$LAYOUT_JSON" screenManifestExt)" || exit 1
SCREEN_LIST_DIR="$(output_layout_get "$LAYOUT_JSON" screenListDir)" || exit 1
SCREEN_LIST_HTML="$(output_layout_get "$LAYOUT_JSON" screenListHtml)" || exit 1
PERMISSION_FUNCTION_MATRIX_HTML="$(output_layout_get "$LAYOUT_JSON" permissionFunctionMatrixHtml)" || exit 1

node - "$raw" "$output_root/$SCREEN_MANIFEST" <<'NODE'
const path = require("path");
const [actual, expected] = process.argv.slice(2).map((value) => path.resolve(value));
if (actual !== expected) {
  throw new Error(`--raw-manifest must be the canonical output path: ${expected}`);
}
NODE
jq empty "$raw" "$api" >/dev/null 2>&1 || { echo "ERROR: input JSON invalid" >&2; exit 1; }
jq -e 'has("manifestContentHash") | not' "$raw" >/dev/null \
  || { echo "ERROR: raw manifest must not contain manifestContentHash" >&2; exit 1; }
bash "$SCRIPT_DIR/validate-manifest.sh" "$raw" --unit-kind screen >/dev/null

epoch="${SOURCE_DATE_EPOCH:-}"
if { [ -n "$generated_at" ] && [ -n "$epoch" ]; } || { [ -z "$generated_at" ] && [ -z "$epoch" ]; }; then
  echo "ERROR: specify exactly one of --generated-at and SOURCE_DATE_EPOCH" >&2
  exit 1
fi
if [ -n "$epoch" ]; then
  printf '%s' "$epoch" | grep -Eq '^[0-9]+$' || { echo "ERROR: SOURCE_DATE_EPOCH must be an integer" >&2; exit 1; }
  generated_at="$(node -e 'const v=Number(process.argv[1]); if(!Number.isSafeInteger(v))process.exit(1); process.stdout.write(new Date(v*1000).toISOString())' "$epoch")"
fi
node -e 'const d=new Date(process.argv[1]); if(Number.isNaN(d.valueOf()) || !/Z$/.test(process.argv[1]))process.exit(1)' "$generated_at" \
  || { echo "ERROR: generatedAt must be canonical UTC ISO8601" >&2; exit 1; }

canonical="$(jq -cjS . "$raw")"
if command -v shasum >/dev/null 2>&1; then
  content_hash="$(printf '%s' "$canonical" | shasum -a 256 | awk '{print $1}')"
else
  content_hash="$(printf '%s' "$canonical" | sha256sum | awk '{print $1}')"
fi

managed=(
  "$SCREEN_MANIFEST_EXT"
  "$SCREEN_LIST_HTML"
  "画面遷移図-data.json"
  "画面遷移図.html"
  "マトリクス・対応表/data/permission-matrix.json"
  "マトリクス・対応表/data/permission-function-matrix.json"
  "マトリクス・対応表/data/crud-matrix.json"
  "マトリクス・対応表/data/traceability.json"
  "マトリクス・対応表/権限画面マトリクス/権限画面マトリクス.html"
  "$PERMISSION_FUNCTION_MATRIX_HTML"
  "マトリクス・対応表/CRUD図/CRUD図.html"
  "マトリクス・対応表/画面-API-テーブル対応表/画面-API-テーブル対応表.html"
  "index.html"
)

# transactionや親ディレクトリを作る前に、output-root自身とmanaged出力の
# 既存祖先をlstatで検査する。symlinkを辿った外部treeへの書き込みを防ぐ。
node - "$output_root" "${managed[@]}" <<'NODE'
const fs = require("fs");
const path = require("path");
const [outputRoot, ...managed] = process.argv.slice(2);

function lstatIfPresent(target) {
  try {
    return fs.lstatSync(target);
  } catch (error) {
    if (error && error.code === "ENOENT") return null;
    throw error;
  }
}

const rootStat = lstatIfPresent(outputRoot);
if (rootStat && rootStat.isSymbolicLink() && !require(process.env.SAFE_WRITE_PATH_LIB).isOsStandardLink(outputRoot)) {
  throw new Error(`output-root must not be a symbolic link: ${outputRoot}`);
}

for (const relative of managed) {
  if (path.isAbsolute(relative)) {
    throw new Error(`managed path must be relative: ${relative}`);
  }
  const segments = relative.split("/");
  if (segments.some((segment) => segment === "" || segment === "." || segment === "..")) {
    throw new Error(`managed path escapes or is not normalized: ${relative}`);
  }
  let current = outputRoot;
  for (const segment of segments.slice(0, -1)) {
    current = path.join(current, segment);
    const stat = lstatIfPresent(current);
    if (!stat) break;
    if (stat.isSymbolicLink() && !require(process.env.SAFE_WRITE_PATH_LIB).isOsStandardLink(current)) {
      throw new Error(`managed path ancestor must not be a symbolic link: ${current}`);
    }
  }
}
NODE

parent="$(dirname "$output_root")"
mkdir -p "$parent"
# transaction_root/backup_rootは${TMPDIR:-/tmp}ではなく${output_rootの}親(sibling)へ
# 作る。コミット段でtransaction_root配下から${output_root配下へmvするため}、両者が
# 別ファイルシステムだとmvがcopy+deleteへ縮退し、中断時に一部だけ移動済みという
# 非原子的な状態を許してしまう。siblingにすることで同一ファイルシステム上のrenameを
# 保証し、トランザクションの原子性を成り立たせている。TMPDIR配下へ戻すな。
if ! transaction_root="$(mktemp -d "$parent/.screen-rebuild.transaction.XXXXXX" 2>/dev/null)" || [ -z "$transaction_root" ]; then
  echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼" >&2
  exit 2
fi
if ! backup_root="$(mktemp -d "$parent/.screen-rebuild.backup.XXXXXX" 2>/dev/null)" || [ -z "$backup_root" ]; then
  echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼" >&2
  exit 2
fi
commit_started=0
commit_done=0

rollback() {
  local rel
  [ "$commit_started" -eq 1 ] && [ "$commit_done" -eq 0 ] || return 0
  for rel in "${managed[@]}"; do
    if [ -f "$backup_root/existing/$rel" ]; then
      mkdir -p "$(dirname "$output_root/$rel")"
      cp -p "$backup_root/existing/$rel" "$output_root/$rel"
    else
      rm -f "$output_root/$rel"
    fi
  done
}
cleanup() {
  status=$?
  rollback
  if [ "${SCREEN_REBUILD_KEEP_TMP:-}" = "1" ] && [ "$status" -ne 0 ]; then
    echo "DEBUG: kept transaction=$transaction_root backup=$backup_root" >&2
  else
    rm -rf "$transaction_root" "$backup_root"
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

mkdir -p "$transaction_root"
if [ -d "$output_root" ]; then cp -a "$output_root/." "$transaction_root/"; fi

snapshot_unmanaged() {
  local base="$1" out="$2"
  node - "$base" "$out" "${managed[@]}" <<'NODE'
const fs=require("fs"),path=require("path"),crypto=require("crypto");
const [base,out,...managed]=process.argv.slice(2), skip=new Set(managed);
const rows=[];
function walk(dir,rel=""){
  if(!fs.existsSync(dir)) return;
  for(const name of fs.readdirSync(dir,{encoding:"utf8"}).sort()){
    const r=rel?`${rel}/${name}`:name, p=path.join(dir,name), s=fs.lstatSync(p);
    if(s.isDirectory()) walk(p,r);
    else if(!skip.has(r)) rows.push(`${r}\t${(s.mode&0o7777).toString(8)}\t${crypto.createHash("sha256").update(fs.readFileSync(p)).digest("hex")}`);
  }
}
walk(base); fs.writeFileSync(out,rows.join("\n")+(rows.length?"\n":""));
NODE
}
snapshot_unmanaged "$output_root" "$backup_root/unmanaged-before"

ext="$transaction_root/$SCREEN_MANIFEST_EXT"
mkdir -p "$(dirname "$ext")"
extract_args=("$raw" "$target_repo" "$ext" --api-manifest "$api" --generated-at "$generated_at" --manifest-content-hash "$content_hash")
if [ -n "$design_docs" ]; then
  # link値はtransaction一時pathではなくcommit後の最終配置を基準に固定する。
  extract_args+=(--design-docs-dir "$design_docs" --link-base-dir "$output_root/$SCREEN_LIST_DIR")
fi
if [ -n "$doc_view_dir" ]; then
  # doc_view_dir（人が読むHTMLの置き場。screenViewRoot）は design_docs（定義の置き場。
  # screenUnitRoot）と別ツリーになりうるため、designDocPath/detailDocPath/sequencePath
  # だけ別ルート・別リンク基点で解決する。未指定時は extract-screen-metadata.sh 側の
  # 既定（design_docsと同一ツリー）にフォールバックする。
  extract_args+=(--doc-view-dir "$doc_view_dir" --doc-view-link-base-dir "$output_root/$SCREEN_LIST_DIR")
fi
bash "$REPO_ROOT/generation-engine/scripts/extract/extract-screen-metadata.sh" "${extract_args[@]}"

screen_args=("$ext" "$transaction_root/$SCREEN_LIST_HTML" --portal-dir "$transaction_root" --generated-at "$generated_at")
[ -n "$project_name" ] && screen_args+=(--project-name "$project_name")
[ -n "$sites" ] && screen_args+=(--sites "$sites")
[ -n "$site_key" ] && screen_args+=(--site-key "$site_key")
bash "$REPO_ROOT/generation-engine/scripts/unit-list/build-screen-list.sh" "${screen_args[@]}"
bash "$REPO_ROOT/generation-engine/scripts/detail-pages/build-detail-pages-from-screen-manifest.sh" \
  "$ext" "$transaction_root" --raw-manifest "$raw" --generated-at "$generated_at"

matrix_dir="$transaction_root/マトリクス・対応表/data"
matrix_args=("$matrix_dir" --screen-manifest "$ext" --api-manifest "$api" --generated-at "$generated_at" --manifest-content-hash "$content_hash")
[ -n "$table" ] && matrix_args+=(--table-manifest "$table")
[ -n "$feature" ] && matrix_args+=(--feature-manifest "$feature")
[ -n "$roles" ] && matrix_args+=(--roles "$roles")
bash "$REPO_ROOT/generation-engine/scripts/extract/build-matrix-data.sh" "${matrix_args[@]}"
bash "$REPO_ROOT/generation-engine/scripts/extract/build-permission-function-data.sh" \
  "$matrix_dir/permission-matrix.json" "$matrix_dir/permission-function-matrix.json" \
  --generated-at "$generated_at" --manifest-content-hash "$content_hash"
[ "${SCREEN_REBUILD_INJECT_FAIL:-}" = "after-matrix" ] && { echo "INJECTED: after-matrix" >&2; exit 89; }

build_matrix() {
  local kind="$1" data="$2" html="$3"
  local args=("$kind" "$data" "$html" --portal-dir "$transaction_root" --generated-at "$generated_at")
  [ -n "$project_name" ] && args+=(--project-name "$project_name")
  bash "$REPO_ROOT/generation-engine/scripts/matrix/build-matrix-pages.sh" "${args[@]}"
}
# transactionへ複製された陳腐化した任意出力を先に除去する。必須成分0件で生成を
# スキップした場合も不在のままにし、commit時に既存outputから削除できるようにする。
rm -f \
  "$transaction_root/マトリクス・対応表/権限画面マトリクス/権限画面マトリクス.html" \
  "$transaction_root/$PERMISSION_FUNCTION_MATRIX_HTML" \
  "$transaction_root/マトリクス・対応表/CRUD図/CRUD図.html" \
  "$transaction_root/マトリクス・対応表/画面-API-テーブル対応表/画面-API-テーブル対応表.html"

build_matrix permission-screen "$matrix_dir/permission-matrix.json" "$transaction_root/マトリクス・対応表/権限画面マトリクス/権限画面マトリクス.html"
permission_function_output="$transaction_root/$PERMISSION_FUNCTION_MATRIX_HTML"
output_layout_assert_path "$LAYOUT_JSON" "$transaction_root" permissionFunctionMatrixHtml "$permission_function_output" || exit 1
build_matrix permission-function "$matrix_dir/permission-function-matrix.json" "$permission_function_output"
build_matrix crud "$matrix_dir/crud-matrix.json" "$transaction_root/マトリクス・対応表/CRUD図/CRUD図.html"
build_matrix traceability "$matrix_dir/traceability.json" "$transaction_root/マトリクス・対応表/画面-API-テーブル対応表/画面-API-テーブル対応表.html"

portal_args=("$target_repo" "$transaction_root" "$transaction_root" --portal-only --generated-at "$generated_at" --screen-manifest "$ext")
[ -n "$catalog" ] && portal_args+=(--catalog "$catalog")
[ -n "$sites" ] && portal_args+=(--sites "$sites")
[ -n "$site_key" ] && portal_args+=(--site-key "$site_key")
bash "$REPO_ROOT/generation-engine/scripts/build-portal.sh" "${portal_args[@]}"

bash "$SCRIPT_DIR/check-screen-manifest-consistency.sh" --raw-manifest "$raw" --ext-manifest "$ext" --output-root "$transaction_root"
snapshot_unmanaged "$transaction_root" "$backup_root/unmanaged-after"
cmp "$backup_root/unmanaged-before" "$backup_root/unmanaged-after" \
  || { echo "ERROR: child changed unmanaged output" >&2; exit 1; }

# マトリクス・対応表配下の各ページ専用ディレクトリ内HTML(権限画面/権限機能/CRUD図/画面-API-テーブル対応表)は
# build-matrix-pages.sh が必須成分すべて0件のとき生成をスキップ(exit 0・既存ファイルは削除)する
# 任意出力である(写真指摘1-101)。パスの列挙ではなく「マトリクス・対応表/<ページ専用dir>/*.html」という
# ディレクトリ構造で判定する(data/*.json は常時生成される必須出力のため対象外)。
for rel in "${managed[@]}"; do
  if [ ! -f "$transaction_root/$rel" ]; then
    case "$rel" in
      "$PERMISSION_FUNCTION_MATRIX_HTML"|マトリクス・対応表/*/*.html)
        : # 必須成分0件によるスキップ。任意出力のため実在検査を免除する
        ;;
      *)
        echo "ERROR: managed output missing: $rel" >&2; exit 1
        ;;
    esac
  fi
  if [ -f "$output_root/$rel" ]; then
    mkdir -p "$backup_root/existing/$(dirname "$rel")"
    cp -p "$output_root/$rel" "$backup_root/existing/$rel"
  fi
done

commit_started=1
index=0
for rel in "${managed[@]}"; do
  index=$((index+1))
  if [ "${SCREEN_REBUILD_INJECT_FAIL:-}" = "commit-5" ] && [ "$index" -eq 5 ]; then
    echo "INJECTED: commit-5" >&2
    exit 90
  fi
  if [ -f "$transaction_root/$rel" ]; then
    mkdir -p "$(dirname "$output_root/$rel")"
    mv "$transaction_root/$rel" "$output_root/$rel"
  else
    # 任意出力が今回スキップされた。既存の陳腐化ページをコミット結果からも取り除く。
    rm -f "$output_root/$rel"
  fi
done
commit_done=1
echo "PASS: rebuilt and committed ${#managed[@]} derived outputs (manifestContentHash=$content_hash)"
