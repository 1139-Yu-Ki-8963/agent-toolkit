# 用語保守Skill 静的テスト観点

| ID | シナリオ | 期待結果 |
|---|---|---|
| K1 | add/update/deprecate/retire | glossaryを直接編集せず変更要求を作る |
| K2 | delete要求 | 操作を拒否しdeprecate/retireを案内する |
| K3 | 類義語候補 | 自動統合せず人の裁定へ回す |
| K4 | 全チャネル0件 | human_check_requiredを残し削除しない |
| K5 | key/definition/scopeの破壊的変更 | 影響分析と移行案を必須にする |
| K6 | proposal審査 | 観測事実と推定を分離する |
| K7 | validator exit 1/2 | review_requiredで停止する |
| K8 | exit 0、review_required>0 | valid reportでも適用可能な変更要求にしない |
| K9 | publish要求 | portalは管理Skillへ委譲し、ai_indexは成果物なしで停止する |
| K10 | 診断report | schema準拠、counts再集計一致、診断familyを保持する |
| K11 | 実行形態 | AI向け手順であり、scriptsは契約検証用テストだけである |
| K12 | 承認者identity | 外部identity provider照合は未実装として人の確認へ戻す |
| K13 | proposal reviewまたは変更操作でregistry省略 | review_requiredとして管理Skillへ変更要求を渡さない |
| K14 | 同一actorが二者roleを兼任 | role別承認を要求し、change案のapproved_byへrole-qualified identityを2件記録する |

正式test commandは `../scripts/test-maintaining-semantic-glossary.sh` とする。
wrapperは `check-skill-contract.test.sh` を呼ぶ。
正式validatorのexit 0/1/2 fixture、report schema、入力・対象無変更を検証する。
さらに、review_required blocking、portal投影CLIの出力、未承認proposal拒否を検証する。
proposalの正規呼出では `--registry` を渡す。
CLI再実行結果と手順契約を区分し、`../verification/ai-forward-test.json` に保存する。
`evidenceMode`、source hash前後、期待status/reason、変更要求サンプルhashを検査する。
検査には `../scripts/verify-ai-forward-test.py` を使う。
`contract_only` はAI実行を再現した証拠ではない。
