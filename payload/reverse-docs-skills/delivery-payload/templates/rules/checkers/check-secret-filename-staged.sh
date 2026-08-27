#!/usr/bin/env bash
# check-secret-filename-staged.sh — 開発環境の組み立て方の決まりのうち静的解析を含む6規則の linter
#
# timing: PreToolUse(Bash)
# 対象規約: 開発環境の組み立て方の決まり
#   - 秘密の値を版管理へ入れない（git add 時）
#   - 構築手順は環境構築手順.html に集める（git commit 時）
#   - 必要な版を明示する（git commit 時）
#   - 環境変数は雛形を版管理に置く（git commit 時）
#   - 起動の口を1つにする（git commit 時）
#   - 環境の差を手順書へ書く（git commit 時）
#
# 判定:
#   git add の引数に秘密の値を含みうるファイル名が含まれていれば block する
#   （既存の判定。変更なし）。
#   git commit のときは、作業ディレクトリ（cwd）を対象に残り5規則を走査する。
#   この5規則は知らせるだけで、足りない点があっても block はしない（exit 0 のまま）。
#
# 入力（hooks標準形。stdin JSON）:
#   .tool_name            "Bash" のときのみ判定対象
#   .tool_input.command    実行しようとしているコマンド文字列
#   .cwd                   作業ディレクトリ（git commit 時の走査基点）
#
# 除外条件（誤検知回避）:
#   - tool_name が Bash 以外 → 対象外
#   - git add / git commit のどちらでもないコマンド → 対象外
#   - cwd が空・参照不能 → fail-open（判定不能を block しない）
#   - 環境構築手順.html が無い場合、必要な版・環境の差の2規則は判定不能として fail-open
#     （文書が無ければ「手順書に書かれているか」自体を判定できないため）
#   - .gitignore に .env 系の除外記述が無い場合、環境変数の雛形規則は fail-open
#     （そのプロジェクトが .env 方式を採用しているか自体が不明なため）
#   - package.json・Makefile・docker-compose.yml のいずれも無い場合、起動の口の
#     規則は fail-open（判定対象の設定ファイルの流儀自体が不明なため）
#
# 既知の限界:
#   - `git add .` / `git add -A` のような一括追加は、引数からファイル名を
#     特定できないため判定対象外とする（fail-open）。個別のファイル名を
#     指定した git add のみを検知する
#   - ファイル名の判定は代表的な慣行に限定した固定リストであり、独自の
#     秘密ファイル命名（例: secrets.local.json）は検出できない
#   - 「必要な版を明示する」は、版を宣言するファイルの実在確認にとどめる。
#     手順書の記述内容と実際の版が一致しているかまでは判定しない
#     （文書とファイルの記述内容の突合は誤検知のリスクが高いため）
#
# 使い方:
#   フック本体として: PreToolUse(Bash) の入力 JSON を stdin から受け取る
#   単体実行: check-secret-filename-staged.sh --self-test
#
# 止めるか知らせるか:
#   秘密の値を版管理へ入れない: 止める（版管理の履歴に入ると秘密の値を後から消せないため）
#   構築手順は環境構築手順.html に集める: 知らせる（環境構築手順.htmlを1件作れば満たされるため）
#   必要な版を明示する: 知らせる（版を宣言するファイルを足せば満たされるため）
#   環境変数は雛形を版管理に置く: 知らせる（.env.example等の雛形を1件置けば満たされるため）
#   起動の口を1つにする: 知らせる（設定ファイルへdev/startの入口を登録すれば満たされるため）
#   環境の差を手順書へ書く: 知らせる（手順書へ対応する動作環境の記述を足せば満たされるため）
#
# 逃げ道:
#   SECRET_FILENAME_STAGED_SKIP_REASON に理由を書けば通る。理由が空の場合は通らない
#   秘密の値を扱う検査のため、通過した記録は必ず標準エラーへ残る
set -uo pipefail

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${SECRET_FILENAME_STAGED_SKIP_REASON:-}" ]; then
    echo "[SECRET-FILENAME-STAGED-SKIP] 理由: ${SECRET_FILENAME_STAGED_SKIP_REASON}"
    return 0
  fi
  return 1
}

is_secret_filename() {
  # $1: ファイルの相対パス（引数トークン）
  local f="$1"
  local base="${f##*/}"
  case "$base" in
    .env|.env.local|.env.production|.env.development|.env.test)
      return 0 ;;
    .env.example|.env.sample|.env.template)
      return 1 ;;
    .env.*)
      return 0 ;;
    id_rsa|id_ed25519|id_ecdsa|id_dsa)
      return 0 ;;
    *.pem)
      return 0 ;;
    credentials.json|*_credentials.json)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

# 「秘密の値を版管理へ入れない」規則の判定（既存。変更なし）
judge_secret_filename() {
  # $1: command
  # 標準出力: 判定理由。戻り値: 0=許可・2=拒否
  local cmd="$1"

  if ! printf '%s' "$cmd" | grep -qE '(^|[^a-zA-Z])git[[:space:]]+add([^a-zA-Z]|$)'; then
    echo "対象外: git add を含まないコマンドです"
    return 0
  fi

  local rest tok found=""
  rest=$(printf '%s' "$cmd" | sed -E 's/^.*git[[:space:]]+add[[:space:]]*//')
  for tok in $rest; do
    case "$tok" in
      -*) continue ;;
    esac
    if is_secret_filename "$tok"; then
      found="$tok"
      break
    fi
  done

  if [ -n "$found" ]; then
    echo "拒否[秘密の値を版管理へ入れない]: ${found} は秘密の値を含みうるファイルです。版管理へ登録しないでください"
    return 2
  fi

  echo "許可[秘密の値を版管理へ入れない]: 秘密の値らしきファイル名は見つかりませんでした"
  return 0
}

# cwd 配下から 環境構築手順.html を探す（node_modules・.git は除外）
find_setup_guide_all() {
  local cwd="$1"
  find "$cwd" -type f -name '環境構築手順.html' \
    -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null
}

# 「構築手順は環境構築手順.html に集める」規則の判定
judge_setup_guide_consolidated() {
  local cwd="$1"
  local matches count
  matches="$(find_setup_guide_all "$cwd")"
  if [ -z "$matches" ]; then
    echo "通知[構築手順は環境構築手順.html に集める]: 環境構築手順.html が見当たりません"
    return 0
  fi
  count=$(printf '%s\n' "$matches" | grep -c .)
  if [ "$count" -gt 1 ]; then
    echo "通知[構築手順は環境構築手順.html に集める]: 環境構築手順.html が複数実在します（${count}件）"
    return 0
  fi
  echo "許可[構築手順は環境構築手順.html に集める]: 環境構築手順.html が1件だけ実在します"
  return 0
}

# 「必要な版を明示する」規則の判定
judge_version_pinned() {
  local cwd="$1"
  local guide
  guide="$(find_setup_guide_all "$cwd" | head -1)"
  if [ -z "$guide" ]; then
    echo "対象外[必要な版を明示する]: 環境構築手順.html が見当たらないため判定不能"
    return 0
  fi

  local found=""
  local f
  for f in .nvmrc .tool-versions runtime.txt .python-version .ruby-version go.mod; do
    if [ -f "$cwd/$f" ]; then
      found="$f"
      break
    fi
  done
  if [ -z "$found" ] && [ -f "$cwd/package.json" ] && grep -q '"engines"' "$cwd/package.json" 2>/dev/null; then
    found="package.json(engines)"
  fi
  if [ -z "$found" ] && [ -f "$cwd/Dockerfile" ] && grep -qE '^FROM[[:space:]]+[^[:space:]]+:[0-9]' "$cwd/Dockerfile" 2>/dev/null; then
    found="Dockerfile(FROM)"
  fi

  if [ -z "$found" ]; then
    echo "通知[必要な版を明示する]: 版を宣言するファイル（.nvmrc・.tool-versions・runtime.txt・package.jsonのengines・DockerfileのFROM等）が見当たりません"
    return 0
  fi
  echo "許可[必要な版を明示する]: ${found} に版の宣言があります"
  return 0
}

# 「環境変数は雛形を版管理に置く」規則の判定
judge_env_template_present() {
  local cwd="$1"
  local gitignore="$cwd/.gitignore"
  if [ ! -f "$gitignore" ] || ! grep -qE '(^|/)\.env($|\.[A-Za-z0-9_.*]*$|\*$)' "$gitignore" 2>/dev/null; then
    echo "対象外[環境変数は雛形を版管理に置く]: .gitignoreに.env系の除外記述が無いため判定不能"
    return 0
  fi

  local tmpl
  tmpl="$(find "$cwd" -maxdepth 2 -type f \( -name '.env.example' -o -name '.env.sample' -o -name '.env.template' \) 2>/dev/null | head -1)"
  if [ -z "$tmpl" ]; then
    echo "通知[環境変数は雛形を版管理に置く]: .env.example・.env.sample・.env.templateのいずれも見当たりません"
    return 0
  fi
  echo "許可[環境変数は雛形を版管理に置く]: ${tmpl} が実在します"
  return 0
}

# 「起動の口を1つにする」規則の判定
judge_single_launch_entry() {
  local cwd="$1"
  local has_config=0 has_entry=0

  if [ -f "$cwd/package.json" ]; then
    has_config=1
    if grep -qE '"(dev|start)"[[:space:]]*:' "$cwd/package.json" 2>/dev/null; then
      has_entry=1
    fi
  fi
  if [ -f "$cwd/Makefile" ]; then
    has_config=1
    if grep -qE '^(dev|start)[[:space:]]*:' "$cwd/Makefile" 2>/dev/null; then
      has_entry=1
    fi
  fi
  if [ -f "$cwd/docker-compose.yml" ] || [ -f "$cwd/compose.yml" ]; then
    has_config=1
    has_entry=1
  fi

  if [ "$has_config" -eq 0 ]; then
    echo "対象外[起動の口を1つにする]: 判定対象の設定ファイル（package.json・Makefile・docker-compose.yml）が見当たらないため判定不能"
    return 0
  fi
  if [ "$has_entry" -eq 0 ]; then
    echo "通知[起動の口を1つにする]: 設定ファイルの実行定義に開発用の起動の入口（dev/start）が見当たりません"
    return 0
  fi
  echo "許可[起動の口を1つにする]: 開発用の起動の入口が登録されています"
  return 0
}

# 「環境の差を手順書へ書く」規則の判定
judge_env_difference_documented() {
  local cwd="$1"
  local guide
  guide="$(find_setup_guide_all "$cwd" | head -1)"
  if [ -z "$guide" ]; then
    echo "対象外[環境の差を手順書へ書く]: 環境構築手順.html が見当たらないため判定不能"
    return 0
  fi
  if grep -qiE 'windows|linux|macos|mac os|wsl' "$guide" 2>/dev/null; then
    echo "許可[環境の差を手順書へ書く]: ${guide} に対応する動作環境の記述があります"
    return 0
  fi
  echo "通知[環境の差を手順書へ書く]: ${guide} に対応する動作環境の記述が見当たりません"
  return 0
}

# git commit 時に走らせる5規則をまとめて判定する。
# 標準出力: 違反理由（複数行可）。戻り値: 0=全許可・2=1件以上拒否
judge_commit_time_rules() {
  local cwd="$1"
  local violations="" msg code rc=0

  for fn in judge_setup_guide_consolidated judge_version_pinned judge_env_template_present judge_single_launch_entry judge_env_difference_documented; do
    if msg="$("$fn" "$cwd")"; then code=0; else code=$?; fi
    if [ "$code" -eq 2 ]; then
      violations="${violations}${msg}"$'\n'
      rc=2
    fi
  done

  if [ "$rc" -eq 2 ]; then
    printf '%s' "$violations"
    return 2
  fi
  echo "許可: git commit 時の対象規則はすべて通過しました"
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

  local msg code
  if printf '%s' "$cmd" | grep -qE '(^|[^a-zA-Z])git[[:space:]]+add([^a-zA-Z]|$)'; then
    if msg="$(judge_secret_filename "$cmd")"; then code=0; else code=$?; fi
    if [ "$code" -eq 2 ]; then
      ctx="[SECRET-FILENAME-STAGED-BLOCK] ${msg}。認証の鍵・合言葉・接続文字列を版管理へ登録しないでください。"
      jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
      printf '%s\n' "$ctx" >&2
      exit 2
    fi
    exit 0
  fi

  if printf '%s' "$cmd" | grep -q 'git' && printf '%s' "$cmd" | grep -q 'commit'; then
    if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
      exit 0
    fi
    if msg="$(judge_commit_time_rules "$cwd")"; then code=0; else code=$?; fi
    if [ "$code" -eq 2 ]; then
      ctx="[SECRET-FILENAME-STAGED-BLOCK] 開発環境の組み立て方の決まりの違反があります:"$'\n'"${msg}"
      jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
      printf '%s\n' "$ctx" >&2
      exit 2
    fi
  fi

  exit 0
}

self_test() {
  local rc=0 msg code tmp

  # 系1: .env の追加 → 拒否（秘密の値を版管理へ入れない）
  if msg="$(judge_secret_filename "git add .env")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系1: .env の追加は拒否される（${msg}）"
  else
    echo "  [FAIL] 系1: .env なのに拒否されなかった（exit=${code}）" >&2
    rc=1
  fi

  # 系2: 秘密鍵ファイルの追加 → 拒否
  if msg="$(judge_secret_filename "git add config/id_rsa")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系2: 秘密鍵ファイルの追加は拒否される（${msg}）"
  else
    echo "  [FAIL] 系2: 秘密鍵ファイルなのに拒否されなかった（exit=${code}）" >&2
    rc=1
  fi

  # 系3: .env.example（雛形）の追加 → 許可
  if msg="$(judge_secret_filename "git add .env.example")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系3: .env.example（雛形）の追加は許可される（${msg}）"
  else
    echo "  [FAIL] 系3: 雛形なのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系4: 通常のソースファイルの追加 → 許可
  if msg="$(judge_secret_filename "git add src/app.js")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系4: 通常のソースファイルの追加は許可される（${msg}）"
  else
    echo "  [FAIL] 系4: 通常ファイルなのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系5: git add を含まないコマンド → 対象外として許可
  if msg="$(judge_secret_filename "git status")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系5: git add を含まないコマンドは対象外（${msg}）"
  else
    echo "  [FAIL] 系5: 対象外のはずが拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系6: 環境構築手順.htmlが無い → 拒否（構築手順の集約）
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-filename-staged-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  if msg="$(judge_setup_guide_consolidated "$tmp")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系6: 環境構築手順.htmlが無ければ通知される（${msg}）"
  else
    echo "  [FAIL] 系6: 環境構築手順.htmlが無いのに知らせるだけで済まなかった（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系7: 環境構築手順.htmlが1件だけ → 許可（構築手順の集約）
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-filename-staged-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  mkdir -p "$tmp/docs"
  printf '<html></html>\n' > "$tmp/docs/環境構築手順.html"
  if msg="$(judge_setup_guide_consolidated "$tmp")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系7: 環境構築手順.htmlが1件なら許可される（${msg}）"
  else
    echo "  [FAIL] 系7: 1件しかないのに拒否された（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系8: 手順書はあるが版宣言ファイルが無い → 拒否（版の明示）
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-filename-staged-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  mkdir -p "$tmp/docs"
  printf '<html></html>\n' > "$tmp/docs/環境構築手順.html"
  if msg="$(judge_version_pinned "$tmp")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系8: 版宣言ファイルが無ければ通知される（${msg}）"
  else
    echo "  [FAIL] 系8: 版宣言ファイルが無いのに知らせるだけで済まなかった（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系9: 手順書と .nvmrc がある → 許可（版の明示）
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-filename-staged-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  mkdir -p "$tmp/docs"
  printf '<html></html>\n' > "$tmp/docs/環境構築手順.html"
  printf '20\n' > "$tmp/.nvmrc"
  if msg="$(judge_version_pinned "$tmp")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系9: .nvmrcがあれば許可される（${msg}）"
  else
    echo "  [FAIL] 系9: .nvmrcがあるのに拒否された（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系10: .gitignoreに.env除外があるが雛形が無い → 拒否（環境変数の雛形）
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-filename-staged-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  printf '.env\n' > "$tmp/.gitignore"
  if msg="$(judge_env_template_present "$tmp")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系10: 雛形が無ければ通知される（${msg}）"
  else
    echo "  [FAIL] 系10: 雛形が無いのに知らせるだけで済まなかった（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系11: .gitignoreに.env除外があり雛形もある → 許可（環境変数の雛形）
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-filename-staged-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  printf '.env\n' > "$tmp/.gitignore"
  printf 'KEY=\n' > "$tmp/.env.example"
  if msg="$(judge_env_template_present "$tmp")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系11: 雛形があれば許可される（${msg}）"
  else
    echo "  [FAIL] 系11: 雛形があるのに拒否された（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系12: package.jsonはあるがdev/start入口が無い → 拒否（起動の口）
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-filename-staged-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  printf '{"scripts":{"build":"tsc"}}\n' > "$tmp/package.json"
  if msg="$(judge_single_launch_entry "$tmp")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系12: dev/start入口が無ければ通知される（${msg}）"
  else
    echo "  [FAIL] 系12: 入口が無いのに知らせるだけで済まなかった（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系13: package.jsonにdev入口がある → 許可（起動の口）
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-filename-staged-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  printf '{"scripts":{"dev":"vite"}}\n' > "$tmp/package.json"
  if msg="$(judge_single_launch_entry "$tmp")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系13: dev入口があれば許可される（${msg}）"
  else
    echo "  [FAIL] 系13: 入口があるのに拒否された（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系14: 手順書に動作環境の記述が無い → 拒否（環境の差）
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-filename-staged-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  mkdir -p "$tmp/docs"
  printf '<html><body>手順です</body></html>\n' > "$tmp/docs/環境構築手順.html"
  if msg="$(judge_env_difference_documented "$tmp")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系14: 動作環境の記述が無ければ通知される（${msg}）"
  else
    echo "  [FAIL] 系14: 記述が無いのに知らせるだけで済まなかった（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系15: 手順書にWindows WSL2の記述がある → 許可（環境の差）
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-filename-staged-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  mkdir -p "$tmp/docs"
  printf '<html><body>対応OS: Windows WSL2環境</body></html>\n' > "$tmp/docs/環境構築手順.html"
  if msg="$(judge_env_difference_documented "$tmp")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系15: 対応OSの記述があれば許可される（${msg}）"
  else
    echo "  [FAIL] 系15: 記述があるのに拒否された（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系16: 理由を設定すると skip される
  if msg="$(SECRET_FILENAME_STAGED_SKIP_REASON="検証用の理由" should_skip_with_reason)"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -q 'SECRET-FILENAME-STAGED-SKIP' && printf '%s' "$msg" | grep -q '検証用の理由'; then
    echo "  [PASS] 系16: 理由を設定するとskipされる（${msg}）"
  else
    echo "  [FAIL] 系16: 理由を設定してもskipされなかった（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系17: 理由が空文字だとskipされない
  if msg="$(SECRET_FILENAME_STAGED_SKIP_REASON="" should_skip_with_reason)"; then code=0; else code=$?; fi
  if [ "$code" -eq 1 ]; then
    echo "  [PASS] 系17: 理由が空文字だとskipされない"
  else
    echo "  [FAIL] 系17: 理由が空文字なのにskipされた（exit=${code}）" >&2
    rc=1
  fi

  # 系18: run_hook経由で、知らせるだけの5規則（構築手順の集約・版の明示・
  # 環境変数の雛形・起動の口・環境の差）のみが該当するgit commitは、
  # 集約の処理を通しても終了コード0のままになる
  local tmp18 out18 rc18
  if ! tmp18="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-filename-staged-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp18" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  out18="$(printf '%s' "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m ok\"},\"cwd\":\"${tmp18}\"}" | bash "$0" 2>&1 1>/dev/null)"
  rc18=$?
  rm -rf "$tmp18"
  if [ "$rc18" -eq 0 ]; then
    echo "  [PASS] 系18: 知らせるだけの5規則しか該当しないgit commitはrun_hook経由でも終了コード0（out=${out18}）"
  else
    echo "  [FAIL] 系18: 知らせるだけのはずがrun_hook経由で終了コード0にならなかった（rc=${rc18}, out=${out18}）" >&2
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
