#!/usr/bin/env bash
set -u

# check-test-designs.sh — 種別内結合テスト設計書・種別横断結合テスト設計書を検査する
#
# 目的:
#   テスト設計書の出力が「出力する」のとき、単位が1つ以上ある種別すべてに
#   種別内結合テスト設計書があり、種別横断結合テスト設計書が観点・ケース・
#   受入条件の対応を持つことを機械で確かめる。「出力しない」のときは何も
#   検査せずSKIPする。
#
# 使い方:
#   check-test-designs.sh <対象> --run <実行フォルダ> [--design-root <設計書の置き場>]
#   check-test-designs.sh --self-test
#
# --design-root の既定は `design-root.sh <実行フォルダ>` の戻り値。
#
# 検査キー（内容を要約した意味語。連番禁止）:
#   共有部品-不在      read-run.sh・design-root.sh・list-units-of.sh が見つからない（判定不能）
#   テスト設計書の出力-不明  run.jsonにキーが無い、または値が「出力する」「出力しない」以外（判定不能）
#   文書-不在          単位が1つ以上ある種別の種別内結合テスト設計書、または種別横断結合
#                      テスト設計書が存在しない
#   節-欠落            `##` 見出しの名前・順序・件数が様式と一致しない
#   位置づけ-欠落      見出し直後に「**この節の位置づけ: 」で始まる行が無い
#   未記入-残存        `<...>` 形式のプレースホルダーが残っている
#   位置-禁止          file:line形式の実装位置の記述がある
#   観点キー-不一致    §2の「対応する観点のキー」が§1（種別横断は§1テスト観点表）に無い
#   観点-ケース未対応  §1の観点キーに対応するケースが§2に無い
#   受入条件-未対応    種別横断結合テスト設計書の§4受入条件との対応が空
#
# 終了コード:
#   0 = 全件合格、または「出力しない」でSKIP
#   1 = 1件以上不合格
#   2 = 使い方の誤り・共有部品の不在・テスト設計書の出力が不明（判定不能）
#
# 保守責任者: 人手（ユーザー）。7種別の一覧・節の名前を変えるときは、
#   ../templates/種別内結合テスト設計書.md・../templates/種別横断結合テスト設計書.md と
#   本スクリプトと自己テストを同時に直す。
#
# 廃棄条件: テスト設計書の様式を構造化データに変えた時。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="${SCRIPT_DIR}/../../reverse-shared/scripts"
READ_RUN="${SHARED_DIR}/read-run.sh"
DESIGN_ROOT_SH="${SHARED_DIR}/design-root.sh"
LIST_UNITS="${SHARED_DIR}/list-units-of.sh"

FAIL_COUNT=0
PASS_COUNT=0

fail() {
  echo "[FAIL] $1: $2" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

passck() {
  PASS_COUNT=$((PASS_COUNT + 1))
}

usage_error() {
  echo "使い方: check-test-designs.sh <対象> --run <実行フォルダ> [--design-root <設計書の置き場>]" >&2
  echo "        check-test-designs.sh --self-test" >&2
  exit 2
}

KINDS="screen api table batch report external feature"

kind_folder() {
  case "$1" in
    screen) echo screens ;;
    api) echo apis ;;
    table) echo tables ;;
    batch) echo batches ;;
    report) echo reports ;;
    external) echo externals ;;
    feature) echo features ;;
  esac
}

kind_label() {
  case "$1" in
    screen) echo "画面" ;;
    api) echo "API" ;;
    table) echo "テーブル" ;;
    batch) echo "バッチ" ;;
    report) echo "帳票" ;;
    external) echo "外部連携" ;;
    feature) echo "機能" ;;
  esac
}

REQUIRED_UNIT_HEADINGS='本書が検証するもの
テスト対象
本書が扱わない範囲
§1 テスト観点
§2 テストケース一覧
§3 単位間のつながり
§4 入力条件
§5 期待結果
§6 異常系
§7 前提条件と終了条件
§8 関連資料'

REQUIRED_CROSS_HEADINGS='本書が検証するもの
テスト対象
本書が扱わない範囲
§1 テスト観点表
§2 テストケース一覧
§3 種別をまたぐ流れ
§4 受入条件との対応
§5 入力条件
§6 期待結果
§7 異常系
§8 前提条件と終了条件
§9 関連資料'

extract_headings() {
  grep -E '^## ' "$1" | sed 's/^## //'
}

check_heading_structure() {
  local doc="$1" expected="$2"
  local actual
  actual="$(extract_headings "$doc")"
  if [ "$actual" != "$expected" ]; then
    fail "節-欠落" "${doc}: 節の名前・順序・件数が様式と一致しません（期待: $(printf '%s' "$expected" | tr '\n' '／')／実際: $(printf '%s' "$actual" | tr '\n' '／')）"
    return 1
  fi
  passck
  return 0
}

check_positions() {
  local doc="$1"
  local heading_lines
  heading_lines="$(grep -n '^## ' "$doc")"
  local ok=1
  local hl lineno next_nonblank
  while IFS= read -r hl; do
    [ -n "$hl" ] || continue
    lineno="${hl%%:*}"
    next_nonblank="$(awk -v start="$lineno" 'NR>start && NF>0 {print; exit}' "$doc")"
    case "$next_nonblank" in
      "**この節の位置づけ: "*) ;;
      *)
        fail "位置づけ-欠落" "${doc}:${lineno}: 見出し直後に位置づけの行がありません"
        ok=0
        ;;
    esac
  done <<HEADINGLIST
$heading_lines
HEADINGLIST
  [ "$ok" -eq 1 ] && passck
}

check_placeholder() {
  local doc="$1"
  local hits
  hits="$(grep -nE '<[^<>]+>' "$doc" || true)"
  if [ -n "$hits" ]; then
    fail "未記入-残存" "${doc}: 未記入のプレースホルダーがあります（例: $(printf '%s\n' "$hits" | head -1)）"
  else
    passck
  fi
}

check_fileline() {
  local doc="$1"
  local hits
  hits="$(grep -nE '[A-Za-z0-9_./-]+\.(ts|js|py|rb|php|java|go|pl|cs|tsx|jsx):[0-9]+' "$doc" || true)"
  if [ -n "$hits" ]; then
    fail "位置-禁止" "${doc}: 実装位置(file:line)の記述があります（例: $(printf '%s\n' "$hits" | head -1)）"
  else
    passck
  fi
}

# $1: file $2: heading（"## " 付きの完全一致文字列）
extract_table_rows() {
  local file="$1" heading="$2"
  awk -v h="$heading" '
    $0 == h { f = 1; next }
    f && /^## / { exit }
    f && /^\|/ {
      if (n == 0) { n = 1; next }
      if ($0 ~ /^\|[- :|]+\|$/) { next }
      print
    }
  ' "$file"
}

split_cols() {
  local line="$1"
  line="${line#|}"
  line="${line%|}"
  IFS='|' read -r -a __cols <<< "$line"
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# $1: doc $2: §1見出し（"## §1 テスト観点" または "## §1 テスト観点表"）$3: §2見出し
check_viewpoint_case_consistency() {
  local doc="$1" vp_heading="$2" case_heading="$3"
  local vp_keys_file case_refs_file
  vp_keys_file="$(mktemp "${TMPDIR:-/tmp}/check-test-designs-vp.XXXXXX")"
  case_refs_file="$(mktemp "${TMPDIR:-/tmp}/check-test-designs-case.XXXXXX")"
  : > "$vp_keys_file"
  : > "$case_refs_file"

  local row key
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    split_cols "$row"
    key="$(trim "${__cols[0]:-}")"
    case "$key" in
      ""|*"<"*) continue ;;
    esac
    printf '%s\n' "$key" >> "$vp_keys_file"
  done < <(extract_table_rows "$doc" "$vp_heading")

  while IFS= read -r row; do
    [ -n "$row" ] || continue
    split_cols "$row"
    key="$(trim "${__cols[3]:-}")"
    case "$key" in
      ""|*"<"*) continue ;;
    esac
    printf '%s\n' "$key" >> "$case_refs_file"
  done < <(extract_table_rows "$doc" "$case_heading")

  local ok=1
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    if ! grep -qxF "$key" "$vp_keys_file"; then
      fail "観点キー-不一致" "${doc}: §2が参照する観点「${key}」が${vp_heading#\#\# }にありません"
      ok=0
    fi
  done < "$case_refs_file"

  while IFS= read -r key; do
    [ -n "$key" ] || continue
    if ! grep -qxF "$key" "$case_refs_file"; then
      fail "観点-ケース未対応" "${doc}: ${vp_heading#\#\# }の観点「${key}」に対応するケースが§2にありません"
      ok=0
    fi
  done < "$vp_keys_file"

  rm -f "$vp_keys_file" "$case_refs_file"
  [ "$ok" -eq 1 ] && passck
}

check_acceptance_coverage() {
  local doc="$1"
  local row count=0
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    split_cols "$row"
    local k
    k="$(trim "${__cols[0]:-}")"
    case "$k" in
      ""|*"<"*) continue ;;
    esac
    count=$((count + 1))
  done < <(extract_table_rows "$doc" "## §4 受入条件との対応")
  if [ "$count" -eq 0 ]; then
    fail "受入条件-未対応" "${doc}: §4受入条件との対応に行がありません"
  else
    passck
  fi
}

check_common_doc_body() {
  local doc="$1" expected_headings="$2" vp_heading="$3"
  check_heading_structure "$doc" "$expected_headings"
  check_positions "$doc"
  check_placeholder "$doc"
  check_fileline "$doc"
  check_viewpoint_case_consistency "$doc" "$vp_heading" "## §2 テストケース一覧"
}

run_main_check() {
  local target="$1" run_dir="$2" design_root_override="$3"

  if [ ! -f "$READ_RUN" ] || [ ! -f "$DESIGN_ROOT_SH" ] || [ ! -f "$LIST_UNITS" ]; then
    echo "[FAIL] 共有部品-不在: read-run.sh・design-root.sh・list-units-of.sh のいずれかが見つかりません" >&2
    return 2
  fi

  local tests_output rc
  tests_output="$(bash "$READ_RUN" "$run_dir" "テスト設計書の出力" 2>/dev/null)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "[FAIL] テスト設計書の出力-不明: ${run_dir}/run.json から「テスト設計書の出力」を読めません" >&2
    return 2
  fi

  case "$tests_output" in
    "出力しない")
      echo "[SKIP] テスト設計書の出力が出力しないため何もしません"
      return 0
      ;;
    "出力する") ;;
    *)
      echo "[FAIL] テスト設計書の出力-不明: 値が「出力する」「出力しない」のいずれでもありません（${tests_output}）" >&2
      return 2
      ;;
  esac

  local design_root="$design_root_override"
  if [ -z "$design_root" ]; then
    design_root="$(bash "$DESIGN_ROOT_SH" "$run_dir" 2>/dev/null)"
  fi
  [ -n "$design_root" ] || design_root="$target"

  local kind units_out units_count
  for kind in $KINDS; do
    units_out="$(bash "$LIST_UNITS" "$target" "$kind" --design-root "$design_root" 2>/dev/null)" || units_out=""
    units_count="$(printf '%s\n' "$units_out" | grep -c . || true)"
    if [ "$units_count" -gt 0 ]; then
      local folder label doc
      folder="$(kind_folder "$kind")"
      label="$(kind_label "$kind")"
      doc="${design_root%/}/docs/design/${folder}/${label}結合テスト設計書.md"
      if [ ! -f "$doc" ]; then
        fail "文書-不在" "${doc} が存在しません（種別: ${kind}、単位数: ${units_count}）"
        continue
      fi
      check_common_doc_body "$doc" "$REQUIRED_UNIT_HEADINGS" "## §1 テスト観点"
    fi
  done

  local cross_doc="${design_root%/}/docs/design/common/種別横断結合テスト設計書.md"
  if [ ! -f "$cross_doc" ]; then
    fail "文書-不在" "${cross_doc} が存在しません"
  else
    check_common_doc_body "$cross_doc" "$REQUIRED_CROSS_HEADINGS" "## §1 テスト観点表"
    check_acceptance_coverage "$cross_doc"
  fi

  return 0
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

run_self_test() {
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-test-designs-self-test.XXXXXX")" || { echo "一時領域を作成できません" >&2; return 2; }
  trap 'rm -rf "$tmp"' RETURN

  local total=0 fail=0

  local self_dir own_name
  self_dir="$(cd "$(dirname "$0")" && pwd)"
  own_name="$(basename "$0")"
  local fixture_root="${tmp}/fixture-skills"
  local copy_dir="${fixture_root}/reverse-writing-test-designs/scripts"
  local shared_dir="${fixture_root}/reverse-shared/scripts"
  mkdir -p "$copy_dir" "$shared_dir"
  cp "${self_dir}/${own_name}" "${copy_dir}/${own_name}"
  chmod +x "${copy_dir}/${own_name}"
  local under_test="${copy_dir}/${own_name}"

  write_shared_stubs() {
    cat > "${shared_dir}/read-run.sh" <<'STUBEOF'
#!/usr/bin/env bash
run_dir="$1"; key="$2"
run_json="${run_dir%/}/run.json"
[ -f "$run_json" ] || { echo "[FAIL] run-不在" >&2; exit 2; }
val="$(command -v jq >/dev/null 2>&1 && jq -r --arg k "$key" 'if has($k) then .[$k] else empty end' "$run_json")"
[ -n "$val" ] || { echo "[FAIL] キー-不在" >&2; exit 2; }
printf '%s\n' "$val"
STUBEOF
    chmod +x "${shared_dir}/read-run.sh"

    cat > "${shared_dir}/design-root.sh" <<'STUBEOF'
#!/usr/bin/env bash
run_dir="$1"
run_json="${run_dir%/}/run.json"
val="$(jq -r '."設計書の置き場" // ."対象リポジトリ" // empty' "$run_json" 2>/dev/null)"
printf '%s\n' "$val"
STUBEOF
    chmod +x "${shared_dir}/design-root.sh"

    cat > "${shared_dir}/list-units-of.sh" <<'STUBEOF'
#!/usr/bin/env bash
target="$1"; kind="$2"; shift 2
design_root="$target"
lists=""
while [ $# -gt 0 ]; do
  case "$1" in
    --design-root) design_root="$2"; shift 2 ;;
    --lists) lists="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$lists" ] || lists="${design_root%/}/docs/design/lists"
file="${lists%/}/${kind}.json"
[ -f "$file" ] || exit 2
jq -r '.[] | .["識別子"]' "$file"
STUBEOF
    chmod +x "${shared_dir}/list-units-of.sh"
  }
  write_shared_stubs

  local target="${tmp}/target"
  mkdir -p "${target}/docs/design/lists" "${target}/docs/design/screens" "${target}/docs/design/common"

  write_run_json() {
    cat > "${target}/run.json" <<RUNEOF
{"テスト設計書の出力": "$1", "対象リポジトリ": "${target}"}
RUNEOF
  }

  write_screen_list_one_unit() {
    cat > "${target}/docs/design/lists/screen.json" <<'LISTEOF'
[{"識別子":"src/pages/OrderList.tsx","名前":"OrderList","場所":"src/pages/OrderList.tsx","属するファイル":[]}]
LISTEOF
  }

  write_unit_doc_good() {
    cat > "${target}/docs/design/screens/画面結合テスト設計書.md" <<'DOCEOF'
# 画面結合テスト設計書

## 本書が検証するもの

**この節の位置づけ: 現行実装**

画面遷移を確かめる。

## テスト対象

**この節の位置づけ: 現行実装**

| 単位 | 役割 |
|---|---|
| OrderList | 一覧 |

## 本書が扱わない範囲

**この節の位置づけ: 現行実装**

| 対象外の事項 | 対象外とする理由 | 代わりに確認する資料 |
|---|---|---|
| 単位ごとの入出力 | 単体テスト設計書が持つ | 単体テスト設計書 |

## §1 テスト観点

**この節の位置づけ: 現行実装**

| 観点キー | 観点 | 区分 |
|---|---|---|
| 一覧-遷移 | 一覧から詳細へ遷移する | 正常 |

## §2 テストケース一覧

**この節の位置づけ: 現行実装**

| キー | 番号 | ケースの名前 | 対応する観点のキー | 前提 | 操作 | 期待結果 |
|---|---|---|---|---|---|---|
| 一覧-遷移-1 | 1 | 詳細へ遷移する | 一覧-遷移 | 一覧が表示されている | 行をクリックする | 詳細が表示される |

## §3 単位間のつながり

**この節の位置づけ: 現行実装**

| 起点の単位 | 終点の単位 | つながりの種類 |
|---|---|---|
| OrderList | OrderDetail | 遷移 |

## §4 入力条件

**この節の位置づけ: 現行実装**

一覧に1件以上のデータがある。

## §5 期待結果

**この節の位置づけ: 現行実装**

画面遷移が実測どおりになる。

## §6 異常系

**この節の位置づけ: 現行実装**

| 観点のキー | 発生させる条件 | 期待する例外・エラー |
|---|---|---|
| 一覧-遷移 | データが0件 | 遷移先が空表示になる |

## §7 前提条件と終了条件

**この節の位置づけ: 現行実装**

| 区分 | 内容 |
|---|---|
| 実行の前提条件 | 一覧画面が表示できる |
| 終了の条件 | §1の全観点に§2のケースが対応していること |

## §8 関連資料

**この節の位置づけ: 現行実装**

- 画面基本設計書
DOCEOF
  }

  write_cross_doc_good() {
    cat > "${target}/docs/design/common/種別横断結合テスト設計書.md" <<'DOCEOF'
# 種別横断結合テスト設計書

## 本書が検証するもの

**この節の位置づけ: 現行実装**

種別をまたぐ流れを確かめる。

## テスト対象

**この節の位置づけ: 現行実装**

| 種別 | 役割 |
|---|---|
| 画面 | 入口 |

## 本書が扱わない範囲

**この節の位置づけ: 現行実装**

| 対象外の事項 | 対象外とする理由 | 代わりに確認する資料 |
|---|---|---|
| 同じ種別のつながり | 種別内結合が持つ | 種別内結合テスト設計書 |

## §1 テスト観点表

**この節の位置づけ: 現行実装**

| 観点キー | 観点 | 区分 |
|---|---|---|
| 発注-一連 | 発注から出荷までが一連で通る | 正常 |

## §2 テストケース一覧

**この節の位置づけ: 現行実装**

| キー | 番号 | ケースの名前 | 対応する観点のキー | 前提 | 操作 | 期待結果 |
|---|---|---|---|---|---|---|
| 発注-一連-1 | 1 | 発注から出荷まで通す | 発注-一連 | 在庫がある | 発注操作を行う | 出荷まで完了する |

## §3 種別をまたぐ流れ

**この節の位置づけ: 現行実装**

| 起点の種別 | 終点の種別 | 流れの内容 |
|---|---|---|
| 画面 | バッチ | 発注から出荷指示 |

## §4 受入条件との対応

**この節の位置づけ: 現行実装**

| 受入条件 | 対応するケースのキー |
|---|---|
| 発注から出荷まで一気通貫で完了できること | 発注-一連-1 |

## §5 入力条件

**この節の位置づけ: 現行実装**

在庫が1件以上ある。

## §6 期待結果

**この節の位置づけ: 現行実装**

一連の流れが実測どおりになる。

## §7 異常系

**この節の位置づけ: 現行実装**

| 観点のキー | 発生させる条件 | 期待する例外・エラー |
|---|---|---|
| 発注-一連 | 在庫が0件 | 発注が拒否される |

## §8 前提条件と終了条件

**この節の位置づけ: 現行実装**

| 区分 | 内容 |
|---|---|
| 実行の前提条件 | 在庫データがある |
| 終了の条件 | §1の全観点に§2のケースが対応し、§4の全受入条件にケースが対応していること |

## §9 関連資料

**この節の位置づけ: 現行実装**

- 要件定義書
DOCEOF
  }

  assert_exit() {
    local desc="$1" expected="$2"; shift 2
    total=$((total + 1))
    "$@" > "${tmp}/out.log" 2>"${tmp}/err.log"
    local actual=$?
    if [ "$actual" = "$expected" ]; then
      echo "PASS: ${desc}"
    else
      echo "FAIL: ${desc}（期待終了コード ${expected} / 実際 ${actual}）"
      sed -n '1,20p' "${tmp}/err.log"
      fail=$((fail + 1))
    fi
  }

  assert_stdout_contains() {
    local desc="$1" key="$2"
    total=$((total + 1))
    if grep -qF "$key" "${tmp}/out.log"; then
      echo "PASS: ${desc}"
    else
      echo "FAIL: ${desc}（標準出力に「${key}」がありません）"
      sed -n '1,20p' "${tmp}/out.log"
      fail=$((fail + 1))
    fi
  }

  assert_contains() {
    local desc="$1" key="$2"
    total=$((total + 1))
    if grep -qF "[FAIL] ${key}" "${tmp}/err.log"; then
      echo "PASS: ${desc}"
    else
      echo "FAIL: ${desc}（${key} の不合格が出ていません）"
      sed -n '1,20p' "${tmp}/err.log"
      fail=$((fail + 1))
    fi
  }

  # 出力しない: SKIP
  write_run_json "出力しない"
  assert_exit "出力しない-終了コード0" 0 bash "$under_test" "$target" --run "$target" --design-root "$target"
  assert_stdout_contains "出力しない-SKIP表示" "[SKIP]"

  # 出力する: 合格（単位1件の種別だけ文書を要求）
  write_run_json "出力する"
  write_screen_list_one_unit
  write_unit_doc_good
  write_cross_doc_good
  assert_exit "出力する-合格" 0 bash "$under_test" "$target" --run "$target" --design-root "$target"

  # 文書不在
  mv "${target}/docs/design/screens/画面結合テスト設計書.md" "${tmp}/画面結合テスト設計書.md.bak"
  assert_exit "文書不在-不合格" 1 bash "$under_test" "$target" --run "$target" --design-root "$target"
  assert_contains "文書不在-検査キー" "文書-不在"
  mv "${tmp}/画面結合テスト設計書.md.bak" "${target}/docs/design/screens/画面結合テスト設計書.md"

  # 節欠落（§8を消す）
  grep -v '^## §8 関連資料$' "${target}/docs/design/screens/画面結合テスト設計書.md" | grep -v '^- 画面基本設計書$' > "${tmp}/broken.md"
  cp "${tmp}/broken.md" "${target}/docs/design/screens/画面結合テスト設計書.md"
  assert_exit "節欠落-不合格" 1 bash "$under_test" "$target" --run "$target" --design-root "$target"
  assert_contains "節欠落-検査キー" "節-欠落"
  write_unit_doc_good

  # 観点キー不一致（§2の対応する観点のキーを§1に無い値に変える）
  sed 's/一覧-遷移-1 | 1 | 詳細へ遷移する | 一覧-遷移/一覧-遷移-1 | 1 | 詳細へ遷移する | 存在しない観点/' "${target}/docs/design/screens/画面結合テスト設計書.md" > "${tmp}/mismatch.md"
  cp "${tmp}/mismatch.md" "${target}/docs/design/screens/画面結合テスト設計書.md"
  assert_exit "観点キー不一致-不合格" 1 bash "$under_test" "$target" --run "$target" --design-root "$target"
  assert_contains "観点キー不一致-検査キー" "観点キー-不一致"
  write_unit_doc_good

  # 未記入残存
  sed 's/画面遷移を確かめる。/<記入>/' "${target}/docs/design/screens/画面結合テスト設計書.md" > "${tmp}/placeholder.md"
  cp "${tmp}/placeholder.md" "${target}/docs/design/screens/画面結合テスト設計書.md"
  assert_exit "未記入残存-不合格" 1 bash "$under_test" "$target" --run "$target" --design-root "$target"
  assert_contains "未記入残存-検査キー" "未記入-残存"
  write_unit_doc_good

  # 位置-禁止
  sed 's/画面遷移を確かめる。/src\/pages\/OrderList.tsx:42 を参照する。/' "${target}/docs/design/screens/画面結合テスト設計書.md" > "${tmp}/fileline.md"
  cp "${tmp}/fileline.md" "${target}/docs/design/screens/画面結合テスト設計書.md"
  assert_exit "位置禁止-不合格" 1 bash "$under_test" "$target" --run "$target" --design-root "$target"
  assert_contains "位置禁止-検査キー" "位置-禁止"
  write_unit_doc_good

  # 受入条件-未対応（横断の§4のデータ行を除いて空にする）
  grep -v '^| 発注から出荷まで一気通貫で完了できること | 発注-一連-1 |$' "${target}/docs/design/common/種別横断結合テスト設計書.md" > "${tmp}/nocoverage.md"
  cp "${tmp}/nocoverage.md" "${target}/docs/design/common/種別横断結合テスト設計書.md"
  assert_exit "受入条件未対応-不合格" 1 bash "$under_test" "$target" --run "$target" --design-root "$target"
  assert_contains "受入条件未対応-検査キー" "受入条件-未対応"
  write_cross_doc_good

  # 使い方の誤り
  assert_exit "判定不能-使い方の誤り" 2 bash "$under_test"

  # テスト設計書の出力-不明
  write_run_json "不明な値"
  assert_exit "判定不能-出力値不明" 2 bash "$under_test" "$target" --run "$target" --design-root "$target"
  write_run_json "出力する"

  echo "実行 ${total} 件 / 失敗 ${fail} 件"
  if [ "$fail" -gt 0 ]; then
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------

if [ "${1:-}" = "--self-test" ]; then
  run_self_test
  exit $?
fi

if [ $# -lt 1 ]; then
  usage_error
fi

TARGET="$1"; shift
RUN_DIR=""
DESIGN_ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --run) RUN_DIR="${2:-}"; shift 2 ;;
    --design-root) DESIGN_ROOT="${2:-}"; shift 2 ;;
    *) usage_error ;;
  esac
done
[ -n "$RUN_DIR" ] || usage_error

run_main_check "$TARGET" "$RUN_DIR" "$DESIGN_ROOT"
mrc=$?
if [ "$mrc" -eq 2 ]; then
  exit 2
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "合格 ${PASS_COUNT} 件 / 不合格 ${FAIL_COUNT} 件"
  exit 1
fi
echo "合格 ${PASS_COUNT} 件 / 不合格 ${FAIL_COUNT} 件"
exit 0
