# generating-screen-list-for-reverse-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 検出失敗-画面実在なのに0件 | 調査書が画面の実在を判定済みである | 組み込み検出器またはカスタム抽出で画面を0件検出する | 停止して報告し、手動リストは聞き出さず、誤った境界を即興確定させない | 手動 |
| 該当なし-画面不在での0件正常終了 | 調査書が画面の不在を判定済みである | 検出0件のまま処理を進める | 判定理由付きの該当なし文書を生成し、status=NONEで終える | 手動 |
| manifest-陽性検証-screen15項目 | 15項目の必須フィールドを満たす正当なmanifestがある | validate-manifest.shをunit-kind screenで実行する | 全15項目がPASSする | validate-manifest.shのself-testケース「screen陽性: 既定unitKind(screen)で全15項目PASS」 |
| manifest-screenType値域外拒否 | screenTypeに値域外の文字列を設定したmanifestがある | validate-manifest.shを実行する | FAILする | validate-manifest.shのself-testケース「screenType陰性(値域外)」 |
| manifest-親子参照-双方向整合 | parentScreenとchildComponentsを相互設定した2画面がある | validate-manifest.shを実行する | 双方向一致ならPASSし、片側のみならFAILする | validate-manifest.shのself-testケース「parent-child陽性」と「parent-child陰性(親のみ)」 |
| manifest-名称一意性の同名許容判定 | 異なるnameScopeを持つ2画面が同じscreenNameGuessを持つ | validate-manifest.shを実行する | 異なる範囲間の同名はPASSし、同一範囲内の同名はFAILする | validate-manifest.shのself-testケース群（nameScope単位の名称重複判定。陽性ケースと陰性ケースの2件） |
| html-識別子内バックスラッシュでも埋め込みJSON一致 | routeにバックスラッシュを含むdetectionMethodを持つmanifestがある | build-screen-list.shで画面一覧htmlを生成する | 埋め込みJSONが原本と完全一致する | build-screen-list.shのself-testケース「ケースa: バックスラッシュを含むdetectionMethodでも埋め込みJSONが原本と完全一致」 |
| html-属性値エスケープでdiagnostics安全化 | 危険文字とマーカー文字列が衝突するdiagnosticsを持つmanifestがある | build-screen-list.shで生成する | application/json埋め込みが安全化され、属性注入を防ぐ | build-screen-list.shのself-testケース「ケースb: 危険文字+実マーカー文字列衝突を含むdiagnosticsでも埋め込みJSONが原本と完全一致」 |
| html-確定画面名の単一表示源化 | 末尾にOK表記を含むscreenNameGuessを持つmanifestがある | build-screen-list.shで生成する | 埋め込みマニフェストを表示源として画面名を再描画する | build-screen-list.shのself-testケース「1-41: 確定画面名は埋め込みマニフェストを単一表示源として再描画」 |
| html-戻りリンクの実在index解決 | portal-dir配下にindex.htmlが実在する | build-screen-list.shに--portal-dirを渡して生成する | ポータルへ戻るリンクが実在するindexへ到達する | build-screen-list.shのself-testケース「1-44: 戻りリンクを任意portalの実在indexへ解決」 |
| OKマーカー除去-業務語保持 | 「決済OK着地」のように語中にOKを含む業務語がある | screenNameGuessの末尾マーカー除去処理を適用する | 語頭語中のOKは保持し、末尾表記だけを除去する | detect-screens.shのself-testケース「1-55-OKマーカー除去-業務用語維持-着地」 |
| 低信頼度分布-警告コールアウト表示 | confidence=lowの画面比率が閾値0.5を超えるmanifestがある | build-screen-list.shでlowConfidence指標を機械算出する | 比率超過時にのみ警告コールアウトを表示し、0件でもタイル自体は常に表示する | 手動 |

## 機械検証との対応

- 機械検証列が「手動」の行は、検証状況（references/generating-screen-list-for-reverse-docs-guide.html のメタテーブル）へ手動確認の記録を残す
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
