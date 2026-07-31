#!/usr/bin/env bash
# output-layout.sh — 生成物の出力配置（日本語パス）の宣言（output-layout.json）を解決する共通関数
#
# 使い方:
#   source "path/to/output-layout.sh"
#   layout_json="$(resolve_output_layout <output_dir>)" || exit 1
#   path="$(output_layout_get "$layout_json" <キー> [label値])" || exit 1
#
# 解決順（番号が大きいほど優先。同一キーは後から読んだものが勝つ）:
#   1. リポジトリ既定 <このファイルの親>/../references/output-layout.json（必須。不在なら ERROR）
#   2. <output_dir>/output-layout.json（対象側の上書き。存在すれば）
#
# {label} プレースホルダを含むキーは、第2引数（label 値）を渡して置換した結果を返す。
# label 値を渡さずに {label} を含むキーを引くとエラーにする（未展開のパスを誤って使わせないため）。
#
# 設計判断（ADR）の正本は .claude/rules/scoped/portal/page-conventions/rule.md の
# 「## 設計判断」内「### output-layout.sh」に記載する。
# 保守責任者: 人手（ユーザー）。配置キーを増減した時に本ファイルと rule.md と self-test を同時に更新する。
# macOS bash 3.2 互換（mapfile / declare -A 不使用）。

OUTPUT_LAYOUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_LAYOUT_DEFAULT="$OUTPUT_LAYOUT_DIR/../references/output-layout.json"

# 複数の宣言ファイルをキー単位で deep merge する（layout オブジェクトのキー単位で後勝ち）。
output_layout_merge_files() {
  jq -s '
    {
      specVersion: (.[0].specVersion // 1),
      layout: (reduce .[] as $f ({}; . * ($f.layout // {})))
    }
  ' "$@"
}

# 解決後の宣言の妥当性を fail-fast で検査する。
output_layout_validate() {
  spec_version="$(printf '%s' "$1" | jq -r '.specVersion // 0')"
  if [ "$spec_version" != "1" ]; then
    echo "ERROR: output-layout.json の specVersion が 1 ではありません" >&2
    return 2
  fi
  return 0
}

# 宣言を解決して JSON を stdout へ返す。
# resolve_output_layout <output_dir>
resolve_output_layout() {
  output_dir="$1"

  if [ ! -f "$OUTPUT_LAYOUT_DEFAULT" ]; then
    echo "ERROR: リポジトリ既定の宣言が見つかりません: $OUTPUT_LAYOUT_DEFAULT" >&2
    return 1
  fi

  set -- "$OUTPUT_LAYOUT_DEFAULT"
  if [ -n "$output_dir" ] && [ -f "$output_dir/output-layout.json" ]; then
    set -- "$@" "$output_dir/output-layout.json"
  fi

  out="$(output_layout_merge_files "$@")" || return 1
  output_layout_validate "$out" || return $?
  printf '%s' "$out"
  return 0
}

# 合成済み宣言からキーの値を取り出す。{label} を含む場合は第3引数で置換する。
# output_layout_get <合成JSON> <キー> [label値]
output_layout_get() {
  layout_json="$1"
  key="$2"
  label="${3:-}"

  if ! printf '%s' "$layout_json" | jq -e --arg k "$key" '.layout | has($k)' >/dev/null 2>&1; then
    echo "ERROR: output-layout のキーが存在しません: $key" >&2
    return 2
  fi

  value="$(printf '%s' "$layout_json" | jq -r --arg k "$key" '.layout[$k]')"

  case "$value" in
    *'{label}'*)
      if [ -z "$label" ]; then
        echo "ERROR: キー '$key' は {label} を含みますが label 値が指定されていません" >&2
        return 2
      fi
      value="${value//\{label\}/$label}"
      ;;
  esac

  printf '%s' "$value"
  return 0
}

output_layout_self_test() {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/output-layout-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN
  rc=0

  # ケース1: 既定のみでキーが取れる
  base="$(resolve_output_layout "$tmp")" || true
  if [ -n "$base" ] && printf '%s' "$base" | jq -e '.layout.unitsRoot == "一覧"' >/dev/null 2>&1; then
    echo "  [PASS] ケース1: 既定解決でキーが取れる"
  else
    echo "  [FAIL] ケース1: 既定解決に失敗" >&2
    rc=1
  fi

  # ケース2: {label} 置換（label=API）
  v2="$(output_layout_get "$base" unitListHtml API 2>/dev/null)" || true
  if [ "$v2" = "一覧/API一覧/API一覧.html" ]; then
    echo "  [PASS] ケース2: {label} 置換 (label=API)"
  else
    echo "  [FAIL] ケース2: {label} 置換が不正: $v2" >&2
    rc=1
  fi

  # ケース3: 上書きファイルがある場合、キー単位でマージ（上書き側が勝ち、他キーは既定が残る）
  cat > "$tmp/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "unitsRoot": "docs/一覧" } }
JSON
  ov="$(resolve_output_layout "$tmp")" || true
  ok3=0
  if printf '%s' "$ov" | jq -e '.layout.unitsRoot == "docs/一覧"' >/dev/null 2>&1; then
    ok3=$((ok3 + 1))
  fi
  if printf '%s' "$ov" | jq -e '.layout.commonRoot == "プロジェクト共通"' >/dev/null 2>&1; then
    ok3=$((ok3 + 1))
  fi
  if [ "$ok3" -eq 2 ]; then
    echo "  [PASS] ケース3: 上書きはキー単位でマージされる（他キーは既定が残る）"
  else
    echo "  [FAIL] ケース3: キー単位マージが不正" >&2
    rc=1
  fi
  rm -f "$tmp/output-layout.json"

  # ケース4: 不在キーで return 2
  output_layout_get "$base" nonExistentKey >/dev/null 2>&1
  rc4=$?
  if [ "$rc4" -eq 2 ]; then
    echo "  [PASS] ケース4: 不在キーで return 2"
  else
    echo "  [FAIL] ケース4: 不在キーの返り値が不正 (rc=$rc4, 期待 2)" >&2
    rc=1
  fi

  # ケース5: label 未指定の {label} キーで return 2
  output_layout_get "$base" unitListHtml >/dev/null 2>&1
  rc5=$?
  if [ "$rc5" -eq 2 ]; then
    echo "  [PASS] ケース5: label 未指定の {label} キーで return 2"
  else
    echo "  [FAIL] ケース5: label 未指定の返り値が不正 (rc=$rc5, 期待 2)" >&2
    rc=1
  fi

  # ケース6: specVersion 不正で return 2
  output_layout_validate '{"specVersion":2,"layout":{}}' >/dev/null 2>&1
  rc6=$?
  if [ "$rc6" -eq 2 ]; then
    echo "  [PASS] ケース6: specVersion 不正で return 2"
  else
    echo "  [FAIL] ケース6: specVersion 不正の返り値が不正 (rc=$rc6, 期待 2)" >&2
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
  output_layout_self_test
  exit $?
fi
