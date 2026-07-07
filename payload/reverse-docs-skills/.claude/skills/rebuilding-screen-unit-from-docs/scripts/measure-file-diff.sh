#!/usr/bin/env bash
# measure-file-diff.sh — Phase 5 の計測を行う。旧来の4項目（import diff / style diff /
# 全体diff / 実質diff）に加え、契約突合（export名・定数値・ハンドラ名・型名・状態変数名・
# API呼出先の6カテゴリ）を機械抽出して集合突合し、verdict の判定式に契約突合の結果を使う。
#
# 「単体テスト仕様の検査」（禁止パターン・import・コンポーネント/API利用）は
# 本スクリプトの対象外。Phase 5 でメインが別途実施する。
#
# 用途:
#   rebuilding-screen-unit-from-docs スキル Phase 5 の差分比較。生成ファイルと原本ファイル
#   （Phase 2 の白紙化前コミットから git show で取り出した一時ファイル）を突合し、
#   import diff だけでの合格判定を防ぐため、契約突合を含む計測を必ず一括出力する。
#
# 引数:
#   $1 = 生成ファイル（generated-file）
#   $2 = 原本ファイル（original-file）
#
# 標準出力（key=value を1行ずつ・この順・機械可読）:
#   import_diff_lines=<整数>
#   style_diff_lines=<整数>
#   export_diff_lines=<整数>
#   const_diff_lines=<整数>
#   handler_diff_lines=<整数>
#   type_diff_lines=<整数>
#   state_diff_lines=<整数>
#   apicall_diff_lines=<整数>
#   contract_match=YES|NO
#   total_diff_lines=<整数>
#   substantive_diff_lines=<整数>
#   verdict=PASS|FAIL
#
# 合格条件（verdict=PASS）:
#   import_diff_lines == 0 && style_diff_lines == 0 && contract_match == YES
#   total_diff_lines と substantive_diff_lines は参考値として出力を継続するが、
#   verdict の判定には使わない（旧「実質diff 20行以下」のしきい値は撤去した）。
#
# contract_match の算出:
#   export_diff_lines / const_diff_lines / handler_diff_lines / type_diff_lines /
#   state_diff_lines / apicall_diff_lines の6項目が全て0のとき YES、
#   1つでも非0のとき NO。
#
# 算出方法（heuristic）:
#   import_diff_lines      : （旧来通り）両ファイルからコメント行を除去→複数行 import を
#                            1論理行へ結合（連続空白は1個に畳み、末尾カンマ `, }` は ` }` へ
#                            正規化）→ `^\s*import ` 行を抽出→前後空白除去→ソート→
#                            diff の差分行数（`^[<>]` 行の数）
#                            （既知の限界: import 抽出は sort -u で重複を畳むため、生成物側にのみ存在する
#                             重複 import 行は import diff に現れない。重複 import の検出はスコープ外）
#   style_diff_lines       : （旧来通り）コメント行を除去した上で、行全体ではなく className /
#                            style 属性の値部分（`className="..."` / `style={...}` 等）・
#                            16進カラーコード・px/rem/em/vh/vw 数値のみを `grep -oE` で
#                            抽出→前後空白除去→ソート→diff の差分行数。px/rem 等の数値は
#                            直後が区切り文字（`;` `,` `)` `}` `]` クォート・空白・行末）の
#                            場合のみスタイル値とみなし、UI文言中に密着した数値
#                            （例:「16pxです」）は対象外とする
#                            （既知の限界: 多重ネストした `{}` 式〔三項演算子を含む複雑な式等〕は
#                             最初の `}` で止まるため不完全抽出になりうる。bash の拡張正規表現は
#                             再帰的な括弧マッチに対応できないため原理的に解消不能）
#   export_diff_lines      : `export (const|function|class|default|type|interface) <名>` の
#                            名前、`export default (function|class) <名>` の名前、
#                            `export { a, b as c }` の要素名（`as` 右辺があればそちら）を
#                            抽出→ソート→diff の差分行数
#                            （既知の限界: `export default function() {}` のように名前を持たない
#                             default export は抽出できない。複数行にまたがる `export { ... }` も
#                             1行内の `[^}]*` までしか追えず不完全になりうる）
#   const_diff_lines       : `const <NAME> = <リテラル値>;`（文字列/数値/真偽値リテラルのみ・
#                            `export const` 形式も同一視して抽出対象に含む）の `NAME=値` ペアを
#                            抽出→ソート→diff の差分行数
#                            （既知の限界: インデント段数によるトップレベル判定は行わない
#                             〔どの階層の const 代入行でもパターン一致すれば抽出対象になる〕。
#                             テンプレートリテラルや式を値に持つ const、複数変数の同時宣言
#                             `const a = 1, b = 2;` は対象外）
#   handler_diff_lines     : `(const|function) (handle|on)[A-Z]\w*` の識別子名、および
#                            JSX 属性 `on[A-Z]\w*=` の属性名を抽出→ソート→diff の差分行数
#                            （既知の限界: 単語境界の先読み/後読みが POSIX ERE で表現できないため、
#                             camelCase 語の途中に `on`+大文字 が偶然出現する場合
#                             〔例: `commonOnClick`〕に誤検出しうる）
#   type_diff_lines        : `(type|interface) <名>` の名前を抽出→ソート→diff の差分行数
#                            （既知の限界: 単語境界を考慮しないため、他の識別子の末尾に
#                             `type`/`interface` が連続して現れる稀なケースを誤検出しうる）
#   state_diff_lines       : `const [x, setX] = useState(...)` の分割代入2名（x と setX）を
#                            抽出→ソート→diff の差分行数
#                            （既知の限界: 配列以外の分割代入パターンや `useReducer` 等の
#                             他フックは対象外）
#   apicall_diff_lines     : `fetch(<引数>)` / `axios.<method>(<引数>)` / `api.<name>(` の
#                            呼出先識別子チェーン＋第一文字列引数（`チェーン|第一引数` 形式）を
#                            抽出→ソート→diff の差分行数
#                            （既知の限界: 変数経由の呼出先〔`const f = fetch; f(...)`〕や
#                             テンプレートリテラル引数は対象外。複数行にまたがる呼び出しは
#                             最初の行の `(` までしか見ない）
#   total_diff_lines       : diff によるファイル全体の差分行数（参考値。verdict には使わない）
#   substantive_diff_lines : コメント行（// ・/* ・*）と空行を除外し、前後空白を
#                            除去した上での diff 差分行数（参考値。verdict には使わない）
#
# 前後空白除去について: 条件分岐の書き方（早期return vs 三項演算子等）の違いで
# ネスト段数がずれると、内容が同一の行でも行頭インデント幅だけが異なり、素朴な
# 文字列比較では誤って差分と判定される。行頭・行末の空白を除去してから比較する
# ことで、この誤検出を防ぐ（インデント自体の一致・不一致は判定対象にしない）。
#
# 終了コード:
#   引数不足・ファイル不在 = 1（stderr にメッセージ） / 正常時 = 0
#
# 使い方:
#   ./measure-file-diff.sh <generated-file> <original-file>
#
# macOS bash 3.2 互換: mapfile 等の bash4 専用機能は使わない。

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "使い方: $0 <generated-file> <original-file>" >&2
  exit 1
fi

GENERATED="$1"
ORIGINAL="$2"

if [ ! -f "$GENERATED" ]; then
  echo "エラー: 生成ファイルが存在しません: $GENERATED" >&2
  exit 1
fi
if [ ! -f "$ORIGINAL" ]; then
  echo "エラー: 原本ファイルが存在しません: $ORIGINAL" >&2
  exit 1
fi

# 行頭・行末の空白を除去する。インデント幅だけが異なる（条件分岐の書き方の違い等で
# ネスト段数がずれる）行を、内容が同一なら差分として誤検出しないための共通ヘルパー。
trim_whitespace() {
  sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

# 行頭が // ・/* ・* で始まるコメント行を除去する。style/import/substantive/契約突合の
# いずれの抽出でも、コメント内の px・色コード・import 風文字列・識別子風文字列を差分として
# 誤検出しないための共通前処理。
strip_comments() {
  grep -vE '^[[:space:]]*(//|/\*|\*)' 2>/dev/null || true
}

# `import {` で始まり `}` が同一行に無い複数行 import を、閉じ `}` を含む行までを
# 1 論理行へ結合する。折り返し import の要素欠落を import diff で検出するため。
normalize_imports() {
  awk '
    inimport {
      buf = buf " " $0
      if ($0 ~ /}/) {
        gsub(/[[:space:]]+/, " ", buf)
        gsub(/,[[:space:]]*}/, " }", buf)
        gsub(/\{[[:space:]]*/, "{ ", buf)
        sub(/^[[:space:]]+/, "", buf)
        print buf
        inimport=0
      }
      next
    }
    /^[[:space:]]*import[[:space:]]/ && /{/ && $0 !~ /}/ { buf=$0; inimport=1; next }
    { print }
  ' 2>/dev/null || true
}

# --- import diff ---
extract_imports() {
  strip_comments < "$1" 2>/dev/null | normalize_imports | grep -E '^[[:space:]]*import ' | trim_whitespace | sort -u || true
}
IMPORT_DIFF_LINES=$(diff <(extract_imports "$ORIGINAL") <(extract_imports "$GENERATED") | grep -cE '^[<>]' || true)

# --- style diff ---
# className / style 属性、16進カラーコード、
# px/rem/em/vh/vw 数値を含む行をスタイル定数行とみなす。
STYLE_PATTERN='className[[:space:]]*=[[:space:]]*("[^"]*"|'"'"'[^'"'"']*'"'"'|\{[^}]*\})'
STYLE_PATTERN="$STYLE_PATTERN"'|style[[:space:]]*=[[:space:]]*(\{[^}]*\}|"[^"]*"|'"'"'[^'"'"']*'"'"')'
STYLE_PATTERN="$STYLE_PATTERN"'|#[0-9a-fA-F]{3,8}'
STYLE_PATTERN="$STYLE_PATTERN"'|[0-9]+(px|rem|em|vh|vw)([];,)}"'"'"'[:space:]]|$)'
extract_style_lines() {
  strip_comments < "$1" 2>/dev/null | grep -oE "$STYLE_PATTERN" | trim_whitespace | sort -u || true
}
STYLE_DIFF_LINES=$(diff <(extract_style_lines "$ORIGINAL") <(extract_style_lines "$GENERATED") | grep -cE '^[<>]' || true)

# --- export diff ---
EXPORT_KEYWORD_PATTERN="export[[:space:]]+(const|function|class|default|type|interface)[[:space:]]+[A-Za-z_\$][A-Za-z0-9_\$]*"
EXPORT_DEFAULT_FN_PATTERN="export[[:space:]]+default[[:space:]]+(function|class)[[:space:]]+[A-Za-z_\$][A-Za-z0-9_\$]*"
EXPORT_BRACE_PATTERN="export[[:space:]]*\{[^}]*\}"
extract_exports() {
  local content
  content=$(strip_comments < "$1" 2>/dev/null) || true
  {
    printf '%s\n' "$content" | grep -oE "$EXPORT_KEYWORD_PATTERN" | awk '{print $NF}' || true
    printf '%s\n' "$content" | grep -oE "$EXPORT_DEFAULT_FN_PATTERN" | awk '{print $NF}' || true
    printf '%s\n' "$content" | grep -oE "$EXPORT_BRACE_PATTERN" | sed -E 's/^export[[:space:]]*\{//; s/\}$//' | tr ',' '\n' | sed -E 's/.*[[:space:]]as[[:space:]]+//' || true
  } | trim_whitespace | grep -vE '^$' | sort -u || true
}
EXPORT_DIFF_LINES=$(diff <(extract_exports "$ORIGINAL") <(extract_exports "$GENERATED") | grep -cE '^[<>]' || true)

# --- const diff ---
# `const` / `export const` の両形式を同一視し、リテラル値（文字列/数値/真偽値）のみを対象とする。
CONST_SED_SCRIPT="s/^[[:space:]]*(export[[:space:]]+)?const[[:space:]]+([A-Za-z_\$][A-Za-z0-9_\$]*)[[:space:]]*=[[:space:]]*(\"[^\"]*\"|'[^']*'|-?[0-9]+(\.[0-9]+)?|true|false)[[:space:]]*;.*/\2=\3/"
extract_consts() {
  strip_comments < "$1" 2>/dev/null | sed -nE "${CONST_SED_SCRIPT}p" | trim_whitespace | sort -u || true
}
CONST_DIFF_LINES=$(diff <(extract_consts "$ORIGINAL") <(extract_consts "$GENERATED") | grep -cE '^[<>]' || true)

# --- handler diff ---
HANDLER_DECL_PATTERN="(const|function)[[:space:]]+(handle|on)[A-Z][A-Za-z0-9_]*"
HANDLER_JSX_PATTERN="on[A-Z][A-Za-z0-9_]*="
extract_handlers() {
  local content
  content=$(strip_comments < "$1" 2>/dev/null) || true
  {
    printf '%s\n' "$content" | grep -oE "$HANDLER_DECL_PATTERN" | awk '{print $NF}' || true
    printf '%s\n' "$content" | grep -oE "$HANDLER_JSX_PATTERN" | sed -E 's/=$//' || true
  } | trim_whitespace | grep -vE '^$' | sort -u || true
}
HANDLER_DIFF_LINES=$(diff <(extract_handlers "$ORIGINAL") <(extract_handlers "$GENERATED") | grep -cE '^[<>]' || true)

# --- type diff ---
TYPE_PATTERN="(type|interface)[[:space:]]+[A-Za-z_\$][A-Za-z0-9_\$]*"
extract_types() {
  strip_comments < "$1" 2>/dev/null | grep -oE "$TYPE_PATTERN" | awk '{print $NF}' | trim_whitespace | sort -u || true
}
TYPE_DIFF_LINES=$(diff <(extract_types "$ORIGINAL") <(extract_types "$GENERATED") | grep -cE '^[<>]' || true)

# --- state diff ---
extract_state() {
  local content
  content=$(strip_comments < "$1" 2>/dev/null) || true
  {
    printf '%s\n' "$content" | sed -nE 's/.*const[[:space:]]*\[[[:space:]]*([A-Za-z_$][A-Za-z0-9_$]*)[[:space:]]*,[[:space:]]*[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*\][[:space:]]*=[[:space:]]*useState.*/\1/p'
    printf '%s\n' "$content" | sed -nE 's/.*const[[:space:]]*\[[[:space:]]*[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*,[[:space:]]*([A-Za-z_$][A-Za-z0-9_$]*)[[:space:]]*\][[:space:]]*=[[:space:]]*useState.*/\1/p'
  } | trim_whitespace | grep -vE '^$' | sort -u || true
}
STATE_DIFF_LINES=$(diff <(extract_state "$ORIGINAL") <(extract_state "$GENERATED") | grep -cE '^[<>]' || true)

# --- apicall diff ---
APICALL_PATTERN="(fetch|axios\.[A-Za-z_\$][A-Za-z0-9_\$]*|api\.[A-Za-z_\$][A-Za-z0-9_\$]*)[[:space:]]*\([[:space:]]*(\"[^\"]*\"|'[^']*')?"
extract_apicalls() {
  strip_comments < "$1" 2>/dev/null | grep -oE "$APICALL_PATTERN" | sed -E 's/[[:space:]]*\([[:space:]]*/|/' | trim_whitespace | sort -u || true
}
APICALL_DIFF_LINES=$(diff <(extract_apicalls "$ORIGINAL") <(extract_apicalls "$GENERATED") | grep -cE '^[<>]' || true)

# --- contract match（6カテゴリ全て0か） ---
if [ "$EXPORT_DIFF_LINES" -eq 0 ] && [ "$CONST_DIFF_LINES" -eq 0 ] && [ "$HANDLER_DIFF_LINES" -eq 0 ] \
  && [ "$TYPE_DIFF_LINES" -eq 0 ] && [ "$STATE_DIFF_LINES" -eq 0 ] && [ "$APICALL_DIFF_LINES" -eq 0 ]; then
  CONTRACT_MATCH="YES"
else
  CONTRACT_MATCH="NO"
fi

# --- total diff（参考値） ---
TOTAL_DIFF_LINES=$(diff "$ORIGINAL" "$GENERATED" | grep -cE '^[<>]' || true)

# --- substantive diff（コメント・空行除外・参考値） ---
strip_noise() {
  strip_comments < "$1" 2>/dev/null | normalize_imports | grep -vE '^[[:space:]]*$' | trim_whitespace || true
}
SUBSTANTIVE_DIFF_LINES=$(diff <(strip_noise "$ORIGINAL") <(strip_noise "$GENERATED") | grep -cE '^[<>]' || true)

# --- verdict ---
if [ "$IMPORT_DIFF_LINES" -eq 0 ] && [ "$STYLE_DIFF_LINES" -eq 0 ] && [ "$CONTRACT_MATCH" = "YES" ]; then
  VERDICT="PASS"
else
  VERDICT="FAIL"
fi

echo "import_diff_lines=$IMPORT_DIFF_LINES"
echo "style_diff_lines=$STYLE_DIFF_LINES"
echo "export_diff_lines=$EXPORT_DIFF_LINES"
echo "const_diff_lines=$CONST_DIFF_LINES"
echo "handler_diff_lines=$HANDLER_DIFF_LINES"
echo "type_diff_lines=$TYPE_DIFF_LINES"
echo "state_diff_lines=$STATE_DIFF_LINES"
echo "apicall_diff_lines=$APICALL_DIFF_LINES"
echo "contract_match=$CONTRACT_MATCH"
echo "total_diff_lines=$TOTAL_DIFF_LINES"
echo "substantive_diff_lines=$SUBSTANTIVE_DIFF_LINES"
echo "verdict=$VERDICT"
