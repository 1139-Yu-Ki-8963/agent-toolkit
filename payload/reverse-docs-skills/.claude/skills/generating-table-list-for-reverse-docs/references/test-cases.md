# generating-table-list-for-reverse-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 検出0件-ハード停止 | カスタム抽出でテーブルが1件も見つからない | Phase 2 Step 3を実行する | 捏造せず、ユーザーに報告して停止する | 手動 |
| manifest-陽性検証-非screen経路 | unitKind:apiで代表される非screen経路の正当なmanifestがある | validate-manifest.shを実行する | 全11項目がPASSする | validate-manifest.shのself-testケース「api陽性: unitKind=apiで全11項目PASS」（table/batch/report/externalも同じ非screen経路を共有する） |
| metadata-DDLコメント除外 | コメントまたは文字列内にCREATE TABLEを含むDDLがある | extract-table-metadata.shを実行する | 行コメントとブロックコメントと引用内の記述を無視し、実DDLのみ抽出する | extract-table-metadata.shのself-testケース「DDLコメント除外: 行・ブロックコメント、単一引用、ドル引用を無視して実DDLのみ抽出」 |
| metadata-終端判定の方言対応 | ENGINE指定等を挟み文末記号が数行後にある方言のDDLがある | extract-table-metadata.shを実行する | 後続の無関係な定義を取り込まず、実数どおりのcolumnCountになる | extract-table-metadata.shのself-testケース「1-134 終端判定: ENGINE=/CHARSET=等の記憶域指定を挟み文末記号が数行後にある方言でも実数どおりcolumnCount=7」 |
| metadata-行内コメント除去 | --や#による行内コメントを含む列定義がある | extract-table-metadata.shを実行する | コメント文言をmainColumnsへ連結せず、columnCountが一致する | extract-table-metadata.shのself-testケース「1-134 行内コメント除去: --・#いずれの行内コメントもmainColumnsへ連結されずcolumnCount=3」 |
| metadata-外部キー解決 | 他テーブルを参照する外部キー制約を持つテーブルがある | extract-table-metadata.shを実行する | foreignKeysが参照先のunitKeyへ解決される | extract-table-metadata.shのself-testケース「posts: columnCount=6・foreignKeys が unitKey(users-master) へ解決・mainColumns 先頭5列」 |
| metadata-同一DDLの複数表抽出 | 1つのDDLファイルに3表の定義が含まれる | extract-table-metadata.shをpipefail下で実行する | SIGPIPEを含む異常終了なく完走する | extract-table-metadata.shのself-testケース「1-16: 同一DDLの3表抽出がpipefail下で完走」 |
| metadata-大規模列集合の処理 | 900列を持つ大規模テーブル定義がある | extract-table-metadata.shを実行する | ARG_MAX超の大規模パッチ集合を全読込し、正しく適用する | extract-table-metadata.shのself-testケース「stress: 900列を全読込し、ARG_MAX超の大規模パッチ集合を適用」 |
| html-属性注入防止 | 引用符を含むunitKeyがある | build-unit-list.shで生成する | 属性値として安全にエスケープし、埋め込みJSONは原本と一致する | build-unit-list.shのself-testケース「ケースb: 引用符を含むunitKeyを属性値として安全にエスケープし、埋め込みJSONも原本と完全一致」 |
| migration-alter単独計上の禁止 | createとalterが積み重なった同一テーブルのマイグレーションがある | Phase 2でテーブル単位に集約する | alterだけを独立テーブルとして数えず、関連マイグレーションをfilesへ列挙する | 手動 |

## 機械検証との対応

- 機械検証が「手動」の行は、generating-table-list-for-reverse-docs-guide.html の検証状況へ手動確認を記録する
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
