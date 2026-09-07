#!/usr/bin/env bash
set -u

# check-detail-design.sh — 種別ごとの詳細設計書（表はテーブル定義書）の
# 実在・節の構成・読み取り結果の網羅を検査する
#
# 目的:
#   工程2-8の完了条件（全単位に詳細設計書がある・読み取り結果を網羅している・
#   file:lineが無い）を種別ごとに単位ごとへ回して機械で確かめる。
#
# 使い方:
#   check-detail-design.sh <対象リポジトリのルート> --run <実行フォルダ> --kind <種別> [--design-root <設計書のルート>]
#   check-detail-design.sh --self-test
#
# --design-root の既定は対象リポジトリのルート。一覧・詳細設計書・合格の記録は
# 設計書のルート配下で読み書きする。
#
# 種別: screen / api / table / batch / report / external（featureは対象外。
#   機能設計書には対応する詳細設計テンプレートが存在しないため）
#
# 依存（相対パスで呼ぶ。本スクリプトの場所からの相対解決）:
#   ../../reverse-shared/scripts/list-units-of.sh   一覧の取得（5列目のフォルダ名をそのまま使う。
#     unit-dir-name.shを識別子から直接呼んで作り直すことはしない）
#   ../../reverse-shared/references/unit-kinds.json  種別キーとフォルダの対応
#   ../../reverse-shared/scripts/check-acceptance-record.sh  合格の記録の確認
#
# 検査キー（内容を要約した意味語。連番禁止）:
#   検査基盤-不在      上記の依存スクリプト・定義が見つからない（判定不能）
#   種別-不正          --kind が対象外（feature含む）または一覧に無い（判定不能）
#   一覧-不在          list-units-of.sh が一覧無しで終了コード2を返す（判定不能）
#   合格記録-不在      check-acceptance-record.sh の終了コードが0でない
#   文書-不在          種別ごとの詳細設計書（表はテーブル定義書）が実在しない
#   節-欠落            種別ごとの様式が定める`##`見出しが順に揃わない
#   未記入-残存        `<...>`形式のプレースホルダーが残っている
#   位置-禁止          file:line形式の実装位置の記述がある
#   見出し-表示名不一致  詳細設計書のh1が一覧の表示名と一致しない
#   読み取り結果-未網羅        読み取り結果ファイルの値が空でない項目の値が文書本文に現れない
#
# 検査から外した項目（旧様式からの移行に伴う既知の限界。理由も記す）:
#   ファイル-不一致    旧の「対応するファイル」表（1列1ファイル）に相当する表を
#                      旧様式のテンプレートは持たない。テーブル定義書の§1構成要素は
#                      「要素名・種別・可視性・所在」で1行1コード要素であり、
#                      1行1ファイルの集合比較が成立しない。対応するファイルの手掛
#                      かりが必要な場合は§6関連資料を人手で確認する
#   整合-欠落          旧の実装（基本設計書の`### <項目名>`見出しが個々の読み取り結果項目を
#                      表す前提）は、旧様式の`### `見出しがテンプレート共通の節番号
#                      付き小見出し（例:「### 2.1 業務フロー」）であり読み取り結果項目を
#                      表さないため成立しない。基本設計と詳細設計の読み取り結果の一貫性は
#                      読み取り結果ファイルを共通の入力源とする読み取り結果-未網羅（本スクリプト）
#                      と読み取り結果-未転記（check-basic-design.sh）の組で担保する
#
# 単位の保留は廃止（2026-09-05）。check-acceptance-record.shの終了コードが
# 0でなければ不合格にする。合格の記録の判定を本スクリプトが再読み込み
# することはしない（定義はcheck-acceptance-record.sh 1か所に置く）。
# check-acceptance-record.shの呼び出しには--runを渡す（2026-09-06改善。
# 要確認の観点を持つ記録は--run無しでは要確認-判定不能として不合格になる）。
#
# 終了コード:
#   0 = 全単位合格
#   1 = 1単位以上不合格
#   2 = 使い方の誤り・依存の不在・種別の不正・一覧の不在（判定不能）
#
# 保守責任者: 人手（ユーザー）。様式の見出し構成を変えるときは、
#   ../templates/<種別key>/内のテンプレートとexpected_headings()・doc_name_of()・
#   本スクリプトと自己テストを同時に直す。
#
# 廃棄条件: 詳細設計書の様式を構造化データに変えた時。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。jqを使用する。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST_UNITS_OF="${SCRIPT_DIR}/../../reverse-shared/scripts/list-units-of.sh"
UNIT_DIR_NAME="${SCRIPT_DIR}/../../reverse-shared/scripts/unit-dir-name.sh"
UNIT_KINDS_JSON="${SCRIPT_DIR}/../../reverse-shared/references/unit-kinds.json"
ACCEPTANCE_RECORD_CHECK="${SCRIPT_DIR}/../../reverse-shared/scripts/check-acceptance-record.sh"

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
  echo "使い方: check-detail-design.sh <対象リポジトリのルート> --run <実行フォルダ> --kind <種別> [--design-root <設計書のルート>]" >&2
  echo "        check-detail-design.sh --self-test" >&2
  exit 2
}

is_valid_kind() {
  case "$1" in
    screen|api|table|batch|report|external) return 0 ;;
    *) return 1 ;;
  esac
}

has_jq() {
  command -v jq > /dev/null 2>&1
}

# 様式の"## "見出しの並び（表とそれ以外）
# 種別ごとの詳細設計書（表はテーブル定義書）の様式（見出しはテンプレートの
# 実測どおり「§N ...」を含めて1行ずつ書く。並び順はテンプレートの節の順）
expected_headings() {
  case "$1" in
    screen)
      printf '%s\n' \
        "§1 画面概要" "§2 機能一覧" "§3 画面構造" \
        "§4 業務ルール（条件付き：業務モード・権限制御がある画面のみ）" \
        "§5 状態管理" "§6 データフロー" "§7 ロジック" "§8 疑似コード" \
        "§9 API 通信仕様（条件付き：API を呼ぶ画面のみ）" "§10 データ定義" \
        "§11 イベント処理" "§12 領域別仕様" \
        "§13 定数・設定値（条件付き：画面固有の定数がある場合のみ）" \
        "§14 エラーハンドリング" "§15 画面遷移仕様" "§16 非機能要件" \
        "§17 共通仕様への準拠" "§18 実装契約" "§19 関連資料"
      ;;
    api)
      printf '%s\n' \
        "§1 API概要" "§2 リクエスト" "§3 レスポンス" "§4 処理フロー" \
        "§5 ロジック" "§6 業務ルールとバリデーション" "§7 エラー" \
        "§8 非機能" "§9 関連資料"
      ;;
    *)
      printf '%s\n' \
        "§1 構成要素" "§2 処理の定義" "§3 ロジック" "§4 入出力の値" \
        "§5 エラー処理" "§6 関連資料"
      ;;
  esac
}

doc_name_of() {
  case "$1" in
    screen) printf '%s' "画面詳細設計書.md" ;;
    api) printf '%s' "API詳細設計書.md" ;;
    table) printf '%s' "テーブル定義書.md" ;;
    batch) printf '%s' "バッチ詳細設計書.md" ;;
    report) printf '%s' "帳票詳細設計書.md" ;;
    external) printf '%s' "外部連携詳細設計書.md" ;;
    *) printf '%s' "" ;;
  esac
}

# 見出し-前付け読み飛ばし: 前付け（1行目が`---`だけの行で始まり、次の`---`だけの
# 行で閉じる区間）を読み飛ばした後の最初の`# `で始まる行（本文のh1）を返す。
# 前付けの中の`# `行は見出しとして扱わない。前付けが閉じていない文書は空を返す
# （壊れた前付けの行を表示名の候補として報告すると読み手を誤らせるため）。
# 本番の検査（check_unit_doc）と自己テストの両方が本関数を呼ぶ
# （第1回改善指示書1-27）。
# $1: 文書パス
extract_body_h1() {
  awk 'NR==1&&/^---$/{fm=1;next} fm&&/^---$/{fm=0;next} fm{next} /^# /{print;exit}' "$1"
}

check_unit_doc() {
  local doc="$1" kind="$2" name="${3:-}"

  if [ ! -f "$doc" ]; then
    fail "文書-不在" "$doc"
    return
  fi

  # 見出し-表示名不一致（h1が元データの表示名と一致するか）
  if [ -n "$name" ]; then
    local suffix expected_h1 actual_h1
    suffix="$(doc_name_of "$kind")"
    suffix="${suffix%.md}"
    expected_h1="# ${name} ${suffix}"
    actual_h1="$(extract_body_h1 "$doc")"
    if [ "$actual_h1" = "$expected_h1" ]; then
      passck
    else
      fail "見出し-表示名不一致" "${doc}: h1「${actual_h1}」が期待「${expected_h1}」と一致しません"
    fi
  fi

  # 節-欠落
  local n_expected expected_list actual_list
  expected_list="$(expected_headings "$kind")"
  n_expected="$(printf '%s\n' "$expected_list" | grep -c '.')"
  actual_list="$(grep -E '^## ' "$doc" | sed 's/^## //' | head -n "$n_expected")"
  if [ "$expected_list" = "$actual_list" ]; then
    passck
  else
    fail "節-欠落" "${doc}: 見出しが規定と一致しません（実際: $(printf '%s' "$actual_list" | tr '\n' '/')）"
  fi

  # 未記入-残存（二重引用符で囲まれた範囲は除く。第1回改善指示書1-36）
  local placeholder_lines
  placeholder_lines="$(awk '
    {
      line = $0
      gsub(/\\"/, "\x01", line)
      gsub(/"[^"]*"/, "", line)
      gsub(/\x01/, "\"", line)
      if (line ~ /<[^<>]+>/) print NR ":" $0
    }
  ' "$doc" || true)"
  if [ -n "$placeholder_lines" ]; then
    fail "未記入-残存" "${doc}: 未記入のプレースホルダーがあります（例: $(printf '%s\n' "$placeholder_lines" | head -1)）"
  else
    passck
  fi

  # 位置-禁止
  local pos_lines
  pos_lines="$(grep -nE '[A-Za-z0-9_./-]+\.(ts|js|py|rb|php|java|go|pl|cs|tsx|jsx):[0-9]+' "$doc" || true)"
  if [ -n "$pos_lines" ]; then
    fail "位置-禁止" "${doc}: 実装位置(file:line)の記述があります（例: $(printf '%s\n' "$pos_lines" | head -1)）"
  else
    passck
  fi
}

check_readings_coverage() {
  local doc="$1" readings_json="$2"

  if [ ! -f "$readings_json" ]; then
    fail "読み取り結果-不在" "$readings_json が存在しません"
    return
  fi
  if ! has_jq; then
    fail "検査基盤-不在" "jqが使えません"
    return
  fi

  local items ok=1
  items="$(jq -r '.["読み取り結果"] | keys[]' "$readings_json" 2>/dev/null || true)"
  local item
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    local values
    values="$(jq -r --arg k "$item" '.["読み取り結果"][$k]["値"][]?' "$readings_json" 2>/dev/null || true)"
    local v
    while IFS= read -r v; do
      [ -n "$v" ] || continue
      if ! grep -qF -- "$v" "$doc"; then
        fail "読み取り結果-未網羅" "${item}=${v}"
        ok=0
      fi
    done <<VLIST
$values
VLIST
  done <<ILIST
$items
ILIST
  [ "$ok" -eq 1 ] && passck
}

run_units() {
  local target="$1" run_dir="$2" kind="$3" design_root="$4"
  local species_folder
  species_folder="$(jq -r --arg k "$kind" '.[] | select(.key==$k) | .["フォルダ"]' "$UNIT_KINDS_JSON")"
  if [ -z "$species_folder" ]; then
    echo "[FAIL] 種別-不正: unit-kinds.jsonに${kind}がありません" >&2
    return 2
  fi
  local doc_name
  doc_name="$(doc_name_of "$kind")"

  local units_out rc=0
  units_out="$(bash "$LIST_UNITS_OF" "$target" "$kind" --lists "${design_root%/}/docs/design/lists" 2>"${TMPDIR:-/tmp}/check-detail-design-list.$$")" || rc=$?
  if [ "$rc" -eq 2 ]; then
    echo "[FAIL] 一覧-不在: ${kind}の一覧がありません" >&2
    cat "${TMPDIR:-/tmp}/check-detail-design-list.$$" >&2
    rm -f "${TMPDIR:-/tmp}/check-detail-design-list.$$"
    return 2
  fi
  rm -f "${TMPDIR:-/tmp}/check-detail-design-list.$$"

  local line identifier name location files_csv folder
  # list-units-of.shの出力はタブ区切りだが、タブはbashのreadでは値に
  # 関わらず「IFSの空白」として連続分がまとめて削られる。属するファイル
  # （4列目）が空でフォルダ名（5列目）が非空という並びだと、空欄が消えて
  # フォルダ名が前の変数へずれ込む。タブを一度\037（IFSの空白扱いされない
  # 制御文字）へ置換してから読み、この崩れを避ける
  while IFS=$'\037' read -r identifier name location files_csv folder; do
    [ -n "$identifier" ] || continue
    local doc="${design_root%/}/docs/design/${species_folder}/${folder}/${doc_name}"
    local readings_json="${run_dir%/}/code-readings/${kind}/${folder}.json"

    local vrc=0
    bash "$ACCEPTANCE_RECORD_CHECK" "$target" --kind "$kind" --unit "$identifier" --design-root "$design_root" --run "$run_dir" > /dev/null 2>&1 || vrc=$?
    if [ "$vrc" -ne 0 ]; then
      fail "合格記録-不在" "${kind}/${identifier}"
      continue
    fi

    check_unit_doc "$doc" "$kind" "$name"
    [ -f "$doc" ] || continue
    check_readings_coverage "$doc" "$readings_json"
  done <<UNITLIST
$(printf '%s' "$units_out" | tr '\t' '\037')
UNITLIST

  return 0
}

run_self_test() {
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-detail-design-self-test.XXXXXX")" || { echo "一時領域を作成できません" >&2; return 2; }
  trap 'rm -rf "$tmp"' RETURN

  local total=0 fail=0

  # 自分自身と依存(reverse-sharedのlist-units-of.sh・unit-dir-name.sh、
  # reverse-sharedのcheck-acceptance-record.sh。いずれも別担当が
  # 並行して構築する)を隔離したfixtureへ複製し、実リポジトリの構築状況に
  # 左右されずに検査ロジックを確かめる。unit-dir-name.shのスタブは規約
  # （agent-operations/skill-naming）に定めるのと同じ置換規則で実装する。
  local self_dir own_name
  self_dir="$(cd "$(dirname "$0")" && pwd)"
  own_name="$(basename "$0")"
  local fixture_root="${tmp}/fixture-skills"
  local copy_dir="${fixture_root}/reverse-writing-detail-design/scripts"
  local shared_dir="${fixture_root}/reverse-shared/scripts"
  local shared_ref_dir="${fixture_root}/reverse-shared/references"
  local record_dir="${fixture_root}/reverse-shared/scripts"
  mkdir -p "$copy_dir" "$shared_dir" "$shared_ref_dir" "$record_dir"
  cp "${self_dir}/${own_name}" "${copy_dir}/${own_name}"
  chmod +x "${copy_dir}/${own_name}"
  local under_test="${copy_dir}/${own_name}"

  cp "${SCRIPT_DIR}/../../reverse-shared/references/unit-kinds.json" "${shared_ref_dir}/unit-kinds.json" 2>/dev/null \
    || cat > "${shared_ref_dir}/unit-kinds.json" <<'KINDSEOF'
[
  { "key": "screen", "名前": "画面", "フォルダ": "screens" },
  { "key": "api", "名前": "接続窓口", "フォルダ": "apis" },
  { "key": "table", "名前": "表", "フォルダ": "tables" },
  { "key": "batch", "名前": "バッチ", "フォルダ": "batches" },
  { "key": "report", "名前": "帳票", "フォルダ": "reports" },
  { "key": "external", "名前": "外部連携", "フォルダ": "externals" },
  { "key": "feature", "名前": "機能", "フォルダ": "features" }
]
KINDSEOF

  cat > "${shared_dir}/unit-dir-name.sh" <<'DIRNAMEEOF'
#!/usr/bin/env bash
id="${1:-}"
printf '%s' "$id" | sed -E 's#[/ {}:\\?*]#_#g' | sed -E 's/^_+//'
DIRNAMEEOF
  chmod +x "${shared_dir}/unit-dir-name.sh"

  local list_data="${tmp}/list-data.tsv"
  cat > "${shared_dir}/list-units-of.sh" <<LISTEOF
#!/usr/bin/env bash
if [ ! -f "${list_data}" ]; then
  echo "一覧がありません" >&2
  exit 2
fi
cat "${list_data}"
LISTEOF
  chmod +x "${shared_dir}/list-units-of.sh"

  local record_rc_file="${tmp}/record-rc.txt"
  echo 0 > "$record_rc_file"
  cat > "${record_dir}/check-acceptance-record.sh" <<RECORDCHECKEOF
#!/usr/bin/env bash
exit "\$(cat "${record_rc_file}")"
RECORDCHECKEOF
  chmod +x "${record_dir}/check-acceptance-record.sh"

  local target="${tmp}/target"
  local run_dir="${tmp}/run"
  local ident="orders"
  local folder="orders"
  local doc_dir="${target}/docs/design/tables/${folder}"
  mkdir -p "$doc_dir" "${target}/ai-work/records/basic-design-acceptance" "${run_dir}/code-readings/table"

  # 4列目（属するファイル）を空にし5列目（フォルダ名）を非空にした行で、
  # タブ2つ連続の並びを作る（読み取り側の空欄崩れの回帰確認を兼ねる）
  printf '%s\t%s\t%s\t%s\t%s\n' "$ident" "受注テーブル" "$ident" "" "$folder" > "$list_data"

  cat > "${run_dir}/code-readings/table/${folder}.json" <<'FACTSEOF'
{
  "種別": "table",
  "識別子": "orders",
  "読み取り結果": {
    "列": {"値": ["受注番号"], "出所": "機械", "根拠": ["orders"]},
    "関係": {"値": ["顧客テーブルを参照"], "出所": "機械", "根拠": ["orders"]}
  },
  "未": []
}
FACTSEOF

  write_doc_good() {
    cat > "${doc_dir}/テーブル定義書.md" <<'DOCEOF'
# 受注テーブル テーブル定義書

## §1 構成要素

| 要素名 | 種別 | 可視性 | 所在 |
|---|---|---|---|
| orders | table | public | db/schema.sql |

## §2 処理の定義

記入済み

## §3 ロジック

記入済み

## §4 入出力の値

記入済み。受注番号を扱う。

## §5 エラー処理

記入済み（理由（観測）: 既存の実装を踏まえる）

## §6 関連資料

顧客テーブルを参照する。

## 要確認事項一覧

なし
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

  refute_contains() {
    local desc="$1" key="$2"
    total=$((total + 1))
    if grep -qF "[FAIL] ${key}" "${tmp}/err.log"; then
      echo "FAIL: ${desc}（${key} の不合格が出ています）"
      sed -n '1,20p' "${tmp}/err.log"
      fail=$((fail + 1))
    else
      echo "PASS: ${desc}"
    fi
  }

  # 合格
  write_doc_good
  echo 0 > "$record_rc_file"
  assert_exit "合格" 0 bash "$under_test" "$target" --run "$run_dir" --kind table
  refute_contains "合格-未記入も様式の残骸もない: 未記入-残存が出ない" "未記入-残存"
  assert_exit "位置づけ-不要: 位置づけの行が無い文書が合格する" 0 bash "$under_test" "$target" --run "$run_dir" --kind table

  # 合格-表の列ごとの型と制約が§4に書かれている
  cat > "${run_dir}/code-readings/table/${folder}.json" <<'FACTSCOLEOF'
{
  "種別": "table",
  "識別子": "orders",
  "読み取り結果": {
    "列": {"値": ["受注番号"], "出所": "機械", "根拠": ["orders"]},
    "型": {"値": ["bigint unsigned"], "出所": "機械", "根拠": ["orders"]},
    "制約": {"値": ["NOT NULL"], "出所": "機械", "根拠": ["orders"]},
    "関係": {"値": ["顧客テーブルを参照"], "出所": "機械", "根拠": ["orders"]}
  },
  "未": []
}
FACTSCOLEOF
  cat > "${doc_dir}/テーブル定義書.md" <<'DOCCOLEOF'
# 受注テーブル テーブル定義書

## §1 構成要素

| 要素名 | 種別 | 可視性 | 所在 |
|---|---|---|---|
| orders | table | public | db/schema.sql |

## §2 処理の定義

記入済み

## §3 ロジック

記入済み

## §4 入出力の値

| 要素名 | 区分 | 名前 | 型 | 有効な範囲 | 空値の許容 | 初期値 | 桁と精度 |
|---|---|---|---|---|---|---|---|
| orders | 列 | 受注番号 | bigint unsigned | - | NOT NULL | - | - |

## §5 エラー処理

記入済み（理由（観測）: 既存の実装を踏まえる）

## §6 関連資料

顧客テーブルを参照する。

## 要確認事項一覧

なし
DOCCOLEOF
  assert_exit "合格-表の列ごとの型と制約が§4に書かれている" 0 bash "$under_test" "$target" --run "$run_dir" --kind table

  # 元の読み取り結果・様式に戻す
  cat > "${run_dir}/code-readings/table/${folder}.json" <<'FACTSEOF'
{
  "種別": "table",
  "識別子": "orders",
  "読み取り結果": {
    "列": {"値": ["受注番号"], "出所": "機械", "根拠": ["orders"]},
    "関係": {"値": ["顧客テーブルを参照"], "出所": "機械", "根拠": ["orders"]}
  },
  "未": []
}
FACTSEOF

  # --- 設計書ルート分離-対象に書かない ---
  local target_code_only="${tmp}/target-code-only"
  local design_root2="${tmp}/design-root2"
  mkdir -p "$target_code_only"
  mkdir -p "$design_root2/docs/design/tables/${folder}" "$design_root2/ai-work/records/basic-design-acceptance"
  cp "${doc_dir}/テーブル定義書.md" "$design_root2/docs/design/tables/${folder}/"
  assert_exit "設計書ルート分離-合格" 0 bash "$under_test" "$target_code_only" --run "$run_dir" --kind table --design-root "$design_root2"
  total=$((total + 1))
  if [ ! -e "$target_code_only/docs" ]; then
    echo "PASS: 設計書ルート分離-対象に書かない"
  else
    echo "FAIL: 設計書ルート分離-対象に書かない（対象側にdocsが作られています）"
    fail=$((fail + 1))
  fi

  # 不合格-合格記録なし
  echo 1 > "$record_rc_file"
  assert_exit "不合格-合格記録なし" 1 bash "$under_test" "$target" --run "$run_dir" --kind table
  assert_contains "不合格-合格記録なし: 合格記録-不在が出る" "合格記録-不在"

  # 不合格（複合）: 節の欠落・未記入・file:line・読み取り結果未網羅
  echo 0 > "$record_rc_file"
  cat > "${doc_dir}/テーブル定義書.md" <<'BADEOF'
# 受注テーブル テーブル定義書

## §1 構成要素

| 要素名 | 種別 | 可視性 | 所在 |
|---|---|---|---|
| orders | table | public | db/schema.sql |

## §2 処理の定義

<ここを埋める>

## §3 ロジック

src/legacy.ts:12 を参照する。
BADEOF
  assert_exit "不合格-複合" 1 bash "$under_test" "$target" --run "$run_dir" --kind table
  assert_contains "不合格-複合: 節-欠落が出る" "節-欠落"
  assert_contains "不合格-複合: 未記入-残存が出る" "未記入-残存"
  assert_contains "不合格-複合: 位置-禁止が出る" "位置-禁止"
  assert_contains "不合格-複合: 読み取り結果-未網羅が出る" "読み取り結果-未網羅"
  write_doc_good

  # 合格-引用の中の山括弧は未記入と見なさない（第1回改善指示書1-36）
  echo 0 > "$record_rc_file"
  cat > "${doc_dir}/テーブル定義書.md" <<'QUOTEOKEOF'
# 受注テーブル テーブル定義書

## §1 構成要素

| 要素名 | 種別 | 可視性 | 所在 |
|---|---|---|---|
| orders | table | public | db/schema.sql |

## §2 処理の定義

記入済み。採番の形式は "EM<連番>" である。

## §3 ロジック

記入済み

## §4 入出力の値

記入済み。受注番号を扱う。

## §5 エラー処理

記入済み（理由（観測）: 既存の実装を踏まえる）

## §6 関連資料

顧客テーブルを参照する。

## 要確認事項一覧

なし
QUOTEOKEOF
  assert_exit "合格-引用の中の山括弧" 0 bash "$under_test" "$target" --run "$run_dir" --kind table
  refute_contains "合格-引用の中の山括弧: 未記入-残存が出ない" "未記入-残存"
  write_doc_good

  # 不合格-引用の外の様式の残骸は未記入として検出する（第1回改善指示書1-36）
  echo 0 > "$record_rc_file"
  cat > "${doc_dir}/テーブル定義書.md" <<'QUOTENGEOF'
# 受注テーブル テーブル定義書

## §1 構成要素

| 要素名 | 種別 | 可視性 | 所在 |
|---|---|---|---|
| orders | table | public | db/schema.sql |

## §2 処理の定義

記入済み。採番の形式は <ここを埋める> である。

## §3 ロジック

記入済み

## §4 入出力の値

記入済み。受注番号を扱う。

## §5 エラー処理

記入済み（理由（観測）: 既存の実装を踏まえる）

## §6 関連資料

顧客テーブルを参照する。

## 要確認事項一覧

なし
QUOTENGEOF
  assert_exit "不合格-様式の残骸(引用の外)" 1 bash "$under_test" "$target" --run "$run_dir" --kind table
  assert_contains "不合格-様式の残骸(引用の外): 未記入-残存が出る" "未記入-残存"
  write_doc_good

  # 合格-引用の中にエスケープされた引用符（\"）がある行も未記入と見なさない（第1回改善指示書1-36）
  echo 0 > "$record_rc_file"
  cat > "${doc_dir}/テーブル定義書.md" <<'QUOTEESCEOF'
# 受注テーブル テーブル定義書

## §1 構成要素

| 要素名 | 種別 | 可視性 | 所在 |
|---|---|---|---|
| orders | table | public | db/schema.sql |

## §2 処理の定義

記入済み。識別子の例は "採番は\"EM<連番>\"の形式" である。

## §3 ロジック

記入済み

## §4 入出力の値

記入済み。受注番号を扱う。

## §5 エラー処理

記入済み（理由（観測）: 既存の実装を踏まえる）

## §6 関連資料

顧客テーブルを参照する。

## 要確認事項一覧

なし
QUOTEESCEOF
  assert_exit "合格-引用の中のエスケープされた引用符" 0 bash "$under_test" "$target" --run "$run_dir" --kind table
  refute_contains "合格-引用の中のエスケープされた引用符: 未記入-残存が出ない" "未記入-残存"
  write_doc_good

  # 判定不能-文書不在
  rm -f "${doc_dir}/テーブル定義書.md"
  assert_exit "不合格-文書不在" 1 bash "$under_test" "$target" --run "$run_dir" --kind table
  assert_contains "不合格-文書不在: 文書-不在が出る" "文書-不在"
  write_doc_good

  # 判定不能-一覧不在
  mv "$list_data" "${list_data}.bak"
  assert_exit "判定不能-一覧不在" 2 bash "$under_test" "$target" --run "$run_dir" --kind table
  mv "${list_data}.bak" "$list_data"

  # 判定不能-種別不正
  assert_exit "判定不能-種別不正" 2 bash "$under_test" "$target" --run "$run_dir" --kind feature

  # 判定不能-使い方の誤り
  assert_exit "判定不能-使い方の誤り" 2 bash "$under_test"

  # 判定不能-検査基盤不在
  rm -f "${shared_dir}/list-units-of.sh"
  assert_exit "判定不能-検査基盤不在" 2 bash "$under_test" "$target" --run "$run_dir" --kind table

  # --- 見出し-前付け読み飛ばし: extract_body_h1（本番と共有）の抽出が前付け
  #     （---〜---）の中の見出し風の行を本文の見出しと誤認しないこと
  #     （第1回改善指示書1-27） ---
  check_h1() {
    local desc="$1" expected="$2" actual="$3"
    total=$((total + 1))
    if [ "$actual" = "$expected" ]; then
      echo "PASS: ${desc}"
    else
      echo "FAIL: ${desc}（期待「${expected}」/ 実際「${actual}」）"
      fail=$((fail + 1))
    fi
  }

  local h1_case1="${tmp}/h1-case1.md"
  printf -- '---\n# 受注テーブル テーブル定義書（unit_kind=table・1つの表に1枚）\nkey: 受注\n---\n\n# 受注テーブル テーブル定義書\n' > "$h1_case1"
  check_h1 "見出し-前付け読み飛ばし: 前付けあり・中に見出し風の行がある文書は本文の見出しを取る" "# 受注テーブル テーブル定義書" "$(extract_body_h1 "$h1_case1")"

  local h1_case2="${tmp}/h1-case2.md"
  printf '# 受注テーブル テーブル定義書\n\n本文。\n' > "$h1_case2"
  check_h1 "見出し-前付け読み飛ばし: 前付けなし・1行目が見出しの文書は本文の見出しを取る" "# 受注テーブル テーブル定義書" "$(extract_body_h1 "$h1_case2")"

  local h1_case3="${tmp}/h1-case3.md"
  printf '地の文がまず来る。\n\n# 受注テーブル テーブル定義書\n' > "$h1_case3"
  check_h1 "見出し-前付け読み飛ばし: 前付けなし・見出しの前に地の文がある文書は本文の見出しを取る" "# 受注テーブル テーブル定義書" "$(extract_body_h1 "$h1_case3")"

  local h1_case4="${tmp}/h1-case4.md"
  printf -- '---\nkey: 受注\n---\n\n# 受注テーブル テーブル定義書\n' > "$h1_case4"
  check_h1 "見出し-前付け読み飛ばし: 前付けあり・中に見出し風の行が無い文書は本文の見出しを取る" "# 受注テーブル テーブル定義書" "$(extract_body_h1 "$h1_case4")"

  local h1_case5="${tmp}/h1-case5.md"
  printf '見出しを1つも持たない文書。\n\n本文。\n' > "$h1_case5"
  check_h1 "見出し-前付け読み飛ばし: 見出しが1つも無い文書は空を返す" "" "$(extract_body_h1 "$h1_case5")"

  local h1_case6="${tmp}/h1-case6.md"
  printf -- '---\n# 受注テーブル テーブル定義書（unit_kind=table・1つの表に1枚）\nkey: 受注\n\n# 受注テーブル テーブル定義書\n' > "$h1_case6"
  check_h1 "見出し-前付け読み飛ばし: 前付けが閉じていない文書は空を返す（壊れた前付けを本文と見なさない）" "" "$(extract_body_h1 "$h1_case6")"

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

if ! has_jq; then
  echo "[FAIL] 検査基盤-不在: jqが使えません" >&2
  exit 2
fi
if [ ! -f "$LIST_UNITS_OF" ] || [ ! -f "$UNIT_DIR_NAME" ] || [ ! -f "$UNIT_KINDS_JSON" ] || [ ! -f "$ACCEPTANCE_RECORD_CHECK" ]; then
  echo "[FAIL] 検査基盤-不在: 依存スクリプト・定義のいずれかが見つかりません" >&2
  exit 2
fi

TARGET=""
RUN_DIR=""
KIND=""
DESIGN_ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --run) RUN_DIR="${2:-}"; shift 2 ;;
    --kind) KIND="${2:-}"; shift 2 ;;
    --design-root) DESIGN_ROOT="${2:-}"; shift 2 ;;
    *)
      if [ -z "$TARGET" ]; then
        TARGET="$1"; shift
      else
        usage_error
      fi
      ;;
  esac
done

if [ -z "$TARGET" ] || [ -z "$RUN_DIR" ] || [ -z "$KIND" ]; then
  usage_error
fi
[ -n "$DESIGN_ROOT" ] || DESIGN_ROOT="$TARGET"
if ! is_valid_kind "$KIND"; then
  echo "[FAIL] 種別-不正: ${KIND} は対象外です" >&2
  exit 2
fi

run_units "$TARGET" "$RUN_DIR" "$KIND" "$DESIGN_ROOT"
rrc=$?
if [ "$rrc" -eq 2 ]; then
  exit 2
fi

echo "合格 ${PASS_COUNT} 件 / 不合格 ${FAIL_COUNT} 件"
if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
