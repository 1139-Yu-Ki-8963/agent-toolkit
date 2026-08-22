#!/usr/bin/env bash
# snapshot-skills.sh — .claude/skills/ の週ごとの状態を台帳へ記録する
#
# 使い方:
#   snapshot-skills.sh [--ledger <台帳のパス>] [--week <YYYY-Www>] [--skills-dir <スキル置き場>]
#   snapshot-skills.sh --self-test
#
# 何をするか:
#   <skills-dir>/*/SKILL.md を走査し、スキル1本につき日本語名・説明・段の数
#   （`^## Phase` に一致する行の数）・道具の数（scripts/配下のファイル数）を
#   取り、台帳の `## 記録` 見出しの直後へ新しい週の節として書き足す。
#
# なぜ必要か:
#   docs/tasks/週次の成果を見える化する指示書.md が指摘するとおり、週ごとの
#   スキルの状態を記録する仕組みがこのリポジトリに1つも無く、先週との比較が
#   できない。同じ週の二重記録は事故のもとになるため、既に同じ週の節がある
#   場合は上書きせず拒否する。
#
# 代替案を採らなかった理由:
#   対話セッションのたびに52本のSKILL.mdを手で読み比べて台帳へ書き写すと、
#   確認のたびに判定基準がぶれ、書き写し漏れが起こる。このリポジトリは
#   Makefile も package.json も持たず、新規導入は本スクリプト専用の依存を
#   増やすだけになるため、繰り返し実行できる bash スクリプトとして1本に
#   閉じた。
#
# 保守責任者: 人手（ユーザー）。台帳の節の形式・記録する4項目を変える場合は
#   本スクリプトと docs/tasks/週次の成果を見える化する指示書.md を同時に
#   更新する。
#
# 廃棄条件: 週次スナップショットの運用自体を廃止した時。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DEFAULT_LEDGER="$REPO_ROOT/docs/tasks/work-records/週次スナップショット.md"
DEFAULT_SKILLS_DIR="$REPO_ROOT/.claude/skills"

TMP_FILES=()
cleanup_tmp() {
  local f
  for f in "${TMP_FILES[@]}"; do
    [ -n "$f" ] && rm -f "$f"
  done
}
trap cleanup_tmp EXIT

# mktemp の失敗を判定不能規約に沿って扱う（.claude/rules/always/verification/indeterminate-result/rule.md）。
# $(mk_tmp) のようにコマンド置換で呼ぶとサブシェル内でTMP_FILESへ追記され、
# 呼び出し元（親シェル）のTMP_FILESには反映されない。そのため代入先の変数名を
# 引数で受け取り、printf -v で親シェルの変数へ直接書き込む形にしている。
mk_tmp() {
  local __var="$1"
  local t
  if ! t="$(mktemp "${TMPDIR:-/tmp}/snapshot-skills.XXXXXX" 2>/dev/null)" || [ -z "$t" ]; then
    return 1
  fi
  TMP_FILES+=("$t")
  printf -v "$__var" '%s' "$t"
  return 0
}

unknown_mktemp() {
  echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）"
}

# frontmatter（先頭の --- 〜 --- の間）だけを取り出す。check-skill-frontmatter.sh と同形。
extract_frontmatter() {
  local file="$1"
  awk 'NR==1 && $0=="---" {f=1; next} f && $0=="---" {exit} f {print}' "$file"
}

# description: の値を取り出す。単一行の引用符付き形式とブロックスカラー形式の両方を扱う。
extract_description() {
  local fm="$1"
  local lineno
  lineno="$(printf '%s\n' "$fm" | grep -n '^description:' | head -1 | cut -d: -f1)"
  [ -z "$lineno" ] && return 0

  local line
  line="$(printf '%s\n' "$fm" | sed -n "${lineno}p")"

  case "$line" in
    'description: "'*)
      printf '%s\n' "$line" | sed -E 's/^description: "//; s/"[[:space:]]*$//'
      ;;
    'description: |'*)
      printf '%s\n' "$fm" | awk -v start="$lineno" '
        NR>start {
          if ($0 ~ /^[[:space:]]/) {
            s=$0
            sub(/^[[:space:]]+/, "", s)
            if (buf=="") { buf=s } else { buf=buf" "s }
          } else {
            exit
          }
        }
        END { print buf }
      '
      ;;
    *)
      printf '%s\n' "$line" | sed -E 's/^description:[[:space:]]*//'
      ;;
  esac
}

# 日本語名: の値を取り出す（引用符・前後の空白を除去）。
extract_japanese_name() {
  local fm="$1"
  local line
  line="$(printf '%s\n' "$fm" | grep -m1 '^日本語名:')"
  [ -z "$line" ] && return 0
  printf '%s\n' "$line" \
    | sed -E 's/^日本語名:[[:space:]]*//; s/^"//; s/"[[:space:]]*$//; s/^[[:space:]]+//; s/[[:space:]]+$//'
  return 0
}

# 表の区切り文字 | と衝突しないよう \| へ置き換える。
escape_pipe() {
  printf '%s' "$1" | sed 's/|/\\|/g'
}

count_phases() {
  local file="$1"
  grep -c '^## Phase' "$file" 2>/dev/null | tr -d '[:space:]'
}

count_tools() {
  local skill_dir="$1"
  if [ -d "$skill_dir/scripts" ]; then
    find "$skill_dir/scripts" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d '[:space:]'
  else
    echo 0
  fi
}

# skills_dir 配下の全スキルを走査し、表の行（skillフォルダ名の昇順）を出す。
build_rows() {
  local skills_dir="$1"
  local d name file fm jp desc phases tools

  find "$skills_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort | while IFS= read -r d; do
    file="$d/SKILL.md"
    [ -f "$file" ] || continue
    name="$(basename "$d")"
    fm="$(extract_frontmatter "$file")"
    jp="$(extract_japanese_name "$fm")"
    desc="$(extract_description "$fm")"
    jp="$(escape_pipe "$jp")"
    desc="$(escape_pipe "$desc")"
    phases="$(count_phases "$file")"
    tools="$(count_tools "$d")"
    printf '| %s | %s | %s | %s | %s |\n' "$name" "$jp" "$desc" "$phases" "$tools"
  done
}

# 台帳へ週の節を書き足す。戻り値: 0=記録した / 1=既に記録がある・スキル置き場が無い / 2=判定不能。
do_snapshot() {
  local ledger="$1" week="$2" skills_dir="$3"

  if [ ! -d "$skills_dir" ]; then
    echo "スキル置き場が見つかりません: $skills_dir" >&2
    return 1
  fi

  mkdir -p "$(dirname "$ledger")"

  if [ ! -f "$ledger" ]; then
    {
      echo "# 週次スナップショット"
      echo
      echo "スキルの週ごとの状態を記録する台帳。\`docs/scripts/snapshot-skills.sh\` が書き込み、\`docs/scripts/compare-skill-snapshots.sh\` が読む。"
      echo
      echo "## 記録"
    } > "$ledger"
  fi

  if grep -qxF "### $week" "$ledger"; then
    echo "既に ${week} の記録があります" >&2
    return 1
  fi

  local base_date commit_hash
  base_date="$(date +%F)"
  commit_hash="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)"
  [ -z "$commit_hash" ] && commit_hash="unknown"

  local rows_file section_file before_file after_file after_trimmed tmp_out
  if ! mk_tmp rows_file; then unknown_mktemp; return 2; fi
  build_rows "$skills_dir" > "$rows_file"
  local skill_count
  skill_count="$(wc -l < "$rows_file" | tr -d '[:space:]')"

  if ! mk_tmp section_file; then unknown_mktemp; return 2; fi
  {
    echo "### $week"
    echo
    echo "**基準日**: $base_date"
    echo "**基準のコミット**: $commit_hash"
    echo "**スキル本数**: $skill_count"
    echo
    echo "| スキル | 日本語名 | 説明 | 段の数 | 道具の数 |"
    echo "|---|---|---|---|---|"
    cat "$rows_file"
  } > "$section_file"

  if ! mk_tmp before_file; then unknown_mktemp; return 2; fi
  if ! mk_tmp after_file; then unknown_mktemp; return 2; fi

  awk -v before="$before_file" -v after="$after_file" '
    {
      if (found) { print > after; next }
      print > before
      if ($0 == "## 記録") { found = 1 }
    }
  ' "$ledger"

  if ! mk_tmp after_trimmed; then unknown_mktemp; return 2; fi
  awk 'BEGIN{skip=1} { if (skip && $0=="") next; skip=0; print }' "$after_file" > "$after_trimmed"

  if ! mk_tmp tmp_out; then unknown_mktemp; return 2; fi
  {
    cat "$before_file"
    echo
    cat "$section_file"
    if [ -s "$after_trimmed" ]; then
      echo
      cat "$after_trimmed"
    fi
  } > "$tmp_out"

  mv "$tmp_out" "$ledger"

  echo "週 ${week} のスナップショットを記録しました（スキル本数: ${skill_count}）"
  return 0
}

# ---- 自己テスト ----

make_fixture_skill() {
  local dir="$1" jp="$2" desc="$3" phases="$4" with_scripts="$5"
  mkdir -p "$dir"
  {
    echo "---"
    echo "name: $(basename "$dir")"
    echo "日本語名: $jp"
    printf 'description: "%s"\n' "$desc"
    echo "invocation: $(basename "$dir")"
    echo "type: transform"
    echo "allowed-tools: [Bash]"
    echo "---"
    echo
    local i=1
    while [ "$i" -le "$phases" ]; do
      echo "## Phase $i"
      i=$((i + 1))
    done
  } > "$dir/SKILL.md"
  if [ "$with_scripts" = "yes" ]; then
    mkdir -p "$dir/scripts"
    touch "$dir/scripts/run.sh" "$dir/scripts/helper.sh"
  fi
}

self_test() {
  local base
  if ! base="$(mktemp -d "${TMPDIR:-/tmp}/snapshot-skills-test.XXXXXX" 2>/dev/null)" || [ -z "$base" ] || [ ! -d "$base" ]; then
    unknown_mktemp
    return 2
  fi

  local pass=0 fail=0 rc

  # ケース1: 台帳が無い状態からの新規作成
  local skills1="$base/skills1" ledger1="$base/ledger1.md"
  make_fixture_skill "$skills1/alpha-skill" "アルファ" "アルファの説明をする。" 3 no
  do_snapshot "$ledger1" "2026-W01" "$skills1" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 0 ] \
    && grep -qxF "### 2026-W01" "$ledger1" \
    && grep -qF "**スキル本数**: 1" "$ledger1" \
    && grep -qF "| alpha-skill | アルファ | アルファの説明をする。 | 3 | 0 |" "$ledger1"; then
    echo "[PASS] 台帳が無い状態からの新規作成"
    pass=$((pass + 1))
  else
    echo "[FAIL] 台帳が無い状態からの新規作成（rc=${rc}）"
    fail=$((fail + 1))
  fi

  # ケース2: 同じ週の二重記録を拒否する
  do_snapshot "$ledger1" "2026-W01" "$skills1" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 1 ]; then
    echo "[PASS] 同じ週の二重記録を拒否する"
    pass=$((pass + 1))
  else
    echo "[FAIL] 同じ週の二重記録を拒否する（rc=${rc}）"
    fail=$((fail + 1))
  fi

  # ケース3: 説明に | を含むスキル → \| へ置き換わる
  local skills2="$base/skills2" ledger2="$base/ledger2.md"
  make_fixture_skill "$skills2/pipe-skill" "パイプ" "A|Bを扱う。" 1 no
  make_fixture_skill "$skills2/tool-skill" "道具持ち" "道具を使う。" 2 yes
  do_snapshot "$ledger2" "2026-W02" "$skills2" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 0 ] \
    && grep -qF '| pipe-skill | パイプ | A\|Bを扱う。 | 1 | 0 |' "$ledger2"; then
    echo "[PASS] 説明に | を含むスキルは \\| へ置き換わる"
    pass=$((pass + 1))
  else
    echo "[FAIL] 説明に | を含むスキルは \\| へ置き換わる（rc=${rc}）"
    fail=$((fail + 1))
  fi

  # ケース4: scripts/ を持たないスキルは道具の数 0、持つスキルは実数
  if grep -qF "| pipe-skill | パイプ | A\\|Bを扱う。 | 1 | 0 |" "$ledger2" \
    && grep -qF "| tool-skill | 道具持ち | 道具を使う。 | 2 | 2 |" "$ledger2"; then
    echo "[PASS] scripts/の有無で道具の数が変わる"
    pass=$((pass + 1))
  else
    echo "[FAIL] scripts/の有無で道具の数が変わる"
    fail=$((fail + 1))
  fi

  rm -rf "$base"
  echo "実行 $((pass + fail)) 件 / 合格 $pass 件 / 不合格 $fail 件"
  [ "$fail" -eq 0 ]
}

# ---- 引数解析 ----

main() {
  local ledger="$DEFAULT_LEDGER"
  local week=""
  local skills_dir="$DEFAULT_SKILLS_DIR"
  local do_self_test="no"

  while [ $# -gt 0 ]; do
    case "$1" in
      --ledger) ledger="$2"; shift 2 ;;
      --week) week="$2"; shift 2 ;;
      --skills-dir) skills_dir="$2"; shift 2 ;;
      --self-test) do_self_test="yes"; shift ;;
      *) echo "不明な引数: $1" >&2; exit 2 ;;
    esac
  done

  if [ "$do_self_test" = "yes" ]; then
    self_test
    exit $?
  fi

  [ -z "$week" ] && week="$(date +%G-W%V)"

  do_snapshot "$ledger" "$week" "$skills_dir"
  exit $?
}

main "$@"
