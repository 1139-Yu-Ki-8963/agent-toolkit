#!/usr/bin/env bash
set -euo pipefail

# validate-rule-definitions.sh — docs/rules/ 配下の規約定義の整合性検査
#
# 設計の定義: shared/references/規約定義と派生生成の設計.md（3節・9節）
#
# 目的:
#   docs/rules/<親>/<子>/rule.md の front matter を読み、設計9節が定める6検査と
#   front matter 13鍵の必須・値域を検査する。1件でも不合格なら終了コード1で
#   不合格内容を標準エラーへ列挙する。
#
# 使い方:
#   validate-rule-definitions.sh <docs/rules のルート>
#   validate-rule-definitions.sh --self-test
#
# 検査キー（設計9節の6検査）:
#   鍵-対応整合     checkable:true なら checker が非null かつ実在。false なら
#                   uncheckableReason が非null かつ非空
#   検査-テスト同伴  checker があるなら <checkerのベース名>.test.sh が同フォルダに実在
#   適用範囲-必須   scope:scoped なら globs が非空の配列
#   階層-一致       parent が親フォルダ名、key が子フォルダ名と一致
#   矯正-矛盾なし   全rule.mdのformatter指定（none以外）が単一の値に揃っている
#   派生-未承認除外  status が draft/approved のいずれか（値域検査。除外自体はbuild側）
#
# 終了コード:
#   0 = 全rule.mdが6検査とfront matter 13鍵の必須・値域を満たす
#   1 = 1件以上の不合格（内容は標準エラーへ列挙）
#   --self-test は上記に加え、期待どおりの検出ができなければ1
#
# 既知の制約:
#   YAMLパーサは使わない。front matterは "key: value" の1行表記のみ対応する。
#   配列（globs）は ["a", "b"] の1行表記のみ受け付け、複数行のブロック表記
#   （globs: のみ書いて次行以降に "- item" と続ける形）は不合格として明示的に報告する。
#   値に半角コロン+半角スペース（": "）を含む文字列は正しく分割できない（既知の限界）。
#
# 保守責任者: 人手（ユーザー）。front matterの鍵を増減する場合は本スクリプトの
#   EXPECTED_KEYS と shared/references/規約定義と派生生成の設計.md の3節を同時に更新する。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

EXPECTED_KEYS="key title parent summary scope globs enforcement checkable checker uncheckableReason formatter status origin"

FAILURES=""
FAIL_COUNT=0

add_failure() {
  # $1: file  $2: 検査キー  $3: 詳細
  FAILURES="${FAILURES}${1}: [${2}] ${3}
"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

# front matter本体（1行目と2行目の "---" に挟まれた範囲）を取り出す。
# 1行目が "---" でなければ空を返し、呼び出し側が不在として扱う。
fm_extract() {
  local file="$1"
  local first_line
  first_line="$(head -n1 "$file" 2>/dev/null || true)"
  if [ "$first_line" != "---" ]; then
    return 1
  fi
  awk 'NR==1{next} /^---$/{exit} {print}' "$file"
  return 0
}

# front matter本体からファイル末尾の "# <title>" 以降（本文）を取り出す。
body_extract() {
  local file="$1"
  awk 'BEGIN{c=0} /^---$/{c++; next} c>=2{print}' "$file"
}

# スカラー値（"key: value" 形式）を取り出す。無ければ空文字。
fm_get_scalar() {
  local body="$1" key="$2"
  printf '%s\n' "$body" | awk -v k="$key" '
    index($0, k ": ") == 1 { sub("^" k ": ", ""); print; exit }
    $0 == k ":" { print ""; exit }
  '
}

# key が front matter 本体に行として存在するかどうか（値が空でも存在扱い）。
fm_has_key() {
  local body="$1" key="$2"
  printf '%s\n' "$body" | grep -qE "^${key}:( |$)"
}

# 配列値（"key: [...]" の1行表記のみ対応）を取り出す。
# echo: 中身（角括弧含む）。戻り値: 0=取得成功 1=key不在 2=複数行ブロック表記（未対応）
fm_get_array() {
  local body="$1" key="$2"
  local line
  line="$(printf '%s\n' "$body" | grep -E "^${key}:" | head -n1 || true)"
  if [ -z "$line" ]; then
    return 1
  fi
  case "$line" in
    "${key}: ["*"]")
      printf '%s\n' "${line#"${key}: "}"
      return 0
      ;;
    *)
      return 2
      ;;
  esac
}

is_kebab() {
  printf '%s' "$1" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'
}

is_nonempty() {
  [ -n "$1" ]
}

# front matterに現れる全ての "先頭がidentifier:" のトップレベル鍵を抽出（重複含む）。
fm_all_key_lines() {
  local body="$1"
  printf '%s\n' "$body" | awk -F: '/^[A-Za-z0-9_]+:/{print $1}'
}

FORMATTER_VALUES=""  # ファイル横断でformatter値（none以外）を集める。 "file<TAB>value" 行

validate_one_rule() {
  local rule_file="$1"
  local child_dir parent_dir child_key_expected parent_key_expected
  child_dir="$(dirname "$rule_file")"
  parent_dir="$(dirname "$child_dir")"
  child_key_expected="$(basename "$child_dir")"
  parent_key_expected="$(basename "$parent_dir")"

  local body
  if ! body="$(fm_extract "$rule_file")"; then
    add_failure "$rule_file" "front-matter形式" "1行目が '---' ではないため front matter を認識できない"
    return
  fi

  # 鍵の過不足・重複検査
  local all_keys sorted_keys dup_keys key missing_keys extra_keys
  all_keys="$(fm_all_key_lines "$body")"
  dup_keys="$(printf '%s\n' "$all_keys" | sort | uniq -d || true)"
  if [ -n "$dup_keys" ]; then
    add_failure "$rule_file" "front-matter鍵-重複" "重複した鍵: $(printf '%s' "$dup_keys" | tr '\n' ' ')"
  fi
  missing_keys=""
  for key in $EXPECTED_KEYS; do
    if ! printf '%s\n' "$all_keys" | grep -qx "$key"; then
      missing_keys="${missing_keys}${key} "
    fi
  done
  if [ -n "$missing_keys" ]; then
    add_failure "$rule_file" "front-matter鍵-欠落" "必須13鍵のうち欠落: ${missing_keys}"
  fi
  extra_keys=""
  local ak
  for ak in $(printf '%s\n' "$all_keys" | sort -u); do
    local known=0
    for key in $EXPECTED_KEYS; do
      if [ "$ak" = "$key" ]; then
        known=1
        break
      fi
    done
    if [ "$known" -eq 0 ]; then
      extra_keys="${extra_keys}${ak} "
    fi
  done
  if [ -n "$extra_keys" ]; then
    add_failure "$rule_file" "front-matter鍵-未定義" "13鍵に無い未定義の鍵: ${extra_keys}"
  fi

  # スカラー値取得
  local v_key v_title v_parent v_summary v_scope v_enforcement v_checkable
  local v_checker v_uncheckable v_formatter v_status v_origin
  v_key="$(fm_get_scalar "$body" key)"
  v_title="$(fm_get_scalar "$body" title)"
  v_parent="$(fm_get_scalar "$body" parent)"
  v_summary="$(fm_get_scalar "$body" summary)"
  v_scope="$(fm_get_scalar "$body" scope)"
  v_enforcement="$(fm_get_scalar "$body" enforcement)"
  v_checkable="$(fm_get_scalar "$body" checkable)"
  v_checker="$(fm_get_scalar "$body" checker)"
  v_uncheckable="$(fm_get_scalar "$body" uncheckableReason)"
  v_formatter="$(fm_get_scalar "$body" formatter)"
  v_status="$(fm_get_scalar "$body" status)"
  v_origin="$(fm_get_scalar "$body" origin)"

  # 値域検査（13鍵）
  if ! is_nonempty "$v_key" || ! is_kebab "$v_key"; then
    add_failure "$rule_file" "値域-key" "key はケバブケースの非空文字列である必要がある（値: '${v_key}'）"
  fi
  if ! is_nonempty "$v_title"; then
    add_failure "$rule_file" "値域-title" "title は非空である必要がある"
  fi
  if ! is_nonempty "$v_parent" || ! is_kebab "$v_parent"; then
    add_failure "$rule_file" "値域-parent" "parent はケバブケースの非空文字列である必要がある（値: '${v_parent}'）"
  fi
  if ! is_nonempty "$v_summary"; then
    add_failure "$rule_file" "値域-summary" "summary は非空である必要がある"
  fi
  case "$v_scope" in
    always|scoped) ;;
    *) add_failure "$rule_file" "値域-scope" "scope は always/scoped のいずれかである必要がある（値: '${v_scope}'）" ;;
  esac
  case "$v_enforcement" in
    advisory|none) ;;
    *) add_failure "$rule_file" "値域-enforcement" "enforcement は advisory/none のいずれかである必要がある（値: '${v_enforcement}'）" ;;
  esac
  case "$v_checkable" in
    true|false) ;;
    *) add_failure "$rule_file" "値域-checkable" "checkable は true/false のいずれかである必要がある（値: '${v_checkable}'）" ;;
  esac
  case "$v_formatter" in
    prettier|biome|editorconfig|none) ;;
    *) add_failure "$rule_file" "値域-formatter" "formatter は prettier/biome/editorconfig/none のいずれかである必要がある（値: '${v_formatter}'）" ;;
  esac
  case "$v_status" in
    draft|approved) ;;
    *) add_failure "$rule_file" "派生-未承認除外" "status は draft/approved のいずれかである必要がある（値: '${v_status}'）" ;;
  esac
  case "$v_origin" in
    template|proposal|manual) ;;
    *) add_failure "$rule_file" "値域-origin" "origin は template/proposal/manual のいずれかである必要がある（値: '${v_origin}'）" ;;
  esac

  # 鍵-対応整合（checkable と checker / uncheckableReason の対応）
  if [ "$v_checkable" = "true" ]; then
    if [ -z "$v_checker" ] || [ "$v_checker" = "null" ]; then
      add_failure "$rule_file" "鍵-対応整合" "checkable:true だが checker が null または未設定"
    else
      if [ ! -f "${child_dir}/${v_checker}" ]; then
        add_failure "$rule_file" "鍵-対応整合" "checker '${v_checker}' が同フォルダに実在しない"
      else
        # 検査-テスト同伴
        local checker_base test_file
        checker_base="${v_checker%.sh}"
        test_file="${child_dir}/${checker_base}.test.sh"
        if [ ! -f "$test_file" ]; then
          add_failure "$rule_file" "検査-テスト同伴" "checker '${v_checker}' に対応する回帰テスト '${checker_base}.test.sh' が同フォルダに実在しない"
        fi
      fi
    fi
    if [ -n "$v_uncheckable" ] && [ "$v_uncheckable" != "null" ]; then
      add_failure "$rule_file" "値域-uncheckableReason" "checkable:true のとき uncheckableReason は null である必要がある"
    fi
  elif [ "$v_checkable" = "false" ]; then
    if [ -z "$v_uncheckable" ] || [ "$v_uncheckable" = "null" ]; then
      add_failure "$rule_file" "鍵-対応整合" "checkable:false だが uncheckableReason が null または未設定"
    fi
    if [ -n "$v_checker" ] && [ "$v_checker" != "null" ]; then
      add_failure "$rule_file" "値域-checker" "checkable:false のとき checker は null である必要がある"
    fi
  fi

  # 適用範囲-必須（globs）
  local globs_raw globs_rc
  globs_rc=0
  globs_raw="$(fm_get_array "$body" globs)" || globs_rc=$?
  if [ "$globs_rc" -eq 1 ]; then
    add_failure "$rule_file" "適用範囲-必須" "globs 鍵が存在しない"
  elif [ "$globs_rc" -eq 2 ]; then
    add_failure "$rule_file" "front-matter配列形式" "globs が複数行のブロック表記であり未対応（[\"a\", \"b\"] の1行表記のみ対応）"
  else
    local globs_count
    globs_count="$(printf '%s' "$globs_raw" | jq 'length' 2>/dev/null || echo -1)"
    if [ "$globs_count" -lt 0 ]; then
      add_failure "$rule_file" "front-matter配列形式" "globs の値がJSON配列として解釈できない（値: ${globs_raw}）"
      globs_count=0
    fi
    if [ "$v_scope" = "scoped" ] && [ "$globs_count" -eq 0 ]; then
      add_failure "$rule_file" "適用範囲-必須" "scope:scoped だが globs が空配列"
    fi
  fi

  # 階層-一致
  if [ "$v_parent" != "$parent_key_expected" ]; then
    add_failure "$rule_file" "階層-一致" "front matter の parent '${v_parent}' が親フォルダ名 '${parent_key_expected}' と不一致"
  fi
  if [ "$v_key" != "$child_key_expected" ]; then
    add_failure "$rule_file" "階層-一致" "front matter の key '${v_key}' が子フォルダ名 '${child_key_expected}' と不一致"
  fi

  # 矯正-矛盾なし の材料収集（none は対象外）
  if [ -n "$v_formatter" ] && [ "$v_formatter" != "none" ]; then
    FORMATTER_VALUES="${FORMATTER_VALUES}${rule_file}	${v_formatter}
"
  fi
}

# 親宣言-実在: 各親フォルダに parent.yml が実在し、key がフォルダ名と一致し、
# title が非空であることを検査する。ルート直下の各サブディレクトリを親フォルダとみなす。
validate_parent_declarations() {
  local root="$1"
  local parent_dirs
  parent_dirs="$(find "$root" -mindepth 1 -maxdepth 1 -type d | sort)"

  local pdir
  while IFS= read -r pdir; do
    [ -n "$pdir" ] || continue
    local parent_key_expected parent_yml
    parent_key_expected="$(basename "$pdir")"
    parent_yml="${pdir}/parent.yml"

    if [ ! -f "$parent_yml" ]; then
      add_failure "$parent_yml" "親宣言-実在" "親フォルダ '${parent_key_expected}' に parent.yml が実在しない"
      continue
    fi

    local pbody pkey ptitle
    pbody="$(cat "$parent_yml")"
    pkey="$(fm_get_scalar "$pbody" key)"
    ptitle="$(fm_get_scalar "$pbody" title)"

    if [ "$pkey" != "$parent_key_expected" ]; then
      add_failure "$parent_yml" "親宣言-実在" "parent.yml の key '${pkey}' が親フォルダ名 '${parent_key_expected}' と不一致"
    fi
    if ! is_nonempty "$ptitle"; then
      add_failure "$parent_yml" "親宣言-実在" "parent.yml の title が非空である必要がある"
    fi
  done <<EOF
$parent_dirs
EOF
}

# 矯正-矛盾なし: 全rule.md横断で、none以外のformatter値が複数種類あれば矛盾とする。
# 根拠: 設計7節「Prettier・Biome・.editorconfigのいずれも、1つのプロジェクトに
#   1つしか設定ファイルを置けない」。front matterにはformatterという1鍵しか
#   矯正設定を表す情報がないため、この鍵の値そのものを「同じ設定項目」として扱う。
check_formatter_conflict() {
  local distinct
  distinct="$(printf '%s' "$FORMATTER_VALUES" | awk -F'\t' 'NF{print $2}' | sort -u)"
  local distinct_count
  distinct_count="$(printf '%s' "$distinct" | grep -c . || true)"
  if [ "$distinct_count" -gt 1 ]; then
    local detail
    detail="$(printf '%s' "$FORMATTER_VALUES" | awk -F'\t' 'NF{printf "%s=%s ", $1, $2}')"
    add_failure "(横断検査)" "矯正-矛盾なし" "formatter指定が複数種類ある（1プロジェクトに1つしか設定ファイルを置けない）: ${detail}"
  fi
}

# 引数が docs/rules を指していないと疑われる場合（渡されたディレクトリの直下に
# parent.yml を持たないフォルダが1つでもある場合）に使い方を標準エラーへ出す。
# 誤検出で止めるのではなく、通常の検査はそのまま続ける（呼び出し元がexitしない）。
check_rules_root_hint() {
  local root="$1"
  local subdir suspect
  suspect=0
  for subdir in "$root"/*/; do
    [ -d "$subdir" ] || continue
    if [ ! -f "${subdir}parent.yml" ]; then
      suspect=1
      break
    fi
  done
  if [ "$suspect" -eq 1 ]; then
    echo "使い方: $(basename "$0") <docs/rules のルート>" >&2
    echo "渡されたディレクトリの直下に parent.yml を持たないフォルダがあります。" >&2
    echo "リポジトリルートではなく docs/rules を指してください。" >&2
  fi
}

run_validate() {
  local root="$1"
  FAILURES=""
  FAIL_COUNT=0
  FORMATTER_VALUES=""

  if [ ! -d "$root" ]; then
    echo "ERROR: ルートディレクトリが存在しません: $root" >&2
    return 1
  fi

  local rule_files
  rule_files="$(find "$root" -type f -name 'rule.md' | sort)"
  if [ -z "$rule_files" ]; then
    echo "ERROR: rule.md が1件も見つかりません: $root" >&2
    return 1
  fi

  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    validate_one_rule "$f"
  done <<EOF
$rule_files
EOF

  check_formatter_conflict
  validate_parent_declarations "$root"

  if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "検査不合格: ${FAIL_COUNT} 件" >&2
    printf '%s' "$FAILURES" >&2
    return 1
  fi

  echo "検査合格: $(printf '%s\n' "$rule_files" | grep -c .) 件の rule.md が全検査に合格"
  return 0
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

st_write_valid_pair() {
  # $1: ルートディレクトリ
  local root="$1"
  mkdir -p "${root}/agent-operations/ai-behavior"
  mkdir -p "${root}/code-standards/naming"

  cat > "${root}/agent-operations/parent.yml" <<'EOF'
key: agent-operations
title: AIエージェント運用
EOF

  cat > "${root}/code-standards/parent.yml" <<'EOF'
key: code-standards
title: コード規約
EOF

  cat > "${root}/agent-operations/ai-behavior/rule.md" <<'EOF'
---
key: ai-behavior
title: AIエージェント行動規約
parent: agent-operations
summary: AIエージェントへの作業委任の取り決め。
scope: always
globs: ["**/*"]
enforcement: advisory
checkable: false
checker: null
uncheckableReason: 行動の是非は静的解析では判定できない。
formatter: none
status: approved
origin: proposal
---

# AIエージェント行動規約

## 概要

テスト用の概要。

## 規則

| 規則 | 内容 | 根拠 |
|---|---|---|
| 例 | 例 | 例 |

## 違反時の手順

1. 例
EOF

  cat > "${root}/code-standards/naming/rule.md" <<'EOF'
---
key: naming
title: 命名規約
parent: code-standards
summary: 変数・クラスの命名パターン。
scope: scoped
globs: ["src/**/*.ts"]
enforcement: advisory
checkable: true
checker: check-naming.sh
uncheckableReason: null
formatter: none
status: approved
origin: proposal
---

# 命名規約

## 概要

テスト用の概要。

## 規則

| 規則 | 内容 | 根拠 |
|---|---|---|
| 例 | 例 | 例 |

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
}

st_case() {
  # $1: ケース名  $2: 期待exitコード  $3: 期待する検査キー(grep用。空なら未チェック)
  local name="$1" expected_rc="$2" expect_key="$3"
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/validate-rule-definitions-self-test.XXXXXX")"
  st_write_valid_pair "$tmp"

  case "$name" in
    pass) : ;;
    key-consistency)
      sed -i.bak 's/^checker: check-naming.sh$/checker: null/' "${tmp}/code-standards/naming/rule.md"
      rm -f "${tmp}/code-standards/naming/rule.md.bak"
      ;;
    test-companion)
      rm -f "${tmp}/code-standards/naming/check-naming.test.sh"
      ;;
    scope-globs)
      sed -i.bak 's/^globs: \["src\/\*\*\/\*.ts"\]$/globs: []/' "${tmp}/code-standards/naming/rule.md"
      rm -f "${tmp}/code-standards/naming/rule.md.bak"
      ;;
    hierarchy)
      sed -i.bak 's/^parent: code-standards$/parent: wrong-parent/' "${tmp}/code-standards/naming/rule.md"
      rm -f "${tmp}/code-standards/naming/rule.md.bak"
      ;;
    formatter-conflict)
      sed -i.bak 's/^formatter: none$/formatter: prettier/' "${tmp}/agent-operations/ai-behavior/rule.md"
      rm -f "${tmp}/agent-operations/ai-behavior/rule.md.bak"
      sed -i.bak 's/^formatter: none$/formatter: biome/' "${tmp}/code-standards/naming/rule.md"
      rm -f "${tmp}/code-standards/naming/rule.md.bak"
      ;;
    status-domain)
      sed -i.bak 's/^status: approved$/status: pending/' "${tmp}/code-standards/naming/rule.md"
      rm -f "${tmp}/code-standards/naming/rule.md.bak"
      ;;
    parent-missing)
      rm -f "${tmp}/agent-operations/parent.yml"
      ;;
    parent-key-mismatch)
      sed -i.bak 's/^key: agent-operations$/key: wrong-key/' "${tmp}/agent-operations/parent.yml"
      rm -f "${tmp}/agent-operations/parent.yml.bak"
      ;;
  esac

  local out rc
  out="$(run_validate "$tmp" 2>&1)"
  rc=$?
  rm -rf "$tmp"

  if [ "$rc" -ne "$expected_rc" ]; then
    echo "  [FAIL] ${name}: 終了コードが不正 (実際=${rc}, 期待=${expected_rc})" >&2
    echo "$out" | sed 's/^/    /' >&2
    return 1
  fi
  if [ -n "$expect_key" ] && ! printf '%s' "$out" | grep -q "\[${expect_key}\]"; then
    echo "  [FAIL] ${name}: 期待した検査キー '[${expect_key}]' が出力に含まれない" >&2
    echo "$out" | sed 's/^/    /' >&2
    return 1
  fi
  echo "  [PASS] ${name}"
  return 0
}

self_test() {
  local rc=0
  st_case "pass" 0 "" || rc=1
  st_case "key-consistency" 1 "鍵-対応整合" || rc=1
  st_case "test-companion" 1 "検査-テスト同伴" || rc=1
  st_case "scope-globs" 1 "適用範囲-必須" || rc=1
  st_case "hierarchy" 1 "階層-一致" || rc=1
  st_case "formatter-conflict" 1 "矯正-矛盾なし" || rc=1
  st_case "status-domain" 1 "派生-未承認除外" || rc=1
  st_case "parent-missing" 1 "親宣言-実在" || rc=1
  st_case "parent-key-mismatch" 1 "親宣言-実在" || rc=1

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
  if [ "$#" -ne 1 ]; then
    echo "使い方: $(basename "$0") <docs/rules のルート>" >&2
    echo "        $(basename "$0") --self-test" >&2
    exit 1
  fi
  check_rules_root_hint "$1"
  run_validate "$1"
  exit $?
}

# 直接実行時のみdispatchする（build-derived-rules.shがsourceしてrun_validate等の
# 関数を再利用できるよう、source時は呼び出し元の位置引数を誤読しない）
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main "$@"
fi
