#!/usr/bin/env bash
# unit-axes.sh — 分類軸・任意列の宣言（unit-axes.json）を解決する共通関数
#
# 使い方:
#   source "path/to/render-template.sh"   # 不要。本ファイルは単独で source できる
#   source "path/to/unit-axes.sh"
#   axes_json="$(resolve_unit_axes <manifest_path> [explicit_axes_file])" || exit 1
#   kind_json="$(unit_axes_for_kind "$axes_json" <unit_kind>)"
#   safe_json="$(unit_axes_script_safe "$kind_json")"
#
# 解決順（番号が大きいほど優先。同一キーは後から読んだものが勝つ）:
#   1. リポジトリ既定 <このファイルの親>/../references/unit-axes.json（必須。不在なら ERROR）
#   2. <manifest_dir>/../unit-axes.json（全種別共通の上書き）
#   3. <manifest_dir>/unit-axes.json（種別別の上書き）
#   4. 第2引数で明示指定されたファイル
#
# 第2引数が非空の場合、1〜3 を一切読まずそのファイルの内容をそのまま解決結果として返す。
# これにより resolve_unit_axes は冪等になり、上流が解決済み JSON を渡したときに
# 既定と再マージして disabled にした軸が復活する事故を防ぐ。
#
# 解決の起点を manifest のパスに固定する理由: validate-manifest.sh は manifest パスだけを
# 引数に単独実行される。ポータルのディレクトリを起点にすると build は上書きを見て
# validate は見ない二重基準が生まれる。manifest パスは全消費者が必ず持つ。
#
# 設計判断（ADR）の正本は .claude/rules/scoped/portal/page-conventions/rule.md の
# 「## 設計判断」に記載する。
# 保守責任者: 人手（ユーザー）。宣言スキーマを変更した時に本ファイルと検査を更新する。
# macOS bash 3.2 互換（mapfile 不使用）。

UNIT_AXES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_AXES_DEFAULT="$UNIT_AXES_DIR/../references/unit-axes.json"

# 複数の宣言ファイルをキー単位で deep merge する。
# values は配列のため丸ごと置換される（部分マージは順序が非決定になるため許さない）。
# disabled:true のエントリは解決後に除外する。
unit_axes_merge_files() {
  jq -s '
    def mergelist($k):
      reduce .[] as $f ({};
        reduce ($f[$k] // [])[] as $e (.; .[$e.key] = ((.[$e.key] // {}) * $e)))
      | [ .[] ]
      | map(select(.disabled != true));
    {
      specVersion: (.[0].specVersion // 1),
      axes:    (mergelist("axes")    | sort_by(.order // 999)),
      columns: (mergelist("columns") | sort_by(.order // 999))
    }
  ' "$@"
}

# 解決後の宣言の妥当性を fail-fast で検査する。
unit_axes_validate() {
  errs="$(printf '%s' "$1" | jq -r '
    [
      (if (.specVersion // 0) != 1 then "specVersion が 1 ではありません" else empty end),

      ( [(.axes[].key), (.columns[].key)] | group_by(.) | map(select(length > 1) | .[0])[]
        | "キーが重複しています: " + . ),

      ( .axes[]
        | (.valuePolicy // "") as $v
        | select(($v == "closed" or $v == "identifier" or $v == "open") | not)
        | "valuePolicy が closed/identifier/open のいずれでもありません: " + .key ),

      ( .axes[] | select(.valuePolicy == "closed" and ((.values // []) | length) == 0)
        | "valuePolicy=closed の軸に values がありません: " + .key ),

      ( .axes[] | select(.valuePolicy == "closed")
        | select(([.values[].key] | length) != ([.values[].key] | unique | length))
        | "values のキーが軸内で重複しています: " + .key ),

      ( .axes[]
        | select((.valuePolicy == "identifier" or .valuePolicy == "open") and (has("values")))
        | "valuePolicy=" + .valuePolicy + " の軸に values を置けません: " + .key ),

      ( (.axes[], .columns[])
        | (.column.show // "auto") as $s
        | select(($s == "auto" or $s == "always" or $s == "never") | not)
        | "column.show が auto/always/never のいずれでもありません: " + .key ),

      ( .axes[] | select((.split.default // false) == true)
        | select(((.split.eligible // false) != true) or (.valuePolicy != "closed"))
        | "split.default=true の軸は split.eligible=true かつ valuePolicy=closed が必要です: " + .key ),

      ( (.axes[], .columns[]) | select(.key == "none")
        | "軸・列のキーに予約語 none は使えません" ),

      ( .axes[] | select(has("detect"))
        | select(((.detect.source // []) | type) != "array" or ((.detect.source // []) | length) == 0)
        | "detect.source が空でない配列ではありません: " + .key ),

      ( .axes[] | select(has("detect"))
        | select(((.detect.rules // []) | type) != "array" or ((.detect.rules // []) | length) == 0)
        | "detect.rules が空でない配列ではありません: " + .key ),

      ( .axes[] | select(has("detect"))
        | . as $axis
        | ($axis.detect.rules // [])[]
        | select((has("value") and has("match")) | not)
        | "detect.rules の要素に value/match がありません: " + $axis.key ),

      ( .axes[] | select(has("detect") and .valuePolicy == "closed")
        | . as $axis
        | ($axis.values // [] | map(.key)) as $allowed
        | ($axis.detect.rules // [])[]
        | select(([.value] - $allowed) | length > 0)
        | "detect.rules[].value が values[].key に存在しません: " + $axis.key + " (" + .value + ")" )
    ] | .[]
  ' 2>&1)"

  if [ -n "$errs" ]; then
    echo "ERROR: unit-axes.json の妥当性検査に失敗しました" >&2
    printf '%s\n' "$errs" >&2
    return 1
  fi
  return 0
}

# 宣言を解決して JSON を stdout へ返す。
resolve_unit_axes() {
  manifest="$1"
  explicit="${2:-}"

  if [ -n "$explicit" ]; then
    if [ ! -f "$explicit" ]; then
      echo "ERROR: 明示指定された宣言ファイルが存在しません: $explicit" >&2
      return 1
    fi
    out="$(cat "$explicit")"
    unit_axes_validate "$out" || return 1
    printf '%s' "$out"
    return 0
  fi

  if [ ! -f "$UNIT_AXES_DEFAULT" ]; then
    echo "ERROR: リポジトリ既定の宣言が見つかりません: $UNIT_AXES_DEFAULT" >&2
    return 1
  fi

  mdir="$(cd "$(dirname "$manifest")" 2>/dev/null && pwd)"
  if [ -z "$mdir" ]; then
    echo "ERROR: manifest のディレクトリを解決できません: $manifest" >&2
    return 1
  fi

  set -- "$UNIT_AXES_DEFAULT"
  [ -f "$mdir/../unit-axes.json" ] && set -- "$@" "$mdir/../unit-axes.json"
  [ -f "$mdir/unit-axes.json" ] && set -- "$@" "$mdir/unit-axes.json"

  out="$(unit_axes_merge_files "$@")" || return 1
  unit_axes_validate "$out" || return 1
  printf '%s' "$out"
  return 0
}

# 解決済み宣言から、指定 unit_kind に適用されるエントリだけを抜き出す。
unit_axes_for_kind() {
  printf '%s' "$1" | jq -c --arg k "$2" '{
    specVersion: .specVersion,
    axes:    [ .axes[]    | select((.appliesTo // []) | index($k)) ],
    columns: [ .columns[] | select((.appliesTo // []) | index($k)) ]
  }'
}

# <script> 要素から脱出できないよう無害化する（shell-injection.sh と同じ処理）。
unit_axes_script_safe() {
  printf '%s' "$1" | sed 's/</\\u003c/g; s/>/\\u003e/g; s/&/\\u0026/g'
}

# unit_axes_apply_detect <resolved_axes_json> <unit_kind> <manifest_path>
#   manifest の各要素に対し、detect を持つ軸の規則を当てて値を埋めた manifest を stdout へ返す。
#   既に値が入っているフィールドは上書きしない（明示的な値を尊重する）。
#
#   規則の評価順: detect.source を先頭から走査し、最初に値を持つ source を採用する
#   （source が配列フィールドの場合は各要素を順に見る）。採用した値に対し
#   detect.rules を先頭から評価し、最初に一致した規則の value を書き込む。
#   一致する規則が無ければフィールド自体を書かない。
#
#   要素の配列名は unit_kind で決まる（screen は "screens"、それ以外は "units"）。
unit_axes_apply_detect() {
  axes_resolved="$1"
  unit_kind="$2"
  manifest_path="$3"

  kind_axes="$(unit_axes_for_kind "$axes_resolved" "$unit_kind")"
  detect_axes="$(printf '%s' "$kind_axes" | jq -c '[.axes[] | select(has("detect"))]')"

  case "$unit_kind" in
    screen) array_name="screens" ;;
    *)      array_name="units" ;;
  esac

  if [ "$(printf '%s' "$detect_axes" | jq 'length')" -eq 0 ]; then
    cat "$manifest_path"
    return 0
  fi

  jq --argjson detectAxes "$detect_axes" --arg arr "$array_name" '
    def detect_one($item; $ax):
      ($ax.detect.source // []) as $srcs
      | ($ax.detect.rules // []) as $rules
      | reduce $srcs[] as $src (null;
          if . != null then .
          else
            ($item[$src]) as $raw
            | (if ($raw | type) == "array" then $raw
               elif $raw == null then []
               else [$raw] end) as $vals
            | reduce $vals[] as $v (null;
                if . != null then .
                elif ($v | type) != "string" then .
                else
                  reduce $rules[] as $r (null;
                    if . != null then .
                    elif ($v | test($r.match; "i")) then $r.value
                    else . end)
                end)
          end);
    if has($arr) then
      .[$arr] |= map(
        . as $item
        | reduce $detectAxes[] as $ax ($item;
            if (($item | has($ax.key)) and ($item[$ax.key] != null)) then .
            else
              (detect_one($item; $ax)) as $dv
              | if $dv != null then (.[$ax.key] = $dv) else . end
            end)
      )
    else . end
  ' "$manifest_path"
}

unit_axes_self_test() {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/unit-axes-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN
  rc=0

  mkdir -p "$tmp/一覧/画面一覧"
  : > "$tmp/一覧/画面一覧/manifest.json"
  m="$tmp/一覧/画面一覧/manifest.json"

  # ケース1: 既定のみで解決でき、妥当性検査を通る
  if base="$(resolve_unit_axes "$m")"; then
    echo "  [PASS] ケース1: 既定のみで解決"
  else
    echo "  [FAIL] ケース1: 既定のみの解決に失敗" >&2
    rc=1
  fi

  # ケース2: 既定に accountGroup / device / operationClass が含まれる
  if printf '%s' "$base" | jq -e '
      ([.axes[].key] | index("accountGroup")) and
      ([.axes[].key] | index("device")) and
      ([.columns[].key] | index("operationClass"))' >/dev/null 2>&1; then
    echo "  [PASS] ケース2: 既定に主要キーが含まれる"
  else
    echo "  [FAIL] ケース2: 既定に主要キーが無い" >&2
    rc=1
  fi

  # ケース3: 種別別上書きのラベルが勝つ
  cat > "$tmp/一覧/画面一覧/unit-axes.json" <<'JSON'
{
  "specVersion": 1,
  "axes": [
    { "key": "accountGroup",
      "values": [ { "key": "user", "label": "利用者向け" }, { "key": "admin", "label": "職員向け" } ] }
  ]
}
JSON
  ov="$(resolve_unit_axes "$m")"
  if printf '%s' "$ov" | jq -e '
      [.axes[] | select(.key=="accountGroup") | .values[].label] == ["利用者向け","職員向け"]' >/dev/null 2>&1; then
    echo "  [PASS] ケース3: 上書きの values が丸ごと置換される"
  else
    echo "  [FAIL] ケース3: 上書きの values が反映されない" >&2
    rc=1
  fi

  # ケース4: 上書きで消していないラベル（label）は既定が残る（deep merge）
  if printf '%s' "$ov" | jq -e '
      [.axes[] | select(.key=="accountGroup") | .label] == ["アカウント区分"]' >/dev/null 2>&1; then
    echo "  [PASS] ケース4: 未指定フィールドは既定が残る"
  else
    echo "  [FAIL] ケース4: 未指定フィールドが失われた" >&2
    rc=1
  fi

  # ケース5: disabled:true の軸が除外される
  cat > "$tmp/一覧/画面一覧/unit-axes.json" <<'JSON'
{ "specVersion": 1, "axes": [ { "key": "device", "disabled": true } ] }
JSON
  dis="$(resolve_unit_axes "$m")"
  if printf '%s' "$dis" | jq -e '([.axes[].key] | index("device")) == null' >/dev/null 2>&1; then
    echo "  [PASS] ケース5: disabled の軸が除外される"
  else
    echo "  [FAIL] ケース5: disabled の軸が残っている" >&2
    rc=1
  fi

  # ケース6: 解決済み JSON を明示指定で渡すと再マージされない（冪等・disabled が復活しない）
  printf '%s' "$dis" > "$tmp/resolved.json"
  again="$(resolve_unit_axes "$m" "$tmp/resolved.json")"
  if printf '%s' "$again" | jq -e '([.axes[].key] | index("device")) == null' >/dev/null 2>&1; then
    echo "  [PASS] ケース6: 明示指定は再マージされない（冪等）"
  else
    echo "  [FAIL] ケース6: 明示指定で除外済みの軸が復活した" >&2
    rc=1
  fi
  rm -f "$tmp/一覧/画面一覧/unit-axes.json"

  # ケース7: unit_axes_for_kind が appliesTo で絞り込む
  api="$(unit_axes_for_kind "$base" api)"
  if printf '%s' "$api" | jq -e '
      ([.columns[].key] | index("method")) and
      (([.columns[].key] | index("permissions")) == null) and
      ((.axes | length) == 0)' >/dev/null 2>&1; then
    echo "  [PASS] ケース7: appliesTo による絞り込み"
  else
    echo "  [FAIL] ケース7: appliesTo の絞り込みが不正" >&2
    rc=1
  fi

  # ケース8: script 無害化
  expected8='{"a":"\u003c/script\u003e\u0026\u003cb\u003e"}'
  if [ "$(unit_axes_script_safe '{"a":"</script>&<b>"}')" = "$expected8" ]; then
    echo "  [PASS] ケース8: script 無害化"
  else
    echo "  [FAIL] ケース8: script 無害化が不正: $(unit_axes_script_safe '{"a":"</script>&<b>"}')" >&2
    rc=1
  fi

  # ケース9〜13: 妥当性検査の陰性
  if unit_axes_validate '{"specVersion":2,"axes":[],"columns":[]}' >/dev/null 2>&1; then
    echo "  [FAIL] ケース9: specVersion=2 を通した" >&2; rc=1
  else
    echo "  [PASS] ケース9: specVersion 不正で ERROR"
  fi

  if unit_axes_validate '{"specVersion":1,"axes":[{"key":"a","valuePolicy":"closed","values":[]}],"columns":[]}' >/dev/null 2>&1; then
    echo "  [FAIL] ケース10: closed かつ values 空を通した" >&2; rc=1
  else
    echo "  [PASS] ケース10: closed かつ values 空で ERROR"
  fi

  if unit_axes_validate '{"specVersion":1,"axes":[{"key":"a","valuePolicy":"open"}],"columns":[{"key":"a"}]}' >/dev/null 2>&1; then
    echo "  [FAIL] ケース11: キー重複を通した" >&2; rc=1
  else
    echo "  [PASS] ケース11: キー重複で ERROR"
  fi

  if unit_axes_validate '{"specVersion":1,"axes":[{"key":"a","valuePolicy":"open","split":{"eligible":true,"default":true}}],"columns":[]}' >/dev/null 2>&1; then
    echo "  [FAIL] ケース12: split.default=true かつ open を通した" >&2; rc=1
  else
    echo "  [PASS] ケース12: split.default=true かつ open で ERROR"
  fi

  if unit_axes_validate '{"specVersion":1,"axes":[{"key":"none","valuePolicy":"open"}],"columns":[]}' >/dev/null 2>&1; then
    echo "  [FAIL] ケース13: 予約語 none を通した" >&2; rc=1
  else
    echo "  [PASS] ケース13: 予約語 none で ERROR"
  fi

  # ケース14〜17: unit_axes_apply_detect（既定の device 軸の detect 規則で検証）
  cat > "$tmp/detect-manifest.json" <<'JSON'
{ "screens": [
  { "screenKey": "a", "route": "/sp/home", "entryFile": "pages/Home.tsx" },
  { "screenKey": "b", "route": "/dashboard", "entryFile": "src/pages/mobile/list.tsx" },
  { "screenKey": "c", "route": "/settings", "entryFile": "pages/Settings.tsx", "device": "pc" },
  { "screenKey": "d", "route": "/other", "entryFile": "pages/Other.tsx" }
] }
JSON
  detected="$(unit_axes_apply_detect "$base" screen "$tmp/detect-manifest.json")"

  if printf '%s' "$detected" | jq -e '(.screens[] | select(.screenKey=="a") | .device) == "sp"' >/dev/null 2>&1; then
    echo "  [PASS] ケース14: route の一致で device=sp を検出"
  else
    echo "  [FAIL] ケース14: route による検出が不正" >&2
    rc=1
  fi

  if printf '%s' "$detected" | jq -e '(.screens[] | select(.screenKey=="b") | .device) == "sp"' >/dev/null 2>&1; then
    echo "  [PASS] ケース15: route 不一致時に entryFile へフォールバックして検出"
  else
    echo "  [FAIL] ケース15: entryFile へのフォールバック検出が不正" >&2
    rc=1
  fi

  if printf '%s' "$detected" | jq -e '(.screens[] | select(.screenKey=="c") | .device) == "pc"' >/dev/null 2>&1; then
    echo "  [PASS] ケース16: 既存の明示値(pc)を上書きしない"
  else
    echo "  [FAIL] ケース16: 明示値が上書きされた" >&2
    rc=1
  fi

  if printf '%s' "$detected" | jq -e '(.screens[] | select(.screenKey=="d") | has("device")) == false' >/dev/null 2>&1; then
    echo "  [PASS] ケース17: 一致する規則が無ければフィールドを書かない"
  else
    echo "  [FAIL] ケース17: 不一致時にフィールドが書き込まれた" >&2
    rc=1
  fi

  # ケース18〜20: detect を含む妥当性検査の陰性
  if unit_axes_validate '{"specVersion":1,"axes":[{"key":"a","valuePolicy":"open","detect":{"source":[],"rules":[{"value":"x","match":"x"}]}}],"columns":[]}' >/dev/null 2>&1; then
    echo "  [FAIL] ケース18: detect.source が空配列を通した" >&2; rc=1
  else
    echo "  [PASS] ケース18: detect.source が空配列で ERROR"
  fi

  if unit_axes_validate '{"specVersion":1,"axes":[{"key":"a","valuePolicy":"open","detect":{"source":["route"],"rules":[{"match":"x"}]}}],"columns":[]}' >/dev/null 2>&1; then
    echo "  [FAIL] ケース19: detect.rules に value が無いものを通した" >&2; rc=1
  else
    echo "  [PASS] ケース19: detect.rules の value 欠落で ERROR"
  fi

  if unit_axes_validate '{"specVersion":1,"axes":[{"key":"a","valuePolicy":"closed","values":[{"key":"x","label":"X"}],"detect":{"source":["route"],"rules":[{"value":"y","match":"y"}]}}],"columns":[]}' >/dev/null 2>&1; then
    echo "  [FAIL] ケース20: closed 軸で detect.rules[].value が values 外を通した" >&2; rc=1
  else
    echo "  [PASS] ケース20: closed 軸で宣言外の detect 値は ERROR"
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

# 直接実行時のみディスパッチする（source 時は呼び出し元の位置引数を誤読しない）
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ] && [ "${1:-}" = "--self-test" ]; then
  unit_axes_self_test
  exit $?
fi
