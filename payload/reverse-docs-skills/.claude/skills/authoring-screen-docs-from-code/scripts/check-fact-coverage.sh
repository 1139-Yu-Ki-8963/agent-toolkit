#!/usr/bin/env bash
set -euo pipefail

# check-fact-coverage.sh — 宣言的契約事実表の「全行が設計書へ転記済みか」を機械突合する完全性ゲート
#
# 使い方:
#   check-fact-coverage.sh <fact-table.md> <画面詳細設計書.md> [<DESIGN.md> ...]
#   check-fact-coverage.sh --self-test
#
# 契約:
#   - fact-table.md の各分類セクション（## で始まる見出し）配下の Markdown 表から
#     1 列目（意味キー）を抽出し、後続引数の設計書いずれかに固定文字列で言及されているか確認する。
#   - ⑨実測系（見出しに「⑨」または「measurement_pending」を含むセクション）は転記対象外として除外する。
#   - 未転記が 1 件でもあれば exit 1（fail-closed）。全件転記済みで exit 0。
#   - --self-test は合成フィクスチャで陽性 exit 0・陰性 exit 1 を自己検証する。
#
# 設計判断（ADR）の正本は本スキルの SKILL.md「## 設計判断」に記載する。
# 保守責任者: 人手（ユーザー）。fact-table.md の書式・除外分類を変更した時に更新する。
# macOS bash 3.2 互換（mapfile 不使用）。

# 事実表からキーを抽出する（⑨/measurement_pending セクションを除外）。
extract_keys() {
  awk '
    /^##[ \t]/ {
      if (index($0, "⑨") > 0 || index($0, "measurement_pending") > 0) { skip = 1 } else { skip = 0 }
      next
    }
    skip == 1 { next }
    /^\|/ {
      n = split($0, a, "|")
      if (n < 2) next
      key = a[2]
      gsub(/^[ \t]+/, "", key)
      gsub(/[ \t]+$/, "", key)
      if (key == "") next
      if (key == "キー") next
      if (key ~ /^-+$/) next
      print key
    }
  ' "$1"
}

# fact-table と設計書群を突合する。未転記があれば return 1。
run_check() {
  fact_table="$1"
  shift
  missing=0
  total=0
  keys="$(extract_keys "$fact_table")"
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    total=$((total + 1))
    found=0
    esc_key="$(printf '%s' "$key" | sed -E 's/([.[\*^$()+?{}|\\])/\\\1/g')"
    for doc in "$@"; do
      if grep -qE -- "(^|[^A-Za-z0-9_-])${esc_key}([^A-Za-z0-9_-]|\$)" "$doc" 2>/dev/null; then
        found=1
        break
      fi
    done
    if [ "$found" -eq 0 ]; then
      echo "  未転記: $key" >&2
      missing=$((missing + 1))
    fi
  done <<EOF
$keys
EOF
  if [ "$missing" -gt 0 ]; then
    echo "完全性ゲート失敗: 事実表 $total 件中 $missing 件が設計書に未転記です（fail-closed）" >&2
    return 1
  fi
  echo "完全性ゲート通過: 事実表 $total 件すべてが設計書に転記済みです"
  return 0
}

# 合成フィクスチャによる自己テスト。
self_test() {
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  # 陽性フィクスチャ: ①import の全キーが設計書に言及される。⑨は設計書に無いが除外されるため影響しない。
  cat > "$tmp/ft-pos.md" <<'MD'
## ①import
| キー | 事実 |
|---|---|
| import-react-useState | react から useState |

## ⑨実測系（measurement_pending・転記対象外）
| キー | 事実 |
|---|---|
| 初期表示-件数 | [画面単位検証で実測] |
MD

  # 陰性フィクスチャ: import-axios-client が設計書に未言及。
  cat > "$tmp/ft-neg.md" <<'MD'
## ①import
| キー | 事実 |
|---|---|
| import-react-useState | react から useState |
| import-axios-client | axios から client |

## ⑨実測系（measurement_pending・転記対象外）
| キー | 事実 |
|---|---|
| 初期表示-件数 | [画面単位検証で実測] |
MD

  # 設計書: useState のみ言及（axios-client・初期表示-件数 は言及しない）。
  cat > "$tmp/design.md" <<'MD'
# 画面詳細設計書
## §15.3 依存（import）一覧
import-react-useState を使用する。
MD

  rc=0
  if run_check "$tmp/ft-pos.md" "$tmp/design.md" >/dev/null 2>&1; then
    echo "  [PASS] 陽性: 転記済み事実表で exit 0（⑨除外も確認）"
  else
    echo "  [FAIL] 陽性: 転記済み事実表なのに非0で終了した" >&2
    rc=1
  fi

  if run_check "$tmp/ft-neg.md" "$tmp/design.md" >/dev/null 2>&1; then
    echo "  [FAIL] 陰性: 未転記1行ありなのに exit 0 になった" >&2
    rc=1
  else
    echo "  [PASS] 陰性: 未転記1行で exit 1"
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

fact_table="${1:?引数1 fact-table.md が必要です}"
shift || true
if [ "$#" -lt 1 ]; then
  echo "エラー: 設計書を 1 つ以上指定してください（使い方: check-fact-coverage.sh <fact-table.md> <画面詳細設計書.md> [<DESIGN.md> ...]）" >&2
  exit 2
fi
for f in "$fact_table" "$@"; do
  if [ ! -f "$f" ]; then
    echo "エラー: ファイルが見つかりません: $f" >&2
    exit 2
  fi
done

run_check "$fact_table" "$@"
