# 機能検出戦略ガイダンス（unit_kind=feature・派生一覧）

generating-feature-list-for-reverse-docs の Phase 1〜3 が従うグルーピング規約の正本。機能一覧は既存の種別別一覧（画面・API・テーブル等）の派生グルーピングであり、コードから直接検出するユニットではない。

## 用語

| 用語 | 定義 |
|---|---|
| 機能 | 同一の業務対象（エンティティ）への操作一式。一覧・詳細・登録・編集・削除・一括操作・エクスポートの各画面・APIを1機能に集約する |
| 大分類（category） | 機能を束ねる業務領域。ルートprefix第1セグメント単位で境界を引く。2階層（大分類 + 機能）の上位 |
| 派生一覧 | 既存一覧マニフェスト + コード構造から導出する一覧。unit_kinds_present の存在判定対象外（機能は常に存在するため） |

## 入力

| 入力 | 必須/任意 | 取得方法 |
|---|---|---|
| 画面一覧マニフェスト | 必須 | `<output_dir>/画面一覧/画面一覧.html` 内の `<script type="application/json" id="screen-manifest">` から抽出。不在なら ERROR で停止する |
| API一覧・テーブル一覧・バッチ一覧・帳票一覧・外部連携一覧の各マニフェスト | 任意 | 各一覧HTML内の `<script type="application/json" id="unit-manifest">` から抽出。`<output_dir>` 配下に実在するものすべてを機械的に列挙して入力とする（ユーザー指示は不要） |
| コード構造 | 必須 | `source_dir` からルート定義・ナビメニュー・バックエンドルーターの prefix/tags・ディレクトリ構造を Grep/Read で特定する |

## 手がかり優先度表

| 優先 | 手がかり | 抽出元の例 | 用途 |
|---|---|---|---|
| ① ルートprefix第1セグメント | ルート定義（createBrowserRouter の配列・pages ルーティング・ルーター登録） | `/master/*` → マスタ管理 | **大分類境界の決定（唯一の境界決定手段）** |
| ② ナビメニュー・設定ハブ項目 | ナビコンポーネント（Footer・Header・Sidebar）の項目定義 | 「履歴」「編成」等の表示文言 | 大分類の**名前付けのみ**（境界には使わない。ナビは全機能を網羅しないため） |
| ③ APIプレフィックス / tags | バックエンドのルーター登録（include_router の prefix・tags） | `/api/battles/*` | 機能への関連API割当・①の裏取り |
| ④ ディレクトリ構造 | pages/ 配下等の機能別サブフォルダ | `pages/master/` | 補助裏取り（単独では low confidence） |

手がかり自体の強弱はこの順位と同一（①が最強・④が最弱）。

## 競合解決フロー

1. 大分類の境界は常に①で引く。①が引けない画面（独立ルートを持たない埋め込みビュー等）のみ④で仮置きし、confidence を low とする
2. ③が①と異なる大分類を示唆する場合は①を採用し、confidence を1段下げ、当該ユニットの notes に競合内容を記録する
3. ②は境界の決定に影響させない（命名のみに使う）
4. APIプレフィックスと tags が競合する場合は prefix を採用する（tags は命名の参考に留める）

## 機能分割規約（2階層・CRUD集約）

- 大分類内で画面群を業務対象ごとに機能へ分割する
- 同一業務対象への操作一式（一覧・詳細・登録・編集・削除・一括操作・エクスポート）は1機能に集約する。例: `/master/teams`・`/master/teams/:id`・`/master/teams/:id/characters` はチーム管理の1機能
- 業務対象が異なれば別機能とする。例: `/master/characters` と `/master/supports` は同じ大分類（マスタ管理）でも別機能
- 目安粒度: 画面一覧の 1〜5 画面が 1 機能に対応する
- 画面を持たないバックエンド機能（API群のみで構成される推薦・割当等の機能）は、relatedScreens を空配列にして機能行を立ててよい（API一覧の tags・prefix を根拠に記録する）

## 大分類の統合規則

①で引いた境界（機能の分割）は変えずに、大分類のみを上位の業務領域へ統合してよい。

- 発動条件: 第1セグメントをそのまま大分類にすると「機能1件のみの大分類」が過半になる、または大分類数が10を超える場合
- 統合の根拠: ②ナビ・設定ハブの領域文言、③APIルーターの共通prefix/tags、画面間の遷移関係。統合の根拠を各機能の notes に記録する
- 統合後の大分類数の目安: 5〜10
- 実測例（<project>）: 第1セグメントそのままでは大分類17（うち機能1件のみの大分類が12）となり読み手の全体把握を阻害した。統合規則の適用で8大分類に収束した

## confidence 基準（3値）

| 値 | 基準 |
|---|---|
| high | 異なる2種以上の手がかり（例: ①+③）が同一の大分類・機能割当を支持する |
| medium | 単一の手がかりのみが割当を支持する（①のみ等） |
| low | ④のみで割り当てた場合、または競合解決（上記フロー2）で降格した場合 |

「複数の手がかりが支持」の定義: ①〜④のうち**異なる番号の手がかり2つ以上**が同一の割当を示すこと。

## unresolved 基準

- ①〜④のいずれの手がかりでも大分類へ割り当てられない画面・APIのみ `kind: "unresolved"` とする
- low confidence は unresolved にしない（割当のうえ要確認として扱う）
- unresolved が残った状態もスキルの完了とみなす（欠陥ではなく人間への引き継ぎ事項）

## unitKey / unitId / category / summary の命名

| フィールド | 規約 |
|---|---|
| unitKey | 日本語の意味語キー（連番禁止）。例: `キャラクター管理` |
| category | 日本語の業務語。ナビ・設定ハブの表示文言を第一候補、該当がなければルートprefixの意味から業務語で命名する |
| unitId | unitKey を英語の業務語へ訳しケバブケース化した値。訳語の優先順位: ルートセグメント > ディレクトリ名 > APIエンドポイント名（コード内の実識別子を優先する） |
| summary | その機能が業務としてできることの1文 |

## related* 突合規約

- スコープ: 同一 `<output_dir>` 配下の一覧マニフェスト同士（= 同一リバース元リポジトリ）に限る
- relatedScreens: 機能に割り当てた画面の screenKey（画面一覧マニフェスト `screens[].screenKey` の実値）
- relatedApis: 画面の entryFile から辿れるデータ取得コード（fetch・APIクライアント呼び出し）の endpoint を API一覧マニフェストの `units[].identifier` に照合し、一致した `units[].unitKey` を記録する
- relatedTables: API の sourceFile から参照モデル・テーブル名を辿り、テーブル一覧マニフェストの `units[].unitKey` に照合して記録する
- 解決できない場合は空のままとする（推測で埋めない）
- 参照元一覧が未生成の種別は空配列とする

## 代表 identifier / sourceFile

- identifier: 機能の代表ルートprefix（機能の起点画面のルート）
- sourceFile: 機能の起点画面（一覧画面など、その機能に入るとき最初に開く画面）の entryFile。validate-manifest.sh の sourceFile-実在検査を通る形式（`sourceDir` 相対パスまたは絶対パス）で記録する

## マニフェストスキーマ（unit_kind=feature）

validate-manifest.sh の非screen汎用分岐（`units`/`unitKey`/`identifier`/`sourceFile`/`unitIdRegex`/`unitCount`）に準拠し、feature 固有フィールド（category・summary・relatedScreens・relatedApis・relatedTables）を拡張する。detectionSummary.unitCount は units 配列の全要素数（unresolved 含む）、unresolvedCount は kind=unresolved の要素数。

```json
{
  "generatedAt": "2026-01-01T00:00:00Z",
  "sourceDir": "/path/to/source",
  "unitKind": "feature",
  "strategy": {
    "extractionMethod": "custom",
    "unitIdRegex": "^[a-z0-9-]+$",
    "approvedByUser": true,
    "inputManifests": ["<output_dir>/画面一覧/画面一覧.html"],
    "groupingSignals": ["route-prefix", "api-prefix", "nav-menu", "directory"],
    "excludePatterns": []
  },
  "detectionSummary": { "method": "custom", "unitCount": 2, "unresolvedCount": 1 },
  "units": [
    {
      "unitKey": "キャラクター管理",
      "unitId": "character-master",
      "unitNameGuess": "キャラクター管理",
      "kind": "feature",
      "category": "マスタ管理",
      "identifier": "/master/characters",
      "sourceFile": "frontend/src/pages/master/CharactersPage.tsx",
      "summary": "キャラクターマスタの一覧表示・登録・編集",
      "relatedScreens": ["character-list"],
      "relatedApis": ["characters-crud"],
      "relatedTables": ["characters"],
      "confidence": "high",
      "fileCount": 1,
      "detectionMethod": "route-prefix+api-tag"
    }
  ]
}
```

- `kind` の区分値は `feature`（通常行）と `unresolved`（割当不能行）の2値のみ
- unresolved 行は category を持たなくてよい（`null` 可）。relatedScreens には自分自身の screenKey を記録する

## 検証

1. `validate-manifest.sh <manifest.json> --unit-kind feature` の7項目検証（機械実行）
2. related* 参照実在の jq 自前検査（validate-manifest.sh の参照整合検査は screen 専用のため、本種別ではスキルの Phase 5 が実施する）。検査内容: relatedScreens の各値が画面一覧マニフェストの `screens[].screenKey` に、relatedApis / relatedTables の各値が対応一覧の `units[].unitKey` に実在すること（形式チェックではなく実在照合）
3. 完全性ゲート（機械強制）: 画面一覧の全 screenKey が「いずれかの機能の relatedScreens または unresolved 行」に載っていること（取りこぼしゼロ）。Phase 3 Step 2 と Phase 6 Step 2(Gate B) の2箇所で `comm -13` により機械検査する。Phase 3 は早期検知（ユーザー承認前に全画面割り当て済みを保証）、Phase 6 は最終防衛線（Phase 4 の API/テーブル紐付け中に relatedScreens が意図せず変更された場合の安全網）
4. API取りこぼし検査（任意・API一覧が入力にある場合）: API一覧の全 unitKey が「いずれかの機能の relatedApis」に載っているかを確認し、載らない API は「画面を持たないバックエンド機能」の候補として機能行の追加を検討するか、割当根拠ゼロなら unresolved として記録する

## Stage 2: API紐付け手順

Phase 4 Step 1 が従う API 紐付けの詳細手順。

### 入力

- 機能マニフェスト（Phase 3 出力。relatedScreens が確定済み、relatedApis は空配列）
- 画面マニフェスト（screens[].screenKey, files[], entryFile）
- API一覧マニフェスト（units[].unitKey, identifier, sourceFile）。未生成の場合は本 Stage をスキップし relatedApis は空配列のまま

### files[] フォールバック

画面マニフェストの `files[]` は `detect-screens.sh --resolve-files` が BFS import 追跡で算出した画面専有ファイル集合である。

| files[] の状態 | 処理 |
|---|---|
| 非空 | files[] 全ファイルを grep 対象とする |
| 空（BFS 未実行または結果が空） | entryFile のみを grep 対象とする。import 先のモジュール内の API 呼び出しを見逃す可能性がある |
| entryFile も空 | 当該画面の API 紐付けをスキップし relatedApis は空のまま |

files[] が空の画面が多い場合は、画面一覧スキルの `--resolve-files` サブコマンドで files[] を再生成してから本 Stage を実行することを推奨する。

### grep パターンの識別

API 呼び出しパターンはプロジェクト固有であり、Phase 1 Step 2 で特定する。代表的なパターン:

| フレームワーク | grep パターン例 |
|---|---|
| fetch | `fetch\s*\(["'\x60][^"'\x60]*["'\x60]` |
| axios | `axios\.\(get\|post\|put\|delete\|patch\)` |
| 生成クライアント | プロジェクト固有の API クライアントメソッド名 |
| tRPC | `trpc\.\w+\.\(query\|mutate\|useQuery\|useMutation\)` |
| GraphQL | `gql\x60[^$]*\x60` または `use\(Query\|Mutation\)` |

Phase 1 で特定したパターンを Phase 4 でそのまま適用する。パターンが不明な場合は `grep -rn 'fetch\|axios\|api' <files>` で広く拾い、ノイズを手動で除去する。

### 照合と残余裁定

1. grep で抽出した endpoint 文字列を正規化する（ベース URL 除去、パスのみ抽出）
2. 正規化した endpoint を API一覧マニフェストの `units[].identifier` と完全一致で照合する
3. 完全一致しない endpoint は残余リストに記録する
4. 残余について Claude が曖昧一致を裁定する: パスパラメータの表記差異（`/users/:id` vs `/users/${id}` vs `/users/[id]`）のみ許容する。それ以外の推測は禁止
5. 裁定後も一致しない endpoint は空のままとし、当該機能の notes に「未照合 API endpoint: ...」として記録する

### 出力

各機能の `relatedApis` に一致した API unitKey の配列を記録する。

## Stage 3: テーブル紐付け手順

Phase 4 Step 2 が従うテーブル紐付けの詳細手順。Stage 2 の出力（紐付いた API unitKey の集合）を入力とする。

### 入力

- Stage 2 で relatedApis に記録された API unitKey の集合
- API一覧マニフェスト（units[].unitKey, sourceFile）
- テーブル一覧マニフェスト（units[].unitKey, identifier）。未生成の場合は本 Stage をスキップし relatedTables は空配列のまま

### 処理手順

1. relatedApis に含まれる各 API unitKey について、API一覧マニフェストの `units[].sourceFile` を取得する
2. sourceFile から ORM モデル import・テーブル名参照を grep する

| ORM/方式 | grep パターン例 |
|---|---|
| Prisma | `prisma\.\w+\.\(findMany\|findUnique\|create\|update\|delete\)` → モデル名抽出 |
| TypeORM | `@Entity\|getRepository\|\.find\|\.save` → エンティティ名抽出 |
| Sequelize | `define\|Model\.init\|belongsTo\|hasMany` → モデル名抽出 |
| 生SQL | `FROM\s+\w+\|INSERT\s+INTO\s+\w+\|UPDATE\s+\w+` → テーブル名抽出 |

3. 抽出したモデル名/テーブル名をテーブル一覧マニフェストの `units[].unitKey` または `units[].identifier` と照合する
4. ORM モデル名と DB テーブル名が異なる場合（例: `User` モデル → `users` テーブル）は、複数形化・スネークケース化を試みて照合する。それでも一致しない場合は Claude が裁定する（推測禁止）

### 出力

各機能の `relatedTables` に一致したテーブル unitKey の配列を記録する。1つの API が複数テーブルを参照する場合はすべて記録する。
