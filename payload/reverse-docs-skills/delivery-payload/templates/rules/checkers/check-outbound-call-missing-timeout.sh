#!/usr/bin/env bash
# check-outbound-call-missing-timeout.sh — 稼働を続けることと復旧の決まりの linter
#
# timing: PreToolUse(Write|Edit)
# 対象規約: 稼働を続けることと復旧の決まり（tool-defined/availability.md）
#
# 検査する規則（検査列に「静的解析」を含むもの、4件すべてを検査する）:
#   1. 稼働の目標を数値で決める
#   2. 復旧の目標を2つ決める
#   3. 外部への依存に失敗時の扱いを持たせる
#   4. 復旧の手順を書いて試す
#
# 判定（規則ごと）:
#   1. 稼働の目標を数値で決める:
#      本文に「稼働率」または「可用性」と「目標」の組み合わせ（話題）が
#      現れているのに、パーセント表記（例: 99.9%）が本文全体に1つも
#      無ければ違反とする。話題が無ければ対象外とする。
#   2. 復旧の目標を2つ決める:
#      本文に「復旧」と「目標」の組み合わせ（話題）が現れているのに、
#      復旧時間側の語（RTO / 復旧時間 / 復旧までの時間）と、データ損失側の
#      語（RPO / データ損失 / 失ってよいデータ / バックアップの間隔）の
#      両方が揃っていなければ違反とする。話題が無ければ対象外とする。
#   3. 外部への依存に失敗時の扱いを持たせる（既存）:
#      外部への通信呼び出しらしい記述（fetch( / axios. / requests.get( 等）
#      を含む行の前後2行（計5行）に "timeout" の語が無ければ違反とする。
#   4. 復旧の手順を書いて試す:
#      cwd 配下（.git 配下を除く）をファイル名で走査し、名前に「復旧」を
#      含む文書を探す。見つからなければ対象外（その文書がまだ無いだけかも
#      しれないため、素通しする）。見つかった場合は中身を検査し、番号付き
#      箇条書き・記号付き箇条書きなど手順らしい記述（例: "1. " "- "）が
#      1つも無ければ違反とする（実在するだけで手順の記述が無い、実質的な
#      空文書を検出する）。
#
# 判定の設計:
#   1・2は、稼働・復旧の目標という話題そのものへの言及があった時点で
#   規則の適否を判定する（話題が無い一般のコード片・文書は対象外）。
#   話題の判定はファイルパスに依存せず、本文の語彙のみで行うため、
#   特定の設計文書パスを決め打ちする必要が無い。3は呼び出しの近傍窓で
#   "timeout" の有無を見る（既存の判定をそのまま維持）。
#   4は検査列が「実在するかを走査する」であり本文の内容ではなく別文書の
#   存在確認を求めるため、ファイル名で対象文書を探す方式を取る
#   （check-doc-heading-addendum.sh と同じ考え方）。文書が無い場合を
#   違反として block すると「まだ書いていないだけ」を止めてしまうため、
#   見つからない場合は対象外として素通しし、見つかった場合にのみ中身
#   （手順らしい記述の有無）を検査する。
#
# 対象文書:
#   4は cwd 配下（.git 配下を除く）でファイル名に「復旧」を含む最初の
#   ファイルを対象文書とする。特定のディレクトリ配置を前提にしない。
#
# 除外条件（誤検知回避）:
#   - tool_name が Write / Edit 以外 → 対象外
#   - 本文（content / new_string）が空 → 対象外
#   - 各規則の判定条件を満たさない → 対象外
#   - 4: cwd が空・存在しない → 対象外（fail-open）。「復旧」を含む文書が
#     見当たらない → 対象外（見つかった場合のみ中身を検査する）
#
# 既知の限界:
#   - 3: 近傍窓（前後2行）を超えた位置での指定は検出できない。"timeout" と
#     いう語を使わない独自の待ち時間制御は検出できない
#   - 1・2: 「稼働率」「復旧」等の話題語を含まない書き方（別の言い回し）
#     では検出できない。1はパーセント表記のみを数値目標の根拠とし、
#     計画停止の時間帯まで検証しない
#   - 4: 「実際に試して動くことを確かめる」（テスト部分）は静的解析の
#     対象外であり検査しない。手順らしい記述の有無という近似判定であり、
#     記述されている手順の正しさまでは検証しない。ファイル名に「復旧」を
#     含む最初の1件のみを見る
#   - MultiEdit は対象外（本checkerは Write / Edit のみに対応する）
#
# 使い方:
#   フック本体として: PreToolUse(Write|Edit) の入力 JSON を stdin から受け取る
#   単体実行: check-outbound-call-missing-timeout.sh --self-test
#
# 止めるか知らせるか:
#   稼働の目標を数値で決める: 止める（数値目標を欠いたまま実装が進むと、後から目標を追加しても実装済みのコードの妥当性を遡って検証できないため）
#   復旧の目標を2つ決める: 止める（復旧時間とデータ損失のどちらかを欠いた目標は、後から補っても当時の想定が再現できないため）
#   外部への依存に失敗時の扱いを持たせる: 止める（タイムアウトの無い外部呼び出しが実装に残ると、障害時に無応答のまま張り付く事態を後から防げなくなるため）
#   復旧の手順を書いて試す: 止める（手順の無い復旧文書が実在したまま運用に入ると、実際の障害時に遡って手順を作る猶予がないため）
#
# 逃げ道:
#   OUTBOUND_CALL_MISSING_TIMEOUT_SKIP_REASON に理由を書けば通る。理由が空の場合は通らない
set -uo pipefail

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${OUTBOUND_CALL_MISSING_TIMEOUT_SKIP_REASON:-}" ]; then
    echo "[OUTBOUND-CALL-MISSING-TIMEOUT-SKIP] 理由: ${OUTBOUND_CALL_MISSING_TIMEOUT_SKIP_REASON}"
    return 0
  fi
  return 1
}

CALL_RE='fetch\(|axios\.(get|post|put|delete|patch)?\(|requests\.(get|post|put|delete)\(|http\.(get|request)\(|urlopen\('

AVAIL_TOPIC_RE='稼働率|可用性'
AVAIL_GOAL_RE='目標'
PERCENT_RE='[0-9]+(\.[0-9]+)?[[:space:]]*%'

RECOVERY_TOPIC_RE='復旧'
RTO_RE='RTO|復旧時間|復旧までの時間'
RPO_RE='RPO|データ損失|失ってよいデータ|バックアップの間隔|バックアップ間隔'

RECOVERY_DOC_NEEDLE='復旧'
STEP_LIST_RE='^[[:space:]]*([0-9]+[.)]|[-*・])[[:space:]]'

# 指定した cwd 配下（.git 配下を除く）から、ファイル名に needle を含む
# 最初のファイルを返す。見つからなければ空を返す
find_doc_by_name() {
  local cwd="$1" needle="$2"
  if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
    return 0
  fi
  find "$cwd" -type f -not -path '*/.git/*' -name "*${needle}*" 2>/dev/null | head -1
}

judge() {
  # $1: 本文テキスト, $2: cwd（省略可。省略時は規則4を対象外として扱う）
  # 標準出力: 判定理由。戻り値: 0=許可・2=拒否
  local text="$1" cwd="${2:-}"

  if [ -z "$text" ]; then
    echo "対象外: 本文が空"
    return 0
  fi

  local tmp
  if ! tmp="$(mktemp "${TMPDIR:-/tmp}/check-outbound-call-missing-timeout.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã¡ã¤ã«ã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  printf '%s\n' "$text" > "$tmp"

  local total call_lines
  total=$(wc -l < "$tmp" | tr -d '[:space:]')
  call_lines=$(grep -nE "$CALL_RE" "$tmp" | cut -d: -f1)

  local ln start end has_timeout
  for ln in $call_lines; do
    start=$((ln - 2))
    [ "$start" -lt 1 ] && start=1
    end=$((ln + 2))
    [ "$end" -gt "$total" ] && end="$total"
    has_timeout=$(sed -n "${start},${end}p" "$tmp" | grep -qi 'timeout' && echo yes || echo no)
    if [ "$has_timeout" = "no" ]; then
      echo "拒否[外部への依存に失敗時の扱いを持たせる]: ${ln}行目付近の外部呼び出しに待ち時間の上限（timeout）指定が見当たらない"
      rm -f "$tmp"
      return 2
    fi
  done

  rm -f "$tmp"

  # 規則: 稼働の目標を数値で決める
  if printf '%s' "$text" | grep -qE -- "$AVAIL_TOPIC_RE" && printf '%s' "$text" | grep -qF -- "$AVAIL_GOAL_RE"; then
    if ! printf '%s' "$text" | grep -qE -- "$PERCENT_RE"; then
      echo "拒否[稼働の目標を数値で決める]: 稼働率・可用性の目標の話題はあるがパーセント表記の数値が見当たらない"
      return 2
    fi
  fi

  # 規則: 復旧の目標を2つ決める
  if printf '%s' "$text" | grep -qF -- "$RECOVERY_TOPIC_RE" && printf '%s' "$text" | grep -qF -- "$AVAIL_GOAL_RE"; then
    local has_rto=0 has_rpo=0
    printf '%s' "$text" | grep -qE -- "$RTO_RE" && has_rto=1
    printf '%s' "$text" | grep -qE -- "$RPO_RE" && has_rpo=1
    if [ "$has_rto" -eq 0 ] || [ "$has_rpo" -eq 0 ]; then
      echo "拒否[復旧の目標を2つ決める]: 復旧の目標の話題はあるが復旧時間とデータ損失の両方の記述が揃っていない"
      return 2
    fi
  fi

  # 規則: 復旧の手順を書いて試す
  local recovery_doc
  recovery_doc="$(find_doc_by_name "$cwd" "$RECOVERY_DOC_NEEDLE")"
  if [ -n "$recovery_doc" ]; then
    local recovery_body relpath
    recovery_body="$(cat "$recovery_doc" 2>/dev/null)"
    relpath="${recovery_doc#"$cwd"/}"
    if ! printf '%s\n' "$recovery_body" | grep -qE -- "$STEP_LIST_RE"; then
      echo "拒否[復旧の手順を書いて試す]: 復旧の手順書（${relpath}）は実在するが、番号付き・記号付き箇条書きなど手順らしい記述が見当たらない"
      return 2
    fi
  fi

  echo "許可: 稼働を続けることと復旧の決まりの違反は検出されなかった"
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

  local text cwd
  if [ "$tool" = "Write" ]; then
    text=$(printf '%s' "$input" | jq -r '.tool_input.content // empty' 2>/dev/null)
  else
    text=$(printf '%s' "$input" | jq -r '.tool_input.new_string // empty' 2>/dev/null)
  fi
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)

  local msg code
  if msg="$(judge "$text" "$cwd")"; then code=0; else code=$?; fi

  [ "$code" -eq 0 ] && exit 0

  ctx="[OUTBOUND-CALL-MISSING-TIMEOUT-BLOCK] ${msg}。呼び出しへ待ち時間の上限（timeout）を指定してください。"
  jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  printf '%s\n' "$ctx" >&2
  exit 2
}

self_test() {
  local rc=0 msg code

  # 系1: axios.get( に timeout 指定なし → 拒否
  local t1='async function loadUser(id) {
  const res = await axios.get("/api/users/" + id);
  return res.data;
}'
  if msg="$(judge "$t1")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF "外部への依存に失敗時の扱いを持たせる"; then
    echo "  [PASS] 系1: timeout指定なしのaxios.getは拒否される（${msg}）"
  else
    echo "  [FAIL] 系1: timeout指定なしなのに拒否されない、または規則名不一致（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系2: axios.get( に timeout 指定あり → 許可
  local t2='async function loadUser(id) {
  const res = await axios.get("/api/users/" + id, { timeout: 5000 });
  return res.data;
}'
  if msg="$(judge "$t2")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系2: timeout指定ありは許可される（${msg}）"
  else
    echo "  [FAIL] 系2: timeout指定ありなのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系3: requests.get( に timeout 指定あり（別記法） → 許可
  local t3='def load_user(user_id):
    res = requests.get("/api/users/%s" % user_id, timeout=5)
    return res.json()'
  if msg="$(judge "$t3")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系3: requests.getのtimeout指定は許可される（${msg}）"
  else
    echo "  [FAIL] 系3: timeout指定ありなのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系4: 外部呼び出しが無い通常コード → 許可
  local t4='function add(a, b) {
  return a + b;
}'
  if msg="$(judge "$t4")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系4: 外部呼び出しなしは許可される（${msg}）"
  else
    echo "  [FAIL] 系4: 外部呼び出しがないのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系5: 稼働率の目標の話題があるがパーセント表記が無い → 拒否（稼働の目標を数値で決める）
  local t5='## 非機能要件

可用性の目標を定める。'
  if msg="$(judge "$t5")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF "稼働の目標を数値で決める"; then
    echo "  [PASS] 系5: パーセント表記の無い稼働目標は拒否される（${msg}）"
  else
    echo "  [FAIL] 系5: パーセント表記の無い稼働目標なのに拒否されない、または規則名不一致（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系6: 稼働率の目標をパーセントで示している → 許可
  local t6='## 非機能要件

稼働率の目標は99.9%とする。'
  if msg="$(judge "$t6")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系6: パーセント表記のある稼働目標は許可される（${msg}）"
  else
    echo "  [FAIL] 系6: パーセント表記のある稼働目標なのに拒否された（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系7: 復旧の目標の話題があるが復旧時間の記述しか無い → 拒否（復旧の目標を2つ決める）
  local t7='## 非機能要件

復旧の目標を定める。復旧時間は4時間以内とする。'
  if msg="$(judge "$t7")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF "復旧の目標を2つ決める"; then
    echo "  [PASS] 系7: 復旧時間のみの復旧目標は拒否される（${msg}）"
  else
    echo "  [FAIL] 系7: 復旧時間のみの復旧目標なのに拒否されない、または規則名不一致（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系8: 復旧の目標に復旧時間とデータ損失の両方がある → 許可
  local t8='## 非機能要件

復旧の目標は、復旧時間4時間以内、データ損失は15分以内とする。'
  if msg="$(judge "$t8")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系8: 復旧時間とデータ損失の両方がある復旧目標は許可される（${msg}）"
  else
    echo "  [FAIL] 系8: 復旧時間とデータ損失の両方があるのに拒否された（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系9: 復旧の手順書らしきファイルが cwd に無い → 対象外として許可
  local tmp9
  if ! tmp9="$(mktemp -d "${TMPDIR:-/tmp}/check-outbound-call-missing-timeout-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp9" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  mkdir -p "$tmp9/docs"
  printf '# 障害対応\n\n概要のみ。\n' > "$tmp9/docs/障害対応方針.md"
  if msg="$(judge "$t4" "$tmp9")"; then code=0; else code=$?; fi
  rm -rf "$tmp9"
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系9: 復旧の手順書が見当たらなければ対象外として許可される（${msg}）"
  else
    echo "  [FAIL] 系9: 復旧の手順書が無いのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系10: 復旧の手順書は実在するが手順らしい記述（箇条書き）が無い → 拒否
  local tmp10
  if ! tmp10="$(mktemp -d "${TMPDIR:-/tmp}/check-outbound-call-missing-timeout-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp10" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  mkdir -p "$tmp10/docs"
  printf '# 復旧手順書\n\n未着手。\n' > "$tmp10/docs/復旧手順書.md"
  if msg="$(judge "$t4" "$tmp10")"; then code=0; else code=$?; fi
  rm -rf "$tmp10"
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF "復旧の手順を書いて試す"; then
    echo "  [PASS] 系10: 手順らしい記述の無い復旧手順書は拒否される（${msg}）"
  else
    echo "  [FAIL] 系10: 手順の記述が無いのに許可、または規則名不一致（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系11: 復旧の手順書に番号付きの手順が書かれている → 許可
  local tmp11
  if ! tmp11="$(mktemp -d "${TMPDIR:-/tmp}/check-outbound-call-missing-timeout-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp11" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  mkdir -p "$tmp11/docs"
  printf '# 復旧手順書\n\n1. サービスを停止する\n2. バックアップから復元する\n3. サービスを再開する\n' > "$tmp11/docs/復旧手順書.md"
  if msg="$(judge "$t4" "$tmp11")"; then code=0; else code=$?; fi
  rm -rf "$tmp11"
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系11: 番号付き手順のある復旧手順書は許可される（${msg}）"
  else
    echo "  [FAIL] 系11: 手順が書かれているのに拒否された（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系12: 環境変数に理由を設定 → should_skip_with_reasonが戻り値0でタグと理由を返す
  local out12
  if out12="$(OUTBOUND_CALL_MISSING_TIMEOUT_SKIP_REASON="テスト用の理由" should_skip_with_reason)"; then
    if printf '%s' "$out12" | grep -qF '[OUTBOUND-CALL-MISSING-TIMEOUT-SKIP]' && printf '%s' "$out12" | grep -qF 'テスト用の理由'; then
      echo "  [PASS] 系12: 理由を設定するとタグと理由付きでskipされる（${out12}）"
    else
      echo "  [FAIL] 系12: skipされたがタグまたは理由が出力に含まれない（${out12}）" >&2
      rc=1
    fi
  else
    echo "  [FAIL] 系12: 理由を設定したのにskipされなかった" >&2
    rc=1
  fi

  # 系13: 環境変数が空文字 → should_skip_with_reasonが戻り値1を返す
  if OUTBOUND_CALL_MISSING_TIMEOUT_SKIP_REASON="" should_skip_with_reason >/dev/null 2>&1; then
    echo "  [FAIL] 系13: 空文字なのにskipされた" >&2
    rc=1
  else
    echo "  [PASS] 系13: 環境変数が空文字ならskipされない"
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
