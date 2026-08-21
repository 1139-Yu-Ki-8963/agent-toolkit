#!/usr/bin/env bash
set -euo pipefail

# rule-scope-overrides.sh — 規約の適用範囲（scope・paths）に対する対象側の上書きを解決する
#
# 対応する指示書: docs/tasks/対象プロジェクトの実態を反映させる指示書.md 3.3
#   （適用範囲に対象側の受け口を設ける。適用範囲以外の前付けの鍵は対象外とする）
#
# 目的:
#   scaffold-rule-definitions.sh は前付けの scope・paths を
#   delivery-payload/references/rule-taxonomy.json（触らない）の既定値から直接読んでいた。
#   対象プロジェクト固有の値（実在するディレクトリへ合わせた paths 等）を宣言する受け口が
#   無く、配置を再実行するたびに既定値へ戻っていた（実測: 対象26本すべて）。
#   本スクリプトは output-layout.sh と同じ形式（対象側の宣言ファイルを読み、
#   キー単位で合成する）で、この受け口を提供する。
#
# 使い方:
#   source "path/to/rule-scope-overrides.sh"
#   overrides_json="$(resolve_rule_scope_overrides <out_root>)" || exit 1
#   scope="$(rule_scope_override_get "$overrides_json" <子カテゴリkey> scope)"   # 無ければ空文字・exit 1
#   paths="$(rule_scope_override_get "$overrides_json" <子カテゴリkey> paths)"   # 無ければ空文字・exit 1
#
# 宣言ファイルの置き場と形式（決めていないこと4。本スクリプトでの選択）:
#   <out_root>/docs/rules/rule-scope-overrides.json
#   {
#     "specVersion": 1,
#     "overrides": {
#       "<子カテゴリkey>": { "scope": "scoped", "paths": ["src/**"] }
#     }
#   }
#   宣言が無いキーは taxonomy の既定値（scaffold-rule-definitions.sh側でそのまま使う）を保つ。
#   scope は "always" または "scoped" のみを許可する。"scoped" の場合は paths が
#   非空の文字列配列であることを要求する。"always" の場合、paths を省略すれば
#   既定 ["**/*"] を補うが、明示された場合はそのまま使う（空配列は不合格にする）。
#   ファイル自体が存在しない場合はエラーにせず、上書きなし（overrides: {}）として扱う
#   （output-layout.jsonの対象側上書きファイルが任意である扱いと揃える）。
#
# 保守責任者・廃棄条件: generation-engine/scripts/rules/rule.md の「## 設計判断」を参照。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。

RULE_SCOPE_OVERRIDES_FILE_NAME="rule-scope-overrides.json"

# <out_root>/docs/rules/rule-scope-overrides.json を読み、妥当性を検査して返す。
# 存在しない場合は overrides:{} を返す（エラーにしない）。
# resolve_rule_scope_overrides <out_root>
resolve_rule_scope_overrides() {
  local out_root="$1" target_file
  target_file="${out_root}/docs/rules/${RULE_SCOPE_OVERRIDES_FILE_NAME}"

  if [ ! -f "$target_file" ]; then
    printf '{"specVersion":1,"overrides":{}}'
    return 0
  fi

  local doc
  if ! doc="$(jq -c '.' "$target_file" 2>/dev/null)"; then
    echo "ERROR: ${target_file} がJSONとして読めません" >&2
    return 1
  fi

  local spec_version
  spec_version="$(printf '%s' "$doc" | jq -r '.specVersion // 0')"
  if [ "$spec_version" != "1" ]; then
    echo "ERROR: ${target_file} の specVersion が 1 ではありません" >&2
    return 1
  fi

  if ! printf '%s' "$doc" | jq -e '(.overrides // {}) | type == "object"' >/dev/null 2>&1; then
    echo "ERROR: ${target_file} の overrides はオブジェクトである必要があります" >&2
    return 1
  fi

  local keys key scope paths_type
  keys="$(printf '%s' "$doc" | jq -r '(.overrides // {}) | keys[]' 2>/dev/null || true)"
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    scope="$(printf '%s' "$doc" | jq -r --arg k "$key" '.overrides[$k].scope // empty')"
    case "$scope" in
      always|scoped) ;;
      *)
        echo "ERROR: ${target_file} の overrides.${key}.scope は always か scoped である必要があります（実際: ${scope:-（未指定）}）" >&2
        return 1
        ;;
    esac
    paths_type="$(printf '%s' "$doc" | jq -r --arg k "$key" '.overrides[$k].paths | if . == null then "null" else type end')"
    if [ "$scope" = "scoped" ]; then
      if [ "$paths_type" != "array" ]; then
        echo "ERROR: ${target_file} の overrides.${key} は scope:scoped のため paths（非空の配列）が必須です" >&2
        return 1
      fi
      local paths_len
      paths_len="$(printf '%s' "$doc" | jq -r --arg k "$key" '.overrides[$k].paths | length')"
      if [ "$paths_len" -eq 0 ]; then
        echo "ERROR: ${target_file} の overrides.${key}.paths は空配列にできません" >&2
        return 1
      fi
    else
      if [ "$paths_type" != "array" ] && [ "$paths_type" != "null" ]; then
        echo "ERROR: ${target_file} の overrides.${key}.paths は配列である必要があります" >&2
        return 1
      fi
      if [ "$paths_type" = "array" ]; then
        local paths_len_always
        paths_len_always="$(printf '%s' "$doc" | jq -r --arg k "$key" '.overrides[$k].paths | length')"
        if [ "$paths_len_always" -eq 0 ]; then
          echo "ERROR: ${target_file} の overrides.${key}.paths は空配列にできません" >&2
          return 1
        fi
      fi
    fi
  done <<EOF
$keys
EOF

  printf '%s' "$doc"
  return 0
}

# 合成済みJSONからキー（子カテゴリのkey）の上書き値を取り出す。
# 上書きが無い場合は空文字を返し、終了コード1にする（呼び出し側は既定値へフォールバックする）。
# rule_scope_override_get <resolve済みJSON> <子カテゴリkey> <scope|paths>
rule_scope_override_get() {
  local doc="$1" key="$2" field="$3"

  if [ "$field" != "scope" ] && [ "$field" != "paths" ]; then
    echo "ERROR: field は scope か paths のみ許可されます: ${field}" >&2
    return 2
  fi

  if ! printf '%s' "$doc" | jq -e --arg k "$key" '(.overrides // {}) | has($k)' >/dev/null 2>&1; then
    printf ''
    return 1
  fi

  if [ "$field" = "scope" ]; then
    printf '%s' "$doc" | jq -r --arg k "$key" '.overrides[$k].scope'
    return 0
  fi

  # paths: always かつ省略時は既定 ["**/*"] を補う
  local paths_type
  paths_type="$(printf '%s' "$doc" | jq -r --arg k "$key" '.overrides[$k].paths | if . == null then "null" else type end')"
  if [ "$paths_type" = "null" ]; then
    printf '["**/*"]'
    return 0
  fi
  printf '%s' "$doc" | jq -c --arg k "$key" '.overrides[$k].paths'
  return 0
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

rule_scope_overrides_self_test() {
  local rc=0
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/rule-scope-overrides-self-test.XXXXXX")"

  # ケース1: 宣言ファイルが無ければ overrides:{} を返しエラーにしない
  local base1
  base1="$(resolve_rule_scope_overrides "$tmp" 2>/dev/null)" || true
  if [ "$(printf '%s' "$base1" | jq -c '.overrides')" = "{}" ]; then
    echo "  [PASS] ケース1: 宣言ファイル不在時は overrides:{} を返す"
  else
    echo "  [FAIL] ケース1: 宣言ファイル不在時の既定値が不正: ${base1}" >&2
    rc=1
  fi

  # ケース2: 上書きが無いキーは rule_scope_override_get が終了コード1・空文字を返す
  local v2 rc2
  if v2="$(rule_scope_override_get "$base1" not-declared-key scope)"; then rc2=0; else rc2=$?; fi
  if [ "$rc2" -eq 1 ] && [ -z "$v2" ]; then
    echo "  [PASS] ケース2: 未宣言キーは空文字・終了コード1を返す"
  else
    echo "  [FAIL] ケース2: 未宣言キーの戻り値が不正（rc=${rc2} v=${v2}）" >&2
    rc=1
  fi

  # ケース3: scope:scoped + paths を宣言すると解決・取得できる
  mkdir -p "${tmp}/docs/rules"
  cat > "${tmp}/docs/rules/rule-scope-overrides.json" <<'EOF'
{
  "specVersion": 1,
  "overrides": {
    "naming": { "scope": "scoped", "paths": ["apps/web/src/**", "apps/api/src/**"] }
  }
}
EOF
  local base3 scope3 paths3
  base3="$(resolve_rule_scope_overrides "$tmp")"
  scope3="$(rule_scope_override_get "$base3" naming scope)"
  paths3="$(rule_scope_override_get "$base3" naming paths)"
  if [ "$scope3" = "scoped" ] && [ "$paths3" = '["apps/web/src/**","apps/api/src/**"]' ]; then
    echo "  [PASS] ケース3: scope:scoped + paths の宣言を解決・取得できる"
  else
    echo "  [FAIL] ケース3: 実際 scope=${scope3} paths=${paths3}" >&2
    rc=1
  fi

  # ケース4: scope:scoped で paths を省略すると不合格（scoped は paths 必須）
  cat > "${tmp}/docs/rules/rule-scope-overrides.json" <<'EOF'
{
  "specVersion": 1,
  "overrides": {
    "naming": { "scope": "scoped" }
  }
}
EOF
  if _gt_out3="$(resolve_rule_scope_overrides "$tmp" 2>&1)"; then
    echo "  [FAIL] ケース4: scope:scoped で paths 省略が不合格にならない" >&2
    printf '%s\n' "$_gt_out3" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] ケース4: scope:scoped で paths 省略は不合格になる"
  fi

  # ケース5: scope:always で paths 省略時は既定 ["**/*"] を補う
  cat > "${tmp}/docs/rules/rule-scope-overrides.json" <<'EOF'
{
  "specVersion": 1,
  "overrides": {
    "ai-behavior": { "scope": "always" }
  }
}
EOF
  local base5 paths5
  base5="$(resolve_rule_scope_overrides "$tmp")"
  paths5="$(rule_scope_override_get "$base5" ai-behavior paths)"
  if [ "$paths5" = '["**/*"]' ]; then
    echo "  [PASS] ケース5: scope:always で paths 省略時は既定 [\"**/*\"] を補う"
  else
    echo "  [FAIL] ケース5: 実際 paths=${paths5}" >&2
    rc=1
  fi

  # ケース6: scope が不正な値なら不合格
  cat > "${tmp}/docs/rules/rule-scope-overrides.json" <<'EOF'
{
  "specVersion": 1,
  "overrides": {
    "naming": { "scope": "invalid-value", "paths": ["src/**"] }
  }
}
EOF
  if _gt_out4="$(resolve_rule_scope_overrides "$tmp" 2>&1)"; then
    echo "  [FAIL] ケース6: 不正な scope 値が不合格にならない" >&2
    printf '%s\n' "$_gt_out4" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] ケース6: 不正な scope 値は不合格になる"
  fi

  rm -rf "$tmp"

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  if [ "${1:-}" = "--self-test" ]; then
    rule_scope_overrides_self_test
    exit $?
  fi
  echo "使い方: $(basename "$0") --self-test（他スクリプトから source して使う）" >&2
  exit 1
fi
