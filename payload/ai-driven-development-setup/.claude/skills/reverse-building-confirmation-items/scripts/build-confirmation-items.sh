#!/usr/bin/env bash
set -uo pipefail
# 見出し・列名の完全一致比較は LC_ALL=C で行う。macOS 標準 awk は UTF-8 ロケールで
# 多バイト文字列の == を誤るため（check-unit-test-design-doc-sections.sh と同じ対処）。
export LC_ALL=C

# build-confirmation-items.sh — 確認事項の記録と各設計書の「要確認事項一覧」節から
#   確認事項一覧（8列）を決定的に組み立てる（reverse-building-confirmation-itemsの実体）
#
# 定義: docs/design/skills/reverse-building-confirmation-items/基本設計書.md・詳細設計書.md
#
# 使い方:
#   build-confirmation-items.sh <実行フォルダ> [--design-root <設計書の置き場>]
#   build-confirmation-items.sh --verify <確認事項一覧.md> --design-root <設計書の置き場>
#   build-confirmation-items.sh --self-test
#
# 終了コード:
#   0 = 出力を書いた（通常実行）、または検証に合格した（--verify）
#   1 = 出力の行に既定・反映先の空欄がある（行-空欄）、または
#       --verifyで設計書のキーが出力に無い（キー-出力欠落）
#   2 = 使い方の誤り・実行フォルダ不在（判定不能）
#
# 保守責任者: 人手（ユーザー）。要確認事項一覧の列見出しの組み合わせ・埋め方の
#   規則を変えるときは、本スクリプトと自己テストと基本設計書§2を同時に直す。
#
# 廃棄条件: 確認事項の記録・要確認事項一覧の様式を構造化データに変えた時。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。3.2では空配列の
# "${arr[@]}" 展開が set -u 下で unbound variable になるため、空になりうる
# 配列の展開は要素数を先に確認してから行う。エントリポイントは
# BASH_SOURCE比較でsource時に自動実行しない形にし、自己テストから
# 関数だけをsourceして/bin/bash(3.2)で呼び直せるようにしている。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="${SCRIPT_DIR}/../../reverse-shared/scripts"

usage_error() {
  echo "使い方: build-confirmation-items.sh <実行フォルダ> [--design-root <設計書の置き場>]" >&2
  echo "        build-confirmation-items.sh --verify <確認事項一覧.md> --design-root <設計書の置き場>" >&2
  echo "        build-confirmation-items.sh --self-test" >&2
  exit 2
}

# 表の1行を列配列へ分割する共通関数。セル内のエスケープ済みパイプ "\|" を
# 先に @@ESCPIPE@@ へ退避してから "|" で分割し、各セルで元の "|" へ戻す。
AWK_SPLIT_ROW='
  function split_row(line, cols,    esc, cnt, i) {
    esc = line
    gsub(/\\\|/, "@@ESCPIPE@@", esc)
    sub(/^\|/, "", esc); sub(/\|$/, "", esc)
    cnt = split(esc, cols, "|")
    for (i = 1; i <= cnt; i++) {
      gsub(/^[ \t]+|[ \t]+$/, "", cols[i])
      gsub(/@@ESCPIPE@@/, "|", cols[i])
    }
    return cnt
  }
'

# 確認事項の記録.md（8列）のデータ行を \x1f 区切りで返す（見出し・区切り行を除く）
extract_record_rows() {
  local file="$1"
  [ -f "$file" ] || return 0
  awk "$AWK_SPLIT_ROW"'
    BEGIN { n = 0 }
    /^\|/ {
      cnt = split_row($0, cols)
      if (n == 0) { n = 1; next }
      if (cols[1] ~ /^[-: ]+$/) next
      out = cols[1]
      for (i = 2; i <= 8; i++) { out = out "\037" (i <= cnt ? cols[i] : "") }
      print out
    }
  ' "$file"
}

# 確認事項の記録.md の見出し行から列名→列番号の対応を返す（\x1f区切りの1行）
record_header_indices() {
  local file="$1"
  [ -f "$file" ] || return 0
  awk "$AWK_SPLIT_ROW"'
    /^\|/ {
      cnt = split_row($0, cols)
      key_i = 0; unit_i = 0; item_i = 0; reason_i = 0; status_i = 0
      for (i = 1; i <= cnt; i++) {
        if (cols[i] == "キー") key_i = i
        if (cols[i] == "単位") unit_i = i
        if (cols[i] == "事項") item_i = i
        if (cols[i] == "理由") reason_i = i
        if (cols[i] == "状態") status_i = i
      }
      printf "%d\037%d\037%d\037%d\037%d\n", key_i, unit_i, item_i, reason_i, status_i
      exit
    }
  ' "$file"
}

# 1設計書ファイルの「## 要確認事項一覧」節から キー\x1f事項\x1f確認先\x1f既定 を返す。
# 見出しは前方一致（末尾の空白・付記を許す）で判定する（check-basic-design.sh:206と同じ）。
extract_survey_items() {
  local file="$1"
  awk "$AWK_SPLIT_ROW"'
    /^## 要確認事項一覧/ { insec = 1; next }
    insec == 1 && /^## / { insec = 0 }
    insec == 1 && /^\|/ {
      cnt = split_row($0, cols)
      if (!headerdone) {
        for (i = 1; i <= cnt; i++) {
          if (cols[i] == "キー") key_i = i
          if (cols[i] == "確認事項" || cols[i] == "事項") item_i = i
          if (cols[i] == "確認先") source_i = i
          if (cols[i] == "既定") default_i = i
        }
        headerdone = 1
        next
      }
      if (cols[1] ~ /^[-: ]+$/) next
      key = (key_i ? cols[key_i] : "")
      if (key == "" || key ~ /^<.*>$/) next
      item = (item_i ? cols[item_i] : "")
      src = (source_i ? cols[source_i] : "")
      def = (default_i ? cols[default_i] : "")
      printf "%s\037%s\037%s\037%s\n", key, item, src, def
    }
  ' "$file"
}

# docs/design/からの相対パスから単位を導く
derive_unit() {
  local relpath="$1"
  local first="${relpath%%/*}"
  case "$first" in
    common|requirements) printf '%s' "全体" ;;
    *)
      local rest="${relpath#*/}"
      if [[ "$rest" == */* ]]; then
        printf '%s' "${rest%%/*}"
      else
        printf '%s' "全体"
      fi
      ;;
  esac
}

kind_for_source() {
  case "$1" in
    非機能要件定義書) printf '%s' "非機能" ;;
    事業部門) printf '%s' "業務ルール" ;;
    運用部門) printf '%s' "運用" ;;
    設計担当) printf '%s' "制約" ;;
    *) printf '%s' "制約" ;;
  esac
}

# 設計書の置き場配下を走査し、キー\x1f単位\x1f種類\x1f事項\x1f既定\x1f反映先 を返す（重複キーは先頭のみ・件数を単位に反映）
collect_design_items() {
  local design_docs_root="$1"
  [ -d "$design_docs_root" ] || return 0
  local file relpath unit docname
  local -a out_key=() out_item=() out_kind=() out_default=() out_unit=() out_doc=() out_count=()
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    relpath="${file#"${design_docs_root%/}"/}"
    docname="$(basename "$file")"
    unit="$(derive_unit "$relpath")"
    local key item src def found j n
    while IFS=$'\037' read -r key item src def; do
      [ -n "$key" ] || continue
      found=-1
      n="${#out_key[@]}"
      for ((j = 0; j < n; j++)); do
        if [ "${out_key[$j]}" = "$key" ]; then found=$j; break; fi
      done
      if [ "$found" -ge 0 ]; then
        out_count[$found]=$((out_count[$found] + 1))
        continue
      fi
      out_key+=("$key")
      out_item+=("$item")
      out_kind+=("$(kind_for_source "$src")")
      if [ -n "$def" ]; then
        out_default+=("$def")
      else
        out_default+=("設計書の現行の記述のまま扱う")
      fi
      out_unit+=("$unit")
      out_doc+=("$docname")
      out_count+=(1)
    done < <(extract_survey_items "$file")
  done < <(find "$design_docs_root" -type f -name '*.md' | sort)
  local n2="${#out_key[@]}"
  [ "$n2" -gt 0 ] || return 0
  local i unit_field refer
  for ((i = 0; i < n2; i++)); do
    unit_field="${out_unit[$i]}"
    if [ "${out_count[$i]}" -gt 1 ]; then
      unit_field="${unit_field}ほか$((out_count[$i] - 1))件"
    fi
    refer="${out_doc[$i]} ${out_unit[$i]}"
    printf '%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\n' "${out_key[$i]}" "$unit_field" "${out_kind[$i]}" "${out_item[$i]}" "${out_default[$i]}" "$refer"
  done
}

# ------------------------------------------------------------------
# 通常実行（組み立て）
# ------------------------------------------------------------------

run_build() {
  local run_dir="$1" design_root="$2"
  local record_file="${run_dir%/}/confirmations/確認事項の記録.md"
  local design_docs_root="${design_root%/}/docs/design"

  local record_rows
  record_rows="$(extract_record_rows "$record_file")"
  local -a rec_keys=() rec_lines=()
  local line key
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    key="$(printf '%s' "$line" | cut -d $'\x1f' -f1)"
    rec_keys+=("$key")
    rec_lines+=("$line")
  done <<< "$record_rows"

  local design_items
  design_items="$(collect_design_items "$design_docs_root")"

  local -a final_lines=()
  local dkey dunit dkind ditem ddefault drefer found j n
  while IFS=$'\x1f' read -r dkey dunit dkind ditem ddefault drefer; do
    [ -n "$dkey" ] || continue
    found=0
    n="${#rec_keys[@]}"
    for ((j = 0; j < n; j++)); do
      if [ "${rec_keys[$j]}" = "$dkey" ]; then found=1; break; fi
    done
    [ "$found" -eq 1 ] && continue
    final_lines+=("$(printf '%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s' "$dkey" "$dunit" "$dkind" "$ditem" "$ddefault" "$drefer" "" "未回答")")
  done <<< "$design_items"

  # 空欄検査（記録行 + 新規行）。bash 3.2ではどちらかが空配列だと
  # "${arr[@]}" だけの展開が unbound variable になるため、要素数を
  # 確認してから安全に連結する。
  local -a all_lines=()
  if [ "${#rec_lines[@]}" -gt 0 ]; then
    all_lines+=("${rec_lines[@]}")
  fi
  if [ "${#final_lines[@]}" -gt 0 ]; then
    all_lines+=("${final_lines[@]}")
  fi

  local -a bad_keys=()
  local l k u ki it de re an st
  if [ "${#all_lines[@]}" -gt 0 ]; then
    for l in "${all_lines[@]}"; do
      IFS=$'\x1f' read -r k u ki it de re an st <<< "$l"
      if [ -z "$de" ] || [ -z "$re" ]; then
        bad_keys+=("$k")
      fi
    done
  fi
  if [ "${#bad_keys[@]}" -gt 0 ]; then
    local bad_list=""
    for k in "${bad_keys[@]}"; do bad_list="${bad_list}${bad_list:+ }${k}"; done
    echo "[FAIL] 行-空欄: 既定または反映先が空の行があります: ${bad_list}" >&2
    return 1
  fi

  {
    echo "# 確認事項一覧"
    echo
    echo "| キー | 単位 | 種類 | 事項 | 既定 | 反映先 | 回答 | 状態 |"
    echo "|---|---|---|---|---|---|---|---|"
    if [ "${#all_lines[@]}" -gt 0 ]; then
      for l in "${all_lines[@]}"; do
        IFS=$'\x1f' read -r k u ki it de re an st <<< "$l"
        echo "| ${k} | ${u} | ${ki} | ${it} | ${de} | ${re} | ${an} | ${st} |"
      done
    fi
    echo
    echo "## 記録に無いキー"
    echo
    echo "記録に無いキー ${#final_lines[@]}件"
    if [ "${#final_lines[@]}" -gt 0 ]; then
      echo
      for l in "${final_lines[@]}"; do
        k="$(printf '%s' "$l" | cut -d $'\x1f' -f1)"
        echo "- ${k}"
      done
    fi
  }
}

# 確認事項一覧を書いた後に提示の記録を書く。回答は確認事項一覧の回答欄へ
# 開発チームが直接書くため、この記録は回答を持たない
# （詳細設計書§3「提示の記録が回答を持たない理由」）。
write_presentation_record() {
  local run_dir="$1" list_body="$2"
  local out_file="${run_dir%/}/confirmations/確認事項の提示の記録.md"
  local total_count unanswered_count
  total_count="$(printf '%s\n' "$list_body" | awk '/^\|---/{s=1;next} s&&/^\| /{c++} END{print c+0}')"
  unanswered_count="$(printf '%s\n' "$list_body" | awk -F'|' '/^\|---/{s=1;next} s&&/^\| /{v=$(NF-1); gsub(/^[ \t]+|[ \t]+$/,"",v); if(v=="未回答")c++} END{print c+0}')"
  {
    echo "# 確認事項の提示の記録"
    echo
    echo "| 項目 | 値 |"
    echo "|---|---|"
    echo "| 提示した日 | $(date +%Y-%m-%d) |"
    echo "| 確認事項の件数 | ${total_count} |"
    echo "| 未回答の件数 | ${unanswered_count} |"
    echo "| 提示した相手 | 開発チーム |"
    echo
    echo "回答は確認事項一覧の回答欄へ開発チームが書く。この記録は回答を持たない。"
  } > "$out_file"
}

# ------------------------------------------------------------------
# --verify（既存の出力を設計書と突き合わせる）
# ------------------------------------------------------------------

run_verify() {
  local target_file="$1" design_root="$2"
  [ -f "$target_file" ] || { echo "[FAIL] 対象-不在: ${target_file}" >&2; return 2; }
  local design_docs_root="${design_root%/}/docs/design"
  local design_items
  design_items="$(collect_design_items "$design_docs_root")"
  local dkey
  local -a missing=()
  while IFS=$'\x1f' read -r dkey _ _ _ _ _; do
    [ -n "$dkey" ] || continue
    if ! grep -qF "| ${dkey} |" "$target_file"; then
      missing+=("$dkey")
    fi
  done <<< "$design_items"
  if [ "${#missing[@]}" -gt 0 ]; then
    local missing_list=""
    for dkey in "${missing[@]}"; do missing_list="${missing_list}${missing_list:+ }${dkey}"; done
    echo "[FAIL] キー-出力欠落: ${#missing[@]}件（${missing_list}）" >&2
    return 1
  fi
  echo "検証合格: 設計書のキーはすべて出力に含まれています"
  return 0
}

# ------------------------------------------------------------------
# self-test
# ------------------------------------------------------------------

self_test() {
  local pass=0 fail=0 tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/build-confirmation-items-self-test.XXXXXX" 2>/dev/null)" || {
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません" >&2
    exit 2
  }
  trap 'rm -rf "$tmp"' RETURN

  local run="${tmp}/run"
  local design_root="${tmp}/design_root"
  mkdir -p "${run}/confirmations" "${design_root}/docs/design/requirements" "${design_root}/docs/design/screens/OrderList"

  cat > "${run}/confirmations/確認事項の記録.md" << 'EOF'
| キー | 単位 | 種類 | 事項 | 既定 | 反映先 | 回答 | 状態 |
|---|---|---|---|---|---|---|---|
| 受注番号-桁数 | OrderList | 業務ルール | 受注番号の桁数 | 8桁とする | 画面基本設計書 OrderList | 未回答 | 未回答 |
| 表の名前-接頭辞 | 全体 | 規約提案 | 表の名前の接頭辞 | 決めるまで書かない | 規約 naming |  | 未回答 |
EOF

  cat > "${design_root}/docs/design/requirements/要件定義書.md" << 'EOF'
## 要確認事項一覧

| キー | 確認事項 | 確認先 |
|---|---|---|
| 期限-猶予日数 | 支払期限の猶予日数 | 事業部門 |
EOF

  local out1 rc1=0
  out1="$(run_build "$run" "$design_root" 2>&1)" || rc1=$?
  if [ "$rc1" -eq 0 ] && printf '%s' "$out1" | grep -q '期限-猶予日数' \
    && printf '%s' "$out1" | grep -q '記録に無いキー 1件'; then
    pass=$((pass + 1)); echo "  [PASS] ケース1: 記録に無いキーが出力に追加される（記録2行+新規1行=3行）"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース1: 記録に無いキーの追加が不正 (exit ${rc1})" >&2
    printf '%s\n' "$out1" | sed 's/^/    /' >&2
  fi

  if printf '%s' "$out1" | grep '期限-猶予日数' | grep -q '業務ルール'; then
    pass=$((pass + 1)); echo "  [PASS] ケース2: 確認先から種類を判定する（事業部門→業務ルール）"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース2: 種類の判定が不正" >&2
  fi

  local run3="${tmp}/run3" design3="${tmp}/design3"
  mkdir -p "${run3}/confirmations" "${design3}/docs/design/common"
  cat > "${run3}/confirmations/確認事項の記録.md" << 'EOF'
| キー | 単位 | 種類 | 事項 | 既定 | 反映先 | 回答 | 状態 |
|---|---|---|---|---|---|---|---|
| 欠落キー | 全体 | 制約 | 何か |  | 反映先あり |  | 未回答 |
EOF
  local out3 rc3=0
  out3="$(run_build "$run3" "$design3" 2>&1)" || rc3=$?
  if [ "$rc3" -eq 1 ] && printf '%s' "$out3" | grep -q '行-空欄'; then
    pass=$((pass + 1)); echo "  [PASS] ケース3: 既定が空なら終了コード1"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース3: 空欄の検知が不正 (exit ${rc3})" >&2
  fi

  local out_file4="${tmp}/確認事項一覧-欠落.md"
  cat > "$out_file4" << 'EOF'
| キー | 単位 | 種類 | 事項 | 既定 | 反映先 | 回答 | 状態 |
|---|---|---|---|---|---|---|---|
| 別のキー | 全体 | 制約 | 別 | 別の既定 | どこか |  | 未回答 |
EOF
  local out4 rc4=0
  out4="$(run_verify "$out_file4" "$design_root" 2>&1)" || rc4=$?
  if [ "$rc4" -eq 1 ] && printf '%s' "$out4" | grep -q 'キー-出力欠落'; then
    pass=$((pass + 1)); echo "  [PASS] ケース4: --verifyで設計書のキーが出力に無ければ終了コード1"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース4: --verifyの欠落検知が不正 (exit ${rc4})" >&2
  fi

  local out_file5="${tmp}/確認事項一覧-完備.md"
  cat > "$out_file5" << 'EOF'
| キー | 単位 | 種類 | 事項 | 既定 | 反映先 | 回答 | 状態 |
|---|---|---|---|---|---|---|---|
| 期限-猶予日数 | 全体 | 業務ルール | 支払期限の猶予日数 | 設計書の現行の記述のまま扱う | 要件定義書.md 全体 |  | 未回答 |
EOF
  local out5 rc5=0
  out5="$(run_verify "$out_file5" "$design_root" 2>&1)" || rc5=$?
  if [ "$rc5" -eq 0 ]; then
    pass=$((pass + 1)); echo "  [PASS] ケース5: --verifyで欠落が無ければ合格"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース5: --verifyの合格判定が不正 (exit ${rc5})" >&2
  fi

  # ケース6: セル内のエスケープ済みパイプ "\|" で列がずれない
  local design6="${tmp}/design6"
  mkdir -p "${design6}/docs/design/requirements"
  cat > "${design6}/docs/design/requirements/要件定義書.md" << 'EOF'
## 要確認事項一覧

| キー | 確認事項 | 確認先 |
|---|---|---|
| 表示形式-パイプ | A\|Bのどちらを既定にするか | 事業部門 |
EOF
  local run6="${tmp}/run6"
  mkdir -p "${run6}/confirmations"
  local out6 rc6=0
  out6="$(run_build "$run6" "$design6" 2>&1)" || rc6=$?
  if [ "$rc6" -eq 0 ] && printf '%s' "$out6" | grep -qF '| 表示形式-パイプ | 全体 | 業務ルール | A|Bのどちらを既定にするか |'; then
    pass=$((pass + 1)); echo "  [PASS] ケース6: セル内のエスケープ済みパイプで列がずれない"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース6: エスケープ済みパイプの扱いが不正 (exit ${rc6})" >&2
    printf '%s\n' "$out6" | sed 's/^/    /' >&2
  fi

  # ケース7: 見出しの前方一致（末尾に空白があっても要確認事項一覧を認識する）
  local design7="${tmp}/design7"
  mkdir -p "${design7}/docs/design/requirements"
  printf '## 要確認事項一覧 \n\n| キー | 確認事項 | 確認先 |\n|---|---|---|\n| 見出し-末尾空白 | 見出し末尾に空白がある場合の確認 | 設計担当 |\n' \
    > "${design7}/docs/design/requirements/要件定義書.md"
  local run7="${tmp}/run7"
  mkdir -p "${run7}/confirmations"
  local out7 rc7=0
  out7="$(run_build "$run7" "$design7" 2>&1)" || rc7=$?
  if [ "$rc7" -eq 0 ] && printf '%s' "$out7" | grep -q '見出し-末尾空白'; then
    pass=$((pass + 1)); echo "  [PASS] ケース7: 見出し末尾の空白があっても要確認事項一覧を認識する"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース7: 見出しの前方一致が不正 (exit ${rc7})" >&2
    printf '%s\n' "$out7" | sed 's/^/    /' >&2
  fi

  # ケース8: 同じキーが2つの設計書に現れると単位欄に「ほか1件」が出る
  local design8="${tmp}/design8"
  mkdir -p "${design8}/docs/design/requirements" "${design8}/docs/design/common"
  cat > "${design8}/docs/design/requirements/要件定義書.md" << 'EOF'
## 要確認事項一覧

| キー | 確認事項 | 確認先 |
|---|---|---|
| 重複-キー | 両方の設計書に現れる事項 | 事業部門 |
EOF
  cat > "${design8}/docs/design/common/業務仕様書.md" << 'EOF'
## 要確認事項一覧

| キー | 確認事項 | 確認先 |
|---|---|---|
| 重複-キー | 両方の設計書に現れる事項 | 運用部門 |
EOF
  local run8="${tmp}/run8"
  mkdir -p "${run8}/confirmations"
  local out8 rc8=0
  out8="$(run_build "$run8" "$design8" 2>&1)" || rc8=$?
  if [ "$rc8" -eq 0 ] && printf '%s' "$out8" | grep '重複-キー' | grep -q 'ほか1件'; then
    pass=$((pass + 1)); echo "  [PASS] ケース8: 同じキーが2設計書にあると単位欄に「ほか1件」が出る"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース8: 重複キーの件数表示が不正 (exit ${rc8})" >&2
    printf '%s\n' "$out8" | sed 's/^/    /' >&2
  fi

  # ケース9: bash 3.2 で「記録ファイル不在」かつ「新規0件」（全配列が空）でも
  # unbound variableにならず正常に完了する。/bin/bashが3.2系のときだけ実行する。
  local bash32_version
  bash32_version="$(/bin/bash -c 'echo "$BASH_VERSION"' 2>/dev/null || true)"
  if [[ "$bash32_version" == 3.2* ]]; then
    local run9="${tmp}/run9" design9="${tmp}/design9"
    mkdir -p "${run9}/confirmations" "${design9}/docs/design/common"
    local out9 rc9=0
    out9="$(/bin/bash -c 'set -uo pipefail; source "'"${SCRIPT_DIR}/build-confirmation-items.sh"'"; run_build "'"$run9"'" "'"$design9"'"' 2>&1)" || rc9=$?
    if [ "$rc9" -eq 0 ] && printf '%s' "$out9" | grep -q '記録に無いキー 0件'; then
      pass=$((pass + 1)); echo "  [PASS] ケース9: /bin/bash(3.2)で記録不在・新規0件でもunbound variableにならない"
    else
      fail=$((fail + 1)); echo "  [FAIL] ケース9: bash3.2互換性が不正 (exit ${rc9})" >&2
      printf '%s\n' "$out9" | sed 's/^/    /' >&2
    fi
  else
    pass=$((pass + 1)); echo "  [PASS扱い-省略] ケース9: /bin/bashが3.2系でないため省略（現在: ${bash32_version:-不明}）"
  fi

  # ケース10: 確認事項一覧を書いた後に提示の記録が書かれ、件数が一覧と一致する
  local run10="${tmp}/run10" design10="${tmp}/design10" presentation_out10 list10
  local rows10="" unans10="" rec_rows10="" rec_unans10=""
  mkdir -p "${run10}/confirmations" "${design10}/docs/design/requirements"
  cp "${run}/confirmations/確認事項の記録.md" "${run10}/confirmations/確認事項の記録.md"
  cp "${design_root}/docs/design/requirements/要件定義書.md" "${design10}/docs/design/requirements/要件定義書.md"
  bash "${BASH_SOURCE[0]}" "$run10" --design-root "$design10" >/dev/null 2>&1
  list10="${run10}/confirmations/確認事項一覧.md"
  presentation_out10="${run10}/confirmations/確認事項の提示の記録.md"
  if [ -f "$list10" ] && [ -f "$presentation_out10" ]; then
    rows10="$(awk '/^\|---/{s=1;next} s&&/^\| /{c++} END{print c+0}' "$list10")"
    unans10="$(awk -F'|' '/^\|---/{s=1;next} s&&/^\| /{v=$(NF-1); gsub(/^[ \t]+|[ \t]+$/,"",v); if(v=="未回答")c++} END{print c+0}' "$list10")"
    rec_rows10="$(awk -F'|' '/^\| 確認事項の件数 /{v=$3; gsub(/^[ \t]+|[ \t]+$/,"",v); print v}' "$presentation_out10")"
    rec_unans10="$(awk -F'|' '/^\| 未回答の件数 /{v=$3; gsub(/^[ \t]+|[ \t]+$/,"",v); print v}' "$presentation_out10")"
  fi
  if [ -n "$rows10" ] && [ "$rows10" -gt 0 ] \
    && [ "$rows10" = "$rec_rows10" ] && [ "$unans10" = "$rec_unans10" ] \
    && grep -q '提示した日' "$presentation_out10" \
    && grep -q '提示した相手' "$presentation_out10"; then
    pass=$((pass + 1)); echo "  [PASS] ケース10: 確認事項一覧とあわせて提示の記録が書かれる"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース10: 記録の件数が一覧と一致しない（一覧 ${rows10}／${unans10}、記録 ${rec_rows10}／${rec_unans10}）" >&2
  fi

  # ケース11: 終了コード1のとき一覧も記録も作られない（詳細設計書§5「失敗したときの出力の扱い」）
  local run11="${tmp}/run11" design11="${tmp}/design11" rc11=0
  mkdir -p "${run11}/confirmations" "${design11}/docs/design/requirements"
  cat > "${run11}/confirmations/確認事項の記録.md" << 'EOF'
# 確認事項の記録

| キー | 単位 | 種類 | 事項 | 既定 | 反映先 | 回答 | 状態 |
|---|---|---|---|---|---|---|---|
| 金額-丸め | 全体 | 業務ルール | 端数の扱い |  | 業務仕様書 全体 |  | 未回答 |
EOF
  cat > "${design11}/docs/design/requirements/要件定義書.md" << 'EOF'
# 要件定義書
EOF
  bash "${BASH_SOURCE[0]}" "$run11" --design-root "$design11" >/dev/null 2>&1 || rc11=$?
  if [ "$rc11" -eq 1 ] \
    && [ ! -f "${run11}/confirmations/確認事項一覧.md" ] \
    && [ ! -f "${run11}/confirmations/確認事項の提示の記録.md" ]; then
    pass=$((pass + 1)); echo "  [PASS] ケース11: 終了コード1のとき一覧も記録も作られない"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース11: 失敗時に出力が作られている (exit ${rc11})" >&2
  fi

  echo "実行 $((pass + fail)) 件 / 合格 ${pass} 件（失敗 ${fail} 件）"
  if [ "$fail" -eq 0 ]; then
    return 0
  fi
  return 1
}

# ------------------------------------------------------------------
# エントリポイント（sourceされたときは実行しない。plan-units.sh等と同じ形）
# ------------------------------------------------------------------

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi

  if [ "${1:-}" = "--verify" ]; then
    local target_file="${2:-}"
    local design_root=""
    shift 2 2>/dev/null || usage_error
    while [ $# -gt 0 ]; do
      case "$1" in
        --design-root) design_root="${2:-}"; shift 2 ;;
        *) usage_error ;;
      esac
    done
    [ -n "$target_file" ] && [ -n "$design_root" ] || usage_error
    run_verify "$target_file" "$design_root"
    exit $?
  fi

  [ $# -ge 1 ] || usage_error
  local run_dir="$1"; shift
  local design_root=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --design-root) design_root="${2:-}"; shift 2 ;;
      *) usage_error ;;
    esac
  done
  [ -d "$run_dir" ] || { echo "[FAIL] 実行フォルダ-不在: ${run_dir}" >&2; exit 2; }
  if [ -z "$design_root" ]; then
    design_root="$(bash "${SHARED_DIR}/design-root.sh" "$run_dir" 2>/dev/null || true)"
    [ -n "$design_root" ] || { echo "[FAIL] 設計書の置き場-不明" >&2; exit 2; }
  fi

  mkdir -p "${run_dir%/}/confirmations"
  local out rc
  out="$(run_build "$run_dir" "$design_root")"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    printf '%s\n' "$out" >&2
    exit "$rc"
  fi
  printf '%s\n' "$out" > "${run_dir%/}/confirmations/確認事項一覧.md"
  write_presentation_record "$run_dir" "$out"
  echo "確認事項一覧を書きました: ${run_dir%/}/confirmations/確認事項一覧.md"
  exit 0
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main "$@"
fi
