#!/usr/bin/env bash
# verification-env.sh — 検証用の使い捨て環境（作業ツリー・出力先）を用意・破棄する共通関数
#
# 目的:
#   往復検証（原本コードとの突合）のために、版管理下から独立した使い捨ての
#   作業領域を発番・作成・削除する。作業領域は必ず ${TMPDIR:-/tmp}/reverse-verification/
#   配下に閉じ込め、誤ってリポジトリ内や範囲外のパスを削除しないよう検査する。
#
# 使い方:
#   source "path/to/verification-env.sh"
#   id="$(verification_env_new_id)"
#   base="$(verification_env_setup "$id")" || exit 1
#   ver="$(verification_env_record_version "<リポジトリのパス>")"
#   verification_env_teardown "$base" || exit 1
#
#   verification-env.sh --self-test   # 直接実行時のみ自己テストを走らせる
#
# 提供する関数:
#   verification_env_new_id                 — 識別子 verify-<epoch秒>-<PID起点の一意数> を標準出力へ返す
#   verification_env_setup <識別子>          — 作業領域を作り、絶対パスを標準出力へ返す
#   verification_env_teardown <作業領域の絶対パス> — 作業領域を削除する（範囲外は拒否し exit 1）
#   verification_env_record_version <リポジトリのパス> — HEAD の全長コミットハッシュを返す。
#     取得不可、または <リポジトリのパス> 自身が git リポジトリのトップレベルで
#     ない場合（版管理下に無い・祖先が別の無関係なリポジトリ）は unknown を返す。
#     祖先を遡った探索は行わない（探索の範囲を <リポジトリのパス> 自身に限る）
#
# 保守責任者: 人手（ユーザー）。作業領域の配置規約を変更する場合は本ファイルと self-test を同時に更新する。
# macOS bash 3.2 互換（連想配列・declare -A・${var^^} は使わない）。
set -uo pipefail

VERIFICATION_ENV_ROOT_NAME="reverse-verification"

# TMPDIR の末尾スラッシュを正規化してから reverse-verification/ の根を返す。
_verification_env_root() {
  local tmpdir="${TMPDIR:-/tmp}"
  tmpdir="${tmpdir%/}"
  echo "${tmpdir}/${VERIFICATION_ENV_ROOT_NAME}"
}

# 呼び出しは通常 `id="$(verification_env_new_id)"` のようにコマンド置換（サブシェル）
# 経由で行われるため、関数内のグローバル連番は呼び出しごとにリセットされ一意性の
# 保証にならない。/dev/urandom はサブシェルの分岐に影響されない系統の乱数源のため、
# PID（呼び出し元プロセス）と組み合わせて epoch 秒だけでは区別できない同一秒内の
# 連続呼び出しでも一意性を保証する。
verification_env_new_id() {
  local epoch rand
  epoch="$(date +%s)"
  rand="$(od -An -N4 -tu4 /dev/urandom 2>/dev/null | tr -d ' \n')"
  [ -n "$rand" ] || rand="$$"
  echo "verify-${epoch}-$$${rand}"
}

verification_env_setup() {
  local id="$1"
  if [ -z "$id" ]; then
    echo "ERROR: verification_env_setup には識別子が必要です" >&2
    return 1
  fi
  local root base
  root="$(_verification_env_root)"
  base="${root}/${id}"
  mkdir -p "${base}/worktree" "${base}/output" || {
    echo "ERROR: 作業領域の作成に失敗しました: ${base}" >&2
    return 1
  }
  echo "$base"
}

verification_env_teardown() {
  local path="$1"
  local root
  root="$(_verification_env_root)"
  if [ -z "$path" ]; then
    echo "ERROR: verification_env_teardown にはパスが必要です" >&2
    return 1
  fi
  case "$path" in
    "${root}"/*) ;;
    *)
      echo "ERROR: verification_env_teardown は ${root} 配下のパスのみ削除できます: ${path}" >&2
      return 1
      ;;
  esac
  rm -rf "$path"
}

verification_env_record_version() {
  local repo="$1"
  local repo_real toplevel hash
  # git は既定で祖先ディレクトリを遡って .git を探す。配布物が版管理の下に
  # 無い場所（$repo 自体が git リポジトリでない）に置かれていても、$repo の
  # 祖先に別の無関係なリポジトリがあれば、その HEAD を誤って取得してしまう。
  # 探索の範囲を $repo 自身に限るため、show-toplevel が $repo と一致する
  # 場合だけ HEAD を採用し、一致しなければ版は不明として扱う。
  repo_real="$(cd "$repo" 2>/dev/null && pwd -P)" || {
    echo "unknown"
    return 0
  }
  toplevel="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)"
  if [ -z "$toplevel" ] || [ "$toplevel" != "$repo_real" ]; then
    echo "unknown"
    return 0
  fi
  hash="$(git -C "$repo" rev-parse HEAD 2>/dev/null)"
  if [ -z "$hash" ] || [ "${#hash}" -ne 40 ]; then
    echo "unknown"
    return 0
  fi
  echo "$hash"
}

# ---- self-test ---------------------------------------------------------

_verification_env_self_test() {
  local run=0 ok=0 ng=0

  _case_pass() { run=$((run+1)); ok=$((ok+1)); echo "[PASS] $1 — $2"; }
  _case_fail() { run=$((run+1)); ng=$((ng+1)); echo "[FAIL] $1 — $2" >&2; }

  # 識別子-形式
  local id1
  id1="$(verification_env_new_id)"
  if [[ "$id1" =~ ^verify-[0-9]+-[0-9]+$ ]]; then
    _case_pass "識別子-形式" "verify- で始まり2つの数値部を持つ（${id1}）"
  else
    _case_fail "識別子-形式" "期待する形式に一致しない（${id1}）"
  fi

  # 識別子-一意
  local id2
  id2="$(verification_env_new_id)"
  if [ "$id1" != "$id2" ]; then
    _case_pass "識別子-一意" "2回の呼び出しで異なる値（$id1 / ${id2}）"
  else
    _case_fail "識別子-一意" "2回の呼び出しで同じ値（${id1}）"
  fi

  # 用意-配下作成
  local base
  base="$(verification_env_setup "$id1")"
  local setup_rc=$?
  if [ "$setup_rc" -eq 0 ] && [ -d "${base}/worktree" ] && [ -d "${base}/output" ]; then
    _case_pass "用意-配下作成" "worktree/ と output/ を作成した（${base}）"
  else
    _case_fail "用意-配下作成" "worktree/ または output/ が作成されなかった（${base}）"
  fi

  # 用意-版管理外
  if ! git -C "$base" rev-parse --show-toplevel >/dev/null 2>&1; then
    _case_pass "用意-版管理外" "作業領域は git リポジトリの中ではない"
  else
    _case_fail "用意-版管理外" "作業領域が git リポジトリとして検出された"
  fi

  # 破棄-範囲外拒否（先に検査。teardown で消える前に別パスを試す）
  local outside
  outside="$(mktemp -d "${TMPDIR:-/tmp}/verification-env-selftest-outside.XXXXXX")"
  verification_env_teardown "$outside" >/dev/null 2>&1
  local reject_rc=$?
  if [ "$reject_rc" -eq 1 ] && [ -d "$outside" ]; then
    _case_pass "破棄-範囲外拒否" "規定の親ディレクトリ配下でないパスを exit 1 で拒否し削除しなかった"
  else
    _case_fail "破棄-範囲外拒否" "拒否できなかった、または削除されてしまった（rc=${reject_rc}）"
  fi
  rm -rf "$outside"

  # 破棄-削除
  verification_env_teardown "$base" >/dev/null 2>&1
  if [ ! -d "$base" ]; then
    _case_pass "破棄-削除" "teardown 後に作業領域が存在しない"
  else
    _case_fail "破棄-削除" "teardown 後も作業領域が残っている（${base}）"
  fi

  # 版-全長
  # 配布物自身のルートではなく、この検査のために作った版管理のリポジトリで
  # 確かめる。配布物のルートを使うと、配布物が版管理の下に置かれているか
  # どうかで結果が変わる（改善課題 1-54: 置き場所によって結果が変わる）。
  # 配布物が版管理の下に無い場合に unknown を返すことは、後続の 2 ケース
  # 「版-版管理下に無い場所は不明」「版-祖先が別リポジトリでも不明」が受け持つ。
  local verRepo ver
  if ! verRepo="$(mktemp -d "${TMPDIR:-/tmp}/verification-env-selftest-ver.XXXXXX" 2>/dev/null)" || [ -z "$verRepo" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktemp が一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）"
    return 2
  fi
  verRepo="$(cd "$verRepo" && pwd -P)"
  git -C "$verRepo" init -q
  printf 'x\n' > "$verRepo/seed.txt"
  git -C "$verRepo" add seed.txt
  git -C "$verRepo" -c user.name=t -c user.email=t@example.com commit -q -m seed
  ver="$(verification_env_record_version "$verRepo")"
  if [[ "$ver" =~ ^[0-9a-f]{40}$ ]]; then
    _case_pass "版-全長" "40文字の16進文字列を返した（${ver}）"
  else
    _case_fail "版-全長" "40文字の16進文字列ではない（${ver}）"
  fi
  rm -rf "$verRepo"

  # 版-版管理下に無い場所は不明（改善課題: 検証の結果を信用できるようにする 3.2）:
  # 配布物自身が git リポジトリでない場所（かつ祖先にも git リポジトリが無い場所）
  # に置かれた場合、版の取得は失敗ではなく unknown を返す。
  local noGitDir noGitVer
  noGitDir="$(mktemp -d "${TMPDIR:-/tmp}/verification-env-selftest-nogit.XXXXXX")"
  if git -C "$noGitDir" rev-parse --show-toplevel >/dev/null 2>&1; then
    _case_fail "版-フィクスチャ前提" "テスト用ディレクトリの祖先に既に git リポジトリがあり前提が崩れている"
  else
    noGitVer="$(verification_env_record_version "$noGitDir")"
    if [ "$noGitVer" = "unknown" ]; then
      _case_pass "版-版管理下に無い場所は不明" "unknown を返した（祖先探索で誤爆しない）"
    else
      _case_fail "版-版管理下に無い場所は不明" "unknown ではなく ${noGitVer} を返した"
    fi
  fi
  rm -rf "$noGitDir"

  # 版-祖先が別リポジトリでも不明（改善課題: 検証の結果を信用できるようにする 3.2）:
  # 配布物自体は git リポジトリでないが、その祖先ディレクトリが無関係な別の
  # git リポジトリだった場合に、その無関係な HEAD を誤って取得しないことを確認する。
  local outerRepo innerDir outerHash innerVer
  outerRepo="$(mktemp -d "${TMPDIR:-/tmp}/verification-env-selftest-outer.XXXXXX")"
  innerDir="$outerRepo/payload/inner"
  mkdir -p "$innerDir"
  (
    cd "$outerRepo" || exit 1
    git init -q
    git -c user.email="selftest@example.com" -c user.name="selftest" commit --allow-empty -qm init
  )
  outerHash="$(cd "$outerRepo" && git rev-parse HEAD 2>/dev/null)"
  innerVer="$(verification_env_record_version "$innerDir")"
  if [ "$innerVer" = "unknown" ] && [ "$innerVer" != "$outerHash" ]; then
    _case_pass "版-祖先が別リポジトリでも不明" "無関係な祖先リポジトリの HEAD（${outerHash}）を借用せず unknown を返した"
  else
    _case_fail "版-祖先が別リポジトリでも不明" "unknown を返すべきところ ${innerVer} を返した（祖先 HEAD=${outerHash}）"
  fi
  rm -rf "$outerRepo"

  echo "実行 ${run} 件 / 成功 ${ok} 件 / 失敗 ${ng} 件"
  [ "$ng" -eq 0 ]
}

# 直接実行時のみディスパッチする（source 時は呼び出し元の位置引数を誤読しない）
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ] && [ "${1:-}" = "--self-test" ]; then
  _verification_env_self_test
  exit $?
fi
