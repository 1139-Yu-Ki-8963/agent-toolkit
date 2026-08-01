#!/usr/bin/env bash
set -euo pipefail

# test-python-facts-flow.sh — 写真指摘1-29〜1-36/1-45〜1-47の決定的縦貫fixture
#
# 外部リポジトリや実データを要求せず、作成した一時fixtureだけで
# Python抽出 → 独立再計数 → 封印 → scaffold順序を検証する。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
EXTRACTOR="$REPO_ROOT/.claude/skills/extracting-unit-facts-from-code/scripts/extract-python-facts.py"
COUNTER="$REPO_ROOT/.claude/skills/extracting-unit-facts-from-code/scripts/recount-python-facts.py"
RECOUNT="$REPO_ROOT/.claude/skills/extracting-unit-facts-from-code/scripts/recount-facts.sh"
SEAL="$SCRIPT_DIR/../seal-facts.sh"
SCAFFOLD="$SCRIPT_DIR/../scaffold-screen.sh"
PREFILL="$SCRIPT_DIR/../prefill-design-from-facts.sh"
COVERAGE="$REPO_ROOT/.claude/skills/generating-reverse-detailed-design/scripts/check-fact-coverage.sh"
ORCHESTRATOR="$REPO_ROOT/.claude/skills/orchestrating-reverse-docs-flow/SKILL.md"
ORCHESTRATOR_CONTRACT="$REPO_ROOT/.claude/skills/orchestrating-reverse-docs-flow/references/contract.md"
ORCHESTRATOR_GUIDE="$REPO_ROOT/.claude/skills/orchestrating-reverse-docs-flow/references/orchestrating-reverse-docs-flow-guide.html"
RESTORE_SCREEN_MANIFEST="$SCRIPT_DIR/../unit-list/restore-screen-manifest.sh"
SURVEY_CHECK="$REPO_ROOT/.claude/skills/surveying-architecture-for-reverse-docs/scripts/check-architecture-survey.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/python-facts-flow.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
fixture_repo="$tmp/repo"
facts_dir="$tmp/verification/screen-python-fixture/facts/extract-1"
docs_dir="$tmp/docs"
mkdir -p "$fixture_repo/src" "$facts_dir" "$docs_dir"

cat > "$fixture_repo/src/service.py" <<'PY'
import os
import sys
import time
from client import API as Api

def load():
    static_value = 42
    stamp = time.time()
    token = os.environ["SERVICE_TOKEN"]
    remote_value = client.fetch()
    try:
        client.fetch()
    except ValueError:
        raise RuntimeError("failed")
    return static_value
PY

# PEP 263宣言付きlatin-1。printfの8進値351はé。
{
  printf '# -*- coding: latin-1 -*-\n'
  printf 'def label():\n'
  printf '    return "caf\351"\n'
} > "$fixture_repo/src/latin.py"

fail=0
report() {
  if [ "$2" -eq 0 ]; then
    echo "PASS: $1"
  else
    echo "FAIL: $1" >&2
    fail=$((fail + 1))
  fi
}

# fresh対話入口fixture: 初期argsは空とし、質問回答だけでPython入口の必須値を確定する。
initial_args="$tmp/initial-args.json"
question_answers="$tmp/question-answers.json"
resolved_args="$tmp/resolved-args.json"
printf '{}\n' > "$initial_args"
PYTHONDONTWRITEBYTECODE=1 python3 - \
  "$question_answers" "$fixture_repo" "$docs_dir" "$tmp/verification" <<'PY'
import json
import pathlib
import sys

answer_path, repo, output_dir, verification_dir = sys.argv[1:]
answers = {
    "facts_profile": "python",
    "target_repo_path": repo,
    "output_dir": output_dir,
    "target_file_paths": ["src/service.py", "src/latin.py"],
    "facts_unit_id": "python-fixture",
    "verification_dir": verification_dir,
    "execution_mode": "full",
}
pathlib.Path(answer_path).write_text(
    json.dumps(answers, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY

PYTHONDONTWRITEBYTECODE=1 python3 - \
  "$initial_args" "$question_answers" "$resolved_args" <<'PY'
import json
import pathlib
import sys

initial_path, answer_path, resolved_path = map(pathlib.Path, sys.argv[1:])
initial = json.loads(initial_path.read_text(encoding="utf-8"))
answers = json.loads(answer_path.read_text(encoding="utf-8"))
if initial:
    raise SystemExit("initial args fixture must be empty")
resolved = dict(initial)
resolved.update(answers)
resolved_path.write_text(
    json.dumps(resolved, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY

entry_ready=0
entry_contract_rc=0
PYTHONDONTWRITEBYTECODE=1 python3 - "$resolved_args" <<'PY' || entry_contract_rc=$?
import json
import pathlib
import sys

args = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
required = (
    "target_repo_path",
    "output_dir",
    "target_file_paths",
    "facts_unit_id",
    "verification_dir",
    "execution_mode",
)
missing = [name for name in required if not args.get(name)]
if args.get("facts_profile") != "python" or missing or "screen_scope" in args:
    raise SystemExit("python pre-hearing contract is incomplete")
repo = pathlib.Path(args["target_repo_path"]).resolve()
paths = args["target_file_paths"]
if not isinstance(paths, list) or not paths:
    raise SystemExit("target_file_paths must be a non-empty list")
for raw in paths:
    rel = pathlib.PurePosixPath(raw)
    if rel.is_absolute() or ".." in rel.parts or rel.suffix != ".py":
        raise SystemExit("target_file_paths must contain repo-relative .py paths")
    target = (repo / pathlib.Path(*rel.parts)).resolve()
    try:
        target.relative_to(repo)
    except ValueError:
        raise SystemExit("target path escaped the fixture repository")
    if not target.is_file():
        raise SystemExit("target file does not exist")
PY
if [ "$entry_contract_rc" -eq 0 ]; then
  entry_ready=1
fi
report "Phase 0P fresh初期args空→質問回答fixtureでPython必須値確定" "$entry_contract_rc"

# 回答確定後、facts抽出より先に調査書を生成し、実際の調査ゲートで検証する。
survey_doc="$docs_dir/プロジェクト共通/アーキテクチャ調査書.md"
survey_ready=0
survey_rc=0
if [ "$entry_ready" -ne 1 ] || [ -e "$survey_doc" ]; then
  survey_rc=1
else
  mkdir -p "$(dirname "$survey_doc")"
  # 調査書の必須節を追加する際は本フィクスチャの追従を同一コミットで行う
  cat > "$survey_doc" <<'MD'
## 調査メタ

### 実行した調査コマンド一覧

| コマンド | 目的 |
|---|---|
| `find . -maxdepth 2 -type f` | Python対象ファイルとディレクトリ構造の確認 |

## エントリポイント

`src/service.py` と `src/latin.py` を確認した。

## ディレクトリ責務マップ

| ディレクトリ | 責務 | 根拠パス |
|---|---|---|
| `src` | Python実装 | `src/service.py` |

## ユニット種別判定

| 種別 | 実在判定 | 検出手がかり | 根拠パス |
|---|---|---|---|
| 画面 | 実在しない（Python facts-only fixtureのため） | - | - |
| API | 実在しない（Python facts-only fixtureのため） | - | - |
| テーブル | 実在しない（Python facts-only fixtureのため） | - | - |
| バッチ | 実在しない（Python facts-only fixtureのため） | - | - |
| 帳票 | 実在しない（Python facts-only fixtureのため） | - | - |
| 外部連携 | 実在しない（Python facts-only fixtureのため） | - | - |

## プロジェクト形態とサイト構成

| 項目 | 内容 | 根拠パス |
|---|---|---|
| プロジェクト形態 | 単独プロジェクト | `src/service.py` |
| ワークスペース定義 | 実在しない（ワークスペース定義ファイルが見つからないため） | `src/service.py` |

### サイト一覧

| サイトキー | 表示名 | ルートディレクトリ | ビルドコマンド | 起動コマンド | 根拠パス |
|---|---|---|---|---|---|
| main | 単一サイト | . | - | - | `src/service.py` |
MD
  bash "$SURVEY_CHECK" "$survey_doc" "$fixture_repo" >/dev/null || survey_rc=$?
fi
if [ "$survey_rc" -eq 0 ]; then
  survey_ready=1
fi
report "Phase 0P 質問回答後にsurvey生成・実ゲート検証" "$survey_rc"

# 1-45: 画面ディレクトリはfacts封印まで不要。factsはverification側へ先に作る。
if [ ! -d "$docs_dir/画面/screen-python-fixture" ]; then
  report "1-45 scaffold前は画面ディレクトリ不在" 0
else
  report "1-45 scaffold前は画面ディレクトリ不在" 1
fi

# 統括到達性: pythonは明示facts-only入口、通常の画面ループは常にscreen。
phase_0p="$(sed -n '/^### Phase 0P:/,/^### Phase 1B:/p' "$ORCHESTRATOR")"
phase_6="$(sed -n '/^### Phase 6:/,/^### Phase 7:/p' "$ORCHESTRATOR")"
if grep -q 'profile=python' <<<"$phase_0p" \
  && grep -q 'survey_doc_path.*解決' <<<"$phase_0p" \
  && grep -q 'surveying-architecture-for-reverse-docs' <<<"$phase_0p" \
  && grep -q '画面一覧生成・対象画面ID実在確認' <<<"$phase_0p" \
  && grep -q '常に`profile=screen`' <<<"$phase_6" \
  && ! grep -q '全件.*py.*pythonへ確定' <<<"$phase_6"; then
  report "1-29/1-45 pythonは明示facts-only、画面ループはscreen固定" 0
else
  report "1-29/1-45 pythonとscreenの統括経路分離" 1
fi

skill_survey_pos="$(grep -n -m1 'survey_doc_path.*解決' "$ORCHESTRATOR" | cut -d: -f1 || true)"
skill_extract_pos="$(grep -n -m1 'survey_doc_path確定後に限り' "$ORCHESTRATOR" | cut -d: -f1 || true)"
contract_survey_pos="$(grep -n -m1 'facts抽出より先にsurvey_doc_pathを解決' "$ORCHESTRATOR_CONTRACT" | cut -d: -f1 || true)"
contract_extract_pos="$(grep -n -m1 '画面一覧生成・対象画面ID実在確認.*extracting-unit-facts-from-code' "$ORCHESTRATOR_CONTRACT" | cut -d: -f1 || true)"
guide_survey_pos="$(grep -n -m1 'survey_doc_path.*既存調査書から解決' "$ORCHESTRATOR_GUIDE" | cut -d: -f1 || true)"
guide_extract_pos="$(grep -n -m1 'facts抽出へ進み' "$ORCHESTRATOR_GUIDE" | cut -d: -f1 || true)"

if grep -q 'Python facts-only入口契約' "$ORCHESTRATOR_CONTRACT" \
  && grep -q '通常の画面フローを意味し、画面ループ.*常に.*screen' "$ORCHESTRATOR_CONTRACT" \
  && grep -q 'Phase 0P（明示Python facts-only）' "$ORCHESTRATOR_GUIDE" \
  && grep -q 'target_file_paths・facts_unit_id・verification_dir・実行モード' "$ORCHESTRATOR" \
  && grep -q 'フル実行（facts_profile=python）.*Phase 0P' "$ORCHESTRATOR" \
  && grep -q '起動引数が空の対話実行ではAskUserQuestion' "$ORCHESTRATOR_CONTRACT" \
  && grep -q 'フル実行の事前ヒアリング完了後はPhase 1でなくPhase 0P' "$ORCHESTRATOR_CONTRACT" \
  && grep -q '起動引数が空の対話実行ではprofileを質問' "$ORCHESTRATOR_GUIDE" \
  && grep -q 'フル実行はPhase 1ではなくPhase 0P' "$ORCHESTRATOR_GUIDE" \
  && [ -n "$skill_survey_pos" ] && [ -n "$skill_extract_pos" ] \
  && [ -n "$contract_survey_pos" ] && [ -n "$contract_extract_pos" ] \
  && [ -n "$guide_survey_pos" ] && [ -n "$guide_extract_pos" ] \
  && [ "$skill_survey_pos" -lt "$skill_extract_pos" ] \
  && [ "$contract_survey_pos" -le "$contract_extract_pos" ] \
  && [ "$guide_survey_pos" -le "$guide_extract_pos" ]; then
  report "1-29 python facts-only三文書でsurvey解決→facts抽出の順序一致" 0
else
  report "1-29 python facts-onlyのsurvey順序が三文書で不一致" 1
fi

# 1-40/1-41: 著述合流後、静的完了より前にmetadata抽出と一覧再生成を必須化。
static_gate="$(sed -n '/^\*\*静的完了ゲート\*\*/,/^\*\*(a)/p' "$ORCHESTRATOR")"
if grep -q 'extract-screen-metadata.sh' <<<"$static_gate" \
  && grep -q 'build-unit-list.sh' <<<"$static_gate" \
  && grep -q 'Phase 3 Step 6' <<<"$static_gate" \
  && grep -q 'screen-manifest.json' "$ORCHESTRATOR_CONTRACT" \
  && grep -q 'restore-screen-manifest.sh' "$ORCHESTRATOR_CONTRACT" \
  && grep -q '明示的な移行・復元時' "$ORCHESTRATOR_CONTRACT" \
  && grep -q 'この後でのみ画面レジストリ' <<<"$static_gate" \
  && grep -q 'この復元・再生成を省略した状態は.*静的完了ではない' "$ORCHESTRATOR_CONTRACT"; then
  report "1-40/1-41 永続manifest復元→metadata抽出→一覧再生成を静的完了ゲートに接続" 0
else
  report "1-40/1-41 再開可能な一覧再生成契約" 1
fi

restore_rc=0
bash "$RESTORE_SCREEN_MANIFEST" --self-test >/dev/null || restore_rc=$?
report "1-40/1-41 既存HTMLの埋込manifestから永続正本を復元" "$restore_rc"

extract_rc=0
if [ "$entry_ready" -eq 1 ] && [ "$survey_ready" -eq 1 ]; then
  PYTHONDONTWRITEBYTECODE=1 python3 "$EXTRACTOR" extract \
    --repo "$fixture_repo" \
    --out "$facts_dir/facts.yml" \
    --run-id extract-1 \
    src/service.py src/latin.py || extract_rc=$?
else
  extract_rc=1
fi
report "1-29 profile=pythonの決定的AST抽出" "$extract_rc"

counts="$(PYTHONDONTWRITEBYTECODE=1 python3 "$COUNTER" counts \
  --repo "$fixture_repo" src/service.py src/latin.py)"
expected_counts="$(cat <<'COUNTS'
import 4
function 2
local_assignment 1
external_call 1
exception_handling 3
measurement_pending 3
COUNTS
)"
if [ "$counts" = "$expected_counts" ]; then
  report "1-29 独立ASTカウンターで5構文＋実測委譲分類の件数一致" 0
else
  printf 'expected:\n%s\nactual:\n%s\n' "$expected_counts" "$counts" >&2
  report "1-29 5構文＋実測委譲分類の件数一致" 1
fi

# 1-30: 完全一致だけでなく包含・部分交差も含め、異分類のsource span重複を拒否する。
span_rc=0
PYTHONDONTWRITEBYTECODE=1 python3 "$COUNTER" validate-spans \
  --facts "$facts_dir/facts.yml" \
  --target-file src/service.py --target-file src/latin.py \
  >/dev/null || span_rc=$?
report "1-30 包含範囲を含む分類間source span重複0" "$span_rc"

cat > "$tmp/overlapping-spans.yml" <<'YML'
profile: python
sections:
  function:
    reason: ""
    items:
      - key: "function-load"
        value: "def load(): return 1"
        evidence: "src/service.py:1"
        source_span: "src/service.py:1:0-3:20"
  local_assignment:
    reason: ""
    items:
      - key: "local-assignment-value"
        value: "value = 1"
        evidence: "src/service.py:2"
        source_span: "src/service.py:2:4-2:13"
YML
if PYTHONDONTWRITEBYTECODE=1 python3 "$COUNTER" validate-spans \
  --facts "$tmp/overlapping-spans.yml" --target-file src/service.py \
  >/dev/null 2>&1; then
  report "1-30 包含範囲を持つ破損fixtureを拒否" 1
else
  report "1-30 包含範囲を持つ破損fixtureを拒否" 0
fi

expect_production_span_rejection() {
  local label="$1" broken_facts="$2"
  if bash "$RECOUNT" "$broken_facts" "$fixture_repo" \
      src/service.py src/latin.py >/dev/null 2>&1; then
    report "$label" 1
  else
    report "$label" 0
  fi
}

# 直接validatorだけでなく、本番のrecount-factsゲートからも排他検査が必ず呼ばれる。
cp "$facts_dir/facts.yml" "$tmp/overlapping-production.yml"
awk '
  /^  local_assignment:/ { in_local=1 }
  in_local && /^        source_span:/ && !changed {
    print "        source_span: \"src/service.py:6:0-6:11\""
    changed=1
    next
  }
  { print }
' "$tmp/overlapping-production.yml" > "$tmp/overlapping-production.tmp"
mv "$tmp/overlapping-production.tmp" "$tmp/overlapping-production.yml"
expect_production_span_rejection \
  "1-30 本番再計数ゲートが分類間span重複を拒否" \
  "$tmp/overlapping-production.yml"

sed '/^        source_span:/d' "$facts_dir/facts.yml" \
  > "$tmp/spans-all-deleted.yml"
expect_production_span_rejection \
  "1-30 本番再計数ゲートがsource_span全削除を拒否" \
  "$tmp/spans-all-deleted.yml"

awk '
  /^        source_span:/ && !changed { changed=1; next }
  { print }
' "$facts_dir/facts.yml" > "$tmp/span-one-deleted.yml"
expect_production_span_rejection \
  "1-30 本番再計数ゲートがsource_span1件削除を拒否" \
  "$tmp/span-one-deleted.yml"

awk '
  /^        source_span:/ && !changed {
    print "        source_span: \"src/service.py:6:0-6:0\""
    changed=1
    next
  }
  { print }
' "$facts_dir/facts.yml" > "$tmp/span-invalid-range.yml"
expect_production_span_rejection \
  "1-30 本番再計数ゲートが不正span範囲を拒否" \
  "$tmp/span-invalid-range.yml"

awk '
  /^        source_span:/ && !changed {
    print "        source_span: \"src/other.py:6:0-6:11\""
    changed=1
    next
  }
  { print }
' "$facts_dir/facts.yml" > "$tmp/span-other-path.yml"
expect_production_span_rejection \
  "1-30 本番再計数ゲートがevidence・target外pathを拒否" \
  "$tmp/span-other-path.yml"

# 1-31: 固定API名ではなく、構文だけで値が確定するかを基準に分類する。
if grep -q '"local_assignment-static_value-' "$facts_dir/facts.yml" \
  && grep -q '"measurement_pending-stamp-' "$facts_dir/facts.yml" \
  && grep -q '"measurement_pending-token-' "$facts_dir/facts.yml" \
  && grep -q '"measurement_pending-remote_value-' "$facts_dir/facts.yml" \
  && ! grep -q '"local_assignment-stamp-' "$facts_dir/facts.yml" \
  && ! grep -q '"local_assignment-token-' "$facts_dir/facts.yml" \
  && ! grep -q '"local_assignment-remote_value-' "$facts_dir/facts.yml"; then
  report "1-31 構文決定性に基づく実測委譲の該当・非該当基準" 0
else
  report "1-31 構文決定性に基づく実測委譲の該当・非該当基準" 1
fi

recount_rc=0
bash "$RECOUNT" "$facts_dir/facts.yml" "$fixture_repo" \
  src/service.py src/latin.py > "$facts_dir/recount-report.txt" || recount_rc=$?
report "1-47 抽出factsと独立再計数の全分類乖離0" "$recount_rc"

# 1-33: 関数本文を先頭行だけへ壊すと行網羅検査が必ず失敗する。
cp "$facts_dir/facts.yml" "$tmp/incomplete.yml"
awk '
  BEGIN { in_function=0; changed=0 }
  /^  function:/ { in_function=1 }
  in_function && /^        value:/ && changed==0 {
    print "        value: \"def load():\""
    changed=1
    next
  }
  { print }
' "$tmp/incomplete.yml" > "$tmp/incomplete.tmp"
mv "$tmp/incomplete.tmp" "$tmp/incomplete.yml"
if PYTHONDONTWRITEBYTECODE=1 python3 "$EXTRACTOR" verify-bodies \
  --facts "$tmp/incomplete.yml" --repo "$fixture_repo" \
  src/service.py src/latin.py >/dev/null 2>&1; then
  report "1-33 関数本文の先頭行だけでは不合格" 1
else
  report "1-33 関数本文の先頭行だけでは不合格" 0
fi

seal_rc=0
bash "$SEAL" seal "$facts_dir" >/dev/null || seal_rc=$?
bash "$SEAL" verify "$facts_dir" >/dev/null || seal_rc=$?
report "1-47 facts封印と直後verify" "$seal_rc"
fresh_chain_rc=0
if [ "$entry_ready" -ne 1 ] || [ "$survey_ready" -ne 1 ] \
  || [ "$extract_rc" -ne 0 ] || [ "$recount_rc" -ne 0 ] || [ "$seal_rc" -ne 0 ]; then
  fresh_chain_rc=1
fi
report "Phase 0P fresh初期args空→質問回答→survey生成検証→facts封印" "$fresh_chain_rc"

# 1-46: latin-1原本を抽出・再計数とも同じPEP 263経路で読み、UTF-8 factsへ変換する。
if grep -q 'café' "$facts_dir/facts.yml" && [ "$recount_rc" -eq 0 ]; then
  report "1-46 非UTF-8原本を共通経路でUTF-8正規化" 0
else
  report "1-46 非UTF-8原本を共通経路でUTF-8正規化" 1
fi

# セキュリティ境界: Python profileはrepo相対の実在.pyだけを読み取る。
cat > "$tmp/outside.py" <<'PY'
def outside():
    return "outside"
PY
cat > "$fixture_repo/src/not-python.txt" <<'TXT'
def disguised():
    return "not-python"
TXT
ln -s "$tmp/outside.py" "$fixture_repo/src/outside-link.py"

target_boundary_rc=0
if PYTHONDONTWRITEBYTECODE=1 python3 "$EXTRACTOR" counts \
    --repo "$fixture_repo" "$tmp/outside.py" >/dev/null 2>&1; then
  target_boundary_rc=1
fi
if PYTHONDONTWRITEBYTECODE=1 python3 "$EXTRACTOR" counts \
    --repo "$fixture_repo" ../outside.py >/dev/null 2>&1; then
  target_boundary_rc=1
fi
if PYTHONDONTWRITEBYTECODE=1 python3 "$EXTRACTOR" counts \
    --repo "$fixture_repo" src/outside-link.py >/dev/null 2>&1; then
  target_boundary_rc=1
fi
if PYTHONDONTWRITEBYTECODE=1 python3 "$EXTRACTOR" counts \
    --repo "$fixture_repo" src/not-python.txt >/dev/null 2>&1; then
  target_boundary_rc=1
fi
if PYTHONDONTWRITEBYTECODE=1 python3 "$COUNTER" counts \
    --repo "$fixture_repo" "$tmp/outside.py" >/dev/null 2>&1; then
  target_boundary_rc=1
fi
if PYTHONDONTWRITEBYTECODE=1 python3 "$COUNTER" counts \
    --repo "$fixture_repo" ../outside.py >/dev/null 2>&1; then
  target_boundary_rc=1
fi
if PYTHONDONTWRITEBYTECODE=1 python3 "$COUNTER" counts \
    --repo "$fixture_repo" src/outside-link.py >/dev/null 2>&1; then
  target_boundary_rc=1
fi
if PYTHONDONTWRITEBYTECODE=1 python3 "$COUNTER" counts \
    --repo "$fixture_repo" src/not-python.txt >/dev/null 2>&1; then
  target_boundary_rc=1
fi
report "Python対象境界: extractor/counterとも絶対/../symlink脱出/.py外をfail-closed" "$target_boundary_rc"

python38_compat_rc=0
PYTHONDONTWRITEBYTECODE=1 python3 - "$EXTRACTOR" "$COUNTER" <<'PY' || python38_compat_rc=$?
import ast
import pathlib
import runpy
import sys

for script_path in sys.argv[1:]:
    source = pathlib.Path(script_path).read_text(encoding="utf-8")
    ast.parse(source, filename=script_path, feature_version=(3, 8))
    namespace = runpy.run_path(script_path)
    try:
        namespace["require_runtime_version"]((3, 7))
    except SystemExit as exc:
        if exc.code != 2:
            raise
    else:
        raise AssertionError("{} accepted Python 3.7".format(script_path))
    namespace["require_runtime_version"]((3, 8))
PY
report "profile=python実行条件: extractor/counterはPython 3.8構文互換かつ3.7以下fail-fast" "$python38_compat_rc"

scaffold_rc=0
bash "$SCAFFOLD" "$docs_dir" python-fixture "Python fixture" >/dev/null || scaffold_rc=$?
bash "$SCAFFOLD" --verify "$docs_dir" python-fixture >/dev/null || scaffold_rc=$?
report "1-45 facts封印後にscaffoldして循環前提なし" "$scaffold_rc"

seal_self_rc=0
bash "$SEAL" --self-test >/dev/null || seal_self_rc=$?
report "1-32 引用符差の正規化fixture" "$seal_self_rc"

prefill_rc=0
bash "$PREFILL" --self-test >/dev/null || prefill_rc=$?
report "1-34/1-35 転記の表幅・コードブロックfixture" "$prefill_rc"

coverage_rc=0
bash "$COVERAGE" --self-test >/dev/null || coverage_rc=$?
report "1-36 拡張子非依存の座標ノイズ除去fixture" "$coverage_rc"

if [ "$fail" -eq 0 ]; then
  echo "self-test: 1-29〜1-36/1-45〜1-47 全項目 PASS"
  exit 0
fi
echo "self-test FAIL: ${fail}件" >&2
exit 1
