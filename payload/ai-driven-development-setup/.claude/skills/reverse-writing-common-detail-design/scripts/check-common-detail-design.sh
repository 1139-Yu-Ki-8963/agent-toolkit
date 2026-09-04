#!/usr/bin/env bash
set -u

# check-common-detail-design.sh — 共通処理の詳細設計書の見出し構成と実在を検査する
#
# 目的:
#   共通処理の詳細設計書は、調査と検出条件の定義書の節7「共通方式の場所」で場所が「なし」でない
#   方式ごとに `## §N <方式>` の節を持ち、各節に位置づけの行と6つの`###`小節
#   （クラス設計・メソッド設計・ロジック設計・戻り値と引数・エラー処理・
#   データ定義）を持つ。工程2-7の完了条件（file:lineが無い・各節に位置づけが
#   ある・未記入が無い）を機械で確かめる。
#
# 使い方:
#   check-common-detail-design.sh <対象リポジトリのルート> [--design-root <設計書のルート>] [--map <調査と検出条件の定義書のパス>]
#   check-common-detail-design.sh --self-test
#
# --design-root の既定は対象リポジトリのルート。調査と検出条件の定義書・共通処理の詳細設計書・
# 合格の記録は設計書のルート配下で読み書きする。
#
# 入口:
#   工程2-6（基本設計の完了判定）の共通設計文書の合格の記録が無ければ検査
#   そのものを始めない。合否の確認は reverse-shared の
#   check-acceptance-record.sh（本スクリプトの場所から相対パスで解決する
#   ../../reverse-shared/scripts/check-acceptance-record.sh <対象> --common）
#   に委ね、本スクリプトは判定方法を再実装しない。
#
# 検査キー（内容を要約した意味語。連番禁止）:
#   検査基盤-不在    check-acceptance-record.sh が見つからない（判定不能）
#   合格記録-不在    check-acceptance-record.sh の終了コードが0でない
#   調査と検出条件の定義書-不在        調査と検出条件の定義書（--map）が存在しない
#   文書-不在        共通処理の詳細設計書.md が存在しない
#   節-欠落          場所が「なし」でない方式の「## §N <方式>」見出しが無い
#   位置づけ-欠落    上記見出しの直後に位置づけの行が無い
#   小節-欠落        節の中に6つの`###`小節のいずれかが無い
#   未記入-残存      `<...>` 形式のプレースホルダーが残っている
#   位置-禁止        file:line形式の実装位置の記述がある
#   追記章-禁止      「追記」「補足」「その他」で始まる見出しがある
#
# 終了コード:
#   0 = 全件合格
#   1 = 1件以上不合格
#   2 = 使い方の誤り・検査基盤の不在・調査と検出条件の定義書や文書の不在（判定不能）
#
# 保守責任者: 人手（ユーザー）。10方式の一覧・6小節の名前を変えるときは、
#   ../templates/共通処理の詳細設計書.md と本スクリプトと自己テストを同時に直す。
#
# 廃棄条件: 共通処理の詳細設計書の様式を構造化データに変えた時。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。jqは不使用。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCEPTANCE_RECORD_CHECK="${SCRIPT_DIR}/../../reverse-shared/scripts/check-acceptance-record.sh"

FAIL_COUNT=0
PASS_COUNT=0

fail() {
  echo "[FAIL] $1: $2" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

passck() {
  PASS_COUNT=$((PASS_COUNT + 1))
}

usage_error() {
  echo "使い方: check-common-detail-design.sh <対象リポジトリのルート> [--design-root <設計書のルート>] [--map <調査と検出条件の定義書のパス>]" >&2
  echo "        check-common-detail-design.sh --self-test" >&2
  exit 2
}

REQUIRED_SUBSECTIONS="クラス設計 メソッド設計 ロジック設計 戻り値と引数 エラー処理 データ定義"

extract_map_rows() {
  local map="$1"
  awk '
    /^## 7\. 共通方式の場所/ {flag=1; next}
    /^## / {flag=0}
    flag && /^\|/ {print}
  ' "$map"
}

trim() {
  printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

check_doc() {
  local design_root="$1" map="$2"
  local doc="${design_root%/}/docs/design/common/共通処理の詳細設計書.md"

  if [ ! -f "$map" ]; then
    echo "[FAIL] 調査と検出条件の定義書-不在: ${map} が存在しません" >&2
    return 2
  fi
  if [ ! -f "$doc" ]; then
    echo "[FAIL] 文書-不在: ${doc} が存在しません" >&2
    return 2
  fi

  local rows
  rows="$(extract_map_rows "$map")"

  local line houshiki basho
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      *"方式"*"実装の場所"*) continue ;;
      *"---"*) continue ;;
    esac
    houshiki="$(printf '%s' "$line" | awk -F'|' '{print $2}')"
    basho="$(printf '%s' "$line" | awk -F'|' '{print $3}')"
    houshiki="$(trim "$houshiki")"
    basho="$(trim "$basho")"
    [ -n "$houshiki" ] || continue
    if [ "$basho" = "なし" ]; then
      continue
    fi

    local heading_line
    heading_line="$(grep -nE "^## §[0-9]+[[:space:]]+${houshiki}([[:space:]]|\$)" "$doc" | head -1 | cut -d: -f1)"
    if [ -z "$heading_line" ]; then
      fail "節-欠落" "${doc}: 方式「${houshiki}」の「## §N ${houshiki}」がありません"
      continue
    fi
    passck

    local next_nonblank
    next_nonblank="$(awk -v start="$heading_line" 'NR>start && NF>0 {print; exit}' "$doc")"
    if [[ "$next_nonblank" != "**この節の位置づけ: "* ]]; then
      fail "位置づけ-欠落" "${doc}: 「${houshiki}」の直後に位置づけの行がありません"
    else
      passck
    fi

    local next_h2 span
    next_h2="$(awk -v start="$heading_line" 'NR>start && /^## /{print NR; exit}' "$doc")"
    if [ -n "$next_h2" ]; then
      span="$(awk -v s="$heading_line" -v e="$next_h2" 'NR>s && NR<e' "$doc")"
    else
      span="$(awk -v s="$heading_line" 'NR>s' "$doc")"
    fi

    local sub ok_sub=1
    for sub in $REQUIRED_SUBSECTIONS; do
      if ! printf '%s\n' "$span" | grep -qE "^### ${sub}([[:space:]]|\$)"; then
        fail "小節-欠落" "${doc}: 「${houshiki}」に「### ${sub}」がありません"
        ok_sub=0
      fi
    done
    [ "$ok_sub" -eq 1 ] && passck
  done <<ROWLIST
$rows
ROWLIST

  local placeholder_lines
  placeholder_lines="$(grep -nE '<[^<>]+>' "$doc" || true)"
  if [ -n "$placeholder_lines" ]; then
    fail "未記入-残存" "${doc}: 未記入のプレースホルダーがあります（例: $(printf '%s\n' "$placeholder_lines" | head -1)）"
  else
    passck
  fi

  local pos_lines
  pos_lines="$(grep -nE '[A-Za-z0-9_./-]+\.(ts|js|py|rb|php|java|go|pl|cs|tsx|jsx):[0-9]+' "$doc" || true)"
  if [ -n "$pos_lines" ]; then
    fail "位置-禁止" "${doc}: 実装位置(file:line)の記述があります（例: $(printf '%s\n' "$pos_lines" | head -1)）"
  else
    passck
  fi

  local addendum_lines
  addendum_lines="$(grep -nE '^#{2,3} (追記|補足|その他)' "$doc" || true)"
  if [ -n "$addendum_lines" ]; then
    fail "追記章-禁止" "${doc}: 追記の見出しがあります（例: $(printf '%s\n' "$addendum_lines" | head -1)）"
  else
    passck
  fi

  return 0
}

run_self_test() {
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-common-detail-design-self-test.XXXXXX")" || { echo "一時領域を作成できません" >&2; return 2; }
  trap 'rm -rf "$tmp"' RETURN

  local total=0 fail=0

  # 自分自身を隔離したfixtureへ複製し、依存(check-acceptance-record.sh。
  # reverse-shared が別担当により並行して構築される)のスタブを
  # 隣に置く。実リポジトリの構築状況に左右されずに検査ロジックを確かめる
  # ためである。
  local self_dir own_name
  self_dir="$(cd "$(dirname "$0")" && pwd)"
  own_name="$(basename "$0")"
  local fixture_root="${tmp}/fixture-skills"
  local copy_dir="${fixture_root}/reverse-writing-common-detail-design/scripts"
  local record_dir="${fixture_root}/reverse-shared/scripts"
  mkdir -p "$copy_dir" "$record_dir"
  cp "${self_dir}/${own_name}" "${copy_dir}/${own_name}"
  chmod +x "${copy_dir}/${own_name}"
  local under_test="${copy_dir}/${own_name}"

  write_record_stub() {
    cat > "${record_dir}/check-acceptance-record.sh" <<STUBEOF
#!/usr/bin/env bash
exit $1
STUBEOF
    chmod +x "${record_dir}/check-acceptance-record.sh"
  }

  local target="${tmp}/target"
  mkdir -p "${target}/docs/design/common"

  cat > "${target}/docs/design/common/調査と検出条件の定義書.md" <<'MAPEOF'
# 調査と検出条件の定義書

## 7. 共通方式の場所

| 方式 | 実装の場所 |
|---|---|
| 認証 | src/auth/ |
| 権限 | src/auth/permission.ts |
| エラー | なし |
| ログ | なし |
| データアクセス | なし |
| 設定 | なし |
| 入力検証 | なし |
| メッセージ | なし |
| トランザクション | なし |
| 排他 | なし |

## 8. 用語の候補
MAPEOF

  write_doc_good() {
    cat > "${target}/docs/design/common/共通処理の詳細設計書.md" <<'DOCEOF'
# 共通処理の詳細設計書

## §1 認証

**この節の位置づけ: 現行実装**

### クラス設計
記入済み

### メソッド設計
記入済み

### ロジック設計
記入済み

### 戻り値と引数
記入済み

### エラー処理
記入済み

### データ定義
記入済み

## §2 権限

**この節の位置づけ: 現行実装**

### クラス設計
記入済み

### メソッド設計
記入済み

### ロジック設計
記入済み

### 戻り値と引数
記入済み

### エラー処理
記入済み

### データ定義
記入済み

## 要確認事項一覧

なし

## 関連資料

なし
DOCEOF
  }

  assert_exit() {
    local desc="$1" expected="$2"; shift 2
    total=$((total + 1))
    "$@" > "${tmp}/out.log" 2>"${tmp}/err.log"
    local actual=$?
    if [ "$actual" = "$expected" ]; then
      echo "PASS: ${desc}"
    else
      echo "FAIL: ${desc}（期待終了コード ${expected} / 実際 ${actual}）"
      sed -n '1,20p' "${tmp}/err.log"
      fail=$((fail + 1))
    fi
  }

  assert_contains() {
    local desc="$1" key="$2"
    total=$((total + 1))
    if grep -qF "[FAIL] ${key}" "${tmp}/err.log"; then
      echo "PASS: ${desc}"
    else
      echo "FAIL: ${desc}（${key} の不合格が出ていません）"
      sed -n '1,20p' "${tmp}/err.log"
      fail=$((fail + 1))
    fi
  }

  # 合格
  write_doc_good
  write_record_stub 0
  assert_exit "合格" 0 bash "$under_test" "$target"

  # 判定不能-検査基盤不在（スタブそのものを消す）
  rm -f "${record_dir}/check-acceptance-record.sh"
  assert_exit "判定不能-検査基盤不在" 2 bash "$under_test" "$target"

  # 不合格-合格記録なし
  write_record_stub 1
  assert_exit "不合格-合格記録なし" 1 bash "$under_test" "$target"
  assert_contains "不合格-合格記録なし: 合格記録-不在が出る" "合格記録-不在"
  write_record_stub 0

  # 不合格（複合）: 節の欠落・位置づけの欠落・小節の欠落・未記入・位置・追記章
  cat > "${target}/docs/design/common/共通処理の詳細設計書.md" <<'BADEOF'
# 共通処理の詳細設計書

## §1 認証

位置づけの行がありません

### クラス設計
記入済み

### メソッド設計
記入済み

### ロジック設計
記入済み

### 戻り値と引数
記入済み

### エラー処理
記入済み

未記入: <ここを埋める>

src/app/auth.ts:42 を参照する。

## 追記

記入済み

## 要確認事項一覧

なし

## 関連資料

なし
BADEOF
  assert_exit "不合格-複合" 1 bash "$under_test" "$target"
  assert_contains "不合格-複合: 節-欠落（権限）が出る" "節-欠落"
  assert_contains "不合格-複合: 位置づけ-欠落が出る" "位置づけ-欠落"
  assert_contains "不合格-複合: 小節-欠落（データ定義）が出る" "小節-欠落"
  assert_contains "不合格-複合: 未記入-残存が出る" "未記入-残存"
  assert_contains "不合格-複合: 位置-禁止が出る" "位置-禁止"
  assert_contains "不合格-複合: 追記章-禁止が出る" "追記章-禁止"

  # 判定不能-文書不在
  rm -f "${target}/docs/design/common/共通処理の詳細設計書.md"
  assert_exit "判定不能-文書不在" 2 bash "$under_test" "$target"
  write_doc_good

  # 判定不能-調査と検出条件の定義書不在
  local target2="${tmp}/target-nomap"
  mkdir -p "${target2}/docs/design/common"
  cp "${target}/docs/design/common/共通処理の詳細設計書.md" "${target2}/docs/design/common/"
  assert_exit "判定不能-調査と検出条件の定義書不在" 2 bash "$under_test" "$target2"

  # --- 設計書ルート分離-対象に書かない ---
  local dc3="${tmp}/target-code-only" design4="${tmp}/design4"
  mkdir -p "$dc3" "$design4/docs/design/common"
  cp "${target}/docs/design/common/調査と検出条件の定義書.md" "$design4/docs/design/common/"
  cp "${target}/docs/design/common/共通処理の詳細設計書.md" "$design4/docs/design/common/"
  write_record_stub 0
  assert_exit "設計書ルート分離-合格" 0 bash "$under_test" "$dc3" --design-root "$design4"
  total=$((total + 1))
  if [ ! -e "$dc3/docs" ]; then
    echo "PASS: 設計書ルート分離-対象に書かない"
  else
    echo "FAIL: 設計書ルート分離-対象に書かない（対象側にdocsが作られています）"
    fail=$((fail + 1))
  fi

  # 判定不能-使い方の誤り
  assert_exit "判定不能-使い方の誤り" 2 bash "$under_test"

  echo "実行 ${total} 件 / 失敗 ${fail} 件"
  if [ "$fail" -gt 0 ]; then
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------

if [ "${1:-}" = "--self-test" ]; then
  run_self_test
  exit $?
fi

if [ ! -f "$ACCEPTANCE_RECORD_CHECK" ]; then
  echo "[FAIL] 検査基盤-不在: ${ACCEPTANCE_RECORD_CHECK} が見つかりません" >&2
  exit 2
fi

if [ $# -lt 1 ]; then
  usage_error
fi

TARGET="$1"; shift
DESIGN_ROOT="$TARGET"
MAP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --map) MAP="${2:-}"; shift 2 ;;
    --design-root) DESIGN_ROOT="${2:-}"; shift 2 ;;
    *) usage_error ;;
  esac
done
[ -n "$MAP" ] || MAP="${DESIGN_ROOT%/}/docs/design/common/調査と検出条件の定義書.md"

bash "$ACCEPTANCE_RECORD_CHECK" "$TARGET" --common --design-root "$DESIGN_ROOT"
vrc=$?
if [ "$vrc" -ne 0 ]; then
  echo "[FAIL] 合格記録-不在: 共通設計文書の合格の記録がありません（check-acceptance-record.sh 終了コード ${vrc}）" >&2
  exit 1
fi

check_doc "$DESIGN_ROOT" "$MAP"
crc=$?
if [ "$crc" -eq 2 ]; then
  exit 2
fi

echo "合格 ${PASS_COUNT} 件 / 不合格 ${FAIL_COUNT} 件"
if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
