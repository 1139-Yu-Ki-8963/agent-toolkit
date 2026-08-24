#!/usr/bin/env bash
# check-direct-commit-to-integration-branch.sh — 実装から統合までの順序の決まりの linter
#
# timing: PreToolUse(Bash)
# 対象規約: 実装から統合までの順序の決まり（検査列に「静的解析:」を含む2件すべてを検査する）
#
# 対象の規則:
#   1. 実装は作業用の枝で行う
#      — 実行しようとしている git commit の時点の現在の枝が統合先の枝
#        （main / master / develop / trunk）であれば違反として block する
#        （既存の検査）
#   2. 統合の前に検査を通す
#      — 実行しようとしているコマンドが統合に関わる操作（git commit / git push）
#        であれば、統合の前に走る検査（テストと静的解析）の登録が
#        cwd 配下（GitHub Actions のワークフロー・package.json の scripts・
#        Makefile のターゲット）に見当たるかを走査する
#
# 入力（hooks標準形。stdin JSON）:
#   .tool_name            "Bash" のときのみ判定対象
#   .tool_input.command    実行しようとしているコマンド文字列
#   .cwd                   コマンドを実行する作業ディレクトリ（絶対パス）
#
# 判定の設計:
#   統合先の枝への直接コミットの検出は、git の履歴ではなく「これからコミットしようと
#   している時点の現在の枝」を PreToolUse で先読みする方式を取る。git 履歴の事後走査
#   では、コミット済みの直接コミットしか検出できず、規則が求める「作業用の枝で行う」
#   という予防（block）の趣旨に合わない。
#
#   「統合の前に検査を通す」は検査列の前半（静的解析: 検査の登録の走査）だけを
#   実装する。このスクリプトは PreToolUse(Bash) のフックであり、検査列の後半
#   （テスト: 検査を実際に実行し通過を確かめる）は実装しない。フックの中で
#   テストを実際に走らせると、書き込みのたびに時間がかかるためである。
#   登録が見当たらない場合も block はしない（戻り値0）。検査の整備は進行途中の
#   プロジェクトでも自然に満たされうるものであり、通知にとどめる。
#
# 除外条件（誤検知回避）:
#   - tool_name が Bash 以外 → 対象外
#   - コマンドに git commit を含まない → 対象外（規則1）
#   - コマンドに git と commit・push のいずれも含まない → 対象外（規則2）
#   - cwd が空・ディレクトリでない → fail-open（判定不能を block しない）
#   - cwd が git リポジトリでない、または現在の枝を取得できない → fail-open（規則1）
#   - 現在の枝が main / master / develop / trunk 以外 → 許可（規則1）
#
# 既知の限界:
#   - 統合先の枝の名前は代表的な慣行（main/master/develop/trunk）に限定した固定リスト
#     であり、これ以外の名前を統合先に使うリポジトリでは検出できない
#   - git alias 経由のコミット（例: git ci）は検知できない
#   - 「統合の前に検査を通す」は検査の登録（静的解析）だけを見る。登録された
#     検査が実際に通過するかどうか（テストの実行結果）は確かめない
#
# 止めるか知らせるか:
#   実装は作業用の枝で行う: 止める（統合先の枝への直接コミットはそのまま push されると、履歴に取り消せない形で残るため）
#   統合の前に検査を通す: 知らせる（検査の登録は整備が進めば自然に満たされるものであり、テスト・静的解析の追加を促すだけで足りるため）
#
# 逃げ道:
#   DIRECT_COMMIT_TO_INTEGRATION_BRANCH_SKIP_REASON に理由を書けば通る。理由が空の場合は通らない
#
# 使い方:
#   フック本体として: PreToolUse(Bash) の入力 JSON を stdin から受け取る
#   単体実行: check-direct-commit-to-integration-branch.sh --self-test
set -uo pipefail

# 「統合の前に検査を通す」規則の判定
judge_pre_merge_checks() {
  # $1: cwd, $2: cmd
  local cwd="$1" cmd="$2"

  if ! printf '%s' "$cmd" | grep -qF 'git' || ! printf '%s' "$cmd" | grep -qE '(commit|push)'; then
    echo "対象外[統合の前に検査を通す]: 統合に関わるコマンドではありません"
    return 0
  fi

  if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
    echo "対象外[統合の前に検査を通す]: 作業ディレクトリが分からないため判定していません"
    return 0
  fi

  local wf_dir="$cwd/.github/workflows"
  if [ -d "$wf_dir" ]; then
    local wf
    while IFS= read -r wf; do
      [ -z "$wf" ] && continue
      if grep -qF 'test' "$wf" 2>/dev/null && grep -qE '(lint|typecheck)' "$wf" 2>/dev/null; then
        echo "許可[統合の前に検査を通す]: 統合の前に走る検査にテストと静的解析が登録されています（${wf#"$cwd"/}）"
        return 0
      fi
    done < <(find "$wf_dir" \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null)
  fi

  local pkg="$cwd/package.json"
  if [ -f "$pkg" ] && command -v jq >/dev/null 2>&1; then
    local has_test has_lint has_typecheck
    has_test=$(jq -r '.scripts.test // empty' "$pkg" 2>/dev/null)
    has_lint=$(jq -r '.scripts.lint // empty' "$pkg" 2>/dev/null)
    has_typecheck=$(jq -r '.scripts.typecheck // empty' "$pkg" 2>/dev/null)
    if [ -n "$has_test" ] && { [ -n "$has_lint" ] || [ -n "$has_typecheck" ]; }; then
      echo "許可[統合の前に検査を通す]: 統合の前に走る検査にテストと静的解析が登録されています（package.json の scripts）"
      return 0
    fi
  fi

  local mk="$cwd/Makefile"
  if [ -f "$mk" ]; then
    if grep -qE '^test:' "$mk" 2>/dev/null && grep -qE '^(lint|typecheck):' "$mk" 2>/dev/null; then
      echo "許可[統合の前に検査を通す]: 統合の前に走る検査にテストと静的解析が登録されています（Makefile）"
      return 0
    fi
  fi

  echo "通知[統合の前に検査を通す]: 統合の前に走る検査の登録が見当たりません。テストと静的解析を登録してください"
  return 0
}

judge() {
  # $1: cwd, $2: command
  # 標準出力: 判定理由（複数行になりうる）。戻り値: 0=許可・2=拒否
  local cwd="$1" cmd="$2"

  # 規則: 統合の前に検査を通す（戻り値は常に0。止めない）
  local pre_msg
  pre_msg="$(judge_pre_merge_checks "$cwd" "$cmd")"
  echo "$pre_msg"

  # 規則: 実装は作業用の枝で行う
  if ! printf '%s' "$cmd" | grep -qE '(^|[^a-zA-Z])git[[:space:]]+commit([^a-zA-Z]|$)'; then
    echo "対象外[実装は作業用の枝で行う]: git commit を含まないコマンドです"
    return 0
  fi

  if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
    echo "対象外[実装は作業用の枝で行う]: 作業ディレクトリを参照できないため判定不能（fail-open）"
    return 0
  fi

  local branch
  branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
    echo "対象外[実装は作業用の枝で行う]: 現在の枝を判定できないため判定不能（fail-open）"
    return 0
  fi

  case "$branch" in
    main|master|develop|trunk)
      echo "拒否[実装は作業用の枝で行う]: 統合先の枝（${branch}）へ直接コミットしようとしています"
      return 2
      ;;
    *)
      echo "許可[実装は作業用の枝で行う]: 作業用の枝（${branch}）でのコミットです"
      return 0
      ;;
  esac
}

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${DIRECT_COMMIT_TO_INTEGRATION_BRANCH_SKIP_REASON:-}" ]; then
    echo "[DIRECT-COMMIT-TO-INTEGRATION-BRANCH-SKIP] 理由: ${DIRECT_COMMIT_TO_INTEGRATION_BRANCH_SKIP_REASON}"
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

  local tool
  tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
  [ "$tool" != "Bash" ] && exit 0

  local cmd cwd msg code
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
  [ -z "$cmd" ] && exit 0
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
  # 入力に作業ディレクトリが無ければ、この検査を動かしている側の作業
  # ディレクトリを使う。フックの入力には通常 .cwd が入るが、入らない
  # 呼び出し方をされたときに枝の判定ごと落ちて素通りするのを防ぐ
  # （実測 2026-08-24: .cwd を渡さずに試すと、統合先の枝の上でも通った）。
  [ -z "$cwd" ] && cwd="$PWD"

  if msg="$(judge "$cwd" "$cmd")"; then code=0; else code=$?; fi

  [ "$code" -eq 0 ] && exit 0

  ctx="[DIRECT-COMMIT-TO-INTEGRATION-BRANCH-BLOCK] ${msg}。作業用の枝を切ってから変更をコミットしてください。"
  jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  printf '%s\n' "$ctx" >&2
  exit 2
}

self_test() {
  local rc=0 msg code tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-direct-commit-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  # repo1: main 枝 → 直接コミットは拒否
  local repo_main="$tmp/repo-main"
  mkdir -p "$repo_main"
  git -C "$repo_main" init -q >/dev/null 2>&1
  git -C "$repo_main" checkout -q -b main >/dev/null 2>&1
  git -C "$repo_main" -c user.email=t@example.com -c user.name=t commit --allow-empty -q -m init >/dev/null 2>&1

  if msg="$(judge "$repo_main" "git commit -m 'x'")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系1: main枝への直接コミットは拒否される（${msg}）"
  else
    echo "  [FAIL] 系1: main枝なのに拒否されなかった（exit=${code}）" >&2
    rc=1
  fi

  # repo2: master 枝 → 直接コミットは拒否
  local repo_master="$tmp/repo-master"
  mkdir -p "$repo_master"
  git -C "$repo_master" init -q >/dev/null 2>&1
  git -C "$repo_master" checkout -q -b master >/dev/null 2>&1
  git -C "$repo_master" -c user.email=t@example.com -c user.name=t commit --allow-empty -q -m init >/dev/null 2>&1

  if msg="$(judge "$repo_master" "git commit --amend")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系2: master枝への直接コミットは拒否される（${msg}）"
  else
    echo "  [FAIL] 系2: master枝なのに拒否されなかった（exit=${code}）" >&2
    rc=1
  fi

  # repo2b: develop 枝 → 直接コミットは拒否
  local repo_develop="$tmp/repo-develop"
  mkdir -p "$repo_develop"
  git -C "$repo_develop" init -q >/dev/null 2>&1
  git -C "$repo_develop" checkout -q -b develop >/dev/null 2>&1
  git -C "$repo_develop" -c user.email=t@example.com -c user.name=t commit --allow-empty -q -m init >/dev/null 2>&1

  if msg="$(judge "$repo_develop" "git commit -m 'x'")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系2b: develop枝への直接コミットは拒否される（${msg}）"
  else
    echo "  [FAIL] 系2b: develop枝なのに拒否されなかった（exit=${code}）" >&2
    rc=1
  fi

  # repo2c: trunk 枝 → 直接コミットは拒否
  local repo_trunk="$tmp/repo-trunk"
  mkdir -p "$repo_trunk"
  git -C "$repo_trunk" init -q >/dev/null 2>&1
  git -C "$repo_trunk" checkout -q -b trunk >/dev/null 2>&1
  git -C "$repo_trunk" -c user.email=t@example.com -c user.name=t commit --allow-empty -q -m init >/dev/null 2>&1

  if msg="$(judge "$repo_trunk" "git commit --amend")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系2c: trunk枝への直接コミットは拒否される（${msg}）"
  else
    echo "  [FAIL] 系2c: trunk枝なのに拒否されなかった（exit=${code}）" >&2
    rc=1
  fi

  # repo3: 作業用の枝 → 許可
  local repo_feat="$tmp/repo-feature"
  mkdir -p "$repo_feat"
  git -C "$repo_feat" init -q >/dev/null 2>&1
  git -C "$repo_feat" checkout -q -b main >/dev/null 2>&1
  git -C "$repo_feat" -c user.email=t@example.com -c user.name=t commit --allow-empty -q -m init >/dev/null 2>&1
  git -C "$repo_feat" checkout -q -b feature/add-something >/dev/null 2>&1

  if msg="$(judge "$repo_feat" "git commit -m 'y'")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系3: 作業用の枝でのコミットは許可される（${msg}）"
  else
    echo "  [FAIL] 系3: 作業用の枝なのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # repo4: git commit を含まないコマンド → 対象外として許可
  if msg="$(judge "$repo_main" "git status")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系4: git commit を含まないコマンドは対象外（${msg}）"
  else
    echo "  [FAIL] 系4: 対象外のはずが拒否された（exit=${code}）" >&2
    rc=1
  fi

  # repo5: git リポジトリでない → fail-open で許可
  local notgit="$tmp/not-a-repo"
  mkdir -p "$notgit"
  if msg="$(judge "$notgit" "git commit -m z")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系5: gitリポジトリでない場合はfail-openで許可される（${msg}）"
  else
    echo "  [FAIL] 系5: fail-openのはずが拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系6: git と commit/push のどちらも含まないコマンド → 「統合の前に検査を通す」は対象外
  if msg="$(judge_pre_merge_checks "$repo_feat" "ls -la")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '対象外[統合の前に検査を通す]'; then
    echo "  [PASS] 系6: 統合に関わらないコマンドは「統合の前に検査を通す」の対象外になる（${msg}）"
  else
    echo "  [FAIL] 系6: 対象外にならなかった、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系7: cwd が空 → 「統合の前に検査を通す」は対象外
  if msg="$(judge_pre_merge_checks "" "git commit -m x")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '対象外[統合の前に検査を通す]'; then
    echo "  [PASS] 系7: 作業ディレクトリが分からなければ「統合の前に検査を通す」の対象外になる（${msg}）"
  else
    echo "  [FAIL] 系7: 対象外にならなかった、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系8: 統合に関わるコマンドだが検査の登録が見当たらない → 通知
  local repo_noreg="$tmp/repo-noreg"
  mkdir -p "$repo_noreg"
  if msg="$(judge_pre_merge_checks "$repo_noreg" "git commit -m x")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '通知[統合の前に検査を通す]'; then
    echo "  [PASS] 系8: 検査の登録が見当たらなければ「統合の前に検査を通す」は通知になる（${msg}）"
  else
    echo "  [FAIL] 系8: 通知にならなかった、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系9: package.json の scripts に test と lint が登録されている → 許可
  local repo_reg="$tmp/repo-reg"
  mkdir -p "$repo_reg"
  cat > "$repo_reg/package.json" <<'EOF'
{"scripts": {"test": "vitest", "lint": "eslint ."}}
EOF
  if msg="$(judge_pre_merge_checks "$repo_reg" "git push")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '許可[統合の前に検査を通す]'; then
    echo "  [PASS] 系9: テストと静的解析が登録されていれば「統合の前に検査を通す」は許可される（${msg}）"
  else
    echo "  [FAIL] 系9: 許可にならなかった、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系10: 環境変数に理由を設定すると should_skip_with_reason は skip する
  local skip_out skip_code
  if skip_out="$(DIRECT_COMMIT_TO_INTEGRATION_BRANCH_SKIP_REASON="テスト理由" should_skip_with_reason)"; then skip_code=0; else skip_code=$?; fi
  if [ "$skip_code" -eq 0 ] && printf '%s' "$skip_out" | grep -qF 'DIRECT-COMMIT-TO-INTEGRATION-BRANCH-SKIP' && printf '%s' "$skip_out" | grep -qF 'テスト理由'; then
    echo "  [PASS] 系10: 理由を設定すると should_skip_with_reason は skip する（${skip_out}）"
  else
    echo "  [FAIL] 系10: 理由があるのに skip しない、またはタグ・理由が含まれない（exit=${skip_code}, ${skip_out}）" >&2
    rc=1
  fi

  # 系11: 環境変数を空文字にすると should_skip_with_reason は skip しない
  local skip_code2
  if DIRECT_COMMIT_TO_INTEGRATION_BRANCH_SKIP_REASON="" should_skip_with_reason >/dev/null 2>&1; then skip_code2=0; else skip_code2=$?; fi
  if [ "$skip_code2" -eq 1 ]; then
    echo "  [PASS] 系11: 環境変数が空文字なら should_skip_with_reason は skip しない"
  else
    echo "  [FAIL] 系11: 空文字なのに skip した（exit=${skip_code2}）" >&2
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
