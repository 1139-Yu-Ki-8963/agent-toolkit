# claudecode-global-setup

PC 全体の Claude Code / Codex 環境（`~/agent-home/` と runtime 別設定）をセットアップするための配布単位です。個別プロジェクト向けのツールキットとは区別され、このフォルダの中身だけで共通基盤が揃います。

## 中身

| フォルダ | 設置先 |
|---|---|
| `agent-home/` | `~/agent-home/`（ディレクトリ全体をミラー） |
| `claude-config/` | `~/.claude/`（ファイル単位で設置） |
| `codex-config/hooks.json` | `~/.codex/hooks.json`（opt-in、安全 merge） |

## 設置手順

agent-toolkit リポジトリ全体を clone したうえで、リポジトリ直下から実行してください（このフォルダ単体の clone では動作しません）。

```bash
git clone https://github.com/1139-Yu-Ki-8963/agent-toolkit.git
cd agent-toolkit
node scripts/install.mjs --doctor    # 前提診断
node scripts/install.mjs --diff      # 設置予定の差分確認
node scripts/install.mjs --apply     # 設置実行
```

Codex は `--runtime codex`、両 runtime は `--runtime all` を各コマンドへ追加します。省略時は Claude のみで、従来動作を維持します。既存 JSON はバックアップ後に merge され、不正な場合は変更せず停止します。

## 既存環境の更新

```bash
git pull
node scripts/install.mjs --diff      # 設置先との差分確認（ローカル改変があれば停止して報告）
node scripts/install.mjs --apply     # 承認後に反映
```

詳細（初回設定の全手順・機械強制フックの説明等）はリポジトリ直下の `README.md` / `CLAUDE.md` を参照してください。
