---
name: maintaining-semantic-glossary
description: |
  用語変更の検査と影響分析を行う。
  TRIGGER when: 用語追加、更新、廃止、重複、類義語、禁止語、命名、未使用、影響調査時。
  SKIP: 解析候補の抽出だけを行う時、用語集を閲覧するだけの時。
invocation: maintaining-semantic-glossary
type: orchestration
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion]
---

# 意味用語集保守スキル

個別の用語変更、品質監査、影響分析、候補をレビューし、`$managing-semantic-glossary` が消費できる変更要求を作る。正式用語集は直接編集せず、既定は `dry_run=true` とする。

本Skillは独立したCRUD runnerや用語保守CLIではない。AIがRead/Grep/Bashで定義YAML・候補・影響を調べ、Write/Editで変更要求を作る手順である。`scripts/` はSkillの実行入口ではなく契約検証用テストだけを置く。

## 使用タイミング

- `add`、`update`、`deprecate`、`retire` の変更要求を準備する時
- `detect-duplicates`、`detect-synonyms`、`detect-forbidden-terms` を行う時
- `detect-naming-violations`、`detect-unused-terms` を行う時
- `analyze-impact`、`review-proposal`、`validate-registry` を行う時

照会だけなら `$managing-semantic-glossary` のlookup、候補抽出だけなら各解析Skillを使う。

## 入出力契約

入力はoperation、glossary/proposal ref、target key、change reason、requester、scan scopes、`dry_run` を持つ。出力はstatus、operation、target key、validation、impact summary、recommended action、不足情報、変更要求の保存先を持つ。

`review-proposal`、`add`、`update`、`deprecate`、`retire` はvalidatorへ `--registry <file-or-dir>` を渡す。registry省略時は `review_required` のblockingとして、変更要求を管理Skillへ渡さない。
change準備時はcanonical proposalの全意味検証、適用後term状態、affected term配列のcanonical `after_hash`を検査する。公開用refは`proposals/<proposal_key>`と`changes/<change_key>`だけを許可し、registryに実在しない自己申告refを変更要求へ渡さない。

正式validatorは `../../../shared/scripts/glossary/validate-semantic-glossary.sh` を使う。
期待終了値は `0`=errorなし、`1`=validation error、`2`=usage/dependency/parse/internal/走査不能とする。
reportの `status` は `valid|invalid|unavailable`、`counts` は `error|warning|review_required` である。
exit 0でもreview_requiredが1件以上なら変更要求を適用可能と判定しない。

診断familyは `SGS`=schema、`SGK`=key/表記衝突、`SGR`=参照、`SGL`=lifecycleとする。
さらに、`SGP`=proposal/approval、`SGV`=version、`SGD`=dependency/parse/internal/走査不能とする。
処理対象diagnostic familyは `SGS`、`SGK`、`SGR`、`SGL`、`SGP`、`SGV`、`SGD` の全系統とする。
各診断はseverityとcodeを保持する。

| SGS | SGK | SGR | SGL | SGP | SGV | SGD |
|---|---|---|---|---|---|---|
| schema | key/表記衝突 | 参照 | lifecycle | proposal/approval | version | dependency/走査不能 |

## 基本ワークフロー

## Phase 1: 要求の正規化

## Step 1-1: operationと対象を確定する

**使用ツール**: Read / Glob / AskUserQuestion

1. operation、対象key、scope、根拠、requester、`dry_run`、registry pathを解決する。
2. 物理削除operationは受け付けず、公開済み用語にはdeprecate/retireを案内する。
3. reverse解析結果はproposalとして読み、観測事実と推定を分離する。
4. proposal reviewと変更操作ではregistryを必須とする。省略時は、validator単体がexit 0でも `review_required` として停止する。

**完了**: operationが許可一覧にあり、正式用語と候補が混在していない。

## Phase 2: 品質検査

## Step 2-1: 構造・命名・重複を検査する

**使用ツール**: Bash / Read / Grep

1. 正式validatorをkind、input、registry、reportの各引数付きで呼ぶ。
   exitとvalidation-report schema準拠reportを保存する。対象操作ではregistryを省略しない。
2. key完全一致、正規化term_ja/term_en、alias/禁止語、code_name/type_name/db_name/api_name/ui_labelとrepresentationの衝突を順序付きで調べる。
3. 類義語はterm_jaだけで統合せず、term_en、definition、category、scope、relation、各コード名を根拠に候補化する。
4. naming violationは違反規則と推奨keyを示す。無意味な連番keyをerrorにする。

**完了**: error、warning、review_requiredを安定した分類で列挙し、自動統合していない。

## Phase 3: 利用・影響分析

## Step 3-1: 参照チャネルを分けて走査する

**使用ツール**: Grep / Glob / Read / Bash

code、database、api、ui、document、event、messageを分け、直接参照、派生参照、意味依存、互換性、教育・運用を区別する。走査不能な法令、契約、教育、運用は `human_check_required` とし、0件を削除許可へ変換しない。

key変更、definition境界変更、scope縮小、active→deprecated、external contract変更では影響分析と移行案を必須にする。

**完了**: 走査したチャネル、未走査領域、直接/推移影響、移行対象が区別されている。

## Phase 4: レビュー補助と変更要求

## Step 4-1: 人が判断できる要求を作る

**使用ツール**: Write / Read / AskUserQuestion

変更前後、理由、根拠、類似語、互換性、影響、不足情報、承認者候補を1件ずつ提示する。AIは推奨判断を返せるが業務上の最終承認者にならない。

外部identity providerによる承認者identity照合は未実装である。actor/role/decisionは審査材料として保持するが、外部本人確認済みとは扱わない。

同一actorがbusiness_approverとtechnical_approverを兼任する場合もrole別承認を要求する。
change案の `approved_by` にはrole-qualified approval identityを2件記録する。
値は `business_approver:<actor>` と `technical_approver:<actor>` とする。

| business_approver:<actor> | technical_approver:<actor> | role-qualified approval identityを2件 |
|---|---|---|
| 業務承認 | 技術承認 | change案へ記録 |

定義変更はglossaryへ書かず、change schemaへ変換しやすい変更要求として保存する。承認を伴う適用は `$managing-semantic-glossary` へ委譲する。

**完了**: registryを含むdry-run結果と、管理Skillへ渡せる変更要求または差し戻し理由が生成されている。registry省略時は変更要求を渡さない。

## Phase 5: 結果の確定

## Step 5-1: 停止理由と次行動を返す

**使用ツール**: Read / Bash

validator exit、finding、影響件数、human check、不足承認、変更要求pathを報告する。errorまたはreview_requiredが残る場合は適用を推奨しない。

**完了**: statusと次の人手判断が一意で、正式用語集が変更されていない。

## 操作別完了条件

| 操作 | 完了条件 |
|---|---|
| add | key衝突と類義候補を確認し、定義・scope・根拠が揃う |
| update | 破壊性、旧新差分、影響、version案が示される |
| deprecate | 理由、後継key、移行期限、移行対象が示される |
| retire | active参照0件と人手確認、移行完了証拠、履歴保持が示される |
| detect-* | 位置・根拠・severityを示し、自動統合・自動削除しない |
| analyze-impact | 直接/派生/意味/互換/運用影響と未走査領域を分ける |
| review-proposal | 観測と推定を分け、採用・差し戻し・却下・保留の材料を返す |

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 許可operationと入力境界が確定している |
| Phase 2 | 品質findingが分類され、自動統合されていない |
| Phase 3 | 全チャネルの結果とhuman checkが区別されている |
| Phase 4 | 管理Skillが消費できる変更要求または差し戻し理由がある |
| Phase 5 | dry-run結果と次行動が監査可能である |
| **Goal** | 正式用語集を直接変更せず、変更判断に必要な品質・影響・根拠を揃えて管理Skillへ引き渡せる |

## ループ設計

| 要素 | 内容 |
|---|---|
| 反復条件 | error、判断不足、追加影響先が見つかった時に要求を補正して再検査する |
| 上限回数 | 同一変更要求につき5回 |
| 収束停止 | error 0件かつ必須情報充足を2回連続で確認する |
| リソース上限 | 5回でreview_requiredのまま停止する |
| 発散検知 | 同じfinding fingerprintが2回連続したら人へ差し戻す |

検出・提案生成と採否判断を同じ主体だけで閉じない。AIは候補と根拠を返し、人が意味を裁定する。

## 重要な注意事項

- 公開済み用語を物理削除しない。未公開・未参照・監査保持不要の誤登録だけを別途人が裁定する。
- 類義語を文字列距離だけで自動統合しない。
- 未使用検出が0件でも削除を提案しない。
- 候補を正式用語へ直接昇格しない。承認状態をファイル移動で代替しない。
- publishを直接実行しない。portalだけを管理Skillへ委譲する。`ai_index`は将来機能であり、現行版では`review_required/not_implemented`として成果物なしで停止する。
- root countsとfindingsから再集計した件数が一致しないvalidator reportを拒否する。

## 予想を裏切る挙動

- `retire` は削除ではなく、通常利用から外してkey解決と履歴を残す操作である。
- 同じterm_jaでもscopeやdefinitionが違えばhomonymであり、重複とは限らない。
- コメントや履歴に現れる禁止語は、新規識別子での利用とseverityを分ける。

## ツールリファレンス

- Read/Grep/Glob: 用語、候補、表現、全参照チャネルを読む。
- Bash: 正式validatorと決定的な走査だけを実行する。
- AskUserQuestion: 不足情報と意味裁定を人へ返す。
- Write/Edit: dry-run reportと変更要求だけを作り、glossary定義を編集しない。

## 参照資料

- 共通契約: `../../../shared/references/semantic-glossary-contract-v0.1.md`
- 保守仕様: `../../../docs/design/用語保守Skill仕様書.md`
- 運用ルール: `../../../docs/design/用語運用ルール.md`
- 固有テスト観点: `references/test-cases.md`
- 人向けガイド: `references/maintaining-semantic-glossary-guide.html`
- CLI再実行・手順契約の区分付き記録（互換ファイル名）: `verification/ai-forward-test.json`
- 証跡記録schema: `verification/ai-forward-test-record.schema.json`

## 完了報告

`~/agent-home/skills/managing-agent-configs/references/skills/completion-report-format.md` の作業報告型を使う。
検証欄へvalidator exit、finding件数、走査チャネル、human_check_required、正式用語未変更を追加する。
