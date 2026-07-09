# 種別ごとの検出戦略ガイダンス

Phase 1（スタック・ユニット規約の特定）で、`unit_kind` に応じて調査すべき対象と検出手法を示す。

## screen（画面）

組み込み検出器 `detect-screens.sh` が対応する。カスタム抽出パスも使用可能。

| 調査対象 | 検出手法 |
|---|---|
| ルーティング定義の所在と方式 | package.json のフレームワーク・ルーターライブラリ確認。Next.js App/Pages Router、React Router（useRoutes 含む）、慣習ディレクトリ（pages/screens/views） |
| 画面ID命名パターン | ルートパスセグメント・ファイル名・コンポーネント名の規則性 |
| View切替関数 | モーダル・タブ・アコーディオン等の表示切替パターン |
| 除外パターン | tests/stories/mocks 等のノイズディレクトリ |

## api（API）

組み込み検出器なし。カスタム抽出パスを使用。

| 調査対象 | 検出手法 |
|---|---|
| エンドポイント定義の所在 | OpenAPI/Swagger 定義ファイル、Express/Fastify/Hono のルート定義、FastAPI/Django REST のビュー定義、コントローラファイル |
| HTTPメソッドとパス | `app.get()`/`app.post()` 等のメソッド呼び出し、デコレータ（`@Get()`/`@Post()`）、ルートテーブル |
| ミドルウェア | 認証・バリデーション等の共通処理 |
| 除外パターン | テスト用エンドポイント、ヘルスチェック |

## table（テーブル）

| 調査対象 | 検出手法 |
|---|---|
| テーブル定義の所在 | マイグレーションファイル（Prisma/TypeORM/Knex/Alembic 等）、ORM モデル定義、SQL DDL |
| スキーマ情報 | カラム名・型・制約・インデックス |
| ビュー定義 | CREATE VIEW 文、ORM のビュー定義 |
| 除外パターン | テスト用マイグレーション、シード |

## batch（バッチ）

| 調査対象 | 検出手法 |
|---|---|
| バッチ定義の所在 | cron 定義（crontab/node-cron/APScheduler）、ジョブスケジューラ設定（Bull/Celery）、CLI コマンド定義 |
| 実行スケジュール | cron 式、実行間隔、トリガー条件 |
| 入出力 | 処理対象データソース、出力先 |
| 除外パターン | ワンショットスクリプト、マイグレーション |

## report（帳票）

| 調査対象 | 検出手法 |
|---|---|
| 帳票定義の所在 | テンプレートファイル（Jasper/BIRT/Crystal）、PDF/Excel 生成コード（puppeteer/pdfkit/ExcelJS）、レポート定義設定 |
| 出力形式 | PDF/Excel/CSV/HTML |
| データソース | クエリ・API 呼び出し・集計ロジック |
| 除外パターン | テスト用テンプレート |

## external（外部連携）

| 調査対象 | 検出手法 |
|---|---|
| 外部連携定義の所在 | API クライアントラッパー、SDK 統合コード、webhook ハンドラ、メッセージキューコンシューマ |
| プロトコル | REST/GraphQL/gRPC/SOAP/WebSocket/メッセージキュー |
| 認証方式 | API キー/OAuth/証明書 |
| 除外パターン | モック・スタブ |

## 汎用マニフェストスキーマ（非画面種別）

```json
{
  "generatedAt": "ISO8601",
  "sourceDir": "探索対象ルート",
  "unitKind": "api|table|batch|report|external",
  "strategy": {
    "extractionMethod": "custom",
    "approvedByUser": true,
    "unitIdRegex": "string|null",
    "excludePatterns": []
  },
  "detectionSummary": {
    "method": "custom",
    "unitCount": 0,
    "unresolvedCount": 0
  },
  "units": [
    {
      "unitKey": "意味キー",
      "unitId": "業務ID（任意）",
      "unitNameGuess": "推定名",
      "kind": "種別固有の区分値",
      "identifier": "主識別子",
      "sourceFile": "主ファイルパス",
      "confidence": "high|medium|low",
      "fileCount": 0,
      "files": [],
      "detectionMethod": "検出手法"
    }
  ]
}
```

各種別の `kind` 値:
- api: `endpoint`, `middleware`, `unresolved`
- table: `table`, `view`, `migration`, `unresolved`
- batch: `scheduled`, `triggered`, `unresolved`
- report: `template`, `generator`, `unresolved`
- external: `client`, `webhook`, `unresolved`
