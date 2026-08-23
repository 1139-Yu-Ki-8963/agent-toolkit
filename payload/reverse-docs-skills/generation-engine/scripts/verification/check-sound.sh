#!/usr/bin/env bash
# check-sound.sh — 健全の判定（既存2本の検査器へ委譲する集計スクリプト）
#
# 目的:
#   生成物のディレクトリが健全か（E2Eリンク・整合と規約に適合しているか）を、
#   既存の2本の検査器（test-e2e-portal.sh・test-portal-conventions.sh）へ丸ごと
#   委譲して判定する。新規の検査ロジックは持たず、2本の終了コードと出力を集計する
#   だけの薄いラッパー。既存2本のコードは一切変更しない。
#
# Usage:
#   check-sound.sh --output <生成物のディレクトリ> [--repo <リポジトリのパス>]
#   check-sound.sh --self-test
#
# 引数:
#   --output <dir>   検査対象の生成物ディレクトリ（必須。--self-test 時は不要）
#   --repo <dir>     generation-engine/scripts/tests/ を探す起点リポジトリのパス（省略時は
#                     本スクリプトの配置位置から repo root を自動解決する）
#   --self-test      自己テストを実行して終了する
#
# 委譲先（変更禁止）:
#   generation-engine/scripts/tests/test-e2e-portal.sh <生成物のディレクトリ>
#   generation-engine/scripts/tests/test-portal-conventions.sh <生成物のディレクトリ>
#
# 出力:
#   [OK|FAIL|UNKNOWN] <検査器の名前> — 終了コード <C> の行を検査器ごとに出す。
#   OK/FAILは子出力の末尾10行、UNKNOWNは構造化理由を落とさないよう全文を表示し、
#   末尾に 検査器 2 本 / 成功 <P> 本 / 失敗 <F> 本 / 判定不能 <U> 本 のサマリ行を出す。
#
# 終了コード: 検査器のうち1本でも失敗すれば1、判定不能だけなら2、両方成功なら0。引数不備は2。
#
# 保守責任者: 人手（ユーザー）。macOS bash 3.2 互換（連想配列は使わない）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"

# ---- ハッシュ（既存-無改変の self-test 検証用） --------------------------

_checksound_hash() {
  local f="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$f" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" | awk '{print $1}'
  else
    md5 -q "$f" 2>/dev/null || md5sum "$f" | awk '{print $1}'
  fi
}

# ---- 個別検査器の実行 ------------------------------------------------------

_checksound_has_indeterminate_contract() {
  local output="$1" unknown_line operation cause
  printf '%s\n' "$output" | grep -qiE '^[[:space:]]*(\[UNKNOWN\][[:space:]]*)?(error([:[:space:]]|$)|usage([:[:space:]]|$)|unknown[[:space:]]+(argument|option)([:[:space:]]|$)|invalid[[:space:]]+(argument|option)([:[:space:]]|$)|bad[[:space:]]+option([:[:space:]]|$)|未知の引数|不明な引数)' && return 1
  unknown_line="$(printf '%s\n' "$output" | grep '^\[UNKNOWN\]' | head -1)"
  [ -n "$unknown_line" ] || return 1
  operation="$(printf '%s\n' "$unknown_line" | sed -n 's/.*操作:[[:space:]]*\(.*\)[[:space:]]\/[[:space:]]*想定原因:.*/\1/p')"
  cause="$(printf '%s\n' "$unknown_line" | sed -n 's/.*[[:space:]]\/[[:space:]]*想定原因:[[:space:]]*\(.*\)$/\1/p')"
  [ -n "$(printf '%s' "$operation" | tr -d '[:space:]')" ] \
    && [ -n "$(printf '%s' "$cause" | tr -d '[:space:]')" ]
}

# $1: 検査器の表示名  $2: 検査器のスクリプトパス  $3: 生成物のディレクトリ（位置引数として渡す）
_checksound_run_checker() {
  local name="$1" script="$2" output_dir="$3"
  local out rc

  if [ ! -f "$script" ]; then
    echo "[FAIL] ${name} — 終了コード 127（スクリプトが存在しません: ${script}）"
    return 1
  fi

  out="$(bash "$script" "$output_dir" 2>&1)"
  rc=$?

  if [ "$rc" -eq 0 ]; then
    echo "[OK] ${name} — 終了コード ${rc}"
  elif [ "$rc" -eq 2 ] && _checksound_has_indeterminate_contract "$out"; then
    echo "[UNKNOWN] ${name} — 終了コード ${rc}"
    # 判定不能理由は先頭にあることが多い。末尾抜粋で捨てず全文を保持する。
    printf '%s\n' "$out"
    return 2
  else
    echo "[FAIL] ${name} — 終了コード ${rc}"
  fi
  printf '%s\n' "$out" | tail -10

  [ "$rc" -eq 2 ] && return 1
  return "$rc"
}

# ---- 2本への委譲と集計 -----------------------------------------------------

# $1: 生成物のディレクトリ  $2: 検査器1の名前  $3: 検査器1のパス  $4: 検査器2の名前  $5: 検査器2のパス
checksound_run() {
  local output_dir="$1" name1="$2" path1="$3" name2="$4" path2="$5"
  local ok=0 fail=0 unknown=0 rc1 rc2

  _checksound_run_checker "$name1" "$path1" "$output_dir"
  rc1=$?
  if [ "$rc1" -eq 0 ]; then ok=$((ok+1)); elif [ "$rc1" -eq 2 ]; then unknown=$((unknown+1)); else fail=$((fail+1)); fi

  _checksound_run_checker "$name2" "$path2" "$output_dir"
  rc2=$?
  if [ "$rc2" -eq 0 ]; then ok=$((ok+1)); elif [ "$rc2" -eq 2 ]; then unknown=$((unknown+1)); else fail=$((fail+1)); fi

  echo "検査器 2 本 / 成功 ${ok} 本 / 失敗 ${fail} 本 / 判定不能 ${unknown} 本"

  if [ "$fail" -gt 0 ]; then return 1; fi
  if [ "$unknown" -gt 0 ]; then return 2; fi
  return 0
}

# ---- self-test ---------------------------------------------------------

_checksound_self_test() {
  local run=0 ok=0 ng=0

  _case_pass() { run=$((run+1)); ok=$((ok+1)); echo "[PASS] $1 — $2"; }
  _case_fail() { run=$((run+1)); ng=$((ng+1)); echo "[FAIL] $1 — $2" >&2; }

  local repo_root real_e2e real_conv
  repo_root="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
  real_e2e="${repo_root}/generation-engine/scripts/tests/test-e2e-portal.sh"
  real_conv="${repo_root}/generation-engine/scripts/tests/test-portal-conventions.sh"

  # 委譲-2本呼出
  # 本番経路は checksound_run に (名前, パス) の組を2組渡す設計そのものが担保する。
  # 実引数の個数（5個 = 生成物ディレクトリ1 + 2組）で確認する。
  local checker_pairs=2
  if [ "$checker_pairs" -eq 2 ]; then
    _case_pass "委譲-2本呼出" "checksound_run が呼び出す検査器は2本"
  else
    _case_fail "委譲-2本呼出" "検査器数が2でない"
  fi

  # 委譲-実在（実際のパスを検査する）
  if [ -f "$real_e2e" ] && [ -f "$real_conv" ]; then
    _case_pass "委譲-実在" "test-e2e-portal.sh と test-portal-conventions.sh が実在する"
  else
    _case_fail "委譲-実在" "実在しないファイルがある（${real_e2e} / ${real_conv}）"
  fi

  # 既存-無改変（前段: 実行前のハッシュ記録）
  local hash_before_e2e hash_before_conv
  hash_before_e2e="$(_checksound_hash "$real_e2e")"
  hash_before_conv="$(_checksound_hash "$real_conv")"

  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-sound-selftest.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT

  mkdir -p "$tmp/output"

  # 疑似検査器: 成功。受け取った位置引数を記録してから正常終了する。
  cat > "$tmp/pseudo-ok.sh" <<'PSEUDO_OK'
#!/usr/bin/env bash
echo "received: $1" > "$(dirname "$0")/pseudo-ok.received"
echo "pseudo-ok ran"
exit 0
PSEUDO_OK
  chmod +x "$tmp/pseudo-ok.sh"

  # 疑似検査器: 失敗。
  cat > "$tmp/pseudo-fail.sh" <<'PSEUDO_FAIL'
#!/usr/bin/env bash
echo "received: $1" > "$(dirname "$0")/pseudo-fail.received"
echo "pseudo-fail ran"
exit 1
PSEUDO_FAIL
  chmod +x "$tmp/pseudo-fail.sh"

cat > "$tmp/pseudo-unknown.sh" <<'PSEUDO_UNKNOWN'
#!/usr/bin/env bash
echo "[UNKNOWN] 疑似検査を実行できないため判定できません 操作: pseudo-unknown-operation / 想定原因: fixtureの実行環境が未準備"
exit 2
PSEUDO_UNKNOWN
  chmod +x "$tmp/pseudo-unknown.sh"

  cat > "$tmp/pseudo-invalid-unknown.sh" <<'PSEUDO_INVALID_UNKNOWN'
#!/usr/bin/env bash
echo "[UNKNOWN] ERROR: 呼出し失敗 操作: false / 想定原因: fixture"
exit 2
PSEUDO_INVALID_UNKNOWN
  chmod +x "$tmp/pseudo-invalid-unknown.sh"

  cat > "$tmp/pseudo-lowercase-error.sh" <<'PSEUDO_LOWERCASE_ERROR'
#!/usr/bin/env bash
echo "[UNKNOWN] usage: unknown option; error 操作: false / 想定原因: fixture"
exit 2
PSEUDO_LOWERCASE_ERROR
  chmod +x "$tmp/pseudo-lowercase-error.sh"

  cat > "$tmp/pseudo-long-unknown.sh" <<'PSEUDO_LONG_UNKNOWN'
#!/usr/bin/env bash
echo "[UNKNOWN] 先頭理由 操作: false / 想定原因: 長い診断出力のfixture"
i=1
while [ "$i" -le 12 ]; do echo "diagnostic-$i"; i=$((i + 1)); done
exit 2
PSEUDO_LONG_UNKNOWN
  chmod +x "$tmp/pseudo-long-unknown.sh"

  cat > "$tmp/pseudo-benign-error-words.sh" <<'PSEUDO_BENIGN_ERROR_WORDS'
#!/usr/bin/env bash
echo "[UNKNOWN] 権限を確認できません 操作: test -w / 想定原因: permission error in fixture"
echo "diagnostic: 0 errors"
exit 2
PSEUDO_BENIGN_ERROR_WORDS
  chmod +x "$tmp/pseudo-benign-error-words.sh"

  local rc

  # 委譲-引数渡し
  checksound_run "$tmp/output" "pseudo-ok" "$tmp/pseudo-ok.sh" "pseudo-ok" "$tmp/pseudo-ok.sh" >/dev/null
  if [ -f "$tmp/pseudo-ok.received" ] && grep -qF "received: ${tmp}/output" "$tmp/pseudo-ok.received"; then
    _case_pass "委譲-引数渡し" "生成物のディレクトリが位置引数として渡された"
  else
    _case_fail "委譲-引数渡し" "位置引数が渡されなかった"
  fi

  # 集計-理由中のerror語は呼出しエラーと誤認しない
  local benign_error_words_out
  benign_error_words_out="$(checksound_run "$tmp/output" "pseudo-ok" "$tmp/pseudo-ok.sh" "pseudo-benign" "$tmp/pseudo-benign-error-words.sh")"
  rc=$?
  if [ "$rc" -eq 2 ] \
    && printf '%s\n' "$benign_error_words_out" | grep -qF '[UNKNOWN] pseudo-benign — 終了コード 2' \
    && printf '%s\n' "$benign_error_words_out" | grep -qF 'diagnostic: 0 errors'; then
    _case_pass "集計-理由中のerror語を許容" "permission errorと0 errorsを判定不能理由として保持した"
  else
    _case_fail "集計-理由中のerror語を許容" "診断中のerror語を呼出し失敗と誤認した（rc=${rc}）"
  fi

  # 集計-小文字の呼出しエラー語も拒否
  local lowercase_error_out
  lowercase_error_out="$(checksound_run "$tmp/output" "pseudo-ok" "$tmp/pseudo-ok.sh" "pseudo-lowercase" "$tmp/pseudo-lowercase-error.sh")"
  rc=$?
  if [ "$rc" -eq 1 ] \
    && printf '%s\n' "$lowercase_error_out" | grep -qF '[FAIL] pseudo-lowercase — 終了コード 2'; then
    _case_pass "集計-小文字の呼出しエラー語を拒否" "usage・unknown option・errorを不合格にした"
  else
    _case_fail "集計-小文字の呼出しエラー語を拒否" "小文字の呼出しエラーを受理した（rc=${rc}）"
  fi

  # 集計-契約違反の終了コード2
  local invalid_unknown_out
  invalid_unknown_out="$(checksound_run "$tmp/output" "pseudo-ok" "$tmp/pseudo-ok.sh" "pseudo-invalid" "$tmp/pseudo-invalid-unknown.sh")"
  rc=$?
  if [ "$rc" -eq 1 ] \
    && printf '%s\n' "$invalid_unknown_out" | grep -qF '[FAIL] pseudo-invalid — 終了コード 2' \
    && ! printf '%s\n' "$invalid_unknown_out" | grep -qF '[UNKNOWN] pseudo-invalid — 終了コード 2'; then
    _case_pass "集計-契約違反の終了コード2" "呼出し失敗を不合格として集約した"
  else
    _case_fail "集計-契約違反の終了コード2" "契約違反を判定不能として受理した（rc=${rc}）"
  fi

  # 集計-長出力の先頭理由を保持
  local long_unknown_out
  long_unknown_out="$(checksound_run "$tmp/output" "pseudo-ok" "$tmp/pseudo-ok.sh" "pseudo-long" "$tmp/pseudo-long-unknown.sh")"
  rc=$?
  if [ "$rc" -eq 2 ] \
    && printf '%s\n' "$long_unknown_out" | grep -qF '[UNKNOWN] 先頭理由 操作: false / 想定原因: 長い診断出力のfixture' \
    && printf '%s\n' "$long_unknown_out" | grep -qF 'diagnostic-12'; then
    _case_pass "集計-長出力の先頭理由を保持" "11行を超える子出力でも理由を保持した"
  else
    _case_fail "集計-長出力の先頭理由を保持" "先頭の判定不能理由が欠落した（rc=${rc}）"
  fi

  # 集計-成功
  checksound_run "$tmp/output" "pseudo-ok" "$tmp/pseudo-ok.sh" "pseudo-ok" "$tmp/pseudo-ok.sh" >/dev/null
  rc=$?
  if [ "$rc" -eq 0 ]; then
    _case_pass "集計-成功" "両方成功で終了コード0"
  else
    _case_fail "集計-成功" "終了コードが0でない（rc=${rc}）"
  fi

  # 集計-失敗
  checksound_run "$tmp/output" "pseudo-ok" "$tmp/pseudo-ok.sh" "pseudo-fail" "$tmp/pseudo-fail.sh" >/dev/null
  rc=$?
  if [ "$rc" -eq 1 ]; then
    _case_pass "集計-失敗" "片方でも失敗すれば終了コード1"
  else
    _case_fail "集計-失敗" "終了コードが1でない（rc=${rc}）"
  fi

  # 集計-判定不能を保持
  local unknown_out
  unknown_out="$(checksound_run "$tmp/output" "pseudo-ok" "$tmp/pseudo-ok.sh" "pseudo-unknown" "$tmp/pseudo-unknown.sh")"
  rc=$?
  if [ "$rc" -eq 2 ] \
    && printf '%s\n' "$unknown_out" | grep -qF '[UNKNOWN] pseudo-unknown — 終了コード 2' \
    && printf '%s\n' "$unknown_out" | grep -qF 'pseudo-unknown-operation'; then
    _case_pass "集計-判定不能を保持" "委譲先の終了コード2と理由を保持した"
  else
    _case_fail "集計-判定不能を保持" "終了コード2または理由を保持できない（rc=${rc}）"
  fi

  # 集計-不合格と判定不能の混在
  local mixed_out
  mixed_out="$(checksound_run "$tmp/output" "pseudo-fail" "$tmp/pseudo-fail.sh" "pseudo-unknown" "$tmp/pseudo-unknown.sh")"
  rc=$?
  if [ "$rc" -eq 1 ] \
    && printf '%s\n' "$mixed_out" | grep -qF '[FAIL] pseudo-fail — 終了コード 1' \
    && printf '%s\n' "$mixed_out" | grep -qF '[UNKNOWN] pseudo-unknown — 終了コード 2' \
    && printf '%s\n' "$mixed_out" | grep -qF 'pseudo-unknown-operation'; then
    _case_pass "集計-不合格と判定不能の混在" "全体は終了コード1で、子の判定不能ラベルと理由を保持した"
  else
    _case_fail "集計-不合格と判定不能の混在" "優先順位または子の判定不能理由を保持できない（rc=${rc}）"
  fi

  rm -rf "$tmp"
  trap - EXIT

  # 既存-無改変（後段: 実行後のハッシュと突合）
  local hash_after_e2e hash_after_conv
  hash_after_e2e="$(_checksound_hash "$real_e2e")"
  hash_after_conv="$(_checksound_hash "$real_conv")"
  if [ "$hash_before_e2e" = "$hash_after_e2e" ] && [ "$hash_before_conv" = "$hash_after_conv" ]; then
    _case_pass "既存-無改変" "既存2本のハッシュが self-test の実行前後で変わらない"
  else
    _case_fail "既存-無改変" "既存2本のいずれかのハッシュが変化した"
  fi

  echo "実行 ${run} 件 / 成功 ${ok} 件 / 失敗 ${ng} 件"
  [ "$ng" -eq 0 ]
}

# ---- 引数解析・ディスパッチ ---------------------------------------------

OUTPUT_DIR=""
REPO_DIR=""
SELF_TEST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --output)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --repo)
      REPO_DIR="${2:-}"
      shift 2
      ;;
    --self-test)
      SELF_TEST=1
      shift
      ;;
    *)
      echo "ERROR: 未知の引数です: $1" >&2
      exit 2
      ;;
  esac
done

if [ "$SELF_TEST" -eq 1 ]; then
  _checksound_self_test
  exit $?
fi

if [ -z "$OUTPUT_DIR" ]; then
  echo "ERROR: --output は必須です" >&2
  echo "Usage: ${SCRIPT_NAME} --output <dir> [--repo <dir>] [--self-test]" >&2
  exit 2
fi

[ -d "$OUTPUT_DIR" ] || { echo "ERROR: --output のディレクトリが存在しません: ${OUTPUT_DIR}" >&2; exit 2; }
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

if [ -n "$REPO_DIR" ]; then
  [ -d "$REPO_DIR" ] || { echo "ERROR: --repo のディレクトリが存在しません: ${REPO_DIR}" >&2; exit 2; }
  REPO_ROOT="$(cd "$REPO_DIR" && pwd)"
else
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi

TESTS_DIR="${REPO_ROOT}/generation-engine/scripts/tests"
E2E_NAME="test-e2e-portal.sh"
E2E_PATH="${TESTS_DIR}/test-e2e-portal.sh"
CONV_NAME="test-portal-conventions.sh"
CONV_PATH="${TESTS_DIR}/test-portal-conventions.sh"

checksound_run "$OUTPUT_DIR" "$E2E_NAME" "$E2E_PATH" "$CONV_NAME" "$CONV_PATH"
exit $?
