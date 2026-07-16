# 画面遷移の検出戦略ガイダンス

Phase 1（Router 種別の特定・検出戦略の宣言）で調査すべき対象と検出手法を示す。画面遷移の検出に組み込み検出器はなく、カスタム抽出パスのみを使う。

## 調査対象と検出手法

| 調査対象 | 検出手法 |
|---|---|
| Router 種別 | `package.json` の依存関係（`react-router-dom`／`next`／`vue-router` 等）、import 文の形跡 |
| 遷移定義の所在 | Router 設定ファイル（ルート定義本体）、画面コンポーネント内の遷移呼び出し |
| 遷移 API パターン | `navigate()`／`<Link>`／`redirect()` 等、Router 種別ごとの遷移手段 |
| 除外パターン | テスト用ダミー遷移、Storybook 等の開発用ルーティング |

## Router 種別ごとの検出パターン

| Router 種別 | 定義箇所 | 遷移 API | confidence 基準 |
|---|---|---|---|
| React Router（v6 系） | `<Routes>`/`<Route path=... element=.../>` または `createBrowserRouter()` | `useNavigate()` が返す関数呼び出し（`navigate('/path')`）、`<Link to="/path">`、`<Navigate to="/path" />` | 静的文字列一致は high。テンプレート文字列・変数展開は medium。変数のみで静的解決不能なものは low |
| Next.js App Router | `app/**/page.tsx` のディレクトリ構造（画面一覧の `route` 側で既に反映済み） | `next/link` の `<Link href="/path">`、`useRouter().push('/path')`、`next/navigation` の `redirect('/path')` | 同上 |
| Next.js Pages Router | `pages/**` のファイル構造（画面一覧の `route` 側で既に反映済み） | `next/link` の `<Link href="/path">`、`useRouter().push('/path')`、`getServerSideProps` の `{ redirect: { destination: '/path' } }` | 同上 |
| Vue Router | `createRouter({ routes: [...] })` のルート定義配列 | `<router-link to="/path">`、`this.$router.push('/path')`／`router.push('/path')`、ルート定義内の `redirect: '/path'` | 同上 |

## page-data 抽出時の注意

- Router 定義とコンポーネント内の遷移呼び出しの両方が存在する場合、遷移呼び出し側（実際に発火する箇所）を `sourceRef` の基準にする。Router 定義側は `to` の妥当性確認にのみ使う
- 動的セグメント（`/users/:id`）を含む route は、遷移呼び出し側の実引数（`/users/${id}`・`/users/' + id`）とパターン単位で突合する。セグメント名まで一致すれば medium、完全な静的一致のみ high とする
- 変数のみで構成され静的解決できない遷移先（`navigate(path)` の `path` が関数引数由来等）は、宛先未解決として `unresolved[]` へ回す。confidence を無理に付けて `edges[]` に含めない
- コメントアウトされた遷移呼び出し（`// navigate('/old')` 等）は抽出前に除去する
- 同一発生元・同一宛先への遷移が複数箇所（条件分岐によるボタン違い等）で発火する場合は、`trigger` を分けて別々の `edges[]` 要素として記録する（1 遷移経路 = 1 edge）
