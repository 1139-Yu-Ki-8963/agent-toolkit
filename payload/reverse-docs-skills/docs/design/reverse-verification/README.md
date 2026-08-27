# リバース検証

`設計.md` に定める第1層・第3層・4判定を、`generation-engine/scripts/verification/` のスクリプトで実行する。

判定結果は各コマンドの標準出力と終了コードで確認する。反復実行の結果や退避内容を専用ファイルへ記録する機能は廃止した。実行できない状態が未解決課題になる場合だけ、`docs/tasks/作業課題一覧.md` の7項目形式で管理する。

統合入口は次のとおりである。

```bash
bash generation-engine/scripts/verification/run-verification-loop.sh
```

長時間かかる第1層を別途実行する場合は、`--skip-layer1` を指定する。
