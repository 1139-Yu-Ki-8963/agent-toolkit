#!/usr/bin/env bash
set -u

# extract-code-readings.sh — 調査と検出条件の定義書の取り出しの規則を実行し、単位ごとの読み取り結果を作る
#
# 目的:
#   調査と検出条件の定義書の節4の当該種別にある「読み取り結果の項目 | どの構文・記述から取るか」の表
#   （取り出しの規則）を解釈し、一覧の元データが持つ単位ごとに、コードから
#   読み取り結果（入力項目・表示項目 等、種別ごとに定めた項目）を機械で取り出して
#   固定する。取り出しの規則が「AIの読み取り」の項目は機械では取り出さず、
#   値を空のまま「未」へ載せ、AIが後で埋める対象として残す。取り直し（再実行）
#   のとき、AIの読み取りの項目は既存の読み取り結果ファイルの値・根拠を引き継ぐ
#   （出所がAIの場合のみ）。機械で埋める項目は取り直しのたびに毎回コードから
#   取り直し、既存の値を引き継がない（第1回改善指示書1-37）。
#
# 使い方:
#   extract-code-readings.sh <対象リポジトリのルート> --run <実行フォルダ> --kind <種別> [--design-root <設計書の置き場>]
#     [--map <調査と検出条件の定義書のパス>] [--lists <一覧の元データの場所>]
#     [--out <code-readings の親>] [--unit <識別子>] [--verify] [--no-units-status]
#   extract-code-readings.sh --self-test
#
# --no-units-status を付けると単位の状態のファイルへ書き込まない。
# --verify は --no-units-status の指定に関わらず常に書き込みを行わない。
#
# --design-root の既定は <対象リポジトリのルート>。--map・--lists の既定はこの値の配下。
# --map の既定は <対象>/docs/design/common/調査と検出条件の定義書.md。
# --lists の既定は <対象>/docs/design/lists。
# --out の既定は <実行フォルダ>/code-readings。
# --unit を付けると、一覧の識別子（list-units-of.shの1列目）が一致する単位1件
#   だけを取り直す。他の単位の読み取り結果ファイルには触れない（中身も更新
#   時刻も変わらない）。一覧に無い識別子を渡すと、何も書かずに検査キー
#   「単位-不在」で終了コード2を返す（第1回改善指示書1-37）。
# --verify を付けると、既存の <out>/<種別>/ ともう一度取り出した結果を
#   compare-code-readings.sh で比べる。差分が0件なら「検証: 一致」に続けて
#   「未の項目: N」（Nは未の項目の総数）を出し終了コード0で返す。未の項目が
#   あっても差分が0件なら合格として扱う。差分が1件以上あれば終了コード1で
#   返す（このとき --out は上書きしない）。差分が0件でも、再取り出しが1
#   （規則を解釈できない項目・属するファイルの不在）を返せば終了コード1で返す。
#
# 取り出しの規則の書式（調査と検出条件の定義書の節4「検出条件の形の制約」に定める）:
#   正規表現: <ERE> ／ 捕捉: <N> ／ 範囲: <場所|属するファイル|両方|単位|単位の定義>
#   （区切りは全角スラッシュ「 ／ 」。捕捉の既定1、範囲の既定 両方。
#    セル内の \| は | に戻す。範囲の値は前方一致で読む。例えば
#    「場所（画面ファイル）」は「場所」として扱う。ただし「単位の定義」は
#    「単位」より先に照合し「単位」へ丸められないようにする）
#   または
#   AI の読み取り: <説明>
#
# 範囲の意味:
#   場所・単位: 一覧の根拠（<場所>:<行>）が指す単位の区間だけを走査する。
#     区間は根拠の行から、同じ場所（ファイル）内で次に大きい行を持つ別の
#     単位の直前の行まで（同じ場所を持つ他の単位が無ければファイル末尾）。
#     1ファイルに1単位しか無い場合は区間がファイル全体に一致する。
#     「単位」は「属するファイルを読まない」ことを強調した場所の別名。
#   単位の定義: 場所・単位と同じ開始行を使うが、終端を一覧の次の単位の
#     直前の行ではなく、定義を開く文の行以降で最初に開く括弧（丸・角・波
#     の3種をまとめて1つの残高で数える）が閉じる行までとする。残高は
#     文字ごとに数え、`(`・`[`・`{` で+1、`)`・`]`・`}` で-1とする。減算で
#     残高が0に戻った直後、空白を除く次の文字が`;`のときはその行を終端
#     とし残りの文字は数えない（例: `CREATE TABLE t (id INT);`は1行、
#     `); CREATE TABLE zombi (`は`;`で終端）。`;`以外で行が終わるときは、
#     探索範囲内の次の空白でない行の、空白を除く最初の文字が波括弧`{`か
#     どうかで先読みする。波括弧なら終端にせず数え続け、そうでなければ
#     その行を終端とする（丸括弧`(`・角括弧`[`では続行しない。例:
#     `function Foo(props) {`は対応する`}`の行が終端。波括弧を次行に置く
#     様式（`function foo($x)`の次行が`{`）は先読みにより`{`のある行へ
#     進み、対応する`}`の行が終端になる）。次の文字が`;`でも行末でもなけ
#     ればそのまま数え続ける（例: `def f(x):`は`:`の次で数え続けるが行末
#     で0のため1行）。探索は一覧の次の単位の直前の行までに限る（この境界
#     を超えて次の単位の閉じ括弧を誤って終端に採ることを防ぐ）。一覧から
#     意図して除外した定義（廃止されたもの）が直前の単位と次の単位の間に
#     残っていても、この終端決定で除外された定義の内容を隣の単位が取り
#     込まない。最初の開き括弧が現れる前に探索範囲が尽きるか、範囲内で
#     残高が0に戻らなければ、従来の終端（一覧の次の単位の直前の行）に
#     落ちる。既知の限界は6つある。本体を括弧で囲まない定義（Pythonの
#     `def`、Rubyの`end`等）は開始行だけになる。ただし次の行が`{`で始ま
#     る場合は続行する。デコレータや注釈の行から始まる定義は、デコレー
#     タの括弧が閉じる行までになり、本体は取れない（開始行が定義の文の
#     行になるよう検出条件を書く）。署名と`{`の間にコメント行があるとき
#     も同様に開始行だけになる（先読みは空行だけを飛ばし、コメント行は
#     飛ばさない）。文字列やコメントの中の括弧も数えるため、閉じ括弧が
#     あれば定義の途中で終端になり（欠落）、開き括弧があれば閉じずに
#     従来の終端まで伸びる（取り込み）。切り出しは行単位のため、次の
#     定義が一覧に無いときは終端の行の残り全体を取り込み、一覧に載る
#     次の単位が同じ行から始まるときは探索範囲がその手前で切れ、終端が
#     決まらず従来の終端に落ちる（行粒度）。メソッド連鎖（`.get(…)`を
#     次の行に続ける書き方）は最初の呼び出しの括弧が閉じた行で終端に
#     なり、続く連鎖を取れない（開始行を連鎖の全体を含む文にする検出
#     条件を書く）
#     （第1回改善指示書1-28）。
#   属するファイル: 一覧の属するファイルの各要素をglobとして対象ルートから
#     展開し、実在するファイルだけを走査する。属するファイルは検出条件の
#     規則の文字列であり、単位ごとに実在するとは限らない。展開結果が0件の
#     要素は警告に留め、不合格にはしない。
#   両方: 場所（単位の区間）と属するファイル（展開結果）の両方を走査する。
#
# 読み取り結果ファイルの形（<out>/<種別>/<単位のフォルダ名>.json）:
#   {"種別","識別子","表示名","場所","属するファイル":[...],
#    "読み取り結果":{"<項目>":{"値":[...],"出所":"機械"|"AI","根拠":[...]}},
#    "未":[...],"取り出した実行":"<実行の識別子>"}
#   フォルダ名はlist-units-of.shの出力（5列目）をそのまま使う。識別子から
#   unit-dir-name.shを直接呼んで作り直すことはしない。
#   値は常に配列。機械で0件だった項目・AIの読み取りの項目は値[]で「未」に
#   載る。捕捉した文字列が空文字列であっても、一致自体があれば正当な値
#   （空文字列）として値に載せ、未には載せない。
#
# 終了コード:
#   0 = 全単位に読み取り結果がある（--verifyでは既存と再取り出しの差分が0件）
#   1 = 一覧の場所（単位そのものの所在）が対象に実在しない、または取り出しの規則の
#       2列目が規定の形（正規表現|AIの読み取り）のどちらでもなく解釈できない項目がある
#       （--verifyでは差分が1件以上、または再取り出しが1を返した）（差し戻し: 検出条件-見直し）
#       （解釈できない項目は集計.jsonの「規則の無い項目」へ列挙し警告を出す）
#   2 = 使い方の誤り・調査と検出条件の定義書や一覧の不在（判定不能）。--unitで
#       指定した識別子が一覧に無い場合も含む（検査キー「単位-不在」）
#
# 保守責任者: 人手（ユーザー）。取り出しの規則の書式を変えるときは、調査と検出条件の定義書の
#   様式（reverse-writing-survey-definition）と本スクリプトと自己テストを同時に直す。
#
# 廃棄条件: 取り出しの規則の形を別の仕組み（構文解析器など）に置き換えた時。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_SCRIPTS="$(cd "${SCRIPT_DIR}/../../reverse-shared/scripts" && pwd)"

usage_error() {
  echo "使い方: extract-code-readings.sh <対象リポジトリのルート> --run <実行フォルダ> --kind <種別> [--design-root <設計書の置き場>] [--map <調査と検出条件の定義書のパス>] [--lists <一覧の元データの場所>] [--out <code-readings の親>] [--unit <識別子>] [--verify] [--no-units-status]" >&2
  echo "        extract-code-readings.sh --self-test" >&2
  exit 2
}

is_valid_kind() {
  case "$1" in
    screen|api|table|batch|report|external|feature) return 0 ;;
    *) return 1 ;;
  esac
}

kind_ja() {
  case "$1" in
    screen) echo "画面" ;;
    api) echo "接続窓口" ;;
    table) echo "表" ;;
    batch) echo "バッチ" ;;
    report) echo "帳票" ;;
    external) echo "外部連携" ;;
    feature) echo "機能" ;;
    *) echo "" ;;
  esac
}

trim() {
  local v="$1"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  printf '%s' "$v"
}

# --- 調査と検出条件の定義書の節0にある「文字コード」の値を読む。無ければUTF-8とみなす
#     （list-units.shと同じ方式。reverse-sharedへは寄せず本ファイルへ
#     複製している。scripts/ は機能ごとに独立して持つという既存の切り方
#     に合わせ、依存を増やさないための複製） ---
read_charset() {
  local map="$1" row cs
  row="$(grep -E '^\|[[:space:]]*文字コード[[:space:]]*\|' "$map" | head -n1)"
  if [ -z "$row" ]; then
    printf 'UTF-8'
    return 0
  fi
  cs="$(printf '%s' "$row" | awk -F'|' '{print $3}')"
  cs="$(trim "$cs")"
  if [ -z "$cs" ]; then
    cs="UTF-8"
  fi
  printf '%s' "$cs"
}

# --- 文字コードがUTF-8でない場合、UTF-8化した一時ファイルのパスを返す
#     （キャッシュ済みなら再利用する）。変換に失敗すれば空文字を返し
#     非0で返る（list-units.shと同じ方式） ---
utf8_path_for() {
  local f="$1" charset="$2" cache_dir="$3"
  if [ "$charset" = "UTF-8" ]; then
    printf '%s' "$f"
    return 0
  fi
  local key cached
  key="$(printf '%s' "$f" | shasum -a 256 | awk '{print $1}')"
  cached="${cache_dir}/${key}"
  if [ -f "$cached" ]; then
    printf '%s' "$cached"
    return 0
  fi
  if iconv -f "$charset" -t UTF-8 "$f" > "$cached" 2>/dev/null; then
    printf '%s' "$cached"
    return 0
  fi
  rm -f "$cached" 2>/dev/null
  return 1
}

# --- 調査と検出条件の定義書の節4の当該種別の「目印」欄が「対象外」かどうかを判定する ---
kind_is_out_of_scope() {
  local map="$1" kind="$2" ja
  ja="$(kind_ja "$kind")"
  [ -n "$ja" ] || return 1

  local mark
  mark="$(awk -v ja="$ja" '
    BEGIN { infile = 0 }
    $0 ~ ("^### 4\\.[0-9]+ " ja "$") { infile = 1; next }
    infile && /^### / { exit }
    infile && /^## / { exit }
    infile && /^\| 目印 \|/ { print; exit }
  ' "$map")"
  case "$mark" in
    *"| 対象外 |"*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- 調査と検出条件の定義書の節4の当該種別の「読み取り結果の項目 | どの構文・記述から取るか」の表を
#     生の行（"| 項目 | 規則 |"）のまま返す ---
read_extraction_rule_rows() {
  local map="$1" kind="$2" ja
  ja="$(kind_ja "$kind")"
  [ -n "$ja" ] || return 1

  local block
  block="$(awk -v ja="$ja" '
    BEGIN { infile = 0 }
    $0 ~ ("^### 4\\.[0-9]+ " ja "$") { infile = 1; next }
    infile && /^### / { exit }
    infile && /^## / { exit }
    infile { print }
  ' "$map")"
  [ -n "$block" ] || return 1

  local header_line
  header_line="$(printf '%s\n' "$block" | grep -n -F -x '| 読み取り結果の項目 | どの構文・記述から取るか |' | head -n1 | cut -d: -f1)"
  [ -n "$header_line" ] || return 1

  local start=$((header_line + 2))
  printf '%s\n' "$block" | awk -v start="$start" '
    NR < start { next }
    /^\|/ { print; next }
    { exit }
  '
}

# --- "| 項目 | 規則 |" の1行を "項目<TAB>規則" に変換する（\| は | に戻す） ---
parse_rule_row() {
  local row="$1" placeholder="@@ESCPIPE@@"
  local esc="${row//\\|/$placeholder}"
  local item rule
  item="$(printf '%s' "$esc" | awk -F'|' '{print $2}')"
  rule="$(printf '%s' "$esc" | awk -F'|' '{print $3}')"
  item="$(trim "$item")"
  rule="$(trim "$rule")"
  item="${item//$placeholder/|}"
  rule="${rule//$placeholder/|}"
  printf '%s\t%s' "$item" "$rule"
}

# --- 調査と検出条件の定義書の節4の当該種別の取り出しの規則を "項目<TAB>規則" の行群で返す ---
read_extraction_rules() {
  local map="$1" kind="$2" rows row
  rows="$(read_extraction_rule_rows "$map" "$kind")" || return 1
  [ -n "$rows" ] || return 1
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    parse_rule_row "$row"
    printf '\n'
  done <<ROWLIST
$rows
ROWLIST
}

# --- 「範囲:」の値を前方一致で正規の値へ寄せる。調査と検出条件の定義書が補足を括弧で付けて
#     も読める（例: 「場所（画面ファイル）」→「場所」）。前方一致で判定
#     できない値は既定の「両方」に寄せる ---
normalize_scope() {
  local raw="$1"
  case "$raw" in
    属するファイル*) printf '属するファイル' ;;
    両方*) printf '両方' ;;
    単位の定義*) printf '単位の定義' ;;
    単位*) printf '単位' ;;
    場所*) printf '場所' ;;
    *) printf '両方' ;;
  esac
}

# --- 規則の文字列を解釈する。標準出力:
#     "MACHINE<TAB><regex><TAB><capture><TAB><scope>" または "AI<TAB><説明>"
#     解釈できなければ何も出さず非0で返る ---
parse_rule() {
  local rule="$1"
  case "$rule" in
    "AI の読み取り:"*)
      local desc="${rule#AI の読み取り:}"
      desc="$(trim "$desc")"
      printf 'AI\t%s' "$desc"
      return 0
      ;;
  esac

  local regex="" capture="1" scope="両方"
  local rest="$rule" part
  while [ -n "$rest" ]; do
    case "$rest" in
      *"／"*)
        part="${rest%%／*}"
        rest="${rest#*／}"
        ;;
      *)
        part="$rest"
        rest=""
        ;;
    esac
    part="$(trim "$part")"
    case "$part" in
      正規表現:*)
        regex="${part#正規表現:}"
        regex="$(trim "$regex")"
        ;;
      捕捉:*)
        capture="${part#捕捉:}"
        capture="$(trim "$capture")"
        ;;
      範囲:*)
        scope="${part#範囲:}"
        scope="$(trim "$scope")"
        ;;
    esac
  done

  [ -n "$regex" ] || return 1
  scope="$(normalize_scope "$scope")"
  printf 'MACHINE\t%s\t%s\t%s' "$regex" "$capture" "$scope"
  return 0
}

# --- 正規表現の捕捉数（エスケープされていない開き括弧の数）を数える ---
count_capture_groups() {
  local regex="$1" stripped cnt
  stripped="$(printf '%s' "$regex" | sed -E 's/\\\(//g; s/\\\)//g')"
  cnt="$(printf '%s' "$stripped" | tr -dc '(' | wc -c | tr -d ' ')"
  printf '%s' "$cnt"
}

# --- 内容の1行から、正規表現のN番目の捕捉を取り出す。標準出力に値を出し
#     0で返る（捕捉が空文字列でも0で返る）。一致が無い、または捕捉番号が
#     正規表現の括弧の数を超える場合は何も出さず非0で返る ---
capture_group_n() {
  local content="$1" regex="$2" n="$3" matched groups cap
  case "$n" in
    ''|*[!0-9]*) return 1 ;;
  esac
  matched="$(printf '%s' "$content" | grep -oE "$regex" | head -n1)"
  [ -n "$matched" ] || return 1
  groups="$(count_capture_groups "$regex")"
  if [ "$n" -lt 1 ] || [ "$groups" -lt "$n" ]; then
    return 1
  fi
  cap="$(printf '%s' "$matched" | sed -E "s/^${regex}\$/@@CAPBEGIN@@\\${n}@@CAPEND@@/" 2>/dev/null)"
  case "$cap" in
    @@CAPBEGIN@@*@@CAPEND@@)
      cap="${cap#@@CAPBEGIN@@}"
      cap="${cap%@@CAPEND@@}"
      printf '%s' "$cap"
      return 0
      ;;
  esac
  return 1
}

# --- 対象ルート内でglobパターンを展開し、対象ルートからの相対パスを返す ---
expand_glob_in_target() {
  local target="$1" pattern="$2"
  ( cd "$target" 2>/dev/null || exit 1
    compgen -G "$pattern" 2>/dev/null )
}

# --- 属するファイル（; 区切りの規則の文字列）をglobとして展開し、実在する
#     ファイルの相対パスを重複なく返す。展開結果が0件の要素は警告のみで
#     不合格にしない ---
resolve_belongs_files() {
  local target="$1" belongs="$2" kind="$3" id="$4"
  [ -n "$belongs" ] || return 0
  printf '%s\n' "$belongs" | tr ';' '\n' | while IFS= read -r pattern; do
    [ -n "$pattern" ] || continue
    local matches
    matches="$(expand_glob_in_target "$target" "$pattern")"
    if [ -z "$matches" ]; then
      echo "[WARN] 属するファイル-一致なし: ${kind}/${id}: ${pattern}" >&2
    else
      printf '%s\n' "$matches"
    fi
  done | awk 'NF' | awk '!seen[$0]++'
}

# --- フォルダ名の重複判定にperl（Unicode::Normalize・fc。fcはperl 5.16
#     以降の機能）を使うための前提を確かめる。使えなければ0以外を返す
#     （呼び出し側が検査キー付きの理由を標準エラーへ出し終了コード2で
#     止める。第1回改善指示書1-30・第2版反証）。perlが無い、または
#     Unicode::Normalizeもしくはfcが使えない環境でclassify_dirname()を
#     呼ぶと、判定できないまま空・想定外の出力を返し、フォルダ名-空/
#     フォルダ名-不正/フォルダ名-重複の検査を素通りしてしまう
#     （fail-open）ため、単位を処理する前に呼び出し側で確かめる。
#     classify_dirname()が実際に使う1行（fc(NFC("A"))が"a"を返すか）と
#     同じ形で確かめる。`perl -MUnicode::Normalize -e 1`だけの確認では
#     Unicode::Normalizeの読み込み可否しか分からず、fcが無い環境（perl
#     5.16未満）でも前提検査を誤って通過してしまう
#     （第1回改善指示書1-30・第3版反証）。 ---
check_dirname_classifier_prerequisite() {
  [ "$(perl -CSDA -MUnicode::Normalize -Mfeature=fc,unicode_strings -e 'print fc(NFC("A"))' 2>/dev/null)" = "a" ]
}

# --- フォルダ名（list-units-of.shの5列目）を検査する。標準出力に
#     "EMPTY"（空白・不可視文字を除いて空）、"INVALID"（書き込み先として
#     使えない値）、または "OK\t<正規化した名前>" のいずれかを1行返す
#     （第1回改善指示書1-30・反証）。呼び出し側は
#     check_dirname_classifier_prerequisite() で前提を確かめてから呼ぶ。
#     空白・不可視文字は半角空白・全角空白U+3000・タブ・改行・ゼロ幅空白
#     U+200B・BOM U+FEFFとする（list-units-of.shの表示名の空白判定と同じ
#     集合）。これを除いて空ならEMPTY。EMPTYでなければ、/ を含む・"." また
#     は".."・\ を含む・制御文字0x00-0x1F/0x7Fを含む・先頭が"."のいずれか
#     でINVALIDとする（出力先の外へ書く・不可視のファイルになる等を防ぐ）。
#     どちらでもなければUnicodeのNFCへ揃えたうえで大文字小文字を畳み込んだ
#     （`fc`。perl 5.16以降）値を返す（大文字小文字だけ・NFC/NFDの合成分解
#     だけ・ß と ss のような畳み込みだけが違う名前を同じフォルダ名として
#     重複検査で捉えるため）。 ---
classify_dirname() {
  local name="$1"
  perl -CSDA -MUnicode::Normalize -Mfeature=fc,unicode_strings -e '
    my $name = shift;
    my $trimmed = $name;
    $trimmed =~ s/[\s\x{3000}\x{200B}\x{FEFF}]//g;
    if ($trimmed eq "") {
      print "EMPTY\n";
      exit 0;
    }
    if ($name =~ m{/} || $name eq "." || $name eq ".." || $name =~ /\\/ || $name =~ /[\x00-\x1F\x7F]/ || $name =~ /^\./) {
      print "INVALID\n";
      exit 0;
    }
    print "OK\t" . fc(NFC($name)) . "\n";
  ' "$name"
}

# --- classify_dirname() の1件分の結果を \037 区切りの1行レコードへ
#     変換する。EMPTY/INVALIDはそのまま、"OK\t<正規化した名前>"は
#     OKとして扱う。それ以外（前提の確認漏れ・classify_dirname自体が
#     想定外の値を返す異常）はOKとして扱わずINVALIDへ倒す
#     （fail-closed。第1回改善指示書1-30・第2版反証）。この判定を
#     $( ) の直下に置くとbash 3.2の既知のパーサ不具合（case文の中の
#     ")"を$( )の終端と誤認する）で構文エラーになるため、独立した
#     関数へ切り出す。 ---
classify_dirname_row() {
  local cid="$1" cdn="$2" ccls
  ccls="$(classify_dirname "$cdn")"
  case "$ccls" in
    EMPTY)
      printf 'EMPTY\037%s\n' "$cid"
      ;;
    OK$'\t'*)
      printf 'OK\037%s\037%s\037%s\n' "$cid" "$cdn" "${ccls#OK$'\t'}"
      ;;
    *)
      printf 'INVALID\037%s\037%s\n' "$cdn" "$cid"
      ;;
  esac
}

# --- 範囲「単位の定義」の終端を、開始行以降で最初に開く括弧（丸・角・波
#     の3種をまとめて1つの残高）から数えて求める。文字ごとに残高を更新し
#     （開き+1・閉じ-1）、減算で残高が0に戻った直後、空白を除く次の文字が
#     ";" または "," のときはその行を終端とし残りの文字は数えない（","は
#     呼び出し式や配列要素の区切りであり本体が続かないため）。";" ・ ","
#     のいずれでもなく行が終わるときは、探索範囲内の次の空白でない行の、
#     空白を除く最初の文字が波括弧 "{" かどうかで先読みする。波括弧なら
#     終端にせず数え続け、そうでなければその行を終端とする（丸括弧 "(" ・
#     角括弧 "[" では続行しない）。次の文字が ";" ・ "," のいずれでも
#     行末でもなければそのまま数え続ける。探索は end（一覧の次の単位の
#     直前の行。0ならファイル末尾）までに限り、越えて探さない（先読みも
#     この上限を超えない）。標準出力に行番号を出し0で返る。最初の開き
#     括弧が現れる前に範囲が尽きる、または範囲内で残高が0に戻らない場合
#     は何も出さず非0で返る ---
find_definition_close_line() {
  local cf="$1" start="$2" end="$3"
  local close
  close="$(awk -v s="$start" -v e="$end" '
    function first_nonblank(str,    t) {
      t = str
      sub(/^[ \t]+/, "", t)
      return t
    }
    function is_opener(c) {
      return (c == "(" || c == "[" || c == "{")
    }
    # 開始行から先の最初の空白でない行を探し、その先頭が波括弧"{"かどうか
    # を返す（見つからなければ -1、波括弧でなければ -1、波括弧ならその
    # 行番号）。丸括弧"("・角括弧"["では続行しない（別の文の開始を誤って
    # 取り込むことを防ぐ）。探索範囲（upto）を超えない
    function next_open_ln(from, upto,    k, t) {
      for (k = from + 1; k <= upto; k++) {
        if (!(k in lines)) continue
        t = first_nonblank(lines[k])
        if (t == "") continue
        if (substr(t, 1, 1) == "{") return k
        return -1
      }
      return -1
    }
    NR < s { next }
    e > 0 && NR > e { exit }
    {
      line0 = $0
      sub(/\r+$/, "", line0)
      lines[NR] = line0
      last = NR
    }
    END {
      limit = (e > 0) ? e : last
      opened = 0
      bal = 0
      last_close = ""
      for (ln = s; ln <= limit; ln++) {
        if (!(ln in lines)) continue
        line = lines[ln]
        n = length(line)
        done = 0
        for (i = 1; i <= n; i++) {
          c = substr(line, i, 1)
          if (!opened) {
            if (is_opener(c)) { opened = 1; bal = 1 }
            continue
          }
          if (is_opener(c)) {
            bal++
          } else if (c == ")" || c == "]" || c == "}") {
            bal--
            if (bal == 0) {
              last_close = c
              j = i + 1
              while (j <= n) {
                cj = substr(line, j, 1)
                if (cj == " " || cj == "\t") { j++; continue }
                break
              }
              if (j <= n && (substr(line, j, 1) == ";" || substr(line, j, 1) == ",")) { print ln; done = 1; exit }
            }
          }
        }
        if (opened && bal == 0 && !done) {
          if (last_close == ")" && next_open_ln(ln, limit) != -1) { continue }
          print ln; exit
        }
      }
    }
  ' "$cf" 2>/dev/null)"
  [ -n "$close" ] || return 1
  printf '%s' "$close"
}

# --- 一覧の元データ（<種別>.json）の識別子・場所・根拠から、単位ごとの
#     区間（開始行・終了行）を求める。標準出力: 識別子<TAB>場所<TAB>開始行
#     <TAB>終了行（0はファイル末尾までを表す）。
#     区間 = 根拠の行から、同じ場所で次に大きい行を持つ別の単位の直前の
#     行まで（無ければファイル末尾）。1ファイル1単位なら区間はファイル
#     全体に一致する。範囲が「単位の定義」のときは、この区間の終端は
#     find_definition_close_line() の探索の上限として渡し、括弧の対応で
#     求めた行が求まればそちらを使う ---
compute_unit_ranges() {
  local lists_file="$1"
  [ -f "$lists_file" ] || return 0
  local raw
  raw="$(jq -r '.[] | [.["識別子"], .["場所"], (.["根拠"] // "")] | @tsv' "$lists_file" 2>/dev/null)"
  [ -n "$raw" ] || return 0

  awk -F'\t' '
    function line_of(ev,    tail, n, arr) {
      n = split(ev, arr, ":")
      if (n < 1) return 1
      tail = arr[n]
      if (tail ~ /^[0-9]+$/) return tail + 0
      return 1
    }
    {
      id[NR] = $1
      place[NR] = $2
      line[NR] = line_of($3)
      n = NR
    }
    END {
      for (i = 1; i <= n; i++) {
        best = 0
        for (j = 1; j <= n; j++) {
          if (place[j] == place[i] && line[j] > line[i]) {
            if (best == 0 || line[j] < best) best = line[j]
          }
        }
        endline = (best == 0) ? 0 : best - 1
        print id[i] "\t" place[i] "\t" line[i] "\t" endline
      }
    }
  ' <<< "$raw"
}

# --- 内容ファイル（対象ファイルの全体、または単位の区間を切り出した一時
#     ファイル）にregexを掛け、捕捉値・根拠（rel）をvalues_file/
#     evidence_fileへ積む ---
scan_regex_source() {
  local rel="$1" content_file="$2" regex="$3" capture="$4" values_file="$5" evidence_file="$6"
  local had_match=0 matchline cap
  while IFS= read -r matchline; do
    [ -n "$matchline" ] || continue
    had_match=1
    if cap="$(capture_group_n "$matchline" "$regex" "$capture")"; then
      if ! grep -qFx -- "$cap" "$values_file" 2>/dev/null; then
        printf '%s\n' "$cap" >> "$values_file"
      fi
    fi
  done < <(grep -E "$regex" "$content_file" 2>/dev/null)
  if [ "$had_match" -eq 1 ] && ! grep -qFx -- "$rel" "$evidence_file" 2>/dev/null; then
    echo "$rel" >> "$evidence_file"
  fi
}

# ============================================================
# 本処理
# ============================================================

do_extract() {
  local target="$1" kind="$2" map="$3" lists="$4" out="$5" exec_id="$6" run_dir="$7" no_status="${8:-0}" unit="${9:-}"

  if kind_is_out_of_scope "$map" "$kind"; then
    echo "対象外: ${kind} は調査と検出条件の定義書の目印が対象外のため取り出しを飛ばします"
    return 0
  fi

  local rules
  rules="$(read_extraction_rules "$map" "$kind")"
  if [ -z "$rules" ]; then
    echo "[FAIL] 規則-不在: 調査と検出条件の定義書に ${kind} の取り出しの規則がありません" >&2
    return 2
  fi

  local units units_rc
  units="$("$SHARED_SCRIPTS/list-units-of.sh" "$target" "$kind" --lists "$lists" 2>&1)"
  units_rc=$?
  if [ "$units_rc" -ne 0 ]; then
    echo "$units" >&2
    return 2
  fi

  # 出力先はフォルダ名（list-units-of.shの5列目）ごとに1ファイルへ落ちる。
  # フォルダ名が空・書き込み先として使えない値、または正規化して同じ値に
  # なる（大文字小文字だけ・NFC/NFDの合成分解だけ・ß と ss のような畳み
  # 込みだけの違いを含む）と、単位を取り違えたまま黙って上書き・欠落する、
  # または出力先の外へ書く（第1回改善指示書1-30・反証）。単位を処理する
  # 前にフォルダ名の空・不正・重複を検査し、あれば止める。この検査は
  # classify_dirname() がperl（Unicode::Normalize・fc）を前提とするため、
  # 前提が満たせない環境では判定できないまま検査を素通りする
  # （fail-open）。何も書く前に前提を確かめ、満たせなければ検査キー
  # 「前提-perl不在」で終了コード2として止める（第1回改善指示書1-30・
  # 第2版反証）。前提不成立の原因はperl本体・Unicode::Normalize・fc
  # （perl 5.16未満）のいずれかを区別しないため、メッセージも3つの
  # いずれかが原因でありうることを示す（第1回改善指示書1-30・
  # 第4版反証所見1）。フォルダ名の検査は --unit による絞り込みより前に、
  # 一覧の全単位に対して行う。絞り込んだ後の1件だけを見ると、一覧の他の
  # 部分に重複フォルダ名があっても検知できず、異なる識別子への --unit
  # 呼び出しが同じ出力ファイルへ黙って重ね書きする（第1回改善指示書
  # 1-37）。
  if ! check_dirname_classifier_prerequisite; then
    echo "[FAIL] 前提-perl不在: ${kind}: perl 5.16以降・Unicode::Normalize・fcのいずれかが使えないためフォルダ名の検査ができません" >&2
    return 2
  fi

  local classify_rows
  classify_rows="$(printf '%s' "$units" | awk -F'\t' '{print $1 "\037" $5}' | while IFS=$'\037' read -r cid cdn; do
    [ -n "$cid" ] || continue
    classify_dirname_row "$cid" "$cdn"
  done)"

  local dup_issues
  dup_issues="$(printf '%s\n' "$classify_rows" | awk -F'\037' '
    $1 == "OK" {
      id = $2; dn = $3; norm = $4
      if (!(norm in seen)) {
        order[++oc] = norm
        seen[norm] = 1
      }
      count[norm]++
      ids[norm] = (ids[norm] == "") ? id : ids[norm] ";" id
      dnkey = norm "\037" dn
      if (!(dnkey in dnseen)) {
        dnseen[dnkey] = 1
        dnlist[norm] = (dnlist[norm] == "") ? dn : dnlist[norm] ";" dn
      }
    }
    END {
      for (i = 1; i <= oc; i++) {
        n = order[i]
        if (count[n] > 1) {
          print "DUP\037" dnlist[n] "\037" ids[n]
        }
      }
    }
  ')"

  local issue_type issue_a issue_b had_dirname_issue=0
  while IFS=$'\037' read -r issue_type issue_a issue_b; do
    [ -n "$issue_type" ] || continue
    case "$issue_type" in
      EMPTY)
        had_dirname_issue=1
        echo "[FAIL] フォルダ名-空: ${kind}: 識別子=${issue_a}" >&2
        ;;
      INVALID)
        had_dirname_issue=1
        echo "[FAIL] フォルダ名-不正: ${kind}: フォルダ名=${issue_a} 識別子=${issue_b}" >&2
        ;;
    esac
  done <<CLASSIFYROWS
$classify_rows
CLASSIFYROWS

  if [ -n "$dup_issues" ]; then
    while IFS=$'\037' read -r issue_type issue_a issue_b; do
      [ -n "$issue_type" ] || continue
      had_dirname_issue=1
      echo "[FAIL] フォルダ名-重複: ${kind}: フォルダ名=${issue_a} 識別子=${issue_b}" >&2
    done <<DUPISSUES
$dup_issues
DUPISSUES
  fi

  if [ "$had_dirname_issue" -eq 1 ]; then
    return 2
  fi

  # --unit は一覧の識別子（1列目）が一致する単位1件だけに絞る。他の単位は
  # 一切処理しないため、その読み取り結果ファイルへは触れない（中身も更新
  # 時刻も変わらない）。一覧に無い識別子は何も書かずに検査キー「単位-不在」
  # で終了コード2にする（第1回改善指示書1-37）。フォルダ名の空・不正・
  # 重複の検査は、この絞り込みより前に一覧の全単位に対して済ませてある。
  if [ -n "$unit" ]; then
    local filtered_units unit_found
    filtered_units="$(printf '%s\n' "$units" | awk -F'\t' -v u="$unit" '$1==u{print; found=1} END{if(!found) exit 1}')"
    unit_found=$?
    if [ "$unit_found" -ne 0 ] || [ -z "$filtered_units" ]; then
      echo "[FAIL] 単位-不在: ${kind}/${unit} は一覧にありません" >&2
      return 2
    fi
    units="$filtered_units"
  fi

  mkdir -p "${out}/${kind}"
  local work
  work="$(mktemp -d "${TMPDIR:-/tmp}/extract-code-readings-work.XXXXXX")" || { echo "[FAIL] 一時領域-作成不能" >&2; return 2; }
  local charset
  charset="$(read_charset "$map")"
  local charset_cache="${work}/charset-cache"
  mkdir -p "$charset_cache"

  local lists_file="${lists%/}/${kind}.json"
  local ranges_file="${work}/unit-ranges.tsv"
  compute_unit_ranges "$lists_file" > "$ranges_file"

  local unit_count=0 machine_filled=0 mi_total=0 missing_total=0 ai_items="" invalid_items="" write_ok_count=0

  local item rule_cell parsed rtype
  while IFS=$'\t' read -r item rule_cell; do
    [ -n "$item" ] || continue
    if parsed="$(parse_rule "$rule_cell")"; then
      rtype="${parsed%%$'\t'*}"
      if [ "$rtype" = "AI" ]; then
        ai_items="${ai_items}${item}
"
      fi
    else
      invalid_items="${invalid_items}${item}
"
    fi
  done <<RULESLIST
$rules
RULESLIST

  local id name place belongs dirname
  # list-units-of.shの出力はタブ区切りだが、bashのreadはタブをIFSの空白と
  # みなし連続分をまとめて削る。属するファイル（4列目）が空でフォルダ名
  # （5列目）が非空という並びだと空欄が消えてフォルダ名が前の変数へずれ
  # 込むため、タブを一度\037（IFSの空白扱いされない制御文字）へ置換してから読む
  while IFS=$'\037' read -r id name place belongs dirname; do
    [ -n "$id" ] || continue
    unit_count=$((unit_count + 1))

    local belongs_json
    if [ -n "$belongs" ]; then
      belongs_json="$(printf '%s' "$belongs" | tr ';' '\n' | jq -R -s -c 'split("\n") | map(select(length>0))')"
    else
      belongs_json="[]"
    fi

    local range_row start_line end_line
    range_row="$(awk -F'\t' -v id="$id" '$1==id{print; exit}' "$ranges_file")"
    if [ -n "$range_row" ]; then
      start_line="$(printf '%s' "$range_row" | awk -F'\t' '{print $3}')"
      end_line="$(printf '%s' "$range_row" | awk -F'\t' '{print $4}')"
    else
      start_line=1
      end_line=0
    fi

    local items_jsonl="${work}/${dirname}.items.jsonl"
    : > "$items_jsonl"
    local mi_list="${work}/${dirname}.mi.txt"
    : > "$mi_list"
    local item_idx=0

    while IFS=$'\t' read -r item2 rule_cell2; do
      [ -n "$item2" ] || continue
      item_idx=$((item_idx + 1))
      local parsed2 rtype2
      parsed2="$(parse_rule "$rule_cell2")" || continue
      rtype2="${parsed2%%$'\t'*}"

      if [ "$rtype2" = "AI" ]; then
        # 取り直し（再実行）でAIが埋めた値を失わないよう、既存の読み取り
        # 結果ファイル（今回の書き込みで上書きされる前の内容）から、出所が
        # AIの同じ項目の値・根拠を引き継ぐ。機械で埋める項目はこの分岐を
        # 通らず、下のscopeの走査で毎回コードから取り直す（第1回改善指示書
        # 1-37）。
        local existing_file="${out}/${kind}/${dirname}.json"
        local prev_source prev_ai_v prev_ai_e
        prev_ai_v="[]"; prev_ai_e="[]"
        if [ -f "$existing_file" ]; then
          prev_source="$(jq -r --arg item "$item2" '.["読み取り結果"][$item]["出所"] // empty' "$existing_file" 2>/dev/null)"
          if [ "$prev_source" = "AI" ]; then
            local cand
            cand="$(jq -c --arg item "$item2" '.["読み取り結果"][$item]["値"] // []' "$existing_file" 2>/dev/null)"
            [ -n "$cand" ] && [ "$cand" != "null" ] && prev_ai_v="$cand"
            cand="$(jq -c --arg item "$item2" '.["読み取り結果"][$item]["根拠"] // []' "$existing_file" 2>/dev/null)"
            [ -n "$cand" ] && [ "$cand" != "null" ] && prev_ai_e="$cand"
          fi
        fi
        jq -n --arg item "$item2" --argjson v "$prev_ai_v" --argjson e "$prev_ai_e" \
          '{"項目": $item, "値": $v, "出所": "AI", "根拠": $e}' >> "$items_jsonl"
        if [ "$prev_ai_v" = "[]" ]; then
          echo "$item2" >> "$mi_list"
        fi
        continue
      fi

      local regex capture scope
      regex="$(printf '%s' "$parsed2" | awk -F'\t' '{print $2}')"
      capture="$(printf '%s' "$parsed2" | awk -F'\t' '{print $3}')"
      scope="$(printf '%s' "$parsed2" | awk -F'\t' '{print $4}')"

      local values_file="${work}/${dirname}.item${item_idx}.values.txt"
      local evidence_file="${work}/${dirname}.item${item_idx}.evidence.txt"
      : > "$values_file"
      : > "$evidence_file"

      local place_abs="${target}/${place}"
      local place_ok=1
      case "$scope" in
        場所|単位|両方|単位の定義)
          if [ ! -f "$place_abs" ]; then
            echo "[FAIL] 属するファイル-不在: ${kind}/${id}: ${place}" >&2
            missing_total=$((missing_total + 1))
            place_ok=0
          fi
          ;;
      esac

      case "$scope" in
        場所|単位|両方|単位の定義)
          if [ "$place_ok" -eq 1 ]; then
            local cf
            if cf="$(utf8_path_for "$place_abs" "$charset" "$charset_cache")" && [ -n "$cf" ]; then
              local slice_file="${work}/${dirname}.item${item_idx}.slice.txt"
              local effective_end="$end_line"
              if [ "$scope" = "単位の定義" ]; then
                local def_close
                if def_close="$(find_definition_close_line "$cf" "$start_line" "$end_line")"; then
                  effective_end="$def_close"
                fi
              fi
              if [ "$effective_end" = "0" ]; then
                sed -n "${start_line},\$p" "$cf" > "$slice_file" 2>/dev/null
              else
                sed -n "${start_line},${effective_end}p" "$cf" > "$slice_file" 2>/dev/null
              fi
              scan_regex_source "$place" "$slice_file" "$regex" "$capture" "$values_file" "$evidence_file"
            else
              echo "[WARN] 文字コード-変換失敗: ${kind}/${id}: ${place}" >&2
            fi
          fi
          ;;
      esac

      case "$scope" in
        属するファイル|両方)
          local belongs_files
          belongs_files="$(resolve_belongs_files "$target" "$belongs" "$kind" "$id")"
          local bf
          while IFS= read -r bf; do
            [ -n "$bf" ] || continue
            local babs="${target}/${bf}"
            [ -f "$babs" ] || continue
            local bcf
            if bcf="$(utf8_path_for "$babs" "$charset" "$charset_cache")" && [ -n "$bcf" ]; then
              scan_regex_source "$bf" "$bcf" "$regex" "$capture" "$values_file" "$evidence_file"
            else
              echo "[WARN] 文字コード-変換失敗: ${kind}/${id}: ${bf}" >&2
            fi
          done <<BELONGSFILES
$belongs_files
BELONGSFILES
          ;;
      esac

      local values_json evidence_json
      values_json="$(jq -R '.' "$values_file" | jq -s -c '.')"
      evidence_json="$(jq -R -s -c 'split("\n") | map(select(length>0))' "$evidence_file")"

      if [ "$values_json" = "[]" ]; then
        echo "$item2" >> "$mi_list"
      else
        machine_filled=$((machine_filled + 1))
      fi

      jq -n --arg item "$item2" --argjson v "$values_json" --argjson e "$evidence_json" \
        '{"項目": $item, "値": $v, "出所": "機械", "根拠": $e}' >> "$items_jsonl"
    done <<RULESLIST2
$rules
RULESLIST2

    local readings_json mi_json mi_count
    readings_json="$(jq -s 'map({(.["項目"]): {"値": .["値"], "出所": .["出所"], "根拠": .["根拠"]}}) | add // {}' "$items_jsonl")"
    mi_json="$(jq -R -s -c 'split("\n") | map(select(length>0)) | unique' "$mi_list")"
    mi_count="$(printf '%s' "$mi_json" | jq 'length')"
    mi_total=$((mi_total + mi_count))

    jq -n --arg v_kind "$kind" --arg v_id "$id" --arg v_name "$name" --arg v_place "$place" \
      --argjson v_belongs "$belongs_json" --argjson v_readings "$readings_json" \
      --argjson v_mi "$mi_json" --arg v_exec "$exec_id" \
      '{"種別": $v_kind, "識別子": $v_id, "表示名": $v_name, "場所": $v_place,
        "属するファイル": $v_belongs, "読み取り結果": $v_readings, "未": $v_mi,
        "取り出した実行": $v_exec}' > "${out}/${kind}/${dirname}.json"

    [ -s "${out}/${kind}/${dirname}.json" ] && write_ok_count=$((write_ok_count + 1))

    if [ "$no_status" != "1" ]; then
      if [ "$mi_count" -gt 0 ]; then
        "$SHARED_SCRIPTS/units-status.sh" "$run_dir" set "$kind" "$id" 読み取り結果 未 > /dev/null 2>&1
      else
        "$SHARED_SCRIPTS/units-status.sh" "$run_dir" set "$kind" "$id" 読み取り結果 済 > /dev/null 2>&1
      fi
    fi
  done <<UNITSLIST
$(printf '%s' "$units" | tr '\t' '\037')
UNITSLIST

  local ai_items_json invalid_items_json rule_free_json invalid_count
  ai_items_json="$(printf '%s' "$ai_items" | jq -R -s -c 'split("\n") | map(select(length>0))')"
  invalid_items_json="$(printf '%s' "$invalid_items" | jq -R -s -c 'split("\n") | map(select(length>0))')"
  rule_free_json="$(jq -n -c --argjson a "$ai_items_json" --argjson b "$invalid_items_json" '($a + $b) | unique')"
  invalid_count="$(printf '%s' "$invalid_items_json" | jq 'length')"

  jq -n --argjson u "$unit_count" --argjson m "$machine_filled" --argjson n "$mi_total" --argjson r "$rule_free_json" \
    '{"単位数": $u, "機械で埋まった項目数": $m, "未の項目数": $n, "規則の無い項目": $r}' \
    > "${out}/${kind}/集計.json"

  rm -rf "$work"

  # 単位数の報告と実ファイルの数が食い違わないことを確かめる（第1回改善
  # 指示書1-30）。フォルダ名の空・重複は既に上で止めているが、それ以外の
  # 理由（書き込み自体の失敗で実ファイルが欠ける、または単位が減った後も
  # 同じ--outへ出し続け前回の実行のファイルが残って余る）も見落とさない。
  # --unitで絞ったときは、出力先フォルダ全体には他の単位の既存ファイルが
  # 残っているのが正常な状態であり、フォルダ内の全ファイル数と比べると
  # 常に食い違う。この場合は絞った単位数（今回書き込んだファイル数）と
  # 比べる（第1回改善指示書1-37。1-30の検査とは対象を分ける）。
  local actual_file_count
  if [ -n "$unit" ]; then
    actual_file_count="$write_ok_count"
  else
    actual_file_count="$(find "${out}/${kind}" -maxdepth 1 -type f -name '*.json' ! -name '集計.json' | wc -l | tr -d ' ')"
  fi
  if [ "$actual_file_count" -ne "$unit_count" ]; then
    echo "[FAIL] 出力-件数不一致: ${kind}: 単位数=${unit_count} 実ファイル数=${actual_file_count}（出力先フォルダに前回実行の古いファイルが残っていないか確認する）" >&2
    return 2
  fi

  echo "単位数=${unit_count} 機械で埋まった項目数=${machine_filled} 未の項目数=${mi_total} 属するファイル不在=${missing_total}"

  if [ "$invalid_count" -gt 0 ]; then
    echo "[WARN] 規則-解釈不能: ${invalid_count} 件の項目の取り出しの規則を解釈できませんでした（集計の規則の無い項目を確認してください）"
  fi

  if [ "$missing_total" -gt 0 ] || [ "$invalid_count" -gt 0 ]; then
    return 1
  fi
  return 0
}

run_main() {
  local target="$1"; shift
  target="${target%/}"
  [ -d "$target" ] || usage_error

  local run_dir="" kind="" map="" lists="" out="" verify=0 design_root="" no_status=0 unit=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --run) run_dir="$2"; shift 2 ;;
      --kind) kind="$2"; shift 2 ;;
      --map) map="$2"; shift 2 ;;
      --lists) lists="$2"; shift 2 ;;
      --out) out="$2"; shift 2 ;;
      --design-root) design_root="$2"; shift 2 ;;
      --unit) unit="$2"; shift 2 ;;
      --verify) verify=1; shift ;;
      --no-units-status) no_status=1; shift ;;
      *) usage_error ;;
    esac
  done

  [ -n "$run_dir" ] || usage_error
  [ -n "$kind" ] || usage_error
  is_valid_kind "$kind" || usage_error

  [ -n "$design_root" ] || design_root="$target"

  [ -n "$map" ] || map="${design_root%/}/docs/design/common/調査と検出条件の定義書.md"
  [ -n "$lists" ] || lists="${design_root%/}/docs/design/lists"
  [ -n "$out" ] || out="${run_dir%/}/code-readings"

  if [ ! -f "$map" ]; then
    echo "[FAIL] 調査と検出条件の定義書-不在: ${map} が存在しません" >&2
    exit 2
  fi

  local exec_id
  if ! exec_id="$("$SHARED_SCRIPTS/read-run.sh" "$run_dir" 実行の識別子 2>&1)"; then
    echo "$exec_id" >&2
    exit 2
  fi

  mkdir -p "$out"

  if [ "$verify" -eq 1 ]; then
    if [ ! -d "${out}/${kind}" ]; then
      echo "[FAIL] 検証-既存無し: ${out}/${kind} がありません" >&2
      exit 2
    fi
    local verify_work
    verify_work="$(mktemp -d "${TMPDIR:-/tmp}/extract-code-readings-verify.XXXXXX")" || { echo "[FAIL] 一時領域-作成不能" >&2; exit 2; }
    do_extract "$target" "$kind" "$map" "$lists" "$verify_work" "$exec_id" "$run_dir" 1
    local extract_rc=$?
    if [ "$extract_rc" -eq 2 ]; then
      rm -rf "$verify_work"
      exit 2
    fi
    bash "$SCRIPT_DIR/compare-code-readings.sh" "$out" "$verify_work" --kind "$kind" > "${verify_work}.cmp.log" 2>&1
    local cmp_rc=$?
    cat "${verify_work}.cmp.log"
    local verify_mi
    verify_mi="$(jq -r '.["未の項目数"] // 0' "${verify_work}/${kind}/集計.json" 2>/dev/null)"
    [ -n "$verify_mi" ] || verify_mi=0
    rm -rf "$verify_work" "${verify_work}.cmp.log"
    if [ "$cmp_rc" -ne 0 ]; then
      echo "[FAIL] 検証-不一致: 既存の読み取り結果と再取り出しの読み取り結果が一致しません" >&2
      exit 1
    fi
    echo "検証: 一致"
    echo "未の項目: ${verify_mi}"
    if [ "$extract_rc" -ne 0 ]; then
      echo "[FAIL] 検証-取り出し不合格: 再取り出しが終了コード ${extract_rc} を返しました（規則を解釈できない項目、または属するファイルの不在があります）" >&2
      exit 1
    fi
    exit 0
  fi

  do_extract "$target" "$kind" "$map" "$lists" "$out" "$exec_id" "$run_dir" "$no_status" "$unit"
  exit $?
}

# ============================================================
# 自己テスト
# ============================================================

self_test() {
  local base
  base="$(mktemp -d "${TMPDIR:-/tmp}/extract-code-readings-self-test.XXXXXX")" || { echo "[FAIL] 自己テスト用一時領域を作れません"; return 2; }
  trap 'rm -rf "$base"' RETURN

  local total=0 fail=0

  check() {
    local name="$1" ok="$2"
    total=$((total + 1))
    if [ "$ok" -eq 0 ]; then
      echo "PASS: ${name}"
    else
      echo "FAIL: ${name}"
      fail=$((fail + 1))
    fi
  }

  make_fixture() {
    local d="$1"
    rm -rf "$d"
    mkdir -p "$d/src/pages" "$d/docs/design/common" "$d/docs/design/lists"

    cat > "$d/src/pages/OrderList.tsx" <<'FIXEOF'
<input name="orderId" />
onClickHandler: handleSubmit
FIXEOF

    cat > "$d/src/pages/OrderDetail.tsx" <<'FIXEOF'
export default function OrderDetail() {
  return null;
}
FIXEOF

    cat > "$d/docs/design/common/調査と検出条件の定義書.md" <<'FIXEOF'
# 調査と検出条件の定義書

## 4. 単位の見つけ方

### 4.1 画面

| 読み取り結果の項目 | どの構文・記述から取るか |
|---|---|
| 入力項目 | 正規表現: <input[[:space:]]+name="([a-zA-Z0-9_]+)" ／ 捕捉: 1 ／ 範囲: 場所 |
| 操作 | 正規表現: handle(Submit\|Cancel) ／ 捕捉: 1 ／ 範囲: 場所 |
| 呼ぶ接続窓口 | AI の読み取り: 呼び出し箇所を読んで判断する |

## 5. 動的な定義
FIXEOF

    cat > "$d/docs/design/lists/screen.json" <<'FIXEOF'
[
  {"種別":"screen","識別子":"src/pages/OrderList.tsx","名前":"OrderList","場所":"src/pages/OrderList.tsx","根拠":"src/pages/OrderList.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]},
  {"種別":"screen","識別子":"src/pages/OrderDetail.tsx","名前":"OrderDetail","場所":"src/pages/OrderDetail.tsx","根拠":"src/pages/OrderDetail.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF
  }

  make_run() {
    local r="$1"
    rm -rf "$r"
    mkdir -p "$r"
    cat > "$r/run.json" <<'FIXEOF'
{"対象リポジトリ":"/path/to/target","対象プロジェクト名":"サンプル対象プロジェクト","出力の置き場":"/path/to/ai-output","実行の識別子":"2026-09-03-abc1234","対象のコミット":"abc1234def"}
FIXEOF
  }

  # --- 合格-見本 ---
  local d1="$base/case1" r1="$base/run1"
  make_fixture "$d1"
  make_run "$r1"
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d1" --run "$r1" --kind screen --out "$r1/code-readings" > "$base/case1.out" 2>"$base/case1.err"
  local rc1=$?
  check "合格-見本: 終了コード0" "$([ "$rc1" -eq 0 ] && echo 0 || echo 1)"

  local orderlist_json="$r1/code-readings/screen/src_pages_OrderList.tsx.json"
  local orderdetail_json="$r1/code-readings/screen/src_pages_OrderDetail.tsx.json"
  check "OrderListの読み取り結果ファイルがある" "$([ -f "$orderlist_json" ] && echo 0 || echo 1)"

  local input_values
  input_values="$(jq -c '.["読み取り結果"]["入力項目"]["値"]' "$orderlist_json" 2>/dev/null)"
  check "入力項目の値がorderId" "$([ "$input_values" = '["orderId"]' ] && echo 0 || echo 1)"

  local action_values
  action_values="$(jq -c '.["読み取り結果"]["操作"]["値"]' "$orderlist_json" 2>/dev/null)"
  check "エスケープしたパイプを含む正規表現でSubmitを捕捉" "$([ "$action_values" = '["Submit"]' ] && echo 0 || echo 1)"

  local ai_source
  ai_source="$(jq -r '.["読み取り結果"]["呼ぶ接続窓口"]["出所"]' "$orderlist_json" 2>/dev/null)"
  check "AIの読み取りの項目は出所がAI" "$([ "$ai_source" = "AI" ] && echo 0 || echo 1)"

  local ai_mi
  ai_mi="$(jq -c '.["未"]' "$orderlist_json" 2>/dev/null)"
  case "$ai_mi" in
    *"呼ぶ接続窓口"*) check "呼ぶ接続窓口は未に載る" 0 ;;
    *) check "呼ぶ接続窓口は未に載る" 1 ;;
  esac

  local detail_input_values
  detail_input_values="$(jq -c '.["読み取り結果"]["入力項目"]["値"]' "$orderdetail_json" 2>/dev/null)"
  check "0件だった項目は値が空配列" "$([ "$detail_input_values" = '[]' ] && echo 0 || echo 1)"

  local detail_mi
  detail_mi="$(jq -c '.["未"]' "$orderdetail_json" 2>/dev/null)"
  case "$detail_mi" in
    *"入力項目"*) check "0件だった項目は未に載る" 0 ;;
    *) check "0件だった項目は未に載る" 1 ;;
  esac

  local exec_recorded
  exec_recorded="$(jq -r '.["取り出した実行"]' "$orderlist_json" 2>/dev/null)"
  check "取り出した実行にrun.jsonの値が入る" "$([ "$exec_recorded" = "2026-09-03-abc1234" ] && echo 0 || echo 1)"

  local status_ok status_mi
  status_ok="$(bash "${SHARED_SCRIPTS}/units-status.sh" "$r1" get screen "src/pages/OrderList.tsx" 読み取り結果)"
  status_mi="$(bash "${SHARED_SCRIPTS}/units-status.sh" "$r1" get screen "src/pages/OrderDetail.tsx" 読み取り結果)"
  check "未が有る単位は読み取り結果=未" "$([ "$status_mi" = "未" ] && echo 0 || echo 1)"
  check "未が有る単位は読み取り結果=未（OrderListも呼ぶ接続窓口がAI項目のため未）" "$([ "$status_ok" = "未" ] && echo 0 || echo 1)"

  local agg_json="$r1/code-readings/screen/集計.json"
  local agg_units agg_rule_free
  agg_units="$(jq -r '.["単位数"]' "$agg_json" 2>/dev/null)"
  agg_rule_free="$(jq -c '.["規則の無い項目"]' "$agg_json" 2>/dev/null)"
  check "集計の単位数が2" "$([ "$agg_units" = "2" ] && echo 0 || echo 1)"
  # macOS標準のbash3.2では、$( )の中に1行のcase ... esacを書くとパーサが
  # 誤ってesac以降を未解析のまま外へ漏らす既知の不具合があるため（実測:
  # 単発でも多バイトの有無を問わず再現）、caseではなく[[ ]]のワイルド
  # カード一致で判定する。
  check "集計の規則の無い項目に呼ぶ接続窓口を含む" "$([[ "$agg_rule_free" == *呼ぶ接続窓口* ]] && echo 0 || echo 1)"

  # --- 不合格-属するファイル不在（場所そのものが実在しない） ---
  local d2="$base/case2" r2="$base/run2"
  make_fixture "$d2"
  make_run "$r2"
  cat > "$d2/docs/design/lists/screen.json" <<'FIXEOF'
[
  {"種別":"screen","識別子":"src/pages/Missing.tsx","名前":"Missing","場所":"src/pages/Missing.tsx","根拠":"src/pages/Missing.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d2" --run "$r2" --kind screen --out "$r2/code-readings" > "$base/case2.out" 2>"$base/case2.err"
  local rc2=$?
  check "不合格-属するファイル不在: 終了コード1" "$([ "$rc2" -eq 1 ] && echo 0 || echo 1)"

  # --- 検証: 一致 ---
  local rc_verify_ok
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d1" --run "$r1" --kind screen --out "$r1/code-readings" --verify > "$base/verify_ok.out" 2>"$base/verify_ok.err"
  rc_verify_ok=$?
  check "検証-一致: 終了コード0" "$([ "$rc_verify_ok" -eq 0 ] && echo 0 || echo 1)"

  local expected_mi
  expected_mi="$(jq -r '.["未の項目数"]' "$r1/code-readings/screen/集計.json" 2>/dev/null)"
  case "$(cat "$base/verify_ok.out")" in
    *"未の項目: ${expected_mi}"*) check "検証-一致: 未の項目数を別行で出す（未が有っても合格）" 0 ;;
    *) check "検証-一致: 未の項目数を別行で出す（未が有っても合格）" 1 ;;
  esac

  # --- 検証: 不一致 ---
  local tampered="$r1/code-readings/screen/src_pages_OrderList.tsx.json"
  cp "$tampered" "${tampered}.bak"
  jq '.["読み取り結果"]["入力項目"]["値"] = ["改ざん"]' "$tampered" > "${tampered}.new" && mv "${tampered}.new" "$tampered"
  local rc_verify_ng
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d1" --run "$r1" --kind screen --out "$r1/code-readings" --verify > "$base/verify_ng.out" 2>"$base/verify_ng.err"
  rc_verify_ng=$?
  check "検証-不一致: 終了コード1" "$([ "$rc_verify_ng" -eq 1 ] && echo 0 || echo 1)"
  mv "${tampered}.bak" "$tampered"

  # --- 検証: --verifyは状態のファイルを書き換えない（第1回改善指示書1-38） ---
  # 更新時刻を大きく過去へ戻してから実行し、書き込みが起きれば時刻が今に
  # 変わることで検知できるようにする（同一秒内の実行では変化が見えないため）。
  local status_file_r1="$r1/logs/units-status.json"
  local status_before_verify
  status_before_verify="$(cat "$status_file_r1" 2>/dev/null)"
  touch -t 202001010000 "$status_file_r1"
  local status_mtime_before_verify
  status_mtime_before_verify="$(stat -f %m "$status_file_r1" 2>/dev/null)"
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d1" --run "$r1" --kind screen --out "$r1/code-readings" --verify > "$base/verify_status.out" 2>"$base/verify_status.err"
  local status_after_verify status_mtime_after_verify
  status_after_verify="$(cat "$status_file_r1" 2>/dev/null)"
  status_mtime_after_verify="$(stat -f %m "$status_file_r1" 2>/dev/null)"
  check "no-units-status-検証: --verifyは状態のファイルの中身を書き換えない" "$([ "$status_before_verify" = "$status_after_verify" ] && echo 0 || echo 1)"
  check "no-units-status-検証: --verifyは状態のファイルの更新時刻を書き換えない" "$([ "$status_mtime_before_verify" = "$status_mtime_after_verify" ] && echo 0 || echo 1)"

  # --- --no-units-status: 既存の状態のファイルは中身も更新時刻も変わらない ---
  local status_before_flag
  status_before_flag="$(cat "$status_file_r1" 2>/dev/null)"
  touch -t 202001010000 "$status_file_r1"
  local status_mtime_before_flag
  status_mtime_before_flag="$(stat -f %m "$status_file_r1" 2>/dev/null)"
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d1" --run "$r1" --kind screen --out "$r1/code-readings" --no-units-status > "$base/no_status_existing.out" 2>"$base/no_status_existing.err"
  local rc_no_status_existing=$?
  local status_after_flag status_mtime_after_flag
  status_after_flag="$(cat "$status_file_r1" 2>/dev/null)"
  status_mtime_after_flag="$(stat -f %m "$status_file_r1" 2>/dev/null)"
  check "no-units-status-既存有り: 終了コード0" "$([ "$rc_no_status_existing" -eq 0 ] && echo 0 || echo 1)"
  check "no-units-status-既存有り: 状態のファイルの中身が変わらない" "$([ "$status_before_flag" = "$status_after_flag" ] && echo 0 || echo 1)"
  check "no-units-status-既存有り: 状態のファイルの更新時刻が変わらない" "$([ "$status_mtime_before_flag" = "$status_mtime_after_flag" ] && echo 0 || echo 1)"

  # --- --no-units-status: 状態のファイルが無い状態では作られない・終了コード0 ---
  local d9="$base/case9" r9="$base/run9"
  make_fixture "$d9"
  make_run "$r9"
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d9" --run "$r9" --kind screen --out "$r9/code-readings" --no-units-status > "$base/no_status_absent.out" 2>"$base/no_status_absent.err"
  local rc_no_status_absent=$?
  check "no-units-status-無い状態: 終了コード0" "$([ "$rc_no_status_absent" -eq 0 ] && echo 0 || echo 1)"
  check "no-units-status-無い状態: 状態のファイルが作られない" "$([ ! -f "$r9/logs/units-status.json" ] && echo 0 || echo 1)"

  # --- 指定なしはこれまでどおり状態のファイルへ書き込む ---
  local d10="$base/case10" r10="$base/run10"
  make_fixture "$d10"
  make_run "$r10"
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d10" --run "$r10" --kind screen --out "$r10/code-readings" > "$base/no_status_default.out" 2>"$base/no_status_default.err"
  check "指定なし: 状態のファイルへ書き込む（これまでどおり）" "$([ -f "$r10/logs/units-status.json" ] && echo 0 || echo 1)"

  # --- 使い方誤り ---
  local d3="$base/case3" r3="$base/run3"
  make_fixture "$d3"
  make_run "$r3"

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d3" --kind screen > /dev/null 2>"$base/case3a.err"
  check "使い方誤り-run無し: 終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d3" --run "$r3" > /dev/null 2>"$base/case3b.err"
  check "使い方誤り-kind無し: 終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d3" --run "$r3" --kind unknown > /dev/null 2>"$base/case3c.err"
  check "使い方誤り-種別不正: 終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d3" --run "$r3" --kind screen --map "$d3/docs/design/common/存在しない.md" > /dev/null 2>"$base/case3d.err"
  check "使い方誤り-調査と検出条件の定義書不在: 終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d3" --run "$r3" --kind api > /dev/null 2>"$base/case3e.err"
  check "使い方誤り-規則不在(api用の表が無い): 終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  local d3f="$base/case3f" r3f="$base/run3f"
  make_fixture "$d3f"
  make_run "$r3f"
  cat >> "$d3f/docs/design/common/調査と検出条件の定義書.md" <<'FIXEOF2'

### 4.2 接続窓口

| 目印 | 対象外 |
|---|---|
FIXEOF2
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d3f" --run "$r3f" --kind api > "$base/case3f.out" 2>"$base/case3f.err"
  rc3f=$?
  check "対象外-種別は飛ばす: 終了コード0" "$([ "$rc3f" -eq 0 ] && echo 0 || echo 1)"
  check "対象外-種別は飛ばす: 対象外の表示が出る" "$(grep -q "対象外" "$base/case3f.out" && echo 0 || echo 1)"

  # --- 文字コード-EUC-JP ---
  local d4="$base/case4" r4="$base/run4"
  rm -rf "$d4" "$r4"
  mkdir -p "$d4/src/pages" "$d4/docs/design/common" "$d4/docs/design/lists"
  make_run "$r4"

  printf 'export default function OrderJP() {\n  displayLabel: 受注一覧\n  return null;\n}\n' \
    | iconv -f UTF-8 -t EUC-JP > "$d4/src/pages/OrderJP.tsx"

  cat > "$d4/docs/design/common/調査と検出条件の定義書.md" <<'FIXEOF4'
| 文字コード | EUC-JP |

# 調査と検出条件の定義書

## 4. 単位の見つけ方

### 4.1 画面

| 読み取り結果の項目 | どの構文・記述から取るか |
|---|---|
| 表示項目 | 正規表現: displayLabel: (受注一覧) ／ 捕捉: 1 ／ 範囲: 場所 |

## 5. 動的な定義
FIXEOF4

  cat > "$d4/docs/design/lists/screen.json" <<'FIXEOF4'
[
  {"種別":"screen","識別子":"src/pages/OrderJP.tsx","名前":"OrderJP","場所":"src/pages/OrderJP.tsx","根拠":"src/pages/OrderJP.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF4

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d4" --run "$r4" --kind screen --out "$r4/code-readings" > "$base/case4.out" 2>"$base/case4.err"
  local rc4=$?
  check "文字コード-EUC-JP: 終了コード0" "$([ "$rc4" -eq 0 ] && echo 0 || echo 1)"

  local jp_values
  jp_values="$(jq -c '.["読み取り結果"]["表示項目"]["値"]' "$r4/code-readings/screen/src_pages_OrderJP.tsx.json" 2>/dev/null)"
  check "文字コード-EUC-JP: EUC-JPを変換して受注一覧を捕捉" "$([ "$jp_values" = '["受注一覧"]' ] && echo 0 || echo 1)"

  # --- 単位の区間: 同一ファイルに2単位があっても値が混ざらない
  #     （範囲の前方一致「場所（画面ファイル）」も同時に確かめる） ---
  local d5="$base/case5" r5="$base/run5"
  rm -rf "$d5" "$r5"
  mkdir -p "$d5/src/pages" "$d5/docs/design/common" "$d5/docs/design/lists"
  make_run "$r5"

  cat > "$d5/src/pages/Combo.tsx" <<'FIXEOF5'
<input name="fieldA" />
sep
sep
<input name="fieldB" />
end
FIXEOF5

  cat > "$d5/docs/design/common/調査と検出条件の定義書.md" <<'FIXEOF5'
# 調査と検出条件の定義書

## 4. 単位の見つけ方

### 4.1 画面

| 読み取り結果の項目 | どの構文・記述から取るか |
|---|---|
| 入力項目 | 正規表現: <input[[:space:]]+name="([a-zA-Z0-9_]+)" ／ 捕捉: 1 ／ 範囲: 場所（画面ファイル） |

## 5. 動的な定義
FIXEOF5

  cat > "$d5/docs/design/lists/screen.json" <<'FIXEOF5'
[
  {"種別":"screen","識別子":"combo-1","名前":"Combo1","場所":"src/pages/Combo.tsx","根拠":"src/pages/Combo.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]},
  {"種別":"screen","識別子":"combo-2","名前":"Combo2","場所":"src/pages/Combo.tsx","根拠":"src/pages/Combo.tsx:4","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF5

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d5" --run "$r5" --kind screen --out "$r5/code-readings" > "$base/case5.out" 2>"$base/case5.err"
  local rc5=$?
  check "単位の区間: 終了コード0" "$([ "$rc5" -eq 0 ] && echo 0 || echo 1)"

  local combo1_json="$r5/code-readings/screen/combo-1.json" combo2_json="$r5/code-readings/screen/combo-2.json"
  local combo1_values combo2_values
  combo1_values="$(jq -c '.["読み取り結果"]["入力項目"]["値"]' "$combo1_json" 2>/dev/null)"
  combo2_values="$(jq -c '.["読み取り結果"]["入力項目"]["値"]' "$combo2_json" 2>/dev/null)"
  check "単位の区間: combo-1はfieldAだけ（fieldBと混ざらない）" "$([ "$combo1_values" = '["fieldA"]' ] && echo 0 || echo 1)"
  check "単位の区間: combo-2はfieldBだけ（fieldAと混ざらない）" "$([ "$combo2_values" = '["fieldB"]' ] && echo 0 || echo 1)"

  # --- 属するファイルはglobとして展開する。0件は警告のみで不合格にしない ---
  local d6="$base/case6" r6="$base/run6"
  rm -rf "$d6" "$r6"
  mkdir -p "$d6/src/pages" "$d6/src/api" "$d6/docs/design/common" "$d6/docs/design/lists"
  make_run "$r6"

  cat > "$d6/src/pages/List.tsx" <<'FIXEOF6'
export default function List() {
  return null;
}
FIXEOF6
  cat > "$d6/src/api/orders.ts" <<'FIXEOF6'
export const path = "/orders";
FIXEOF6
  cat > "$d6/src/api/users.ts" <<'FIXEOF6'
export const path = "/users";
FIXEOF6

  cat > "$d6/docs/design/common/調査と検出条件の定義書.md" <<'FIXEOF6'
# 調査と検出条件の定義書

## 4. 単位の見つけ方

### 4.1 画面

| 読み取り結果の項目 | どの構文・記述から取るか |
|---|---|
| 呼ぶ接続窓口 | 正規表現: path = "([a-zA-Z0-9_/]+)" ／ 捕捉: 1 ／ 範囲: 属するファイル |

## 5. 動的な定義
FIXEOF6

  cat > "$d6/docs/design/lists/screen.json" <<'FIXEOF6'
[
  {"種別":"screen","識別子":"src/pages/List.tsx","名前":"List","場所":"src/pages/List.tsx","根拠":"src/pages/List.tsx:1","単位の定義":"","属するファイル":["src/api/*.ts","src/api/none-*.ts"],"分類軸":[]}
]
FIXEOF6

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d6" --run "$r6" --kind screen --out "$r6/code-readings" > "$base/case6.out" 2>"$base/case6.err"
  local rc6=$?
  check "属するファイルglob: 終了コード0（0件一致は警告のみ）" "$([ "$rc6" -eq 0 ] && echo 0 || echo 1)"

  local list_json="$r6/code-readings/screen/src_pages_List.tsx.json"
  local list_values
  list_values="$(jq -c '.["読み取り結果"]["呼ぶ接続窓口"]["値"] | sort' "$list_json" 2>/dev/null)"
  check "属するファイルglob: 複数ファイルへの展開結果を両方捕捉" "$([ "$list_values" = '["/orders","/users"]' ] && echo 0 || echo 1)"

  case "$(cat "$base/case6.err")" in
    *"属するファイル-一致なし"*) check "属するファイルglob: 0件一致は警告メッセージを出す" 0 ;;
    *) check "属するファイルglob: 0件一致は警告メッセージを出す" 1 ;;
  esac

  # --- 捕捉: 一致全体と同じ捕捉・空文字列の捕捉を正しく値として採る ---
  local d7="$base/case7" r7="$base/run7"
  rm -rf "$d7" "$r7"
  mkdir -p "$d7/src/pages" "$d7/docs/design/common" "$d7/docs/design/lists"
  make_run "$r7"

  cat > "$d7/src/pages/Order.tsx" <<'FIXEOF7'
route path=""
route path="/orders"
standalone
onlyempty=""
FIXEOF7

  cat > "$d7/docs/design/common/調査と検出条件の定義書.md" <<'FIXEOF7'
# 調査と検出条件の定義書

## 4. 単位の見つけ方

### 4.1 画面

| 読み取り結果の項目 | どの構文・記述から取るか |
|---|---|
| 経路 | 正規表現: route path="([^"]*)" ／ 捕捉: 1 ／ 範囲: 場所 |
| 名前一致 | 正規表現: (standalone) ／ 捕捉: 1 ／ 範囲: 場所 |
| 空値項目 | 正規表現: onlyempty="([^"]*)" ／ 捕捉: 1 ／ 範囲: 場所 |

## 5. 動的な定義
FIXEOF7

  cat > "$d7/docs/design/lists/screen.json" <<'FIXEOF7'
[
  {"種別":"screen","識別子":"src/pages/Order.tsx","名前":"Order","場所":"src/pages/Order.tsx","根拠":"src/pages/Order.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF7

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d7" --run "$r7" --kind screen --out "$r7/code-readings" > "$base/case7.out" 2>"$base/case7.err"
  local rc7=$?
  check "捕捉の取りこぼし: 終了コード0" "$([ "$rc7" -eq 0 ] && echo 0 || echo 1)"

  local order_json="$r7/code-readings/screen/src_pages_Order.tsx.json"
  local route_values name_values empty_values order_mi
  route_values="$(jq -c '.["読み取り結果"]["経路"]["値"] | sort' "$order_json" 2>/dev/null)"
  name_values="$(jq -c '.["読み取り結果"]["名前一致"]["値"]' "$order_json" 2>/dev/null)"
  empty_values="$(jq -c '.["読み取り結果"]["空値項目"]["値"]' "$order_json" 2>/dev/null)"
  order_mi="$(jq -c '.["未"]' "$order_json" 2>/dev/null)"

  check "捕捉: 空文字列の捕捉を値として含める" "$([ "$route_values" = '["","/orders"]' ] && echo 0 || echo 1)"
  check "捕捉: 一致全体と同じ捕捉でも値を採る（standaloneが空にならない）" "$([ "$name_values" = '["standalone"]' ] && echo 0 || echo 1)"
  check "捕捉: 常に空文字列しか捕捉しない項目も値[\"\"]になる" "$([ "$empty_values" = '[""]' ] && echo 0 || echo 1)"
  case "$order_mi" in
    *"空値項目"*) check "捕捉: 空文字列の値がある項目は未に載らない" 1 ;;
    *) check "捕捉: 空文字列の値がある項目は未に載らない" 0 ;;
  esac

  # --- 規則-解釈不能: 取り出しの規則の2列目が規定のどちらの形でもない項目 ---
  local d8="$base/case8" r8="$base/run8"
  rm -rf "$d8" "$r8"
  mkdir -p "$d8/src/pages" "$d8/docs/design/common" "$d8/docs/design/lists"
  make_run "$r8"

  cat > "$d8/src/pages/Broken.tsx" <<'FIXEOF8'
<input name="orderId" />
FIXEOF8

  cat > "$d8/docs/design/common/調査と検出条件の定義書.md" <<'FIXEOF8'
# 調査と検出条件の定義書

## 4. 単位の見つけ方

### 4.1 画面

| 読み取り結果の項目 | どの構文・記述から取るか |
|---|---|
| 入力項目 | 正規表現: <input[[:space:]]+name="([a-zA-Z0-9_]+)" ／ 捕捉: 1 ／ 範囲: 場所 |
| 壊れた項目 | ここには地の文が書かれていて規定の形ではない |

## 5. 動的な定義
FIXEOF8

  cat > "$d8/docs/design/lists/screen.json" <<'FIXEOF8'
[
  {"種別":"screen","識別子":"src/pages/Broken.tsx","名前":"Broken","場所":"src/pages/Broken.tsx","根拠":"src/pages/Broken.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF8

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d8" --run "$r8" --kind screen --out "$r8/code-readings" > "$base/case8.out" 2>"$base/case8.err"
  local rc8=$?
  check "規則-解釈不能: 終了コードが0以外" "$([ "$rc8" -ne 0 ] && echo 0 || echo 1)"

  local agg8_json="$r8/code-readings/screen/集計.json"
  local agg8_rule_free
  agg8_rule_free="$(jq -c '.["規則の無い項目"]' "$agg8_json" 2>/dev/null)"
  case "$agg8_rule_free" in
    *壊れた項目*) check "規則-解釈不能: 集計の規則の無い項目に列挙される" 0 ;;
    *) check "規則-解釈不能: 集計の規則の無い項目に列挙される" 1 ;;
  esac

  case "$(cat "$base/case8.out")" in
    *"規則-解釈不能"*) check "規則-解釈不能: 標準出力に警告が出る" 0 ;;
    *) check "規則-解釈不能: 標準出力に警告が出る" 1 ;;
  esac

  local broken_json="$r8/code-readings/screen/src_pages_Broken.tsx.json"
  local broken_input_values
  broken_input_values="$(jq -c '.["読み取り結果"]["入力項目"]["値"]' "$broken_json" 2>/dev/null)"
  check "規則-解釈不能: 規定の形の項目は従来どおり値が埋まる" "$([ "$broken_input_values" = '["orderId"]' ] && echo 0 || echo 1)"

  # --- 規則-解釈不能: --verify を付けても終了コードで伝わる ---
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d8" --run "$r8" --kind screen --out "$r8/code-readings" --verify > "$base/case8v.out" 2>"$base/case8v.err"
  local rc8v=$?
  check "規則-解釈不能: --verify でも終了コードが0以外" "$([ "$rc8v" -ne 0 ] && echo 0 || echo 1)"
  case "$(cat "$base/case8v.out")" in
    *"検証: 一致"*) check "規則-解釈不能: --verify の比較自体は一致する" 0 ;;
    *) check "規則-解釈不能: --verify の比較自体は一致する" 1 ;;
  esac
  case "$(cat "$base/case8v.err")" in
    *"検証-取り出し不合格"*) check "規則-解釈不能: --verify で取り出し不合格の理由を標準エラーへ出す" 0 ;;
    *) check "規則-解釈不能: --verify で取り出し不合格の理由を標準エラーへ出す" 1 ;;
  esac

  # --- 範囲「単位の定義」: 一覧から除外した定義（廃止されたもの）が対象
  #     単位と次の単位の間に残っていても、単位の定義は括弧の対応で終端を
  #     決めるため取り込まない。単位（従来の終端）は対比として取り込む
  #     ことを確かめる。括弧付きの値「単位の定義（補足）」も単位の定義へ
  #     正規化されることを同じ対象で確かめる（第1回改善指示書1-28）---
  local d9="$base/case9" r9="$base/run9"
  rm -rf "$d9" "$r9"
  mkdir -p "$d9/src/pages" "$d9/docs/design/common" "$d9/docs/design/lists"
  make_run "$r9"

  cat > "$d9/src/pages/Tables.tsx" <<'FIXEOF9'
CREATE TABLE orders (
  id INT,
  amount INT
)
CREATE TABLE legacy_orders (
  notes TEXT
)
CREATE TABLE users (
  id INT,
  name TEXT
)
FIXEOF9

  cat > "$d9/docs/design/common/調査と検出条件の定義書.md" <<'FIXEOF9'
# 調査と検出条件の定義書

## 4. 単位の見つけ方

### 4.1 画面

| 読み取り結果の項目 | どの構文・記述から取るか |
|---|---|
| 列-単位の定義 | 正規表現: ([a-z_]+) (INT\|TEXT) ／ 捕捉: 1 ／ 範囲: 単位の定義 |
| 列-単位 | 正規表現: ([a-z_]+) (INT\|TEXT) ／ 捕捉: 1 ／ 範囲: 単位 |
| 列-単位の定義注釈 | 正規表現: ([a-z_]+) (INT\|TEXT) ／ 捕捉: 1 ／ 範囲: 単位の定義（テーブル定義） |

## 5. 動的な定義
FIXEOF9

  cat > "$d9/docs/design/lists/screen.json" <<'FIXEOF9'
[
  {"種別":"screen","識別子":"orders","名前":"orders","場所":"src/pages/Tables.tsx","根拠":"src/pages/Tables.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]},
  {"種別":"screen","識別子":"users","名前":"users","場所":"src/pages/Tables.tsx","根拠":"src/pages/Tables.tsx:8","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF9

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d9" --run "$r9" --kind screen --out "$r9/code-readings" > "$base/case9.out" 2>"$base/case9.err"
  local rc9=$?
  local orders9_json="$r9/code-readings/screen/orders.json"
  local v_def v_unit v_def_note
  v_def="$(jq -c '.["読み取り結果"]["列-単位の定義"]["値"]' "$orders9_json" 2>/dev/null)"
  v_unit="$(jq -c '.["読み取り結果"]["列-単位"]["値"]' "$orders9_json" 2>/dev/null)"
  v_def_note="$(jq -c '.["読み取り結果"]["列-単位の定義注釈"]["値"]' "$orders9_json" 2>/dev/null)"
  check "単位の定義: 除外された定義を取り込まない（列がid,amountだけ）" "$([ "$rc9" -eq 0 ] && [ "$v_def" = '["id","amount"]' ] && echo 0 || echo 1)"
  case "$v_unit" in
    *notes*) check "単位: 除外された定義を取り込む（対比。notesが混入する）" 0 ;;
    *) check "単位: 除外された定義を取り込む（対比。notesが混入する）" 1 ;;
  esac
  check "単位の定義: 括弧付きの値「単位の定義（補足）」も単位の定義に正規化される" "$([ "$v_def_note" = '["id","amount"]' ] && echo 0 || echo 1)"

  # --- 範囲「単位の定義」: 閉じ括弧が見つからない壊れた定義は、従来の
  #     終端（一覧の次の単位の直前の行）に落ちる（第1回改善指示書1-28）---
  local d10="$base/case10" r10="$base/run10"
  rm -rf "$d10" "$r10"
  mkdir -p "$d10/src/pages" "$d10/docs/design/common" "$d10/docs/design/lists"
  make_run "$r10"

  cat > "$d10/src/pages/Broken.tsx" <<'FIXEOF10'
CREATE TABLE broken (
  id INT
CREATE TABLE next_one (
  id INT,
  amount INT
FIXEOF10

  cat > "$d10/docs/design/common/調査と検出条件の定義書.md" <<'FIXEOF10'
# 調査と検出条件の定義書

## 4. 単位の見つけ方

### 4.1 画面

| 読み取り結果の項目 | どの構文・記述から取るか |
|---|---|
| 列-単位の定義 | 正規表現: ([a-z_]+) (INT\|TEXT) ／ 捕捉: 1 ／ 範囲: 単位の定義 |

## 5. 動的な定義
FIXEOF10

  cat > "$d10/docs/design/lists/screen.json" <<'FIXEOF10'
[
  {"種別":"screen","識別子":"broken","名前":"broken","場所":"src/pages/Broken.tsx","根拠":"src/pages/Broken.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]},
  {"種別":"screen","識別子":"next-one","名前":"next-one","場所":"src/pages/Broken.tsx","根拠":"src/pages/Broken.tsx:3","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF10

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d10" --run "$r10" --kind screen --out "$r10/code-readings" > "$base/case10.out" 2>"$base/case10.err"
  local rc10=$?
  local broken10_json="$r10/code-readings/screen/broken.json"
  local v_broken
  v_broken="$(jq -c '.["読み取り結果"]["列-単位の定義"]["値"]' "$broken10_json" 2>/dev/null)"
  check "単位の定義: 閉じ括弧が無い壊れた定義は従来の終端に落ちる" "$([ "$rc10" -eq 0 ] && [ "$v_broken" = '["id"]' ] && echo 0 || echo 1)"

  # --- 範囲「単位の定義」: 字下げされた閉じ括弧の行（字下げを除く最初の
  #     文字が ")" である行）も終端として認識する（第1回改善指示書1-28）---
  local d11="$base/case11" r11="$base/run11"
  rm -rf "$d11" "$r11"
  mkdir -p "$d11/src/pages" "$d11/docs/design/common" "$d11/docs/design/lists"
  make_run "$r11"

  cat > "$d11/src/pages/Indented.tsx" <<'FIXEOF11'
CREATE TABLE indented (
  id INT
  )
  notes TEXT
CREATE TABLE after_indented (
  other INT
)
FIXEOF11

  cat > "$d11/docs/design/common/調査と検出条件の定義書.md" <<'FIXEOF11'
# 調査と検出条件の定義書

## 4. 単位の見つけ方

### 4.1 画面

| 読み取り結果の項目 | どの構文・記述から取るか |
|---|---|
| 列-単位の定義 | 正規表現: ([a-z_]+) (INT\|TEXT) ／ 捕捉: 1 ／ 範囲: 単位の定義 |

## 5. 動的な定義
FIXEOF11

  cat > "$d11/docs/design/lists/screen.json" <<'FIXEOF11'
[
  {"種別":"screen","識別子":"indented","名前":"indented","場所":"src/pages/Indented.tsx","根拠":"src/pages/Indented.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]},
  {"種別":"screen","識別子":"after-indented","名前":"after-indented","場所":"src/pages/Indented.tsx","根拠":"src/pages/Indented.tsx:5","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF11

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d11" --run "$r11" --kind screen --out "$r11/code-readings" > "$base/case11.out" 2>"$base/case11.err"
  local rc11=$?
  local indented11_json="$r11/code-readings/screen/indented.json"
  local v_indented
  v_indented="$(jq -c '.["読み取り結果"]["列-単位の定義"]["値"]' "$indented11_json" 2>/dev/null)"
  check "単位の定義: 字下げされた閉じ括弧の行を終端にする" "$([ "$rc11" -eq 0 ] && [ "$v_indented" = '["id"]' ] && echo 0 || echo 1)"

  # --- 範囲「単位の定義」: 閉じ無しの定義の直後に閉じ括弧を持つ次の単位
  #     があっても、探索を次の単位の直前までに限るため、次の単位の閉じ
  #     括弧を誤って終端に採らない。単位（対比）も同じ値になる
  #     （第1回改善指示書1-28 反証所見1）---
  local d12="$base/case12" r12="$base/run12"
  rm -rf "$d12" "$r12"
  mkdir -p "$d12/src/pages" "$d12/docs/design/common" "$d12/docs/design/lists"
  make_run "$r12"

  cat > "$d12/src/pages/Broken2.tsx" <<'FIXEOF12'
CREATE TABLE broken2 (
  id INT
CREATE TABLE next2 (
  amount INT
)
FIXEOF12

  cat > "$d12/docs/design/common/調査と検出条件の定義書.md" <<'FIXEOF12'
# 調査と検出条件の定義書

## 4. 単位の見つけ方

### 4.1 画面

| 読み取り結果の項目 | どの構文・記述から取るか |
|---|---|
| 列-単位の定義 | 正規表現: ([a-z_]+) (INT\|TEXT) ／ 捕捉: 1 ／ 範囲: 単位の定義 |
| 列-単位 | 正規表現: ([a-z_]+) (INT\|TEXT) ／ 捕捉: 1 ／ 範囲: 単位 |

## 5. 動的な定義
FIXEOF12

  cat > "$d12/docs/design/lists/screen.json" <<'FIXEOF12'
[
  {"種別":"screen","識別子":"broken2","名前":"broken2","場所":"src/pages/Broken2.tsx","根拠":"src/pages/Broken2.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]},
  {"種別":"screen","識別子":"next2","名前":"next2","場所":"src/pages/Broken2.tsx","根拠":"src/pages/Broken2.tsx:3","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF12

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d12" --run "$r12" --kind screen --out "$r12/code-readings" > "$base/case12.out" 2>"$base/case12.err"
  local rc12=$?
  local broken2_json="$r12/code-readings/screen/broken2.json"
  local v_def12 v_unit12
  v_def12="$(jq -c '.["読み取り結果"]["列-単位の定義"]["値"]' "$broken2_json" 2>/dev/null)"
  v_unit12="$(jq -c '.["読み取り結果"]["列-単位"]["値"]' "$broken2_json" 2>/dev/null)"
  check "単位の定義: 次の単位の閉じ括弧を誤って終端に採らない（単位も対比で同じ値）" "$([ "$rc12" -eq 0 ] && [ "$v_def12" = '["id"]' ] && [ "$v_unit12" = '["id"]' ] && echo 0 || echo 1)"

  # --- 範囲「単位の定義」: ネストした括弧の閉じ行（"),"）では終わらず、
  #     定義の最後（対応が0に戻る行）まで取る（第1回改善指示書1-28
  #     反証所見3）---
  local d13="$base/case13" r13="$base/run13"
  rm -rf "$d13" "$r13"
  mkdir -p "$d13/src/pages" "$d13/docs/design/common" "$d13/docs/design/lists"
  make_run "$r13"

  cat > "$d13/src/pages/Nested.tsx" <<'FIXEOF13'
CREATE TABLE nested (
  id INT,
  meta JSONB DEFAULT (
    '{}'
  ),
  amount INT
)
CREATE TABLE after_nested (
  other INT
)
FIXEOF13

  cat > "$d13/docs/design/common/調査と検出条件の定義書.md" <<'FIXEOF13'
# 調査と検出条件の定義書

## 4. 単位の見つけ方

### 4.1 画面

| 読み取り結果の項目 | どの構文・記述から取るか |
|---|---|
| 列-単位の定義 | 正規表現: ([a-z_]+) (INT\|TEXT) ／ 捕捉: 1 ／ 範囲: 単位の定義 |

## 5. 動的な定義
FIXEOF13

  cat > "$d13/docs/design/lists/screen.json" <<'FIXEOF13'
[
  {"種別":"screen","識別子":"nested","名前":"nested","場所":"src/pages/Nested.tsx","根拠":"src/pages/Nested.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]},
  {"種別":"screen","識別子":"after-nested","名前":"after-nested","場所":"src/pages/Nested.tsx","根拠":"src/pages/Nested.tsx:8","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF13

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d13" --run "$r13" --kind screen --out "$r13/code-readings" > "$base/case13.out" 2>"$base/case13.err"
  local rc13=$?
  local nested13_json="$r13/code-readings/screen/nested.json"
  local v_nested13
  v_nested13="$(jq -c '.["読み取り結果"]["列-単位の定義"]["値"]' "$nested13_json" 2>/dev/null)"
  check "単位の定義: ネストした括弧の閉じ行では終わらず定義の最後まで取る" "$([ "$rc13" -eq 0 ] && [ "$v_nested13" = '["id","amount"]' ] && echo 0 || echo 1)"

  # --- 範囲「単位の定義」: 開始行の中で開いて閉じる1行定義は、その行だけ
  #     を終端にする（第1回改善指示書1-28 反証所見2）---
  local d14="$base/case14" r14="$base/run14"
  rm -rf "$d14" "$r14"
  mkdir -p "$d14/src/pages" "$d14/docs/design/common" "$d14/docs/design/lists"
  make_run "$r14"

  cat > "$d14/src/pages/Oneline.tsx" <<'FIXEOF14'
CREATE TABLE oneline (id INT);
CREATE TABLE afterone (
  other INT
)
FIXEOF14

  cat > "$d14/docs/design/common/調査と検出条件の定義書.md" <<'FIXEOF14'
# 調査と検出条件の定義書

## 4. 単位の見つけ方

### 4.1 画面

| 読み取り結果の項目 | どの構文・記述から取るか |
|---|---|
| 列-単位の定義 | 正規表現: ([a-z_]+) (INT\|TEXT) ／ 捕捉: 1 ／ 範囲: 単位の定義 |

## 5. 動的な定義
FIXEOF14

  cat > "$d14/docs/design/lists/screen.json" <<'FIXEOF14'
[
  {"種別":"screen","識別子":"oneline","名前":"oneline","場所":"src/pages/Oneline.tsx","根拠":"src/pages/Oneline.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]},
  {"種別":"screen","識別子":"afterone","名前":"afterone","場所":"src/pages/Oneline.tsx","根拠":"src/pages/Oneline.tsx:2","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF14

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d14" --run "$r14" --kind screen --out "$r14/code-readings" > "$base/case14.out" 2>"$base/case14.err"
  local rc14=$?
  local oneline14_json="$r14/code-readings/screen/oneline.json"
  local v_oneline14
  v_oneline14="$(jq -c '.["読み取り結果"]["列-単位の定義"]["値"]' "$oneline14_json" 2>/dev/null)"
  check "単位の定義: 1行定義はその行だけを終端にする" "$([ "$rc14" -eq 0 ] && [ "$v_oneline14" = '["id"]' ] && echo 0 || echo 1)"

  # --- 範囲「単位の定義」: 定義を開く文の行に開き括弧が無く、次の行以降で
  #     開いても、そこから残高を数え始める（第2版反証所見1）---
  local d15="$base/case15" r15="$base/run15"
  rm -rf "$d15" "$r15"
  mkdir -p "$d15/src/pages" "$d15/docs/design/common" "$d15/docs/design/lists"
  make_run "$r15"

  cat > "$d15/src/pages/NextLine.tsx" <<'FIXEOF15'
CREATE TABLE orders
(
  id INT,
  amount INT
)
CREATE TABLE legacy_orders (
  notes TEXT
)
CREATE TABLE users (
  id INT,
  name TEXT
)
FIXEOF15

  cat > "$d15/docs/design/common/調査と検出条件の定義書.md" <<'FIXEOF15'
# 調査と検出条件の定義書

## 4. 単位の見つけ方

### 4.1 画面

| 読み取り結果の項目 | どの構文・記述から取るか |
|---|---|
| 列-単位の定義 | 正規表現: ([a-z_]+) (INT\|TEXT) ／ 捕捉: 1 ／ 範囲: 単位の定義 |

## 5. 動的な定義
FIXEOF15

  cat > "$d15/docs/design/lists/screen.json" <<'FIXEOF15'
[
  {"種別":"screen","識別子":"orders","名前":"orders","場所":"src/pages/NextLine.tsx","根拠":"src/pages/NextLine.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]},
  {"種別":"screen","識別子":"users","名前":"users","場所":"src/pages/NextLine.tsx","根拠":"src/pages/NextLine.tsx:9","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF15

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d15" --run "$r15" --kind screen --out "$r15/code-readings" > "$base/case15.out" 2>"$base/case15.err"
  local rc15=$?
  local orders15_json="$r15/code-readings/screen/orders.json"
  local v_def15
  v_def15="$(jq -c '.["読み取り結果"]["列-単位の定義"]["値"]' "$orders15_json" 2>/dev/null)"
  check "単位の定義: 開始行に開き括弧が無く次行以降で開いても除外定義を取り込まない" "$([ "$rc15" -eq 0 ] && [ "$v_def15" = '["id","amount"]' ] && echo 0 || echo 1)"

  # --- 範囲「単位の定義」: 残高が0に戻った直後の次の文字が ";" のとき、
  #     同じ行に次の定義の開きが続いていてもその行で終端にする
  #     （第2版反証所見2）---
  local d16="$base/case16" r16="$base/run16"
  rm -rf "$d16" "$r16"
  mkdir -p "$d16/src/pages" "$d16/docs/design/common" "$d16/docs/design/lists"
  make_run "$r16"

  cat > "$d16/src/pages/SameLine.tsx" <<'FIXEOF16'
CREATE TABLE orders (
  id INT,
  amount INT
); CREATE TABLE zombi (
  ghost TEXT
)
CREATE TABLE users (
  id INT,
  name TEXT
)
FIXEOF16

  cat > "$d16/docs/design/common/調査と検出条件の定義書.md" <<'FIXEOF16'
# 調査と検出条件の定義書

## 4. 単位の見つけ方

### 4.1 画面

| 読み取り結果の項目 | どの構文・記述から取るか |
|---|---|
| 列-単位の定義 | 正規表現: ([a-z_]+) (INT\|TEXT) ／ 捕捉: 1 ／ 範囲: 単位の定義 |

## 5. 動的な定義
FIXEOF16

  cat > "$d16/docs/design/lists/screen.json" <<'FIXEOF16'
[
  {"種別":"screen","識別子":"orders","名前":"orders","場所":"src/pages/SameLine.tsx","根拠":"src/pages/SameLine.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]},
  {"種別":"screen","識別子":"users","名前":"users","場所":"src/pages/SameLine.tsx","根拠":"src/pages/SameLine.tsx:7","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF16

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d16" --run "$r16" --kind screen --out "$r16/code-readings" > "$base/case16.out" 2>"$base/case16.err"
  local rc16=$?
  local orders16_json="$r16/code-readings/screen/orders.json"
  local v_def16
  v_def16="$(jq -c '.["読み取り結果"]["列-単位の定義"]["値"]' "$orders16_json" 2>/dev/null)"
  check "単位の定義: 残高0直後が';'の行を終端にし同じ行の次の定義を取り込まない" "$([ "$rc16" -eq 0 ] && [ "$v_def16" = '["id","amount"]' ] && echo 0 || echo 1)"

  # --- 範囲「単位の定義」: 文字列中の開き括弧を数えて残高が範囲内で0に
  #     戻らない場合、従来の終端まで伸びて隣の内容を取り込む（取り込み
  #     方向。既知の限界の確認）（第2版反証所見4）---
  local d17="$base/case17" r17="$base/run17"
  rm -rf "$d17" "$r17"
  mkdir -p "$d17/src/pages" "$d17/docs/design/common" "$d17/docs/design/lists"
  make_run "$r17"

  cat > "$d17/src/pages/StrParen.tsx" <<'FIXEOF17'
CREATE TABLE strtest (
  id INT,
  note TEXT DEFAULT '('
)
orphan_column TEXT
CREATE TABLE after_str (
  other INT
)
FIXEOF17

  cat > "$d17/docs/design/common/調査と検出条件の定義書.md" <<'FIXEOF17'
# 調査と検出条件の定義書

## 4. 単位の見つけ方

### 4.1 画面

| 読み取り結果の項目 | どの構文・記述から取るか |
|---|---|
| 列-単位の定義 | 正規表現: ([a-z_]+) (INT\|TEXT) ／ 捕捉: 1 ／ 範囲: 単位の定義 |

## 5. 動的な定義
FIXEOF17

  cat > "$d17/docs/design/lists/screen.json" <<'FIXEOF17'
[
  {"種別":"screen","識別子":"strtest","名前":"strtest","場所":"src/pages/StrParen.tsx","根拠":"src/pages/StrParen.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]},
  {"種別":"screen","識別子":"after-str","名前":"after-str","場所":"src/pages/StrParen.tsx","根拠":"src/pages/StrParen.tsx:6","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF17

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d17" --run "$r17" --kind screen --out "$r17/code-readings" > "$base/case17.out" 2>"$base/case17.err"
  local rc17=$?
  local strtest17_json="$r17/code-readings/screen/strtest.json"
  local v_def17
  v_def17="$(jq -c '.["読み取り結果"]["列-単位の定義"]["値"]' "$strtest17_json" 2>/dev/null)"
  check "単位の定義: 文字列中の開き括弧で残高が戻らず従来の終端まで伸びて隣を取り込む（既知の限界）" "$([ "$rc17" -eq 0 ] && [ "$v_def17" = '["id","note","orphan_column"]' ] && echo 0 || echo 1)"

  # --- 範囲「単位の定義」: 関数シグネチャ形（丸括弧の対応が0に戻った直後
  #     が"{"）は数え続け、対応する"}"の行を終端にする（第2版指摘）---
  local d18="$base/case18" r18="$base/run18"
  rm -rf "$d18" "$r18"
  mkdir -p "$d18/src/pages" "$d18/docs/design/common" "$d18/docs/design/lists"
  make_run "$r18"

  cat > "$d18/src/pages/FuncSig.tsx" <<'FIXEOF18'
function Foo(props) {
  return props.id;
}
function Legacy(props) {
  return props.legacy;
}
function Bar(props) {
  return props.name;
}
FIXEOF18

  cat > "$d18/docs/design/common/調査と検出条件の定義書.md" <<'FIXEOF18'
# 調査と検出条件の定義書

## 4. 単位の見つけ方

### 4.1 画面

| 読み取り結果の項目 | どの構文・記述から取るか |
|---|---|
| 戻り値-単位の定義 | 正規表現: return props\.([a-z]+) ／ 捕捉: 1 ／ 範囲: 単位の定義 |

## 5. 動的な定義
FIXEOF18

  cat > "$d18/docs/design/lists/screen.json" <<'FIXEOF18'
[
  {"種別":"screen","識別子":"foo","名前":"foo","場所":"src/pages/FuncSig.tsx","根拠":"src/pages/FuncSig.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]},
  {"種別":"screen","識別子":"bar","名前":"bar","場所":"src/pages/FuncSig.tsx","根拠":"src/pages/FuncSig.tsx:7","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF18

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d18" --run "$r18" --kind screen --out "$r18/code-readings" > "$base/case18.out" 2>"$base/case18.err"
  local rc18=$?
  local foo18_json="$r18/code-readings/screen/foo.json"
  local v_def18
  v_def18="$(jq -c '.["読み取り結果"]["戻り値-単位の定義"]["値"]' "$foo18_json" 2>/dev/null)"
  check "単位の定義: 関数シグネチャ形は対応する'}'の行を終端にし除外定義を取り込まない" "$([ "$rc18" -eq 0 ] && [ "$v_def18" = '["id"]' ] && echo 0 || echo 1)"

  # --- 範囲「単位の定義」: 括弧を閉じても直後が";"でも行末でもない場合
  #     （Pythonのdefの":"）は数え続けるが、行末で残高が0に戻れば開始行
  #     だけを終端にする（既知の限界の確認）（第2版指摘）---
  local d19="$base/case19" r19="$base/run19"
  rm -rf "$d19" "$r19"
  mkdir -p "$d19/src/pages" "$d19/docs/design/common" "$d19/docs/design/lists"
  make_run "$r19"

  cat > "$d19/src/pages/PyDef.tsx" <<'FIXEOF19'
def order_summary(x):
    return x.id
def legacy_summary(x):
    return x.legacy
def user_summary(x):
    return x.name
FIXEOF19

  cat > "$d19/docs/design/common/調査と検出条件の定義書.md" <<'FIXEOF19'
# 調査と検出条件の定義書

## 4. 単位の見つけ方

### 4.1 画面

| 読み取り結果の項目 | どの構文・記述から取るか |
|---|---|
| 戻り値-単位の定義 | 正規表現: return x\.([a-z]+) ／ 捕捉: 1 ／ 範囲: 単位の定義 |

## 5. 動的な定義
FIXEOF19

  cat > "$d19/docs/design/lists/screen.json" <<'FIXEOF19'
[
  {"種別":"screen","識別子":"order-summary","名前":"order-summary","場所":"src/pages/PyDef.tsx","根拠":"src/pages/PyDef.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]},
  {"種別":"screen","識別子":"user-summary","名前":"user-summary","場所":"src/pages/PyDef.tsx","根拠":"src/pages/PyDef.tsx:5","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF19

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d19" --run "$r19" --kind screen --out "$r19/code-readings" > "$base/case19.out" 2>"$base/case19.err"
  local rc19=$?
  local ordersummary19_json="$r19/code-readings/screen/order-summary.json"
  local v_def19
  v_def19="$(jq -c '.["読み取り結果"]["戻り値-単位の定義"]["値"]' "$ordersummary19_json" 2>/dev/null)"
  check "単位の定義: 本体を括弧で囲まない定義（def）は行末で0に戻り開始行だけになる" "$([ "$rc19" -eq 0 ] && [ "$v_def19" = '[]' ] && echo 0 || echo 1)"

  # --- 範囲「単位の定義」: 波括弧を次行に置く様式（Allman）は、丸括弧の
  #     対応が行末で0に戻っても次の空白でない行の先頭が"{"なら終端にせず
  #     数え続け（先読み）、対応する"}"の行を終端にする（第3版反証所見1）---
  local d20="$base/case20" r20="$base/run20"
  rm -rf "$d20" "$r20"
  mkdir -p "$d20/src/pages" "$d20/docs/design/common" "$d20/docs/design/lists"
  make_run "$r20"

  cat > "$d20/src/pages/FuncAllman.tsx" <<'FIXEOF20'
function foo(props)
{
  return props.id;
}
function legacy(props)
{
  return props.legacy;
}
function bar(props)
{
  return props.name;
}
FIXEOF20

  cat > "$d20/docs/design/common/調査と検出条件の定義書.md" <<'FIXEOF20'
# 調査と検出条件の定義書

## 4. 単位の見つけ方

### 4.1 画面

| 読み取り結果の項目 | どの構文・記述から取るか |
|---|---|
| 戻り値-単位の定義 | 正規表現: return props\.([a-z]+) ／ 捕捉: 1 ／ 範囲: 単位の定義 |

## 5. 動的な定義
FIXEOF20

  cat > "$d20/docs/design/lists/screen.json" <<'FIXEOF20'
[
  {"種別":"screen","識別子":"foo","名前":"foo","場所":"src/pages/FuncAllman.tsx","根拠":"src/pages/FuncAllman.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]},
  {"種別":"screen","識別子":"bar","名前":"bar","場所":"src/pages/FuncAllman.tsx","根拠":"src/pages/FuncAllman.tsx:9","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF20

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d20" --run "$r20" --kind screen --out "$r20/code-readings" > "$base/case20.out" 2>"$base/case20.err"
  local rc20=$?
  local foo20_json="$r20/code-readings/screen/foo.json"
  local v_def20
  v_def20="$(jq -c '.["読み取り結果"]["戻り値-単位の定義"]["値"]' "$foo20_json" 2>/dev/null)"
  check "単位の定義: 波括弧が次行の定義は先読みで本体まで取り除外定義を取り込まない" "$([ "$rc20" -eq 0 ] && [ "$v_def20" = '["id"]' ] && echo 0 || echo 1)"

  # --- 範囲「単位の定義」: デコレータ行を定義の開始行にしていると、その
  #     行自体の丸括弧で残高が0に戻り、次の行は定義の文自体（先頭が開き
  #     括弧でない）から始まるため先読みでは救えず、開始行だけが終端に
  #     なる（既知の限界の確認）（第3版反証所見2）---
  local d21="$base/case21" r21="$base/run21"
  rm -rf "$d21" "$r21"
  mkdir -p "$d21/src/pages" "$d21/docs/design/common" "$d21/docs/design/lists"
  make_run "$r21"

  cat > "$d21/src/pages/Decorator.tsx" <<'FIXEOF21'
@Injectable()
export class FooService {
  getId() {
    return this.id;
  }
}
@Injectable()
export class LegacyService {
  getId() {
    return this.legacy;
  }
}
@Injectable()
export class BarService {
  getId() {
    return this.name;
  }
}
FIXEOF21

  cat > "$d21/docs/design/common/調査と検出条件の定義書.md" <<'FIXEOF21'
# 調査と検出条件の定義書

## 4. 単位の見つけ方

### 4.1 画面

| 読み取り結果の項目 | どの構文・記述から取るか |
|---|---|
| 戻り値-単位の定義 | 正規表現: return this\.([a-z]+) ／ 捕捉: 1 ／ 範囲: 単位の定義 |

## 5. 動的な定義
FIXEOF21

  cat > "$d21/docs/design/lists/screen.json" <<'FIXEOF21'
[
  {"種別":"screen","識別子":"foo-service","名前":"foo-service","場所":"src/pages/Decorator.tsx","根拠":"src/pages/Decorator.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]},
  {"種別":"screen","識別子":"bar-service","名前":"bar-service","場所":"src/pages/Decorator.tsx","根拠":"src/pages/Decorator.tsx:13","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF21

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d21" --run "$r21" --kind screen --out "$r21/code-readings" > "$base/case21.out" 2>"$base/case21.err"
  local rc21=$?
  local fooservice21_json="$r21/code-readings/screen/foo-service.json"
  local v_def21
  v_def21="$(jq -c '.["読み取り結果"]["戻り値-単位の定義"]["値"]' "$fooservice21_json" 2>/dev/null)"
  check "単位の定義: デコレータ行から始まる定義は先読みで救えず開始行だけになる" "$([ "$rc21" -eq 0 ] && [ "$v_def21" = '[]' ] && echo 0 || echo 1)"

  # --- 範囲「単位の定義」: 行末で残高が0に戻った直後の次の行が丸括弧
  #     "(" で始まっていても、先読みの継続条件は波括弧"{"だけであり
  #     続けない。閉じ括弧の行（"）"）を終端にし、次の行に丸括弧で
  #     始まる別の文（別のSELECT文など）が続いても取り込まない
  #     （第4版反証所見1）---
  local d22="$base/case22" r22="$base/run22"
  rm -rf "$d22" "$r22"
  mkdir -p "$d22/src/pages" "$d22/docs/design/common" "$d22/docs/design/lists"
  make_run "$r22"

  cat > "$d22/src/pages/OpenParenNext.tsx" <<'FIXEOF22'
CREATE TABLE a (
  id INT,
  amount INT
)
(orphan_column INT);
CREATE TABLE next_one (
  id INT,
  name TEXT
)
FIXEOF22

  cat > "$d22/docs/design/common/調査と検出条件の定義書.md" <<'FIXEOF22'
# 調査と検出条件の定義書

## 4. 単位の見つけ方

### 4.1 画面

| 読み取り結果の項目 | どの構文・記述から取るか |
|---|---|
| 列-単位の定義 | 正規表現: ([a-z_]+) (INT\|TEXT) ／ 捕捉: 1 ／ 範囲: 単位の定義 |

## 5. 動的な定義
FIXEOF22

  cat > "$d22/docs/design/lists/screen.json" <<'FIXEOF22'
[
  {"種別":"screen","識別子":"a","名前":"a","場所":"src/pages/OpenParenNext.tsx","根拠":"src/pages/OpenParenNext.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]},
  {"種別":"screen","識別子":"next-one","名前":"next-one","場所":"src/pages/OpenParenNext.tsx","根拠":"src/pages/OpenParenNext.tsx:6","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF22

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d22" --run "$r22" --kind screen --out "$r22/code-readings" > "$base/case22.out" 2>"$base/case22.err"
  local rc22=$?
  local a22_json="$r22/code-readings/screen/a.json"
  local v_def22
  v_def22="$(jq -c '.["読み取り結果"]["列-単位の定義"]["値"]' "$a22_json" 2>/dev/null)"
  check "単位の定義: 次行が丸括弧で始まる別の文は先読みで続けず閉じ括弧の行を終端にする" "$([ "$rc22" -eq 0 ] && [ "$v_def22" = '["id","amount"]' ] && echo 0 || echo 1)"

  # --- 範囲「単位の定義」: 括弧で囲まない定義（Pythonのdef）の次行が丸
  #     括弧で始まるタプル代入でも、先読みの継続条件は波括弧"{"だけで
  #     あり続けない。開始行だけが終端になる（第4版反証所見1）---
  local d23="$base/case23" r23="$base/run23"
  rm -rf "$d23" "$r23"
  mkdir -p "$d23/src/pages" "$d23/docs/design/common" "$d23/docs/design/lists"
  make_run "$r23"

  cat > "$d23/src/pages/TupleAssign.tsx" <<'FIXEOF23'
def order_summary(x):
    (a, b) = (x.id, x.name)
    return a
def user_summary(x):
    return x.name
FIXEOF23

  cat > "$d23/docs/design/common/調査と検出条件の定義書.md" <<'FIXEOF23'
# 調査と検出条件の定義書

## 4. 単位の見つけ方

### 4.1 画面

| 読み取り結果の項目 | どの構文・記述から取るか |
|---|---|
| 戻り値-単位の定義 | 正規表現: x\.([a-z]+) ／ 捕捉: 1 ／ 範囲: 単位の定義 |

## 5. 動的な定義
FIXEOF23

  cat > "$d23/docs/design/lists/screen.json" <<'FIXEOF23'
[
  {"種別":"screen","識別子":"order-summary","名前":"order-summary","場所":"src/pages/TupleAssign.tsx","根拠":"src/pages/TupleAssign.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]},
  {"種別":"screen","識別子":"user-summary","名前":"user-summary","場所":"src/pages/TupleAssign.tsx","根拠":"src/pages/TupleAssign.tsx:4","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF23

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d23" --run "$r23" --kind screen --out "$r23/code-readings" > "$base/case23.out" 2>"$base/case23.err"
  local rc23=$?
  local ordersummary23_json="$r23/code-readings/screen/order-summary.json"
  local v_def23
  v_def23="$(jq -c '.["読み取り結果"]["戻り値-単位の定義"]["値"]' "$ordersummary23_json" 2>/dev/null)"
  check "単位の定義: defの次行が丸括弧で始まるタプル代入でも続けず開始行だけになる" "$([ "$rc23" -eq 0 ] && [ "$v_def23" = '[]' ] && echo 0 || echo 1)"

  # --- 範囲「単位の定義」: オブジェクトを並べる様式（`},`の次行が`{`）
  #     では、残高を0に戻した閉じ括弧が波括弧`}`のため先読みをせず、
  #     閉じた行で終端にする。次行が波括弧で始まっていても続けず、
  #     除外した隣のオブジェクトを取り込まない（第5版反証所見1）---
  local d24="$base/case24" r24="$base/run24"
  rm -rf "$d24" "$r24"
  mkdir -p "$d24/src/pages" "$d24/docs/design/common" "$d24/docs/design/lists"
  make_run "$r24"

  cat > "$d24/src/pages/RouteList.tsx" <<'FIXEOF24'
const routes = [
  {
    id: "orders",
    label: "orders-real"
  },
  {
    id: "zombi",
    label: "zombi-ghost"
  }
];
function users(props) {
  return props.name;
}
FIXEOF24

  cat > "$d24/docs/design/common/調査と検出条件の定義書.md" <<'FIXEOF24'
# 調査と検出条件の定義書

## 4. 単位の見つけ方

### 4.1 画面

| 読み取り結果の項目 | どの構文・記述から取るか |
|---|---|
| ラベル-単位の定義 | 正規表現: label: "([a-z-]+)" ／ 捕捉: 1 ／ 範囲: 単位の定義 |

## 5. 動的な定義
FIXEOF24

  cat > "$d24/docs/design/lists/screen.json" <<'FIXEOF24'
[
  {"種別":"screen","識別子":"orders","名前":"orders","場所":"src/pages/RouteList.tsx","根拠":"src/pages/RouteList.tsx:2","単位の定義":"","属するファイル":[],"分類軸":[]},
  {"種別":"screen","識別子":"users","名前":"users","場所":"src/pages/RouteList.tsx","根拠":"src/pages/RouteList.tsx:11","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF24

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d24" --run "$r24" --kind screen --out "$r24/code-readings" > "$base/case24.out" 2>"$base/case24.err"
  local rc24=$?
  local orders24_json="$r24/code-readings/screen/orders.json"
  local v_def24
  v_def24="$(jq -c '.["読み取り結果"]["ラベル-単位の定義"]["値"]' "$orders24_json" 2>/dev/null)"
  check "単位の定義: 波括弧で閉じた行の次行が波括弧でも先読みで続けず隣のオブジェクトを取り込まない" "$([ "$rc24" -eq 0 ] && [ "$v_def24" = '["orders-real"]' ] && echo 0 || echo 1)"

  # --- 範囲「単位の定義」: CRLF改行のファイルで、丸括弧の署名と波括弧の
  #     本体の間に`\r`だけの空行があっても、行末の`\r`を除いて空行と
  #     判定するため先読みが続き、対応する`}`の行を終端にする
  #     （第5版反証所見2）---
  local d25="$base/case25" r25="$base/run25"
  rm -rf "$d25" "$r25"
  mkdir -p "$d25/src/pages" "$d25/docs/design/common" "$d25/docs/design/lists"
  make_run "$r25"

  printf 'function foo($x)\r\n\r\n{\r\n  return $x->id;\r\n}\r\nfunction legacy($x)\r\n\r\n{\r\n  return $x->legacy;\r\n}\r\nfunction bar($x)\r\n\r\n{\r\n  return $x->name;\r\n}\r\n' > "$d25/src/pages/CrlfAllman.php"

  cat > "$d25/docs/design/common/調査と検出条件の定義書.md" <<'FIXEOF25'
# 調査と検出条件の定義書

## 4. 単位の見つけ方

### 4.1 画面

| 読み取り結果の項目 | どの構文・記述から取るか |
|---|---|
| 戻り値-単位の定義 | 正規表現: return \$x->([a-z]+); ／ 捕捉: 1 ／ 範囲: 単位の定義 |

## 5. 動的な定義
FIXEOF25

  cat > "$d25/docs/design/lists/screen.json" <<'FIXEOF25'
[
  {"種別":"screen","識別子":"foo","名前":"foo","場所":"src/pages/CrlfAllman.php","根拠":"src/pages/CrlfAllman.php:1","単位の定義":"","属するファイル":[],"分類軸":[]},
  {"種別":"screen","識別子":"bar","名前":"bar","場所":"src/pages/CrlfAllman.php","根拠":"src/pages/CrlfAllman.php:11","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF25

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d25" --run "$r25" --kind screen --out "$r25/code-readings" > "$base/case25.out" 2>"$base/case25.err"
  local rc25=$?
  local foo25_json="$r25/code-readings/screen/foo.json"
  local v_def25
  v_def25="$(jq -c '.["読み取り結果"]["戻り値-単位の定義"]["値"]' "$foo25_json" 2>/dev/null)"
  check "単位の定義: CRLFの空行を挟んでも先読みが続き除外定義を取り込まない" "$([ "$rc25" -eq 0 ] && [ "$v_def25" = '["id"]' ] && echo 0 || echo 1)"

  # --- 範囲「単位の定義」: 呼び出し式が`),`で閉じる行（丸括弧の残高が
  #     0に戻った直後が`,`）は、`,`を終端の合図として扱いその行で終わる。
  #     次行の除外オブジェクトへ先読みで続けない（第6版反証所見1）---
  local d26="$base/case26" r26="$base/run26"
  rm -rf "$d26" "$r26"
  mkdir -p "$d26/src/pages" "$d26/docs/design/common" "$d26/docs/design/lists"
  make_run "$r26"

  cat > "$d26/src/pages/RouteList.tsx" <<'FIXEOF26'
const routes = [
  wrapHandler(ordersHandler, "orders-real"),
  {
    id: "zombi",
    label: "zombi-ghost"
  }
];
function users(props) {
  return props.name;
}
FIXEOF26

  cat > "$d26/docs/design/common/調査と検出条件の定義書.md" <<'FIXEOF26'
# 調査と検出条件の定義書

## 4. 単位の見つけ方

### 4.1 画面

| 読み取り結果の項目 | どの構文・記述から取るか |
|---|---|
| ラベル-単位の定義 | 正規表現: label: "([a-z-]+)" ／ 捕捉: 1 ／ 範囲: 単位の定義 |

## 5. 動的な定義
FIXEOF26

  cat > "$d26/docs/design/lists/screen.json" <<'FIXEOF26'
[
  {"種別":"screen","識別子":"orders","名前":"orders","場所":"src/pages/RouteList.tsx","根拠":"src/pages/RouteList.tsx:2","単位の定義":"","属するファイル":[],"分類軸":[]},
  {"種別":"screen","識別子":"users","名前":"users","場所":"src/pages/RouteList.tsx","根拠":"src/pages/RouteList.tsx:8","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF26

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d26" --run "$r26" --kind screen --out "$r26/code-readings" > "$base/case26.out" 2>"$base/case26.err"
  local rc26=$?
  local orders26_json="$r26/code-readings/screen/orders.json"
  local v_def26
  v_def26="$(jq -c '.["読み取り結果"]["ラベル-単位の定義"]["値"]' "$orders26_json" 2>/dev/null)"
  check "単位の定義: カンマで閉じた呼び出し式は次行の除外オブジェクトを取り込まない" "$([ "$rc26" -eq 0 ] && [ "$v_def26" = '[]' ] && echo 0 || echo 1)"

  # --- 範囲「単位の定義」: CRLF改行のファイルで、丸括弧の署名と波括弧の
  #     本体の間の空行に`\r`が2個続いても、行末の1個以上の`\r`をすべて
  #     除いて空行と判定するため先読みが続き、対応する`}`の行を終端に
  #     する（第6版反証所見3）---
  local d27="$base/case27" r27="$base/run27"
  rm -rf "$d27" "$r27"
  mkdir -p "$d27/src/pages" "$d27/docs/design/common" "$d27/docs/design/lists"
  make_run "$r27"

  printf 'function foo($x)\r\n\r\r\n{\r\n  return $x->id;\r\n}\r\nfunction legacy($x)\r\n\r\r\n{\r\n  return $x->legacy;\r\n}\r\nfunction bar($x)\r\n\r\r\n{\r\n  return $x->name;\r\n}\r\n' > "$d27/src/pages/CrlfAllman.php"

  cat > "$d27/docs/design/common/調査と検出条件の定義書.md" <<'FIXEOF27'
# 調査と検出条件の定義書

## 4. 単位の見つけ方

### 4.1 画面

| 読み取り結果の項目 | どの構文・記述から取るか |
|---|---|
| 戻り値-単位の定義 | 正規表現: return \$x->([a-z]+); ／ 捕捉: 1 ／ 範囲: 単位の定義 |

## 5. 動的な定義
FIXEOF27

  cat > "$d27/docs/design/lists/screen.json" <<'FIXEOF27'
[
  {"種別":"screen","識別子":"foo","名前":"foo","場所":"src/pages/CrlfAllman.php","根拠":"src/pages/CrlfAllman.php:1","単位の定義":"","属するファイル":[],"分類軸":[]},
  {"種別":"screen","識別子":"bar","名前":"bar","場所":"src/pages/CrlfAllman.php","根拠":"src/pages/CrlfAllman.php:11","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF27

  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d27" --run "$r27" --kind screen --out "$r27/code-readings" > "$base/case27.out" 2>"$base/case27.err"
  local rc27=$?
  local foo27_json="$r27/code-readings/screen/foo.json"
  local v_def27
  v_def27="$(jq -c '.["読み取り結果"]["戻り値-単位の定義"]["値"]' "$foo27_json" 2>/dev/null)"
  check "単位の定義: CRLFの空行に\\rが2個続いても先読みが続き除外定義を取り込まない" "$([ "$rc27" -eq 0 ] && [ "$v_def27" = '["id"]' ] && echo 0 || echo 1)"

  # --- 不合格-フォルダ名が空（表示名がフォルダ名に使えない文字だけで空に潰れる） ---
  local d28="$base/case28" r28="$base/run28"
  make_fixture "$d28"
  make_run "$r28"
  cat > "$d28/docs/design/lists/screen.json" <<'FIXEOF'
[
  {"種別":"screen","識別子":"src/pages/Slash.tsx","表示名":"/","場所":"src/pages/Slash.tsx","根拠":"src/pages/Slash.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d28" --run "$r28" --kind screen --out "$r28/code-readings" > "$base/case28.out" 2>"$base/case28.err"
  local rc28=$?
  check "不合格-フォルダ名が空: 終了コード2" "$([ "$rc28" -eq 2 ] && echo 0 || echo 1)"
  check "不合格-フォルダ名が空: [FAIL]フォルダ名-空を識別子付きで出す" "$(grep -q '\[FAIL\] フォルダ名-空: screen: 識別子=src/pages/Slash.tsx' "$base/case28.err" && echo 0 || echo 1)"

  # --- 不合格-フォルダ名が重複（別の識別子が同じフォルダ名に落ちる） ---
  local d29="$base/case29" r29="$base/run29"
  make_fixture "$d29"
  make_run "$r29"
  cat > "$d29/docs/design/lists/screen.json" <<'FIXEOF'
[
  {"種別":"screen","識別子":"src/pages/OrderList.tsx","表示名":"注文","場所":"src/pages/OrderList.tsx","根拠":"src/pages/OrderList.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[],"フォルダ名":"dup"},
  {"種別":"screen","識別子":"src/pages/OrderDetail.tsx","表示名":"注文詳細","場所":"src/pages/OrderDetail.tsx","根拠":"src/pages/OrderDetail.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[],"フォルダ名":"dup"}
]
FIXEOF
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d29" --run "$r29" --kind screen --out "$r29/code-readings" > "$base/case29.out" 2>"$base/case29.err"
  local rc29=$?
  check "不合格-フォルダ名が重複: 終了コード2" "$([ "$rc29" -eq 2 ] && echo 0 || echo 1)"
  check "不合格-フォルダ名が重複: [FAIL]フォルダ名-重複を識別子の列挙付きで出す" "$(grep -q '\[FAIL\] フォルダ名-重複: screen: フォルダ名=dup 識別子=src/pages/OrderList.tsx;src/pages/OrderDetail.tsx' "$base/case29.err" && echo 0 || echo 1)"

  # --- 不合格-出力件数不一致（単位を減らしても古い出力ファイルが残る） ---
  local d30="$base/case30" r30="$base/run30"
  make_fixture "$d30"
  make_run "$r30"
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d30" --run "$r30" --kind screen --out "$r30/code-readings" > "$base/case30a.out" 2>"$base/case30a.err"
  local rc30a=$?
  cat > "$d30/docs/design/lists/screen.json" <<'FIXEOF'
[
  {"種別":"screen","識別子":"src/pages/OrderList.tsx","名前":"OrderList","場所":"src/pages/OrderList.tsx","根拠":"src/pages/OrderList.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d30" --run "$r30" --kind screen --out "$r30/code-readings" > "$base/case30b.out" 2>"$base/case30b.err"
  local rc30b=$?
  check "不合格-出力件数不一致: 初回は終了コード0" "$([ "$rc30a" -eq 0 ] && echo 0 || echo 1)"
  check "不合格-出力件数不一致: 単位を減らすと終了コード2" "$([ "$rc30b" -eq 2 ] && echo 0 || echo 1)"
  check "不合格-出力件数不一致: [FAIL]出力-件数不一致を出す" "$(grep -q '\[FAIL\] 出力-件数不一致: screen: 単位数=1 実ファイル数=2' "$base/case30b.err" && echo 0 || echo 1)"

  # --- 不合格-フォルダ名が重複（大文字小文字だけの違いは正規化して重複扱いにする） ---
  local d31="$base/case31" r31="$base/run31"
  make_fixture "$d31"
  make_run "$r31"
  cat > "$d31/docs/design/lists/screen.json" <<'FIXEOF'
[
  {"種別":"screen","識別子":"src/pages/Order.tsx","表示名":"注文","場所":"src/pages/Order.tsx","根拠":"src/pages/Order.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[],"フォルダ名":"Order"},
  {"種別":"screen","識別子":"src/pages/order.tsx","表示名":"注文詳細","場所":"src/pages/order.tsx","根拠":"src/pages/order.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[],"フォルダ名":"order"}
]
FIXEOF
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d31" --run "$r31" --kind screen --out "$r31/code-readings" > "$base/case31.out" 2>"$base/case31.err"
  local rc31=$?
  check "不合格-フォルダ名が重複-正規化: 大文字小文字だけの違いは書き込み前に終了コード2で止める（出力先が空のまま）" "$([ "$rc31" -eq 2 ] && [ ! -d "$r31/code-readings/screen" ] && grep -q '\[FAIL\] フォルダ名-重複: screen: フォルダ名=Order;order' "$base/case31.err" && echo 0 || echo 1)"

  # --- 不合格-フォルダ名が重複（NFC/NFDの合成分解だけの違いは正規化して重複扱いにする） ---
  local d32="$base/case32" r32="$base/run32" nfc_po nfd_po
  nfc_po="$(printf '\xe3\x83\x9d')"
  nfd_po="$(printf '\xe3\x83\x9b\xe3\x82\x9a')"
  make_fixture "$d32"
  make_run "$r32"
  cat > "$d32/docs/design/lists/screen.json" <<FIXEOF32
[
  {"種別":"screen","識別子":"src/pages/PoNfc.tsx","表示名":"NFC","場所":"src/pages/PoNfc.tsx","根拠":"src/pages/PoNfc.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[],"フォルダ名":"${nfc_po}"},
  {"種別":"screen","識別子":"src/pages/PoNfd.tsx","表示名":"NFD","場所":"src/pages/PoNfd.tsx","根拠":"src/pages/PoNfd.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[],"フォルダ名":"${nfd_po}"}
]
FIXEOF32
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d32" --run "$r32" --kind screen --out "$r32/code-readings" > "$base/case32.out" 2>"$base/case32.err"
  local rc32=$?
  check "不合格-フォルダ名が重複-正規化: NFC_NFDの合成分解だけの違いは書き込み前に終了コード2で止める（出力先が空のまま）" "$([ "$rc32" -eq 2 ] && [ ! -d "$r32/code-readings/screen" ] && grep -q '\[FAIL\] フォルダ名-重複: screen:' "$base/case32.err" && echo 0 || echo 1)"

  # --- 不合格-フォルダ名が不正（相対パスの上位参照は出力先の外へ書く前に止める） ---
  local d33="$base/case33" r33="$base/run33"
  make_fixture "$d33"
  make_run "$r33"
  cat > "$d33/docs/design/lists/screen.json" <<'FIXEOF'
[
  {"種別":"screen","識別子":"src/pages/Escaped.tsx","表示名":"脱出","場所":"src/pages/Escaped.tsx","根拠":"src/pages/Escaped.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[],"フォルダ名":"../escaped"}
]
FIXEOF
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d33" --run "$r33" --kind screen --out "$r33/code-readings" > "$base/case33.out" 2>"$base/case33.err"
  local rc33=$?
  check "不合格-フォルダ名が不正: 相対パスの上位参照は書き込み前に終了コード2で止め出力先の外へ書かない" "$([ "$rc33" -eq 2 ] && [ -z "$(ls -A "$r33/code-readings" 2>/dev/null)" ] && grep -q '\[FAIL\] フォルダ名-不正: screen: フォルダ名=../escaped 識別子=src/pages/Escaped.tsx' "$base/case33.err" && echo 0 || echo 1)"

  # --- 不合格-フォルダ名が空（空白1文字は不可視文字を除いて空と判定する） ---
  local d34="$base/case34" r34="$base/run34"
  make_fixture "$d34"
  make_run "$r34"
  cat > "$d34/docs/design/lists/screen.json" <<'FIXEOF'
[
  {"種別":"screen","識別子":"src/pages/Blank.tsx","表示名":"空白","場所":"src/pages/Blank.tsx","根拠":"src/pages/Blank.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[],"フォルダ名":" "}
]
FIXEOF
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d34" --run "$r34" --kind screen --out "$r34/code-readings" > "$base/case34.out" 2>"$base/case34.err"
  local rc34=$?
  check "不合格-フォルダ名が空: 空白1文字は不可視文字を除いて空と判定し終了コード2で止める" "$([ "$rc34" -eq 2 ] && [ -z "$(ls -A "$r34/code-readings" 2>/dev/null)" ] && grep -q '\[FAIL\] フォルダ名-空: screen: 識別子=src/pages/Blank.tsx' "$base/case34.err" && echo 0 || echo 1)"

  # --- 不合格-フォルダ名が不正（先頭がドットの値は隠しファイルになるため止める） ---
  local d35="$base/case35" r35="$base/run35"
  make_fixture "$d35"
  make_run "$r35"
  cat > "$d35/docs/design/lists/screen.json" <<'FIXEOF'
[
  {"種別":"screen","識別子":"src/pages/Hidden.tsx","表示名":"隠し","場所":"src/pages/Hidden.tsx","根拠":"src/pages/Hidden.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[],"フォルダ名":".hidden"}
]
FIXEOF
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d35" --run "$r35" --kind screen --out "$r35/code-readings" > "$base/case35.out" 2>"$base/case35.err"
  local rc35=$?
  check "不合格-フォルダ名が不正: 先頭がドットの値は書き込み前に終了コード2で止める" "$([ "$rc35" -eq 2 ] && [ -z "$(ls -A "$r35/code-readings" 2>/dev/null)" ] && grep -q '\[FAIL\] フォルダ名-不正: screen: フォルダ名=.hidden 識別子=src/pages/Hidden.tsx' "$base/case35.err" && echo 0 || echo 1)"

  # --- 不合格-前提-perl不在（perlが使えない環境ではフォルダ名の検査が
  #     できず、判定不能として何も書かずに止める。第1回改善指示書1-30・
  #     第2版反証） ---
  local d36="$base/case36" r36="$base/run36"
  make_fixture "$d36"
  make_run "$r36"
  mkdir -p "$base/noperl"
  cat > "$base/noperl/perl" <<'FIXEOF'
#!/bin/sh
exit 127
FIXEOF
  chmod +x "$base/noperl/perl"
  PATH="$base/noperl:$PATH" bash "$SCRIPT_DIR/extract-code-readings.sh" "$d36" --run "$r36" --kind screen --out "$r36/code-readings" > "$base/case36.out" 2>"$base/case36.err"
  local rc36=$?
  check "不合格-前提-perl不在: perlが使えないと終了コード2で止め出力先が空のまま" "$([ "$rc36" -eq 2 ] && [ ! -d "$r36/code-readings/screen" ] && grep -q '\[FAIL\] 前提-perl不在: screen:' "$base/case36.err" && echo 0 || echo 1)"

  # --- 不合格-フォルダ名が重複（大文字小文字の畳み込みでßとssが重複する。
  #     第1回改善指示書1-30・第2版反証） ---
  local d37="$base/case37" r37="$base/run37" eszett
  eszett="$(printf '\xc3\x9f')"
  make_fixture "$d37"
  make_run "$r37"
  cat > "$d37/docs/design/lists/screen.json" <<FIXEOF37
[
  {"種別":"screen","識別子":"src/pages/Strasse.tsx","表示名":"通り(エスツェット)","場所":"src/pages/Strasse.tsx","根拠":"src/pages/Strasse.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[],"フォルダ名":"${eszett}"},
  {"種別":"screen","識別子":"src/pages/StrasseSs.tsx","表示名":"通り(ss)","場所":"src/pages/StrasseSs.tsx","根拠":"src/pages/StrasseSs.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[],"フォルダ名":"ss"}
]
FIXEOF37
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d37" --run "$r37" --kind screen --out "$r37/code-readings" > "$base/case37.out" 2>"$base/case37.err"
  local rc37=$?
  check "不合格-フォルダ名が重複-畳み込み: ßとssは大文字小文字の畳み込みで重複扱いになり書き込み前に終了コード2で止める（出力先が空のまま）" "$([ "$rc37" -eq 2 ] && [ ! -d "$r37/code-readings/screen" ] && grep -q '\[FAIL\] フォルダ名-重複: screen:' "$base/case37.err" && echo 0 || echo 1)"

  # --- 不合格-前提-fc不在（-Mfeature=fcを含む呼び出しだけ失敗させ、
  #     含まない呼び出しは本物のperlへ委譲する偽perl。委譲することで
  #     Unicode::Normalizeが実際に読み込めることも検証しつつ、fc
  #     （perl 5.16以降の機能）だけが使えない環境を再現する。すべての
  #     呼び出しを一律exit 0にする粗いスタブでは、この検証を伴わない
  #     （第1回改善指示書1-30・第4版反証所見2）。「perl -MUnicode::
  #     Normalize -e 1」だけの前提確認では通過してしまうことの再発防止。
  #     第1回改善指示書1-30・第3版反証） ---
  local d38="$base/case38" r38="$base/run38" real_perl38
  real_perl38="$(command -v perl)"
  make_fixture "$d38"
  make_run "$r38"
  mkdir -p "$base/nofc"
  cat > "$base/nofc/perl" <<'FIXEOF'
#!/bin/sh
case "$*" in
  *-Mfeature=fc*) exit 1 ;;
esac
exec "$REAL_PERL" "$@"
FIXEOF
  chmod +x "$base/nofc/perl"
  REAL_PERL="$real_perl38" PATH="$base/nofc:$PATH" bash "$SCRIPT_DIR/extract-code-readings.sh" "$d38" --run "$r38" --kind screen --out "$r38/code-readings" > "$base/case38.out" 2>"$base/case38.err"
  local rc38=$?
  check "不合格-前提-fc不在: fcが使えないと終了コード2で止め出力先が空のまま" "$([ "$rc38" -eq 2 ] && [ ! -d "$r38/code-readings/screen" ] && grep -q '\[FAIL\] 前提-perl不在: screen:' "$base/case38.err" && echo 0 || echo 1)"

  # --- AI値引き継ぎ（取り直しでAIが埋めた値・全単位が処理されること） ---
  local d39="$base/case39" r39="$base/run39"
  make_fixture "$d39"
  make_run "$r39"
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d39" --run "$r39" --kind screen --out "$r39/code-readings" > "$base/case39a.out" 2>"$base/case39a.err"
  local orderlist39="$r39/code-readings/screen/src_pages_OrderList.tsx.json"
  local orderdetail39="$r39/code-readings/screen/src_pages_OrderDetail.tsx.json"
  local tmp39
  tmp39="$(mktemp "${base}/case39.tmp.XXXXXX")"
  jq '.["読み取り結果"]["呼ぶ接続窓口"]["値"] = ["OrdersService"] | .["読み取り結果"]["呼ぶ接続窓口"]["根拠"] = ["manual"]' \
    "$orderlist39" > "$tmp39" && mv "$tmp39" "$orderlist39"
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d39" --run "$r39" --kind screen --out "$r39/code-readings" > "$base/case39b.out" 2>"$base/case39b.err"
  local rc39b=$?
  local ai_kept39
  ai_kept39="$(jq -c '.["読み取り結果"]["呼ぶ接続窓口"]["値"]' "$orderlist39" 2>/dev/null)"
  check "AI値引き継ぎ: 取り直し後もAIが埋めた値が残る" "$([ "$rc39b" -eq 0 ] && [ "$ai_kept39" = '["OrdersService"]' ] && echo 0 || echo 1)"
  check "AI値引き継ぎ: --unit無しでは全単位を処理する" "$(grep -q '単位数=2' "$base/case39b.out" && echo 0 || echo 1)"

  # --- 単位絞り込み（--unit）は指定した単位以外に触れない ---
  touch -t 202001010000 "$orderdetail39"
  local before_hash40 before_mtime40
  before_hash40="$(shasum "$orderdetail39" | awk '{print $1}')"
  before_mtime40="$(stat -f %m "$orderdetail39")"
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d39" --run "$r39" --kind screen --out "$r39/code-readings" --unit src/pages/OrderList.tsx > "$base/case40.out" 2>"$base/case40.err"
  local rc40=$?
  local after_hash40 after_mtime40
  after_hash40="$(shasum "$orderdetail39" | awk '{print $1}')"
  after_mtime40="$(stat -f %m "$orderdetail39")"
  check "単位絞り込み: --unitを指定した実行は終了コード0" "$([ "$rc40" -eq 0 ] && echo 0 || echo 1)"
  check "単位絞り込み: 他の単位のファイルの中身が変わらない" "$([ "$before_hash40" = "$after_hash40" ] && echo 0 || echo 1)"
  check "単位絞り込み: 他の単位のファイルの更新時刻が変わらない" "$([ "$before_mtime40" = "$after_mtime40" ] && echo 0 || echo 1)"
  local ai_kept40
  ai_kept40="$(jq -c '.["読み取り結果"]["呼ぶ接続窓口"]["値"]' "$orderlist39" 2>/dev/null)"
  check "単位絞り込み: 絞った単位のAI値も引き継がれる" "$([ "$ai_kept40" = '["OrdersService"]' ] && echo 0 || echo 1)"

  # --- 単位絞り込み（--unit）で一覧に無い識別子を渡す ---
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d39" --run "$r39" --kind screen --out "$r39/code-readings" --unit does-not-exist > "$base/case41.out" 2>"$base/case41.err"
  local rc41=$?
  check "単位絞り込み: 一覧に無い識別子は終了コード2" "$([ "$rc41" -eq 2 ] && echo 0 || echo 1)"
  check "単位絞り込み: [FAIL]単位-不在のメッセージが出る" "$(grep -q '\[FAIL\] 単位-不在: screen/does-not-exist は一覧にありません' "$base/case41.err" && echo 0 || echo 1)"

  # --- 機械の項目は取り直しのたびに毎回コードから取り直す（引き継がない） ---
  local d42="$base/case42" r42="$base/run42"
  make_fixture "$d42"
  make_run "$r42"
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d42" --run "$r42" --kind screen --out "$r42/code-readings" > "$base/case42a.out" 2>"$base/case42a.err"
  local orderlist42="$r42/code-readings/screen/src_pages_OrderList.tsx.json"
  local tmp42
  tmp42="$(mktemp "${base}/case42.tmp.XXXXXX")"
  jq '.["読み取り結果"]["入力項目"]["値"] = ["STALE"]' "$orderlist42" > "$tmp42" && mv "$tmp42" "$orderlist42"
  cat >> "$d42/src/pages/OrderList.tsx" <<'FIXEOF'
<input name="newField" />
FIXEOF
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d42" --run "$r42" --kind screen --out "$r42/code-readings" > "$base/case42b.out" 2>"$base/case42b.err"
  local machine_refreshed42
  machine_refreshed42="$(jq -c '.["読み取り結果"]["入力項目"]["値"]' "$orderlist42" 2>/dev/null)"
  check "機械項目再取得: 手で書き換えた値を引き継がずコードから取り直す" "$([ "$machine_refreshed42" = '["orderId","newField"]' ] && echo 0 || echo 1)"

  # --- 単位絞り込み（--unit）でも重複フォルダ名は絞り込み前の全単位で検査する ---
  local d43="$base/case43" r43="$base/run43"
  make_fixture "$d43"
  make_run "$r43"
  cat > "$d43/docs/design/lists/screen.json" <<'FIXEOF'
[
  {"種別":"screen","識別子":"src/pages/OrderList.tsx","表示名":"注文","場所":"src/pages/OrderList.tsx","根拠":"src/pages/OrderList.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[],"フォルダ名":"dup"},
  {"種別":"screen","識別子":"src/pages/OrderDetail.tsx","表示名":"注文詳細","場所":"src/pages/OrderDetail.tsx","根拠":"src/pages/OrderDetail.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[],"フォルダ名":"dup"}
]
FIXEOF
  bash "$SCRIPT_DIR/extract-code-readings.sh" "$d43" --run "$r43" --kind screen --out "$r43/code-readings" --unit src/pages/OrderList.tsx > "$base/case43.out" 2>"$base/case43.err"
  local rc43=$?
  check "単位絞り込み-フォルダ名重複: --unit指定でも全単位で検査し終了コード2" "$([ "$rc43" -eq 2 ] && echo 0 || echo 1)"
  check "単位絞り込み-フォルダ名重複: [FAIL]フォルダ名-重複を識別子の列挙付きで出す" "$(grep -q '\[FAIL\] フォルダ名-重複: screen: フォルダ名=dup 識別子=src/pages/OrderList.tsx;src/pages/OrderDetail.tsx' "$base/case43.err" && echo 0 || echo 1)"
  check "単位絞り込み-フォルダ名重複: 出力先へ書き込まない" "$([ ! -d "$r43/code-readings/screen" ] && echo 0 || echo 1)"

  echo "実行 ${total} 件 / 失敗 ${fail} 件"
  if [ "$fail" -gt 0 ]; then
    return 1
  fi
  return 0
}

# ============================================================
# エントリポイント
# ============================================================

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

if [ $# -lt 1 ]; then
  usage_error
fi

run_main "$@"
