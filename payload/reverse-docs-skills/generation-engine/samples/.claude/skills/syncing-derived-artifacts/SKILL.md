---
name: syncing-derived-artifacts
description: |
  docs/rules/ の定義から各AIツール向けの設定を生成し、手作業の混入を検知して復旧する。
  TRIGGER when: docs/rules/ を編集した後、「派生設定を更新して」「規約のずれを確認して」と言われた時。
  SKIP: docs/rules/ 自体の編集（→importing-rule-proposals または人手での編集）。
invocation: syncing-derived-artifacts
type: transform
allowed-tools: [Bash, Read, Write]
---

<!-- 生成物: delivery-payload/templates/delivered-skills/syncing-derived-artifacts/SKILL.md から複製。直接編集しないこと -->

# 派生設定同期スキル

`docs/rules/` の定義から、`.claude/rules/`・`.cursor/rules/*.mdc`・`AGENTS.md`・3ツールのフック登録を生成する。定義は `docs/rules/` だけであり、これらの生成物を直接編集してはならない。本スキルは生成に加えて、生成物が手作業で編集されていないかの検知と、検知した際の復旧も担う。

## 引数

| 引数 | 必須 | 内容 |
|---|---|---|
| `mode` | 必須 | `status` / `apply` / `restore` のいずれか。既定値を持たない |
| `rules_root` | 任意 | 既定は `docs/rules` |
| `restore_ref` | `restore` のときのみ任意 | 戻す先のgit参照（コミットハッシュ・タグ・ブランチ名等）。省略時は `HEAD` を使う |

`mode` に既定値を置かない理由は、誤りの方向が両側にあるためである。既定を `apply` にすると、事故で書き込みが起きる。既定を `status` にすると、`apply` のつもりで呼んだのに何も書き込まれず、しかもそれに気付けない。どちらの誤りも防ぐため、呼び出し側に明示させる。

## 生成に使う実行資産

`docs/rules/agent-operations/ai-config-asset-management/` 配下に配布されるスクリプトを呼ぶ。スクリプトの実体はこの1か所にしか置かない。

- `docs/rules/agent-operations/ai-config-asset-management/validate-rule-definitions.sh`：定義の整合検査。`build-derived-rules.sh` の内部からも自動で呼ばれる
- `docs/rules/agent-operations/ai-config-asset-management/build-derived-rules.sh <rules_root> <出力先リポジトリルート> [--apply]`：生成本体。**`--dry-run` という引数は存在しない**。`--apply` を付けなければ生成予定の一覧を表示するだけで書き込みが起きない。この省略状態が既定のドライラン扱いになる
- `docs/rules/agent-operations/ai-config-asset-management/check-rule-drift.sh <rules_root> <出力先リポジトリルート>`：手作業編集の検知。サブコマンドは持たない。定義から一時ディレクトリへ再生成し、丸ごと生成される2種類（`.claude/rules/**/rule.md`・`.cursor/rules/*.mdc`）だけを実リポジトリの現物と突き合わせる。台帳は持たず、毎回その場で再生成して比べる

`build-derived-rules.sh` は実行の最初に `validate-rule-definitions.sh` を呼び、不合格なら何も生成せず終了する。`status: draft` の規約は生成対象から除外され、除外件数を `非承認(draft)除外: N件` として出力する。この除外は `build-derived-rules.sh` 自身が行うため、本スキル側で重ねて絞り込む必要はない。

## モード別の動作

以下の6つをまとめて「派生ファイル一式」と呼ぶ。

- `.claude/rules/`
- `.cursor/rules/`
- `AGENTS.md`
- `.claude/settings.json`
- `.cursor/hooks.json`
- `.codex/config.toml`

`check-rule-drift.sh` が突合の対象とするのは、派生ファイル一式のうち丸ごと生成される2種類だけである。対象は `.claude/rules/**/rule.md` と `.cursor/rules/*.mdc` である。

### status

書き込みは一切行わない。次の2種類を確認する。どちらも「定義から一時ディレクトリへ再生成し、実リポジトリの現物と突き合わせる」という同じ仕組みを使うが、突き合わせる対象の範囲と報告の粒度が異なる。

**生成予定と現状の差**。`mktemp -d` で作業用の一時ディレクトリを作る。実リポジトリではなくこの一時ディレクトリへ向けて `build-derived-rules.sh <rules_root> <一時ディレクトリ> --apply` を実行する。これにより、現在の定義から生成される内容を、実リポジトリの書き換えなしに得られる。この一時ディレクトリの内容と、実リポジトリの派生ファイル一式（6種類すべて）を突き合わせる。追加予定・変更予定・（定義から消えたための）削除予定を報告する。

**手作業編集の検知**。`docs/rules/agent-operations/ai-config-asset-management/check-rule-drift.sh <rules_root> <実リポジトリルート>` を呼ぶ。このコマンドは自身の内部で同じ「一時ディレクトリへの再生成」を行い、丸ごと生成される2種類（`.claude/rules/**/rule.md`・`.cursor/rules/*.mdc`）だけに絞って `MODIFIED`（内容が違う）・`DELETED`（定義側にはあるが現物にない）・`ADDED`（現物にはあるが定義側にない）を報告する。台帳は持たない。記録と現物のどちらが正かを判断する必要がないよう、毎回その場で `docs/rules/` の定義から再生成して比べる。対象を2種類に絞る理由は、それ以外の派生ファイルがマーカーで挟んだ一部だけを差し替える方式であり、ファイル全体の突合では対象外の箇所への正当な手作業編集まで「ずれ」として誤検知するためである。

### apply

最初に `build-derived-rules.sh --deploy-rule-scripts <実リポジトリルート>` を実行し、`docs/rules/agent-operations/ai-config-asset-management/` へ3本（`validate-rule-definitions.sh`・`build-derived-rules.sh`・`check-rule-drift.sh`）を配備する。既に配備済みでも最新の内容で上書きする。

続けて `status` と同じ確認をし、結果を示す。上書きする前に、いま何が変わるかを必ず把握してから次へ進む。

`build-derived-rules.sh <rules_root> <実リポジトリルート> --apply` を実行する。`status: draft` の規約は生成対象から除外され、その件数は上記のとおりスクリプト自身が報告する。

承認済みの規約が0件でも、`AGENTS.md` の索引ブロックは空の内容で書き換わる。書き込み自体は必ず起きる。

生成前の複製や生成後の台帳更新は行わない。派生物は版管理下にあり、戻す手段は `restore` モード（git ベース）が提供する。

### restore

派生物は版管理下にあるため、戻す手段は git が提供する。バックアップの複製は持たない。

対象は、実リポジトリの派生ファイル一式のうち git 管理下にあるパスに限る。`restore_ref`（既定 `HEAD`）を対象に、各パスを `git checkout <restore_ref> -- <path>` で戻す。

戻す前に `git status`（および必要なら `git diff <restore_ref> -- <path>`）で当該パスの未コミット差分の有無を確認し、戻すと失われる変更があれば一覧にして示してから実行する。無条件に戻してはならない。

戻した後、`docs/rules/agent-operations/ai-config-asset-management/check-rule-drift.sh <rules_root> <実リポジトリルート>` を実行し、戻した内容が現在の定義と一致しているかを確認して結果を示す。一致しない場合は、`restore_ref` の時点の定義と現在の `docs/rules/` の定義がずれている可能性がある旨を添えて報告する（自動修復は行わない）。

## Phase 1: 前提条件の確認

`mode` が3値のいずれかであることを確認する。無指定・不明な値であれば、指定必須である旨を返して停止する。`rules_root`（既定 `docs/rules`）が実在することを確認する。`restore` の場合は対象リポジトリが git 管理下にあることを確認する。git 管理下になければ「戻す手段が無い」旨を報告して停止する。

**完了**: `mode` の値が確定し、`rules_root` の実在を確認済み。`restore` では対象リポジトリが git 管理下にあることも確認済み

## Phase 2: モード別の実行

上記「モード別の動作」の該当節に沿って実行する。

**完了**: `status` は確認結果を報告して書き込みなしに終わっている。`apply` は配備と生成が完了している。`restore` は対象を示したうえで `git checkout` による上書きと事後確認が完了している

## Phase 3: 結果の報告

モードに応じて次を報告する。

- `status`: 追加予定・変更予定・削除予定の件数、`check-rule-drift.sh` が検知した手作業編集（`MODIFIED`/`DELETED`/`ADDED`）の一覧
- `apply`: 生成した各派生物のパス、`非承認(draft)除外` の件数
- `restore`: 戻した `restore_ref`、`git checkout` で上書きしたパスの一覧、戻した後の `check-rule-drift.sh` の判定結果

**完了**: モードに応じて報告し、`apply`/`restore` では書き込んだ具体的なパスを列挙している

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | `mode` の値が確定し、`rules_root`（`restore` は対象リポジトリの git 管理下も）の実在を確認済み |
| Phase 2 | 選んだモードの動作を完遂している |
| Phase 3 | モードに応じた結果報告を行っている |
| **Goal** | 実行者が明示した1つのモードだけが走り、`status` は現状把握に、`apply` は定義からの反映に、`restore` は明示した git 参照への巻き戻しに、それぞれ限定して完了している |

## 予想を裏切る挙動

- `build-derived-rules.sh` に `--dry-run` という引数は無い。`--apply` を付けないことがドライランであり、そのまま既定の状態になる
- `status` の差分検知は、一覧の突き合わせだけではなく、一時ディレクトリへ実際に生成した結果との突き合わせで行う。定義を変えていなくても、一時ディレクトリでの生成自体は毎回走る
- `check-rule-drift.sh` が突合する対象は `rule.md` の複製と `.mdc` ファイルだけである。`AGENTS.md` やフック登録ファイルは一部だけを差し替える方式のため、突合の対象に含めていない
- `apply` は `status: draft` の規約を自動で除外する。この除外は `build-derived-rules.sh` 自身が行うため、除外漏れの規約が生成物に混ざることはない
- `restore` は指定した `restore_ref` 時点のファイルをそのまま `git checkout` で戻すだけであり、戻した後の内容が現在の `docs/rules/` の定義と一致しているかは、戻した直後に自動で `check-rule-drift.sh` を実行して報告する。ただし一致しない場合の自動修復は行わない。`restore_ref` の時点から定義を変えていた場合、戻した直後に再びずれが検知されることがある
- `check-rule-drift.sh` はサブコマンドを持たない。`<rules_root> <出力先リポジトリルート>` の2つの位置引数だけを取り、`record`/`status` のような旧来のサブコマンドは無い。台帳ファイルも持たないため、自前で台帳を作る必要はなく、作ってもこのスクリプトからは参照されない

## 関連

- `importing-rule-proposals`：`docs/rules/` へ定義を書き込むもう一方のスキル。本スキルはその定義を読むだけで書き換えない
- `docs/rules/agent-operations/ai-config-asset-management/build-derived-rules.sh`：生成本体
- `docs/rules/agent-operations/ai-config-asset-management/validate-rule-definitions.sh`：整合検査
- `docs/rules/agent-operations/ai-config-asset-management/check-rule-drift.sh`：手作業編集検知（台帳を持たず、その場で再生成して突合する）
