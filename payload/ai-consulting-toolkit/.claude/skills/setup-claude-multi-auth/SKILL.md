---
name: setup-claude-multi-auth
description: |
  マルチアカウント / Bedrock 環境切り替えを対話形式で自動構築する。
  TRIGGER when: 「Claude Codeのアカウント切り替え設定」「マルチアカウント設定」「Bedrock接続設定」「サブ環境を作って」と言われた時。
  SKIP: 既存環境の認証トークン更新のみの場合（settings.json を直接編集）。Claude Code 自体のインストール（前提条件）。
invocation: setup-claude-multi-auth
type: orchestration
allowed-tools: Read, Write, Edit, Bash, AskUserQuestion
---

# マルチアカウント / Bedrock 環境セットアップ（setup-claude-multi-auth）

`CLAUDE_CONFIG_DIR` 環境変数によるディレクトリ分離で、Claude Code の複数アカウント・Bedrock 環境を切り替える仕組みを対話形式で構築する。根拠文書は `references/multi-account-guide.md`。

## 対話原則

- 全ての質問は AskUserQuestion ツールで選択肢付きに提示する。テキストで番号列挙して手入力させない
- 1回の質問は2個まで。選択肢は4個まで
- 複数選択可能な場合は `multiSelect: true` を使う
- サブフォルダ名・エイリアス名など純粋な自由入力が必要な場合のみ Other で自由入力を受ける

## Phase 1: 環境検出

実行マシンの OS・シェル・既存サブ環境・rcファイルの管理ブロックを検出し、表で報告する。

### Step 1-1: OS・シェルの判定

Bash で `uname -s` を実行し OS を判定する。macOS (`Darwin`) → zsh (`~/.zshrc`)、Windows (MSYS/Cygwin/WSL) → PowerShell (`$PROFILE`)、Linux → bash (`~/.bashrc`)。

**入力**: なし
**完了**: OS・シェル・rcファイルパスが確定している

### Step 1-2: 既存サブ環境の列挙

Bash で `ls -d ~/.claude-* 2>/dev/null` を実行し、`~/.claude-{provider}-{identifier}` パターンに合致するディレクトリを列挙する。各ディレクトリの `settings.json` の有無も確認する。

**入力**: なし
**完了**: 既存サブ環境の一覧（0件を含む）が把握されている

### Step 1-3: 既存管理ブロックの検出

Step 1-1 で確定したrcファイルを Bash (`grep`) で走査し、`# setup-claude-multi-auth managed block start` / `end` マーカーの有無を確認する。マーカーがあれば既存のエイリアス行を抽出する。

**入力**: Step 1-1 のrcファイルパス
**完了**: 管理ブロックの有無と既存エイリアス一覧が把握されている

### Step 1-4: 検出結果の報告

Step 1-1〜1-3 の結果を表で提示する。

**入力**: Step 1-1〜1-3 の結果
**完了**: 検出結果が表で提示されている

完了条件: OS・シェル・rcファイル・既存サブ環境・管理ブロックの状態が把握されている

## Phase 2: 環境仕様の収集

AskUserQuestion で環境の仕様を収集する。Bedrock 未選択時は Step 2-3〜2-5 をスキップする。複数環境選択時は Step 2-2〜2-6 を環境ごとに順次繰り返す。

### Step 2-1: 追加する環境の選択

AskUserQuestion（`multiSelect: true`）で追加する環境を聞く。既存環境がある場合は検出結果を提示して重複を防ぐ。

**入力**: Phase 1 の既存環境一覧
**完了**: 追加する環境のプロバイダー一覧が確定している

### Step 2-2: サブフォルダ名の決定

環境ごとに AskUserQuestion で識別子を聞く。選択値がそのまま `~/.claude-{provider}-{identifier}` の `{identifier}` になる。

**入力**: Step 2-1 の環境一覧
**完了**: 全環境の `{provider}-{identifier}` が確定している

### Step 2-3: Bedrock 認証方式の選択（Bedrock のみ）

AskUserQuestion で認証方式を選択する。

**入力**: Bedrock 環境の一覧
**完了**: 認証方式が確定している

### Step 2-4: AWS リージョンの選択（Bedrock のみ）

AskUserQuestion でリージョンを選択する。

**入力**: Step 2-3 の環境
**完了**: リージョンが確定している

### Step 2-5: モデル版ピン留めの確認（Bedrock のみ）

AskUserQuestion でピン留め要否を聞く。ピン留め時はリージョンプレフィックス（ap → `jp.anthropic.`、us → `us.anthropic.`、eu → `eu.anthropic.`）を自動算出する。

**入力**: Step 2-4 のリージョン
**完了**: ピン留め要否が確定している

### Step 2-6: エイリアス名の確認

環境ごとにデフォルト名（`clu` + provider 頭文字 + identifier 頭文字）を生成し、AskUserQuestion で確認する。

**入力**: 全環境の provider-identifier
**完了**: 全環境のエイリアス名が確定している

完了条件: 全環境のプロバイダー・識別子・認証方式・リージョン・ピン留め・エイリアス名が確定している

## Phase 3: 環境構築

Phase 2 で確定した仕様に基づき、ディレクトリと settings.json を作成する。

### Step 3-1: ディレクトリの作成

環境ごとに Bash で `mkdir -p ~/.claude-{provider}-{identifier}` を実行する。既存ディレクトリは作成をスキップする。

**入力**: Phase 2 の全環境一覧、Phase 1 の既存ディレクトリ一覧
**完了**: 全環境のディレクトリが存在する

### Step 3-2: Bedrock 環境の settings.json 作成

認証方式に応じた settings.json を動的生成して `~/.claude-{provider}-{identifier}/settings.json` に Write する。既存の settings.json がある環境はスキップする。

Bearer Token の場合:
```json
{
  "env": {
    "CLAUDE_CODE_USE_BEDROCK": "1",
    "AWS_REGION": "{リージョン}",
    "AWS_BEARER_TOKEN_BEDROCK": "YOUR_SECRET_HERE"
  }
}
```

IAM の場合:
```json
{
  "env": {
    "CLAUDE_CODE_USE_BEDROCK": "1",
    "AWS_REGION": "{リージョン}",
    "AWS_ACCESS_KEY_ID": "YOUR_ACCESS_KEY_HERE",
    "AWS_SECRET_ACCESS_KEY": "YOUR_SECRET_KEY_HERE"
  }
}
```

SSO の場合:
```json
{
  "env": {
    "CLAUDE_CODE_USE_BEDROCK": "1",
    "AWS_REGION": "{リージョン}",
    "AWS_PROFILE": "{プロファイル名}"
  }
}
```

モデルピン留め有の場合は env ブロックに追加:
```json
"ANTHROPIC_DEFAULT_OPUS_MODEL": "{prefix}claude-opus-4-8",
"ANTHROPIC_DEFAULT_SONNET_MODEL": "{prefix}claude-sonnet-4-6"
```

**入力**: Phase 2 の Bedrock 環境仕様
**完了**: Bedrock 環境の settings.json が配置されている

### Step 3-3: 秘密情報の設定案内

Bearer Token / IAM 認証の環境について、settings.json のファイルパスとプレースホルダ箇所を明示してユーザーに手動置換を案内する。AskUserQuestion で完了確認する（完了した / あとで設定する）。「あとで設定する」の場合は Phase 5 の検証をスキップする。

**入力**: Step 3-2 で配置した settings.json のパス一覧
**完了**: 秘密情報の設定状況が確認されている

完了条件: 全環境のディレクトリと settings.json が作成され、秘密情報の設定状況が確認されている

## Phase 4: エイリアス登録

Phase 1 で検出した OS・シェルに応じて、rcファイルにエイリアスを登録する。

### Step 4-1: rcファイルへの追記

rcファイルの管理ブロック（`# setup-claude-multi-auth managed block start` / `end`）内にエイリアスを追記する。既存ブロックがあれば既存エイリアスを保持しつつ新規分を追記する。既存ブロックがなければ新規作成する。

macOS/Linux (zsh/bash):
```bash
# setup-claude-multi-auth managed block start
alias {name}='CLAUDE_CONFIG_DIR="$HOME/.claude-{provider}-{identifier}" claude'
# setup-claude-multi-auth managed block end
```

Windows (PowerShell):
```powershell
# setup-claude-multi-auth managed block start
function {name} { $env:CLAUDE_CONFIG_DIR = "$env:USERPROFILE\.claude-{provider}-{identifier}"; claude @args }
# setup-claude-multi-auth managed block end
```

**入力**: Phase 2 の全環境エイリアス名、Phase 1 のrcファイルパス・管理ブロック状態
**完了**: rcファイルに管理ブロックが存在し全エイリアスが登録されている

### Step 4-2: 登録結果の報告

登録したエイリアスの一覧を表で報告する。`source ~/.zshrc`（macOS/Linux）または新規ターミナル起動の案内を添える。

**入力**: Step 4-1 の登録結果
**完了**: 登録結果が表で報告され、有効化方法が案内されている

完了条件: 全エイリアスがrcファイルに登録され、有効化方法が案内されている

## Phase 5: 認証案内と検証

各環境の初回認証を案内し、完了状況を確認する。

### Step 5-1: 認証コマンドの提示と実行案内

環境ごとに、ユーザーがプロンプトでそのまま実行できるコマンドをコードブロックで提示する。OAuth 認証はブラウザ操作が必須であり Claude では代行できないため、[NO-DELEGATION-ABORT] 形式で案内する。

**Anthropic 環境の場合:**

以下のコマンドをプロンプトで実行するよう案内する:

    ! CLAUDE_CONFIG_DIR="$HOME/.claude-{provider}-{identifier}" claude

ブラウザが開くので対象アカウントでログインし、認証完了後にセッション内で `/exit` と入力して終了する旨を添える。

**Bedrock (Bearer/IAM) の場合:**

秘密情報が settings.json に設定済みであれば追加認証は不要。以下のコマンドで動作確認を案内する:

    ! CLAUDE_CONFIG_DIR="$HOME/.claude-{provider}-{identifier}" claude

起動後 `/status` で `Provider: Amazon Bedrock` と表示されることを確認し、`/exit` で終了する旨を添える。

**Bedrock (SSO) の場合:**

以下の 2 コマンドを順に案内する:

    ! aws sso login --profile {profile}

SSO ログイン完了後:

    ! CLAUDE_CONFIG_DIR="$HOME/.claude-{provider}-{identifier}" claude

起動後 `/status` で確認し `/exit` で終了。

[NO-DELEGATION-ABORT]
操作: OAuth ブラウザログイン（Anthropic）/ SSO ログイン（Bedrock SSO）
理由: ブラウザでの対話操作が必須であり Claude では代行不可
代替案: プロンプトで `!` プレフィックスコマンドを実行しこのセッション内から起動可能

**入力**: Phase 2 の全環境仕様（provider / identifier / エイリアス名 / 認証方式）
**完了**: 全環境の実行可能なコマンドが提示され、操作手順が案内されている

### Step 5-2: 認証完了の確認

AskUserQuestion で認証の実行状況を確認する（全環境完了 / 一部完了 / まだ実施していない）。

**入力**: Step 5-1 の手順案内
**完了**: 認証の実行状況が確認されている

### Step 5-3: 動作検証

認証完了した環境について動作検証を行う。秘密情報を「あとで設定する」とした環境はスキップする。

1. `CLAUDE_CONFIG_DIR=~/.claude-{provider}-{identifier} claude --version` で起動確認
2. Bedrock 環境は settings.json の JSON 構文検証と必須キー（`CLAUDE_CODE_USE_BEDROCK`, `AWS_REGION`, 認証変数）の存在確認

**入力**: 認証完了した環境一覧
**完了**: 検証結果が PASS/FAIL で記録されている

### Step 5-4: 結果報告

全環境のセットアップ結果を PASS/FAIL 表で報告する。

**入力**: Phase 1〜5 の全結果
**完了**: PASS/FAIL 表で結果が報告されている

完了条件: 認証完了環境の動作検証が PASS/FAIL で報告されている

## 重要ルール

- 秘密情報（Bearer Token / IAM SecretKey）を AskUserQuestion で聞かない。チャットログに残るため settings.json にプレースホルダを書き出しユーザーが直接編集する
- rcファイルは管理ブロック（`# setup-claude-multi-auth managed block start/end`）内のみ操作する。ブロック外の既存設定に一切触れない
- 既存サブ環境の settings.json を上書きしない。新規環境のみ作成する
- `~/.aws/credentials` を Read しない（サンドボックスの deny 対象）
- メインの `~/.claude/settings.json` は変更しない

## 予想を裏切る挙動

- エイリアスは rcファイルへの追記後、新規ターミナルか `source ~/.zshrc` まで有効にならない
- Bedrock のモデルデフォルトは Anthropic API より遅延する（2026-06-22 時点: opus=4.6, sonnet=4.5）。ピン留めなしでは意図しない旧バージョンで動作する
- ピン留めしたモデル ID は新バージョンリリースで陳腐化する
- Windows の `$PROFILE` ファイルが未作成の場合がある（Write で新規作成する）
- SSO 認証はセッション期限切れで `aws sso login` の再実行が必要

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | OS・シェル・rcファイル・既存サブ環境・管理ブロックの状態が把握されている |
| Phase 2 | 全環境のプロバイダー・識別子・認証方式・リージョン・ピン留め・エイリアス名が確定している |
| Phase 3 | 全環境のディレクトリと settings.json が作成され、秘密情報の設定状況が確認されている |
| Phase 4 | 全エイリアスがrcファイルに登録され、有効化方法が案内されている |
| Phase 5 | 認証完了環境の動作検証が PASS/FAIL で報告されている |
| **Goal** | 全環境のディレクトリ・settings.json・エイリアスが配置され、認証完了環境の動作が検証されている |

## 完了報告

- `.claude/skills/shared/references/completion-report-format.md` の作業報告型骨格に従う
- 固有の検証行: 作成環境数・エイリアス一覧・認証/検証の PASS/FAIL 表・未完了環境の件数

## 設計判断

**必要性**: Claude Code のマルチアカウント / Bedrock 切り替えは、ディレクトリ作成・settings.json 記述・シェルエイリアス登録・認証実行という 4 段階の手作業を要し、認証方式ごとに settings.json の内容が異なる。手順書は存在するが、OS ごとの差異・既存設定との衝突・秘密情報の取り扱いを毎回判断する必要があり、スキル化して自動化する価値がある。

**代替案を採用しなかった理由**:
- AskUserQuestion で秘密情報を収集: チャットログに秘密鍵が残るためプレースホルダ + 手動編集方式を採用
- `~/.aws/credentials` からの自動読み取り: サンドボックスの deny リストに該当するため技術的に不可
- rcファイル全体の Read-rewrite: 既存の機密情報を読み取る・事故で消すリスクがあるため管理ブロック限定方式を採用

**保守責任者**: 人手（setup-claude-multi-auth スキルの利用者・保守者）

**廃棄条件**: Claude Code 本体にマルチアカウント切り替え機能が組み込まれ、`CLAUDE_CONFIG_DIR` によるディレクトリ分離が不要になった時
