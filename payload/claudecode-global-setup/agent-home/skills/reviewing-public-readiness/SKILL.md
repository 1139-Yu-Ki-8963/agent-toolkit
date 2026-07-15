---
name: reviewing-public-readiness
description: "公開前機密漏洩スナップショット走査。 TRIGGER when: make public・[PUBLISH-*]注入。 SKIP: PR・差分セキュリティレビュー（→ security-review）。"
invocation: reviewing-public-readiness
type: reactive
allowed-tools: ["Agent", "Bash", "Read", "Grep", "Glob"]
---

# 公開可否レビュー

リポジトリを公開する前に、機密ファイル・履歴漏洩・author 情報・内部限定情報・高エントロピー文字列など 12 観点でリポジトリ全体を走査する。差分ではなく **リポジトリ全体のスナップショット** を見る監査スキル。

## 使用タイミング

| シーン | 例 |
|---|---|
| OSS 化の判断時 | 「このリポジトリ、OSS 化しても大丈夫？」 |
| public 切り替え前 | 「private → public にするけどリスクある？」 |
| コミット時の自動発火 | フックから `[PUBLISH-AUTHOR]` `[PUBLISH-SAFETY]` `[PUBLISH-SAFETY-FULL]` 注入時（`~/.claude/settings.json` の PreToolUse フック経由） |
| 公開前の最終チェック | 「公開前チェックして」 |

## 基本ワークフロー（6 ステップ）

1. **対象確定**: `git rev-parse --show-toplevel` でリポジトリルート、`git remote -v` で public/private を判別
2. **author 情報取得**: `git config user.name` `git config user.email` で現在値を取得し、`git log --all --format='%aN <%aE>' | sort -u` で全 author の一覧を取得
3. **走査**: 下記「チェック観点」12 カテゴリを許可済み Bash コマンドのみで実行
4. **分類**: ヒット項目を `[CRITICAL]` / `[WARN]` / `[INFO]` に振り分け、誤検知の高い箇所（README の例示部・`tests/fixtures/` 配下）は除外候補としてマーク
5. **完了報告**: 「レポートフォーマット」で結論ラベル + 件数 + author のみ提示。**質問・確認は書かない**
6. **追加要求への対応**: ユーザーから「詳細」「CRITICAL の中身」等を聞かれた時のみ、該当カテゴリの検出箇所と対処コマンド例を出力

## チェック観点（12 カテゴリ）

| # | 大分類 | 個別チェック | 検出手段 | 既定重大度 |
|---|---|---|---|---|
| 1 | 機密ファイル混入 | `.env*` `*.pem` `*.key` `id_rsa*` `id_ed25519*` `.pypirc` `.npmrc` `credentials.json` `*.kdbx` `service-account*.json` `.aws/credentials` `*.tfstate*` `*.tfvars`（実値混入時）／`*.sql` `*.dump`（DB ダンプ）／`*.swp` | `git ls-files \| grep -E` | CRITICAL |
| 2 | .gitignore 妥当性 | `node_modules/` `dist/` `.venv/` `.env` `*.log` `.DS_Store` `Thumbs.db` `coverage/` `.idea/` `.vscode/` の不足 | `cat .gitignore` ＋既存ファイル一覧と突合 | WARN |
| 3 | git 履歴中の漏洩 | 過去コミットでの `.env` 等の追加履歴・削除済み秘密値 | `git log --all --full-history -- <pattern>` ／ `git log -p -G '<高エントロピー正規表現>'` | CRITICAL（過去のみ残存は WARN） |
| 4 | 内部限定情報 | 社内ホスト名（`*.internal` `*.corp` `*.local`）／内部 URL／個人メール／プライベート IP（10./172.16-31./192.168.）／IDE 設定の絶対パス（`/Users/<name>/`）／`.idea/workspace.xml` `.vscode/settings.json` の社内 URL | `git grep -nE` | WARN |
| 5 | 高エントロピー文字列 | AWS / OpenAI / GitHub / Slack / Google / JWT / PEM 系の正規表現群（詳細は `references/detection-patterns.md`） | `git grep -nE` | CRITICAL |
| 6 | メタファイル整備 | `LICENSE` `README.md` `SECURITY.md` `CODE_OF_CONDUCT.md` `CONTRIBUTING.md` の存在・空でないこと | `find` + `wc -l` | INFO（不足）／WARN（README 空 ／ OSS 化前提時の LICENSE 欠落） |
| 7 | 依存・設定リーク | `.git/config` の `url =` 内部ホスト／`package.json` の `"private": true`／`.npmrc` の `_authToken`／private registry URL／`pyproject.toml` の private index／lockfile の `resolved` 内部レジストリ URL／`.gitmodules` の内部 git URL／LFS endpoint の内部ホスト | `grep -E` | WARN |
| 8 | 巨大ファイル | 10MB 超／`.zip .iso .pkg .dmg .mp4` ／`.pdf > 5MB` | `find . -size +10M` ／ `git ls-files \| xargs wc -c` | INFO（10–50MB）／WARN（50MB 超） |
| 9 | コミット author 情報 | 現在の `user.name` `user.email`／全 author 一覧／co-author の妥当性 | `git config user.name && git config user.email` ／ `git log --all --format='%aN <%aE>' \| sort -u` | WARN（個人実名・会社メール検出時） |
| 10 | CI/CD・インフラ設定 | `.github/workflows/*.yml` の `runs-on: self-hosted`（社内 runner 名）／secret 名の妥当性／`Dockerfile` の `ARG` ビルド時 secret／`docker-compose.yml` 環境変数直書き／`kustomize/overlays/*/secrets.yaml` 実値混入／Helm `values.yaml` の secret refs／`.dockerignore` 妥当性 | `find .github .` + `grep -E` | CRITICAL（Helm/Kustomize 実値）／WARN（runner ラベル等） |
| 11 | コミットメッセージ・refs 内容 | `git log --all --format=%B` 全文の社内ツール名／JIRA 等内部チケット番号（`[A-Z]+-[0-9]+`）／顧客名・プロジェクトコード／ブランチ名・タグ名の機密／個人的悪態 | `git log --all --format=%B \| grep -E` ／ `git branch -a` `git tag -l` | WARN |
| 12 | 画像・PDF メタデータ | `*.png` `*.jpg` `*.pdf` の存在確認のみ。EXIF GPS 等の実読取はオプション | `find . \( -name '*.png' -o -name '*.jpg' -o -name '*.pdf' \) -exec ls -la {} \;` | INFO（要目視）／WARN（GPS 検出時） |

**例示ファイルの実値混入**: ファイル名が `*example*` `*sample*` でも、内容を grep して高エントロピー文字列が含まれれば CRITICAL に格上げ。

**LICENSE と依存ライセンスの整合**: 範囲外（別スキル化）。INFO で「目視推奨」とのみ報告。

詳細パターンは `references/detection-patterns.md` 参照。

## 重大度判定

| ラベル | 意味 | 結論 |
|---|---|---|
| `[CRITICAL]` | 公開即被害確定（実鍵・履歴中の鍵） | **公開不可** |
| `[WARN]` | 公開可だが対処強く推奨 | **条件付き公開可** |
| `[INFO]` | 整備推奨 | **公開可（INFO 項目は整備推奨）** |

絵文字は使わない。テキストラベルで統一。

## レポートフォーマット

ユーザーへの完了報告は `completion-report-format.md` に従う。本節はその中で示す詳細レポートの形式を定義する。**質問・確認は一切書かない**（詳細を見たい場合はユーザーが自発的に聞く）。

```markdown
## 公開可否レビュー

**対象**: <repo> | **可視性**: <public/private> | **ブランチ**: <branch>

**[<結論ラベル>]** CRITICAL <N> / WARN <N> / INFO <N>
Author: `<name> <email>`（過去 <N> 名）
```

ユーザーから詳細要求があった時のみ、該当カテゴリの検出箇所と対処コマンド例を出力する。

## 重要な注意事項

- **スクリプトファイル禁止**: `.sh` `.py` `.js` 等を作らない。すべて Read / Grep / Glob / 許可済み Bash で完結
- **絶対パス記述禁止**: SKILL.md 内では `~/agent-home/skills/...` 形式を使う
- **質問しない**: 完了報告のみ。判断はユーザーに委ねる
- **再帰防止**: 直前ターンで同一リポジトリのレビューを起動済みなら、初回結果を再利用
- **誤検知の扱い**: 走査前に **`references/detection-patterns.md` の「誤検知除外ルール」と「ファイル名一致時の内容確認ルール」を必ず確認**する。ファイル名一致だけで CRITICAL 確定はせず、内容を grep して秘密値の有無を判定する 2 段判定を行う。第三者 vendored ディレクトリ（`vendor/**` `third_party/**` `plugins/marketplaces/**` `node_modules/**`）と自己言及ヒット（パターン定義テキスト自身）は除外候補

## 他スキルとの連携

| スキル | 役割分担 |
|---|---|
| `security-review` | PR/作業ブランチの差分・コード脆弱性レビュー。本スキルは差分ではなくリポジトリ全体のスナップショットを対象 |
| `reviewing-single-pr-with-inline-comments` | PR の取得・コメント投稿。本スキルは PR を扱わない |
| `grouping-commits` | コミット作成。本スキルが PreToolUse で並行発火し、機密混入が検出された場合は grouping-commits を中断する |
| `managing-agent-configs`（種別: hooks） | フックの作成・レビュー・実機検証。本スキルを発火させる `[PUBLISH-AUTHOR]` `[PUBLISH-SAFETY]` `[PUBLISH-SAFETY-FULL]` フックの実体は settings.json |

## 参照資料

| ファイル | 内容 |
|---|---|
| `references/detection-patterns.md` | 高エントロピー正規表現の完全リスト・誤検知除外ルール |
| `~/.claude/settings.json` | 本スキルの自動発火指示（フックからの委譲ルール） |
| `~/.claude/settings.json` | 本スキルを発火させる PreToolUse フックの実装 |

---

## 完了報告

`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（調査報告型）に従う。
固有の検証行: CRITICAL / WARN / INFO 件数、author 一覧

## 予想を裏切る挙動

- CRITICAL 指摘はレポートのみ — 自動修正はしない。修正は手動または managing-agent-configs（種別: skills、review モード）で対応する
