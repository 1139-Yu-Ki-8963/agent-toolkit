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
#   - **値レベル検証**: 固定 props 値・enum 実使用値・コンポーネント宣言形状等、items[].value に
#     具体的な値文字列を持つ facts については、キーへの言及だけでなく value 文字列自体が設計書本文に
#     出現するかも確認する。value が見つからない場合は「値未転記」として stderr に WARN を出力する
#     （exit code には影響しない。既存の exit 1 = 未転記キー検出 の挙動を変更しない）。
#   - --self-test は合成フィクスチャで陽性 exit 0・陰性 exit 1・値未転記 WARN を自己検証する。
#
# 設計判断（ADR）の正本は本スキルの SKILL.md「## 設計判断」に記載する。
# 保守責任者: 人手（ユーザー）。facts.yml の書式・除外分類を変更した時に更新する。
# macOS bash 3.2 互換（mapfile 不使用）。

# facts.yml から「セクション名<TAB>キー<TAB>値」を1行ずつ抽出する。値フィールドが
# 無いitems（evidenceのみ等）は値列が空文字になる。
# 固定インデント契約（shared/references/facts-schema.md）:
#   sections配下のキー(2段目)  = 2スペース
#   items配下の "- key:"(4段目) = 6スペース
#   items配下の "value:"(4段目、keyと同じ項目内) = 8スペース
extract_section_keys() {
  awk '
    function flush_item() {
      if (key != "") print section "\t" key "\t" value
    }
    /^  [a-z_]+:[ \t]*$/ {
      flush_item()
      s = $0
      sub(/^  /, "", s)
      sub(/:[ \t]*$/, "", s)
      section = s
      key = ""
      value = ""
      next
    }
    /^      - key:/ {
      flush_item()
      k = $0
      sub(/^      - key:[ \t]*/, "", k)
      gsub(/^"/, "", k)
      gsub(/"$/, "", k)
      gsub(/^[ \t]+/, "", k)
      gsub(/[ \t]+$/, "", k)
      key = k
      value = ""
      next
    }
    /^        value:/ {
      v = $0
      sub(/^        value:[ \t]*/, "", v)
      gsub(/^"/, "", v)
      gsub(/"$/, "", v)
      gsub(/^[ \t]+/, "", v)
      gsub(/[ \t]+$/, "", v)
      value = v
      next
    }
    END { flush_item() }
  ' "$1"
}

# facts.yml と設計書群を突合する。未転記があれば return 1。
# 値レベル検証（固定props値・enum実使用値・コンポーネント宣言形状等、value
# フィールドを持つfacts）は設計書本文への値文字列出現も確認し、見つからなければ
# 「値未転記」としてstderrへWARNを出す（exit codeには影響しない。既存の
# exit 1 = 未転記キー検出 の挙動は維持する）。measurement_pendingは実測委譲設計
# のため値レベル検証の対象外とする。
run_check() {
  facts_yml="$1"
  shift
  missing=0
  total=0
  value_missing=0

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
    value="$(printf '%s' "$row" | cut -f3)"
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

    if [ "$section" != "measurement_pending" ] && [ -n "$value" ]; then
      value_found=0
      for doc in "$@"; do
        if grep -qF -- "$value" "$doc" 2>/dev/null; then
          value_found=1
          break
        fi
      done
      if [ "$value_found" -eq 0 ]; then
        echo "  WARN: 値未転記: ${key} の値「${value}」が設計書本文に見当たりません（分類: ${section}）" >&2
        value_missing=$((value_missing + 1))
      fi
    fi
  done <<EOF
$rows
EOF

  if [ "$missing" -gt 0 ]; then
    echo "完全性ゲート失敗: facts.yml $total 件中 $missing 件が設計書に未転記です（fail-closed）" >&2
    return 1
  fi
  if [ "$value_missing" -gt 0 ]; then
    echo "値レベル検証: $value_missing 件の値未転記WARNがあります（exit codeには影響しません）" >&2
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

  # 値レベル検証フィクスチャ: キーは転記済みだが value 文字列が設計書本文に
  # 出現しない（固定props値の値未転記）ケース。exit code は 0 のまま、
  # stderr に「値未転記」WARN が出ることを確認する。
  cat > "$tmp/facts-value.yml" <<'YML'
run_id: extract-1
profile: screen
target_repo_path: /abs/path/to/repo
target_file_paths:
  - src/screens/Foo/Foo.tsx
sections:
  const:
    reason: ""
    items:
      - key: const-max-count
        value: "MAX_COUNT=100"
        evidence: "src/screens/Foo/Foo.tsx:5"
YML

  cat > "$tmp/design-value-missing.md" <<'MD'
# 画面詳細設計書
## §10 定数・設定値
const-max-count を使用する。
MD

  cat > "$tmp/design-value-present.md" <<'MD'
# 画面詳細設計書
## §10 定数・設定値
const-max-count を使用する（MAX_COUNT=100）。
MD

  if out_value_missing="$(run_check "$tmp/facts-value.yml" "$tmp/design-value-missing.md" 2>&1)"; then rc_value_missing=0; else rc_value_missing=$?; fi
  if [ "$rc_value_missing" -eq 0 ] && printf '%s' "$out_value_missing" | grep -q "値未転記"; then
    echo "  [PASS] 値レベル検証陰性: キー転記済み・値未転記で WARN が出るが exit 0 のまま"
  else
    echo "  [FAIL] 値レベル検証陰性: 値未転記WARNが出ない、または exit 0 でない（exit=${rc_value_missing}）" >&2
    rc=1
  fi

  if out_value_present="$(run_check "$tmp/facts-value.yml" "$tmp/design-value-present.md" 2>&1)"; then rc_value_present=0; else rc_value_present=$?; fi
  if [ "$rc_value_present" -eq 0 ] && ! printf '%s' "$out_value_present" | grep -q "値未転記"; then
    echo "  [PASS] 値レベル検証陽性: 値も転記済みならWARNが出ない"
  else
    echo "  [FAIL] 値レベル検証陽性: 値転記済みなのにWARNが出た、または exit 0 でない（exit=${rc_value_present}）" >&2
    rc=1
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
