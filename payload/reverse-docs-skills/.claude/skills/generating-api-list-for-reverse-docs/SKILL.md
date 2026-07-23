---
name: generating-api-list-for-reverse-docs
description: "API一覧フォルダ・API一覧HTML生成（unit_kind=api 専用）。 TRIGGER when: API一覧作成、API一覧生成、エンドポイント一覧。 SKIP: 他種別の一覧（→対応する種別別一覧スキル）、往復検証/同期/実装。"
invocation: generating-api-list-for-reverse-docs
type: transform
allowed-tools: [Bash, Read, Write, Edit, Grep, Glob, AskUserQuestion, TaskCreate, TaskUpdate]
---

# API一覧生成スキル

工程全体は orchestrating-reverse-docs-flow が案内する。本スキルは API 一覧の生成のみを担い、単独起動できる（起動引数 source_dir・output_dir の 2 つを渡せば動く）。`unit_kind` は **api 固定** であり、引数では受け取らない。

既存コードベースを、スタック調査→検出戦略の宣言→戦略に基づく抽出→整合検証、の順で調査し、API エンドポイントの単位にファイルをグルーピングして **API一覧.html** を作成する。**本スキルの仕事は API一覧.html の作成のみ** であり、設計書の雛形展開・生成・記入は一切行わない。

他スキルへの依存を持たず、単独で動作する。

## 設計原則: 固定と可変の分離

マニフェストスキーマ・整合検証（`validate-manifest.sh`）・HTML生成（`build-unit-list.sh`）は決定的スクリプトに固定する。抽出（エンドポイント境界の検出）はプロジェクトごとに可変である。

API 種別に組み込み検出器はない。抽出は **カスタム抽出パスのみ**: Claude 自身が Phase 1 の戦略宣言に沿ってプロジェクト専用の抽出手順を設計・実行し、スキーマ準拠のマニフェスト JSON（配列キーは `units`）を出力する。

抽出が Claude の手作業であっても、`validate-manifest.sh` が抽出者非依存でマニフェストの整合性を機械保証する。汎用の正規表現を無条件に当てるのではなく、対象プロジェクト固有の API 規約を先に確認してから検出することで、境界の取り違えを防ぐ。

## エンジンスクリプトの参照

エンジンスクリプトは本スキルフォルダからの相対パスで参照する。

- 整合検証: `../../../shared/scripts/unit-list/validate-manifest.sh`
- HTML生成: `../../../shared/scripts/unit-list/build-unit-list.sh`

正本リポジトリと公開先（payload）はディレクトリレイアウトが同一のため、この相対参照は両環境でそのまま成立する。

## 使用タイミング

- 既存コードベースの API 一覧（エンドポイント一覧）を作りたいとき
- 起動引数: `source_dir`（ソースコードディレクトリ。探索対象）・`output_dir`（出力先ディレクトリ。API一覧.html の書き出し先）の 2 つ

## 出力

| 項目 | 値 |
|---|---|
| 出力フォルダ | `<output_dir>/一覧/API一覧/` |
| 出力ファイル | `API一覧.html` |
| マニフェスト配列キー | `units` |

## 進捗管理（必須手順）

スキル開始時に `TaskCreate` で Phase 1〜4 のタスクを登録する。各 Phase 開始時に該当タスクを `in_progress` に、完了時に `completed` へ `TaskUpdate` で更新する。Phase 3 から Phase 2 へ差し戻す場合は Phase 2 タスクを `in_progress` に戻す。実行環境に TaskCreate/TaskUpdate が存在しない場合は、出力先ディレクトリ内のタスク台帳ファイル（`task-ledger.md`）で同等の Phase 遷移記録を代替する。

## 動作フロー（Phase 1〜4）

### Phase 1: スタック・API規約の特定

調査項目の詳細は `references/api-detection.md` を参照する。

- **Step 1**: `package.json`・lockファイル（`package-lock.json`/`yarn.lock`/`pnpm-lock.yaml`）またはバックエンド相当（`requirements.txt`/`pyproject.toml`/`go.mod` 等）からフレームワーク・ルーターライブラリを確定する。これらが存在しないコードベースでは import 文・API 使用形跡から推定する。完了条件: ライブラリ名とバージョンが特定済み、または特定不能の根拠（推定経路）が記録済み
- **Step 2**: エンドポイント定義の所在と方式を特定する（OpenAPI/Swagger 定義ファイル、ルート定義、コントローラ、デコレータ等）。**定義と登録が別ファイルの場合（ルーターの分割マウント等）は定義ファイルまで追跡して所在を確定する**。完了条件: エンドポイント定義を含む実ファイルパスが列挙済み
- **Step 3**: API 規約を調査する（API ID 命名パターン・HTTP メソッドとパスの記述方式・ミドルウェアの適用方式）。完了条件: `unitIdRegex` の候補値または「なし」が確定済み
- **Step 4**: 除外パターンを確定する。テスト用エンドポイント・ヘルスチェック・`tests`/`mocks` 等のノイズを実際に `ls` で確認する。完了条件: `excludePatterns` 一覧が確定済み
- **Step 5**: 検出戦略宣言を作成し、AskUserQuestion で承認を取る。宣言 JSON は一時ファイルに保存する。完了条件: 戦略 JSON（`unitKind: "api"`/`extractionMethod: "custom"`/`unitIdRegex`/`excludePatterns`/`approvedByUser: true`/`notes`）が保存済み

### Phase 2: 戦略に基づく抽出

- **Step 1**: 抽出方式を確認する。API 種別に組み込み検出器はないため、常にカスタム抽出パスとなる。完了条件: `extractionMethod: "custom"` が戦略宣言に記録済み
- **Step 2**: Phase 1 で宣言した手順（例: ルート定義ファイルの走査・デコレータの収集・OpenAPI 定義の解析等）を Claude 自身が Bash/Grep/Read で実行し、スキーマ準拠のマニフェスト JSON（配列キー `units`）を Write する。**0 件検出ならハード停止** し、ユーザーに報告する。エンドポイントを捏造しない。完了条件: マニフェスト JSON が生成済み、または 0 件検出を報告して停止している
- **Step 3**: diagnostics を確認する。sourceFile 集中警告等が出た場合は抽出手順を見直し、見直し時は Step 2 へ戻る。完了条件: diagnostics が空、または警告を承知の上で続行と判断済み
- **Step 4**: マニフェストへメタデータを付与する。`../../../shared/scripts/extract/extract-api-metadata.sh <manifest.json> <source_dir> <manifest.ext.json>` を実行し、各ユニットに `method`・`authRequired`・`ioSummary` フィールドを追加した拡張マニフェスト（`manifest.ext.json`）を生成する。`callers`・`targetTables` は画面一覧・テーブル一覧の拡張マニフェストを要する（`--screen-manifest`/`--table-manifest`）ため、本スキル単独実行では付与されない（マトリクス・対応表生成時に generating-cross-views-for-reverse-docs が担う）。以降の Phase では `manifest.ext.json` を使用する。完了条件: 拡張マニフェストが生成済み

検出結果は一時ディレクトリ（`$CLAUDE_JOB_DIR/tmp/api-manifest.json`、未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下。`${session}` はセッション ID が取得できなければ任意の一意な値でよい）に保存する。

### Phase 3: 整合検証（機械実行）

- **Step 1**: `../../../shared/scripts/unit-list/validate-manifest.sh <manifest.ext.json> --unit-kind api` を実行する。完了条件: 全項目 PASS
- **Step 2**: FAIL 時は指摘に応じて修正する（sourceFile 不在は `--fix` で unresolved 降格可）。修正後 Step 1 を再実行する。3 回失敗したら抽出手順の再検討（Phase 2 Step 2）へ差し戻す。完了条件: exit 0

`validate-manifest.sh` は抽出者に依存せず同一基準で検証する。Claude のカスタム抽出であっても、この検証を通過しないマニフェストは Phase 4 に進めない。

### Phase 4: API一覧.html 生成

- **Step 1**: `../../../shared/scripts/unit-list/build-unit-list.sh <manifest.ext.json> <output_dir>/一覧/API一覧/API一覧.html --unit-kind api --portal-dir <output_dir>` を実行する。`--portal-dir` にはポータル（`index.html`）の配置先＝納品物ルート（output_dir=docs_root）を渡し、「ポータルへ戻る」リンクを実在パスに解決させる。build 側が内部で validate を再実行するため、検証を経ない manifest からは生成できない。完了条件: HTML 生成済み

**手作業でのプレースホルダ置換は禁止する**（過去に `entryFile=None` の混入という実害が発生している）。HTML 生成は必ずスクリプト経由の決定的処理で行う。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | Step 1〜4 の調査完了（`references/api-detection.md` の調査項目に準拠）。Step 5 の検出戦略宣言（`unitKind: "api"`/`extractionMethod`/`unitIdRegex`/`excludePatterns`）がユーザー承認済み |
| Phase 2 | Step 1 でカスタム抽出パスが確認済み。Step 2 でスキーマ準拠のマニフェストが 1 件以上確定、または 0 件検出をユーザーに報告して停止している。Step 3 で diagnostics を確認済み。Step 4 でマニフェストに method・authRequired フィールドが付与されている |
| Phase 3 | Step 1 で `validate-manifest.sh --unit-kind api` が全項目 PASS。Step 2 の FAIL 時修正ループは 3 回以内 |
| Phase 4 | Step 1 で API一覧.html が生成され、埋め込み JSON がマニフェストと一致している |
| **Goal** | 検証済みマニフェストのみから HTML が生成され、未解決・診断警告が可視化され、設計書単位の判断材料が揃っている |

## 返却

本スキルは orchestrating-reverse-docs-flow の契約に準拠する。完了時に以下を返す。

- `status`: `DONE | ERROR`
- `artifacts`: 生成した API一覧.html のパス
- `unit_list_html`: artifacts[0] の汎用名
- `embedded_json_ref`: HTML 内に埋め込んだマニフェスト JSON への参照
- `unit_kind`: `api`（固定値）

## ツールリファレンス

| ツール | 用途 |
|---|---|
| Bash | `../../../shared/scripts/unit-list/validate-manifest.sh`・`build-unit-list.sh` の実行 |
| Read | package.json・エンドポイント定義・OpenAPI 定義・`references/api-detection.md` の参照 |
| Grep/Glob | API 規約（ID 命名パターン・メソッド/パス記述方式）・エンドポイント定義の調査、カスタム抽出での物理ファイル収集 |
| Write | 検出戦略宣言の一時保存、マニフェスト JSON の出力（API一覧.html 本体はスクリプト経由で生成） |
| AskUserQuestion | Phase 1 の検出戦略宣言確認、Phase 2 の 0 件検出時の報告 |
| TaskCreate/TaskUpdate | Phase 1〜4 の進捗管理 |

## 推奨手順

- ソースディレクトリは対象プロジェクトの実コードルート（例: `backend/src`）を指定する。モノレポでアプリが複数ある場合は対象アプリのディレクトリのみを渡す（自動判別なし）
- Phase 1 の調査を省略して汎用の `unitIdRegex` を当てない。プロジェクトごとに命名規約・ルーティング方式は異なる
- OpenAPI/Swagger 定義が存在する場合は、それを一次情報として実装コードと突合する。定義と実装が食い違う場合は実装側を正とし、食い違いを `notes` に記録する

## 重要な注意事項

- 設計書の雛形展開・生成・記入は一切行わない。本スキルの成果物は API一覧.html のみ
- Phase 4 の HTML 手作業組み立てを禁止する。`build-unit-list.sh` を必ず経由し、プレースホルダの手動置換による `entryFile=None` 等のデータ混入を防ぐ
- 0 件検出時に AskUserQuestion で手動リストを聞き出さない。誤った境界を即興確定させない

## 予想を裏切る挙動

- `validate-manifest.sh`・`build-unit-list.sh` は jq に依存する。未インストール環境では事前に導入する
- カスタム抽出でソースを解析する際、コメントアウトされたルート定義・import 文を除去してから抽出する（コメント内の定義を実在として誤検出した実害を防ぐ）
- 動的に構築されるルートパス（変数結合・ループ登録等）は静的走査で取りこぼしやすい。Phase 1 でその方式を発見したら、抽出手順に展開ロジックの追跡を組み込む
- ミドルウェア（認証・バリデーション等の共通処理）はエンドポイントとして数えない。`kind: middleware` として別区分で記録する
- 認証・依存性注入のヘルパー定義（`Depends(get_current_user)` / `Depends(check_session)` 等、Depends の引数に現れる関数の定義）はエンドポイントとして計上しない。ルートデコレータ・ルート登録を持たない関数は、パス文字列や HTTP 関連の記述を含んでいてもエンドポイントではない
- 他種別の一覧（外部連携の受信エンドポイント等）として計上済みのエンドポイントは重複計上しない。主たる種別に単独計上し、本一覧から除外した旨とその理由を検出ログ（戦略宣言の `notes` または diagnostics）に残す
- エンドポイント数のカウントには `kind: endpoint` 行のみを含める。`middleware`/`unresolved` 行は数えない
- マニフェストの配列キーは `screens` ではなく `units` とする
- 出力先は `<output_dir>/一覧/API一覧/API一覧.html`。他種別と独立したフォルダを作成する

## 完了報告

`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（作業報告型）に従う。

固有の検証行:
- validate-manifest.sh --unit-kind api が全項目 PASS・API一覧.html の生成成功

## 設計判断

本スキルは独自スクリプトを持たないため省略する。
