---
name: grouping-commits
description: "変更分析しグループ化・単一目的コミット作成。 TRIGGER when: 「コミット分割」「変更グループ化」「まとめてコミット」と言われた時。 SKIP: コミット操作なし（→ rules: always/naming/commit-branch）。"
invocation: grouping-commits
execution: subagent-compatible
type: action
allowed-tools: ["Bash", "Read", "Write", "Edit"]
---

# スマートコミット — インテリジェントGitコミット作成

変更内容を自動的に分析し、関連する変更ごとにグループ化して適切なコミットを作成します。

## 実行方針（コスト最適化）

グループ分けの確定後、コミット実行（`git add` / `git commit` の発行）は **worker-haiku へ Agent 委譲する**（機械的な定型 git 操作のため。subagent-delegation-rules の委任先テーブルと整合）。メインエージェントが直接実行するのはグループ分けの判断と最終確認のみ。ただし対象が 1 グループ・数ファイルの単純ケースは委譲コストが上回るため直接実行してよい。

## 前提条件

- [ ] [PRE-001] Gitリポジトリの確認
  - 確認方法: `git rev-parse --is-inside-work-tree`
  - 期待: Gitリポジトリ内であること

- [ ] [PRE-002] 変更ファイルの存在確認
  - 確認方法: `git status --short`
  - 期待: 変更されたファイルが存在すること

- [ ] [PRE-003] 機密情報チェック
  - 確認方法: 変更ファイル一覧から`.env`、`credentials.json`などを検出
  - 期待: 機密ファイルがステージングされていないこと

- [ ] [PRE-004] git author 設定の確認
  - 確認方法: `git var GIT_AUTHOR_IDENT`
  - 期待値: `1139-Yu-Ki-8963 <63326271+1139-Yu-Ki-8963@users.noreply.github.com>`（check-git-author-allowlist.sh 白リスト・PR #11 で実在アカウントへ統一済み）
  - NG 時の対処: `~/.gitconfig` の `[user]` セクションを `name = 1139-Yu-Ki-8963` / `email = 63326271+1139-Yu-Ki-8963@users.noreply.github.com` に直す（local config・env 経由の上書きは禁止）
  - 許可リスト外の author は PreToolUse hook が `[GIT-AUTHOR-BLOCK]` exit 2 で block する

# Phase 1: 変更状況の確認

## 現在のブランチ確認

```bash
git rev-parse --abbrev-ref HEAD
```

## 変更ファイル一覧の取得

```bash
git status          # 全体のステータスを確認
git status --short  # 変更ファイルの詳細リスト
```

## 変更内容の詳細確認

```bash
git diff --cached   # stagedの変更内容
git diff            # unstagedの変更内容
```

# Phase 2: 変更のグループ化

変更内容とファイルタイプに基づいて、`references/grouping-rules.md` のグループ化ルールに従いグループ化します。

## グループ化の実行

Claude は変更ファイルを上記ルールに従って分類し、グループごとにリスト化する。

## issue-N ブランチ時の 1 issue 範囲モード（特例）

ブランチ名が `issue-<番号>` の場合、本スキルの動作モードを切り替える:

1. **グルーピング無効化**: 同一 issue の作業として全変更を 1 コミットにまとめる
   （本来のグルーピングは複数コミットを生むが、issue-N ブランチでは原則 1 PR = 1 コミットを保つ）
2. **`managing-github-issues`（verify モード）の事前呼び出し**: `git add` の前に必ず `managing-github-issues` スキルを verify モードで実行し、
   staged ファイルが対象 issue の範囲内かを `gh issue view` の body と突合する
3. **🔴 NG ファイルの除外**: `managing-github-issues`（verify モード）が 🔴 NG（ブラックリスト or 範囲外）と
   判定したパスは `git restore --staged <PATH>` で除外してから `git commit`

判定例:

```bash
branch=$(git rev-parse --abbrev-ref HEAD)
if [[ "$branch" =~ ^issue-([0-9]+)$ ]]; then
  # 1 issue 範囲モード
  # → managing-github-issues（verify モード）を呼び出し
  # → 🔴 NG があれば git restore --staged で除外
  # → 残りを 1 コミットにまとめる
fi
```

ルーティン（`issue-resolver-daily` / `coverage-improvement-daily` /
`design-doc-sync-daily` / `pr-health-check`）から呼ばれた場合も同モードを適用する。

# Phase 3: コミットの実行

各グループごとに以下を実行します：

## 機密情報の最終チェック

```bash
# .envファイルのチェック
git status --short | grep -iE '\.env\b|\bcredentials\b|\bsecrets?\b|\.key$|\.pem$|\bid_rsa\b' || echo "機密ファイルなし"
```

## グループごとのコミット作成

各グループに対して：

1. **ファイルのステージング**
```bash
git add [ファイルパス]
```

2. **コミットメッセージの生成と実行**
- 簡潔で明確な日本語メッセージ（**25字以内**）
- 変更の「なぜ」「何を」を記述
- 1行で完結

```bash
git commit -m "[prefix]: [変更内容の説明]"
```

3. **コミット確認**
```bash
git log --oneline -1
```

## エラーハンドリング

コミットが失敗した場合：
- エラー内容を確認: `git status`
- 失敗理由を説明
- 次のグループに進む

# Phase 4: 最終確認

## 残りの変更確認

```bash
git status
```

## 最近のコミット履歴

```bash
git log --oneline -5
```

## 完了報告

`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（作業報告型）に従う。

固有の検証行:
- 作成されたコミット数
- 未コミットのファイルが残っている場合はその理由（未実施・制約に記載）

## 検証項目

- [ ] [VAL-001] コミット作成の確認
  - 確認方法: `git log --oneline -5`
  - 確認内容: 新しいコミットが作成されている
  - 成功条件: 想定されたグループ数のコミットが作成されている

- [ ] [VAL-002] 機密情報の非包含確認
  - 確認方法: コミット履歴とdiffの確認
  - 確認内容: `.env`、credentials等がコミットされていない
  - 成功条件: 機密ファイルがコミットに含まれていない

- [ ] [VAL-003] 単一目的コミットの確認
  - 確認方法: 各コミットの内容確認
  - 確認内容: 各コミットが関連する変更のみを含む
  - 成功条件: コミットが論理的にグループ化されている

- [ ] [VAL-004] 未コミットファイルの確認
  - 確認方法: `git status`
  - 確認内容: 意図的に残されたファイル以外は全てコミット済み
  - 成功条件: 残存する未コミットファイルがある場合、その理由が完了レポートに明記されている

## 重要な注意事項

1. **1グループ = 1コミット**: 関連する変更をまとめ、1つのコミットとして作成する。
2. **単一目的コミット**: 各コミットは独立して意味を持つこと
3. **機密情報チェック**: Claude は `.env`、`credentials.json` などを絶対にコミットしない。
4. **実行前の状態確認**: 最初に現在のブランチと変更状況を表示
5. **エラーハンドリング**: コミットが失敗した場合は理由を説明し、次のグループに進む

## 予想を裏切る挙動

- staging 状態を確認せず commit すると無関係な変更が混入する — `git diff --staged` で必ず差分を確認してからコミット

## 他スキルとの連携

| スキル | 役割分担 |
|---|---|
| 命名規約（rules: always/naming/commit-branch） | コミットメッセージの正規ルール（type / subject / 25文字制限）の定義元。本スキルはルールを参照して `git commit -m` を実行する側 |
| `reviewing-public-readiness` | コミット作成直前に PreToolUse から並行発火（`[PUBLISH-AUTHOR]` `[PUBLISH-SAFETY]` `[PUBLISH-SAFETY-FULL]`）し、機密ファイル名・author 情報・公開リスクを警告。CRITICAL 検出時は本スキルのコミット作成を中断し、ユーザーに対処を促す |
