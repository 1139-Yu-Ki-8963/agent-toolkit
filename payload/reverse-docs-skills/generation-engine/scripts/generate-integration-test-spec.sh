#!/usr/bin/env bash
# generate-integration-test-spec.sh — 複数の設計単位をまたぐ結合テスト仕様書を、生成済みの設計書から起こす
#
# 使い方:
#   generate-integration-test-spec.sh <output_root> [project_name]
#   generate-integration-test-spec.sh --self-test
#
# 観点の起こし方（改善課題1-246。定義: .claude/skills/generating-integration-test-spec-for-reverse-docs/SKILL.md Step 2-2）:
#   1. <output_root>/docs/design/*/<kind>-<id>/*/ *詳細設計書.md の「### 4.2 内部呼び出し」（または相当する
#      節）の表の「呼び出し先」列を読む。同じ呼び出し先を2つ以上の単位が呼んでいれば、その呼び出し先を
#      共有する連携（連携キー: shared-<呼び出し先>）として起こす。
#   2. <output_root>/docs/design/features/feature-<id>/*/機能設計書.md の「### 7.1 機能内の呼び出し一覧」の
#      表の「呼び出す構成要素」列を読む。1つの機能が2つ以上の構成要素を順に呼んでいれば、その順序の
#      連携（連携キー: flow-<機能id>）として起こす。
#   3. 起こした連携ごとに、対象範囲へ1行、テストケース一覧へ区分「結合」の1行を書く。
#      連携が0件なら表は空のまま出し、その旨を標準エラーへ報告する（不合格にはしない）。
#
# 実装判断: 表の読み取りは perl で行う。macOS 標準の awk は多バイト文字列の比較を誤ることがあり、
#   「呼び出し先」のような日本語の列名で列位置を決める処理に使えない（詳細設計書 rule.md の実装判断を参照）。
set -u
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
template="$repo_root/delivery-payload/templates/リバース検証/プロジェクト共通/結合テスト仕様書.md"

# 観点の抽出。出力は TSV: kind \t linkKey \t from \t to \t shared \t sourceSection
observe_links() {
  local root="$1"
  perl -CSDA -Mutf8 -e '
    use strict; use warnings;
    my $root = shift;
    my (%callee_units, %callee_src);
    my @detail = sort glob("$root/docs/design/*/*/*/*詳細設計書.md");
    for my $f (@detail) {
      my ($unit) = ($f =~ m{/docs/design/[^/]+/([^/]+)/[^/]+/[^/]+$});
      next unless $unit;
      open my $fh, "<", $f or next; my @lines = <$fh>; close $fh;
      my ($in, $col) = (0, -1);
      for my $l (@lines) {
        chomp $l;
        if ($l =~ /^### [0-9.]+ 内部呼び出し/) { $in = 1; $col = -1; next }
        if ($in && $l =~ /^#{2,3} /) { $in = 0; next }
        next unless $in && $l =~ /^\|/;
        my @c = map { s/^\s+|\s+$//gr } split /\|/, $l; shift @c; pop @c if @c && $c[-1] eq "";
        if ($col < 0) { for my $i (0..$#c) { if ($c[$i] eq "呼び出し先") { $col = $i; last } } next }
        next if $l =~ /^\|\s*-/;
        my $callee = $c[$col] // ""; next if $callee eq "" || $callee =~ /^（|^\(|^<|^\[/;
        $callee_units{$callee}{$unit} = 1;
        $callee_src{$callee} = "詳細設計書 4.2 内部呼び出し";
      }
    }
    for my $callee (sort keys %callee_units) {
      my @units = sort keys %{$callee_units{$callee}};
      next if @units < 2;
      my $key = "shared-" . ($callee =~ s/[^\p{L}\p{N}_]+/-/gr);
      print join("\t", "shared", $key, join("・", @units), $callee, $callee, $callee_src{$callee}), "\n";
    }
    my @features = sort glob("$root/docs/design/features/*/*/機能設計書.md");
    for my $f (@features) {
      my ($unit) = ($f =~ m{/docs/design/features/([^/]+)/});
      next unless $unit;
      open my $fh, "<", $f or next; my @lines = <$fh>; close $fh;
      my ($in, $col, @calls) = (0, -1);
      for my $l (@lines) {
        chomp $l;
        if ($l =~ /^### 7\.1 /) { $in = 1; $col = -1; next }
        if ($in && $l =~ /^#{2,3} /) { $in = 0; next }
        next unless $in && $l =~ /^\|/;
        my @c = map { s/^\s+|\s+$//gr } split /\|/, $l; shift @c; pop @c if @c && $c[-1] eq "";
        if ($col < 0) { for my $i (0..$#c) { if ($c[$i] eq "呼び出す構成要素") { $col = $i; last } } next }
        next if $l =~ /^\|\s*-/;
        my $v = $c[$col] // ""; next if $v eq "" || $v =~ /^（|^\(|^<|^\[/;
        push @calls, $v unless grep { $_ eq $v } @calls;
      }
      next if @calls < 2;
      print join("\t", "flow", "flow-$unit", $calls[0], $calls[-1], join(" → ", @calls), "$unit 機能設計書 7.1 機能内の呼び出し一覧"), "\n";
    }
  ' "$root"
}

generate_spec() {
  local output_root="$1"
  local project_name="$2"
  local output="$output_root/docs/test-cases/結合テスト仕様書.md"
  mkdir -p "$(dirname "$output")"
  local links; links="$(observe_links "$output_root")"
  local n; n="$(printf '%s' "$links" | grep -c . || true)"
  if [ "$n" -eq 0 ]; then
    echo "INFO: 複数の単位をまたぐ連携を設計書から起こせませんでした（内部呼び出し・機能内の呼び出し一覧に該当なし）。表は空のまま出力します: ${output}" >&2
  fi
  printf '%s' "$links" | perl -CSDA -Mutf8 -e '
    use strict; use warnings;
    my ($template, $project) = @ARGV;
    my @links = map { chomp; [split /\t/] } grep { /\S/ } <STDIN>;
    open my $fh, "<", $template or die "template: $!"; my @t = <$fh>; close $fh;
    my $section = "";
    for my $l (@t) {
      $l =~ s/<プロジェクト名>/$project/g;
      print $l;
      if ($l =~ /^## (.*)$/) { $section = $1; next }
      next unless $l =~ /^\|\s*-{3}/;
      if ($section eq "対象範囲") {
        for my $k (@links) {
          my ($kind, $key, $from, $to, $shared, $src) = @$k;
          my $common = $kind eq "shared" ? $shared : "";
          print "| ${key} | ${from} | ${to} | ${common} | ${src} |\n";
        }
      } elsif ($section eq "テストケース一覧") {
        my $i = 0;
        for my $k (@links) {
          my ($kind, $key, $from, $to, $shared, $src) = @$k;
          $i++;
          my ($name, $pre, $steps, $expect);
          if ($kind eq "shared") {
            ${name} = "${shared}を共有する単位の連続実行";
            ${pre} = "${from} の各単位が実行できる状態";
            ${steps} = "1. ${from} の各単位を順に実行する 2. 各単位から ${shared} を呼ぶ箇所を通す";
            ${expect} = "各単位の結果が互いの実行順序に依存せず、${shared} の状態が単位間で矛盾しない";
          } else {
            ${name} = "${key} の呼び出し順序どおりの通し実行";
            ${pre} = "${from} を実行できる状態";
            ${steps} = "1. ${shared} の順に実行する";
            ${expect} = "${to} まで到達し、各段の出力が次の段の入力として成立する";
          }
          print "| 結合-${i} | ${key} | ${name} | 結合 | ${pre} | ${steps} | ${expect} |\n";
        }
      }
    }
  ' "$template" "$project_name" > "$output"
  printf '%s\n' "$output"
}

self_test() {
  local tmp output rc=0
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/integration-test-spec.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktemp が一時領域へ書き込めませんでした）"
    return 2
  fi
  trap 'rm -rf "$tmp"' RETURN
  # ケース1: 連携の材料が無い入力（従来の契約）
  output="$(generate_spec "$tmp" "検証用プロジェクト" 2>/dev/null)" || return 1
  test -f "$output" || rc=1
  grep -q '^# 検証用プロジェクト 結合テスト仕様書$' "$output" || rc=1
  grep -q '^## テストケース一覧$' "$output" || rc=1
  grep -q '^| キー | 連携キー | ケースの名前 | 区分 | 前提条件 | 操作手順 | 期待結果 |$' "$output" || rc=1
  grep -q '複数の画面・機能・API・テーブル・バッチ・帳票・外部連携' "$output" || rc=1
  if [ "$rc" -eq 0 ]; then echo 'PASS: ケース1 材料なしでも様式どおりの仕様書を生成'; else echo 'FAIL: ケース1 生成結果が契約を満たさない' >&2; fi
  # ケース2（改善課題1-246 検収4）: 2つの単位が同じモジュールを呼ぶ合成の入力
  local d="$tmp/case2"; local mk
  for u in api-login api-orders; do
    mk="$d/docs/design/apis/$u/detail-design"; mkdir -p "$mk"
    printf '# %s API詳細設計書\n\n## §4 処理フロー\n\n### 4.1 主処理\n\n### 4.2 内部呼び出し\n\n| 呼び出し先 | 引数 | 戻り値 |\n|---|---|---|\n| Session::verify | token | 真偽 |\n| Util::log | msg | なし |\n\n### 4.3 外部呼び出し\n' "$u" > "$mk/API詳細設計書.md"
  done
  mk="$d/docs/design/apis/api-health/detail-design"; mkdir -p "$mk"
  printf '# health\n\n### 4.2 内部呼び出し\n\n| 呼び出し先 | 引数 | 戻り値 |\n|---|---|---|\n| Util::log | msg | なし |\n\n### 4.3 外部呼び出し\n' > "$mk/API詳細設計書.md"
  mk="$d/docs/design/features/feature-checkout/basic-design"; mkdir -p "$mk"
  printf '# 決済 機能設計書\n\n## §7 呼び出し仕様\n\n### 7.1 機能内の呼び出し一覧\n\n| 識別子 | 契機 | 呼び出す構成要素 | 個別設計書 |\n|---|---|---|---|\n| c1 | 画面操作 | api-orders | x |\n| c2 | c1の成功 | api-login | y |\n\n### 7.2 呼び出し元との対応\n' > "$mk/機能設計書.md"
  output="$(generate_spec "$d" "合成" 2>/dev/null)" || { echo 'FAIL: ケース2 生成に失敗' >&2; return 1; }
  local rc2=0
  grep -q '^| shared-Session-verify | api-login・api-orders | Session::verify | Session::verify |' "$output" || rc2=1
  grep -q '^| shared-Util-log | api-health・api-login・api-orders |' "$output" || rc2=1
  grep -q '^| flow-feature-checkout | api-orders | api-login |' "$output" || rc2=1
  test "$(grep -c '^| 結合-[0-9]* | .* | 結合 | ' "$output")" -eq 3 || rc2=1
  if [ "$rc2" -eq 0 ]; then echo 'PASS: ケース2 同じ呼び出し先を共有する単位と機能の呼び出し順序を連携の観点として起こす（改善課題1-246）'; else echo 'FAIL: ケース2 連携の観点が起きていない' >&2; sed -n '/^## 対象範囲/,/^## データ/p' "$output" >&2; rc=1; fi
  # ケース3: 1つの単位しか呼ばない呼び出し先は連携にしない
  if grep -q 'shared-Util-log | api-health |' "$output"; then echo 'FAIL: ケース3 単独の呼び出し先を連携にしている' >&2; rc=1; else echo 'PASS: ケース3 単独の呼び出し先は連携に含めない'; fi
  return "$rc"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test; exit $?
fi
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo 'Usage: generate-integration-test-spec.sh <output_root> [project_name]' >&2
  exit 2
fi

generate_spec "$1" "${2:-プロジェクト}"
