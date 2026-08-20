# ディレクトリ構成ガード（DIRECTORY-STRUCTURE）

リポジトリのルート直下ディレクトリを許可リストで管理し、無秩序なフォルダ増殖を防止する規約。

## 概要

- ルート直下のディレクトリ名を各リポジトリの許可リストで管理する
- 許可リスト外のディレクトリ作成を検出し、AskUserQuestion で承認を求める
- 許可済み親ディレクトリ内の子ディレクトリ作成にも確認を注入する
- block（exit 2）はしない。advisory（exit 0）+ Claude 側の確認フローで制御する

## 許可リストの配置

正: 各リポジトリの `<repo>/.claude/rules/always/project-context/rule.md` 内の `## ルート直下許可ディレクトリ` 節に許可リストをテーブルで記載する（サブディレクトリ許可リストは `### <親ディレクトリ名>` 節）。

フォールバック（移行互換）: project-context/rule.md に当該節が無い場合、専用ファイル（新形式 `<repo>/.claude/rules/always/placement/directory-structure/rule.md` → 旧形式 `<repo>/.claude/rules/directory-structure-rules/rule.md` の順）を解決先とする。

### 記載フォーマット

```markdown
## ルート直下許可ディレクトリ

| ディレクトリ名 | 用途 |
|---|---|
| src | ソースコード |
| docs | ドキュメント |
```

本グローバル規約は「何を守るか・違反時にどうするか」を定義する。「どのディレクトリを許可するか」は各リポジトリ側の project-context/rule.md（またはフォールバック先の専用ファイル）が持つ。

## hook の動作

### 検出対象

PreToolUse(Bash) で `mkdir` コマンドを検出する。

### 判定フロー

1. `mkdir` の対象パスからリポジトリルートからの相対パスを算出する
2. ルート直下の場合:
   - `${cwd}/.claude/rules/always/project-context/rule.md` の `## ルート直下許可ディレクトリ` 節を読む（無ければ専用ファイルへフォールバック）
   - 許可リストに存在する → `[DIR-STRUCTURE-OK]` を注入（通過）
   - 許可リストに存在しない → `[DIR-STRUCTURE-CHECK]` を注入
   - 許可リストファイルが存在しない → `[DIR-STRUCTURE-NO-LIST]` を注入
3. ルート直下以外（子ディレクトリ）:
   - `[DIR-STRUCTURE-CHILD]` を注入

### 既存 hook との関係

`dispatch-pre-bash-checks.sh`（legacy バケット）の mkdir 命名チェック（ケバブケース advisory）は併用する。本 hook は許可リスト照合を担当し、命名チェックは既存 hook に委ねる。

## 機械強制

| timing | スクリプト | 注入タグ | 挙動 |
|---|---|---|---|
| PreToolUse(Bash) | `check-mkdir-allowlist.sh`（rules-bash-runner 経由） | `[DIR-STRUCTURE-OK]` | 許可リスト内。通過（exit 0） |
| PreToolUse(Bash) | `check-mkdir-allowlist.sh`（rules-bash-runner 経由） | `[DIR-STRUCTURE-CHECK]` | ルート直下またはサブ許可リスト外。advisory 注入（exit 0） |
| PreToolUse(Bash) | `check-mkdir-allowlist.sh`（rules-bash-runner 経由） | `[DIR-STRUCTURE-CHILD]` | 子ディレクトリ作成。advisory 注入（exit 0） |
| PreToolUse(Bash) | `check-mkdir-allowlist.sh`（rules-bash-runner 経由） | `[DIR-STRUCTURE-NO-LIST]` | 許可リストファイルが存在しない。advisory 注入（exit 0） |
| PreToolUse(Write\|Edit) | `check-write-implicit-dir.sh` | `[DIR-STRUCTURE-WRITE-GUARD]` | Write による暗黙のディレクトリ作成を検出。advisory 注入（exit 0） |

## 違反検知時の手順

### `[DIR-STRUCTURE-CHECK]` 受信

1. AskUserQuestion で以下を確認する:
   - 「`<dirname>` を新規作成します。許可リスト（ルート直下またはサブ許可リスト）に存在しません。作成しますか？」
   - 選択肢: (A) 作成して許可リストにも追加 / (B) 作成するが許可リストには追加しない / (C) 中止
2. (A) の場合: mkdir 実行後、`<repo>/.claude/rules/always/project-context/rule.md` の `## ルート直下許可ディレクトリ` 節（フォールバック先を使っている場合は専用ファイル）の許可テーブルに追記する
3. (B) の場合: mkdir のみ実行する
4. (C) の場合: mkdir を中止する

### `[DIR-STRUCTURE-CHILD]` 受信

1. AskUserQuestion で以下を確認する:
   - 「`<parent>/<dirname>` を新規作成します。作成しますか？」
   - 選択肢: (A) 作成する / (B) 中止
2. (A) の場合: mkdir を実行する
3. (B) の場合: mkdir を中止する

### `[DIR-STRUCTURE-NO-LIST]` 受信

1. 許可リストが未整備であることをユーザーに伝える
2. AskUserQuestion で以下を確認する:
   - 「このリポジトリに許可リストがありません。作成しますか？」
   - 選択肢: (A) 許可リストを作成してから mkdir する / (B) 許可リストなしで mkdir する / (C) 中止
3. (A) の場合: 現在のルート直下ディレクトリを `ls -d */` で取得し、許可リストの初期値として `rule.md` を作成する

### `[DIR-STRUCTURE-WRITE-GUARD]` 受信

1. Write ツールが新規ディレクトリを暗黙的に作成しようとしていることを確認する
2. AskUserQuestion で以下を確認する:
   - 「Write により `<dirname>` が暗黙的に作成されます。作成しますか？」
   - 選択肢: (A) 作成して許可リストにも追加 / (B) 作成するが許可リストには追加しない / (C) 中止（Write を取りやめる）
3. mkdir の場合と同じフローで処理する

## プロジェクト上書き

- 上書き可否: 委譲可（値のみ）
- 受け口: 正は `<repo>/.claude/rules/always/project-context/rule.md` の `## ルート直下許可ディレクトリ` 節。専用ファイル（新形式 `<repo>/.claude/rules/always/placement/directory-structure/rule.md` → 旧形式 `<repo>/.claude/rules/directory-structure-rules/rule.md`）は移行互換フォールバックとして解決される
- 優先順位: project-context/rule.md に当該節があればそれを優先する。無ければ hook は同ディレクトリの `shared/rule-resolver.sh`（`resolve_rule_file`）で新形式 → 旧形式の順にフォールバック解決する。枠組み（advisory + AskUserQuestion のフロー・違反時手順）はグローバルが常に正

設計判断・経緯の記録は同ディレクトリの `design-notes.txt` を参照（非注入サイドカー）。

## 関連

- `~/.claude/rules/always/infra/pre-bash-dispatch/rule.md` — mkdir 命名規則チェック（ケバブケース advisory）
- `~/.claude/rules/scoped/agent-config/hooks/rule.md` — hook 配置 4 象限（本 hook の配置根拠）
- `~/.claude/rules/always/placement/file-guard/rule.md` — ファイル配置ガード（ディレクトリではなくファイルレベルの制御）
