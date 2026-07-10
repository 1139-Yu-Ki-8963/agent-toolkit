#!/usr/bin/env bash
# audit-doc-consistency.sh — syncing-reverse-env のドキュメント整合性監査
#
# 用途:
#   確定仕様の正本 syncing-reverse-env-guide.html と、SKILL.md・
#   config.yml の間で、キー名・陳腐化表現・
#   返却フィールドの整合を機械的に検査する。仕様追従の抜け（typo・記述漏れ・
#   古い記述の残存）を早期検出するためのスキルローカル監査スクリプト。
#
# 検査内容（5 項目。「1」はキー突合単独、「2」は陳腐化 grep を FAIL/WARN の
#   2 系統に分けて出力するため、実行結果は 6 行になる）:
#   1. キー突合      : guide.html のプリフライト表（9 キー）・env_check 表
#                       （13 キー）を抽出し、SKILL.md 内で
#                       「キー: ...」の形式により明示的に列挙されているキー名が
#                       すべて guide のキー集合に含まれるかを確認する（typo 検出）。
#                       方向は「SKILL で言及されたキー ⊆ guide の
#                       キー集合」のみで、guide の全キーの言及は要求しない。
#   2a. 陳腐化表現(個数語): 「7 項目」「10 項目」「10/10」の残存を検出する
#                       （1 件でもあれば FAIL）。旧仕様（固定 7/10 項目時代）の
#                       記述が現行の「全項目」表現に追従できていない兆候。
#   2b. 陳腐化表現(lsof): 現行仕様を記述するファイル（guide.html を除く）に
#                       「lsof 単独前提」の行が残存していれば WARN する
#                       （block はしない）。「lsof / ss」の併記行は WSL2 対応の
#                       フォールバック表記であり正しい記述のため除外する。
#   3. config 整合   : config.yml の defaults 直下キー（ports / services /
#                       launch / l3_threshold_percent / max_loop /
#                       tag_namespace / diff_exclude / install_command /
#                       env_file_globs / bundler_cache_dirs / artifacts_root /
#                       node_modules_strategy / allow_mnt_fs / playwright_exec /
#                       original_sharing）
#                       がすべて guide.html 本文にキー名として登場するかを
#                       確認する。1 件でも欠ければ FAIL。
#   4. 返却ブロック契約: guide.html §8 の機械向け返却ブロックが持つべき
#                       10 フィールド名（status / scope / slot / ports /
#                       baseline_tag / static_diff / dynamic / env_check /
#                       artifacts / hint）の存在を確認する。1 件でも欠ければ
#                       FAIL。
#   5. 環境名直書き   : 命名規則の接頭辞 original-code- / reverse-code- の直後
#                       には常に <system> / <scope> 等のプレースホルダ（<...>）
#                       か glob（*）だけが来る。直後に具体値（英数字）が続く記述
#                       は <system>/<画面ID> のハードコード（プロジェクトに寄った
#                       実装）の兆候として FAIL。worktree 名・ポート・ガード等の
#                       判定文字列は source_repo / config.yml から実行時に解決し、
#                       具体値をファイルに焼き込まないことを保証する。
#
# 引数: なし（本スクリプト自身の配置場所からスキルフォルダ・skills ルートを
#   相対的に解決する。実行時の cwd に依存しない）
#
# 実行方法:
#   ./audit-doc-consistency.sh
#
# 出力: 検査ごとに「[PASS]/[WARN]/[FAIL] 検査名」の 1 行を標準出力へ出す。
#   FAIL の場合は詳細（該当キー・該当ファイル・該当行）を続けて出力する。
#
# 終了コード:
#   0 = 全検査が PASS または WARN のみ（FAIL 0 件）
#   1 = FAIL が 1 件以上

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SKILLS_ROOT="$(cd "${SKILL_DIR}/.." && pwd)"

GUIDE="${SKILL_DIR}/references/syncing-reverse-env-guide.html"
SKILL_MD="${SKILL_DIR}/SKILL.md"
CONFIG_YML="${SKILL_DIR}/config.yml"

for f in "$GUIDE" "$SKILL_MD" "$CONFIG_YML"; do
  if [ ! -f "$f" ]; then
    echo "エラー: 対象ファイルが存在しません: $f" >&2
    exit 1
  fi
done

FAIL_COUNT=0
WARN_COUNT=0

report_pass() { echo "[PASS] $1"; }
report_warn() { echo "[WARN] $1"; WARN_COUNT=$((WARN_COUNT + 1)); }
report_fail() {
  echo "[FAIL] $1"
  shift
  for detail in "$@"; do
    echo "    ${detail}"
  done
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

# ---------------------------------------------------------------------------
# 1. キー突合
# ---------------------------------------------------------------------------

preflight_keys="$(
  awk '/<h3>プリフライト/{flag=1} flag{print} flag && /<\/table>/{exit}' "$GUIDE" \
    | grep -oE '<td>[0-9]+</td><td>[a-z0-9-]+</td>' \
    | sed -E 's#<td>[0-9]+</td><td>([a-z0-9-]+)</td>#\1#'
)"
env_keys="$(
  # 見出し番号（7-2 / 8-2 等）は guide.html の改訂で章番号ごと繰り下がることが
  # あるため、番号に依存せず <h3> 見出し文言「環境同一性チェック」で一致させる
  # （本文中の <pre> フロー図等にも同じ文言が現れるため、<h3> タグ限定で誤爆を防ぐ）。
  awk '/<h3>[^<]*環境同一性チェック/{flag=1} flag{print} flag && /<\/table>/{exit}' "$GUIDE" \
    | grep -oE '<td>[0-9]+</td><td>[a-z0-9-]+</td>' \
    | sed -E 's#<td>[0-9]+</td><td>([a-z0-9-]+)</td>#\1#'
)"

preflight_count="$(printf '%s\n' "$preflight_keys" | grep -c . || true)"
env_count="$(printf '%s\n' "$env_keys" | grep -c . || true)"
all_keys="$(printf '%s\n%s\n' "$preflight_keys" "$env_keys" | grep -v '^$' | sort -u)"

key_check_details=()

if [ "$preflight_count" -ne 9 ]; then
  key_check_details+=("guide.html のプリフライトキー数が想定外: ${preflight_count} 件（期待 9 件）")
fi
if [ "$env_count" -ne 13 ]; then
  key_check_details+=("guide.html の env_check キー数が想定外: ${env_count} 件（期待 13 件）")
fi

# SKILL.md 内で「キー: A 〜 Z」のように明示的に列挙されている
# キー名だけを対象にする（無関係な kebab-case 語 = ブランチ名・スキル名等の
# 誤検出を避けるため、「キー:」直後の範囲に限定して抽出する）。
collect_mentioned_keys() {
  local file="$1"
  grep -oE 'キー[:：][^。）」]*' "$file" 2>/dev/null \
    | grep -oE '[a-z][a-z0-9]*(-[a-z0-9]+)+' \
    | sort -u || true
}

check_doc_keys() {
  local label="$1" file="$2"
  local mentioned
  mentioned="$(collect_mentioned_keys "$file")"
  local tok
  while IFS= read -r tok; do
    [ -z "$tok" ] && continue
    if ! printf '%s\n' "$all_keys" | grep -qx "$tok"; then
      key_check_details+=("${label} で guide 未定義のキー疑い（typo?）: ${tok}")
    fi
  done <<< "$mentioned"
}

check_doc_keys "SKILL.md" "$SKILL_MD"

if [ "${#key_check_details[@]}" -eq 0 ]; then
  report_pass "キー突合: guide.html プリフライト ${preflight_count} キー・env_check ${env_count} キーを抽出。SKILL.md の明示的キー列挙はすべて guide のキー集合に含まれる"
else
  report_fail "キー突合" "${key_check_details[@]}"
fi

# ---------------------------------------------------------------------------
# 2. 陳腐化 grep
# ---------------------------------------------------------------------------

TARGET_DIRS=("${SKILLS_ROOT}/syncing-reverse-env")

stale_hits="$(
  grep -rnE '7 項目|10 項目|10/10' "${TARGET_DIRS[@]}" \
    --include='*.md' --include='*.html' --include='*.yml' 2>/dev/null || true
)"

if [ -z "$stale_hits" ]; then
  report_pass "陳腐化表現(個数語): 「7 項目」「10 項目」「10/10」の残存なし"
else
  mapfile -t stale_lines <<< "$stale_hits"
  report_fail "陳腐化表現(個数語): 「7 項目」「10 項目」「10/10」が残存" "${stale_lines[@]}"
fi

# lsof: 現行仕様ファイルでの lsof 単独前提を WARN（guide.html は対象外。
# 「lsof / ss」併記のフォールバック表記は許容）
lsof_files="$(
  grep -rl 'lsof' "${TARGET_DIRS[@]}" \
    --include='*.md' --include='*.html' --include='*.yml' 2>/dev/null || true
)"

lsof_warn_lines=()
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ "$f" = "$GUIDE" ] && continue
  matches="$(grep -n 'lsof' "$f" | grep -v 'lsof / ss' || true)"
  if [ -n "$matches" ]; then
    while IFS= read -r m; do
      [ -z "$m" ] && continue
      lsof_warn_lines+=("${f}:${m}")
    done <<< "$matches"
  fi
done <<< "$lsof_files"

if [ "${#lsof_warn_lines[@]}" -eq 0 ]; then
  report_pass "陳腐化表現(lsof): guide.html 以外での「lsof」残存なし（許容リスト除外後）"
else
  report_warn "陳腐化表現(lsof): guide.html 以外に「lsof」が残存（許容リスト除外後・${#lsof_warn_lines[@]} 件）"
  for l in "${lsof_warn_lines[@]}"; do
    echo "    ${l}"
  done
fi

# ---------------------------------------------------------------------------
# 3. config 整合
# ---------------------------------------------------------------------------

config_keys=(ports services launch l3_threshold_percent max_loop tag_namespace diff_exclude install_command env_file_globs bundler_cache_dirs artifacts_root node_modules_strategy allow_mnt_fs playwright_exec original_sharing)

config_missing=()
for k in "${config_keys[@]}"; do
  if ! grep -qF "${k}:" "$GUIDE"; then
    config_missing+=("guide.html にキー名 ${k} が見当たらない")
  fi
done

if [ "${#config_missing[@]}" -eq 0 ]; then
  report_pass "config整合: config.yml defaults の ${#config_keys[@]} キーすべてが guide.html 本文に登場する"
else
  report_fail "config整合" "${config_missing[@]}"
fi

# ---------------------------------------------------------------------------
# 4. 返却ブロック契約
# ---------------------------------------------------------------------------

return_fields=(status scope slot ports baseline_tag static_diff dynamic env_check artifacts hint)

return_missing=()
for f in "${return_fields[@]}"; do
  if ! grep -qE "^  ${f}:" "$GUIDE"; then
    return_missing+=("guide.html §8 の返却ブロックにフィールド ${f} が見当たらない")
  fi
done

if [ "${#return_missing[@]}" -eq 0 ]; then
  report_pass "返却ブロック契約: guide.html §8 の返却ブロックに ${#return_fields[@]} フィールドすべてが存在する"
else
  report_fail "返却ブロック契約" "${return_missing[@]}"
fi

# ---------------------------------------------------------------------------
# 5. 環境名の直書き検出
# ---------------------------------------------------------------------------
# 命名規則の接頭辞 original-code- / reverse-code- の直後には、常に <system> /
# <scope> 等のプレースホルダ（<...>）か glob（*）だけが来る。直後に具体値（英数字）
# が続く記述は <system>/<画面ID> のハードコードであり、プロジェクトに寄った実装の
# 兆候として FAIL する。worktree 名・ポート・ガード等の判定文字列は source_repo /
# config.yml から実行時に解決し、具体値をファイルに焼き込まないことを保証する。
hardcode_hits="$(
  grep -rnE '(original|reverse)-code-[A-Za-z0-9]' "${TARGET_DIRS[@]}" \
    --include='*.md' --include='*.html' --include='*.yml' \
    --include='*.sh' --include='*.py' 2>/dev/null || true
)"

if [ -z "$hardcode_hits" ]; then
  report_pass "環境名直書き検出: original-code-/reverse-code- の直後は常にプレースホルダ（<...>）または glob（*）で、具体値の焼き込みなし"
else
  mapfile -t hardcode_lines <<< "$hardcode_hits"
  report_fail "環境名直書き検出: original-code-/reverse-code- の直後に具体値（<system>/<画面ID> のハードコード疑い）" "${hardcode_lines[@]}"
fi

# ---------------------------------------------------------------------------
# 集計
# ---------------------------------------------------------------------------

echo "---"
echo "FAIL: ${FAIL_COUNT} 件 / WARN: ${WARN_COUNT} 件"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
