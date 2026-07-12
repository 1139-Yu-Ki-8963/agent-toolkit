#!/usr/bin/env bash
set -euo pipefail

# check-fact-coverage.sh — facts.yml の「全項目が設計書へ転記済みか」を機械突合する完全性ゲート
#
# 使い方:
#   check-fact-coverage.sh <facts.yml> <画面詳細設計書.md> [<DESIGN.md> ...]
#   check-fact-coverage.sh --self-test
#
# 契約:
#   - facts.yml（shared/references/facts-schema.md 準拠。sections配下9キーの固定インデント構造）の
#     各セクション items[].key を抽出し、後続引数の設計書いずれかに固定文字列で言及されているか確認する。
#   - measurement_pending（⑨実測委譲）セクションの items[].key は、設計書に「実測委譲」の表記が
#     1箇所でもあれば転記済み扱いとする（個別キー一致は不要）。表記が無い場合のみ、他セクションと
#     同様に個別キー一致を要求する。
#   - 未転記が1件でもあれば exit 1（fail-closed）。全件転記済みで exit 0。
#   - --self-test は合成フィクスチャで陽性 exit 0・陰性 exit 1 を自己検証する。
#
# 設計判断（ADR）の正本は本スキルの SKILL.md「## 設計判断」に記載する。
# 保守責任者: 人手（ユーザー）。facts.yml の書式・除外分類を変更した時に更新する。
# macOS bash 3.2 互換（mapfile 不使用）。

# facts.yml から「セクション名<TAB>キー」を1行ずつ抽出する。
# 固定インデント契約（shared/references/facts-schema.md）:
#   sections配下のキー(2段目)  = 2スペース
#   items配下の "- key:"(4段目) = 6スペース
extract_section_keys() {
  awk '
    /^  [a-z_]+:[ \t]*$/ {
      s = $0
      sub(/^  /, "", s)
      sub(/:[ \t]*$/, "", s)
      section = s
      next
    }
    /^      - key:/ {
      key = $0
      sub(/^      - key:[ \t]*/, "", key)
      gsub(/^"/, "", key)
      gsub(/"$/, "", key)
      gsub(/^[ \t]+/, "", key)
      gsub(/[ \t]+$/, "", key)
      if (key != "") print section "\t" key
    }
  ' "$1"
}

# facts.yml と設計書群を突合する。未転記があれば return 1。
run_check() {
  facts_yml="$1"
  shift
  missing=0
  total=0

  has_delegation_note=0
  for doc in "$@"; do
    if grep -q "実測委譲" "$doc" 2>/dev/null; then
      has_delegation_note=1
      break
    fi
  done

  rows="$(extract_section_keys "$facts_yml")"
  while IFS= read -r row; do
    [ -z "$row" ] && continue
    section="$(printf '%s' "$row" | cut -f1)"
    key="$(printf '%s' "$row" | cut -f2)"
    total=$((total + 1))

    if [ "$section" = "measurement_pending" ] && [ "$has_delegation_note" -eq 1 ]; then
      continue
    fi

    found=0
    esc_key="$(printf '%s' "$key" | sed -E 's/([.[\*^$()+?{}|\\])/\\\1/g')"
    for doc in "$@"; do
      if grep -qE -- "(^|[^A-Za-z0-9_-])${esc_key}([^A-Za-z0-9_-]|\$)" "$doc" 2>/dev/null; then
        found=1
        break
      fi
    done
    if [ "$found" -eq 0 ]; then
      echo "  未転記: ${key}（分類: ${section}）" >&2
      missing=$((missing + 1))
    fi
  done <<EOF
$rows
EOF

  if [ "$missing" -gt 0 ]; then
    echo "完全性ゲート失敗: facts.yml $total 件中 $missing 件が設計書に未転記です（fail-closed）" >&2
    return 1
  fi
  echo "完全性ゲート通過: facts.yml $total 件すべてが設計書に転記済みです"
  return 0
}

# 合成フィクスチャによる自己テスト。
self_test() {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-fact-coverage-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  # 陽性フィクスチャ: ①import は設計書に言及され、⑨measurement_pendingは
  # 「実測委譲」表記があるため個別キー一致なしでも転記済み扱いになる。
  cat > "$tmp/facts-pos.yml" <<'YML'
run_id: extract-1
profile: screen
target_repo_path: /abs/path/to/repo
target_file_paths:
  - src/screens/Foo/Foo.tsx
sections:
  import:
    reason: ""
    items:
      - key: import-react-useState
        value: "react から useState"
        evidence: "src/screens/Foo/Foo.tsx:1"
  measurement_pending:
    reason: ""
    items:
      - key: 初期表示-件数
        evidence: "src/screens/Foo/Foo.tsx:12"
YML

  cat > "$tmp/design-pos.md" <<'MD'
# 画面詳細設計書
## §15.3 依存（import）一覧
import-react-useState を使用する。

## §9 領域別仕様
初期表示件数は実測委譲（画面単位検証で確定）。
MD

  # 陰性フィクスチャ1: import-axios-client が未転記。
  cat > "$tmp/facts-neg1.yml" <<'YML'
run_id: extract-1
profile: screen
target_repo_path: /abs/path/to/repo
target_file_paths:
  - src/screens/Foo/Foo.tsx
sections:
  import:
    reason: ""
    items:
      - key: import-react-useState
        value: "react から useState"
        evidence: "src/screens/Foo/Foo.tsx:1"
      - key: import-axios-client
        value: "axios から client"
        evidence: "src/screens/Foo/Foo.tsx:2"
  measurement_pending:
    reason: ""
    items:
      - key: 初期表示-件数
        evidence: "src/screens/Foo/Foo.tsx:12"
YML

  # 陰性フィクスチャ2: measurement_pendingが「実測委譲」表記なし・個別キーも未転記。
  cat > "$tmp/facts-neg2.yml" <<'YML'
run_id: extract-1
profile: screen
target_repo_path: /abs/path/to/repo
target_file_paths:
  - src/screens/Foo/Foo.tsx
sections:
  import:
    reason: ""
    items:
      - key: import-react-useState
        value: "react から useState"
        evidence: "src/screens/Foo/Foo.tsx:1"
  measurement_pending:
    reason: ""
    items:
      - key: 初期表示-件数
        evidence: "src/screens/Foo/Foo.tsx:12"
YML

  cat > "$tmp/design-neg2.md" <<'MD'
# 画面詳細設計書
## §15.3 依存（import）一覧
import-react-useState を使用する。
MD

  rc=0

  if run_check "$tmp/facts-pos.yml" "$tmp/design-pos.md" >/dev/null 2>&1; then
    echo "  [PASS] 陽性: 転記済み+実測委譲表記ありで exit 0"
  else
    echo "  [FAIL] 陽性: 転記済みなのに非0で終了した" >&2
    rc=1
  fi

  if run_check "$tmp/facts-neg1.yml" "$tmp/design-pos.md" >/dev/null 2>&1; then
    echo "  [FAIL] 陰性1: import未転記1件ありなのに exit 0 になった" >&2
    rc=1
  else
    echo "  [PASS] 陰性1: import未転記1件で exit 1"
  fi

  if run_check "$tmp/facts-neg2.yml" "$tmp/design-neg2.md" >/dev/null 2>&1; then
    echo "  [FAIL] 陰性2: 実測委譲表記なし・個別キー未転記なのに exit 0 になった" >&2
    rc=1
  else
    echo "  [PASS] 陰性2: 実測委譲表記なし・個別キー未転記で exit 1"
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

facts_yml="${1:?引数1 facts.yml が必要です}"
shift || true
if [ "$#" -lt 1 ]; then
  echo "エラー: 設計書を 1 つ以上指定してください（使い方: check-fact-coverage.sh <facts.yml> <画面詳細設計書.md> [<DESIGN.md> ...]）" >&2
  exit 2
fi
for f in "$facts_yml" "$@"; do
  if [ ! -f "$f" ]; then
    echo "エラー: ファイルが見つかりません: $f" >&2
    exit 2
  fi
done

run_check "$facts_yml" "$@"
