#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENGINE="$SCRIPT_DIR/../portal-catalog.mjs"
DEFAULT_CATALOG="$SCRIPT_DIR/../../../delivery-payload/references/portal-catalog.json"
DEFAULT_GOLDEN="$SCRIPT_DIR/../../../delivery-payload/references/portal-catalog-legacy-golden.json"

usage() {
  cat >&2 <<'USAGE'
Usage:
  check-portal-catalog.sh
  check-portal-catalog.sh --self-test
  check-portal-catalog.sh --capture-golden --commit <sha> --repo-root <dir> --output <file>
USAGE
}

capture_golden() {
  local commit="" repo_root="" output=""
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --commit) commit="${2:-}"; shift 2 ;;
      --repo-root) repo_root="${2:-}"; shift 2 ;;
      --output) output="${2:-}"; shift 2 ;;
      *) echo "ERROR: unknown argument: $1" >&2; usage; return 1 ;;
    esac
  done
  [ -n "$commit" ] && [ -n "$repo_root" ] && [ -n "$output" ] \
    || { echo "ERROR: --commit, --repo-root, and --output are required" >&2; return 1; }
  git -C "$repo_root" cat-file -e "$commit:generation-engine/samples/project-portal/index.html" 2>/dev/null \
    || { echo "ERROR: commit/path does not exist: $commit:generation-engine/samples/project-portal/index.html" >&2; return 1; }
  local temporary_html temporary_output
  temporary_html="$(mktemp)"
  temporary_output="$(mktemp "$(dirname "$output")/.portal-catalog-golden.XXXXXX")"
  trap 'rm -f "$temporary_html" "$temporary_output"' RETURN
  git -C "$repo_root" show "$commit:generation-engine/samples/project-portal/index.html" > "$temporary_html"
  node "$ENGINE" extract --html "$temporary_html" > "$temporary_output"
  node -e 'const fs=require("fs");const value=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));const strip=v=>Array.isArray(v)?v.map(strip):v&&typeof v==="object"?Object.fromEntries(Object.entries(v).filter(([k])=>k!=="generatedAt").map(([k,x])=>[k,strip(x)])):v;process.stdout.write(JSON.stringify(strip(value),null,2)+"\n")' "$temporary_output" > "${temporary_output}.normalized"
  mv "${temporary_output}.normalized" "$output"
  rm -f "$temporary_html" "$temporary_output"
  trap - RETURN
  echo "OK: captured portal catalog golden from $commit"
}

self_test() {
  local repo_root="$SCRIPT_DIR/../../.."
  local tmpdir
  # 判定不能規約（.claude/rules/always/verification/indeterminate-result/rule.md）:
  # mktemp の失敗（実行環境のサンドボックス制約等）を対象の不合格と区別する。
  # if の条件式の中で代入と失敗チェックを行うことで、set -e の対象から外す。
  if ! tmpdir="$(mktemp -d 2>/dev/null)" || [ -z "$tmpdir" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）"
    exit 2
  fi
  trap 'rm -rf "$tmpdir"' RETURN

  node "$ENGINE" validate --catalog "$DEFAULT_CATALOG"
  node "$ENGINE" compare \
    --catalog "$DEFAULT_CATALOG" \
    --output-root "$repo_root/generation-engine/samples" \
    --portal-dir "$repo_root/generation-engine/samples/project-portal" \
    --golden "$DEFAULT_GOLDEN"

  if [ "$(jq -r '[.categories[].blueprints[] | select(.kind=="semantic-glossary" and .generator=="managing-semantic-glossary" and .discovery.artifactType=="glossary-page")] | length' "$DEFAULT_CATALOG")" -ne 1 ]; then
    echo "FAIL: approved semantic glossary blueprint is missing or duplicated" >&2
    return 1
  fi
  if [ "$(jq -r '.categories[] | select(any(.blueprints[]; .kind=="semantic-glossary")) | .key' "$DEFAULT_CATALOG")" != "list" ]; then
    echo "FAIL: semantic glossary must belong to list (一覧・設計図), not project (基盤情報)" >&2
    exit 1
  fi
  if [ "$(jq -r '.categories[].blueprints[] | select(.kind=="semantic-glossary") | .dir' "$DEFAULT_CATALOG")" != "project-portal/一覧/用語辞書" ] \
    || [ "$(jq -r '.categories[].blueprints[] | select(.kind=="semantic-glossary") | .discovery.glob' "$DEFAULT_CATALOG")" != "project-portal/一覧/用語辞書/用語辞書.html" ]; then
    echo "FAIL: semantic glossary must be physically located under project-portal/一覧/用語辞書" >&2
    exit 1
  fi
  if jq -e '.categories[].blueprints[] | select(.generator=="generating-glossary-for-reverse-docs")' "$DEFAULT_CATALOG" >/dev/null; then
    echo "FAIL: obsolete reverse glossary generator returned to portal catalog" >&2
    return 1
  fi
  echo "PASS: approved semantic glossary blueprint replaces obsolete reverse generator"

  mkdir -p "$tmpdir/output/pages"
  printf '<h1>Beta</h1><script type="application/json" id="broken">{</script>' > "$tmpdir/output/pages/b.html"
  printf '<h1>Alpha</h1>' > "$tmpdir/output/pages/a.html"
  cat > "$tmpdir/dynamic-catalog.json" <<'JSON'
{"schemaVersion":1,"categories":[{"key":"dynamic","label":"Dynamic","group":"Test","icon":"folder","sub":"test","blueprints":[{"kind":"page","label":"Page","icon":"description","desc":"test","dir":"","generator":"test-generator","unit":"件","countFormat":"detail","discovery":{"artifactType":"dynamic-page","root":"output-dir","glob":"pages/*.html","matchKind":"file","titleSource":"html-h1","dirSource":"match-parent","instanceKeySource":"relative-path","sort":"relative-path-bytewise"}}]}]}
JSON
  dynamic_json="$(node "$ENGINE" render --catalog "$tmpdir/dynamic-catalog.json" --output-root "$tmpdir/output" --portal-dir "$tmpdir/output")"
  [ "$(jq -r '.categories[0].tools | length' <<<"$dynamic_json")" -eq 2 ]
  [ "$(jq -r '.categories[0].tools[0].title' <<<"$dynamic_json")" = "Alpha" ]
  [ "$(jq -r '.categories[0].tools[1].count' <<<"$dynamic_json")" = "詳細を見る" ]
  [ "$(jq -r 'has("group")' <<<"$(jq -c '.categories[0].tools[0]' <<<"$dynamic_json")")" = "false" ]
  echo "PASS: registered blueprint discovers new instances with stable bytewise order"

  cat > "$tmpdir/output/count.html" <<'HTML'
<script type="application/json" id="items">{&quot;items&quot;:[1,2,3]}</script>
HTML
  cat > "$tmpdir/count-catalog.json" <<'JSON'
{"schemaVersion":1,"categories":[{"key":"count","label":"Count","group":"Test","icon":"list","sub":"test","blueprints":[{"kind":"items","label":"Items","icon":"list","desc":"test","dir":"","generator":"test-generator","unit":"項目","countFormat":"unit-count","discovery":{"artifactType":"count-page","root":"output-dir","glob":"count.html","matchKind":"file","titleSource":"blueprint-label","dirSource":"blueprint","instanceKeySource":"relative-path","sort":"relative-path-bytewise","embeddedScriptId":"items","countJsonPointer":"/items"}}]}]}
JSON
  count_json="$(node "$ENGINE" render --catalog "$tmpdir/count-catalog.json" --output-root "$tmpdir/output" --portal-dir "$tmpdir/output")"
  [ "$(jq -r '.categories[0].tools[0].count' <<<"$count_json")" = "3 項目 →" ]
  echo "PASS: entity-decoded embedded JSON count"

  jq 'del(.categories[0].blueprints[0].discovery.countJsonPointer)' "$tmpdir/count-catalog.json" > "$tmpdir/invalid.json"
  if node "$ENGINE" validate --catalog "$tmpdir/invalid.json" >/dev/null 2>&1; then
    echo "FAIL: incomplete unit-count contract was accepted" >&2
    return 1
  fi
  echo "PASS: incomplete unit-count contract rejected"

  jq 'del(.categories[0].blueprints[0].group)' "$DEFAULT_CATALOG" > "$tmpdir/missing-group.json"
  if node "$ENGINE" validate --catalog "$tmpdir/missing-group.json" >/dev/null 2>&1; then
    echo "FAIL: category with 4 or more blueprints accepted a missing group" >&2
    return 1
  fi
  echo "PASS: every blueprint in categories with 4 or more entries requires a group"

  for script in build-portal.sh test-e2e-portal.sh check-overview-consistency.sh; do
    case "$script" in
      build-portal.sh) script_path="$SCRIPT_DIR/../$script" ;;
      *) script_path="$SCRIPT_DIR/$script" ;;
    esac
    if rg -q 'get_(kind|future|derived|cross)_(label|icon|desc|dir|group)|CATEGORIES_JSON=.*"id"' "$script_path"; then
      echo "FAIL: duplicated portal card literals remain in $script" >&2
      return 1
    fi
  done
  echo "PASS: portal card literals are absent from the three consumers"

  # カタログが宣言する生成元が実在することを検査する。生成元は
  # このリポジトリのスキル・納品先へ配るスキル・generation-engine/scripts 配下の
  # スクリプトのいずれかであり、3つのどこにも無ければ誤りとみなす。
  local repo_root missing_generators gen
  repo_root="$SCRIPT_DIR/../../.."
  missing_generators=""
  while IFS= read -r gen; do
    [ -z "$gen" ] && continue
    [ "$gen" = "null" ] && continue
    [ -f "$repo_root/.claude/skills/$gen/SKILL.md" ] && continue
    [ -f "$repo_root/delivery-payload/templates/delivered-skills/$gen/SKILL.md" ] && continue
    if find "$repo_root/generation-engine/scripts" \( -name "$gen.sh" -o -name "$gen.mjs" \) 2>/dev/null | grep -q .; then
      continue
    fi
    missing_generators="$missing_generators $gen"
  done <<< "$(jq -r '[paths(scalars) as $p | select($p[-1]=="generator") | getpath($p)] | unique[]' "$DEFAULT_CATALOG")"
  if [ -n "$missing_generators" ]; then
    echo "FAIL: catalog declares generators that do not exist:$missing_generators" >&2
    return 1
  fi
  echo "PASS: every generator declared in the catalog exists"
  rm -rf "$tmpdir"
  trap - RETURN
}

case "${1:-}" in
  --capture-golden) capture_golden "$@" ;;
  --self-test) self_test ;;
  "")
    node "$ENGINE" validate --catalog "$DEFAULT_CATALOG"
    node "$ENGINE" compare --catalog "$DEFAULT_CATALOG" --output-root "$SCRIPT_DIR/../../samples" --portal-dir "$SCRIPT_DIR/../../samples/project-portal" --golden "$DEFAULT_GOLDEN"
    ;;
  *) usage; exit 1 ;;
esac
