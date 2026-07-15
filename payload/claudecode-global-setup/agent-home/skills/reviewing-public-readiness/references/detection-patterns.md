# 検出パターン詳細

`reviewing-public-readiness` スキルが使用する正規表現と誤検知除外ルールの完全リスト。

## 高エントロピー文字列（カテゴリ 5）

| プロバイダ | 正規表現 | 例 |
|---|---|---|
| AWS Access Key | `AKIA[0-9A-Z]{16}` | `AKIA` + 英大文字数字16桁（AWS公式ドキュメントの例示値と同形式） |
| AWS Secret Key | `(?<![A-Za-z0-9])[A-Za-z0-9/+=]{40}(?![A-Za-z0-9])` ※ 文脈依存・誤検知多 | 英数記号40桁の高エントロピー文字列（AWS公式ドキュメントの例示値と同形式） |
| OpenAI API Key | `sk-[A-Za-z0-9]{20,}` | `sk-proj-...` |
| GitHub Personal Token | `ghp_[A-Za-z0-9]{36}` | `ghp_...` |
| GitHub OAuth Token | `gho_[A-Za-z0-9]{36}` | `gho_...` |
| GitHub User-to-Server | `ghu_[A-Za-z0-9]{36}` | `ghu_...` |
| GitHub Server-to-Server | `ghs_[A-Za-z0-9]{36}` | `ghs_...` |
| GitHub Refresh Token | `ghr_[A-Za-z0-9]{76}` | `ghr_...` |
| Slack Token | `xox[baprs]-[A-Za-z0-9-]{10,}` | `xoxb-...` |
| Google API Key | `AIza[0-9A-Za-z_-]{35}` | `AIza...` |
| JWT | `eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}` | `eyJhbGc...` |
| PEM 秘密鍵 | `-----BEGIN [A-Z ]*PRIVATE KEY-----` | PEM形式ヘッダー行（BEGIN + アルゴリズム名 + PRIVATE KEY の並び） |
| Stripe Secret Key | `sk_live_[A-Za-z0-9]{24,}` | `sk_live_...` |
| Stripe Publishable Key | `pk_live_[A-Za-z0-9]{24,}` ※ 公開キーだが誤コミット検知用 | `pk_live_...` |

`git grep -nE` で各パターンを順次走査する。

## 機密ファイル名パターン（カテゴリ 1）

```
^|/)\.env($|\.) 
^|/)\.env\.(local|production|development|staging|test)$
^|/).*\.pem$
^|/).*\.key$
^|/)id_rsa($|\.)
^|/)id_ed25519($|\.)
^|/)id_ecdsa($|\.)
^|/)\.pypirc$
^|/)\.npmrc$
^|/)credentials\.json$
^|/)service-account.*\.json$
^|/)\.aws/credentials$
^|/).*\.kdbx$
^|/).*\.tfstate$
^|/).*\.tfstate\.backup$
^|/).*\.swp$
^|/).*\.dump$
```

`*.tfvars` `*.sql` は内容次第で CRITICAL 格上げ（実値混入時）。

## 内部限定情報（カテゴリ 4）

| 種別 | パターン |
|---|---|
| 社内ホスト | `\.internal\b` `\.corp\b` `\.local\b`（mDNS と区別必要） |
| プライベート IP | `\b10\.\d+\.\d+\.\d+\b` `\b172\.(1[6-9]\|2[0-9]\|3[0-1])\.\d+\.\d+\b` `\b192\.168\.\d+\.\d+\b` |
| IDE 絶対パス | `/Users/[a-zA-Z0-9._-]+/` `/home/[a-zA-Z0-9._-]+/` `C:\\\\Users\\\\` |
| 個人メール | `[a-zA-Z0-9._%+-]+@(gmail\|yahoo\|outlook\|icloud)\.(com\|jp\|co\.jp)` |

## 内部チケット番号（カテゴリ 11）

| 種別 | パターン | 備考 |
|---|---|---|
| JIRA 形式 | `[A-Z]+-[0-9]+` | プロジェクトキーが社名・顧客名を示すことが多い |
| GitHub Issue | `#[0-9]+` | 公開リポジトリでは問題なし、private のみ要警戒 |
| Linear | `[A-Z]{3,4}-[0-9]+` | JIRA と区別困難 |

## 誤検知除外ルール

以下の箇所のヒットは除外候補としてマーク（最終判断はユーザー）。

| 除外対象 | 理由 |
|---|---|
| `README.md` `docs/**` 内の例示 | ドキュメントの説明用文字列 |
| `tests/fixtures/**` `__fixtures__/**` `**/*.fixture.*` | テストデータ |
| `**/*.example.*` `**/*.sample.*` | 例示ファイル（ただし内容に高エントロピー文字列があれば CRITICAL 格上げ） |
| コードコメント内 `# example: ...` `// example: ...` | 例示コメント |
| `.gitignore` 自身に書かれたパターン | 除外対象を列挙しているだけ |
| 第三者 vendored ディレクトリ（`vendor/**` `third_party/**` `plugins/marketplaces/**` `node_modules/**` 等） | 自リポジトリの管理外。著作権上の理由で混入していても自リポジトリの公開リスクとは別問題 |
| スキャナー本体・本 SKILL.md・`references/detection-patterns.md` 内のパターン定義テキスト | 自己言及ヒット。検出パターン自身が grep の対象になっているだけで実害なし |

### ファイル名一致時の内容確認ルール（カテゴリ 1 拡張）

カテゴリ 1（機密ファイル混入）でファイル名がパターンに合致した場合、ファイル名だけで CRITICAL 確定とせず、**内容を grep して秘密値が含まれるか確認**する 2 段判定を行う。

| ファイル | 内容判定基準（CRITICAL 維持の条件） |
|---|---|
| `.env*` | `[A-Z_]+=` の形式で値が設定されている（空でない値） |
| `.npmrc` | `_authToken=` `_password=` `_auth=` のいずれかが含まれる（公開レジストリ URL のみは INFO 降格） |
| `.pypirc` | `password = ` `username = __token__` 等の認証情報を含む（リポジトリ URL のみは INFO 降格） |
| `credentials.json` | `client_secret` `private_key` `token` 等のキーが含まれる |
| `*.pem` `*.key` | `-----BEGIN [A-Z ]*PRIVATE KEY-----` を含む（公開鍵のみは INFO 降格） |
| `service-account*.json` | `private_key` キーを含む |

内容判定で秘密値が無ければ **INFO 降格 + 除外候補マーク**。第三者 vendored ディレクトリ配下のものはさらに除外候補として確定する。

## 巨大ファイル閾値（カテゴリ 8）

| サイズ | 重大度 | 対処 |
|---|---|---|
| 10MB 未満 | 対象外 | - |
| 10MB–50MB | INFO | LFS 化を提案 |
| 50MB 超 | WARN | LFS 化必須・履歴からの削除を提案 |
| 100MB 超 | CRITICAL | GitHub の単一ファイル上限超過。即時対処必要 |

## CI/CD 設定の検出（カテゴリ 10）

| ファイル | パターン | 重大度 |
|---|---|---|
| `.github/workflows/*.yml` | `runs-on: self-hosted` ／ `runs-on: \[self-hosted` | WARN |
| `.github/workflows/*.yml` | `\$\{\{ secrets\.[A-Z_]+ \}\}` | INFO（secret 名のみ確認） |
| `Dockerfile` | `^ARG [A-Z_]*(SECRET\|TOKEN\|KEY\|PASSWORD)` | WARN |
| `docker-compose.yml` | `^\s*[A-Z_]*(SECRET\|TOKEN\|KEY\|PASSWORD)\s*:\s*[^$]` ※ `$` で始まらない直値 | CRITICAL |
| `kustomize/**/secrets.yaml` | `data:` 配下の base64 文字列 | CRITICAL |
| `helm/**/values.yaml` `**/values.yaml` | `password:` `apiKey:` 等の直値 | CRITICAL |
