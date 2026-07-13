#!/usr/bin/env python3
import json
import os
import subprocess
import sys

def ring(pct):
    if pct is None:
        return "?"
    if pct < 13:
        return "○"
    if pct < 38:
        return "◔"
    if pct < 63:
        return "◑"
    if pct < 88:
        return "◕"
    return "●"

def color(pct):
    if pct is None:
        return "\033[90m"   # gray
    if pct < 50:
        return "\033[32m"   # green
    if pct < 80:
        return "\033[33m"   # yellow
    return "\033[31m"       # red

RESET = "\033[0m"
GRAY  = "\033[90m"

def fmt_rate(label, pct):
    c = color(pct)
    r = ring(pct)
    val = f"{pct:.0f}%" if pct is not None else "?"
    return f"{c}{r} {label}:{val}{RESET}"

data = {}
try:
    data = json.load(sys.stdin)
except Exception:
    pass

# Model name
model = data.get("model", {}).get("display_name") or "Claude"

# Session ID
sid = data.get("session_id", "")

# Current folder
folder = os.path.basename(os.getcwd())

# Git branch
try:
    branch = subprocess.check_output(
        ["git", "branch", "--show-current"],
        stderr=subprocess.DEVNULL
    ).decode().strip()
except Exception:
    branch = ""

# Context window + rate limits (line 2)
ctx = data.get("context_window", {}).get("used_percentage")
rl = data.get("rate_limits", {})
fh = rl.get("five_hour", {}).get("used_percentage")
sd = rl.get("seven_day", {}).get("used_percentage")

# Session name
sname = data.get("session_name", "")

# Flow status from flow-status.json (used for Line 4)
def load_flow_status(session_id):
    if not session_id:
        return None
    tmpdir = os.environ.get("TMPDIR", "/tmp")
    candidates = []
    # worktree path
    cwd = data.get("cwd", "")
    if cwd:
        candidates.append(os.path.join(cwd, ".claude", "markers", session_id, "flow-status.json"))
    # /tmp path
    candidates.append(os.path.join(tmpdir, "claude-hooks", session_id, "flow-status.json"))
    # sandbox-writable fallback path (update-flow-status.sh writes here when
    # /tmp/claude-hooks is blocked by the Bash sandbox filesystem policy)
    candidates.append(os.path.join("/tmp", "claude", "claude-hooks", session_id, "flow-status.json"))
    for path in candidates:
        try:
            with open(path) as f:
                obj = json.load(f)
            cp = obj.get("current_phase")
            pn = obj.get("phase_name")
            cs = obj.get("current_step")
            ts = obj.get("total_steps")
            sn = obj.get("step_name")
            if cp is None or pn is None or cs is None or ts is None or sn is None:
                continue
            # progress bar (parallelogram-style, 13 chars wide)
            filled = round(cs / ts * 13) if ts > 0 else 0
            filled = max(0, min(13, filled))
            bar = "▰" * filled + "▱" * (13 - filled)
            return f"\033[36m⚙ Phase {cp} {pn} {bar} {cs}/{ts} {sn}{RESET}"
        except Exception:
            pass
    return None

# Line 1: model / folder / branch
line1 = f"🤖 {model} | 📂 {folder}"
if branch:
    line1 += f" | Branch: {branch}"

# Line 2: session id + session name
line2_parts = []
if sid:
    line2_parts.append(f"Session: {sid[:8]}")
if sname:
    line2_parts.append(f"Name: {sname}")
line2 = " | ".join(line2_parts) if line2_parts else ""

# Line 3: ctx / 5h / 7d
line3_parts = [fmt_rate("ctx", ctx), fmt_rate("5h", fh), fmt_rate("7d", sd)]
line3 = " ".join(line3_parts)

# Line 4: flow progress (optional)
line4 = load_flow_status(sid)

print(line1)
if line2:
    print(line2)
print(line3)
if line4:
    print(line4)
