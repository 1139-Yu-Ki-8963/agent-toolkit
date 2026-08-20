# ER 関連の検出戦略ガイダンス

Phase 1（前提確認 + 検出戦略宣言）で調査すべき対象と、Phase 2（抽出）で使う ORM 別 FK 検出パターンを示す。エンティティ自体はテーブル一覧 manifest から取るため、本ガイダンスは関連（FK）の抽出だけを扱う。

## 調査対象と検出手法

| 調査対象 | 検出手法 |
|---|---|
| ORM/マイグレーションツールの特定 | `package.json`・lock ファイル・`requirements.txt`/`pyproject.toml` 等の依存関係。テーブル一覧生成時に確定した定義（マイグレーション or ORM モデル）と同じ側を使う |
| FK 定義の所在 | ORM モデルのカラム定義・`relationship`/`@relation` 等の関連宣言・マイグレーションファイルの `REFERENCES`/`FOREIGN KEY` 句 |
| 除外パターン | テスト用マイグレーション・シード・コメントアウトされた定義 |

## ORM 別 FK 検出パターン

### SQLAlchemy

- カラム定義の `ForeignKey("<table>.<column>")` 引数からテーブル名を抽出する（例: `ForeignKey("users.id")`）
- `relationship(...)` 単体では対象テーブルが確定しない場合がある（文字列引数がモデルクラス名のことがあるため）。`ForeignKey` 側のテーブル名を正とし、`relationship` は補助情報として扱う
- 複合外部キー（`ForeignKeyConstraint`）は関連先テーブルを 1 件の関連として集約する

### Prisma

- モデル定義内の `@relation(fields: [...], references: [...])` から参照元フィールドと参照先モデルを抽出する
- 参照先モデル名は schema.prisma 内の `model <Name>` 宣言と対応させ、そのモデルに対応するテーブル一覧 manifest の `identifier` へ変換する

### 生 SQL migration

- `FOREIGN KEY (<column>) REFERENCES <table>(<column>)` 句を抽出する
- `ALTER TABLE ... ADD CONSTRAINT ... FOREIGN KEY ...` 形式も同様に抽出対象とする
- コメントアウトされた DDL（`-- FOREIGN KEY ...` 等）は抽出前に除去する

## cardinality の導出規則

| 検出条件 | cardinality |
|---|---|
| FK 列に一意制約（`unique=True`／`@unique`／`UNIQUE` 制約）が付与されている | `1:1` |
| FK 列に一意制約がない（既定） | `1:N` |
| 中間テーブル（複合主キーが両側の FK で構成される）を介した関連 | `N:N`。中間テーブル自体は独立エンティティとして `entities[]` に残す |

導出できない場合は cardinality を推測で埋めず、`unresolved[]` へ回す。

## manifest 外参照の扱い

FK の参照先テーブルが、テーブル一覧 manifest の `units[]`（`kind != "unresolved"`）に存在しない場合、その関連は `relations[]` に含めない。この場合は次の形式で `unresolved[]` へ分離する。

```json
{ "label": "<参照元>.<列名> → <参照先テーブル名>", "reason": "参照先テーブル<参照先テーブル名>がテーブル一覧manifestに存在しない", "sourceRef": "<FK定義箇所>" }
```

## 抽出時の注意

- マイグレーションと ORM モデルの両方が存在する場合、テーブル一覧生成時に確定した定義と同じ側から FK を抽出する。両方を無差別に走査すると同一関連の重複検出になる
- 自己参照 FK（同一テーブル内の親子関係）は `from`/`to` が同一の `entities[].key` になる。孤児関連の判定対象にはならない
- コメントアウトされた定義（`-- FOREIGN KEY ...`・コメント内のモデル宣言等）は抽出前に除去する
