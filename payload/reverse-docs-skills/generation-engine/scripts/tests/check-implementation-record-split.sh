#!/usr/bin/env bash
# check-implementation-record-split.sh — 詳細設計書の分割（改善課題1-288）が期待どおりに働くかを見る
#
# 使い方: bash check-implementation-record-split.sh --self-test
# 判定:
#   1. 宣言のファイル（design-doc-required-sections.json）が5種別の詳細設計書と実装記録の両方の節の一覧を持つ
#   2. 配置の宣言（design-unit-layout.json）の detail が両文書を持ち、scaffold が合成の入力で2文書を配置する
#   3. 分ける処理（split-implementation-record.pl）が合成の入力から2文書を作り、現行実装の節だけが実装記録へ移る
#   4. 納品物の一覧（deliverable-inventory.json）が5種別で両文書を登録している
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
R="$ROOT/delivery-payload/references"
self_test() {
  local rc=0 tmp
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/impl-record-split.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktemp が一時領域へ書き込めませんでした）"; return 2; fi
  local pairs="api:API詳細設計書.md:API実装記録.md table:テーブル定義書.md:テーブル実装記録.md batch:バッチ詳細設計書.md:バッチ実装記録.md report:帳票詳細設計書.md:帳票実装記録.md external:外部連携詳細設計書.md:外部連携実装記録.md"
  local ok=1 p k d r
  for p in $pairs; do IFS=: read -r k d r <<< "$p"
    _cap="$(jq -e --arg k "$k" --arg d "$d" --arg r "$r" '((.documentTypes[$k][$d].requiredSections|length)>0) and ((.documentTypes[$k][$r].requiredSections|length)>0)' "$R/design-doc-required-sections.json" 2>&1)" || { ok=0; echo "  宣言に節の一覧が無い: $k $d / $r"; }
    _cap="$(jq -e --arg k "$k" --arg d "$d" --arg r "$r" '(.kinds[$k].phases.detail|index($d))!=null and (.kinds[$k].phases.detail|index($r))!=null' "$R/design-unit-layout.json" 2>&1)" || { ok=0; echo "  配置の宣言に両文書が無い: $k"; }
    _cap="$(jq -e --arg k "$k" --arg d "$d" --arg r "$r" '[.items[]|select(.kind==$k)|.unitDesignDocuments]|.[0]|(index($d)!=null and index($r)!=null)' "$R/deliverable-inventory.json" 2>&1)" || { ok=0; echo "  納品物の一覧に両文書が無い: $k"; }
  done
  if [ "$ok" -eq 1 ]; then echo "  [PASS] 検収1・3: 宣言・配置・納品物の一覧が5種別で2文書を持つ"; else echo "  [FAIL] 検収1・3"; rc=1; fi
  # 検収2: 合成の入力（scaffold）で2文書が配置される
  local out="$tmp/o"; mkdir -p "$out"
  if bash "$ROOT/generation-engine/scripts/scaffold-design-unit.sh" api detail "$out" fx 合成API "$ROOT/delivery-payload/templates/リバース検証" > "$tmp/.scaffold-out" 2>&1 \
     && [ -f "$out/docs/design/apis/api-fx/detail-design/API詳細設計書.md" ] && [ -f "$out/docs/design/apis/api-fx/detail-design/API実装記録.md" ]; then
    echo "  [PASS] 検収2: 合成の入力で詳細設計書と実装記録の2文書が配置される"
  else { echo "  [FAIL] 検収2: 2文書が配置されない"; sed 's/^/      /' "$tmp/.scaffold-out" >&2; }; rc=1; fi
  # 分ける処理: 合成の入力で現行実装の節だけが移る
  mkdir -p "$tmp/s"; printf -- '---\nunit_kind: api\n---\n\n# 合成 API詳細設計書\n\n## §1 API概要\n\n**この節の位置づけ: 仕様**\n\n本文\n\n## §2 疑似コード\n\n**この節の位置づけ: 現行実装。理由。作り直す際は引き継がない**\n\n擬似\n\n## §3 関連資料\n\n**この節の位置づけ: 仕様**\n\n§2 を見る。\n' > "$tmp/s/API詳細設計書.md"
  _cap="$(perl "$ROOT/generation-engine/scripts/design-docs/split-implementation-record.pl" "$tmp/s/API詳細設計書.md" 2>&1)"
  if [ -f "$tmp/s/API実装記録.md" ] && grep -q '^## §1 疑似コード' "$tmp/s/API実装記録.md" && ! grep -q '疑似コード' "$tmp/s/API詳細設計書.md" && grep -q '^## §2 関連資料' "$tmp/s/API詳細設計書.md" && grep -q 'API実装記録 §1 を見る' "$tmp/s/API詳細設計書.md"; then
    echo "  [PASS] 分ける処理: 現行実装の節だけが実装記録へ移り、仕様の節は採番し直され、移った節への参照は文書名付きになる"
  else echo "  [FAIL] 分ける処理の結果が期待と違う"; sed -n 1,30p "$tmp/s/API詳細設計書.md"; rc=1; fi
  printf '%s\n' "$_cap" | sed 's/^/      /' >&2
  rm -rf "$tmp"; [ "$rc" -eq 0 ] && echo "self-test PASS" || echo "self-test FAIL"; return "$rc"
}
case "${1:-}" in --self-test) self_test ;; *) echo "usage: $0 --self-test" >&2; exit 2 ;; esac
