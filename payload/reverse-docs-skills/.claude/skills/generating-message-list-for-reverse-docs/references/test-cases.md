# generating-message-list-for-reverse-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| メッセージ定義書不在-ハード停止 | output_dir配下にメッセージ定義書.mdが無い | Phase 1を実行する | 未作成である旨を報告して停止する | 手動 |
| 変換-5列テーブルからunits抽出 | 5列パイプテーブルが2件ある | convert-message-doc-to-manifest.shを実行する | units2件が抽出され終了コード0になる | convert-message-doc-to-manifest.shのself-testケース「正常系（5列テーブル2件からunits 2件抽出）」 |
| 変換-入力ファイル不在 | メッセージ定義書.mdが実在しない | convert-message-doc-to-manifest.shを実行する | 終了コード1で失敗する | convert-message-doc-to-manifest.shのself-testケース「異常系（入力ファイル不在）」 |
| 変換-テーブル0件でもfail-safe | テーブルが1件も見つからない | convert-message-doc-to-manifest.shを実行する | エラーにせずunits:[]で正常終了する | 手動 |
| 検証-完全契約パイプライン | 変換済みmanifestをHTML化し埋め込みJSONを再検証する | validate-message-manifest.shとbuild-unit-list.shを実行する | sourceFile配列と戻りリンクを含め埋め込みJSONが原本と一致する | validate-message-manifest.shのself-testケース「pipeline」 |
| 検証-approvedByUser常時false | 転記工程のためapprovedByUserがtrueに書き換えられている | validate-message-manifest.shを実行する | 終了コード1でFAILする | validate-message-manifest.shのself-testケース「陰性: approvedByUser=trueでFAIL」 |
| 検証-必須文字列キー欠落拒否 | unitKeyやkindなどがnullになっている | validate-message-manifest.shを実行する | 終了コード1でFAILする | validate-message-manifest.shのself-testケース「陰性: 必須文字列キー=nullでFAIL（unitKey等をループ検査）」 |
| html生成-message専用テンプレート経路 | manifest.jsonが確定済み | build-unit-list.shを--unit-kind messageで実行する | screenのようなbuild-screen-list.shへの委譲はされない | 手動 |
| 転記のみ-文言粒度は判定しない | メッセージ文言の粒度が不揃い | Phase 2を実行する | 妥当性や粒度は判定せず記載事実のみ転記する | 手動 |

## 機械検証との対応

- 機械検証が「手動」の行は、guide.html の検証状況へ手動確認を記録する
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
