---
name: reverse-proposing-rules
日本語名: 規約提案を出す
description: "全設計文書・コード・支援ツール側の写しの規約を読み、規約の提案（用語の追加候補を含む）を出典と提案先付きでconfirmations/規約提案.mdへ書く。AIが様式を埋め、検査スクリプトが出典・提案先・観測なしの理由を検査する。工程2-10。"
invocation: reverse-proposing-rules
type: transform
allowed-tools: [Bash, Read, Glob, Grep, Write]
unit: reverse
category: setup
kind: none
inputs: [docs/design/requirements/要件定義書.md, docs/design/common/*.md, docs/design/screens/*/画面/基本設計/画面基本設計書.md, docs/design/apis/*/API基本設計書.md, docs/design/tables/*/論理データモデル.md, docs/design/batches/*/バッチ基本設計書.md, docs/design/reports/*/帳票基本設計書.md, docs/design/externals/*/外部連携基本設計書.md, docs/design/features/*/機能設計書.md, docs/design/lists/*.json, confirmations/確認事項の記録.md]
outputs: [confirmations/規約提案.md]
requires: [reverse-writing-detail-design]
---
<!-- 生成物: 定義は支援ツールの正本リポジトリの docs/skills/reverse-proposing-rules/ にある（この配布物には含まれない）。直接編集しないこと -->

## いつ使うか

工程2-8（単位の詳細設計）が完了条件を満たした後（テスト設計書の出力を「出力する」にした場合は工程2-9の後）。設計文書とコードから規約の提案・用語の追加候補を出すとき。

## いつ使わないか

規約の採否・用語の承認そのものを決めるとき（採否は工程2-12でユーザーに聞き、確認事項の記録へ回答として書き戻す。本機能は提案を出すだけ）。

## 前提

- 実行フォルダを受け取る
- 設計書の置き場は `bash ../reverse-shared/scripts/design-root.sh <実行フォルダ>` で読む
- 提案先の規約の一覧は `../reverse-shared/references/rule-taxonomy.json` で読む。setupの規約の分類の写しであり、同一性は`reverse-shared/tests/test-self-tests.sh`が確かめる
- 前提条件は工程2-8（単位の詳細設計）の完了のみ。テスト設計書の出力を「出力する」にした場合、統括の実行順（plan-reverse.sh）は入出力の重なりにより工程2-9の後に本機能を置く。requiresへ2-9を明示しないのは、2-9が「出力しない」設定では何もしない任意工程であり、本機能の前提条件をそれより強くしないためである

## 手順

1. `bash ../reverse-shared/scripts/design-root.sh <実行フォルダ>` で設計書の置き場を読む
2. 設計書の置き場配下の全設計文書とコードを読み、規約提案の候補（表の名前の付け方・入力検証の分け方・用語の追加候補等）を集める
3. `templates/規約提案.md` を `confirmations/規約提案.md` へ複製する。「## 観測」節（キー・観測した慣行・出典の文書・数え方の条件）と「## 判断」節（キー・提案先の規約・提案する規則・検査の手段・判断）を埋める。観測できる慣行が無い規約は「## 観測なし」節にキーと理由を書く
4. 提案先の規約は `../reverse-shared/references/rule-taxonomy.json` の `parent`/`key` の組で書く（例: `code-standards/naming`）
5. `bash scripts/check-rule-proposals.sh <実行フォルダ>` を実行する
6. 不合格の理由が名指しする行を直し、手順3へ戻る
7. 提案の採否・用語の承認は確認事項の記録へ行として書く（工程2-12で開発チームに聞く）

## 観測と判断の分離

「## 観測」節は数え方の条件を併記した事実の記録、「## 判断」節は提案する・しないの判断を持つ。判断の根拠が観測に無い提案は作らない。

## 完了条件

- `confirmations/規約提案.md`があり、「## 観測」「## 判断」「## 観測なし」の3節を持つ
- 「## 判断」の各行に出典の文書（「## 観測」の対応するキーの行）と提案先の規約がある
- 提案先の規約が`rule-taxonomy.json`の`parent`/`key`の組に実在する
- 「## 観測なし」の各行に理由がある
- `scripts/check-rule-proposals.sh`が終了コード0

## 設計判断

### check-rule-proposals.sh

**必要性**: 規約提案は出典の無い思いつきや、実在しない規約への提案では採否を判断できない。AIが様式を埋める性質上、出典・提案先・理由の欠落を機械で検知する必要がある。

**代替案を採用しなかった理由**:
- 検査を持たずAIの自己申告に任せる: 出典の無い提案・存在しない規約への提案が確認事項の記録まで混入する
- 提案先の存在確認を省く: 採否を聞く工程2-12で初めて「そんな規約は無い」と気づき、手戻りになる

**保守責任者**: 人手（ユーザー）。様式の節構成を変えるときは、本スクリプトと`templates/規約提案.md`と自己テストを同時に直す。

**廃棄条件**: 規約提案の様式を構造化データに変えた時。

### tests/test-self-tests.sh

**必要性**: 検収の入口を`tests/`配下に固定する規約（skill-naming）に従う。`check-rule-proposals.sh --self-test`を呼ぶ薄い入口が要る。他のreverse機能と同じ形の入口を持つ。

**代替案を採用しなかった理由**:
- Bashツール直叩き: `check-acceptance.sh`等の一括検収が`tests/`配下の実行可能な`*.sh`を規約で探すため、入口が無いと自動収集されない
- 既存Makefileターゲット拡張・package.json scripts追加: このリポジトリはどちらも持たない

**保守責任者**: 人手（ユーザー）。check-rule-proposals.shのケースを増減する場合は本ファイルは変えず、スクリプト側と単体テスト設計書の件数を直す。

**廃棄条件**: reverse-proposing-rules自体を廃止した時。
