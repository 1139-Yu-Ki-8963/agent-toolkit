---
key: git-hooks-activation
title: 設計先行検査の有効化の決まり
parent: agent-operations
summary: 設計先行の検査本体が動くための core.hooksPath を、セッション開始のたびに設定し直す決まり。
scope: always
paths: []
enforcement: advisory
checkable: true
checker: ensure-githooks.sh
uncheckableReason: null
formatter: none
status: approved
origin: manual
workUnit: process
---
# 設計先行検査の有効化の決まり

## 概要

`docs/rules/agent-operations/work-records/rule.md`が定める設計先行の検査は、
第4版で本体を変えた。本体はgit自身の参照更新フック
（`reference-transaction`）である。

第5版（2026-09-06）で導入方式を変えた。第4版は`core.hooksPath`を作業ツリーの
`githooks`フォルダへ直接向けていた。作業ツリーのフックファイルをrmで消す、
または内容を`exit 0`に書き換えるだけで無効化できる穴があった。第5版は
mainのコミット済みの版だけを導入元にする。`ensure-githooks.sh`は
`git show main:<path>`でフックの実体を取り出す。実体は
`reference-transaction`と`shared/design-first-lib.sh`の2つである。
取り出した実体は`$(git rev-parse --git-common-dir)`配下の
`design-first-hooks/`へ書き出す。`core.hooksPath`はこの絶対パスへ
設定する。作業ツリー側の変更はmainへ取り込まれ次回`ensure-githooks.sh`が
走るまで導入済みの実体に影響しない。

## 規則

| 規則 | 内容 | 検査 |
|---|---|---|
| セッション開始のたびにmainの版から導入し直す | `ensure-githooks.sh`をSessionStartのたびに実行する。mainの`reference-transaction`・`design-first-lib.sh`を取り出す。`$(git rev-parse --git-common-dir)/design-first-hooks/`へ書き出す。`core.hooksPath`をその絶対パスへ設定する。既存の`.git/hooks`の実行可能フックは共存ラッパーで引き継ぐ。導入時に既定の`PATH`でgitの絶対パスを解決し、導入先の`git-path`に記録する。解決したgitが`$TMPDIR`・`/tmp`・作業ツリーの配下なら導入を止める | 静的解析: SessionStart契機で`ensure-githooks.sh`が呼ばれるかを見る。`core.hooksPath`が導入先の絶対パスと一致するかも見る。`git-path`が記録されているかも見る |
| 有効になっていなければ書き込みを止める | `check-work-records.sh`の開始の検査（PreToolUse）は4条件を見る。(a)`core.hooksPath`が導入先の絶対パスと一致すること。(b)導入済みの実体が実在し実行権限を持つこと。(c)導入済みの実体のsha256がmainの版と一致すること。(d)`git-path`が実在し、その指す実体のsha256が導入時の記録（`git-path.sha256`）と一致すること。1つでも欠ければ書き込みを拒否する。作業ツリーの内容は見ない | 静的解析: `check-work-records.sh`の`verify_installed_hooks_cwr`が4条件を検査しているかを走査する |
| 導入時に alias が無いことを確かめる | `ensure-githooks.sh`は`git config --get-regexp '^alias\.'`が空でなければ導入を止めて警告する。`git config alias.*`はgitの副命令を任意に間接実行できる経路であり、放置すると設計先行の検査を迂回する足がかりになる | 静的解析: 同コマンドの出力の有無 |
| main がシンボリック参照なら導入を止める | シンボリック参照は`git symbolic-ref refs/heads/main <他の参照>`で作る別名である。`refs/heads/main`がそれになっていれば、`ensure-githooks.sh`は導入を止める。`check-work-records.sh`の開始・応答終了の検査でも同じ判定を見る。 | 静的解析: `git symbolic-ref refs/heads/main refs/heads/<他の枝>`を実行したリポジトリで導入が止まるかを見る。 |

## このプロジェクトの規則

| 規則 | 内容 | 検査 |
|---|---|---|
| 観測なし | この規約はこのリポジトリ自身の検査有効化を定めるもので、対象リポジトリの観測から起こす規則は無い | 観測なし |

## 違反時の手順

書き込みが止められた場合、`ensure-githooks.sh <リポジトリのルート>`を実行してから再試行する。

`git --version`が2.28未満の場合は導入されない。gitのバージョンを上げてから再実行する。

恒常的に不一致が起きる環境では、`ensure-githooks.sh`のSessionStart登録が外れていないかを確認する。

## 既知の限界

- `git -c core.hooksPath=<path>`・`GIT_CONFIG_COUNT`等の環境変数で、gitのプロセス単位で`core.hooksPath`を上書きできる。この経路の参照更新はgit自体のフックを経由しないため、フック側では止められない。正当な用途が無いため、Claude側の`check_merge`（`check_hook_bypass_guard`）がこの2パターンを含むコマンドをexit 2で拒否する
- `.git/` 配下（導入先の実体・参照・設定）への書き込みは、Claude 側の `check-work-records.sh` が字面で拒否する。残る限界は、字面に内部の語が現れない形（変数で組んだパス・base64）と、Claude のツールを経ない人手の操作である
- git 2.28未満では`reference-transaction`フックの仕組み自体が無い。`ensure-githooks.sh`はバージョンを検査し、未満なら導入をスキップする。導入されないため開始の検査はfail-closedになる
- `.git/hooks`（common dir直下の既定のフックディレクトリ）に既存の実行可能フックがあれば、導入フォルダへ同名の呼び出しラッパーを置いて引き継ぐ。ラッパーは元のフックへ`exec`するだけであり、内容は複製しない。既存フックが導入後に追加された場合は次回の`ensure-githooks.sh`実行まで引き継がれない
- worktreeごとに`.git`の実体（common dir）は共有される。`core.hooksPath`はこのcommon dir単位の設定であり、worktreeごとに別の値を持てない。第5版はこれを逆手に取り、mainの版をcommon dir配下へ導入することで全worktreeに一括して効かせる
- main に導入元が無い初回導入中は、`ensure-githooks.sh` は導入をスキップし、開始の検査は警告して通す。導入元が main に入った後は、導入元を消す更新を git フックが拒否するため、この状態へは戻らない
- `GIT_EXEC_PATH=<偽のgitを置いたdir> git merge --no-ff feature`によるgitの実体差し替えがあった。第16版でフック・共有ライブラリが`GIT_EXEC_PATH`を捨てて`PATH`を既定値へ組み直した。導入時に記録した絶対パス（`git-path`）でgitを呼ぶ構造に改め、この経路を閉じた。単純な`PATH=偽:$PATH`前置は、git-core自身が実行時に自らのexec pathをPATHの先頭へ再度差し込む。そのため元々この経路では実害が無い（reference-transaction.test.shケース27で確認）
- フックの観測点自体を経ない参照の差し替え（`git symbolic-ref refs/heads/main <他の参照>`）がある。gitの参照更新フック（`reference-transaction`）は、prepared・committedのどちらの段階でもこの操作を発火させない（実測済み）。導入時（`ensure-githooks.sh`）と開始・応答終了の検査（`check-work-records.sh`）の両方で拒否することで補う

## 設計判断

### ensure-githooks.sh / ensure-githooks.test.sh

**必要性**: `core.hooksPath`はバージョン管理できないリポジトリ固有configである。リポジトリをcloneし直した・別worktreeを作った・他ツールが値を書き換えた等の理由で失われうる。失われると設計先行の検査本体（reference-transaction）が無効化される。その事実に気づく手段が無ければ「検査が効いていると思って実は効いていない」状態になる。セッション開始という確実な契機で毎回設定し直す処理が要る。既存値との一致を確かめる自己テストも要る。Bashツールの直叩きでは契機に接続できない。`ensure-githooks.test.sh`は本体の`--self-test`を呼ぶだけの薄い入口である。判定の中身を二重に持たない（`check-work-records.test.sh`と同じ設計）。

第5版で、導入元を作業ツリーからmainのコミット済みの版へ変えた。第4版のcode-reviewerが、作業ツリーのフックファイルをrmで消す・内容を`exit 0`に書き換える・linked worktreeに実体が無く発火しない、の3件を指摘した。いずれも「作業ツリーの内容をそのまま信用する」構造が原因だった。`git show main:<path>`でmainのオブジェクトストアから直接取り出す方式に変えた。取り出した実体は`$(git rev-parse --git-common-dir)`配下（全worktreeが共有する実体）へ書き出す。この方式なら、作業ツリー側の改変は導入済みの実体に一切影響しない。あわせてgitのバージョン検査と、既存`.git/hooks`フックの共存ラッパーを追加した。

14回目の反証で`GIT_EXEC_PATH`による偽gitの差し替えで本体が破られた。gitはフック起動時にGIT_EXEC_PATHの指す先をPATHの先頭へ足す。そのためフック・共有ライブラリが呼ぶ裸の`git`が偽の実体を向いてしまう。第16版で、導入時にgitの絶対パスを固定した（既定のPATHで一度だけ解決し`git-path`へ記録する）。フック・共有ライブラリは`GIT_EXEC_PATH`を捨てて`PATH`を既定値へ組み直した。そのうえで、この固定した絶対パスでgitを呼ぶ構造に改めた。環境変数の判定一覧（`check-work-records.sh`の`command_disables_hooks_path`）も広げた。個別列挙（`GIT_DIR`・`GIT_COMMON_DIR`等）から`GIT_`接頭辞全体へ広げた。あわせて`--config-env`を拒否対象へ足した。`--config`と同じ設定上書き経路だが接頭辞が異なるため個別に見逃していた。

2026-09-06の18回目の反証で、`git symbolic-ref refs/heads/main refs/heads/feature`によりmainの指す先が差し替えられる穴が見つかった。この操作をしても、gitの参照更新フック（`reference-transaction`）はprepared・committedのどちらの段階でも発火しない（git 2.39.5で実測）。本体の観測点そのものを経ない差し替えであるため、フック側の改修では防げない。導入時（`install_from_main`。`_egt_main_is_symbolic`新設）に`refs/heads/main`がシンボリック参照なら導入を止める形へ改めた。`ensure-githooks.test.sh`にケース17（本ファイル末尾のself_test関数内）を足した。

**代替案を採用しなかった理由**:
- Bashツール直叩き: SessionStartという契機にBashツール単体では接続できず、毎回の手動実行に頼ると忘れる
- `.git/config`をリポジトリのバージョン管理対象にする: gitの仕様上`core.hooksPath`を含む`.git/config`はバージョン管理できない（`.git`配下は追跡対象外）
- 作業ツリーの`githooks`フォルダを直接`core.hooksPath`へ向け続ける（第4版の方式）: rmや書き換えで無効化できる。linked worktreeには実体が無いことがある
- 既存Makefileターゲット拡張・package.json scripts追加: このリポジトリはどちらも持たず、新規導入は本チェック専用の依存を増やすだけになる

**保守責任者**: 人手（ユーザー）。導入元のパス（`HOOK_REL_MAIN`・`LIB_REL_MAIN`）を変える場合がある。導入先のサブフォルダ名（`HOOK_INSTALL_SUBDIR`）を変える場合もある。gitの絶対パス解決に使う既定の`PATH`（`GIT_RESOLVE_PATH_DEFAULT`）を変える場合もある。いずれも、本ファイルと`check-work-records.sh`の対応する定数を同時に更新する。

**廃棄条件**: 設計先行の検査本体をgitの参照更新フック以外の仕組みへ移した時、またはClaude Codeが`core.hooksPath`相当の設定を自動で維持する機能を持つようになった時。

## 関連

- `docs/rules/agent-operations/work-records/rule.md` — 設計先行の検査。本体はreference-transaction。本規約はその有効化を担当し対象が異なる
- `docs/rules/agent-operations/work-records/githooks/reference-transaction` — 検査本体
