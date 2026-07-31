# generating-er-diagram-for-reverse-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 前提-テーブル一覧不在-ハード停止 | テーブル一覧.htmlが不在 | Phase 1 Step 1を実行する | テーブル一覧生成スキルの先行実行を案内して停止する | 手動 |
| 検出戦略-ユーザー承認必須 | ORMやマイグレーション種別を判別した | Phase 1 Step 3を実行する | AskUserQuestionで検出戦略の承認を取ってから抽出へ進む | 手動 |
| entities-manifest外参照は捏造しない | FKの参照先テーブルがmanifestに存在しない | Phase 2 Step 2を実行する | relations[]へ加えずunresolved[]へ分離する | 手動 |
| columns型検証-正常系 | entities[].columnsのnameとtypeが文字列、pk等が真偽値 | validate-page-data.shを実行する | 全項目PASSする | validate-page-data.shのself-testケース「ケースa」 |
| columns型検証-異常系 | columns[].pkが文字列"yes"など型が不正 | validate-page-data.shを実行する | 終了コード1でFAILする | validate-page-data.shのself-testケース「ケースb」 |
| entities0件-ハード停止 | テーブル一覧manifestにentitiesが1件もない | Phase 2 Step 3を実行する | 描画対象が無いためユーザーに報告して停止する | 手動 |
| FK0件-俯瞰ページ生成 | entitiesが3件でrelationsが0件 | build-detail-page.shで生成する | クラスタ探索を表示せずentities全件を静的に描画し外部キー0件を明示する | build-detail-page.shのself-testケース「ケースk(er-relations無)」 |
| relations非空-flat-list非表示 | relationsが非空の通常系 | build-detail-page.shで生成する | flat-listセクションは出力されない（後方互換） | build-detail-page.shのself-testケース「ケースk(er-relations有)」 |
| clipboardフォールバック | ER図.htmlを生成する | build-detail-page.shで生成する | execCommandによるclipboardフォールバックが出力に含まれる | build-detail-page.shのself-testケース「ケースf(er)」 |
| 自己参照FK-孤児関連に該当しない | fromとtoが同一entities[].keyを指すFKがある | validate-page-data.shを実行する | 孤児関連として検出されない | 手動 |
| entities-key識別子 | テーブル一覧manifestのunitがある | Phase 2 Step 1を実行する | entities[].keyはidentifierを使う（unitKeyではない） | 手動 |

## 機械検証との対応

- 機械検証が「手動」の行は、generating-er-diagram-for-reverse-docs-guide.html の検証状況へ手動確認を記録する
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
