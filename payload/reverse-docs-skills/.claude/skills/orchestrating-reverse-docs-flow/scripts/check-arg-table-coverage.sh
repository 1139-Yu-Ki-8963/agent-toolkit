#!/usr/bin/env bash
# check-arg-table-coverage.sh — 起動引数表と本文の子スキル起動引数の突合（改善課題1-121再発防止）
#
# orchestrating-reverse-docs-flow の SKILL.md「## 起動引数」表に載る引数名の集合と、
# references/contract.md「## args 仕様」節が子スキルへ args として渡す引数名の集合を機械抽出し、
# 後者が前者に含まれない差分（表への掲載漏れ）を検出する。差分が1件でもあればexit 1。
#
# 子スキル固有の内部値（mode・ports・scope等、統括が起動ごとに導出・決定して渡す値であり、
# 統括自身の起動引数として外部から受け取るものではない）はDENYLISTで除外する。新規の子スキル
# 引数が本文に追加された際、DENYLIST未登録かつ表未掲載であれば本チェックはFAILする。追加時は
# 「表に載せるべき統括自身の起動引数か」「DENYLISTに追加すべき統括内部の導出値か」を都度判定し、
# 本スクリプトとSKILL.mdの両方を更新する。
#
# Usage: check-arg-table-coverage.sh <SKILL.md> <contract.md>
#        check-arg-table-coverage.sh --self-test
#
# 保守責任者: 人手（ユーザー）。子スキルへの新規args追加時はDENYLISTまたは起動引数表を追従させる。

set -uo pipefail

# 統括自身の起動引数ではなく、統括が起動ごとに導出・決定して子スキルへ渡す内部値・子スキル固有値。
DENYLIST_STR="mode ports scope reverse_worktree system screen_id user-approved env_block
design-doc dry-run reset-first scenarios max-loop invocation_mode compare_result
freeze_commit saved_test_paths screen_ids model wait_seconds fail_limit_k log_path
portal_output_dir sites_path site_key target_branch source_ref revise_findings
append_findings facts_ref chapter_map_path audit_script_path scaffold_script_path
common_docs_root unit_kind target_file_path screenshot_dir verification_url run_id
screen_dir baseline_tag_status profile source_dir"

is_denylisted() { # $1=token
  local t="$1" d
  for d in $DENYLIST_STR; do
    [ "$t" = "$d" ] && return 0
  done
  return 1
}

# SKILL.mdの「## 起動引数」表の第1列（引数名）を1行1件で列挙する
# 注意: sed/awkのブラケット表現 [ \t] はBSD sed（macOS既定）ではタブと解釈されず、
#       スペース・バックスラッシュ・文字'ｔ'の集合として解釈され語頭・語末の"t"を誤って
#       削ってしまう（実測済みの罠）。空白除去には[[:space:]]のみを使う。
extract_table_args() { # $1=SKILL.md
  awk '
    /^## 起動引数$/ { intable=1; next }
    intable && /^## / { intable=0 }
    intable && /^\|/ { print }
  ' "$1" \
  | tail -n +3 \
  | awk -F'|' '{ v=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); gsub(/`/, "", v); if (v != "") print v }'
}

# contract.mdの「## args 仕様」節の箇条書き行から、子スキルへ渡すargs名を1行1件で列挙する
# 「- 注記:」で始まる補足説明の箇条書きはargs宣言ではないため対象外とする。
extract_child_args() { # $1=contract.md
  awk '
    /^## args 仕様$/ { insec=1; next }
    insec && /^## / { insec=0 }
    insec && /^- / { print }
  ' "$1" \
  | while IFS= read -r line; do
      case "$line" in
        "- 注記:"*) continue ;;
        *": "*) rest="${line#*: }" ;;
        *) continue ;;
      esac
      printf '%s\n' "$rest" | tr ',' '\n'
    done \
  | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/`//g' \
  | grep -oE '^[A-Za-z_][A-Za-z0-9_-]*'
}

# $1=SKILL.md $2=contract.md。差分（表未掲載の子args）を1行1件で標準出力へ。差分0件ならexit 0
check_coverage() {
  local skill_md="$1" contract_md="$2"
  local table_args child_args diff tok
  table_args="$(extract_table_args "$skill_md" | sort -u)"
  child_args="$(extract_child_args "$contract_md" | sort -u)"

  diff=""
  while IFS= read -r tok; do
    [ -z "$tok" ] && continue
    is_denylisted "$tok" && continue
    if ! printf '%s\n' "$table_args" | grep -qxF "$tok"; then
      diff="${diff}${tok}
"
    fi
  done <<EOF
$child_args
EOF

  if [ -n "$diff" ]; then
    printf '%s' "$diff"
    return 1
  fi
  return 0
}

self_test() {
  local tmp rc=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-arg-table-coverage-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  # ---- 陽性: 実ファイル(SKILL.md / contract.md)で差分0件 ----
  local script_dir real_skill real_contract
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  real_skill="$script_dir/../SKILL.md"
  real_contract="$script_dir/../references/contract.md"
  local real_diff
  if real_diff="$(check_coverage "$real_skill" "$real_contract")"; then
    echo "  [PASS] 実ファイル陽性: 起動引数表と本文のargsに掲載漏れ0件"
  else
    echo "  [FAIL] 実ファイル陽性: 掲載漏れを検出しました — ${real_diff}" >&2
    rc=1
  fi

  # ---- 合成フィクスチャ: 表にalpha/betaのみ、本文がalpha/beta/gammaを要求 → gammaが差分 ----
  local fx_skill="$tmp/fixture-skill.md" fx_contract="$tmp/fixture-contract.md"
  cat > "$fx_skill" <<'MD'
## 起動引数

| 引数 | 必須 | 内容 |
|---|---|---|
| alpha | 必須 | 説明 |
| beta | 任意 | 説明 |

## 基本ワークフロー
MD
  cat > "$fx_contract" <<'MD'
## args 仕様

- some-skill: alpha, beta, gamma（任意）, mode（x|y）

## Python facts-only入口契約
MD
  local fx_diff
  if fx_diff="$(check_coverage "$fx_skill" "$fx_contract")"; then
    echo "  [FAIL] 合成陰性: gammaが表未掲載なのにPASSした" >&2
    rc=1
  else
    if printf '%s' "$fx_diff" | grep -qxF "gamma"; then
      echo "  [PASS] 合成陰性: 表未掲載のgammaを差分として検出"
    else
      echo "  [FAIL] 合成陰性: FAILしたが差分にgammaが含まれない — ${fx_diff}" >&2
      rc=1
    fi
    if printf '%s' "$fx_diff" | grep -qxF "mode"; then
      echo "  [FAIL] 合成陰性: DENYLIST対象のmodeが誤って差分に含まれた" >&2
      rc=1
    fi
  fi

  # ---- 合成陽性: gammaを表へ追加すれば差分0件 ----
  cat > "$fx_skill" <<'MD'
## 起動引数

| 引数 | 必須 | 内容 |
|---|---|---|
| alpha | 必須 | 説明 |
| beta | 任意 | 説明 |
| gamma | 任意 | 説明 |

## 基本ワークフロー
MD
  if check_coverage "$fx_skill" "$fx_contract" >/dev/null 2>&1; then
    echo "  [PASS] 合成陽性: gammaを表へ追加すれば差分0件"
  else
    echo "  [FAIL] 合成陽性: gammaを表へ追加してもFAILした" >&2
    rc=1
  fi

  # ---- 回帰確認: 表からalphaの行を削除すると再度FAILする(検査自体が無効化されていないことの証明) ----
  cat > "$fx_skill" <<'MD'
## 起動引数

| 引数 | 必須 | 内容 |
|---|---|---|
| beta | 任意 | 説明 |
| gamma | 任意 | 説明 |

## 基本ワークフロー
MD
  local del_diff
  if del_diff="$(check_coverage "$fx_skill" "$fx_contract")"; then
    echo "  [FAIL] 回帰確認: alpha行を削除してもPASSした（検査が機能していない）" >&2
    rc=1
  else
    if printf '%s' "$del_diff" | grep -qxF "alpha"; then
      echo "  [PASS] 回帰確認: alpha行の削除を差分として検出（検査は有効な回帰ガード）"
    else
      echo "  [FAIL] 回帰確認: FAILしたが差分にalphaが含まれない — ${del_diff}" >&2
      rc=1
    fi
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

skill_md="${1:?使い方: check-arg-table-coverage.sh <SKILL.md> <contract.md> ／ check-arg-table-coverage.sh --self-test}"
contract_md="${2:?使い方: check-arg-table-coverage.sh <SKILL.md> <contract.md> ／ check-arg-table-coverage.sh --self-test}"

if diff_out="$(check_coverage "$skill_md" "$contract_md")"; then
  echo "PASS: 起動引数表と本文のargsに掲載漏れ0件"
  exit 0
else
  echo "FAIL: 以下の引数が本文でargsとして子スキルへ渡されているが起動引数表に未掲載です" >&2
  printf '%s' "$diff_out" >&2
  exit 1
fi
