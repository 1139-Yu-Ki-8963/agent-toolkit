#!/usr/bin/env bash
# remove-table-column.sh — 設計書の表から列を除く（改善課題1-282）
#
# 使い方:
#   remove-table-column.sh <Markdown> <列名> [<列名> ...]        除いた結果を標準出力へ出す
#   remove-table-column.sh --in-place <Markdown> <列名> [...]    ファイルを書き換える
#   remove-table-column.sh --self-test
#
# 判定:
#   - 見出し行に指定の列名を持つ表だけを対象にし、その列を見出し行・区切り行・データ行から除く
#   - 除いた列の内容を残る列のセルへ混入させない。表を箇条書きへ変換しない。対象でない行は変えない
#   - 除いた結果、表が成立しない（残る列が1つも無い・データ行のセル数が見出しと合わない）場合は
#     何も書かずに理由を標準エラーへ出し、終了コード1で止める
#   - 走査できない（ファイルが無い等）場合は [UNKNOWN]・終了コード2
#
# 実装判断: 表の読み書きは perl で行う。macOS 標準の awk は多バイト文字列の比較を誤ることがあり、
#   日本語の列名で列位置を決める処理に使えない。
set -u
run() {
  local in_place=0
  if [ "${1:-}" = "--in-place" ]; then in_place=1; shift; fi
  local file="${1:-}"; shift || true
  [ -n "$file" ] && [ -f "$file" ] || { echo "[UNKNOWN] 対象ファイルが無いため処理できません: ${file:-（未指定）}" >&2; return 2; }
  [ "$#" -ge 1 ] || { echo "usage: remove-table-column.sh [--in-place] <Markdown> <列名> [...]" >&2; return 2; }
  local out; out="$(perl -CSDA -Mutf8 -e '
    use strict; use warnings;
    my ($file, @names) = @ARGV; my %drop = map { $_ => 1 } @names;
    open my $fh, "<", $file or die; my @lines = <$fh>; close $fh;
    my @out; my $i = 0; my $errors = 0;
    my $split = sub { my $l = shift; $l =~ s/\r?\n$//; $l =~ s/^\s*\|//; $l =~ s/\|\s*$//; return [ map { s/^\s+|\s+$//gr } split /\|/, $l, -1 ] };
    while ($i < @lines) {
      my $l = $lines[$i];
      my $is_header = $l =~ /^\s*\|/ && $i + 1 < @lines && $lines[$i+1] =~ /^\s*\|\s*:?-{3,}/;
      if (!$is_header) { push @out, $l; $i++; next }
      my $cells = $split->($l);
      my @keep = grep { !$drop{$cells->[$_]} } 0..$#$cells;
      if (@keep == @$cells) { push @out, $l; $i++; next }   # 対象の列を持たない表
      if (!@keep) { print STDERR "ERROR: $file:" . ($i+1) . ": 列を除くと表に列が残りません（表として成立しないため止めました）\n"; $errors++; push @out, $l; $i++; next }
      my $n = scalar @$cells;
      my $emit = sub { my $c = shift; "| " . join(" | ", map { $c->[$_] } @keep) . " |\n" };
      push @out, $emit->($cells); $i++;
      my $sep = $split->($lines[$i]); push @out, $emit->($sep); $i++;
      while ($i < @lines && $lines[$i] =~ /^\s*\|/) {
        my $row = $split->($lines[$i]);
        if (@$row != $n) { print STDERR "ERROR: $file:" . ($i+1) . ": データ行のセル数（" . scalar(@$row) . "）が見出し（$n）と合いません（列を除くと表が成立しないため止めました）\n"; $errors++; push @out, $lines[$i]; $i++; next }
        push @out, $emit->($row); $i++;
      }
    }
    exit 1 if $errors;
    print @out;
  ' "$file" "$@")"; local rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  if [ "$in_place" -eq 1 ]; then printf '%s\n' "$out" > "$file"; else printf '%s\n' "$out"; fi
}
self_test() {
  local tmp rc=0
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/remove-table-column.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktemp が一時領域へ書き込めませんでした）"; return 2; fi
  printf '# 表\n\n| 項目 | 型 | 根拠 | 出典参照 | 説明 |\n|---|---|---|---|---|\n| id | 数値 | src/a.pm:12 | §3 | 識別子です |\n| name | 文字列 | src/a.pm:20 | §4 | 名前です |\n\n- 箇条書きは変えない\n\n| 別の表 | 値 |\n|---|---|\n| x | 1 |\n' > "$tmp/a.md"
  local out; out="$(run "$tmp/a.md" 根拠 出典参照)"; local r=$?
  if [ "$r" -eq 0 ] && [ "$(printf '%s\n' "$out" | grep -c '^| id | 数値 | 識別子です |$')" -eq 1 ] && [ "$(printf '%s\n' "$out" | grep -c '^| 項目 | 型 | 説明 |$')" -eq 1 ] && ! printf '%s' "$out" | grep -q 'src/a.pm'; then
    echo "  [PASS] 検収1: 残る列の数と各セルの内容が期待どおり（除いた列の文言は残らない）"
  else echo "  [FAIL] 検収1: 出力が期待と違う"; printf '%s\n' "$out"; rc=1; fi
  if [ "$(printf '%s\n' "$out" | grep -c '^|')" -eq 7 ] && printf '%s' "$out" | grep -q '^| 別の表 | 値 |$' && printf '%s' "$out" | grep -q '^- 箇条書きは変えない$'; then
    echo "  [PASS] 検収2: 表を箇条書きへ変換せず、対象でない表と行は変えない"
  else echo "  [FAIL] 検収2: 表の行数または対象外の行が変わった"; rc=1; fi
  printf '| 根拠 |\n|---|\n| src/a.pm:1 |\n' > "$tmp/b.md"
  if run "$tmp/b.md" 根拠 >/dev/null 2>&1; then echo "  [FAIL] 検収3: 表が成立しない入力で終了コード0"; rc=1; else echo "  [PASS] 検収3: 除くと表が成立しない入力で非0で終了する"; fi
  printf '| a | 根拠 |\n|---|---|\n| 1 |\n' > "$tmp/c.md"
  if run "$tmp/c.md" 根拠 >/dev/null 2>&1; then echo "  [FAIL] 検収3b: セル数の合わない行で終了コード0"; rc=1; else echo "  [PASS] 検収3b: セル数の合わない行があれば非0で終了し書き換えない"; fi
  rm -rf "$tmp"; [ "$rc" -eq 0 ] && echo "self-test PASS" || echo "self-test FAIL"; return "$rc"
}
case "${1:-}" in --self-test) self_test ;; *) run "$@" ;; esac
