#!/usr/bin/env bash
# measure-file-diff.sh — Phase 5 の計測を行う。旧来の4項目（import diff / style diff /
# 全体diff / 実質diff）に加え、契約突合（export名・定数値・ハンドラ名・型名・状態変数名・
# API呼出先の6カテゴリ）を機械抽出して集合突合し、さらにコメント・改行・宣言順序・
# ローカル変数抽出等の書式差を吸収するスタイル正規化diffを算出して、verdict の
# 判定式に契約突合とスタイル正規化diffの結果を使う。
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
#   --self-test を第1引数に渡すと、内蔵の合成フィクスチャ4ケースで自己テストを実行する
#   （ファイル引数は不要）。全ケースPASSなら exit 0、FAILがあれば exit 1。
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
#   style_normalized_diff_lines=<整数>
#   verdict=PASS|FAIL
#
# 合格条件（verdict=PASS）:
#   import_diff_lines == 0 && style_diff_lines == 0 && contract_match == YES
#   && (substantive_diff_lines <= 20 || style_normalized_diff_lines <= 20)
#   contract_match は export/const/handler/type/state/apicall の宣言レベルの欠落しか
#   検出できず、関数本体のロジック差分は対象外のため、実質diff 20行以下のしきい値を
#   ロジック差分の安全網として維持する。スタイル正規化diff（宣言順序の入替え・改行位置・
#   ローカル変数抽出等の書式差だけを吸収した diff）が20行以下であれば、実質diffが
#   書式差だけで跳ね上がった場合の救済路として二段判定に用いる。total_diff_lines は
#   参考値のまま。
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
#                            除去した上での diff 差分行数（verdict 判定に使用: 20行以下が
#                            条件の一つ。契約突合が対象外とするロジック差分の安全網）
#   style_normalized_diff_lines : 両ファイルからコメント行（行頭 // ・/* ・JSXコメント専用行
#                            `{/* ... */}`）を除去→改行を全除去して1行に結合→連続空白を
#                            1個へ畳み込み→`{` `;` `:` `}` の直後で論理チャンクへ再分割→
#                            前後空白除去→空行除去→ソート→diff の差分行数（verdict 判定に
#                            使用: 20行以下が条件の一つ）。宣言順序の入替え・折り返しスタイルの
#                            違い・ローカル変数抽出等の書式差を吸収し、真のロジック差分だけを
#                            残す
#                            （既知の限界: チャンク分割は `{;:}` の直後改行のみに依存するため、
#                             これらの区切り文字を含まない書式差〔スペースの意味的な違い等〕は
#                             残存しうる）
#
# 前後空白除去について: 条件分岐の書き方（早期return vs 三項演算子等）の違いで
# ネスト段数がずれると、内容が同一の行でも行頭インデント幅だけが異なり、素朴な
# 文字列比較では誤って差分と判定される。行頭・行末の空白を除去してから比較する
# ことで、この誤検出を防ぐ（インデント自体の一致・不一致は判定対象にしない）。
#
# 終了コード:
#   引数不足・ファイル不在 = 1（stderr にメッセージ） / 正常時 = 0
#   --self-test 実行時は全ケースPASS = 0 / FAILあり = 1
#
# 使い方:
#   ./measure-file-diff.sh <generated-file> <original-file>
#   ./measure-file-diff.sh --self-test
#
# macOS bash 3.2 互換: mapfile 等の bash4 専用機能は使わない。

set -euo pipefail

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

# --- const diff ---
# `const` / `export const` の両形式を同一視し、リテラル値（文字列/数値/真偽値）のみを対象とする。
CONST_SED_SCRIPT="s/^[[:space:]]*(export[[:space:]]+)?const[[:space:]]+([A-Za-z_\$][A-Za-z0-9_\$]*)[[:space:]]*=[[:space:]]*(\"[^\"]*\"|'[^']*'|-?[0-9]+(\.[0-9]+)?|true|false)[[:space:]]*;?.*/\2=\3/"
extract_consts() {
  strip_comments < "$1" 2>/dev/null | sed -nE "${CONST_SED_SCRIPT}p" | trim_whitespace | sort -u || true
}

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

# --- type diff ---
TYPE_PATTERN="(type|interface)[[:space:]]+[A-Za-z_\$][A-Za-z0-9_\$]*"
extract_types() {
  strip_comments < "$1" 2>/dev/null | grep -oE "$TYPE_PATTERN" | awk '{print $NF}' | trim_whitespace | sort -u || true
}

# --- state diff ---
extract_state() {
  local content
  content=$(strip_comments < "$1" 2>/dev/null) || true
  {
    printf '%s\n' "$content" | sed -nE 's/.*const[[:space:]]*\[[[:space:]]*([A-Za-z_$][A-Za-z0-9_$]*)[[:space:]]*,[[:space:]]*[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*\][[:space:]]*=[[:space:]]*useState.*/\1/p'
    printf '%s\n' "$content" | sed -nE 's/.*const[[:space:]]*\[[[:space:]]*[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*,[[:space:]]*([A-Za-z_$][A-Za-z0-9_$]*)[[:space:]]*\][[:space:]]*=[[:space:]]*useState.*/\1/p'
  } | trim_whitespace | grep -vE '^$' | sort -u || true
}

# --- apicall diff ---
APICALL_PATTERN="(fetch|axios\.[A-Za-z_\$][A-Za-z0-9_\$]*|api\.[A-Za-z_\$][A-Za-z0-9_\$]*)[[:space:]]*\([[:space:]]*(\"[^\"]*\"|'[^']*')?"
extract_apicalls() {
  strip_comments < "$1" 2>/dev/null | grep -oE "$APICALL_PATTERN" | sed -E 's/[[:space:]]*\([[:space:]]*/|/' | trim_whitespace | sort -u || true
}

# --- substantive diff ---
strip_noise() {
  strip_comments < "$1" 2>/dev/null | normalize_imports | grep -vE '^[[:space:]]*$' | trim_whitespace || true
}

# --- style normalized diff ---
# 宣言順序の入替え・折り返しスタイルの違い・ローカル変数抽出等の書式差を吸収した上での
# diff 差分行数を計測する。行単位の位置比較ではなく、コメント除去→改行全除去→
# 論理チャンク（`{;:}` 境界）へ再分割→ソートという手順で「内容の集合」同士を比較するため、
# 行の並び順自体の違いは差分として現れない。
compute_style_normalized_diff() {
  local file_a="$1" file_b="$2"
  local norm_a norm_b

  # $1 = 対象ファイル。コメント行・JSXコメント専用行を除去し、改行を除去して1行に結合、
  # 連続空白を畳み、`{;:}` の直後で論理チャンクへ再分割してソートする。
  normalize_style() {
    grep -vE '^\s*//|^\s*/\*|\*/\s*$|^\s*\{/\*.*\*/\}\s*$' "$1" |
    tr '\n' ' ' |
    tr -s ' ' |
    sed -E 's/([{;:}])/\1\n/g' |
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' |
    grep -v '^$' |
    sort
  }

  norm_a=$(mktemp)
  norm_b=$(mktemp)

  normalize_style "$file_a" > "$norm_a"
  normalize_style "$file_b" > "$norm_b"

  local diff_lines
  diff_lines=$(diff "$norm_a" "$norm_b" | grep -c '^[<>]' || true)

  rm -f "$norm_a" "$norm_b"
  echo "$diff_lines"
}

# --- 自己テスト（合成フィクスチャ4ケース） ---
# main 定義より前に配置する。ファイル引数なしで --self-test 起動時にのみ呼ばれる。
run_self_test() {
  local workdir fail=0
  workdir="$(mktemp -d "${TMPDIR:-/tmp}/measure-file-diff-selftest.XXXXXX")"
  trap 'rm -rf "$workdir"' RETURN

  # --- ケース1: 同一ファイル → PASS ---
  local c1_dir="$workdir/case1"
  mkdir -p "$c1_dir"
  cat > "$c1_dir/original.tsx" <<'EOF'
import React, { useState } from 'react';

export const MAX_COUNT = 10;

export function UserCard() {
  const [count, setCount] = useState(0);

  const handleClick = () => {
    fetch("/api/users");
    setCount(count + 1);
  };

  return (
    <button onClick={handleClick} className="btn">
      {count}
    </button>
  );
}
EOF
  cp "$c1_dir/original.tsx" "$c1_dir/generated.tsx"

  local c1_out c1_verdict
  c1_out="$(main "$c1_dir/generated.tsx" "$c1_dir/original.tsx")"
  c1_verdict="$(printf '%s\n' "$c1_out" | sed -n 's/^verdict=//p')"
  if [ "$c1_verdict" = "PASS" ]; then
    echo "ケース1(同一ファイル): PASS (verdict=${c1_verdict})"
  else
    echo "ケース1(同一ファイル): FAIL (期待 verdict=PASS / 実測 verdict=${c1_verdict})"
    printf '%s\n' "$c1_out"
    fail=1
  fi

  # --- ケース2: スタイル差のみ（宣言順入替え + JSXコメント追加 + ローカル変数抽出）→ PASS ---
  # 契約（export/const/handler/type/state/apicall）は不変のまま、宣言順序の入替え・
  # JSXコメント行の追加・`count + 1` のローカル変数への抽出だけを行う。行単位の位置が
  # 全体的にずれるため substantive_diff_lines は20行を超えるが、書式差を吸収する
  # style_normalized_diff_lines は20行以下に収まることを確認する。
  local c2_dir="$workdir/case2"
  mkdir -p "$c2_dir"
  cat > "$c2_dir/original.tsx" <<'EOF'
import React, { useState } from 'react';

export const MAX_COUNT = 10;
export const MIN_COUNT = 0;
export const STEP = 1;

export interface CardProps {
  id: string;
  label: string;
  tone: string;
}

export function CardFooter({ label }: CardProps) {
  return <span className="footer">{label}</span>;
}

export function UserCard({ id, label, tone }: CardProps) {
  const [count, setCount] = useState(0);

  const handleClick = () => {
    fetch("/api/users");
    setCount(count + 1);
  };

  return (
    <button onClick={handleClick} className="btn">
      {label}: {count}
    </button>
  );
}
EOF
  cat > "$c2_dir/generated.tsx" <<'EOF'
import React, { useState } from 'react';

export function UserCard({ id, label, tone }: CardProps) {
  const [count, setCount] = useState(0);

  const handleClick = () => {
    fetch("/api/users");
    const next = count + 1;
    setCount(next);
  };

  return (
    {/* ラベル表示 */}
    <button onClick={handleClick} className="btn">
      {/* カウント表示 */}
      {label}: {count}
    </button>
  );
}

export function CardFooter({ label }: CardProps) {
  {/* フッター見出し */}
  return <span className="footer">{label}</span>;
}

export interface CardProps {
  id: string;
  label: string;
  tone: string;
}

export const MAX_COUNT = 10;
export const MIN_COUNT = 0;
export const STEP = 1;
EOF

  local c2_out c2_verdict c2_substantive c2_normalized
  c2_out="$(main "$c2_dir/generated.tsx" "$c2_dir/original.tsx")"
  c2_verdict="$(printf '%s\n' "$c2_out" | sed -n 's/^verdict=//p')"
  c2_substantive="$(printf '%s\n' "$c2_out" | sed -n 's/^substantive_diff_lines=//p')"
  c2_normalized="$(printf '%s\n' "$c2_out" | sed -n 's/^style_normalized_diff_lines=//p')"
  if [ "$c2_verdict" = "PASS" ] && [ "$c2_substantive" -gt 20 ] && [ "$c2_normalized" -le 20 ]; then
    echo "ケース2(スタイル差のみ): PASS (verdict=${c2_verdict} substantive_diff_lines=${c2_substantive} style_normalized_diff_lines=${c2_normalized})"
  else
    echo "ケース2(スタイル差のみ): FAIL (期待 verdict=PASS かつ substantive>20 かつ normalized<=20 / 実測 verdict=${c2_verdict} substantive_diff_lines=${c2_substantive} style_normalized_diff_lines=${c2_normalized})"
    printf '%s\n' "$c2_out"
    fail=1
  fi

  # --- ケース3: 契約に現れない20文字超のロジック欠落 → FAIL ---
  # export/const/handler/type/state/apicall はすべて不変のまま、handleSelect 本体の
  # 中間計算（12行・計200文字超）を丸ごと削除する。契約突合には現れない実質的な
  # ロジック欠落であり、substantive_diff_lines・style_normalized_diff_lines のいずれも
  # 20行を超えることを確認する。
  local c3_dir="$workdir/case3"
  mkdir -p "$c3_dir"
  cat > "$c3_dir/original.tsx" <<'EOF'
import React, { useState } from 'react';

export const MAX_ITEMS = 5;

export function ItemList({ items }: ItemListProps) {
  const [selected, setSelected] = useState(0);

  const handleSelect = (idx) => {
    fetch("/api/items");
    const a1 = idx + 1;
    const a2 = idx + 2;
    const a3 = idx + 3;
    const a4 = idx + 4;
    const a5 = idx + 5;
    const a6 = idx + 6;
    const a7 = idx + 7;
    const a8 = idx + 8;
    const a9 = idx + 9;
    const a10 = idx + 10;
    const a11 = idx + 11;
    const a12 = idx + 12;
    const a13 = idx + 13;
    const a14 = idx + 14;
    const a15 = idx + 15;
    const a16 = idx + 16;
    const a17 = idx + 17;
    const a18 = idx + 18;
    const a19 = idx + 19;
    const a20 = idx + 20;
    const a21 = idx + 21;
    const a22 = idx + 22;
    const a23 = idx + 23;
    const a24 = idx + 24;
    const a25 = idx + 25;
    setSelected(idx);
  };

  return (
    <ul onClick={() => handleSelect(0)} className="list">
      {items.map((item) => (
        <li key={item.id}>{item.name}</li>
      ))}
    </ul>
  );
}
EOF
  cat > "$c3_dir/generated.tsx" <<'EOF'
import React, { useState } from 'react';

export const MAX_ITEMS = 5;

export function ItemList({ items }: ItemListProps) {
  const [selected, setSelected] = useState(0);

  const handleSelect = (idx) => {
    fetch("/api/items");
    setSelected(idx);
  };

  return (
    <ul onClick={() => handleSelect(0)} className="list">
      {items.map((item) => (
        <li key={item.id}>{item.name}</li>
      ))}
    </ul>
  );
}
EOF

  local c3_out c3_verdict c3_substantive c3_normalized c3_contract
  c3_out="$(main "$c3_dir/generated.tsx" "$c3_dir/original.tsx")"
  c3_verdict="$(printf '%s\n' "$c3_out" | sed -n 's/^verdict=//p')"
  c3_contract="$(printf '%s\n' "$c3_out" | sed -n 's/^contract_match=//p')"
  c3_substantive="$(printf '%s\n' "$c3_out" | sed -n 's/^substantive_diff_lines=//p')"
  c3_normalized="$(printf '%s\n' "$c3_out" | sed -n 's/^style_normalized_diff_lines=//p')"
  if [ "$c3_verdict" = "FAIL" ] && [ "$c3_contract" = "YES" ] && [ "$c3_substantive" -gt 20 ] && [ "$c3_normalized" -gt 20 ]; then
    echo "ケース3(契約に現れないロジック欠落): PASS (verdict=${c3_verdict} contract_match=${c3_contract} substantive_diff_lines=${c3_substantive} style_normalized_diff_lines=${c3_normalized})"
  else
    echo "ケース3(契約に現れないロジック欠落): FAIL (期待 verdict=FAIL かつ contract_match=YES かつ substantive>20 かつ normalized>20 / 実測 verdict=${c3_verdict} contract_match=${c3_contract} substantive_diff_lines=${c3_substantive} style_normalized_diff_lines=${c3_normalized})"
    printf '%s\n' "$c3_out"
    fail=1
  fi

  # --- ケース4: ハンドラ名不一致 → FAIL ---
  local c4_dir="$workdir/case4"
  mkdir -p "$c4_dir"
  cat > "$c4_dir/original.tsx" <<'EOF'
import React, { useState } from 'react';

export const MAX_COUNT = 10;

export function UserCard() {
  const [count, setCount] = useState(0);

  const handleClick = () => {
    fetch("/api/users");
    setCount(count + 1);
  };

  return (
    <button onClick={handleClick} className="btn">
      {count}
    </button>
  );
}
EOF
  cat > "$c4_dir/generated.tsx" <<'EOF'
import React, { useState } from 'react';

export const MAX_COUNT = 10;

export function UserCard() {
  const [count, setCount] = useState(0);

  const handleSubmit = () => {
    fetch("/api/users");
    setCount(count + 1);
  };

  return (
    <button onClick={handleSubmit} className="btn">
      {count}
    </button>
  );
}
EOF

  local c4_out c4_verdict c4_contract c4_handler
  c4_out="$(main "$c4_dir/generated.tsx" "$c4_dir/original.tsx")"
  c4_verdict="$(printf '%s\n' "$c4_out" | sed -n 's/^verdict=//p')"
  c4_contract="$(printf '%s\n' "$c4_out" | sed -n 's/^contract_match=//p')"
  c4_handler="$(printf '%s\n' "$c4_out" | sed -n 's/^handler_diff_lines=//p')"
  if [ "$c4_verdict" = "FAIL" ] && [ "$c4_contract" = "NO" ] && [ "$c4_handler" -ne 0 ]; then
    echo "ケース4(ハンドラ名不一致): PASS (verdict=${c4_verdict} contract_match=${c4_contract} handler_diff_lines=${c4_handler})"
  else
    echo "ケース4(ハンドラ名不一致): FAIL (期待 verdict=FAIL かつ contract_match=NO かつ handler_diff_lines!=0 / 実測 verdict=${c4_verdict} contract_match=${c4_contract} handler_diff_lines=${c4_handler})"
    printf '%s\n' "$c4_out"
    fail=1
  fi

  if [ "$fail" -eq 0 ]; then
    echo "self-test: 全4ケース PASS"
    return 0
  else
    echo "self-test: FAILあり"
    return 1
  fi
}

# --- 本体（通常モード: 2ファイル引数で計測結果を出力） ---
main() {
  if [ $# -ne 2 ]; then
    echo "使い方: $0 <generated-file> <original-file>" >&2
    exit 1
  fi

  local generated="$1"
  local original="$2"

  if [ ! -f "$generated" ]; then
    echo "エラー: 生成ファイルが存在しません: $generated" >&2
    exit 1
  fi
  if [ ! -f "$original" ]; then
    echo "エラー: 原本ファイルが存在しません: $original" >&2
    exit 1
  fi

  local import_diff_lines style_diff_lines export_diff_lines const_diff_lines
  local handler_diff_lines type_diff_lines state_diff_lines apicall_diff_lines
  local contract_match total_diff_lines substantive_diff_lines style_normalized_diff_lines
  local verdict

  import_diff_lines=$(diff <(extract_imports "$original") <(extract_imports "$generated") | grep -cE '^[<>]' || true)
  style_diff_lines=$(diff <(extract_style_lines "$original") <(extract_style_lines "$generated") | grep -cE '^[<>]' || true)
  export_diff_lines=$(diff <(extract_exports "$original") <(extract_exports "$generated") | grep -cE '^[<>]' || true)
  const_diff_lines=$(diff <(extract_consts "$original") <(extract_consts "$generated") | grep -cE '^[<>]' || true)
  handler_diff_lines=$(diff <(extract_handlers "$original") <(extract_handlers "$generated") | grep -cE '^[<>]' || true)
  type_diff_lines=$(diff <(extract_types "$original") <(extract_types "$generated") | grep -cE '^[<>]' || true)
  state_diff_lines=$(diff <(extract_state "$original") <(extract_state "$generated") | grep -cE '^[<>]' || true)
  apicall_diff_lines=$(diff <(extract_apicalls "$original") <(extract_apicalls "$generated") | grep -cE '^[<>]' || true)

  # --- contract match（6カテゴリ全て0か） ---
  if [ "$export_diff_lines" -eq 0 ] && [ "$const_diff_lines" -eq 0 ] && [ "$handler_diff_lines" -eq 0 ] \
    && [ "$type_diff_lines" -eq 0 ] && [ "$state_diff_lines" -eq 0 ] && [ "$apicall_diff_lines" -eq 0 ]; then
    contract_match="YES"
  else
    contract_match="NO"
  fi

  # --- total diff（参考値） ---
  total_diff_lines=$(diff "$original" "$generated" | grep -cE '^[<>]' || true)

  # --- substantive diff（コメント・空行除外。verdict判定に使用: 20行以下が条件の一つ） ---
  substantive_diff_lines=$(diff <(strip_noise "$original") <(strip_noise "$generated") | grep -cE '^[<>]' || true)

  # --- style normalized diff（書式差吸収。verdict判定に使用: 20行以下が条件の一つ） ---
  style_normalized_diff_lines=$(compute_style_normalized_diff "$original" "$generated")

  # --- verdict ---
  # contract_match（6カテゴリの識別子集合一致）は export/const/handler/type/state/apicall の
  # 宣言レベルの欠落だけを検出し、関数本体のロジック（条件分岐・算術式・JSX子要素の並び等）は
  # 対象外である。ロジック差分を見逃さないよう、実質diff（コメント・空行除外）またはスタイル
  # 正規化diff（書式差吸収）のいずれかが20行以下であることを判定条件として維持する
  # （契約突合の追加以前から存在する既知の限界はそのまま: 純粋な実装スタイル差は P7 で
  # 「実装スタイル差」クラスとして扱う）。
  if [ "$import_diff_lines" -eq 0 ] && [ "$style_diff_lines" -eq 0 ] && [ "$contract_match" = "YES" ] \
    && { [ "$substantive_diff_lines" -le 20 ] || [ "$style_normalized_diff_lines" -le 20 ]; }; then
    verdict="PASS"
  else
    verdict="FAIL"
  fi

  echo "import_diff_lines=$import_diff_lines"
  echo "style_diff_lines=$style_diff_lines"
  echo "export_diff_lines=$export_diff_lines"
  echo "const_diff_lines=$const_diff_lines"
  echo "handler_diff_lines=$handler_diff_lines"
  echo "type_diff_lines=$type_diff_lines"
  echo "state_diff_lines=$state_diff_lines"
  echo "apicall_diff_lines=$apicall_diff_lines"
  echo "contract_match=$contract_match"
  echo "total_diff_lines=$total_diff_lines"
  echo "substantive_diff_lines=$substantive_diff_lines"
  echo "style_normalized_diff_lines=$style_normalized_diff_lines"
  echo "verdict=$verdict"
}

if [ "${1:-}" = "--self-test" ]; then
  run_self_test
  exit $?
fi

main "$@"
