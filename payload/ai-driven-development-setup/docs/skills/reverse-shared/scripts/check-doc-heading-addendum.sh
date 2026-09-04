#!/usr/bin/env bash
# 写し: 定義は setup の規約の様式（document-writing / test-policy）。同一性は reverse-shared の tests が確かめる
# check-doc-heading-addendum.sh — 設計書の書き方の決まりの linter
#
# timing: PreToolUse(Write|Edit)
# 対象規約: 設計書の書き方の決まり
#
# 対象の規則（検査列に「静的解析:」を含む4件のうち4件すべてを検査する）:
#   1. 追記章と補足章を作らない
#      — Markdown 見出しが「追記」「補足」「その他」で始まっていないかを
#        走査する（既存の検査）
#   2. 任意記載と省略記載をしない
#      — 本文に「…」「以下略」で列挙を打ち切る記述が無いかを走査する
#        （「等」は日常語として頻出し誤検知が避けられないため対象外。
#        既知の限界として明記する）
#   3. 要件定義書は合意した範囲を確定させる
#      — ファイル名に「要件定義書」を含む文書に、対象範囲・優先度・
#        受入条件の3見出しがあるかを走査する
#   4. 基本設計書は詳細設計を書ける状態を作る
#      — ファイル名に「基本設計書」を含む文書に、完了状態の各項目に対応する
#        見出し（外部仕様・業務仕様の確定・方式設計・データ仕様の確定・
#        エラーと例外の仕様確定・単体テスト設計書）があるかを走査する
#
# 判定の設計:
#   追記章の検査は、見出し行（^#{1,6}\s+...）という記号的な特徴で機械的に
#   検出する（既存の設計を維持）。省略記載の検査も同様に、本文中の記号
#   （「…」「以下略」）の出現という記号的な特徴で判定する。
#   要件定義書・基本設計書の完了状態の検査は、設計書の書き方の決まり自体が
#   「設計書に何の節を置くかの目録」であり対象を要件定義書・基本設計書・
#   詳細設計書の3文書に限定しているため、他の規約（業務の判定の書き方の決まり・金額と数量の計算の決まり等）
#   と異なりファイル名の慣行（「○○要件定義書.md」「○○基本設計書.md」）
#   から対象文書の種別を機械的に特定できる。この判定方式は
#   check-unit-test-design-doc-sections.sh（単体テスト設計書の決まり）の既存の実装と
#   同じ考え方を踏襲した。
#
# 対象ファイル:
#   Markdown（.md）を前提とする（見出し記法・表記法がその他の形式では
#   成立しないため）。要件定義書・基本設計書の検査はファイル名一致が
#   さらに必要。
#
# 除外条件（誤検知回避）:
#   - tool_name が Write / Edit 以外 → 対象外
#   - 本文中に該当語が出現しても、見出し行でなければ対象外（誤検知回避）
#   - 本文（content / new_string）が空 → 対象外
#   - ファイル名に「要件定義書」「基本設計書」を含まない → 各該当検査は対象外
#
# 既知の限界:
#   - MultiEdit は対象外（本checkerは Write / Edit のみに対応する）
#   - 見出しの階層（# の個数）は問わない
#   - 省略記載の検査は「等」を対象に含めない。日常的な列挙終端の語として
#     頻出し、通常の文章でも多用されるため、これを含めると誤検知が避けられない
#   - 要件定義書・基本設計書の検査は見出しの存在だけを見る。各見出し配下の
#     記述内容が実際に確定しているか（不明点が残っていないか）までは判定
#     しない
#
# 止めるか知らせるか:
#   追記章と補足章を作らない: 止める（追記・補足の見出しがそのまま確定すると、章立てを設計し直さない場当たりの追記が履歴に残り続けるため）
#   任意記載と省略記載をしない: 止める（省略記載がそのまま確定すると、打ち切られた内容が何であったか後から復元できなくなるため）
#   要件定義書は合意した範囲を確定させる: 止める（対象範囲・優先度・受入条件を欠いた要件定義書が確定すると、合意した範囲を後から復元できなくなるため）
#   基本設計書は詳細設計を書ける状態を作る: 止める（完了状態の見出しを欠いた基本設計書が確定すると、詳細設計に進める根拠を後から復元できなくなるため）
#
# 逃げ道:
#   DOC_HEADING_ADDENDUM_SKIP_REASON に理由を書けば通る。理由が空の場合は通らない
#
# 使い方:
#   フック本体として: PreToolUse(Write|Edit) の入力 JSON を stdin から受け取る
#   単体実行: check-doc-heading-addendum.sh --self-test
set -uo pipefail

HEADING_RE='^#{1,6}[[:space:]]+(追記|補足|その他)'
ELLIPSIS_RE='(…|\.\.\.|以下略)'
REQUIREMENTS_SECTIONS="対象範囲 優先度 受入条件"
BASIC_DESIGN_SECTIONS="外部仕様 業務仕様の確定 方式設計 データ仕様の確定 エラーと例外の仕様確定 単体テスト設計書"

# 必須見出しの欠落を確認する。$1: 本文, $2: 見出し語のスペース区切り一覧
# 出力: 欠落している見出し語をスペース区切りで返す（すべて揃っていれば空）
missing_sections() {
  local text="$1" sections="$2" missing="" section
  for section in $sections; do
    if ! printf '%s\n' "$text" | grep -qE "^#{1,6}[^\n]*${section}"; then
      missing="${missing}${missing:+、}${section}"
    fi
  done
  printf '%s' "$missing"
}

judge() {
  # $1: file_path, $2: 本文テキスト
  # 標準出力: 判定理由。戻り値: 0=許可・2=拒否
  local file_path="$1" text="$2"

  if [ -z "$text" ]; then
    echo "対象外: 本文が空"
    return 0
  fi

  local hit
  hit=$(printf '%s\n' "$text" | grep -nE "$HEADING_RE" | head -1)
  if [ -n "$hit" ]; then
    echo "拒否[追記章と補足章を作らない]: 追記・補足・その他で始まる見出しがある（${hit}）"
    return 2
  fi

  local ellipsis_hit
  ellipsis_hit=$(printf '%s\n' "$text" | grep -nE "$ELLIPSIS_RE" | head -1)
  if [ -n "$ellipsis_hit" ]; then
    echo "拒否[任意記載と省略記載をしない]: 「…」「以下略」で列挙を打ち切る記述がある（${ellipsis_hit}）"
    return 2
  fi

  local base missing
  base="$(basename "$file_path")"

  if printf '%s' "$base" | grep -qF '要件定義書'; then
    missing="$(missing_sections "$text" "$REQUIREMENTS_SECTIONS")"
    if [ -n "$missing" ]; then
      echo "拒否[要件定義書は合意した範囲を確定させる]: 必須見出しが欠けています（${missing}）"
      return 2
    fi
  fi

  if printf '%s' "$base" | grep -qF '基本設計書'; then
    missing="$(missing_sections "$text" "$BASIC_DESIGN_SECTIONS")"
    if [ -n "$missing" ]; then
      echo "拒否[基本設計書は詳細設計を書ける状態を作る]: 必須見出しが欠けています（${missing}）"
      return 2
    fi
  fi

  echo "許可: 追記・補足章、省略記載、必須見出しの欠落のいずれも見当たらない"
  return 0
}

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${DOC_HEADING_ADDENDUM_SKIP_REASON:-}" ]; then
    echo "[DOC-HEADING-ADDENDUM-SKIP] 理由: ${DOC_HEADING_ADDENDUM_SKIP_REASON}"
    return 0
  fi
  return 1
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

  local file_path text
  file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
  if [ "$tool" = "Write" ]; then
    text=$(printf '%s' "$input" | jq -r '.tool_input.content // empty' 2>/dev/null)
  else
    text=$(printf '%s' "$input" | jq -r '.tool_input.new_string // empty' 2>/dev/null)
  fi

  local msg code
  if msg="$(judge "$file_path" "$text")"; then code=0; else code=$?; fi

  [ "$code" -eq 0 ] && exit 0

  ctx="[DOC-HEADING-ADDENDUM-BLOCK] ${msg}。指摘された章・記述・見出しを修正してから再実行してください。"
  jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  printf '%s\n' "$ctx" >&2
  exit 2
}

self_test() {
  local rc=0 msg code

  # 系1: 見出し「## 追記」あり → 拒否
  local t1='# 設計書

## 概要
本文。

## 追記
後から足した内容。'
  if msg="$(judge "docs/設計書.md" "$t1")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系1: 「追記」見出しは拒否される（${msg}）"
  else
    echo "  [FAIL] 系1: 「追記」見出しがあるのに許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系2: 見出し「### 補足事項」あり → 拒否
  local t2='# 設計書

## 概要
本文。

### 補足事項
書き足した注記。'
  if msg="$(judge "docs/設計書.md" "$t2")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系2: 「補足事項」見出しは拒否される（${msg}）"
  else
    echo "  [FAIL] 系2: 「補足事項」見出しがあるのに許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系3: 通常の見出しのみ → 許可
  local t3='# 設計書

## 概要
本文。

## 対象範囲
記載。'
  if msg="$(judge "docs/設計書.md" "$t3")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系3: 通常の見出しのみは許可される（${msg}）"
  else
    echo "  [FAIL] 系3: 通常の見出しなのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系4: 本文中（見出しではない地の文）に「追記」が出るだけ → 許可（誤検知回避）
  local t4='# 設計書

## 概要
この節は後で追記する予定はない。その他の事情も無い。'
  if msg="$(judge "docs/設計書.md" "$t4")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系4: 地の文の言及のみは許可される（${msg}）"
  else
    echo "  [FAIL] 系4: 見出しではないのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系5: 「…」で列挙を打ち切る記述がある → 拒否（任意記載と省略記載をしない）
  local t5='# 設計書

## 画面項目
氏名、住所、電話番号…'
  if msg="$(judge "docs/設計書.md" "$t5")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '任意記載と省略記載をしない'; then
    echo "  [PASS] 系5: 「…」で打ち切る記述は拒否される（${msg}）"
  else
    echo "  [FAIL] 系5: 省略記載があるのに許可、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系6: 「以下略」で列挙を打ち切る記述がある → 拒否（任意記載と省略記載をしない）
  local t6='# 設計書

## 画面項目
氏名、住所、電話番号、以下略'
  if msg="$(judge "docs/設計書.md" "$t6")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '任意記載と省略記載をしない'; then
    echo "  [PASS] 系6: 「以下略」で打ち切る記述は拒否される（${msg}）"
  else
    echo "  [FAIL] 系6: 省略記載があるのに許可、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系7（近傍事例）: 省略記号を含まない全項目の列挙 → 許可
  local t7='# 設計書

## 画面項目
氏名、住所、電話番号、生年月日'
  if msg="$(judge "docs/設計書.md" "$t7")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系7: 省略記号を含まない全項目の列挙は許可される（${msg}）"
  else
    echo "  [FAIL] 系7: 省略記載が無いのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系8: ファイル名が「要件定義書」で、必須見出し（対象範囲・優先度・受入条件）が欠けている → 拒否
  local t8='# 注文機能要件定義書

## 対象範囲
注文の受付から発送までを対象とする。

## 優先度
最優先。'
  if msg="$(judge "docs/注文機能要件定義書.md" "$t8")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '要件定義書は合意した範囲を確定させる'; then
    echo "  [PASS] 系8: 受入条件の見出しが欠けた要件定義書は拒否される（${msg}）"
  else
    echo "  [FAIL] 系8: 見出しが欠けているのに許可、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系9: ファイル名が「要件定義書」で、必須見出し3つが揃っている → 許可
  local t9='# 注文機能要件定義書

## 対象範囲
注文の受付から発送までを対象とする。

## 優先度
最優先。

## 受入条件
すべての注文が正しく記録されること。'
  if msg="$(judge "docs/注文機能要件定義書.md" "$t9")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系9: 必須見出し3つが揃った要件定義書は許可される（${msg}）"
  else
    echo "  [FAIL] 系9: 必須見出しが揃っているのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系10: ファイル名が「基本設計書」で、完了状態の見出しが欠けている → 拒否
  local t10='# 注文機能基本設計書

## 外部仕様
画面・帳票・外部インタフェースを確定する。

## 方式設計
性能方式・可用性方式を確定する。'
  if msg="$(judge "docs/注文機能基本設計書.md" "$t10")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '基本設計書は詳細設計を書ける状態を作る'; then
    echo "  [PASS] 系10: 完了状態の見出しが欠けた基本設計書は拒否される（${msg}）"
  else
    echo "  [FAIL] 系10: 見出しが欠けているのに許可、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系11: ファイル名が「基本設計書」で、完了状態の見出しがすべて揃っている → 許可
  local t11='# 注文機能基本設計書

## 外部仕様
画面・帳票・外部インタフェースを確定する。

## 業務仕様の確定
業務フロー・状態遷移・業務ルールを確定する。

## 方式設計
性能方式・可用性方式を確定する。

## データ仕様の確定
概念と論理を確定する。

## エラーと例外の仕様確定
エラー分類・エラーコード体系を確定する。

## 単体テスト設計書
テスト観点を確定する。'
  if msg="$(judge "docs/注文機能基本設計書.md" "$t11")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系11: 完了状態の見出しがすべて揃った基本設計書は許可される（${msg}）"
  else
    echo "  [FAIL] 系11: 見出しが揃っているのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系12（近傍事例）: 要件定義書・基本設計書のどちらでもないファイル名 → 見出し欠落検査は対象外として許可
  local t12='# メモ

## 概要
自由に書いたメモ。'
  if msg="$(judge "docs/メモ.md" "$t12")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系12: 要件定義書・基本設計書以外は見出し欠落検査の対象外として許可される（${msg}）"
  else
    echo "  [FAIL] 系12: 対象外ファイル名なのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系13: 環境変数に理由を設定すると should_skip_with_reason は skip する
  local skip_out skip_code
  if skip_out="$(DOC_HEADING_ADDENDUM_SKIP_REASON="テスト理由" should_skip_with_reason)"; then skip_code=0; else skip_code=$?; fi
  if [ "$skip_code" -eq 0 ] && printf '%s' "$skip_out" | grep -qF 'DOC-HEADING-ADDENDUM-SKIP' && printf '%s' "$skip_out" | grep -qF 'テスト理由'; then
    echo "  [PASS] 系13: 理由を設定すると should_skip_with_reason は skip する（${skip_out}）"
  else
    echo "  [FAIL] 系13: 理由があるのに skip しない、またはタグ・理由が含まれない（exit=${skip_code}, ${skip_out}）" >&2
    rc=1
  fi

  # 系14: 環境変数を空文字にすると should_skip_with_reason は skip しない
  local skip_code2
  if DOC_HEADING_ADDENDUM_SKIP_REASON="" should_skip_with_reason >/dev/null 2>&1; then skip_code2=0; else skip_code2=$?; fi
  if [ "$skip_code2" -eq 1 ]; then
    echo "  [PASS] 系14: 環境変数が空文字なら should_skip_with_reason は skip しない"
  else
    echo "  [FAIL] 系14: 空文字なのに skip した（exit=${skip_code2}）" >&2
    rc=1
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
