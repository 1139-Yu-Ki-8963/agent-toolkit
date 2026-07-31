# generating-release-notes-for-reverse-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| gitリポジトリ不在-ハード停止 | target_repo_pathに.gitが無い | Phase 1 Step 1を実行する | git履歴を持たない旨を報告して停止する | 手動 |
| プレフィックス対応表-対応表外はその他扱い | コミット件名の先頭に対応表に無いプレフィックスがある | Phase 2 Step 2を実行する | flowをmaintenanceに分類する | 手動 |
| flow値-3値の部分集合検査 | 全コミットのflow分類が確定済み | Phase 2 Step 4のjq検査を実行する | 出力される値がfeatureかmaintenanceかdocsのいずれかのみになる | 手動 |
| releases-sourceRefを持たない | リリースエントリを組み立てる | page-data.jsonを構築する | releases[]にsourceRefを持たせずchangesとsummaryへ要約する | 手動 |
| html生成-埋め込みJSON一致 | release-notesのpage-data.jsonがある | build-detail-page.shで生成する | ファイル名対応（リリースノート.html）で出力し、埋め込みJSONが原本と完全一致する | build-detail-page.shのself-testケース「ケースd(release-notes)」 |
| html生成-未解決マーカーなし | 同上 | build-detail-page.shで生成する | page-data埋め込み範囲外に未解決の{{が残らない | build-detail-page.shのself-testケース「ケースd(release-notes)」 |
| portal未反映-未指定時は再実行しない | portal_output_dirが未指定 | Phase 4 Step 2を実行する | build-portal.shを実行せず省略を注記する | 手動 |
| 転記のみ-コミット内容の良否は判定しない | コミットメッセージの粒度が不揃い | Phase 2を実行する | 良否や粒度の妥当性には踏み込まず機械的な種別分類のみを行う | 手動 |

## 機械検証との対応

- 機械検証が「手動」の行は、generating-release-notes-for-reverse-docs-guide.html の検証状況へ手動確認を記録する
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
