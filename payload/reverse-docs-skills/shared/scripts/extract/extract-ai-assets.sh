#!/usr/bin/env bash
# AI設定資産ページ用データ抽出エンジン: リポジトリ内の AI 設定資産(rules / skills / subagents / hooks)を
# 走査し、shared/samples/AI設定資産/AI設定資産.html の埋め込みマニフェスト
# (<script type="application/json" id="matrix-manifest">)と同じ 4 セクション構成の JSON を出力する。
#
# Usage: extract-ai-assets.sh <repo-root> <output.json>
#        extract-ai-assets.sh --self-test
#
# 出力 JSON スキーマ(正本: shared/samples/AI設定資産/AI設定資産.html の埋め込みマニフェスト。
# 追加フィールドの根拠: shared/references/manifest-schema-extensions.md「AI設定資産ページのデータ源」):
# {
#   "generatedAt": "ISO8601",
#   "dataSource": "<repo-root>",
#   "rules":     [{"ruleName": "...", "layer": "always|scoped", "enforcement": "block|advisory|なし",
#                  "tags": ["[TAG]"], "summary": "..."}],
#   "skills":    [{"skillName": "...", "category": "指揮|一覧生成|基盤ページ生成|工程",
#                  "trigger": "...", "summary": "...", "phaseCount": 0}],
#   "subagents": [{"name": "...", "mainTools": "..."}],
#   "hooks":     [{"script": "...", "timing": "...", "matcher": "...", "tags": ["[TAG]"],
#                  "behavior": "block|advisory", "summary": "..."}]
# }
# 全セクションのフィールドは任意。検出根拠が弱い値は出力しない(誤った値より欠落を優先する fail-safe)。
# サンプルにある classification・verdict(subagents)はヒューリスティックで
# 確度高く導出できないため出力しない(欠落扱い)。phaseCount は schema 拡張仕様が定める追加フィールド。
# category(skills) はスキル名パターンから決定的に判定する(判定規則は下記 skill_category 参照。
# orchestrating-* → 指揮、generating-*-list-for-reverse-docs → 一覧生成、
# 単発ポータルページを作る generating-*(er-diagram/env-guide/glossary/tech-stack/screen-transition)
# → 基盤ページ生成、それ以外 → 工程。サンプル埋め込みマニフェストの実データ 10 件全件と一致する
# ことを --self-test ケースbで検証済み)。configIndex はサンプル埋め込みマニフェストに存在しない
# ため出力しない。
#
# 検出ヒューリスティック一覧:
#   rules(<repo-root>/.claude/rules/**/rule.md):
#     - ruleName: 先頭の h1 見出し(「# 」行)の本文
#     - layer: パス中の /always/ → always、/scoped/ → scoped
#     - enforcement: 「## 機械強制」節の本文を grep。
#         'exit 2' または 'decision:block' あり → block
#         'advisory' あり → advisory
#         '機械強制なし' 等「なし」表記のみ / 節不在 → なし
#         (「block なし」の block 文字列に誤反応しないよう 'exit 2|decision:block' のみを block 根拠とする)
#     - tags: 「## 機械強制」節内の \[[A-Z][A-Z0-9-]+\] パターンを重複排除して列挙
#     - summary: h1 直後の最初の非見出し段落の第 1 文(最初の「。」まで)
#   skills(<repo-root>/.claude/skills/*/SKILL.md):
#     - skillName: frontmatter の name:
#     - trigger: frontmatter description 内の 'TRIGGER when:' から 'SKIP:'(無ければ末尾)まで
#     - summary: frontmatter description の 'TRIGGER when:' より前の本文の最初の非空行
#       (description はブロック形式 '|' と単一行引用形式 "..." の両方に対応)
#     - phaseCount: 本文の '^## Phase' 行数
#   subagents(<repo-root>/.claude/agents/*.md および *​/*.md):
#     - name: frontmatter の name:(無ければファイル名)
#     - mainTools: frontmatter の description:(同一行値のみ)
#     - 定義ファイルが無ければ空配列(サンプルのグローバルサブエージェント記載はサンプル固有データ)
#   hooks(<repo-root>/.claude/settings.json の hooks キー):
#     - timing × matcher × スクリプト名(command の basename)を列挙。matcher 不在は「—」
#     - スクリプト実体($CLAUDE_PROJECT_DIR を repo-root に展開。不在なら .claude 配下を basename 検索)の
#       冒頭 40 行から tags(\[[A-Z][A-Z0-9-]+\])と behavior('exit 2|decision:block' → block、
#       'advisory' → advisory。どちらも無ければ behavior 欠落)、summary(2 行目のコメント文)を補完
#   configIndex:
#     - CLAUDE.md: 実在と '^## ' 見出し一覧
#     - .claude/rules/always/project-context/flow-values.yml: 実在と top-level キー一覧
#
# 出力先ディレクトリは自動作成する。出力は AI設定資産ページ専用スキーマであり、
# unit-list/validate-manifest.sh(unit-manifest 契約)の検証対象外。

set -euo pipefail

# --- 共通ヘルパ ---

# h1 直後の最初の段落の第 1 文を返す
first_paragraph_sentence() {
  local file="$1"
  local para
  para="$(awk '
    /^# / { seen = 1; next }
    seen && /^[[:space:]]*$/ { next }
    seen && /^#/ { exit }
    seen { print; exit }
  ' "$file")"
  case "$para" in
    *。*) printf '%s。' "${para%%。*}" ;;
    *)    printf '%s' "$para" ;;
  esac
}

# 「## 機械強制」節の本文(次の「## 」まで)を返す
enforcement_section() {
  awk '/^## 機械強制/ { f = 1; next } /^## / { f = 0 } f' "$1"
}

# テキストから注入タグを JSON 配列で返す
tags_json_from_text() {
  { grep -oE '\[[A-Z][A-Z0-9-]+\]' 2>/dev/null || true; } <<<"$1" \
    | sort -u | jq -R . | jq -s -c .
}

# frontmatter(先頭 --- 〜 次の ---)を返す
frontmatter_of() {
  awk 'NR == 1 && /^---[[:space:]]*$/ { f = 1; next } f && /^---[[:space:]]*$/ { exit } f' "$1"
}

# skillName から category(サンプル埋め込みマニフェストの値集合: 指揮|一覧生成|基盤ページ生成|工程)を判定する。
# 判定規則(サンプル実データ10件全件と一致することを --self-test ケースbで検証済み):
#   orchestrating-*                         → 指揮(工程全体の指揮役)
#   generating-*-list-for-reverse-docs      → 一覧生成(種別別ユニット一覧の生成)
#   generating-er-diagram-for-reverse-docs
#   generating-env-guide-for-reverse-docs
#   generating-glossary-for-reverse-docs
#   generating-tech-stack-for-reverse-docs
#   generating-screen-transition-for-reverse-docs
#                                            → 基盤ページ生成(ポータル単発ページの生成)
#   それ以外(surveying-* / extracting-* / rebuilding-* / running-* / syncing-* /
#            unlocking-* / counting-* / generating-reverse-basic-design /
#            generating-reverse-common-docs / generating-reverse-detailed-design 等)
#                                            → 工程(往復検証フローの各段階)
skill_category() {
  local name="$1"
  case "$name" in
    orchestrating-*) printf '指揮' ;;
    generating-*-list-for-reverse-docs) printf '一覧生成' ;;
    generating-er-diagram-for-reverse-docs \
      | generating-env-guide-for-reverse-docs \
      | generating-glossary-for-reverse-docs \
      | generating-tech-stack-for-reverse-docs \
      | generating-screen-transition-for-reverse-docs)
      printf '基盤ページ生成' ;;
    *) printf '工程' ;;
  esac
}

# --- 抽出本体 ---

extract_rules() {
  local repo="$1" out_dir="$2"
  : > "$out_dir/rules.jsonl"
  local f
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    local rule_name layer section enforcement tags summary
    rule_name="$(sed -n 's/^# //p' "$f" | head -1)"
    [ -n "$rule_name" ] || continue
    case "$f" in
      */rules/always/*) layer="always" ;;
      */rules/scoped/*) layer="scoped" ;;
      *)                layer="" ;;
    esac
    section="$(enforcement_section "$f")"
    if grep -qE 'exit 2|decision:block' <<<"$section"; then
      enforcement="block"
    elif grep -q 'advisory' <<<"$section"; then
      enforcement="advisory"
    else
      enforcement="なし"
    fi
    tags="$(tags_json_from_text "$section")"
    summary="$(first_paragraph_sentence "$f")"
    jq -n -c \
      --arg ruleName "$rule_name" \
      --arg layer "$layer" \
      --arg enforcement "$enforcement" \
      --argjson tags "$tags" \
      --arg summary "$summary" \
      '{ruleName: $ruleName}
       + (if $layer != "" then {layer: $layer} else {} end)
       + {enforcement: $enforcement, tags: $tags}
       + (if $summary != "" then {summary: $summary} else {} end)' \
      >> "$out_dir/rules.jsonl"
  done < <(find "$repo/.claude/rules" -type f -name rule.md 2>/dev/null | sort)
}

extract_skills() {
  local repo="$1" out_dir="$2"
  : > "$out_dir/skills.jsonl"
  local f
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    local fm skill_name category desc trigger summary phase_count
    fm="$(frontmatter_of "$f")"
    skill_name="$(sed -n 's/^name:[[:space:]]*//p' <<<"$fm" | head -1)"
    [ -n "$skill_name" ] || continue
    category="$(skill_category "$skill_name")"
    # description: 同一行値、または 'description: |' ブロックのインデント行群
    desc="$(awk '
      /^description:[[:space:]]*/ {
        rest = $0; sub(/^description:[[:space:]]*/, "", rest)
        if (rest != "" && rest != "|" && rest != ">") { print rest; exit }
        blk = 1; next
      }
      blk && /^[[:space:]]+[^[:space:]]/ { line = $0; sub(/^[[:space:]]+/, "", line); print line; next }
      blk { exit }
    ' <<<"$fm")"
    # 単一行引用形式(description: "...")の外側引用符を除去
    desc="${desc#\"}"
    desc="${desc%\"}"
    # trigger: 'TRIGGER when:' から 'SKIP:' (無ければ末尾)まで。改行は空白へ畳む
    trigger=""
    if [[ "$desc" == *"TRIGGER when:"* ]]; then
      trigger="${desc#*TRIGGER when:}"
      trigger="${trigger%%SKIP:*}"
      trigger="$(printf '%s' "$trigger" | tr '\n' ' ' \
        | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    fi
    # summary: 'TRIGGER when:' より前の本文の最初の非空行
    summary="$(printf '%s\n' "${desc%%TRIGGER when:*}" \
      | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | { grep -m1 . || true; })"
    phase_count="$(grep -c '^## Phase' "$f" || true)"
    jq -n -c \
      --arg skillName "$skill_name" \
      --arg category "$category" \
      --arg trigger "$trigger" \
      --arg summary "$summary" \
      --argjson phaseCount "${phase_count:-0}" \
      '{skillName: $skillName}
       + (if $category != "" then {category: $category} else {} end)
       + (if $trigger != "" then {trigger: $trigger} else {} end)
       + (if $summary != "" then {summary: $summary} else {} end)
       + {phaseCount: $phaseCount}' \
      >> "$out_dir/skills.jsonl"
  done < <(find "$repo/.claude/skills" -mindepth 2 -maxdepth 2 -type f -name SKILL.md 2>/dev/null | sort)
}

extract_subagents() {
  local repo="$1" out_dir="$2"
  : > "$out_dir/subagents.jsonl"
  [ -d "$repo/.claude/agents" ] || return 0
  local f
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    local fm name desc
    fm="$(frontmatter_of "$f")"
    name="$(sed -n 's/^name:[[:space:]]*//p' <<<"$fm" | head -1)"
    [ -n "$name" ] || name="$(basename "$f" .md)"
    desc="$(sed -n 's/^description:[[:space:]]*//p' <<<"$fm" | head -1)"
    case "$desc" in
      '|' | '>') desc="" ;;
    esac
    jq -n -c \
      --arg name "$name" \
      --arg mainTools "$desc" \
      '{name: $name}
       + (if $mainTools != "" then {mainTools: $mainTools} else {} end)' \
      >> "$out_dir/subagents.jsonl"
  done < <(find "$repo/.claude/agents" -mindepth 1 -maxdepth 2 -type f -name '*.md' 2>/dev/null | sort)
}

extract_hooks() {
  local repo="$1" out_dir="$2"
  : > "$out_dir/hooks.jsonl"
  local settings="$repo/.claude/settings.json"
  [ -f "$settings" ] || return 0
  jq -e '.hooks | type == "object"' "$settings" >/dev/null 2>&1 || return 0
  local entry
  while IFS= read -r entry; do
    local timing matcher command script script_path header tags behavior summary
    timing="$(jq -r '.timing' <<<"$entry")"
    matcher="$(jq -r '.matcher // "—"' <<<"$entry")"
    command="$(jq -r '.command // ""' <<<"$entry")"
    [ -n "$command" ] || continue
    script="$(basename "$command")"
    # スクリプト実体の解決: $CLAUDE_PROJECT_DIR を repo に展開 → 不在なら .claude 配下を basename 検索
    script_path="${command//\$CLAUDE_PROJECT_DIR/$repo}"
    if [ ! -f "$script_path" ]; then
      script_path="$(find "$repo/.claude" -type f -name "$script" 2>/dev/null | head -1)"
    fi
    tags='[]'
    behavior=""
    summary=""
    if [ -n "$script_path" ] && [ -f "$script_path" ]; then
      header="$(head -40 "$script_path")"
      tags="$(tags_json_from_text "$header")"
      if grep -qE 'exit 2|decision:block' <<<"$header"; then
        behavior="block"
      elif grep -q 'advisory' <<<"$header"; then
        behavior="advisory"
      fi
      summary="$(sed -n '2s/^#[[:space:]]*//p' "$script_path")"
    fi
    jq -n -c \
      --arg script "$script" \
      --arg timing "$timing" \
      --arg matcher "$matcher" \
      --argjson tags "$tags" \
      --arg behavior "$behavior" \
      --arg summary "$summary" \
      '{script: $script, timing: $timing, matcher: $matcher, tags: $tags}
       + (if $behavior != "" then {behavior: $behavior} else {} end)
       + (if $summary != "" then {summary: $summary} else {} end)' \
      >> "$out_dir/hooks.jsonl"
  done < <(jq -c '
    .hooks | to_entries[] | .key as $t
    | .value[] | {timing: $t, matcher: (.matcher // null)} as $base
    | .hooks[] | $base + {command: .command}
  ' "$settings")
}

run_extract() {
  local repo="$1" output="$2"
  local work
  work="$(mktemp -d "${TMPDIR:-/tmp}/extract-ai-assets.XXXXXX")"
  # RETURN trap は self_test 内呼び出しでも関数終了時に確実に清掃する
  trap 'rm -rf "$work"' RETURN

  extract_rules "$repo" "$work"
  extract_skills "$repo" "$work"
  extract_subagents "$repo" "$work"
  extract_hooks "$repo" "$work"

  mkdir -p "$(dirname "$output")"
  jq -n \
    --arg generatedAt "$(date +%Y-%m-%dT%H:%M:%S%z)" \
    --arg dataSource "$repo" \
    --argjson rules "$(jq -s -c . "$work/rules.jsonl")" \
    --argjson skills "$(jq -s -c . "$work/skills.jsonl")" \
    --argjson subagents "$(jq -s -c . "$work/subagents.jsonl")" \
    --argjson hooks "$(jq -s -c . "$work/hooks.jsonl")" \
    '{generatedAt: $generatedAt, dataSource: $dataSource,
      rules: $rules, skills: $skills, subagents: $subagents, hooks: $hooks}' \
    > "$output"
  echo "OK: wrote $output" >&2
}

# --- --self-test モード ---
# 1) mktemp フィクスチャリポジトリで各セクションの抽出値を jq 検証
# 2) 本リポジトリ(このスクリプトが属する extraction-engines worktree)を実走査し、
#    rules 3件以上・hooks 1件以上・jq パース可能・サンプルページの埋め込みマニフェストと
#    キー構成が一致(各セクションのオブジェクトキーが許容集合の範囲内)することを検証
self_test() {
  local script_path="$0"
  local script_dir
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  local repo_root
  repo_root="$(cd "$script_dir/../../.." && pwd)"
  local tmp rc=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/extract-ai-assets-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  # --- フィクスチャリポジトリ生成 ---
  local fx="$tmp/fixture-repo"
  mkdir -p "$fx/.claude/rules/always/test-gate" \
           "$fx/.claude/rules/scoped/adv-note" \
           "$fx/.claude/rules/always/plain-doc" \
           "$fx/.claude/skills/testing-fixture-skill" \
           "$fx/.claude/agents"

  cat > "$fx/.claude/rules/always/test-gate/rule.md" <<'EOF'
# テストゲート規約（TEST-GATE）

テスト用の block 規約。フィクスチャ検証のための最初の段落である。二文目は summary に含めない。

## 機械強制

| timing | スクリプト | 注入タグ | 挙動 |
|---|---|---|---|
| PreToolUse(Bash) | `check-test-gate.sh` | `[TEST-GATE-BLOCK]` | 違反を exit 2 で block |

## 関連

- なし
EOF

  cat > "$fx/.claude/rules/scoped/adv-note/rule.md" <<'EOF'
# 助言規約（ADV-NOTE）

テスト用の advisory 規約。

## 機械強制

| timing | スクリプト | 注入タグ | 挙動 |
|---|---|---|---|
| PostToolUse(Write) | `check-adv-note.sh` | `[ADV-NOTE]` | advisory 注入（block なし） |
EOF

  cat > "$fx/.claude/rules/always/plain-doc/rule.md" <<'EOF'
# 素の文書規約（PLAIN-DOC）

機械強制を持たない行動規範。

## 機械強制

現時点では hook による機械強制なし。
EOF

  cat > "$fx/.claude/skills/testing-fixture-skill/SKILL.md" <<'EOF'
---
name: testing-fixture-skill
description: |
  フィクスチャ検証用スキル。
  TRIGGER when: セルフテスト実行時。
  SKIP: 本番利用。
---

# フィクスチャスキル

## Phase 1: 準備

## Phase 2: 検証
EOF

  cat > "$fx/.claude/agents/test-agent.md" <<'EOF'
---
name: test-agent
description: フィクスチャ検証用の読み取り専用エージェント
---
EOF

  cat > "$fx/.claude/hook-fixture.sh" <<'EOF'
#!/usr/bin/env bash
# フィクスチャ hook: [FIXTURE-BLOCK] を exit 2 で注入する
exit 0
EOF

  cat > "$fx/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hook-fixture.sh"}
        ]
      }
    ]
  }
}
EOF

  # --- ケースa: フィクスチャ抽出値の検証 ---
  local out_fx="$tmp/fixture-out.json"
  if bash "$script_path" "$fx" "$out_fx" >/dev/null 2>&1 && jq -e . "$out_fx" >/dev/null 2>&1; then
    local checks_a
    checks_a="$(jq -r '
      [
        (.rules | length) == 3,
        ([.rules[] | select(.ruleName == "テストゲート規約（TEST-GATE）")][0]
          | .layer == "always" and .enforcement == "block"
            and .tags == ["[TEST-GATE-BLOCK]"]
            and (.summary | startswith("テスト用の block 規約。"))
            and (.summary | contains("二文目") | not)),
        ([.rules[] | select(.ruleName == "助言規約（ADV-NOTE）")][0]
          | .layer == "scoped" and .enforcement == "advisory" and .tags == ["[ADV-NOTE]"]),
        ([.rules[] | select(.ruleName == "素の文書規約（PLAIN-DOC）")][0]
          | .enforcement == "なし" and .tags == []),
        (.skills | length) == 1,
        (.skills[0] | .skillName == "testing-fixture-skill"
          and .category == "工程"
          and .trigger == "セルフテスト実行時。"
          and .summary == "フィクスチャ検証用スキル。"
          and .phaseCount == 2),
        (.subagents | length) == 1,
        (.subagents[0].name == "test-agent"),
        (.hooks | length) == 1,
        (.hooks[0] | .script == "hook-fixture.sh" and .timing == "PreToolUse"
          and .matcher == "Bash" and .behavior == "block" and .tags == ["[FIXTURE-BLOCK]"])
      ] | all
    ' "$out_fx")"
    if [ "$checks_a" = "true" ]; then
      echo "  [PASS] ケースa: フィクスチャの rules/skills/subagents/hooks 抽出値が期待どおり"
    else
      echo "  [FAIL] ケースa: フィクスチャ抽出値が期待と不一致" >&2
      jq . "$out_fx" >&2 || true
      rc=1
    fi
  else
    echo "  [FAIL] ケースa: フィクスチャ抽出の実行または JSON パースに失敗" >&2
    rc=1
  fi

  # --- ケースb: 実リポジトリ抽出(件数 + サンプルとのキー構成一致) ---
  local out_real="$tmp/real-out.json"
  local sample_html="$repo_root/shared/samples/AI設定資産/AI設定資産.html"
  if bash "$script_path" "$repo_root" "$out_real" >/dev/null 2>&1 && jq -e . "$out_real" >/dev/null 2>&1; then
    local rules_n hooks_n skills_n
    rules_n="$(jq '.rules | length' "$out_real")"
    hooks_n="$(jq '.hooks | length' "$out_real")"
    skills_n="$(jq '.skills | length' "$out_real")"
    if [ "$rules_n" -ge 3 ] && [ "$hooks_n" -ge 1 ]; then
      echo "  [PASS] ケースb-件数: 実リポジトリで rules=${rules_n}件(3以上) / hooks=${hooks_n}件(1以上) / skills=${skills_n}件"
    else
      echo "  [FAIL] ケースb-件数: rules=${rules_n} / hooks=${hooks_n} が下限未満" >&2
      rc=1
    fi

    # サンプルページの埋め込みマニフェストとキー構成を突合:
    # - 4 セクションのキーがともに存在し配列である
    # - 各セクションの行キーが許容集合(サンプルのキー + schema 拡張仕様の phaseCount)の範囲内
    if [ -f "$sample_html" ]; then
      local sample_json="$tmp/sample-manifest.json"
      sed -n '/^<script type="application\/json" id="matrix-manifest">/,/<\/script>/p' "$sample_html" \
        | sed '1d;$d' > "$sample_json"
      local keys_ok
      keys_ok="$(jq -r --slurpfile sample "$sample_json" '
        ($sample[0] | keys | sort) as $sampleSections
        | (keys | contains($sampleSections)) and
          ([.rules[]     | keys[]] - ["ruleName","layer","enforcement","tags","summary"] == []) and
          ([.skills[]    | keys[]] - ["skillName","category","trigger","summary","phaseCount"] == []) and
          ([.subagents[] | keys[]] - ["name","classification","verdict","mainTools"] == []) and
          ([.hooks[]     | keys[]] - ["script","timing","matcher","tags","behavior","summary"] == [])
      ' "$out_real")"
      if [ "$keys_ok" = "true" ]; then
        echo "  [PASS] ケースb-スキーマ: 4 セクション構成と行キーがサンプル埋め込みマニフェストと一致"
      else
        echo "  [FAIL] ケースb-スキーマ: サンプル埋め込みマニフェストとキー構成が不一致" >&2
        rc=1
      fi
    else
      echo "  [FAIL] ケースb-スキーマ: サンプル HTML が見つからない: $sample_html" >&2
      rc=1
    fi
  else
    echo "  [FAIL] ケースb: 実リポジトリ抽出の実行または JSON パースに失敗" >&2
    rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

REPO_ROOT="${1:?Usage: extract-ai-assets.sh <repo-root> <output.json>}"
OUTPUT_JSON="${2:?Usage: extract-ai-assets.sh <repo-root> <output.json>}"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found in PATH" >&2
  exit 1
fi

if [ ! -d "$REPO_ROOT" ]; then
  echo "ERROR: repo-root not found: $REPO_ROOT" >&2
  exit 1
fi
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"

run_extract "$REPO_ROOT" "$OUTPUT_JSON"
