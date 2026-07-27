# running-e2e（orchestrating-dev-flow 内部モジュール）

プロジェクトのブラウザ動作を Playwright MCP で確認する。
URL・コマンド・ヘルスエンドポイントはすべて `flow-values.yml の e2e セクション` から取得する。

**flow-values.yml（プロジェクトルートに配置）の参照キー**:

```yaml
e2e:
  fe_url: "http://localhost:5173"        # フロントエンド URL（必須）
  be_url: "http://localhost:8000"        # バックエンド URL（必須）
  test_cmd: "cd frontend && npm run test:e2e"  # Playwright スイート実行コマンド
  db_start_cmd: "make e2e-up"           # DB + サービス一括起動コマンド（任意）
  health_endpoint: "/api/health"         # ヘルスチェックパス（既定 /api/health）
  app_pages: ["/dashboard", "/admin"]   # 認証済みで確認するページ一覧
  port_env_file: ".worktree-ports.env"  # worktree 並行実行時のポート上書きファイル（任意）
```

---

## 前提条件とポート解決（worktree 並行 E2E 対応）

このモジュールは worktree ごとに独立したポート帯での並行実行に対応する。**まず現在地のポートを確定する**:

```bash
PROJECT=$(git rev-parse --show-toplevel)

# flow-values.yml から e2e 設定を読み込む
FE_URL=$(yq '.e2e.fe_url // "http://localhost:5173"' flow-values.yml 2>/dev/null || echo "http://localhost:5173")
BE_URL=$(yq '.e2e.be_url // "http://localhost:8000"' flow-values.yml 2>/dev/null || echo "http://localhost:8000")
HEALTH=$(yq '.e2e.health_endpoint // "/api/health"' flow-values.yml 2>/dev/null || echo "/api/health")
TEST_CMD=$(yq '.e2e.test_cmd // empty' flow-values.yml 2>/dev/null)
DB_START=$(yq '.e2e.db_start_cmd // empty' flow-values.yml 2>/dev/null)
PORT_ENV=$(yq '.e2e.port_env_file // empty' flow-values.yml 2>/dev/null)

# worktree 固有のポート上書きファイルが存在する場合は優先する
if [ -n "$PORT_ENV" ] && [ -f "$PROJECT/$PORT_ENV" ]; then
  # .worktree-ports.env 等からポートを読み込んで FE_URL / BE_URL を上書き
  source "$PROJECT/$PORT_ENV"
  [ -n "$WT_BASE_URL" ]    && FE_URL="$WT_BASE_URL"
  [ -n "$WT_BACKEND_URL" ] && BE_URL="$WT_BACKEND_URL"
fi
```

以降の Step では固定値ではなく**この解決済み URL** を使う。

Playwright スイート（`e2e.test_cmd`）は `global-setup` でサービスを自己起動する構成が多い。
MCP での手動確認時のみ、フロント／バックエンドが未起動なら `e2e.db_start_cmd` で起動する。

---

## Step 1: ヘルスチェック（API 疎通確認）

Bash で直接確認する:

```bash
curl -s "${BE_URL}${HEALTH}"
```

期待値: `{"status": "ok"}` またはプロジェクトが定義する正常レスポンス。

失敗した場合はバックエンドが未起動。`e2e.db_start_cmd` が定義されていれば実行を試みる。それでも失敗した場合は E2E テストを中断してユーザーに報告する。

---

## Step 2: フロントエンド起動確認

Playwright MCP で navigate する:

```
URL: <FE_URL>
```

確認事項:
- ページが 200 で返る（エラー画面でない）
- ログイン画面またはトップ画面が表示される

---

## Step 3: ログイン画面の確認

未認証状態でアクセスした場合、ログイン画面が表示されることを確認する。

確認事項:
- メールアドレス入力フィールドまたはログインフォームが存在する
- 送信ボタンが存在する

ログイン画面の構造はプロジェクトによって異なる。`flow-values.yml` に `e2e.login_selector` が定義されている場合はその selector で確認する。

---

## Step 4: ナビゲーション確認（認証済みセッションがある場合）

認証済みの場合は `flow-values.yml の e2e.app_pages` に列挙されたページを順に確認する:

```bash
APP_PAGES=$(yq '.e2e.app_pages[]' flow-values.yml 2>/dev/null)
```

各ページで確認すること:
- エラー画面でなくコンテンツが表示される
- コンソールに致命的エラーが出ていない

---

## Step 5: 結果レポート

以下フォーマットで報告する:

```
[E2E-TEST] 結果
- API ヘルス: OK / NG（理由）
- フロントエンド起動: OK / NG（理由）
- ログイン画面: OK / NG（理由）
- ナビゲーション: OK / NG / スキップ（未認証のため）
```

NG がある場合は原因を特定してユーザーに報告する。自動修正は行わない（E2E 失敗の修正は別途ソースコードの調査が必要）。

`references/module-fixing-review-findings.md` の手順から呼ばれた場合は、NG を検出した時点でそちらに結果を返し、Phase 5 の「修正と無関係の場合」の処理に委ねる。

---

## 予想を裏切る挙動

- `port_env_file` が指定されており worktree 内で実行する場合、そのファイルの URL を使わなければならない。`fe_url` / `be_url` をハードコードすると別 worktree の環境を誤ってテストする
- Playwright スイート（`test_cmd`）はサービスを自動起動する `global-setup` を持つ構成が多いが、MCP での手動確認では自動起動しないため `db_start_cmd` で事前に起動が必要
- Step 1 の API ヘルスチェック失敗時は E2E テスト全体を中断する。`db_start_cmd` が未定義の場合はユーザーに手動起動を促す（ただし CLI コマンド実行を依頼する形ではなく、このモジュールが `db_start_cmd` を直接実行できるかを先に確認すること）
- `flow-values.yml` が存在しないプロジェクトでは `fe_url` / `be_url` の既定値（5173 / 8000）を使い、動作可否をユーザーに確認してから進む
- Playwright MCP の `filename` 引数に相対パスを使うと CWD 直下に PNG が生成される。スクリーンショットは必ず絶対パスで保存すること（`file-guard-rules` 参照）
