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

## ブラウザバック検出パターン

`triggerType` を「ブラウザバック」、`to` を空文字列にする。遷移先はランタイム依存で静的に確定しないため、`unresolved[]` にはせず `edges[]` に含める(発生元は確定しているため)。

| Router 種別 | 検出パターン | 備考 |
|---|---|---|
| React Router(v6 系) | `navigate(-1)`, `navigate(-N)` | `useNavigate()` が返す関数の引数が負数 |
| Next.js(App / Pages 共通) | `router.back()`, `window.history.back()` | `useRouter()` のメソッド |
| Vue Router | `router.back()`, `router.go(-N)`, `this.$router.go(-1)` | |
| 汎用(フレームワーク非依存) | `history.back()`, `history.go(-N)`, `window.history.back()` | |

### アプリの戻るボタンとの区別

`history.back()` / `router.back()` を呼ぶ場合のみ triggerType を「ブラウザバック」にする。以下はブラウザバックではなく、別のパターンとして検出する。

| パターン | 検出例 | 記録方法 |
|---|---|---|
| 遷移先固定の戻りリンク | `<a href="/cart">カートに戻る</a>`、`<Link to="/products">一覧に戻る</Link>` | triggerType「リンク遷移」、`to` に固定先 |
| 遷移先が動的に変わる戻りボタン | `navigate(returnUrl)`、`router.push(query.from \|\| '/default')` | 条件ごとに別 edge を作成。triggerType「リダイレクト」、`to` にそれぞれの遷移先、`condition` に「〇〇から遷移した場合」 |

- `returnUrl` / `from` / `redirect` 等のクエリパラメータやステートで遷移先を振り分けるコードは、パターン2（動的な戻りボタン）として検出する
- コード上で `history.back()` と `navigate(returnUrl)` の両方が条件分岐で使い分けられている場合は、それぞれ別の edge として記録する

## 条件付き遷移(ガード)の検出パターン

既存の `triggerType`(通常は「リダイレクト」)をそのまま使い、`condition` フィールドに発動条件を自由記述で記録する。ガード専用の `triggerType` は追加しない。

| Router 種別 | 検出パターン | condition 記載例 |
|---|---|---|
| React Router(v6 系) | `<Navigate>` inside conditional render, `redirect()` in `loader` | "未認証の場合" |
| Next.js App Router | `redirect()` inside `middleware.ts`, conditional in Server Component | "未認証の場合" |
| Next.js Pages Router | `getServerSideProps` の `redirect` | "セッション無効の場合" |
| Vue Router | `beforeEach` / `beforeEnter` ガード内の `next('/login')` | "認証トークン期限切れの場合" |

- `condition` はコードのガード条件を日本語で要約する自由記述
- 同一 `from`/`to` でも条件が異なれば別の edge として記録する
