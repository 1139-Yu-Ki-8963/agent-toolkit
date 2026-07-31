# generating-component-inventory-for-reverse-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 検出0件-ハード停止 | 対象リポジトリに.tsx/.jsx/.vueファイルが0件 | Phase 1の存在確認を実行する | 捏造せず、コンポーネントファイル不在を報告して停止する | 手動 |
| 抽出-被参照カウント | Fooをexportするファイルと、それをimportするページがある | extract-component-inventory.shを実行する | totalComponentsが2、Foo importCountが1になる | extract-component-inventory.shのself-testケース「正常系（component 2件）で終了コード0」 |
| 抽出-source-dir不在 | source-dirが実在しない | extract-component-inventory.shを実行する | 終了コード1で失敗する | extract-component-inventory.shのself-testケース「異常系（source-dir不在）で終了コード1」 |
| 抽出-0件正常終了 | 対象ディレクトリに対象拡張子ファイルが1件もない | extract-component-inventory.shを実行する | エラーにせずcomponents:[]で正常終了する | 手動 |
| hasProps-文字列一致のみ | ファイル内にProps文字列を含む行がある | 抽出を実行する | 型として使われているかは検証せずhasProps=trueになる | 手動 |
| export名-判定順序 | いずれのexportパターンにも一致しないファイルがある | 抽出を実行する | ファイル名（拡張子抜き）がexport名として採用される | 手動 |
| html生成-埋め込みJSON一致 | component-inventoryのpage-data.jsonがある | build-detail-page.shで生成する | ファイル名対応（コンポーネント棚卸し.html）で出力し、埋め込みJSONが原本と完全一致する | build-detail-page.shのself-testケース「ケースd(component-inventory)」 |
| html生成-未解決マーカーなし | 同上 | build-detail-page.shで生成する | page-data埋め込み範囲外に未解決の{{が残らない | build-detail-page.shのself-testケース「ケースd(component-inventory)」 |
| 分類-ディレクトリパス由来のみ | components/pages/layouts以外のパスにあるファイルがある | 抽出を実行する | 分類はotherになり、責務を推定した独自分類は行わない | 手動 |

## 機械検証との対応

- 機械検証が「手動」の行は、generating-component-inventory-for-reverse-docs-guide.html の検証状況へ手動確認を記録する
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
