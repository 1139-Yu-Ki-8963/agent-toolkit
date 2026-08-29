#!/usr/bin/env perl
# split-implementation-record.pl — 詳細設計書から「現行実装」の節を <種別>実装記録.md へ分ける（改善課題1-288）
#
# 使い方: perl split-implementation-record.pl <詳細設計書.md> [...]
#   同じディレクトリへ <種別>実装記録.md を書き、詳細設計書は仕様の節だけを残して採番し直す。
#   既に実装記録がある（詳細設計書に現行実装の節が無い）場合は何もしない。
#
# 対象と移す節（節番号は分ける前の番号）:
#   API詳細設計書: §6 疑似コード・§7 データアクセス・§8 データ定義・§12 実装契約
#   バッチ／帳票／外部連携詳細設計書・テーブル定義書: §4 疑似コード・§7 データ定義・§8 実装契約
#   節ごとの位置づけの行（**この節の位置づけ: 現行実装…**）を持つ節を移す。
#
# 実装判断: 節番号の参照（§N・§N.M・N.M）は分けた後の番号へ機械的に追従させる。移した節への参照は
#   「<種別>実装記録 §N.M」の形（文書間参照の記法）に、実装記録から仕様の節への参照は
#   「<詳細設計書名> §N.M」の形にする。手で書き換えると417箇所の追従がぶれるためスクリプトに固定する。
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8'; binmode STDERR, ':utf8';
use File::Basename qw(basename dirname);
use Encode qw(decode encode);

for my $file (@ARGV) {
  my $base = basename($file); my $ubase = decode('UTF-8', $base);
  my ($kind_label, $rec_base);
  if    ($ubase eq 'API詳細設計書.md')       { $kind_label = 'API';   $rec_base = 'API実装記録.md' }
  elsif ($ubase eq 'バッチ詳細設計書.md')     { $kind_label = 'バッチ'; $rec_base = 'バッチ実装記録.md' }
  elsif ($ubase eq '帳票詳細設計書.md')       { $kind_label = '帳票';  $rec_base = '帳票実装記録.md' }
  elsif ($ubase eq '外部連携詳細設計書.md')   { $kind_label = '外部連携'; $rec_base = '外部連携実装記録.md' }
  elsif ($ubase eq 'テーブル定義書.md')       { $kind_label = 'テーブル'; $rec_base = 'テーブル実装記録.md' }
  else { print STDERR "SKIP（対象外）: $file\n"; next }
  my $spec_doc = $ubase =~ s/\.md$//r; my $rec_doc = $rec_base =~ s/\.md$//r;
  open my $fh, '<:utf8', $file or die "$file: $!"; my @lines = <$fh>; close $fh;
  # front matter
  my ($fm_end) = (-1);
  if (@lines && $lines[0] =~ /^---\s*$/) { for my $i (1..$#lines) { if ($lines[$i] =~ /^---\s*$/) { $fm_end = $i; last } } }
  my @fm = $fm_end >= 0 ? @lines[0..$fm_end] : ();
  my @body = $fm_end >= 0 ? @lines[$fm_end+1..$#lines] : @lines;
  # 節へ分ける（## §N で始まる範囲）
  my @pre; my @secs; my $cur;
  for my $l (@body) {
    if ($l =~ /^## §(\d+)\s+(.*?)\s*$/) { $cur = { num => $1, title => $2, lines => [] }; push @secs, $cur; next }
    if ($cur) { push @{$cur->{lines}}, $l } else { push @pre, $l }
  }
  my %is_impl;
  for my $s (@secs) { $is_impl{$s->{num}} = 1 if grep { /^\*\*この節の位置づけ: 現行実装/ } @{$s->{lines}} }
  if (!%is_impl) { print STDERR "SKIP（現行実装の節が無い）: $file\n"; next }
  my (@spec, @rec); my (%map_spec, %map_rec); my ($ns, $nr) = (0, 0);
  for my $s (@secs) { if ($is_impl{$s->{num}}) { $nr++; $map_rec{$s->{num}} = $nr; push @rec, $s } else { $ns++; $map_spec{$s->{num}} = $ns; push @spec, $s } }
  # 参照の書き換え
  my $rewrite = sub {
    my ($text, $self) = @_;   # $self: 'spec' or 'rec'
    my ($mine, $other, $other_doc) = $self eq 'spec' ? (\%map_spec, \%map_rec, $rec_doc) : (\%map_rec, \%map_spec, $spec_doc);
    # 見出し
    $text =~ s{^### (\d+)\.(\d+)(\s)}{"### " . (exists $mine->{$1} ? $mine->{$1} : $1) . ".$2$3"}mge;
    # 本文中の §N.M / §N
    $text =~ s{§(\d+)(\.\d+)?(?=[^\d]|$)}{
      my ($n,$m)=($1, defined $2 ? $2 : '');
      exists $mine->{$n} ? "§$mine->{$n}$m" : exists $other->{$n} ? "$other_doc §$other->{$n}$m" : "§$n$m"}ge;
    # 「N.M 題」の形（§無し）は見出し以外では既存の意味が取りにくいため触らない
    $text =~ s/\Q$other_doc\E \Q$other_doc\E /$other_doc /g;
    return $text;
  };
  # 冒頭案内の表の行を振り分け（| 節 | 内容 | 読み手へのお願い | の行のうち §N で始まるもの）
  my (@pre_spec, @pre_rec_rows);
  for my $l (@pre) {
    if ($l =~ /^\|\s*§(\d+)\b/ && $is_impl{$1}) { push @pre_rec_rows, $l; next }
    next if $l =~ /^\*\*この文書の位置づけ\*\*/ || $l =~ /^- (仕様|現行実装|仕様／現行実装)[（:]/;
    push @pre_spec, $l;
  }
  # 詳細設計書（仕様）
  my $spec_text = join('', @fm) . join('', @pre_spec) . join('', map { "## §$_->{num} $_->{title}\n" . join('', @{$_->{lines}}) } @spec);
  $spec_text = $rewrite->($spec_text, 'spec');
  # chapter_map: 実装記録へ移った役割を除く（section の値で判定）
  $spec_text = filter_chapter_map($spec_text, \%map_spec);
  # 実装記録
  my $title_line = (grep { /^# / } @pre)[0] // "# $rec_doc\n";
  my $rec_title = $title_line; $rec_title =~ s/\Q$spec_doc\E\s*$/$rec_doc\n/ or $rec_title =~ s/\s*$/ $rec_doc\n/;
  my $intro = "本書は、この${kind_label}の今の作りをそのまま記録した文書です。作り直す際に引き継がない情報だけを置きます。業務の決まり・外部との契約・満たすべき性質は $spec_doc を参照してください。\n\n";
  my $rec_table = @pre_rec_rows ? "| 節 | 内容 | 読み手へのお願い |\n|---|---|---|\n" . join('', @pre_rec_rows) . "\n" : "";
  my $rec_text = join('', @fm) . $rec_title . "\n" . $intro . $rec_table . join('', map { "## §$_->{num} $_->{title}\n" . join('', @{$_->{lines}}) } @rec);
  $rec_text = $rewrite->($rec_text, 'rec');
  $rec_text = filter_chapter_map($rec_text, \%map_rec);
  # 書き出し
  my $rec_file = dirname($file) . "/" . encode("UTF-8", $rec_base);
  open my $o1, '>:utf8', $file or die; print $o1 $spec_text; close $o1;
  open my $o2, '>:utf8', $rec_file or die; print $o2 $rec_text; close $o2;
  printf "%s: 仕様 %d 節 / 実装記録 %d 節 → %s\n", $file, scalar(@spec), scalar(@rec), $rec_file;
}

# front matter の chapter_map から、この文書に残る節だけを残し、section を新番号へ写す
sub filter_chapter_map {
  my ($text, $map) = @_;
  return $text unless $text =~ /^chapter_map:/m;
  my @out; my $in = 0; my @pending;
  my @l = split /\n/, $text, -1;
  my $flush = sub {
    return unless @pending;
    my $sec = join("\n", @pending);
    if ($sec =~ /^\s+section:\s*(\d+)\s*$/m) { my $n = $1; if (exists $map->{$n}) { $sec =~ s/^(\s+section:\s*)\d+/$1$map->{$n}/m; push @out, $sec } }
    else { push @out, $sec }
    @pending = ();
  };
  for my $x (@l) {
    if ($x =~ /^chapter_map:/) { $in = 1; push @out, $x; next }
    if ($in) {
      if ($x =~ /^  - /) { $flush->(); @pending = ($x); next }
      if ($x =~ /^    /) { push @pending, $x; next }
      $flush->(); $in = 0;
    }
    push @out, $x;
  }
  $flush->();
  return join("\n", @out);
}
