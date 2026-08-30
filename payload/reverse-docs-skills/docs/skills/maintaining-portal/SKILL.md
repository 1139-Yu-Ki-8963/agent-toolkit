---
name: maintaining-portal
description: |
  ポータルの生成HTMLへの手編集を検知して版管理から元へ戻す、または生成器で作り直す。
  TRIGGER when: ポータルのHTMLを直接編集してしまった時、「ポータルのずれを確認して」「ポータルを元へ戻して」「ポータルを作り直して」と言われた時。
  SKIP: 定義そのものの編集（→importing-rule-proposals）、AIツール向け設定の生成（→syncing-derived-artifacts）。
invocation: maintaining-portal
type: transform
allowed-tools: [Bash, Read, Write]
---

# ポータル保守スキル

ポータルのHTMLは定義から作られる生成物である。直接編集すると、次に作り直したときに変更が消える。本スキルは手編集を見つけて版管理から戻すか、生成器でポータルを作り直す。

## 引数

| 引数 | 必須 | 既定 | 意味 |
|---|---|---|---|
| `--mode` | いいえ | `status` | `status` は検知のみ。`restore` は版管理から戻す。`regenerate` は生成器で作り直す |
| `--root` | いいえ | 現在のリポジトリのルート | 対象のリポジトリのルート |
| `--restore-ref` | `restore` のとき必須 | なし | 戻す先の版（枝名・タグ・コミットのいずれか） |
| `--source-root` | `regenerate` のとき必須 | なし | 一覧の元データが指すソースコードが実在するリポジトリのパス |
| `--project-name` | `regenerate` のとき任意 | なし | ポータルに表示するプロジェクト名 |

## 検知に使う実行資産

| 資産 | 役割 |
|---|---|
| `docs/rules/documentation-standards/portal-maintenance/check-generated-html-manual-edit.sh` | 生成物の目印を持つHTMLへの書き込みを止める検査 |
| `git` | 版管理との差分の取得と復旧 |

## 作り直しに使う実行資産

| 資産 | 役割 |
|---|---|
| `reverse-docs-engine/generation-engine/scripts/build-portal.sh` | ポータル本体・状態遷移図・ER図・画面遷移図・基盤資料等の生成 |
| `reverse-docs-engine/generation-engine/scripts/unit-list/build-screen-list.sh` | 画面一覧のHTML生成 |
| `reverse-docs-engine/generation-engine/scripts/unit-list/build-unit-list.sh` | 画面以外7種別の一覧HTML生成（`--unit-kind` で種別を指定） |
| `jq`・`node`（20以上）・`python3`・`shasum` | 生成器が内部で使う外部の道具 |

## 対象となるHTML

生成物の目印（`id="page-data"`・`id="unit-manifest"`・`id="screen-manifest"` のいずれか）を持つHTMLを対象とする。加えて `docs/rules/<親>/<子>/rule.html` も対象とする。目印を持たない手書きのHTMLは対象外とする。

## Phase 1: 前提の確認

1. `--root` が git のリポジトリであることを `git -C <root> rev-parse --show-toplevel` で確かめる。失敗したら中止して理由を報告する
2. `check-generated-html-manual-edit.sh` が配備されていることを確かめる。無ければ中止して「検査が配備されていない」と報告する
3. `--mode regenerate` のときは、追加で「作り直しの前提確認」節の手順を行う

## Phase 2: 手編集の検知

1. `git -C <root> status --porcelain -- '*.html'` で変更のあるHTMLを列挙する
2. 各HTMLについて「対象となるHTML」の条件に当てはまるかを判定する
3. 当てはまるものを、変更の種類（変更・削除・追加）で分けて数える

## Phase 3: モード別の動作

### status

書き込みをしない。Phase 2 の結果を次の形で報告する。

```
手編集の検知: 変更 <N> 件 / 削除 <N> 件 / 追加 <N> 件
  <パス>: <変更の種類>
```

0 件なら「手編集なし」と報告する。

### restore

1. `--restore-ref` が指定されていることを確かめる。無ければ中止する
2. Phase 2 で挙がった各パスを `git -C <root> checkout <restore-ref> -- <パス>` で戻す
3. 戻した後に Phase 2 を再実行し、0 件になったことを確かめる
4. 0 件にならなければ、残った件数とパスを報告する

### regenerate

生成器を使ってポータルとその関連資料を作り直す。手順は次のとおり。

1. `<root>/reverse-docs-engine/` が配られていることを確かめる。無ければ中止し、配られていない旨を報告する
2. 必要な外部の道具（`jq`・`node`・`python3`・`shasum`）が揃っていることを確かめる。欠けていれば中止し、欠けている道具の名前を報告する
3. 「一覧を先に作り、ポータル本体を後に作る」節の順序に従い、一覧のHTMLを種別ごとに作り直す
4. `build-portal.sh <--source-root で指定したパス> <docsとproject-portalを子に持つルート> <ポータルの出力先>` を実行する。ポータル本体を作り直す
5. 作り直したあと `--mode status` を実行し、定義と生成物が一致することを確かめる。一致しなければ差分を報告する

## 一覧を先に作り、ポータル本体を後に作る（順序の制約）

**一覧のHTMLを先に作り、そのあとにポータル本体を作る。** `build-portal.sh` が作るポータル本体の規模カードは、既存の一覧HTMLから件数を読む設計になっている。順序を逆にすると、ポータル本体の規模カードの件数が0のまま生成される。この0件は生成が失敗した合図を出さないため、順序を誤ったこと自体に気づきにくい。

一覧のHTMLは `build-portal.sh` の中で作られるのではなく、種別ごとに次のスクリプトで個別に作る。

| 対象 | スクリプト |
|---|---|
| 画面 | `reverse-docs-engine/generation-engine/scripts/unit-list/build-screen-list.sh <画面の元データ> <出力先>` |
| 画面以外の7種別 | `reverse-docs-engine/generation-engine/scripts/unit-list/build-unit-list.sh <元データ> <出力先> --unit-kind <種別>` |

メッセージの一覧だけは例外で、`build-portal.sh` が作る。

## 作り直しの前提確認

1. `--source-root` で指定したパスに、対象リポジトリのソースコードが実在することを確かめる。一覧の元データが指すファイルの実在を検査する仕組みがあるため、ソースコードが同じ場所に無いと一覧の作り直しが途中で止まる
2. `<root>/reverse-docs-engine/` の内部階層を確認する。対象は `generation-engine/scripts/`・`delivery-payload/templates/` の2つ。加えて `delivery-payload/references/` も対象である。配られたときのままであることを確かめる。階層を動かすと、生成器がテンプレートを見つけられずに止まる
3. どちらも満たさない場合は作り直しを中止し、満たさない条件を報告する

## 完了条件

1. `status` は書き込みを 1 件も行わず、検知の結果を報告する
2. `restore` は指定した版の内容と一致する状態にし、再検知で 0 件になることを確かめる
3. `regenerate` は一覧のHTMLを先に、ポータル本体を後に作り直し、作り直し後の `status` で定義と生成物が一致することを確かめる
4. どのモードも、対象外のHTML（生成物の目印を持たないもの）を触らない

## 使い方の条件（作り直しに残る制約）

作り直しには次の2つの条件がある。いずれも生成器を正しい環境と正しい階層で使うための条件であり、機能そのものの不足ではない。

- 一覧の元データが指すファイルの実在を検査する仕組みがあるため、対象リポジトリのソースコードが `--source-root` の場所に揃っていないと、一覧の作り直しが止まる。作り直しは対象リポジトリのソースコードが揃っている場所で実行する
- `reverse-docs-engine/` の階層を動かすと、生成器がテンプレートを見つけられずに止まる。配られたときの階層をそのまま保つ

## 予想を裏切る挙動

`restore` は版管理を使うため、指定した版に対象のHTMLが存在しない場合は復旧できない。その場合は該当パスを報告して次へ進み、途中で止まらない。

生成物の目印を持たないHTMLは、変更されていても報告しない。手書きのHTMLを誤って戻さないためである。

`regenerate` で `--portal-only` と `--standalone` を同時に指定すると `build-portal.sh` が異常終了する。両者は同時に指定できない。

## 関連

- `docs/rules/documentation-standards/portal-maintenance/rule.md` — 本スキルが守らせる規約
- `.claude/skills/syncing-derived-artifacts/SKILL.md` — AIツール向け設定の側を担う同型のスキル
- `reverse-docs-engine/README.md` — 配られた生成器一式の使い方
