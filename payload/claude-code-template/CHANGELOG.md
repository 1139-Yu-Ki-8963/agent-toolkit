# 変更履歴

## 0.1.0 — 初版

### 同梱内容

- 危険操作ガード（pre-tool-use.mjs） — 配線済み
- 未適応検知（session-start.mjs） — 配線済み
- オプション hook 6 本 — 未配線（user-prompt-submit / permission-request / post-tool-use / post-tool-use-failure / config-change / session-end）
- rules 7 ファイル（00-global / 10-frontend / 20-backend / 30-security / 40-testing / 50-database / 90-infra）
- スキル 2 本（/adapt — プロジェクト適応、/safe-commit — 確認つきコミット）
- 導入スクリプト init.mjs（冪等・非破壊）
- テストスイート guard.test.mjs
