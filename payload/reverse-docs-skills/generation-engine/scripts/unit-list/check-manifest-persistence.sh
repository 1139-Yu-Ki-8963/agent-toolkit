#!/usr/bin/env bash
# check-manifest-persistence.sh — 一覧マニフェストの永続化を機械検査する
#
# 必要性: 一覧生成スキルごとにマニフェストの永続化先が非対称だった問題（改善課題
#   1-136）に対し、生成後の実在を機械判定するため。定義文書の記述だけでは実際に
#   永続化されたかを確認できない。
# 代替案を採用しなかった理由: `validate-manifest.sh` への統合は、あちらが manifest
#   の中身の検証を担っており、ファイルの配置場所の検査は関心が異なる。各スキルへ
#   の個別実装は 7 種別で同じ検査が重複する。
# 保守責任者: 人手（ユーザー）。一覧種別を追加した場合は対応表に行を追加する。
# 廃棄条件: 一覧フォルダとマニフェスト名の対応が宣言ファイルから解決できるように
#   なった時。
#
# Usage: check-manifest-persistence.sh <output_dir>
#        check-manifest-persistence.sh --self-test
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../output-layout.sh"

# ---------------------------------------------------------------------------
# 対応表: 一覧フォルダ名 -> output-layout の manifest / manifestExt キー
# 対応表に無いフォルダ（テスト観点表・テストケース一覧・メッセージ一覧等）は
# 検査対象外として無視する。マニフェストの永続化先自体は manifestsRoot
# （docs/manifests/）であり、一覧フォルダ（unitsRoot）はHTML実在の判定にのみ使う。
# ---------------------------------------------------------------------------
manifest_key_for_folder() {
  case "$1" in
    画面一覧) echo "screenManifest" ;;
    API一覧) echo "apiManifest" ;;
    テーブル一覧) echo "tableManifest" ;;
    バッチ一覧) echo "batchManifest" ;;
    帳票一覧) echo "reportManifest" ;;
    外部連携一覧) echo "externalManifest" ;;
    機能一覧) echo "featureManifest" ;;
    *) echo "" ;;
  esac
}

manifest_ext_key_for_folder() {
  case "$1" in
    画面一覧) echo "screenManifestExt" ;;
    API一覧) echo "apiManifestExt" ;;
    テーブル一覧) echo "tableManifestExt" ;;
    バッチ一覧) echo "batchManifestExt" ;;
    帳票一覧) echo "reportManifestExt" ;;
    外部連携一覧) echo "externalManifestExt" ;;
    機能一覧) echo "featureManifestExt" ;;
    *) echo "" ;;
  esac
}

# ---------------------------------------------------------------------------
# 検査本体
# ---------------------------------------------------------------------------
run_check() {
  local output_dir="$1"
  local layout_json units_root list_root
  layout_json="$(resolve_output_layout "$output_dir")" || return 1
  units_root="$(output_layout_get "$layout_json" unitsRoot)" || return 1
  list_root="$output_dir/$units_root"
  local fail_count=0
  local checked_count=0

  if [ ! -d "$list_root" ]; then
    echo "  [FAIL] 一覧ディレクトリが存在しない: $list_root" >&2
    return 1
  fi

  local folder folder_name manifest_key manifest_ext_key manifest_rel manifest_ext_rel
  local manifest_name ext_manifest_name manifest_path ext_manifest_path html_path
  for folder in "$list_root"/*/; do
    [ -d "$folder" ] || continue
    folder_name="$(basename "$folder")"
    manifest_key="$(manifest_key_for_folder "$folder_name")"
    manifest_ext_key="$(manifest_ext_key_for_folder "$folder_name")"
    [ -n "$manifest_key" ] || continue

    html_path="$folder/${folder_name}.html"
    [ -f "$html_path" ] || continue

    checked_count=$((checked_count + 1))
    manifest_rel="$(output_layout_get "$layout_json" "$manifest_key")" || return 1
    manifest_ext_rel="$(output_layout_get "$layout_json" "$manifest_ext_key")" || return 1
    manifest_path="$output_dir/$manifest_rel"
    ext_manifest_path="$output_dir/$manifest_ext_rel"
    manifest_name="$manifest_rel"
    ext_manifest_name="$manifest_ext_rel"

    local this_ok=1
    if [ -f "$manifest_path" ]; then
      printf '  [PASS] %s: %s\n' "$folder_name" "$manifest_name"
    else
      printf '  [FAIL] %s: %s が見つからない (%s)\n' "$folder_name" "$manifest_name" "$manifest_path" >&2
      this_ok=0
    fi

    if [ -f "$ext_manifest_path" ]; then
      if _gt_out1="$(jq -e --slurpfile base "$manifest_path" '
        (.screens // .units // []) as $extended
        | ([$extended | to_entries[] | .key as $i | .value as $after
          | ($base[0].screens // $base[0].units // [])[$i] as $before
          | select((($after | keys) - ($before | keys) | length) > 0)] | length) > 0
      ' "$ext_manifest_path" 2>&1)"; then
        printf '  [PASS] %s: %s (追加項目あり)\n' "$folder_name" "$ext_manifest_name"
      else
        printf '  [FAIL] %s: %s に追加項目がない\n' "$folder_name" "$ext_manifest_name" >&2
        printf '%s\n' "$_gt_out1" | sed 's/^/    /' >&2
        this_ok=0
      fi
    else
      printf '  [FAIL] %s: %s が見つからない (%s)\n' "$folder_name" "$ext_manifest_name" "$ext_manifest_path" >&2
      this_ok=0
    fi

    if [ "$this_ok" -eq 0 ]; then
      fail_count=$((fail_count + 1))
    fi
  done

  if [ "$checked_count" -eq 0 ]; then
    echo "  検査対象の一覧フォルダが見つからなかった（HTML未生成、または対応表外のみ）"
  fi

  echo "=== $((checked_count - fail_count))/$checked_count PASS, ${fail_count}/$checked_count FAIL ==="
  [ "$fail_count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 自己テスト
# ---------------------------------------------------------------------------
self_test() {
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-manifest-persistence-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  local rc=0
  local self_test_layout_json self_test_units_root self_test_manifests_root
  self_test_layout_json="$(resolve_output_layout "")" || return 1
  self_test_units_root="$(output_layout_get "$self_test_layout_json" unitsRoot)" || return 1
  self_test_manifests_root="$(output_layout_get "$self_test_layout_json" manifestsRoot)" || return 1

  # ケース1: HTMLと対応マニフェストが揃った合成 output_dir で終了コード 0
  # HTMLは一覧フォルダ（unitsRoot）、マニフェストは永続化先（manifestsRoot）に置く。
  local ok_dir="$tmp/ok-output"
  mkdir -p "$ok_dir/$self_test_units_root/画面一覧" "$ok_dir/$self_test_units_root/API一覧" "$ok_dir/$self_test_manifests_root"
  echo '<html></html>' > "$ok_dir/$self_test_units_root/画面一覧/画面一覧.html"
  echo '{"screens":[{"screenKey":"s1"}]}' > "$ok_dir/$self_test_manifests_root/screen-manifest.json"
  echo '{"screens":[{"screenKey":"s1","category":"一般"}]}' > "$ok_dir/$self_test_manifests_root/screen-manifest.ext.json"
  echo '<html></html>' > "$ok_dir/$self_test_units_root/API一覧/API一覧.html"
  echo '{"units":[{"unitKey":"a1"}]}' > "$ok_dir/$self_test_manifests_root/api-manifest.json"
  echo '{"units":[{"unitKey":"a1","method":"GET"}]}' > "$ok_dir/$self_test_manifests_root/api-manifest.ext.json"

  if _gt_out2="$(run_check "$ok_dir" 2>&1)"; then
    echo "  [PASS] 陽性: HTMLとマニフェストが揃った output_dir で終了コード0"
  else
    echo "  [FAIL] 陽性: 揃っているのにFAILした" >&2
    printf '%s\n' "$_gt_out2" | sed 's/^/    /' >&2
    rc=1
  fi

  # ケース4: 拡張マニフェスト自体はあるが追加項目が無い場合は不合格になる
  local emptyext_dir="$tmp/emptyext-output"
  mkdir -p "$emptyext_dir/$self_test_units_root/画面一覧" "$emptyext_dir/$self_test_manifests_root"
  echo '<html></html>' > "$emptyext_dir/$self_test_units_root/画面一覧/画面一覧.html"
  echo '{"screens":[{"screenKey":"s1"}]}' > "$emptyext_dir/$self_test_manifests_root/screen-manifest.json"
  echo '{"screens":[{"screenKey":"s1"}]}' > "$emptyext_dir/$self_test_manifests_root/screen-manifest.ext.json"
  local emptyext_output
  if emptyext_output=$(run_check "$emptyext_dir" 2>&1); then
    echo "  [FAIL] 陰性: 追加項目なしの拡張マニフェストがPASSした" >&2
    rc=1
  elif printf '%s' "$emptyext_output" | grep -q "追加項目がない"; then
    echo "  [PASS] 陰性: 追加項目なしの拡張マニフェストを検出"
  else
    echo "  [FAIL] 陰性: 追加項目なしで不合格だが理由が確認できない" >&2
    rc=1
  fi

  # ケース2: HTMLはあるがマニフェストが一時ディレクトリにしか無い合成 output_dir で
  # 終了コード 1 になり、不足が列挙される
  local ng_dir="$tmp/ng-output"
  mkdir -p "$ng_dir/$self_test_units_root/画面一覧" "$ng_dir/tmp"
  echo '<html></html>' > "$ng_dir/$self_test_units_root/画面一覧/画面一覧.html"
  echo '{}' > "$ng_dir/tmp/screen-manifest.json"

  local ng_output
  if ng_output=$(run_check "$ng_dir" 2>&1); then
    echo "  [FAIL] 陰性: マニフェスト不在なのにPASSした" >&2
    rc=1
  else
    if printf '%s' "$ng_output" | grep -q "screen-manifest.json"; then
      echo "  [PASS] 陰性: マニフェスト不在で終了コード1・不足が列挙される"
    else
      echo "  [FAIL] 陰性: 終了コード1だが不足の列挙が確認できない" >&2
      rc=1
    fi
  fi

  # ケース3: HTMLと基本マニフェストはあるが拡張マニフェストが無い合成 output_dir で
  # 終了コード 1 になり、拡張マニフェストの不足が列挙される
  local extng_dir="$tmp/extng-output"
  mkdir -p "$extng_dir/$self_test_units_root/画面一覧" "$extng_dir/$self_test_manifests_root"
  echo '<html></html>' > "$extng_dir/$self_test_units_root/画面一覧/画面一覧.html"
  echo '{}' > "$extng_dir/$self_test_manifests_root/screen-manifest.json"

  local extng_output
  if extng_output=$(run_check "$extng_dir" 2>&1); then
    echo "  [FAIL] 拡張マニフェスト不在なのにPASSした" >&2
    rc=1
  else
    if printf '%s' "$extng_output" | grep -q "screen-manifest.ext.json"; then
      echo "  [PASS] 拡張マニフェスト不在で終了コード1・不足が列挙される"
    else
      echo "  [FAIL] 終了コード1だが拡張マニフェスト不足の列挙が確認できない" >&2
      rc=1
    fi
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

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <output_dir>" >&2
  exit 1
fi

OUTPUT_DIR="$1"
run_check "$OUTPUT_DIR"
