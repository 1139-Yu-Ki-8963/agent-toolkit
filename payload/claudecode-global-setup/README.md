# claudecode-global-setup

PC 全体の Claude Code 環境（`~/agent-home/` と `~/.claude/`）をセットアップするための配布単位です。個別プロジェクト向けのツールキット（`ai-consulting-toolkit` や `reverse-docs-skills`）とは区別され、このフォルダの中身だけで「その PC で Claude Code を使うための共通基盤」が揃います。

## 中身

| フォルダ | 設置先 |
|---|---|
| `agent-home/` | `~/agent-home/`（ディレクトリ全体をミラー） |
| `claude-config/` | `~/.claude/`（ファイル単位で設置） |

## 設置手順

agent-toolkit リポジトリ全体を clone したうえで、リポジトリ直下から実行してください（このフォルダ単体の clone では動作しません）。

```bash
git clone https://github.com/1139-Yu-Ki-8963/agent-toolkit.git
cd agent-toolkit
node scripts/install.mjs --doctor    # 前提診断
node scripts/install.mjs --diff      # 設置予定の差分確認
node scripts/install.mjs --apply     # 設置実行
```

## 既存環境の更新

```bash
git pull
node scripts/install.mjs --diff      # 設置先との差分確認（ローカル改変があれば停止して報告）
node scripts/install.mjs --apply     # 承認後に反映
```

詳細（初回設定の全手順・機械強制フックの説明等）はリポジトリ直下の `README.md` / `CLAUDE.md` を参照してください。
