#!/usr/bin/env bash
# run-authoring-mode.sh — 対話モデルを挟む別モード（著述モード）の骨格
#
# 何をするか:
#   決定的なスクリプトでは作れない設計文書の Markdown（画面・API・テーブル・
#   バッチ・帳票・外部連携の各設計書、および共通設計書）を、対話モデルの
#   1 回呼び出し（claude -p）で執筆させる。挟み込む位置は、生成連鎖の
#   3 段目（マニフェストの組み立て）の直前である。
#
# なぜ既定で走らないか（2 点）:
#   1. 対話モデルの実行は自己テストとして回せない。--self-test は判断を
#      要する処理そのものを検査対象にできず、呼び出しの構成だけを検査する。
#   2. 実行のたびに出力が揺れるため、往復検証が求める「再現」（同じ入力で
#      2 回実行し、生成物が一致すること）の判定と衝突する。
#
# Usage:
#   run-authoring-mode.sh --output <出力先> [--repo <リポジトリのパス>] [--enable] [--dry-run] [--permission-mode <値>] [--self-test]
#
#   --output <path>          設計文書の書き出し先ルート（--enable 時は必須）
#   --repo <path>            対象リポジトリのパス（任意。プロンプトへ渡すだけで本スクリプトは中身を解釈しない）
#   --enable                 明示した場合のみ対話モデルの呼び出しへ進む。既定は無効
#   --dry-run                --enable と併用時、実行予定のコマンド文字列を出力するだけで実行しない
#   --permission-mode <値>   claude -p へ渡す承認モード。指定しなければ claude -p の呼び出しに
#                            --permission-mode を一切付けない（claude 側の既定＝対話的な承認が効く）
#   --self-test              呼び出しの構成だけを検査する（対話モデルは実際に呼ばない）
#
# 承認の迂回について:
#   承認を迂回する設定（acceptEdits・bypassPermissions 等）はこのスクリプトの
#   既定に含めない。無人で走らせる必要が生じたときは、呼び出し元が
#   --permission-mode を明示して責任を持つこと。
#
# 作るもの（3 点。骨格のみ）:
#   1. 既定モードと別モードを切り替える引数の受け口（--enable 無しでは到達しない）
#   2. 生成連鎖のどの段の後に挟むかという位置の定義
#   3. claude -p の呼び出しを 1 か所（実際に動く形）
#
# 作らないもの:
#   - 挟み込んだ結果に対する 4 判定（網羅・自立・再現・健全）の調整
#   - 実行時間の制御・タイムアウト・並列度の管理
#   - 生成された設計文書の品質検査
#
# macOS 標準の bash 3.2 で動作する（連想配列不使用）。
# claude -p の実行はサンドボックスの外向き接続制限に当たるため、
# --enable を実際に実行する呼び出し元は dangerouslyDisableSandbox: true を使うこと。

set -uo pipefail

# --- 挟み込む位置の定義（生成連鎖上の段） -----------------------------
# 対象は決定的スクリプトでは作れない設計文書の Markdown の執筆段であり、
# 生成連鎖 3 段目（マニフェストの組み立て）の直前に挟む。
AUTHORING_MODE_STAGE_LABEL="設計文書の Markdown を執筆する段"
AUTHORING_MODE_POSITION="マニフェストの組み立ての前"

# --- 執筆対象の設計文書種別 --------------------------------------------
AUTHORING_MODE_TARGET_KINDS="画面 API テーブル バッチ 帳票 外部連携 共通設計書"

# --- claude -p の既定フラグ構成（running-reverse-screen-batch に倣う） ---
# 承認モードは既定を持たない。呼び出し元が --permission-mode を明示しない限り、
# claude -p の呼び出しに --permission-mode を一切付けず、claude 側の既定
# （対話的な承認）に委ねる。承認を迂回する設定をここへ既定として書かないこと。
AUTHORING_MODE_ALLOWED_TOOLS="Read,Write,Edit"
AUTHORING_MODE_OUTPUT_FORMAT="text"
AUTHORING_MODE_MODEL="claude-sonnet-5"

usage() {
  cat <<'EOF'
Usage: run-authoring-mode.sh --output <出力先> [--repo <リポジトリのパス>] [--enable] [--dry-run] [--self-test]
EOF
}

# 引数からプロンプト本文を組み立てる。中身の解釈はここで行わない。
build_prompt() {
  output_dir="$1"
  repo_path="$2"

  prompt="対話モデル著述モード。${AUTHORING_MODE_STAGE_LABEL}を担当する。"
  prompt="${prompt} 挟み込み位置: ${AUTHORING_MODE_POSITION}。"
  prompt="${prompt} 執筆対象種別: ${AUTHORING_MODE_TARGET_KINDS}。"
  prompt="${prompt} 出力先: ${output_dir}。"
  if [ -n "${repo_path}" ]; then
    prompt="${prompt} 対象リポジトリ: ${repo_path}。"
  fi
  printf '%s' "${prompt}"
}

# claude -p の呼び出しコマンドを配列で組み立てる。
# permission_mode が空なら --permission-mode を一切付けない（claude 側の既定に委ねる）。
# 呼び出し元は build_authoring_command 実行後に "${AUTHORING_CMD[@]}" を参照する。
build_authoring_command() {
  output_dir="$1"
  repo_path="$2"
  permission_mode="$3"

  prompt="$(build_prompt "${output_dir}" "${repo_path}")"

  AUTHORING_CMD=(
    claude
    -p "${prompt}"
    --allowedTools "${AUTHORING_MODE_ALLOWED_TOOLS}"
  )
  if [ -n "${permission_mode}" ]; then
    AUTHORING_CMD+=(--permission-mode "${permission_mode}")
  fi
  AUTHORING_CMD+=(
    --output-format "${AUTHORING_MODE_OUTPUT_FORMAT}"
    --no-session-persistence
    --model "${AUTHORING_MODE_MODEL}"
  )
}

# 表示用にコマンド配列を 1 行の文字列へ整形する（シェル再入力できる形を保証しない。表示専用）。
format_command_for_display() {
  out=""
  for tok in "$@"; do
    if [ -z "${out}" ]; then
      out="${tok}"
    else
      out="${out} ${tok}"
    fi
  done
  printf '%s' "${out}"
}

run_main() {
  output_dir=""
  repo_path=""
  enable_flag=0
  dry_run_flag=0
  permission_mode=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --output)
        output_dir="${2:-}"
        shift 2
        ;;
      --repo)
        repo_path="${2:-}"
        shift 2
        ;;
      --enable)
        enable_flag=1
        shift
        ;;
      --dry-run)
        dry_run_flag=1
        shift
        ;;
      --permission-mode)
        permission_mode="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        echo "ERROR: 不明な引数です: $1" >&2
        usage >&2
        return 1
        ;;
    esac
  done

  if [ "${enable_flag}" -eq 0 ]; then
    echo "別モードは無効である（既定の挙動）。対話モデルは呼び出さない。有効化するには --enable を明示すること。"
    return 0
  fi

  if [ -z "${output_dir}" ]; then
    echo "ERROR: --enable 時は --output が必須である" >&2
    return 1
  fi

  build_authoring_command "${output_dir}" "${repo_path}" "${permission_mode}"

  if [ "${dry_run_flag}" -eq 1 ]; then
    echo "実行予定のコマンド（--dry-run のため実行しない）:"
    format_command_for_display "${AUTHORING_CMD[@]}"
    echo
    return 0
  fi

  echo "対話モデルを起動する: ${AUTHORING_MODE_STAGE_LABEL}（${AUTHORING_MODE_POSITION}）"
  "${AUTHORING_CMD[@]}"
  return $?
}

# ============================================================================
# --self-test
# ============================================================================

SELF_TEST_TOTAL=0
SELF_TEST_PASS=0
SELF_TEST_FAIL=0

record_result() {
  key="$1"
  status="$2"
  detail="$3"
  SELF_TEST_TOTAL=$((SELF_TEST_TOTAL + 1))
  if [ "${status}" = "PASS" ]; then
    SELF_TEST_PASS=$((SELF_TEST_PASS + 1))
  else
    SELF_TEST_FAIL=$((SELF_TEST_FAIL + 1))
  fi
  echo "[${status}] ${key} — ${detail}"
}

self_test() {
  script_path="$1"
  if ! tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/run-authoring-mode-selftest.XXXXXX" 2>/dev/null)" || [ -z "$tmp_dir" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼" >&2
    exit 2
  fi
  trap 'rm -rf "${tmp_dir}"' EXIT

  # --- 既定-無効 -----------------------------------------------------
  out="$(bash "${script_path}" 2>&1)"
  code=$?
  if [ "${code}" -eq 0 ]; then
    record_result "既定-無効" "PASS" "--enable 無しで終了コード 0"
  else
    record_result "既定-無効" "FAIL" "終了コードが ${code}（期待: 0）"
  fi

  # --- 既定-出力明示 ---------------------------------------------------
  case "${out}" in
    *無効*)
      record_result "既定-出力明示" "PASS" "出力に「無効」を含む"
      ;;
    *)
      record_result "既定-出力明示" "FAIL" "出力に「無効」を含まない: ${out}"
      ;;
  esac

  # --- 有効化-引数必須 -------------------------------------------------
  out2="$(bash "${script_path}" --enable 2>&1)"
  code2=$?
  if [ "${code2}" -eq 1 ]; then
    record_result "有効化-引数必須" "PASS" "--output 無しで終了コード 1"
  else
    record_result "有効化-引数必須" "FAIL" "終了コードが ${code2}（期待: 1）: ${out2}"
  fi

  # --- 試行-実行しない / 試行-コマンド形 --------------------------------
  dry_out="$(bash "${script_path}" --enable --dry-run --output "${tmp_dir}/out" 2>&1)"
  dry_code=$?
  if [ "${dry_code}" -eq 0 ]; then
    record_result "試行-実行しない" "PASS" "--dry-run で終了コード 0（claude を実行せず）"
  else
    record_result "試行-実行しない" "FAIL" "終了コードが ${dry_code}（期待: 0）: ${dry_out}"
  fi

  case "${dry_out}" in
    *claude*-p*|*claude*" -p "*)
      record_result "試行-コマンド形" "PASS" "出力コマンド文字列に claude と -p を含む"
      ;;
    *)
      case "${dry_out}" in
        *claude*)
          case "${dry_out}" in
            *-p*)
              record_result "試行-コマンド形" "PASS" "出力コマンド文字列に claude と -p を含む"
              ;;
            *)
              record_result "試行-コマンド形" "FAIL" "出力に -p を含まない: ${dry_out}"
              ;;
          esac
          ;;
        *)
          record_result "試行-コマンド形" "FAIL" "出力に claude を含まない: ${dry_out}"
          ;;
      esac
      ;;
  esac

  # --- 位置-定義 -------------------------------------------------------
  if grep -q "マニフェストの組み立ての前" "${script_path}" \
     && grep -q "AUTHORING_MODE_POSITION" "${script_path}"; then
    record_result "位置-定義" "PASS" "挟み込み位置の定義（マニフェストの組み立ての前）をスクリプトが保持"
  else
    record_result "位置-定義" "FAIL" "挟み込み位置の定義が見つからない"
  fi

  # --- 固有名-不在 -------------------------------------------------------
  # 検査対象パターンは、この自己テスト自身の走査でヒットしないよう、
  # ソース上は分割した文字列として組み立てる（実行時に連結して判定する）。
  p1="reverse-docs"; p1="${p1}-skills"
  p2="/Users"; p2="${p2}/"
  p3="Mac"; p3="${p3}Pro"
  p4="screen-manifest"; p4="${p4}.json"
  p5="docs/design"; p5="${p5}/screens"

  forbidden_found=""
  for pattern in "${p1}" "${p2}" "${p3}" "${p4}" "${p5}"; do
    if grep -qF "${pattern}" "${script_path}"; then
      forbidden_found="${forbidden_found} ${pattern}"
    fi
  done
  if [ -z "${forbidden_found}" ]; then
    record_result "固有名-不在" "PASS" "プロジェクト固有名・ローカル絶対パスを含まない"
  else
    record_result "固有名-不在" "FAIL" "禁止パターンを検出:${forbidden_found}"
  fi

  # --- 承認-既定で迂回なし ---------------------------------------------
  case "${dry_out}" in
    *acceptEdits*|*bypassPermissions*|*dontAsk*)
      record_result "承認-既定で迂回なし" "FAIL" "既定の出力に承認迂回の値を含む: ${dry_out}"
      ;;
    *)
      record_result "承認-既定で迂回なし" "PASS" "既定の出力に acceptEdits / bypassPermissions / dontAsk のいずれも含まない"
      ;;
  esac

  # --- 承認-明示指定 -----------------------------------------------------
  dry_out_explicit="$(bash "${script_path}" --enable --dry-run --output "${tmp_dir}/out" --permission-mode acceptEdits 2>&1)"
  case "${dry_out_explicit}" in
    *acceptEdits*)
      record_result "承認-明示指定" "PASS" "--permission-mode acceptEdits を明示したときのみ出力に含まれる"
      ;;
    *)
      record_result "承認-明示指定" "FAIL" "明示指定したのに出力に acceptEdits を含まない: ${dry_out_explicit}"
      ;;
  esac

  echo "実行 ${SELF_TEST_TOTAL} 件 / 成功 ${SELF_TEST_PASS} 件 / 失敗 ${SELF_TEST_FAIL} 件"

  trap - EXIT
  rm -rf "${tmp_dir}"

  if [ "${SELF_TEST_FAIL}" -eq 0 ]; then
    return 0
  fi
  return 1
}

# ============================================================================
# エントリポイント
# ============================================================================

main() {
  for arg in "$@"; do
    if [ "${arg}" = "--self-test" ]; then
      self_test "${BASH_SOURCE[0]}"
      return $?
    fi
  done

  run_main "$@"
  return $?
}

main "$@"
exit $?
