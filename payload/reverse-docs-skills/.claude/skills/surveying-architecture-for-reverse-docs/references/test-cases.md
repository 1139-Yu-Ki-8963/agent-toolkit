# surveying-architecture-for-reverse-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| パス実在-未実在検出 | backtick表記の相対パスが対象リポジトリに実在しない | check-architecture-survey.shを実行する | 検査1がFAILしexit 1になる | check-architecture-survey.shのself-testケース「[PASS] 検査1: 未実在パスでexit 1」 |
| パス実在-非実在マーカーで対象外 | 実在しないパスに「非実在:」マーカーを前置している | check-architecture-survey.shを実行する | 実在チェック対象外として通過する | check-architecture-survey.shのself-testケース「[PASS] 検査1(1-115): 非実在マーカー付きの実在しないパスは実在チェック対象外として通過」 |
| ユニット種別-判定手がかり不整合検出 | 「実在しない」と記録した種別を検出手がかりで再実行すると1件以上返る | check-architecture-survey.shを実行する | 検査2がFAILしexit 1になる | check-architecture-survey.shのself-testケース「[PASS] 検査2(1-140): 判定と検出手がかり再実行結果の不整合でexit 1」 |
| 推測語混入-検出 | 「おそらく」等の推測語が調査書に含まれる | check-architecture-survey.shを実行する | 検査3がFAILしexit 1になる | check-architecture-survey.shのself-testケース「[PASS] 検査3: 推測語混入でexit 1」 |
| テンプレ残存-地の文言及は誤検出しない | TODO/TBDという語自体を地の文で言及している | check-architecture-survey.shを実行する | プレースホルダとして誤検出せず通過する | check-architecture-survey.shのself-testケース「[PASS] 検査4(1-153): TODO/TBDの地の文言及は誤検出しない」 |
| ディレクトリ網羅-ルート行の限定網羅 | §4の`.`行がルート直下のみを記載している | check-architecture-survey.shを実行する | ルート直下のみ網羅済みとみなしsrc/appの未網羅でexit 1になる | check-architecture-survey.shのself-testケース「[PASS] 検査5: §4の`.`行はルート直下のみ網羅しsrc/appの未網羅でexit 1」 |
| ディレクトリ網羅-走査範囲の自己完結 | §1の調査コマンドが浅いmaxdepthを記述しつつ深階層に未網羅ディレクトリがある | check-architecture-survey.shを実行する | 記述に関わらず深階層の未網羅ディレクトリを検出しexit 1になる | check-architecture-survey.shのself-testケース「[PASS] 検査5: §1の記述に関わらず深階層の未網羅ディレクトリを検出しexit 1」 |
| サイト一覧-ルート未実在検出 | サイト一覧のルートディレクトリが対象リポジトリに実在しない | check-architecture-survey.shを実行する | 検査6がFAILしexit 1になる | check-architecture-survey.shのself-testケース「[PASS] 検査6: サイトのルートディレクトリ未実在でexit 1」 |
| ワークスペースなし-複数サイト許容 | ワークスペース定義が無いのにサイト一覧が2行ある | check-architecture-survey.shを実行する | Webサーバー設定由来の複数サイトとして通過する | check-architecture-survey.shのself-testケース「[PASS] 検査6(1-116): ワークスペース定義なしでも複数サイト行(2件)が実在ルートで通過」 |
| エンコーディング-実測不一致検出 | §8に記録したエンコーディング名で対象ファイルが復号できない | check-architecture-survey.shを実行する | 検査7がFAILしexit 1になる | check-architecture-survey.shのself-testケース「[PASS] 検査7(1-126): 復号できない値の記録でexit 1」 |
| revise-部分ゲート禁止 | mode=reviseで指摘節のみ改訂した | Phase 5の機械ゲートを実行する | 部分ゲートは無く全項目を再実行する | 手動 |
| 発散判定-即中断 | 同一検査項目の同一NG理由が2回連続で再発する | ループ実行中に判定する | 上限5回消化前でも発散として即中断する | 手動 |

## 機械検証との対応

- 機械検証列「手動」は、検証状況（references/guide.html）へ確認結果を残す
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
