#!/usr/bin/env bash
set -uo pipefail

# check-internal-jargon.sh — この場所でしか通じない言葉をスキル定義とガイドから走査する
#
# 目的:
#   .claude/skills/*/SKILL.md と .claude/skills/*/references/guide.html は
#   納品先の AI エージェント・エンジニアが読む。この場所でしか通じない言葉
#   （delivery-payload/references/rule-banned-terms.json の scope に "skills"
#   を含む語）が残っていないかを機械的に検査する。
#
#   規約定義（rule.md・rule.html）向けの既存の走査（scaffold-rule-definitions.sh
#   の scan_banned_terms、scope="rule-definitions"）とは対象ファイル・scope が
#   異なるため独立したスクリプトとした（.claude/rules/scoped/portal/
#   page-conventions/rule.md の「設計判断」節を参照）。
#
# 使い方:
#   check-internal-jargon.sh [<リポジトリルート>]
#   check-internal-jargon.sh --self-test
#
# 出力:
#   見つかった語ごとに「<語>: <ファイル>:<行> → <置き換え先>」を1行で出す。
#   末尾に「独自語彙検査: <N>件」を出す（0件なら本文なしでこの1行だけ）。
#   既存の scan_banned_terms と同じ方針で、報告のみで実行は止めない
#   （通常実行時の終了コードは常に0）。
#
# 除外（enum値・コードの中の識別子としての使用）:
#   「status=封印済み」「status = 封印済み」のような、実装が実際に返す値
#   （enum値）としての使用は、指示書5節の「コードの中の識別子」に相当し、
#   走査対象から除外する。同様に「採録v0確定」のようなバージョン付き状態値
#   （語の直後に v + 数字が続く形）も除外する。
#   バッククォートで囲まれた対象語（例: `封印済み` | `中断` のようなテーブル
#   での enum 列挙）と、class="tag ...">の直後に続く対象語（例:
#   <span class="tag pass">封印済み→完了</span> のような状態バッジの HTML
#   表示）も、同様にコードの中の値・実行結果の表示に相当するため除外する。
#
# 自己テスト（--self-test）:
#   (a) 対象語（scope=skills）が含まれる場合に検出されること
#   (b) 対象語が含まれない場合に0件を返すこと
#   (c) scope に "skills" を含まない語（scope=rule-definitions の既存語）が
#       誤って検出されないこと
#   (d) status= の右辺値・バージョン付き状態値としての使用は除外されること
#   (e) 「収束」「未収束」「束ねる」が「束」の誤検知にならないこと
#   (f) バッククォート囲みのenum列挙・HTMLタグ表示としての使用は
#       除外されること
#   (g) 「書き起こす」「書き起こし」「未書き起こし」が「起こす」の
#       誤検知にならないこと
#   の7ケースを検証し、[PASS]/[FAIL] を出力する。全PASSなら終了コード0、
#   1件でもFAILなら終了コード1。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# 「束」「起こす」だけの特別扱い: 「収束」「未収束」「束ねる」「書き起こす」
# （「書き起こし」「書き起こされ」「未書き起こし」等の活用形も含む）は正当な
# 複合語であり、「束」「起こす」単体の誤検知になる（例:「上限3回で収束しな
# ければ」「共通文書を書き起こす」）。これらの語だけを、対象語の文字を一切
# 含まないプレースホルダ（SAFEWORD）へ置き換えてから grep する。他の語には
# 一切適用しない。
# 出力形式は grep -n -H -F と同じ「file:line:content」を維持する。
grep_term_matches() {
  local term="$1"
  shift
  local f line_out
  if [ "$term" = "束" ]; then
    for f in "$@"; do
      while IFS= read -r line_out; do
        [ -z "$line_out" ] && continue
        printf '%s:%s\n' "$f" "$line_out"
      done < <(sed -e 's/収束/SAFEWORD/g' -e 's/未収束/SAFEWORD/g' -e 's/束ねる/SAFEWORD/g' "$f" 2>/dev/null | grep -n -F -- "$term" || true)
    done
  elif [ "$term" = "起こす" ]; then
    for f in "$@"; do
      while IFS= read -r line_out; do
        [ -z "$line_out" ] && continue
        printf '%s:%s\n' "$f" "$line_out"
      done < <(sed -e 's/書き起こ/SAFEWORD/g' "$f" 2>/dev/null | grep -n -F -- "$term" || true)
    done
  else
    grep -n -H -F -- "$term" "$@" 2>/dev/null || true
  fi
}

# 対象ファイル（SKILL.md・guide.html）を rule-banned-terms.json の scope=skills
# の語で走査し、結果を標準出力へ書く。$1: リポジトリルート
run_check() {
  local root="$1"
  local term_file="${root}/delivery-payload/references/rule-banned-terms.json"
  if [ ! -f "$term_file" ]; then
    echo "独自語彙検査: 0件"
    return 0
  fi

  local files=()
  while IFS= read -r f; do
    files+=("$f")
  done < <(find "${root}/.claude/skills" \( -name 'SKILL.md' -o -name 'guide.html' \) -type f 2>/dev/null | sort)

  if [ "${#files[@]}" -eq 0 ]; then
    echo "独自語彙検査: 0件"
    return 0
  fi

  local terms_tsv
  terms_tsv="$(jq -r '.terms[] | select(.scope | index("skills")) | [.term, (.replacement // "")] | @tsv' "$term_file" 2>/dev/null || true)"
  if [ -z "$terms_tsv" ]; then
    echo "独自語彙検査: 0件"
    return 0
  fi

  local hit_count=0
  local term replacement match f rest line content relpath
  while IFS=$'\t' read -r term replacement; do
    [ -z "$term" ] && continue
    while IFS= read -r match; do
      [ -z "$match" ] && continue
      f="${match%%:*}"
      rest="${match#*:}"
      line="${rest%%:*}"
      content="${rest#*:}"
      # enum値・バージョン付き状態値としての使用は、コードの中の識別子に
      # 相当するため除外する（例: status=封印済み / 採録v0確定）。
      if printf '%s' "$content" | grep -qE "status[[:space:]]*=[[:space:]]*${term}"; then
        continue
      fi
      if printf '%s' "$content" | grep -qE "${term}v[0-9]"; then
        continue
      fi
      # バッククォートで囲まれた対象語（コード内の値・識別子としての表示）は
      # enumのテーブル列挙（例: `封印済み` | `中断`）に相当するため除外する。
      # 対象語がバッククォート同士の間に現れていれば、その間に他の文字
      # （例: 「封印」に対する「封印済み」の「済み」）を挟んでいてもよい。
      # バッククォートを跨いで一致しないよう、間に別のバッククォートが
      # 無いことを条件にする（[^`]*）。
      if printf '%s' "$content" | grep -qE '`[^`]*'"${term}"'[^`]*`'; then
        continue
      fi
      # class="tag ...">の直後に続く対象語は、状態バッジのHTML表示
      # （例: <span class="tag pass">封印済み→完了</span>）に相当するため除外する。
      if printf '%s' "$content" | grep -qE 'class="tag[^"]*">'"${term}"; then
        continue
      fi
      relpath="${f#"$root"/}"
      echo "${term}: ${relpath}:${line} → ${replacement}"
      hit_count=$((hit_count + 1))
    done < <(grep_term_matches "$term" "${files[@]}")
  done <<< "$terms_tsv"

  if [ "$hit_count" -eq 0 ]; then
    echo "独自語彙検査: 0件"
  else
    echo "独自語彙検査: ${hit_count}件"
  fi
  return 0
}

self_test() {
  local pass=0 fail=0
  local tmp
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-internal-jargon-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "${tmp}/delivery-payload/references"
  cat > "${tmp}/delivery-payload/references/rule-banned-terms.json" <<'JSON'
{
  "specVersion": 2,
  "terms": [
    {"term": "納品", "replacement": null, "scope": ["rule-definitions"]},
    {"term": "束", "replacement": "まとまり", "scope": ["skills"]}
  ]
}
JSON

  mkdir -p "${tmp}/.claude/skills/sample-skill/references"
  cat > "${tmp}/.claude/skills/sample-skill/SKILL.md" <<'MD'
# サンプルスキル

このスキルは複数ファイルの束を扱う。
納品の確認も行う。
MD

  local out
  out="$(run_check "$tmp")"

  if grep -qE '^束: .*SKILL\.md:[0-9]+ → まとまり$' <<< "$out"; then
    echo "[PASS] (a) scope=skillsの対象語が検出される"; pass=$((pass + 1))
  else
    echo "[FAIL] (a) scope=skillsの対象語が検出されるべき"; echo "$out"; fail=$((fail + 1))
  fi

  if grep -q '^納品:' <<< "$out"; then
    echo "[FAIL] (c) scopeにskillsを含まない語(納品)が誤って検出された"; fail=$((fail + 1))
  else
    echo "[PASS] (c) scopeにskillsを含まない語は検出されない"; pass=$((pass + 1))
  fi

  # ケース(b): 対象語を含まない本文にすると0件になること
  cat > "${tmp}/.claude/skills/sample-skill/SKILL.md" <<'MD'
# サンプルスキル

このスキルはまとまりを扱う。
MD
  local out2
  out2="$(run_check "$tmp")"
  if grep -qF "独自語彙検査: 0件" <<< "$out2"; then
    echo "[PASS] (b) 対象語がない場合は0件"; pass=$((pass + 1))
  else
    echo "[FAIL] (b) 対象語がない場合は0件になるべき"; echo "$out2"; fail=$((fail + 1))
  fi

  # ケース(d): status= の右辺値・バージョン付き状態値は除外されること
  cat > "${tmp}/delivery-payload/references/rule-banned-terms.json" <<'JSON'
{
  "specVersion": 2,
  "terms": [
    {"term": "封印済み", "replacement": "確定済み", "scope": ["skills"]},
    {"term": "採録", "replacement": "書き起こす", "scope": ["skills"]}
  ]
}
JSON
  cat > "${tmp}/.claude/skills/sample-skill/SKILL.md" <<'MD'
# サンプルスキル

このスキルは status=封印済み のときだけ実行する。
採録v0確定 の facts を読む。
MD
  local out3
  out3="$(run_check "$tmp")"
  if grep -qF "独自語彙検査: 0件" <<< "$out3"; then
    echo "[PASS] (d) status=の右辺値・バージョン付き状態値は除外される"; pass=$((pass + 1))
  else
    echo "[FAIL] (d) status=の右辺値・バージョン付き状態値は除外されるべき"; echo "$out3"; fail=$((fail + 1))
  fi

  # ケース(e): 「収束」「未収束」「束ねる」は「束」の誤検知にならないこと
  cat > "${tmp}/delivery-payload/references/rule-banned-terms.json" <<'JSON'
{
  "specVersion": 2,
  "terms": [
    {"term": "束", "replacement": "まとまり", "scope": ["skills"]}
  ]
}
JSON
  cat > "${tmp}/.claude/skills/sample-skill/SKILL.md" <<'MD'
# サンプルスキル

上限3回で収束しなければ処理を止める。
未収束のまま次工程へ進まない。
結果を束ねる処理を行う。
MD
  local out4
  out4="$(run_check "$tmp")"
  if grep -qF "独自語彙検査: 0件" <<< "$out4"; then
    echo "[PASS] (e) 収束・未収束・束ねるは束の誤検知にならない"; pass=$((pass + 1))
  else
    echo "[FAIL] (e) 収束・未収束・束ねるが誤検知された"; echo "$out4"; fail=$((fail + 1))
  fi

  # ケース(f): バッククォート囲みのenum列挙・HTMLタグ表示としての使用は除外されること
  cat > "${tmp}/delivery-payload/references/rule-banned-terms.json" <<'JSON'
{
  "specVersion": 2,
  "terms": [
    {"term": "封印済み", "replacement": "確定済み", "scope": ["skills"]}
  ]
}
JSON
  cat > "${tmp}/.claude/skills/sample-skill/SKILL.md" <<'MD'
# サンプルスキル

| status | `封印済み` | `中断` |
<span class="tag pass">封印済み→完了</span>
MD
  local out5
  out5="$(run_check "$tmp")"
  if grep -qF "独自語彙検査: 0件" <<< "$out5"; then
    echo "[PASS] (f) バッククォート囲みのenum列挙・HTMLタグ表示は除外される"; pass=$((pass + 1))
  else
    echo "[FAIL] (f) バッククォート囲みのenum列挙・HTMLタグ表示は除外されるべき"; echo "$out5"; fail=$((fail + 1))
  fi

  # ケース(g): 「書き起こす」「書き起こし」「未書き起こし」は「起こす」の誤検知にならないこと
  cat > "${tmp}/delivery-payload/references/rule-banned-terms.json" <<'JSON'
{
  "specVersion": 2,
  "terms": [
    {"term": "起こす", "replacement": "作る", "scope": ["skills"]}
  ]
}
JSON
  cat > "${tmp}/.claude/skills/sample-skill/SKILL.md" <<'MD'
# サンプルスキル

共通文書を書き起こす。
状態遷移表がまだ書き起こされていない。
未書き起こしのまま次工程へ進まない。
MD
  local out6
  out6="$(run_check "$tmp")"
  if grep -qF "独自語彙検査: 0件" <<< "$out6"; then
    echo "[PASS] (g) 書き起こす・書き起こし・未書き起こしは起こすの誤検知にならない"; pass=$((pass + 1))
  else
    echo "[FAIL] (g) 書き起こす・書き起こし・未書き起こしが誤検知された"; echo "$out6"; fail=$((fail + 1))
  fi

  echo "self-test: ${pass} PASS, ${fail} FAIL"
  if [ "$fail" -eq 0 ]; then
    return 0
  else
    return 1
  fi
}

case "${1:-}" in
  --self-test)
    self_test
    exit $?
    ;;
esac

ROOT="${1:-$DEFAULT_ROOT}"
run_check "$ROOT"
exit 0
