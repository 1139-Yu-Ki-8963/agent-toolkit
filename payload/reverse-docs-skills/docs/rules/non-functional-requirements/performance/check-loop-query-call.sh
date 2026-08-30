#!/usr/bin/env bash
# check-loop-query-call.sh — 応答の速さと処理の量の決まりの linter
#
# timing: PreToolUse(Write|Edit)
# 対象規約: 応答の速さと処理の量の決まり（tool-defined/performance.md）
#
# 検査する規則（検査列に「静的解析」を含むもの、4件すべて）:
#   1. 目標を数値で決める
#   2. 測る条件を目標と一緒に書く
#   3. 繰り返しの中で問い合わせを発行しない
#   4. 大きな結果を一度に返さない
#
# 判定（規則ごと）:
#   1. 目標を数値で決める:
#      本文に性能目標の話題（「性能目標」、または「応答時間」「処理件数」の
#      いずれかと「目標」の組み合わせ）が現れているのに、数値+単位
#      （秒・ミリ秒・ms・件・rps・req 等）の記述が本文全体に1つも無ければ
#      違反とする。話題が無ければ対象外とする。
#   2. 測る条件を目標と一緒に書く:
#      1の話題と数値目標の両方があるのに、測定条件を示す語（同時・環境・
#      ユーザー数・接続数・負荷・台数）が本文全体に1つも無ければ違反とする。
#      話題または数値目標が無ければ対象外とする（1と独立に判定するため、
#      「件数」は話題語と重複するため測定条件語からは除外している）。
#   3. 繰り返しの中で問い合わせを発行しない（既存）:
#      繰り返し構文の開始行（for / while / .forEach( / .map( 等）の直後
#      15行以内に問い合わせ・外部呼び出しらしい記述が現れれば違反とする。
#   4. 大きな結果を一度に返さない:
#      「SELECT * FROM <テーブル>」で WHERE も LIMIT も持たない行、または
#      引数の無い .findAll() の呼び出しがあれば違反とする（上限も絞り込みの
#      条件も無い取得とみなす）。
#
# 判定の設計:
#   1・2は、応答の速さと処理の量の決まりの話題（性能目標という語、または「応答時間」「処理件数」
#   と「目標」の組み合わせ）に言及した時点で規則の適否を判定する。話題への
#   言及が無い一般のコード片は対象外とする。4は、絞り込み（WHERE）または
#   上限（LIMIT）のどちらも持たない SELECT * を明確な違反パターンとし、
#   WHERE を持つ問い合わせは対象から外す（誤検出を避けるための狭い判定）。
#
# 除外条件（誤検知回避）:
#   - tool_name が Write / Edit 以外 → 対象外
#   - 本文（content / new_string）が空 → 対象外
#   - 各規則の判定条件を満たさない → 対象外
#
# 既知の限界:
#   - 3: 近傍窓（15行）を超えた位置の呼び出しは検出できない。ループの外側に
#     ある呼び出しを、行番号が近いという理由で誤検知しうる
#   - 4: WHERE を持つが上限の無い SELECT（大量該当のおそれがある絞り込み）は
#     検出しない（狭い判定を優先した設計上の割り切り）
#   - 1・2: 「性能目標」「応答時間」等の話題語を含まない設計文書の書き方
#     （別の言い回し）では検出できない
#   - MultiEdit は対象外（本checkerは Write / Edit のみに対応する）
#
# 使い方:
#   フック本体として: PreToolUse(Write|Edit) の入力 JSON を stdin から受け取る
#   単体実行: check-loop-query-call.sh --self-test
#
# 止めるか知らせるか:
#   目標を数値で決める: 止める（数値目標を欠いたまま実装が進むと、後から目標を追加しても実装済みのコードの妥当性を遡って検証できないため）
#   測る条件を目標と一緒に書く: 止める（測定条件を欠いた目標値は、後から条件を補っても当時何を測ったかが再現できないため）
#   繰り返しの中で問い合わせを発行しない: 止める（件数に比例する呼び出しが実装へ混入すると、本番で負荷が増えてから遡って直すのは手戻りが大きいため）
#   大きな結果を一度に返さない: 止める（上限のない取得が実装へ混入すると、データ量が増えてから遡って絞り込みを足すのは手戻りが大きいため）
#
# 逃げ道:
#   LOOP_QUERY_CALL_SKIP_REASON に理由を書けば通る。理由が空の場合は通らない
set -uo pipefail

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${LOOP_QUERY_CALL_SKIP_REASON:-}" ]; then
    echo "[LOOP-QUERY-CALL-SKIP] 理由: ${LOOP_QUERY_CALL_SKIP_REASON}"
    return 0
  fi
  return 1
}

LOOP_RE='^[[:space:]]*(for[[:space:]]*\(|for[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+(in|of)[[:space:]]|while[[:space:]]*\(|.*[A-Za-z_.]+\.(forEach|map|filter|flatMap|some|every)\()'
# コールバックを渡す形（.map( 等）だけを取り出す。この形は繰り返しの本体が
# 開始行と同じ行に書かれうるため、次の行から見る窓とは別に照合する。
CALLBACK_LOOP_RE='[A-Za-z_.]+\.(forEach|map|filter|flatMap|some|every)\('
QUERY_RE='\.(query|find|findOne|findAll|execute)\(|SELECT[[:space:]]|INSERT[[:space:]]INTO|db\.|Model\.|prisma\.|fetch\(|axios\.|requests\.(get|post)\('
WINDOW=15

UNBOUNDED_SELECT_RE='SELECT[[:space:]]+\*[[:space:]]+FROM[[:space:]]+[A-Za-z_][A-Za-z0-9_]*'
UNBOUNDED_FINDALL_RE='\.findAll\([[:space:]]*\)'

PERF_TOPIC_WORD_RE='性能目標'
PERF_TOPIC_PAIR_A_RE='応答時間|処理件数'
PERF_TOPIC_GOAL_RE='目標'
NUMBER_UNIT_RE='[0-9]+(\.[0-9]+)?[[:space:]]*(秒|ミリ秒|ms|件|rps|req)'
CONDITION_RE='同時|環境|ユーザー数|接続数|負荷|台数'

judge() {
  # $1: 本文テキスト
  # 標準出力: 判定理由。戻り値: 0=許可・2=拒否
  local text="$1"

  if [ -z "$text" ]; then
    echo "対象外: 本文が空"
    return 0
  fi

  local tmp
  if ! tmp="$(mktemp "${TMPDIR:-/tmp}/check-loop-query-call.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  printf '%s\n' "$text" > "$tmp"

  local total loop_lines
  total=$(wc -l < "$tmp" | tr -d '[:space:]')
  loop_lines=$(grep -nE "$LOOP_RE" "$tmp" | cut -d: -f1)

  local ln hit body
  for ln in $loop_lines; do
    local end=$((ln + WINDOW))
    [ "$end" -gt "$total" ] && end="$total"

    # コールバックを渡す形（.map( / .forEach( 等）は、繰り返しの本体が開始行と
    # 同じ行に書かれることがある（xs.map((x) => db.query(sql)) の形）。1 行で
    # 完結するため、次の行から見る窓では本体が窓の外に落ち、素通りしていた
    # （実測 2026-08-24: 実際の書き方 10 通りのうち、この 1 行の形だけが
    # 止まらなかった）。開始行のうち、渡した関数の中身にあたる部分
    # （=> または function より後ろ）だけを本体として先に照合する。
    # 開始行の全体を見ないのは、for (const x of db.rows) のように繰り返しの
    # 「対象」を取る呼び出しまで違反として拾ってしまうため。
    if sed -n "${ln}p" "$tmp" | grep -qE "$CALLBACK_LOOP_RE"; then
      body="$(sed -n "${ln}p" "$tmp" | grep -oE '(=>|function[[:space:]]*\().*' || :)"
      if [ -n "$body" ] && printf '%s' "$body" | grep -qE "$QUERY_RE"; then
        echo "拒否[繰り返しの中で問い合わせを発行しない]: ${ln}行目の繰り返しに渡した関数の中で問い合わせ呼び出しがある"
        rm -f "$tmp"
        return 2
      fi
    fi

    hit=$(sed -n "$((ln + 1)),${end}p" "$tmp" | grep -nE "$QUERY_RE" | head -1)
    if [ -n "$hit" ]; then
      echo "拒否[繰り返しの中で問い合わせを発行しない]: ${ln}行目付近の繰り返しの内側に問い合わせ呼び出しがある（${hit}）"
      rm -f "$tmp"
      return 2
    fi
  done

  # 規則: 大きな結果を一度に返さない
  local unbounded_select
  unbounded_select=$(grep -nE "$UNBOUNDED_SELECT_RE" "$tmp" | grep -viE 'WHERE|LIMIT' | head -1)
  if [ -n "$unbounded_select" ]; then
    echo "拒否[大きな結果を一度に返さない]: WHEREもLIMITも持たないSELECT *がある（${unbounded_select}）"
    rm -f "$tmp"
    return 2
  fi
  local unbounded_findall
  unbounded_findall=$(grep -nE "$UNBOUNDED_FINDALL_RE" "$tmp" | head -1)
  if [ -n "$unbounded_findall" ]; then
    echo "拒否[大きな結果を一度に返さない]: 引数の無いfindAll()呼び出しがある（${unbounded_findall}）"
    rm -f "$tmp"
    return 2
  fi

  rm -f "$tmp"

  # 規則: 目標を数値で決める／測る条件を目標と一緒に書く
  local topic=0 has_number=0
  if printf '%s' "$text" | grep -qF -- "$PERF_TOPIC_WORD_RE"; then
    topic=1
  elif printf '%s' "$text" | grep -qE -- "$PERF_TOPIC_PAIR_A_RE" && printf '%s' "$text" | grep -qF -- "$PERF_TOPIC_GOAL_RE"; then
    topic=1
  fi
  if [ "$topic" -eq 1 ]; then
    if printf '%s' "$text" | grep -qE -- "$NUMBER_UNIT_RE"; then
      has_number=1
    else
      echo "拒否[目標を数値で決める]: 性能目標の話題はあるが数値+単位の記述が見当たらない"
      return 2
    fi
  fi
  if [ "$topic" -eq 1 ] && [ "$has_number" -eq 1 ]; then
    if ! printf '%s' "$text" | grep -qE -- "$CONDITION_RE"; then
      echo "拒否[測る条件を目標と一緒に書く]: 性能目標の数値はあるが測定条件（同時・環境・ユーザー数等）の記述が見当たらない"
      return 2
    fi
  fi

  echo "許可: 応答の速さと処理の量の決まりの違反は検出されなかった"
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

  local text
  if [ "$tool" = "Write" ]; then
    text=$(printf '%s' "$input" | jq -r '.tool_input.content // empty' 2>/dev/null)
  else
    text=$(printf '%s' "$input" | jq -r '.tool_input.new_string // empty' 2>/dev/null)
  fi

  local msg code
  if msg="$(judge "$text")"; then code=0; else code=$?; fi

  [ "$code" -eq 0 ] && exit 0

  ctx="[LOOP-QUERY-CALL-BLOCK] ${msg}。繰り返しの外へ問い合わせを出すか、まとめて取得する方式に直してください。"
  jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  printf '%s\n' "$ctx" >&2
  exit 2
}

self_test() {
  local rc=0 msg code

  # 系1: for ループの内側に db.query( → 拒否
  local t1='function loadAll(ids) {
  const results = [];
  for (const id of ids) {
    const row = db.query("SELECT * FROM users WHERE id = ?", [id]);
    results.push(row);
  }
  return results;
}'
  if msg="$(judge "$t1")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF "繰り返しの中で問い合わせを発行しない"; then
    echo "  [PASS] 系1: forループ内のdb.queryは拒否される（${msg}）"
  else
    echo "  [FAIL] 系1: forループ内のdb.queryなのに許可されない、または規則名不一致（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系2: forEach の内側に fetch( → 拒否
  local t2='ids.forEach(function (id) {
  fetch("/api/users/" + id).then(function (r) { return r.json(); });
});'
  if msg="$(judge "$t2")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF "繰り返しの中で問い合わせを発行しない"; then
    echo "  [PASS] 系2: forEach内のfetchは拒否される（${msg}）"
  else
    echo "  [FAIL] 系2: forEach内のfetchなのに許可されない、または規則名不一致（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系3: ループ内が計算だけ（問い合わせなし） → 許可
  local t3='function sum(values) {
  let total = 0;
  for (const v of values) {
    total += v;
  }
  return total;
}'
  if msg="$(judge "$t3")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系3: 計算のみのループは許可される（${msg}）"
  else
    echo "  [FAIL] 系3: 計算のみなのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系4: 問い合わせ呼び出しがループの外にある → 許可
  local t4='function loadOnce(ids) {
  const rows = db.query("SELECT * FROM users WHERE id IN (?)", [ids]);
  for (const row of rows) {
    console.log(row.name);
  }
  return rows;
}'
  if msg="$(judge "$t4")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系4: ループ外の問い合わせは許可される（${msg}）"
  else
    echo "  [FAIL] 系4: ループ外の問い合わせなのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系5: WHEREもLIMITも無いSELECT * → 拒否（大きな結果を一度に返さない）
  local t5='function loadOrders() {
  return db.query("SELECT * FROM orders");
}'
  if msg="$(judge "$t5")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF "大きな結果を一度に返さない"; then
    echo "  [PASS] 系5: WHERE/LIMITなしのSELECT *は拒否される（${msg}）"
  else
    echo "  [FAIL] 系5: WHERE/LIMITなしのSELECT *なのに拒否されない、または規則名不一致（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系6: 引数の無いfindAll() → 拒否（大きな結果を一度に返さない）
  local t6='function loadAllOrders() {
  return Order.findAll();
}'
  if msg="$(judge "$t6")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF "大きな結果を一度に返さない"; then
    echo "  [PASS] 系6: 引数無しfindAll()は拒否される（${msg}）"
  else
    echo "  [FAIL] 系6: 引数無しfindAll()なのに拒否されない、または規則名不一致（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系7: WHEREを持つSELECT * → 許可
  local t7='function loadOrder(id) {
  return db.query("SELECT * FROM orders WHERE id = ?", [id]);
}'
  if msg="$(judge "$t7")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系7: WHEREありのSELECT *は許可される（${msg}）"
  else
    echo "  [FAIL] 系7: WHEREありのSELECT *なのに拒否された（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系8: 性能目標の話題があるが数値が無い → 拒否（目標を数値で決める）
  local t8='## 非機能要件

応答時間の目標を定める。'
  if msg="$(judge "$t8")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF "目標を数値で決める"; then
    echo "  [PASS] 系8: 数値の無い性能目標は拒否される（${msg}）"
  else
    echo "  [FAIL] 系8: 数値の無い性能目標なのに拒否されない、または規則名不一致（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系9: 性能目標の数値はあるが測定条件が無い → 拒否（測る条件を目標と一緒に書く）
  local t9='## 非機能要件

応答時間の目標は200ミリ秒以内とする。'
  if msg="$(judge "$t9")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF "測る条件を目標と一緒に書く"; then
    echo "  [PASS] 系9: 測定条件の無い性能目標は拒否される（${msg}）"
  else
    echo "  [FAIL] 系9: 測定条件の無い性能目標なのに拒否されない、または規則名不一致（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系10: 性能目標の数値と測定条件の両方がある → 許可
  local t10='## 非機能要件

応答時間の目標は、同時接続100件のとき200ミリ秒以内とする。'
  if msg="$(judge "$t10")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系10: 数値と測定条件の両方がある性能目標は許可される（${msg}）"
  else
    echo "  [FAIL] 系10: 数値と測定条件の両方があるのに拒否された（exit=${code}, msg=${msg}）" >&2
    rc=1
  fi

  # 系11: 環境変数に理由を設定 → should_skip_with_reasonが戻り値0でタグと理由を返す
  local out11
  if out11="$(LOOP_QUERY_CALL_SKIP_REASON="テスト用の理由" should_skip_with_reason)"; then
    if printf '%s' "$out11" | grep -qF '[LOOP-QUERY-CALL-SKIP]' && printf '%s' "$out11" | grep -qF 'テスト用の理由'; then
      echo "  [PASS] 系11: 理由を設定するとタグと理由付きでskipされる（${out11}）"
    else
      echo "  [FAIL] 系11: skipされたがタグまたは理由が出力に含まれない（${out11}）" >&2
      rc=1
    fi
  else
    echo "  [FAIL] 系11: 理由を設定したのにskipされなかった" >&2
    rc=1
  fi

  # 系12: 環境変数が空文字 → should_skip_with_reasonが戻り値1を返す
  if LOOP_QUERY_CALL_SKIP_REASON="" should_skip_with_reason >/dev/null 2>&1; then
    echo "  [FAIL] 系12: 空文字なのにskipされた" >&2
    rc=1
  else
    echo "  [PASS] 系12: 環境変数が空文字ならskipされない"
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
