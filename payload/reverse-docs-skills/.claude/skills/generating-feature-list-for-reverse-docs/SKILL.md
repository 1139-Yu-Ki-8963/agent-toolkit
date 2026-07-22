---
name: generating-feature-list-for-reverse-docs
description: "機能一覧フォルダ・機能一覧HTML生成(unit_kind=feature 専用・派生一覧)。 TRIGGER when: 機能一覧作成、機能一覧生成、業務機能の横断目録。 SKIP: 種別別の技術一覧(→対応する種別別一覧スキル)、往復検証/同期/実装。"
invocation: generating-feature-list-for-reverse-docs
type: transform
allowed-tools: [Bash, Read, Write, Edit, Grep, Glob, AskUserQuestion, TaskCreate, TaskUpdate]
---

# 機能一覧生成スキル(派生一覧)

工程全体は orchestrating-reverse-docs-flow が案内する。本スキルは機能一覧の生成のみを担い、単独起動できる(起動引数 source_dir・output_dir の 2 つを渡せば動く)。`unit_kind` は **feature 固定** であり、引数では受け取らない。

既存の種別別一覧(画面一覧は必須、API・テーブル等の一覧は任意)を入力として、業務機能の単位(2階層: 大分類 + 機能)に画面・APIをグルーピングして **機能一覧.html** を作成する。**本スキルの仕事は機能一覧.html の作成のみ** であり、設計書の雛形展開・生成・記入は一切行わない。

機能は「コードから直接検出するユニット」ではなく **既存一覧の派生グルーピング(派生一覧)** である。アーキテクチャ調査の存在判定(unit_kinds_present)の対象にならず(機能は常に存在する)、excluded-kinds.json の allKinds にも含めない。

## 設計原則: 固定と可変の分離

マニフェストスキーマ・整合検証(`validate-manifest.sh`)・HTML生成(`build-unit-list.sh` → `build-feature-list.sh`)は決定的スクリプトに固定する。グルーピング(大分類境界の決定・機能分割・関連付け)はプロジェクトごとに可変である。

feature 種別に組み込み検出器はない。抽出は **カスタム抽出パスのみ**: Claude 自身が `references/feature-detection.md`(グルーピング規約の正本)に沿って解析を実行し、スキーマ準拠のマニフェスト JSON(配列キーは `units`)を出力する。機械処理は Phase 5 の検証と生成のみ。

## エンジンスクリプトの参照

エンジンスクリプトは本スキルフォルダからの相対パスで参照する。

- 整合検証: `../../../shared/scripts/unit-list/validate-manifest.sh`
- HTML生成: `../../../shared/scripts/unit-list/build-unit-list.sh`(unit_kind=feature を内部で `build-feature-list.sh` に委譲する)

正本リポジトリと公開先(payload)はディレクトリレイアウトが同一のため、この相対参照は両環境でそのまま成立する。

## 使用タイミング

- 既存コードベースの機能一覧(業務機能の横断目録)を作りたいとき
- 前提: 画面一覧(`<output_dir>/一覧/画面一覧/画面一覧.html`)が生成済みであること
- 起動引数: `source_dir`(ソースコードディレクトリ)・`output_dir`(一覧の出力先。既存6種と同じ)・`survey_doc_path`(任意。アーキテクチャ調査書。ルート定義等の所在特定の参考)

## 出力

| 項目 | 値 |
|---|---|
| 出力フォルダ | `<output_dir>/一覧/機能一覧/` |
| 出力ファイル | `機能一覧.html` |
| マニフェスト配列キー | `units` |

## 進捗管理(必須手順)

スキル開始時に `TaskCreate` で Phase 1〜6 のタスクを登録する。各 Phase 開始時に該当タスクを `in_progress` に、完了時に `completed` へ `TaskUpdate` で更新する。Phase 5 から Phase 2〜4 へ差し戻す場合は該当タスクを `in_progress` に戻す。実行環境に TaskCreate/TaskUpdate が存在しない場合は、出力先ディレクトリ内のタスク台帳ファイル(`task-ledger.md`)で同等の Phase 遷移記録を代替する。

## 動作フロー(Phase 1〜6)

グルーピング規約の詳細は `references/feature-detection.md` を参照する。

### Phase 1: 入力収集

- **Step 1**: `<output_dir>/一覧/` 配下に実在する一覧HTMLを機械的に列挙し、各HTML内の埋め込みマニフェスト(画面一覧は `<script type="application/json" id="screen-manifest">`、他種別は `id="unit-manifest"`)から JSON を抽出する。**画面一覧は必須**。不在なら status=ERROR で停止し、hint に「先に generating-screen-list-for-reverse-docs を実行」と記録する。実在した一覧のパスをすべて `strategy.inputManifests` に記録する(ユーザー指示は不要)。完了条件: 画面一覧マニフェストが抽出済みで、inputManifests が確定している
- **Step 2**: `source_dir` からルート定義・ナビメニュー・バックエンドルーターの prefix/tags・ディレクトリ構造を Grep/Read で特定する。survey_doc_path があれば所在特定の参考にする。完了条件: 手がかり①〜④(feature-detection.md の優先度表)の抽出元ファイルが列挙済み

### Phase 2: 大分類候補の導出

- **Step 1**: ルートprefix第1セグメント(手がかり①)で大分類の境界を引く。ナビメニュー・設定ハブの表示文言(手がかり②)は名前付けのみに使い、境界の決定には使わない。完了条件: 候補表(大分類キー・根拠・所属画面数)が作成済み
- **Step 2**: APIプレフィックス/tags(③)・ディレクトリ構造(④)で裏取りし、競合があれば feature-detection.md の競合解決フローに従う。完了条件: 全画面が大分類候補に割当済み、または割当根拠ゼロとして unresolved 候補に分類済み
- **Step 3**: 大分類が細分化しすぎる場合(機能1件のみの大分類が過半、または大分類数が10超)、`references/feature-detection.md` の「大分類の統合規則」に従い上位の業務領域へ統合する。境界(機能の分割)は変えない。完了条件: 大分類数が目安(5〜10)に収まっている、または収まらない理由が記録済み

### Phase 3: 画面→機能グルーピング + 完全性ゲート(Stage 1)

- **Step 1**: 大分類内で画面群を機能単位(同一業務対象への操作一式。CRUD集約)に分割する。完了条件: グルーピングが完了し各画面に機能が割り当てられている
- **Step 2(完全性ゲート)**: 画面一覧の全 screenKey が「いずれかの機能の relatedScreens」または「unresolved 行」に載っているかを機械検査する。未割当が1件でもあれば Step 1 へ差し戻す

```bash
# 未割当の screenKey を検出(空なら PASS、非空なら Step 1 へ差し戻し)
comm -13 \
  <(jq -r '.units[] | .relatedScreens[]?' feature-manifest.json | sort -u) \
  <(jq -r '.screens[].screenKey' screen-manifest.json | sort -u)
```

- **Step 3**: スキーマ準拠のマニフェスト JSON を一時ディレクトリ(`$CLAUDE_JOB_DIR/tmp/feature-manifest.json`、未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下)に Write する。この時点で `relatedApis`・`relatedTables` は空配列とする。機能を捏造しない。完了条件: マニフェスト JSON が生成済みで完全性ゲート PASS

### Phase 4: API紐付け + テーブル紐付け(Stage 2 + Stage 3)

Phase 1 で特定したプロジェクト固有の API 呼び出しパターンと ORM/モデル参照パターンを使い、構造化された手順で related* を埋める。手順の詳細は `references/feature-detection.md` の「Stage 2: API紐付け手順」「Stage 3: テーブル紐付け手順」を参照する。

- **Step 1(Stage 2: API紐付け)**: 各機能の relatedScreens に含まれる画面について、画面マニフェストの `files[]`(なければ `entryFile` にフォールバック)から API 呼び出しパターンを grep し、API一覧マニフェストの `units[].identifier` に照合する。一致した `unitKey` を当該機能の `relatedApis` に記録する。照合できない endpoint は残余リストに記録し、パスパラメータ差異等の曖昧一致のみ Claude が裁定する(推測禁止)。完了条件: 全機能の relatedApis が確定済み(空配列を含む)
- **Step 2(Stage 3: テーブル紐付け)**: Step 1 で紐付いた API unitKey について、API一覧マニフェストの `units[].sourceFile` からモデル/テーブル参照を grep し、テーブル一覧マニフェストの `units[].unitKey` に照合する。一致した `unitKey` を当該機能の `relatedTables` に記録する。照合できない参照は残余リストに記録し Claude が裁定する。完了条件: 全機能の relatedTables が確定済み(空配列を含む)
- **Step 3(組み立て)**: Stage 2・Stage 3 の結果をマニフェスト JSON にマージする。各機能の confidence を確定する。完了条件: マニフェスト JSON の relatedApis・relatedTables・confidence が全機能分記録済み

Stage 2 → Stage 3 の実行順はデータ依存(Stage 3 は Stage 2 の出力する API unitKey を入力とする)により固定。ただし各画面・各 API の処理は独立しておりサブエージェント並列委任が可能。API一覧またはテーブル一覧が未生成の場合、該当する related* は空配列のまま PASS とする。

### Phase 5: 戦略・構成のユーザー承認

- **Step 1**: 大分類と機能の構成案(unresolved 行・relatedApis・relatedTables を含む)を AskUserQuestion で提示する。応答は (A) 構成案どおり承認 / (B) 修正指示(大分類・機能の統合/分割・unresolved の割当指示・related* の修正)の2系統で受け、(B) なら該当部分の Phase 2〜4 を再実行して再提示する。承認で `strategy.approvedByUser: true` をマニフェストに記録する。unresolved 行に割当指示がなければ unresolved のまま出力してよい(人間への引き継ぎ事項であり、残置もスキル完了とみなす)。完了条件: approvedByUser: true が記録済み

### Phase 6: 検証とHTML生成(機械実行)

- **Step 1**: マニフェストへメタデータを付与する。`../../../shared/scripts/extract/extract-feature-metadata.sh <manifest.json> <manifest.ext.json>` を実行し、各機能に `operationClass`(照会/登録/更新/削除/承認/その他)フィールドを追加した拡張マニフェスト(`manifest.ext.json`)を生成する。以降の Step では `manifest.ext.json` を使用する。完了条件: 拡張マニフェストが生成済み
- **Step 2**: `../../../shared/scripts/unit-list/validate-manifest.sh <manifest.ext.json> --unit-kind feature` を実行する。FAIL 時は指摘に応じて修正し再実行(3回失敗で Phase 3 へ差し戻し)。完了条件: 全項目 PASS
- **Step 3**: 両方向の参照検査を実行する。いずれかが非空なら該当 Phase へ差し戻す

```bash
# Gate A(既存): dangling reference — relatedScreens の参照先が画面一覧に実在するか
# (relatedApis/relatedTables も対応一覧の units[].unitKey で同型。
# 参照先一覧が未生成の種別は related* が空配列のため自動的に PASS)
comm -23 \
  <(jq -r '.units[] | .relatedScreens[]?' feature-manifest.ext.json | sort -u) \
  <(jq -r '.screens[].screenKey' screen-manifest.json | sort -u)

# Gate B(新設): completeness — 画面一覧の全 screenKey が機能に割り当て済みか
comm -13 \
  <(jq -r '.units[] | .relatedScreens[]?' feature-manifest.ext.json | sort -u) \
  <(jq -r '.screens[].screenKey' screen-manifest.json | sort -u)
# Gate A・B いずれも空 = PASS。1行でも出力があれば FAIL
```

- **Step 4**: `../../../shared/scripts/unit-list/build-unit-list.sh <manifest.ext.json> <output_dir>/一覧/機能一覧/機能一覧.html --unit-kind feature --portal-dir <output_dir>` を実行する。`--portal-dir` にはポータル（`index.html`）の配置先＝納品物ルート（output_dir=docs_root）を渡し、「ポータルへ戻る」リンクを実在パスに解決させる。build 側が内部で validate を再実行するため、検証を経ない manifest からは生成できない。完了条件: HTML 生成済み

**手作業でのプレースホルダ置換は禁止する**。HTML 生成は必ずスクリプト経由の決定的処理で行う。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 画面一覧マニフェスト抽出済み・inputManifests 確定・手がかり①〜④の抽出元が列挙済み・API/テーブル grep パターン特定済み |
| Phase 2 | 候補表が作成済みで全画面が大分類候補または unresolved 候補に分類済み |
| Phase 3 | 全画面が relatedScreens または unresolved に載り(完全性ゲート PASS)、マニフェスト JSON が生成済み(relatedApis/relatedTables は空配列) |
| Phase 4 | 全機能の relatedApis・relatedTables・confidence が確定済み |
| Phase 5 | 構成案がユーザー承認済み(approvedByUser: true) |
| Phase 6 | Step 1で拡張マニフェストに operationClass が付与済み。validate 全項目 PASS・Gate A(dangling) PASS・Gate B(completeness) PASS・機能一覧.html 生成済み |
| **Goal** | 検証済みマニフェストのみから HTML が生成され、大分類ごとの機能と関連画面・API・テーブルの対応、および要手動確認が可視化されている |

## 返却

本スキルは orchestrating-reverse-docs-flow の契約に準拠する。完了時に以下を返す。

- `status`: `DONE | ERROR`
- `artifacts`: 生成した機能一覧.html のパス
- `unit_list_html`: artifacts[0] の汎用名
- `embedded_json_ref`: HTML 内に埋め込んだマニフェスト JSON への参照
- `unit_kind`: `feature`(固定値)

## ツールリファレンス

| ツール | 用途 |
|---|---|
| Bash | `validate-manifest.sh`・`build-unit-list.sh`・jq 自前検査の実行 |
| Read | 既存一覧HTML・ルート定義・ナビ定義・`references/feature-detection.md` の参照 |
| Grep/Glob | ルート定義・APIプレフィックス・ディレクトリ構造の調査、データ取得コードの追跡 |
| Write | マニフェスト JSON の出力(機能一覧.html 本体はスクリプト経由で生成) |
| AskUserQuestion | Phase 4 の構成案承認 |
| TaskCreate/TaskUpdate | Phase 1〜5 の進捗管理 |

## 推奨手順

- source_dir は対象プロジェクトの実コードルートを指定する。モノレポの場合はフロントエンド・バックエンド両方を含む親ディレクトリを渡してよい(ルート定義とAPIルーターの両方を読むため)
- 大分類の期待数は 5〜10、機能は画面 1〜5 枚につき 1 件が目安。画面数と極端に乖離した場合は分割規約の適用を見直す
- 対象プロジェクトに人手の機能一覧・設計書目録(`docs/` 配下等)が既にある場合は、Phase 4 の承認前にその目録と突合し、大きな乖離を notes に記録する

## 重要な注意事項

- 設計書の雛形展開・生成・記入は一切行わない。本スキルの成果物は機能一覧.html のみ
- Phase 5 の HTML 手作業組み立てを禁止する。`build-unit-list.sh` を必ず経由する
- 機能・大分類を捏造しない。すべての割当に手がかり①〜④いずれかの根拠を持たせ、根拠ゼロは unresolved とする
- related* を推測で埋めない。突合で解決できないものは空のままとする
- 画面一覧が空(screens が 0 件)の場合はハード停止しユーザーに報告する。手動リストを聞き出さない

## 予想を裏切る挙動

- `validate-manifest.sh`・`build-unit-list.sh` は jq に依存する。未インストール環境では事前に導入する
- 大分類の境界はルートprefix(手がかり①)のみで引く。ナビメニューが境界を示唆しても境界には使わない(ナビは全機能を網羅しないため。命名のみに使う)。なお境界を保ったまま大分類名を上位業務領域へ統合することは統合規則(feature-detection.md)で許可されている
- unresolved が残った状態も status=DONE で完了とする(既存6種の「要手動確認」と同じ扱い。ERROR ではない)
- validate-manifest.sh は related* の参照実在を検査しない(参照整合検査は screen 専用)。Phase 5 Step 2 の jq 自前検査を省略すると不在参照が成果物に混入する
- detectionSummary.unitCount は units 配列の全要素数(unresolved 含む)。機能数として報告する場合は kind=feature 行のみを数える
- マニフェストの配列キーは `screens` ではなく `units` とする
- 出力先は `<output_dir>/一覧/機能一覧/機能一覧.html`。他種別と独立したフォルダを作成する
- ルート定義に載らない画面(認証ガード内で条件レンダリングされるログイン画面等)は前段の画面一覧の抽出品質に依存する。画面一覧に無い画面は本スキルでは補完しない(画面一覧側の再生成で対処する)

## 完了報告

`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（作業報告型）に従う。

固有の検証行:
- validate 全項目 PASS・related 参照実在検査 PASS・機能一覧.html の生成成功

## 設計判断

### build-feature-list.sh / feature-list-template.html

**必要性**: 機能一覧は関連画面・関連API・関連テーブルの3列と大分類ごとのセクション分割を持ち、汎用テンプレート(unit-list-template.html・9列固定)に収まらない。既存方針(手作業プレースホルダ置換の禁止・決定的生成)に従い、screen と同じ「専用ビルダー + 専用テンプレート」方式で `build-feature-list.sh` と `feature-list-template.html` に生成処理を固定する。`--self-test` は render_template の単一パス置換がマーカー衝突・バックスラッシュを含む値でも誤爆しないことを回帰検証する。

**代替案を採用しなかった理由**:
- 汎用 `build-unit-list.sh` の列拡張: 列構成とグルーピングが feature 固有であり、全種別共通テンプレートに条件分岐を持ち込むと他5種別の生成に回帰リスクを生む。screen の前例(専用ビルダー分離)に合わせた
- Bash ツール直叩き(Claude が都度プレースホルダ置換): 手作業組み立てによるデータ混入(entryFile=None 等)の実害が過去に発生しており、決定的スクリプト固定が確立済みの再発防止策
- 既存 Makefile ターゲット拡張・package.json scripts 追加: 本リポジトリに Makefile・package.json は存在しない

**保守責任者**: 人手(ユーザー)。マニフェストスキーマ変更時に validate-manifest.sh との整合を同時更新する

**廃棄条件**: generating-feature-list-for-reverse-docs スキルが廃止された時、またはHTML生成が別基盤へ移行した時

### extract-feature-metadata.sh

**必要性**: 機能一覧の各ユニットへ `operationClass`(照会/登録/更新/削除/承認/その他の6値)を付与する処理は、Phase 6 で毎回同じキーワード判定ロジック(優先順を持つ複数カテゴリのキーワード集合との突合)を繰り返し適用する必要があり、Bash ツール直叩きでは判定ロジックが都度手書きになり判定基準がユニット間・実行間でぶれる。他5種別(`extract-batch-metadata.sh` 等)と同じ「決定的スクリプト固定」方針に揃え、`--self-test` で分類ロジックの回帰(6カテゴリ全ての判定・キーワード不一致時の「その他」フォールバック・既存フィールド不変・validate-manifest.sh PASS)を機械保証する。

**代替案を採用しなかった理由**:
- Bash ツール直叩き(Claude が都度キーワード判定): 実行のたびに判定基準が微妙にぶれるリスクがあり、他5種別で確立した「抽出は決定的スクリプト」の方針から逸脱する
- 既存 Makefile ターゲット拡張・package.json scripts 追加: 本リポジトリに Makefile・package.json は存在しない
- `build-feature-list.sh` への処理統合: `build-feature-list.sh` は HTML 生成(検証済み manifest からの決定的変換)を担い、メタデータ抽出(manifest 自体の拡張)とは責務が異なる。他種別の `extract-*-metadata.sh` と `build-unit-list.sh` の分離方針に合わせた

**保守責任者**: 人手(ユーザー)。キーワード集合・優先順を変更する場合は `shared/references/manifest-schema-extensions.md`「features」節の値域定義と `shared/templates/unit-list/feature-list-template.html` のバッジ色分けを同時更新する

**廃棄条件**: `operationClass` フィールドがスキーマから廃止された時、または分類ロジックが機械抽出ではなく人手判定に一本化された時
