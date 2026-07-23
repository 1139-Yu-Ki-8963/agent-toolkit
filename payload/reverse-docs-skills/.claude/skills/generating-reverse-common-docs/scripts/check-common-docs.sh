#!/usr/bin/env bash
set -euo pipefail

# check-common-docs.sh — プロジェクト共通10文書の機械ゲート（6検査すべて決定的）
#
# 使い方:
#   check-common-docs.sh <common_docs_dir> <target_repo_path>
#   check-common-docs.sh --self-test
#
# <common_docs_dir> は `<output_dir>/プロジェクト共通` を指す（10文書＋サンプル記録.mdの
# 親ディレクトリ）。
#
# 検査:
#   1. 実在検査: 10文書＋サンプル記録.md（計11ファイル。規約4種は規約/サブディレクトリ）
#      すべてが実在する。
#   2. 規則行完備性: 規約4文書内の各テーブル行のうち、backtick囲みの相対パス
#      （「/」を含む）トークンを1件以上含む行を「規則行」とみなし、その行に
#      ①実例パス3件以上 ②頻度（[0-9]+/[0-9]+形式） ③例外率（[0-9.]+%形式）
#      が揃っているかを確認する。
#   3. パス実在検査: 規約4種＋共通設計書.md＋メッセージ定義書.md＋DESIGN.md内の
#      backtick囲み相対パス全件が target_repo_path 配下に test -e で実在する。
#      除外規則は検査2と同じ（URL・glob・プレースホルダ・絶対パス・空白/正規表現
#      記号を含むトークンは対象外）。
#   4. テンプレ残存ゼロ: <実測|<FILL|TBD|TODO が11ファイルすべてで0件。
#   5. 理想論表現ゼロ: すべきである|望ましい|べきだ|理想的には|今後は が
#      規約4文書で0件（実装事実の記録に限る）。
#   6. メッセージ定義書規模突合: メッセージ定義書.md内の規模宣言行
#      （「総件数: <N>件」形式）と、同ファイル内のbacktickメッセージ文字列を
#      含むテーブル行の実測件数が一致する。宣言行が無い場合もFAILとする
#      （カタログ規模の推測表現を禁止するための機械検証）。
#
#   いずれか1件でも違反があれば exit 1（fail-closed）。全件PASSでexit 0。
#   --self-test は合成フィクスチャで陽性exit 0・陰性(検査ごと)exit 1を自己検証する。
#
# 設計判断（ADR）の正本は本スキルの SKILL.md「## 設計判断」に記載する。
# 保守責任者: 人手（ユーザー）。検査基準・除外規則を変更した時に更新する。
# macOS bash 3.2 互換（mapfile 不使用）。

REQUIRED_FILES="規約/コーディング規約.md 規約/命名規約.md 規約/ディレクトリ構成規約.md 規約/コンポーネント設計規約.md 共通設計書.md メッセージ定義書.md DESIGN.md 基盤設計.md UI共通設計.md データ設計.md サンプル記録.md"
CONVENTION_FILES="規約/コーディング規約.md 規約/命名規約.md 規約/ディレクトリ構成規約.md 規約/コンポーネント設計規約.md"
# 検査3（パス実在検査）は規約4種に加え、共通設計書・メッセージ定義書・DESIGN.mdも対象にする
PATH_CHECK_FILES="$CONVENTION_FILES 共通設計書.md メッセージ定義書.md DESIGN.md"
MESSAGE_DOC_FILE="メッセージ定義書.md"
PLACEHOLDER_RE='<実測|<FILL|TBD|TODO'
IDEAL_WORDS_RE='すべきである|望ましい|べきだ|理想的には|今後は'
FREQ_RE='[0-9]+/[0-9]+'
EXCEPTION_RE='[0-9]+(\.[0-9]+)?%'
MESSAGE_SCALE_RE='総件数[:：] *[0-9]+件'

# backtick囲みトークンのうち「相対パス」とみなせるもの以外を除外する判定。
# 除外: 「/」を含まない / URL / glob / プレースホルダ / 絶対パス / 空白・正規表現記号を含む
is_path_candidate() {
  tok="$1"
  case "$tok" in
    */*) : ;;
    *) return 1 ;;
  esac
  case "$tok" in
    *'://'*|*'*'*|*'?'*|*'<'*|*'>'*|/*|*' '*|*'\'*|*'"'*|*"'"*|*'('*|*')'*|*'|'*|*'['*|*']'*|*'^'*|*'$'*|*'+'*|*'{'*|*'}'*)
      return 1 ;;
  esac
  return 0
}

extract_backtick_tokens() {
  grep -oE '`[^`]+`' "$1" 2>/dev/null | sed -E 's/^`//; s/`$//' || true
}

# 表の区切り行（|---|---|等）かどうかを判定する
is_separator_row() {
  line="$1"
  stripped="$(printf '%s' "$line" | tr -d '|:\- ')"
  [ -z "$stripped" ]
}

# 検査1: 実在検査（11ファイル）
check_files_exist() {
  dir="$1"
  missing=0
  for f in $REQUIRED_FILES; do
    if [ ! -f "$dir/$f" ]; then
      echo "  未実在: $f" >&2
      missing=$((missing + 1))
    fi
  done
  if [ "$missing" -gt 0 ]; then
    echo "検査1失敗: プロジェクト共通11ファイル中 $missing 件が未実在です" >&2
    return 1
  fi
  echo "検査1通過: 11ファイルすべて実在"
  return 0
}

# 検査2: 規則行完備性（規約4文書）
check_rule_rows() {
  dir="$1"
  violations=0
  for f in $CONVENTION_FILES; do
    path="$dir/$f"
    [ -f "$path" ] || continue
    lineno=0
    while IFS= read -r line; do
      lineno=$((lineno + 1))
      case "$line" in
        '|'*) : ;;
        *) continue ;;
      esac
      is_separator_row "$line" && continue

      tokens="$(printf '%s' "$line" | grep -oE '`[^`]+`' 2>/dev/null | sed -E 's/^`//; s/`$//' || true)"
      path_count=0
      while IFS= read -r tok; do
        [ -z "$tok" ] && continue
        if is_path_candidate "$tok"; then
          path_count=$((path_count + 1))
        fi
      done <<EOF
$tokens
EOF
      # backtickパス候補が1件も無い行は規則行とみなさない（見出し・区切り行等）
      [ "$path_count" -eq 0 ] && continue

      row_ng=0
      if [ "$path_count" -lt 3 ]; then
        echo "  実例不足: ${f}:${lineno}（実例パス ${path_count} 件、3件以上必要）" >&2
        row_ng=1
      fi
      if ! printf '%s' "$line" | grep -qE -- "$FREQ_RE"; then
        echo "  頻度欠落: ${f}:${lineno}（[0-9]+/[0-9]+ 形式が見つからない）" >&2
        row_ng=1
      fi
      if ! printf '%s' "$line" | grep -qE -- "$EXCEPTION_RE"; then
        echo "  例外率欠落: ${f}:${lineno}（[0-9.]+% 形式が見つからない）" >&2
        row_ng=1
      fi
      if [ "$row_ng" -eq 1 ]; then
        violations=$((violations + 1))
      fi
    done < "$path"
  done
  if [ "$violations" -gt 0 ]; then
    echo "検査2失敗: 規則行 $violations 件が実例/頻度/例外率のいずれかを欠いています" >&2
    return 1
  fi
  echo "検査2通過: 規則行すべてに実例3件以上・頻度・例外率あり"
  return 0
}

# 検査3: パス実在検査（規約4種＋共通設計書＋メッセージ定義書＋DESIGN.md）
check_paths_exist() {
  dir="$1"
  repo="$2"
  missing=0
  total=0
  for f in $PATH_CHECK_FILES; do
    path="$dir/$f"
    [ -f "$path" ] || continue
    tokens="$(extract_backtick_tokens "$path")"
    while IFS= read -r tok; do
      [ -z "$tok" ] && continue
      if ! is_path_candidate "$tok"; then
        continue
      fi
      total=$((total + 1))
      checkpath="$tok"
      case "$checkpath" in
        ./*) checkpath="${checkpath#./}" ;;
      esac
      if [ ! -e "$repo/$checkpath" ]; then
        echo "  未実在: $f: $tok" >&2
        missing=$((missing + 1))
      fi
    done <<EOF
$tokens
EOF
  done
  if [ "$missing" -gt 0 ]; then
    echo "検査3失敗: 記載パス $total 件中 $missing 件が target_repo_path 配下に実在しません" >&2
    return 1
  fi
  echo "検査3通過: 記載パス $total 件すべて実在（対象0件を含む）"
  return 0
}

# 検査4: テンプレ残存ゼロ（11ファイル）
check_no_placeholder() {
  dir="$1"
  hit_total=0
  for f in $REQUIRED_FILES; do
    path="$dir/$f"
    [ -f "$path" ] || continue
    hits="$(grep -nE -- "$PLACEHOLDER_RE" "$path" 2>/dev/null || true)"
    if [ -n "$hits" ]; then
      echo "  テンプレ残存: $f" >&2
      echo "$hits" >&2
      hit_total=$((hit_total + 1))
    fi
  done
  if [ "$hit_total" -gt 0 ]; then
    echo "検査4失敗: $hit_total ファイルにテンプレ残存トークンを検出" >&2
    return 1
  fi
  echo "検査4通過: 11ファイルすべてテンプレ残存0件"
  return 0
}

# 検査5: 理想論表現ゼロ（規約4文書）
check_no_ideal_words() {
  dir="$1"
  hit_total=0
  for f in $CONVENTION_FILES; do
    path="$dir/$f"
    [ -f "$path" ] || continue
    hits="$(grep -nE -- "$IDEAL_WORDS_RE" "$path" 2>/dev/null || true)"
    if [ -n "$hits" ]; then
      echo "  理想論表現: $f" >&2
      echo "$hits" >&2
      hit_total=$((hit_total + 1))
    fi
  done
  if [ "$hit_total" -gt 0 ]; then
    echo "検査5失敗: $hit_total ファイルに理想論表現を検出" >&2
    return 1
  fi
  echo "検査5通過: 規約4文書すべて理想論表現0件"
  return 0
}

# 検査6: メッセージ定義書規模突合
check_message_scale() {
  dir="$1"
  path="$dir/$MESSAGE_DOC_FILE"
  if [ ! -f "$path" ]; then
    echo "  未実在: $MESSAGE_DOC_FILE" >&2
    echo "検査6失敗: $MESSAGE_DOC_FILE が存在しません" >&2
    return 1
  fi
  declared="$(grep -oE -- "$MESSAGE_SCALE_RE" "$path" | head -n1 | grep -oE '[0-9]+' || true)"
  if [ -z "$declared" ]; then
    echo "  規模宣言欠落: $MESSAGE_DOC_FILE に「総件数: <N>件」形式の宣言行が見つかりません" >&2
    echo "検査6失敗: メッセージ定義書に規模宣言がありません" >&2
    return 1
  fi
  actual=0
  while IFS= read -r line; do
    case "$line" in
      '|'*) : ;;
      *) continue ;;
    esac
    is_separator_row "$line" && continue
    if printf '%s' "$line" | grep -qE '`[^`]+`'; then
      actual=$((actual + 1))
    fi
  done < "$path"
  if [ "$actual" -ne "$declared" ]; then
    echo "  規模不一致: $MESSAGE_DOC_FILE の宣言(${declared}件)と実測テーブル行数(${actual}件)が不一致です" >&2
    echo "検査6失敗: メッセージ定義書の宣言件数と実測件数が不一致です" >&2
    return 1
  fi
  echo "検査6通過: メッセージ定義書の宣言件数(${declared})と実測件数(${actual})が一致"
  return 0
}

# 6検査すべてを実行し集約結果を返す。
run_all_checks() {
  dir="$1"
  repo="$2"
  rc=0
  check_files_exist "$dir" || rc=1
  check_rule_rows "$dir" || rc=1
  check_paths_exist "$dir" "$repo" || rc=1
  check_no_placeholder "$dir" || rc=1
  check_no_ideal_words "$dir" || rc=1
  check_message_scale "$dir" || rc=1
  return "$rc"
}

# 合成フィクスチャによる自己テスト（陽性1件・検査ごとの陰性5件＝計6ケース）。
self_test() {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/compiling-common-docs-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  repo="$tmp/repo"
  mkdir -p "$repo/src/components" "$repo/src/utils" "$repo/src/hooks" "$repo/src/legacy"
  : > "$repo/src/components/Button.tsx"
  : > "$repo/src/utils/format.ts"
  : > "$repo/src/hooks/useAuth.ts"
  : > "$repo/src/legacy/OldForm.tsx"

  rule_row='| インデント | スペース2個。`src/components/Button.tsx`・`src/utils/format.ts`・`src/hooks/useAuth.ts` で確認。頻度 18/20。例外率 10.0%（例外: `src/legacy/OldForm.tsx`） | `.eslintrc.json` |'

  build_docs() {
    target="$1"
    mkdir -p "$target/規約"
    for f in コーディング規約 命名規約 ディレクトリ構成規約 コンポーネント設計規約; do
      cat > "$target/規約/${f}.md" <<MD
# ${f}（リバース版）

| 項目 | 実測内容 | 抽出元 |
|---|---|---|
$rule_row
MD
    done
    cat > "$target/共通設計書.md" <<'MD'
# 共通設計書（リバース版）

## §1 共通画面状態の規則（実測）
loading状態はスケルトン表示。
MD
    cat > "$target/メッセージ定義書.md" <<'MD'
# 共通メッセージ定義書（リバース版）

総件数: 2件

## メッセージ一覧

| メッセージ | 用途 |
|---|---|
| `保存に成功しました` | 保存成功トースト |
| `保存に失敗しました` | 保存失敗トースト |
MD
    cat > "$target/DESIGN.md" <<'MD'
# 共通デザインシステム（リバース版）

primary色は#1a73e8。
MD
    cat > "$target/基盤設計.md" <<'MD'
# 基盤設計書（リバース版）

## §1 フレームワーク構成（実測）
Reactを採用。
MD
    cat > "$target/UI共通設計.md" <<'MD'
# UI共通設計書（リバース版）

## §1 デザインシステム（実測）
独自コンポーネントライブラリを使用。
MD
    cat > "$target/データ設計.md" <<'MD'
# データ設計書（リバース版）

## §1 データモデル概要（実測）
ユーザーエンティティを保有。
MD
    cat > "$target/サンプル記録.md" <<'MD'
# サンプル記録

## 選定コマンド
`find src/components -type f | sort | head -n 5`
MD
  }

  rc=0

  # 陽性フィクスチャ: 6検査すべてPASSする想定
  pass_dir="$tmp/pass"
  build_docs "$pass_dir"
  if run_all_checks "$pass_dir" "$repo" >/dev/null 2>&1; then
    echo "  [PASS] 陽性フィクスチャがexit 0"
  else
    echo "  [FAIL] 陽性フィクスチャがexit 0にならない" >&2
    rc=1
  fi

  # 陰性1: 検査1のみ違反（DESIGN.mdを欠落）
  fail1_dir="$tmp/fail1"
  build_docs "$fail1_dir"
  rm -f "$fail1_dir/DESIGN.md"
  if check_files_exist "$fail1_dir" >/dev/null 2>&1; then
    echo "  [FAIL] 検査1: ファイル欠落があるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査1: ファイル欠落でexit 1"
  fi

  # 陰性2: 検査2のみ違反（実例パス2件のみ・頻度/例外率欠落）
  fail2_dir="$tmp/fail2"
  build_docs "$fail2_dir"
  cat > "$fail2_dir/規約/コーディング規約.md" <<MD
# コーディング規約（リバース版）

| 項目 | 実測内容 | 抽出元 |
|---|---|---|
| インデント | \`src/components/Button.tsx\`・\`src/utils/format.ts\` で確認 | \`.eslintrc.json\` |
MD
  if check_rule_rows "$fail2_dir" >/dev/null 2>&1; then
    echo "  [FAIL] 検査2: 実例/頻度/例外率欠落があるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査2: 実例/頻度/例外率欠落でexit 1"
  fi

  # 陰性3: 検査3のみ違反（存在しないパスを記載）
  fail3_dir="$tmp/fail3"
  build_docs "$fail3_dir"
  cat > "$fail3_dir/規約/命名規約.md" <<MD
# 命名規約（リバース版）

| 項目 | 実測内容 | 抽出元 |
|---|---|---|
$rule_row
| ファイル名 | \`src/components/Missing.tsx\` を確認。頻度 5/5。例外率 0.0% | \`src/utils/format.ts\` |
MD
  if check_paths_exist "$fail3_dir" "$repo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査3: 未実在パスがあるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査3: 未実在パスでexit 1"
  fi

  # 陰性4: 検査4のみ違反（テンプレ残存）
  fail4_dir="$tmp/fail4"
  build_docs "$fail4_dir"
  cat >> "$fail4_dir/DESIGN.md" <<'MD'

surface色は TBD。
MD
  if check_no_placeholder "$fail4_dir" >/dev/null 2>&1; then
    echo "  [FAIL] 検査4: テンプレ残存があるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査4: テンプレ残存でexit 1"
  fi

  # 陰性5: 検査5のみ違反（理想論表現混入）
  fail5_dir="$tmp/fail5"
  build_docs "$fail5_dir"
  cat >> "$fail5_dir/規約/ディレクトリ構成規約.md" <<'MD'

今後は共通コンポーネントをまとめるべきである。
MD
  if check_no_ideal_words "$fail5_dir" >/dev/null 2>&1; then
    echo "  [FAIL] 検査5: 理想論表現があるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査5: 理想論表現でexit 1"
  fi

  # 陰性6: 検査6のみ違反（メッセージ定義書の宣言件数と実測件数が不一致）
  fail6_dir="$tmp/fail6"
  build_docs "$fail6_dir"
  cat > "$fail6_dir/メッセージ定義書.md" <<'MD'
# 共通メッセージ定義書（リバース版）

総件数: 3件

## メッセージ一覧

| メッセージ | 用途 |
|---|---|
| `保存に成功しました` | 保存成功トースト |
| `保存に失敗しました` | 保存失敗トースト |
MD
  if check_message_scale "$fail6_dir" >/dev/null 2>&1; then
    echo "  [FAIL] 検査6: 宣言件数と実測件数の不一致があるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査6: 宣言件数と実測件数の不一致でexit 1"
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

docs_dir="${1:?使い方: check-common-docs.sh <common_docs_dir> <target_repo_path>}"
repo="${2:?使い方: check-common-docs.sh <common_docs_dir> <target_repo_path>}"

if [ ! -d "$docs_dir" ]; then
  echo "エラー: common_docs_dir が見つかりません: $docs_dir" >&2
  exit 2
fi
if [ ! -d "$repo" ]; then
  echo "エラー: target_repo_path が見つかりません: $repo" >&2
  exit 2
fi

if run_all_checks "$docs_dir" "$repo"; then
  echo "プロジェクト共通文書ゲート: 全6検査PASS"
  exit 0
else
  echo "プロジェクト共通文書ゲート: FAIL" >&2
  exit 1
fi
