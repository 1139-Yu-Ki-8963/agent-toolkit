# generating-design-system-for-reverse-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| DESIGN.md不在-ハード停止 | output_dir配下にDESIGN.mdが無い | Phase 1を実行する | 生成せず不在を報告して停止する | 手動 |
| トークン抽出-validate通過 | frontmatterありのDESIGN.mdがある | extract-design-tokens-from-designmd.shを実行する | 出力JSONがvalidate-page-data.shを全項目PASSで通過する | extract-design-tokens-from-designmd.shのself-testケース「ケースa」 |
| トークン抽出-summary型 | 同上 | 抽出を実行する | summaryが配列として出力される | extract-design-tokens-from-designmd.shのself-testケース「ケースb」 |
| トークン抽出-表形式からの件数一致 | frontmatterが無く本文表のみのDESIGN.mdがある | 抽出を実行する | 記載件数どおりに抽出される（colors3件、typography2件、spacing1件） | extract-design-tokens-from-designmd.shのself-testケース「ケースc」 |
| 生成HTML-実行時例外なし | 抽出済みpage-data.jsonがある | 生成HTMLをNode DOMスタブ上で実行する | 実行時例外が発生しない | extract-design-tokens-from-designmd.shのself-testケース「ケースd」 |
| フォールバック時-components固定空 | frontmatterが存在しない | 抽出を実行する | componentsは常に空配列になる（フォールバック対象外） | 手動 |
| role補完-本文表との突合 | frontmatterにroleが無く該当行が本文表にも無い | 抽出を実行する | roleは空文字になる（失敗ではない） | 手動 |
| rounded-spacingへの合流 | frontmatterにrounded:がある | 抽出を実行する | roundedはspacingカテゴリの一員として出力JSONに現れる | 手動 |
| html生成-埋め込みJSON一致 | design-systemのpage-data.jsonがある | build-detail-page.shで生成する | ファイル名対応（デザインシステム.html）で出力し、埋め込みJSONが原本と完全一致する | build-detail-page.shのself-testケース「ケースd(design-system)」 |

## 機械検証との対応

- 機械検証が「手動」の行は、generating-design-system-for-reverse-docs-guide.html の検証状況へ手動確認を記録する
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
