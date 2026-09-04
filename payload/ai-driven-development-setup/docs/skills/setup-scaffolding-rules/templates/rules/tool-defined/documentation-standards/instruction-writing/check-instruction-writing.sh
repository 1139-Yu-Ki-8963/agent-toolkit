#!/usr/bin/env bash
# check-instruction-writing.sh — 指示書の書き方を検査する。
#
# 検査対象:
#   1. 対象プロジェクトの名前を含む固有名・識別子・パス
#   2. <名前空間>::<モジュール> 形の実装識別子
#   3. グローバル prh.yml が禁止する表記
#   4. 配布物の語彙一覧が定めるカタカナ音写と、引用されていない章名
#
# 対象プロジェクト名は、対象ルートの
# .claude/rules/always/project-context/rule.md から読む。project_name / projectName
# の設定行があればその値を優先し、無ければ先頭見出しの
# 「<名前> プロジェクトコンテキスト」から読む。名前を本体へ直書きしない。
#
# 使い方:
#   check-instruction-writing.sh <指示書.md> [--project-root <対象ルート>]
#     [--project-config <設定ファイル>] [--dictionary <prh.yml>]
#     [--terms <instruction-writing-terms.json>]
#   check-instruction-writing.sh --self-test
#
# 終了コード: 0=合格、1=不合格または入力不備、2=必要なツールが無く判定不能
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_TERMS_FILE="$SCRIPT_DIR/../../../references/instruction-writing-terms.json"

usage() {
  echo "Usage: $0 <指示書.md> [--project-root <対象ルート>] [--project-config <設定ファイル>] [--dictionary <prh.yml>] [--terms <terms.json>]" >&2
}

run_check() {
  local instruction_file="$1" project_root="$2" project_config="$3" dictionary="$4" terms_file="$5"

  if ! command -v node >/dev/null 2>&1; then
    echo "UNKNOWN: node が無いため判定できません" >&2
    return 2
  fi
  if [ ! -f "$instruction_file" ]; then
    echo "ERROR: 指示書が存在しません: $instruction_file" >&2
    return 1
  fi
  if [ -z "$project_config" ]; then
    project_config="$project_root/.claude/rules/always/project-context/rule.md"
  fi
  if [ ! -f "$project_config" ]; then
    echo "ERROR: プロジェクト名を読む設定が存在しません: $project_config" >&2
    return 1
  fi
  if [ ! -f "$dictionary" ]; then
    echo "[UNKNOWN] 辞書が存在しないため判定できません（参照したパス: ${dictionary}。配布先へ辞書が配置されていないか、--dictionary の指定先が誤っている可能性があります）" >&2
    return 2
  fi
  if [ ! -f "$terms_file" ]; then
    echo "[UNKNOWN] 配布物の語彙一覧が存在しないため判定できません（参照したパス: ${terms_file}。配布先へ語彙一覧が配置されていないか、--terms の指定先が誤っている可能性があります）" >&2
    return 2
  fi

  node - "$instruction_file" "$project_config" "$dictionary" "$terms_file" <<'NODE'
const fs = require('fs');

const [instructionPath, configPath, dictionaryPath, termsPath] = process.argv.slice(2);
const text = fs.readFileSync(instructionPath, 'utf8');
const config = fs.readFileSync(configPath, 'utf8');
const dictionary = fs.readFileSync(dictionaryPath, 'utf8');

let terms;
try {
  terms = JSON.parse(fs.readFileSync(termsPath, 'utf8'));
} catch (error) {
  console.error(`ERROR: 配布物の語彙一覧を読めません: ${error.message}`);
  process.exit(1);
}
if (!Array.isArray(terms.transliterations) || !Array.isArray(terms.quotedTemplateHeadings)) {
  console.error('ERROR: 配布物の語彙一覧の形式が不正です');
  process.exit(1);
}

function unquote(value) {
  const trimmed = value.trim();
  if ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
      (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
    return trimmed.slice(1, -1);
  }
  return trimmed;
}

function projectNameFromConfig(source) {
  const setting = source.match(/^\s*(?:project_name|projectName)\s*:\s*(.+?)\s*$/m);
  if (setting) return unquote(setting[1].replace(/\s+#.*$/, ''));
  const heading = source.match(/^#\s+(.+?)\s+プロジェクトコンテキスト(?:（[^\n]*）)?\s*$/m);
  return heading ? heading[1].trim() : '';
}

function nameVariants(name) {
  const values = new Set([name]);
  values.add(name.replace(/[\s-]+/g, '_'));
  values.add(name.replace(/[\s_-]+/g, ''));
  return [...values].filter(Boolean).sort((a, b) => b.length - a.length);
}

function maskJapaneseQuotes(line) {
  let previous;
  let masked = line;
  do {
    previous = masked;
    masked = masked.replace(/「[^「」]*」/g, match => ' '.repeat(match.length));
    masked = masked.replace(/『[^『』]*』/g, match => ' '.repeat(match.length));
  } while (masked !== previous);
  return masked;
}

function dictionaryRules(source) {
  const rules = [];
  let expected = '';
  const escapeRegex = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  for (const line of source.split(/\r?\n/)) {
    const expectedMatch = line.match(/^\s*-?\s*expected:\s*(.+?)\s*$/);
    if (expectedMatch) {
      expected = unquote(expectedMatch[1]);
      continue;
    }
    const patternMatch = line.match(/^\s*-\s*\/(.*)\/([a-z]*)\s*$/i);
    const literalMatch = patternMatch ? null : line.match(/^\s*-\s+([^:#][^:]*)\s*$/);
    if (!patternMatch && !literalMatch) continue;
    try {
      if (patternMatch) {
        const flags = patternMatch[2].includes('i') ? 'iu' : 'u';
        rules.push({expected, expression: patternMatch[1], regex: new RegExp(patternMatch[1], flags)});
      } else {
        const literal = unquote(literalMatch[1]);
        rules.push({expected, expression: literal, regex: new RegExp(escapeRegex(literal), 'u')});
      }
    } catch (error) {
      const shown = patternMatch ? `/${patternMatch[1]}/${patternMatch[2]}` : literalMatch[1];
      console.error(`ERROR: グローバル辞書の禁止表記を解釈できません: ${shown} (${error.message})`);
      process.exit(1);
    }
  }
  if (rules.length === 0) {
    console.error('ERROR: グローバル辞書から禁止表記を1件も読めません');
    process.exit(1);
  }
  return rules;
}

const projectName = projectNameFromConfig(config);
if (!projectName) {
  console.error(`ERROR: 設定からプロジェクト名を読めません: ${configPath}`);
  process.exit(1);
}

const variants = nameVariants(projectName);
const implementationIdentifier = /[A-Za-z_][A-Za-z0-9_.-]*::[A-Za-z_][A-Za-z0-9_.-]*/u;
const dictRules = dictionaryRules(dictionary);
const headingSet = new Set(terms.quotedTemplateHeadings);
const findings = [];

for (const [index, line] of text.split(/\r?\n/).entries()) {
  const lineNumber = index + 1;
  const lower = line.toLocaleLowerCase('ja-JP');
  for (const variant of variants) {
    if (lower.includes(variant.toLocaleLowerCase('ja-JP'))) {
      findings.push(`FAIL project-name ${instructionPath}:${lineNumber}: 設定から読んだプロジェクト名を含む表記（${variant}）`);
      break;
    }
  }

  const identifier = line.match(implementationIdentifier);
  if (identifier) {
    findings.push(`FAIL implementation-identifier ${instructionPath}:${lineNumber}: ${identifier[0]}`);
  }

  for (const rule of dictRules) {
    const match = line.match(rule.regex);
    if (match) {
      findings.push(`FAIL global-dictionary ${instructionPath}:${lineNumber}: ${match[0]}${rule.expected ? ` → ${rule.expected}` : ''}`);
    }
  }

  const prose = maskJapaneseQuotes(line);
  for (const heading of terms.quotedTemplateHeadings) {
    if (prose.includes(heading)) {
      findings.push(`FAIL unquoted-template-heading ${instructionPath}:${lineNumber}: ${heading}（「${heading}」と引用する）`);
    }
  }
  for (const item of terms.transliterations) {
    if (!item || typeof item.term !== 'string' || headingSet.has(item.term)) continue;
    if (prose.includes(item.term)) {
      findings.push(`FAIL transliteration ${instructionPath}:${lineNumber}: ${item.term} → ${item.replacement || '日本語で説明する'}`);
    }
  }
}

if (findings.length > 0) {
  console.log(findings.join('\n'));
  console.log(`SUMMARY: FAIL ${findings.length}件`);
  process.exit(1);
}
console.log('SUMMARY: PASS 0件');
NODE
}

SELF_TEST_TMP=""

cleanup_self_test() {
  [ -z "$SELF_TEST_TMP" ] || [ ! -e "$SELF_TEST_TMP" ] || rm -rf -- "$SELF_TEST_TMP"
}

self_test() {
  local pass=0 fail=0
  if ! SELF_TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-instruction-writing-self-test.XXXXXX" 2>/dev/null)" || [ -z "$SELF_TEST_TMP" ]; then
    echo "UNKNOWN: 一時ディレクトリを作れません" >&2
    return 2
  fi
  trap cleanup_self_test EXIT
  local tmp="$SELF_TEST_TMP"

  mkdir -p "$tmp/project/.claude/rules/always/project-context"
  printf '# 検査用配布物 プロジェクトコンテキスト\n' > "$tmp/project/.claude/rules/always/project-context/rule.md"
  cat > "$tmp/prh.yml" <<'YAML'
version: 1
rules:
  - expected: 確認する
    patterns:
      - /チェックする/i
  - expected: 分岐表
    patterns:
      - 決定木
YAML
  cat > "$tmp/terms.json" <<'JSON'
{
  "transliterations": [{"term":"バックログ", "replacement":"未着手の課題一覧"}],
  "quotedTemplateHeadings": ["リクエスト", "レスポンス", "バリデーション", "エンドポイント"]
}
JSON

  assert_case() {
    local name="$1" expected="$2" body="$3" file out rc
    file="$tmp/${name}.md"
    printf '%s\n' "$body" > "$file"
    if out="$(run_check "$file" "$tmp/project" "" "$tmp/prh.yml" "$tmp/terms.json" 2>&1)"; then rc=0; else rc=$?; fi
    if [ "$rc" -eq "$expected" ]; then
      echo "  [PASS] ${name}（exit=${rc}）"
      pass=$((pass + 1))
    else
      echo "  [FAIL] ${name}（期待=${expected} 実際=${rc} 出力=${out}）" >&2
      fail=$((fail + 1))
    fi
  }

  assert_case "通常の日本語" 0 '配布物の確認方法を日本語で記す。'
  assert_case "設定由来の固有名" 1 '検査用配布物の専用パスを直す。'
  assert_case "固有名を含む識別子" 1 '検査用配布物_adapterを直す。'
  assert_case "実装識別子" 1 'OrderDomain::CreateOrderを変更する。'
  assert_case "辞書の禁止語" 1 '結果をチェックする。'
  assert_case "辞書の固定文字列" 1 '決定木を使って分岐する。'
  assert_case "語彙一覧の音写" 1 'バックログへ追加する。'
  assert_case "引用した章名" 0 '配布物の「リクエスト」章へ入力項目を記す。'
  assert_case "地の文の章名" 1 'リクエストの入力項目を記す。'

  local missing_dictionary_file missing_dictionary_out missing_dictionary_rc
  missing_dictionary_file="$tmp/missing-dictionary.md"
  printf '%s\n' '配布物の確認方法を日本語で記す。' > "$missing_dictionary_file"
  if missing_dictionary_out="$(run_check "$missing_dictionary_file" "$tmp/project" "" "$tmp/存在しない辞書.yml" "$tmp/terms.json" 2>&1)"; then
    missing_dictionary_rc=0
  else
    missing_dictionary_rc=$?
  fi
  if [ "$missing_dictionary_rc" -eq 2 ] && printf '%s' "$missing_dictionary_out" | grep -qF '[UNKNOWN]'; then
    echo "  [PASS] 辞書欠落は判定不能（exit=2）"
    pass=$((pass + 1))
  else
    echo "  [FAIL] 辞書欠落を判定不能として区別できない（期待=2 実際=${missing_dictionary_rc} 出力=${missing_dictionary_out}）" >&2
    fail=$((fail + 1))
  fi

  local missing_terms_file missing_terms_out missing_terms_rc
  missing_terms_file="$tmp/missing-terms.md"
  printf '%s\n' '配布物の確認方法を日本語で記す。' > "$missing_terms_file"
  if missing_terms_out="$(run_check "$missing_terms_file" "$tmp/project" "" "$tmp/prh.yml" "$tmp/存在しない語彙一覧.json" 2>&1)"; then
    missing_terms_rc=0
  else
    missing_terms_rc=$?
  fi
  if [ "$missing_terms_rc" -eq 2 ] && printf '%s' "$missing_terms_out" | grep -qF '[UNKNOWN]'; then
    echo "  [PASS] 語彙一覧欠落は判定不能（exit=2）"
    pass=$((pass + 1))
  else
    echo "  [FAIL] 語彙一覧欠落を判定不能として区別できない（期待=2 実際=${missing_terms_rc} 出力=${missing_terms_out}）" >&2
    fail=$((fail + 1))
  fi

  echo "self-test: PASS=$pass FAIL=$fail"
  [ "$fail" -eq 0 ]
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

[ "$#" -ge 1 ] || { usage; exit 1; }
instruction_file="$1"
shift
project_root="$(pwd)"
project_config=""
dictionary="${HOME}/.claude/rules/always/review-checklist/text-dictionary/prh.yml"
terms_file="$DEFAULT_TERMS_FILE"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-root) [ "$#" -ge 2 ] || { usage; exit 1; }; project_root="$2"; shift 2 ;;
    --project-config) [ "$#" -ge 2 ] || { usage; exit 1; }; project_config="$2"; shift 2 ;;
    --dictionary) [ "$#" -ge 2 ] || { usage; exit 1; }; dictionary="$2"; shift 2 ;;
    --terms) [ "$#" -ge 2 ] || { usage; exit 1; }; terms_file="$2"; shift 2 ;;
    *) usage; exit 1 ;;
  esac
done

run_check "$instruction_file" "$project_root" "$project_config" "$dictionary" "$terms_file"
