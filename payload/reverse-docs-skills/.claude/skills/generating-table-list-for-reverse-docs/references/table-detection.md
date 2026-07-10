# テーブル種別の検出戦略ガイダンス

Phase 1（スタック・テーブル規約の特定）で調査すべき対象と検出手法を示す。テーブル種別（`unit_kind=table` 固定）に組み込み検出器はなく、カスタム抽出パスのみを使う。

## 調査対象と検出手法

| 調査対象 | 検出手法 |
|---|---|
| テーブル定義の所在 | マイグレーションファイル（Prisma/TypeORM/Knex/Alembic 等）、ORM モデル定義、SQL DDL |
| スキーマ情報 | カラム名・型・制約・インデックス |
| ビュー定義 | CREATE VIEW 文、ORM のビュー定義 |
| 除外パターン | テスト用マイグレーション、シード |

## マニフェストスキーマ（テーブル種別）

配列キーは `units` とする。

```json
{
  "generatedAt": "ISO8601",
  "sourceDir": "探索対象ルート",
  "unitKind": "table",
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
      "kind": "table|view|migration|unresolved",
      "identifier": "主識別子（テーブル名・ビュー名）",
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
| `table` | CREATE TABLE・ORM モデルとして定義される実テーブル |
| `view` | CREATE VIEW・ORM のビュー定義 |
| `migration` | テーブル/ビューへ集約できない独立マイグレーション（データ移行専用等） |
| `unresolved` | 定義ファイルは見つかったが実体を特定できないもの（隔離用） |

## 抽出時の注意

- マイグレーションと ORM モデルの両方が存在する場合、どちらを正本とするかを先に確定する。両方を無差別に数えると同一テーブルの重複検出になる
- 同一テーブルへの create → alter の積み重ねはテーブル単位に集約し、`files` に関連マイグレーションを列挙する
- コメントアウトされた DDL（`-- CREATE TABLE ...` 等）は抽出前に除去する
