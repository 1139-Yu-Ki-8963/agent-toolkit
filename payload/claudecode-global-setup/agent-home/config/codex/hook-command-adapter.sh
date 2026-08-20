#!/usr/bin/env bash

set -uo pipefail

event="${1:?Codex event is required}"
id="${2:?hook id is required}"
agent_home_root="${AGENT_HOME_ROOT:-$HOME/agent-home}"
registry="${CODEX_HOOK_REGISTRY:-$agent_home_root/config/codex/hooks-registry.json}"
input_file="$(mktemp "${TMPDIR:-/tmp}/codex-hook-input.XXXXXX")"
output_file="$(mktemp "${TMPDIR:-/tmp}/codex-hook-output.XXXXXX")"
status_file="$(mktemp "${TMPDIR:-/tmp}/codex-hook-status.XXXXXX")"
compat_input_file="$(mktemp "${TMPDIR:-/tmp}/codex-hook-compat-input.XXXXXX")"
turn_input_file="$(mktemp "${TMPDIR:-/tmp}/codex-hook-turn-input.XXXXXX")"
trap 'rm -f "$input_file" "$output_file" "$status_file" "$compat_input_file" "$turn_input_file"' EXIT
cat >"$input_file"

command="$(jq -r --arg id "$id" '.commands[$id].command // empty' "$registry" 2>/dev/null)"
[ -n "$command" ] || exit 0

source_event="$(jq -r --arg id "$id" '.commands[$id].sourceEvent // empty' "$registry" 2>/dev/null)"
source_matcher="$(jq -r --arg id "$id" '.commands[$id].matcher // "*"' "$registry" 2>/dev/null)"

# SessionStart は context injection の契機にすぎず、Skill 実行完了を意味しない。
# workflow context の供給記録は UserPromptSubmit hook が独立して管理する。

if [ "$source_matcher" = "EnterPlanMode" ] || [ "$source_matcher" = "ExitPlanMode" ]; then
    phase="$(jq -r '[.tool_input.plan[]?.status] | if length == 0 then "other" elif all(. == "completed" or . == "cancelled") then "exit" elif any(. == "in_progress") then "enter" else "other" end' "$input_file" 2>/dev/null)"
    [ "$source_matcher" = "EnterPlanMode" ] && [ "$phase" != "enter" ] && exit 0
    [ "$source_matcher" = "ExitPlanMode" ] && [ "$phase" != "exit" ] && exit 0
    jq --arg tool "$source_matcher" '.tool_name = $tool' "$input_file" >"$compat_input_file" 2>/dev/null || cp "$input_file" "$compat_input_file"
else
    cp "$input_file" "$compat_input_file"
fi

# Codex の後続イベントには prompt 本文が無いことがあるため、UserPromptSubmit
# で現在ターンの hash だけを保存し、PreToolUse/Stop の互換入力へ注入する。
# これは Skill 実行記録ではなく、stale-turn 検出専用の派生状態である。
session_id="$(jq -r '.session_id // empty' "$input_file" 2>/dev/null)"
turn_state_dir="${TMPDIR:-/tmp}/session-workflow-context"
turn_state_file="$turn_state_dir/${session_id}.turn.json"
cleanup_turn_state=false
if [ "$source_event" = "SessionStart" ] && [ -n "$session_id" ]; then
    # A reused session id must never inherit the prior run's turn hash.
    rm -f "$turn_state_file"
elif [ "$source_event" = "UserPromptSubmit" ] && [ -n "$session_id" ]; then
    prompt="$(jq -r '.prompt // empty' "$input_file" 2>/dev/null)"
    if [ -n "$prompt" ]; then
        prompt_sha="$(printf '%s' "$prompt" | shasum -a 256 | awk '{print $1}')"
        mkdir -p "$turn_state_dir"
        jq -n --arg sessionId "$session_id" --arg promptSha256 "$prompt_sha" \
          '{schemaVersion:1,sessionId:$sessionId,currentPromptSha256:$promptSha256}' \
          >"$turn_state_file"
    else
        # Missing prompt means the current turn cannot be identified. Fail closed
        # by discarding any prior hash instead of treating it as the new turn.
        rm -f "$turn_state_file"
    fi
elif [ -n "$session_id" ] && [ -f "$turn_state_file" ]; then
    prompt_sha="$(jq -r '.currentPromptSha256 // empty' "$turn_state_file" 2>/dev/null)"
    if [ -n "$prompt_sha" ]; then
        jq --arg promptSha "$prompt_sha" \
          '.current_prompt_sha256 = $promptSha' "$compat_input_file" >"$turn_input_file" &&
          cp "$turn_input_file" "$compat_input_file"
    fi
fi
if [ "$source_event" = "Stop" ] && [ -n "$session_id" ]; then
    cleanup_turn_state=true
fi


# Claude exposes failure-only events that Codex currently folds into their
# successful counterparts. Preserve the source timing where Codex exposes a
# reliable success marker; otherwise skip the failure-only notification rather
# than duplicate it on every normal completion.
if [ "$source_event" = "PostToolUseFailure" ]; then
    successful="$(jq -r '
      if .tool_response.success == true then "true"
      elif (.tool_response.exit_code? == 0) then "true"
      elif (.tool_response.status? == "completed" and .tool_response.is_error? != true) then "true"
      else "false" end
    ' "$input_file" 2>/dev/null)"
    [ "$successful" = "true" ] && exit 0
fi
if [ "$source_event" = "StopFailure" ]; then
    # Stop has no failure discriminator in Codex v0.145.0. A missing final
    # assistant message is the only safe failure signal available in its wire
    # input; normal completed turns are suppressed to avoid duplicate notify.
    last_message="$(jq -r '.last_assistant_message // empty' "$input_file" 2>/dev/null)"
    [ -n "$last_message" ] && exit 0
fi

cwd="$(jq -r '.cwd // empty' "$input_file" 2>/dev/null)"
export SUPERSET_HOME_DIR="${SUPERSET_HOME_DIR:-$HOME/.superset}"
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$cwd}"
export CLAUDE_SESSION_ID="$(jq -r .session_id "$input_file" 2>/dev/null)"
export CLAUDE_TRANSCRIPT_PATH="$(jq -r .transcript_path "$input_file" 2>/dev/null)"
command="${command//SUPERSET_AGENT_ID=claude/SUPERSET_AGENT_ID=codex}"

bash -c "$command" <"$compat_input_file" >"$output_file" 2>&1
printf '%s' "$?" >"$status_file"
[ "$cleanup_turn_state" = true ] && rm -f "$turn_state_file"

python3 - "$event" "$id" "$output_file" "$status_file" <<'PY'
import json
import sys

event, hook_id, output_path, status_path = sys.argv[1:]
text = open(output_path, encoding="utf-8", errors="replace").read()
status = int(open(status_path).read() or "0")
decoder = json.JSONDecoder()
cursor = 0
plain = []
ui_messages = []
context_messages = []
blocked = []

while cursor < len(text):
    start = text.find("{", cursor)
    if start < 0:
        plain.extend(line for line in text[cursor:].splitlines() if line.strip())
        break
    plain.extend(line for line in text[cursor:start].splitlines() if line.strip())
    try:
        value, end = decoder.raw_decode(text[start:])
    except json.JSONDecodeError:
        plain.append(text[start:].splitlines()[0].strip())
        cursor = start + 1
        continue
    cursor = start + end
    if value.get("decision") == "block":
        blocked.append(value.get("reason") or value.get("systemMessage") or "hook blocked the turn")
    if value.get("systemMessage"):
        ui_messages.append(str(value["systemMessage"]))
    nested = value.get("hookSpecificOutput") or {}
    if nested.get("additionalContext"):
        context_messages.append(str(nested["additionalContext"]))

context_messages.extend(plain)
if status == 2 and not blocked:
    blocked.append(f"[CLAUDE-COMPAT-BLOCK] hook {hook_id} exited with status 2")

if blocked and event == "PreToolUse":
    reason = "\n".join(blocked)
    payload = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }
    if ui_messages:
        payload["systemMessage"] = "\n".join(ui_messages)
elif blocked and event == "PermissionRequest":
    reason = "\n".join(blocked)
    payload = {
        "hookSpecificOutput": {
            "hookEventName": "PermissionRequest",
            "decision": {"behavior": "deny", "message": reason},
        }
    }
    if ui_messages:
        payload["systemMessage"] = "\n".join(ui_messages)
elif blocked:
    payload = {"continue": False, "stopReason": "\n".join(blocked + ui_messages + context_messages)}
    if ui_messages:
        payload["systemMessage"] = "\n".join(ui_messages)
elif not ui_messages and not context_messages:
    raise SystemExit(0)
elif event in {"SessionStart", "UserPromptSubmit", "PostToolUse", "PreToolUse", "SubagentStart", "SubagentStop"}:
    payload = {}
    if ui_messages:
        payload["systemMessage"] = "\n".join(ui_messages)
    if context_messages:
        payload["hookSpecificOutput"] = {"hookEventName": event, "additionalContext": "\n".join(context_messages)}
else:
    payload = {"systemMessage": "\n".join(ui_messages + context_messages)}
print(json.dumps(payload, ensure_ascii=False))
PY
