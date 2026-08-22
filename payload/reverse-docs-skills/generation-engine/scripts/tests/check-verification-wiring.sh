#!/usr/bin/env bash
# check-verification-wiring.sh — 検査の配線漏れを検出する
#
# 目的:
#   第1層の集約（generation-engine/scripts/verification/run-layer-machine-checks.sh）は
#   対象を動的に集める。当初は --self-test を持つ .sh だけを集めていたため、
#   Node.js で書かれた検査が一度も実行されない状態が2週間以上続いた実績が
#   ある。本スクリプトは、検査として実行できるファイルがすべて集約の対象に
#   含まれているかを機械的に検査し、同種の配線漏れを再発直後に検知する。
#
# 使い方:
#   check-verification-wiring.sh [<リポジトリルート>]
#   check-verification-wiring.sh --self-test
#
# 判定:
#   検査1（不合格なら exit 1）:
#     母集合は「集約の実際の --list 出力」と「自前列挙（generation-engine/scripts/ 配下で
#     .sh が --self-test を引数として処理するもの、および tests/ 配下の
#     test-*.cjs・test-*.mjs）」の和集合とする。2026-08-19 まで母集合を
#     自前列挙のみで作っていたため、集約の収集条件（list_targets）が名前だけで
#     test-*.sh を拾う経路や checkers ディレクトリの走査を追加しても、
#     検査1の母集合はそれを知らずに乖離した（母集合125件・集約160件）。
#     `run-layer-machine-checks.sh --list` を呼んで得た結果をそのまま母集合に
#     取り込むことで、集約側の収集条件が変わっても検査1の母集合が自動的に
#     追従する。自前列挙は「listed に無い、集約から漏れている検査可能ファイル」を
#     引き続き検出するために和集合へ残す。
#     node_modules 配下・.venv 配下・run-layer-machine-checks.sh 自身は除外する。
#
#   検査2（不合格にしない。警告として列挙するのみ）:
#     generation-engine/scripts/ 配下の check-*.sh / validate-*.sh / test-*.sh
#     （*.test.sh を除く。node_modules・.venv 配下も除く）のうち、
#     --self-test を持たないものを件数とともに列挙する（WARN）。
#     ただし次の2条件のいずれかに当てはまるファイルは、実行そのものが判定である
#     独立した検査（またはその重複）とみなし、WARN からは除外する。
#       条件1: ファイル内に自己宣言コメント（「集約の対象外」）
#              を持つもの
#       条件2: generation-engine/scripts/ 配下の他ファイルから
#              `<このファイル名>" --self-test` の形（引数として --self-test を
#              渡して呼ばれる形）で参照されているもの
#     この2条件のいずれかで WARN から外れたファイルが、実際には集約の
#     --list に含まれている場合は、目印が実態と食い違っている可能性があるため
#     別枠の警告（WARN2）として件数とともに報せる（既存の WARN の件数には
#     含めない）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

# 検査1で使う: 「検査として実行できるファイル」を絶対パス・ソート済み・
# 重複なしで列挙する。引数: repo（リポジトリルート）
list_checkable_files() {
  local repo="$1" dir
  dir="$repo/generation-engine/scripts"
  [ -d "$dir" ] || return 0
  {
    grep -rlE --include='*.sh' -e '--self-test\)' -e '= "--self-test"' "$dir" 2>/dev/null
    find "$dir/tests" \( -name 'test-*.cjs' -o -name 'test-*.mjs' \) -type f 2>/dev/null
  } | grep -vE '/node_modules/|/\.venv/' | while IFS= read -r f; do
    [ -z "$f" ] && continue
    local abs
    abs="$(cd "$(dirname "$f")" 2>/dev/null && pwd)/$(basename "$f")"
    [ -z "$abs" ] && continue
    printf '%s\n' "$abs"
  done | sort -u
}

# 集約の --list 出力を絶対パスへ変換して返す。集約が無ければ空を返す。
# 検査1・検査2の双方が、この関数の戻り値を「集約が実際に何を拾っているか」の
# 唯一の情報源として使う。ここを経由せず自前で --list を呼び直す・自前の
# 列挙で代用することを禁じる（2026-08-19 の乖離の再発防止）。
get_listed_abs() {
  local repo="$1" agg
  agg="$repo/generation-engine/scripts/verification/run-layer-machine-checks.sh"
  [ -f "$agg" ] || return 0
  bash "$agg" --list 2>/dev/null | while IFS= read -r r; do
    [ -z "$r" ] && continue
    printf '%s/%s\n' "$repo" "$r"
  done
}

# 集約一覧に対象の絶対パスが1行として含まれるかを返す。
# set -o pipefail 下で `printf | grep -q` を使うと、grep が一致後に早期終了した際の
# printf の SIGPIPE（終了コード141）をパイプ全体の失敗と誤認するため、標準入力は
# here-string で渡す。対象179本で、実際には一覧にある4本を未掲載と誤判定した実測に
# 基づく。部分一致による別パスの誤認も避けるため、1行完全一致で判定する。
listed_contains() {
  local listed="$1" target="$2"
  grep -Fxq "$target" <<< "$listed"
}

# 検査1本体。引数: repo（リポジトリルート）。戻り値: 不合格なら1。
#
# 母集合（checkable）は「集約の実際の --list 出力（listed）」と「自前列挙
# （self_built）」の和集合とする。listed をそのまま母集合に採る（自前列挙を
# 母集合の唯一の情報源にしない）ことで、集約側の収集条件が広がっても検査の
# 母集合が自動的に追従する。self_built を和集合に残すのは、self_built にしか
# 現れない検査可能ファイル（collectできる形なのに集約からは漏れているもの）を
# 引き続き検出するためであり、これを消すと「配線漏れの検出」という検査1の
# 本来の役目が失われる。
run_check1() {
  local repo="$1" agg
  agg="$repo/generation-engine/scripts/verification/run-layer-machine-checks.sh"
  if [ ! -f "$agg" ]; then
    echo "SKIP: 集約スクリプトが見つからない: $agg"
    return 0
  fi
  local agg_abs
  agg_abs="$(cd "$(dirname "$agg")" && pwd)/$(basename "$agg")"

  local self_built listed checkable missing=0 total=0 f rel
  self_built="$(list_checkable_files "$repo" | grep -vF "$agg_abs" || true)"
  listed="$(get_listed_abs "$repo")"
  checkable="$(printf '%s\n%s\n' "$listed" "$self_built" | grep -v '^$' | sort -u)"

  while IFS= read -r f; do
    [ -z "$f" ] && continue
    total=$((total + 1))
    if ! listed_contains "$listed" "$f"; then
      rel="$f"
      case "$rel" in
        "$repo"/*) rel="${rel#"$repo"/}" ;;
      esac
      echo "FAIL: 集約に含まれない検査: $rel"
      missing=$((missing + 1))
    fi
  done <<CHECKABLE
$checkable
CHECKABLE

  if [ "$missing" -eq 0 ]; then
    echo "PASS: 検査1 — 対象 $total 件すべてが集約に含まれる"
    return 0
  fi
  echo "検査1: 集約から漏れた検査 $missing 件"
  return 1
}

# 検査2で使う条件1: ファイルが自己宣言コメントを持つか。
# 引数: f（対象ファイルの絶対パス）
has_exempt_comment() {
  local f="$1"
  # 目印は内容が読める文字列にする。2026-08-19 まで「改善課題 1-138 の横断検収
  # 条件の対象外」という通し番号を含む文字列を探していたが、番号からは何のための
  # 除外かを読み取れず、連番を識別子に使うことを禁じる決まり（meaningful-key-naming）
  # とも食い違っていた。番号へ戻さないこと。
  grep -qF '集約の対象外' "$f" 2>/dev/null
}

# 検査2で使う条件2: 他のスクリプトから `<このファイル名>" --self-test` の形で
# 呼ばれているか。引数: f（対象ファイルの絶対パス）、repo（リポジトリルート）
called_from_other_self_test() {
  local f="$1" repo="$2" base base_re
  base="$(basename "$f")"
  base_re="$(printf '%s' "$base" | sed 's/[.[\*^$]/\\&/g')"
  grep -rlE --include='*.sh' -e "${base_re}[\"']?[[:space:]]+--self-test" "$repo/generation-engine/scripts" 2>/dev/null \
    | grep -vE '/node_modules/|/\.venv/' \
    | while IFS= read -r hit; do
        [ -z "$hit" ] && continue
        local hit_abs
        hit_abs="$(cd "$(dirname "$hit")" 2>/dev/null && pwd)/$(basename "$hit")"
        [ "$hit_abs" = "$f" ] && continue
        printf '%s\n' "$hit_abs"
      done | grep -q .
}

# 検査2本体。引数: repo（リポジトリルート）。常に成功として扱う（警告のみ）。
#
# 目印（条件1・条件2）は「実行そのものが判定である独立した検査（または重複）」
# を警告から外すためのものだが、目印の有無は文字列の一致でしか判定できない。
# 目印を持ちながら、実際には集約の --list に含まれているファイルは、目印が
# 実態と食い違っている可能性がある。これを既存の警告（WARN）とは別枠の
# 警告（WARN2）として報せる。既存の警告の件数を変えないため、既存の判定
# ロジックには手を入れず、目印で continue する直前に分岐を追加するだけに
# とどめる。
run_check2() {
  local repo="$1" dir count=0 count2=0 f rel listed
  dir="$repo/generation-engine/scripts"
  [ -d "$dir" ] || {
    echo "検査2: 自己テストを持たない判定スクリプト 0 件"
    echo "検査2b: 目印を持ちながら集約に含まれるもの 0 件"
    return 0
  }

  listed="$(get_listed_abs "$repo")"

  while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in
      *.test.sh) continue ;;
    esac
    if ! grep -qE -- '--self-test\)|= "--self-test"' "$f" 2>/dev/null; then
      if has_exempt_comment "$f" \
        || called_from_other_self_test "$f" "$repo"; then
        if [ -n "$listed" ] && listed_contains "$listed" "$f"; then
          rel="$f"
          case "$rel" in
            "$repo"/*) rel="${rel#"$repo"/}" ;;
          esac
          echo "WARN2: 目印があるが集約に含まれる: $rel"
          count2=$((count2 + 1))
        fi
        continue
      fi
      rel="$f"
      case "$rel" in
        "$repo"/*) rel="${rel#"$repo"/}" ;;
      esac
      echo "WARN: 自己テストを持たない判定スクリプト: $rel"
      count=$((count + 1))
    fi
  done < <(find "$dir" \( -name 'check-*.sh' -o -name 'validate-*.sh' -o -name 'test-*.sh' \) -type f 2>/dev/null \
    | grep -vE '/node_modules/|/\.venv/' | sort)

  echo "検査2: 自己テストを持たない判定スクリプト $count 件"
  echo "検査2b: 目印を持ちながら集約に含まれるもの $count2 件"
  return 0
}

self_test() {
  local tmp pass=0 fail=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-verification-wiring-self-test.XXXXXX")" || {
    echo "self-test: 一時ディレクトリを作成できない" >&2
    return 1
  }
  tmp="$(cd "$tmp" && pwd)"
  trap 'rm -rf "$tmp"' EXIT

  assert_true() {
    local name="$1" ok="$2"
    if [ "$ok" -eq 0 ]; then
      echo "  [PASS] $name"
      pass=$((pass + 1))
    else
      echo "  [FAIL] $name"
      fail=$((fail + 1))
    fi
  }

  # 一覧がパイプバッファを超える規模でも、先頭行の一致を見落とさないこと。
  # 旧実装の `printf | grep -q` は set -o pipefail 下で grep の早期終了により
  # printf が SIGPIPE（終了コード141）となり、一致済みでも不一致と判定した。
  local listedMembershipFixture
  listedMembershipFixture="$(awk 'BEGIN {
    print "/fixture/target.sh"
    for (i = 1; i <= 10000; i++) print "/fixture/filler-" i ".sh"
  }')"
  listed_contains "$listedMembershipFixture" "/fixture/target.sh"
  assert_true "一覧所属-大きな一覧の先頭一致" $?

  # パスの一部が一致するだけでは、一覧に載っていると判定しないこと。
  listed_contains "/fixture/target.sh.backup" "/fixture/target.sh"
  local partialMembershipRc=$?
  [ "$partialMembershipRc" -ne 0 ] \
    && assert_true "一覧所属-部分一致を拒否" 0 \
    || assert_true "一覧所属-部分一致を拒否" 1

  # ケース1: 現状のリポジトリで検査1が合格すること
  local realRoot
  realRoot="$(cd "$SCRIPT_DIR/../../.." && pwd)"
  run_check1 "$realRoot" >/dev/null 2>&1
  assert_true "検査1-現状リポジトリで合格" $?

  # ケース2: 集約の対象から外れたファイルを一時ディレクトリに作ると
  # 検査1が不合格になること（集約側を「何も列挙しない」スタブにして
  # 配線漏れの状態を再現する）
  local repoA="$tmp/repoA"
  mkdir -p "$repoA/generation-engine/scripts/verification"
  cat > "$repoA/generation-engine/scripts/verification/run-layer-machine-checks.sh" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--list" ]; then
  # 意図的に何も列挙しない（配線漏れの状態を模す）
  exit 0
fi
exit 0
EOS
  chmod +x "$repoA/generation-engine/scripts/verification/run-layer-machine-checks.sh"

  cat > "$repoA/generation-engine/scripts/orphan-check.sh" <<'EOS'
#!/usr/bin/env bash
case "${1:-}" in
  --self-test)
    echo "  [PASS] orphan-case"
    exit 0
    ;;
esac
exit 0
EOS
  chmod +x "$repoA/generation-engine/scripts/orphan-check.sh"

  run_check1 "$repoA" >/dev/null 2>&1
  local rcA=$?
  [ "$rcA" -ne 0 ] && assert_true "検査1-配線漏れを検出" 0 || assert_true "検査1-配線漏れを検出" 1

  # 対照ケース: 集約が正しく列挙していれば合格すること
  local repoB="$tmp/repoB"
  mkdir -p "$repoB/generation-engine/scripts/verification"
  cp "$repoA/generation-engine/scripts/orphan-check.sh" "$repoB/generation-engine/scripts/orphan-check.sh"
  cat > "$repoB/generation-engine/scripts/verification/run-layer-machine-checks.sh" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--list" ]; then
  echo "generation-engine/scripts/orphan-check.sh"
  exit 0
fi
exit 0
EOS
  chmod +x "$repoB/generation-engine/scripts/verification/run-layer-machine-checks.sh"
  run_check1 "$repoB" >/dev/null 2>&1
  assert_true "検査1-集約に含まれていれば合格" $?

  # ケース3: 検査2の警告が件数とともに出ること
  local repoC="$tmp/repoC"
  mkdir -p "$repoC/generation-engine/scripts"
  cat > "$repoC/generation-engine/scripts/check-no-self-test.sh" <<'EOS'
#!/usr/bin/env bash
echo "no self test here"
exit 0
EOS
  chmod +x "$repoC/generation-engine/scripts/check-no-self-test.sh"
  local outC
  outC="$(run_check2 "$repoC")"
  if printf '%s\n' "$outC" | grep -q 'WARN' \
    && printf '%s\n' "$outC" | grep -qE '検査2: 自己テストを持たない判定スクリプト [0-9]+ 件'; then
    assert_true "検査2-警告と件数の出力" 0
  else
    assert_true "検査2-警告と件数の出力" 1
  fi

  # ケース4: 検査2の除外条件1（自己宣言コメント）が働くこと
  local repoD="$tmp/repoD"
  mkdir -p "$repoD/generation-engine/scripts/tests"
  cat > "$repoD/generation-engine/scripts/tests/test-exempt-by-comment.sh" <<'EOS'
#!/usr/bin/env bash
# 集約の対象外: これはテストのfixtureである。
set -euo pipefail
echo "no self test here"
EOS
  chmod +x "$repoD/generation-engine/scripts/tests/test-exempt-by-comment.sh"
  local outD
  outD="$(run_check2 "$repoD")"
  if ! printf '%s\n' "$outD" | grep -qF 'test-exempt-by-comment.sh' \
    && printf '%s\n' "$outD" | grep -qE '検査2: 自己テストを持たない判定スクリプト 0 件'; then
    assert_true "検査2-除外条件1（自己宣言コメント）で警告から外れる" 0
  else
    assert_true "検査2-除外条件1（自己宣言コメント）で警告から外れる" 1
  fi

  # ケース5: 検査2の除外条件2（他スクリプトの --self-test から呼ばれる）が働くこと
  local repoE="$tmp/repoE"
  mkdir -p "$repoE/generation-engine/scripts/tests"
  cat > "$repoE/generation-engine/scripts/tests/test-called-by-caller.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
echo "no self test here"
EOS
  chmod +x "$repoE/generation-engine/scripts/tests/test-called-by-caller.sh"
  cat > "$repoE/generation-engine/scripts/caller.sh" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  bash "$(dirname "$0")/tests/test-called-by-caller.sh" --self-test
  exit $?
fi
exit 0
EOS
  chmod +x "$repoE/generation-engine/scripts/caller.sh"
  local outE
  outE="$(run_check2 "$repoE")"
  if ! printf '%s\n' "$outE" | grep -qF 'test-called-by-caller.sh' \
    && printf '%s\n' "$outE" | grep -qE '検査2: 自己テストを持たない判定スクリプト 0 件'; then
    assert_true "検査2-除外条件2（他スクリプトの--self-testから呼ばれる）で警告から外れる" 0
  else
    assert_true "検査2-除外条件2（他スクリプトの--self-testから呼ばれる）で警告から外れる" 1
  fi

  # ケース6（収集条件-集約と一致）: 自前列挙（list_checkable_files）の
  # 正規表現には一致しないが、集約が名前だけで拾う想定のファイルがあっても、
  # 検査1が報せる母集合の件数が集約の --list 件数と一致すること。
  # 2026-08-19 まではここが自前列挙のみを母集合としていたため、この種の
  # ファイルは検査1の視野の外にあり、母集合の件数が集約より少なく出ていた。
  local repoF="$tmp/repoF"
  mkdir -p "$repoF/generation-engine/scripts/verification"
  cat > "$repoF/generation-engine/scripts/verification/run-layer-machine-checks.sh" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--list" ]; then
  echo "generation-engine/scripts/tests/test-by-name-only.sh"
  exit 0
fi
exit 0
EOS
  chmod +x "$repoF/generation-engine/scripts/verification/run-layer-machine-checks.sh"
  mkdir -p "$repoF/generation-engine/scripts/tests"
  cat > "$repoF/generation-engine/scripts/tests/test-by-name-only.sh" <<'EOS'
#!/usr/bin/env bash
# --self-test の case 分岐を持たず、名前（test-*.sh）だけで集約に拾われる
# 想定の fixture。list_checkable_files の正規表現（--self-test) / = "--self-test"）
# には一致しない。
echo "実行 1 件"
exit 0
EOS
  chmod +x "$repoF/generation-engine/scripts/tests/test-by-name-only.sh"

  local outF1 totalF listedCountF
  outF1="$(run_check1 "$repoF" 2>&1)"
  totalF="$(printf '%s\n' "$outF1" | sed -n 's/.*対象 \([0-9][0-9]*\) 件.*/\1/p' | head -1)"
  listedCountF="$(bash "$repoF/generation-engine/scripts/verification/run-layer-machine-checks.sh" --list 2>/dev/null | grep -c .)"
  if [ -n "$totalF" ] && [ "$totalF" = "$listedCountF" ] && [ "$totalF" = "1" ]; then
    assert_true "収集条件-集約と一致" 0
  else
    assert_true "収集条件-集約と一致" 1
  fi

  # ケース7: 検査2の目印を持ちながら実際には集約に含まれるファイルが、
  # 既存の警告（WARN）とは別枠の警告（WARN2）として報せられること。
  local repoG="$tmp/repoG"
  mkdir -p "$repoG/generation-engine/scripts/verification" "$repoG/generation-engine/scripts/tests"
  cat > "$repoG/generation-engine/scripts/verification/run-layer-machine-checks.sh" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--list" ]; then
  echo "generation-engine/scripts/tests/test-exempt-but-listed.sh"
  exit 0
fi
exit 0
EOS
  chmod +x "$repoG/generation-engine/scripts/verification/run-layer-machine-checks.sh"
  cat > "$repoG/generation-engine/scripts/tests/test-exempt-but-listed.sh" <<'EOS'
#!/usr/bin/env bash
# 集約の対象外: これはテストのfixtureである。実際には集約の --list に含まれる。
set -euo pipefail
echo "no self test here"
EOS
  chmod +x "$repoG/generation-engine/scripts/tests/test-exempt-but-listed.sh"
  local outG
  outG="$(run_check2 "$repoG")"
  if printf '%s\n' "$outG" | grep -qF 'WARN2: 目印があるが集約に含まれる' \
    && printf '%s\n' "$outG" | grep -qE '検査2b: 目印を持ちながら集約に含まれるもの 1 件' \
    && printf '%s\n' "$outG" | grep -qE '検査2: 自己テストを持たない判定スクリプト 0 件'; then
    assert_true "検査2-目印付きだが集約に含まれると別警告" 0
  else
    assert_true "検査2-目印付きだが集約に含まれると別警告" 1
  fi

  rm -rf "$tmp"
  trap - EXIT
  echo "実行 $((pass + fail)) 件 / 成功 $pass 件 / 失敗 $fail 件"
  [ "$fail" -eq 0 ]
}

usage() {
  cat <<'EOS'
使い方: check-verification-wiring.sh [<リポジトリルート>]
        check-verification-wiring.sh --self-test
EOS
}

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
  fi

  local root="${1:-}"
  if [ -z "$root" ]; then
    root="$(cd "$SCRIPT_DIR/../../.." && pwd)"
  fi

  local rc=0
  run_check1 "$root" || rc=1
  run_check2 "$root"
  exit "$rc"
}

main "$@"
