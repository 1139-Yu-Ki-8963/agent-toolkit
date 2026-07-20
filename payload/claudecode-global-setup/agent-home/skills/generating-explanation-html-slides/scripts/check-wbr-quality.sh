#!/usr/bin/env bash
# check-wbr-quality.sh — <wbr> 文節改行の品質検査
# 用途: Phase 4 Step 4-1 からファイルパス引数で直接実行する
# 使い方: bash scripts/check-wbr-quality.sh <HTMLファイルパス>
# hook 登録しない理由: スキルを単体配布する際に settings.json への依存を避けるため
#
# 検証対象: h1〜h3 見出し内の <wbr>（文節改行ヒント）の品質。
#   1. wbr-存在性: 見出しに <wbr> が1つ以上あるか（短い見出し・非日本語見出し・
#      ファイル全体に <wbr> が無い場合は免除）
#   2. wbr-最小チャンク: <wbr> 分割後の各断片（タグ除去後）が2文字以下でないか
#   3. wbr-カタカナ分断: カタカナ3文字以上の連続の途中に <wbr> がないか
#   4. wbr-数値助数詞分断: 数値直後の <wbr> が助数詞1文字を分断していないか
#   (WARN) 過剰密度: 1見出しに <wbr> が4個以上ある場合は警告のみ（block しない）
#
# macOS の BSD grep は -P 非対応のため、マルチバイト対応の正規表現判定は
# すべて perl（-CSD で UTF-8 入出力）に委ねる。タグ除去は sed で行う。
set -u

errors=""
warnings=""

# ---------------------------------------------------------------------------
# extract_headings <file>
#   h1〜h3 の内側 HTML を1見出し1行（内部改行はスペースに正規化）で出力する
# ---------------------------------------------------------------------------
extract_headings() {
  perl -0777 -ne '
    while (/<h[1-3][^>]*>(.*?)<\/h[1-3]>/gs) {
      my $h = $1;
      $h =~ s/\r?\n/ /g;
      print $h, "\n";
    }
  ' "$1"
}

# ---------------------------------------------------------------------------
# has_japanese
#   stdin のテキストにひらがな/カタカナ/漢字が含まれれば exit 0、なければ exit 1
# ---------------------------------------------------------------------------
has_japanese() {
  perl -CSD -e '
    my $s = do { local $/; <STDIN> };
    exit(($s =~ /[\x{3040}-\x{309F}\x{30A0}-\x{30FF}\x{4E00}-\x{9FFF}]/) ? 0 : 1);
  '
}

# ---------------------------------------------------------------------------
# char_len
#   stdin のテキストの文字数（UTF-8 単位）を標準出力に出す
# ---------------------------------------------------------------------------
char_len() {
  perl -CSD -e '
    my $s = do { local $/; <STDIN> };
    print length($s);
  '
}

# ---------------------------------------------------------------------------
# check_min_chunk
#   stdin: 見出し内側 HTML。<wbr> 分割後の各断片（タグ除去後）が2文字以下なら
#   exit 1（違反あり）、問題なければ exit 0
# ---------------------------------------------------------------------------
check_min_chunk() {
  perl -CSD -e '
    my $h = do { local $/; <STDIN> };
    my @chunks = split /<wbr\s*\/?>/i, $h;
    exit 0 if scalar(@chunks) < 2;
    my $bad = 0;
    for my $c (@chunks) {
      (my $plain = $c) =~ s/<[^>]*>//g;
      $bad = 1 if length($plain) <= 2;
    }
    exit($bad ? 1 : 0);
  '
}

# ---------------------------------------------------------------------------
# check_katakana_split
#   stdin: 見出し内側 HTML。カタカナ3文字以上の連続の途中に <wbr> があれば
#   exit 1（違反あり）、なければ exit 0
# ---------------------------------------------------------------------------
check_katakana_split() {
  perl -CSD -e '
    my $h = do { local $/; <STDIN> };
    $h =~ s/<wbr\s*\/?>/\x02/gi;
    $h =~ s/<[^>]*>//g;
    my @positions;
    my $plain = "";
    for my $c (split //, $h) {
      if ($c eq "\x02") { push @positions, length($plain); }
      else { $plain .= $c; }
    }
    my $bad = 0;
    while ($plain =~ /[\x{30A0}-\x{30FF}]{3,}/g) {
      my $start = $-[0];
      my $end = $+[0];
      for my $p (@positions) {
        $bad = 1 if $p > $start && $p < $end;
      }
    }
    exit($bad ? 1 : 0);
  '
}

# ---------------------------------------------------------------------------
# check_counter_split
#   stdin: 見出し内側 HTML。数値直後の <wbr> + ひらがな/カタカナ/漢字1文字の
#   パターンがあれば exit 1（違反あり）、なければ exit 0
# ---------------------------------------------------------------------------
check_counter_split() {
  perl -CSD -e '
    my $h = do { local $/; <STDIN> };
    $h =~ s/<(?!wbr\b)[^>]*>//gi;
    my $bad = ($h =~ /[0-9\x{FF10}-\x{FF19}]\s*<wbr\s*\/?>[\x{3040}-\x{309F}\x{30A0}-\x{30FF}\x{4E00}-\x{9FFF}]/) ? 1 : 0;
    exit($bad ? 1 : 0);
  '
}

# ---------------------------------------------------------------------------
# check_file <file> <label>
#   1 ファイル分の 4 検証（+ 過剰密度 WARN）を実行し、errors / warnings に追記する
# ---------------------------------------------------------------------------
check_file() {
  file="$1"
  label="$2"

  total_wbr=$(grep -o -i '<wbr' "$file" 2>/dev/null | wc -l | tr -d ' ')
  total_wbr=${total_wbr:-0}

  headings_raw=$(extract_headings "$file")
  [ -z "$headings_raw" ] && return 0

  while IFS= read -r h; do
    [ -z "$h" ] && continue

    plain=$(printf '%s' "$h" | sed 's/<[^>]*>//g')
    plen=$(printf '%s' "$plain" | char_len)
    plen=${plen:-0}

    # --- 検証1: wbr-存在性 ---
    if [ "$total_wbr" -gt 0 ] && [ "$plen" -ge 8 ]; then
      if printf '%s' "$plain" | has_japanese; then
        if ! printf '%s' "$h" | grep -qi '<wbr'; then
          errors="${errors}${label}: 見出し「${plain}」に <wbr> がありません\n"
        fi
      fi
    fi

    # <wbr> を含まない見出しは以降の検証対象外
    printf '%s' "$h" | grep -qi '<wbr' || continue

    # --- 検証2: wbr-最小チャンク ---
    if ! printf '%s' "$h" | check_min_chunk; then
      errors="${errors}${label}: 見出し「${plain}」の <wbr> 分割断片に2文字以下のものがあります\n"
    fi

    # --- 検証3: wbr-カタカナ分断 ---
    if ! printf '%s' "$h" | check_katakana_split; then
      errors="${errors}${label}: 見出し「${plain}」でカタカナ3文字以上の連続の途中に <wbr> があります\n"
    fi

    # --- 検証4: wbr-数値助数詞分断 ---
    if ! printf '%s' "$h" | check_counter_split; then
      errors="${errors}${label}: 見出し「${plain}」で数値直後の <wbr> が助数詞1文字を分断しています\n"
    fi

    # --- WARN: 過剰密度 ---
    wbr_count=$(printf '%s' "$h" | grep -o -i '<wbr' | wc -l | tr -d ' ')
    wbr_count=${wbr_count:-0}
    if [ "$wbr_count" -ge 4 ]; then
      warnings="${warnings}${label}: 見出し「${plain}」に <wbr> が${wbr_count}個あり過剰密度の可能性があります\n"
    fi
  done <<< "$headings_raw"
}

# ---------------------------------------------------------------------------
# 引数チェック
# ---------------------------------------------------------------------------
if [ $# -lt 1 ]; then
  echo "Usage: $0 <html-file>" >&2
  exit 1
fi
targets="$1"

# ---------------------------------------------------------------------------
# 検査実行
# ---------------------------------------------------------------------------
while IFS= read -r file; do
  [ -z "$file" ] && continue
  [ -f "$file" ] || continue
  check_file "$file" "$file"
done <<< "$targets"

if [ -n "$errors" ]; then
  printf '[WBR-QUALITY-BLOCK] wbr品質検査に失敗:\n%b' "$errors" >&2
  exit 2
fi

if [ -n "$warnings" ]; then
  printf '[WBR-QUALITY] %b' "$warnings" >&2
fi

exit 0
