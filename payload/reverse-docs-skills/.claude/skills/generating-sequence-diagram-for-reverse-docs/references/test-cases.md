# generating-sequence-diagram-for-reverse-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 操作開始-合成step | call_orderを持つhandlerがある | facts.ymlからpage-dataへ変換する | 各operationの先頭にuser→screenの合成stepが付き、sourceRefを持たない | 手動 |
| 単一sourceRef-内部処理レーン | 1つのoperation内の全stepが同一ファイルパスを指す | 変換後にレーンを判定する | api endpointがinternalへ置換され、レーンからapiが除かれる | 手動 |
| 複数sourceRef-APIレーン維持 | 1つのoperation内のstepが複数ファイルパスを指す | 変換後にレーンを判定する | apiレーンとendpointが維持される | 手動 |
| 15ステップ超過-分割優先順 | 1handlerのcall_orderから15を超えるstepが生成される | operations[]への組み立てを行う | 機能一覧対応付けを優先し、無ければコメント境界、最後に機械的な15区切りの順で分割する | 手動 |
| 呼び出し0件区分-隣接吸収 | コメント境界区切りでcall_orderを含まない区分がある | operations[]を分割する | その区分は局面化せず、ソース出現順で連続する側の区分へ吸収される | 手動 |
| call_order0件-空operations生成 | facts.ymlは実在するがcall_orderを持つhandlerが0件 | Step 1-2を実行する | 推測で補わずoperations: []のpage-dataを生成する | 手動 |
| facts.yml不在-変換不能報告 | 対象画面にfacts.yml自体が存在しない | Step 1-2を実行する | 捏造せず変換不能として報告し当該画面をスキップする | 手動 |
| 表示文言-業務名導出優先順 | api分類itemのvalueに代入式や引数の丸括弧が含まれる | steps[].labelを導出する | 日本語コメント由来の業務名を優先し、無ければ識別子部分のみを使い代入や引数や分類タグは落とす | 手動 |
| doc_nav-ファイル経由必須 | 戻るリンクや設計書項目に二重引用符を含むdoc_nav文字列がある | Step 3-1でrender_templateへdoc_navを渡す | ファイル経由(cat)で読み込み、生成が停止せず終了コード0で完了しナビゲーション表示テキストが出力に実在する | shell-injection.shのself-testケース「PASS: 二重引用符を含むdoc_navでも生成が停止せず終了コード0」と「PASS: ナビゲーションの表示テキストが出力に実在する」 |
| doc_nav-引用符なし回帰 | 引用符を含まないdoc_nav文字列がある | Step 3-1でrender_templateへdoc_navを渡す | 従来どおり生成が成功し内容が出力に含まれる | shell-injection.shのself-testケース「PASS: 引用符を含まないdoc_navも従来どおり生成できる」 |
| 新規sh作成禁止-render_template直接source | render-template.shのrender_template関数を使う場面がある | Step 3-1を実行する | 新規.shファイルを作らずBashからのインラインsourceで完結する | 手動 |
| pageKind体系外-出力先分岐 | シーケンス図はpageKind契約（1固定ファイル名）に属さない | 出力先を決定する | output_dir直下ではなく、screenはscreenViewRoot、api・featureは各UnitRootの設計単位ディレクトリへ生成する | 手動 |
| screenUnitRoot上書き-物理path | output-layoutでscreenUnitRoot=スクリーン、screenViewRoot=project-portal/screens、kindLabels.screen=画面 | page-dataとHTMLを生成する | page-dataはスクリーン/screen-<ID>、HTMLはproject-portal/screens/screen-<ID>だけを読み書きし表示ラベルをpathへ流用しない | 手動 |
| API処理順序-シーケンス生成 | API詳細設計書§4.1の2処理に相当する合成page-dataがある | APIユニット相当のHTMLを生成する | apiUnitRoot/unit-dir直下にシーケンス図HTMLが生成され、一覧基点のsequencePathが安全な相対URLになる | `node scripts/test-sequence-kind-policy.mjs` |
| 機能正常系フロー-シーケンス生成 | 機能設計書§3.1の2処理に相当する合成page-dataがある | 機能ユニット相当のHTMLを生成する | featureUnitRoot/unit-dir直下にpage-dataとシーケンス図HTMLが生成され、page-dataがjq検証を通過する | `node scripts/test-sequence-kind-policy.mjs` |
| unitId空-識別子fallback | APIまたは機能のunitIdがnullで安全なunitKeyがある | unit-dirとマニフェスト対象を確定する | 種別prefix＋unitKeyをunit-dirとし、unitKey完全一致で1件を選ぶ | `node scripts/test-sequence-kind-policy.mjs` |
| unitKey不正-fallback拒否 | unitIdが空でunitKeyにpath区切りまたは制御文字がある | unit-dirを確定する | 衝突し得る置換をせず生成を停止する | `node scripts/test-sequence-kind-policy.mjs` |
| unitId不正-path拒否 | unitIdが`../escape`など安全な単一pathセグメントでない | unit-dirを確定する | output_dir外へ解決せず生成を停止する | `node scripts/test-sequence-kind-policy.mjs` |
| 順序表不成立-生成省略 | API§4.1または機能§3.1が空・プレースホルダのみ・順番号不正 | 対象ユニットを処理する | stepを推測せずHTMLを生成せずsequencePathも設定しない | 手動 |
| 非対象種別-sequencePath省略 | table・batch・report・external・messageの一覧マニフェストがある | 一覧生成前にpolicyを適用する | policyに従ってsequencePathを削除すると、実一覧テンプレートの表示処理にシーケンス図リンクも未作成表示も現れない | `node scripts/test-sequence-kind-policy.mjs` |
| 種別policy-完全性 | sequence-kind-policy.jsonを読む | 8種別のgenerateと一覧契約を検査する | screen/api/featureだけgenerate=true、残り5種別はgenerate=falseかつomitListField=sequencePath | `node scripts/test-sequence-kind-policy.mjs` |

## 機械検証との対応

- 機械検証列「手動」は、検証状況（references/guide.html）へ確認結果を残す
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
