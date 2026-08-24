#!/usr/bin/env bash
# check-payload-safety.sh — 公開リポジトリの payload/reverse-docs-skills に、配ってはならないもの
#   （実行環境の固有パス・GitHubのアカウント名・除外すべき名前のフォルダ・
#   除外すべき名前の本文への言及）が含まれていないかを検査する。
#
# 使い方:
#   bash docs/scripts/check-payload-safety.sh
#   bash docs/scripts/check-payload-safety.sh --self-test
#
# 必要性: 公開リポジトリの payload/reverse-docs-skills に、配る必要の無いもの
#   （作業の記録・セッションのプロンプト・実行環境の固有パス・GitHubのアカウント名）が
#   実際に混入した実測がある。除外名の追加漏れや同期エンジンの挙動変化により、
#   同種の混入は今後も起こりうる。同期の前後どちらでも繰り返し確認できる、
#   決定的なスクリプトとして1本に閉じる必要がある。
#
#   さらに、除外の定義（.names）はフォルダ・ファイルの実在は防ぐが、
#   その名前を「本文の中で言及する」ことまでは防げない。実際に、除外済みの
#   非公開スキルが1件あり、そのスキル本体はフォルダごと除外されていた
#   一方、その名前と用途が複数件の公開ファイルの本文に残っていた実測がある
#   （スキル本体は無いのに、無いはずのものの存在と役割だけが読み取れる状態）。
#   check_no_forbidden_mentions はこの穴を、除外名を識別子・パスの1トークン
#   として本文から検出することで塞ぐ。除外名そのものは .names 定義ファイルに
#   だけ置き、本ファイルのソースへ直接書き込まない（本ファイル自身が
#   payload 経由で配布されるため、直接書くと自分自身を不合格にする）。
#
# 代替案を採用しなかった理由:
#   - Bash ツール直叩き: 公開のたびに grep を手で組み立てて確認すると、検出パターンや
#     走査範囲が実行のたびにぶれる
#   - 既存 check-publish-sync-gate.sh への機能追加: あちらは正本と origin/main の内容が
#     一致しているか（乖離の有無）を見る検査であり、内容そのものに機密・固有情報が
#     混入していないかという観点とは判定式が異なる
#   - 既存 Makefile ターゲット拡張・package.json scripts 追加: このリポジトリは
#     どちらも持たない
#
# 保守責任者: 人手（ユーザー）。検出パターンや除外すべき名前の既定値を変更する場合は、
#   本スクリプトと ~/agent-home/state/payload-forbidden-content.json と
#   .claude/rules/always/publish/complete/rule.md の設計判断節を同時に更新する。
#
# 廃棄条件: 公開先リポジトリへの同期運用自体を廃止した時、または混入検査を
#   同期エンジン（sync-payload.mjs の --check-artifacts）が標準で兼ねるようになった時。

set -uo pipefail

DEFAULT_TARGET="$HOME/github-public/agent-toolkit/payload/reverse-docs-skills"
TARGET="${PAYLOAD_SAFETY_TARGET:-$DEFAULT_TARGET}"
DEFAULT_NAMES_FILE="$HOME/agent-home/state/payload-forbidden-content.json"
NAMES_FILE="${PAYLOAD_SAFETY_FORBIDDEN_NAMES_FILE:-$DEFAULT_NAMES_FILE}"

# 検出パターンは、本ファイル自身が payload 経由で配布されたときに自分自身の
# ソースコードへ誤って一致しないよう、文字クラス（1文字だけの角括弧）を挟んで
# 連続する文字列として保持しない。角括弧は正規表現としては単一文字にしか
# マッチしないため、判定の挙動そのものは変わらない。
#
# 実行環境の固有パスは、汎用の「/Users/」という語ではなく、実行環境のユーザー名
# （MacPro）まで含めた具体的な絶対パスに絞る。汎用の「/Users/」だけで走査すると、
# 既存の匿名パス検出コード自身（他プロジェクトの絶対パス検出用の正規表現・
# アサーション・glob パターン等）まで誤検出してしまうことを実測で確認したため。
HOME_PATH_PATTERN='/Users/MacPr[o]'
GH_ACCOUNT_PATTERN='1139-Yu-K''i-896[3]'

unknown_missing_target() {
  local target="$1"
  echo "[UNKNOWN] 検査対象が見つからないため判定できません: ${target}（同期をまだ一度も実行していない可能性があります）" >&2
  return 2
}

default_forbidden_names() {
  printf '%s\n' "work-records" "session-prompts"
}

forbidden_names() {
  local file="$1"
  if [ -f "$file" ] && command -v jq >/dev/null 2>&1; then
    local names
    names="$(jq -r '.names[]? // empty' "$file" 2>/dev/null || true)"
    if [ -n "$names" ]; then
      printf '%s\n' "$names"
      return 0
    fi
  fi
  default_forbidden_names
}

check_no_local_paths() {
  local target="$1"
  local hits
  hits="$(grep -rnE "$HOME_PATH_PATTERN" "$target" 2>/dev/null || true)"
  if [ -n "$hits" ]; then
    echo "[FAIL] 実行環境の固有パスが含まれています:"
    printf '%s\n' "$hits" | sed 's/^/  /'
    return 1
  fi
  return 0
}

check_no_account_name() {
  local target="$1"
  local hits
  hits="$(grep -rnE "$GH_ACCOUNT_PATTERN" "$target" 2>/dev/null || true)"
  if [ -n "$hits" ]; then
    echo "[FAIL] GitHubのアカウント名が含まれています:"
    printf '%s\n' "$hits" | sed 's/^/  /'
    return 1
  fi
  return 0
}

check_no_forbidden_dirs() {
  local target="$1" names_file="$2"
  local failed=0 name hits
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    hits="$(find "$target" -depth -name "$name" 2>/dev/null || true)"
    if [ -n "$hits" ]; then
      echo "[FAIL] 除外すべき名前のフォルダ・ファイルが実在します: ${name}"
      printf '%s\n' "$hits" | sed 's/^/  /'
      failed=1
    fi
  done < <(forbidden_names "$names_file")
  return "$failed"
}

# 除外すべき名前を正規表現の特殊文字として使っても安全な形へエスケープする。
# バックスラッシュ→他の特殊文字の順で置換する（先に他を置換するとバック
# スラッシュの二重エスケープが混ざるため）。
escape_ere() {
  printf '%s' "$1" \
    | sed -e 's/\\/\\\\/g' \
          -e 's/\./\\./g' \
          -e 's/\*/\\*/g' \
          -e 's/\^/\\^/g' \
          -e 's/\$/\\$/g' \
          -e 's/\[/\\[/g' \
          -e 's/\]/\\]/g' \
          -e 's/(/\\(/g' \
          -e 's/)/\\)/g' \
          -e 's/+/\\+/g' \
          -e 's/?/\\?/g' \
          -e 's/{/\\{/g' \
          -e 's/}/\\}/g' \
          -e 's/|/\\|/g'
}

# 名前が識別子・パスの1トークンとして本文に現れているかを検査する。
# 前後がASCII英数字・ハイフン・アンダースコアでない（＝行頭/行末を含む）
# 場合だけ一致とみなす。これにより surveying-local-environment のような、
# 除外名を部分文字列として含むだけの正当な複合語を誤検出しない。
check_no_forbidden_mentions() {
  local target="$1" names_file="$2"
  local failed=0 name escaped pattern hits examined=0
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    examined=$((examined + 1))
    escaped="$(escape_ere "$name")"
    pattern="(^|[^A-Za-z0-9_-])${escaped}([^A-Za-z0-9_-]|\$)"
    hits="$(grep -rnE "$pattern" "$target" 2>/dev/null || true)"
    if [ -n "$hits" ]; then
      echo "[FAIL] 除外すべき名前が本文に含まれています: ${name}"
      printf '%s\n' "$hits" | sed 's/^/  /'
      failed=1
    fi
  done < <(forbidden_names "$names_file")
  echo "[INFO] 除外名 ${examined} 件すべてについて本文の言及を調べました" >&2
  FORBIDDEN_MENTIONS_EXAMINED="$examined"
  return "$failed"
}

run_check() {
  local target="$1" names_file="$2"
  [ -d "$target" ] || { unknown_missing_target "$target"; return 2; }

  local failed=0
  FORBIDDEN_MENTIONS_EXAMINED=0

  check_no_local_paths "$target" || failed=1
  check_no_account_name "$target" || failed=1
  check_no_forbidden_dirs "$target" "$names_file" || failed=1
  check_no_forbidden_mentions "$target" "$names_file" || failed=1

  if [ "$failed" -eq 0 ]; then
    echo "[PASS] payloadの安全性検査（4件。うち本文の言及検査は除外名${FORBIDDEN_MENTIONS_EXAMINED}件すべてを調査）に合格しました: ${target}"
    return 0
  fi
  return 1
}

record_self_test() {
  local name="$1" expected="$2"
  shift 2
  total=$((total + 1))
  local actual
  set +e
  "$@" >/dev/null 2>&1
  actual=$?
  set -e
  if [ "$actual" -eq "$expected" ]; then
    echo "  [PASS] ${name}"
    pass=$((pass + 1))
  else
    echo "  [FAIL] ${name}（終了コード=${actual}、期待=${expected}）"
    fail=$((fail + 1))
  fi
}

# 終了コードではなく出力内容を検証する（除外名の調査件数が報告されているか等）。
record_self_test_output() {
  local name="$1" expected_substr="$2"
  shift 2
  total=$((total + 1))
  local out
  out="$("$@" 2>&1)"
  if printf '%s' "$out" | grep -qF "$expected_substr"; then
    echo "  [PASS] ${name}"
    pass=$((pass + 1))
  else
    echo "  [FAIL] ${name}（出力に「${expected_substr}」を含まない）"
    fail=$((fail + 1))
  fi
}

run_self_test() {
  local pass=0 fail=0 total=0
  local tmp=""
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-payload-safety.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）"
    exit 2
  fi
  trap 'if [ -n "${tmp:-}" ]; then rm -rf "$tmp"; fi' EXIT

  # ケース1: 正常系（違反なし）
  mkdir -p "$tmp/clean/docs"
  printf 'これは正常なファイルです。\n' > "$tmp/clean/docs/ok.md"

  # ケース2: 実行環境の固有パスを含む。
  # フィクスチャの文字列は実行時の連結で組み立て、本ファイルのソース上に
  # 連続した該当文字列を残さない（本ファイル自身が将来 payload 経由で
  # 配布されたときに自己一致しないようにするため）。
  mkdir -p "$tmp/local-path/docs"
  local home_like
  home_like="/Users/MacPr""o/example/project/file.txt"
  printf 'path: %s\n' "$home_like" > "$tmp/local-path/docs/bad.md"

  # ケース2b: 汎用の /Users/ だけを含み、実行環境のユーザー名を伴わない場合は
  # 誤検出しないことを確認する（既存の匿名パス検出コードとの区別）。
  mkdir -p "$tmp/generic-users-path/docs"
  local generic_users_like
  generic_users_like="/Users/example""/project/file.txt"
  printf 'path: %s\n' "$generic_users_like" > "$tmp/generic-users-path/docs/ok.md"

  # ケース3: GitHubのアカウント名を含む
  mkdir -p "$tmp/account/docs"
  local account_like
  account_like="1139-Yu-K""i-8963"
  printf 'author: %s\n' "$account_like" > "$tmp/account/docs/bad.md"

  # ケース4: 除外すべきフォルダが実在する
  mkdir -p "$tmp/forbidden-dir/docs/tasks/work-records"
  printf 'dummy\n' > "$tmp/forbidden-dir/docs/tasks/work-records/note.md"

  # ケース6: 除外すべき名前がフォルダとしては実在しないが、本文の中で
  # 独立した識別子として言及されている（本課題の主眼）。
  mkdir -p "$tmp/mention/docs"
  printf 'この節は work-records の使い方を説明する。\n' > "$tmp/mention/docs/guide.md"

  # ケース7: 除外名がより長い複合語の一部として現れるだけの正当な語は
  # 誤検出しない（例: surveying-local-environment のようなスキル名）。
  mkdir -p "$tmp/substring-only/docs"
  printf 'presession-promptsy という語はどの除外名とも一致しない。\n' \
    > "$tmp/substring-only/docs/ok.md"

  # ケース5: 対象ディレクトリが存在しない
  local missing_target="$tmp/does-not-exist"

  # このマシンに ~/agent-home が無い環境でも自己完結できるよう、
  # 自前の除外名定義ファイルを用意する
  local names_file="$tmp/forbidden-names.json"
  printf '{"names":["work-records","session-prompts"]}\n' > "$names_file"

  record_self_test "正常系は合格" 0 run_check "$tmp/clean" "$names_file"
  record_self_test "固有パスの混入を検出" 1 run_check "$tmp/local-path" "$names_file"
  record_self_test "汎用の/Users/だけでは誤検出しない" 0 run_check "$tmp/generic-users-path" "$names_file"
  record_self_test "アカウント名の混入を検出" 1 run_check "$tmp/account" "$names_file"
  record_self_test "除外フォルダの残存を検出" 1 run_check "$tmp/forbidden-dir" "$names_file"
  record_self_test "対象不在を判定不能として区別" 2 run_check "$missing_target" "$names_file"
  record_self_test "本文の言及を検出" 1 run_check "$tmp/mention" "$names_file"
  record_self_test "部分文字列だけの複合語は誤検出しない" 0 run_check "$tmp/substring-only" "$names_file"
  record_self_test_output "除外名の調査件数を報告する" "除外名 2 件すべて" \
    run_check "$tmp/clean" "$names_file"

  echo "実行 ${total} 件 / 成功 ${pass} 件 / 失敗 ${fail} 件"
  local result=0
  [ "$fail" -eq 0 ] || result=1
  rm -rf "$tmp"
  tmp=""
  trap - EXIT
  return "$result"
}

case "${1:-}" in
  "") run_check "$TARGET" "$NAMES_FILE"; exit $? ;;
  --self-test) run_self_test; exit $? ;;
  *) echo "不明な引数: $1" >&2; exit 1 ;;
esac
