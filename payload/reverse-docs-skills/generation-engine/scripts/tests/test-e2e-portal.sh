#!/usr/bin/env bash
# test-e2e-portal.sh — ポータル静的 E2E テスト
#
# 集約には名前で収集される（run-layer-machine-checks.sh が test-*.sh を無条件に拾う）。
# 通常実行はポータル一式のE2E検査、--self-testは壊れた埋め込みJSONパスを検出できるかの
# 負試験を行う。
#
# Usage: test-e2e-portal.sh <portal-root-dir>
#   引数省略時はスクリプト位置から ../samples を解決する。
#
# レイアウト方針（正本準拠の強制が本テストの役割）:
#   - 一覧ページは 2 レイアウトを許容する。「<root>/一覧/<種別一覧>/<種別一覧>.html」
#     （サンプル配置）と「<root>/<種別一覧>/<種別一覧>.html」（統括フロー生成配置）の
#     両方を探索し、見つかった方を検査対象にする。検出レイアウトはヘッダ行で出力する
#   - ポータル index の正本は「<root>/index.html」の 1 つのみ。<root>/../project-portal/
#     等の正本外配置は探索しない（正本外に置かれた場合はリンク解決 FAIL のままとする。
#     正本準拠を強制するのがこのテストの役割であり、探索を広げて救済しない）
#   - AI設定資産・マトリクス・対応表のページは存在する場合のみ検査する（不在は SKIP 行を出す。
#     対応表は現行正本「<root>/matrices/」と旧レイアウト「<root>/マトリクス・対応表/」
#     「<root>/対応表/」を探索し、生成フローが未対応のページを FAIL にしない）
#
# 検査項目（ケースキーは意味語。連番禁止）:
#   リンク-戻る解決   各ページにポータルトップへ戻る手段があるか。従来の「ポータルへ戻る」
#                     リンク／brand アンカーの href が実在ファイルを指すか、または共通シェルの
#                     サイドバー（class="pt-sidebar"）が data-portal-href に空でない値を持つか
#   リンク-内部解決   全 <a href>（#・http 以外）を相対解決して実在するか
#   json-埋め込み妥当  <script type="application/json"> の中身が jq でパース可能か
#   整合-行数一致     一覧9ページのマニフェスト件数と tbody データ行数の一致
#   機能-必須JS       一覧9ページの copy-btn/filter-chips/row-detail/csv/URLSearchParams、
#                     マトリクス・対応表4+AI設定資産の URLSearchParams
#   退行-行高         一覧9ページの td CSS に white-space: nowrap / text-overflow: ellipsis
#   退行-縦書き       マトリクス3ページに rotate(180deg) が無く text-orientation が有ること
#   構造-タグ開閉     table/script/details の開閉数一致（HTMLコメント除外）
#   リンク-存在確認   index.html の portal-categories JSON 内の全 tools[].href がファイルとして実在するか
#   構造-カテゴリ整合 index.html の portal-categories JSON 内の全カテゴリ id がユニークであるか
#   構造-グループ整合 group フィールドを持つカテゴリ・ツールで、同一 group 内のカードが
#                     連続配置されているか（レンダラは group 変化時にのみ見出しを描画するため、
#                     非連続だと同一グループ見出しが重複表示される）
#   絶対パス断片-0件  全ページ内容に実行環境の絶対パス断片(/Users/... または /home/...)が
#                     残存していないか（改善課題1-102: 実行環境の絶対パスの焼き込み防止）
#   フッター-空確認   全ページの <footer> 内にスキル名・生成ツール名が含まれていないか
#   リンク-文書存在確認 全ページの埋め込みJSONにある名前がPathで終わる文字列フィールドを
#                     ページ基準で解決し、指す実体がすべて存在するか
#   整合-リンク設計   画面一覧サンプル・テンプレートの詳細行 JS が item[doc.pathField] で
#                     リンク有効/無効を制御しているか（固定パターン screenDir が残存しないか）
#
# 出力: 「[PASS|FAIL|SKIP] <ケースキー> <ページ名> — 詳細」+ 末尾サマリ。FAIL があれば exit 1。
# 依存: bash / jq / perl（macOS 標準）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "${1:-}" = "--self-test" ]; then
  SELF_TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/e2e-portal-self-test.XXXXXX")"
  trap 'rm -rf "$SELF_TEST_DIR"' EXIT
  mkdir -p "$SELF_TEST_DIR/project-portal"
  cat > "$SELF_TEST_DIR/project-portal/index.html" <<'HTML'
<!doctype html>
<html lang="ja"><body>
<script type="application/json">[{"id":"fixture","tools":[]}]</script>
<script type="application/json">{"testCasePath":"missing-test-case.html"}</script>
<footer></footer>
</body></html>
HTML
  self_test_output="$(bash "$0" "$SELF_TEST_DIR" 2>&1)"
  self_test_rc=$?
  if [ "$self_test_rc" -eq 1 ] \
    && printf '%s\n' "$self_test_output" | grep -q '\[FAIL\] リンク-文書存在確認 project-portal/index.html' \
    && printf '%s\n' "$self_test_output" | grep -q 'missing-test-case.html'; then
    echo "[PASS] 壊れた埋め込みJSONの文書パスを検出して終了コード1"
    exit 0
  fi
  echo "[FAIL] 壊れた埋め込みJSONの文書パスを検出できない（本体終了コード=${self_test_rc}）" >&2
  printf '%s\n' "$self_test_output" >&2
  exit 1
fi

SAMPLES_DIR="${1:-$SCRIPT_DIR/../../samples}"
SAMPLES_DIR="$(cd "$SAMPLES_DIR" 2>/dev/null && pwd)" || {
  echo "ERROR: samples ディレクトリが見つからない: ${1:-$SCRIPT_DIR/../../samples}" >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq が必要" >&2; exit 2; }

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/e2e-portal.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

TOTAL=0
FAILS=0
SKIPS=0

report() { # report <PASS|FAIL|SKIP> <ケースキー> <ページ名> <詳細>
  local st="$1" key="$2" page="$3" detail="$4"
  TOTAL=$((TOTAL + 1))
  [ "$st" = "FAIL" ] && FAILS=$((FAILS + 1))
  [ "$st" = "SKIP" ] && SKIPS=$((SKIPS + 1))
  echo "[$st] $key $page — $detail"
}

rel() { # samples 相対のページ名
  printf '%s\n' "${1#"$SAMPLES_DIR"/}"
}

check_contiguous_groups() { # 標準入力: group値を改行区切りで受け取り、非連続に再出現したgroup名を返す（連続なら空）
  awk '
    { g = $0 }
    g == "" { next }
    {
      if (prev != "" && g != prev) { closed[prev] = 1 }
      if ((g in closed) && g != prev) { print g; exit }
      prev = g
    }
  '
}

# ---- 対象ページの収集（ER図.html・規約提案配下は対象外）----
# 規約提案HTMLはポータルのページではなく、リポジトリ外へ出力して現場のエンジニアが
# 判定するための独立した成果物である（ポータル共通シェルを使わない。
# .claude/rules/scoped/portal/page-conventions/rule.md「## 適用対象」参照）。
# 除外の書き方は test-portal-conventions.sh の -not -path 指定に揃える。
ALL_PAGES=()
while IFS= read -r f; do
  case "$(basename "$f")" in "ER図.html") continue ;; esac
  ALL_PAGES+=("$f")
done < <(find "$SAMPLES_DIR" -name '*.html' \
  -not -path '*/generation-engine/samples/規約提案/*' \
  -not -path '*/delivery-payload/templates/rule-proposal/*' \
  | LC_ALL=C sort)

# shellcheck source=output-layout.sh
source "$SCRIPT_DIR/../output-layout.sh"
LAYOUT_JSON="$(resolve_output_layout "$SAMPLES_DIR")" || exit 2
UNITS_ROOT="$(output_layout_get "$LAYOUT_JSON" unitsRoot)" || exit 2

# 一覧ページの探索: 「<unitsRoot>/<種別一覧>/」（サンプル配置）と「<種別一覧>/」（生成配置）の
# 両レイアウトを種別ごとに探索し、見つかった方を検査対象にする（ヘッダ方針コメント参照）
LIST_TYPES=(画面一覧 機能一覧 API一覧 テーブル一覧 バッチ一覧 帳票一覧 外部連携一覧 メッセージ一覧 テスト観点表)
LIST_PAGES=()
NESTED_COUNT=0
FLAT_COUNT=0
for t in "${LIST_TYPES[@]}"; do
  if [ -f "$SAMPLES_DIR/$UNITS_ROOT/$t/$t.html" ]; then
    LIST_PAGES+=("$SAMPLES_DIR/$UNITS_ROOT/$t/$t.html")
    NESTED_COUNT=$((NESTED_COUNT + 1))
  elif [ -f "$SAMPLES_DIR/$t/$t.html" ]; then
    LIST_PAGES+=("$SAMPLES_DIR/$t/$t.html")
    FLAT_COUNT=$((FLAT_COUNT + 1))
  fi
done
echo "# 一覧レイアウト検出: 一覧/<種別一覧>/ 形式 ${NESTED_COUNT} 件・<種別一覧>/ 形式 ${FLAT_COUNT} 件（計 ${#LIST_PAGES[@]}/${#LIST_TYPES[@]} 種別）"

CROSS_PAGES=()
for f in "${ALL_PAGES[@]}"; do
  case "$f" in */matrices/*|*/マトリクス・対応表/*|*/対応表/*) CROSS_PAGES+=("$f") ;; esac
done

MATRIX_PAGES=()
for f in ${CROSS_PAGES[@]+"${CROSS_PAGES[@]}"}; do
  case "$(basename "$f")" in
    権限画面マトリクス.html|権限機能マトリクス.html|CRUD図.html) MATRIX_PAGES+=("$f") ;;
  esac
done

AI_PAGE="$SAMPLES_DIR/project-portal/foundation/AI設定資産.html"

# ---- 検査キー: リンク-戻る解決 ----
for f in "${ALL_PAGES[@]}"; do
  page="$(rel "$f")"
  [ "$page" = "index.html" ] && continue
  # 規約提案HTMLはポータルのページではなく、リポジトリ外へ出力して現場のエンジニアが
  # 判定するための独立した成果物である（ポータル共通シェルを使わない。
  # .claude/rules/scoped/portal/page-conventions/rule.md「## 適用対象」参照）。
  # samples には見本が置かれているため、走査の対象から除外する必要がある。
  # 表記ゆれ許容: 「ポータルへ戻る」「ポータル TOP へ戻る」。無ければ brand アンカーで代替
  line="$(grep -m1 -E 'ポータル[^<]*戻る' "$f" || true)"
  [ -z "$line" ] && line="$(grep -m1 -E '<a class="brand" href="[^"]*"' "$f" || true)"
  if [ -n "$line" ]; then
    href="$(printf '%s' "$line" | grep -oE 'href="[^"]*"' | head -1 | sed 's/^href="//; s/"$//')"
    if [ -z "$href" ]; then
      report FAIL "リンク-戻る解決" "$page" "戻るリンク行から href を抽出できない"
      continue
    fi
    target="${href%%\#*}"; target="${target%%\?*}"
    if [ -f "$(dirname "$f")/$target" ]; then
      report PASS "リンク-戻る解決" "$page" "href=$href 実在"
    else
      report FAIL "リンク-戻る解決" "$page" "href=$href が実在しない"
    fi
    continue
  fi
  # 従来リンクが無い場合: 共通シェルのサイドバー(pt-sidebar)がポータルへの相対パスを
  # data-portal-href に持つかで代替判定する（ナビ項目自体はJSが実行時に描画するため静的HTMLには現れない）
  sidebar_line="$(grep -m1 -E 'class="pt-sidebar"' "$f" || true)"
  if [ -z "$sidebar_line" ]; then
    report FAIL "リンク-戻る解決" "$page" "「ポータルへ戻る」リンク・brand アンカー・pt-sidebar のいずれも見つからない"
    continue
  fi
  portal_href="$(printf '%s' "$sidebar_line" | grep -oE 'data-portal-href="[^"]*"' | head -1 | sed 's/^data-portal-href="//; s/"$//')"
  if [ -z "$portal_href" ] || [ "${portal_href#*\{\{}" != "$portal_href" ]; then
    report FAIL "リンク-戻る解決" "$page" "pt-sidebar の data-portal-href が空または未置換(${portal_href})"
  else
    report PASS "リンク-戻る解決" "$page" "pt-sidebar data-portal-href=$portal_href"
  fi
done

# ---- 検査キー: リンク-内部解決 ----
for f in "${ALL_PAGES[@]}"; do
  page="$(rel "$f")"
  dir="$(dirname "$f")"
  broken=""
  checked=0
  while IFS= read -r href; do
    case "$href" in
      ''|'#'*|http://*|https://*|mailto:*|javascript:*) continue ;;
      *"'"*|*'+'*|*'$'*|*'`'*|*' '*) continue ;;  # JS 文字列連結で生成される href は静的検査の対象外
    esac
    target="${href%%\#*}"; target="${target%%\?*}"
    [ -z "$target" ] && continue
    checked=$((checked + 1))
    if [ ! -e "$dir/$target" ]; then
      broken="$broken $href"
    fi
  done < <(grep -oE '<a[^>]*href="[^"]*"' "$f" | grep -oE 'href="[^"]*"' | sed 's/^href="//; s/"$//' | LC_ALL=C sort -u)
  if [ -n "$broken" ]; then
    report FAIL "リンク-内部解決" "$page" "リンク切れ:$broken"
  else
    report PASS "リンク-内部解決" "$page" "内部リンク ${checked} 件すべて実在"
  fi
done

# ---- 検査キー: json-埋め込み妥当 ----
extract_json_blocks() { # <file> <outdir> — application/json ブロックを個別ファイルに書き出す
  # HTML コメント内のタグ言及を誤検出しないよう、コメント除去後に抽出する。
  # HTML全体を走査し、開始タグの改行・属性順・単二重引用・同一行の複数scriptに対応する。
  # data-type等の部分属性は、独立したtype属性ではないため対象外にする。
  perl -0777 - "$1" "$2" <<'PERL'
use strict;
use warnings;

my ($file, $outdir) = @ARGV;
open my $input, '<', $file or die "open $file: $!";
local $/;
my $html = <$input>;
close $input;
$html =~ s/<!--.*?-->//gs;

sub has_application_json_type {
  my ($attributes) = @_;
  pos($attributes) = 0;
  while ($attributes =~ /\G\s*([^\s=\/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/gc) {
    my ($name, $double_quoted, $single_quoted, $unquoted) = ($1, $2, $3, $4);
    my $value = defined $double_quoted ? $double_quoted
      : defined $single_quoted ? $single_quoted
      : defined $unquoted ? $unquoted
      : '';
    return 1 if lc($name) eq 'type' && lc($value) eq 'application/json';
  }
  return 0;
}

my $count = 0;
while ($html =~ m{<script(?=[\s>])((?:"[^"]*"|'[^']*'|[^'"<>])*)>(.*?)</script\s*>}gis) {
  my ($attributes, $body) = ($1, $2);
  next unless has_application_json_type($attributes);
  $count++;
  my $output = "$outdir/block_$count.json";
  open my $block, '>', $output or die "open $output: $!";
  print {$block} $body;
  close $block;
}

open my $count_file, '>', "$outdir/count" or die "open count: $!";
print {$count_file} $count;
close $count_file;
PERL
}

for f in "${ALL_PAGES[@]}"; do
  page="$(rel "$f")"
  blockdir="$TMP_DIR/json_$TOTAL"
  mkdir -p "$blockdir"
  extract_json_blocks "$f" "$blockdir"
  count="$(cat "$blockdir/count" 2>/dev/null || echo 0)"
  if [ "$count" -eq 0 ]; then
    report PASS "json-埋め込み妥当" "$page" "JSON ブロックなし（対象外）"
    continue
  fi
  bad=""
  for b in "$blockdir"/block_*.json; do
    [ -f "$b" ] || continue
    jq empty "$b" >/dev/null 2>&1 || bad="$bad $(basename "$b")"
  done
  if [ -n "$bad" ]; then
    report FAIL "json-埋め込み妥当" "$page" "jq パース不能:${bad}（全 ${count} 個中）"
  else
    report PASS "json-埋め込み妥当" "$page" "JSON ${count} 個すべてパース可能"
  fi
done

# ---- 検査キー: 整合-行数一致 ----
for f in ${LIST_PAGES[@]+"${LIST_PAGES[@]}"}; do
  page="$(rel "$f")"
  blockdir="$TMP_DIR/manifest_$TOTAL"
  mkdir -p "$blockdir"
  extract_json_blocks "$f" "$blockdir"
  mcount=""
  for b in "$blockdir"/block_*.json; do
    [ -f "$b" ] || continue
    v="$(jq -r 'if type=="object" and has("screens") then .screens|length
                elif type=="object" and has("units") then .units|length
                else empty end' "$b" 2>/dev/null || true)"
    if [ -n "$v" ]; then mcount="$v"; break; fi
  done
  if [ -z "$mcount" ]; then
    report FAIL "整合-行数一致" "$page" "units/screens を持つマニフェストが見つからない"
    continue
  fi
  # データ表（class units/screens または id unit/screen-table）配下の全 tbody 行を合算する
  # （機能一覧のようにグループ別の複数テーブルへ分割されるページがあるため）
  rcount="$(awk '
    /<table[^>]*(id="(unit|screen)-table"|class="(units|screens)")/ { intable = 1 }
    intable && /<\/table>/ { intable = 0; inbody = 0 }
    intable && /<tbody/ { inbody = 1; next }
    inbody && /<\/tbody>/ { inbody = 0; next }
    intable && inbody && /<tr[ >]/ && $0 !~ /row-detail/ && $0 !~ /empty-row/ { rows++ }
    END { print rows + 0 }
  ' "$f")"
  if [ "$mcount" -eq "$rcount" ]; then
    report PASS "整合-行数一致" "$page" "マニフェスト ${mcount} 件 = tbody ${rcount} 行"
  else
    report FAIL "整合-行数一致" "$page" "マニフェスト ${mcount} 件 ≠ tbody ${rcount} 行"
  fi
done

# ---- 検査キー: 機能-必須JS ----
has_initial_q_handoff() { # <file> — initialQ の?q=取得から同一条件ブロック内の絞り込み実行までを検証
  awk '
    /^[[:space:]]*(var|let|const)[[:space:]]+initialQ[[:space:]]*=.*URLSearchParams\(location\.search\)\.get\('\''q'\''\)/ {
      initial_q_getter = 1
    }
    initial_q_getter && /^[[:space:]]*if[[:space:]]*\(initialQ[[:space:]]*&&[[:space:]]*search\)[[:space:]]*\{/ {
      in_query_block = 1
      next
    }
    in_query_block && /^[[:space:]]*search\.value[[:space:]]*=[[:space:]]*initialQ;[[:space:]]*$/ {
      search_assigned = 1
      next
    }
    in_query_block && search_assigned && /^[[:space:]]*applyFilter\(\);[[:space:]]*$/ {
      handoff_complete = 1
      exit
    }
    in_query_block && /^[[:space:]]*\}/ {
      in_query_block = 0
    }
    END { exit(handoff_complete ? 0 : 1) }
  ' "$1"
}

for f in ${LIST_PAGES[@]+"${LIST_PAGES[@]}"}; do
  page="$(rel "$f")"
  missing=""
  for token in "copy-btn" "filter-chips" "row-detail" "URLSearchParams"; do
    grep -q "$token" "$f" || missing="$missing $token"
  done
  grep -qi "csv" "$f" || missing="$missing csv"
  if [ -n "$missing" ]; then
    report FAIL "機能-必須JS" "$page" "欠落:$missing"
  else
    report PASS "機能-必須JS" "$page" "copy-btn/filter-chips/row-detail/csv/URLSearchParams すべて存在"
  fi
done
# マトリクス・対応表・AI設定資産は存在する場合のみ検査（不在は SKIP。生成フロー未対応を FAIL にしない）
if [ "${#CROSS_PAGES[@]}" -eq 0 ]; then
  report SKIP "機能-必須JS" "マトリクス・対応表" "ページ不在（生成フロー未対応のため検査対象外）"
fi
for f in ${CROSS_PAGES[@]+"${CROSS_PAGES[@]}"} "$AI_PAGE"; do
  page="$(rel "$f")"
  if [ ! -f "$f" ]; then
    report SKIP "機能-必須JS" "$page" "ページ不在（生成フロー未対応のため検査対象外）"
    continue
  fi
  case "$(basename "$f")" in
    画面-API-テーブル対応表.html|機能別API・テーブル対応表.html)
      if has_initial_q_handoff "$f"; then
        report PASS "機能-必須JS" "$page" "initialQ の?q=取得・検索窓設定・絞り込み実行が同一条件ブロック内に存在"
      else
        report FAIL "機能-必須JS" "$page" "initialQ の?q=取得・検索窓設定・絞り込み実行が同一条件ブロック内にない"
      fi
      ;;
    *)
      if grep -q "URLSearchParams" "$f"; then
        report PASS "機能-必須JS" "$page" "URLSearchParams 存在"
      else
        report FAIL "機能-必須JS" "$page" "URLSearchParams 欠落"
      fi
      ;;
  esac
done

# ---- 検査キー: 退行-行高 ----
css_td_has() { # <file> <property-regex> — td を含むセレクタのルール本体に property があるか
  # 行ベースの状態機械で「td を含むセレクタの { 〜 } 区間」を追跡する。
  # （macOS awk はレコード分割 split(…, "{") が誤動作するため split を使わない）
  awk -v prop="$2" '
    {
      line = $0
      if (line ~ /\{/) {
        sel = line; sub(/\{.*/, "", sel)
        rest = line; sub(/^[^{]*\{/, "", rest)
        intd = (sel ~ /td/) ? 1 : 0
        if (intd && rest ~ prop) found = 1
        if (rest ~ /\}/) intd = 0
      } else if (line ~ /\}/) {
        if (intd && line ~ prop) found = 1
        intd = 0
      } else if (intd && line ~ prop) {
        found = 1
      }
    }
    END { exit found ? 0 : 1 }
  ' "$1"
}

for f in ${LIST_PAGES[@]+"${LIST_PAGES[@]}"}; do
  page="$(rel "$f")"
  missing=""
  css_td_has "$f" "white-space:[[:space:]]*nowrap" || missing="$missing white-space:nowrap"
  css_td_has "$f" "text-overflow:[[:space:]]*ellipsis" || missing="$missing text-overflow:ellipsis"
  if [ -n "$missing" ]; then
    report FAIL "退行-行高" "$page" "td CSS に欠落:$missing"
  else
    report PASS "退行-行高" "$page" "td CSS に nowrap / ellipsis あり"
  fi
done

# ---- 検査キー: 退行-縦書き ----
if [ "${#MATRIX_PAGES[@]}" -eq 0 ]; then
  report SKIP "退行-縦書き" "マトリクス・対応表" "マトリクスページ不在（生成フロー未対応のため検査対象外）"
fi
for f in ${MATRIX_PAGES[@]+"${MATRIX_PAGES[@]}"}; do
  page="$(rel "$f")"
  probs=""
  # 共通シェルの折りたたみ矢印（.pt-brand-caret の回転）は縦書きと無関係のため除外して検査する。
  # 除外を安易に外さないこと（誤検知の原因だった）。pipefail 下の SIGPIPE 競合を避けるため
  # grep -q の代わりに変数へ結果を受けてから空判定する
  hits="$(grep 'rotate(180deg)' "$f" | grep -v '\.pt-brand-caret' || true)"
  [ -n "$hits" ] && probs="$probs rotate(180deg)が残存"
  grep -q 'text-orientation' "$f" || probs="$probs text-orientationが欠落"
  if [ -n "$probs" ]; then
    report FAIL "退行-縦書き" "$page" "$probs"
  else
    report PASS "退行-縦書き" "$page" "rotate(180deg) なし・text-orientation あり"
  fi
done

# ---- 検査キー: 構造-タグ開閉 ----
for f in "${ALL_PAGES[@]}"; do
  page="$(rel "$f")"
  stripped="$TMP_DIR/stripped.html"
  # HTML コメントと CSS/JS の /* ... */ ブロックコメント（装飾コメント中のタグ名混入があり得る）に加え、
  # JS の行頭 // コメント（タグ名への言及があり得る）も除外する。
  # /* ... */ の除去は <style> と <script>（text/plain 除く）の中身だけに限定する。
  # ファイル全体へ適用すると、data-paths 属性値や本文中の glob 記法（例: "src/**/*"）に含まれる
  # 「/*」が、離れた位置にある本物のブロックコメントの「*/」まで非貪欲マッチしてしまい、
  # その間に挟まる実タグ（<script> 開始タグ等）ごと消えてしまう事故があった
  # （規約提案サンプルで実際に発生・構造-タグ開閉が誤検知した）。
  # <script type="text/plain"> の中身はブラウザが解釈しないリテラル文である。
  # 中身のリテラル <script 等を開閉カウントに含めないよう、開閉タグだけ残して除去する
  perl -0777 -pe '
    s/<!--.*?-->//gs;
    s{(<style[^>]*>)(.*?)(</style>)}{my ($o,$b,$c)=($1,$2,$3); $b=~s{/\*.*?\*/}{}gs; $o.$b.$c}gse;
    s{(<script(?![^>]*type="text/plain")[^>]*>)(.*?)(</script>)}{my ($o,$b,$c)=($1,$2,$3); $b=~s{/\*.*?\*/}{}gs; $o.$b.$c}gse;
    s{(<script[^>]*type="text/plain"[^>]*>).*?(?=</script>)}{$1}gs;
  ' "$f" | grep -vE '^[[:space:]]*//' > "$stripped"
  probs=""
  for tag in table script details; do
    counts="$(perl -0777 -ne '
      BEGIN { $tag = shift @ARGV }
      $open += () = /<\Q$tag\E(?:\s|>)/g;
      $close += () = m{</\Q$tag\E\s*>}g;
      END { print(($open || 0) . " " . ($close || 0)) }
    ' "$tag" "$stripped")"
    open="${counts%% *}"
    close="${counts##* }"
    [ "$open" -ne "$close" ] && probs="$probs ${tag}(開${open}/閉${close})"
  done
  if [ -n "$probs" ]; then
    report FAIL "構造-タグ開閉" "$page" "開閉数不一致:$probs"
  else
    report PASS "構造-タグ開閉" "$page" "table/script/details の開閉数一致"
  fi
done

# ---- 検査キー: リンク-存在確認 / 構造-カテゴリ整合 / 構造-グループ整合（index.html の portal-categories JSON）----
INDEX_PAGE="$SAMPLES_DIR/index.html"
if [ ! -f "$INDEX_PAGE" ]; then
  report SKIP "リンク-存在確認" "index.html" "ページ不在（生成フロー未対応のため検査対象外）"
  report SKIP "構造-カテゴリ整合" "index.html" "ページ不在（生成フロー未対応のため検査対象外）"
  report SKIP "構造-グループ整合" "index.html" "ページ不在（生成フロー未対応のため検査対象外）"
else
  idx_blockdir="$TMP_DIR/index_categories"
  mkdir -p "$idx_blockdir"
  extract_json_blocks "$INDEX_PAGE" "$idx_blockdir"
  cat_json=""
  for b in "$idx_blockdir"/block_*.json; do
    [ -f "$b" ] || continue
    if [ "$(jq -r 'if type=="array" then "array" else "other" end' "$b" 2>/dev/null)" = "array" ]; then
      cat_json="$b"
      break
    fi
  done

  if [ -z "$cat_json" ]; then
    report FAIL "リンク-存在確認" "index.html" "カテゴリJSON(配列)が見つからない"
    report FAIL "構造-カテゴリ整合" "index.html" "カテゴリJSON(配列)が見つからない"
    report FAIL "構造-グループ整合" "index.html" "カテゴリJSON(配列)が見つからない"
  else
    idx_dir="$(dirname "$INDEX_PAGE")"

    # -- リンク-存在確認 --
    broken=""
    checked=0
    while IFS= read -r href; do
      case "$href" in
        ''|'#'*|http://*|https://*|mailto:*|javascript:*) continue ;;
      esac
      target="${href%%\#*}"; target="${target%%\?*}"
      [ -z "$target" ] && continue
      checked=$((checked + 1))
      if [ ! -e "$idx_dir/$target" ]; then
        broken="$broken $href"
      fi
    done < <(jq -r '[.[].tools[]?.href] | .[]' "$cat_json" 2>/dev/null | LC_ALL=C sort -u)
    if [ -n "$broken" ]; then
      report FAIL "リンク-存在確認" "index.html" "リンク切れ:$broken"
    else
      report PASS "リンク-存在確認" "index.html" "tools[].href ${checked} 件すべて実在"
    fi

    # -- 構造-カテゴリ整合 --
    dup_ids="$(jq -r '[.[].id] | group_by(.) | map(select(length > 1) | .[0]) | join(",")' "$cat_json" 2>/dev/null)"
    if [ -n "$dup_ids" ]; then
      report FAIL "構造-カテゴリ整合" "index.html" "id重複:$dup_ids"
    else
      report PASS "構造-カテゴリ整合" "index.html" "全カテゴリidがユニーク"
    fi

    # -- 構造-グループ整合（トップレベルのカテゴリgroup + 各カテゴリ内tools[].group）--
    top_violation="$(jq -r '.[] | .group // ""' "$cat_json" 2>/dev/null | check_contiguous_groups)"
    group_problems=""
    [ -n "$top_violation" ] && group_problems="トップレベル(${top_violation})"

    while IFS= read -r cat_id; do
      [ -z "$cat_id" ] && continue
      v="$(jq -r --arg id "$cat_id" '.[] | select(.id == $id) | .tools[] | .group // ""' "$cat_json" 2>/dev/null | check_contiguous_groups)"
      if [ -n "$v" ]; then
        group_problems="${group_problems} ${cat_id}(${v})"
      fi
    done < <(jq -r '.[].id' "$cat_json" 2>/dev/null)

    if [ -n "$group_problems" ]; then
      report FAIL "構造-グループ整合" "index.html" "非連続group:${group_problems}"
    else
      report PASS "構造-グループ整合" "index.html" "全カテゴリ・全ツールのgroupが連続配置"
    fi
  fi
fi

# ---- 検査キー: 絶対パス断片-0件（改善課題1-102）----
ABS_PATH_PATTERN='/Users/[^"'\''`[:space:]]+|/home/[^"'\''`[:space:]]+'
for f in "${ALL_PAGES[@]}"; do
  page="$(rel "$f")"
  hits="$(grep -oE "$ABS_PATH_PATTERN" "$f" 2>/dev/null | LC_ALL=C sort -u | tr '\n' ' ')"
  if [ -n "$hits" ]; then
    report FAIL "絶対パス断片-0件" "$page" "検出:${hits}"
  else
    report PASS "絶対パス断片-0件" "$page" "絶対パス断片なし"
  fi
done

# ---- 検査キー: フッター-空確認 ----
FOOTER_BAN_PATTERN='スキルにより生成|により自動生成|設計スキル群'
for f in "${ALL_PAGES[@]}"; do
  page="$(rel "$f")"
  footer_content="$(awk '/<footer/,/<\/footer>/' "$f")"
  if [ -z "$footer_content" ]; then
    report PASS "フッター-空確認" "$page" "footerタグなし（対象外）"
    continue
  fi
  if printf '%s\n' "$footer_content" | grep -qE "$FOOTER_BAN_PATTERN"; then
    report FAIL "フッター-空確認" "$page" "footer内にスキル名・生成ツール名の記述が残存"
  else
    report PASS "フッター-空確認" "$page" "footer内にスキル名・生成ツール名なし"
  fi
done

# ---- 検査キー: リンク-文書存在確認（全ページの埋め込みJSON）----
SCREEN_LIST_PAGE=""
for f in ${LIST_PAGES[@]+"${LIST_PAGES[@]}"}; do
  case "$(basename "$f")" in "画面一覧.html") SCREEN_LIST_PAGE="$f" ;; esac
done
for f in "${ALL_PAGES[@]}"; do
  page="$(rel "$f")"
  dir="$(dirname "$f")"
  blockdir="$TMP_DIR/json_paths_$TOTAL"
  mkdir -p "$blockdir"
  extract_json_blocks "$f" "$blockdir"
  paths_file="$blockdir/paths.txt"
  : > "$paths_file"
  for b in "$blockdir"/block_*.json; do
    [ -f "$b" ] || continue
    jq -r '
      .. | objects | to_entries[]
      | select(.key | test("^[a-zA-Z]+Path$"))
      | .value | strings
    ' "$b" 2>/dev/null >> "$paths_file" || true
  done
  broken=""
  checked=0
  while IFS= read -r path; do
    case "$path" in
      ''|'#'*) continue ;;
    esac
    target="${path%%\#*}"; target="${target%%\?*}"
    [ -n "$target" ] || continue
    checked=$((checked + 1))
    if [ "${target#/}" != "$target" ]; then
      resolved="$SAMPLES_DIR/${target#/}"
    else
      resolved="$dir/$target"
    fi
    if [ ! -f "$resolved" ]; then
      broken="$broken $path"
    fi
  done < <(LC_ALL=C sort -u "$paths_file")
  if [ -n "$broken" ]; then
    report FAIL "リンク-文書存在確認" "$page" "埋め込みJSONの文書パス切れ:$broken"
  else
    report PASS "リンク-文書存在確認" "$page" "埋め込みJSONの*Path ${checked} 件すべて実在"
  fi
done

# ---- 検査キー: 整合-リンク設計 ----
LINK_DESIGN_TARGETS=()
[ -n "$SCREEN_LIST_PAGE" ] && LINK_DESIGN_TARGETS+=("$SCREEN_LIST_PAGE")
TEMPLATE_SCREEN_LIST="$SCRIPT_DIR/../../../delivery-payload/templates/unit-list/screen-list-template.html"
[ -f "$TEMPLATE_SCREEN_LIST" ] && LINK_DESIGN_TARGETS+=("$TEMPLATE_SCREEN_LIST")

if [ "${#LINK_DESIGN_TARGETS[@]}" -eq 0 ]; then
  report SKIP "整合-リンク設計" "画面一覧" "検査対象ページ・テンプレート不在（生成フロー未対応のため検査対象外）"
else
  for f in ${LINK_DESIGN_TARGETS[@]+"${LINK_DESIGN_TARGETS[@]}"}; do
    case "$f" in
      "$SAMPLES_DIR"/*) page="$(rel "$f")" ;;
      *) page="$(basename "$(dirname "$f")")/$(basename "$f")" ;;
    esac
    probs=""
    grep -q 'item\[doc\.pathField\]' "$f" || probs="${probs} pathFieldパターン欠落"
    grep -q 'screenDir' "$f" && probs="${probs} 固定パターンscreenDirが残存"
    if [ -n "$probs" ]; then
      report FAIL "整合-リンク設計" "$page" "$probs"
    else
      report PASS "整合-リンク設計" "$page" "item[doc.pathField]パターンで制御・screenDir固定パターンなし"
    fi
  done
fi

# ---- 検査キー: 値-画面名整合 / 値-表示コミット整合（check-derived-values.sh。Phase D 保守-派生値ずれ検知）----
DERIVED_VALUES_SCRIPT="$SCRIPT_DIR/../check-derived-values.sh"
if [ ! -f "$DERIVED_VALUES_SCRIPT" ]; then
  report SKIP "値-画面名整合" "全体" "check-derived-values.sh が見つからない"
  report SKIP "値-表示コミット整合" "全体" "check-derived-values.sh が見つからない"
else
  screens_out="$(bash "$DERIVED_VALUES_SCRIPT" "$SAMPLES_DIR" --screens-only 2>&1)"; screens_rc=$?
  if [ "$screens_rc" -eq 2 ]; then
    report SKIP "値-画面名整合" "全体" "前提不足（screen-manifest.json 不在等）のため検査対象外"
  elif [ "$screens_rc" -eq 0 ]; then
    report PASS "値-画面名整合" "全体" "画面名の定義（screen-manifest.json）と一覧・詳細ページの表示値が一致"
  else
    report FAIL "値-画面名整合" "全体" "$(printf '%s' "$screens_out" | grep '^MISMATCH:' | tr '\n' ';')"
  fi

  commits_out="$(bash "$DERIVED_VALUES_SCRIPT" "$SAMPLES_DIR" --commits-only 2>&1)"; commits_rc=$?
  if [ "$commits_rc" -eq 2 ]; then
    report SKIP "値-表示コミット整合" "全体" "前提不足のため検査対象外"
  elif [ "$commits_rc" -eq 0 ]; then
    report PASS "値-表示コミット整合" "全体" "表示コミットの定義（source_ref）とポータル・画面ページの表示値が一致"
  else
    report FAIL "値-表示コミット整合" "全体" "$(printf '%s' "$commits_out" | grep '^MISMATCH:' | tr '\n' ';')"
  fi
fi

# ---- サマリ ----
echo "合計 ${TOTAL} 件 / FAIL ${FAILS} 件 / SKIP ${SKIPS} 件"
[ "$FAILS" -eq 0 ] || exit 1
exit 0
