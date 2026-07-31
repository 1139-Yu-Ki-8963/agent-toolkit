# counting-code-lines テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 出力検証-全キー充足の正常系 | 必須キーがすべて揃ったcode-metrics.jsonがある | validate-code-metrics.shを実行する | 終了コード0で通過する | validate-code-metrics.shのself-testケース「ケース1 正常JSONで終了コード0」 |
| 出力検証-scanScope欠落の検出 | scanScopeキーが欠けたcode-metrics.jsonがある | validate-code-metrics.shを実行する | 終了コード1になり、欠落キーとしてscanScopeが列挙される | validate-code-metrics.shのself-testケース「ケース2 scanScope欠落で終了コード1・欠落キー列挙」 |
| 未分類率超過-警告なしの拒否 | unclassified.ratioが0.5を超え、warningがfalseのままである | validate-code-metrics.shを実行する | 終了コード1になる | validate-code-metrics.shのself-testケース「ケース3 ratio超過かつwarning falseで終了コード1」 |
| 未分類率超過-警告ありの許容 | unclassified.ratioが0.5を超え、warningがtrueである | validate-code-metrics.shを実行する | 終了コード0で通過する | validate-code-metrics.shのself-testケース「ケース4 ratio超過かつwarning trueで終了コード0」 |
| env未実行-clocなしフォールバック | env-config.jsonが存在しない対象ディレクトリがある | Phase 1とPhase 2を実行する | tools.clocをfalse扱いにし、wc -l方式で計測を進める | 手動 |
| テスト検出失敗-設定不在との区別 | 既定パターンでのテストファイル列挙が0件になる | Phase 5でテストランナー設定の実在を確認する | 設定もテスト用ディレクトリも実在しなければtestDetectionFailedをtrueにする | 手動 |
| 初回計測-previousのnull化 | code-metrics.jsonが出力先に存在しない初回計測である | Phase 6でWriteを実行する | previousをnullとし、デフォルト値を作らない | 手動 |
| 未分類ファイル-total不一致の許容 | FE/BEいずれのパターンにも一致しないファイルがある | Phase 4でFE/BE分離を実行する | totalにのみ計上し、totalとfe足すbeの合計が一致しない状態を許容する | 手動 |

## 機械検証との対応

- 機械検証が「手動」の行は、counting-code-lines-guide.html の検証状況へ手動確認を記録する
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
