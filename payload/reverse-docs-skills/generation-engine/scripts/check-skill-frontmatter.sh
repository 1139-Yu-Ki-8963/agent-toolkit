#!/usr/bin/env bash
# check-skill-frontmatter.sh — .claude/skills/*/SKILL.md の設定（frontmatter）を検査する
#
# 何を検査するか（4つ）:
#   検査1 日本語名: `日本語名:` の行があり、値が空でなく、日本語
#         （ひらがな・カタカナ・漢字のいずれか）を1文字以上含む
#   検査2 句点:     `description:` の値に含まれる句点「。」がちょうど1個で、
#         値の末尾にある
#   検査3 動詞:     `description:` の値が、句点の直前で日本語の動詞の終止形
#         （う・く・ぐ・す・つ・ぬ・ぶ・む・るのいずれか）で終わっている
#   検査4 英字:     `description:` の値に半角英字（A-Z・a-z）が1文字も無い
#
#   検査対象は `description:` の値だけである。`allowed-tools:` は道具の名前
#   であり英字が要るため、検査4の対象に含めない。
#
# なぜ必要か:
#   このリポジトリの52個のスキルは全て `name`・`description`・`invocation`・
#   `type`・`allowed-tools` の5項目を持つ設定を冒頭に置くが、この形式を検査
#   するものが1つも無かった。そのため説明欄に英字・複数文・このリポジトリを
#   知らないと読めない語（`TRIGGER when:`・`SKIP:` 等）が混ざったまま配布
#   されている。読み手が意味を取れない説明文を機械的に検出する必要がある。
#
# 代替案を採らなかった理由:
#   対話セッションのたびに52個のSKILL.mdを手で読み比べて形式を確認すると、
#   確認のたびに判定基準がぶれ、見落としが起こる。このリポジトリは
#   Makefile も package.json も持たず、新規導入は本スクリプト専用の依存を
#   増やすだけになるため、繰り返し実行できる bash スクリプトとして1本に
#   閉じた。
#
# 使い方:
#   check-skill-frontmatter.sh              .claude/skills/*/SKILL.md を検査する
#   check-skill-frontmatter.sh --self-test   判定の妥当性を検査する
#
# 保守責任者: 人手（ユーザー）。検査の語彙（動詞終止形の一覧・除外する
#   allowed-tools の扱い）を変える場合は本スクリプトと本節を同時に更新する。
#
# 廃棄条件: `.claude/skills/*/SKILL.md` の設定形式自体を廃止した時、または
#   frontmatter の妥当性検査を別の機構が標準で保証するようになった時。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# frontmatter（先頭の --- 〜 --- の間）だけを取り出す。
extract_frontmatter() {
  local file="$1"
  awk 'NR==1 && $0=="---" {f=1; next} f && $0=="---" {exit} f {print}' "$file"
}

# description: の値を取り出す。単一行の引用符付き形式（description: "..."）と
# ブロックスカラー形式（description: |\n  行1\n  行2\n...）の両方を扱う。
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
  [ -z "$line" ] && return 1
  printf '%s\n' "$line" \
    | sed -E 's/^日本語名:[[:space:]]*//; s/^"//; s/"[[:space:]]*$//; s/^[[:space:]]+//; s/[[:space:]]+$//'
  return 0
}

# 1つの SKILL.md を検査し、[OK]/[FAIL] を出力する。合格なら0、不合格なら1を返す。
check_skill_file() {
  local file="$1"
  local skill_name
  skill_name="$(basename "$(dirname "$file")")"

  local fm
  fm="$(extract_frontmatter "$file")"

  local failures=()

  # 検査1: 日本語名
  local jp_line jp_value
  jp_line="$(printf '%s\n' "$fm" | grep -m1 '^日本語名:')"
  if [ -z "$jp_line" ]; then
    failures+=("検査1 日本語名: 欄が無い")
  else
    jp_value="$(extract_japanese_name "$fm")"
    if [ -z "$jp_value" ]; then
      failures+=("検査1 日本語名: 値が空")
    elif ! printf '%s' "$jp_value" | grep -qE '[ぁ-んァ-ヶ一-龠]'; then
      failures+=("検査1 日本語名: 値に日本語が含まれない")
    fi
  fi

  # description の値を取り出し、検査2〜4を行う
  local desc
  desc="$(extract_description "$fm")"

  if [ -z "$desc" ]; then
    failures+=("検査2 句点: description欄が読み取れない")
    failures+=("検査3 動詞: description欄が読み取れない")
    failures+=("検査4 英字: description欄が読み取れない")
  else
    # 検査2: 句点がちょうど1個で末尾にある
    local period_count
    period_count="$(printf '%s' "$desc" | grep -o '。' | wc -l | tr -d '[:space:]')"
    if [ "$period_count" -ne 1 ]; then
      failures+=("検査2 句点: 句点が${period_count}個ある（1個であること）")
    elif [[ "$desc" != *。 ]]; then
      failures+=("検査2 句点: 句点が末尾にない")
    fi

    # 検査3: 句点の直前が動詞の終止形
    if ! printf '%s' "$desc" | grep -qE '[うくぐすつぬぶむる]。$'; then
      failures+=("検査3 動詞: 説明が動詞で終わっていない")
    fi

    # 検査4: 半角英字が無い
    if printf '%s' "$desc" | grep -qE '[A-Za-z]'; then
      local en_words
      en_words="$(printf '%s' "$desc" | grep -oE '[A-Za-z]+' | LC_ALL=C sort -u | paste -sd, - | sed -E 's/,/, /g')"
      failures+=("検査4 英字: 説明に英字が含まれる（${en_words}）")
    fi
  fi

  if [ "${#failures[@]}" -eq 0 ]; then
    echo "[OK]   $skill_name"
    return 0
  fi

  echo "[FAIL] $skill_name"
  local m
  for m in "${failures[@]}"; do
    echo "       $m"
  done
  return 1
}

# base 配下の .claude/skills/*/SKILL.md をすべて検査する。
run_checks() {
  local base="$1"
  local total=0 fail_count=0
  local f

  while IFS= read -r f; do
    [ -z "$f" ] && continue
    total=$((total + 1))
    if ! check_skill_file "$f"; then
      fail_count=$((fail_count + 1))
    fi
  done < <(find "$base/.claude/skills" -mindepth 2 -maxdepth 2 -type f -name 'SKILL.md' 2>/dev/null | LC_ALL=C sort)

  echo "合格 $((total - fail_count)) 件 / 不合格 $fail_count 件"
  [ "$fail_count" -eq 0 ]
}

# 自己テスト用: 疑似のスキルフォルダを作る
make_skill() {
  local dir="$1" body="$2"
  mkdir -p "$dir"
  {
    echo "---"
    printf '%s\n' "$body"
    echo "---"
    echo
    echo "# 疑似スキル"
  } > "$dir/SKILL.md"
}

run_case() {
  local name="$1" body="$2" expect="$3" tmp="$4"
  local dir="$tmp/case-$name-$RANDOM"
  make_skill "$dir" "$body"
  local rc=0
  check_skill_file "$dir/SKILL.md" >/dev/null 2>&1 || rc=1
  if { [ "$expect" = "pass" ] && [ "$rc" -eq 0 ]; } || { [ "$expect" = "fail" ] && [ "$rc" -ne 0 ]; }; then
    echo "[PASS] $name"
    return 0
  fi
  echo "[FAIL] $name"
  return 1
}

self_test() {
  local tmp pass=0 fail=0

  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/skill-frontmatter.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）"
    return 2
  fi

  # ケース1: 4検査すべてを満たす → 合格
  if run_case "検査1-4すべて満たす" "$(printf '%s\n' \
    'name: test-skill' \
    '日本語名: テストスキル' \
    'description: "疑似のスキルを検査する。"' \
    'invocation: test-skill' \
    'type: transform' \
    'allowed-tools: [Bash, Read]')" pass "$tmp"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
  fi

  # ケース2: 日本語名の欄が無い → 不合格（検査1）
  if run_case "日本語名の欄が無い" "$(printf '%s\n' \
    'name: test-skill' \
    'description: "疑似のスキルを検査する。"' \
    'invocation: test-skill' \
    'type: transform' \
    'allowed-tools: [Bash, Read]')" fail "$tmp"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
  fi

  # ケース3: 日本語名の値が空 → 不合格（検査1）
  if run_case "日本語名の値が空" "$(printf '%s\n' \
    'name: test-skill' \
    '日本語名: ' \
    'description: "疑似のスキルを検査する。"' \
    'invocation: test-skill' \
    'type: transform' \
    'allowed-tools: [Bash, Read]')" fail "$tmp"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
  fi

  # ケース4: 説明に句点が2個 → 不合格（検査2）
  if run_case "説明に句点が2個" "$(printf '%s\n' \
    'name: test-skill' \
    '日本語名: テストスキル' \
    'description: "疑似のスキルを検査する。ダミー文言も足す。"' \
    'invocation: test-skill' \
    'type: transform' \
    'allowed-tools: [Bash, Read]')" fail "$tmp"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
  fi

  # ケース5: 説明が名詞で終わる → 不合格（検査3）
  if run_case "説明が名詞で終わる" "$(printf '%s\n' \
    'name: test-skill' \
    '日本語名: テストスキル' \
    'description: "スキルの雛形を生成。"' \
    'invocation: test-skill' \
    'type: transform' \
    'allowed-tools: [Bash, Read]')" fail "$tmp"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
  fi

  # ケース6: 説明に英字が含まれる → 不合格（検査4）
  if run_case "説明に英字が含まれる" "$(printf '%s\n' \
    'name: test-skill' \
    '日本語名: テストスキル' \
    'description: "TRIGGER when 何かをする。"' \
    'invocation: test-skill' \
    'type: transform' \
    'allowed-tools: [Bash, Read]')" fail "$tmp"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
  fi

  # ケース7: 説明が「する。」で終わり英字なし句点1個 → 合格
  if run_case "説明がするで終わり英字なし" "$(printf '%s\n' \
    'name: test-skill' \
    '日本語名: テストスキル' \
    'description: "スキルを検査する。"' \
    'invocation: test-skill' \
    'type: transform' \
    'allowed-tools: [Bash, Read]')" pass "$tmp"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
  fi

  # ケース8: allowed-tools に英字があっても合格（説明欄だけを見ることの確認）
  if run_case "allowed-toolsの英字は対象外" "$(printf '%s\n' \
    'name: test-skill' \
    '日本語名: テストスキル' \
    'description: "スキルを検査する。"' \
    'invocation: test-skill' \
    'type: transform' \
    'allowed-tools: [AskUserQuestion, Bash, Edit, Read, Write]')" pass "$tmp"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
  fi

  rm -rf "$tmp"
  echo "実行 $((pass + fail)) 件 / 合格 $pass 件 / 不合格 $fail 件"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
  --self-test)
    self_test
    exit $?
    ;;
  "")
    run_checks "$REPO_ROOT"
    exit $?
    ;;
  *)
    echo "使い方: $(basename "$0") [--self-test]" >&2
    exit 2
    ;;
esac
