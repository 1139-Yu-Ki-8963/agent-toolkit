#!/usr/bin/env bash
set -euo pipefail

# backtest-facts-against-gold.sh — gold標準設計書のトークンを facts.yml に逆突合するカバレッジ検査
#
# 用途:
#   gold標準（正解セット）の設計書群から検証可能なトークンを抽出し、facts.yml の各キー・値が
#   それらをどれだけ網羅しているかを機械判定する。gold設計書のトークンが facts.yml 内に
#   1つも現れない場合、そのトークンは生成側で復元できていない（記載漏れ）ことを意味する。
#
# 使い方:
#   backtest-facts-against-gold.sh <facts.yml> <gold設計書.md> [<gold追加設計書.md> ...]
#   backtest-facts-against-gold.sh --self-test
#
# exit code:
#   0 = 全トークン網羅（カバレッジ100%）
#   1 = 未網羅トークンあり
#   2 = 引数エラー
#
# 出力:
#   - stdout: 未網羅トークンを `<goldファイル名>:<行番号>\t<トークン>` の TSV 形式で列挙
#   - stderr: `coverage=<pct> found=<F> total=<T>` のサマリ
#
# 保守責任者: 人手（ユーザー）。トークン抽出パターン・ノイズ除去ルールを変更した場合は
# self_test のフィクスチャも同時に更新する。

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

token_in_facts() {
  tok="$1"
  facts="$2"
  if grep -qF -- "$tok" "$facts" 2>/dev/null; then
    return 0
  fi
  case "$tok" in
    \'*\'*)
      inner="${tok#\'}"
      inner="${inner%\'}"
      if [ -n "$inner" ] && grep -qF -- "$inner" "$facts" 2>/dev/null; then
        return 0
      fi
      ;;
  esac
  return 1
}

run_backtest() {
  facts_yml="$1"
  shift
  found=0
  total=0

  for doc in "$@"; do
    docname="$(basename "$doc")"
    lineno=0
    excluded=0

    while IFS= read -r line || [ -n "$line" ]; do
      lineno=$((lineno + 1))

      # 除外ブロック（章マップ・目次）中は、次の h1/h2 見出しで除外を閉じる
      if [ "$excluded" -eq 1 ]; then
        if [[ "$line" =~ ^##?[[:space:]] ]]; then
          excluded=0
        else
          continue
        fi
      fi

      # 除外ブロックの開始（章マップ・目次見出し）。見出し行自体は採録しない
      if [[ "$line" =~ ^##?[[:space:]]+(章マップ|目次) ]]; then
        excluded=1
        continue
      fi

      work="$(strip_noise "$line")"

      # 空行・空白のみの行はスキップ
      case "$work" in
        *[!\ ]*) : ;;
        *) continue ;;
      esac
      # 表罫線の残骸（空白・コロン・ハイフンのみ）はスキップ
      if [[ "$work" =~ ^[[:space:]:\-]+$ ]]; then
        continue
      fi

      tokens="$(extract_line_tokens "$work")"
      [ -z "$tokens" ] && continue

      while IFS= read -r tok; do
        [ -z "$tok" ] && continue
        total=$((total + 1))
        if token_in_facts "$tok" "$facts_yml"; then
          found=$((found + 1))
        else
          printf '%s:%s\t%s\n' "$docname" "$lineno" "$tok"
        fi
      done < <(printf '%s\n' "$tokens")
    done < "$doc"
  done

  coverage="$(awk -v f="$found" -v t="$total" 'BEGIN{ if (t == 0) printf "%.1f", 100.0; else printf "%.1f", (f / t * 100) }')"
  echo "coverage=${coverage} found=${found} total=${total}" >&2

  if awk -v c="$coverage" 'BEGIN{ exit !(c >= 100.0) }'; then
    return 0
  fi
  return 1
}

main() {
  facts_yml="$1"
  shift

  if [ ! -f "$facts_yml" ]; then
    echo "エラー: ファイルが見つかりません: $facts_yml" >&2
    return 2
  fi
  if [ "$#" -eq 0 ]; then
    echo "エラー: 引数不足（gold設計書が最低1つ必要です）" >&2
    return 2
  fi
  for f in "$@"; do
    if [ ! -f "$f" ]; then
      echo "エラー: ファイルが見つかりません: $f" >&2
      return 2
    fi
  done

  rc=0
  run_backtest "$facts_yml" "$@" || rc=$?
  return "$rc"
}

self_test() {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/backtest-facts-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN
  rc_all=0

  # 共通の gold設計書（トークン4種: TOKENALPHA / TOKENBETA / TOKENGAMMA / TOKENDELTA）
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

  # facts.yml（全トークンを含む）
  cat > "$tmp/facts.yml" <<'YML'
run_id: extract-1
profile: screen
sections:
  const:
    reason: ""
    items:
      - key: const-MAX_ROWS-100
        value: "TOKENALPHA TOKENBETA TOKENGAMMA TOKENDELTA"
        evidence: "src/pages/x.tsx:5"
YML

  # ケース1（陽性）
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

  # ケース2（陰性）: GAMMA/DELTA を欠いた生成設計書
  cat > "$tmp/gen_missing.md" <<'MD'
# 画面詳細設計書
## §10 定数・設定値
TOKENALPHA と TOKENBETA を使用する。
MD
  rc=0
  err2="$tmp/err2.txt"
  out="$(main "$tmp/gen_missing.md" "$tmp/gold.md" 2>"$err2")" || rc=$?
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

  # ケース4（gold自己突合）: 第1引数=第2引数
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

if [ "$#" -lt 2 ]; then
  echo "エラー: 引数不足（使い方: backtest-facts-against-gold.sh <facts.yml> <gold設計書.md> [...]）" >&2
  exit 2
fi

rc=0
main "$@" || rc=$?
exit "$rc"
