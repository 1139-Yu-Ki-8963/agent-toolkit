#!/bin/sh
[ $# -eq 1 ] && [ -f "$1" ] && [ -r "$1" ] || { echo "使い方: $0 <SKILL.md のパス>" >&2; exit 2; }
LC_ALL=C awk -v F="$1" '
function row(l, t, d) { printf "| この雛形で作るスキルが守ること | %s | %s:%d | %s |\n", t, F, l, d; n++ }
BEGIN { A = "phase は 1 から、各 phase の step は 1 から空きなく並ぶ。"; B = "流れの表、行き先、中止の文面の中の番号は、見出しの番号と一致する。" }
!fe && /^```/ { fe = $0; sub(/[^`].*$/, "", fe); next }
fe { if ($0 == fe) fe = ""; next }
/^### 流れ$/ { fl = 1; next }
/^#/ { fl = 0 }
fl && /^\| [0-9]+ \|/ { split($0, c, / *\| */); nf++; fp[nf] = c[2]; fr[nf] = c[4]; fn[nf] = NR; next }
/^## phase / { if ($3 != np + 1) row(NR, A, "phase " $3 " の前の phase が " np); np = $3; hl[np] = NR; next }
/^### step / { split($3, s, "-"); if (s[1] != np || s[2] != ns[np] + 1) row(NR, A, "見出しの step " $3 " が、並びでは step " np "-" ns[np] + 1 " の位置にある"); ns[np] = s[2]; next }
END {
  if (!nf) row(NR, B, "流れの表の行がない")
  for (i = 1; i <= nf; i++) { p = fp[i]; ok[p] = 1; w = (ns[p] > 1) ? p "-1 から " p "-" ns[p] : p "-1"
    if (!(p in hl)) row(fn[i], B, "phase " p " の見出しがない")
    else if (fr[i] != w) row(fn[i], B, "流れの表の step は " fr[i] "、見出しの step は " w) }
  for (p in hl) if (!(p in ok)) row(hl[p], B, "phase " p " の行が流れの表にない")
  exit n > 0 }' "$1"
