# reverse-docs-skills

既存コードから設計書をリバース生成し、その設計書だけからコードを再生成して原本と一致するまで往復検証するスキル群の正本リポジトリ。

## 概要

このリポジトリは、指揮役スキル 1 つと子スキル 22 個（一覧生成 6 + 機能一覧 1 + 基盤ページ生成 5 + 工程 10）で構成される。既存コードベースを走査して一覧・共通文書・詳細設計書を積み上げ、最後に「設計書だけからコードを再生成し、原本と機械突合する」往復検証で設計書の品質を保証する。再生成コードが原本と一致しなければ設計書のどこかに欠落がある、という考え方により、設計書の完成度を主観ではなく機械判定（画面描画・内容・ARIA・画素差分・console・操作の各一致）で確定させる。

## 成果物の最終形

すべての成果物は設計書リポジトリの `<docs_root>` 配下に積み上がる。最終形の要約は次のとおり（全量は [納品物フォルダ体系.md](shared/references/納品物フォルダ体系.md) を参照）。

```
<docs_root>/
├── 一覧/                  # 種別ごとの目録（画面一覧.html 等6種 + 機能一覧（派生）） + excluded-kinds.json + 画面レジストリ
├── プロジェクト共通/      # アーキテクチャ調査書 + 規約4種 + 共通設計書 + メッセージ定義書 + DESIGN.md
├── 画面/screen-<ID>/      # 詳細設計（画面詳細設計書.md・original.png・rebuilt.png 等）+ 基本設計 + テスト項目書
└── API/ テーブル/ バッチ/ 帳票/ 外部連携/   # 各種別の詳細設計置き場（現時点は一覧確立まで）
```

検証記録（facts・往復検証の証跡）は納品物ではないため `docs_root` の外に配置する。`docs_root` と同階層の `verification/` フォルダに移動した（詳細は [納品物フォルダ体系.md](shared/references/納品物フォルダ体系.md) を参照）。

スキルを 1 つ実行するごとに増える成果物の対応（標準の実行順）:

| 実行順のスキル | `<docs_root>` に増える成果物 |
|---|---|
| surveying-architecture-for-reverse-docs | `プロジェクト共通/アーキテクチャ調査書.md`（機械検証済み） |
| generating-<種別>-list-for-reverse-docs（実在種別ごと） | `一覧/<種別>一覧/<種別>一覧.html`。全種別確定後に指揮役が `一覧/excluded-kinds.json` を書き出す |
| unlocking-reverse-target-screens | `一覧/reverse-screen-registry.yml` への記帳と、対象コード側の基準タグ（`reverse-baseline/<scope>`） |
| generating-reverse-common-docs | `プロジェクト共通/` の 7 文書 v0（規約 4 種・共通設計書・メッセージ定義書・DESIGN.md） |
| extracting-unit-facts-from-code | `verification/screen-<ID>/facts/<run_id>/`（facts 一式 + 封印 facts.lock） |
| generating-reverse-basic-design | `画面/screen-<ID>/基本設計/画面基本設計書.md` |
| generating-reverse-detailed-design | `画面/screen-<ID>/詳細設計/画面詳細設計書.md`・`DESIGN.md`・`original.png`（画面キャプチャ） |
| rebuilding-screen-unit-from-docs | `verification/screen-<ID>/単体-<対象ファイル>/` の検証記録と `テスト項目書/テストコード/単体/` の最終テストコード |
| rebuilding-code-from-docs + syncing-reverse-env | `verification/screen-<ID>/<timestamp>/修正指示書.md`・`最終報告.md`、判定 PASS 時は基準タグの本番更新と `詳細設計/rebuilt.png`（画面キャプチャ）の更新 |

## スキル一覧

指揮役 1 + 一覧生成 6 + 機能一覧 1 + 基盤ページ生成 5 + 工程 10 の計 23 スキル。

| スキル名 | 役割 | 主成果物 |
|---|---|---|
| orchestrating-reverse-docs-flow | 指揮役。状態判定から次工程の子スキルを機械的に起動する | excluded-kinds.json・画面レジストリの管理 |
| generating-screen-list-for-reverse-docs | 画面の一覧生成 | 画面一覧.html |
| generating-api-list-for-reverse-docs | API の一覧生成 | API一覧.html |
| generating-table-list-for-reverse-docs | テーブルの一覧生成 | テーブル一覧.html |
| generating-batch-list-for-reverse-docs | バッチの一覧生成 | バッチ一覧.html |
| generating-report-list-for-reverse-docs | 帳票の一覧生成 | 帳票一覧.html |
| generating-external-list-for-reverse-docs | 外部連携の一覧生成 | 外部連携一覧.html |
| generating-feature-list-for-reverse-docs | 既存一覧を業務機能単位でグルーピングした派生一覧を生成 | 機能一覧.html |
| generating-tech-stack-for-reverse-docs | 調査書と定義ファイルの実測突合から技術スタックページを生成 | 技術スタック.html |
| generating-env-guide-for-reverse-docs | 調査書とローカル環境調査結果から環境実行手順ページを生成 | 環境実行手順.html |
| generating-screen-transition-for-reverse-docs | 画面一覧マニフェストとルーティング定義から画面遷移図を生成 | 画面遷移図.html |
| generating-er-diagram-for-reverse-docs | テーブル一覧マニフェストと FK 定義から ER 図を生成 | ER図.html |
| generating-glossary-for-reverse-docs | 層化サンプリングによる採録から用語辞書ページを生成 | 用語辞書.html |
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

## 種別×工程の対応表

6 種別 × 4 工程の対応状況。画面のみ全工程が確立済みで、他 5 種別は一覧生成まで対応済み（facts 抽出以降は「[段階計画](#段階計画)」の対象）。

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

Phase 0（ヒアリング）で対象パス・出力先・画面スコープを確定後、以下の状態機械で進行する。Phase 1B では 6 一覧を Agent 並列実行し、Phase 4C では画面数 4 件以上の場合に running-reverse-screen-batch で無人バッチ実行する。基本設計と詳細設計は facts 封印後に並列著述する。

指揮役は成果物の実在から現在の状態を判定し（11 状態）、次に起動する子スキルを機械的に決める。判定は次の順に降りる決定木で行う。

```
アーキ未調査 → 一覧未生成 → 共通未採録 → 画面未開通 → 事実未封印 → 基本設計未著述
  → 設計書未著述 → ファイル単位未検証（任意工程） → 基準未確立
  → 往復未検証 → 検証完了
```

工程順の要約:

```
アーキ調査 ─→ 一覧生成（実在種別ごと） ─→ 画面開通・基準タグ確立 ─→ 共通採録 v0
                                                                        │
     ┌──────────────────────────────────────────────────────────────────┘
     ▼
facts 抽出・封印 ─→ 基本設計 ‖ 詳細設計（並列） ─→（任意）ファイル単位検証
     ─→ 往復検証（再実装 → 環境比較 → 判定） ─→ PASS: 基準タグ更新
                                              └─→ FAIL: NG 帰着 3 系統へ差し戻し
```

状態判定表・返却ブロック契約の正本は [contract.md](.claude/skills/orchestrating-reverse-docs-flow/references/contract.md)、Phase/Step とスキルの対応は [リバース工程設計.md](shared/references/リバース工程設計.md) を参照。全体ガイドは [reverse-docs-overview.html](reverse-docs-overview.html) を参照。

## 使い方

### (a) 指揮役から起動する（推奨）

`orchestrating-reverse-docs-flow` を起動すると、成果物の実在から現在の状態を判定し、必要な工程だけを自動で続行する。人間の介在点はスコープ確認（Phase 1）と白紙化承認（user-approved）のみ。

```
Skill(orchestrating-reverse-docs-flow)
```

### (b) 子スキルを単独起動する

各子スキルは指揮役が渡すのと同じ引数（args）をユーザーが手渡しすれば単独で動く。引数の全量は [contract.md](.claude/skills/orchestrating-reverse-docs-flow/references/contract.md) の「args 仕様」を参照。

```
例: extracting-unit-facts-from-code に
    target_repo_path / target_file_paths / screen_dir / profile=screen / survey_doc_path を手渡し
```

## 設計原則

- **完全仲介方式**: 指揮役と子スキルは契約書（contract.md）だけで繋がる。子スキルは契約書自体を読まず args だけで動き、子スキル同士は互いの内部仕様を知らない。`unlocking-reverse-target-screens` は開通から基準タグ確立まで単独で完走するが、これは完全仲介方式の例外ではなく、開通の事実を知るのが本スキルだけであることに基づく意図した正式仕様である
- **情報アクセス規律の段階的縮小**: extracting は原本コードを読む → authoring は封印済み facts と共通文書のみを読む（原本コードは読まない）→ rebuilding は設計書のみを読む盲検。工程が進むほど参照できる情報を狭め、設計書の自立性を検証する
- **固定と可変の分離**: 決定的スクリプト（`shared/scripts/unit-list/` の共通エンジン等）が固定の処理を担い、プロジェクト・種別ごとの差分は戦略宣言（種別別の検出戦略 reference・抽出プロファイル）に閉じる
- **NG 帰着 3 系統**: 往復検証の判定 FAIL は必ず (a) 執筆規律不足（→執筆規律 reference の改訂）/ (b) facts 欠落（→抽出プロファイルの改訂）/ (c) 共通文書欠落（→共通採録の mode=append 追記）のいずれかに帰着させ、該当資産の改訂へ還元する

## 段階計画

確立済みの範囲と今後の拡張方針。正本は [リバース工程設計.md](shared/references/リバース工程設計.md) の「段階計画（Cycle 0〜4）」、実装順序の正本は [スキル実装計画.md](shared/references/スキル実装計画.md) を参照。各 Cycle の合格条件は既存原則を踏襲する: 異種プロジェクトでスキル無改造成立・決定的出力のみで検収。

| Cycle | 状態 | 内容 |
|---|---|---|
| Cycle 0 | 完了 | 一覧スキル 6 分割・契約明文化・責務確定・README/全体ガイド整備 |
| Cycle 1 | 未着手 | API 縦貫。extracting-unit-facts-from-code の profile=api 追加・facts-schema 拡張 → generating-reverse-detailed-design の API 章マップ → 画面レンダリング比較に代わる検証方式（スキーマ差分・HTTP 応答突合）の設計 |
| Cycle 2 | 未着手 | テーブル・バッチ。テーブルはスキーマ静的比較、バッチは実行契約の facts |
| Cycle 3 | 未着手 | 帳票・外部連携。帳票レイアウト・外部連携契約 |
| Cycle 4 | 未着手 | 上位抽象化スキル。基本設計・要件定義文書群（[納品物フォルダ体系.md](shared/references/納品物フォルダ体系.md) の未実装担当分） |

## 正本文書

| 文書 | 内容 |
|---|---|
| [reverse-docs-overview.html](reverse-docs-overview.html) | 全体ガイド（工程フロー図・スキル→成果物対応表・種別×工程の実装状況） |
| [contract.md](.claude/skills/orchestrating-reverse-docs-flow/references/contract.md) | 返却ブロック契約・args 仕様・状態判定表の正本 |
| [リバース工程設計.md](shared/references/リバース工程設計.md) | Phase/Step×スキル対応・NG 帰着 3 系統の正本 |
| [納品物フォルダ体系.md](shared/references/納品物フォルダ体系.md) | 成果物の置き場（`<docs_root>` 配下構成）の正本 |
| [スキル実装計画.md](shared/references/スキル実装計画.md) | 実装順序・完了条件・検証想定の正本 |
| [facts-schema.md](shared/references/facts-schema.md) | facts の共有スキーマ |
| [chapter-map.md](shared/references/chapter-map.md) | 設計書の章マップ |

各スキルの詳解ガイド:

- [指揮役（orchestrating-reverse-docs-flow）](.claude/skills/orchestrating-reverse-docs-flow/references/orchestrating-reverse-docs-flow-guide.html)
- [アーキテクチャ調査（surveying-architecture-for-reverse-docs）](.claude/skills/surveying-architecture-for-reverse-docs/references/surveying-architecture-for-reverse-docs-guide.html)
- [画面開通（unlocking-reverse-target-screens）](.claude/skills/unlocking-reverse-target-screens/references/unlocking-reverse-target-screens-guide.html)
- [環境同期（syncing-reverse-env）](.claude/skills/syncing-reverse-env/references/syncing-reverse-env-guide.html)
- [共通採録（generating-reverse-common-docs）](.claude/skills/generating-reverse-common-docs/references/generating-reverse-common-docs-guide.html)
- [facts 抽出（extracting-unit-facts-from-code）](.claude/skills/extracting-unit-facts-from-code/references/extracting-unit-facts-from-code-guide.html)
- [基本設計書執筆（generating-reverse-basic-design）](.claude/skills/generating-reverse-basic-design/references/generating-reverse-basic-design-guide.html)
- [設計書執筆（generating-reverse-detailed-design）](.claude/skills/generating-reverse-detailed-design/references/generating-reverse-detailed-design-guide.html)
- [ファイル単位検証（rebuilding-screen-unit-from-docs）](.claude/skills/rebuilding-screen-unit-from-docs/references/rebuilding-screen-unit-from-docs-guide.html)
- [画面単位検証（rebuilding-code-from-docs）](.claude/skills/rebuilding-code-from-docs/references/rebuilding-code-from-docs-guide.html)
- [画面一覧生成（generating-screen-list-for-reverse-docs）](.claude/skills/generating-screen-list-for-reverse-docs/references/generating-screen-list-for-reverse-docs-guide.html)
- [API一覧生成（generating-api-list-for-reverse-docs）](.claude/skills/generating-api-list-for-reverse-docs/references/generating-api-list-for-reverse-docs-guide.html)
- [テーブル一覧生成（generating-table-list-for-reverse-docs）](.claude/skills/generating-table-list-for-reverse-docs/references/generating-table-list-for-reverse-docs-guide.html)
- [バッチ一覧生成（generating-batch-list-for-reverse-docs）](.claude/skills/generating-batch-list-for-reverse-docs/references/generating-batch-list-for-reverse-docs-guide.html)
- [帳票一覧生成（generating-report-list-for-reverse-docs）](.claude/skills/generating-report-list-for-reverse-docs/references/generating-report-list-for-reverse-docs-guide.html)
- [外部連携一覧生成（generating-external-list-for-reverse-docs）](.claude/skills/generating-external-list-for-reverse-docs/references/generating-external-list-for-reverse-docs-guide.html)
- [機能一覧生成（generating-feature-list-for-reverse-docs）](.claude/skills/generating-feature-list-for-reverse-docs/references/generating-feature-list-for-reverse-docs-guide.html)
- [技術スタックページ生成（generating-tech-stack-for-reverse-docs）](.claude/skills/generating-tech-stack-for-reverse-docs/references/generating-tech-stack-for-reverse-docs-guide.html)
- [環境実行手順ページ生成（generating-env-guide-for-reverse-docs）](.claude/skills/generating-env-guide-for-reverse-docs/references/generating-env-guide-for-reverse-docs-guide.html)
- [画面遷移図生成（generating-screen-transition-for-reverse-docs）](.claude/skills/generating-screen-transition-for-reverse-docs/references/generating-screen-transition-for-reverse-docs-guide.html)
- [ER図生成（generating-er-diagram-for-reverse-docs）](.claude/skills/generating-er-diagram-for-reverse-docs/references/generating-er-diagram-for-reverse-docs-guide.html)
- [用語辞書ページ生成（generating-glossary-for-reverse-docs）](.claude/skills/generating-glossary-for-reverse-docs/references/generating-glossary-for-reverse-docs-guide.html)
- [画面単位リバース検証バッチ（running-reverse-screen-batch）](.claude/skills/running-reverse-screen-batch/references/running-reverse-screen-batch-guide.html)
- [コード行数計測（counting-code-lines）](.claude/skills/counting-code-lines/references/counting-code-lines-guide.html)
- [ローカル環境調査（surveying-local-environment）](.claude/skills/surveying-local-environment/references/surveying-local-environment-guide.html)
