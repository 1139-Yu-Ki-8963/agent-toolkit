#!/usr/bin/env bash
# compare-skill-snapshots.sh — 週次スナップショット台帳の最新2件を突き合わせ、
# リリース候補を挙げる
#
# 使い方:
#   compare-skill-snapshots.sh [--ledger <台帳のパス>]
#   compare-skill-snapshots.sh --self-test
#
# 何をするか:
#   台帳（snapshot-skills.sh が書く週次スナップショット.md）の最新2件の節を
#   読み、次の3条件でリリース候補を挙げる。
#     新しく増えた       前の週に無く今週にあるスキル
#     選び方が変わった   日本語名または説明が違うスキル
#     できることが変わった 段の数または道具の数が違うスキル
#   前の節にあり今週の節に無いスキルは [消えた] として別に出す。
#   節が1件以下（基準点のみ）の場合は「基準点のみ。比較できません」と出し
#   exit 0 で終える（不合格ではない）。
#
# なぜ必要か:
#   docs/tasks/週次の成果を見える化する指示書.md が指摘するとおり、週ごとの
#   増減を人手で見比べると見落としが起こる。台帳の表という同じ形式のデータ
#   同士を突き合わせるだけの処理であり、繰り返し実行できるスクリプトへ
#   固定する必要がある。
#
# 採否は人が決める。決めた結果は台帳の当該週の節へ「判断の記録」として
# 書き足す（この決定自体は本スクリプトの担当外）。
#
# 保守責任者: 人手（ユーザー）。3条件の判定基準・出力の形式を変える場合は
#   本スクリプトと docs/tasks/週次の成果を見える化する指示書.md を同時に
#   更新する。
#
# 廃棄条件: 週次スナップショットの運用自体を廃止した時。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DEFAULT_LEDGER="$REPO_ROOT/docs/tasks/work-records/週次スナップショット.md"

TMP_FILES=()
cleanup_tmp() {
  local f
  for f in "${TMP_FILES[@]}"; do
    [ -n "$f" ] && rm -f "$f"
  done
}
trap cleanup_tmp EXIT

# $(mk_tmp) のようにコマンド置換で呼ぶとサブシェル内でTMP_FILESへ追記され、
# 呼び出し元（親シェル）のTMP_FILESには反映されない。そのため代入先の変数名を
# 引数で受け取り、printf -v で親シェルの変数へ直接書き込む形にしている。
mk_tmp() {
  local __var="$1"
  local t
  if ! t="$(mktemp "${TMPDIR:-/tmp}/compare-skill-snapshots.XXXXXX" 2>/dev/null)" || [ -z "$t" ]; then
    return 1
  fi
  TMP_FILES+=("$t")
  printf -v "$__var" '%s' "$t"
  return 0
}

unknown_mktemp() {
  echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）"
}

# 第idx番目（1=最新）の節の **スキル本数**: の値を取り出す。
extract_section_count() {
  local ledger="$1" idx="$2"
  awk -v target="$idx" '
    /^### / { count++; insection = (count == target); next }
    insection && /^\*\*スキル本数\*\*: / {
      v = $0
      sub(/^\*\*スキル本数\*\*: /, "", v)
      print v
      exit
    }
  ' "$ledger"
}

# 第idx番目（1=最新）の節の表の行を skill<TAB>jp<TAB>desc<TAB>phases<TAB>tools で出す。
extract_section_rows() {
  local ledger="$1" idx="$2"
  awk -v target="$idx" '
    /^### / { count++; insection = (count == target); next }
    insection && /^\|/ {
      line = $0
      if (line ~ /^\|---/) next
      gsub(/\\\|/, "\x01", line)
      n = split(line, parts, "|")
      out = ""
      skiprow = 0
      for (i = 2; i <= n - 1; i++) {
        v = parts[i]
        gsub(/^[ \t]+|[ \t]+$/, "", v)
        gsub(/\x01/, "|", v)
        if (i == 2 && v == "スキル") skiprow = 1
        out = (out == "") ? v : out "\t" v
      }
      if (skiprow) next
      print out
    }
  ' "$ledger"
}

# 台帳の最新2件を突き合わせ、結果を標準出力へ書く。戻り値: 0=比較完了 / 1=台帳が無い / 2=判定不能。
do_compare() {
  local ledger="$1"

  if [ ! -f "$ledger" ]; then
    echo "台帳が見つかりません: $ledger" >&2
    return 1
  fi

  local section_count
  section_count="$(grep -cE '^### ' "$ledger" 2>/dev/null)"
  section_count="${section_count:-0}"

  if [ "$section_count" -le 1 ]; then
    echo "基準点のみ。比較できません"
    return 0
  fi

  local latest_week prev_week
  latest_week="$(grep -m1 -E '^### ' "$ledger" | sed 's/^### //')"
  prev_week="$(grep -E '^### ' "$ledger" | sed -n '2p' | sed 's/^### //')"

  local latest_count prev_count
  latest_count="$(extract_section_count "$ledger" 1)"
  prev_count="$(extract_section_count "$ledger" 2)"
  [ -z "$latest_count" ] && latest_count=0
  [ -z "$prev_count" ] && prev_count=0

  local diff sign
  diff=$((latest_count - prev_count))
  if [ "$diff" -gt 0 ]; then
    sign="+${diff}"
  elif [ "$diff" -lt 0 ]; then
    sign="${diff}"
  else
    sign="±0"
  fi

  echo "比較: ${prev_week} → ${latest_week}"
  echo "本数: ${prev_count} → ${latest_count}（${sign}）"
  echo

  local latest_rows prev_rows
  if ! mk_tmp latest_rows; then unknown_mktemp; return 2; fi
  if ! mk_tmp prev_rows; then unknown_mktemp; return 2; fi
  extract_section_rows "$ledger" 1 > "$latest_rows"
  extract_section_rows "$ledger" 2 > "$prev_rows"

  local candidates=0
  local skill jp desc phases tools p_line p_skill p_jp p_desc p_phases p_tools reasons

  while IFS=$'\t' read -r skill jp desc phases tools; do
    [ -z "$skill" ] && continue
    p_line="$(LC_ALL=C awk -F'\t' -v s="$skill" '$1==s{print;exit}' "$prev_rows")"
    if [ -z "$p_line" ]; then
      echo "[候補] ${skill}: 新しく増えた"
      candidates=$((candidates + 1))
      continue
    fi
    IFS=$'\t' read -r p_skill p_jp p_desc p_phases p_tools <<< "$p_line"
    reasons=""
    if [ "$jp" != "$p_jp" ] || [ "$desc" != "$p_desc" ]; then
      reasons="選び方が変わった"
    fi
    if [ "$phases" != "$p_phases" ] || [ "$tools" != "$p_tools" ]; then
      if [ -n "$reasons" ]; then
        reasons="${reasons}, できることが変わった"
      else
        reasons="できることが変わった"
      fi
    fi
    if [ -n "$reasons" ]; then
      echo "[候補] ${skill}: ${reasons}"
      candidates=$((candidates + 1))
    fi
  done < "$latest_rows"

  echo
  echo "候補 ${candidates} 件"

  while IFS=$'\t' read -r skill jp desc phases tools; do
    [ -z "$skill" ] && continue
    if ! LC_ALL=C awk -F'\t' -v s="$skill" 'BEGIN{f=0} $1==s{f=1} END{exit !f}' "$latest_rows"; then
      echo "[消えた] ${skill}"
    fi
  done < "$prev_rows"

  # 呼び出し元が $(do_compare ...) のようにコマンド置換で結果を捕まえる場合、
  # do_compare 自体がサブシェルで動くため EXIT トラップは親シェルまで届かない。
  # サブシェルが終わる前にここで明示的に片付ける。
  rm -f "$latest_rows" "$prev_rows"

  return 0
}

# ---- 自己テスト ----

write_ledger_case() {
  local file="$1"
  cat > "$file" << 'LEDGER_EOF'
# 週次スナップショット

説明文。

## 記録

### 2026-W02

**基準日**: 2026-08-14
**基準のコミット**: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
**スキル本数**: 5

| スキル | 日本語名 | 説明 | 段の数 | 道具の数 |
|---|---|---|---|---|
| new-skill | 新規 | 新しいスキル。 | 2 | 0 |
| renamed-skill | 新名前 | 新しい説明。 | 3 | 1 |
| changed-skill | 変更 | 変わらない説明。 | 5 | 2 |
| combo-skill | 新 | 新しい説明。 | 9 | 9 |
| stable-skill | 安定 | 変わらない。 | 1 | 0 |

### 2026-W01

**基準日**: 2026-08-07
**基準のコミット**: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
**スキル本数**: 5

| スキル | 日本語名 | 説明 | 段の数 | 道具の数 |
|---|---|---|---|---|
| renamed-skill | 旧名前 | 新しい説明。 | 3 | 1 |
| changed-skill | 変更 | 変わらない説明。 | 2 | 2 |
| combo-skill | 旧 | 古い説明。 | 1 | 0 |
| stable-skill | 安定 | 変わらない。 | 1 | 0 |
| gone-skill | 消える | いなくなる。 | 1 | 0 |
LEDGER_EOF
}

write_ledger_single() {
  local file="$1"
  cat > "$file" << 'LEDGER_EOF'
# 週次スナップショット

説明文。

## 記録

### 2026-W01

**基準日**: 2026-08-07
**基準のコミット**: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
**スキル本数**: 1

| スキル | 日本語名 | 説明 | 段の数 | 道具の数 |
|---|---|---|---|---|
| stable-skill | 安定 | 変わらない。 | 1 | 0 |
LEDGER_EOF
}

write_ledger_identical() {
  local file="$1"
  cat > "$file" << 'LEDGER_EOF'
# 週次スナップショット

説明文。

## 記録

### 2026-W02

**基準日**: 2026-08-14
**基準のコミット**: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
**スキル本数**: 1

| スキル | 日本語名 | 説明 | 段の数 | 道具の数 |
|---|---|---|---|---|
| stable-skill | 安定 | 変わらない。 | 1 | 0 |

### 2026-W01

**基準日**: 2026-08-07
**基準のコミット**: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
**スキル本数**: 1

| スキル | 日本語名 | 説明 | 段の数 | 道具の数 |
|---|---|---|---|---|
| stable-skill | 安定 | 変わらない。 | 1 | 0 |
LEDGER_EOF
}

self_test() {
  local base
  if ! base="$(mktemp -d "${TMPDIR:-/tmp}/compare-skill-snapshots-test.XXXXXX" 2>/dev/null)" || [ -z "$base" ] || [ ! -d "$base" ]; then
    unknown_mktemp
    return 2
  fi

  local pass=0 fail=0 out rc

  # ケース1: 節が1件だけのとき
  local l1="$base/single.md"
  write_ledger_single "$l1"
  out="$(do_compare "$l1")"
  rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF "基準点のみ。比較できません"; then
    echo "[PASS] 節が1件だけのとき"
    pass=$((pass + 1))
  else
    echo "[FAIL] 節が1件だけのとき（rc=${rc}）"
    fail=$((fail + 1))
  fi

  # ケース2: 3条件それぞれに当たるとき（複合の組も含む）
  local l2="$base/three.md"
  write_ledger_case "$l2"
  out="$(do_compare "$l2")"
  rc=$?
  if [ "$rc" -eq 0 ] \
    && printf '%s' "$out" | grep -qF "[候補] new-skill: 新しく増えた" \
    && printf '%s' "$out" | grep -qF "[候補] renamed-skill: 選び方が変わった" \
    && printf '%s' "$out" | grep -qF "[候補] changed-skill: できることが変わった" \
    && printf '%s' "$out" | grep -qF "[候補] combo-skill: 選び方が変わった, できることが変わった" \
    && ! printf '%s' "$out" | grep -qF "[候補] stable-skill"; then
    echo "[PASS] 3条件それぞれに当たるとき"
    pass=$((pass + 1))
  else
    echo "[FAIL] 3条件それぞれに当たるとき（rc=${rc}）"
    printf '%s\n' "$out" >&2
    fail=$((fail + 1))
  fi

  # ケース3: スキルが消えたとき
  if printf '%s' "$out" | grep -qF "[消えた] gone-skill"; then
    echo "[PASS] スキルが消えたとき"
    pass=$((pass + 1))
  else
    echo "[FAIL] スキルが消えたとき"
    fail=$((fail + 1))
  fi

  # ケース4: 候補0件のとき
  local l4="$base/identical.md"
  write_ledger_identical "$l4"
  out="$(do_compare "$l4")"
  rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF "候補 0 件" && ! printf '%s' "$out" | grep -qF "[候補]"; then
    echo "[PASS] 候補0件のとき"
    pass=$((pass + 1))
  else
    echo "[FAIL] 候補0件のとき（rc=${rc}）"
    fail=$((fail + 1))
  fi

  rm -rf "$base"
  echo "実行 $((pass + fail)) 件 / 合格 $pass 件 / 不合格 $fail 件"
  [ "$fail" -eq 0 ]
}

# ---- 引数解析 ----

main() {
  local ledger="$DEFAULT_LEDGER"
  local do_self_test="no"

  while [ $# -gt 0 ]; do
    case "$1" in
      --ledger) ledger="$2"; shift 2 ;;
      --self-test) do_self_test="yes"; shift ;;
      *) echo "不明な引数: $1" >&2; exit 2 ;;
    esac
  done

  if [ "$do_self_test" = "yes" ]; then
    self_test
    exit $?
  fi

  do_compare "$ledger"
  exit $?
}

main "$@"
