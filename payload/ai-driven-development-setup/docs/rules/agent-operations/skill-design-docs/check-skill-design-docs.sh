#!/usr/bin/env bash
# check-skill-design-docs.sh — docs/design/skills/ の reverse 単位の
#   基本設計書・詳細設計書・単体テスト設計書を検査する
#
# 規約の定義: docs/rules/agent-operations/skill-design-docs/rule.md
#
# 対象: docs/skills/ のうち reverse-* および reverse-shared だけ。setup単位は対象外。
#
# 使い方:
#   check-skill-design-docs.sh <リポジトリのルート>
#   check-skill-design-docs.sh --self-test
#
# 終了コード（CLI）:
#   0 = 全機能が規則を満たす
#   1 = 1件以上の不合格（標準エラーへ [FAIL] 行を列挙）
#   2 = ルートが存在しない、または対象機能が0件（判定不能）
#
# 保守責任者: 人手（ユーザー）。規則を増減する場合は rule.md と本スクリプトを
#   同時に更新する。
set -uo pipefail
export LC_ALL=C

fail_count=0
warn_count=0

fail() { echo "[FAIL] $1" >&2; fail_count=$((fail_count + 1)); }
warn() { echo "[WARN] $1" >&2; warn_count=$((warn_count + 1)); }

heading_exists() {
  local file="$1" heading="$2"
  grep -qxF "$heading" "$file" 2>/dev/null
}

list_skill_names() {
  # reverse-* および reverse-shared だけを対象にする
  local skills_root="$1"
  [ -d "$skills_root" ] || return 1
  local d name
  for d in "$skills_root"/reverse-*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    if [ -f "${d}SKILL.md" ] || [[ "$name" == *-shared ]]; then
      printf '%s\n' "$name"
    fi
  done
}

count_table_rows() {
  # $1 = file, $2 = セクション見出し。見出し直後の表本体行（先頭 | 、区切り行 |---| を除く）を数える
  local file="$1" heading="$2"
  awk -v h="$heading" '
    $0 == h { f = 1; next }
    f && /^## / { exit }
    f && /^\|/ {
      if (n == 0) { n = 1; next }         # ヘッダ行
      if ($0 ~ /^\|[- :|]+\|$/) { next }  # 区切り行
      c++
    }
    END { print c + 0 }
  ' "$file"
}

sum_case_count_column() {
  # 「テスト対象」表の最終列（ケース数）を合計する
  local file="$1"
  awk '
    $0 == "## テスト対象" { f = 1; next }
    f && /^## / { exit }
    f && /^\|/ {
      if (n == 0) { n = 1; next }
      if ($0 ~ /^\|[- :|]+\|$/) { next }
      line = $0
      gsub(/^\|/, "", line); gsub(/\|$/, "", line)
      nsplit = split(line, cols, "|")
      val = cols[nsplit]
      gsub(/^[ \t]+|[ \t]+$/, "", val)
      if (val ~ /^[0-9]+$/) sum += val
    }
    END { print sum + 0 }
  ' "$file"
}

check_repo() {
  local root="$1"
  [ -d "$root" ] || { echo "[FAIL] リポジトリのルートが存在しません: $root" >&2; return 2; }
  local skills_root="$root/docs/skills"
  local design_root="$root/docs/design/skills"
  local names
  names="$(list_skill_names "$skills_root")"
  if [ -z "$names" ]; then
    echo "[FAIL] docs/skills 配下に reverse 単位の機能が0件です: $skills_root" >&2
    return 2
  fi

  local name bd dd ud
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    bd="$design_root/$name/基本設計書.md"
    dd="$design_root/$name/詳細設計書.md"
    ud="$design_root/$name/単体テスト設計書.md"

    if [ ! -f "$bd" ]; then
      fail "基本設計書が無い: $name ($bd)"
    else
      local h
      for h in "## §1 外部仕様" "## §2 業務仕様" "## §3 方式設計" "## §4 データ仕様" "## §5 エラーと例外" "## §6 関連資料"; do
        heading_exists "$bd" "$h" || fail "基本設計書に節が無い: $name / $h"
      done
      grep -q '要件の柱' "$bd" 2>/dev/null || fail "基本設計書の§1に「要件との対応」の表が無い: $name"
    fi

    if [ ! -f "$dd" ]; then
      fail "詳細設計書が無い: $name ($dd)"
    else
      local h
      for h in "## §1 構成要素" "## §2 処理の定義" "## §3 ロジック" "## §4 入出力の値" "## §5 エラー処理" "## §6 関連資料"; do
        heading_exists "$dd" "$h" || fail "詳細設計書に節が無い: $name / $h"
      done
    fi

    if [ ! -f "$ud" ]; then
      fail "単体テスト設計書が無い: $name ($ud)"
    else
      local h
      for h in "## テスト対象" "## §1 テスト観点" "## §2 テストケース一覧" "## §5 異常系" "## §6 境界値"; do
        heading_exists "$ud" "$h" || fail "単体テスト設計書に節が無い: $name / $h"
      done
      local sum rows
      sum="$(sum_case_count_column "$ud")"
      rows="$(count_table_rows "$ud" "## §2 テストケース一覧")"
      if [ "$sum" != "$rows" ]; then
        fail "単体テスト設計書のケース数が不一致: $name (テスト対象の合計=$sum, §2の行数=$rows)"
      fi
    fi
  done <<< "$names"

  # 対応表チェック（reverse単位だけの逆引き）
  local corr="$root/docs/design/requirements/要件と機能の対応表.md"
  if [ ! -f "$corr" ]; then
    fail "要件と機能の対応表が無い: $corr"
  else
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      grep -q "$name" "$corr" 2>/dev/null \
        || fail "要件と機能の対応表の逆引きに機能が無い: $name"
    done <<< "$names"
    if grep -E '^\| 柱1|^\| 柱2|^\| 支援ツール全体の制約' "$corr" | grep '対応済み' | grep -q '（なし）'; then
      fail "要件と機能の対応表の柱1・柱2・全体の制約に、対応済みなのに「満たす機能」が無い行がある"
    fi
  fi

  return 0
}

self_test() {
  tmp=""
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/skill-design-docs.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT
  pass=0; total=0

  write_basic() {
    cat > "$1" << 'EOF'
## §1 外部仕様
| 要件の柱 | 要件の項目 | この機能が満たす内容 |
|---|---|---|
| 柱1 | x | y |
## §2 業務仕様
## §3 方式設計
## §4 データ仕様
## §5 エラーと例外
## §6 関連資料
EOF
  }
  write_detail() {
    cat > "$1" << 'EOF'
## §1 構成要素
## §2 処理の定義
## §3 ロジック
## §4 入出力の値
## §5 エラー処理
## §6 関連資料
EOF
  }

  # ケース1: 完全な最小リポジトリ → 合格
  mkdir -p "$tmp/ok/docs/skills/reverse-doing-thing"
  mkdir -p "$tmp/ok/docs/design/skills/reverse-doing-thing"
  mkdir -p "$tmp/ok/docs/design/requirements"
  touch "$tmp/ok/docs/skills/reverse-doing-thing/SKILL.md"
  write_basic "$tmp/ok/docs/design/skills/reverse-doing-thing/基本設計書.md"
  write_detail "$tmp/ok/docs/design/skills/reverse-doing-thing/詳細設計書.md"
  cat > "$tmp/ok/docs/design/skills/reverse-doing-thing/単体テスト設計書.md" << 'EOF'
## テスト対象
| スクリプト | 自己テストの実行 | ケース数 |
|---|---|---|
| a.sh | あり | 2 |
## §1 テスト観点
| キー | 観点 | 確かめる手段 |
|---|---|---|
| k1 | v1 | m1 |
## §2 テストケース一覧
| キー | 番号 | スクリプト | 前提 | 操作 | 期待値 |
|---|---|---|---|---|---|
| c1 | 1 | a.sh | p | o | e |
| c2 | 2 | a.sh | p | o | e |
## §5 異常系
## §6 境界値
EOF
  cat > "$tmp/ok/docs/design/requirements/要件と機能の対応表.md" << 'EOF'
| 柱1 | x | reverse-doing-thing | c | 対応済み |
| reverse-doing-thing | 何か |
EOF
  total=$((total + 1))
  fail_count=0; check_repo "$tmp/ok" > /dev/null 2>&1; if [ "$fail_count" = 0 ]; then pass=$((pass + 1)); else echo "[SELFTEST-FAIL] ケース1(合格想定)が不合格" >&2; fi

  # ケース2: 基本設計書が無い → 不合格
  mkdir -p "$tmp/ng1/docs/skills/reverse-doing-thing"
  mkdir -p "$tmp/ng1/docs/design/requirements"
  touch "$tmp/ng1/docs/skills/reverse-doing-thing/SKILL.md"
  total=$((total + 1))
  fail_count=0; check_repo "$tmp/ng1" > /dev/null 2>&1; if [ "$fail_count" -gt 0 ]; then pass=$((pass + 1)); else echo "[SELFTEST-FAIL] ケース2(不合格想定)が合格" >&2; fi

  # ケース3: ケース数不一致 → 不合格
  mkdir -p "$tmp/ng2/docs/skills/reverse-doing-thing"
  mkdir -p "$tmp/ng2/docs/design/skills/reverse-doing-thing"
  mkdir -p "$tmp/ng2/docs/design/requirements"
  touch "$tmp/ng2/docs/skills/reverse-doing-thing/SKILL.md"
  write_basic "$tmp/ng2/docs/design/skills/reverse-doing-thing/基本設計書.md"
  write_detail "$tmp/ng2/docs/design/skills/reverse-doing-thing/詳細設計書.md"
  cat > "$tmp/ng2/docs/design/skills/reverse-doing-thing/単体テスト設計書.md" << 'EOF'
## テスト対象
| スクリプト | 自己テストの実行 | ケース数 |
|---|---|---|
| a.sh | あり | 3 |
## §1 テスト観点
| キー | 観点 | 確かめる手段 |
|---|---|---|
| k1 | v1 | m1 |
## §2 テストケース一覧
| キー | 番号 | スクリプト | 前提 | 操作 | 期待値 |
|---|---|---|---|---|---|
| c1 | 1 | a.sh | p | o | e |
## §5 異常系
## §6 境界値
EOF
  cp "$tmp/ok/docs/design/requirements/要件と機能の対応表.md" "$tmp/ng2/docs/design/requirements/要件と機能の対応表.md"
  total=$((total + 1))
  fail_count=0; check_repo "$tmp/ng2" > /dev/null 2>&1; if [ "$fail_count" -gt 0 ]; then pass=$((pass + 1)); else echo "[SELFTEST-FAIL] ケース3(不合格想定)が合格" >&2; fi

  # ケース4: ルート不在 → 判定不能(2)
  total=$((total + 1))
  check_repo "$tmp/does-not-exist" > /dev/null 2>&1
  if [ "$?" = 2 ]; then pass=$((pass + 1)); else echo "[SELFTEST-FAIL] ケース4(判定不能想定)が異なる終了コード" >&2; fi

  # ケース5: setup単位の機能は対象外（reverse機能が0件なら判定不能のまま）
  mkdir -p "$tmp/setup-only/docs/skills/setup-doing-thing"
  touch "$tmp/setup-only/docs/skills/setup-doing-thing/SKILL.md"
  total=$((total + 1))
  check_repo "$tmp/setup-only" > /dev/null 2>&1
  if [ "$?" = 2 ]; then pass=$((pass + 1)); else echo "[SELFTEST-FAIL] ケース5(setup単位のみは判定不能想定)が異なる終了コード" >&2; fi

  echo "実行 ${total} 件 / 合格 ${pass} 件"
  [ "$pass" = "$total" ]
}

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi
  local root="${1:-}"
  if [ -z "$root" ]; then
    echo "使い方: check-skill-design-docs.sh <リポジトリのルート>" >&2
    exit 2
  fi
  check_repo "$root"
  local rc=$?
  if [ "$rc" = 2 ]; then exit 2; fi
  if [ "$fail_count" -gt 0 ]; then
    echo "不合格 ${fail_count} 件 / 警告 ${warn_count} 件" >&2
    exit 1
  fi
  echo "合格（警告 ${warn_count} 件）"
  exit 0
}

main "$@"
