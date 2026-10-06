#!/usr/bin/env bash
#
# 用途:
#   PreToolUse(Bash) hook。`git commit` コマンド実行前に、docs 配下の
#   staged 追加行を textlint で検査し、指摘語があればコミットを block する。
#   外部ライブラリ（marker-path.sh 等）への依存を持たない自己完結スクリプト。
#
# settings.json への登録例:
#   {
#     "hooks": {
#       "PreToolUse": [
#         {
#           "matcher": "Bash",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "bash .claude/hooks/check-textlint-commit.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }
#
# 設定変数:
#   TEXTLINT_CONFIG - リポジトリルート相対または絶対パスの textlint 設定ファイルパス
#   DOCS_PATTERN    - 検査対象とする staged ファイルパスの正規表現（grep -E 形式）
#   TEXTLINT_BIN    - textlint 起動コマンド。tools/linter 配下に node_modules を
#                     配置する運用の場合は `npx --prefix tools/linter textlint` の
#                     ように --prefix を指定して起動してもよい
#
set -euo pipefail

TEXTLINT_CONFIG="tools/linter/.textlintrc.json"
DOCS_PATTERN='^docs/.*\.md$'
TEXTLINT_BIN="npx textlint"

# ── 依存コマンドが無い環境では検査せず fail-open する ──────────────
# 導入直後の環境差異（jq/git/textlint 未インストール等）でコミット不能に
# させないための設計判断。検査を厳格化したい場合は運用側で依存を揃える。
command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[ -z "$cmd" ] && exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -z "$cwd" ] && cwd="$PWD"

# git commit を含まないコマンドは対象外（改行区切りの複数コマンドにも対応）
cmd_flat=$(printf '%s' "$cmd" | tr '\n' ';')
case "$cmd_flat" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

git_in_ctx() { git -C "$cwd" "$@"; }

repo_root=$(git_in_ctx rev-parse --show-toplevel 2>/dev/null || true)
[ -z "$repo_root" ] && exit 0

case "$TEXTLINT_CONFIG" in
  /*) config_path="$TEXTLINT_CONFIG" ;;
  *)  config_path="$repo_root/$TEXTLINT_CONFIG" ;;
esac
if [ ! -f "$config_path" ]; then
  echo "[textlint-hook] 設定ファイルが見つからないため検査をスキップ: $config_path" >&2
  exit 0
fi

# docs 配下の staged ファイルを抽出
docs_files=$(
  git_in_ctx diff --cached --name-only --diff-filter=ACM 2>/dev/null \
    | grep -E "$DOCS_PATTERN" \
    || true
)
[ -z "$docs_files" ] && exit 0

# textlint 実行環境が無ければ検査せず fail-open
if ! command -v npx >/dev/null 2>&1; then
  exit 0
fi

violations_file=$(mktemp)
trap 'rm -f "$violations_file" "${staged_tmp:-}"' EXIT

while IFS= read -r f; do
  [ -z "$f" ] && continue

  # 追加行の行番号を収集（変更されていないファイル・削除のみの差分はスキップ）
  # 末尾の || true: pipefail 下で grep が無マッチ(exit 1)になった場合でも
  # コマンド置換全体の異常終了（set -e によるスクリプト中断）を防ぐ
  added_lines=$(
    git_in_ctx diff --cached -U0 -- "$f" 2>/dev/null \
      | grep -E '^@@ ' \
      | sed -E 's/^@@ .* \+([0-9]+)(,([0-9]+))? @@.*$/\1 \3/' \
      | while read -r start count; do
          count="${count:-1}"
          for ((i = 0; i < count; i++)); do
            echo $((start + i))
          done
        done \
      || true
  )
  [ -z "$added_lines" ] && continue

  # staged 版の内容を一時ファイルへ書き出して検査対象にする
  # BSD mktemp（macOS）は --suffix 非対応。フォールバックすると拡張子なしの
  # ファイルになり textlint が対応拡張子と認識できず黙って0件・exit 0 で
  # 通過してしまうため、拡張子なしで作成後に .md へ付け替える
  staged_tmp="$(mktemp "${TMPDIR:-/tmp}/textlint-hook.XXXXXX")"
  staged_tmp_md="${staged_tmp}.md"
  mv "$staged_tmp" "$staged_tmp_md"
  staged_tmp="$staged_tmp_md"
  git_in_ctx show ":$f" > "$staged_tmp" 2>/dev/null || continue

  # 末尾の || true: grep が無マッチ(exit 1)でもパイプライン全体の異常終了を防ぐ
  # --format compact の実出力は `path: line N, col N, Error - message` 形式。
  # 行番号が抽出できない場合は「新規行かどうか判定不能」であり、fail-open
  # (=握りつぶし)にせず違反として計上する（行番号なしのままメッセージを出力）。
  $TEXTLINT_BIN --config "$config_path" --format compact "$staged_tmp" 2>/dev/null \
    | grep "Error -" \
    | while IFS= read -r line; do
        line_no=$(printf '%s' "$line" | sed -nE 's/^[^:]*: line ([0-9]+),.*/\1/p')
        if [ -z "$line_no" ]; then
          printf '%s\n' "$line" | sed "s|$staged_tmp|$f|"
        elif printf '%s\n' "$added_lines" | grep -qx "$line_no"; then
          printf '%s\n' "$line" | sed "s|$staged_tmp|$f|"
        fi
      done >> "$violations_file" \
      || true

  rm -f "$staged_tmp"
done <<< "$docs_files"

if [ -s "$violations_file" ]; then
  result=$(cat "$violations_file")
  printf '[TEXTLINT-BLOCK]\n%s\n\ndocs の追加・変更行に文章品質ルール違反があります（既存行は対象外・新規行のみ）。%s 準拠で指摘語を修正し、git add で再ステージしてから再度 commit してください。\n' \
    "$result" "$TEXTLINT_CONFIG" >&2
  exit 2
fi

exit 0
