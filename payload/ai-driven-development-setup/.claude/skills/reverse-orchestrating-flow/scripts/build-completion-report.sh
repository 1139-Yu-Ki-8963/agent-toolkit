#!/usr/bin/env bash
set -u

# build-completion-report.sh — 工程2-13（完了報告と受け入れ）の集計を行う
#
# 目的:
#   統括の手順書（SKILL.md）の最後の手順が呼ぶ。納品物一覧（種別・単位・文書・
#   所在の4列）を業務名.jsonから組み立て、各行の文書が実在するかを確かめる。
#   すべて実在すれば完了報告（到達範囲・納品物の件数・確認事項の件数と未回答の
#   件数・実行した機能とその結果・受け入れの欄）を書く。受け入れの欄は人（開発
#   チーム）が書くため常に空で出す（詳細設計書§3「受け入れの欄を空で出す理由」）。
#
# 使い方:
#   build-completion-report.sh <実行フォルダ> --design-root <設計書の置き場>
#   build-completion-report.sh --self-test
#
# 納品物一覧の行の作り方:
#   単位ごとの行は docs/design/lists/業務名.json の各種別の要素（識別子・業務名・
#   区別・フォルダ名）から作る。表示名は区別が無ければ業務名、あれば
#   「業務名（区別）」とする（reverse-listing-unitsのmerge_business_namesと
#   同じ規則。共有部品化されていないための複製）。文書名は
#   reverse-shared/scripts/design-doc-name.sh が
#   返す基本設計書の名前を必ず含み、run.jsonの「テスト設計書の出力」が
#   「出力する」のときだけ単体テスト設計書の名前も含める。これは
#   record-acceptance.sh が合格の記録へ書く文書の組（docs_json）と同じ集合で
#   あり、既に「合格の記録の対象」として機械強制されている納品物である
#   （唯一の定義の再実装ではなく、record-acceptance.shのspecies_folderと同じ
#   種別→フォルダ名の対応を本スクリプトも持つ。共有部品化されていないため
#   複製であり、対応を変えるときは両方を直す）。
#   単位を持たない行（共通設計文書・要件定義書・docs/design/lists配下の文書・
#   種別内結合テスト設計書）は、既存のMarkdownファイルを走査して作る（単位の
#   欄は「全体」）。これらは工程2-7〜2-9の合格記録の門で既に実在を確かめて
#   いるため、本スクリプトでは実在の有無に関わらず一覧に加えるだけである。
#   docs/design/lists配下は納品物一覧.md自身を除く。
#
# 確認事項の件数・未回答の件数:
#   <実行フォルダ>/confirmations/確認事項の記録.md の表（キー・単位・種類・
#   事項・既定・反映先・回答・状態の8列）を読み、データ行の総数と「状態」列が
#   「未回答」の行数を数える。ファイルが無ければどちらも0とする。
#
# 到達範囲:
#   <実行フォルダ>/run.json の「出力の範囲」をそのまま使う（決めた内容：
#   工程2-13の完了報告は到達範囲を出力の範囲として書く）。
#
# 実行した機能とその結果:
#   <実行フォルダ>/reports/reverse-plan.md（統括の手順5がSTEPと各機能の結果を
#   書く）が実在すればその内容をそのまま埋め込む。無ければその旨を書く。
#
# 終了コード:
#   0 = 完了報告と納品物一覧を書いた
#   1 = 納品物一覧の行の文書が1件以上実在しない（標準エラー出力にキー
#       納品物-不在で行ごとに1行。このときは完了報告・納品物一覧のいずれも
#       書かない）
#   2 = 使い方の誤り（引数不足・--design-root無し）、または
#       <実行フォルダ>/run.json が読めない
#   3 = 業務名.jsonが無いか読めない（[FAIL] 業務名-読めない）、または
#       単位のフォルダ名が空か前後の空白（半角の空白・タブ・全角の空白）だけ
#       （[FAIL] フォルダ名-未確定: <識別子>）。いずれのときも完了報告・
#       納品物一覧のいずれも書かない。前回の実行が書いた両ファイルは
#       そのまま残る
#
# 保守責任者: 人手（ユーザー）。文書名の決め方を変えるときは
#   reverse-shared/scripts/design-doc-name.sh と本スクリプトの種別→フォルダ名の
#   対応（species_folder_of）を同時に直す。
#
# 廃棄条件: 工程2-13の集計を別の仕組みに変えた時。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。jqを使用する。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESIGN_DOC_NAME_SH="${SCRIPT_DIR}/../../reverse-shared/scripts/design-doc-name.sh"

usage_error() {
  echo "使い方: build-completion-report.sh <実行フォルダ> --design-root <設計書の置き場>" >&2
  echo "        build-completion-report.sh --self-test" >&2
  exit 2
}

# 種別（業務名.jsonのキー）→ 設計書のフォルダ名（record-acceptance.shの
# species_folderと同じ対応。共有部品が無いための複製）
species_folder_of() {
  case "$1" in
    screen) echo screens ;;
    api) echo apis ;;
    table) echo tables ;;
    batch) echo batches ;;
    report) echo reports ;;
    external) echo externals ;;
    feature) echo features ;;
    *) echo "" ;;
  esac
}

# 業務名.jsonの単位ごとに「種別\x1f単位\x1f文書\x1f所在」の行を出す
# （基本設計書は必ず、単体テスト設計書はtests_outputが「出力する」のときだけ）
# 欄の区切りは\x1f（単位区切り文字）を使う。タブはbashのIFSの空白類に属し、
# 空の欄（例: 業務名が空文字）があると詰まって列がずれるため使わない
# （reverse-building-confirmation-itemsのbuild-confirmation-items.shと同じ方式）。
#
# 戻り値:
#   0 = 正常終了
#   3 = 業務名.jsonが無いか読めない、またはフォルダ名が空（設定の不備）
collect_unit_rows() {
  local design_root="$1" tests_output="$2"
  local business_path="${design_root%/}/docs/design/lists/業務名.json"
  if [ ! -f "$business_path" ] || ! jq -e . "$business_path" > /dev/null 2>&1; then
    echo "[FAIL] 業務名-読めない: ${business_path}" >&2
    return 3
  fi
  [ -f "$DESIGN_DOC_NAME_SH" ] || return 0

  local kind
  while IFS= read -r kind; do
    [ -n "$kind" ] || continue
    local species
    species="$(species_folder_of "$kind")"
    [ -n "$species" ] || continue

    local id name folder degree
    while IFS=$'\x1f' read -r id name folder degree; do
      [ -n "$id" ] || continue
      local folder_trimmed
      # 落とす空白は半角の空白・タブ・全角の空白（U+3000）の3つ（詳細設計書
      # §2手順9）。[[:space:]]はロケール次第でU+3000を含むか変わるため使わず、
      # 3つを個別に指定してロケールに依存しない判定にする。
      folder_trimmed="$(printf '%s' "$folder" | sed -E 's/^( |	|　)*//; s/( |	|　)*$//')"
      if [ -z "$folder_trimmed" ]; then
        echo "[FAIL] フォルダ名-未確定: ${id}" >&2
        return 3
      fi
      folder="$folder_trimmed"
      # 業務名が空になるのは工程2-1の業務名の確定が先に不合格にするため通常は
      # 起きない。ここへ到達したときに単位の欄が空の括弧だけになると読み手が
      # 単位を特定できないため、識別子で代用する。一覧を作る機能の合成規則
      # （list-units.shのmerge_business_namesは業務名が空なら空のまま）との
      # 違いはこの一点である。
      local bn="${name:-$id}"
      local disp="$bn"
      if [ -n "$degree" ]; then
        disp="${bn}（${degree}）"
      fi

      local basic_name
      basic_name="$(bash "$DESIGN_DOC_NAME_SH" "$kind" basic 2>/dev/null)"
      if [ -n "$basic_name" ]; then
        printf '%s\x1f%s（%s）\x1f%s\x1f%s\n' "$kind" "$disp" "$id" "$basic_name" \
          "docs/design/${species}/${folder}/${basic_name}"
      fi

      if [ "$tests_output" = "出力する" ]; then
        local test_name
        test_name="$(bash "$DESIGN_DOC_NAME_SH" "$kind" test 2>/dev/null)"
        if [ -n "$test_name" ]; then
          printf '%s\x1f%s（%s）\x1f%s\x1f%s\n' "$kind" "$disp" "$id" "$test_name" \
            "docs/design/${species}/${folder}/${test_name}"
        fi
      fi
    done < <(jq -r --arg k "$kind" --arg sep "$(printf '\x1f')" \
      '(.[$k] // [])[] | [(.["識別子"] // ""), (.["業務名"] // ""), (.["フォルダ名"] // ""), (.["区別"] // "")] | join($sep)' \
      "$business_path" 2>/dev/null)
  done < <(jq -r 'keys[] | select(. != "退役フォルダ名")' "$business_path" 2>/dev/null)
}

# 既存のMarkdownファイルを走査して「種別\x1f全体\x1f文書\x1f所在」の行を出す
# （単位を持たない共通・要件・一覧・種別内結合テスト設計書。区切りは
# collect_unit_rowsと同じ\x1fに揃える。片方だけタブのままだと、cat結合後の
# sort・readで欄がずれる）
collect_scan_rows() {
  local design_root="$1" dir_rel="$2" label="$3" exclude_name="${4:-}"
  local dir="${design_root%/}/${dir_rel}"
  [ -d "$dir" ] || return 0
  local f base
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    base="$(basename "$f")"
    if [ -n "$exclude_name" ] && [ "$base" = "$exclude_name" ]; then
      continue
    fi
    printf '%s\x1f全体\x1f%s\x1f%s/%s\n' "$label" "$base" "$dir_rel" "$base"
  done < <(find "$dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort)
}

# データ行の総数と「状態」列が「未回答」の行数を数える
count_confirmations() {
  local run_dir="$1"
  local f="${run_dir%/}/confirmations/確認事項の記録.md"
  local total=0 unanswered=0
  if [ -f "$f" ]; then
    local line status
    while IFS= read -r line; do
      case "$line" in
        '|'*'|') ;;
        *) continue ;;
      esac
      case "$line" in
        *'キー'*'単位'*'状態'*) continue ;;
      esac
      case "$line" in
        *'---'*) continue ;;
      esac
      total=$((total + 1))
      status="$(printf '%s' "$line" | awk -F'|' '{n=NF-1; gsub(/^[ \t]+|[ \t]+$/, "", $n); print $n}')"
      if [ "$status" = "未回答" ]; then
        unanswered=$((unanswered + 1))
      fi
    done < "$f"
  fi
  printf '%s\x1f%s\n' "$total" "$unanswered"
}

build_report() {
  local run_dir="$1" design_root="$2"
  local run_json="${run_dir%/}/run.json"
  if [ ! -f "$run_json" ] || ! jq -e . "$run_json" > /dev/null 2>&1; then
    echo "[FAIL] 実行フォルダ-run.json不在: ${run_json}" >&2
    return 2
  fi

  local scope tests_output
  scope="$(jq -r '.["出力の範囲"] // ""' "$run_json" 2>/dev/null)"
  [ -n "$scope" ] || scope="不明"
  tests_output="$(jq -r '.["テスト設計書の出力"] // ""' "$run_json" 2>/dev/null)"

  local unit_rows_file
  unit_rows_file="$(mktemp "${TMPDIR:-/tmp}/build-completion-report.unit-rows.XXXXXX")" || {
    echo "[FAIL] 一時ファイル-作成不可" >&2
    return 2
  }

  # 業務名.jsonが読めない・フォルダ名が空のときはここで止める（設定の不備。
  # 完了報告・納品物一覧のいずれも書かない）。パイプへ流すとexit codeが失われる
  # ため、単位の行だけを先に単独で集めて終了コードを確かめる。
  collect_unit_rows "$design_root" "$tests_output" > "$unit_rows_file"
  local unit_rc=$?
  if [ "$unit_rc" -ne 0 ]; then
    rm -f "$unit_rows_file"
    return "$unit_rc"
  fi

  local rows_file
  rows_file="$(mktemp "${TMPDIR:-/tmp}/build-completion-report.rows.XXXXXX")" || {
    rm -f "$unit_rows_file"
    echo "[FAIL] 一時ファイル-作成不可" >&2
    return 2
  }
  trap 'rm -f "$rows_file" "$unit_rows_file"' RETURN

  {
    cat "$unit_rows_file"
    collect_scan_rows "$design_root" "docs/design/requirements" "要件"
    collect_scan_rows "$design_root" "docs/design/common" "共通"
    collect_scan_rows "$design_root" "docs/design/lists" "一覧" "納品物一覧.md"
    local k species
    for k in screen api table batch report external feature; do
      species="$(species_folder_of "$k")"
      collect_scan_rows "$design_root" "docs/design/${species}" "$k"
    done
  } | sort -t "$(printf '\x1f')" -k1,1 -k2,2 -k3,3 > "$rows_file"

  rm -f "$unit_rows_file"

  local missing=0
  local kk uu dd rel
  while IFS=$'\x1f' read -r kk uu dd rel; do
    [ -n "$rel" ] || continue
    if [ ! -f "${design_root%/}/${rel}" ]; then
      missing=$((missing + 1))
      echo "[FAIL] 納品物-不在: ${rel}" >&2
    fi
  done < "$rows_file"

  if [ "$missing" -gt 0 ]; then
    return 1
  fi

  local total_count
  total_count="$(wc -l < "$rows_file" | tr -d ' ')"

  local manifest
  manifest="| 種別 | 単位 | 文書 | 所在 |
|---|---|---|---|
"
  while IFS=$'\x1f' read -r kk uu dd rel; do
    manifest="${manifest}| ${kk} | ${uu} | ${dd} | ${rel} |
"
  done < "$rows_file"

  local conf_counts conf_total conf_unanswered
  conf_counts="$(count_confirmations "$run_dir")"
  conf_total="${conf_counts%%$'\x1f'*}"
  conf_unanswered="${conf_counts##*$'\x1f'}"

  local plan_section
  local plan_file="${run_dir%/}/reports/reverse-plan.md"
  if [ -f "$plan_file" ]; then
    plan_section="$(cat "$plan_file")"
  else
    plan_section="reports/reverse-plan.md が無いため記載なし。"
  fi

  mkdir -p "${design_root%/}/docs/design/lists" "${run_dir%/}/reports" || {
    echo "[FAIL] 書き込み先-作成不可" >&2
    return 2
  }
  printf '%s' "$manifest" > "${design_root%/}/docs/design/lists/納品物一覧.md"
  printf '%s' "$manifest" > "${run_dir%/}/reports/納品物一覧.md"

  {
    echo "# 完了報告"
    echo
    echo "## 到達範囲"
    echo
    echo "出力の範囲: ${scope}"
    echo
    echo "## 納品物の件数"
    echo
    echo "${total_count}件（docs/design/lists/納品物一覧.md を参照）"
    echo
    echo "## 確認事項の件数と未回答の件数"
    echo
    echo "確認事項の件数: ${conf_total}件"
    echo "未回答の件数: ${conf_unanswered}件"
    echo
    echo "## 実行した機能とその結果"
    echo
    echo "${plan_section}"
    echo
    echo "## 受け入れ"
    echo
    echo "（人（開発チーム）が記入する。空欄のまま出す）"
  } > "${run_dir%/}/reports/完了報告.md"

  echo "完了報告: ${run_dir%/}/reports/完了報告.md"
  echo "納品物一覧: ${design_root%/}/docs/design/lists/納品物一覧.md"
  return 0
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

self_test() {
  local pass=0 fail=0 tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/build-completion-report-self-test.XXXXXX" 2>/dev/null)" || {
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません" >&2
    exit 2
  }
  trap 'rm -rf "$tmp"' RETURN

  # ケース1: 納品物一覧と完了報告が書かれ単位が表示名と識別子を持つ
  local run1="${tmp}/run1" design1="${tmp}/design1"
  mkdir -p "${run1}/confirmations" "${run1}/reports" "${design1}/docs/design/lists" \
    "${design1}/docs/design/screens/受注一覧" "${design1}/docs/design/screens/受注一覧A"
  cat > "${run1}/run.json" << 'EOF'
{
  "出力の範囲": "全部",
  "テスト設計書の出力": "出力しない"
}
EOF
  cat > "${design1}/docs/design/lists/業務名.json" << 'EOF'
{
  "screen": [
    {"識別子":"screens/order-list.tsx","業務名":"受注一覧","区別":null,"フォルダ名":"受注一覧"},
    {"識別子":"screens/order-list-a.tsx","業務名":"受注一覧","区別":"新","フォルダ名":"受注一覧A"}
  ],
  "退役フォルダ名": {}
}
EOF
  echo "# 画面基本設計書" > "${design1}/docs/design/screens/受注一覧/画面基本設計書.md"
  echo "# 画面基本設計書" > "${design1}/docs/design/screens/受注一覧A/画面基本設計書.md"
  cat > "${run1}/confirmations/確認事項の記録.md" << 'EOF'
| キー | 単位 | 種類 | 事項 | 既定 | 反映先 | 回答 | 状態 |
|---|---|---|---|---|---|---|---|
| 受注番号-桁数 | 受注一覧 | 業務ルール | 桁数 | 8桁 | 画面基本設計書 | 未回答 | 未回答 |
| 期限-猶予日数 | 全体 | 業務ルール | 猶予日数 | 3日 | 業務仕様書 | 3日 | 回答済み |
EOF

  local out1 rc1=0
  out1="$(bash "$0" "$run1" --design-root "$design1" 2>&1)" || rc1=$?
  local manifest_lines1=0 declared_count1=""
  if [ -f "${design1}/docs/design/lists/納品物一覧.md" ]; then
    manifest_lines1="$(grep -c '^|' "${design1}/docs/design/lists/納品物一覧.md")"
  fi
  if [ -f "${run1}/reports/完了報告.md" ]; then
    declared_count1="$(grep -oE '^[0-9]+件（docs/design/lists/納品物一覧.md' "${run1}/reports/完了報告.md" | grep -oE '^[0-9]+')"
  fi
  if [ "$rc1" -eq 0 ] \
    && [ -f "${design1}/docs/design/lists/納品物一覧.md" ] \
    && [ -f "${run1}/reports/納品物一覧.md" ] \
    && [ -f "${run1}/reports/完了報告.md" ] \
    && grep -q '受注一覧（screens/order-list.tsx）' "${design1}/docs/design/lists/納品物一覧.md" \
    && grep -q '受注一覧（新）（screens/order-list-a.tsx）' "${design1}/docs/design/lists/納品物一覧.md" \
    && grep -q '到達範囲' "${run1}/reports/完了報告.md" \
    && grep -q '納品物の件数' "${run1}/reports/完了報告.md" \
    && grep -q '確認事項の件数' "${run1}/reports/完了報告.md" \
    && grep -q '未回答の件数' "${run1}/reports/完了報告.md" \
    && grep -q '受け入れ' "${run1}/reports/完了報告.md" \
    && grep -q '確認事項の件数: 2件' "${run1}/reports/完了報告.md" \
    && grep -q '未回答の件数: 1件' "${run1}/reports/完了報告.md" \
    && [ "$manifest_lines1" -eq 4 ] \
    && [ -n "$declared_count1" ] \
    && [ "$declared_count1" -eq "$((manifest_lines1 - 2))" ]; then
    pass=$((pass + 1)); echo "  [PASS] ケース1: 納品物一覧と完了報告が書かれ単位が表示名と識別子を持つ"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース1: 納品物一覧と完了報告が書かれ単位が表示名と識別子を持つ (exit ${rc1})" >&2
    printf '%s\n' "$out1" | sed 's/^/    /' >&2
  fi

  # ケース2: 納品物一覧の行の文書が無いと終了コード1で止まる
  local run2="${tmp}/run2" design2="${tmp}/design2"
  mkdir -p "${run2}/confirmations" "${run2}/reports" "${design2}/docs/design/lists"
  cat > "${run2}/run.json" << 'EOF'
{
  "出力の範囲": "全部",
  "テスト設計書の出力": "出力しない"
}
EOF
  cat > "${design2}/docs/design/lists/業務名.json" << 'EOF'
{
  "screen": [
    {"識別子":"screens/order-list.tsx","業務名":"受注一覧","区別":null,"フォルダ名":"受注一覧"}
  ],
  "退役フォルダ名": {}
}
EOF
  local out2 rc2=0
  out2="$(bash "$0" "$run2" --design-root "$design2" 2>&1)" || rc2=$?
  if [ "$rc2" -eq 1 ] && printf '%s' "$out2" | grep -q '\[FAIL\] 納品物-不在' \
    && [ ! -f "${design2}/docs/design/lists/納品物一覧.md" ]; then
    pass=$((pass + 1)); echo "  [PASS] ケース2: 納品物一覧の行の文書が無いと終了コード1で止まる"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース2: 納品物一覧の行の文書が無いと終了コード1で止まる (exit ${rc2})" >&2
    printf '%s\n' "$out2" | sed 's/^/    /' >&2
  fi

  # ケース3: 業務名.jsonが読めないと終了コード3で止まる
  local run3="${tmp}/run3" design3="${tmp}/design3"
  mkdir -p "${run3}/confirmations" "${run3}/reports" "${design3}/docs/design/lists"
  cat > "${run3}/run.json" << 'EOF'
{
  "出力の範囲": "全部",
  "テスト設計書の出力": "出力しない"
}
EOF
  printf '{ "screen": [ 壊れたJSON' > "${design3}/docs/design/lists/業務名.json"
  local out3 rc3=0
  out3="$(bash "$0" "$run3" --design-root "$design3" 2>&1)" || rc3=$?
  if [ "$rc3" -eq 3 ] && printf '%s' "$out3" | grep -q '\[FAIL\] 業務名-読めない' \
    && [ ! -f "${design3}/docs/design/lists/納品物一覧.md" ] \
    && [ ! -f "${run3}/reports/完了報告.md" ]; then
    pass=$((pass + 1)); echo "  [PASS] ケース3: 業務名.jsonが読めないと終了コード3で止まる"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース3: 業務名.jsonが読めないと終了コード3で止まる (exit ${rc3})" >&2
    printf '%s\n' "$out3" | sed 's/^/    /' >&2
  fi

  # ケース4: フォルダ名が空だと終了コード3で止まる
  local run4="${tmp}/run4" design4="${tmp}/design4"
  mkdir -p "${run4}/confirmations" "${run4}/reports" "${design4}/docs/design/lists"
  cat > "${run4}/run.json" << 'EOF'
{
  "出力の範囲": "全部",
  "テスト設計書の出力": "出力しない"
}
EOF
  cat > "${design4}/docs/design/lists/業務名.json" << 'EOF'
{
  "screen": [
    {"識別子":"screens/order-list.tsx","業務名":"受注一覧","区別":null,"フォルダ名":""}
  ],
  "退役フォルダ名": {}
}
EOF
  local out4 rc4=0
  out4="$(bash "$0" "$run4" --design-root "$design4" 2>&1)" || rc4=$?
  if [ "$rc4" -eq 3 ] && printf '%s' "$out4" | grep -q '\[FAIL\] フォルダ名-未確定: screens/order-list.tsx' \
    && [ ! -f "${design4}/docs/design/lists/納品物一覧.md" ] \
    && [ ! -f "${run4}/reports/完了報告.md" ]; then
    pass=$((pass + 1)); echo "  [PASS] ケース4: フォルダ名が空だと終了コード3で止まる"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース4: フォルダ名が空だと終了コード3で止まる (exit ${rc4})" >&2
    printf '%s\n' "$out4" | sed 's/^/    /' >&2
  fi

  # ケース5: 業務名が空でもフォルダ名の判定を誤らない
  local run5="${tmp}/run5" design5="${tmp}/design5"
  mkdir -p "${run5}/confirmations" "${run5}/reports" "${design5}/docs/design/lists" \
    "${design5}/docs/design/screens/受注一覧"
  cat > "${run5}/run.json" << 'EOF'
{
  "出力の範囲": "全部",
  "テスト設計書の出力": "出力しない"
}
EOF
  cat > "${design5}/docs/design/lists/業務名.json" << 'EOF'
{
  "screen": [
    {"識別子":"screens/order-list.tsx","業務名":"","区別":null,"フォルダ名":"受注一覧"}
  ],
  "退役フォルダ名": {}
}
EOF
  echo "# 画面基本設計書" > "${design5}/docs/design/screens/受注一覧/画面基本設計書.md"
  local out5 rc5=0
  out5="$(bash "$0" "$run5" --design-root "$design5" 2>&1)" || rc5=$?
  if [ "$rc5" -eq 0 ] \
    && [ -f "${design5}/docs/design/lists/納品物一覧.md" ] \
    && grep -q 'screens/order-list.tsx（screens/order-list.tsx）' "${design5}/docs/design/lists/納品物一覧.md"; then
    pass=$((pass + 1)); echo "  [PASS] ケース5: 業務名が空でもフォルダ名の判定を誤らない"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース5: 業務名が空でもフォルダ名の判定を誤らない (exit ${rc5})" >&2
    printf '%s\n' "$out5" | sed 's/^/    /' >&2
  fi

  # ケース6: フォルダ名が空白だけだと終了コード3で止まる
  local run6="${tmp}/run6" design6="${tmp}/design6"
  mkdir -p "${run6}/confirmations" "${run6}/reports" "${design6}/docs/design/lists"
  cat > "${run6}/run.json" << 'EOF'
{
  "出力の範囲": "全部",
  "テスト設計書の出力": "出力しない"
}
EOF
  cat > "${design6}/docs/design/lists/業務名.json" << 'EOF'
{
  "screen": [
    {"識別子":"screens/order-list.tsx","業務名":"受注一覧","区別":null,"フォルダ名":"   "}
  ],
  "退役フォルダ名": {}
}
EOF
  local out6 rc6=0
  out6="$(bash "$0" "$run6" --design-root "$design6" 2>&1)" || rc6=$?
  if [ "$rc6" -eq 3 ] && printf '%s' "$out6" | grep -q '\[FAIL\] フォルダ名-未確定: screens/order-list.tsx' \
    && [ ! -f "${design6}/docs/design/lists/納品物一覧.md" ] \
    && [ ! -f "${run6}/reports/完了報告.md" ]; then
    pass=$((pass + 1)); echo "  [PASS] ケース6: フォルダ名が空白だけだと終了コード3で止まる"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース6: フォルダ名が空白だけだと終了コード3で止まる (exit ${rc6})" >&2
    printf '%s\n' "$out6" | sed 's/^/    /' >&2
  fi

  # ケース7: フォルダ名が全角の空白だけでも終了コード3で止まる
  local run7="${tmp}/run7" design7="${tmp}/design7"
  mkdir -p "${run7}/confirmations" "${run7}/reports" "${design7}/docs/design/lists"
  cat > "${run7}/run.json" << 'EOF'
{
  "出力の範囲": "全部",
  "テスト設計書の出力": "出力しない"
}
EOF
  cat > "${design7}/docs/design/lists/業務名.json" << 'EOF'
{
  "screen": [
    {"識別子":"screens/order-list.tsx","業務名":"受注一覧","区別":null,"フォルダ名":"　　"}
  ],
  "退役フォルダ名": {}
}
EOF
  local out7 rc7=0
  out7="$(bash "$0" "$run7" --design-root "$design7" 2>&1)" || rc7=$?
  if [ "$rc7" -eq 3 ] && printf '%s' "$out7" | grep -q '\[FAIL\] フォルダ名-未確定: screens/order-list.tsx' \
    && [ ! -f "${design7}/docs/design/lists/納品物一覧.md" ] \
    && [ ! -f "${run7}/reports/完了報告.md" ]; then
    pass=$((pass + 1)); echo "  [PASS] ケース7: フォルダ名が全角の空白だけでも終了コード3で止まる"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース7: フォルダ名が全角の空白だけでも終了コード3で止まる (exit ${rc7})" >&2
    printf '%s\n' "$out7" | sed 's/^/    /' >&2
  fi

  echo "実行 $((pass + fail)) 件 / 失敗 ${fail} 件"
  if [ "$fail" -gt 0 ]; then
    return 1
  fi
  return 0
}

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi

  local run_dir="" design_root="" args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --design-root) design_root="${2:-}"; shift 2 ;;
      *) args+=("$1"); shift ;;
    esac
  done
  if [ "${#args[@]}" -ne 1 ] || [ -z "$design_root" ]; then
    usage_error
  fi
  run_dir="${args[0]}"

  build_report "$run_dir" "$design_root"
  exit $?
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main "$@"
fi
