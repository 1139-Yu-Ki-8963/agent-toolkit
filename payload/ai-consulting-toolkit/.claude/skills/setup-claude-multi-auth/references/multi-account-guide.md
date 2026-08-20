# Claude Code — 複数アカウント / Bedrock 切り替え運用手順

Claude Code CLI で複数の Anthropic アカウントと Amazon Bedrock を切り替えて使う手順。

## Claude Code の設定スコープ

Claude Code の設定は 3 層に分かれており、上位が下位を上書きする。

| 優先度 | ファイル | スコープ | 内容 |
|---|---|---|---|
| 高 | `<プロジェクト>\.claude\settings.local.json` | プロジェクト × 個人 | 個人のローカルオーバーライド。gitignore 対象 |
| 中 | `<プロジェクト>\.claude\settings.json` | プロジェクト × チーム | チーム共有の設定。git 管理対象 |
| 低 | `~\.claude\settings.json` | ユーザーグローバル | 全プロジェクト共通の個人設定。認証情報もここに保存される |

本手順ではユーザーグローバル設定（`~\.claude\`）を切り替え可能にする。プロジェクト設定（`<プロジェクト>\.claude\`）は切り替えの影響を受けない。

## 仕組み

Claude Code は通常 `~\.claude\` に認証情報・設定・セッション履歴を保存する。環境変数 `CLAUDE_CONFIG_DIR` を指定すると、この保存先を任意のディレクトリに変更できる。ディレクトリごとに認証情報・設定・履歴が完全に隔離されるため、アカウント数だけディレクトリを用意すれば切り替えが成立する。

### デフォルト環境とサブ環境

デスクトップアプリと VS Code 拡張は `CLAUDE_CONFIG_DIR` を無視し、常に `~\.claude\` を参照する。そのため `~\.claude\` には最も使用頻度の高いアカウントを割り当て、デフォルト環境とする。それ以外のアカウントは `CLAUDE_CONFIG_DIR` で切り替えるサブ環境として管理する。

### 命名規則

ディレクトリ名は {プロバイダー}-{識別情報} で統一する。

```
~\.claude\                          ← デフォルト環境（デスクトップアプリ・VS Code もここを使う）
~\.claude-anthropic-{識別情報}\     ← Anthropic サブ環境
~\.claude-bedrock-{識別情報}\       ← Bedrock サブ環境
```

例：

```
~\.claude\                          ← Anthropic 個人アカウント（デフォルト）
~\.claude-anthropic-work\           ← Anthropic 業務アカウント
~\.claude-bedrock-dev\              ← Bedrock 開発環境
```

## 前提条件

- Windows 10 22H2 以降
- Anthropic アカウントを 2 つ保有
- Bedrock API キーを保有

## Bedrock の認証方式

Bedrock の credentials には複数の形式がある。形式によって settings.json の書き方が異なる。

| credentials の形式 | 識別方法 | 使用する環境変数 |
|---|---|---|
| Bedrock API キー | AccessKey が {ユーザー名}-at-{AWSアカウントID} の形式 | `AWS_BEARER_TOKEN_BEDROCK`（値は SecretKey。`ABSK` で始まる文字列） |
| IAM アクセスキー | AccessKey が `AKIA` で始まる | `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` |
| SSO / Identity Center | `aws sso login` で取得する一時クレデンシャル | `AWS_PROFILE` |

## Step 1 — Claude Code CLI のインストール

Claude Code CLI がインストール済みか確認する。

```powershell
claude --version
```

バージョンが表示されればスキップ。コマンドが見つからない場合はインストールする。

```powershell
irm https://claude.ai/install.ps1 | iex
```

インストール後、`claude` コマンドが認識されない場合は PATH を確認する。インストーラーが表示したパス（通常 `~\.local\bin`）を PATH に追加する。

```powershell
$binPath = "$env:USERPROFILE\.local\bin"
$currentPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
if ($currentPath -notlike "*\.local\bin*") {
    [System.Environment]::SetEnvironmentVariable("PATH", "$binPath;$currentPath", "User")
}
```

PATH 変更後はターミナルを再起動し、`claude --version` で確認する。

## Step 2 — デフォルト環境のログイン

`~\.claude\` がデフォルト環境になる。最も使用頻度の高いアカウントでログインする。

```powershell
claude
```

ブラウザが開くのでデフォルトにしたいアカウントでログイン。認証完了後、セッション内で `/exit` で終了。

## Step 3 — サブ環境の設定ディレクトリ作成

デフォルト以外の環境を作成する。ディレクトリ名は運用に合わせて変更すること。

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.claude-anthropic-work"
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.claude-bedrock-dev"
```

## Step 4 — Bedrock サブ環境の設定ファイル作成

Bedrock 環境のみ、設定ファイルに provider と credentials を書く。credentials の形式に応じて以下のいずれかを使う。

### Bedrock API キーの場合

AccessKey が {ユーザー名}-at-{AWSアカウントID} の形式の場合。`AWS_BEARER_TOKEN_BEDROCK` には **SecretKey**（`ABSK` で始まる文字列）を設定する。AccessKey は不要。

```json
{
  "env": {
    "CLAUDE_CODE_USE_BEDROCK": "1",
    "AWS_REGION": "ap-northeast-1",
    "AWS_BEARER_TOKEN_BEDROCK": "自分の SecretKey（ABSKで始まる文字列）"
  }
}
```

### IAM アクセスキーの場合

AccessKey が `AKIA` で始まる場合。

```json
{
  "env": {
    "CLAUDE_CODE_USE_BEDROCK": "1",
    "AWS_REGION": "ap-northeast-1",
    "AWS_ACCESS_KEY_ID": "自分の AccessKey",
    "AWS_SECRET_ACCESS_KEY": "自分の SecretKey"
  }
}
```

Anthropic サブ環境には設定ファイル不要。OAuth ログインだけで動作する。

## Step 5 — サブ環境の初回ログイン

### Anthropic サブ環境

```powershell
$env:CLAUDE_CONFIG_DIR = "$env:USERPROFILE\.claude-anthropic-work"
claude
```

ブラウザが開くので該当アカウントでログイン。認証完了後、セッション内で `/exit` で終了。

### Bedrock サブ環境

```powershell
$env:CLAUDE_CONFIG_DIR = "$env:USERPROFILE\.claude-bedrock-dev"
claude
```

Step 4 で settings.json に credentials を書いているため、ブラウザ認証は不要。セッション内で `/status` を実行し、`Provider: Amazon Bedrock` と表示されれば成功。

## 日常の使い方

デフォルト環境はそのまま起動する。

```powershell
claude
```

サブ環境は `CLAUDE_CONFIG_DIR` を設定してから起動する。

```powershell
# Anthropic 業務アカウント
$env:CLAUDE_CONFIG_DIR = "$env:USERPROFILE\.claude-anthropic-work"
claude

# Bedrock 開発環境
$env:CLAUDE_CONFIG_DIR = "$env:USERPROFILE\.claude-bedrock-dev"
claude
```

別ターミナルで異なる環境を同時に起動することも可能。

## 確認方法

セッション内で `/status` を実行する。

- Anthropic の場合：`Provider: Anthropic` と表示
- Bedrock の場合：`Provider: Amazon Bedrock` と表示

## モデル版の固定（Bedrock のみ）

Bedrock ではモデルエイリアス（opus, sonnet 等）が最新版に自動追従しない。Claude Code 内部にプロバイダー別のハードコードされたデフォルトがあり、Anthropic API より古いバージョンに固定される。

2026-06-22 時点のデフォルト：

| エイリアス | Anthropic API | Bedrock デフォルト |
|---|---|---|
| opus | Opus 4.8 | **Opus 4.6** |
| sonnet | Sonnet 4.6 | **Sonnet 4.5** |

最新モデルを使うには、Bedrock サブ環境の `settings.json` の `env` に明示的にモデル ID を追加する。モデル ID にはリージョンプレフィックスが必要で、`AWS_REGION` に合わせて変える。

| リージョン | プレフィックス |
|---|---|
| us-east-1, us-west-2 等 | `us.anthropic.` |
| ap-northeast-1（東京） | `jp.anthropic.` |
| eu-west-1 等 | `eu.anthropic.` |

東京リージョンの例：

```json
"ANTHROPIC_DEFAULT_OPUS_MODEL": "jp.anthropic.claude-opus-4-8",
"ANTHROPIC_DEFAULT_SONNET_MODEL": "jp.anthropic.claude-sonnet-4-6"
```

確認方法：セッション内で `/model` を実行し、実際に解決されるモデル ID を確認する。Anthropic API 側のデフォルトと一致しない場合は上記の環境変数で固定する。

## 環境の追加・削除

### 追加時に必要な情報

| # | 項目 | 説明 |
|---|---|---|
| 1 | プロバイダー | Anthropic または Bedrock |
| 2 | 識別情報 | ディレクトリ名に使う任意の文字列 |
| 3 | 認証情報 | Bedrock の場合のみ必要。Bedrock API キーなら SecretKey（`ABSK` で始まる）、IAM なら AccessKey + SecretKey。形式は「Bedrock の認証方式」を参照 |

### 追加手順

1. `~\.claude-{プロバイダー}-{識別情報}\` ディレクトリを作成
2. Bedrock なら `settings.json` に credentials を書く
3. `CLAUDE_CONFIG_DIR` を指定して `claude` を起動し初回ログイン

### 削除

対象の `~\.claude-{プロバイダー}-{識別情報}\` ディレクトリを削除するだけ。他の環境に影響しない。

## 制約

- セッション内でのプロバイダー切り替えは不可。新セッション開始が必要
- デスクトップアプリと VS Code 拡張は `CLAUDE_CONFIG_DIR` に対応していない。常に `~\.claude\`（デフォルト環境）を使用する
- Bedrock では WebSearch ツールが利用できない
