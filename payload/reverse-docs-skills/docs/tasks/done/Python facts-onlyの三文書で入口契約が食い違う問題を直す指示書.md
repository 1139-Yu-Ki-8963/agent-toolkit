**状態**: 着手できる
**優先度**: 高
**前提**: なし
**元の指摘**: 1-261

## 1. この指示書は何か

Python facts-only経路を説明する三文書で、surveyからfactsへの順序ではなく入口の対話契約が食い違い、自己テストの失敗名が実原因を表していない問題を直す指示書である。

## 2. なぜ必要か

SKILL.mdとcontract.mdは不足値を推測せず中断する非対話契約だが、guide.htmlはprofileを質問すると説明する。さらにテストが旧契約を要求するため、正本に合わせた実装が不合格になる。

## 3. やること

guide.htmlを非対話契約へ統一する。`test-python-facts-flow.sh` はsurvey_doc_path確定→facts抽出の順序比較を維持し、三文書の非対話契約と旧い対話文言の不在も検査する。失敗名は入口契約または順序の不一致を示す文言へ変える。

## 4. 完了の判定

1. `bash generation-engine/scripts/tests/test-python-facts-flow.sh` が終了コード0を返す。
2. `bash .claude/rules/always/tasks/instruction-format/check-instruction-format.sh` が不合格0件で終了コード0を返す。
3. `bash generation-engine/scripts/tests/check-broken-verdict-rows.sh` が終了コード0を返す。

## 5. 触らない範囲

Python AST抽出、facts封印、画面フローのprofile固定、survey生成・revise処理、および三文書のsurvey_doc_path確定→facts抽出という処理順は変更しない。

## 6. 決めていないこと

| 何を決めるか | 既定（迷ったらこれを選ぶ） | 覆すときの条件 |
|---|---|---|
| 入口の不足値処理 | 対話せず、推測せず中断する | SKILL.mdとcontract.mdを同時に変更する別の承認済み要件がある場合 |
| テストの失敗名 | 入口契約とsurvey順序の両方を列挙する | 各条件を独立した判定へ分割する場合 |

## 7. 他の指示書との関係

1-260とは独立して実装できるが、第1層の機械検証を同時に完了させるため同じ作業で検収する。

## 8. この指示書の位置づけ

正本の非対話契約をguideと回帰検査へ反映し、検査を弱めず診断名も実態へ合わせる文書・テスト整合修正である。

## 9. 対応の記録

### 判定の充足状況

| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |
|---|---|---|---|---|
| 1. Python facts flow自己テストが終了コード0を返す | `bash generation-engine/scripts/tests/test-python-facts-flow.sh` | 完了 | b7538a7 | 三文書の入口契約とsurvey順序を含む全項目PASS、終了コード0 |
| 2. 指示書形式検査が不合格0件で終了コード0を返す | `bash .claude/rules/always/tasks/instruction-format/check-instruction-format.sh` | 完了 | b7538a7 | 合格97件、不合格0件、終了コード0 |
| 3. 壊れた判定行検査が終了コード0を返す | `bash generation-engine/scripts/tests/check-broken-verdict-rows.sh` | 完了 | b7538a7 | 実行3件、成功3件、失敗0件、終了コード0 |

### 判断の記録

| 何を決めたか | 選んだもの | 選んだ理由 | 覆すと何が変わるか |
|---|---|---|---|
| 三文書の正とする入口契約 | SKILL.mdとcontract.mdに一致する非対話契約 | 二文書が一致し、guideだけが反対の説明を持つ実測結果による | 対話入口へ戻す場合は三文書とテストを同時に変更する必要がある |
| 順序検査 | 既存の行位置比較を維持する | survey確定前のfacts抽出を防ぐ判定を弱めないため | 独立した構文検査へ置き換える場合だけテスト構造が変わる |
