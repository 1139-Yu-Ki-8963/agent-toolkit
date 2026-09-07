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

# $1 = file, $2 = セクション見出し。見出し直後の表本体行（先頭 | 、区切り行 |---| を除く）を
# 1行1レコードで標準出力へ出す（先頭・末尾の | を除いた生の行）。
extract_table_rows() {
  local file="$1" heading="$2"
  awk -v h="$heading" '
    $0 == h { f = 1; next }
    f && /^## / { exit }
    f && /^\|/ {
      if (n == 0) { n = 1; next }         # ヘッダ行
      if ($0 ~ /^\|[- :|]+\|$/) { next }  # 区切り行
      print
    }
  ' "$file"
}

# 表の行文字列を列配列へ分割する（先頭・末尾の | を落としてから split）
split_cols() {
  local line="$1"
  line="${line#|}"
  line="${line%|}"
  # セル内のエスケープ済みパイプ（`\|`）を列区切りと誤認しないよう、分割前に
  # 一時退避してから戻す（2026-09-06追加: reverse-building-confirmation-items
  # の§2に`A\|Bのどちらを既定にするか`という実物のセルがあり、退避しないと
  # このセルだけ列がずれ、後続列すべての値がずれて誤判定していた）。
  line="${line//\\|/$'\x01'}"
  IFS='|' read -r -a __cols <<< "$line"
  local __i
  for __i in "${!__cols[@]}"; do
    __cols[$__i]="${__cols[$__i]//$'\x01'/|}"
  done
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# 単体テスト設計書の「§7 網羅基準」末尾の自己テスト件数表は、スクリプト列に
# `--self-test`の引数や`（…）`の注記を書く実物がある（例:
# `scripts/list-units.sh --self-test`・`tests/test-self-tests.sh（独自ケース）`）。
# これらを除いた素のパスだけを取り出す。
clean_script_ref() {
  local s
  s="$(trim "$1")"
  s="${s%（*）}"
  s="${s% --self-test}"
  trim "$s"
}

# 素のパスから実物のスクリプトファイルを解決する。"/"を含めばサブディレクトリ
# 込みの相対パスとして`docs/skills/<name>/`直下から見る。含まなければ
# `scripts/`配下にあるという命名の決まり（skill-naming規約）を前提に補う。
resolve_script_path() {
  local root="$1" name="$2" cleaned="$3" candidate
  [ -n "$cleaned" ] || return 1
  case "$cleaned" in
    */*) candidate="${root%/}/docs/skills/${name}/${cleaned}" ;;
    *) candidate="${root%/}/docs/skills/${name}/scripts/${cleaned}" ;;
  esac
  [ -f "$candidate" ] || return 1
  printf '%s' "$candidate"
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

  # macOS標準のbash3.2は連想配列（declare -A/local -A）を持たないため、
  # 集合の判定はワークディレクトリ内のファイル（1行1キー）とgrep -Fxqの
  # 完全一致検索で行う（check-business-names.shのfold_containsと同じ流儀）。
  local work
  work="$(mktemp -d "${TMPDIR:-/tmp}/check-skill-design-docs.XXXXXX")" || {
    echo "[FAIL] 作業領域を作れません" >&2
    return 2
  }
  # trap ... RETURNはbashの仕様上、check_repo自身の返りだけでなく以後に
  # 呼ばれる他関数の返りにも残り続けるため使わない（自己テストのself_test内で
  # 後続の関数呼び出しのたびに本trapが再実行され、スコープ外の$workを参照して
  # unbound variableになった実測に基づく）。関数末尾で明示的に掃除する。

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

      # §1 テスト観点の観点キー一覧（1列目）を集める
      : > "$work/viewpoint_keys.txt"
      local vrow
      while IFS= read -r vrow; do
        [ -n "$vrow" ] || continue
        split_cols "$vrow"
        local vk
        vk="$(trim "${__cols[0]:-}")"
        [ -n "$vk" ] && printf '%s\n' "$vk" >> "$work/viewpoint_keys.txt"
      done < <(extract_table_rows "$ud" "## §1 テスト観点")

      # 自己テストの表: スクリプト | 件数 の2列。「## §7 網羅基準」節の内側
      # （末尾に置く実測件数の表を含む）から拾う。独立した「## 自己テスト」
      # 見出しは実物のどの単体テスト設計書も持たないため検索対象にしない
      # （2026-09-05 実測: rule.md「§7の末尾に置いてもよい」の記述と現物は
      # 一致していたが、本チェッカーだけが独立見出しを前提にしており、
      # 実測不一致を1件も検出していなかった）。
      #
      # スクリプト列の値は実物では素のファイル名だけとは限らず、
      # `scripts/list-units.sh --self-test`・`tests/test-self-tests.sh（独自
      # ケース）`のように`--self-test`の引数や`（…）`の注記、`scripts/`等の
      # サブディレクトリ接頭辞を伴う（2026-09-05 実測: find -name によるbasename
      # 照合ではこれらに1件もヒットせず、22件全件が判定不能警告になっていた）。
      # clean_script_ref/resolve_script_pathで注記を除いてから
      # `docs/skills/<機能>/`を起点に実在を確かめる。
      #
      # §2の10列目（自己テストのケース名）と自己テストの出力を双方向で照合
      # するため、先に本節で実行できるスクリプトの一覧と実物の出力を集めて
      # おく（2026-09-06追加: 件数という集計値の一致だけでは、自己テストに
      # ケースを足しても§2へ足さない抜け道を検出できなかった）。
      : > "$work/actual_case_set.txt"
      local resolvable_count=0
      local srow script expect actual
      while IFS= read -r srow; do
        [ -n "$srow" ] || continue
        split_cols "$srow"
        script="$(trim "${__cols[0]:-}")"
        expect="$(trim "${__cols[$((${#__cols[@]} - 1))]:-}")"
        [ -n "$script" ] || continue
        if [[ "$expect" != [0-9]* ]]; then
          continue
        fi
        local cleaned script_path
        cleaned="$(clean_script_ref "$script")"
        script_path="$(resolve_script_path "$root" "$name" "$cleaned")"
        if [ -z "$script_path" ] || [ ! -x "$script_path" ]; then
          warn "自己テストの実物確認が判定不能: $name / $script（見つからない、または実行権限が無い）"
          continue
        fi
        resolvable_count=$((resolvable_count + 1))
      done < <(extract_table_rows "$ud" "## §7 網羅基準")

      while IFS= read -r srow; do
        [ -n "$srow" ] || continue
        split_cols "$srow"
        script="$(trim "${__cols[0]:-}")"
        expect="$(trim "${__cols[$((${#__cols[@]} - 1))]:-}")"
        [ -n "$script" ] || continue
        if [[ "$expect" != [0-9]* ]]; then
          continue
        fi
        local cleaned script_path
        cleaned="$(clean_script_ref "$script")"
        script_path="$(resolve_script_path "$root" "$name" "$cleaned")"
        if [ -z "$script_path" ] || [ ! -x "$script_path" ]; then
          continue
        fi
        local out
        out="$("$script_path" --self-test 2>&1)"
        local rc=$?
        if [ "$rc" != 0 ] && [ "$rc" != 1 ]; then
          warn "自己テストの実物確認が判定不能: $name / $script（--self-test を実行できない）"
          continue
        fi
        # 「実行 N 件」は自身が他スクリプトの--self-testを子として呼ぶ場合、
        # 子の集計行が先に出力されうる。最後の出現（自身の最終集計）を取る。
        actual="$(printf '%s\n' "$out" | grep -o '実行 [0-9]\+ 件' | grep -o '[0-9]\+' | tail -n 1)"
        if [ -z "$actual" ]; then
          # PASS行は "  [PASS] ケース1: ..." のように行頭に空白を伴う実装がある
          # ため、行頭からの完全一致ではなく出現有無で数える。
          actual="$(printf '%s\n' "$out" | grep -c '\[PASS\]')"
        fi
        if [ "$actual" != "$expect" ]; then
          fail "単体テスト設計書の自己テストの件数が実物と不一致: $name / $script (記載=$expect, 実物=$actual)"
        fi
        # ケース名の集合を作る。実行できるスクリプトが複数ある文書は
        # 「<スクリプトの表記> ケースN: ...」の形で一意にし、1本だけの
        # 文書は素の「ケースN: ...」のまま照合する。
        #
        # 自己テストの出力形式は実物で2通りある（2026-09-06実測）。
        # 「  [PASS] ケースN: 説明」の角括弧形と「PASS: 説明」のコロン形。
        # 両方を拾い、先頭の印（`[FAIL]`の場合は末尾の期待終了コードの
        # 注記も）を外して名前を残す。
        #
        # 出力全体をそのまま拾うと、他スクリプトの--self-testを子として
        # 呼ぶ入口（tests/test-self-tests.sh等）で子の出力ぶんまで自分の
        # ケースとして数えてしまう（2026-09-06実測: reverse-sharedの
        # tests/test-self-tests.shは実測20件のところPASS/FAIL形式の行が
        # 195件あった）。件数チェックで確定した$actual件を末尾から
        # 取り、自身の最終集計ぶんだけに絞る。
        local case_line case_name
        while IFS= read -r case_line; do
          [ -n "$case_line" ] || continue
          case_name="$(printf '%s' "$case_line" \
            | sed -E 's/^[[:space:]]*\[(PASS|FAIL)\][[:space:]]*//; s/^(PASS|FAIL): ?//; s/（期待終了コード[^）]*）$//')"
          [ -n "$case_name" ] || continue
          if [ "$resolvable_count" -gt 1 ]; then
            printf '%s\n' "$script $case_name" >> "$work/actual_case_set.txt"
          else
            printf '%s\n' "$case_name" >> "$work/actual_case_set.txt"
          fi
        done < <(
          if [[ "$actual" == [0-9]* ]]; then
            printf '%s\n' "$out" | grep -E '^[[:space:]]*(\[(PASS|FAIL)\]|(PASS|FAIL):)' | tail -n "$actual"
          else
            printf '%s\n' "$out" | grep -E '^[[:space:]]*(\[(PASS|FAIL)\]|(PASS|FAIL):)'
          fi
        )
      done < <(extract_table_rows "$ud" "## §7 網羅基準")

      # §7の表は`--self-test`を持つ全スクリプトとtests/test-self-tests.shの
      # 独自ケースを網羅する（rule.md「自己テストの件数が実物と一致する」の
      # 追記分）。表に無いスクリプトは、件数が実物と一致するかを1度も
      # 照合されないまますり抜ける（2026-09-06実測: 表への未登録は本チェッカー
      # の既存ループでは検出できず、テスト設計書のレビュー指摘で見つかった）。
      # 表記は`scripts/a.sh`のようにサブディレクトリ接頭辞を伴う実物と、
      # `a.sh`のように伴わない実物の両方があるため、文字列同士ではなく
      # resolve_script_pathで解決した実ファイルパス同士で突き合わせる。
      : > "$work/registered_paths.txt"
      local rrow rscript rcleaned rpath
      while IFS= read -r rrow; do
        [ -n "$rrow" ] || continue
        split_cols "$rrow"
        rscript="$(trim "${__cols[0]:-}")"
        [ -n "$rscript" ] || continue
        rcleaned="$(clean_script_ref "$rscript")"
        rpath="$(resolve_script_path "$root" "$name" "$rcleaned")"
        [ -n "$rpath" ] && printf '%s\n' "$rpath" >> "$work/registered_paths.txt"
      done < <(extract_table_rows "$ud" "## §7 網羅基準")

      local func_dir="$root/docs/skills/$name"
      local sfile
      if [ -d "$func_dir/scripts" ]; then
        for sfile in "$func_dir"/scripts/*.sh; do
          [ -f "$sfile" ] || continue
          grep -q -- '--self-test' "$sfile" 2>/dev/null || continue
          if ! grep -Fxq -- "$sfile" "$work/registered_paths.txt" 2>/dev/null; then
            fail "自己テスト-未登録: $name scripts/$(basename "$sfile")"
          fi
        done
      fi
      # tests/test-self-tests.shは実物に2種類ある（2026-09-06実測）。他の
      # スクリプトの--self-testを右から左へ委譲するだけの薄い入口（関数定義
      # 0〜1個。委譲先自身の§7登録で既に照合される）と、check_reference_paths
      # のような自前の判定ロジックを持つもの（関数定義2個以上）。後者だけが
      # rule.mdの言う「独自ケース」であり登録を要する。薄い入口まで一律に
      # 要求すると、委譲先の判定と同じ内容を二重に登録することになる。
      if [ -f "$func_dir/tests/test-self-tests.sh" ]; then
        local fn_count
        fn_count="$(grep -cE '^[a-zA-Z_][a-zA-Z0-9_]*\(\)[[:space:]]*\{' "$func_dir/tests/test-self-tests.sh" 2>/dev/null)"
        if [ "${fn_count:-0}" -gt 1 ] && ! grep -Fxq -- "$func_dir/tests/test-self-tests.sh" "$work/registered_paths.txt" 2>/dev/null; then
          fail "自己テスト-未登録: $name tests/test-self-tests.sh"
        fi
      fi

      # §2 テストケース一覧: 10列（キー・番号・機能・ケースの名前・対応する
      # 観点のキー・区分・前提・操作・期待結果・自己テストのケース名）
      : > "$work/expected_case_set.txt"
      local crow
      while IFS= read -r crow; do
        [ -n "$crow" ] || continue
        split_cols "$crow"
        local col_key col_vp col_pre col_op col_exp col_case
        col_key="$(trim "${__cols[0]:-}")"
        col_vp="$(trim "${__cols[4]:-}")"
        col_pre="$(trim "${__cols[6]:-}")"
        col_op="$(trim "${__cols[7]:-}")"
        col_exp="$(trim "${__cols[8]:-}")"
        col_case="$(trim "${__cols[9]:-}")"
        if [ -z "$col_pre" ] || [ -z "$col_op" ] || [ -z "$col_exp" ]; then
          fail "単体テスト設計書の§2に前提・操作・期待結果が無い行がある: $name / ${col_key:-(キー不明)}"
        fi
        if [ -n "$col_vp" ] && ! grep -Fxq -- "$col_vp" "$work/viewpoint_keys.txt" 2>/dev/null; then
          fail "単体テスト設計書の§2の観点キーが§1に無い: $name / ${col_key:-(キー不明)} -> $col_vp"
        fi
        if [ -z "$col_case" ]; then
          fail "単体テスト設計書の§2に自己テストのケース名が無い行がある: $name / ${col_key:-(キー不明)}"
        elif [ "$col_case" = "（レビュー）" ]; then
          :
        else
          printf '%s\n' "$col_case" >> "$work/expected_case_set.txt"
          if ! grep -Fxq -- "$col_case" "$work/actual_case_set.txt" 2>/dev/null; then
            fail "単体テスト設計書の§2のケースが自己テストに無い: $name / ${col_key:-(キー不明)} -> $col_case"
          fi
        fi
      done < <(extract_table_rows "$ud" "## §2 テストケース一覧")

      local actual_name
      while IFS= read -r actual_name; do
        [ -n "$actual_name" ] || continue
        if ! grep -Fxq -- "$actual_name" "$work/expected_case_set.txt" 2>/dev/null; then
          fail "単体テスト設計書の自己テストのケースが§2に無い: $name / $actual_name"
        fi
      done < <(LC_ALL=C sort -u "$work/actual_case_set.txt" 2>/dev/null)
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

  rm -rf "$work"
  return 0
}

self_test() {
  tmp=""
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/skill-design-docs.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT
  pass=0; total=0

  write_basic() {
    cat > "$1" << 'INNER_EOF'
## §1 外部仕様
| 要件の柱 | 要件の項目 | この機能が満たす内容 |
|---|---|---|
| 柱1 | x | y |
## §2 業務仕様
## §3 方式設計
## §4 データ仕様
## §5 エラーと例外
## §6 関連資料
INNER_EOF
  }
  write_detail() {
    cat > "$1" << 'INNER_EOF'
## §1 構成要素
## §2 処理の定義
## §3 ロジック
## §4 入出力の値
## §5 エラー処理
## §6 関連資料
INNER_EOF
  }

  # ケース1: 完全な最小リポジトリ → 合格
  mkdir -p "$tmp/ok/docs/skills/reverse-doing-thing"
  mkdir -p "$tmp/ok/docs/design/skills/reverse-doing-thing"
  mkdir -p "$tmp/ok/docs/design/requirements"
  touch "$tmp/ok/docs/skills/reverse-doing-thing/SKILL.md"
  write_basic "$tmp/ok/docs/design/skills/reverse-doing-thing/基本設計書.md"
  write_detail "$tmp/ok/docs/design/skills/reverse-doing-thing/詳細設計書.md"
  cat > "$tmp/ok/docs/design/skills/reverse-doing-thing/単体テスト設計書.md" << 'INNER_EOF'
## テスト対象
| スクリプト | 自己テストの実行 |
|---|---|
| a.sh | あり |
## §1 テスト観点
| キー | 観点 | 確かめる手段 |
|---|---|---|
| k1 | v1 | m1 |
## §2 テストケース一覧
| キー | 番号 | 機能 | ケースの名前 | 対応する観点のキー | 区分 | 前提 | 操作 | 期待結果 | 自己テストのケース名 |
|---|---|---|---|---|---|---|---|---|---|
| c1 | 1 | f1 | 名前1 | k1 | 正常 | p | o | e | ケース1: 動作1 |
| c2 | 2 | f1 | 名前2 | k1 | 異常 | p | o | e | ケース2: 動作2 |
## §5 異常系
## §6 境界値
## §7 網羅基準

検査スクリプトの自己テストの実測件数は次のとおり。

| スクリプト | 件数 |
|---|---|
| a.sh | 2 |
INNER_EOF
  cat > "$tmp/ok/docs/design/requirements/要件と機能の対応表.md" << 'INNER_EOF'
| 柱1 | x | reverse-doing-thing | c | 対応済み |
| reverse-doing-thing | 何か |
INNER_EOF
  mkdir -p "$tmp/ok/docs/skills/reverse-doing-thing/scripts"
  cat > "$tmp/ok/docs/skills/reverse-doing-thing/scripts/a.sh" << 'INNER_EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "  [PASS] ケース1: 動作1"
  echo "  [PASS] ケース2: 動作2"
  echo "実行 2 件 / 合格 2 件"
  exit 0
fi
exit 0
INNER_EOF
  chmod +x "$tmp/ok/docs/skills/reverse-doing-thing/scripts/a.sh"
  total=$((total + 1))
  fail_count=0; check_repo "$tmp/ok" > /dev/null 2>&1; if [ "$fail_count" = 0 ]; then pass=$((pass + 1)); else echo "[SELFTEST-FAIL] ケース1(合格想定)が不合格" >&2; fi

  # ケース2: 基本設計書が無い → 不合格
  mkdir -p "$tmp/ng1/docs/skills/reverse-doing-thing"
  mkdir -p "$tmp/ng1/docs/design/requirements"
  touch "$tmp/ng1/docs/skills/reverse-doing-thing/SKILL.md"
  total=$((total + 1))
  fail_count=0; check_repo "$tmp/ng1" > /dev/null 2>&1; if [ "$fail_count" -gt 0 ]; then pass=$((pass + 1)); else echo "[SELFTEST-FAIL] ケース2(不合格想定)が合格" >&2; fi

  # ケース3: §2に前提・操作・期待結果が空の行がある → 不合格
  mkdir -p "$tmp/ng2/docs/skills/reverse-doing-thing"
  mkdir -p "$tmp/ng2/docs/design/skills/reverse-doing-thing"
  mkdir -p "$tmp/ng2/docs/design/requirements"
  touch "$tmp/ng2/docs/skills/reverse-doing-thing/SKILL.md"
  write_basic "$tmp/ng2/docs/design/skills/reverse-doing-thing/基本設計書.md"
  write_detail "$tmp/ng2/docs/design/skills/reverse-doing-thing/詳細設計書.md"
  cat > "$tmp/ng2/docs/design/skills/reverse-doing-thing/単体テスト設計書.md" << 'INNER_EOF'
## テスト対象
| スクリプト | 自己テストの実行 |
|---|---|
| a.sh | あり |
## §1 テスト観点
| キー | 観点 | 確かめる手段 |
|---|---|---|
| k1 | v1 | m1 |
## §2 テストケース一覧
| キー | 番号 | 機能 | ケースの名前 | 対応する観点のキー | 区分 | 前提 | 操作 | 期待結果 |
|---|---|---|---|---|---|---|---|---|
| c1 | 1 | f1 | 名前1 | k1 | 正常 |  | o | e |
## §5 異常系
## §6 境界値
## §7 網羅基準

検査スクリプトの自己テストの実測件数は次のとおり。

| スクリプト | 件数 |
|---|---|
| a.sh | 1 |
INNER_EOF
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

  # ケース6: §2の観点キーが§1に無い → 不合格
  mkdir -p "$tmp/ng3/docs/skills/reverse-doing-thing"
  mkdir -p "$tmp/ng3/docs/design/skills/reverse-doing-thing"
  mkdir -p "$tmp/ng3/docs/design/requirements"
  touch "$tmp/ng3/docs/skills/reverse-doing-thing/SKILL.md"
  write_basic "$tmp/ng3/docs/design/skills/reverse-doing-thing/基本設計書.md"
  write_detail "$tmp/ng3/docs/design/skills/reverse-doing-thing/詳細設計書.md"
  cat > "$tmp/ng3/docs/design/skills/reverse-doing-thing/単体テスト設計書.md" << 'INNER_EOF'
## テスト対象
| スクリプト | 自己テストの実行 |
|---|---|
| a.sh | あり |
## §1 テスト観点
| キー | 観点 | 確かめる手段 |
|---|---|---|
| k1 | v1 | m1 |
## §2 テストケース一覧
| キー | 番号 | 機能 | ケースの名前 | 対応する観点のキー | 区分 | 前提 | 操作 | 期待結果 |
|---|---|---|---|---|---|---|---|---|
| c1 | 1 | f1 | 名前1 | k9 | 正常 | p | o | e |
## §5 異常系
## §6 境界値
## §7 網羅基準

検査スクリプトの自己テストの実測件数は次のとおり。

| スクリプト | 件数 |
|---|---|
| a.sh | 1 |
INNER_EOF
  cp "$tmp/ok/docs/design/requirements/要件と機能の対応表.md" "$tmp/ng3/docs/design/requirements/要件と機能の対応表.md"
  total=$((total + 1))
  fail_count=0; check_repo "$tmp/ng3" > /dev/null 2>&1; if [ "$fail_count" -gt 0 ]; then pass=$((pass + 1)); else echo "[SELFTEST-FAIL] ケース6(不合格想定)が合格" >&2; fi

  # ケース7: 自己テストの件数が実物とずれる → 不合格
  mkdir -p "$tmp/ng4/docs/skills/reverse-doing-thing"
  mkdir -p "$tmp/ng4/docs/design/skills/reverse-doing-thing"
  mkdir -p "$tmp/ng4/docs/design/requirements"
  mkdir -p "$tmp/ng4/docs/skills/reverse-doing-thing/scripts"
  touch "$tmp/ng4/docs/skills/reverse-doing-thing/SKILL.md"
  write_basic "$tmp/ng4/docs/design/skills/reverse-doing-thing/基本設計書.md"
  write_detail "$tmp/ng4/docs/design/skills/reverse-doing-thing/詳細設計書.md"
  cat > "$tmp/ng4/docs/design/skills/reverse-doing-thing/単体テスト設計書.md" << 'INNER_EOF'
## テスト対象
| スクリプト | 自己テストの実行 |
|---|---|
| a.sh | あり |
## §1 テスト観点
| キー | 観点 | 確かめる手段 |
|---|---|---|
| k1 | v1 | m1 |
## §2 テストケース一覧
| キー | 番号 | 機能 | ケースの名前 | 対応する観点のキー | 区分 | 前提 | 操作 | 期待結果 |
|---|---|---|---|---|---|---|---|---|
| c1 | 1 | f1 | 名前1 | k1 | 正常 | p | o | e |
## §5 異常系
## §6 境界値
## §7 網羅基準

検査スクリプトの自己テストの実測件数は次のとおり。

| スクリプト | 件数 |
|---|---|
| a.sh | 3 |
INNER_EOF
  cat > "$tmp/ng4/docs/skills/reverse-doing-thing/scripts/a.sh" << 'INNER_EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "実行 2 件 / 合格 2 件"
  exit 0
fi
exit 0
INNER_EOF
  chmod +x "$tmp/ng4/docs/skills/reverse-doing-thing/scripts/a.sh"
  cp "$tmp/ok/docs/design/requirements/要件と機能の対応表.md" "$tmp/ng4/docs/design/requirements/要件と機能の対応表.md"
  total=$((total + 1))
  fail_count=0; check_repo "$tmp/ng4" > /dev/null 2>&1; if [ "$fail_count" -gt 0 ]; then pass=$((pass + 1)); else echo "[SELFTEST-FAIL] ケース7(不合格想定)が合格" >&2; fi

  # ケース8: §7網羅基準に観点/基準の表（非数値）と自己テストの件数表が
  # 独立見出し無しで同居する実物の形でも、件数のずれを検出する
  # （2026-09-05実測: 独立見出し「## 自己テスト」を前提にしていた旧実装は
  # 実物のどの単体テスト設計書にも一致せず、この検出を1件も行っていなかった）
  mkdir -p "$tmp/ng5/docs/skills/reverse-doing-thing/scripts"
  mkdir -p "$tmp/ng5/docs/design/skills/reverse-doing-thing"
  mkdir -p "$tmp/ng5/docs/design/requirements"
  touch "$tmp/ng5/docs/skills/reverse-doing-thing/SKILL.md"
  write_basic "$tmp/ng5/docs/design/skills/reverse-doing-thing/基本設計書.md"
  write_detail "$tmp/ng5/docs/design/skills/reverse-doing-thing/詳細設計書.md"
  cat > "$tmp/ng5/docs/design/skills/reverse-doing-thing/単体テスト設計書.md" << 'INNER_EOF'
## テスト対象
| スクリプト | 自己テストの実行 |
|---|---|
| a.sh | あり |
## §1 テスト観点
| キー | 観点 | 確かめる手段 |
|---|---|---|
| k1 | v1 | m1 |
## §2 テストケース一覧
| キー | 番号 | 機能 | ケースの名前 | 対応する観点のキー | 区分 | 前提 | 操作 | 期待結果 |
|---|---|---|---|---|---|---|---|---|
| c1 | 1 | f1 | 名前1 | k1 | 正常 | p | o | e |
## §5 異常系
## §6 境界値
## §7 網羅基準

| 観点 | 基準 |
|---|---|
| 条件の網羅 | §1の全観点に§2のケースを1件以上対応させる |

検査スクリプトの自己テストの実測件数は次のとおり。

| スクリプト | 件数 |
|---|---|
| scripts/a.sh --self-test | 9 |
INNER_EOF
  cat > "$tmp/ng5/docs/skills/reverse-doing-thing/scripts/a.sh" << 'INNER_EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "実行 2 件 / 合格 2 件"
  exit 0
fi
exit 0
INNER_EOF
  chmod +x "$tmp/ng5/docs/skills/reverse-doing-thing/scripts/a.sh"
  cp "$tmp/ok/docs/design/requirements/要件と機能の対応表.md" "$tmp/ng5/docs/design/requirements/要件と機能の対応表.md"
  total=$((total + 1))
  fail_count=0; check_repo "$tmp/ng5" > /dev/null 2>&1
  if [ "$fail_count" -gt 0 ]; then
    pass=$((pass + 1))
  else
    echo "[SELFTEST-FAIL] ケース8(§7内の観点表と件数表が同居しても件数ずれを検出する想定)が合格" >&2
  fi

  # ケース9: スクリプト列が`tests/xxx.sh（注記）`の実物形（reverse-sharedの
  # 単体テスト設計書と同じ形）でも、件数が一致すれば警告・不合格にならない
  # （2026-09-05実測: この形の実物照合は1件も行われていなかった不具合の
  # 直接の再現。件数が合っているのに誤って不合格にしないことも確かめる）
  mkdir -p "$tmp/ok2/docs/skills/reverse-doing-thing/tests"
  mkdir -p "$tmp/ok2/docs/design/skills/reverse-doing-thing"
  mkdir -p "$tmp/ok2/docs/design/requirements"
  touch "$tmp/ok2/docs/skills/reverse-doing-thing/SKILL.md"
  write_basic "$tmp/ok2/docs/design/skills/reverse-doing-thing/基本設計書.md"
  write_detail "$tmp/ok2/docs/design/skills/reverse-doing-thing/詳細設計書.md"
  cat > "$tmp/ok2/docs/design/skills/reverse-doing-thing/単体テスト設計書.md" << 'INNER_EOF'
## テスト対象
| スクリプト | 自己テストの実行 |
|---|---|
| a.sh | あり |
## §1 テスト観点
| キー | 観点 | 確かめる手段 |
|---|---|---|
| k1 | v1 | m1 |
## §2 テストケース一覧
| キー | 番号 | 機能 | ケースの名前 | 対応する観点のキー | 区分 | 前提 | 操作 | 期待結果 | 自己テストのケース名 |
|---|---|---|---|---|---|---|---|---|---|
| c1 | 1 | f1 | 名前1 | k1 | 正常 | p | o | e | ケース1: 動作1 |
## §5 異常系
## §6 境界値
## §7 網羅基準

検査スクリプトの自己テストの実測件数は次のとおり。

| スクリプト | 件数 |
|---|---|
| tests/a.sh（独自ケース） | 1 |
INNER_EOF
  cat > "$tmp/ok2/docs/skills/reverse-doing-thing/tests/a.sh" << 'INNER_EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "  [PASS] ケース1: 動作1"
  echo "実行 1 件 / 合格 1 件"
  exit 0
fi
exit 0
INNER_EOF
  chmod +x "$tmp/ok2/docs/skills/reverse-doing-thing/tests/a.sh"
  cp "$tmp/ok/docs/design/requirements/要件と機能の対応表.md" "$tmp/ok2/docs/design/requirements/要件と機能の対応表.md"
  total=$((total + 1))
  fail_count=0; warn_count=0; check_repo "$tmp/ok2" > /dev/null 2>&1
  if [ "$fail_count" = 0 ] && [ "$warn_count" = 0 ]; then
    pass=$((pass + 1))
  else
    echo "[SELFTEST-FAIL] ケース9(tests/xxx.sh（注記）形の実物照合が合格想定)が不合格または警告 (fail=${fail_count} warn=${warn_count})" >&2
  fi

  # ケース11: §2の10列目（自己テストのケース名）が自己テストの出力と
  # 1対1で一致する → 合格（2026-09-06追加）
  mkdir -p "$tmp/ok3/docs/skills/reverse-doing-thing/scripts"
  mkdir -p "$tmp/ok3/docs/design/skills/reverse-doing-thing"
  mkdir -p "$tmp/ok3/docs/design/requirements"
  touch "$tmp/ok3/docs/skills/reverse-doing-thing/SKILL.md"
  write_basic "$tmp/ok3/docs/design/skills/reverse-doing-thing/基本設計書.md"
  write_detail "$tmp/ok3/docs/design/skills/reverse-doing-thing/詳細設計書.md"
  cat > "$tmp/ok3/docs/design/skills/reverse-doing-thing/単体テスト設計書.md" << 'INNER_EOF'
## テスト対象
| スクリプト | 自己テストの実行 |
|---|---|
| a.sh | あり |
## §1 テスト観点
| キー | 観点 | 確かめる手段 |
|---|---|---|
| k1 | v1 | m1 |
## §2 テストケース一覧
| キー | 番号 | 機能 | ケースの名前 | 対応する観点のキー | 区分 | 前提 | 操作 | 期待結果 | 自己テストのケース名 |
|---|---|---|---|---|---|---|---|---|---|
| c1 | 1 | f1 | 名前1 | k1 | 正常 | p | o | e | ケース1: 動作1 |
| c2 | 2 | f1 | 名前2 | k1 | 異常 | p | o | e | ケース2: 動作2 |
## §5 異常系
## §6 境界値
## §7 網羅基準

検査スクリプトの自己テストの実測件数は次のとおり。

| スクリプト | 件数 |
|---|---|
| a.sh | 2 |
INNER_EOF
  cp "$tmp/ok/docs/design/requirements/要件と機能の対応表.md" "$tmp/ok3/docs/design/requirements/要件と機能の対応表.md"
  cat > "$tmp/ok3/docs/skills/reverse-doing-thing/scripts/a.sh" << 'INNER_EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "  [PASS] ケース1: 動作1"
  echo "  [PASS] ケース2: 動作2"
  echo "実行 2 件 / 合格 2 件"
  exit 0
fi
exit 0
INNER_EOF
  chmod +x "$tmp/ok3/docs/skills/reverse-doing-thing/scripts/a.sh"
  total=$((total + 1))
  fail_count=0; check_repo "$tmp/ok3" > /dev/null 2>&1
  if [ "$fail_count" = 0 ]; then
    pass=$((pass + 1))
  else
    echo "[SELFTEST-FAIL] ケース11(§2と自己テストの1対1一致は合格想定)が不合格" >&2
  fi

  # ケース12: 自己テストにあって§2に無いケースがある → 不合格
  mkdir -p "$tmp/ng7/docs/skills/reverse-doing-thing/scripts"
  mkdir -p "$tmp/ng7/docs/design/skills/reverse-doing-thing"
  mkdir -p "$tmp/ng7/docs/design/requirements"
  touch "$tmp/ng7/docs/skills/reverse-doing-thing/SKILL.md"
  write_basic "$tmp/ng7/docs/design/skills/reverse-doing-thing/基本設計書.md"
  write_detail "$tmp/ng7/docs/design/skills/reverse-doing-thing/詳細設計書.md"
  cat > "$tmp/ng7/docs/design/skills/reverse-doing-thing/単体テスト設計書.md" << 'INNER_EOF'
## テスト対象
| スクリプト | 自己テストの実行 |
|---|---|
| a.sh | あり |
## §1 テスト観点
| キー | 観点 | 確かめる手段 |
|---|---|---|
| k1 | v1 | m1 |
## §2 テストケース一覧
| キー | 番号 | 機能 | ケースの名前 | 対応する観点のキー | 区分 | 前提 | 操作 | 期待結果 | 自己テストのケース名 |
|---|---|---|---|---|---|---|---|---|---|
| c1 | 1 | f1 | 名前1 | k1 | 正常 | p | o | e | ケース1: 動作1 |
## §5 異常系
## §6 境界値
## §7 網羅基準

検査スクリプトの自己テストの実測件数は次のとおり。

| スクリプト | 件数 |
|---|---|
| a.sh | 2 |
INNER_EOF
  cp "$tmp/ok/docs/design/requirements/要件と機能の対応表.md" "$tmp/ng7/docs/design/requirements/要件と機能の対応表.md"
  cat > "$tmp/ng7/docs/skills/reverse-doing-thing/scripts/a.sh" << 'INNER_EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "  [PASS] ケース1: 動作1"
  echo "  [PASS] ケース2: 動作2"
  echo "実行 2 件 / 合格 2 件"
  exit 0
fi
exit 0
INNER_EOF
  chmod +x "$tmp/ng7/docs/skills/reverse-doing-thing/scripts/a.sh"
  total=$((total + 1))
  fail_count=0; check_repo "$tmp/ng7" > /dev/null 2>&1
  if [ "$fail_count" -gt 0 ]; then
    pass=$((pass + 1))
  else
    echo "[SELFTEST-FAIL] ケース12(自己テストにあって§2に無いケースは不合格想定)が合格" >&2
  fi

  # ケース13: §2にあって自己テストに無いケースがある → 不合格
  mkdir -p "$tmp/ng8/docs/skills/reverse-doing-thing/scripts"
  mkdir -p "$tmp/ng8/docs/design/skills/reverse-doing-thing"
  mkdir -p "$tmp/ng8/docs/design/requirements"
  touch "$tmp/ng8/docs/skills/reverse-doing-thing/SKILL.md"
  write_basic "$tmp/ng8/docs/design/skills/reverse-doing-thing/基本設計書.md"
  write_detail "$tmp/ng8/docs/design/skills/reverse-doing-thing/詳細設計書.md"
  cat > "$tmp/ng8/docs/design/skills/reverse-doing-thing/単体テスト設計書.md" << 'INNER_EOF'
## テスト対象
| スクリプト | 自己テストの実行 |
|---|---|
| a.sh | あり |
## §1 テスト観点
| キー | 観点 | 確かめる手段 |
|---|---|---|
| k1 | v1 | m1 |
## §2 テストケース一覧
| キー | 番号 | 機能 | ケースの名前 | 対応する観点のキー | 区分 | 前提 | 操作 | 期待結果 | 自己テストのケース名 |
|---|---|---|---|---|---|---|---|---|---|
| c1 | 1 | f1 | 名前1 | k1 | 正常 | p | o | e | ケース1: 動作1 |
| c2 | 2 | f1 | 名前2 | k1 | 異常 | p | o | e | ケース9: 実在しない |
## §5 異常系
## §6 境界値
## §7 網羅基準

検査スクリプトの自己テストの実測件数は次のとおり。

| スクリプト | 件数 |
|---|---|
| a.sh | 2 |
INNER_EOF
  cp "$tmp/ok/docs/design/requirements/要件と機能の対応表.md" "$tmp/ng8/docs/design/requirements/要件と機能の対応表.md"
  cat > "$tmp/ng8/docs/skills/reverse-doing-thing/scripts/a.sh" << 'INNER_EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "  [PASS] ケース1: 動作1"
  echo "  [PASS] ケース2: 動作2"
  echo "実行 2 件 / 合格 2 件"
  exit 0
fi
exit 0
INNER_EOF
  chmod +x "$tmp/ng8/docs/skills/reverse-doing-thing/scripts/a.sh"
  total=$((total + 1))
  fail_count=0; check_repo "$tmp/ng8" > /dev/null 2>&1
  if [ "$fail_count" -gt 0 ]; then
    pass=$((pass + 1))
  else
    echo "[SELFTEST-FAIL] ケース13(§2にあって自己テストに無いケースは不合格想定)が合格" >&2
  fi

  # ケース14: セル内のエスケープ済みパイプ（`\|`）があっても列がずれず
  # 10列目のケース名が一致する（2026-09-06追加。実物のreverse-building-
  # confirmation-itemsで発見した不具合の再現）
  mkdir -p "$tmp/ok4/docs/skills/reverse-doing-thing/scripts"
  mkdir -p "$tmp/ok4/docs/design/skills/reverse-doing-thing"
  mkdir -p "$tmp/ok4/docs/design/requirements"
  touch "$tmp/ok4/docs/skills/reverse-doing-thing/SKILL.md"
  write_basic "$tmp/ok4/docs/design/skills/reverse-doing-thing/基本設計書.md"
  write_detail "$tmp/ok4/docs/design/skills/reverse-doing-thing/詳細設計書.md"
  cat > "$tmp/ok4/docs/design/skills/reverse-doing-thing/単体テスト設計書.md" << 'INNER_EOF'
## テスト対象
| スクリプト | 自己テストの実行 |
|---|---|
| a.sh | あり |
## §1 テスト観点
| キー | 観点 | 確かめる手段 |
|---|---|---|
| k1 | v1 | m1 |
## §2 テストケース一覧
| キー | 番号 | 機能 | ケースの名前 | 対応する観点のキー | 区分 | 前提 | 操作 | 期待結果 | 自己テストのケース名 |
|---|---|---|---|---|---|---|---|---|---|
| c1 | 1 | f1 | 名前1 | k1 | 正常 | 列に`A\|Bのどちらか` | o | e | ケース1: 動作1 |
## §5 異常系
## §6 境界値
## §7 網羅基準

検査スクリプトの自己テストの実測件数は次のとおり。

| スクリプト | 件数 |
|---|---|
| a.sh | 1 |
INNER_EOF
  cp "$tmp/ok/docs/design/requirements/要件と機能の対応表.md" "$tmp/ok4/docs/design/requirements/要件と機能の対応表.md"
  cat > "$tmp/ok4/docs/skills/reverse-doing-thing/scripts/a.sh" << 'INNER_EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "  [PASS] ケース1: 動作1"
  echo "実行 1 件 / 合格 1 件"
  exit 0
fi
exit 0
INNER_EOF
  chmod +x "$tmp/ok4/docs/skills/reverse-doing-thing/scripts/a.sh"
  total=$((total + 1))
  fail_count=0; check_repo "$tmp/ok4" > /dev/null 2>&1
  if [ "$fail_count" = 0 ]; then
    pass=$((pass + 1))
  else
    echo "[SELFTEST-FAIL] ケース14(セル内のエスケープ済みパイプで列がずれない想定)が不合格" >&2
  fi

  # ケース15: 自己テストの出力が「PASS: 説明」のコロン形（角括弧を使わない
  # 実物の形）でも1対1の照合ができる（2026-09-06追加。reverse-writing-
  # basic-design等の実物形の再現）
  mkdir -p "$tmp/ok5/docs/skills/reverse-doing-thing/scripts"
  mkdir -p "$tmp/ok5/docs/design/skills/reverse-doing-thing"
  mkdir -p "$tmp/ok5/docs/design/requirements"
  touch "$tmp/ok5/docs/skills/reverse-doing-thing/SKILL.md"
  write_basic "$tmp/ok5/docs/design/skills/reverse-doing-thing/基本設計書.md"
  write_detail "$tmp/ok5/docs/design/skills/reverse-doing-thing/詳細設計書.md"
  cat > "$tmp/ok5/docs/design/skills/reverse-doing-thing/単体テスト設計書.md" << 'INNER_EOF'
## テスト対象
| スクリプト | 自己テストの実行 |
|---|---|
| a.sh | あり |
## §1 テスト観点
| キー | 観点 | 確かめる手段 |
|---|---|---|
| k1 | v1 | m1 |
## §2 テストケース一覧
| キー | 番号 | 機能 | ケースの名前 | 対応する観点のキー | 区分 | 前提 | 操作 | 期待結果 | 自己テストのケース名 |
|---|---|---|---|---|---|---|---|---|---|
| c1 | 1 | f1 | 名前1 | k1 | 正常 | p | o | e | 合格-見本 |
## §5 異常系
## §6 境界値
## §7 網羅基準

検査スクリプトの自己テストの実測件数は次のとおり。

| スクリプト | 件数 |
|---|---|
| a.sh | 1 |
INNER_EOF
  cp "$tmp/ok/docs/design/requirements/要件と機能の対応表.md" "$tmp/ok5/docs/design/requirements/要件と機能の対応表.md"
  cat > "$tmp/ok5/docs/skills/reverse-doing-thing/scripts/a.sh" << 'INNER_EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "PASS: 合格-見本"
  echo "実行 1 件 / 失敗 0 件"
  exit 0
fi
exit 0
INNER_EOF
  chmod +x "$tmp/ok5/docs/skills/reverse-doing-thing/scripts/a.sh"
  total=$((total + 1))
  fail_count=0; check_repo "$tmp/ok5" > /dev/null 2>&1
  if [ "$fail_count" = 0 ]; then
    pass=$((pass + 1))
  else
    echo "[SELFTEST-FAIL] ケース15(PASS:コロン形の1対1照合は合格想定)が不合格" >&2
  fi

  # ケース16: 他スクリプトの--self-testを子として呼ぶ入口でも、自身の
  # 最終集計ぶんだけがケース名として数えられる（2026-09-06追加。実物の
  # tests/test-self-tests.shが子の出力を195件含みながら実測20件と
  # 集計する形の再現）
  mkdir -p "$tmp/ok6/docs/skills/reverse-doing-thing/scripts"
  mkdir -p "$tmp/ok6/docs/design/skills/reverse-doing-thing"
  mkdir -p "$tmp/ok6/docs/design/requirements"
  touch "$tmp/ok6/docs/skills/reverse-doing-thing/SKILL.md"
  write_basic "$tmp/ok6/docs/design/skills/reverse-doing-thing/基本設計書.md"
  write_detail "$tmp/ok6/docs/design/skills/reverse-doing-thing/詳細設計書.md"
  cat > "$tmp/ok6/docs/design/skills/reverse-doing-thing/単体テスト設計書.md" << 'INNER_EOF'
## テスト対象
| スクリプト | 自己テストの実行 |
|---|---|
| a.sh | あり |
## §1 テスト観点
| キー | 観点 | 確かめる手段 |
|---|---|---|
| k1 | v1 | m1 |
## §2 テストケース一覧
| キー | 番号 | 機能 | ケースの名前 | 対応する観点のキー | 区分 | 前提 | 操作 | 期待結果 | 自己テストのケース名 |
|---|---|---|---|---|---|---|---|---|---|
| c1 | 1 | f1 | 名前1 | k1 | 正常 | p | o | e | ケース1: 自分の集計 |
## §5 異常系
## §6 境界値
## §7 網羅基準

検査スクリプトの自己テストの実測件数は次のとおり。

| スクリプト | 件数 |
|---|---|
| a.sh | 1 |
INNER_EOF
  cp "$tmp/ok/docs/design/requirements/要件と機能の対応表.md" "$tmp/ok6/docs/design/requirements/要件と機能の対応表.md"
  cat > "$tmp/ok6/docs/skills/reverse-doing-thing/scripts/a.sh" << 'INNER_EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "  [PASS] ケース1: 子の集計その1"
  echo "  [PASS] ケース2: 子の集計その2"
  echo "実行 2 件 / 合格 2 件"
  echo "  [PASS] ケース1: 自分の集計"
  echo "実行 1 件 / 合格 1 件"
  exit 0
fi
exit 0
INNER_EOF
  chmod +x "$tmp/ok6/docs/skills/reverse-doing-thing/scripts/a.sh"
  total=$((total + 1))
  fail_count=0; check_repo "$tmp/ok6" > /dev/null 2>&1
  if [ "$fail_count" = 0 ]; then
    pass=$((pass + 1))
  else
    echo "[SELFTEST-FAIL] ケース16(子の集計を含む出力でも末尾の自分の集計だけを数える想定)が不合格" >&2
  fi

  # ケース17: docs/skills/<機能>/scripts/配下に--self-testを持つスクリプトが
  # あるのに§7の表に登録が無い → 不合格「自己テスト-未登録」（改善指示書対応）
  mkdir -p "$tmp/ng7/docs/skills/reverse-doing-thing/scripts"
  mkdir -p "$tmp/ng7/docs/design/skills/reverse-doing-thing"
  mkdir -p "$tmp/ng7/docs/design/requirements"
  touch "$tmp/ng7/docs/skills/reverse-doing-thing/SKILL.md"
  write_basic "$tmp/ng7/docs/design/skills/reverse-doing-thing/基本設計書.md"
  write_detail "$tmp/ng7/docs/design/skills/reverse-doing-thing/詳細設計書.md"
  cat > "$tmp/ng7/docs/design/skills/reverse-doing-thing/単体テスト設計書.md" << 'INNER_EOF'
## テスト対象
| スクリプト | 自己テストの実行 |
|---|---|
| a.sh | あり |
## §1 テスト観点
| キー | 観点 | 確かめる手段 |
|---|---|---|
| k1 | v1 | m1 |
## §2 テストケース一覧
| キー | 番号 | 機能 | ケースの名前 | 対応する観点のキー | 区分 | 前提 | 操作 | 期待結果 | 自己テストのケース名 |
|---|---|---|---|---|---|---|---|---|---|
| c1 | 1 | f1 | 名前1 | k1 | 正常 | p | o | e | ケース1: 動作1 |
## §5 異常系
## §6 境界値
## §7 網羅基準

検査スクリプトの自己テストの実測件数は次のとおり。

| スクリプト | 件数 |
|---|---|
| a.sh | 1 |
INNER_EOF
  cp "$tmp/ok/docs/design/requirements/要件と機能の対応表.md" "$tmp/ng7/docs/design/requirements/要件と機能の対応表.md"
  cat > "$tmp/ng7/docs/skills/reverse-doing-thing/scripts/a.sh" << 'INNER_EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "  [PASS] ケース1: 動作1"
  echo "実行 1 件 / 合格 1 件"
  exit 0
fi
exit 0
INNER_EOF
  chmod +x "$tmp/ng7/docs/skills/reverse-doing-thing/scripts/a.sh"
  cat > "$tmp/ng7/docs/skills/reverse-doing-thing/scripts/b.sh" << 'INNER_EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "実行 0 件 / 合格 0 件"
  exit 0
fi
exit 0
INNER_EOF
  chmod +x "$tmp/ng7/docs/skills/reverse-doing-thing/scripts/b.sh"
  total=$((total + 1))
  fail_count=0; check_repo "$tmp/ng7" > /dev/null 2>&1
  if [ "$fail_count" -gt 0 ]; then
    pass=$((pass + 1))
  else
    echo "[SELFTEST-FAIL] ケース17(§7未登録のスクリプトは不合格想定)が合格" >&2
  fi

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
