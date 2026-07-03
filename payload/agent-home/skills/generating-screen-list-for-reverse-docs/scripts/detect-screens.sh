#!/usr/bin/env bash
# generating-screen-list-for-reverse-docs: Phase 1 画面境界検出
#
# Usage: detect-screens.sh <source-dir> <manifest-out-path> \
#          [--screen-id-regex <ERE>] [--view-switch-pattern <ERE>]
#
# --screen-id-regex <ERE>:
#   entryFile の basename(拡張子なし) から grep -oE で画面IDを抽出するパターン
#   (例: 'T-[A-Z]+-[0-9]+(-[0-9]+)*')。未指定なら screenId は null。
# --view-switch-pattern <ERE>:
#   埋め込みビュー検出用の grep パターン(例: 'setEditView|setModalView')。
#   未指定なら埋め込みビュー検出をスキップする。
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
#   4. 全セグメントを使っても衝突する場合、エントリディレクトリのパスで具体化する
#   5. それでも衝突する場合、entry_file の basename(拡張子なし・小文字化)で具体化する
#   6. ルートが `/` または静的セグメント無しの場合は `top`
#
# ファイル収集: エントリファイルと同一ディレクトリ直下 + 直下の components/(_components/) 1階層のみ
# (import グラフ解析はしない。MVPスコープ外)
#
# 重複マージ: 同一 (route, entryFile) の行は 1 行にマージし、出現回数を routeDupCount として保持する。
# 共有クラスタ: 異なる screenKey が同一 entryFile を共有する場合、sharedWith / clusterId を付与する。
# 埋め込みビュー: --view-switch-pattern 指定時、条件分岐で切り替えられる子ビューを kind: "embedded-view" として
#   独立行で出力する(1階層 import grep による best-effort 解決)。

set -euo pipefail

SCREEN_ID_REGEX=""
VIEW_SWITCH_PATTERN=""
POSITIONAL=()
while [ $# -gt 0 ]; do
  case "$1" in
    --screen-id-regex)
      SCREEN_ID_REGEX="${2:-}"
      shift 2
      ;;
    --view-switch-pattern)
      VIEW_SWITCH_PATTERN="${2:-}"
      shift 2
      ;;
    --)
      shift
      while [ $# -gt 0 ]; do
        POSITIONAL+=("$1")
        shift
      done
      ;;
    -*)
      echo "ERROR: unknown option: $1" >&2
      exit 1
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

if [ "${#POSITIONAL[@]}" -lt 2 ]; then
  echo "Usage: detect-screens.sh <source-dir> <manifest-out-path> [--screen-id-regex <ERE>] [--view-switch-pattern <ERE>]" >&2
  exit 1
fi
SOURCE_DIR="${POSITIONAL[0]}"
MANIFEST_OUT="${POSITIONAL[1]}"

if [ ! -d "$SOURCE_DIR" ]; then
  echo "ERROR: source-dir not found: $SOURCE_DIR" >&2
  exit 1
fi
SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"

TMP_ROWS="$(mktemp)"
SEEN_KEYS_FILE="$(mktemp)"
TMP_MERGED="$(mktemp)"
TMP_KEYED="$(mktemp)"
TMP_EMBEDDED="$(mktemp)"
TMP_ALL="$(mktemp)"
TMP_CLUSTERS="$(mktemp)"
trap 'rm -f "$TMP_ROWS" "$SEEN_KEYS_FILE" "$TMP_MERGED" "$TMP_KEYED" "$TMP_EMBEDDED" "$TMP_ALL" "$TMP_CLUSTERS"' EXIT

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

# キー正規化: 連続ハイフンの縮約・先頭/末尾ハイフンの除去(意味キー品質の担保)
norm_key() {
  local k
  k="$(printf '%s' "$1" | sed -E 's/-+/-/g; s/^-+//; s/-+$//')"
  [ -z "$k" ] && k="top"
  printf '%s' "$k"
}

# --- 完全重複の事前マージ(同一 route + entryFile を1行に集約し、routeDupCount を保持) ---
# dirkey 経路での偶発的なキー重複バグ(問題3)を構造的に解消する: 同一 (route, entryFile) が
# 複数回出現しても、キー生成前に1行へ縮約されるため重複キーが発生しない。
awk -F'\t' '
{
  k = $1 SUBSEP $3
  if (!(k in seen)) {
    order[++n] = k
    r[k] = $1
    ed[k] = $2
    ef[k] = $3
    cf[k] = $4
  }
  seen[k]++
}
END {
  for (i = 1; i <= n; i++) {
    k = order[i]
    printf "%s\t%s\t%s\t%s\t%d\n", r[k], ed[k], ef[k], cf[k], seen[k]
  }
}
' "$TMP_ROWS" > "$TMP_MERGED"

# --- キー採番(保険として dirkey 付与後も再衝突検証を行う) ---
while IFS=$'\t' read -r route entry_dir entry_file confidence dupcount; do
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
      # entry_dir が SOURCE_DIR 直下等で dirkey が空になる場合は付与しない(末尾ハイフン防止)
      [ -n "$dirkey" ] && key="${key}-${dirkey}"
      break
    fi
    key="$(key_from_tail "$route" "$n")"
  done
  key="$(norm_key "$key")"
  # 保険: dirkey付与後もなお衝突する場合は entry_file の basename(拡張子なし・小文字化)で具体化する
  if key_seen "$key"; then
    base_noext="$(basename "$entry_file")"
    base_noext="${base_noext%.*}"
    base_noext_lc="$(printf '%s' "$base_noext" | tr '[:upper:]' '[:lower:]')"
    key="$(norm_key "${key}-${base_noext_lc}")"
  fi
  mark_seen "$key"
  kind="route"
  row_confidence="$confidence"
  if [ -z "$entry_file" ]; then
    kind="unresolved"
    row_confidence="low"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$key" "$kind" "$route" "$entry_dir" "$entry_file" "$row_confidence" "$dupcount" "" >> "$TMP_KEYED"
done < "$TMP_MERGED"

# --- JSON エスケープ (最小限: バックスラッシュとダブルクォートのみ) ---
json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# --- screenId 抽出 ---
extract_screen_id() {
  local file="$1"
  [ -z "$SCREEN_ID_REGEX" ] && return 0
  [ -z "$file" ] && return 0
  local base
  base="$(basename "$file")"
  base="${base%.*}"
  printf '%s' "$base" | grep -oE "$SCREEN_ID_REGEX" | head -1 || true
}

# --- 既に route 画面の entryFile として検出済みの basename(拡張子なし)集合 ---
ROUTE_ENTRY_BASENAMES="$(awk -F'\t' '$2=="route"{n=$5; sub(/.*\//,"",n); sub(/\.[^.]*$/,"",n); if (n!="") print n}' "$TMP_KEYED" | sort -u)"

# --- 埋め込みビュー検出(kind: "embedded-view") ---
# --view-switch-pattern 指定時のみ。1階層 import grep による best-effort 解決(完全な import グラフ解析はしない)。
# 同一 entryFile を複数の親画面が共有する場合(共有クラスタ)でも1回だけ処理し、
# embeddedIn には当該 entryFile を持つ全親キーをカンマ結合で記録する(重複行防止)。
if [ -n "$VIEW_SWITCH_PATTERN" ]; then
  awk -F'\t' '$2=="route" && $5!="" {
    if (!($5 in keys)) { order[++n]=$5 }
    keys[$5] = keys[$5] ((keys[$5]=="")?"":",") $1
  } END { for(i=1;i<=n;i++){ f=order[i]; print f "\t" keys[f] } }' "$TMP_KEYED" > "${TMP_EMBEDDED}.parents"
  while IFS=$'\t' read -r entry_file parent_keys; do
    [ -f "$entry_file" ] || continue
    first_parent="${parent_keys%%,*}"
    matching_lines="$(grep -E "$VIEW_SWITCH_PATTERN" "$entry_file" 2>/dev/null || true)"
    [ -z "$matching_lines" ] && continue
    comps="$(printf '%s\n' "$matching_lines" | grep -oE '<[A-Z][A-Za-z0-9]*' | sed 's/^<//' | sort -u || true)"
    [ -z "$comps" ] && continue
    while IFS= read -r comp; do
      [ -z "$comp" ] && continue
      if printf '%s\n' "$ROUTE_ENTRY_BASENAMES" | grep -qxF "$comp"; then
        continue
      fi
      import_line="$(grep -E "^import.*${comp}.*from" "$entry_file" 2>/dev/null | head -1 || true)"
      import_path=""
      if [ -n "$import_line" ]; then
        import_path="$(printf '%s' "$import_line" | grep -oE "['\"][^'\"]+['\"]" | head -1 | sed "s/^['\"]//; s/['\"]\$//" || true)"
      fi
      found_file="$(find "$SOURCE_DIR" -type f \( -iname "${comp}.tsx" -o -iname "${comp}.jsx" -o -iname "${comp}.ts" -o -iname "${comp}.js" \) 2>/dev/null | grep -v node_modules | head -1 || true)"
      if [ -n "$found_file" ]; then
        resolved="$found_file"
      elif [ -n "$import_path" ]; then
        resolved="$import_path"
      else
        resolved="$comp"
      fi
      ekey="$(printf '%s' "$comp" | sed -E 's/([a-z0-9])([A-Z])/\1-\2/g; s/([A-Z]+)([A-Z][a-z])/\1-\2/g' | tr '[:upper:]' '[:lower:]')"
      ekey="$(norm_key "$ekey")"
      if key_seen "$ekey"; then
        ekey="$(norm_key "${first_parent}-${ekey}")"
      fi
      if key_seen "$ekey"; then
        safeguard="$(basename "$resolved")"
        safeguard="${safeguard%.*}"
        safeguard_lc="$(printf '%s' "$safeguard" | tr '[:upper:]' '[:lower:]')"
        ekey="$(norm_key "${ekey}-${safeguard_lc}")"
      fi
      mark_seen "$ekey"
      edir=""
      if [ -n "$found_file" ]; then
        edir="$(dirname "$found_file")"
      fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ekey" "embedded-view" "なし（埋め込みビュー）" "$edir" "$resolved" "medium" "1" "$parent_keys" >> "$TMP_EMBEDDED"
    done <<< "$comps"
  done < "${TMP_EMBEDDED}.parents"
  rm -f "${TMP_EMBEDDED}.parents"

  # 最終マージ: 異なる親entryFileが同一コンポーネントを参照した場合の (route+entryFile) 重複を1行に統合し、
  # embeddedIn の親キーを結合・重複除去する
  if [ -s "$TMP_EMBEDDED" ]; then
    awk -F'\t' '{
      k=$5
      if (!(k in seen)) { order[++n]=k; k1[k]=$1; k4[k]=$4; parents[k]=$8 }
      else { parents[k]=parents[k] "," $8 }
      seen[k]=1
    } END {
      for(i=1;i<=n;i++){
        k=order[i]
        m=split(parents[k], arr, ",")
        out=""; delete uniq
        for(j=1;j<=m;j++){ if(!(arr[j] in uniq) && arr[j]!=""){ uniq[arr[j]]=1; out=out ((out=="")?"":",") arr[j] } }
        printf "%s\tembedded-view\tなし（埋め込みビュー）\t%s\t%s\tmedium\t1\t%s\n", k1[k], k4[k], k, out
      }
    }' "$TMP_EMBEDDED" > "${TMP_EMBEDDED}.merged" && mv "${TMP_EMBEDDED}.merged" "$TMP_EMBEDDED"
  fi
fi

cat "$TMP_KEYED" "$TMP_EMBEDDED" > "$TMP_ALL"

# --- 共有クラスタ算出(同一 entryFile を共有する route 画面が2つ以上ある場合) ---
awk -F'\t' '$2=="route" && $5!=""{
  keys[$5] = keys[$5] (($5 in seen) ? "," : "") $1
  seen[$5]=1
}
END {
  for (f in keys) {
    n = split(keys[f], arr, ",")
    if (n >= 2) {
      print f "\t" keys[f]
    }
  }
}' "$TMP_ALL" > "${TMP_CLUSTERS}.raw"

: > "$TMP_CLUSTERS"
while IFS=$'\t' read -r efile keys_csv; do
  sorted="$(printf '%s\n' "$keys_csv" | tr ',' '\n' | sort -u | paste -sd, -)"
  rep="$(printf '%s' "$sorted" | cut -d, -f1)"
  cluster_id="${rep}-shared"
  printf '%s\t%s\t%s\n' "$efile" "$sorted" "$cluster_id" >> "$TMP_CLUSTERS"
done < "${TMP_CLUSTERS}.raw"
rm -f "${TMP_CLUSTERS}.raw"

mkdir -p "$(dirname "$MANIFEST_OUT")"

screen_count="$(wc -l < "$TMP_ALL" | tr -d ' ')"
cluster_count="$(wc -l < "$TMP_CLUSTERS" | tr -d ' ')"
shared_screen_count="$(awk -F'\t' '{n=split($2,a,","); sum+=n} END{print sum+0}' "$TMP_CLUSTERS")"
embedded_candidate_count="$(wc -l < "$TMP_EMBEDDED" | tr -d ' ')"
unresolved_count="$(awk -F'\t' '$5==""{c++} END{print c+0}' "$TMP_ALL")"

screen_id_regex_json="null"
[ -n "$SCREEN_ID_REGEX" ] && screen_id_regex_json="\"$(json_escape "$SCREEN_ID_REGEX")\""
view_switch_pattern_json="null"
[ -n "$VIEW_SWITCH_PATTERN" ] && view_switch_pattern_json="\"$(json_escape "$VIEW_SWITCH_PATTERN")\""

{
  printf '{\n'
  printf '  "generatedAt": "%s",\n' "$(date +%Y-%m-%dT%H:%M:%S%z)"
  printf '  "sourceDir": "%s",\n' "$(json_escape "$SOURCE_DIR")"
  printf '  "strategy": {"screenIdRegex": %s, "viewSwitchPattern": %s},\n' "$screen_id_regex_json" "$view_switch_pattern_json"
  printf '  "detectionSummary": {"method": "%s", "screenCount": %d, "clusterCount": %d, "sharedScreenCount": %d, "embeddedCandidateCount": %d, "unresolvedCount": %d},\n' \
    "$detection_method" "$screen_count" "$cluster_count" "$shared_screen_count" "$embedded_candidate_count" "$unresolved_count"
  printf '  "screens": [\n'
  first=1
  while IFS=$'\t' read -r key kind route entry_dir entry_file confidence dupcount embedded_in; do
    if [ -z "$entry_file" ]; then
      kind="unresolved"
      confidence="low"
    fi

    files=""
    file_count=0
    if [ -n "$entry_dir" ] && [ -d "$entry_dir" ]; then
      files="$( { find "$entry_dir" -maxdepth 1 -type f 2>/dev/null; find "$entry_dir/components" "$entry_dir/_components" -maxdepth 1 -type f 2>/dev/null; } | grep -v '^$' || true)"
      file_count="$(printf '%s\n' "$files" | grep -c . || true)"
    fi
    files_json="$(printf '%s\n' "$files" | grep -v '^$' | while IFS= read -r f; do printf '      "%s"' "$(json_escape "$f")"; echo; done | paste -sd, - 2>/dev/null || true)"

    screen_id="$(extract_screen_id "$entry_file")"
    screen_id_json="null"
    [ -n "$screen_id" ] && screen_id_json="\"$(json_escape "$screen_id")\""

    if [ "$kind" = "embedded-view" ]; then
      name_guess="$(printf '%s' "$key" | sed 's/-/ /g')"
    elif [ -n "$entry_dir" ]; then
      name_guess="$(basename "$entry_dir" | sed -E 's/[-_]/ /g')"
    else
      name_guess="$(basename "$entry_file" 2>/dev/null | sed -E 's/[-_]/ /g')"
    fi
    name_guess="$(printf '%s' "$name_guess" | sed -E 's/ +/ /g; s/^ //; s/ $//')"

    shared_with_json="[]"
    cluster_id_json="null"
    if [ "$kind" = "route" ] && [ -n "$entry_file" ]; then
      cluster_line="$(awk -F'\t' -v ef="$entry_file" '$1==ef{print; exit}' "$TMP_CLUSTERS" 2>/dev/null || true)"
      if [ -n "$cluster_line" ]; then
        cluster_keys="$(printf '%s' "$cluster_line" | cut -d "$(printf '\t')" -f2)"
        cluster_id_val="$(printf '%s' "$cluster_line" | cut -d "$(printf '\t')" -f3)"
        others="$(printf '%s\n' "$cluster_keys" | tr ',' '\n' | grep -vxF "$key" || true)"
        others_json="$(printf '%s\n' "$others" | grep -v '^$' | while IFS= read -r ok; do printf '"%s"' "$(json_escape "$ok")"; echo; done | paste -sd, - 2>/dev/null || true)"
        if [ -n "$others_json" ]; then
          shared_with_json="[${others_json}]"
        fi
        cluster_id_json="\"$(json_escape "$cluster_id_val")\""
        name_guess="(共有: $(basename "$entry_file"))"
      fi
    fi

    embedded_in_json="null"
    [ -n "$embedded_in" ] && embedded_in_json="\"$(json_escape "$embedded_in")\""

    detection_method_field="$detection_method"
    if [ "$kind" = "embedded-view" ]; then
      detection_method_field="embedded-view-heuristic"
    fi

    [ "$first" -eq 1 ] || printf ',\n'
    first=0
    printf '    {\n'
    printf '      "screenKey": "%s",\n' "$(json_escape "$key")"
    printf '      "screenId": %s,\n' "$screen_id_json"
    printf '      "kind": "%s",\n' "$kind"
    printf '      "screenNameGuess": "%s",\n' "$(json_escape "$name_guess")"
    printf '      "route": "%s",\n' "$(json_escape "$route")"
    printf '      "detectionMethod": "%s",\n' "$detection_method_field"
    printf '      "confidence": "%s",\n' "$confidence"
    printf '      "entryFile": "%s",\n' "$(json_escape "$entry_file")"
    printf '      "fileCount": %d,\n' "$file_count"
    if [ -n "$files_json" ]; then
      printf '      "files": [\n%s\n      ],\n' "$files_json"
    else
      printf '      "files": [],\n'
    fi
    printf '      "sharedWith": %s,\n' "$shared_with_json"
    printf '      "clusterId": %s,\n' "$cluster_id_json"
    printf '      "embeddedIn": %s,\n' "$embedded_in_json"
    printf '      "routeDupCount": %d\n' "$dupcount"
    printf '    }'
  done < "$TMP_ALL"
  printf '\n  ]\n'
  printf '}\n'
} > "$MANIFEST_OUT"

echo "OK: detected $screen_count screens ($cluster_count clusters, $embedded_candidate_count embedded, $unresolved_count unresolved) via $detection_method -> $MANIFEST_OUT" >&2
