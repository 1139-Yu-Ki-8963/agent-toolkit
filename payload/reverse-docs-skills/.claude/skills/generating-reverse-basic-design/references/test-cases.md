# generating-reverse-basic-design テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 画面単位root上書き-scaffold | screenUnitRootがスクリーン | scaffold後に--verifyする | スクリーン/screen-*へ展開され同じrootをverifyする | scaffold-screen.sh self-test「screenUnitRoot上書きへ展開しverifyも同じ配置を検証」 |
| 画面構成入力判定-helper単一判定源 | 著述前にscreen-composition判定を行う | validate-reverse-authoring-inputs.pyを実行する | 終了コードとstatusの不一致はfail-closedで停止する | 手動 |
| 画面構成4ケース-両方無しは著述停止 | original.pngもfacts.ymlの利用可能な構造も無い | Phase 2の画面構成生成を行う | status=基本設計著述失敗とし両方の根拠が無い旨を返す | validate-reverse-authoring-inputs.pyのself-testが検証する分岐「1-23 branch original=False jsx=False」（expected=1） |
| 画面構成4ケース-画像優先 | original.pngがある | Phase 2の画面構成生成を行う | 構造の有無にかかわらず画像を優先する | validate-reverse-authoring-inputs.pyのself-testが検証する分岐「1-23 branch original=True jsx=False」（expected=0） |
| 画面構成4ケース-構造推定の明記 | original.pngが無くfacts.ymlに利用可能な構造がある | Phase 2の画面構成生成を行う | 見出しに構造推定と明記し根拠に無い値を創作しない | validate-reverse-authoring-inputs.pyのself-testが検証する分岐「1-23 branch original=False jsx=True」（expected=0） |
| 原本Read禁止-facts.ymlと共通文書に限定 | 本スキル実行中である | 情報源を確認する | 対象リポジトリの原本コードを一切Readしない | 手動 |
| 転記対象限定-実装寄り5分類は転記しない | facts.ymlにimport・export_type等が含まれる | Phase 2の転記を行う | 転記対象はstate・handler・jsx・api・meta.routeの5分類に限る | 手動 |
| 実装用語混入検査-内部成果物名も禁止対象 | facts.yml等の内部識別子が本文に残る | Phase 3のgrep検査を行う | 検出0件を完了条件とし内部識別子も禁止対象に含める | 手動 |
| 創作の禁止-UI部品からの挙動推定を禁止 | facts上で空実装と分かる部品がある | Phase 2の業務断定を行う | 現状をそのまま明記し切替挙動等を創作しない | 手動 |
| unit_kind制約-screen以外は未実装 | unit_kindにscreen以外が指定される | Phase 1の起動引数検収を行う | 著述せずstatus=基本設計著述失敗とする | 手動 |
| large-pass2-固定契約の再検収 | authoring_pass=large-pass2で起動される | Phase 1の検収を行う | パス1証跡5条件を機械検収し1条件でも欠ければfail-closedとする | 手動 |

## 機械検証との対応

- 機械検証が「手動」の行は、guide.html の検証状況へ手動確認を記録する
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
