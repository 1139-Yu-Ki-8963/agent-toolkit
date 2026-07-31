# generating-report-list-for-reverse-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 検出0件-ハード停止 | カスタム抽出で帳票が1件も見つからない | Phase 2の検出を実行する | 捏造せず、ユーザーに報告して停止する | 手動 |
| manifest-陽性検証-非screen経路 | unitKind:apiで代表される非screen経路の正当なmanifestがある | validate-manifest.shを実行する | 全11項目がPASSする | validate-manifest.shのself-testケース「api陽性: unitKind=apiで全11項目PASS」（table/batch/report/externalも同じ非screen経路を共有する） |
| metadata-出力形式の判定 | reportlabへのヒットとto_csvへのヒットを持つ帳票がある | extract-report-metadata.shを実行する | formatフィールドにPDFとCSVがそれぞれ判定される | extract-report-metadata.shのself-testケース「format: reportlabヒットでPDF」と「format: to_csvヒットでCSV」 |
| metadata-複数形式ヒットのfail-safe | 複数の出力形式手がかりが同時にヒットする帳票がある | extract-report-metadata.shを実行する | formatフィールドを付けない | extract-report-metadata.shのself-testケース「format: 複数形式ヒットではフィールドを付けない(fail-safe)」 |
| metadata-jobsからのimportによるバッチ判定 | jobs配下の外にあるがjobsのバッチからimportされる帳票がある | extract-report-metadata.shを実行する | triggerフィールドがバッチと判定される | extract-report-metadata.shのself-testケース「trigger: jobs配下外でもjobsのバッチからimportされる帳票はバッチ」 |
| metadata-既存フィールド不変 | operationClass等の抽出前のmanifestがある | extract-report-metadata.shを実行し追加フィールドを除去する | 除去後は入力manifestと完全一致する | extract-report-metadata.shのself-testケース「既存フィールド不変: 追加フィールド除去後は入力マニフェストと完全一致」 |
| html-属性注入防止 | 引用符を含むunitKeyがある | build-unit-list.shで生成する | 属性値として安全にエスケープし、埋め込みJSONは原本と一致する | build-unit-list.shのself-testケース「ケースb: 引用符を含むunitKeyを属性値として安全にエスケープし、埋め込みJSONも原本と完全一致」 |
| kind区分-3値の運用 | template由来とgenerator由来と主ファイル未解決の帳票が混在する | Phase 2で各帳票にkindを付与する | kindがtemplateとgeneratorとunresolvedの3値のいずれかに収まる | 手動 |

## 機械検証との対応

- 機械検証が「手動」の行は、generating-report-list-for-reverse-docs-guide.html の検証状況へ手動確認を記録する
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
