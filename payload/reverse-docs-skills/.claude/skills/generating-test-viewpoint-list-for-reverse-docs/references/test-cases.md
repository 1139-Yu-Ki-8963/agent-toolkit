# generating-test-viewpoint-list-for-reverse-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 画面単位root上書き-decoy除外 | screenUnitRootがスクリーンで旧画面rootにも観点表がある | aggregate-test-viewpoints.shを実行する | スクリーン配下2種だけを集約する | aggregate-test-viewpoints.sh self-test「screenUnitRoot上書きだけを探索し既定rootのdecoyを除外」 |
| APIのみ-種別付き生成 | APIの2テスト設計書だけが存在する | 集約・検証・HTML生成を実行する | 2件を集約し、全行のsourceKindがapiでHTMLに「種別」列が表示される | aggregate-test-viewpoints.sh self-test「API外部契約・関数単位の由来章を重複キーなしで集約」および一時入力による結合確認 |
| 観点表横断集約-連結成功 | 単体・結合の2観点表が実在する | aggregate-test-viewpoints.shから検証・HTML・ポータルまで連結実行する | 2種のカテゴリと観点が可視表示されポータルへ反映される | aggregate-test-viewpoints.shのself-testケース「self-test PASS: テスト観点表の集約→検証→HTML→ポータル連結」 |
| manifest埋め込み範囲-非表示確認 | 観点データがpage-data埋め込みJSONに含まれる | 生成HTMLのscriptタグのみを抽出する | manifest内容が可視表示テーブルとは別に埋め込まれていることを区別できる | aggregate-test-viewpoints.shのself-testケース「self-test PASS: テスト観点表の集約→検証→HTML→ポータル連結」内のmanifest_only検査 |
| テスト設計書0件-生成停止 | output_dir配下に2種類のテスト設計書が1件も無い | Phase 1を実行する | HTMLを生成せずSTOPPEDを返す。集約スクリプト単体はfail-safeとしてunits:[]で正常終了する | Phase 1の前提条件確認、およびaggregate-test-viewpoints.shのself-testケース「self-test PASS: 0件のoutput_dirでも集約→検証→HTML生成が完走（空状態ページ生成）」 |
| screenKey-非正規化 | screenKeyが画面一覧側の命名と食い違う可能性がある | パスから screen- ディレクトリ名を抽出する | 正規化せずそのまま使い、乖離はbyScreenから目視確認する | 手動 |
| unit-kind分岐-汎用テンプレート経路 | build-unit-list.shへunit-kind test_viewpointを渡す | HTMLを生成する | screen種別専用委譲(build-screen-list.sh)ではなく汎用テンプレート経路で生成される | 手動 |
| html-生成手作業禁止 | manifestが確定している | Phase 4でHTMLを生成する | build-unit-list.sh経由の決定的処理のみで生成し手作業組み立てをしない | 手動 |
| 出力ファイル名-固定 | テスト観点表.htmlを生成する | Phase 4 Step 1を実行する | output_dir配下の一覧/テスト観点表/テスト観点表.htmlに固定して出力する | 手動 |
| 探索範囲-集約スクリプトと一致 | output_dir配下に対象アプリの旧来の設計書ディレクトリなど集約対象外のファイルが存在する | Phase 1 Step 1のfindコマンドを実行する | `<screenUnitRoot>/screen-*/詳細設計/`配下だけを走査し、範囲外のファイルを件数に含めないこと（aggregate-test-viewpoints.shの`find`と同じ`-mindepth 3 -maxdepth 3`・pathパターンで揃える） | 手動（aggregate-test-viewpoints.sh内`find`との一致を目視確認） |

## 機械検証との対応

- 機械検証列「手動」は、検証状況（references/guide.html）へ確認結果を残す
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
