---
name: maintaining-portal
description: |
  ポータルの生成HTMLへの手編集を検知して版管理から元へ戻す、または設計書の変更に合わせて手作業で作り直す。
  TRIGGER when: ポータルのHTMLを直接編集してしまった時、「ポータルのずれを確認して」「ポータルを元へ戻して」「ポータルを作り直して」と言われた時。
  SKIP: 定義そのものの編集（→importing-rule-proposals）。
invocation: maintaining-portal
type: transform
allowed-tools: [Bash, Read, Write]
---

# ポータル保守スキル

ポータルのHTMLは定義（設計書・規約・一覧の元データ）から作られる生成物である。生成器は納品先に配らないため、直接編集を検知して版管理から戻すか、変更のあった箇所だけを手作業でHTMLへ反映する。

## 引数

| 引数 | 必須 | 既定 | 意味 |
|---|---|---|---|
| `--mode` | いいえ | `status` | `status` は検知のみ。`restore` は版管理から戻す。`regenerate` は変更のあった箇所を手作業で反映する |
| `--root` | いいえ | 現在のリポジトリのルート | 対象のリポジトリのルート |
| `--restore-ref` | `restore` のとき必須 | なし | 戻す先の版（枝名・タグ・コミットのいずれか） |

## 検知に使う実行資産

| 資産 | 役割 |
|---|---|
| `docs/rules/documentation-standards/portal-maintenance/check-generated-html-manual-edit.sh` | 生成物の目印を持つHTMLへの書き込みを止める検査 |
| `git` | 版管理との差分の取得と復旧 |

## 対象となるHTML

生成物の目印（`id="page-data"`・`id="unit-manifest"`・`id="screen-manifest"` のいずれか）を持つHTML、および `docs/rules/<親>/<子>/rule.html` を対象とする。目印を持たない手書きのHTMLは対象外とする。

## Phase 1: 前提の確認

1. `--root` が git のリポジトリであることを `git -C <root> rev-parse --show-toplevel` で確かめる。失敗したら中止して理由を報告する
2. `check-generated-html-manual-edit.sh` が配備されていることを確かめる。無ければ中止して「検査が配備されていない」と報告する

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

生成器を持たないため、変更のあった設計単位だけを対象のHTMLへ手作業で反映する。手順は次のとおり。

1. **どの入力を読むか。** 更新・追加・削除された入力（`docs/rules/` の規約本文、`docs/design/` の各設計単位、一覧の元データ）を、直前のコミットとの差分から列挙する
2. **どのHTMLを直すか。** 各入力に対応するHTMLを `project-portal/` の配置規則（一覧は `lists/<種別>/<種別の日本語名>一覧.html`、画面詳細は `screens/<画面キー>/` 配下、規約は `docs/rules/<親>/<子>/rule.html`）から特定する
3. **どのテンプレートに沿って更新するか。** 特定したHTML自身の中にある、変更していない他の設計単位の既存エントリを手本にする。埋め込みJSON（`id="page-data"`・`id="unit-manifest"`・`id="screen-manifest"`）の中の、対応する要素をキー・型・並びとも既存エントリと同じ構造で追加・更新・削除する。表示側のマークアップは埋め込みJSONを読んで描画する既存のスクリプトをそのまま使い、スクリプト自体は書き換えない
4. **最後に何を照合するか。** 更新したHTMLを読み直し、埋め込みJSONの値（画面名・参照元コミット・件数など）が入力（設計書・一覧の元データ）の現在の値と一致することを確かめる
5. 反映後に `--mode status` を実行し、対象外の手編集が紛れ込んでいないことを確かめる

## 完了条件

1. `status` は書き込みを 1 件も行わず、検知の結果を報告する
2. `restore` は指定した版の内容と一致する状態にし、再検知で 0 件になることを確かめる
3. `regenerate` は入力の変更に対応するHTMLだけを更新し、更新後の値が入力の現在の値と一致することを確かめてから、`status` で対象外の手編集が無いことを確かめる
4. どのモードも、対象外のHTML（生成物の目印を持たないもの）を触らない

## 予想を裏切る挙動

`restore` は版管理を使うため、指定した版に対象のHTMLが存在しない場合は復旧できない。その場合は該当パスを報告して次へ進み、途中で止まらない。

生成物の目印を持たないHTMLは、変更されていても報告しない。手書きのHTMLを誤って戻さないためである。

`regenerate` は埋め込みJSONの構造を変えない。既存エントリと異なるキー・型で追加すると、表示側のスクリプトが読み込めず、その項目だけ描画されない。

## 関連

- `docs/rules/documentation-standards/portal-maintenance/rule.md` — 本スキルが守らせる規約
