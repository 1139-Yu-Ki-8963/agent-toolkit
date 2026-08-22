# check-instruction-formatのmktempをサンドボックス下で成功させる指示書

**状態**: 着手できる
**優先度**: 中
**前提**: なし
**元の指摘**: なし

## この指示書は何か

`.claude/rules/always/tasks/instruction-format/check-instruction-format.sh`が使う2箇所の引数なし`mktemp`（`ensure_stripped_tmp`関数内の`mktemp`と`run_self_test`関数内の`mktemp -d`）を、明示パス指定（`mktemp -d "${TMPDIR:-/tmp}/<名前>.XXXXXX"`の形）へ書き換える。これにより、サンドボックス環境下でも一時ファイルの作成そのものが成功するようにし、検査が「判定不能」で止まらず実際に判定できる状態にする。

## なぜ必要か

`docs/tasks/片付き判定の実測が上限を超えると静的確認へ逃げてしまう問題を片付ける指示書.md`の判定3の調査で、`docs/scripts/judge-task-done.sh --only`で`docs/tasks/done/`配下のファイルを手動判定すると「判定不能」を返す事例を再現・特定した。原因は次のとおりである。

1. `check-instruction-format.sh`の`ensure_stripped_tmp`（60行目付近）と`run_self_test`（922行目付近）は、いずれも引数なしの`mktemp`／`mktemp -d`を使う
2. この環境のサンドボックスでは、引数なし`mktemp`はmacOSの既定挙動により`$TMPDIR`環境変数を無視し`/var/folders/.../T/`配下へ書き込もうとする。このパスはサンドボックスの書き込み許可対象に含まれないため`Operation not permitted`で失敗する（実測: `mktemp -d`単体実行で`mkdtemp failed on /var/folders/.../T/tmp.xxx: Operation not permitted`）
3. `check-instruction-format.sh`はこの失敗を検出し、`.claude/rules/always/verification/indeterminate-result/rule.md`の規約どおり`[UNKNOWN]`・終了コード2で正しく終了する（これは既存の別指示書`docs/tasks/done/mktemp失敗を判定不能として区別する指示書.md`が意図して実装させた挙動であり、バグではない）
4. `docs/scripts/judge-task-done.sh`の`judge_measurement`はこの終了コード2を「確かめる手段が判定不能（終了コード2）」として正しく区別し、当該指示書を「移せない」に分類する

**この「判定不能」は`done/`配下という置き場に固有の問題ではない。** 実測で確認したとおり、`docs/tasks/`直下にある通常の指示書（例: `片付き判定に実測の段階を足す指示書.md`）で「確かめる手段」に`check-instruction-format.sh`（`--self-test`の有無を問わず）を使う行があると、サンドボックス下では同じ「判定不能」になる。逆に`done/`配下のファイルでも、確かめる手段が`check-instruction-format.sh`に触れなければ（例: `検証記録の置き場-ゲートとの衝突を片付ける指示書.md`）サンドボックス下でも正しく判定でき、`dangerouslyDisableSandbox: true`を付けて同じファイルを再実行すると正常に判定が進む（未着手・対応中が残る等、mktempと無関係な理由で止まる）ことも確認済みである。

つまり、大元の指示書本文が記した「サンドボックスの有無を問わず「判定不能」を返し」という記述は実測と一致しない。判定不能を左右するのはサンドボックスの有無そのものであり、`done/`という置き場ではない。この事実誤認は元の指示書側の記録として残す（本指示書の対応外）。

引数なし`mktemp`を明示パスへ直す修正は、既存の`docs/tasks/done/mktemp失敗を判定不能として区別する指示書.md`が「触らない範囲」で明示的に除外した対象（「`mktemp`自体の呼び出し方（`-d`オプション・生成先ディレクトリ等）は変えない」）である。同指示書はそのスコープの中で「判定不能として正しく区別できる」ところまでを完了条件とし、「サンドボックス下でも成功させる」は意図的に対象外にした。その制約を勝手に上書きせず、新しい指示書として起票し、スコープを再定義したうえで対応する。

## やること

1. `.claude/rules/always/tasks/instruction-format/check-instruction-format.sh`の`ensure_stripped_tmp`関数内、`STRIPPED_TMP="$(mktemp 2>/dev/null)"`を`STRIPPED_TMP="$(mktemp "${TMPDIR:-/tmp}/check-instruction-format-stripped.XXXXXX" 2>/dev/null)"`へ書き換える
2. 同ファイルの`run_self_test`関数内、`tmpdir="$(mktemp -d 2>/dev/null)"`を`tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/check-instruction-format-selftest.XXXXXX" 2>/dev/null)"`へ書き換える
3. サンドボックス下で`bash .claude/rules/always/tasks/instruction-format/check-instruction-format.sh`（引数なし）と`--self-test`をそれぞれ実行し、いずれも終了コード2・`[UNKNOWN]`にならず正常に判定結果（0または1）を返すことを確認する
4. サンドボックスを無効化した実行（`dangerouslyDisableSandbox: true`）でも同じ2コマンドを実行し、修正前と同じ判定結果（合格件数・不合格件数）になることを確認する。差異があれば修正が既存の判定内容を変えてしまっている可能性があるため見直す
5. `docs/scripts/judge-task-done.sh --only "docs/tasks/done/指摘の追跡を機械で読める形にする指示書.md"`をサンドボックス下で再実行し、「判定不能」ではなく実測に基づく判定（「移せる」または具体的な不合格理由）を返すことを確認する

## 完了の判定

1. サンドボックス下で`bash .claude/rules/always/tasks/instruction-format/check-instruction-format.sh`を実行した終了コードが2でない
2. サンドボックス下で`bash .claude/rules/always/tasks/instruction-format/check-instruction-format.sh --self-test`を実行した終了コードが2でない
3. サンドボックス下でのこの2コマンドの出力に`[UNKNOWN]`という文字列が含まれない
4. サンドボックス下で`bash docs/scripts/judge-task-done.sh --only "docs/tasks/done/指摘の追跡を機械で読める形にする指示書.md"`を実行した出力に「判定不能」という文字列が含まれない

## 触らない範囲

- `docs/scripts/judge-task-done.sh`の判定ロジック自体（`judge_measurement`等）。本指示書は`check-instruction-format.sh`側のmktemp呼び出しの直し方のみを対象とする
- `check-instruction-format.sh`の検査ロジックそのもの（各`validate_*`関数・状態語の妥当性判定等）。mktempの呼び出しパス指定のみを変更する
- `mktemp`を引数なしで使う他の119件のスクリプト（`docs/tasks/done/mktemp失敗を判定不能として区別する指示書.md`が実測した120件のうちの残り）。本指示書は`check-instruction-format.sh`1件・2箇所に限定する

## 決めていないこと

| 何を決めるか | 既定（迷ったらこれを選ぶ） | 覆すときの条件 |
|---|---|---|
| 一時ファイル・一時ディレクトリの命名 | `check-instruction-format-stripped.XXXXXX`（ファイル）・`check-instruction-format-selftest.XXXXXX`（ディレクトリ）とし、判定器自身の実装上の注意（`docs/scripts/judge-task-done.sh`冒頭コメント）と同じ命名慣行（用途がわかる接頭辞+`.XXXXXX`）に揃える | 同名の一時ファイルが別プロセスと衝突する実測が出た場合、接頭辞をより一意にする |
| 残り119件のスクリプトへの横展開 | 本指示書では行わない。`check-instruction-format.sh`1件で修正パターンを確立し、他への展開要否は別途判断する | 本指示書の完了後、同種の「判定不能」による支障が他スクリプトでも実際に発生した場合、横展開の指示書を別途起票する |

## 他の指示書との関係

| 指示書 | 関係 |
|---|---|
| `docs/tasks/片付き判定の実測が上限を超えると静的確認へ逃げてしまう問題を片付ける指示書.md` | 判定3の調査で本件の原因を特定し、本指示書として切り出した |
| `docs/tasks/done/mktemp失敗を判定不能として区別する指示書.md` | 「判定不能として正しく区別する」までを完了条件とし「触らない範囲」でmktempの呼び出し方自体の変更を明示的に除外した。本指示書はそのスコープを再定義し、サンドボックス下での成功までを対象にする後続の指示書である |

## この指示書の位置づけ

`check-instruction-format.sh`という1ファイル・2箇所のmktemp呼び出しに対象を絞った、独立して着手・完了できる小さな修正である。`docs/scripts/judge-task-done.sh`の判定ロジックには触れないため、同スクリプトの既存22件の自己テストとは独立に進められる。

## 対応の記録

### 判定の充足状況

| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |
|---|---|---|---|---|
| 1. check-instruction-format.shの終了コードが2でない | `bash .claude/rules/always/tasks/instruction-format/check-instruction-format.sh; [ $? -ne 2 ]` | 完了 | — | — |
| 2. check-instruction-format.sh --self-testの終了コードが2でない | `bash .claude/rules/always/tasks/instruction-format/check-instruction-format.sh --self-test; [ $? -ne 2 ]` | 完了 | — | — |
| 3. 出力にUNKNOWNが含まれない | `! (bash .claude/rules/always/tasks/instruction-format/check-instruction-format.sh 2>&1; bash .claude/rules/always/tasks/instruction-format/check-instruction-format.sh --self-test 2>&1) \| grep -q '\[UNKNOWN\]'` | 完了 | — | — |
| 4. judge-task-done.shのdone/判定不能が解消 | `! bash docs/scripts/judge-task-done.sh --only "docs/tasks/done/指摘の追跡を機械で読める形にする指示書.md" 2>&1 \| grep -q '判定不能'` | 完了 | — | — |

### 判断の記録

| 何を決めたか | 選んだもの | 選んだ理由 | 覆すと何が変わるか |
|---|---|---|---|
| 起票するか、この場で直すか | 起票する | 元の作業指示（`片付き判定の実測が上限を超えると静的確認へ逃げてしまう問題を片付ける指示書.md`の調査）が「触らない範囲」で`judge-task-done.sh`の判定ロジックへの直接修正を禁じていた。加えて修正対象自体が既存の別指示書（`mktemp失敗を判定不能として区別する指示書.md`）が明示的にスコープ外とした「mktempの呼び出し方自体の変更」に当たるため、そのスコープを勝手に上書きせず新しい指示書として再定義した | 覆すと、既存の完了済み指示書の「触らない範囲」を無断で踏み越えたことになり、レビュー時にスコープ外の変更として差し戻される可能性がある |
