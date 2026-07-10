# API 検出戦略ガイダンス

Phase 1（スタック・API規約の特定）で調査すべき対象と検出手法を示す。本スキルの `unit_kind` は api 固定であり、組み込み検出器はない。抽出は常にカスタム抽出パス（Claude 自身が戦略宣言に沿って抽出し、スキーマ準拠のマニフェスト JSON を出力する）を使う。

## 調査項目

| 調査対象 | 検出手法 |
|---|---|
| エンドポイント定義の所在 | OpenAPI/Swagger 定義ファイル、Express/Fastify/Hono のルート定義、FastAPI/Django REST のビュー定義、コントローラファイル |
| HTTPメソッドとパス | `app.get()`/`app.post()` 等のメソッド呼び出し、デコレータ（`@Get()`/`@Post()`）、ルートテーブル |
| ミドルウェア | 認証・バリデーション等の共通処理 |
| 除外パターン | テスト用エンドポイント、ヘルスチェック |

## 調査の進め方

1. **フレームワークの確定**: `package.json`・lockファイル、またはバックエンド相当（`requirements.txt`/`pyproject.toml`/`go.mod` 等）から Web フレームワークを特定する
2. **定義所在の追跡**: ルーターの分割マウント（`app.use('/prefix', router)` 等）がある場合、マウント元からルート定義ファイルまで追跡し、最終的なパス（prefix 結合後）を確定する
3. **一次情報の選定**: OpenAPI/Swagger 定義が存在する場合はそれを一次情報とし、実装コードと突合する。食い違いは実装側を正とし、`notes` に記録する
4. **除外の実地確認**: テスト用エンドポイント・ヘルスチェック・モックの実在を `ls`/Grep で確認してから `excludePatterns` に載せる

## マニフェストスキーマ

```json
{
  "generatedAt": "ISO8601",
  "sourceDir": "探索対象ルート",
  "unitKind": "api",
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
      "kind": "endpoint|middleware|unresolved",
      "identifier": "主識別子（例: GET /users/:id）",
      "sourceFile": "主ファイルパス",
      "confidence": "high|medium|low",
      "fileCount": 0,
      "files": [],
      "detectionMethod": "検出手法"
    }
  ]
}
```

## `kind` 値の使い分け

| kind | 用途 |
|---|---|
| `endpoint` | HTTP メソッド + パスが確定した API エンドポイント。エンドポイント数のカウント対象はこの行のみ |
| `middleware` | 認証・バリデーション等の共通処理。エンドポイントとして数えない |
| `unresolved` | 定義の存在は確認できたが、メソッド/パス/実装ファイルのいずれかを確定できなかったもの |

## 記録の指針

- `identifier` は「HTTP メソッド + パス」を推奨する（例: `GET /users/:id`）。パスは prefix 結合後の最終形で記録する
- `unitKey` は連番禁止。内容を要約した意味語キーを付ける（例: `ユーザー-詳細取得`）
- 動的に構築されるルート（変数結合・ループ登録）は、展開ロジックを追跡して最終パスを確定できた場合のみ `endpoint` とし、できなければ `unresolved` に降格する
