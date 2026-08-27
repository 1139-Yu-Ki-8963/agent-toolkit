#!/usr/bin/env bash
# check-excluded-kinds-consistency.sh — 対象外種別の宣言と一覧成果物の実態を照合する
#
# Usage: check-excluded-kinds-consistency.sh <output_dir>
#        check-excluded-kinds-consistency.sh --present-lists <output_dir>
#        check-excluded-kinds-consistency.sh --manifests <output_dir>
#        check-excluded-kinds-consistency.sh --self-test
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../output-layout.sh"

KINDS="screen api table batch report external"

resolved_layout_for() {
  if [ -n "${CHECK_EXCLUDED_LAYOUT_CACHE:-}" ]; then
    printf '%s' "$CHECK_EXCLUDED_LAYOUT_CACHE"
  else
    resolve_output_layout "$1"
  fi
}

validate_relative_path() {
  local key="$1"
  local value="$2"
  case "$value" in
    ""|.|..|/*|*/|*//*|.*|*'/.'*|*'\'*|*'*'*|*'?'*|*'['*|*']'*)
      echo "ERROR: output-layout の $key は出力先内の安全な相対パスで指定してください" >&2
      return 2
      ;;
  esac
}

validate_layout_paths() {
  if ! printf '%s' "$1" | node -e '
    const fs = require("fs");
    const doc = JSON.parse(fs.readFileSync(0, "utf8"));
    const layout = doc.layout || {};
    const labels = Object.values(doc.kindLabels || {});
    const keys = [
      "excludedKinds",
      "screenManifest", "screenManifestExt", "apiManifest", "apiManifestExt",
      "tableManifest", "tableManifestExt", "batchManifest", "batchManifestExt",
      "reportManifest", "reportManifestExt", "externalManifest", "externalManifestExt",
      "featureManifest", "featureManifestExt"
    ];
    const paths = keys.map((key) => layout[key]);
    for (const label of labels) {
      paths.push(String(layout.unitListHtml || "").replaceAll("{label}", label));
      paths.push(String(layout.unitListAbsentMd || "").replaceAll("{label}", label));
    }
    const invalid = (value) =>
      typeof value !== "string" || value.length === 0 || value === "." || value === ".." ||
      value.startsWith("/") || value.startsWith(".") || value.endsWith("/") ||
      value.includes("//") || value.includes("\\") || /[*?\[\]]/.test(value) ||
      value.split("/").some((part) => part.startsWith(".")) ||
      /[\p{C}\p{Z}]/u.test(value) || value.normalize("NFC") !== value;
    if (paths.some(invalid)) process.exit(1);
    const normalized = paths.map((value) => value.normalize("NFC"));
    if (new Set(normalized).size !== normalized.length) process.exit(1);
  ' >/dev/null 2>&1; then
    echo "ERROR: output-layout の判定対象パスに安全でない相対パスがある" >&2
    return 2
  fi
}

manifest_key_for_kind() {
  case "$1" in
    screen) echo "screenManifest" ;;
    api) echo "apiManifest" ;;
    table) echo "tableManifest" ;;
    batch) echo "batchManifest" ;;
    report) echo "reportManifest" ;;
    external) echo "externalManifest" ;;
    feature) echo "featureManifest" ;;
    *) return 1 ;;
  esac
}

manifest_ext_key_for_kind() {
  printf '%sManifestExt' "$1"
}

run_check() {
  local output_dir="$1"
  local mode="${2:-full}"
  local layout_json excluded_rel excluded_path fail_count kind label html_rel absent_rel
  local manifest_key manifest_rel manifest_ext_key manifest_ext_rel
  if [ -z "$output_dir" ]; then
    echo "  [FAIL] output_dir は空にできない" >&2
    return 1
  fi
  layout_json="$(resolved_layout_for "$output_dir")" || return 1
  validate_layout_paths "$layout_json" || return $?
  excluded_rel="$(output_layout_get "$layout_json" excludedKinds)" || return 1
  validate_relative_path excludedKinds "$excluded_rel" || return $?
  excluded_path="$output_dir/$excluded_rel"
  fail_count=0

  if [ ! -f "$excluded_path" ]; then
    echo "  [FAIL] 対象外種別の宣言が存在しない: $excluded_path" >&2
    return 1
  fi
  local _gt_kinds_arrays_ok=1 _gt_out2a _gt_out2b _gt_out2c
  _gt_out2a="$(jq -e '.allKinds | type == "array"' "$excluded_path" 2>&1)" || _gt_kinds_arrays_ok=0
  _gt_out2b="$(jq -e '.presentKinds | type == "array"' "$excluded_path" 2>&1)" || _gt_kinds_arrays_ok=0
  _gt_out2c="$(jq -e '.excludedKinds | type == "array"' "$excluded_path" 2>&1)" || _gt_kinds_arrays_ok=0
  if [ "$_gt_kinds_arrays_ok" -ne 1 ]; then
    echo "  [FAIL] allKinds・presentKinds・excludedKinds は配列で必須: $excluded_path" >&2
    printf '%s\n%s\n%s\n' "$_gt_out2a" "$_gt_out2b" "$_gt_out2c" | sed 's/^/    /' >&2
    return 1
  fi

  local _gt_out4
  if ! _gt_out4="$(jq -e --argjson expected '["api","batch","external","report","screen","table"]' '
    ([.allKinds[]] | sort) == $expected
    and ([.presentKinds[]] | sort | unique) == ([.presentKinds[]] | sort)
    and ([.excludedKinds[].kind] | sort | unique) == ([.excludedKinds[].kind] | sort)
    and (([.presentKinds[]] + [.excludedKinds[].kind]) | sort) == $expected
    and (([.presentKinds[]] - [.excludedKinds[].kind]) | length) == (.presentKinds | length)
  ' "$excluded_path" 2>&1)"; then
    echo "  [FAIL] 6種別が presentKinds と excludedKinds に重複なく完全分割されていない" >&2
    printf '%s\n' "$_gt_out4" | sed 's/^/    /' >&2
    fail_count=$((fail_count + 1))
  fi
  if ! _gt_out3="$(jq -e '
    (.generatedAt | type == "string" and length > 0)
    and (.surveyDocPath | type == "string" and length > 0)
    and (all(.excludedKinds[]; (.label | type == "string" and length > 0)
      and (.reason | type == "string" and length > 0)))
  ' "$excluded_path" 2>&1)"; then
    echo "  [FAIL] generatedAt・surveyDocPath・対象外種別のlabel・reasonは空でない文字列で必須" >&2
    printf '%s\n' "$_gt_out3" | sed 's/^/    /' >&2
    fail_count=$((fail_count + 1))
  fi

  for kind in $KINDS; do
    label="$(output_layout_kind_label "$layout_json" "$kind")" || return 1
    html_rel="$(output_layout_get "$layout_json" unitListHtml "$label")" || return 1
    validate_relative_path unitListHtml "$html_rel" || return $?
    absent_rel="$(output_layout_get "$layout_json" unitListAbsentMd "$label")" || return 1
    validate_relative_path unitListAbsentMd "$absent_rel" || return $?
    manifest_key="$(manifest_key_for_kind "$kind")" || return 1
    manifest_rel="$(output_layout_get "$layout_json" "$manifest_key")" || return 1
    validate_relative_path "$manifest_key" "$manifest_rel" || return $?
    manifest_ext_key="$(manifest_ext_key_for_kind "$kind")"
    manifest_ext_rel="$(output_layout_get "$layout_json" "$manifest_ext_key")" || return 1
    validate_relative_path "$manifest_ext_key" "$manifest_ext_rel" || return $?

    if jq -e --arg kind "$kind" '.excludedKinds[] | select(.kind == $kind)' "$excluded_path" >/dev/null 2>&1; then
      if [ "$mode" = "present-lists" ] || [ "$mode" = "manifests" ]; then
        continue
      fi
      if [ -e "$output_dir/$html_rel" ] || [ -e "$output_dir/$manifest_rel" ] || [ -e "$output_dir/$manifest_ext_rel" ]; then
        echo "  [FAIL] $kind: 対象外宣言と成果物の実在が食い違う ($html_rel / $manifest_rel / $manifest_ext_rel)" >&2
        fail_count=$((fail_count + 1))
      elif [ ! -f "$output_dir/$absent_rel" ]; then
        echo "  [FAIL] $kind: 対象外の人間可読記録がない ($absent_rel)" >&2
        fail_count=$((fail_count + 1))
      else
        echo "  [PASS] $kind: 対象外宣言どおり一覧HTML・マニフェストなし、対象外記録あり"
      fi
    else
      if [ "$mode" = "present-lists" ] && [ -f "$output_dir/$html_rel" ]; then
        echo "  [PASS] $kind: 実在宣言どおり一覧HTMLあり"
      elif [ "$mode" = "present-lists" ]; then
        echo "  [FAIL] $kind: 対象外未宣言だが一覧HTMLがない ($html_rel)" >&2
        fail_count=$((fail_count + 1))
      elif [ "$mode" = "manifests" ] && [ -f "$output_dir/$manifest_rel" ] && [ -f "$output_dir/$manifest_ext_rel" ]; then
        echo "  [PASS] $kind: 実在宣言どおり基本・拡張マニフェストあり"
      elif [ "$mode" = "manifests" ]; then
        echo "  [FAIL] $kind: 対象外未宣言だがマニフェストがない ($manifest_rel / $manifest_ext_rel)" >&2
        fail_count=$((fail_count + 1))
      elif [ -f "$output_dir/$html_rel" ] && [ -f "$output_dir/$manifest_rel" ] && [ -f "$output_dir/$manifest_ext_rel" ]; then
        echo "  [PASS] $kind: 実在宣言どおり一覧HTML・基本・拡張マニフェストあり"
      else
        echo "  [FAIL] $kind: 対象外未宣言だが一覧HTMLまたはマニフェストがない ($html_rel / $manifest_rel / $manifest_ext_rel)" >&2
        fail_count=$((fail_count + 1))
      fi
    fi
  done

  kind="feature"
  label="$(output_layout_kind_label "$layout_json" "$kind")" || return 1
  html_rel="$(output_layout_get "$layout_json" unitListHtml "$label")" || return 1
  manifest_key="$(manifest_key_for_kind "$kind")" || return 1
  manifest_rel="$(output_layout_get "$layout_json" "$manifest_key")" || return 1
  manifest_ext_key="$(manifest_ext_key_for_kind "$kind")"
  manifest_ext_rel="$(output_layout_get "$layout_json" "$manifest_ext_key")" || return 1
  if [ "$mode" = "present-lists" ] && [ -f "$output_dir/$html_rel" ]; then
    echo "  [PASS] feature: 派生機能一覧HTMLあり"
  elif [ "$mode" = "manifests" ] && [ -f "$output_dir/$manifest_rel" ] && [ -f "$output_dir/$manifest_ext_rel" ]; then
    echo "  [PASS] feature: 基本・拡張マニフェストあり"
  elif [ "$mode" = "full" ] && [ -f "$output_dir/$html_rel" ] && [ -f "$output_dir/$manifest_rel" ] && [ -f "$output_dir/$manifest_ext_rel" ]; then
    echo "  [PASS] feature: 派生一覧HTML・基本・拡張マニフェストあり"
  else
    echo "  [FAIL] feature: 派生機能一覧の成果物がない ($html_rel / $manifest_rel / $manifest_ext_rel)" >&2
    fail_count=$((fail_count + 1))
  fi

  echo "=== excluded-kinds consistency: ${fail_count} FAIL ==="
  [ "$fail_count" -eq 0 ]
}

write_declaration() {
  local output_dir="$1"
  local excluded_kind="${2:-}"
  local present_json excluded_json layout_json label absent_rel
  present_json="$(printf '%s\n' $KINDS | jq -Rsc --arg excluded "$excluded_kind" 'split("\n") | map(select(length > 0 and . != $excluded))')"
  if [ -n "$excluded_kind" ]; then
    layout_json="$(resolved_layout_for "$output_dir")" || return 1
    label="$(output_layout_kind_label "$layout_json" "$excluded_kind")" || return 1
    excluded_json="$(jq -nc --arg kind "$excluded_kind" --arg label "$label" '[{kind: $kind, label: $label, reason: "self-test"}]')"
    absent_rel="$(output_layout_get "$layout_json" unitListAbsentMd "$label")" || return 1
    mkdir -p "$output_dir/$(dirname "$absent_rel")"
    printf '# %s一覧（該当なし）\n' "$label" > "$output_dir/$absent_rel"
  else
    excluded_json='[]'
  fi
  mkdir -p "$output_dir/docs/scope-and-progress"
  jq -n --argjson present "$present_json" --argjson excluded "$excluded_json" \
    '{generatedAt:"2026-08-19T00:00:00+09:00",surveyDocPath:"docs/design/common/アーキテクチャ調査書.md",allKinds:["screen","api","table","batch","report","external"],presentKinds:$present,excludedKinds:$excluded}' \
    > "$output_dir/docs/scope-and-progress/excluded-kinds.json"
}

write_artifacts() {
  local output_dir="$1"
  local omitted_kind="${2:-}"
  local layout_json kind label html_rel manifest_key manifest_rel manifest_ext_key manifest_ext_rel
  layout_json="$(resolved_layout_for "$output_dir")" || return 1
  for kind in $KINDS; do
    [ "$kind" = "$omitted_kind" ] && continue
    label="$(output_layout_kind_label "$layout_json" "$kind")" || return 1
    html_rel="$(output_layout_get "$layout_json" unitListHtml "$label")" || return 1
    manifest_key="$(manifest_key_for_kind "$kind")" || return 1
    manifest_rel="$(output_layout_get "$layout_json" "$manifest_key")" || return 1
    manifest_ext_key="$(manifest_ext_key_for_kind "$kind")"
    manifest_ext_rel="$(output_layout_get "$layout_json" "$manifest_ext_key")" || return 1
    mkdir -p "$output_dir/$(dirname "$html_rel")" "$output_dir/$(dirname "$manifest_rel")" "$output_dir/$(dirname "$manifest_ext_rel")"
    printf '<html></html>\n' > "$output_dir/$html_rel"
    printf '{"units":[{"unitKey":"self-test"}]}\n' > "$output_dir/$manifest_rel"
    printf '{"units":[{"unitKey":"self-test","category":"test"}]}\n' > "$output_dir/$manifest_ext_rel"
  done
  kind="feature"
  label="$(output_layout_kind_label "$layout_json" "$kind")" || return 1
  html_rel="$(output_layout_get "$layout_json" unitListHtml "$label")" || return 1
  manifest_rel="$(output_layout_get "$layout_json" featureManifest)" || return 1
  manifest_ext_rel="$(output_layout_get "$layout_json" featureManifestExt)" || return 1
  mkdir -p "$output_dir/$(dirname "$html_rel")" "$output_dir/$(dirname "$manifest_rel")" "$output_dir/$(dirname "$manifest_ext_rel")"
  printf '<html></html>\n' > "$output_dir/$html_rel"
  printf '{"units":[{"unitKey":"self-test"}]}\n' > "$output_dir/$manifest_rel"
  printf '{"units":[{"unitKey":"self-test","category":"test"}]}\n' > "$output_dir/$manifest_ext_rel"
}

run_stage1() {
  local output_dir="$1"
  run_check "$output_dir" present-lists || return 1
  run_check "$output_dir" manifests || return 1
  run_check "$output_dir"
}

self_test() {
  local tmp rc output safe_layout collision_layout
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-excluded-kinds-consistency.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' RETURN
  rc=0
  CHECK_EXCLUDED_LAYOUT_CACHE="$(resolve_output_layout "")" || return 1
  export CHECK_EXCLUDED_LAYOUT_CACHE

  write_declaration "$tmp/declared-absent" report
  write_artifacts "$tmp/declared-absent" report
  if _gt_out5="$(run_stage1 "$tmp/declared-absent" 2>&1)"; then
    echo "  [PASS] 検収2: 対象外宣言した帳票の成果物が無ければ合格"
  else
    echo "  [FAIL] 検収2: 対象外宣言と成果物不在が一致しているのに不合格" >&2
    printf '%s\n' "$_gt_out5" | sed 's/^/    /' >&2
    rc=1
  fi

  write_declaration "$tmp/undeclared-absent"
  write_artifacts "$tmp/undeclared-absent" report
  if output="$(run_stage1 "$tmp/undeclared-absent" 2>&1)"; then
    echo "  [FAIL] 検収3: 帳票成果物が無いのに対象外未宣言で合格" >&2
    rc=1
  elif printf '%s' "$output" | grep -q 'report: 対象外未宣言'; then
    echo "  [PASS] 検収3: 対象外未宣言の帳票成果物不在を検出"
  else
    echo "  [FAIL] 検収3: 不合格理由が対象外未宣言の成果物不在ではない" >&2
    rc=1
  fi

  write_declaration "$tmp/declared-present" report
  write_artifacts "$tmp/declared-present"
  if output="$(run_stage1 "$tmp/declared-present" 2>&1)"; then
    echo "  [FAIL] 検収4: 対象外宣言した帳票成果物が存在するのに合格" >&2
    rc=1
  elif printf '%s' "$output" | grep -q 'report: 対象外宣言と成果物の実在が食い違う'; then
    echo "  [PASS] 検収4: 対象外宣言と帳票成果物実在の食い違いを検出"
  else
    echo "  [FAIL] 検収4: 不合格理由が宣言と実態の食い違いではない" >&2
    rc=1
  fi

  safe_layout="$CHECK_EXCLUDED_LAYOUT_CACHE"
  collision_layout="$(printf '%s' "$safe_layout" | jq '.layout.apiManifest = .layout.screenManifest')"
  CHECK_EXCLUDED_LAYOUT_CACHE="$collision_layout"
  if _gt_out6="$(run_check "$tmp/declared-absent" manifests 2>&1)"; then
    echo "  [FAIL] 追加回帰: 衝突するマニフェスト出力先を受理" >&2
    printf '%s\n' "$_gt_out6" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] 追加回帰: 衝突する出力先を拒否"
  fi
  CHECK_EXCLUDED_LAYOUT_CACHE="$safe_layout"

  [ "$rc" -eq 0 ] && echo "self-test 全3項目 PASS"
  return "$rc"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi
if [ "${1:-}" = "--present-lists" ]; then
  [ "$#" -eq 2 ] || { echo "Usage: $0 --present-lists <output_dir>" >&2; exit 1; }
  run_check "$2" present-lists
  exit $?
fi
if [ "${1:-}" = "--manifests" ]; then
  [ "$#" -eq 2 ] || { echo "Usage: $0 --manifests <output_dir>" >&2; exit 1; }
  run_check "$2" manifests
  exit $?
fi
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <output_dir>" >&2
  exit 1
fi
run_check "$1"
