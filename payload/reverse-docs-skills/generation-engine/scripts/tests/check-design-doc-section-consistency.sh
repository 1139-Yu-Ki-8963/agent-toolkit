#!/usr/bin/env bash
# 設計文書群の必須節・見出し順を検査する。
#
# 判定:
#   delivery-payload/references/design-doc-required-sections.json が、文書種別ごとの
#   必須節と正規の並びを定義する。必須節の欠落を FAIL（exit 1）、並び順の違いと
#   必須節定義のない文書を WARN（exit 0）として報告する。API詳細設計書と単体テスト
#   設計書7種別（conformance_triples_default が定める対象）はさらに、現行テンプレート
#   の全 ## 見出しと全表の列見出しへ完全一致することを検査する。欠落・余分・順序のみ
#   相違を区別して報告する（1-268）。多数決では判定しないため、規約に適合する少数の
#   文書を逸脱として扱わない。
#
# 使い方:
#   check-design-doc-section-consistency.sh <project_root>
#   check-design-doc-section-consistency.sh --self-test
#
# 環境変数:
#   SECTION_REQUIREMENTS_FILE  必須節定義JSONの差し替え先。定義だけを変更した
#                              場合の検証にも使用する。
#
# 終了コード:
#   0 = 必須節の欠落なし（WARNのみを含む）
#   1 = 必須節の欠落、入力不備、または定義JSONの形式不正
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DEFAULT_REQUIREMENTS_FILE="$REPO_ROOT/delivery-payload/references/design-doc-required-sections.json"
TEMPLATE_ROOT="$REPO_ROOT/delivery-payload/templates/リバース検証"
# 1-210の残件対応。detailフェーズの配置フォルダ名はハードコードせず、
# scaffold-design-unit.sh自身と同じくoutput-layout.jsonのunitPhaseDirNames
# を正として読む（自己テストのfixture展開先の突き合わせに使う）。
SELF_TEST_DETAIL_DIR_NAME="$(jq -r '.unitPhaseDirNames.detail' "$REPO_ROOT/delivery-payload/references/output-layout.json")"
API_DETAIL_TEMPLATE="$TEMPLATE_ROOT/API/API詳細設計書.md"
# shellcheck source=../output-layout.sh
. "$SCRIPT_DIR/../output-layout.sh"

# output-layout.jsonのキーと必須節定義で使う種別名の対応。必須節の中身はJSONだけに置く。
KIND_ROOTS="screenUnitRoot:screen apiUnitRoot:api tableUnitRoot:table batchUnitRoot:batch reportUnitRoot:report externalUnitRoot:external featureUnitRoot:feature"

# 全見出し・全表列見出しの完全一致検査（テンプレート適合検査）を課す対象。
# kind・basename・比較先テンプレートの絶対パスの3つ組。API詳細設計書の行は
# 既存の比較先テンプレート・判定条件のまま（1-268の触らない範囲）。
# 単体テスト設計書7種別は1-268で追加した。
conformance_triples_default() {
  printf '%s\t%s\t%s\n' \
    "api" "API詳細設計書.md" "$API_DETAIL_TEMPLATE" \
    "screen" "画面単体テスト設計書.md" "$TEMPLATE_ROOT/画面/テスト設計/画面単体テスト設計書.md" \
    "api" "API単体テスト設計書.md" "$TEMPLATE_ROOT/API/API単体テスト設計書.md" \
    "table" "テーブル単体テスト設計書.md" "$TEMPLATE_ROOT/テーブル/テーブル単体テスト設計書.md" \
    "batch" "バッチ単体テスト設計書.md" "$TEMPLATE_ROOT/バッチ/バッチ単体テスト設計書.md" \
    "report" "帳票単体テスト設計書.md" "$TEMPLATE_ROOT/帳票/帳票単体テスト設計書.md" \
    "external" "外部連携単体テスト設計書.md" "$TEMPLATE_ROOT/外部連携/外部連携単体テスト設計書.md" \
    "feature" "機能単体テスト設計書.md" "$TEMPLATE_ROOT/機能/機能単体テスト設計書.md"
}

requirements_file() {
  printf '%s\n' "${SECTION_REQUIREMENTS_FILE:-$DEFAULT_REQUIREMENTS_FILE}"
}

validate_requirements_file() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "ERROR: 必須節定義ファイルが存在しません: $file" >&2
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required to read the required-section definition" >&2
    return 1
  fi
  if ! jq -e '
    . as $root
    | ["screen", "api", "table", "batch", "report", "external", "feature"] as $kinds
    |
    .schemaVersion == 1 and
    (.documentTypes | type == "object") and
    ($kinds | all(. as $kind | ($root.documentTypes[$kind] | type == "object"))) and
    ([
      $root.documentTypes[]
      | to_entries[]
      | .value
      | (type == "object") and
        (.requiredSections | type == "array") and
        (.requiredSections | length > 0) and
        (.requiredSections | all(type == "string" and length > 0)) and
        ((.requiredSections | length) == (.requiredSections | unique | length))
    ] | all)
  ' "$file" >/dev/null; then
    echo "ERROR: 必須節定義ファイルの形式が不正です: $file" >&2
    return 1
  fi
}

# frontmatter（先頭行が --- のときの --- 〜 --- の範囲）を除いた本文を返す。
strip_frontmatter() {
  local file="$1"
  awk 'NR==1 && /^---$/ {skip=1; next} skip && /^---$/ {skip=0; next} !skip' "$file" 2>/dev/null
}

# ファイル本文（frontmatter除く）の ## 見出し一覧を、`## ` を除いて順番に返す。
extract_headings() {
  local file="$1"
  strip_frontmatter "$file" | awk '/^## / {sub(/^## /, ""); print}'
}

# 全表の列見出しを、所属する ## / ### 見出しと組にして順番どおり返す。
# データ行は執筆で増減するため比較せず、直後が区切り行である行だけを表見出しとみなす。
extract_table_headers() {
  local file="$1"
  strip_frontmatter "$file" | awk '
    /^## / { h2 = substr($0, 4); h3 = "" }
    /^### / { h3 = substr($0, 5) }
    {
      if ($0 ~ /^\|[|: -]+\|[[:space:]]*$/ && $0 ~ /---/ && previous ~ /^\|.*\|[[:space:]]*$/) {
        if (h2 != "") print h2 "\t" h3 "\t" previous
      }
      previous = $0
    }
  '
}

check_api_template_conformance() {
  local file="$1" template_headings actual_headings template_tables actual_tables rc=0
  if [ ! -f "$API_DETAIL_TEMPLATE" ]; then
    echo "ERROR: API詳細設計書テンプレートが存在しません: $API_DETAIL_TEMPLATE" >&2
    return 1
  fi

  template_headings="$(extract_headings "$API_DETAIL_TEMPLATE")"
  actual_headings="$(extract_headings "$file")"
  if [ "$template_headings" != "$actual_headings" ]; then
    echo "FAIL テンプレート見出し-不一致 ${file}: API詳細設計書の全節・順序・件数がテンプレートと一致しない"
    rc=1
  fi

  template_tables="$(extract_table_headers "$API_DETAIL_TEMPLATE")"
  actual_tables="$(extract_table_headers "$file")"
  if [ "$template_tables" != "$actual_tables" ]; then
    echo "FAIL テンプレート表列-不一致 ${file}: API詳細設計書の表の所属節・小節・列見出し・順序・件数がテンプレートと一致しない"
    rc=1
  fi
  return "$rc"
}

# 対象ルート一覧（種別名<TAB>絶対パス。実在するものだけ）を返す。
resolve_kind_roots() {
  local project_root="$1" layout_json pair root_key kind rel abs
  layout_json="$(resolve_output_layout "$project_root")" || return 1
  for pair in $KIND_ROOTS; do
    root_key="${pair%%:*}"
    kind="${pair#*:}"
    rel="$(output_layout_get "$layout_json" "$root_key" 2>/dev/null)" || continue
    [ -n "$rel" ] || continue
    abs="$project_root/$rel"
    [ -d "$abs" ] || continue
    printf '%s\t%s\n' "$kind" "$abs"
  done
}

has_definition() {
  local definition_file="$1" kind="$2" basename="$3"
  jq -e --arg kind "$kind" --arg basename "$basename" \
    '.documentTypes[$kind][$basename].requiredSections? | type == "array"' \
    "$definition_file" >/dev/null
}

required_sections() {
  local definition_file="$1" kind="$2" basename="$3"
  jq -r --arg kind "$kind" --arg basename "$basename" \
    '.documentTypes[$kind][$basename].requiredSections[]' "$definition_file"
}

check_document() {
  local definition_file="$1" kind="$2" basename="$3" file="$4"
  local headings section position previous_position=0 missing=0 out_of_order=0
  headings="$(extract_headings "$file")"

  while IFS= read -r section; do
    [ -n "$section" ] || continue
    position="$(awk -v section="$section" '$0 == section { print NR; exit }' <<< "$headings")"
    if [ -z "$position" ]; then
      echo "FAIL 必須節-欠落 ${file}: 文書種別（${kind}/${basename}）に必須節「${section}」がない"
      missing=1
      continue
    fi
    if [ "$position" -le "$previous_position" ]; then
      out_of_order=1
    fi
    previous_position="$position"
  done < <(required_sections "$definition_file" "$kind" "$basename")

  if [ "$out_of_order" -eq 1 ]; then
    echo "WARN 見出し順-相違 ${file}: 同一役割（${basename}）の必須節の並びが定義と異なる"
  fi
  return "$missing"
}

run_check() {
  local project_root="$1" definition_file kind_roots rc=0 undefined_seen="" checked_count=0
  definition_file="$(requirements_file)"

  if [ ! -d "$project_root" ]; then
    echo "ERROR: ディレクトリが存在しません: $project_root" >&2
    return 1
  fi
  validate_requirements_file "$definition_file" || return 1
  kind_roots="$(resolve_kind_roots "$project_root")" || return 1

  local kind kind_root c_kind c_basename c_template
  local -a check_args conformance_triples
  conformance_triples=()
  while IFS=$'\t' read -r c_kind c_basename c_template; do
    [ -n "$c_template" ] || continue
    conformance_triples+=("$c_kind" "$c_basename" "$c_template")
  done < <(conformance_triples_default)

  check_args=("$definition_file" "$DEFAULT_REQUIREMENTS_FILE" "${#conformance_triples[@]}")
  check_args+=("${conformance_triples[@]}")
  while IFS=$'\t' read -r kind kind_root; do
    [ -n "$kind_root" ] || continue
    check_args+=("$kind" "$kind_root")
  done <<EOF
$kind_roots
EOF

  # 定義・文書ごとに jq/awk/find を起動すると、build-portal の再帰self-testで
  # 同じ定義JSONを数百回読み直す。出力順・文言・終了コードを保ったまま、定義を
  # 1回だけ読み、全対象文書を1つのNodeプロセスで走査する。
  node - "$project_root" "${check_args[@]}" <<'NODE'
const fs = require("fs");
const path = require("path");

const [projectRoot, definitionFile, defaultDefinitionFile, conformanceArgCountStr, ...rest] = process.argv.slice(2);
const conformanceArgCount = Number(conformanceArgCountStr);
const conformanceArgs = rest.slice(0, conformanceArgCount);
const kindRoots = rest.slice(conformanceArgCount);
const definition = JSON.parse(fs.readFileSync(definitionFile, "utf8"));
let failed = false;
let checkedCount = 0;
const undefinedSeen = new Set();

// kind・basenameの組から、全見出し・全表列見出しの完全一致検査（テンプレート
// 適合検査）を課す対象を引く。値は比較先テンプレートの絶対パス。
const conformanceTemplates = new Map();
for (let index = 0; index < conformanceArgs.length; index += 3) {
  const c_kind = conformanceArgs[index];
  const c_basename = conformanceArgs[index + 1];
  const c_template = conformanceArgs[index + 2];
  conformanceTemplates.set(`${c_kind}/${c_basename}`, c_template);
}
const conformanceHeadingsCache = new Map();
const conformanceTablesCache = new Map();

// 2つの見出し・表列の並びを多重集合として比較し、欠落・余分・順序のみ相違を
// 区別する。「不一致」ひとくくりにせず、読み手が何を直せばよいか分かる形で返す。
function classifyListDiff(templateList, actualList) {
  const count = (list) => {
    const map = new Map();
    for (const item of list) map.set(item, (map.get(item) || 0) + 1);
    return map;
  };
  const templateCount = count(templateList);
  const actualCount = count(actualList);
  const missing = [];
  for (const [item, num] of templateCount) {
    const diff = num - (actualCount.get(item) || 0);
    for (let i = 0; i < diff; i += 1) missing.push(item);
  }
  const extra = [];
  for (const [item, num] of actualCount) {
    const diff = num - (templateCount.get(item) || 0);
    for (let i = 0; i < diff; i += 1) extra.push(item);
  }
  const orderOnly = missing.length === 0 && extra.length === 0
    && JSON.stringify(templateList) !== JSON.stringify(actualList);
  return { missing, extra, orderOnly, equal: missing.length === 0 && extra.length === 0 && !orderOnly };
}

function describeListDiff(diff) {
  const parts = [];
  if (diff.missing.length) parts.push(`欠落: ${diff.missing.join(" / ")}`);
  if (diff.extra.length) parts.push(`余分: ${diff.extra.join(" / ")}`);
  if (diff.orderOnly) parts.push("順序のみ相違");
  return parts.join("、");
}

function listMarkdownFiles(root) {
  const files = [];
  function visit(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const target = path.join(dir, entry.name);
      if (entry.isDirectory()) visit(target);
      else if (entry.isFile() && entry.name.endsWith(".md")) files.push(target);
    }
  }
  visit(root);
  return files.sort((left, right) => Buffer.compare(Buffer.from(left), Buffer.from(right)));
}

function bodyLines(file) {
  const lines = fs.readFileSync(file, "utf8").split(/\n/);
  if (lines[0] !== "---") return lines;
  let index = 1;
  while (index < lines.length && lines[index] !== "---") index += 1;
  return index < lines.length ? lines.slice(index + 1) : [];
}

function headings(file) {
  return bodyLines(file).filter((line) => line.startsWith("## ")).map((line) => line.slice(3));
}

function tableHeaders(file) {
  const result = [];
  let h2 = "";
  let h3 = "";
  let previous = "";
  for (const line of bodyLines(file)) {
    if (line.startsWith("## ")) { h2 = line.slice(3); h3 = ""; }
    if (line.startsWith("### ")) h3 = line.slice(4);
    if (/^\|[|: \-]+\|[\s]*$/.test(line) && line.includes("---") && /^\|.*\|[\s]*$/.test(previous)) {
      if (h2 !== "") result.push(`${h2}\t${h3}\t${previous}`);
    }
    previous = line;
  }
  return result;
}

for (let index = 0; index < kindRoots.length; index += 2) {
  const kind = kindRoots[index];
  const root = kindRoots[index + 1];
  for (const file of listMarkdownFiles(root)) {
    checkedCount += 1;
    const basename = path.basename(file);
    const documentDefinition = definition.documentTypes?.[kind]?.[basename];
    if (!documentDefinition || !Array.isArray(documentDefinition.requiredSections)) {
      const key = `${kind}/${basename}`;
      if (!undefinedSeen.has(key)) {
        process.stdout.write(`WARN 必須節定義-なし ${file}: 文書種別（${key}）の必須節定義がない\n`);
        undefinedSeen.add(key);
      }
      continue;
    }

    const actualHeadings = headings(file);
    let previousPosition = 0;
    let outOfOrder = false;
    for (const section of documentDefinition.requiredSections) {
      const found = actualHeadings.indexOf(section);
      if (found === -1) {
        process.stdout.write(`FAIL 必須節-欠落 ${file}: 文書種別（${kind}/${basename}）に必須節「${section}」がない\n`);
        failed = true;
        continue;
      }
      const position = found + 1;
      if (position <= previousPosition) outOfOrder = true;
      previousPosition = position;
    }
    if (outOfOrder) {
      process.stdout.write(`WARN 見出し順-相違 ${file}: 同一役割（${basename}）の必須節の並びが定義と異なる\n`);
    }

    const conformanceKey = `${kind}/${basename}`;
    if (definitionFile === defaultDefinitionFile && conformanceTemplates.has(conformanceKey)) {
      const conformanceTemplate = conformanceTemplates.get(conformanceKey);
      if (!fs.existsSync(conformanceTemplate)) {
        process.stderr.write(`ERROR: テンプレートが存在しません（${conformanceKey}）: ${conformanceTemplate}\n`);
        failed = true;
      } else {
        if (!conformanceHeadingsCache.has(conformanceTemplate)) {
          conformanceHeadingsCache.set(conformanceTemplate, headings(conformanceTemplate));
        }
        if (!conformanceTablesCache.has(conformanceTemplate)) {
          conformanceTablesCache.set(conformanceTemplate, tableHeaders(conformanceTemplate));
        }
        const templateHeadings = conformanceHeadingsCache.get(conformanceTemplate);
        const templateTables = conformanceTablesCache.get(conformanceTemplate);

        const headingDiff = classifyListDiff(templateHeadings, actualHeadings);
        if (!headingDiff.equal) {
          process.stdout.write(`FAIL テンプレート見出し-不一致 ${file}: ${conformanceKey}の全節・順序・件数がテンプレートと一致しない（${describeListDiff(headingDiff)}）\n`);
          failed = true;
        }

        const tableDiff = classifyListDiff(templateTables, tableHeaders(file));
        if (!tableDiff.equal) {
          process.stdout.write(`FAIL テンプレート表列-不一致 ${file}: ${conformanceKey}の表の所属節・小節・列見出し・順序・件数がテンプレートと一致しない（${describeListDiff(tableDiff)}）\n`);
          failed = true;
        }
      }
    }
  }
}

if (checkedCount === 0) {
  process.stderr.write(`ERROR: 検査対象の設計文書が0件です: project_root=${projectRoot}\n`);
  process.exit(1);
}
process.exit(failed ? 1 : 0);
NODE
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

SELF_TEST_DIRS=()

cleanup_self_test_dirs() {
  local dir
  for dir in "${SELF_TEST_DIRS[@]}"; do
    [ -n "$dir" ] || continue
    case "$dir" in
      "${TMPDIR:-/tmp}"/design-doc-consistency-self-test.*|"$REPO_ROOT"/.design-doc-consistency-self-test.*)
        [ ! -e "$dir" ] || rm -rf -- "$dir"
        ;;
    esac
  done
}

self_test() {
  local pass=0 fail=0

  # HUP/INT/TERMは既存trapを上書きせず、終了時の削除だけをEXITへ一元化する。
  # 外部中断でshellが終了する場合もEXIT trapが登録済みfixtureを削除する。
  trap cleanup_self_test_dirs EXIT

  assert_eq() {
    local name="$1" want="$2" actual="$3"
    if [ "$want" = "$actual" ]; then
      echo "  [PASS] $name"
      pass=$((pass + 1))
    else
      echo "  [FAIL] ${name}（期待 ${want}・実際 ${actual}）"
      fail=$((fail + 1))
    fi
  }

  assert_contains() {
    local name="$1" needle="$2" haystack="$3"
    case "$haystack" in
      *"$needle"*)
        echo "  [PASS] $name"
        pass=$((pass + 1))
        ;;
      *)
        echo "  [FAIL] ${name}（出力: ${haystack}）"
        fail=$((fail + 1))
        ;;
    esac
  }

  assert_not_contains() {
    local name="$1" needle="$2" haystack="$3"
    case "$haystack" in
      *"$needle"*)
        echo "  [FAIL] ${name}（出力: ${haystack}）"
        fail=$((fail + 1))
        ;;
      *)
        echo "  [PASS] $name"
        pass=$((pass + 1))
        ;;
    esac
  }

  assert_invalid_requirements() {
    local name="$1" file="$2" rc=0
    validate_requirements_file "$file" >/dev/null 2>&1 || rc=$?
    assert_eq "$name" 1 "$rc"
  }

  write_layout_override() {
    mkdir -p "$1/api"
    cat > "$1/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "apiUnitRoot": "api" } }
JSON
  }

  write_requirements() {
    cat > "$1" <<'JSON'
{
  "schemaVersion": 1,
  "documentTypes": {
    "screen": {},
    "api": {
      "API詳細設計書.md": {
        "requiredSections": ["§1 API概要", "§2 リクエスト", "§3 レスポンス"]
      }
    },
    "table": {},
    "batch": {},
    "report": {},
    "external": {},
    "feature": {}
  }
}
JSON
  }

  write_api_doc() {
    local file="$1" headings="$2"
    mkdir -p "$(dirname "$file")"
    {
      printf '%s\n\n' '# 注文API API詳細設計書'
      printf '%s\n\n本文\n' "$headings"
    } > "$file"
  }

  # 課題1-196回帰: 文書の置き場ではなくプロジェクトルートを要求し、0件を合格にしない。
  local tmp_root_arg req_root_arg out_wrong_root rc_wrong_root usage_out
  if ! tmp_root_arg="$(mktemp -d "${TMPDIR:-/tmp}/design-doc-consistency-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp_root_arg" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  SELF_TEST_DIRS+=("$tmp_root_arg")
  req_root_arg="$tmp_root_arg/requirements.json"
  write_layout_override "$tmp_root_arg"; write_requirements "$req_root_arg"
  write_api_doc "$tmp_root_arg/api/A/API詳細設計書.md" $'## §1 API概要\n## §2 リクエスト\n## §3 レスポンス'
  out_wrong_root="$(SECTION_REQUIREMENTS_FILE="$req_root_arg" run_check "$tmp_root_arg/api" 2>&1)"; rc_wrong_root=$?
  assert_eq "課題1-196-文書ディレクトリ指定は非0" 1 "$rc_wrong_root"
  assert_contains "課題1-196-0件を明示" '検査対象の設計文書が0件' "$out_wrong_root"
  usage_out="$(bash "$0" 2>&1)" || true
  assert_contains "課題1-196-引数名はproject_root" '<project_root>' "$usage_out"
  assert_not_contains "課題1-196-旧引数名を表示しない" '<docs_root>' "$usage_out"
  rm -rf "$tmp_root_arg"

  # 検収1: 必須節を欠いた文書はFAILかつ非0。
  local tmp_1 req_1 out_1 rc_1
  if ! tmp_1="$(mktemp -d "${TMPDIR:-/tmp}/design-doc-consistency-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp_1" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  SELF_TEST_DIRS+=("$tmp_1")
  req_1="$tmp_1/requirements.json"
  write_layout_override "$tmp_1"; write_requirements "$req_1"
  write_api_doc "$tmp_1/api/A/API詳細設計書.md" $'## §1 API概要\n## §2 リクエスト'
  out_1="$(SECTION_REQUIREMENTS_FILE="$req_1" run_check "$tmp_1")"; rc_1=$?
  assert_eq "検収1-終了コード" 1 "$rc_1"
  assert_contains "検収1-必須節欠落をFAIL" 'FAIL 必須節-欠落' "$out_1"
  rm -rf "$tmp_1"

  # 検収2: 規約適合の2件が少数でもFAILにせず、欠落した5件だけをFAILにする。
  local tmp_2 req_2 out_2 rc_2 i
  if ! tmp_2="$(mktemp -d "${TMPDIR:-/tmp}/design-doc-consistency-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp_2" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  SELF_TEST_DIRS+=("$tmp_2")
  req_2="$tmp_2/requirements.json"
  write_layout_override "$tmp_2"; write_requirements "$req_2"
  for i in 1 2; do write_api_doc "$tmp_2/api/good-${i}/API詳細設計書.md" $'## §1 API概要\n## §2 リクエスト\n## §3 レスポンス'; done
  for i in 1 2 3 4 5; do write_api_doc "$tmp_2/api/bad-${i}/API詳細設計書.md" $'## §1 API概要\n## §2 リクエスト'; done
  out_2="$(SECTION_REQUIREMENTS_FILE="$req_2" run_check "$tmp_2")"; rc_2=$?
  assert_eq "検収2-終了コード" 1 "$rc_2"
  if [[ "$out_2" != *"good-1"* && "$out_2" != *"good-2"* && "$out_2" == *"bad-5"* ]]; then
    echo "  [PASS] 検収2-少数派の適合文書をFAILにしない"
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検収2-少数派の適合文書をFAILにしない（出力: ${out_2}）"
    fail=$((fail + 1))
  fi
  rm -rf "$tmp_2"

  # 検収3: 必須節が揃う文書だけなら無FAIL・exit 0。
  local tmp_3 req_3 out_3 rc_3
  if ! tmp_3="$(mktemp -d "${TMPDIR:-/tmp}/design-doc-consistency-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp_3" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  SELF_TEST_DIRS+=("$tmp_3")
  req_3="$tmp_3/requirements.json"
  write_layout_override "$tmp_3"; write_requirements "$req_3"
  write_api_doc "$tmp_3/api/A/API詳細設計書.md" $'## §1 API概要\n## §2 リクエスト\n## §3 レスポンス'
  write_api_doc "$tmp_3/api/B/API詳細設計書.md" $'## §1 API概要\n## §2 リクエスト\n## §3 レスポンス'
  out_3="$(SECTION_REQUIREMENTS_FILE="$req_3" run_check "$tmp_3")"; rc_3=$?
  assert_eq "検収3-終了コード" 0 "$rc_3"
  assert_eq "検収3-出力0件" '' "$out_3"
  rm -rf "$tmp_3"

  # 検収4: 定義だけに必須節を追加すると、スクリプトを変えずに新たな欠落を検出する。
  local tmp_4 req_4 out_4 rc_4
  if ! tmp_4="$(mktemp -d "${TMPDIR:-/tmp}/design-doc-consistency-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp_4" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  SELF_TEST_DIRS+=("$tmp_4")
  req_4="$tmp_4/requirements.json"
  write_layout_override "$tmp_4"; write_requirements "$req_4"
  write_api_doc "$tmp_4/api/A/API詳細設計書.md" $'## §1 API概要\n## §2 リクエスト\n## §3 レスポンス'
  jq '.documentTypes.api["API詳細設計書.md"].requiredSections += ["§4 追加必須節"]' "$req_4" > "$req_4.next" && mv "$req_4.next" "$req_4"
  out_4="$(SECTION_REQUIREMENTS_FILE="$req_4" run_check "$tmp_4")"; rc_4=$?
  assert_eq "検収4-終了コード" 1 "$rc_4"
  assert_contains "検収4-定義追加の欠落を検出" '§4 追加必須節' "$out_4"
  rm -rf "$tmp_4"

  # 検収5: 必須節が揃い順だけ違う場合はWARN・exit 0。
  local tmp_5 req_5 out_5 rc_5
  if ! tmp_5="$(mktemp -d "${TMPDIR:-/tmp}/design-doc-consistency-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp_5" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  SELF_TEST_DIRS+=("$tmp_5")
  req_5="$tmp_5/requirements.json"
  write_layout_override "$tmp_5"; write_requirements "$req_5"
  write_api_doc "$tmp_5/api/A/API詳細設計書.md" $'## §1 API概要\n## §2 リクエスト\n## §3 レスポンス'
  write_api_doc "$tmp_5/api/B/API詳細設計書.md" $'## §2 リクエスト\n## §1 API概要\n## §3 レスポンス'
  out_5="$(SECTION_REQUIREMENTS_FILE="$req_5" run_check "$tmp_5")"; rc_5=$?
  assert_eq "検収5-終了コード" 0 "$rc_5"
  assert_contains "検収5-順序相違をWARN" 'WARN 見出し順-相違' "$out_5"
  rm -rf "$tmp_5"

  # 追加回帰1: 定義JSONの構造をfail closedで検証する。
  local tmp_validation req_validation
  if ! tmp_validation="$(mktemp -d "${TMPDIR:-/tmp}/design-doc-consistency-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp_validation" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  SELF_TEST_DIRS+=("$tmp_validation")
  req_validation="$tmp_validation/requirements.json"
  write_requirements "$req_validation"
  jq 'del(.documentTypes.screen)' "$req_validation" > "$tmp_validation/kind-missing.json"
  jq '.documentTypes.screen = []' "$req_validation" > "$tmp_validation/kind-not-object.json"
  jq '.documentTypes.api["API詳細設計書.md"] = []' "$req_validation" > "$tmp_validation/document-not-object.json"
  jq '.documentTypes.api["API詳細設計書.md"].requiredSections = []' "$req_validation" > "$tmp_validation/sections-empty.json"
  jq '.documentTypes.api["API詳細設計書.md"].requiredSections[1] = ""' "$req_validation" > "$tmp_validation/section-empty-string.json"
  jq '.documentTypes.api["API詳細設計書.md"].requiredSections += ["§1 API概要"]' "$req_validation" > "$tmp_validation/section-duplicate.json"
  assert_invalid_requirements "追加回帰1-種別欠落を拒否" "$tmp_validation/kind-missing.json"
  assert_invalid_requirements "追加回帰1-種別の非objectを拒否" "$tmp_validation/kind-not-object.json"
  assert_invalid_requirements "追加回帰1-文書定義の非objectを拒否" "$tmp_validation/document-not-object.json"
  assert_invalid_requirements "追加回帰1-requiredSections空配列を拒否" "$tmp_validation/sections-empty.json"
  assert_invalid_requirements "追加回帰1-requiredSections空文字を拒否" "$tmp_validation/section-empty-string.json"
  assert_invalid_requirements "追加回帰1-requiredSections重複を拒否" "$tmp_validation/section-duplicate.json"
  rm -rf "$tmp_validation"

  # 追加回帰2: 欠落と順序相違が併存すればFAILとWARNを両方出す。
  local tmp_both req_both out_both rc_both
  if ! tmp_both="$(mktemp -d "${TMPDIR:-/tmp}/design-doc-consistency-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp_both" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  SELF_TEST_DIRS+=("$tmp_both")
  req_both="$tmp_both/requirements.json"
  write_layout_override "$tmp_both"; write_requirements "$req_both"
  write_api_doc "$tmp_both/api/A/API詳細設計書.md" $'## §2 リクエスト\n## §1 API概要'
  out_both="$(SECTION_REQUIREMENTS_FILE="$req_both" run_check "$tmp_both")"; rc_both=$?
  assert_eq "追加回帰2-終了コード" 1 "$rc_both"
  assert_contains "追加回帰2-欠落FAILを出力" 'FAIL 必須節-欠落' "$out_both"
  assert_contains "追加回帰2-順序WARNも出力" 'WARN 見出し順-相違' "$out_both"
  rm -rf "$tmp_both"

  # 追加回帰3: 未定義basenameは同一kind/basenameにつき1回だけWARN・exit 0。
  local tmp_undefined req_undefined out_undefined rc_undefined undefined_count
  if ! tmp_undefined="$(mktemp -d "${TMPDIR:-/tmp}/design-doc-consistency-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp_undefined" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  SELF_TEST_DIRS+=("$tmp_undefined")
  req_undefined="$tmp_undefined/requirements.json"
  write_layout_override "$tmp_undefined"; write_requirements "$req_undefined"
  write_api_doc "$tmp_undefined/api/A/API詳細設計書.md" $'## §1 API概要\n## §2 リクエスト\n## §3 レスポンス'
  write_api_doc "$tmp_undefined/api/A/補足設計書.md" $'## 補足'
  write_api_doc "$tmp_undefined/api/B/補足設計書.md" $'## 補足'
  out_undefined="$(SECTION_REQUIREMENTS_FILE="$req_undefined" run_check "$tmp_undefined")"; rc_undefined=$?
  undefined_count="$(printf '%s\n' "$out_undefined" | grep -c '^WARN 必須節定義-なし ' || true)"
  assert_eq "追加回帰3-終了コード" 0 "$rc_undefined"
  assert_eq "追加回帰3-未定義警告は1回" 1 "$undefined_count"
  rm -rf "$tmp_undefined"

  # 検収6: build-portal.shの連鎖は欠落で失敗し、修復後は成功する。
  local tmp_6 req_6 out_6_fail out_6_clean rc_6_fail rc_6_clean
  # build-portal.sh は出力先の親ディレクトリにsymlinkがないことを検査する。
  # macOSのTMPDIRは /var 経由であり、この契約に抵触するため、物理パスである
  # リポジトリ直下に短命のfixtureを置く。
  if ! tmp_6="$(mktemp -d "$REPO_ROOT/.design-doc-consistency-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp_6" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  SELF_TEST_DIRS+=("$tmp_6")
  req_6="$tmp_6/requirements.json"
  mkdir -p "$tmp_6/target"
  write_layout_override "$tmp_6"; write_requirements "$req_6"
  write_api_doc "$tmp_6/api/A/API詳細設計書.md" $'## §1 API概要\n## §2 リクエスト'
  out_6_fail="$(SECTION_REQUIREMENTS_FILE="$req_6" bash "$SCRIPT_DIR/../build-portal.sh" "$tmp_6/target" "$tmp_6" "$tmp_6/portal" 2>&1)"; rc_6_fail=$?
  write_api_doc "$tmp_6/api/A/API詳細設計書.md" $'## §1 API概要\n## §2 リクエスト\n## §3 レスポンス'
  out_6_clean="$(SECTION_REQUIREMENTS_FILE="$req_6" bash "$SCRIPT_DIR/../build-portal.sh" "$tmp_6/target" "$tmp_6" "$tmp_6/portal" 2>&1)"; rc_6_clean=$?
  assert_eq "検収6-欠落時の終了コード" 1 "$rc_6_fail"
  assert_contains "検収6-欠落を生成連鎖が報告" 'FAIL 必須節-欠落' "$out_6_fail"
  assert_eq "検収6-修復後の終了コード" 0 "$rc_6_clean"
  rm -rf "$tmp_6"

  # 課題1-223回帰: 改訂した全種別テンプレートと検査4の定義を突合する。
  # 廃止済み資料名の一覧は docs/references/retired-terms.json（正本）を読む。
  # 4語をここへ個別にハードコードしない（docs/tasks/廃止した名前の一覧が
  # 散らばり起票が古い名前を指す問題を直す指示書.md）。
  local template_root related_count evidence_ref_count old_heading_count old_move_count unit_chapter_count decision_heading_count api_related_rows stale_skill_route_count
  local retired_terms_file retired_pattern
  template_root="$REPO_ROOT/delivery-payload/templates/リバース検証"
  retired_terms_file="$REPO_ROOT/docs/references/retired-terms.json"
  retired_pattern="$(jq -r '[.terms[].term] | join("|")' "$retired_terms_file")"
  related_count="$(grep -R -l -E '^## (§[0-9]+ )?関連資料$' "$template_root" --include='*.md' | wc -l | tr -d ' ')"
  evidence_ref_count="$(grep -R -l -E "$retired_pattern" "$template_root" --include='*.md' | wc -l | tr -d ' ')"
  old_heading_count="$(grep -R -l -E '^## (§[0-9]+ )?要確認事項一覧$' "$template_root" --include='*.md' | wc -l | tr -d ' ')"
  old_move_count="$(grep -R -l -F '要確認事項一覧へ移す' "$template_root" --include='*.md' | wc -l | tr -d ' ')"
  unit_chapter_count="$(grep -R -l -E '^## §[0-9]+ .*単体テスト設計書$' "$template_root" --include='*.md' | wc -l | tr -d ' ')"
  decision_heading_count="$(grep -c '^### 12\.5 設計判断とその理由$' "$template_root/API/API詳細設計書.md")"
  api_related_rows="$(grep -E -c '^\| (API詳細設計書|API単体テスト設計書) \|' "$template_root/API/API基本設計書.md")"
  stale_skill_route_count="$(grep -E -h '完了条件: §(11|13) が埋まっている|要確認（現場確認事項）|付録 A・B|\^## 関連資料|根拠を記録する資料の「確定できなかった事項」' \
    "$REPO_ROOT/.claude/skills/generating-api-detail-design-for-reverse-docs/SKILL.md" \
    "$REPO_ROOT/.claude/skills/generating-feature-design-for-reverse-docs/SKILL.md" \
    "$REPO_ROOT/.claude/skills/generating-reverse-basic-design/SKILL.md" | wc -l | tr -d ' ')"
  assert_eq "課題1-223-関連資料節を持つテンプレート数" 27 "$related_count"
  assert_eq "課題1-223-廃止済み資料名を含む参照の残存数" 0 "$evidence_ref_count"
  assert_eq "課題1-223-要確認事項節の残存数" 0 "$old_heading_count"
  assert_eq "課題1-223-旧回送文言の残存数" 0 "$old_move_count"
  assert_eq "課題1-223-単体テスト設計書独立章の残存数" 0 "$unit_chapter_count"
  assert_eq "課題1-223-設計判断見出しの番号付き件数" 1 "$decision_heading_count"
  assert_eq "課題1-223-API基本設計書の個別関連資料行数" 2 "$api_related_rows"
  assert_eq "課題1-223-生成スキルの旧回送契約残存数" 0 "$stale_skill_route_count"

  local tmp_7 out_7 rc_7 kind basename source_dir target_dir
  if ! tmp_7="$(mktemp -d "${TMPDIR:-/tmp}/design-doc-consistency-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp_7" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  SELF_TEST_DIRS+=("$tmp_7")
  cat > "$tmp_7/output-layout.json" <<'JSON'
{
  "specVersion": 1,
  "layout": {
    "screenUnitRoot": "screen",
    "apiUnitRoot": "api",
    "tableUnitRoot": "table",
    "batchUnitRoot": "batch",
    "reportUnitRoot": "report",
    "externalUnitRoot": "external",
    "featureUnitRoot": "feature"
  }
}
JSON
  while IFS=$'\t' read -r kind basename source_dir; do
    target_dir="$tmp_7/$kind/fixture"
    mkdir -p "$target_dir"
    cp "$template_root/$source_dir/$basename" "$target_dir/$basename"
  done <<'EOF'
screen	画面詳細設計書.md	画面/詳細設計
api	API詳細設計書.md	API
table	テーブル定義書.md	テーブル
batch	バッチ詳細設計書.md	バッチ
report	帳票詳細設計書.md	帳票
external	外部連携詳細設計書.md	外部連携
feature	機能設計書.md	機能
EOF
  out_7="$(run_check "$tmp_7")"; rc_7=$?
  assert_eq "課題1-223-改訂テンプレートの検査4終了コード" 0 "$rc_7"
  assert_eq "課題1-223-改訂テンプレートの検査4出力0件" '' "$out_7"
  rm -rf "$tmp_7"

  # 課題1-201回帰: scaffoldで合成API詳細設計書を3件生成し、現行テンプレートの
  # 全節と全表列を保つこと、および節・列の逸脱をそれぞれ検出することを確認する。
  local tmp_201 out_201 rc_201 generated_201_count bad_heading bad_columns out_bad_heading out_bad_columns rc_bad_heading rc_bad_columns
  # scaffold-design-unit.sh は出力先の親にsymlinkがある場合を拒否する。macOSの
  # TMPDIRは /var 経由になるため、検収6と同じく物理パスのリポジトリ直下を使う。
  if ! tmp_201="$(mktemp -d "$REPO_ROOT/.design-doc-consistency-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp_201" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  SELF_TEST_DIRS+=("$tmp_201")
  write_layout_override "$tmp_201"
  for i in 1 2 3; do
    bash "$SCRIPT_DIR/../scaffold-design-unit.sh" api detail "$tmp_201" "fixture-${i}" "合成API ${i}" "$REPO_ROOT/delivery-payload/templates/リバース検証" >/dev/null
  done
  generated_201_count="$(find "$tmp_201/api" -type f -name 'API詳細設計書.md' | wc -l | tr -d ' ')"
  out_201="$(run_check "$tmp_201")"; rc_201=$?
  assert_eq "課題1-201-合成API詳細設計書の生成件数" 3 "$generated_201_count"
  assert_eq "課題1-201-3件のテンプレート一致終了コード" 0 "$rc_201"
  assert_eq "課題1-201-3件のテンプレート一致出力0件" '' "$out_201"

  bad_heading="$tmp_201/api/api-fixture-1/$SELF_TEST_DETAIL_DIR_NAME/API詳細設計書.md"
  sed -i.bak 's/^## §5 ロジック$/## §5 ロジック設計/' "$bad_heading"
  out_bad_heading="$(run_check "$tmp_201")"; rc_bad_heading=$?
  assert_eq "課題1-201-節構成の逸脱を非0にする" 1 "$rc_bad_heading"
  assert_contains "課題1-201-節構成の逸脱を報告" 'FAIL テンプレート見出し-不一致' "$out_bad_heading"
  mv "$bad_heading.bak" "$bad_heading"

  bad_columns="$tmp_201/api/api-fixture-2/$SELF_TEST_DETAIL_DIR_NAME/API詳細設計書.md"
  sed -i.bak '1,/^| 名前 | 型 | 必須 | 有効な範囲 | NULL許容 | 初期値 | 桁と精度 | 制約 |$/s/^| 名前 | 型 | 必須 | 有効な範囲 | NULL許容 | 初期値 | 桁と精度 | 制約 |$/| 名前 | 型 | 必須 | 制約 |/' "$bad_columns"
  out_bad_columns="$(run_check "$tmp_201")"; rc_bad_columns=$?
  assert_eq "課題1-201-表列の逸脱を非0にする" 1 "$rc_bad_columns"
  assert_contains "課題1-201-表列の逸脱を報告" 'FAIL テンプレート表列-不一致' "$out_bad_columns"
  mv "$bad_columns.bak" "$bad_columns"
  rm -rf "$tmp_201"

  # 課題1-268: 単体テスト設計書（API単体テスト設計書で代表）にも様式への完全一致
  # 検査を課す。様式どおりの入力で合格になること、欠落・余分・順序のみ相違を
  # 区別して報告すること、表列の相違も検出することを確認する。
  local tmp_268 doc_268 out_268_ok rc_268_ok
  if ! tmp_268="$(mktemp -d "$REPO_ROOT/.design-doc-consistency-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp_268" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  SELF_TEST_DIRS+=("$tmp_268")
  write_layout_override "$tmp_268"
  bash "$SCRIPT_DIR/../scaffold-design-unit.sh" api test "$tmp_268" "fixture-268" "合成API 268" "$REPO_ROOT/delivery-payload/templates/リバース検証" >/dev/null
  doc_268="$tmp_268/api/api-fixture-268/テスト設計/API単体テスト設計書.md"
  # 同じphaseで生成されるAPIテスト設計書.mdは本検収の対象外（1-268の対象は
  # 単体テスト設計書のみ）。必須節定義-なしのWARNが混ざるのを避けるため取り除く。
  rm -f "$tmp_268/api/api-fixture-268/テスト設計/APIテスト設計書.md"
  cp "$doc_268" "$doc_268.orig"

  out_268_ok="$(run_check "$tmp_268")"; rc_268_ok=$?
  assert_eq "検収268-様式どおりの終了コード" 0 "$rc_268_ok"
  assert_eq "検収268-様式どおりの出力0件" '' "$out_268_ok"

  # 欠落: 節をまるごと削除する。
  local out_268_missing rc_268_missing
  cp "$doc_268.orig" "$doc_268"
  sed -i.bak '/^## §5 異常系$/d' "$doc_268"
  out_268_missing="$(run_check "$tmp_268")"; rc_268_missing=$?
  assert_eq "検収268-欠落の終了コード" 1 "$rc_268_missing"
  assert_contains "検収268-欠落をFAILで報告" 'FAIL テンプレート見出し-不一致' "$out_268_missing"
  assert_contains "検収268-欠落の内訳を報告" '欠落: §5 異常系' "$out_268_missing"
  assert_not_contains "検収268-欠落ケースは順序相違を報告しない" '順序のみ相違' "$out_268_missing"
  rm -f "$doc_268.bak"

  # 余分: 様式にない節を追加する。
  local out_268_extra rc_268_extra
  awk '/^## §6 境界値$/ { print "## §99 追加節" } { print }' "$doc_268.orig" > "$doc_268"
  out_268_extra="$(run_check "$tmp_268")"; rc_268_extra=$?
  assert_eq "検収268-余分の終了コード" 1 "$rc_268_extra"
  assert_contains "検収268-余分をFAILで報告" 'FAIL テンプレート見出し-不一致' "$out_268_extra"
  assert_contains "検収268-余分の内訳を報告" '余分: §99 追加節' "$out_268_extra"
  assert_not_contains "検収268-余分ケースは欠落を報告しない" '欠落:' "$out_268_extra"

  # 順序のみ相違: §1節と§2節を丸ごと（見出しと表を一緒に）入れ替える。見出し行
  # だけを入れ替えると表が元の節に取り残され、表列側にも欠落・余分が生じて
  # しまうため、節全体を単位に動かして純粋な順序違いにする。
  local out_268_order rc_268_order swap_before swap_block1 swap_block2 swap_after
  swap_before="$tmp_268/.swap-before"
  swap_block1="$tmp_268/.swap-block1"
  swap_block2="$tmp_268/.swap-block2"
  swap_after="$tmp_268/.swap-after"
  sed '/^## §1 テスト観点$/,$d' "$doc_268.orig" > "$swap_before"
  sed -n '/^## §1 テスト観点$/,/^## §2 テストケース一覧$/p' "$doc_268.orig" | sed '$d' > "$swap_block1"
  sed -n '/^## §2 テストケース一覧$/,/^## §3 入力条件$/p' "$doc_268.orig" | sed '$d' > "$swap_block2"
  sed -n '/^## §3 入力条件$/,$p' "$doc_268.orig" > "$swap_after"
  cat "$swap_before" "$swap_block2" "$swap_block1" "$swap_after" > "$doc_268"
  rm -f "$swap_before" "$swap_block1" "$swap_block2" "$swap_after"
  out_268_order="$(run_check "$tmp_268")"; rc_268_order=$?
  assert_eq "検収268-順序相違の終了コード" 1 "$rc_268_order"
  assert_contains "検収268-順序相違をFAILで報告" 'FAIL テンプレート見出し-不一致' "$out_268_order"
  assert_contains "検収268-順序相違の内訳を報告" '順序のみ相違' "$out_268_order"
  assert_not_contains "検収268-順序相違ケースは欠落を報告しない" '欠落:' "$out_268_order"
  assert_not_contains "検収268-順序相違ケースは余分を報告しない" '余分:' "$out_268_order"

  # 表列相違: §3 入力条件の表の列見出しを変える（課題1-201のbad_columnsと同じ深さ）。
  local out_268_columns rc_268_columns
  sed 's/^| ケースのキー | 引数・事前状態 | 値 | 由来する詳細設計書の章 |$/| 名前 | 値 |/' "$doc_268.orig" > "$doc_268"
  out_268_columns="$(run_check "$tmp_268")"; rc_268_columns=$?
  assert_eq "検収268-表列相違の終了コード" 1 "$rc_268_columns"
  assert_contains "検収268-表列相違をFAILで報告" 'FAIL テンプレート表列-不一致' "$out_268_columns"

  rm -f "$doc_268.orig"
  rm -rf "$tmp_268"

  echo "self-test: $pass PASS, $fail FAIL"
  [ "$fail" -eq 0 ]
}

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi
  if [ "$#" -ne 1 ]; then
    echo "使い方: $(basename "$0") <project_root>" >&2
    echo "        $(basename "$0") --self-test" >&2
    exit 1
  fi
  run_check "$1"
  exit $?
}

main "$@"
