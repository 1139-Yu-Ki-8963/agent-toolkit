---
name: managing-github-issues
description: |
  GitHub issue の起票・選択着手・スコープ検証のモードハブ。
  TRIGGER when: 「issue作成」「起票」「issueにして」「issueを選んで実装」「issue一覧から着手」「スコープ検証」「issue範囲チェック」、issue-N ブランチで commit 前。
  SKIP: PRレビュー（→reviewing-single-pr-with-inline-comments）、issue番号指定済みのブランチ作成（→parallel-dev-worktree）、コミット分割（→grouping-commits）。
invocation: managing-github-issues
type: orchestration
allowed-tools: [Bash, Read, Write, Edit, Grep, AskUserQuestion]
---

# GitHub issue ライフサイクル管理ハブ

GitHub issue の起票（create）・選択着手（pick）・スコープ検証（verify）を 1 つの動線で担うモードハブ。旧 `creating-issue` / `picking-issues` / `verifying-issue-scope` を統合し、モードを判定した上でモードごとの `references/` を必要時のみロードする。

## モード判定

ユーザー発話・状況から 1 モードを判定し、該当 references のみを Read する。

| ユーザー発話・状況 | モード | ロードする references | 旧スキル（Type 性質） |
|---|---|---|---|
| 起票・issue作成・issueにして・バグ報告を作成 | create | `references/creating.md` | creating-issue（action） |
| issueを選んで実装・一覧から着手・どのissueをやるか | pick | `references/picking.md` | picking-issues（gateway） |
| スコープ検証・issue範囲チェック・issue-N ブランチで commit 前 | verify | `references/verifying.md` | verifying-issue-scope（gate） |

判定が曖昧な場合は AskUserQuestion で確認する。モード間の自動連鎖はない（各モードは独立に完結する）。

## 共通の前提

- `gh` インストール済み・認証済み
- モード別の詳細（Phase 構成・完了条件・ループ設計・注意事項）は各 references が正本。本体ハブはモード判定とロード指示のみを行う
- `scripts/check-issue-scope.sh` は settings.json 登録の PreToolUse hook。issue ブランチでの一括 `git add -A` / `git add .` を block し、スコープを意識した個別 staging を促す（verify モードの突合処理はエージェント手順であり、この script ではない）

## 完了条件

| モード | 完了条件 |
|---|---|
| create | `gh issue create` が成功し issue URL が表示されている |
| pick | 選択された全 issue に対して対応スキルが起動されている |
| verify | 全 staged ファイルの判定（OK / 要確認 / NG）が報告されている |
| **Goal** | 判定したモードの references に定義された完了条件をすべて満たしている |

## ループ設計

反復は create モードのみ（修正要求ループ・上限 3 回・「このまま登録する」選択で収束停止・同一修正依頼 2 回連続で発散停止）。pick / verify は反復構造を持たない単一パス。

## 完了報告

`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格に従う。モード固有の検証行は各 references の完了報告節を参照。

## 予想を裏切る挙動

- 本体ハブだけでは作業できない。必ずモード判定 → 該当 references を Read してから着手する
- 旧 3 スキル名での呼び出し・発火ログは `skill-aliases.yml` で本スキルに正規化される
- verify モードは `git restore --staged` を自動実行しない（候補提示のみ）

## 参照資料

- `references/creating.md` — create モード本文（起票フロー Phase 1〜4）
- `references/picking.md` — pick モード本文（issue 選択 → フロー起動 Phase 1〜5）
- `references/verifying.md` — verify モード本文（スコープ突合 Phase 1〜5）
- `references/managing-github-issues-guide.html` — ポータル用スキルガイド
