#!/usr/bin/env bash
# check-secret-literal-in-code.sh — 認証と入力と秘密の値の決まりの linter
#
# timing: PreToolUse(Write|Edit)
# 対象規約: 認証と入力と秘密の値の決まり（tool-defined/security.md）
#
# 検査する規則（検査列に「静的解析」を含むもの、6件すべて）:
#   1. 問い合わせを文字列の結合で組み立てない
#   2. 利用者の入力を素のまま出力しない
#   3. 権限の確認を処理の側で行う
#   4. 秘密の値をコードへ書かない
#   5. 入力の検証を境界で行う
#   6. 依存の脆弱性を決めた間隔で確かめる
#
# 判定（規則ごと）:
#   1. 問い合わせを文字列の結合で組み立てない:
#      SQL キーワード（SELECT / INSERT INTO / UPDATE / DELETE FROM）を含む行に、
#      引用符と "+" が隣接する文字列結合の記述が同時にあれば違反とする。
#   2. 利用者の入力を素のまま出力しない:
#      innerHTML= / dangerouslySetInnerHTML / document.write( 等の出力先（シンク）
#      と、req. / request. / params. 等の入力元（ソース）が同じ行に現れ、かつ
#      本文全体に無害化（sanitize/escape/DOMPurify 等）の記述が1つも無ければ
#      違反とする。
#   3. 権限の確認を処理の側で行う:
#      本文に処理の入口らしい記述（router. / route( / @Get 等の HTTP メソッド
#      デコレーター / app.get( 等 / def ...(request / handler / Handler）が
#      無ければ対象外とする。あれば cwd 配下の docs/rules/**/rule.md の
#      「## このプロジェクトの規則」表から、規則名「権限の確認を処理の側で
#      行う」の宣言（権限の確認の呼び出しの名前）を引く。宣言が無ければ
#      判定せず通知にとどめる。宣言があれば、その内容から英字で始まり
#      英数字とアンダースコアが続く3文字以上の語を1つ取り出し（最初に
#      一致したもの）、本文にその語が含まれているかを走査する。
#   4. 秘密の値をコードへ書かない（既存）:
#      (a) AWS アクセスキー形式 (b) 秘密鍵ファイルのヘッダ (c) *_KEY 等への
#      引用符付き16文字以上のリテラル代入、のいずれかを違反とする。
#   5. 入力の検証を境界で行う:
#      req.body / req.query / req.params / request.GET 等の外部入力の直接
#      アクセスが本文にあり、かつ本文全体に検証の記述（validate/schema/zod/
#      joi/yup/pydantic/assert/isValid 等）が1つも無ければ違反とする。
#   6. 依存の脆弱性を決めた間隔で確かめる:
#      file_path が CI 設定ファイル（.github/workflows/*.yml 等）で、かつ
#      本文に依存脆弱性検査の記述（npm audit / dependabot / snyk 等）があるのに、
#      週次の cron 指定（曜日欄が数字で埋まる5フィールドの cron 文字列）が
#      本文に見当たらなければ違反とする。CI 設定ファイルでない、または
#      依存脆弱性検査の記述自体が無い場合は対象外とする（誤検出回避）。
#
# 判定の設計:
#   1・2・5 は「危険な記述パターンの存在」と「対処の記述の不在」の組み合わせで
#   判定する。対処の記述は同じ行の近傍ではなく本文全体から探す（validate 等の
#   対処は呼び出し箇所から離れた場所に書かれることが多いため、近傍窓で探すと
#   対処済みのコードまで誤検知する）。6 は file_path で CI 設定ファイルに限定し、
#   依存脆弱性検査そのものへの言及が無い一般の CI 設定ファイルは対象外とする
#   （すべての CI 設定に依存脆弱性検査を義務付けると誤検出が増えるため）。
#   3 は、対象プロジェクトごとに権限の確認を呼び出す関数の名前が異なるため、
#   ファイルパスではなく cwd 配下の docs/rules/**/rule.md の宣言（リバース
#   解析が起こした「このプロジェクトの規則」）を仲立ちにする。宣言が無ければ
#   判定せず通知にとどめ、宣言があれば本文にその呼び出しの名前が含まれて
#   いるかを走査する。
#
# 除外条件（誤検知回避）:
#   - tool_name が Write / Edit 以外 → 対象外
#   - 本文（content / new_string）が空 → 対象外
#   - 各規則の判定条件を満たさない → 対象外
#   - 3: 本文に処理の入口らしい記述が無い → 対象外。cwd 配下の
#     docs/rules/**/rule.md に「権限の確認を処理の側で行う」の宣言が無い
#     → 判定せず通知にとどめる
#
# 既知の限界:
#   - 1 は "+" による結合のみを検出する（PHP の "." 結合、f-string 等は検出しない）
#   - 2 は同一行での入力元・出力先の共起のみを見るため、複数行にまたがる記述は
#     検出できない。無害化の記述は本文のどこにあっても対処済みとみなす（実際に
#     その入力へ適用されているかまでは確認しない）
#   - 5 は入力元アクセスと検証記述の共起のみを見るため、検証記述が別ファイルに
#     ある場合は誤検知しうる
#   - 6 は cron の曜日欄が数字であることのみを週次の根拠とするため、
#     "0 0 * * 1-5"（平日毎日）のような範囲指定も週次とみなしてしまう
#   - MultiEdit は対象外（本checkerは Write / Edit のみに対応する）
#   - 3: 宣言から値を取り出す方式は、宣言が自由な文章のため最初に一致した
#     1つだけを見る。本文にその名前の呼び出しが含まれているかしか見ないため、
#     実際にその処理の入口の直前で呼ばれているかまでは確認しない
#
# 使い方:
#   フック本体として: PreToolUse(Write|Edit) の入力 JSON を stdin から受け取る
#   単体実行: check-secret-literal-in-code.sh --self-test
#
# 止めるか知らせるか:
#   問い合わせを文字列の結合で組み立てない: 止める（SQLインジェクションの脆弱性はコードに残ると攻撃の実害に直結するため）
#   利用者の入力を素のまま出力しない: 止める（未検証の出力はXSS等の実害につながり書いた後には取り消せないため）
#   権限の確認を処理の側で行う: 止める（権限確認の抜けは不正アクセスという取り消せない実害につながるため）
#   秘密の値をコードへ書かない: 止める（版管理に入った秘密の値は履歴から消せないため）
#   入力の検証を境界で行う: 止める（未検証の入力はシステムの侵害という取り消せない実害につながるため）
#   依存の脆弱性を決めた間隔で確かめる: 止める（確認間隔が空くほど脆弱性の放置期間が伸び攻撃を受けるリスクが積み上がるため）
#
# 逃げ道:
#   SECRET_LITERAL_IN_CODE_SKIP_REASON に理由を書けば通る。理由が空の場合は通らない
#   秘密の値を扱う検査のため、通過した記録は必ず標準エラーへ残る
set -uo pipefail

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${SECRET_LITERAL_IN_CODE_SKIP_REASON:-}" ]; then
    echo "[SECRET-LITERAL-IN-CODE-SKIP] 理由: ${SECRET_LITERAL_IN_CODE_SKIP_REASON}"
    return 0
  fi
  return 1
}

AWS_KEY_RE='AKIA[0-9A-Z]{16}'
PRIVATE_KEY_RE='-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'
ASSIGN_RE='[A-Za-z_][A-Za-z0-9_]*(KEY|SECRET|TOKEN|PASSWORD)[A-Za-z0-9_]*[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9_./+=-]{16,}["'"'"']'

SQL_KEYWORD_RE='(SELECT|INSERT[[:space:]]+INTO|UPDATE|DELETE[[:space:]]+FROM)'
CONCAT_RE='["'"'"'][[:space:]]*\+|\+[[:space:]]*["'"'"']'

SINK_RE='\.innerHTML[[:space:]]*=|dangerouslySetInnerHTML|document\.write\(|render_template_string\(|\.html\(|v-html='
SOURCE_RE='req\.|request\.|params\.|query\.|input\.|user[A-Za-z]*\.|body\.'
SANITIZE_RE='sanitize|escape|DOMPurify|escapeHtml|textContent|autoescape|striptags|bleach\.'

ENTRY_RE='req\.(body|query|params)\b|request\.(GET|POST|form)\b|sys\.argv\b|input\(\)'
VALIDATE_RE='validate|schema|zod|joi|yup|pydantic|sanitize|assert|isValid|parse\('

SCAN_KEYWORD_RE='npm audit|yarn audit|pip-audit|safety check|bundler-audit|dependabot|snyk|trivy|audit-ci'
WEEKLY_CRON_RE='cron:[[:space:]]*["'"'"']?[0-9*/,-]+[[:space:]]+[0-9*/,-]+[[:space:]]+[0-9*/,-]+[[:space:]]+[0-9*/,-]+[[:space:]]+[0-6]'

PERMISSION_ENTRY_RE='(router\.|route\(|@(Get|Post|Put|Delete|Patch)|app\.(get|post|put|delete|patch)|def [a-z_]+\(request|handler|Handler)'

is_ci_file() {
  case "$1" in
    */.github/workflows/*.yml|*/.github/workflows/*.yaml) return 0 ;;
    */.gitlab-ci.yml|*/.gitlab-ci.yaml) return 0 ;;
    */.circleci/config.yml|*/.circleci/config.yaml) return 0 ;;
    */dependabot.yml|*/dependabot.yaml) return 0 ;;
    .github/workflows/*.yml|.github/workflows/*.yaml) return 0 ;;
    .gitlab-ci.yml|.gitlab-ci.yaml) return 0 ;;
    *) return 1 ;;
  esac
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

# 「権限の確認を処理の側で行う」規則の判定
judge_permission_check() {
  # $1: cwd, $2: file_path, $3: content
  local cwd="$1" file_path="$2" content="$3"

  if ! printf '%s' "$content" | grep -qiE -- "$PERMISSION_ENTRY_RE" 2>/dev/null; then
    echo "対象外[権限の確認を処理の側で行う]: 処理の入口らしい記述が見当たりません"
    return 0
  fi

  local override
  override="$(lookup_project_override_content "$cwd" "権限の確認を処理の側で行う")"
  if [ -z "$override" ]; then
    echo "通知[権限の確認を処理の側で行う]: このプロジェクトの規則に権限の確認の宣言がないため判定していません。リバース解析を実行すると判定の対象になります"
    return 0
  fi

  local key
  key="$(printf '%s' "$override" | grep -oE '[A-Za-z][A-Za-z0-9_]{2,}' | head -1)"
  if [ -z "$key" ]; then
    echo "通知[権限の確認を処理の側で行う]: このプロジェクトの規則に宣言はありますが、権限の確認の呼び出しの名前を読み取れません"
    return 0
  fi

  if ! printf '%s' "$content" | grep -qF -- "$key" 2>/dev/null; then
    echo "拒否[権限の確認を処理の側で行う]: 処理の入口がありますが、権限の確認（${key}）が見当たりません"
    return 2
  fi

  echo "許可[権限の確認を処理の側で行う]: 処理の入口に権限の確認（${key}）があります"
  return 0
}

judge() {
  # $1: file_path, $2: 本文テキスト, $3: cwd（省略可。省略時は「権限の確認を処理の側で行う」を対象外として扱う）
  # 標準出力: 判定理由。戻り値: 0=許可・2=拒否
  local file_path="$1" text="$2" cwd="${3:-}"

  if [ -z "$text" ]; then
    echo "対象外: 本文が空"
    return 0
  fi

  if [ -n "$cwd" ]; then
    local pc_msg pc_code
    if pc_msg="$(judge_permission_check "$cwd" "$file_path" "$text")"; then pc_code=0; else pc_code=$?; fi
    if [ "$pc_code" -eq 2 ]; then
      echo "$pc_msg"
      return 2
    fi
    echo "$pc_msg"
  fi

  # 規則: 秘密の値をコードへ書かない
  if printf '%s' "$text" | grep -qE -- "$AWS_KEY_RE"; then
    echo "拒否[秘密の値をコードへ書かない]: AWS アクセスキー形式のリテラルが含まれている"
    return 2
  fi
  if printf '%s' "$text" | grep -qE -- "$PRIVATE_KEY_RE"; then
    echo "拒否[秘密の値をコードへ書かない]: 秘密鍵ファイルのヘッダが含まれている"
    return 2
  fi
  if printf '%s' "$text" | grep -qEi -- "$ASSIGN_RE"; then
    echo "拒否[秘密の値をコードへ書かない]: 鍵・合言葉・トークンらしい識別子へリテラル値が直接代入されている"
    return 2
  fi

  # 規則: 問い合わせを文字列の結合で組み立てない
  local sql_hit
  sql_hit=$(printf '%s\n' "$text" | grep -inE -- "$SQL_KEYWORD_RE" 2>/dev/null | grep -E -- "$CONCAT_RE" 2>/dev/null | head -1)
  if [ -n "$sql_hit" ]; then
    echo "拒否[問い合わせを文字列の結合で組み立てない]: SQL文の組み立てに文字列結合が使われている（${sql_hit}）"
    return 2
  fi

  # 規則: 利用者の入力を素のまま出力しない
  local sink_hit
  sink_hit=$(printf '%s\n' "$text" | grep -inE -- "$SINK_RE" 2>/dev/null | grep -E -- "$SOURCE_RE" 2>/dev/null | head -1)
  if [ -n "$sink_hit" ] && ! printf '%s' "$text" | grep -qEi -- "$SANITIZE_RE"; then
    echo "拒否[利用者の入力を素のまま出力しない]: 入力元の値を無害化せずに出力先へ渡している（${sink_hit}）"
    return 2
  fi

  # 規則: 入力の検証を境界で行う
  if printf '%s' "$text" | grep -qE -- "$ENTRY_RE" && ! printf '%s' "$text" | grep -qEi -- "$VALIDATE_RE"; then
    echo "拒否[入力の検証を境界で行う]: 外部からの入力を受ける記述があるが検証の記述が見当たらない"
    return 2
  fi

  # 規則: 依存の脆弱性を決めた間隔で確かめる（CI設定ファイル限定）
  if is_ci_file "$file_path" && printf '%s' "$text" | grep -qEi -- "$SCAN_KEYWORD_RE"; then
    if ! printf '%s' "$text" | grep -qE -- "$WEEKLY_CRON_RE"; then
      echo "拒否[依存の脆弱性を決めた間隔で確かめる]: 依存脆弱性検査の記述はあるが週次の cron 指定が見当たらない"
      return 2
    fi
  fi

  echo "許可: 認証と入力と秘密の値の決まりの違反は検出されなかった"
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
  [ "$tool" != "Write" ] && [ "$tool" != "Edit" ] && exit 0

  local file_path
  file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

  local text
  if [ "$tool" = "Write" ]; then
    text=$(printf '%s' "$input" | jq -r '.tool_input.content // empty' 2>/dev/null)
  else
    text=$(printf '%s' "$input" | jq -r '.tool_input.new_string // empty' 2>/dev/null)
  fi

  local cwd
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)

  local msg code
  if msg="$(judge "$file_path" "$text" "$cwd")"; then code=0; else code=$?; fi

  [ "$code" -eq 0 ] && exit 0

  ctx="[SECRET-LITERAL-IN-CODE-BLOCK] ${msg}。該当箇所を修正してください。"
  jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  printf '%s\n' "$ctx" >&2
  exit 2
}

self_test() {
  local rc=0 msg code

  # 系1: AWS アクセスキー形式 → 拒否
  # 秘密の値を検出する側の hook(push 時の検査)が、この自己テストの入力そのものを秘密の値と読み違えないよう、
  # 接頭辞と残りを分けて実行時に連結する(値は同じ。実測 2026-08-28: 配布先の push が止まった)
  local aws_key_suffix='ABCDEFGHIJKLMNOP'
  local t1='const key = "AKIA'"$aws_key_suffix"'";'
  if msg="$(judge "app.js" "$t1")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF "秘密の値をコードへ書かない"; then
    echo "  [PASS] 系1: AWSキー形式は拒否される（${msg}）"
  else
    echo "  [FAIL] 系1: AWSキー形式なのに許可されない、または規則名不一致（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系2: 秘密鍵ヘッダ → 拒否
  # 系1と同じ理由で、鍵の見出し語を実行時に連結する(値は同じ)
  local pk_word='PRIVATE'
  local t2='-----BEGIN RSA '"$pk_word"' KEY-----
MIIEpAIBAAKCAQEA...
-----END RSA PRIVATE KEY-----'
  if msg="$(judge "app.js" "$t2")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF "秘密の値をコードへ書かない"; then
    echo "  [PASS] 系2: 秘密鍵ヘッダは拒否される（${msg}）"
  else
    echo "  [FAIL] 系2: 秘密鍵ヘッダなのに拒否されない、または規則名不一致（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系3: 識別子へのリテラル直接代入 → 拒否
  local t3='API_SECRET_KEY = "sk_live_abcdef1234567890abcdef"'
  if msg="$(judge "app.js" "$t3")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF "秘密の値をコードへ書かない"; then
    echo "  [PASS] 系3: 秘密リテラル代入は拒否される（${msg}）"
  else
    echo "  [FAIL] 系3: 秘密リテラル代入なのに拒否されない、または規則名不一致（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系4: 環境変数からの読み出し（リテラルなし） → 許可
  local t4='const apiKey = process.env.API_KEY;'
  if msg="$(judge "app.js" "$t4")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系4: 環境変数読み出しは許可される（${msg}）"
  else
    echo "  [FAIL] 系4: 環境変数読み出しなのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系5: 秘密と無関係な通常コード → 許可
  local t5='function add(a, b) { return a + b; }'
  if msg="$(judge "app.js" "$t5")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系5: 無関係な通常コードは許可される（${msg}）"
  else
    echo "  [FAIL] 系5: 無関係な通常コードなのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系6: SQL文を "+" で結合 → 拒否（問い合わせを文字列の結合で組み立てない）
  local t6='const q = "SELECT * FROM users WHERE id = " + userId;'
  if msg="$(judge "app.js" "$t6")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF "問い合わせを文字列の結合で組み立てない"; then
    echo "  [PASS] 系6: SQL文の文字列結合は拒否される（${msg}）"
  else
    echo "  [FAIL] 系6: SQL文の文字列結合なのに拒否されない、または規則名不一致（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系7: SQL文をパラメータ化して渡す（結合なし） → 許可
  local t7='const q = "SELECT * FROM users WHERE id = ?";
db.query(q, [userId]);'
  if msg="$(judge "app.js" "$t7")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系7: パラメータ化されたSQL文は許可される（${msg}）"
  else
    echo "  [FAIL] 系7: パラメータ化されたSQL文なのに拒否された（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系8: 入力元の値を無害化せずに innerHTML へ出力 → 拒否（利用者の入力を素のまま出力しない）
  local t8='el.innerHTML = req.query.name;'
  if msg="$(judge "app.js" "$t8")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF "利用者の入力を素のまま出力しない"; then
    echo "  [PASS] 系8: 無害化なしのinnerHTML出力は拒否される（${msg}）"
  else
    echo "  [FAIL] 系8: 無害化なしのinnerHTML出力なのに拒否されない、または規則名不一致（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系9: 入力元の値を無害化してから innerHTML へ出力 → 許可
  local t9='el.innerHTML = DOMPurify.sanitize(req.query.name);'
  if msg="$(judge "app.js" "$t9")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系9: 無害化ありのinnerHTML出力は許可される（${msg}）"
  else
    echo "  [FAIL] 系9: 無害化ありのinnerHTML出力なのに拒否された（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系10: 外部入力へアクセスするが検証の記述が無い → 拒否（入力の検証を境界で行う）
  local t10='app.post("/users", function (req, res) {
  const name = req.body.name;
  createUser(name);
});'
  if msg="$(judge "app.js" "$t10")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF "入力の検証を境界で行う"; then
    echo "  [PASS] 系10: 検証なしの外部入力アクセスは拒否される（${msg}）"
  else
    echo "  [FAIL] 系10: 検証なしの外部入力アクセスなのに拒否されない、または規則名不一致（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系11: 外部入力へアクセスし、スキーマ検証を経てから使う → 許可
  local t11='app.post("/users", function (req, res) {
  const parsed = userSchema.validate(req.body);
  createUser(parsed.name);
});'
  if msg="$(judge "app.js" "$t11")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系11: 検証ありの外部入力アクセスは許可される（${msg}）"
  else
    echo "  [FAIL] 系11: 検証ありの外部入力アクセスなのに拒否された（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系12: CI設定ファイルで依存脆弱性検査はあるが週次cronが無い → 拒否
  local t12='name: security
on:
  push:
jobs:
  audit:
    steps:
      - run: npm audit'
  if msg="$(judge ".github/workflows/security.yml" "$t12")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF "依存の脆弱性を決めた間隔で確かめる"; then
    echo "  [PASS] 系12: 週次cronなしの依存脆弱性検査は拒否される（${msg}）"
  else
    echo "  [FAIL] 系12: 週次cronなしの依存脆弱性検査なのに拒否されない、または規則名不一致（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系13: CI設定ファイルで依存脆弱性検査に週次cronが指定されている → 許可
  local t13='name: security
on:
  schedule:
    - cron: "0 0 * * 0"
jobs:
  audit:
    steps:
      - run: npm audit'
  if msg="$(judge ".github/workflows/security.yml" "$t13")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系13: 週次cron指定ありの依存脆弱性検査は許可される（${msg}）"
  else
    echo "  [FAIL] 系13: 週次cron指定ありなのに拒否された（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系14: 処理の入口らしい記述が無い → 対象外（権限の確認を処理の側で行う）
  local tmp14
  if ! tmp14="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-literal-in-code-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp14" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  local t14='function add(a, b) { return a + b; }'
  if msg="$(judge "app.js" "$t14" "$tmp14")"; then code=0; else code=$?; fi
  rm -rf "$tmp14"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '対象外[権限の確認を処理の側で行う]'; then
    echo "  [PASS] 系14: 処理の入口らしい記述が無ければ「権限の確認を処理の側で行う」は対象外になる（${msg}）"
  else
    echo "  [FAIL] 系14: 対象外にならない、または規則名が含まれない（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系15: 処理の入口はあるが権限の確認の宣言が無い → 通知（権限の確認を処理の側で行う）
  local tmp15
  if ! tmp15="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-literal-in-code-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp15" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  local t15='app.get("/admin", function (req, res) { res.send("ok"); });'
  if msg="$(judge "app.js" "$t15" "$tmp15")"; then code=0; else code=$?; fi
  rm -rf "$tmp15"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '通知[権限の確認を処理の側で行う]'; then
    echo "  [PASS] 系15: 宣言が無ければ「権限の確認を処理の側で行う」は通知にとどまる（${msg}）"
  else
    echo "  [FAIL] 系15: 宣言が無いのに判定された、または規則名が含まれない（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系16: 宣言はあるが権限の確認の呼び出しが処理の入口に無い → 拒否（権限の確認を処理の側で行う）
  local tmp16
  if ! tmp16="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-literal-in-code-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp16" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  mkdir -p "$tmp16/docs/rules/security/permission-check"
  cat > "$tmp16/docs/rules/security/permission-check/rule.md" <<'EOF'
# セキュリティ要件

## このプロジェクトの規則

| 規則 | 内容 | 検査 |
|---|---|---|
| 権限の確認を処理の側で行う | 権限の確認は requirePermission を呼ぶ | 静的解析 |
EOF
  local t16='app.get("/admin", function (req, res) { res.send("ok"); });'
  if msg="$(judge "app.js" "$t16" "$tmp16")"; then code=0; else code=$?; fi
  rm -rf "$tmp16"
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '拒否[権限の確認を処理の側で行う]'; then
    echo "  [PASS] 系16: 権限の確認が無い処理の入口は拒否される（${msg}）"
  else
    echo "  [FAIL] 系16: 権限の確認が無いのに許可、または規則名が含まれない（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系17: 宣言があり権限の確認の呼び出しが処理の入口にある → 許可（権限の確認を処理の側で行う）
  local tmp17
  if ! tmp17="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-literal-in-code-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp17" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  mkdir -p "$tmp17/docs/rules/security/permission-check"
  cat > "$tmp17/docs/rules/security/permission-check/rule.md" <<'EOF'
# セキュリティ要件

## このプロジェクトの規則

| 規則 | 内容 | 検査 |
|---|---|---|
| 権限の確認を処理の側で行う | 権限の確認は requirePermission を呼ぶ | 静的解析 |
EOF
  local t17='app.get("/admin", requirePermission("admin"), function (req, res) { res.send("ok"); });'
  if msg="$(judge "app.js" "$t17" "$tmp17")"; then code=0; else code=$?; fi
  rm -rf "$tmp17"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '許可[権限の確認を処理の側で行う]'; then
    echo "  [PASS] 系17: 権限の確認がある処理の入口は許可される（${msg}）"
  else
    echo "  [FAIL] 系17: 権限の確認があるのに拒否、または規則名が含まれない（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系18: 環境変数に理由を書けば skip する
  local skip_msg18
  if skip_msg18="$(SECRET_LITERAL_IN_CODE_SKIP_REASON="点検済みのため" should_skip_with_reason)"; then
    if printf '%s' "$skip_msg18" | grep -qF "SECRET-LITERAL-IN-CODE-SKIP" && printf '%s' "$skip_msg18" | grep -qF "点検済みのため"; then
      echo "  [PASS] 系18: 理由付きの環境変数で skip される（${skip_msg18}）"
    else
      echo "  [FAIL] 系18: skip はされたがタグまたは理由が含まれない（${skip_msg18}）" >&2
      rc=1
    fi
  else
    echo "  [FAIL] 系18: 理由付きの環境変数なのに skip されない" >&2
    rc=1
  fi

  # 系19: 環境変数が空なら skip しない
  local skip_code19
  if SECRET_LITERAL_IN_CODE_SKIP_REASON="" should_skip_with_reason >/dev/null 2>&1; then skip_code19=0; else skip_code19=$?; fi
  if [ "$skip_code19" -eq 1 ]; then
    echo "  [PASS] 系19: 環境変数が空なら skip されない"
  else
    echo "  [FAIL] 系19: 環境変数が空なのに skip された（exit=${skip_code19}）" >&2
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
