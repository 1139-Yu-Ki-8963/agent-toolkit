# orchestrating-reverse-docs-flow テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 画面単位root上書き-状態検査 | output-layoutのscreenUnitRootがスクリーンで旧画面rootにdecoyがある | 状態8〜12の画面単位文書検査を行う | スクリーン配下だけを認識し旧rootを読まない | resolve-flow-state.sh self-test「screenUnitRoot上書きだけを状態検査し既定rootのdecoyを除外」 |
| 状態判定-機械出力採用 | 状態判定の根拠が複数の成果物の実在にわたる | resolve-flow-state.shを実行する | 標準出力の状態キー1行をそのまま採用する | resolve-flow-state.shのself-testケース「状態1 アーキ未調査」ほか16状態 |
| 状態判定-未判定時の対応 | 状態8までの実在条件が確定しない | resolve-flow-state.shを実行する | 未判定を返しscreen_idの解決状況を確認する | resolve-flow-state.shのself-testケース「未判定 screen_id解決不能で未判定」 |
| 起動引数表-掲載漏れ検出 | 起動引数表とcontract.mdのargs仕様に差分がある | check-arg-table-coverage.shを実行する | 表に載らない子スキル起動引数を差分として検出する | check-arg-table-coverage.shのself-testケース「合成陰性: 表未掲載のgammaを差分として検出」 |
| 起動引数表-内部値の除外 | 差分候補にmode等の統括内部の導出値が含まれる | check-arg-table-coverage.shを実行する | DENYLIST対象は差分に含めない | check-arg-table-coverage.shのself-testケース「合成陰性: DENYLIST対象のmodeが誤って差分に含まれた」の否定確認 |
| サイトループ-対象サイトごとに繰り返す | アーキテクチャ調査書§10で複数サイトを確定した | サイトを確定した後にglobal Step 3〜16を実行する | 確定した対象サイトごとに同じStepを繰り返す | 手動 |
| サイトループ-失敗時は他サイトへ進まない | いずれかのサイトの工程が中断した | 次サイトの着手可否を判定する | そのまま停止し他サイトへ進まない | 手動 |
| Python経路-画面範囲を問わない | facts_profile=pythonが明示されている | Step 1-1で必須項目を確定する | screen_scopeを要求せず対象ファイルと論理IDで進める | 手動 |
| Python経路-対象ファイル全件.py要求 | target_file_pathsに.py以外が混在する | 明示Python facts-only経路を実行する | 全件.pyでなければ中断する | 手動 |
| 大規模2パス-パス1未完了での開始禁止 | detail-onlyがDETAIL_AUTHOREDを返していない | パス2（companion-docs）を起動しようとする | パス1未完了を理由に開始しない | 手動 |
| NG帰着-facts欠落は自動配線しない | judgeがNG帰着(b)facts欠落と判定した | 改善サイクルの配線を決定する | 自動配線せずユーザーに報告する | 手動 |
| NG帰着-共通文書欠落は再起動可能 | judgeがNG帰着(c)共通文書欠落と判定した | 改善サイクルの配線を決定する | generating-reverse-common-docsをmode=appendで再起動できる | 手動 |
| 画面バッチ経路-4件以上で委譲 | 対象画面が4件以上ある | Step 4-5完了後に経路を選ぶ | running-reverse-screen-batchへglobal Step 17〜30を委譲する | 手動 |
| ファイル単位差し戻し-iterative限定 | rebuilding-screen-unit-from-docsがstatus=差し戻しを返した | verification_modeごとに差し戻し先を決める | iterativeのときだけ設計書未著述へ戻す | 手動 |
| 画面開通-facts抽出の前提条件でない | 対象画面が未開通のまま | 静的リバースの継続可否を判定する | 開通できなくても facts・基本設計・詳細設計へ進める | 手動 |
| 無人モード-進捗記録 | headless=trueで工程が開始または完了した | progress.jsonlへの追記可否を確認する | 工程名とstatusを持つJSON行が追記される | 手動 |
| 画面レジストリ復元-拡張マニフェスト起点 | 永続screen_manifest_pathが不在で画面一覧HTMLがある | restore-screen-manifest.shで復元する | 復元内容は生検出結果でなく拡張マニフェスト相当と扱う | 手動 |

## 機械検証との対応

- 機械検証が「手動」の行は、orchestrating-reverse-docs-flow-guide.html の検証状況へ手動確認を記録する
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
