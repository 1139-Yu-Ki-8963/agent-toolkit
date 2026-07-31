# generating-icon-catalog-for-reverse-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| アイコン参照0件-ハード停止 | Material Iconsも SVG importもReact iconsも存在しない | Phase 1を実行する | 0件を報告して停止する | 手動 |
| 抽出-validate通過 | アイコン参照があるフィクスチャがある | extract-icon-usage.shを実行する | 出力JSONがvalidate-page-data.shを全項目PASSで通過する | extract-icon-usage.shのself-testケース「ケースa」 |
| 抽出-summary型 | 同上 | extract-icon-usage.shを実行する | summaryが配列として出力される | extract-icon-usage.shのself-testケース「ケースb」 |
| 生成HTML-実行時例外なし | 抽出済みpage-data.jsonがある | 生成HTMLをNode DOMスタブ上で実行する | 実行時例外が発生しない | extract-icon-usage.shのself-testケース「ケースc」 |
| 抽出対象-3パターン固定 | CSSのbackground-imageなど独自参照方式がある | 抽出を実行する | 対象外として扱われ0件でも異常ではない | 手動 |
| grep0件-fail-safe | Phase 1を通過したがPhase 2で該当が0件 | extract-icon-usage.shを実行する | エラーにせずicons:[]で正常終了する | 手動 |
| html生成-埋め込みJSON一致 | icon-catalogのpage-data.jsonがある | build-detail-page.shで生成する | ファイル名対応（アイコンカタログ.html）で出力し、埋め込みJSONが原本と完全一致する | build-detail-page.shのself-testケース「ケースd(icon-catalog)」 |
| 転記のみ-重複の是非は判定しない | アイコン使用が重複している | 抽出を実行する | 重複の是非は判定せず出現事実のみ転記する | 手動 |

## 機械検証との対応

- 機械検証が「手動」の行は、generating-icon-catalog-for-reverse-docs-guide.html の検証状況へ手動確認を記録する
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
