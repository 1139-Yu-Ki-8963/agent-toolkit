---
name: generating-reverse-basic-design
description: "封印済みfactsから業務語彙のみで基本設計書を執筆する執筆役。 TRIGGER when: 事実封印後の基本設計書生成、決定木「基本設計未著述」での起動。 SKIP: 詳細設計執筆（→generating-reverse-detailed-design）、facts抽出（→extracting-unit-facts-from-code）。"
invocation: generating-reverse-basic-design
type: transform
allowed-tools: [Bash, Read, Write]
---

# 封印済みfactsからの基本設計書執筆スキル

封印済み facts（facts.yml）とプロジェクト共通文書だけを情報源に、業務語彙のみで書かれた基本設計書（画面基本設計書.md）を著述する執筆専任スキル。generating-reverse-detailed-design と同じく原本非アクセスの執筆役であり、情報源は facts_ref 配下の facts.yml と common_docs_root 配下の共通文書に限定する。**本スキル実行中に対象リポジトリの原本コードを Read することは全面禁止**（検証の盲検性を壊す契約違反）である。

基本設計書は詳細設計書の抽象化・要約ではない。facts.yml から業務語彙で直接書く独立した成果物であり、詳細設計書（コード識別子・型構文を含む実装契約）とは章立て・読み手（業務担当者）が異なる。ただし大規模ユニットでは、詳細設計書の完全性ゲート完了後に始まるパス2で著述する。

## 目的

orchestrating-reverse-docs-flow の標準ユニットでは「基本設計未著述」を facts 封印直後に解消する。大規模ユニットでは「設計書未著述」を先に解消し、詳細設計のパス1完了後に本スキルをパス2として起動する。詳細設計書（generating-reverse-detailed-design が著述）が実装寄りの宣言的契約を担うのに対し、本スキルは業務担当者が読める業務レベルの記述に限定した基本設計書を担う。両者は独立した成果物であり、完成済み詳細設計書は大規模パス2の開始証跡・整合対象であって本文の出典ではない。

## 使用タイミング

- facts が封印済み（extracting-unit-facts-from-code が `status=封印済み` で facts_ref を返した後）で、画面基本設計書を新規著述・再著述したいとき
- 標準ユニットでは詳細設計と並列、大規模ユニットでは詳細設計完了後のパス2で起動する
- 起動引数は screen_dir + facts_ref + common_docs_root + 資産パス群 + unit_kind + authoring_pass。`authoring_pass=large-pass2` では detail_design_path と pass1_receipt_path も必須

## 対象範囲

unit_kind パラメータで screen / batch / report / external を区別する契約とするが、**現時点で実装済みなのは unit_kind=screen のみ**（テンプレート `shared/templates/リバース検証/画面/基本設計/画面基本設計書.md` が存在するのは screen のみ。batch/report/external の基本設計書テンプレートは `納品物フォルダ体系.md` の【段階計画 Cycle 4】であり未着手）。screen 以外を指定された場合は著述せず `status=基本設計著述失敗` とし、hint に「unit_kind=screen 以外は未実装」と記す。この契約は extracting-unit-facts-from-code の `profile=screen のみ実装` と同型である。

## 設計原則

1. **正本一元化**: facts.yml は封印済みの確定情報であり第二の正本ではない。正は基本設計書。設計書と facts.yml が食い違ったら基本設計書を直す（facts.yml 自体の誤りは extracting-unit-facts-from-code への差し戻し対象であり本スキルは書き換えない）
2. **「該当なし」に根拠を必須とする**（例:「該当なし（facts.yml の api セクションに項目なし）」）。根拠なしの裸の「未確認」は完了条件違反
3. **プロジェクト非依存**: リバース対象の固有値（対象リポジトリパス・画面 ID・業務名）はすべて起動引数・設計書側に置き、本 SKILL.md 本文には書かない
4. **原本 Read 禁止**: 本スキル実行中に対象リポジトリの原本コードを Read することを全面禁止する。情報源は起動引数 facts_ref 配下の facts.yml と common_docs_root 配下の共通文書に限定する
5. **業務語彙限定**: コード識別子・フレームワーク用語・型構文・ファイルパス・ライブラリ名を一切含めない。実装寄りの契約は詳細設計書（generating-reverse-detailed-design）が担う
6. **詳細設計を内容の出典にしない**: 詳細設計書を要約せず、facts.yml から業務語彙で直接書く。大規模ユニットでは完成済み詳細設計書をパス2開始の完了証跡・整合対象としてのみ検収する

## Phase 1: テンプレート展開と facts 読込

## Step 1-1: テンプレート展開と facts 読込

**使用ツール**: Read / Bash

起動引数を検収する: screen_dir / output_dir / template_root / scaffold_script_path / facts_ref / common_docs_root / unit_kind（既定 screen）/ authoring_pass（`standard|large-pass2`、既定 `standard`）。unit_kind が screen 以外の場合は著述せず `status=基本設計著述失敗` とする（「対象範囲」節を参照）。`authoring_pass=large-pass2` では detail_design_path と pass1_receipt_path を必須とする。証跡JSONの `status=DETAIL_AUTHORED`、`detail_design_path` の一致、`facts_lock_sha256` と現在の facts.lock の SHA-256 の一致、`coverage_check=PASS`、`audit_check=PASS`、詳細設計書の実在を機械検収し、1条件でも満たさなければ fail-closed で `status=基本設計著述失敗` とする。

統括（orchestrator）が著述スキル起動前にスキャフォールディングを実施済みの前提で動作する（標準の並列起動・大規模パス2のいずれでも競合を避けるため、実施主体は統括に一本化されている）。ただし単独起動（統括を介さず本スキルを直接起動する経路）でスキャフォールディングが未実施のまま渡された場合は、本スキル自身が以下の手順で実施してから継続する。画面IDは `screen_dir`（`<output_dir>/<screenUnitRoot>/screen-<画面ID>`。`screenUnitRoot` は output-layout の物理配置キー）の末尾から復元する。表示用 `kindLabels.screen` はpathに使わない。scaffold_script_path は管理者が解決して渡すスキャフォールディングスクリプトのパス（実体: `shared/scripts/scaffold-screen.sh`。正本はこの1本のみ）。

1. `screen_dir` が存在しない場合: `bash <scaffold_script_path> <output_dir> <画面ID>` を実行してテンプレート一式を新規展開する
2. `screen_dir` が存在する場合: `bash <scaffold_script_path> --verify <output_dir> <画面ID>` で構造の健全性を確認する。exit 1（必須ファイルの欠落等）なら `template_root` 起点の原本から欠落ファイルのみ復元し、`--verify` を再実行する（fail-closed）。再実行してもなお exit 1 なら著述を行わず `status=基本設計著述失敗` とする

統括からの起動では、統括が事前に完了させたスキャフォールディングにより手順1・2のいずれも `--verify` が初回で exit 0 になるため、本手順を経ても二重にスキャフォールディングは発生しない。

`shared/scripts/seal-facts.sh verify <facts_ref>` を実行し exit 0 を確認する（必須ゲート）。exit 1（facts.yml が封印時から改変されている）なら著述を行わず `status=基本設計著述失敗` とし、hint に「extracting-unit-facts-from-code で再封印せよ」と記す。

exit 0 を確認したら `<facts_ref>/facts.yml`（`shared/references/facts-schema.md` 準拠の12分類構造）と `common_docs_root` 配下のプロジェクト共通文書だけを情報源として読み込む。**対象リポジトリの原本コードは Read しない**（設計原則4）。

**完了**: 必須引数が揃い、画面ディレクトリの構造健全性を確認済み・`seal-facts.sh verify` が exit 0・facts.yml と共通文書の読込完了・（large-pass2のみ）固定契約のパス1証跡と detail_design_path の検収完了

## Phase 2: facts → 業務語彙への転記（章ごとに実施）

## Step 2-1: facts → 業務語彙への転記（章ごとに実施）

**使用ツール**: Read / Bash / Write

facts.yml の各セクションを下記マップに従って基本設計書の各章へ転記する。12分類のうち業務挙動に直結する6分類（state / handler / jsx / api / effect_trigger / error_handling）と meta.route を使用する。import / export_type / const / style / measurement_pending / local_type は基本設計書に転記しない。

| facts.yml セクション | 基本設計書の章 | 変換規則 |
|---|---|---|
| handler | §3 機能仕様 | 業務動作に翻訳する（例: `onClick` ハンドラ → 「ボタン押下時の処理」） |
| jsx | §1 画面の目的 | 業務目的に翻訳する（画面が「何を見せるか」を業務の言葉で書く） |
| api | §5 入出力の業務的意味 | 業務目的に翻訳する（「何のデータをやり取りするか」を業務の言葉で書く） |
| state | §4 業務ルール | 業務的な制約・条件に翻訳する（実装の条件式ではなく業務の言葉で書く） |
| effect_trigger | §3 機能仕様 / §4 業務ルール | 発火契機と条件を業務動作・業務条件へ翻訳する |
| error_handling | §4 業務ルール | 失敗時の処理・利用者への影響を業務の言葉で書く |
| meta.route（+ common_docs_root の共通設計書） | §6 画面遷移の業務文脈 | 共通設計書の遷移情報を参照引用する |

§2 画面構成の生成: 著述前に`python3 shared/scripts/validate-reverse-authoring-inputs.py screen-composition --screen-dir <screen_dir> --facts <facts_ref>/facts.yml --record <screen_dir>/基本設計/画面構成入力判定.json`を必ず実行する。このhelperのJSON出力を選択経路の単一判定源とし、終了コードと`status`が不一致の場合はfail-closedに停止する。`route=image-priority`なら`<screen_dir>/詳細設計/original.png`を最優先し、画像パスを`../詳細設計/original.png`としてMarkdownに埋め込み、視覚的な領域配置を業務用語のASCIIアートで作成する。original.pngはunlocking-reverse-target-screensが撮影済みの画像ファイルであり、原本コードの直接読み取りには該当しない（情報源制約の対象外）。

次の4ケースを検証記録で確認する。

1. original.png がある場合は、画像を優先する。
2. original.png が無い場合は、facts.yml の jsx セクションにある利用可能な構造だけを根拠に ASCII アートを作成する。
   見出しに **「構造推定」** と明記する。
   根拠に無い値・位置・挙動は創作しない。
3. 構造を推定できない領域は、空欄または「未定義」と記載する。
4. 画像と利用可能な構造がどちらも無い場合は、画面構成を著述しない。
   `status=基本設計著述失敗` とし、両方の根拠が無いことを理由として返す。

実行ごとに、検証記録へ次の監査表を残す。

| original.png | facts.yml の利用可能な構造 | 選択経路 | 出力・停止status |
|---|---|---|---|
| あり | あり | 画像優先 | 画面構成を出力 |
| あり | なし | 画像優先 | 画面構成を出力 |
| なし | あり | 構造推定 | 「構造推定」と明記して画面構成を出力 |
| なし | なし | 著述停止 | `status=基本設計著述失敗` |

完了ゲート: 入力条件・選択経路・出力または停止statusが監査表の同一行で対応し、helperが原子的に保存した`画面構成入力判定.json`が残っていること。helperを呼ばない手作業判定は禁止する。

いずれのケースでも、コンポーネント名や関数名などのコード識別子は使用しない。

各章のキー（意味キー規約準拠）は facts.yml のキーをそのまま流用せず、業務語彙で章ごとに新規に付け直す（例: `handler-onRowClick-遷移` → §3 の機能キー `一覧行選択-詳細遷移`）。facts.yml に該当分類の事実が無い場合は「該当なし」＋根拠（例:「該当なし（facts.yml の api セクションに項目なし）」）を記す。

**創作の禁止（業務断定の根拠規律）**: 業務的な機能・役割・利用者・目的の断定は、対応する facts のキーから直接導出できるものに限る。導出できない事項（なぜこの仕様か・誰が使うか・業務上の位置づけ等）は、もっともらしく断定せず「要確認（現場確認事項）」として明示する。特に注意すべき創作パターン: (a) UI部品の存在（タブ・ボタン等）から、実装されていない挙動（切替で内容が変わる等）を推定して機能として記述する (b) 画面内の文言から利用者・業務フローの方向を推定して断定する。facts 上で空実装・無処理と分かる部品は、その現状（「選択しても表示内容は変わらない」等）を明記する。

**完了**: テンプレートの6章（§1〜§6）すべてに記述がある（「該当なし」＋根拠を含む）・創作の禁止（業務断定の根拠規律）遵守

## Phase 3: 実装用語混入検査

## Step 3-1: 実装用語混入検査

**使用ツール**: Read / Bash / Write

生成した画面基本設計書.md 全文に対し、コード識別子・フレームワーク用語・型構文・ファイルパス・ライブラリ名の混入を grep で検査する。

```bash
grep -nE 'useState|useEffect|useReducer|\bProps\b|styled-components|\bReact\b|\bVue\b|\bAngular\b|interface [A-Z]|: *(string|number|boolean)\b|/[A-Za-z0-9_-]+\.(tsx|ts|jsx|js|css)\b|facts\.yml|facts-schema|facts_ref|const_declarations|handler_exports|type_definitions' <画面基本設計書.md>
```

検出0件で完了とする。1件でも検出された場合は、該当箇所を業務語彙へ書き直してから Phase 3 を再実行する（Phase 2 の転記自体は既に完了しているため、書き直しは検出箇所のみに限定し Phase 2 全体はやり直さない）。

**内部成果物名禁止**: 実装用語 grep の禁止パターンに `facts.yml`・`facts-schema`・`facts_ref`・内部分類名（`const_declarations`・`handler_exports`・`type_definitions` 等の facts.yml セクション名）を含める。これらは内部成果物の識別子であり、業務設計書に露出してはならない。

**facts 根拠チェック**: 業務的な機能・役割の断定（「〜する機能」「〜の役割を持つ」等）は、対応する facts.yml のキーと紐づけ可能なもののみ許可する。紐づけの確認は執筆者のセルフチェックで行い、本文には注記を書かない。facts に根拠が無い事項は断定せず「要確認（現場確認事項）」として明示する。

**コメント残存・status 検査**: HTMLコメント（`<!-- -->`）の残存検査を行う。テンプレートの執筆指示コメントが1件でも残存していれば著述未完了として差し戻す。frontmatter の `status` が `draft` のまま残っていないことを確認する（著述完了時は `status: authored` に更新すること）。

**完了**: 実装用語検出0件・内部成果物名検出0件・facts根拠チェック済み・HTMLコメント残存0件・frontmatter status=authored

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 必須引数が揃い、画面ディレクトリの構造健全性を確認済み・`seal-facts.sh verify` が exit 0・facts.yml と共通文書の読込完了・（large-pass2のみ）パス1証跡検収済み |
| Phase 2 | テンプレートの6章（§1〜§6）すべてに記述がある（「該当なし」＋根拠を含む）・創作の禁止（業務断定の根拠規律）遵守 |
| Phase 3 | 実装用語検出0件・内部成果物名検出0件・facts根拠チェック済み・HTMLコメント残存0件・frontmatter status=authored |
| **Goal** | `status=基本設計著述完了` の返却ブロックが検証記録に保存済み。裸の「未確認」ゼロ |

## ループ設計

Phase 3（実装用語混入検査）で実装用語が検出された場合、該当箇所を業務語彙へ書き直して Phase 3 を再実行する。

| 要素 | 内容 |
|---|---|
| 反復条件 | grep 検査で実装用語が1件でも検出されたら、該当箇所を書き直して Phase 3 を再実行する |
| 上限回数 | 3回 |
| 停止条件 | 収束停止: grep 検出0件 ／ リソース上限: 3回到達（未収束の場合は `status=基本設計著述失敗` として呼び出し元へ差し戻す） |
| Phase 1ゲートとの違い | Phase 1 の封印検証失敗（exit 1）はこのループの対象外。即 `status=基本設計著述失敗` の終端条件 |

facts 読込・執筆（Phase 1〜2）はサブエージェントへ委任しない。本スキルは原本非アクセスの執筆役であり、業務語彙の一貫性を保つため単一のメインエージェントが通しで担う。

## 返却ブロック

契約正本 `orchestrating-reverse-docs-flow/references/contract.md` の共通サブセット（status/scope/artifacts/hint）に準拠する。

| キー | 値 |
|---|---|
| status | `基本設計著述完了`（著述完了）\| `基本設計著述失敗`（facts 未封印・unit_kind 未実装・実装用語混入が上限内で解消しない等で著述不能） |
| scope | `<system>-<画面ID>`（工程を跨いだ同一性キー） |
| artifacts | 画面基本設計書のパス |
| facts_ref（拡張） | 入力で受け取った facts ディレクトリの絶対パスをそのまま転記（下流工程への追跡用） |
| hint | 標準ユニットは並列著述の合流、大規模ユニットはパス2合流への申し送り・差し戻し理由 |

## 予想を裏切る挙動

- 入力は封印済み facts であり、原本コードは直接読まない。コードから事実を抽出するのは extracting-unit-facts-from-code の責務
- 詳細設計書を内容の出典にはしない。標準ユニットは facts から独立して著述し、大規模ユニットは完成済み詳細設計書をパス2開始の完了証跡・整合対象としてだけ検収する（詳細設計の劣化版・要約版にはしない）
- chapter_map_path・audit_script_path は受け取らない。基本設計書は6章固定のテンプレートであり、章役割キーの解決も15章監査（audit-consistency.sh）も不要。本スキル独自の Phase 3 grep 検査で完結する
- unit_kind は受け取るが screen 以外は未実装。batch/report/external の基本設計書テンプレートが存在しないため、無理に screen 用テンプレートを流用しない
- facts.yml の import / export_type / const / style / measurement_pending（実装寄り・実測系の5分類）は基本設計書に一切転記しない。転記対象は state / handler / jsx / api / meta.route の5分類のみ
- 本 SKILL.md 本文にリバース対象の固有値（対象リポジトリパス・画面 ID・業務名）を書かない
- 進捗は Step 単位で TaskCreate/TaskUpdate する（一括登録しない）

## 完了報告

`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（作業報告型）に従う。

固有の検証行:
- 実装用語検出結果（grep 0件 / N件）
- 6章（§1〜§6）の記述充足状況

## 参照資料

本スキルは orchestrating-reverse-docs-flow の契約（`references/contract.md`）に準拠し、args 全量指定で単独起動できる。

- 起動引数 scaffold_script_path（Phase 1 スキャフォールディング。実体: `shared/scripts/scaffold-screen.sh`。正本はこの1本のみ）
- 起動引数 facts_ref（封印済み facts ディレクトリの絶対パス。実体: extracting-unit-facts-from-code が出力する `<verification_dir>/screen-<画面ID>/facts/<run_id>/`）
- 起動引数 common_docs_root（プロジェクト共通文書ルートの絶対パス。実体: generating-reverse-common-docs が採録する `プロジェクト共通/`）
- 起動引数 template_root（テンプレート原本。実体: `shared/templates/リバース検証`）
- `shared/references/facts-schema.md` — facts.yml のスキーマ定義（12分類・必須フィールド・正規化規則）
- `shared/templates/リバース検証/画面/基本設計/画面基本設計書.md` — 基本設計書テンプレート正本（6章固定）

## 設計判断

本スキルは独自スクリプトを持たないため省略する。
