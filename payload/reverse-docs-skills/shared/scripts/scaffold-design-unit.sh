#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESIGN_UNIT_LAYOUT_DEFAULT="$script_dir/../references/design-unit-layout.json"

# scaffold-design-unit.sh — 非画面種別（API・テーブル・バッチ・帳票・外部連携）の
# リバース検証テンプレートを対象プロジェクトへ展開する
#
# 使い方:
#   scaffold-design-unit.sh <kind> <phase> <output_dir> <識別子> [表示名] [template_root]
#   scaffold-design-unit.sh --verify <kind> <phase> <output_dir> <識別子> [表示名] [template_root]
#   scaffold-design-unit.sh --dry-run <kind> <phase> <output_dir> <識別子> [表示名] [template_root]
#
# 引数:
#   kind          api / table / batch / report / external のいずれか
#   phase         basic / detail のいずれか
#   output_dir    設計書展開先ルート（呼び出し元スキルが起動引数として渡す）
#   識別子        単位識別子（例: get-users）
#   表示名        日本語の表示名（省略時は識別子をそのまま使う）
#   template_root テンプレート原本ルート（省略時はスクリプト位置基準の既定値
#                 `<スクリプトのあるディレクトリ>/../templates/リバース検証` を使う）
#
# ファイル束の宣言は shared/references/design-unit-layout.json を参照する。

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
      if (fs.lstatSync(current).isSymbolicLink()) {
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
  if (stat.isSymbolicLink()) {
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

# phase キー（basic / detail）を和名フォルダ名へ変換する。
design_unit_phase_label() {
  case "$1" in
    basic) echo "基本設計" ;;
    detail) echo "詳細設計" ;;
    *)
      echo "エラー: 未知の phase です: $1" >&2
      return 1
      ;;
  esac
}

if [ "${1:-}" = "--self-test" ]; then
  self_test() {
    local self_path pass=0 fail=0
    self_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/design-unit-scaffold-selftest.XXXXXX")"
    tmp="$(cd "$tmp" && pwd -P)"
    trap 'rm -rf "$tmp"' EXIT

    mkdir -p "$tmp/docs_ok"
    ok_all=1
    for kind in api table batch report external; do
      for phase in basic detail; do
        if ! bash "$self_path" "$kind" "$phase" "$tmp/docs_ok" "selftest-${kind}" "セルフテスト${kind}" >/dev/null 2>&1; then
          echo "FAIL: 展開に失敗しました: $kind $phase" >&2
          ok_all=0
        fi
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
esac

kind="${1:?引数1 kind が必要です}"
phase="${2:?引数2 phase が必要です}"
output_dir="${3:?引数3 output_dir が必要です}"
unit_id="${4:?引数4 識別子 が必要です}"
display_name="${5:-$unit_id}"
template_root="${6:-$script_dir/../templates/リバース検証}"

layout_json="$(design_unit_layout_load)" || exit 1
label="$(design_unit_field "$layout_json" "$kind" label)" || exit 1
token="$(design_unit_field "$layout_json" "$kind" token)" || exit 1
phase_files="$(design_unit_phase_files "$layout_json" "$kind" "$phase")" || exit 1
phase_label="$(design_unit_phase_label "$phase")" || exit 1

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

if [ ! -d "$template_root" ]; then
  echo "エラー: テンプレートディレクトリが見つかりません: $template_root" >&2
  exit 1
fi
template_dir="$(cd "$template_root" && pwd)"
if [ ! -d "$template_dir/$label" ]; then
  echo "エラー: 種別のテンプレートディレクトリが見つかりません: $template_dir/$label" >&2
  exit 1
fi

unit_dir="$output_dir/$label/${kind}-${unit_id}"
phase_dir="$unit_dir/$phase_label"
assert_no_symlink_output_path "$output_dir" "$unit_dir" || exit 1
assert_no_symlink_output_path "$output_dir" "$phase_dir" || exit 1

if [ "$MODE" = "verify" ]; then
  errors=0
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    if [ ! -f "$phase_dir/$file" ]; then
      echo "エラー: 必須ファイルがありません: $phase_dir/$file" >&2
      errors=$((errors + 1))
      continue
    fi
    if grep -qF "$token" "$phase_dir/$file"; then
      echo "エラー: 未置換のプレースホルダが残っています（$token）: $phase_dir/$file" >&2
      errors=$((errors + 1))
    fi
    if [ -f "$template_dir/$label/$file" ]; then
      while IFS= read -r heading; do
        [ -z "$heading" ] && continue
        if ! grep -qF "$heading" "$phase_dir/$file"; then
          echo "エラー: 見出しが欠落しています（$heading）: $phase_dir/$file" >&2
          errors=$((errors + 1))
        fi
      done < <(grep '^## ' "$template_dir/$label/$file")
    fi
  done <<< "$phase_files"
  if [ "$errors" -gt 0 ]; then
    echo "検証失敗: $errors 件" >&2
    exit 1
  fi
  echo "検証OK: $phase_dir の構造は健全です"
  exit 0
fi

if [ "$MODE" = "dry-run" ]; then
  echo "以下を展開予定です（--dry-run のため実際には書き込みません）"
  echo "  展開先: $phase_dir"
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    echo "  コピー元テンプレート: $template_dir/$label/$file"
  done <<< "$phase_files"
  echo "  置換予定のプレースホルダ: $token → $display_name"
  exit 0
fi

if [ -d "$phase_dir" ]; then
  echo "エラー: phase ディレクトリが既に存在します: $phase_dir" >&2
  exit 1
fi

echo "設計単位テンプレートを展開: $phase_dir"
staging="$unit_dir/.staging-${phase}-${unit_id}.$$"
rm -rf "$staging"
mkdir -p "$staging"
while IFS= read -r file; do
  [ -z "$file" ] && continue
  if [ ! -f "$template_dir/$label/$file" ]; then
    rm -rf "$staging"
    echo "エラー: テンプレートファイルが見つかりません: $template_dir/$label/$file" >&2
    exit 1
  fi
  cp "$template_dir/$label/$file" "$staging/$file"
done <<< "$phase_files"

# プレースホルダ置換（GNU/BSD sed 両対応: -i.bak + rm を使用）
echo "プレースホルダを置換: $token → $display_name"
while IFS= read -r file; do
  ok=1
  sed -i.bak "s/${token}/${display_name}/g" "$file" || ok=0
  rm -f "${file}.bak"
  if [ "$ok" -eq 0 ]; then
    rm -rf "$staging"
    echo "エラー: プレースホルダ置換に失敗しました: $file" >&2
    exit 1
  fi
done < <(find "$staging" -name '*.md' -type f)

# 全処理成功。ここで初めて最終位置へ移動する。
mv "$staging" "$phase_dir"

echo ""
echo "=== 展開結果 ==="
if command -v tree >/dev/null 2>&1; then
  tree "$unit_dir"
else
  find "$unit_dir" -type f | sort
fi

echo ""
echo "スキャフォールディング完了: ${kind}-${unit_id} (${display_name}) / ${phase_label}"
