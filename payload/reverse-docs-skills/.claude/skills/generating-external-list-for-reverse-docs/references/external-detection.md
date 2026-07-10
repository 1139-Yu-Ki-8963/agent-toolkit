# 外部連携（external）の検出戦略ガイダンス

Phase 1（スタック・連携規約の特定）で調査すべき対象と検出手法を示す。本スキルは `unit_kind=external` 固定であり、組み込み検出器は存在しない。カスタム抽出パスのみを使う。

## 調査対象と検出手法

| 調査対象 | 検出手法 |
|---|---|
| 外部連携定義の所在 | API クライアントラッパー、SDK 統合コード、webhook ハンドラ、メッセージキューコンシューマ |
| プロトコル | REST/GraphQL/gRPC/SOAP/WebSocket/メッセージキュー |
| 認証方式 | API キー/OAuth/証明書 |
| 除外パターン | モック・スタブ |

## 調査の観点（Phase 1 各 Step への対応）

| Step | 外部連携での読み替え |
|---|---|
| Step 1（スタック確定） | HTTP クライアントライブラリ（axios/fetch ラッパー/requests 等）・外部サービス SDK・キュークライアント（AMQP/Kafka クライアント等）の依存を lockファイルから確定する |
| Step 2（定義の所在） | クライアントラッパーの配置ディレクトリ、webhook 受信ルートの登録箇所、コンシューマの購読定義を実ファイルパスで列挙する |
| Step 3（識別パターン） | 接続先 URL・API キー等を保持する環境変数名・設定キー名の規則性、連携先ごとの命名規約（`XxxClient`/`XxxGateway` 等）を調査する |
| Step 4（除外パターン） | tests/mocks/stubs 等のテスト用偽クライアント・スタブ実装を除外リストに載せる |

## 境界の判断基準

- 外部連携として数えるのは「プロセス外・組織外のシステムとの通信」を担う単位。自プロジェクト内の別モジュール呼び出しは含めない
- 同一連携先に対する複数ファイル（クライアント本体・型定義・設定）は 1 ユニットにまとめ、`files` に列挙する
- 送信（クライアント）と受信（webhook・コンシューマ）は `kind` で区別する

## マニフェストスキーマ（external）

```json
{
  "generatedAt": "ISO8601",
  "sourceDir": "探索対象ルート",
  "unitKind": "external",
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
      "kind": "client|webhook|unresolved",
      "identifier": "主識別子（連携先名・エンドポイント等）",
      "sourceFile": "主ファイルパス",
      "confidence": "high|medium|low",
      "fileCount": 0,
      "files": [],
      "detectionMethod": "検出手法"
    }
  ]
}
```

`kind` の値:

- `client`: 外部システムへの送信側（API クライアント・SDK 統合・キュー発行）
- `webhook`: 外部システムからの受信側（webhook ハンドラ・キューコンシューマ）
- `unresolved`: 連携の形跡はあるが主ファイル・連携先を確定できなかったもの（隔離用）
