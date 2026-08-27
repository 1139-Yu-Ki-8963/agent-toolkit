#!/usr/bin/env bash
# AI設定資産ページ用データ抽出エンジン: リポジトリ内の AI 設定資産(rules / skills / subagents / hooks)を
# 走査し、generation-engine/samples/AI設定資産/AI設定資産.html の埋め込みマニフェスト
# (<script type="application/json" id="matrix-manifest">)と同じ 4 セクション構成の JSON を出力する。
#
# Usage: extract-ai-assets.sh <repo-root> <output.json>
#        extract-ai-assets.sh --self-test
#
# 出力 JSON スキーマ(正本: generation-engine/samples/AI設定資産/AI設定資産.html の埋め込みマニフェスト。
# 追加フィールドの根拠: delivery-payload/references/manifest-schema-extensions.md「AI設定資産ページのデータ源」):
# {
#   "generatedAt": "ISO8601",
#   "dataSource": "<repo-root>",
#   "rules":     [{"ruleName": "...", "layer": "always|scoped|generated",
#                  "declaredEnforcement": "block|advisory|なし", "mechanicalEnforcement": false,
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
#     - declaredEnforcement: generated ruleは所有index、既存ruleは「## 機械強制」節を読む。
#         'exit 2' または 'decision:block' あり → block
#         'advisory' あり → advisory
#         '機械強制なし' 等「なし」表記のみ / 節不在 → なし
#         (「block なし」の block 文字列に誤反応しないよう 'exit 2|decision:block' のみを block 根拠とする)
#     - mechanicalEnforcement: generated ruleは常にfalse。既存ruleは機械強制節に記載された
#         hook scriptが.claude/settings.jsonへ実際に登録されている場合だけtrue。
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

# 配布対象から外すスキル（このリポジトリ専用・非公開）の名前は、環境変数で
# 指定された除外定義ファイルの .names から読む。名前をこのスクリプトへ直接
# 書き込まない。環境変数が未設定、定義ファイルまたは jq が無い場合は除外を
# 適用しない（fail-open）。
DEFAULT_AI_ASSETS_FORBIDDEN_NAMES_FILE=""
AI_ASSETS_FORBIDDEN_NAMES_FILE="${PAYLOAD_FORBIDDEN_NAMES_FILE:-$DEFAULT_AI_ASSETS_FORBIDDEN_NAMES_FILE}"
is_forbidden_skill_name() {
  local name="$1"
  if [ -f "$AI_ASSETS_FORBIDDEN_NAMES_FILE" ] && command -v jq >/dev/null 2>&1; then
    jq -e --arg n "$name" '(.names // []) | index($n) != null' "$AI_ASSETS_FORBIDDEN_NAMES_FILE" >/dev/null 2>&1
    return $?
  fi
  return 1
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
  local generated_index="$repo/.claude/rules/generated/index.json"
  if [ -e "$generated_index" ]; then
    jq -e '
      .generatedBy == "generate-rules-from-common-docs.sh"
      and .schemaVersion == 1
      and (.entries | type == "array")
      and ([.entries[].key] | length == (unique | length))
    ' "$generated_index" >/dev/null || {
      echo "ERROR: generated rules index is invalid: $generated_index" >&2
      return 1
    }
  fi
  local registered_commands=""
  if [ -f "$repo/.claude/settings.json" ]; then
    registered_commands="$(jq -r '.hooks // {} | .. | objects | .command? // empty' "$repo/.claude/settings.json" 2>/dev/null || true)"
  fi
  local f
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    local rule_name layer section declared mechanical tags summary relative generated_entry scan_f
    # scan_f: 非UTF-8原本ならUTF-8一時コピー(改善課題1-131)。fはパス判定・生成物照合に使うため
    # 変更しない。内容走査には常にscan_fを使う
    scan_f="$(to_utf8_for_scan "$f" "$SCAN_WORKDIR")"
    rule_name="$(sed -n 's/^# //p' "$scan_f" | head -1)"
    [ -n "$rule_name" ] || continue
    case "$f" in
      */rules/always/*) layer="always" ;;
      */rules/scoped/*) layer="scoped" ;;
      */rules/generated/*) layer="generated" ;;
      *)                layer="" ;;
    esac
    if [ "$layer" = "generated" ]; then
      [ -f "$generated_index" ] || {
        echo "ERROR: generated rule exists without index: $f" >&2
        return 1
      }
      relative="${f#"$repo/"}"
      generated_entry="$(jq -c --arg p "$relative" '[.entries[] | select(.rulePath == $p)] | if length == 1 then .[0] else empty end' "$generated_index")"
      [ -n "$generated_entry" ] || {
        echo "ERROR: generated rule is not owned by index: $relative" >&2
        return 1
      }
      grep -q "^generatedBy: generate-rules-from-common-docs.sh$" "$scan_f" || {
        echo "ERROR: generated rule marker mismatch: $relative" >&2
        return 1
      }
      declared="$(jq -r '.declaredEnforcement' <<<"$generated_entry")"
      summary="$(jq -r '.summary // empty' <<<"$generated_entry")"
      mechanical="false"
      tags="[]"
    else
      section="$(enforcement_section "$scan_f")"
      if grep -qE 'exit 2|decision:block' <<<"$section"; then
        declared="block"
      elif grep -q 'advisory' <<<"$section"; then
        declared="advisory"
      else
        declared="なし"
      fi
      mechanical="false"
      while IFS= read -r script; do
        [ -n "$script" ] || continue
        if printf '%s\n' "$registered_commands" | grep -Fq -- "$script"; then
          mechanical="true"
          break
        fi
      done < <(printf '%s\n' "$section" | grep -oE '`[^`]+\.sh`' | tr -d '`' | while IFS= read -r script; do basename "$script"; done || true)
      tags="$(tags_json_from_text "$section")"
      summary="$(first_paragraph_sentence "$scan_f")"
    fi
    jq -n -c \
      --arg ruleName "$rule_name" \
      --arg layer "$layer" \
      --arg declaredEnforcement "$declared" \
      --argjson mechanicalEnforcement "$mechanical" \
      --argjson tags "$tags" \
      --arg summary "$summary" \
      '{ruleName: $ruleName}
       + (if $layer != "" then {layer: $layer} else {} end)
       + {declaredEnforcement: $declaredEnforcement, mechanicalEnforcement: $mechanicalEnforcement, tags: $tags}
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
    local fm skill_name category desc trigger summary phase_count scan_f
    # scan_f: 非UTF-8原本ならUTF-8一時コピー(改善課題1-131)。内容走査には常にscan_fを使う
    scan_f="$(to_utf8_for_scan "$f" "$SCAN_WORKDIR")"
    fm="$(frontmatter_of "$scan_f")"
    skill_name="$(sed -n 's/^name:[[:space:]]*//p' <<<"$fm" | head -1)"
    [ -n "$skill_name" ] || continue
    is_forbidden_skill_name "$skill_name" && continue
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
    phase_count="$(grep -c '^## Phase' "$scan_f" || true)"
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
    local fm name desc scan_f
    # scan_f: 非UTF-8原本ならUTF-8一時コピー(改善課題1-131)。内容走査には常にscan_fを使う
    scan_f="$(to_utf8_for_scan "$f" "$SCAN_WORKDIR")"
    fm="$(frontmatter_of "$scan_f")"
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
    local timing matcher command script script_path header tags behavior summary scan_script
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
      # scan_script: 非UTF-8原本ならUTF-8一時コピー(改善課題1-131)。内容走査には常にscan_scriptを使う
      scan_script="$(to_utf8_for_scan "$script_path" "$SCAN_WORKDIR")"
      header="$(head -40 "$scan_script")"
      tags="$(tags_json_from_text "$header")"
      if grep -qE 'exit 2|decision:block' <<<"$header"; then
        behavior="block"
      elif grep -q 'advisory' <<<"$header"; then
        behavior="advisory"
      fi
      summary="$(sed -n '2s/^#[[:space:]]*//p' "$scan_script")"
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
  if ! work="$(mktemp -d "${TMPDIR:-/tmp}/extract-ai-assets.XXXXXX" 2>/dev/null)" || [ -z "$work" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  # RETURN trap は self_test 内呼び出しでも関数終了時に確実に清掃する
  trap 'rm -rf "$work"' RETURN

  extract_rules "$repo" "$work"
  extract_skills "$repo" "$work"
  extract_subagents "$repo" "$work"
  extract_hooks "$repo" "$work"

  mkdir -p "$(dirname "$output")"
  jq -n \
    --arg generatedAt "$(date +%Y-%m-%dT%H:%M:%S%z)" \
    --arg dataSource "$(basename "$repo")" \
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
# 1) mktemp フィクスチャリポジトリ(fixture-repo)で各セクションの抽出値を jq 検証
# 2) 別の mktemp 合成フィクスチャリポジトリ(fixture-repo-b)で
#    rules 3件・hooks 1件・skills 1件の既知件数と、出力スキーマの
#    トップレベルキー・各セクションのフィールドキーが許容集合の範囲内であることを検証
#    (実行環境の実資産・サンプル HTML には依存しない)
self_test() {
  local script_path="$0"
  local tmp rc=0
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/extract-ai-assets-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
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
| PreToolUse(Bash) | `hook-fixture.sh` | `[TEST-GATE-BLOCK]` | 違反を exit 2 で block |

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
          | .layer == "always" and .declaredEnforcement == "block" and .mechanicalEnforcement == true
            and .tags == ["[TEST-GATE-BLOCK]"]
            and (.summary | startswith("テスト用の block 規約。"))
            and (.summary | contains("二文目") | not)),
        ([.rules[] | select(.ruleName == "助言規約（ADV-NOTE）")][0]
          | .layer == "scoped" and .declaredEnforcement == "advisory"
            and .mechanicalEnforcement == false and .tags == ["[ADV-NOTE]"]),
        ([.rules[] | select(.ruleName == "素の文書規約（PLAIN-DOC）")][0]
          | .declaredEnforcement == "なし" and .mechanicalEnforcement == false and .tags == []),
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

  # --- ケースb: 合成フィクスチャ抽出(既知件数 + スキーマ検証) ---
  # 実行環境の実資産・サンプル HTML に依存せず、rules 3件(block/advisory/なし各1)・
  # skills 1件(Phase 1件)・hooks 1件の最小合成フィクスチャで検証する。
  local fx_b="$tmp/fixture-repo-b"
  mkdir -p "$fx_b/.claude/rules/always/rule-a" \
           "$fx_b/.claude/rules/always/rule-b" \
           "$fx_b/.claude/rules/scoped/rule-c" \
           "$fx_b/.claude/skills/skill-a" \
           "$fx_b/.claude/agents"

  cat > "$fx_b/.claude/rules/always/rule-a/rule.md" <<'EOF'
# 規約A（RULE-A）

ケースb検証用の最小 block 規約。

## 機械強制

| timing | スクリプト | 注入タグ | 挙動 |
|---|---|---|---|
| PreToolUse(Bash) | `check-rule-a.sh` | `[RULE-A-BLOCK]` | 違反を exit 2 で block |
EOF

  cat > "$fx_b/.claude/rules/always/rule-b/rule.md" <<'EOF'
# 規約B（RULE-B）

ケースb検証用の最小 advisory 規約。

## 機械強制

| timing | スクリプト | 注入タグ | 挙動 |
|---|---|---|---|
| PostToolUse(Write) | `check-rule-b.sh` | `[RULE-B]` | advisory 注入(block なし) |
EOF

  cat > "$fx_b/.claude/rules/scoped/rule-c/rule.md" <<'EOF'
# 規約C（RULE-C）

ケースb検証用の機械強制を持たない規約。

## 機械強制

現時点では hook による機械強制なし。
EOF

  cat > "$fx_b/.claude/skills/skill-a/SKILL.md" <<'EOF'
---
name: skill-a
description: |
  ケースb検証用の最小スキル。
  TRIGGER when: セルフテスト実行時。
  SKIP: 本番利用。
---

# スキルA

## Phase 1: 準備
EOF

  cat > "$fx_b/.claude/agents/agent-a.md" <<'EOF'
---
name: agent-a
description: ケースb検証用の最小サブエージェント
---
EOF

  cat > "$fx_b/.claude/hook-b.sh" <<'EOF'
#!/usr/bin/env bash
# フィクスチャ hook: [HOOK-B] を exit 2 で注入する
exit 0
EOF

  cat > "$fx_b/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hook-b.sh"}
        ]
      }
    ]
  }
}
EOF

  local out_b="$tmp/out-b.json"
  if bash "$script_path" "$fx_b" "$out_b" >/dev/null 2>&1 && jq -e . "$out_b" >/dev/null 2>&1; then
    local rules_n hooks_n skills_n
    rules_n="$(jq '.rules | length' "$out_b")"
    hooks_n="$(jq '.hooks | length' "$out_b")"
    skills_n="$(jq '.skills | length' "$out_b")"
    if [ "$rules_n" -eq 3 ] && [ "$hooks_n" -eq 1 ] && [ "$skills_n" -eq 1 ]; then
      echo "  [PASS] ケースb-件数: 合成フィクスチャで rules=${rules_n} / hooks=${hooks_n} / skills=${skills_n}"
    else
      echo "  [FAIL] ケースb-件数: rules=${rules_n}(期待3) / hooks=${hooks_n}(期待1) / skills=${skills_n}(期待1)" >&2
      rc=1
    fi

    # スキーマ検査: サンプル HTML には依存せず、トップレベルキーとフィールドキーをリテラルで検証
    local schema_ok
    schema_ok="$(jq '
      (keys | sort) == ["dataSource","generatedAt","hooks","rules","skills","subagents"] and
      ([.rules[]     | keys[]] - ["ruleName","layer","declaredEnforcement","mechanicalEnforcement","tags","summary"] == []) and
      ([.skills[]    | keys[]] - ["skillName","category","trigger","summary","phaseCount"] == []) and
      ([.subagents[] | keys[]] - ["name","classification","verdict","mainTools"] == []) and
      ([.hooks[]     | keys[]] - ["script","timing","matcher","tags","behavior","summary"] == [])
    ' "$out_b")"
    if [ "$schema_ok" = "true" ]; then
      echo "  [PASS] ケースb-スキーマ: 全セクション・全フィールドが許容集合内"
    else
      echo "  [FAIL] ケースb-スキーマ: フィールド不整合" >&2
      rc=1
    fi
  else
    echo "  [FAIL] ケースb: 合成フィクスチャ抽出の実行または JSON パースに失敗" >&2
    rc=1
  fi

  # --- ケースc: AI設定資産テンプレートの宣言区分/機械強制の表示分離 ---
  local script_dir template_path
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  template_path="$(cd "$script_dir/../../.." && pwd)/delivery-payload/templates/ai-assets/ai-assets-template.html"
  if [ -f "$template_path" ] \
    && grep -q '<th>宣言区分</th>' "$template_path" \
    && grep -q '<th>機械強制</th>' "$template_path" \
    && grep -q "value === true ? 'badge danger' : 'badge neutral'" "$template_path" \
    && grep -q "value === true ? '有効' : 'なし'" "$template_path" \
    && grep -q 'declaredBadge(r.declaredEnforcement)' "$template_path" \
    && grep -q 'mechanicalBadge(r.mechanicalEnforcement)' "$template_path"; then
    echo "  [PASS] ケースc: UIが宣言区分と機械強制を別列・別badgeで表示し、dangerはmechanical=trueだけ"
  else
    echo "  [FAIL] ケースc: AI設定資産テンプレートの表示分離契約が不一致" >&2
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

# --- 非UTF-8原本の走査対応(改善課題1-131): detect-encoding.sh の走査ヘルパーを読み込む ---
_EXTRACT_AI_ASSETS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../detect-encoding.sh
source "$_EXTRACT_AI_ASSETS_SCRIPT_DIR/../detect-encoding.sh"
if ! SCAN_WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/extract-ai-assets-scan.XXXXXX" 2>/dev/null)" || [ -z "$SCAN_WORKDIR" ]; then
  echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
  exit 2
fi
trap 'rm -rf "$SCAN_WORKDIR"' EXIT

run_extract "$REPO_ROOT" "$OUTPUT_JSON"
