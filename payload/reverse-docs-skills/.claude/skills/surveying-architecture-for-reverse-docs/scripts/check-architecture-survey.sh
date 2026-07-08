#!/usr/bin/env bash
set -euo pipefail

# check-architecture-survey.sh — アーキテクチャ調査書の機械ゲート（4検査すべて決定的）
#
# 使い方:
#   check-architecture-survey.sh <調査書パス> <target_repo_path>
#   check-architecture-survey.sh --self-test
#
# 検査:
#   1. 記載パス実在100%: 調査書内のbacktick囲みトークンのうち「/」を含む相対パスとみなせるものを
#      抽出し、全件 target_repo_path 配下に test -e で実在確認する。URL（://）・glob（* ?）・
#      プレースホルダ（< >）・絶対パス（先頭/）・空白/正規表現記号を含むトークン（grepパターン等の
#      コード例）は対象外とする。
#   2. 6種別網羅: 画面・API・テーブル・バッチ・帳票・外部連携の6語すべてについて、種別名と
#      判定語（実在する / 実在しない（）が同一行に存在する判定行があるか確認する。
#   3. 推測語ゼロ: おそらく|と思われ|かもしれ|推測|たぶん|恐らく|でしょう|のはず が0件。
#   4. テンプレ残存ゼロ: <実測|<FILL|TBD|TODO が0件。
#
#   いずれか1件でも違反があれば exit 1（fail-closed）。全件PASSでexit 0。
#   --self-test は合成フィクスチャで陽性exit 0・陰性(検査ごと)exit 1を自己検証する。
#
# 設計判断（ADR）の正本は本スキルの SKILL.md「## 設計判断」に記載する。
# 保守責任者: 人手（ユーザー）。検査基準・除外規則を変更した時に更新する。
# macOS bash 3.2 互換（mapfile 不使用）。

UNIT_KINDS="画面 API テーブル バッチ 帳票 外部連携"
GUESS_WORDS_RE='おそらく|と思われ|かもしれ|推測|たぶん|恐らく|でしょう|のはず'
PLACEHOLDER_RE='<実測|<FILL|TBD|TODO'

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

extract_path_tokens() {
  grep -oE '`[^`]+`' "$1" 2>/dev/null | sed -E 's/^`//; s/`$//'
}

# 検査1: 記載パス実在100%
check_paths_exist() {
  survey="$1"
  repo="$2"
  missing=0
  total=0
  tokens="$(extract_path_tokens "$survey")"
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
      echo "  未実在: $tok" >&2
      missing=$((missing + 1))
    fi
  done <<EOF
$tokens
EOF
  if [ "$missing" -gt 0 ]; then
    echo "検査1失敗: 記載パス $total 件中 $missing 件が target_repo_path 配下に実在しません" >&2
    return 1
  fi
  echo "検査1通過: 記載パス $total 件すべて実在（対象0件を含む）"
  return 0
}

# 検査2: 6種別網羅（判定語が同一行に存在するか）
check_unit_kinds() {
  survey="$1"
  missing=0
  for k in $UNIT_KINDS; do
    line="$(grep -F -- "$k" "$survey" 2>/dev/null | grep -E '実在する|実在しない（' || true)"
    if [ -z "$line" ]; then
      echo "  種別未判定: ${k}（種別名と判定語「実在する」または「実在しない（」が同一行に無い）" >&2
      missing=$((missing + 1))
    fi
  done
  if [ "$missing" -gt 0 ]; then
    echo "検査2失敗: 6種別中 $missing 種別の判定行が見つかりません" >&2
    return 1
  fi
  echo "検査2通過: 6種別すべてに判定行あり"
  return 0
}

# 検査3: 推測語ゼロ
check_no_guess_words() {
  survey="$1"
  hits="$(grep -nE -- "$GUESS_WORDS_RE" "$survey" 2>/dev/null || true)"
  if [ -n "$hits" ]; then
    echo "検査3失敗: 推測語を検出" >&2
    echo "$hits" >&2
    return 1
  fi
  echo "検査3通過: 推測語0件"
  return 0
}

# 検査4: テンプレ残存ゼロ
check_no_placeholder() {
  survey="$1"
  hits="$(grep -nE -- "$PLACEHOLDER_RE" "$survey" 2>/dev/null || true)"
  if [ -n "$hits" ]; then
    echo "検査4失敗: テンプレ残存トークンを検出" >&2
    echo "$hits" >&2
    return 1
  fi
  echo "検査4通過: テンプレ残存0件"
  return 0
}

# 4検査すべてを実行し集約結果を返す。
run_all_checks() {
  survey="$1"
  repo="$2"
  rc=0
  check_paths_exist "$survey" "$repo" || rc=1
  check_unit_kinds "$survey" || rc=1
  check_no_guess_words "$survey" || rc=1
  check_no_placeholder "$survey" || rc=1
  return "$rc"
}

# 合成フィクスチャによる自己テスト（陽性1件・検査ごとの陰性4件＝計5ケース）。
self_test() {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/architecture-survey-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  repo="$tmp/repo"
  mkdir -p "$repo/src/app/api"
  : > "$repo/package.json"
  : > "$repo/src/app/page.tsx"
  : > "$repo/src/app/api/route.ts"

  base_kinds='| 種別 | 実在判定 | 検出手がかり | 根拠パス |
|---|---|---|---|
| 画面 | 実在する | `find src/app -name page.tsx` で検出 | `src/app/page.tsx` |
| API | 実在する | `find src/app/api -name route.ts` で検出 | `src/app/api/route.ts` |
| テーブル | 実在しない（マイグレーション・ORMスキーマが見つからないため） | - | - |
| バッチ | 実在しない（cron/ジョブランナー定義が見つからないため） | - | - |
| 帳票 | 実在しない（帳票生成ライブラリの使用箇所が見つからないため） | - | - |
| 外部連携 | 実在しない（外部APIクライアントの使用箇所が見つからないため） | - | - |'

  # 陽性フィクスチャ: 4検査すべてPASSする想定
  cat > "$tmp/pass.md" <<MD
## 調査メタ
対象リポジトリ: $repo
実行した調査コマンド: \`find . -maxdepth 2 -type f\`

## エントリポイント
\`package.json\` と \`src/app/page.tsx\` を確認した。API定義は \`src/app/api/route.ts\`。

## ユニット種別判定
$base_kinds
MD

  # 陰性1: 検査1のみ違反（存在しないパスを記載）
  cat > "$tmp/fail1.md" <<MD
## エントリポイント
\`src/app/missing.tsx\` を確認した。

## ユニット種別判定
$base_kinds
MD

  # 陰性2: 検査2のみ違反（画面の判定語を欠落）
  cat > "$tmp/fail2.md" <<MD
## エントリポイント
\`package.json\` を確認した。

## ユニット種別判定
| 種別 | 実在判定 | 検出手がかり | 根拠パス |
|---|---|---|---|
| 画面 | 要確認 | - | - |
| API | 実在する | \`find src/app/api\` で検出 | \`src/app/api/route.ts\` |
| テーブル | 実在しない（マイグレーションが見つからないため） | - | - |
| バッチ | 実在しない（ジョブ定義が見つからないため） | - | - |
| 帳票 | 実在しない（帳票生成ライブラリが見つからないため） | - | - |
| 外部連携 | 実在しない（外部APIクライアントが見つからないため） | - | - |
MD

  # 陰性3: 検査3のみ違反（推測語混入）
  cat > "$tmp/fail3.md" <<MD
## エントリポイント
\`package.json\` を確認した。ルーティング方式はおそらくApp Routerである。

## ユニット種別判定
$base_kinds
MD

  # 陰性4: 検査4のみ違反（テンプレ残存）
  cat > "$tmp/fail4.md" <<MD
## 調査メタ
updated: <実測: YYYY-MM-DD>

## エントリポイント
\`package.json\` を確認した。

## ユニット種別判定
$base_kinds
MD

  rc=0

  if run_all_checks "$tmp/pass.md" "$repo" >/dev/null 2>&1; then
    echo "  [PASS] 陽性フィクスチャがexit 0"
  else
    echo "  [FAIL] 陽性フィクスチャがexit 0にならない" >&2
    rc=1
  fi

  if check_paths_exist "$tmp/fail1.md" "$repo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査1: 未実在パスがあるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査1: 未実在パスでexit 1"
  fi

  if check_unit_kinds "$tmp/fail2.md" >/dev/null 2>&1; then
    echo "  [FAIL] 検査2: 判定行欠落があるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査2: 判定行欠落でexit 1"
  fi

  if check_no_guess_words "$tmp/fail3.md" >/dev/null 2>&1; then
    echo "  [FAIL] 検査3: 推測語混入があるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査3: 推測語混入でexit 1"
  fi

  if check_no_placeholder "$tmp/fail4.md" >/dev/null 2>&1; then
    echo "  [FAIL] 検査4: テンプレ残存があるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査4: テンプレ残存でexit 1"
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

survey="${1:?使い方: check-architecture-survey.sh <調査書パス> <target_repo_path>}"
repo="${2:?使い方: check-architecture-survey.sh <調査書パス> <target_repo_path>}"

if [ ! -f "$survey" ]; then
  echo "エラー: 調査書が見つかりません: $survey" >&2
  exit 2
fi
if [ ! -d "$repo" ]; then
  echo "エラー: target_repo_path が見つかりません: $repo" >&2
  exit 2
fi

if run_all_checks "$survey" "$repo"; then
  echo "アーキテクチャ調査書ゲート: 全4検査PASS"
  exit 0
else
  echo "アーキテクチャ調査書ゲート: FAIL" >&2
  exit 1
fi
