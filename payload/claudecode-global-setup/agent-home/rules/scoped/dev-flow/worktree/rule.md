---
paths:
  - "src/**"
  - "app/**"
  - "lib/**"
  - "pages/**"
  - "components/**"
---

# worktree 必須運用規約（WORKTREE-REQUIRED）

orchestrating-dev-flow（統合開発フロー）発動時は worktree 内での作業を必須とする。main ブランチ直接編集はフロー管轄外（調査・質問のみ）に限定する。

## 1. worktree 必須の理由

orchestrating-dev-flow は `.status.json`・session 分離による進捗管理を持つ。main ブランチで 3〜5 セッションが並行稼働するため、worktree なしでは以下が破綻する。

- **複数セッションのファイル競合** — 同一ファイルへの同時書き込みが衝突する
- **進捗ファイル（.flow-progress.json）の混在** — 複数フローの進捗が単一ファイルに上書きされる
- **セッション跨ぎの進捗引き継ぎ** — どのセッションがどのフェーズまで完了したか判別不能になる

## 2. worktree 必須の適用範囲

orchestrating-dev-flow の全 5 ルートに適用する。

| ルート | 適用 |
|---|---|
| フル | 必須 |
| クイック | 必須 |
| ドキュメント | 必須 |
| メンテ | 必須 |
| インシデント | 必須 |

Phase 2（ブランチ準備）で worktree を作成する。worktree 外からの Phase 2 スキップは禁止。

## 3. main ブランチ直接編集が許されるケース

orchestrating-dev-flow の管轄外の作業に限定される。

- **調査・質問応答** — 実装を伴わない調査、ファイルの読み取りのみ
- **グローバル設定の変更** — `~/.claude/` 配下の rules / settings / agents
- **agent-home リポジトリ自体の管理作業** — ポータル更新・スキル追加等

これらの作業は orchestrating-dev-flow を発動しないため、worktree は不要。

## 4. 進捗ファイルの配置

### セッション内進捗

`<worktree>/.claude/markers/${session}/flow-status.json`

- file-guard-rules の `marker_path` ヘルパーと整合する
- SessionEnd の `cleanup-session-markers.sh` でセッション終了時に自動削除される

### セッション跨ぎ進捗

`<worktree>/.flow-progress.json`

- worktree ルートに配置する
- セッション再開時に `.claude/markers/` 内の `flow-status.json` へ復元する
- worktree 削除時に自動消滅する（worktree 内に閉じているため）
- `.gitignore` に追加して commit 対象外にする

## 機械強制

| timing | スクリプト | 注入タグ | 挙動 |
|---|---|---|---|
| PreToolUse(Write\|Edit\|MultiEdit\|NotebookEdit) | `check-worktree-required.sh` | `[WORKTREE-REQUIRED]` | メインツリーでの実装ファイル編集を JSON stdout `decision:block` で block。例外: `~/.claude/*`、`~/agent-home/*`、サブエージェント |

## 違反検知時の手順

orchestrating-dev-flow 発動中に worktree 外で実装ファイルの編集が試みられた場合:

1. 作業を中断する
2. `Skill(parallel-dev-worktree)` を呼び出して worktree を作成する
3. worktree 内で作業を再開する

## プロジェクト上書き

- 上書き可否: 一律適用
- 理由: worktree 分離はセッション管理の枠組みであり、プロジェクトに依存しないため受け口を設けない

設計判断・経緯の記録は同ディレクトリの `design-notes.txt` を参照（非注入サイドカー）。

## 関連

- `~/agent-home/skills/orchestrating-dev-flow/SKILL.md` — 統合開発フローの全体設計
- `~/.claude/rules/always/placement/file-guard/rule.md` — `marker_path` ヘルパーと配置規約（進捗ファイルの配置先と整合）
- `~/.claude/rules/always/local-environment/port-management/rule.md` — worktree スロットとポート管理（worktree 作成時のスロット割当と整合）
- `~/agent-home/skills/parallel-dev-worktree/SKILL.md` — worktree 作成の実行エンジン
- `~/agent-home/skills/parallel-dev-worktree/scripts/check-worktree-required.sh` — メインツリー編集 block の hook 本体（skill 側に配置）
