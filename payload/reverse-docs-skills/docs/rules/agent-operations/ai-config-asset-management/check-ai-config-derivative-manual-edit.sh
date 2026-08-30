#!/usr/bin/env bash
# check-ai-config-derivative-manual-edit.sh — 定義と生成物の分け方の決まりの linter
#
# timing: PreToolUse(Write|Edit|MultiEdit)
# 対象規約: 定義と生成物の分け方の決まり（検査列に「静的解析:」を含む3件すべてを検査する）
#
# 対象の規則:
#   1. 定義は docs に置く
#      — 書き込み先が .claude/rules/・.cursor/rules/・.codex/ のいずれかの配下
#        （派生の置き場）である場合に、docs/rules 配下に同じファイル名の定義が
#        実在するかを走査する
#   2. 派生は生成物として扱う
#      — 書き込み先が派生の置き場そのものであれば、直接編集として拒否する
#        （既存の検査。判定はファイルパスの一致だけで行う）
#   3. ずれは台帳で検知する
#      — 台帳の置き場は対象プロジェクトごとに異なるため、対象プロジェクトの
#        docs/rules 配下の「## このプロジェクトの規則」表に宣言された台帳の
#        パスを読み、その実在だけを確かめる
#
# 入力（hooks標準形。stdin JSON）:
#   .tool_name             "Write" / "Edit" / "MultiEdit" のときのみ判定対象
#   .tool_input.file_path  書き込み先の絶対パス（または相対パス）
#   .cwd                   ツールを実行する作業ディレクトリ（絶対パス）
#
# 判定の設計:
#   「定義は docs に置く」と「ずれは台帳で検知する」は、書き込み先のツールが
#   Write/Edit/MultiEdit のいずれであるかによらず判定できるため、集約関数
#   judge() の冒頭で呼ぶ。「派生は生成物として扱う」は既存のツール種別判定を
#   保つため、集約関数の末尾に残す。
#
# 既知の限界:
#   - 「ずれは台帳で検知する」は台帳に記録された内容ハッシュと各派生物の
#     現在の内容ハッシュを突合する処理を実装しない。台帳の形式（キー・値の
#     構造）が「このプロジェクトの規則」の宣言に書かれておらず、汎用の
#     linter からは読み取れないため、台帳ファイルの実在確認にとどめる
#   - 「定義は docs に置く」は同名ファイルの実在だけを確かめる。ファイルの
#     中身が対応する定義として妥当かまでは判定しない
#
# 止めるか知らせるか:
#   定義は docs に置く: 止める（対応する定義を欠いた派生物がそのままコミットされると、正本不在の派生が履歴に残り事後に取り消せなくなるため）
#   ずれは台帳で検知する: 止める（台帳が実在しないまま派生が進むと、ずれを検知できない状態のまま履歴が積み上がり事後に取り消せなくなるため）
#   派生は生成物として扱う: 止める（生成物への直接の手作業編集は、再生成で消えるか気付かれず残るかのいずれかになり、取り消しがきかないため）
#
# 逃げ道:
#   AI_CONFIG_DERIVATIVE_MANUAL_EDIT_SKIP_REASON に理由を書けば通る。理由が空の場合は通らない
#
# 使い方:
#   フック本体として: PreToolUse(Write|Edit|MultiEdit) の入力 JSON を stdin から受け取る
#   単体実行: check-ai-config-derivative-manual-edit.sh --self-test
set -uo pipefail

# cwd 配下の docs/rules/**/rule.md の「## このプロジェクトの規則」表から、
# 規則名（第1列）が完全一致する行の内容列（第2列）を1件返す。無ければ空文字。
lookup_project_override_content() {
  # $1: cwd, $2: rule name
  local cwd="$1" name="$2" file
  [ -d "$cwd/docs/rules" ] || return 0
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    awk -v name="$name" '
      BEGIN { insec = 0 }
      /^## このプロジェクトの規則/ { insec = 1; next }
      /^## / && insec == 1 { insec = 0 }
      insec == 1 && /^\|/ {
        line = $0
        if (line ~ /^\| *規則 *\|/) next
        if (line ~ /^\|[-: ]+\|[-: ]+\|/) next
        n = split(line, cols, "|")
        rule = cols[2]; gsub(/^[ \t]+|[ \t]+$/, "", rule)
        if (rule == name) {
          content = cols[3]; gsub(/^[ \t]+|[ \t]+$/, "", content)
          print content
          exit
        }
      }
    ' "$file"
  done < <(find "$cwd/docs/rules" -name 'rule.md' 2>/dev/null) | head -1
}

# 「定義は docs に置く」規則の判定
judge_definition_in_docs() {
  # $1: cwd, $2: file_path
  local cwd="$1" file_path="$2"

  if ! [[ "$file_path" =~ (^|/)\.claude/rules/ ]] \
    && ! [[ "$file_path" =~ (^|/)\.cursor/rules/ ]] \
    && ! [[ "$file_path" =~ (^|/)\.codex/ ]]; then
    echo "対象外[定義は docs に置く]: 派生の置き場ではありません（${file_path}）"
    return 0
  fi

  if [ -z "$cwd" ] || [ ! -d "$cwd/docs/rules" ]; then
    echo "通知[定義は docs に置く]: docs/rules が見当たらないため、対応する定義の有無を判定していません"
    return 0
  fi

  local base found
  base="$(basename "$file_path")"
  found="$(find "$cwd/docs/rules" -type f -name "$base" 2>/dev/null | head -1)"

  if [ -n "$found" ]; then
    local relpath="${found#"$cwd"/}"
    echo "許可[定義は docs に置く]: 対応する定義が docs/rules 配下に実在します（${relpath}）"
    return 0
  fi

  echo "拒否[定義は docs に置く]: docs/rules 配下に対応する定義がありません。定義を docs 側へ置いてから派生を生成してください"
  return 2
}

# 「ずれは台帳で検知する」規則の判定
judge_drift_ledger() {
  # $1: cwd
  local cwd="$1"

  local override
  override="$(lookup_project_override_content "$cwd" "ずれは台帳で検知する")"
  if [ -z "$override" ]; then
    echo "通知[ずれは台帳で検知する]: このプロジェクトの規則に台帳の置き場の宣言がないため判定していません。リバース解析を実行すると判定の対象になります"
    return 0
  fi

  local token
  token="$(printf '%s\n' "$override" | tr ' ' '\n' | grep -E '(/|\.json$)' | head -1)"
  if [ -z "$token" ]; then
    echo "通知[ずれは台帳で検知する]: このプロジェクトの規則に宣言はありますが、台帳の置き場を読み取れません"
    return 0
  fi

  if [ ! -f "$cwd/$token" ]; then
    echo "拒否[ずれは台帳で検知する]: 宣言された台帳（${token}）が実在しません"
    return 2
  fi

  echo "許可[ずれは台帳で検知する]: 宣言された台帳（${token}）が実在します"
  return 0
}

judge() {
  # $1: tool_name, $2: file_path, $3: cwd（省略可）
  # 標準出力: 判定理由（複数行になりうる）。戻り値: 0=許可・2=拒否
  local tool="$1" file_path="$2" cwd="${3:-}"

  # 規則: 定義は docs に置く
  local def_msg def_code
  if def_msg="$(judge_definition_in_docs "$cwd" "$file_path")"; then def_code=0; else def_code=$?; fi
  echo "$def_msg"
  if [ "$def_code" -eq 2 ]; then
    return 2
  fi

  # 規則: ずれは台帳で検知する
  local ledger_msg ledger_code
  if ledger_msg="$(judge_drift_ledger "$cwd")"; then ledger_code=0; else ledger_code=$?; fi
  echo "$ledger_msg"
  if [ "$ledger_code" -eq 2 ]; then
    return 2
  fi

  # 規則: 派生は生成物として扱う
  case "$tool" in
    Write|Edit|MultiEdit) ;;
    *)
      echo "対象外[派生は生成物として扱う]: Write/Edit/MultiEdit 以外のツールのため対象外（${tool}）"
      return 0
      ;;
  esac

  if [ -z "$file_path" ]; then
    echo "対象外[派生は生成物として扱う]: file_path が空のため判定不能（fail-open）"
    return 0
  fi

  if [[ "$file_path" =~ (^|/)\.claude/rules/ ]] \
    || [[ "$file_path" =~ (^|/)\.cursor/rules/ ]] \
    || [[ "$file_path" =~ (^|/)\.codex/ ]]; then
    echo "拒否[派生は生成物として扱う]: ${file_path} は .claude/rules・.cursor/rules・.codex 配下の派生物であり、直接編集は禁止されています"
    return 2
  fi

  echo "許可[派生は生成物として扱う]: 派生物の置き場パターンに一致しません（${file_path}）"
  return 0
}

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${AI_CONFIG_DERIVATIVE_MANUAL_EDIT_SKIP_REASON:-}" ]; then
    echo "[AI-CONFIG-DERIVATIVE-MANUAL-EDIT-SKIP] 理由: ${AI_CONFIG_DERIVATIVE_MANUAL_EDIT_SKIP_REASON}"
    return 0
  fi
  return 1
}

run_hook() {
  local skip_msg
  if skip_msg="$(should_skip_with_reason)"; then
    printf '%s\n' "$skip_msg" >&2
    exit 0
  fi

  local input
  input="$(cat)"
  [ -z "$input" ] && exit 0

  if ! command -v jq >/dev/null 2>&1; then
    exit 0
  fi

  local tool
  tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0

  local file_path cwd msg code
  file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null) || exit 0

  if msg="$(judge "$tool" "$file_path" "$cwd")"; then code=0; else code=$?; fi

  if [ "$code" -eq 0 ]; then
    exit 0
  fi

  ctx="[AI-CONFIG-DERIVATIVE-MANUAL-EDIT-BLOCK] ${msg}。編集は docs/ 配下の定義から行い、派生物は生成し直してください。"
  jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  printf '%s\n' "$ctx" >&2
  exit 2
}

self_test() {
  local rc=0 msg code

  # 系1: .claude/rules 配下への Edit は拒否される
  if msg="$(judge "Edit" "/repo/.claude/rules/foo/bar/rule.md")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系1: .claude/rules 配下への Edit は拒否される（${msg}）"
  else
    echo "  [FAIL] 系1: .claude/rules 配下への Edit が許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系2: .codex 配下への Write は拒否される
  if msg="$(judge "Write" "/repo/.codex/AGENTS.md")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系2: .codex 配下への Write は拒否される（${msg}）"
  else
    echo "  [FAIL] 系2: .codex 配下への Write が許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系3: .cursor/rules 配下への MultiEdit は拒否される
  if msg="$(judge "MultiEdit" "/repo/.cursor/rules/baz/rule.md")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系3: .cursor/rules 配下への MultiEdit は拒否される（${msg}）"
  else
    echo "  [FAIL] 系3: .cursor/rules 配下への MultiEdit が許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系4: docs/rules（定義側）への Write は許可される
  if msg="$(judge "Write" "/repo/docs/rules/foo/bar/rule.md")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系4: docs/rules（定義側）への Write は許可される（${msg}）"
  else
    echo "  [FAIL] 系4: docs/rules への Write が拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系5: Read は対象外として許可される
  if msg="$(judge "Read" "/repo/.claude/rules/foo/rule.md")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系5: Read は対象外として許可される（${msg}）"
  else
    echo "  [FAIL] 系5: Read が拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系6: file_path が空は fail-open で許可される
  if msg="$(judge "Write" "")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系6: file_path 空は fail-open で許可される（${msg}）"
  else
    echo "  [FAIL] 系6: file_path 空なのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系7: 派生の置き場ではないファイルは「定義は docs に置く」の対象外になる
  if msg="$(judge_definition_in_docs "" "/repo/docs/rules/foo/rule.md")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '対象外[定義は docs に置く]'; then
    echo "  [PASS] 系7: 派生の置き場でなければ「定義は docs に置く」は対象外になる（${msg}）"
  else
    echo "  [FAIL] 系7: 対象外にならなかった、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系8: docs/rules が見当たらない → 通知
  local tmp8
  if ! tmp8="$(mktemp -d "${TMPDIR:-/tmp}/check-ai-config-derivative-manual-edit-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp8" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  if msg="$(judge_definition_in_docs "$tmp8" "/repo/.claude/rules/foo/rule.md")"; then code=0; else code=$?; fi
  rm -rf "$tmp8"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '通知[定義は docs に置く]'; then
    echo "  [PASS] 系8: docs/rules が見当たらなければ「定義は docs に置く」は通知になる（${msg}）"
  else
    echo "  [FAIL] 系8: 通知にならなかった、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系9: docs/rules はあるが対応する定義が無い → 拒否
  local tmp9
  if ! tmp9="$(mktemp -d "${TMPDIR:-/tmp}/check-ai-config-derivative-manual-edit-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp9" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  mkdir -p "$tmp9/docs/rules"
  if msg="$(judge_definition_in_docs "$tmp9" "$tmp9/.claude/rules/foo/rule.md")"; then code=0; else code=$?; fi
  rm -rf "$tmp9"
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '拒否[定義は docs に置く]'; then
    echo "  [PASS] 系9: 対応する定義が無ければ「定義は docs に置く」は拒否される（${msg}）"
  else
    echo "  [FAIL] 系9: 拒否されなかった、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系10: docs/rules に対応するファイル名の定義が実在する → 許可
  local tmp10
  if ! tmp10="$(mktemp -d "${TMPDIR:-/tmp}/check-ai-config-derivative-manual-edit-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp10" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  mkdir -p "$tmp10/docs/rules/foo" "$tmp10/.claude/rules/bar"
  printf '# 定義\n' > "$tmp10/docs/rules/foo/rule.md"
  if msg="$(judge_definition_in_docs "$tmp10" "$tmp10/.claude/rules/bar/rule.md")"; then code=0; else code=$?; fi
  rm -rf "$tmp10"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '許可[定義は docs に置く]'; then
    echo "  [PASS] 系10: 対応する定義が実在すれば「定義は docs に置く」は許可される（${msg}）"
  else
    echo "  [FAIL] 系10: 許可されなかった、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系11: 台帳の置き場の宣言が無い → 通知
  local tmp11
  if ! tmp11="$(mktemp -d "${TMPDIR:-/tmp}/check-ai-config-derivative-manual-edit-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp11" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  if msg="$(judge_drift_ledger "$tmp11")"; then code=0; else code=$?; fi
  rm -rf "$tmp11"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '通知[ずれは台帳で検知する]'; then
    echo "  [PASS] 系11: 宣言が無ければ「ずれは台帳で検知する」は通知になる（${msg}）"
  else
    echo "  [FAIL] 系11: 通知にならなかった、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系12: 宣言はあるが台帳の置き場を読み取れない → 通知
  local tmp12
  if ! tmp12="$(mktemp -d "${TMPDIR:-/tmp}/check-ai-config-derivative-manual-edit-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp12" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  mkdir -p "$tmp12/docs/rules/foo"
  cat > "$tmp12/docs/rules/foo/rule.md" <<'EOF'
# 規約

## このプロジェクトの規則

| 規則 | 内容 | 検査 |
|---|---|---|
| ずれは台帳で検知する | 台帳は特に定めない | 静的解析 |
EOF
  if msg="$(judge_drift_ledger "$tmp12")"; then code=0; else code=$?; fi
  rm -rf "$tmp12"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '通知[ずれは台帳で検知する]'; then
    echo "  [PASS] 系12: 宣言はあるが読み取れなければ「ずれは台帳で検知する」は通知になる（${msg}）"
  else
    echo "  [FAIL] 系12: 通知にならなかった、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系13: 宣言された台帳が実在しない → 拒否
  local tmp13
  if ! tmp13="$(mktemp -d "${TMPDIR:-/tmp}/check-ai-config-derivative-manual-edit-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp13" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  mkdir -p "$tmp13/docs/rules/foo"
  cat > "$tmp13/docs/rules/foo/rule.md" <<'EOF'
# 規約

## このプロジェクトの規則

| 規則 | 内容 | 検査 |
|---|---|---|
| ずれは台帳で検知する | 台帳は docs/derived-ledger.json に置く | 静的解析 |
EOF
  if msg="$(judge_drift_ledger "$tmp13")"; then code=0; else code=$?; fi
  rm -rf "$tmp13"
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '拒否[ずれは台帳で検知する]'; then
    echo "  [PASS] 系13: 宣言された台帳が実在しなければ「ずれは台帳で検知する」は拒否される（${msg}）"
  else
    echo "  [FAIL] 系13: 拒否されなかった、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系14: 宣言された台帳が実在する → 許可
  local tmp14
  if ! tmp14="$(mktemp -d "${TMPDIR:-/tmp}/check-ai-config-derivative-manual-edit-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp14" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  mkdir -p "$tmp14/docs/rules/foo"
  cat > "$tmp14/docs/rules/foo/rule.md" <<'EOF'
# 規約

## このプロジェクトの規則

| 規則 | 内容 | 検査 |
|---|---|---|
| ずれは台帳で検知する | 台帳は docs/derived-ledger.json に置く | 静的解析 |
EOF
  printf '{}' > "$tmp14/docs/derived-ledger.json"
  if msg="$(judge_drift_ledger "$tmp14")"; then code=0; else code=$?; fi
  rm -rf "$tmp14"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '許可[ずれは台帳で検知する]'; then
    echo "  [PASS] 系14: 宣言された台帳が実在すれば「ずれは台帳で検知する」は許可される（${msg}）"
  else
    echo "  [FAIL] 系14: 許可されなかった、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系15: 環境変数に理由を設定すると should_skip_with_reason は skip する
  local skip_out skip_code
  if skip_out="$(AI_CONFIG_DERIVATIVE_MANUAL_EDIT_SKIP_REASON="テスト理由" should_skip_with_reason)"; then skip_code=0; else skip_code=$?; fi
  if [ "$skip_code" -eq 0 ] && printf '%s' "$skip_out" | grep -qF 'AI-CONFIG-DERIVATIVE-MANUAL-EDIT-SKIP' && printf '%s' "$skip_out" | grep -qF 'テスト理由'; then
    echo "  [PASS] 系15: 理由を設定すると should_skip_with_reason は skip する（${skip_out}）"
  else
    echo "  [FAIL] 系15: 理由があるのに skip しない、またはタグ・理由が含まれない（exit=${skip_code}, ${skip_out}）" >&2
    rc=1
  fi

  # 系16: 環境変数を空文字にすると should_skip_with_reason は skip しない
  local skip_code2
  if AI_CONFIG_DERIVATIVE_MANUAL_EDIT_SKIP_REASON="" should_skip_with_reason >/dev/null 2>&1; then skip_code2=0; else skip_code2=$?; fi
  if [ "$skip_code2" -eq 1 ]; then
    echo "  [PASS] 系16: 環境変数が空文字なら should_skip_with_reason は skip しない"
  else
    echo "  [FAIL] 系16: 空文字なのに skip した（exit=${skip_code2}）" >&2
    rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

case "${1:-}" in
  --self-test) self_test; exit $? ;;
  *) run_hook ;;
esac
