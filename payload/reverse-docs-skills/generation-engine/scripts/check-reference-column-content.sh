#!/usr/bin/env bash
# 参照先列の内容検査
#
# 目的:
#   テンプレート（および生成された設計書）の表が持つ「参照先」列に、挙動の記述
#   （「〜する」「〜を送出する」等）が混入していないかを検査する。挙動の記述は
#   本文の該当節へ、実装の位置は根拠台帳へ書くべきもので、参照先の列に書くと
#   文書内参照ではなくなる（1-234）。参照先は上位の設計書の節・自書の節・
#   関数単位の契約への参照のいずれかであり、動詞で終わる文にはならない。
#
# 使い方:
#   check-reference-column-content.sh <対象ファイルまたはディレクトリ>...
#   check-reference-column-content.sh --self-test
#
# 判定:
#   ヘッダ行に「参照先」を含む表の、そのデータ行の同じ列位置の値が、動詞で終わる文
#   （「する」「した」「される」「させる」「出す」「返す」で終わる）であれば不合格
#   とする。プレースホルダ（`<...>`）は値の実体を持たないため対象外とする。
#
# 実装判断: 表の列位置検出と日本語文字列の一致判定を bash/awk で書かず node -e に
# 委譲する。実測（このリポジトリの環境）で、macOS 標準の awk（One True Awk 系、
# 20200816版）が多バイト文字列同士の == 比較で誤って真を返す不具合を確認した
# （「接続が未定義時に例外を送出する」 == 「参照先」 が真になる）。gawk は導入されて
# いない。node の文字列比較はUTF-8を正しく扱うため、これを避けるにはbashの文字列
# 比較のみで組むか、node等の別処理へ委譲する必要があった。
set -uo pipefail

scan_file() {
  local f="$1"
  node -e '
    const fs = require("fs");
    const path = process.argv[1];
    const text = fs.readFileSync(path, "utf8");
    const lines = text.split("\n");
    const behaviorRe = /(する|した|される|させる|出す|返す)。?[`'"'"']?$/;
    let refCol = -1;
    let failed = false;
    lines.forEach((line, idx) => {
      const lineNo = idx + 1;
      if (/^\s*$/.test(line)) { refCol = -1; return; }
      if (!/^\s*\|/.test(line)) { refCol = -1; return; }
      const cells = line.split("|").map((c) => c.trim());
      // セパレータ行（|---|---|）は無視する
      if (cells.every((c) => c === "" || /^:?-+:?$/.test(c))) return;
      const foundIdx = cells.findIndex((c) => c === "参照先");
      if (foundIdx >= 0) { refCol = foundIdx; return; }
      if (refCol >= 0 && refCol < cells.length) {
        const val = cells[refCol];
        if (val === "" || /^`<.*>`$/.test(val)) return;
        if (behaviorRe.test(val)) {
          console.log(`FAIL ${path}:${lineNo} 参照先列に挙動の記述が混入: ${val}`);
          failed = true;
        }
      }
    });
    process.exit(failed ? 1 : 0);
  ' "$f"
}

run_check() {
  local rc=0 files=0 f target
  for target in "$@"; do
    if [ -d "$target" ]; then
      while IFS= read -r f; do
        files=$((files + 1))
        scan_file "$f" || rc=1
      done < <(find "$target" -type f -name '*.md' 2>/dev/null | sort)
    elif [ -f "$target" ]; then
      files=$((files + 1))
      scan_file "$target" || rc=1
    fi
  done
  if [ "$files" -eq 0 ]; then
    echo "SKIP: 対象の Markdown がない"
    return 0
  fi
  if [ "$rc" -eq 0 ]; then
    echo "CLEAN: $files 件の文書の参照先列に挙動の記述はない"
  fi
  return "$rc"
}

self_test() {
  local tmp pass=0 fail=0 got
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-reference-column-content-self-test.XXXXXX")" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリを作成できないため判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）"
    return 2
  fi

  assert() {
    local name="$1" want="$2" actual="$3"
    if [ "$want" = "$actual" ]; then
      echo "  [PASS] $name"
      pass=$((pass + 1))
    else
      echo "  [FAIL] ${name}（期待 ${want}・実際 ${actual}）"
      fail=$((fail + 1))
    fi
  }

  printf '| 対象 | 参照先 |\n|---|---|\n| a | %s |\n' '§7.1' > "$tmp/a.md"
  run_check "$tmp/a.md" >/dev/null 2>&1; got=$?
  assert "文書内参照（節番号）は合格" 0 "$got"

  printf '| 対象 | 参照先 |\n|---|---|\n| a | %s |\n' '`<実測: 参照先>`' > "$tmp/a.md"
  run_check "$tmp/a.md" >/dev/null 2>&1; got=$?
  assert "プレースホルダは対象外" 0 "$got"

  printf '| 対象 | 参照先 |\n|---|---|\n| a | %s |\n' '接続が未定義時に例外を送出する' > "$tmp/a.md"
  run_check "$tmp/a.md" >/dev/null 2>&1; got=$?
  assert "挙動の記述（送出する）を検出" 1 "$got"

  printf '| 対象 | 参照先 |\n|---|---|\n| a | %s |\n' '設定を変更した' > "$tmp/a.md"
  run_check "$tmp/a.md" >/dev/null 2>&1; got=$?
  assert "挙動の記述（変更した）を検出" 1 "$got"

  printf '| 対象 | 参照先 |\n|---|---|\n| a | %s |\n' '§13.4' > "$tmp/a.md"
  run_check "$tmp/a.md" >/dev/null 2>&1; got=$?
  assert "文書内参照（別節）は合格" 0 "$got"

  printf '| 対象 | 他列 |\n|---|---|\n| a | %s |\n' '接続が未定義時に例外を送出する' > "$tmp/a.md"
  run_check "$tmp/a.md" >/dev/null 2>&1; got=$?
  assert "参照先列を持たない表は対象外" 0 "$got"

  printf '| 対象 | 参照先 |\n|---|---|\n\n本文中の説明で使うと判定しない。\n' > "$tmp/a.md"
  run_check "$tmp/a.md" >/dev/null 2>&1; got=$?
  assert "空行の後は表の外として扱う" 0 "$got"

  rm -rf "$tmp"
  echo "self-test: $pass PASS, $fail FAIL"
  [ "$fail" -eq 0 ]
}

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi
  if [ "$#" -eq 0 ]; then
    echo "使い方: check-reference-column-content.sh <対象ファイルまたはディレクトリ>... | --self-test" >&2
    exit 2
  fi
  run_check "$@"
  exit $?
}

main "$@"
