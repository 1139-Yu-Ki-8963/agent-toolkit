---
name: managing-semantic-glossary
日本語名: 用語の変更と公開の管理
description: 正式用語集、用語候補又は変更要求を入力に、指定に応じて照会・審査・試行を行い、役割別の二件の承認がある変更だけを適用して公開する。
invocation: managing-semantic-glossary
type: orchestration
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion]
---

## いつ使うか

用語集の照会、提案の審査、追加、更新、廃止、検証、公開を行いたい時に使う。

## いつ使わないか

解析候補の抽出だけを行う時、全変数一覧を作る時は使わない。

# 正本: reverse-docs-skills

# 意味用語集管理スキル

承認済み用語、解析候補、変更履歴を分離し、用語の照会からポータル投影までを順序付きで統制する。既定は `dry-run` であり、変更要求が業務承認者と技術承認者の二者承認を持つ場合だけ正式用語集を書き換える。

本Skillは独立したCRUD runnerや用語管理CLIではない。AIがRead/Grep/Bashで定義YAML・根拠・reportを確認し、Write/Editで変更要求または承認済みYAML差分を扱う手順である。`scripts/` はSkillの実行入口ではなく契約検証用テストだけを置く。

## 使用タイミング

- `lookup`、`review-proposal`、`add`、`update`、`deprecate`、`retire`、`validate`、`publish` を実行する時
- 承認済み用語と候補の境界、ライフサイクル、content versionを統制する時
- リバース解析結果の扱いを正式用語へ上げる前に人の判断を挟む時

候補抽出だけなら解析Skillを使う。品質検査、影響分析、変更要求の作成だけなら `$maintaining-semantic-glossary` を使う。

## 入出力契約

- 共通契約: `../../../delivery-payload/references/semantic-glossary-contract-v0.1.md`
- validator: `../../../generation-engine/scripts/glossary/validate-semantic-glossary.sh`
- portal投影: `../../../generation-engine/scripts/detail-pages/project-semantic-glossary.py`
- glossary、proposal、changeを別ファイルとして受け取り、混在させない。
- 正式用語は`key`、`term_ja`、`term_en`、`definition`、`scope`、`category`、`code_name`、`type_name`、`db_name`、`api_name`、`ui_label`、`allowed_values`、`status`、`notes`の14項目を同名で管理する。`representations`は出現位置の追跡情報であり、これらの列を「主なコード対応」へ集約する用途には使わない。
- `review-proposal`、`add`、`update`、`deprecate`、`retire` はvalidatorへ `--registry <file-or-dir>` を渡す。registry省略時は `review_required` のblockingとして適用不可にする。
- 実行結果は `status`、`mode`、`dry_run`、`validation`、`approvals`、`artifacts`、`next_action` を返す。
- `dry_run` は省略時 `true`。明示的な適用指示がない限りsource YAMLを変更しない。

validatorの期待終了値は `0`=errorなし、`1`=validation error、`2`=usage/dependency/parse/internal/走査不能とする。reportの `status` は `valid|invalid|unavailable`、`counts` は `error|warning|review_required` である。exit 0かつstatus=validでもreview_requiredが1件以上なら適用を止める。

診断familyは `SGS`=schema、`SGK`=key/表記衝突、`SGR`=参照、`SGL`=lifecycleとする。
さらに、`SGP`=proposal/approval、`SGV`=version、`SGD`=dependency/parse/internal/走査不能とする。
処理対象diagnostic familyは `SGS`、`SGK`、`SGR`、`SGL`、`SGP`、`SGV`、`SGD` の全系統とする。
codeを文字列の部分一致で再解釈しない。severity、code、path、message、relatedRefsを保持する。

| SGS | SGK | SGR | SGL | SGP | SGV | SGD |
|---|---|---|---|---|---|---|
| schema | key/表記衝突 | 参照 | lifecycle | proposal/approval | version | dependency/走査不能 |

## 基本ワークフロー

## Phase 1: モードと入力の確定

## Step 1-1: 操作境界を確定する

**使用ツール**: Read / Glob / AskUserQuestion

1. mode、glossary/proposal/changeのpath、target key、scope、`dry_run`、registry pathを解決する。
2. reverse解析の出力ならproposalとしてだけ受け取り、glossary直接更新要求を拒否する。
3. proposal reviewと変更操作ではregistryを必須とする。省略されたら、validator単体がexit 0でも `review_required` として停止する。
4. `add`、`update`、`deprecate`、`retire`、`publish` の適用は、dry-run結果の提示後にだけ選択可能にする。

**完了**: 入力kindが分離され、modeとdry-run状態が一意に決まっている。

## Phase 2: 機械検証と影響確認

## Step 2-1: 正式validatorを呼ぶ

**使用ツール**: Bash / Read / Grep

1. validatorを `--kind <glossary|proposal|change> --input <path> --registry <file-or-dir> --report <path>` で呼ぶ。lookup/単体validate以外ではregistryを省略しない。
2. exit `1`/`2`、status=`invalid|unavailable`、counts.error>0、counts.review_required>0を検出したら変更と投影を止める。
3. status=validかつwarningだけなら継続できるが、要約と未裁定事項を承認者へ示す。
4. 意味境界、key、scope、external contract、active→deprecatedの変更では影響分析の実在を確認する。

**完了**: validator reportと影響要否が確定し、停止条件が評価されている。

## Phase 3: 二者承認と変更適用

## Step 3-1: 承認を検証して適用する

**使用ツール**: Read / AskUserQuestion / Edit / Write

1. 変更理由、根拠、requester、業務承認者、技術承認者、検査結果を確認する。
2. business approverはdefinition/scopeを、technical approverはrepresentation/移行影響を承認する。AIだけを業務承認者にしない。
   外部identity providerによる承認者identity照合は未実装であり、現段階ではYAML上のactor/role/decision記録と人のレビューだけを検査する。
3. 二者承認のactorが同じ場合でも、role別承認を別々に記録する。
   changeの `approved_by` には `business_approver:<actor>` と `technical_approver:<actor>` を記録する。
   2件のrole-qualified approval identityが必要である。承認欠落、stale version、未裁定衝突では適用しない。

| business_approver:<actor> | technical_approver:<actor> | role-qualified approval identityを2件 |
|---|---|---|
| 業務承認 | 技術承認 | changeへ記録 |
4. 明示的な適用指示があり、`dry_run=false` かつ全条件を満たす時だけglossaryとchangeを一体更新する。
5. 公開済み用語は物理削除せず `active -> deprecated -> retired` を使う。keyを別の意味へ再利用しない。

**完了**: dry-runなら差分だけが返り、適用時は二者承認済みのglossary/changeが同じ変更単位で更新されている。

## Phase 4: 派生物の投影

## Step 4-1: portalだけを生成する

**使用ツール**: Bash / Read / AskUserQuestion

1. publish targetが `portal` であることを確認する。
2. 承認済みglossaryを再度validatorへ渡す。
   `--registry <canonical-registry>`を必須とし、各termが`publication_status=approved`、2件のrole-qualified approver、`decision_ref=proposals/<key>`、`change_ref=changes/<key>`を持ち、実在proposal/changeの承認者・term・適用後hashと一致することを確認する。
   exit `0`かつerror/review_requiredなしを公開条件とする。`candidate`、状態欠落、`legacy_migrated`は公開しない。
3. `project-semantic-glossary.py`をinput、registry、outputの各引数付きで実行する。
   proposal/changeへ結合できない自己申告refを拒否する。source YAMLは変更しない。
   portal投影は標準14項目を同じ列名・順序で出力する。
   page-dataの英語キーは保持し、閲覧用HTMLでは対応する日本語14列見出しを表示する。HTMLの正本配置は`<output_dir>/<unitsRoot>/用語辞書/用語辞書.html`とし、`<output_dir>/用語辞書.html`へは生成しない。`unitsRoot`はoutput-layoutの物理配置キーである。
4. validator exit `1`/`2` または投影失敗時は部分出力を残さず停止する。
5. `ai_index` は将来のpublish拡張である。現行版では `status=review_required`、`reason=not_implemented` で停止し、成果物を作らない。

**完了**: portal targetだけが承認済みversionから投影されたか、禁止targetとして成果物なしで停止している。

## Phase 5: 結果の確定

## Step 5-1: 監査可能な結果を返す

**使用ツール**: Read / Bash

変更key、旧新version、承認者、validator exit、finding件数、生成物、未実施事項をまとめる。変更がなかったdry-runも成功として隠さず報告する。

**完了**: 操作、判断、検証、成果物、次の人手判断が追跡できる。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | mode、kind、path、dry-runが確定している |
| Phase 2 | validator結果と影響要否が記録されている |
| Phase 3 | dry-run、または二者承認済み変更が履歴と一体で処理されている |
| Phase 4 | portalのみ投影され、ai_indexは成果物なしで停止している |
| Phase 5 | 判断根拠と次の行動を含む結果が返されている |
| **Goal** | 未承認・error・review_requiredを正式用語へ混入させず、承認済み意味定義と派生物のversion整合が保たれている |

## ループ設計

| 要素 | 内容 |
|---|---|
| 反復条件 | validation error、承認不足、影響情報不足を修正して再検証する |
| 上限回数 | 同一変更要求につき5回 |
| 収束停止 | error 0件、review_required 0件、必須承認充足を2回連続確認する |
| リソース上限 | 5回に到達したら適用せず停止する |
| 発散検知 | 同じfinding fingerprintが2回連続したら人へ差し戻す |

検証と承認判断を変更生成者だけで完結させない。必要に応じ、別担当へvalidator reportと差分だけを渡して事実確認させる。

## 重要な注意事項

- reverse/API/DB/画面解析Skillからglossaryを直接編集させない。提案はproposalへ保存する。
- 無意味な連番ID、表示順用key、意味を説明できない略語を承認しない。
- `publish` は定義を編集しない。派生物の手修正を定義YAMLへ逆流させない。
- active/deprecated/retiredは保持し、retiredもkey解決と履歴参照を可能にする。
- 現行hash/ref検証は同時に読み取ったartifact間driftの検出であり、可変filesystem上のglossary/proposal/change全同時改変への耐性ではない。真正性保証には保護Git履歴または署名済み外部anchorが必要だが、現行production registry/identity providerとともに未実装である。
- validator reportはvalidation-report schemaで検証し、root countsとfindingsから再集計した件数が一致しないreportを拒否する。

## 予想を裏切る挙動

- `validate` exit `0`でもreview_requiredがあれば適用しない。
- `dry_run=false`だけでは変更権限にならず、二者承認と明示的な適用指示が別途必要になる。
- 未使用の用語でも契約・法令・教育・移行で必要な場合があるため、自動削除しない。

## ツールリファレンス

- Read/Grep/Glob: 入力、schema version、承認、根拠、参照を確認する。
- Bash: 正式validatorとportal投影CLIだけを決定的に実行する。
- AskUserQuestion: 不足承認、適用、破壊的変更の選択を人へ返す。
- Write/Edit: 二者承認済み適用時だけglossary/changeを更新する。

## 参照資料

- 共通契約: `../../../delivery-payload/references/semantic-glossary-contract-v0.1.md`
- 管理仕様・運用ルール: このリポジトリ自身の設計文書（配布対象外）に記載
- 固有テスト観点: `references/test-cases.md`
- 人向けガイド: `references/guide.html`
- CLI再実行・手順契約の区分付き記録（互換ファイル名）: `verification/ai-forward-test.json`
- 証跡記録schema: `verification/ai-forward-test-record.schema.json`

## 完了報告

`../../../delivery-payload/references/完了報告の書き方.md` の作業報告型を使う。
検証欄へvalidator exit、error/review_required件数、承認状況、投影targetを追加する。
