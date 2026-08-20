# リバース解析・関連Skill連携仕様

## 1. 権限境界

リバース解析Skillは、用語の候補を生成する。
承認済み用語集へ直接登録、更新、削除してはならない。

解析Skillが観測できるのはコードや既存文書に現れた事実である。
業務上の正式定義、正規表記、採否はプロジェクトメンバーが判断する。

```text
解析対象 -> 候補抽出 -> 提案YAML -> 保守検査 -> 人の審査 -> 管理Skill -> 承認済み用語YAML -> 派生物
```

## 2. 解析Skillが抽出する情報

### 2.1 観測事実

- 識別子、型名、DB表名、列名、API field、画面ラベル、メッセージ
- 出現位置と参照先
- 型、制約、列挙値、主キー、外部キー
- 同じ語の複数チャネルでの対応
- コメント、設計書、OpenAPI、schemaに明記された定義文
- 利用頻度と分布。ただし、重要度の確定には使わない

### 2.2 推定情報

- 提案key
- 提案label
- 推定definition
- kindとcategory
- scope
- 既存用語との関係
- 同義語、略語、旧称の候補

推定項目は `proposal.inferences[]` に入れ、観測事実へ混ぜない。

### 2.3 根拠

根拠は、参照位置、観測時刻、対象revision、抜粋hash、何を裏付けるかを持つ。
全文コピーを定義へ保存せず、必要最小限の抜粋またはhashと参照を使う。

### 2.4 信頼度

提案全体のscoreだけでなく、term_ja、term_en、definition、scope、categoryなど推定フィールドごとの根拠不足を記録できるようにする。
信頼度は採用可否を自動決定しない。

### 2.5 承認状態

解析Skillが設定できる状態は `detected` だけとする。
maintainerが構造検査を通した候補だけを `needs_review` にする。
`approved`、`rejected`、`deferred`、`merged` は審査者または管理Skillだけが設定できる。

## 3. 提案データの変換規則

| 提案フィールド | 承認時の変換先 | 規則 |
|---|---|---|
| `proposed_term` | `terms[]` | approver、導入versionを含む完成形を再検証後にそのまま昇格する |
| `proposed_term.provenance.sources` | `provenance.sources` | 完成形に含まれる根拠をそのまま昇格する |
| `proposal.evidence` | 変更履歴 | 観測時刻と抜粋hashを監査証跡として残す |
| `proposal.inferences` | 変更履歴 | どの推定を人が承認または修正したか残す |
| `proposal.confidence` | 変更履歴 | 定義用語の品質値としては使わない |
| `proposal.approval` | 変更履歴 | reviewer、日時、理由を残す |
| `proposal.detected_by` | 変更履歴 | Skill名とversionを残す |

承認時にapprover、導入versionが未確定、定義根拠が不足、keyが衝突している場合は昇格しない。

## 4. 既存リバースSkillとの移行方針

既存名を維持する互換入口 `generating-glossary-for-reverse-docs` は、次の2段階を越境しないよう候補生成専用へ変更した。

1. 解析経路は、対象リポジトリ外として明示された絶対 `proposal_output_ref` へ、正式proposal schemaの提案YAMLと隣接diagnostics JSONだけを出力する。
2. 用語管理経路は、schema検証済みかつ承認済みの用語YAMLから `managing-semantic-glossary` のportal publishで `一覧/用語辞書/用語辞書.html` を生成する。

既存の `term`、`definition`、`codeRefs`、`category`、`sourceRef` は、提案モデルの `proposed_term` と `proposal.evidence` へ移行する。
既定のcategory対応は `domain` から `business`、`tech` から `technical` とする。
それ以外の既存categoryは自動変換せず、対応keyを人が指定するまで `changes_requested` にする。
互換入口は承認操作を持たず、proposalの `approval.status` を `detected` に固定する。`proposal_output_ref` の省略、相対パス、対象repo内またはsymlink経由のrepo内パスはエラー終了する。ヘッドレス時も自動承認せず、`NEEDS_REVIEW` で停止する。

## 5. 関連Skill

DTOはData Transfer Object、ORMはObject Relational Mappingを指す。

| Skill領域 | 入力 | 出力 | 用語基盤との境界 |
|---|---|---|---|
| リバース解析統括 | 対象repo、解析範囲 | 分野別候補 | 定義へ書き込まない |
| API解析 | OpenAPI、router、DTO | endpoint、field、enum候補 | API表現と根拠を提案する |
| DB解析 | schema、migration、ORM | entity、attribute、identifier候補 | DB表現と制約を提案する |
| 画面解析 | label、form、message | ui_label、term_ja、別名候補 | 表示語を正式語と断定しない |
| コード解析 | class、type、function、event | code表現候補 | 局所変数を原則除外する |
| 文書解析 | 設計書、業務資料 | 定義候補、根拠 | 文書の権威レベルを付ける |
| 命名レビュー | 変更差分、用語索引 | 違反、推奨key | 承認済み用語だけを規範に使う |
| ドキュメント生成 | 承認済み用語 | 定義挿入、リンク | 定義を変更しない |
| ポータル表示 | 承認済み用語、表示設定 | 検索可能なHTML | 提案と承認済みを別画面にする |
| AI設計支援 | 要件、用語索引 | 用語に整合する設計 | 不明語を候補として返す |
| AI実装支援 | 設計、用語索引、命名規約 | 用語に整合するコード案 | 未承認候補を命名規範に使わない |
| コードレビュー | 差分、用語索引 | 表記、意味、禁止語の指摘 | 自動改名しない |
| テスト設計 | 用語、状態、制約 | 境界値、状態遷移観点 | 用語制約を観点へ変換する |
| 影響分析 | 用語変更、資産索引 | 影響グラフ、移行対象 | 書き込みを行わない |
| 派生ずれ検出 | 定義version、派生物 | driftレポート | 定義優先で再生成を促す |
| インポート | 外部提案、legacy辞書 | 正規化した変更要求 | 無審査の一括投入を禁止する |
| セキュリティ分類 | 用語、データ項目 | 機密区分候補 | 最終区分は承認者が承認する |
| ローカライズ | term_ja、term_en、alias、言語 | 翻訳候補 | keyとconcept identityを変えない |

## 6. 連携APIの最小契約

各Skillはファイルまたは標準出力で次を返す。

```yaml
contract_version: 1.0.0
producer:
  skill: analyzing-api-glossary-candidates
  version: 1.0.0
target_glossary_key: commerce_platform
proposal_output_ref: /external-review-area/commerce-platform/proposals.yaml
proposals: []
diagnostics:
  scanned_sources: 0
  missing_sources: []
  unscanned_scopes: []
```

空配列を正常な0件として扱う。
走査不能と走査結果0件を区別する。
`proposal_output_ref` が対象repoの外部にあることを、生成前に実パスで検査する。

## 7. レビュー手順

1. 審査者は候補の観測事実と推定を分けて読む。
2. 保守Skillは既存key、alias、representationとの衝突を示す。
3. 審査者は採用、修正要求、却下、保留を選ぶ。
4. 採用時はapprover、scope、definitionの根拠を確定する。
5. 管理Skillは影響分析とschemaを検証する。
6. 承認済み変更だけを定義へ反映する。
7. 現行のpublish処理はポータルを再生成し、定義versionを記録する。
8. `ai_index`は`review_required/not_implemented`で停止する。AI索引は将来タスクで実装する。

## 8. 予想を裏切る挙動

- 解析結果のconfidenceがhighでも、自動承認しない。
- 同じコード識別子が複数箇所にあっても、同じ業務概念とは限らない。
- 画面ラベルは利用者向けの省略表現であり、正規labelやdefinitionの根拠として不足する場合がある。
