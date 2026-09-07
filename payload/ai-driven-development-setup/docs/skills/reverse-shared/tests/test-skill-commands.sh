#!/usr/bin/env bash
set -u

# test-skill-commands.sh — 全機能のSKILL.mdが書くコマンドを実際に走らせ、
# 引数不足で落ちないことを確かめる（reverse単位の共有部品の検収。
# 第1回改善指示書1-35追記への対応）
#
# 使い方:
#   test-skill-commands.sh [<docs/skills のルート>]
#
# 判定（1コマンドあたり）:
#   標準出力・標準エラーに「使い方:」「usage」「引数不正」「余分な引数」のいずれかを含む → 引数不足（使い方）
#   標準出力・標準エラーに「要確認-判定不能」を含み、かつ終了コードが0でない
#     → 引数不足（判定不能）
#   終了コードが128以上、または127 → 引数不足ではなく落ちた（シグナル死または依存するコマンドの不在。異常終了）
#     実例: validate-rule-definitions.sh が SIGPIPE で rc=141（1-35追記の完了条件「落ちるものが0件」）
#   「判定不能」だけの広い一致にしない理由: このリポジトリは「設定-判定不能」
#   （run.json不在・形式不正等の設定不備）という別の語彙を同じ単語で持ち、
#   これは他の「-不在」系の早期終了と同種の正当な既定挙動である
#   （record-acceptance.shの自己テストが多数のケースで意図的に確かめている）。
#   広く一致させると、標本のrun.json未整備という本テスト側の限界を
#   ドキュメント側の不具合として誤検出する（本テスト作成時に実測）。
#   「要確認-判定不能」に絞ることで、コーディネーターが示した実例
#   （要確認の観点を持つ合格の記録が--run無しで誤って不合格になる型）だけを
#   対象にする。
#   上記のいずれでもない → 合格（内容の正否は問わない。文書・一覧の不在で
#     終わる実行は合格として扱う）
#
#   合格は既定値である。3つの型のいずれにも当たらない終了はすべて合格に分類する。
#   実測では抽出した66件のうち52件が非0終了であり、その大半は標本の文書・一覧が
#   無いことによる正当な早期終了である。この検査は引数不足と異常終了だけを見る。
#
# 標本:
#   各コマンドの `<...>` 引数は、位置ごとに新規のダミーディレクトリへ
#   置き換える。ただし次の語を含む引数は、使い方の誤りとして誤判定される
#   実測（本テスト作成時に検出）を避けるため個別の値へ置き換える。
#     種別                → screen（reverse-shared/references/unit-kinds.jsonの
#                           keyの1つ。extract-code-readings.shはこの値でしか
#                           使い方の誤りを回避できないことを実測で確認した）
#     識別子              → unit-001
#     文書名              → 業務仕様書
#     sha256              → 0を64個並べた文字列
#     合格|不合格          → 合格
#     観点=...            → 自明性=合
#     単位をカンマ区切り    → reverse
#     キー                → 対象リポジトリ
#   末尾が.md/.jsonの引数はファイル（touchで作る空ファイル）として扱う。
#   docs/rules のルート・docs/skills のルートは、このリポジトリ自身の
#   実物（${SKILLS_ROOT}/../rules・$SKILLS_ROOTそのもの）を渡す。
#   validate-rule-definitions.sh がダミーの空ディレクトリでは「使い方:」を
#   誤って出す実測（parent.ymlの構造チェックによる案内文）を避けるため。
#   read専用のスクリプト（build-derived-*.shの書き込み先を除く）にしか
#   使わないため、実物を渡しても対象リポジトリ自身を書き換えない。
#   置き換えるのは語の全体が <...> の引数だけである。語の途中に <...> を含む形
#   （--out <写し>/docs/design/lists・--judged <文書名>=<sha256>;...の2件）は
#   置き換えず、字面のまま渡す。いずれも引数の不足ではなく値の形の例示である。
#
#   check-acceptance-record.shは「要確認の観点を持つ合格の記録は--run無しでは
#   要確認-判定不能になる」という、静的な引数の数だけでは検出できない不具合の
#   型を持つ（第1回改善指示書1-35追記）。この型を実際に検出できることを
#   別途、陽性・陰性の対で確かめる（build_positive_control_fixture）。
#
# 終了コード:
#   0 = 抽出したコマンドすべてで引数不足なし、かつ陽性・陰性対照も正しい
#   1 = 1件以上引数不足、または陽性・陰性対照のいずれかが誤り
#
# 保守責任者: 人手（ユーザー）。SKILL.mdのコマンド記法（コードフェンス・
#   インラインバッククォート）を変える場合、または新しい種類の引数不足の
#   型（本ファイルの「判定」節にある3種以外）を見つけた場合は、抽出規則・
#   置き換え表・判定式を本スクリプトと
#   docs/design/skills/reverse-shared/詳細設計書.md を同時に更新する。
#
# 廃棄条件: SKILL.mdのコマンド記法を構造化データ（JSON等）に変えた時。
#
# 既知の限界:
#   1. パイプの前段が落ちても検知できない。set -o pipefail を持たないスクリプトでは、
#      前段がシグナルで死んでも終了コードは後段の値になる。今回直した SIGPIPE と
#      同じ型の欠陥が他に残っていても、この検査は合格を返す。
#   2. 省略可の記法 [...] は中身ごと削除するため、省略可の引数は一度も渡されない。
#      本検査作成時点の該当は 5 箇所である。内訳は --until が 1、--reason が 2、
#      --taxonomy が 1、--unit が 1 である。
#   3. 対象は引数を 1 つ以上持つ言及に限る。引数を持たない裸の言及は走らせない。
#      本検査作成時点の裸の言及は 19 件（重複を除くと 17 本）である。そのうち
#      引数付きの言及を他所に持たず一度も走らないのは start-run.sh と
#      check-doc-heading-addendum.sh の 2 本である。
#   4. 到達の深さは標本に依る。抽出 66 件のうち終了コード 0 は 14 件であり、残りは
#      標本の文書・一覧が無いことによる早期終了である。本来のロジックの奥までは
#      到達しない。
#   5. set -u の未定義の参照で落ちた実行は合格に分類する。終了コードが 1 になり、
#      正当な早期終了と見分けられないためである。
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="${1:-${SCRIPT_DIR}/../..}"
SKILLS_ROOT="$(cd "$SKILLS_ROOT" && pwd)" || { echo "docs/skills のルートを解決できません" >&2; exit 2; }
REAL_RULES_ROOT="$(cd "${SKILLS_ROOT}/../rules" 2>/dev/null && pwd)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-skill-commands.XXXXXX")" || { echo "一時領域を作成できません" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

total=0
bad=0

# --- 抽出 ---------------------------------------------------------------

# コードフェンス(言語指定が bash・sh・無指定のもの。インデント許容)内を1コマンド1行へ結合する。
# 末尾が\の行は次行と連結する。
# 他言語（yaml・json・diff 等）のフェンスも開始・終了は追跡し、内容だけ捨てる（閉じ行を開始と誤認しないため）。
extract_fenced() {
  local file="$1"
  awk '
    !infence && /^[[:space:]]*```/ {
      infence=1; buf=""
      capture = ($0 ~ /^[[:space:]]*```(bash|sh)?[[:space:]]*$/) ? 1 : 0
      next
    }
    infence && /^[[:space:]]*```[[:space:]]*$/ {
      infence=0
      if (capture) print buf
      next
    }
    infence && !capture { next }
    infence {
      line=$0
      sub(/^[[:space:]]+/, "", line)
      if (buf != "") buf = buf " "
      if (line ~ /\\$/) {
        sub(/\\$/, "", line)
        buf = buf line
      } else {
        buf = buf line
        print buf
        buf = ""
      }
    }
  ' "$file"
}

# インライン `...` スパンを1行1件で出す。
extract_inline() {
  local file="$1"
  grep -Eo '`[^`]+`' "$file" | sed -e 's/^`//' -e 's/`$//'
}

# 候補行から、実行対象のコマンドだけを1行1件で残す。
#   - --self-test を含む行は除外
#   - [ ... ] （省略可の記法）は削除
#   - 引用符は除去（このリポジトリのコマンド例に埋め込み空白を持つ引用は無い）
#   - scripts/*.sh を含み、かつスクリプトパスの後に引数を1つ以上持つ行だけ残す
#     （bash前置は任意。裸の言及は除外）
normalize_and_filter() {
  local line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      *--self-test*) continue ;;
    esac
    line="$(printf '%s' "$line" | sed -E 's/\[[^]]*\]//g')"
    line="$(printf '%s' "$line" | tr -d '"')"
    # <...>内の空白（例: <docs/rules のルート>）は、後段の空白区切りの
    # トークン化で分断されると1トークンとして復元できない。トークン化の
    # 前にここで_SP_へ置き換えて1トークンへ束ねる（substitute_tokenの
    # case文もこのマーカー形で照合する）。
    line="$(printf '%s' "$line" | sed -E -e 's#<([^<>]*) ([^<>]*)>#<\1_SP_\2>#g' -e 's#<([^<>]*) ([^<>]*)>#<\1_SP_\2>#g')"
    line="$(printf '%s' "$line" | sed -E -e 's/[[:space:]]+/ /g' -e 's/^ //' -e 's/ $//')"
    [ -n "$line" ] || continue
    case "$line" in
      *scripts/*.sh*) : ;;
      *) continue ;;
    esac
    local rest script_tok
    if [ "${line%% *}" = "bash" ]; then
      rest="${line#bash }"
    else
      rest="$line"
    fi
    script_tok="${rest%% *}"
    [ "$script_tok" != "$rest" ] || continue
    echo "$line"
  done
}

# 標準出力へ「<機能名>\t<コマンド文字列>」を1行1件で出す。
extract_all() {
  local f skill
  for f in "${SKILLS_ROOT}"/*/SKILL.md; do
    [ -f "$f" ] || continue
    skill="$(basename "$(dirname "$f")")"
    { extract_fenced "$f"; extract_inline "$f"; } | normalize_and_filter | while IFS= read -r c; do
      printf '%s\t%s\n' "$skill" "$c"
    done
  done
}

# --- 置き換え -------------------------------------------------------------

ZERO_SHA="0000000000000000000000000000000000000000000000000000000000000000"

# $1: `<...>` を含む1トークン（山括弧を含む）。標準出力へ置き換え値を出す。
# $2: このコマンド呼び出し専用のダミー領域（ディレクトリ。実在する）。
substitute_token() {
  local tok="$1" dummy="$2"
  case "$tok" in
    *種別*) echo "screen"; return ;;
    *識別子*) echo "unit-001"; return ;;
    "<キー>") echo "対象リポジトリ"; return ;;
    *文書名*) echo "業務仕様書"; return ;;
    *sha256*) echo "$ZERO_SHA"; return ;;
    "<合格|不合格>") echo "合格"; return ;;
    *観点=*) echo "自明性=合"; return ;;
    *単位をカンマ区切り*) echo "reverse"; return ;;
    "<docs/rules_SP_のルート>")
      if [ -n "$REAL_RULES_ROOT" ]; then echo "$REAL_RULES_ROOT"; else echo "$dummy"; fi
      return ;;
    "<docs/skills_SP_のルート>") echo "$SKILLS_ROOT"; return ;;
    *.md\>|*.json\>)
      : > "${dummy}.placeholder"
      echo "${dummy}.placeholder"
      return ;;
    *)
      mkdir -p "$dummy"
      echo "$dummy"
      return ;;
  esac
}

# --- 判定 -----------------------------------------------------------------

# 1コマンドの出力と終了コードから判定の名前を返す。
# 「合格」「不合格-使い方」「不合格-判定不能」「不合格-異常終了」のいずれか。
# 対照もこの関数を通す。判定の条件を壊したときに対照が落ちるようにするため
# （反証で、対照が各自 grep を再実装していて判定を検証していなかった）。
judge_of() {
  local out="$1" rc="$2"
  if printf '%s\n' "$out" | grep -qi '使い方:\|usage\|引数不正\|余分な引数'; then
    echo "不合格-使い方"
  elif printf '%s\n' "$out" | grep -q '要確認-判定不能' && [ "$rc" -ne 0 ]; then
    echo "不合格-判定不能"
  elif [ "$rc" -ge 128 ] || [ "$rc" -eq 127 ]; then
    echo "不合格-異常終了"
  else
    echo "合格"
  fi
}

# 1コマンドを走らせ、出力・終了コード・判定の名前を大域の変数へ置く。
# 標準出力と標準エラーの両方を捕捉し、終了コードを判定へ渡す。
# run_one もこの関数を通す。配管を1箇所へ集め、対照が本番の経路を守るため
# （反証とレビューで、対照が本番の通らない複製を守っていた）。
# コマンド置換で呼ぶと部分シェルになり大域の変数が伝わらないため、
# 戻り値を標準出力で返さない。
RJ_OUT=""
RJ_RC=0
RJ_JUDGE=""
run_and_judge() {
  local skill_dir="$1" script_rel="$2"
  shift 2
  RJ_OUT="$(cd "$skill_dir" && /bin/bash "$script_rel" ${@+"$@"} 2>&1)"
  RJ_RC=$?
  RJ_JUDGE="$(judge_of "$RJ_OUT" "$RJ_RC")"
}

# --- 実行 -----------------------------------------------------------------

# 1件のコマンド文字列を走らせ、判定を1行標準出力へ書く。
# $1: 機能フォルダ名  $2: コマンド文字列（bash前置は任意）
run_one() {
  local skill="$1" cmdline="$2" skill_dir="${SKILLS_ROOT}/${1}"
  local tokens
  # shellcheck disable=SC2206
  tokens=($cmdline)
  local start=0
  if [ "${tokens[0]}" = "bash" ]; then
    start=1
  fi
  local script_rel="${tokens[$start]}"
  start=$((start + 1))

  total=$((total + 1))
  local call_base="${TMP}/call-${total}"

  local args=()
  local n=${#tokens[@]}
  local i=$start tok sub
  local idx=0
  while [ $i -lt $n ]; do
    tok="${tokens[$i]}"
    case "$tok" in
      \<*\>)
        idx=$((idx + 1))
        sub="$(substitute_token "$tok" "${call_base}-${idx}")"
        args+=("$sub")
        ;;
      *) args+=("$tok") ;;
    esac
    i=$((i + 1))
  done

  local script_dir_part script_base script_abs_dir
  script_dir_part="$(dirname "$script_rel")"
  script_base="$(basename "$script_rel")"
  script_abs_dir="$(cd "$skill_dir" 2>/dev/null && cd "$script_dir_part" 2>/dev/null && pwd)"
  if [ -z "$script_abs_dir" ] || [ ! -f "${script_abs_dir}/${script_base}" ]; then
    echo "[FAIL 引数不足-スクリプト不在] ${skill}: ${script_rel}"
    bad=$((bad + 1))
    return
  fi

  run_and_judge "$skill_dir" "$script_rel" ${args[@]+"${args[@]}"}
  local out="$RJ_OUT" rc="$RJ_RC" judge="$RJ_JUDGE"

  if [ "$judge" = "合格" ]; then
    echo "[PASS rc=${rc}] ${skill}: ${script_rel} ${args[*]:-}"
  else
    echo "[FAIL ${judge} rc=${rc}] ${skill}: ${script_rel} ${args[*]:-}"
    printf '%s\n' "$out" | head -3 | sed 's/^/    /'
    bad=$((bad + 1))
  fi
}

# --- 判定不能の陽性・陰性対照 -----------------------------------------------
# check-acceptance-record.sh は「要確認の観点を持つ合格の記録は--run無しでは
# 要確認-判定不能になる」という、静的な引数の数だけでは検出できない不具合の
# 型を持つ（第1回改善指示書1-35追記の実例）。この型を検出できることを
# reverse-shared/scripts/record-acceptance.shの自己テストの「要確認を含む
# 合格の記録」ケースと同じ手順で標本を作り、確かめる。
build_positive_control_fixture() {
  local pc="$1"
  rm -rf "$pc"
  mkdir -p "${pc}/target/docs/design/apis/api_get_orders" "${pc}/run/confirmations"

  cat > "${pc}/run/run.json" << 'RUNJSON'
{
  "実行の識別子": "test-skill-commands-pc",
  "テスト設計書の出力": "出力する"
}
RUNJSON

  echo "# API基本設計書" > "${pc}/target/docs/design/apis/api_get_orders/API基本設計書.md"
  echo "# API単体テスト設計書" > "${pc}/target/docs/design/apis/api_get_orders/API単体テスト設計書.md"

  local sha1 sha2 judged
  sha1="$(shasum -a 256 "${pc}/target/docs/design/apis/api_get_orders/API基本設計書.md" | awk '{print $1}')"
  sha2="$(shasum -a 256 "${pc}/target/docs/design/apis/api_get_orders/API単体テスト設計書.md" | awk '{print $1}')"
  judged="API基本設計書.md=${sha1};API単体テスト設計書.md=${sha2}"

  cat > "${pc}/run/confirmations/確認事項の記録.md" << 'CONFEOF'
| キー | 単位 | 種類 | 事項 | 既定 | 反映先 | 回答 | 状態 |
|---|---|---|---|---|---|---|---|
| 性能-数値目標 | api/get_orders | 確認事項 | 性能の数値目標が無い | 既定なし | 方式設計書 | 未回答 | 未回答 |
CONFEOF

  /bin/bash "${SKILLS_ROOT}/reverse-shared/scripts/record-acceptance.sh" "${pc}/target" --run "${pc}/run" --kind api --unit "api/get_orders" \
    --verdict 合格 --viewpoints "非機能の方式の確定=要確認" --judged "$judged" --reason "性能-数値目標は要確認事項一覧に登録済み" > /dev/null 2>&1
}

check_judgenone_detection() {
  local pc="${TMP}/pc-fixture"
  build_positive_control_fixture "$pc"
  local target="${SKILLS_ROOT}/reverse-shared/scripts/check-acceptance-record.sh"
  [ -f "$target" ] || { echo "[FAIL 対照] 判定不能-陽性陰性対照-検査対象不在: ${target}"; return 1; }

  local out_with out_without rc_with rc_without
  out_with="$(/bin/bash "$target" "${pc}/target" --kind api --unit "api/get_orders" --run "${pc}/run" 2>&1)"
  rc_with=$?
  out_without="$(/bin/bash "$target" "${pc}/target" --kind api --unit "api/get_orders" 2>&1)"
  rc_without=$?

  local verdict_with verdict_without ok=1
  verdict_with="$(judge_of "$out_with" "$rc_with")"
  verdict_without="$(judge_of "$out_without" "$rc_without")"
  if [ "$verdict_with" != "合格" ]; then
    echo "[FAIL 対照] 判定不能-陰性対照: --run 付きの正しい呼び出しを判定が「${verdict_with}」に分類した（期待: 合格）"
    ok=0
  fi
  if [ "$verdict_without" != "不合格-判定不能" ]; then
    echo "[FAIL 対照] 判定不能-陽性対照: --run 無しの呼び出しを判定が「${verdict_without}」に分類した（期待: 不合格-判定不能）"
    ok=0
  fi

  if [ "$ok" -eq 1 ]; then
    echo "[PASS 対照] 判定不能-陽性陰性対照: --run 無しのときだけ判定が「不合格-判定不能」に分類する"
    return 0
  fi
  return 1
}

check_usage_detection() {
  local target="${SKILLS_ROOT}/reverse-shared/scripts/check-entry.sh"
  [ -f "$target" ] || { echo "[FAIL 対照] 使い方-陽性対照-検査対象不在: ${target}"; return 1; }
  local out rc verdict
  out="$(/bin/bash "$target" "${TMP}" 2>&1)"
  rc=$?
  verdict="$(judge_of "$out" "$rc")"
  if [ "$verdict" = "不合格-使い方" ]; then
    echo "[PASS 対照] 使い方-陽性対照: 引数不足の実例を判定が「不合格-使い方」に分類する"
    return 0
  fi
  echo "[FAIL 対照] 使い方-陽性対照: 判定が「${verdict}」を返した（期待: 不合格-使い方）"
  return 1
}

check_abnormal_exit_detection() {
  local out rc verdict_abn verdict_ok ok=1
  # シグナルで落ちた実例（終了コード 141）を作る。
  out="$(/bin/bash -c 'kill -PIPE $$' 2>&1)"
  rc=$?
  if [ "$rc" -ne 141 ]; then
    echo "[FAIL 対照] 異常終了-陽性対照: 終了コード141を作れなかった（実際: ${rc}）"
    return 1
  fi
  verdict_abn="$(judge_of "$out" "$rc")"
  if [ "$verdict_abn" != "不合格-異常終了" ]; then
    echo "[FAIL 対照] 異常終了-陽性対照: 判定が「${verdict_abn}」を返した（期待: 不合格-異常終了）"
    ok=0
  fi
  # 3型のいずれにも当たらない終了は合格に分類する。
  verdict_ok="$(judge_of "文書が見つかりません" 2)"
  if [ "$verdict_ok" != "合格" ]; then
    echo "[FAIL 対照] 異常終了-陰性対照: 3型に当たらない終了を判定が「${verdict_ok}」に分類した（期待: 合格）"
    ok=0
  fi
  # しきい値の境界を固定する。126 は合格、128 は異常終了である。
  # 127 は依存するコマンドが無いときの終了コードであり、異常終了に数える。
  local verdict_126 verdict_128
  verdict_126="$(judge_of "" 126)"
  verdict_128="$(judge_of "" 128)"
  if [ "$verdict_126" != "合格" ]; then
    echo "[FAIL 対照] 異常終了-境界: 終了コード126を判定が「${verdict_126}」に分類した（期待: 合格）"
    ok=0
  fi
  if [ "$verdict_128" != "不合格-異常終了" ]; then
    echo "[FAIL 対照] 異常終了-境界: 終了コード128を判定が「${verdict_128}」に分類した（期待: 不合格-異常終了）"
    ok=0
  fi

  # 依存するコマンドが無いときの終了コード127も異常終了に数える。
  local verdict_127nf
  verdict_127nf="$(judge_of "bash: nosuchcmd: command not found" 127)"
  if [ "$verdict_127nf" != "不合格-異常終了" ]; then
    echo "[FAIL 対照] 異常終了-依存不在: 終了コード127を「${verdict_127nf}」に分類した（期待: 不合格-異常終了）"
    ok=0
  fi

  if [ "$ok" -eq 1 ]; then
    echo "[PASS 対照] 異常終了-陽性陰性対照: 終了コード128以上と127だけを「不合格-異常終了」に分類する"
    return 0
  fi
  return 1
}

check_judge_condition_details() {
  local ok=1 v
  # 条件1の語彙が3つともそれぞれ効く。
  v="$(judge_of "使い方: foo" 0)"
  if [ "$v" != "不合格-使い方" ]; then
    echo "[FAIL 対照] 判定の細目-語彙: 「使い方:」を「${v}」に分類した（期待: 不合格-使い方）"
    ok=0
  fi
  v="$(judge_of "usage: foo" 0)"
  if [ "$v" != "不合格-使い方" ]; then
    echo "[FAIL 対照] 判定の細目-語彙: 「usage」を「${v}」に分類した（期待: 不合格-使い方）"
    ok=0
  fi
  v="$(judge_of "check-引数不正: x" 2)"
  if [ "$v" != "不合格-使い方" ]; then
    echo "[FAIL 対照] 判定の細目-語彙: 「引数不正」を「${v}」に分類した（期待: 不合格-使い方）"
    ok=0
  fi
  v="$(judge_of "余分な引数です: EXTRA" 2)"
  if [ "$v" != "不合格-使い方" ]; then
    echo "[FAIL 対照] 判定の細目-語彙: 「余分な引数」を「${v}」に分類した（期待: 不合格-使い方）"
    ok=0
  fi
  # 大文字と小文字を区別しない。
  v="$(judge_of "USAGE: foo" 0)"
  if [ "$v" != "不合格-使い方" ]; then
    echo "[FAIL 対照] 判定の細目-大文字小文字: 「USAGE」を「${v}」に分類した（期待: 不合格-使い方）"
    ok=0
  fi
  # 条件2は終了コードが0でないことも見る。
  v="$(judge_of "要確認-判定不能 が1件" 0)"
  if [ "$v" != "合格" ]; then
    echo "[FAIL 対照] 判定の細目-判定不能の終了コード: 終了コード0の要確認-判定不能を「${v}」に分類した（期待: 合格）"
    ok=0
  fi
  v="$(judge_of "要確認-判定不能 が1件" 1)"
  if [ "$v" != "不合格-判定不能" ]; then
    echo "[FAIL 対照] 判定の細目-判定不能の終了コード: 終了コード1の要確認-判定不能を「${v}」に分類した（期待: 不合格-判定不能）"
    ok=0
  fi

  if [ "$ok" -eq 1 ]; then
    echo "[PASS 対照] 判定の細目: 語彙4つ・大文字小文字の無視・終了コードの条件がそれぞれ効く"
    return 0
  fi
  return 1
}

check_pipeline_detection() {
  local ok=1 v sig
  # 標準エラーへ出る使い方の誤りを捕捉する（2>&1 の欠落を検知する）。
  run_and_judge "${SKILLS_ROOT}/reverse-shared" "scripts/check-entry.sh" "${TMP}"
  v="$RJ_JUDGE"
  if [ "$v" != "不合格-使い方" ]; then
    echo "[FAIL 対照] 配管-標準エラーの捕捉: 標準エラーへ出る使い方の誤りを「${v}」に分類した（期待: 不合格-使い方）"
    ok=0
  fi
  # 終了コードを取り違えない（rc の取り落としを検知する）。
  sig="${TMP}/sig-case.sh"
  printf '#!/bin/bash\nkill -PIPE $$\n' > "$sig"
  chmod +x "$sig"
  run_and_judge "${TMP}" "sig-case.sh"
  v="$RJ_JUDGE"
  if [ "$v" != "不合格-異常終了" ]; then
    echo "[FAIL 対照] 配管-終了コードの取得: シグナルで落ちる実例を「${v}」に分類した（期待: 不合格-異常終了）"
    ok=0
  fi

  # 引数を1つずつ別の語として渡す（"$*" への退行を検知する）。
  local argcase="${TMP}/arg-case.sh"
  printf '#!/bin/bash\nif [ "$#" -eq 2 ] && [ "$1" = "a b" ] && [ "$2" = "c" ]; then\n  exit 0\nfi\necho "使い方: 引数の渡し方が違う" >&2\nexit 2\n' > "$argcase"
  chmod +x "$argcase"
  run_and_judge "${TMP}" "arg-case.sh" "a b" "c"
  v="$RJ_JUDGE"
  if [ "$v" != "合格" ]; then
    echo "[FAIL 対照] 配管-引数の渡し方: 空白を含む引数と2つの引数の受け渡しで「${v}」に分類した（期待: 合格）"
    ok=0
  fi

  if [ "$ok" -eq 1 ]; then
    echo "[PASS 対照] 配管: 標準エラーの捕捉と終了コードの取得と引数の渡し方がどれも効く"
    return 0
  fi
  return 1
}

check_fence_language_exclusion() {
  local md="${TMP}/fence-lang.md" got
  cat > "$md" << 'MDEOF'
# dummy

```yaml
key: scripts/foo.sh <対象>
```

説明文。scripts/foo.sh <対象> を地の文で言及する。

```bash
scripts/bar.sh <対象>
```
MDEOF
  got="$(extract_fenced "$md" | normalize_and_filter)"
  if [ "$got" = "scripts/bar.sh <対象>" ]; then
    echo "[PASS 対照] フェンス-他言語除外: yaml フェンスの中身と閉じ行以降の地の文を抽出せず bash フェンスだけを抽出する"
    return 0
  fi
  echo "[FAIL 対照] フェンス-他言語除外: 抽出結果が期待と異なる:"
  printf '%s\n' "$got" | sed 's/^/    /'
  return 1
}

# --- 本体 -------------------------------------------------------------
# extract_all | while ... だとパイプがサブシェルを作りtotal/badの更新が
# 親シェルへ伝わらないため、プロセス置換(< <(...))で読む（bash 3.2対応）。

while IFS=$'\t' read -r skill cmd; do
  run_one "$skill" "$cmd"
done < <(extract_all)
extracted=$total

if ! check_usage_detection; then
  bad=$((bad + 1))
fi
total=$((total + 1))

if ! check_judgenone_detection; then
  bad=$((bad + 1))
fi
total=$((total + 1))

if ! check_fence_language_exclusion; then
  bad=$((bad + 1))
fi
total=$((total + 1))

if ! check_abnormal_exit_detection; then
  bad=$((bad + 1))
fi
total=$((total + 1))

if ! check_judge_condition_details; then
  bad=$((bad + 1))
fi
total=$((total + 1))

if ! check_pipeline_detection; then
  bad=$((bad + 1))
fi
total=$((total + 1))

# 抽出が0件なら、抽出の仕組みが壊れている。合格として通さない。
if [ "$extracted" -eq 0 ]; then
  echo "[FAIL] 抽出-0件: 手順書からコマンドを1件も抽出できなかった"
  bad=$((bad + 1))
fi

echo "抽出 ${extracted} 件 + 対照 $((total - extracted)) 件 / 引数不足 ${bad} 件"
if [ "$bad" -gt 0 ]; then
  exit 1
fi
exit 0
