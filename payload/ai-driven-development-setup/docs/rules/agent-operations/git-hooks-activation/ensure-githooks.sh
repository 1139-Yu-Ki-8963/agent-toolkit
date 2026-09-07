#!/bin/bash -p
# ensure-githooks.sh — 設計先行の検査（reference-transaction）の実体を、
# mainのコミット済みオブジェクトストアから共有gitディレクトリ（common dir）
#
# シェバンは`#!/bin/bash -p`（特権モード）に固定する。本スクリプトは
# SessionStartのたびに直接実行され（`.claude/settings.json`のhooks経由）、
# `BASH_ENV`等でインタプリタ起動そのものを乗っ取られると、core.hooksPathの
# 導入処理自体が無効化されうる（2026-09-06第19版。15回目の反証を受け、
# reference-transactionと対で固定した）。
# 配下へ導入し、core.hooksPathをその絶対パスへ設定し直す。セッション開始の
# たびに実行する。
#
# timing: SessionStart
#
# 第5版（2026-09-06）: 導入元をmainの版だけに限定する。以前（第4版）は
# 作業ツリーのgithooks/フォルダへ相対パスでcore.hooksPathを向けていたため、
# 次の2つの穴があった。
#   1. 作業ツリーでフックファイルをrmすると、gitは（core.hooksPathが指す
#      先が存在しないため）フックを発火させず素通りする。Claude側の検査も
#      core.hooksPathの文字列だけを見ていたため、両方とも検知できなかった
#   2. 作業ツリーでフック本体を`exit 0`に書き換えてmergeすると、参照更新の
#      直前に無力化された版が発火する
# 本版は、gitのconfig（core.hooksPath）が全worktreeで共有される
# common dir単位の値であることを利用し、mainのコミット済みの版だけを
# common dir配下（design-first-hooks/）へ書き出し、そこへcore.hooksPathを
# 絶対パスで向ける。作業ツリー側のgithooks/・shared/を変更しても、mainへ
# 取り込まれ次のSessionStartでensure-githooks.shが再導入するまでは
# 導入済みの実体に影響しない（鶏卵回避のための例外は不要になる。
# rule.mdの設計判断・既知の限界を参照）。
#
# 第16版（2026-09-06）: 14回目の反証で、`GIT_EXEC_PATH=<偽のgitを置いたdir>
# git merge --no-ff feature`が本体を破ることが実測された。gitはフック起動時に
# GIT_EXEC_PATHの指す先をPATHの先頭へ足すため、フック・共有ライブラリが呼ぶ
# 裸の`git`が偽の実体を向く。`PATH=偽:$PATH`はgit-core自身のprependで無力化
# されるが、GIT_EXEC_PATHはgit-coreそのものを差し替えるため環境変数の除去
# だけでは防げない。本版は、導入時に固定PATH（GIT_RESOLVE_PATH。/usr/bin等の
# 既定のディレクトリだけを見る）でgitの絶対パスを一度だけ解決し、導入先へ
# `git-path`として記録する。フック・共有ライブラリはこの記録済みの絶対パス
# でgitを呼ぶ（reference-transaction・design-first-lib.shを参照）。解決した
# git が一時領域（$TMPDIR・/tmp・/private/tmp）またはリポジトリの作業ツリー
# 配下を指す場合は、偽物が紛れ込んでいる疑いがあるため導入を止める。
#
# 使い方:
#   ensure-githooks.sh <リポジトリのルート>
#   ensure-githooks.sh --self-test

set -uo pipefail

# 親プロセスから継承された設定上書きを先頭で捨てる（2026-09-06第13版
# レビュー: `-c core.useReplaceRefs=true`はGIT_CONFIG_PARAMETERSとして
# 子プロセスへ継承され、GIT_NO_REPLACE_OBJECTSより優先順位が高い。継承分は
# ここで捨て、mainの版の読み出しにはCLIで`--no-replace-objects`を明示する）。
unset GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT 2>/dev/null || true
for _dfl_inherited_var in $(env 2>/dev/null | awk -F= '/^GIT_CONFIG_(KEY|VALUE)_?[0-9]+=/{print $1}'); do
  unset "$_dfl_inherited_var" 2>/dev/null || true
done
unset _dfl_inherited_var 2>/dev/null || true

# mainの版の読み出し（git show main:…・cat-file）が置換参照
# （refs/replace/）越しの捏造内容を読まないようにする（2026-09-06
# 第12版反証。install_from_mainがcommon dir配下へ書き出す実体は、
# 常にmainのコミット済みの真の内容と一致していなければならない。第13版で
# 環境変数だけに頼らず、下のgit呼び出しにもCLIで`--no-replace-objects`を
# 明示する構成へ改めた。この export は多重の防御として残す）。
export GIT_NO_REPLACE_OBJECTS=1

# graft（`.git/info/grafts`）を無視する（2026-09-06第13版レビュー）。
export GIT_GRAFT_FILE=/dev/null

HOOK_INSTALL_SUBDIR="design-first-hooks"
HOOK_REL_MAIN="docs/rules/agent-operations/work-records/githooks/reference-transaction"
LIB_REL_MAIN="docs/rules/agent-operations/work-records/shared/design-first-lib.sh"
GIT_MIN_MAJOR=2
GIT_MIN_MINOR=28

# gitの絶対パスを解決するときにだけ使う固定のPATH（第16版新設）。実行環境の
# PATH（GIT_EXEC_PATHの影響を受けうる）を一切見ない。自己テストが偽のgitを
# 使って導入停止を確かめるときだけ、このデフォルト値を書き換える。
GIT_RESOLVE_PATH_DEFAULT="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin"
GIT_RESOLVE_PATH="$GIT_RESOLVE_PATH_DEFAULT"

# $1: file。1行目が厳密に`#!/bin/bash -p`と一致するかを見る（2026-09-06
# 第20版新設。16回目の反証。`BASH_ENV`等によるインタプリタ起動の乗っ取りは
# シェバンが`#!/bin/bash -p`でないと防げないため、mainのコミット済みの版を
# common dirへ書き出す前に確かめ、一致しなければ導入を止める。導入後の
# 差し替えはverify_installed_hooks_cwr側の再検査が別途見る）。
_dfl_first_line_is_bash_p() {
  local file="$1" first
  first="$(head -1 "$file" 2>/dev/null)"
  [ "$first" = "#!/bin/bash -p" ]
}

# $1: バージョン文字列（例: "2.39.5"）。GIT_MIN_MAJOR.GIT_MIN_MINOR以上なら
# 真を返す。
git_version_ge_min() {
  local v="$1" major minor
  major="$(printf '%s' "$v" | awk -F. '{print $1+0}')"
  minor="$(printf '%s' "$v" | awk -F. '{print $2+0}')"
  [ -z "$major" ] && return 1
  if [ "$major" -gt "$GIT_MIN_MAJOR" ]; then return 0; fi
  if [ "$major" -lt "$GIT_MIN_MAJOR" ]; then return 1; fi
  [ "$minor" -ge "$GIT_MIN_MINOR" ]
}

git_version_raw() {
  git --version 2>/dev/null | awk '{print $3}'
}

# $1: root。common dir（全worktreeで共有される実体の.gitディレクトリ）の
# 絶対パスを返す。git rev-parse --git-common-dirはメインツリーからは
# 相対パス（例: ".git"）を返すことがあるため、cdしてpwdすることで
# 常に絶対パスへ解決する（2026-09-06第5版反証: 相対パスのままcore.hooksPath
# へ設定すると、Claude側の絶対パス一致検査と食い違い、開始の検査が
# 常にfail-closedになる不具合があった）。
resolve_common_dir() {
  local root="$1" out
  out="$(git -C "$root" rev-parse --git-common-dir 2>/dev/null)" || return 1
  case "$out" in
    /*) : ;;
    *) out="${root}/${out}" ;;
  esac
  (cd "$out" 2>/dev/null && pwd -P)
}

# $1: root。GIT_RESOLVE_PATH（固定のPATH。実行環境のPATH・GIT_EXEC_PATHは
# 一切見ない）でgitの絶対パスを解決する。symlinkを辿った実体をpwd -Pで
# 正規化してから、一時領域（$TMPDIR・/tmp・/private/tmp）またはrootの作業
# ツリー配下を指していないかを確かめる。指していれば偽物が紛れ込んでいる
# 疑いがあるため戻り値1（呼び出し側install_from_mainが導入を止める。
# 第16版新設）。TMPDIRはmacOSで`/var/folders/…`が`/private/var/folders/…`の
# symlinkであるため、両方とも pwd -P で正規化してから比較する。
# 第17版（2026-09-06）: bashのコマンドハッシュ表が`git`を過去の呼び出し
# （本関数より前のcat-file等）の実PATHで記憶しているため、`PATH=…
# command -v git`が固定PATHを無視しハッシュ済みの値を返す実測不具合が
# あった（自己テストのケース13・14が別のbash・別のTMPDIRの環境で
# rc=0になる形で発現）。ハッシュはGIT_EXEC_PATHが先頭に割り込ませた
# 偽gitのパスを記憶しうるため、固定PATHでの解決そのものを無力化する
# 穴でもある。検索の直前に`git`のハッシュ項目だけを消し、常に
# GIT_RESOLVE_PATHでの実探索を強制する。
resolve_git_path() {
  local root="$1" git_bin real_dir real_path tmp_canon
  hash -d git 2>/dev/null || true
  git_bin="$(PATH="$GIT_RESOLVE_PATH" command -v git 2>/dev/null)" || return 1
  [ -z "$git_bin" ] && return 1
  case "$git_bin" in
    /*) : ;;
    *) return 1 ;;
  esac
  real_dir="$(cd "$(dirname "$git_bin")" 2>/dev/null && pwd -P)" || return 1
  real_path="${real_dir}/$(basename "$git_bin")"
  case "$real_path" in
    /tmp/*|/private/tmp/*) return 1 ;;
  esac
  case "$real_path" in
    "${root}"/*) return 1 ;;
  esac
  tmp_canon="$(cd "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P)"
  if [ -n "$tmp_canon" ]; then
    case "$real_path" in "${tmp_canon}"/*) return 1 ;; esac
  fi
  printf '%s' "$real_path"
}

# $1: root。`refs/heads/main`がシンボリック参照（`git symbolic-ref
# <他の参照>`で作られた、他の参照への別名）になっていないかを見る。
# なっていれば真を返す（2026-09-06 18回目の反証: `git symbolic-ref
# refs/heads/main refs/heads/feature`はmainの指す先を差し替えるが、gitの
# 参照更新フック（reference-transaction）はこの操作をprepared・committed
# のどちらの段階でも発火しない。本体の観測点そのものを経ない差し替えで
# あるため、フック側では検知できない。導入・再検査の側で拒否する）。
_egt_main_is_symbolic() {
  local root="$1"
  git -C "$root" symbolic-ref -q refs/heads/main >/dev/null 2>&1
}

# $1: root。mainのコミット済みの版から導入する。バージョン不足・main不在・
# 対象ファイル不在の場合は何もせず戻り値1（開始の検査側がcore.hooksPathの
# 不整合としてfail-closedにする。中途半端な設定を残さない）。
install_from_main() {
  local root="$1" common_dir install_dir default_hooks gv f name alias_list

  if _egt_main_is_symbolic "$root"; then
    echo "警告[main がシンボリック参照になっている]: refs/heads/main がシンボリック参照になっている。導入を止める" >&2
    return 1
  fi

  gv="$(git_version_raw)"
  if [ -z "$gv" ] || ! git_version_ge_min "$gv"; then
    echo "git ${GIT_MIN_MAJOR}.${GIT_MIN_MINOR} 以上が必要（現在: ${gv:-不明}）。導入をスキップする" >&2
    return 1
  fi

  # git config alias.* はgitの副命令を任意に間接実行できる経路であり、
  # 放置すると設計先行の検査（副命令の字面照合に依存する箇所）を迂回する
  # 足がかりになる。導入の前にalias.*の登録が無いことを確かめ、あれば
  # 導入を止めて警告する（2026-09-06第11版新設）。
  alias_list="$(git -C "$root" config --get-regexp '^alias\.' 2>/dev/null)"
  if [ -n "$alias_list" ]; then
    echo "警告[導入時に alias が無いことを確かめる]: alias が登録されている: ${alias_list}" >&2
    return 1
  fi

  git --no-replace-objects -C "$root" cat-file -e main 2>/dev/null || return 1
  git --no-replace-objects -C "$root" cat-file -e "main:${HOOK_REL_MAIN}" 2>/dev/null || return 1
  git --no-replace-objects -C "$root" cat-file -e "main:${LIB_REL_MAIN}" 2>/dev/null || return 1

  common_dir="$(resolve_common_dir "$root")" || return 1
  install_dir="${common_dir}/${HOOK_INSTALL_SUBDIR}"
  mkdir -p "${install_dir}/githooks" "${install_dir}/shared" || return 1

  # gitの絶対パスを固定PATHで解決し、導入先へgit-pathとして記録する
  # （第16版新設）。一時領域・作業ツリー配下を指す場合はresolve_git_pathが
  # 戻り値1を返し、ここで導入を止める。中途半端な導入を残さないよう、
  # フック本体・共有ライブラリの書き出しより前に確定させる。
  local resolved_git_path
  resolved_git_path="$(resolve_git_path "$root")"
  if [ -z "$resolved_git_path" ]; then
    echo "警告[gitの絶対パスを固定する]: 既定のPATH（${GIT_RESOLVE_PATH}）でgitを解決できない、または一時領域・作業ツリー配下を指すため導入を止める" >&2
    return 1
  fi
  printf '%s' "$resolved_git_path" > "${install_dir}/git-path"
  shasum -a 256 "$resolved_git_path" 2>/dev/null | awk '{print $1}' > "${install_dir}/git-path.sha256"

  git --no-replace-objects -C "$root" show "main:${HOOK_REL_MAIN}" > "${install_dir}/githooks/reference-transaction.tmp" 2>/dev/null || return 1
  if ! _dfl_first_line_is_bash_p "${install_dir}/githooks/reference-transaction.tmp"; then
    echo "警告[シェバンを固定する]: mainのreference-transactionの1行目が#!/bin/bash -pでないため導入を止める" >&2
    rm -f "${install_dir}/githooks/reference-transaction.tmp"
    return 1
  fi
  mv "${install_dir}/githooks/reference-transaction.tmp" "${install_dir}/githooks/reference-transaction"
  chmod +x "${install_dir}/githooks/reference-transaction"

  git --no-replace-objects -C "$root" show "main:${LIB_REL_MAIN}" > "${install_dir}/shared/design-first-lib.sh.tmp" 2>/dev/null || return 1
  if ! _dfl_first_line_is_bash_p "${install_dir}/shared/design-first-lib.sh.tmp"; then
    echo "警告[シェバンを固定する]: mainのdesign-first-lib.shの1行目が#!/bin/bash -pでないため導入を止める" >&2
    rm -f "${install_dir}/shared/design-first-lib.sh.tmp"
    return 1
  fi
  mv "${install_dir}/shared/design-first-lib.sh.tmp" "${install_dir}/shared/design-first-lib.sh"

  # 既存の.git/hooks（common dir直下の既定のフックディレクトリ）の実行可能な
  # フックを共存ラッパーで引き継ぐ。core.hooksPathをdesign-first-hooks/へ
  # 向けると、gitは既定の.git/hooksを見なくなるため、既存フックを失わせない
  # ためにラッパーで呼び戻す。reference-transaction以外の同名フックが既に
  # 導入フォルダに無い場合だけラッパーを置く（reference-transaction自体は
  # 常にこちらの版で上書きする）。
  default_hooks="${common_dir}/hooks"
  if [ -d "$default_hooks" ]; then
    for f in "$default_hooks"/*; do
      [ -e "$f" ] || continue
      [ -x "$f" ] || continue
      name="$(basename "$f")"
      case "$name" in *.sample) continue ;; esac
      [ "$name" = "reference-transaction" ] && continue
      [ -e "${install_dir}/githooks/${name}" ] && continue
      {
        printf '#!/usr/bin/env bash\n'
        printf '# 共存ラッパー（ensure-githooks.shが自動生成）。既存の%s/%sへ引き継ぐ\n' "$default_hooks" "$name"
        printf 'exec "%s/%s" "$@"\n' "$default_hooks" "$name"
      } > "${install_dir}/githooks/${name}"
      chmod +x "${install_dir}/githooks/${name}"
    done
  fi

  git -C "$root" config core.hooksPath "${install_dir}/githooks"
}

ensure_one() {
  local root="$1"
  [ -d "${root}/.git" ] || [ -f "${root}/.git" ] || return 0
  install_from_main "$root"
}

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi
  local root="${1:-$PWD}"
  ensure_one "$root"
}

# --- 自己テスト用ヘルパー ---------------------------------------------------

_egt_init_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q -b main 2>/dev/null || { git -C "$repo" init -q; git -C "$repo" checkout -q -B main; }
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "test"
}

# $1: repo。mainへ実物と同じ相対パスのhook・libを置いてcommitする。シェバンは
# 実物と同じ`#!/bin/bash -p`にする（2026-09-06第20版。install_from_mainが
# シェバン照合で導入を止めるようになったため、正常系のシードもこれに合わせる）。
_egt_seed_main_hook() {
  local repo="$1"
  mkdir -p "${repo}/$(dirname "$HOOK_REL_MAIN")" "${repo}/$(dirname "$LIB_REL_MAIN")" "${repo}/ai-work"
  {
    printf '#!/bin/bash -p\n'
    printf 'STAGE="${1:-}"\n'
    printf 'if [ "$STAGE" != "prepared" ]; then cat >/dev/null; exit 0; fi\n'
    printf 'cat >/dev/null\n'
    printf 'exit 1\n'
  } > "${repo}/${HOOK_REL_MAIN}"
  chmod +x "${repo}/${HOOK_REL_MAIN}"
  printf '#!/bin/bash -p\n# stub lib\n' > "${repo}/${LIB_REL_MAIN}"
  : > "${repo}/ai-work/.keep"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "seed"
}

# $1: repo  $2: target（hook または lib）。_egt_seed_main_hookと同じ内容だが、
# $2で指定した側だけシェバンを`#!/usr/bin/env bash`（不一致）にしてcommitする
# （2026-09-06第20版新設。導入時のシェバン照合が拒否することを確かめる
# ケース15・16で使う）。
_egt_seed_main_hook_bad_shebang() {
  local repo="$1" target="$2" hook_shebang="#!/bin/bash -p" lib_shebang="#!/bin/bash -p"
  [ "$target" = "hook" ] && hook_shebang="#!/usr/bin/env bash"
  [ "$target" = "lib" ] && lib_shebang="#!/usr/bin/env bash"
  mkdir -p "${repo}/$(dirname "$HOOK_REL_MAIN")" "${repo}/$(dirname "$LIB_REL_MAIN")" "${repo}/ai-work"
  {
    printf '%s\n' "$hook_shebang"
    printf 'STAGE="${1:-}"\n'
    printf 'if [ "$STAGE" != "prepared" ]; then cat >/dev/null; exit 0; fi\n'
    printf 'cat >/dev/null\n'
    printf 'exit 1\n'
  } > "${repo}/${HOOK_REL_MAIN}"
  chmod +x "${repo}/${HOOK_REL_MAIN}"
  printf '%s\n# stub lib\n' "$lib_shebang" > "${repo}/${LIB_REL_MAIN}"
  : > "${repo}/ai-work/.keep"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "seed (bad shebang: ${target})"
}

self_test() {
  local tmp pass=0 fail=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/ensure-githooks.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  # ケース1: mainにhook/libがあるリポジトリでcore.hooksPathが導入先の
  # 絶対パスに設定され、実体が書き出される
  local repo1="$tmp/repo1"
  _egt_init_repo "$repo1"
  _egt_seed_main_hook "$repo1"
  ensure_one "$repo1"
  local got common_dir1 expect1
  got="$(git -C "$repo1" config --get core.hooksPath 2>/dev/null)"
  common_dir1="$(resolve_common_dir "$repo1")"
  expect1="${common_dir1}/${HOOK_INSTALL_SUBDIR}/githooks"
  if [ "$got" = "$expect1" ] && [ -x "${expect1}/reference-transaction" ] && [ -f "${common_dir1}/${HOOK_INSTALL_SUBDIR}/shared/design-first-lib.sh" ]; then
    echo "  [PASS] ケース1: mainの版から導入し絶対パスを設定する"; pass=$((pass + 1))
  else
    echo "  [FAIL] ケース1: mainの版から導入し絶対パスを設定する（got=${got} expect=${expect1}）" >&2; fail=$((fail + 1))
  fi

  # ケース2: 導入した実体の内容がmainのコミット済みの版と一致する
  local repo2="$tmp/repo2"
  _egt_init_repo "$repo2"
  _egt_seed_main_hook "$repo2"
  ensure_one "$repo2"
  local common_dir2 installed_sha main_sha
  common_dir2="$(resolve_common_dir "$repo2")"
  installed_sha="$(shasum -a 256 "${common_dir2}/${HOOK_INSTALL_SUBDIR}/githooks/reference-transaction" 2>/dev/null | awk '{print $1}')"
  main_sha="$(git -C "$repo2" show "main:${HOOK_REL_MAIN}" 2>/dev/null | shasum -a 256 | awk '{print $1}')"
  if [ -n "$installed_sha" ] && [ "$installed_sha" = "$main_sha" ]; then
    echo "  [PASS] ケース2: 導入した実体のsha256がmainの版と一致する"; pass=$((pass + 1))
  else
    echo "  [FAIL] ケース2: 導入した実体のsha256がmainの版と一致する（installed=${installed_sha} main=${main_sha}）" >&2; fail=$((fail + 1))
  fi

  # ケース3: mainにhook/libが無いリポジトリでは何もしない（core.hooksPath未設定のまま）
  local repo3="$tmp/repo3"
  _egt_init_repo "$repo3"
  mkdir -p "${repo3}/ai-work"
  : > "${repo3}/ai-work/.keep"
  git -C "$repo3" add -A
  git -C "$repo3" commit -q -m "no hook"
  local rc3=0
  ensure_one "$repo3" || rc3=$?
  got="$(git -C "$repo3" config --get core.hooksPath 2>/dev/null)"
  if [ -z "$got" ]; then
    echo "  [PASS] ケース3: mainにhookが無い-何もしない"; pass=$((pass + 1))
  else
    echo "  [FAIL] ケース3: mainにhookが無い-何もしない（got=${got}）" >&2; fail=$((fail + 1))
  fi

  # ケース4: gitリポジトリでないディレクトリでは何もしない（エラーにしない）
  local notrepo="$tmp/notrepo"
  mkdir -p "$notrepo"
  local rc4=0
  ensure_one "$notrepo" || rc4=$?
  if [ "$rc4" -eq 0 ]; then
    echo "  [PASS] ケース4: gitリポジトリでない-何もしない"; pass=$((pass + 1))
  else
    echo "  [FAIL] ケース4: gitリポジトリでない-何もしない（rc=${rc4}）" >&2; fail=$((fail + 1))
  fi

  # ケース5: 既存のcore.hooksPathが別の値でも上書きする
  local repo5="$tmp/repo5"
  _egt_init_repo "$repo5"
  _egt_seed_main_hook "$repo5"
  git -C "$repo5" config core.hooksPath "other/path"
  ensure_one "$repo5"
  got="$(git -C "$repo5" config --get core.hooksPath 2>/dev/null)"
  local common_dir5 expect5
  common_dir5="$(resolve_common_dir "$repo5")"
  expect5="${common_dir5}/${HOOK_INSTALL_SUBDIR}/githooks"
  if [ "$got" = "$expect5" ]; then
    echo "  [PASS] ケース5: 別の値が設定済みでも上書きする"; pass=$((pass + 1))
  else
    echo "  [FAIL] ケース5: 別の値が設定済みでも上書きする（got=${got}）" >&2; fail=$((fail + 1))
  fi

  # ケース6: 既存の.git/hooks/pre-commit（実行可能）があれば共存ラッパーを
  # 導入フォルダへ置き、実際に元のフックへ引き継がれる
  local repo6="$tmp/repo6"
  _egt_init_repo "$repo6"
  _egt_seed_main_hook "$repo6"
  local common_dir6
  common_dir6="$(resolve_common_dir "$repo6")"
  mkdir -p "${common_dir6}/hooks"
  local marker6="${tmp}/pre-commit-ran"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'echo ran > "%s"\n' "$marker6"
    printf 'exit 0\n'
  } > "${common_dir6}/hooks/pre-commit"
  chmod +x "${common_dir6}/hooks/pre-commit"
  ensure_one "$repo6"
  if [ -x "${common_dir6}/${HOOK_INSTALL_SUBDIR}/githooks/pre-commit" ]; then
    ( cd "$repo6" && : > f.txt && git add f.txt && git commit -q -m "wrapper test" ) >/dev/null 2>&1
    if [ -f "$marker6" ]; then
      echo "  [PASS] ケース6: 既存フックを共存ラッパーで引き継ぐ"; pass=$((pass + 1))
    else
      echo "  [FAIL] ケース6: ラッパーは置かれたが元のフックが呼ばれていない" >&2; fail=$((fail + 1))
    fi
  else
    echo "  [FAIL] ケース6: 既存フックの共存ラッパーが導入フォルダに無い" >&2; fail=$((fail + 1))
  fi

  # ケース7: git 2.28未満相当を模擬するとバージョン判定関数が偽を返す
  if git_version_ge_min "2.27.0"; then
    echo "  [FAIL] ケース7: 2.27を2.28未満として判定する" >&2; fail=$((fail + 1))
  else
    echo "  [PASS] ケース7: 2.27を2.28未満として判定する"; pass=$((pass + 1))
  fi
  if git_version_ge_min "2.28.0" && git_version_ge_min "3.0.0"; then
    echo "  [PASS] ケース8: 2.28以上（同値・メジャー超え）を満たすとして判定する"; pass=$((pass + 1))
  else
    echo "  [FAIL] ケース8: 2.28以上を満たすとして判定する" >&2; fail=$((fail + 1))
  fi

  # ケース9: メインツリー（rev-parse --git-common-dirが相対パス".git"を
  # 返す環境）でも絶対パスへ解決する
  local repo9 common_dir9
  repo9="$tmp/repo9"
  _egt_init_repo "$repo9"
  common_dir9="$(resolve_common_dir "$repo9")"
  case "$common_dir9" in
    /*) echo "  [PASS] ケース9: common dirを絶対パスへ解決する"; pass=$((pass + 1)) ;;
    *) echo "  [FAIL] ケース9: common dirを絶対パスへ解決する（got=${common_dir9}）" >&2; fail=$((fail + 1)) ;;
  esac

  # ケース10: aliasが登録されていると導入を止めて警告する
  local repo10="$tmp/repo10"
  _egt_init_repo "$repo10"
  _egt_seed_main_hook "$repo10"
  git -C "$repo10" config alias.fp "push --force"
  local out10 rc10=0
  out10="$(ensure_one "$repo10" 2>&1)" || rc10=$?
  got="$(git -C "$repo10" config --get core.hooksPath 2>/dev/null)"
  if [ "$rc10" -ne 0 ] && [ -z "$got" ] && printf '%s' "$out10" | grep -q '警告\[導入時に alias が無いことを確かめる\]'; then
    echo "  [PASS] ケース10: aliasありは導入を止めて警告する"; pass=$((pass + 1))
  else
    echo "  [FAIL] ケース10: aliasありは導入を止めて警告する（rc=${rc10} got=${got} out=${out10}）" >&2; fail=$((fail + 1))
  fi

  # ケース11: aliasが無ければ従来どおり導入する
  local repo11="$tmp/repo11"
  _egt_init_repo "$repo11"
  _egt_seed_main_hook "$repo11"
  ensure_one "$repo11"
  got="$(git -C "$repo11" config --get core.hooksPath 2>/dev/null)"
  if [ -n "$got" ]; then
    echo "  [PASS] ケース11: aliasなしは導入する"; pass=$((pass + 1))
  else
    echo "  [FAIL] ケース11: aliasなしは導入する（got=${got}）" >&2; fail=$((fail + 1))
  fi

  # ケース12: git-pathが記録され、実体のsha256が固定PATHで解決したgitと
  # 一致する（第16版新設）
  local repo12 common_dir12 git_path_file12 real_git12 sha_file12 sha_installed12 sha_actual12
  repo12="$tmp/repo12"
  _egt_init_repo "$repo12"
  _egt_seed_main_hook "$repo12"
  ensure_one "$repo12"
  common_dir12="$(resolve_common_dir "$repo12")"
  git_path_file12="${common_dir12}/${HOOK_INSTALL_SUBDIR}/git-path"
  real_git12="$(cat "$git_path_file12" 2>/dev/null)"
  sha_file12="${common_dir12}/${HOOK_INSTALL_SUBDIR}/git-path.sha256"
  sha_installed12="$(cat "$sha_file12" 2>/dev/null)"
  sha_actual12="$(shasum -a 256 "$real_git12" 2>/dev/null | awk '{print $1}')"
  if [ -n "$real_git12" ] && [ -x "$real_git12" ] && [ -n "$sha_actual12" ] && [ "$sha_installed12" = "$sha_actual12" ]; then
    echo "  [PASS] ケース12: git-pathが記録されsha256が実体と一致する"; pass=$((pass + 1))
  else
    echo "  [FAIL] ケース12: git-pathが記録されsha256が実体と一致する（git=${real_git12} installed=${sha_installed12} actual=${sha_actual12}）" >&2; fail=$((fail + 1))
  fi

  # ケース13: 解決したgitが$TMPDIR配下（偽のgit）を指すと導入を止める
  # （GIT_EXEC_PATHによる偽git差し替えの反証を受けた第16版新設）
  local repo13 fakebin13 saved_resolve_path rc13
  repo13="$tmp/repo13"
  _egt_init_repo "$repo13"
  _egt_seed_main_hook "$repo13"
  fakebin13="$tmp/fake-git-bin-13"
  mkdir -p "$fakebin13"
  printf '#!/usr/bin/env bash\necho "git version 2.99.0"\n' > "${fakebin13}/git"
  chmod +x "${fakebin13}/git"
  saved_resolve_path="$GIT_RESOLVE_PATH"
  GIT_RESOLVE_PATH="${fakebin13}:${GIT_RESOLVE_PATH_DEFAULT}"
  rc13=0
  ensure_one "$repo13" || rc13=$?
  GIT_RESOLVE_PATH="$saved_resolve_path"
  got="$(git -C "$repo13" config --get core.hooksPath 2>/dev/null)"
  if [ "$rc13" -ne 0 ] && [ -z "$got" ]; then
    echo "  [PASS] ケース13: 解決したgitが\$TMPDIR配下なら導入を止める"; pass=$((pass + 1))
  else
    echo "  [FAIL] ケース13: 解決したgitが\$TMPDIR配下なら導入を止める（rc=${rc13} got=${got}）" >&2; fail=$((fail + 1))
  fi

  # ケース14: 解決したgitが作業ツリー（root）配下を指すと導入を止める。
  # 自己テストは$TMPDIR配下で動くため、この偽gitも同時にTMPDIR配下に
  # あるが、作業ツリー配下判定の分岐そのものを踏むことが目的である。
  local repo14 fakebin14 rc14
  repo14="$tmp/repo14"
  _egt_init_repo "$repo14"
  _egt_seed_main_hook "$repo14"
  fakebin14="${repo14}/fake-git-bin-14"
  mkdir -p "$fakebin14"
  printf '#!/usr/bin/env bash\necho "git version 2.99.0"\n' > "${fakebin14}/git"
  chmod +x "${fakebin14}/git"
  saved_resolve_path="$GIT_RESOLVE_PATH"
  GIT_RESOLVE_PATH="${fakebin14}:${GIT_RESOLVE_PATH_DEFAULT}"
  rc14=0
  ensure_one "$repo14" || rc14=$?
  GIT_RESOLVE_PATH="$saved_resolve_path"
  got="$(git -C "$repo14" config --get core.hooksPath 2>/dev/null)"
  if [ "$rc14" -ne 0 ] && [ -z "$got" ]; then
    echo "  [PASS] ケース14: 解決したgitが作業ツリー配下なら導入を止める"; pass=$((pass + 1))
  else
    echo "  [FAIL] ケース14: 解決したgitが作業ツリー配下なら導入を止める（rc=${rc14} got=${got}）" >&2; fail=$((fail + 1))
  fi

  # ケース15: mainのreference-transactionのシェバンが#!/bin/bash -pで
  # ないと導入を止める（2026-09-06第20版新設。16回目の反証）
  local repo15 rc15=0
  repo15="$tmp/repo15"
  _egt_init_repo "$repo15"
  _egt_seed_main_hook_bad_shebang "$repo15" hook
  ensure_one "$repo15" || rc15=$?
  got="$(git -C "$repo15" config --get core.hooksPath 2>/dev/null)"
  if [ "$rc15" -ne 0 ] && [ -z "$got" ]; then
    echo "  [PASS] ケース15: hookのシェバン不一致は導入を止める"; pass=$((pass + 1))
  else
    echo "  [FAIL] ケース15: hookのシェバン不一致は導入を止める（rc=${rc15} got=${got}）" >&2; fail=$((fail + 1))
  fi

  # ケース16: mainのdesign-first-lib.shのシェバンが#!/bin/bash -pで
  # ないと導入を止める
  local repo16 rc16=0
  repo16="$tmp/repo16"
  _egt_init_repo "$repo16"
  _egt_seed_main_hook_bad_shebang "$repo16" lib
  ensure_one "$repo16" || rc16=$?
  got="$(git -C "$repo16" config --get core.hooksPath 2>/dev/null)"
  if [ "$rc16" -ne 0 ] && [ -z "$got" ]; then
    echo "  [PASS] ケース16: libのシェバン不一致は導入を止める"; pass=$((pass + 1))
  else
    echo "  [FAIL] ケース16: libのシェバン不一致は導入を止める（rc=${rc16} got=${got}）" >&2; fail=$((fail + 1))
  fi

  # ケース17: refs/heads/mainがシンボリック参照（`git symbolic-ref
  # refs/heads/main refs/heads/feature`）になっていると導入を止める
  # （2026-09-06 18回目の反証。gitの参照更新フックはこの操作を発火させ
  # ないため、導入・再検査の側で拒否する）。
  local repo17 rc17=0
  repo17="$tmp/repo17"
  _egt_init_repo "$repo17"
  _egt_seed_main_hook "$repo17"
  ( cd "$repo17" && git branch -q feature && git symbolic-ref refs/heads/main refs/heads/feature ) >/dev/null 2>&1
  ensure_one "$repo17" || rc17=$?
  got="$(git -C "$repo17" config --get core.hooksPath 2>/dev/null)"
  if [ "$rc17" -ne 0 ] && [ -z "$got" ]; then
    echo "  [PASS] ケース17: mainがシンボリック参照なら導入を止める"; pass=$((pass + 1))
  else
    echo "  [FAIL] ケース17: mainがシンボリック参照なら導入を止める（rc=${rc17} got=${got}）" >&2; fail=$((fail + 1))
  fi

  echo "自己テスト結果: 合格 ${pass} 件 / 不合格 ${fail} 件"
  [ "$fail" -eq 0 ]
}

main "$@"
