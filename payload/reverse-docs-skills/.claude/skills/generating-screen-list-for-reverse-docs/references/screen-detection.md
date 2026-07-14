# 画面（screen）検出戦略ガイダンス

Phase 1（スタック・画面規約の特定）で調査すべき対象と検出手法を示す。本スキルは画面種別（unit_kind=screen）専用であり、他種別の検出戦略は各種別別一覧スキルの references を参照する。

## 検出経路

組み込み検出器 `../../../shared/scripts/unit-list/detect-screens.sh` が対応する（高速パス）。組み込み検出器がPhase 1の調査結果と適合しない場合はカスタム抽出パスを使用する。

## 調査対象と検出手法

| 調査対象 | 検出手法 |
|---|---|
| ルーティング定義の所在と方式 | package.json のフレームワーク・ルーターライブラリ確認。Next.js App/Pages Router、React Router（useRoutes 含む）、慣習ディレクトリ（pages/screens/views） |
| 画面ID命名パターン | ルートパスセグメント・ファイル名・コンポーネント名の規則性 |
| View切替関数 | モーダル・タブ・アコーディオン等の表示切替パターン |
| 除外パターン | tests/stories/mocks 等のノイズディレクトリ |

## 調査手順の詳細

### ルーティング定義の所在特定（Phase 1 Step 2）

- ルーティング定義の所在と方式を特定する。定義と呼び出しが別ファイルの場合（`useRoutes(router)` 等）は定義ファイルまで追跡して所在を確定する
- 完了条件: `path`/`route` 定義を含む実ファイルパスが列挙済み
- 対応する方式の目安:
  - Next.js App Router: `app/` 配下の `page.tsx`/`page.jsx`（`next.config.*` の実在が前提）
  - Next.js Pages Router: `pages/` 配下のファイル（`next.config.*` の実在が前提）
  - React Router: `<Route path=...>` 要素、`createBrowserRouter`/`useRoutes` に渡すルート配列
  - 慣習ディレクトリ: ルーターライブラリ不在時の `pages/`/`screens/`/`views/` 配下

### 画面規約の調査（Phase 1 Step 3）

- 画面ID命名パターン（例: ルートパスや画面コンポーネント名に一貫した業務ID書式があるか）を調べ、`screen-id-regex` の候補値または「なし」を確定する
- View切替関数（`view-switch-pattern`）を調べる。setEditView/ModalMode に限らず、自己管理モーダル（useState+条件レンダリング等）を使うプロジェクトではそのパターンを特定して宣言する
- メニュー定義・画面マスタの有無を確認する。存在すれば画面一覧の突合先として記録する
- 完了条件: `screen-id-regex`/`view-switch-pattern` の候補値または「なし」が確定済み

## マニフェストスキーマ（screen）

配列キーは `screens`（後方互換）。組み込み検出器・カスタム抽出パスのどちらも同一スキーマで出力する。

```json
{
  "generatedAt": "ISO8601",
  "sourceDir": "探索対象ルート",
  "unitKind": "screen",
  "strategy": {
    "extractionMethod": "builtin-*|custom",
    "approvedByUser": true,
    "screenUnitDefinition": "画面1単位の定義",
    "screenIdRegex": "string|null",
    "viewSwitchPattern": "string|null",
    "excludePatterns": []
  },
  "detectionSummary": {
    "method": "builtin-*|custom",
    "screenCount": 0,
    "unresolvedCount": 0
  },
  "screens": [
    {
      "screenKey": "意味キー",
      "screenId": "業務ID（任意）",
      "screenNameGuess": "推定名",
      "kind": "route|embedded-view|unresolved",
      "route": "ルートパス（route の場合）",
      "entryFile": "主ファイルパス",
      "confidence": "high|medium|low",
      "fileCount": 0,
      "files": [],
      "sharedWith": [],
      "detectionMethod": "検出手法"
    }
  ]
}
```

`kind` 値: `route`（ルーティング定義に対応する画面）、`embedded-view`（View切替で表示される埋め込みビュー。`view-switch-pattern` 指定時のみ検出）、`unresolved`（entryFile を解決できなかった候補）。

## 注意事項

- 画面数のカウントには部品ファイル（共有クラスタで参照されるだけのコンポーネント等）を含めない。画面として数えるのは route 行と embedded-view 行のみ
- 動的に構築されるルート文字列（変数結合等）は組み込み検出器では検出できない。静的リテラルの `path` のみが対象
- コメントアウトされたルート定義・import 文は除去してから抽出する（コメント内の定義を実在として誤検出した実害がある）
- Next.js 系検出器は `next.config.*` の実在を必須とする（Vite+React Router プロジェクトの `src/pages/` を Next.js Pages Router と誤判定する実害を防ぐ）
