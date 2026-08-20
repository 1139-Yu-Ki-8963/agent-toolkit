#!/usr/bin/env bash
# 生成物である。直接編集しない（定義: generation-engine/scripts/rules/build-derived-rules.sh）
set -euo pipefail

# build-derived-rules.sh — docs/rules/ の規約定義から派生物を生成する
#
# 設計の定義: delivery-payload/references/規約定義と派生生成の設計.md（5節・6節）
#
# 目的:
#   docs/rules/<親>/<子>/rule.md から、.claude/rules/・.cursor/rules/・AGENTS.md索引・
#   3ツール（.claude/.cursor/.codex）のhooks登録を生成する。定義から派生への
#   一方向生成のみを行い、生成物の直接編集は前提としない。
#
# 使い方:
#   build-derived-rules.sh <docs/rules のルート> <出力先リポジトリルート> [--apply]
#   build-derived-rules.sh --deploy-rule-scripts <出力先リポジトリルート>
#   build-derived-rules.sh --self-test
#
# --deploy-rule-scripts は、本スクリプト・validate-rule-definitions.sh・
# check-rule-drift.sh の3本を、出力先リポジトリの
# docs/rules/agent-operations/ai-config-asset-management/ へ複製する。
# 規約を扱うスクリプトは対応する規約のフォルダへ置き、スクリプト専用の
# フォルダを作らない（設計の定義: delivery-payload/references/規約定義と派生生成の設計.md
# 2節）。複製先の先頭には生成物である旨のコメントを入れる。定義（docs/rules/）の
# 生成とは独立した動作であり、docs/rules のルートを必要としない。
#
# 既定はdry-run。生成予定のパスと内容の要約を標準出力へ出すのみで書き込みをしない。
# --apply を付けたときだけ出力先リポジトリルートへ実際に書き込む。
#
# 実行の最初に validate-rule-definitions.sh（同ディレクトリ）を呼び、
# 不合格なら何も生成せず終了コード1で止まる。
#
# status: draft の規約は生成対象から除外し、除外件数を報告する。
#
# 生成物（設計5節・6節）:
#   (1) .claude/rules/<scope>/<parent>/<key>/rule.md    front matterを落とした本文
#   (2) .cursor/rules/<parent>-<key>.mdc                Cursor用front matter + 本文
#   (3) AGENTS.md の <!-- RULES-INDEX:START/END --> 間   規約本文を複製しない索引
#   (4) checkable:true の規約について .claude/settings.json・.cursor/hooks.json・
#       .codex/config.toml へ checker 呼び出しを登録（スクリプト実体は複製しない。
#       常に "docs/rules/<parent>/<key>/<checker>" という設計上の定義配置パスを
#       参照する。JSONはコメントを持てないため "_generatedNotice" フィールドで
#       生成物であることを示し、TOMLは "# BEGIN/END" コメントで印を付ける）
#   (5) <root>/mcp-servers.json（McpCanon。docs/rules ルート直下の平置きファイルで、
#       parent.yml を持たないため validate-rule-definitions.sh の親カテゴリ走査の対象外。
#       形式は {"mcpServers": {"<name>": {"command"|"url", "args", "env", "type", ...}}}。
#       type:"http" (または url を持つ) はリモートサーバー、それ以外は command必須の
#       stdioサーバーとして扱う）が実在する場合、.mcp.json（mcpServersキー。Claude Code・
#       Cursorと互換。3ツールともmcpServers鍵で高い互換性を持つという構想の実測に基づく）
#       と .codex/config.toml の [mcp_servers.<name>] ブロックを生成する。
#       既知の限界: Codex向けTOML変換はstdio型のみ対応する。remote(http/url)型サーバーの
#       Codex側TOML表現は本リポジトリの参照範囲内で確認できず未対応とし、変換対象外である旨を
#       stderrへ列挙する。.mcp.json側はstdio・remoteの両方を変換する。
#       mcp-servers.jsonが不在の場合は生成をスキップする（hooksが初期0個でも配管だけ敷く
#       という構想の決定と同型。生成の有無は定義ファイルの有無に従う）。
#
# 冪等性: 既存の .claude/settings.json・.cursor/hooks.json は、コマンドが
#   "docs/rules/" で始まるエントリだけを本スクリプト管理分として差し替える
#   （それ以外の既存エントリは保持する）。.codex/config.toml は
#   "# BEGIN docs/rules-generated hooks" 〜 "# END ..." と
#   "# BEGIN docs/rules-generated mcp" 〜 "# END ..." の2種のブロックを、
#   それぞれ独立に丸ごと差し替える。AGENTS.md はマーカー間だけを差し替える。
#   .mcp.json の "mcpServers" キーは本スクリプトの完全管理下とし丸ごと差し替える
#   （エントリ名にdocs/rules/接頭辞のような区別可能な性質を持たないため、
#   settings.json・hooks.jsonと同じ部分フィルタ方式ではなくキー単位の完全所有とする。
#   手動追加のMCPサーバーは "mcpServers" 以外のトップレベルキーで管理する想定）。
#   .mcp.json・.codex/config.toml はいずれも部分差し替え方式のため、check-rule-drift.sh の
#   突合対象（丸ごと生成されるrule.md/*.mdcのみを対象とする設計）の対象外とする
#   （AGENTS.md・settings.json・hooks.jsonと同じ既存の除外理由に倣う）。
#
# 終了コード:
#   0 = 生成（またはdry-runの列挙）が完了
#   1 = validate-rule-definitions.sh が不合格、または引数不正
#   --self-test のみ、期待どおりの生成ができなければ1
#
# 保守責任者・廃棄条件: generation-engine/scripts/rules/rule.md の「## 設計判断」
#   「### build-derived-rules.sh」を参照。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./validate-rule-definitions.sh
. "${SCRIPT_DIR}/validate-rule-definitions.sh"

APPLY=0
DRAFT_COUNT=0
PLAN_LINES=""

GENERATED_NOTICE="このエントリ群（コマンドが docs/rules/ で始まるもの）は build-derived-rules.sh が docs/rules/ から自動生成した。直接編集しないこと。"
TOML_BEGIN_MARK="# BEGIN docs/rules-generated hooks (build-derived-rules.sh) — 直接編集しないこと"
TOML_END_MARK="# END docs/rules-generated hooks"
MCP_GENERATED_NOTICE="mcpServersキーは build-derived-rules.sh が <docs/rules root>/mcp-servers.json (McpCanon) から自動生成した。直接編集しないこと。手動追加のMCPサーバーはmcpServers以外のキーで管理する。"
MCP_TOML_BEGIN_MARK="# BEGIN docs/rules-generated mcp (build-derived-rules.sh) — 直接編集しないこと"
MCP_TOML_END_MARK="# END docs/rules-generated mcp"

plan_add() {
  PLAN_LINES="${PLAN_LINES}${1}
"
}

ensure_dir_for_file() {
  [ "$APPLY" -eq 1 ] || return 0
  mkdir -p "$(dirname "$1")"
}

write_file_if_apply() {
  # $1: 出力パス  $2: 内容
  ensure_dir_for_file "$1"
  if [ "$APPLY" -eq 1 ]; then
    printf '%s\n' "$2" > "$1"
  fi
}

trim_leading_blank_lines() {
  # 標準入力の先頭の空行だけを取り除く
  sed -e '/./,$!d'
}

# 親カテゴリの日本語表示名を parent.yml から取得する。
# parent.yml が無ければ親キーそのものをフォールバックとして返す
# （validate-rule-definitions.sh が事前に実在を検査済みのため、通常は到達しない）。
parent_title_for() {
  local root="$1" parent_key="$2"
  local pfile="${root}/${parent_key}/parent.yml"
  if [ -f "$pfile" ]; then
    local title
    title="$(fm_get_scalar "$(cat "$pfile")" title)"
    if [ -n "$title" ]; then
      printf '%s' "$title"
      return 0
    fi
  fi
  printf '%s' "$parent_key"
}

trim_blank_edges() {
  # 標準入力の先頭・末尾の空行を取り除く（内部の空行は保持）。
  # マーカー差し替えを繰り返すたびに空行が蓄積するのを防ぐために使う。
  awk '
    { a[NR] = $0 }
    END {
      s = 1; e = NR
      while (s <= e && a[s] == "") s++
      while (e >= s && a[e] == "") e--
      for (i = s; i <= e; i++) print a[i]
    }
  '
}

# ---------------------------------------------------------------------------
# MCPサーバー設定（McpCanon → .mcp.json / .codex/config.toml [mcp_servers.*]）
# ---------------------------------------------------------------------------

# JSON文字列をTOML基本文字列（ダブルクオート）へ変換する。
# jq の @json はJSON文字列エスケープを出力し、TOML基本文字列のエスケープ規則と
# 単純なASCII文字列（バックスラッシュ・ダブルクオート・制御文字を含まない）の
# 範囲では一致するため、その範囲に限定して使う。
toml_quote() {
  jq -rn --arg s "$1" '$s | @json'
}

# McpCanonの1サーバー定義（jqオブジェクト、標準入力）をTOMLの
# [mcp_servers.<name>] ブロックへ変換する。stdio型（command必須）のみ対応する。
# 対応外（url保有のremote型）はcaller側で事前にフィルタする。
mcp_entry_to_toml() {
  local name="$1" entry_json="$2"
  local command args_json env_json
  command="$(jq -r '.command' <<<"$entry_json")"
  local out="[mcp_servers.$(printf '%s' "$name" | sed 's/\./\\./g')]
command = $(toml_quote "$command")"
  args_json="$(jq -c '.args // []' <<<"$entry_json")"
  if [ "$(jq 'length' <<<"$args_json")" -gt 0 ]; then
    local args_toml
    args_toml="$(jq -r '[.[] | @json] | join(", ")' <<<"$args_json")"
    out="${out}
args = [${args_toml}]"
  fi
  env_json="$(jq -c '.env // {}' <<<"$entry_json")"
  if [ "$(jq 'length' <<<"$env_json")" -gt 0 ]; then
    local env_toml
    env_toml="$(jq -r 'to_entries | map("\(.key) = " + (.value | @json)) | join(", ")' <<<"$env_json")"
    out="${out}
env = { ${env_toml} }"
  fi
  printf '%s\n' "$out"
}

# <root>/mcp-servers.json (McpCanon) から .mcp.json と .codex/config.toml の
# [mcp_servers.*] ブロックを生成する。定義ファイルが無ければ何もしない（skip）。
build_mcp_artifacts() {
  local root="$1" out_root="$2"
  local mcp_def="${root}/mcp-servers.json"

  if [ ! -f "$mcp_def" ]; then
    plan_add "MCP定義なし（${mcp_def} 不在）。.mcp.json・.codex/config.tomlのmcp_servers生成はskip"
    return 0
  fi

  if ! jq -e '.mcpServers | type == "object"' "$mcp_def" >/dev/null 2>&1; then
    echo "ERROR: ${mcp_def} は .mcpServers オブジェクトを持つ必要がある" >&2
    return 1
  fi

  local names name entry is_remote
  names="$(jq -r '.mcpServers | keys[]' "$mcp_def" | sort)"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    entry="$(jq -c --arg n "$name" '.mcpServers[$n]' "$mcp_def")"
    is_remote="$(jq -r 'if (.type == "http") or (has("url")) then "1" else "0" end' <<<"$entry")"
    if [ "$is_remote" = "0" ] && [ "$(jq -r 'has("command")' <<<"$entry")" != "true" ]; then
      echo "ERROR: ${mcp_def} の mcpServers.${name} はstdio型だが command が無い" >&2
      return 1
    fi
    if [ "$is_remote" = "1" ] && [ "$(jq -r 'has("url")' <<<"$entry")" != "true" ]; then
      echo "ERROR: ${mcp_def} の mcpServers.${name} はremote型だが url が無い" >&2
      return 1
    fi
  done <<EOF
$names
EOF

  # --- .mcp.json（stdio・remote両方をmcpServersキーへ丸ごと反映） ---
  local mcp_out="${out_root}/.mcp.json"
  local mcp_base mcp_final
  if [ -f "$mcp_out" ]; then
    mcp_base="$(cat "$mcp_out")"
  else
    mcp_base="{}"
  fi
  mcp_final="$(jq --slurpfile def "$mcp_def" --arg notice "$MCP_GENERATED_NOTICE" '
    ._generatedMcpNotice = $notice
    | .mcpServers = $def[0].mcpServers
  ' <<<"$mcp_base")"
  plan_add "${mcp_out}"
  write_file_if_apply "$mcp_out" "$mcp_final"

  # --- .codex/config.toml の [mcp_servers.*]（stdio型のみ。remoteは既知の限界としてskip） ---
  local mcp_toml_block="${MCP_TOML_BEGIN_MARK}
"
  local skipped_remote=""
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    entry="$(jq -c --arg n "$name" '.mcpServers[$n]' "$mcp_def")"
    is_remote="$(jq -r 'if (.type == "http") or (has("url")) then "1" else "0" end' <<<"$entry")"
    if [ "$is_remote" = "1" ]; then
      skipped_remote="${skipped_remote}${name} "
      continue
    fi
    mcp_toml_block="${mcp_toml_block}
$(mcp_entry_to_toml "$name" "$entry")"
  done <<EOF
$names
EOF
  mcp_toml_block="${mcp_toml_block}
${MCP_TOML_END_MARK}"
  if [ -n "$skipped_remote" ]; then
    echo "NOTE: Codex向けTOML変換はstdio型のみ対応のため、remote型を変換対象外とした: ${skipped_remote}" >&2
  fi

  local codex_out="${out_root}/.codex/config.toml"
  local codex_final
  if [ -f "$codex_out" ] && grep -q "^${MCP_TOML_BEGIN_MARK}$" "$codex_out" 2>/dev/null; then
    local stripped
    stripped="$(awk -v begin="$MCP_TOML_BEGIN_MARK" -v end="$MCP_TOML_END_MARK" '
      $0 == begin { skip=1; next }
      $0 == end { skip=0; next }
      skip==1 { next }
      { print }
    ' "$codex_out" | trim_blank_edges)"
    if [ -z "$stripped" ]; then
      codex_final="$mcp_toml_block"
    else
      codex_final="${stripped}

${mcp_toml_block}"
    fi
  elif [ -f "$codex_out" ]; then
    local existing_codex_trimmed
    existing_codex_trimmed="$(trim_blank_edges < "$codex_out")"
    if [ -z "$existing_codex_trimmed" ]; then
      codex_final="$mcp_toml_block"
    else
      codex_final="${existing_codex_trimmed}

${mcp_toml_block}"
    fi
  else
    codex_final="$mcp_toml_block"
  fi
  plan_add "${codex_out}（mcp_servers）"
  write_file_if_apply "$codex_out" "$codex_final"
  return 0
}

# ---------------------------------------------------------------------------
# 生成本体
# ---------------------------------------------------------------------------

run_build() {
  local root="$1" out_root="$2"

  local validate_out
  validate_out="$(mktemp "${TMPDIR:-/tmp}/build-derived-rules-validate.XXXXXX")"
  if ! run_validate "$root" >"$validate_out" 2>&1; then
    cat "$validate_out" >&2
    rm -f "$validate_out"
    echo "ERROR: validate-rule-definitions.sh が不合格のため生成を中止しました" >&2
    return 1
  fi
  rm -f "$validate_out"

  DRAFT_COUNT=0
  PLAN_LINES=""

  local rule_files
  rule_files="$(find "$root" -type f -name 'rule.md' | sort)"

  # AGENTS.md索引ブロック・checkable規約のhooks登録先を貯めるバッファ
  local agents_block="<!-- RULES-INDEX:START -->
<!-- 生成物: build-derived-rules.sh により docs/rules/ から自動生成。直接編集しないこと -->
"
  local current_parent=""
  local hook_entries_json="[]"
  local toml_block="${TOML_BEGIN_MARK}
"
  local has_hook_entries=0

  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue

    local body v_status
    body="$(fm_extract "$f")"
    v_status="$(fm_get_scalar "$body" status)"
    if [ "$v_status" = "draft" ]; then
      DRAFT_COUNT=$((DRAFT_COUNT + 1))
      continue
    fi

    local v_key v_title v_parent v_summary v_scope v_enforcement v_checkable v_checker v_formatter v_origin
    v_key="$(fm_get_scalar "$body" key)"
    v_title="$(fm_get_scalar "$body" title)"
    v_parent="$(fm_get_scalar "$body" parent)"
    v_summary="$(fm_get_scalar "$body" summary)"
    v_scope="$(fm_get_scalar "$body" scope)"
    v_enforcement="$(fm_get_scalar "$body" enforcement)"
    v_checkable="$(fm_get_scalar "$body" checkable)"
    v_checker="$(fm_get_scalar "$body" checker)"
    v_formatter="$(fm_get_scalar "$body" formatter)"
    v_origin="$(fm_get_scalar "$body" origin)"

    local paths_raw paths_csv
    paths_raw="$(fm_get_array "$body" paths)" || paths_raw="[]"
    paths_csv="$(printf '%s' "$paths_raw" | jq -r 'join(",")' 2>/dev/null || echo "")"

    local scope_dir
    if [ "$v_scope" = "always" ]; then
      scope_dir="always"
    else
      scope_dir="scoped"
    fi

    local always_apply
    if [ "$v_scope" = "always" ]; then
      always_apply="true"
    else
      always_apply="false"
    fi

    local body_content
    body_content="$(body_extract "$f" | trim_leading_blank_lines)"

    local docs_ref="docs/rules/${v_parent}/${v_key}/rule.md"

    # --- (1) .claude/rules/<scope>/<parent>/<key>/rule.md ---
    local claude_out="${out_root}/.claude/rules/${scope_dir}/${v_parent}/${v_key}/rule.md"
    local claude_content
    claude_content="<!-- 生成物: ${docs_ref} から自動生成。直接編集しないこと -->

${body_content}"
    plan_add "${claude_out}"
    write_file_if_apply "$claude_out" "$claude_content"

    # --- (2) .cursor/rules/<parent>-<key>.mdc ---
    local mdc_out="${out_root}/.cursor/rules/${v_parent}-${v_key}.mdc"
    local mdc_content
    mdc_content="---
description: ${v_summary}
globs: ${paths_csv}
alwaysApply: ${always_apply}
---

<!-- 生成物: ${docs_ref} から自動生成。直接編集しないこと -->

${body_content}"
    plan_add "${mdc_out}"
    write_file_if_apply "$mdc_out" "$mdc_content"

    # --- (3) AGENTS.md 索引ブロックの材料 ---
    if [ "$v_parent" != "$current_parent" ]; then
      local parent_title
      parent_title="$(parent_title_for "$root" "$v_parent")"
      agents_block="${agents_block}
## ${parent_title}
"
      current_parent="$v_parent"
    fi
    agents_block="${agents_block}- **${v_title}**: ${v_summary}（参照: ${docs_ref}）
"

    # --- (4) hooks登録の材料（checkable:true のみ） ---
    if [ "$v_checkable" = "true" ] && [ -n "$v_checker" ] && [ "$v_checker" != "null" ]; then
      local checker_ref="docs/rules/${v_parent}/${v_key}/${v_checker}"
      local entry
      entry="$(jq -n --arg m "Write|Edit|MultiEdit" --arg cmd "$checker_ref" \
        '{matcher: $m, hooks: [{type: "command", command: $cmd}]}')"
      hook_entries_json="$(jq -c --argjson e "$entry" '. + [$e]' <<<"$hook_entries_json")"
      toml_block="${toml_block}
[[hooks]]
event = \"afterFileEdit\"
command = \"${checker_ref}\"
"
      has_hook_entries=1
      plan_add "hooks登録: ${v_parent}/${v_key}（${checker_ref}）"
    fi
  done <<EOF
$rule_files
EOF

  agents_block="${agents_block}<!-- RULES-INDEX:END -->"
  toml_block="${toml_block}${TOML_END_MARK}"

  # --- (3) AGENTS.md の書き出し ---
  local agents_out="${out_root}/AGENTS.md"
  local agents_final
  if [ -f "$agents_out" ] && grep -q '<!-- RULES-INDEX:START -->' "$agents_out" 2>/dev/null \
     && grep -q '<!-- RULES-INDEX:END -->' "$agents_out" 2>/dev/null; then
    # NEWBLOCK は環境変数経由で渡す（-v は改行を含む値をmacOS/BSD awkで
    # 受け付けないため。ENVIRON参照ならエスケープ解釈が走らず安全）
    agents_final="$(NEWBLOCK="$agents_block" awk '
      /<!-- RULES-INDEX:START -->/ { print ENVIRON["NEWBLOCK"]; skip=1; next }
      /<!-- RULES-INDEX:END -->/ { skip=0; next }
      skip==1 { next }
      { print }
    ' "$agents_out")"
  elif [ -f "$agents_out" ]; then
    local existing_agents_trimmed
    existing_agents_trimmed="$(trim_blank_edges < "$agents_out")"
    if [ -z "$existing_agents_trimmed" ]; then
      agents_final="$agents_block"
    else
      agents_final="${existing_agents_trimmed}

${agents_block}"
    fi
  else
    agents_final="$agents_block"
  fi
  plan_add "${agents_out}（規約索引 差し替え/追記）"
  write_file_if_apply "$agents_out" "$agents_final"

  # --- (4) hooks登録の書き出し ---
  if [ "$has_hook_entries" -eq 1 ]; then
    # .claude/settings.json
    local settings_out="${out_root}/.claude/settings.json"
    local settings_base settings_final
    if [ -f "$settings_out" ]; then
      settings_base="$(cat "$settings_out")"
    else
      settings_base="{}"
    fi
    settings_final="$(jq --argjson new "$hook_entries_json" --arg notice "$GENERATED_NOTICE" '
      ._generatedNotice = $notice
      | .hooks = (.hooks // {})
      | .hooks.PostToolUse = ((.hooks.PostToolUse // []) | map(select(((.hooks[0].command // "") | startswith("docs/rules/")) | not))) + $new
    ' <<<"$settings_base")"
    plan_add "${settings_out}"
    write_file_if_apply "$settings_out" "$settings_final"

    # .cursor/hooks.json
    local cursor_hooks_out="${out_root}/.cursor/hooks.json"
    local cursor_hooks_base cursor_hooks_new cursor_hooks_final
    if [ -f "$cursor_hooks_out" ]; then
      cursor_hooks_base="$(cat "$cursor_hooks_out")"
    else
      cursor_hooks_base="{}"
    fi
    cursor_hooks_new="$(jq -c '[.[] | {command: .hooks[0].command}]' <<<"$hook_entries_json")"
    cursor_hooks_final="$(jq --argjson new "$cursor_hooks_new" --arg notice "$GENERATED_NOTICE" '
      ._generatedNotice = $notice
      | .hooks = (.hooks // {})
      | .hooks.afterFileEdit = ((.hooks.afterFileEdit // []) | map(select((.command // "") | startswith("docs/rules/") | not))) + $new
    ' <<<"$cursor_hooks_base")"
    plan_add "${cursor_hooks_out}"
    write_file_if_apply "$cursor_hooks_out" "$cursor_hooks_final"

    # .codex/config.toml
    local codex_out="${out_root}/.codex/config.toml"
    local codex_final
    if [ -f "$codex_out" ] && grep -q "^${TOML_BEGIN_MARK}$" "$codex_out" 2>/dev/null; then
      local stripped
      stripped="$(awk -v begin="$TOML_BEGIN_MARK" -v end="$TOML_END_MARK" '
        $0 == begin { skip=1 }
        skip==0 { print }
        $0 == end { skip=0 }
      ' "$codex_out" | trim_blank_edges)"
      if [ -z "$stripped" ]; then
        codex_final="$toml_block"
      else
        codex_final="${stripped}

${toml_block}"
      fi
    elif [ -f "$codex_out" ]; then
      local existing_codex_trimmed
      existing_codex_trimmed="$(trim_blank_edges < "$codex_out")"
      if [ -z "$existing_codex_trimmed" ]; then
        codex_final="$toml_block"
      else
        codex_final="${existing_codex_trimmed}

${toml_block}"
      fi
    else
      codex_final="$toml_block"
    fi
    plan_add "${codex_out}"
    write_file_if_apply "$codex_out" "$codex_final"
  fi

  # --- (5) MCPサーバー設定（McpCanon → .mcp.json・.codex/config.tomlのmcp_servers） ---
  build_mcp_artifacts "$root" "$out_root" || return 1

  echo "非承認(draft)除外: ${DRAFT_COUNT} 件"
  if [ "$APPLY" -eq 1 ]; then
    echo "生成完了（--apply）:"
  else
    echo "DRY-RUN: 以下を生成予定（--apply未指定のため書き込みなし）:"
  fi
  printf '%s' "$PLAN_LINES"
  return 0
}

# ---------------------------------------------------------------------------
# --deploy-rule-scripts
# ---------------------------------------------------------------------------

DEPLOY_NOTICE="生成物である。直接編集しない（定義: generation-engine/scripts/rules/"
DEPLOY_NOTICE_CHECKERS="生成物である。直接編集しない（定義: delivery-payload/templates/rules/checkers/"
CHECKERS_TEMPLATE_DIR_FOR_DEPLOY="${SCRIPT_DIR}/../../templates/rules/checkers"

deploy_rule_scripts() {
  local out_root="$1"
  local scripts_dir="${out_root}/docs/rules/agent-operations/ai-config-asset-management"
  mkdir -p "$scripts_dir"

  local src name dest
  for name in build-derived-rules.sh validate-rule-definitions.sh check-rule-drift.sh; do
    src="${SCRIPT_DIR}/${name}"
    dest="${scripts_dir}/${name}"
    {
      printf '#!/usr/bin/env bash\n'
      printf '# %s%s）\n' "$DEPLOY_NOTICE" "$name"
      tail -n +2 "$src"
    } > "$dest"
    chmod +x "$dest"
    echo "配備完了: ${dest}"
  done

  # resolve-applicable-rules.sh は個別の規約に紐づかない横断ツールのため
  # checkers/ テンプレートから配備する（他3本とは複製元ディレクトリが異なる）。
  # 配備先（納品先リポジトリ）で本スクリプトを直接再実行した場合、
  # checkers/ テンプレートは存在しないため、既に配備済みの自分自身を
  # 複製元にフォールバックする（他3本と同じ自己参照方式）。
  name="resolve-applicable-rules.sh"
  src="${CHECKERS_TEMPLATE_DIR_FOR_DEPLOY}/${name}"
  if [ ! -f "$src" ]; then
    src="${SCRIPT_DIR}/${name}"
  fi
  dest="${scripts_dir}/${name}"
  if [ ! -f "$src" ]; then
    echo "配備失敗: ${name} の複製元が見つからない（${CHECKERS_TEMPLATE_DIR_FOR_DEPLOY}/${name} にも ${SCRIPT_DIR}/${name} にも存在しない）" >&2
    return 1
  fi
  {
    printf '#!/usr/bin/env bash\n'
    printf '# %s%s）\n' "$DEPLOY_NOTICE_CHECKERS" "$name"
    tail -n +2 "$src"
  } > "$dest"
  chmod +x "$dest"
  echo "配備完了: ${dest}"
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

bst_write_fixture() {
  # $1: ルートディレクトリ（docs/rulesのルート）
  local root="$1"
  mkdir -p "${root}/agent-operations/ai-behavior"
  mkdir -p "${root}/code-standards/naming"
  mkdir -p "${root}/docs-quality/review-notes"

  cat > "${root}/agent-operations/parent.yml" <<'EOF'
key: agent-operations
title: AIエージェント運用
EOF

  cat > "${root}/code-standards/parent.yml" <<'EOF'
key: code-standards
title: コード規約
EOF

  cat > "${root}/docs-quality/parent.yml" <<'EOF'
key: docs-quality
title: ドキュメント品質
EOF

  cat > "${root}/agent-operations/ai-behavior/rule.md" <<'EOF'
---
key: ai-behavior
title: 人とAIの分担の決まり
parent: agent-operations
summary: AIエージェントへの作業委任の取り決め。
scope: always
paths: ["**/*"]
enforcement: advisory
checkable: false
checker: null
uncheckableReason: 行動の是非は静的解析では判定できない。
formatter: none
status: approved
origin: proposal
---

# 人とAIの分担の決まり

## 概要

テスト用の概要。

## 規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 例 | 例 | 例 | 静的解析: 例 |

## 違反時の手順

1. 例
EOF

  cat > "${root}/code-standards/naming/rule.md" <<'EOF'
---
key: naming
title: 名前の付け方の決まり
parent: code-standards
summary: 変数・クラスの命名パターン。
scope: scoped
paths: ["src/**/*.ts", "src/**/*.tsx"]
enforcement: advisory
checkable: true
checker: check-naming.sh
uncheckableReason: null
formatter: none
status: approved
origin: proposal
---

# 名前の付け方の決まり

## 概要

テスト用の概要。

## 規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 例 | 例 | 例 | 静的解析: 例 |

## 違反時の手順

1. 例
EOF

  cat > "${root}/code-standards/naming/check-naming.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "${root}/code-standards/naming/check-naming.test.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${root}/code-standards/naming/check-naming.sh" "${root}/code-standards/naming/check-naming.test.sh"

  cat > "${root}/docs-quality/review-notes/rule.md" <<'EOF'
---
key: review-notes
title: レビュー観点メモ（未承認）
parent: docs-quality
summary: 取り込み直後のdraft規約。派生生成の対象外になるべきもの。
scope: always
paths: ["**/*"]
enforcement: advisory
checkable: false
checker: null
uncheckableReason: 未承認のため検査対象外。
formatter: none
status: draft
origin: proposal
---

# レビュー観点メモ（未承認）

## 概要

draft状態の規約。build-derived-rules.shの生成対象から除外されることを確認する。

## 規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 例 | 例 | 例 | 静的解析: 例 |

## 違反時の手順

1. 例
EOF

  cat > "${root}/mcp-servers.json" <<'EOF'
{
  "specVersion": 1,
  "mcpServers": {
    "fs-tools": {
      "command": "node",
      "args": ["./mcp/fs-tools.js"],
      "env": {"MODE": "readonly"}
    },
    "remote-search": {
      "type": "http",
      "url": "https://example.invalid/mcp"
    }
  }
}
EOF
}

self_test() {
  local rc=0
  local src out1 out2 bst_run1_log bst_diff_log
  src="$(mktemp -d "${TMPDIR:-/tmp}/build-derived-rules-self-test-src.XXXXXX")"
  bst_write_fixture "$src"

  # ケース1: --apply なしでは書き込みが起きない
  out1="$(mktemp -d "${TMPDIR:-/tmp}/build-derived-rules-self-test-out1.XXXXXX")"
  rm -rf "$out1"
  APPLY=0
  run_build "$src" "$out1" >/dev/null 2>&1 || true
  if [ -d "$out1" ]; then
    echo "  [FAIL] ケース1: --apply なしで出力先ディレクトリが作成された" >&2
    rc=1
  else
    echo "  [PASS] ケース1: --apply なしでは書き込みが起きない"
  fi

  # 以降は --apply で実データを生成して検証する
  out1="$(mktemp -d "${TMPDIR:-/tmp}/build-derived-rules-self-test-out1.XXXXXX")"
  APPLY=1
  bst_run1_log="$(mktemp "${TMPDIR:-/tmp}/build-derived-rules-bst-run1.XXXXXX")"
  run_build "$src" "$out1" >"$bst_run1_log" 2>&1
  rc1=$?
  if [ "$rc1" -ne 0 ]; then
    echo "  [FAIL] 1回目の --apply 実行が失敗した (rc=$rc1)" >&2
    sed 's/^/    /' "$bst_run1_log" >&2
    rc=1
  fi
  rm -f "$bst_run1_log"

  # ケース2: status:draft の規約が生成物に含まれない
  ok2=1
  [ -e "${out1}/.claude/rules/always/docs-quality/review-notes/rule.md" ] && ok2=0
  [ -e "${out1}/.cursor/rules/docs-quality-review-notes.mdc" ] && ok2=0
  if grep -q "review-notes" "${out1}/AGENTS.md" 2>/dev/null; then
    ok2=0
  fi
  if [ "$ok2" -eq 1 ]; then
    echo "  [PASS] ケース2: status:draft の規約が生成物に含まれない"
  else
    echo "  [FAIL] ケース2: draft規約が生成物に混入した" >&2
    rc=1
  fi

  # ケース3: .cursor/rules/*.mdc の front matter が3鍵を持つ
  local mdc_file mdc_fm ok3
  mdc_file="${out1}/.cursor/rules/code-standards-naming.mdc"
  ok3=1
  if [ -f "$mdc_file" ]; then
    mdc_fm="$(fm_extract "$mdc_file" || true)"
    fm_has_key "$mdc_fm" description || ok3=0
    fm_has_key "$mdc_fm" globs || ok3=0
    fm_has_key "$mdc_fm" alwaysApply || ok3=0
  else
    ok3=0
  fi
  if [ "$ok3" -eq 1 ]; then
    echo "  [PASS] ケース3: .cursor/rules/*.mdc の front matter が3鍵を持つ"
  else
    echo "  [FAIL] ケース3: .mdc の front matter が不正 (${mdc_file})" >&2
    rc=1
  fi

  # ケース4: AGENTS.md に規約本文が複製されていない
  ok4=1
  if [ -f "${out1}/AGENTS.md" ]; then
    grep -q '## 規則' "${out1}/AGENTS.md" && ok4=0
    grep -q 'docs/rules/code-standards/naming/rule.md' "${out1}/AGENTS.md" || ok4=0
  else
    ok4=0
  fi
  if [ "$ok4" -eq 1 ]; then
    echo "  [PASS] ケース4: AGENTS.md に規約本文が複製されず、参照パスのみ列挙"
  else
    echo "  [FAIL] ケース4: AGENTS.md の内容が不正" >&2
    rc=1
  fi

  # ケース5: hooksの登録先が docs/rules/ 配下の相対パスを指し、スクリプトが複製されない
  ok5=1
  grep -q '"docs/rules/code-standards/naming/check-naming.sh"' "${out1}/.claude/settings.json" 2>/dev/null || ok5=0
  grep -q '"docs/rules/code-standards/naming/check-naming.sh"' "${out1}/.cursor/hooks.json" 2>/dev/null || ok5=0
  grep -q 'docs/rules/code-standards/naming/check-naming.sh' "${out1}/.codex/config.toml" 2>/dev/null || ok5=0
  if [ -n "$(find "$out1" -name 'check-naming.sh' 2>/dev/null)" ]; then
    ok5=0
  fi
  if [ "$ok5" -eq 1 ]; then
    echo "  [PASS] ケース5: hooks登録は docs/rules/ 配下の相対パス参照のみで、スクリプト実体は複製されない"
  else
    echo "  [FAIL] ケース5: hooks登録またはスクリプト複製が不正" >&2
    rc=1
  fi

  # ケース6: 同じ入力で2回実行した結果がbyte単位で同一（決定的生成・冪等）
  out2="$(mktemp -d "${TMPDIR:-/tmp}/build-derived-rules-self-test-out2.XXXXXX")"
  APPLY=1
  run_build "$src" "$out2" >/dev/null 2>&1
  # out1 に対してもう一度 --apply して、既存生成物への再適用が冪等であることも確認する
  run_build "$src" "$out1" >/dev/null 2>&1
  bst_diff_log="$(mktemp "${TMPDIR:-/tmp}/build-derived-rules-bst-diff.XXXXXX")"
  if diff -r "$out1" "$out2" >"$bst_diff_log" 2>&1; then
    echo "  [PASS] ケース6: 決定的生成（同一入力→byte単位で同一の出力）・再適用の冪等性"
  else
    echo "  [FAIL] ケース6: 生成結果が決定的でない" >&2
    sed 's/^/    /' "$bst_diff_log" >&2
    rc=1
  fi
  rm -f "$bst_diff_log"

  # ケース7: AGENTS.md の親見出しが日本語表示名になっている（ケバブケースのままではない）
  ok7=1
  if [ -f "${out1}/AGENTS.md" ]; then
    grep -q '^## AIエージェント運用$' "${out1}/AGENTS.md" || ok7=0
    grep -q '^## コード規約$' "${out1}/AGENTS.md" || ok7=0
    grep -q '^## agent-operations$' "${out1}/AGENTS.md" && ok7=0
    grep -q '^## code-standards$' "${out1}/AGENTS.md" && ok7=0
  else
    ok7=0
  fi
  if [ "$ok7" -eq 1 ]; then
    echo "  [PASS] ケース7: AGENTS.md の親見出しが parent.yml の日本語表示名になっている"
  else
    echo "  [FAIL] ケース7: AGENTS.md の親見出しが日本語表示名になっていない" >&2
    rc=1
  fi

  # ケース10: mcp-servers.json (McpCanon) から .mcp.json の mcpServers が生成される
  ok10=1
  if [ -f "${out1}/.mcp.json" ]; then
    jq -e '.mcpServers["fs-tools"].command == "node"' "${out1}/.mcp.json" >/dev/null 2>&1 || ok10=0
    jq -e '.mcpServers["remote-search"].url == "https://example.invalid/mcp"' "${out1}/.mcp.json" >/dev/null 2>&1 || ok10=0
  else
    ok10=0
  fi
  if [ "$ok10" -eq 1 ]; then
    echo "  [PASS] ケース10: .mcp.json の mcpServers が stdio・remote 両方を含めて生成される"
  else
    echo "  [FAIL] ケース10: .mcp.json の mcpServers 生成が不正" >&2
    rc=1
  fi

  # ケース11: .codex/config.toml に stdio型のみ [mcp_servers.*] として反映され、remote型は変換対象外
  ok11=1
  if [ -f "${out1}/.codex/config.toml" ]; then
    grep -q '\[mcp_servers.fs-tools\]' "${out1}/.codex/config.toml" || ok11=0
    grep -q 'command = "node"' "${out1}/.codex/config.toml" || ok11=0
    grep -q '\[mcp_servers.remote-search\]' "${out1}/.codex/config.toml" && ok11=0
  else
    ok11=0
  fi
  if [ "$ok11" -eq 1 ]; then
    echo "  [PASS] ケース11: .codex/config.toml の mcp_servers はstdio型のみ生成され、remote型は変換対象外"
  else
    echo "  [FAIL] ケース11: .codex/config.toml の mcp_servers 生成が不正" >&2
    rc=1
  fi

  # ケース12: mcp-servers.json が不在の入力では .mcp.json・mcp_servers ブロックを生成しない(skip)
  local src_nomcp out12 ok12
  src_nomcp="$(mktemp -d "${TMPDIR:-/tmp}/build-derived-rules-self-test-nomcp.XXXXXX")"
  bst_write_fixture "$src_nomcp"
  rm -f "${src_nomcp}/mcp-servers.json"
  out12="$(mktemp -d "${TMPDIR:-/tmp}/build-derived-rules-self-test-out12.XXXXXX")"
  APPLY=1
  run_build "$src_nomcp" "$out12" >/dev/null 2>&1
  ok12=1
  [ -f "${out12}/.mcp.json" ] && ok12=0
  if [ -f "${out12}/.codex/config.toml" ] && grep -q 'mcp_servers' "${out12}/.codex/config.toml" 2>/dev/null; then
    ok12=0
  fi
  if [ "$ok12" -eq 1 ]; then
    echo "  [PASS] ケース12: mcp-servers.json 不在時は .mcp.json・mcp_servers ブロックを生成しない"
  else
    echo "  [FAIL] ケース12: mcp-servers.json 不在時にもMCP関連生成物ができてしまった" >&2
    rc=1
  fi
  rm -rf "$src_nomcp" "$out12"

  rm -rf "$src" "$out1" "$out2"

  # ケース8: --deploy-rule-scripts で4本が配備され、実行可能である
  local deploy_out ok8 deploy_dir
  deploy_out="$(mktemp -d "${TMPDIR:-/tmp}/build-derived-rules-self-test-deploy.XXXXXX")"
  deploy_dir="${deploy_out}/docs/rules/agent-operations/ai-config-asset-management"
  deploy_rule_scripts "$deploy_out" >/dev/null 2>&1
  ok8=1
  [ -x "${deploy_dir}/build-derived-rules.sh" ] || ok8=0
  [ -x "${deploy_dir}/validate-rule-definitions.sh" ] || ok8=0
  [ -x "${deploy_dir}/check-rule-drift.sh" ] || ok8=0
  [ -x "${deploy_dir}/resolve-applicable-rules.sh" ] || ok8=0
  if [ "$ok8" -eq 1 ]; then
    bash "${deploy_dir}/validate-rule-definitions.sh" --self-test >/dev/null 2>&1 || ok8=0
  fi
  if [ "$ok8" -eq 1 ]; then
    bash "${deploy_dir}/check-rule-drift.sh" --self-test >/dev/null 2>&1 || ok8=0
  fi
  if [ "$ok8" -eq 1 ]; then
    bash "${deploy_dir}/resolve-applicable-rules.sh" --self-test >/dev/null 2>&1 || ok8=0
  fi
  if [ "$ok8" -eq 1 ]; then
    local usage_out
    usage_out="$(bash "${deploy_dir}/build-derived-rules.sh" 2>&1 || true)"
    printf '%s' "$usage_out" | grep -q "使い方" || ok8=0
  fi
  if [ "$ok8" -eq 1 ]; then
    echo "  [PASS] ケース8: --deploy-rule-scripts で4本が配備され、実行可能である"
  else
    echo "  [FAIL] ケース8: --deploy-rule-scriptsの配備または実行に失敗した" >&2
    rc=1
  fi
  rm -rf "$deploy_out"

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi

  if [ "${1:-}" = "--deploy-rule-scripts" ]; then
    local deploy_target="${2:-}"
    if [ -z "$deploy_target" ]; then
      echo "使い方: $(basename "$0") --deploy-rule-scripts <出力先リポジトリルート>" >&2
      exit 1
    fi
    deploy_rule_scripts "$deploy_target"
    exit $?
  fi

  local root="" out_root="" apply_flag=0
  local args=()
  for a in "$@"; do
    if [ "$a" = "--apply" ]; then
      apply_flag=1
    else
      args+=("$a")
    fi
  done

  if [ "${#args[@]}" -ne 2 ]; then
    echo "使い方: $(basename "$0") <docs/rules のルート> <出力先リポジトリルート> [--apply]" >&2
    echo "        $(basename "$0") --deploy-rule-scripts <出力先リポジトリルート>" >&2
    echo "        $(basename "$0") --self-test" >&2
    exit 1
  fi

  root="${args[0]}"
  out_root="${args[1]}"
  APPLY="$apply_flag"

  run_build "$root" "$out_root"
  exit $?
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main "$@"
fi
