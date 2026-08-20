# 用語管理Skill 静的テスト観点

| ID | シナリオ | 期待結果 |
|---|---|---|
| M1 | 操作指定なし | dry-runとして差分だけを返す |
| M2 | reverse解析がglossaryを直接更新 | proposalへ戻し、正式定義を変更しない |
| M3 | business/technical承認の片方が欠落 | review_requiredで停止する |
| M4 | validator exit 1/2 | reportはinvalid/unavailableとなり、入力・対象を変更しない |
| M5 | active用語の削除要求 | deprecateを案内する |
| M6 | retired移行要求 | active参照0件と移行証拠を要求する |
| M7 | publish target=portal | 承認済みglossaryだけを投影する |
| M8 | publish target=ai_index | not_implementedで成果物なしに停止する |
| M9 | exit 0、review_required>0 | status=validでも適用を止める |
| M10 | 診断report | schema準拠、counts再集計一致、診断familyを保持する |
| M11 | proposal reviewまたは変更操作でregistry省略 | review_requiredとして適用を止める |
| M12 | 実行形態 | AI向け手順であり、scriptsは契約検証用テストだけである |
| M13 | 承認者identity | 外部identity provider照合は未実装として人の確認へ戻す |
| M14 | 同一actorが二者roleを兼任 | role別承認を要求し、approved_byへrole-qualified identityを2件記録する |

正式test commandは `../scripts/test-managing-semantic-glossary.sh` とする。
wrapperは `check-skill-contract.test.sh` を呼ぶ。
正式validatorのexit 0/1/2 fixture、report schema、入力・対象無変更を検証する。
さらに、review_required blocking、portal投影CLIの出力、未承認proposal拒否を検証する。
proposalの正規呼出では `--registry` を渡す。
CLI再実行結果と手順契約を区分し、`../verification/ai-forward-test.json` に保存する。
`evidenceMode`、source hash前後、期待status/reason、成果物hashを検査する。
検査には `../scripts/verify-ai-forward-test.py` を使う。
portal成果物はCLI再生成とのbyte一致も確認する。`contract_only` はAI実行を再現した証拠ではない。
