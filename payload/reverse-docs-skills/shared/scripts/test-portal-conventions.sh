#!/usr/bin/env bash
# ポータル HTML 規約の自動検証スクリプト
# 使い方: bash test-portal-conventions.sh <HTML ファイルまたはディレクトリ>
# 終了コード: 全 PASS → 0, 1つでも FAIL → 1

PASS=0
FAIL=0
SKIP=0

pass() { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }
skip() { SKIP=$((SKIP+1)); echo "  SKIP: $1"; }

OLD_COLORS_LIGHT='#F0EDE3|#DAD5C5|#BFB9A6|#3F4F8E|#5A6BAE|#E6E9F3|#BAC2DC|#9B7A1F|#F5EFD9|#DDC68A|#9B3F2D|#F5E2DC'
OLD_COLORS_DARK='#232730|#353944|#4A4F5C|#8FA3DB|#A8B8E5|#2A2E47|#4C5680|#D4B45D|#3D3520|#7A6633|#D4836E|#3F2620'

check_file() {
  local f="$1"
  echo ""
  echo "=== $f ==="

  if grep -q 'class="pm-page"' "$f" 2>/dev/null; then
    skip "ポータルトップ（pm-page）は対象外"
    return
  fi

  local is_doc_viewer=0
  grep -q 'class="doc-main"' "$f" 2>/dev/null && is_doc_viewer=1

  local old_l; old_l=$(grep -cE "$OLD_COLORS_LIGHT" "$f" 2>/dev/null || true)
  [ "$old_l" -eq 0 ] && pass "色トークン-旧値禁止（ライト）" || fail "色トークン-旧値禁止（ライト）: ${old_l}件"

  local old_d; old_d=$(grep -cE "$OLD_COLORS_DARK" "$f" 2>/dev/null || true)
  [ "$old_d" -eq 0 ] && pass "色トークン-旧値禁止（ダーク）" || fail "色トークン-旧値禁止（ダーク）: ${old_d}件"

  grep -q '#F6F8FA' "$f" 2>/dev/null && pass "色トークン-新値存在（panel-2）" || fail "色トークン-新値存在（panel-2）"

  if grep -q 'prefers-color-scheme: dark' "$f" 2>/dev/null && grep -q 'data-theme="dark"' "$f" 2>/dev/null; then
    pass "テーマ-ダーク定義"
  else
    fail "テーマ-ダーク定義"
  fi

  if [ "$is_doc_viewer" -eq 1 ]; then
    skip "全画面-高さ固定（文書ビューア型は適用除外）"
    skip "全画面-min-height禁止（文書ビューア型は適用除外）"
    skip "全画面-overflow制御（文書ビューア型は適用除外）"
    skip "全画面-スクロール領域（文書ビューア型は適用除外）"
    skip "sticky-thead（文書ビューア型は適用除外）"
  else
    grep -q 'height: 100vh' "$f" 2>/dev/null && pass "全画面-高さ固定" || fail "全画面-高さ固定"
    grep -q 'min-height: 100vh' "$f" 2>/dev/null && fail "全画面-min-height禁止（残存）" || pass "全画面-min-height禁止"

    if grep -qE 'overflow:\s*hidden|overflow: hidden' "$f" 2>/dev/null; then
      pass "全画面-overflow制御"
    else
      fail "全画面-overflow制御"
    fi

    if grep -qE 'overflow-y:\s*auto|overflow-y: auto' "$f" 2>/dev/null; then
      pass "全画面-スクロール領域"
    else
      fail "全画面-スクロール領域"
    fi

    if grep -q '<table' "$f" 2>/dev/null; then
      grep -qE 'position:\s*sticky' "$f" 2>/dev/null && pass "sticky-thead" || fail "sticky-thead"
    else
      skip "sticky-thead（テーブルなし）"
    fi
  fi

  local footer_content
  footer_content=$(awk '/<footer/,/<\/footer>/' "$f" 2>/dev/null)
  if [ -z "$footer_content" ]; then
    pass "フッター-空確認（footerタグなし）"
  elif printf '%s\n' "$footer_content" | grep -qE 'スキルにより生成|により自動生成|設計スキル群'; then
    fail "フッター-空確認"
  else
    pass "フッター-空確認"
  fi

  if grep -qE 'id="unit-manifest"|id="screen-manifest"' "$f" 2>/dev/null; then
    # 最初の thead のみカウント
    local th_count
    th_count=$(sed -n '/<thead/,/<\/thead/{p;/<\/thead/q;}' "$f" | grep -co '<th' || true)
    [ "$th_count" -le 5 ] && pass "一覧-列数上限（${th_count}列）" || fail "一覧-列数上限（${th_count}列）"

    if grep -q 'detail-group-label' "$f" 2>/dev/null && grep -q 'evidence' "$f" 2>/dev/null; then
      pass "一覧-展開グループ分離"
    else
      fail "一覧-展開グループ分離"
    fi

    if grep -q '<details.*class="module-group"' "$f" 2>/dev/null; then
      if grep -q 'unitKind.*feature' "$f" 2>/dev/null; then
        pass "一覧-details禁止（feature-listカテゴリ別は許可）"
      else
        fail "一覧-details禁止（残存）"
      fi
    else
      pass "一覧-details禁止"
    fi

    grep -q 'class="common-files"' "$f" 2>/dev/null && fail "一覧-common-files禁止" || pass "一覧-common-files禁止"

    if grep -qE 'unresolved.*(empty|has-items)' "$f" 2>/dev/null; then
      pass "unresolved-条件付き"
    else
      fail "unresolved-条件付き"
    fi
  fi
}

check_matrix_template_tokens() {
  local script_dir templates_dir template definitions markers
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  templates_dir="$script_dir/../templates/matrix"
  echo ""
  echo "=== matrix template token contract ==="
  for template in \
    permission-screen-matrix-template.html \
    permission-function-matrix-template.html \
    crud-matrix-template.html \
    traceability-template.html; do
    if [ ! -f "$templates_dir/$template" ]; then
      fail "matrix token-template実在: $template"
      continue
    fi
    definitions="$(grep -cE '^[[:space:]]*--[a-z0-9-]+[[:space:]]*:' "$templates_dir/$template" 2>/dev/null || true)"
    markers="$(grep -cF '/* TOKENS_CSS */' "$templates_dir/$template" 2>/dev/null || true)"
    if [ "$definitions" -eq 0 ]; then
      pass "matrix token実値定義0件: $template"
    else
      fail "matrix token実値定義0件: $template（${definitions}件残存）"
    fi
    if [ "$markers" -eq 1 ]; then
      pass "matrix token注入placeholder 1件: $template"
    else
      fail "matrix token注入placeholder 1件: $template（${markers}件）"
    fi
  done
}

target="${1:-.}"
if [ -d "$target" ]; then
  while IFS= read -r f; do
    check_file "$f"
  done < <(find "$target" -name '*.html' -not -path '*/node_modules/*' -not -path '*/fixtures/*' | sort)
else
  check_file "$target"
fi

check_matrix_template_tokens

echo ""
echo "========================================="
echo "結果: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"
echo "========================================="
[ "$FAIL" -gt 0 ] && exit 1
exit 0
