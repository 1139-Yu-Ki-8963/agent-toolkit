---
name: resolving-confirmation-items
description: |
  要確認事項への回答を設計書の該当セルへ反映し、台帳と反映先セルの整合を検査する。
  TRIGGER when: 納品後に要確認事項へ回答する時、回答済み事項を設計書へ反映する時。
  SKIP: コードから設計書を生成する時、回答を推測で補う時。
invocation: resolving-confirmation-items
type: transform
allowed-tools: [Bash, Read, Write]
---

<!-- 生成物: docs/skills/resolving-confirmation-items/SKILL.md から自動生成。直接編集しないこと -->

# 要確認事項の回答反映

設計単位フォルダ直下の `要確認事項台帳.json` を正として、回答済み事項を同じフォルダの設計書へ反映する。確認事項と回答の記録は台帳だけで管理する。

## 台帳の形式

台帳は `unitKey`、`designDocument`、`items` を持つ JSON とする。`items` の各要素は次の8項目だけを持つ。

| 項目 | 内容 |
|---|---|
| `key` | 単位内で一意のキー |
| `raisedDate` | 起票日（`YYYY-MM-DD`） |
| `question` | 確認事項 |
| `unresolvedReason` | コードから導出できなかった理由 |
| `status` | `未確認`・`確認中`・`回答済み`・`反映済み`・`対象外` のいずれか |
| `answer` | 回答。未回答時は空文字 |
| `answeredDate` | 回答日（`YYYY-MM-DD`）。未回答時は空文字 |
| `target` | `section`・`rowKey`・`column` を持つ反映先 |

`target.section` は反映対象の節見出し、`target.rowKey` はその節にある表の先頭列の値、`target.column` は書き換える列名を表す。設計書へ確認事項の一覧表を設けず、回答と履歴を重複して持たせない。

## 回答の記入

1. 回答者は該当行の `answer` と `answeredDate` を記入する。
2. 回答が確定した行だけ `status` を `回答済み` にする。
3. 回答が得られない行は `未確認` または `確認中` のまま残し、`unresolvedReason` を消さない。
4. 設計対象外と合意した行だけ `対象外` にする。推測で `回答済み` や `対象外` にしない。

## 設計書への反映

単位フォルダで次を実行する。

```bash
node <このスキルのフォルダ>/scripts/apply-confirmation-answers.mjs \
  --ledger ./要確認事項台帳.json
```

処理は `回答済み` の各行について、`target.section` 内の表から `target.rowKey` の行と `target.column` のセルを特定し、`answer` を書き込む。反映できた行は台帳の状態を `反映済み` にする。反映先が見つからない場合は設計書と台帳を変更せず異常終了する。

回答がない `未確認`・`確認中` の行は台帳に残る。実行結果に `未回答のため残す` とキー・状態を表示し、残した判断を台帳で追跡できるようにする。

## 整合検査

反映後、または台帳を手で直した後は次を実行する。

```bash
node <このスキルのフォルダ>/scripts/apply-confirmation-answers.mjs \
  --ledger ./要確認事項台帳.json \
  --check-only
```

検査は次を不合格にする。

- 台帳でキーが重複している
- `回答済み` のまま本文へ未反映の行が残っている
- `反映済み` の反映先セルが回答と一致しない、または確認できない
- 状態、日付、回答、反映先の形式が台帳の契約に合わない

## self-test

次を実行する。隔離した合成フィクスチャだけを使い、実際の設計書は変更しない。

```bash
node <このスキルのフォルダ>/scripts/apply-confirmation-answers.mjs --self-test
```

3件の要確認事項に対し、回答済み2件が本文の指定セルへ反映されること、未回答1件が台帳に残ること、反映後の整合検査が通ることを確認する。

## 完了条件

- `回答済み` の全行が指定した本文セルへ反映され、台帳では `反映済み` になっている
- `未確認`・`確認中` の全行が台帳に残っている
- `--check-only` が終了コード0で `PASS: 設計書と要確認事項台帳は整合しています` を出す
