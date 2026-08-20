# ai-management-portal

マシン全体の AI エージェント資産を閲覧する管理ポータル。

## 配信手順（正本）

```bash
node ~/agent-home/tools/harness/scripts/portal-server.mjs start   # 起動
node ~/agent-home/tools/harness/scripts/portal-server.mjs status  # 状態・URL 確認
node ~/agent-home/tools/harness/scripts/portal-server.mjs stop    # 停止
```

- ポート: 9000（`~/.claude/rules/always/local-environment/port-management/port-values.txt` の割当。変更禁止）
- 配信ルート: 本ディレクトリのみ（agent-home 全体は公開しない。セッションログ等の保護のため）
- LAN 公開（bind 0.0.0.0）はモバイル閲覧のための意図的設定

## アクセス URL

- PC: `http://localhost:9000/`
- モバイル（同一 Wi-Fi）: `http://<LAN IP>:9000/board/task-board.html`（LAN IP は status コマンドで表示される）
- 旧ブックマーク互換: `/ai-management-portal/...`・`/docs-portal/...` のパスも自己参照シンボリックリンクで到達できる

## トラブルシュート

| 症状 | 確認 |
|---|---|
| 404 | パス形式を確認する。ルートは本ディレクトリのため `/board/task-board.html` が正。旧形式もシンボリックリンクで救済済み |
| 接続できない | `status` で LISTEN を確認 → 落ちていれば `start`。モバイルが同一 Wi-Fi か確認。macOS ファイアウォールで Python の受信許可を確認 |
| ボードが空表示 | `state/task-board/board.js` が未生成。task-board.mjs を一度実行すると生成される |
