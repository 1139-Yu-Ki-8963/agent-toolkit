---
name: generating-screen-list-for-reverse-docs
description: "既存コードベースから画面単位の一覧フォルダ・画面一覧HTMLを生成する。 TRIGGER when: 画面一覧作成、画面一覧生成、画面の洗い出し。 SKIP: 他種別の一覧（→対応する種別別一覧スキル）、往復検証/同期/実装。"
invocation: generating-screen-list-for-reverse-docs
type: transform
allowed-tools: [Bash, Read, Write, Edit, Grep, Glob, AskUserQuestion, TaskCreate, TaskUpdate]
---

# 画面一覧生成スキル

工程全体は orchestrating-reverse-docs-flow が案内する。本スキルは画面（unit_kind=screen 固定）の一覧生成のみを担い、単独起動できる（起動引数 source_dir・output_dir の2つを渡せば動く）。任意引数 `survey_doc_path`（アーキテクチャ調査書のパス）を渡すと、Phase 1 の共有ファイル・エイリアス調査の裏取り元として参照する（本スキルは内容を読み込まず実在確認のみ行う。渡されない場合は Phase 1 の調査のみで判断する）。

既存コードベースを、スタック調査→検出戦略の宣言→戦略に基づく抽出→整合検証、の順で調査し、画面単位にファイルをグルーピングして **画面一覧.html**（画面詳細設計書.md の単位を正確に分けるための正本）を作成する。**本スキルの仕事は画面一覧.htmlの作成のみ**であり、設計書の雛形展開・生成・記入は一切行わない。

他スキルへの依存を持たず、単独で動作する。

## エンジンスクリプトの所在

整合検証・HTML生成・組み込み検出はスキルフォルダからの相対パスで参照する（正本リポジトリと公開先はフォルダ配置が同一のため、両環境でこの相対参照が成立する）。

| スクリプト | パス（スキルフォルダ相対） |
|---|---|
| 整合検証 | `../../../shared/scripts/unit-list/validate-manifest.sh` |
| HTML生成 | `../../../shared/scripts/unit-list/build-unit-list.sh` |
| 組み込み画面検出 | `../../../shared/scripts/unit-list/detect-screens.sh` |

## 設計原則: 固定と可変の分離

マニフェストスキーマ・整合検証（`validate-manifest.sh`）・HTML生成（`build-unit-list.sh`。内部で `build-screen-list.sh` に委譲）は決定的スクリプトに固定する。抽出（画面境界の検出）はプロジェクトごとに可変であり、次の2経路のいずれかを取る。

- **組み込み検出器（高速パス）**: `detect-screens.sh` がNext.js App/Pages Router・React Router（`useRoutes`含む）・慣習ディレクトリを機械的に検出する
- **カスタム抽出パス**: 組み込み検出器がPhase 1の調査結果と適合しない場合、Claude自身が戦略宣言に沿ってプロジェクト専用の抽出手順を設計・実行し、スキーマ準拠のJSONマニフェストを出力する

抽出方式がどちらであっても、`validate-manifest.sh` が抽出者非依存でマニフェストの整合性を機械保証する。汎用の正規表現を無条件に当てるのではなく、対象プロジェクト固有の画面規約を先に確認してから検出することで、境界の取り違えを防ぐ。

## 使用タイミング

- 既存コードベースの画面一覧を作りたいとき
- 起動引数: ソースコードディレクトリ（探索対象）・出力先ディレクトリ（画面一覧.htmlの書き出し先）の2つ

## 出力

- 出力フォルダ: `<output_dir>/画面一覧/`
- 出力ファイル: `<output_dir>/画面一覧/画面一覧.html`
- マニフェスト配列キー: `screens`（後方互換）
- 任意出力ファイル（Phase 5実行時のみ）: `<output_dir>/画面一覧/複雑度プロファイル.json`

## 進捗管理（必須手順）

スキル開始時に `TaskCreate` でPhase 1〜4のタスクを登録する（Phase 5は任意工程のため、複雑度プロファイリングを実行する場合のみ追加登録する）。各Phase開始時に該当タスクを `in_progress` に、完了時に `completed` へ `TaskUpdate` で更新する。Phase 3からPhase 2へ差し戻す場合はPhase 2タスクを `in_progress` に戻す。実行環境にTaskCreate/TaskUpdateが存在しない場合は、出力先ディレクトリ内のタスク台帳ファイル（`task-ledger.md`）で同等のPhase遷移記録を代替する。

## 動作フロー（Phase 1〜4、任意でPhase 5）

### Phase 1: スタック・画面規約の特定

画面固有の調査項目の詳細は `references/screen-detection.md` を参照する。

- **Step 1**: `package.json`・lockファイル（`package-lock.json`/`yarn.lock`/`pnpm-lock.yaml`）からフレームワーク・ルーターライブラリを確定する。これらが存在しないコードベースでは import 文・API 使用形跡から推定する。完了条件: ライブラリ名とバージョンが特定済み、または特定不能の根拠（推定経路）が記録済み
- **Step 2**: ルーティング定義の所在と方式を特定する。**定義と呼び出しが別ファイルの場合（`useRoutes(router)`等）は定義ファイルまで追跡して所在を確定する**。完了条件: `path`/`route`定義を含む実ファイルパスが列挙済み
- **Step 3**: 画面規約を調査する（画面ID命名パターン・View切替関数・メニュー定義/画面マスタの有無）。完了条件: `screen-id-regex`/`view-switch-pattern`の候補値または「なし」が確定済み
- **Step 4**: 除外パターンを確定する。`tests`/`stories`/`mocks`等のノイズディレクトリを実際に `ls` で確認する。完了条件: `excludePatterns` 一覧が確定済み
- **Step 5**: 共有ファイル・エイリアス調査を行う。複数画面から参照される共有ディレクトリ（`shared/`・`common/`・`components/`等のプロジェクト固有の命名）と、tsconfig/webpack/vite等のパスエイリアス設定（`@/*`等）を実際に調べる。完了条件: `sharedDirPatterns`（共有ディレクトリのglob一覧）・`pathAliases`（エイリアス→実パスの対応表）が確定済み、または対象プロジェクトに共有ディレクトリ・エイリアスが存在しない旨が確認済み
- **Step 6**: 検出戦略宣言を作成し、AskUserQuestionで承認を取る。宣言JSONは一時ファイルに保存する。完了条件: 戦略JSON（`unitKind: "screen"`/`extractionMethod`/`screenUnitDefinition`/`screenIdRegex`/`viewSwitchPattern`/`excludePatterns`/`sharedDirPatterns`/`pathAliases`/`approvedByUser: true`/`notes`）が保存済み

### 抽出基準の明文化

抽出対象はルート配線済み画面を基本とする。ルート未配線の埋め込みビュー・休眠画面は、Phase 1 の strategy 宣言で明示的に `includeUnrouted: true` を指定した場合のみ含める。含める場合は kind=`unrouted` として区分表記する。

直接element指定ルート（`element={<Foo/>}` のようにコンポーネント参照ではなくJSX要素をインライン指定するルート定義）は一律除外せず、ルートごとに個別分類する。実体ファイルへ解決できる場合はマニフェストへ画面として掲載する。除外する場合は除外根拠（例:「インラインJSXで実体ファイルを機械解決できないため対象外」）をdiagnosticsに記録する。

### Phase 2: 戦略に基づく抽出

- **Step 1**: 抽出方式を分岐判定する。組み込み検出器（Next.js App/Pages Router・React Router（`useRoutes`含む）・慣習ディレクトリ）がPhase 1の調査結果と適合する場合のみ組み込みパスを選べる。完了条件: `builtin-*` か `custom` かが決定済み
- **Step 2（組み込みパス）**: `../../../shared/scripts/unit-list/detect-screens.sh <source-dir> <manifest-out> --strategy-json <strategy.json> [--screen-id-regex <re>] [--view-switch-pattern <re>] [--exclude <pattern>]` を実行する。0件ならハード停止（exit 3）。画面を捏造しない。ルート抽出前処理として、行コメント（`//`）・ブロックコメント（`/* */`）を除去してからルート定義を抽出する（コメントアウトされたルート定義を実在として誤検出することを防ぐ。カスタム抽出パスと同一の前処理方針）
- **Step 2（カスタム抽出パス）**: Phase 1で宣言した手順（例: element属性の`viewId`/`pageId`から物理ファイルを組み立てる・カスタムルート配列のJSON解析等）をClaude自身がBash/Grep/Readで実行し、スキーマ準拠のマニフェストJSONをWriteする。完了条件（両パス共通）: マニフェストJSONが生成済み
- **Step 3**: diagnosticsを確認する。entryFile集中警告等が出た場合はカスタム抽出パスへの切替を検討し、切替時はStep 1へ戻る。完了条件: diagnosticsが空、または警告を承知の上で続行と判断済み
- **セルフチェックゲート**: Phase 2 完了後にエントリファイル実在数（`find <source_dir> -name '*.tsx' -path '*/pages/*' -o -name '*.tsx' -path '*/app/*' | wc -l` 等）と抽出件数を突合し、乖離が 20% を超える場合は警告を出力して AskUserQuestion で確認する。headless=true 時は AskUserQuestion が使用できないため、乖離 20% 超の場合は警告を `<verification_dir>/progress.jsonl` に記録し、工程を続行する（中断しない）。最終報告に乖離率を明記する。併せて、マニフェストの各 route がコメント除去後のルーター定義に有効に存在することを照合する。存在しない route が1件でもあれば、実在しないルートの誤検出としてPhase 2 Step 1（抽出方式再検討）へ差し戻す。
- **ルート網羅性検査ゲート**: コメント除去後の有効ルート総数と、「マニフェストに掲載された画面数」＋「根拠付き除外記録の件数」の合計を突合する。一致しない場合はFAILとし、除外漏れ・二重計上のいずれかを特定してから再実行する。

検出結果は一時ディレクトリ（`$CLAUDE_JOB_DIR/tmp/screen-manifest.json`、未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下。`${session}`はセッションIDが取得できなければ任意の一意な値でよい）に保存する。

### Phase 3: 整合検証（機械実行）

- **Step 1**: `../../../shared/scripts/unit-list/validate-manifest.sh <manifest.json> --unit-kind screen` を実行する。7項目検証が動く。完了条件: 全項目PASS
- **Step 2**: FAIL時は指摘に応じて修正する（entryFile不在は `--fix` でunresolved降格可）。修正後Step 1を再実行する。3回失敗したら抽出方式の再検討（Phase 2 Step 1）へ差し戻す。完了条件: exit 0
- **Step 3（レジストリ整合検査）**: 画面レジストリ（`<output_dir>/reverse-screen-registry.yml`。存在しない場合は本Stepをスキップする）に記帳済みの全画面キーを列挙し、マニフェスト掲載画面キーと突合する。レジストリにのみ存在するキーが1件でもあり、かつ根拠付き除外記録が無ければFAILとし、Phase 2の抽出漏れとして差し戻す。完了条件: 突合差分ゼロ（根拠付き除外記録がある場合のみ許容）

`validate-manifest.sh` は抽出方式（組み込み/カスタム）を問わず同一基準で検証する。カスタム抽出パスであっても、この検証を通過しないマニフェストはPhase 4に進めない。

### Phase 4: 画面一覧.html 生成

- **Step 1**: `../../../shared/scripts/unit-list/build-unit-list.sh <manifest.json> <output-dir>/画面一覧/画面一覧.html --unit-kind screen` を実行する。内部で `build-screen-list.sh` に委譲される。build側が内部でvalidateを再実行するため、検証を経ないmanifestからは生成できない。完了条件: HTML生成済み

**手作業でのプレースホルダ置換は禁止する**（過去に `entryFile=None` の混入という実害が発生している）。HTML生成は必ずスクリプト経由の決定的処理で行う。

### Phase 5（任意）: 複雑度プロファイリング

`--profile` サブコマンドで複雑度プロファイル.json を生成する。orchestrating-reverse-docs-flow が画面スコープ「複雑度層別サンプル」を選択した場合、または管理者が層別サンプリングの入力として要求した場合にのみ実行する任意工程であり、Phase 1〜4（画面一覧.html生成）の完了を前提とする。プロファイル未生成時（`<output_dir>/画面一覧/複雑度プロファイル.json` が不在）は、複雑度層別サンプルを要求された時点で本Phaseを先行起動する。

- **Step 1**: `../../../shared/scripts/unit-list/detect-screens.sh --profile <manifest.json> <source-dir> <output-dir>/画面一覧/複雑度プロファイル.json --recount-script <extracting-unit-facts-from-code>/scripts/recount-facts.sh --repo-root <target_repo_path>` を実行し、画面ごとの複雑度指標（loc・8軸・スコア・層）を機械算出する。drvfs（Windows側パスをWSL2からマウントした場合のファイルシステム）上は極端に遅いため、Linux側の作業コピーでの実行を推奨する（260画面規模で数分〜10分程度かかる）。完了条件: 複雑度プロファイル.jsonが生成済み

完了条件: 複雑度プロファイル.jsonが `<output_dir>/画面一覧/複雑度プロファイル.json` に生成されている（本Phaseを実行した場合のみ）

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | Step 1〜4の調査完了。Step 5の共有ファイル・エイリアス調査（sharedDirPatterns/pathAliases）完了。Step 6の検出戦略宣言（`unitKind: "screen"`/screenUnitDefinition/screenIdRegex/viewSwitchPattern/excludePatterns/sharedDirPatterns/pathAliases）がユーザー承認済み |
| Phase 2 | Step 1で抽出方式（builtin/custom）が決定済み。Step 2でスキーマ準拠のマニフェストが1件以上確定、または0件検出をユーザーに報告して停止している。Step 3でdiagnosticsを確認済み。セルフチェックゲート（route実在照合含む）・ルート網羅性検査ゲートをPASS済み |
| Phase 3 | Step 1で `validate-manifest.sh --unit-kind screen` が7項目すべてPASS。Step 2のFAIL時修正ループは3回以内。Step 3のレジストリ整合検査で突合差分ゼロ（画面レジストリが存在する場合のみ） |
| Phase 4 | Step 1で画面一覧.htmlが生成され、埋め込みJSONがマニフェストと一致している |
| Phase 5（任意） | `--profile`サブコマンド実行時のみ、複雑度プロファイル.jsonが生成されている |
| **Goal** | 検証済みマニフェストのみからHTMLが生成され、共有/埋め込み/未解決/診断警告が可視化され、設計書単位の判断材料が揃っている |

## 返却

本スキルは orchestrating-reverse-docs-flow の契約に準拠する。完了時に status（`DONE | ERROR`）と artifacts（生成した画面一覧.htmlのパス）を返す。artifacts[0] を汎用名 unit_list_html として返し、`unit_kind: screen`（固定値）を返却ブロックに含める。HTML内に埋め込んだマニフェストJSONへの参照を embedded_json_ref として併せて返す。従来互換のため screen_list_html を unit_list_html のエイリアスとして併せて返す。Phase 5（複雑度プロファイリング）を実行した場合のみ、拡張フィールド complexity_profile_path（複雑度プロファイル.json の絶対パス）を併せて返す。

## ツールリファレンス

| ツール | 用途 |
|---|---|
| Bash | `detect-screens.sh`・`validate-manifest.sh`・`build-unit-list.sh`（いずれも `../../../shared/scripts/unit-list/` 配下）の実行 |
| Read | package.json・ルーター定義・テンプレート・`references/screen-detection.md` の参照 |
| Grep/Glob | 画面規約（画面ID命名パターン・View切替関数）・ルーティング定義の調査、カスタム抽出パスでの物理ファイル収集 |
| Write | 検出戦略宣言の一時保存、カスタム抽出パスでのマニフェストJSON出力（画面一覧.html本体はスクリプト経由で生成） |
| AskUserQuestion | Phase 1の検出戦略宣言確認、Phase 2の0件検出時の報告 |
| TaskCreate/TaskUpdate | Phase 1〜4の進捗管理 |

## 推奨手順

- ソースディレクトリは対象プロジェクトの実コードルート（例: `frontend/src`）を指定する。モノレポでアプリが複数ある場合は対象アプリのディレクトリのみを渡す（自動判別なし）
- Phase 1の調査を省略して汎用の `screen-id-regex` を当てない。プロジェクトごとに命名規約・ナビゲーション方式は異なる
- 組み込み検出器の適合を過信しない。Phase 2 Step 3のdiagnosticsでentryFile集中警告等が出たら、無理に組み込みパスを続けずカスタム抽出パスへ切り替える

## 重要な注意事項

- 設計書（`画面詳細設計書.md` 等）の雛形展開・生成・記入は一切行わない。本スキルの成果物は画面一覧.htmlのみ
- Phase 4のHTML手作業組み立てを禁止する。`build-unit-list.sh` を必ず経由し、プレースホルダの手動置換による `entryFile=None` 等のデータ混入を防ぐ
- import グラフ解析は行わない（組み込み検出器の場合。カスタム抽出パスでは戦略宣言に沿った収集を行う）
- 0件検出時にAskUserQuestionで手動リストを聞き出さない。誤った境界を即興確定させない

## 予想を裏切る挙動

- `validate-manifest.sh`・`build-unit-list.sh`（内部で呼ぶ `build-screen-list.sh` も）は jq に依存する。未インストール環境では事前に導入する
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
- この方式は共通エンジン（`validate-manifest.sh`）を改造せず、プロジェクト側のstrategy宣言（config）で吸収する設計である
- 出力先は `<output-dir>/画面一覧/画面一覧.html`。画面種別専用の独立フォルダを作成する

## 設計判断

### エンジンスクリプトの共有配置（`shared/scripts/unit-list/`）

**必要性**: 整合検証・HTML生成・組み込み検出の3スクリプトは種別別一覧スキル群の共通エンジンであり、スキルごとに複製すると修正時の追従漏れが発生する。`shared/scripts/unit-list/` に単一の正本を置き、各スキルはスキルフォルダ相対（`../../../shared/scripts/unit-list/`）で参照する。

**代替案を採用しなかった理由**:
- スキルフォルダ内への複製: 修正のたびに全スキルへ手動反映が必要になり、実装差異の混入リスクが高い
- 絶対パス参照: 正本リポジトリと公開先でルートパスが異なるため成立しない。相対参照なら両環境で同一に解決できる

**保守責任者**: 人手（ユーザー）

**廃棄条件**: 種別別一覧スキル群が単一スキルに再統合された時、またはエンジンが別ツールに置き換わった時

### build-screen-list.sh（build-unit-list.sh の委譲先）

**必要性**: 画面一覧.html生成をClaude手作業（プレースホルダ置換）で行うと、検証なしのデータ混入が発生する（実例: `entryFile=None` が10件混入）。JSONマニフェストからHTMLへの変換を決定的スクリプトに固定化し、手作業経路を根絶する。

**代替案を採用しなかった理由**:
- Bashツール直叩き: 毎回30行超のjq+ヒアドキュメントを手書きし、エスケープ事故が再発する
- 既存Makefile拡張: 本スキルはプロジェクト非依存でMakefileを持たない
- package.json scripts: 本スキルはプロジェクト横断で動作するため、単一プロジェクトのpackage.jsonに依存できない

**保守責任者**: 人手（ユーザー）

**廃棄条件**: 画面一覧.htmlの形式が廃止された時

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
