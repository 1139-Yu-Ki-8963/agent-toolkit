# generating-cross-views-for-reverse-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 前提-画面API不在でハード停止 | screen-manifestまたはext、API一覧.htmlのいずれかが不在 | Phase 1を実行する | 画面一覧または一覧生成スキルの先行実行を案内して停止する | 手動 |
| 前提-テーブル機能一覧は任意 | テーブル一覧.htmlと機能一覧.htmlが不在 | Phase 1 Step 2を実行する | 停止せずPhase 2以降を続行する | 手動 |
| 交差データ-重複unitKey拒否 | feature-manifestに同じunitKeyを持つunitが2件ある | build-matrix-data.shを実行する | 終了コード1で重複unitKeyをstderrへ列挙する | build-matrix-data.shのself-testケース「ケースd」 |
| 交差データ-CRUD判定材料不足 | relatedApis参照先APIがmethodを持たない | build-matrix-data.shを実行する | 終了コード1でCRUD判定材料不足のエラーを出す | build-matrix-data.shのself-testケース「ケースe」 |
| 交差データ-targetTables欠落は許容 | feature参照APIのtargetTablesが欠落している | build-matrix-data.shを実行する | 非CRUDとして許容し3成果物を生成する | build-matrix-data.shのself-testケース「ケースf」 |
| 交差データ-feature-manifest任意 | feature-manifestを指定しない | build-matrix-data.shを実行する | API単位のフォールバックで生成が成功する | build-matrix-data.shのself-testケース「ケースb」 |
| AI設定資産-抽出値 | .claude/配下にrules/skills/subagents/hooksがあるフィクスチャがある | extract-ai-assets.shを実行する | フィクスチャの抽出値が期待どおりになる | extract-ai-assets.shのself-testケース「ケースa」 |
| AI設定資産-表示分離 | mechanical=trueの規約とadvisory規約が混在する | AI設定資産.htmlを生成する | 宣言区分と機械強制を分けて表示し、dangerはmechanical=trueの時だけ付く | extract-ai-assets.shのself-testケース「ケースc」 |
| permission-function変換-決定性 | 同一permission-matrix.jsonを2回変換する | build-permission-function-data.shを実行する | 出力が原本と一致する | 手動 |
| permission-function変換-重複拒否 | featuresに同一unitKeyの重複がある | build-permission-function-data.shを実行する | 生成が失敗し重複を許容しない | 手動 |
| 出力先-ai-assetsの専用フォルダ名 | ai-assetsページを生成する | build-matrix-pages.shで生成する | フォルダ名がラベルと一致せずAI設定資産/AI設定資産.htmlに出力される | 手動 |

## 機械検証との対応

- 機械検証が「手動」の行は、guide.html の検証状況へ手動確認を記録する
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
