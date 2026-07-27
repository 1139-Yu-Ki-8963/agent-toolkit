#!/usr/bin/env bash
# check-dev-flow-phase-gate.sh
# PreToolUse(Write|Edit) で以下を block する:
#   1. .flow-progress.json への直接書き込み（update-flow-status.sh 経由のみ許可）
#   2. ~/Projects/ 配下のコードファイル編集（前提 Phase 未完了時）
set -euo pipefail

input=$(cat)
warning_context=""

emit_json() {
  local decision="${1:-}"
  local message="${2:-}"
  local system_message="${3:-}"
  if [ "$decision" = "block" ]; then
    jq -n --arg ctx "$message" --arg system "$system_message" \
      '{"decision":"block","systemMessage":$system,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  elif [ -n "$message" ]; then
    jq -n --arg ctx "$message" --arg system "$system_message" \
      '{"systemMessage":$system,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  fi
}

block() {
  local message="$1"
  local system_message="$2"
  if [ -n "$warning_context" ]; then
    message="${warning_context}
${message}"
  fi
  emit_json block "$message" "$system_message"
  exit 2
}

pass() {
  if [ -n "$warning_context" ]; then
    emit_json "" "$warning_context" "[フック発火] FLOW-GATE: YAML parser 利用不可"
  fi
  exit 0
}

[ "${CLAUDE_HOOKS_TEST:-}" = "1" ] && exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"
case "$cwd" in
  */agent-home|*/agent-home/*) exit 0 ;;
  */agent-toolkit|*/agent-toolkit/*) exit 0 ;;
esac

[ "${CLAUDE_SKILL_NAME:-}" = "creating-new-project" ] && exit 0

file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$file_path" ] && exit 0

case "$file_path" in
  /*) abs="$file_path" ;;
  *) abs="$cwd/$file_path" ;;
esac

# --- .flow-progress.json 直接書き換え防止 ---
case "$(basename "$abs")" in
  .flow-progress.json)
    ctx="[DEV-FLOW-PHASE-GATE-BLOCK] .flow-progress.json への直接書き込みは禁止されています。Phase 進捗は update-flow-status.sh 経由で更新してください。"
    block "$ctx" "[フック発火] FLOW-GATE: .flow-progress.json 直接編集"
    ;;
esac

# --- ~/Projects/ 配下のみチェック ---
case "$abs" in
  "$HOME/Projects/"*) ;;
  *) exit 0 ;;
esac

dir=$(dirname "$abs")
# 新規ネストディレクトリへの初回 Write では $dir がまだ実在しないため、
# 実在する最初の祖先ディレクトリまで遡ってから git rev-parse する
# （worktree ルート自体は常に実在するため、中間ディレクトリが未作成でも正しく解決できる）
check_dir="$dir"
while [ ! -d "$check_dir" ] && [ "$check_dir" != "/" ] && [ "$check_dir" != "." ]; do
  check_dir=$(dirname "$check_dir")
done
project_root=$(git -C "$check_dir" rev-parse --show-toplevel 2>/dev/null || true)

if [ -z "$project_root" ]; then
  rel="${abs#$HOME/Projects/}"
  project_name="${rel%%/*}"
  project_root="$HOME/Projects/$project_name"
fi

rel_from_root="${abs#$project_root/}"

flow_context="$project_root/.claude/rules/always/project-context/flow-values.yml"
if [ -f "$flow_context" ]; then
  yaml_validator="${DEV_FLOW_YAML_VALIDATOR:-auto}"
  if [ "$yaml_validator" = "auto" ]; then
    if command -v ruby >/dev/null 2>&1; then
      yaml_validator="ruby"
    elif command -v yq >/dev/null 2>&1; then
      yaml_validator="yq"
    elif command -v node >/dev/null 2>&1 &&
      node -e 'require.resolve("js-yaml")' >/dev/null 2>&1; then
      yaml_validator="node"
    else
      yaml_validator="unavailable"
    fi
  fi

  yaml_valid=true
  case "$yaml_validator" in
    ruby)
      if command -v ruby >/dev/null 2>&1; then
        ruby -e 'require "yaml"; YAML.safe_load(File.read(ARGV[0]), permitted_classes: [], aliases: false)' \
          "$flow_context" >/dev/null 2>&1 || yaml_valid=false
      else
        yaml_valid="unknown"
      fi
      ;;
    yq)
      if command -v yq >/dev/null 2>&1; then
        yq eval '.' "$flow_context" >/dev/null 2>&1 || yaml_valid=false
      else
        yaml_valid="unknown"
      fi
      ;;
    node)
      if command -v node >/dev/null 2>&1 &&
        node -e 'require.resolve("js-yaml")' >/dev/null 2>&1; then
        node -e 'require("js-yaml").load(require("fs").readFileSync(process.argv[1], "utf8"))' \
          "$flow_context" >/dev/null 2>&1 || yaml_valid=false
      else
        yaml_valid="unknown"
      fi
      ;;
    unavailable) yaml_valid="unknown" ;;
    *) yaml_valid="unknown" ;;
  esac

  if [ "$yaml_valid" = false ]; then
    ctx="[DEV-FLOW-PHASE-GATE-BLOCK] parser が既存の flow-values.yml を不正と判定しました。YAML を修正してから続行してください。対象: $flow_context"
    block "$ctx" "[フック発火] FLOW-GATE: flow-values.yml 不正"
  elif [ "$yaml_valid" = "unknown" ]; then
    warning_context="[DEV-FLOW-PHASE-GATE-WARN] YAML parser を利用できないため flow-values.yml の構文を断定せず、既存 Phase 判定を続行します。"
  fi
fi

# --- Phase 順序検証 ---
current_phase=""
route=""
progress_file="$project_root/.flow-progress.json"

if [ -f "$progress_file" ]; then
  current_phase=$(jq -r '.current_phase // empty' "$progress_file" 2>/dev/null)
  route=$(jq -r '.route // empty' "$progress_file" 2>/dev/null)
fi

if [ -z "$current_phase" ]; then
  session="${CLAUDE_SESSION_ID:-${SESSION_ID:-unknown}}"
  status_dir="${TMPDIR:-/tmp}/claude-hooks/${session}"
  status_file="${status_dir}/flow-status.json"
  if [ -f "$status_file" ]; then
    current_phase=$(jq -r '.current_phase // empty' "$status_file" 2>/dev/null)
  fi
fi

[ -z "$current_phase" ] && current_phase="0"

# ルート別のコード書き込み前提条件
code_prereqs=""
case "$route" in
  feature-with-full-planning)     code_prereqs="1 2 3 4 5" ;;
  feature-with-quick-delivery)    code_prereqs="1 2 5" ;;
  refactor-with-safety-guarantee) code_prereqs="1 2 5" ;;
  config-with-review-and-verify)  code_prereqs="1 2" ;;
  incident-with-emergency-path)   code_prereqs="1 2" ;;
  "")
    case "$rel_from_root" in
      .claude/*|CLAUDE.md|docs/*|slides/*) pass ;;
    esac
    # route 不明: 従来の current_phase >= 6 フォールバック
    phase_num=$((current_phase + 0)) 2>/dev/null || phase_num=0
    if [ "$phase_num" -lt 6 ]; then
      ctx="[DEV-FLOW-PHASE-GATE-BLOCK] 現在 Phase ${current_phase} です。Phase 6（実装）に到達するまでコードの書き込みはできません。対象: $abs"
      block "$ctx" "[フック発火] FLOW-GATE: Phase 6 未到達"
    fi
    pass
    ;;
esac

handoff_file="${DEV_FLOW_HANDOFF_FILE:-$project_root/.claude/dev-flow/handoff-and-coverage.json}"
case "$abs" in
  "$handoff_file") pass ;;
esac

# phases_completed を検証
if [ -f "$progress_file" ]; then
  missing=""
  for prereq in $code_prereqs; do
    if ! jq -e --arg p "$prereq" '.phases_completed | map(tostring) | index($p)' "$progress_file" > /dev/null 2>&1; then
      missing="$missing Phase-$prereq"
    fi
  done

  if [ -n "$missing" ]; then
    ctx="[DEV-FLOW-PHASE-GATE-BLOCK] コード書き込みの前提 Phase が未完了です。不足:${missing}。ルート: ${route}。対象: ${abs}"
    block "$ctx" "[フック発火] FLOW-GATE: 前提 Phase 未完了"
  fi
else
  # progress_file がない場合はフォールバック
  phase_num=$((current_phase + 0)) 2>/dev/null || phase_num=0
  if [ "$phase_num" -lt 6 ]; then
    ctx="[DEV-FLOW-PHASE-GATE-BLOCK] 現在 Phase ${current_phase} です。Phase 6（実装）に到達するまでコードの書き込みはできません。対象: $abs"
    block "$ctx" "[フック発火] FLOW-GATE: Phase 6 未到達"
  fi
fi

handoff_validator="${DEV_FLOW_HANDOFF_VALIDATOR:-$HOME/agent-home/skills/orchestrating-dev-flow/scripts/validate-handoff-coverage.mjs}"
if [ ! -f "$handoff_file" ]; then
  ctx="[DEV-FLOW-PHASE-GATE-BLOCK] 正規 handoff/coverage artifact がありません。既存ルートの計画工程で作成し、implementation validator を通してください。対象: $handoff_file"
  block "$ctx" "[フック発火] FLOW-GATE: handoff/coverage 未作成"
fi
if [ ! -f "$handoff_validator" ] ||
  ! node "$handoff_validator" implementation "$handoff_file" >/dev/null 2>&1; then
  ctx="[DEV-FLOW-PHASE-GATE-BLOCK] 正規 handoff/coverage artifact が implementation validator を通過していません。対象: $handoff_file"
  block "$ctx" "[フック発火] FLOW-GATE: handoff/coverage 不備"
fi

pass
