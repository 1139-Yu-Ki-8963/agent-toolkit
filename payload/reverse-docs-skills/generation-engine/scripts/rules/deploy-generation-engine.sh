#!/usr/bin/env bash
set -euo pipefail

# deploy-generation-engine.sh — 納品先へ生成器一式（reverse-docs-engine/）を配る
#
# 目的:
#   納品先には成果物（ポータルのHTML・規約のHTML・一覧）だけが配られ、それを
#   作り直す生成器が1本も配られていなかった。定義（docs/rules/ 等）を直しても
#   成果物へ反映する手段が無い問題への対応として、生成器一式を配る。
#
# 配るもの（複製元はこのリポジトリのルートから、複製先は納品先のルートから）:
#   generation-engine/scripts/       -> reverse-docs-engine/generation-engine/scripts/
#   delivery-payload/templates/      -> reverse-docs-engine/delivery-payload/templates/
#   delivery-payload/references/     -> reverse-docs-engine/delivery-payload/references/
#   （いずれも木ごと cp -R する。個々のファイルを数え上げて選ばない）
#   生成物notice: reverse-docs-engine/README.md（新規/既存にかかわらず常に書き直す）
#   対象側の配置上書き: <納品先>/output-layout.json
#     （既存の場合は上書きしない。無ければ generation-engine/samples/output-layout.json
#      と同じ内容で作る。無いと出力先フォルダ名が既定の英字名になり、
#      日本語名（一覧・対応表・画面・図・基盤）にならない）
#
# 動く理由（実証済み）:
#   生成器の全スクリプトはテンプレート・定義のパスを自分の位置からの相対で解決する
#   （$SCRIPT_DIR/../../delivery-payload/... の形。入れ子の深いものは ../../../）。
#   reverse-docs-engine/ 配下で generation-engine/scripts と delivery-payload の
#   相対位置がこのリポジトリのルート直下と同じ階層関係を保つ限り、コードを
#   1行も書き換えずに動く。この階層関係を保つことが唯一の条件である。
#
# 使い方:
#   deploy-generation-engine.sh <納品先のルート> [--apply]
#   deploy-generation-engine.sh --self-test
#
# 既定はdry-run。配布予定のパスを標準出力へ列挙するのみで書き込みをしない。
# --apply を付けたときだけ納品先のルートへ実際に書き込む。
# --apply 実行後は配布後の検査（5件）を行い、1件でも不合格なら終了コード1で終わる。
#
# 終了コード:
#   0 = 配布（またはdry-runの列挙）が完了し、--apply時は検査もすべてPASS
#   1 = 引数不正、または --apply後の検査に不合格がある
#   --self-test のみ、期待どおりの挙動でなければ1
#   2 = mktemp（一時ディレクトリの作成）が失敗、または生成器一式の複製
#       （cp -R）が実行環境の制約で失敗し判定不能
#
# 実装判断（cp -R の失敗を判定不能として区別する理由）:
#   generation-engine/scripts/ 配下には .venv 等の実行環境依存の成果物
#   （gitignore対象。ビルド時にpipが作るPython仮想環境等）が混在しうる。
#   2026-08-28実測: generation-engine/scripts/glossary/.venv 配下の
#   cacert.pem（pipのvendor証明書）を cp -R が複製しようとすると、
#   実行環境のサンドボックス制約（*.pemファイルへの読み取り拒否）により
#   「Operation not permitted」で失敗する。制限を外して同じ環境で実行すると
#   成功する（成果物・本スクリプト自体の欠陥ではない）。
#   この失敗を通常の不合格（終了コード1）として扱うと、成果物の欠陥と
#   読み違える（.claude/rules/always/verification/indeterminate-result/rule.md
#   が定める判定不能規約に反する）。cp -R の標準エラーに
#   「Operation not permitted」が含まれる場合だけ終了コード2・[UNKNOWN]で
#   返し、それ以外の失敗（複製元の欠落等）は従来どおり終了コード1で返す。
#
# 設計判断（必要性・代替案・保守責任者・廃棄条件）:
#   必要性: 納品先には成果物（ポータルのHTML・規約のHTML・一覧）だけが配られ、
#     それを作り直す生成器が配られていなかった。定義を直しても成果物へ反映する
#     手段が無い。実証（一時ディレクトリへ複製して実行）により、
#     generation-engine/scripts と delivery-payload を木ごと複製し階層関係を
#     保つだけで、コードを1行も書き換えずに動くことを確かめた。
#   代替案を採用しなかった理由:
#     必要な二十数本のファイルを数え上げて個別に配る方式は、数え間違いが
#     そのまま「動かない生成器を配る」事故になる。木ごと複製すれば数え上げ自体が
#     不要になる。
#     配置先ごとにパスを書き換える方式（相対パスをreverse-docs-engine配下向けに
#     個別に書き換える）は、生成スクリプト二十数本すべてに手を入れる必要があり、
#     書き換え漏れが混入するリスクを常に負う。実証した「階層関係を保てば
#     書き換え不要」という事実に反する回り道である。
#   保守責任者: 人手（ユーザー）。
#   廃棄条件: 納品先での作り直しを廃止した時。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

SRC_ENGINE_SCRIPTS="${REPO_ROOT}/generation-engine/scripts"
SRC_TEMPLATES="${REPO_ROOT}/delivery-payload/templates"
SRC_REFERENCES="${REPO_ROOT}/delivery-payload/references"
SRC_OUTPUT_LAYOUT_OVERRIDE="${REPO_ROOT}/generation-engine/samples/output-layout.json"

usage() {
  echo "使い方: $(basename "$0") <納品先のルート> [--apply]" >&2
  echo "        $(basename "$0") --self-test" >&2
}

readme_content() {
  cat <<'EOF'
# reverse-docs-engine

このフォルダは納品物を作り直すための生成器の一式である。**生成物であり、直接編集してはならない。**

複製元はリバース設計スキル群のリポジトリであり、`deploy-generation-engine.sh` が木ごと複製する。ここへ加えた変更は次の複製で失われる。

## 構造

| パス | 内容 |
|---|---|
| `generation-engine/scripts/` | 生成器のスクリプト一式 |
| `delivery-payload/templates/` | 生成に使うテンプレート |
| `delivery-payload/references/` | 生成に使う定義 |

## 階層を動かしてはならない理由

生成器はテンプレートと定義のパスを、自分の位置からの相対で解決する。`generation-engine/scripts/` と `delivery-payload/` の相対位置が変わると、テンプレートを見つけられずに止まる。フォルダの移動・改名をしてはならない。

## 使い方

`maintaining-portal` スキルが呼ぶ。手で実行する必要はない。

## 動作に必要な外部の道具

`jq`・`node`（20以上）・`python3`・`shasum`。追加の依存パッケージは無い。
EOF
}

# 配布予定・配布結果のパス一覧（説明つき）を組み立てて標準出力へ返す。
# $1: 納品先のルート
build_plan() {
  local target_root="$1"
  local engine_root="${target_root}/reverse-docs-engine"
  printf '%s\n' \
    "${engine_root}/generation-engine/scripts/" \
    "${engine_root}/delivery-payload/templates/" \
    "${engine_root}/delivery-payload/references/" \
    "${engine_root}/README.md"
  if [ -e "${target_root}/output-layout.json" ]; then
    printf '%s\n' "${target_root}/output-layout.json（既存のため上書きしない）"
  else
    printf '%s\n' "${target_root}/output-layout.json"
  fi
}

# 生成器一式を配る。$1: 納品先のルート  $2: apply（1なら実際に書き込む・0ならdry-run）
# 木を複製する。実行環境の制約（サンドボックスの *.pem 等の読み取り拒否）に
# よる失敗を、対象の欠陥による通常の失敗と区別するため、cp -R の標準エラーを
# 見て判定する（.claude/rules/always/verification/indeterminate-result/rule.md
# の判定不能規約に沿う）。
# 戻り値: 0=成功 / 1=失敗（対象の欠陥の可能性） / 2=環境の制約による失敗（判定不能）
_cp_tree_or_report() {
  local src="$1" dst="$2"
  local err_output
  if err_output="$(cp -R "$src" "$dst" 2>&1 >/dev/null)"; then
    return 0
  fi
  if printf '%s' "$err_output" | grep -q 'Operation not permitted'; then
    echo "ERROR: ${src} の一部を読み取れず複製できません（Operation not permitted）。実行環境の制約による可能性があります。" >&2
    printf '%s\n' "$err_output" >&2
    return 2
  fi
  printf '%s\n' "$err_output" >&2
  return 1
}

run_deploy() {
  local target_root="$1" apply="$2"
  local engine_root="${target_root}/reverse-docs-engine"

  if [ "$apply" -ne 1 ]; then
    echo "DRY-RUN: 以下を配布予定（--apply未指定のため書き込みなし）:"
    build_plan "$target_root"
    return 0
  fi

  if [ ! -d "$SRC_ENGINE_SCRIPTS" ] || [ ! -d "$SRC_TEMPLATES" ] || [ ! -d "$SRC_REFERENCES" ]; then
    echo "ERROR: 複製元が見つかりません（generation-engine/scripts・delivery-payload/templates・delivery-payload/references のいずれか）" >&2
    return 1
  fi

  # output-layout.json の「既存のため上書きしない」表示は、書き込みより前の
  # 存在状態で判定する（後で判定すると、今回新規に作った直後に確認するため
  # 常に「既存」と誤表示する）。
  local output_layout_existed=0
  [ -e "${target_root}/output-layout.json" ] && output_layout_existed=1

  mkdir -p "${engine_root}/generation-engine" "${engine_root}/delivery-payload"

  # 木ごと複製する（個々のファイルを数え上げない）。再実行時に古い内容が
  # 混ざらないよう、複製先を先に消してから複製する。
  local _cp_rc
  rm -rf "${engine_root}/generation-engine/scripts"
  _cp_rc=0
  _cp_tree_or_report "$SRC_ENGINE_SCRIPTS" "${engine_root}/generation-engine/scripts" || _cp_rc=$?
  [ "$_cp_rc" -ne 0 ] && return "$_cp_rc"

  rm -rf "${engine_root}/delivery-payload/templates"
  _cp_rc=0
  _cp_tree_or_report "$SRC_TEMPLATES" "${engine_root}/delivery-payload/templates" || _cp_rc=$?
  [ "$_cp_rc" -ne 0 ] && return "$_cp_rc"

  rm -rf "${engine_root}/delivery-payload/references"
  _cp_rc=0
  _cp_tree_or_report "$SRC_REFERENCES" "${engine_root}/delivery-payload/references" || _cp_rc=$?
  [ "$_cp_rc" -ne 0 ] && return "$_cp_rc"

  readme_content > "${engine_root}/README.md"

  if [ "$output_layout_existed" -ne 1 ]; then
    if [ ! -f "$SRC_OUTPUT_LAYOUT_OVERRIDE" ]; then
      echo "ERROR: 対象側の配置上書きの複製元が見つかりません: ${SRC_OUTPUT_LAYOUT_OVERRIDE}" >&2
      return 1
    fi
    cp "$SRC_OUTPUT_LAYOUT_OVERRIDE" "${target_root}/output-layout.json"
  fi

  echo "配布完了（--apply）:"
  printf '%s\n' \
    "${engine_root}/generation-engine/scripts/" \
    "${engine_root}/delivery-payload/templates/" \
    "${engine_root}/delivery-payload/references/" \
    "${engine_root}/README.md"
  if [ "$output_layout_existed" -eq 1 ]; then
    printf '%s\n' "${target_root}/output-layout.json（既存のため上書きしない）"
  else
    printf '%s\n' "${target_root}/output-layout.json"
  fi
  return 0
}

# 配布後の検査。1件でも不合格なら1を返す。$1: 納品先のルート
verify_deploy() {
  local target_root="$1"
  local engine_root="${target_root}/reverse-docs-engine"
  local fail=0

  _verify_one() {
    local label="$1" path="$2"
    if [ -e "$path" ]; then
      echo "  [PASS] ${label}: ${path}"
    else
      echo "  [FAIL] ${label}: ${path}" >&2
      fail=1
    fi
  }

  _verify_one "検査1: 生成器の入口スクリプトが実在する" \
    "${engine_root}/generation-engine/scripts/build-portal.sh"
  _verify_one "検査2: 相対パスの解決が正しい（scripts配下からdelivery-payload/referencesへ）" \
    "${engine_root}/generation-engine/scripts/../../delivery-payload/references/portal-catalog.json"
  _verify_one "検査3: テンプレートの共通シェルCSSが実在する" \
    "${engine_root}/delivery-payload/templates/partials/shell.css"
  _verify_one "検査4: 対象側の配置上書きが実在する" \
    "${target_root}/output-layout.json"
  _verify_one "検査5: 生成物notice（README.md）が実在する" \
    "${engine_root}/README.md"

  return "$fail"
}

self_test() {
  local tmpdir
  # 判定不能規約（.claude/rules/always/verification/indeterminate-result/rule.md）:
  # mktemp の失敗（実行環境のサンドボックス制約等）を対象の不合格と区別する。
  # if の条件式の中で代入と失敗チェックを行うことで、set -e の対象から外す。
  # 置き場を明示するのは、引数なしの mktemp が既定の置き場へ書こうとして失敗する環境があるためである（実測 2026-08-24）。素直な mktemp へ戻さない。
  if ! tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/$(basename "${BASH_SOURCE[0]}" .sh).XXXXXX" 2>/dev/null)" || [ -z "$tmpdir" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）"
    exit 2
  fi
  trap 'rm -rf "$tmpdir"' RETURN

  local rc=0

  # ケース1: --apply を付けない場合に1件も書き込まないこと
  local out1="${tmpdir}/case1"
  mkdir -p "$out1"
  run_deploy "$out1" 0 >/dev/null
  if [ -e "${out1}/reverse-docs-engine" ] || [ -e "${out1}/output-layout.json" ]; then
    echo "  [FAIL] ケース1: --apply未指定なのに書き込みが発生した" >&2
    rc=1
  else
    echo "  [PASS] ケース1: --apply未指定では書き込みが1件も発生しない"
  fi

  # 判定不能規約: run_deploy の cp -R が実行環境の制約（サンドボックスの
  # *.pem等の読み取り拒否）で失敗した場合、run_deploy は終了コード2を返す
  # （_cp_tree_or_report 参照）。ケース2・ケース3のどちらでこの2を受け取っても、
  # 対象の欠陥による不合格（rc=1）とは区別し、self-test全体を打ち切って
  # [UNKNOWN]・終了コード2で終える。ケース1（apply=0）はcpを行わないため対象外。

  # ケース2: --apply で配布し、検査1〜5がすべて通ること
  local out2="${tmpdir}/case2"
  mkdir -p "$out2"
  local case2_deploy_rc=0 case2_verify_output
  run_deploy "$out2" 1 >/dev/null || case2_deploy_rc=$?
  if [ "$case2_deploy_rc" -eq 2 ]; then
    echo "[UNKNOWN] --self-test: 生成器一式の複製に失敗したため判定できません（cp -R が『Operation not permitted』で失敗しました。実行環境のサンドボックス制約等が原因である可能性があります）" >&2
    rm -rf "$tmpdir"
    exit 2
  elif [ "$case2_deploy_rc" -ne 0 ]; then
    echo "  [FAIL] ケース2: --apply の実行が異常終了した" >&2
    rc=1
  elif case2_verify_output="$(verify_deploy "$out2" 2>&1)"; then
    echo "  [PASS] ケース2: --apply で配布し、検査1〜5がすべて通る"
  else
    echo "  [FAIL] ケース2: 配布後の検査に不合格があった" >&2
    printf '%s\n' "$case2_verify_output" >&2
    rc=1
  fi

  # ケース3: 既存の output-layout.json を上書きしないこと
  local out3="${tmpdir}/case3"
  mkdir -p "$out3"
  printf '{"specVersion":1,"layout":{"__marker__":"keep"}}\n' > "${out3}/output-layout.json"
  local case3_deploy_rc=0
  run_deploy "$out3" 1 >/dev/null || case3_deploy_rc=$?
  if [ "$case3_deploy_rc" -eq 2 ]; then
    echo "[UNKNOWN] --self-test: 生成器一式の複製に失敗したため判定できません（cp -R が『Operation not permitted』で失敗しました。実行環境のサンドボックス制約等が原因である可能性があります）" >&2
    rm -rf "$tmpdir"
    exit 2
  fi
  if grep -q '__marker__' "${out3}/output-layout.json" 2>/dev/null; then
    echo "  [PASS] ケース3: 既存の output-layout.json を上書きしない"
  else
    echo "  [FAIL] ケース3: 既存の output-layout.json が上書きされた" >&2
    rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi

  local target_root="" apply_flag=0
  local args=()
  for a in "$@"; do
    case "$a" in
      --apply) apply_flag=1 ;;
      *) args+=("$a") ;;
    esac
  done

  if [ "${#args[@]}" -ne 1 ]; then
    usage
    exit 1
  fi

  target_root="${args[0]}"
  mkdir -p "$target_root"
  target_root="$(cd "$target_root" && pwd)"

  local deploy_rc=0
  run_deploy "$target_root" "$apply_flag" || deploy_rc=$?

  if [ "$deploy_rc" -eq 2 ]; then
    echo "[UNKNOWN] 生成器一式の複製に失敗したため判定できません（cp -R が『Operation not permitted』で失敗しました。実行環境のサンドボックス制約等が原因である可能性があります）" >&2
    exit 2
  fi

  if [ "$apply_flag" -eq 1 ] && [ "$deploy_rc" -eq 0 ]; then
    echo
    echo "配布後の検査:"
    if verify_deploy "$target_root"; then
      echo "検査1〜5: 全件PASS"
    else
      echo "検査1〜5: 不合格あり" >&2
      exit 1
    fi
  fi

  exit "$deploy_rc"
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main "$@"
fi
