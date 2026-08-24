#!/usr/bin/env bash
# check-portal-dir-ascii.sh — project-portal/ 配下の一覧以外の置き場（マトリクス・
# 対応表・図・基盤・画面）が日本語のフォルダ名へ逆戻りしていないかを見る
#
# 判定の式を指示書の表へ直接書けないためスクリプトへ切り出した。式に含まれる
# 縦棒を片付けの判定器が列の区切りと読み違え、判定行そのものを壊すためである
# （.claude/rules/always/tasks/instruction-format/rule.md の設計判断を参照）。
#
# 背景: matrixDir・diagramDir・foundationDir・screenViewRoot の4つの置き場は
# project-portal/matrices・project-portal/diagrams・project-portal/foundation・
# project-portal/screens（英字）を正とする。日本語のディレクトリは3つの不具合を
# 起こすと実測で確かめたため
# （docs/tasks/work-records/2026-08-24-日本語のフォルダ名の実測.md）、この4つを
# 英字へ揃え直した（一覧以外の置き場も定義と実態が食い違う問題を直す指示書.md）。
# unitsRoot 等の一覧系5キーの1段下（project-portal/lists・project-portal/matrices
# 配下の種別ごとのフォルダ名）は、project-portal/ の直後のセグメントではないため
# 本検査の対象外である。この1段下にも日本語のフォルダ名（用語辞書・メッセージ
# 一覧等、9件）が残っていたが、ディレクトリ名の方針が実態と食い違う問題を直す
# 指示書.md で portal-catalog.json の blueprint.dir・discovery.glob を直接英字
# （semantic-glossary・message-list等）へ書き換え、解消済みである。この1段下の
# 逆戻りを継続監視する専用の検査は本指示書の完了の判定に含めず、portal-catalog.json・
# output-layout.json の該当パスへの grep（同指示書の完了の判定3・4）で代える判断
# とした（新規検査の追加は指示書の完了条件に含まれておらず、追加の保守コスト
# （--self-test・design-判断の記載・tests/ラッパー）に見合わないため）。
# check-list-path-unified.sh は unitsRoot自体の旧来の日本語トップ名（project-portal
# 直後のセグメント）への逆戻りを検査し、1段下のセグメント名は対象にしない
# （別の検査対象）。
#
# 検出方法: project-portal/ の直後に4つの既知の旧名（図・対応表・基盤・画面）が
# 来る箇所を検出する。完了の判定1の grep（`project-portal/(図|対応表|基盤|画面)`）
# と同じ対象に絞る。project-portal/ 直後の日本語全般（ひらがな・カタカナ・漢字）を
# 汎用的に検出する設計も検討したが、実装時の実測で2種類の誤検知が判明したため
# 見送った。1つは detect_stale_portal_placeholders の自己テスト（build-portal.sh
# の既定 --self-test に含まれるケース49）が、定義に無い任意の置き場を検出できる
# ことを証明するため、恒久的に project-portal/旧構成・project-portal/作業中 という
# 日本語の合成フィクスチャを使う（意図的な任意名であり、置き場の逆戻りではない）。
# もう1つは project-portal/規約/（規約定義の派生先。本指示書が対象とする4キー
# 〈matrixDir・diagramDir・foundationDir・screenViewRoot〉には含まれない、既存の
# 別の置き場）で、汎用検出だと本指示書の対象外まで誤って不合格にしてしまう。
# 4つの既知名に絞ることで、この2種類の誤検知を避けつつ本指示書が対象とする
# 逆戻りを確実に捕捉する。
# ロケール指定は呼び出しのたびに明示する。LC_ALL=C を前置きするコマンドから
# 呼ばれても解決経路の途中で上書きされないようにするためである
# （.claude/rules/always/design-record/implementation-decision/rule.md の
# 「ロケールの使い分け」節・既定3）。
#
# 除外対象（走査から外す。理由は各項目を参照）:
#   1. このスクリプト自身（自己言及。本ファイルのコメント・自己テストの
#      フィクスチャ文字列が誤って自分自身を違反として検出しないようにする）
#
# 一覧の置き場の検査（check-list-path-unified.sh）と異なり、本検査は
# docs/tasks/ 等の除外を持たない。走査対象を generation-engine/・
# delivery-payload/・.claude/skills/ の3つに絞り、docs/ 配下（指示書・
# 作業記録・設計文書）は最初から走査対象に含めていないためである
# （一覧以外の置き場も定義と実態が食い違う問題を直す指示書.md の完了の判定1
# が docs を走査対象から外すと明記している）。
#
# 使い方:
#   check-portal-dir-ascii.sh             project-portal/直下の日本語が0件かを見る
#   check-portal-dir-ascii.sh --self-test このスクリプト自身の判定を確かめる
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TARGET_DIRS=(
  "generation-engine"
  "delivery-payload"
  ".claude/skills"
)

# 4つの既知の旧名（図・対応表・基盤・画面）。完了の判定1の grep と同じ対象。
LEGACY_NAMES='図|対応表|基盤|画面'

# scan_dirs: <root> 配下の TARGET_DIRS を走査し、project-portal/ の直後に
# 4つの既知の旧名が来る行を「ファイル:行番号:内容」の形で標準出力へ書く。
# 除外対象（このスクリプト自身）は含めない。
scan_dirs() {
  local root="$1"
  local self_rel="docs/scripts/check-portal-dir-ascii.sh"
  local d
  for d in "${TARGET_DIRS[@]}"; do
    [ -d "$root/$d" ] || continue
    LC_ALL=en_US.UTF-8 grep -rnE "project-portal/(${LEGACY_NAMES})" "$root/$d" 2>/dev/null | while IFS= read -r line; do
      local file="${line%%:*}"
      local rel="${file#"$root"/}"
      case "$rel" in
        "$self_rel") continue ;;
      esac
      printf '%s\n' "$line"
    done
  done
  return 0
}

run_self_test() {
  local pass=0 fail=0
  local tmp
  # 明示テンプレート付き mktemp。引数なしの mktemp は $TMPDIR を無視し書き込みを
  # 拒む環境で失敗する（.claude/rules/always/verification/indeterminate-result/rule.md）。
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-portal-dir-ascii.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため自己テストを判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' RETURN

  # ケース1: 4つの置き場すべてが英字で揃い、違反が0件 → exit 0
  mkdir -p "$tmp/case_clean/generation-engine/scripts" "$tmp/case_clean/delivery-payload/references" "$tmp/case_clean/.claude/skills/dummy-skill"
  printf '%s\n' 'const p = "project-portal/matrices/権限画面マトリクス/権限画面マトリクス.html";' \
    > "$tmp/case_clean/generation-engine/scripts/good.mjs"
  printf '%s\n' '{"foundationDir": "project-portal/foundation", "diagramDir": "project-portal/diagrams"}' \
    > "$tmp/case_clean/delivery-payload/references/good.json"
  if out="$(_run_scan_over "$tmp/case_clean")" && [ -z "$out" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "[FAIL] ケース1(違反なし): ${out}" >&2
  fi

  # ケース2: project-portal/基盤 への言及が1件 → 検出される
  mkdir -p "$tmp/case_bad1/generation-engine/scripts"
  printf '%s\n' 'const p = "project-portal/基盤/共通設計書.html";' \
    > "$tmp/case_bad1/generation-engine/scripts/bad.mjs"
  if out="$(_run_scan_over "$tmp/case_bad1")" && printf '%s' "$out" | grep -q 'bad.mjs:1:'; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "[FAIL] ケース2(project-portal/基盤の検出): ${out}" >&2
  fi

  # ケース3: project-portal/対応表・図・画面 への言及もそれぞれ検出される
  mkdir -p "$tmp/case_bad2/delivery-payload/references"
  printf '%s\n' '対応表: project-portal/対応表/CRUD図/CRUD図.html' \
    > "$tmp/case_bad2/delivery-payload/references/bad1.md"
  printf '%s\n' '図: project-portal/図/ER図.html' \
    >> "$tmp/case_bad2/delivery-payload/references/bad1.md"
  printf '%s\n' '画面: project-portal/画面/screen-a/シーケンス図.html' \
    >> "$tmp/case_bad2/delivery-payload/references/bad1.md"
  if out="$(_run_scan_over "$tmp/case_bad2")" \
    && printf '%s' "$out" | grep -q '対応表' \
    && printf '%s' "$out" | grep -q '/図/' \
    && printf '%s' "$out" | grep -q '画面'; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "[FAIL] ケース3(対応表・図・画面の検出): ${out}" >&2
  fi

  # ケース4: 一覧配下の日本語サブフォルダ（project-portal/ の直後ではない）は
  # 対象外（project-portal/lists/用語辞書 のように、直後のセグメントは英字のため）
  mkdir -p "$tmp/case_exempt_nested/generation-engine/scripts"
  printf '%s\n' 'const p = "project-portal/lists/用語辞書/用語辞書.html";' \
    > "$tmp/case_exempt_nested/generation-engine/scripts/ok.mjs"
  printf '%s\n' 'const q = "project-portal/matrices/権限機能マトリクス/権限機能マトリクス.html";' \
    >> "$tmp/case_exempt_nested/generation-engine/scripts/ok.mjs"
  if out="$(_run_scan_over "$tmp/case_exempt_nested")" && [ -z "$out" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "[FAIL] ケース4(直後ではない日本語サブフォルダの非検出): ${out}" >&2
  fi

  # ケース5: docs/ 配下は走査対象外（TARGET_DIRSに含まれない）
  mkdir -p "$tmp/case_docs_exempt/docs/tasks"
  printf '%s\n' '旧配置は project-portal/基盤 だった。' \
    > "$tmp/case_docs_exempt/docs/tasks/記録.md"
  if out="$(_run_scan_over "$tmp/case_docs_exempt")" && [ -z "$out" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "[FAIL] ケース5(docs/配下の非走査): ${out}" >&2
  fi

  # ケース6: 走査対象の置き場が1つも無い → [UNKNOWN]・終了コード2
  mkdir -p "$tmp/case_empty"
  if out="$(cd "$tmp/case_empty" && bash "$SCRIPT_DIR/check-portal-dir-ascii.sh" --repo-root "$tmp/case_empty" 2>&1)"; then
    fail=$((fail + 1))
    echo "[FAIL] ケース6(置き場なしでUNKNOWNを返す): exit 0 だった" >&2
  else
    rc=$?
    if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q '^\[UNKNOWN\]'; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
      echo "[FAIL] ケース6(置き場なしでUNKNOWNを返す): rc=${rc} out=${out}" >&2
    fi
  fi

  # ケース7: --self-test 自身が実引数として処理される
  if grep -q -- '--self-test' "$SCRIPT_DIR/check-portal-dir-ascii.sh"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "[FAIL] ケース7(--self-testの実装確認)" >&2
  fi

  # ケース8: このスクリプト自身は自己言及として除外され、violationにならない
  # （本ファイルはコメント・自己テストのフィクスチャ文字列の中に
  # project-portal/基盤 等の文字列を含むため、除外が無いと自身を検出してしまう）
  if out="$(scan_dirs "$REPO_ROOT")" 2>/dev/null; then
    if ! printf '%s' "$out" | grep -q 'check-portal-dir-ascii.sh:'; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
      echo "[FAIL] ケース8(自己言及の除外): ${out}" >&2
    fi
  else
    fail=$((fail + 1))
    echo "[FAIL] ケース8(自己言及の除外): scan_dirs実行時にエラー" >&2
  fi

  echo "self-test: ${pass} PASS, ${fail} FAIL" >&2
  [ "$fail" -eq 0 ]
}

# _run_scan_over: 自己テスト用に、指定した疑似リポジトリ配下を走査した結果
# （違反行の一覧）を返す。
_run_scan_over() {
  local root="$1"
  scan_dirs "$root"
}

main() {
  local repo_root="$REPO_ROOT"
  local i=1
  local args=("$@")
  while [ $i -le $# ]; do
    case "${args[$((i-1))]}" in
      --repo-root)
        i=$((i + 1))
        repo_root="${args[$((i-1))]}"
        ;;
    esac
    i=$((i + 1))
  done

  local missing=0
  local d
  for d in "${TARGET_DIRS[@]}"; do
    [ -d "$repo_root/$d" ] || missing=$((missing + 1))
  done
  if [ "$missing" -eq "${#TARGET_DIRS[@]}" ]; then
    echo "[UNKNOWN] 走査対象の置き場が1つも見つからないため判定できません（参照したルート: ${repo_root}）" >&2
    exit 2
  fi

  local out
  out="$(scan_dirs "$repo_root")"
  if [ -z "$out" ]; then
    echo "[PASS] project-portal/ 直下の日本語フォルダ名への言及は0件"
    exit 0
  fi

  printf '%s\n' "$out"
  local violations
  violations="$(printf '%s\n' "$out" | grep -c .)"
  echo "[FAIL] project-portal/ 直下の日本語フォルダ名への言及が ${violations} 件ある"
  exit 1
}

if [ "${1:-}" = "--self-test" ]; then
  run_self_test
  exit $?
fi

main "$@"
