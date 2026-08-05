#!/usr/bin/env bash
set -euo pipefail

# check-naming.sh — 命名規約(rule.md)のadvisory linter
#
# 目的: 関数名のキャメルケース・DBカラム名のスネークケース・Reactコンポーネント名の
#   パスカルケースを検査し、違反箇所を標準出力へ報告する。
#
# 使い方:
#   check-naming.sh <file> [<file> ...]   # 指定ファイル群を検査する
#   check-naming.sh --self-test            # 合格例・違反例を一時ディレクトリに作って検出を確認する
#
# 終了コード:
#   通常実行は常に0（enforcement: advisory のためblockしない）。
#   --self-test のみ、検出漏れ・誤検出があれば1を返す。
#
# 検査対象と規則（rule.mdの「## 規則」と対応）:
#   - *.ts / *.tsx の function宣言: 先頭小文字のキャメルケースであること
#     （.tsx でexportされる関数はコンポーネントとみなし、パスカルケース規則を適用する）
#   - *.sql のカラム定義: 英小文字・数字・アンダースコアだけのスネークケースであること
#
# 既知の限界:
#   - 正規表現による簡易走査であり、分割代入・高階関数・動的生成コードは検出できない
#   - .tsx のコンポーネント判定はexportの有無だけで行う。exportされないヘルパー関数は
#     キャメルケース規則の対象になる（意図した仕様）
#
# 保守責任者: 人手（ユーザー）。命名規則の対象を拡張する場合は本スクリプトと
#   rule.md の「## 規則」表を同時に更新する。
#
# macOS bash 3.2 互換。

is_camel_case() {
  # $1: 識別子。先頭小文字のキャメルケースならexit 0
  printf '%s' "$1" | grep -Eq '^[a-z][a-zA-Z0-9]*$'
}

is_pascal_case() {
  # $1: 識別子。先頭大文字のパスカルケースならexit 0
  printf '%s' "$1" | grep -Eq '^[A-Z][a-zA-Z0-9]*$'
}

is_snake_case() {
  # $1: 識別子。英小文字・数字・アンダースコアだけのスネークケースならexit 0
  printf '%s' "$1" | grep -Eq '^[a-z][a-z0-9_]*$'
}

scan_ts_functions() {
  # $1: file
  file="$1"
  is_tsx=0
  case "$file" in
    *.tsx) is_tsx=1 ;;
  esac

  while IFS= read -r line; do
    lineno="${line%%:*}"
    rest="${line#*:}"
    name="$(printf '%s' "$rest" | sed -E 's/^[[:space:]]*(export[[:space:]]+)?(default[[:space:]]+)?function[[:space:]]+([A-Za-z0-9_]+).*/\3/')"

    exported=0
    if printf '%s' "$rest" | grep -q '^[[:space:]]*export'; then
      exported=1
    fi

    if [ "$is_tsx" -eq 1 ] && [ "$exported" -eq 1 ]; then
      if ! is_pascal_case "$name"; then
        echo "${file}:${lineno}: 違反(コンポーネント名パスカルケース): ${name}"
      fi
    else
      if ! is_camel_case "$name"; then
        echo "${file}:${lineno}: 違反(関数名キャメルケース): ${name}"
      fi
    fi
  done < <(grep -nE '^[[:space:]]*(export[[:space:]]+)?(default[[:space:]]+)?function[[:space:]]+[A-Za-z0-9_]+' "$file" 2>/dev/null || true)
}

scan_sql_columns() {
  # $1: file
  file="$1"
  while IFS= read -r line; do
    lineno="${line%%:*}"
    rest="${line#*:}"
    name="$(printf '%s' "$rest" | sed -E 's/^[[:space:]]*([A-Za-z0-9_]+).*/\1/')"

    if ! is_snake_case "$name"; then
      echo "${file}:${lineno}: 違反(DBカラムスネークケース): ${name}"
    fi
  done < <(grep -nE '^[[:space:]]*[A-Za-z0-9_]+[[:space:]]+(INT|INTEGER|VARCHAR|TEXT|BOOLEAN|TIMESTAMP|DATE|DECIMAL|BIGINT|SERIAL)' "$file" 2>/dev/null || true)
}

scan_file() {
  # $1: file。拡張子で検査関数を振り分ける
  file="$1"
  case "$file" in
    *.ts|*.tsx) scan_ts_functions "$file" ;;
    *.sql) scan_sql_columns "$file" ;;
  esac
}

self_test() {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-naming-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN
  rc=0

  # 系1: 合格 - キャメルケース関数(.ts)
  cat > "$tmp/pass-function.ts" <<'EOF'
function getUserName() {
  return "taro";
}
EOF
  out="$(scan_file "$tmp/pass-function.ts")"
  if [ -z "$out" ]; then
    echo "  [PASS] 系1: キャメルケース関数(.ts)は検出されない"
  else
    echo "  [FAIL] 系1: 合格例が誤検出された（${out}）" >&2
    rc=1
  fi

  # 系2: 合格 - パスカルケースのexportコンポーネント(.tsx)
  cat > "$tmp/pass-component.tsx" <<'EOF'
export default function UserCard() {
  return null;
}
EOF
  out="$(scan_file "$tmp/pass-component.tsx")"
  if [ -z "$out" ]; then
    echo "  [PASS] 系2: パスカルケースのexportコンポーネント(.tsx)は検出されない"
  else
    echo "  [FAIL] 系2: 合格例が誤検出された（${out}）" >&2
    rc=1
  fi

  # 系3: 合格 - スネークケースのDBカラム(.sql)
  cat > "$tmp/pass-schema.sql" <<'EOF'
CREATE TABLE users (
  user_id INT,
  created_at TIMESTAMP
);
EOF
  out="$(scan_file "$tmp/pass-schema.sql")"
  if [ -z "$out" ]; then
    echo "  [PASS] 系3: スネークケースのDBカラム(.sql)は検出されない"
  else
    echo "  [FAIL] 系3: 合格例が誤検出された（${out}）" >&2
    rc=1
  fi

  # 系4: 違反 - スネークケース関数(.ts)
  cat > "$tmp/fail-function.ts" <<'EOF'
function get_user_name() {
  return "taro";
}
EOF
  out="$(scan_file "$tmp/fail-function.ts")"
  if [ -n "$out" ]; then
    echo "  [PASS] 系4: スネークケース関数(.ts)の違反を検出した（${out}）"
  else
    echo "  [FAIL] 系4: 違反例を検出できなかった" >&2
    rc=1
  fi

  # 系5: 違反 - 小文字始まりのexportコンポーネント(.tsx)
  cat > "$tmp/fail-component.tsx" <<'EOF'
export default function userCard() {
  return null;
}
EOF
  out="$(scan_file "$tmp/fail-component.tsx")"
  if [ -n "$out" ]; then
    echo "  [PASS] 系5: 小文字始まりのexportコンポーネント(.tsx)の違反を検出した（${out}）"
  else
    echo "  [FAIL] 系5: 違反例を検出できなかった" >&2
    rc=1
  fi

  # 系6: 違反 - キャメルケース混じりのDBカラム(.sql)
  cat > "$tmp/fail-schema.sql" <<'EOF'
CREATE TABLE users (
  userId INT,
  CreatedAt TIMESTAMP
);
EOF
  out="$(scan_file "$tmp/fail-schema.sql")"
  if [ -n "$out" ]; then
    echo "  [PASS] 系6: キャメルケース混じりのDBカラム(.sql)の違反を検出した（${out}）"
  else
    echo "  [FAIL] 系6: 違反例を検出できなかった" >&2
    rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

main() {
  if [ "$#" -eq 0 ]; then
    exit 0
  fi
  for f in "$@"; do
    scan_file "$f"
  done
  exit 0
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

main "$@"
