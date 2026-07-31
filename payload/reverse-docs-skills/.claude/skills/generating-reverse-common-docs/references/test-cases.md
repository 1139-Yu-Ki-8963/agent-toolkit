# generating-reverse-common-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 雛形ファイル欠落-検出 | 11文書のいずれかが欠落している | check-common-docs.shを実行する | 検査1がFAILしexit 1になる | check-common-docs.shのself-testケース「[PASS] 検査1: ファイル欠落でexit 1」 |
| 三点セット欠落-検出 | 規則行に実例か頻度か例外率のいずれかが欠落している | check-common-docs.shを実行する | 検査2がFAILしexit 1になる | check-common-docs.shのself-testケース「[PASS] 検査2: 実例/頻度/例外率欠落でexit 1」 |
| 記載パス未実在-検出 | backtick表記の相対パスが対象リポジトリに実在しない | check-common-docs.shを実行する | 検査3がFAILしexit 1になる | check-common-docs.shのself-testケース「[PASS] 検査3: 未実在パスでexit 1」 |
| テンプレ残存-地の文言及は誤検出しない | TODO/TBDという語自体を地の文で言及している | check-common-docs.shを実行する | プレースホルダとして誤検出せず通過する | check-common-docs.shのself-testケース「[PASS] 検査4(1-153): TODO/TBDの地の文言及は誤検出しない」 |
| 理想論表現-規約4文書で検出 | 規約4文書にあるべき姿を語る理想論表現がある | check-common-docs.shを実行する | 検査5がFAILしexit 1になる | check-common-docs.shのself-testケース「[PASS] 検査5: 理想論表現でexit 1」 |
| メッセージ規模-宣言不一致検出 | メッセージ定義書の宣言件数と実測件数が一致しない | check-common-docs.shを実行する | 検査6がFAILしexit 1になる | check-common-docs.shのself-testケース「[PASS] 検査6: 宣言件数と実測件数の不一致でexit 1」 |
| サンプル外裏取り-規模実測限定 | サンプル外で定義本体を開いて裏取りする場面がある | Phase 3〜4で採録する | 規模と件数とキー一覧の実測に限り開き、カタログ規模の推測表現は禁止する | 手動 |
| 層化サンプリング-必須サンプル先取り | アーキテクチャ調査書が特定ディレクトリを名指ししている | Phase 2で層化サンプリングを実行する | 均等配分に先立って必須サンプルとして先取りする | 手動 |
| append-部分ゲート禁止 | mode=appendで指摘文書のみ追記した | Phase 5の機械ゲートを実行する | 部分ゲートは無く全項目を再実行する | 手動 |
| 探索範囲拡大-scope-exhausted中断 | 検出例不足が報告され全ディレクトリ走査済みである | 再試行の探索範囲拡大を判断する | scope-exhaustedとして発散検知と同等に中断する | 手動 |

## 機械検証との対応

- 機械検証列「手動」は、検証状況（references/generating-reverse-common-docs-guide.html）へ確認結果を残す
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
