# generating-env-guide-for-reverse-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 調査書不在-ハード停止 | アーキテクチャ調査書.mdが不在 | Phase 1 Step 1を実行する | 調査スキルの先行実行を案内して停止する | 手動 |
| env-config任意-不在でも続行 | env_config_pathが存在しない | Phase 1 Step 2を実行する | 停止せず前提ツール表のみ省略して続行する | 手動 |
| steps組み立て-order欠番拒否 | steps[].orderに欠番（1と3）がある | validate-page-data.shを実行する | 終了コード1でFAILする | validate-page-data.shのself-testケース「ケースf」 |
| steps組み立て-command散文混入拒否 | steps[].commandに句点を含む説明文が混入している | validate-page-data.shを実行する | 終了コード1でFAILする | validate-page-data.shのself-testケース「ケースg」 |
| steps組み立て-連番かつ純粋な正常系 | orderが連番でcommandが純粋（該当なし含む） | validate-page-data.shを実行する | 全項目PASSする | validate-page-data.shのself-testケース「ケースi」 |
| environment-linux互換表記の描画 | environment[]にlinux_compat_env=trueがある | build-detail-page.shで生成する | 互換環境上での実行の表記がHTMLに出力される | build-detail-page.shのself-testケース「ケースg(env-true)」 |
| environment-false時は非表示 | linux_compat_env=falseがある | build-detail-page.shで生成する | 互換環境表記は出力されない | build-detail-page.shのself-testケース「ケースg(env-false)」 |
| environment-空配列でも生成成功 | environment[]が空配列 | build-detail-page.shで生成する | エラーにならず生成できる | build-detail-page.shのself-testケース「ケースg(env-empty)」 |
| sourceRef検査-allocationsのみ対象 | prerequisitesとstepsにはsourceRefが存在しない | validate-page-data.shを実行する | sourceRef実在検査はallocations[].sourceRefのみを対象にする | 手動 |
| allocations抽出-記載なしは空配列 | 環境変数定義ファイルに割当を示す記載が無い | Phase 2 Step 3を実行する | 捏造せず空配列のまま進める | 手動 |

## 機械検証との対応

- 機械検証が「手動」の行は、generating-env-guide-for-reverse-docs-guide.html の検証状況へ手動確認を記録する
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
