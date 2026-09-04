#!/usr/bin/env bash
# check-generated-html-manual-edit.sh — 「HTML を直接編集しない」規則の linter
#
# timing: PreToolUse(Write|Edit)
# 対象規約: 生成した文書を直接編集しない決まり「HTML を直接編集しない」
#
# 判定:
#   Write/Edit の書き込み先ファイルが既にファイルシステム上に存在し、かつ
#   その既存内容に生成物マーカー（id="page-data" / id="unit-manifest" /
#   id="screen-manifest" のいずれか）が含まれる場合、そのファイルは生成物の
#   HTML であるとみなし、手作業での上書きを違反として block（exit 2）する。
#   新規作成（対象ファイルが存在しない）や、マーカーを持たない通常の HTML は
#   対象外とする。
#
# 判定の設計:
#   生成物の台帳（内容ハッシュの記録）は納品先ごとに置き場所が異なりうるため、
#   汎用の linter からは参照できない。そこで、生成器が埋め込む既知のデータ
#   マーカー（id="page-data" 等）を「この HTML は生成物である」という
#   ファイル内容だけで完結する目印として使う。ディレクトリ名の慣行にも
#   台帳にも依存しないため、納品先の配置構成が変わっても機能する。
#
# 除外条件（誤検知回避）:
#   - tool_name が Write / Edit 以外 → 対象外
#   - 対象ファイルがまだ存在しない（新規作成） → 対象外
#   - 既存ファイルにマーカーが含まれない（生成物ではない通常の HTML） → 対象外
#
# 既知の限界:
#   - マーカーの3種以外の生成方式を採る場合は検知できない
#   - MultiEdit は対象外（本checkerは Write / Edit のみに対応する）
#
# 使い方:
#   フック本体として: PreToolUse(Write|Edit) の入力 JSON を stdin から受け取る
#   単体実行: check-generated-html-manual-edit.sh --self-test
#
# 止めるか知らせるか:
#   HTML を直接編集しない: 止める（生成物のHTMLを手作業で書き換えると生成の実行結果と食い違い、以後の再生成で気付けなくなるため）
#
# 逃げ道:
#   GENERATED_HTML_MANUAL_EDIT_SKIP_REASON に理由を書けば通る。理由が空の場合は通らない
set -uo pipefail

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${GENERATED_HTML_MANUAL_EDIT_SKIP_REASON:-}" ]; then
    echo "[GENERATED-HTML-MANUAL-EDIT-SKIP] 理由: ${GENERATED_HTML_MANUAL_EDIT_SKIP_REASON}"
    return 0
  fi
  return 1
}

MARKER_RE='id="page-data"|id="unit-manifest"|id="screen-manifest"'

judge() {
  # $1: file_path
  # 標準出力: 判定理由。戻り値: 0=許可・2=拒否
  local file_path="$1"

  if [ ! -f "$file_path" ]; then
    echo "対象外[HTML を直接編集しない]: 新規作成のため生成物の既存判定はできません（${file_path}）"
    return 0
  fi

  if grep -qE "$MARKER_RE" "$file_path" 2>/dev/null; then
    echo "拒否[HTML を直接編集しない]: ${file_path} は生成物マーカーを含む生成済み HTML です"
    return 2
  fi

  echo "対象外[HTML を直接編集しない]: 生成物マーカーを含まないため通常のファイルとして扱う"
  return 0
}

run_hook() {
  local skip_msg
  if skip_msg="$(should_skip_with_reason)"; then
    printf '%s\n' "$skip_msg" >&2
    exit 0
  fi

  local input
  input="$(cat)"
  [ -z "$input" ] && exit 0

  local tool
  tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
  [ "$tool" != "Write" ] && [ "$tool" != "Edit" ] && exit 0

  local file_path
  file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
  [ -z "$file_path" ] && exit 0

  local msg code
  if msg="$(judge "$file_path")"; then code=0; else code=$?; fi

  [ "$code" -eq 0 ] && exit 0

  ctx="[GENERATED-HTML-MANUAL-EDIT-BLOCK] ${msg}。手作業で直さず、生成スクリプトを再実行して再生成してください。"
  jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  printf '%s\n' "$ctx" >&2
  exit 2
}

self_test() {
  local tmp rc=0 msg code
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-generated-html-manual-edit-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  trap 'rm -rf "$tmp"' RETURN

  # 系1: 新規作成（未存在） → 許可
  local new_file="$tmp/new.html"
  if msg="$(judge "$new_file")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系1: 新規作成は許可される（${msg}）"
  else
    echo "  [FAIL] 系1: 新規作成なのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系2: 既存ファイルに id="unit-manifest" マーカーあり → 拒否
  local generated="$tmp/list.html"
  printf '<html><body><script type="application/json" id="unit-manifest">{}</script></body></html>\n' > "$generated"
  if msg="$(judge "$generated")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系2: unit-manifestマーカーありは拒否される（${msg}）"
  else
    echo "  [FAIL] 系2: マーカーがあるのに許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系3: 既存ファイルに id="page-data" マーカーあり → 拒否
  local generated2="$tmp/detail.html"
  printf '<html><body><script id="page-data">{}</script></body></html>\n' > "$generated2"
  if msg="$(judge "$generated2")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系3: page-dataマーカーありは拒否される（${msg}）"
  else
    echo "  [FAIL] 系3: マーカーがあるのに許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系4: 既存ファイルだがマーカーなし（通常のHTML） → 許可
  local plain="$tmp/plain.html"
  printf '<html><body><p>手書きのページ</p></body></html>\n' > "$plain"
  if msg="$(judge "$plain")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系4: マーカーなしの既存HTMLは許可される（${msg}）"
  else
    echo "  [FAIL] 系4: マーカーがないのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系5: 環境変数に理由を設定 → should_skip_with_reasonが戻り値0でタグと理由を返す
  local out5
  if out5="$(GENERATED_HTML_MANUAL_EDIT_SKIP_REASON="テスト用の理由" should_skip_with_reason)"; then
    if printf '%s' "$out5" | grep -qF '[GENERATED-HTML-MANUAL-EDIT-SKIP]' && printf '%s' "$out5" | grep -qF 'テスト用の理由'; then
      echo "  [PASS] 系5: 理由を設定するとタグと理由付きでskipされる（${out5}）"
    else
      echo "  [FAIL] 系5: skipされたがタグまたは理由が出力に含まれない（${out5}）" >&2
      rc=1
    fi
  else
    echo "  [FAIL] 系5: 理由を設定したのにskipされなかった" >&2
    rc=1
  fi

  # 系6: 環境変数が空文字 → should_skip_with_reasonが戻り値1を返す
  if _cap="$(GENERATED_HTML_MANUAL_EDIT_SKIP_REASON="" should_skip_with_reason 2>&1)"; then
    echo "  [FAIL] 系6: 空文字なのにskipされた" >&2
    printf '%s\n' "$_cap" | sed 's/^/      /' >&2
    rc=1
  else
    echo "  [PASS] 系6: 環境変数が空文字ならskipされない"
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

case "${1:-}" in
  --self-test) self_test; exit $? ;;
  *) run_hook ;;
esac
