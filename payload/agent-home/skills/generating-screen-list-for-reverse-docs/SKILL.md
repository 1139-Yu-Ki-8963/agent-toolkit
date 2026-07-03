---
name: generating-screen-list-for-reverse-docs
description: |
  レガシー画面をスタック調査→戦略宣言→検出し画面一覧HTMLを生成する。
  TRIGGER when: 画面一覧作成、reverse-docs向け画面棚卸し、画面境界の確定。
  SKIP: 設計書の生成・記入（本スキルは一覧作成のみ）、往復検証（→rebuilding-code-from-docs）、環境同期（→syncing-reverse-env）、通常実装（→orchestrating-dev-flow）。
invocation: generating-screen-list-for-reverse-docs
type: action
allowed-tools: [Bash, Read, Write, Grep, Glob, AskUserQuestion]
---

# レガシー画面一覧生成スキル

レガシー（既存）コードベースを、スタック調査→検出戦略の宣言→戦略に基づく抽出→整合検証、の順で調査し、「画面」単位にファイルをグルーピングして **画面一覧.HTML**（画面詳細設計の単位を正確に分けるための正本）を作成する。**本スキルの仕事は画面一覧.HTMLの作成のみ**であり、設計書の雛形展開・生成・記入は一切行わない。

汎用の正規表現を無条件に当てるのではなく、対象プロジェクト固有の画面規約（画面IDの命名パターン・ナビゲーション方式）を先に確認してから検出することで、境界の取り違えを防ぐ。

`rebuilding-code-from-docs`（既に存在する設計書の往復検証）・`syncing-reverse-env`（環境同期）とは独立して単独動作する。

## 使用タイミング

- レガシーコードベースの画面一覧を作りたいとき
- 起動引数: ソースコードディレクトリ（探索対象）と出力先ディレクトリ（画面一覧.HTMLの書き出し先）の2つ

## 動作フロー（Phase 1〜4）

### Phase 1: スタック・画面規約の特定

エージェント自身が Read/Grep で以下を調査する。

- `package.json`・lockファイル（`package-lock.json`/`yarn.lock`/`pnpm-lock.yaml`）からフレームワーク・ルーターライブラリを確定する
- ルーター定義ファイルの有無・形式を確認する（`app/`・`pages/`・ルーター設定ファイル等）
- 画面規約を調査する:
  - 画面IDのファイル名命名パターン（例: `T-A-1-113.tsx` のようなコード付きファイル名）
  - メニュー定義・画面マスタの有無
  - ナビゲーション方式: `router.push` 型（URLルーティング）か、`setEditView` 等の状態切替関数によるView切替型か。View切替型の場合は切替関数名を特定する

調査結果を **検出戦略宣言** としてまとめ、AskUserQuestion で1回だけユーザー確認を取る。宣言には以下を含める。

- 画面単位の定義（1ファイル=1画面か、複数ファイルの集合か等）
- `screen-id-regex`（画面IDをファイル名等から抽出する正規表現。命名パターンがなければ「なし」と明記）
- `view-switch-pattern`（View切替型ナビゲーションを検出する正規表現。該当しなければ「なし」と明記）

完了条件: 検出戦略宣言がユーザー承認済み

### Phase 2: 戦略に基づく抽出

`scripts/detect-screens.sh <source-dir> <manifest-out> [--screen-id-regex <re>] [--view-switch-pattern <re>]` を実行する。Phase 1で確定した `screen-id-regex`・`view-switch-pattern` を引数として渡す。

検出チェーン（優先順位）:

1. Next.js App Router: `app/` 配下の `page.tsx/jsx/js` をファイルパスベースで列挙。`(group)` は除去、`[param]`→`:param`、`[...slug]`→`*`
2. Next.js Pages Router: `app/` が無ければ `pages/` 配下（`_app`/`_document`/`api/` 除外）
3. React Router: `createBrowserRouter`/`createHashRouter`/`<Route` を grep し `path` 属性を正規表現抽出（フラット抽出のみ、ネスト親子パス合成は非対応）
4. 慣習ディレクトリ: 1〜3が0件なら `pages/`/`screens/`/`views/` 直下を1画面として扱う。ルートは「不明（フォールバック検出）」
5. 1〜4すべて0件ならハード停止。画面を捏造しない。手動リスト入力へのフォールバックはしない（exit code 3）

`view-switch-pattern` が指定されている場合、View切替型のナビゲーション呼び出しを1階層の静的 grep で検出し、`kind: embedded-view` の独立行としてマニフェストに追加する（import グラフ解析はしない）。同一の埋め込みビューを複数の親画面が参照する場合も行は1つに統合され、`embeddedIn` に親画面キーがカンマ結合で記録される。

各画面候補に `confidence`（high/medium/low）を付与する。ファイル収集はエントリファイルと同一ディレクトリ直下＋直下 `components/`(`_components/`)1階層のみ。

画面キーは意味キー規約（連番禁止）に従い、ルートの静的セグメントから導出する。衝突時はセグメントを拡張して解消し、連番サフィックスは使わない。詳細アルゴリズムは `scripts/detect-screens.sh` 内コメント参照。

検出結果は `$CLAUDE_JOB_DIR/tmp/screen-manifest.json`（未設定時 `${TMPDIR:-/tmp}/claude-job-${session}/tmp/`。`${session}` はセッションIDが取得できなければ任意の一意な値でよい）に一時保存する。

完了条件: 画面マニフェストが1件以上確定している、または0件検出をユーザーに報告して停止している

### Phase 3: 整合検証（スクリプト内で機械実行）

`detect-screens.sh` の内部で自動実行される（Claude が手動で個別コマンドを叩く必要はない）。

- 同一 `(route, entryFile)` の重複を1エントリにマージし、マージ件数を `routeDupCount` として記録する
- 物理ファイルが複数の画面候補に跨って参照される場合、共有クラスタを算出し `sharedWith`／`clusterId` を各エントリに付与する
- ルーティング定義・命名規約のいずれからも解決できなかった候補は `unresolved` として隔離し、`confidence` を強制的に `low` にする
- 共有クラスタに属する画面は個別の `screenNameGuess`（画面名推測）を抑制する（誤った個別名の断定を避けるため）

完了条件: マニフェスト内の重複キー（`route`+`entryFile` の組合せ）が0件

### Phase 4: 画面一覧.HTML 生成

`scripts/build-screen-list.sh <manifest.json> <output-dir>/画面一覧.html` を実行する。

**手作業でのプレースホルダ置換は禁止する**（過去に `entryFile=None` の混入という実害が発生している）。HTML生成は必ずスクリプト経由の決定的処理で行う。

`assets/screen-list-template.html` を土台に、テーブル行と `<script type="application/json" id="screen-manifest">` へマニフェストをそのまま注入する。外部CDN不使用・単一ファイル自己完結。前回生成分が存在する場合、新規検出画面／消滅した画面（廃止候補）の差分をヘッダに追記する。

完了条件: 画面一覧.HTMLが生成され、埋め込みJSONがマニフェストの内容と一致している

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 検出戦略宣言（画面単位の定義・screen-id-regex・view-switch-pattern）がユーザー承認済み |
| Phase 2 | 画面マニフェストが1件以上確定、または0件検出をユーザーに報告して停止している |
| Phase 3 | マニフェスト内の重複キー（route+entryFile の組合せ）が0件 |
| Phase 4 | 画面一覧.HTMLが生成され、埋め込みJSONがマニフェストと一致している |
| **Goal** | 重複キー0件・共有/埋め込み/未解決が可視化された画面一覧.HTMLが生成済み、設計書単位の判断材料が揃っている |

## ツールリファレンス

| ツール | 用途 |
|---|---|
| Bash | `scripts/detect-screens.sh`・`scripts/build-screen-list.sh` の実行 |
| Read | package.json・ルーター定義・テンプレートの参照 |
| Grep/Glob | 画面規約（画面ID命名パターン・View切替関数）・ルーティング定義の調査 |
| Write | 検出戦略宣言用の一時メモが必要な場合のみ（画面一覧.HTML本体はスクリプト経由で生成） |
| AskUserQuestion | Phase 1の検出戦略宣言確認、Phase 2の0件検出時の報告 |

## 推奨手順

- ソースディレクトリは対象プロジェクトの実コードルート（例: `frontend/src`）を指定する。モノレポでアプリが複数ある場合は対象アプリのディレクトリのみを渡す（自動判別なし）
- Phase 1の調査を省略して汎用の `screen-id-regex` を当てない。プロジェクトごとに命名規約・ナビゲーション方式は異なる

## 重要な注意事項

- 設計書（`02_画面基本設計` 等）の雛形展開・生成・記入は一切行わない。本スキルの成果物は画面一覧.HTMLのみ
- Phase 4のHTML手作業組み立てを禁止する。`build-screen-list.sh` を必ず経由し、プレースホルダの手動置換による `entryFile=None` 等のデータ混入を防ぐ
- import グラフ解析は行わない。画面ファイルの収集は物理的同居のみ
- 0件検出時にAskUserQuestionで手動リストを聞き出さない。誤った境界を即興確定させない

## Gotchas

- `build-screen-list.sh` は jq に依存する。未インストール環境では事前に導入する
- React Routerの深いネスト親子パス合成は非対応（フラット抽出のみ）。ネストが深い構成では検出精度が落ちる
- 動的に構築されるルート文字列（変数結合等）は検出できない。静的リテラルの `path` のみが対象
- 埋め込みビュー（`kind: embedded-view`）の検出はPhase 1で `view-switch-pattern` を指定した場合のみ有効。未指定なら検出しない
- 設計書の雛形展開・生成は行わない（本スキルのスコープ外）

## 設計判断

### build-screen-list.sh

**必要性**: 画面一覧.HTML生成をClaude手作業（プレースホルダ置換）で行うと、検証なしのデータ混入が発生する（実例: `entryFile=None` が10件混入）。JSONマニフェストからHTMLへの変換を決定的スクリプトに固定化し、手作業経路を根絶する。

**代替案を採用しなかった理由**:
- Bashツール直叩き: 毎回30行超のjq+ヒアドキュメントを手書きし、エスケープ事故が再発する
- 既存Makefile拡張: 本スキルはプロジェクト非依存でMakefileを持たない
- package.json scripts: 本スキルはプロジェクト横断で動作するため、単一プロジェクトのpackage.jsonに依存できない

**保守責任者**: 人手（ユーザー）

**廃棄条件**: 画面一覧.HTMLの形式が廃止された時

### detect-screens.sh（検出+整合検証の決定的実行）

**必要性**: 画面境界検出と、それに続く重複マージ・共有クラスタ算出・confidence調整は200行を超えるロジックであり、毎回Bash直叩きで実行すると再現性がなく、検出結果が実行者・実行回ごとにブレる。1本のスクリプトに固定化することで、同一入力から同一マニフェストが決定的に得られる。

**代替案を採用しなかった理由**:
- Bashツール直叩き: 200行超のロジックを毎回インラインで書くと再現性がなく、修正のたびに全体を再実装するリスクが高い

**保守責任者**: 人手（ユーザー）

**廃棄条件**: 画面境界検出のアプローチが別スキル・別ツールに置き換わった時
