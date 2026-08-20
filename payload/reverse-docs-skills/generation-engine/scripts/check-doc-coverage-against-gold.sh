#!/usr/bin/env bash
set -euo pipefail

# check-doc-coverage-against-gold.sh — gold標準設計書のトークンを生成設計書に転記網羅しているか機械判定するカバレッジ検査
#
# 用途:
#   gold標準（正解セット）の設計書群から検証可能なトークンを抽出し、生成設計書がそれらを
#   どれだけ網羅しているか（転記網羅率）を機械判定する。backtest-facts-against-gold.sh が
#   「gold設計書→facts.yml」の抽出網羅を見るのに対し、本スクリプトは「gold設計書→生成設計書」の
#   転記網羅（カバレッジ率）を見る。トークン抽出ロジック（strip_noise / extract_line_tokens）は
#   backtest-facts-against-gold.sh と同一実装を本ファイル内にも複製している（共有する設計のため）。
#
# 使い方:
#   check-doc-coverage-against-gold.sh [--code-root <dir>] [--threshold <pct>] <生成設計書.md> <gold設計書.md> [<gold追加設計書.md> ...]
#   check-doc-coverage-against-gold.sh --self-test
#
# オプション:
#   --code-root <dir>   gold設計書から抽出した各トークンについて、まず <dir> 配下のソースファイル
#                        （*.ts / *.tsx）への実在を確認する。コードに実在しないトークン
#                        （DESIGN.md・SHA・DOM等の文書語彙ノイズ）は判定対象外としてスキップし、
#                        コードに実在するトークンだけをカバレッジの母数(total)に算入する
#   --threshold <pct>   合格とみなすカバレッジ閾値（既定 95）。coverage >= threshold で exit 0
#
# exit code:
#   0 = カバレッジ>=閾値
#   1 = 閾値未満
#   2 = 引数エラー
#
# 出力:
#   - stdout: 生成設計書に見つからなかった gold トークンを `<goldファイル名>:<行番号>\t<トークン>` で列挙
#   - stderr: `coverage=<pct> found=<F> total=<T>` のサマリ
#
# 保守責任者: 人手（ユーザー）。トークン抽出パターン・ノイズ除去ルールを変更した場合は
# backtest-facts-against-gold.sh の strip_noise / extract_line_tokens と self_test のフィクスチャを
# 同時に更新する。

strip_noise() {
  printf '%s' "$1" | sed -E \
    -e 's#[A-Za-z0-9_/.-]+\.(tsx?|md):[0-9]+# #g' \
    -e 's/§[0-9]+(\.[0-9]+)*/ /g' \
    -e 's/実測委譲/ /g' \
    -e 's/^#+[[:space:]]*//'\
    -e 's/^[0-9]+(\.[0-9]+)*[[:space:]]+//' \
    -e 's/[|]/ /g'
}

extract_line_tokens() {
  {
    printf '%s\n' "$1" | grep -oE "'[^']{1,60}'" 2>/dev/null || true
    printf '%s\n' "$1" | grep -oE '#[0-9a-fA-F]{3,6}' 2>/dev/null || true
    printf '%s\n' "$1" | grep -oE '[A-Za-z_$][A-Za-z0-9_$]*\.[A-Za-z_$][A-Za-z0-9_$]*' 2>/dev/null || true
    printf '%s\n' "$1" | grep -oE '[A-Z][A-Z0-9_]{2,}' 2>/dev/null || true
    printf '%s\n' "$1" | grep -oE '[a-z][A-Za-z0-9_$]*[A-Z][A-Za-z0-9_$]*' 2>/dev/null || true
    printf '%s\n' "$1" | grep -oE '[A-Z][A-Za-z0-9_$]{2,}' 2>/dev/null | grep -E '[a-z]' 2>/dev/null || true
  } | sort -u
}

token_in_code() {
  tok="$1"
  root="$2"
  if grep -rqF --include='*.ts' --include='*.tsx' -- "$tok" "$root" 2>/dev/null; then
    return 0
  fi
  case "$tok" in
    \'*\'*)
      inner="${tok#\'}"
      inner="${inner%\'}"
      if [ -n "$inner" ] && grep -rqF --include='*.ts' --include='*.tsx' -- "$inner" "$root" 2>/dev/null; then
        return 0
      fi
      ;;
  esac
  return 1
}

token_in_doc() {
  tok="$1"
  doc="$2"
  if grep -qF -- "$tok" "$doc" 2>/dev/null; then
    return 0
  fi
  case "$tok" in
    \'*\'*)
      inner="${tok#\'}"
      inner="${inner%\'}"
      if [ -n "$inner" ] && grep -qF -- "$inner" "$doc" 2>/dev/null; then
        return 0
      fi
      ;;
  esac
  return 1
}

run_coverage() {
  code_root="$1"
  target="$2"
  threshold="$3"
  shift 3
  found=0
  total=0

  for doc in "$@"; do
    docname="$(basename "$doc")"
    lineno=0
    excluded=0

    while IFS= read -r line || [ -n "$line" ]; do
      lineno=$((lineno + 1))

      if [ "$excluded" -eq 1 ]; then
        if [[ "$line" =~ ^##?[[:space:]] ]]; then
          excluded=0
        else
          continue
        fi
      fi

      if [[ "$line" =~ ^##?[[:space:]]+(章マップ|目次) ]]; then
        excluded=1
        continue
      fi

      work="$(strip_noise "$line")"

      case "$work" in
        *[!\ ]*) : ;;
        *) continue ;;
      esac
      if [[ "$work" =~ ^[[:space:]:\-]+$ ]]; then
        continue
      fi

      tokens="$(extract_line_tokens "$work")"
      [ -z "$tokens" ] && continue

      while IFS= read -r tok; do
        [ -z "$tok" ] && continue
        if [ -n "$code_root" ] && ! token_in_code "$tok" "$code_root"; then
          continue
        fi
        total=$((total + 1))
        if token_in_doc "$tok" "$target"; then
          found=$((found + 1))
        else
          printf '%s:%s\t%s\n' "$docname" "$lineno" "$tok"
        fi
      done < <(printf '%s\n' "$tokens")
    done < "$doc"
  done

  coverage="$(awk -v f="$found" -v t="$total" 'BEGIN{ if (t == 0) printf "%.1f", 100.0; else printf "%.1f", (f / t * 100) }')"
  echo "coverage=${coverage} found=${found} total=${total}" >&2

  if awk -v c="$coverage" -v th="$threshold" 'BEGIN{ exit !(c >= th) }'; then
    return 0
  fi
  return 1
}

main() {
  code_root=""
  threshold="95"

  while [ "$#" -gt 0 ]; do
    case "${1:-}" in
      --code-root)
        if [ "$#" -lt 2 ]; then
          echo "エラー: --code-root にディレクトリを指定してください" >&2
          return 2
        fi
        code_root="$2"
        shift 2
        if [ ! -d "$code_root" ]; then
          echo "エラー: --code-root のディレクトリが見つかりません: $code_root" >&2
          return 2
        fi
        ;;
      --threshold)
        if [ "$#" -lt 2 ]; then
          echo "エラー: --threshold にパーセント値を指定してください" >&2
          return 2
        fi
        threshold="$2"
        shift 2
        case "$threshold" in
          ''|*[!0-9.]*)
            echo "エラー: --threshold は数値で指定してください: $threshold" >&2
            return 2
            ;;
        esac
        ;;
      *)
        break
        ;;
    esac
  done

  target="$1"
  shift
  if [ "$#" -lt 1 ]; then
    echo "エラー: gold設計書を 1 つ以上指定してください（使い方: check-doc-coverage-against-gold.sh [--code-root <dir>] [--threshold <pct>] <生成設計書.md> <gold設計書.md> [...]）" >&2
    return 2
  fi

  for f in "$target" "$@"; do
    if [ ! -f "$f" ]; then
      echo "エラー: ファイルが見つかりません: $f" >&2
      return 2
    fi
  done

  rc=0
  run_coverage "$code_root" "$target" "$threshold" "$@" || rc=$?
  return "$rc"
}

self_test() {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-doc-coverage-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN
  rc_all=0

  # gold設計書（トークン4種: TOKENALPHA / TOKENBETA / TOKENGAMMA / TOKENDELTA）
  cat > "$tmp/gold.md" <<'MD'
# 画面詳細設計書
## 章マップ
| 役割 | § | 章名 |
|---|---|---|
| ZZZEXCLUDED | §1 | 概要 |
## §10 定数・設定値
TOKENALPHA と TOKENBETA を使用する。
TOKENGAMMA と TOKENDELTA も使用する。
MD

  # ケース1（陽性）: gold と同内容の生成設計書 → coverage=100.0・exit 0
  cp "$tmp/gold.md" "$tmp/gen_full.md"
  rc=0
  err1="$tmp/err1.txt"
  out="$(main "$tmp/gen_full.md" "$tmp/gold.md" 2>"$err1")" || rc=$?
  cov1="$(sed -nE 's/.*coverage=([0-9.]+).*/\1/p' "$err1")"
  if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$cov1" = "100.0" ]; then
    echo "  [PASS] ケース1 陽性: 全トークン網羅で coverage=100.0・exit 0・stdout空（章マップ除外も機能）"
  else
    echo "  [FAIL] ケース1 陽性: rc=$rc cov=$cov1 out=[$out]" >&2
    rc_all=1
  fi

  # ケース2（陰性）: GAMMA/DELTA を欠く → coverage<100 で exit 1・TSV 2行
  cat > "$tmp/gen_missing.md" <<'MD'
# 画面詳細設計書
## §10 定数・設定値
TOKENALPHA と TOKENBETA を使用する。
MD
  rc=0
  err2="$tmp/err2.txt"
  out="$(main --threshold 100 "$tmp/gen_missing.md" "$tmp/gold.md" 2>"$err2")" || rc=$?
  nlines="$(printf '%s\n' "$out" | grep -c . || true)"
  cov2="$(sed -nE 's/.*coverage=([0-9.]+).*/\1/p' "$err2")"
  has_gamma="$(printf '%s\n' "$out" | grep -cF 'TOKENGAMMA' || true)"
  has_delta="$(printf '%s\n' "$out" | grep -cF 'TOKENDELTA' || true)"
  if [ "$rc" -eq 1 ] && [ "$nlines" -eq 2 ] && [ "$cov2" = "50.0" ] \
    && [ "$has_gamma" -ge 1 ] && [ "$has_delta" -ge 1 ]; then
    echo "  [PASS] ケース2 陰性: coverage=50.0<100 で exit 1・TSV 2行（GAMMA/DELTA を未網羅報告）"
  else
    echo "  [FAIL] ケース2 陰性: rc=$rc cov=$cov2 nlines=$nlines gamma=$has_gamma delta=$has_delta" >&2
    rc_all=1
  fi

  # ケース3: 引数不足 → exit 2
  rc=0
  main "$tmp/gold.md" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 2 ]; then
    echo "  [PASS] ケース3 引数不足: exit 2"
  else
    echo "  [FAIL] ケース3 引数不足: rc=$rc (期待2) " >&2
    rc_all=1
  fi

  # ケース4（gold自己突合）
  rc=0
  err4="$tmp/err4.txt"
  out="$(main "$tmp/gold.md" "$tmp/gold.md" 2>"$err4")" || rc=$?
  cov4="$(sed -nE 's/.*coverage=([0-9.]+).*/\1/p' "$err4")"
  if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$cov4" = "100.0" ]; then
    echo "  [PASS] ケース4 gold自己突合: 第1=第2 で coverage=100.0・exit 0"
  else
    echo "  [FAIL] ケース4 gold自己突合: rc=$rc cov=$cov4 out=[$out]" >&2
    rc_all=1
  fi

  # ケース5（--code-root）: コード実在トークンだけを母数に算入
  mkdir -p "$tmp/code5/src"
  cat > "$tmp/code5/src/Sample.tsx" <<'TSX'
export const CODE_PRESENT_TOKEN = 1;
TSX
  cat > "$tmp/gold5.md" <<'MD'
# 画面詳細設計書
## §10 定数・設定値
CODE_PRESENT_TOKEN を使う。DocNoiseWord は文書語彙。
MD
  cat > "$tmp/gen5.md" <<'MD'
# 画面詳細設計書
## §10 定数・設定値
別の内容のみ記載。
MD
  rc=0
  err5="$tmp/err5.txt"
  out="$(main --code-root "$tmp/code5" "$tmp/gen5.md" "$tmp/gold5.md" 2>"$err5")" || rc=$?
  total5="$(sed -nE 's/.*total=([0-9]+).*/\1/p' "$err5")"
  has_present="$(printf '%s\n' "$out" | grep -cF 'CODE_PRESENT_TOKEN' || true)"
  has_noise="$(printf '%s\n' "$out" | grep -cF 'DocNoiseWord' || true)"
  if [ "$rc" -eq 1 ] && [ "${total5:-0}" -eq 1 ] && [ "$has_present" -ge 1 ] && [ "$has_noise" -eq 0 ]; then
    echo "  [PASS] ケース5 code-root: 母数=1（コード実在のみ）・CODE_PRESENT_TOKEN を未網羅報告・文書語彙は除外"
  else
    echo "  [FAIL] ケース5 code-root: rc=$rc total=$total5 present=$has_present noise=$has_noise" >&2
    rc_all=1
  fi

  if [ "$rc_all" -eq 0 ]; then
    echo "self-test 全ケース PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc_all"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

rc=0
main "$@" || rc=$?
exit "$rc"
