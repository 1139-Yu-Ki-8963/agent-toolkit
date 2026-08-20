# generating-glossary-for-reverse-docs テストケース

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 外部出力-正常 | 対象repo外の絶対YAML path | 境界validatorを実行 | exit 0で正規化pathを返す | contract test |
| 外部出力-未指定 | proposal_output_refなし | Skillを起動 | 成果物なしでSTOPPED | Skill契約 |
| 外部出力-相対拒否 | 相対path | 境界validatorを実行 | exit 2 | contract test |
| 外部出力-repo内拒否 | 対象repo配下のpath | 境界validatorを実行 | exit 2、既存file不変 | contract test |
| 外部出力-symlink拒否 | 外部symlinkが対象repoを指す | 境界validatorを実行 | exit 2 | contract test |
| proposal-detected固定 | 外部pathへ候補を生成 | 正式validatorでproposal検証 | schema準拠、status=detected | contract test |
| proposal-diagnostics分離 | 候補に欠落源がある | sidecarを検査 | needs_reviewと未走査領域を保持 | contract test |
| headless-承認禁止 | 対話不能 | Skillを完走 | 自動承認せずNEEDS_REVIEW | static contract |
| glossary-直接更新禁止 | 候補抽出完了 | 出力一覧を検査 | glossary/page-data/HTMLを生成しない | static contract |
| portal-別経路 | 承認済みglossary YAMLあり | 管理Skillのportal publishを使う | 管理Skillだけが用語辞書を投影 | orchestrator contract |

正式テストコマンド:

```bash
bash .claude/skills/generating-glossary-for-reverse-docs/scripts/test-generating-glossary-proposal-contract.sh
```
