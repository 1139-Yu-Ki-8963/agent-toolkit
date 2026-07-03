# agent-toolkit / CLAUDE.md（リポジトリ作業手順書）

このファイルは **agent-toolkit リポジトリを clone して Claude Code を起動した AI 向けの手順書** です。
配布される CLAUDE.md の実体は `payload/claude-config/CLAUDE.md` にあります（二役分離）。

## 設置マッピング

| payload パス | 設置先 | 備考 |
|---|---|---|
| `payload/agent-home/` | `~/agent-home/` | ディレクトリ全体をミラー |
| `payload/claude-config/CLAUDE.md` | `~/.claude/CLAUDE.md` | 既存があれば上書きしない |
| `payload/claude-config/settings-hooks.json` | `~/.claude/settings.json` | 既存の hooks セクションへ merge |

設置・更新の実作業は `scripts/install.mjs` が担う。インターフェース:

```
node scripts/install.mjs --doctor    # 前提診断（Node.js / 必須コマンド / 既存設定の確認）
node scripts/install.mjs --diff      # 設置予定を差分で提示（書き込み禁止）
node scripts/install.mjs --apply     # 設置実行（settings.json はバックアップ後 merge）
node scripts/install.mjs --target <dir>   # テスト用: 設置先を <dir> に変更して実行
```

---

## 初回設定（新しい PC）

1. **前提診断**: `node scripts/install.mjs --doctor` を実行し、必須コマンドの不足や既存設定の競合を確認する
2. **差分確認**: `node scripts/install.mjs --diff` で設置予定の一覧をユーザーに提示し、承認を得る
3. **設置実行**: `node scripts/install.mjs --apply` を実行する
   - `~/.claude/settings.json` は自動バックアップ後に hooks セクションを merge する
   - `~/.claude/CLAUDE.md` が既存の場合は上書きせず、差分をユーザーに報告する
   - `--apply` の最後に `manage-portal.mjs generate` → `verify` を自動実行し、exit 0 を受け入れ判定とする
4. **hook 発火スモーク**: 設置後に `~/agent-home/skills/managing-agent-configs/SKILL.md` を 1 行編集し、`[MANAGING-REVIEW-REQUIRED]` advisory が注入されることを確認する

---

## 更新（2 回目以降）

1. `git pull` で最新を取得する
2. `node scripts/install.mjs --diff` で設置先との差分を提示する
   - **設置先にローカル改変がある場合は停止し、ユーザーに内容を報告する**（強制上書き禁止）
3. ユーザーの承認後に `node scripts/install.mjs --apply` を実行する
4. `manage-portal.mjs verify` が exit 0 で完了することを受け入れ判定とする

---

## このリポジトリで開発する人向け

リポジトリ直下の `.claude/settings.json` に gate hook 2 本が登録済みです。managed ファイル
（`payload/agent-home/skills/*/SKILL.md` 等）を編集すると `[MANAGING-REVIEW-REQUIRED]` が
advisory 注入され、テスト完了マーカーがない状態の `git commit` は exit 2 で block されます。

commit 前に `payload/agent-home/skills/managing-agent-configs/scripts/manage-portal.mjs verify`
を実行して 7 検査が全て PASS することを確認してから commit してください。

配布物の同期元は private リポジトリの agent-home です。AT への変更は agent-home 側の正本と
齟齬が生じないよう、design/ HTML と `references/` conventions.md の両方を更新してください。
