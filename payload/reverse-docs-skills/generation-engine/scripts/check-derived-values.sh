#!/usr/bin/env bash
# check-derived-values.sh — 値レベルのずれ検知（画面名 / 表示コミット）
#
# 目的:
#   check-derived-drift.sh はファイルのハッシュ突合で「派生物が変わったか」を検知するが、
#   「表示されている値が定義と一致するか」までは見ない。本スクリプトは値そのものを突合する。
#   AI駆動開発セットアップ構想 Phase D「保守-派生値ずれ検知」が定める検知対象は次の2つに限定する。
#     1. 画面名: screen-manifest.json の値と、画面一覧HTML・画面詳細ページの表示値との一致
#     2. 表示コミット: 画面詳細設計書 frontmatter の source_ref と、ポータル・画面ページの表示値との一致
#   sourceRef（証跡のパスと行番号。camelCase・370箇所）は別概念のため検査対象に含めない。
#   判定は毎回、定義（manifest.json / frontmatter）から期待値を導出して現在の表示値と突合する
#   （check-derived-drift.sh のような台帳は持たない。値は決定的に再導出できるため不要）。
#
# 使い方:
#   check-derived-values.sh <出力ルート> [--screens-only|--commits-only]
#   check-derived-values.sh --self-test
#
# 終了コード: 不一致なし 0 / 不一致あり 1 / 前提不足（マニフェスト不在等） 2
# 依存: bash / jq
# macOS bash 3.2 互換（mapfile / declare -A 不使用。output-layout.sh と同じ方針）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck source=output-layout.sh
source "$SCRIPT_DIR/output-layout.sh"

usage() {
  echo "usage: $0 <root> [--screens-only|--commits-only] | --self-test" >&2
  exit 2
}

# --- frontmatter_value / is_commit_sha は build-portal.sh の定義と同一の規則を複製する。
#     本スクリプトは build-portal.sh を source せず単独で完結させるための複製であり、
#     判定規則を変える場合は両方を同時に更新する（check-derived-drift.sh の hash_file() と
#     同じ「単独完結のための複製」という設計判断）。
frontmatter_value() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 0
  awk -v key="$key" '
    { sub(/\r$/, "", $0) }
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter && $0 ~ ("^[[:space:]]*" key "[[:space:]]*:") {
      value = $0
      sub("^[[:space:]]*" key "[[:space:]]*:[[:space:]]*", "", value)
      sub("[[:space:]]*$", "", value)
      print value
      exit
    }
  ' "$file"
}

is_commit_sha() {
  [[ "$1" =~ ^([[:xdigit:]]{7}|[[:xdigit:]]{40}|[[:xdigit:]]{64})$ ]]
}

# <root>/<相対パス>/<id>.html の <script type="application/json" id="...">...</script> の中身を返す
extract_embedded_json() {
  local file="$1" id="$2"
  awk -v id="$id" '
    $0 ~ ("<script type=\"application/json\" id=\"" id "\">") { flag=1; next }
    flag && /<\/script>/ { flag=0; next }
    flag { print }
  ' "$file"
}

# <h1 class="pt-title" id="dp-hero-title">NAME 画面基本設計書</h1> から NAME を取り出す
extract_html_h1_name() {
  local file="$1" raw
  raw="$(grep -oE '<h1 class="pt-title" id="dp-hero-title">[^<]*</h1>' "$file" 2>/dev/null | head -n1)"
  [ -n "$raw" ] || { printf ''; return 0; }
  raw="${raw#*>}"; raw="${raw%<*}"
  raw="${raw% 画面基本設計書}"
  raw="${raw% 画面詳細設計書}"
  printf '%s' "$raw"
}

# <span id="pt-footer-commit">...コミット番号: XXXXXXX...</span> から短縮コミット値を取り出す
# （「コミット番号: 」を含まなければ空 = 表示なしとみなす。除去済み/未表示の両方を空で表す）
extract_commit_display() {
  local file="$1" id="$2" raw
  raw="$(grep -oE "<span id=\"$id\">[^<]*</span>" "$file" 2>/dev/null | head -n1)"
  [ -n "$raw" ] || { printf ''; return 0; }
  raw="${raw#*>}"; raw="${raw%<*}"
  if [[ "$raw" == *"コミット番号: "* ]]; then
    printf '%s' "${raw#*コミット番号: }"
  else
    printf ''
  fi
}

MISMATCHES=()
add_mismatch() { # <種別> <対象> <期待値> <実際値> <ファイル>
  MISMATCHES+=("MISMATCH: 種別=$1 対象=$2 期待値=$3 実際値=$4 ファイル=$5")
}

NAME_EXPR='(.confirmedScreenName // .screenNameGuess // "")'

check_screen_names() {
  local root="$1" manifest_path="$2" list_html_path="$3" screen_unit_root="$4"

  if [ -f "$list_html_path" ]; then
    local embedded
    embedded="$(extract_embedded_json "$list_html_path" screen-manifest)"
    if [ -n "$embedded" ] && printf '%s' "$embedded" | jq -e . >/dev/null 2>&1; then
      while IFS=$'\t' read -r key expected; do
        [ -n "$key" ] || continue
        local actual has_key
        has_key="$(printf '%s' "$embedded" | jq -r --arg k "$key" '[.screens[] | select(.screenKey==$k)] | length')"
        if [ "$has_key" = "0" ]; then
          add_mismatch "画面名-一覧" "$key" "$expected" "(一覧に該当screenKeyなし)" "$list_html_path"
          continue
        fi
        actual="$(printf '%s' "$embedded" | jq -r --arg k "$key" ".screens[] | select(.screenKey==\$k) | $NAME_EXPR" | head -n1)"
        if [ "$actual" != "$expected" ]; then
          add_mismatch "画面名-一覧" "$key" "$expected" "$actual" "$list_html_path"
        fi
      done < <(jq -r ".screens[] | [.screenKey, $NAME_EXPR] | @tsv" "$manifest_path")
    else
      echo "WARN: 一覧HTMLの screen-manifest 埋め込みJSONを取得できない: $list_html_path" >&2
    fi
  fi

  while IFS=$'\t' read -r screen_id expected; do
    [ -n "$screen_id" ] || continue
    local pair dir base html actual
    for pair in "基本設計:画面基本設計書" "詳細設計:画面詳細設計書"; do
      dir="${pair%%:*}"; base="${pair##*:}"
      html="$root/$screen_unit_root/$screen_id/$dir/$base.html"
      [ -f "$html" ] || continue
      actual="$(extract_html_h1_name "$html")"
      if [ "$actual" != "$expected" ]; then
        add_mismatch "画面名-詳細ページ" "$screen_id:$dir" "$expected" "$actual" "$html"
      fi
    done
  done < <(jq -r ".screens[] | select(.screenId != null) | [.screenId, $NAME_EXPR] | @tsv" "$manifest_path")
}

check_commit_values() {
  local root="$1" screen_unit_root="$2"
  local detail_md sr sr_values="" sr_count=0 expected_agg=""

  for detail_md in "$root/$screen_unit_root"/screen-*/詳細設計/画面詳細設計書.md; do
    [ -f "$detail_md" ] || continue
    sr="$(frontmatter_value "$detail_md" source_ref)"
    if [ -n "$sr" ] && [ "$sr" != "SOURCECOMMIT" ] && is_commit_sha "$sr"; then
      sr_values="${sr_values}${sr}"$'\n'
    fi
  done
  sr_values="$(printf '%s' "$sr_values" | sort -u | sed '/^$/d')"
  [ -n "$sr_values" ] && sr_count="$(printf '%s\n' "$sr_values" | wc -l | tr -d ' ')"
  if [ "$sr_count" -eq 1 ]; then
    expected_agg="$(printf '%s' "$sr_values" | cut -c1-7)"
  elif [ "$sr_count" -gt 1 ]; then
    expected_agg="画面ごとに異なる"
  fi

  local index_html="$root/index.html"
  if [ -f "$index_html" ]; then
    local actual_agg
    actual_agg="$(extract_commit_display "$index_html" pt-footer-commit)"
    if [ "$actual_agg" != "$expected_agg" ]; then
      add_mismatch "表示コミット-ポータル" "index.html" "$expected_agg" "$actual_agg" "$index_html"
    fi
  fi

  for detail_md in "$root/$screen_unit_root"/screen-*/詳細設計/画面詳細設計書.md; do
    [ -f "$detail_md" ] || continue
    local screen_dir screen_id expected_page="" pair dir base html actual_page
    screen_dir="$(dirname "$(dirname "$detail_md")")"
    screen_id="$(basename "$screen_dir")"
    sr="$(frontmatter_value "$detail_md" source_ref)"
    if [ -n "$sr" ] && [ "$sr" != "SOURCECOMMIT" ] && is_commit_sha "$sr"; then
      expected_page="$(printf '%s' "$sr" | cut -c1-7)"
    fi
    for pair in "基本設計:画面基本設計書" "詳細設計:画面詳細設計書"; do
      dir="${pair%%:*}"; base="${pair##*:}"
      html="$screen_dir/$dir/$base.html"
      [ -f "$html" ] || continue
      actual_page="$(extract_commit_display "$html" pt-footer-commit)"
      if [ "$actual_page" != "$expected_page" ]; then
        add_mismatch "表示コミット-画面" "$screen_id:$dir" "$expected_page" "$actual_page" "$html"
      fi
    done
  done
}

# ============================= self-test =============================

self_test() {
  command -v jq >/dev/null 2>&1 || { echo "ERROR: jq が必要" >&2; return 2; }
  local t pass=0 fail=0
  if ! t="$(mktemp -d "${TMPDIR:-/tmp}/check-derived-values.XXXXXX" 2>/dev/null)" || [ -z "$t" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  trap "rm -rf '$t'" RETURN

  local SHA_A SHA_B
  SHA_A="$(printf 'a%.0s' {1..40})"
  SHA_B="$(printf 'b%.0s' {1..40})"

  # 出力配置の宣言（output-layout.json）から自己テストの固定パスを解決する。
  # ここが本番の解決（324〜327行目付近の resolve_output_layout 呼び出し）とずれると、
  # フィクスチャが実際の検査対象と異なる場所に書かれ CLEAN 判定にならない。
  local BASE_LAYOUT_JSON SCREEN_UNIT_ROOT_T SCREEN_MANIFEST_REL_T SCREEN_LIST_HTML_REL_T
  BASE_LAYOUT_JSON="$(resolve_output_layout "")" || return 1
  SCREEN_UNIT_ROOT_T="$(output_layout_get "$BASE_LAYOUT_JSON" screenUnitRoot)" || return 1
  SCREEN_MANIFEST_REL_T="$(output_layout_get "$BASE_LAYOUT_JSON" screenManifest)" || return 1
  SCREEN_LIST_HTML_REL_T="$(output_layout_get "$BASE_LAYOUT_JSON" screenListHtml)" || return 1

  # baseline を <dir> に構築する（全チェックが一致する状態）
  build_baseline() {
    local dir="$1"
    rm -rf "$dir"
    mkdir -p "$(dirname "$dir/$SCREEN_MANIFEST_REL_T")" "$(dirname "$dir/$SCREEN_LIST_HTML_REL_T")" \
             "$dir/$SCREEN_UNIT_ROOT_T/screen-alpha/基本設計" "$dir/$SCREEN_UNIT_ROOT_T/screen-alpha/詳細設計" \
             "$dir/$SCREEN_UNIT_ROOT_T/screen-beta/基本設計" "$dir/$SCREEN_UNIT_ROOT_T/screen-beta/詳細設計"

    local manifest_json='{"screens":[
      {"screenId":"screen-alpha","screenKey":"alpha","screenNameGuess":"アルファ画面","confirmedScreenName":null},
      {"screenId":"screen-beta","screenKey":"beta","screenNameGuess":"ベータ画面","confirmedScreenName":null}
    ]}'
    printf '%s' "$manifest_json" | jq -c . > "$dir/$SCREEN_MANIFEST_REL_T"

    {
      echo '<html><body>'
      echo '<script type="application/json" id="screen-manifest">'
      printf '%s' "$manifest_json" | jq -c .
      echo '</script>'
      echo '</body></html>'
    } > "$dir/$SCREEN_LIST_HTML_REL_T"

    write_screen_page() { # <path> <name> <suffix> <commit-span>
      cat > "$1" <<EOF
<html><body>
<h1 class="pt-title" id="dp-hero-title">$2 $3</h1>
<span id="pt-footer-commit">$4</span>
<script type="application/json" id="page-data">{"sourceRef":"src/pages/Alpha.tsx:42"}</script>
</body></html>
EOF
    }
    write_screen_page "$dir/$SCREEN_UNIT_ROOT_T/screen-alpha/基本設計/画面基本設計書.html" "アルファ画面" "画面基本設計書" " · コミット番号: aaaaaaa"
    write_screen_page "$dir/$SCREEN_UNIT_ROOT_T/screen-alpha/詳細設計/画面詳細設計書.html" "アルファ画面" "画面詳細設計書" " · コミット番号: aaaaaaa"
    write_screen_page "$dir/$SCREEN_UNIT_ROOT_T/screen-beta/基本設計/画面基本設計書.html" "ベータ画面" "画面基本設計書" " · コミット番号: aaaaaaa"
    write_screen_page "$dir/$SCREEN_UNIT_ROOT_T/screen-beta/詳細設計/画面詳細設計書.html" "ベータ画面" "画面詳細設計書" " · コミット番号: aaaaaaa"

    cat > "$dir/$SCREEN_UNIT_ROOT_T/screen-alpha/詳細設計/画面詳細設計書.md" <<EOF
---
doc_id: screen-alpha
type: screen-detail-design
target_screen: アルファ画面
source_ref: $SHA_A
---
# アルファ画面 画面詳細設計書
EOF
    cat > "$dir/$SCREEN_UNIT_ROOT_T/screen-beta/詳細設計/画面詳細設計書.md" <<EOF
---
doc_id: screen-beta
type: screen-detail-design
target_screen: ベータ画面
source_ref: $SHA_A
---
# ベータ画面 画面詳細設計書
EOF

    cat > "$dir/index.html" <<EOF
<html><body>
<span id="pt-footer-commit"> · コミット番号: aaaaaaa</span>
</body></html>
EOF
  }

  # --- ケース1: 一致している状態で終了コード0 ---
  build_baseline "$t/c1"
  rc=0; out="$("$0" "$t/c1" 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^CLEAN:'; then
    pass=$((pass+1)); echo "  PASS: ケース1（一致状態は exit 0 で CLEAN）"
  else
    fail=$((fail+1)); echo "  FAIL: ケース1（exit ${rc}）: $out" >&2
  fi

  # --- ケース2: 画面名（一覧側）を1件書き換えて不一致を検出 ---
  build_baseline "$t/c2"
  jq '.screens[0].screenNameGuess = "アルファ画面2"' "$t/c2/$SCREEN_MANIFEST_REL_T" > "$t/c2/tmp.json" \
    && mv "$t/c2/tmp.json" "$t/c2/$SCREEN_MANIFEST_REL_T"
  rc=0; out="$("$0" "$t/c2" 2>&1)" || rc=$?
  if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q '種別=画面名-一覧 対象=alpha'; then
    pass=$((pass+1)); echo "  PASS: ケース2（一覧側の画面名不一致を検出）"
  else
    fail=$((fail+1)); echo "  FAIL: ケース2（exit ${rc}）: $out" >&2
  fi

  # --- ケース3: 画面詳細ページ側だけを書き換えて不一致を検出 ---
  build_baseline "$t/c3"
  sed -i.bak 's/アルファ画面 画面基本設計書/アルファ画面X 画面基本設計書/' "$t/c3/$SCREEN_UNIT_ROOT_T/screen-alpha/基本設計/画面基本設計書.html"
  rm -f "$t/c3/$SCREEN_UNIT_ROOT_T/screen-alpha/基本設計/画面基本設計書.html.bak"
  rc=0; out="$("$0" "$t/c3" 2>&1)" || rc=$?
  if [ "$rc" -eq 1 ] \
    && printf '%s' "$out" | grep -q '種別=画面名-詳細ページ 対象=screen-alpha:基本設計' \
    && ! printf '%s' "$out" | grep -q '種別=画面名-一覧'; then
    pass=$((pass+1)); echo "  PASS: ケース3（詳細ページ側だけの画面名不一致を検出。一覧側は無反応）"
  else
    fail=$((fail+1)); echo "  FAIL: ケース3（exit ${rc}）: $out" >&2
  fi

  # --- ケース4: 表示コミットを書き換えて不一致を検出 ---
  build_baseline "$t/c4"
  sed -i.bak 's/コミット番号: aaaaaaa/コミット番号: bbbbbbb/' "$t/c4/$SCREEN_UNIT_ROOT_T/screen-alpha/詳細設計/画面詳細設計書.html"
  rm -f "$t/c4/$SCREEN_UNIT_ROOT_T/screen-alpha/詳細設計/画面詳細設計書.html.bak"
  rc=0; out="$("$0" "$t/c4" 2>&1)" || rc=$?
  if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q '種別=表示コミット-画面 対象=screen-alpha:詳細設計'; then
    pass=$((pass+1)); echo "  PASS: ケース4（表示コミットの不一致を検出）"
  else
    fail=$((fail+1)); echo "  FAIL: ケース4（exit ${rc}）: $out" >&2
  fi

  # --- ケース4b: ポータル index.html 側の表示コミットを書き換えて不一致を検出（種別=表示コミット-ポータル） ---
  # ケース4は画面ページ側（種別=表示コミット-画面）だけを検証しており、今回追加した
  # screen_unit_root 不在ガードが誤って握りつぶしうる「種別=表示コミット-ポータル」側の
  # 検出経路には陽性検出のカバレッジが無かった。ガードは前提が揃っているときの検出を
  # 妨げてはならないため、ここで陽性側も固定する。
  build_baseline "$t/c4b"
  sed -i.bak 's/コミット番号: aaaaaaa/コミット番号: ccccccc/' "$t/c4b/index.html"
  rm -f "$t/c4b/index.html.bak"
  rc=0; out="$("$0" "$t/c4b" 2>&1)" || rc=$?
  if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q '種別=表示コミット-ポータル 対象=index.html'; then
    pass=$((pass+1)); echo "  PASS: ケース4b（ポータル index.html 側の表示コミット不一致を検出）"
  else
    fail=$((fail+1)); echo "  FAIL: ケース4b（exit ${rc}）: $out" >&2
  fi

  # --- ケース5: sourceRef（証跡パス）を書き換えても反応しないこと ---
  build_baseline "$t/c5"
  sed -i.bak 's#src/pages/Alpha.tsx:42#src/pages/Alpha.tsx:999#' "$t/c5/$SCREEN_UNIT_ROOT_T/screen-alpha/基本設計/画面基本設計書.html"
  rm -f "$t/c5/$SCREEN_UNIT_ROOT_T/screen-alpha/基本設計/画面基本設計書.html.bak"
  rc=0; out="$("$0" "$t/c5" 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^CLEAN:'; then
    pass=$((pass+1)); echo "  PASS: ケース5（sourceRef の書き換えは無反応・CLEAN のまま）"
  else
    fail=$((fail+1)); echo "  FAIL: ケース5（exit ${rc}）: $out" >&2
  fi

  # --- ケース6: マニフェスト不在で終了コード2 ---
  build_baseline "$t/c6"
  rm -f "$t/c6/$SCREEN_MANIFEST_REL_T"
  rc=0; "$0" "$t/c6" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 2 ]; then
    pass=$((pass+1)); echo "  PASS: ケース6（マニフェスト不在は exit 2）"
  else
    fail=$((fail+1)); echo "  FAIL: ケース6（exit ${rc}）" >&2
  fi

  # --- ケース7: screen_unit_root 自体が不在でも --commits-only は空期待値の誤検知にせず exit 2（SKIP） ---
  # index.html に正当な表示コミット値があっても、母集団（画面詳細設計書.md）がそもそも
  # 存在しない環境では「期待値=空」を確定できない。これを検知せず比較すると
  # 「期待値=空 実際値=非空」という誤検知の MISMATCH になる（本ファイルの回帰対象）。
  build_baseline "$t/c7"
  rm -rf "${t:?}/c7/${SCREEN_UNIT_ROOT_T:?}"
  rc=0; out="$("$0" "$t/c7" --commits-only 2>&1)" || rc=$?
  if [ "$rc" -eq 2 ] && ! printf '%s' "$out" | grep -q '^MISMATCH:'; then
    pass=$((pass+1)); echo "  PASS: ケース7（screen_unit_root 不在時の --commits-only は誤検知せず exit 2）"
  else
    fail=$((fail+1)); echo "  FAIL: ケース7（exit ${rc}）: $out" >&2
  fi

  echo "self-test: PASS=$pass FAIL=$fail"
  [ "$fail" -eq 0 ]
}

# ============================= CLI =============================

case "${1:-}" in
  --self-test) self_test; exit $? ;;
  "") usage ;;
esac

ROOT="$1"
[ -d "$ROOT" ] || { echo "ERROR: root が存在しない: $ROOT" >&2; exit 2; }
shift
ROOT="$(cd "$ROOT" && pwd -P)"

RUN_SCREENS=1
RUN_COMMITS=1
while [ $# -gt 0 ]; do
  case "$1" in
    --screens-only) RUN_COMMITS=0; shift ;;
    --commits-only) RUN_SCREENS=0; shift ;;
    *) usage ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq が必要" >&2; exit 2; }

LAYOUT_JSON="$(resolve_output_layout "$ROOT")" || exit 2
SCREEN_UNIT_ROOT="$(output_layout_get "$LAYOUT_JSON" screenUnitRoot)" || exit 2
SCREEN_LIST_HTML_REL="$(output_layout_get "$LAYOUT_JSON" screenListHtml)" || exit 2
SCREEN_MANIFEST_REL="$(output_layout_get "$LAYOUT_JSON" screenManifest)" || exit 2

if [ "$RUN_SCREENS" -eq 1 ]; then
  MANIFEST_PATH="$ROOT/$SCREEN_MANIFEST_REL"
  LIST_HTML_PATH="$ROOT/$SCREEN_LIST_HTML_REL"
  if [ ! -f "$MANIFEST_PATH" ]; then
    echo "NO-MANIFEST: screen-manifest.json が存在しない ($MANIFEST_PATH)" >&2
    exit 2
  fi
  check_screen_names "$ROOT" "$MANIFEST_PATH" "$LIST_HTML_PATH" "$SCREEN_UNIT_ROOT"
fi

if [ "$RUN_COMMITS" -eq 1 ]; then
  # 表示コミットの根拠（画面詳細設計書.md の source_ref）は screen_unit_root 配下にしか
  # 存在しない。このディレクトリ自体が無い環境（screens 側の前提不足と同じ状況）では
  # 検査対象の母集団が0件になり、expected_agg が空文字のまま確定してしまう。
  # ここで前提不足を検知せず check_commit_values を呼ぶと、index.html 側に正当な表示値
  # （例: 「画面ごとに異なる」）があるだけで「期待値=空 実際値=非空」という誤検知の
  # MISMATCH になる（縦書き誤検知と同種の、前提不足を考慮しない検査バグ）。
  # RUN_SCREENS 側のマニフェスト不在ガード（370行目付近）と同じ exit 2（SKIP）で揃える。
  if [ ! -d "$ROOT/$SCREEN_UNIT_ROOT" ]; then
    echo "NO-SCREEN-UNIT-ROOT: 画面単位文書のディレクトリが存在しない ($ROOT/$SCREEN_UNIT_ROOT)" >&2
    exit 2
  fi
  check_commit_values "$ROOT" "$SCREEN_UNIT_ROOT"
fi

if [ "${#MISMATCHES[@]}" -eq 0 ]; then
  echo "CLEAN: 画面名・表示コミットの値に不一致なし"
  exit 0
fi

for m in "${MISMATCHES[@]}"; do
  echo "$m"
done
echo "DRIFT: 定義（manifest.json / source_ref）と表示値がずれている。定義から再生成するか、意図した変更なら定義側を更新する" >&2
exit 1
