#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
portal="$repo_root/generation-engine/scripts/build-portal.sh"
pages="$repo_root/generation-engine/scripts/matrix/build-matrix-pages.sh"
data="$repo_root/generation-engine/scripts/extract/build-matrix-data.sh"
prepare="$repo_root/generation-engine/scripts/verification/prepare-verification-input.sh"
tmp_base="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
tmp="$(mktemp -d "$tmp_base/issues-1-77-1-85.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

require_text() {
  local file="$1" text="$2" label="$3"
  if grep -Fq -- "$text" "$file"; then
    echo "PASS: $label"
  else
    echo "FAIL: $label" >&2
    return 1
  fi
}

# 1-77: 納品手順の本番経路を疑似入力で実行し、5系統の成果物とログを検査する。
bash "$prepare" --output "$tmp/input" --repo "$repo_root"
mkdir -p "$tmp/target/src"
for source_kind in api batch external feature report screen; do
  cp -R "$repo_root/generation-engine/samples/source/$source_kind/." "$tmp/target/"
done
cp "$repo_root/generation-engine/samples/source/table/001_create_users.sql" "$tmp/target/001_create_users.sql"
bash "$portal" "$tmp/target" "$tmp/input" "$tmp/portal" \
  --build-manifests-from-docs --generated-at 2026-01-01T00:00:00Z \
  >"$tmp/portal.log" 2>&1

for manifest_kind in api table batch report external feature; do
  manifest="$tmp/input/docs/manifests/$manifest_kind-manifest.json"
  [ -s "$manifest" ] || { echo "FAIL: 1-77 マニフェストが無い: $manifest" >&2; exit 1; }
  manifest_count="$(jq -r '.units | length' "$manifest")"
  echo "PASS: 1-77 マニフェストを生成: $manifest ($manifest_count 件)"
done

for artifact in \
  "$tmp/portal/lists/message-list/メッセージ一覧.html" \
  "$tmp/portal/matrices/data/crud-matrix.json" \
  "$tmp/portal/matrices/crud/CRUD図.html" \
  "$tmp/portal/diagrams/状態遷移図.html" \
  "$tmp/portal/diagrams/ER図.html" \
  "$tmp/portal/diagrams/画面遷移図.html"; do
  [ -s "$artifact" ] || { echo "FAIL: 1-77 成果物が無い: $artifact" >&2; exit 1; }
  echo "PASS: 1-77 成果物を生成: $artifact"
done

for log_text in \
  'INFO: generating design-document manifests' \
  'INFO: generating message manifest' \
  'INFO: generating message list' \
  'INFO: generating entity-state diagram data' \
  'INFO: generating er diagram data' \
  'INFO: generating transition diagram data' \
  'INFO: generating CRUD matrix data' \
  'INFO: generating CRUD matrix page'; do
  require_text "$tmp/portal.log" "$log_text" "1-77 実行ログ: $log_text"
done

# 本番経路の到達先と、失敗を成功扱いしないガードも走査する。
require_text "$portal" 'portal-input/build-manifests-from-docs.sh' '1-77 設計文書マニフェスト生成器へ到達'
require_text "$portal" 'extract/convert-message-doc-to-manifest.sh' '1-77 メッセージ一覧のデータ生成器へ到達'
require_text "$portal" 'unit-list/build-unit-list.sh" "$message_manifest"' '1-77 メッセージ一覧の版面生成器へ到達'
require_text "$portal" 'entity-state|extract-entity-state-page-data.sh' '1-77 実体状態図の生成器へ到達'
require_text "$portal" 'er|extract-er-page-data.sh' '1-77 関連図の生成器へ到達'
require_text "$portal" 'portal-input/extract-transition-page-data.sh' '1-77 遷移図の生成器へ到達'
require_text "$portal" 'extract/build-matrix-data.sh' '1-77 対応表データ生成器へ到達'
require_text "$portal" 'matrix/build-matrix-pages.sh" crud' '1-77 対応表版面生成器へ到達'
require_text "$portal" 'SKIP: message list' '1-77 メッセージ入力不在を記録'
require_text "$portal" 'SKIP: transition diagram' '1-77 遷移図入力不在を記録'
require_text "$portal" 'SKIP: CRUD matrix' '1-77 対応表入力不在を記録'
require_text "$portal" 'ERROR: message list generation failed' '1-77 メッセージ生成失敗を伝播'
require_text "$portal" 'ERROR: CRUD matrix page generation failed' '1-77 対応表生成失敗を伝播'

# 入力不在時は失敗せず、SKIPを実ログへ残す。
bash "$prepare" --output "$tmp/input-missing" --repo "$repo_root"
mv "$tmp/input-missing/docs/design/common/メッセージ定義書.md" "$tmp/message-disabled.md"
bash "$portal" "$tmp/target" "$tmp/input-missing" "$tmp/portal-missing" \
  --build-manifests-from-docs --generated-at 2026-01-01T00:00:00Z \
  >"$tmp/portal-missing.log" 2>&1
require_text "$tmp/portal-missing.log" 'SKIP: message list' '1-77 不在種別を実行ログへ記録'

# メッセージ生成器だけを意図的に失敗させ、本番手順が非0を返すことを実行確認する。
bash "$prepare" --output "$tmp/input-failure" --repo "$repo_root"
bash() {
  case "${1:-}" in
    *convert-message-doc-to-manifest.sh) return 23 ;;
    *) command /bin/bash "$@" ;;
  esac
}
export -f bash
failure_rc=0
/bin/bash "$portal" "$tmp/target" "$tmp/input-failure" "$tmp/portal-failure" \
  --build-manifests-from-docs --generated-at 2026-01-01T00:00:00Z \
  >"$tmp/portal-failure.log" 2>&1 || failure_rc=$?
[ "$failure_rc" -ne 0 ] || { echo 'FAIL: 1-77 生成器失敗が成功扱いされた' >&2; exit 1; }
require_text "$tmp/portal-failure.log" 'ERROR: message manifest generation failed' '1-77 生成器失敗を非0で伝播'
unset -f bash

# 1-85: 既定保持、明示削除、通常生成、0件連鎖をブラウザなしで実行する。
jq -n '{generatedAt:"2026-01-01T00:00:00Z",dataSource:"acceptance",tables:[{physicalName:"users",logicalName:"Users"}],features:[{featureId:"users",featureName:"Users",cells:{users:"CRUD"}}]}' >"$tmp/crud-full.json"
jq -n '{generatedAt:"2026-01-01T00:00:00Z",dataSource:"acceptance",tables:[],features:[]}' >"$tmp/crud-empty.json"
bash "$pages" crud "$tmp/crud-full.json" "$tmp/crud.html"
cp "$tmp/crud.html" "$tmp/crud-before.html"
bash "$pages" crud "$tmp/crud-empty.json" "$tmp/crud.html" >"$tmp/skip.log" 2>&1
cmp -s "$tmp/crud-before.html" "$tmp/crud.html"
require_text "$tmp/skip.log" 'SKIP:' '1-85 空データで既存ページを保持'
require_text "$tmp/skip.log" "$tmp/crud.html" '1-85 保持したファイル名を記録'

delete_rc=0
bash "$pages" crud "$tmp/crud-empty.json" "$tmp/crud.html" --delete-on-empty >"$tmp/delete.log" 2>&1 || delete_rc=$?
[ "$delete_rc" -eq 2 ]
[ ! -e "$tmp/crud.html" ]
require_text "$tmp/delete.log" 'DELETE:' '1-85 明示削除を記録'
require_text "$tmp/delete.log" "$tmp/crud.html" '1-85 削除したファイル名を記録'

jq -n '{screens:[]}' >"$tmp/screen-empty.json"
jq -n '{units:[]}' >"$tmp/api-empty.json"
jq -n '{units:[]}' >"$tmp/feature-empty.json"
bash "$pages" crud "$tmp/crud-full.json" "$tmp/crud.html"
cp "$tmp/crud.html" "$tmp/crud-before.html"
bash "$data" "$tmp/matrix-data" --screen-manifest "$tmp/screen-empty.json" --api-manifest "$tmp/api-empty.json" --feature-manifest "$tmp/feature-empty.json" --roles , >"$tmp/data.log" 2>&1
bash "$pages" crud "$tmp/matrix-data/crud-matrix.json" "$tmp/crud.html" >"$tmp/chain.log" 2>&1
cmp -s "$tmp/crud-before.html" "$tmp/crud.html"
require_text "$tmp/data.log" 'INFO: zero-row matrix data:' '1-85 0件データを生成済みとして記録'
require_text "$tmp/chain.log" 'SKIP:' '1-85 0件連鎖で既存ページを保持'
echo 'PASS: 1-77 / 1-85 acceptance checks'
