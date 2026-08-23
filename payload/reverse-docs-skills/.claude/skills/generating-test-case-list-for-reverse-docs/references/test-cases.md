# generating-test-case-list-for-reverse-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 画面単位root上書き-decoy除外 | screenUnitRootがスクリーンで旧画面rootにも仕様書がある | aggregate-test-cases.shを実行する | スクリーン配下3種だけを集約する | aggregate-test-cases.sh self-test「screenUnitRoot上書きだけを探索し既定rootのdecoyを除外」 |
| APIのみ-種別付き生成 | APIの2テスト設計書だけが存在する | 集約・検証・HTML生成を実行する | 2件を集約し、全行のsourceKindがapiでHTMLに「種別」列が表示される | aggregate-test-cases.sh self-test「API外部契約・関数単位の二文書を重複キーなしで集約」および一時入力による結合確認 |
| 全種別テスト設計書0件-ハード停止 | 全設計種別の2テスト設計書と画面の操作シナリオ仕様書がいずれも0件 | Phase 1 Step 1を実行する | テスト設計書未作成の旨を報告して停止する | 手動 |
| 3種横断集約-連結成功 | 単体と結合と操作シナリオの3仕様書が実在する | aggregate-test-cases.shから検証とHTMLとポータルまで連結実行する | 3種のケースが横断集約されHTMLとポータルへ反映される | aggregate-test-cases.shのself-testケース「self-test PASS: テストケースの集約→検証→HTML→ポータル連結（単体/結合/操作シナリオ）」 |
| 結合-操作手順の転記 | 結合テスト仕様書に操作手順列がある | aggregate-test-cases.shで集約する | stepsに操作手順の値が転記される | aggregate-test-cases.shのself-testケース「self-test PASS: テストケースの集約→検証→HTML→ポータル連結」内のsteps一致検証 |
| 単体-steps空文字 | 単体テスト仕様書には操作手順列がない | aggregate-test-cases.shで集約する | 単体ケースのstepsは空文字列になる | 手動 |
| 操作シナリオ-シナリオ名突合 | シナリオ一覧表と`###`節の期待結果段落がある | aggregate-test-cases.shで集約する | シナリオ名で突合し1件のケースへ合成する | aggregate-test-cases.shのself-testケース「self-test PASS: テストケースの集約→検証→HTML→ポータル連結」内のexpected一致検証 |
| 確定行0件種別-キー保持 | 仕様書は実在するが操作シナリオの確定行が0件 | aggregate-test-cases.shで集約し検証する | scannedByTestTypeで区別しつつキーを脱落させず0件を記録する | aggregate-test-cases.shのself-testケース「self-test PASS: 仕様書実在・確定行0件種別のキー保持（scannedByTestTypeで区別）」 |
| タブ切替なし-単一テーブル | 単体と結合と操作シナリオが混在するケース一覧がある | build-unit-list.shでHTMLを生成する | タブ構成を持たず単一テーブルで種別列とテスト種別列により区別する | 手動 |
| html-生成手作業禁止 | manifestが確定している | Phase 4でHTMLを生成する | build-unit-list.sh経由の決定的処理のみで生成し手作業組み立てをしない | 手動 |
| 観点網羅対象外-出力範囲の限定 | 観点表側の観点網羅状況を確認したい場面がある | 本スキルの出力を確認する | 観点網羅は本スキルの出力に含まず、テスト観点表一覧を別途参照する必要がある | 手動 |

## 機械検証との対応

- 機械検証列「手動」は、検証状況（references/guide.html）へ確認結果を残す
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
