# generating-reverse-detailed-design テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 画面単位root上書き-verify | screenUnitRootがスクリーンで旧画面rootにdecoyがある | scaffold-screen.sh --verifyを実行する | 物理配置キーのrootだけを検証する | scaffold-screen.sh self-test「screenUnitRoot上書きへ展開しverifyも同じ配置を検証」 |
| 充足検査-孤児参照の検出 | facts.ymlのevidenceが対象ファイル集合と一致しない | check-facts-sufficiency.shを実行する | orphan-evidenceとしてexit1になる | check-facts-sufficiency.shのself-testケース「陰性: orphan-evidence で exit 1」 |
| 充足検査-根拠形式の検出 | evidenceの記載形式が規約に合わない | check-facts-sufficiency.shを実行する | evidence-formatとしてexit1になる | check-facts-sufficiency.shのself-testケース「陰性: evidence-format で exit 1」 |
| 完全性ゲート-未転記キー検出 | facts.ymlのimportに未転記の項目がある | check-fact-coverage.shを実行する | 未転記1件でもexit1のfail-closedとなる | check-fact-coverage.shのself-testケース「陰性1: import未転記1件で exit 1」 |
| 完全性ゲート-実測委譲なしの未転記 | 実測委譲表記が無く個別キーも未転記のまま | check-fact-coverage.shを実行する | exit1のfail-closedとなる | check-fact-coverage.shのself-testケース「陰性2: 実測委譲表記なし・個別キー未転記で exit 1」 |
| 値レベル検証-トークン未転記の検出 | facts.ymlの値中トークンが設計書本文に無い | check-fact-coverage.shを実行する | fail-closedでexit1になる | check-fact-coverage.shのself-testケース「値レベル検証陰性: トークン未転記(100)で exit 1（fail-closed）」 |
| 除外セクション-実装寄り分類は値検査対象外 | measurement_pending・styleの値が未転記のまま残る | check-fact-coverage.shを実行する | この2分類は未転記でもexit0とする | check-fact-coverage.shのself-testケース「除外セクション: measurement_pending/style はトークン未転記(200/480)でも exit 0」 |
| 座標ノイズ除去-file:line断片は要求しない | evidenceがFoo.tsx:12のような座標断片を持つ | check-fact-coverage.shを実行する | 座標断片をトークンとして要求せずexit0になる | check-fact-coverage.shのself-testケース「座標ノイズ除去: Foo.tsx:12 断片を要求せず exit 0」 |
| §16連携-実測委譲件数の突合 | 本文の実測委譲件数と§16計上数が食い違う | audit-consistency.shを実行する | 違反として検出される | audit-consistency.shのself-testケース「検査i-3陽性: 本文の実測委譲件数と§16計上の不一致を違反として検出する」 |
| §16厳格モード-未解消行の違反昇格 | AUDIT_STRICT_P16=1を設定し§16に未解消行が残る | audit-consistency.shを実行する | 違反へ昇格しexit1になる | audit-consistency.shのself-testケース「検査i陰性2: AUDIT_STRICT_P16=1で未解消行が違反に昇格しexit1になる」 |
| 到達不能参照-relatedフィールドの検査 | related系フィールドが実在しない参照を含む | audit-consistency.shを実行する | 到達不能な参照として違反検出される | audit-consistency.shのself-testケース「本文の到達不能な相対パス参照を違反として検出する」 |
| 型定義なしの集約-捏造防止 | facts.ymlのexport_typeに型定義が無い | §15.2を非該当集約する | 型を捏造せずaudit-consistency.shはexit0になる | 手動 |
| 原本Read禁止-facts_refとcommon_docs_rootに限定 | 本スキル実行中である | 情報源を確認する | 対象リポジトリの原本コードを一切Readしない | 手動 |
| 大規模2パス-パス1未完了でのパス2開始禁止 | detail-onlyがDETAIL_AUTHOREDを返していない | companion-docsを起動しようとする | パス1未完了を理由に開始しない | 手動 |
| scenarios入力検査-未開通時の省略許容 | verification_urlが無い未開通状態である | validate-reverse-authoring-inputs.py scenariosを実行する | query・path_params省略をPASSとする | 手動 |
| 画面横断章-実装用語の露出禁止 | mode=screenが機能一覧・画面遷移を著述する | audit-consistency.shの禁止観点検査を行う | コード識別子・型構文の露出を検出する | 手動 |

## 機械検証との対応

- 機械検証が「手動」の行は、generating-reverse-detailed-design-guide.html の検証状況へ手動確認を記録する
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
