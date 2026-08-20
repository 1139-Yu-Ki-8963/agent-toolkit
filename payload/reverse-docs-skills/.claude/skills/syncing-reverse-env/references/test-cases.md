# syncing-reverse-env テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 共有オリジナル-4条件充足で共有 | system・source_ref・起動プロファイル・リクエスト独立の4条件を満たす | Phase 2で環境確保を行う | sha8付きworktree名で共有オリジナルを使い回す | 手動 |
| 共有オリジナル-条件外はper-scope | 4条件のいずれかが外れる | Phase 2で環境確保を行う | per-scopeへ自動degradeする | 手動 |
| 読み取り専用契約-使用中は復元しない | 共有オリジナルの参照カウントが0を超える | dirtyを検出する | 再チェックアウトせずERRORとする | 手動 |
| teardown-明示依頼が無ければ実行しない | user-approvedが渡されない | mode=teardownを実行する | 削除せずstatus=ERRORで差し戻す | 手動 |
| ポート正規化-数字違いだけは許容しない | オリジナルとリバースの値が計算式どおりでない | Phase 3で静的比較を行う | 実差分として扱う | 手動 |
| sync-基準タグ乖離の付記 | タグ記録のsource_refと現在pinしたSHAが異なる | mode=syncを実行する | 再検証が必要としてbaseline_tagへ付記する | 手動 |
| 動的比較判定-未到達はPASSにしない | 両環境が同一スピナーで停止している | Phase 6で収束判定を行う | PASSにせずFAILまたはDESIGN-INCOMPLETEとする | 手動 |
| L5評価-operations不在は対象外 | scenarioがoperationsを持たない | 収束判定を行う | L5を評価対象から外し従来条件で判定する | 手動 |
| ドキュメント整合-キー不整合検出 | guide.htmlとSKILL.mdでキー名が食い違う | audit-doc-consistency.shを実行する | 不整合をFAILとして検出する | audit-doc-consistency.shのself-testケース「PASS: 不整合フィクスチャでexit1」 |
| ドキュメント整合-対象ファイル不在 | 監査対象ファイルが1件でも不在 | audit-doc-consistency.shを実行する | exit1で終了する | audit-doc-consistency.shのself-testケース「PASS: 対象ファイル不在時にexit1」 |
| 環境名直書き-プレースホルダ以外禁止 | スクリプトにoriginal-code-の直後へ具体値を書く | audit-doc-consistency.shを実行する | 環境名のハードコードとしてFAILする | 手動 |
| worktree操作-親ディレクトリ単位で排他 | git worktree add/removeを実行する | 排他ロックの取得を確認する | .reverse-worktree-ops.lockを120秒待機で保持する | 手動 |

## 機械検証との対応

- 機械検証が「手動」の行は、guide.html の検証状況へ手動確認を記録する
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
