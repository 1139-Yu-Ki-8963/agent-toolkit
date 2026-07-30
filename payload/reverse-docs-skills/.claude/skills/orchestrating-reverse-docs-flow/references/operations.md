# 統括フロー運用詳細

本書は `orchestrating-reverse-docs-flow/SKILL.md` から段階的開示した運用契約である。統括は Phase 1 の開始前に本文書を Read で全文読み込み、報告・委任・タスク・ループの書式を適用する。工程順序の正本は `shared/references/リバース工程設計.md`、返却値と状態の正本は `contract.md` とする。

## 最終報告フォーマット

管理者が Goal 到達時（または中断報告時）に提示する最終報告には、以下7種の必須フィールドをすべて含める。

| フィールド | 内容 |
|---|---|
| 種別判定結果 | 全6種別それぞれについて、アーキテクチャ調査書の実在判定（実在する／実在しない・理由）と対応する成果物パス（一覧HTML または `<種別>一覧（該当なし）.md`）を記す |
| 6種別到達状態 | 全6種別（screen/api/table/batch/report/external）それぞれの到達状態を3値（生成済み / 対象外 / 後続未対応）で記す（正本は `references/contract.md` の「種別ループ」） |
| 盲検分離充足状況（無人時のみ） | headless=true 実行時に限り、原本を読む工程と設計書のみで判定する工程が同一プロセスか分離実行かを記す（正本は `references/contract.md` の「無人モード仕様」の「盲検分離の必須要件」） |
| 部分著述 | 画面ごとに「対象ファイルn件/全m件」の形式で著述完了対象ファイル数と当該画面の全対象ファイル数を記す（正本は `references/contract.md` の「画面完了の定義」） |
| テスト実行結果 | 保存済みテストコード（rebuilding-screen-unit-from-docs の saved_test_paths 由来）の実行結果一覧を画面ごとに記す |
| 進捗ファイルの行数と最終行 | `<verification_dir>/progress.jsonl` の総行数と最終1行の内容を記す（工程の進行が実際に記録されていたことの裏取り） |
| 各工程のSkill起動有無と返却status | 実行した全工程について、子スキルを Skill ツールで起動したか否かと、返却された status を工程ごとに記す（完全仲介方式の禁止形が遵守されたことの裏取り） |

## 報告書式（3表テンプレート）

最終報告フォーマットの各フィールドは、次の3表のいずれかに集約して記載する。表の列・凡例は削除せず、値が無い場合も列自体は残し「該当なし」等で埋める。

### 表1: 種別判定・納品物ルート表

「種別判定結果」フィールドの書式。全6種別を1行ずつ記載する。

| 種別 | 実在判定 | 成果物パス | 到達状態 |
|---|---|---|---|
| screen | 実在する | `一覧/画面一覧/画面一覧.html` | 生成済み |
| api | 実在する | `一覧/API一覧/API一覧.html` | 後続未対応 |
| table | 実在しない（理由: …） | `一覧/テーブル一覧（該当なし）.md` | 対象外 |
| feature（派生） | 判定対象外（派生一覧） | `一覧/機能一覧/機能一覧.html` | 生成済み |
| … | … | … | … |

feature（機能一覧）は派生一覧であり、実在判定（unit_kinds_present）の対象外。到達状態は 生成済み / 未生成 の2値で記す。

### 表2: 画面単位の工程進行表

「部分著述」「テスト実行結果」フィールドの書式。対象画面ごとに1行を記載する。

| 画面ID | 現在Phase | 状態キー | 部分著述（n件/m件） | テスト実行結果 |
|---|---|---|---|---|
| screen-<画面ID> | Phase 7 | 検証完了 | 5件/5件 | PASS 5/5 |
| … | … | … | … | … |

### 表3: フェーズ完了ごとの増分報告

「各工程のSkill起動有無と返却status」「進捗ファイルの行数と最終行」フィールドの書式。工程（Phase）ごとに1行を記載する。

| Phase | Skill起動有無 | 返却status | 増分成果物 |
|---|---|---|---|
| Phase 2 | 起動済み | 調査確定 | アーキテクチャ調査書.md |
| Phase 3 | 起動済み | DONE | 一覧HTML × unit_kinds_present件数 |
| … | … | … | … |

進捗ファイル（`<verification_dir>/progress.jsonl`）の総行数と最終1行の内容は表3の末尾に注記として添える。

### 適用規則

- チャット上の報告では3表をそのまま（Markdown表として）表示する。要約に潰さない
- 無人モード（headless=true）では、最終報告ファイル（`<verification_dir>/screen-<画面ID>/<timestamp>/実行レポート.md` 等）にも同じ3表をそのまま含める
- 列・凡例の削除を禁止する。プロジェクトによって値が無い列（例: 「後続未対応」種別が無いプロジェクトの表1）も列自体は残し、該当行が無ければ「該当なし」と明記する

## サブエージェント委任仕様

| 呼び出し箇所 | invocation | args骨格 | 期待返却status |
|---|---|---|---|
| global Step 3〜7 | surveying-architecture-for-reverse-docs | target_repo_path, output_dir, template_root, mode | 調査確定 |
| global Step 9 | generating-<種別>-list-for-reverse-docs（不在種別ごとに対応スキル） | source_dir, output_dir | DONE |
| global Step 10 | generating-feature-list-for-reverse-docs | source_dir, output_dir | DONE |
| global Step 11 | generating-cross-views-for-reverse-docs | target_repo_path, output_dir, portal_output_dir（任意）, sites_path（任意）, site_key（任意） | DONE |
| global Step 12〜15 | generating-reverse-common-docs | target_repo_path, output_dir, template_root, survey_doc_path, mode | 採録v0確定 / 追記完了 |
| global Step 16 | surveying-local-environment / counting-code-lines / 基盤ページ生成スキル | output_dir, target_repo_path, portal_output_dir | DONE |
| global Step 2（明示Python facts-only経路） | extracting-unit-facts-from-code | target_repo_path, target_file_paths, logical screen_dir, verification_dir, profile=python, survey_doc_path, run_id | 封印済み→Python facts封印完了 |
| global Step 18〜21 | extracting-unit-facts-from-code | target_repo_path, target_file_paths, screen_dir, verification_dir, profile=screen, survey_doc_path, run_id | 封印済み |
| global Step 22〜24 | generating-reverse-basic-design | screen_dir, output_dir, template_root, scaffold_script_path, facts_ref, common_docs_root, unit_kind, authoring_pass, detail_design_path・pass1_receipt_path（large-pass2時） | 基本設計著述完了 |
| global Step 25〜28 | generating-reverse-detailed-design | screen_dir, output_dir, template_root, chapter_map_path, audit_script_path, scaffold_script_path, facts_ref, common_docs_root, mode, target_file_path, verification_url, verification_dir, authoring_pass, detail_design_path・pass1_receipt_path（companion-docs時） | AUTHORED / DETAIL_AUTHORED / COMPANION_AUTHORED |
| global Step 29 | unlocking-reverse-target-screens / syncing-reverse-env / rebuilding-screen-unit-from-docs / rebuilding-code-from-docs | 動的検証に必要なargs全量 | UNLOCKED / PASS / 再現一致 / NEED-COMPARE |
| global Step 30 | rebuilding-code-from-docs / syncing-reverse-env | mode=judge と compare_result / mode=syncまたはteardown | PASS/FAIL |

Agent（サブエージェント）は preflight の並行事実確認等に限定して用いる。実検証は子スキルへ委ねる。

**並列起動**: `authoring_mode=standard` は generating-reverse-basic-design と generating-reverse-detailed-design を同時起動する。`authoring_mode=large-two-pass` は詳細設計のパス1を単独で完了させた後、パス2の基本設計と周辺文書を同時起動する。パス境界をまたぐ並列化は禁止する。

## タスク一覧フォーマット

Phase 1 の状態判定完了後に一括登録するタスク一覧の設計。

### subject 形式

`Phase <N>[-<N>]: [<画面ID>: ]<工程名>[ ← 並列グループ<G>]`

- 画面横断工程（アーキ調査・一覧生成・共通採録）: 画面IDなし
- 画面単位工程: 画面ID付きで画面数分展開
- 並列実行対象: 並列グループIDを末尾に付与し、同グループは Agent(run_in_background: true) で同時起動

### 展開例（画面 A・B の 2 件、アーキ〜一覧は完了済みの場合）

| subject | 並列 |
|---|---|
| Step 4-1〜4-5: 共通採録とポータル | — |
| Step 5-2〜5-5: 画面A: 事実封印 | — |
| Step 5-6〜5-8: 画面A: 基本設計 | 並列グループ-画面A-設計 |
| Step 5-9〜5-12: 画面A: 詳細設計・返却検収 | 並列グループ-画面A-設計 |
| Step 6-1: 画面A: 動的往復検証 | — |
| Step 7-1: 画面A: 判定・基準更新 | — |
| Step 5-2〜5-5: 画面B: 事実封印 | — |
| Step 5-6〜5-8: 画面B: 基本設計 | 並列グループ-画面B-設計 |
| Step 5-9〜5-12: 画面B: 詳細設計・返却検収 | 並列グループ-画面B-設計 |
| Step 6-1: 画面B: 動的往復検証 | — |
| Step 7-1: 画面B: 判定・基準更新 | — |

### ルール

- global Step 9（6一覧並列）は「Step 3-1: 一覧生成-画面」「Step 3-1: 一覧生成-API」…と種別分展開し、全て同一並列グループにする
- global Step 10〜11は派生一覧・派生補完として1タスクずつ登録する
- screen-batch-route 選択時はglobal Step 17〜30を「条件付きStep: 画面バッチ実行」1タスクに集約し、新しいPhase番号を作らない
- 差し戻し発生時は差し戻し先工程を新規 TaskCreate で末尾に追加（既存タスクの状態は変更しない）
- headless=true 時もタスク一覧は同じ形式で生成する（進捗の可視化用途。実行制御は per-item prompt が担う）

## ループ設計

| 要素 | 内容 |
|---|---|
| 反復条件 | `verification_mode=iterative` かつ global Step 30 の judge が FAIL → Back-edgeメタデータで分類し、共通文書欠落はglobal Step 14、facts欠落はglobal Step 18、著述不足はglobal Step 26へ戻す |
| 上限回数 | max_loop（既定3。⑧の max_loop とは別軸の工程ループ） |
| 停止条件 | ① 収束停止: 全対象画面が PASS（2連続で確定）② リソース上限: max_loop 到達で FAIL 確定 ③ 発散検知: ⑨judge が2連続同一差分（compare_result の static_diff 署名一致）で上限前に打切り |
| 検証役の分離 | 各工程の判定は子スキルの返却ブロック（status）のみで行い、管理者は自然文で判定しない |

この外側ループ（発散判定2連続・上限）は、元々④（rebuilding-code-from-docs）が持っていた責務を管理者へ移管したものである。

### 静的著述とファイル単位検証の反復

| 要素 | 内容 |
|---|---|
| 反復条件 | `verification_mode=iterative` かつ rebuilding-screen-unit-from-docs（ファイル単位未検証）が status=差し戻し を返したら generating-reverse-detailed-design（設計書未著述）へ戻し、再著述後にファイル単位未検証を再実行する |
| 上限回数 | 5回目安（rebuilding-screen-unit-from-docs 自身の内側ループ上限と揃える） |
| 停止条件 | ① 収束停止: rebuilding-screen-unit-from-docs が status=再現一致 を返す ② リソース上限: 5回到達しても差し戻しが続く場合はユーザーに報告する |
| 検証役の分離 | 設計書未著述（著述）とファイル単位未検証（盲検検証）は別スキル・別セッションで実行され、判定は自身の完全性ゲート・6計測の決定的出力のみで行う |

## 設計判断

### build-portal / render-template

**必要性**: ポータル生成はリバース設計フローの global Step 16 で毎回実行される。テンプレート置換ロジック（render_template）は build-unit-list.sh と build-screen-list.sh に既に重複定義されており、ポータル生成でも同じロジックが必要なため、共通関数として render-template.sh に抽出した。build-portal.sh はコード行数計測・一覧件数抽出・JSON組み立て・テンプレート置換の複合処理であり、Bash ツール直叩きでは毎回の実行でトークンを大量に浪費する。

**代替案を採用しなかった理由**:
- Bash ツール直叩き: 200行超のスクリプトを毎回トークンとして消費する。フロー内で global Step 16 として繰り返し呼ばれるため非効率
- 既存 Makefile ターゲット拡張: reverse-docs-skills リポジトリに Makefile は存在しない
- package.json scripts 追加: 同リポジトリに package.json は存在しない

**保守責任者**: 人手（ユーザー）。テンプレートのプレースホルダや一覧HTMLのJSON構造を変更する場合は build-portal.sh と portal-template.html を同時に更新する。METRICS_JSON は構造化オブジェクト形式である。形式変更時はテンプレート（portal-template.html）とスクリプト（build-portal.sh）を同一コミットで同時更新する。トークンブロックは portal-template.html と detail-pages テンプレ4本（`shared/templates/detail-pages/`）で複製している。色定義・テーマ切替を変更する場合は両方を同時に更新する

**廃棄条件**: リバース設計フロー自体が廃止された時、またはポータル生成が別の仕組み（専用スキル等）に置き換えられた時

### build-detail-page.sh / validate-page-data.sh

**必要性**: 基盤ページ5枚（用語辞書・技術スタック・画面遷移図・ER図・環境構築手順）は、生成スキルが抽出した page-data.json をテンプレ4本へ流し込む処理を共通で必要とする。この流し込みロジックを各スキルに複製すると、`build-portal.sh` の FUTURE_FILES と出力ファイル名がスキルごとにずれる事故が起こりうる。`build-detail-page.sh` は page 種別 → テンプレ・固定出力ファイル名の対応表を1箇所に固定し、FUTURE_FILES との一致を機械保証する。`validate-page-data.sh` は埋め込みJSONの `jq -S` 一致・マーカー衝突・未解決 `{{` の残存・sourceRef の実在確認を、抽出者（各スキル）非依存で検証する。いずれも複数の決定的処理を含み、Bash ツール直叩きでは self-test を持てず回帰検証ができない。

**代替案を採用しなかった理由**:
- Bash ツール直叩き: 5スキル × 生成のたびに同じ流し込み・検証手順を手書きすると条件がぶれ、FUTURE_FILES との不一致を機械的に検知できない
- 既存 Makefile ターゲット拡張: 本リポジトリに Makefile は存在せず、新規導入は本チェック専用の依存を増やすだけになる
- package.json scripts 追加: 同様に本リポジトリはビルド設定を持たない

**保守責任者**: 人手（ユーザー）。テンプレ4本を変更する場合は build-detail-page.sh の対応表・page-data-schema.md・validate-page-data.sh を同時に更新する

**廃棄条件**: 詳細ページ機構（基盤ページ5枚の生成）自体が廃止された時
