---
name: maintaining-portal
description: |
  ポータルの生成HTMLへの手編集を検知し、版管理から元へ戻す。
  TRIGGER when: ポータルのHTMLを直接編集してしまった時、「ポータルのずれを確認して」「ポータルを元へ戻して」と言われた時。
  SKIP: 定義そのものの編集（→importing-rule-proposals）、AIツール向け設定の生成（→syncing-derived-artifacts）。
invocation: maintaining-portal
type: transform
allowed-tools: [Bash, Read, Write]
---

<!-- 生成物: docs/skills/maintaining-portal/SKILL.md から自動生成。直接編集しないこと -->

# ポータル保守スキル

ポータルのHTMLは定義から作られる生成物である。直接編集すると、次に作り直したときに変更が消える。本スキルは手編集を見つけて版管理から戻す。

## 引数

| 引数 | 必須 | 既定 | 意味 |
|---|---|---|---|
| `--mode` | いいえ | `status` | `status` は検知のみ。`restore` は版管理から戻す |
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

## 完了条件

1. `status` は書き込みを 1 件も行わず、検知の結果を報告する
2. `restore` は指定した版の内容と一致する状態にし、再検知で 0 件になることを確かめる
3. どちらのモードも、対象外のHTML（生成物の目印を持たないもの）を触らない

## 既知の限界

**ポータルを作り直す生成器は納品物に含まれない。** 本スキルができるのは、手編集の検知と版管理からの復旧までである。定義を変えた結果をHTMLへ反映するには、ポータルを生成した側での作り直しが必要になる。

この限界があるため、定義を変えた場合と手編集した場合を区別する必要がある。定義を変えたのであれば `importing-rule-proposals` で定義を正しく更新し、HTMLの更新はポータルを生成した側の作り直しを待つ。手編集したのであれば本スキルの `restore` で戻す。

## 予想を裏切る挙動

`restore` は版管理を使うため、指定した版に対象のHTMLが存在しない場合は復旧できない。その場合は該当パスを報告して次へ進み、途中で止まらない。

生成物の目印を持たないHTMLは、変更されていても報告しない。手書きのHTMLを誤って戻さないためである。

## 関連

- `docs/rules/documentation-standards/portal-maintenance/rule.md` — 本スキルが守らせる規約
- `.claude/skills/syncing-derived-artifacts/SKILL.md` — AIツール向け設定の側を担う同型のスキル
