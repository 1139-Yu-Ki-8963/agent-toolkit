# generating-rule-proposals-for-reverse-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 出力先-リポジトリ外 | `output_path` が `target_repo_path` の内側を指す | Phase 1 Step 3を実行する | HTMLを生成せず、外側のパスへ変更するよう報告して停止する | 手動 |
| 状態-4値 | 27カテゴリそれぞれに `state` を判定する | Phase 2 Step 2を実行する | 全カテゴリが `proposal`・`proposal-limited`・`na`・`common` のいずれかになる | 手動 |
| 状態-未知値のフォールバック | `state` に4値以外の値を持つカテゴリがある | `build-rule-proposal.sh` を実行する | エラーにせず判定ボタンなし（`pill--na` 相当）として描画される | `build-rule-proposal.sh` の手動スモークテスト（`state: "unknown-value"` を含む入力JSONで確認済み） |
| 検査可能-静的判定のみ | あるカテゴリの `checkMethod` が人手判断（レビュー観点等）を要する内容である | Phase 4 Step 2で `checkable` を確定する | `checkable: false` とし、静的解析で判定できるものだけに `true` を付ける | 手動 |
| 強制-2値 | Phase 4で `enforcement` を確定する | `enforcement` に値を設定する | `advisory` か `none` のいずれかになり、`block` は選べない | 手動 |
| 強制-none透過確認 | `enforcement: "none"` を持つカテゴリがある | `build-rule-proposal.sh` を実行する | `data-enforcement="none"` がそのまま出力へ反映される | `build-rule-proposal.sh` の手動スモークテスト（`enforcement: "none"` を含む入力JSONで確認済み） |
| 生成-決定的 | 同一の入力JSONと同一の `--generated-at` を使う | `build-rule-proposal.sh` を2回実行する | 2回の出力がbyte一致する | `build-rule-proposal.sh --self-test` のケース4（同一入力からの2回の生成がbyte一致） |
| 骨格-文書構造 | 最小の入力JSONを渡す | `build-rule-proposal.sh` を実行する | 文書骨格（doctype・タイトル・カテゴリid）を持つHTMLが生成される | `build-rule-proposal.sh --self-test` のケース1 |
| 判定ボタン-state依存 | `state` が `na`/`common` のカテゴリと `proposal` のカテゴリが混在する | `build-rule-proposal.sh` を実行する | `na`/`common` に判定ボタンが出ず、`proposal` には出る | `build-rule-proposal.sh --self-test` のケース2 |
| 未解決マーカーなし | 任意の入力JSONで生成する | `build-rule-proposal.sh` を実行する | 出力に未解決の `{{` が残らない | `build-rule-proposal.sh --self-test` のケース6 |
| na-理由必須 | `state: "na"` のカテゴリがある | Phase 2 Step 2を実行する | 判定ボタンを出さず、対象外の理由（`reason`）のみを示す | 手動 |
| 観測-根拠の同伴 | `state` が `proposal` か `proposal-limited` のカテゴリがある | Phase 3を実行する | 観測ごとにパスと行番号が付き、断定できない事項は「未確認」と明記される | 手動 |
| キー-宣言一致 | 提案データの `key` と `slug` を組み立てる | Phase 2 Step 1を実行する | 提案データの `key` と `slug` が `shared/references/rule-taxonomy.json` の親 `key`・子 `key` と一致する | 手動 |

## 機械検証との対応

- 機械検証が「手動」の行は、generating-rule-proposals-for-reverse-docs-guide.html の検証状況へ手動確認を記録する
- `build-rule-proposal.sh` の `--self-test` に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
- 「手動スモークテスト」と記載した行は、本スキル追加時に一度限りで実行した確認であり、`--self-test` へは未統合。統合する場合はこの表の機械検証列を更新する
