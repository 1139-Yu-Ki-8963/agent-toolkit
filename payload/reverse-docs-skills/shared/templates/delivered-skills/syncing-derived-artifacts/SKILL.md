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

# 派生設定同期スキル

`docs/rules/` の定義から、`.claude/rules/`・`.cursor/rules/*.mdc`・`AGENTS.md`・3ツールのフック登録を生成する。定義は `docs/rules/` だけであり、これらの生成物を直接編集してはならない。本スキルは生成に加えて、生成物が手作業で編集されていないかの検知と、検知した際の復旧も担う。

## 引数

| 引数 | 必須 | 内容 |
|---|---|---|
| `mode` | 必須 | `status` / `apply` / `restore` のいずれか。既定値を持たない |
| `rules_root` | 任意 | 既定は `docs/rules` |
| `backup_id` | `restore` のときのみ任意 | 戻す先のバックアップの識別子。省略時は最新を使う |

`mode` に既定値を置かない理由は、誤りの方向が両側にあるためである。既定を `apply` にすると、事故で書き込みが起きる。既定を `status` にすると、`apply` のつもりで呼んだのに何も書き込まれず、しかもそれに気付けない。どちらの誤りも防ぐため、呼び出し側に明示させる。

## 生成に使う実行資産

`docs/rules-tooling/` 配下に配布されるスクリプトを呼ぶ。スクリプトの実体はこの1か所にしか置かない。

- `docs/rules-tooling/validate-rule-definitions.sh`：定義の整合検査。`build-derived-rules.sh` の内部からも自動で呼ばれる
- `docs/rules-tooling/build-derived-rules.sh <rules_root> <出力先リポジトリルート> [--apply]`：生成本体。**`--dry-run` という引数は存在しない**。`--apply` を付けなければ生成予定の一覧を表示するだけで書き込みが起きない。この省略状態が既定のドライラン扱いになる

`build-derived-rules.sh` は実行の最初に `validate-rule-definitions.sh` を呼び、不合格なら何も生成せず終了する。`status: draft` の規約は生成対象から除外され、除外件数を `非承認(draft)除外: N件` として出力する。この除外は `build-derived-rules.sh` 自身が行うため、本スキル側で重ねて絞り込む必要はない。

## モード別の動作

以下の6つをまとめて「派生ファイル一式」と呼ぶ。

- `.claude/rules/`
- `.cursor/rules/`
- `AGENTS.md`
- `.claude/settings.json`
- `.cursor/hooks.json`
- `.codex/config.toml`

台帳（後述）が対象とするのは、派生ファイル一式のうち丸ごと生成される2種類だけである。対象は `.claude/rules/**/rule.md` と `.cursor/rules/*.mdc` である。

### status

書き込みは一切行わない。次の2種類を確認する。

**生成予定と現状の差**。`mktemp -d` で作業用の一時ディレクトリを作る。実リポジトリではなくこの一時ディレクトリへ向けて `build-derived-rules.sh <rules_root> <一時ディレクトリ> --apply` を実行する。これにより、現在の定義から生成される内容を、実リポジトリの書き換えなしに得られる。この一時ディレクトリの内容と、実リポジトリの派生ファイル一式を突き合わせる。追加予定・変更予定・（定義から消えたための）削除予定を報告する。

**手作業編集の検知**。`docs/rules-tooling/derived-fingerprints.json` の台帳と、実リポジトリ側の対象2種類の現在のハッシュ値（`shasum -a 256`）を突き合わせる。判定は内容のハッシュだけで行い、更新日時は使わない。`git checkout` や別のツールでもファイルの更新日時は動くため、日時では手作業編集の有無を判定できない。台帳が対象2種類に絞る理由は、それ以外の派生ファイルがマーカーで挟んだ一部だけを差し替える方式だからである。ファイル全体のハッシュを取ると、対象外の箇所への正当な手作業編集まで「ずれ」として誤検知する。

台帳が存在しない場合は「未記録」として報告し、ずれの有無は判定しない。

### apply

最初に `build-derived-rules.sh --deploy-tooling <実リポジトリルート>` を実行し、`docs/rules-tooling/` へ2本を配備する。既に配備済みでも最新の内容で上書きする。

続けて `status` と同じ確認をし、結果を示す。

実リポジトリに現存する派生ファイル一式を `docs/rules-tooling/backups/<実行時刻>/` へまるごと複製する。生成前に必ずこの複製を取ってから次へ進む。

複製の後、`build-derived-rules.sh <rules_root> <実リポジトリルート> --apply` を実行する。`status: draft` の規約は生成対象から除外され、その件数は上記のとおりスクリプト自身が報告する。

承認済みの規約が0件でも、`AGENTS.md` の索引ブロックは空の内容で書き換わる。書き込み自体は必ず起きる。

生成が終わったら、台帳の対象2種類のハッシュを取り直す。ハッシュは `docs/rules-tooling/derived-fingerprints.json` へ記録する。記録の形式は「相対パスをキー、`sha256` ハッシュ値を値とするJSONオブジェクト」とする。

### restore

`docs/rules-tooling/backups/` の直下を新しい順に列挙し、利用できる複製の一覧を示す。`backup_id` の指定があればそれを使い、無ければ最新のものを使う。どちらを戻すかを示してから実行する。無条件に最新へ戻してはならない。

戻す対象が定まったら、その複製の内容で派生ファイル一式を上書きする。上書き後、台帳の対象2種類のハッシュを取り直し、台帳を戻した内容に合わせて更新する。

## Phase 1: 前提条件の確認

`mode` が3値のいずれかであることを確認する。無指定・不明な値であれば、指定必須である旨を返して停止する。`rules_root`（既定 `docs/rules`）が実在することを確認する。`restore` の場合は `docs/rules-tooling/backups/` が1件以上の複製を持つことを確認する。1件も無ければ「戻す先が無い」旨を報告して停止する。

**完了**: `mode` の値が確定し、`rules_root` の実在を確認済み。`restore` では複製の実在も確認済み

## Phase 2: モード別の実行

上記「モード別の動作」の該当節に沿って実行する。

**完了**: `status` は確認結果を報告して書き込みなしに終わっている。`apply` は複製の取得と生成と台帳更新が完了している。`restore` は対象の複製を示したうえで上書きと台帳更新が完了している

## Phase 3: 結果の報告

モードに応じて次を報告する。

- `status`: 追加予定・変更予定・削除予定の件数、手作業編集として検知したファイルの一覧（台帳が無ければその旨）
- `apply`: 複製の格納先、生成した各派生物のパス、`非承認(draft)除外` の件数、台帳へ記録した件数
- `restore`: 戻した複製の識別子、上書きした対象、台帳の更新結果

**完了**: モードに応じて報告し、`apply`/`restore` では書き込んだ具体的なパスを列挙している

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | `mode` の値が確定し、`rules_root`（`restore` は複製も）の実在を確認済み |
| Phase 2 | 選んだモードの動作を完遂している |
| Phase 3 | モードに応じた結果報告を行っている |
| **Goal** | 実行者が明示した1つのモードだけが走り、`status` は現状把握に、`apply` は複製取得後の反映に、`restore` は明示した複製への巻き戻しに、それぞれ限定して完了している |

## 予想を裏切る挙動

- `build-derived-rules.sh` に `--dry-run` という引数は無い。`--apply` を付けないことがドライランであり、そのまま既定の状態になる
- `status` の差分検知は、一覧の突き合わせだけではなく、一時ディレクトリへ実際に生成した結果との突き合わせで行う。定義を変えていなくても、一時ディレクトリでの生成自体は毎回走る
- 手作業編集の検知対象は `rule.md` の複製と `.mdc` ファイルだけである。`AGENTS.md` やフック登録ファイルは一部だけを差し替える方式のため、台帳の対象に含めていない
- `apply` は `status: draft` の規約を自動で除外する。この除外は `build-derived-rules.sh` 自身が行うため、除外漏れの規約が生成物に混ざることはない
- `restore` は指定した時点のファイルをそのまま戻すだけであり、戻した後の内容が現在の `docs/rules/` の定義と一致しているかは再検証しない。バックアップ後に定義を変えていた場合、戻した直後に `status` を実行すると再びずれが検知されることがある

## 関連

- `importing-rule-proposals`：`docs/rules/` へ定義を書き込むもう一方のスキル。本スキルはその定義を読むだけで書き換えない
- `docs/rules-tooling/build-derived-rules.sh`：生成本体
- `docs/rules-tooling/validate-rule-definitions.sh`：整合検査
- `docs/rules-tooling/derived-fingerprints.json`：手作業編集検知の台帳
- `docs/rules-tooling/backups/`：`apply` 実行前の複製の格納先
