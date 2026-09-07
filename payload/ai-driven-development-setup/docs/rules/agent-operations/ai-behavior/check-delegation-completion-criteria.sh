#!/bin/bash -p
# check-delegation-completion-criteria.sh — 「完了条件を渡す」「外への公開まで AI が行う」
#   「実装の委任は設計の引用を渡す」「提示前に判定役を通す」
#   「判定役への委任は自己検査の結果を添える」の5規則の linter
#
# シェバンは`#!/bin/bash -p`（特権モード）にする（2026-09-06第20版。16回目の
# 反証。check-work-records.shと同じ危険（`BASH_ENV`等によるインタプリタ
# 起動の乗っ取り）を持つのに、フック側だけをシェバン固定の対象にし本体を
# 見落としていた）。
#
# timing: PreToolUse(Agent|Bash)
# timing: Stop
# 対象規約: 人とAIの分担の決まり「完了条件を渡す」「外への公開まで AI が行う」
#   「実装の委任は設計の引用を渡す」「提示前に判定役を通す」
#   「判定役への委任は自己検査の結果を添える」（対応する規則文言は
#   work-records/rule.md「提出前に自己検査を添える」にも同趣旨で重複定義される）
#
# 追加の判定の設計（2026-09-06 第3版。改善指示書の対応で設計書を実装の後に
# 件数だけ合わせる作業が続いた実例を受け行動を機械で止める。第1版（変更語の
# 判定）・第2版（commit時検査）は反証で迂回できると実証され、本体は
# check-work-records.sh側の「設計を先に書いてから実装する」（mainへの
# 取り込み=git merge時の枝差分・判定役の記録）へ移した。ここで扱う2規則は
# その**補助**であり、字面の粗さを埋める役割に限定する:
#
#   実装の委任は設計の引用を渡す — Agent への委任 prompt が docs/skills・
#   docs/design・docs/rules・.claude/skills・.claude/rules・scripts/・
#   templates/ のいずれかのパスの語を含むとき（変更語の判定は廃止）、
#   読み取り専用の担当者（investigator等）は対象外とし、.claude/skills・
#   .claude/rulesだけを対象にした委任は派生の直接編集として拒否する。
#   それ以外は見出し「## 設計の引用」の直下に <パス>#<節>（docs/design/か
#   docs/rules/配下）の行と引用文（40字以上・句点を含む・見出し行や表の
#   区切り行は不可）を求め、引用文が所在のファイルに（空白の揺れを無視して）
#   部分一致で実在するかを見る。
#
#   提示前に判定役を通す — Stop 時点の transcript から最終assistant
#   メッセージの全textブロックを連結して本文とし、(a) 10行以上のコード
#   フェンス、または (b) 原稿・ご確認ください・案・文面・差し替え・
#   プロンプト・スライドの語かフェンス内の「設計」、または (c) 最後の
#   ユーザー発話以降のArtifact(publish)・SendUserFile・AskUserQuestionの
#   tool_use、のいずれかに該当すれば「提示の形」ありと判定する。該当する
#   場合、最後の「本物のユーザー発話」より後に、提示する内容の所在
#   （docs/design/・docs/rules/・scratchpad）をpromptに含み、そのtool_result
#   にPASS・合格・承認可を含む判定役（document-reviewer・
#   adversarial-verifier・code-reviewer）への委任が無ければ違反として
#   blockする。自動解除は無い（下の「止めるか知らせるか」節を参照）。
#
#   判定役への委任は自己検査の結果を添える（2026-09-06新設） — Agent への
#   委任先が code-reviewer・adversarial-verifier・document-reviewer の
#   いずれかのとき、prompt に見出し「## 自己検査の結果」を求める。見出しの
#   直下（次の「## 」見出しまで）に、ヘッダ行が観点・実測したこと・結果・
#   否のときの直しの4列を持つ表を求める。表のデータ行が1件も無ければ拒否
#   する。データ行の4列目（結果列）が「否」で始まる行が1件でもあれば
#   「否が残る成果物は出さない」として拒否する。緊急口は無い
#   （judge_self_check_result・extract_self_check_block・
#   self_check_data_rows）。
#
# 免除の設計判断（2026-09-06）:
#   既存の2規則が持つ緊急口（[DELEGATION-EXEMPT] 明示・
#   DELEGATION_COMPLETION_CRITERIA_SKIP_REASON・孫委任=agent_id付与）は、
#   「完了条件を渡す」判定だけに適用する。「実装の委任は設計の引用を渡す」は
#   これらのいずれでも免除しない（孫委任にも適用する）。本作業が解こうとした
#   問題そのもの（設計先行が守られなかった実例）に対する検査であり、
#   既存の緊急口を流用すると同じ抜け道を再現するため。「提示前に判定役を通す」
#   （Stop）は agent_id・prompt を持たないため、既存の緊急口の対象外である。
#   「外への公開まで AI が行う」も理由付きの緊急口を持たない（2026-09-06
#   改訂で廃止。下の「逃げ道」節を参照）。
#
# 判定の設計:
#   完了条件を渡す — 既存の check-evidence-checklist.sh（PreToolUse(Agent)）が、
#   同じ timing で prompt 内の見出し（## 調査チェックリスト）の有無を検査している。
#   本checkerは検査対象の見出し・語彙を「完了条件」に差し替えたものであり、機構は
#   既存実例とほぼ同一である。
#
#   外への公開まで AI が行う — 実行しようとしている Bash コマンドが、履歴を
#   書き換える強制の送信かどうかを走査する。tool_name が Bash のときにこの判定
#   だけを行い、Agent の判定とは独立して扱う（2026-09-06 改訂。旧規則「外への
#   公開は人がする」は人の指示に無い AI の記述だったため廃止した）。強制の
#   判定には、通常のgit push検出と同じ前置の剥がしとgitオプションの読み飛ばし
#   （_strip_leading_prefixes・_git_subcommand）を適用する。
#
# 判定:
#   完了条件を渡す — Agent への委任 prompt に、完了条件を示す見出し（## 完了条件）
#   または完了条件を明示する語彙（「完了条件」を含む一文）が無ければ違反として
#   block（exit 2）する。
#
#   外への公開まで AI が行う — 強制の送信（--force・-f・--force-with-lease・
#   参照の先頭の +）であれば違反として block（exit 2）する。通常の送信・
#   npm publish 等は止めない。
#
# 検査が見る操作の具体（外への公開まで AI が行う）:
#   git push に強制の指定が付く形だけを止める。ヒアドキュメント本体・引用
#   文字列を除いたうえで区切り、各区切りの先頭の前置（command・exec・nohup・
#   time・xargs・env代入・sudo・busybox・バックスラッシュ・実行ファイルの
#   パス・複合文の開き）を剥がし、_git_subcommandでgit自身のオプションを
#   読み飛ばして副命令を取り、副命令がpushかつ強制の指定を伴う場合だけ拒否する。
#
# 除外条件（誤検知回避）:
#   - tool_name が Agent・Bash のいずれでもない → 対象外
#   - （完了条件を渡す）サブエージェント内部からの再委任（agent_id が付与されている）
#     → 対象外（既存 check-evidence-checklist.sh と同じ判断: 孫委任まで強制すると
#     委任の連鎖のたびに書式強制が増殖する）
#   - （完了条件を渡す）prompt 冒頭 500 文字に [DELEGATION-EXEMPT] 明示 → 対象外
#     （緊急口）
#   - （完了条件を渡す）prompt が空 → 対象外（他 hook の検査対象）
#   - （外への公開まで AI が行う）command が空 → 対象外（他 hook の検査対象）
#
# 止めるか知らせるか:
#   完了条件を渡す: 止める（完了条件を欠いた委任がそのまま実行されると、何を確認すれば完了かを後から復元できなくなるため）
#   外への公開まで AI が行う: 強制の送信だけ止める（書き換えた履歴は取り戻せないため）
#
# 逃げ道:
#   DELEGATION_COMPLETION_CRITERIA_SKIP_REASON に理由を書けば「完了条件を渡す」の
#   判定は通る。理由が空の場合は通らない。
#   外への公開まで AI が行う の判定に緊急口は無い（2026-09-06改訂で廃止）。
#   旧規則「外への公開は人がする」が持っていた、コマンド文字列先頭の理由付き
#   割り当てによる緊急口は、通常の送信を止めなくなったため不要になった。
#   強制の送信は理由の有無によらず常に拒否する。
#
#   環境変数（シェルの `export` や代入によって hook プロセス自身の環境に
#   設定した DELEGATION_COMPLETION_CRITERIA_SKIP_REASON）は使えない。
#   PreToolUse hook はコマンドの実行前に動くサブプロセスであり、これから
#   実行されるコマンドの環境変数を hook プロセス自身は継承しない。この
#   ためコマンド文字列そのものの先頭を走査する方式を取る（「完了条件を渡す」
#   の緊急口に限る）。
#
#   実装の委任は設計の引用を渡す・提示前に判定役を通す・
#   判定役への委任は自己検査の結果を添える には緊急口が無い
#   （上の「免除の設計判断」節を参照）。提示前に判定役を通す は自動解除も
#   持たない。解消する手段は、所在を含み結果が合格の判定役への委任だけ
#   である。判定役への委任は自己検査の結果を添える は、見出しと表を整え
#   否を無くす以外に解消する手段が無い。
#
# 既知の限界:
#   異なる種類の操作を1つの照合の文字列へ並べた例は既存に無く、納品先で2種類とも
#   発火することは実機で確かめていない。
#   外への公開まで AI が行う は、`printf pu%s sh | xargs git` のように、独立した
#   語としての"push"がコマンド文字列の字面に現れず、実行時にprintfとxargsが
#   結合して初めて成立する形は検出できない（字面解析の限界。2026-09-06第8版）。
#   同様に `$(which git) push` のように、命令自体がコマンド置換の結果として
#   実行時にしか定まらない形も検出できない。_git_subcommandは前置を剥がした
#   区切りの第1語が文字列として"git"と一致するかしか見ておらず、
#   コマンド置換を評価しないため（字面解析の限界。2026-09-06第9版）。
#   `bash -c "git push --force"` のように、引用符の中身へコマンド全体を
#   渡す形も検出できない（_strip_heredoc_and_quotesが引用文字列の中身を
#   空にするため）。
#   実装の委任は設計の引用を渡す・提示前に判定役を通す はいずれも補助であり、
#   本体は check-work-records.sh 側（設計を先に書いてから実装する）にある。
#   ここでの拒否は「字面が粗い」ことを示すに過ぎず、通過（対象外・許可）が
#   即座に「設計先行が守られている」ことを意味しない。
#   実装の委任は設計の引用を渡す の「原稿」等の提示語は短い一般語のため、
#   無関係な文脈（「提案」「事案」等の一部）でも一致しうる（過検知は許容し、
#   提示物をファイルに書いて委任すれば解消する設計）。
#   提示前に判定役を通す の自動解除は無い（下の「逃げ道」節を参照）。
#   判定役への委任のtool_result抽出はtool_use_idの対応で行うが、
#   同一transcript内でidが重複する実例は確認していない。
#
# 使い方:
#   フック本体として: PreToolUse(Agent|Bash) または Stop の入力 JSON を stdin から
#     受け取る
#   単体実行: check-delegation-completion-criteria.sh --self-test
set -uo pipefail

judge() {
  # $1: prompt
  # 標準出力: 判定理由。戻り値: 0=許可・2=拒否
  local prompt="$1"

  if printf '%s' "$prompt" | head -c 500 | grep -q '\[DELEGATION-EXEMPT\]'; then
    echo "対象外[完了条件を渡す]: [DELEGATION-EXEMPT] が明示されている"
    return 0
  fi

  if printf '%s' "$prompt" | grep -qE '## 完了条件'; then
    echo "許可[完了条件を渡す]: 見出し「## 完了条件」がある"
    return 0
  fi

  if printf '%s' "$prompt" | grep -qE '完了条件(は|:|：)'; then
    echo "許可[完了条件を渡す]: 「完了条件」を明示する記述がある"
    return 0
  fi

  echo "拒否[完了条件を渡す]: prompt に完了条件の見出しまたは明示的な記述がない"
  return 2
}

# $1: cmd。バックスラッシュ + 改行（LF、またはCR+LF）を、引用の外・中を
# 問わず一律に取り除き、行を結合する。bashの行継続と同じ扱いである
# （2026-09-07 22回目の反証。`git -c core.hooksPa\<改行>th=/dev/null
# merge x`のように、語の途中に実際の改行を挟むと`git`という語が字面に
# 現れず素通りしていた）。全ての判定の最初（`_mask_separators_in_quotes`
# より前）で呼び出す。sentinel（0x1e。既存のマスク文字0x01〜0x04とは
# 重ならない制御文字）を末尾へ直接連結してから1レコードずつ処理することで、
# 「入力の真の末尾にある単独のバックスラッシュ（継続ではない）」と
# 「バックスラッシュの直後に実際の改行がある継続」を区別する。
# 継続でない末尾のバックスラッシュ（例: 生のコマンド文字列が`foo\`で
# 終わる形）は、その直後に何も続かないため素通しする（bash自身も
# この形を継続として扱わない）。check-work-records.sh側の同名関数と
# 同じ振る舞いにする。
#
# 末尾のバックスラッシュは連続数の偶奇で判定する（2026-09-07 第24版・
# 23回目の反証で見つかった見逃し。check-work-records.sh側の同じ変更を
# 参照）。連続数が奇数のときだけ継続として結合する。
_join_line_continuations() {
  local sentinel out
  sentinel=$'\x1e'
  out="$(printf '%s%s' "$1" "$sentinel" | awk '
    {
      line = $0
      hascr = (line ~ /\r$/)
      if (hascr) sub(/\r$/, "", line)
      n = length(line)
      cnt = 0
      while (cnt < n && substr(line, n - cnt, 1) == "\\") cnt++
      if (cnt % 2 == 1) {
        keep = (cnt - 1) / 2
        base = substr(line, 1, n - cnt)
        lit = ""
        for (i = 0; i < keep; i++) lit = lit "\\"
        printf "%s%s", base, lit
      } else {
        keep = cnt / 2
        base = substr(line, 1, n - cnt)
        lit = ""
        for (i = 0; i < keep; i++) lit = lit "\\"
        line = base lit
        if (hascr) line = line "\r"
        printf "%s\n", line
      }
    }
  ')"
  if [ "${out%$'\n'"$sentinel"}" != "$out" ]; then
    out="${out%$'\n'"$sentinel"}"
  else
    out="${out%"$sentinel"}"
  fi
  printf '%s' "$out"
}

# $1: cmd。引用符の文字そのもの（'・"）だけを取り除き、中身は残す
# （ヒアドキュメントの区切りには触れない）。`_strip_heredoc_and_quotes`は
# 引用符の中身ごと空にするため、`'+main:main'`のように引用符の中に検出対象
# の文字列そのものが入っている形（先頭+・空の左辺:<参照>）を検出できない。
# 本関数は引用符の文字だけを削り中身の文字は残すため、この回避を内容を
# 消さずに検出できる（2026-09-06第11版新設。check-work-records.sh側の
# 同名関数と同じ振る舞いにする）。
# 続けて、語の途中のバックスラッシュ（`gi\t`・`me\rge`・`re\flog`のように
# 英数字の直前にあるバックスラッシュ）を取り除く（2026-09-06 21回目の反証。
# bashは`gi\t`を`git`として解決するが、字面の判定は`gi\t`のままでは
# `git`という語に一致しない）。`\;`・`\|`・`\&`・`\"`・`\'`・`\\`・`\$`は、
# 直後の文字が英数字でないため対象外のまま残る。行末の`\`（改行を伴う継続）
# は、この関数より前に`_join_line_continuations`が結合するため、この関数へ
# 到達する時点では既に消えている。
_strip_quote_marks_only() {
  printf '%s' "$1" | tr -d "\"'" | sed -E 's/\\([A-Za-z0-9])/\1/g'
}

# $1: cmd。ヒアドキュメント本体（<<DELIM の次行からDELIM行まで。起動行は
# 残す）と引用文字列（'...'・"..."。区切り文字は残し中身だけ空にする）を
# 取り除いた文字列を返す。コード例・コメントの中に現れる語（例:
# "push @candidates"）を実行される git のコマンドと誤認しないための下ごしらえ
# （2026-09-06第6版）。引用符の中身を空にしたあと、語の途中のバックスラッシュ
# （`gi\t`等）を取り除く（2026-09-06 21回目の反証。`_strip_quote_marks_only`
# と同じ理由）。
_strip_heredoc_and_quotes() {
  local cmd="$1" stripped
  stripped="$(printf '%s\n' "$cmd" | awk '
    BEGIN { in_heredoc = 0; delim = "" }
    {
      if (in_heredoc) {
        if ($0 == delim) { in_heredoc = 0 }
        next
      }
      line = $0
      if (match(line, /<<-?[[:space:]]*[\x27"]?[A-Za-z_][A-Za-z0-9_]*[\x27"]?/)) {
        d = substr(line, RSTART, RLENGTH)
        gsub(/<<-?[[:space:]]*/, "", d)
        gsub(/[\x27"]/, "", d)
        delim = d
        in_heredoc = 1
      }
      print line
    }
  ')"
  printf '%s' "$stripped" | sed -E "s/'[^']*'/''/g; s/\"[^\"]*\"/\"\"/g" | sed -E 's/\\([A-Za-z0-9])/\1/g'
}

# $1: seg（区切り済みの1コマンド）。先頭から `command`・`exec`・`nohup`・
# `time`・`xargs`・`env`（とその `VAR=val` の代入）・`sudo`・`busybox`・
# バックスラッシュ・実行ファイルのパス（絶対パス`/usr/bin/git`・相対パス
# `./x/git`・`../x/git`・チルダ`~/bin/git`。スラッシュが1個だけの`./git`・
# `../git`・`~/git`も含む → いずれも最後の`/`より後を命令にする）・
# 複合文の開き（`{`・`(`・`if`・`for`・`while`・`until`・`case`・`then`・
# `do`・`else`・`elif`）の前置を、変化が無くなるまで繰り返し剥がした文字列を
# 返す（2026-09-06第7版反証: `command git push`・`exec git push`・
# `nohup git push`・`time git push`・`/usr/bin/git push`・`\git push`・
# `xargs git push`・`env GIT_DIR=x git push` のいずれも、前置を剥がさない
# 旧実装では区切りの先頭の `git` 判定を逃れていた。2026-09-06第8版で
# `./tools/git push`・`~/bin/git push`・`{ git push; }`・
# `if true; then git push; fi`・`busybox git push`・`( git push )` も同様に
# 前置を剥がして判定する。2026-09-06第9版でスラッシュ1個のパス前置
# （`./git push`・`~/git push`）を追加し、rule.mdの検査列の記述に合わせた）。
# sedの`\b`（単語境界）はBSD sed（macOS）で機能しないため使わない。
# check-work-records.sh側の同名関数と、この関数の本体はバイト単位で
# 同一に保つ（共有ライブラリへは移動せず2か所に同名関数を置く）。
# 2026-09-07 23回目の反証で、`nice`・`timeout`が自分自身の必須引数
# （`-n 5`・`5`）を消費する前置として一覧に無いことが実測された
# （finding1a。check-work-records.sh側の同じ変更を参照）。
_strip_leading_prefixes() {
  local s="$1" prev
  s="$(printf '%s' "$s" | sed -E 's/^[[:space:]]+//')"
  prev=""
  while [ "$s" != "$prev" ]; do
    prev="$s"
    s="$(printf '%s' "$s" | sed -E 's/^(command([[:space:]]+-p)?|exec|nohup|time|xargs|sudo|env|busybox|setsid|chronic)[[:space:]]+//; s/^nice([[:space:]]+-n[[:space:]]*[0-9]+)?[[:space:]]+//; s/^timeout([[:space:]]+(--signal=[^[:space:]]+|-s[[:space:]]+[^[:space:]]+|-k[[:space:]]+[^[:space:]]+))*[[:space:]]+[0-9][0-9.]*[A-Za-z]?[[:space:]]+//; s/^ionice([[:space:]]+(-c[[:space:]]*[0-9]+|-n[[:space:]]*[0-9]+|-t))*[[:space:]]+//; s/^stdbuf([[:space:]]+-[oei][^[:space:]]*)*[[:space:]]+//; s/^caffeinate([[:space:]]+-[a-z]+)*([[:space:]]+-[tw][[:space:]]+[0-9]+)*[[:space:]]+//; s/^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]()]*[[:space:]]+//; s/^\\+//; s/^(\{|\(|then|do|else|if|for|while|until|case|elif)[[:space:]]+//; s#^(/|\./|\.\./|~/)([^[:space:]]*/)?([A-Za-z0-9_.-]+)#\3#')"
    s="$(printf '%s' "$s" | sed -E 's/^[[:space:]]+//')"
  done
  printf '%s' "$s"
}

# $1: seg（前置を剥がした区切り。_strip_leading_prefixesの出力）。命令が
# gitのとき、副命令の前にあるgit自身のオプション（`-`で始まる語は読み飛ばす。
# `-C`・`-c`・`--git-dir`・`--work-tree`・`--namespace`・`--exec-path`は
# `=`を含まなければ次の語も読み飛ばす）を読み飛ばし、副命令から末尾までを
# 空白区切りで再結合して返す（副命令の1語だけでなく残りの引数も返す。
# `reflog expire`・`config --get`のように副命令＋直後の語で判定する
# 呼び出し元があるため）。check-work-records.sh側の同名関数と、この関数の
# 本体はバイト単位で同一に保つ（共有ライブラリへは移動せず2か所に同名関数を
# 置く）。命令がgitでない、または副命令が無ければ戻り値1
# （2026-09-06第9版新設。`git -C /x push`・`git -c a=b push`・
# `git --git-dir=x push`・`git --no-pager push`のいずれもgit自身のオプションを
# 挟むが、本関数で読み飛ばして副命令pushを正しく取る）。
_git_subcommand() {
  local s="$1"
  local -a words=()
  read -ra words <<< "$s"
  local n="${#words[@]}"
  [ "$n" -eq 0 ] && return 1
  [ "${words[0]}" = "git" ] || return 1
  local i=1
  while [ "$i" -lt "$n" ]; do
    case "${words[$i]}" in
      -C|-c|--git-dir|--work-tree|--namespace|--exec-path)
        i=$((i + 2))
        ;;
      --git-dir=*|--work-tree=*|--namespace=*|--exec-path=*)
        i=$((i + 1))
        ;;
      -*)
        i=$((i + 1))
        ;;
      *)
        break
        ;;
    esac
  done
  [ "$i" -ge "$n" ] && return 1
  local out="" k
  k=$i
  while [ "$k" -lt "$n" ]; do
    if [ -z "$out" ]; then out="${words[$k]}"; else out="${out} ${words[$k]}"; fi
    k=$((k + 1))
  done
  printf '%s' "$out"
  return 0
}

# $1: 走査対象の文字列（cmd本体、または引用符の文字だけを取り除いた版）。
# git push の force相当（--force・-f・--force-with-lease・--force-if-includes・
# --mirror・--delete・-d・--prune）、参照の先頭の+、空の左辺（:<参照>）の
# いずれかがあれば真を返す（2026-09-06第12版: --force-if-includes・
# --pruneを追加。前者は--forceとの前方一致だけでは境界判定に一致しないため
# 見逃していた）。
_jep_scan_for_force() {
  local src="$1" stripped seg seg_stripped sub subcmd
  stripped="$(_strip_heredoc_and_quotes "$src")"
  while IFS= read -r seg; do
    seg_stripped="$(_strip_leading_prefixes "$seg")"
    sub="$(_git_subcommand "$seg_stripped")" || continue
    subcmd="$(printf '%s' "$sub" | awk '{print $1}')"
    [ "$subcmd" = "push" ] || continue
    if printf '%s' "$sub" | grep -qE '([[:space:]]|^)(--force-if-includes|--force-with-lease|--force|-f|--mirror|--delete|--prune)([[:space:]=]|$)' \
      || printf '%s' "$sub" | grep -qE '([[:space:]]|^)-d([[:space:]]|$)' \
      || printf '%s' "$sub" | grep -qE '[[:space:]]\+[^[:space:]]' \
      || printf '%s' "$sub" | grep -qE '(^|[[:space:]]):[A-Za-z0-9_./-]'; then
      return 0
    fi
  done < <(printf '%s\n' "$stripped" | sed -E 's/(&&|\|\||;|\|)/\n/g')
  return 1
}

judge_external_publish() {
  # $1: cmd
  # 標準出力: 判定理由。戻り値: 0=許可・2=拒否
  # 2026-09-06 改訂: 規則「外への公開は人がする」を廃止し、統合先へ送る操作は
  # AI が行う。止めるのは履歴を書き換える強制の送信（--force・-f・
  # --force-with-lease・--mirror・--delete・-d・参照の先頭の +・空の左辺
  # :<参照>）だけ。強制の判定にも、通常のgit push検出
  # （_strip_heredoc_and_quotes・_strip_leading_prefixes・_git_subcommand）と
  # 同じ前置の剥がしとgitオプションの読み飛ばしを適用する。以前は'git'と
  # 'push'がコマンド文字列のどこかにそれぞれ現れるだけで拒否しており、
  # コメント・引用文字列・ヒアドキュメント内の文字列や、無関係な2つの
  # コマンドの組み合わせ（例: `echo git && echo push`）まで誤って拒否
  # していた。npm/yarn/pnpm・docker・ghの判定は行わない（公開の拒否そのものを
  # 廃止したため）。内部を指す語・無効化の経路の照合と同じく、剥がす前の
  # cmdと、引用符の文字だけを取り除いたcmd_nqの両方に対して照合し、どちらか
  # で当たれば当たりとする（`git push origin '+main:main'`のように引用符の
  # 中に検出対象の文字列そのものが入っている形を、内容を消さずに検出する
  # ため。2026-09-06第11版）。
  local cmd="$1" cmd_nq
  # 全ての正規化の最初に行継続を結合する（2026-09-07 22回目の反証）。
  cmd="$(_join_line_continuations "$cmd")"

  if _jep_scan_for_force "$cmd"; then
    echo "拒否[外への公開まで AI が行う]: 強制の送信は履歴を書き換えるため行わない。新しい記録を重ねる形に直してから送る"
    return 2
  fi
  cmd_nq="$(_strip_quote_marks_only "$cmd")"
  if _jep_scan_for_force "$cmd_nq"; then
    echo "拒否[外への公開まで AI が行う]: 強制の送信は履歴を書き換えるため行わない。新しい記録を重ねる形に直してから送る"
    return 2
  fi

  echo "許可[外への公開まで AI が行う]: 強制の送信は見当たらない"
  return 0
}

# 全角スペース・半角スペース・タブ・改行・バッククォートを取り除く（空白の揺れを
# 無視した部分一致を行うための正規化）。標準入力を受け標準出力へ返す。
normalize_ws() {
  tr -d ' \t\n\r`' | sed 's/　//g'
}

# $1: 引用文  $2: ファイルの絶対パス。空白（全角含む）とバッククォートの揺れを
# 無視した部分一致で、ファイル内容に引用文があるかを判定する。
quote_found_in_file() {
  local quote="$1" file="$2" norm_quote norm_file
  [ -f "$file" ] || return 1
  norm_quote="$(printf '%s' "$quote" | normalize_ws)"
  [ -z "$norm_quote" ] && return 1
  norm_file="$(normalize_ws < "$file")"
  printf '%s' "$norm_file" | grep -qF -- "$norm_quote"
}

# $1: cwd。git のリポジトリルートを返す。git 管理外・失敗時は $1 をそのまま返す。
resolve_repo_root() {
  local cwd="$1" root
  root="$(cd "$cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$root" ] && printf '%s' "$root" || printf '%s' "$cwd"
}

# $1: prompt。見出し「## 設計の引用」の直後から次の「## 」見出し（または末尾）
# までのブロック本文を返す。見出しが無ければ空文字を返す。
extract_design_quote_block() {
  printf '%s\n' "$1" | awk '
    /^## 設計の引用/ { found=1; next }
    found && /^## / { exit }
    found { print }
  '
}

# $1: ブロック本文。最初の非空行（<パス>#<節> の行を想定）を返す。
design_quote_location_line() {
  printf '%s\n' "$1" | grep -m1 -E '[^[:space:]]' || true
}

# $1: 行。見出し行（#始まり）または表の区切り行（|・-・:・空白だけで構成）
# なら真を返す（引用として認めない行）。
_is_disallowed_quote_line() {
  local line="$1"
  case "$line" in
    \#*) return 0 ;;
  esac
  printf '%s' "$line" | grep -qE '^[[:space:]]*\|?[-:[:space:]|]+\|?[[:space:]]*$' && return 0
  return 1
}

# $1: ブロック本文。最初の非空行（所在の行）を除いた、以降の非空行のうち
# 見出し行・表の区切り行を除いたものを改行で結合して返す。各行先頭の
# 「引用:」は取り除く（コードレビュー指摘2026-09-06: 見出し・区切り行での
# 字数稼ぎを許さない）。
design_quote_text() {
  local block="$1" first_seen=0 out="" line stripped
  while IFS= read -r line; do
    case "$line" in
      *[![:space:]]*) : ;;
      *) continue ;;
    esac
    if [ "$first_seen" -eq 0 ]; then
      first_seen=1
      continue
    fi
    _is_disallowed_quote_line "$line" && continue
    stripped="${line#引用:}"
    stripped="$(printf '%s' "$stripped" | sed -E 's/^[[:space:]]+//')"
    if [ -z "$out" ]; then out="$stripped"; else out="${out}
${stripped}"; fi
  done <<EOF
$block
EOF
  printf '%s' "$out"
}

# $1: subagent_type。設計の引用を課さない読み取り専用の担当者なら真。
is_read_only_subagent() {
  case "$1" in
    investigator|researcher|code-reviewer|document-reviewer|adversarial-verifier|plan-comprehension-prober|report-reviewer) return 0 ;;
    *) return 1 ;;
  esac
}

# 「実装の委任は設計の引用を渡す」規則の判定。2026-09-06改訂: 変更語（直す/
# 足す等）の判定を廃止しパスの語だけで対象を決める。反証所見で否定文
# （「変更はしない」）の誤検知・活用形の見逃し・スラッシュ無しの見逃しが
# 実証されたため。読み取り専用の担当者は対象外（設計の引用は実装の委任に
# 課すもの）。所在は docs/design/ か docs/rules/ に限り（本体である「順序の
# 強制」に合わせる。SKILL.md や scripts を所在にしない）、引用は40字以上・
# 句点を含み・見出し/表の区切り行を除いた本文であることを求める。
judge_design_quote() {
  # $1: prompt  $2: cwd  $3: subagent_type（空可）
  # 標準出力: 判定理由。戻り値: 0=許可（対象外含む）・2=拒否
  local prompt="$1" cwd="$2" subagent_type="${3:-}"

  if is_read_only_subagent "$subagent_type"; then
    echo "対象外[実装の委任は設計の引用を渡す]: 読み取り専用の担当者（${subagent_type}）への委任"
    return 0
  fi

  if ! printf '%s' "$prompt" | grep -qE '(docs/skills|docs/design|docs/rules|\.claude/skills|\.claude/rules|scripts/|templates/)'; then
    echo "対象外[実装の委任は設計の引用を渡す]: docs/skills・docs/design・docs/rules・.claude/skills・.claude/rules・scripts/・templates/のいずれの文字列も無い"
    return 0
  fi

  # 派生（.claude/skills・.claude/rules）だけを対象にした委任は、設計の引用
  # ではなく「定義（docs/）を直せ」で止める（2026-09-06第3版E: 派生は
  # docs/から生成される一方通行の生成物であり、直接編集する運用を許さない）。
  if printf '%s' "$prompt" | grep -qE '\.claude/(skills|rules)' \
    && ! printf '%s' "$prompt" | grep -qE '(docs/skills|docs/rules)'; then
    echo "拒否[実装の委任は設計の引用を渡す]: .claude/skills・.claude/rulesは定義から生成される派生です。定義（docs/skills・docs/rules）を直してから派生を再生成してください"
    return 2
  fi

  if ! printf '%s' "$prompt" | grep -qE '^## 設計の引用'; then
    echo "拒否[実装の委任は設計の引用を渡す]: 見出し「## 設計の引用」がない"
    return 2
  fi

  local block loc quote path root full_path
  block="$(extract_design_quote_block "$prompt")"
  loc="$(design_quote_location_line "$block")"
  if [ -z "$loc" ] || ! printf '%s' "$loc" | grep -qF '#'; then
    echo "拒否[実装の委任は設計の引用を渡す]: 「## 設計の引用」の直下に <パス>#<節> の行がない"
    return 2
  fi

  quote="$(design_quote_text "$block")"
  if [ -z "$quote" ]; then
    echo "拒否[実装の委任は設計の引用を渡す]: 引用文がない"
    return 2
  fi
  if [ "${#quote}" -lt 40 ] || ! printf '%s' "$quote" | grep -qF '。'; then
    echo "拒否[実装の委任は設計の引用を渡す]: 引用は40字以上かつ句点を含む必要があります"
    return 2
  fi

  path="${loc%%#*}"
  path="$(printf '%s' "$path" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  case "$path" in
    docs/design/*|docs/rules/*) : ;;
    *)
      echo "拒否[実装の委任は設計の引用を渡す]: 所在は docs/design/ または docs/rules/ 配下に限ります（${path}）"
      return 2
      ;;
  esac
  root="$(resolve_repo_root "$cwd")"
  full_path="${root}/${path}"

  if ! quote_found_in_file "$quote" "$full_path"; then
    echo "拒否[実装の委任は設計の引用を渡す]: 引用が ${full_path} に無い"
    return 2
  fi

  echo "許可[実装の委任は設計の引用を渡す]: 設計の引用が ${full_path} に実在する"
  return 0
}

# $1: prompt  $2: subagent_type。判定役（document-reviewer・
# adversarial-verifier・code-reviewer）への委任で、promptがdocs/design/・
# docs/rules/への言及を含む場合、「## レビュー対象」見出しとその直下の
# パスの行を必須にする（2026-09-06第4版・反証所見: promptにパスの文字列が
# 含まれるだけでは「そのパスをレビュー対象として渡した」ことを字面では
# 判定できず、Stop側のreview_agent_used_after_indexのcontains判定が
# 無関係な言及まで合格の根拠にしてしまいうる。委任の時点で構造化された
# 見出しを強制することで、後段の判定に使える確実な手がかりを作る）。
# 標準出力: 判定理由。戻り値: 0=許可（対象外含む）・2=拒否
judge_review_target_heading() {
  local prompt="$1" subagent_type="${2:-}"
  case "$subagent_type" in
    document-reviewer|adversarial-verifier|code-reviewer) : ;;
    *)
      echo "対象外[レビュー対象の明記]: 判定役への委任でない（${subagent_type}）"
      return 0
      ;;
  esac
  if ! printf '%s' "$prompt" | grep -qE '(docs/design/|docs/rules/)'; then
    echo "対象外[レビュー対象の明記]: docs/design/・docs/rules/への言及が無い"
    return 0
  fi
  if ! printf '%s' "$prompt" | grep -qE '^## レビュー対象'; then
    echo "拒否[レビュー対象の明記]: 見出し「## レビュー対象」がない"
    return 2
  fi
  local target_line
  target_line="$(printf '%s' "$prompt" | awk '/^## レビュー対象/{f=1;next} f && NF{print; exit}')"
  if [ -z "$target_line" ]; then
    echo "拒否[レビュー対象の明記]: 「## レビュー対象」の直下にパスの行がない"
    return 2
  fi
  echo "許可[レビュー対象の明記]: レビュー対象の行がある（${target_line}）"
  return 0
}

# $1: prompt。見出し「## 自己検査の結果」の直後から次の「## 」見出し（または
# 末尾）までのブロック本文を返す（extract_design_quote_blockと同型）。
extract_self_check_block() {
  printf '%s\n' "$1" | awk '
    /^## 自己検査の結果/ { found=1; next }
    found && /^## / { exit }
    found { print }
  '
}

# $1: ブロック本文。表のデータ行（先頭が|の行から、ヘッダ行と区切り行
# （|---|等）を除いたもの）を1行ずつ返す。_is_disallowed_quote_lineを
# 区切り行の判定に再利用する（judge_design_quoteと同じ判定基準）。
self_check_data_rows() {
  local block="$1" header_seen=0 line
  while IFS= read -r line; do
    case "$line" in
      \|*) : ;;
      *) continue ;;
    esac
    _is_disallowed_quote_line "$line" && continue
    if [ "$header_seen" -eq 0 ]; then
      header_seen=1
      continue
    fi
    printf '%s\n' "$line"
  done <<EOF
$block
EOF
}

# 「判定役への委任は自己検査の結果を添える」規則の判定。code-reviewer・
# adversarial-verifier・document-reviewerへの委任prompt に見出し
# 「## 自己検査の結果」と、観点・実測したこと・結果・否のときの直しの4列を
# 持つ表を求める。表のデータ行が1件も無ければ拒否する。データ行の4列目
# （結果列）は「合」または「対象外」の許可制にする。それ以外（「否」・
# 「×」・「不合格」・「NG」・「要確認」・空・その他）の値が1件でもあれば
# 拒否する（2026-09-06新設: work-records/rule.md「提出前に自己検査を添える」・
# ai-behavior/rule.md「判定役への委任は自己検査の結果を添える」に対応する
# 検査。緊急口は無い。13回目の反証: 「否」で始まるかどうかだけを見る旧実装
# では、「×」「不合格」「要確認」「空」等が素通りした。結果列の値を許可制
# （「合」「対象外」以外はすべて拒否）へ改めた）。
judge_self_check_result() {
  # $1: prompt  $2: subagent_type
  # 標準出力: 判定理由。戻り値: 0=許可（対象外含む）・2=拒否
  local prompt="$1" subagent_type="${2:-}"
  case "$subagent_type" in
    code-reviewer|adversarial-verifier|document-reviewer) : ;;
    *)
      echo "対象外[判定役への委任は自己検査の結果を添える]: 判定役への委任でない（${subagent_type}）"
      return 0
      ;;
  esac

  if ! printf '%s' "$prompt" | grep -qE '^## 自己検査の結果'; then
    echo "拒否[判定役への委任は自己検査の結果を添える]: 見出し「## 自己検査の結果」が無い"
    return 2
  fi

  local block header_line
  block="$(extract_self_check_block "$prompt")"
  header_line="$(printf '%s\n' "$block" | grep -m1 -E '^\|')"
  if [ -z "$header_line" ] \
    || ! printf '%s' "$header_line" | grep -qF '観点' \
    || ! printf '%s' "$header_line" | grep -qF '実測したこと' \
    || ! printf '%s' "$header_line" | grep -qF '結果' \
    || ! printf '%s' "$header_line" | grep -qF '否のときの直し'; then
    echo "拒否[判定役への委任は自己検査の結果を添える]: 見出しの直下に観点・実測したこと・結果・否のときの直しの4列を持つ表が無い"
    return 2
  fi

  local rows row_count=0 has_deny=0 row cell3 bad_value=""
  rows="$(self_check_data_rows "$block")"
  while IFS= read -r row; do
    case "$row" in
      *[![:space:]]*) : ;;
      *) continue ;;
    esac
    row_count=$((row_count + 1))
    cell3="$(printf '%s' "$row" | awk -F'|' '{print $4}' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    case "$cell3" in
      合|対象外) : ;;
      *) has_deny=1; bad_value="$cell3" ;;
    esac
  done <<EOF
$rows
EOF

  if [ "$row_count" -eq 0 ]; then
    echo "拒否[判定役への委任は自己検査の結果を添える]: 表にデータ行が無い"
    return 2
  fi

  if [ "$has_deny" -eq 1 ]; then
    echo "拒否[判定役への委任は自己検査の結果を添える]: 結果列の値が「合」「対象外」のいずれでもない行がある（値: ${bad_value}）"
    return 2
  fi

  echo "許可[判定役への委任は自己検査の結果を添える]: 自己検査の結果の表があり否が無い"
  return 0
}

# transcript（JSONL）の最後の「本物のユーザー発話」の0始まりインデックスを返す
# （tool_result だけの user エントリは除く。無ければ -1）。
last_real_user_index() {
  jq -s '
    def is_real_user: .type=="user" and (
      (.message.content|type)=="string" or
      ((.message.content|type)=="array" and (([.message.content[]?.type] | index("tool_result"))==null))
    );
    [ to_entries[] | select(.value|is_real_user) | .key ] | (if length>0 then .[-1] else -1 end)
  ' "$1" 2>/dev/null
}

# $1: transcriptパス  $2: 開始インデックス。これより大きいインデックスの
# assistant tool_use の中に、subagent_type が document-reviewer・
# adversarial-verifier・code-reviewer のいずれかであり、prompt に提示する
# 内容の所在（docs/design/・docs/rules/・$TMPDIR配下のscratchpad）を含み、
# かつそのtool_use_id対応のtool_resultにPASS・合格・承認可のいずれかを
# 含むAgent呼び出しがあるかを判定する（2026-09-06 第3版・code-reviewer指摘:
# 提示物をファイルに書いてから委任する運用を機械で裏付け、judge_design_quote
# の所在許容（docs/design/・docs/rules/）と一致させる。委任の実在だけでなく
# 結果の合格も求める）。
review_agent_used_after_index() {
  local tp="$1" idx="${2:--1}" tmpdir found
  tmpdir="${TMPDIR:-/tmp}"
  tmpdir="${tmpdir%/}"
  found="$(jq -s --argjson idx "$idx" --arg tmpdir "$tmpdir" '
    def path_re: "docs/design/|docs/rules/|scratchpad|" + ($tmpdir | gsub("/"; "\\/"));
    . as $all
    | [ to_entries[] | select(.key > $idx) | select(.value.type=="assistant") |
        .value.message.content[]? | select(.type=="tool_use" and .name=="Agent") |
        select(.input.subagent_type=="document-reviewer" or .input.subagent_type=="adversarial-verifier" or .input.subagent_type=="code-reviewer") |
        select((.input.prompt // "") | test(path_re)) |
        .id
      ] as $ids
    | any($ids[]; . as $id |
        ( [ $all[] | select(.type=="user") | .message.content[]? |
              select(.type=="tool_result" and .tool_use_id==$id) |
              (if (.content|type)=="string" then .content
               elif (.content|type)=="array" then ([.content[]? | (.text? // "")] | join(" "))
               else "" end)
          ] | any(. | test("PASS|合格|承認可"))
        )
      )
  ' "$tp" 2>/dev/null)"
  [ "$found" = "true" ]
}

# transcript（JSONL）の最後のassistantメッセージのcontent配列にある text を
# すべて連結して返す（2026-09-06第3版・code-reviewer指摘: 旧実装は全体の
# 最後のtextブロック1つだけを見ており、本文と「以上です。」のように複数の
# textブロックに分かれた最終応答を取りこぼしていた）。
last_assistant_text() {
  jq -r --slurp '
    ( [ to_entries[] | select(.value.type=="assistant") ] | last ) as $last
    | if $last == null then empty
      else ( [ $last.value.message.content[]? | select(.type=="text") | .text ] | join("\n") )
      end
  ' "$1" 2>/dev/null
}

# $1: transcriptパス。最後の「本物のユーザー発話」以降に、Artifact
# （action=="publish"）・SendUserFile・AskUserQuestion のtool_useが
# あるかを判定する（2026-09-06第3版D: これらも「提示」とみなし、同じ判定役
# の要件を課す）。
presentation_tool_used_after_index() {
  local tp="$1" idx="${2:--1}" found
  found="$(jq -s --argjson idx "$idx" '
    any(to_entries[]; .key > $idx and .value.type=="assistant" and
      (.value.message.content[]? |
        (.type=="tool_use") and
        ((.name=="SendUserFile") or (.name=="AskUserQuestion") or
         (.name=="Artifact" and ((.input.action // "publish")=="publish")))
      )
    )
  ' "$tp" 2>/dev/null)"
  [ "$found" = "true" ]
}

# $1: 本文テキスト。フェンス（```）に囲まれた本文の行数の合計が10行以上に
# なれば真。単一ブロックの行数ではなく全フェンスの合計で見る（2026-09-06
# 第4版・反証所見: 1つの大きなフェンスを10行未満の複数のフェンスへ分割
# すれば、旧版の「1ブロックが10行以上」判定を回避できたため）。
has_long_fence() {
  local text="$1" in_fence=0 total=0 line
  while IFS= read -r line; do
    case "$line" in
      '```'*)
        if [ "$in_fence" -eq 1 ]; then
          in_fence=0
        else
          in_fence=1
        fi
        ;;
      *)
        [ "$in_fence" -eq 1 ] && total=$((total + 1))
        ;;
    esac
  done <<EOF
$text
EOF
  [ "$total" -ge 10 ]
}

# $1: 本文テキスト。フェンス内に現れる「設計」があれば真。
design_word_in_fence() {
  local text="$1" in_fence=0 line
  while IFS= read -r line; do
    case "$line" in
      '```'*)
        if [ "$in_fence" -eq 1 ]; then in_fence=0; else in_fence=1; fi
        ;;
      *)
        if [ "$in_fence" -eq 1 ] && printf '%s' "$line" | grep -qF '設計'; then
          return 0
        fi
        ;;
    esac
  done <<EOF
$text
EOF
  return 1
}

# $1: 本文テキスト。次のいずれかがあれば真（提示の形）。
#   (a) 「原稿」「ご確認ください」「案」「文面」「差し替え」「プロンプト」
#       「スライド」のいずれかの語
#   (b) フェンス内に現れる「設計」、または「設計の説明」「設計を説明」の語
# 2026-09-06コードレビュー指摘: 旧版の「設計」＋「以下」の組は通常の報告文
# （「〜を修正しました。以下のとおりです」等）を過検知し、逆に「原稿を
# 作成しました。ご確認ください」のような典型的な提示文を見逃した。単独の
# 「設計」はフェンス外の言及（例: 本規約の説明文）まで拾うため、フェンス内
# または明示句に限定する。
has_presentation_shape() {
  local text="$1"
  printf '%s' "$text" | grep -qE '(原稿|ご確認ください|確認ください|案|文面|差し替え|プロンプト|スライド|見ていただけますか|ご覧ください|たたき台)' && return 0
  printf '%s' "$text" | grep -qE '(設計の説明|設計を説明)' && return 0
  design_word_in_fence "$text" && return 0
  return 1
}

# 「提示前に判定役を通す」規則の判定。
judge_presentation_review() {
  # $1: 最終応答本文  $2: transcriptパス
  # 標準出力: 判定理由。戻り値: 0=許可（対象外含む）・2=拒否
  local text="$1" tp="$2"
  local idx
  idx="$(last_real_user_index "$tp")"

  local has_shape=1
  has_long_fence "$text" && has_shape=0
  has_presentation_shape "$text" && has_shape=0
  local has_tool=1
  presentation_tool_used_after_index "$tp" "$idx" && has_tool=0

  if [ "$has_shape" -ne 0 ] && [ "$has_tool" -ne 0 ]; then
    echo "対象外[提示前に判定役を通す]: 提示の形（合計10行以上のコードフェンス、原稿/確認ください/案/文面/差し替え/プロンプト/スライド/見ていただけますか/ご覧ください/たたき台/設計の説明等、Artifact/SendUserFile/AskUserQuestionの委任）のいずれも無い"
    return 0
  fi

  if review_agent_used_after_index "$tp" "$idx"; then
    echo "許可[提示前に判定役を通す]: 提示する内容の所在（docs/design/・docs/rules/・scratchpad）を含み結果が合格の判定役（document-reviewer/adversarial-verifier/code-reviewer）への委任が最後のユーザー発話以降にある"
    return 0
  fi

  echo "拒否[提示前に判定役を通す]: 提示の形があるのに、所在を含み結果が合格の判定役への委任が最後のユーザー発話以降に無い"
  return 2
}

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${DELEGATION_COMPLETION_CRITERIA_SKIP_REASON:-}" ]; then
    echo "[DELEGATION-COMPLETION-CRITERIA-SKIP] 理由: ${DELEGATION_COMPLETION_CRITERIA_SKIP_REASON}"
    return 0
  fi
  return 1
}

# 「提示前に判定役を通す」規則のStop処理。自動解除は無い（下記コメント
# 参照）。解消する手段は、所在を含み結果が合格の判定役への委任だけである。
#
# stop_hook_active（Claude Code自身が「これはStop hookからの再実行である」と
# 伝えるフラグ）でも同じ判定をそのまま行う（2026-09-06第4版・反証所見:
# 旧版はstop_hook_active=trueで無条件return 0していたため、1回でも
# block済みのセッションはその後のStop（stop_hook_activeが立つ）を
# 素通りする抜け道になっていた）。
handle_stop() {
  local input="$1" tp
  tp="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
  [ -z "$tp" ] || [ ! -f "$tp" ] && return 0

  # 自動解除は無い（2026-09-06第3版・code-reviewer指摘）。Stop hookのblock時
  # のreasonが実transcriptへどう記録されるかを`~/.claude/projects/`配下の
  # 既存transcriptで確認したが、"decision":"block"の文字列がそのまま記録
  # される実例を見つけられなかった（PreToolUse advisoryのadditionalContext
  # は見つかったが、Stopのdecision:block自体の記録形式は未確認）。回数を
  # 数える基準を確立できないため、解除条件を持たせずに固定する。解消する
  # 手段は判定役への委任（所在を含み合格の記録があるもの）だけである。
  # livelockの緩和（第4版）: 同じblockタグが5回以上transcriptに現れたら
  # systemMessageで人に知らせる。解除はしない（blockは維持する）。

  local text
  text="$(last_assistant_text "$tp")"
  [ -z "$text" ] && return 0

  local msg code
  if msg="$(judge_presentation_review "$text" "$tp")"; then code=0; else code=$?; fi
  [ "$code" -eq 0 ] && return 0

  local ctx="[PRESENTATION-BEFORE-REVIEW-BLOCK] ${msg}。document-reviewer・adversarial-verifier・code-reviewerのいずれかへ委任してから応答してください。"
  local hits
  hits="$(grep -o '\[PRESENTATION-BEFORE-REVIEW-BLOCK\]' "$tp" 2>/dev/null | wc -l | tr -d ' ')"
  [ -z "$hits" ] && hits=0
  if [ "$hits" -ge 5 ]; then
    local notice="[PRESENTATION-BEFORE-REVIEW-BLOCK] 同じblockが${hits}回続いています。判定役への委任が実施されていない状態が続いている可能性があります（解除はしません）。"
    jq -n --arg ctx "$ctx" --arg notice "$notice" '{"decision":"block","reason":$ctx,"systemMessage":$notice}'
  else
    jq -n --arg ctx "$ctx" '{"decision":"block","reason":$ctx}'
  fi
  return 0
}

run_hook() {
  local input
  input="$(cat)"
  [ -z "$input" ] && exit 0

  local hook_event
  hook_event="$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)"
  if [ "$hook_event" = "Stop" ]; then
    handle_stop "$input"
    exit 0
  fi

  local tool
  tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)

  if [ "$tool" = "Bash" ]; then
    local cmd msg code
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
    [ -z "$cmd" ] && exit 0

    if msg="$(judge_external_publish "$cmd")"; then code=0; else code=$?; fi

    [ "$code" -eq 0 ] && exit 0

    ctx="[FORCE-PUSH-BLOCK] ${msg}"
    jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
    printf '%s\n' "$ctx" >&2
    exit 2
  fi

  if [ "$tool" = "Agent" ]; then
    local agent_id
    agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)

    local prompt cwd subagent_type
    prompt=$(printf '%s' "$input" | jq -r '.tool_input.prompt // empty' 2>/dev/null)
    [ -z "$prompt" ] && exit 0
    cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
    [ -z "$cwd" ] && cwd="$PWD"
    subagent_type=$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)

    local msg code ctx

    # 完了条件を渡す（孫委任・[DELEGATION-EXEMPT]・SKIP_REASONで免除される）
    if [ -z "$agent_id" ]; then
      local skip_msg
      if skip_msg="$(should_skip_with_reason)"; then
        printf '%s\n' "$skip_msg" >&2
      else
        if msg="$(judge "$prompt")"; then code=0; else code=$?; fi
        if [ "$code" -ne 0 ]; then
          ctx="[DELEGATION-COMPLETION-CRITERIA-BLOCK] ${msg}。prompt に完了条件（判定基準）を明示してから再実行してください。"
          jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
          printf '%s\n' "$ctx" >&2
          exit 2
        fi
      fi
    fi

    # 実装の委任は設計の引用を渡す（免除なし。孫委任にも適用する。
    # 上の「免除の設計判断」節を参照）
    if msg="$(judge_design_quote "$prompt" "$cwd" "$subagent_type")"; then code=0; else code=$?; fi
    if [ "$code" -ne 0 ]; then
      ctx="[DELEGATION-DESIGN-QUOTE-BLOCK] ${msg}。promptに「## 設計の引用」の見出しと所在（パス#節）・引用文を書き、引用文を所在のファイルに実在させてから再実行してください。"
      jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
      printf '%s\n' "$ctx" >&2
      exit 2
    fi

    # 判定役への委任はレビュー対象を見出しで明記する
    if msg="$(judge_review_target_heading "$prompt" "$subagent_type")"; then code=0; else code=$?; fi
    if [ "$code" -ne 0 ]; then
      ctx="[DELEGATION-REVIEW-TARGET-BLOCK] ${msg}。promptに「## レビュー対象」の見出しと、その直下にレビュー対象のパスの行を書いてから再実行してください。"
      jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
      printf '%s\n' "$ctx" >&2
      exit 2
    fi

    # 判定役への委任は自己検査の結果を添える（免除なし）
    if msg="$(judge_self_check_result "$prompt" "$subagent_type")"; then code=0; else code=$?; fi
    if [ "$code" -ne 0 ]; then
      ctx="[SELF-CHECK-RESULT-BLOCK] ${msg}。promptに「## 自己検査の結果」の見出しと、観点・実測したこと・結果・否のときの直しの4列を持つ表を書き、結果に否が残らない状態にしてから再実行してください。"
      jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
      printf '%s\n' "$ctx" >&2
      exit 2
    fi

    exit 0
  fi

  exit 0
}

self_test() {
  local rc=0 msg code

  # 系1: 見出し「## 完了条件」あり → 許可
  local p1='作業内容: ファイルAを修正する。
## 完了条件
テストが通ること。'
  if msg="$(judge "$p1")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系1: 見出しありは許可される（${msg}）"
  else
    echo "  [FAIL] 系1: 見出しがあるのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系2: 見出しは無いが文中に「完了条件は」の明示あり → 許可
  local p2='作業内容: ファイルBを調査する。完了条件は grep 結果が0件になることです。'
  if msg="$(judge "$p2")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系2: 文中の明示ありは許可される（${msg}）"
  else
    echo "  [FAIL] 系2: 明示があるのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系3: 完了条件の記述が一切ない → 拒否
  local p3='作業内容: ファイルCを直してください。'
  if msg="$(judge "$p3")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系3: 完了条件の記述なしは拒否される（${msg}）"
  else
    echo "  [FAIL] 系3: 記述がないのに許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系4: [DELEGATION-EXEMPT] 明示 → 対象外として許可
  local p4='[DELEGATION-EXEMPT] 作業内容: ログを確認するだけ。'
  if msg="$(judge "$p4")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系4: [DELEGATION-EXEMPT] 明示は対象外として許可される（${msg}）"
  else
    echo "  [FAIL] 系4: 緊急口が効かず拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系5: 環境変数に理由を設定すると should_skip_with_reason は skip する
  local skip_out skip_code
  if skip_out="$(DELEGATION_COMPLETION_CRITERIA_SKIP_REASON="テスト理由" should_skip_with_reason)"; then skip_code=0; else skip_code=$?; fi
  if [ "$skip_code" -eq 0 ] && printf '%s' "$skip_out" | grep -qF 'DELEGATION-COMPLETION-CRITERIA-SKIP' && printf '%s' "$skip_out" | grep -qF 'テスト理由'; then
    echo "  [PASS] 系5: 理由を設定すると should_skip_with_reason は skip する（${skip_out}）"
  else
    echo "  [FAIL] 系5: 理由があるのに skip しない、またはタグ・理由が含まれない（exit=${skip_code}, ${skip_out}）" >&2
    rc=1
  fi

  # 系6: 環境変数を空文字にすると should_skip_with_reason は skip しない
  local skip_code2
  if DELEGATION_COMPLETION_CRITERIA_SKIP_REASON="" should_skip_with_reason >/dev/null 2>&1; then skip_code2=0; else skip_code2=$?; fi
  if [ "$skip_code2" -eq 1 ]; then
    echo "  [PASS] 系6: 環境変数が空文字なら should_skip_with_reason は skip しない"
  else
    echo "  [FAIL] 系6: 空文字なのに skip した（exit=${skip_code2}）" >&2
    rc=1
  fi

  # 系7: git push origin main → 外への公開まで AI が行う で許可
  if msg="$(judge_external_publish "git push origin main")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '外への公開まで AI が行う'; then
    echo "  [PASS] 系7: git push origin main は許可される（${msg}）"
  else
    echo "  [FAIL] 系7: 通常の送信が拒否された、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系8: npm publish → 公開の拒否は廃止したため許可
  if msg="$(judge_external_publish "npm publish")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系8: npm publish は許可される（${msg}）"
  else
    echo "  [FAIL] 系8: npm publish が拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系9: git commit -m "test" → 許可
  if msg="$(judge_external_publish 'git commit -m "test"')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系9: git commit は許可される（${msg}）"
  else
    echo "  [FAIL] 系9: git commit が拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系10: ls -la → 許可
  if msg="$(judge_external_publish "ls -la")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系10: ls -la は許可される（${msg}）"
  else
    echo "  [FAIL] 系10: ls -la が拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系11: git push --force → 強制の送信は拒否
  if msg="$(judge_external_publish "git push --force origin main")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '強制の送信'; then
    echo "  [PASS] 系11: git push --force は拒否される（${msg}）"
  else
    echo "  [FAIL] 系11: 強制の送信が拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系12: git push -f origin main → 拒否
  if msg="$(judge_external_publish "git push -f origin main")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系12: git push -f は拒否される"
  else
    echo "  [FAIL] 系12: git push -f が拒否されなかった（exit=${code}）" >&2
    rc=1
  fi

  # 系13: git push origin +main → 参照の先頭の + は強制のため拒否
  if msg="$(judge_external_publish "git push origin +main")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系13: git push origin +main は拒否される"
  else
    echo "  [FAIL] 系13: +refspec が拒否されなかった（exit=${code}）" >&2
    rc=1
  fi

  # 系14: --force-with-lease は拒否。区切り後の通常の送信と、push の語だけの検索は許可
  if msg="$(judge_external_publish "git push --force-with-lease origin main")"; then code=0; else code=$?; fi
  local code_b code_c
  if judge_external_publish "cd x && git push origin main" >/dev/null; then code_b=0; else code_b=$?; fi
  if judge_external_publish "git log --grep push" >/dev/null; then code_c=0; else code_c=$?; fi
  if [ "$code" -eq 2 ] && [ "$code_b" -eq 0 ] && [ "$code_c" -eq 0 ]; then
    echo "  [PASS] 系14: --force-with-lease は拒否、区切り後の通常の送信と push の語だけの検索は許可"
  else
    echo "  [FAIL] 系14: 期待と異なる（force-with-lease=${code}, 区切り後=${code_b}, 検索=${code_c}）" >&2
    rc=1
  fi

  # ここから「実装の委任は設計の引用を渡す」「提示前に判定役を通す」の自己テスト。
  # フィクスチャ用の一時ディレクトリを用意する（check-work-records.sh と同型）。
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-delegation-design-quote.XXXXXX" 2>/dev/null)" || tmp=""
  if [ -n "$tmp" ]; then
    git -C "$tmp" init -q -b main 2>/dev/null || git -C "$tmp" init -q
    mkdir -p "$tmp/docs/design/common"
    {
      echo "# テスト"
      echo ""
      echo "## §1"
      echo ""
      echo "名指しの項目を直す。書き方や方法を変える対象ではなく、欠けが無くなるまで必ず戻る。"
    } > "$tmp/docs/design/common/テスト.md"
  fi

  local dq_msg dq_code

  # 系15: docs/skills・docs/designに触れない委任は対象外
  if dq_msg="$(judge_design_quote "何か作業をしてください。" "$tmp")"; then dq_code=0; else dq_code=$?; fi
  if [ "$dq_code" -eq 0 ] && printf '%s' "$dq_msg" | grep -qF '対象外'; then
    echo "  [PASS] 系15: docs/skills・docs/designに触れない委任は対象外（${dq_msg}）"
  else
    echo "  [FAIL] 系15: 対象外にならなかった（exit=${dq_code}, ${dq_msg}）" >&2
    rc=1
  fi

  # 系16: docs/designの変更を求めるが見出し「## 設計の引用」が無ければ拒否
  local p16='docs/design/common/テスト.md を直す。'
  if dq_msg="$(judge_design_quote "$p16" "$tmp")"; then dq_code=0; else dq_code=$?; fi
  if [ "$dq_code" -eq 2 ] && printf '%s' "$dq_msg" | grep -qF '見出し'; then
    echo "  [PASS] 系16: 見出しが無ければ拒否される（${dq_msg}）"
  else
    echo "  [FAIL] 系16: 見出しが無いのに拒否されなかった（exit=${dq_code}, ${dq_msg}）" >&2
    rc=1
  fi

  # 系17: 見出しはあるが引用文がファイルに実在しなければ拒否
  local p17='docs/design/common/テスト.md を直す。

## 設計の引用

docs/design/common/テスト.md#§1
引用: この文言は設計書のファイルには一切存在しない架空の引用文であり、テストのために作成したものである。'
  if dq_msg="$(judge_design_quote "$p17" "$tmp")"; then dq_code=0; else dq_code=$?; fi
  if [ "$dq_code" -eq 2 ] && printf '%s' "$dq_msg" | grep -qF '引用が'; then
    echo "  [PASS] 系17: 引用が実在しなければ拒否される（${dq_msg}）"
  else
    echo "  [FAIL] 系17: 引用が実在しないのに拒否されなかった（exit=${dq_code}, ${dq_msg}）" >&2
    rc=1
  fi

  # 系18: 引用文がファイルに実在すれば許可
  local p18='docs/design/common/テスト.md を直す。

## 設計の引用

docs/design/common/テスト.md#§1
引用: 名指しの項目を直す。書き方や方法を変える対象ではなく、欠けが無くなるまで必ず戻る。'
  if dq_msg="$(judge_design_quote "$p18" "$tmp")"; then dq_code=0; else dq_code=$?; fi
  if [ "$dq_code" -eq 0 ] && printf '%s' "$dq_msg" | grep -qF '許可'; then
    echo "  [PASS] 系18: 引用が実在すれば許可される（${dq_msg}）"
  else
    echo "  [FAIL] 系18: 引用が実在するのに許可されなかった（exit=${dq_code}, ${dq_msg}）" >&2
    rc=1
  fi

  local pr_msg pr_code
  local fence20
  fence20="$(printf '```\n1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n```')"

  # 系19: 提示の形（長いフェンス・スライド等の語）が無ければ対象外
  if pr_msg="$(judge_presentation_review "ふつうの応答です。" "${tmp}/no-such.jsonl")"; then pr_code=0; else pr_code=$?; fi
  if [ "$pr_code" -eq 0 ] && printf '%s' "$pr_msg" | grep -qF '対象外'; then
    echo "  [PASS] 系19: 提示の形が無ければ対象外（${pr_msg}）"
  else
    echo "  [FAIL] 系19: 対象外にならなかった（exit=${pr_code}, ${pr_msg}）" >&2
    rc=1
  fi

  # 系20: 10行以上のフェンスがあり、判定役への委任が無ければ拒否
  local tp20="${tmp}/transcript20.jsonl"
  : > "$tp20"
  jq -nc '{type:"user", message:{role:"user", content:"作業をお願いします"}}' >> "$tp20"
  jq -nc '{type:"assistant", message:{content:[{type:"tool_use", name:"Write", input:{file_path:"a.txt"}}]}}' >> "$tp20"
  if pr_msg="$(judge_presentation_review "$fence20" "$tp20")"; then pr_code=0; else pr_code=$?; fi
  if [ "$pr_code" -eq 2 ]; then
    echo "  [PASS] 系20: 10行以上のフェンスがあり判定役への委任が無ければ拒否される（${pr_msg}）"
  else
    echo "  [FAIL] 系20: 拒否されなかった（exit=${pr_code}, ${pr_msg}）" >&2
    rc=1
  fi

  # 系21: 同じフェンスでも、最後のユーザー発話以降に判定役への委任があれば許可
  local tp21="${tmp}/transcript21.jsonl"
  : > "$tp21"
  jq -nc '{type:"user", message:{role:"user", content:"作業をお願いします"}}' >> "$tp21"
  jq -nc '{type:"assistant", message:{content:[{type:"tool_use", id:"tu21", name:"Agent", input:{subagent_type:"document-reviewer", prompt:"docs/design/common/テスト.md を読んでレビューしてください"}}]}}' >> "$tp21"
  jq -nc '{type:"user", message:{content:[{type:"tool_result", tool_use_id:"tu21", content:"PASS: 問題ありません"}]}}' >> "$tp21"
  if pr_msg="$(judge_presentation_review "$fence20" "$tp21")"; then pr_code=0; else pr_code=$?; fi
  if [ "$pr_code" -eq 0 ] && printf '%s' "$pr_msg" | grep -qF '許可'; then
    echo "  [PASS] 系21: 判定役への委任が最後のユーザー発話以降にあれば許可される（${pr_msg}）"
  else
    echo "  [FAIL] 系21: 許可されなかった（exit=${pr_code}, ${pr_msg}）" >&2
    rc=1
  fi

  # 系22: スライド＋以下の提示の形があり判定役への委任が無ければ拒否
  local text22='スライドの原稿を作りました。以下の内容でご確認ください。'
  if pr_msg="$(judge_presentation_review "$text22" "$tp20")"; then pr_code=0; else pr_code=$?; fi
  if [ "$pr_code" -eq 2 ]; then
    echo "  [PASS] 系22: スライド＋以下の形があり判定役が無ければ拒否される（${pr_msg}）"
  else
    echo "  [FAIL] 系22: 拒否されなかった（exit=${pr_code}, ${pr_msg}）" >&2
    rc=1
  fi

  # 系23: tool_resultだけのuserエントリは最後の本物のユーザー発話に数えない
  local tp23="${tmp}/transcript23.jsonl"
  : > "$tp23"
  jq -nc '{type:"user", message:{role:"user", content:"最初の依頼"}}' >> "$tp23"
  jq -nc '{type:"assistant", message:{content:[{type:"tool_use", name:"Agent", input:{subagent_type:"document-reviewer"}}]}}' >> "$tp23"
  jq -nc '{type:"user", message:{role:"user", content:[{type:"tool_result", content:"結果"}]}}' >> "$tp23"
  local idx23
  idx23="$(last_real_user_index "$tp23")"
  if [ "$idx23" = "0" ]; then
    echo "  [PASS] 系23: tool_resultだけのuserエントリは最後の本物のユーザー発話に数えない（idx=${idx23}）"
  else
    echo "  [FAIL] 系23: tool_resultをユーザー発話と誤認した（idx=${idx23}）" >&2
    rc=1
  fi

  # 系24: 最後のユーザー発話より前にあった判定役への委任は数えない
  local tp24="${tmp}/transcript24.jsonl"
  : > "$tp24"
  jq -nc '{type:"assistant", message:{content:[{type:"tool_use", name:"Agent", input:{subagent_type:"document-reviewer"}}]}}' >> "$tp24"
  jq -nc '{type:"user", message:{role:"user", content:"新しい依頼"}}' >> "$tp24"
  local idx24
  idx24="$(last_real_user_index "$tp24")"
  if review_agent_used_after_index "$tp24" "$idx24"; then
    echo "  [FAIL] 系24: 最後のユーザー発話より前の委任を数えてしまった（idx=${idx24}）" >&2
    rc=1
  else
    echo "  [PASS] 系24: 最後のユーザー発話より前の判定役への委任は数えない（idx=${idx24}）"
  fi

  # 系25: 引用が1文字（「。」）→拒否（コードレビュー指摘: 最短長）
  local p25='docs/design/common/テスト.md を直す。

## 設計の引用

docs/design/common/テスト.md#§1
引用: 。'
  if dq_msg="$(judge_design_quote "$p25" "$tmp")"; then dq_code=0; else dq_code=$?; fi
  if [ "$dq_code" -eq 2 ] && printf '%s' "$dq_msg" | grep -qF '40字以上'; then
    echo "  [PASS] 系25: 引用が1文字なら拒否される（${dq_msg}）"
  else
    echo "  [FAIL] 系25: 拒否されなかった（exit=${dq_code}, ${dq_msg}）" >&2
    rc=1
  fi

  # 系26: 否定文の調査依頼（読み取り専用の担当者）→対象外で通過
  # （コードレビュー指摘: 変更語の判定を廃止したため、パスの語が含まれる
  # 調査だけの委任も一度は対象になるが、読み取り専用の担当者は免除する）
  local p26='docs/design/common/テスト.md の内容を調査してください。変更はしない。'
  if dq_msg="$(judge_design_quote "$p26" "$tmp" "investigator")"; then dq_code=0; else dq_code=$?; fi
  if [ "$dq_code" -eq 0 ] && printf '%s' "$dq_msg" | grep -qF '対象外'; then
    echo "  [PASS] 系26: 否定文の調査依頼は読み取り専用の担当者として対象外（${dq_msg}）"
  else
    echo "  [FAIL] 系26: 対象外にならなかった（exit=${dq_code}, ${dq_msg}）" >&2
    rc=1
  fi

  # 系27: 「原稿…ご確認ください」→提示物として判定される（判定役への委任が
  # 無いため拒否になることで、提示物と認識されたことを確かめる）
  local text27='原稿を作成しました。ご確認ください。'
  if pr_msg="$(judge_presentation_review "$text27" "$tp20")"; then pr_code=0; else pr_code=$?; fi
  if [ "$pr_code" -eq 2 ]; then
    echo "  [PASS] 系27: 原稿・ご確認くださいは提示物として判定される（${pr_msg}）"
  else
    echo "  [FAIL] 系27: 提示物として判定されなかった（exit=${pr_code}, ${pr_msg}）" >&2
    rc=1
  fi

  # 系28: 通常の報告文（フェンス無し・提示語無し）→対象外
  local text28='修正が完了しました。以下の変更を行いました。ファイルAのtypoを直しました。'
  if pr_msg="$(judge_presentation_review "$text28" "$tp20")"; then pr_code=0; else pr_code=$?; fi
  if [ "$pr_code" -eq 0 ] && printf '%s' "$pr_msg" | grep -qF '対象外'; then
    echo "  [PASS] 系28: 通常の報告文は対象外（${pr_msg}）"
  else
    echo "  [FAIL] 系28: 対象外にならなかった（exit=${pr_code}, ${pr_msg}）" >&2
    rc=1
  fi

  # 系29: last_assistant_text が最終assistantメッセージの複数textブロックを
  # 連結する（2026-09-06第3版・code-reviewer指摘: 本文＋「以上です。」の
  # 2ブロックが対象になることを確認する）
  local tp29="${tmp}/transcript29.jsonl"
  : > "$tp29"
  jq -nc '{type:"user", message:{role:"user", content:"お願いします"}}' >> "$tp29"
  jq -nc '{type:"assistant", message:{content:[{type:"text", text:"原稿を作成しました。ご確認ください。"},{type:"text", text:"以上です。"}]}}' >> "$tp29"
  local text29
  text29="$(last_assistant_text "$tp29")"
  if printf '%s' "$text29" | grep -qF '原稿を作成しました' && printf '%s' "$text29" | grep -qF '以上です'; then
    echo "  [PASS] 系29: last_assistant_textが複数textブロックを連結する（${text29}）"
  else
    echo "  [FAIL] 系29: 複数textブロックを連結できなかった（${text29}）" >&2
    rc=1
  fi

  # 系30: Artifact（publish）のtool_useが最後のユーザー発話以降にあれば
  # 「提示」とみなされる（判定役への委任が無いため拒否になることで確認する）
  local tp30="${tmp}/transcript30.jsonl"
  : > "$tp30"
  jq -nc '{type:"user", message:{role:"user", content:"お願いします"}}' >> "$tp30"
  jq -nc '{type:"assistant", message:{content:[{type:"tool_use", name:"Artifact", input:{action:"publish"}}]}}' >> "$tp30"
  if pr_msg="$(judge_presentation_review "ふつうの本文です。" "$tp30")"; then pr_code=0; else pr_code=$?; fi
  if [ "$pr_code" -eq 2 ]; then
    echo "  [PASS] 系30: Artifact(publish)のtool_useは提示とみなされる（${pr_msg}）"
  else
    echo "  [FAIL] 系30: 提示とみなされなかった（exit=${pr_code}, ${pr_msg}）" >&2
    rc=1
  fi

  # 系31: judge_design_quote は .claude/skills への言及も対象にする
  local p31='.claude/skills/foo/SKILL.mdを直してください。'
  if dq_msg="$(judge_design_quote "$p31" "$tmp")"; then dq_code=0; else dq_code=$?; fi
  if [ "$dq_code" -eq 2 ] && printf '%s' "$dq_msg" | grep -qF '派生'; then
    echo "  [PASS] 系31: .claude/skillsだけの委任は派生の直接編集として拒否される（${dq_msg}）"
  else
    echo "  [FAIL] 系31: 対象にならなかった、または派生メッセージでなかった（exit=${dq_code}, ${dq_msg}）" >&2
    rc=1
  fi

  # 系32: docs/skillsとdocs/rulesの両方を含む委任は派生ブロックの対象外
  # （派生パスの言及があっても定義側の変更も伴う正常な委任は妨げない）
  local p32='docs/skills/foo/SKILL.mdを直してください。'
  if dq_msg="$(judge_design_quote "$p32" "$tmp")"; then dq_code=0; else dq_code=$?; fi
  if [ "$dq_code" -eq 2 ] && printf '%s' "$dq_msg" | grep -qF '見出し'; then
    echo "  [PASS] 系32: docs/skillsのみの委任は通常どおり見出し不足で拒否される（${dq_msg}）"
  else
    echo "  [FAIL] 系32: 派生ブロックへ誤って分類された（exit=${dq_code}, ${dq_msg}）" >&2
    rc=1
  fi

  [ -n "$tmp" ] && rm -rf "$tmp"

  # 系33: 判定役への委任でdocs/design/への言及があり「## レビュー対象」が
  # 無ければ拒否される
  local p33='docs/design/skills/order機能/ を読んでレビューしてください'
  local rt_msg rt_code
  if rt_msg="$(judge_review_target_heading "$p33" "code-reviewer")"; then rt_code=0; else rt_code=$?; fi
  if [ "$rt_code" -eq 2 ] && printf '%s' "$rt_msg" | grep -qF '見出し'; then
    echo "  [PASS] 系33: レビュー対象見出しが無ければ拒否される（${rt_msg}）"
  else
    echo "  [FAIL] 系33: レビュー対象見出しが無ければ拒否される（exit=${rt_code}, ${rt_msg}）" >&2
    rc=1
  fi

  # 系34: 「## レビュー対象」見出しと直下のパスがあれば許可される
  local p34='## レビュー対象
docs/design/skills/order機能/
上記をレビューしてください。'
  if rt_msg="$(judge_review_target_heading "$p34" "code-reviewer")"; then rt_code=0; else rt_code=$?; fi
  if [ "$rt_code" -eq 0 ]; then
    echo "  [PASS] 系34: レビュー対象見出しがあれば許可される（${rt_msg}）"
  else
    echo "  [FAIL] 系34: レビュー対象見出しがあれば許可される（exit=${rt_code}, ${rt_msg}）" >&2
    rc=1
  fi

  # 系35: 判定役以外への委任は対象外
  local rt_msg35 rt_code35
  if rt_msg35="$(judge_review_target_heading "$p33" "worker-sonnet")"; then rt_code35=0; else rt_code35=$?; fi
  if [ "$rt_code35" -eq 0 ] && printf '%s' "$rt_msg35" | grep -qF '対象外'; then
    echo "  [PASS] 系35: 判定役以外への委任は対象外（${rt_msg35}）"
  else
    echo "  [FAIL] 系35: 判定役以外への委任は対象外（exit=${rt_code35}, ${rt_msg35}）" >&2
    rc=1
  fi

  # 系36: has_long_fence は複数の短いフェンスの合計が10行以上になれば真になる
  # （1つの大きなフェンスを短く分割する回避を防ぐ）
  local fence_split
  fence_split="$(printf '%s\n' '```' '行1' '行2' '行3' '行4' '```' '以上です。' '```' '行5' '行6' '行7' '行8' '行9' '行10' '```')"
  if has_long_fence "$fence_split"; then
    echo "  [PASS] 系36: 分割した複数フェンスの合計10行以上を真と判定する"
  else
    echo "  [FAIL] 系36: 分割した複数フェンスの合計10行以上を真と判定できなかった" >&2
    rc=1
  fi

  # 系36b: 短いフェンス1つだけなら偽のまま
  local fence_short
  fence_short="$(printf '%s\n' '```' '行1' '行2' '```')"
  if has_long_fence "$fence_short"; then
    echo "  [FAIL] 系36b: 短いフェンス1つは偽のはず" >&2
    rc=1
  else
    echo "  [PASS] 系36b: 短いフェンス1つは偽のまま"
  fi

  # 系37: 新しい提示語彙（たたき台・ご覧ください・見ていただけますか）を検知する
  if has_presentation_shape 'たたき台を作りました。ご覧ください。'; then
    echo "  [PASS] 系37: 新語彙（たたき台・ご覧ください）を検知する"
  else
    echo "  [FAIL] 系37: 新語彙（たたき台・ご覧ください）を検知しなかった" >&2
    rc=1
  fi

  # 系38: ヒアドキュメント本体に'git'と'push @candidates'を含んでいても、
  # 実行されるコマンドではないため許可される
  local hd_cmd38='cat <<EOF
if ($seg =~ /^\s*(?:sudo\s+)?git\b/) { push @candidates, "x"; }
EOF'
  if msg="$(judge_external_publish "$hd_cmd38")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系38: ヒアドキュメント本体のgit・pushは許可される（${msg}）"
  else
    echo "  [FAIL] 系38: ヒアドキュメント本体のgit・pushなのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系39: 引用文字列の中のpushは実行されるサブコマンドではないため許可される
  if msg="$(judge_external_publish 'git log --grep "push"')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系39: 引用文字列内のpushは許可される（${msg}）"
  else
    echo "  [FAIL] 系39: 引用文字列内のpushなのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系40: gitとpushが無関係な2つのコマンドにそれぞれ現れるだけなら許可される
  if msg="$(judge_external_publish 'echo git && echo push')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系40: echo git && echo push は許可される（${msg}）"
  else
    echo "  [FAIL] 系40: 無関係な2コマンドなのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系41: "git push"という文字列全体が1つの引用文字列の中にあるだけなら許可される
  if msg="$(judge_external_publish 'echo "git push"')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系41: echo \"git push\" は許可される（${msg}）"
  else
    echo "  [FAIL] 系41: 引用文字列全体なのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系42: git -C <path> push --force のように、間にオプションを挟んでも
  # 強制の送信は拒否される
  if msg="$(judge_external_publish 'git -C /x push --force origin main')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系42: git -C /x push --force origin main は拒否される（${msg}）"
  else
    echo "  [FAIL] 系42: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系43: sudo git push --force のように先頭にsudoを挟んでも強制の送信は拒否される
  if msg="$(judge_external_publish 'sudo git push --force')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系43: sudo git push --force は拒否される（${msg}）"
  else
    echo "  [FAIL] 系43: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系44: cd x && git push --force のように無関係なコマンドの後に続いても
  # 強制の送信は拒否される
  if msg="$(judge_external_publish 'cd x && git push --force')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系44: cd x && git push --force は拒否される（${msg}）"
  else
    echo "  [FAIL] 系44: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系45〜系52: 第7版で前置の剥がしを追加した各前置語を挟んでも、強制の送信
  # （push --force）の判定を逃れられないことを確かめる
  if msg="$(judge_external_publish 'command git push --force origin main')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系45: command git push --force origin main は拒否される（${msg}）"
  else
    echo "  [FAIL] 系45: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  if msg="$(judge_external_publish 'exec git push --force')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系46: exec git push --force は拒否される（${msg}）"
  else
    echo "  [FAIL] 系46: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  if msg="$(judge_external_publish 'nohup git push --force')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系47: nohup git push --force は拒否される（${msg}）"
  else
    echo "  [FAIL] 系47: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  if msg="$(judge_external_publish 'time git push --force')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系48: time git push --force は拒否される（${msg}）"
  else
    echo "  [FAIL] 系48: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  if msg="$(judge_external_publish '/usr/bin/git push --force')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系49: /usr/bin/git push --force は拒否される（${msg}）"
  else
    echo "  [FAIL] 系49: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  if msg="$(judge_external_publish '\git push --force')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系50: \\git push --force は拒否される（${msg}）"
  else
    echo "  [FAIL] 系50: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  if msg="$(judge_external_publish 'xargs git push --force')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系51: xargs git push --force は拒否される（${msg}）"
  else
    echo "  [FAIL] 系51: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  if msg="$(judge_external_publish 'env GIT_DIR=x git push --force')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系52: env GIT_DIR=x git push --force は拒否される（${msg}）"
  else
    echo "  [FAIL] 系52: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系53: 引用符の中の git push は既知の限界として許可される
  # （_strip_heredoc_and_quotesが引用文字列の中身を空にするため、
  # bash -c 'git push' のように別シェルへ丸ごと渡す形は検出できない）
  if msg="$(judge_external_publish "bash -c 'git push'")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系53: bash -c 'git push' は既知の限界として許可される（${msg}）"
  else
    echo "  [FAIL] 系53: 既知の限界のはずが拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系54〜59: 第8版・_strip_leading_prefixesへの前置（相対パス・チルダ・
  # busybox・複合文の開き）を挟んでも、強制の送信（push --force）の
  # 判定を逃れられないことを確かめる

  if msg="$(judge_external_publish './tools/git push --force origin main')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系54: ./tools/git push --force origin main は拒否される（${msg}）"
  else
    echo "  [FAIL] 系54: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  if msg="$(judge_external_publish '~/bin/git push --force')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系55: ~/bin/git push --force は拒否される（${msg}）"
  else
    echo "  [FAIL] 系55: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  if msg="$(judge_external_publish '{ git push --force; }')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系56: { git push --force; } は拒否される（${msg}）"
  else
    echo "  [FAIL] 系56: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  if msg="$(judge_external_publish 'if true; then git push --force; fi')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系57: if true; then git push --force; fi は拒否される（${msg}）"
  else
    echo "  [FAIL] 系57: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  if msg="$(judge_external_publish 'busybox git push --force')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系58: busybox git push --force は拒否される（${msg}）"
  else
    echo "  [FAIL] 系58: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  if msg="$(judge_external_publish '( git push --force )')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系59: ( git push --force ) は拒否される（${msg}）"
  else
    echo "  [FAIL] 系59: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系60: printfで文字列を組み立ててxargs経由でgitへ渡す形は既知の限界として
  # 許可される（コマンド文字列の字面には独立した語としての"push"が現れず、
  # 実行時にxargsとprintfが結合して初めて成立するため、字面解析では検出できない）
  if msg="$(judge_external_publish 'printf pu%s sh | xargs git')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系60: printf pu%s sh | xargs git は既知の限界として許可される（${msg}）"
  else
    echo "  [FAIL] 系60: 既知の限界のはずが拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系61〜66: 第9版・_git_subcommand導入（git自身のオプションを読み飛ばして
  # 副命令を見る）を挟んでも、強制の送信（push --force）の判定を逃れられない
  # ことを確かめる

  if msg="$(judge_external_publish './git push --force origin main')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系61: ./git push --force origin main は拒否される（スラッシュ1個のパス前置。${msg}）"
  else
    echo "  [FAIL] 系61: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  if msg="$(judge_external_publish '~/git push --force')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系62: ~/git push --force は拒否される（スラッシュ1個のパス前置。${msg}）"
  else
    echo "  [FAIL] 系62: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  if msg="$(judge_external_publish 'git -C /x push --force')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系63: git -C /x push --force は拒否される（既存。_git_subcommand経由でも維持。${msg}）"
  else
    echo "  [FAIL] 系63: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  if msg="$(judge_external_publish 'git -c a=b push --force')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系64: git -c a=b push --force は拒否される（${msg}）"
  else
    echo "  [FAIL] 系64: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  if msg="$(judge_external_publish 'git --git-dir=/x/.git push --force')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系65: git --git-dir=/x/.git push --force は拒否される（${msg}）"
  else
    echo "  [FAIL] 系65: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  if msg="$(judge_external_publish 'git --no-pager push --force')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系66: git --no-pager push --force は拒否される（${msg}）"
  else
    echo "  [FAIL] 系66: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  if msg="$(judge_external_publish 'git -C /x log')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系67: git -C /x log は許可される（副命令logはpushと不一致。${msg}）"
  else
    echo "  [FAIL] 系67: 許可されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系68: $(which git) push は既知の限界として許可される（コマンド置換の
  # 結果を実行時にしか知り得ず、字面には独立した語としての"git"が現れない
  # ため、_git_subcommandの第1語比較では検出できない）
  if msg="$(judge_external_publish '$(which git) push')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系68: \$(which git) push は既知の限界として許可される（${msg}）"
  else
    echo "  [FAIL] 系68: 既知の限界のはずが拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系69〜74: 第11版で追加したforce相当（--mirror・--delete・空の左辺・
  # 引用符で分断した先頭+）の拒否と、通常の送信（main・main:main）の許可。
  if msg="$(judge_external_publish 'git push --mirror')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系69: git push --mirror は拒否される（${msg}）"
  else
    echo "  [FAIL] 系69: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  if msg="$(judge_external_publish 'git push origin --delete main')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系70: git push origin --delete main は拒否される（${msg}）"
  else
    echo "  [FAIL] 系70: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  if msg="$(judge_external_publish 'git push origin :main')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系71: git push origin :main は拒否される（${msg}）"
  else
    echo "  [FAIL] 系71: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  if msg="$(judge_external_publish "git push origin '+main:main'")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系72: git push origin '+main:main' は引用符で分断しても拒否される（${msg}）"
  else
    echo "  [FAIL] 系72: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  if msg="$(judge_external_publish 'git push origin main')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系73: git push origin main は許可される（${msg}）"
  else
    echo "  [FAIL] 系73: 許可されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  if msg="$(judge_external_publish 'git push origin main:main')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系74: git push origin main:main は許可される（${msg}）"
  else
    echo "  [FAIL] 系74: 許可されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系75: --force-if-includesは--forceとの前方一致では境界判定に一致せず
  # 見逃していた（2026-09-06第12版）
  if msg="$(judge_external_publish 'git push --force-if-includes')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系75: git push --force-if-includes は拒否される（${msg}）"
  else
    echo "  [FAIL] 系75: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系76: --pruneも拒否対象に加える（2026-09-06第12版）
  if msg="$(judge_external_publish 'git push --prune origin')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系76: git push --prune origin は拒否される（${msg}）"
  else
    echo "  [FAIL] 系76: 拒否されなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # ここから「判定役への委任は自己検査の結果を添える」の自己テスト。
  local sc_msg sc_code

  # 系77: 見出し「## 自己検査の結果」が無ければ拒否
  local p77='作業内容: レビューしてください。'
  if sc_msg="$(judge_self_check_result "$p77" "code-reviewer")"; then sc_code=0; else sc_code=$?; fi
  if [ "$sc_code" -eq 2 ] && printf '%s' "$sc_msg" | grep -qF '見出し'; then
    echo "  [PASS] 系77: 見出しが無ければ拒否される（${sc_msg}）"
  else
    echo "  [FAIL] 系77: 見出しが無いのに拒否されなかった（exit=${sc_code}, ${sc_msg}）" >&2
    rc=1
  fi

  # 系78: 見出しはあるが表が無ければ拒否
  local p78='## 自己検査の結果
表はまだ作っていません。'
  if sc_msg="$(judge_self_check_result "$p78" "code-reviewer")"; then sc_code=0; else sc_code=$?; fi
  if [ "$sc_code" -eq 2 ] && printf '%s' "$sc_msg" | grep -qF '表が無い'; then
    echo "  [PASS] 系78: 表が無ければ拒否される（${sc_msg}）"
  else
    echo "  [FAIL] 系78: 表が無いのに拒否されなかった（exit=${sc_code}, ${sc_msg}）" >&2
    rc=1
  fi

  # 系79: 4列でない表（否のときの直し列が無い）は拒否
  local p79='## 自己検査の結果

| 観点 | 実測したこと | 結果 |
|---|---|---|
| 命名 | grepした | 合 |'
  if sc_msg="$(judge_self_check_result "$p79" "code-reviewer")"; then sc_code=0; else sc_code=$?; fi
  if [ "$sc_code" -eq 2 ] && printf '%s' "$sc_msg" | grep -qF '4列'; then
    echo "  [PASS] 系79: 4列でない表は拒否される（${sc_msg}）"
  else
    echo "  [FAIL] 系79: 4列でない表なのに拒否されなかった（exit=${sc_code}, ${sc_msg}）" >&2
    rc=1
  fi

  # 系80: 結果に否があれば拒否
  local p80='## 自己検査の結果

| 観点 | 実測したこと | 結果 | 否のときの直し |
|---|---|---|---|
| 命名 | grepした | 否 | 直す予定 |'
  if sc_msg="$(judge_self_check_result "$p80" "adversarial-verifier")"; then sc_code=0; else sc_code=$?; fi
  if [ "$sc_code" -eq 2 ] && printf '%s' "$sc_msg" | grep -qF 'いずれでもない'; then
    echo "  [PASS] 系80: 結果に否があれば拒否される（${sc_msg}）"
  else
    echo "  [FAIL] 系80: 否があるのに拒否されなかった（exit=${sc_code}, ${sc_msg}）" >&2
    rc=1
  fi

  # 系81: 正しい表（結果は合と対象外だけ）は許可
  local p81='## 自己検査の結果

| 観点 | 実測したこと | 結果 | 否のときの直し |
|---|---|---|---|
| 命名 | grepした | 合 | - |
| 表記 | 確認した | 対象外 | - |'
  if sc_msg="$(judge_self_check_result "$p81" "document-reviewer")"; then sc_code=0; else sc_code=$?; fi
  if [ "$sc_code" -eq 0 ] && printf '%s' "$sc_msg" | grep -qF '許可'; then
    echo "  [PASS] 系81: 合と対象外だけの表は許可される（${sc_msg}）"
  else
    echo "  [FAIL] 系81: 許可されなかった（exit=${sc_code}, ${sc_msg}）" >&2
    rc=1
  fi

  # 系82: worker-sonnetへの委任は対象外
  if sc_msg="$(judge_self_check_result "何か作業をしてください。" "worker-sonnet")"; then sc_code=0; else sc_code=$?; fi
  if [ "$sc_code" -eq 0 ] && printf '%s' "$sc_msg" | grep -qF '対象外'; then
    echo "  [PASS] 系82: worker-sonnetへの委任は対象外（${sc_msg}）"
  else
    echo "  [FAIL] 系82: 対象外にならなかった（exit=${sc_code}, ${sc_msg}）" >&2
    rc=1
  fi

  # 系83〜85: 結果列の許可制（13回目の反証再現防止）。「合」「対象外」
  # 以外の値（×・不合格・空）はいずれも拒否される。

  local p83='## 自己検査の結果

| 観点 | 実測したこと | 結果 | 否のときの直し |
|---|---|---|---|
| 命名 | grepした | × | 直す予定 |'
  if sc_msg="$(judge_self_check_result "$p83" "code-reviewer")"; then sc_code=0; else sc_code=$?; fi
  if [ "$sc_code" -eq 2 ] && printf '%s' "$sc_msg" | grep -qF 'いずれでもない'; then
    echo "  [PASS] 系83: 結果が×なら拒否される（${sc_msg}）"
  else
    echo "  [FAIL] 系83: 結果が×なのに拒否されなかった（exit=${sc_code}, ${sc_msg}）" >&2
    rc=1
  fi

  local p84='## 自己検査の結果

| 観点 | 実測したこと | 結果 | 否のときの直し |
|---|---|---|---|
| 命名 | grepした | 不合格 | 直す予定 |'
  if sc_msg="$(judge_self_check_result "$p84" "code-reviewer")"; then sc_code=0; else sc_code=$?; fi
  if [ "$sc_code" -eq 2 ] && printf '%s' "$sc_msg" | grep -qF 'いずれでもない'; then
    echo "  [PASS] 系84: 結果が不合格なら拒否される（${sc_msg}）"
  else
    echo "  [FAIL] 系84: 結果が不合格なのに拒否されなかった（exit=${sc_code}, ${sc_msg}）" >&2
    rc=1
  fi

  local p85='## 自己検査の結果

| 観点 | 実測したこと | 結果 | 否のときの直し |
|---|---|---|---|
| 命名 | grepした |  | - |'
  if sc_msg="$(judge_self_check_result "$p85" "code-reviewer")"; then sc_code=0; else sc_code=$?; fi
  if [ "$sc_code" -eq 2 ] && printf '%s' "$sc_msg" | grep -qF 'いずれでもない'; then
    echo "  [PASS] 系85: 結果が空なら拒否される（${sc_msg}）"
  else
    echo "  [FAIL] 系85: 結果が空なのに拒否されなかった（exit=${sc_code}, ${sc_msg}）" >&2
    rc=1
  fi

  # 系86: 全行の結果が「対象外」だけの表は許可される
  local p86='## 自己検査の結果

| 観点 | 実測したこと | 結果 | 否のときの直し |
|---|---|---|---|
| 命名 | 対象外の項目 | 対象外 | - |
| 表記 | 対象外の項目 | 対象外 | - |'
  if sc_msg="$(judge_self_check_result "$p86" "document-reviewer")"; then sc_code=0; else sc_code=$?; fi
  if [ "$sc_code" -eq 0 ] && printf '%s' "$sc_msg" | grep -qF '許可'; then
    echo "  [PASS] 系86: 対象外だけの表は許可される（${sc_msg}）"
  else
    echo "  [FAIL] 系86: 許可されなかった（exit=${sc_code}, ${sc_msg}）" >&2
    rc=1
  fi

  # 系87〜88: 22回目の反証（語の途中の行継続）。バックスラッシュ+実改行で
  # 検査語を割ると`git`という語が字面に現れず素通りしていた。
  local pu_cmd1
  pu_cmd1=$'git pu\\\nsh --force origin main'
  if msg="$(judge_external_publish "$pu_cmd1")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系87: 語の途中に実改行を挟んだgit push --forceは拒否される（22回目の反証）"
  else
    echo "  [FAIL] 系87: git pu<改行>sh --forceが拒否されなかった（exit=${code}）" >&2
    rc=1
  fi

  if msg="$(judge_external_publish "git push origin main")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系88: 通常のgit pushは許可される（22回目の反証の回帰）"
  else
    echo "  [FAIL] 系88: 通常のgit pushが拒否された（exit=${code}）" >&2
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
