#!/usr/bin/env bash
# judge-task-done.sh — docs/tasks/*.md のうち片付いた指示書を機械で見分け、docs/tasks/done/ へ移す。
#
# 使い方:
#   bash docs/scripts/judge-task-done.sh                判定して一覧を出すだけ（ファイルを動かさない）
#   bash docs/scripts/judge-task-done.sh --apply         移せる対象を git mv でステージへ載せる（commit はしない）
#   bash docs/scripts/judge-task-done.sh --write         「確かめる手段」を実行し、結果を「状態」欄へ書き込む
#   bash docs/scripts/judge-task-done.sh --only <パス>    指定した指示書1件だけを対象にする（--write と併用可）
#   bash docs/scripts/judge-task-done.sh --timeout <秒>  「確かめる手段」1件あたりの時間の上限を変える（既定120秒）
#   bash docs/scripts/judge-task-done.sh --cross-check   段階3（照合）: 指示書が主張するキーに台帳の裏付けがあるか数える
#   bash docs/scripts/judge-task-done.sh --self-test     スクリプト自身の検査
#
# 判定する条件（すべて満たしたものだけを「移せる」とする）:
#   1. 記録が済んでいる: 「対応の記録」の節があり、「### 判定の充足状況」の表に判定の行が1件以上あり、
#      状態がすべて「完了」または「対象外」（「未着手」「対応中」「判断待ち」が1件でも残れば満たさない）
#   2. 実測が済んでいる（段階2）: 表が「判定 | 確かめる手段 | 状態 | コミット | 確かめた内容」の5列であり
#      （「確かめる手段」の列が無い古い4列の表は満たさない）、各行の「確かめる手段」欄のコマンドを
#      実際に実行してすべてが終了コード0を返す。「目視」と書かれた行が1件でもあれば
#      （機械では確かめられないため）満たさない。コマンドが時間の上限（既定120秒。--timeoutで変更可）を
#      超えたら「未確認」として満たさない。終了コード2（判定不能）も「未確認」として満たさない
#      （実行できなかったことと不合格だったことを区別する。定義:
#      .claude/rules/always/verification/indeterminate-result/rule.md）
#   3. main へ入っている: 表のコミット欄から実在するコミット（`git cat-file -e`）を取り出し、
#      すべてが main の祖先（`git merge-base --is-ancestor`）である。「対象外」だけで構成され
#      実在するコミットを持たない指示書は対象なしとして満たす。ただし「完了」が1件以上あるのに
#      実在するコミットが1件も無い場合は満たさない
#   4. 公開が済んでいる: リポジトリ全体で1回だけ判定する。payload が現在の main と一致し、
#      agent-toolkit の payload を運ぶ枝（現在の HEAD）に未 push のコミットが0件であれば
#      「反映済み」。agent-toolkit の他の作業用の枝の未 push は判定に含めない
#      （同期が指示書の単位ではなく main の状態をまるごと写す形で行われるため、指示書ごとに追わない。
#      追跡先（@{u}）が解決できない場合は「判定不能」とし「反映済み」とは言わない）
#
# --write: 「確かめる手段」を実行した結果（完了/未着手/未確認）を「状態」欄へ書き込む。
#   「目視」の行は書き換えない（機械では判定できないため、書かれている値をそのまま残す）。
#   元の状態が「対象外」「判断待ち」の行は、確かめる手段が終了コード0を返しても「完了」へ
#   昇格させない（元の値のまま残す。不成立なら「未着手」へ戻し再検討を促す）。対象外・判断待ちは
#   対応の要不要という別軸の判断結果であり、機械的な確認の成否だけで人間の判断を書き換えては
#   ならないためである。
#   人が「状態」欄へ直接「完了」と書けるようにしないための仕組みであり、--write を使わない
#   既定の実行では「状態」欄を一切書き換えない（一覧を出すだけ）。
#
# 出力: 「公開の状態」の1行 / 「移せる」の一覧 / 「移せない」の一覧（理由付き。理由は11通り:
#   記録なし・確かめる手段の列が無い・判定の行が0件・目視の行がある・実測で満たさない判定がある・
#   確かめる手段が判定不能（終了コード2）・確かめる手段が時間の上限を超えた（未確認）・
#   判断待ちが残る・未着手/対応中が残る・
#   完了があるのに実在するコミットが1件も書かれていない・mainに入っていないコミットがある・公開が未反映）
#
# 必要性: 「どの指示書が終わって公開まで済んだか」を目で追う運用は、指示書が増えるたびに
#   確認漏れを起こす。実際、記録の状態語（未着手/対応中/完了/対象外/判断待ち）が指示書ごとに
#   自由記述であり、コミットが本当に main へ入っているか、payload が本当に公開済みかは
#   1件ずつ人手で `git merge-base --is-ancestor` や payload の差分を確かめない限り分からない。
#   繰り返し実行して同じ基準で判定する必要があるため、スクリプト化が要る。
#
#   段階2（実測）の必要性: 「状態」欄の文字列は自由記述であり、条件が実際に満たされたかを
#   裏付けずに「完了」と書けてしまう。実際に `docs/tasks/done/` 23件・判定168件を実測したところ
#   4件が偽の完了だった（状態欄が「完了」のまま、実際には self-test が不合格だった等）。
#   「確かめる手段」欄へコマンドそのものを書かせ、判定のたびに実行して終了コードで判定することで、
#   文字列だけでは検知できない偽の完了を機械的に検知する。
#
#   段階3（照合）の必要性: 段階1・2は指示書1件それぞれの内側だけを見る。指示書が
#   「片付けた」と主張していても、その裏付け（反映の記録）がどこにも無いまま
#   移せてしまっては「終わったことにしていないか」を確かめたことにならない。
#   `docs/tasks/work-records/改善反映台帳.md` は「スキル改善 反映対応台帳」であり、
#   載っているキーはすでに反映が済んだものである（台帳に載っているのに指示書が
#   無いのは正常な終わりの状態であり欠落ではない）。段階3は逆に、`docs/tasks/`
#   直下と `done/` の指示書本文に現れる「1-NN」形のキー（指示書が「これを片付けた」
#   と主張しているキー）を集め、各キーについて台帳に `（原番号 1-NN）` を含む行が
#   あり、かつその行の「検証方法と結果」欄が空・「—」・「-」のいずれでもないかを
#   確かめる。台帳に行が無い、または検証方法と結果欄が空のキーは「裏付けの無い
#   キー」として報告する。キーの情報源に指示書本文（`docs/tasks/` 直下 + `done/`）
#   を使い、`docs/tasks/指摘改善一覧.md` の見出し「### 1-NN.」だけに限定しないのは、
#   指示書が主張を書く場所（見出し・本文中の言及）を特定の1文書に限定する理由が
#   無いため。裏付けの照合先（改善反映台帳）は `docs/tasks/work-records/` 配下にあり
#   指示書の走査対象（`docs/tasks/` 直下 + `done/`）に含まれないため、走査対象の
#   キーが自分自身の裏付けとして誤って一致することはない。
#
# 代替案を採用しなかった理由:
#   - Bash ツール直叩き: 指示書それぞれで状態表の走査・確かめる手段の実行・コミットの実在確認・
#     main祖先判定・payload突合を対話セッションのたびに手で組み立てると、判定基準が実行のたびにぶれる
#   - generation-engine/scripts/ へ置く: `docs/` 配下は agent-toolkit の
#     `scripts/sync-manifest.json` で mirror として同期対象に登録されている。
#     つまり本スクリプトも配布される。配布されること自体は矛盾しない。指示書の形を定める
#     規約（`.claude/rules/always/tasks/instruction-format/rule.md`）も配布対象であり、
#     指示書の運用そのものが配布される資産に含まれるためである。それでも
#     `generation-engine/scripts/` へ置かないのは、公開から外すためではない。本スクリプトが
#     実装している流れの文書（`docs/design/指示書の片付け方.md`）と同じ場所に置くためである。
#     `generation-engine/scripts/` は納品物を生成する道具の置き場であり、指示書の運用を
#     判定する道具とは役割が異なる
#   - 既存 Makefile ターゲット拡張・package.json scripts 追加: このリポジトリはどちらも持たない
#   - `.claude/rules/always/publish/complete/check-publish-sync-gate.sh` の直接改修: あちらは
#     git commit 直後の advisory hook であり、判定条件も呼び出し契機も異なる（本スクリプトは
#     指示書単位の条件判定が主目的で、公開判定はその一部として同じ比較ロジックを流用するに
#     とどまる）。同スクリプトの diff 比較ロジック（同期対象6件・除外10件）はそのまま踏襲した
#   - `timeout`/`gtimeout` コマンドの利用: この環境にはどちらも存在しない
#     （`generation-engine/scripts/verification/run-layer-machine-checks.sh` の実測と同じ）。
#     同スクリプトと同じ考え方（`set -m` で専用プロセスグループとして起動し、ポーリングで
#     生存確認したうえで上限超過時に負のPIDへシグナルを送る）で自前実装する
#
# 保守責任者: 人手（ユーザー）。同期対象・除外名を変える場合は
#   `.claude/rules/always/publish/complete/rule.md` と `check-publish-sync-gate.sh` と
#   本ファイルの sync_targets・diff exclude を同時に更新する。同期対象そのものの正本は
#   agent-toolkit の `scripts/sync-manifest.json` である。`publish/complete/rule.md` の
#   一覧はこの正本から意図的に絞った diff 比較対象であり、古くなりうる。
#   「確かめる手段」欄の実行タイムアウト既定値（120秒）を変える場合は本ファイルの
#   TIMEOUT_SEC の既定値とこのコメントを同時に更新する。
#
# 廃棄条件: `docs/tasks/` による指示書運用自体を廃止した時、
#   または片付き判定を別の機構（CI 等）が標準で提供するようになった時。
#
# 既知の副作用: `docs/scripts/check-task-done-move.sh` の自己テストは、判定の充足状況の表に
#   「確かめる手段」列を持たない疑似指示書（3列: 項目|状態|コミット）を使って「3条件充足-通る」
#   ケースを組み立てている。本改修により、この列を持たない表は「確かめる手段の列が無い」として
#   一律に移せない扱いになるため、当該ケースは不合格に転じる。これは段階2（実測）を追加する
#   という本改修の意図どおりの挙動であり、`check-task-done-move.sh` 自体は本改修の変更許可対象
#   外のため、当該ファイルの疑似指示書は現時点では未追従のまま残る。
#
# 実装上の注意（macOS bash 3.2 / 実測に基づく回避策）:
#   - macOS 標準 awk は多バイト文字列の `==` 比較で誤判定する既知の不具合がある
#     （このリポジトリの `compare-with-previous.sh` の設計判断が既に明記している）。
#     本スクリプトの awk 呼び出しはすべて `LC_ALL=C` を付けて回避する
#   - `mapfile`・`declare -A` は使わない（bash 3.2 に無い）
#   - 空の配列を `set -u` の下で展開すると落ちるため、件数を確かめてから for に回す
#   - 引数なしの `mktemp` は使わない。`mktemp -d "${TMPDIR:-/tmp}/<名前>.XXXXXX"` の形を使う
#   - `extract_judgment_rows` は「対応の記録」節へ入る前を code fence の内外を問わず
#     無視し、節へ入った後も code fence の中は無視する。`指示書の形を揃える指示書.md` が
#     記録の節の書き方の見本をコードフェンスの中に埋め込んで持つため、見本の行を実データの
#     判定行と誤認しないための処理である（実際に指示書1件で踏んだ罠）
#   - 「確かめる手段」「状態」「コミット」の列位置は、見出し行のセル文字列で動的に特定する
#     （固定位置には依存しない）。列の並びが将来変わっても、見出しの文言さえ一致すれば動く
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$REPO_ROOT" ]; then
  echo "ERROR: git リポジトリの外で実行された" >&2
  exit 1
fi

TASKS_DIR="$REPO_ROOT/docs/tasks"
DONE_DIR="$TASKS_DIR/done"
MAIN_REF="main"
TOOLKIT_DIR="${TASK_DONE_TOOLKIT_DIR:-$HOME/github-public/agent-toolkit}"

if [ ! -d "$TASKS_DIR" ]; then
  echo "ERROR: $TASKS_DIR が無い" >&2
  exit 1
fi

command -v git >/dev/null 2>&1 || { echo "ERROR: git が無い" >&2; exit 1; }

# ---------- 「対応の記録」節の有無 ----------
has_record_heading() {
  LC_ALL=C awk '
    BEGIN { fence = 0 }
    {
      line = $0
      if (line ~ /^```/) { fence = !fence; next }
      if (fence) next
      if (line ~ /^#+[ \t]*([0-9]+\.[ \t]*)?対応の記録[ \t]*$/) { print "yes"; exit }
    }
  ' "$1"
}

# ---------- 「### 判定の充足状況」表から判定行を取り出す ----------
# 出力は2種の行:
#   "HEADER<TAB>yes|no"                          先頭1行。「確かめる手段」の列を持つか
#   "ROW<TAB>確かめる手段<TAB>状態<TAB>コミット"  データ行（「確かめる手段」列が無ければ出ない）
# 見出しの前後の code fence（```）は無視する。列位置は見出し行のセル文字列（動的）で特定する。
extract_judgment_rows() {
  LC_ALL=C awk '
    BEGIN { fence = 0; found_record = 0; found_table = 0 }
    {
      line = $0
      if (line ~ /^```/) { fence = !fence; next }
      if (fence) next
      if (!found_record) {
        if (line ~ /^#+[ \t]*([0-9]+\.[ \t]*)?対応の記録[ \t]*$/) { found_record = 1 }
        next
      }
      if (!found_table) {
        if (line ~ /^### 判定の充足状況/) { found_table = 1 }
        next
      }
      if (line ~ /^### /) { exit }
      if (line ~ /^## /) { exit }
      if (line ~ /^\|/) { print line }
    }
  ' "$1" \
  | LC_ALL=C awk '
      function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
      BEGIN { header_seen = 0; sep_seen = 0; confirm_col = 0; state_col = 0; commit_col = 0 }
      {
        # Markdown のセル内エスケープ `\|` は 1 個のパイプ文字として扱い、列の区切りとして
        # 解釈しない。分割前に `\|` を制御文字へ退避し、分割後に各セルへ `|` として復元する。
        line = $0
        gsub(/\\\|/, "\001", line)
        n = split(line, cols, "|")
        for (i = 1; i <= n; i++) { gsub(/\001/, "|", cols[i]); cols[i] = trim(cols[i]) }
        if (!header_seen) {
          header_seen = 1
          for (i = 2; i < n; i++) {
            if (cols[i] == "確かめる手段") confirm_col = i
            if (cols[i] == "状態")         state_col = i
            if (cols[i] == "コミット")     commit_col = i
          }
          if (confirm_col > 0) { print "HEADER\tyes" } else { print "HEADER\tno" }
          next
        }
        if (!sep_seen) {
          sep_seen = 1
          is_sep = 1
          for (i = 2; i < n; i++) { if (cols[i] !~ /^-+$/) { is_sep = 0; break } }
          if (is_sep) next
        }
        if (confirm_col == 0) next
        c  = cols[confirm_col]
        # 「確かめる手段」欄は Markdown のインラインコード（単一のバッククォート囲み）で
        # 書く見本になっている（rule.md の書き方の見本を参照）。囲みのバッククォートは
        # 表示上の体裁であり、実行するコマンド文字列の一部ではない。両端に1個ずつ
        # バッククォートがあれば、その対だけを取り除く（中身に別のバッククォートを
        # 含む多重の囲みは対象外。取り除かないとコマンドの実行結果を bash が
        # さらにコマンドとして実行してしまい、常に別物を実行する事故になる）。
        if (c ~ /^`.+`$/) { c = substr(c, 2, length(c) - 2) }
        s  = (state_col  > 0) ? cols[state_col]  : ""
        cm = (commit_col > 0) ? cols[commit_col] : ""
        print "ROW\t" c "\t" s "\t" cm
      }
    '
}

# ---------- コミット判定 ----------
commit_hashes_from_text() {
  printf '%s\n' "$1" | grep -oE '[0-9a-f]{7,40}' || true
}

commit_exists() {
  local h="$1"
  git -C "$REPO_ROOT" cat-file -e "${h}^{commit}" 2>/dev/null
}

is_ancestor_of_main() {
  local h="$1"
  git -C "$REPO_ROOT" merge-base --is-ancestor "$h" "$MAIN_REF" 2>/dev/null
}

# ---------- 公開状態の判定（リポジトリ全体で1回） ----------
PUBLISH_OK=0
PUBLISH_MSG="判定不能"

judge_publish() {
  if ! command -v jq >/dev/null 2>&1; then
    PUBLISH_MSG="判定不能（jqが無い）"
    return
  fi
  if [ ! -d "$TOOLKIT_DIR" ]; then
    # 全角文字との境界を明示し、LC_ALLの変更で変数名として誤読されるのを防ぐ。
    PUBLISH_MSG="未反映（agent-toolkitが見当たらない: ${TOOLKIT_DIR}）"
    return
  fi
  if ! git -C "$TOOLKIT_DIR" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
    PUBLISH_MSG="判定不能（agent-toolkitにorigin/mainが無い）"
    return
  fi
  if ! git -C "$REPO_ROOT" rev-parse --verify --quiet "$MAIN_REF" >/dev/null 2>&1; then
    PUBLISH_MSG="判定不能（${MAIN_REF}ブランチが無い）"
    return
  fi

  # payload を運ぶのは今 checkout している枝であり、agent-toolkit の他の作業用の枝の
  # 未pushはこのリポジトリの成果の公開可否とは無関係である。公開の判定が答えるべき問いは
  # 「reverse-docs-skills の成果が公開されたか」であり、agent-toolkit の別の作業が途中で
  # あることはこの問いへの答えを変えない。そのため運ぶ枝（現在の HEAD）だけの未push件数を見る。
  local cur_branch
  cur_branch="$(git -C "$TOOLKIT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [ -z "$cur_branch" ] || [ "$cur_branch" = "HEAD" ]; then
    PUBLISH_MSG="判定不能（agent-toolkitが枝を指していない）"
    return
  fi
  # 追跡先（@{u}）が解決できない場合は、押し出せているかどうか分からない状態であり
  # 「反映済み」と言ってはならないため、これまでと同じく「判定不能」で止める。
  local unpushed_count
  unpushed_count="$(git -C "$TOOLKIT_DIR" rev-list --count '@{u}..HEAD' 2>/dev/null || true)"
  if [ -z "$unpushed_count" ]; then
    PUBLISH_MSG="判定不能（agent-toolkitの${cur_branch}の追跡先が解決できない）"
    return
  fi
  if [ "$unpushed_count" -ne 0 ]; then
    PUBLISH_MSG="未反映（agent-toolkitの${cur_branch}に未pushのコミットが${unpushed_count}件ある）"
    return
  fi

  # 同期対象は check-publish-sync-gate.sh の diff 比較対象と揃える（RUNBOOK.md は
  # 同期対象だが diff 比較対象ではない。rule.md の既存判断のとおり）。
  local sync_targets rel
  sync_targets=(
    .claude/skills
    .claude/rules/scoped/portal/page-conventions/rule.md
    .claude/rules/always/verification/reverse-verification/rule.md
    delivery-payload
    generation-engine
    README.md
  )
  local existing_paths=()
  for rel in "${sync_targets[@]}"; do
    if git -C "$REPO_ROOT" cat-file -e "$MAIN_REF:$rel" 2>/dev/null; then
      existing_paths+=("$rel")
    fi
  done

  if [ "${#existing_paths[@]}" -eq 0 ]; then
    PUBLISH_MSG="判定不能（同期対象が${MAIN_REF}に存在しない）"
    return
  fi

  local tmp_src tmp_pub
  tmp_src="$(mktemp -d "${TMPDIR:-/tmp}/judge-task-done-src.XXXXXX")"
  tmp_pub="$(mktemp -d "${TMPDIR:-/tmp}/judge-task-done-pub.XXXXXX")"

  git -C "$REPO_ROOT" archive "$MAIN_REF" -- "${existing_paths[@]}" 2>/dev/null | tar -x -C "$tmp_src" 2>/dev/null
  git -C "$TOOLKIT_DIR" archive origin/main payload/reverse-docs-skills 2>/dev/null | tar -x -C "$tmp_pub" 2>/dev/null

  local mismatch=""
  for rel in "${existing_paths[@]}"; do
    # 除外名10件は .claude/rules/always/publish/complete/rule.md
    # 「公開対象から外す資産」節と揃える。
    if ! diff -r -q \
        --exclude=.DS_Store --exclude=node_modules --exclude='*.local.yml' \
        --exclude=flow-config --exclude=flow-context.yml \
        --exclude='.flow-progress.json' --exclude='.port-slot' \
        --exclude='.investigation-checklist.md' \
        --exclude='local-environment' --exclude='.cc-writes' \
        --exclude='prioritizing-improvement-tasks-from-images' \
        --exclude='改善課題タスク一覧.md' \
        --exclude='check-self-contained.sh' \
        "$tmp_src/$rel" "$tmp_pub/payload/reverse-docs-skills/$rel" >/dev/null 2>&1; then
      mismatch="${mismatch}${rel} "
    fi
  done

  rm -rf "$tmp_src" "$tmp_pub"

  if [ -n "$mismatch" ]; then
    PUBLISH_MSG="未反映（不一致: ${mismatch}）"
  else
    PUBLISH_OK=1
    PUBLISH_MSG="反映済み"
  fi
}

# ---------- 「確かめる手段」欄のコマンド実行（時間の上限つき） ----------
# `timeout`/`gtimeout` コマンドがこの環境に無いため、
# generation-engine/scripts/verification/run-layer-machine-checks.sh の run_one() と
# 同じ考え方（`set -m` で専用プロセスグループとして起動し、ポーリングで生存確認したうえで
# 上限超過時に負のPID（プロセスグループ）へシグナルを送る）で自前実装する。
CONFIRM_RC=0
run_confirm_command() {
  local cmd="$1" timeout_sec="$2"
  local out_file pid ticks max_ticks finished prev_monitor

  out_file="$(mktemp "${TMPDIR:-/tmp}/judge-task-done-cmd.XXXXXX" 2>/dev/null)" || true
  if [ -z "${out_file:-}" ]; then
    # 判定器自身が一時ファイルを作れない場合も「実行できなかった」であり不合格ではない。
    CONFIRM_RC=2
    return
  fi

  prev_monitor=0
  case $- in *m*) prev_monitor=1 ;; esac
  set -m

  {
    ( cd "$REPO_ROOT" && bash -c "$cmd" ) >"$out_file" 2>&1 &
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
    sleep 0.2
    ticks=$((ticks + 1))
  done

  if [ "$finished" -eq 1 ]; then
    { wait "$pid" 2>/dev/null; CONFIRM_RC=$?; } 2>/dev/null
  else
    {
      kill -TERM -$pid 2>/dev/null
      sleep 0.3
      kill -KILL -$pid 2>/dev/null
      wait "$pid" 2>/dev/null
    } 2>/dev/null
    CONFIRM_RC=124
  fi

  [ "$prev_monitor" -eq 0 ] && set +m
  rm -f "$out_file" 2>/dev/null
}

# ---------- 段階2（実測）: 「確かめる手段」欄を実行し満たすかを判定する ----------
# MEAS_OK=1: 満たす（列あり・行あり・目視なし・全行が終了コード0）
# MEAS_OK=0: 満たさない（MEAS_REASON に理由）
# 副産物として MEAS_CONFIRM[]・MEAS_RESULT[]（pass|fail|timeout|manual）・
# MEAS_ORIG_STATE[]・MEAS_COMMIT[] を行の順に積む（--write が使う）。
MEAS_OK=1
MEAS_REASON=""
MEAS_CONFIRM=()
MEAS_RESULT=()
MEAS_ORIG_STATE=()
MEAS_COMMIT=()

judge_measurement() {
  local file="$1" timeout_sec="$2"
  MEAS_OK=1
  MEAS_REASON=""
  MEAS_CONFIRM=()
  MEAS_RESULT=()
  MEAS_ORIG_STATE=()
  MEAS_COMMIT=()

  local raw
  raw="$(extract_judgment_rows "$file")"

  local header_ok
  header_ok="$(printf '%s\n' "$raw" | LC_ALL=C awk -F'\t' '$1=="HEADER"{print $2; exit}')"
  if [ "$header_ok" != "yes" ]; then
    MEAS_OK=0
    MEAS_REASON="確かめる手段の列が無い"
    return
  fi

  local data_rows
  data_rows="$(printf '%s\n' "$raw" | sed -n 's/^ROW\t//p')"
  if [ -z "$data_rows" ]; then
    MEAS_OK=0
    MEAS_REASON="判定の行が0件"
    return
  fi

  local confirm state cm has_shime=0 has_fail=0 has_timeout=0 has_indeterminate=0 rc
  while IFS=$'\t' read -r confirm state cm; do
    MEAS_CONFIRM+=("$confirm")
    MEAS_ORIG_STATE+=("$state")
    MEAS_COMMIT+=("$cm")
    if [ "$confirm" = "目視" ]; then
      MEAS_RESULT+=("manual")
      has_shime=1
      continue
    fi
    if [ -z "$confirm" ]; then
      # 確かめる手段が空欄の行は、機械では確かめようがないため不合格として扱う。
      MEAS_RESULT+=("fail")
      has_fail=1
      continue
    fi
    run_confirm_command "$confirm" "$timeout_sec"
    rc="$CONFIRM_RC"
    if [ "$rc" -eq 0 ]; then
      MEAS_RESULT+=("pass")
    elif [ "$rc" -eq 2 ]; then
      # 終了コード2は判定不能（実行できなかった）であり、不合格（満たさない）ではない。
      # 実行環境の制約（サンドボックスによる一時領域への書き込み拒否等）で検査を
      # 実行できなかった場合が該当する。定義:
      # .claude/rules/always/verification/indeterminate-result/rule.md
      MEAS_RESULT+=("indeterminate")
      has_indeterminate=1
    elif [ "$rc" -eq 124 ]; then
      MEAS_RESULT+=("timeout")
      has_timeout=1
    else
      MEAS_RESULT+=("fail")
      has_fail=1
    fi
  done <<< "$data_rows"

  if [ "$has_shime" -eq 1 ]; then
    MEAS_OK=0
    MEAS_REASON="目視の行がある"
    return
  fi
  if [ "$has_indeterminate" -eq 1 ]; then
    MEAS_OK=0
    MEAS_REASON="確かめる手段が判定不能（終了コード2）。実行環境の制約で検査を実行できなかった"
    return
  fi
  if [ "$has_timeout" -eq 1 ]; then
    MEAS_OK=0
    MEAS_REASON="確かめる手段が時間の上限（${timeout_sec}秒）を超えた（未確認）"
    return
  fi
  if [ "$has_fail" -eq 1 ]; then
    MEAS_OK=0
    MEAS_REASON="実測で満たさない判定がある"
    return
  fi
  MEAS_OK=1
  MEAS_REASON=""
}

# ---------- 「状態」欄の書き込み（--write） ----------
# 対応表: 実行結果 pass→完了 / fail→未着手 / indeterminate（終了コード2）→未確認 /
# timeout→未確認 / manual（目視）→元の値のまま
# ただし元の状態が「対象外」または「判断待ち」の行は、pass（確かめる手段が終了コード0を
# 返した）であっても「完了」へ昇格させない。「対象外」は対応の要不要という別軸の判断結果
# であり、確かめる手段の成否は「その判断の前提が今も成立しているか」を確認するものに
# すぎない（成立＝対象外の維持、不成立＝前提が崩れたので未着手へ戻し再検討を促す）。
# 「判断待ち」も同様に、機械的な確認の成否だけで人間の判断を確定させてはならない。
write_measurement_states() {
  local file="$1" timeout_sec="$2"
  judge_measurement "$file" "$timeout_sec"

  local n="${#MEAS_CONFIRM[@]}"
  if [ "$n" -eq 0 ]; then
    return
  fi

  local states_tmp
  states_tmp="$(mktemp "${TMPDIR:-/tmp}/judge-task-done-states.XXXXXX" 2>/dev/null)" || true
  if [ -z "${states_tmp:-}" ]; then
    return
  fi

  : > "$states_tmp"
  local i
  for ((i = 0; i < n; i++)); do
    case "${MEAS_RESULT[$i]}" in
      pass)
        case "${MEAS_ORIG_STATE[$i]}" in
          対象外|判断待ち) echo "${MEAS_ORIG_STATE[$i]}" >> "$states_tmp" ;;
          *)                echo "完了" >> "$states_tmp" ;;
        esac
        ;;
      fail)    echo "未着手" >> "$states_tmp" ;;
      indeterminate)
        # 判定不能は「実行できなかった」であり「不合格だった」ではない。「対象外」
        # 「判断待ち」はその前提が崩れたことを確かめられていないため元の値のまま残す。
        case "${MEAS_ORIG_STATE[$i]}" in
          対象外|判断待ち) echo "${MEAS_ORIG_STATE[$i]}" >> "$states_tmp" ;;
          *)                echo "未確認" >> "$states_tmp" ;;
        esac
        ;;
      timeout) echo "未確認" >> "$states_tmp" ;;
      *)       echo "${MEAS_ORIG_STATE[$i]}" >> "$states_tmp" ;;
    esac
  done

  apply_states_to_file "$file" "$states_tmp"
  rm -f "$states_tmp"
}

# ---------- ファイルの「状態」列を states_file の内容で順に置き換える ----------
# 「対応の記録」節の「### 判定の充足状況」表の中だけを対象にする。
# 見出し行・区切り行・表の外は一切変えず、データ行の「状態」セルだけを書き換える。
apply_states_to_file() {
  local file="$1" states_file="$2"
  local tmp_out
  tmp_out="$(mktemp "${TMPDIR:-/tmp}/judge-task-done-out.XXXXXX" 2>/dev/null)" || true
  if [ -z "${tmp_out:-}" ]; then
    return
  fi

  LC_ALL=C awk -v statesfile="$states_file" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    BEGIN {
      rn = 0
      while ((getline sline < statesfile) > 0) { rn++; newstate[rn] = sline }
      close(statesfile)
      fence = 0; found_record = 0; found_table = 0
      header_seen = 0; sep_seen = 0
      state_col = 0
      cur = 0
    }
    {
      line = $0
      if (line ~ /^```/) { fence = !fence; print; next }
      if (fence) { print; next }
      if (!found_record) {
        print
        if (line ~ /^#+[ \t]*([0-9]+\.[ \t]*)?対応の記録[ \t]*$/) { found_record = 1 }
        next
      }
      if (!found_table) {
        print
        if (line ~ /^### 判定の充足状況/) { found_table = 1 }
        next
      }
      if (found_table && (line ~ /^### / || line ~ /^## /)) {
        found_table = 0
        print
        next
      }
      if (found_table && line ~ /^\|/) {
        # Markdown のセル内エスケープ `\|` は 1 個のパイプ文字として扱い、列の区切りとして
        # 解釈しない。分割前に `\|` を制御文字へ退避し、再構築した行へ書き戻す直前に
        # 元のエスケープ表記（`\|`）へ復元する（他の列の内容を変えないため）。
        esc_line = line
        gsub(/\\\|/, "\001", esc_line)
        n = split(esc_line, cols, "|")
        if (!header_seen) {
          header_seen = 1
          for (i = 2; i < n; i++) { if (trim(cols[i]) == "状態") state_col = i }
          print
          next
        }
        if (!sep_seen) {
          sep_seen = 1
          is_sep = 1
          for (i = 2; i < n; i++) { if (trim(cols[i]) !~ /^-+$/) { is_sep = 0; break } }
          if (is_sep) { print; next }
        }
        cur++
        if (state_col > 0 && (cur in newstate)) {
          cols[state_col] = " " newstate[cur] " "
        }
        rebuilt = cols[1]
        for (i = 2; i <= n; i++) { rebuilt = rebuilt "|" cols[i] }
        gsub(/\001/, "\\|", rebuilt)
        print rebuilt
        next
      }
      print
    }
  ' "$file" > "$tmp_out"

  mv "$tmp_out" "$file"
}

# ---------- 段階3（照合）: 指示書が主張するキーに台帳の裏付けがあるか ----------
# キーの情報源は docs/tasks/ 直下 + done/ の指示書の冒頭4行目
# 「**元の指摘**: 1-NN, 1-NN」（instruction-format/rule.md 準拠）だけに限る。
# 本文の地の文（見出し「### 1-NN.」・「原番号 1-NN」）はもう走査しない。
# 地の文の走査は、工程番号・範囲・版の断片（例: 「Stage 1-3の成果物」）を
# 指摘のキーとして誤って拾う事故を招いた（実測: `\b1-[0-9]+\b` の緩い抽出は
# 64件を拾ったが、そのうち9件は工程番号など指摘のキーでないものだった。例:
# `docs/tasks/done/スキル実装計画.md` の「Stage 1-3」「Stage 1-4」）。指示書が
# 主張するキーを、書き手が明示した4行目の欄だけから読む形へ移し、この誤りの
# 芽そのものを断つ（`指摘の追跡を機械で読める形にする指示書.md` が指示する変更）。
# 裏付けの照合先は docs/tasks/work-records/改善反映台帳.md の
# 「（原番号 1-NN）」（例: 原番号 1-48）を含む行の「検証方法と結果」欄。
# 書式は実測で確認済み（該当行を `|` で分割した最後から2番目のセルが
# 「検証方法と結果」欄の値になる）。この照合先の書式・key_backed_in_ledger の
# 実装は変えない。

# 指示書ファイル群から重複無しのキー一覧（1行1キー、"1-NN" の形）を取り出す。
# 各ファイルの冒頭4行目「**元の指摘**:」の値だけを読む。値が「なし」、または
# 行そのものが無い場合はそのファイルからは0件とする（エラーにしない）。
# 値はカンマ区切りで複数件を並べられる（件数に上限は無い）。各要素は
# 前後の空白を落としたうえで `1-NN` の形（`1-` に続き1桁以上の数字）に一致する
# ものだけを採用し、それ以外（instruction-format の検査12が拒否する形式不正な
# 値が万一残っていた場合の保険）は無視する。
extract_claimed_keys() {
  local files=("$@")
  local f
  # `${files[@]}` を空配列のまま展開すると bash 3.2 の `set -u` 下で
  # unbound variable になる（本ファイル冒頭の実装上の注意を参照）。
  # 件数を確かめてから展開する。
  if [ "${#files[@]}" -eq 0 ]; then
    return 0
  fi
  for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    local val
    # 冒頭20行だけを見る（instruction-format/check-instruction-format.sh の
    # 検査2と同じ head -20 の範囲）。本文中のコード柵の例示（例:
    # 「```」で挟まれた `**元の指摘**: 1-62, 1-65, 1-81` という書式説明）を
    # 実際の宣言と誤って拾わないようにするための境界。
    val="$(LC_ALL=C head -20 "$f" 2>/dev/null | LC_ALL=C grep -m1 -E '^\*\*元の指摘\*\*:' \
      | LC_ALL=C sed -E 's/^\*\*元の指摘\*\*:[[:space:]]*//; s/[[:space:]]+$//')"
    [ -z "$val" ] && continue
    [ "$val" = "なし" ] && continue
    LC_ALL=C awk -v v="$val" '
      BEGIN {
        n = split(v, arr, ",")
        for (i = 1; i <= n; i++) {
          s = arr[i]
          gsub(/^[ \t]+|[ \t]+$/, "", s)
          if (s ~ /^1-[0-9]+$/) print s
        }
      }
    '
  done | LC_ALL=C sort -u
}

# 1個のキーが台帳（ledger_file）で裏付けられているか。
# 「原番号 <key>）」を含む表の行（先頭が「|」の行に限る。地の文の中で偶然
# キーへ言及しているだけの行は表の行ではないため対象外にする。実測で
# 「第33回で未解決として残した…（原番号 1-26）は、…」のような地の文がヒットし、
# 表の行を見ずに誤って「裏付けなし」と判定する事故を実際に踏んだ）を1件以上
# 取り出し、そのいずれかの行を「|」で分割した最後から2番目のセル
# （「検証方法と結果」欄）が、前後の空白を除いて空・「—」・「-」のいずれでもなければ
# 裏付けありとして 0 を返す。表の行が1件も見つからない、またはどの行の当該欄も
# 空・「—」・「-」なら裏付けなしとして 1 を返す（同じキーが複数行に跨がる項目が
# 実在するため、最初の1行だけで判定せず全行を見る）。セル内エスケープ `\|` は
# extract_judgment_rows と同じ考え方で1個のパイプ文字として扱い、列の区切りとして
# 解釈しない。
# 探す文字列は「原番号 <key>）」であり、直前に開き括弧「（」があることは要求しない。
# 台帳には「（原番号 1-3）」のように直前が開き括弧の書き方と、
# 「（原文未取得、原番号 1-76）」のように間に語が挟まる書き方の両方が実在する
# （実測: 前者119件・後者1件）。開き括弧の直前一致を要求すると後者の書き方が
# 「裏付けの無いキー」として誤検知される。閉じ括弧「）」で終わることは要求し続ける
# （外すと「原番号 1-7」が「原番号 1-76）」の一部として誤って一致してしまう）。
key_backed_in_ledger() {
  local key="$1" ledger_file="$2"
  [ -f "$ledger_file" ] || return 1
  local rows line last
  rows="$(LC_ALL=C grep -F "原番号 ${key}）" "$ledger_file" 2>/dev/null | LC_ALL=C grep -E '^\|')"
  [ -z "$rows" ] && return 1
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    last="$(printf '%s\n' "$line" | LC_ALL=C awk '
      function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
      {
        esc = $0
        gsub(/\\\|/, "\001", esc)
        n = split(esc, cols, "|")
        val = cols[n-1]
        gsub(/\001/, "|", val)
        print trim(val)
      }
    ')"
    case "$last" in
      ""|"—"|"-") : ;;
      *) return 0 ;;
    esac
  done <<< "$rows"
  return 1
}

# 照合本体。CROSS_TOTAL（指示書が主張するキーの件数）と CROSS_MISSING[]（台帳に
# 裏付けの無いキー）を積む。主張の一覧が空（指示書にキーが1件も無い）でも
# エラーにはせず、CROSS_TOTAL=0・CROSS_MISSING=() のまま返る。
CROSS_TOTAL=0
CROSS_MISSING=()
run_cross_check_core() {
  local ledger_file="$1"; shift
  local files=("$@")
  CROSS_TOTAL=0
  CROSS_MISSING=()

  local keys key
  if [ "${#files[@]}" -eq 0 ]; then
    return
  fi
  keys="$(extract_claimed_keys "${files[@]}")"
  [ -z "$keys" ] && return

  while IFS= read -r key; do
    [ -z "$key" ] && continue
    CROSS_TOTAL=$((CROSS_TOTAL + 1))
    if ! key_backed_in_ledger "$key" "$ledger_file"; then
      CROSS_MISSING+=("$key")
    fi
  done <<< "$keys"
}

# 実際の docs/tasks/ 直下 + done/ を走査対象として照合を実行し、結果を表示する。
run_cross_check() {
  local ledger_file="$TASKS_DIR/work-records/改善反映台帳.md"
  local all_files=()
  shopt -s nullglob
  all_files=("$TASKS_DIR"/*.md "$DONE_DIR"/*.md)
  shopt -u nullglob

  if [ "${#all_files[@]}" -gt 0 ]; then
    run_cross_check_core "$ledger_file" "${all_files[@]}"
  else
    run_cross_check_core "$ledger_file"
  fi

  echo "指示書が主張するキー: ${CROSS_TOTAL}件"
  echo
  if [ "${#CROSS_MISSING[@]}" -gt 0 ]; then
    echo "裏付けの無いキー:"
    for key in "${CROSS_MISSING[@]}"; do
      echo "- $key"
    done
  else
    echo "すべてのキーに台帳の裏付けがある。"
  fi
}

# ---------- 指示書ごとの判定 ----------
MOVABLE=()
BLOCKED_FILES=()
BLOCKED_REASONS=()

judge_file() {
  local file="$1" fname
  fname="$(basename "$file")"

  if [ -z "$(has_record_heading "$file")" ]; then
    BLOCKED_FILES+=("$fname")
    BLOCKED_REASONS+=("記録なし")
    return
  fi

  # ---- 段階2（実測）: 確かめる手段の列・目視・実行結果 ----
  judge_measurement "$file" "$TIMEOUT_SEC"
  if [ "$MEAS_OK" -ne 1 ]; then
    BLOCKED_FILES+=("$fname")
    BLOCKED_REASONS+=("$MEAS_REASON")
    return
  fi

  # ---- 段階1（書式）: 状態の語の妥当性・コミットの収集 ----
  local completed=0 all_hashes="" idx n_rows
  n_rows="${#MEAS_ORIG_STATE[@]}"
  for ((idx = 0; idx < n_rows; idx++)); do
    local st="${MEAS_ORIG_STATE[$idx]}"
    case "$st" in
      完了) completed=$((completed + 1)) ;;
      対象外) : ;;
      判断待ち)
        BLOCKED_FILES+=("$fname")
        BLOCKED_REASONS+=("判断待ちが残る")
        return
        ;;
      *)
        BLOCKED_FILES+=("$fname")
        BLOCKED_REASONS+=("未着手・対応中が残る")
        return
        ;;
    esac
    local toks
    toks="$(commit_hashes_from_text "${MEAS_COMMIT[$idx]}")"
    if [ -n "$toks" ]; then
      all_hashes="${all_hashes}${toks}
"
    fi
  done

  all_hashes="$(printf '%s\n' "$all_hashes" | grep -v '^$' | LC_ALL=C sort -u || true)"

  local existing_hashes="" h
  if [ -n "$all_hashes" ]; then
    while IFS= read -r h; do
      [ -z "$h" ] && continue
      if commit_exists "$h"; then
        existing_hashes="${existing_hashes}${h}
"
      fi
    done <<< "$all_hashes"
    existing_hashes="$(printf '%s\n' "$existing_hashes" | grep -v '^$' || true)"
  fi

  if [ -z "$existing_hashes" ]; then
    if [ "$completed" -gt 0 ]; then
      BLOCKED_FILES+=("$fname")
      BLOCKED_REASONS+=("完了があるのに実在するコミットが1件も書かれていない")
      return
    fi
  else
    local bad=0
    while IFS= read -r h; do
      [ -z "$h" ] && continue
      if ! is_ancestor_of_main "$h"; then
        bad=1
        break
      fi
    done <<< "$existing_hashes"
    if [ "$bad" -eq 1 ]; then
      BLOCKED_FILES+=("$fname")
      BLOCKED_REASONS+=("mainに入っていないコミットがある")
      return
    fi
  fi

  if [ "$PUBLISH_OK" -ne 1 ]; then
    BLOCKED_FILES+=("$fname")
    BLOCKED_REASONS+=("公開が未反映")
    return
  fi

  MOVABLE+=("$fname")
}

# ---------- --only の対象パス解決 ----------
# 成功時: ONLY_FILE に絶対パスを設定し、返り値0。
# 失敗時: エラーメッセージを stderr へ出し、ONLY_FILE を空のまま、返り値1。
# 呼び出し側（引数の解釈の直後）がこの返り値を見て exit 1 する。
ONLY_FILE=""
resolve_only_path() {
  local path="$1" abs
  ONLY_FILE=""
  case "$path" in
    /*) abs="$path" ;;
    *)  abs="$REPO_ROOT/$path" ;;
  esac
  if [ ! -f "$abs" ]; then
    echo "ERROR: --only に指定されたパスが無い: $path" >&2
    return 1
  fi
  case "$abs" in
    "$TASKS_DIR"/*)
      ONLY_FILE="$abs"
      return 0
      ;;
    *)
      echo "ERROR: --only に指定されたパスは docs/tasks/ の配下でない: $path" >&2
      return 1
      ;;
  esac
}

# ---------- 通常モード（判定・--write・出力・--apply） ----------
# ONLY_FILE が空なら $TASKS_DIR/*.md 全件、非空ならその1件だけを対象にする。
# --only を指定しない既定の実行では ONLY_FILE が空のままなので、挙動はこれまでと変わらない。
run_normal_mode() {
  local target_files=() f

  if [ -n "$ONLY_FILE" ]; then
    target_files=("$ONLY_FILE")
  else
    shopt -s nullglob
    target_files=("$TASKS_DIR"/*.md)
    shopt -u nullglob
  fi

  if [ "$WRITE" -eq 1 ] && [ "${#target_files[@]}" -gt 0 ]; then
    for f in "${target_files[@]}"; do
      write_measurement_states "$f" "$TIMEOUT_SEC"
    done
  fi

  judge_publish

  MOVABLE=()
  BLOCKED_FILES=()
  BLOCKED_REASONS=()
  if [ "${#target_files[@]}" -gt 0 ]; then
    for f in "${target_files[@]}"; do
      judge_file "$f"
    done
  fi

  # ---------- 出力 ----------
  echo "公開の状態: ${PUBLISH_MSG}"
  echo
  echo "移せる:"
  if [ "${#MOVABLE[@]}" -gt 0 ]; then
    for f in "${MOVABLE[@]}"; do
      echo "- $f"
    done
  else
    echo "（0件）"
  fi
  echo
  echo "移せない:"
  if [ "${#BLOCKED_FILES[@]}" -gt 0 ]; then
    local i=0
    for f in "${BLOCKED_FILES[@]}"; do
      echo "- ${f}: ${BLOCKED_REASONS[$i]}"
      i=$((i + 1))
    done
  else
    echo "（0件）"
  fi

  # ---------- --apply ----------
  if [ "$APPLY" -eq 1 ]; then
    echo
    if [ "${#MOVABLE[@]}" -eq 0 ]; then
      echo "--apply: 移す対象が無い"
    else
      mkdir -p "$DONE_DIR"
      for f in "${MOVABLE[@]}"; do
        git -C "$REPO_ROOT" mv "docs/tasks/$f" "docs/tasks/done/$f"
      done
      echo "--apply: ${#MOVABLE[@]}件を docs/tasks/done/ へ移した（コミットはしていない）"
    fi
  fi
}

# ---------- self-test ----------
run_self_test() {
  if ! tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/judge-task-done-test.XXXXXX" 2>/dev/null)" || [ -z "$tmpdir" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため自己テストを判定できません（mktemp -d が一時領域へ書き込めませんでした）"
    return 2
  fi
  trap 'rm -rf "$tmpdir"' EXIT

  local pass=0 fail=0

  mk_doc() {
    local table="$1"
    printf '# サンプル指示書\n\n## 対応の記録\n\n### 判定の充足状況\n\n%s\n' "$table"
  }

  run_meas_case() {
    local name="$1" file="$2" timeout_sec="$3" expect_ok="$4" expect_substr="${5:-}"
    judge_measurement "$file" "$timeout_sec"
    local got="fail"
    if [ "$MEAS_OK" = "$expect_ok" ]; then
      if [ -z "$expect_substr" ]; then
        got="pass"
      else
        case "$MEAS_REASON" in
          *"$expect_substr"*) got="pass" ;;
        esac
      fi
    fi
    if [ "$got" = "pass" ]; then
      echo "[PASS] ${name}"
      pass=$((pass + 1))
    else
      echo "[FAIL] ${name}（MEAS_OK=${MEAS_OK} MEAS_REASON=${MEAS_REASON}）"
      fail=$((fail + 1))
    fi
  }

  echo "実行 23 件"

  # 0. 確かめる手段がバッククォート囲み（rule.mdの見本と同じ書き方） -> 中身のコマンドとして実行され満たす
  #    （囲みを剥がさずに実行すると、バッククォート付き文字列がコマンド置換として実行され、
  #    その出力をさらにコマンドとして実行しようとして必ず失敗する。実際に本番の指示書へ
  #    見本どおりバッククォート付きで書いたところ、この不具合を実測で踏んだ）
  local f0="$tmpdir/case0.md"
  mk_doc "$(printf '| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |\n|---|---|---|---|---|\n| 1. 何か | `true` | 未着手 | — | — |')" > "$f0"
  run_meas_case "確かめる手段がバッククォート囲み" "$f0" 5 1

  # 1. 確かめる手段が終了コード0を返す -> 満たす（移せる）
  local f1="$tmpdir/case1.md"
  mk_doc "$(printf '| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |\n|---|---|---|---|---|\n| 1. 何か | true | 未着手 | — | — |')" > "$f1"
  run_meas_case "確かめる手段が終了コード0を返す" "$f1" 5 1

  # 2. 確かめる手段が終了コード1を返す -> 満たさない（移せない）
  local f2="$tmpdir/case2.md"
  mk_doc "$(printf '| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |\n|---|---|---|---|---|\n| 1. 何か | false | 未着手 | — | — |')" > "$f2"
  run_meas_case "確かめる手段が終了コード1を返す" "$f2" 5 0 "実測"

  # 3. 確かめる手段が目視 -> 満たさない（移せない）
  local f3="$tmpdir/case3.md"
  mk_doc "$(printf '| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |\n|---|---|---|---|---|\n| 1. 何か | 目視 | 未着手 | — | — |')" > "$f3"
  run_meas_case "確かめる手段が目視" "$f3" 5 0 "目視"

  # 4. 確かめる手段が時間の上限を超える -> 満たさない（未確認・移せない）
  local f4="$tmpdir/case4.md"
  mk_doc "$(printf '| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |\n|---|---|---|---|---|\n| 1. 何か | sleep 3 | 未着手 | — | — |')" > "$f4"
  run_meas_case "確かめる手段が時間の上限を超える" "$f4" 1 0 "時間の上限"

  # 5. 表が4列（確かめる手段の列が無い） -> 満たさない（移せない）
  local f5="$tmpdir/case5.md"
  mk_doc "$(printf '| 判定 | 状態 | コミット | 確かめた内容 |\n|---|---|---|---|\n| 1. 何か | 完了 | abc1234 | 済 |')" > "$f5"
  run_meas_case "表が4列（確かめる手段の列が無い）" "$f5" 5 0 "確かめる手段の列が無い"

  # 6. --write（write_measurement_states）で状態欄が書き換わる
  local f6="$tmpdir/case6.md"
  mk_doc "$(printf '| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |\n|---|---|---|---|---|\n| 1. 何か | true | 未着手 | — | — |\n| 2. 何か | false | 未着手 | — | — |')" > "$f6"
  write_measurement_states "$f6" 5
  local got6="fail"
  if grep -qE '\|[[:space:]]*1\. 何か[[:space:]]*\|[[:space:]]*true[[:space:]]*\|[[:space:]]*完了[[:space:]]*\|[[:space:]]*—[[:space:]]*\|[[:space:]]*—[[:space:]]*\|' "$f6" \
     && grep -qE '\|[[:space:]]*2\. 何か[[:space:]]*\|[[:space:]]*false[[:space:]]*\|[[:space:]]*未着手[[:space:]]*\|[[:space:]]*—[[:space:]]*\|[[:space:]]*—[[:space:]]*\|' "$f6"; then
    got6="pass"
  fi
  if [ "$got6" = "pass" ]; then
    echo "[PASS] --writeで状態欄が書き換わる"
    pass=$((pass + 1))
  else
    echo "[FAIL] --writeで状態欄が書き換わる"
    echo "       中身:"
    sed 's/^/       /' "$f6"
    fail=$((fail + 1))
  fi

  # 7. 確かめる手段にセル内エスケープ `\|` を含む -> 1個のパイプ文字として復元され、
  #    コマンドが分断されずに実行される（「目視」の行が無い構成にする。judge_measurement は
  #    目視の行を先に判定して早期リターンするため、目視の行があるとパイプの破損まで
  #    到達しない。実際に本番の指示書で目視の行を除去した後に初めて破損が顕在化した）
  local f7="$tmpdir/case7.md"
  mk_doc "$(printf '| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |\n|---|---|---|---|---|\n| 1. 何か | `test "a\|b" = "a\|b"` | 未着手 | — | — |')" > "$f7"
  run_meas_case "確かめる手段のセル内エスケープ\|が1個のパイプとして復元される" "$f7" 5 1

  # 8. --write は元の状態が「対象外」「判断待ち」の行を、確かめる手段が終了コード0でも
  #    「完了」へ昇格させない（対応の要不要という別軸の判断結果であり、機械的な確認の
  #    成否だけで書き換えてはならない）
  local f8="$tmpdir/case8.md"
  mk_doc "$(printf '| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |\n|---|---|---|---|---|\n| 1. 何か | true | 対象外 | — | — |\n| 2. 何か | true | 判断待ち | — | — |\n| 3. 何か | false | 対象外 | — | — |')" > "$f8"
  write_measurement_states "$f8" 5
  local got8="fail"
  if grep -qE '\|[[:space:]]*1\. 何か[[:space:]]*\|[[:space:]]*true[[:space:]]*\|[[:space:]]*対象外[[:space:]]*\|[[:space:]]*—[[:space:]]*\|[[:space:]]*—[[:space:]]*\|' "$f8" \
     && grep -qE '\|[[:space:]]*2\. 何か[[:space:]]*\|[[:space:]]*true[[:space:]]*\|[[:space:]]*判断待ち[[:space:]]*\|[[:space:]]*—[[:space:]]*\|[[:space:]]*—[[:space:]]*\|' "$f8" \
     && grep -qE '\|[[:space:]]*3\. 何か[[:space:]]*\|[[:space:]]*false[[:space:]]*\|[[:space:]]*未着手[[:space:]]*\|[[:space:]]*—[[:space:]]*\|[[:space:]]*—[[:space:]]*\|' "$f8"; then
    got8="pass"
  fi
  if [ "$got8" = "pass" ]; then
    echo "[PASS] --writeが対象外・判断待ちを完了へ昇格させない"
    pass=$((pass + 1))
  else
    echo "[FAIL] --writeが対象外・判断待ちを完了へ昇格させない"
    echo "       中身:"
    sed 's/^/       /' "$f8"
    fail=$((fail + 1))
  fi

  # 9. 段階3（照合）: 指示書が主張したキーに台帳の裏付けがある -> 落ちているキー0件
  local f9_ledger="$tmpdir/case9-ledger.md"
  local f9_task="$tmpdir/case9-task.md"
  printf '| 項目 | 項目名 | 反映先資産 | 反映箇所 | 配線した呼び出し箇所 | 検証方法と結果 |\n|---|---|---|---|---|---|\n| x-1 | 何か（原番号 1-99） | path | 箇所 | 呼び出し | self-test 実走: exit 0 |\n' > "$f9_ledger"
  printf '# サンプル指示書\n\n**元の指摘**: 1-99\n' > "$f9_task"
  run_cross_check_core "$f9_ledger" "$f9_task"
  local got9="fail"
  if [ "$CROSS_TOTAL" -eq 1 ] && [ "${#CROSS_MISSING[@]}" -eq 0 ]; then
    got9="pass"
  fi
  if [ "$got9" = "pass" ]; then
    echo "[PASS] 段階3-主張したキーに台帳の裏付けがある"
    pass=$((pass + 1))
  else
    echo "[FAIL] 段階3-主張したキーに台帳の裏付けがある（CROSS_TOTAL=${CROSS_TOTAL} MISSING=${#CROSS_MISSING[@]}）"
    fail=$((fail + 1))
  fi

  # 10. 段階3（照合）: 主張したキーが台帳のどの行にも現れない -> そのキーを報告する
  local f10_ledger="$tmpdir/case10-ledger.md"
  local f10_task="$tmpdir/case10-task.md"
  printf '| 項目 | 項目名 | 反映先資産 | 反映箇所 | 配線した呼び出し箇所 | 検証方法と結果 |\n|---|---|---|---|---|---|\n| x-1 | 何か（原番号 1-1） | path | 箇所 | 呼び出し | self-test 実走: exit 0 |\n' > "$f10_ledger"
  printf '# サンプル指示書\n\n**元の指摘**: 1-98\n' > "$f10_task"
  run_cross_check_core "$f10_ledger" "$f10_task"
  local got10="fail"
  if [ "$CROSS_TOTAL" -eq 1 ] && [ "${#CROSS_MISSING[@]}" -eq 1 ] && [ "${CROSS_MISSING[0]}" = "1-98" ]; then
    got10="pass"
  fi
  if [ "$got10" = "pass" ]; then
    echo "[PASS] 段階3-裏付けの無いキーを報告する"
    pass=$((pass + 1))
  else
    echo "[FAIL] 段階3-裏付けの無いキーを報告する（CROSS_TOTAL=${CROSS_TOTAL} MISSING=${CROSS_MISSING[*]:-}）"
    fail=$((fail + 1))
  fi

  # 11. 段階3（照合）: 台帳に行はあるが「検証方法と結果」欄が空（—）-> 裏付けなしとして報告する
  local f11_ledger="$tmpdir/case11-ledger.md"
  local f11_task="$tmpdir/case11-task.md"
  printf '| 項目 | 項目名 | 反映先資産 | 反映箇所 | 配線した呼び出し箇所 | 検証方法と結果 |\n|---|---|---|---|---|---|\n| x-1 | 何か（原番号 1-97） | path | 箇所 | 呼び出し | — |\n' > "$f11_ledger"
  printf '# サンプル指示書\n\n**元の指摘**: 1-97\n' > "$f11_task"
  run_cross_check_core "$f11_ledger" "$f11_task"
  local got11="fail"
  if [ "$CROSS_TOTAL" -eq 1 ] && [ "${#CROSS_MISSING[@]}" -eq 1 ] && [ "${CROSS_MISSING[0]}" = "1-97" ]; then
    got11="pass"
  fi
  if [ "$got11" = "pass" ]; then
    echo "[PASS] 段階3-検証方法と結果が空なら裏付けなし"
    pass=$((pass + 1))
  else
    echo "[FAIL] 段階3-検証方法と結果が空なら裏付けなし（CROSS_TOTAL=${CROSS_TOTAL} MISSING=${CROSS_MISSING[*]:-}）"
    fail=$((fail + 1))
  fi

  # 12. 段階3（照合）: 指示書側に主張するキーが1件も無ければ0件（エラーにしない）
  local f12_ledger="$tmpdir/case12-ledger.md"
  local f12_task="$tmpdir/case12-task.md"
  printf '| 項目 | 項目名 | 反映先資産 | 反映箇所 | 配線した呼び出し箇所 | 検証方法と結果 |\n|---|---|---|---|---|---|\n| x-1 | 何か（原番号 1-1） | path | 箇所 | 呼び出し | self-test 実走: exit 0 |\n' > "$f12_ledger"
  printf '# サンプル指示書\n\nキーを含まない本文。\n' > "$f12_task"
  run_cross_check_core "$f12_ledger" "$f12_task"
  local got12="fail"
  if [ "$CROSS_TOTAL" -eq 0 ] && [ "${#CROSS_MISSING[@]}" -eq 0 ]; then
    got12="pass"
  fi
  if [ "$got12" = "pass" ]; then
    echo "[PASS] 段階3-主張するキーが無ければ0件（エラーにしない）"
    pass=$((pass + 1))
  else
    echo "[FAIL] 段階3-主張するキーが無ければ0件（エラーにしない）（CROSS_TOTAL=${CROSS_TOTAL} MISSING=${#CROSS_MISSING[@]}）"
    fail=$((fail + 1))
  fi

  # 13. 段階3（照合）: 地の文（表の行でない）にだけキーが現れても裏付けにしない。
  #     表の行が後に続けばそちらで裏付ける（実際に「1-26」の実測でこの順序を踏み、
  #     地の文がgrepの最初の一致になって誤って「裏付けなし」と判定する事故があった）
  local f13_ledger="$tmpdir/case13-ledger.md"
  local f13_task="$tmpdir/case13-task.md"
  printf '第33回で未解決として残した項目（原番号 1-96）は地の文の言及である。\n| 項目 | 項目名 | 反映先資産 | 反映箇所 | 配線した呼び出し箇所 | 検証方法と結果 |\n|---|---|---|---|---|---|\n| x-1 | 何か（原番号 1-96） | path | 箇所 | 呼び出し | self-test 実走: exit 0 |\n' > "$f13_ledger"
  printf '# サンプル指示書\n\n**元の指摘**: 1-96\n' > "$f13_task"
  run_cross_check_core "$f13_ledger" "$f13_task"
  local got13="fail"
  if [ "$CROSS_TOTAL" -eq 1 ] && [ "${#CROSS_MISSING[@]}" -eq 0 ]; then
    got13="pass"
  fi
  if [ "$got13" = "pass" ]; then
    echo "[PASS] 段階3-地の文の言及より表の行を優先する"
    pass=$((pass + 1))
  else
    echo "[FAIL] 段階3-地の文の言及より表の行を優先する（CROSS_TOTAL=${CROSS_TOTAL} MISSING=${#CROSS_MISSING[@]}）"
    fail=$((fail + 1))
  fi

  # 14. 段階3（照合）: 原番号の前に語が挟まる形も拾う
  #     （実測: 台帳に「（原文未取得、原番号 1-76）」のように「（原番号 」の直後でなく
  #     間に語を挟む書き方が1件実在する。開き括弧の直前一致を要求すると誤って
  #     「裏付けなし」と判定される）
  local f14_ledger="$tmpdir/case14-ledger.md"
  local f14_task="$tmpdir/case14-task.md"
  printf '| 項目 | 項目名 | 反映先資産 | 反映箇所 | 配線した呼び出し箇所 | 検証方法と結果 |\n|---|---|---|---|---|---|\n| 記帳漏れ-原文未取得 | 記帳漏れ（原文未取得、原番号 1-96） | path | 箇所 | 呼び出し | self-test 実走: exit 0 |\n' > "$f14_ledger"
  printf '# サンプル指示書\n\n**元の指摘**: 1-96\n' > "$f14_task"
  run_cross_check_core "$f14_ledger" "$f14_task"
  local got14="fail"
  if [ "$CROSS_TOTAL" -eq 1 ] && [ "${#CROSS_MISSING[@]}" -eq 0 ]; then
    got14="pass"
  fi
  if [ "$got14" = "pass" ]; then
    echo "[PASS] 段階3-原番号の前に語が挟まる形も拾う"
    pass=$((pass + 1))
  else
    echo "[FAIL] 段階3-原番号の前に語が挟まる形も拾う（CROSS_TOTAL=${CROSS_TOTAL} MISSING=${#CROSS_MISSING[@]}）"
    fail=$((fail + 1))
  fi

  # 15. 段階3（抽出）: 4行目の欄にカンマ区切りで並べた複数のキーを拾う
  local f15_ledger="$tmpdir/case15-ledger.md"
  local f15_task="$tmpdir/case15-task.md"
  printf '| 項目 | 項目名 | 反映先資産 | 反映箇所 | 配線した呼び出し箇所 | 検証方法と結果 |\n|---|---|---|---|---|---|\n| x-1 | 何か（原番号 1-95） | path | 箇所 | 呼び出し | self-test 実走: exit 0 |\n| x-2 | 何か（原番号 1-94） | path | 箇所 | 呼び出し | self-test 実走: exit 0 |\n' > "$f15_ledger"
  printf '# サンプル指示書\n\n**元の指摘**: 1-95, 1-94\n' > "$f15_task"
  run_cross_check_core "$f15_ledger" "$f15_task"
  local got15="fail"
  if [ "$CROSS_TOTAL" -eq 2 ] && [ "${#CROSS_MISSING[@]}" -eq 0 ]; then
    got15="pass"
  fi
  if [ "$got15" = "pass" ]; then
    echo "[PASS] 段階3-カンマ区切りで複数のキーを拾う"
    pass=$((pass + 1))
  else
    echo "[FAIL] 段階3-カンマ区切りで複数のキーを拾う（CROSS_TOTAL=${CROSS_TOTAL} MISSING=${#CROSS_MISSING[@]}）"
    fail=$((fail + 1))
  fi

  # 16. 段階3（抽出）: 本文の地の文（見出し「### 1-NN.」・工程番号「Stage 1-3」相当の
  #     記述）は、4行目の欄が「なし」なら主張として拾わない。本文走査をやめた
  #     ことの決定的な確認（旧実装ならCROSS_TOTAL=1になっていた場面で0件になる
  #     ことを見る。実測で `\b1-[0-9]+\b` の緩い抽出が64件中9件、工程番号などを
  #     誤って拾っていたことが分かった事故の再発防止）
  local f16_ledger="$tmpdir/case16-ledger.md"
  local f16_task="$tmpdir/case16-task.md"
  printf '| 項目 | 項目名 | 反映先資産 | 反映箇所 | 配線した呼び出し箇所 | 検証方法と結果 |\n|---|---|---|---|---|---|\n| x-1 | 何か（原番号 1-3） | path | 箇所 | 呼び出し | self-test 実走: exit 0 |\n' > "$f16_ledger"
  printf '# サンプル指示書\n\n**元の指摘**: なし\n\n### 1-3. 見出しの形（本文走査なら拾ってしまう）\n\n| 前提 | Stage 1-3の成果物＋既存検証スキル群 |\n' > "$f16_task"
  run_cross_check_core "$f16_ledger" "$f16_task"
  local got16="fail"
  if [ "$CROSS_TOTAL" -eq 0 ] && [ "${#CROSS_MISSING[@]}" -eq 0 ]; then
    got16="pass"
  fi
  if [ "$got16" = "pass" ]; then
    echo "[PASS] 段階3-工程番号をキーとして拾わない"
    pass=$((pass + 1))
  else
    echo "[FAIL] 段階3-工程番号をキーとして拾わない（CROSS_TOTAL=${CROSS_TOTAL} MISSING=${#CROSS_MISSING[@]}）"
    fail=$((fail + 1))
  fi

  # 17. --only で対象を1件に絞る（指定した側のコマンドだけが実行され、指定しなかった側は実行されない）
  local only_dir="$tmpdir/only-scope"
  mkdir -p "$only_dir"
  local marker_a="$tmpdir/only-marker-a" marker_b="$tmpdir/only-marker-b"
  rm -f "$marker_a" "$marker_b"
  local only_a="$only_dir/taskA.md" only_b="$only_dir/taskB.md"
  mk_doc "$(printf '| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |\n|---|---|---|---|---|\n| 1. 何か | touch %s | 未着手 | — | — |' "$marker_a")" > "$only_a"
  mk_doc "$(printf '| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |\n|---|---|---|---|---|\n| 1. 何か | touch %s | 未着手 | — | — |' "$marker_b")" > "$only_b"

  # judge_publish は公開状態の repo 横断チェックであり --only の対象絞り込みとは無関係だが、
  # run_normal_mode は毎回これを呼ぶ。実物の agent-toolkit を突合する重い処理のため、
  # ここでは判定だけをスタブに差し替えて run_normal_mode 本体（対象選定・実行ループ）を
  # 実際に通す（テストのたびに公開判定の重い処理を繰り返さないため）。
  local judge_publish_orig
  judge_publish_orig="$(declare -f judge_publish)"
  judge_publish() { PUBLISH_OK=1; PUBLISH_MSG="stub"; }

  local saved_tasks_dir="$TASKS_DIR" saved_only_file="$ONLY_FILE" saved_write="$WRITE"
  TASKS_DIR="$only_dir"
  ONLY_FILE="$only_a"
  WRITE=0
  run_normal_mode >/dev/null 2>&1
  TASKS_DIR="$saved_tasks_dir"
  ONLY_FILE="$saved_only_file"
  WRITE="$saved_write"
  eval "$judge_publish_orig"

  local marker_a_state="なし" marker_b_state="なし"
  [ -f "$marker_a" ] && marker_a_state="あり"
  [ -f "$marker_b" ] && marker_b_state="あり"
  local got17="fail"
  if [ -f "$marker_a" ] && [ ! -f "$marker_b" ]; then
    got17="pass"
  fi
  if [ "$got17" = "pass" ]; then
    echo "[PASS] --onlyで対象を1件に絞る"
    pass=$((pass + 1))
  else
    echo "[FAIL] --onlyで対象を1件に絞る（marker_a=${marker_a_state} marker_b=${marker_b_state}）"
    fail=$((fail + 1))
  fi

  # 18. --only に実在しないパスを渡すと解決に失敗する（本体ではこの返り値1がそのまま exit 1 に直結する）
  resolve_only_path "$tmpdir/does-not-exist.md"
  local rc18=$?
  local got18="fail"
  if [ "$rc18" -eq 1 ] && [ -z "$ONLY_FILE" ]; then
    got18="pass"
  fi
  if [ "$got18" = "pass" ]; then
    echo "[PASS] --onlyに実在しないパスを渡すと終了コード1"
    pass=$((pass + 1))
  else
    echo "[FAIL] --onlyに実在しないパスを渡すと終了コード1（rc=${rc18} ONLY_FILE=${ONLY_FILE}）"
    fail=$((fail + 1))
  fi

  # 19. --only と --write を併用すると対象1件の状態欄だけが書き換わる
  local write_dir="$tmpdir/only-write-scope"
  mkdir -p "$write_dir"
  local write_a="$write_dir/taskA.md" write_b="$write_dir/taskB.md"
  mk_doc "$(printf '| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |\n|---|---|---|---|---|\n| 1. 何か | true | 未着手 | — | — |')" > "$write_a"
  mk_doc "$(printf '| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |\n|---|---|---|---|---|\n| 1. 何か | true | 未着手 | — | — |')" > "$write_b"

  judge_publish_orig="$(declare -f judge_publish)"
  judge_publish() { PUBLISH_OK=1; PUBLISH_MSG="stub"; }

  saved_tasks_dir="$TASKS_DIR"
  saved_only_file="$ONLY_FILE"
  saved_write="$WRITE"
  TASKS_DIR="$write_dir"
  ONLY_FILE="$write_a"
  WRITE=1
  run_normal_mode >/dev/null 2>&1
  TASKS_DIR="$saved_tasks_dir"
  ONLY_FILE="$saved_only_file"
  WRITE="$saved_write"
  eval "$judge_publish_orig"

  local got19="fail"
  if grep -qE '\|[[:space:]]*1\. 何か[[:space:]]*\|[[:space:]]*true[[:space:]]*\|[[:space:]]*完了[[:space:]]*\|' "$write_a" \
     && grep -qE '\|[[:space:]]*1\. 何か[[:space:]]*\|[[:space:]]*true[[:space:]]*\|[[:space:]]*未着手[[:space:]]*\|' "$write_b"; then
    got19="pass"
  fi
  if [ "$got19" = "pass" ]; then
    echo "[PASS] --onlyと--write併用で対象1件の状態欄だけが書き換わる"
    pass=$((pass + 1))
  else
    echo "[FAIL] --onlyと--write併用で対象1件の状態欄だけが書き換わる"
    echo "       taskA:"
    sed 's/^/       /' "$write_a"
    echo "       taskB:"
    sed 's/^/       /' "$write_b"
    fail=$((fail + 1))
  fi

  # 20. 確かめる手段が終了コード2（判定不能）を返す -> 満たさない（未確認・移せない）
  #     不合格（終了コード1）とは区別する。実行環境の制約で検査を実行できなかった場合が
  #     該当する。定義: .claude/rules/always/verification/indeterminate-result/rule.md
  local f20="$tmpdir/case20.md"
  mk_doc "$(printf '| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |\n|---|---|---|---|---|\n| 1. 何か | exit 2 | 未着手 | — | — |')" > "$f20"
  run_meas_case "確かめる手段が判定不能（終了コード2）" "$f20" 5 0 "判定不能"

  # 21. --write は終了コード2（判定不能）の行を「未着手」へ降格させない。
  #     「完了」だった行は「未確認」にし、「対象外」「判断待ち」は元の値のまま残す。
  #     実行環境の制約で検査を実行できなかっただけで、正しい記録を消してはならない。
  local f21="$tmpdir/case21.md"
  mk_doc "$(printf '| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |\n|---|---|---|---|---|\n| 1. 何か | exit 2 | 完了 | — | — |\n| 2. 何か | exit 2 | 対象外 | — | — |\n| 3. 何か | exit 2 | 判断待ち | — | — |')" > "$f21"
  write_measurement_states "$f21" 5
  local got21="fail"
  if grep -qE '\|[[:space:]]*1\. 何か[[:space:]]*\|[[:space:]]*exit 2[[:space:]]*\|[[:space:]]*未確認[[:space:]]*\|' "$f21" \
     && grep -qE '\|[[:space:]]*2\. 何か[[:space:]]*\|[[:space:]]*exit 2[[:space:]]*\|[[:space:]]*対象外[[:space:]]*\|' "$f21" \
     && grep -qE '\|[[:space:]]*3\. 何か[[:space:]]*\|[[:space:]]*exit 2[[:space:]]*\|[[:space:]]*判断待ち[[:space:]]*\|' "$f21"; then
    got21="pass"
  fi
  if [ "$got21" = "pass" ]; then
    echo "[PASS] --writeが判定不能の行を未着手へ降格させない"
    pass=$((pass + 1))
  else
    echo "[FAIL] --writeが判定不能の行を未着手へ降格させない"
    echo "       中身:"
    sed 's/^/       /' "$f21"
    fail=$((fail + 1))
  fi

  # 22. UTF-8ロケールでも全角文字直前のTOOLKIT_DIRを正しく展開する。
  local saved_toolkit_dir="$TOOLKIT_DIR" saved_lc_all="${LC_ALL-}" lc_all_was_set=0
  if [ "${LC_ALL+x}" = "x" ]; then
    lc_all_was_set=1
  fi
  TOOLKIT_DIR="$tmpdir/missing-toolkit"
  LC_ALL=zh_CN.UTF-8
  PUBLISH_MSG=""
  judge_publish
  if [ "$lc_all_was_set" -eq 1 ]; then
    LC_ALL="$saved_lc_all"
  else
    unset LC_ALL
  fi
  TOOLKIT_DIR="$saved_toolkit_dir"
  if [ "$PUBLISH_MSG" = "未反映（agent-toolkitが見当たらない: ${tmpdir}/missing-toolkit）" ]; then
    echo "[PASS] 公開判定の変数境界を維持する"
    pass=$((pass + 1))
  else
    echo "[FAIL] 公開判定の変数境界が壊れている"
    fail=$((fail + 1))
  fi

  echo "合格 ${pass} 件 / 不合格 ${fail} 件"

  if [ "$fail" -gt 0 ]; then
    return 1
  fi
  return 0
}

# ---------- 引数の解釈 ----------
APPLY=0
WRITE=0
SELF_TEST=0
CROSS_CHECK=0
TIMEOUT_SEC=120
ONLY_PATH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --write) WRITE=1; shift ;;
    --self-test) SELF_TEST=1; shift ;;
    --cross-check) CROSS_CHECK=1; shift ;;
    --only)
      if [ $# -ge 2 ]; then ONLY_PATH="$2"; shift 2; else shift 1; fi
      ;;
    --timeout)
      if [ $# -ge 2 ]; then TIMEOUT_SEC="$2"; shift 2; else shift 1; fi
      ;;
    *) shift ;;
  esac
done

if [ "$SELF_TEST" -eq 1 ]; then
  run_self_test
  exit $?
fi

if [ "$CROSS_CHECK" -eq 1 ]; then
  run_cross_check
  exit 0
fi

if [ -n "$ONLY_PATH" ]; then
  if ! resolve_only_path "$ONLY_PATH"; then
    exit 1
  fi
fi

run_normal_mode
