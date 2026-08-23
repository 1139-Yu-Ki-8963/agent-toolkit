#!/usr/bin/env bash
# check-reproducible.sh — 再現の判定（2回の生成物ディレクトリを内容比較する）
#
# 目的:
#   同一の入力から2回生成した成果物ディレクトリを比較し、内容が再現しているかを判定する。
#   両ディレクトリ配下の全ファイルについて相対パスとハッシュを取り、一致・相違・片側のみを
#   判定する。往復検証（原本コードとの突合）とは別に、生成そのものの決定性を確認する用途。
#
# Usage:
#   check-reproducible.sh --first <1回目の生成物ディレクトリ> --second <2回目の生成物ディレクトリ> \
#     [--exclude <glob>]... [--ignore-timestamps]
#   check-reproducible.sh --self-test
#
# 引数:
#   --first <dir>      1回目の生成物ディレクトリ（必須。--self-test 時は不要）
#   --second <dir>      2回目の生成物ディレクトリ（必須。--self-test 時は不要）
#   --exclude <glob>    比較から除外する相対パスの glob パターン（複数指定可。既定は除外なし）
#   --ignore-timestamps 生成時刻らしき文字列（ISO 8601 の日時・generatedAt の値）を取り除いた上で
#                        比較する。取り除いた結果が一致すれば SAME-EXCEPT-TIME として区別する
#                        （既定では無効。既定の挙動は変わらず、時刻の差も相違として数える）
#   --self-test         自己テストを実行して終了する
#
# 出力:
#   [SAME|DIFF|ONLY-FIRST|ONLY-SECOND] <相対パス> の行を全対象ぶん出力し、末尾に
#   対象 <T> 件 / 一致 <S> 件 / 相違 <D> 件 / 片側のみ <O> 件 のサマリ行を出す。
#   --ignore-timestamps 指定時は [SAME-EXCEPT-TIME] <相対パス> の行が追加で出力され、
#   サマリ行にも 時刻を除き一致 <ST> 件 が挿入される。
#
# 終了コード: 相違または片側のみが1件でもあれば1、全件一致なら0（SAME-EXCEPT-TIMEは不合格にしない）。
# 比較対象が0件、同じ生成物を二度指定した場合は [UNKNOWN]・2。引数不備は2。
#
# 保守責任者: 人手（ユーザー）。macOS bash 3.2 互換（連想配列は使わない。
# 空配列を "${arr[@]}" で展開する箇所は set -u 下の未定義変数エラーを避けるため
# "${arr[@]+"${arr[@]}"}" のイディオムを使う）。
set -uo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"

EXCLUDES=()
IGNORE_TIMESTAMPS=0

# ---- ハッシュ・除外判定 -------------------------------------------------

_checkrepro_hash() {
  local f="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$f" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" | awk '{print $1}'
  else
    md5 -q "$f" 2>/dev/null || md5sum "$f" | awk '{print $1}'
  fi
}

# 生成時刻らしき文字列（ISO 8601 の日時・generatedAt の値）を <TIMESTAMP> に置き換えて標準出力へ書く
# なぜ sed ではなく perl を使うか: この正規表現は \d（数字クラス）・(?:...)（非捕捉グループ）・
# ? の量指定子を組み合わせて使う。BSD sed（macOS標準）の正規表現エンジンはこれらのPCRE
# 記法を素直な形（sed -E への書き換え）では表現できない。perlは事前インストール済みの
# 標準コマンドとして扱える（macOS・多くのLinux配布の既定に含まれる）ため、正規表現の
# 表現力を優先してperlを選んでいる。
# 環境依存: 依存する。perlが存在しない環境（最小構成のコンテナ等）では動かない。
# 過去に消えて再発した経緯: 記録なし。
_checkrepro_strip_timestamps() {
  local f="$1"
  perl -pe '
    s/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?/<TIMESTAMP>/g;
    s/("?generatedAt"?\s*[:=]\s*)"[^"]*"/$1"<TIMESTAMP>"/g;
  ' "$f"
}

# 時刻を取り除いた内容のハッシュを返す（--ignore-timestamps 用）
_checkrepro_hash_stripped() {
  local f="$1"
  if command -v shasum >/dev/null 2>&1; then
    _checkrepro_strip_timestamps "$f" | shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    _checkrepro_strip_timestamps "$f" | sha256sum | awk '{print $1}'
  else
    _checkrepro_strip_timestamps "$f" | (md5 -q 2>/dev/null || md5sum | awk '{print $1}')
  fi
}

# 相対パスが EXCLUDES の glob 群のいずれかに一致するか
_checkrepro_is_excluded() {
  local relpath="$1"
  local pattern
  for pattern in "${EXCLUDES[@]+"${EXCLUDES[@]}"}"; do
    [ -z "$pattern" ] && continue
    case "$relpath" in
      $pattern) return 0 ;;
    esac
  done
  return 1
}

# ディレクトリの別名（symlink、macOS の firmlink 等）を同一生成物として検出する。
# まず pwd -P で symlink を解決し、それでも表記が異なる場合は device/inode を比べる。
_checkrepro_dir_identity() {
  local dir="$1"
  stat -f '%d:%i' "$dir" 2>/dev/null || stat -c '%d:%i' "$dir" 2>/dev/null
}

_checkrepro_same_directory() {
  local first="$1" second="$2" first_physical second_physical first_id second_id
  first_physical="$(cd "$first" && pwd -P)" || return 1
  second_physical="$(cd "$second" && pwd -P)" || return 1
  [ "$first_physical" = "$second_physical" ] && return 0
  first_id="$(_checkrepro_dir_identity "$first")"
  second_id="$(_checkrepro_dir_identity "$second")"
  [ -n "$first_id" ] && [ "$first_id" = "$second_id" ]
}

# ディレクトリ配下の全ファイルの相対パス一覧をソートして返す（改行区切り）。除外glob適用。
_checkrepro_list_files() {
  local dir="$1"
  local relpath
  ( cd "$dir" && find . -type f | sed 's#^\./##' | sort ) | while IFS= read -r relpath; do
    _checkrepro_is_excluded "$relpath" && continue
    printf '%s\n' "$relpath"
  done
}

# ---- 比較本体 -------------------------------------------------------------

checkrepro_compare() {
  local first="$1" second="$2"
  local tmp_first tmp_second tmp_union
  tmp_first="$(mktemp "${TMPDIR:-/tmp}/checkrepro-first.XXXXXX" 2>/dev/null)" || tmp_first=""
  if [ -z "$tmp_first" ] || [ ! -f "$tmp_first" ]; then
    echo "[UNKNOWN] 比較一覧の一時ファイルを作成できないため再現性を判定できません 操作: mktemp / 想定原因: 一時ディレクトリが存在しない、または書き込み権限がありません"
    return 2
  fi
  tmp_second="$(mktemp "${TMPDIR:-/tmp}/checkrepro-second.XXXXXX" 2>/dev/null)" || tmp_second=""
  if [ -z "$tmp_second" ] || [ ! -f "$tmp_second" ]; then
    rm -f "$tmp_first"
    echo "[UNKNOWN] 比較一覧の一時ファイルを作成できないため再現性を判定できません 操作: mktemp / 想定原因: 一時ディレクトリが存在しない、または書き込み権限がありません"
    return 2
  fi
  tmp_union="$(mktemp "${TMPDIR:-/tmp}/checkrepro-union.XXXXXX" 2>/dev/null)" || tmp_union=""
  if [ -z "$tmp_union" ] || [ ! -f "$tmp_union" ]; then
    rm -f "$tmp_first" "$tmp_second"
    echo "[UNKNOWN] 比較一覧の一時ファイルを作成できないため再現性を判定できません 操作: mktemp / 想定原因: 一時ディレクトリが存在しない、または書き込み権限がありません"
    return 2
  fi

  _checkrepro_list_files "$first" > "$tmp_first"
  _checkrepro_list_files "$second" > "$tmp_second"
  cat "$tmp_first" "$tmp_second" | sort -u > "$tmp_union"

  local total=0 same=0 same_time=0 diff=0 only=0
  local relpath in_first in_second h1 h2 hs1 hs2

  while IFS= read -r relpath; do
    [ -z "$relpath" ] && continue
    total=$((total+1))
    in_first=0
    in_second=0
    grep -Fxq "$relpath" "$tmp_first" && in_first=1
    grep -Fxq "$relpath" "$tmp_second" && in_second=1
    if [ "$in_first" -eq 1 ] && [ "$in_second" -eq 1 ]; then
      h1="$(_checkrepro_hash "${first}/${relpath}")"
      h2="$(_checkrepro_hash "${second}/${relpath}")"
      if [ "$h1" = "$h2" ]; then
        echo "[SAME] ${relpath}"
        same=$((same+1))
      elif [ "$IGNORE_TIMESTAMPS" -eq 1 ]; then
        hs1="$(_checkrepro_hash_stripped "${first}/${relpath}")"
        hs2="$(_checkrepro_hash_stripped "${second}/${relpath}")"
        if [ "$hs1" = "$hs2" ]; then
          echo "[SAME-EXCEPT-TIME] ${relpath}"
          same_time=$((same_time+1))
        else
          echo "[DIFF] ${relpath}"
          diff=$((diff+1))
        fi
      else
        echo "[DIFF] ${relpath}"
        diff=$((diff+1))
      fi
    elif [ "$in_first" -eq 1 ]; then
      echo "[ONLY-FIRST] ${relpath}"
      only=$((only+1))
    else
      echo "[ONLY-SECOND] ${relpath}"
      only=$((only+1))
    fi
  done < "$tmp_union"

  rm -f "$tmp_first" "$tmp_second" "$tmp_union"

  if [ "$total" -eq 0 ]; then
    echo "[UNKNOWN] 比較対象を列挙できないため再現性を判定できません（find が両方の生成物から比較対象ファイルを1件も見つけませんでした。生成が未実行、または出力先の指定誤りが原因である可能性があります）"
    return 2
  fi

  if [ "$IGNORE_TIMESTAMPS" -eq 1 ]; then
    echo "対象 ${total} 件 / 一致 ${same} 件 / 時刻を除き一致 ${same_time} 件 / 相違 ${diff} 件 / 片側のみ ${only} 件"
  else
    echo "対象 ${total} 件 / 一致 ${same} 件 / 相違 ${diff} 件 / 片側のみ ${only} 件"
  fi

  if [ "$diff" -gt 0 ] || [ "$only" -gt 0 ]; then
    return 1
  fi
  return 0
}

# ---- self-test ---------------------------------------------------------

_checkrepro_self_test() {
  local run=0 ok=0 ng=0

  _case_pass() { run=$((run+1)); ok=$((ok+1)); echo "[PASS] $1 — $2"; }
  _case_fail() { run=$((run+1)); ng=$((ng+1)); echo "[FAIL] $1 — $2" >&2; }

  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-reproducible-selftest.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT

  mkdir -p "$tmp/a/sub" "$tmp/b/sub"
  echo "hello" > "$tmp/a/file1.txt"
  echo "hello" > "$tmp/b/file1.txt"
  echo "nested" > "$tmp/a/sub/file2.txt"
  echo "nested" > "$tmp/b/sub/file2.txt"

  local out rc

  # 比較-一致検出
  EXCLUDES=()
  out="$(checkrepro_compare "$tmp/a" "$tmp/b")"
  rc=$?
  if [ "$rc" -eq 0 ] && echo "$out" | grep -q '一致 2 件' \
    && ! echo "$out" | grep -qE '^\[DIFF\]|^\[ONLY'; then
    _case_pass "比較-一致検出" "同一内容の2ディレクトリが全件一致になった"
  else
    _case_fail "比較-一致検出" "期待通りにならなかった: ${out}"
  fi

  # 比較-入れ子
  if echo "$out" | grep -q '^\[SAME\] sub/file2.txt$'; then
    _case_pass "比較-入れ子" "サブディレクトリ配下のファイルも比較対象になった"
  else
    _case_fail "比較-入れ子" "サブディレクトリ配下が検出されなかった: ${out}"
  fi

  # 比較-相違検出
  echo "changed" > "$tmp/b/file1.txt"
  out="$(checkrepro_compare "$tmp/a" "$tmp/b")"
  if echo "$out" | grep -q '^\[DIFF\] file1.txt$'; then
    _case_pass "比較-相違検出" "内容を変えたファイルを相違として検出した"
  else
    _case_fail "比較-相違検出" "相違を検出できなかった: ${out}"
  fi
  echo "hello" > "$tmp/b/file1.txt"

  # 比較-片側のみ
  echo "only-in-a" > "$tmp/a/onlya.txt"
  out="$(checkrepro_compare "$tmp/a" "$tmp/b")"
  if echo "$out" | grep -q '^\[ONLY-FIRST\] onlya.txt$'; then
    _case_pass "比較-片側のみ" "片方にしか無いファイルを片側のみとして検出した"
  else
    _case_fail "比較-片側のみ" "片側のみを検出できなかった: ${out}"
  fi

  # 除外-glob
  EXCLUDES=("onlya.txt")
  out="$(checkrepro_compare "$tmp/a" "$tmp/b")"
  if ! echo "$out" | grep -q 'onlya.txt'; then
    _case_pass "除外-glob" "--exclude 相当のパターン指定で比較対象から外れた"
  else
    _case_fail "除外-glob" "除外されなかった: ${out}"
  fi
  EXCLUDES=()
  rm -f "$tmp/a/onlya.txt"

  # 終了コード-相違時
  echo "changed" > "$tmp/b/file1.txt"
  checkrepro_compare "$tmp/a" "$tmp/b" >/dev/null
  rc=$?
  if [ "$rc" -eq 1 ]; then
    _case_pass "終了コード-相違時" "相違が1件でもあれば終了コード1"
  else
    _case_fail "終了コード-相違時" "終了コードが1でない（rc=${rc}）"
  fi
  echo "hello" > "$tmp/b/file1.txt"

  # 終了コード-一致時
  checkrepro_compare "$tmp/a" "$tmp/b" >/dev/null
  rc=$?
  if [ "$rc" -eq 0 ]; then
    _case_pass "終了コード-一致時" "全件一致で終了コード0"
  else
    _case_fail "終了コード-一致時" "終了コードが0でない（rc=${rc}）"
  fi

  # 判定不能-対象0件
  mkdir -p "$tmp/empty-a" "$tmp/empty-b"
  out="$(checkrepro_compare "$tmp/empty-a" "$tmp/empty-b")"
  rc=$?
  if [ "$rc" -eq 2 ] && echo "$out" | grep -q '^\[UNKNOWN\].*比較対象'; then
    _case_pass "判定不能-対象0件" "比較対象が無い場合を [UNKNOWN]・終了コード2で区別した"
  else
    _case_fail "判定不能-対象0件" "期待通りにならなかった: rc=${rc} ${out}"
  fi

  # 判定不能-TMPDIR不正: mktemp失敗を対象0件の原因へ誤分類せず、作成済みの
  # 一時ファイルを残さないこと。存在しないパスは自己テスト領域内に限定する。
  local invalid_tmp="$tmp/missing-tmpdir" invalid_tmp_out
  invalid_tmp_out="$(TMPDIR="$invalid_tmp" checkrepro_compare "$tmp/a" "$tmp/b")"
  rc=$?
  if [ "$rc" -eq 2 ] \
    && echo "$invalid_tmp_out" | grep -q '^\[UNKNOWN\].*操作: mktemp / 想定原因:' \
    && [ ! -e "$invalid_tmp" ]; then
    _case_pass "判定不能-TMPDIR不正" "mktemp失敗を構造化UNKNOWN・終了コード2で返した"
  else
    _case_fail "判定不能-TMPDIR不正" "mktemp失敗の理由または終了コードが不正（rc=${rc} ${invalid_tmp_out}）"
  fi

  # 独立性-同一物理ディレクトリの別名を拒否
  ln -s "$tmp/a" "$tmp/a-link"
  if _checkrepro_same_directory "$tmp/a" "$tmp/a-link"; then
    _case_pass "独立性-同一物理ディレクトリの別名を拒否" "symlink経由でも同一生成物と判定した"
  else
    _case_fail "独立性-同一物理ディレクトリの別名を拒否" "symlink経由の同一生成物を検出できなかった"
  fi

  # 時刻除外-一致判定
  echo '{"generatedAt":"2026-08-14T07:20:47Z","v":1}' > "$tmp/a/ts.json"
  echo '{"generatedAt":"2026-08-14T07:26:59Z","v":1}' > "$tmp/b/ts.json"
  IGNORE_TIMESTAMPS=1
  out="$(checkrepro_compare "$tmp/a" "$tmp/b")"
  IGNORE_TIMESTAMPS=0
  if echo "$out" | grep -q '^\[SAME-EXCEPT-TIME\] ts.json$' && echo "$out" | grep -q '時刻を除き一致 1 件'; then
    _case_pass "時刻除外-一致判定" "時刻だけが違う2ファイルが --ignore-timestamps で SAME-EXCEPT-TIME になった"
  else
    _case_fail "時刻除外-一致判定" "期待通りにならなかった: ${out}"
  fi

  # 時刻除外-既定は厳密
  out="$(checkrepro_compare "$tmp/a" "$tmp/b")"
  if echo "$out" | grep -q '^\[DIFF\] ts.json$'; then
    _case_pass "時刻除外-既定は厳密" "同じ2ファイルが --ignore-timestamps 無しでは DIFF になった"
  else
    _case_fail "時刻除外-既定は厳密" "期待通りにならなかった: ${out}"
  fi

  # 時刻除外-内容差は検出
  echo '{"generatedAt":"2026-08-14T07:26:59Z","v":2}' > "$tmp/b/ts.json"
  IGNORE_TIMESTAMPS=1
  out="$(checkrepro_compare "$tmp/a" "$tmp/b")"
  IGNORE_TIMESTAMPS=0
  if echo "$out" | grep -q '^\[DIFF\] ts.json$'; then
    _case_pass "時刻除外-内容差は検出" "時刻以外も違う2ファイルは --ignore-timestamps でも DIFF になった"
  else
    _case_fail "時刻除外-内容差は検出" "期待通りにならなかった: ${out}"
  fi
  rm -f "$tmp/a/ts.json" "$tmp/b/ts.json"

  rm -rf "$tmp"
  trap - EXIT

  echo "実行 ${run} 件 / 成功 ${ok} 件 / 失敗 ${ng} 件"
  [ "$ng" -eq 0 ]
}

# ---- 引数解析・ディスパッチ ---------------------------------------------

FIRST_DIR=""
SECOND_DIR=""
SELF_TEST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --first)
      FIRST_DIR="${2:-}"
      shift 2
      ;;
    --second)
      SECOND_DIR="${2:-}"
      shift 2
      ;;
    --exclude)
      EXCLUDES+=("${2:-}")
      shift 2
      ;;
    --ignore-timestamps)
      IGNORE_TIMESTAMPS=1
      shift
      ;;
    --self-test)
      SELF_TEST=1
      shift
      ;;
    *)
      echo "ERROR: 未知の引数です: $1" >&2
      exit 2
      ;;
  esac
done

if [ "$SELF_TEST" -eq 1 ]; then
  _checkrepro_self_test
  exit $?
fi

if [ -z "$FIRST_DIR" ] || [ -z "$SECOND_DIR" ]; then
  echo "ERROR: --first と --second は必須です" >&2
  echo "Usage: ${SCRIPT_NAME} --first <dir> --second <dir> [--exclude <glob>]... [--self-test]" >&2
  exit 2
fi

[ -d "$FIRST_DIR" ] || { echo "ERROR: --first のディレクトリが存在しません: ${FIRST_DIR}" >&2; exit 2; }
[ -d "$SECOND_DIR" ] || { echo "ERROR: --second のディレクトリが存在しません: ${SECOND_DIR}" >&2; exit 2; }

if _checkrepro_same_directory "$FIRST_DIR" "$SECOND_DIR"; then
  echo "[UNKNOWN] 独立した2回の生成物を確認できないため再現性を判定できません（--first と --second が同じ物理パスを指しています。2回の生成を別の出力先へ実行して指定してください）" >&2
  exit 2
fi

FIRST_DIR="$(cd "$FIRST_DIR" && pwd -P)"
SECOND_DIR="$(cd "$SECOND_DIR" && pwd -P)"

checkrepro_compare "$FIRST_DIR" "$SECOND_DIR"
exit $?
