#!/usr/bin/env bash
# run-layer-machine-checks.sh — 第1層（機械検証）の自己テストを横断実行する集約スクリプト
#
# 目的:
#   generation-engine/scripts/ 配下と delivery-payload/templates/rules/checkers/ 配下で
#   --self-test を持つ .sh を動的に列挙し、順に
#   `bash <path> --self-test` で実行して結果を集計する。個々の自己テストが
#   ケースを1件も実行しないまま終了コード0を返し、全件合格と誤認される
#   事故（途中停止の疑い）を横断的に検出する。
#
# 使い方:
#   run-layer-machine-checks.sh [--repo <リポジトリのパス>] [--list] [--self-test]
#                                [--timeout <秒>]
#
# オプション:
#   --repo <path>    対象リポジトリのパス。省略時はこのスクリプトの位置から
#                    3階層上（generation-engine/scripts/verification → generation-engine/scripts →
#                    shared → リポジトリルート）を既定とする
#   --list           対象スクリプトの一覧（リポジトリルートからの相対パス）を
#                    出力するだけで実行しない
#   --self-test      本スクリプト自身の自己テストを実行する
#   --timeout <秒>   1本あたりの実行時間上限（秒）。既定値は120秒。上限に
#                    達したスクリプトは強制終了し TIMEOUT として記録する。
#                    declared_long_running_timeout() に登録された対象
#                    （実測150〜260秒）は、実測時間に基づく個別の上限（この
#                    既定値より長い場合のみ）を優先する。declared_long_running_
#                    known() に登録された対象（実測300秒超）はこの既定値の
#                    まま打ち切り、TIMEOUTではなくDECLARED-LONGとして記録
#                    する（改善課題1-52: 機能自体を変更せず「成功」または
#                    「宣言済みの既知事実」として区別可能にするための宣言。
#                    後者は集計側の待ち時間を1本のために際限なく延ばさない
#                    ための区別であり終了コードに影響しない）
#
# 列挙対象:
#   <repo>/generation-engine/scripts/ 配下の .sh のうち、ファイル内容に "--self-test" を
#   実際に引数として処理している形跡（case文の `--self-test)` 分岐、または
#   if文の `= "--self-test"` 比較）を含むもの（パスに /tests/ を含むものも
#   対象）。コメントでの言及や、他スクリプトへ --self-test を渡して呼び出す
#   だけの記述は対象外とする。本スクリプト自身は絶対パス比較で除外する。
#
# 出力（一括実行時）:
#   スクリプトごとに1行:
#     [PASS|FAIL|UNKNOWN|SUSPECT] <相対パス> — 実行 <N> 件 / 終了コード <C>
#   [UNKNOWN] は終了コード2かつ子出力が判定不能契約を満たす場合だけを表す。
#   実行の環境に道具が無い等で走れなかった場合であり、成果物の欠陥ではない。
#   [UNKNOWN] だけなら終了コード2、失敗等と混在すれば終了コード1へ反映する。
#   [FAIL] の場合のみ、対象スクリプトの標準出力・標準エラー出力（run_one() が
#   捨てずに RUN_OUTPUT へ保持しているもの）を、2文字インデントで直後に
#   そのまま添える。失敗の理由をその場で読めるようにするための出力であり、
#   PASS・SUSPECT の行はこの追加を行わない（従来の見え方を変えない）。
#     [TIMEOUT] <相対パス> — 上限 <N> 秒に達したため打ち切り
#     [DECLARED-LONG] <相対パス> — 宣言済み長時間実行のため既定上限で打ち切り
#       （declared_long_running_known() に登録済みの対象のみ。実測が既知の
#       事実であり、機械検証の実行時間を1本のために際限なく延ばさないための
#       区別。途中停止の疑い・打ち切りのいずれにも数えず、終了コードにも
#       影響しない）
#   打ち切りが1本以上あれば、末尾に打ち切り一覧を出す。
#   末尾に集計行:
#     対象 <T> 本 / 成功 <P> 本 / 失敗 <F> 本 / 判定不能 <U> 本 / 途中停止の疑い <S> 本 /
#     打ち切り <TO> 本 / 宣言済み長時間 <DL> 本 / 総ケース数 <TC> 件
#
# 終了コード: 失敗・途中停止の疑い・打ち切りのいずれかが1本でもあれば1。
# UNKNOWNだけなら2、すべて成功なら0。
#
# 時間上限の実装: `timeout`/`gtimeout` コマンドに依存しない。対象スクリプトを
# バックグラウンドで起動し、0.2秒間隔でポーリングして生存確認する。上限に
# 達したら `set -m` で作成したプロセスグループへ SIGTERM → SIGKILL を送る。
# なぜ素直な形（`timeout <秒> <cmd>` を使う形）を避けたか: この環境には
# `timeout` コマンドも `gtimeout` コマンドも実在しない（実測。`command -v timeout`・
# `command -v gtimeout` がともに何も返さない）ため、標準の時間制限手段が使えない。
# 環境依存: 依存する。`timeout`/`gtimeout` が存在する環境（多くのLinux配布やGNU
# coreutils導入済みのmacOS）へ持ち込んでも、それを理由にポーリング実装を
# 素直な `timeout` 呼び出しへ戻すな（この環境に存在しないという制約は変わらない）。
# 全体実測（引数なし・対象132本・版 645377f31c32532f95286fa9a4084331d01e3efa）:
# 所要時間1819秒 / 総ケース数1444件 / 成功114本 / 失敗17本 / 打ち切り0本 /
# 途中停止の疑い0本。対象本数の規模でも1本あたりのポーリング実装が全体の
# 所要時間を破綻させないことを示す実測値であり、この上限実装の妥当性の根拠。
#
# 保守責任者: 人手（ユーザー）。列挙規則・カウント規則・時間上限の実装を
# 変える場合は本ファイルと self-test を同時に更新する。
# macOS bash 3.2 互換（連想配列 declare -A・${var^^}・wait -n 等は使わない）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

# 対象スクリプトを列挙する（絶対パス・ソート済み・1行1件）。
# repo: リポジトリルート / self: 除外する絶対パス（通常は本スクリプト自身の SCRIPT_PATH）
list_targets() {
  local repo="$1" self="$2" dir checkers
  dir="$repo/generation-engine/scripts"
  # 納品先へ配る検査も対象に含める。配る先で規約の違反を見つける道具であり、
  # 壊れたまま配られないよう、このリポジトリの機械検証で動かす。
  checkers="$repo/delivery-payload/templates/rules/checkers"
  [ -d "$dir" ] || [ -d "$checkers" ] || return 0
  {
    if [ -d "$dir" ]; then
      grep -rlE --include='*.sh' -e '--self-test\)' -e '= "--self-test"' "$dir" 2>/dev/null
      # 引数を取らず、実行そのものが検査になるテストも対象に含める。
      # これらは --self-test を受け取らないため、上の走査では拾えない。
      # .sh を名前で拾う条件は 2026-08-19 に追加した。それまで .cjs と .mjs だけを
      # 名前で拾っており、同じ性質を持つ test-*.sh が一度も走らないまま残っていた。
      # 追加により収集は 149 件から 160 件へ増えた（実測）。増えた 11 本のうち 2 本は
      # 終了コード 1 で落ちており、集約に載っていないため誰も見ていなかった。
      # 落ちているものを条件から外してはならない。落ちている事実が見えなくなる。
      # 上限を超えるものだけを declared_long_running_known() へ登録して別枠にする。
      # --self-test を持つ .sh と重複しうるため、末尾の並べ替えで重複を除く。
      find "$dir" \( -name 'test-*.cjs' -o -name 'test-*.mjs' -o -name 'test-*.sh' \) -type f 2>/dev/null
    fi
    if [ -d "$checkers" ]; then
      grep -rlE --include='*.sh' -e '--self-test\)' -e '= "--self-test"' "$checkers" 2>/dev/null
    fi
  } | while IFS= read -r f; do
    [ -z "$f" ] && continue
    local abs
    abs="$(cd "$(dirname "$f")" 2>/dev/null && pwd)/$(basename "$f")"
    [ -z "$abs" ] && continue
    [ "$abs" = "$self" ] && continue
    printf '%s\n' "$abs"
  done | sort -u
}

# 子検査の終了コード2を判定不能として受け入れる前に、判定不能規約が求める
# ラベル・実際に失敗した操作名・想定原因を同じ [UNKNOWN] 行で確認する。
# 形だけの終了コード2（未知引数など）は呼出し失敗であり、不合格として扱う。
has_indeterminate_contract() {
  local output="$1" unknown_line body operation cause parenthetical
  printf '%s\n' "$output" | grep -qiE '^[[:space:]]*(\[UNKNOWN\][[:space:]]*)?(error([:[:space:]]|$)|usage([:[:space:]]|$)|unknown[[:space:]]+(argument|option)([:[:space:]]|$)|invalid[[:space:]]+(argument|option)([:[:space:]]|$)|bad[[:space:]]+option([:[:space:]]|$)|未知の引数|不明な引数)' && return 1
  unknown_line="$(printf '%s\n' "$output" | grep '^\[UNKNOWN\]' | head -1)"
  [ -n "$unknown_line" ] || return 1

  # 操作名と原因は非空を必須とする。集約器が検証できるのは非空値という構文まで
  # であり、子が申告した意味の真偽は子検査自身が担保する。
  # 例えば false は実在するコマンドなので、操作名のallowlist化は行わない。
  #
  # 受け入れる書き方は 2 通りある。
  #   1. キー付き: [UNKNOWN] 〜 操作: <操作名> / 想定原因: <原因>
  #   2. 括弧書き: [UNKNOWN] 〜（<操作名と原因を述べた文>）
  # 2 を受け入れるのは、判定不能規約
  # （.claude/rules/always/verification/indeterminate-result/rule.md）の
  # 「具体例」節が示す書き方が括弧書きだからである。キー付きだけを認めていた
  # ため、規約の見本どおりに書いた子検査が不合格として数えられていた
  # （実測 2026-08-24: 2 本が [FAIL] に混ざり、実行できなかったことと
  # 不合格だったことの区別が失われていた）。
  # 括弧の中身が非空であることを、操作名と原因を述べたことの代わりとする。
  body="${unknown_line#\[UNKNOWN\]}"
  operation="$(printf '%s\n' "$body" | sed -n 's/.*操作:[[:space:]]*\(.*\)[[:space:]]\/[[:space:]]*想定原因:.*/\1/p')"
  cause="$(printf '%s\n' "$body" | sed -n 's/.*[[:space:]]\/[[:space:]]*想定原因:[[:space:]]*\(.*\)$/\1/p')"
  if [ -n "$(printf '%s' "$operation" | tr -d '[:space:]')" ] \
     && [ -n "$(printf '%s' "$cause" | tr -d '[:space:]')" ]; then
    return 0
  fi

  parenthetical="$(printf '%s\n' "$body" | LC_ALL=en_US.UTF-8 sed -n 's/.*（\(.*\)）.*/\1/p')"
  [ -n "$(printf '%s' "$parenthetical" | tr -d '[:space:]')" ]
}

# 出力から実行ケース数を読み取る。次の順で試し、最初に一致した形式の値を採る。
#   1. 「実行 <N> 件」の N
#   2. 「self-test: <N> PASS」の N（「, <M> FAIL」があれば N+M）
#   3. 「結果: PASS=<N> FAIL=<M>」の N+M
#   4. 行頭の「self-test PASS:」/「self-test FAIL:」の合計
#   5. 行頭の PASS(<N>):/FAIL(<N>): の合計
#   6. 行頭の [PASS]/[FAIL] の合計
#   7. 行頭の PASS:/FAIL: の合計
#   8. 出力全体に「全項目 PASS」/「全項目 FAIL」という個別内訳を伴わない単一の
#      要約行がある場合は1件（cmp/jq -e 等が set -euo pipefail 下で暗黙にケースを
#      検証しており、内訳の行だけを持たない自己テストのための救済）
#   9. 行頭の PASS /FAIL （空白区切り）の合計
count_cases() {
  local output="$1" n pass_n fail_n line p f

  n="$(printf '%s\n' "$output" | grep -oE '実行 [0-9]+ 件' | head -1 | grep -oE '[0-9]+')"
  if [ -n "$n" ]; then
    printf '%s' "$n"
    return 0
  fi

  n="$(printf '%s\n' "$output" | grep -oE '^# (tests|pass) [0-9]+' | head -1 | grep -oE '[0-9]+')"
  if [ -n "$n" ]; then
    printf '%s' "$n"
    return 0
  fi

  line="$(printf '%s\n' "$output" | grep -oE 'self-test: [0-9]+ PASS(, [0-9]+ FAIL)?' | head -1)"
  if [ -n "$line" ]; then
    p="$(printf '%s' "$line" | grep -oE '[0-9]+ PASS' | grep -oE '[0-9]+')"
    f="$(printf '%s' "$line" | grep -oE '[0-9]+ FAIL' | grep -oE '[0-9]+')"
    [ -z "$p" ] && p=0
    [ -z "$f" ] && f=0
    printf '%s' "$((p + f))"
    return 0
  fi

  line="$(printf '%s\n' "$output" | grep -oE '結果: *PASS=[0-9]+ *FAIL=[0-9]+' | head -1)"
  if [ -n "$line" ]; then
    p="$(printf '%s' "$line" | grep -oE 'PASS=[0-9]+' | grep -oE '[0-9]+')"
    f="$(printf '%s' "$line" | grep -oE 'FAIL=[0-9]+' | grep -oE '[0-9]+')"
    [ -z "$p" ] && p=0
    [ -z "$f" ] && f=0
    printf '%s' "$((p + f))"
    return 0
  fi

  pass_n="$(printf '%s\n' "$output" | grep -cE '^[[:space:]]*self-test (PASS|FAIL): ')"
  if [ "$pass_n" -gt 0 ]; then
    printf '%s' "$pass_n"
    return 0
  fi

  pass_n="$(printf '%s\n' "$output" | grep -cE '^[[:space:]]*(PASS|FAIL)\([0-9]+\): ')"
  if [ "$pass_n" -gt 0 ]; then
    printf '%s' "$pass_n"
    return 0
  fi

  pass_n="$(printf '%s\n' "$output" | grep -cE '^[[:space:]]*\[PASS\]')"
  fail_n="$(printf '%s\n' "$output" | grep -cE '^[[:space:]]*\[FAIL\]')"
  if [ "$((pass_n + fail_n))" -gt 0 ]; then
    printf '%s' "$((pass_n + fail_n))"
    return 0
  fi

  pass_n="$(printf '%s\n' "$output" | grep -cE '^[[:space:]]*PASS:')"
  fail_n="$(printf '%s\n' "$output" | grep -cE '^[[:space:]]*FAIL:')"
  if [ "$((pass_n + fail_n))" -gt 0 ]; then
    printf '%s' "$((pass_n + fail_n))"
    return 0
  fi

  if printf '%s\n' "$output" | grep -qE '全項目 (PASS|FAIL)'; then
    printf '%s' "1"
    return 0
  fi

  pass_n="$(printf '%s\n' "$output" | grep -cE '^[[:space:]]*PASS[[:space:]]')"
  fail_n="$(printf '%s\n' "$output" | grep -cE '^[[:space:]]*FAIL[[:space:]]')"
  printf '%s' "$((pass_n + fail_n))"
}

# 実測所要時間が既定の --timeout（90〜120秒）を超える既存の自己テストを
# 宣言する表（改善課題1-52）。個々のスクリプトは generation-engine/scripts/extract/・
# generation-engine/scripts/unit-list/ 配下であり、検証する機能そのもの（大規模フィクス
# チャでの抽出ロジック）を変更する権限が無い、または変更すると検証範囲が
# 狭まるため、実行時間の短縮ではなく上限側の宣言で対応する。値は隔離環境
# での単発実測（2026-08-14, `time bash <script> --self-test`）に対し安全率を
# 掛けた秒数。新たに90秒を超える自己テストが見つかった場合、実測が300秒
# 以内ならここに追記する（実測値は本関数のコメントに残す）。300秒を超える
# 場合は集計側の待ち時間を際限なく延ばさないため declared_long_running_known()
# （後述）へ登録し、既定上限で打ち切って [DECLARED-LONG] として区別する。
#   generation-engine/scripts/audit-consistency.sh                 実測151s → 200s
#   generation-engine/scripts/extract/extract-batch-metadata.sh     実測252s → 300s
#   generation-engine/scripts/extract/extract-table-metadata.sh     実測241s → 300s
#   generation-engine/scripts/unit-list/detect-screens.sh           実測209s → 260s
#   generation-engine/scripts/unit-list/build-screen-list.sh        実測155s → 200s
#   generation-engine/scripts/unit-list/build-unit-list.sh          実測189s → 240s
#   generation-engine/scripts/rules/scaffold-rule-definitions.sh    実測212s（規約27件・checker27件の時点）→ 300s
#     （2026-08-14再実測: 当初の隔離実測では既定90秒以内に収まっていたが、
#      同一worktree内の並行作業による負荷変動で90秒を超える揺れを観測した
#      ため、再実測値に安全率を掛けて追加登録した。
#      2026-08-18再実測: 独自語彙検査の新設・適用範囲の上書き受け口等、
#      コミット5ebabbb3（実測110s時点）以降に積み重なった変更により212sへ
#      増加した。self-testは規約27件それぞれの生成・検証・rule.html化を
#      行うため、規約・検査ケースの件数増加に対しほぼ線形に所要時間が伸びる
#      構造である。実測212sに約40%の余裕を持たせ300sへ引き上げた）
#   generation-engine/scripts/rules/build-derived-rules.sh          実測115s → 150s
#     （2026-08-18実測: `time bash <script> --self-test`で1:55(115s)。
#      既定90秒を超え[TIMEOUT]として打ち切られていたが、全17ケースPASSで
#      exit 0の正常完走であることを確認済み。ケース数が多い決定的生成の
#      自己テストであり、機能・実行時間の是正は範囲外として宣言する）
# 引数: repo・abs（対象スクリプトの絶対パス）。戻り値: 宣言された上限秒数を
# echo する。該当が無ければ何も出力しない（呼び出し側は既定値を使う）。
declared_long_running_timeout() {
  local repo="$1" abs="$2" rel
  rel="$abs"
  case "$rel" in
    "$repo"/*) rel="${rel#"$repo"/}" ;;
  esac
  case "$rel" in
    generation-engine/scripts/audit-consistency.sh) echo 200 ;;
    # 実測 2026-08-24: --self-test は 122 秒（パイプ無し・出力破棄）。既定の
    # 上限 120 秒では、見張りの誤差を入れた実時間の打ち切り点（約 124 秒）まで
    # 2 秒しか余裕が無く、負荷が少し上がるだけで打ち切られていた。検査の内容に
    # 問題が無いのに第 1 層の合否が実行環境の混み具合で変わるため、余裕を持つ
    # 上限を与える。所要時間を縮める道は、内訳が 1 秒未満の多数のケースへ薄く
    # 分散しており 1 箇所を直しても届かないと実測で分かっている。
    generation-engine/scripts/build-portal.sh) echo 200 ;;
    generation-engine/scripts/extract/extract-batch-metadata.sh) echo 300 ;;
    generation-engine/scripts/extract/extract-table-metadata.sh) echo 300 ;;
    generation-engine/scripts/unit-list/detect-screens.sh) echo 260 ;;
    generation-engine/scripts/unit-list/build-screen-list.sh) echo 200 ;;
    generation-engine/scripts/unit-list/build-unit-list.sh) echo 240 ;;
    generation-engine/scripts/rules/scaffold-rule-definitions.sh) echo 300 ;;
    generation-engine/scripts/rules/build-derived-rules.sh) echo 150 ;;
    *) ;;
  esac
}

# 既定上限を超えることを実測で確認した対象だけをここへ宣言する。この関数が
# 真を返すスクリプトが既定上限で打ち切られた場合、run_all() は TIMEOUT ではなく
# DECLARED-LONG として記録し、途中停止の疑い・打ち切りのいずれにも数えず、
# 終了コードにも影響させない。現在の登録は0件。将来、既定上限超過が実測された
# 対象のみここへ追加する。
# 引数: repo・abs（対象スクリプトの絶対パス）。戻り値: 対象なら "1" を echo
# し終了コード0、対象外なら何も出力せず終了コード1。
declared_long_running_known() {
  local repo="$1" abs="$2" rel
  rel="$abs"
  case "$rel" in
    "$repo"/*) rel="${rel#"$repo"/}" ;;
  esac
  case "$rel" in
    *)
      return 1
      ;;
  esac
}

# ポーリング間隔（秒）。`timeout`/`gtimeout` が無い環境向けに、対象スクリプトを
# バックグラウンドで起動し、この間隔で生存確認する。
POLL_INTERVAL="0.2"

# 1本を `bash <path> --self-test` で実行し、グローバル RUN_OUTPUT / RUN_RC /
# RUN_TIMED_OUT に格納する。timeout_sec 秒を超えて生存していれば強制終了し
# RUN_TIMED_OUT=1・RUN_RC=124 とする。
# `timeout`/`gtimeout` コマンドは使わない（この環境には存在しないため）。
# `set -m` で対象スクリプトを専用プロセスグループとして起動し、上限超過時は
# 負のPID（プロセスグループ）へシグナルを送って子孫プロセスごと止める。
RUN_OUTPUT=""
RUN_RC=0
RUN_TIMED_OUT=0
run_one() {
  local script="$1" timeout_sec="$2"
  local out_file pid ticks max_ticks finished prev_monitor

  if [ "${RUN_LAYER_MACHINE_CHECKS_TEST_MKTEMP_FAIL:-0}" = "1" ]; then
    out_file=""
  else
    out_file="$(mktemp "${TMPDIR:-/tmp}/run-layer-check.XXXXXX" 2>/dev/null)"
  fi
  if [ -z "$out_file" ] || [ ! -f "$out_file" ]; then
    RUN_OUTPUT="[UNKNOWN] 子検査の出力先を作成できないため実行できません 操作: mktemp / 想定原因: 一時ディレクトリが存在しない、または書き込み権限がありません"
    RUN_RC=2
    RUN_TIMED_OUT=0
    return
  fi

  prev_monitor=0
  case $- in *m*) prev_monitor=1 ;; esac
  set -m

  # 呼び方は拡張子ではなく「--self-test を解釈するか」で決める。拡張子だけで
  # 決めると、名前で拾った test-*.sh のうち --self-test を解釈しないものへも
  # --self-test が渡り、それを別の意味の引数として受け取って失敗する。
  # 実測（2026-08-19）: test-e2e-portal.sh は第1引数を samples ディレクトリと
  # して受け取るため「ERROR: samples ディレクトリが見つからない: --self-test」
  # を出して終了コード2で止まっていた。引数なしなら終了コード0で55秒で完走する。
  # 同じ形のものが 7 本ある。
  {
    case "$script" in
      *.cjs|*.mjs) node "$script" >"$out_file" 2>&1 & ;;
      *)
        if LC_ALL=C grep -qE -e '--self-test\)' -e '= "--self-test"' "$script" 2>/dev/null; then
          # 集約から呼ばれたことを対象へ伝える。対象の側は、集約が独立した対象
          # として直接呼ぶ検査を自分の中で重ねて走らせないために使う（二重実行の
          # 回避）。使う側は build-portal.sh の skip_when_aggregated を参照。
          RUN_LAYER_MACHINE_CHECKS=1 bash "$script" --self-test >"$out_file" 2>&1 &
        else
          bash "$script" >"$out_file" 2>&1 &
        fi
        ;;
    esac
    pid=$!
  } 2>/dev/null

  max_ticks=$((timeout_sec * 5))
  [ "$max_ticks" -lt 1 ] && max_ticks=1
  ticks=0
  finished=0
  while [ "$ticks" -lt "$max_ticks" ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      finished=1
      break
    fi
    sleep "$POLL_INTERVAL"
    ticks=$((ticks + 1))
  done

  if [ "$finished" -eq 1 ]; then
    { wait "$pid" 2>/dev/null; RUN_RC=$?; } 2>/dev/null
    RUN_TIMED_OUT=0
  else
    {
      kill -TERM -$pid 2>/dev/null
      sleep 0.3
      kill -KILL -$pid 2>/dev/null
      wait "$pid" 2>/dev/null
    } 2>/dev/null
    RUN_RC=124
    RUN_TIMED_OUT=1
  fi

  [ "$prev_monitor" -eq 0 ] && set +m

  RUN_OUTPUT="$(cat "$out_file" 2>/dev/null)"
  rm -f "$out_file"
}

# 対象スクリプト群を順に実行し、結果を標準出力へ書く。戻り値: 失敗・
# 途中停止の疑い・打ち切りのいずれかが1本でもあれば1、UNKNOWNだけなら2、
# すべて成功なら0。
run_all() {
  local repo="$1" self="$2" timeout_sec="${3:-120}"
  local targets total=0 passed=0 failed=0 suspect=0 timed_out=0 total_cases=0 declared_long=0 unknown=0
  local timed_out_list=""

  targets="$(list_targets "$repo" "$self")"
  if [ -z "$targets" ]; then
    printf '[UNKNOWN] 集約対象を列挙できないため機械検証を判定できません 操作: list_targets / 想定原因: 走査起点の欠落、対象リポジトリの指定誤り、または検査ファイルの全消失\n'
    printf '対象 0 本 / 成功 0 本 / 失敗 0 本 / 判定不能 0 本 / 途中停止の疑い 0 本 / 打ち切り 0 本 / 宣言済み長時間 0 本 / 総ケース数 0 件\n'
    return 2
  fi

  while IFS= read -r script; do
    [ -z "$script" ] && continue
    total=$((total + 1))
    local declared_timeout effective_timeout
    declared_timeout="$(declared_long_running_timeout "$repo" "$script")"
    effective_timeout="$timeout_sec"
    if [ -n "$declared_timeout" ] && [ "$declared_timeout" -gt "$timeout_sec" ]; then
      effective_timeout="$declared_timeout"
    fi
    run_one "$script" "$effective_timeout"
    local n status rel
    n="$(count_cases "$RUN_OUTPUT")"
    rel="$script"
    case "$rel" in
      "$repo"/*) rel="${rel#"$repo"/}" ;;
    esac
    if [ "$RUN_TIMED_OUT" -eq 1 ]; then
      if declared_long_running_known "$repo" "$script" >/dev/null; then
        status="DECLARED-LONG"
        declared_long=$((declared_long + 1))
        total_cases=$((total_cases + n))
        printf '[%s] %s — 宣言済み長時間実行のため既定上限 %s 秒で打ち切り（機能・実行時間の是正は範囲外として宣言済み）\n' \
          "$status" "$rel" "$effective_timeout"
        continue
      fi
      status="TIMEOUT"
      timed_out=$((timed_out + 1))
      timed_out_list="$timed_out_list$rel
"
      total_cases=$((total_cases + n))
      printf '[%s] %s — 上限 %s 秒に達したため打ち切り\n' "$status" "$rel" "$effective_timeout"
      continue
    fi
    # 終了コード 2 は「実行できなかった」を表す（判定不能の規約）。不合格と同じ
    # 扱いにすると、実行の環境に道具が無いだけの検査を成果物の欠陥と読み違える。
    # 2026-08-19 実測: 用語の一覧を検査する 2 本が道具（PyYAML・venv）を持たない
    # ために終了コード 2 を返し、失敗として数えられていた。中身の不備ではない。
    if [ "$n" -eq 0 ] && [ "$RUN_RC" -eq 0 ]; then
      status="SUSPECT"
      suspect=$((suspect + 1))
    elif [ "$RUN_RC" -eq 0 ]; then
      status="PASS"
      passed=$((passed + 1))
    elif [ "$RUN_RC" -eq 2 ] && has_indeterminate_contract "$RUN_OUTPUT"; then
      status="UNKNOWN"
      unknown=$((unknown + 1))
    elif [ "$RUN_RC" -eq 2 ]; then
      status="FAIL"
      failed=$((failed + 1))
    else
      status="FAIL"
      failed=$((failed + 1))
    fi
    total_cases=$((total_cases + n))
    printf '[%s] %s — 実行 %s 件 / 終了コード %s\n' "$status" "$rel" "$n" "$RUN_RC"
    if { [ "$status" = "FAIL" ] || [ "$status" = "UNKNOWN" ]; } && [ -n "$RUN_OUTPUT" ]; then
      printf '%s\n' "$RUN_OUTPUT" | sed 's/^/  /'
    fi
  done <<TARGETS
$targets
TARGETS

  if [ "$timed_out" -gt 0 ]; then
    printf '打ち切り一覧:\n'
    printf '%s' "$timed_out_list" | while IFS= read -r rel; do
      [ -z "$rel" ] && continue
      printf '  %s\n' "$rel"
    done
  fi

  printf '対象 %s 本 / 成功 %s 本 / 失敗 %s 本 / 判定不能 %s 本 / 途中停止の疑い %s 本 / 打ち切り %s 本 / 宣言済み長時間 %s 本 / 総ケース数 %s 件\n' \
    "$total" "$passed" "$failed" "$unknown" "$suspect" "$timed_out" "$declared_long" "$total_cases"

  # 判定不能だけなら終了コード2を返し、失敗等との混在では1を優先する。
  # 実行不能と成果物の不合格を区別しつつ、実在する失敗を隠さない。
  if [ "$failed" -gt 0 ] || [ "$suspect" -gt 0 ] || [ "$timed_out" -gt 0 ]; then
    return 1
  fi
  if [ "$unknown" -gt 0 ]; then
    return 2
  fi
  return 0
}

self_test() {
  local tmp pass=0 fail=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/run-layer-machine-checks-self-test.XXXXXX")" || {
    echo "self-test: 一時ディレクトリを作成できない" >&2
    return 1
  }
  # TMPDIR が末尾スラッシュ付きの場合に "//" が残ると、list_targets が
  # `cd && pwd` で正規化した絶対パスと文字列比較でずれるため、ここで正規化する。
  tmp="$(cd "$tmp" && pwd)"
  trap 'rm -rf "$tmp"' EXIT

  assert_true() {
    local name="$1" ok="$2"
    if [ "$ok" -eq 0 ]; then
      echo "  [PASS] $name"
      pass=$((pass + 1))
    else
      echo "  [FAIL] $name"
      fail=$((fail + 1))
    fi
  }

  # --- フィクスチャ準備（repoA: 列挙・除外の検証用） ---
  local scanA="$tmp/repoA/generation-engine/scripts"
  mkdir -p "$scanA/tests"

  cat > "$scanA/good.sh" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "  [PASS] good-case-1"
  echo "  [PASS] good-case-2"
  exit 0
fi
exit 0
EOS

  cat > "$scanA/no-flag.sh" <<'EOS'
#!/usr/bin/env bash
echo "no self test string here"
exit 0
EOS

  cat > "$scanA/tests/quiet.sh" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  exit 0
fi
exit 0
EOS

  cat > "$scanA/self-marker.sh" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "  [PASS] self-marker-case"
  exit 0
fi
exit 0
EOS

  cat > "$scanA/comment-only.sh" <<'EOS'
#!/usr/bin/env bash
# このスクリプトは --self-test フラグを持つ本番経路スクリプトではないため、
# 追加の --self-test 実装は行わない。
echo "no processing here"
exit 0
EOS

  chmod +x "$scanA"/*.sh "$scanA/tests"/*.sh

  # 列挙-対象検出 / 列挙-非対象除外
  local listedA
  listedA="$(list_targets "$tmp/repoA" "/dev/null/no-such-self")"
  if printf '%s' "$listedA" | grep -qF "$scanA/good.sh" \
    && printf '%s' "$listedA" | grep -qF "$scanA/tests/quiet.sh"; then
    assert_true "列挙-対象検出" 0
  else
    assert_true "列挙-対象検出" 1
  fi
  if printf '%s' "$listedA" | grep -qF "$scanA/no-flag.sh"; then
    assert_true "列挙-非対象除外" 1
  else
    assert_true "列挙-非対象除外" 0
  fi

  # 列挙-引数処理のみ（コメントで言及するだけのスクリプトは列挙されない）
  if printf '%s' "$listedA" | grep -qF "$scanA/comment-only.sh"; then
    assert_true "列挙-引数処理のみ" 1
  else
    assert_true "列挙-引数処理のみ" 0
  fi

  # 列挙-納品する検査（delivery-payload の検査も対象に入る）
  local deliveredDir="$tmp/repoA/delivery-payload/templates/rules/checkers"
  mkdir -p "$deliveredDir"
  printf '%s\n' '#!/usr/bin/env bash' 'case "${1:-}" in --self-test) echo "実行 1 件"; exit 0 ;; esac' > "$deliveredDir/check-delivered.sh"
  chmod +x "$deliveredDir/check-delivered.sh"
  local listedDelivered
  listedDelivered="$(list_targets "$tmp/repoA" "/dev/null/no-such-self")"
  if printf '%s' "$listedDelivered" | grep -qF "$deliveredDir/check-delivered.sh"; then
    assert_true "列挙-納品する検査" 0
  else
    assert_true "列挙-納品する検査" 1
  fi

  # 除外-自身（自身は消え、他は残る）
  local listedExcl
  listedExcl="$(list_targets "$tmp/repoA" "$scanA/self-marker.sh")"
  if printf '%s' "$listedExcl" | grep -qF "$scanA/self-marker.sh"; then
    assert_true "除外-自身" 1
  elif printf '%s' "$listedExcl" | grep -qF "$scanA/good.sh"; then
    assert_true "除外-自身" 0
  else
    assert_true "除外-自身" 1
  fi

  # ケース数-読取
  local nRead
  nRead="$(count_cases "実行 5 件 / 成功 5 件 / 失敗 0 件")"
  [ "$nRead" = "5" ] && assert_true "ケース数-読取" 0 || assert_true "ケース数-読取" 1

  # 読取-コロン形式（PASS: 説明 を3行出す出力から3が読み取られる）
  local nColon
  nColon="$(count_cases "$(printf 'PASS: 説明1\nPASS: 説明2\nPASS: 説明3\n')")"
  [ "$nColon" = "3" ] && assert_true "読取-コロン形式" 0 || assert_true "読取-コロン形式" 1

  # 読取-集計行形式（self-test: 5 PASS, 0 FAIL から5が読み取られる）
  local nSummary
  nSummary="$(count_cases "self-test: 5 PASS, 0 FAIL")"
  [ "$nSummary" = "5" ] && assert_true "読取-集計行形式" 0 || assert_true "読取-集計行形式" 1

  # 読取-self-test PASS形式（改善課題1-52: aggregate-test-cases.sh 等が使う
  # 「self-test PASS: 説明」形式を4行出す出力から4が読み取られる）
  local nSelfTestPass
  nSelfTestPass="$(count_cases "$(printf 'self-test PASS: 説明1\nself-test PASS: 説明2\nself-test FAIL: 説明3\nself-test PASS: 説明4\n')")"
  [ "$nSelfTestPass" = "4" ] && assert_true "読取-self-test-PASS形式" 0 || assert_true "読取-self-test-PASS形式" 1

  # 読取-番号付きPASS形式（改善課題1-52: apply-guide-style.sh 等が使う
  # 「PASS(N): 説明」形式を3行出す出力から3が読み取られる）
  local nNumberedPass
  nNumberedPass="$(count_cases "$(printf 'PASS(1): 説明1\nPASS(2): 説明2\nFAIL(3): 説明3\n')")"
  [ "$nNumberedPass" = "3" ] && assert_true "読取-番号付きPASS形式" 0 || assert_true "読取-番号付きPASS形式" 1

  # 読取-全項目要約行（改善課題1-52: build-permission-function-data.sh 等が使う、
  # 個別内訳を持たない「self-test 全項目 PASS」の単一要約行から1が読み取られる）
  local nAllItems
  nAllItems="$(count_cases "$(printf 'OK: wrote a.json\nOK: wrote b.json\nself-test 全項目 PASS\n')")"
  [ "$nAllItems" = "1" ] && assert_true "読取-全項目要約行" 0 || assert_true "読取-全項目要約行" 1

  # Node標準node:testのTAP要約を読めること。tests/passは同じ件数なので、先に
  # 現れるtests行を採用する。
  local nTap
  nTap="$(count_cases $'# tests 5\n# pass 5')"
  [ "$nTap" = "5" ] && assert_true "読取-node-test-TAP要約" 0 || assert_true "読取-node-test-TAP要約" 1

  # 実行-mktemp失敗: 子出力を保存できない場合は不合格へ変換せず、構造化した
  # 判定不能として呼出し側へ返す。
  RUN_LAYER_MACHINE_CHECKS_TEST_MKTEMP_FAIL=1 run_one "/dev/null/no-such-script" 30
  if [ "$RUN_RC" -eq 2 ] \
    && [ "$RUN_TIMED_OUT" -eq 0 ] \
    && has_indeterminate_contract "$RUN_OUTPUT" \
    && printf '%s\n' "$RUN_OUTPUT" | grep -qF '操作: mktemp / 想定原因:'; then
    assert_true "実行-mktemp失敗を判定不能にする" 0
  else
    assert_true "実行-mktemp失敗を判定不能にする" 1
  fi

  # 判定不能-対象0本: 対象が無い早期return経路を合格と読み替えないこと。
  local outEmpty rcEmpty
  outEmpty="$(run_all "$tmp/repo-empty" "/dev/null/no-such-self" 30)"
  rcEmpty=$?
  if [ "$rcEmpty" -eq 2 ] \
    && has_indeterminate_contract "$outEmpty" \
    && printf '%s\n' "$outEmpty" | grep -q '^\[UNKNOWN\].*集約対象' \
    && printf '%s\n' "$outEmpty" | grep -qF '操作: list_targets / 想定原因:' \
    && printf '%s\n' "$outEmpty" | grep -q '対象 0 本'; then
    assert_true "判定不能-対象0本の集計行" 0
  else
    assert_true "判定不能-対象0本の集計行" 1
  fi

  # --- フィクスチャ準備（repoB: 成功/失敗/継続/終了コードの検証用） ---
  local scanB="$tmp/repoB/generation-engine/scripts"
  mkdir -p "$scanB"

  cat > "$scanB/a-fail.sh" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "  [PASS] a-case-1"
  echo "  [FAIL] a-case-2"
  exit 1
fi
exit 0
EOS

  # z-after.sh は実行された証跡として、自分と同じディレクトリに副作用ファイルを残す。
  # run_all の報告行は集計のみで生の出力本文を含まないため、継続実行の確認には
  # 報告文字列の grep ではなく副作用ファイルの実在確認を使う。
  cat > "$scanB/z-after.sh" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "  [PASS] z-after-ran-marker"
  touch "$(dirname "$0")/.z-after-ran"
  exit 0
fi
exit 0
EOS

  # 終了コード2（実行できなかった）を返す疑似スクリプト。判定不能の規約が
  # 定める形であり、不合格（終了コード1）と区別されることを確かめるために置く。
  cat > "$scanB/b-unknown.sh" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "[UNKNOWN] 一時領域を作れないため判定できません 操作: mktemp -d / 想定原因: fixtureの実行環境が未準備"
  exit 2
fi
exit 0
EOS

  chmod +x "$scanB"/*.sh

  local outB rcB
  outB="$(run_all "$tmp/repoB" "/dev/null/no-such-self" 30)"
  rcB=$?

  # 判定不能-不合格と区別: 終了コード2の対象が [FAIL] ではなく [UNKNOWN] として
  # 報告され、集計行の「判定不能」に数えられること。
  if printf '%s' "$outB" | grep -qF "[UNKNOWN] generation-engine/scripts/b-unknown.sh" \
    && printf '%s' "$outB" | grep -qF '操作: mktemp -d / 想定原因: fixtureの実行環境が未準備' \
    && printf '%s' "$outB" | grep -qE '判定不能 [1-9][0-9]* 本'; then
    assert_true "判定不能-不合格と区別" 0
  else
    assert_true "判定不能-不合格と区別" 1
  fi
  if [ "$rcB" -eq 1 ] \
    && printf '%s' "$outB" | grep -qF '[FAIL] generation-engine/scripts/a-fail.sh' \
    && printf '%s' "$outB" | grep -qF '[UNKNOWN] generation-engine/scripts/b-unknown.sh' \
    && printf '%s' "$outB" | grep -qF '操作: mktemp -d / 想定原因: fixtureの実行環境が未準備'; then
    assert_true "判定不能-不合格混在は1を優先し理由を保持" 0
  else
    assert_true "判定不能-不合格混在は1を優先し理由を保持" 1
  fi

  # 終了コード2でも [UNKNOWN]・操作名・原因のいずれかを欠けば呼出し失敗である。
  local scanInvalid outInvalid rcInvalid
  scanInvalid="$tmp/repo-invalid/generation-engine/scripts"
  mkdir -p "$scanInvalid"
  cat > "$scanInvalid/invalid-unknown.sh" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "[UNKNOWN] 判定できません"
  exit 2
fi
exit 0
EOS
  cat > "$scanInvalid/abc-unknown.sh" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "[UNKNOWN] abc 原因"
  exit 2
fi
exit 0
EOS
  cat > "$scanInvalid/unknown-argument.sh" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "[UNKNOWN] 未知の引数です: --help 操作: false / 想定原因: fixture"
  exit 2
fi
exit 0
EOS
  cat > "$scanInvalid/error-unknown.sh" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "[UNKNOWN] ERROR: 呼出し失敗 操作: false / 想定原因: fixture"
  exit 2
fi
exit 0
EOS
  cat > "$scanInvalid/lowercase-error.sh" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "[UNKNOWN] error 操作: false / 想定原因: fixture"
  exit 2
fi
exit 0
EOS
  cat > "$scanInvalid/lowercase-usage.sh" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "[UNKNOWN] usage: tool 操作: false / 想定原因: fixture"
  exit 2
fi
exit 0
EOS
  cat > "$scanInvalid/unknown-option.sh" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "[UNKNOWN] unknown option --bad 操作: false / 想定原因: fixture"
  exit 2
fi
exit 0
EOS
  chmod +x "$scanInvalid/invalid-unknown.sh"
  chmod +x "$scanInvalid/abc-unknown.sh" "$scanInvalid/unknown-argument.sh" "$scanInvalid/error-unknown.sh" \
    "$scanInvalid/lowercase-error.sh" "$scanInvalid/lowercase-usage.sh" "$scanInvalid/unknown-option.sh"
  outInvalid="$(run_all "$tmp/repo-invalid" "/dev/null/no-such-self" 30)"
  rcInvalid=$?
  if [ "$rcInvalid" -eq 1 ] \
    && printf '%s' "$outInvalid" | grep -qF '[FAIL] generation-engine/scripts/invalid-unknown.sh' \
    && printf '%s' "$outInvalid" | grep -qF '[FAIL] generation-engine/scripts/abc-unknown.sh' \
    && printf '%s' "$outInvalid" | grep -qF '[FAIL] generation-engine/scripts/unknown-argument.sh' \
    && printf '%s' "$outInvalid" | grep -qF '[FAIL] generation-engine/scripts/error-unknown.sh' \
    && printf '%s' "$outInvalid" | grep -qF '[FAIL] generation-engine/scripts/lowercase-error.sh' \
    && printf '%s' "$outInvalid" | grep -qF '[FAIL] generation-engine/scripts/lowercase-usage.sh' \
    && printf '%s' "$outInvalid" | grep -qF '[FAIL] generation-engine/scripts/unknown-option.sh'; then
    assert_true "判定不能-契約違反の終了コード2を不合格にする" 0
  else
    assert_true "判定不能-契約違反の終了コード2を不合格にする" 1
  fi

  # 判定不能規約（.claude/rules/always/verification/indeterminate-result/rule.md）の
  # 「具体例」節が示す括弧書きの [UNKNOWN] を判定不能として受け入れる。
  # キー付き（操作: / 想定原因:）だけを認めていたため、規約の見本どおりに
  # 書いた子検査 2 本が不合格として数えられていた（実測 2026-08-24）。
  local scanParen outParen rcParen
  scanParen="$tmp/repo-paren/generation-engine/scripts"
  mkdir -p "$scanParen"
  cat > "$scanParen/paren-unknown.sh" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）"
  exit 2
fi
exit 0
EOS
  cat > "$scanParen/paren-empty.sh" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "[UNKNOWN] 判定できません（）"
  exit 2
fi
exit 0
EOS
  chmod +x "$scanParen/paren-unknown.sh" "$scanParen/paren-empty.sh"
  outParen="$(run_all "$tmp/repo-paren" "/dev/null/no-such-self" 30)"
  rcParen=$?
  if printf '%s' "$outParen" | grep -qF '[UNKNOWN] generation-engine/scripts/paren-unknown.sh' \
    && printf '%s' "$outParen" | grep -qF '[FAIL] generation-engine/scripts/paren-empty.sh'; then
    assert_true "判定不能-括弧書きを受け入れ括弧が空なら不合格にする" 0
  else
    assert_true "判定不能-括弧書きを受け入れ括弧が空なら不合格にする" 1
  fi

  if printf '%s' "$outB" | grep -qF "[PASS] generation-engine/scripts/z-after.sh"; then
    assert_true "実行-成功集計" 0
  else
    assert_true "実行-成功集計" 1
  fi
  if printf '%s' "$outB" | grep -qF "[FAIL] generation-engine/scripts/a-fail.sh"; then
    assert_true "実行-失敗集計" 0
  else
    assert_true "実行-失敗集計" 1
  fi
  # 失敗-理由が出力に現れる（改善課題: 検証の結果を信用できるようにする 3.1）:
  # a-fail.sh 自身が --self-test で出した "a-case-2" という診断文字列が、
  # 従来は run_all() に捨てられていたが、[FAIL] 行の直後にそのまま現れること。
  if printf '%s' "$outB" | grep -qF "a-case-2"; then
    assert_true "失敗-理由が出力に現れる" 0
  else
    assert_true "失敗-理由が出力に現れる" 1
  fi
  # 成功-出力は追加されない（改善課題: 検証の結果を信用できるようにする 3.2 節の
  # 「成功が続く限り、見え方は従来と変わらない」の検証）:
  # z-after.sh 自身が --self-test で出す "z-after-ran-marker" は、
  # z-after.sh が PASS であるため、[FAIL] 用の追加出力には現れない。
  if printf '%s' "$outB" | grep -qF "z-after-ran-marker"; then
    assert_true "成功-出力は追加されない" 1
  else
    assert_true "成功-出力は追加されない" 0
  fi
  if [ -f "$scanB/.z-after-ran" ]; then
    assert_true "実行-継続" 0
  else
    assert_true "実行-継続" 1
  fi
  [ "$rcB" -eq 1 ] && assert_true "終了コード-失敗時" 0 || assert_true "終了コード-失敗時" 1

  # 判定不能-集約の終了コードを保持: 判定不能だけがあり失敗が無い場合、
  # 集約は2を返すこと。実行できなかったことを合格にも不合格にも変換しない。
  local scanBU outBU rcBU
  scanBU="$tmp/repoBU/generation-engine/scripts"
  mkdir -p "$scanBU"
  cp "$scanB/b-unknown.sh" "$scanBU/b-unknown.sh"
  cat > "$scanBU/c-benign-error-words.sh" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "[UNKNOWN] 権限を確認できません 操作: test -w / 想定原因: permission error in fixture"
  echo "diagnostic: 0 errors"
  exit 2
fi
exit 0
EOS
  cat > "$scanBU/z-ok.sh" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  echo "  [PASS] z-ok-case"
  exit 0
fi
exit 0
EOS
  chmod +x "$scanBU"/*.sh
  outBU="$(run_all "$tmp/repoBU" "/dev/null/no-such-self" 30)"
  rcBU=$?
  if [ "$rcBU" -eq 2 ] \
    && printf '%s' "$outBU" | grep -qE '判定不能 2 本' \
    && printf '%s' "$outBU" | grep -qF '[UNKNOWN] generation-engine/scripts/c-benign-error-words.sh' \
    && printf '%s' "$outBU" | grep -qF 'diagnostic: 0 errors'; then
    assert_true "判定不能-集約の終了コード2を保持" 0
  else
    assert_true "判定不能-集約の終了コード2を保持" 1
  fi

  # --- フィクスチャ準備（repoC: 途中停止の疑いの検証用） ---
  local scanC="$tmp/repoC/generation-engine/scripts"
  mkdir -p "$scanC"
  cp "$scanA/tests/quiet.sh" "$scanC/quiet.sh"
  chmod +x "$scanC/quiet.sh"

  local outC
  outC="$(run_all "$tmp/repoC" "/dev/null/no-such-self" 30)"
  if printf '%s' "$outC" | grep -qF "[SUSPECT] generation-engine/scripts/quiet.sh"; then
    assert_true "途中停止-検出" 0
  else
    assert_true "途中停止-検出" 1
  fi

  # --- フィクスチャ準備（repoD: 時間上限の検証用） ---
  # slow.sh は上限（2秒）を超えて走り続け、quick.sh は上限より短く終わる。
  local scanD="$tmp/repoD/generation-engine/scripts"
  mkdir -p "$scanD"

  cat > "$scanD/slow.sh" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  sleep 30
  echo "  [PASS] slow-case-should-not-print"
  exit 0
fi
exit 0
EOS

  cat > "$scanD/quick.sh" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  sleep 0.3
  echo "  [PASS] quick-case"
  exit 0
fi
exit 0
EOS

  chmod +x "$scanD"/*.sh

  local outD rcD
  outD="$(run_all "$tmp/repoD" "/dev/null/no-such-self" 2)"
  rcD=$?

  if printf '%s' "$outD" | grep -qF "[TIMEOUT] generation-engine/scripts/slow.sh"; then
    assert_true "上限-打ち切り" 0
  else
    assert_true "上限-打ち切り" 1
  fi
  if printf '%s' "$outD" | grep -qF "[PASS] generation-engine/scripts/quick.sh"; then
    assert_true "上限-完走は影響なし" 0
  else
    assert_true "上限-完走は影響なし" 1
  fi
  [ "$rcD" -eq 1 ] && assert_true "上限-終了コード" 0 || assert_true "上限-終了コード" 1

  # 宣言済み長時間実行スクリプトの判定関数そのものの検証
  local declaredKnown declaredUnknown
  declaredKnown="$(declared_long_running_timeout "/x" "/x/generation-engine/scripts/audit-consistency.sh")"
  [ "$declaredKnown" = "200" ] && assert_true "長時間宣言-登録対象" 0 || assert_true "長時間宣言-登録対象" 1
  declaredUnknown="$(declared_long_running_timeout "/x" "/x/generation-engine/scripts/unrelated-script.sh")"
  [ -z "$declaredUnknown" ] && assert_true "長時間宣言-未登録は空" 0 || assert_true "長時間宣言-未登録は空" 1

  # declared_long_running_known() 判定関数そのものの検証
  local knownYes knownRc
  knownYes="$(declared_long_running_known "/x" "/x/generation-engine/scripts/build-portal.sh")"
  knownRc=$?
  [ -z "$knownYes" ] && [ "$knownRc" -ne 0 ] \
    && assert_true "宣言済み既知対象-現在0件" 0 || assert_true "宣言済み既知対象-現在0件" 1
  declared_long_running_known "/x" "/x/generation-engine/scripts/unrelated-script.sh" >/dev/null
  [ $? -ne 0 ] && assert_true "宣言済み既知対象-未登録は非0" 0 || assert_true "宣言済み既知対象-未登録は非0" 1

  # --- フィクスチャ準備（repoE: declared_long_running_timeout の個別上限
  #     適用の検証用） ---
  # ファイル名を declared_long_running_timeout() の登録名（相対パス）と一致
  # させ、既定の1秒上限では打ち切られる1.5秒の実行が、宣言側の200秒上限
  # 適用によりTIMEOUTにならずPASSすることを確認する。
  local scanE="$tmp/repoE/generation-engine/scripts"
  mkdir -p "$scanE"

  cat > "$scanE/audit-consistency.sh" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  sleep 1.5
  echo "  [PASS] declared-long-running-case"
  exit 0
fi
exit 0
EOS
  chmod +x "$scanE/audit-consistency.sh"

  local outE
  outE="$(run_all "$tmp/repoE" "/dev/null/no-such-self" 1)"
  if printf '%s' "$outE" | grep -qF "[PASS] generation-engine/scripts/audit-consistency.sh"; then
    assert_true "長時間宣言-上限適用でTIMEOUT回避" 0
  else
    assert_true "長時間宣言-上限適用でTIMEOUT回避" 1
  fi

  # --- フィクスチャ準備（repoF: declared_long_running_known の
  #     DECLARED-LONG 分類の検証用） ---
  # テスト専用の override で build-portal.sh だけを既知対象として扱い、
  # 既定の1秒上限を超える1.5秒の実行が TIMEOUT ではなく
  # [DECLARED-LONG] として記録され、それが唯一の異常でも run_all() の
  # 終了コードが0のまま（途中停止の疑い・打ち切りいずれにも数えない）
  # ことを確認する。
  local scanF="$tmp/repoF/generation-engine/scripts"
  mkdir -p "$scanF"

  cat > "$scanF/build-portal.sh" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--self-test" ]; then
  sleep 1.5
  echo "  [PASS] declared-long-known-case-should-not-print"
  exit 0
fi
exit 0
EOS
  chmod +x "$scanF/build-portal.sh"

  # 本番の登録が0件であることとは独立して分類ロジックを検証するための、
  # self-test ローカルの override。実対象を case arm に再登録しない。
  local self_test_declared_rel="generation-engine/scripts/build-portal.sh"
  declared_long_running_known() {
    local repo="$1" abs="$2" rel
    rel="$abs"
    case "$rel" in
      "$repo"/*) rel="${rel#"$repo"/}" ;;
    esac
    if [ "$rel" = "$self_test_declared_rel" ]; then
      echo 1
      return 0
    fi
    return 1
  }

  # 上限の宣言も同じ理由で override する。fixture は本番と同じ相対パスを使う
  # ため、本番側で build-portal.sh へ長い上限を登録すると、この fixture の
  # sleep が完走してしまい打ち切りが起きず、分類ロジックを検証できなくなる
  # （実測 2026-08-24: 本番へ 200 秒を登録した際にこのケースだけが落ちた）。
  # fixture には既定の上限を使わせ、本番の登録から独立に検証する。
  declared_long_running_timeout() {
    local repo="$1" abs="$2" rel
    rel="$abs"
    case "$rel" in
      "$repo"/*) rel="${rel#"$repo"/}" ;;
    esac
    [ "$rel" = "$self_test_declared_rel" ] && return 0
    return 0
  }

  local outF rcF
  outF="$(run_all "$tmp/repoF" "/dev/null/no-such-self" 1)"
  rcF=$?
  if printf '%s' "$outF" | grep -qF "[DECLARED-LONG] generation-engine/scripts/build-portal.sh"; then
    assert_true "宣言済み既知対象-DECLARED-LONG分類" 0
  else
    assert_true "宣言済み既知対象-DECLARED-LONG分類" 1
  fi
  if printf '%s' "$outF" | grep -qF "[TIMEOUT] generation-engine/scripts/build-portal.sh"; then
    assert_true "宣言済み既知対象-TIMEOUTにしない" 1
  else
    assert_true "宣言済み既知対象-TIMEOUTにしない" 0
  fi
  [ "$rcF" -eq 0 ] && assert_true "宣言済み既知対象-終了コードに影響しない" 0 \
    || assert_true "宣言済み既知対象-終了コードに影響しない" 1

  rm -rf "$tmp"
  trap - EXIT
  echo "実行 $((pass + fail)) 件 / 成功 $pass 件 / 失敗 $fail 件"
  [ "$fail" -eq 0 ]
}

usage() {
  cat <<'EOS'
使い方: run-layer-machine-checks.sh [--repo <リポジトリのパス>] [--list] [--self-test]
                                     [--timeout <秒>]
EOS
}

main() {
  local repo="" list_only=0 self_test_mode=0 timeout_sec=120

  while [ $# -gt 0 ]; do
    case "$1" in
      --repo)
        repo="${2:-}"
        shift 2
        ;;
      --list)
        list_only=1
        shift
        ;;
      --self-test)
        self_test_mode=1
        shift
        ;;
      --timeout)
        timeout_sec="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "不明な引数: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
  done

  case "$timeout_sec" in
    ''|*[!0-9]*)
      echo "--timeout には正の整数を指定する: $timeout_sec" >&2
      exit 2
      ;;
  esac
  if [ "$timeout_sec" -lt 1 ]; then
    echo "--timeout には正の整数を指定する: $timeout_sec" >&2
    exit 2
  fi

  if [ "$self_test_mode" -eq 1 ]; then
    self_test
    exit $?
  fi

  if [ -z "$repo" ]; then
    repo="$(cd "$SCRIPT_DIR/../../.." && pwd)"
  fi

  if [ "$list_only" -eq 1 ]; then
    local targets t
    targets="$(list_targets "$repo" "$SCRIPT_PATH")"
    if [ -n "$targets" ]; then
      printf '%s\n' "$targets" | while IFS= read -r t; do
        case "$t" in
          "$repo"/*) printf '%s\n' "${t#"$repo"/}" ;;
          *) printf '%s\n' "$t" ;;
        esac
      done
    fi
    exit 0
  fi

  run_all "$repo" "$SCRIPT_PATH" "$timeout_sec"
  exit $?
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main "$@"
fi
