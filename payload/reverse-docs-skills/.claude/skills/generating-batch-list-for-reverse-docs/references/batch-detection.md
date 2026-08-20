# バッチ種別の検出戦略ガイダンス

Phase 1（スタック・バッチ規約の特定）で調査すべき対象と検出手法を示す。本スキルは `unit_kind=batch` 固定であり、組み込み検出器は存在しない。抽出は常にカスタム抽出パス（Claude 自身が戦略宣言に沿って抽出し、スキーマ準拠のマニフェスト JSON を出力する）を取る。

## 調査対象と検出手法

| 調査対象 | 検出手法 |
|---|---|
| バッチ定義の所在 | cron 定義（crontab/node-cron/APScheduler）、ジョブスケジューラ設定（Bull/Celery）、CLI コマンド定義 |
| 実行スケジュール | cron 式、実行間隔、トリガー条件 |
| 入出力 | 処理対象データソース、出力先 |
| 除外パターン | ワンショットスクリプト、マイグレーション |

## 調査の進め方

1. **依存定義からスケジューラを特定する**: `package.json`（node-cron/Bull/Agenda 等）、`requirements.txt`/`pyproject.toml`（APScheduler/Celery 等）を確認する。依存定義が無い場合は import 文・API 使用形跡（`cron.schedule(`・`@app.task` 等）から推定する
2. **定義ファイルを列挙する**: スケジューラごとの登録箇所（ジョブ登録呼び出し・設定ファイル・crontab エントリ）を Grep で洗い出し、実ファイルパスを確定する
3. **識別要素を確定する**: ジョブ名の命名パターン（`unit-id-regex` の候補）、cron 式・実行間隔・トリガー条件、処理対象データソースと出力先を記録する
4. **ノイズを除外する**: ワンショットスクリプト（一度きりのデータ修正等）・マイグレーション・テスト用ジョブは一覧に含めない

## マニフェストスキーマ（batch）

```json
{
  "generatedAt": "ISO8601",
  "sourceDir": "探索対象ルート",
  "unitKind": "batch",
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
      "nameConfidence": "confirmed|inferred",
      "kind": "scheduled|triggered|unresolved",
      "identifier": "主識別子（ジョブ名・cron エントリ名等）",
      "sourceFile": "主ファイルパス",
      "confidence": "high|medium|low",
      "fileCount": 0,
      "files": [],
      "detectionMethod": "検出手法"
    }
  ]
}
```

## `kind` 値の区分

| kind | 意味 |
|---|---|
| `scheduled` | 定期実行ジョブ。cron 式・実行間隔で自動起動される |
| `triggered` | トリガー起動ジョブ。イベント・キュー投入・手動実行（CLI コマンド）で起動される |
| `unresolved` | 定義は検出したが起動方式・実体ファイルを確定できないもの。実在するかのように断定せず隔離する |

## businessClass・triggerConfirmed（任意フィールド。1-9・1-19）

`定期` / `手動` 等の業務上の分類は、`kind`（上表の技術的な種類）ではなく任意フィールド `businessClass` へ記録する。また、実行契機（`kind` が示す起動方式の裏付けとなる cron 定義・イベント登録等）を人間が確認済みかどうかは `triggerConfirmed`（boolean）へ記録する。`execMethod`（手動実行のコマンド手順）とは別概念であり、契機そのものの確認状況を表す。スキーマ定義は `delivery-payload/references/manifest-schema-extensions.md` の「batches（バッチ）」節を参照する。
