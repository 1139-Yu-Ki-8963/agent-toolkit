---
paths:
  - "**/CLAUDE.md"
  - "**/.claude/**"
---

# CLAUDE.md 保護規約（CLAUDE-MD-GUARD）

エージェントによる CLAUDE.md への無断書き込みと、存在しないセクション番号参照を2層で機械強制する。

## 禁止事項

### 禁止1: CLAUDE.md への無断書き込み

`~/.claude/CLAUDE.md` を Write / Edit / MultiEdit することは、ユーザーの明示的な指示なしに禁止する。

CLAUDE.md はユーザーが管理する設定資産であり、エージェントが自律的に内容を追加・変更することを想定していない。
追加すべき内容がある場合は、scoped/agent-config/placement/rule.md の判定フローに従い rule / skill / hook のいずれかに配置する。

### 禁止2: ファントム §N 参照

SKILL.md・rule ファイル・hook スクリプトなど、エージェントが書くすべてのファイルで次のパターンを使用することを禁止する:

```
CLAUDE.md §N        ← 禁止（§ セクションは CLAUDE.md に存在しない）
CLAUDE.md の第N章   ← 禁止
CLAUDE.md chapter N ← 禁止
```

**理由**: CLAUDE.md に § 番号付きセクションは一切存在しない。このような参照は読み手を架空のセクションに誘導するだけで、機能しない。

**代替**: 参照先として伝えたい規約や手順は、それ自体を rule ファイルや SKILL.md に切り出し、そのパスで参照する。

```
# ✗ 禁止
"対処: CLAUDE.md §13 を参照"

# ✓ 許可
"対処: ~/.claude/rules/parallel-dev-worktree-rules/rule.md を参照"
"対処: ~/agent-home/skills/parallel-dev-worktree/SKILL.md を参照"
```

## 機械強制

| layer | 対象 | 注入タグ | 挙動 |
|---|---|---|---|
| permissions.ask | Write/Edit/MultiEdit(~/.claude/CLAUDE.md) | — | ユーザー承認ダイアログを表示（ゲート役） |
| PreToolUse hook | Write\|Edit\|MultiEdit | `[CLAUDE-MD-WRITE-WARN]` | CLAUDE.md への書き込みを検知し警告（block しない） |
| PreToolUse hook | Write\|Edit\|MultiEdit | `[CLAUDE-MD-REF-BLOCK]` | ファントム §N 参照を exit 2 で block |

hook スクリプト: `~/.claude/rules/scoped/agent-config/claude-md/check-claude-md-guard.sh`

CLAUDE.md 書き込みは `permissions.ask` がゲート役を担う。ユーザーが承認すれば通過する。hook は警告のみで block しない。
ファントム §N 参照は正当な理由がないため hook が block する。再帰防止: 同セッション 3 連続 block で auto-release。

## 違反検知時の手順

### `[CLAUDE-MD-WRITE-WARN]` 受信

1. ユーザーの明示的な指示で CLAUDE.md を編集している場合 → permissions.ask の承認ダイアログでユーザーが判断する。hook 警告は無視してよい
2. ユーザーの指示なく自律的に書こうとした場合 → 書き込みを中止し、scoped/agent-config/placement/rule.md の判定フローで正しい配置先を選ぶ

### `[CLAUDE-MD-REF-BLOCK]` 受信

1. block されたファイルの対象箇所を確認する
2. `CLAUDE.md §N` / `CLAUDE.md の第N章` パターンを削除する
3. 規約の定義が存在する rule / skill のパスに差し替える（存在しない場合は rule を新規作成する）
4. ファントム参照は「ドキュメントが無いルールを参照している状態」なので、参照先を作ってから修正する

## プロジェクト上書き

- 上書き可否: 一律適用
- 理由: CLAUDE.md 保護はグローバル設定資産の保護であり、プロジェクト側の迂回を想定しないため受け口を設けない

設計判断・経緯の記録は同ディレクトリの `design-notes.txt` を参照（非注入サイドカー）。

## 関連

- `~/.claude/rules/scoped/agent-config/placement/rule.md` — どこに書くかの判定フロー
- `~/.claude/rules/scoped/agent-config/hooks/rule.md` — hook の配置規約
