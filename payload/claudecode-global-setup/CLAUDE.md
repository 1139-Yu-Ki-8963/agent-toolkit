# claudecode-global-setup / CLAUDE.md（AI 向け説明）

このフォルダは、PC 全体の Claude Code 環境（`~/agent-home/` と `~/.claude/`）の配布単位です。`payload/` 直下の他のフォルダ（`ai-consulting-toolkit` / `reverse-docs-skills`）は個別プロジェクト向けツールキットであり、本フォルダとは役割が異なります。

## 中身の対応表

| パス | 設置先 | 備考 |
|---|---|---|
| `agent-home/` | `~/agent-home/` | ディレクトリ全体をミラー |
| `claude-config/CLAUDE.md` | `~/.claude/CLAUDE.md` | 既存があれば上書きしない |
| `claude-config/settings-hooks.json` | `~/.claude/settings.json` | 既存の hooks セクションへ merge |

## 実処理の委譲先

設置・更新の実作業はこのフォルダの中には置かず、リポジトリ直下の `scripts/install.mjs` に委譲しています。このフォルダ単体を直接操作するスクリプトは存在しません。設置・更新手順はリポジトリ直下の `CLAUDE.md` の「設置マッピング」節を参照してください。

## 正本との関係

`agent-home/` と `claude-config/` の中身は private 環境の正本（`~/agent-home/`・`~/.claude/`）のコピーです。**このフォルダ配下のファイルを直接手編集しないでください。** 正本を編集したうえで、リポジトリ直下の `scripts/sync-payload.mjs --check` / `--apply` 経由で反映してください。詳細はリポジトリ直下の `CLAUDE.md` の「payload 同期機構」節を参照してください。
