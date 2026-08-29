#!/usr/bin/env bash
# check-crumb-contrast.sh — 版面のパンくずの文字色と背景色のコントラスト比を確かめる（改善課題1-301）
#
# 使い方: bash docs/scripts/check-crumb-contrast.sh [<tokens.css>]   / --self-test
# 判定: 明るい配色（:root と data-theme="light"）・暗い配色の --muted と --bg の組で
#       WCAG のコントラスト比を計算し、4.5 未満が1件でもあれば終了コード1。
#       パンくず（.pt-crumb）の文字色は delivery-payload/templates/partials/shell.css が var(--muted) と定める。
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOKENS="${1:-$ROOT/delivery-payload/templates/tokens.css}"
run() {
  local tokens="$1"
  [ -f "$tokens" ] || { echo "[UNKNOWN] tokens.css が無いため判定できません: $tokens"; return 2; }
  perl -e '
    use strict; use warnings;
    my $file = shift; open my $fh, "<", $file or die; my $css = do { local $/; <$fh> }; close $fh;
    # ブロックごとに --muted と --bg を拾う（:root / [data-theme=light] / dark）
    my @blocks = $css =~ /([^{}]*\{[^{}]*\})/g;
    my (%pairs);
    for my $b (@blocks) {
      my ($sel) = $b =~ /^\s*([^{]*?)\s*\{/; $sel //= "";
      my ($m) = $b =~ /--muted:\s*(#[0-9A-Fa-f]{6})/; my ($g) = $b =~ /--bg:\s*(#[0-9A-Fa-f]{6})/;
      next unless $m && $g;
      my $label = ($sel =~ /data-theme="dark"\]/ && $sel !~ /:not\(/) ? "dark:$sel" : "light:$sel"; $label =~ s/\s+/ /g;
      $pairs{$label} = [$m, $g];
    }
    die "[UNKNOWN] --muted と --bg の組を1件も読めませんでした\n" unless %pairs;
    sub lum { my $c = shift; $c =~ s/^#//; my @v = map { hex($_)/255 } ($c =~ /(..)(..)(..)/);
      my @l = map { $_ <= 0.03928 ? $_/12.92 : (($_+0.055)/1.055)**2.4 } @v; 0.2126*$l[0]+0.7152*$l[1]+0.0722*$l[2] }
    my $bad = 0;
    for my $k (sort keys %pairs) {
      my ($m, $g) = @{$pairs{$k}}; my ($a, $b) = (lum($m), lum($g));
      my $cr = $a > $b ? ($a+0.05)/($b+0.05) : ($b+0.05)/($a+0.05);
      my $ok = $cr >= 4.5;
      printf "[%s] %s: パンくず %s / 背景 %s → コントラスト比 %.2f\n", ($ok ? "PASS" : "FAIL"), $k, $m, $g, $cr;
      $bad++ unless $ok;
    }
    exit($bad ? 1 : 0);
  ' "$tokens"
}
self_test() {
  local tmp rc=0
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/crumb-contrast.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktemp が一時領域へ書き込めませんでした）"; return 2; fi
  printf ':root { --bg: #F1F4F8; --muted: #657285; }\n' > "$tmp/bad.css"
  printf ':root { --bg: #F1F4F8; --muted: #58657A; }\n:root[data-theme="dark"] { --bg: #0F1217; --muted: #8A96A7; }\n' > "$tmp/good.css"
  if run "$tmp/bad.css" >/dev/null; then echo "  [FAIL] 陽性: 4.43 の組を不合格にしない"; rc=1; else echo "  [PASS] 陽性: 4.5 未満の組を不合格にする"; fi
  if run "$tmp/good.css" >/dev/null; then echo "  [PASS] 陰性: 明るい配色・暗い配色とも 4.5 以上なら合格"; else echo "  [FAIL] 陰性: 基準を満たす組を不合格にした"; rc=1; fi
  if run "$ROOT/delivery-payload/templates/tokens.css" >/dev/null; then echo "  [PASS] 実物: tokens.css の全配色が 4.5 以上"; else echo "  [FAIL] 実物: tokens.css に 4.5 未満の配色がある"; rc=1; fi
  rm -rf "$tmp"; [ "$rc" -eq 0 ] && echo "self-test PASS" || echo "self-test FAIL"; return "$rc"
}
case "${1:-}" in --self-test) self_test ;; *) run "$TOKENS" ;; esac
