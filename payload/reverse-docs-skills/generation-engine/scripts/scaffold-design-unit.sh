#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESIGN_UNIT_LAYOUT_DEFAULT="$script_dir/../../delivery-payload/references/design-unit-layout.json"
DETAIL_FRONTMATTER_KEYS_DEFAULT="$script_dir/../../delivery-payload/references/detail-design-frontmatter-keys.json"
# shellcheck source=./output-layout.sh
source "$script_dir/output-layout.sh"

# kind（api/table/batch/report/external/feature）から output-layout.json の物理配置キー
# （<kind>UnitRoot）を導出する。未知の kind は呼び出し元の design_unit_field で
# 先に弾かれるため、ここでは対応表の欠落だけを検査する。
unit_root_key_for_kind() {
  case "$1" in
    api) echo "apiUnitRoot" ;;
    table) echo "tableUnitRoot" ;;
    batch) echo "batchUnitRoot" ;;
    report) echo "reportUnitRoot" ;;
    external) echo "externalUnitRoot" ;;
    feature) echo "featureUnitRoot" ;;
    *)
      echo "エラー: output-layout の物理配置キーが未定義の種別です: $1" >&2
      return 1
      ;;
  esac
}

# scaffold-design-unit.sh — 非画面種別（API・テーブル・バッチ・帳票・外部連携・機能）の
# リバース検証テンプレートを対象プロジェクトへ展開する
#
# 使い方:
#   scaffold-design-unit.sh <kind> <phase> <output_dir> <識別子> [表示名] [template_root]
#   scaffold-design-unit.sh --overwrite <kind> <phase> <output_dir> <識別子> [表示名] [template_root]
#   scaffold-design-unit.sh --check-missing <kind> <phase> <output_dir> <識別子> [表示名] [template_root]
#   scaffold-design-unit.sh --verify <kind> <phase> <output_dir> <識別子> [表示名] [template_root]
#   scaffold-design-unit.sh --dry-run <kind> <phase> <output_dir> <識別子> [表示名] [template_root]
#   scaffold-design-unit.sh --backfill-basic <output_dir> [template_root]
#   scaffold-design-unit.sh --backfill-test <output_dir> [template_root]
#
# 引数:
#   kind          api / table / batch / report / external / feature のいずれか
#   phase         basic / detail / test のいずれか（feature は detail を持たない）
#   output_dir    設計書展開先ルート（呼び出し元スキルが起動引数として渡す）
#   識別子        単位識別子（例: get-users）
#   表示名        日本語の表示名（省略時は識別子をそのまま使う）
#   template_root テンプレート原本ルート（省略時はスクリプト位置基準の既定値
#                 `<スクリプトのあるディレクトリ>/../../delivery-payload/templates/リバース検証` を使う）
#
# ファイル束の宣言は delivery-payload/references/design-unit-layout.json を参照する。
# 通常実行は不足ファイルだけを追加し、既存ファイルを上書きしない。宣言ファイルを
# 再配置して既存内容も置き換える場合だけ、先頭オプション --overwrite を指定する。

# 書込先自身と、そこへ至る既存path componentをlstatで検査する。
# symlinkを1つでも含む場合は、リンク先のrepo外treeへ書かないようfail closedにする。
assert_no_symlink_output_path() {
  node - "$1" "$2" <<'NODE'
const fs = require("fs");
const path = require("path");
function lexicalAbsolute(raw) {
  return path.isAbsolute(raw) ? raw : `${process.cwd()}${path.sep}${raw}`;
}
function assertNoLexicalSymlink(raw) {
  const absolute = lexicalAbsolute(raw);
  const parsed = path.parse(absolute);
  let current = parsed.root;
  for (const segment of absolute.slice(parsed.root.length).split(path.sep)) {
    if (!segment || segment === ".") continue;
    if (segment === "..") {
      current = path.dirname(current);
      continue;
    }
    current = path.join(current, segment);
    try {
      if (fs.lstatSync(current).isSymbolicLink() && !require(process.env.SAFE_WRITE_PATH_LIB).isOsStandardLink(current)) {
        throw new Error(`write path must not contain a symbolic link: ${current}`);
      }
    } catch (error) {
      if (error && error.code === "ENOENT") continue;
      throw error;
    }
  }
}
assertNoLexicalSymlink(process.argv[2]);
assertNoLexicalSymlink(process.argv[3]);
const outputRoot = path.resolve(process.argv[2]);
const target = path.resolve(process.argv[3]);
const relative = path.relative(outputRoot, target);
if (relative === ".." || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) {
  throw new Error(`write path must stay under output_dir: ${target}`);
}
const parsed = path.parse(target);
let current = parsed.root;
for (const segment of target.slice(parsed.root.length).split(path.sep).filter(Boolean)) {
  current = path.join(current, segment);
  let stat;
  try {
    stat = fs.lstatSync(current);
  } catch (error) {
    if (error && error.code === "ENOENT") break;
    throw error;
  }
  if (stat.isSymbolicLink() && !require(process.env.SAFE_WRITE_PATH_LIB).isOsStandardLink(current)) {
    throw new Error(`write path must not contain a symbolic link: ${current}`);
  }
}
NODE
}

# 宣言 JSON を読み、jq で妥当性を検査してから中身を stdout へ返す。
design_unit_layout_load() {
  if [ ! -f "$DESIGN_UNIT_LAYOUT_DEFAULT" ]; then
    echo "エラー: 宣言ファイルが見つかりません: $DESIGN_UNIT_LAYOUT_DEFAULT" >&2
    return 1
  fi
  if ! jq -e '.specVersion == "1.0.0"' "$DESIGN_UNIT_LAYOUT_DEFAULT" >/dev/null 2>&1; then
    echo "エラー: design-unit-layout.json の specVersion が不正です" >&2
    return 1
  fi
  cat "$DESIGN_UNIT_LAYOUT_DEFAULT"
}

# 宣言 JSON から種別のフィールド（label / token）を取り出す。未知の種別は return 1。
design_unit_field() {
  local json="$1" kind="$2" field="$3"
  if ! printf '%s' "$json" | jq -e --arg k "$kind" '.kinds | has($k)' >/dev/null 2>&1; then
    echo "エラー: 未知の種別です: $kind" >&2
    return 1
  fi
  printf '%s' "$json" | jq -r --arg k "$kind" --arg f "$field" '.kinds[$k][$f]'
}

# 宣言 JSON から種別・phase のファイル束（改行区切り）を取り出す。未知の phase は return 1。
design_unit_phase_files() {
  local json="$1" kind="$2" phase="$3"
  if ! printf '%s' "$json" | jq -e --arg k "$kind" --arg p "$phase" '.kinds[$k].phases | has($p)' >/dev/null 2>&1; then
    echo "エラー: 未知の phase です: $phase" >&2
    return 1
  fi
  printf '%s' "$json" | jq -r --arg k "$kind" --arg p "$phase" '.kinds[$k].phases[$p][]'
}

# 実装契約の節が関連資料の直前に置かれているかを検査する。
# 対象は design-unit-layout.json の kinds のうち detail phase にファイルを持つ
# api/table/batch/report/external と、design-unit-layout.json の対象外である画面
# （scaffold-screen.sh 経由で別管理）。機能（feature）は detail が空であり対象外とする。
check_impl_contract_adjacency() {
  local file="$1" headings impl_line impl_num next_line
  if [ ! -f "$file" ]; then
    echo "エラー: 検査対象のテンプレートが見つかりません: $file" >&2
    return 1
  fi
  headings="$(grep -n '^## §' "$file")"
  impl_line="$(printf '%s\n' "$headings" | grep '実装契約' | head -1)"
  if [ -z "$impl_line" ]; then
    echo "エラー: §実装契約の見出しがありません: $file" >&2
    return 1
  fi
  impl_num="$(printf '%s' "$impl_line" | cut -d: -f1)"
  next_line="$(printf '%s\n' "$headings" | awk -F: -v n="$impl_num" '$1 > n' | sort -t: -k1,1n | head -1)"
  if [ -z "$next_line" ] || ! printf '%s' "$next_line" | grep -q '関連資料'; then
    echo "エラー: §実装契約の直後が§関連資料ではありません: $file" >&2
    return 1
  fi
  return 0
}

# phase キーを配置フォルダ名へ変換する。
# basic・detail・testの名前はいずれもoutput-layout.jsonを正とする（1-210）。
# basic・detailはunitPhaseDirNames.basic・.detailを読む。このキーは
# layoutオブジェクトの外（トップレベル）にありoutput_layout_getでは引けず、
# build-portal.sh・build-manifests-from-docs.shの既存踏襲どおり合成JSONへ
# 直接jqで問い合わせる。testの名前はunitTestDesignDirを正とする。
design_unit_phase_label() {
  case "$1" in
    basic|detail)
      local resolved_layout value
      resolved_layout="$(resolve_output_layout "${2:-}")" || return 1
      value="$(printf '%s' "$resolved_layout" | jq -r --arg k "$1" '.unitPhaseDirNames[$k] // empty')"
      if [ -z "$value" ]; then
        echo "エラー: unitPhaseDirNames に $1 の定義がありません" >&2
        return 1
      fi
      printf '%s\n' "$value"
      ;;
    test)
      local resolved_layout
      resolved_layout="$(resolve_output_layout "${2:-}")" || return 1
      output_layout_get "$resolved_layout" unitTestDesignDir
      ;;
    *)
      echo "エラー: 未知の phase です: $1" >&2
      return 1
      ;;
  esac
}

# 宣言されたファイルを展開する。通常生成と既存詳細設計からの一括補完では不足分だけを
# 配置し、overwrite=1 の場合だけ宣言ファイル全件を再配置する。
scaffold_missing_phase_files() {
  local phase_dir="$1" unit_dir="$2" phase="$3" unit_id="$4"
  local template_dir="$5" label="$6" token="$7" display_name="$8" phase_files="$9" overwrite="${10}"
  local files_to_stage="" staging file ok staged_file destination phase_dir_existed=0

  if [ -d "$phase_dir" ]; then
    phase_dir_existed=1
  fi

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    if [ -L "$phase_dir/$file" ]; then
      echo "エラー: 宣言ファイルがシンボリックリンクです: $phase_dir/$file" >&2
      return 1
    fi
    if [ -e "$phase_dir/$file" ] && [ ! -f "$phase_dir/$file" ]; then
      echo "エラー: 宣言ファイルの配置先が通常ファイルではありません: $phase_dir/$file" >&2
      return 1
    fi
    if [ "$overwrite" -eq 1 ] || [ ! -f "$phase_dir/$file" ]; then
      files_to_stage="${files_to_stage}${file}"$'\n'
    fi
  done <<< "$phase_files"
  if [ -z "$files_to_stage" ]; then
    echo "補完不要: $phase_dir の宣言ファイルはすべて実在します"
    return 0
  fi

  echo "設計単位テンプレートを展開: $phase_dir"
  staging="$unit_dir/.staging-${phase}-${unit_id}.$$"
  rm -rf "$staging"
  mkdir -p "$staging"
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    if [ ! -f "$template_dir/$label/$file" ]; then
      rm -rf "$staging"
      echo "エラー: テンプレートファイルが見つかりません: $template_dir/$label/$file" >&2
      return 1
    fi
    cp "$template_dir/$label/$file" "$staging/$file"
  done <<< "$files_to_stage"

  echo "プレースホルダを置換: $token → $display_name"
  while IFS= read -r file; do
    ok=1
    sed -i.bak "s/${token}/${display_name}/g" "$file" || ok=0
    rm -f "${file}.bak"
    if [ "$ok" -eq 0 ]; then
      rm -rf "$staging"
      echo "エラー: プレースホルダ置換に失敗しました: $file" >&2
      return 1
    fi
  done < <(find "$staging" -name '*.md' -type f)
  if ! node "$script_dir/materialize-introduction-guidance.mjs" "$staging"; then
    rm -rf "$staging"
    echo "エラー: 冒頭案内の本文展開に失敗しました: $staging" >&2
    return 1
  fi

  if [ "$phase_dir_existed" -eq 0 ]; then
    # 通常生成は従来どおり、完成したstagingをディレクトリ単位で配置する。
    mv "$staging" "$phase_dir"
  else
    # 既存phaseでは宣言対象だけを個別に配置する。通常時は不足分だけ、
    # --overwrite時はstaging済みの宣言ファイルを明示的に置き換える。
    while IFS= read -r staged_file; do
      [ -n "$staged_file" ] || continue
      destination="$phase_dir/$(basename "$staged_file")"
      if [ -L "$destination" ]; then
        rm -rf "$staging"
        echo "エラー: 宣言ファイルがシンボリックリンクです: $destination" >&2
        return 1
      fi
      if [ -e "$destination" ] && [ ! -f "$destination" ]; then
        rm -rf "$staging"
        echo "エラー: 宣言ファイルの配置先が通常ファイルではありません: $destination" >&2
        return 1
      fi
      if [ "$overwrite" -eq 1 ] || [ ! -e "$destination" ]; then
        mv -f "$staged_file" "$destination"
      fi
    done < <(find "$staging" -maxdepth 1 -type f | LC_ALL=C sort)
    rmdir "$staging"
  fi
}

# テンプレートファイルのfrontmatter(先頭の --- から次の --- まで)を抽出する。
extract_frontmatter_block() {
  local file="$1"
  awk '
    NR == 1 {
      if ($0 != "---") { exit }
      delim = 1
      next
    }
    /^---[ \t]*$/ {
      exit
    }
    delim == 1 { print }
  ' "$file"
}

# frontmatter のトップレベルにある identifier 形式の鍵を集合として抽出する。
# インデントされた子要素とコメント行は対象外とし、比較可能なよう常に sort -u する。
extract_frontmatter_top_level_keys() {
  local file="$1"
  extract_frontmatter_block "$file" \
    | grep -v '^[[:space:]]*#' \
    | grep -E '^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:' \
    | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*:.*/\1/' \
    | LC_ALL=C sort -u \
    || true
}

# 詳細設計書はテンプレート自身を期待値にせず、機械可読な契約を期待値にする。
# これによりテンプレートと生成物が同じ誤りを持つ場合も検出できる。
detail_frontmatter_expected_keys() {
  local kind="$1"
  if [ ! -f "$DETAIL_FRONTMATTER_KEYS_DEFAULT" ]; then
    echo "エラー: 詳細設計書frontmatter定義がありません: $DETAIL_FRONTMATTER_KEYS_DEFAULT" >&2
    return 1
  fi
  if ! jq -e --arg kind "$kind" '.kinds[$kind].keys | type == "array" and length > 0' \
      "$DETAIL_FRONTMATTER_KEYS_DEFAULT" >/dev/null 2>&1; then
    echo "エラー: 詳細設計書frontmatter定義に種別がありません: $kind" >&2
    return 1
  fi
  jq -r --arg kind "$kind" '.kinds[$kind].keys[]' "$DETAIL_FRONTMATTER_KEYS_DEFAULT" \
    | LC_ALL=C sort -u
}

# frontmatterブロックから、2文字以上の全大文字英字の連なり(トークン候補)を
# 重複除去して抽出する。コメント行(#で始まる行)は、テンプレートの説明文であり
# プレースホルダではないため対象から除く(例: APIテンプレートの
# 「# API基本設計書テンプレート」というコメント中の「API」は種別名の地の文で
# あり、未置換のプレースホルダではない)。design-unit-layout.jsonのtoken自体も
# ここに含まれうるが、二重検出は許容する(1件目で止めない設計方針のため)。
extract_allcaps_tokens() {
  local file="$1"
  extract_frontmatter_block "$file" | grep -v '^[[:space:]]*#' | grep -oE '[A-Z]{2,}' | LC_ALL=C sort -u
}

if [ "${1:-}" = "--self-test" ]; then
  self_test() {
    local self_path pass=0 fail=0
    self_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/design-unit-scaffold-selftest.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
      echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
      exit 2
    fi
    tmp="$(cd "$tmp" && pwd -P)"
    trap 'rm -rf "$tmp"' EXIT

    mkdir -p "$tmp/docs_ok"
    ok_all=1
    for kind in api table batch report external; do
      for phase in basic detail; do
        if ! bash "$self_path" "$kind" "$phase" "$tmp/docs_ok" "selftest-${kind}" "セルフテスト${kind}" >/dev/null 2>&1; then
          echo "FAIL: 展開に失敗しました: $kind $phase" >&2
          ok_all=0
          continue
        fi
        # テンプレートの未置換の欄を検知できるようにする指示書: 新設した全大文字
        # トークン検査により、判定材料欄等(scaffold自体が置換しない欄)が未記入の
        # ままだと--verifyが不合格になる。ここでは展開処理自体の正常動作を検証
        # したいだけなので、frontmatter内の未置換欄をダミー値で機械的に埋めてから
        # verifyを呼ぶ。
        selftest_layout_json_st="$(resolve_output_layout "$tmp/docs_ok")" || { ok_all=0; continue; }
        selftest_unit_root_key_st="$(unit_root_key_for_kind "$kind")" || { ok_all=0; continue; }
        selftest_unit_root_rel_st="$(output_layout_get "$selftest_layout_json_st" "$selftest_unit_root_key_st")" || { ok_all=0; continue; }
        selftest_phase_label_st="$(design_unit_phase_label "$phase" "$tmp/docs_ok")" || { ok_all=0; continue; }
        selftest_phase_dir_st="$tmp/docs_ok/$selftest_unit_root_rel_st/${kind}-selftest-${kind}/$selftest_phase_label_st"
        while IFS= read -r selftest_fill_file; do
          [ -z "$selftest_fill_file" ] && continue
          sed -i.bak -E 's/^([a-z_]+): [A-Z]{2,}$/\1: dummy-value/' "$selftest_fill_file"
          rm -f "${selftest_fill_file}.bak"
        done < <(find "$selftest_phase_dir_st" -name '*.md' -type f)
        if ! bash "$self_path" --verify "$kind" "$phase" "$tmp/docs_ok" "selftest-${kind}" >/dev/null 2>&1; then
          echo "FAIL: verifyに失敗しました: $kind $phase" >&2
          ok_all=0
        fi
      done
    done
    if [ "$ok_all" -eq 1 ]; then
      echo "PASS: 5種別×2phaseの展開とverifyが全件成功" >&2
      pass=$((pass + 1))
    else
      echo "FAIL: 5種別×2phaseの展開とverifyのいずれかが失敗" >&2
      fail=$((fail + 1))
    fi

    # 対象側のoutput-layout.jsonで3phaseの名前を変えた場合も、その宣言値へ展開する。
    custom_phase_root="$tmp/docs_custom_phase"
    mkdir -p "$custom_phase_root"
    cat > "$custom_phase_root/output-layout.json" <<'JSON'
{
  "specVersion": 1,
  "unitPhaseDirNames": {
    "basic": "foundation-spec",
    "detail": "implementation-spec"
  },
  "layout": {
    "unitTestDesignDir": "quality-spec"
  }
}
JSON
    custom_phase_ok=1
    for custom_phase_pair in "basic:foundation-spec" "detail:implementation-spec" "test:quality-spec"; do
      custom_phase="${custom_phase_pair%%:*}"
      custom_phase_dir="${custom_phase_pair#*:}"
      if ! bash "$self_path" api "$custom_phase" "$custom_phase_root" custom-layout-api "宣言追従API" >/dev/null 2>&1; then
        custom_phase_ok=0
        continue
      fi
      if [ ! -d "$custom_phase_root/docs/design/apis/api-custom-layout-api/$custom_phase_dir" ]; then
        custom_phase_ok=0
      fi
    done
    if [ "$custom_phase_ok" -eq 1 ]; then
      echo "PASS: 基本設計・詳細設計・テスト設計を対象側の配置宣言どおりに展開" >&2
      pass=$((pass + 1))
    else
      echo "FAIL: 対象側の3phase配置宣言への追従" >&2
      fail=$((fail + 1))
    fi

    # API詳細設計書のcanonical frontmatter集合を正常系・欠落・余剰で検査する。
    frontmatter_root="$tmp/docs_frontmatter"
    mkdir -p "$frontmatter_root"
    if bash "$self_path" api detail "$frontmatter_root" frontmatter-api "前付け検査API" >/dev/null 2>&1; then
      frontmatter_layout_json="$(resolve_output_layout "$frontmatter_root")"
      frontmatter_root_rel="$(output_layout_get "$frontmatter_layout_json" apiUnitRoot)"
      frontmatter_file="$frontmatter_root/$frontmatter_root_rel/api-frontmatter-api/detail-design/API詳細設計書.md"
      sed -i.bak \
        -e 's/APIKEY/api-selftest-key/g' \
        -e 's/APIID/api-selftest-id/g' \
        -e 's/METHOD/GET/g' \
        -e 's#PATH#/selftest#g' \
        -e 's/FEATUREKEY/feature-selftest/g' \
        -e 's#SOURCEREF#src/api.js#g' \
        "$frontmatter_file"
      rm -f "$frontmatter_file.bak"
      frontmatter_original="$tmp/api-detail-frontmatter-original.md"
      cp "$frontmatter_file" "$frontmatter_original"

      if bash "$self_path" --verify api detail "$frontmatter_root" frontmatter-api >/dev/null 2>&1; then
        echo "PASS: API詳細設計書の値置換済みcanonical frontmatterをverify" >&2
        pass=$((pass + 1))
      else
        echo "FAIL: API詳細設計書の値置換済みcanonical frontmatterをverify" >&2
        fail=$((fail + 1))
      fi

      sed -i.bak '/^feature_key:/d' "$frontmatter_file"
      rm -f "$frontmatter_file.bak"
      if bash "$self_path" --verify api detail "$frontmatter_root" frontmatter-api >/dev/null 2>&1; then
        echo "FAIL: feature_key欠落をverifyが受理" >&2
        fail=$((fail + 1))
      else
        echo "PASS: feature_key欠落をverifyが拒否" >&2
        pass=$((pass + 1))
      fi
      cp "$frontmatter_original" "$frontmatter_file"

      sed -i.bak '/^unit_kind: api$/a\
title: 余剰鍵' "$frontmatter_file"
      rm -f "$frontmatter_file.bak"
      if bash "$self_path" --verify api detail "$frontmatter_root" frontmatter-api >/dev/null 2>&1; then
        echo "FAIL: title余剰をverifyが受理" >&2
        fail=$((fail + 1))
      else
        echo "PASS: title余剰をverifyが拒否" >&2
        pass=$((pass + 1))
      fi
      cp "$frontmatter_original" "$frontmatter_file"
    else
      echo "FAIL: frontmatter完全一致fixtureの初回展開" >&2
      fail=$((fail + 3))
    fi

    # 既存phaseへ様式追加分だけを配置し、既存ファイルを既定では保持する。
    # 1-219で基本設計とテスト設計を分離したため、複数ファイルを宣言する
    # api/testをfixtureに使う。
    incremental_root="$tmp/docs_incremental"
    mkdir -p "$incremental_root"
    if bash "$self_path" api test "$incremental_root" incremental-api "既存API" >/dev/null 2>&1; then
      incremental_layout_json="$(resolve_output_layout "$incremental_root")"
      incremental_root_rel="$(output_layout_get "$incremental_layout_json" apiUnitRoot)"
      incremental_phase_label="$(output_layout_get "$incremental_layout_json" unitTestDesignDir)"
      incremental_phase_dir="$incremental_root/$incremental_root_rel/api-incremental-api/$incremental_phase_label"
      incremental_existing="$incremental_phase_dir/API結合テスト設計書.md"
      incremental_added="$incremental_phase_dir/API単体テスト設計書.md"
      printf '\n既存内容は保持する\n' >> "$incremental_existing"
      existing_before="$(cksum "$incremental_existing")"
      rm -f "$incremental_added"
      missing_out="$(bash "$self_path" --check-missing api test "$incremental_root" incremental-api 2>&1)" && missing_rc=0 || missing_rc=$?
      if [ "$missing_rc" -ne 0 ] && printf '%s\n' "$missing_out" | grep -q 'API単体テスト設計書.md' \
         && bash "$self_path" api test "$incremental_root" incremental-api "既存API" >/dev/null 2>&1 \
         && [ -f "$incremental_added" ] \
         && [ "$existing_before" = "$(cksum "$incremental_existing")" ] \
         && bash "$self_path" --check-missing api test "$incremental_root" incremental-api >/dev/null 2>&1; then
        echo "PASS: 既存phaseへ不足分だけを追加し、既存ファイルを保持" >&2
        pass=$((pass + 1))
      else
        echo "FAIL: 既存phaseへの不足分追加または不足列挙" >&2
        fail=$((fail + 1))
      fi

      if bash "$self_path" --overwrite api test "$incremental_root" incremental-api "既存API" >/dev/null 2>&1 \
         && ! grep -q '既存内容は保持する' "$incremental_existing"; then
        echo "PASS: --overwrite指定時だけ既存ファイルを再配置" >&2
        pass=$((pass + 1))
      else
        echo "FAIL: --overwriteによる明示的な再配置" >&2
        fail=$((fail + 1))
      fi
    else
      echo "FAIL: 追加配置fixtureの初回展開" >&2
      fail=$((fail + 2))
    fi

    # 詳細設計が存在するAPI 50件のうち12件だけに基本設計がある状態を再現し、
    # 残りを差分補完する。さらに他4種別も含め、配置定義が要求する基本設計
    # ファイル数と生成後の実在数を横断して照合する。
    backfill_root="$tmp/docs_backfill"
    mkdir -p "$backfill_root"
    backfill_layout_json="$(design_unit_layout_load)" || {
      echo "FAIL: 補完fixture用の配置定義を読めません" >&2
      fail=$((fail + 1))
    }
    # 直前の既存self-testで解決・検証済みの既定配置を再利用する。fixture準備で
    # 50+12件分のscaffoldや同一配置の再検証を繰り返さない。
    backfill_output_layout="$selftest_layout_json_st"
    backfill_template_root="$script_dir/../../delivery-payload/templates/リバース検証"
    api_root_rel="$(output_layout_get "$backfill_output_layout" apiUnitRoot)"
    api_root="$backfill_root/$api_root_rel"
    api_label="$(design_unit_field "$backfill_layout_json" api label)"
    api_detail_file="$(design_unit_phase_files "$backfill_layout_json" api detail)"
    api_basic_files="$(design_unit_phase_files "$backfill_layout_json" api basic)"
    for i in $(seq 1 50); do
      api_id="backfill-api-${i}"
      api_unit_dir="$api_root/api-$api_id"
      mkdir -p "$api_unit_dir/detail-design"
      cp "$backfill_template_root/$api_label/$api_detail_file" "$api_unit_dir/detail-design/$api_detail_file"
      if [ "$i" -le 12 ]; then
        mkdir -p "$api_unit_dir/basic-design"
        while IFS= read -r api_basic_file; do
          cp "$backfill_template_root/$api_label/$api_basic_file" "$api_unit_dir/basic-design/$api_basic_file"
        done <<< "$api_basic_files"
      fi
    done
    for kind in table batch report external; do
      kind_root_key="$(unit_root_key_for_kind "$kind")"
      kind_root_rel="$(output_layout_get "$backfill_output_layout" "$kind_root_key")"
      kind_label="$(design_unit_field "$backfill_layout_json" "$kind" label)"
      kind_detail_file="$(design_unit_phase_files "$backfill_layout_json" "$kind" detail)"
      kind_unit_dir="$backfill_root/$kind_root_rel/${kind}-backfill-${kind}"
      mkdir -p "$kind_unit_dir/detail-design"
      cp "$backfill_template_root/$kind_label/$kind_detail_file" "$kind_unit_dir/detail-design/$kind_detail_file"
    done
    existing_before="$(for i in $(seq 1 12); do find "$api_root/api-backfill-api-${i}/basic-design" -type f -exec cksum {} +; done | LC_ALL=C sort)"
    if bash "$self_path" --backfill-basic "$backfill_root" >/dev/null 2>&1; then
      existing_after="$(for i in $(seq 1 12); do find "$api_root/api-backfill-api-${i}/basic-design" -type f -exec cksum {} +; done | LC_ALL=C sort)"
      api_detail_count="$(find "$api_root" -path '*/detail-design/API詳細設計書.md' -type f | wc -l | tr -d ' ')"
      api_basic_count="$(find "$api_root" -path '*/basic-design/*.md' -type f | wc -l | tr -d ' ')"
      layout_path="$script_dir/../../delivery-payload/references/design-unit-layout.json"
      expected_basic_count=0
      actual_basic_count=0
      for kind in api table batch report external; do
        kind_root_key="$(unit_root_key_for_kind "$kind")"
        kind_root_rel="$(output_layout_get "$backfill_output_layout" "$kind_root_key")"
        basic_file_count="$(jq -r --arg k "$kind" '.kinds[$k].phases.basic | length' "$layout_path")"
        unit_count="$(find "$backfill_root/$kind_root_rel" -mindepth 1 -maxdepth 1 -type d -name "${kind}-*" | wc -l | tr -d ' ')"
        expected_basic_count=$((expected_basic_count + basic_file_count * unit_count))
        while IFS= read -r declared_file; do
          [ -n "$declared_file" ] || continue
          found_count="$(find "$backfill_root/$kind_root_rel" -path "*/basic-design/$declared_file" -type f | wc -l | tr -d ' ')"
          actual_basic_count=$((actual_basic_count + found_count))
        done < <(jq -r --arg k "$kind" '.kinds[$k].phases.basic[]' "$layout_path")
      done
      if [ "$api_detail_count" -eq 50 ] && [ "$api_basic_count" -eq 50 ] \
         && [ "$expected_basic_count" -eq 54 ] && [ "$actual_basic_count" -eq "$expected_basic_count" ] \
         && [ "$existing_before" = "$existing_after" ]; then
        echo "PASS: 50 API（既存12件）を差分補完し、5種別の基本設計定義54件と実在54件が一致" >&2
        pass=$((pass + 1))
      else
        echo "FAIL: 全ユニット差分補完（API詳細=${api_detail_count}, API基本=${api_basic_count}, 定義=${expected_basic_count}, 実在=${actual_basic_count}, 既存保持=$([ "$existing_before" = "$existing_after" ] && echo yes || echo no)）" >&2
        fail=$((fail + 1))
      fi
    else
      echo "FAIL: --backfill-basic の実行に失敗" >&2
      fail=$((fail + 1))
    fi

    # testフェーズの後埋め（--backfill-test）。
    # 詳細設計は揃っているユニットを合成する。ただしtestフェーズのファイルは欠けさせる。
    # 空のユニットと、一部だけ欠けたユニット（部分）を6種別で用意する。
    # 後埋め後に宣言ファイルが実在することを確認する。既存ファイルが上書きされないことも確認する。
    # 機能（feature）はdetailフォルダを作らずに合成する。detailを持たない種別でも後埋め対象になることを確認する。
    bft_root="$tmp/docs_backfill_test"
    mkdir -p "$bft_root"
    bft_ok=1
    for bft_kind in api table batch report external feature; do
      bft_root_key="$(unit_root_key_for_kind "$bft_kind")" || { bft_ok=0; continue; }
      bft_root_rel="$(output_layout_get "$backfill_output_layout" "$bft_root_key")" || { bft_ok=0; continue; }
      bft_kind_root="$bft_root/$bft_root_rel"
      bft_label="$(design_unit_field "$backfill_layout_json" "$bft_kind" label)" || { bft_ok=0; continue; }
      bft_test_files="$(design_unit_phase_files "$backfill_layout_json" "$bft_kind" test)" || { bft_ok=0; continue; }
      bft_first_test_file="$(printf '%s\n' "$bft_test_files" | head -1)"
      bft_empty_dir="$bft_kind_root/${bft_kind}-empty-${bft_kind}"
      bft_partial_dir="$bft_kind_root/${bft_kind}-partial-${bft_kind}"
      mkdir -p "$bft_empty_dir" "$bft_partial_dir"
      if [ "$bft_kind" != "feature" ]; then
        bft_detail_files="$(design_unit_phase_files "$backfill_layout_json" "$bft_kind" detail)" || { bft_ok=0; continue; }
        mkdir -p "$bft_empty_dir/detail-design" "$bft_partial_dir/detail-design"
        while IFS= read -r bft_detail_file; do
          [ -n "$bft_detail_file" ] || continue
          cp "$backfill_template_root/$bft_label/$bft_detail_file" "$bft_empty_dir/detail-design/$bft_detail_file"
          cp "$backfill_template_root/$bft_label/$bft_detail_file" "$bft_partial_dir/detail-design/$bft_detail_file"
        done <<< "$bft_detail_files"
      fi
      bft_partial_test_label="$(design_unit_phase_label test "$bft_root")" || { bft_ok=0; continue; }
      mkdir -p "$bft_partial_dir/$bft_partial_test_label"
      printf '既存内容は保持する\n' > "$bft_partial_dir/$bft_partial_test_label/$bft_first_test_file"
      echo "$bft_partial_dir/$bft_partial_test_label/$bft_first_test_file" >> "$tmp/bft-existing-list.txt"
    done
    bft_partial_before="$(LC_ALL=C sort "$tmp/bft-existing-list.txt" | xargs cksum)"
    if [ "$bft_ok" -eq 1 ] && bash "$self_path" --backfill-test "$bft_root" >/dev/null 2>&1; then
      bft_partial_after="$(LC_ALL=C sort "$tmp/bft-existing-list.txt" | xargs cksum)"
      bft_expected=0
      bft_actual=0
      for bft_kind in api table batch report external feature; do
        bft_root_key="$(unit_root_key_for_kind "$bft_kind")" || { bft_ok=0; continue; }
        bft_root_rel="$(output_layout_get "$backfill_output_layout" "$bft_root_key")" || { bft_ok=0; continue; }
        bft_kind_root="$bft_root/$bft_root_rel"
        bft_test_files="$(design_unit_phase_files "$backfill_layout_json" "$bft_kind" test)"
        bft_test_label="$(design_unit_phase_label test "$bft_root")" || { bft_ok=0; continue; }
        while IFS= read -r bft_test_file; do
          [ -n "$bft_test_file" ] || continue
          bft_expected=$((bft_expected + 2))
          bft_found_empty="$(find "$bft_kind_root" -path "*-empty-*/$bft_test_label/$bft_test_file" -type f | wc -l | tr -d ' ')"
          bft_found_partial="$(find "$bft_kind_root" -path "*-partial-*/$bft_test_label/$bft_test_file" -type f | wc -l | tr -d ' ')"
          bft_actual=$((bft_actual + bft_found_empty + bft_found_partial))
        done <<< "$bft_test_files"
      done
      if [ "$bft_expected" -eq "$bft_actual" ] && [ "$bft_partial_before" = "$bft_partial_after" ]; then
        echo "PASS: testフェーズ後埋め（6種別12ユニット、宣言ファイル${bft_expected}件が実在し既存ファイルは保持）" >&2
        pass=$((pass + 1))
      else
        echo "FAIL: testフェーズ後埋め（期待=${bft_expected}, 実在=${bft_actual}, 既存保持=$([ "$bft_partial_before" = "$bft_partial_after" ] && echo yes || echo no)）" >&2
        fail=$((fail + 1))
      fi
    else
      echo "FAIL: --backfill-test の実行に失敗、またはfixture準備に失敗" >&2
      fail=$((fail + 1))
    fi

    if bash "$self_path" api basic "$tmp/docs_not_exist" selftest-missing >/dev/null 2>&1; then
      echo "FAIL: 存在しないoutput_dir指定時にexit1" >&2
      fail=$((fail + 1))
    else
      echo "PASS: 存在しないoutput_dir指定時にexit1" >&2
      pass=$((pass + 1))
    fi

    if bash "$self_path" nope basic "$tmp/docs_ok" selftest-unknown-kind >/dev/null 2>&1; then
      echo "FAIL: 未知のkind指定時にexit1" >&2
      fail=$((fail + 1))
    else
      echo "PASS: 未知のkind指定時にexit1" >&2
      pass=$((pass + 1))
    fi

    if bash "$self_path" api nope "$tmp/docs_ok" selftest-unknown-phase >/dev/null 2>&1; then
      echo "FAIL: 未知のphase指定時にexit1" >&2
      fail=$((fail + 1))
    else
      echo "PASS: 未知のphase指定時にexit1" >&2
      pass=$((pass + 1))
    fi

    # 実装契約-節の隣接（全種別の詳細設計が §実装契約→§関連資料 の隣接を持つか）
    impl_root="$script_dir/../../delivery-payload/templates/リバース検証"
    impl_ok=1
    impl_layout_json="$(design_unit_layout_load)" || impl_ok=0
    for kind in api table batch report external; do
      impl_label="$(design_unit_field "$impl_layout_json" "$kind" label)" || { impl_ok=0; continue; }
      impl_detail_file="$(design_unit_phase_files "$impl_layout_json" "$kind" detail | head -1)" || { impl_ok=0; continue; }
      if ! check_impl_contract_adjacency "$impl_root/$impl_label/$impl_detail_file" >/dev/null 2>&1; then
        echo "FAIL: 実装契約-節の隣接: $kind" >&2
        impl_ok=0
      fi
    done
    if ! check_impl_contract_adjacency "$impl_root/画面/詳細設計/画面詳細設計書.md" >/dev/null 2>&1; then
      echo "FAIL: 実装契約-節の隣接: screen" >&2
      impl_ok=0
    fi
    if [ "$impl_ok" -eq 1 ]; then
      echo "PASS: 実装契約-節の隣接（api/table/batch/report/external/画面の6種別）" >&2
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
    fi
    echo "INFO: 機能(feature)はdetailが空のため実装契約-節の隣接検査の対象外" >&2

    echo "self-test: ${pass} PASS, ${fail} FAIL" >&2
    [ "$fail" -eq 0 ]
  }
  if self_test; then exit 0; else exit 1; fi
fi

MODE=normal
case "${1:-}" in
  --verify)
    MODE=verify
    shift
    ;;
  --dry-run)
    MODE=dry-run
    shift
    ;;
  --overwrite)
    MODE=overwrite
    shift
    ;;
  --check-missing)
    MODE=check-missing
    shift
    ;;
  --backfill-basic)
    MODE=backfill-basic
    shift
    ;;
  --backfill-test)
    MODE=backfill-test
    shift
    ;;
esac

if [ "$MODE" = "backfill-basic" ]; then
  output_dir="${1:?引数1 output_dir が必要です}"
  template_root="${2:-$script_dir/../../delivery-payload/templates/リバース検証}"
  layout_json="$(design_unit_layout_load)" || exit 1
  source_phase="$(printf '%s' "$layout_json" | jq -r '.generationRules.basicFromExistingDetail.sourcePhase')"
  target_phase="$(printf '%s' "$layout_json" | jq -r '.generationRules.basicFromExistingDetail.targetPhase')"
  if [ -z "$source_phase" ] || [ "$source_phase" = "null" ] || [ -z "$target_phase" ] || [ "$target_phase" = "null" ]; then
    echo "エラー: basicFromExistingDetail の sourcePhase / targetPhase が未定義です" >&2
    exit 1
  fi
  if [ ! -d "$output_dir" ]; then
    echo "エラー: output_dir が存在しません（タイポ防止のため自動作成しません）: $output_dir" >&2
    exit 1
  fi
  assert_no_symlink_output_path "$output_dir" "$output_dir" || exit 1
  output_layout_json="$(resolve_output_layout "$output_dir")" || exit 1
  eligible_units=0
  completed_units=0
  while IFS= read -r backfill_kind; do
    [ -n "$backfill_kind" ] || continue
    backfill_root_key="$(unit_root_key_for_kind "$backfill_kind")" || exit 1
    backfill_root_rel="$(output_layout_get "$output_layout_json" "$backfill_root_key")" || exit 1
    backfill_root="$output_dir/$backfill_root_rel"
    [ -d "$backfill_root" ] || continue
    source_label="$(design_unit_phase_label "$source_phase")" || exit 1
    target_label="$(design_unit_phase_label "$target_phase")" || exit 1
    backfill_label="$(design_unit_field "$layout_json" "$backfill_kind" label)" || exit 1
    backfill_token="$(design_unit_field "$layout_json" "$backfill_kind" token)" || exit 1
    target_files="$(design_unit_phase_files "$layout_json" "$backfill_kind" "$target_phase")" || exit 1
    template_dir="$(cd "$template_root" && pwd)"
    while IFS= read -r candidate_dir; do
      [ -n "$candidate_dir" ] || continue
      source_complete=1
      while IFS= read -r source_file; do
        [ -n "$source_file" ] || continue
        if [ ! -f "$candidate_dir/$source_label/$source_file" ]; then
          source_complete=0
          break
        fi
      done < <(design_unit_phase_files "$layout_json" "$backfill_kind" "$source_phase")
      [ "$source_complete" -eq 1 ] || continue
      eligible_units=$((eligible_units + 1))
      candidate_name="$(basename "$candidate_dir")"
      candidate_id="${candidate_name#"${backfill_kind}-"}"
      target_dir="$candidate_dir/$target_label"
      if [ -L "$target_dir" ]; then
        echo "エラー: 補完先phaseディレクトリがシンボリックリンクです: $target_dir" >&2
        exit 1
      fi
      if scaffold_missing_phase_files "$target_dir" "$candidate_dir" "$target_phase" "$candidate_id" \
          "$template_dir" "$backfill_label" "$backfill_token" "$candidate_id" "$target_files" 0 >/dev/null; then
        completed_units=$((completed_units + 1))
      else
        echo "エラー: 基本設計の差分補完に失敗しました: $candidate_dir" >&2
        exit 1
      fi
    done < <(find "$backfill_root" -mindepth 1 -maxdepth 1 -type d -name "${backfill_kind}-*" | LC_ALL=C sort)
  done < <(printf '%s' "$layout_json" | jq -r --arg source "$source_phase" '
    .generationRules.basicFromExistingDetail.excludedKinds as $excluded
    | .kinds | to_entries[] | . as $entry
    | select((.value.phases[$source] // []) | length > 0)
    | select(($excluded | index($entry.key)) == null)
    | .key
  ')
  echo "基本設計の差分補完完了: 対象 ${eligible_units} ユニット、完了 ${completed_units} ユニット"
  exit 0
fi

# testフェーズの後埋め（--backfill-test）。--backfill-basicと同じ形の処理を、
# testFromExistingDetailの宣言に差し替えて行う。
# kindの絞り込みだけはbasicFromExistingDetail側と異なる。
# あちらはphases[source]（detail）の長さで対象kindを絞る。
# 機能（feature）はdetailを持たない（空配列）。
# 同じ絞り込みを使うと機能が常に除外される。
# 機能のtestフェーズ後埋めは1-72の再検証で要求される対象そのものである。
# このため絞り込みはexcludedKindsだけで行い、phases[source]の長さは見ない。
# sourcePhaseに宣言されたファイルが0件の種別がある。
# その種別は、ファイル群が「すべて実在する」を空虚な真として満たす。
# このため後埋めの対象に含まれる。
if [ "$MODE" = "backfill-test" ]; then
  output_dir="${1:?引数1 output_dir が必要です}"
  template_root="${2:-$script_dir/../../delivery-payload/templates/リバース検証}"
  layout_json="$(design_unit_layout_load)" || exit 1
  source_phase="$(printf '%s' "$layout_json" | jq -r '.generationRules.testFromExistingDetail.sourcePhase')"
  target_phase="$(printf '%s' "$layout_json" | jq -r '.generationRules.testFromExistingDetail.targetPhase')"
  if [ -z "$source_phase" ] || [ "$source_phase" = "null" ] || [ -z "$target_phase" ] || [ "$target_phase" = "null" ]; then
    echo "エラー: testFromExistingDetail の sourcePhase / targetPhase が未定義です" >&2
    exit 1
  fi
  if [ ! -d "$output_dir" ]; then
    echo "エラー: output_dir が存在しません（タイポ防止のため自動作成しません）: $output_dir" >&2
    exit 1
  fi
  assert_no_symlink_output_path "$output_dir" "$output_dir" || exit 1
  output_layout_json="$(resolve_output_layout "$output_dir")" || exit 1
  eligible_units=0
  completed_units=0
  while IFS= read -r backfill_kind; do
    [ -n "$backfill_kind" ] || continue
    backfill_root_key="$(unit_root_key_for_kind "$backfill_kind")" || exit 1
    backfill_root_rel="$(output_layout_get "$output_layout_json" "$backfill_root_key")" || exit 1
    backfill_root="$output_dir/$backfill_root_rel"
    [ -d "$backfill_root" ] || continue
    source_label="$(design_unit_phase_label "$source_phase")" || exit 1
    target_label="$(design_unit_phase_label "$target_phase" "$output_dir")" || exit 1
    backfill_label="$(design_unit_field "$layout_json" "$backfill_kind" label)" || exit 1
    backfill_token="$(design_unit_field "$layout_json" "$backfill_kind" token)" || exit 1
    target_files="$(design_unit_phase_files "$layout_json" "$backfill_kind" "$target_phase")" || exit 1
    template_dir="$(cd "$template_root" && pwd)"
    while IFS= read -r candidate_dir; do
      [ -n "$candidate_dir" ] || continue
      source_complete=1
      while IFS= read -r source_file; do
        [ -n "$source_file" ] || continue
        if [ ! -f "$candidate_dir/$source_label/$source_file" ]; then
          source_complete=0
          break
        fi
      done < <(design_unit_phase_files "$layout_json" "$backfill_kind" "$source_phase")
      [ "$source_complete" -eq 1 ] || continue
      eligible_units=$((eligible_units + 1))
      candidate_name="$(basename "$candidate_dir")"
      candidate_id="${candidate_name#"${backfill_kind}-"}"
      target_dir="$candidate_dir/$target_label"
      if [ -L "$target_dir" ]; then
        echo "エラー: 補完先phaseディレクトリがシンボリックリンクです: $target_dir" >&2
        exit 1
      fi
      if scaffold_missing_phase_files "$target_dir" "$candidate_dir" "$target_phase" "$candidate_id" \
          "$template_dir" "$backfill_label" "$backfill_token" "$candidate_id" "$target_files" 0 >/dev/null; then
        completed_units=$((completed_units + 1))
      else
        echo "エラー: 単体テスト設計の差分補完に失敗しました: $candidate_dir" >&2
        exit 1
      fi
    done < <(find "$backfill_root" -mindepth 1 -maxdepth 1 -type d -name "${backfill_kind}-*" | LC_ALL=C sort)
  done < <(printf '%s' "$layout_json" | jq -r '
    .generationRules.testFromExistingDetail.excludedKinds as $excluded
    | .kinds | to_entries[] | . as $entry
    | select(($excluded | index($entry.key)) == null)
    | .key
  ')
  echo "単体テスト設計の差分補完完了: 対象 ${eligible_units} ユニット、完了 ${completed_units} ユニット"
  exit 0
fi

kind="${1:?引数1 kind が必要です}"
phase="${2:?引数2 phase が必要です}"
output_dir="${3:?引数3 output_dir が必要です}"
unit_id="${4:?引数4 識別子 が必要です}"
display_name="${5:-$unit_id}"
template_root="${6:-$script_dir/../../delivery-payload/templates/リバース検証}"

layout_json="$(design_unit_layout_load)" || exit 1
label="$(design_unit_field "$layout_json" "$kind" label)" || exit 1
token="$(design_unit_field "$layout_json" "$kind" token)" || exit 1
phase_files="$(design_unit_phase_files "$layout_json" "$kind" "$phase")" || exit 1
phase_label="$(design_unit_phase_label "$phase" "$output_dir")" || exit 1

# 禁止文字バリデーション（sed 展開先の破壊・部分生成物の混入を防ぐ）
for _val in "$unit_id" "$display_name"; do
  case "$_val" in
    *"/"*|*"&"*|*"|"*)
      echo "エラー: 識別子・表示名に禁止文字（ / & |）を含められません: '$_val'" >&2
      exit 1 ;;
  esac
  case "$_val" in
    *$'\n'*)
      echo "エラー: 識別子・表示名に改行を含められません" >&2
      exit 1 ;;
  esac
done

if [ ! -d "$output_dir" ]; then
  echo "エラー: output_dir が存在しません（タイポ防止のため自動作成しません）: $output_dir" >&2
  exit 1
fi
assert_no_symlink_output_path "$output_dir" "$output_dir" || exit 1

if [ "$MODE" != "check-missing" ]; then
  if [ ! -d "$template_root" ]; then
    echo "エラー: テンプレートディレクトリが見つかりません: $template_root" >&2
    exit 1
  fi
  template_dir="$(cd "$template_root" && pwd)"
  if [ ! -d "$template_dir/$label" ]; then
    echo "エラー: 種別のテンプレートディレクトリが見つかりません: $template_dir/$label" >&2
    exit 1
  fi
fi

unit_root_key="$(unit_root_key_for_kind "$kind")" || exit 1
output_layout_json="$(resolve_output_layout "$output_dir")" || exit 1
unit_root_rel="$(output_layout_get "$output_layout_json" "$unit_root_key")" || exit 1
unit_dir="$output_dir/$unit_root_rel/${kind}-${unit_id}"
phase_dir="$unit_dir/$phase_label"
assert_no_symlink_output_path "$output_dir" "$unit_dir" || exit 1
assert_no_symlink_output_path "$output_dir" "$phase_dir" || exit 1
if [ -e "$phase_dir" ] && [ ! -d "$phase_dir" ]; then
  echo "エラー: phaseパスがディレクトリではありません: $phase_dir" >&2
  exit 1
fi

if [ "$MODE" = "verify" ]; then
  errors=0
  detail_frontmatter_document=""
  if [ "$phase" = "detail" ] && [ -n "$phase_files" ]; then
    if [ ! -f "$DETAIL_FRONTMATTER_KEYS_DEFAULT" ]; then
      echo "エラー: 詳細設計書frontmatter定義がありません: $DETAIL_FRONTMATTER_KEYS_DEFAULT" >&2
      exit 1
    fi
    if ! jq -e --arg kind "$kind" '
        .kinds[$kind].document | type == "string" and length > 0
      ' "$DETAIL_FRONTMATTER_KEYS_DEFAULT" >/dev/null 2>&1; then
      echo "エラー: 詳細設計書frontmatter定義に種別または文書名がありません: $kind" >&2
      exit 1
    fi
    detail_frontmatter_document="$(jq -r --arg kind "$kind" '.kinds[$kind].document' "$DETAIL_FRONTMATTER_KEYS_DEFAULT")"
    detail_frontmatter_expected_keys "$kind" >/dev/null || exit 1
  fi
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    if [ ! -f "$phase_dir/$file" ]; then
      echo "エラー: 必須ファイルがありません: $phase_dir/$file" >&2
      errors=$((errors + 1))
      continue
    fi
    if [ ! -f "$template_dir/$label/$file" ]; then
      echo "エラー: 比較元テンプレートがありません: $template_dir/$label/$file" >&2
      errors=$((errors + 1))
      continue
    fi
    if [ "$phase" = "detail" ] && [ -n "$detail_frontmatter_document" ]; then
      if [ "$file" != "$detail_frontmatter_document" ]; then
        echo "エラー: 詳細設計書frontmatter定義の文書名と配置宣言が一致しません: $kind ($file)" >&2
        errors=$((errors + 1))
        continue
      fi
      template_frontmatter_keys="$(detail_frontmatter_expected_keys "$kind")" || exit 1
    else
      template_frontmatter_keys="$(extract_frontmatter_top_level_keys "$template_dir/$label/$file")"
    fi
    target_frontmatter_keys="$(extract_frontmatter_top_level_keys "$phase_dir/$file")"
    missing_frontmatter_keys="$(comm -23 \
      <(printf '%s\n' "$template_frontmatter_keys" | sed '/^$/d') \
      <(printf '%s\n' "$target_frontmatter_keys" | sed '/^$/d'))"
    extra_frontmatter_keys="$(comm -13 \
      <(printf '%s\n' "$template_frontmatter_keys" | sed '/^$/d') \
      <(printf '%s\n' "$target_frontmatter_keys" | sed '/^$/d'))"
    if [ -n "$missing_frontmatter_keys" ]; then
      missing_frontmatter_keys_display="$(printf '%s\n' "$missing_frontmatter_keys" | paste -sd ',' -)"
      echo "エラー: frontmatter鍵が欠落しています（missing: ${missing_frontmatter_keys_display}）: $phase_dir/$file" >&2
      errors=$((errors + 1))
    fi
    if [ -n "$extra_frontmatter_keys" ]; then
      extra_frontmatter_keys_display="$(printf '%s\n' "$extra_frontmatter_keys" | paste -sd ',' -)"
      echo "エラー: frontmatter鍵が余剰です（extra: ${extra_frontmatter_keys_display}）: $phase_dir/$file" >&2
      errors=$((errors + 1))
    fi
    if grep -qF "$token" "$phase_dir/$file"; then
      echo "エラー: 未置換のプレースホルダが残っています（${token}）: $phase_dir/$file" >&2
      errors=$((errors + 1))
    fi
    # テンプレートの未置換の欄を検知できるようにする指示書: ${tokenは種別識別}子
    # 1件だけを見るため、判定材料の欄(table_subkind等)を含むそれ以外の全大文字
    # 欄が未記入のまま残っても検出できなかった。複製元テンプレートのfrontmatter
    # から全大文字トークンを実行時に走査し、frontmatter範囲内での残存を検査する
    # (本文は対象外)。
    template_tokens="$(extract_allcaps_tokens "$template_dir/$label/$file")"
    if [ -n "$template_tokens" ]; then
      target_frontmatter="$(extract_frontmatter_block "$phase_dir/$file")"
      while IFS= read -r tmpl_token; do
        [ -z "$tmpl_token" ] && continue
        if printf '%s' "$target_frontmatter" | grep -qF "$tmpl_token"; then
          echo "エラー: 未置換のプレースホルダが残っています（${tmpl_token}）: $phase_dir/$file" >&2
          errors=$((errors + 1))
        fi
      done <<< "$template_tokens"
    fi
    while IFS= read -r heading; do
      [ -z "$heading" ] && continue
      if ! grep -qF "$heading" "$phase_dir/$file"; then
        echo "エラー: 見出しが欠落しています（${heading}）: $phase_dir/$file" >&2
        errors=$((errors + 1))
      fi
    done < <(grep '^## ' "$template_dir/$label/$file")
  done <<< "$phase_files"
  if [ "$errors" -gt 0 ]; then
    echo "検証失敗: $errors 件" >&2
    exit 1
  fi
  echo "検証OK: $phase_dir の構造は健全です"
  exit 0
fi

if [ "$MODE" = "check-missing" ]; then
  missing=0
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    if [ -L "$phase_dir/$file" ] || [ ! -f "$phase_dir/$file" ]; then
      echo "不足: $phase_dir/$file"
      missing=1
    fi
  done <<< "$phase_files"
  exit "$missing"
fi

if [ "$MODE" = "dry-run" ]; then
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    dry_run_destination="$phase_dir/$file"
    if [ -L "$dry_run_destination" ]; then
      echo "エラー: 宣言ファイルがシンボリックリンクです: $dry_run_destination" >&2
      exit 1
    fi
    if [ -e "$dry_run_destination" ] && [ ! -f "$dry_run_destination" ]; then
      echo "エラー: 宣言ファイルの配置先が通常ファイルではありません: $dry_run_destination" >&2
      exit 1
    fi
  done <<< "$phase_files"
  echo "以下を展開予定です（--dry-run のため実際には書き込みません）"
  echo "  展開先: $phase_dir"
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    if [ ! -f "$phase_dir/$file" ]; then
      echo "  コピー元テンプレート: $template_dir/$label/$file"
    fi
  done <<< "$phase_files"
  echo "  置換予定のプレースホルダ: $token → $display_name"
  exit 0
fi

overwrite=0
if [ "$MODE" = "overwrite" ]; then
  overwrite=1
fi
scaffold_missing_phase_files "$phase_dir" "$unit_dir" "$phase" "$unit_id" \
  "$template_dir" "$label" "$token" "$display_name" "$phase_files" "$overwrite" || exit 1

echo ""
echo "=== 展開結果 ==="
if command -v tree >/dev/null 2>&1; then
  tree "$unit_dir"
else
  find "$unit_dir" -type f | sort
fi

echo ""
echo "スキャフォールディング完了: ${kind}-${unit_id} (${display_name}) / ${phase_label}"
