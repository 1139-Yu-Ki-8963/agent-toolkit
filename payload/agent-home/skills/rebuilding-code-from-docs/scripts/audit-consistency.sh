#!/usr/bin/env bash
# audit-consistency.sh — Phase 2 の機械チェック
#
# 用途: 画面基本設計書の内部整合性を機械的にチェックする。
#   (a) §2 機能一覧表の機能キー集合と、frontmatter の unit_test_sheet /
#       integration_test_sheet が指す観点表の機能キー集合の突合（両方向一致）
#   (b) 未記入プレースホルダ `<...>` の検出（HTML コメント内は除外）
#   (c) 連番キー検出（意味キー規約違反の WARN）
#
# 引数: $1 = 画面ディレクトリ（画面基本設計書.md を含むディレクトリ）
# 終了コード: 違反あり(a,b) = 1 / WARN のみ(c) = 0 / 正常 = 0
#
# 使い方:
#   ./audit-consistency.sh <画面ディレクトリ>

set -euo pipefail

SCREEN_DIR="${1:-}"
if [ -z "$SCREEN_DIR" ]; then
  echo "使い方: $0 <画面ディレクトリ>" >&2
  exit 1
fi
if [ ! -d "$SCREEN_DIR" ]; then
  echo "エラー: ディレクトリが存在しません: $SCREEN_DIR" >&2
  exit 1
fi

# 設計書の特定: 画面基本設計書.md を第一候補とし、無ければ frontmatter に
# `type: screen-basic-design` を持つ .md を探す。観点表にも doc_id があるため
# 「doc_id を含む最初の .md」では観点表を誤選択しうる（実証済みバグ）。
DESIGN_DOC=""
if [ -f "$SCREEN_DIR/画面基本設計書.md" ]; then
  DESIGN_DOC="$SCREEN_DIR/画面基本設計書.md"
else
  for cand in "$SCREEN_DIR"/*.md; do
    if [ -f "$cand" ] && grep -qE '^type: *screen-basic-design *$' "$cand" 2>/dev/null; then
      DESIGN_DOC="$cand"
      break
    fi
  done
fi
if [ -z "$DESIGN_DOC" ]; then
  echo "エラー: 設計書を特定できません（画面基本設計書.md が無く、type: screen-basic-design を持つ .md も見つかりません）: $SCREEN_DIR" >&2
  exit 1
fi

echo "対象設計書: $DESIGN_DOC"
VIOLATIONS=0
WARNINGS=0

# --- frontmatter から観点表パスを取得 ---
frontmatter_value() {
  local key="$1"
  awk -v k="$key" '
    /^---$/ { c++; next }
    c==1 && $0 ~ "^"k":" { sub("^"k": *", ""); print; exit }
  ' "$DESIGN_DOC"
}

# BSD realpath（macOS）には -m が無いため、cd + pwd によるポータブルな解決を行う。
# 相対パスの親ディレクトリが存在しない場合は空文字を返す。
resolve_rel_path() {
  local base_dir="$1" rel="$2" rel_dir rel_base abs_dir
  [ -z "$rel" ] && return 1
  rel_dir="$(dirname "$rel")"
  rel_base="$(basename "$rel")"
  if [ -d "$base_dir/$rel_dir" ]; then
    abs_dir="$(cd "$base_dir/$rel_dir" && pwd)"
    printf '%s/%s\n' "$abs_dir" "$rel_base"
    return 0
  fi
  return 1
}

UNIT_SHEET_REL="$(frontmatter_value unit_test_sheet)"
INTEG_SHEET_REL="$(frontmatter_value integration_test_sheet)"
UNIT_SHEET="$(resolve_rel_path "$SCREEN_DIR" "$UNIT_SHEET_REL" || true)"
INTEG_SHEET="$(resolve_rel_path "$SCREEN_DIR" "$INTEG_SHEET_REL" || true)"

# --- (a) §2 機能一覧表 × 観点表の機能キー集合突合（両方向一致） ---
echo ""
echo "[検査 a] §2 機能一覧表 × 観点表 の機能キーの集合突合（両方向一致）"

# §2.1 機能一覧表の行数（先頭列 = キー。ヘッダ/区切り行/空行を除く）
FUNC_KEYS=$(awk '
  /^## §2/ { in_sec=1 }
  /^## §3/ { in_sec=0 }
  in_sec && /^\|/ {
    line=$0
    gsub(/^\| */, "", line)
    split(line, cols, "|")
    key=cols[1]; gsub(/^ +| +$/, "", key)
    if (key != "" && key != "キー" && key !~ /^-+$/) print key
  }
' "$DESIGN_DOC" | sort -u)
FUNC_COUNT=$(printf '%s\n' "$FUNC_KEYS" | grep -c . || true)
echo "  §2 機能一覧表の機能キー数: $FUNC_COUNT"

# 観点表ファイルにはテストサイズ対応表・本書に書かないもの・観点の導出元マップ等の
# ガイドテーブルが「## 観点表」セクションの前後に存在する（テンプレート準拠）。
# これらの先頭列（small/medium・書かない内容 等）まで機能キーとして拾うと、
# §2 に無いキーとして誤検出（EXTRA_IN_SHEETS）する実バグがあったため、
# 「## 観点表」見出し配下（次の "## " 見出し手前まで）のテーブルのみを対象にする。
extract_sheet_keys() {
  local sheet="$1"
  [ -f "$sheet" ] || return 0
  awk '
    /^## 観点表/ { in_sec=1; next }
    /^## / && in_sec { in_sec=0 }
    in_sec && /^\|/ {
      line=$0
      gsub(/^\| */, "", line)
      split(line, cols, "|")
      key=cols[1]; gsub(/^ +| +$/, "", key)
      if (key != "" && key !~ /^-+$/ && key !~ /^(キー|観点|ID)$/) print key
    }
  ' "$sheet" | sort -u
}

UNIT_KEYS=""
INTEG_KEYS=""

if [ -f "$UNIT_SHEET" ]; then
  UNIT_KEYS="$(extract_sheet_keys "$UNIT_SHEET")"
  UNIT_COUNT=$(printf '%s\n' "$UNIT_KEYS" | grep -c . || true)
  echo "  単体テスト観点表 ($UNIT_SHEET_REL) のキー行数: $UNIT_COUNT"
else
  echo "  WARN: 単体テスト観点表が見つかりません ($UNIT_SHEET_REL)" >&2
  WARNINGS=$((WARNINGS + 1))
fi

if [ -f "$INTEG_SHEET" ]; then
  INTEG_KEYS="$(extract_sheet_keys "$INTEG_SHEET")"
  INTEG_COUNT=$(printf '%s\n' "$INTEG_KEYS" | grep -c . || true)
  echo "  結合テスト観点表 ($INTEG_SHEET_REL) のキー行数: $INTEG_COUNT"
else
  echo "  WARN: 結合テスト観点表が見つかりません ($INTEG_SHEET_REL)" >&2
  WARNINGS=$((WARNINGS + 1))
fi

if [ "$FUNC_COUNT" -eq 0 ]; then
  echo "  違反: §2 機能一覧表にキーが 1 件もありません" >&2
  VIOLATIONS=$((VIOLATIONS + 1))
fi

# --- 機能キーと観点表キーの実突合 ---
# 観点表が単体/結合の 2 枚構成でも、§2 の各機能キーが「少なくとも一方」の
# 観点表に出現すればよい（単純な総数比較は 2 枚構成で必ずずれるため行わない）。
# 逆に観点表側にしか無いキーは機能一覧の記載漏れとして違反にする。
if [ -f "$UNIT_SHEET" ] || [ -f "$INTEG_SHEET" ]; then
  ALL_SHEET_KEYS="$(printf '%s\n%s\n' "$UNIT_KEYS" "$INTEG_KEYS" | grep . | sort -u || true)"
  FUNC_KEYS_NONEMPTY="$(printf '%s\n' "$FUNC_KEYS" | grep . || true)"
  MISSING_IN_SHEETS="$(comm -23 <(printf '%s\n' "$FUNC_KEYS_NONEMPTY") <(printf '%s\n' "$ALL_SHEET_KEYS") || true)"
  EXTRA_IN_SHEETS="$(comm -13 <(printf '%s\n' "$FUNC_KEYS_NONEMPTY") <(printf '%s\n' "$ALL_SHEET_KEYS") || true)"

  if [ -n "$MISSING_IN_SHEETS" ]; then
    echo "  違反: 観点表未整備のキー（§2 にあるが単体/結合いずれの観点表にも無い）:" >&2
    printf '%s\n' "$MISSING_IN_SHEETS" | sed 's/^/    - /' >&2
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
  if [ -n "$EXTRA_IN_SHEETS" ]; then
    echo "  違反: 機能一覧の記載漏れ（観点表にあるが §2 に無いキー）:" >&2
    printf '%s\n' "$EXTRA_IN_SHEETS" | sed 's/^/    - /' >&2
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
  if [ -z "$MISSING_IN_SHEETS" ] && [ -z "$EXTRA_IN_SHEETS" ]; then
    echo "  §2 機能キーと観点表キーの突合 OK（過不足なし）"
  fi
else
  echo "  観点表が 1 枚も見つからないためキー突合をスキップします（WARN 済み）"
fi

# --- (b) 未記入プレースホルダ検出 ---
echo ""
echo "[検査 b] 未記入プレースホルダ検出（HTML コメント外の <...>）"

PLACEHOLDER_LINES=$(awk '
  /<!--/ { in_comment=1 }
  {
    line=$0
    if (in_comment) {
      if (line ~ /-->/) { in_comment=0 }
      next
    }
    if (line ~ /<[^\/!][^>]*>/ && line ~ /<[^>]+>/) {
      # frontmatter のプレースホルダ行 <値> のような単純表現を対象
      if (line ~ /<[^<>]+>/) print NR": "line
    }
  }
' "$DESIGN_DOC" | grep -E '<[^<>]+>' || true)

if [ -n "$PLACEHOLDER_LINES" ]; then
  PLACEHOLDER_COUNT=$(printf '%s\n' "$PLACEHOLDER_LINES" | grep -c .)
  echo "  違反: 未記入プレースホルダが $PLACEHOLDER_COUNT 件見つかりました" >&2
  printf '%s\n' "$PLACEHOLDER_LINES" | head -20 >&2
  VIOLATIONS=$((VIOLATIONS + 1))
else
  echo "  未記入プレースホルダなし"
fi

# --- (c) 連番キー検出（WARN） ---
echo ""
echo "[検査 c] 連番キー検出（意味キー規約違反の疑い・WARN）"

SEQ_KEYS=$(grep -nE '\b[A-Z]{1,4}-[0-9]+\b' "$DESIGN_DOC" | grep -viE 'utf-8|sha-256|iso-8601' || true)
ID_COLUMNS=$(grep -nE '^\| *ID *\|' "$DESIGN_DOC" || true)

if [ -n "$SEQ_KEYS" ] || [ -n "$ID_COLUMNS" ]; then
  echo "  WARN: 連番キー・ID 列の疑いがあります（意味キー規約 semantic-key-rules 参照）" >&2
  [ -n "$SEQ_KEYS" ] && printf '%s\n' "$SEQ_KEYS" >&2
  [ -n "$ID_COLUMNS" ] && printf '%s\n' "$ID_COLUMNS" >&2
  WARNINGS=$((WARNINGS + 1))
else
  echo "  連番キー・ID 列なし"
fi

# --- 結果集計 ---
echo ""
echo "=== 検査結果 ==="
echo "違反: $VIOLATIONS 件 / WARN: $WARNINGS 件"

if [ "$VIOLATIONS" -gt 0 ]; then
  exit 1
fi
exit 0
