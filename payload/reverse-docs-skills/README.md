# reverse-docs-skills

既存コードから設計書をリバース生成し、その設計書だけからコードを再生成して原本と一致するまで往復検証するスキル群の正本リポジトリ。

## 言葉

このリポジトリの文書で使う言葉のうち、初めて読む人に馴染みの薄いものをここでまとめて説明する。

| 言葉 | 意味 |
|---|---|
| リバース | 既存のコードを読み取り、そこから設計書を書き起こす処理を指す言葉。 |
| 派生 | 既存の一覧や生成物を元に、グルーピングやまとめ直しでさらに作る成果物を指す言葉。 |
| 種別 | 画面・API・テーブル・バッチ・帳票・外部連携・機能という、生成対象を分類する区分を指す言葉。 |
| 単位 | 画面やAPIなど、設計書を1件ずつ数えるまとまりを指す言葉（例: 画面単位）。 |
| 工程 | 一覧生成・facts抽出・設計書執筆・往復検証という、リバース生成が進む段階を指す言葉。 |
| ポータル | 一覧・設計書・規約などの生成物をまとめて閲覧できる、HTML形式の案内ページを指す言葉。 |
| manifest | 一覧の元になる、種別ごとの候補情報をJSON形式でまとめたファイルを指す言葉。 |

## 概要

このリポジトリは、指揮役 1 個を含む実在する 52 スキルで構成される。既存コードベースを走査して一覧・共通文書・詳細設計書を積み上げ、最後に「設計書だけからコードを再生成し、原本と機械突合する」往復検証で設計書の品質を保証する。再生成コードが原本と一致しなければ設計書のどこかに欠落がある、という考え方により、設計書の完成度を主観ではなく機械判定（画面描画・内容・ARIA・画素差分・console・操作の各一致）で確定させる。スキル数の正本は `.claude/skills/*/SKILL.md` の実在ファイルであり、本 README の表は役割と主成果物を読むための索引である。

## 成果物の最終形

すべての成果物は設計書リポジトリの `<output_dir>` 配下に積み上がる。最終形の要約は次のとおり（全量は [納品物フォルダ体系.md](delivery-payload/references/納品物フォルダ体系.md) を参照）。

```
<output_dir>/
├── 一覧/                  # 種別ごとの目録（画面一覧.html 等6種 + 機能一覧（派生）） + excluded-kinds.json + 画面レジストリ
├── プロジェクト共通/      # アーキテクチャ調査書 + 共通設計書 + メッセージ定義書 + DESIGN.md 等 7 文書
├── <screenUnitRoot>/screen-<ID>/ # 画面単位の物理root（output-layout.jsonで解決、既定値: 画面）+ 詳細設計・基本設計・テスト項目書
└── API/ テーブル/ バッチ/ 帳票/ 外部連携/   # 各種別の詳細設計置き場（現時点は一覧確立まで）
```

検証記録（facts・往復検証の証跡）は納品物ではないため `output_dir` の外に配置する。`output_dir` と同階層の `verification/` フォルダに移動した（詳細は [納品物フォルダ体系.md](delivery-payload/references/納品物フォルダ体系.md) を参照）。

規約定義も `output_dir` の外に置く。対象リポジトリ直下の `docs/rules/` に親 7・子 27 の 2 階層で配置する。雛形は `scaffold-rule-definitions.sh` が配る。`delivery-payload/references/rule-taxonomy.json` が宣言する子 27 は、すべてツール側が本文を定めて納品する。本文が持つのは役割と方針の水準であり、対象リポジトリ固有の規則は各 rule.md の「このプロジェクトの規則」の節が規約提案の取り込みから受ける。提案 HTML の生成・取り込み・派生生成の 3 段構成による。

スキルを 1 つ実行するごとに増える成果物の対応（標準の実行順）:

| 実行順のスキル | `<output_dir>` に増える成果物 |
|---|---|
| surveying-architecture-for-reverse-docs | `プロジェクト共通/アーキテクチャ調査書.md`（機械検証済み） |
| generating-<種別>-list-for-reverse-docs（実在種別ごと） | `一覧/<種別>一覧/<種別>一覧.html`。全種別確定後に指揮役が `一覧/excluded-kinds.json` を書き出す |
| unlocking-reverse-target-screens | `一覧/reverse-screen-registry.yml` への記帳と、対象コード側の基準タグ（`reverse-baseline/<scope>`） |
| generating-reverse-common-docs | `プロジェクト共通/` の 7 文書 v0（共通設計書・メッセージ定義書・DESIGN.md 等 6 文書 + サンプル記録.md）。規約は出力しない。規約は `docs/rules/` で別管理する |
| extracting-unit-facts-from-code | `verification/screen-<ID>/facts/<run_id>/`（facts 一式 + 封印 facts.lock） |
| generating-reverse-basic-design | `<screenUnitRoot>/screen-<ID>/基本設計/画面基本設計書.md`（`screenUnitRoot` は output-layout.json で解決） |
| generating-reverse-detailed-design | `<screenUnitRoot>/screen-<ID>/詳細設計/画面詳細設計書.md`・`DESIGN.md`・`original.png`（画面キャプチャ） |
| rebuilding-screen-unit-from-docs | `verification/screen-<ID>/単体-<対象ファイル>/` の検証記録と `テスト項目書/テストコード/単体/` の最終テストコード |
| rebuilding-code-from-docs + syncing-reverse-env | `verification/screen-<ID>/<timestamp>/修正指示書.md`・`最終報告.md`、判定 PASS 時は基準タグの本番更新と `詳細設計/rebuilt.png`（画面キャプチャ）の更新 |

## スキル一覧

`.claude/skills/*/SKILL.md` に実在する全52スキル。以下の表は役割と主成果物を読むための索引であり、実数はファイル実体を正本とする。

| スキル名 | 役割 | 主成果物 |
|---|---|---|
| orchestrating-ai-development-setup | 指揮役。状態判定から次工程の子スキルを機械的に起動する | excluded-kinds.json・画面レジストリの管理 |
| generating-screen-list-for-reverse-docs | 画面の一覧生成 | 画面一覧.html |
| generating-api-list-for-reverse-docs | API の一覧生成 | API一覧.html |
| generating-api-basic-design-for-reverse-docs | API 1本ごとの基本設計書を業務語彙のみで生成 | API基本設計書.md |
| generating-api-detail-design-for-reverse-docs | API 1本ごとの詳細設計書を原本読解から生成 | API詳細設計書.md |
| generating-table-list-for-reverse-docs | テーブルの一覧生成 | テーブル一覧.html |
| generating-table-definition-for-reverse-docs | テーブル定義書を原本のschemaから生成 | テーブル定義書.md |
| generating-table-logical-model-for-reverse-docs | テーブルの論理データモデルを業務語彙のみで生成 | 論理データモデル.md |
| generating-batch-list-for-reverse-docs | バッチの一覧生成 | バッチ一覧.html |
| generating-batch-basic-design-for-reverse-docs | バッチ 1本ごとの基本設計書を業務語彙のみで生成 | バッチ基本設計書.md |
| generating-batch-detail-design-for-reverse-docs | バッチ詳細設計書を原本の処理定義から生成 | バッチ詳細設計書.md |
| generating-report-list-for-reverse-docs | 帳票の一覧生成 | 帳票一覧.html |
| generating-report-basic-design-for-reverse-docs | 帳票 1本ごとの基本設計書を業務語彙のみで生成 | 帳票基本設計書.md |
| generating-report-detail-design-for-reverse-docs | 帳票詳細設計書を原本の編集処理から生成 | 帳票詳細設計書.md |
| generating-external-list-for-reverse-docs | 外部連携の一覧生成 | 外部連携一覧.html |
| generating-external-basic-design-for-reverse-docs | 外部連携の基本設計書を業務語彙のみで生成 | 外部連携基本設計書.md |
| generating-external-detail-design-for-reverse-docs | 外部連携詳細設計書を原本の電文定義から生成 | 外部連携詳細設計書.md |
| generating-feature-list-for-reverse-docs | 既存一覧を業務機能単位でグルーピングした派生一覧を生成 | 機能一覧.html |
| generating-feature-design-for-reverse-docs | 機能単位の集約設計書を機能一覧マニフェストと配下ユニットから執筆 | 機能設計書.md |
| generating-tech-stack-for-reverse-docs | 調査書と定義ファイルの実測突合から技術スタックページを生成 | 技術スタック.html |
| generating-env-guide-for-reverse-docs | 調査書とローカル環境調査結果から環境構築手順ページを生成 | 環境構築手順.html |
| generating-screen-transition-for-reverse-docs | 画面一覧マニフェストとルーティング定義から画面遷移図を生成 | 画面遷移図.html |
| generating-er-diagram-for-reverse-docs | テーブル一覧マニフェストと FK 定義から ER 図を生成 | ER図.html |
| generating-glossary-for-reverse-docs | リバース解析から未承認の用語候補を生成する互換入口 | 対象repo外の proposal YAML・diagnostics |
| maintaining-semantic-glossary | 用語追加・更新・廃止・重複検出・影響分析・レビュー補助 | glossary change・検査結果 |
| managing-semantic-glossary | 承認済み用語YAMLの検証・適用・portal publishを統括 | 用語辞書.html・実行結果 |
| surveying-architecture-for-reverse-docs | 対象リポジトリの前提調査を機械検証付きで確定 | アーキテクチャ調査書.md |
| unlocking-reverse-target-screens | 設計書が無い画面をモック API で開通させ基準タグ確立まで単独完走 | 画面レジストリ記帳・基準タグ |
| syncing-reverse-env | リバース元と設計書の 2 環境同期・比較・基準タグ操作 | 基準タグ・比較結果ブロック |
| generating-reverse-common-docs | 層化サンプリングでプロジェクト共通 7 文書の v0 を採録 | プロジェクト共通/ 7 文書 |
| extracting-unit-facts-from-code | 原本コードから宣言的契約の事実表（facts）を抽出し封印 | facts 一式 + facts.lock |
| generating-reverse-basic-design | 封印済み facts と共通文書から業務語彙のみで画面基本設計書を執筆 | 画面基本設計書.md |
| generating-reverse-detailed-design | 封印済み facts と共通文書から画面詳細設計書を執筆 | 画面詳細設計書.md・DESIGN.md |
| rebuilding-screen-unit-from-docs | 設計書だけから 1 ファイルを再生成し原本と突合（ファイル単位検証） | 検証記録・最終テストコード |
| rebuilding-code-from-docs | 設計書だけから画面単位で再実装し比較・判定（implement / judge の 2 モード） | 修正指示書.md・最終報告.md |
| running-reverse-screen-batch | 画面単位の検証を claude -p 無人バッチで一括実行 | 画面バッチ実行ログ |
| counting-code-lines | 対象コードの行数を算出 | 行数集計結果 |
| surveying-local-environment | 対象プロジェクトのローカル実行環境を調査 | 環境調査結果 |
| generating-component-inventory-for-reverse-docs | UIコンポーネントを棚卸し | コンポーネント棚卸し |
| generating-cross-views-for-reverse-docs | 複数成果物を横断する対応表を生成 | 対応表 |
| generating-design-system-for-reverse-docs | デザインシステムを採録 | デザインシステム |
| generating-entity-state-for-reverse-docs | エンティティ状態を採録 | 状態遷移表 |
| generating-icon-catalog-for-reverse-docs | アイコンを棚卸し | アイコンカタログ |
| generating-message-list-for-reverse-docs | メッセージを棚卸し | メッセージ一覧 |
| generating-release-notes-for-reverse-docs | リリース履歴を採録 | リリースノート |
| generating-sequence-diagram-for-reverse-docs | シーケンスを採録 | シーケンス図 |
| generating-test-viewpoint-list-for-reverse-docs | テスト観点を一覧化 | テスト観点一覧 |
| generating-test-case-list-for-reverse-docs | 画面ごとのテスト仕様書（単体・結合・操作シナリオ）を横断集約しテストケース一覧を生成 | テストケース一覧.html |
| generating-agent-config-index-from-repo | リポジトリ分析からAGENTS/CLAUDE索引を生成 | AGENTS.md・CLAUDE.md |
| generating-requirement-definitions-for-reverse-docs | 一覧マニフェストと個別基本設計書から観測できる事実だけで要件定義5文書を生成 | 機能要件一覧・帳票要件・バッチ要件・外部連携要件・ビジネス概要 |
| generating-rule-proposals-for-reverse-docs | 対象コードの実装慣行を観測し、規約提案HTMLをリポジトリ外へ出力 | 規約提案HTML |

## 種別×工程の対応表

6 種別 × 4 工程の対応状況。画面のみ全工程が確立済みで、他 5 種別は一覧生成まで対応済み（facts 抽出以降は「[段階計画](#段階計画)」の対象）。ポータルで扱う納品物カテゴリ全体（基盤情報・規約・設計書・一覧/設計図・マトリクス/対応表・AI設定資産・デザイン）は生成されるポータルの納品物ガイドの納品物表を正本とする。

| 種別 | 一覧生成 | facts 抽出 | 設計書執筆 | 往復検証 |
|---|---|---|---|---|
| 画面 | 済 | 済 | 済 | 済 |
| API | 済 | 未対応 | 未対応 | 未対応 |
| テーブル | 済 | 未対応 | 未対応 | 未対応 |
| バッチ | 済 | 未対応 | 未対応 | 未対応 |
| 帳票 | 済 | 未対応 | 未対応 | 未対応 |
| 外部連携 | 済 | 未対応 | 未対応 | 未対応 |

「未対応」は一覧確立の時点で工程が止まる状態を指す。アーキテクチャ調査書で「実在しない」と判定された種別（excluded-kinds.json に記録）とは区別される。

## 全体の流れ

事前ヒアリングで対象パス・出力先・画面範囲を確定後、Phase 1〜7 / global Step 1〜41の状態機械で進行する。global Step 9では6一覧をAgent並列実行でき、global Step 16の条件分岐で画面数4件以上の場合だけrunning-reverse-screen-batchへStep 17〜28・40〜41を委譲する。条件分岐は新しいPhase番号を作らない。`docs-only` はglobal Step 28で静的リバース完了として終端する。標準ユニットは基本設計と詳細設計を並列著述し、大規模ユニットは1回目に詳細設計だけを完成させ、2回目に基本設計・観点表・テスト仕様書を作る。

指揮役は成果物の実在から現在の状態を判定し（15 状態）、次に起動する子スキルを機械的に決める。判定は次の順に降りる判定フローで行う。

```
アーキ未調査 → 一覧未生成 → 共通未採録 → ポータル未生成
  → 基盤ページ未生成（任意） → 状態遷移図未生成（任意） → シーケンス図未生成（任意）
  → 事実未封印 → 基本設計未著述 → 設計書未著述
  → 画面未開通（動的検証時のみ） → ファイル単位未検証（任意工程）
  → 基準未確立 → 往復未検証 → 検証完了
```

工程順の要約:

```
アーキ調査 ─→ 一覧生成（実在種別ごと） ─→ 共通採録 v0
     ─→ facts 抽出・封印 ─→ 標準: 基本設計 ‖ 詳細設計（並列）
                       └─→ 大規模: 詳細設計（1回目）→ 基本設計 ‖ 観点表・テスト仕様書（2回目）
     ─→（動的検証時）画面開通 ─→（任意）ファイル単位検証
     ─→ 往復検証（再実装 → 環境比較 → 判定） ─→ PASS: 基準タグ更新
                                              └─→ FAIL: 結果報告
                                                   └─→ iterative 指定時のみ NG 帰着 3 系統へ差し戻し
```

画面が未開通でも、原本コードから facts を抽出し、基本設計・詳細設計まで静的リバースを完了できる。動的検証は `verification_mode` で選ぶ。既定の `single-pass` は1回だけ検証し、`docs-only` は静的リバースで終了、`iterative` を明示した場合だけ FAIL 後の再抽出・再著述・再比較を反復する。

状態判定表・返却ブロック契約の正本は [contract.md](.claude/skills/orchestrating-ai-development-setup/references/contract.md)、唯一のグローバル順序（Phase 1〜7 / Step 1〜41）と条件分岐・back-edge metadataは [リバース工程設計.md](delivery-payload/references/リバース工程設計.md) を参照。全体ガイドと納品先向けの読み方は、生成されるポータルの案内ページを参照。

## 使い方

起動の前に、`RUNBOOK.md` の「1. 推奨配置」と「2. 起動規約」で置き場所と起動の決まりを確かめる。

### (a) 指揮役から起動する（推奨）

`orchestrating-ai-development-setup` を起動すると、成果物の実在から現在の状態を判定し、必要な工程だけを自動で続行する。人間の介在点はスコープ確認（Phase 1）と白紙化承認（user-approved）のみ。

```
Skill(orchestrating-ai-development-setup)
```

### (b) 子スキルを単独起動する

各子スキルは指揮役が渡すのと同じ引数（args）をユーザーが手渡しすれば単独で動く。引数の全量は [contract.md](.claude/skills/orchestrating-ai-development-setup/references/contract.md) の「args 仕様」を参照。

```
例: extracting-unit-facts-from-code に
    target_repo_path / target_file_paths / screen_dir / profile=screen / survey_doc_path を手渡し
```

## ポータル生成の前後処理受け口

配布物の生成器（`generation-engine/scripts/build-portal.sh`）だけではポータルを再現できない場合がある。取り込み可否を調べた結果は次の表のとおりで、取り込まないと判断した工程は実行側が独自スクリプトで補う必要がある。そのために、ポータル生成の前後に任意の処理を差し込む受け口を用意している。

### 使い方

`build-portal.sh` に `--pre-build <コマンド>` と `--post-build <コマンド>` を渡すと、それぞれ次のタイミングで `sh -c` 実行される。

- `--pre-build`: 引数の解決が終わり、ポータルの生成を始める直前
- `--post-build`: `index.html` を書き出した直後

```bash
bash generation-engine/scripts/build-portal.sh <target_repo_path> <output_dir> <portal_output_dir> \
  --pre-build "対象リポジトリの設計文書から一覧の入力データを組み立てるスクリプト" \
  --post-build "`--build-manifests-from-docs` でも導けなかった項目をポータルへ反映するスクリプト"
```

差し込んだコマンドへは、次の 3 つの環境変数で対象リポジトリ・docs・ポータルの各パスが渡る。

| 環境変数 | 内容 |
|---|---|
| `REVERSE_DOCS_TARGET_REPO` | 対象リポジトリのパス（`<target_repo_path>`） |
| `REVERSE_DOCS_DOCS_DIR` | 設計文書の出力先パス（`<output_dir>`） |
| `REVERSE_DOCS_PORTAL_DIR` | ポータルの出力先パス（`<portal_output_dir>`） |

値を指定しなければ何も実行しない。差し込んだコマンドが非 0 で終了した場合、`build-portal.sh` 自体もその終了コードで異常終了する。差し込んだ処理の失敗を黙って握りつぶさない。

`build-portal.sh` に `--build-manifests-from-docs` を渡すと、`--pre-build` よりも前（生成開始前・一覧ページを組み立てるより先）に `generation-engine/scripts/portal-input/build-manifests-from-docs.sh` が実行され、設計文書の frontmatter から非画面 6 種別（API/テーブル/バッチ/帳票/外部連携/機能）の一覧マニフェストを組み立てる。出力先は `output-layout.json` の `manifestsRoot`（既定 `docs/manifests`）配下で、既存の一覧生成（`generating-<種別>-list-for-reverse-docs`）が読む場所と同じ。`delivery-payload/references/doc-extraction.json` が無い場合、または抽出コマンド自体が失敗した場合は非 0 で終了する。

```bash
bash generation-engine/scripts/build-portal.sh <target_repo_path> <output_dir> <portal_output_dir> \
  --build-manifests-from-docs
```

### 取り込み可否の判断

| 処理 | 判断 | 理由 |
|---|---|---|
| 規約定義から人間向けページと索引のカードを生成する処理 | 取り込み済み | `portal-catalog.mjs` と `build-portal.sh` に既に実装済み |
| 対応表の描画不具合を生成後に当て直す後処理 | 不要 | 回避の対象だった不具合をテンプレートへ恒久修正したため、生成後の当て直し自体が不要になった |
| 種別ごとの一覧の入力データを設計文書から組み立てる処理 | 一部取り込み | 設計文書テンプレートの frontmatter は6種別（API/テーブル/バッチ/帳票/外部連携/機能）ともキー名がこのリポジトリのテンプレートで固定されており、`delivery-payload/references/doc-extraction.json` の宣言で設定化できた。`unitKey`・`unitId`・`sourceFile`、および API の `identifier` は frontmatter から導ける。一方、`kind`・`confidence`・`detectionMethod`・`fileCount`、および API 以外の `identifier` は原本コードの静的解析に由来し、設計文書テンプレートが意図的にコード識別子を排除しているため文書からは復元できず、宣言の代替値（`unresolved`・`low` 等）で埋める。`build-portal.sh` の `--build-manifests-from-docs`（上記）でこの抽出を実行する |
| 状態遷移図の入力データを設計文書から組み立てる処理 | 取り込み済み | `データ設計.md` §6「状態遷移表」の根拠パス列から `sourceRef` を抽出できる。欄を新設する必要はなかった |
| ER図の入力データを設計文書から組み立てる処理 | 取り込み済み | `テーブル定義書.md` §6.3「外部キー」に出典参照・関連の種別（cardinality）の列を足し、そこから抽出できるようにした |
| 画面遷移図の入力データを設計文書から組み立てる処理 | 取り込み済み | 画面遷移図の入力だけが確信度（値そのものではなく値の確からしさを表す判断のメタ情報）を要求するが、`画面基本設計書.md` §6「画面遷移の業務文脈」が既に持つ遷移元・遷移先・契機の3列だけから矢印を組み立てられた。確信度の欄は設計文書へ新設せず、値は空のまま（捏造しない）とし、表示に使われないことを実描画で確認した |

`--build-manifests-from-docs` でも導けない項目が残る場合は、上記の `--pre-build` / `--post-build` を使って実行側のスクリプトで補う。関連図3種（状態遷移図・ER図・画面遷移図）はいずれも取り込み済みのため、この受け口で補う必要はない。

### 単位フォルダだけを配布する

非画面6種別（API・テーブル・バッチ・帳票・外部連携・機能）は、通常の生成に `--standalone` を加えると、各単位フォルダだけで配布できる形へ整える。`--portal-only` とは同時に指定できない。

```bash
bash generation-engine/scripts/build-portal.sh <target_repo_path> <output_dir> <portal_output_dir> --standalone
```

同梱物を定めるファイルは `delivery-payload/references/design-unit-layout.json` である。
このファイルを正とする。
各Markdownと同じ階層に、拡張子だけを `.html` に変えたHTMLを含める。

| 種別 | 基本 | 詳細 | 通常テスト・単体テスト |
|---|---|---|---|
| API | `API基本設計書` | `API詳細設計書` | `APIテスト設計書`・`API単体テスト設計書` |
| テーブル | `論理データモデル` | `テーブル定義書` | `テーブルテスト設計書`・`テーブル単体テスト設計書` |
| バッチ | `バッチ基本設計書` | `バッチ詳細設計書` | `バッチテスト設計書`・`バッチ単体テスト設計書` |
| 帳票 | `帳票基本設計書` | `帳票詳細設計書` | `帳票テスト設計書`・`帳票単体テスト設計書` |
| 外部連携 | `外部連携基本設計書` | `外部連携詳細設計書` | `外部連携テスト設計書`・`外部連携単体テスト設計書` |
| 機能 | `機能設計書` | なし | `機能テスト設計書`・`機能単体テスト設計書` |

表内の文書名はすべて `.md` と `.html` の組を表す。
機能は定義ファイルの `detail=[]` に従い、詳細文書を要求しない。
また、必須文書の少なくとも1つに、MarkdownまたはHTMLの見出しとして「要確認事項」を置く。
本文中に語句があるだけでは、確認事項の記録にならない。

生成後、または配布前の検査は次で実行する。
検査は、必須文書の不足、ポータルへ戻る導線、単位外参照、単位内のリンク切れを不合格にする。
HTTPなどのスキームを持つURLと `#` で始まるページ内リンクは、ローカルファイルリンクの検査対象外である。

```bash
node generation-engine/scripts/prepare-standalone-units.mjs --prepare <output_dir>
node generation-engine/scripts/prepare-standalone-units.mjs --verify <output_dir>
node generation-engine/scripts/prepare-standalone-units.mjs --self-test
```

## 設計原則

- **完全仲介方式**: 指揮役と子スキルは契約書（contract.md）だけで繋がる。子スキルは契約書自体を読まず args だけで動き、子スキル同士は互いの内部仕様を知らない。`unlocking-reverse-target-screens` は単独経路（`standalone`）では開通から基準タグ確立まで完走する。統括経路（`dynamic-only`）では開通・実測項目補完までを担い、基準確立は後続工程へ委ねる。いずれも開通の事実を知る本スキルに限定した正式仕様である
- **情報アクセス規律の段階的縮小**: extracting は原本コードを読む → authoring は封印済み facts と共通文書のみを読む（原本コードは読まない）→ rebuilding は設計書のみを読む盲検。工程が進むほど参照できる情報を狭め、設計書の自立性を検証する
- **固定と可変の分離**: 決定的スクリプト（`generation-engine/scripts/unit-list/` の共通エンジン等）が固定の処理を担い、プロジェクト・種別ごとの差分は戦略宣言（種別別の検出戦略 reference・抽出プロファイル）に閉じる
- **NG 帰着 3 系統**: 往復検証の判定 FAIL は必ず (a) 執筆規律不足（→執筆規律 reference の改訂）/ (b) facts 欠落（→抽出プロファイルの改訂）/ (c) 共通文書欠落（→共通採録の mode=append 追記）のいずれかに帰着させ、該当資産の改訂へ還元する

## 段階計画

確立済みの範囲と今後の拡張方針。正本は [リバース工程設計.md](delivery-payload/references/リバース工程設計.md) の「段階計画（Cycle 0〜4）」を参照（実装順序の詳細はこのリポジトリ側の計画文書が正本）。各 Cycle の合格条件は既存原則を踏襲する: 異種プロジェクトでスキル無改造成立・決定的出力のみで検収。

| Cycle | 状態 | 内容 |
|---|---|---|
| Cycle 0 | 完了 | 一覧スキル 6 分割・契約明文化・責務確定・README/全体ガイド整備 |
| Cycle 1 | 未着手 | API 縦貫。extracting-unit-facts-from-code の profile=api 追加・facts-schema 拡張 → generating-reverse-detailed-design の API 章マップ → 画面レンダリング比較に代わる検証方式（スキーマ差分・HTTP 応答突合）の設計 |
| Cycle 2 | 未着手 | テーブル・バッチ。テーブルはスキーマ静的比較、バッチは実行契約の facts |
| Cycle 3 | 未着手 | 帳票・外部連携。帳票レイアウト・外部連携契約 |
| Cycle 4 | 一部完了 | 上位抽象化スキル。バッチ・帳票・外部連携の各基本設計書は実装済み。残りは機能要件一覧・帳票要件・バッチ要件・外部連携要件・ビジネス概要の 5 文書（[納品物フォルダ体系.md](delivery-payload/references/納品物フォルダ体系.md) の未実装担当分） |

## 正本文書

| 文書 | 内容 |
|---|---|
| reverse-docs-overview.html（このリポジトリ自身の説明資料。配布対象外） | 全体ガイド（工程フロー図・スキル→成果物対応表・種別×工程の実装状況） |
| 納品物ガイド.html（このリポジトリ自身の説明資料。配布対象外） | 納品物ガイド（何が届いたか・どこから読むか・開発の進め方・規約の効き方） |
| [contract.md](.claude/skills/orchestrating-ai-development-setup/references/contract.md) | 返却ブロック契約・args 仕様・状態判定表の正本 |
| [リバース工程設計.md](delivery-payload/references/リバース工程設計.md) | Phase/Step×スキル対応・NG 帰着 3 系統の正本 |
| [納品物フォルダ体系.md](delivery-payload/references/納品物フォルダ体系.md) | 成果物の置き場（`<output_dir>` 配下構成）の正本 |
| [設計書様式.md](delivery-payload/references/設計書様式.md) | 新規設計とリバース解析で共通する設計書の形・記入手順の定義 |
| スキル実装計画.md（このリポジトリ自身の計画文書。配布対象外） | 実装順序・完了条件・検証想定の正本 |
| [facts-schema.md](delivery-payload/references/facts-schema.md) | facts の共有スキーマ |
| [chapter-map.md](delivery-payload/references/chapter-map.md) | 設計書の章マップ |

## 全体ガイドの整合検証

全体ガイドの表示内容は、ポータルサンプルのカテゴリ・カード名・リンク先と一致させる。工程表は、状態遷移の順序と実行時の並列化（大規模画面の二段パスを含む）を混同しない。変更後は次の検査を実行する。

```bash
bash generation-engine/scripts/tests/check-overview-consistency.sh
bash generation-engine/scripts/tests/check-phase-step-structure.test.sh
```

前者は `generation-engine/samples/index.html` のカテゴリ JSON と全体ガイド（このリポジトリ自身の説明資料）の可視表記を突合する。後者は52個のSkillのPhase/Step構造、26件の operational refs における旧番号・Phase/Step再定義の不在、統括フローのPhase 1〜7 / global Step 1〜41、正本の親Phase対応、条件分岐・Back-edgeメタデータを検査する。失敗時は値を推測して埋めず、正本（サンプル、工程設計、契約、各スキル）へ戻って原因を修正する。なお、実行環境の hook が検査スクリプトを遮断した場合は、成功扱いにせず、遮断理由と未実行の検証を受入記録へ残す。

各スキルの詳解ガイド:

- [指揮役（orchestrating-ai-development-setup）](.claude/skills/orchestrating-ai-development-setup/references/guide.html)
- [アーキテクチャ調査（surveying-architecture-for-reverse-docs）](.claude/skills/surveying-architecture-for-reverse-docs/references/guide.html)
- [画面開通（unlocking-reverse-target-screens）](.claude/skills/unlocking-reverse-target-screens/references/guide.html)
- [環境同期（syncing-reverse-env）](.claude/skills/syncing-reverse-env/references/guide.html)
- [共通採録（generating-reverse-common-docs）](.claude/skills/generating-reverse-common-docs/references/guide.html)
- [facts 抽出（extracting-unit-facts-from-code）](.claude/skills/extracting-unit-facts-from-code/references/guide.html)
- [基本設計書執筆（generating-reverse-basic-design）](.claude/skills/generating-reverse-basic-design/references/guide.html)
- [設計書執筆（generating-reverse-detailed-design）](.claude/skills/generating-reverse-detailed-design/references/guide.html)
- [ファイル単位検証（rebuilding-screen-unit-from-docs）](.claude/skills/rebuilding-screen-unit-from-docs/references/guide.html)
- [画面単位検証（rebuilding-code-from-docs）](.claude/skills/rebuilding-code-from-docs/references/guide.html)
- [画面一覧生成（generating-screen-list-for-reverse-docs）](.claude/skills/generating-screen-list-for-reverse-docs/references/guide.html)
- [API一覧生成（generating-api-list-for-reverse-docs）](.claude/skills/generating-api-list-for-reverse-docs/references/guide.html)
- [テーブル一覧生成（generating-table-list-for-reverse-docs）](.claude/skills/generating-table-list-for-reverse-docs/references/guide.html)
- [バッチ一覧生成（generating-batch-list-for-reverse-docs）](.claude/skills/generating-batch-list-for-reverse-docs/references/guide.html)
- [帳票一覧生成（generating-report-list-for-reverse-docs）](.claude/skills/generating-report-list-for-reverse-docs/references/guide.html)
- [外部連携一覧生成（generating-external-list-for-reverse-docs）](.claude/skills/generating-external-list-for-reverse-docs/references/guide.html)
- [機能一覧生成（generating-feature-list-for-reverse-docs）](.claude/skills/generating-feature-list-for-reverse-docs/references/guide.html)
- [技術スタックページ生成（generating-tech-stack-for-reverse-docs）](.claude/skills/generating-tech-stack-for-reverse-docs/references/guide.html)
- [環境構築手順ページ生成（generating-env-guide-for-reverse-docs）](.claude/skills/generating-env-guide-for-reverse-docs/references/guide.html)
- [画面遷移図生成（generating-screen-transition-for-reverse-docs）](.claude/skills/generating-screen-transition-for-reverse-docs/references/guide.html)
- [ER図生成（generating-er-diagram-for-reverse-docs）](.claude/skills/generating-er-diagram-for-reverse-docs/references/guide.html)
- [用語候補生成互換（generating-glossary-for-reverse-docs）](.claude/skills/generating-glossary-for-reverse-docs/references/guide.html)
- [用語保守（maintaining-semantic-glossary）](.claude/skills/maintaining-semantic-glossary/references/guide.html)
- [用語管理統括（managing-semantic-glossary）](.claude/skills/managing-semantic-glossary/references/guide.html)
- [画面単位リバース検証バッチ（running-reverse-screen-batch）](.claude/skills/running-reverse-screen-batch/references/guide.html)
- [コード行数計測（counting-code-lines）](.claude/skills/counting-code-lines/references/guide.html)
- [ローカル環境調査（surveying-local-environment）](.claude/skills/surveying-local-environment/references/guide.html)
- [コンポーネント棚卸し（generating-component-inventory-for-reverse-docs）](.claude/skills/generating-component-inventory-for-reverse-docs/references/guide.html)
- [横断表生成（generating-cross-views-for-reverse-docs）](.claude/skills/generating-cross-views-for-reverse-docs/references/guide.html)
- [デザインシステム生成（generating-design-system-for-reverse-docs）](.claude/skills/generating-design-system-for-reverse-docs/references/guide.html)
- [状態遷移生成（generating-entity-state-for-reverse-docs）](.claude/skills/generating-entity-state-for-reverse-docs/references/guide.html)
- [アイコンカタログ生成（generating-icon-catalog-for-reverse-docs）](.claude/skills/generating-icon-catalog-for-reverse-docs/references/guide.html)
- [メッセージ一覧生成（generating-message-list-for-reverse-docs）](.claude/skills/generating-message-list-for-reverse-docs/references/guide.html)
- [リリースノート生成（generating-release-notes-for-reverse-docs）](.claude/skills/generating-release-notes-for-reverse-docs/references/guide.html)
- [シーケンス図生成（generating-sequence-diagram-for-reverse-docs）](.claude/skills/generating-sequence-diagram-for-reverse-docs/references/guide.html)
- [テスト観点表生成（generating-test-viewpoint-list-for-reverse-docs）](.claude/skills/generating-test-viewpoint-list-for-reverse-docs/references/guide.html)
- [AGENTS/CLAUDE索引生成（generating-agent-config-index-from-repo）](.claude/skills/generating-agent-config-index-from-repo/references/guide.html)
