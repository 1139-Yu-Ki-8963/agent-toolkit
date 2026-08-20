#!/usr/bin/env bash
# check-generated-artifact-staged.sh — コミットと枝の決まりのうち静的解析を含む5規則の linter
#
# timing: PreToolUse(Bash)
# 対象規約: コミットと枝の決まり
#   - 生成物を版管理へ入れない（git add 時）
#   - 1コミットを1つの目的に絞る（git commit 時）
#   - 表題に何をしたかを書く（git commit 時）
#   - 枝の名前に目的を入れる（git checkout -b / git branch / git switch -c 時）
#   - 統合の単位を小さく保つ（git commit 時）
#
# 判定:
#   git add の引数に生成物・依存の実体の代表的な出力先が含まれていれば block する
#   （既存の判定。変更なし）。
#   git commit のときは、cwd を対象にステージ済みの差分を走査し、コミットの目的の
#   分散・表題の形式・統合の単位（差分行数）の3規則を判定する。
#   git checkout -b / git branch / git switch -c のときは、枝の名前の形式を判定する。
#   この4規則（分散・表題・統合の単位・枝の名前）は知らせるだけで、
#   足りない点があっても block はしない（exit 0 のまま）。
#
# 入力（hooks標準形。stdin JSON）:
#   .tool_name            "Bash" のときのみ判定対象
#   .tool_input.command    実行しようとしているコマンド文字列
#   .cwd                   作業ディレクトリ（git diff の実行基点）
#
# 値の上書き:
#   「表題に何をしたかを書く」（既定50文字）と「統合の単位を小さく保つ」
#   （既定400行）は、cwd 配下の docs/rules/**/rule.md にある
#   「## このプロジェクトの規則」表から、規則名が完全一致する行の内容列に
#   含まれる数字を上書き値として使う。見つからなければ既定値を使う。
#
# 除外条件（誤検知回避）:
#   - tool_name が Bash 以外 → 対象外
#   - 対象コマンドのいずれにも一致しない → 対象外
#   - cwd が空・参照不能、または git リポジトリでない → fail-open
#   - git commit のコマンド文字列からコミットメッセージを抽出できない
#     （-m / --message を使わない、ヒアドキュメント等）→ 表題の規則のみ fail-open
#   - ステージ済みの差分が無い（`git diff --cached` が空） → 分散・行数の2規則は fail-open
#
# 既知の限界:
#   - `git add .` / `git add -A` のような一括追加は、引数からファイル名を
#     特定できないため判定対象外とする（fail-open）。個別のパスを指定した
#     git add のみを検知する
#   - 出力先の名前は代表的な慣行に限定した固定リストであり、プロジェクト独自の
#     生成物ディレクトリ名（例: .output）は検出できない
#   - 「1コミットを1つの目的に絞る」は、ステージ済みファイルの最上位ディレクトリの
#     異なり数が4以上のときに違反とみなす簡易な目安であり、実際の変更内容の
#     関連性までは判定しない
#
# 使い方:
#   フック本体として: PreToolUse(Bash) の入力 JSON を stdin から受け取る
#   単体実行: check-generated-artifact-staged.sh --self-test
#
# 止めるか知らせるか:
#   生成物を版管理へ入れない: 止める（生成物が版管理へ混入すると履歴から消すのが難しいため）
#   1コミットを1つの目的に絞る: 知らせる（ステージする範囲を絞り込めば満たされるため）
#   表題に何をしたかを書く: 知らせる（表題を種別と対象を含む形に書き直せば満たされるため）
#   枝の名前に目的を入れる: 知らせる（枝の名前を<種別>/<対象>の形に付け直せば満たされるため）
#   統合の単位を小さく保つ: 知らせる（差分を上限内に収まる単位へ分ければ満たされるため）
#
# 逃げ道:
#   GENERATED_ARTIFACT_STAGED_SKIP_REASON に理由を書けば通る。理由が空の場合は通らない
set -uo pipefail

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${GENERATED_ARTIFACT_STAGED_SKIP_REASON:-}" ]; then
    echo "[GENERATED-ARTIFACT-STAGED-SKIP] 理由: ${GENERATED_ARTIFACT_STAGED_SKIP_REASON}"
    return 0
  fi
  return 1
}

is_generated_artifact() {
  # $1: ファイルの相対パス（引数トークン）
  local f="$1"
  case "$f" in
    node_modules|node_modules/*|*/node_modules|*/node_modules/*)
      return 0 ;;
    dist|dist/*|*/dist|*/dist/*)
      return 0 ;;
    build|build/*|*/build|*/build/*)
      return 0 ;;
    __pycache__|__pycache__/*|*/__pycache__|*/__pycache__/*)
      return 0 ;;
    *.pyc)
      return 0 ;;
    .venv|.venv/*|*/.venv|*/.venv/*)
      return 0 ;;
    venv|venv/*|*/venv|*/venv/*)
      return 0 ;;
    *.DS_Store|.DS_Store)
      return 0 ;;
    target|target/*|*/target|*/target/*)
      return 0 ;;
    coverage|coverage/*|*/coverage|*/coverage/*)
      return 0 ;;
    .next|.next/*|*/.next|*/.next/*)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

# 「生成物を版管理へ入れない」規則の判定（既存。変更なし）
judge_generated_artifact() {
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
    if is_generated_artifact "$tok"; then
      found="$tok"
      break
    fi
  done

  if [ -n "$found" ]; then
    echo "拒否[生成物を版管理へ入れない]: ${found} は生成物・依存の実体です。除外の指定へ登録し、版管理へ入れないでください"
    return 2
  fi

  echo "許可[生成物を版管理へ入れない]: 生成物らしきパスは見つかりませんでした"
  return 0
}

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

# $1: cwd, $2: rule name, $3: default number → 上書き数値 or 既定値
resolve_numeric_limit() {
  local cwd="$1" name="$2" default="$3" override num
  override="$(lookup_project_override_content "$cwd" "$name")"
  if [ -n "$override" ]; then
    num="$(printf '%s' "$override" | grep -oE '[0-9]+' | head -1)"
    if [ -n "$num" ]; then
      printf '%s' "$num"
      return 0
    fi
  fi
  printf '%s' "$default"
}

# 「1コミットを1つの目的に絞る」規則の判定
judge_commit_single_purpose() {
  local cwd="$1"
  local files count
  files="$(git -C "$cwd" diff --cached --name-only 2>/dev/null)"
  if [ -z "$files" ]; then
    echo "対象外[1コミットを1つの目的に絞る]: ステージ済みの差分が無いため判定不能"
    return 0
  fi
  count="$(printf '%s\n' "$files" | awk -F/ '{print $1}' | sort -u | wc -l | tr -d ' ')"
  if [ "$count" -ge 4 ]; then
    echo "通知[1コミットを1つの目的に絞る]: ステージ済みの変更が${count}個の無関係なディレクトリへまたがっています"
    return 0
  fi
  echo "許可[1コミットを1つの目的に絞る]: 変更が及ぶ最上位ディレクトリは${count}個です"
  return 0
}

# コマンド文字列から git commit のメッセージ（-m / --message）を抽出する
extract_commit_message() {
  local cmd="$1" msg=""
  msg="$(printf '%s' "$cmd" | sed -nE 's/.*-m[[:space:]]+"([^"]*)".*/\1/p')"
  [ -z "$msg" ] && msg="$(printf '%s' "$cmd" | sed -nE "s/.*-m[[:space:]]+'([^']*)'.*/\\1/p")"
  [ -z "$msg" ] && msg="$(printf '%s' "$cmd" | sed -nE 's/.*--message=?"([^"]*)".*/\1/p')"
  [ -z "$msg" ] && msg="$(printf '%s' "$cmd" | sed -nE "s/.*--message=?'([^']*)'.*/\\1/p")"
  printf '%s' "$msg"
}

# 「表題に何をしたかを書く」規則の判定
judge_commit_title_format() {
  # $1: cwd, $2: command
  local cwd="$1" cmd="$2"
  local msg limit len
  msg="$(extract_commit_message "$cmd")"
  if [ -z "$msg" ]; then
    echo "対象外[表題に何をしたかを書く]: コミットメッセージを抽出できないため判定不能"
    return 0
  fi

  limit="$(resolve_numeric_limit "$cwd" "表題に何をしたかを書く" 50)"
  len="$(printf '%s' "$msg" | jq -Rr 'length' 2>/dev/null)"
  [ -z "$len" ] && len=${#msg}

  local trimmed
  trimmed="$(printf '%s' "$msg" | sed -E 's/^[[:space:]]+|[[:space:]]+$//')"
  case "$(printf '%s' "$trimmed" | tr '[:upper:]' '[:lower:]')" in
    修正|更新|fix|update|fixed|updated)
      echo "通知[表題に何をしたかを書く]: 「${trimmed}」は変更の種別と対象を含みません"
      return 0
      ;;
  esac

  if [ -n "$len" ] && [ "$len" -gt "$limit" ]; then
    echo "通知[表題に何をしたかを書く]: 表題が${len}文字あり、上限の${limit}文字を超えています"
    return 0
  fi

  echo "許可[表題に何をしたかを書く]: 表題は${len}文字で上限${limit}文字以内です"
  return 0
}

# 「枝の名前に目的を入れる」規則の判定
judge_branch_name_format() {
  # $1: cwd, $2: command
  local cwd="$1" cmd="$2"
  local name=""

  if printf '%s' "$cmd" | grep -qE '(^|[^a-zA-Z])git[[:space:]]+checkout[[:space:]]+-b[[:space:]]+'; then
    name="$(printf '%s' "$cmd" | sed -E 's/^.*git[[:space:]]+checkout[[:space:]]+-b[[:space:]]+//' | awk '{print $1}')"
  elif printf '%s' "$cmd" | grep -qE '(^|[^a-zA-Z])git[[:space:]]+switch[[:space:]]+-c[[:space:]]+'; then
    name="$(printf '%s' "$cmd" | sed -E 's/^.*git[[:space:]]+switch[[:space:]]+-c[[:space:]]+//' | awk '{print $1}')"
  elif printf '%s' "$cmd" | grep -qE '(^|[^a-zA-Z])git[[:space:]]+branch[[:space:]]+'; then
    name="$(printf '%s' "$cmd" | sed -E 's/^.*git[[:space:]]+branch[[:space:]]+//' | awk '{print $1}')"
    case "$name" in
      -*) name="" ;;
    esac
  else
    echo "対象外[枝の名前に目的を入れる]: 枝を作るコマンドではありません"
    return 0
  fi

  if [ -z "$name" ]; then
    echo "対象外[枝の名前に目的を入れる]: 枝の名前を抽出できないため判定不能"
    return 0
  fi

  local override_content=""
  override_content="$(lookup_project_override_content "$cwd" "枝の名前に目的を入れる")"

  case "$name" in
    */*)
      local head_part="${name%%/*}" tail_part="${name#*/}"
      if [ -n "$head_part" ] && [ -n "$tail_part" ]; then
        echo "許可[枝の名前に目的を入れる]: ${name} は <種別>/<対象> の形式です"
        return 0
      fi
      ;;
  esac

  if [ -n "$override_content" ]; then
    echo "通知[枝の名前に目的を入れる]: ${name} は <種別>/<対象> の形式ではありません（プロジェクトの規則: ${override_content}）"
  else
    echo "通知[枝の名前に目的を入れる]: ${name} は既定の形式（<種別>/<対象>）ではありません"
  fi
  return 0
}

# 「統合の単位を小さく保つ」規則の判定
judge_change_size_limit() {
  local cwd="$1"
  local shortstat total limit ins del
  shortstat="$(git -C "$cwd" diff --cached --shortstat 2>/dev/null)"
  if [ -z "$shortstat" ]; then
    echo "対象外[統合の単位を小さく保つ]: ステージ済みの差分が無いため判定不能"
    return 0
  fi
  ins="$(printf '%s' "$shortstat" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || true)"
  del="$(printf '%s' "$shortstat" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || true)"
  [ -z "$ins" ] && ins=0
  [ -z "$del" ] && del=0
  total=$((ins + del))

  limit="$(resolve_numeric_limit "$cwd" "統合の単位を小さく保つ" 400)"

  if [ "$total" -gt "$limit" ]; then
    echo "通知[統合の単位を小さく保つ]: 差分が${total}行あり、上限の${limit}行を超えています"
    return 0
  fi
  echo "許可[統合の単位を小さく保つ]: 差分は${total}行で上限${limit}行以内です"
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
    if msg="$(judge_generated_artifact "$cmd")"; then code=0; else code=$?; fi
    if [ "$code" -eq 2 ]; then
      ctx="[GENERATED-ARTIFACT-STAGED-BLOCK] ${msg}。"
      jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
      printf '%s\n' "$ctx" >&2
      exit 2
    fi
    exit 0
  fi

  if [ -z "$cwd" ] || [ ! -d "$cwd" ] || ! git -C "$cwd" rev-parse --show-toplevel >/dev/null 2>&1; then
    exit 0
  fi

  if printf '%s' "$cmd" | grep -q 'git' && printf '%s' "$cmd" | grep -q 'commit'; then
    local violations="" rc=0
    for out in \
      "$(judge_commit_single_purpose "$cwd"; echo "|$?")" \
      "$(judge_commit_title_format "$cwd" "$cmd"; echo "|$?")" \
      "$(judge_change_size_limit "$cwd"; echo "|$?")"
    do
      local body="${out%|*}" c="${out##*|}"
      if [ "$c" -eq 2 ]; then
        violations="${violations}${body}"$'\n'
        rc=2
      fi
    done
    if [ "$rc" -eq 2 ]; then
      ctx="[GENERATED-ARTIFACT-STAGED-BLOCK] コミットと枝の決まりの違反があります:"$'\n'"${violations}"
      jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
      printf '%s\n' "$ctx" >&2
      exit 2
    fi
    exit 0
  fi

  if msg="$(judge_branch_name_format "$cwd" "$cmd")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    ctx="[GENERATED-ARTIFACT-STAGED-BLOCK] ${msg}。"
    jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
    printf '%s\n' "$ctx" >&2
    exit 2
  fi

  exit 0
}

self_test() {
  local rc=0 msg code tmp

  # 系1: node_modules 配下の追加 → 拒否（生成物を版管理へ入れない）
  if msg="$(judge_generated_artifact "git add node_modules/foo/package.json")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系1: node_modules 配下の追加は拒否される（${msg}）"
  else
    echo "  [FAIL] 系1: node_modules なのに拒否されなかった（exit=${code}）" >&2
    rc=1
  fi

  # 系2: dist 配下の追加 → 拒否
  if msg="$(judge_generated_artifact "git add dist/bundle.js")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系2: dist 配下の追加は拒否される（${msg}）"
  else
    echo "  [FAIL] 系2: dist なのに拒否されなかった（exit=${code}）" >&2
    rc=1
  fi

  # 系3: 通常のソースファイルの追加 → 許可
  if msg="$(judge_generated_artifact "git add src/app.js")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系3: 通常のソースファイルの追加は許可される（${msg}）"
  else
    echo "  [FAIL] 系3: 通常ファイルなのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系4: package.json の追加 → 許可
  if msg="$(judge_generated_artifact "git add package.json")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系4: package.json の追加は許可される（${msg}）"
  else
    echo "  [FAIL] 系4: package.json なのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系5: git add を含まないコマンド → 対象外として許可
  if msg="$(judge_generated_artifact "git status")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系5: git add を含まないコマンドは対象外（${msg}）"
  else
    echo "  [FAIL] 系5: 対象外のはずが拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系6: 4個の無関係ディレクトリへ変更が及ぶ → 拒否（1コミット1目的）
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-generated-artifact-staged-self-test.XXXXXX")"
  git -C "$tmp" init -q
  mkdir -p "$tmp/a" "$tmp/b" "$tmp/c" "$tmp/d"
  printf 'x\n' > "$tmp/a/f.txt"
  printf 'x\n' > "$tmp/b/f.txt"
  printf 'x\n' > "$tmp/c/f.txt"
  printf 'x\n' > "$tmp/d/f.txt"
  git -C "$tmp" add -A >/dev/null 2>&1
  if msg="$(judge_commit_single_purpose "$tmp")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系6: 4個の無関係ディレクトリへの変更は通知される（${msg}）"
  else
    echo "  [FAIL] 系6: 4個のディレクトリなのに知らせるだけで済まなかった（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系7: 1個のディレクトリだけの変更 → 許可（1コミット1目的）
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-generated-artifact-staged-self-test.XXXXXX")"
  git -C "$tmp" init -q
  mkdir -p "$tmp/a"
  printf 'x\n' > "$tmp/a/f.txt"
  printf 'y\n' > "$tmp/a/g.txt"
  git -C "$tmp" add -A >/dev/null 2>&1
  if msg="$(judge_commit_single_purpose "$tmp")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系7: 1個のディレクトリだけの変更は許可される（${msg}）"
  else
    echo "  [FAIL] 系7: 1個のディレクトリなのに拒否された（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系8: 表題が「修正」のみ → 拒否（表題の形式）
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-generated-artifact-staged-self-test.XXXXXX")"
  if msg="$(judge_commit_title_format "$tmp" 'git commit -m "修正"')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系8: 表題が「修正」だけなら通知される（${msg}）"
  else
    echo "  [FAIL] 系8: 表題が「修正」だけなのに知らせるだけで済まなかった（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系9: 種別と対象を含む短い表題 → 許可（表題の形式）
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-generated-artifact-staged-self-test.XXXXXX")"
  if msg="$(judge_commit_title_format "$tmp" 'git commit -m "ログイン画面のバリデーション不具合を修正"')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系9: 種別と対象を含む表題は許可される（${msg}）"
  else
    echo "  [FAIL] 系9: 妥当な表題なのに拒否された（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系10: 枝の名前が種別/対象の形式でない → 拒否（枝の名前）
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-generated-artifact-staged-self-test.XXXXXX")"
  if msg="$(judge_branch_name_format "$tmp" "git checkout -b 123")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系10: 通し番号だけの枝名は通知される（${msg}）"
  else
    echo "  [FAIL] 系10: 通し番号だけなのに知らせるだけで済まなかった（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系11: 枝の名前が <種別>/<対象> の形式 → 許可（枝の名前）
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-generated-artifact-staged-self-test.XXXXXX")"
  if msg="$(judge_branch_name_format "$tmp" "git checkout -b feature/login-fix")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系11: <種別>/<対象>形式の枝名は許可される（${msg}）"
  else
    echo "  [FAIL] 系11: 妥当な枝名なのに拒否された（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系12: 差分が上限行数を超える → 拒否（統合の単位）
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-generated-artifact-staged-self-test.XXXXXX")"
  git -C "$tmp" init -q
  seq 1 500 > "$tmp/big.txt"
  git -C "$tmp" add -A >/dev/null 2>&1
  if msg="$(judge_change_size_limit "$tmp")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系12: 500行の差分は通知される（${msg}）"
  else
    echo "  [FAIL] 系12: 上限超過なのに知らせるだけで済まなかった（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系13: 差分が上限行数以内 → 許可（統合の単位）
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-generated-artifact-staged-self-test.XXXXXX")"
  git -C "$tmp" init -q
  seq 1 10 > "$tmp/small.txt"
  git -C "$tmp" add -A >/dev/null 2>&1
  if msg="$(judge_change_size_limit "$tmp")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系13: 10行の差分は許可される（${msg}）"
  else
    echo "  [FAIL] 系13: 上限以内なのに拒否された（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系14: 環境変数に理由を設定 → should_skip_with_reasonが戻り値0でタグと理由を返す
  local out14
  if out14="$(GENERATED_ARTIFACT_STAGED_SKIP_REASON="テスト用の理由" should_skip_with_reason)"; then
    if printf '%s' "$out14" | grep -qF '[GENERATED-ARTIFACT-STAGED-SKIP]' && printf '%s' "$out14" | grep -qF 'テスト用の理由'; then
      echo "  [PASS] 系14: 理由を設定するとタグと理由付きでskipされる（${out14}）"
    else
      echo "  [FAIL] 系14: skipされたがタグまたは理由が出力に含まれない（${out14}）" >&2
      rc=1
    fi
  else
    echo "  [FAIL] 系14: 理由を設定したのにskipされなかった" >&2
    rc=1
  fi

  # 系15: 環境変数が空文字 → should_skip_with_reasonが戻り値1を返す
  if GENERATED_ARTIFACT_STAGED_SKIP_REASON="" should_skip_with_reason >/dev/null 2>&1; then
    echo "  [FAIL] 系15: 空文字なのにskipされた" >&2
    rc=1
  else
    echo "  [PASS] 系15: 環境変数が空文字ならskipされない"
  fi

  # 系16: run_hook経由で、知らせるだけの規則（1コミット1目的・表題の形式）
  # のみが該当するgit commitは、集約の処理を通しても終了コード0のままになる
  local tmp16 out16 rc16 input16
  tmp16="$(mktemp -d "${TMPDIR:-/tmp}/check-generated-artifact-staged-self-test.XXXXXX")"
  git -C "$tmp16" init -q
  mkdir -p "$tmp16/a" "$tmp16/b" "$tmp16/c" "$tmp16/d"
  printf 'x\n' > "$tmp16/a/f.txt"
  printf 'x\n' > "$tmp16/b/f.txt"
  printf 'x\n' > "$tmp16/c/f.txt"
  printf 'x\n' > "$tmp16/d/f.txt"
  git -C "$tmp16" add -A >/dev/null 2>&1
  input16="$(jq -n --arg cmd 'git commit -m "修正"' --arg cwd "$tmp16" '{tool_name:"Bash",tool_input:{command:$cmd},cwd:$cwd}')"
  out16="$(printf '%s' "$input16" | bash "$0" 2>&1 1>/dev/null)"
  rc16=$?
  rm -rf "$tmp16"
  if [ "$rc16" -eq 0 ]; then
    echo "  [PASS] 系16: 知らせるだけの規則しか該当しないgit commitはrun_hook経由でも終了コード0（out=${out16}）"
  else
    echo "  [FAIL] 系16: 知らせるだけのはずがrun_hook経由で終了コード0にならなかった（rc=${rc16}, out=${out16}）" >&2
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
