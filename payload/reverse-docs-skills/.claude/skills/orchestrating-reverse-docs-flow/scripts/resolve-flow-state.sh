#!/usr/bin/env bash
set -uo pipefail

# resolve-flow-state.sh — orchestrating-reverse-docs-flow の16状態判定を決定的に固定する
#
# 必要性: 改善課題 1-122 が指摘するとおり、SKILL.md の状態判定は成果物の実在確認を自然文の手順として
#   記述しただけで、判定の正しさを確認する手段がない。16状態の実在判定を1本のスクリプトに固定し、
#   標準出力の状態キー1行を決定的に返すことで、管理者の自己申告に代わる機械判定を提供する。
# 代替案を採用しなかった理由: SKILL.md本文への判定手順の直書きのままでは、判定ロジックが自然文に
#   埋もれて機械実行できず、リグレッションを自己テストで検知できない。他スキルの validate-*.sh /
#   check-*.sh と同様に独立スクリプト化し、--self-test で回帰検証できる形にした。
# 保守責任者: 人手（ユーザー）。contract.md の状態判定表（実在判定列）を変更した場合は、本スクリプトの
#   対応する check_* 関数を同時に更新する。
# 廃棄条件: orchestrating-reverse-docs-flow スキル自体が廃止された時、または状態判定をビルド基盤が
#   標準で提供するようになった時。
#
# 正本: ../references/contract.md の「状態判定表」（16状態・実在判定列）と、直後の「判定は次の順に
#   降りる判定フロー」節（1→16の降順）。本スクリプトはこの2箇所の記述をそのまま実行可能な形にする。
#   派生一覧（「派生一覧未生成（任意）」= メッセージ一覧・テスト観点表一覧）は SKILL.md 243行目が
#   明記するとおり16状態の判定フロー対象外のため、本スクリプトの対象にも含めない。
#
# 前提事実（実在確認が難しい判定条件の扱い）:
#   - アーキ未調査・共通未採録は「成果物の実在」に加えて機械ゲート（check-architecture-survey.sh /
#     check-common-docs.sh）の再実行が exit 1 かどうかも判定条件に含む。これらのゲートは実在する
#     target_repo_path のコード内容と突き合わせるため、target_repo_path が未指定の場合はゲートの
#     再実行をスキップし、実在確認のみで判定する（fail-open。ゲートスクリプト自体が無い環境でも
#     同様にスキップする）。
#   - 事実封印（seal-facts.sh verify）はfacts_dir単体で検証可能なため、target_repo_path の有無に
#     関わらず常に再実行する。
#   - サイト定義未生成の「サイトが2件以上」判定は、アーキテクチャ調査書 §10 の「サイト一覧」見出し
#     直後の Markdown 表（ヘッダ行・区切り行を除く本文行）の行数で数える。この抽出方法は
#     check-architecture-survey.sh の §10 検査と同じ発想（サイト一覧表の実在確認）を流用した本
#     スクリプト独自の簡易実装であり、contract.md 自体はこの抽出アルゴリズムまでは規定していない。
#   - 基準未確立/往復未検証/検証完了は、baseline_tag の実在確認に `git tag -l
#     "reverse-baseline/<scope>"` を用い（contract.md 86行目の実測例と同じコマンド）、往復検証の
#     最終判定は最終報告.md の「## 判定」直後の非空行（`references/report-format.md` の書式）を
#     PASS 前方一致で判定する。これらはいずれも machine-readable な既存書式を流用しており、本
#     スクリプト独自の新規スキーマを追加するものではない。
#   - ファイル単位未検証は対象ファイルの basename（--target-file）が未指定の場合、contract.md
#     260行目の「検証記録が1件も無い場合は着手前であり本状態を確定させず読み飛ばす」規定に従い、
#     常に非該当（false）として次状態へ読み飛ばす。
#   - 画面スコープの状態（9〜16）は screen_id の解決が前提。--screen-id 未指定かつ
#     screen-manifest.json からの自動解決にも失敗した場合、状態8までで確定しなければ「未判定」を返す
#     （画面スコープ外の状態1〜8がどの条件にも該当しなかった場合に限る決定不能ケース）。
#
# Usage:
#   resolve-flow-state.sh <output_dir> [<target_repo_path>] [--screen-id <ID>]
#                          [--verification-dir <DIR>] [--system <NAME>]
#                          [--reverse-worktree <DIR>] [--target-file <basename>]
#   resolve-flow-state.sh --self-test
#
# 標準出力: 状態キー1行（16状態いずれか、または「未判定」）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# shellcheck source=../../../../shared/scripts/output-layout.sh
. "$REPO_ROOT/shared/scripts/output-layout.sh"

KIND_LABEL() {
  output_layout_kind_label "$LAYOUT_JSON" "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# 引数解析
# ---------------------------------------------------------------------------
OUTPUT_DIR=""
TARGET_REPO_PATH=""
SCREEN_ID=""
VERIFICATION_DIR=""
SYSTEM_NAME=""
REVERSE_WORKTREE=""
TARGET_FILE_BASENAME=""

parse_args() {
  local positional_count=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --screen-id) SCREEN_ID="${2:-}"; shift 2 ;;
      --verification-dir) VERIFICATION_DIR="${2:-}"; shift 2 ;;
      --system) SYSTEM_NAME="${2:-}"; shift 2 ;;
      --reverse-worktree) REVERSE_WORKTREE="${2:-}"; shift 2 ;;
      --target-file) TARGET_FILE_BASENAME="${2:-}"; shift 2 ;;
      *)
        if [ "$positional_count" -eq 0 ]; then
          OUTPUT_DIR="$1"
        elif [ "$positional_count" -eq 1 ]; then
          TARGET_REPO_PATH="$1"
        fi
        positional_count=$((positional_count + 1))
        shift
        ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# 共通ヘルパー
# ---------------------------------------------------------------------------

# YAMLの単純なトップレベルキー配下から特定フィールドの値を1つ取り出す（フラットな2階層のみ対応）
yaml_field() {
  local file="$1" key="$2" field="$3"
  [ -f "$file" ] || return 0
  local in_block=0
  local val=""
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$in_block" = 1 ]; then
      case "$line" in
        " "*|$'\t'*)
          case "$line" in
            *"${field}:"*)
              val="${line#*"${field}:"}"
              val="$(printf '%s' "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')"
              break
              ;;
          esac
          ;;
        *)
          break
          ;;
      esac
    fi
    case "$line" in
      "${key}:") in_block=1 ;;
    esac
  done < "$file"
  printf '%s' "$val"
}

# アーキテクチャ調査書の §10 サイト一覧表の本文行数を数える
count_site_rows() {
  local doc="$1"
  [ -f "$doc" ] || { echo 0; return; }
  local phase=0 count=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$phase" in
      0)
        case "$line" in
          *"サイト一覧"*) phase=1 ;;
        esac
        ;;
      1)
        case "$line" in
          "|"*) phase=2 ;;  # ヘッダ行を検出（次が区切り行）
        esac
        ;;
      2)
        case "$line" in
          "|"*"---"*) phase=3 ;;
          "#"*) phase=4 ;;
        esac
        ;;
      3)
        case "$line" in
          "|"*) count=$((count + 1)) ;;
          "#"*) phase=4 ;;
          "") phase=4 ;;
        esac
        ;;
    esac
    [ "$phase" = 4 ] && break
  done < "$doc"
  echo "$count"
}

# 最終報告.md の「## 判定」直後の非空行を取り出す
extract_verdict() {
  local file="$1"
  [ -f "$file" ] || return 0
  local found=0
  local val=""
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$found" = 1 ]; then
      local trimmed
      trimmed="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      if [ -n "$trimmed" ]; then
        val="$trimmed"
        break
      fi
      continue
    fi
    case "$line" in
      "## 判定") found=1 ;;
    esac
  done < "$file"
  printf '%s' "$val"
}

resolve_default_screen_id() {
  local manifest="$OUTPUT_DIR/$(output_layout_get "$LAYOUT_JSON" screenManifest)"
  [ -f "$manifest" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -r '.screens[0].id // empty' "$manifest" 2>/dev/null
}

# ---------------------------------------------------------------------------
# 状態判定関数（0=この状態に該当する / 1=非該当・次状態へ）
# ---------------------------------------------------------------------------

check_arch_unsurveyed() {
  local doc="$OUTPUT_DIR/$(output_layout_get "$LAYOUT_JSON" surveyDoc)"
  [ -f "$doc" ] || return 0
  local gate="$REPO_ROOT/.claude/skills/surveying-architecture-for-reverse-docs/scripts/check-architecture-survey.sh"
  if [ -n "$TARGET_REPO_PATH" ] && [ -x "$gate" ]; then
    "$gate" "$doc" "$TARGET_REPO_PATH" >/dev/null 2>&1 || return 0
  fi
  return 1
}

check_list_ungenerated() {
  local excluded_json="$OUTPUT_DIR/$(output_layout_get "$LAYOUT_JSON" excludedKinds)"
  [ -f "$excluded_json" ] || return 0
  command -v jq >/dev/null 2>&1 || return 1
  local kind label html md
  for kind in $(jq -r '.presentKinds[]?' "$excluded_json" 2>/dev/null); do
    label="$(KIND_LABEL "$kind")"
    [ -n "$label" ] || continue
    html="$OUTPUT_DIR/$(output_layout_get "$LAYOUT_JSON" unitListHtml "$label")"
    [ -f "$html" ] || return 0
  done
  for label in $(jq -r '.excludedKinds[]?.label' "$excluded_json" 2>/dev/null); do
    md="$OUTPUT_DIR/$(output_layout_get "$LAYOUT_JSON" unitListAbsentMd "$label")"
    [ -f "$md" ] || return 0
  done
  return 1
}

common_doc_files() {
  local keys="commonDesignDoc messageDoc designDoc foundationDoc uiCommonDoc dataDesignDoc"
  local k out=""
  for k in $keys; do
    out="$out $(output_layout_get "$LAYOUT_JSON" "$k")"
  done
  printf '%s' "${out# }"
}

check_common_undocumented() {
  local f
  for f in $(common_doc_files); do
    [ -f "$OUTPUT_DIR/$f" ] || return 0
  done
  local gate="$REPO_ROOT/.claude/skills/generating-reverse-common-docs/scripts/check-common-docs.sh"
  if [ -n "$TARGET_REPO_PATH" ] && [ -x "$gate" ]; then
    "$gate" "$OUTPUT_DIR" "$TARGET_REPO_PATH" >/dev/null 2>&1 || return 0
  fi
  return 1
}

check_portal_ungenerated() {
  [ -f "$OUTPUT_DIR/index.html" ] && return 1
  return 0
}

check_site_def_missing() {
  local doc="$OUTPUT_DIR/$(output_layout_get "$LAYOUT_JSON" surveyDoc)"
  local rows
  rows="$(count_site_rows "$doc")"
  if [ "${rows:-0}" -ge 2 ] && [ ! -f "$OUTPUT_DIR/sites.json" ]; then
    return 0
  fi
  return 1
}

FOUNDATION_PAGES="技術スタック.html 画面遷移図.html ER図.html 環境構築手順.html リリースノート.html デザインシステム.html コンポーネント棚卸し.html アイコンカタログ.html"

check_foundation_pages_missing() {
  local p
  for p in $FOUNDATION_PAGES; do
    [ -f "$OUTPUT_DIR/$p" ] || return 0
  done
  return 1
}

check_state_transition_missing() {
  [ -f "$OUTPUT_DIR/状態遷移図.html" ] && return 1
  return 0
}

check_sequence_diagram_missing() {
  [ -n "$SCREEN_ID" ] || return 1
  [ -f "$OUTPUT_DIR/$SCREEN_UNIT_ROOT/screen-$SCREEN_ID/シーケンス図.html" ] && return 1
  return 0
}

check_facts_unsealed() {
  local latest
  latest="$(ls "$VERIFICATION_DIR/screen-$SCREEN_ID"/facts/*/facts.lock 2>/dev/null | sort | tail -1)"
  [ -n "$latest" ] || return 0
  local facts_dir
  facts_dir="$(dirname "$latest")"
  local seal_script="$REPO_ROOT/shared/scripts/seal-facts.sh"
  if [ -x "$seal_script" ]; then
    "$seal_script" verify "$facts_dir" >/dev/null 2>&1 || return 0
  fi
  return 1
}

check_basic_design_missing() {
  [ -f "$OUTPUT_DIR/$SCREEN_UNIT_ROOT/screen-$SCREEN_ID/基本設計/画面基本設計書.md" ] && return 1
  return 0
}

check_detail_design_missing() {
  [ -f "$OUTPUT_DIR/$SCREEN_UNIT_ROOT/screen-$SCREEN_ID/詳細設計/画面詳細設計書.md" ] && return 1
  return 0
}

check_screen_unlocked_missing() {
  local registry="$OUTPUT_DIR/$(output_layout_get "$LAYOUT_JSON" screenRegistry)"
  [ -f "$registry" ] || return 0
  local scope="${SYSTEM_NAME}-${SCREEN_ID}"
  local url
  url="$(yaml_field "$registry" "$scope" "verification_url")"
  case "$url" in
    ""|"未実施") return 0 ;;
  esac
  return 1
}

check_file_unit_unverified() {
  [ -n "$TARGET_FILE_BASENAME" ] || return 1
  local base_dir="$VERIFICATION_DIR/screen-$SCREEN_ID/単体-$TARGET_FILE_BASENAME"
  [ -d "$base_dir" ] || return 1
  local latest
  latest="$(find "$base_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -1)"
  [ -n "$latest" ] || return 1
  local instr="$latest/修正指示書.md"
  [ -f "$instr" ] || return 1
  if grep -q "NG なし" "$instr" 2>/dev/null; then
    return 1
  fi
  return 0
}

check_baseline_missing() {
  local repo="${REVERSE_WORKTREE:-$TARGET_REPO_PATH}"
  local scope="${SYSTEM_NAME}-${SCREEN_ID}"
  if [ -z "$repo" ] || [ ! -d "$repo/.git" ]; then
    return 0
  fi
  local tag
  tag="$(git -C "$repo" tag -l "reverse-baseline/${scope}" 2>/dev/null)"
  [ -n "$tag" ] && return 1
  return 0
}

latest_final_report() {
  find "$VERIFICATION_DIR/screen-$SCREEN_ID" -mindepth 2 -maxdepth 2 -name "最終報告.md" -not -path "*単体-*" 2>/dev/null | sort | tail -1
}

check_roundtrip_unverified() {
  local report
  report="$(latest_final_report)"
  [ -n "$report" ] || return 0
  local verdict
  verdict="$(extract_verdict "$report")"
  case "$verdict" in
    PASS*) return 1 ;;
    *) return 0 ;;
  esac
}

check_complete() {
  local report
  report="$(latest_final_report)"
  [ -n "$report" ] || return 1
  local verdict
  verdict="$(extract_verdict "$report")"
  case "$verdict" in
    PASS*) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# 判定本体（16状態を1→16の順で降りる。詳細は contract.md 265〜282行目）
# ---------------------------------------------------------------------------
resolve_state() {
  VERIFICATION_DIR="${VERIFICATION_DIR:-$(dirname "$OUTPUT_DIR")/verification}"
  if [ -z "$SCREEN_ID" ]; then
    SCREEN_ID="$(resolve_default_screen_id)"
  fi

  if check_arch_unsurveyed; then
    echo "アーキ未調査"; return
  elif check_list_ungenerated; then
    echo "一覧未生成"; return
  elif check_common_undocumented; then
    echo "共通未採録"; return
  elif check_portal_ungenerated; then
    echo "ポータル未生成"; return
  elif check_site_def_missing; then
    echo "サイト定義未生成"; return
  elif check_foundation_pages_missing; then
    echo "基盤ページ未生成（任意）"; return
  elif check_state_transition_missing; then
    echo "状態遷移図未生成（任意）"; return
  elif check_sequence_diagram_missing; then
    echo "シーケンス図未生成（任意）"; return
  elif [ -z "$SCREEN_ID" ]; then
    echo "未判定"; return
  elif check_facts_unsealed; then
    echo "事実未封印"; return
  elif check_basic_design_missing; then
    echo "基本設計未著述"; return
  elif check_detail_design_missing; then
    echo "設計書未著述"; return
  elif check_screen_unlocked_missing; then
    echo "画面未開通"; return
  elif check_file_unit_unverified; then
    echo "ファイル単位未検証"; return
  elif check_baseline_missing; then
    echo "基準未確立"; return
  elif check_roundtrip_unverified; then
    echo "往復未検証"; return
  elif check_complete; then
    echo "検証完了"; return
  else
    echo "未判定"; return
  fi
}

# ---------------------------------------------------------------------------
# self-test: 16状態それぞれの合成フィクスチャ + 未判定フィクスチャの計17ケース
# ---------------------------------------------------------------------------
self_test() {
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/resolve-flow-state-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  LAYOUT_JSON="$(resolve_output_layout "")" || return 1
  SCREEN_UNIT_ROOT="$(output_layout_get "$LAYOUT_JSON" screenUnitRoot)" || return 1

  local pass=0 fail=0
  local docs="$tmp/docs"
  local verification="$tmp/verification"
  SYSTEM_NAME="demo"
  SCREEN_ID_FIXED="S001"
  local scope="${SYSTEM_NAME}-${SCREEN_ID_FIXED}"

  assert_state() {
    local expected="$1" label="$2"
    OUTPUT_DIR="$docs"
    TARGET_REPO_PATH=""
    SCREEN_ID="$SCREEN_ID_FIXED"
    VERIFICATION_DIR="$verification"
    # REVERSE_WORKTREE・TARGET_FILE_BASENAME は呼び出し側が状態13・状態15以降で
    # 個別に設定するため、ここではリセットしない。
    local got
    got="$(resolve_state)"
    if [ "$got" = "$expected" ]; then
      echo "PASS: ${label}（${got}）"; pass=$((pass + 1))
    else
      echo "FAIL: ${label}（期待=${expected} 実測=${got}）"; fail=$((fail + 1))
    fi
  }

  mkdir -p "$docs" "$verification"

  # 状態1: アーキ未調査（何も無い）
  assert_state "アーキ未調査" "状態1 アーキ未調査"

  # 状態2: 一覧未生成（アーキ調査書のみ追加）
  mkdir -p "$docs/プロジェクト共通"
  cat > "$docs/プロジェクト共通/アーキテクチャ調査書.md" <<'MD'
# アーキテクチャ調査書

## §10 プロジェクト形態

プロジェクト形態: モノレポ

### サイト一覧

| サイトキー | ルートディレクトリ |
|---|---|
| main | apps/main |
| admin | apps/admin |
MD
  assert_state "一覧未生成" "状態2 一覧未生成"

  # 状態3: 共通未採録（excluded-kinds.json + 画面一覧HTMLを追加）
  mkdir -p "$docs/一覧/画面一覧" "$docs/一覧/API一覧" "$docs/一覧/テーブル一覧" "$docs/一覧/バッチ一覧" "$docs/一覧/帳票一覧" "$docs/一覧/外部連携一覧"
  cat > "$docs/一覧/excluded-kinds.json" <<'JSON'
{
  "generatedAt": "2026-07-31T00:00:00Z",
  "surveyDocPath": "プロジェクト共通/アーキテクチャ調査書.md",
  "allKinds": ["screen", "api", "table", "batch", "report", "external"],
  "presentKinds": ["screen"],
  "excludedKinds": [
    { "kind": "api", "label": "API", "reason": "実在しない" },
    { "kind": "table", "label": "テーブル", "reason": "実在しない" },
    { "kind": "batch", "label": "バッチ", "reason": "実在しない" },
    { "kind": "report", "label": "帳票", "reason": "実在しない" },
    { "kind": "external", "label": "外部連携", "reason": "実在しない" }
  ]
}
JSON
  : > "$docs/一覧/画面一覧/画面一覧.html"
  : > "$docs/一覧/API一覧（該当なし）.md"
  : > "$docs/一覧/テーブル一覧（該当なし）.md"
  : > "$docs/一覧/バッチ一覧（該当なし）.md"
  : > "$docs/一覧/帳票一覧（該当なし）.md"
  : > "$docs/一覧/外部連携一覧（該当なし）.md"
  assert_state "共通未採録" "状態3 共通未採録"

  # 状態4: ポータル未生成（6文書を追加）
  : > "$docs/プロジェクト共通/共通設計書.md"
  : > "$docs/プロジェクト共通/メッセージ定義書.md"
  : > "$docs/プロジェクト共通/DESIGN.md"
  : > "$docs/プロジェクト共通/基盤設計.md"
  : > "$docs/プロジェクト共通/UI共通設計.md"
  : > "$docs/プロジェクト共通/データ設計.md"
  assert_state "ポータル未生成" "状態4 ポータル未生成"

  # 状態5: サイト定義未生成（index.htmlを追加。§10は2サイト記載済みでsites.json不在）
  : > "$docs/index.html"
  assert_state "サイト定義未生成" "状態5 サイト定義未生成"

  # 状態6: 基盤ページ未生成（任意）（sites.jsonを追加）
  : > "$docs/sites.json"
  assert_state "基盤ページ未生成（任意）" "状態6 基盤ページ未生成（任意）"

  # 状態7: 状態遷移図未生成（任意）（基盤ページ9枚を追加）
  local p
  for p in $FOUNDATION_PAGES; do : > "$docs/$p"; done
  assert_state "状態遷移図未生成（任意）" "状態7 状態遷移図未生成（任意）"

  # 状態8: シーケンス図未生成（任意）（状態遷移図.htmlを追加）
  : > "$docs/状態遷移図.html"
  assert_state "シーケンス図未生成（任意）" "状態8 シーケンス図未生成（任意）"

  # 状態9: 事実未封印（シーケンス図.htmlを追加）
  mkdir -p "$docs/$SCREEN_UNIT_ROOT/screen-$SCREEN_ID_FIXED"
  : > "$docs/$SCREEN_UNIT_ROOT/screen-$SCREEN_ID_FIXED/シーケンス図.html"
  assert_state "事実未封印" "状態9 事実未封印"

  # 状態10: 基本設計未著述（factsを実際にseal-facts.shで封印する）
  local facts_dir="$verification/screen-$SCREEN_ID_FIXED/facts/extract-1"
  mkdir -p "$facts_dir"
  cat > "$facts_dir/facts.yml" <<'YML'
screen_id: S001
key: value
YML
  bash "$REPO_ROOT/shared/scripts/seal-facts.sh" seal "$facts_dir" >/dev/null 2>&1
  assert_state "基本設計未著述" "状態10 基本設計未著述"

  # 状態11: 設計書未著述（画面基本設計書.mdを追加）
  mkdir -p "$docs/$SCREEN_UNIT_ROOT/screen-$SCREEN_ID_FIXED/基本設計"
  : > "$docs/$SCREEN_UNIT_ROOT/screen-$SCREEN_ID_FIXED/基本設計/画面基本設計書.md"
  assert_state "設計書未著述" "状態11 設計書未著述"

  # 状態12: 画面未開通（画面詳細設計書.mdを追加）
  mkdir -p "$docs/$SCREEN_UNIT_ROOT/screen-$SCREEN_ID_FIXED/詳細設計"
  : > "$docs/$SCREEN_UNIT_ROOT/screen-$SCREEN_ID_FIXED/詳細設計/画面詳細設計書.md"
  assert_state "画面未開通" "状態12 画面未開通"

  # 状態13: ファイル単位未検証（画面レジストリにverification_urlを記帳。--target-fileを指定してNG一覧ありの記録を追加）
  cat > "$docs/一覧/reverse-screen-registry.yml" <<YML
${scope}:
  source_ref: abc123
  verification_url: http://localhost:3000/target
  design_doc_path: 画面/screen-$SCREEN_ID_FIXED/詳細設計/画面詳細設計書.md
  status: authored
YML
  local unit_dir="$verification/screen-$SCREEN_ID_FIXED/単体-Foo.tsx/20260731-000000"
  mkdir -p "$unit_dir"
  cat > "$unit_dir/修正指示書.md" <<'MD'
# 修正指示書

## 対象設計書パス

画面/screen-S001/詳細設計/画面詳細設計書.md

## NG 一覧

| 失敗クラス | 帰着（役割・既定§） | 修正指示 | 根拠となる証跡パス |
|---|---|---|---|
| 執筆規律不足 | §15 | 契約を明記する | dummy |
MD
  TARGET_FILE_BASENAME="Foo.tsx"
  assert_state "ファイル単位未検証" "状態13 ファイル単位未検証"
  TARGET_FILE_BASENAME=""

  # 状態14: 基準未確立（--target-fileを外し、baseline tagはまだ無い状態）
  assert_state "基準未確立" "状態14 基準未確立"

  # 状態15: 往復未検証（git worktreeを用意しbaseline_tagを打つが最終報告は未生成）
  local worktree="$tmp/worktree"
  mkdir -p "$worktree"
  git -C "$worktree" init -q
  git -C "$worktree" -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m init
  git -C "$worktree" tag "reverse-baseline/${scope}"
  REVERSE_WORKTREE="$worktree"
  assert_state "往復未検証" "状態15 往復未検証"

  # 状態16: 検証完了（最終報告.mdにPASSを記録）
  local report_dir="$verification/screen-$SCREEN_ID_FIXED/20260731-000000"
  mkdir -p "$report_dir"
  cat > "$report_dir/最終報告.md" <<'MD'
# 最終報告

## 判定

PASS

## 著述スコープ

完全著述
MD
  assert_state "検証完了" "状態16 検証完了"

  # 未判定: screen_idが解決できない構成（状態1〜8完了・画面一覧マニフェストも--screen-idも無し）
  local undetermined_docs="$tmp/docs-undetermined"
  mkdir -p "$undetermined_docs/プロジェクト共通"
  cp "$docs/プロジェクト共通/アーキテクチャ調査書.md" "$undetermined_docs/プロジェクト共通/アーキテクチャ調査書.md"
  mkdir -p "$undetermined_docs/一覧/画面一覧" "$undetermined_docs/一覧/API一覧" "$undetermined_docs/一覧/テーブル一覧" "$undetermined_docs/一覧/バッチ一覧" "$undetermined_docs/一覧/帳票一覧" "$undetermined_docs/一覧/外部連携一覧"
  cp "$docs/一覧/excluded-kinds.json" "$undetermined_docs/一覧/excluded-kinds.json"
  : > "$undetermined_docs/一覧/画面一覧/画面一覧.html"
  : > "$undetermined_docs/一覧/API一覧（該当なし）.md"
  : > "$undetermined_docs/一覧/テーブル一覧（該当なし）.md"
  : > "$undetermined_docs/一覧/バッチ一覧（該当なし）.md"
  : > "$undetermined_docs/一覧/帳票一覧（該当なし）.md"
  : > "$undetermined_docs/一覧/外部連携一覧（該当なし）.md"
  mkdir -p "$undetermined_docs/プロジェクト共通"
  : > "$undetermined_docs/プロジェクト共通/共通設計書.md"
  : > "$undetermined_docs/プロジェクト共通/メッセージ定義書.md"
  : > "$undetermined_docs/プロジェクト共通/DESIGN.md"
  : > "$undetermined_docs/プロジェクト共通/基盤設計.md"
  : > "$undetermined_docs/プロジェクト共通/UI共通設計.md"
  : > "$undetermined_docs/プロジェクト共通/データ設計.md"
  : > "$undetermined_docs/index.html"
  : > "$undetermined_docs/sites.json"
  for p in $FOUNDATION_PAGES; do : > "$undetermined_docs/$p"; done
  : > "$undetermined_docs/状態遷移図.html"
  mkdir -p "$undetermined_docs/$SCREEN_UNIT_ROOT/screen-XXX"
  : > "$undetermined_docs/$SCREEN_UNIT_ROOT/screen-XXX/シーケンス図.html"
  OUTPUT_DIR="$undetermined_docs"
  TARGET_REPO_PATH=""
  SCREEN_ID=""
  VERIFICATION_DIR="$tmp/verification-undetermined"
  REVERSE_WORKTREE=""
  TARGET_FILE_BASENAME=""
  mkdir -p "$VERIFICATION_DIR"
  local got
  got="$(resolve_state)"
  if [ "$got" = "未判定" ]; then
    echo "PASS: 未判定 screen_id解決不能で未判定（${got}）"; pass=$((pass + 1))
  else
    echo "FAIL: 未判定 screen_id解決不能で未判定（期待=未判定 実測=${got}）"; fail=$((fail + 1))
  fi

  # screenUnitRoot上書き: 状態8〜12の画面単位文書検査は上書きrootだけを参照する
  local custom_docs="$tmp/docs-custom-root"
  mkdir -p "$custom_docs/画面/screen-$SCREEN_ID_FIXED/基本設計" \
    "$custom_docs/画面/screen-$SCREEN_ID_FIXED/詳細設計" \
    "$custom_docs/スクリーン/screen-$SCREEN_ID_FIXED/基本設計" \
    "$custom_docs/スクリーン/screen-$SCREEN_ID_FIXED/詳細設計"
  cat > "$custom_docs/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "screenUnitRoot": "スクリーン" } }
JSON
  : > "$custom_docs/画面/screen-$SCREEN_ID_FIXED/シーケンス図.html"
  : > "$custom_docs/画面/screen-$SCREEN_ID_FIXED/基本設計/画面基本設計書.md"
  : > "$custom_docs/画面/screen-$SCREEN_ID_FIXED/詳細設計/画面詳細設計書.md"
  OUTPUT_DIR="$custom_docs"
  SCREEN_ID="$SCREEN_ID_FIXED"
  LAYOUT_JSON="$(resolve_output_layout "$OUTPUT_DIR")" || return 1
  SCREEN_UNIT_ROOT="$(output_layout_get "$LAYOUT_JSON" screenUnitRoot)" || return 1
  if check_sequence_diagram_missing && check_basic_design_missing && check_detail_design_missing; then
    : > "$custom_docs/スクリーン/screen-$SCREEN_ID_FIXED/シーケンス図.html"
    : > "$custom_docs/スクリーン/screen-$SCREEN_ID_FIXED/基本設計/画面基本設計書.md"
    : > "$custom_docs/スクリーン/screen-$SCREEN_ID_FIXED/詳細設計/画面詳細設計書.md"
    if ! check_sequence_diagram_missing && ! check_basic_design_missing && ! check_detail_design_missing; then
      echo "PASS: screenUnitRoot上書きだけを状態検査し既定rootのdecoyを除外"; pass=$((pass + 1))
    else
      echo "FAIL: screenUnitRoot上書きの状態検査が実在文書を認識しない"; fail=$((fail + 1))
    fi
  else
    echo "FAIL: screenUnitRoot上書きの状態検査が既定rootのdecoyを読み込んだ"; fail=$((fail + 1))
  fi

  echo "self-test: $pass PASS, $fail FAIL"
  if [ "$fail" -eq 0 ]; then return 0; else return 1; fi
}

# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

if [ $# -lt 1 ]; then
  echo "使い方: $(basename "$0") <output_dir> [<target_repo_path>] [--screen-id <ID>] [--verification-dir <DIR>] [--system <NAME>] [--reverse-worktree <DIR>] [--target-file <basename>]" >&2
  echo "        $(basename "$0") --self-test" >&2
  exit 1
fi

parse_args "$@"

if [ ! -d "$OUTPUT_DIR" ]; then
  echo "ERROR: output_dir が存在しません: $OUTPUT_DIR" >&2
  exit 1
fi

LAYOUT_JSON="$(resolve_output_layout "$OUTPUT_DIR")" || exit 1
SCREEN_UNIT_ROOT="$(output_layout_get "$LAYOUT_JSON" screenUnitRoot)" || exit 1

resolve_state
