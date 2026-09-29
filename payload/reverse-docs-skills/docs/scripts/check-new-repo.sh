#!/usr/bin/env bash
# check-new-repo.sh — 「新リポジトリへ体系を作り直す指示書.md」の判定表2〜11の
# 「確かめる手段」欄を短くする。
#
# なぜ要るか: 判定表の各行は新リポジトリ（$HOME/Projects/ai-driven-
#   development-setup）への絶対パスを含む長いコマンドを書いており、1文が
#   100字を超えると片付けの判定器の追加行検査（textlint の
#   ja-technical-writing/sentence-length）に止められる。実際に判定9（統括の
#   計画）の行を1文字書き換えただけで commit が止まった。式をこのファイルへ
#   移し、表からは短いキーだけを呼ぶ形にする
#   （先例: docs/scripts/check-boundary-value-scope.sh・
#   docs/scripts/check-api-only-sample.sh）。
#
# 使い方:
#   bash docs/scripts/check-new-repo.sh <キー>
#   bash docs/scripts/check-new-repo.sh --self-test
#
# キー一覧（指示書の判定表2〜11に対応）:
#   basic-design-check-self-test / document-writing-checkable /
#   reverse-order-check-self-test / acceptance / mapping-total-37 /
#   building-delivery-tests / acceptance-reverse / plan-setup /
#   sync-manifest-registered / old-reverse-skills-removed
#
# 終了コード: 各判定のコマンドの終了コードをそのまま返す。新リポジトリが
#   実在しない場合は [UNKNOWN] を出し終了コード2で終える
#   （.claude/rules/always/verification/indeterminate-result/rule.md の
#   判定不能規約に従う）。未知のキーは使い方を出し終了コード2で終える。
#
# 既知の限界: old-reverse-skills-removed は新リポジトリではなく旧リポジトリ
#   （このリポジトリ自身）の状態を見る判定だが、他のキーと同じ枠組みに
#   揃えるため新リポジトリの実在確認を共通の前提として先に行う。

set -uo pipefail

NEW_REPO="$HOME/Projects/reverse-design-skills"
OLD_REPO="$HOME/Projects/reverse-docs-skills"

usage() {
  echo "usage: $0 <basic-design-check-self-test|document-writing-checkable|reverse-order-check-self-test|acceptance|mapping-total-37|building-delivery-tests|acceptance-reverse|plan-setup|sync-manifest-registered|old-reverse-skills-removed>" >&2
}

run_key() {
  local key="$1"
  case "$key" in
    basic-design-check-self-test)
      bash "$NEW_REPO/docs/skills/setup-scaffolding-rules/templates/rules/checkers/check-basic-design-completion.sh" --self-test
      ;;
    document-writing-checkable)
      grep -q "^checkable: true" "$NEW_REPO/docs/skills/setup-scaffolding-rules/templates/rules/tool-defined/documentation-standards/document-writing/rule.md"
      ;;
    reverse-order-check-self-test)
      bash "$NEW_REPO/docs/skills/setup-scaffolding-rules/templates/rules/checkers/check-reverse-design-order.sh" --self-test
      ;;
    acceptance)
      bash "$NEW_REPO/docs/skills/setup-checking-acceptance/scripts/check-acceptance.sh" "$NEW_REPO"
      ;;
    mapping-total-37)
      grep -q "合計 \| 37" "$NEW_REPO/docs/design/旧skillの対応表.md"
      ;;
    building-delivery-tests)
      bash "$NEW_REPO/docs/skills/setup-building-delivery/tests/test-self-tests.sh"
      ;;
    acceptance-reverse)
      bash "$NEW_REPO/docs/skills/setup-checking-acceptance/scripts/check-acceptance.sh" "$NEW_REPO" --unit reverse
      ;;
    plan-setup)
      bash "$NEW_REPO/docs/skills/setup-orchestrating-units/scripts/plan-setup.sh" "$NEW_REPO" --units setup,reverse
      ;;
    sync-manifest-registered)
      grep -q "payload/reverse-design-skills" "$HOME/github-public/agent-toolkit/scripts/sync-manifest.json"
      ;;
    old-reverse-skills-removed)
      test ! -d "$OLD_REPO/.claude/skills/generating-screen-list-for-reverse-docs"
      ;;
    *)
      usage
      return 2
      ;;
  esac
}

self_test() {
  local rc=0

  # 系1: 未知のキーは使い方を出し終了コード2
  local out code
  out="$(run_key "no-such-key" 2>&1)"; code=$?
  if [ "$code" -eq 2 ] && printf '%s' "$out" | grep -qF 'usage:'; then
    echo "  [PASS] 系1: 未知のキーは使い方を出し終了コード2で終わる"
  else
    echo "  [FAIL] 系1: 未知のキーの扱いが違う（exit=${code}）" >&2
    rc=1
  fi

  # 系2: 実在するキー（old-reverse-skills-removed）は case 分岐へ到達し、
  # usage を出さずに実際の判定コマンドを実行する
  out="$(run_key "old-reverse-skills-removed" 2>&1)"; code=$?
  if ! printf '%s' "$out" | grep -qF 'usage:'; then
    echo "  [PASS] 系2: 実在するキーは usage を出さず判定コマンドへ到達する（exit=${code}）"
  else
    echo "  [FAIL] 系2: 実在するキーなのに usage が出た" >&2
    rc=1
  fi

  # 系3: 引数無し（空文字キー）も未知のキーと同じ扱いになる
  out="$(run_key "" 2>&1)"; code=$?
  if [ "$code" -eq 2 ] && printf '%s' "$out" | grep -qF 'usage:'; then
    echo "  [PASS] 系3: 引数無しは未知のキーと同じ扱いになる"
  else
    echo "  [FAIL] 系3: 引数無しの扱いが違う（exit=${code}）" >&2
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
  local key="${1:-}"

  if [ "$key" = "--self-test" ]; then
    self_test
    exit $?
  fi

  if [ -z "$key" ]; then
    usage
    exit 2
  fi

  if [ ! -d "$NEW_REPO" ]; then
    echo "[UNKNOWN] 新リポジトリ（${NEW_REPO}）が実在しないため判定できません"
    exit 2
  fi

  run_key "$key"
  exit $?
}

main "$@"
