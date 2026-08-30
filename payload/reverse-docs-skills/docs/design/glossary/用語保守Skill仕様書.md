# 用語保守Skill仕様書

## 1. 位置づけ

用語保守Skillは、承認済み用語集と解析候補を継続的に保守する操作ハブである。
推奨名は `maintaining-semantic-glossary`、型は `orchestration` とする。

管理Skillが定義のライフサイクルと公開を統制し、保守Skillは個別操作、品質監査、影響分析、レビュー補助を実行する。
保守Skillは、承認を伴う定義変更を管理Skillへ委譲する。

実装済みfrontmatterは次のとおりである。

```yaml
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
```

## 2. 責務

- 変更要求を正規化し、対象keyを一意に解決する。
- 変更前後の差分と破壊性を判定する。
- 重複、類義、禁止語、命名違反、参照切れを検出する。
- 未使用候補を検出し、削除ではなく確認対象として提示する。
- 影響範囲を画面、API、DB、コード、文書、他用語に分けて集計する。
- 提案の採否判断に必要な根拠と不足情報を提示する。
- 管理Skillが消費できる変更要求を生成する。

## 3. 入出力共通契約

### 3.1 入力

次のpathは契約を説明する架空例であり、このリポジトリの実在pathではない。

```yaml
operation: add
glossary_ref: docs/rules/business-domain/glossary/glossary-root.yaml
target_key: customer_id
request:
  change_reason: 顧客識別子をAPIとDBで統一するため
  requested_by: customer-domain-team
  proposal_ref: proposals/customer_id-from-users-table.yaml
options:
  dry_run: true
  scan_scopes: [code, database, api, ui, document]
```

### 3.2 出力

```yaml
status: review_required
operation: add
target_key: customer_id
validation:
  errors: []
  warnings: []
impact_summary:
  code: 3
  database: 1
  api: 2
  ui: 1
  document: 4
decision:
  recommended_action: approve_with_changes
  reasons: []
change_request_ref: work/glossary-changes/customer_id.yaml
```

`dry_run` を既定値とする。
定義を変える操作は、審査者、変更理由、検査結果を持つ変更要求を管理Skillへ渡す。

## 4. 操作仕様

| 操作 | 目的 | 入力 | 出力 | 完了条件 |
|---|---|---|---|---|
| `add` | 新しい概念を追加する | 用語案、根拠、approver | 追加変更要求 | key衝突と類義候補を確認し、必須項目が揃う |
| `update` | 定義、表現、関係、scopeを更新する | key、変更差分、理由 | 更新変更要求 | 破壊性と影響先を示す |
| `deprecate` | 新規利用を停止する | key、理由、後継key、移行期限 | 廃止変更要求 | 後継、移行対象、告知方針を示す |
| `retire` | 移行済み用語を通常利用から外す | key、移行完了証拠 | 退役変更要求 | active参照が0件で、履歴が残る |
| `detect-duplicates` | 同一概念の重複登録を検出する | 用語集 | 衝突グループ | 完全一致と正規化一致を全件報告する |
| `detect-synonyms` | 類義語候補を検出する | 用語集、しきい値 | 類義候補と根拠 | 自動統合せず人の判断へ回す |
| `detect-forbidden-terms` | 禁止表記の新規利用を検出する | 用語集、対象資産 | 違反箇所、置換key | 位置と推奨置換を示す |
| `detect-naming-violations` | keyと表現の命名違反を検出する | 用語集、命名規約 | error、warning | 違反規則を特定する |
| `detect-unused-terms` | 未使用候補を抽出する | 用語集、対象資産、期間 | 候補、残存根拠 | 全チャネル走査結果を分けて示す |
| `analyze-impact` | 変更影響を集計する | key、変更種別、対象範囲 | 影響グラフ、移行案 | 直接参照と推移参照を区別する |
| `review-proposal` | 解析候補の審査を補助する | 提案、既存用語集 | 採用案、差し戻し項目 | 観測と推定を分けて比較する |
| `validate-registry` | 用語集全体を検査する | 定義、schema | 検査レポート | error 0件を合格とする |

## 5. 検出ルール

### 5.1 重複検出

次の順序で判定する。

1. keyの完全一致をerrorにする。
2. Unicode正規化、空白除去、英字の大小文字統一後のlabel衝突をerror候補にする。
3. aliasを含む表記衝突をreview_requiredにする。
4. 同じrepresentationを複数のactive用語が所有する場合をreview_requiredにする。
5. 定義と関係が近い用語を類義候補へ渡す。

### 5.2 類義語検出

文字列類似度だけで統合しない。
term_ja、term_en、alias、definition、category、scope、relations。code_name、type_name、db_name、api_name、ui_labelの一致度を根拠として提示する。

結果は `same_concept`、`related_concept`、`homonym`、`not_similar` の4候補を人が選べる形にする。

### 5.3 禁止語検出

禁止表記ごとに、理由、置換key、例外scopeを持つ。
コメントや履歴での言及と、新規識別子での利用を区別する。

### 5.4 未使用用語検出

未使用は削除条件ではない。
code、database、api、ui、document、event、messageの各チャネルを走査し、0件だったチャネルを記録する。

法令、契約、運用、教育、移行の利用を機械走査できない場合は `human_check_required` を付ける。

## 6. 影響範囲分析

| 影響分類 | 例 | 判定 |
|---|---|---|
| 直接参照 | key、term_ja、term_en、各コード名を直接使用する | 位置を列挙する |
| 派生参照 | ポータル、生成文書、将来のAI索引 | 再生成対象を列挙する |
| 意味依存 | 計算規則や状態遷移が定義に依存する | 人の確認を要求する |
| 互換性 | 外部API、イベント、DB列 | 破壊的変更として扱う |
| 教育と運用 | 手順書、FAQ、研修資料 | 機械走査結果と確認不足を分ける |

key変更、definitionの境界変更、scope縮小、activeからdeprecatedへの遷移は、常に影響分析を必須にする。

## 7. レビュー補助

レビュー画面またはレポートは、次を1件ずつ提示する。

- 変更前と変更後
- 変更理由
- 根拠
- 既存の類似語
- 直接影響と派生影響
- 後方互換性
- 推奨判断
- 不足情報
- 承認者候補

AIは推奨判断を返せるが、業務定義の最終承認者にはならない。

## 8. ループ設計

| 要素 | 内容 |
|---|---|
| 反復条件 | 検査でerror、判断不足、影響先の追加が見つかった時 |
| 上限 | 同じ変更要求に対する自動修正は5回 |
| 収束停止 | error 0件かつ必須承認が揃う |
| 発散検知 | 同じfingerprintが2回連続で再発する |
| 外部停止 | 承認者未確定、業務判断待ち、根拠取得不能 |

## 9. 予想を裏切る挙動

- 用語削除モードは設けず、公開済み用語にはdeprecateとretireを使う。
- 類義語検出は統合を自動実行しない。別scopeの同義語や同名異義語を壊すためである。
- 未使用用語の検出結果が0件でも、物理削除を許可しない。
