---
name: generating-screen-list-for-reverse-docs
description: "レガシー画面検出→画面一覧HTML生成。 TRIGGER when: 画面一覧作成。 SKIP: 往復検証/同期/実装（→rebuilding-code-from-docs/syncing-reverse-env/orchestrating-dev-flow）。"
invocation: generating-screen-list-for-reverse-docs
type: transform
allowed-tools: [Bash, Read, Write, Edit, Grep, Glob, AskUserQuestion, TaskCreate, TaskUpdate]
---

# レガシー画面一覧生成スキル

レガシー（既存）コードベースを、スタック調査→検出戦略の宣言→戦略に基づく抽出→整合検証、の順で調査し、「画面」単位にファイルをグルーピングして **画面一覧.HTML**（画面詳細設計書.md の単位を正確に分けるための正本）を作成する。**本スキルの仕事は画面一覧.HTMLの作成のみ**であり、設計書の雛形展開・生成・記入は一切行わない。

`rebuilding-code-from-docs`（既に存在する設計書の往復検証）・`syncing-reverse-env`（環境同期）とは独立して単独動作する。

## 設計原則: 固定と可変の分離

マニフェストスキーマ・整合検証（`scripts/validate-manifest.sh`）・HTML生成（`scripts/build-screen-list.sh`）は決定的スクリプトに固定する。抽出（画面境界の検出）はプロジェクトごとに可変であり、次の2経路のいずれかを取る。

- **組み込み検出器（高速パス）**: `detect-screens.sh` がNext.js App/Pages Router・React Router（`useRoutes`含む）・慣習ディレクトリを機械的に検出する
- **カスタム抽出パス**: 組み込み検出器がPhase 1の調査結果と適合しない場合、Claude自身が戦略宣言に沿ってプロジェクト専用の抽出手順を設計・実行し、スキーマ準拠のJSONマニフェストを出力する

抽出方式がどちらであっても、`validate-manifest.sh` が抽出者非依存でマニフェストの整合性を機械保証する。汎用の正規表現を無条件に当てるのではなく、対象プロジェクト固有の画面規約を先に確認してから検出することで、境界の取り違えを防ぐ。

## 使用タイミング

- レガシーコードベースの画面一覧を作りたいとき
- 起動引数: ソースコードディレクトリ（探索対象）と出力先ディレクトリ（画面一覧.HTMLの書き出し先）の2つ

## 進捗管理（必須手順）

スキル開始時に `TaskCreate` でPhase 1〜4のタスクを登録する。各Phase開始時に該当タスクを `in_progress` に、完了時に `completed` へ `TaskUpdate` で更新する。Phase 3からPhase 2へ差し戻す場合はPhase 2タスクを `in_progress` に戻す。実行環境にTaskCreate/TaskUpdateが存在しない場合は、出力先ディレクトリ内のタスク台帳ファイル（`task-ledger.md`）で同等のPhase遷移記録を代替する。

## 動作フロー（Phase 1〜4）

### Phase 1: スタック・画面規約の特定

- **Step 1**: `package.json`・lockファイル（`package-lock.json`/`yarn.lock`/`pnpm-lock.yaml`）からフレームワーク・ルーターライブラリを確定する。これらが存在しないコードベースでは import 文・API 使用形跡から推定する。完了条件: ライブラリ名とバージョンが特定済み、または特定不能の根拠（推定経路）が記録済み
- **Step 2**: ルーティング定義の所在と方式を特定する。**定義と呼び出しが別ファイルの場合（`useRoutes(router)`等）は定義ファイルまで追跡して所在を確定する**。完了条件: `path`/`route`定義を含む実ファイルパスが列挙済み
- **Step 3**: 画面規約を調査する（画面ID命名パターン・View切替関数・メニュー定義/画面マスタの有無）。完了条件: `screen-id-regex`/`view-switch-pattern`の候補値または「なし」が確定済み
- **Step 4**: 除外パターンを確定する。`tests`/`stories`/`mocks`等のノイズディレクトリを実際に `ls` で確認する。完了条件: `excludePatterns` 一覧が確定済み
- **Step 5**: 検出戦略宣言を作成し、AskUserQuestionで承認を取る。宣言JSONは一時ファイルに保存する。完了条件: 戦略JSON（`extractionMethod`/`screenUnitDefinition`/`screenIdRegex`/`viewSwitchPattern`/`excludePatterns`/`approvedByUser: true`/`notes`）が保存済み

### Phase 2: 戦略に基づく抽出

- **Step 1**: 抽出方式を分岐判定する。組み込み検出器（Next.js App/Pages Router・React Router（`useRoutes`含む）・慣習ディレクトリ）がPhase 1の調査結果と適合するか判定する。完了条件: `builtin-*` か `custom` かが決定済み
- **Step 2（組み込みパス）**: `scripts/detect-screens.sh <source-dir> <manifest-out> --strategy-json <strategy.json> [--screen-id-regex <re>] [--view-switch-pattern <re>] [--exclude <pattern>]` を実行する。0件ならハード停止（exit 3）。画面を捏造しない
- **Step 2（カスタム抽出パス）**: Phase 1で宣言した手順（例: element属性の`viewId`/`pageId`から物理ファイルを組み立てる・カスタムルート配列のJSON解析等）をClaude自身がBash/Grep/Readで実行し、スキーマ準拠のマニフェストJSONをWriteする。完了条件（両パス共通）: マニフェストJSONが生成済み
- **Step 3**: diagnosticsを確認する。entryFile集中警告等が出た場合はカスタム抽出パスへの切替を検討し、切替時はStep 1へ戻る。完了条件: diagnosticsが空、または警告を承知の上で続行と判断済み

検出結果は一時ディレクトリ（`$CLAUDE_JOB_DIR/tmp/screen-manifest.json`、未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下。`${session}`はセッションIDが取得できなければ任意の一意な値でよい）に保存する。

### Phase 3: 整合検証（機械実行）

- **Step 1**: `scripts/validate-manifest.sh <manifest.json>` を実行する。完了条件: 全7項目PASS
- **Step 2**: FAIL時は指摘に応じて修正する（entryFile不在は `--fix` でunresolved降格可）。修正後Step 1を再実行する。3回失敗したら抽出方式の再検討（Phase 2 Step 1）へ差し戻す。完了条件: exit 0

`validate-manifest.sh` は抽出方式（組み込み/カスタム）を問わず同一基準で検証する。カスタム抽出パスであっても、この検証を通過しないマニフェストはPhase 4に進めない。

### Phase 4: 画面一覧.HTML 生成

- **Step 1**: `scripts/build-screen-list.sh <manifest.json> <output-dir>/画面一覧.html` を実行する。build側が内部でvalidateを再実行するため、検証を経ないmanifestからは生成できない。完了条件: HTML生成済み

**手作業でのプレースホルダ置換は禁止する**（過去に `entryFile=None` の混入という実害が発生している）。HTML生成は必ずスクリプト経由の決定的処理で行う。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | Step 1〜4の調査完了。Step 5の検出戦略宣言（screenUnitDefinition/screenIdRegex/viewSwitchPattern/excludePatterns）がユーザー承認済み |
| Phase 2 | Step 1で抽出方式（builtin/custom）が決定済み。Step 2でスキーマ準拠のマニフェストが1件以上確定、または0件検出をユーザーに報告して停止している。Step 3でdiagnosticsを確認済み |
| Phase 3 | Step 1で `validate-manifest.sh` が全7項目PASS。Step 2のFAIL時修正ループは3回以内 |
| Phase 4 | Step 1で画面一覧.HTMLが生成され、埋め込みJSONがマニフェストと一致している |
| **Goal** | 検証済みマニフェストのみからHTMLが生成され、共有/埋め込み/未解決/診断警告が可視化され、設計書単位の判断材料が揃っている |

## ツールリファレンス

| ツール | 用途 |
|---|---|
| Bash | `scripts/detect-screens.sh`・`scripts/validate-manifest.sh`・`scripts/build-screen-list.sh` の実行 |
| Read | package.json・ルーター定義・テンプレートの参照 |
| Grep/Glob | 画面規約（画面ID命名パターン・View切替関数）・ルーティング定義の調査、カスタム抽出パスでの物理ファイル収集 |
| Write | 検出戦略宣言の一時保存、カスタム抽出パスでのマニフェストJSON出力（画面一覧.HTML本体はスクリプト経由で生成） |
| AskUserQuestion | Phase 1の検出戦略宣言確認、Phase 2の0件検出時の報告 |
| TaskCreate/TaskUpdate | Phase 1〜4の進捗管理 |

## 推奨手順

- ソースディレクトリは対象プロジェクトの実コードルート（例: `frontend/src`）を指定する。モノレポでアプリが複数ある場合は対象アプリのディレクトリのみを渡す（自動判別なし）
- Phase 1の調査を省略して汎用の `screen-id-regex` を当てない。プロジェクトごとに命名規約・ナビゲーション方式は異なる
- 組み込み検出器の適合を過信しない。Phase 2 Step 3のdiagnosticsでentryFile集中警告等が出たら、無理に組み込みパスを続けずカスタム抽出パスへ切り替える

## 重要な注意事項

- 設計書（`画面詳細設計書.md` 等）の雛形展開・生成・記入は一切行わない。本スキルの成果物は画面一覧.HTMLのみ
- Phase 4のHTML手作業組み立てを禁止する。`build-screen-list.sh` を必ず経由し、プレースホルダの手動置換による `entryFile=None` 等のデータ混入を防ぐ
- import グラフ解析は行わない（組み込み検出器の場合。カスタム抽出パスでは戦略宣言に沿った収集を行う）
- 0件検出時にAskUserQuestionで手動リストを聞き出さない。誤った境界を即興確定させない

## Gotchas

- `validate-manifest.sh`・`build-screen-list.sh` は jq に依存する。未インストール環境では事前に導入する
- 組み込み検出器は `useRoutes` と2段階importまでのimport追跡に対応する。それ以外の方式（カスタムルート配列・element属性解決等）はカスタム抽出パスで対応する
- Phase 2 Step 3でentryFile集中診断が出たら、組み込みパスの継続ではなくカスタム抽出パスへの切替を検討する
- 動的に構築されるルート文字列（変数結合等）は組み込み検出器では検出できない。静的リテラルの `path` のみが対象
- 埋め込みビュー（`kind: embedded-view`）の検出はPhase 1で `view-switch-pattern` を指定した場合のみ有効。未指定なら検出しない
- 設計書の雛形展開・生成は行わない（本スキルのスコープ外）
- カスタム抽出でソースを解析する際、コメントアウトされたルート定義・import文を除去してから抽出する（コメント内の定義を実在として誤検出した実害を防ぐ）
- View切替の検出パターンはsetEditView/ModalModeに限らない。自己管理モーダル（useState+条件レンダリング等）を使うプロジェクトではPhase 1でそのパターンを特定して宣言する
- `import Foo, { Bar } from ...`（default+named混合import）の解決は組み込み検出器では不完全。カスタム抽出パスで対応する
- 埋め込みビューの1階層スキャンでは子コンポーネント内のさらなるView切替を検出できない。深い階層が疑われる場合はカスタム抽出パスで再帰スキャンを設計する
- 画面数のカウントには部品ファイル（共有クラスタで参照されるだけのコンポーネント等）を含めない。画面として数えるのはroute行とembedded-view行のみ
- 検出方式は戦略宣言（`strategy.extractionMethod` が `builtin-*`）が最優先される。自動チェーン時、Next.js系検出器は `next.config.*` の実在を必須とする（Vite+React Routerプロジェクトの `src/pages/` を Next.js Pages Router と誤判定する実害を防ぐ）。ルーティング方式が確定しているPhase 1では `--strategy-json` で `extractionMethod` を明示指定するのが確実
- `strategy.sharedWithBusinessIdsAllowed: true` を設定すると、`sharedWith` に `screenIdRegex` 一致の業務ID（screenKey/screenId行を持たない「代表1冊+バリエーション統合」方式のバリエーション）を列挙しても参照整合が誤FAILしない。デフォルトは `false`（strict）で通常プロジェクトのダングリング参照検出を維持する
- この方式は汎用スキル本体（`validate-manifest.sh`）を改造せず、プロジェクト側のstrategy宣言（config）で吸収する設計である

## 設計判断

### build-screen-list.sh

**必要性**: 画面一覧.HTML生成をClaude手作業（プレースホルダ置換）で行うと、検証なしのデータ混入が発生する（実例: `entryFile=None` が10件混入）。JSONマニフェストからHTMLへの変換を決定的スクリプトに固定化し、手作業経路を根絶する。

**代替案を採用しなかった理由**:
- Bashツール直叩き: 毎回30行超のjq+ヒアドキュメントを手書きし、エスケープ事故が再発する
- 既存Makefile拡張: 本スキルはプロジェクト非依存でMakefileを持たない
- package.json scripts: 本スキルはプロジェクト横断で動作するため、単一プロジェクトのpackage.jsonに依存できない

**保守責任者**: 人手（ユーザー）

**廃棄条件**: 画面一覧.HTMLの形式が廃止された時

### detect-screens.sh（組み込み検出器）

**必要性**: 画面境界検出（Next.js App/Pages Router・React Router・慣習ディレクトリ）は200行を超えるロジックであり、毎回Bash直叩きで実行すると再現性がなく、検出結果が実行者・実行回ごとにブレる。1本のスクリプトに固定化することで、同一入力から同一マニフェストが決定的に得られる。

**代替案を採用しなかった理由**:
- Bashツール直叩き: 200行超のロジックを毎回インラインで書くと再現性がなく、修正のたびに全体を再実装するリスクが高い

**保守責任者**: 人手（ユーザー）

**廃棄条件**: 画面境界検出のアプローチが別スキル・別ツールに置き換わった時

### validate-manifest.sh

**必要性**: 抽出がカスタムパス（Claude手書きJSON）であっても品質を機械保証する独立検証が必要。抽出方式（組み込み検出器かClaudeによるカスタム抽出か）に依存せず、マニフェストスキーマ・重複キー・共有クラスタ・unresolved隔離を同一基準で検査する。Phase 1で承認した検出戦略宣言（`approvedByUser: true`）の機械的な存在確認も本スクリプトが担う。

**代替案を採用しなかった理由**:
- detect-screens.sh内部検証のみ: カスタム抽出パスで生成されたマニフェストをカバーできない
- Claude自己申告（検証コマンドを介さない目視確認）: 自己申告のみでの品質保証は `entryFile=None` 混入という実害実績があり信頼できない

**保守責任者**: 人手（ユーザー）

**廃棄条件**: マニフェスト形式（JSONスキーマ）が廃止された時
