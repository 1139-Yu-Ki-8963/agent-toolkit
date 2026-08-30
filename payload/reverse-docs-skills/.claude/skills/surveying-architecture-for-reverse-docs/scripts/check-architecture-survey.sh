#!/usr/bin/env bash
set -euo pipefail

# check-architecture-survey.sh — アーキテクチャ調査書の機械ゲート（7検査すべて決定的）
#
# 使い方:
#   check-architecture-survey.sh <調査書パス> <target_repo_path>
#   check-architecture-survey.sh --self-test
#
# 検査:
#   1. 記載パス実在100%: 調査書内のbacktick囲みトークンのうち「/」を含む相対パスとみなせるものを
#      抽出し、全件 target_repo_path 配下に test -e で実在確認する。URL（://）・glob（* ?）・
#      プレースホルダ（< >）・絶対パス（先頭/）・空白/正規表現記号を含むトークン（grepパターン等の
#      コード例）は対象外とする。トークンが否定文脈マーカー「非実在:」で始まる場合
#      （例: `非実在:.github/workflows/ci.yml`）も対象外とする。これは「このパスは実在しない」と
#      本文で明示的に述べるための記法であり、実在チェックを免除する（改善課題1-115）。
#   2. 6種別網羅: 画面・API・テーブル・バッチ・帳票・外部連携の6語すべてについて、種別名と
#      判定語（実在する / 実在しない（）が同一行に存在する判定行があるか確認する。加えて、
#      §6ユニット種別判定テーブルの検出手がかり列に記録されたgrep/rg/find系コマンドを実際に
#      target_repo_path に対して再実行し、「実在する」なら1件以上・「実在しない」なら0件を
#      返すことを確認する（改善課題1-140）。検索系コマンド以外・手がかり未記載（「-」等）は
#      再実行せず検証不能として通過扱いにする。非UTF-8ファイルは detect-encoding.sh で
#      UTF-8変換した一時ミラーに対して再実行する。§6テーブル行の列分割はbacktickスパン内の
#      「|」を区切りとして扱わない（検出手がかりのgrepパターンがOR条件で「|」を含む場合の
#      列崩れ対策。改善課題キー: アーキ調査ゲート-パイプで検証不能）。検索系コマンドの
#      安全判定も同様にクオート外の実際のシェル連結記号（; & | ` $( ）のみを再実行対象外とし、
#      クオート内の「|」（OR条件）は連結とみなさない。
#   3. 推測語ゼロ: おそらく|と思われ|かもしれ|推測|たぶん|恐らく|でしょう|のはず が0件。
#   4. テンプレ残存ゼロ: <実測|<FILL|TBD|TODO|（調査結果を記入） が0件（§9テスト基盤のプレースホルダ残存を含む）。
#   5. §4ディレクトリ網羅: §1のfindコマンドから走査範囲を決定的に再現し、直接ファイルを
#      持つディレクトリがすべて§4（責務マップ本体または対象外ディレクトリ）もしくは
#      §4に列挙された層の子ディレクトリとして包含されることを確認する。
#   6. §10プロジェクト形態: §10節が存在し、プロジェクト形態が「単独プロジェクト」または
#      「モノレポ」のいずれかであり、サイト一覧に1行以上あって各ルートディレクトリが
#      target_repo_path配下に実在し、サイトキーが重複していないことを確認する。
#      参照先列の書式は検査しない（パス実在は検査1が担当する）。
#   7. §8申し送りエンコーディング実測整合: §8後続工程への申し送りに記載された
#      「エンコーディング-」始まりのキー行について、内容セルの先頭backtickトークンを
#      エンコーディング名、後続のbacktickトークンを対象ファイル群として抽出し、
#      各ファイルが実バイトでそのエンコーディング名により復号できることを
#      detect-encoding.sh decodable で確認する（改善課題1-126）。UNKNOWNと記載された
#      行は復号可否検査の対象外とする（UNKNOWNは明示的な判定不能の申告であり、検証不能な
#      値との復号照合はできないため）。
#
#   いずれか1件でも違反があれば exit 1（fail-closed）。実行不能だけならexit 2、全件PASSでexit 0。
#   --self-test は合成フィクスチャで陽性exit 0・陰性(検査ごと)exit 1を自己検証する。
#
# 設計判断（ADR）の正本は本スキルの SKILL.md「## 設計判断」に記載する。
# 保守責任者: 人手（ユーザー）。検査基準・除外規則を変更した時に更新する。
# macOS bash 3.2 互換（mapfile 不使用）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DETECT_ENCODING_SH="$SCRIPT_DIR/../../../../generation-engine/scripts/detect-encoding.sh"

UNIT_KINDS="画面 API テーブル バッチ 帳票 外部連携"
GUESS_WORDS_RE='おそらく|と思われ|かもしれ|推測|たぶん|恐らく|でしょう|のはず'
PLACEHOLDER_RE='<実測|<FILL|TBD|TODO|調査結果を記入'
# 実在しないことを述べるための否定文脈マーカー（改善課題1-115）。backtickトークンの先頭に
# このマーカーを付けると（例: `非実在:src/legacy/old.ts`）、検査1の実在チェックを免除する。
NOT_EXIST_MARKER="非実在:"
MIRROR_MAX_BYTES_DEFAULT=1073741824
MIRROR_TMP_ROOT="${TMPDIR:-/tmp}"
REGISTERED_MIRRORS=""
PREPARED_MIRROR=""
CHECK_PASS_COUNT=0
CHECK_FAIL_COUNT=0
CHECK_UNKNOWN_COUNT=0
MIRROR_ACTIVE_CHILD_PID=""

# 一時ミラーは、このプロセスがmktemp直後に登録したarchitecture-survey-mirrorだけを
# 削除する。単純なrm -rf "${TMPDIR:-/tmp}"やglobを使わないのは、過去の残留物や
# 他プロセスのミラーを巻き込まず、TERM/INT時にも所有権を証明できる対象だけを消すため。
cleanup_registered_mirrors() {
  registered="$REGISTERED_MIRRORS"
  while IFS= read -r registered_mirror; do
    [ -z "$registered_mirror" ] && continue
    case "$registered_mirror" in
      "$MIRROR_TMP_ROOT"/architecture-survey-mirror.*)
        if [ -d "$registered_mirror" ] && [ ! -L "$registered_mirror" ]; then
          rm -rf -- "$registered_mirror"
        fi
        ;;
    esac
  done <<CLEANUP_MIRRORS
$registered
CLEANUP_MIRRORS
  REGISTERED_MIRRORS=""
}

handle_mirror_signal() {
  signal_status="$1"
  if [ -n "$MIRROR_ACTIVE_CHILD_PID" ]; then
    kill -TERM "$MIRROR_ACTIVE_CHILD_PID" 2>/dev/null || true
    wait "$MIRROR_ACTIVE_CHILD_PID" 2>/dev/null || true
    MIRROR_ACTIVE_CHILD_PID=""
  fi
  cleanup_registered_mirrors
  trap - EXIT INT TERM
  exit "$signal_status"
}

trap cleanup_registered_mirrors EXIT
trap 'handle_mirror_signal 130' INT
trap 'handle_mirror_signal 143' TERM

# backtick囲みトークンのうち「相対パス」とみなせるもの以外を除外する判定。
# 除外: 「/」を含まない / URL / glob / プレースホルダ / 絶対パス / 空白・正規表現記号を含む /
#       否定文脈マーカー（非実在:）で始まる
is_path_candidate() {
  tok="$1"
  case "$tok" in
    "${NOT_EXIST_MARKER}"*) return 1 ;;
  esac
  case "$tok" in
    */*) : ;;
    *) return 1 ;;
  esac
  case "$tok" in
    *'://'*|*'*'*|*'?'*|*'<'*|*'>'*|/*|*' '*|*'\'*|*'"'*|*"'"*|*'('*|*')'*|*'|'*|*'['*|*']'*|*'^'*|*'$'*|*'+'*|*'{'*|*'}'*)
      return 1 ;;
  esac
  return 0
}

extract_path_tokens() {
  grep -oE '`[^`]+`' "$1" 2>/dev/null | sed -E 's/^`//; s/`$//'
}

# 表の行を「|」で列分割する。backtick（`）で囲まれた区間内の「|」は列区切りとして
# 扱わない。素朴な awk -F'|' は、検出手がかりのgrepパターンがOR条件（例:
# `grep -rlE "cron|schedule" src`）で「|」を含む場合に列がずれて崩れる（改善課題
# アーキ調査ゲート-パイプで検証不能）。$1=行 $2=欲しい列番号（awk -F'|'と同じ
# 番号付け。行頭の空セルが1、以降2,3,4...）。
table_col() {
  LC_ALL=C awk -v col="$2" '
  {
    n = length($0)
    idx = 1
    buf = ""
    inbt = 0
    for (i = 1; i <= n; i++) {
      c = substr($0, i, 1)
      if (c == "`") { inbt = !inbt; buf = buf c; continue }
      if (c == "|" && inbt == 0) {
        if (idx == col) { print buf; exit }
        idx++
        buf = ""
        continue
      }
      buf = buf c
    }
    if (idx == col) print buf
  }' <<<"$1"
}

# コマンド文字列のうち、シングル/ダブルクオート内ではない位置にシェル連結記号
# （; & | < > ` $( ）があるかを判定する。クオート内の同じ文字（grepのOR条件 `|` 等）は
# コマンド連結とみなさない。真（連結あり）なら0、偽（連結なし）なら1を返す。
has_unquoted_shell_chain() {
  cmd="$1"
  n=${#cmd}
  i=0
  q=""
  while [ "$i" -lt "$n" ]; do
    c="${cmd:$i:1}"
    if [ -n "$q" ]; then
      [ "$c" = "$q" ] && q=""
    else
      case "$c" in
        "'"|'"') q="$c" ;;
        ';'|'&'|'|'|'<'|'>'|'`') return 0 ;;
        '$')
          nc="${cmd:$((i + 1)):1}"
          [ "$nc" = "(" ] && return 0
          ;;
      esac
    fi
    i=$((i + 1))
  done
  return 1
}

# §1 調査メタ節を抽出する（### サブ見出しを含む）
extract_section_meta() {
  LC_ALL=C awk '/^## .*調査メタ/{f=1;next} /^## [^#]|^---$/{if(f)exit} f' "$1"
}

# §4 ディレクトリ責務マップの本体テーブルのみ抽出する（### 対象外ディレクトリの手前で停止）
extract_section4() {
  LC_ALL=C awk '/^## .*ディレクトリ責務マップ/{f=1;next} /^## [^#]|^### |^---$/{if(f)exit} f' "$1"
}

# §4 内の「### 対象外ディレクトリ」サブセクションを抽出する
extract_excluded_dirs() {
  LC_ALL=C awk '/^### .*対象外ディレクトリ/{f=1;next} /^## [^#]|^---$/{if(f)exit} f' "$1"
}

# §10 プロジェクト形態とサイト構成節を抽出する（### サブ見出しを含む）
extract_section10() {
  LC_ALL=C awk '/^## .*プロジェクト形態とサイト構成/{f=1;next} /^## [^#]/{if(f)exit} f' "$1"
}

# §6 ユニット種別判定の本体テーブルを抽出する（1-140: 検出手がかりの再実行に使う）
extract_section6() {
  LC_ALL=C awk '/^## .*ユニット種別判定/{f=1;next} /^## [^#]|^---$/{if(f)exit} f' "$1"
}

# §8 後続工程への申し送り節を抽出する（1-126: エンコーディング申し送りの実測整合に使う）
extract_section8() {
  LC_ALL=C awk '/^## .*後続工程への申し送り/{f=1;next} /^## [^#]|^---$/{if(f)exit} f' "$1"
}

# 実測では3.9GiB・96,660ファイルの全体複製が9分半でも検査1から進まず、判定を
# 返せなかった。したがって、この処理を全体cpへ戻さず、grep/findの引数をshlexで
# 分解して実際に読む相対パスだけを抽出する。
# オプション値をパスと誤認すると無関係な範囲を複製するため、未対応・曖昧な構文は
# 全体複製へ倒さず判定不能にする。親パスが含まれる子パスはここで除き、同じ木を1回だけ扱う。
extract_hint_paths() {
  python3 - "$1" <<'PY'
import posixpath
import shlex
import sys

cmd = sys.argv[1]
try:
    tokens = shlex.split(cmd, posix=True)
except ValueError:
    sys.exit(2)
if not tokens or tokens[0] not in {"grep", "find"}:
    sys.exit(2)

command = tokens[0]
args = tokens[1:]
paths = []
if command == "find":
    i = 0
    while i < len(args):
        arg = args[i]
        if arg in {"-H", "-L", "-P"} or arg.startswith("-O"):
            i += 1
            continue
        if arg == "-D":
            if i + 1 >= len(args):
                sys.exit(2)
            i += 2
            continue
        break
    for arg in args[i:]:
        if arg == "--":
            continue
        if arg.startswith("-") or arg in {"!", "(", ")"}:
            break
        paths.append(arg)
    if not paths:
        paths = ["."]
else:
    value_options = {
        "--after-context", "--before-context", "--binary-files",
        "--color", "--context", "--directories",
        "--exclude", "--exclude-dir", "--field-context-separator",
        "--field-match-separator", "--file", "--include", "--label",
        "--max-count", "--regexp"
    }
    boolean_options = {
        "--binary", "--block-buffered", "--byte-offset", "--column",
        "--count", "--debug",
        "--files-with-matches", "--files-without-match", "--fixed-strings",
        "--follow", "--invert-match", "--line-buffered", "--line-number",
        "--no-filename", "--no-messages", "--null", "--null-data",
        "--only-matching", "--quiet", "--recursive", "--text",
        "--version",
        "--with-filename", "--word-regexp", "--extended-regexp",
        "--basic-regexp", "--perl-regexp", "--line-regexp", "--files-without-match"
    }
    grep_value_short = set("ABCdefm")
    grep_boolean_short = set("EFGHILPRUVZabchilnoqrsuvwxyz")
    pattern_from_option = False
    files_mode = False
    operands = []
    i = 0
    options_done = False
    while i < len(args):
        arg = args[i]
        if not options_done and arg == "--":
            options_done = True
            i += 1
            continue
        if not options_done and arg.startswith("--"):
            opt = arg.split("=", 1)[0]
            if opt in {"-e", "--regexp", "-f", "--file"}:
                pattern_from_option = True
            if opt in value_options and "=" not in arg:
                if i + 1 >= len(args):
                    sys.exit(2)
                i += 2
            elif opt in value_options or opt in boolean_options:
                i += 1
            else:
                sys.exit(2)
            continue
        if not options_done and arg.startswith("-") and arg != "-":
            value_short = grep_value_short
            boolean_short = grep_boolean_short
            short = arg[1:]
            pos = 0
            consumed_next = False
            while pos < len(short):
                flag = short[pos]
                if flag in value_short:
                    if flag in {"e", "f"}:
                        pattern_from_option = True
                    if pos + 1 == len(short):
                        if i + 1 >= len(args):
                            sys.exit(2)
                        consumed_next = True
                    break
                if flag not in boolean_short:
                    sys.exit(2)
                pos += 1
            i += 2 if consumed_next else 1
            continue
        operands.append(arg)
        i += 1
    if files_mode:
        paths = operands or ["."]
    elif pattern_from_option:
        paths = operands
    elif operands:
        paths = operands[1:]
    if not paths:
        sys.exit(2)

normalized = []
for path in paths:
    if (not path or path.startswith("/") or "\n" in path
            or any(marker in path for marker in ("*", "?", "[", "$", "~"))):
        sys.exit(2)
    norm = posixpath.normpath(path)
    if norm == ".." or norm.startswith("../"):
        sys.exit(2)
    if norm not in normalized:
        normalized.append(norm)

selected = []
for path in sorted(normalized, key=lambda p: (p.count("/"), len(p), p)):
    if any(parent == "." or path == parent or path.startswith(parent + "/") for parent in selected):
        continue
    selected.append(path)
for path in selected:
    print(path)
PY
}

# 外部cp・エンコーディング変換はバックグラウンド子として待つ。bashは同期実行中の
# 外部コマンドが終わるまでtrapを遅延するため、wait builtinを割り込み点にし、signal時は
# 所有する子だけを止めてからミラーを削除する。
run_mirror_child() {
  "$@" &
  MIRROR_ACTIVE_CHILD_PID=$!
  if wait "$MIRROR_ACTIVE_CHILD_PID"; then
    child_status=0
  else
    child_status=$?
  fi
  MIRROR_ACTIVE_CHILD_PID=""
  return "$child_status"
}

logical_file_size() {
  size_path="$1"
  wc -c < "$size_path" | tr -d '[:space:]'
}

# 重複除去済みの対象木だけを走査し、通常ファイルの論理バイト数を測る。
# 疎ファイルも実サイズでなく論理サイズによって1GiB上限へ掛ける必要がある。findは
# シンボリックリンクをたどらず、POSIXのwcで環境に依存せず測る。
measure_hint_paths() {
  measure_repo="$1"
  measure_paths="$2"
  total_bytes=0
  while IFS= read -r measure_path; do
    [ -z "$measure_path" ] && continue
    full_measure_path="$measure_repo/$measure_path"
    if [ -f "$full_measure_path" ] && [ ! -L "$full_measure_path" ]; then
      file_bytes="$(logical_file_size "$full_measure_path")" || return 2
      total_bytes=$((total_bytes + file_bytes))
    elif [ -d "$full_measure_path" ] && [ ! -L "$full_measure_path" ]; then
      subtree_bytes="$(find "$full_measure_path" -type f -exec wc -c {} \; 2>/dev/null | awk '{s += $1} END {printf "%.0f", s + 0}')"
      case "$subtree_bytes" in ''|*[!0-9]*) return 2 ;; esac
      total_bytes=$((total_bytes + subtree_bytes))
    fi
  done <<MEASURE_PATHS
$measure_paths
MEASURE_PATHS
  printf '%s\n' "$total_bytes"
}

create_utf8_mirror() {
  if ! mirror="$(mktemp -d "$MIRROR_TMP_ROOT/architecture-survey-mirror.XXXXXX")" || [ -z "$mirror" ]; then
    echo "[UNKNOWN] mktempによる一時ミラー作成に失敗したため判定できません（一時領域への書き込み権限またはサンドボックス制約を確認してください）: $MIRROR_TMP_ROOT" >&2
    return 2
  fi
  case "$mirror" in
    "$MIRROR_TMP_ROOT"/architecture-survey-mirror.*) ;;
    *)
      echo "[UNKNOWN] mktempが想定外のパスを返しました: $mirror" >&2
      return 2
      ;;
  esac
  # コマンド置換の子で作らず、親が複製開始前に登録することでシグナルとの隙間を無くす。
  REGISTERED_MIRRORS="${REGISTERED_MIRRORS}${REGISTERED_MIRRORS:+
}$mirror"
  PREPARED_MIRROR="$mirror"
}

unregister_and_remove_mirror() {
  remove_mirror="$1"
  case "$remove_mirror" in
    "$MIRROR_TMP_ROOT"/architecture-survey-mirror.*)
      [ -d "$remove_mirror" ] && [ ! -L "$remove_mirror" ] && rm -rf -- "$remove_mirror"
      ;;
  esac
  kept_mirrors=""
  while IFS= read -r kept_mirror; do
    [ -z "$kept_mirror" ] && continue
    [ "$kept_mirror" = "$remove_mirror" ] && continue
    kept_mirrors="${kept_mirrors}${kept_mirrors:+
}$kept_mirror"
  done <<REGISTERED_LIST
$REGISTERED_MIRRORS
REGISTERED_LIST
  REGISTERED_MIRRORS="$kept_mirrors"
}

prepare_utf8_mirror() {
  src="$1"
  mirror="$2"
  selected_paths="$3"
  copied_count=0
  while IFS= read -r selected_path; do
    [ -z "$selected_path" ] && continue
    # 検査2はproject-portal/（build-portal.shが生成する閲覧用ポータル出力）を
    # 検出対象に含めない。調査書から派生したHTMLが本文全体をJSON文字列として
    # 埋め込むため、調査書自身の例示文字列（帳票・外部連携の検出パターン等）と
    # 自己一致し検査2を誤って不合格にする（実測 2026-08-31）。
    case "$selected_path" in
      project-portal|project-portal/*|*/project-portal|*/project-portal/*)
        continue
        ;;
    esac
    source_path="$src/$selected_path"
    target_path="$mirror/$selected_path"
    if [ -d "$source_path" ] && [ ! -L "$source_path" ]; then
      mkdir -p "$target_path" || return 2
      mirror_cp_command="${ARCHITECTURE_SURVEY_MIRROR_TEST_CP_COMMAND:-cp}"
      run_mirror_child "$mirror_cp_command" -R -P "$source_path/." "$target_path/" || return 2
      # 「.」等、project-portalを内包しうる木を複製した場合はここで取り除く
      # （上のcase文は選択パス自体がproject-portalそのものを指す場合だけを防ぐため）。
      if [ -e "$target_path/project-portal" ] || [ -L "$target_path/project-portal" ]; then
        rm -rf -- "$target_path/project-portal"
      fi
    elif [ -e "$source_path" ] || [ -L "$source_path" ]; then
      mkdir -p "$(dirname "$target_path")" || return 2
      mirror_cp_command="${ARCHITECTURE_SURVEY_MIRROR_TEST_CP_COMMAND:-cp}"
      run_mirror_child "$mirror_cp_command" -P "$source_path" "$target_path" || return 2
    fi
    copied_count=$((copied_count + 1))
  done <<COPY_PATHS
$selected_paths
COPY_PATHS

  files="$(find "$mirror" -type f 2>/dev/null || true)"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    encoding_result_file="${f}.encodingcheck"
    if run_mirror_child bash "$DETECT_ENCODING_SH" encoding "$f" >"$encoding_result_file" 2>/dev/null; then
      enc="$(awk 'NR==1 {print; exit}' "$encoding_result_file")"
    else
      enc=""
    fi
    rm -f "$encoding_result_file"
    if [ -n "$enc" ] && [ "$enc" != "UTF-8" ]; then
      if run_mirror_child bash "$DETECT_ENCODING_SH" to-utf8 "$f" "${f}.utf8mirrortmp" 2>/dev/null; then
        mv "${f}.utf8mirrortmp" "$f" || return 2
      fi
    fi
  done <<MIRRORFILES
$files
MIRRORFILES
}

# 検査1: 記載パス実在100%
check_paths_exist() {
  survey="$1"
  repo="$2"
  missing=0
  total=0
  tokens="$(extract_path_tokens "$survey")"
  while IFS= read -r tok; do
    [ -z "$tok" ] && continue
    if ! is_path_candidate "$tok"; then
      continue
    fi
    total=$((total + 1))
    checkpath="$tok"
    case "$checkpath" in
      ./*) checkpath="${checkpath#./}" ;;
    esac
    if [ ! -e "$repo/$checkpath" ]; then
      echo "  未実在: $tok" >&2
      missing=$((missing + 1))
    fi
  done <<EOF
$tokens
EOF
  if [ "$missing" -gt 0 ]; then
    echo "検査1失敗: 記載パス $total 件中 $missing 件が target_repo_path 配下に実在しません" >&2
    return 1
  fi
  echo "検査1通過: 記載パス $total 件すべて実在（対象0件を含む）"
  return 0
}

# 検査2: 6種別網羅（判定語が同一行に存在するか）＋ 検出手がかりの再実行整合（1-140）
# repo（第2引数）は任意。単体で呼び出す既存の使い方（判定行の存否のみ検査）を壊さないため、
# repo指定時のみ§6検出手がかりの再実行整合チェックを追加で行う。
check_unit_kinds() {
  survey="$1"
  # 引数名はhint_repoとし、他検査（check_directory_coverage等）が使うグローバル変数
  # repoを本関数が上書きしないようにする（単一引数の既存呼び出しでrepoが空文字に
  # クリアされ、後続検査が壊れる事故を防ぐ）。
  hint_repo="${2:-}"
  missing=0
  for k in $UNIT_KINDS; do
    line="$(grep -F -- "$k" "$survey" 2>/dev/null | grep -E '実在する|実在しない（' || true)"
    if [ -z "$line" ]; then
      echo "  種別未判定: ${k}（種別名と判定語「実在する」または「実在しない（」が同一行に無い）" >&2
      missing=$((missing + 1))
    fi
  done
  if [ "$missing" -gt 0 ]; then
    echo "検査2失敗: 6種別中 $missing 種別の判定行が見つかりません" >&2
    return 1
  fi

  hint_bad=0
  hint_unknown=0
  LAST_UNKNOWN_COUNT=0
  if [ -n "$hint_repo" ]; then
    mirror_max_raw="${ARCHITECTURE_SURVEY_MIRROR_MAX_BYTES:-$MIRROR_MAX_BYTES_DEFAULT}"
    # シェル算術の範囲外を比較すると上限判定を迂回するため、正の符号付き64bit整数へ正規化する。
    if ! mirror_max_bytes="$(python3 - "$mirror_max_raw" <<'PY'
import sys
raw = sys.argv[1]
if not raw.isascii() or not raw.isdigit():
    sys.exit(2)
value = int(raw)
if value <= 0 or value > 9223372036854775807:
    sys.exit(2)
print(value)
PY
)" || [ -z "$mirror_max_bytes" ]; then
      echo "[UNKNOWN] 検査2: ARCHITECTURE_SURVEY_MIRROR_MAX_BYTESは1以上9223372036854775807以下の整数で指定してください: ${mirror_max_raw}" >&2
      LAST_UNKNOWN_COUNT=1
      return 2
    fi
    s6="$(extract_section6 "$survey")"
    while IFS= read -r line6; do
      [ -z "$line6" ] && continue
      case "$line6" in '|'*) ;; *) continue ;; esac
      case "$line6" in *'|---|'*) continue ;; esac

      kind_cell="$(table_col "$line6" 2 | sed -E 's/^[ \t]+//; s/[ \t]+$//')"
      is_kind=0
      for k in $UNIT_KINDS; do
        if [ "$kind_cell" = "$k" ]; then
          is_kind=1
          break
        fi
      done
      if [ "$is_kind" -eq 0 ]; then
        continue
      fi

      verdict_cell="$(table_col "$line6" 3 | sed -E 's/^[ \t]+//; s/[ \t]+$//')"
      hint_cell="$(table_col "$line6" 4 | sed -E 's/^[ \t]+//; s/[ \t]+$//')"

      case "$verdict_cell" in
        実在する*) expect="positive" ;;
        実在しない*) expect="zero" ;;
        *) continue ;;
      esac

      hint_cmd="$(echo "$hint_cell" | grep -oE '`[^`]+`' 2>/dev/null | head -1 | sed 's/^`//; s/`$//' || true)"
      # Markdownの表記法では、セル内容がバッククォート区間内であっても「|」は列区切りとの
      # 混同を避けるため「\|」とエスケープして書く決まりがある（GFMの表拡張仕様。表行の
      # 列分割は行の生テキストに対して行われ、コードスパンの解釈より前に起こるため）。
      # 本スクリプトの table_col はバッククォート区間を自前で判定して分割するため、この
      # エスケープは分割の可否そのものには不要だが、抽出したコマンド文字列には「\|」が
      # 文字どおり残る。この状態でシェルへ渡すと、二重引用符内のバックスラッシュはそのまま
      # 保持されるため grep -E は「\|」を「エスケープされた選択（alternation）」つまり
      # リテラルの「|」1文字と解釈し、OR条件が消えて検出0件になる（改善課題: 検証コマンド-
      # 表のエスケープを解釈しない）。Markdownの表エスケープが対象とするのは「|」のみで、
      # 他の文字への汎用エスケープ規約はGFM表仕様に存在しないため、ここでは「\|」→「|」の
      # 変換だけを行う。正規表現中の他のバックスラッシュ（例: 「\.」）はMarkdown側の表記法
      # エスケープではなくgrep側のメタ文字エスケープであり、書き換えない。
      if [ -n "$hint_cmd" ]; then
        hint_cmd="$(printf '%s' "$hint_cmd" | sed 's/\\|/|/g')"
      fi
      if [ -z "$hint_cmd" ] || [ "$hint_cmd" = "-" ]; then
        echo "  検証不能: ${kind_cell}の検出手がかりが記録されていないため再実行できません（そのまま通過）" >&2
        continue
      fi

      # 安全のため検索系(grep/find)で始まるコマンドのみ再実行する。
      # クオート外にシェル連結記号（; & | ` $( ）がある場合も、
      # 「検索系コマンドのみ」とはみなさず再実行しない。クオート内の「|」
      # （grepのOR条件等）は連結とみなさない。
      case "$hint_cmd" in
        'grep '*|'find '*) is_search=1 ;;
        *) is_search=0 ;;
      esac
      if has_unquoted_shell_chain "$hint_cmd"; then
        is_search=0
      fi
      if [ "$is_search" -eq 0 ]; then
        echo "  検証不能: ${kind_cell}の検出手がかりは検索系コマンド（grep/find）でないため再実行しません: ${hint_cmd}" >&2
        continue
      fi

      if ! hint_paths="$(extract_hint_paths "$hint_cmd")" || [ -z "$hint_paths" ]; then
        echo "[SKIP] 種別=${kind_cell} 対象パス=抽出不能 実測バイト数=不明 上限=${mirror_max_bytes} 理由=検出手がかりから安全に参照パスを抽出できないため" >&2
        hint_unknown=$((hint_unknown + 1))
        continue
      fi
      display_paths="$(printf '%s\n' "$hint_paths" | awk 'BEGIN{ORS=""} NR>1{printf ","} {printf "%s", $0}')"
      if ! measured_bytes="$(measure_hint_paths "$hint_repo" "$hint_paths")"; then
        echo "[SKIP] 種別=${kind_cell} 対象パス=${display_paths} 実測バイト数=不明 上限=${mirror_max_bytes} 理由=通常ファイルの論理サイズを測定できないため" >&2
        hint_unknown=$((hint_unknown + 1))
        continue
      fi
      if [ "$measured_bytes" -gt "$mirror_max_bytes" ]; then
        echo "[SKIP] 種別=${kind_cell} 対象パス=${display_paths} 実測バイト数=${measured_bytes} 上限=${mirror_max_bytes} 理由=複製対象が規模上限を超えたため" >&2
        hint_unknown=$((hint_unknown + 1))
        continue
      fi

      PREPARED_MIRROR=""
      if ! create_utf8_mirror; then
        echo "[SKIP] 種別=${kind_cell} 対象パス=${display_paths} 実測バイト数=${measured_bytes} 上限=${mirror_max_bytes} 理由=一時ミラーを作成できないため" >&2
        hint_unknown=$((hint_unknown + 1))
        continue
      fi
      mirror_dir="$PREPARED_MIRROR"
      if ! prepare_utf8_mirror "$hint_repo" "$mirror_dir" "$hint_paths"; then
        echo "[SKIP] 種別=${kind_cell} 対象パス=${display_paths} 実測バイト数=${measured_bytes} 上限=${mirror_max_bytes} 理由=限定複製またはUTF-8変換に失敗したため" >&2
        unregister_and_remove_mirror "$mirror_dir"
        hint_unknown=$((hint_unknown + 1))
        continue
      fi

      hint_output="$( (cd "$mirror_dir" && eval "$hint_cmd") 2>/dev/null || true )"
      unregister_and_remove_mirror "$mirror_dir"
      if [ -n "$hint_output" ]; then
        result="positive"
      else
        result="zero"
      fi

      if [ "$expect" != "$result" ]; then
        echo "  検出手がかり不整合: ${kind_cell}は「${verdict_cell}」と判定されているが検出手がかり再実行結果は${result}件相当です: ${hint_cmd}" >&2
        hint_bad=$((hint_bad + 1))
      fi
    done <<S6END
$s6
S6END
  fi

  LAST_UNKNOWN_COUNT="$hint_unknown"
  if [ "$hint_bad" -gt 0 ]; then
    echo "検査2失敗: 検出手がかりの再実行結果が判定語と $hint_bad 件不整合です" >&2
    return 1
  fi
  if [ "$hint_unknown" -gt 0 ]; then
    echo "検査2判定不能: 検出手がかり $hint_unknown 件を再実行できませんでした（他の検査は継続）" >&2
    return 2
  fi

  echo "検査2通過: 6種別すべてに判定行あり（検出手がかり再実行の整合確認込み）"
  return 0
}

# 検査3: 推測語ゼロ
check_no_guess_words() {
  survey="$1"
  hits="$(grep -nE -- "$GUESS_WORDS_RE" "$survey" 2>/dev/null || true)"
  if [ -n "$hits" ]; then
    echo "検査3失敗: 推測語を検出" >&2
    echo "$hits" >&2
    return 1
  fi
  echo "検査3通過: 推測語0件"
  return 0
}

# 未置換のプレースホルダと、規約として正当に言及した語を区別する（1-153）。
# <実測/<FILL と同様、TBD/TODOも裸の語（文中に埋め込まれた語）では検出せず、次の2形式に限定する。
#   (a) 雛形記法と同じ開き括弧付きの形: <実測 / <FILL / <TBD / <TODO
#   (b) 行全体、またはMarkdown表のセル全体がプレースホルダそのものである形
#         （例: セル内容がちょうど "TBD" だけ／"TODO" だけ）
# 「調査結果を記入」は独立した定型フレーズであり誤検知の実例が無いため、従来どおり地の文への
# 出現も検出する（検出対象語の追加・削除ではないため本改修の対象外）。
# 正当な言及を通す記法（規約・調査書の本文でTODO/TBDという語自体を説明する場合）は、
# バッククォートで囲んだ開き括弧付き形（`<TBD ...>`）にせず、地の文にそのまま書く。
placeholder_residue_hits() { # $1=file -> "行番号:該当行" を1件1行で列挙（0件なら出力なし）
  local file="$1" line lineno=0 cell trimmed hit
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    hit=0
    if printf '%s' "$line" | grep -qE -- '<実測|<FILL|<TBD|<TODO|調査結果を記入'; then
      hit=1
    elif printf '%s' "$line" | grep -q '|'; then
      local cells=()
      IFS='|' read -r -a cells <<<"$line"
      for cell in "${cells[@]}"; do
        trimmed="$(printf '%s' "$cell" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/`//g')"
        if [ "$trimmed" = "TBD" ] || [ "$trimmed" = "TODO" ]; then
          hit=1
          break
        fi
      done
    else
      trimmed="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/`//g')"
      if [ "$trimmed" = "TBD" ] || [ "$trimmed" = "TODO" ]; then
        hit=1
      fi
    fi
    [ "$hit" -eq 1 ] && printf '%d:%s\n' "$lineno" "$line"
  done < "$file"
}

# 検査4: テンプレ残存ゼロ
check_no_placeholder() {
  survey="$1"
  hits="$(placeholder_residue_hits "$survey" 2>/dev/null || true)"
  if [ -n "$hits" ]; then
    echo "検査4失敗: テンプレ残存トークンを検出" >&2
    echo "$hits" >&2
    return 1
  fi
  echo "検査4通過: テンプレ残存0件"
  return 0
}

# 検査5: §4ディレクトリ網羅性
check_directory_coverage() {
  survey="$1"
  repo="$2"

  # §1に調査手段としてのfindコマンドが記録されていることは引き続き要求する。
  # ただし走査範囲はその記述から導出しない（被検査文書が検査の厳格さを決められるため）。
  meta="$(extract_section_meta "$survey")"
  find_cmds="$(echo "$meta" | grep -oE '`find [^`]+`' | sed 's/^`//; s/`$//')"

  if [ -z "$find_cmds" ]; then
    echo "検査5失敗: §1にfindコマンドが見つかりません" >&2
    return 1
  fi

  # 走査範囲は対象リポジトリの実ディレクトリ構造から決定する。
  # 直接ファイルを持つディレクトリの集合を1回の走査でまとめて取得し、
  # ディレクトリ数に比例したプロセス起動をなくす（旧実装はディレクトリごとにfindを起動していた）。
  scan_max_depth="${DIRCOV_MAX_DEPTH:-}"
  all_files="$(find "$repo" -type f -not -path '*/.git/*' 2>/dev/null)"
  dirs_with_files="$(printf '%s\n' "$all_files" | sed 's|/[^/]*$||' | sort -u)"

  # 深度を制限する場合は、制限した深度と検査対象外にした件数を後段で出力へ明示する
  scanned_dirs=""
  skipped_by_depth=0
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    if [ -n "$scan_max_depth" ]; then
      if [ "$d" = "$repo" ]; then
        depth=0
      else
        relpath="${d#$repo/}"
        depth="$(printf '%s' "$relpath" | awk -F'/' '{print NF}')"
      fi
      if [ "$depth" -gt "$scan_max_depth" ]; then
        skipped_by_depth=$((skipped_by_depth + 1))
        continue
      fi
    fi
    scanned_dirs="${scanned_dirs}${d}
"
  done <<DIRSRC
$dirs_with_files
DIRSRC
  all_dirs="$(printf '%s' "$scanned_dirs" | sort)"
  scan_count="$(printf '%s' "$all_dirs" | grep -c . || true)"

  # §4本体テーブルからディレクトリパスを抽出（covered集合を構築）
  s4_raw="$(extract_section4 "$survey")"
  covered=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in '|'*) ;; *) continue ;; esac
    case "$line" in *'|---|'*) continue ;; esac
    case "$line" in *'ディレクトリ'*'責務'*) continue ;; esac
    cell="$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')"
    path="$(echo "$cell" | grep -oE '`[^`]+`' | head -1 | sed 's/^`//; s/`$//')"
    if [ -n "$path" ]; then
      norm="$path"
      case "$norm" in ./*) norm="${norm#./}" ;; esac
      if [ -f "$repo/$norm" ] 2>/dev/null; then
        norm="$(dirname "$norm")"
      fi
      covered="${covered}${norm}
"
    fi
  done <<S4END
$s4_raw
S4END

  # 対象外ディレクトリを抽出してcovered集合に追加
  excl_raw="$(extract_excluded_dirs "$survey")"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in '|'*) ;; *) continue ;; esac
    case "$line" in *'|---|'*) continue ;; esac
    case "$line" in *'ディレクトリ'*'除外理由'*) continue ;; esac
    cell="$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')"
    # 対象外ディレクトリは1セルに複数パスを列記できる。先頭1件だけを読むと残りが
    # 未網羅として不合格になるため、セル内のバッククォート囲みトークンをすべて読む
    # （改善課題: 対象外ディレクトリ-複数列記の先頭しか読まない）。
    paths="$(echo "$cell" | grep -oE '`[^`]+`' | sed 's/^`//; s/`$//')"
    while IFS= read -r path; do
      [ -z "$path" ] && continue
      norm="$path"
      case "$norm" in ./*) norm="${norm#./}" ;; esac
      covered="${covered}${norm}
"
    done <<EXCLPATHS
$paths
EXCLPATHS
  done <<EXCLEND
$excl_raw
EXCLEND

  # 各ディレクトリの網羅性を検証
  uncovered=0
  while IFS= read -r dir; do
    [ -z "$dir" ] && continue

    # all_dirs は既に「直接ファイルを持つディレクトリ」のみ。ここでのfind再起動は不要

    # 相対パスに変換
    if [ "$dir" = "$repo" ]; then
      rel="."
    else
      rel="${dir#$repo/}"
    fi
    case "$rel" in ./*) rel="${rel#./}" ;; esac

    # covered集合との照合
    found=false
    while IFS= read -r c; do
      [ -z "$c" ] && continue
      if [ "$rel" = "$c" ]; then
        found=true; break
      fi
      # §4の`.`行はルート直下の直接ファイルのみを網羅し、子ディレクトリへは波及しない
      if [ "$c" = "." ] && [ "$rel" = "." ]; then
        found=true; break
      fi
      case "$rel" in
        "$c"/*) found=true; break ;;
      esac
    done <<COVCHECK
$covered
COVCHECK

    if ! "$found"; then
      echo "  未網羅: $rel" >&2
      uncovered=$((uncovered + 1))
    fi
  done <<DIREND
$all_dirs
DIREND

  if [ "$uncovered" -gt 0 ]; then
    echo "検査5失敗: §4ディレクトリ責務マップに $uncovered 件の未網羅ディレクトリがあります（走査対象 ${scan_count} 件 / 深度制限による対象外 ${skipped_by_depth} 件）" >&2
    return 1
  fi
  if [ -n "$scan_max_depth" ]; then
    echo "検査5通過: ディレクトリ網羅性OK（走査対象 ${scan_count} 件 / 深度 ${scan_max_depth} 制限により対象外 ${skipped_by_depth} 件）"
  else
    echo "検査5通過: ディレクトリ網羅性OK（走査対象 ${scan_count} 件 / 深度制限なし・対象外 0 件）"
  fi
  return 0
}

# 検査6: §10 プロジェクト形態とサイト構成
check_project_form() {
  survey="$1"
  repo="$2"

  s10="$(extract_section10 "$survey")"
  if [ -z "$s10" ]; then
    echo "検査6失敗: §10 プロジェクト形態とサイト構成の節が見つかりません" >&2
    return 1
  fi

  form_line="$(echo "$s10" | grep -E '^\|[^|]*プロジェクト形態' | head -1)"
  if [ -z "$form_line" ]; then
    echo "検査6失敗: §10 にプロジェクト形態の行がありません" >&2
    return 1
  fi
  case "$form_line" in
    *単独プロジェクト*|*モノレポ*) : ;;
    *)
      echo "検査6失敗: プロジェクト形態が「単独プロジェクト」「モノレポ」のいずれでもありません" >&2
      echo "$form_line" >&2
      return 1 ;;
  esac

  site_rows="$(echo "$s10" \
    | LC_ALL=C awk '/^### .*サイト一覧/{f=1;next} f' \
    | grep -E '^\|' \
    | grep -v '^|[[:space:]]*---' \
    | grep -v 'サイトキー')"
  if [ -z "$site_rows" ]; then
    echo "検査6失敗: サイト一覧に行がありません（単独プロジェクトでも1行必要）" >&2
    return 1
  fi

  seen_keys=""
  bad=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    key="$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}' | sed 's/^`//; s/`$//')"
    root="$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$4); print $4}' | sed 's/^`//; s/`$//')"
    [ -z "$key" ] && continue

    case "$seen_keys" in
      *"[$key]"*)
        echo "  サイトキー重複: $key" >&2
        bad=$((bad + 1)) ;;
    esac
    seen_keys="${seen_keys}[$key]"

    if [ -z "$root" ]; then
      echo "  ルートディレクトリ未記入: $key" >&2
      bad=$((bad + 1))
    elif [ ! -d "$repo/$root" ]; then
      echo "  ルートディレクトリが実在しない: $key -> $root" >&2
      bad=$((bad + 1))
    fi
  done <<S10END
$site_rows
S10END

  if [ "$bad" -gt 0 ]; then
    echo "検査6失敗: サイト一覧に $bad 件の問題があります" >&2
    return 1
  fi
  echo "検査6通過: プロジェクト形態とサイト一覧OK"
  return 0
}

# 検査7: §8申し送りエンコーディング実測整合（1-126）
# 「エンコーディング-」で始まるキー行のみを対象とする。内容セルの先頭backtickトークンを
# エンコーディング名、後続backtickトークンを対象ファイル群として、各ファイルが実バイトで
# そのエンコーディング名により復号できることを detect-encoding.sh decodable で確認する。
# UNKNOWN行は復号可否検査の対象外（明示的な判定不能の申告のため）。
check_encoding_hints() {
  survey="$1"
  repo="$2"
  bad=0
  total=0
  s8="$(extract_section8 "$survey")"
  while IFS= read -r line8; do
    [ -z "$line8" ] && continue
    case "$line8" in '|'*) ;; *) continue ;; esac
    case "$line8" in *'|---|'*) continue ;; esac

    key_cell="$(echo "$line8" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')"
    case "$key_cell" in
      エンコーディング-*) : ;;
      *) continue ;;
    esac

    content_cell="$(echo "$line8" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$3); print $3}')"
    cell_tokens="$(echo "$content_cell" | grep -oE '`[^`]+`' 2>/dev/null | sed 's/^`//; s/`$//' || true)"
    enc="$(echo "$cell_tokens" | head -1)"
    files="$(echo "$cell_tokens" | tail -n +2)"
    [ -z "$enc" ] && continue

    if [ "$enc" = "UNKNOWN" ]; then
      continue
    fi

    while IFS= read -r f; do
      [ -z "$f" ] && continue
      total=$((total + 1))
      path="$repo/$f"
      if [ ! -f "$path" ]; then
        echo "  対象ファイル不在: ${f}（キー=${key_cell}, エンコーディング=${enc}）" >&2
        bad=$((bad + 1))
        continue
      fi
      if ! bash "$DETECT_ENCODING_SH" decodable "$path" "$enc" >/dev/null 2>&1; then
        echo "  復号不可: ${f} はエンコーディング ${enc} で復号できません（キー=${key_cell}）" >&2
        bad=$((bad + 1))
      fi
    done <<FILESEND
$files
FILESEND
  done <<S8END
$s8
S8END

  if [ "$bad" -gt 0 ]; then
    echo "検査7失敗: 申し送りのエンコーディング記載 $bad 件が実バイトで復号できません（対象 $total 件中）" >&2
    return 1
  fi
  echo "検査7通過: 申し送りのエンコーディング記載はすべて実バイトで復号可能（対象 $total 件。UNKNOWN行は対象外）"
  return 0
}

# 登録済み検査の唯一の一覧（検査数はこの一覧から導出する。固定文字列で件数を書かない）。
# 検査を追加・削除する場合はこの一覧のみを更新すればよい（成功時メッセージ・失敗時メッセージは
# CHECK_COUNT を通じて自動追従する）。
CHECK_NAMES="check_paths_exist check_unit_kinds check_no_guess_words check_no_placeholder check_directory_coverage check_project_form check_encoding_hints"

# CHECK_NAMES 内の検査すべてを実行し集約結果を返す。実行後 CHECK_COUNT に登録検査数を格納する。
run_all_checks() {
  survey="$1"
  repo="$2"
  count=0
  CHECK_PASS_COUNT=0
  CHECK_FAIL_COUNT=0
  CHECK_UNKNOWN_COUNT=0
  for name in $CHECK_NAMES; do
    count=$((count + 1))
    LAST_UNKNOWN_COUNT=0
    case "$name" in
      check_no_guess_words|check_no_placeholder)
        if "$name" "$survey"; then check_status=0; else check_status=$?; fi
        ;;
      *)
        if "$name" "$survey" "$repo"; then check_status=0; else check_status=$?; fi
        ;;
    esac
    case "$check_status" in
      0) CHECK_PASS_COUNT=$((CHECK_PASS_COUNT + 1)) ;;
      1) CHECK_FAIL_COUNT=$((CHECK_FAIL_COUNT + 1)) ;;
      2)
        if [ "${LAST_UNKNOWN_COUNT:-0}" -eq 0 ]; then
          CHECK_UNKNOWN_COUNT=$((CHECK_UNKNOWN_COUNT + 1))
        fi
        ;;
      *)
        echo "[UNKNOWN] ${name} が未定義の終了コード ${check_status} を返しました" >&2
        CHECK_UNKNOWN_COUNT=$((CHECK_UNKNOWN_COUNT + 1))
        ;;
    esac
    if [ "${LAST_UNKNOWN_COUNT:-0}" -gt 0 ]; then
      CHECK_UNKNOWN_COUNT=$((CHECK_UNKNOWN_COUNT + LAST_UNKNOWN_COUNT))
    fi
  done
  CHECK_COUNT="$count"
  if [ "$CHECK_FAIL_COUNT" -gt 0 ]; then
    return 1
  fi
  if [ "$CHECK_UNKNOWN_COUNT" -gt 0 ]; then
    return 2
  fi
  return 0
}

# 合成フィクスチャによる自己テスト。既存7検査の正負例に加え、課題別の回帰例も実行する。
self_test() {
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/architecture-survey-self-test.XXXXXX")" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] mktempによるself-test用一時ディレクトリ作成に失敗したため判定できません（一時領域への書き込み権限またはサンドボックス制約を確認してください）: ${TMPDIR:-/tmp}" >&2
    return 2
  fi
  trap 'rm -rf "$tmp"' RETURN

  repo="$tmp/repo"
  mkdir -p "$repo/src/app/api"
  mkdir -p "$repo/src/styles"
  : > "$repo/package.json"
  : > "$repo/src/app/page.tsx"
  : > "$repo/src/app/api/route.ts"
  : > "$repo/src/styles/shared-theme.ts"

  # 1-126自己テスト用: §8申し送りエンコーディング実測整合(検査7)の材料となる
  # 非UTF-8ファイル（EUC-JPとShift_JISを取り違えないことも兼ねて確認する）。
  # 既存の$repo（検査5の§4網羅性テストが厳密に対応付けている）を汚さないよう、
  # 独立したencoding_repoに置く。
  encoding_repo="$tmp/encoding-repo"
  mkdir -p "$encoding_repo/src/legacy"
  python3 -c "
import sys
sys.stdout.buffer.write('経理システムのルーティング定義。\n'.encode('euc-jp'))
" > "$encoding_repo/src/legacy/routes.euc.txt"

  base_kinds='| 種別 | 実在判定 | 検出手がかり | 参照先 |
|---|---|---|---|
| 画面 | 実在する | `find src/app -name page.tsx` で検出 | `src/app/page.tsx` |
| API | 実在する | `find src/app/api -name route.ts` で検出 | `src/app/api/route.ts` |
| テーブル | 実在しない（マイグレーション・ORMスキーマが見つからないため） | - | - |
| バッチ | 実在しない（cron/ジョブランナー定義が見つからないため） | - | - |
| 帳票 | 実在しない（帳票生成ライブラリの使用箇所が見つからないため） | - | - |
| 外部連携 | 実在しない（外部APIクライアントの使用箇所が見つからないため） | - | - |'

  # 陽性フィクスチャ: 7検査すべてPASSする想定
  cat > "$tmp/pass.md" <<MD
## 調査メタ

### 実行した調査コマンド一覧

| コマンド | 目的 |
|---|---|
| \`find . -maxdepth 2 -type f\` | ディレクトリ構造の確認 |

## エントリポイント
\`package.json\` と \`src/app/page.tsx\` を確認した。API定義は \`src/app/api/route.ts\`。

## ディレクトリ責務マップ
| ディレクトリ | 責務 | 参照先 |
|---|---|---|
| \`.\` | プロジェクトルート | \`package.json\` |
| \`src/styles/shared-theme.ts\` | 共有ファイル（3ディレクトリから参照） | grep -rlE "from ['\"].*theme['\"]" src で検出（3件） |

### 対象外ディレクトリ
| ディレクトリ | 除外理由 |
|---|---|
| \`src/app\` | ユニット種別判定で個別管理するため |

## ユニット種別判定
$base_kinds

## プロジェクト形態とサイト構成
| 項目 | 内容 | 参照先 |
|---|---|---|
| プロジェクト形態 | 単独プロジェクト | \`package.json\` |
| ワークスペース定義 | 実在しない（ワークスペース定義ファイルが見つからないため） | \`package.json\` |

### サイト一覧
| サイトキー | 表示名 | ルートディレクトリ | ビルドコマンド | 起動コマンド | 参照先 |
|---|---|---|---|---|---|
| main | 単一サイト | . | npm run build | npm run dev | \`package.json\` |
MD

  # 陰性1: 検査1のみ違反（存在しないパスを記載）
  cat > "$tmp/fail1.md" <<MD
## エントリポイント
\`src/app/missing.tsx\` を確認した。

## ユニット種別判定
$base_kinds
MD

  # 陰性2: 検査2のみ違反（画面の判定語を欠落）
  cat > "$tmp/fail2.md" <<MD
## エントリポイント
\`package.json\` を確認した。

## ユニット種別判定
| 種別 | 実在判定 | 検出手がかり | 参照先 |
|---|---|---|---|
| 画面 | 要確認 | - | - |
| API | 実在する | \`find src/app/api\` で検出 | \`src/app/api/route.ts\` |
| テーブル | 実在しない（マイグレーションが見つからないため） | - | - |
| バッチ | 実在しない（ジョブ定義が見つからないため） | - | - |
| 帳票 | 実在しない（帳票生成ライブラリが見つからないため） | - | - |
| 外部連携 | 実在しない（外部APIクライアントが見つからないため） | - | - |
MD

  # 陰性3: 検査3のみ違反（推測語混入）
  cat > "$tmp/fail3.md" <<MD
## エントリポイント
\`package.json\` を確認した。ルーティング方式はおそらくApp Routerである。

## ユニット種別判定
$base_kinds
MD

  # 陰性4: 検査4のみ違反（テンプレ残存）
  cat > "$tmp/fail4.md" <<MD
## 調査メタ
updated: <実測: YYYY-MM-DD>

## エントリポイント
\`package.json\` を確認した。

## ユニット種別判定
$base_kinds
MD

  # 陰性4b: 検査4のみ違反（§9テスト基盤のプレースホルダ残存）
  cat > "$tmp/fail4b.md" <<MD
## エントリポイント
\`package.json\` を確認した。

## ユニット種別判定
$base_kinds

## テスト基盤

### テストフレームワーク

| 種別 | フレームワーク | 設定ファイル | 備考 |
|---|---|---|---|
| 単体テスト | （調査結果を記入） | （パス） | |
MD

  # 陰性5: 検査5のみ違反（ディレクトリ未網羅）
  cat > "$tmp/fail5.md" <<MD
## 調査メタ

### 実行した調査コマンド一覧

| コマンド | 目的 |
|---|---|
| \`find . -maxdepth 2 -type f\` | ディレクトリ構造の確認 |

## エントリポイント
\`package.json\` を確認した。

## ディレクトリ責務マップ
| ディレクトリ | 責務 | 参照先 |
|---|---|---|
| \`src/styles/shared-theme.ts\` | 共有ファイル（3ディレクトリから参照） | grep で検出 |

## ユニット種別判定
$base_kinds
MD

  # 陰性6: 検査5のみ違反（§4の`.`行が対象外ディレクトリ表なしで存在し、
  # 子ディレクトリsrc/appが個別行にも対象外にも未記載＝`.`の誤った全域マッチを検出する）
  cat > "$tmp/fail6.md" <<MD
## 調査メタ

### 実行した調査コマンド一覧

| コマンド | 目的 |
|---|---|
| \`find . -maxdepth 2 -type f\` | ディレクトリ構造の確認 |

## エントリポイント
\`package.json\` と \`src/app/page.tsx\` を確認した。API定義は \`src/app/api/route.ts\`。

## ディレクトリ責務マップ
| ディレクトリ | 責務 | 参照先 |
|---|---|---|
| \`.\` | プロジェクトルート | \`package.json\` |
| \`src/styles/shared-theme.ts\` | 共有ファイル（3ディレクトリから参照） | grep -rlE "from ['\"].*theme['\"]" src で検出（3件） |

## ユニット種別判定
$base_kinds
MD

  # 陰性7: 検査6のみ違反（§10節そのものが欠落）
  cat > "$tmp/fail7.md" <<MD
## エントリポイント
\`package.json\` を確認した。

## ユニット種別判定
$base_kinds
MD

  # 陰性8: 検査6のみ違反（サイト一覧のルートディレクトリが実在しない）
  cat > "$tmp/fail8.md" <<MD
## エントリポイント
\`package.json\` を確認した。

## ユニット種別判定
$base_kinds

## プロジェクト形態とサイト構成
| 項目 | 内容 | 参照先 |
|---|---|---|
| プロジェクト形態 | モノレポ | \`package.json\` |

### サイト一覧
| サイトキー | 表示名 | ルートディレクトリ | ビルドコマンド | 起動コマンド | 参照先 |
|---|---|---|---|---|---|
| web | 利用者サイト | apps/missing-site | npm run build | npm run dev | \`package.json\` |
MD

  rc=0

  if run_all_checks "$tmp/pass.md" "$repo" >/dev/null 2>&1; then
    echo "  [PASS] 陽性フィクスチャがexit 0"
  else
    echo "  [FAIL] 陽性フィクスチャがexit 0にならない" >&2
    rc=1
  fi

  if check_paths_exist "$tmp/fail1.md" "$repo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査1: 未実在パスがあるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査1: 未実在パスでexit 1"
  fi

  if check_unit_kinds "$tmp/fail2.md" >/dev/null 2>&1; then
    echo "  [FAIL] 検査2: 判定行欠落があるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査2: 判定行欠落でexit 1"
  fi

  if check_no_guess_words "$tmp/fail3.md" >/dev/null 2>&1; then
    echo "  [FAIL] 検査3: 推測語混入があるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査3: 推測語混入でexit 1"
  fi

  if check_no_placeholder "$tmp/fail4.md" >/dev/null 2>&1; then
    echo "  [FAIL] 検査4: テンプレ残存があるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査4: テンプレ残存でexit 1"
  fi

  if check_no_placeholder "$tmp/fail4b.md" >/dev/null 2>&1; then
    echo "  [FAIL] 検査4: §9テスト基盤のプレースホルダ残存があるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査4: §9テスト基盤のプレースホルダ残存でexit 1"
  fi

  # 陽性(1-153): TODO/TBDという語自体を地の文で正当に言及した場合は検出しないこと
  cat > "$tmp/mention4.md" <<MD
## エントリポイント
\`package.json\` を確認した。作業メモ用コメントはTODOで統一し、確定していない値はTBDと書く運用である。

## ユニット種別判定
$base_kinds
MD
  if check_no_placeholder "$tmp/mention4.md" >/dev/null 2>&1; then
    echo "  [PASS] 検査4(1-153): TODO/TBDの地の文言及は誤検出しない"
  else
    echo "  [FAIL] 検査4(1-153): 正当な言及なのにテンプレ残存として誤検出した" >&2
    rc=1
  fi

  if check_directory_coverage "$tmp/fail5.md" "$repo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査5: ディレクトリ未網羅があるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査5: ディレクトリ未網羅でexit 1"
  fi

  if check_directory_coverage "$tmp/fail6.md" "$repo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査5: §4の\`.\`行が子ディレクトリへ誤って全域マッチしexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査5: §4の\`.\`行はルート直下のみ網羅しsrc/appの未網羅でexit 1"
  fi

  # 陽性(対象外ディレクトリ-複数列記の先頭しか読まない): 1セルに複数パスを列記した
  # 対象外ディレクトリ表を持つ調査書で、先頭パスだけでなく全パスが未網羅解消に
  # 使われることを確認する。修正前は`src/moduleB`が未網羅として検出されexit 1だった。
  multiexcl_repo="$tmp/multiexcl-repo"
  mkdir -p "$multiexcl_repo/src/moduleA" "$multiexcl_repo/src/moduleB"
  : > "$multiexcl_repo/package.json"
  : > "$multiexcl_repo/src/moduleA/file.ts"
  : > "$multiexcl_repo/src/moduleB/file.ts"

  cat > "$tmp/multiexcl.md" <<MD
## 調査メタ

### 実行した調査コマンド一覧

| コマンド | 目的 |
|---|---|
| \`find . -maxdepth 2 -type f\` | ディレクトリ構造の確認 |

## ディレクトリ責務マップ
| ディレクトリ | 責務 | 参照先 |
|---|---|---|
| \`.\` | プロジェクトルート | \`package.json\` |

### 対象外ディレクトリ
| ディレクトリ | 除外理由 |
|---|---|
| \`src/moduleA\` \`src/moduleB\` | 個別ユニット判定で管理するため |
MD

  if check_directory_coverage "$tmp/multiexcl.md" "$multiexcl_repo" >/dev/null 2>&1; then
    echo "  [PASS] 検査5(対象外ディレクトリ-複数列記): 1セル内の複数パスをすべて読み網羅判定"
  else
    echo "  [FAIL] 検査5(対象外ディレクトリ-複数列記): 1セルの先頭パスしか読まず未網羅と誤判定した" >&2
    rc=1
  fi

  if check_project_form "$tmp/fail7.md" "$repo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査6: §10節が欠落しているのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査6: §10節の欠落でexit 1"
  fi

  if check_project_form "$tmp/fail8.md" "$repo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査6: サイトのルートディレクトリが未実在なのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査6: サイトのルートディレクトリ未実在でexit 1"
  fi

  # 陰性9: 検査5のみ違反（走査範囲が被検査文書の記述に依存しない）。
  # §1のfindコマンドは-maxdepth 1という浅い深度を記述するが、深い階層に
  # 責務マップ未記載のディレクトリ（直接ファイルを持つ）を置く。旧実装は
  # §1の記述をそのまま走査範囲に採用していたためこのケースを検出できなかった。
  rangerepo="$tmp/rangerepo"
  mkdir -p "$rangerepo/a/b/c/deep"
  : > "$rangerepo/package.json"
  : > "$rangerepo/a/b/c/deep/file.txt"

  cat > "$tmp/fail9.md" <<MD
## 調査メタ

### 実行した調査コマンド一覧

| コマンド | 目的 |
|---|---|
| \`find . -maxdepth 1 -type d\` | ディレクトリ構造の確認 |

## ディレクトリ責務マップ
| ディレクトリ | 責務 | 参照先 |
|---|---|---|
| \`.\` | プロジェクトルート | \`package.json\` |
MD

  if check_directory_coverage "$tmp/fail9.md" "$rangerepo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査5: §1の浅いfind記述に反して深階層の未網羅ディレクトリを検出できなかった（走査範囲が被検査文書に依存している）" >&2
    rc=1
  else
    echo "  [PASS] 検査5: §1の記述に関わらず深階層の未網羅ディレクトリを検出しexit 1"
  fi

  # 陽性9: 検査5の出力に走査対象件数と対象外件数の両方が含まれる。
  # check_directory_coverage は内部で repo="$2" とグローバル変数を上書きするため、
  # 直前のテストで変化した $repo に依存せず、pass フィクスチャ自身のリポジトリを明示指定する。
  cov_output="$(check_directory_coverage "$tmp/pass.md" "$tmp/repo" 2>&1)" || true
  if echo "$cov_output" | grep -q '走査対象' && echo "$cov_output" | grep -q '対象外'; then
    echo "  [PASS] 検査5: 出力に走査対象件数と対象外件数の両方が含まれる"
  else
    echo "  [FAIL] 検査5: 出力に走査対象件数または対象外件数が含まれない" >&2
    echo "$cov_output" >&2
    rc=1
  fi

  # --- 1-140自己テスト追加分: 検査2への検出手がかり再実行整合チェック ---
  # 陰性10: 「実在しない」と記録しながら再実行すると1件以上返す合成調査書でexit 1になること
  mismatch_kinds='| 種別 | 実在判定 | 検出手がかり | 参照先 |
|---|---|---|---|
| 画面 | 実在する | `find src/app -name page.tsx` で検出 | `src/app/page.tsx` |
| API | 実在する | `find src/app/api -name route.ts` で検出 | `src/app/api/route.ts` |
| テーブル | 実在しない（マイグレーション・ORMスキーマが見つからないため） | `find src/app -name page.tsx` で検出 | - |
| バッチ | 実在しない（cron/ジョブランナー定義が見つからないため） | - | - |
| 帳票 | 実在しない（帳票生成ライブラリの使用箇所が見つからないため） | - | - |
| 外部連携 | 実在しない（外部APIクライアントの使用箇所が見つからないため） | - | - |'

  cat > "$tmp/fail10.md" <<MD
## エントリポイント
\`package.json\` を確認した。

## ユニット種別判定
$mismatch_kinds
MD

  if check_unit_kinds "$tmp/fail10.md" "$tmp/repo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査2(1-140): 「実在しない」判定なのに検出手がかり再実行が1件以上返すのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査2(1-140): 判定と検出手がかり再実行結果の不整合でexit 1"
  fi

  # 陽性: 判定と検出手がかり再実行結果が整合する合成調査書（pass.md）は通過すること
  if check_unit_kinds "$tmp/pass.md" "$tmp/repo" >/dev/null 2>&1; then
    echo "  [PASS] 検査2(1-140): 判定と検出手がかり再実行結果が整合する合成調査書は通過"
  else
    echo "  [FAIL] 検査2(1-140): 整合しているのにexit 1になった" >&2
    rc=1
  fi

  # --- project-portal除外: 調査書から派生した閲覧用HTMLが本文をJSON文字列として
  #     埋め込むため、その中に例示文字列（帳票検出パターン等）が含まれていても
  #     検査2の再実行ではproject-portal/を検出対象外として扱うことを確認する
  #     （実測 2026-08-31）。 ---
  portal_repo="$tmp/portal-repo"
  mkdir -p "$portal_repo/src/app/api" "$portal_repo/project-portal/foundation"
  : > "$portal_repo/src/app/page.tsx"
  : > "$portal_repo/src/app/api/route.ts"
  echo 'new ExcelJS.Workbook()' > "$portal_repo/project-portal/foundation/report.html"
  portal_kinds='| 種別 | 実在判定 | 検出手がかり | 参照先 |
|---|---|---|---|
| 画面 | 実在する | `find src/app -name page.tsx` で検出 | `src/app/page.tsx` |
| API | 実在する | `find src/app/api -name route.ts` で検出 | `src/app/api/route.ts` |
| テーブル | 実在しない（マイグレーション・ORMスキーマが見つからないため） | - | - |
| バッチ | 実在しない（cron/ジョブランナー定義が見つからないため） | - | - |
| 帳票 | 実在しない（帳票生成ライブラリの使用箇所が見つからないため） | `grep -rlE "new ExcelJS\." .` で検出 | - |
| 外部連携 | 実在しない（外部APIクライアントの使用箇所が見つからないため） | - | - |'
  cat > "$tmp/portal.md" <<MD
## エントリポイント
\`package.json\` を確認した。

## ユニット種別判定
$portal_kinds
MD
  if check_unit_kinds "$tmp/portal.md" "$portal_repo" >/dev/null 2>&1; then
    echo "  [PASS] 検査2(project-portal除外): project-portal配下の例示文字列に自己一致せず通過"
  else
    echo "  [FAIL] 検査2(project-portal除外): project-portal配下の例示文字列に自己一致してexit 1になった" >&2
    rc=1
  fi

  # --- アーキ調査ゲート-パイプで検証不能: 検出手がかりにOR条件（クオート内パイプ）を
  #     含む場合の列崩れ回避チェック ---
  pipe_repo="$tmp/pipe-repo"
  mkdir -p "$pipe_repo/src/app/api" "$pipe_repo/src/jobs"
  : > "$pipe_repo/src/app/page.tsx"
  : > "$pipe_repo/src/app/api/route.ts"
  echo "cron.schedule(...)" > "$pipe_repo/src/jobs/scheduler.ts"

  pipe_kinds='| 種別 | 実在判定 | 検出手がかり | 参照先 |
|---|---|---|---|
| 画面 | 実在する | `find src/app -name page.tsx` で検出 | `src/app/page.tsx` |
| API | 実在する | `find src/app/api -name route.ts` で検出 | `src/app/api/route.ts` |
| テーブル | 実在しない（マイグレーション・ORMスキーマが見つからないため） | - | - |
| バッチ | 実在する | `grep -rlE "cron|schedule" src` で検出 | `src/jobs/scheduler.ts` |
| 帳票 | 実在しない（帳票生成ライブラリの使用箇所が見つからないため） | - | - |
| 外部連携 | 実在しない（外部APIクライアントの使用箇所が見つからないため） | - | - |'

  cat > "$tmp/pipe-pass.md" <<MD
## エントリポイント
\`package.json\` を確認した。

## ユニット種別判定
$pipe_kinds
MD

  # 陽性: OR条件（クオート内の「|」）を持つ検出手がかりが列崩れせず正しく再実行され、
  # 「実在する」判定と一致すること（対象ファイルにcronキーワードあり）
  if check_unit_kinds "$tmp/pipe-pass.md" "$pipe_repo" >/dev/null 2>&1; then
    echo "  [PASS] 検査2(パイプ検証): OR条件の検出手がかりが列崩れせず判定と整合"
  else
    echo "  [FAIL] 検査2(パイプ検証): OR条件の検出手がかりが列崩れし整合判定できなかった" >&2
    rc=1
  fi

  # 陰性: 同じOR条件の検出手がかりだが、対象repoに一致ファイルが無く「実在する」判定と
  # 矛盾する場合。修正前は列崩れでhint_cmdが空になり「検証不能」としてそのまま通過（exit 0）
  # していたが、修正後は不一致を正しく検出しexit 1になること
  if check_unit_kinds "$tmp/pipe-pass.md" "$tmp/repo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査2(パイプ検証): OR条件の検出手がかりが不一致なのに列崩れで検証不能へ落ちてexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査2(パイプ検証): OR条件の検出手がかりが列崩れせず正しく不一致を検出しexit 1"
  fi

  # 回帰確認: 引用外の本物のシェル連結記号（|）を含む検出手がかりは、既存どおり
  # 再実行せず「検証不能」で素通りする（安全策が弱まっていないことの確認）
  chain_kinds='| 種別 | 実在判定 | 検出手がかり | 参照先 |
|---|---|---|---|
| 画面 | 実在する | `find src/app -name page.tsx` で検出 | `src/app/page.tsx` |
| API | 実在する | `find src/app/api -name route.ts` で検出 | `src/app/api/route.ts` |
| テーブル | 実在しない（マイグレーション・ORMスキーマが見つからないため） | - | - |
| バッチ | 実在しない（cron/ジョブランナー定義が見つからないため） | `find . -type f | wc -l` で検出 | - |
| 帳票 | 実在しない（帳票生成ライブラリの使用箇所が見つからないため） | - | - |
| 外部連携 | 実在しない（外部APIクライアントの使用箇所が見つからないため） | - | - |'

  cat > "$tmp/chain-skip.md" <<MD
## エントリポイント
\`package.json\` を確認した。

## ユニット種別判定
$chain_kinds
MD

  if check_unit_kinds "$tmp/chain-skip.md" "$tmp/repo" >/dev/null 2>&1; then
    chain_status=0
  else
    chain_status=$?
  fi
  if [ "$chain_status" -eq 0 ]; then
    echo "  [PASS] 検査2(パイプ検証): 引用外のシェル連結記号を含む検出手がかりは再実行せず既存どおり不整合にしない"
  else
    echo "  [FAIL] 検査2(パイプ検証): 引用外のシェル連結記号を含む検出手がかりが不整合扱いになった" >&2
    rc=1
  fi

  # --- 検証コマンド-表のエスケープを解釈しない: Markdownの表記法で「\|」と
  #     エスケープされた検出手がかりを解いてから再実行することを確認する ---
  escpipe_repo="$tmp/escpipe-repo"
  mkdir -p "$escpipe_repo/backend/app"
  : > "$escpipe_repo/backend/app/page.tsx"
  cat > "$escpipe_repo/backend/app/webhook_handler.py" <<'PYEOF'
def handle():
    return "webhook received"
PYEOF

  escpipe_kinds='| 種別 | 実在判定 | 検出手がかり | 参照先 |
|---|---|---|---|
| 画面 | 実在しない（対象なし） | - | - |
| API | 実在しない（対象なし） | - | - |
| テーブル | 実在しない（対象なし） | - | - |
| バッチ | 実在しない（対象なし） | - | - |
| 帳票 | 実在しない（対象なし） | - | - |
| 外部連携 | 実在する | `grep -rlE "requests\.\|httpx\.\|discord\|slack\|webhook" backend/app` で検出 | `backend/app/webhook_handler.py` |'

  cat > "$tmp/escpipe.md" <<MD
## エントリポイント
\`package.json\` を確認した。

## ユニット種別判定
$escpipe_kinds
MD

  # 修正前は「\|」を解かずに実行するため、alternationが消えて検出0件になり、
  # 「実在する」判定と矛盾してexit 1（不整合判定）になっていた。修正後は「\|」を
  # 「|」へ戻してから実行するためwebhook_handler.pyが検出され、判定と整合してexit 0になる。
  if check_unit_kinds "$tmp/escpipe.md" "$escpipe_repo" >/dev/null 2>&1; then
    echo "  [PASS] 検査2(検証コマンド-表のエスケープ): \\|を|へ解いてから再実行し判定と整合"
  else
    echo "  [FAIL] 検査2(検証コマンド-表のエスケープ): \\|を解かずに実行し不整合と誤判定した" >&2
    rc=1
  fi

  # --- 1-126自己テスト追加分: 検査7(§8申し送りエンコーディング実測整合) ---
  # 陽性: 記録されたエンコーディング名で対象ファイルが実際に復号できる
  cat > "$tmp/encoding-pass.md" <<MD
## §8 後続工程への申し送り

| キー | 内容 |
|---|---|
| エンコーディング-legacyルーティング定義 | \`EUC-JP\`（対象: \`src/legacy/routes.euc.txt\`） |
MD

  if check_encoding_hints "$tmp/encoding-pass.md" "$encoding_repo" >/dev/null 2>&1; then
    echo "  [PASS] 検査7(1-126): 記録されたエンコーディング名で対象ファイルが復号できる場合は通過"
  else
    echo "  [FAIL] 検査7(1-126): 復号できるのにexit 1になった" >&2
    rc=1
  fi

  # 陰性: 記録されたエンコーディング名では対象ファイルを復号できない（EUC-JPの実バイトにShift_JISと誤記）
  cat > "$tmp/encoding-fail.md" <<MD
## §8 後続工程への申し送り

| キー | 内容 |
|---|---|
| エンコーディング-legacyルーティング定義誤記 | \`Shift_JIS\`（対象: \`src/legacy/routes.euc.txt\`） |
MD

  if check_encoding_hints "$tmp/encoding-fail.md" "$encoding_repo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査7(1-126): 復号できない値が記録されているのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査7(1-126): 復号できない値の記録でexit 1"
  fi

  # UNKNOWN行は復号可否検査の対象外として通過すること
  cat > "$tmp/encoding-unknown.md" <<MD
## §8 後続工程への申し送り

| キー | 内容 |
|---|---|
| エンコーディング-判定不能ファイル | \`UNKNOWN\`（対象: \`src/legacy/routes.euc.txt\`） |
MD

  if check_encoding_hints "$tmp/encoding-unknown.md" "$encoding_repo" >/dev/null 2>&1; then
    echo "  [PASS] 検査7(1-126): UNKNOWN行は復号可否検査の対象外として通過"
  else
    echo "  [FAIL] 検査7(1-126): UNKNOWN行が誤ってexit 1になった" >&2
    rc=1
  fi

  # --- 1-258自己テスト追加分: 手がかり参照先限定・大容量回避・signal cleanup・
  #     規模超過の局所的判定不能・非UTF-8再実行の回帰確認 ---
  mirror_scope_repo="$tmp/mirror-scope-repo"
  mkdir -p "$mirror_scope_repo/config" "$mirror_scope_repo/src/allowed" "$mirror_scope_repo/unrelated"
  echo "needle" > "$mirror_scope_repo/config/app.conf"
  echo "needle" > "$mirror_scope_repo/src/allowed/target.txt"
  echo "must-not-copy" > "$mirror_scope_repo/unrelated/large.bin"
  scope_paths="$(extract_hint_paths 'grep -rl "needle" config/app.conf src/allowed')"
  PREPARED_MIRROR=""
  if create_utf8_mirror && prepare_utf8_mirror "$mirror_scope_repo" "$PREPARED_MIRROR" "$scope_paths" \
    && [ -f "$PREPARED_MIRROR/config/app.conf" ] \
    && [ -f "$PREPARED_MIRROR/src/allowed/target.txt" ] \
    && [ ! -e "$PREPARED_MIRROR/unrelated/large.bin" ]; then
    echo "  [PASS] 1-258判定1: 一時ミラーは手がかりが読むパス配下だけを複製"
  else
    echo "  [FAIL] 1-258判定1: 一時ミラーへ手がかり外のファイルを複製した、または参照先を複製できない" >&2
    rc=1
  fi
  [ -n "$PREPARED_MIRROR" ] && unregister_and_remove_mirror "$PREPARED_MIRROR"

  large_hint_repo="$tmp/large-hint-repo"
  mkdir -p "$large_hint_repo/src/selected" "$large_hint_repo/unrelated"
  echo "needle" > "$large_hint_repo/src/selected/target.txt"
  python3 - "$large_hint_repo/unrelated/sparse.bin" <<'PY'
import sys
with open(sys.argv[1], "wb") as handle:
    handle.seek(1073741825)
    handle.write(b"0")
PY
  large_hint_kinds='| 種別 | 実在判定 | 検出手がかり | 参照先 |
|---|---|---|---|
| 画面 | 実在する | `grep -rl "needle" src/selected` で検出 | `src/selected/target.txt` |
| API | 実在しない（対象なし） | - | - |
| テーブル | 実在しない（対象なし） | - | - |
| バッチ | 実在しない（対象なし） | - | - |
| 帳票 | 実在しない（対象なし） | - | - |
| 外部連携 | 実在しない（対象なし） | - | - |'
  cat > "$tmp/large-hint.md" <<MD
## ユニット種別判定
$large_hint_kinds
MD
  large_started="$(date +%s)"
  large_selected_paths="$(extract_hint_paths 'grep -rl "needle" src/selected')"
  large_selected_bytes="$(measure_hint_paths "$large_hint_repo" "$large_selected_paths")"
  if [ "$large_selected_paths" = "src/selected" ] && [ "$large_selected_bytes" -lt 1024 ] \
    && check_unit_kinds "$tmp/large-hint.md" "$large_hint_repo" >/dev/null 2>&1; then
    large_elapsed=$(( $(date +%s) - large_started ))
    if [ "$large_elapsed" -le 10 ]; then
      echo "  [PASS] 1-258判定2: 1GiB超の無関係疎ファイルを複製せず判定を返却（${large_elapsed}秒）"
    else
      echo "  [FAIL] 1-258判定2: 無関係ファイルを含む判定が制限時間を超過（${large_elapsed}秒）" >&2
      rc=1
    fi
  else
    echo "  [FAIL] 1-258判定2: 1GiB超の無関係ファイルにより検出手がかりを判定できない" >&2
    rc=1
  fi

  if [ "$(extract_hint_paths 'grep --after-context 2 needle src/selected')" = "src/selected" ] \
    && [ "$(extract_hint_paths 'grep --include *.py needle src/selected')" = "src/selected" ] \
    && [ "$(extract_hint_paths 'grep -m 2 needle src/selected')" = "src/selected" ] \
    && [ "$(extract_hint_paths 'grep -e needle src/selected')" = "src/selected" ] \
    && [ "$(extract_hint_paths 'find -H src/selected -name target.txt')" = "src/selected" ] \
    && ! extract_hint_paths 'grep --未対応 値 needle src/selected' >/dev/null 2>&1; then
    echo "  [PASS] 1-258引数解析: 値付きoptionとfind前置きoptionをパスから除外し未対応構文を拒否"
  else
    echo "  [FAIL] 1-258引数解析: option値または検索patternを参照パスとして誤採用" >&2
    rc=1
  fi

  signal_repo="$tmp/signal-repo"
  cp -R "$tmp/repo" "$signal_repo"
  echo "page" > "$signal_repo/src/app/page.tsx"
  sed 's#`find src/app -name page.tsx`#`grep -rl "page" src/app src/styles`#' "$tmp/pass.md" > "$tmp/signal.md"
  slow_cp="$tmp/slow-copy-for-signal.sh"
  cat > "$slow_cp" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
copy_args=("$@")
copy_arg_count=${#copy_args[@]}
copy_source="${copy_args[$((copy_arg_count - 2))]}"
copy_target="${copy_args[$((copy_arg_count - 1))]}"
copy_root="${copy_source%/.}"
if [ -d "$copy_root" ]; then
  first_file="$(find "$copy_root" -type f | head -1)"
  if [ -n "$first_file" ]; then
    relative_file="${first_file#"$copy_root"/}"
    mkdir -p "$copy_target/$(dirname "$relative_file")"
    /bin/cp -P "$first_file" "$copy_target/$relative_file"
  fi
fi
# 外部copyコマンド自身を未完了のまま保ち、親がwait中にsignalを受けるケースを作る。
copy_pause_until=$((SECONDS + 20))
while [ "$SECONDS" -lt "$copy_pause_until" ]; do :; done
exec /bin/cp "$@"
SH
  chmod +x "$slow_cp"
  for signal_name in TERM INT; do
    signal_tmp="$tmp/signal-tmp-$signal_name"
    mkdir -p "$signal_tmp"
    signal_result="$(python3 - "$0" "$tmp/signal.md" "$signal_repo" "$signal_tmp" "$signal_name" "$slow_cp" <<'PY'
import glob
import os
import signal
import subprocess
import sys
import time

script, survey, repo, temp_root, signal_name, slow_cp = sys.argv[1:]
env = os.environ.copy()
env["TMPDIR"] = temp_root
env["ARCHITECTURE_SURVEY_MIRROR_TEST_CP_COMMAND"] = slow_cp
started = time.monotonic()
proc = subprocess.Popen(
    ["bash", script, survey, repo],
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
    env=env,
)
observed_copy = False
deadline = started + 5
while time.monotonic() < deadline:
    mirrors = glob.glob(os.path.join(temp_root, "architecture-survey-mirror.*"))
    if any(
        any(os.path.isfile(item) for item in glob.glob(os.path.join(path, "src", "app", "**", "*"), recursive=True))
        for path in mirrors
    ):
        observed_copy = True
        break
    if proc.poll() is not None:
        break
    time.sleep(0.02)
if observed_copy and proc.poll() is None:
    proc.send_signal(getattr(signal, "SIG" + signal_name))
try:
    output, _ = proc.communicate(timeout=5)
except subprocess.TimeoutExpired:
    proc.kill()
    output, _ = proc.communicate()
remaining = len(glob.glob(os.path.join(temp_root, "architecture-survey-mirror.*")))
continued = int("ゲート総括" in output)
elapsed = time.monotonic() - started
print(f"status={proc.returncode} remaining={remaining} elapsed={elapsed:.3f} observed={int(observed_copy)} continued={continued}")
PY
)"
    expected_signal_status=143
    [ "$signal_name" = "INT" ] && expected_signal_status=130
    if printf '%s\n' "$signal_result" | grep -q "status=${expected_signal_status} " \
      && printf '%s\n' "$signal_result" | grep -q 'remaining=0 ' \
      && printf '%s\n' "$signal_result" | grep -q 'observed=1 ' \
      && printf '%s\n' "$signal_result" | grep -q 'continued=0'; then
      echo "  [PASS] 1-258判定$([ "$signal_name" = TERM ] && echo 3 || echo 4): ${signal_name}で終了コード${expected_signal_status}・ミラー0件・制限時間内終了（${signal_result}）"
    else
      echo "  [FAIL] 1-258 ${signal_name}: signal cleanupまたは終了コードが不正（${signal_result}）" >&2
      rc=1
    fi
  done

  limit_repo="$tmp/limit-repo"
  cp -R "$tmp/repo" "$limit_repo"
  python3 - "$limit_repo/src/app/unrelated.sparse" <<'PY'
import sys
with open(sys.argv[1], "wb") as handle:
    handle.seek(4095)
    handle.write(b"0")
PY
  sed 's#`find src/app -name page.tsx`#`find . -name page.tsx`#' "$tmp/pass.md" > "$tmp/limit.md"
  if ARCHITECTURE_SURVEY_MIRROR_MAX_BYTES=1024 limit_output="$(ARCHITECTURE_SURVEY_MIRROR_MAX_BYTES=1024 bash "$0" "$tmp/limit.md" "$limit_repo" 2>&1)"; then
    limit_status=0
  else
    limit_status=$?
  fi
  if [ "$limit_status" -eq 2 ] \
    && printf '%s\n' "$limit_output" | grep -q '^\[SKIP\].*種別=画面.*実測バイト数=.*上限=1024' \
    && printf '%s\n' "$limit_output" | grep -q '検査1通過' \
    && printf '%s\n' "$limit_output" | grep -q '検査3通過' \
    && printf '%s\n' "$limit_output" | grep -q '合格=6 不合格=0 判定不能=1'; then
    echo "  [PASS] 1-258判定5: 規模超過を判定不能として他6検査を完了しexit 2"
  else
    echo "  [FAIL] 1-258判定5: 規模超過時の継続・総括・exit 2契約を満たさない" >&2
    echo "$limit_output" >&2
    rc=1
  fi

  legacy_hint_repo="$tmp/legacy-hint-repo"
  mkdir -p "$legacy_hint_repo/src/legacy"
  python3 - "$legacy_hint_repo/src/legacy/routes.euc.txt" <<'PY'
import sys
with open(sys.argv[1], "wb") as handle:
    handle.write("経理システムのルーティング定義。\n".encode("euc-jp"))
PY
  legacy_hint_kinds='| 種別 | 実在判定 | 検出手がかり | 参照先 |
|---|---|---|---|
| 画面 | 実在しない（対象なし） | - | - |
| API | 実在する | `grep -rl "経理" src/legacy` で検出 | `src/legacy/routes.euc.txt` |
| テーブル | 実在しない（対象なし） | - | - |
| バッチ | 実在しない（対象なし） | - | - |
| 帳票 | 実在しない（対象なし） | - | - |
| 外部連携 | 実在しない（対象なし） | - | - |'
  cat > "$tmp/legacy-hint.md" <<MD
## ユニット種別判定
$legacy_hint_kinds
MD
  if check_unit_kinds "$tmp/legacy-hint.md" "$legacy_hint_repo" >/dev/null 2>&1; then
    echo "  [PASS] 1-258判定6: 非UTF-8参照ファイルを変換後に再実行し期待件数を判定"
  else
    echo "  [FAIL] 1-258判定6: 非UTF-8参照ファイルの変換後再実行が回帰" >&2
    rc=1
  fi

  # 陽性10: 1,000ディレクトリ規模のフィクスチャでディレクトリごとのfind再起動なしに
  # 単一走査が完了する（所要時間ではなく完了することを判定基準とする）
  bigrepo="$tmp/bigrepo"
  mkdir -p "$bigrepo"
  : > "$bigrepo/package.json"
  bi=1
  while [ "$bi" -le 1000 ]; do
    bd="$bigrepo/dir$bi"
    mkdir -p "$bd"
    : > "$bd/file.txt"
    bi=$((bi + 1))
  done

  cat > "$tmp/bigsurvey.md" <<MD
## 調査メタ

### 実行した調査コマンド一覧

| コマンド | 目的 |
|---|---|
| \`find . -type f\` | ディレクトリ構造の確認 |

## ディレクトリ責務マップ
| ディレクトリ | 責務 | 参照先 |
|---|---|---|
| \`.\` | プロジェクトルート | \`package.json\` |
MD

  if check_directory_coverage "$tmp/bigsurvey.md" "$bigrepo" >/dev/null 2>&1; then
    echo "  [PASS] 検査5: 1,000ディレクトリ規模のフィクスチャで単一走査が完了した（exit 0）"
  else
    echo "  [PASS] 検査5: 1,000ディレクトリ規模のフィクスチャで単一走査が完了した（exit 1・未網羅検出のため想定内）"
  fi

  # --- 1-111自己テスト追加分: 成功時メッセージの検査数がCHECK_NAMES登録数と一致すること ---
  registered_count="$(printf '%s\n' $CHECK_NAMES | wc -l | tr -d ' ')"
  full_output="$(bash "$0" "$tmp/pass.md" "$tmp/repo" 2>&1)" || true
  if echo "$full_output" | grep -q "全${registered_count}検査PASS"; then
    echo "  [PASS] 1-111: 成功時メッセージの検査数(${registered_count})がCHECK_NAMES登録数と一致"
  else
    echo "  [FAIL] 1-111: 成功時メッセージの検査数がCHECK_NAMES登録数(${registered_count})と一致しない" >&2
    echo "$full_output" >&2
    rc=1
  fi

  # --- 1-115自己テスト追加分: 実在しないことを示す否定文脈マーカー「非実在:」 ---
  cat > "$tmp/notexist-pass.md" <<MD
## エントリポイント
\`非実在:src/legacy/removed.ts\` は過去に存在したが削除済みで、現在は存在しない。
MD

  if check_paths_exist "$tmp/notexist-pass.md" "$tmp/repo" >/dev/null 2>&1; then
    echo "  [PASS] 検査1(1-115): 非実在マーカー付きの実在しないパスは実在チェック対象外として通過"
  else
    echo "  [FAIL] 検査1(1-115): 非実在マーカー付きなのにexit 1になった" >&2
    rc=1
  fi

  cat > "$tmp/notexist-fail.md" <<MD
## エントリポイント
\`src/legacy/removed.ts\` は過去に存在したが削除済みで、現在は存在しない。
MD

  if check_paths_exist "$tmp/notexist-fail.md" "$tmp/repo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査1(1-115): マーカー無しで実在しないパスを記述したのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査1(1-115): マーカー無しで実在しないパスを記述するとexit 1"
  fi

  # --- 1-116自己テスト追加分: ワークスペース定義なしで複数サイト行を持つ調査書 ---
  # Webサーバー設定のドキュメントルート検出（SKILL.md手順）の結果、ワークスペース定義が
  # 無くてもサイト一覧が2行以上になり得ることを検査6で確認する。
  multisite_repo="$tmp/multisite-repo"
  mkdir -p "$multisite_repo/public" "$multisite_repo/admin-assets"
  : > "$multisite_repo/package.json"

  cat > "$tmp/multisite.md" <<MD
## プロジェクト形態とサイト構成
| 項目 | 内容 | 参照先 |
|---|---|---|
| プロジェクト形態 | 単独プロジェクト | \`package.json\` |
| ワークスペース定義 | 実在しない（ワークスペース定義ファイルが見つからないため） | \`package.json\` |

### サイト一覧
| サイトキー | 表示名 | ルートディレクトリ | ビルドコマンド | 起動コマンド | 参照先 |
|---|---|---|---|---|---|
| web | 利用者サイト | public | npm run build | npm run dev | \`nginx.conf\` |
| admin | 管理画面 | admin-assets | npm run build:admin | npm run dev:admin | \`nginx.conf\` |
MD

  if check_project_form "$tmp/multisite.md" "$multisite_repo" >/dev/null 2>&1; then
    echo "  [PASS] 検査6(1-116): ワークスペース定義なしでも複数サイト行(2件)が実在ルートで通過"
  else
    echo "  [FAIL] 検査6(1-116): ワークスペース定義なしの複数サイト行がexit 1になった" >&2
    rc=1
  fi

  # --- 改善課題: 調査書-責務マップの粒度が未定義 ---
  # 検査5(ディレクトリ網羅性検査)が機械的に何を要求しているかを、調査書を書く担当者が
  # SKILL.md本文から読み取れるかを検査する。粒度要件(自身または親としての記載義務)と
  # 対象外ディレクトリ表の1行1パス推奨が明記されていなければ、担当ごとに粒度判断が割れる
  # (2026-08-11の再検証でフロントエンド・バックエンドのルート自体やテスト関連ディレクトリが
  # 未網羅として32件不合格になった実例)。
  skill_md="$SCRIPT_DIR/../SKILL.md"
  if grep -q '自身または親として記載されている' "$skill_md" 2>/dev/null; then
    echo "  [PASS] SKILL.mdに§4責務マップの粒度要件（自身または親として記載）が明記されている"
  else
    echo "  [FAIL] SKILL.mdに§4責務マップの粒度要件が明記されていない" >&2
    rc=1
  fi
  if grep -q '1行1パス' "$skill_md" 2>/dev/null; then
    echo "  [PASS] SKILL.mdに対象外ディレクトリ表の1行1パス推奨が明記されている"
  else
    echo "  [FAIL] SKILL.mdに対象外ディレクトリ表の1行1パス推奨が明記されていない" >&2
    rc=1
  fi

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

survey="${1:?使い方: check-architecture-survey.sh <調査書パス> <target_repo_path>}"
repo="${2:?使い方: check-architecture-survey.sh <調査書パス> <target_repo_path>}"

if [ ! -f "$survey" ]; then
  echo "エラー: 調査書が見つかりません: $survey" >&2
  exit 2
fi
if [ ! -d "$repo" ]; then
  echo "エラー: target_repo_path が見つかりません: $repo" >&2
  exit 2
fi

if run_all_checks "$survey" "$repo"; then
  final_status=0
else
  final_status=$?
fi
echo "アーキテクチャ調査書ゲート総括: 合格=${CHECK_PASS_COUNT} 不合格=${CHECK_FAIL_COUNT} 判定不能=${CHECK_UNKNOWN_COUNT} 登録検査数=${CHECK_COUNT}"
case "$final_status" in
  0)
    echo "アーキテクチャ調査書ゲート: 全${CHECK_COUNT}検査PASS"
    exit 0
    ;;
  1)
    echo "アーキテクチャ調査書ゲート: FAIL（不合格=${CHECK_FAIL_COUNT} 判定不能=${CHECK_UNKNOWN_COUNT}）" >&2
    exit 1
    ;;
  *)
    echo "アーキテクチャ調査書ゲート: UNKNOWN（判定不能=${CHECK_UNKNOWN_COUNT}、他の検査は完了）" >&2
    exit 2
    ;;
esac
