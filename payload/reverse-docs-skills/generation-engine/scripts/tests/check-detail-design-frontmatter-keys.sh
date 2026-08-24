#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DEFINITION="$REPO_ROOT/delivery-payload/references/detail-design-frontmatter-keys.json"
CONTRACT_DOC="$REPO_ROOT/delivery-payload/references/規約定義と派生生成の設計.md"
API_SKILL="$REPO_ROOT/.claude/skills/generating-api-detail-design-for-reverse-docs/SKILL.md"
SCAFFOLD="$REPO_ROOT/generation-engine/scripts/scaffold-design-unit.sh"
WORK_TMP=""

unknown() {
  echo "[UNKNOWN] $1" >&2
  exit 2
}

prepare_tmp() {
  [ -n "$WORK_TMP" ] && return 0
  if ! WORK_TMP="$(mktemp -d "${TMPDIR:-/tmp}/detail-design-frontmatter-keys.XXXXXX")"; then
    unknown "mktempで一時ディレクトリを作成できませんでした。一時領域への書込み不可または実行環境の制約が考えられます"
  fi
  if ! WORK_TMP="$(cd "$WORK_TMP" && pwd -P)"; then
    unknown "mktempで作成した一時ディレクトリの実体パスを解決できませんでした。実行環境のパス制約が考えられます"
  fi
  trap 'rm -rf "$WORK_TMP"' EXIT
}

extract_keys() {
  local file="$1"
  awk '
    NR == 1 { if ($0 != "---") exit; inside = 1; next }
    inside && /^---[[:space:]]*$/ { exit }
    inside && /^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:/ {
      key = $0
      sub(/[[:space:]]*:.*/, "", key)
      print key
    }
  ' "$file" | LC_ALL=C sort -u
}

fill_frontmatter_values() {
  local file="$1"
  if ! sed -i.bak -E 's/^([a-z_]+): [A-Z]{2,}$/\1: test-value/' "$file"; then
    unknown "mktempで作成した一時領域のfrontmatterへ書き込めませんでした。書込み権限または実行環境の制約が考えられます"
  fi
  rm -f "$file.bak"
}

compare_keys() {
  local kind="$1" file="$2" label="$3"
  local expected actual missing extra errors=0
  expected="$(jq -r --arg kind "$kind" '.kinds[$kind].keys[]' "$DEFINITION" | LC_ALL=C sort -u)"
  actual="$(extract_keys "$file")"
  missing="$(comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual"))"
  extra="$(comm -13 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual"))"
  if [ -n "$missing" ]; then
    echo "[FAIL] $label missing: $(printf '%s\n' "$missing" | paste -sd ',' -)" >&2
    errors=$((errors + 1))
  fi
  if [ -n "$extra" ]; then
    echo "[FAIL] $label extra: $(printf '%s\n' "$extra" | paste -sd ',' -)" >&2
    errors=$((errors + 1))
  fi
  if [ "$errors" -eq 0 ]; then
    echo "[PASS] $label: 定義済み鍵集合と完全一致"
    return 0
  fi
  return 1
}

check_definition_document() {
  local kind expected_line errors=0
  while IFS= read -r kind; do
    expected_line="$(jq -r --arg kind "$kind" '
      "- " + .kinds[$kind].label + "（" + $kind + "）: " + (.kinds[$kind].keys | join("・"))
    ' "$DEFINITION")"
    if ! grep -qF -- "$expected_line" "$CONTRACT_DOC"; then
      echo "[FAIL] 定義文書にJSONと一致する鍵集合がありません: $kind" >&2
      errors=$((errors + 1))
    fi
  done < <(jq -r '.kinds | keys[]' "$DEFINITION")
  [ "$errors" -eq 0 ] || return 1
  echo "[PASS] 定義文書: JSONの全種別鍵集合と一致"
}

check_source_ref_contract() {
  local file marker errors=0
  local markers=(
    "1ファイルの場合"
    "複数ファイルの場合"
    "実装が0件の場合"
    "リポジトリルート相対パス1件"
    "ルーター、コントローラー、ハンドラーの順"
    "sourceFile"
    "confirmation-survey"
    "絶対パスと行番号を含めない"
  )
  for file in "$CONTRACT_DOC" "$API_SKILL"; do
    for marker in "${markers[@]}"; do
      if ! grep -qF "$marker" "$file"; then
        echo "[FAIL] source_ref契約が不足: $(basename "$file"): $marker" >&2
        errors=$((errors + 1))
      fi
    done
  done
  [ "$errors" -eq 0 ] || return 1
  echo "[PASS] source_ref契約: 1ファイル・複数ファイル・実装0件を両文書へ明記"
}

check_template() {
  local kind="$1" template
  template="$(jq -r --arg kind "$kind" '.kinds[$kind].template' "$DEFINITION")"
  compare_keys "$kind" "$REPO_ROOT/$template" "$kind テンプレート"
}

check_generated() {
  local kind="$1" document output_dir generated
  prepare_tmp
  document="$(jq -r --arg kind "$kind" '.kinds[$kind].document' "$DEFINITION")"
  output_dir="$WORK_TMP/$kind"
  if ! mkdir -p "$output_dir"; then
    unknown "mktempで作成した一時領域へ出力ディレクトリを作成できませんでした。書込み権限または実行環境の制約が考えられます"
  fi
  if ! bash "$SCAFFOLD" "$kind" detail "$output_dir" frontmatter-check "前付け検査" >/dev/null 2>&1; then
    echo "[FAIL] $kind 実生成物を作成できません" >&2
    return 1
  fi
  generated="$(find "$output_dir" -type f -name "$document" -print -quit)"
  if [ -z "$generated" ]; then
    echo "[FAIL] $kind 実生成物が見つかりません: $document" >&2
    return 1
  fi
  fill_frontmatter_values "$generated"
  local errors=0
  compare_keys "$kind" "$generated" "$kind 実生成物" || errors=$((errors + 1))
  if bash "$SCAFFOLD" --verify "$kind" detail "$output_dir" frontmatter-check >/dev/null 2>&1; then
    echo "[PASS] $kind 実生成物: scaffold --verifyがJSON正本との一致を確認"
  else
    echo "[FAIL] $kind 実生成物: scaffold --verifyが不合格" >&2
    errors=$((errors + 1))
  fi
  [ "$errors" -eq 0 ]
}

check_kind() {
  local kind="$1" errors=0
  check_template "$kind" || errors=$((errors + 1))
  check_generated "$kind" || errors=$((errors + 1))
  [ "$errors" -eq 0 ]
}

check_api_template() {
  local forbidden key errors=0 api_template
  check_definition_document || errors=$((errors + 1))
  check_template api || errors=$((errors + 1))
  forbidden="$(jq -r '.kinds.api.forbiddenKeys[]' "$DEFINITION")"
  api_template="$REPO_ROOT/$(jq -r '.kinds.api.template' "$DEFINITION")"
  while IFS= read -r key; do
    if extract_keys "$api_template" | grep -qxF "$key"; then
      echo "[FAIL] APIテンプレートに禁止鍵があります: $key" >&2
      errors=$((errors + 1))
    fi
  done <<< "$forbidden"
  [ "$errors" -eq 0 ] || return 1
  echo "[PASS] APIテンプレート: 禁止5鍵なし"
}

check_all_kinds() {
  local kind errors=0
  check_definition_document || errors=$((errors + 1))
  for kind in table batch report external; do
    check_kind "$kind" || errors=$((errors + 1))
  done
  [ "$errors" -eq 0 ]
}

self_test() {
  local pass=0 total=3 canonical original output_dir
  prepare_tmp
  output_dir="$WORK_TMP/self-test-output"
  if ! mkdir -p "$output_dir"; then
    unknown "mktempで作成した一時領域へ自己テスト出力先を作成できませんでした。書込み権限または実行環境の制約が考えられます"
  fi
  if ! bash "$SCAFFOLD" api detail "$output_dir" frontmatter-self-test "前付け自己テスト" >/dev/null 2>&1; then
    echo "[FAIL] 自己テスト用のAPI詳細設計書を生成できません" >&2
    return 1
  fi
  canonical="$(find "$output_dir" -type f -name 'API詳細設計書.md' -print -quit)"
  [ -n "$canonical" ] || unknown "mktempで作成した一時領域に自己テスト用API詳細設計書がありません。実行環境の制約が考えられます"
  fill_frontmatter_values "$canonical"
  original="$WORK_TMP/api-canonical-original.md"
  if ! cp "$canonical" "$original"; then
    unknown "mktempで作成した一時領域へ正常入力を複製できませんでした。書込み権限または実行環境の制約が考えられます"
  fi

  if compare_keys api "$canonical" "自己テスト正常入力" >/dev/null 2>&1 \
     && bash "$SCAFFOLD" --verify api detail "$output_dir" frontmatter-self-test >/dev/null 2>&1; then
    echo "[PASS] ケース1: 定義の7鍵をそろえた入力が合格"
    pass=$((pass + 1))
  else
    echo "[FAIL] ケース1: 定義の7鍵をそろえた入力が不合格" >&2
  fi
  if ! sed -i.bak '/^feature_key:/d' "$canonical"; then
    unknown "mktempで作成した一時領域へ欠落入力を書き込めませんでした。書込み権限または実行環境の制約が考えられます"
  fi
  rm -f "$canonical.bak"
  if ! compare_keys api "$canonical" "自己テスト欠落入力" >/dev/null 2>&1 \
     && ! bash "$SCAFFOLD" --verify api detail "$output_dir" frontmatter-self-test >/dev/null 2>&1; then
    echo "[PASS] ケース2: 欠落鍵を持つ入力が不合格"
    pass=$((pass + 1))
  else
    echo "[FAIL] ケース2: 欠落鍵を持つ入力が合格" >&2
  fi
  if ! cp "$original" "$canonical" \
     || ! sed -i.bak '2i\
title: 余剰鍵' "$canonical"; then
    unknown "mktempで作成した一時領域へ余剰入力を書き込めませんでした。書込み権限または実行環境の制約が考えられます"
  fi
  rm -f "$canonical.bak"
  if ! compare_keys api "$canonical" "自己テスト余剰入力" >/dev/null 2>&1 \
     && ! bash "$SCAFFOLD" --verify api detail "$output_dir" frontmatter-self-test >/dev/null 2>&1; then
    echo "[PASS] ケース3: 余剰鍵を持つ入力が不合格"
    pass=$((pass + 1))
  else
    echo "[FAIL] ケース3: 余剰鍵を持つ入力が合格" >&2
  fi
  echo "自己テスト実行件数: $total"
  echo "自己テスト成功件数: $pass"
  [ "$pass" -eq "$total" ]
}

main() {
  if [ ! -f "$DEFINITION" ] || ! jq -e '.schemaVersion == 1 and (.kinds | type == "object")' "$DEFINITION" >/dev/null 2>&1; then
    echo "[FAIL] 詳細設計書frontmatter定義が不正です: $DEFINITION" >&2
    return 1
  fi
  case "${1:-}" in
    "")
      local kind errors=0
      check_api_template || errors=$((errors + 1))
      check_source_ref_contract || errors=$((errors + 1))
      for kind in api table batch report external; do
        check_kind "$kind" || errors=$((errors + 1))
      done
      [ "$errors" -eq 0 ]
      ;;
    --check-api-template) check_api_template ;;
    --check-source-ref-contract) check_source_ref_contract ;;
    --check-all-kinds) check_all_kinds ;;
    --self-test) self_test ;;
    *)
      echo "使い方: $0 [--check-api-template|--check-source-ref-contract|--check-all-kinds|--self-test]" >&2
      return 2
      ;;
  esac
}

main "$@"
