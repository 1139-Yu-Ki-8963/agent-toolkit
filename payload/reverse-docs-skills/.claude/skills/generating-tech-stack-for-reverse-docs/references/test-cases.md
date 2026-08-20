# generating-tech-stack-for-reverse-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 調査書不在-ハード停止 | アーキテクチャ調査書.mdが不在 | Phase 1 Step 1を実行する | 先行実行を案内して停止する | 手動 |
| 実在しない群-突合対象外 | 調査書§2に「実在しない（理由: …）」の行がある | Phase 2 Step 1で2群に分類する | 定義ファイルとの突合対象外とする | 手動 |
| 乖離検出-page-data生成せず停止 | 実在する群で調査書記載値と定義ファイル実測値が食い違う | Phase 2 Step 3を実行する | page-dataを生成せず乖離内容を報告して停止する | 手動 |
| absentRows-根拠パス保持 | 実在しないと判定された項目がabsentRows[]にある | build-detail-page.shでtechstack.htmlを生成する | 項目名と根拠パスがpage-data埋め込み範囲外の静的HTMLに現れる | build-detail-page.shのself-testケース「ケースj(techstack-absent): absentRows[]の項目名・根拠パスがpage-data埋め込み範囲外の静的HTMLに現れる」 |
| sourceRef-実パス限定 | rows[]のsourceRefを組み立てる | Phase 2 Step 4を実行する | 文書参照形式ではなく突合に使った定義ファイルの実パスを使う | 手動 |
| 整合検証-sourceRef実在確認 | page-data.jsonのrows[].sourceRefが対象リポジトリのファイルを指す | validate-page-data.shを--target-repo付きで実行する | パス実在と行番号範囲を検査しPASSする | 手動 |
| html-生成手作業禁止 | page-data.jsonが確定している | Phase 4でHTMLを生成する | build-detail-page.sh経由の決定的処理のみで生成し手作業組み立てをしない | 手動 |
| 出力先-種別専用フォルダなし | 技術スタック.htmlを生成する | Phase 4 Step 1を実行する | output_dir/project-portal/foundation直下に固定出力名で生成する | 手動 |
| 永続入力-ポータル再生成 | 検証済みpage-dataをmanifestsRoot/detail-pagesへ保存済み | build-portal.shを実行する | techstack-page-data.jsonから技術スタック.htmlを再生成する | build-portal.shのself-testケース48a |

## 機械検証との対応

- 機械検証列「手動」は、検証状況（references/guide.html）へ確認結果を残す
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
