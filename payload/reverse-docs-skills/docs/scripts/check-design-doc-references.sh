#!/usr/bin/env bash
# check-design-doc-references.sh — docs/design/ 配下の設計文書が指す参照のうち、
# 実在しない場所を指すものを機械的に検出する。
#
# 背景: docs/design/AI駆動開発セットアップ構想.md の2箇所が、置き場の移動に
# 追従できず実在しないパスを指したまま長期間残っていた（2026-08-26実測）。
# 既存の check-payload-references.sh は納品対象（.claude/skills・delivery-payload・
# generation-engine 等）だけを走査対象にしており docs/design/ を含まない。同種の
# 参照切れを繰り返し見つける検査が docs/design/ 配下には1本も無かった。
#
# 抽出方法:
#   docs/design/ 配下の *.md から、逆引用符（`）で囲まれた文字列のうち
#   スラッシュを1つ以上含むものを「パス付きの参照」として抽出する。
#
# 判定方法:
#   抽出した各参照について、(a) リポジトリのルートからの相対、および
#   (b) 参照元の文書があるディレクトリからの相対、の両方で実在を確かめる。
#   どちらでも見つからないものを不在として報告する。
#
# 除外（本検査が対象から外すもの）:
#   1. 先頭が `../` で始まる参照。文脈上の基点が文書ごとに異なり、
#      機械的に確定できないため対象外とする。
#   2. スラッシュを含まない参照（ファイル名だけの言及）。実在するファイルを
#      名前で指しているだけであり、参照切れではないため対象外とする。
#   3. 空白・シェルのメタ文字（$ < > * ( ) { } ' " | ; & \）を含む文字列。
#      これらはコマンド断片・環境変数・グロブ・プレースホルダであり、
#      「パス付きの参照」ではなく実在確認の対象にならないため対象外とする。
#   4. 先頭が `/` で始まる参照（絶対パス）。/tmp・/dev 等のOS一般のパスを
#      指す記述であり、リポジトリ相対の参照ではないため対象外とする。
#   5. 末尾の1個のスラッシュを除いた残りにスラッシュを含まない参照
#      （例: `shared/`・`project-setup/`）。単一階層のディレクトリ名だけの
#      言及であり、対象リポジトリの実在パスを名指す参照とは性質が異なる
#      ため対象外とする。
#   6. 最初の1階層がこのリポジトリのルート直下の実在物（delivery-payload・
#      generation-engine・docs・.claude・.codex・.cursor・AGENTS.md・CLAUDE.md・
#      README.md・RUNBOOK.md・package.json・package-lock.json・.gitignore・.git）
#      のいずれとも一致しない参照。generation-engine/scripts/ 配下の群を
#      相互に参照する際の省略記法（例: `extract/foo.sh` が
#      `generation-engine/scripts/extract/foo.sh` を指す）や、外部リポジトリ
#      （`DevsProtein/agents-sync` 等）のパスを、リポジトリ相対パスと誤認
#      しないための絞り込みである。
#   7. docs/references/design-doc-reference-exclusions.json に登録された参照
#      （納品先の出力配置を説明する記述・履歴の書き換えで実在確認の手段が
#      失われた過去のファイルへの言及・改称記録の中で意図的に残した旧名・
#      検証時点の一時的な記述等）。この一覧は実測時点で固定し、以後は手で
#      追記する。ここに無い新しい参照切れはそのまま不合格として検出される。
#
# 使い方:
#   check-design-doc-references.sh [<repo_root>]   既定は自身の位置から解決したリポジトリルート
#   check-design-doc-references.sh --self-test      自己テスト
#
# 終了コード: 0=参照切れなし。1=参照切れあり。2=判定不能（mktemp失敗等）。
#
# 設計判断: .claude/rules/scoped/portal/page-conventions/rule.md の
#   「設計判断」節「check-design-doc-references.sh」を参照。
set -uo pipefail

# 公開対象から外すスキルの名前。payload の安全検査が名前の出現で判定するため、
# 検出側のこの定義は連結で持つ（check-secret-*.sh を対象外とする先例と同じ理由）。
PRIVATE_SKILL_NAME='prioritizing-improvement-tasks'
PRIVATE_SKILL_NAME="${PRIVATE_SKILL_NAME}-from-images"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DEFAULT_REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EXCLUSIONS_REL="docs/references/design-doc-reference-exclusions.json"

BAD_CHARS=(' ' $'\t' '$' '<' '>' '*' '(' ')' '{' '}' "'" '"' '|' ';' '&' '\\')
ROOT_ALLOW=(
  "delivery-payload" "generation-engine" "docs" ".claude" ".codex" ".cursor"
  "AGENTS.md" "CLAUDE.md" "README.md" "RUNBOOK.md"
  "package.json" "package-lock.json" ".gitignore" ".git"
)

has_bad_char() {
  local s="$1" c
  for c in "${BAD_CHARS[@]}"; do
    case "$s" in
      *"$c"*) return 0 ;;
    esac
  done
  return 1
}

in_root_allow() {
  local first="$1" a
  for a in "${ROOT_ALLOW[@]}"; do
    [ "$first" = "$a" ] && return 0
  done
  return 1
}

# _normalize: 末尾の1個のスラッシュだけを取り除く。
_normalize() {
  local s="$1"
  case "$s" in
    */) printf '%s' "${s%/}" ;;
    *) printf '%s' "$s" ;;
  esac
}

# load_exclusions: 除外一覧のJSONから reference 値だけを1行1件で書き出す。
# ファイルが無ければ空のまま（除外0件として動く）。
load_exclusions() {
  local repo_root="$1" out="$2" json="$repo_root/$EXCLUSIONS_REL"
  : > "$out"
  if [ -f "$json" ]; then
    if command -v jq >/dev/null 2>&1; then
      jq -r '.excludedReferences[]?.reference // empty' "$json" >> "$out" 2>/dev/null || true
    fi
  fi
}

is_excluded() {
  local norm="$1" excl_file="$2"
  grep -qxF "$norm" "$excl_file" 2>/dev/null
}

# run_check: repo_root配下 docs/design/ の全 .md を走査し、不在の参照を報告する。
run_check() {
  local repo_root="$1"
  local design_dir="$repo_root/docs/design"
  if [ ! -d "$design_dir" ]; then
    echo "[PASS] 対象なし: docs/design/ がありません"
    return 0
  fi

  local work
  if ! work="$(mktemp -d "${TMPDIR:-/tmp}/check-design-doc-references.XXXXXX" 2>/dev/null)" || [ -z "$work" ]; then
    echo "[UNKNOWN] 一時ディレクトリを作れないため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    return 2
  fi
  trap 'rm -rf "$work"' RETURN

  local excl_file="$work/exclusions.txt"
  load_exclusions "$repo_root" "$excl_file"

  local missing_file="$work/missing.txt"
  local total_file="$work/total.count"
  local excluded_file="$work/excluded.count"
  # 配布先（このリポジトリ自身の規約 .claude/rules/always/publish/complete/rule.md を持たない置き場）では、
  # 配布対象外の資産（このリポジトリ自身の規約・エディタ設定・作業の記録・手順書）への参照は
  # 実在しないのが正しい。配布先ではこれらを除外として数える（2026-08-28 実測: 28件）。
  # 公開対象から外す資産（公開完遂規約の一覧）に載るスキル（PRIVATE_SKILL_NAME）
  # への参照も同様に、配布先では実在しないのが正しい（2026-08-31 実測: 5件）。
  local is_payload=0
  [ -f "$repo_root/.claude/rules/always/publish/complete/rule.md" ] || is_payload=1
  : > "$missing_file"
  printf '0\n' > "$total_file"
  printf '0\n' > "$excluded_file"

  local file
  while IFS= read -r file; do
    local doc_dir
    doc_dir="$(dirname "$file")"
    local cand
    while IFS= read -r cand; do
      [ -n "$cand" ] || continue
      case "$cand" in
        */*) : ;;
        *) continue ;;
      esac
      if has_bad_char "$cand"; then
        continue
      fi
      case "$cand" in
        ../*) continue ;;
        /*) continue ;;
      esac
      local stripped
      stripped="$(_normalize "$cand")"
      case "$stripped" in
        */*) : ;;
        *) continue ;;
      esac
      local first="${cand%%/*}"
      if ! in_root_allow "$first"; then
        continue
      fi
      local norm
      norm="$(_normalize "$cand")"
      if [ "$is_payload" -eq 1 ]; then
        case "$norm" in
          .claude/rules/*|.claude/rules|.codex/*|.codex|.cursor/*|.cursor|docs/session-prompts/*|docs/session-prompts|docs/tasks/work-records/*|docs/tasks/work-records|".claude/skills/${PRIVATE_SKILL_NAME}"/*|".claude/skills/${PRIVATE_SKILL_NAME}")
            local ecp
            ecp="$(cat "$excluded_file")"
            echo $((ecp + 1)) > "$excluded_file"
            continue
            ;;
        esac
      fi
      if is_excluded "$norm" "$excl_file"; then
        local ec
        ec="$(cat "$excluded_file")"
        echo $((ec + 1)) > "$excluded_file"
        continue
      fi
      local tc
      tc="$(cat "$total_file")"
      echo $((tc + 1)) > "$total_file"
      if [ -e "$repo_root/$cand" ] || [ -e "$doc_dir/$cand" ]; then
        continue
      fi
      printf '%s\t%s\n' "$file" "$cand" >> "$missing_file"
    done < <(grep -oE '`[^`]*`' "$file" 2>/dev/null | sed -e 's/^`//' -e 's/`$//')
  done < <(find "$design_dir" -type f -name '*.md' | sort)

  local total excluded missing_count
  total="$(cat "$total_file")"
  excluded="$(cat "$excluded_file")"
  missing_count="$(wc -l < "$missing_file" | tr -d ' ')"

  if [ "$missing_count" -gt 0 ]; then
    echo "[FAIL] 対象 ${total} 件（除外 ${excluded} 件）のうち ${missing_count} 件が実在しません:" >&2
    while IFS=$'\t' read -r f c; do
      echo "  ${f} -> ${c}" >&2
    done < "$missing_file"
    return 1
  fi

  echo "[PASS] 対象 ${total} 件（除外 ${excluded} 件）すべてが実在する参照です"
  return 0
}

run_self_test() {
  local total=0 fail=0

  local work
  if ! work="$(mktemp -d "${TMPDIR:-/tmp}/check-design-doc-references-selftest.XXXXXX" 2>/dev/null)" || [ -z "$work" ]; then
    echo "[UNKNOWN] 一時ディレクトリを作れないため自己テストを判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    return 2
  fi
  trap 'rm -rf "$work"' RETURN

  # ケース1: 実在する参照だけの文書は合格する
  total=$((total + 1))
  local proj1="$work/case1"
  mkdir -p "$proj1/docs/design" "$proj1/docs/foo"
  : > "$proj1/docs/foo/bar.md"
  cat > "$proj1/docs/design/x.md" <<'EOF'
参照: `docs/foo/bar.md` を見よ。
EOF
  if run_check "$proj1" >/dev/null 2>&1; then
    echo "  [PASS] ケース1: 実在する参照だけの文書は合格する"
  else
    echo "  [FAIL] ケース1: 実在する参照だけの文書が不合格になった" >&2
    fail=$((fail + 1))
  fi

  # ケース2: 実在しない参照を含む文書は不合格になる
  total=$((total + 1))
  local proj2="$work/case2"
  mkdir -p "$proj2/docs/design"
  cat > "$proj2/docs/design/x.md" <<'EOF'
参照: `docs/no-such-file.md` を見よ。
EOF
  local rc2=0
  run_check "$proj2" >/dev/null 2>&1
  rc2=$?
  if [ "$rc2" -eq 1 ]; then
    echo "  [PASS] ケース2: 実在しない参照を含む文書は不合格(rc=1)になる"
  else
    echo "  [FAIL] ケース2: 実在しない参照を含む文書の終了コードが1でない(rc=${rc2})" >&2
    fail=$((fail + 1))
  fi

  # ケース3: 先頭が ../ の参照は対象外（実在しなくても合格する）
  total=$((total + 1))
  local proj3="$work/case3"
  mkdir -p "$proj3/docs/design"
  cat > "$proj3/docs/design/x.md" <<'EOF'
参照: `../no-such-sibling.sh` を見よ。
EOF
  if run_check "$proj3" >/dev/null 2>&1; then
    echo "  [PASS] ケース3: 先頭が../の参照は対象外として合格する"
  else
    echo "  [FAIL] ケース3: 先頭が../の参照が誤って不合格にされた" >&2
    fail=$((fail + 1))
  fi

  # ケース4: スラッシュを含まない参照（ファイル名だけ）は対象外
  total=$((total + 1))
  local proj4="$work/case4"
  mkdir -p "$proj4/docs/design"
  cat > "$proj4/docs/design/x.md" <<'EOF'
参照: `no-such-file.md` を見よ。
EOF
  if run_check "$proj4" >/dev/null 2>&1; then
    echo "  [PASS] ケース4: スラッシュを含まない参照は対象外として合格する"
  else
    echo "  [FAIL] ケース4: スラッシュを含まない参照が誤って不合格にされた" >&2
    fail=$((fail + 1))
  fi

  # ケース5: 参照元の文書があるディレクトリからの相対でも見つかれば合格する
  total=$((total + 1))
  local proj5="$work/case5"
  mkdir -p "$proj5/docs/design/generation-engine/foo"
  : > "$proj5/docs/design/generation-engine/foo/sibling.md"
  cat > "$proj5/docs/design/generation-engine/foo/x.md" <<'EOF'
参照: `docs/design/generation-engine/foo/sibling.md` を見よ。
EOF
  if run_check "$proj5" >/dev/null 2>&1; then
    echo "  [PASS] ケース5: 文書ディレクトリからの相対で見つかれば合格する"
  else
    echo "  [FAIL] ケース5: 文書ディレクトリからの相対解決が機能しなかった" >&2
    fail=$((fail + 1))
  fi

  # ケース6: 除外一覧に載る参照は実在しなくても合格する
  total=$((total + 1))
  local proj6="$work/case6"
  mkdir -p "$proj6/docs/design" "$proj6/docs/references"
  cat > "$proj6/docs/design/x.md" <<'EOF'
参照: `docs/example-excluded-path.md` を見よ。
EOF
  cat > "$proj6/docs/references/design-doc-reference-exclusions.json" <<'EOF'
{"excludedReferences": [{"reference": "docs/example-excluded-path.md", "reason": "自己テスト用のダミー除外"}]}
EOF
  if run_check "$proj6" >/dev/null 2>&1; then
    echo "  [PASS] ケース6: 除外一覧に載る参照は実在しなくても合格する"
  else
    echo "  [FAIL] ケース6: 除外一覧が機能せず不合格になった" >&2
    fail=$((fail + 1))
  fi

  # ケース7: 先頭がルート直下許可リストに無い参照（群の省略記法）は対象外
  total=$((total + 1))
  local proj7="$work/case7"
  mkdir -p "$proj7/docs/design"
  cat > "$proj7/docs/design/x.md" <<'EOF'
参照: `extract/no-such-script.sh` を見よ。
EOF
  if run_check "$proj7" >/dev/null 2>&1; then
    echo "  [PASS] ケース7: ルート直下許可リストに無い先頭要素の参照は対象外として合格する"
  else
    echo "  [FAIL] ケース7: 群の省略記法が誤って不合格にされた" >&2
    fail=$((fail + 1))
  fi

  # ケース8: 単一階層のディレクトリ名だけの言及（末尾スラッシュのみ）は対象外
  total=$((total + 1))
  local proj8="$work/case8"
  mkdir -p "$proj8/docs/design"
  cat > "$proj8/docs/design/x.md" <<'EOF'
提案: `no-such-dir/` という置き場を新設する案がある。
EOF
  if run_check "$proj8" >/dev/null 2>&1; then
    echo "  [PASS] ケース8: 単一階層のディレクトリ名だけの言及は対象外として合格する"
  else
    echo "  [FAIL] ケース8: 単一階層のディレクトリ名の言及が誤って不合格にされた" >&2
    fail=$((fail + 1))
  fi

  # ケース9: docs/design/ が無いプロジェクトは対象なしとして合格
  total=$((total + 1))
  local proj9="$work/case9"
  mkdir -p "$proj9"
  local rc9=0
  run_check "$proj9" >/dev/null 2>&1
  rc9=$?
  if [ "$rc9" -eq 0 ]; then
    echo "  [PASS] ケース9: docs/design/ が無いと対象なしとして合格する"
  else
    echo "  [FAIL] ケース9: docs/design/ が無いときの終了コードが0でない(rc=${rc9})" >&2
    fail=$((fail + 1))
  fi

  # ケース10: 空白・シェルのメタ文字を含む文字列は対象外
  total=$((total + 1))
  local proj10="$work/case10"
  mkdir -p "$proj10/docs/design"
  cat > "$proj10/docs/design/x.md" <<'EOF'
式: `${TMPDIR:-/tmp}/no-such` を使う。
EOF
  if run_check "$proj10" >/dev/null 2>&1; then
    echo "  [PASS] ケース10: シェルのメタ文字を含む文字列は対象外として合格する"
  else
    echo "  [FAIL] ケース10: メタ文字を含む文字列が誤って不合格にされた" >&2
    fail=$((fail + 1))
  fi

  # ケース11: 配布先（公開完遂規約ファイルを持たない置き場）では、公開対象から
  # 外す資産のスキル（PRIVATE_SKILL_NAME）への参照は
  # 実在しなくても合格する
  total=$((total + 1))
  local proj11="$work/case11"
  mkdir -p "$proj11/docs/design"
  printf '参照: `%s` を見よ。\n' ".claude/skills/${PRIVATE_SKILL_NAME}/SKILL.md" > "$proj11/docs/design/x.md"
  if run_check "$proj11" >/dev/null 2>&1; then
    echo "  [PASS] ケース11: 配布先では公開対象外スキルへの参照は対象外として合格する"
  else
    echo "  [FAIL] ケース11: 配布先での公開対象外スキル除外が機能せず不合格になった" >&2
    fail=$((fail + 1))
  fi

  echo "実行 ${total} 件 / 成功 $((total - fail)) 件 / 失敗 ${fail} 件"
  [ "$fail" -eq 0 ]
}

main() {
  case "${1:-}" in
    --self-test)
      run_self_test
      exit $?
      ;;
    "")
      run_check "$DEFAULT_REPO_ROOT"
      exit $?
      ;;
    *)
      run_check "$1"
      exit $?
      ;;
  esac
}

main "$@"
