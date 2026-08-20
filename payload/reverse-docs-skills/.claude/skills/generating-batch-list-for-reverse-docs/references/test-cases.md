# generating-batch-list-for-reverse-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 検出0件-ハード停止 | カスタム抽出でジョブが1件も見つからない | Phase 2の検出を実行する | 捏造せず、ユーザーに報告して停止する | 手動 |
| manifest-陽性検証-非screen経路 | unitKind:apiで代表される非screen経路の正当なmanifestがある | validate-manifest.shを実行する | 全11項目がPASSする | validate-manifest.shのself-testケース「api陽性: unitKind=apiで全11項目PASS」（table/batch/report/externalも同じ非screen経路を共有する） |
| metadata-cron式の平易表記 | 毎日パターンと毎月パターンのcron式を持つジョブがある | extract-batch-metadata.shを実行する | scheduleフィールドに平易な表記が生成される | extract-batch-metadata.shのself-testケース「schedule: 毎日パターンのcron式と平易表記」と「schedule: 毎月パターンのcron式と平易表記」 |
| metadata-対象テーブルのfail-safe | テーブル識別子へのヒットが無いジョブがある | extract-batch-metadata.shを実行する | targetTablesフィールドを付けない | extract-batch-metadata.shのself-testケース「targetTables: ヒット無しユニットにはフィールドを付けない(fail-safe)」 |
| metadata-後続ジョブの検出 | 呼び出し記述で他ジョブを参照するジョブがある | extract-batch-metadata.shを実行する | downstreamJobsに後続ジョブのunitKeyが列挙される | extract-batch-metadata.shのself-testケース「downstreamJobs: 呼び出し記述ヒットで後続ジョブのunitKey配列」 |
| metadata-定義のみジョブの診断 | crontabに登録済みだが実装ファイルが無いジョブがある | extract-batch-metadata.shを実行する | definitionWithoutImplementation診断のcountとtotalが正しく集計される | extract-batch-metadata.shのself-testケース「definitionWithoutImplementation診断: count=1(nonexistent_jobのみ実装なし)」と「definitionWithoutImplementation診断: total=3(crontab全登録エントリ数)」 |
| metadata-大規模ユニット処理 | 500ユニット規模のジョブ定義集合がある | extract-batch-metadata.shを実行する | 抽出コマンドが終了コード0で完了する | extract-batch-metadata.shのself-testケース「1-127-scale: 500ユニット規模でも抽出コマンドが終了コード0で完了」 |
| html-属性注入防止 | 引用符を含むunitKeyがある | build-unit-list.shで生成する | 属性値として安全にエスケープし、埋め込みJSONは原本と一致する | build-unit-list.shのself-testケース「ケースb: 引用符を含むunitKeyを属性値として安全にエスケープし、埋め込みJSONも原本と完全一致」 |
| 動的ジョブ名-低confidence可視化 | 変数結合で動的に構築されるジョブ名やcron式がある | Phase 2の抽出で確定できないと判断する | confidence:lowまたはunresolvedとして可視化し、実在するかのように断定しない | 手動 |

## 機械検証との対応

- 機械検証が「手動」の行は、guide.html の検証状況へ手動確認を記録する
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
