#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
fixture="$repo_root/generation-engine/scripts/glossary/fixtures/valid-glossary.yaml"
registry="$repo_root/generation-engine/scripts/glossary/fixtures/canonical-registry"
projector="$script_dir/project-semantic-glossary.py"
portal_root="${1:-$repo_root/generation-engine/samples}"
portal_dir="$portal_root/project-portal"
output_dir="$portal_root/project-portal/lists/semantic-glossary"
if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/semantic-glossary-sample.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
  echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
  exit 2
fi
trap 'rm -rf "$tmp"' EXIT
if [ "$#" -eq 0 ]; then
  page_data="$repo_root/generation-engine/scripts/detail-pages/fixtures/semantic-glossary-sample-page-data.json"
else
  page_data="$tmp/semantic-glossary-sample-page-data.json"
fi

python3 "$projector" \
  --input "$fixture" \
  --registry "$registry" \
  --output "$page_data"

if ! sample_page_data="$(mktemp "$tmp/semantic-glossary-page-data.XXXXXX" 2>/dev/null)" || [ -z "$sample_page_data" ]; then
  echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
  exit 2
fi
jq '.title = "用語辞書" | .description = "承認済みの業務概念とコード上の名称を対応付けます。"' "$page_data" > "$sample_page_data"
mv "$sample_page_data" "$page_data"

bash "$script_dir/build-detail-page.sh" "$page_data" "$output_dir" --page glossary --portal-dir "$portal_dir"

printf 'generated: %s/用語辞書.html\n' "$output_dir"
