#!/usr/bin/env bash
# 横断確認事項質問票データ生成エンジン: unit-manifest群・permission-matrix.json・
# 画面詳細設計書由来の要確認事項JSON群から、人間確認待ちの4系統(推定名称・要手動確認・
# 権限未設定・要確認事項)を横断集約した confirmation-survey.json を決定的に導出する。
# ソースコードは読まない(拡張済みマニフェスト・データファイルのみを入力とする導出エンジン)。
#
# Usage: build-confirmation-survey-data.sh <output-json-path>
#          [--unit-manifest <path>]... [--permission-matrix <path>] [--unresolved-questions <path>]...
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
#   全引数省略可(0件入力で questions: [] を出力する)。
#
# 出力契約: <output-json-path> へ以下の構造を直接書き込む(スキーマ正本:
#   shared/references/manifest-schema-extensions.md「confirmation-survey.json」節。
#   同スキーマは shared/templates/matrix/confirmation-survey-template.html 内 JS が
#   参照するトップレベルキー・フィールド名と一致させている。二重管理・ドリフト禁止)。
#   - generatedAt: 現在時刻のUTC ISO8601
#   - dataSource: 指定された入力ファイルパスをスペース区切りで連結(0件なら空文字)
#   - questions[]: questionKey(連番禁止・内容要約キー規約に従う)・targetUnit・
#     question・evidence・answerTarget(常に空文字。ヒアリング回答取り込みの自動化は
#     対象外)を持つオブジェクトの配列。questionKey は
#     <unitKeyまたはscreenId>-業務名未確定 / -要手動確認 / -権限未設定 /
#     -要確認事項-<item要約スラッグ> の4系統。同一 questionKey が複数入力から
#     生じた場合は初出のみを残し重複除去する。

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
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/build-confirmation-survey-data-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  assert() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
      echo "  [PASS] $desc"
    else
      echo "  [FAIL] $desc" >&2
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
  assert "ケース1: dataSourceに指定した3ファイルパスが含まれる" \
    jq -e --arg um "$um1" --arg pm "$pm1" --arg uq "$uq1" \
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
  assert "ケース2: dataSourceは指定ファイルパスを保持する(0件は questions のみ)" \
    jq -e --arg um "$um2" '.dataSource | contains($um)' "$out2"

  # --- ケース3(補足): 全引数省略時は questions:[] かつ dataSource は空文字 ---
  local out3="$tmp/confirmation-survey-noargs.json"
  assert "ケース3: 全引数省略でも生成コマンドが成功" \
    bash "$script_path" "$out3"
  assert "ケース3: questionsが空配列・dataSourceが空文字" \
    jq -e '.questions == [] and .dataSource == ""' "$out3"

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
USAGE="Usage: build-confirmation-survey-data.sh <output-json-path> [--unit-manifest <path>]... [--permission-matrix <path>] [--unresolved-questions <path>]..."
OUTPUT_JSON="${1:?$USAGE}"
shift

UNIT_MANIFESTS=()
PERMISSION_MATRIX=""
UNRESOLVED_QUESTIONS=()
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

for f in "${UNIT_MANIFESTS[@]:-}" ${PERMISSION_MATRIX:+"$PERMISSION_MATRIX"} "${UNRESOLVED_QUESTIONS[@]:-}"; do
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

GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [ "${#ORDERED_INPUTS[@]}" -gt 0 ]; then
  DATA_SOURCE="$(printf '%s ' "${ORDERED_INPUTS[@]}")"
  DATA_SOURCE="${DATA_SOURCE% }"
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

QUESTION_BLOCKS_FILE="$(mktemp "${TMPDIR:-/tmp}/build-confirmation-survey-data-blocks.XXXXXX")"
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

# --- 結合 + questionKey重複除去(初出のみ残す。挿入順は保持する) ---
jq -n \
  --arg generatedAt "$GENERATED_AT" \
  --arg dataSource "$DATA_SOURCE" \
  --slurpfile blocks "$QUESTION_BLOCKS_FILE" \
  '
  def dedupe_by_key:
    reduce .[] as $x ([]; if (any(.[]; .questionKey == $x.questionKey)) then . else . + [$x] end);
  ($blocks | add // []) as $all
  | { generatedAt: $generatedAt,
      dataSource: $dataSource,
      questions: ($all | dedupe_by_key) }
  ' > "$OUTPUT_JSON"

rm -f "$QUESTION_BLOCKS_FILE"
trap - EXIT

echo "OK: wrote $OUTPUT_JSON" >&2
