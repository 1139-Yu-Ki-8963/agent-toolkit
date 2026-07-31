# generating-api-list-for-reverse-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 検出0件-ハード停止 | カスタム抽出でエンドポイントが1件も見つからない | Phase 2 Step 2を実行する | 捏造せず、ユーザーに報告して停止する | 手動 |
| manifest-陽性検証-unitKind自動判定 | unitKind:apiを持つ正当なmanifestがある | validate-manifest.shを実行する | 全11項目がPASSし、unitKindがapiと自動判定される | validate-manifest.shのself-testケース「api陽性: unitKind=apiで全11項目PASS」と「unitKind自動判定」 |
| manifest-unitKey重複拒否 | 2つのunitが同じunitKeyを持つ | validate-manifest.shを実行する | 重複したunitKeyでFAILする | validate-manifest.shのself-testケース「unitKey-一意性陰性: unitKeyの重複でFAIL」 |
| manifest-sourceFile不在のfix降格 | sourceFileが実在しないunitがある | validate-manifest.shを--fix付きで実行する | unresolvedへ降格し、PASSする | validate-manifest.shのself-testケース「api --fix: sourceFile不在エントリをunresolvedへ降格しPASS」 |
| manifest-拡張フィールド型検査 | authRequiredが文字列でcallersが数値配列のunitがある | validate-manifest.shを実行する | 型違反としてFAILする | validate-manifest.shのself-testケース「拡張フィールド陰性: 型違反(authRequired文字列/callers数値配列)なのにPASSした」の否定確認 |
| manifest-統合候補の分岐判定 | 引数分岐のない同一sourceFileを参照する2つのunitがある | validate-manifest.shを実行する | 統合候補として列挙し、引数分岐ペアは列挙しない | validate-manifest.shのself-testケース「実装参照-統合候補: 分岐なしペアのみ列挙し引数分岐ペアは列挙しない」 |
| manifest-置換文字混入検査 | unitNameGuessに置換文字U+FFFDを含むunitがある | validate-manifest.shを実行する | 混入件数付きでFAILする | validate-manifest.shのself-testケース「置換文字-非混入陰性: 置換文字混入でFAILし件数が列挙される」 |
| html-unitKind不一致の拒否 | --unit-kind apiとmanifest.unitKind:tableが食い違う | build-unit-list.shを実行する | 不一致を検出し、生成しない | build-unit-list.shのself-testケース「入力契約: --unit-kind不一致とgeneratedAt:nullをscreen委譲前を含めて拒否」 |
| html-属性注入防止 | 引用符を含むunitKeyがある | build-unit-list.shで生成する | 属性値として安全にエスケープし、埋め込みJSONは原本と一致する | build-unit-list.shのself-testケース「ケースb: 引用符を含むunitKeyを属性値として安全にエスケープし、埋め込みJSONも原本と完全一致」 |
| metadata-method抽出 | GET /api/usersのような識別子を持つunitがある | extract-api-metadata.shを実行する | methodフィールドにGETが抽出される | extract-api-metadata.shのself-testケース「method: GET /api/users から GET を抽出」 |
| metadata-認証根拠なしでfail-safe | 認証判定の根拠となるコードが無いunitがある | extract-api-metadata.shを実行する | authRequired等の根拠が無いフィールドを付けない | extract-api-metadata.shのself-testケース「fail-safe: 根拠の無い authRequired/callers/targetTables/ioSummary は欠落」 |

## 機械検証との対応

- 機械検証列が「手動」の行は、検証状況（references/generating-api-list-for-reverse-docs-guide.html のメタテーブル）へ手動確認の記録を残す
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
