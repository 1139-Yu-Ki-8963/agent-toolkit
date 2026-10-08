#!/bin/sh
[ $# -eq 1 ] && [ -f "$1" ] && [ -r "$1" ] || { echo "使い方: $0 <SKILL.md のパス>" >&2; exit 2; }
LC_ALL=C awk -v F="$1" '
function row(l, d) { printf "| この雛形で作るスキルが守ること | %s | %s:%d | %s |\n", T, F, l, d; n++ }
function run(s,   k, g, p, a, b, i) { k = 0; E = 0; g = 0
  while (match(s, /^[0-9]+-[0-9]+/)) { p = substr(s, 1, RLENGTH); E += RLENGTH; s = substr(s, RLENGTH + 1)
    if (g) { split(R[k], a, "-"); split(p, b, "-"); for (i = a[2] + 1; i < b[2]; i++) R[++k] = a[1] "-" i }
    R[++k] = p; g = (s ~ /^ から [0-9]/)
    if (!match(s, /^( から |、| と |と)[0-9]/)) break
    E += RLENGTH - 1; s = substr(s, RLENGTH) }
  return k }
function cell(x, kd, nm,   i, j, k) { while ((i = index(x, "(")) && (j = index(substr(x, i), ")"))) x = substr(x, 1, i - 1) substr(x, i + j)
  sub(/^ +/, "", x); k = run(x); for (i = 1; i <= k; i++) TB[kd, nm, R[i]] = NR }
BEGIN { T = "「#### ── step <番号> の情報 ──」の入力と出力の文に含まれる名前と step の番号は、中間成果物の表の「名前」「出す step」「使う step」と、最終出力の表の「名前」と一致する。"; W["出力"] = "出す"; W["入力"] = "使う" }
!fe && /^```/ { fe = $0; sub(/[^`].*$/, "", fe); next }
fe { if ($0 == fe) fe = ""; next }
/^### 中間成果物$/ { it = 1; next }
/^#/ { it = 0; cur = "" }
it && /^\| / && !/^\| 名前 \|/ && !/^\|-/ { split($0, c, / *\| */); N[++nn] = c[2]; cell(c[4], "出力", c[2]); cell(c[5], "入力", c[2]) }
/^#### ── step [0-9]+-[0-9]+ の情報 ──$/ { cur = $4 }
cur != "" && /^- (入力|出力): / { nl++; L[nl] = $0; LS[nl] = cur; LK[nl] = substr($0, 3, length("入力")); LN[nl] = NR }
END {
  for (i = 1; i <= nn; i++) for (j = i + 1; j <= nn; j++) if (length(N[j]) > length(N[i])) { t = N[i]; N[i] = N[j]; N[j] = t }
  for (x = 1; x <= nl; x++) { m = L[x]; s = LS[x]; k = LK[x]; o = (k == "入力") ? "出力" : "入力"; split("", P)
    for (i = 1; i <= nn; i++) while ((p = index(m, N[i]))) { M[k, N[i], s] = LN[x]; P[p] = N[i]; r = N[i]; gsub(/./, "\001", r); m = substr(m, 1, p - 1) r substr(m, p + length(N[i])) }
    q = 0; while ((p = index(substr(L[x], q + 1), "step "))) { st = q + p; q = st + 4; h = run(substr(L[x], q + 1)); nm = ""
      if (substr(L[x], q + 1 + E, length(" で")) == " で") { b = 0; z = index(substr(L[x], q + 1 + E), "step "); z = z ? q + E + z : length(L[x]) + 1
        for (p in P) if (p + 0 > q && p + 0 < z && (!b || p + 0 < b)) b = p + 0; if (b) nm = P[b] }
      else if (substr(L[x], st - length("を "), length("を ")) == "を ") for (p in P) if (p + length(P[p]) == st - length("を ")) nm = P[p]
      for (j = 1; nm != "" && j <= h; j++) if (!((o, nm, R[j]) in TB)) row(LN[x], "step " s " の" k "の文の「" nm "」の step " R[j] " が、中間成果物の表の" W[o] " step にない") } }
  for (key in TB) if (!(key in M)) { split(key, a, SUBSEP); row(TB[key], "中間成果物の表の「" a[2] "」の" W[a[1]] " step " a[3] " の" a[1] "の文に、この名前がない") }
  for (key in M) if (!(key in TB)) { split(key, a, SUBSEP); row(M[key], "step " a[3] " の" a[1] "の文に「" a[2] "」があるが、中間成果物の表の" W[a[1]] " step に " a[3] " がない") }
  exit n > 0 }' "$1"
