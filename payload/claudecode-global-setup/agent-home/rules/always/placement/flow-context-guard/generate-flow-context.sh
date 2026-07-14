#!/usr/bin/env bash
set -euo pipefail

# generate-flow-context.sh — PostToolUse(Bash)
# git clone / git init / git worktree add 完了後に
# ~/Projects/ 配下のリポジトリに flow-values.yml が無ければ自動生成する。
# .claude/rules は実体ディレクトリとして直接生成する（symlink 方式は廃止済み）。

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -z "$cwd" ] && cwd="$PWD"

# git clone / git init / git worktree add 以外は対象外
case "$cmd" in
  *"git clone"*|*"git init"*|*"git worktree add"*) ;;
  *) exit 0 ;;
esac

# 対象リポジトリのパスを特定
target_path=""
if printf '%s' "$cmd" | grep -qE 'git[[:space:]]+clone'; then
  # git clone の場合: clone先ディレクトリを推定
  # パターン1: git clone <url> <dir> → <dir>
  # パターン2: git clone <url> → リポジトリ名から導出
  # パターン3: git -C <dir> clone ... → -C の引数
  if printf '%s' "$cmd" | grep -qE 'git[[:space:]]+-C[[:space:]]+'; then
    c_dir="$(printf '%s' "$cmd" | sed -E 's/.*git[[:space:]]+-C[[:space:]]+([^[:space:]]+).*/\1/')"
    case "$c_dir" in
      /*) target_path="$c_dir" ;;
      *) target_path="$cwd/$c_dir" ;;
    esac
  else
    # 最後の引数がURLでなければclone先ディレクトリ
    last_arg="$(printf '%s' "$cmd" | awk '{print $NF}')"
    case "$last_arg" in
      *://*|*.git|*@*)
        # URLっぽい → リポジトリ名を導出
        repo_name="$(basename "$last_arg" .git)"
        target_path="$cwd/$repo_name"
        ;;
      *)
        case "$last_arg" in
          /*) target_path="$last_arg" ;;
          *) target_path="$cwd/$last_arg" ;;
        esac
        ;;
    esac
  fi
elif printf '%s' "$cmd" | grep -qE 'git[[:space:]]+init'; then
  # git init の場合: 引数があればそのパス、なければcwd
  init_arg="$(printf '%s' "$cmd" | sed -E 's/.*git[[:space:]]+init[[:space:]]*//' | awk '{print $1}')"
  if [ -n "$init_arg" ]; then
    case "$init_arg" in
      /*) target_path="$init_arg" ;;
      *) target_path="$cwd/$init_arg" ;;
    esac
  else
    target_path="$cwd"
  fi
elif printf '%s' "$cmd" | grep -qE 'git[[:space:]]+worktree[[:space:]]+add'; then
  # git worktree add <path> の場合: addの直後の引数がパス
  wt_path="$(printf '%s' "$cmd" | sed -E 's/.*git[[:space:]]+((-C[[:space:]]+[^[:space:]]+[[:space:]]+)?worktree[[:space:]]+add[[:space:]]+)//' | awk '{print $1}')"
  if [ -n "$wt_path" ]; then
    case "$wt_path" in
      /*) target_path="$wt_path" ;;
      *) target_path="$cwd/$wt_path" ;;
    esac
  fi
fi

[ -z "$target_path" ] && exit 0

# ~/Projects/ 配下か確認
case "$target_path" in
  "$HOME/Projects/"*) ;;
  *) exit 0 ;;
esac

# 対象パスが存在し、gitリポジトリであることを確認
[ ! -d "$target_path" ] && exit 0
root="$(git -C "$target_path" rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$root" ] && exit 0

# .claude/rules は実体ディレクトリとして直接使う。未配置なら作成する。
claude_dir="$root/.claude"
rules_dir="$claude_dir/rules"
mkdir -p "$rules_dir"

context_dir="$rules_dir/always/project-context"

# flow-values.yml が既に存在すれば何もしない
fc_path="$context_dir/flow-values.yml"
[ -f "$fc_path" ] && exit 0

# デフォルト内容で自動生成
mkdir -p "$context_dir"
cat > "$fc_path" <<'YAML'
# プロジェクト実装フロー設定（スキーマ正本: ~/.claude/rules/scoped/agent-config/project-structure/rule.md）
domain_glossary: null
design_system: null
test_conventions: null
adr_dir: null
design_docs: null
portal_dir: null
review_gates: {}
review_agents: {}
pr: {}
classify: {}
preflight: {}
YAML

# rule.md が無ければプロジェクト概要の雛形も生成する（既存があればスキップ）
context_rule_path="$context_dir/rule.md"
if [ ! -f "$context_rule_path" ]; then
  # ルート直下の実在ディレクトリを許可リスト節の初期値として列挙（ls -d */ 相当）
  allowlist_rows=""
  for d in "$root"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    allowlist_rows="${allowlist_rows}| ${name} | （記入） |
"
  done
  {
    cat <<'MARKDOWN'
# プロジェクト概要（project-context）

<!-- このプロジェクトの概要・技術スタック・設定索引を 80 行以内で記載する（許可リスト節は予算対象外）。
     正本規約: ~/.claude/rules/scoped/agent-config/project-structure/rule.md -->

## 概要

（1〜3 行で記載）

## 技術スタック

（箇条書きで記載）

## 設定索引

- 実装フロー設定値: 同フォルダの flow-values.yml

## ルート直下許可ディレクトリ

| ディレクトリ名 | 用途 |
|---|---|
MARKDOWN
    printf '%s' "$allowlist_rows"
  } > "$context_rule_path"
fi

# 生成した旨を通知
repo_name="$(basename "$root")"
ctx="[FLOW-CONTEXT-GENERATED] ~/Projects/${repo_name}/.claude/rules/always/project-context/ 配下（flow-values.yml・ルート直下許可リスト節を含む rule.md）をデフォルト内容で自動生成しました。プロジェクト固有の設定（domain_glossary・design_system・許可リスト用途欄等）は Skill(creating-new-project) または手動で更新してください。"
jq -n --arg ctx "$ctx" '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$ctx}}'
exit 0
