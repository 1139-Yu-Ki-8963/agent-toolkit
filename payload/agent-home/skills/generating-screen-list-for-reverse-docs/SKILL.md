---
name: generating-screen-list-for-reverse-docs
description: |
  レガシー画面をルーティング検出→画面一覧HTML化→02_画面基本設計へ雛形展開する。
  TRIGGER when: 画面一覧作成、reverse-docsスキャフォールド、画面基本設計書雛形生成。
  SKIP: 環境同期（→syncing-reverse-env）、設計書品質検証（→rebuilding-code-from-docs）、通常実装（→orchestrating-dev-flow）。
invocation: generating-screen-list-for-reverse-docs
type: action
allowed-tools: [Bash, Read, Write, Edit, Grep, Glob, AskUserQuestion]
---

# レガシー画面一覧生成スキル

レガシー（既存）コードベースを調査し、「画面」単位にファイルをグルーピングして **画面一覧.HTML**（画面詳細設計の単位を正確に分けるための正本）を作成する。同じ粒度で `templates/reverse-docs/02_画面基本設計/` を対象プロジェクトへスキャフォールド展開する。

`rebuilding-code-from-docs`（既に存在する設計書の往復検証）・`syncing-reverse-env`（環境同期）とは独立して単独動作する。§1〜§16 の本文（業務ルール等）は書かない。機械的に確定できる事実（画面名・ルート・構成ファイル一覧）のみを frontmatter・§15.1 に反映し、それ以外はテンプレートのプレースホルダのまま残す。

## 使用タイミング

- レガシーコードベースの画面一覧を作りたいとき
- `02_画面基本設計/screen-<画面キー>/` の雛形をコード実態から機械展開したいとき
- 起動引数: ソースコードディレクトリ（探索対象）と出力先ルートディレクトリ（対象プロジェクト root。配下に `docs/02_画面基本設計/` を自動付加）の2つ

## 基本ワークフロー（Phase 1〜3）

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

Phase 1完了後、検出サマリ（フレームワーク・検出方式・画面数・confidence内訳）を提示し、**AskUserQuestionで1回だけ続行確認**を取る。破壊的操作（mkdir/cp）はここより後でのみ行う。

### Phase 2: スキャフォールド展開（承認後）

`scripts/scaffold-screens.sh <manifest-path> <output-root>` を実行する。テンプレート複製とfrontmatter機械置換の手順は `creating-new-project/references/phase-2-4-scaffold-docs.md`（project-docs/greenfield版）の既存パターンを転用する。

1. `mkdir -p <output-root>/docs/02_画面基本設計`
2. `README.md` が無ければ `~/agent-home/templates/reverse-docs/02_画面基本設計/README.md` を1回だけコピー（既存なら上書きしない）
3. `_共通/` が無ければ `共通設計書.md`・`メッセージ定義書.md`（0バイトのまま）を1回だけコピー
4. 各画面について:
   - `screen-<画面キー>/` が既存なら無条件スキップし `scaffoldStatus: skipped-existing` を記録
   - 存在しなければ `mkdir -p` し3ファイル（画面基本設計書.md・単体テスト観点表.md・結合テスト観点表.md）をコピー
   - frontmatterの `doc_id`/`target_screen`/`route`/`updated`（`date +%Y-%m-%d`）のみ機械置換する。`design_md`/`common_spec_version`/`mock`/`messages`/`common_spec` は変更しない
   - §15.1「ファイル分割とexport一覧」の「ファイルパス」列のみPhase 1の構成ファイル一覧で機械記入する（`export名`/`種別`列はプレースホルダのまま）
   - confidenceがlowの画面は §16 要確認事項一覧に意味キー（例: `画面境界-自動判定信頼度低`）で1行追記する
   - それ以外の§1〜§16本文には一切触れない

完了条件: 検出した全画面について `screen-<画面キー>/` が作成済みまたは `skipped-existing` として記録されている

### Phase 3: 画面一覧.HTML 生成

Phase 1/2の確定結果を実施済み事実のレポートとして `<output-root>/docs/02_画面基本設計/画面一覧.html` へ出力する。`assets/screen-list-template.html` を土台に、テーブル行と `<script type="application/json" id="screen-manifest">` を注入して `Write` する（専用スクリプトは持たない。プレースホルダの置換は Claude 本体が担う）。

テーブル列: 画面キー／画面名（技術名の機械整形のみ、業務的意訳はしない）／ルート／検出方式／confidence／構成ファイル数／主ファイル／02_画面基本設計状態（生成済み／スキップ）。埋め込みJSONのスキーマは `assets/screen-list-template.html` 内コメント参照。外部CDN不使用・単一ファイル自己完結。

前回生成分が存在する場合、新規検出画面／消滅した画面（廃止候補）の差分をヘッダに追記する。消滅画面のディレクトリは削除しない。

完了条件: `画面一覧.html` が最新の検出・スキャフォールド結果を反映して書き出し済み

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 画面マニフェストが1件以上確定、または0件検出をユーザーに報告して停止している |
| Phase 2 | 検出した全画面について `screen-<画面キー>/` が作成済みまたは `skipped-existing` として記録されている |
| Phase 3 | `画面一覧.html` が最新の検出・スキャフォールド結果を反映して書き出し済み |
| **Goal** | 生成画面キーに連番形式が0件、かつ `<output-root>/` 直下に `docs/02_画面基本設計/` 以外の新規ファイルが生成されていない |

## ツールリファレンス

| ツール | 用途 |
|---|---|
| Bash | `scripts/detect-screens.sh` / `scripts/scaffold-screens.sh` の実行、`mkdir`/`cp`/`date` |
| Read | テンプレート・既存frontmatterの参照 |
| Write | 画面一覧.html・新規スキャフォールドファイルの生成 |
| Edit | 既存コピー済みファイルのfrontmatter該当行のみ書き換え |
| Grep/Glob | ルーティング定義・慣習ディレクトリの検索 |
| AskUserQuestion | Phase1→2間の1回だけの続行確認、0件検出時の報告 |

## 推奨手順

- ソースディレクトリは対象プロジェクトの実コードルート（例: `frontend/src`）を指定する。モノレポでアプリが複数ある場合は対象アプリのディレクトリのみを渡す（自動判別なし）
- 既に `screen-<キー>/` へ人手で加筆済みの場合は再実行しても上書きされない（非破壊優先）。加筆済み設計書の更新は本スキルの対象外

## 重要な注意事項

- §1〜§16の本文（業務ルール・API契約詳細等）を推測で埋めない。機械的に確定できる事実のみを反映する
- import グラフ解析は行わない。画面ファイルの収集は物理的同居のみ
- 0件検出時にAskUserQuestionで手動リストを聞き出さない。誤った境界を即興確定させない

## Gotchas

- React Routerの深いネスト親子パス合成は非対応（フラット抽出のみ）。ネストが深い構成では検出精度が落ちる
- 動的に構築されるルート文字列（変数結合等）は検出できない。静的リテラルの `path` のみが対象
- 既存 `screen-<キー>/` は再実行しても差分マージされない（無条件スキップ）
- `scaffold-screens.sh` は `jq` 前提。対象環境に `jq` が無い場合は事前にインストールが必要

## 参照資料

- `~/agent-home/templates/reverse-docs/02_画面基本設計/` — スキャフォールドのコピー元
- `~/agent-home/skills/creating-new-project/references/phase-2-4-scaffold-docs.md`（L155-202）— テンプレート複製+frontmatter機械置換の転用元パターン
- `~/agent-home/skills/rebuilding-code-from-docs/SKILL.md` — 往復検証の後工程スキル（本スキルはその前工程）
- `~/.claude/rules/semantic-key-rules/rule.md` — 画面キー生成アルゴリズムの制約
- `~/.claude/rules/file-guard-rules/rule.md` — 出力先パス設計の制約
- 将来拡張: 大規模コードベース（数百画面規模）向けのサブエージェント並列探索は本バージョンでは非搭載。必要になった場合は Phase 1 の探索をバッチ分割し `worker-sonnet` へ委任する設計を追加検討する
