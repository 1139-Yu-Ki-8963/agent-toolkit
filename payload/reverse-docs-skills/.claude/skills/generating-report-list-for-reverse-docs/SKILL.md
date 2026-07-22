---
name: generating-report-list-for-reverse-docs
description: "帳票専用のユニット一覧生成スキル。帳票一覧フォルダ・帳票一覧.htmlを作成する。 TRIGGER when: 帳票一覧作成、帳票一覧生成。 SKIP: 他種別の一覧（→対応する種別別一覧スキル）、往復検証/同期/実装。"
invocation: generating-report-list-for-reverse-docs
type: transform
allowed-tools: [Bash, Read, Write, Edit, Grep, Glob, AskUserQuestion, TaskCreate, TaskUpdate]
---

# 帳票一覧生成スキル

工程全体は orchestrating-reverse-docs-flow が案内する。本スキルは帳票（`unit_kind=report` 固定）の一覧生成のみを担い、単独起動できる（起動引数 `source_dir`・`output_dir` の2つを渡せば動く）。

既存コードベースを、スタック調査→検出戦略の宣言→戦略に基づく抽出→整合検証、の順で調査し、帳票の単位にファイルをグルーピングして **帳票一覧.html** を作成する。**本スキルの仕事は帳票一覧.htmlの作成のみ**であり、設計書の雛形展開・生成・記入は一切行わない。

他スキルへの依存を持たず、単独で動作する。

## 設計原則: 固定と可変の分離

マニフェストスキーマ・整合検証（`validate-manifest.sh`）・HTML生成（`build-unit-list.sh`）は決定的スクリプトに固定する。抽出（帳票境界の検出）はプロジェクトごとに可変であり、**カスタム抽出パスのみ**を取る。帳票には組み込み検出器が存在しないため、Claude自身が Phase 1 の戦略宣言に沿ってプロジェクト専用の抽出手順を設計・実行し、スキーマ準拠のマニフェストJSON（配列キーは `units`）を出力する。

抽出者が誰であっても、`validate-manifest.sh` が抽出者非依存でマニフェストの整合性を機械保証する。汎用の正規表現を無条件に当てるのではなく、対象プロジェクト固有の帳票規約を先に確認してから検出することで、境界の取り違えを防ぐ。

### エンジンスクリプトの所在

エンジンスクリプトはスキルフォルダからの相対パスで参照する。

- 整合検証: `../../../shared/scripts/unit-list/validate-manifest.sh`
- HTML生成: `../../../shared/scripts/unit-list/build-unit-list.sh`

正本リポジトリと公開先はディレクトリレイアウトが同一のため、この相対参照は両環境でそのまま成立する。

## 使用タイミング

- 既存コードベースの帳票一覧を作りたいとき
- 起動引数: `source_dir`（ソースコードディレクトリ。探索対象）・`output_dir`（帳票一覧.htmlの書き出し先）の2つ

## 出力先

| 項目 | 値 |
|---|---|
| 出力フォルダ | `<output_dir>/一覧/帳票一覧/` |
| 出力ファイル | `帳票一覧.html` |
| マニフェスト配列キー | `units` |

## 進捗管理（必須手順）

スキル開始時に `TaskCreate` でPhase 1〜4のタスクを登録する。各Phase開始時に該当タスクを `in_progress` に、完了時に `completed` へ `TaskUpdate` で更新する。Phase 3からPhase 2へ差し戻す場合はPhase 2タスクを `in_progress` に戻す。実行環境にTaskCreate/TaskUpdateが存在しない場合は、出力先ディレクトリ内のタスク台帳ファイル（`task-ledger.md`）で同等のPhase遷移記録を代替する。

## 動作フロー（Phase 1〜4）

帳票固有の調査項目・検出手法・マニフェストスキーマの詳細は `references/report-detection.md` を参照する。

### Phase 1: スタック・帳票規約の特定

- **Step 1**: `package.json`・lockファイル（`package-lock.json`/`yarn.lock`/`pnpm-lock.yaml`）からフレームワークと帳票生成ライブラリ（puppeteer/pdfkit/ExcelJS 等）を確定する。これらが存在しないコードベースでは import 文・API 使用形跡から推定する。完了条件: ライブラリ名とバージョンが特定済み、または特定不能の根拠（推定経路）が記録済み
- **Step 2**: 帳票定義の所在を特定する。テンプレートファイル（Jasper/BIRT/Crystal 等）・PDF/Excel生成コード・レポート定義設定の実ファイルパスを列挙する。完了条件: 帳票定義を含む実ファイルパスが列挙済み
- **Step 3**: 帳票の識別要素を調査する。帳票ID命名パターン・出力形式（PDF/Excel/CSV/HTML）・データソース（クエリ・API呼び出し・集計ロジック）の対応関係を確認する。完了条件: `unitIdRegex` の候補値または「なし」が確定済み
- **Step 4**: 除外パターンを確定する。テスト用テンプレート・`tests`/`mocks` 等のノイズディレクトリを実際に `ls` で確認する。完了条件: `excludePatterns` 一覧が確定済み
- **Step 5**: 検出戦略宣言を作成し、AskUserQuestionで承認を取る。宣言JSONは一時ファイルに保存する。完了条件: 戦略JSON（`unitKind: "report"`/`extractionMethod: "custom"`/`unitIdRegex`/`excludePatterns`/`approvedByUser: true`/`notes`）が保存済み

### Phase 2: 戦略に基づく抽出（カスタム抽出パスのみ）

- **Step 1**: Phase 1で宣言した手順（例: テンプレートファイルの走査・帳票生成関数の呼び出し元収集・レポート定義設定のJSON解析等）をClaude自身がBash/Grep/Readで実行し、スキーマ準拠のマニフェストJSONをWriteする。0件検出の場合はユーザーに報告してハード停止する。帳票を捏造しない。完了条件: マニフェストJSONが生成済み、または0件検出を報告して停止している
- **Step 2**: diagnosticsを確認する。sourceFile集中警告等が出た場合は抽出手順を見直し、見直し時はStep 1へ戻る。完了条件: diagnosticsが空、または警告を承知の上で続行と判断済み
- **Step 3**: マニフェストへメタデータを付与する。`../../../shared/scripts/extract/extract-report-metadata.sh <manifest.json> <source_dir> <manifest.ext.json>` を実行し、各ユニットに `format`・`trigger` フィールドを追加した拡張マニフェスト（`manifest.ext.json`）を生成する。以降のPhaseでは `manifest.ext.json` を使用する。完了条件: 拡張マニフェストが生成済み

検出結果は一時ディレクトリ（`$CLAUDE_JOB_DIR/tmp/report-manifest.json`、未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下。`${session}`はセッションIDが取得できなければ任意の一意な値でよい）に保存する。

### Phase 3: 整合検証（機械実行）

- **Step 1**: `../../../shared/scripts/unit-list/validate-manifest.sh <manifest.ext.json> --unit-kind report` を実行する。完了条件: 全項目PASS
- **Step 2**: FAIL時は指摘に応じて修正する（sourceFile不在は `--fix` でunresolved降格可）。修正後Step 1を再実行する。3回失敗したら抽出手順の再検討（Phase 2 Step 1）へ差し戻す。完了条件: exit 0

カスタム抽出パスで生成したマニフェストであっても、この検証を通過しないマニフェストはPhase 4に進めない。

### Phase 4: 帳票一覧.html 生成

- **Step 1**: `../../../shared/scripts/unit-list/build-unit-list.sh <manifest.ext.json> <output_dir>/一覧/帳票一覧/帳票一覧.html --unit-kind report --portal-dir <output_dir>` を実行する。`--portal-dir` にはポータル（`index.html`）の配置先＝納品物ルート（output_dir=docs_root）を渡し、「ポータルへ戻る」リンクを実在パスに解決させる。build側が内部でvalidateを再実行するため、検証を経ないmanifestからは生成できない。完了条件: HTML生成済み

**手作業でのプレースホルダ置換は禁止する**（過去に `entryFile=None` の混入という実害が発生している）。HTML生成は必ずスクリプト経由の決定的処理で行う。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | Step 1〜4の調査完了（`references/report-detection.md` の調査項目に準拠）。Step 5の検出戦略宣言（`unitKind`/`extractionMethod`/`unitIdRegex`/`excludePatterns`）がユーザー承認済み |
| Phase 2 | Step 1でスキーマ準拠のマニフェストが1件以上確定、または0件検出をユーザーに報告して停止している。Step 2でdiagnosticsを確認済み。Step 3で拡張マニフェストに種別固有フィールド（format・trigger）が付与されている |
| Phase 3 | Step 1で `validate-manifest.sh --unit-kind report` が全項目PASS。Step 2のFAIL時修正ループは3回以内 |
| Phase 4 | Step 1で帳票一覧.htmlが生成され、埋め込みJSONがマニフェストと一致している |
| **Goal** | 検証済みマニフェストのみからHTMLが生成され、未解決/診断警告が可視化され、設計書単位の判断材料が揃っている |

## 返却

本スキルは orchestrating-reverse-docs-flow の契約に準拠する。完了時に以下を返す。

| キー | 内容 |
|---|---|
| status | `DONE \| ERROR` |
| artifacts | 生成した帳票一覧.htmlのパス |
| unit_list_html | artifacts[0] の汎用名エイリアス |
| embedded_json_ref | HTML内に埋め込んだマニフェストJSONへの参照 |
| unit_kind | `report`（固定値） |

## ツールリファレンス

| ツール | 用途 |
|---|---|
| Bash | `validate-manifest.sh`・`build-unit-list.sh` の実行、抽出時のファイル収集 |
| Read | package.json・帳票テンプレート・生成コード・`references/report-detection.md` の参照 |
| Grep/Glob | 帳票規約（帳票ID命名パターン・生成ライブラリ呼び出し）・帳票定義の調査、カスタム抽出パスでの物理ファイル収集 |
| Write | 検出戦略宣言の一時保存、マニフェストJSON出力（帳票一覧.html本体はスクリプト経由で生成） |
| AskUserQuestion | Phase 1の検出戦略宣言確認、Phase 2の0件検出時の報告 |
| TaskCreate/TaskUpdate | Phase 1〜4の進捗管理 |

## 推奨手順

- ソースディレクトリは対象プロジェクトの実コードルートを指定する。モノレポでアプリが複数ある場合は対象アプリのディレクトリのみを渡す（自動判別なし）
- Phase 1の調査を省略して汎用の `unitIdRegex` を当てない。プロジェクトごとに帳票の命名規約・生成方式は異なる
- 帳票の実体はテンプレート・生成コード・定義設定のいずれか（または複合）でありうる。Phase 1 Step 2で「このプロジェクトでは何を1帳票と数えるか」を先に確定させる

## 重要な注意事項

- 設計書の雛形展開・生成・記入は一切行わない。本スキルの成果物は帳票一覧.htmlのみ
- Phase 4のHTML手作業組み立てを禁止する。`build-unit-list.sh` を必ず経由し、プレースホルダの手動置換によるデータ混入を防ぐ
- 0件検出時にAskUserQuestionで手動リストを聞き出さない。誤った境界を即興確定させない

## 予想を裏切る挙動

- `validate-manifest.sh`・`build-unit-list.sh` は jq に依存する。未インストール環境では事前に導入する
- 帳票には組み込み検出器が存在しない。カスタム抽出パスのみを使う
- マニフェストの配列キーは `units`（`screens` ではない）
- 出力先は `<output_dir>/一覧/帳票一覧/帳票一覧.html`。帳票専用の独立フォルダを作成する
- カスタム抽出でソースを解析する際、コメントアウトされた帳票定義・import文を除去してから抽出する（コメント内の定義を実在として誤検出した実害を防ぐ）
- `kind` の区分値は `template`（テンプレート主体）・`generator`（生成コード主体）・`unresolved`（主ファイル未解決）の3つ（`references/report-detection.md` 参照）

## 完了報告

`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（作業報告型）に従う。

固有の検証行:
- validate-manifest.sh --unit-kind report が全項目 PASS・帳票一覧.html の生成成功

## 設計判断

### build-unit-list.sh（共有エンジン）

**必要性**: 帳票一覧.htmlの生成をClaude手作業（プレースホルダ置換）で行うと、検証なしのデータ混入が発生する（画面一覧での実例: `entryFile=None` が10件混入）。JSONマニフェストからHTMLへの変換を決定的スクリプトに固定化し、手作業経路を根絶する。種別別一覧スキル群で1本を共有するため `shared/scripts/unit-list/` に置く。

**代替案を採用しなかった理由**:
- Bashツール直叩き: 毎回30行超のjq+ヒアドキュメントを手書きし、エスケープ事故が再発する
- スキルフォルダ内への複製: 種別別スキルごとにコピーを持つと修正が分散し、挙動差が生まれる

**保守責任者**: 人手（ユーザー）

**廃棄条件**: 帳票一覧.htmlの形式が廃止された時

### validate-manifest.sh（共有エンジン）

**必要性**: 抽出がカスタムパス（Claude手書きJSON）であるため、品質を機械保証する独立検証が必須。マニフェストスキーマ・重複キー・unresolved隔離を抽出者非依存の同一基準で検査する。Phase 1で承認した検出戦略宣言（`approvedByUser: true`）の機械的な存在確認も本スクリプトが担う。

**代替案を採用しなかった理由**:
- Claude自己申告（検証コマンドを介さない目視確認）: 自己申告のみでの品質保証はデータ混入の実害実績があり信頼できない

**保守責任者**: 人手（ユーザー）

**廃棄条件**: マニフェスト形式（JSONスキーマ）が廃止された時
