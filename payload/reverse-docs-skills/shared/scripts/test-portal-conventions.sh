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

OLD_COLORS_LIGHT='#F6F8FA|#D1D9E0|#AFB8C1|#0969DA|#218BFF|#DDF4FF|#54AEFF|#BC4C00|#FFF1E5|#1A7F37|#DAFBE1|#CF222E'
OLD_COLORS_DARK='#15171C|#1C1F26|#21262D|#30363D|#484F58|#E8E5DC|#B6B3AB|#888784|#58A6FF|#79C0FF|#132D4B|#1F6FEB'

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

  if grep -q '#0F1217' "$f" 2>/dev/null && grep -q '#4CC2FE' "$f" 2>/dev/null && grep -q '#FF6E4F' "$f" 2>/dev/null; then
    pass "色トークン-新値存在"
  else
    fail "色トークン-新値存在"
  fi

  if grep -q 'prefers-color-scheme' "$f" 2>/dev/null && grep -q 'data-theme="dark"' "$f" 2>/dev/null && grep -q 'data-theme="light"' "$f" 2>/dev/null; then
    pass "テーマ-定義"
  else
    fail "テーマ-定義"
  fi

  grep -q 'class="pt-sidebar"' "$f" 2>/dev/null && pass "共通シェル-サイドバー" || fail "共通シェル-サイドバー"

  grep -q 'background-size' "$f" 2>/dev/null && pass "共通シェル-方眼紙" || fail "共通シェル-方眼紙"

  local radius_count
  radius_count=$(grep -cE 'border-radius:[[:space:]]*[^0[:space:];]' "$f" 2>/dev/null || true)
  [ "$radius_count" -eq 0 ] && pass "角丸-ゼロ" || fail "角丸-ゼロ: ${radius_count}件"

  local shadow_count
  shadow_count=$(grep -cE 'box-shadow:[^;]*[0-9]px[[:space:]]+[-0-9.]+px[[:space:]]+[1-9]' "$f" 2>/dev/null || true)
  [ "$shadow_count" -eq 0 ] && pass "影-オフセットのみ" || fail "影-オフセットのみ: ${shadow_count}件"

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

    if grep -qE 'overflow-y:\s*auto|overflow:\s*auto' "$f" 2>/dev/null; then
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
    [ "$th_count" -le 6 ] && pass "一覧-列数上限（${th_count}列）" || fail "一覧-列数上限（${th_count}列）"

    if grep -q 'detail-group-label' "$f" 2>/dev/null && grep -q 'evidence' "$f" 2>/dev/null; then
      pass "一覧-展開グループ分離"
    else
      fail "一覧-展開グループ分離"
    fi

    if grep -q '<details.*class="module-group"' "$f" 2>/dev/null; then
      if grep -q 'data-split-axis="[^"]\+"' "$f" 2>/dev/null; then
        pass "一覧-details禁止（分割軸の宣言ありは許可）"
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

    if grep -qE 'class="unresolved has-items' "$f" 2>/dev/null; then
      grep -qF 'class="unresolved has-items pt-callout pt-callout--warning"' "$f" \
        && pass "unresolved-非空警告コールアウト" \
        || fail "unresolved-非空警告コールアウト"
    else
      grep -qE 'class="unresolved empty[^"]*pt-callout' "$f" \
        && fail "unresolved-空状態は非警告" \
        || pass "unresolved-空状態は非警告"
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

check_callout_contract() {
  local script_dir templates_dir shell_css representative builder template guide
  local material_symbols_href expected_font_sha shell_font_sha representative_font_sha
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  templates_dir="$script_dir/../templates"
  shell_css="$templates_dir/partials/shell.css"
  representative="$script_dir/../samples/一覧/API一覧/API一覧.html"
  material_symbols_href='https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined&amp;icon_names=info,priority_high,warning&amp;display=block'
  expected_font_sha='8f1b843abe398437ce5b3194a9f060f45534414e1fd6bced2521d39ca3d5a778'
  shell_font_sha="$(grep -o 'data:font/ttf;base64,[^"]*' "$shell_css" | head -1 | cut -d, -f2- | base64 --decode | shasum -a 256 | awk '{print $1}')"
  representative_font_sha="$(grep -o 'data:font/ttf;base64,[^"]*' "$representative" | head -1 | cut -d, -f2- | base64 --decode | shasum -a 256 | awk '{print $1}')"

  echo ""
  echo "=== importance callout contract ==="

  if grep -qF '.pt-callout {' "$shell_css" \
    && grep -qF '.pt-callout--caution {' "$shell_css" \
    && grep -qF '.pt-callout--warning {' "$shell_css" \
    && grep -qF '.pt-callout--important {' "$shell_css" \
    && grep -qF 'box-shadow: inset 5px 0 0 var(--callout-color)' "$shell_css" \
    && grep -qF '.pt-callout__icon {' "$shell_css" \
    && grep -A2 -F '.pt-callout__icon {' "$shell_css" | grep -qF 'display: none' \
    && grep -qF 'font-family: "Material Symbols Outlined Local"' "$shell_css" \
    && grep -qF 'data:font/ttf;base64,' "$shell_css" \
    && grep -qF 'font-family: "Material Symbols Outlined", "Material Symbols Outlined Local"' "$shell_css" \
    && [ "$shell_font_sha" = "$expected_font_sha" ] \
    && grep -qF '.pt-callout > :first-child > .pt-callout__icon { display: inline-block; }' "$shell_css" \
    && grep -qF -- '--callout-color: var(--accent)' "$shell_css" \
    && grep -qF -- '--callout-color: var(--stamp)' "$shell_css" \
    && grep -qF -- '--callout-color: var(--green)' "$shell_css"; then
    pass "コールアウト-3重要度CSS"
  else
    fail "コールアウト-3重要度CSS"
  fi

  for builder in \
    "$script_dir/unit-list/build-unit-list.sh" \
    "$script_dir/unit-list/build-screen-list.sh" \
    "$script_dir/unit-list/build-feature-list.sh"; do
    if grep -qF 'unresolved_class="has-items pt-callout pt-callout--warning"' "$builder" \
      && grep -qF 'unresolved_class="empty"' "$builder" \
      && ! grep -qF '単一ファイル自己完結' "$builder"; then
      pass "コールアウト-要確認事項への生成規律: $(basename "$builder")"
    else
      fail "コールアウト-要確認事項への生成規律: $(basename "$builder")"
    fi
  done

  for template in \
    "$templates_dir/unit-list/unit-list-template.html" \
    "$templates_dir/unit-list/screen-list-template.html" \
    "$templates_dir/unit-list/feature-list-template.html"; do
    if grep -qF "$material_symbols_href" "$template" \
      && grep -qF '<span class="material-symbols-outlined pt-callout__icon" aria-hidden="true">warning</span>' "$template" \
      && ! grep -qF '外部リソース(CDN・フォント・画像)は一切使わない' "$template"; then
      pass "コールアウト-Material Symbols規律: $(basename "$template")"
    else
      fail "コールアウト-Material Symbols規律: $(basename "$template")"
    fi
  done

  for guide in \
    "$script_dir/../../.claude/skills/generating-api-list-for-reverse-docs/references/generating-api-list-for-reverse-docs-guide.html" \
    "$script_dir/../../.claude/skills/generating-screen-list-for-reverse-docs/references/generating-screen-list-for-reverse-docs-guide.html" \
    "$script_dir/../../.claude/skills/generating-feature-list-for-reverse-docs/references/generating-feature-list-for-reverse-docs-guide.html" \
    "$script_dir/../../.claude/skills/generating-table-list-for-reverse-docs/references/generating-table-list-for-reverse-docs-guide.html" \
    "$script_dir/../../.claude/skills/generating-batch-list-for-reverse-docs/references/generating-batch-list-for-reverse-docs-guide.html" \
    "$script_dir/../../.claude/skills/generating-report-list-for-reverse-docs/references/generating-report-list-for-reverse-docs-guide.html" \
    "$script_dir/../../.claude/skills/generating-external-list-for-reverse-docs/references/generating-external-list-for-reverse-docs-guide.html"; do
    if grep -qF 'Material Symbols OutlinedのGoogle Fonts CDNだけを許可する' "$guide" \
      && ! grep -qF '外部リソース（CDN・画像・link）は一切使わず' "$guide"; then
      pass "コールアウト-一覧ガイドの外部依存規律: $(basename "$guide")"
    else
      fail "コールアウト-一覧ガイドの外部依存規律: $(basename "$guide")"
    fi
  done

  if grep -qF 'class="unresolved has-items pt-callout pt-callout--warning"' "$representative" \
    && grep -qF "$material_symbols_href" "$representative" \
    && grep -qF '<span class="material-symbols-outlined pt-callout__icon" aria-hidden="true">warning</span>' "$representative" \
    && [ "$representative_font_sha" = "$expected_font_sha" ] \
    && ! grep -qF '外部リソース(CDN・フォント・画像)は一切使わない' "$representative"; then
    pass "コールアウト-代表生成HTMLへの適用"
  else
    fail "コールアウト-代表生成HTMLへの適用"
  fi

  if grep -qF '| 注意 | `.pt-callout.pt-callout--caution` | `info` |' "$script_dir/../../.claude/rules/scoped/portal/page-conventions/rule.md" \
    && grep -qF '| 警告 | `.pt-callout.pt-callout--warning` | `warning` |' "$script_dir/../../.claude/rules/scoped/portal/page-conventions/rule.md" \
    && grep -qF '| 重要 | `.pt-callout.pt-callout--important` | `priority_high` |' "$script_dir/../../.claude/rules/scoped/portal/page-conventions/rule.md"; then
    pass "コールアウト-重要度とアイコンの対応規律"
  else
    fail "コールアウト-重要度とアイコンの対応規律"
  fi

  if grep -qF '<span class="ex">単一HTML生成</span>' "$script_dir/../references/ポータル設計基盤.html" \
    && grep -qF '<span class="ex">外部依存はMaterial Symbolsのみ</span>' "$script_dir/../references/ポータル設計基盤.html"; then
    pass "コールアウト-ポータル設計基盤の外部依存規律"
  else
    fail "コールアウト-ポータル設計基盤の外部依存規律"
  fi
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
check_callout_contract

echo ""
echo "========================================="
echo "結果: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"
echo "========================================="
[ "$FAIL" -gt 0 ] && exit 1
exit 0
