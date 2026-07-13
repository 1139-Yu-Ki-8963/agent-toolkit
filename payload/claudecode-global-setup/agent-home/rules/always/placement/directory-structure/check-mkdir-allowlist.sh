#!/usr/bin/env bash
# check-mkdir-allowlist.sh — PreToolUse(Bash)
# mkdir コマンドを検出し、リポジトリの許可リストと照合する。
# ルート直下 + サブディレクトリ許可リストの 2 階層を検査する。
# 許可リスト解決順: ①project-context/rule.md の「## ルート直下許可ディレクトリ」節
#                   ②旧専用ファイル（新形式 always/placement/directory-structure/rule.md → 旧形式 directory-structure-rules/rule.md）
# exit 0（advisory）のみ。block しない。
set -euo pipefail

# 共通パースライブラリを読み込み
. "$(dirname "$0")/shared/parse-allowlist.sh"
. "$(dirname "$0")/shared/rule-resolver.sh"

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0

# mkdir 以外は即通過
[[ "$cmd" =~ ^mkdir[[:space:]] ]] || exit 0

# cwd 取得
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$cwd" ] && cwd="$PWD"

# mkdir の対象ディレクトリを抽出（オプション引数を除外）
dirs=()
while IFS= read -r d; do
  [[ "$d" =~ ^- ]] && continue
  dirs+=("$d")
done <<< "$(echo "$cmd" | grep -oE '[^ ]+' | tail -n +2)"

# mkdir -p 対応: 中間ディレクトリを展開
if [[ "$cmd" =~ -p ]]; then
  expanded=()
  for d in "${dirs[@]}"; do
    expanded+=("$d")
    if [[ "$d" == */* ]]; then
      IFS='/' read -ra path_parts <<< "$d"
      accumulated=""
      for ((i=0; i<${#path_parts[@]}-1; i++)); do
        if [ -z "$accumulated" ]; then
          accumulated="${path_parts[i]}"
        else
          accumulated="${accumulated}/${path_parts[i]}"
        fi
        # 重複チェック
        dup=0
        for existing in "${expanded[@]}"; do
          [ "$existing" = "$accumulated" ] && dup=1 && break
        done
        [ "$dup" -eq 0 ] && expanded+=("$accumulated")
      done
    fi
  done
  dirs=("${expanded[@]}")
fi

[ ${#dirs[@]} -eq 0 ] && exit 0

# 許可リストファイルのパス
# 正: project-context/rule.md の「## ルート直下許可ディレクトリ」節。フォールバック: 旧専用ファイル
pc_file="${cwd}/.claude/rules/always/project-context/rule.md"
if [ -f "$pc_file" ] && grep -q '^## ルート直下許可ディレクトリ' "$pc_file"; then
  allowlist_file="$pc_file"
else
  allowlist_file="$(resolve_rule_file "$cwd" "always/placement/directory-structure/rule.md" "directory-structure-rules/rule.md")"
fi

# 各ディレクトリをチェック
results=""
for d in "${dirs[@]}"; do
  # 絶対パスに変換
  if [[ "$d" = /* ]]; then
    abs="$d"
  else
    abs="${cwd}/${d}"
  fi
  abs="${abs%/}"

  # リポジトリルートからの相対パスを算出
  rel="${abs#"${cwd}"/}"
  [[ "$rel" = "$abs" ]] && continue

  # パス要素を分解
  IFS='/' read -ra parts <<< "$rel"
  depth=${#parts[@]}
  dirname_base="${parts[$((depth - 1))]}"

  if [ "$depth" -eq 1 ]; then
    # ルート直下
    if [ ! -f "$allowlist_file" ]; then
      results="${results}[DIR-STRUCTURE-NO-LIST]
このリポジトリに許可リスト（project-context/rule.md の「## ルート直下許可ディレクトリ」節、または旧専用ファイル）が存在しません: ${allowlist_file}
ディレクトリ「${dirname_base}」をルート直下に作成しようとしています。
許可リストを作成してからディレクトリを作成することを推奨します。

"
    else
      allowed_dirs="$(parse_root_allowlist "$allowlist_file" 2>/dev/null || echo "")"
      if echo "$allowed_dirs" | grep -qxF "$dirname_base"; then
        results="${results}[DIR-STRUCTURE-OK]
ディレクトリ「${dirname_base}」は許可リストに存在します。

"
      else
        results="${results}[DIR-STRUCTURE-CHECK]
ルート直下に「${dirname_base}」を新規作成しようとしています。
このディレクトリは許可リスト（${allowlist_file}）に存在しません。
~/.claude/rules/always/placement/directory-structure/rule.md を参照。

"
      fi
    fi
  elif [ "$depth" -eq 2 ]; then
    # 2 階層目: サブディレクトリ許可リストをチェック
    parent_name="${parts[0]}"
    sub_allowed="$(parse_sub_allowlist "$allowlist_file" "$parent_name" 2>/dev/null || echo "")"
    if [ -n "$sub_allowed" ]; then
      # サブ許可リストが定義されている親ディレクトリ
      if echo "$sub_allowed" | grep -qxF "$dirname_base"; then
        results="${results}[DIR-STRUCTURE-OK]
ディレクトリ「${parent_name}/${dirname_base}」はサブ許可リストに存在します。

"
      else
        results="${results}[DIR-STRUCTURE-CHECK]
「${parent_name}/」配下に「${dirname_base}」を新規作成しようとしています。
このディレクトリはサブ許可リスト（${allowlist_file}）に存在しません。
~/.claude/rules/always/placement/directory-structure/rule.md を参照。

"
      fi
    else
      # サブ許可リストが未定義 → 子ディレクトリ扱い（確認のみ）
      results="${results}[DIR-STRUCTURE-CHILD]
「${parent_name}/${dirname_base}」を新規作成しようとしています。
~/.claude/rules/always/placement/directory-structure/rule.md を参照。

"
    fi
  else
    # 3 階層目以降: 確認のみ
    parent_rel="$(dirname "$rel")"
    results="${results}[DIR-STRUCTURE-CHILD]
「${parent_rel}/${dirname_base}」を新規作成しようとしています。
~/.claude/rules/always/placement/directory-structure/rule.md を参照。

"
  fi
done

if [ -n "$results" ]; then
  printf '%s' "$results"
fi

exit 0
