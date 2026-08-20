# surveying-local-environment テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 既存env-config-再生成拒否 | output_dirにenv-config.jsonが既に存在する | Phase 1 Step 1-1を実行する | 削除してから再実行するよう報告して終了する | 手動 |
| 正常JSON-必須キー充足 | 全必須キーを備えた正しいenv-config.jsonがある | validate-env-config.shを実行する | 終了コード0で通過する | validate-env-config.shのself-testケース「PASS: ケース1 正常JSONで終了コード0」 |
| 必須キー欠落-トップレベル検出 | surveyed_atのようなトップレベル必須キーが欠落している | validate-env-config.shを実行する | 終了コード1で欠落キーを列挙する | validate-env-config.shのself-testケース「PASS: ケース2 必須キー欠落で終了コード1・欠落キー列挙」 |
| 必須キー欠落-tools配下検出 | tools.jqのようなtools配下の必須キーが欠落している | validate-env-config.shを実行する | 終了コード1で欠落キーを列挙する | validate-env-config.shのself-testケース「PASS: ケース3 tools配下欠落で終了コード1・欠落キー列挙」 |
| Linux互換環境-ベンダー名判定 | uname -sがLinuxを返す実行環境がある | Phase 2でlinux_compat_envを判定する | /proc/versionにベンダー名が含まれるかで真偽を判定し素のLinuxと区別する | 手動 |
| cloc未導入-案内提示 | tools.cloc が false | Phase 4 Step 4-1を実行する | パッケージ管理ツールに応じたインストールコマンドを案内する | 手動 |
| cloc導入済み-案内省略 | tools.cloc が true | Phase 4 Step 4-1を実行する | 案内を省略する | 手動 |
| フィールド消費経路-無いものは追加しない | env-config.jsonへ新規フィールドを追加する場面がある | スキーマを拡張する | 消費経路表に行を追加してから追加し、消費先の無いフィールドは追加しない | 手動 |

## 機械検証との対応

- 機械検証列「手動」は、検証状況（references/guide.html）へ確認結果を残す
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
