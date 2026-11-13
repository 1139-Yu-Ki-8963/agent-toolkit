# stop

## 設定のファイルへの登録

| 項目 | 値 |
|---|---|
| 発火点 | Stop |
| matcher | なし |
| command | `node "$CLAUDE_PROJECT_DIR/.claude/hooks/stop.js"` |
| timeout | 60 |

## スクリプトがする検査

| 検査の名前 | 確かめること | 対象のファイルの条件 | 根拠の規約と規則の観点 | 使うコマンドとファイル | 返す結果の種類(`kind`) | テスト |
|---|---|---|---|---|---|---|
| checkTestsRun | skill-factory の画面と中継サーバーの 5 つのファイル(`ui/server.mjs`、`ui/index.html`、`ui/段階ごとのスキルと規約.json`、`ui/はじめに.md`、`ui/デザイントークン.css`)の SHA-256 が、最新の判定の記録 `ui/tests/<実行日時>/判定の記録.md` の値と同じで、その記録の合否が「新しい不合格なし」である | skill-factory のフォルダの下の `ui/` のフォルダ。skill-factory のフォルダは、環境変数 `CLAUDE_PROJECT_DIR` のフォルダと `~/Projects/skill-factory` のうち、`ui/tests/run-auto.sh` を持つ最初のフォルダとする | なし | なし | `violation` | 「checkTestsRun: 結果を返す」と「checkTestsRun: 結果を返さない」 |
| checkTestsChanged | checkTestsRun の 5 つのファイルが直前のコミットと違うときに、`ui/tests/` のテストのプログラムも直前のコミットと違うか、`ui/tests/テストを足さない理由.md` が今の 5 つのファイルの SHA-256 を持つ | skill-factory のフォルダの下の `ui/` のフォルダ | なし | `/usr/bin/git` | `violation` | 「checkTestsChanged: 結果を返す」と「checkTestsChanged: 結果を返さない」 |

## 入力

| 標準入力の JSON の項目 | 使い方 |
|---|---|
| `hook_event_name` | `Stop` であることを確かめる |
| `stop_hook_active` | 検査をするかを決める |
| `transcript_path` | 会話の記録が skill-factory のフォルダのパスを持つかを確かめ、持つセッションでだけ検査をする |

## 出力

| スクリプトが終わる場合 | 終了コード | 出力先 | 出力の形 |
|---|---|---|---|
| 標準入力が JSON として読めない | 0 | なし | なし |
| `hook_event_name` が `Stop` 以外 | 0 | なし | なし |
| `stop_hook_active` が true | 0 | なし | なし |
| 結果が 0 件 | 0 | なし | なし |
| 結果が 1 件以上 | 2 | 標準エラー | まとめた文章 |

## スクリプトの動作の確かめ方

確かめる人は、`node --test hooks/stop/stop.test.js` を実行し、すべてのテストが合格することを確かめる。
