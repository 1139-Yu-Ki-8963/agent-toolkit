#!/usr/bin/env bash
# check-write-implicit-dir.sh — PreToolUse(Write|Edit)
# file_path のディレクトリ部分を検査し、存在しないルート直下ディレクトリへの
# 暗黙の作成を検出して advisory を注入する。
# 許可リスト解決順: ①project-context/rule.md の「## ルート直下許可ディレクトリ」節
#                   ②旧専用ファイル（新形式 always/placement/directory-structure/rule.md → 旧形式 directory-structure-rules/rule.md）
# exit 0（advisory）のみ。block しない。
set -euo pipefail

# 共通パースライブラリを読み込み
. "$(dirname "$0")/shared/parse-allowlist.sh"
. "$(dirname "$0")/shared/rule-resolver.sh"

input="$(cat)"
file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
[ -z "$file_path" ] && exit 0

# cwd 取得
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$cwd" ] && cwd="$PWD"

# 絶対パスに変換
if [[ "$file_path" != /* ]]; then
  file_path="${cwd}/${file_path}"
fi

# ファイルの親ディレクトリ
parent_dir="$(dirname "$file_path")"

# 親ディレクトリが既に存在する → 問題なし
[ -d "$parent_dir" ] && exit 0

# 存在しない親ディレクトリがある場合、ルートからの相対パスを算出
rel_parent="${parent_dir#"${cwd}"/}"
[[ "$rel_parent" = "$parent_dir" ]] && exit 0

# パス要素を分解
IFS='/' read -ra parts <<< "$rel_parent"
[ ${#parts[@]} -eq 0 ] && exit 0

# 許可リストファイル
# 正: project-context/rule.md の「## ルート直下許可ディレクトリ」節。フォールバック: 旧専用ファイル
pc_file="${cwd}/.claude/rules/always/project-context/rule.md"
if [ -f "$pc_file" ] && grep -q '^## ルート直下許可ディレクトリ' "$pc_file"; then
  allowlist_file="$pc_file"
else
  allowlist_file="$(resolve_rule_file "$cwd" "always/placement/directory-structure/rule.md" "directory-structure-rules/rule.md")"
fi

top_dir="${parts[0]}"

# ルート直下ディレクトリが存在しない場合
if [ ! -d "${cwd}/${top_dir}" ]; then
  if [ ! -f "$allowlist_file" ]; then
    ctx="[DIR-STRUCTURE-WRITE-GUARD] Write によりルート直下に新規ディレクトリ「${top_dir}」が暗黙的に作成されます。許可リスト（project-context/rule.md の「## ルート直下許可ディレクトリ」節、または旧専用ファイル）が存在しません: ${allowlist_file} ~/.claude/rules/always/placement/directory-structure/rule.md を参照。"
    jq -n --arg ctx "$ctx" \
      '{"systemMessage":"[フック発火] Write による暗黙ディレクトリ作成検出","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  else
    allowed="$(parse_root_allowlist "$allowlist_file" 2>/dev/null || echo "")"
    if ! echo "$allowed" | grep -qxF "$top_dir"; then
      ctx="[DIR-STRUCTURE-WRITE-GUARD] Write によりルート直下に新規ディレクトリ「${top_dir}」が暗黙的に作成されます。このディレクトリは許可リスト（${allowlist_file}）に存在しません。~/.claude/rules/always/placement/directory-structure/rule.md を参照。"
      jq -n --arg ctx "$ctx" \
        '{"systemMessage":"[フック発火] Write による暗黙ディレクトリ作成検出","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
    fi
  fi
fi

# 2 階層目のチェック（ルート直下は存在するが 2 階層目が存在しない場合）
if [ ${#parts[@]} -ge 2 ] && [ -d "${cwd}/${top_dir}" ] && [ ! -d "${cwd}/${top_dir}/${parts[1]}" ]; then
  sub_dir="${parts[1]}"
  if [ -f "$allowlist_file" ]; then
    sub_allowed="$(parse_sub_allowlist "$allowlist_file" "$top_dir" 2>/dev/null || echo "")"
    if [ -n "$sub_allowed" ] && ! echo "$sub_allowed" | grep -qxF "$sub_dir"; then
      ctx="[DIR-STRUCTURE-WRITE-GUARD] Write により「${top_dir}/」配下に新規ディレクトリ「${sub_dir}」が暗黙的に作成されます。このディレクトリはサブ許可リスト（${allowlist_file}）に存在しません。~/.claude/rules/always/placement/directory-structure/rule.md を参照。"
      jq -n --arg ctx "$ctx" \
        '{"systemMessage":"[フック発火] Write による暗黙ディレクトリ作成検出","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
    fi
  fi
fi

exit 0
