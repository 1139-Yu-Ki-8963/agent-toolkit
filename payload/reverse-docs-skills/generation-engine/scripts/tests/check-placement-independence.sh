#!/usr/bin/env bash
# check-placement-independence.sh — 自己テストの結果が置き場所によって変わらないことを確かめる
#
# 背景（docs/tasks/配布先で自己テストが通るようにする指示書.md）:
#   validate-manifest.sh は、マニフェストの相対sourceDirを解決する基準（対象リポジトリの
#   ルート）を、所在ディレクトリから上へ.git祖先を探して求めていた。配布物（このリポジトリ）が
#   公開リポジトリや対象プロジェクトの中へ一区画として埋め込まれると、埋め込み先自体には
#   配布物自身の.gitが無いため、探索が配布物の境界を越えて外側のリポジトリへ到達し、
#   実物の見本マニフェスト（sourceDirがリポジトリのルート起点）の解決に失敗していた
#   （実測: 独立配置は終了コード0、埋め込み配置は終了コード1）。
#   対策として、配布物の境界目印（generation-engine/DESIGN.md）を.gitと並ぶ停止条件に
#   加えた。本スクリプトは、この性質が退行していないかを実際の2つの置き方で確かめ続ける。
#
# 目的:
#   置き方1（独立したリポジトリとしての配置。generation-engine一式が自身の.gitの直下にある）と
#   置き方2（上位にリポジトリを持つ配置。外側の別リポジトリの中へ.gitを持たないまま
#   埋め込まれる）の両方で、実物の見本マニフェスト
#   （generation-engine/samples/docs/manifests/screen-manifest.json）をvalidate-manifest.shで
#   検証し、終了コードが両方とも0で一致することを確かめる。一致しなければ不合格とする。
#
# 使い方:
#   check-placement-independence.sh [<リポジトリルート>]
#   check-placement-independence.sh --self-test
#
# 保守責任者: 人手（ユーザー）。generation-engine/DESIGN.md を境界目印から変更する場合は
# 本ファイルと generation-engine/scripts/unit-list/validate-manifest.sh を同時に更新する。
# macOS bash 3.2 互換。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# generation-engine一式を$dst直下へ複製する。引数: repo（リポジトリルート）、dst（複製先の親）
copy_generation_engine() {
  local repo="$1" dst="$2"
  mkdir -p "$dst"
  cp -R "$repo/generation-engine" "$dst/generation-engine"
  # 見本のsourceDirは samples 起点なので、配置独立性を調べる複製では配布物
  # ルート起点へ正規化する。これにより境界目印を外したときだけ埋め込み配置が失敗する。
  jq '.sourceDir = "generation-engine/samples/" + .sourceDir' \
    "$dst/generation-engine/samples/docs/manifests/screen-manifest.json" \
    > "$dst/generation-engine/samples/docs/manifests/screen-manifest.json.next"
  mv "$dst/generation-engine/samples/docs/manifests/screen-manifest.json.next" \
    "$dst/generation-engine/samples/docs/manifests/screen-manifest.json"
}

# 見本マニフェストを$placement配下のvalidate-manifest.shで検証する。
# 引数: placement（generation-engineを直下に持つディレクトリ）
# 複製時にsourceDirを配布物ルート起点へ正規化しているため、境界目印または.git祖先から
# 自動解決させる。ここで--repo-rootを明示すると、境界目印を外した退行ケースでも
# 同じ基準を注入してしまい、配置差を検出できなくなる。
# 標準出力: 検証コマンドの出力。戻り値: 検証コマンドの終了コード。
run_gold_validation() {
  local placement="$1"
  (
    cd /tmp 2>/dev/null || cd "$placement" || exit 1
    bash "$placement/generation-engine/scripts/unit-list/validate-manifest.sh" \
      "$placement/generation-engine/samples/docs/manifests/screen-manifest.json" \
      --unit-kind screen
  )
}

# 置き方1（独立したリポジトリ）と置き方2（上位にリポジトリを持つ配置）の両方を
# $tmp配下に用意し、見本マニフェストの検証結果を比較する。
# 引数: repo（複製元のリポジトリルート）、tmp（作業用の一時ディレクトリ）
# 標準出力: 判定行。戻り値: 両方とも終了コード0で一致すれば0、それ以外は1。
compare_placements() {
  local repo="$1" tmp="$2"
  local standalone outer embedded

  # 置き方1: 独立したリポジトリとしての配置
  standalone="$tmp/standalone"
  copy_generation_engine "$repo" "$standalone"
  ( cd "$standalone" && git init -q ) || true

  # 置き方2: 上位にリポジトリを持つ配置（複製自体には.gitを持たせない）
  outer="$tmp/outer"
  mkdir -p "$outer"
  ( cd "$outer" && git init -q ) || true
  embedded="$outer/payload"
  copy_generation_engine "$repo" "$embedded"

  local out1 rc1 out2 rc2
  out1="$(run_gold_validation "$standalone" 2>&1)"; rc1=$?
  out2="$(run_gold_validation "$embedded" 2>&1)"; rc2=$?

  if [ "$rc1" -ne 0 ] && [ "$rc2" -ne 0 ]; then
    echo "FAIL: 両方の置き方で終了コードが0以外（独立配置=${rc1} / 上位リポジトリを持つ配置=${rc2}）"
    return 1
  fi
  if [ "$rc1" -ne "$rc2" ]; then
    echo "FAIL: 置き方によって結果が食い違う（独立配置=終了コード${rc1} / 上位リポジトリを持つ配置=終了コード${rc2}）"
    if [ "$rc1" -ne 0 ]; then printf '%s\n' "$out1" | grep '^\[FAIL\]'; fi
    if [ "$rc2" -ne 0 ]; then printf '%s\n' "$out2" | grep '^\[FAIL\]'; fi
    return 1
  fi
  if [ "$rc1" -ne 0 ]; then
    echo "FAIL: 両方の置き方で終了コード${rc1}（期待値0）"
    printf '%s\n' "$out1" | grep '^\[FAIL\]'
    return 1
  fi
  echo "PASS: 両方の置き方で終了コード0（独立したリポジトリとしての配置・上位にリポジトリを持つ配置）"
  return 0
}

self_test() {
  local tmp pass=0 fail=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-placement-independence-self-test.XXXXXX")" || {
    echo "self-test: 一時ディレクトリを作成できない" >&2
    return 1
  }
  tmp="$(cd "$tmp" && pwd)"
  trap 'rm -rf "$tmp"' EXIT

  assert_true() {
    local name="$1" ok="$2"
    if [ "$ok" -eq 0 ]; then
      echo "  [PASS] $name"
      pass=$((pass + 1))
    else
      echo "  [FAIL] $name"
      fail=$((fail + 1))
    fi
  }

  local realRoot
  realRoot="$(cd "$SCRIPT_DIR/../../.." && pwd)"

  # ケース1: 現状のリポジトリで、両方の置き方の比較がPASSすること
  local case1dir out1
  case1dir="$tmp/case1"
  mkdir -p "$case1dir"
  out1="$(compare_placements "$realRoot" "$case1dir")"
  if printf '%s\n' "$out1" | grep -q '^PASS:'; then
    assert_true "現状のリポジトリで両方の置き方がPASS" 0
  else
    assert_true "現状のリポジトリで両方の置き方がPASS" 1
    printf '%s\n' "$out1" | sed 's/^/    /'
  fi
  rm -rf "$case1dir"

  # ケース2: 境界目印の停止条件を外した複製では、上位にリポジトリを持つ配置だけが
  # 不合格になり、比較そのものが不合格（食い違い検出）を返すこと（退行検出の確認）
  local case2repo case2dir
  case2repo="$tmp/case2-repo"
  copy_generation_engine "$realRoot" "$case2repo"
  local target="$case2repo/generation-engine/scripts/unit-list/validate-manifest.sh"
  local old_cond='[ -e "$probe/.git" ] || [ -f "$probe/generation-engine/DESIGN.md" ]'
  local new_cond='[ -e "$probe/.git" ]'
  # 環境変数経由でperlへ渡す。bashの二重引用符展開とperlの引用符解釈が
  # 衝突しないよう、perl本体は単一引用符で囲みシェル展開を一切させない。
  OLD_COND="$old_cond" NEW_COND="$new_cond" perl -0777 -pi -e '
    my $old = $ENV{OLD_COND};
    my $new = $ENV{NEW_COND};
    s/\Q$old\E/$new/;
  ' "$target"
  if grep -qF "$new_cond" "$target" && ! grep -qF "$old_cond" "$target"; then
    assert_true "退行の再現-境界目印の停止条件を除去できた" 0
  else
    assert_true "退行の再現-境界目印の停止条件を除去できた" 1
  fi

  case2dir="$tmp/case2"
  mkdir -p "$case2dir"
  local out2
  out2="$(compare_placements "$case2repo" "$case2dir")"
  if printf '%s\n' "$out2" | grep -q '^FAIL:'; then
    assert_true "境界目印を外した複製では食い違いをFAILで検出する" 0
  else
    assert_true "境界目印を外した複製では食い違いをFAILで検出する" 1
    printf '%s\n' "$out2" | sed 's/^/    /'
  fi
  rm -rf "$case2dir" "$case2repo"

  rm -rf "$tmp"
  trap - EXIT
  echo "実行 $((pass + fail)) 件 / 成功 $pass 件 / 失敗 $fail 件"
  [ "$fail" -eq 0 ]
}

usage() {
  cat <<'EOS'
使い方: check-placement-independence.sh [<リポジトリルート>]
        check-placement-independence.sh --self-test
EOS
}

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
  fi

  local root="${1:-}"
  if [ -z "$root" ]; then
    root="$(cd "$SCRIPT_DIR/../../.." && pwd)"
  fi

  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-placement-independence.XXXXXX")" || {
    echo "一時ディレクトリを作成できない" >&2
    exit 1
  }
  local rc=0
  compare_placements "$root" "$tmp" || rc=1
  rm -rf "$tmp"
  exit "$rc"
}

main "$@"
