#!/usr/bin/env bash
# check-commit-issue-trace.sh — コミットから課題キーへの追跡漏れを事後検出する
#
# 目的:
#   コミット-課題対応規約（.claude/rules/always/tasks/commit-issue-trace/rule.md）は
#   PreToolUse(Bash) フックによる commit 時点の block を定めるが、実測により、
#   プロジェクト固有の <repo>/.claude/settings.json に登録した PreToolUse(Bash) フックは
#   サブエージェント経由の git commit 実行では発火しないことが判明した
#   （グローバル設定側の同種フックは発火する）。フックが呼ばれていないだけであり、
#   判定ロジック自体（check-commit-issue-trace.sh の judge 関数）は正しく動作する。
#   本スクリプトは、コミット時点で止める代わりに、直近のコミット履歴を事後に
#   走査して同じ判定を再現し、違反を発見する。第1層の機械検証
#   （generation-engine/scripts/verification/run-layer-machine-checks.sh）が
#   --self-test の有無で動的に対象を集めるため、本スクリプトを
#   generation-engine/scripts/tests/ 配下へ置くことで自動的に拾われる。
#
# 使い方:
#   check-commit-issue-trace.sh [<リポジトリのパス>] [--max-commits <件数>]
#   check-commit-issue-trace.sh --self-test
#
# 走査範囲（既定200件の理由）:
#   直近200コミット（git log --format=%H -n 200 相当）を対象にする。
#   このリポジトリでは1日で345件のコミットが記録された実測があり、
#   200件は主要な作業期間をカバーしつつ、過去の全履歴を無制限に遡ると
#   実行が重くなることを避けるための値である。本スクリプトは git log・
#   git show・git diff-tree によるメタデータ・ファイル内容の解析のみを
#   行い、他スクリプトの --self-test を呼び出す重い処理を含まないため、
#   200件でも第1層の集約が持つ1本あたりの時間上限（既定120秒）に収まる
#   見込みである。
#
# 免除・対象外の条件（規約と同一の判定基準）:
#   - コミットメッセージ（件名+本文）が「【マージ】」または「【同期】」を
#     含む場合はそのコミット全体を免除する
#   - コミットが変更したファイルのうち docs/tasks/ 配下の .md 以外は対象外
#   - 対象ファイルの当該コミット時点の内容（削除の場合は親コミット時点の
#     内容へフォールバック）に `**元の指摘**:` 行が無ければ対象外
#   - その行の値が「なし」なら対象外（要求無し）
#   - 値が課題キー（1-NN の形。カンマ区切りで複数可）を持つ場合、
#     いずれか1つがコミットメッセージに含まれていなければ違反とする
#
# 判定不能の扱い:
#   --self-test 実行時に mktemp が失敗した場合、対象の合否とは無関係に
#   [UNKNOWN] を出力し終了コード2で終わる
#   （.claude/rules/always/verification/indeterminate-result/rule.md の規約）。
#
# 終了コード: 違反が1件以上あれば1。無ければ0。--self-test は失敗ケースが
#   1件以上あれば1、mktemp 失敗時は2。
#
# 保守責任者: 人手（ユーザー）。`**元の指摘**:` 行の形式・免除接頭辞
#   （【マージ】・【同期】）を変更する場合は、本ファイルと
#   .claude/rules/always/tasks/commit-issue-trace/check-commit-issue-trace.sh と
#   rule.md を同時に更新する。
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================
# 判定ロジック（フック本体の判定と同一の基準を再実装する）
# ============================================================

# ファイル内容（標準入力）から `**元の指摘**:` 行の値を取り出す。
# 行が無ければ空文字を返す（= このファイルは指示書形式ではないため対象外）。
extract_original_issue_value() {
  LC_ALL=C grep -m1 '^\*\*元の指摘\*\*:' | sed -e 's/^\*\*元の指摘\*\*:[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# 元の指摘の値からキー一覧を1行1件で出力する。値が「なし」または空なら何も出力しない。
extract_keys() {
  local value="$1"
  value="$(printf '%s' "${value}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  if [ -z "${value}" ] || [ "${value}" = "なし" ]; then
    return 0
  fi
  printf '%s\n' "${value}" | tr ',' '\n' | while IFS= read -r k; do
    k="$(printf '%s' "${k}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -n "${k}" ] && printf '%s\n' "${k}"
  done
}

# コミットメッセージ（件名+本文）に免除接頭辞（【マージ】【同期】）が含まれるか。
has_exempt_prefix() {
  local msg="$1"
  case "${msg}" in
    *'【マージ】'*|*'【同期】'*) return 0 ;;
    *) return 1 ;;
  esac
}

# ============================================================
# 走査本体
# ============================================================

# 引数: repo（リポジトリのパス。相対でも可） max（走査するコミット数上限）
# 標準出力: 違反があれば「<短縮ハッシュ> <ファイル> (要求: key1/key2) メッセージ先頭: <件名>」を1行1件、
#           末尾に「検査対象コミット <N> 件 / 違反 <M> 件」の集計行
# 終了コード: 0=違反なし / 1=違反あり
run_scan() {
  local repo="$1" max="$2"
  local toplevel

  toplevel="$(git -C "${repo}" rev-parse --show-toplevel 2>/dev/null)"
  if [ -z "${toplevel}" ]; then
    echo "対象外: ${repo} は git リポジトリではありません" >&2
    return 0
  fi
  if [ ! -d "${toplevel}/docs/tasks" ]; then
    echo "対象外: ${toplevel} は docs/tasks/ を持ちません" >&2
    return 0
  fi

  local hashes
  hashes="$(git -c core.quotepath=false -C "${toplevel}" log --format=%H -n "${max}" 2>/dev/null)"
  if [ -z "${hashes}" ]; then
    echo "対象コミットが0件です"
    return 0
  fi

  local violations="" checked=0 hits=0

  while IFS= read -r hash; do
    [ -z "${hash}" ] && continue
    checked=$((checked + 1))

    local msg
    msg="$(git -C "${toplevel}" log -1 --format=%B "${hash}" 2>/dev/null)"

    if has_exempt_prefix "${msg}"; then
      continue
    fi

    local files
    files="$(git -c core.quotepath=false -C "${toplevel}" diff-tree --no-commit-id --name-only -r "${hash}" -- 'docs/tasks/*.md' 2>/dev/null)"
    [ -z "${files}" ] && continue

    while IFS= read -r f; do
      [ -z "${f}" ] && continue

      local content
      content="$(git -C "${toplevel}" show "${hash}:${f}" 2>/dev/null)"
      if [ -z "${content}" ]; then
        content="$(git -C "${toplevel}" show "${hash}^:${f}" 2>/dev/null)"
      fi
      [ -z "${content}" ] && continue

      local value keys found key_hit
      value="$(printf '%s\n' "${content}" | extract_original_issue_value)"
      [ -z "${value}" ] && continue

      keys="$(extract_keys "${value}")"
      [ -z "${keys}" ] && continue

      found=0
      while IFS= read -r key_hit; do
        [ -z "${key_hit}" ] && continue
        case "${msg}" in
          *"${key_hit}"*) found=1; break ;;
        esac
      done <<KEYS
${keys}
KEYS

      if [ "${found}" -eq 0 ]; then
        hits=$((hits + 1))
        local short subject req
        short="$(git -C "${toplevel}" rev-parse --short "${hash}" 2>/dev/null)"
        subject="$(printf '%s\n' "${msg}" | head -n1)"
        req="$(printf '%s' "${keys}" | tr '\n' '/' | sed -e 's#/$##')"
        violations="${violations}${short} ${f} (要求: ${req}) メッセージ先頭: ${subject}
"
      fi
    done <<FILES
${files}
FILES
  done <<HASHES
${hashes}
HASHES

  if [ "${hits}" -eq 0 ]; then
    echo "検査対象コミット ${checked} 件 / 違反 0 件"
    return 0
  fi

  printf '%s' "${violations}"
  echo "検査対象コミット ${checked} 件 / 違反 ${hits} 件"
  return 1
}

# ============================================================
# self-test（使い捨てのgitリポジトリで判定を検証する）
# ============================================================

run_self_test() {
  local root pass_count fail_count
  pass_count=0
  fail_count=0

  # mktemp の失敗は「判定不能」として区別する（不合格と誤読させない）。
  if ! root="$(mktemp -d 2>/dev/null)" || [ -z "${root}" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため自己テストを判定できません（mktemp -d が一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）"
    return 2
  fi
  # 物理パスへ解決する（macOS の /tmp -> /private/tmp のような symlink 経由の
  # パス不一致を避けるため）。
  root="$(cd "${root}" && pwd)"
  trap 'rm -rf "${root}"' RETURN

  report() {
    if [ "$2" = "ok" ]; then
      echo "PASS: $1"
      pass_count=$((pass_count + 1))
    else
      echo "FAIL: $1"
      fail_count=$((fail_count + 1))
    fi
  }

  git_quiet() {
    git -c user.name=test -c user.email=test@example.com "$@" >/dev/null 2>&1
  }

  local repo="${root}/repo"
  mkdir -p "${repo}/docs/tasks"
  git_quiet -C "${repo}" init
  git_quiet -C "${repo}" config core.quotepath false
  echo base > "${repo}/README.md"
  git_quiet -C "${repo}" add -A
  git_quiet -C "${repo}" commit -m init

  # --- ケース1: 課題キー有りの指示書 + メッセージに正しいキー有り → 違反にならない ---
  printf '**元の指摘**: 1-99\n' > "${repo}/docs/tasks/対象1指示書.md"
  git_quiet -C "${repo}" add -A
  git_quiet -C "${repo}" commit -m "1-99対応"

  # --- ケース2: 課題キー有りの指示書 + メッセージにキー無し → 違反として検出される ---
  printf '**元の指摘**: 1-99\n本文\n' > "${repo}/docs/tasks/対象2指示書.md"
  git_quiet -C "${repo}" add -A
  git_quiet -C "${repo}" commit -m "課題キーなしのコミット"

  # --- ケース3: 元の指摘=なし の指示書 + メッセージにキー無し → 対象外で違反にならない ---
  printf '**元の指摘**: なし\n' > "${repo}/docs/tasks/対象3指示書.md"
  git_quiet -C "${repo}" add -A
  git_quiet -C "${repo}" commit -m "対象外の指示書変更"

  # --- ケース4: 【マージ】接頭辞のコミット + メッセージにキー無し → 免除されて違反にならない ---
  printf '**元の指摘**: 1-99\n' > "${repo}/docs/tasks/対象4指示書.md"
  git_quiet -C "${repo}" add -A
  git_quiet -C "${repo}" commit -m "【マージ】取り込み"

  local out
  out="$(run_scan "${repo}" 200)"

  if printf '%s\n' "${out}" | grep -q '対象2指示書.md'; then
    report "ケース2: 課題キーなしのコミットが違反として検出される" ok
  else
    report "ケース2: 課題キーなしのコミットが違反として検出される" ng
  fi

  if ! printf '%s\n' "${out}" | grep -q '対象1指示書.md'; then
    report "ケース1: 課題キー記載済みは違反にならない" ok
  else
    report "ケース1: 課題キー記載済みは違反にならない" ng
  fi

  if ! printf '%s\n' "${out}" | grep -q '対象3指示書.md'; then
    report "ケース3: 元の指摘なしは対象外" ok
  else
    report "ケース3: 元の指摘なしは対象外" ng
  fi

  if ! printf '%s\n' "${out}" | grep -q '対象4指示書.md'; then
    report "ケース4: 【マージ】接頭辞は免除される" ok
  else
    report "ケース4: 【マージ】接頭辞は免除される" ng
  fi

  echo "----------------------------------------"
  echo "self-test: ${pass_count} PASS, ${fail_count} FAIL"
  [ "${fail_count}" -eq 0 ] && return 0
  return 1
}

# ============================================================
# エントリポイント
# ============================================================

usage() {
  cat <<'USAGE_EOF'
使い方: check-commit-issue-trace.sh [<リポジトリのパス>] [--max-commits <件数>]
        check-commit-issue-trace.sh --self-test
USAGE_EOF
}

main() {
  case "${1:-}" in
    --self-test)
      run_self_test
      exit $?
      ;;
    -h|--help)
      usage
      exit 0
      ;;
  esac

  local repo="" max=200
  while [ $# -gt 0 ]; do
    case "$1" in
      --max-commits)
        max="${2:-200}"
        shift 2
        ;;
      *)
        repo="$1"
        shift
        ;;
    esac
  done

  if [ -z "${repo}" ]; then
    repo="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
  fi

  run_scan "${repo}" "${max}"
  exit $?
}

main "$@"
