#!/usr/bin/env bash
# 参照JSON間のキー対応を reference-json-integrity.json の宣言に従って検査する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEFAULT_CONTRACT="$REPO_ROOT/delivery-payload/references/reference-json-integrity.json"

unknown() {
  echo "[UNKNOWN] $*" >&2
  return 2
}

run_integrity_check() {
  local contract="$1" reference_dir="$2" temporary_dir check_count index
  if [ ! -f "$contract" ]; then
    unknown "対応定義が見つかりません: $contract"
    return 2
  fi
  if ! jq -e '
    .specVersion == 1
    and (.expectedCheckCount | type) == "number"
    and (.expectedCheckCount > 0)
    and (.checks | type) == "array"
    and ((.checks | length) == .expectedCheckCount)
    and (([.checks[].id] | unique | length) == .expectedCheckCount)
    and all(.checks[];
      (.id | type) == "string"
      and (.relation == "equal" or .relation == "subset")
      and (.source.file | type) == "string"
      and (.source.query | type) == "string"
      and (.target.file | type) == "string"
      and (.target.query | type) == "string"
      and ((.minimumSourceCount // 0) | type) == "number"
      and ((.minimumTargetCount // 0) | type) == "number"
      and ((.uniqueSource // false) | type) == "boolean"
      and ((.uniqueTarget // false) | type) == "boolean"
    )
  ' "$contract" >/dev/null 2>&1; then
    unknown "対応定義をJSONとして読めないか、形式が不正です: $contract"
    return 2
  fi
  if ! temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/check-reference-json-integrity.XXXXXX" 2>/dev/null)" || [ -z "$temporary_dir" ]; then
    unknown "mktempで一時領域を作成できないため判定できません"
    return 2
  fi
  trap 'rm -rf "$temporary_dir"' RETURN

  check_count="$(jq '.checks | length' "$contract")"
  local total_missing=0
  for ((index = 0; index < check_count; index++)); do
    local id relation source_file target_file source_query target_query source_path target_path
    local minimum_source_count minimum_target_count unique_source unique_target
    id="$(jq -r ".checks[$index].id // empty" "$contract")"
    relation="$(jq -r ".checks[$index].relation // empty" "$contract")"
    source_file="$(jq -r ".checks[$index].source.file // empty" "$contract")"
    target_file="$(jq -r ".checks[$index].target.file // empty" "$contract")"
    source_query="$(jq -r ".checks[$index].source.query // empty" "$contract")"
    target_query="$(jq -r ".checks[$index].target.query // empty" "$contract")"
    minimum_source_count="$(jq -r ".checks[$index].minimumSourceCount // 0" "$contract")"
    minimum_target_count="$(jq -r ".checks[$index].minimumTargetCount // 0" "$contract")"
    unique_source="$(jq -r ".checks[$index].uniqueSource // false" "$contract")"
    unique_target="$(jq -r ".checks[$index].uniqueTarget // false" "$contract")"
    if [ -z "$id" ] || { [ "$relation" != "equal" ] && [ "$relation" != "subset" ]; } \
      || [ -z "$source_file" ] || [ -z "$target_file" ] || [ -z "$source_query" ] || [ -z "$target_query" ]; then
      unknown "対応定義の checks[$index] に必須項目がありません"
      return 2
    fi
    source_path="$reference_dir/$source_file"
    target_path="$reference_dir/$target_file"
    if [ ! -f "$source_path" ] || [ ! -f "$target_path" ]; then
      unknown "$id が読む定義ファイルが見つかりません: $source_file / $target_file"
      return 2
    fi
    if ! jq -r "$source_query" "$source_path" 2>"$temporary_dir/$index.source.err" | LC_ALL=C sort >"$temporary_dir/$index.source"; then
      unknown "$id の参照元を抽出できません: $(tr '\n' ' ' <"$temporary_dir/$index.source.err")"
      return 2
    fi
    if ! jq -r "$target_query" "$target_path" 2>"$temporary_dir/$index.target.err" | LC_ALL=C sort >"$temporary_dir/$index.target"; then
      unknown "$id の参照先を抽出できません: $(tr '\n' ' ' <"$temporary_dir/$index.target.err")"
      return 2
    fi
    local source_count target_count
    source_count="$(wc -l <"$temporary_dir/$index.source" | tr -d ' ')"
    target_count="$(wc -l <"$temporary_dir/$index.target" | tr -d ' ')"
    if [ "$source_count" -lt "$minimum_source_count" ] || [ "$target_count" -lt "$minimum_target_count" ]; then
      echo "[FAIL] $id: 抽出件数が対応定義の下限未満です（参照元 ${source_count}/${minimum_source_count}、参照先 ${target_count}/${minimum_target_count}）" >&2
      total_missing=$((total_missing + 1))
      continue
    fi
    if [ "$unique_source" = "true" ] && [ -n "$(uniq -d "$temporary_dir/$index.source")" ]; then
      echo "[FAIL] $id: 参照元に重複キーがあります" >&2
      total_missing=$((total_missing + 1))
      continue
    fi
    if [ "$unique_target" = "true" ] && [ -n "$(uniq -d "$temporary_dir/$index.target")" ]; then
      echo "[FAIL] $id: 参照先に重複キーがあります" >&2
      total_missing=$((total_missing + 1))
      continue
    fi
    if [ "$relation" = "subset" ]; then
      LC_ALL=C sort -u "$temporary_dir/$index.source" -o "$temporary_dir/$index.source"
      LC_ALL=C sort -u "$temporary_dir/$index.target" -o "$temporary_dir/$index.target"
    fi

    comm -23 "$temporary_dir/$index.source" "$temporary_dir/$index.target" >"$temporary_dir/$index.missing"
    local missing_count reverse_count=0
    missing_count="$(wc -l <"$temporary_dir/$index.missing" | tr -d ' ')"
    if [ "$relation" = "equal" ]; then
      comm -13 "$temporary_dir/$index.source" "$temporary_dir/$index.target" >"$temporary_dir/$index.reverse"
      reverse_count="$(wc -l <"$temporary_dir/$index.reverse" | tr -d ' ')"
    fi
    if [ "$missing_count" -gt 0 ] || [ "$reverse_count" -gt 0 ]; then
      echo "[FAIL] $id: 不在 $((missing_count + reverse_count)) 件" >&2
      sed 's/^/  参照先に不在: /' "$temporary_dir/$index.missing" >&2
      if [ "$reverse_count" -gt 0 ]; then
        sed 's/^/  参照元に不在: /' "$temporary_dir/$index.reverse" >&2
      fi
      total_missing=$((total_missing + missing_count + reverse_count))
    else
      echo "[PASS] $id: 不在 0 件"
    fi
  done
  if [ "$total_missing" -gt 0 ]; then
    echo "[FAIL] 参照先不在は合計 ${total_missing} 件" >&2
    return 1
  fi
  echo "[PASS] 参照先不在は合計 0 件（${check_count} 対応）"
  return 0
}

self_test() {
  local temporary_dir
  local expected_check_count=23
  if [ "$(jq '.checks | length' "$DEFAULT_CONTRACT" 2>/dev/null)" != "$expected_check_count" ]; then
    echo "[FAIL] 自己テスト0: 対応が ${expected_check_count} 件ではありません" >&2
    return 1
  fi
  if ! temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/check-reference-json-integrity-self-test.XXXXXX" 2>/dev/null)" || [ -z "$temporary_dir" ]; then
    unknown "mktempで自己テスト用の一時領域を作成できません"
    return 2
  fi
  trap 'rm -rf "$temporary_dir"' RETURN
  mkdir -p "$temporary_dir/references"
  if ! cp "$REPO_ROOT"/delivery-payload/references/{portal-catalog,output-layout,deliverable-inventory,unit-axes,doc-extraction,design-unit-layout,rule-taxonomy}.json "$temporary_dir/references/"; then
    unknown "自己テスト用の参照JSONを複製できません"
    return 2
  fi

  local actual_rc=0
  run_integrity_check "$DEFAULT_CONTRACT" "$temporary_dir/references" >/dev/null || actual_rc=$?
  if [ "$actual_rc" -eq 2 ]; then
    unknown "実物の定義を判定できません"
    return 2
  fi
  if [ "$actual_rc" -ne 0 ]; then
    echo "[FAIL] 自己テスト1: 実物の定義が合格しません" >&2
    return 1
  fi
  echo "[PASS] 自己テスト1: 実物の定義は不在0件"

  jq 'del(.items[0])' "$temporary_dir/references/deliverable-inventory.json" >"$temporary_dir/inventory.json"
  mv "$temporary_dir/inventory.json" "$temporary_dir/references/deliverable-inventory.json"
  local broken_rc=0
  run_integrity_check "$DEFAULT_CONTRACT" "$temporary_dir/references" >/dev/null 2>&1 || broken_rc=$?
  if [ "$broken_rc" -ne 1 ]; then
    echo "[FAIL] 自己テスト2: 参照先を1件欠いた入力の終了コードが1ではありません: $broken_rc" >&2
    return 1
  fi
  echo "[PASS] 自己テスト2: 参照先を1件欠くと終了コード1"

  printf '{' >"$temporary_dir/invalid-contract.json"
  local unknown_rc=0
  run_integrity_check "$temporary_dir/invalid-contract.json" "$temporary_dir/references" >/dev/null 2>&1 || unknown_rc=$?
  if [ "$unknown_rc" -ne 2 ]; then
    echo "[FAIL] 自己テスト3: 不正な対応定義の終了コードが2ではありません: $unknown_rc" >&2
    return 1
  fi
  echo "[PASS] 自己テスト3: 判定不能は終了コード2"

  cp "$REPO_ROOT/delivery-payload/references/design-unit-layout.json" "$temporary_dir/references/design-unit-layout.json"
  jq '.generationRules = {}' "$temporary_dir/references/design-unit-layout.json" >"$temporary_dir/layout-empty.json"
  mv "$temporary_dir/layout-empty.json" "$temporary_dir/references/design-unit-layout.json"
  local empty_rc=0
  run_integrity_check "$DEFAULT_CONTRACT" "$temporary_dir/references" >/dev/null 2>&1 || empty_rc=$?
  if [ "$empty_rc" -ne 1 ]; then
    echo "[FAIL] 自己テスト4: 参照元が空集合の入力の終了コードが1ではありません: $empty_rc" >&2
    return 1
  fi
  echo "[PASS] 自己テスト4: 参照元が空集合なら終了コード1"

  cp "$REPO_ROOT/delivery-payload/references/design-unit-layout.json" "$temporary_dir/references/design-unit-layout.json"
  cp "$REPO_ROOT/delivery-payload/references/portal-catalog.json" "$temporary_dir/references/portal-catalog.json"
  cp "$REPO_ROOT/delivery-payload/references/deliverable-inventory.json" "$temporary_dir/references/deliverable-inventory.json"
  jq '.categories[0].blueprints += [.categories[0].blueprints[0]]' "$temporary_dir/references/portal-catalog.json" >"$temporary_dir/catalog-duplicate.json"
  mv "$temporary_dir/catalog-duplicate.json" "$temporary_dir/references/portal-catalog.json"
  local source_duplicate_rc=0
  run_integrity_check "$DEFAULT_CONTRACT" "$temporary_dir/references" >/dev/null 2>&1 || source_duplicate_rc=$?
  if [ "$source_duplicate_rc" -ne 1 ]; then
    echo "[FAIL] 自己テスト5: 参照元だけに重複がある入力の終了コードが1ではありません: $source_duplicate_rc" >&2
    return 1
  fi
  echo "[PASS] 自己テスト5: 参照元だけの重複は終了コード1"

  cp "$REPO_ROOT/delivery-payload/references/portal-catalog.json" "$temporary_dir/references/portal-catalog.json"
  jq '.items += [.items[0]]' "$temporary_dir/references/deliverable-inventory.json" >"$temporary_dir/inventory-duplicate.json"
  mv "$temporary_dir/inventory-duplicate.json" "$temporary_dir/references/deliverable-inventory.json"
  local target_duplicate_rc=0
  run_integrity_check "$DEFAULT_CONTRACT" "$temporary_dir/references" >/dev/null 2>&1 || target_duplicate_rc=$?
  if [ "$target_duplicate_rc" -ne 1 ]; then
    echo "[FAIL] 自己テスト6: 参照先だけに重複がある入力の終了コードが1ではありません: $target_duplicate_rc" >&2
    return 1
  fi
  echo "[PASS] 自己テスト6: 参照先だけの重複は終了コード1"

  jq '.checks[0].minimumSourceCount = "one"' "$DEFAULT_CONTRACT" >"$temporary_dir/invalid-type-contract.json"
  local invalid_type_rc=0
  run_integrity_check "$temporary_dir/invalid-type-contract.json" "$temporary_dir/references" >/dev/null 2>&1 || invalid_type_rc=$?
  if [ "$invalid_type_rc" -ne 2 ]; then
    echo "[FAIL] 自己テスト7: 型が不正な対応定義の終了コードが2ではありません: $invalid_type_rc" >&2
    return 1
  fi
  echo "[PASS] 自己テスト7: 対応定義の型不正は終了コード2"

  jq '.checks[1].id = .checks[0].id' "$DEFAULT_CONTRACT" >"$temporary_dir/duplicate-id-contract.json"
  local duplicate_id_rc=0
  run_integrity_check "$temporary_dir/duplicate-id-contract.json" "$temporary_dir/references" >/dev/null 2>&1 || duplicate_id_rc=$?
  if [ "$duplicate_id_rc" -ne 2 ]; then
    echo "[FAIL] 自己テスト8: 対応IDが重複した定義の終了コードが2ではありません: $duplicate_id_rc" >&2
    return 1
  fi
  echo "[PASS] 自己テスト8: 対応IDの重複は終了コード2"
  echo "[PASS] 自己テスト 8 件"
}

case "${1:-}" in
  "") run_integrity_check "$DEFAULT_CONTRACT" "$REPO_ROOT/delivery-payload/references" ;;
  --self-test) self_test ;;
  *) echo "Usage: check-reference-json-integrity.sh [--self-test]" >&2; exit 2 ;;
esac
