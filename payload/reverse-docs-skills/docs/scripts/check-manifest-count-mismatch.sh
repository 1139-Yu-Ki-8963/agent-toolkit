#!/usr/bin/env bash
# check-manifest-count-mismatch.sh — 単位フォルダの数と一覧の元データへ組み立てられた件数の
# 食い違いが検知されるかを確かめる（改善課題1-254）。
#
# 背景: 設計文書からマニフェストを組み立てる処理
# (generation-engine/scripts/portal-input/build-manifests-from-docs.sh) は、単位フォルダが
# 実在するのに一覧の元データが0件になっても、従来は終了コード0のまま正常終了していた。
# 0件であることは不合格として現れないため、前付けの不足やファイル名の不一致が沈黙のまま
# 通っていた。本検査は、単位フォルダの数と組み立てられた件数の突き合わせが実際に働くかを
# 確かめる。
#
# 判定の式を指示書の表へ直接書けないためスクリプトへ切り出した。
# （.claude/rules/always/tasks/instruction-format/rule.md の
# check-broken-verdict-rows.sh の設計判断と同じ理由: 式に含まれる縦棒を
# 片付けの判定器が列の区切りと読み違え、判定行そのものを壊す）
#
# 使い方:
#   bash docs/scripts/check-manifest-count-mismatch.sh             食い違い検知が働くかを見る
#   bash docs/scripts/check-manifest-count-mismatch.sh --self-test このスクリプト自身の判定を確かめる
#
# 対象: generation-engine/scripts/portal-input/build-manifests-from-docs.sh
#
# 一時ファイルの置き場は明示する（引数なしの mktemp は既定の置き場へ書こうとして
# 失敗する環境があるため。実測 2026-08-24）。diff・comm へプロセス置換は渡さない。
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_DEFAULT="${REPO_ROOT}/generation-engine/scripts/portal-input/build-manifests-from-docs.sh"

# 単位フォルダを2つ用意し、片方だけ設計文書を実在させたプロジェクトルートを作る。
# 折り返し値: 作った一時ディレクトリのプロジェクトルート(標準出力へ1行)。
make_mismatch_project() {
  local base="$1" root
  root="$base/mismatch-project"
  mkdir -p "$root/docs/design/features/feature-with-doc" \
    "$root/docs/design/features/feature-without-doc"
  cat > "$root/docs/design/features/feature-with-doc/機能設計書.md" <<'EOF'
---
feature_key: with-doc
feature_id: feature-with-doc
category: 会員管理
source_ref: src/features/with_doc.py
unit_kind: feature
---

# 設計書ありの機能設計書
EOF
  # feature-without-doc は単位フォルダとして実在するが機能設計書.mdを欠く
  # (前付けの不足・ファイル名の不一致など、設計書が実在するのに一覧の元データへ
  # 反映されない事象全般の代表として、ここでは意図的にファイル自体を欠かせる)。
  printf '%s\n' "$root"
}

# 単位フォルダを1つも持たないプロジェクトルートを作る(0件が正しい種別の代表)。
make_empty_project() {
  local base="$1" root
  root="$base/empty-project"
  mkdir -p "$root"
  printf '%s\n' "$root"
}

# targetを与えたプロジェクトルートに対して実行し、標準出力+標準エラーと終了コードを
# 呼び出し元へ返す。結果は "<終了コード>\t<出力全体>" の1行(出力側の改行は保持したまま
# 末尾へ連結)ではなく、2つの一時ファイル経由で受け渡す(出力に改行・タブが混在するため)。
run_target() {
  local target="$1" project_root="$2" dest_dir="$3" out_file="$4" rc_file="$5"
  local rc
  bash "$target" "$project_root" "$dest_dir" --unit-kind feature >"$out_file" 2>&1
  rc=$?
  printf '%s' "$rc" > "$rc_file"
}

check_detection() {
  local target="${1:-$TARGET_DEFAULT}"
  if [ ! -f "$target" ]; then
    echo "[UNKNOWN] 検査対象が見つからないため判定できません: ${target}" >&2
    return 2
  fi

  # 静的確認: 単位フォルダ数と組み立て件数を突き合わせる実装(count_canonical_unit_dirs)が
  # 対象スクリプトに存在するか。このスクリプト自身(docs/scripts/配下)は対象に含まれないため、
  # 自己参照で誤って合格することはない。
  local ok=1 static_ok=1
  grep -q "count_canonical_unit_dirs" "$target" 2>/dev/null || static_ok=0
  grep -q "単位フォルダの数" "$target" 2>/dev/null || static_ok=0
  [ "$static_ok" -eq 1 ] || ok=0

  local tmp
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-manifest-count-mismatch.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）" >&2
    return 2
  fi
  trap 'rm -rf "$tmp"' RETURN

  # ケース1: 単位フォルダが2つあり片方だけ設計文書が実在する → 食い違いのWARNが出て、
  #          終了コードは0のまま続くこと。
  local mismatch_root mismatch_out
  mismatch_root="$(make_mismatch_project "$tmp")"
  mismatch_out="$tmp/mismatch-out"
  mkdir -p "$mismatch_out"
  run_target "$target" "$mismatch_root" "$mismatch_out" \
    "$tmp/mismatch-output.txt" "$tmp/mismatch-rc.txt"
  local mismatch_rc mismatch_output
  mismatch_rc="$(cat "$tmp/mismatch-rc.txt" 2>/dev/null || echo "")"
  mismatch_output="$(cat "$tmp/mismatch-output.txt" 2>/dev/null || echo "")"
  [ "$mismatch_rc" = "0" ] || ok=0
  printf '%s' "$mismatch_output" | grep -q "WARN" || ok=0
  printf '%s' "$mismatch_output" | grep -q "単位フォルダの数" || ok=0

  # ケース2: 単位フォルダを1つも持たない種別(0件が正しい種別) → 食い違いのWARNが
  #          出ないこと。
  local empty_root empty_out
  empty_root="$(make_empty_project "$tmp")"
  empty_out="$tmp/empty-out"
  mkdir -p "$empty_out"
  run_target "$target" "$empty_root" "$empty_out" \
    "$tmp/empty-output.txt" "$tmp/empty-rc.txt"
  local empty_rc empty_output
  empty_rc="$(cat "$tmp/empty-rc.txt" 2>/dev/null || echo "")"
  empty_output="$(cat "$tmp/empty-output.txt" 2>/dev/null || echo "")"
  [ "$empty_rc" = "0" ] || ok=0
  printf '%s' "$empty_output" | grep -q "単位フォルダの数" && ok=0

  rm -rf "$tmp"
  trap - RETURN

  if [ "$ok" -eq 1 ]; then
    echo "[PASS] 単位フォルダの数と組み立てられた件数の食い違いを検知し、0件が正しい種別では誤って報告しません"
    return 0
  fi
  echo "[FAIL] 食い違い検知の実装または挙動が不正です（対象: ${target}）"
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

run_self_test() {
  local pass=0 fail=0 total=0
  local tmp
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-manifest-count-mismatch-selftest.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' EXIT

  # ケースA: 実際の対象スクリプトに対して実行すると合格する
  # (単位フォルダが1つ欠けたケースで食い違いが出て、0件が正しいケースでは出ない)。
  record_self_test "実対象で食い違い検知が合格する" 0 check_detection "$TARGET_DEFAULT"

  # ケースB: 検査対象が存在しない場合は判定不能として区別する。
  record_self_test "検査対象不在を判定不能として区別する" 2 check_detection "$tmp/no-such-script.sh"

  # ケースC: 食い違い検知を実装しないスタブ(単位フォルダの実在に関わらず常に0件の
  # マニフェストを書き、WARNを一切出さない)を対象にすると不合格になる。項目を欠いた
  # 入力(feature-without-doc)を与えても食い違いが報告されないことを確かめるケース。
  local stub="$tmp/stub-build-manifests-from-docs.sh"
  cat > "$stub" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
output_dir="${1:?}"
dest_dir="${2:?}"
shift 2
kind="feature"
while [ $# -gt 0 ]; do
  case "$1" in
    --unit-kind) kind="${2:?}"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$dest_dir"
printf '{"generatedAt":"1970-01-01T00:00:00Z","sourceDir":"docs/design/features","unitKind":"%s","strategy":{"extractionMethod":"document-frontmatter","approvedByUser":true,"unitIdRegex":null},"detectionSummary":{"unitCount":0,"unresolvedCount":0},"units":[]}\n' "$kind" > "$dest_dir/${kind}-manifest.json"
exit 0
EOF
  chmod +x "$stub"
  record_self_test "食い違い検知を持たないスタブは不合格になる" 1 check_detection "$stub"

  echo "実行 ${total} 件 / 成功 ${pass} 件 / 失敗 ${fail} 件"
  local result=0
  [ "$fail" -eq 0 ] || result=1
  rm -rf "$tmp"
  trap - EXIT
  return "$result"
}

case "${1:-}" in
  "") check_detection "$TARGET_DEFAULT"; exit $? ;;
  --self-test) run_self_test; exit $? ;;
  *) echo "不明な引数: $1" >&2; exit 1 ;;
esac
