# generating-reverse-common-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 永続共通文書欠落-検出 | 永続する共通6文書のいずれかが欠落している | check-common-docs.shを実行する | 検査1がFAILしexit 1になる | check-common-docs.shのself-testケース「[PASS] 検査1: ファイル欠落でexit 1」 |
| 非永続文書欠落-許可 | サンプル記録が存在しない（規約定義は本スキルの対象外） | check-common-docs.shを実行する | 永続する共通6文書が正常ならexit 0になる | check-common-docs.shのself-testケース「[PASS] Phase A: 規約4文書・サンプル記録なしで永続6文書がexit 0」 |
| 記載パス未実在-検出 | backtick表記の相対パスが対象リポジトリに実在しない | check-common-docs.shを実行する | 検査3がFAILしexit 1になる | check-common-docs.shのself-testケース「[PASS] 検査3: 未実在パスでexit 1」 |
| テンプレ残存-地の文言及は誤検出しない | TODO/TBDという語自体を地の文で言及している | check-common-docs.shを実行する | プレースホルダとして誤検出せず通過する | check-common-docs.shのself-testケース「[PASS] 検査4(1-153): TODO/TBDの地の文言及は誤検出しない」 |
| sample記録-ゲート対象外 | sample記録にテンプレ残存がある | check-common-docs.shを実行する | 永続6文書が正常ならsample記録の内容に依存せずexit 0 | self-testの「[PASS] Phase A: sample記録の内容をゲート対象外として扱う」 |
| メッセージ規模-宣言不一致検出 | メッセージ定義書の宣言件数と実測件数が一致しない | check-common-docs.shを実行する | 検査6がFAILしexit 1になる | check-common-docs.shのself-testケース「[PASS] 検査6: 宣言件数と実測件数の不一致でexit 1」 |
| 必須節見出し-合格 | 定義上の必須節がMarkdown見出しとしてすべて存在する | check-common-docs.shを実行する | 検査7がPASSしexit 0になる | check-common-docs.shのself-testケース「[PASS] 検査7: 必須節をMarkdown見出しとして持つ文書でexit 0」 |
| 必須語本文のみ-不合格 | 定義上の必須語が本文の1行にだけありMarkdown見出しとして存在しない | check-common-docs.shを実行する | 検査7がFAILしexit 1になる | check-common-docs.shのself-testケース「[PASS] 検査7: 必須語が本文にだけある文書でexit 1」 |
| コードフェンス内見出し風-不合格 | 定義上の必須語を持つATX見出し風の行がコードフェンス内にだけ存在する | check-common-docs.shを実行する | 検査7がコード内の行を節として数えずFAILしexit 1になる | check-common-docs.shのself-testケース「[PASS] 検査7: コードフェンス内のATX見出し風の行でexit 1」 |
| 共通本文根拠分離-合格 | 共通6文書の本文に根拠・抽出元列と対象コードのfile:line表記がない | check-common-docs.shを実行する | 検査8がPASSしexit 0になる | check-common-docs.shのself-testケース「[PASS] 検査8: 根拠列とfile:line表記がない本文でexit 0」 |
| 共通本文根拠分離-検出 | 共通文書の表に根拠列または対象コードのfile:line表記がある | check-common-docs.shを実行する | 検査8がFAILしexit 1になる | check-common-docs.shのself-testケース「[PASS] 検査8: 根拠列またはfile:line表記でexit 1」 |
| 共通本文根拠分離-言語非依存 | 共通文書に`src/views/App.vue:2`と`日本語/処理.sql:1`がある | check-common-docs.shを実行する | 拡張子やASCII文字に依存せず検査8がFAILしexit 1になる | check-common-docs.shのself-testケース「[PASS] 検査8: .vueと日本語パス.sqlのfile:line注記でexit 1」 |
| 共通本文根拠分離-URL除外 | 共通文書に`https://example.com/docs/file.vue:1`がある | check-common-docs.shを実行する | URLをfile:line注記として誤検出せず検査8がexit 0になる | check-common-docs.shのself-testケース「[PASS] 検査8: URLはfile:line注記から除外」 |
| 横断根拠台帳-対象文書検出 | 台帳の対象文書が定義外または`commonRoot`配下に実在しない | check-common-docs.shを実行する | 検査9がFAILしexit 1になる | check-common-docs.shのself-testケース「[PASS] 検査9: 定義外・未実在の対象文書でexit 1」 |
| 横断根拠台帳-節項目検出 | 台帳の節・項目が対象文書本文に存在しない | check-common-docs.shを実行する | 検査9がFAILしexit 1になる | check-common-docs.shのself-testケース「[PASS] 検査9: 対象文書に存在しない節・項目でexit 1」 |
| 横断根拠台帳-文書網羅検出 | 適用対象の共通文書1件に台帳行がない | check-common-docs.shを実行する | 検査9がFAILしexit 1になる | check-common-docs.shのself-testケース「[PASS] 検査9: 適用対象1文書の台帳行欠落でexit 1」 |
| 横断根拠台帳-非適用文書行許可 | 定義済み文書が現在は非適用で、過去からの台帳行が残っている | check-common-docs.shを実行する | 既存行を許可し、被覆要求は現在の適用対象文書だけに課す | check-common-docs.shのself-testケース「[PASS] 定義駆動: 定義だけの変更で基盤設計書を対象なしに変更」 |
| 横断根拠台帳-4列限定 | 台帳のデータ行に5列目がある | check-common-docs.shを実行する | canonical 4列以外をfail-closedで扱い検査9がexit 1になる | check-common-docs.shのself-testケース「[PASS] 検査9: canonical 4列以外の台帳行でexit 1」 |
| 横断根拠台帳-配置宣言整合 | output-layoutとdeliverable-inventoryに台帳の配置・種別がある | check-common-docs.shを実行する | 検査10がPASSしexit 0になる | check-common-docs.shのself-testケース「[PASS] 検査10: output-layoutとinventoryの台帳宣言でexit 0」 |
| self-test一時領域-判定不能 | self-test開始時にmktempが一時領域へ書き込めない | check-common-docs.sh --self-testを実行する | stderrへ`[UNKNOWN]`と原因を出しexit 2になる | 環境依存のため規約準拠をコードレビューで確認 |
| サンプル外裏取り-規模実測限定 | サンプル外で定義本体を開いて裏取りする場面がある | Phase 3で採録する | 規模と件数とキー一覧の実測に限り開き、カタログ規模の推測表現は禁止する | 手動 |
| 層化サンプリング-必須サンプル先取り | アーキテクチャ調査書が特定ディレクトリを名指ししている | Phase 2で層化サンプリングを実行する | 均等配分に先立って必須サンプルとして先取りする | 手動 |
| append-部分ゲート禁止 | mode=appendで指摘文書のみ追記した | Phase 4の機械ゲートを実行する | 部分ゲートは無く全項目を再実行する | 手動 |
| 探索範囲拡大-scope-exhausted中断 | 検出例不足が報告され全ディレクトリ走査済みである | 再試行の探索範囲拡大を判断する | scope-exhaustedとして発散検知と同等に中断する | 手動 |

## 機械検証との対応

- 機械検証列「手動」は、検証状況（references/guide.html）へ確認結果を残す
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
