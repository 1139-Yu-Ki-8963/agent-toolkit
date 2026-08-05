#!/usr/bin/env bash
set -euo pipefail

# check-naming.test.sh — check-naming.sh の回帰テスト
#
# 目的: check-naming.sh の --self-test 実行に加え、独立した固定サンプル
#   （合格3ケース・違反3ケース）で検出精度を回帰検証する。
#
# 使い方:
#   check-naming.test.sh
#
# 終了コード:
#   0 = 全項目PASS。1 = いずれかFAIL。
#
# 保守責任者: 人手（ユーザー）。check-naming.sh の検査ロジックを変更した場合は
#   本テストのケースも同時に見直す。
#
# macOS bash 3.2 互換。

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
checker="${script_dir}/check-naming.sh"
rc=0

echo "== check-naming.sh --self-test =="
if bash "$checker" --self-test; then
  echo "  [PASS] self-test"
else
  echo "  [FAIL] self-test" >&2
  rc=1
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-naming-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# 合格1: キャメルケース関数(.ts)
cat > "$tmp/regression-pass-1.ts" <<'EOF'
function fetchOrderList() {
  return [];
}
EOF

# 合格2: パスカルケースのexportコンポーネント(.tsx)
cat > "$tmp/regression-pass-2.tsx" <<'EOF'
export function OrderSummaryPanel() {
  return null;
}
EOF

# 合格3: スネークケースのDBカラム(.sql)
cat > "$tmp/regression-pass-3.sql" <<'EOF'
CREATE TABLE orders (
  order_id INT,
  total_amount DECIMAL
);
EOF

# 違反1: パスカルケース関数名(.ts、コンポーネントではない)
cat > "$tmp/regression-fail-1.ts" <<'EOF'
function FetchOrderList() {
  return [];
}
EOF

# 違反2: 小文字始まりのexportコンポーネント(.tsx)
cat > "$tmp/regression-fail-2.tsx" <<'EOF'
export function orderSummaryPanel() {
  return null;
}
EOF

# 違反3: キャメルケース混じりのDBカラム(.sql)
cat > "$tmp/regression-fail-3.sql" <<'EOF'
CREATE TABLE orders (
  orderId INT,
  totalAmount DECIMAL
);
EOF

echo "== 独立回帰ケース =="

for f in regression-pass-1.ts regression-pass-2.tsx regression-pass-3.sql; do
  out="$(bash "$checker" "$tmp/$f")"
  if [ -z "$out" ]; then
    echo "  [PASS] ${f}: 誤検出なし"
  else
    echo "  [FAIL] ${f}: 合格例が誤検出された（${out}）" >&2
    rc=1
  fi
done

for f in regression-fail-1.ts regression-fail-2.tsx regression-fail-3.sql; do
  out="$(bash "$checker" "$tmp/$f")"
  if [ -n "$out" ]; then
    echo "  [PASS] ${f}: 違反を検出した（${out}）"
  else
    echo "  [FAIL] ${f}: 違反例を検出できなかった" >&2
    rc=1
  fi
done

if [ "$rc" -eq 0 ]; then
  echo "回帰テスト 全項目 PASS"
else
  echo "回帰テスト FAIL" >&2
fi
exit "$rc"
