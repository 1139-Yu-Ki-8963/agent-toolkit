# generating-feature-list-for-reverse-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| unresolved残存-status DONE扱い | 一部のunitがunresolvedのまま残ったmanifestがある | Phase 6で完了判定を行う | 既存6種の要手動確認と同じ扱いとし、status=DONEのまま完了する | 手動 |
| operationClass-登録分類 | create-userのようなキーワードを含むunitがある | extract-feature-metadata.shを実行する | operationClassが登録と判定される | extract-feature-metadata.shのself-testケース「登録: create-userがキーワード一致で分類される」 |
| operationClass-照会分類 | list-ordersのようなキーワードを含むunitがある | extract-feature-metadata.shを実行する | operationClassが照会と判定される | extract-feature-metadata.shのself-testケース「照会: list-ordersがキーワード一致で分類される」 |
| operationClass-その他フォールバック | ping-endpointのように該当キーワードが無いunitがある | extract-feature-metadata.shを実行する | operationClassがその他に分類される | extract-feature-metadata.shのself-testケース「その他: 該当キーワードなしのpingが「その他」に分類される」 |
| operationClass-空関連の警告診断 | relatedApisとrelatedTablesが全件空の6機能がある | extract-feature-metadata.shを実行する | emptyRelation診断のcountとtotalが6でwarningがtrueになる | extract-feature-metadata.shのself-testケース「emptyRelation診断: count=6(全featureがrelatedApis/relatedTables空)」と「emptyRelation診断: 全件空でwarning: true」 |
| 直接データアクセス-relatedTablesの紐付け | 画面が生SQLを直接埋め込んで持つ実装がある | extract-feature-metadata.shを実行する | relatedTablesが該当テーブルのunitKeyへ紐付く | extract-feature-metadata.shのself-testケース「直接データアクセス経路: 画面が直接持つ生SQLからrelatedTablesが紐付く」 |
| html-識別子内バックスラッシュでも埋め込みJSON一致 | identifierにバックスラッシュを含むmanifestがある | build-feature-list.shで機能一覧htmlを生成する | 埋め込みJSONが原本と完全一致する | build-feature-list.shのself-testケース「ケースa: バックスラッシュ(\d+)を含むidentifierでも埋め込みJSONが原本と完全一致」 |
| html-危険文字を含むunitNameGuessの安全化 | 山括弧とマーカー文字列が衝突するunitNameGuessがある | build-feature-list.shで生成する | application/json埋め込みが安全化され、埋め込みJSONは原本と一致する | build-feature-list.shのself-testケース「ケースb: 危険文字+実マーカー文字列衝突を含むunitNameGuessでも埋め込みJSONが原本と完全一致」 |
| 大分類境界-ルートprefix単独判定 | ナビメニューの区分がルートprefixと食い違う機能がある | Phase 1で大分類の境界を確定する | ルートprefixのみで境界を引き、ナビは命名の参考にとどめる | 手動 |
| related参照整合-未検査の自前検査 | related系フィールドが実在しない参照を含むmanifestがある | Phase 5 Step 2でjqによる自前検査を実行する | 不在参照を検出し、成果物への混入を防ぐ | 手動 |

## 機械検証との対応

- 機械検証が「手動」の行は、generating-feature-list-for-reverse-docs-guide.html の検証状況へ手動確認を記録する
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
