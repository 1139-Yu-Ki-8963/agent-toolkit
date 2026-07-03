---
name: generating-screen-list-for-reverse-docs
description: |
  レガシー画面をルーティング検出でグルーピングし画面一覧HTMLを生成する。
  TRIGGER when: 画面一覧作成、reverse-docs向け画面棚卸し、画面境界の確定。
  SKIP: 設計書の生成・記入（本スキルは一覧作成のみ）、往復検証（→rebuilding-code-from-docs）、環境同期（→syncing-reverse-env）、通常実装（→orchestrating-dev-flow）。
invocation: generating-screen-list-for-reverse-docs
type: action
allowed-tools: [Bash, Read, Write, Grep, Glob, AskUserQuestion]
---

# レガシー画面一覧生成スキル

レガシー（既存）コードベースを調査し、「画面」単位にファイルをグルーピングして **画面一覧.HTML**（画面詳細設計の単位を正確に分けるための正本）を作成する。**本スキルの仕事は画面一覧.HTMLの作成のみ**であり、設計書の雛形展開・生成・記入は一切行わない。

`rebuilding-code-from-docs`（既に存在する設計書の往復検証）・`syncing-reverse-env`（環境同期）とは独立して単独動作する。

## 使用タイミング

- レガシーコードベースの画面一覧を作りたいとき
- 起動引数: ソースコードディレクトリ（探索対象）と出力先ディレクトリ（画面一覧.HTMLの書き出し先）の2つ

## 基本ワークフロー（Phase 1〜2）

### Phase 1: 画面境界検出

`scripts/detect-screens.sh <source-dir> <manifest-out>` を実行し、以下の優先順位でルーティングを検出する。

1. Next.js App Router: `app/` 配下の `page.tsx/jsx/js` をファイルパスベースで列挙。`(group)` は除去、`[param]`→`:param`、`[...slug]`→`*`
2. Next.js Pages Router: `app/` が無ければ `pages/` 配下（`_app`/`_document`/`api/` 除外）
3. React Router: `createBrowserRouter`/`createHashRouter`/`<Route` を grep し `path` 属性を正規表現抽出（フラット抽出のみ、ネスト親子パス合成は非対応）
4. フォールバック: 1〜3が0件なら `pages/`/`screens/`/`views/` 慣習ディレクトリ直下を1画面として扱う。ルートは「不明（フォールバック検出）」
5. 1〜4すべて0件ならハード停止。画面を捏造しない。手動リスト入力へのフォールバックはしない（exit code 3）

各画面候補に `confidence`（high/medium/low）を付与する。ファイル収集はエントリファイルと同一ディレクトリ直下＋直下 `components/`(`_components/`)1階層のみ（import グラフ解析はしない）。

画面キーは意味キー規約（連番禁止）に従い、ルートの静的セグメントから導出する。衝突時はセグメントを拡張して解消し、連番サフィックスは使わない。詳細アルゴリズムは `scripts/detect-screens.sh` 内コメント参照。

検出結果は `$CLAUDE_JOB_DIR/tmp/screen-manifest.json`（未設定時 `${TMPDIR:-/tmp}/claude-job-${session}/tmp/`）に一時保存する。

完了条件: 画面マニフェストが1件以上確定している、または0件検出をユーザーに報告して停止している

### Phase 2: 画面一覧.HTML 生成

Phase 1の確定結果を実施済み事実のレポートとして `<output-dir>/画面一覧.html` へ出力する。`assets/screen-list-template.html` を土台に、テーブル行と `<script type="application/json" id="screen-manifest">` を注入して `Write` する（専用スクリプトは持たない。プレースホルダの置換は Claude 本体が担う）。

テーブル列: 画面キー／画面名（技術名の機械整形のみ、業務的意訳はしない）／ルート／検出方式／confidence／構成ファイル数／主ファイル。埋め込みJSONのスキーマは `assets/screen-list-template.html` 内コメント参照。外部CDN不使用・単一ファイル自己完結。

前回生成分が存在する場合、新規検出画面／消滅した画面（廃止候補）の差分をヘッダに追記する。

完了条件: `画面一覧.html` が最新の検出結果を反映して書き出し済み

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 画面マニフェストが1件以上確定、または0件検出をユーザーに報告して停止している |
| Phase 2 | `画面一覧.html` が最新の検出結果を反映して書き出し済み |
| **Goal** | 生成画面キーに連番形式が0件、かつ画面一覧.HTML以外の新規ファイルが生成されていない |

## ツールリファレンス

| ツール | 用途 |
|---|---|
| Bash | `scripts/detect-screens.sh` の実行 |
| Read | テンプレートの参照 |
| Write | 画面一覧.html の生成（新規のみ、既存ファイルの書き換えは行わない） |
| Grep/Glob | ルーティング定義・慣習ディレクトリの検索 |
| AskUserQuestion | 0件検出時の報告 |

## 推奨手順

- ソースディレクトリは対象プロジェクトの実コードルート（例: `frontend/src`）を指定する。モノレポでアプリが複数ある場合は対象アプリのディレクトリのみを渡す（自動判別なし）

## 重要な注意事項

- 設計書（`02_画面基本設計` 等）の雛形展開・生成・記入は一切行わない。本スキルの成果物は画面一覧.HTMLのみ
- import グラフ解析は行わない。画面ファイルの収集は物理的同居のみ
- 0件検出時にAskUserQuestionで手動リストを聞き出さない。誤った境界を即興確定させない

## Gotchas

- React Routerの深いネスト親子パス合成は非対応（フラット抽出のみ）。ネストが深い構成では検出精度が落ちる
- 動的に構築されるルート文字列（変数結合等）は検出できない。静的リテラルの `path` のみが対象
