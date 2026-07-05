#!/usr/bin/env bash
set -euo pipefail

# scaffold-screen.sh — リバース検証テンプレートを対象プロジェクトへ展開する
#
# 使い方:
#   scaffold-screen.sh <docs_root> <画面ID> [<画面名>]
#
# 引数:
#   docs_root  設計書展開先ルート（syncing-reverse-env/config.yml の docs_root）
#   画面ID     画面識別子（例: monthly-report）
#   画面名     日本語の画面名（省略時は画面IDをそのまま使う）
#
# 処理:
#   1. テンプレート（rebuilding-code-from-docs/assets/リバース検証/）を特定
#   2. <docs_root>/画面/screen-<画面ID>/ へ画面単位テンプレートをコピー
#   3. <docs_root>/プロジェクト共通/ が未存在なら初回コピー
#   4. 全 .md の <画面ID> <画面名> プレースホルダを sed 置換
#   5. 展開結果を tree で表示

docs_root="${1:?引数1 docs_root が必要です}"
screen_id="${2:?引数2 画面ID が必要です}"
screen_name="${3:-$screen_id}"

script_dir="$(cd "$(dirname "$0")" && pwd)"
template_dir="$(cd "$script_dir/../../rebuilding-code-from-docs/assets/リバース検証" && pwd)"

if [ ! -d "$template_dir" ]; then
  echo "エラー: テンプレートディレクトリが見つかりません: $template_dir" >&2
  exit 1
fi

screen_dir="$docs_root/画面/screen-${screen_id}"

if [ -d "$screen_dir" ]; then
  echo "エラー: 画面ディレクトリが既に存在します: $screen_dir" >&2
  exit 1
fi

# 画面単位テンプレートのコピー
echo "画面テンプレートを展開: $screen_dir"
mkdir -p "$screen_dir"
cp -r "$template_dir/画面/詳細設計" "$screen_dir/"
cp -r "$template_dir/画面/テスト項目書" "$screen_dir/"
mkdir -p "$screen_dir/検証記録"
if [ -d "$template_dir/画面/検証記録" ]; then
  cp -r "$template_dir/画面/検証記録/"* "$screen_dir/検証記録/" 2>/dev/null || true
fi

# プロジェクト共通テンプレートのコピー（初回のみ）
common_dir="$docs_root/プロジェクト共通"
if [ -d "$common_dir" ]; then
  echo "プロジェクト共通/ は既に存在するためスキップ: $common_dir"
else
  echo "プロジェクト共通テンプレートを展開: $common_dir"
  cp -r "$template_dir/プロジェクト共通" "$common_dir"
fi

# プレースホルダ置換（GNU/BSD sed 両対応: -i.bak + rm を使用）
echo "プレースホルダを置換: <画面ID> → $screen_id, <画面名> → $screen_name"
find "$screen_dir" -name '*.md' -type f | while IFS= read -r file; do
  sed -i.bak "s/<画面ID>/${screen_id}/g" "$file" && rm -f "${file}.bak"
  sed -i.bak "s/<画面名>/${screen_name}/g" "$file" && rm -f "${file}.bak"
done

# 相対パス補正: テンプレートは 画面/詳細設計/ を想定した ../../プロジェクト共通/... だが、
# 展開先は 画面/screen-<画面ID>/詳細設計/ で1階層深い。../../../プロジェクト共通/... に補正する。
find "$screen_dir" -name '*.md' -type f | while IFS= read -r file; do
  sed -i.bak "s#\\.\\./\\.\\./プロジェクト共通#../../../プロジェクト共通#g" "$file" && rm -f "${file}.bak"
done

# 展開結果の表示
echo ""
echo "=== 展開結果 ==="
if command -v tree >/dev/null 2>&1; then
  tree "$docs_root"
else
  find "$docs_root" -type f | sort
fi

echo ""
echo "スキャフォールディング完了: screen-${screen_id} (${screen_name})"
