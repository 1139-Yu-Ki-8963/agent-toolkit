# generating-glossary-for-reverse-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 採録源-全不在のみ停止 | 共通文書と調査書とコードの3系統すべてが不在 | Phase 1 Step 2を実行する | 該当スキルの先行実行を案内して停止する | 手動 |
| 採録源-一部不在は続行 | 3系統のうち1件か2件のみ不在 | Phase 1 Step 2を実行する | 停止せずmissingSourceLayersへ記録して続行する | 手動 |
| 採録-層化サンプリングの決定性 | コード識別子を抽出する | Phase 2 Step 2を実行する | 決定的コマンドに固定され乱数や目視選定は行わない | 手動 |
| 採録-根拠なき語の退避 | 分類軸に該当しそうだが採録源に定義記述が無い語がある | Phase 2 Step 3を実行する | terms[]に含めずunresolved[]へ退避する | 手動 |
| 二段承認-候補一覧の取捨 | 候補一覧を提示した後に削除指示を受ける | Phase 3 Step 2を実行する | 削除指示があった語はterms[]から除かれる | 手動 |
| 二段承認-新規事実追加の禁止 | 言い換え指示に採録源に無い新規事実が含まれる | Phase 3 Step 2を実行する | 反映せずhintに記録する | 手動 |
| sourceRef-文書参照形式は検査対象外 | terms[].sourceRefに文書参照形式の値がある | validate-page-data.sh --target-repoを実行する | 実在検査の対象外として扱われる | 手動 |
| diagnostics-欠落採録源の可視化 | 採録源系統が3系統中1件不在 | Phase 2の可視化手順を実行する | missingSourceのcountとtotalとratioとwarningが算出される | 手動 |
| 全語削除-空配列でも組み立て可 | Phase 3で全語が削除された | page-data.jsonを組み立てる | terms:[]として組み立てられ空配列を許容する | 手動 |
| html生成-埋め込みJSON一致 | glossaryのpage-data.jsonがある | build-detail-page.shで生成する | ファイル名対応（用語辞書.html）で出力し、埋め込みJSONが原本と完全一致する | build-detail-page.shのself-testケース「ケースd(glossary)」 |
| ヘッドレス実行-既定値自動承認 | 対話環境が無い状態で実行する | Phase 1 Step 4とPhase 3 Step 2を実行する | 既定値で自動承認し適用値をhintに明記する | 手動 |

## 機械検証との対応

- 機械検証が「手動」の行は、generating-glossary-for-reverse-docs-guide.html の検証状況へ手動確認を記録する
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
