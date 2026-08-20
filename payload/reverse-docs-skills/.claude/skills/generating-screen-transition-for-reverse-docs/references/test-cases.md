# generating-screen-transition-for-reverse-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| raw定義ext不在-ハード停止 | 永続raw定義またはraw由来extのいずれかが不在 | Phase 1 Step 1を実行する | 通常生成では画面一覧HTMLから復元せずハード停止する | 手動 |
| route空文字-unresolved隔離 | routeが空文字列の画面がnodes転記元にある | Phase 2 Step 1を実行する | nodes[]に含めず、有効表示名と理由付きでunresolved[]へ登録する | 手動 |
| 孤児edge-検出 | 存在しないnodes[].unitKeyをtoに持つedgeがある | validate-page-data.shで検証する | FAILし孤児参照として検出される | validate-page-data.shのself-testケース(c)「存在しないnodes[].unitKeyをtoに持つ孤児edgeを含むtransitionフィクスチャがFAILする」 |
| ノード件数整合-不一致検出 | manifestScreenCountとnodes[]+route空文字unresolved[]件数が一致しない | validate-page-data.shで検証する | FAILする | validate-page-data.shのself-testケース(d)「manifestScreenCountとnodes[]+route空文字unresolved[]件数が一致しないtransitionフィクスチャがFAILする」 |
| ノード件数整合-一致で通過 | manifestScreenCountが正しいtransitionフィクスチャがある | validate-page-data.shで検証する | PASSする | validate-page-data.shのself-testケース(e)「manifestScreenCountが正しいtransitionフィクスチャがPASSする」 |
| raw-ext-page-data-hash整合 | rawとraw由来extと画面遷移page-dataの3資産が整合している | check-screen-transition-manifest-alignment.shを実行する | 終了コード0で通過する | check-screen-transition-manifest-alignment.shのself-testケース「PASS: 正常系（raw/ext/page-data整合）で終了コード0」 |
| manifestContentHash-不一致検出 | page-dataのmanifestContentHashがraw/extと一致しない | check-screen-transition-manifest-alignment.shを実行する | 終了コード1で異常終了する | check-screen-transition-manifest-alignment.shのself-testケース「PASS: 異常系（manifestContentHash不一致）で終了コード1」 |
| 第三経路禁止-nodes/unresolved二択 | raw画面がnodes[]にもunresolved[]にも現れない可能性がある | Phase 2 Step 1を実行する | いずれか一方に必ず現れ、欠落を許さない | 手動 |
| sourceScanned-走査可否記録 | nodeのfrom元ファイルが実在し走査できるか不明 | Phase 2 Step 2を実行する | 走査できた画面はsourceScanned: trueに更新し、できない画面はfalseのまま残す | 手動 |
| ブラウザバック-遷移先空文字 | history.back()やrouter.back()のような遷移トリガーがある | triggerTypeを判定する | 「ブラウザバック」と判定しtoを空文字列にする | 手動 |
| html-生成手作業禁止 | page-data.jsonが確定している | Phase 4でHTMLを生成する | build-detail-page.sh経由の決定的処理のみで生成し手作業組み立てをしない | 手動 |

## 機械検証との対応

- 機械検証列「手動」は、検証状況（references/guide.html）へ確認結果を残す
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
