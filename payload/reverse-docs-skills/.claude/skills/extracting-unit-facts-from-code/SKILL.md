---
name: extracting-unit-facts-from-code
description: "原本コードから宣言的契約factsを抽出し独立再計数・封印まで完走する。 TRIGGER when: リバース設計のfacts抽出、画面ユニットの事実表新規作成、facts欠落からの再抽出。 SKIP: 詳細設計執筆（→generating-reverse-detailed-design）、共通文書採録（→generating-reverse-common-docs）。"
invocation: extracting-unit-facts-from-code
type: orchestration
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, TaskCreate, TaskUpdate]
---

# ユニット事実抽出スキル

工程全体は orchestrating-reverse-docs-flow が案内する。本スキルは対象ユニットの原本コードから宣言的契約 facts を抽出し、独立再計数・封印・再現性検証を通して「執筆工程が原本を読まずに済む」品質の `facts.yml` を確定するところまでを単独で担い、単独起動できる（起動引数を渡せば動く）。後続工程（詳細設計執筆）はこの facts を前提として動くが、本スキル自体は他スキルへの依存を持たない。

対象リポジトリに対しては読み取り専用で動作する。書き込み・変更は一切行わない。出力は `screen_dir` 配下の `検証記録/facts/<run_id>/` の3ファイル（`facts.yml`・`facts.lock`・`recount-report.txt`）のみ。

本 Stage は `profile=screen`（画面ユニット）のみを実装する。他プロファイル（API・テーブル・バッチ・帳票・外部連携）は未対応であり、指定された場合は `status=中断` を返す。

画面ユニット以外のプロファイルへの対応は、本スキルの拡張ではなく別の改善サイクルで行う。facts抽出・設計書執筆・往復検証の各スキルのPhase構成・共有スキーマ・テンプレート資産への追加が必要になり、影響範囲が大きいためである。

## 使用タイミング

- 対象ユニット（画面）の原本コードから、後続の詳細設計執筆が参照する宣言的契約 facts を新規に抽出したいとき
- 判定（Phase 7 / Step 30）が NG帰着(b)（事実抽出プロファイルが対象コードの挙動を捕捉できていない）と判定し、抽出プロファイルを改訂した上で再抽出したいとき

### args（全量指定・対話ゼロ）

| 引数 | 必須 | 内容 |
|---|---|---|
| target_repo_path | 必須 | 対象リポジトリの絶対パス |
| target_file_paths | 必須 | 対象ユニットの対象ファイル（画面本体＋直接の子コンポーネント）の、target_repo_path からの相対パス配列。ルーティング定義ファイル（複数画面の遷移情報を単一ファイルで持つもの）は対象外とし、遷移情報はプロジェクト共通文書（共通設計書）側で扱う |
| screen_dir | 必須 | 出力先の画面ディレクトリ絶対パス。facts は `<screen_dir>/検証記録/facts/<run_id>/` に出力する |
| profile | 必須 | `screen` のみ実装。他値は `status=中断` で hint に未対応と返す |
| survey_doc_path | 必須 | アーキテクチャ調査書のパス（方式→プロファイル選択の根拠）。本スキルは内容を読み込まず実在確認のみ行う |
| run_id | 任意（既定 `extract-1`） | 抽出実行の識別子。出力ディレクトリ名・facts.yml内の run_id フィールドに使う |

本スキルはユーザーに直接確認しない（AskUserQuestion不使用）。単独起動時は上表の args をユーザーから直接取得する。

### 対象ファイル集合の列挙方法（target_file_paths）

`target_file_paths` は、画面のエントリ（画面本体コンポーネント）から辿れる画面専有コンポーネント（当該画面からのみ import される子コンポーネント・フック・ユーティリティ）を再帰的に列挙して確定する。他画面と共有されるコンポーネントは対象外（プロジェクト共通側の対象）とする。

ルーティング定義ファイル（Next.js の layout.tsx / page.tsx のルーティング階層、React Router の設定ファイル、Vue Router の設定ファイル等、複数画面の遷移を単一ファイルで定義するもの）は画面単位の対象ファイル集合に含めない。遷移情報はプロジェクト共通文書（共通設計書）が担い、各画面の設計書は共通設計書を参照する形式とする。

列挙結果は `orchestrating-reverse-docs-flow` の契約（`references/contract.md` の「画面完了の定義」）における対象ファイル集合の網羅判定の入力になる。対象ファイルの一部のみを指定する場合（部分スコープ実行）は、`run_id` または facts.yml のメタ情報に対象ファイル数（n件/全m件）を記録し、完全性を欠く旨を明示する。

## 設計原則

- **読み取り専用**: 対象リポジトリへの書き込み・変更は一切行わない。出力は `screen_dir` 配下のみ
- **原本事実主義**: 推測・要約での補完を禁止する。コードに存在しない事実を書かない。全項目に原本の `file:line` 根拠を付ける
- **独立再計数による検証**: 抽出者（Phase 2）と検証者（Phase 3 の `recount-facts.sh`）を分離する。検証者は facts.yml を読まずにまずコードから件数を独立算出し、その後に突合する
- **封印による改ざん検知**: 確定した facts.yml は正規化ハッシュで封印し、以降の改変を機械検知できる状態にする
- **再現性の担保**: 同一 args での抽出結果は（run_id を除き）決定的に一致することを diff で確認する
- **合格判定はスクリプトのexit codeのみ**: 自然文の自己申告での合格判定を行わない

## Phase 手順

### Phase 1: 前提確認

`target_repo_path`・`screen_dir`・`survey_doc_path` の実在を確認する（`test -d`/`test -f`）。`target_file_paths` 全件について `target_repo_path` 配下の実在を確認する。`profile` が `screen` であることを確認する（`screen` 以外は Phase 6 で `status=中断` とし、hint に「未対応プロファイル」と記す）。`run_id`（省略時 `extract-1`）を確定し、`<screen_dir>/検証記録/facts/<run_id>/` を作成する。

完了条件: 全args解決済み・target_file_paths全件実在確認済み・facts出力ディレクトリ作成済み

### Phase 2: 抽出

`references/profile-screen.md` の分類別抽出手順に従い、`target_file_paths` の実コードを読解し、`facts.yml`（`shared/references/facts-schema.md` 準拠の9分類構造）を作成する。全項目は原本の行番号根拠付き（`file:line`）とする。推測・要約での補完を禁止する（コードに無い事実を書かない）。分類に該当項目が無い場合は `items: []` とし `reason` に根拠を記す（根拠なしの空節・裸の「未確認」は完了条件違反）。⑨実測系（`measurement_pending`）は key・evidence のみを記録し value は書かない。あわせて `references/profile-screen.md` の「メタ節（meta）の採録手順」に従い `meta`（source_repo・source_ref・route）を記録する。

完了条件: facts.ymlが9分類（`sections` 配下9キー）の節を持ち、かつ `meta`（source_repo・source_ref・route）を記録済み

### Phase 3: 独立再計数ゲート

`scripts/recount-facts.sh <facts.yml> <target_repo_path> <target_file_paths...>` を実行する。スクリプトは facts.yml を読まずにまずコードから分類別件数を再計数し、その後 facts.yml の記載件数と突合する（乖離率5%以内・必須フィールド（key・evidence）の空欄率30%以内・孤児参照0件の3検査）。標準出力を `recount-report.txt` へ保存する（`scripts/recount-facts.sh ... | tee <facts_dir>/recount-report.txt`）。FAILした場合は Phase 2 へ戻り、指摘された乖離・空欄・孤児参照を修正して再実行する（上限3回。ループ設計は下表参照）。上限到達で収束しない場合は `status=中断` とする。

完了条件: `recount-facts.sh` が `exit 0` かつ recount-report.txt保存済み

### Phase 4: 封印

`bash <shared>/scripts/seal-facts.sh seal <facts_dir>` を実行し `facts.lock` を生成する。続けて `bash <shared>/scripts/seal-facts.sh verify <facts_dir>` を実行し、封印直後の整合性を確認する。

完了条件: `seal-facts.sh verify` が `exit 0`

### Phase 5: 再現性検証

同じ args で抽出（Phase 2〜4 相当。ただし封印は任意）をもう1度、`mktemp -d "${TMPDIR:-/tmp}/XXXXXX"` 形式で作成した一時ディレクトリに実行する。両方の `facts.yml` を `seal-facts.sh normalize` でそれぞれ一時ファイルへ書き出し、`diff` で比較する（プロセス置換 `<(...)` はサンドボックス環境で `/dev/fd` アクセスが権限拒否される場合があるため使わない。一時ファイル経由の比較に固定する）。diffが空なら通過。diffに差分がある場合は以下の診断ステップで分類する:
1. **順序差異**: diff が行の順序のみの違い（キー名・値は同一）→ seal-facts.sh の正規化不足として status=中断、hint に ordering-divergence を記録
2. **キー命名揺れ**: 同一の事実に対して異なるキー名が付与されている → プロファイル改訂が必要として status=中断、hint に key-naming-divergence を記録
3. **共通文書由来の解釈分岐**: 差分の原因が共通文書に記載のない規約・パターンの解釈に起因する → status=共通文書帰着、hint に不足している共通文書の観点を記録。オーケストレーターは NG帰着(c) として generating-reverse-common-docs を mode=append で再起動する
分類できない場合は status=中断（終端条件）とする。

完了条件: 2回の正規化出力の diff が空

### Phase 6: 返却

返却ブロックを出力する。`封印済み` の場合は `artifacts` に facts.yml・facts.lock・recount-report.txt の絶対パスを、`facts_ref` に facts ディレクトリの絶対パスと facts.lock の sha256 を、`pending_measurements` に ⑨実測委譲キーの一覧を記す。`中断` の場合は hint に Phase 3 で未解消の検査項目・Phase 5 の非決定箇所・非対応プロファイル等、中断理由を記す。

完了条件: `status` が確定している

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 全args解決済み・target_file_paths全件実在確認済み・facts出力ディレクトリ作成済み |
| Phase 2 | facts.ymlが9分類（`sections` 配下9キー）の節を持ち、かつ `meta`（source_repo・source_ref・route）を記録済み |
| Phase 3 | `recount-facts.sh` が `exit 0` かつ recount-report.txt保存済み |
| Phase 4 | `seal-facts.sh verify` が `exit 0` |
| Phase 5 | 2回の正規化出力の diff が空 |
| Phase 6 | `status` 確定（`封印済み` \| `中断` \| `共通文書帰着`） |
| **Goal** | 対象ユニットの原本コードから抽出したfactsが独立再計数・封印・再現性検証のすべてを通過し、執筆工程が原本を読まずに済む品質で `screen_dir` 配下に確定していること |

## 返却ブロック

本スキルは orchestrating-reverse-docs-flow の契約（返却ブロック共通サブセット: status/scope/artifacts/hint）に準拠する。

| キー | 値 |
|---|---|
| status | `封印済み` \| `中断` \| `共通文書帰着` |
| scope | `screen_dir` のbasename |
| artifacts | `[facts.yml, facts.lock, recount-report.txtの絶対パス]` |
| hint | 次工程への申し送り、または中断理由 |
| facts_ref（拡張） | facts ディレクトリの絶対パス＋facts.lockのsha256 |
| pending_measurements（拡張） | ⑨実測委譲キーの一覧 |

## ループ設計

| 要素 | 内容 |
|---|---|
| 反復対象 | Phase 3（独立再計数ゲート） `exit 1` → Phase 2（抽出）へ戻る |
| 上限回数 | 3回 |
| 収束条件 | `recount-facts.sh` が `exit 0` |
| 発散条件 | 同一のNG理由（同一検査の同一違反）が2回連続で再発した場合、発散として即中断する（上限回数消化前でも中断してよい） |
| 上限到達時の報告 | `status=中断` とし、`hint` に未解消の検査項目・違反内容・試行回数を記録する |
| 検証役の分離 | 合否判定は `recount-facts.sh`/`seal-facts.sh` の `exit code` のみで行う。自然文の自己申告での合格判定は行わない。Phase 5 の再現性検証は失敗しても Phase 2 へは戻らない（終端条件として `status=中断`） |

## 重要な注意事項

- 対象リポジトリに対しては読み取り専用。書き込み・変更は一切行わない
- 出力は `screen_dir` 配下の `検証記録/facts/<run_id>/` のみ（facts.yml・facts.lock・recount-report.txtの3ファイル）。対象リポジトリ側には何も生成しない
- 推測・要約での補完を禁止する。コードに存在しない事実を書かない。全項目に `file:line` 根拠が必要
- 合格判定は `recount-facts.sh`・`seal-facts.sh` の `exit code` のみで行う。自然文の自己申告は用いない
- `profile=screen` 以外は未対応。指定された場合は抽出を行わず `status=中断` を返す
- AskUserQuestionを使わない。args全量指定・対話ゼロで完走する
- SKILL.md本文にプロジェクト固有値（リポジトリ名・画面名・絶対パス・ユーザー名）を一切書かない。固有値はすべて起動argsで受ける

## 予想を裏切る挙動

- `mktemp` は必ず `mktemp -d "${TMPDIR:-/tmp}/XXXXXX"` 形式で使う。macOS の引数なし `mktemp -d` はサンドボックス環境で失敗する実害がある
- `recount-facts.sh` の各検査はfacts.yml全体を走査する。`references/profile-screen.md`・`shared/references/facts-schema.md` の記入例（`evidence: "src/screens/Foo/Foo.tsx:1"` 等）はあくまで様式説明であり、Phase 2 実行者がそのままコピーして実データとして残さないよう注意する（コピー由来の evidence は孤児参照や乖離超過の原因になる）
- 再現性検証のため facts.yml に現在時刻を書かない。`run_id` のみを持たせ、`seal-facts.sh normalize` が `run_id` 行を除去することで2回の抽出結果を比較可能にする
- 独立再計数の乖離許容5%は正規表現ベースの近似計数と手動キー付けの粒度差を吸収するための閾値。`references/profile-screen.md` の分類別パターンに沿ってキー付け粒度（特にオブジェクト/enum型のフィールド分解単位）を揃えないと乖離超過になりやすい
- **乖離が「粒度差」ではなく「対象コードに実在する構文パターンをrecount-facts.shの正規表現が構造的に検知できないこと」に起因する場合**（記載件数に関わらず再計数が常に0のまま等）、items を reason へ逃がして回避することは禁止する（`shared/references/facts-schema.md` の「該当なし」は実在しない事実専用であり、検知漏れの回避手段ではない）。この場合は `references/profile-screen.md` の該当パターンと `scripts/recount-facts.sh` の対応する count_* 関数を実在の構文に合わせて拡張し、再計数させてから収束させる。既知の構造的盲点（Promiseチェーン形式のAPI呼出し・複数行に折り返したJSX開始タグ・カスタムフックの分割代入による状態変数・オブジェクトリテラル定数のフィールド分解漏れ（宣言行1件のみに丸められる）・条件分岐（早期return・三項演算子）が生成する複数レンダリングパスの外殻ラッパー未採録）は既に対応済み。新たな盲点を発見した場合は `references/profile-screen.md` の「再計数パターンの既知の限界」に追記した上でパターンを拡張する
- `recount-facts.sh` の空欄率検査は key・evidence の2フィールドのみを対象とする。value の欠落はこのメトリクスに現れない（Phase 2 実行者が抽出粒度表に従い必ず埋める）
- 孤児参照は evidence のファイル部分が `target_file_paths` の集合と**完全一致**するかで判定する。サブパスやディレクトリ包含では判定しない
- grep実装（ugrep/BSD grep/GNU grep等）は同一パターンでもパイプ経由のstdinと通常ファイルとで正規表現マッチングの挙動が異なる場合がある。`recount-facts.sh` の分類別カウント関数は必ず実ファイルを引数に渡す設計にしている（改修時もこの原則を崩さない）
- シェルスクリプト内で `$変数` の直後に全角記号（`）`等）を空白なしで続けると、環境によって変数名の終端誤認識が起きる場合がある。`${変数}` のブレース記法を必須にする
- Phase 5 の diff はプロセス置換 `<(...)` ではなく一時ファイル書き出し経由の比較に固定する（サンドボックス環境で `/dev/fd` への書き込みが権限拒否されるケースを実際に確認した）
- `profile=screen` 以外を指定した場合、Phase 2 以降を実行せず Phase 1 の時点で `status=中断` に確定してよい

## 設計判断

### recount-facts.sh

**必要性**: facts.yml の品質保証（抽出漏れ・空欄・孤児参照の不在）を、抽出者自身の自己申告や目視確認に委ねると、「独立再計数による検証」という本スキルの中核原則が成立しない。facts.yml を読まずにまずコードから分類別件数を独立算出し、その後突合するという二段階の検証を1本の決定的スクリプトへ固定化することで、抽出担当（人間・サブエージェント問わず）の記述品質を再現可能な基準で強制する。姉妹スキル `generating-reverse-detailed-design` の `check-fact-coverage.sh`・`generating-reverse-common-docs` の `check-common-docs.sh` と同じ設計方針（決定的grep/awkパターンによる機械ゲート・exit codeのみでの合否判定）を踏襲する。

**代替案を採用しなかった理由**:
- Bashツール直叩き: 分類別の独立再計数（import文のシンボル分解・interface/typeフィールド行の判定・useState等のジェネリクス対応・JSX開始タグの識別等）は数十行のawk/grepロジックを要し、都度手書きでは実行のたびに判定基準がブレる
- 既存Makefile拡張: 本スキルはプロジェクト非依存でMakefileを持たない
- Claude自己申告（検証コマンドを介さない目視確認）: 抽出者自身が「漏れなく抽出した」と自己申告するだけでは、独立検証にならず本スキルの存在意義（原本を読まずに済む品質の facts.yml）を担保できない

**保守責任者**: 人手（ユーザー）。分類別の再計数パターン・閾値（乖離5%・空欄率30%）を変更した時に更新する。

**廃棄条件**: facts.ymlのスキーマ・9分類の枠組みが廃止された時、または本スキルが撤回された時。

### seal-facts.sh

**必要性**: 確定した facts.yml が後続工程（詳細設計執筆）に渡るまでの間に意図せず改変される事故を防ぐには、封印時点の内容を機械的に記録し、以降いつでも1コマンドで整合性を検証できる仕組みが要る。また Phase 5 の再現性検証（同一argsでの2回の抽出結果比較）は run_id・タイムスタンプ・空白の揺れを正規化してから比較する必要があり、この正規化ロジック（`normalize`）は封印（`seal`/`verify`）と再現性検証の両方が同一の実装を共有しなければ判定基準がズレる。`generating-reverse-detailed-design` が後続で facts.yml の封印検証を再利用する設計（Phase 5詳細のリバース工程設計.mdの位置づけ）のため `shared/scripts/` に配置する。

**代替案を採用しなかった理由**:
- Bashツール直叩き: sha256計算・normalize・封印記録の照合を都度手書きすると、封印（seal）と検証（verify）と正規化（normalize）で異なるロジックを使ってしまう危険があり、改ざん検知の信頼性が保証できない
- 各スキル（extracting-unit-facts-from-code・generating-reverse-detailed-design）に同等ロジックを個別実装: 正規化規則の二重管理になり、片方だけ改訂されて判定基準がズレる実害が予見される。共有スクリプト化により単一の正本を維持する
- 既存Makefile拡張・package.json scripts追加: 本スキルはプロジェクト非依存であり対象にならない

**保守責任者**: 人手（ユーザー）。facts.ymlのフィールド構成・正規化規則（`shared/references/facts-schema.md`）を変更した時に同時更新する。

**廃棄条件**: facts.ymlのスキーマが廃止された時、または封印による改ざん検知の仕組みそのものが不要になった時。

## 参照資料

- `~/reverse-docs-skills/.claude/skills/orchestrating-reverse-docs-flow/references/contract.md` — 返却ブロック契約・args仕様の正本
- `references/profile-screen.md`（本スキル同梱） — screen プロファイルの分類別抽出手順・独立再計数用の決定的パターン
- `shared/references/facts-schema.md` — facts.ymlのスキーマ正本（9分類・必須フィールド・孤児参照定義・normalize規則）
- `shared/scripts/seal-facts.sh` — facts.ymlの封印・検証・正規化を担う共有スクリプト
- `shared/references/リバース工程設計.md` — Phase/Step×スキル対応の正本（本スキルの位置づけ: Phase 5 ユニット反復 / Step 18-21）。NG帰着3系統の(b)facts欠落からの差し戻し先でもある
- `.claude/skills/generating-reverse-detailed-design/references/phase-details.md` — 9分類定義の移設元（fact-table.md 側は本スキーマの対象外。authoring 側の改修は別工程）
- `.claude/skills/surveying-architecture-for-reverse-docs/SKILL.md` — 本スキルが前提とするアーキテクチャ調査書（方式→プロファイル選択の根拠）を確定する上流スキル
