#!/usr/bin/env bash
# check-confirmation-ledger-current-template.sh — check-confirmation-ledger.mjs が
# 現行の画面詳細設計書テンプレート（§19 関連資料。要確認事項一覧の見出しを持たない）
# に対して機能するかを検査する。
#
# 改善課題1-215は、check-confirmation-ledger.mjsが「## 要確認事項一覧」という
# 見出しを設計書に求めるが、後発の改善課題1-223がその見出しを全テンプレートから
# 消したため、現行テンプレートに対して常に異常終了する問題を扱う。判定は
# 「一時領域を作る→現行テンプレートを複製する→最小の台帳を作る→
# check-confirmation-ledger.mjsを実行する」という複数段の手順であり、1行の
# 縦棒なしコマンドへ収められない
# （.claude/rules/always/tasks/instruction-format/rule.md の設計判断を参照）。
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE="$REPO_ROOT/delivery-payload/templates/リバース検証/画面/詳細設計/画面詳細設計書.md"
CHECKER="$REPO_ROOT/generation-engine/scripts/check-confirmation-ledger.mjs"

main() {
  local tmp
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/confirmation-ledger-current-template.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktemp）"
    return 2
  fi

  if [ ! -f "$TEMPLATE" ]; then
    echo "[UNKNOWN] テンプレートが見つかりません: $TEMPLATE"
    rm -rf "$tmp"
    return 2
  fi

  local doc="$tmp/画面詳細設計書.md"
  cp "$TEMPLATE" "$doc"
  # frontmatterのstatusをapprovedへ書き換える（承認の条件の再現のため）
  sed -i.bak 's/^status:.*/status: approved/' "$doc"
  rm -f "$doc.bak"

  local ledger="$tmp/要確認事項台帳.json"
  cat > "$ledger" <<'JSON'
{"unitKey":"screen-selftest","designDocument":"画面詳細設計書.md","items":[]}
JSON

  if node "$CHECKER" --ledger "$ledger" --design-doc "$doc" >"$tmp/out.log" 2>&1; then
    echo "[PASS] 現行テンプレートに対してcheck-confirmation-ledger.mjsが異常終了しない"
    rm -rf "$tmp"
    return 0
  fi
  echo "[FAIL] 現行テンプレートに対してcheck-confirmation-ledger.mjsが異常終了する"
  cat "$tmp/out.log"
  rm -rf "$tmp"
  return 1
}

main "$@"
exit $?
