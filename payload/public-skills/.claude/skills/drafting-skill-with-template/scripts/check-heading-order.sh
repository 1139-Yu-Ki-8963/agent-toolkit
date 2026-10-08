#!/bin/sh
[ $# -eq 1 ] && [ -f "$1" ] && [ -r "$1" ] || { echo "使い方: $0 <SKILL.md のパス>" >&2; exit 2; }
LC_ALL=C awk -v F="$1" '
function row(l, t, d) { printf "| 雛形の本文 | %s | %s:%d | %s |\n", t, F, l, d; n++ }
BEGIN { nh = split("# <日本語名>|## 全体像|### 開始時の入力|### 中間成果物|### 最終出力|### 流れ|## 前提ツール|## 使用するスクリプト|## 使用するリファレンス", H, "|")
  X["P"] = "### step <番号> <step の名前>"; X["S"] = "#### ユーザーに見せる文面 か #### 手順"; X["U"] = "#### 手順"; X["T"] = "#### ── step <番号> の情報 ──"; X["I"] = "### step <番号> <step の名前> か ## phase <番号> <名前>" }
NR == 1 && $0 == "---" { fm = 1; next }
fm { if ($0 == "---") fm = 0; next }
!fe && /^```/ { fe = $0; sub(/[^`].*$/, "", fe); next }
fe { if ($0 == fe) fe = ""; next }
!/^#/ { next }
k < nh { k++; if (k == 1 ? !/^# [^#]/ : $0 != H[k]) row(NR, H[k], "「" $0 "」がある"); next }
/^## phase [0-9]+ / { y = "P"; ok = (st == "I" || st == "") }
/^### step [0-9]+-[0-9]+ / { y = "S"; ok = (st == "P" || st == "I"); cur = $3 }
/^#### ユーザーに見せる文面$/ { y = "U"; ok = (st == "S") }
/^#### 手順$/ { y = "T"; ok = (st == "S" || st == "U") }
/^#### ── step [0-9]+-[0-9]+ の情報 ──$/ { y = "I"; ok = (st == "T" && $4 == cur) }
{ w = (st == "") ? "## phase 1 <名前>" : X[st]; if (st == "T") sub(/<番号>/, cur, w); if (!y) ok = 0; if (!ok) row(NR, w, "「" $0 "」がある"); if (y) st = y; y = "" }
END { if (k < nh) row(NR, H[k + 1], "見出しがない"); else if (st != "I") row(NR, (st == "") ? "## phase 1 <名前>" : X[st], "見出しがない")
  exit n > 0 }' "$1"
