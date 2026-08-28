#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=output-layout.sh
source "$script_dir/output-layout.sh"

# scaffold-screen.sh — リバース検証テンプレートを対象プロジェクトへ展開する
#
# 使い方:
#   scaffold-screen.sh <output_dir> <画面ID> [<画面名>] [<template_root>]
#   scaffold-screen.sh --verify <output_dir> <画面ID>
#   scaffold-screen.sh --dry-run <output_dir> <画面ID> [<画面名>] [<template_root>]
#
# 引数:
#   output_dir     設計書展開先ルート（呼び出し元スキルが起動引数として渡す）
#   画面ID        画面識別子（例: monthly-report）
#   画面名        日本語の画面名（省略時は画面IDをそのまま使う）
#   template_root テンプレート原本ルート（省略時はスクリプト位置基準の既定値
#                 `<スクリプトのあるディレクトリ>/../../delivery-payload/templates/リバース検証` を使う）
#
# 処理:
#   1. template_root（引数指定 or 既定値）からテンプレートを特定
#   2. <output_dir>/<screenUnitRoot>/screen-<画面ID>/ へ画面単位テンプレートをコピー
#   3. output-layout.json の commonRoot が指す場所（既定は docs/design/common）が未存在なら初回コピー
#   4. 全 .md の <画面ID> <画面名> プレースホルダを sed 置換
#   5. 展開結果を tree で表示

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

if [ "${1:-}" = "--self-test" ]; then
  self_test() {
    local self_path pass=0 fail=0
    self_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/scaffold-screen-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
      echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
      exit 2
    fi
    tmp="$(cd "$tmp" && pwd -P)"
    trap 'rm -rf "$tmp"' EXIT

    # 正常系: 実テンプレートで新規展開した後、--verify が健全性をexit0で確認する
    mkdir -p "$tmp/docs_ok"
    if bash "$self_path" "$tmp/docs_ok" selftest-screen "セルフテスト画面" >/dev/null 2>&1 \
       && bash "$self_path" --verify "$tmp/docs_ok" selftest-screen >/dev/null 2>&1; then
      echo "PASS: 実テンプレート展開後にverifyがexit0" >&2
      pass=$((pass + 1))
    else
      echo "FAIL: 実テンプレート展開後にverifyがexit0" >&2
      fail=$((fail + 1))
    fi

    # 異常系: 存在しないoutput_dirを指定するとexit1
    if bash "$self_path" "$tmp/docs_not_exist" selftest-screen2 >/dev/null 2>&1; then
      echo "FAIL: 存在しないoutput_dir指定時にexit1" >&2
      fail=$((fail + 1))
    else
      echo "PASS: 存在しないoutput_dir指定時にexit1" >&2
      pass=$((pass + 1))
    fi

    # 異常系: 未展開ディレクトリへの--verifyはexit1
    mkdir -p "$tmp/docs_empty/画面/screen-empty-screen"
    if bash "$self_path" --verify "$tmp/docs_empty" empty-screen >/dev/null 2>&1; then
      echo "FAIL: 未展開ディレクトリへのverifyでexit1" >&2
      fail=$((fail + 1))
    else
      echo "PASS: 未展開ディレクトリへのverifyでexit1" >&2
      pass=$((pass + 1))
    fi

    # output-layout上書き: 表示ラベルではなくscreenUnitRootへ展開し、verifyも同じ配置を読む
    mkdir -p "$tmp/docs_override/画面/screen-decoy"
    cat > "$tmp/docs_override/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "screenUnitRoot": "スクリーン" } }
JSON
    if bash "$self_path" "$tmp/docs_override" custom-root "配置上書き画面" >/dev/null 2>&1 \
       && bash "$self_path" --verify "$tmp/docs_override" custom-root >/dev/null 2>&1 \
       && [ -d "$tmp/docs_override/スクリーン/screen-custom-root" ] \
       && [ ! -d "$tmp/docs_override/画面/screen-custom-root" ]; then
      echo "PASS: screenUnitRoot上書きへ展開しverifyも同じ配置を検証" >&2
      pass=$((pass + 1))
    else
      echo "FAIL: screenUnitRoot上書きの展開・verify" >&2
      fail=$((fail + 1))
    fi

    # 異常系: output_dir自身またはscreenUnitRoot祖先がsymlinkなら外部treeへ書かない
    mkdir -p "$tmp/symlink-external-root" "$tmp/symlink-parent-docs" "$tmp/symlink-external-screen-root" \
      "$tmp/symlink-external-parent/docs" "$tmp/lexical-base" "$tmp/lexical-external/child" \
      "$tmp/lexical-external/docs"
    ln -s "$tmp/symlink-external-root" "$tmp/docs-root-link"
    cat > "$tmp/symlink-parent-docs/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "screenUnitRoot": "スクリーン" } }
JSON
    ln -s "$tmp/symlink-external-screen-root" "$tmp/symlink-parent-docs/スクリーン"
    ln -s "$tmp/symlink-external-parent" "$tmp/link-parent"
    ln -s "$tmp/lexical-external/child" "$tmp/lexical-base/link"
    if bash "$self_path" "$tmp/docs-root-link" root-link "root symlink" >/dev/null 2>&1 \
       || [ -e "$tmp/symlink-external-root/画面/screen-root-link" ] \
       || [ -e "$tmp/symlink-external-root/スクリーン/screen-root-link" ]; then
      echo "FAIL: symlinkのoutput_dirを拒否して外部treeを不変に保つ" >&2
      fail=$((fail + 1))
    else
      echo "PASS: symlinkのoutput_dirを拒否して外部treeを不変に保つ" >&2
      pass=$((pass + 1))
    fi
    if bash "$self_path" "$tmp/symlink-parent-docs" ancestor-link "ancestor symlink" >/dev/null 2>&1 \
       || [ -e "$tmp/symlink-external-screen-root/screen-ancestor-link" ]; then
      echo "FAIL: screenUnitRootのsymlink祖先を拒否して外部treeを不変に保つ" >&2
      fail=$((fail + 1))
    else
      echo "PASS: screenUnitRootのsymlink祖先を拒否して外部treeを不変に保つ" >&2
      pass=$((pass + 1))
    fi
    if bash "$self_path" "$tmp/link-parent/docs" parent-component "parent component symlink" >/dev/null 2>&1 \
       || [ -e "$tmp/symlink-external-parent/docs/画面/screen-parent-component" ]; then
      echo "FAIL: output_dirへ至る親component symlinkを拒否して外部treeを不変に保つ" >&2
      fail=$((fail + 1))
    else
      echo "PASS: output_dirへ至る親component symlinkを拒否して外部treeを不変に保つ" >&2
      pass=$((pass + 1))
    fi
    if bash "$self_path" "$tmp/lexical-base/link/../docs" lexical-collapse "lexical symlink" >/dev/null 2>&1 \
       || [ -e "$tmp/lexical-external/docs/画面/screen-lexical-collapse" ]; then
      echo "FAIL: collapse前の字句component symlinkを拒否して外部treeを不変に保つ" >&2
      fail=$((fail + 1))
    else
      echo "PASS: collapse前の字句component symlinkを拒否して外部treeを不変に保つ" >&2
      pass=$((pass + 1))
    fi

    # 異常系: screenUnitRootがcommonRootと衝突する宣言は共通文書を変更せず拒否する
    mkdir -p "$tmp/collision-docs"
    collision_base_layout="$(resolve_output_layout "$tmp/collision-docs")" || true
    collision_root="$(output_layout_get "$collision_base_layout" commonRoot 2>/dev/null)" || true
    mkdir -p "$tmp/collision-docs/$collision_root"
    printf '%s\n' 'preserve-common-docs' > "$tmp/collision-docs/$collision_root/marker.txt"
    jq -n --arg value "$collision_root" \
      '{specVersion: 1, layout: {screenUnitRoot: $value}}' > "$tmp/collision-docs/output-layout.json"
    if bash "$self_path" "$tmp/collision-docs" collision "root collision" >/dev/null 2>&1 \
       || [ "$(cat "$tmp/collision-docs/$collision_root/marker.txt")" != "preserve-common-docs" ] \
       || [ -e "$tmp/collision-docs/$collision_root/screen-collision" ]; then
      echo "FAIL: screenUnitRootとcommonRootの衝突を拒否して共通文書を保全" >&2
      fail=$((fail + 1))
    else
      echo "PASS: screenUnitRootとcommonRootの衝突を拒否して共通文書を保全" >&2
      pass=$((pass + 1))
    fi

    echo "self-test: ${pass} PASS, ${fail} FAIL" >&2
    [ "$fail" -eq 0 ]
  }
  if self_test; then exit 0; else exit 1; fi
fi

if [ "${1:-}" = "--verify" ]; then
  shift
  output_dir="${1:?引数 output_dir が必要です}"
  screen_id="${2:?引数 画面ID が必要です}"
  assert_no_symlink_output_path "$output_dir" "$output_dir" || exit 1
  LAYOUT_JSON="$(resolve_output_layout "$output_dir")" || exit 1
  LAYOUT_SCREEN_UNIT_ROOT="$(output_layout_get "$LAYOUT_JSON" screenUnitRoot)" || exit 1
  screen_dir="$output_dir/$LAYOUT_SCREEN_UNIT_ROOT/screen-${screen_id}"
  assert_no_symlink_output_path "$output_dir" "$screen_dir" || exit 1
  errors=0
  for req in 詳細設計/画面詳細設計書.md 詳細設計/DESIGN.md \
             テスト設計/画面結合テスト設計書.md テスト設計/画面単体テスト設計書.md \
             テスト設計/操作シナリオ仕様書.md 基本設計/画面基本設計書.md; do
    if [ ! -f "$screen_dir/$req" ]; then
      echo "エラー: 必須ファイルがありません: $screen_dir/$req" >&2
      errors=$((errors + 1))
    fi
  done
  if [ -d "$screen_dir/検証記録/<timestamp>" ]; then
    echo "エラー: 未展開の <timestamp> ディレクトリが残っています: $screen_dir/検証記録" >&2
    errors=$((errors + 1))
  fi
  if find "$screen_dir" -name '*.md' -exec grep -lE '<画面ID>|<画面名>|<YYYY-MM-DD>' {} \; 2>/dev/null | grep -q .; then
    echo "エラー: 未置換のプレースホルダが残っています（<画面ID>/<画面名>/<YYYY-MM-DD>）" >&2
    errors=$((errors + 1))
  fi
  if [ "$errors" -gt 0 ]; then
    echo "検証失敗: $errors 件" >&2
    exit 1
  fi
  echo "検証OK: $screen_dir の構造は健全です"
  exit 0
fi

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=1
  shift
fi

output_dir="${1:?引数1 output_dir が必要です}"
screen_id="${2:?引数2 画面ID が必要です}"
screen_name="${3:-$screen_id}"
template_root="${4:-$script_dir/../../delivery-payload/templates/リバース検証}"
today="$(date +%Y-%m-%d)"

# 禁止文字バリデーション（sed 展開先の破壊・部分生成物の混入を防ぐ）
for _val in "$screen_id" "$screen_name"; do
  case "$_val" in
    *"/"*|*"&"*|*"|"*)
      echo "エラー: 画面ID・画面名に禁止文字（ / & |）を含められません: '$_val'" >&2
      exit 1 ;;
  esac
  case "$_val" in
    *$'\n'*)
      echo "エラー: 画面ID・画面名に改行を含められません" >&2
      exit 1 ;;
  esac
done

# output_dir は既存必須（タイポによる意図しない新規作成を防ぐ）
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

LAYOUT_JSON="$(resolve_output_layout "$output_dir")" || exit 1
LAYOUT_COMMON_ROOT="$(output_layout_get "$LAYOUT_JSON" commonRoot)" || exit 1
LAYOUT_SCREEN_UNIT_ROOT="$(output_layout_get "$LAYOUT_JSON" screenUnitRoot)" || exit 1

screen_dir="$output_dir/$LAYOUT_SCREEN_UNIT_ROOT/screen-${screen_id}"
common_dir="$output_dir/$LAYOUT_COMMON_ROOT"
assert_no_symlink_output_path "$output_dir" "$screen_dir" || exit 1
assert_no_symlink_output_path "$output_dir" "$common_dir" || exit 1

if [ -d "$screen_dir" ]; then
  echo "エラー: 画面ディレクトリが既に存在します: $screen_dir" >&2
  exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "以下を展開予定です（--dry-run のため実際には書き込みません）"
  echo "  展開先: $screen_dir"
  echo "  コピー元テンプレート: $template_dir/画面/詳細設計, $template_dir/画面/テスト設計, $template_dir/画面/基本設計"
  if [ -d "$common_dir" ]; then
    echo "  プロジェクト共通: 既に存在するためスキップ ($common_dir)"
  else
    echo "  コピー元テンプレート: $template_dir/プロジェクト共通 → $common_dir"
  fi
  echo "  置換予定のプレースホルダ: <画面ID> → $screen_id, <画面名> → $screen_name, <YYYY-MM-DD> → $today"
  exit 0
fi

# 画面単位テンプレートのコピー（一時ディレクトリへ展開し、全処理成功時のみ最終位置へ mv する）
echo "画面テンプレートを展開: $screen_dir"
staging="$(dirname "$screen_dir")/.staging-screen-${screen_id}.$$"
rm -rf "$staging"
mkdir -p "$staging"
cp -r "$template_dir/画面/詳細設計" "$staging/"
cp -r "$template_dir/画面/テスト設計" "$staging/"
cp -r "$template_dir/画面/基本設計" "$staging/"

# プロジェクト共通テンプレートのコピー（初回のみ。output_dir 直下の共通領域なので画面ディレクトリとは別扱い）
if [ -d "$common_dir" ]; then
  echo "プロジェクト共通/ は既に存在するためスキップ: $common_dir"
else
  echo "プロジェクト共通テンプレートを展開: $common_dir"
  # commonRoot が複数階層になった場合でも cp -r が親を自動作成しない（BSD cp は
  # 欠落中間ディレクトリを複数階層まとめて作れない）ため、先に親を作る。
  mkdir -p "$(dirname "$common_dir")"
  cp -r "$template_dir/プロジェクト共通" "$common_dir"
  # プロジェクト共通は画面非依存のため <画面ID>/<画面名> は置換しない
  # （メッセージ定義書.md の記入例行にある <画面名> を誤って書き換えないため）。
  while IFS= read -r file; do
    ok=1
    sed -i.bak "s/<YYYY-MM-DD>/${today}/g" "$file" || ok=0
    rm -f "${file}.bak"
    if [ "$ok" -eq 0 ]; then
      rm -rf "$staging" "$common_dir"
      echo "エラー: プレースホルダ置換に失敗しました: $file" >&2
      exit 1
    fi
  done < <(find "$common_dir" -name '*.md' -type f)
  node "$script_dir/materialize-introduction-guidance.mjs" "$common_dir" || exit 1
fi

# プレースホルダ置換（GNU/BSD sed 両対応: -i.bak + rm を使用）+ 相対パス補正を1回のfindループで行う。
# 相対パス補正: テンプレートは 画面/詳細設計/ を想定した ../../プロジェクト共通/... だが、
# 展開先は <screenUnitRoot>/screen-<画面ID>/詳細設計/ で1階層深い。../../../プロジェクト共通/... に補正する。
echo "プレースホルダを置換: <画面ID> → $screen_id, <画面名> → $screen_name"
while IFS= read -r file; do
  ok=1
  sed -i.bak "s/<画面ID>/${screen_id}/g" "$file" || ok=0
  sed -i.bak "s/<画面名>/${screen_name}/g" "$file" || ok=0
  sed -i.bak "s/<YYYY-MM-DD>/${today}/g" "$file" || ok=0
  sed -i.bak "s#\\.\\./\\.\\./プロジェクト共通#../../../プロジェクト共通#g" "$file" || ok=0
  rm -f "${file}.bak"
  if [ "$ok" -eq 0 ]; then
    rm -rf "$staging"
    echo "エラー: プレースホルダ置換・相対パス補正に失敗しました: $file" >&2
    exit 1
  fi
done < <(find "$staging" -name '*.md' -type f)
node "$script_dir/materialize-introduction-guidance.mjs" "$staging" || {
  rm -rf "$staging"
  exit 1
}

# 全処理成功。ここで初めて最終位置へ移動する。
mv "$staging" "$screen_dir"

# 展開結果の表示
echo ""
echo "=== 展開結果 ==="
if command -v tree >/dev/null 2>&1; then
  tree "$output_dir"
else
  find "$output_dir" -type f | sort
fi

echo ""
echo "スキャフォールディング完了: screen-${screen_id} (${screen_name})"
