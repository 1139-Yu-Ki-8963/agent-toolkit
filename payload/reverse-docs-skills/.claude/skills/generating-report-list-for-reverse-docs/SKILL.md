---
name: generating-report-list-for-reverse-docs
日本語名: 帳票一覧のとりまとめ
description: "既存のコードから帳票の単位を見つけ出し、帳票一覧のページを作る。"
invocation: generating-report-list-for-reverse-docs
type: transform
allowed-tools: [AskUserQuestion, Bash, Glob, Grep, Read, TaskCreate, TaskUpdate, Write]
---

## いつ使うか

既存のコードから帳票の一覧を新しく作りたいとき。

## いつ使わないか

帳票以外の種類の一覧を作るとき、原本との突き合わせや環境の同期や実装そのものを行うとき。

# 正本: reverse-docs-skills

本スキルが生成する納品物は顧客提示の文書である。自由記述の本文（要約・説明文）は敬体（です・ます）で書く。記入規則・検証記録・作業記録は常体でもよい（`delivery-payload/references/設計書様式.md` §8）。

# 帳票一覧生成スキル

工程全体は orchestrating-ai-development-setup が案内する。本スキルは帳票（`unit_kind=report` 固定）の一覧生成のみを担い、単独起動できる（起動引数 `source_dir`・`output_dir` の2つを渡せば動く）。

既存コードベースを、スタック調査→検出戦略の宣言→戦略に基づく抽出→整合検証、の順で調査し、帳票の単位にファイルをグルーピングして **帳票一覧.html** を作成する。**本スキルの仕事は帳票一覧.htmlの作成のみ**であり、設計書の雛形展開・生成・記入は一切行わない。

他スキルへの依存を持たず、単独で動作する。

## 設計原則: 固定と可変の分離

マニフェストスキーマ・整合検証（`validate-manifest.sh`）・HTML生成（`build-unit-list.sh`）は決定的スクリプトに固定する。抽出（帳票境界の検出）はプロジェクトごとに可変であり、**カスタム抽出パスのみ**を取る。帳票には組み込み検出器が存在しないため、Claude自身が Phase 1 の戦略宣言に沿ってプロジェクト専用の抽出手順を設計・実行し、スキーマ準拠のマニフェストJSON（配列キーは `units`）を出力する。

抽出者が誰であっても、`validate-manifest.sh` が抽出者非依存でマニフェストの整合性を機械保証する。汎用の正規表現を無条件に当てるのではなく、対象プロジェクト固有の帳票規約を先に確認してから検出することで、境界の取り違えを防ぐ。

### エンジンスクリプトの所在

エンジンスクリプトはスキルフォルダからの相対パスで参照する。

- 整合検証: `../../../generation-engine/scripts/unit-list/validate-manifest.sh`
- HTML生成: `../../../generation-engine/scripts/unit-list/build-unit-list.sh`

正本リポジトリと公開先はディレクトリレイアウトが同一のため、この相対参照は両環境でそのまま成立する。

## 使用タイミング

- 既存コードベースの帳票一覧を作りたいとき
- 起動引数: `source_dir`（ソースコードディレクトリ。探索対象）・`output_dir`（帳票一覧.htmlの書き出し先）の2つ

## 出力先

| 項目 | 値 |
|---|---|
| 出力フォルダ | `<output_dir>/<unitListDir>`（`unitListDir` は output-layout の物理配置キーで {label} は「帳票」） |
| 出力ファイル | `帳票一覧.html` |
| マニフェスト配列キー | `units` |

永続マニフェスト（`report-manifest.json`・`report-manifest.ext.json`）は HTML と同じフォルダではなく `<output_dir>/<manifestsRoot>/` に永続化する。`manifestsRoot` は output-layout の物理配置キー（既定値 `docs/manifests`）。

## 進捗管理（必須手順）

スキル開始時に `TaskCreate` でPhase 1〜4のタスクを登録する。各Phase開始時に該当タスクを `in_progress` に、完了時に `completed` へ `TaskUpdate` で更新する。Phase 3からPhase 2へ差し戻す場合はPhase 2タスクを `in_progress` に戻す。実行環境にTaskCreate/TaskUpdateが存在しない場合は、出力先ディレクトリ内のタスク台帳ファイル（`task-ledger.md`）で同等のPhase遷移記録を代替する。

## 動作フロー（Phase 1〜4）

帳票固有の調査項目・検出手法・マニフェストスキーマの詳細は `references/report-detection.md` を参照する。

## Phase 1: スタック・帳票規約の特定

## Step 1-1: スタック・帳票規約の特定

**使用ツール**: AskUserQuestion / Bash / Grep / Read / Write

- **Step 1**: `package.json`・lockファイル（`package-lock.json`/`yarn.lock`/`pnpm-lock.yaml`）からフレームワークと帳票生成ライブラリ（puppeteer/pdfkit/ExcelJS 等）を確定する。これらが存在しないコードベースでは import 文・API 使用形跡から推定する。完了条件: ライブラリ名とバージョンが特定済み、または特定不能の根拠（推定経路）が記録済み
- **Step 2**: 帳票定義の所在を特定する。テンプレートファイル（Jasper/BIRT/Crystal 等）・PDF/Excel生成コード・レポート定義設定の実ファイルパスを列挙する。完了条件: 帳票定義を含む実ファイルパスが列挙済み
- **Step 3**: 帳票の識別要素を調査する。帳票ID命名パターン・出力形式（PDF/Excel/CSV/HTML）・データソース（クエリ・API呼び出し・集計ロジック）の対応関係を確認する。完了条件: `unitIdRegex` の候補値または「なし」が確定済み
- **Step 4**: 除外パターンを確定する。テスト用テンプレート・`tests`/`mocks` 等のノイズディレクトリを実際に `ls` で確認する。完了条件: `excludePatterns` 一覧が確定済み
- **Step 5**: 検出戦略宣言を作成し、AskUserQuestionで承認を取る。宣言JSONは一時ファイルに保存する。完了条件: 戦略JSON（`unitKind: "report"`/`extractionMethod: "custom"`/`unitIdRegex`/`excludePatterns`/`approvedByUser: true`/`notes`）が保存済み

**完了**: Step 1〜4の調査完了（`references/report-detection.md` の調査項目に準拠）。Step 5の検出戦略宣言（`unitKind`/`extractionMethod`/`unitIdRegex`/`excludePatterns`）がユーザー承認済み

## Phase 2: 戦略に基づく抽出（カスタム抽出パスのみ）

## Step 2-1: 戦略に基づく抽出（カスタム抽出パスのみ）

- **Step 1**: Phase 1で宣言した手順（例: テンプレートファイルの走査・帳票生成関数の呼び出し元収集・レポート定義設定のJSON解析等）をClaude自身がBash/Grep/Readで実行し、スキーマ準拠のマニフェストJSONをWriteする。0件検出の場合は「0件時の分岐」節に従って処理する。帳票を捏造しない。完了条件: マニフェストJSONが生成済み、または0件検出を「0件時の分岐」に従い処理している
- **Step 2**: diagnosticsを確認する。sourceFile集中警告等が出た場合は抽出手順を見直し、見直し時はStep 1へ戻る。完了条件: diagnosticsが空、または警告を承知の上で続行と判断済み
- **Step 3**: マニフェストへメタデータを付与する。`../../../generation-engine/scripts/extract/extract-report-metadata.sh <manifest.json> <source_dir> <output_dir>/<manifestsRoot>/report-manifest.ext.json` を実行し、各ユニットに `format`・`trigger` フィールドを追加した拡張マニフェストを一時ファイル + rename で `<output_dir>/<manifestsRoot>/report-manifest.ext.json` へ原子的に永続化する。以降のPhaseでは永続化した `report-manifest.ext.json` を使用する。完了条件: 拡張マニフェストが `<output_dir>/<manifestsRoot>/report-manifest.ext.json` に永続化済み

**非UTF-8原本への対応**: 原本が UTF-8 以外のエンコーディングで書かれている場合、通常の文字列検索はバイナリ扱いとなりマッチ 0 件を返す。走査の前に `generation-engine/scripts/detect-encoding.sh encoding <file>` でエンコーディングを確定し、UTF-8 以外なら `detect-encoding.sh to-utf8` で変換した一時コピーに対して走査する。変換結果は永続化せず一時コピーで足りる。マッチ 0 件を「該当なし」と結論する前に、エンコーディングが原因でないことを確認する。

## 0件時の分岐

検出0件は2つの状態を区別する。アーキテクチャ調査書（`survey_doc_path`）の帳票種別の実在判定と突合して分岐する。エンコーディング起因の0件でないことを先に確認する（上記「非UTF-8原本への対応」）。

| 調査書の判定 | 意味 | 動作 |
|---|---|---|
| 帳票は実在しない | 帳票を持たないプロジェクト | `<output_dir>/<unitListAbsentMd>`（`unitListAbsentMd` は output-layout の物理配置キー。`{label}` に「帳票」を代入。既定値 `docs/manifests/帳票一覧（該当なし）.md`）を判定理由の転記付きで生成し、status=`NONE` で正常終了する。API とテーブル等の対象外記録と同型。呼び出し元は excluded-kinds.json の excludedKinds へ report を記録する |
| 帳票は実在する | 検出失敗（抽出パスの不適合、境界の誤り） | 停止する。headless=false なら AskUserQuestion で報告し、headless=true なら `<verification_dir>/progress.jsonl` へ記録して status=`ERROR` を返す。手動リストは聞き出さない |

`survey_doc_path` が未指定で調査書と突合できない場合は、実在判定を推測せず検出失敗として扱う（fail-closed）。

**名称（name）の作り方**: マニフェストの各ユニットに付与する名称は、実装モジュール名・サブ名・ユニットキー・実装状態マーカー等の内部識別子を機械連結して生成しない。業務語のみで名称を構成する。設定ファイルのコメント等から得た業務名がそれ単体で一意にならない場合は、実装が属する機能グループを業務語へ訳して前置きする。訳語は参照テーブル名・コード内コメント・呼び出し関数名・テンプレート名等、実装コードの根拠に基づかせ、根拠のないものは推定と明示する。業務名が「テスト用」「一覧」「トップ」のように実態を表していない場合は、実装を読んで帳票の実態に即した名称を作る。設定ファイルのコメントが空欄でフォールバックが必要な場合も、＜系統名：ユニットキー（サブ名）＞のような内部識別子の連結を名称にしない。参照テーブル名・データ操作の種別・呼び出し関数名・テンプレート名・出力される固定文言を手がかりに実装から業務名を作る。実装からも業務名を断定できない場合は捏造せず、推定であることと手がかりを記録に残す。当該ユニットは名称を空にせず「業務名が未確定である」旨が利用者に伝わる表記にし、要確認として別掲する。要確認件数は成果物のサマリへ表示する。名称の根拠と確信度は次の列構成で記録する。

| ユニットキー | 現行の名称 | 命名 | 根拠 | 断定可否 |
|---|---|---|---|---|

検出結果は一時ディレクトリ（`$CLAUDE_JOB_DIR/tmp/report-manifest.json`、未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下。`${session}`はセッションIDが取得できなければ任意の一意な値でよい）に保存する。確定後は `<output_dir>/<manifestsRoot>/report-manifest.json` へ一時ファイル + rename で原子的に永続化する。一時ファイルを後続・再開処理の入力にしてはならない。

**完了**: Step 1でスキーマ準拠のマニフェストが1件以上確定、または0件検出を「0件時の分岐」に従い処理している（該当なし生成による正常終了、または検出失敗の停止）。Step 2でdiagnosticsを確認済み。Step 3で拡張マニフェストに種別固有フィールド（format・trigger）が付与されている

## Phase 3: 整合検証（機械実行）

## Step 3-1: 整合検証（機械実行）

**使用ツール**: Bash / Write

- **Step 1**: `../../../generation-engine/scripts/unit-list/validate-manifest.sh <manifest.ext.json> --unit-kind report` を実行する。完了条件: 全項目PASS
- **Step 2**: FAIL時は指摘に応じて修正する（sourceFile不在は `--fix` でunresolvedへ扱いを下げられる）。修正後Step 1を再実行する。3回失敗したら抽出手順の再検討（Phase 2 Step 1）へ差し戻す。完了条件: exit 0

カスタム抽出パスで生成したマニフェストであっても、この検証を通過しないマニフェストはPhase 4に進めない。

**完了**: Step 1で `validate-manifest.sh --unit-kind report` が全項目PASS。Step 2のFAIL時修正ループは3回以内

## Phase 4: 帳票一覧.html 生成

## Step 4-1: 帳票一覧.html 生成

**使用ツール**: Bash / Write

- **Step 1**: `../../../generation-engine/scripts/unit-list/build-unit-list.sh <manifest.ext.json> <output_dir>/<unitListHtml> --unit-kind report --portal-dir <output_dir>` を実行する。`--portal-dir` にはポータル（`index.html`）の配置先＝納品物ルート（output_dir=output_dir）を渡し、「ポータルへ戻る」リンクを実在パスに解決させる。build側が内部でvalidateを再実行するため、検証を経ないmanifestからは生成できない。完了条件: HTML生成済み

**手作業でのプレースホルダ置換は禁止する**（過去に `entryFile=None` の混入という実害が発生している）。HTML生成は必ずスクリプト経由の決定的処理で行う。

**完了**: Step 1で帳票一覧.htmlが生成され、埋め込みJSONがマニフェストと一致している。永続マニフェストが `<output_dir>/<manifestsRoot>/report-manifest.json` に実在する

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | Step 1〜4の調査完了（`references/report-detection.md` の調査項目に準拠）。Step 5の検出戦略宣言（`unitKind`/`extractionMethod`/`unitIdRegex`/`excludePatterns`）がユーザー承認済み |
| Phase 2 | Step 1でスキーマ準拠のマニフェストが1件以上確定、または0件検出を「0件時の分岐」に従い処理している（該当なし生成による正常終了、または検出失敗の停止）。Step 2でdiagnosticsを確認済み。Step 3で拡張マニフェストに種別固有フィールド（format・trigger）が付与されている |
| Phase 3 | Step 1で `validate-manifest.sh --unit-kind report` が全項目PASS。Step 2のFAIL時修正ループは3回以内 |
| Phase 4 | Step 1で帳票一覧.htmlが生成され、埋め込みJSONがマニフェストと一致している。永続マニフェストが `<output_dir>/<manifestsRoot>/report-manifest.json` に実在する |
| **Goal** | 検証済みマニフェストのみからHTMLが生成され、未解決/診断警告が可視化され、設計書単位の判断材料が揃っている |

## 返却

本スキルは orchestrating-ai-development-setup の契約に準拠する。完了時に以下を返す。

| キー | 内容 |
|---|---|
| status | `DONE \| NONE \| ERROR` |
| artifacts | `DONE` は生成した帳票一覧.htmlのパス。`NONE` は `<output_dir>/<unitListAbsentMd>`（`unitListAbsentMd` は output-layout の物理配置キー。`{label}` に「帳票」を代入。既定値 `docs/manifests/帳票一覧（該当なし）.md`）のパス |
| unit_list_html | artifacts[0] の汎用名エイリアス |
| embedded_json_ref | HTML内に埋め込んだマニフェストJSONへの参照 |
| unit_kind | `report`（固定値） |
| report_manifest_path | 永続生マニフェスト（`<output_dir>/<manifestsRoot>/report-manifest.json`） |
| report_manifest_ext_path | 永続拡張マニフェスト（`<output_dir>/<manifestsRoot>/report-manifest.ext.json`） |

本スキルの status は `DONE | NONE | ERROR` のいずれかを返す。`NONE` は調査書が帳票の実在しないことを判定済みの場合だけ返す（「0件時の分岐」節を参照）。`NONE` で終了する場合、呼び出し元は excluded-kinds.json の excludedKinds へ report を記録する。

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

- ソースディレクトリは対象プロジェクトの実コードルートを指定する。モノレポの場合はアーキテクチャ調査書 §10 のサイト一覧で確定した当該サイトのルートディレクトリを渡す
- Phase 1の調査を省略して汎用の `unitIdRegex` を当てない。プロジェクトごとに帳票の命名規約・生成方式は異なる
- 帳票の実体はテンプレート・生成コード・定義設定のいずれか（または複合）でありうる。Phase 1 Step 2で「このプロジェクトでは何を1帳票と数えるか」を先に確定させる

## 重要な注意事項

- 設計書の雛形展開・生成・記入は一切行わない。本スキルの成果物は帳票一覧.htmlのみ
- Phase 4のHTML手作業組み立てを禁止する。`build-unit-list.sh` を必ず経由し、プレースホルダの手動置換によるデータ混入を防ぐ
- 0件検出時にAskUserQuestionで手動リストを聞き出さない。誤った境界を即興確定させない。該当なしの正常終了と検出失敗の停止の区別は「0件時の分岐」の表が正である

## 予想を裏切る挙動

- `validate-manifest.sh`・`build-unit-list.sh` は jq に依存する。未インストール環境では事前に導入する
- 帳票には組み込み検出器が存在しない。カスタム抽出パスのみを使う
- マニフェストの配列キーは `units`（`screens` ではない）
- 出力先は `<output_dir>/<unitListHtml>`。帳票専用の独立フォルダを作成する
- カスタム抽出でソースを解析する際、コメントアウトされた帳票定義・import文を除去してから抽出する（コメント内の定義を実在として誤検出した実害を防ぐ）
- `kind` の区分値は `template`（テンプレート主体）・`generator`（生成コード主体）・`unresolved`（主ファイル未解決）の3つ（`references/report-detection.md` 参照）

## 完了報告

`../../../delivery-payload/references/完了報告の書き方.md` の共通骨格（作業報告型）に従う。

固有の検証行:
- validate-manifest.sh --unit-kind report が全項目 PASS・帳票一覧.html の生成成功

## 設計判断

### build-unit-list.sh（共有エンジン）

**必要性**: 帳票一覧.htmlの生成をClaude手作業（プレースホルダ置換）で行うと、検証なしのデータ混入が発生する（画面一覧での実例: `entryFile=None` が10件混入）。JSONマニフェストからHTMLへの変換を決定的スクリプトに固定化し、手作業経路を根絶する。種別別一覧スキル群で1本を共有するため `generation-engine/scripts/unit-list/` に置く。

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
