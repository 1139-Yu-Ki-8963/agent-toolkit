#!/usr/bin/env bash
set -u

# check-foundation-guides.sh — 技術スタック・環境構築手順書の構造と実在を検査する
#
# 目的:
#   工程2-3（基盤文書）の完了条件を機械で確かめる。技術スタックの各行が
#   道標の節1「依存の定義」の場所に実在するかを確かめ、環境構築手順書の
#   節構成・未記入・実装位置(file:line)・秘密の値らしき記述の混入を検出する。
#   文面の良し悪しは検査しない。
#
# 使い方:
#   check-foundation-guides.sh <対象リポジトリのルート> [--map <道標の相対パス>]
#   check-foundation-guides.sh --self-test
#
# --map の既定は docs/design/common/道標.md。技術スタック・環境構築手順書の
# パスは docs/design/common/技術スタック.md・docs/design/common/環境構築手順書.md
# に固定する（工程2-3の出力先であり、変更する理由が無いため引数を持たない）。
#
# 検査キー（内容を要約した意味語。連番禁止）:
#   依存-不在      技術スタックの行の「名前」が、道標の節1「依存の定義」の
#                  場所のファイルのいずれにも文字列として現れない
#   節-欠落        環境構築手順書の見出しが規定の9個・順序と一致しない
#                  （§1〜§7 ＋ 要確認事項一覧 ＋ 関連資料）
#   位置づけ-欠落  環境構築手順書の§1〜§7の直後に
#                  「**この節の位置づけ: 現行実装**」の行が無い
#   未記入-残存    環境構築手順書に「<...>」形式のプレースホルダーが残っている
#   位置-禁止      環境構築手順書にfile:line形式の実装位置の記述がある
#   秘密-混入      環境構築手順書に「=」の右へ20字以上の英数字が続く記述がある
#                  （環境の値は書かず確認事項へ登録する規約への違反）
#
# 終了コード:
#   0 = 全件合格
#   1 = 1件以上不合格（[FAIL]行を標準エラーへ列挙）
#   2 = 使い方の誤り・対象/道標/技術スタック/環境構築手順書の不在（判定不能）
#
# 保守責任者: 人手（ユーザー）。様式（templates/技術スタック.md・
#   templates/環境構築手順書.md）の節構成を変えるときは、本スクリプトと
#   自己テストを同時に直す。
#
# 廃棄条件: 基盤文書の機械で読む部分を構造化データとして別に出す形に変えた時。
#
# macOS bash 3.2 互換（連想配列は不使用）。

FAIL_COUNT=0
PASS_COUNT=0

fail() {
  echo "[FAIL] $1: $2" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

passck() {
  PASS_COUNT=$((PASS_COUNT + 1))
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

col() {
  local line="$1" n="$2"
  local IFS='|'
  local -a arr
  read -ra arr <<< "$line"
  printf '%s' "$(trim "${arr[$n]:-}")"
}

table_data_rows() {
  local text="$1"
  local rows
  rows="$(grep -E '^\|.*\|[[:space:]]*$' <<< "$text" || true)"
  rows="$(grep -vE '^\|[-:|[:space:]]+$' <<< "$rows" || true)"
  tail -n +2 <<< "$rows" 2>/dev/null | grep -v '^$' || true
}

first_table_text() {
  awk '
    /^\|/ { intable=1; print; next }
    intable && !/^\|/ { exit }
  ' <<< "$1"
}

section_text() {
  # section_text <content> <開始見出しの完全一致文字列>
  # 次の「## 」見出し行、またはEOFまでを返す
  local content="$1" start="$2"
  awk -v start="$start" '
    BEGIN{flag=0}
    index($0,start)==1 {flag=1; next}
    flag && /^## / {flag=0}
    flag {print}
  ' <<< "$content"
}

path_list_missing_or_files() {
  # path_list_files <target> <;区切りのパス一覧>
  # 対象配下に実在するパスだけを改行区切りで返す
  local target="$1" list="$2"
  local -a parts
  local old_ifs="$IFS"
  IFS=';' read -ra parts <<< "$list"
  IFS="$old_ifs"
  local p
  for p in "${parts[@]}"; do
    p="$(trim "$p")"
    [ -z "$p" ] && continue
    if [ -e "${target}/${p}" ]; then
      printf '%s\n' "${target}/${p}"
    fi
  done
}

usage_error() {
  echo "使い方: check-foundation-guides.sh <対象リポジトリのルート> [--map <道標の相対パス>]" >&2
  echo "        check-foundation-guides.sh --self-test" >&2
  exit 2
}

check_foundation_guides() {
  local target="$1" map_rel="$2"
  local map_file="${target%/}/${map_rel}"
  local tech_file="${target%/}/docs/design/common/技術スタック.md"
  local env_file="${target%/}/docs/design/common/環境構築手順書.md"

  if [ ! -d "$target" ]; then
    echo "対象リポジトリが見つかりません: ${target}" >&2
    return 2
  fi
  if [ ! -f "$map_file" ]; then
    echo "道標が見つかりません: ${map_file}" >&2
    return 2
  fi
  if [ ! -f "$tech_file" ]; then
    echo "技術スタックが見つかりません: ${tech_file}" >&2
    return 2
  fi
  if [ ! -f "$env_file" ]; then
    echo "環境構築手順書が見つかりません: ${env_file}" >&2
    return 2
  fi

  # 道標の節1「依存の定義」の場所を読む
  local map_content sec1 rows1 dep_row dep_loc
  map_content="$(cat "$map_file")"
  sec1="$(section_text "$map_content" "## 1. 調査")"
  rows1="$(table_data_rows "$sec1")"
  dep_row=""
  while IFS= read -r r; do
    [ -z "$r" ] && continue
    if [ "$(col "$r" 1)" = "依存の定義" ]; then dep_row="$r"; break; fi
  done <<< "$rows1"
  dep_loc="$(col "$dep_row" 3)"

  local dep_files=""
  if [ -n "$dep_loc" ] && [ "$dep_loc" != "なし" ]; then
    dep_files="$(path_list_missing_or_files "$target" "$dep_loc")"
  fi

  # 依存-不在
  local tech_content tech_table tech_rows ok_dep=1
  tech_content="$(cat "$tech_file")"
  tech_table="$(first_table_text "$tech_content")"
  tech_rows="$(table_data_rows "$tech_table")"
  while IFS= read -r r; do
    [ -z "$r" ] && continue
    local name
    name="$(col "$r" 2)"
    [ -z "$name" ] && continue
    [ "${name:0:1}" = "<" ] && continue
    local found=0
    if [ -n "$dep_files" ]; then
      local df
      while IFS= read -r df; do
        [ -z "$df" ] && continue
        if grep -qF "$name" "$df" 2>/dev/null; then
          found=1
          break
        fi
      done <<< "$dep_files"
    fi
    if [ "$found" -ne 1 ]; then
      fail "依存-不在" "$name"
      ok_dep=0
    fi
  done <<< "$tech_rows"
  [ "$ok_dep" -eq 1 ] && passck

  # 節-欠落 (環境構築手順書)
  local env_content
  env_content="$(cat "$env_file")"
  local -a expected_headings=(
    "## §1 前提"
    "## §2 取得"
    "## §3 依存の導入"
    "## §4 環境の値"
    "## §5 起動"
    "## §6 テスト"
    "## §7 よくある失敗"
    "## 要確認事項一覧"
    "## 関連資料"
  )
  local actual expected_joined actual_joined
  actual="$(grep -E '^## ' "$env_file" || true)"
  expected_joined="$(printf '%s\n' "${expected_headings[@]}")"
  actual_joined="$actual"
  if [ "$expected_joined" = "$actual_joined" ]; then
    passck
  else
    fail "節-欠落" "見出しが規定の9個・順序と一致しません（実際: $(printf '%s' "$actual_joined" | tr '\n' '/')）"
  fi

  # 位置づけ-欠落 (§1〜§7)
  local ok_place=1
  local h
  for h in "## §1 前提" "## §2 取得" "## §3 依存の導入" "## §4 環境の値" "## §5 起動" "## §6 テスト" "## §7 よくある失敗"; do
    local heading_line_no
    heading_line_no="$(grep -n -F "$h" "$env_file" | head -1 | cut -d: -f1)"
    if [ -z "$heading_line_no" ]; then
      continue
    fi
    local next_nonblank
    next_nonblank="$(awk -v start="$heading_line_no" 'NR>start && NF>0 {print; exit}' "$env_file")"
    if [ "$next_nonblank" != "**この節の位置づけ: 現行実装**" ]; then
      fail "位置づけ-欠落" "「${h}」の直後に位置づけの行がありません"
      ok_place=0
    fi
  done
  [ "$ok_place" -eq 1 ] && passck

  # 未記入-残存
  local placeholder_lines
  placeholder_lines="$(grep -nE '<[^<>]+>' "$env_file" || true)"
  if [ -n "$placeholder_lines" ]; then
    local cnt
    cnt="$(printf '%s\n' "$placeholder_lines" | grep -c '.')"
    fail "未記入-残存" "未記入のプレースホルダーが${cnt}件あります（例: $(printf '%s\n' "$placeholder_lines" | head -1)）"
  else
    passck
  fi

  # 位置-禁止
  local pos_lines
  pos_lines="$(grep -nE '[A-Za-z0-9_./-]+\.(ts|js|py|rb|php|java|go|pl|cs|tsx|jsx):[0-9]+' "$env_file" || true)"
  if [ -n "$pos_lines" ]; then
    fail "位置-禁止" "実装位置(file:line)の記述があります（例: $(printf '%s\n' "$pos_lines" | head -1)）"
  else
    passck
  fi

  # 秘密-混入
  local secret_lines
  secret_lines="$(grep -nE '=[[:space:]]*"?'"'"'?[A-Za-z0-9_+/-]{20,}' "$env_file" || true)"
  if [ -n "$secret_lines" ]; then
    local secret_line_nos
    secret_line_nos="$(printf '%s\n' "$secret_lines" | cut -d: -f1 | tr '\n' ',' | sed 's/,$//')"
    fail "秘密-混入" "秘密の値らしき記述があります（行: ${secret_line_nos}）"
  else
    passck
  fi

  return 0
}

run_self_test() {
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-foundation-guides-self-test.XXXXXX")" || { echo "一時領域を作成できません" >&2; return 2; }
  trap 'rm -rf "$tmp"' RETURN

  local self_fail=0
  local self_total=0

  build_target() {
    local root="$1"
    mkdir -p "${root}/docs/design/common"
    echo '{"dependencies": {"react": "18.0.0", "typescript": "5.0.0"}}' > "${root}/package.json"
    cat > "${root}/docs/design/common/道標.md" << 'MAPEOF6'
# 道標

## 1. 調査

| 項目 | 値 | 場所 |
|---|---|---|
| 依存の定義 | package.json | package.json |
MAPEOF6
    cat > "${root}/docs/design/common/技術スタック.md" << 'TECHEOF'
# 技術スタック

| 区分 | 名前 | 版 | 用途 | 定義の場所 |
|---|---|---|---|---|
| 言語 | typescript | 5 | 実装言語 | package.json |
| フレームワーク | react | 18 | UI | package.json |

## 要確認事項一覧

| キー | 確認事項 | 確認先 |
|---|---|---|
| 版-固定方針 | バージョン固定の方針 | 開発チーム |

## 関連資料

- `docs/design/common/道標.md` — 道標
TECHEOF
    cat > "${root}/docs/design/common/環境構築手順書.md" << 'ENVEOF'
# 環境構築手順書

## §1 前提

**この節の位置づけ: 現行実装**

Node 20を前提とする。

## §2 取得

**この節の位置づけ: 現行実装**

git cloneで取得する。

## §3 依存の導入

**この節の位置づけ: 現行実装**

npm installを実行する。

## §4 環境の値

**この節の位置づけ: 現行実装**

環境変数の一覧は確認事項へ登録する。

## §5 起動

**この節の位置づけ: 現行実装**

npm run devを実行する。

## §6 テスト

**この節の位置づけ: 現行実装**

npm testを実行する。

## §7 よくある失敗

**この節の位置づけ: 現行実装**

依存の導入漏れに注意する。

## 要確認事項一覧

| キー | 確認事項 | 確認先 |
|---|---|---|
| 接続先-値 | 接続先の値 | 開発チーム |

## 関連資料

- `docs/design/common/道標.md` — 道標
- `docs/design/common/基盤設計書.md` — 基盤設計書
ENVEOF
  }

  assert_exit() {
    local desc="$1" expected="$2"; shift 2
    self_total=$((self_total + 1))
    "$@" > "${tmp}/out.log" 2>"${tmp}/err.log"
    local actual=$?
    if [ "$actual" = "$expected" ]; then
      echo "PASS: ${desc}"
    else
      echo "FAIL: ${desc} (期待終了コード ${expected} / 実際 ${actual})"
      sed -n '1,20p' "${tmp}/err.log"
      self_fail=$((self_fail + 1))
    fi
  }

  assert_contains() {
    local desc="$1" key="$2"
    self_total=$((self_total + 1))
    if grep -qF "[FAIL] ${key}" "${tmp}/err.log"; then
      echo "PASS: ${desc}"
    else
      echo "FAIL: ${desc} （${key} の不合格が出ていません）"
      sed -n '1,20p' "${tmp}/err.log"
      self_fail=$((self_fail + 1))
    fi
  }

  # 合格-完成形
  local root_ok="${tmp}/target-ok"
  build_target "$root_ok"
  assert_exit "合格-完成形" 0 bash "$0" "$root_ok"

  # 不合格-依存不在
  local root_dep="${tmp}/target-dep"
  build_target "$root_dep"
  sed -i.bak 's/| フレームワーク | react |/| フレームワーク | vue |/' "${root_dep}/docs/design/common/技術スタック.md"
  assert_exit "不合格-依存不在" 1 bash "$0" "$root_dep"
  assert_contains "不合格-依存不在: 依存-不在が出る" "依存-不在"

  # 不合格-節の欠落
  local root_sec="${tmp}/target-sec"
  build_target "$root_sec"
  awk '/^## §7 よくある失敗$/{skip=1} !skip{print}' "${root_sec}/docs/design/common/環境構築手順書.md" > "${root_sec}/docs/design/common/環境構築手順書.md.tmp"
  mv "${root_sec}/docs/design/common/環境構築手順書.md.tmp" "${root_sec}/docs/design/common/環境構築手順書.md"
  assert_exit "不合格-節の欠落" 1 bash "$0" "$root_sec"
  assert_contains "不合格-節の欠落: 節-欠落が出る" "節-欠落"

  # 不合格-位置づけ欠落
  local root_place="${tmp}/target-place"
  build_target "$root_place"
  perl -i -pe 'BEGIN{$done=0} if (!$done && /^\*\*この節の位置づけ: 現行実装\*\*$/) { $_ = "位置づけの行を書き忘れた\n"; $done=1 }' "${root_place}/docs/design/common/環境構築手順書.md"
  assert_exit "不合格-位置づけ欠落" 1 bash "$0" "$root_place"
  assert_contains "不合格-位置づけ欠落: 位置づけ-欠落が出る" "位置づけ-欠落"

  # 不合格-未記入残存
  local root_blank="${tmp}/target-blank"
  build_target "$root_blank"
  printf '\n<書きかけ>\n' >> "${root_blank}/docs/design/common/環境構築手順書.md"
  assert_exit "不合格-未記入残存" 1 bash "$0" "$root_blank"
  assert_contains "不合格-未記入残存: 未記入-残存が出る" "未記入-残存"

  # 不合格-位置禁止
  local root_pos="${tmp}/target-pos"
  build_target "$root_pos"
  printf '\nsrc/app.ts:120を参照する。\n' >> "${root_pos}/docs/design/common/環境構築手順書.md"
  assert_exit "不合格-位置禁止" 1 bash "$0" "$root_pos"
  assert_contains "不合格-位置禁止: 位置-禁止が出る" "位置-禁止"

  # 不合格-秘密混入
  local root_secret="${tmp}/target-secret"
  build_target "$root_secret"
  printf '\nAPI_KEY=abcdefghij1234567890\n' >> "${root_secret}/docs/design/common/環境構築手順書.md"
  assert_exit "不合格-秘密混入" 1 bash "$0" "$root_secret"
  assert_contains "不合格-秘密混入: 秘密-混入が出る" "秘密-混入"

  # 判定不能-道標不在
  local root_no_map="${tmp}/target-no-map"
  build_target "$root_no_map"
  rm -f "${root_no_map}/docs/design/common/道標.md"
  assert_exit "判定不能-道標不在" 2 bash "$0" "$root_no_map"

  # 使い方-引数不足
  assert_exit "使い方-引数不足" 2 bash "$0"

  echo "実行 ${self_total} 件 / 失敗 ${self_fail} 件"
  if [ "$self_fail" -gt 0 ]; then
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

if [ $# -lt 1 ]; then
  usage_error
fi

TARGET="$1"
shift
MAP_REL="docs/design/common/道標.md"

while [ $# -gt 0 ]; do
  case "$1" in
    --map)
      MAP_REL="${2:-}"
      shift 2
      ;;
    *)
      echo "余分な引数です: $1" >&2
      exit 2
      ;;
  esac
done

check_foundation_guides "$TARGET" "$MAP_REL"
rc=$?
if [ "$rc" -eq 2 ]; then
  exit 2
fi

echo "合格 ${PASS_COUNT} 件 / 不合格 ${FAIL_COUNT} 件"
if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
