#!/usr/bin/env bash
# 横断確認事項質問票データ生成エンジン: unit-manifest群・permission-matrix.json・
# 画面詳細設計書由来の要確認事項JSON群から、人間確認待ちの4系統(推定名称・要手動確認・
# 権限未設定・要確認事項)を横断集約した confirmation-survey.json を決定的に導出する。
# ソースコードは読まない(拡張済みマニフェスト・データファイルのみを入力とする導出エンジン)。
#
# Usage: build-confirmation-survey-data.sh <output-json-path>
#          [--unit-manifest <path>]... [--permission-matrix <path>]
#          [--unresolved-questions <path>]... [--confirmation-ledger <path>]...
#        build-confirmation-survey-data.sh --self-test
#
# 入力契約:
#   --unit-manifest <path>: 繰り返し指定可。各マニフェストの units[] を走査し、
#     nameConfidence == "inferred" の要素から「業務名未確定」、
#     kind == "unresolved" の要素から「要手動確認」の質問行を生成する。
#   --permission-matrix <path>: 省略可(0〜1個)。permission-matrix.json の screens[] を
#     走査し、permissions == null の要素から「権限未設定」の質問行を生成する。
#   --unresolved-questions <path>: 繰り返し指定可。各ファイルは
#     {"unitKey": "screen-xxx", "items": ["質問文1", "質問文2"]} 形式のJSON
#     (画面詳細設計書の要確認事項一覧を事前にJSON化したもの)。items毎に
#     「要確認事項」の質問行を生成する。
#   --confirmation-ledger <path>: 繰り返し指定可。各ファイルは
#     {"unitKey": "screen-xxx", "designDocument": "画面詳細設計書.md",
#      "items": [{"key": "内容要約キー", "question": "質問文", "status": "未確認",
#                  "answer": ""}]} 形式の要確認事項台帳。状態が「反映済み」「対象外」
#     以外の行を質問へ変換し、answerTargetを当該行のanswer欄へ対応づける。
#     unitKeyは空白だけでない文字列かつ入力台帳間で一意とする。
#   全引数省略可(0件入力で questions: [] を出力する)。
#
# 出力契約: <output-json-path> へ以下の構造を直接書き込む(スキーマ正本:
#   delivery-payload/references/manifest-schema-extensions.md「confirmation-survey.json」節。
#   同スキーマは delivery-payload/templates/matrix/confirmation-survey-template.html 内 JS が
#   参照するトップレベルキー・フィールド名と一致させている。二重管理・ドリフト禁止)。
#   - generatedAt: 現在時刻のUTC ISO8601
#   - dataSource: 指定された入力ファイルのbasenameを" + "で連結(0件なら空文字。
#     出力先環境に依存する絶対パスは含めない)
#   - questions[]: questionKey(連番禁止・内容要約キー規約に従う)・targetUnit・
#     question・evidence・answerTargetを持つオブジェクトの配列。台帳由来の行は
#     answerTargetが `<台帳ファイル名>#unitKey=<unitKey>&items[key=<キー>].answer` を指す。
#     unitKeyとキーはURIパーセント符号化する。
#     questionKey は
#     <unitKeyまたはscreenId>-業務名未確定 / -要手動確認 / -権限未設定 /
#     -要確認事項-<item要約スラッグ> の4系統。同一 questionKey が複数入力から
#     生じた場合は初出(挿入順で最初のもの)を代表として残し、他は代表へ集約する。
#     代表が2件以上を集約した場合、代表オブジェクトに mergedCount(集約件数)・
#     mergedQuestions(集約された全questionの配列)を追加する
#     (詳細: delivery-payload/references/manifest-schema-extensions.md「confirmation-survey.json」節)。

set -euo pipefail

# ---------------------------------------------------------------------------
# --self-test モード
# (1) 4系統混在フィクスチャで各系統の質問行が1件以上生成されること
# (2) 対象フィールドが全て「問題なし」のフィクスチャで questions が空配列になること
# を jq で検証する。
# ---------------------------------------------------------------------------
self_test() {
  local script_path="$0"
  local tmp rc=0
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/build-confirmation-survey-data-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' RETURN

  assert() {
    local desc="$1"
    shift
    if _gt_out1="$("$@" 2>&1)"; then
      echo "  [PASS] $desc"
    else
      echo "  [FAIL] $desc" >&2
      printf '%s\n' "$_gt_out1" | sed 's/^/    /' >&2
      rc=1
    fi
  }

  # --- ケース1: 4系統混在フィクスチャ ---
  local um1="$tmp/unit-manifest.json"
  jq -n '{
    units: [
      {unitKey: "batch-0042", kind: "batch", identifier: "daily-aggregate",
       unitNameGuess: "日次集計", nameConfidence: "inferred"},
      {unitKey: "batch-0099", kind: "unresolved", identifier: "unknown-batch",
       unitNameGuess: "不明バッチ", nameConfidence: "high"}
    ]
  }' > "$um1"

  local pm1="$tmp/permission-matrix.json"
  jq -n '{
    screens: [
      {screenId: "legacy-report", screenName: "レガシー帳票", route: "/legacy/report", permissions: null},
      {screenId: "home", screenName: "ホーム", route: "/", permissions: {"admin": true}}
    ]
  }' > "$pm1"

  local uq1="$tmp/unresolved-questions.json"
  jq -n '{
    unitKey: "screen-login",
    items: ["初回ログイン時のパスワード変更要否を確認してください"]
  }' > "$uq1"

  local out1="$tmp/confirmation-survey.json"
  assert "ケース1: 4系統混在フィクスチャで生成コマンドが成功" \
    bash "$script_path" "$out1" --unit-manifest "$um1" --permission-matrix "$pm1" --unresolved-questions "$uq1"

  assert "ケース1: 業務名未確定の質問行が1件以上生成される" \
    jq -e '[.questions[] | select(.questionKey | endswith("-業務名未確定"))] | length >= 1' "$out1"
  assert "ケース1: 業務名未確定の質問文に推定名を含む" \
    jq -e '.questions[] | select(.questionKey == "batch-0042-業務名未確定")
           | .targetUnit == "batch-0042" and (.question | contains("日次集計"))
             and (.evidence | contains("nameConfidence=inferred"))' "$out1"
  assert "ケース1: 要手動確認の質問行が1件以上生成される" \
    jq -e '[.questions[] | select(.questionKey | endswith("-要手動確認"))] | length >= 1' "$out1"
  assert "ケース1: 要手動確認の質問文にidentifierを含む" \
    jq -e '.questions[] | select(.questionKey == "batch-0099-要手動確認")
           | .targetUnit == "batch-0099" and (.question | contains("unknown-batch"))
             and (.evidence | contains("kind=unresolved"))' "$out1"
  assert "ケース1: 権限未設定の質問行が1件以上生成される" \
    jq -e '[.questions[] | select(.questionKey | endswith("-権限未設定"))] | length >= 1' "$out1"
  assert "ケース1: 権限未設定の質問文に画面名を含む" \
    jq -e '.questions[] | select(.questionKey == "legacy-report-権限未設定")
           | .targetUnit == "legacy-report" and (.question | contains("レガシー帳票"))
             and (.evidence | contains("permissions=null"))' "$out1"
  assert "ケース1: 要確認事項の質問行が1件以上生成される" \
    jq -e '[.questions[] | select(.questionKey | contains("-要確認事項-"))] | length >= 1' "$out1"
  assert "ケース1: 要確認事項の質問文はitem文字列そのまま" \
    jq -e '.questions[] | select(.questionKey | contains("-要確認事項-"))
           | .targetUnit == "screen-login"
             and .question == "初回ログイン時のパスワード変更要否を確認してください"
             and (.evidence | contains("要確認事項"))' "$out1"
  assert "ケース1: questionKeyに連番(末尾-数字)が使われていない" \
    bash -c "! jq -r '.questions[].questionKey' '$out1' | grep -Eq -- '-[0-9]+$'"
  assert "ケース1: answerTargetは全行空文字" \
    jq -e '[.questions[].answerTarget] | all(. == "")' "$out1"
  assert "ケース1: dataSourceに指定した3ファイルのbasenameが含まれる" \
    jq -e --arg um "$(basename "$um1")" --arg pm "$(basename "$pm1")" --arg uq "$(basename "$uq1")" \
      '.dataSource | contains($um) and contains($pm) and contains($uq)' "$out1"

  # --- ケース2: 欠落0件フィクスチャ(対象フィールドが全て問題なし) ---
  local um2="$tmp/unit-manifest-clean.json"
  jq -n '{
    units: [
      {unitKey: "batch-0042", kind: "batch", identifier: "daily-aggregate",
       unitNameGuess: "日次集計", nameConfidence: "high"},
      {unitKey: "batch-0099", kind: "batch", identifier: "monthly-report",
       unitNameGuess: "月次帳票", nameConfidence: "high"}
    ]
  }' > "$um2"

  local pm2="$tmp/permission-matrix-clean.json"
  jq -n '{
    screens: [
      {screenId: "legacy-report", screenName: "レガシー帳票", route: "/legacy/report", permissions: {"admin": true}},
      {screenId: "home", screenName: "ホーム", route: "/", permissions: {"admin": true}}
    ]
  }' > "$pm2"

  local uq2="$tmp/unresolved-questions-clean.json"
  jq -n '{unitKey: "screen-login", items: []}' > "$uq2"

  local out2="$tmp/confirmation-survey-clean.json"
  assert "ケース2: 欠落0件フィクスチャで生成コマンドが成功" \
    bash "$script_path" "$out2" --unit-manifest "$um2" --permission-matrix "$pm2" --unresolved-questions "$uq2"
  assert "ケース2: questionsが空配列" \
    jq -e '.questions == []' "$out2"
  assert "ケース2: dataSourceは指定ファイルのbasenameを保持する(0件は questions のみ)" \
    jq -e --arg um "$(basename "$um2")" '.dataSource | contains($um)' "$out2"

  # --- ケース3(補足): 全引数省略時は questions:[] かつ dataSource は空文字 ---
  local out3="$tmp/confirmation-survey-noargs.json"
  assert "ケース3: 全引数省略でも生成コマンドが成功" \
    bash "$script_path" "$out3"
  assert "ケース3: questionsが空配列・dataSourceが空文字" \
    jq -e '.questions == [] and .dataSource == ""' "$out3"

  # --- ケース4: 同一unitKey内で先頭16文字が一致する異なる要確認事項が
  #     questionKey衝突してもmergedCount/mergedQuestionsで欠落を検知可能なこと ---
  local uq4="$tmp/unresolved-questions-collision.json"
  jq -n '{
    unitKey: "screen-collision",
    items: [
      "この画面の権限設定について確認してください（詳細は別紙参照）",
      "この画面の権限設定について確認してください（実装後に再確認）",
      "別の項目についての確認事項です"
    ]
  }' > "$uq4"

  local out4="$tmp/confirmation-survey-collision.json"
  assert "ケース4: questionKey衝突フィクスチャで生成コマンドが成功" \
    bash "$script_path" "$out4" --unresolved-questions "$uq4"
  assert "ケース4: 衝突キーはquestions内に1件のみ残る" \
    jq -e '[.questions[] | select(.questionKey == "screen-collision-要確認事項-この画面の権限設定について確認し")] | length == 1' "$out4"
  assert "ケース4: 衝突した代表行にmergedCount=2が記録される" \
    jq -e '.questions[] | select(.questionKey == "screen-collision-要確認事項-この画面の権限設定について確認し") | .mergedCount == 2' "$out4"
  assert "ケース4: mergedQuestionsに衝突した2件の質問文が両方含まれる" \
    jq -e '.questions[] | select(.questionKey == "screen-collision-要確認事項-この画面の権限設定について確認し")
           | .mergedQuestions == [
               "この画面の権限設定について確認してください（詳細は別紙参照）",
               "この画面の権限設定について確認してください（実装後に再確認）"
             ]' "$out4"
  assert "ケース4: 衝突しなかった項目にはmergedCount/mergedQuestionsが付与されない" \
    jq -e '.questions[] | select(.question == "別の項目についての確認事項です")
           | has("mergedCount") == false and has("mergedQuestions") == false' "$out4"

  # --- ケース5: 出力-絶対パス不在(dataSourceに出力先環境の絶対パスが残らないこと) ---
  assert "ケース5: 出力-絶対パス不在(dataSourceに入力ファイルの格納先ディレクトリ($tmp)が含まれない)" \
    bash -c "! jq -r '.dataSource' '$out1' | grep -qF -- '$tmp'"
  assert "ケース5: 出力-絶対パス不在(dataSourceが/で始まる値を含まない)" \
    jq -e '.dataSource | test("^/") | not' "$out1"

  # --- ケース6: 台帳入力のanswerTarget生成と重複unitKey拒否 ---
  local ledger6_dir_a="$tmp/ledger-a"
  local ledger6_dir_b="$tmp/ledger-b"
  local ledger6_a="$ledger6_dir_a/要確認事項台帳.json"
  local ledger6_b="$ledger6_dir_b/要確認事項台帳.json"
  local out6="$tmp/confirmation-survey-ledger.json"
  local dup_out6="$tmp/confirmation-survey-ledger-duplicate.json"
  local dup_err6="$tmp/confirmation-survey-ledger-duplicate.err"
  local blank_ledger6="$tmp/要確認事項台帳-unitKey空白.json"
  local blank_out6="$tmp/confirmation-survey-ledger-blank-unit-key.json"
  local blank_err6="$tmp/confirmation-survey-ledger-blank-unit-key.err"
  local feff_ledger6="$tmp/要確認事項台帳-unitKey-feff.json"
  local feff_out6="$tmp/confirmation-survey-ledger-feff-unit-key.json"
  local feff_err6="$tmp/confirmation-survey-ledger-feff-unit-key.err"
  local padded_ledger6="$tmp/要確認事項台帳-unitKey前後空白.json"
  local padded_out6="$tmp/confirmation-survey-ledger-padded-unit-key.json"
  local line_ledger6_dir="$tmp/ledger-line"
  local newline_ledger6_dir="$tmp/ledger-line-newline"
  local line_ledger6="$line_ledger6_dir/要確認事項台帳.json"
  local newline_ledger6="$newline_ledger6_dir/要確認事項台帳.json"
  local line_out6="$tmp/confirmation-survey-ledger-line-unit-keys.json"
  mkdir -p "$ledger6_dir_a" "$ledger6_dir_b" "$line_ledger6_dir" "$newline_ledger6_dir"
  jq -n '{
    unitKey: "screen-ledger",
    designDocument: "画面詳細設計書.md",
    items: [{key: "permission-policy", question: "操作権限を確定してください",
             status: "未確認", answer: ""}]
  }' > "$ledger6_a"
  jq -n '{
    unitKey: "screen-ledger",
    designDocument: "画面詳細設計書.md",
    items: [{key: "permission-policy", question: "操作権限を確定してください",
             status: "未確認", answer: ""}]
  }' > "$ledger6_b"
  assert "ケース6: 単一台帳入力で生成コマンドが成功" \
    bash "$script_path" "$out6" --confirmation-ledger "$ledger6_a"
  assert "ケース6: unitKey付きの非空answerTargetが生成される" \
    jq -e '.questions[0].answerTarget
           == "要確認事項台帳.json#unitKey=screen-ledger&items[key=permission-policy].answer"' "$out6"
  local dup_rc6=0
  bash "$script_path" "$dup_out6" \
    --confirmation-ledger "$ledger6_a" --confirmation-ledger "$ledger6_b" \
    >/dev/null 2>"$dup_err6" || dup_rc6=$?
  assert "ケース6: 同じunitKeyの台帳2件を非0で拒否する" test "$dup_rc6" -ne 0
  assert "ケース6: 重複エラーにunitKeyを含む" grep -Fq 'unitKey=screen-ledger' "$dup_err6"
  assert "ケース6: 重複エラーに1件目の入力パスを含む" grep -Fq "$ledger6_a" "$dup_err6"
  assert "ケース6: 重複エラーに2件目の入力パスを含む" grep -Fq "$ledger6_b" "$dup_err6"
  jq -n '{
    unitKey: " \t ",
    designDocument: "画面詳細設計書.md",
    items: [{key: "permission-policy", question: "操作権限を確定してください",
             status: "未確認", answer: ""}]
  }' > "$blank_ledger6"
  local blank_rc6=0
  bash "$script_path" "$blank_out6" --confirmation-ledger "$blank_ledger6" \
    >/dev/null 2>"$blank_err6" || blank_rc6=$?
  assert "ケース6: 空白だけのunitKeyを非0で拒否する" test "$blank_rc6" -ne 0
  assert "ケース6: 空白だけのunitKey拒否でエラーを出す" \
    grep -Fq 'unitKeyは空でない文字列' "$blank_err6"
  jq -n '{
    unitKey: "\uFEFF",
    designDocument: "画面詳細設計書.md",
    items: [{key: "permission-policy", question: "操作権限を確定してください",
             status: "未確認", answer: ""}]
  }' > "$feff_ledger6"
  local feff_rc6=0
  bash "$script_path" "$feff_out6" --confirmation-ledger "$feff_ledger6" \
    >/dev/null 2>"$feff_err6" || feff_rc6=$?
  assert "ケース6: U+FEFFだけのunitKeyを非0で拒否する" test "$feff_rc6" -ne 0
  assert "ケース6: U+FEFFだけのunitKey拒否でエラーを出す" \
    grep -Fq 'unitKeyは空でない文字列' "$feff_err6"
  jq -n '{
    unitKey: " \t screen-valid \t ",
    designDocument: "画面詳細設計書.md",
    items: [{key: "permission-policy", question: "操作権限を確定してください",
             status: "未確認", answer: ""}]
  }' > "$padded_ledger6"
  assert "ケース6: 前後空白を含む有効unitKeyで生成コマンドが成功" \
    bash "$script_path" "$padded_out6" --confirmation-ledger "$padded_ledger6"
  assert "ケース6: 前後空白を含むunitKeyの元値をtargetUnitへ保持する" \
    jq -e --arg expected $' \t screen-valid \t ' '.questions[0].targetUnit == $expected' "$padded_out6"
  jq -n '{
    unitKey: "screen-line",
    designDocument: "画面詳細設計書.md",
    items: [{key: "permission-policy", question: "操作権限を確定してください",
             status: "未確認", answer: ""}]
  }' > "$line_ledger6"
  jq -n '{
    unitKey: "screen-line\n",
    designDocument: "画面詳細設計書.md",
    items: [{key: "permission-policy", question: "操作権限を確定してください",
             status: "未確認", answer: ""}]
  }' > "$newline_ledger6"
  assert "ケース6: 末尾改行だけ異なるunitKeyの台帳2件で生成コマンドが成功" \
    bash "$script_path" "$line_out6" \
      --confirmation-ledger "$line_ledger6" --confirmation-ledger "$newline_ledger6"
  assert "ケース6: 末尾改行だけ異なるunitKeyの元値とanswerTargetを損失なく保持する" \
    jq -e '
      ([.questions[] | select(.targetUnit == "screen-line")] | length) == 1
      and ([.questions[] | select(.targetUnit == "screen-line\n")] | length) == 1
      and ([.questions[].answerTarget]
           | index("要確認事項台帳.json#unitKey=screen-line&items[key=permission-policy].answer") != null)
      and ([.questions[].answerTarget]
           | index("要確認事項台帳.json#unitKey=screen-line%0A&items[key=permission-policy].answer") != null)
    ' "$line_out6"

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

# ---------------------------------------------------------------------------
# 引数パース
# ---------------------------------------------------------------------------
USAGE="Usage: build-confirmation-survey-data.sh <output-json-path> [--unit-manifest <path>]... [--permission-matrix <path>] [--unresolved-questions <path>]... [--confirmation-ledger <path>]..."
OUTPUT_JSON="${1:?$USAGE}"
shift

UNIT_MANIFESTS=()
PERMISSION_MATRIX=""
UNRESOLVED_QUESTIONS=()
CONFIRMATION_LEDGERS=()
ORDERED_INPUTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --unit-manifest)
      UNIT_MANIFESTS+=("${2:?$USAGE}")
      ORDERED_INPUTS+=("${2:?$USAGE}")
      shift 2
      ;;
    --permission-matrix)
      PERMISSION_MATRIX="${2:?$USAGE}"
      ORDERED_INPUTS+=("${2:?$USAGE}")
      shift 2
      ;;
    --unresolved-questions)
      UNRESOLVED_QUESTIONS+=("${2:?$USAGE}")
      ORDERED_INPUTS+=("${2:?$USAGE}")
      shift 2
      ;;
    --confirmation-ledger)
      CONFIRMATION_LEDGERS+=("${2:?$USAGE}")
      ORDERED_INPUTS+=("${2:?$USAGE}")
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      echo "$USAGE" >&2
      exit 1
      ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found in PATH" >&2
  exit 1
fi

for f in "${UNIT_MANIFESTS[@]:-}" ${PERMISSION_MATRIX:+"$PERMISSION_MATRIX"} "${UNRESOLVED_QUESTIONS[@]:-}" "${CONFIRMATION_LEDGERS[@]:-}"; do
  [ -z "$f" ] && continue
  if [ ! -f "$f" ]; then
    echo "ERROR: file not found: $f" >&2
    exit 1
  fi
  if ! jq empty "$f" >/dev/null 2>&1; then
    echo "ERROR: invalid JSON: $f" >&2
    exit 1
  fi
done

CONFIRMATION_LEDGER_UNIT_KEYS_B64=()
CONFIRMATION_LEDGER_UNIT_KEY_LABELS=()
CONFIRMATION_LEDGER_PATHS=()
for f in "${CONFIRMATION_LEDGERS[@]:-}"; do
  [ -z "$f" ] && continue
  if ! ledger_unit_key_b64="$(jq -er '
    if ((.unitKey | type) == "string" and (.unitKey | test("[^\\s\uFEFF]")))
    then (.unitKey | @base64)
    else error("unitKey must be a non-empty string")
    end
  ' "$f" 2>/dev/null)"; then
    echo "ERROR: 要確認事項台帳のunitKeyは空でない文字列でなければなりません: $f" >&2
    exit 1
  fi
  ledger_unit_key_label="$(jq -r '
    .unitKey
    | if test("[^A-Za-z0-9._:-]") then @json else . end
  ' "$f")"

  ledger_index=0
  while [ "$ledger_index" -lt "${#CONFIRMATION_LEDGER_UNIT_KEYS_B64[@]}" ]; do
    if [ "${CONFIRMATION_LEDGER_UNIT_KEYS_B64[$ledger_index]}" = "$ledger_unit_key_b64" ]; then
      echo "ERROR: 要確認事項台帳のunitKeyが重複しています: unitKey=$ledger_unit_key_label" >&2
      echo "  - path=${CONFIRMATION_LEDGER_PATHS[$ledger_index]} basename=$(basename "${CONFIRMATION_LEDGER_PATHS[$ledger_index]}") unitKey=${CONFIRMATION_LEDGER_UNIT_KEY_LABELS[$ledger_index]}" >&2
      echo "  - path=$f basename=$(basename "$f") unitKey=$ledger_unit_key_label" >&2
      exit 1
    fi
    ledger_index=$((ledger_index + 1))
  done
  CONFIRMATION_LEDGER_UNIT_KEYS_B64+=("$ledger_unit_key_b64")
  CONFIRMATION_LEDGER_UNIT_KEY_LABELS+=("$ledger_unit_key_label")
  CONFIRMATION_LEDGER_PATHS+=("$f")
done

GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [ "${#ORDERED_INPUTS[@]}" -gt 0 ]; then
  DATA_SOURCE_BASENAMES=()
  for f in "${ORDERED_INPUTS[@]}"; do
    DATA_SOURCE_BASENAMES+=("$(basename "$f")")
  done
  DATA_SOURCE="$(printf '%s + ' "${DATA_SOURCE_BASENAMES[@]}")"
  DATA_SOURCE="${DATA_SOURCE% + }"
else
  DATA_SOURCE=""
fi

# ---------------------------------------------------------------------------
# 質問行の抽出(系統ごとにファイル1件あたり1本のjq呼び出しで配列を出力し、
# 最後にまとめてスラープして結合・questionKey重複除去する)
# ---------------------------------------------------------------------------
QUESTION_KEY_SUFFIX_SLUG='
  def survey_slug:
    gsub("[\\s　、。，,.:：;；!！?？()（）\\[\\]【】/\\\\]"; "")
    | if length > 16 then .[0:16] else . end;
'

if ! QUESTION_BLOCKS_FILE="$(mktemp "${TMPDIR:-/tmp}/build-confirmation-survey-data-blocks.XXXXXX" 2>/dev/null)" || [ -z "$QUESTION_BLOCKS_FILE" ]; then
  echo "[UNKNOWN] ä¸æãã¡ã¤ã«ã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼" >&2
  exit 2
fi
trap 'rm -f "$QUESTION_BLOCKS_FILE"' EXIT

for f in "${UNIT_MANIFESTS[@]:-}"; do
  [ -z "$f" ] && continue
  jq -c --arg src "$(basename "$f")" '
    [ (.units // [])[]
      | select(.nameConfidence == "inferred")
      | { questionKey: (.unitKey + "-業務名未確定"),
          targetUnit: .unitKey,
          question: ("業務名を確定してください（現在の推定名: " + (.unitNameGuess // "") + "）"),
          evidence: ($src + ": nameConfidence=inferred"),
          answerTarget: "" }
    ] + [ (.units // [])[]
      | select(.kind == "unresolved")
      | { questionKey: (.unitKey + "-要手動確認"),
          targetUnit: .unitKey,
          question: ("対象の実体を確認してください（identifier: " + (.identifier // "") + "）"),
          evidence: ($src + ": kind=unresolved"),
          answerTarget: "" }
    ]
  ' "$f" >> "$QUESTION_BLOCKS_FILE"
done

if [ -n "$PERMISSION_MATRIX" ]; then
  jq -c --arg src "$(basename "$PERMISSION_MATRIX")" '
    [ (.screens // [])[]
      | select(.permissions == null)
      | { questionKey: (.screenId + "-権限未設定"),
          targetUnit: .screenId,
          question: ((.screenName // .screenId) + "のロール別アクセス可否を確定してください"),
          evidence: ($src + ": permissions=null"),
          answerTarget: "" }
    ]
  ' "$PERMISSION_MATRIX" >> "$QUESTION_BLOCKS_FILE"
fi

for f in "${UNRESOLVED_QUESTIONS[@]:-}"; do
  [ -z "$f" ] && continue
  jq -c --arg src "$(basename "$f")" "$QUESTION_KEY_SUFFIX_SLUG"'
    (.unitKey) as $uk
    | [ (.items // [])[]
        | . as $item
        | { questionKey: ($uk + "-要確認事項-" + ($item | survey_slug)),
            targetUnit: $uk,
            question: $item,
            evidence: ($src + ": 要確認事項"),
            answerTarget: "" }
      ]
  ' "$f" >> "$QUESTION_BLOCKS_FILE"
done

for f in "${CONFIRMATION_LEDGERS[@]:-}"; do
  [ -z "$f" ] && continue
  jq -c --arg src "$(basename "$f")" '
    (.unitKey) as $uk
    | ($uk | @uri) as $encodedUk
    | [ (.items // [])[]
        | select(.status != "反映済み" and .status != "対象外")
        | (.key | @uri) as $encodedKey
        | { questionKey: ($uk + "-要確認事項-" + .key),
            targetUnit: $uk,
            question: .question,
            evidence: ($src + ": 要確認事項台帳 status=" + .status),
            answerTarget: ($src + "#unitKey=" + $encodedUk + "&items[key=" + $encodedKey + "].answer") }
      ]
  ' "$f" >> "$QUESTION_BLOCKS_FILE"
done

# --- 結合 + questionKey重複除去(初出を代表として残す。挿入順は保持する。
#     同一questionKeyに2件以上が集約された場合は代表へmergedCount/mergedQuestionsを付与する。
#     非空answerTargetは代表へ引き継ぎ、異なる非空値が複数あれば異常終了する) ---
jq -n \
  --arg generatedAt "$GENERATED_AT" \
  --arg dataSource "$DATA_SOURCE" \
  --slurpfile blocks "$QUESTION_BLOCKS_FILE" \
  '
  def dedupe_by_key:
    reduce .[] as $x (
      {order: [], byKey: {}};
      ($x.questionKey) as $k
      | if (.byKey | has($k))
        then (.byKey[$k] += [$x])
        else (.order += [$k]) | (.byKey[$k] = [$x])
        end
    )
    | . as $acc
    | $acc.order
    | map($acc.byKey[.] as $group
          | ($group | map(.answerTarget) | map(select(. != "")) | unique) as $answerTargets
          | if ($answerTargets | length) > 1
            then error("同一questionKeyに異なるanswerTargetがあります: " + $group[0].questionKey)
            else ($group[0]
              + (if ($answerTargets | length) == 1
                 then {answerTarget: $answerTargets[0]}
                 else {}
                 end)
              + (if ($group | length) > 1
                 then {mergedCount: ($group | length), mergedQuestions: ($group | map(.question))}
                 else {}
                 end))
            end);
  ($blocks | add // []) as $all
  | { generatedAt: $generatedAt,
      dataSource: $dataSource,
      questions: ($all | dedupe_by_key) }
  ' > "$OUTPUT_JSON"

rm -f "$QUESTION_BLOCKS_FILE"
trap - EXIT

echo "OK: wrote $OUTPUT_JSON" >&2
