#!/usr/bin/env bash
# check-payload-references.sh — 配布物の説明文書の中の
# 相対参照が実在するファイルを指しているかを検査する
#
# 何を見るか:
#   delivery-payload/ と generation-engine/ 配下、README.md、配布対象の検証規約・
#   公開完遂規約の *.md を対象にする（*.html は対象外。理由は下の「対象外にすること」
#   を参照）。ただし次の3か所は走査対象から
#   除く。
#     - delivery-payload/templates/rules/ 配下: 「検証の結果を信用できるように
#       する指示書」がこのリポジトリ側の担当者に編集を禁じている範囲であり、
#       違反を見つけても自分では直せないため対象にしない。
#     - delivery-payload/templates/リバース検証/ 配下: 3.5節が扱う「様式の中の
#       見本用の画像」「記法の誤り」の対象であり、存在確認ではなく意図の確認・
#       記法の是正で扱う。
#     - generation-engine/samples/ 配下・generation-engine/samples-no-screen/ 配下:
#       納品先の仮想プロジェクトを描いた生成済みの見本であり、本文中の参照が
#       このリポジトリ自身の資料ではなく、納品先プロジェクトに将来生成される
#       想定のファイル（例: 依頼側の rule.html・src/ 配下のソース断片）を指す
#       ことが多い。これは check-delivery-doc-links.sh が docs/ を含むリンクを
#       意図的に見逃す設計にしている理由と同じであり、本検査でも同様に除外する。
#   本文中の次の2種の「参照の形で書かれたパス」だけを候補にする。
#     1. Markdown のリンク・画像: ](パス) — パスは空白・丸括弧を含まず、拡張子を持つもの
#     2. バッククォートで囲まれた、generation-engine/ または delivery-payload/ で
#        始まるリポジトリルート相対パス（拡張子を持つもの）
#
#   バッククォート囲みのパスのうち、generation-engine/・delivery-payload/ の
#   どちらの接頭辞も持たないもの（例: `references/phase-details.md`・
#   `scripts/recount-facts.sh`）は候補にしない。このリポジトリの文書は、直前の
#   文脈（言及中のスキル・ファイル）を暗黙の起点とした省略形のバッククォート
#   表記を多用する慣習があり（例: facts-schema.md 内の `scripts/recount-facts.sh`
#   は `.claude/skills/extracting-unit-facts-from-code/scripts/recount-facts.sh`
#   の省略形）、これはクリック可能なナビゲーション参照ではなく地の文の一部で
#   あるため、既存の check-skill-reference-paths.sh の ABS_RE と同じ「既知の
#   トップレベル接頭辞を持つものだけを対象にする」基準に合わせた。
#
# 対象外にすること（意図的）:
#   - *.html は対象外にする。テンプレートのプレースホルダ（{{BACK_LINK}} 等）や
#     生成物内のJS文字列結合（' + sanitizedUrl + ' 等）、ページ内アンカーへの
#     素の名前リンク（](画面遷移) 等）が大量に紛れ込み、拡張子を持たない
#     文字列まで候補になってしまうため、*.md に絞ることで実質的に排除する。
#   - 外部参照（http:// / https:// / mailto:）、ページ内アンカーのみの参照
#     （#で始まる）、ホーム配下の参照（~/ で始まる。このリポジトリの外を指す）
#     は候補にしない。
#   - 拡張子を持たない候補（画面名など、ファイルパスでない語句）は候補にしない。
#   - 値の末尾に付く # 以降のフラグメントと ? 以降のクエリは、実在確認の前に
#     切り落として解決する。
#
# 何を違反とするか:
#   候補のパスを、まずそのファイルのあるディレクトリからの相対として解決し、
#   実在しなければ次にリポジトリルートからの相対として解決する。どちらでも
#   実在しない場合だけを違反とする。
#
# 使い方:
#   check-payload-references.sh             delivery-payload・generation-engine を走査する
#   check-payload-references.sh --self-test 判定の妥当性を検査する
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

TARGETS=(
  "delivery-payload"
  "generation-engine"
  "README.md"
  ".claude/rules/always/verification/reverse-verification/rule.md"
  ".claude/rules/always/publish/complete/rule.md"
)

# パス本体: 空白・丸括弧・波括弧・引用符・プラス記号を含まず、末尾に拡張子を持つ。
PATH_BODY='[^][:space:]{}()"'"'"'+]+\.[A-Za-z0-9]+'
MD_RE="\\][(]${PATH_BODY}[)]"
BACKTICK_RE='`(generation-engine|delivery-payload)/[A-Za-z0-9_./-]+\.[A-Za-z0-9]+`'

collect_files() {
  local base="$1" t p
  for t in "${TARGETS[@]}"; do
    p="$base/$t"
    if [ -d "$p" ]; then
      find "$p" -type f -name '*.md' \
        -not -path "$base/delivery-payload/templates/rules/*" \
        -not -path "$base/delivery-payload/templates/リバース検証/*" \
        -not -path "$base/generation-engine/samples/*" \
        -not -path "$base/generation-engine/samples-no-screen/*" \
        2>/dev/null
    elif [ -f "$p" ]; then
      printf '%s\n' "$p"
    fi
  done
}

# 対象外（外部参照・アンカーのみ・ホーム配下）と判定する。
is_excluded() {
  case "$1" in
    http://*|https://*|mailto:*|\#*|"~"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# 1 ファイルから候補パスを抜き出す。
extract_candidates() {
  local f="$1"
  {
    grep -oE "$MD_RE" "$f" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//'
    grep -oE "$BACKTICK_RE" "$f" 2>/dev/null | sed -E 's/^`//; s/`$//'
  } | LC_ALL=C sort -u
}

scan() {
  local base="$1"
  local total=0 violations=0 f d p anchor resolved
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    d="$(dirname "$f")"
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      is_excluded "$p" && continue
      total=$((total + 1))
      anchor="${p%%#*}"
      anchor="${anchor%%\?*}"
      [ -z "$anchor" ] && continue
      resolved="$(cd "$d" 2>/dev/null && realpath "$anchor" 2>/dev/null)" || resolved=""
      if [ -z "$resolved" ] || [ ! -e "$resolved" ]; then
        resolved="$(cd "$base" 2>/dev/null && realpath "$anchor" 2>/dev/null)" || resolved=""
      fi
      if [ -z "$resolved" ] || [ ! -e "$resolved" ]; then
        echo "[FAIL] $f -> $p"
        violations=$((violations + 1))
      fi
    done < <(extract_candidates "$f")
  done < <(collect_files "$base" | LC_ALL=C sort -u)
  echo "走査 $total 件 / 違反 $violations 件"
  [ "$violations" -eq 0 ]
}

self_test() {
  local tmp pass=0 fail=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/payload-references.XXXXXX" 2>/dev/null)" || tmp=""
  if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
    echo "[FAIL] 一時ディレクトリを作れないため自己検査を実行できない"
    echo "実行 1 件 / 合格 0 件 / 不合格 1 件"
    return 1
  fi

  local base="$tmp/base"

  # ケース1: 実在するファイルへのMarkdownリンクは違反にしない
  mkdir -p "$base/delivery-payload/references"
  : > "$base/delivery-payload/references/target.md"
  printf '%s\n' '参照: [対象](target.md)' > "$base/delivery-payload/references/source.md"
  if _gt_out1="$(scan "$base" 2>&1)"; then
    echo "[PASS] 実在するファイルへのMarkdownリンクは違反にしない"; pass=$((pass + 1))
  else
    echo "[FAIL] 実在するファイルへのMarkdownリンクは違反にしない"; fail=$((fail + 1))
    printf '%s\n' "$_gt_out1" | sed 's/^/    /' >&2
  fi
  rm -rf "$base"

  # ケース2: 実在しないファイルへのMarkdownリンクを違反と判定する
  mkdir -p "$base/delivery-payload/references"
  printf '%s\n' '参照: [不在](absent.md)' > "$base/delivery-payload/references/source.md"
  if _gt_out2="$(scan "$base" 2>&1)"; then
    echo "[FAIL] 実在しないファイルへのMarkdownリンクを違反と判定する"; fail=$((fail + 1))
    printf '%s\n' "$_gt_out2" | sed 's/^/    /' >&2
  else
    echo "[PASS] 実在しないファイルへのMarkdownリンクを違反と判定する"; pass=$((pass + 1))
  fi
  rm -rf "$base"

  # ケース3: *.html は対象外にする（テンプレートのプレースホルダ等の誤検出を防ぐ）
  mkdir -p "$base/generation-engine/samples"
  printf '%s\n' '<a href="{{BACK_LINK}}">戻る</a>' > "$base/generation-engine/samples/page.html"
  if _gt_out3="$(scan "$base" 2>&1)"; then
    echo "[PASS] *.htmlは対象外にする"; pass=$((pass + 1))
  else
    echo "[FAIL] *.htmlは対象外にする"; fail=$((fail + 1))
    printf '%s\n' "$_gt_out3" | sed 's/^/    /' >&2
  fi
  rm -rf "$base"

  # ケース4: バッククォートで囲まれた実在しないパスを違反と判定する
  mkdir -p "$base/generation-engine/scripts"
  printf '%s\n' '設計判断は `generation-engine/scripts/absent.sh` を参照する' > "$base/generation-engine/scripts/note.md"
  if _gt_out4="$(scan "$base" 2>&1)"; then
    echo "[FAIL] バッククォートの実在しないパスを違反と判定する"; fail=$((fail + 1))
    printf '%s\n' "$_gt_out4" | sed 's/^/    /' >&2
  else
    echo "[PASS] バッククォートの実在しないパスを違反と判定する"; pass=$((pass + 1))
  fi
  rm -rf "$base"

  # ケース5: 外部参照・アンカーのみ・ホーム配下は対象外にする
  mkdir -p "$base/delivery-payload"
  printf '%s\n' '[外部](https://example.com/x.md) [アンカー](#top) [ホーム](~/agent-home/foo.md)' > "$base/delivery-payload/note.md"
  if _gt_out5="$(scan "$base" 2>&1)"; then
    echo "[PASS] 外部・アンカーのみ・ホーム配下は対象外にする"; pass=$((pass + 1))
  else
    echo "[FAIL] 外部・アンカーのみ・ホーム配下は対象外にする"; fail=$((fail + 1))
    printf '%s\n' "$_gt_out5" | sed 's/^/    /' >&2
  fi
  rm -rf "$base"

  # ケース6: リポジトリルートからの相対でも解決できれば違反にしない
  mkdir -p "$base/generation-engine/scripts/nested" "$base/delivery-payload/references"
  : > "$base/delivery-payload/references/root-relative.md"
  printf '%s\n' '[ルート相対](delivery-payload/references/root-relative.md)' > "$base/generation-engine/scripts/nested/deep.md"
  if _gt_out6="$(scan "$base" 2>&1)"; then
    echo "[PASS] リポジトリルート起点でも解決できれば違反にしない"; pass=$((pass + 1))
  else
    echo "[FAIL] リポジトリルート起点でも解決できれば違反にしない"; fail=$((fail + 1))
    printf '%s\n' "$_gt_out6" | sed 's/^/    /' >&2
  fi
  rm -rf "$base"

  # ケース7: 拡張子を持たない候補（画面名などの素の語句）は対象外にする
  mkdir -p "$base/delivery-payload/templates"
  printf '%s\n' '[画面遷移](画面遷移)' > "$base/delivery-payload/templates/detail-t4-diagram.md"
  if _gt_out7="$(scan "$base" 2>&1)"; then
    echo "[PASS] 拡張子を持たない候補は対象外にする"; pass=$((pass + 1))
  else
    echo "[FAIL] 拡張子を持たない候補は対象外にする"; fail=$((fail + 1))
    printf '%s\n' "$_gt_out7" | sed 's/^/    /' >&2
  fi
  rm -rf "$base"

  # ケース8: 対象が1件も無い場合は合格と判定する
  mkdir -p "$base"
  if _gt_out8="$(scan "$base" 2>&1)"; then
    echo "[PASS] 対象が1件も無い場合は合格と判定する"; pass=$((pass + 1))
  else
    echo "[FAIL] 対象が1件も無い場合は合格と判定する"; fail=$((fail + 1))
    printf '%s\n' "$_gt_out8" | sed 's/^/    /' >&2
  fi
  rm -rf "$base"

  rm -rf "$tmp"
  echo "実行 $((pass + fail)) 件 / 合格 $pass 件 / 不合格 $fail 件"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
  --self-test)
    self_test
    exit $?
    ;;
  "")
    scan "$REPO_ROOT"
    exit $?
    ;;
  *)
    echo "使い方: $(basename "$0") [--self-test]" >&2
    exit 2
    ;;
esac
