# generating-external-list-for-reverse-docs テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| 検出0件-ハード停止 | カスタム抽出で外部連携が1件も見つからない | Phase 2の検出を実行する | 捏造せず、ユーザーに報告して停止する | 手動 |
| manifest-陽性検証-非screen経路 | unitKind:apiで代表される非screen経路の正当なmanifestがある | validate-manifest.shを実行する | 全11項目がPASSする | validate-manifest.shのself-testケース「api陽性: unitKind=apiで全11項目PASS」（table/batch/report/externalも同じ非screen経路を共有する） |
| metadata-通信方向の判定 | requests.postへのヒットとapp.postへのヒットを持つ連携がある | extract-external-metadata.shを実行する | directionフィールドに送信と受信がそれぞれ判定される | extract-external-metadata.shのself-testケース「direction: requests.postヒットで送信」と「direction: @app.postヒットで受信」 |
| metadata-プロトコル判定 | webhook文字列とparamikoによるsftpクライアントを持つ連携がある | extract-external-metadata.shを実行する | protocolフィールドにWebhookとSFTPがそれぞれ判定される | extract-external-metadata.shのself-testケース「protocol: webhook文字列でWebhook」と「protocol: paramiko/sftpでSFTP」 |
| metadata-認証方式の判定 | Authorization BearerとX-API-KeyのヘッダーをそれぞれUnitが持つ | extract-external-metadata.shを実行する | authMethodフィールドにOAuth2とAPIキーがそれぞれ判定される | extract-external-metadata.shのself-testケース「authMethod: Authorization BearerでOAuth2」と「authMethod: X-API-KeyでAPIキー」 |
| metadata-認証根拠なしでfail-safe | 認証判定の根拠となる記述が無い連携がある | extract-external-metadata.shを実行する | authMethodフィールドを付けない | extract-external-metadata.shのself-testケース「authMethod: 検出根拠が無ければフィールドを付けない(fail-safe)」 |
| metadata-宣言のみファイルの隔離 | クライアントの宣言だけで呼び出し実装が無いファイルがある | extract-external-metadata.shを実行する | 一覧本体のunitsに載らず、declarationOnly診断へ計上される | extract-external-metadata.shのself-testケース「宣言のみのファイルは一覧本体(units)に載らない」と「declarationOnly診断: count=1(unused_client.pyのみ宣言のみ)」 |
| html-属性注入防止 | 引用符を含むunitKeyがある | build-unit-list.shで生成する | 属性値として安全にエスケープし、埋め込みJSONは原本と一致する | build-unit-list.shのself-testケース「ケースb: 引用符を含むunitKeyを属性値として安全にエスケープし、埋め込みJSONも原本と完全一致」 |
| 境界判定-自プロジェクト内呼び出しの除外 | 自プロジェクトの別モジュールを呼び出すだけの記述がある | Phase 1で除外パターンを確定する | プロセス外かつ組織外のシステムとの通信だけを対象とし、内部呼び出しは含めない | 手動 |

## 機械検証との対応

- 機械検証が「手動」の行は、guide.html の検証状況へ手動確認を記録する
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
