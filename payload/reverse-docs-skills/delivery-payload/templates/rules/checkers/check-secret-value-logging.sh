#!/usr/bin/env bash
# check-secret-value-logging.sh — 記録と監視の決まりの linter
#
# timing: PreToolUse(Write)
# 対象規約: 記録と監視の決まり（tool-defined/observability.md）
#
# 検査する規則（検査列に「静的解析」を含むもの、7件すべてを実装）:
#   1. 記録の形式を1つに揃える
#   2. 記録に追跡の鍵を含める
#   3. 秘密の値と個人の情報を記録しない
#   4. 記録の水準を使い分ける
#   5. 監視する指標を先に決める
#   6. 知らせる条件と宛先を決める
#   7. 操作の記録を残す
#
# 判定（規則ごと）:
#   1. 記録の形式を1つに揃える:
#      水準付きのログ呼び出し（logger.info( 等）と、水準を持たない直接の
#      書き出し（console.log( / print( / System.out.println( 等）が同じ
#      本文内に混在していれば、共通の出力口を経ない直接の書き出しがあると
#      みなし違反とする。
#   2. 記録に追跡の鍵を含める:
#      本文に記録の出力の呼び出し（既存の LOG_RE）が1件も無ければ対象外と
#      する。あれば cwd 配下の docs/rules/**/rule.md の「## このプロジェクトの
#      規則」表から、規則名「記録に追跡の鍵を含める」の宣言（追跡の鍵の名前）
#      を引く。宣言が無ければ判定せず通知にとどめる。宣言があれば、その内容
#      から英字で始まり英数字とアンダースコアが続く3文字以上の語を1つ取り出し
#      （最初に一致したもの）、本文にその語が含まれているかを走査する。
#   3. 秘密の値と個人の情報を記録しない（既存）:
#      ログ出力の呼び出しと秘密の値らしい識別子が同じ行に現れれば違反とする。
#   4. 記録の水準を使い分ける:
#      水準付きのログ呼び出しが本文内にあるのに、水準を指定しない汎用の
#      呼び出し（logger.log( や単体の log( ）も本文内にあれば違反とする
#      （水準付きの API が使える環境で、水準の無い呼び出しを使っている
#      ことが本文内の証拠から確認できる場合に限定する）。
#   7. 操作の記録を残す:
#      権限の変更・削除・設定変更らしい記述（DELETE FROM / .destroy( /
#      .remove( / .delete( / DROP TABLE / setRole( / chmod 等）が本文にあり、
#      かつ本文全体に記録の出力らしい記述（logger. / log. / console.log( /
#      audit 等）が1つも無ければ違反とする。
#   5. 監視する指標を先に決める:
#      cwd 配下（.git 配下を除く）をファイル名で走査し、名前に「監視」を
#      含む文書（監視の設定ファイル）を探す。見つからなければ対象外。
#      見つかった場合、中身に指標を示す語（指標 / metric）が1つも無ければ
#      違反とする。
#   6. 知らせる条件と宛先を決める:
#      5と同じ監視の設定ファイルを対象に、通知の条件を示す語（条件 /
#      しきい値 / threshold）と、宛先を示す語（宛先 / 通知先 / channel /
#      email / webhook）の両方が揃っていなければ違反とする。
#
# 対象ファイル:
#   拡張子がコードファイルらしいもの（.js/.jsx/.ts/.tsx/.py/.java/.go/.rb/.php/
#   .cs/.kt/.swift）に限定する。Markdown 等の説明文書でこの語を地の文として
#   使う場合の誤検知を避けるため。1・3・4・7の4規則はいずれもこの
#   コードファイル判定を前提とする。2は本文に記録の出力の呼び出しがあるかで
#   判定するため拡張子には依存しない。5・6は書き込み対象ファイルの拡張子に
#   依存しない（監視の設定ファイルという別文書の実在・内容を検査するため）。
#
# 判定の設計:
#   1・4は「水準付きのログ呼び出しが存在する（＝水準付きの API が使える）のに
#   水準を持たない呼び出しも使っている」という本文内で完結する矛盾のみを見る。
#   水準付きの呼び出しが1つも無い場合は判定しない（水準付きの API 自体が
#   使えない環境かどうかを本文だけでは判断できないため、誤検出を避ける側に
#   倒す）。7は、破壊的操作・権限変更の記述と記録出力の記述の共起を本文全体
#   から探す（近傍窓ではなく本文全体を見る。監査記録は呼び出しの直後ではなく
#   関数の別の場所や共通処理側に書かれることが多いため）。
#   2は、対象プロジェクトごとに追跡の鍵の名前が異なるため、ファイルパスでは
#   なく cwd 配下の docs/rules/**/rule.md の宣言（リバース解析が起こした
#   「このプロジェクトの規則」）を仲立ちにする。宣言が無ければ判定せず通知に
#   とどめ、宣言があれば本文にその鍵の名前が含まれているかを走査する。
#   5・6は検査列が「監視の設定ファイルが実在し」「監視の設定に…登録
#   されているか」であり、書き込み対象ファイルの本文ではなく別文書の存在
#   確認を求めるため、ファイル名で対象文書を探す方式を取る
#   （check-doc-heading-addendum.sh と同じ考え方）。文書が無い場合を違反として
#   block すると「まだ用意していないだけ」を止めてしまうため、見つからない
#   場合は対象外として素通しし、見つかった場合にのみ中身を検査する。
#
# 除外条件（誤検知回避）:
#   - tool_name が Write 以外 → 対象外（Edit は差分のみで全文を持たないため対象外）
#   - file_path の拡張子がコードファイル一覧に無い → 1・3・4・7 は対象外
#   - 各規則の判定条件を満たさない → 対象外
#   - 2: 本文に記録の出力の呼び出しが無い → 対象外。cwd 配下の docs/rules/**/
#     rule.md に「記録に追跡の鍵を含める」の宣言が無い → 判定せず通知に
#     とどめる
#   - 5・6: cwd が空・存在しない → 対象外（fail-open）。「監視」を含む文書が
#     見当たらない → 対象外（見つかった場合のみ中身を検査する）
#
# 既知の限界:
#   - 3: 同一行での文字列共起のみを見るため、変数名や文字列リテラルとして秘密語彙を
#     含むが実際には秘密の値を渡していない行（例: エラーメッセージの説明文）も
#     誤検知しうる。逆に複数行にまたがる呼び出しは検出できない
#   - 1・4: 水準付きの呼び出しが1件も無い本文（例: console.log のみで構成された
#     小さなスクリプト）は判定対象にならない（誤検出回避を優先した設計上の割り切り）
#   - 7: 記録出力の記述が本文のどこかにありさえすれば許可するため、実際にその
#     破壊的操作の直後に記録しているかまでは確認しない
#   - 対象外拡張子のファイル・コメント行中の言及は、各規則の呼び出し語彙自体が
#     出現しない限り検出対象にならない
#   - 5・6: ファイル名に「監視」を含む最初の1件のみを見る。指標・条件・宛先の
#     語がその文書の中に存在するかという近似判定であり、実際に監視の仕組みへ
#     登録されているかまでは確認しない
#   - 2: 宣言から値を取り出す方式は、宣言が自由な文章のため最初に一致した
#     1つだけを見る。本文にその名前の鍵が含まれているかしか見ないため、
#     実際にログ出力の引数として渡されているかまでは確認しない
#
# 使い方:
#   フック本体として: PreToolUse(Write) の入力 JSON を stdin から受け取る
#   単体実行: check-secret-value-logging.sh --self-test
#
# 止めるか知らせるか:
#   記録の形式を1つに揃える: 止める（形式の混在は放置すると記録の集計・調査が阻害されるため）
#   記録に追跡の鍵を含める: 止める（追跡の鍵がない記録は障害調査時に原因追跡ができなくなるため）
#   秘密の値と個人の情報を記録しない: 止める（記録に残った秘密の値・個人情報は記録基盤から消せない実害につながるため）
#   記録の水準を使い分ける: 止める（水準の混在は重大度の判断を誤らせ対応の遅れという実害につながるため）
#   監視する指標を先に決める: 止める（指標のない監視設定は異常の検知漏れという取り消せない実害につながるため）
#   知らせる条件と宛先を決める: 止める（通知の条件・宛先がない監視は異常を検知しても届かず対応が遅れるため）
#   操作の記録を残す: 止める（記録のない破壊的操作は事後に何が起きたか追跡できなくなるため）
#
# 逃げ道:
#   SECRET_VALUE_LOGGING_SKIP_REASON に理由を書けば通る。理由が空の場合は通らない
#   秘密の値を扱う検査のため、通過した記録は必ず標準エラーへ残る
set -uo pipefail
export LC_ALL=C

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${SECRET_VALUE_LOGGING_SKIP_REASON:-}" ]; then
    echo "[SECRET-VALUE-LOGGING-SKIP] 理由: ${SECRET_VALUE_LOGGING_SKIP_REASON}"
    return 0
  fi
  return 1
}

LOG_RE='(console\.(log|error|warn|info|debug)|logger\.(info|debug|warn|error|trace)|log\.(info|debug|warn|error)|System\.out\.println|System\.err\.println|print\()'
SECRET_RE='(password|passwd|secret|token|api[_-]?key|credential|private[_-]?key|ssn)'

LEVELED_RE='(logger\.(info|debug|warn|error|trace)\(|log\.(info|debug|warn|error)\()'
RAW_RE='(console\.log\(|print\(|System\.out\.println\()'
GENERIC_RE='(logger\.log\(|\blog\()'

DESTRUCTIVE_RE='(DELETE[[:space:]]+FROM[[:space:]]|\.destroy\(|\.remove\(|\.delete\(|DROP[[:space:]]+TABLE[[:space:]]|setRole\(|chmod[[:space:]])'
AUDIT_RE='(audit|logger\.|log\.(info|warn|error|debug)\(|console\.log\()'

MONITOR_DOC_NEEDLE='監視'
METRIC_RE='(指標|metric)'
NOTIFY_COND_RE='(条件|しきい値|threshold)'
NOTIFY_DEST_RE='(宛先|通知先|channel|email|webhook)'

is_code_ext() {
  case "$1" in
    *.js|*.jsx|*.ts|*.tsx|*.py|*.java|*.go|*.rb|*.php|*.cs|*.kt|*.swift) return 0 ;;
    *) return 1 ;;
  esac
}

# 指定した cwd 配下（.git 配下を除く）から、ファイル名に needle を含む
# 最初のファイルを返す。見つからなければ空を返す
find_doc_by_name() {
  local cwd="$1" needle="$2"
  if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
    return 0
  fi
  find "$cwd" -type f -not -path '*/.git/*' -name "*${needle}*" 2>/dev/null | head -1
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

# 「記録に追跡の鍵を含める」規則の判定
judge_trace_key() {
  # $1: cwd, $2: file_path, $3: content
  local cwd="$1" file_path="$2" content="$3"

  if ! printf '%s' "$content" | grep -qE -- "$LOG_RE" 2>/dev/null; then
    echo "対象外[記録に追跡の鍵を含める]: 記録の出力の呼び出しが見当たりません"
    return 0
  fi

  local override
  override="$(lookup_project_override_content "$cwd" "記録に追跡の鍵を含める")"
  if [ -z "$override" ]; then
    echo "通知[記録に追跡の鍵を含める]: このプロジェクトの規則に追跡の鍵の宣言がないため判定していません。リバース解析を実行すると判定の対象になります"
    return 0
  fi

  local key
  key="$(printf '%s' "$override" | grep -oE '[A-Za-z][A-Za-z0-9_]{2,}' | head -1)"
  if [ -z "$key" ]; then
    echo "通知[記録に追跡の鍵を含める]: このプロジェクトの規則に宣言はありますが、追跡の鍵の名前を読み取れません"
    return 0
  fi

  if ! printf '%s' "$content" | grep -qF -- "$key" 2>/dev/null; then
    echo "拒否[記録に追跡の鍵を含める]: 記録の出力がありますが、追跡の鍵（${key}）が見当たりません"
    return 2
  fi

  echo "許可[記録に追跡の鍵を含める]: 記録の出力に追跡の鍵（${key}）があります"
  return 0
}

judge() {
  # $1: file_path, $2: content, $3: cwd（省略可。省略時は規則2・5・6を対象外として扱う）
  local file_path="$1" content="$2" cwd="${3:-}"

  if [ -n "$cwd" ]; then
    local tk_msg tk_code
    if tk_msg="$(judge_trace_key "$cwd" "$file_path" "$content")"; then tk_code=0; else tk_code=$?; fi
    if [ "$tk_code" -eq 2 ]; then
      echo "$tk_msg"
      return 2
    fi
    echo "$tk_msg"
  fi

  if is_code_ext "$file_path"; then
    local hit
    hit=$(printf '%s\n' "$content" | grep -nE "$LOG_RE" 2>/dev/null | grep -E "$SECRET_RE" 2>/dev/null | head -1)

    if [ -n "$hit" ]; then
      echo "拒否[秘密の値と個人の情報を記録しない]: ログ出力の行に秘密の値らしい識別子が渡されています（${hit}）"
      return 2
    fi

    local has_leveled=0
    printf '%s' "$content" | grep -qE -- "$LEVELED_RE" && has_leveled=1

    # 規則: 記録の形式を1つに揃える
    if [ "$has_leveled" -eq 1 ] && printf '%s' "$content" | grep -qE -- "$RAW_RE"; then
      echo "拒否[記録の形式を1つに揃える]: 水準付きのログ呼び出しと共通の出力口を経ない直接の書き出しが混在しています"
      return 2
    fi

    # 規則: 記録の水準を使い分ける
    if [ "$has_leveled" -eq 1 ] && printf '%s' "$content" | grep -qE -- "$GENERIC_RE"; then
      echo "拒否[記録の水準を使い分ける]: 水準付きの呼び出しが使えるのに水準を指定しない呼び出しも使われています"
      return 2
    fi

    # 規則: 操作の記録を残す
    if printf '%s' "$content" | grep -qE -- "$DESTRUCTIVE_RE" && ! printf '%s' "$content" | grep -qEi -- "$AUDIT_RE"; then
      echo "拒否[操作の記録を残す]: 削除・権限変更・設定変更らしい記述があるが記録の出力が見当たりません"
      return 2
    fi
  fi

  # 規則: 監視する指標を先に決める／知らせる条件と宛先を決める
  local monitor_doc
  monitor_doc="$(find_doc_by_name "$cwd" "$MONITOR_DOC_NEEDLE")"
  if [ -n "$monitor_doc" ]; then
    local monitor_content relpath
    monitor_content="$(cat "$monitor_doc" 2>/dev/null)"
    relpath="${monitor_doc#"$cwd"/}"

    if ! printf '%s' "$monitor_content" | grep -qE -- "$METRIC_RE"; then
      echo "拒否[監視する指標を先に決める]: 監視の設定ファイル（${relpath}）は実在するが、指標の記述が見当たりません"
      return 2
    fi

    if ! printf '%s' "$monitor_content" | grep -qE -- "$NOTIFY_COND_RE" || ! printf '%s' "$monitor_content" | grep -qE -- "$NOTIFY_DEST_RE"; then
      echo "拒否[知らせる条件と宛先を決める]: 監視の設定ファイル（${relpath}）は実在するが、通知の条件または宛先の記述が見当たりません"
      return 2
    fi
  fi

  echo "許可: 記録と監視の決まりの違反は検出されませんでした"
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
  [ "$tool" != "Write" ] && exit 0

  local file_path content cwd
  file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
  [ -z "$file_path" ] && exit 0
  content=$(printf '%s' "$input" | jq -r '.tool_input.content // empty' 2>/dev/null)
  [ -z "$content" ] && exit 0
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)

  local msg code
  if msg="$(judge "$file_path" "$content" "$cwd")"; then code=0; else code=$?; fi

  [ "$code" -eq 0 ] && exit 0

  ctx="[SECRET-VALUE-LOGGING-BLOCK] ${msg}。秘密の値をログへ渡さないよう修正してから再実行してください。"
  jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  printf '%s\n' "$ctx" >&2
  exit 2
}

self_test() {
  local rc=0 msg code

  # 系1: ログ呼び出し + password を同一行で渡す → 拒否
  local c1='function login(user) {
  logger.info(user.password);
}'
  if msg="$(judge "app.js" "$c1")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF "秘密の値と個人の情報を記録しない"; then
    echo "  [PASS] 系1: logger.info(password) は拒否される（${msg}）"
  else
    echo "  [FAIL] 系1: 秘密の値の記録なのに拒否されない、または規則名不一致（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系2: console.log + token を同一行で渡す → 拒否
  local c2='console.log("token=" + apiToken);'
  if msg="$(judge "auth.ts" "$c2")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF "秘密の値と個人の情報を記録しない"; then
    echo "  [PASS] 系2: console.log(apiToken) は拒否される（${msg}）"
  else
    echo "  [FAIL] 系2: 秘密の値の記録なのに拒否されない、または規則名不一致（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系3（近傍事例）: ログ呼び出しを伴わないコメントでの言及 → 対象外として許可
  local c3='// TODO: never log the password field directly
function login() {}'
  if msg="$(judge "app.js" "$c3")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系3: ログ呼び出しを伴わないコメント言及は許可される（${msg}）"
  else
    echo "  [FAIL] 系3: ログ呼び出しが無いのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系4: コードファイルの拡張子ではない（.md） → 対象外として許可
  local c4='logger.info(user.password);'
  if msg="$(judge "docs/note.md" "$c4")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系4: コードファイル以外は対象外として許可される（${msg}）"
  else
    echo "  [FAIL] 系4: コードファイル以外なのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系5（近傍事例）: ログ呼び出しはあるが秘密語彙を含まない → 許可
  local c5='console.log(username);'
  if msg="$(judge "app.js" "$c5")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系5: 秘密語彙を含まないログ出力は許可される（${msg}）"
  else
    echo "  [FAIL] 系5: 秘密語彙が無いのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系6: 水準付きログと共通の出力口を経ない直接の書き出しが混在 → 拒否（記録の形式を1つに揃える）
  local c6='function start() {
  logger.info("service started");
  console.log("debug details");
}'
  if msg="$(judge "app.js" "$c6")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF "記録の形式を1つに揃える"; then
    echo "  [PASS] 系6: logger.infoとconsole.logの混在は拒否される（${msg}）"
  else
    echo "  [FAIL] 系6: logger.infoとconsole.logの混在なのに拒否されない、または規則名不一致（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系7: 水準付きログのみで統一されている → 許可
  local c7='function start() {
  logger.info("service started");
  logger.warn("low disk");
}'
  if msg="$(judge "app.js" "$c7")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系7: 水準付きログのみの記録形式は許可される（${msg}）"
  else
    echo "  [FAIL] 系7: 水準付きログのみなのに拒否された（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系8: 水準付きログが使えるのに水準の無い汎用呼び出しも使っている → 拒否（記録の水準を使い分ける）
  local c8='function start() {
  logger.info("service started");
  logger.log("misc");
}'
  if msg="$(judge "app.js" "$c8")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF "記録の水準を使い分ける"; then
    echo "  [PASS] 系8: logger.logの混在は拒否される（${msg}）"
  else
    echo "  [FAIL] 系8: logger.logの混在なのに拒否されない、または規則名不一致（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系9: 水準の指定が無い呼び出しが1つも無い → 許可（系7と同一データで水準使い分けの許可も確認）
  local c9='function start() {
  logger.error("failure");
  logger.debug("trace");
}'
  if msg="$(judge "app.js" "$c9")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系9: 水準付きログの使い分けは許可される（${msg}）"
  else
    echo "  [FAIL] 系9: 水準付きログの使い分けなのに拒否された（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系10: 削除処理があるが記録の出力が無い → 拒否（操作の記録を残す）
  local c10='function deleteUser(id) {
  db.query("DELETE FROM users WHERE id = ?", [id]);
}'
  if msg="$(judge "app.js" "$c10")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF "操作の記録を残す"; then
    echo "  [PASS] 系10: 記録の無い削除処理は拒否される（${msg}）"
  else
    echo "  [FAIL] 系10: 記録の無い削除処理なのに拒否されない、または規則名不一致（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系11: 削除処理の記録を残している → 許可
  local c11='function deleteUser(id, actor) {
  logger.info("user " + actor + " deleted " + id);
  db.query("DELETE FROM users WHERE id = ?", [id]);
}'
  if msg="$(judge "app.js" "$c11")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系11: 記録のある削除処理は許可される（${msg}）"
  else
    echo "  [FAIL] 系11: 記録のある削除処理なのに拒否された（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系12: 監視の設定ファイルが cwd に無い → 対象外として許可
  local tmp12
  if ! tmp12="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-value-logging-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp12" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  mkdir -p "$tmp12/docs"
  printf '# メモ\n' > "$tmp12/docs/メモ.md"
  if msg="$(judge "app.js" "$c5" "$tmp12")"; then code=0; else code=$?; fi
  rm -rf "$tmp12"
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系12: 監視の設定ファイルが見当たらなければ対象外として許可される（${msg}）"
  else
    echo "  [FAIL] 系12: 監視の設定ファイルが無いのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系13: 監視の設定ファイルは実在するが指標の記述が無い → 拒否（監視する指標を先に決める）
  local tmp13
  if ! tmp13="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-value-logging-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp13" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  mkdir -p "$tmp13/docs"
  printf '# 監視設定\n\n通知先: ops@example.com\n' > "$tmp13/docs/監視設定.md"
  if msg="$(judge "app.js" "$c5" "$tmp13")"; then code=0; else code=$?; fi
  rm -rf "$tmp13"
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF "監視する指標を先に決める"; then
    echo "  [PASS] 系13: 指標の記述が無い監視設定は拒否される（${msg}）"
  else
    echo "  [FAIL] 系13: 指標の記述が無いのに許可、または規則名不一致（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系14: 監視の設定ファイルに指標はあるが通知の条件・宛先が無い → 拒否（知らせる条件と宛先を決める）
  local tmp14
  if ! tmp14="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-value-logging-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp14" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  mkdir -p "$tmp14/docs"
  printf '# 監視設定\n\n指標: CPU使用率\n' > "$tmp14/docs/監視設定.md"
  if msg="$(judge "app.js" "$c5" "$tmp14")"; then code=0; else code=$?; fi
  rm -rf "$tmp14"
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF "知らせる条件と宛先を決める"; then
    echo "  [PASS] 系14: 通知の条件・宛先が無い監視設定は拒否される（${msg}）"
  else
    echo "  [FAIL] 系14: 通知の条件・宛先が無いのに許可、または規則名不一致（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系15: 監視の設定ファイルに指標・通知の条件・宛先がすべて揃っている → 許可
  local tmp15
  if ! tmp15="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-value-logging-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp15" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  mkdir -p "$tmp15/docs"
  printf '# 監視設定\n\n指標: CPU使用率\nしきい値: 80%%\n宛先: ops@example.com\n' > "$tmp15/docs/監視設定.md"
  if msg="$(judge "app.js" "$c5" "$tmp15")"; then code=0; else code=$?; fi
  rm -rf "$tmp15"
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系15: 指標・条件・宛先が揃った監視設定は許可される（${msg}）"
  else
    echo "  [FAIL] 系15: 指標・条件・宛先が揃っているのに拒否された（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系16: 記録の出力の呼び出しが無い → 対象外（記録に追跡の鍵を含める）
  local tmp16
  if ! tmp16="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-value-logging-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp16" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  local c16='function add(a, b) { return a + b; }'
  if msg="$(judge "app.js" "$c16" "$tmp16")"; then code=0; else code=$?; fi
  rm -rf "$tmp16"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '対象外[記録に追跡の鍵を含める]'; then
    echo "  [PASS] 系16: 記録の出力の呼び出しが無ければ「記録に追跡の鍵を含める」は対象外になる（${msg}）"
  else
    echo "  [FAIL] 系16: 対象外にならない、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系17: 記録の出力はあるが追跡の鍵の宣言が無い → 通知（記録に追跡の鍵を含める）
  local tmp17
  if ! tmp17="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-value-logging-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp17" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  local c17='logger.info("service started");'
  if msg="$(judge "app.js" "$c17" "$tmp17")"; then code=0; else code=$?; fi
  rm -rf "$tmp17"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '通知[記録に追跡の鍵を含める]'; then
    echo "  [PASS] 系17: 宣言が無ければ「記録に追跡の鍵を含める」は通知にとどまる（${msg}）"
  else
    echo "  [FAIL] 系17: 宣言が無いのに判定された、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系18: 宣言はあるが追跡の鍵が記録の出力に含まれない → 拒否（記録に追跡の鍵を含める）
  local tmp18
  if ! tmp18="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-value-logging-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp18" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  mkdir -p "$tmp18/docs/rules/observability/trace-key"
  cat > "$tmp18/docs/rules/observability/trace-key/rule.md" <<'EOF'
# 監視要件

## このプロジェクトの規則

| 規則 | 内容 | 検査 |
|---|---|---|
| 記録に追跡の鍵を含める | 追跡の鍵は requestId とする | 静的解析 |
EOF
  local c18='logger.info("service started");'
  if msg="$(judge "app.js" "$c18" "$tmp18")"; then code=0; else code=$?; fi
  rm -rf "$tmp18"
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '拒否[記録に追跡の鍵を含める]'; then
    echo "  [PASS] 系18: 追跡の鍵が無い記録出力は拒否される（${msg}）"
  else
    echo "  [FAIL] 系18: 追跡の鍵が無いのに許可、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系19: 宣言があり追跡の鍵が記録の出力に含まれる → 許可（記録に追跡の鍵を含める）
  local tmp19
  if ! tmp19="$(mktemp -d "${TMPDIR:-/tmp}/check-secret-value-logging-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp19" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  mkdir -p "$tmp19/docs/rules/observability/trace-key"
  cat > "$tmp19/docs/rules/observability/trace-key/rule.md" <<'EOF'
# 監視要件

## このプロジェクトの規則

| 規則 | 内容 | 検査 |
|---|---|---|
| 記録に追跡の鍵を含める | 追跡の鍵は requestId とする | 静的解析 |
EOF
  local c19='logger.info("request " + requestId + " started");'
  if msg="$(judge "app.js" "$c19" "$tmp19")"; then code=0; else code=$?; fi
  rm -rf "$tmp19"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '許可[記録に追跡の鍵を含める]'; then
    echo "  [PASS] 系19: 追跡の鍵を含む記録出力は許可される（${msg}）"
  else
    echo "  [FAIL] 系19: 追跡の鍵を含むのに拒否、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系20: 環境変数に理由を書けば skip する
  local skip_msg20
  if skip_msg20="$(SECRET_VALUE_LOGGING_SKIP_REASON="点検済みのため" should_skip_with_reason)"; then
    if printf '%s' "$skip_msg20" | grep -qF "SECRET-VALUE-LOGGING-SKIP" && printf '%s' "$skip_msg20" | grep -qF "点検済みのため"; then
      echo "  [PASS] 系20: 理由付きの環境変数で skip される（${skip_msg20}）"
    else
      echo "  [FAIL] 系20: skip はされたがタグまたは理由が含まれない（${skip_msg20}）" >&2
      rc=1
    fi
  else
    echo "  [FAIL] 系20: 理由付きの環境変数なのに skip されない" >&2
    rc=1
  fi

  # 系21: 環境変数が空なら skip しない
  local skip_code21
  if SECRET_VALUE_LOGGING_SKIP_REASON="" should_skip_with_reason >/dev/null 2>&1; then skip_code21=0; else skip_code21=$?; fi
  if [ "$skip_code21" -eq 1 ]; then
    echo "  [PASS] 系21: 環境変数が空なら skip されない"
  else
    echo "  [FAIL] 系21: 環境変数が空なのに skip された（exit=${skip_code21}）" >&2
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
