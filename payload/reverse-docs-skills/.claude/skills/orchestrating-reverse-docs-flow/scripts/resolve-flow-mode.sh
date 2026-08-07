#!/usr/bin/env bash
# resolve-flow-mode.sh — 統括スキルの入口モード（setup-only / reverse-full / reverse-degraded）を判定する
#
# 必要性: `docs/AI駆動開発セットアップ構想.md` Phase B（統括-モード分岐）は、コードを持たない
#   リポジトリ・画面を持たないリポジトリが入口から辿れない問題への対処として3モード分岐を求める。
#   判定は自然文の自己申告ではなく、成果物の実在確認に基づく機械判定として固定する必要がある。
# 代替案を採用しなかった理由: 新しい種別判定基盤を作ると、既に surveying-architecture-for-reverse-docs
#   が持つ unit_kinds_present（画面等6種別の実在判定）と二重の判定基準が生まれる。本スクリプトは
#   既存資産（excluded-kinds.json の presentKinds、§10 プロジェクト形態の記法）を優先的に読み、
#   それが未生成の場合だけ対象リポジトリを直接走査する。
# 保守責任者: 人手（ユーザー）。判定材料（既存資産のパス・走査対象拡張子・画面指標パターン）を
#   変更した場合は本スクリプトと --self-test を同時に更新する。
# 廃棄条件: orchestrating-reverse-docs-flow の入口モード分岐が別基盤へ置き換えられた時。
#
# Usage:
#   resolve-flow-mode.sh <対象リポジトリルート> [--site <サブプロジェクトのパス>] [--output-dir <output_dir>]
#   resolve-flow-mode.sh --self-test
#
# 標準出力: JSON 1件（mode・reason・evidence・sites）
#
# 判定の材料（優先順）:
#   1. --output-dir が指定され、`<output_dir>/一覧/excluded-kinds.json` が実在する場合、
#      presentKinds に "screen" が含まれるかで画面の有無を判定する（surveying-architecture-for-reverse-docs
#      が返す unit_kinds_present をそのまま永続化した値）。
#   2. --output-dir が指定され、`<output_dir>/プロジェクト共通/アーキテクチャ調査書.md` が実在し
#      check-architecture-survey.sh のゲートを通る場合、§10 プロジェクト形態の記法（「単独プロジェクト」/
#      「モノレポ」）とサイト一覧表を読み、サブプロジェクトの分割に使う。
#   3. 上記が未生成の場合、対象リポジトリを直接走査する。コードの有無はソースファイル拡張子の実在、
#      画面の有無は pages/views/screens/routes/templates ディレクトリ・ルーティング定義ファイル名・
#      ルーティングAPI呼び出しの検出で判定する。モノレポの分割は package.json の workspaces 宣言を使う
#      （宣言が無ければ単独プロジェクトとして扱う）。
#
# macOS bash 3.2 互換を意識する（mapfile / declare -A 不使用）。ただし find|grep の終了コードで
# set -e が誤爆する経路が多いため、本スクリプトは set -e を使わず set -uo pipefail のみを使う。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

usage() {
  echo "使い方: $(basename "$0") <対象リポジトリルート> [--site <サブプロジェクトのパス>] [--output-dir <output_dir>]" >&2
  echo "        $(basename "$0") --self-test" >&2
}

# ---------------------------------------------------------------------------
# 共通ヘルパー
# ---------------------------------------------------------------------------

# 相対パスを絶対パスへ解決する（base 指定時はそこを起点に結合する）
abs_path() {
  local p="$1" base="${2:-}"
  case "$p" in
    /*) : ;;
    *) [ -n "$base" ] && p="$base/$p" ;;
  esac
  if [ -d "$p" ]; then
    (cd "$p" 2>/dev/null && pwd)
  else
    printf '%s' "$p"
  fi
}

# 対象範囲配下のソースファイル数を数える（依存物・ビルド生成物のディレクトリは除外）
count_source_files() {
  local root="$1"
  find "$root" \
    \( -name node_modules -o -name .git -o -name vendor -o -name dist -o -name build \
       -o -name .venv -o -name venv -o -name target -o -name __pycache__ -o -name .next \
       -o -name .nuxt -o -name coverage \) -prune -o \
    -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.mjs' \
       -o -name '*.cjs' -o -name '*.py' -o -name '*.rb' -o -name '*.go' -o -name '*.java' \
       -o -name '*.php' -o -name '*.cs' \) \
    -print 2>/dev/null | wc -l | tr -d ' '
}

# 画面に相当する実体（ルーティング定義・画面コンポーネント・テンプレート）の候補ファイルを列挙する
screen_indicator_files() {
  local root="$1"

  # (a) 画面系ディレクトリ名の直下にあるファイル
  find "$root" \
    \( -name node_modules -o -name .git -o -name vendor -o -name dist -o -name build \) -prune -o \
    -type d \( -name pages -o -name views -o -name screens -o -name routes -o -name templates \) -print 2>/dev/null \
    | while IFS= read -r d; do find "$d" -type f 2>/dev/null; done

  # (b) ルーティング定義らしきファイル名
  find "$root" \
    \( -name node_modules -o -name .git -o -name vendor -o -name dist -o -name build \) -prune -o \
    -type f \( -iname '*route*.ts' -o -iname '*route*.tsx' -o -iname '*route*.js' -o -iname '*route*.jsx' \
       -o -iname '*router*.ts' -o -iname '*router*.js' -o -iname 'urls.py' -o -iname 'routes.rb' \) -print 2>/dev/null

  # (c) ルーティングAPI呼び出しを含むファイル
  find "$root" \
    \( -name node_modules -o -name .git -o -name vendor -o -name dist -o -name build \) -prune -o \
    -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.py' -o -name '*.rb' \) -print 2>/dev/null \
    | while IFS= read -r f; do
        grep -lE '<Route|createBrowserRouter|useRoutes\(|@app\.route\(|urlpatterns|resources :|RouterModule' "$f" 2>/dev/null
      done
}

count_screen_indicators() {
  local root="$1"
  screen_indicator_files "$root" 2>/dev/null | sed '/^$/d' | sort -u | wc -l | tr -d ' '
}

# アーキテクチャ調査書 §10 の「プロジェクト形態」セルを読む
extract_project_form() {
  local doc="$1"
  [ -f "$doc" ] || { printf ''; return 0; }
  local line
  line="$(grep -E '^\|[^|]*プロジェクト形態' "$doc" 2>/dev/null | head -1)"
  case "$line" in
    *モノレポ*) printf 'monorepo' ;;
    *単独プロジェクト*) printf 'single' ;;
    *) printf '' ;;
  esac
}

# アーキテクチャ調査書 §10 の「### サイト一覧」表本文を "サイトキー|ルートディレクトリ" で列挙する
extract_site_table() {
  local doc="$1"
  [ -f "$doc" ] || return 0
  local phase=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$phase" in
      0) case "$line" in *"サイト一覧"*) phase=1 ;; esac ;;
      1) case "$line" in "|"*) phase=2 ;; esac ;;
      2)
        case "$line" in
          "|"*"---"*) phase=3 ;;
          "#"*) phase=4 ;;
        esac
        ;;
      3)
        case "$line" in
          "|"*)
            local key root
            key="$(printf '%s' "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}' | sed 's/^`//; s/`$//')"
            root="$(printf '%s' "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$4); print $4}' | sed 's/^`//; s/`$//')"
            [ -n "$key" ] && printf '%s|%s\n' "$key" "$root"
            ;;
          "#"*) phase=4 ;;
          "") phase=4 ;;
        esac
        ;;
    esac
    [ "$phase" = 4 ] && break
  done < "$doc"
}

# 既存資産（アーキテクチャ調査書）からサイト一覧を得る。モノレポでない・未生成・ゲート不合格なら空を返す
sites_from_survey() {
  local output_dir="$1" repo="$2"
  [ -n "$output_dir" ] || return 0
  local survey_doc="$output_dir/プロジェクト共通/アーキテクチャ調査書.md"
  [ -f "$survey_doc" ] || return 0
  local gate
  gate="$(cd "$SCRIPT_DIR/../../../.." && pwd)/.claude/skills/surveying-architecture-for-reverse-docs/scripts/check-architecture-survey.sh"
  [ -x "$gate" ] || return 0
  "$gate" "$survey_doc" "$repo" >/dev/null 2>&1 || return 0
  [ "$(extract_project_form "$survey_doc")" = "monorepo" ] || return 0
  extract_site_table "$survey_doc"
}

# package.json の workspaces 宣言からサブプロジェクトの相対パスを列挙する（"path|path" 形式）
# 対応するのは workspaces が文字列配列、または {packages:[...]} のオブジェクトの場合のみ。
# パターンは「<parent>/*」（parent 配下の全ディレクトリへ展開）と、glob を含まない直接指定のみ扱う。
detect_workspaces_sites() {
  local root="$1"
  local pkg="$root/package.json"
  [ -f "$pkg" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local patterns
  patterns="$(jq -r '
    .workspaces? as $w
    | if ($w | type) == "array" then $w[]
      elif ($w | type) == "object" then (($w.packages // [])[])
      else empty end
  ' "$pkg" 2>/dev/null)"
  [ -n "$patterns" ] || return 0
  local pat parent d rel
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    case "$pat" in
      */\*)
        parent="${pat%/*}"
        if [ -d "$root/$parent" ]; then
          find "$root/$parent" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while IFS= read -r d; do
            rel="${d#"$root"/}"
            printf '%s|%s\n' "$rel" "$rel"
          done
        fi
        ;;
      *)
        if [ -d "$root/$pat" ]; then
          printf '%s|%s\n' "$pat" "$pat"
        fi
        ;;
    esac
  done <<PATEND
$patterns
PATEND
}

# ---------------------------------------------------------------------------
# モード判定本体
# ---------------------------------------------------------------------------
# 結果は MODE_RESULT_* グローバル変数へ格納する（jqでのJSON組み立てを呼び出し側に委ねるため）
determine_mode_for_scope() {
  local root="$1" output_dir="$2" form_label="$3"
  local code_count screen_count screen_present screen_source mode reason

  code_count="$(count_source_files "$root")"
  screen_count="$(count_screen_indicators "$root")"
  screen_source="ソース走査（pages/views/screens/routes/templatesディレクトリ・ルーティング定義ファイル名・ルーティングAPI呼び出しの検出）"
  if [ "${screen_count:-0}" -gt 0 ]; then screen_present=1; else screen_present=0; fi

  if [ -n "$output_dir" ]; then
    local excluded_json="$output_dir/一覧/excluded-kinds.json"
    if [ -f "$excluded_json" ] && command -v jq >/dev/null 2>&1; then
      if jq -e '((.presentKinds // []) | index("screen")) != null' "$excluded_json" >/dev/null 2>&1; then
        screen_present=1
      else
        screen_present=0
      fi
      screen_source="既存資産 excluded-kinds.json の presentKinds"
    fi
  fi

  if [ "${code_count:-0}" -eq 0 ]; then
    mode="setup-only"
    reason="ソースファイルが0件のため"
  elif [ "$screen_present" -eq 1 ]; then
    mode="reverse-full"
    reason="ソースファイル${code_count}件と画面に相当する実体を検出したため（画面判定根拠: ${screen_source}）"
  else
    mode="reverse-degraded"
    reason="ソースファイル${code_count}件はあるが画面に相当する実体を検出できなかったため（画面判定根拠: ${screen_source}）"
  fi

  MODE_RESULT_MODE="$mode"
  MODE_RESULT_REASON="$reason"
  MODE_RESULT_CODE_COUNT="${code_count:-0}"
  MODE_RESULT_SCREEN_COUNT="${screen_count:-0}"
  MODE_RESULT_FORM="$form_label"
}

print_single_result() {
  jq -n \
    --arg mode "$MODE_RESULT_MODE" \
    --arg reason "$MODE_RESULT_REASON" \
    --argjson codeFileCount "$MODE_RESULT_CODE_COUNT" \
    --argjson screenIndicatorCount "$MODE_RESULT_SCREEN_COUNT" \
    --arg projectForm "$MODE_RESULT_FORM" \
    '{mode:$mode, reason:$reason, evidence:{codeFileCount:$codeFileCount, screenIndicatorCount:$screenIndicatorCount, projectForm:$projectForm}, sites:[]}'
}

print_monorepo_result() {
  local sites_lines="$1" target_repo_root="$2" output_dir="$3"
  local site_json_all="" total_code=0 total_screen=0
  local best_mode="setup-only" best_priority=0
  local first_mode="" mixed=0
  local mode_list=""

  while IFS='|' read -r key root; do
    [ -z "$key" ] && continue
    local abs_root
    abs_root="$(abs_path "$root" "$target_repo_root")"
    [ -d "$abs_root" ] || continue
    determine_mode_for_scope "$abs_root" "$output_dir" "monorepo"
    total_code=$((total_code + MODE_RESULT_CODE_COUNT))
    total_screen=$((total_screen + MODE_RESULT_SCREEN_COUNT))

    local prio
    case "$MODE_RESULT_MODE" in
      reverse-full) prio=3 ;;
      reverse-degraded) prio=2 ;;
      *) prio=1 ;;
    esac
    if [ "$prio" -gt "$best_priority" ]; then
      best_priority="$prio"
      best_mode="$MODE_RESULT_MODE"
    fi

    if [ -z "$first_mode" ]; then
      first_mode="$MODE_RESULT_MODE"
    elif [ "$MODE_RESULT_MODE" != "$first_mode" ]; then
      mixed=1
    fi
    mode_list="${mode_list}${key}=${MODE_RESULT_MODE}, "

    local site_json
    site_json="$(jq -n \
      --arg path "$root" \
      --arg mode "$MODE_RESULT_MODE" \
      --arg reason "$MODE_RESULT_REASON" \
      --argjson codeFileCount "$MODE_RESULT_CODE_COUNT" \
      --argjson screenIndicatorCount "$MODE_RESULT_SCREEN_COUNT" \
      --arg projectForm "$MODE_RESULT_FORM" \
      '{path:$path, mode:$mode, reason:$reason, evidence:{codeFileCount:$codeFileCount, screenIndicatorCount:$screenIndicatorCount, projectForm:$projectForm}}')"
    site_json_all="${site_json_all}${site_json}
"
  done <<SITES
$sites_lines
SITES

  mode_list="${mode_list%, }"
  local top_reason
  if [ "$mixed" -eq 1 ]; then
    top_reason="モノレポのサブプロジェクトでモードが異なる（${mode_list}）。代表値は最も広い工程を要する ${best_mode} とする"
  else
    top_reason="モノレポの全サブプロジェクトが ${best_mode} と判定されたため（${mode_list}）"
  fi

  local sites_array
  sites_array="$(printf '%s' "$site_json_all" | sed '/^$/d' | jq -s '.')"

  jq -n \
    --arg mode "$best_mode" \
    --arg reason "$top_reason" \
    --argjson codeFileCount "$total_code" \
    --argjson screenIndicatorCount "$total_screen" \
    --arg projectForm "monorepo" \
    --argjson sites "$sites_array" \
    '{mode:$mode, reason:$reason, evidence:{codeFileCount:$codeFileCount, screenIndicatorCount:$screenIndicatorCount, projectForm:$projectForm}, sites:$sites}'
}

# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------
main() {
  local target_repo_root site_arg="" output_dir_arg=""
  target_repo_root="$(abs_path "$1")"
  shift

  while [ $# -gt 0 ]; do
    case "$1" in
      --site) site_arg="${2:-}"; shift 2 ;;
      --output-dir) output_dir_arg="${2:-}"; shift 2 ;;
      *) echo "ERROR: 不明な引数です: $1" >&2; usage; exit 1 ;;
    esac
  done

  if [ ! -d "$target_repo_root" ]; then
    echo "ERROR: 対象リポジトリルートが存在しません: $target_repo_root" >&2
    exit 1
  fi

  if [ -n "$site_arg" ]; then
    local scope_root
    scope_root="$(abs_path "$site_arg" "$target_repo_root")"
    if [ ! -d "$scope_root" ]; then
      echo "ERROR: --site の対象ディレクトリが存在しません: $scope_root" >&2
      exit 1
    fi
    determine_mode_for_scope "$scope_root" "$output_dir_arg" "site"
    print_single_result
    return 0
  fi

  local sites_lines=""
  sites_lines="$(sites_from_survey "$output_dir_arg" "$target_repo_root")"
  if [ -z "$sites_lines" ]; then
    sites_lines="$(detect_workspaces_sites "$target_repo_root" | sort -u)"
  fi

  local site_count
  site_count="$(printf '%s\n' "$sites_lines" | sed '/^$/d' | wc -l | tr -d ' ')"

  if [ "${site_count:-0}" -ge 2 ]; then
    print_monorepo_result "$sites_lines" "$target_repo_root" "$output_dir_arg"
  else
    determine_mode_for_scope "$target_repo_root" "$output_dir_arg" "single"
    print_single_result
  fi
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------
self_test() {
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/resolve-flow-mode-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  local pass=0 fail=0

  assert_mode() {
    local dir="$1" expected="$2" label="$3"
    shift 3
    local out mode ev
    out="$(bash "$SCRIPT_PATH" "$dir" "$@" 2>/dev/null)"
    mode="$(printf '%s' "$out" | jq -r '.mode // empty' 2>/dev/null)"
    ev="$(printf '%s' "$out" | jq -c '.evidence // empty' 2>/dev/null)"
    if [ "$mode" = "$expected" ] && [ -n "$ev" ] && [ "$ev" != "null" ] && [ "$ev" != "{}" ]; then
      echo "PASS: ${label}（mode=${mode} evidence=${ev}）"
      pass=$((pass + 1))
    else
      echo "FAIL: ${label}（期待mode=${expected} 実測mode=${mode} evidence=${ev} 出力=${out}）" >&2
      fail=$((fail + 1))
    fi
  }

  # ケース1: 空のディレクトリ
  local d1="$tmp/empty"
  mkdir -p "$d1"
  assert_mode "$d1" "setup-only" "ケース1 空のディレクトリ"

  # ケース2: READMEと設計書だけ
  local d2="$tmp/docs-only"
  mkdir -p "$d2"
  cat > "$d2/README.md" <<'MD'
# サンプルプロジェクト
MD
  cat > "$d2/設計書.md" <<'MD'
# 設計書

本文。
MD
  assert_mode "$d2" "setup-only" "ケース2 READMEと設計書だけ"

  # ケース3: ソースあり・画面なし
  local d3="$tmp/code-no-screen"
  mkdir -p "$d3/src/lib"
  cat > "$d3/src/lib/calc.ts" <<'TS'
export function add(a: number, b: number): number {
  return a + b;
}
TS
  cat > "$d3/src/lib/util.py" <<'PY'
def double(x):
    return x * 2
PY
  assert_mode "$d3" "reverse-degraded" "ケース3 ソースあり・画面なし"

  # ケース4: ソースあり・画面あり
  local d4="$tmp/code-with-screen"
  mkdir -p "$d4/src/pages" "$d4/src/lib"
  cat > "$d4/src/pages/Home.tsx" <<'TSX'
export default function Home() {
  return <div>home</div>;
}
TSX
  cat > "$d4/src/lib/util.ts" <<'TS'
export const noop = () => {};
TS
  assert_mode "$d4" "reverse-full" "ケース4 ソースあり・画面あり"

  # ケース5: モノレポで片方が画面あり・片方が画面なし
  local d5="$tmp/monorepo"
  mkdir -p "$d5/apps/web/src/pages" "$d5/apps/api-only/src"
  cat > "$d5/package.json" <<'JSON'
{ "name": "mono", "private": true, "workspaces": ["apps/*"] }
JSON
  cat > "$d5/apps/web/src/pages/Home.tsx" <<'TSX'
export default function Home() {
  return <div>home</div>;
}
TSX
  cat > "$d5/apps/api-only/src/index.ts" <<'TS'
export const start = () => {};
TS
  local out5 sites_count web_mode api_mode top_mode top_ev
  out5="$(bash "$SCRIPT_PATH" "$d5" 2>/dev/null)"
  sites_count="$(printf '%s' "$out5" | jq '.sites | length' 2>/dev/null)"
  web_mode="$(printf '%s' "$out5" | jq -r '.sites[] | select(.path=="apps/web") | .mode' 2>/dev/null)"
  api_mode="$(printf '%s' "$out5" | jq -r '.sites[] | select(.path=="apps/api-only") | .mode' 2>/dev/null)"
  top_mode="$(printf '%s' "$out5" | jq -r '.mode' 2>/dev/null)"
  top_ev="$(printf '%s' "$out5" | jq -c '.evidence // empty' 2>/dev/null)"
  if [ "$sites_count" = "2" ] && [ "$web_mode" = "reverse-full" ] && [ "$api_mode" = "reverse-degraded" ] \
    && [ "$web_mode" != "$api_mode" ] && [ -n "$top_ev" ] && [ "$top_ev" != "null" ] && [ "$top_ev" != "{}" ]; then
    echo "PASS: ケース5 モノレポでsite別に異なるモード（web=${web_mode} api-only=${api_mode} 代表=${top_mode}）"
    pass=$((pass + 1))
  else
    echo "FAIL: ケース5 モノレポ判定が不正（出力=${out5}）" >&2
    fail=$((fail + 1))
  fi

  # ボーナス: --output-dir 経由の既存資産（excluded-kinds.json）の再利用
  local d6="$tmp/reuse-code"
  mkdir -p "$d6/src"
  cat > "$d6/src/util.ts" <<'TS'
export const noop = () => {};
TS
  local out6dir="$tmp/reuse-output"
  mkdir -p "$out6dir/一覧"
  cat > "$out6dir/一覧/excluded-kinds.json" <<'JSON'
{
  "generatedAt": "2026-08-01T00:00:00Z",
  "allKinds": ["screen", "api", "table", "batch", "report", "external"],
  "presentKinds": ["screen"],
  "excludedKinds": []
}
JSON
  assert_mode "$d6" "reverse-full" "ボーナス 既存資産(excluded-kinds.json)のscreen実在を優先" --output-dir "$out6dir"

  echo "self-test: $pass PASS, $fail FAIL"
  if [ "$fail" -eq 0 ]; then return 0; else return 1; fi
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

if [ $# -lt 1 ]; then
  usage
  exit 1
fi

main "$@"
