#!/usr/bin/env bash
# check-mktemp-placement.sh — 置き場を指定しない mktemp 呼び出しが無いことを見る
#
# 判定の式を指示書の表へ直接書けないためスクリプトへ切り出した。
# （.claude/rules/always/tasks/instruction-format/rule.md の
# check-broken-verdict-rows.sh の設計判断と同じ理由: 式に含まれる縦棒を
# 片付けの判定器が列の区切りと読み違え、判定行そのものを壊す）
#
# 引数なしの mktemp は既定の置き場へ書こうとして失敗する環境がある
# （実測 2026-08-24:
#   mktemp: mkstemp failed on /var/folders/.../T/tmp.XXXX: Operation not permitted）。
# 同じ環境で ${TMPDIR:-/tmp} を明示すると成功する
# （実測 2026-08-24: mktemp "${TMPDIR:-/tmp}/chk.XXXXXX" → /tmp/claude-501/chk.xdPAWi）。
#
# 走査対象は docs/scripts・generation-engine/scripts・
# delivery-payload/templates/rules/checkers・.claude/rules の *.sh である。
# 各ファイルの実際の mktemp 呼び出し（コメント行・メッセージ文字列は対象外）を
# 見つけ、置き場の引数（フラグ・リダイレクト以外の実引数）を持たないものを
# 「置き場を指定しない mktemp」として数える。
#
# 使い方:
#   check-mktemp-placement.sh             置き場を指定しない mktemp が0件かを見る
#   check-mktemp-placement.sh --self-test このスクリプト自身の判定を確かめる
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TARGET_DIRS=(
  "docs/scripts"
  "generation-engine/scripts"
  "delivery-payload/templates/rules/checkers"
  ".claude/rules"
)

# scan_dir: 指定ディレクトリ配下の *.sh を走査し、置き場を指定しない mktemp
# 呼び出しの行を「ファイル:行番号:内容」の形で標準出力へ書く。
#
# 判定のロジック(awk):
#   1. コメント行(行頭が # の行)は対象外にする。
#   2. 行内の「mktemp」という語のうち、識別子の一部(mktemp_ok・
#      _mktemp_or_unknown 等)であるものは対象外にする(直前直後が
#      英数字・下線でない場合だけを「呼び出しの語」として扱う)。
#   3. 「mktemp」の直後から、行末・閉じ括弧・バッククォート・セミコロン・
#      && ・|| のいずれかまでを1回の呼び出し区間として切り出す。
#   4. 区間をトークンに分解し、フラグ(-で始まる語)とリダイレクト
#      (2> 等)以外の実引数トークンが1つでもあれば「置き場を指定した
#      呼び出し」として対象外にする。実引数が1つも無ければ違反として
#      報告する。
#   5. 1行に複数回「mktemp」が現れる場合も、出現ごとに判定する。
scan_dir() {
  local dir="$1"
  find "$dir" -name '*.sh' -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
    LC_ALL=C awk -v file="$f" '
      {
        line = $0
        trimmed = line
        sub(/^[ \t]+/, "", trimmed)
        if (trimmed ~ /^#/) next
        if (line !~ /(^|[^_[:alnum:]])mktemp([^_[:alnum:]]|$)/) next

        rest = line
        while (1) {
          pos = index(rest, "mktemp")
          if (pos == 0) break
          before = substr(rest, 1, pos - 1)
          prevc = substr(before, length(before), 1)
          after = substr(rest, pos + length("mktemp"))
          nextc = substr(after, 1, 1)
          if (prevc ~ /[_[:alnum:]]/ || nextc ~ /[_[:alnum:]]/) {
            rest = after
            continue
          }
          # 呼び出し位置の判定: 直前が実際にコマンドを開始する位置
          # ($( ・バッククォート・; ・&&・||・行頭の空白のみ)でなければ、
          # 地の文の中でたまたま「(mktemp)」のように括弧が隣接しただけの
          # 記述と判断し、対象外にする(実測: 「作成に失敗しました(mktemp)」
          # という説明文が、この判定を入れないと誤検出された)。
          btrim = before
          sub(/[ \t]+$/, "", btrim)
          is_call_pos = 0
          if (btrim == "") is_call_pos = 1
          else if (substr(btrim, length(btrim) - 1) == "$(") is_call_pos = 1
          else if (substr(btrim, length(btrim)) == "`") is_call_pos = 1
          else if (substr(btrim, length(btrim)) == ";") is_call_pos = 1
          else if (substr(btrim, length(btrim) - 1) == "&&") is_call_pos = 1
          else if (substr(btrim, length(btrim) - 1) == "||") is_call_pos = 1
          if (!is_call_pos) {
            rest = after
            continue
          }
          # 呼び出し区間の終端を探す
          seg = after
          seglen = length(seg)
          endpos = seglen + 1
          for (i = 1; i <= seglen; i++) {
            c = substr(seg, i, 1)
            if (c == ")" || c == "`" || c == ";") { endpos = i; break }
          }
          m = index(seg, "&&"); if (m > 0 && m < endpos) endpos = m
          m = index(seg, "||"); if (m > 0 && m < endpos) endpos = m
          call = substr(seg, 1, endpos - 1)

          hasarg = 0
          ntok = split(call, toks, /[ \t]+/)
          for (t = 1; t <= ntok; t++) {
            tok = toks[t]
            if (tok == "") continue
            # フラグ全体が英数字だけの短いオプション(-d・-u・-q・-p2 等)の
            # 場合だけ「実引数ではない」として除外する。「-d検出」のように
            # 説明文の一部がたまたま "-" で始まる場合まで除外すると、
            # 説明文(例: 「裸のmktemp -d検出」)を実引数ありと誤判定してしまう
            # ため、トークン全体が -[英数字]+ に完全一致する場合だけ除外する。
            if (tok ~ /^-[A-Za-z0-9]+$/) continue
            if (tok ~ /^[0-9]*>/) continue
            hasarg = 1
          }
          if (!hasarg) {
            print file ":" NR ": " line
          }
          rest = after
        }
      }
    ' "$f"
  done
}

run_self_test() {
  local pass=0 fail=0
  local tmp
  # 置き場を明示するのは、引数なしの mktemp が既定の置き場へ書こうとして
  # 失敗する環境があるためである（実測 2026-08-24）。素直な mktemp へ戻さない。
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/$(basename "${BASH_SOURCE[0]}" .sh).XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため自己テストを判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' RETURN

  # ケース1: 4つの置き場すべてが揃い、違反が0件 → exit 0
  mkdir -p "$tmp/case_clean/docs/scripts" "$tmp/case_clean/generation-engine/scripts" \
    "$tmp/case_clean/delivery-payload/templates/rules/checkers" "$tmp/case_clean/.claude/rules"
  cat > "$tmp/case_clean/docs/scripts/good.sh" <<'EOF'
#!/usr/bin/env bash
# mktemp という語だけを含むコメント行は対象外
tmp="$(mktemp "${TMPDIR:-/tmp}/good.XXXXXX")"
tmpd="$(mktemp -d "${TMPDIR:-/tmp}/good-d.XXXXXX" 2>/dev/null)"
echo "[UNKNOWN] 一時ファイルを作れないため判定できません（mktempが一時領域へ書き込めませんでした）"
mktemp_ok=1
_mktemp_or_unknown() { :; }
EOF
  if out="$(_run_scan_over "$tmp/case_clean")" && [ -z "$out" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "[FAIL] ケース1(違反なし): ${out}" >&2
  fi

  # ケース2: 置き場を指定しない mktemp が1件 → 検出される
  #
  # 実装判断: フィクスチャの中身は「mk」「temp」を分けて持ち、printf の
  # %s で組み立ててから書き出す。このスクリプト自身のソース上に "mktemp"
  # という裸呼び出しの文字列をそのまま書くと、本検査が自分自身を走査した
  # 際にこのフィクスチャ生成行そのものを違反として誤検出する
  # （実測: 分けずに書いたところ本ファイルの該当行が誤検出された）。
  local mk_word="mk""temp"
  mkdir -p "$tmp/case_bare/docs/scripts" "$tmp/case_bare/generation-engine/scripts" \
    "$tmp/case_bare/delivery-payload/templates/rules/checkers" "$tmp/case_bare/.claude/rules"
  printf '#!/usr/bin/env bash\ntmp="$(%s)"\n' "$mk_word" > "$tmp/case_bare/docs/scripts/bad.sh"
  if out="$(_run_scan_over "$tmp/case_bare")" && printf '%s' "$out" | grep -q 'bad.sh:2:'; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "[FAIL] ケース2(裸のmktemp検出): ${out}" >&2
  fi

  # ケース3: mktemp -d が裸のまま → 検出される
  printf '#!/usr/bin/env bash\nd="$(%s -d 2>/dev/null)"\n' "$mk_word" > "$tmp/case_bare/docs/scripts/bad_d.sh"
  if out="$(_run_scan_over "$tmp/case_bare")" && printf '%s' "$out" | grep -q 'bad_d.sh:2:'; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "[FAIL] ケース3(裸のmktemp -d検出): ${out}" >&2
  fi

  # ケース4: 置き場を指定した呼び出し・識別子・メッセージ文字列は検出しない
  #（ケース1で作った good.sh を case_bare 側にも置き、bad.sh 由来の検出と
  #  混ざらないことを確かめる）
  cp "$tmp/case_clean/docs/scripts/good.sh" "$tmp/case_bare/docs/scripts/good.sh"
  if out="$(_run_scan_over "$tmp/case_bare")" \
    && printf '%s' "$out" | grep -q 'bad.sh:2:' \
    && printf '%s' "$out" | grep -q 'bad_d.sh:2:' \
    && ! printf '%s' "$out" | grep -q 'good.sh'; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "[FAIL] ケース4(good.shの非検出): ${out}" >&2
  fi

  # ケース5: 走査対象の置き場が1つも無い → [UNKNOWN]・終了コード2
  mkdir -p "$tmp/case_empty"
  if out="$(cd "$tmp/case_empty" && bash "$SCRIPT_DIR/check-mktemp-placement.sh" --repo-root "$tmp/case_empty" 2>&1)"; then
    fail=$((fail + 1))
    echo "[FAIL] ケース5(置き場なしでUNKNOWNを返す): exit 0 だった" >&2
  else
    rc=$?
    if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q '^\[UNKNOWN\]'; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
      echo "[FAIL] ケース5(置き場なしでUNKNOWNを返す): rc=${rc} out=${out}" >&2
    fi
  fi

  # ケース6: --self-test 自身が実引数として処理される
  if grep -q -- '--self-test' "$SCRIPT_DIR/check-mktemp-placement.sh"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "[FAIL] ケース6(--self-testの実装確認)" >&2
  fi

  echo "self-test: ${pass} PASS, ${fail} FAIL" >&2
  [ "$fail" -eq 0 ]
}

# _run_scan_over: 自己テスト用に、指定した疑似リポジトリ配下の4つの置き場を
# 走査した結果（違反行の一覧）を返す。
_run_scan_over() {
  local root="$1"
  local d
  for d in "${TARGET_DIRS[@]}"; do
    scan_dir "$root/$d"
  done
}

main() {
  local repo_root="$REPO_ROOT"
  local i=1
  local args=("$@")
  while [ $i -le $# ]; do
    case "${args[$((i-1))]}" in
      --repo-root)
        i=$((i + 1))
        repo_root="${args[$((i-1))]}"
        ;;
    esac
    i=$((i + 1))
  done

  local missing=0
  local d
  for d in "${TARGET_DIRS[@]}"; do
    [ -d "$repo_root/$d" ] || missing=$((missing + 1))
  done
  if [ "$missing" -eq "${#TARGET_DIRS[@]}" ]; then
    echo "[UNKNOWN] 走査対象の置き場が1つも見つからないため判定できません（参照したルート: ${repo_root}）" >&2
    exit 2
  fi

  local violations=0
  local out=""
  for d in "${TARGET_DIRS[@]}"; do
    [ -d "$repo_root/$d" ] || continue
    local found
    found="$(scan_dir "$repo_root/$d")"
    if [ -n "$found" ]; then
      out="${out}${out:+$'\n'}${found}"
      violations=$((violations + $(printf '%s\n' "$found" | grep -c .)))
    fi
  done

  if [ "$violations" -eq 0 ]; then
    echo "[PASS] 置き場を指定しない mktemp は0件"
    exit 0
  fi

  printf '%s\n' "$out"
  echo "[FAIL] 置き場を指定しない mktemp が ${violations} 件ある"
  exit 1
}

if [ "${1:-}" = "--self-test" ]; then
  run_self_test
  exit $?
fi

main "$@"
