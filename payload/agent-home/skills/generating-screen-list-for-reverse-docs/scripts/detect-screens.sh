#!/usr/bin/env bash
# generating-screen-list-for-reverse-docs: Phase 1 画面境界検出
#
# Usage: detect-screens.sh <source-dir> <manifest-out-path>
#
# 検出優先順位:
#   1. Next.js App Router (app/**/page.{tsx,jsx,js})
#   2. Next.js Pages Router (pages/**/*.{tsx,jsx,js}, _app/_document/api 除外)
#   3. React Router (createBrowserRouter/createHashRouter/<Route> のフラット path 抽出)
#   4. フォールバック: pages/screens/views 慣習ディレクトリ直下を1画面として扱う
#   5. 1-4すべて0件ならハード停止 (exit 3)。画面を捏造しない
#
# 画面キー生成アルゴリズム(意味キー規約準拠・連番サフィックス禁止):
#   1. ルートの静的セグメントのみ抽出(動的パラメータ・ワイルドカード除外)
#   2. 末尾1セグメントを仮キーとする
#   3. 衝突時は末尾からのセグメント数を1つずつ増やして再判定
#   4. 全セグメントを使っても衝突する場合のみ、エントリディレクトリのパスで具体化する
#   5. ルートが `/` または静的セグメント無しの場合は `top`
#
# ファイル収集: エントリファイルと同一ディレクトリ直下 + 直下の components/(_components/) 1階層のみ
# (import グラフ解析はしない。MVPスコープ外)

set -euo pipefail

SOURCE_DIR="${1:?Usage: detect-screens.sh <source-dir> <manifest-out-path>}"
MANIFEST_OUT="${2:?Usage: detect-screens.sh <source-dir> <manifest-out-path>}"

if [ ! -d "$SOURCE_DIR" ]; then
  echo "ERROR: source-dir not found: $SOURCE_DIR" >&2
  exit 1
fi
SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"

TMP_ROWS="$(mktemp)"
SEEN_KEYS_FILE="$(mktemp)"
trap 'rm -f "$TMP_ROWS" "${TMP_ROWS}.keyed" "$SEEN_KEYS_FILE"' EXIT

detection_method=""

# --- 1. Next.js App Router ---
if [ -d "$SOURCE_DIR/app" ]; then
  pagefiles="$(find "$SOURCE_DIR/app" -type f \( -name "page.tsx" -o -name "page.jsx" -o -name "page.js" \) 2>/dev/null | grep -v node_modules || true)"
  if [ -n "$pagefiles" ]; then
    detection_method="nextjs-app"
    while IFS= read -r pagefile; do
      [ -z "$pagefile" ] && continue
      rel="${pagefile#"$SOURCE_DIR"/app}"
      rel="${rel%/page.*}"
      [ -z "$rel" ] && rel="/"
      route="$(printf '%s' "$rel" | sed -E 's#/\([^)]*\)##g')"
      [ -z "$route" ] && route="/"
      route="$(printf '%s' "$route" | sed -E 's#\[\.\.\.[^]]+\]#*#g; s#\[([^]]+)\]#:\1#g')"
      entry_dir="$(dirname "$pagefile")"
      printf '%s\t%s\t%s\t%s\n' "$route" "$entry_dir" "$pagefile" "high" >> "$TMP_ROWS"
    done <<< "$pagefiles"
  fi
fi

# --- 2. Next.js Pages Router ---
if [ -z "$detection_method" ] && [ -d "$SOURCE_DIR/pages" ]; then
  pagefiles="$(find "$SOURCE_DIR/pages" -type f \( -name "*.tsx" -o -name "*.jsx" -o -name "*.js" \) 2>/dev/null \
    | grep -v node_modules \
    | grep -Ev '/_app\.[jt]sx?$' \
    | grep -Ev '/_document\.[jt]sx?$' \
    | grep -Ev '/api/' || true)"
  if [ -n "$pagefiles" ]; then
    detection_method="nextjs-pages"
    while IFS= read -r pagefile; do
      [ -z "$pagefile" ] && continue
      rel="${pagefile#"$SOURCE_DIR"/pages}"
      rel="${rel%.*}"
      rel="${rel%/index}"
      [ -z "$rel" ] && rel="/"
      route="$(printf '%s' "$rel" | sed -E 's#\[\.\.\.[^]]+\]#*#g; s#\[([^]]+)\]#:\1#g')"
      entry_dir="$(dirname "$pagefile")"
      printf '%s\t%s\t%s\t%s\n' "$route" "$entry_dir" "$pagefile" "high" >> "$TMP_ROWS"
    done <<< "$pagefiles"
  fi
fi

# --- 3. React Router (フラット抽出のみ) ---
if [ -z "$detection_method" ]; then
  router_files="$(grep -rlE 'createBrowserRouter|createHashRouter|<Route\b' "$SOURCE_DIR" \
    --include='*.tsx' --include='*.jsx' --include='*.ts' --include='*.js' 2>/dev/null \
    | grep -v node_modules || true)"
  if [ -n "$router_files" ]; then
    detection_method="react-router"
    while IFS= read -r rf; do
      [ -z "$rf" ] && continue
      routes="$(grep -oE 'path[[:space:]]*[:=][[:space:]]*["'"'"'\`][^"'"'"'\`]+["'"'"'\`]' "$rf" 2>/dev/null \
        | sed -E 's/^path[[:space:]]*[:=][[:space:]]*["'"'"'\`]//; s/["'"'"'\`]$//' || true)"
      [ -z "$routes" ] && continue
      while IFS= read -r route; do
        [ -z "$route" ] && continue
        printf '%s\t%s\t%s\t%s\n' "$route" "$(dirname "$rf")" "$rf" "medium" >> "$TMP_ROWS"
      done <<< "$routes"
    done <<< "$router_files"
  fi
fi

# --- 4. フォールバック: 慣習ディレクトリ ---
if [ -z "$detection_method" ]; then
  for conv in pages screens views; do
    conv_dir="$(find "$SOURCE_DIR" -maxdepth 4 -type d -iname "$conv" 2>/dev/null | grep -v node_modules | head -1 || true)"
    if [ -n "$conv_dir" ]; then
      entries="$(find "$conv_dir" -mindepth 1 -maxdepth 1 2>/dev/null || true)"
      [ -z "$entries" ] && continue
      detection_method="fallback-directory"
      while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        if [ -d "$entry" ]; then
          entry_dir="$entry"
        else
          entry_dir="$(dirname "$entry")"
        fi
        printf '不明（フォールバック検出）\t%s\t%s\t%s\n' "$entry_dir" "$entry" "low" >> "$TMP_ROWS"
      done <<< "$entries"
      break
    fi
  done
fi

# --- 5. ハード停止 ---
if [ -z "$detection_method" ] || [ ! -s "$TMP_ROWS" ]; then
  mkdir -p "$(dirname "$MANIFEST_OUT")"
  cat > "$MANIFEST_OUT" <<EOF
{
  "generatedAt": null,
  "sourceDir": "$SOURCE_DIR",
  "detectionSummary": {"method": "none", "screenCount": 0},
  "screens": []
}
EOF
  echo "DETECTION_FAILED: ルーティング定義も慣習ディレクトリも検出できませんでした ($SOURCE_DIR)" >&2
  exit 3
fi

# --- 画面キー生成関数(意味キー規約準拠) ---
# 注意: bash 3.2 (macOS標準/bin/bash) 互換のため declare -A / mapfile は使わない。
# 空配列を printf '%s\n' "${arr[@]}" に渡すとフォーマットが1回だけ評価され
# 空行が1行出力される bash の仕様があるため、要素数ガードを必ず入れる。
static_segments() {
  local route="$1"
  local -a segs
  IFS='/' read -ra segs <<< "$route"
  local out=()
  for s in "${segs[@]}"; do
    [ -z "$s" ] && continue
    case "$s" in
      :*|\**) continue ;;
    esac
    out+=("$s")
  done
  if [ "${#out[@]}" -gt 0 ]; then
    printf '%s\n' "${out[@]}"
  fi
}

read_segments_into() {
  # $1: route, 結果はグローバル配列 SEGS_RESULT に格納(mapfile不使用でbash3.2互換)
  local route="$1"
  SEGS_RESULT=()
  local line
  while IFS= read -r line; do
    SEGS_RESULT+=("$line")
  done < <(static_segments "$route")
}

key_from_tail() {
  local route="$1" n="$2"
  read_segments_into "$route"
  local total="${#SEGS_RESULT[@]}"
  if [ "$total" -eq 0 ]; then
    echo "top"
    return
  fi
  local start=$(( total - n ))
  [ "$start" -lt 0 ] && start=0
  local key=""
  local i
  for ((i=start; i<total; i++)); do
    key="${key}${key:+-}${SEGS_RESULT[$i]}"
  done
  echo "$key"
}

# seen_keys は連想配列(bash4+専用)を使わず、改行区切りファイル($SEEN_KEYS_FILE)で管理する(bash3.2互換)
key_seen() {
  grep -qxF "$1" "$SEEN_KEYS_FILE" 2>/dev/null
}
mark_seen() {
  printf '%s\n' "$1" >> "$SEEN_KEYS_FILE"
}

: > "${TMP_ROWS}.keyed"
while IFS=$'\t' read -r route entry_dir entry_file confidence; do
  read_segments_into "$route"
  total="${#SEGS_RESULT[@]}"
  n=1
  key="$(key_from_tail "$route" "$n")"
  while key_seen "$key"; do
    n=$((n+1))
    if [ "$n" -gt "$total" ]; then
      # ソースディレクトリからの相対パスでキーを具体化する(絶対パス・ユーザー名の混入を避ける)
      rel_dir="${entry_dir#"$SOURCE_DIR"}"
      rel_dir="${rel_dir#/}"
      dirkey="$(printf '%s' "$rel_dir" | sed -E 's#[/ ]+#-#g' | tr '[:upper:]' '[:lower:]')"
      key="${key}-${dirkey}"
      break
    fi
    key="$(key_from_tail "$route" "$n")"
  done
  mark_seen "$key"
  printf '%s\t%s\t%s\t%s\t%s\n' "$key" "$route" "$entry_dir" "$entry_file" "$confidence" >> "${TMP_ROWS}.keyed"
done < "$TMP_ROWS"

# --- JSON エスケープ (最小限: バックスラッシュとダブルクォートのみ) ---
json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

mkdir -p "$(dirname "$MANIFEST_OUT")"
{
  printf '{\n'
  printf '  "generatedAt": "%s",\n' "$(date +%Y-%m-%dT%H:%M:%S%z)"
  printf '  "sourceDir": "%s",\n' "$(json_escape "$SOURCE_DIR")"
  screen_count="$(wc -l < "${TMP_ROWS}.keyed" | tr -d ' ')"
  printf '  "detectionSummary": {"method": "%s", "screenCount": %d},\n' "$detection_method" "$screen_count"
  printf '  "screens": [\n'
  first=1
  while IFS=$'\t' read -r key route entry_dir entry_file confidence; do
    files="$( { find "$entry_dir" -maxdepth 1 -type f 2>/dev/null; find "$entry_dir/components" "$entry_dir/_components" -maxdepth 1 -type f 2>/dev/null; } | grep -v '^$' || true)"
    file_count="$(printf '%s\n' "$files" | grep -c . || true)"
    files_json="$(printf '%s\n' "$files" | grep -v '^$' | while IFS= read -r f; do printf '      "%s"' "$(json_escape "$f")"; echo; done | paste -sd, - 2>/dev/null || true)"
    name_guess="$(basename "$entry_dir" | sed -E 's/[-_]/ /g')"
    [ "$first" -eq 1 ] || printf ',\n'
    first=0
    printf '    {\n'
    printf '      "screenKey": "%s",\n' "$(json_escape "$key")"
    printf '      "screenNameGuess": "%s",\n' "$(json_escape "$name_guess")"
    printf '      "route": "%s",\n' "$(json_escape "$route")"
    printf '      "detectionMethod": "%s",\n' "$detection_method"
    printf '      "confidence": "%s",\n' "$confidence"
    printf '      "entryFile": "%s",\n' "$(json_escape "$entry_file")"
    printf '      "fileCount": %d,\n' "$file_count"
    if [ -n "$files_json" ]; then
      printf '      "files": [\n%s\n      ],\n' "$files_json"
    else
      printf '      "files": [],\n'
    fi
    printf '      "scaffoldDir": "screen-%s",\n' "$(json_escape "$key")"
    printf '      "scaffoldStatus": "pending"\n'
    printf '    }'
  done < "${TMP_ROWS}.keyed"
  printf '\n  ]\n'
  printf '}\n'
} > "$MANIFEST_OUT"

echo "OK: detected $screen_count screens via $detection_method -> $MANIFEST_OUT" >&2
