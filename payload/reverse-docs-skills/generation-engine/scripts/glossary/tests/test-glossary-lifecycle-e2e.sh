#!/usr/bin/env bash
# 用語管理のライフサイクルを1本で通す検査。
#
# 候補（提案）の検証 → 変更の検証 → 用語集の検証 → 投影（ページの生成）までを
# 順に実行し、各段が終了コード0を返すことを確かめる。段ごとの検査は既にあるが、
# 段をまたいだ流れが通ることを確かめるものは無かった（2026-08-28実測）。
#
# 契約: delivery-payload/references/semantic-glossary-contract-v0.1.md
#   6節「意味検証最小範囲」が提案の状態遷移・二者承認・古い基準版を定める。
#   243行目が同じ検証時点の用語集・提案・変更の間のずれの検出を定める。
#
# 判定不能（.claude/rules/always/verification/indeterminate-result/rule.md）:
#   一時領域を確保できない場合、依存（PyYAML）が無い場合は
#   [UNKNOWN] を出力して終了コード2で終える。不合格（1）とは区別する。
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../../.." && pwd)"
glossary_dir="$repo_root/generation-engine/scripts/glossary"
fixtures="$glossary_dir/fixtures"
registry="$fixtures/canonical-registry"
validator="$glossary_dir/validate-semantic-glossary.sh"
projector="$repo_root/generation-engine/scripts/detail-pages/project-semantic-glossary.py"

pass=0
fail=0

ok() { echo "PASS: $1"; pass=$((pass + 1)); }
ng() { echo "FAIL: $1"; fail=$((fail + 1)); }

unknown() {
  echo "[UNKNOWN] $1"
  exit 2
}

# 一時領域を確保する。裸の mktemp は実行環境の制約で失敗しうるため
# ${TMPDIR:-/tmp} を明示する（1-50 の実測）。
if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/glossary-e2e.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
  unknown "一時領域を確保できないため判定できません（mktemp が失敗しました。実行環境の制約が原因である可能性があります）"
fi
trap 'rm -rf "$tmp"' EXIT

# 依存の有無を先に確かめる。無ければ判定不能とする。
if ! bash "$validator" --kind glossary --input "$fixtures/valid-glossary.yaml" >/dev/null 2>"$tmp/dep.err"; then
  if grep -qi 'yaml\|module\|import' "$tmp/dep.err" 2>/dev/null; then
    unknown "用語集の検証に必要な依存が無いため判定できません（$(head -1 "$tmp/dep.err" 2>/dev/null | cut -c1-80)）"
  fi
fi

# 段1: 候補（提案）が検証を通る
if bash "$validator" --kind proposal \
     --input "$fixtures/valid-proposal.yaml" >"$tmp/s1.log" 2>&1; then
  ok "段1 候補の検証が通る"
else
  ng "段1 候補の検証が通らない（$(tail -1 "$tmp/s1.log" | cut -c1-80)）"
fi

# 段2: 変更が検証を通る
if bash "$validator" --kind change \
     --input "$fixtures/valid-change.yaml" >"$tmp/s2.log" 2>&1; then
  ok "段2 変更の検証が通る"
else
  ng "段2 変更の検証が通らない（$(tail -1 "$tmp/s2.log" | cut -c1-80)）"
fi

# 段3: 用語集が検証を通る
if bash "$validator" --kind glossary \
     --input "$fixtures/valid-glossary.yaml" \
     --registry "$registry" >"$tmp/s3.log" 2>&1; then
  ok "段3 用語集の検証が通る"
else
  ng "段3 用語集の検証が通らない（$(tail -1 "$tmp/s3.log" | cut -c1-80)）"
fi

# 段4: 投影が page-data を作る
if python3 "$projector" \
     --input "$fixtures/valid-glossary.yaml" \
     --registry "$registry" \
     --output "$tmp/page-data.json" >"$tmp/s4.log" 2>&1 \
   && [ -s "$tmp/page-data.json" ]; then
  ok "段4 投影が page-data を作る"
else
  # 引数の形が違う場合に備え、使い方を読んで再試行する
  if python3 "$projector" --help >"$tmp/help.txt" 2>&1; then
    ng "段4 投影が page-data を作れない（使い方: $(grep -m1 'usage' "$tmp/help.txt" | cut -c1-70)）"
  else
    ng "段4 投影を実行できない（$(tail -1 "$tmp/s4.log" | cut -c1-80)）"
  fi
fi

# 段5: 承認されていない候補が用語集へ入らない
# 契約6節「提案の状態遷移、二者承認」に当たる。承認の記録を壊した候補が
# 検証で止まることを確かめる。
if [ -f "$fixtures/invalid-approved-proposal.yaml" ]; then
  if bash "$validator" --kind proposal \
       --input "$fixtures/invalid-approved-proposal.yaml" \
       --registry "$registry" >"$tmp/s5.log" 2>&1; then
    ng "段5 承認の記録が壊れた候補を止められない"
  else
    ok "段5 承認の記録が壊れた候補を止める"
  fi
else
  ng "段5 承認の検査に使う見本が無い"
fi

echo "実行 $((pass + fail)) 件 / 成功 $pass 件 / 失敗 $fail 件"
[ "$fail" -eq 0 ]
