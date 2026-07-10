# 帳票の検出戦略ガイダンス

Phase 1（スタック・帳票規約の特定）で調査すべき対象と検出手法を示す。本スキルは `unit_kind=report` 固定であり、他種別の検出戦略は各種別別一覧スキルの references を参照する。

## 検出方式

組み込み検出器なし。カスタム抽出パスを使用する（Claude 自身が戦略宣言に沿って抽出手順を設計・実行し、スキーマ準拠のマニフェスト JSON を出力する）。

## 調査項目

| 調査対象 | 検出手法 |
|---|---|
| 帳票定義の所在 | テンプレートファイル（Jasper/BIRT/Crystal）、PDF/Excel 生成コード（puppeteer/pdfkit/ExcelJS）、レポート定義設定 |
| 出力形式 | PDF/Excel/CSV/HTML |
| データソース | クエリ・API 呼び出し・集計ロジック |
| 除外パターン | テスト用テンプレート |

## 抽出時の観点

- 「1帳票」の単位を先に確定する。テンプレートファイル1枚＝1帳票のプロジェクトもあれば、生成関数1つ＝1帳票のプロジェクトもある。テンプレートと生成コードが対になる場合は主ファイル（`sourceFile`）をどちらにするかを戦略宣言の `notes` に明記する
- 同一テンプレートを複数の出力形式（PDF と Excel 等）で使い回す場合、形式ごとに分けず1帳票として数え、出力形式の違いは `identifier` や `notes` で表現する
- コメントアウトされた帳票定義・import 文は抽出前に除去する（コメント内の定義を実在として誤検出した実害がある）

## マニフェストスキーマ

```json
{
  "generatedAt": "ISO8601",
  "sourceDir": "探索対象ルート",
  "unitKind": "report",
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
      "kind": "template|generator|unresolved",
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

## `kind` の区分値

| 値 | 意味 |
|---|---|
| `template` | テンプレートファイルが帳票の主体（Jasper/BIRT/Crystal 等の定義ファイル、HTML テンプレート等） |
| `generator` | 生成コードが帳票の主体（pdfkit/ExcelJS 等でコードから直接組み立てる方式） |
| `unresolved` | 帳票の存在は確認できたが主ファイルを解決できなかったもの（隔離用） |
