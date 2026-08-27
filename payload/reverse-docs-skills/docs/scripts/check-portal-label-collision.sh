#!/usr/bin/env bash
# check-portal-label-collision.sh — project-portal/ 直下の実際のディレクトリ名が、
# portal-catalog.json のカテゴリ label 値と同じ文字列になっていないかを検査する
#
# 改善課題1-213は、output-layout.json の置き場の値（英字）と portal-catalog.json
# の表示見出し（label。日本語）が別の鍵に分かれている一方で、既存の逆戻り検知
# （check-portal-dir-ascii.sh）は短い旧名4語だけを対象にしており、label値そのもの
# （「マトリクス・対応表」「基盤情報」等の複合語）と同名のディレクトリを検出しない
# 穴を扱う。
#
# 判定式を指示書の表へ直接書けないためスクリプトへ切り出した
# （.claude/rules/always/tasks/instruction-format/rule.md の設計判断を参照）。
#
# 使い方:
#   check-portal-label-collision.sh <project-portal のパス>   実ディレクトリを検査する
#   check-portal-label-collision.sh --self-test               合成フィクスチャで自己検査する
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CATALOG="$REPO_ROOT/delivery-payload/references/portal-catalog.json"

# labels_from_catalog: portal-catalog.json の全カテゴリ label 値を1行1件で出す
labels_from_catalog() {
  jq -r '.categories[].label' "$CATALOG" 2>/dev/null
}

# check_portal_dir: <portal_dir> 直下の実ディレクトリ名を label 一覧と突き合わせる。
# 一致が1件も無ければ0、1件でもあれば1を返す（labels_from_catalog の失敗は2）。
check_portal_dir() {
  local portal_dir="$1"
  local labels
  if ! labels="$(labels_from_catalog)"; then
    echo "[UNKNOWN] portal-catalog.jsonからlabel一覧を取得できませんでした"
    return 2
  fi
  if [ -z "$labels" ]; then
    echo "[UNKNOWN] portal-catalog.jsonにlabelが1件もありません"
    return 2
  fi
  [ -d "$portal_dir" ] || { echo "[PASS] $portal_dir は存在しないため対象0件"; return 0; }

  local hit=0 d name
  for d in "$portal_dir"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    while IFS= read -r label; do
      [ -z "$label" ] && continue
      if [ "$name" = "$label" ]; then
        echo "[FAIL] $portal_dir/$name は表示見出し「${label}」と同じ名前の置き場です"
        hit=1
      fi
    done <<LABELS_EOF
$labels
LABELS_EOF
  done

  if [ "$hit" -eq 1 ]; then
    return 1
  fi
  echo "[PASS] $portal_dir 直下にlabelと同名の置き場は無い"
  return 0
}

run_self_test() {
  local ok=1
  local tmp
  local case1_output case1_rc
  local case2_output case2_rc
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/portal-label-collision-selftest.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] --self-test: 一時ディレクトリの作成に失敗したため判定できません（mktemp）"
    return 2
  fi

  # ケース1: labelと同名のディレクトリがあれば不合格になること
  mkdir -p "$tmp/case1/マトリクス・対応表"
  case1_output="$(check_portal_dir "$tmp/case1")"
  case1_rc=$?
  if [ "$case1_rc" -eq 1 ]; then
    if [[ "$case1_output" == *'[FAIL]'* ]]; then
      echo "[PASS] ケース1: label同名の置き場を終了コード1で検出した"
    else
      echo "[FAIL] ケース1: 終了コード1だが検出結果を出力しなかった"
      ok=0
    fi
  else
    echo "[FAIL] ケース1: label同名の置き場に終了コード1を返さなかった（exit ${case1_rc}）"
    ok=0
  fi

  # ケース2: 英字の正しい置き場だけならPASSすること
  mkdir -p "$tmp/case2/matrices"
  case2_output="$(check_portal_dir "$tmp/case2")"
  case2_rc=$?
  if [ "$case2_rc" -eq 0 ]; then
    if [[ "$case2_output" == *'[PASS]'* ]]; then
      echo "[PASS] ケース2: 英字の置き場は終了コード0で誤検知しない"
    else
      echo "[FAIL] ケース2: 終了コード0だが合格結果を出力しなかった"
      ok=0
    fi
  else
    echo "[FAIL] ケース2: 英字の置き場に終了コード0を返さなかった（exit ${case2_rc}）"
    ok=0
  fi

  # ケース3: 現行のgeneration-engine/samplesにlabel同名の置き場が無いこと
  local samples_portal="$REPO_ROOT/generation-engine/samples/project-portal"
  if check_portal_dir "$samples_portal" >/dev/null; then
    echo "[PASS] ケース3: 現行samplesにlabel同名の置き場は無い"
  else
    echo "[FAIL] ケース3: 現行samplesにlabel同名の置き場がある"
    ok=0
  fi

  rm -rf "$tmp"
  if [ "$ok" -eq 1 ]; then
    echo "self-test: 3 PASS, 0 FAIL"
    return 0
  fi
  echo "self-test: FAILあり"
  return 1
}

main() {
  if [ "$#" -gt 1 ]; then
    echo "usage: $0 [<project-portal path> | --self-test]" >&2
    return 2
  fi
  if [ "$#" -eq 1 ]; then
    if [ "$1" = "--self-test" ]; then
      run_self_test
      return $?
    fi
  fi
  local target="${1:-$REPO_ROOT/generation-engine/samples/project-portal}"
  check_portal_dir "$target"
  return $?
}

main "$@"
exit $?
