# 用語データモデル・YAMLスキーマ仕様

## 1. モデルの分離

用語基盤は、承認済み用語、解析候補、変更履歴の3モデルを分ける。

承認済み用語モデルは、設計、実装、レビュー、ポータルが参照する定義である。

解析候補モデルは、観測事実、推定、信頼度、承認状態を保持する審査待ちデータである。

変更履歴モデルは、定義の意味変更と移行判断を追跡する監査データである。

解析候補の `proposed_term` は承認済み用語レコードと同じ構造を使う。
承認時は提案メタデータを変更履歴へ移し、`proposed_term` を定義へ昇格させる。

## 2. 用語集ルート

| フィールド | 必須 | 型 | 説明 |
|---|---|---|---|
| `schema_version` | 必須 | string | データ構造のSemVer |
| `content_version` | 必須 | string | 用語内容のSemVer |
| `glossary_key` | 必須 | string | 用語集を表す意味のあるsnake_case key |
| `title` | 必須 | string | 人向け名称 |
| `scope` | 必須 | object | organization、product、applicationなどの適用範囲 |
| `scope_catalog` | 必須 | array | 用語が参照できるorganization、product、application、moduleの意味key一覧 |
| `default_language` | 必須 | string | BCP 47形式の既定言語 |
| `terms` | 必須 | array | 用語レコード。空配列を許可する |
| `metadata` | 任意 | object | 作成日時、更新日時、生成元など |

大規模運用では、論理モデルを変えずに `terms` をドメイン別ファイルへ分割できる。
分割時もregistry全体でkeyと別名の一意性を検査する。

`scope.includes` と `scope.excludes` は、同じ用語集の `scope_catalog[].key` を参照する。
catalogにない外部scopeは、catalogへ意味keyと出所を追加してから参照する。

keyは、物理ファイルやアプリの境界にかかわらず、1つの論理registry全体で一意にする。

SemVerはSemantic Versioningの3区分versionを指す。
BCP 47は言語tagの標準表記を指す。

## 3. 用語レコード

### 3.1 必須フィールド

| フィールド | 型 | 説明 |
|---|---|---|
| `key` | string | 永続的な意味key。ASCII snake_case |
| `term_ja` | string | 日本語の代表用語 |
| `term_en` | string | 英語の代表用語。未確定時は空文字列 |
| `definition` | string | 含む範囲と含まない範囲が判断できる定義 |
| `scope` | string | 適用範囲を示す意味keyまたはdot path |
| `category` | enum | `entity`、`attribute`、`value`、`process`、`event`、`role`、`rule`、`metric` |
| `code_name` | string | 変数・プロパティ等の代表コード名。該当なしは空文字列 |
| `type_name` | string/null | クラス・型・enum等の型名 |
| `db_name` | string | テーブル・列等のDB名。該当なしは空文字列 |
| `api_name` | string | APIのfield・parameter名。該当なしは空文字列 |
| `ui_label` | string/null | 画面表示名 |
| `allowed_values` | string[] | 状態・区分等の許容値。該当なしは空配列 |
| `status` | enum | `active`、`deprecated`、`retired` |
| `notes` | string | 機械判定に使わない補足。補足なしは空文字列 |
| `lifecycle` | object | 状態、導入version、廃止情報 |
| `stewardship` | object | approvers |
| `provenance` | object | 定義根拠と由来 |

上の14フィールドは用語と各実装面を明示的に結ぶ標準列であり、YAMLとポータル投影で同じ名前を使う。
`status`は`lifecycle.status`と一致しなければならない。
`lifecycle`、`stewardship`、`provenance`は承認・履歴・根拠の詳細を保持する管理メタデータであり、標準14列を置き換えない。

### 3.2 任意フィールド

| フィールド | 型 | 説明 |
|---|---|---|
| `aliases` | array | 許可された別名、略語、旧称、言語別表記 |
| `forbidden_terms` | array | 新規利用を禁止する表記と理由 |
| `relations` | array | 上位、下位、部分、関連、置換関係 |
| `examples` | array | 定義に含む具体例 |
| `counter_examples` | array | 定義に含まない紛らわしい例 |
| `constraints` | array | 単位、形式、値域、不変条件 |
| `tags` | array | 検索用の補助タグ。keyの代替には使わない |
| `security_classification` | enum | `public`、`internal`、`confidential`、`restricted` |
| `representations` | array | 各名称の出現位置とchannelを複数保持する追跡情報 |

## 4. 下位オブジェクト

以降のYAML例にあるpath、location、refは、構造を示すための架空値である。
このリポジトリの実在pathを示すものではない。

### 4.1 scope

```yaml
scope:
  level: cross_application
  includes: [customer_portal, order_admin]
  excludes: []
```

`level` は `organization`、`product`、`cross_application`、`application`、`module` のいずれかとする。

### 4.2 representations

```yaml
representations:
  - channel: code
    value: Customer
    symbol_kind: class
    location: src/domain/customer.ts:12
  - channel: database
    value: customers.customer_id
    location: db/schema.sql:41
  - channel: api
    value: customerId
    location: openapi/customer.yaml#/components/schemas/Customer
  - channel: ui
    value: 顧客ID
    location: src/pages/customer/detail.tsx:88
```

`channel` は `code`、`database`、`api`、`ui`、`document`、`event`、`message` のいずれかとする。
`location` は追跡可能な参照であり、単なるディレクトリ名よりファイルと位置を優先する。

### 4.3 aliases

```yaml
aliases:
  - value: 得意先
    type: legacy
    language: ja
    usage: read_only
```

`type` は `synonym`、`abbreviation`、`legacy`、`translation`、`search_only` のいずれかとする。
`usage` は `preferred`、`allowed`、`read_only` のいずれかとする。

### 4.4 relations

```yaml
relations:
  - type: has_identifier
    target_key: customer_id
  - type: related_to
    target_key: order
```

`type` は `broader_than`、`narrower_than`、`part_of`、`has_part`、`related_to`、`has_identifier`、`replaced_by` のいずれかとする。
逆関係を自動導出する場合は、定義に両方向を重複保存しない。

### 4.5 lifecycle

```yaml
lifecycle:
  status: active
  introduced_in: 1.4.0
  deprecated_in: null
  retired_in: null
  replaced_by: null
  reason: null
```

### 4.6 stewardshipとprovenance

```yaml
stewardship:
  approvers: [business-reviewer, architecture-reviewer]
provenance:
  sources:
    - type: domain_document
      ref: docs/domain/customer.md#顧客
      supports: definition
  publication_status: approved
  decision_ref: proposals/customer_from_domain_document
  change_ref: changes/add_customer
```

approverは連絡可能なチーム名または役割名を使う。
個人名だけに固定しない。

| provenanceフィールド | 条件 | 説明 |
|---|---|---|
| `sources` | 必須 | 定義や表現を支える根拠 |
| `publication_status` | 公開判定時に必須 | `candidate`、`approved`、`legacy_migrated`のいずれか |
| `decision_ref` | `approved`で必須 | `proposals/<proposal_key>`形式の承認判断参照 |
| `change_ref` | `approved`で必須 | `changes/<change_key>`形式の適用履歴参照 |
| `legacy_source_ref` | `legacy_migrated`で必須 | 移行前データの参照 |

ポータルへ公開できるのは`publication_status=approved`だけである。
この状態では、2件以上のapprover、`decision_ref`、`change_ref`を必須とする。
`publication_status=approved`では`legacy_source_ref`を禁止する。

## 5. 解析候補モデル

```yaml
proposal_key: customer_id_from_users_table
proposal_operation: add
proposal_schema_version: 1.0.0
target_glossary_key: commerce_platform
base_content_version: 1.9.0
target_content_version: 2.0.0
merge_key: add_customer_id_to_commerce_platform_2_0_0
proposed_term:
  key: customer_id
  term_ja: 顧客ID
  term_en: Customer ID
  definition: 顧客を一意に識別する値
  scope: customer_portal
  category: attribute
  code_name: customerId
  type_name: CustomerId
  db_name: customer_id
  api_name: customerId
  ui_label: 顧客ID
  allowed_values: []
  status: active
  notes: 顧客エンティティの識別属性
  representations:
    - channel: database
      value: customers.customer_id
      location: db/schema.sql:41
  lifecycle:
    status: active
    introduced_in: 2.0.0
  stewardship:
    approvers: [business-reviewer, architecture-reviewer]
  provenance:
    sources:
      - type: database_schema
        ref: db/schema.sql:41
        supports: db_name
proposal:
  extracted_facts:
    - subject: customers.customer_id
      predicate: declared_as
      object: uuid_primary_key
      evidence_ref: db/schema.sql:41
  inferences:
    - field: definition
      statement: 顧客を一意に識別する値
      basis: 主キー名と参照関係から推定
  evidence:
    - ref: db/schema.sql:41
      excerpt_hash: sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
      observed_at: 2026-08-01T00:00:00Z
      source_revision: abc1234
  confidence:
    score: 0.86
    level: high
    rationale: DB主キーとAPI名が一致するが業務文書の定義は未確認
  approval:
    status: needs_review
    reviewers: []
    reviewed_at: null
    decision_reason: null
    events:
      - from: null
        to: detected
        actor: database-analyzer
        actor_role: analyzer
        occurred_at: 2026-08-01T00:00:00Z
        reason: DB定義から候補を検出したため
      - from: detected
        to: needs_review
        actor: glossary-maintainer
        actor_role: maintainer
        occurred_at: 2026-08-01T00:05:00Z
        reason: 構造検査を通過し、人の審査が必要なため
  detected_by:
    skill: analyzing-database-glossary-candidates
    version: 1.0.0
merged_revision: null
```

### 5.1 承認状態

`detected`、`needs_review`、`changes_requested`、`approved`、`rejected`、`deferred`、`merged` を使う。

- `approved` は審査判断が完了した状態で、まだ定義へ反映していない。
- `merged` は定義のcontent versionへ反映した状態である。
- `rejected` と `deferred` は理由を必須にする。

`proposed_term` は、採用後に作るレコードの完成形を保持する。
審査前でも、予定するlifecycle、approver、導入versionを埋める。
値を確定できない候補は `changes_requested` または `deferred` とし、approvedへ遷移させない。

`proposal_operation` は後方互換のためschema上は任意だが、registryを使う審査では必須である。
`add` は同じ用語keyが存在しない場合だけ許可し、`update` は対象用語keyが存在する場合だけ許可する。
省略した旧proposalは `review_required` として停止し、人が `add` または `update` を補完する。
collision比較から既存の同一key用語を除外するのは `update` の時だけである。

承認操作は `proposal.approval` だけを更新する。
管理Skillはapprovedの提案を再検証し、`proposed_term` を変更せずに用語集へ追加してからapprovalをmergedへ更新する。

状態遷移は次の表に限定する。

| 遷移元 | 遷移先 | 許可する役割 |
|---|---|---|
| なし | `detected` | analyzer |
| `detected` | `needs_review` | maintainer |
| `needs_review` | `changes_requested`、`rejected`、`deferred` | steward、business_approver、technical_approver |
| `changes_requested` | `needs_review` | steward |
| `needs_review` | `approved` | 両承認記録を確認したmaintainer |
| `approved` | `merged` | maintainer |
| `approved` | `needs_review` | base versionが古くなった時のmaintainer |

business_approverとtechnical_approverはreviewersへ各自の判断を記録する。
両者のdecisionがapprovedの場合だけ、maintainerが状態をapprovedへ遷移させる。

各遷移はeventsに、遷移前後、actor、actor_role、時刻、理由を追記する。
実行基盤のidentityとactorを照合し、解析Skillの自己申告だけではapprovedへ遷移できないようにする。
actorと変更履歴のrequested_byはtrim後に空文字であってはならない。
eventsの時刻は単調非減少とし、全reviewerのdecided_at、reviewed_at、approved/merged eventの順序を守る。

`base_content_version` は審査を開始した用語集versionである。
merge時に現在versionと一致しない場合は再baseと再検証を要求する。
この場合はapprovedからneeds_reviewへ戻し、reviewersを空にしてbase versionを更新する。
衝突解消でproposed_termを変えた場合も、同じ手順で再審査する。
`merge_key` の二重適用を禁止し、成功後に `merged_revision` を記録する。

### 5.2 信頼度

scoreは0以上1以下とし、levelは次の境界で決める。

| level | score | 用途 |
|---|---|---|
| `high` | 0.80以上 | 複数の独立根拠が一致している |
| `medium` | 0.50以上0.80未満 | 根拠はあるが定義境界が未確認である |
| `low` | 0.50未満 | 名称や局所文脈からの推定が中心である |

信頼度は承認の代替ではない。
highでも人の承認を省略しない。

### 5.3 変更履歴モデル

変更履歴は、1回の定義反映を1レコードとして保存する。

| フィールド | 必須 | 説明 |
|---|---|---|
| `change_key` | 必須 | 変更内容を表す意味key。二重適用防止にも使う |
| `glossary_key` | 必須 | 変更した論理registry |
| `change_type` | 必須 | add、update、deprecate、retire、split、merge |
| `affected_term_keys` | 必須 | 影響した用語key |
| `proposal_key` | 任意 | 解析候補からの変更なら元提案を指す |
| `proposal_content_hash` | proposal由来で必須 | 承認対象proposal snapshotのcanonical SHA-256 |
| `base_content_version` | 必須 | 変更前version |
| `target_content_version` | 必須 | 変更後version |
| `before_hash` | 任意 | 変更前レコードのhash |
| `after_hash` | 必須 | 3つの公開用fieldだけを除く適用後affected term配列のcanonical SHA-256 |
| `requested_by` | 必須 | 変更要求者 |
| `approved_by` | 必須 | 承認者一覧 |
| `reason` | 必須 | 変更理由 |
| `evidence` | 任意 | 提案の観測証拠 |
| `proposal_audit` | proposal由来で必須 | 推定、信頼度、判断理由、reviewer、承認event、検出Skillの監査snapshot |
| `applied_at` | 必須 | 反映時刻 |
| `applied_revision` | 必須 | Git revisionまたは同等の不変参照 |

履歴は追記専用とし、同じchange_keyを再適用しない。
`after_hash`は、`affected_term_keys`順に対応する適用後termをkey順JSON・空白なし・UTF-8でcanonical化して算出する。
hash対象から`provenance.publication_status`、`decision_ref`、`change_ref`を除外する。
`legacy_source_ref`はhash対象から除外しない。
proposal由来の適用では、各termの`decision_ref`を`proposals/<proposal_key>`にする。
同様に、`change_ref`を`changes/<change_key>`にし、参照先と厳格に結合する。
`proposal_key`を持つ履歴は、registry内の同key proposalがちょうど1件存在する場合だけ有効である。
参照先proposalは、対象glossaryとbase/target versionが一致し、status=`approved|merged`でなければならない。
proposal由来changeでは、`evidence`と`proposal_audit`を必須とする。
`proposal_audit`の`decision_reason`は空白以外の文字を含める。
changeの`evidence`は参照先proposalの`evidence`と一致させる。
changeの`proposal_audit`は、参照先proposalの監査snapshotと一致させる。
`inferences`、`confidence`、`detected_by`は、proposalの同名fieldと一致させる。
`decision_reason`と`reviewers`は、proposalの`approval`内にある同名fieldと一致させる。
`approval_events`は、proposalの`approval.events`と一致させる。
proposal由来changeでは、参照先proposalの`proposal_operation`を`add|update`に限定する。
この値は`change_type`と一致させる。
`affected_term_keys`は、参照先`proposed_term.key`だけを持つ1要素配列とする。
別の操作や用語への承認流用は禁止する。
changeのapplied_atは全reviewer判断とapproval event以後にする。

## 6. バリデーション

### 6.1 error

- 必須フィールドが欠けている。
- schemaにない列挙値を使っている。
- `key` がregistry内で重複している。
- keyが重複している。
- `target_key`、`replaced_by`、scope参照が存在しない。
- `replaced_by` が循環している。
- activeまたはdeprecatedの用語に根拠がない。
- activeの用語に承認者記録がない。
- 解析候補を承認状態なしで定義へ取り込もうとしている。
- proposalのextracted_facts.evidence_refが同proposalのevidence.refを参照しない、またはevidence.refが重複している。
- evidenceのexcerpt_hashが`sha256:`に続く64桁の小文字16進数でない。
- proposal由来changeを参照先proposalへ一意に結合できない。
- proposalが未承認、version不一致、操作種別・対象用語不一致、または監査snapshot不一致である。
- 承認event、reviewer判断、reviewed_at、applied_atの時系列が逆転している。
- 連番、UUID、ハッシュだけで構成した意味のないkeyを使っている。

### 6.2 warning

- 定義が代表表記の言い換えだけである。
- 類義度が高い既存用語がある。
- labelまたはaliasが既存用語と衝突している。
- 1年以上根拠参照を再確認していない。
- representationのlocationが実在しない。
- 未使用候補だが、法令、契約、移行資料の確認が終わっていない。
- 承認者記録が長期間更新されていない、または参照先のチームが廃止されている。

### 6.3 review_required

- 定義の対象範囲が変わる。
- keyを変更する。
- activeからdeprecatedへ遷移する。
- 別名を禁止表記へ移す。
- scopeを広げるまたは狭める。
- security classificationを変更する。

## 7. 命名ルール

- keyはASCII小文字のsnake_caseを使う。
- keyは概念の意味を表し、表示順、連番、UUID、ハッシュを含めない。
- 単数形を原則とする。集合そのものが概念なら複数形を許可する。
- `_id` は業務上または連携上の識別子概念にだけ使う。
- `_status`、`_type`、`_code` は定義できる区分概念にだけ使う。
- 略語は業界標準または用語集内で定義済みの場合だけ使う。
- 同名異義がある場合は、意味を表す限定語を前置する。例は `sales_order` と `purchase_order` である。
- `data`、`info`、`item`、`value`、`master`を単独で使わない。
- 廃止keyを別の意味で再利用しない。

## 8. YAML schemaの配置

YAMLスキーマ成果物は、`generation-engine/schemas/semantic-glossary/1.0.0/`の正式schemaが満たす。
設計用draftを別に維持せず、実行時と設計レビューで同じschemaを参照する。

- `glossary.schema.yaml`: 承認済み用語
- `proposal.schema.yaml`: 解析候補
- `change.schema.yaml`: 変更履歴
- `validation-report.schema.yaml`: 検証結果

`generation-engine/scripts/glossary/validate-semantic-glossary.sh`が、これらを使って入力を検証する。
構造の判定、fixture、validator、設計レビューは正式な1.0.0 schemaを基準にする。
