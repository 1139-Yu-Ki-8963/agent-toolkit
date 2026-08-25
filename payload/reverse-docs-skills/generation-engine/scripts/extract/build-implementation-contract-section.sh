#!/usr/bin/env bash
# 抽出エンジン(generation-engine/scripts/extract): 原本コードから「実装契約」の節
# (関数1本ごとの引数と戻り値の契約)を組み立てる。接続窓口(API等)の一覧マニフェストの
# units[].sourceFile が指す実装ファイル(モジュール)を原本コードから走査し、抽出できた
# フィールドだけを units[] の各要素へ implementationContract として追加した拡張マニフェスト
# を出力する(既存の extract-api-metadata.sh 等と同じ「入力の既存フィールドは変更せず、
# 検出できた分だけ追記する」契約)。台帳1-259。
#
# Usage: build-implementation-contract-section.sh <manifest.json> <source-dir> <output.json>
#            [--naming-convention <path>] [--threshold <0-100>]
#        build-implementation-contract-section.sh --self-test
#
# 入力契約:
#   <manifest.json>      : units[].sourceFile を持つユニットマニフェスト(unitKind=api を想定するが
#                           sourceFile を持つ他種別でも動く)。kind=unresolved の要素は対象外
#   <source-dir>          : 原本コードのルート。sourceFile が相対パスの場合はここを起点に解決する
#   --naming-convention   : 接頭辞と型の対応表(JSON。{"prefixes":{"href_":"ハッシュ参照",...}})。
#                           変数名からシジル($/@/%)を除いた文字列の接頭辞と前方一致するものを
#                           採用する(最長一致優先)。省略時・不一致時は全て「判定不能」とし、
#                           推測しない
#   --threshold            : 抽出できた割合の警告閾値(0-100の整数パーセント。既定80)
#
# 抽出する3項目(台帳1-259「やること」2):
#   1. モジュール(ファイル)ごとのサブルーチンの一覧 — 名前・公開の可否・引数の数・戻り値の要約
#   2. 関数ごとの引数の表 — 位置・名前・型・NULL許容・初期値・導出
#   3. 戻り値 — return文から集めた式の一覧と要約
#
# 対象言語: Perl のみ(既知の限界)。台帳の実測がPerl(`my (...) = @_`・`my $x = shift`という
#   Perlの慣用句)を根拠にしているため、本抽出処理もPerlの2大慣用句だけを対象にする。他言語の
#   引数取得記法(分割代入・デフォルト引数等)は本版の対象外であり、該当ファイルは全関数が
#   「読めなかった」扱いになる(推測で埋めない)。
#
# 引数取得パターン(いずれもsub本文の先頭付近だけを走査する。台帳「やること」4):
#   A. 分解代入: `my ($a, $b, ...) = @_;` — かっこ内をカンマ分割し、位置1から順に割り当てる
#   B. 逐次shift: sub本文の先頭から連続する `my $x = shift ...;` の並び。`shift // 既定値` /
#      `shift || 既定値` の形が続く場合は、その既定値をNULL許容="可"・初期値として記録する
#   どちらにも一致しないコード行に最初に出会った時点で走査を打ち切り、その関数は「引数の取得
#   パターンを検出できませんでした」として引数欄を空にする(推測しない)。空行・コメント行
#   (行頭が#)・開き/閉じかっこのみの行は判定を打ち切らずスキップする
#
# 戻り値の抽出: sub本文全体から `return` 文(前後が識別子文字でない出現に限る。identBoundary判定
#   でreturnValueのような識別子の一部を誤検出しない)を探し、`return;`(値なし)は「undef(値なし
#   のreturn)」、`return EXPR;` は EXPR(末尾セミコロンを除去)を記録する。同じ式は1回だけ数える。
#   return文が1つも見つからない場合は「読めなかった」扱いにする(戻り値なしの関数と、書き方が
#   読めなかった関数を区別しない。実装読解の対象外)
#
# 型の導出: --naming-convention の prefixes を、変数名からシジルを除いた文字列への前方一致で
#   最長一致優先に適用する。--naming-convention 省略時、または一致する接頭辞が無い場合は
#   すべて「判定不能」とする(台帳「やること」3: 規約を持たないプロジェクトでは判定不能)
#
# 抽出できた割合の報告: 出力マニフェストの detectionSummary.diagnostics.implementationContract に
#   readableArguments / readableReturns の count・total・ratio・thresholdPercent・warning を記録する。
#   warning は ratio*100 が --threshold(既定80)を下回った場合に true(台帳「やること」5)。
#   他の抽出処理の diagnostics(definitionWithoutImplementation 等)は「ratio > threshold で警告」
#   (問題の割合が高いほど警告)だが、本フィールドは「readableの割合がthresholdを下回ると警告」
#   (読み取れた割合が低いほど警告)であり極性が逆になる。名前(readableArguments/readableReturns)
#   で意味を明示することで、既存 diagnostics の極性(count=問題件数)と混同しないようにしている
#
# ブレース深さの追跡(実装判断): サブルーチン本体の終端検出は、行ごとに"{"と"}"の出現数を数える
#   単純なヒューリスティックで行う(文字列・正規表現リテラル中の"{"/"}"は区別しない。既知の限界)。
#   行頭が"#"の行(行全体コメント)は深さ計算から除外するが、コード行の末尾に続くインラインコメント
#   中の"{"/"}"は区別できない(同上)。この単純化は generation-engine/scripts/extract/
#   extract-table-metadata.sh の sql_code_only と同種の「文字列・コメントを厳密には字句解析しない」
#   トレードオフであり、対象コードがこの単純化を破る書き方(文字列内に不釣り合いな中かっこを含む等)
#   をしている場合、当該サブルーチンの終端検出がずれる可能性がある
#
# --argjson を使わない理由(実装判断): generation-engine/scripts/tests/check-argjson-unbounded-value.sh
#   が本ディレクトリ配下の新規 `jq --argjson` 使用を許可リスト方式(default-deny)で検査する
#   (改善課題1-52の再発防止)。本スクリプトは可変長になりうる値(抽出したレコード全体・命名規約
#   定義)を一時ファイル経由の `--slurpfile` で渡し、固定長のスカラー値(閾値)も `--arg` +
#   `tonumber` で渡すことで、`--argjson` そのものを使わない設計にした(許可リストへの新規登録が
#   不要になる)
#
# POSIX awk 互換性(実装判断): macOS標準awk(One True Awk)は `match(s, r, arr)` という3引数形式
#   (gawk拡張)を持たない。本スクリプトの awk はすべて2引数の `match()` + `RSTART`/`RLENGTH` +
#   `substr()` の組み合わせだけでキャプチャ相当の抽出を行う(generation-engine/scripts/extract/
#   extract-table-metadata.sh の sql_code_only と同じ制約下の実装方針)
#
# 出力契約:
#   <output.json> に、units[] の各要素へ implementationContract(sourceFile・subroutines[]・
#   functions[])を追加した拡張マニフェストを書き出す。sourceFile が原本コード上に見つからない、
#   またはサブルーチンを1本も検出できなかったユニットには implementationContract を付けない
#   (根拠が無い場合は欠落させるfail-safe。既存フィールドは変更しない)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# --- awk本体: 1モジュール(1ファイル)を走査し、US(\x1f)区切りのFUNC/ARGレコードを標準出力へ書く ---
# 引数: $1=走査対象の絶対パス $2=modfile(出力へ埋め込むsourceFileラベル。マニフェスト記載値のまま)
extract_module_records() {
  local abs_path="$1" modfile="$2"
  awk -v modfile="$modfile" -v US="$US_SEP" -v RSJ="$RS_SEP" '
    function ltrim(s) { sub(/^[ \t]+/, "", s); return s }
    function rtrim(s) { sub(/[ \t]+$/, "", s); return s }
    function trim(s)  { return rtrim(ltrim(s)) }
    function count_open(s,    t, c)  { t = s; c = gsub(/\{/, "", t); return c }
    function count_close(s,    t, c) { t = s; c = gsub(/\}/, "", t); return c }

    BEGIN {
      in_sub = 0
      depth = 0
      fidx = 0
    }

    {
      line = $0
      trimmed = trim(line)

      if (!in_sub) {
        if (match(line, /^[ \t]*sub[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
          seg = trim(substr(line, RSTART, RLENGTH))
          n = split(seg, parts, /[ \t]+/)
          name = parts[n]
          fidx++
          in_sub = 1
          args_locked = 0
          args_found = 0
          arg_count = 0
          arg_derivation = ""
          shift_chain = 0
          lookahead = 0
          ret_found = 0
          ret_count = 0
          delete ret_seen
          delete ret_list
          ret_list_n = 0
          opens = count_open(line)
          closes = count_close(line)
          depth = opens - closes
          if (depth <= 0) {
            # "{" がまだ現れていない(次行以降に開きかっこがある記法)。depth=0のまま継続
            depth = 0
          }
        }
        next
      }

      # --- in_sub == 1: 本文走査 ---
      is_line_comment = (trimmed ~ /^#/)
      if (is_line_comment) {
        opens = 0
        closes = 0
      } else {
        opens = count_open(line)
        closes = count_close(line)
      }
      depth += (opens - closes)

      is_only_braces = (trimmed ~ /^[{}]+$/)
      is_blank_or_comment = (trimmed == "" || is_line_comment || is_only_braces)

      if (!args_locked && !is_blank_or_comment) {
        if (!args_found && match(trimmed, /^my[ \t]*\([^)]*\)[ \t]*=[ \t]*@_/)) {
          seg = substr(trimmed, RSTART, RLENGTH)
          p1 = index(seg, "(")
          p2 = index(seg, ")")
          inner = substr(seg, p1 + 1, p2 - p1 - 1)
          ncount = split(inner, argnames, ",")
          emitted = 0
          for (i = 1; i <= ncount; i++) {
            an = trim(argnames[i])
            if (an == "") continue
            emitted++
            print "ARG" US modfile US fidx US emitted US an US "不明" US ""
          }
          arg_count = emitted
          args_found = 1
          arg_derivation = "分解代入"
          args_locked = 1
        } else if (match(trimmed, /^my[ \t]+\$[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*shift/)) {
          seg = substr(trimmed, RSTART, RLENGTH)
          dollar_pos = index(seg, "$")
          rest = substr(seg, dollar_pos + 1)
          varname = rest
          sub(/[^A-Za-z0-9_].*$/, "", varname)
          after = trimmed
          sub(/^.*shift/, "", after)
          after = trim(after)
          nullable = "不明"
          defv = ""
          if (match(after, /^(\/\/|\|\|)/)) {
            oplen = RLENGTH
            rem = trim(substr(after, RSTART + oplen))
            sub(/;[ \t]*$/, "", rem)
            defv = trim(rem)
            nullable = "可"
          }
          shift_chain++
          print "ARG" US modfile US fidx US shift_chain US ("$" varname) US nullable US defv
          arg_count = shift_chain
          args_found = 1
          arg_derivation = "shift"
        } else {
          args_locked = 1
        }
        lookahead++
        if (lookahead >= 12) args_locked = 1
      }

      if (!is_blank_or_comment) {
        padded = " " line " "
        if (match(padded, /[^A-Za-z0-9_]return([^A-Za-z0-9_]|$)/)) {
          hitstart = RSTART
          hitlen = RLENGTH
          kwpos = index(substr(padded, hitstart), "return")
          exprstart = hitstart + kwpos - 1 + 6
          expr = trim(substr(padded, exprstart))
          sub(/;[ \t]*$/, "", expr)
          expr = trim(expr)
          ret_found = 1
          ret_count++
          if (expr == "") {
            key = "@@EMPTY@@"
            label = "undef(値なしのreturn)"
          } else {
            key = expr
            label = expr
          }
          if (!(key in ret_seen)) {
            ret_seen[key] = 1
            ret_list_n++
            ret_list[ret_list_n] = label
          }
        }
      }

      if (depth <= 0) {
        visibility = (substr(name, 1, 1) == "_") ? "非公開" : "公開"
        readable_args = args_found ? 1 : 0
        args_reason = args_found ? "" : "引数の取得パターン(分解代入またはshift)を検出できませんでした"
        readable_ret = ret_found ? 1 : 0
        ret_reason = ret_found ? "" : "return文が見つかりませんでした"
        retjoined = ""
        for (i = 1; i <= ret_list_n; i++) {
          retjoined = (i == 1) ? ret_list[i] : retjoined RSJ ret_list[i]
        }
        print "FUNC" US modfile US fidx US name US visibility US readable_args US args_reason US arg_derivation US arg_count US readable_ret US ret_reason US retjoined
        in_sub = 0
      }
    }
  ' "$abs_path"
}

# --- --self-test モード ---
self_test() {
  local script_path="$0"
  local script_dir
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  local rc=0
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/build-impl-contract-self-test.XXXXXX" 2>/dev/null)" || {
    echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません(mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります)" >&2
    return 2
  }
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/src/lib"

  # 1本のモジュールに4関数(分解代入・shift+デフォルト・引数取得パターン不一致・return文なし)
  cat > "$tmp/src/lib/Sample.pm" <<'EOF'
package Sample;

# 分解代入の形。href_opts は naming-convention でハッシュ参照と判定できる
sub pub_decomp {
    my ($user_id, $href_opts) = @_;
    my $status = $href_opts->{status};
    if ($status) {
        return $status;
    }
    return $status;
}

# 逐次shiftの形。非公開(先頭アンダースコア)。flagは // でデフォルト値を持つ
sub _priv_shift {
    my $aref_list = shift;
    my $flag = shift // 0;
    for my $item (@$aref_list) {
        print $item;
    }
    return;
}

# 引数取得パターンに一致しない(推測せず「読めなかった」扱いにする)
sub unreadable_args {
    do_something(@_);
    print "no explicit my-capture here\n";
    return 1;
}

# 引数は読めるが return文が無い(戻り値は「読めなかった」扱い)
sub no_return_func {
    my ($x) = @_;
    print $x;
}
EOF

  local naming_conv="$tmp/naming.json"
  cat > "$naming_conv" <<'EOF'
{"prefixes": {"href_": "ハッシュ参照", "aref_": "配列参照"}}
EOF

  local manifest="$tmp/api-manifest.json"
  jq -n --arg sourceFile "lib/Sample.pm" '{
    generatedAt: "2026-01-01T00:00:00Z",
    sourceDir: "unused",
    unitKind: "api",
    strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
    detectionSummary: {unitCount: 2, unresolvedCount: 0},
    units: [
      {unitKey: "sample-list", kind: "endpoint", identifier: "GET /api/sample",
       unitNameGuess: "サンプル一覧取得", sourceFile: $sourceFile,
       confidence: "high", fileCount: 1, detectionMethod: "manual"},
      {unitKey: "sample-create", kind: "endpoint", identifier: "POST /api/sample",
       unitNameGuess: "サンプル作成", sourceFile: $sourceFile,
       confidence: "high", fileCount: 1, detectionMethod: "manual"},
      {unitKey: "sample-unresolved", kind: "unresolved", identifier: "未確認",
       unitNameGuess: "未確認", sourceFile: "未確認",
       confidence: "low", fileCount: null, detectionMethod: "未確認"}
    ]
  }' > "$manifest"

  # --- 1: 命名規約ありで実行し、様式どおりの表構造・型導出を検証する ---
  local out_with_conv="$tmp/out-with-conv.json"
  if ! bash "$script_path" "$manifest" "$tmp/src" "$out_with_conv" --naming-convention "$naming_conv" > "$tmp/run1.log" 2>&1; then
    echo "  [FAIL] 命名規約ありの実行が失敗した" >&2
    sed 's/^/    /' "$tmp/run1.log" >&2
    rc=1
  else
    if ! jq -e '.units[0].implementationContract.subroutines | length == 4' "$out_with_conv" >/dev/null; then
      echo "  [FAIL] subroutines が4件でない" >&2
      rc=1
    else
      echo "  [PASS] subroutines: モジュール内4関数を検出"
    fi

    if ! jq -e '.units[0].implementationContract.subroutines[] | select(.name=="_priv_shift") | .visibility == "非公開"' "$out_with_conv" >/dev/null; then
      echo "  [FAIL] _priv_shift の visibility が非公開でない" >&2
      rc=1
    else
      echo "  [PASS] visibility: 先頭アンダースコアを非公開と判定"
    fi

    if ! jq -e '
      [.units[0].implementationContract.functions[] | select(.name=="pub_decomp")][0] as $f
      | ($f.arguments | length == 2)
        and ($f.arguments[0].position == 1) and ($f.arguments[0].name == "$user_id")
        and ($f.arguments[0].type == "判定不能")
        and ($f.arguments[1].name == "$href_opts") and ($f.arguments[1].type == "ハッシュ参照")
        and ($f.arguments[1].derivation == "分解代入")
    ' "$out_with_conv" >/dev/null; then
      echo "  [FAIL] pub_decomp の分解代入引数の表が様式どおりでない" >&2
      rc=1
    else
      echo "  [PASS] 分解代入(my (...) = @_)の引数表・型導出が様式どおり"
    fi

    if ! jq -e '
      [.units[0].implementationContract.functions[] | select(.name=="_priv_shift")][0] as $f
      | ($f.arguments | length == 2)
        and ($f.arguments[0].name == "$aref_list") and ($f.arguments[0].type == "配列参照")
        and ($f.arguments[0].derivation == "shift")
        and ($f.arguments[1].name == "$flag") and ($f.arguments[1].nullable == "可")
        and ($f.arguments[1].default == "0")
    ' "$out_with_conv" >/dev/null; then
      echo "  [FAIL] _priv_shift の逐次shift引数の表が様式どおりでない" >&2
      rc=1
    else
      echo "  [PASS] 逐次shift(my \$x = shift)の引数表・デフォルト値検出が様式どおり"
    fi

    if ! jq -e '
      [.units[0].implementationContract.functions[] | select(.name=="pub_decomp")][0].returnValue
      | .readable == true and (.expressions | length == 1) and (.expressions[0] == "$status")
    ' "$out_with_conv" >/dev/null; then
      echo "  [FAIL] pub_decomp の戻り値(重複returnの重複排除を含む)が様式どおりでない" >&2
      rc=1
    else
      echo "  [PASS] 戻り値: 同じ式のreturnを重複排除して1件に集約"
    fi

    # --- 2: 引数の取得パターンが読めない関数は欄が空になり、読めなかった旨が記録される ---
    if ! jq -e '
      [.units[0].implementationContract.functions[] | select(.name=="unreadable_args")][0] as $f
      | ($f.readableArguments == false)
        and ($f.arguments == [])
        and ($f.argsUnreadableReason | length > 0)
    ' "$out_with_conv" >/dev/null; then
      echo "  [FAIL] 引数取得パターン不一致の関数が「読めなかった」として記録されていない" >&2
      rc=1
    else
      echo "  [PASS] 読めない引数: 欄が空になり理由が記録される"
    fi

    if ! jq -e '
      [.units[0].implementationContract.functions[] | select(.name=="no_return_func")][0].returnValue
      | (.readable == false) and (.unreadableReason | length > 0) and (.expressions == [])
    ' "$out_with_conv" >/dev/null; then
      echo "  [FAIL] return文が無い関数が「読めなかった」として記録されていない" >&2
      rc=1
    else
      echo "  [PASS] 読めない戻り値: return文が無い関数は理由が記録される"
    fi

    # --- unresolved ユニットには implementationContract を付けない ---
    if ! jq -e '.units[2].implementationContract == null' "$out_with_conv" >/dev/null; then
      echo "  [FAIL] kind=unresolved のユニットに implementationContract が付いてしまった" >&2
      rc=1
    else
      echo "  [PASS] kind=unresolved は対象外のまま(implementationContract を付けない)"
    fi

    # --- 抽出できた割合の報告 ---
    if ! jq -e '
      .detectionSummary.diagnostics.implementationContract as $s
      | $s.totalFunctions == 4
        and $s.readableArguments.count == 3 and $s.readableArguments.total == 4
        and $s.readableArguments.thresholdPercent == 80
        and $s.readableArguments.warning == true
        and $s.readableReturns.count == 3 and $s.readableReturns.total == 4
        and $s.readableReturns.warning == true
    ' "$out_with_conv" >/dev/null; then
      echo "  [FAIL] extractionSummary(抽出できた割合)の内容が期待どおりでない" >&2
      jq '.detectionSummary.diagnostics.implementationContract' "$out_with_conv" >&2 || true
      rc=1
    else
      echo "  [PASS] 抽出できた割合(readableArguments/readableReturns)が実行結果へ報告される(75%<80%で警告)"
    fi
  fi

  # --- 3: 命名規約なしで実行し、規約を持たないプロジェクトでは型がすべて「判定不能」になる ---
  local out_without_conv="$tmp/out-without-conv.json"
  if ! bash "$script_path" "$manifest" "$tmp/src" "$out_without_conv" > "$tmp/run2.log" 2>&1; then
    echo "  [FAIL] 命名規約なしの実行が失敗した" >&2
    sed 's/^/    /' "$tmp/run2.log" >&2
    rc=1
  else
    if ! jq -e '
      [.units[0].implementationContract.functions[] | select(.name=="pub_decomp")][0].arguments
      | all(.type == "判定不能")
    ' "$out_without_conv" >/dev/null; then
      echo "  [FAIL] 命名規約なしなのに型が判定不能以外になった" >&2
      rc=1
    else
      echo "  [PASS] 命名規約なし: 型がすべて「判定不能」になる"
    fi
  fi

  # --- 閾値を明示的に下げると warning が false になることの確認 ---
  local out_lowthresh="$tmp/out-lowthresh.json"
  if ! bash "$script_path" "$manifest" "$tmp/src" "$out_lowthresh" --threshold 50 > "$tmp/run3.log" 2>&1; then
    echo "  [FAIL] --threshold 指定の実行が失敗した" >&2
    sed 's/^/    /' "$tmp/run3.log" >&2
    rc=1
  else
    if ! jq -e '
      .detectionSummary.diagnostics.implementationContract
      | .readableArguments.warning == false and .readableReturns.warning == false
        and .readableArguments.thresholdPercent == 50
    ' "$out_lowthresh" >/dev/null; then
      echo "  [FAIL] --threshold 50 指定時に warning が false にならない" >&2
      rc=1
    else
      echo "  [PASS] --threshold 指定で警告閾値が変わる(75%>=50%で警告なし)"
    fi
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

US_SEP="$(printf '\x1f')"
RS_SEP="$(printf '\x1e')"

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

USAGE="Usage: build-implementation-contract-section.sh <manifest.json> <source-dir> <output.json> [--naming-convention <path>] [--threshold <0-100>]"
MANIFEST="${1:?$USAGE}"
SOURCE_DIR="${2:?$USAGE}"
OUTPUT_JSON="${3:?$USAGE}"
shift 3

NAMING_CONVENTION=""
THRESHOLD=80
while [ $# -gt 0 ]; do
  case "$1" in
    --naming-convention) NAMING_CONVENTION="${2:-}"; shift 2 ;;
    --threshold) THRESHOLD="${2:-80}"; shift 2 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found in PATH" >&2
  exit 1
fi
if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: manifest not found: $MANIFEST" >&2
  exit 1
fi
if ! jq empty "$MANIFEST" >/dev/null 2>&1; then
  echo "ERROR: invalid JSON: $MANIFEST" >&2
  exit 1
fi
if [ ! -d "$SOURCE_DIR" ]; then
  echo "ERROR: source-dir not found: $SOURCE_DIR" >&2
  exit 1
fi
case "$THRESHOLD" in
  ''|*[!0-9]*) echo "ERROR: --threshold は0-100の整数で指定してください: $THRESHOLD" >&2; exit 1 ;;
esac
if [ -n "$NAMING_CONVENTION" ]; then
  if [ ! -f "$NAMING_CONVENTION" ]; then
    echo "ERROR: naming-convention file not found: $NAMING_CONVENTION" >&2
    exit 1
  fi
  if ! jq empty "$NAMING_CONVENTION" >/dev/null 2>&1; then
    echo "ERROR: invalid JSON: $NAMING_CONVENTION" >&2
    exit 1
  fi
fi

resolve_path() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    *) printf '%s' "${SOURCE_DIR%/}/$1" ;;
  esac
}

mkdir -p "$(dirname "$OUTPUT_JSON")"

records_tmp="$(mktemp "${TMPDIR:-/tmp}/build-impl-contract-records.XXXXXX" 2>/dev/null)" || {
  echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません(mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります)" >&2
  exit 2
}
records_json_tmp="$(mktemp "${TMPDIR:-/tmp}/build-impl-contract-records-json.XXXXXX" 2>/dev/null)" || {
  echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません(mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります)" >&2
  rm -f "$records_tmp"
  exit 2
}
naming_json_tmp="$(mktemp "${TMPDIR:-/tmp}/build-impl-contract-naming.XXXXXX" 2>/dev/null)" || {
  echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません(mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります)" >&2
  rm -f "$records_tmp" "$records_json_tmp"
  exit 2
}
jq_file_tmp="$(mktemp "${TMPDIR:-/tmp}/build-impl-contract.XXXXXX.jq" 2>/dev/null)" || {
  echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません(mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります)" >&2
  rm -f "$records_tmp" "$records_json_tmp" "$naming_json_tmp"
  exit 2
}
trap 'rm -f "$records_tmp" "$records_json_tmp" "$naming_json_tmp" "$jq_file_tmp"' EXIT

if [ -n "$NAMING_CONVENTION" ]; then
  cp "$NAMING_CONVENTION" "$naming_json_tmp"
else
  printf '{}' > "$naming_json_tmp"
fi

: > "$records_tmp"
while IFS= read -r src; do
  [ -z "$src" ] && continue
  abs="$(resolve_path "$src")"
  if [ ! -f "$abs" ]; then
    echo "WARN: source file not found, skipped: $src" >&2
    continue
  fi
  extract_module_records "$abs" "$src" >> "$records_tmp"
done < <(jq -r '.units[]? | select((.kind // "") != "unresolved") | .sourceFile // empty' "$MANIFEST" | sort -u)

jq -R -s --arg US "$US_SEP" --arg RSJ "$RS_SEP" '
  split("\n") | map(select(length > 0)) | map(split($US))
  | map(
      if .[0] == "FUNC" then
        {
          type: "FUNC",
          sourceFile: .[1],
          fidx: (.[2] | tonumber),
          name: .[3],
          visibility: .[4],
          readableArgs: (.[5] == "1"),
          argsReason: .[6],
          derivation: .[7],
          argCount: (.[8] | tonumber),
          readableReturn: (.[9] == "1"),
          returnReason: .[10],
          returnExpressions: ((.[11] // "") as $j | if ($j | length) > 0 then ($j | split($RSJ)) else [] end)
        }
      elif .[0] == "ARG" then
        {
          type: "ARG",
          sourceFile: .[1],
          fidx: (.[2] | tonumber),
          position: (.[3] | tonumber),
          rawName: .[4],
          nullable: .[5],
          default: .[6]
        }
      else
        empty
      end
    )
' "$records_tmp" > "$records_json_tmp"

cat > "$jq_file_tmp" <<'JQ'
def stripSigil(n): (n | if test("^[\\$@%]") then .[1:] else . end);
def deriveType(n; $pm):
  if ($pm | length) == 0 then
    "判定不能"
  else
    (stripSigil(n)) as $stripped
    | ($pm | keys | map(select(. as $p | $stripped | startswith($p))) | sort_by(-(length))) as $matched
    | if ($matched | length) == 0 then "判定不能" else $pm[$matched[0]] end
  end;

($records[0]) as $records
| ($naming[0].prefixes // {}) as $pm
| ($thresholdPercent | tonumber) as $thresholdPercent
| ($records | map(select(.type == "FUNC"))) as $funcs
| ($records | map(select(.type == "ARG"))) as $args
| ($funcs | map(
    . as $f
    | ($args | map(select(.sourceFile == $f.sourceFile and .fidx == $f.fidx)) | sort_by(.position)
        | map({
            position: .position,
            name: .rawName,
            type: deriveType(.rawName; $pm),
            nullable: .nullable,
            default: (if .default == "" then null else .default end),
            derivation: $f.derivation
          })
      ) as $argRows
    | {
        sourceFile: $f.sourceFile,
        name: $f.name,
        visibility: $f.visibility,
        readableArguments: $f.readableArgs,
        argsUnreadableReason: (if $f.readableArgs then null else $f.argsReason end),
        arguments: $argRows,
        returnValue: {
          readable: $f.readableReturn,
          unreadableReason: (if $f.readableReturn then null else $f.returnReason end),
          summary: (if ($f.returnExpressions | length) > 0 then ($f.returnExpressions | join("; ")) else null end),
          expressions: $f.returnExpressions
        }
      }
  )) as $functionRows
| ($functionRows | group_by(.sourceFile) | map({
      sourceFile: .[0].sourceFile,
      subroutines: map({name: .name, visibility: .visibility, argCount: (.arguments | length), returnSummary: (.returnValue.summary // "(読み取れませんでした)")}),
      functions: map(del(.sourceFile))
    })) as $modules
| ($functionRows | length) as $total
| ($functionRows | map(select(.readableArguments)) | length) as $argOk
| ($functionRows | map(select(.returnValue.readable)) | length) as $retOk
| (if $total > 0 then ($argOk / $total) else 1 end) as $argRatio
| (if $total > 0 then ($retOk / $total) else 1 end) as $retRatio
| {
    totalFunctions: $total,
    readableArguments: {
      count: $argOk, total: $total, ratio: $argRatio, thresholdPercent: $thresholdPercent,
      warning: (if $total > 0 then (($argRatio * 100) < $thresholdPercent) else false end)
    },
    readableReturns: {
      count: $retOk, total: $total, ratio: $retRatio, thresholdPercent: $thresholdPercent,
      warning: (if $total > 0 then (($retRatio * 100) < $thresholdPercent) else false end)
    }
  } as $summary
| .units = ((.units // []) | map(
    if ((.kind // "") == "unresolved") then
      .
    else
      (.sourceFile // "") as $sf
      | ($modules | map(select(.sourceFile == $sf)) | .[0]) as $mod
      | if $mod == null then
          .
        else
          . + {implementationContract: {sourceFile: $mod.sourceFile, subroutines: $mod.subroutines, functions: $mod.functions}}
        end
    end
  ))
| .detectionSummary.diagnostics = ((.detectionSummary.diagnostics // {}) + {implementationContract: $summary})
JQ

jq --slurpfile records "$records_json_tmp" --slurpfile naming "$naming_json_tmp" --arg thresholdPercent "$THRESHOLD" -f "$jq_file_tmp" "$MANIFEST" > "$OUTPUT_JSON"

echo "OK: wrote $OUTPUT_JSON" >&2
