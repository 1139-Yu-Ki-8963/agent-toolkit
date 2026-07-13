---
name: generating-reverse-detailed-design
description: "封印済みfactsと共通文書から画面詳細設計書を執筆する執筆役。 TRIGGER when: facts封印後の設計書執筆・再執筆。 SKIP: facts抽出（→extracting-unit-facts-from-code）、盲検検証（→rebuilding-screen-unit-from-docs）。"
invocation: generating-reverse-detailed-design
type: orchestration
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Agent]
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
2. **「該当なし」に根拠を必須とする**（例:「該当なし（facts.yml の const セクションに項目なし）」）。根拠なしの裸の「未確認」は完了条件違反
3. **プロジェクト非依存**: リバース対象の固有値（対象リポジトリパス・画面 ID・BL 名）はすべて起動引数・設計書側に置き、本 SKILL.md 本文には書かない。完成後に固有文字列ゼロを確認する（環境名の直書き禁止規約にも整合させる）
4. **原本 Read 禁止**: 本スキル実行中に対象リポジトリの原本コードを Read することを全面禁止する。情報源は起動引数 facts_ref 配下の facts.yml と common_docs_root 配下の共通文書に限定する。原本を読むことは検証の盲検性を壊す契約違反であり、facts の欠落に気づいた場合でも自ら原本を確認せず extracting-unit-facts-from-code への差し戻しとして扱う
5. **検証スキルとの関係を明記**: 上記「使用タイミング」の通り、AUTHORED 後に検証スキルを起動し、検証 差し戻し の差し戻し先は本スキルである

## Phase 1: preflight（起動引数検収・スキャフォールディング）

起動引数を検収する: screen_dir / docs_root / template_root / chapter_map_path / audit_script_path / scaffold_script_path / facts_ref / common_docs_root / mode / target_file_path（mode=file 時）。補助情報源（スクリーンショット dir・verification_url）があれば受け取る。verification_url（任意）は開通時に実レンダリング確認済みのURLで、画面レジストリの値を統括が解決して渡し、scenarios の query/path_params の確定転記に使用する。いずれか必須引数が欠ける場合は起動不可として呼び出し元へ差し戻す。

統括（orchestrator）が並列起動前にスキャフォールディングを実施済みの前提で動作する（基本設計・詳細設計の並列起動時にスキャフォールディングが競合するのを避けるため、実施主体は統括に一本化されている）。画面ディレクトリが存在しない場合はエラーとして呼び出し元へ報告する。存在する場合は `bash <scaffold_script_path> --verify <docs_root> <画面ID>`（scaffold_script_path は管理者が解決して渡すスキャフォールディングスクリプトのパス。audit_script_path と同型。実体: `shared/scripts/scaffold-screen.sh`）で構造の健全性を確認し、exit 1 なら template_root 起点の原本から欠落ファイルのみ復元して再実行する（fail-closed）。

完了条件: 必須引数が揃い、画面ディレクトリの構造健全性を確認済み

## Phase 2: 封印検証と facts 読込

`shared/scripts/seal-facts.sh verify <facts_ref>` を実行し exit 0 を確認する（Phase 2 の必須ゲート）。exit 1（facts.yml が封印時から改変されている）なら著述を行わず `status=BLOCKED` とし、hint に「extracting-unit-facts-from-code で再封印せよ」と記す（このゲートはループ対象外の終端条件）。

exit 0 を確認したら、`<facts_ref>/facts.yml`（`shared/references/facts-schema.md` 準拠の9分類構造）と `common_docs_root` 配下のプロジェクト共通文書だけを情報源として読み込む。**対象リポジトリの原本コードは Read しない**（設計原則4）。9 分類（① import 〜 ⑨ measurement_pending）の定義・キーの付け方は `shared/references/facts-schema.md` を参照する。

完了条件: `seal-facts.sh verify` が exit 0、かつ facts.yml と共通文書の読込完了

## Phase 3: 観点表追記

facts.yml から単体テスト観点表へ観点行を追記する（意味キー規約: 連番禁止・内容要約キー）。`measurement_pending`（⑨）に由来する観点は `実測委譲（画面単位検証で確定）` として留保する。

完了条件: facts.yml 由来の観点行が観点表に追記済み・意味キー規約準拠

## Phase 4: 設計書転記

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

**measurement_pending の§16自動計上**: measurement_pending の全項目を §16 要確認事項一覧へ自動計上する。計上形式: `| mp-<キー名> | 実測委譲（画面単位検証で確定） | facts由来 | 未解消 |`。Phase 5 の audit-consistency.sh 検査で §16 の measurement_pending 計上数と返却ブロック measurement_pending[] の件数が一致することを突合する。

§3 画面構造の冒頭に画面キャプチャ（`![元コードの画面](./original.png)`）と、コンポーネント名（コード識別子）による入れ子構造の ASCII アートを配置する。ASCII アートは facts から抽出したコンポーネントツリー構造を箱図形（┌─ ComponentName ─┐）で視覚化したもの。基本設計書の部品構成（業務用語）とは異なり、実装のコンポーネント階層を反映する。

章の役割キー → §番号の解決は起動引数 chapter_map_path を正本とする。§番号は既定値であり、設計書の章マップ表で解決する。

あわせて facts.yml の `meta` 節を frontmatter へ転記する（`meta.source_repo`→`source_repo`・`meta.source_ref`→`source_ref`・`meta.route`→`scenarios[].path`）。転記規律は `references/writing-rules.md` の「frontmatter 転記規律」を正本とする。

`scenarios` の `query/path_params` は `verification_url` から確定転記する。`ready` は facts の jsx 分岐別ルート要素から確定する。`scenarios` 内の実測委譲プレースホルダを禁止し、確定できない場合は AUTHORED を返さず hint「開通不完全（scenarios 確定不能）」で差し戻す。

完了条件: 転記完了・`measurement_pending` が `実測委譲（画面単位検証で確定）` として留保済み・frontmatter に `source_repo`/`source_ref` を転記済み・`scenarios` が1件以上

## Phase 5: 完全性ゲート

1. `scripts/check-fact-coverage.sh <facts_ref>/facts.yml <画面詳細設計書.md> [<DESIGN.md>]` を実行し exit 0 を確認する。facts.yml の全項目（`measurement_pending` は「実測委譲」表記があれば転記済み扱い）が設計書いずれかの章に転記済みかを機械突合し、未転記が 1 件でもあれば exit 1（fail-closed）。未転記キーを Phase 4 のマップに従って転記してから再実行する
2. 起動引数 audit_script_path（`shared/scripts/audit-consistency.sh`）を通常モードで実行し、exit 0（内部整合性の違反 0 件）を確認する。§15.2 が facts.yml の export_type「型定義なし」に基づく根拠付き該当なし文であっても exit 0 になる（型を捏造して検査を通すことは禁止）。返却ブロックの `measurement_pending[]` 件数を `AUDIT_EXPECTED_MP_COUNT=<件数>` として渡して再実行し、検査 i-2（§16のmeasurement_pending計上数と`AUDIT_EXPECTED_MP_COUNT`の突合）の WARN が出ないことを確認する
3. `awk '/^---$/{n++; next} n==1' <画面詳細設計書.md> | grep -c 実測委譲` が `0` であることを確認する（frontmatter の `scenarios` に実測委譲プレースホルダが残っていないかの機械検査）。非0なら著述未完了として Phase 4 へ差し戻す

完了条件: `check-fact-coverage.sh` と `audit-consistency.sh` がともに exit 0・§16 の measurement_pending 計上数（mp-接頭辞キー）が返却ブロック `measurement_pending[]` の件数と一致・frontmatter の実測委譲プレースホルダ検査（`grep -c 実測委譲` が `0`）通過

## Phase 6: 返却

返却ブロックを検証記録に保存する（下記「返却ブロック」を参照）。

完了条件: `status=AUTHORED` の返却ブロックが検証記録に保存済み

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 必須引数が揃い、画面ディレクトリの構造健全性を確認済み |
| Phase 2 | `seal-facts.sh verify` が exit 0、かつ facts.yml と共通文書の読込完了 |
| Phase 3 | facts.yml 由来の観点行が観点表に追記済み・意味キー規約準拠 |
| Phase 4 | 転記完了・`measurement_pending` が `実測委譲（画面単位検証で確定）` として留保済み・frontmatter に `source_repo`/`source_ref` を転記済み・`scenarios` が1件以上 |
| Phase 5 | `check-fact-coverage.sh` が exit 0 かつ `audit-consistency.sh` 違反 0 件・§16 measurement_pending 計上数と `measurement_pending[]` 件数が一致・frontmatter 実測委譲プレースホルダ検査（`grep -c 実測委譲` が `0`）通過 |
| Phase 6 | `status=AUTHORED` の返却ブロックが検証記録に保存済み |
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
| status | `AUTHORED`（著述完了）\| `BLOCKED`（facts 未封印・引数不足等で著述不能） |
| scope | `<system>-<画面ID>`（工程を跨いだ同一性キー） |
| artifacts | 画面詳細設計書・DESIGN.md・単体テスト観点表 のパス |
| facts_ref（拡張） | 入力で受け取った facts ディレクトリの絶対パスをそのまま転記（下流工程への追跡用） |
| measurement_pending | ⑨実測系として設計書に確定せず画面単位検証へ委譲した項目の一覧（拡張フィールド） |
| hint | 次工程（検証スキル起動）への申し送り・差し戻し理由 |

## 予想を裏切る挙動

- 原本コードの Read は全面禁止。情報源は facts_ref 配下の facts.yml と common_docs_root 配下の共通文書のみ（設計原則4）
- facts.yml の字面（`value` 列）をそのまま書き写すだけでなく、章の文脈に沿って正規化して書く。ただし facts に無い事実を創作しない（境界例は `references/writing-rules.md`）
- `measurement_pending`（⑨実測系: 初期表示値・DOM 順・要素位置・レイアウト）を目視転記・推測で確定しない。`実測委譲（画面単位検証で確定）` に留め measurement_pending へ回す
- 「該当なし」は必ず根拠を添える。裸の「未確認」は完了条件違反
- §15.2 が facts.yml export_type「型定義なし」の根拠付き該当なし文でも audit_script_path は exit 0 になる（検査gの型名抽出は無マッチ許容）。exit 1 は常に実違反として扱い、型を捏造して検査を通すことは絶対にしない
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

未確定値はプレースホルダ文字列（`実測委譲`・`TBD`・`TODO`・`未定` 等）をリテラル記入せず、キー省略または §16 要確認事項へ回す。唯一の許容表記は `実測委譲（画面単位検証で確定）`（`measurement_pending` 由来の実測委譲。根拠の丸括弧を伴う固定書式）であり、根拠を伴わない裸の「実測委譲」は許容しない。「該当なし」と記す場合は根拠（何をどう調べて該当なしと判断したか）の併記を必須とする。DESIGN.md の雛形が要求する「実測値の抽出元」欄の省略も同様に禁止（省略は未記入プレースホルダとして扱う）。これらは audit_script_path が機械検査する。

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
- `shared/references/facts-schema.md` — facts.yml のスキーマ正本（9 分類・必須フィールド・正規化規則）
