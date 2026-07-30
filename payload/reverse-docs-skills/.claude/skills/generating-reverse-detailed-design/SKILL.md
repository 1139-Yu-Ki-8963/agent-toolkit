---
name: generating-reverse-detailed-design
description: "封印済みfactsと共通文書から画面詳細設計書を執筆する執筆役。 TRIGGER when: facts封印後の設計書執筆・再執筆。 SKIP: facts抽出（→extracting-unit-facts-from-code）、盲検検証（→rebuilding-screen-unit-from-docs）。"
invocation: generating-reverse-detailed-design
type: orchestration
allowed-tools: [Agent, Bash, Read, Write, Edit]
---

# 封印済みfactsからのリバース設計書執筆スキル

封印済み facts（facts.yml）とプロジェクト共通文書だけを情報源に、リバース設計書（画面詳細設計書・DESIGN.md・単体テスト観点表）を著述する執筆専任スキル。原本コードの読解は上流スキル extracting-unit-facts-from-code が担い、本スキルはその成果物（facts_ref）を受け取って書くだけの役割に限定する。**本スキル実行中に対象リポジトリの原本コードを Read することは全面禁止**（検証の盲検性を壊す契約違反）である。

執筆は「宣言的契約への正規化」であり、facts.yml の `value` をそのまま書き写すだけでなく、章の文脈に沿って要約・整形する。ただし facts に無い事実を創作することも禁止する（境界例は `references/writing-rules.md`）。

## 目的

facts 抽出・設計書執筆・盲検検証の3スキルは情報アクセス規律がそれぞれ異なる。**原本を読むのは抽出役（extracting-unit-facts-from-code）だけ**であり、執筆役（本スキル）と検証役（rebuilding-screen-unit-from-docs）はどちらも原本を読まない。両者の違いは、執筆役が封印済み facts という確定情報を読める点にある（検証役は設計書のみから再現する）。本スキルを独立させることで、「執筆役が原本を読んで穴埋めする」事故（facts の欠落を勝手に推測で埋めてしまい、盲検検証の意味が失われる事故）を構造的に防ぐ。

## 使用タイミング

- facts が封印済み（extracting-unit-facts-from-code が `status=封印済み` で facts_ref を返した後）で、リバース設計書を新規著述・再著述したいとき
- 本スキルが `status=AUTHORED` を返した後に検証スキル rebuilding-screen-unit-from-docs を起動する（facts抽出 → 執筆 → 盲検往復検証の順）
- 検証スキルが `差し戻し`（設計書に対象契約なし）を返した場合の差し戻し先は本スキルである
- 起動引数は screen_dir + facts_ref + common_docs_root + 資産パス群 + mode（+ mode=file 時は target_file_path）

## スコープ（2 モード）

- **mode=file**: 1 起動 = 1 ファイル。対象ファイルの宣言的契約を該当章へ著述する
- **mode=screen**: 画面横断章（§1 画面概要・§2 機能一覧・§4 業務ルール・§12 画面遷移・§13 非機能要件・§14 共通仕様準拠）と画面構成の統合（§3 画面構造・§9 領域別仕様）を著述する。mode=file が**全対象ファイル分完了した後**に実行する

## 設計原則

1. **正本一元化**: facts.yml は封印済みの確定情報であり第二の正本ではない。正は設計書。設計書と facts.yml が食い違ったら設計書を直す（facts.yml 自体の誤りは extracting-unit-facts-from-code への差し戻し対象であり本スキルは書き換えない）
2. **対象外に根拠を必須とする**
   複数の対象外項目は `references/writing-rules.md` の章単位集約書式でまとめる。
   各項目の理由を残し、根拠なしの裸の「未確認」を禁止する
3. **プロジェクト非依存**: リバース対象の固有値（対象リポジトリパス・画面 ID・BL 名）はすべて起動引数・設計書側に置き、本 SKILL.md 本文には書かない。完成後に固有文字列ゼロを確認する（環境名の直書き禁止規約にも整合させる）
4. **原本 Read 禁止**: 本スキル実行中に対象リポジトリの原本コードを Read することを全面禁止する。情報源は起動引数 facts_ref 配下の facts.yml と common_docs_root 配下の共通文書に限定する。原本を読むことは検証の盲検性を壊す契約違反であり、facts の欠落に気づいた場合でも自ら原本を確認せず extracting-unit-facts-from-code への差し戻しとして扱う
5. **検証スキルとの関係を明記**: 上記「使用タイミング」の通り、AUTHORED 後に検証スキルを起動し、検証 差し戻し の差し戻し先は本スキルである

## Phase 1: preflight（起動引数検収・スキャフォールディング）

## Step 1-1: preflight（起動引数検収・スキャフォールディング）

**使用ツール**: Read / Bash / Write / Agent

起動引数を検収する: screen_dir / output_dir / template_root / chapter_map_path / audit_script_path / scaffold_script_path / facts_ref / common_docs_root / mode / target_file_path（mode=file 時）/ verification_dir / authoring_pass（`full|detail-only|companion-docs`、既定 `full`）。補助情報源（スクリーンショット dir・verification_url）があれば受け取る。verification_url は任意であり、未開通でも著述を止めない。渡された場合だけ scenarios の query/path_params の実測値を確定転記する。`authoring_pass=companion-docs` では detail_design_path と pass1_receipt_path を必須とし、パス1証跡の固定検収契約を満たさなければ fail-closed で差し戻す。いずれか必須引数が欠ける場合は起動不可として呼び出し元へ差し戻す。

`companion-docs` の開始前に pass1_receipt_path の JSON を読み、`status=DETAIL_AUTHORED`、`detail_design_path` が起動引数と一致、`facts_lock_sha256` が現在の `<facts_ref>/facts.lock` の SHA-256 と一致、`coverage_check=PASS`、`audit_check=PASS` の5条件を機械検収する。詳細設計書の実在も確認し、1条件でも満たさなければ `status=BLOCKED` とする。

統括（orchestrator）が著述スキル起動前にスキャフォールディングを実施済みの前提で動作する（標準の並列起動・大規模2パスのいずれでも競合を避けるため、実施主体は統括に一本化されている）。画面ディレクトリが存在しない場合はエラーとして呼び出し元へ報告する。存在する場合は `bash <scaffold_script_path> --verify <output_dir> <画面ID>`（scaffold_script_path は管理者が解決して渡すスキャフォールディングスクリプトのパス。audit_script_path と同型。実体: `shared/scripts/scaffold-screen.sh`）で構造の健全性を確認し、exit 1 なら template_root 起点の原本から欠落ファイルのみ復元して再実行する（fail-closed）。

**完了**: 必須引数が揃い、画面ディレクトリの構造健全性を確認済み

## Phase 2: 封印検証と facts 読込

## Step 2-1: 封印検証と facts 読込

**使用ツール**: Read / Bash

`shared/scripts/seal-facts.sh verify <facts_ref>` を実行し exit 0 を確認する（Phase 2 の必須ゲート）。exit 1（facts.yml が封印時から改変されている）なら著述を行わず `status=BLOCKED` とし、hint に「extracting-unit-facts-from-code で再封印せよ」と記す（このゲートはループ対象外の終端条件）。

exit 0 を確認したら、`<facts_ref>/facts.yml`（`shared/references/facts-schema.md` 準拠の12分類構造）と `common_docs_root` 配下のプロジェクト共通文書だけを情報源として読み込む。**対象リポジトリの原本コードは Read しない**（設計原則4）。12分類の定義・キーの付け方は `shared/references/facts-schema.md` を参照する。

封印検証成功後、`bash shared/scripts/check-facts-sufficiency.sh <facts_ref>/facts.yml` を実行し exit 0 を確認する（著述前の充足検査）。exit 0 でなければ著述に入らず `status=BLOCKED` としてfacts抽出工程へ差し戻す。差し戻し理由には検査出力のchapter-impact行（違反セクション→影響する設計書の章）を添え、どの章のfactsが薄いかを申し送る。

**完了**: `seal-facts.sh verify` が exit 0、`check-facts-sufficiency.sh` が exit 0、かつ facts.yml と共通文書の読込完了

## Phase 3: 観点表追記

## Step 3-1: 観点表追記

**使用ツール**: Bash / Write

facts.yml から単体テスト観点表へ観点行を追記する（意味キー規約: 連番禁止・内容要約キー）。`measurement_pending`（⑨）に由来する観点は `実測委譲（画面単位検証で確定）` として留保する。

`authoring_pass=detail-only` では本Phaseと「テスト仕様書記入責務」を実行せず、詳細設計書だけをPhase 4〜5で完成させる。`authoring_pass=companion-docs` ではPhase 4の設計書転記を実行せず、パス1完成版を改変しないまま本Phaseとテスト仕様書3点の著述だけを行う。

**完了**: `full|companion-docs` は facts.yml 由来の観点行が観点表に追記済み・意味キー規約準拠。`detail-only` は契約どおりスキップ済み

## Phase 4: 設計書転記

## Step 4-1: 設計書転記

**使用ツール**: Read / Bash / Write / Edit / Agent

scaffold直後に `shared/scripts/prefill-design-from-facts.sh <facts_ref>/facts.yml <画面詳細設計書.md>` で facts.yml からの機械転記を実行してよい（任意工程）。facts.yml の12分類を下記マップに従って対応する章表へ機械的に転記し、転記できない列（業務的意味・分類判断等）には `【著述・未確認:<章番号>-<種別>】` マーカーを置く。転記スクリプトを使った場合、Phase 5 の完全性ゲートに `shared/scripts/check-prefill-markers.sh <画面詳細設計書.md>` による残存マーカー検査（残0件）を追記する。

各章の執筆直前に、`shared/references/gold-standard/docs/` 配下の正解設計書（gold標準）を記載粒度・表形式・値の書き方の見本として参照する（gold標準が存在する場合のみ）。参照してよいのは書式（章の粒度・表のカラム構成・値の記述スタイル）のみであり、値・識別子・画面固有の事実の転写・流用は禁止する（対象画面の事実の唯一の出典はfacts.yml）。

facts.yml の各セクションを下記マップに従って各章へ転記する。`measurement_pending`（⑨）は転記せず、該当章に `実測委譲（画面単位検証で確定）` プレースホルダを残し、返却ブロックの `measurement_pending[]` に一覧化する。転記先決定・字面転記と要約の境界・実測委譲の書式などの執筆規律は `references/writing-rules.md` を正本とする。

| facts.yml セクション | 転記先 |
|---|---|
| import | §15.3（依存） |
| export_type | §15.1（ファイル分割）/ §15.2（型定義） |
| const | §10（定数・設定値） |
| state | §5（状態管理） |
| handler | §8（イベント処理） |
| jsx | §3（画面構造）/ §9（領域別仕様） |
| style | DESIGN.md + §3.6/§15.6 のキー参照 |
| api | §7（API 通信仕様） |
| measurement_pending | 転記せず `実測委譲（画面単位検証で確定）` + measurement_pending |
| local_type | §15.2（型定義） |
| effect_trigger | §6.4（データフローの発火契機） |
| error_handling | 章役割キー「エラーハンドリング」で解決（既定 §11.2） |

**measurement_pending の§16自動計上**: measurement_pending の全項目を §16 要確認事項一覧へ自動計上する。計上形式: `| mp-<キー名> | 実測委譲（画面単位検証で確定） | facts由来 | 未解消 |`。Phase 5 の audit-consistency.sh 検査で §16 の measurement_pending 計上数と返却ブロック measurement_pending[] の件数が一致することを突合する。

§3 画面構造の冒頭に画面キャプチャ（`![元コードの画面](./original.png)`）と、コンポーネント名（コード識別子）による入れ子構造の ASCII アートを配置する。画像実体がない場合は `references/writing-rules.md` の読者向け `screen-capture-placeholder` を置き、執筆工程の内部語を本文へ出さない。ASCII アートは facts から抽出したコンポーネントツリー構造を箱図形（┌─ ComponentName ─┐）で視覚化したもの。基本設計書の部品構成（業務用語）とは異なり、実装のコンポーネント階層を反映する。

章の役割キー → §番号の解決は起動引数 chapter_map_path を正本とする。§番号は既定値であり、設計書の章マップ表で解決する。

あわせて facts.yml の `meta` 節を frontmatter へ転記する（`meta.source_repo`→`source_repo`・`meta.source_ref`→`source_ref`・`meta.route`→`scenarios[].path`）。転記規律は `references/writing-rules.md` の「frontmatter 転記規律」を正本とする。

`scenarios[].path` は facts の `meta.route` から必ず確定する。`ready` は facts の jsx 分岐別ルート要素から確定する。実レンダリング確認済みの `verification_url` がある場合だけ `query/path_params` の具体値を転記し、無い場合はテンプレート値を残さず両キーを省略する（該当なしなら省略可という frontmatter 契約に従う）。画面未開通を AUTHORED の差し戻し理由にしてはならない。実測が必要な値は本文の `measurement_pending` と §16 に留保し、後続の動的検証で補完する。

### 大規模ユニットの著述の2パス分割

画面詳細設計書の著述と周辺文書（観点表・テスト仕様書・基本設計）の著述は別パス（別サブエージェント委任）に分割する。対象コードが合計1,500行超または4ファイル超、もしくは詳細設計書が1,000行を超える見込みの大規模ユニットでは必須とする。

- パス1（`authoring_pass=detail-only`）: 画面詳細設計書だけを著述し、Phase 5 の完全性ゲートまで通して `DETAIL_AUTHORED` を返す
- パス2（`authoring_pass=companion-docs`）: パス1の `DETAIL_AUTHORED`・詳細設計書の完成版・facts を入力に、観点表・テスト仕様書を著述して `COMPANION_AUTHORED` を返す。基本設計書は同じパス2で generating-reverse-basic-design（`authoring_pass=large-pass2`）へ別委任する
- パス1未完了でパス2を開始すること、およびパス1で基本設計・観点表・テスト仕様書を先行著述することを禁止する

**完了**: 転記完了・`measurement_pending` が `実測委譲（画面単位検証で確定）` として留保済み・frontmatter に `source_repo`/`source_ref` を転記済み・`scenarios` が1件以上

## Phase 5: 完全性ゲート

## Step 5-1: 完全性ゲート

**使用ツール**: Read / Bash / Write

1. `scripts/check-fact-coverage.sh <facts_ref>/facts.yml <画面詳細設計書.md> [<DESIGN.md>]` を実行し exit 0 を確認する。facts.yml の全項目（`measurement_pending` は「実測委譲」表記があれば転記済み扱い）が設計書いずれかの章に転記済みかを機械突合し、未転記が 1 件でもあれば exit 1（fail-closed）。未転記キーを Phase 4 のマップに従って転記してから再実行する
2. 起動引数 audit_script_path（`shared/scripts/audit-consistency.sh`）を通常モードで実行し、exit 0（内部整合性の違反 0 件）を確認する。
   §15.2 が facts.yml の export_type「型定義なし」に基づく§15章冒頭の非該当集約でも、型を捏造せず exit 0 になる。
   返却ブロックの `measurement_pending[]` 件数を `AUDIT_EXPECTED_MP_COUNT=<件数>` として渡し、再実行する。
   §16 の計上数と指定件数の突合で警告が出ないことを確認する
3. `awk '/^---$/{n++; next} n==1' <画面詳細設計書.md> | grep -c 実測委譲` が `0` であることを確認する（frontmatter の `scenarios` に実測委譲プレースホルダが残っていないかの機械検査）。非0なら著述未完了として Phase 4 へ差し戻す
4. Phase 4 で `prefill-design-from-facts.sh` を使った場合のみ、`shared/scripts/check-prefill-markers.sh <画面詳細設計書.md>` を実行し exit 0（残存マーカー0件）を確認する。残存があれば当該箇所を著述で埋めてから再実行する
5. `python3 shared/scripts/validate-reverse-authoring-inputs.py scenarios --design-doc <画面詳細設計書.md> [--verification-url <verification_url>] --record <verification_dir>/screen-<画面ID>/authoring/scenarios-input-check.json`を必ず実行する。全scenarioのpath/readyは常時必須。verification_urlが無い未開通状態ではquery/path_params省略をPASSとし、実測URLの証跡がある場合は両キーが不足・空ならexit 1とする。exit 1はPhase 4へ差し戻し、AUTHORED系statusを返さない

**完了**: `check-fact-coverage.sh` と `audit-consistency.sh` がともに exit 0・§16 の measurement_pending 計上数（mp-接頭辞キー）が返却ブロック `measurement_pending[]` の件数と一致・frontmatter の実測委譲プレースホルダ検査（`grep -c 実測委譲` が `0`）通過・（prefill-design-from-facts.sh 使用時のみ）`check-prefill-markers.sh` が exit 0・scenarios-input-check.jsonがPASS

## Phase 6: 返却

## Step 6-1: 返却

**使用ツール**: Read / Bash / Write

返却ブロックを検証記録に保存する（下記「返却ブロック」を参照）。`detail-only` では `<verification_dir>/screen-<画面ID>/authoring/detail-pass1.json` を原子的に作成し、`status`、`facts_lock_sha256`、`detail_design_path`、`coverage_check`、`audit_check` を保存する。status は `DETAIL_AUTHORED`、2つの検査値は `PASS` に固定し、facts_lock_sha256 は検収済み facts.lock の SHA-256 とする。

**完了**: authoring_pass に対応する `status=AUTHORED|DETAIL_AUTHORED|COMPANION_AUTHORED` の返却ブロックが検証記録に保存済み

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 必須引数が揃い、画面ディレクトリの構造健全性を確認済み |
| Phase 2 | `seal-facts.sh verify` が exit 0、`check-facts-sufficiency.sh` が exit 0、かつ facts.yml と共通文書の読込完了 |
| Phase 3 | `full|companion-docs` は観点表・テスト仕様書を著述済み。`detail-only` はスキップ済み |
| Phase 4 | `full|detail-only` は転記完了・`measurement_pending` 留保済み・frontmatter確定。`companion-docs` はパス1完成版を未変更 |
| Phase 5 | `full|detail-only` は完全性ゲートと決定的scenarios入力検査を通過。`companion-docs` は入力した `DETAIL_AUTHORED` 証跡と詳細設計書の実在を再検収済み |
| Phase 6 | authoring_pass に対応する返却 status が検証記録に保存済み。detail-only は固定形式のパス1証跡も保存済み |
| **Goal** | 裸の「未確認」ゼロ（残ってよいのは `実測委譲（画面単位検証で確定）` と §16 起票済みのみ） |

## ループ設計

Phase 5（完全性ゲート）で未転記キーが検出された場合、Phase 4 へ差し戻して転記を補い、Phase 5 を再実行する。Phase 2 の封印検証失敗（exit 1）はこのループの対象外であり、即 `status=BLOCKED` として呼び出し元へ差し戻す終端条件である。

| 要素 | 内容 |
|---|---|
| 反復条件 | `check-fact-coverage.sh` が未転記キーを検出（exit 1）したら、Phase 4 で転記を補い Phase 5 を再実行する |
| 上限回数 | 5 回 |
| 停止条件 | 収束停止: `check-fact-coverage.sh` exit 0 かつ `audit-consistency.sh` 違反 0 件 ／ リソース上限: 5 回到達（未収束の場合は BLOCKED として呼び出し元へ差し戻す） |

facts 読込・執筆（Phase 2〜4）はサブエージェントへ委任しない。本スキルは原本非アクセスの執筆役であり、カンニング防止のための情報遮断は不要だが、章マップ・執筆規律の一貫性を保つため単一のメインエージェントが通しで担う。

## 返却ブロック

契約正本 `orchestrating-reverse-docs-flow/references/contract.md` の共通サブセット（status/scope/artifacts/hint）に準拠する。

| キー | 値 |
|---|---|
| status | `AUTHORED`（full完了）\| `DETAIL_AUTHORED`（detail-only完了）\| `COMPANION_AUTHORED`（companion-docs完了）\| `BLOCKED`（facts未封印・引数不足・パス順序違反等で著述不能） |
| scope | `<system>-<画面ID>`（工程を跨いだ同一性キー） |
| artifacts | 画面詳細設計書・DESIGN.md・単体テスト観点表 のパス |
| facts_ref（拡張） | 入力で受け取った facts ディレクトリの絶対パスをそのまま転記（下流工程への追跡用） |
| detail_design_path（拡張） | detail-only / companion-docs が参照する完成済み画面詳細設計書の絶対パス |
| pass1_receipt_path（拡張） | detail-only が作成し、companion-docs が固定契約で再検収する `detail-pass1.json` の絶対パス |
| measurement_pending | ⑨実測系として設計書に確定せず画面単位検証へ委譲した項目の一覧（拡張フィールド） |
| hint | 次工程（検証スキル起動）への申し送り・差し戻し理由 |

## 予想を裏切る挙動

- 原本コードの Read は全面禁止。情報源は facts_ref 配下の facts.yml と common_docs_root 配下の共通文書のみ（設計原則4）
- facts.yml の字面（`value` 列）をそのまま書き写すだけでなく、章の文脈に沿って正規化して書く。ただし facts に無い事実を創作しない（境界例は `references/writing-rules.md`）
- `measurement_pending`（⑨実測系: 初期表示値・DOM 順・要素位置・レイアウト）を目視転記・推測で確定しない。画面未開通でも著述を止めず、`実測委譲（画面単位検証で確定）` に留め measurement_pending へ回す
- 対象外は必ず根拠を添える。章内の全下位項目が対象外なら `references/writing-rules.md` の章単位集約書式を使う
  個別の見出し・空表・「該当なし」行へ展開しない。裸の「未確認」は完了条件違反とする
- §15.2を「型定義なし」と集約した場合も、audit_script_path は exit 0 になる
  型名抽出は型定義表がない場合を許容する。exit 1 は実違反として扱い、型を捏造して検査を通さない
- facts.yml 自体の誤り・欠落に気づいても本スキルは書き換えない。extracting-unit-facts-from-code への差し戻しとして hint に記録する
- 本 SKILL.md 本文にリバース対象の固有値（対象リポジトリパス・画面 ID・BL 名）を書かない。固有値は起動引数・設計書側に置く
- 進捗は Step 単位で TaskCreate/TaskUpdate する（一括登録しない）

## テスト仕様書記入責務

facts.yml と単体テスト観点表・結合テスト観点表を情報源に、著述工程はテスト仕様書3点（`テスト項目書/単体テスト仕様書.md`・`テスト項目書/結合テスト仕様書.md`・`テスト項目書/操作シナリオ仕様書.md`）の「テストケース一覧」（操作シナリオ仕様書は「シナリオ一覧表」）を記入する責務を負う。各行は観点表の観点キーと1:1または1:多で対応させ、キーは連番禁止（意味キー規約）。

- 単体テスト仕様書・結合テスト仕様書: 観点表の各観点キーについて、facts.yml から読み取れる具体的な入力値・期待結果（アサーション）を記入する。facts.yml から確定できないケースは空行のまま残さず、根拠付き「該当なし」または §16 要確認事項一覧への計上のいずれかで扱う
- 操作シナリオ仕様書: `jsx`（⑥）・`handler`（⑤）分類に操作要素（クリック・入力・選択等）が facts.yml 上に実在する画面では、最低1シナリオを定義する責務を負う。操作要素が facts.yml に実在しない画面は frontmatter の `operation_test_spec` キーを省略してよい（省略自体が「該当なし」の表明であり、別途根拠併記は不要）
- テストコードの保存: 著述工程が facts.yml から導出した例示・雛形のテストコード断片を作成した場合は `<画面ID>/検証記録/<timestamp>/テストコード/` へ保存し、ファイル名を観点キーと対応させる（例: `<観点キー>.test.ts`）。この断片は著述工程の参考実装であり、最終的な単体テスト正本（`<画面ディレクトリ>/テスト項目書/テストコード/単体/`）の生産者は `rebuilding-screen-unit-from-docs` のみである（`shared/references/リバース工程設計.md` の責務確定「単体テスト正本」を参照）。著述工程の断片保存は正本の差し替えを意味しない

## 画面横断章の業務語彙抽象化責務

mode=screen が著述する画面横断章（§1 画面概要・§2 機能一覧・§4 業務ルール・§12 画面遷移・§13 非機能要件・§14 共通仕様準拠）は、§3〜§11・§15 実装契約等の実装依存章から業務語彙へ抽象化した、実装非依存の記述とする。これらの章は §15 実装契約とは異なり、原本コードの実装詳細（コード識別子・フレームワーク用語・型構文・ファイルパス・ライブラリ名）を読み手に露出させない。

禁止観点（コード識別子・フレームワーク用語・型構文・ファイルパス・ライブラリ名）は audit_script_path（`shared/scripts/audit-consistency.sh`）が画面横断章のうち章マップに役割キーが登録済みの章（既定: 機能一覧・画面遷移）を対象に検査する。§15 実装契約章はこの禁止観点の対象外（実装契約章はコード識別子・型構文を記載する章のため）。

## 未確定値の記載ルール

未確定値は「未定」等のプレースホルダを記入せず、キーを省略するか §16 要確認事項へ回す。
唯一の許容表記は `measurement_pending` 由来の `実測委譲（画面単位検証で確定）` とする。
根拠を伴わない裸の「実測委譲」は許容しない。
対象外には判断根拠を残し、複数の対象外項目は `references/writing-rules.md` の章単位集約書式を使う。
DESIGN.md の雛形が要求する「実測値の抽出元」欄も省略してはならない。
audit_script_path はこれらを機械検査する。

## 完了報告

`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（作業報告型）に従う。

固有の検証行:
- check-fact-coverage.sh が exit 0・audit-consistency.sh 違反 0 件

## 設計判断

### check-fact-coverage.sh

**必要性**: facts.yml の全項目が設計書に転記されたかの網羅を機械ゲート化する必要がある。著述の完了条件は「裸の未確認ゼロ」であり、転記漏れを目視確認に頼ると穴だらけの設計書が収束宣言される事故（本スキル分離の動機そのもの）を防げない。facts.yml の意味キー集合（`sections` 配下、`measurement_pending` 除く）と設計書本文の言及を突合し、未転記が 1 件でもあれば exit 1 とすることで Phase 5 の完全性ゲートに組み込む。`measurement_pending` は「実測委譲」表記の有無で判定を切り替える分岐・YAML 固定インデントに基づくキー抽出・自己テストという複数分岐があり、Bash 直叩きでは再現性が失われる。

**代替案を採用しなかった理由**:
- Bash 直叩き: YAML の固定インデントに基づくキー抽出・`measurement_pending` の分岐・comm 突合を都度手書きすると抽出条件がぶれ、転記漏れの見逃しを誘発する
- 既存 Makefile ターゲット拡張: このリポジトリに Makefile がない
- package.json scripts 追加: スキル用途でありプロジェクトの package.json に属さない

**保守責任者**: 人手（ユーザー）。facts.yml の書式・除外分類を変更した時に更新する。

**廃棄条件**: 本スキル廃止時、または転記突合が別の網羅計測に統合された時。

### scaffold-screen.sh（正本は shared/scripts の1本・scaffold_script_path 引数で受領）

**必要性**: 画面ディレクトリのスキャフォールディングは、元来は設計書を新規著述する著者役（本スキル）が担っていた。しかし基本設計（generating-reverse-basic-design）と詳細設計（本スキル）が Agent(run_in_background: true) で並列起動されるようになったため、両スキルが個別にスキャフォールディングを実行すると競合するリスクが生じる。この競合を避けるため、実施主体を統括（orchestrator）へ一本化し、本スキルは並列起動前にスキャフォールディング済みであることを前提として動作する。スクリプトの正本は本リポジトリの `shared/scripts/scaffold-screen.sh` の1本のみで、本スキルはスクリプト本体を保持せず、起動引数 scaffold_script_path（管理者が解決して渡す。audit_script_path と同型）で受け取って Phase 1 で `--verify` を実行し、構造の健全性のみを確認する。スクリプトは template_root（引数指定 or 既定値）からのコピー・プレースホルダ置換・staging 経由の原子的配置・--verify/--dry-run の 3 モードを持ち、Bash 直叩きでは再現性がない。

**代替案を採用しなかった理由**:
- Bash 直叩き: テンプレートコピー・sed 置換・相対パス補正・staging mv を都度手書きすると部分生成物の混入を招く
- スキルフォルダごとのスクリプト複製: 本スキルと rebuilding-screen-unit-from-docs で同一スクリプトの複製を持つと二重保守になり内容が乖離する。正本を `shared/scripts/` に1本化し、各スキルは scaffold_script_path 引数で受け取る
- 既存 Makefile ターゲット拡張: このリポジトリに Makefile がない
- package.json scripts 追加: スキル用途でありプロジェクトの package.json に属さない

**保守責任者**: 人手（ユーザー）。テンプレート構造の変更時に `shared/scripts/scaffold-screen.sh`（正本の1本）を更新する。

**廃棄条件**: 本スキル廃止時、またはスキャフォールディングがテンプレートエンジンに統合された時。

### prefill-design-from-facts.sh

**必要性**: facts.yml（12分類）を各章表へ転記するPhase 4の作業は、キー命名規約（`<分類>-<名前>-<補足>`）に基づく名前列の復元・evidence引用の付与・facts側に無い列へのマーカー挿入・アイテム0件時のプレースホルダ温存判断・転記後の残存プレースホルダ一括マーカー化という複数分岐を機械的に反復する定型作業であり、目視での転記は転記漏れ・裸のプレースホルダ残存という本スキル分離の動機そのものの事故を誘発する。facts.yml の固定インデント解析（2パス構成のawkステートマシン）・12分類と転記先アンカーの対応表・終端self-verify（プレースホルダ残存検査＋facts全キー突合）という複数の決定的分岐を持ち、Bash直叩きでは再現性が失われる。

**代替案を採用しなかった理由**:
- Bash 直叩き: 12分類と転記先の対応・アンカー検索・プレースホルダ一括置換を都度手書きすると転記漏れや裸のプレースホルダ残存を誘発する
- 既存 Makefile ターゲット拡張: このリポジトリに Makefile がない
- package.json scripts 追加: スキル用途でありプロジェクトの package.json に属さない

**保守責任者**: 人手（ユーザー）。facts.yml のスキーマ・画面詳細設計書テンプレートの章構成を変更した時に転記マップ・アンカー正規表現を追従させる。

**廃棄条件**: 本スキル廃止時、または転記が別の自動生成基盤に統合された時。

### check-prefill-markers.sh

**必要性**: `prefill-design-from-facts.sh` が挿入する `【著述・未確認:<章番号>-<種別>】` マーカーは、著者が実際に著述を終えたかを機械的に検査できなければ、マーカーが残存したまま設計書が完成扱いされる事故を防げない。Phase 5 完全性ゲートに組み込む fail-closed の残存検査には再現性のあるスクリプト化が必要。

**代替案を採用しなかった理由**:
- Bash 直叩き: `grep` 一発で代替できなくはないが、ファイル/ディレクトリ両対応・exit コード契約（0/1/2）・自己テストをPhase 5ゲートから毎回安定して呼べる形にするにはスクリプト化が必要
- 既存 Makefile ターゲット拡張: このリポジトリに Makefile がない
- package.json scripts 追加: スキル用途でありプロジェクトの package.json に属さない

**保守責任者**: 人手（ユーザー）。`prefill-design-from-facts.sh` のマーカー書式を変更した時に検査パターンを追従させる。

**廃棄条件**: 本スキル廃止時、または `prefill-design-from-facts.sh` 自体が廃止された時。

## 参照資料

本スキルは orchestrating-reverse-docs-flow の契約（`references/contract.md`）に準拠し、args 全量指定で単独起動できる。

- `references/phase-details.md` — Phase 2（封印検証と facts 読込）・Phase 5（完全性ゲート）の詳細手順
- `references/writing-rules.md` — 執筆規律の正本（章マップ準拠の転記先決定・facts のキー→設計書章の対応規律・字面転記と要約の境界・実測委譲の書式・禁止事項）
- `scripts/check-fact-coverage.sh` — Phase 5 完全性ゲート（facts.yml → 設計書の転記突合。`--self-test` 内蔵）
- 起動引数 scaffold_script_path（Phase 1 スキャフォールディング〔テンプレート展開・--verify・--dry-run〕。実体: `shared/scripts/scaffold-screen.sh`。正本はこの1本のみ）
- 起動引数 facts_ref（封印済み facts ディレクトリの絶対パス。実体: extracting-unit-facts-from-code が出力する `<verification_dir>/screen-<画面ID>/facts/<run_id>/`）
- 起動引数 common_docs_root（プロジェクト共通文書ルートの絶対パス。実体: generating-reverse-common-docs が採録する `プロジェクト共通/`）
- 起動引数 chapter_map_path（章役割キー対応表。実体: `shared/references/chapter-map.md`）
- 起動引数 audit_script_path（内部整合性監査。実体: `shared/scripts/audit-consistency.sh`）
- 起動引数 template_root（テンプレート原本。実体: `shared/templates/リバース検証`）
- `shared/references/facts-schema.md` — facts.yml のスキーマ定義（12分類・必須フィールド・正規化規則）
- `shared/scripts/prefill-design-from-facts.sh` — Phase 4 の任意工程（facts.yml からの機械転記。`--self-test` 内蔵）
- `shared/scripts/check-prefill-markers.sh` — Phase 5 完全性ゲートの追加検査（prefill 使用時のみ。残存マーカー検査。`--self-test` 内蔵）
- `shared/scripts/check-facts-sufficiency.sh` — Phase 2 充足検査ゲート（facts.yml の12分類充足を機械検査。`--self-test` 内蔵）
- `shared/references/gold-standard/` — 正解セット（gold標準）。記載粒度の見本（Phase 4）・バックテスト（スキーマ検証）・カバレッジ受入判定に使用
- `shared/scripts/backtest-facts-against-gold.sh` — gold標準からの逆算検査（`--self-test` 内蔵）
- `shared/scripts/check-doc-coverage-against-gold.sh` — gold標準に対するカバレッジ受入判定（`--self-test` 内蔵）
