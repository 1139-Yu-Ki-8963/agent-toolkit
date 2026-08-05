# generating-agent-config-index-from-repo テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 共通索引語-両ファイル揃い | AGENTS.mdとCLAUDE.mdの前半索引が8つの索引語を含む | check-agent-config-index.shで検証する | 終了コード0で通過する | check-agent-config-index.shのself-testケース「PASS: 正常系（索引語すべて揃う）で終了コード0」 |
| 共通索引語-欠落検出 | AGENTS.mdから「検証」の索引語が欠落している | check-agent-config-index.shで検証する | 終了コード1で異常終了する | check-agent-config-index.shのself-testケース「PASS: 異常系（索引語欠落）で終了コード1」 |
| 参照パス-対象リポジトリ基準で実在 | AGENTS.mdが対象リポジトリ配下の実在パスを参照する | 対象リポジトリを第3引数に渡して検証する | 対象リポジトリを基準にパスが実在し終了コード0になる | check-agent-config-index.shのself-testケース「PASS: 対象リポジトリを基準に実在するパスは終了コード0」 |
| 参照パス-対象リポジトリ基準で不在 | AGENTS.mdが対象リポジトリに存在しないパスを参照する | 対象リポジトリを第3引数に渡して検証する | 終了コード1で異常終了する | check-agent-config-index.shのself-testケース「PASS: 対象リポジトリに存在しないパスで終了コード1」 |
| CLAUDE-規約複製禁止 | CLAUDE.mdにdocs/rules/への言及や規約一覧見出しがある | check-agent-config-index.shで検証する | 規約本文や規約一覧の複製を検出しFAILと判定する | check-agent-config-index.shのcheck関数「FAIL: CLAUDE.md contains duplicated rule index/body」「FAIL: CLAUDE.md contains a rule-loading section」 |
| 規約索引-単一経路 | 規約索引を書くのはbuild-derived-rules.shだけであり、スキルは書かない | Phase 2 Step 2-1を実行する | AGENTS.mdにはRULES-INDEXマーカーを含むテンプレートだけが複製され、個々の規約参照や承認件数をスキル側が書き込まない | 手動 |
| 未確認事項-推測記入禁止 | 実行検証していないコマンドや業務目的が不明 | Phase 1 Step 1-1を実行する | 未実行コマンドを成功例として書かず、未確認事項を推測で埋めない | 手動 |
| 規約参照-実在パスのみ | rules_rootが指定されている | Phase 2 Step 2-1を実行する | AGENTS.mdの規約参照を実在パスのみで構成し根拠がない規約カテゴリは生成しない | 手動 |
| 出力先-逸脱検出 | 生成先がoutput_dir配下に固定されている | Phase 3 Step 3-1を実行する | テンプレートルートや対象リポジトリの無関係な場所へ出力が逸脱していないことを検査する | 手動 |
| 検証失敗-生成非確定 | Phase 3の検査項目のいずれかが失敗する | Phase 3 Step 3-1を実行する | 生成を確定せず根拠不足として返す | 手動 |

## 機械検証との対応

- 機械検証列「手動」は、検証状況（references/generating-agent-config-index-from-repo-guide.html）へ確認結果を残す
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
