# generating-entity-state-for-reverse-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 状態遷移表-0件停止 | データ設計.md§6状態遷移表にデータ行が1件もない | Phase 1 Step 2を実行する | 遷移を捏造せず0件を報告して停止する | 手動 |
| nodes組み立て-遷移前後からの補完 | 状態列に無い状態が遷移前か遷移後にのみ登場する | Phase 2 Step 1を実行する | 表記漏れがあってもnodesへ補完され孤児参照を防ぐ | 手動 |
| edges組み立て-根拠パス転記 | 状態遷移表の各行に根拠パス列がある | Phase 2 Step 2を実行する | sourceRefに根拠パスがそのまま転記される | 手動 |
| 自己遷移-孤児参照に該当しない | fromとtoが同一状態を指す行がある | validate-page-data.shを実行する | 孤児参照として検出されずPASSする | 手動 |
| html生成-埋め込みJSON一致 | entity-stateのpage-data.jsonがある | build-detail-page.shで生成する | ファイル名対応（状態遷移図.html）で出力し、埋め込みJSONが原本と完全一致する | build-detail-page.shのself-testケース「ケースd(entity-state)」 |
| html生成-未解決マーカーなし | 同上 | build-detail-page.shで生成する | page-data埋め込み範囲外に未解決の{{が残らない | build-detail-page.shのself-testケース「ケースd(entity-state)」 |
| key形式-複合キー | 複数エンティティを横断する同名状態がある | Phase 2 Step 1を実行する | keyは<エンティティ>.<状態>形式のため衝突しない | 手動 |
| portal反映-カード受け口配線済み | portal_output_dirを指定してbuild-portal.shを再実行する | Phase 4 Step 2を実行する | entity-stateのカードがportal-catalog.jsonの受け口経由でトップに表示され、状態遷移図.htmlへ遷移できる | 手動 |

## 機械検証との対応

- 機械検証が「手動」の行は、guide.html の検証状況へ手動確認を記録する
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
