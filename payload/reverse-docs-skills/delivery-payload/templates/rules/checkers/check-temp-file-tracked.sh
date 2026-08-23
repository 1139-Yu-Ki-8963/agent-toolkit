#!/usr/bin/env bash
# check-temp-file-tracked.sh — どこに何を置くかの決まり linter
#
# timing: PreToolUse(Write)
# 対象規約: どこに何を置くかの決まり（directory-structure.md）
# 検査する規則（検査列に「静的解析」を含む規則すべて）:
#   - 一時ファイルをリポジトリ内へ置かない: 版管理の追跡の対象に一時ファイルらしい
#     名前が無いかを走査する
#   - 直下を許可の一覧で管理する: リポジトリ直下のディレクトリが許可の一覧に
#     含まれているかを走査する（新設される直下ディレクトリのみを対象とする）
#   - 深い入れ子を作らない: 5 階層を超えていないかを走査する（既定値）
#   - 名前の付け方を階層内で揃える: 同じ階層のディレクトリ名の表記の形式が
#     揃っているかを走査する（静的解析の範囲のみ。レビュー観点の
#     「単数と複数の混在」は対象外）
#   - 置き場を役割で分ける: 実装・テスト・文書・設定・生成物の役割ごとの
#     置き場を、対象プロジェクトが cwd 配下の docs/rules/**/rule.md へ
#     宣言している場合のみ判定する（check-currency-float-type.sh と同じ
#     「宣言待ち」方式。宣言が無ければ通知のみ）
#   - 依存の向きを一方向に保つ: 層をまたぐ取り込みの向きが、同じ宣言に
#     並んだ層の順序（先頭が最も外側、末尾が最も内側）と逆になっていないかを
#     走査する（宣言待ち方式）
#   - 運営文書の置き場を固定する: ファイル名から種類を確定できる運営文書が、
#     作業指示書は docs/tasks/、検査・検証・進行の記録と台帳は
#     docs/tasks/work-records/、設計判断は docs/decisions/ に置かれているかを走査する
#
# 判定:
#   書き込み先パスから上記の各規則の違反を走査し、1件でも見つかれば
#   block（exit 2）する。違反メッセージには規則名を含める。
#   出力する各行は「動詞＋角括弧に囲んだ規則名＋コロン＋説明」の形式（動詞は
#   拒否・通知・許可・対象外のいずれか）とし、1行に1判定だけを出力する。
#
# 除外条件（誤検知回避）:
#   - tool_name が Write 以外 → 対象外
#   - 直下許可一覧・階層深さ・命名表記の各判定は、書き込み先が git リポジトリ内
#     で repo root を解決できる場合のみ実行する（git が使えない・リポジトリで
#     ない場合は対象外の判定を返す）
#   - 直下許可一覧の判定は、許可リスト定義ファイル
#     （`.claude/rules/always/project-context/rule.md` の
#     「## ルート直下許可ディレクトリ」節）が存在する場合のみ実行する
#   - 置き場を役割で分ける・依存の向きを一方向に保つ: cwd が空 → 判定関数自体を
#     呼ばない（宣言の有無を確認する docs/rules/ の走査基点が無いため）
#
# 既知の限界:
#   - 直下許可一覧・階層深さ・命名表記の判定は、対象ディレクトリが「既に存在する
#     かどうか」をファイルシステムから読み取る。存在しなければ「新設」とみなす
#     ため、既存のディレクトリ構成の是非までは判定しない
#   - 命名表記の判定はディレクトリ名がケバブケース・スネークケース・キャメル
#     ケースのいずれかに明確に分類できる場合のみ比較する
#   - 置き場を役割で分ける: 宣言された置き場は書き込み先パスの単純な前方一致で
#     照合する。cwd からの相対パスへの正規化は行わないため、絶対パスで
#     渡された書き込み先は宣言の文字列と前方一致しないことがある
#   - 宣言から値を取り出す方式は、宣言が自由な文章のため最初に一致した組だけを見る
#   - 取り込みの抽出は3つの書き方だけを見る（`from '...'` / `import '...'` /
#     `require('...')`）。それ以外の書き方（動的 import 等）は見落とす
#
# 止めるか知らせるか:
#   一時ファイルをリポジトリ内へ置かない: 止める（一時ファイルが履歴に一度入ると、以後の版すべてに残り続け取り消せないため）
#   直下を許可の一覧で管理する: 止める（許可の一覧に無いディレクトリが直下に新設され履歴に残ると、構成の逸脱が既成事実として積み重なるため）
#   深い入れ子を作らない: 止める（既定の上限を超える深い階層が一度作られ履歴に残ると、後から浅くし直す作業が構成変更として重くなるため）
#   名前の付け方を階層内で揃える: 止める（表記形式が揃わないディレクトリが一度新設され履歴に残ると、同じ階層内の不揃いが既成事実として固定されるため）
#   置き場を役割で分ける: 知らせる（宣言は対象プロジェクトのリバース解析が進めば自然に整い、判定できるようになるため）
#   依存の向きを一方向に保つ: 止める（内側の層から外側の層への取り込みが一度実装され履歴に残ると、依存の逆転が既成事実として固定されるため）
#   運営文書の置き場を固定する: 止める（誤った置き場へ運営文書が追加されると、課題や判断の探索先が分散するため）
#
# 逃げ道:
#   TEMP_FILE_TRACKED_SKIP_REASON に理由を書けば通る。理由が空の場合は通らない
#
# 使い方:
#   フック本体として: PreToolUse(Write) の入力 JSON を stdin から受け取る
#   単体実行: check-temp-file-tracked.sh --self-test
set -uo pipefail

TEMP_NAME_RE='\.(tmp|bak|swp|swo|orig|rej)$|~$|^\.DS_Store$|^Thumbs\.db$|^(scratch|draft|wip)[-_.]'
NEST_DEPTH_LIMIT=5

# ---- 共通ヘルパー ----
nearest_existing_dir() {
  local d="$1"
  while [ ! -d "$d" ] && [ "$d" != "/" ] && [ "$d" != "." ]; do
    d="$(dirname "$d")"
  done
  printf '%s' "$d"
}

# repo_root_for が返す値は git によりシンボリックリンク解決済みだが、
# file_path 側は未解決のことがある（macOS の /tmp -> /private/tmp 等）。
# 両者を同じ正規化空間へそろえてから比較するため、書き込み先ディレクトリの
# 正規化パスと repo root からの相対パスを算出し、REPO_ROOT / REL_DIR /
# RESOLVED_DIR へ設定する。
compute_dir_context() {
  local file_path="$1" dir base_dir remainder resolved_base
  dir="$(dirname "$file_path")"
  base_dir="$(nearest_existing_dir "$dir")"
  [ -z "$base_dir" ] && return 1
  command -v git >/dev/null 2>&1 || return 1
  REPO_ROOT="$(git -C "$base_dir" rev-parse --show-toplevel 2>/dev/null)"
  [ -z "$REPO_ROOT" ] && return 1
  resolved_base="$(cd "$base_dir" 2>/dev/null && pwd -P)" || return 1
  if [ "$dir" = "$base_dir" ]; then
    RESOLVED_DIR="$resolved_base"
  else
    remainder="${dir#"$base_dir"/}"
    RESOLVED_DIR="${resolved_base}/${remainder}"
  fi
  case "$RESOLVED_DIR" in
    "$REPO_ROOT") REL_DIR="" ;;
    "$REPO_ROOT"/*) REL_DIR="${RESOLVED_DIR#"$REPO_ROOT"/}" ;;
    *) return 1 ;;
  esac
  return 0
}

parse_root_allowlist() {
  local repo_root="$1" rule_file
  rule_file="${repo_root}/.claude/rules/always/project-context/rule.md"
  [ -f "$rule_file" ] || return 1
  awk '
    /^## ルート直下許可ディレクトリ/{flag=1; next}
    /^## /{if(flag) exit}
    flag && /^\|/ {print}
  ' "$rule_file" \
  | grep -vE '^\|[-: ]+\|' \
  | tail -n +2 \
  | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); if ($2!="") print $2}'
}

# cwd 配下の docs/rules/**/rule.md の「## このプロジェクトの規則」表から、
# 規則名（第1列）が完全一致する行の内容列（第2列）を1件返す。無ければ空文字。
lookup_project_override_content() {
  # $1: cwd, $2: rule name
  local cwd="$1" name="$2" file
  [ -d "$cwd/docs/rules" ] || return 0
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    awk -v name="$name" '
      BEGIN { insec = 0 }
      /^## このプロジェクトの規則/ { insec = 1; next }
      /^## / && insec == 1 { insec = 0 }
      insec == 1 && /^\|/ {
        line = $0
        if (line ~ /^\| *規則 *\|/) next
        if (line ~ /^\|[-: ]+\|[-: ]+\|/) next
        n = split(line, cols, "|")
        rule = cols[2]; gsub(/^[ \t]+|[ \t]+$/, "", rule)
        if (rule == name) {
          content = cols[3]; gsub(/^[ \t]+|[ \t]+$/, "", content)
          print content
          exit
        }
      }
    ' "$file"
  done < <(find "$cwd/docs/rules" -name 'rule.md' 2>/dev/null) | head -1
}

# ---- 一時ファイルをリポジトリ内へ置かない（既存） ----
check_temp_file_tracked() {
  # $1: file_path, $2: skip_gitignore_check(1=スキップ, 0=通常)
  local file_path="$1" skip_gitignore="${2:-0}"
  local base
  base="$(basename "$file_path")"

  if ! printf '%s' "$base" | grep -qE "$TEMP_NAME_RE"; then
    echo "許可[一時ファイルをリポジトリ内へ置かない]: 一時ファイルらしい名前ではありません"
    return 0
  fi

  if [ "$skip_gitignore" -eq 0 ] && command -v git >/dev/null 2>&1; then
    local dir
    dir="$(dirname "$file_path")"
    if [ -d "$dir" ] && git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      if git -C "$dir" check-ignore -q -- "$file_path" 2>/dev/null; then
        echo "対象外[一時ファイルをリポジトリ内へ置かない]: .gitignore により追跡対象外です（${base}）"
        return 0
      fi
    fi
  fi

  echo "拒否[一時ファイルをリポジトリ内へ置かない]: 一時ファイルらしい名前のファイルをリポジトリ内へ置こうとしています（${base}）"
  return 2
}

# ---- 直下を許可の一覧で管理する ----
check_root_dir_allowlist() {
  local file_path="$1"
  if ! compute_dir_context "$file_path"; then
    echo "対象外[直下を許可の一覧で管理する]: リポジトリを解決できません（${file_path}）"
    return 0
  fi
  if [ -z "$REL_DIR" ]; then
    echo "対象外[直下を許可の一覧で管理する]: 書き込み先はリポジトリ直下のファイルであり、新設ディレクトリの判定対象ではありません（${file_path}）"
    return 0
  fi

  local top="${REL_DIR%%/*}"
  if [ -d "${REPO_ROOT}/${top}" ]; then
    echo "許可[直下を許可の一覧で管理する]: ${top} は既存のディレクトリです"
    return 0
  fi

  local allowlist
  allowlist="$(parse_root_allowlist "$REPO_ROOT")"
  if [ -z "$allowlist" ]; then
    echo "対象外[直下を許可の一覧で管理する]: 許可の一覧が定義されていません"
    return 0
  fi

  if printf '%s\n' "$allowlist" | grep -qxF "$top"; then
    echo "許可[直下を許可の一覧で管理する]: ${top} は許可の一覧に含まれています"
    return 0
  fi

  echo "拒否[直下を許可の一覧で管理する]: リポジトリ直下に許可の一覧に無いディレクトリを新設しようとしています（${top}）"
  return 2
}

# ---- 深い入れ子を作らない（5階層） ----
check_deep_nesting() {
  local file_path="$1" limit="$2"
  if ! compute_dir_context "$file_path"; then
    echo "対象外[深い入れ子を作らない]: リポジトリを解決できません（${file_path}）"
    return 0
  fi
  if [ -z "$REL_DIR" ]; then
    echo "許可[深い入れ子を作らない]: リポジトリ直下のため階層の上限に達しません"
    return 0
  fi

  local depth
  depth=$(printf '%s' "$REL_DIR" | awk -F'/' '{print NF}')
  if [ "$depth" -le "$limit" ]; then
    echo "許可[深い入れ子を作らない]: ディレクトリの深さは既定の上限（${limit}階層）以内です（${depth}階層）"
    return 0
  fi

  echo "拒否[深い入れ子を作らない]: ディレクトリの深さが既定の上限（${limit}階層）を超えています（${depth}階層、${REL_DIR}）"
  return 2
}

# ---- 名前の付け方を階層内で揃える ----
detect_casing_style() {
  local name="$1"
  if printf '%s' "$name" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)+$'; then
    echo "kebab"
  elif printf '%s' "$name" | grep -qE '^[a-z0-9]+(_[a-z0-9]+)+$'; then
    echo "snake"
  elif printf '%s' "$name" | grep -qE '^[a-z][a-zA-Z0-9]*[A-Z][a-zA-Z0-9]*$'; then
    echo "camel"
  else
    echo "other"
  fi
}

check_sibling_casing() {
  local file_path="$1"
  if ! compute_dir_context "$file_path"; then
    echo "対象外[名前の付け方を階層内で揃える]: リポジトリを解決できません（${file_path}）"
    return 0
  fi
  if [ -z "$REL_DIR" ]; then
    echo "対象外[名前の付け方を階層内で揃える]: リポジトリ直下への書き込みです（${file_path}）"
    return 0
  fi

  local cur="$REPO_ROOT" seg parent="" new_name=""
  local IFS_OLD="$IFS"
  IFS='/'
  for seg in $REL_DIR; do
    IFS="$IFS_OLD"
    [ -z "$seg" ] && continue
    if [ ! -d "${cur}/${seg}" ]; then
      parent="$cur"
      new_name="$seg"
      break
    fi
    cur="${cur}/${seg}"
    IFS='/'
  done
  IFS="$IFS_OLD"
  if [ -z "$new_name" ]; then
    echo "対象外[名前の付け方を階層内で揃える]: 新設するディレクトリが見当たりません（${file_path}）"
    return 0
  fi

  local new_style
  new_style="$(detect_casing_style "$new_name")"
  if [ "$new_style" = "other" ]; then
    echo "対象外[名前の付け方を階層内で揃える]: 表記形式を判定できない名前です（${new_name}）"
    return 0
  fi

  local sibling_path sibling_name style siblings_styles=""
  for sibling_path in "$parent"/*/; do
    [ -d "$sibling_path" ] || continue
    sibling_path="${sibling_path%/}"
    sibling_name="$(basename "$sibling_path")"
    [ "$sibling_name" = "$new_name" ] && continue
    style="$(detect_casing_style "$sibling_name")"
    [ "$style" = "other" ] && continue
    siblings_styles="${siblings_styles}${style}
"
  done
  if [ -z "$siblings_styles" ]; then
    echo "許可[名前の付け方を階層内で揃える]: 比較できる既存の兄弟ディレクトリが見当たりません"
    return 0
  fi

  if ! printf '%s' "$siblings_styles" | grep -qxF "$new_style"; then
    echo "拒否[名前の付け方を階層内で揃える]: 新設するディレクトリの表記形式が同じ階層の既存ディレクトリと揃っていません（${new_name}: ${new_style}）"
    return 2
  fi

  echo "許可[名前の付け方を階層内で揃える]: 新設するディレクトリの表記形式は同じ階層の既存ディレクトリと揃っています（${new_name}: ${new_style}）"
  return 0
}

# ---- 置き場を役割で分ける ----
judge_role_separation() {
  # $1: cwd, $2: file_path
  local cwd="$1" file_path="$2"

  local override
  override="$(lookup_project_override_content "$cwd" "置き場を役割で分ける")"
  if [ -z "$override" ]; then
    echo "通知[置き場を役割で分ける]: このプロジェクトの規則に役割ごとの置き場の宣言がないため判定していません。リバース解析を実行すると判定の対象になります"
    return 0
  fi

  local tokens roles
  tokens="$(printf '%s' "$override" | sed 's/、/\n/g; s/,/\n/g; s/・/\n/g; s/　/\n/g; s/ /\n/g' | sed '/^[[:space:]]*$/d')"
  roles="$(printf '%s\n' "$tokens" | grep -F '/')"
  if [ -z "$roles" ]; then
    echo "通知[置き場を役割で分ける]: このプロジェクトの規則に宣言はありますが、役割ごとの置き場を読み取れません"
    return 0
  fi

  local role matched=""
  while IFS= read -r role; do
    [ -z "$role" ] && continue
    case "$file_path" in
      "$role"*) matched="$role"; break ;;
    esac
  done < <(printf '%s\n' "$roles")

  if [ -n "$matched" ]; then
    echo "許可[置き場を役割で分ける]: 書き込み先は宣言された置き場（${matched}）の下にあります"
    return 0
  fi

  echo "通知[置き場を役割で分ける]: 書き込み先が宣言されたどの置き場にも当たりません（${file_path}）"
  return 0
}

# ---- 運営文書の置き場を固定する ----
judge_operational_document_placement() {
  # $1: cwd, $2: file_path
  local cwd="$1" file_path="$2" relative base expected_dir actual_dir kind matches=0

  case "$file_path" in
    "$cwd"/*) relative="${file_path#"$cwd"/}" ;;
    /*)
      echo "対象外[運営文書の置き場を固定する]: 書き込み先は対象リポジトリの外です（${file_path}）"
      return 0
      ;;
    *) relative="${file_path#./}" ;;
  esac

  base="$(basename "$relative")"
  expected_dir=""
  kind=""

  case "$base" in
    *指示書.md)
      expected_dir="docs/tasks"
      kind="作業指示書"
      matches=$((matches + 1))
      ;;
  esac
  case "$base" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*検査*.md|[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*検証*.md|[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*進行*.md|*台帳.md)
      expected_dir="docs/tasks/work-records"
      kind="検査・検証・進行の記録または台帳"
      matches=$((matches + 1))
      ;;
  esac
  case "$base" in
    ADR-*.md|adr-*.md|*設計判断*.md)
      expected_dir="docs/decisions"
      kind="設計判断の記録"
      matches=$((matches + 1))
      ;;
  esac

  if [ "$matches" -eq 0 ]; then
    echo "対象外[運営文書の置き場を固定する]: ファイル名から運営文書の種類を確定できません（${relative}）"
    return 0
  fi
  if [ "$matches" -gt 1 ]; then
    echo "対象外[運営文書の置き場を固定する]: ファイル名が複数種類の運営文書に一致するため置き場を確定できません（${relative}）"
    return 0
  fi

  actual_dir="$(dirname "$relative")"
  if [ "$actual_dir" = "$expected_dir" ]; then
    echo "許可[運営文書の置き場を固定する]: ${kind}は定めた置き場（${expected_dir}/）にあります"
    return 0
  fi

  echo "拒否[運営文書の置き場を固定する]: ${kind}は ${expected_dir}/ に置きます（書き込み先: ${relative}）"
  return 2
}

# ---- 依存の向きを一方向に保つ ----
judge_dependency_direction() {
  # $1: cwd, $2: file_path, $3: content
  local cwd="$1" file_path="$2" content="$3"

  local override
  override="$(lookup_project_override_content "$cwd" "依存の向きを一方向に保つ")"
  if [ -z "$override" ]; then
    echo "通知[依存の向きを一方向に保つ]: このプロジェクトの規則に層の宣言がないため判定していません。リバース解析を実行すると判定の対象になります"
    return 0
  fi

  local tokens layers layer_count
  tokens="$(printf '%s' "$override" | sed 's/、/\n/g; s/,/\n/g; s/・/\n/g; s/　/\n/g; s/ /\n/g' | sed '/^[[:space:]]*$/d')"
  layers="$(printf '%s\n' "$tokens" | grep -F '/')"
  layer_count=$(printf '%s\n' "$layers" | grep -c .)
  if [ -z "$layers" ] || [ "$layer_count" -lt 2 ]; then
    echo "通知[依存の向きを一方向に保つ]: このプロジェクトの規則に宣言はありますが、層の並びを2つ以上読み取れません"
    return 0
  fi

  local own_layer="" own_index=-1 idx=0 layer
  while IFS= read -r layer; do
    [ -z "$layer" ] && { idx=$((idx + 1)); continue; }
    if [ -z "$own_layer" ]; then
      case "$file_path" in
        "$layer"*) own_layer="$layer"; own_index=$idx ;;
      esac
    fi
    idx=$((idx + 1))
  done < <(printf '%s\n' "$layers")

  if [ -z "$own_layer" ]; then
    echo "対象外[依存の向きを一方向に保つ]: 書き込み先が宣言されたどの層にも属しません（${file_path}）"
    return 0
  fi

  local imports
  imports="$(printf '%s\n' "$content" \
    | grep -oE "from[[:space:]]+['\"][^'\"]+['\"]|import[[:space:]]+['\"][^'\"]+['\"]|require\(['\"][^'\"]+['\"]\)" \
    | grep -oE "['\"][^'\"]+['\"]" \
    | sed -E "s/^['\"]//; s/['\"]\$//")"

  local outer_hit="" imp
  while IFS= read -r imp; do
    [ -z "$imp" ] && continue
    local imp_idx=0 layer2
    while IFS= read -r layer2; do
      [ -z "$layer2" ] && { imp_idx=$((imp_idx + 1)); continue; }
      case "$imp" in
        "$layer2"*)
          if [ "$imp_idx" -lt "$own_index" ]; then
            outer_hit="$layer2"
          fi
          break
          ;;
      esac
      imp_idx=$((imp_idx + 1))
    done < <(printf '%s\n' "$layers")
    [ -n "$outer_hit" ] && break
  done < <(printf '%s\n' "$imports")

  if [ -n "$outer_hit" ]; then
    echo "拒否[依存の向きを一方向に保つ]: 内側の層（${own_layer}）から外側の層（${outer_hit}）を取り込んでいます"
    return 2
  fi

  echo "許可[依存の向きを一方向に保つ]: 層をまたぐ取り込みの向きは宣言の並びに沿っています"
  return 0
}

judge() {
  # $1: file_path, $2: skip_gitignore_check, $3: content（省略可）, $4: cwd（省略可）
  # 標準出力: 判定理由（複数行）。戻り値: 0=許可・2=拒否
  local file_path="$1" skip_gitignore="${2:-0}" content="${3:-}" cwd="${4:-}"
  local msg code

  if msg="$(check_temp_file_tracked "$file_path" "$skip_gitignore")"; then code=0; else code=$?; fi
  echo "$msg"
  [ "$code" -eq 2 ] && return 2

  if msg="$(check_root_dir_allowlist "$file_path")"; then code=0; else code=$?; fi
  echo "$msg"
  [ "$code" -eq 2 ] && return 2

  if msg="$(check_deep_nesting "$file_path" "$NEST_DEPTH_LIMIT")"; then code=0; else code=$?; fi
  echo "$msg"
  [ "$code" -eq 2 ] && return 2

  if msg="$(check_sibling_casing "$file_path")"; then code=0; else code=$?; fi
  echo "$msg"
  [ "$code" -eq 2 ] && return 2

  if [ -n "$cwd" ]; then
    if msg="$(judge_operational_document_placement "$cwd" "$file_path")"; then code=0; else code=$?; fi
    echo "$msg"
    [ "$code" -eq 2 ] && return 2

    if msg="$(judge_role_separation "$cwd" "$file_path")"; then code=0; else code=$?; fi
    echo "$msg"
    [ "$code" -eq 2 ] && return 2

    if msg="$(judge_dependency_direction "$cwd" "$file_path" "$content")"; then code=0; else code=$?; fi
    echo "$msg"
    [ "$code" -eq 2 ] && return 2
  fi

  return 0
}

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${TEMP_FILE_TRACKED_SKIP_REASON:-}" ]; then
    echo "[TEMP-FILE-TRACKED-SKIP] 理由: ${TEMP_FILE_TRACKED_SKIP_REASON}"
    return 0
  fi
  return 1
}

run_hook() {
  local skip_msg
  if skip_msg="$(should_skip_with_reason)"; then
    printf '%s\n' "$skip_msg" >&2
    exit 0
  fi

  local input
  input="$(cat)"
  [ -z "$input" ] && exit 0

  local tool
  tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
  [ "$tool" != "Write" ] && exit 0

  local file_path content cwd
  file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
  [ -z "$file_path" ] && exit 0
  content=$(printf '%s' "$input" | jq -r '.tool_input.content // empty' 2>/dev/null)
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)

  local msg code
  if msg="$(judge "$file_path" 0 "$content" "$cwd")"; then code=0; else code=$?; fi

  [ "$code" -eq 0 ] && exit 0

  ctx="[TEMP-FILE-TRACKED-BLOCK] ${msg}"
  jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  printf '%s\n' "$ctx" >&2
  exit 2
}

self_test() {
  local rc=0 msg code

  # 系1: .tmp 拡張子（gitignoreチェックはスキップして名前判定のみ検査）→ 拒否
  if msg="$(judge "/repo/notes.tmp" 1)"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -q '一時ファイルをリポジトリ内へ置かない'; then
    echo "  [PASS] 系1: .tmp 拡張子は拒否される"
  else
    echo "  [FAIL] 系1: 一時ファイル名なのに許可された、または規則名が無い（exit=${code}）" >&2
    rc=1
  fi

  # 系2: .DS_Store → 拒否
  if msg="$(judge "/repo/src/.DS_Store" 1)"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系2: .DS_Store は拒否される"
  else
    echo "  [FAIL] 系2: .DS_Store なのに許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系3: 通常のソースファイル（git外のパス）→ 許可
  if msg="$(judge "/repo/src/app.ts" 1)"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系3: 通常のファイル名は許可される"
  else
    echo "  [FAIL] 系3: 一時ファイル名でないのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系4: README.md（.bak等に一致しない）→ 許可
  if msg="$(judge "/repo/README.md" 1)"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系4: README.md は許可される"
  else
    echo "  [FAIL] 系4: 通常のドキュメントなのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系5: .gitignore で除外されている一時ファイル → 対象外として許可（実ディレクトリで検証）
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-temp-file-tracked-self-test.XXXXXX")"
  ( cd "$tmp" && git init -q 2>/dev/null && printf '*.bak\n' > .gitignore )
  if msg="$(judge "$tmp/dropped.bak" 0)"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系5: .gitignore 対象は許可される"
  else
    echo "  [FAIL] 系5: .gitignore対象なのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系6: 直下を許可の一覧で管理する — 許可一覧に無い直下ディレクトリの新設 → 拒否
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-temp-file-tracked-self-test.XXXXXX")"
  ( cd "$tmp" && git init -q 2>/dev/null )
  mkdir -p "$tmp/.claude/rules/always/project-context"
  cat > "$tmp/.claude/rules/always/project-context/rule.md" <<'EOF'
## ルート直下許可ディレクトリ

| ディレクトリ名 | 用途 |
|---|---|
| src | ソースコード |
| docs | ドキュメント |
EOF
  if msg="$(judge "$tmp/scratch2/notes.md" 1)"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -q '直下を許可の一覧で管理する'; then
    echo "  [PASS] 系6: 許可一覧に無い直下ディレクトリの新設は拒否される"
  else
    echo "  [FAIL] 系6: 許可一覧に無い直下ディレクトリなのに許可された、または規則名が無い（exit=${code}）" >&2
    rc=1
  fi

  # 系7: 直下を許可の一覧で管理する — 許可一覧にあるディレクトリの直下作成 → 許可
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-temp-file-tracked-self-test.XXXXXX")"
  ( cd "$tmp" && git init -q 2>/dev/null )
  mkdir -p "$tmp/.claude/rules/always/project-context"
  cat > "$tmp/.claude/rules/always/project-context/rule.md" <<'EOF'
## ルート直下許可ディレクトリ

| ディレクトリ名 | 用途 |
|---|---|
| src | ソースコード |
| docs | ドキュメント |
EOF
  if msg="$(judge "$tmp/src/app.ts" 1)"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系7: 許可一覧にあるディレクトリへの新規ファイルは許可される"
  else
    echo "  [FAIL] 系7: 許可一覧にあるディレクトリなのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系8: 深い入れ子を作らない（5階層超）→ 拒否
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-temp-file-tracked-self-test.XXXXXX")"
  ( cd "$tmp" && git init -q 2>/dev/null )
  if msg="$(judge "$tmp/a/b/c/d/e/f/file.ts" 1)"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -q '深い入れ子を作らない'; then
    echo "  [PASS] 系8: 5階層を超える深さは拒否される"
  else
    echo "  [FAIL] 系8: 深い階層なのに許可された、または規則名が無い（exit=${code}）" >&2
    rc=1
  fi

  # 系9: 浅い階層 → 許可
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-temp-file-tracked-self-test.XXXXXX")"
  ( cd "$tmp" && git init -q 2>/dev/null )
  if msg="$(judge "$tmp/a/b/file.ts" 1)"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系9: 浅い階層は許可される"
  else
    echo "  [FAIL] 系9: 浅い階層なのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系10: 名前の付け方を階層内で揃える — kebab-case の兄弟の中に snake_case を新設 → 拒否
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-temp-file-tracked-self-test.XXXXXX")"
  ( cd "$tmp" && git init -q 2>/dev/null )
  mkdir -p "$tmp/packages/module-one" "$tmp/packages/module-two"
  if msg="$(judge "$tmp/packages/module_three/file.ts" 1)"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -q '名前の付け方を階層内で揃える'; then
    echo "  [PASS] 系10: 兄弟と異なる表記形式のディレクトリ新設は拒否される"
  else
    echo "  [FAIL] 系10: 表記が揃っていないのに許可された、または規則名が無い（exit=${code}）" >&2
    rc=1
  fi

  # 系11: 名前の付け方を階層内で揃える — 兄弟と同じ表記形式 → 許可
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-temp-file-tracked-self-test.XXXXXX")"
  ( cd "$tmp" && git init -q 2>/dev/null )
  mkdir -p "$tmp/packages/module-one" "$tmp/packages/module-two"
  if msg="$(judge "$tmp/packages/module-three/file.ts" 1)"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系11: 兄弟と同じ表記形式のディレクトリ新設は許可される"
  else
    echo "  [FAIL] 系11: 表記が揃っているのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系12: 置き場を役割で分ける — 宣言はあるが / を含む語が無い → 通知
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-temp-file-tracked-self-test.XXXXXX")"
  mkdir -p "$tmp/docs/rules/dirstructure/role-separation"
  cat > "$tmp/docs/rules/dirstructure/role-separation/rule.md" <<'EOF'
# 規約

## このプロジェクトの規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 置き場を役割で分ける | 実装とテストと文書を分ける | 観測による | 静的解析 |
EOF
  if msg="$(judge_role_separation "$tmp" "src/app.ts")"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -q '通知\[置き場を役割で分ける\]'; then
    echo "  [PASS] 系12: /を含む語が無い宣言は通知にとどまる"
  else
    echo "  [FAIL] 系12: /を含む語が無いのに通知が出なかった（exit=${code}）" >&2
    rc=1
  fi

  # 系13: 置き場を役割で分ける — 宣言が無い → 通知
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-temp-file-tracked-self-test.XXXXXX")"
  if msg="$(judge_role_separation "$tmp" "src/app.ts")"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -q '通知\[置き場を役割で分ける\]'; then
    echo "  [PASS] 系13: 宣言が無い場合は通知にとどまる"
  else
    echo "  [FAIL] 系13: 宣言が無いのに通知が出なかった（exit=${code}）" >&2
    rc=1
  fi

  # 系14: 置き場を役割で分ける — 宣言があり違反する場合 → 通知（止めない）
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-temp-file-tracked-self-test.XXXXXX")"
  mkdir -p "$tmp/docs/rules/dirstructure/role-separation"
  cat > "$tmp/docs/rules/dirstructure/role-separation/rule.md" <<'EOF'
# 規約

## このプロジェクトの規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 置き場を役割で分ける | 実装は src/、試験は tests/、文書は docs/ | 観測による | 静的解析 |
EOF
  if msg="$(judge_role_separation "$tmp" "lib/app.ts")"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -q '通知\[置き場を役割で分ける\]'; then
    echo "  [PASS] 系14: どの置き場にも当たらない場合は通知される（止めない）"
  else
    echo "  [FAIL] 系14: 当たらないのに通知が出なかった、または誤って止められた（exit=${code}）" >&2
    rc=1
  fi

  # 系15: 置き場を役割で分ける — 宣言があり満たしている場合 → 許可
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-temp-file-tracked-self-test.XXXXXX")"
  mkdir -p "$tmp/docs/rules/dirstructure/role-separation"
  cat > "$tmp/docs/rules/dirstructure/role-separation/rule.md" <<'EOF'
# 規約

## このプロジェクトの規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 置き場を役割で分ける | 実装は src/、試験は tests/、文書は docs/ | 観測による | 静的解析 |
EOF
  if msg="$(judge_role_separation "$tmp" "src/app.ts")"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -q '許可\[置き場を役割で分ける\]'; then
    echo "  [PASS] 系15: 宣言された置き場の下にあれば許可される"
  else
    echo "  [FAIL] 系15: 置き場の下にあるのに許可されなかった（exit=${code}）" >&2
    rc=1
  fi

  # 系16: 依存の向きを一方向に保つ — 対象でない場合 → 対象外
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-temp-file-tracked-self-test.XXXXXX")"
  mkdir -p "$tmp/docs/rules/dirstructure/dependency-direction"
  cat > "$tmp/docs/rules/dirstructure/dependency-direction/rule.md" <<'EOF'
# 規約

## このプロジェクトの規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 依存の向きを一方向に保つ | 層の並びは ui/、domain/、data/ | 観測による | 静的解析 |
EOF
  if msg="$(judge_dependency_direction "$tmp" "lib/app.ts" 'export const z = 1;')"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -q '対象外\[依存の向きを一方向に保つ\]'; then
    echo "  [PASS] 系16: 宣言された層に属さない書き込み先は対象外になる"
  else
    echo "  [FAIL] 系16: 層に属さないのに対象外の判定が出なかった（exit=${code}）" >&2
    rc=1
  fi

  # 系17: 依存の向きを一方向に保つ — 宣言が無い → 通知
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-temp-file-tracked-self-test.XXXXXX")"
  if msg="$(judge_dependency_direction "$tmp" "ui/App.ts" 'export const z = 1;')"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -q '通知\[依存の向きを一方向に保つ\]'; then
    echo "  [PASS] 系17: 宣言が無い場合は通知にとどまる"
  else
    echo "  [FAIL] 系17: 宣言が無いのに通知が出なかった（exit=${code}）" >&2
    rc=1
  fi

  # 系18: 依存の向きを一方向に保つ — 宣言があり違反する場合 → 拒否
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-temp-file-tracked-self-test.XXXXXX")"
  mkdir -p "$tmp/docs/rules/dirstructure/dependency-direction"
  cat > "$tmp/docs/rules/dirstructure/dependency-direction/rule.md" <<'EOF'
# 規約

## このプロジェクトの規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 依存の向きを一方向に保つ | 層の並びは ui/、domain/、data/ | 観測による | 静的解析 |
EOF
  if msg="$(judge_dependency_direction "$tmp" "data/repo.ts" 'import { x } from "ui/Something";')"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -q '拒否\[依存の向きを一方向に保つ\]'; then
    echo "  [PASS] 系18: 内側の層から外側の層を取り込むと拒否される"
  else
    echo "  [FAIL] 系18: 逆向きの取り込みなのに拒否されなかった（exit=${code}）" >&2
    rc=1
  fi

  # 系19: 依存の向きを一方向に保つ — 宣言があり満たしている場合 → 許可
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-temp-file-tracked-self-test.XXXXXX")"
  mkdir -p "$tmp/docs/rules/dirstructure/dependency-direction"
  cat > "$tmp/docs/rules/dirstructure/dependency-direction/rule.md" <<'EOF'
# 規約

## このプロジェクトの規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 依存の向きを一方向に保つ | 層の並びは ui/、domain/、data/ | 観測による | 静的解析 |
EOF
  if msg="$(judge_dependency_direction "$tmp" "data/repo.ts" 'import { helper } from "./helper";
export const z = 1;')"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -q '許可\[依存の向きを一方向に保つ\]'; then
    echo "  [PASS] 系19: 宣言の並びに沿っていれば許可される"
  else
    echo "  [FAIL] 系19: 並びに沿っているのに許可されなかった（exit=${code}）" >&2
    rc=1
  fi

  # 系20: 運営文書の置き場を固定する — 指示書が docs/tasks/ 直下なら許可
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-temp-file-tracked-self-test.XXXXXX")"
  if msg="$(judge_operational_document_placement "$tmp" "docs/tasks/作業指示書.md")"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -q '許可\[運営文書の置き場を固定する\]'; then
    echo "  [PASS] 系20: 指示書は docs/tasks/ 直下で許可される"
  else
    echo "  [FAIL] 系20: 指示書の正しい置き場が許可されない（exit=${code}）" >&2
    rc=1
  fi

  # 系21: 運営文書の置き場を固定する — 指示書が別の場所なら拒否
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-temp-file-tracked-self-test.XXXXXX")"
  if msg="$(judge_operational_document_placement "$tmp" "docs/作業指示書.md")"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -q '拒否\[運営文書の置き場を固定する\]'; then
    echo "  [PASS] 系21: 指示書を定めた場所以外へ置くと拒否される"
  else
    echo "  [FAIL] 系21: 指示書の誤った置き場が拒否されない（exit=${code}）" >&2
    rc=1
  fi

  # 系22: 運営文書の置き場を固定する — 日付付き検証記録が work-records なら許可
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-temp-file-tracked-self-test.XXXXXX")"
  if msg="$(judge_operational_document_placement "$tmp" "docs/tasks/work-records/2026-08-23-配る規約の検証.md")"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -q '許可\[運営文書の置き場を固定する\]'; then
    echo "  [PASS] 系22: 日付付き検証記録は work-records で許可される"
  else
    echo "  [FAIL] 系22: 検証記録の正しい置き場が許可されない（exit=${code}）" >&2
    rc=1
  fi

  # 系23: 運営文書の置き場を固定する — 台帳が work-records なら許可
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-temp-file-tracked-self-test.XXXXXX")"
  if msg="$(judge_operational_document_placement "$tmp" "docs/tasks/work-records/運営台帳.md")"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -q '許可\[運営文書の置き場を固定する\]'; then
    echo "  [PASS] 系23: 台帳は work-records で許可される"
  else
    echo "  [FAIL] 系23: 台帳の正しい置き場が許可されない（exit=${code}）" >&2
    rc=1
  fi

  # 系24: 運営文書の置き場を固定する — ADRが docs/decisions なら許可
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-temp-file-tracked-self-test.XXXXXX")"
  if msg="$(judge_operational_document_placement "$tmp" "docs/decisions/ADR-storage.md")"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -q '許可\[運営文書の置き場を固定する\]'; then
    echo "  [PASS] 系24: ADRは docs/decisions で許可される"
  else
    echo "  [FAIL] 系24: ADRの正しい置き場が許可されない（exit=${code}）" >&2
    rc=1
  fi

  # 系25: 運営文書の置き場を固定する — 設計判断を別の場所へ置くと拒否
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-temp-file-tracked-self-test.XXXXXX")"
  if msg="$(judge_operational_document_placement "$tmp" "docs/設計判断.md")"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -q '拒否\[運営文書の置き場を固定する\]'; then
    echo "  [PASS] 系25: 設計判断を定めた場所以外へ置くと拒否される"
  else
    echo "  [FAIL] 系25: 設計判断の誤った置き場が拒否されない（exit=${code}）" >&2
    rc=1
  fi

  # 系26: 複数種類に一致する名前は対象外
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-temp-file-tracked-self-test.XXXXXX")"
  if msg="$(judge_operational_document_placement "$tmp" "docs/tasks/2026-08-23-検証指示書.md")"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -q '対象外\[運営文書の置き場を固定する\]'; then
    echo "  [PASS] 系26: 複数種類に一致する名前は対象外になる"
  else
    echo "  [FAIL] 系26: 曖昧な名前を対象外として区別できない（exit=${code}）" >&2
    rc=1
  fi

  # 系27: 環境変数に理由を設定すると should_skip_with_reason は skip する
  local skip_out skip_code
  if skip_out="$(TEMP_FILE_TRACKED_SKIP_REASON="テスト理由" should_skip_with_reason)"; then skip_code=0; else skip_code=$?; fi
  if [ "$skip_code" -eq 0 ] && printf '%s' "$skip_out" | grep -qF 'TEMP-FILE-TRACKED-SKIP' && printf '%s' "$skip_out" | grep -qF 'テスト理由'; then
    echo "  [PASS] 系27: 理由を設定すると should_skip_with_reason は skip する（${skip_out}）"
  else
    echo "  [FAIL] 系27: 理由があるのに skip しない、またはタグ・理由が含まれない（exit=${skip_code}, ${skip_out}）" >&2
    rc=1
  fi

  # 系28: 環境変数を空文字にすると should_skip_with_reason は skip しない
  local skip_code2
  if TEMP_FILE_TRACKED_SKIP_REASON="" should_skip_with_reason >/dev/null 2>&1; then skip_code2=0; else skip_code2=$?; fi
  if [ "$skip_code2" -eq 1 ]; then
    echo "  [PASS] 系28: 環境変数が空文字なら should_skip_with_reason は skip しない"
  else
    echo "  [FAIL] 系28: 空文字なのに skip した（exit=${skip_code2}）" >&2
    rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

case "${1:-}" in
  --self-test) self_test; exit $? ;;
  *) run_hook ;;
esac
