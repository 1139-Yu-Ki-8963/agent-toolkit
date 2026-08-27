#!/usr/bin/env bash
# output-layout.sh — 生成物の出力配置（日本語パス）の宣言（output-layout.json）を解決する共通関数
#
# 使い方:
#   source "path/to/output-layout.sh"
#   layout_json="$(resolve_output_layout <output_dir>)" || exit 1
#   path="$(output_layout_get "$layout_json" <キー> [label値])" || exit 1
#
# 解決順（番号が大きいほど優先。同一キーは後から読んだものが勝つ）:
#   1. リポジトリ既定 <このファイルの親>/../../delivery-payload/references/output-layout.json（必須。不在なら ERROR）
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
# 書き込み先の判定を1箇所へ寄せた共通モジュール（lib/safe-write-path.cjs）。
# ここで設定すると、output-layout.sh を読み込む全スクリプトへ届く。
# scaffold-screen.sh・scaffold-design-unit.sh は build-portal.sh を通らないため、
# 呼び出し側ごとに設定すると抜けが生じる。
: "${SAFE_WRITE_PATH_LIB:=${OUTPUT_LAYOUT_DIR}/lib/safe-write-path.cjs}"
export SAFE_WRITE_PATH_LIB
OUTPUT_LAYOUT_DEFAULT="$OUTPUT_LAYOUT_DIR/../../delivery-payload/references/output-layout.json"

# 複数の宣言ファイルをキー単位で deep merge する（各トップレベルキーのオブジェクトを
# キー単位で後勝ちマージする）。
#
# 1-242: 以前はトップレベルキーを名前で列挙していたため、output-layout.json へ
# 新設したキー（kindDirNames・directoryNamePolicy・displayLabels・unitPhaseDirNames）を
# 追記し忘れると合成結果から静かに削り落とされ、{labelDir} 等の解決が空文字になる事故を
# 同一セッション内で3回発生させた。列挙をやめ、入力ファイル群が実際に持つトップレベル
# キーの和集合を動的に求めて合成することで、新設キーを追記漏れなく取り込む。
# specVersion のみ最初のファイルの値を採用する特別扱いとし、それ以外の全キーは
# オブジェクトとして `*`（jq の深いマージ演算子）でキー単位マージする。
output_layout_merge_files() {
  jq -s '
    . as $files
    | ($files | map(keys[]) | unique | map(select(. != "specVersion"))) as $keys
    | reduce $keys[] as $k (
        {specVersion: ($files[0].specVersion // 1)};
        . + { ($k): (reduce $files[] as $f ({}; . * ($f[$k] // {}))) }
      )
  ' "$@"
}

# 相対パス（複数階層可）としての安全性を検査する共通ヘルパー。
# docsRoot・rulesRoot・manifestsRoot・scopeProgressRoot・screenUnitRoot・commonRoot が共用する。
# 拒否条件（維持）:
# - 空文字・null・.・..
# - 絶対パス（/ で始まる）
# - .. を含む（docs/../etc のような上位への脱出。segment 先頭の . で判定し .. も含めて捕捉する）
# - backslash を含む
# - find の glob メタ文字（* ? [ ]）を含む
# - 制御文字（Unicode general category C）・空白類（Unicode general category Z）を含む
# - 非NFC（macOS上の正規化別名を許可しない）
# - 先頭または末尾が /
# - // の連続
# 許容: / で区切られた 1 つ以上の安全な相対 segment（日本語の可視文字・ASCIIハイフンを含む）。
# Unicode判定・正規化にはリポジトリ既存runtimeのNode.jsを使う。
_output_layout_check_relpath() {
  key="$1"
  value="$2"

  if [ -z "$value" ] || [ "$value" = "." ] || [ "$value" = ".." ]; then
    echo "ERROR: output-layout の $key は空・.・.. 以外の安全な相対パスで指定してください" >&2
    return 2
  fi
  case "$value" in
    /*|*/)
      echo "ERROR: output-layout の $key は先頭または末尾に / を含められません" >&2
      return 2
      ;;
  esac
  case "$value" in
    *'//'*)
      echo "ERROR: output-layout の $key に // の連続を含められません" >&2
      return 2
      ;;
  esac
  case "$value" in
    *'\'*|*'*'*|*'?'*|*'['*|*']'*)
      echo "ERROR: output-layout の $key に backslash・find globメタ文字を含められません" >&2
      return 2
      ;;
  esac
  case "$value" in
    .*|*'/.'*)
      echo "ERROR: output-layout の $key の各 segment は . で始められません（.. による上位脱出を含む）" >&2
      return 2
      ;;
  esac
  if ! printf '%s' "$value" | node -e '
    const fs = require("fs");
    const v = fs.readFileSync(0, "utf8");
    if (/[\p{C}\p{Z}]/u.test(v)) process.exit(1);
    if (v.normalize("NFC") !== v) process.exit(1);
  ' >/dev/null 2>&1; then
    echo "ERROR: output-layout の $key はUnicode制御・空白文字を含まずNFCで指定してください" >&2
    return 2
  fi
  return 0
}

# 解決後の宣言の妥当性を fail-fast で検査する。
output_layout_validate() {
  # 同じJSONをキーごとにjq/Nodeへ渡すと、ポータル生成1回につき30近い
  # 短命プロセスが起動する。検査順・拒否条件・エラー文言を保ったまま1プロセスで検査する。
  printf '%s' "$1" | node -e '
    const fs = require("fs");
    let doc;
    try {
      doc = JSON.parse(fs.readFileSync(0, "utf8"));
    } catch (_) {
      process.stderr.write("ERROR: output-layout.json の specVersion が 1 ではありません\n");
      process.exit(2);
    }
    if (doc.specVersion !== 1 && doc.specVersion !== "1") {
      process.stderr.write("ERROR: output-layout.json の specVersion が 1 ではありません\n");
      process.exit(2);
    }
    const layout = doc.layout || {};
    const required = [
      "docsRoot", "rulesRoot", "manifestsRoot", "scopeProgressRoot", "screenUnitRoot", "commonRoot",
      "apiUnitRoot", "tableUnitRoot", "batchUnitRoot", "reportUnitRoot", "externalUnitRoot", "featureUnitRoot",
      "unitTestDesignDir", "permissionFunctionMatrixHtml", "platformDesignHtml", "commonDesignHtml",
      "dataDesignHtml", "messageDesignHtml", "uiCommonDesignHtml"
    ];
    for (const key of required) {
      const value = layout[key];
      if (typeof value !== "string") {
        process.stderr.write(`ERROR: output-layout の ${key} は文字列で必須です\n`);
        process.exit(2);
      }
      if (value === "" || value === "." || value === "..") {
        process.stderr.write(`ERROR: output-layout の ${key} は空・.・.. 以外の安全な相対パスで指定してください\n`);
        process.exit(2);
      }
      if (value.startsWith("/") || value.endsWith("/")) {
        process.stderr.write(`ERROR: output-layout の ${key} は先頭または末尾に / を含められません\n`);
        process.exit(2);
      }
      if (value.includes("//")) {
        process.stderr.write(`ERROR: output-layout の ${key} に // の連続を含められません\n`);
        process.exit(2);
      }
      if (/[\\*?\[\]]/.test(value)) {
        process.stderr.write(`ERROR: output-layout の ${key} に backslash・find globメタ文字を含められません\n`);
        process.exit(2);
      }
      if (value.split("/").some((segment) => segment.startsWith("."))) {
        process.stderr.write(`ERROR: output-layout の ${key} の各 segment は . で始められません（.. による上位脱出を含む）\n`);
        process.exit(2);
      }
      if (/[\p{C}\p{Z}]/u.test(value) || value.normalize("NFC") !== value) {
        process.stderr.write(`ERROR: output-layout の ${key} はUnicode制御・空白文字を含まずNFCで指定してください\n`);
        process.exit(2);
      }
    }

    const rootKeys = [
      "screenUnitRoot", "apiUnitRoot", "tableUnitRoot", "batchUnitRoot",
      "reportUnitRoot", "externalUnitRoot", "featureUnitRoot", "unitsRoot", "commonRoot",
      "crossCuttingDesignRoot", "plansRoot", "recordsRoot"
    ];
    const values = rootKeys
      .map((key) => layout[key])
      .filter((value) => typeof value === "string")
      .map((value) => value.normalize("NFC"));
    if (new Set(values).size !== values.length) {
      process.stderr.write("ERROR: output-layout の種別ごとの物理rootは互いに、また unitsRoot・commonRoot・crossCuttingDesignRoot・plansRoot・recordsRoot とも衝突できません\n");
      process.exit(2);
    }
  '
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
    *'{labelDir}'*)
      if [ -z "$label" ]; then
        echo "ERROR: キー '$key' は {labelDir} を含みますが label 値が指定されていません" >&2
        return 2
      fi
      label_dir="$(printf '%s' "$layout_json" | jq -r --arg l "$label" '
        (.kindLabels // {}) as $kl
        | ([$kl | to_entries[] | select(.value == $l) | .key] | first) as $kind
        | if $kind == null then "" else ((.kindDirNames // {})[$kind] // "") end')"
      if [ -z "$label_dir" ]; then
        echo "ERROR: label '$label' に対応する kindDirNames の値が宣言にありません" >&2
        return 2
      fi
      value="${value//\{labelDir\}/$label_dir}"
      ;;
  esac

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

# output_layout_assert_path <合成JSON> <出力ルート> <キー> <候補出力先>
#
# 出力先を引数で受ける生成経路が、宣言に無い場所へ書き出すことを防ぐ。
# 候補と宣言値は正規化後の絶対パスで比較し、同じ場所だけを受け付ける。
output_layout_assert_path() {
  local layout_json="$1"
  local output_root="$2"
  local key="$3"
  local candidate="$4"
  local declared_rel
  declared_rel="$(output_layout_get "$layout_json" "$key")" || return $?
  node - "$output_root" "$output_root/$declared_rel" "$candidate" "$key" <<'NODE'
const fs = require("fs");
const path = require("path");
const [outputRoot, declared, candidate, key] = process.argv.slice(2);
const root = path.resolve(outputRoot);
const declaredPath = path.resolve(declared);
const candidatePath = path.resolve(candidate);
const relative = path.relative(root, candidatePath);
if (relative === ".." || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) {
  process.stderr.write(`ERROR: ${key} の出力先は出力ルート配下でなければなりません: ${candidate}\n`);
  process.exit(2);
}
let current = path.parse(candidatePath).root;
for (const segment of candidatePath.slice(current.length).split(path.sep).filter(Boolean)) {
  current = path.join(current, segment);
  try {
    if (fs.lstatSync(current).isSymbolicLink() && !require(process.env.SAFE_WRITE_PATH_LIB).isOsStandardLink(current)) {
      process.stderr.write(`ERROR: ${key} の出力先にシンボリックリンクを含められません: ${current}\n`);
      process.exit(2);
    }
  } catch (error) {
    if (error && error.code === "ENOENT") break;
    throw error;
  }
}
if (declaredPath !== candidatePath) {
  process.stderr.write(`ERROR: ${key} の出力先は output-layout の定義と一致しません: ${candidate}\n`);
  process.exit(2);
}
NODE
}

# 合成済み宣言から種別キーの日本語ラベルを取り出す。
# output_layout_kind_label <合成JSON> <kind>
output_layout_kind_label() {
  layout_json="$1"
  kind="$2"

  if ! printf '%s' "$layout_json" | jq -e --arg k "$kind" '.kindLabels | has($k)' >/dev/null 2>&1; then
    echo "ERROR: output-layout の kindLabels に存在しない種別です: $kind" >&2
    return 2
  fi

  printf '%s' "$layout_json" | jq -r --arg k "$kind" '.kindLabels[$k]'
  return 0
}

output_layout_self_test() {
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/output-layout-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼" >&2
    exit 2
  fi
  tmp="$(cd "$tmp" && pwd -P)"
  trap 'rm -rf "$tmp"' RETURN
  rc=0

  # ケース1: 既定のみでキーが取れる
  base="$(resolve_output_layout "$tmp" 2>"$tmp/.resolve-err")" || true
  _gt_resolve_err="$(cat "$tmp/.resolve-err" 2>/dev/null)"
  _gt_case1_jq=""
  if [ -n "$base" ] && _gt_case1_jq="$(printf '%s' "$base" | jq -e '.layout.unitsRoot == "project-portal/lists"' 2>&1)"; then
    echo "  [PASS] ケース1: 既定解決でキーが取れる"
  else
    echo "  [FAIL] ケース1: 既定解決に失敗" >&2
    { printf '%s\n' "$_gt_resolve_err"; printf '%s\n' "$_gt_case1_jq"; printf 'base=%s\n' "$base"; } | sed 's/^/    /' >&2
    rc=1
  fi

  # ケース2: {labelDir}/{label} 置換（label=API）
  v2="$(output_layout_get "$base" unitListHtml API 2>/dev/null)" || true
  if [ "$v2" = "project-portal/lists/apis/API一覧.html" ]; then
    echo "  [PASS] ケース2: {labelDir}/{label} 置換 (label=API)"
  else
    echo "  [FAIL] ケース2: {labelDir}/{label} 置換が不正: $v2" >&2
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
  if printf '%s' "$ov" | jq -e '.layout.commonRoot == "docs/design/common"' >/dev/null 2>&1; then
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

  # ケース6: specVersion は数値1・文字列"1"を受理し、それ以外を return 2
  string_version6="$(printf '%s' "$base" | jq '.specVersion = "1"')"
  output_layout_validate "$string_version6" >/dev/null 2>&1
  rc6_string=$?
  output_layout_validate '{"specVersion":2,"layout":{}}' >/dev/null 2>&1
  rc6=$?
  invalid_string_version6="$(printf '%s' "$base" | jq '.specVersion = "2"')"
  output_layout_validate "$invalid_string_version6" >/dev/null 2>&1
  rc6_invalid_string=$?
  if [ "$rc6_string" -eq 0 ] && [ "$rc6" -eq 2 ] && [ "$rc6_invalid_string" -eq 2 ]; then
    echo "  [PASS] ケース6: specVersion の数値1・文字列\"1\"を受理し、それ以外を return 2"
  else
    echo "  [FAIL] ケース6: specVersion の返り値が不正 (string1=$rc6_string number2=$rc6 string2=$rc6_invalid_string)" >&2
    rc=1
  fi

  # ケース7: 既定解決で kind_label screen が「画面」を返す
  kl7="$(output_layout_kind_label "$base" screen 2>/dev/null)" || true
  if [ "$kl7" = "画面" ]; then
    echo "  [PASS] ケース7: kind_label screen が「画面」を返す"
  else
    echo "  [FAIL] ケース7: kind_label screen が不正: $kl7" >&2
    rc=1
  fi

  # ケース8: 不在 kind で return 2
  output_layout_kind_label "$base" nonExistentKind >/dev/null 2>&1
  rc8=$?
  if [ "$rc8" -eq 2 ]; then
    echo "  [PASS] ケース8: 不在 kind で return 2"
  else
    echo "  [FAIL] ケース8: 不在 kind の返り値が不正 (rc=$rc8, 期待 2)" >&2
    rc=1
  fi

  # ケース9: 対象側上書きで kindLabels の1キーだけ差し替え、他キーは既定のまま残る
  cat > "$tmp/output-layout.json" <<'JSON'
{ "specVersion": 1, "kindLabels": { "screen": "スクリーン" } }
JSON
  ov9="$(resolve_output_layout "$tmp")" || true
  ok9=0
  if printf '%s' "$ov9" | jq -e '.kindLabels.screen == "スクリーン"' >/dev/null 2>&1; then
    ok9=$((ok9 + 1))
  fi
  if printf '%s' "$ov9" | jq -e '.kindLabels.api == "API"' >/dev/null 2>&1; then
    ok9=$((ok9 + 1))
  fi
  if [ "$ok9" -eq 2 ]; then
    echo "  [PASS] ケース9: kindLabels の上書きはキー単位でマージされる（他キーは既定が残る）"
  else
    echo "  [FAIL] ケース9: kindLabels のキー単位マージが不正" >&2
    rc=1
  fi
  rm -f "$tmp/output-layout.json"

  # ケース10: screenUnitRoot の既定値と対象側上書きを解決できる
  sur10="$(output_layout_get "$base" screenUnitRoot 2>/dev/null)" || true
  cat > "$tmp/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "screenUnitRoot": "スクリーン" } }
JSON
  ov10="$(resolve_output_layout "$tmp")" || true
  sur10_override="$(output_layout_get "$ov10" screenUnitRoot 2>/dev/null)" || true
  if [ "$sur10" = "docs/design/screens" ] && [ "$sur10_override" = "スクリーン" ]; then
    echo "  [PASS] ケース10: screenUnitRoot の既定値・上書きを解決"
  else
    echo "  [FAIL] ケース10: screenUnitRoot の解決が不正 (default=$sur10 override=$sur10_override)" >&2
    rc=1
  fi
  rm -f "$tmp/output-layout.json"

  # ケース11: null・空・危険な非単一segmentを拒否する
  invalid11=0
  cat > "$tmp/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "screenUnitRoot": null } }
JSON
  resolve_output_layout "$tmp" >/dev/null 2>&1 && invalid11=$((invalid11 + 1))
  for value11 in "" "." ".." ".git" ".claude" 'a\b' 'a*b' 'a?b' 'a[b' 'a]b'; do
    jq -n --arg value "$value11" \
      '{specVersion: 1, layout: {screenUnitRoot: $value}}' > "$tmp/output-layout.json"
    resolve_output_layout "$tmp" >/dev/null 2>&1 && invalid11=$((invalid11 + 1))
  done
  for value11 in $'line\nbreak' $'tab\tbreak' $'cr\rbreak' $'del\x7fbreak' \
    $'nel\u0085break' $'zero\u200bwidth' $'line\u2028separator' $'no\u00a0break' \
    'has space' '   ' ' leading' 'trailing '; do
    jq -n --arg value "$value11" \
      '{specVersion: 1, layout: {screenUnitRoot: $value}}' > "$tmp/output-layout.json"
    resolve_output_layout "$tmp" >/dev/null 2>&1 && invalid11=$((invalid11 + 1))
  done
  jq -n --arg value 'screen-root' \
    '{specVersion: 1, layout: {screenUnitRoot: $value}}' > "$tmp/output-layout.json"
  resolve_output_layout "$tmp" >/dev/null 2>&1 || invalid11=$((invalid11 + 1))
  for collision_root in commonRoot unitsRoot; do
    collision_value="$(output_layout_get "$base" "$collision_root" 2>/dev/null)"
    jq -n --arg value "$collision_value" \
      '{specVersion: 1, layout: {screenUnitRoot: $value}}' > "$tmp/output-layout.json"
    resolve_output_layout "$tmp" >/dev/null 2>&1 && invalid11=$((invalid11 + 1))
  done
  nfd_common="$(printf '%s' 'プロジェクト共通' | node -e \
    'const fs=require("fs");process.stdout.write(fs.readFileSync(0,"utf8").normalize("NFD"))')"
  nfd_general="$(printf '%s' 'ガイド' | node -e \
    'const fs=require("fs");process.stdout.write(fs.readFileSync(0,"utf8").normalize("NFD"))')"
  for value11 in "$nfd_common" "$nfd_general"; do
    jq -n --arg value "$value11" \
      '{specVersion: 1, layout: {screenUnitRoot: $value}}' > "$tmp/output-layout.json"
    resolve_output_layout "$tmp" >/dev/null 2>&1 && invalid11=$((invalid11 + 1))
  done
  if [ "$invalid11" -eq 0 ]; then
    echo "  [PASS] ケース11: 危険文字・Unicode C/Z・NFD・NFC物理root衝突を拒否しNFC日本語/ハイフンを許可"
  else
    echo "  [FAIL] ケース11: 不正なscreenUnitRootを${invalid11}件受理" >&2
    rc=1
  fi
  rm -f "$tmp/output-layout.json"

  # ケース12: 非永続の作業記録・サンプル記録は納品layoutに持たない
  invalid12=0
  for removed_key in workRecordDoc sampleRecordDoc; do
    output_layout_get "$base" "$removed_key" >/dev/null 2>&1 && invalid12=$((invalid12 + 1))
  done
  if [ "$invalid12" -eq 0 ]; then
    echo "  [PASS] ケース12: 非永続記録キーを納品layoutから除外"
  else
    echo "  [FAIL] ケース12: 除外済み記録キーを${invalid12}件解決できた" >&2
    rc=1
  fi

  # ケース13: 複数階層の相対パスを受理する（docsRoot・rulesRoot・manifestsRoot・
  #           scopeProgressRoot・screenUnitRoot・commonRoot 共通）
  ok13=0
  if printf '%s' "$base" | jq -e '.layout.screenUnitRoot == "docs/design/screens"' >/dev/null 2>&1; then
    ok13=$((ok13 + 1))
  fi
  if printf '%s' "$base" | jq -e '.layout.commonRoot == "docs/design/common"' >/dev/null 2>&1; then
    ok13=$((ok13 + 1))
  fi
  if printf '%s' "$base" | jq -e '.layout.rulesRoot == "docs/rules"' >/dev/null 2>&1; then
    ok13=$((ok13 + 1))
  fi
  cat > "$tmp/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "commonRoot": "docs/design/shared/common" } }
JSON
  ov13="$(resolve_output_layout "$tmp")" || true
  if printf '%s' "$ov13" | jq -e '.layout.commonRoot == "docs/design/shared/common"' >/dev/null 2>&1; then
    ok13=$((ok13 + 1))
  fi
  rm -f "$tmp/output-layout.json"
  if [ "$ok13" -eq 4 ]; then
    echo "  [PASS] ケース13: 複数階層の相対パスを既定値・上書き双方で受理"
  else
    echo "  [FAIL] ケース13: 複数階層の相対パスの受理が不正 (ok13=$ok13)" >&2
    rc=1
  fi

  # ケース14: 8つの拒否条件（rulesRoot に対して検証。screenUnitRoot 以外のキーでも
  #           同じ拒否が働くことを確かめる）
  invalid14=0
  for value14 in "" "." ".." "/docs/rules" "docs/rules/" "docs//rules" \
    'docs\rules' 'docs/ru*les' 'docs/../etc'; do
    jq -n --arg value "$value14" \
      '{specVersion: 1, layout: {rulesRoot: $value}}' > "$tmp/output-layout.json"
    resolve_output_layout "$tmp" >/dev/null 2>&1 && invalid14=$((invalid14 + 1))
  done
  rm -f "$tmp/output-layout.json"
  if [ "$invalid14" -eq 0 ]; then
    echo "  [PASS] ケース14: 8つの拒否条件をrulesRootでも拒否"
  else
    echo "  [FAIL] ケース14: 拒否すべきrulesRootを${invalid14}件受理" >&2
    rc=1
  fi

  # ケース15: 6種別（api/table/batch/report/external/feature）の物理rootと
  #           マニフェストキーが既定値で解決できる
  ok15=0
  for kind15 in api table batch report external feature; do
    root_key15="${kind15}UnitRoot"
    manifest_key15="${kind15}Manifest"
    manifest_ext_key15="${kind15}ManifestExt"
    root_val15="$(output_layout_get "$base" "$root_key15" 2>/dev/null)" || true
    manifest_val15="$(output_layout_get "$base" "$manifest_key15" 2>/dev/null)" || true
    manifest_ext_val15="$(output_layout_get "$base" "$manifest_ext_key15" 2>/dev/null)" || true
    case "$root_val15" in
      docs/design/*) : ;;
      *) echo "  [FAIL] ケース15: $root_key15 の既定値が不正: $root_val15" >&2; continue ;;
    esac
    if [ "$manifest_val15" = "docs/manifests/${kind15}-manifest.json" ] \
      && [ "$manifest_ext_val15" = "docs/manifests/${kind15}-manifest.ext.json" ]; then
      ok15=$((ok15 + 1))
    else
      echo "  [FAIL] ケース15: ${kind15}Manifest系の既定値が不正 (manifest=$manifest_val15 ext=$manifest_ext_val15)" >&2
    fi
  done
  if [ "$ok15" -eq 6 ]; then
    echo "  [PASS] ケース15: 6種別のUnitRoot・Manifest・ManifestExtキーが既定値で解決できる"
  else
    echo "  [FAIL] ケース15: 6種別のうち${ok15}/6件のみ既定値解決に成功" >&2
    rc=1
  fi

  # ケース16: 種別ごとの物理rootが重複する場合は衝突として拒否する
  cat > "$tmp/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "apiUnitRoot": "docs/design/tables" } }
JSON
  local _gt_c16_out
  if _gt_c16_out="$(resolve_output_layout "$tmp" 2>&1)"; then
    echo "  [FAIL] ケース16: apiUnitRootとtableUnitRootの重複値を受理してしまった" >&2
    printf '%s\n' "$_gt_c16_out" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] ケース16: 種別ごとの物理root同士の重複値を拒否"
  fi
  rm -f "$tmp/output-layout.json"

  # ケース17: crossCuttingDesignRoot・plansRoot・recordsRoot が既定値で解決できる
  ok17=0
  ccd17="$(output_layout_get "$base" crossCuttingDesignRoot 2>/dev/null)" || true
  plans17="$(output_layout_get "$base" plansRoot 2>/dev/null)" || true
  records17="$(output_layout_get "$base" recordsRoot 2>/dev/null)" || true
  if [ "$ccd17" = "docs/design/cross-cutting" ]; then
    ok17=$((ok17 + 1))
  fi
  if [ "$plans17" = "docs/tasks" ]; then
    ok17=$((ok17 + 1))
  fi
  if [ "$records17" = "docs/tasks/work-records" ]; then
    ok17=$((ok17 + 1))
  fi
  if [ "$ok17" -eq 3 ]; then
    echo "  [PASS] ケース17: crossCuttingDesignRoot・plansRoot・recordsRootが既定値で解決できる"
  else
    echo "  [FAIL] ケース17: crossCuttingDesignRoot/plansRoot/recordsRootの既定値解決が不正 (ccd=$ccd17 plans=$plans17 records=$records17)" >&2
    rc=1
  fi

  # ケース19: plansRoot が既存の物理rootと重複する場合は衝突として拒否する
  cat > "$tmp/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "plansRoot": "docs/design/common" } }
JSON
  local _gt_c19_out
  if _gt_c19_out="$(resolve_output_layout "$tmp" 2>&1)"; then
    echo "  [FAIL] ケース19: plansRootとcommonRootの重複値を受理してしまった" >&2
    printf '%s\n' "$_gt_c19_out" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] ケース19: plansRootと既存物理rootの重複値を拒否"
  fi
  rm -f "$tmp/output-layout.json"

  # ケース20: 1-242 合成対象外の新規トップレベルキーを持つフィクスチャでも、
  #           動的合成によりそのキーが合成結果へ含まれ空文字にならない
  cat > "$tmp/output-layout.json" <<'JSON'
{ "specVersion": 1, "brandNewTopLevelKey": { "foo": "bar" } }
JSON
  ov20="$(output_layout_merge_files "$OUTPUT_LAYOUT_DEFAULT" "$tmp/output-layout.json")" || true
  v20="$(printf '%s' "$ov20" | jq -r '.brandNewTopLevelKey.foo // ""' 2>/dev/null)"
  if [ "$v20" = "bar" ]; then
    echo "  [PASS] ケース20: 合成対象外の新規トップレベルキーが動的合成で取り込まれる"
  else
    echo "  [FAIL] ケース20: 新規トップレベルキーの合成結果が不正: '$v20'" >&2
    rc=1
  fi
  rm -f "$tmp/output-layout.json"

  # ケース21: 既存の kindDirNames・directoryNamePolicy・displayLabels・
  #           unitPhaseDirNames の4キーが合成結果に含まれ、値が空でないこと
  ok21=0
  for key21 in kindDirNames directoryNamePolicy displayLabels unitPhaseDirNames; do
    _gt_case21_jq="$(printf '%s' "$base" | jq -e --arg k "$key21" '.[$k] != null and (.[$k] | type == "object") and (.[$k] | length > 0)' 2>&1)"
    if [ "$?" -eq 0 ]; then
      ok21=$((ok21 + 1))
    else
      echo "  [FAIL] ケース21: $key21 が合成結果に含まれないか空です" >&2
      printf '%s\n' "$_gt_case21_jq" | sed 's/^/    /' >&2
    fi
  done
  if [ "$ok21" -eq 4 ]; then
    echo "  [PASS] ケース21: kindDirNames・directoryNamePolicy・displayLabels・unitPhaseDirNamesの4キーが合成結果に含まれる"
  else
    echo "  [FAIL] ケース21: 4キーのうち${ok21}/4件のみ合成結果に含まれた" >&2
    rc=1
  fi

  # ケース22: 1-211対象の6鍵は合成後の定義先だけを受け付け、候補引数が
  #           定義外なら全鍵でreturn 2となる
  cat > "$tmp/output-layout.json" <<'JSON'
{
  "specVersion": 1,
  "layout": {
    "permissionFunctionMatrixHtml": "custom/matrices/permission-function.html",
    "platformDesignHtml": "custom/foundation/platform.html",
    "commonDesignHtml": "custom/foundation/common.html",
    "dataDesignHtml": "custom/foundation/data.html",
    "messageDesignHtml": "custom/foundation/message.html",
    "uiCommonDesignHtml": "custom/foundation/ui-common.html"
  }
}
JSON
  ov22="$(resolve_output_layout "$tmp")" || true
  ok22=0
  rejected22=0
  for key22 in permissionFunctionMatrixHtml platformDesignHtml commonDesignHtml dataDesignHtml messageDesignHtml uiCommonDesignHtml; do
    rel22="$(output_layout_get "$ov22" "$key22" 2>/dev/null)" || continue
    if output_layout_assert_path "$ov22" "$tmp" "$key22" "$tmp/$rel22" >/dev/null 2>&1; then
      ok22=$((ok22 + 1))
    fi
    output_layout_assert_path "$ov22" "$tmp" "$key22" "$tmp/undefined/$key22.html" >/dev/null 2>&1
    [ "$?" -eq 2 ] && rejected22=$((rejected22 + 1))
  done
  rm -f "$tmp/output-layout.json"
  if [ "$ok22" -eq 6 ] && [ "$rejected22" -eq 6 ]; then
    echo "  [PASS] ケース22: 1-211対象6鍵の合成定義先を受理し、定義外の候補引数を全鍵で拒否"
  else
    echo "  [FAIL] ケース22: 1-211対象6鍵の出力先検査が不正 (defined=$ok22/6 rejected=$rejected22/6)" >&2
    rc=1
  fi

  # ケース23: 6鍵の宣言値自体に上位脱出を入れた合成定義を全鍵で拒否する
  rejected23=0
  for key23 in permissionFunctionMatrixHtml platformDesignHtml commonDesignHtml dataDesignHtml messageDesignHtml uiCommonDesignHtml; do
    jq -n --arg key "$key23" '{specVersion: 1, layout: {($key): "../../outside.html"}}' > "$tmp/output-layout.json"
    resolve_output_layout "$tmp" >/dev/null 2>&1
    [ "$?" -ne 0 ] && rejected23=$((rejected23 + 1))
  done
  rm -f "$tmp/output-layout.json"
  if [ "$rejected23" -eq 6 ]; then
    echo "  [PASS] ケース23: 1-211対象6鍵の宣言値による出力ルート脱出を全鍵で拒否"
  else
    echo "  [FAIL] ケース23: 1-211対象6鍵のルート脱出を${rejected23}/6件だけ拒否" >&2
    rc=1
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
  output_layout_self_test
  exit $?
fi
