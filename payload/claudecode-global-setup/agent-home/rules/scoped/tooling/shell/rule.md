---
paths:
  - "**/*.sh"
  - "**/Makefile"
  - "**/package.json"
  - "**/justfile"
  - "**/Taskfile.yaml"
---

# セキュリティと制限（SECURITY）

Claude Code がグローバルに遵守する禁止・制限事項。

## スクリプトファイル作成方針

### 本ルールが扱う「スクリプト」の定義

本ルールでいう「スクリプト」は **シェルスクリプト** を指す。Python / Ruby / JavaScript / TypeScript / Go / Rust 等のプログラミング言語で書かれたファイルは本ルールの対象外とし、通常のプロジェクト本体コードとして扱う。

シェルスクリプト系で許可される拡張子は **`.sh` のみ**。他のシェル系拡張子（`.bat` / `.zsh` / `.fish`）の Write は `permissions.deny` で全プロジェクト共通の hard block とする。

プロジェクト側 `settings.json` で `allow` 上書きして本ルールを迂回することは禁止する。シェルが必要なら `.sh` を使う。例外なし。

### AI 単独判断での作成は禁止

Claude が自分の判断で `.sh` を新規作成することは禁止する。`Write(**/*.sh)` は `permissions.ask` 経由でユーザーへ確認を求める。

### 作成時の必須要件: ADR

`.sh` ファイルを新規作成する際は、必要性を説明する設計判断（Architecture Decision Record）を残す。対象の定義ドキュメント（rule.md / SKILL.md）内に `## 設計判断` セクションとして記載する。

ADR に書くべき項目:

- **必要性**: なぜスクリプト化が必要か（例: 繰り返し利用される / トークン節約 / 複雑な分岐ロジック / hook 連携）
- **代替案を採用しなかった理由**: なぜ Bash ツール直叩き・既存 `Makefile` 拡張・`package.json` の `scripts` 追加で代替できないか
- **保守責任者**: 誰が更新するか（人手 / routine）
- **廃棄条件**: いつ削除してよいか

ADR が書けない（必要性を説明できない）場合は、そもそもスクリプト化すべきでない。Bash ツールで直接実行する。

### 既存プロジェクト基盤ファイルの扱い

次のファイルは「スクリプト作成」の対象外とし、既存資産の保守として通常通り編集してよい:

- `Makefile`
- `package.json` の `scripts` セクション
- `justfile` / `Taskfile.yaml`
- `.husky/*` 内のフック本体
- `.github/workflows/*.yml`
- `Dockerfile` / `docker-compose.yml`
- `~/agent-home/tools/hooks/*.sh`（既存 hook script）
- 既存の `<skill>/scripts/*.sh`

新規追加で `Makefile` ターゲットや `package.json` scripts に長大なシェルロジックを埋め込んで `.sh` 禁止を回避する行為は禁止する（運用上の倫理規範）。

## 外部スクリプト依存禁止

ワークフロー実装のために外部スクリプトへ処理を逃がすことは禁止する。
内蔵ツール（Bash / Edit / Write / MCP / Agent）で完結させ、再現性とレビュー容易性を保つ。

`.sh` の新規作成が ADR を伴って正当化された場合のみ、上記の例外として認める。

## 削除操作

不要なファイル・ディレクトリは `rm` / `rm -rf` で直接削除する。`_trash` への退避は廃止（容量肥大化の原因のため）。
破壊的削除を行う前にユーザーに対象を確認し承認を得る。

## worktree の畳み方

worktree を畳む時は `git worktree remove <path>`（必要なら `--force`）を実行し、メタデータも同時にクリーンアップする。
`mv _trash` の 2 段処理は廃止。

## 機械強制

| timing | 強制ポイント | 注入タグ | 挙動 |
|---|---|---|---|
| 事前 | `permissions.deny` | — | シェル系 `.bat` / `.zsh` / `.fish` の Write を hard block |
| 事前 | `check-curl-egress.sh`（rules-bash-runner 経由） | `[CURL-EGRESS-BLOCK]` | 外部ホストへの生 curl / wget を exit 2 で block（localhost 直書き URL と call-api.sh のみ許可） |
| 事後 | `check-sh-design-decision.sh` | `[DESIGN-DECISION-REQUIRED]` | 新規 `.sh` (git untracked) に対応する設計判断セクションが定義ドキュメント内に無い場合に警告 |
| 事後 | `shell-evasion-check.sh` | `[SHELL-EVASION-DETECTED]` | Makefile / package.json scripts / justfile / Taskfile に net-new で長大シェル (200 字超 / 3 連以上 `&&`) を検出時に警告 |

`permissions.deny` の hard block はセッション中バイパス不可。プロジェクト側 `settings.json` での `allow` 上書きも禁止する（例外なし）。

事後 hook は `exit 2` でブロックせず additionalContext で警告するのみ。Claude は次ターンで ADR 作成または脱法ロジック解体に進む。

## permissions の全自動運用（意図的設定）

`Bash(*)` の包括 allow と `defaultMode=auto`・`skipDangerousModePermissionPrompt`・`skipAutoPermissionPrompt`・`skipWorkflowUsageWarning` の 3 フラグは、ルーティン・クラウド実行を含む自律運用のための**意図的な設定**であり、設定事故ではない（2026-07-02 監査で確認・維持を決定）。防御は permissions ではなく 3 層で担う: ①deny の網（rm -rf /・filter-branch・push --mirror 等の最悪系）②pre-bash-dispatch の文脈ガード（secret 検出・命名・textlint）③各 rules の PreToolUse block hook。

curl / wget の外部送信は `check-curl-egress.sh`（PreToolUse(Bash)、rules-bash-runner 経由）で block する。localhost 系（localhost / 127.0.0.1 / ::1 / 0.0.0.0）への直書き URL は開発サーバーの疎通確認用に通過させ、外部 API 呼び出しは `~/agent-home/tools/call-api.sh`（ホスト白リスト検証ラッパー）を唯一の経路とする。変数展開 URL（`curl "$URL"` 等）は検証不能のため fail-closed で block する。旧方式の deny `Bash(curl:*)` は localhost への正当な疎通確認まで一律 block し（2026-07-03 のセッションログ調査で延べ 218 件の localhost 誤爆と Playwright 迂回の誘発を確認）、deny では localhost 例外を表現できないため hook 方式へ移行した。

## 設計判断テンプレート

対象の定義ドキュメント（rule.md / SKILL.md）内に `## 設計判断` セクションとして記載する。独立した ADR ファイルは作成しない。`check-sh-design-decision.sh` は定義ドキュメント内に `.sh` の basename（拡張子なし）を含む `## 設計判断` セクションが存在するかで検出する。

定義ドキュメント内に以下の 4 項目を記載する:

```markdown
## 設計判断

**必要性**: （なぜスクリプト化が必要か。例: 同じ処理が日次 routine で 5 回以上呼ばれる / Bash 直叩きだと 30 行を超えトークンを浪費する / hook から複数引数で呼ぶ需要がある）

**代替案を採用しなかった理由**:
- Bash ツール直叩き: <なぜ不可>
- 既存 Makefile ターゲット拡張: <なぜ不可>
- package.json scripts 追加: <なぜ不可>

**保守責任者**: （人手 / routine 名）

**廃棄条件**: （このスクリプトが不要になる条件。例: 上流の foo が API 化された時 / routine X が deprecate された時）
```

設計判断が書けない（必要性を説明できない）場合は、そもそもスクリプト化すべきでない。Bash ツールで直接実行する。

## プロジェクト上書き

- 上書き可否: 上書き禁止
- 理由: セキュリティ規約はプロジェクト側での迂回を許すと防御線として機能しないため、受け口を設けない

設計判断・経緯の記録は同ディレクトリの `design-notes.txt` を参照（非注入サイドカー）。
