---
name: reverse-building-confirmation-items
日本語名: 確認事項一覧を作る
description: "確認事項の記録と各設計書の要確認事項一覧を読み、8列1枚の確認事項一覧を決定的なスクリプトで組み立てる。記録に無いキーを検知する。工程2-11。"
invocation: reverse-building-confirmation-items
type: transform
allowed-tools: [Bash, Read, Glob, Grep]
unit: reverse
category: setup
kind: none
inputs: [confirmations/確認事項の記録.md, docs/design/requirements/要件定義書.md, docs/design/common/*.md, docs/design/screens/*/画面/基本設計/画面基本設計書.md, docs/design/apis/*/API基本設計書.md, docs/design/tables/*/論理データモデル.md, docs/design/batches/*/バッチ基本設計書.md, docs/design/reports/*/帳票基本設計書.md, docs/design/externals/*/外部連携基本設計書.md, docs/design/features/*/機能設計書.md, confirmations/規約提案.md]
outputs: [confirmations/確認事項一覧.md]
requires: [reverse-proposing-rules]
---

## いつ使うか

工程2-10（規約提案）が完了条件を満たした後。各工程が確認事項の記録へ書いた事項と、各設計書の「要確認事項一覧」節を1枚の確認事項一覧へまとめるとき。

## いつ使わないか

確認事項の記録の内容そのものを作るとき（各工程が個別に確認事項の記録へ直接書く。本機能はまとめるだけ）。

## 前提

- 実行フォルダを受け取る
- 設計書の置き場は `bash ../reverse-shared/scripts/design-root.sh <実行フォルダ>` で読む
- 確認事項の記録は `<実行フォルダ>/confirmations/確認事項の記録.md`

## 手順

1. `bash ../reverse-shared/scripts/design-root.sh <実行フォルダ>` で設計書の置き場を読む
2. `bash scripts/build-confirmation-items.sh <実行フォルダ> --design-root <設計書の置き場>` を実行する。設計書の置き場配下の全「要確認事項一覧」節を走査し、確認事項の記録と突き合わせて `confirmations/確認事項一覧.md` を書く
3. 終了コード1（既定・反映先の空欄）なら、名指しされたキーの既定・反映先を確認事項の記録または該当する設計書の「要確認事項一覧」節へ書き足し、手順2へ戻る
4. 出力の完備性を確かめる。`bash scripts/build-confirmation-items.sh --verify <確認事項一覧.md> --design-root <置き場>` を使う。終了コード1なら手順2へ戻る

## 要確認事項一覧の列見出しの3通り

設計書によって「要確認事項一覧」節の列見出しが異なる。本機能は列名の文字列で値を読み分け、並び順を前提にしない。見出しの判定は前方一致（末尾の空白・付記を許す）で行う。表のセル内にエスケープ済みパイプ（`\|`）がある場合は列区切りと誤認せず、元の文字へ戻して読む。

| 列見出しの組 | 使う設計書の例 |
|---|---|
| キー・確認事項・確認先 | 要件定義書、業務仕様書等の共通設計文書 |
| キー・事項・既定 | 共通処理の詳細設計書 |
| キー・事項・既定・状態 | 基本設計書 |

## 埋め方の規則

| 欄 | 埋め方 |
|---|---|
| 単位 | 設計書の置き場から取る。`docs/design/common/`・`docs/design/requirements/`配下は「全体」。それ以外は単位のフォルダ名。同じキーが複数の単位に現れる場合は先頭の単位と「ほかN件」を書く |
| 種類 | 「確認先」列の値から当てる。非機能要件定義書は非機能、事業部門は業務ルール、運用部門は運用、設計担当は制約とする。対応が無い場合は制約とする |
| 事項 | 「確認事項」または「事項」列の値を写す |
| 既定 | 「既定」列があればその値。無ければ「設計書の現行の記述のまま扱う」を置く |
| 反映先 | 「設計書のファイル名 単位」の形で書く |
| 回答 | 空欄のまま |
| 状態 | 「未回答」を置く |

## 完了条件

- 出力の全行に既定と反映先がある
- 設計書の要確認事項一覧の全キーが出力に載っている（`--verify`で確認）
- `scripts/build-confirmation-items.sh`が終了コード0

## 設計判断

### build-confirmation-items.sh

**必要性**: 確認事項の記録と、7種別・共通設計文書に散らばる「要確認事項一覧」節を、開発チームが読める1枚の8列表へ統合する必要がある。列見出しが設計書によって3通りに分かれるため、列名を動的に読み分ける必要がある。設計書のキーが記録に登録されないまま進む事故（実測で94件の登録漏れ）を機械で検知する必要もある。

**代替案を採用しなかった理由**:
- 確認事項の記録をそのまま確認事項一覧として使う: 設計書側で新たに見つかったキー（記録への登録漏れ）を拾えない
- AIが手で1枚にまとめる: 219件規模のキーを人手で突き合わせると漏れが生じる

**保守責任者**: 人手（ユーザー）。要確認事項一覧の列見出しの組み合わせを増やすときは、本スクリプトと自己テストを同時に直す。

**廃棄条件**: 確認事項の記録・要確認事項一覧の様式を構造化データに変えた時。

### tests/test-self-tests.sh

**必要性**: 検収の入口を`tests/`配下に固定する規約（skill-naming）に従う。`build-confirmation-items.sh --self-test`を呼ぶ薄い入口が要る。他のreverse機能（reverse-writing-test-designs等）も同じ形の入口を持つ。

**代替案を採用しなかった理由**:
- Bashツール直叩き: `check-acceptance.sh`等の一括検収が`tests/`配下の実行可能な`*.sh`を規約で探すため、入口が無いと自動収集されない
- 既存Makefileターゲット拡張・package.json scripts追加: このリポジトリはどちらも持たない

**保守責任者**: 人手（ユーザー）。build-confirmation-items.shのケースを増減する場合は本ファイルは変えず、スクリプト側と単体テスト設計書の件数を直す。

**廃棄条件**: reverse-building-confirmation-items自体を廃止した時。
