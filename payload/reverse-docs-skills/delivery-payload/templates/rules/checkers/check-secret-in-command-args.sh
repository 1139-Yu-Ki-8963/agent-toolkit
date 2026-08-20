#!/usr/bin/env bash
# check-secret-in-command-args.sh — 使うツールとコマンドの決まりのうち静的解析を含む4規則の linter
#
# timing: PreToolUse(Bash)
# 対象規約: 使うツールとコマンドの決まり
#   - 秘密の値をコマンドの引数に置かない（すべての Bash コマンド）
#   - 使うツールを宣言で定める（git commit 時）
#   - 版を固定する（git commit 時）
#   - コマンドは宣言した入口から呼ぶ（git commit 時）
#
# 判定:
#   実行しようとしている Bash コマンドの引数に、認証の鍵・合言葉らしき語へ
#   環境変数参照ではない値が直接続いていれば違反として block（既存の判定。
#   変更なし。すべての Bash コマンドが対象）。
#   git commit のときは、cwd を対象に依存宣言・版固定・宣言済み入口の3規則を
#   追加で走査する。この3規則は知らせるだけで、足りない点があっても
#   block はしない（exit 0 のまま）。
#
# 入力（hooks標準形。stdin JSON）:
#   .tool_name            "Bash" のときのみ判定対象
#   .tool_input.command    実行しようとしているコマンド文字列
#   .cwd                   作業ディレクトリ（git commit 時の走査基点）
#
# 除外条件（誤検知回避）:
#   - tool_name が Bash 以外 → 対象外
#   - 秘密らしき語を示す引数が無い → 許可
#   - 値が環境変数参照（$ で始まる）→ 許可（規則が求める実践そのもの）
#   - 依存宣言ファイル（package.json・pyproject.toml・Gemfile 等）が
#     1つも見当たらない → 依存宣言・版固定・宣言済み入口の3規則は fail-open
#     （このリポジトリがどの言語・パッケージ管理の流儀かが不明なため）
#
# 既知の限界:
#   - 語彙リストに無い名前のフラグ（例: 社内独自の --secretkey 等）は検出できない
#   - 値が `$` で始まらない一見無害な文字列（例: プレースホルダの xxx）でも、
#     語彙に一致する引数名が付いていれば拒否される（誤検知は拒否方向に倒れる設計。
#     再実行時に環境変数参照へ書き換えれば解消する）
#   - 「使うツールを宣言で定める」は、依存宣言ファイルに devDependencies や
#     ツール名の記述があるかという簡易な判定にとどまり、実際にそのツールが
#     テスト・整形・静的解析の目的で使われているかまでは確認しない
#   - 「版を固定する」は、ロックファイルの実在と .gitignore からの除外有無の
#     確認にとどまり、実際に版管理へ登録済みかどうかまでは確認しない
#
# 使い方:
#   フック本体として: PreToolUse(Bash) の入力 JSON を stdin から受け取る
#   単体実行: check-secret-in-command-args.sh --self-test
#
# 止めるか知らせるか:
#   秘密の値をコマンドの引数に置かない: 止める（引数はシェルの履歴やプロセス一覧に残り、実行後に消せないため）
#   使うツールを宣言で定める: 知らせる（依存宣言ファイルへ使うツールの記載を足せば満たされるため）
#   版を固定する: 知らせる（ロックファイルを作って版管理へ登録すれば満たされるため）
#   コマンドは宣言した入口から呼ぶ: 知らせる（設定ファイルへテスト・整形・静的解析の入口を登録すれば満たされるため）
#
# 逃げ道:
#   SECRET_IN_COMMAND_ARGS_SKIP_REASON に理由を書けば通る。理由が空の場合は通らない
#   秘密の値を扱う検査のため、通過した記録は必ず標準エラーへ残る
set -uo pipefail

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${SECRET_IN_COMMAND_ARGS_SKIP_REASON:-}" ]; then
    echo "[SECRET-IN-COMMAND-ARGS-SKIP] 理由: ${SECRET_IN_COMMAND_ARGS_SKIP_REASON}"
    return 0
  fi
  return 1
}

SECRET_FLAG_ALT='password|passwd|secret|token|api[_-]?key|apikey|access[_-]?key|auth'

# 「秘密の値をコマンドの引数に置かない」規則の判定（既存。変更なし）
judge_secret_in_args() {
  # $1: command
  # 標準出力: 判定理由。戻り値: 0=許可・2=拒否
  local cmd="$1"

  if printf '%s' "$cmd" | grep -qE -- "--(${SECRET_FLAG_ALT})=[^\$[:space:]][^[:space:]]*"; then
    echo "拒否[秘密の値をコマンドの引数に置かない]: コマンド引数に秘密の値らしき文字列が直接書かれています（--<flag>=<値> 形式）"
    return 2
  fi

  if printf '%s' "$cmd" | grep -qE -- "--(${SECRET_FLAG_ALT})[[:space:]]+[^\$-][^[:space:]]*"; then
    echo "拒否[秘密の値をコマンドの引数に置かない]: コマンド引数に秘密の値らしき文字列が直接書かれています（--<flag> <値> 形式）"
    return 2
  fi

  if printf '%s' "$cmd" | grep -qE -- '(^|[[:space:]])-p[A-Za-z0-9_!@#%^&*.+/=-]{6,}'; then
    echo "拒否[秘密の値をコマンドの引数に置かない]: コマンド引数に秘密の値らしき文字列が直接書かれています（-p<値> 形式）"
    return 2
  fi

  echo "許可[秘密の値をコマンドの引数に置かない]: コマンド引数に秘密の値の直接記載は見つかりませんでした"
  return 0
}

# cwd 直下の依存宣言ファイルを1件見つける。種別と共に返す（"<種別> <パス>"）。無ければ空。
find_dependency_manifest() {
  local cwd="$1"
  if [ -f "$cwd/package.json" ]; then
    printf 'node %s' "$cwd/package.json"; return 0
  fi
  if [ -f "$cwd/pyproject.toml" ]; then
    printf 'python %s' "$cwd/pyproject.toml"; return 0
  fi
  if [ -f "$cwd/requirements.txt" ]; then
    printf 'python %s' "$cwd/requirements.txt"; return 0
  fi
  if [ -f "$cwd/Gemfile" ]; then
    printf 'ruby %s' "$cwd/Gemfile"; return 0
  fi
  if [ -f "$cwd/go.mod" ]; then
    printf 'go %s' "$cwd/go.mod"; return 0
  fi
  if [ -f "$cwd/Cargo.toml" ]; then
    printf 'rust %s' "$cwd/Cargo.toml"; return 0
  fi
  return 0
}

# 「使うツールを宣言で定める」規則の判定
judge_tools_declared() {
  local cwd="$1"
  local manifest kind path
  manifest="$(find_dependency_manifest "$cwd")"
  if [ -z "$manifest" ]; then
    echo "対象外[使うツールを宣言で定める]: 依存宣言ファイルが見当たらないため判定不能"
    return 0
  fi
  kind="${manifest%% *}"
  path="${manifest#* }"

  case "$kind" in
    node)
      if grep -qE '"(devDependencies|dependencies)"' "$path" 2>/dev/null; then
        echo "許可[使うツールを宣言で定める]: ${path} に依存の宣言があります"
        return 0
      fi
      ;;
    python)
      if grep -qE '\[tool\.(pytest|ruff|black|flake8|mypy)\]|^[A-Za-z0-9_.-]+([><=!~]|$)' "$path" 2>/dev/null; then
        echo "許可[使うツールを宣言で定める]: ${path} にツールの宣言があります"
        return 0
      fi
      ;;
    ruby)
      if grep -qE "gem[[:space:]]+['\"]" "$path" 2>/dev/null; then
        echo "許可[使うツールを宣言で定める]: ${path} にgemの宣言があります"
        return 0
      fi
      ;;
    go|rust)
      echo "許可[使うツールを宣言で定める]: ${path} が依存の宣言ファイルとして実在します"
      return 0
      ;;
  esac

  echo "通知[使うツールを宣言で定める]: ${path} に使用するツールの宣言が見当たりません"
  return 0
}

# 「版を固定する」規則の判定
judge_dependency_lockfile() {
  local cwd="$1"
  local manifest kind lockfile=""
  manifest="$(find_dependency_manifest "$cwd")"
  if [ -z "$manifest" ]; then
    echo "対象外[版を固定する]: 依存宣言ファイルが見当たらないため判定不能"
    return 0
  fi
  kind="${manifest%% *}"

  case "$kind" in
    node)
      for f in package-lock.json yarn.lock pnpm-lock.yaml; do
        [ -f "$cwd/$f" ] && { lockfile="$f"; break; }
      done
      ;;
    python)
      for f in poetry.lock Pipfile.lock; do
        [ -f "$cwd/$f" ] && { lockfile="$f"; break; }
      done
      ;;
    ruby)
      [ -f "$cwd/Gemfile.lock" ] && lockfile="Gemfile.lock"
      ;;
    go)
      [ -f "$cwd/go.sum" ] && lockfile="go.sum"
      ;;
    rust)
      [ -f "$cwd/Cargo.lock" ] && lockfile="Cargo.lock"
      ;;
  esac

  if [ -z "$lockfile" ]; then
    echo "通知[版を固定する]: 依存の版を固定するファイル（ロックファイル）が見当たりません"
    return 0
  fi

  if [ -f "$cwd/.gitignore" ] && grep -qE "(^|/)${lockfile}(\$|/)" "$cwd/.gitignore" 2>/dev/null; then
    echo "通知[版を固定する]: ${lockfile} が .gitignore で版管理から除外されています"
    return 0
  fi

  echo "許可[版を固定する]: ${lockfile} が実在し、版管理から除外されていません"
  return 0
}

# 「コマンドは宣言した入口から呼ぶ」規則の判定
judge_declared_entrypoints() {
  local cwd="$1"
  local has_config=0 has_entry=0

  if [ -f "$cwd/package.json" ]; then
    has_config=1
    if grep -qE '"(test|lint|format)"[[:space:]]*:' "$cwd/package.json" 2>/dev/null; then
      has_entry=1
    fi
  fi
  if [ -f "$cwd/Makefile" ]; then
    has_config=1
    if grep -qE '^(test|lint|format)[[:space:]]*:' "$cwd/Makefile" 2>/dev/null; then
      has_entry=1
    fi
  fi

  if [ "$has_config" -eq 0 ]; then
    echo "対象外[コマンドは宣言した入口から呼ぶ]: 判定対象の設定ファイル（package.json・Makefile）が見当たらないため判定不能"
    return 0
  fi
  if [ "$has_entry" -eq 0 ]; then
    echo "通知[コマンドは宣言した入口から呼ぶ]: 設定ファイルの実行定義にテスト・整形・静的解析の入口が見当たりません"
    return 0
  fi
  echo "許可[コマンドは宣言した入口から呼ぶ]: テスト・整形・静的解析の入口が登録されています"
  return 0
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

  local cmd cwd
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
  [ -z "$cmd" ] && exit 0
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)

  local msg code violations="" rc=0

  if msg="$(judge_secret_in_args "$cmd")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    violations="${violations}${msg}"$'\n'
    rc=2
  fi

  if [ -n "$cwd" ] && [ -d "$cwd" ] && printf '%s' "$cmd" | grep -q 'git' && printf '%s' "$cmd" | grep -q 'commit'; then
    for fn in judge_tools_declared judge_dependency_lockfile judge_declared_entrypoints; do
      if msg="$("$fn" "$cwd")"; then code=0; else code=$?; fi
      if [ "$code" -eq 2 ]; then
        violations="${violations}${msg}"$'\n'
        rc=2
      fi
    done
  fi

  [ "$rc" -eq 0 ] && exit 0

  ctx="[SECRET-IN-COMMAND-ARGS-BLOCK] 使うツールとコマンドの決まりの違反があります:"$'\n'"${violations}"
  jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  printf '%s\n' "$ctx" >&2
  exit 2
}

self_test() {
  local rc=0 msg code tmp

  # 系1: --token=<値> 形式で直接記載 → 拒否
  if msg="$(judge_secret_in_args "curl --token=sk_live_abc123XYZ https://api.example.com")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系1: --token=<値> 直接記載は拒否される（${msg}）"
  else
    echo "  [FAIL] 系1: 直接記載なのに拒否されなかった（exit=${code}）" >&2
    rc=1
  fi

  # 系2: -p<値> 形式で直接記載 → 拒否
  if msg="$(judge_secret_in_args "mysql -uroot -pSuperSecret123 mydb")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系2: -p<値> 直接記載は拒否される（${msg}）"
  else
    echo "  [FAIL] 系2: 直接記載なのに拒否されなかった（exit=${code}）" >&2
    rc=1
  fi

  # 系3: 環境変数参照 → 許可
  if msg="$(judge_secret_in_args 'curl --token=$API_TOKEN https://api.example.com')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系3: 環境変数参照は許可される（${msg}）"
  else
    echo "  [FAIL] 系3: 環境変数参照なのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系4: 秘密らしき引数が無いコマンド → 許可
  if msg="$(judge_secret_in_args "npm test")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系4: 秘密らしき引数が無いコマンドは許可される（${msg}）"
  else
    echo "  [FAIL] 系4: 対象外のはずが拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系5: --api-key に空白区切りで環境変数参照 → 許可
  if msg="$(judge_secret_in_args 'aws configure set --api-key $AWS_KEY')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系5: 空白区切りの環境変数参照も許可される（${msg}）"
  else
    echo "  [FAIL] 系5: 環境変数参照なのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系6: 依存宣言ファイルにツールの宣言が無い → 拒否（使うツールを宣言で定める）
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-in-command-args-self-test.XXXXXX")"
  printf '{"name":"app"}\n' > "$tmp/package.json"
  if msg="$(judge_tools_declared "$tmp")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系6: devDependenciesが無ければ通知される（${msg}）"
  else
    echo "  [FAIL] 系6: 宣言が無いのに知らせるだけで済まなかった（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系7: 依存宣言ファイルにツールの宣言がある → 許可（使うツールを宣言で定める）
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-in-command-args-self-test.XXXXXX")"
  printf '{"name":"app","devDependencies":{"eslint":"^9.0.0"}}\n' > "$tmp/package.json"
  if msg="$(judge_tools_declared "$tmp")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系7: devDependenciesがあれば許可される（${msg}）"
  else
    echo "  [FAIL] 系7: 宣言があるのに拒否された（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系8: package.jsonはあるがロックファイルが無い → 拒否（版を固定する）
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-in-command-args-self-test.XXXXXX")"
  printf '{"name":"app"}\n' > "$tmp/package.json"
  if msg="$(judge_dependency_lockfile "$tmp")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系8: ロックファイルが無ければ通知される（${msg}）"
  else
    echo "  [FAIL] 系8: ロックファイルが無いのに知らせるだけで済まなかった（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系9: package-lock.jsonが実在し除外されていない → 許可（版を固定する）
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-in-command-args-self-test.XXXXXX")"
  printf '{"name":"app"}\n' > "$tmp/package.json"
  printf '{}\n' > "$tmp/package-lock.json"
  if msg="$(judge_dependency_lockfile "$tmp")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系9: ロックファイルが実在すれば許可される（${msg}）"
  else
    echo "  [FAIL] 系9: ロックファイルがあるのに拒否された（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系10: package.jsonにtest/lint/formatの入口が無い → 拒否（宣言した入口から呼ぶ）
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-in-command-args-self-test.XXXXXX")"
  printf '{"scripts":{"build":"tsc"}}\n' > "$tmp/package.json"
  if msg="$(judge_declared_entrypoints "$tmp")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系10: test/lint入口が無ければ通知される（${msg}）"
  else
    echo "  [FAIL] 系10: 入口が無いのに知らせるだけで済まなかった（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系11: package.jsonにtestの入口がある → 許可（宣言した入口から呼ぶ）
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-in-command-args-self-test.XXXXXX")"
  printf '{"scripts":{"test":"jest"}}\n' > "$tmp/package.json"
  if msg="$(judge_declared_entrypoints "$tmp")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系11: testの入口があれば許可される（${msg}）"
  else
    echo "  [FAIL] 系11: 入口があるのに拒否された（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系12: 理由を設定すると skip される
  if msg="$(SECRET_IN_COMMAND_ARGS_SKIP_REASON="検証用の理由" should_skip_with_reason)"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -q 'SECRET-IN-COMMAND-ARGS-SKIP' && printf '%s' "$msg" | grep -q '検証用の理由'; then
    echo "  [PASS] 系12: 理由を設定するとskipされる（${msg}）"
  else
    echo "  [FAIL] 系12: 理由を設定してもskipされなかった（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系13: 理由が空文字だとskipされない
  if msg="$(SECRET_IN_COMMAND_ARGS_SKIP_REASON="" should_skip_with_reason)"; then code=0; else code=$?; fi
  if [ "$code" -eq 1 ]; then
    echo "  [PASS] 系13: 理由が空文字だとskipされない"
  else
    echo "  [FAIL] 系13: 理由が空文字なのにskipされた（exit=${code}）" >&2
    rc=1
  fi

  # 系14: run_hook経由で、知らせるだけの3規則（使うツール・版固定・宣言した入口）
  # のみが該当するgit commitは、集約の処理を通しても終了コード0のままになる
  local tmp14 out14 rc14
  tmp14="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-in-command-args-self-test.XXXXXX")"
  printf '{"name":"app"}\n' > "$tmp14/package.json"
  out14="$(printf '%s' "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m ok\"},\"cwd\":\"${tmp14}\"}" | bash "$0" 2>&1 1>/dev/null)"
  rc14=$?
  rm -rf "$tmp14"
  if [ "$rc14" -eq 0 ]; then
    echo "  [PASS] 系14: 知らせるだけの3規則しか該当しないgit commitはrun_hook経由でも終了コード0（out=${out14}）"
  else
    echo "  [FAIL] 系14: 知らせるだけのはずがrun_hook経由で終了コード0にならなかった（rc=${rc14}, out=${out14}）" >&2
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
