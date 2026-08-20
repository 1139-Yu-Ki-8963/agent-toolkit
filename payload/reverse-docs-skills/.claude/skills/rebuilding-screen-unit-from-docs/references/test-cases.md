# rebuilding-screen-unit-from-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| カンニング防止層1-白紙化 | Phase 2で対象ファイルをgit rmする | Phase 5まで原本参照コミットのReadを試みる | 削除直前のHEADのみ記録しPhase5まで内容を読まない | 手動 |
| カンニング防止層2-隔離委任 | Phase 4でworker-sonnetへ委任する | promptの内容を確認する | 元コードのパス・内容を一切含めない | 手動 |
| 観点網羅ゲート-全キー言及済み | 観点表の全キーがテストコードに言及済みである | check-viewpoint-coverage.shを実行する | exit0になる | check-viewpoint-coverage.shのself-testケース「PASS: 全キー言及済みでexit0」 |
| 観点網羅ゲート-未言及キーの検出 | 観点表のキーが1件テストコードに未言及である | check-viewpoint-coverage.shを実行する | exit1になる | check-viewpoint-coverage.shのself-testケース「PASS: 未言及キー検出時にexit1」 |
| 観点網羅ゲート-観点表不在 | 観点表ファイルが存在しない | check-viewpoint-coverage.shを実行する | exit1になる | check-viewpoint-coverage.shのself-testケース「PASS: 観点表ファイル不在時にexit1」 |
| 契約突合-宣言集合の完全一致 | 生成物と原本のexport名等6カテゴリを抽出する | measure-file-diff.shを実行する | contract_matchがYESまたはNOで返る | 手動 |
| スタイル正規化diff-書式差の吸収 | クォート種別や末尾カンマだけが異なる生成物がある | measure-file-diff.shを実行する | 実質diffが20行超でも正規化diffが20行以下ならPASSにできる | measure-file-diff.shのself-testケース「ケース2(スタイル差のみ): PASS」 |
| 元コード全緑証明-原本redの黙認禁止 | 生成物greenかつ原本redの結果になる | Phase 5の判定に組み込む | iterativeは修正して再投入しsingle-passは差分として渡す | 手動 |
| 8計測の省略禁止 | import diffだけが0件になる | Phase 5の8計測を実行する | 8計測すべてを出力し1つでも省略しない | 手動 |
| 内部整合違反-早期離脱 | 監査で機能一覧と観点表のキーが両方向一致しない | Phase 2の内部整合性確認を行う | 白紙化・実装を経ずPhase 7へ直行する | 手動 |
| 起動不可-status=差し戻しとの区別 | target_repo_path等の必須引数が欠ける | Phase 1を実行する | status=差し戻しは返さずSkill呼び出し失敗として即時報告する | 手動 |
| テスト定義保存-既存テスト上書き禁止 | target_repo_path内に同名の既存テストがある | Phase 7でテストコードを納品物化する | 上書きせず既存テストの扱いをhintに記録する | 手動 |
| 画面ディレクトリ-screenUnitRoot解決 | output-layoutでscreenUnitRoot=スクリーン | 管理者が起動引数を組み立てる | スクリーン配下の画面ディレクトリを渡し旧画面rootを参照しない | 手動 |

## 機械検証との対応

- 機械検証が「手動」の行は、guide.html の検証状況へ手動確認を記録する
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
