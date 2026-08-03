# Semantic Glossary 共通契約 v0.1

状態: `frozen`

review_amended: `2026-08-02`

| 項目 | 値 |
| --- | --- |
| contract_version | `0.1.6` |
| schema_version | `1.0.0` |

v0.1内では既存フィールドおよび診断codeの意味を変更してはならない。追加のみ後方互換で認める。

## 変更履歴

- `0.1.6 (2026-08-02)`: `proposal_audit.decision_reason`を必須化する。
  canonical proposalの承認理由と完全一致させる。
  意味内容のhashと承認監査snapshotを分離し、承認理由の事後改変も拒否する。
  migration: 既存changeへ承認時点の理由を補完し、proposalと一致しない記録は再承認する。
- `0.1.5 (2026-08-02)`: canonical proposalのschema通過だけでなく、承認時系列・actor・reasonを含む全意味検証をchange経由でも必須化。changeの適用後term状態とcanonical SHA-256、公開termのproposal/change実在結合、projectorのregistry必須化、`changeRef`投影を追加。migration: 公開termのrefを`proposals/<proposal_key>`/`changes/<change_key>`へ正規化し、承認者と適用後hashを再計算する。自己申告refだけの既存termは再承認まで公開しない。
- `0.1.4 (2026-08-02)`: proposal承認対象の完全snapshot hashとportal公開状態を追加。
  decision/change provenanceも追加した。migrationでは既存changeへcanonical SHA-256を補完する。
  承認証跡を確認できるtermには公開状態と参照を補完する。
  確認できない移行データは`legacy_migrated`として再承認まで公開しない。
- `0.1.3 (2026-08-02)`: Aはchangeの操作種別・対象用語を定義proposalと結合した。
  別操作・別用語への承認流用を禁止した。Bは旧reverse入口を外部proposal出力だけに制限した。
  Cはportal投影と候補監査keyの遮断を追加した。
  migration: 既存proposalへ操作種別を補完し、旧用語HTMLはlegacy表示または再審査へ送る。
- `0.1.2 (2026-08-02)`: proposal定義とchange snapshotの結合検証、`proposal_operation`、承認時系列、根拠参照・SHA-256検証を追加。migration: 既存proposalは読込可能だが、registry付き審査前に`proposal_operation: add|update`を補完する。省略時は`review_required`として自動適用しない。
- `0.1.1 (2026-08-01)`: reviewでalias/forbidden衝突、安全JSON埋込、承認済みYAML→page-data投影CLIを追加。`0.1.0`は初回freeze案。migration: 実装前のためデータ移行なし。

## 1. 目的と境界

- 承認済み用語（glossary）、解析候補（proposal）、変更履歴（change）を別YAML文書として管理する。
- reverse解析はproposalのみを生成し、glossaryを直接変更してはならない。
- 今回の対象は正式schema/validator、用語管理・用語保守・proposal-only reverse入口の3 Skill、承認済み用語のportal投影である。分野別adapter、AI index、production registry、外部identity provider、署名済み外部anchor、候補審査画面は対象外とする。

## 2. 正式配置

| 種別 | 配置 |
| --- | --- |
| schema | `shared/schemas/semantic-glossary/1.0.0/glossary.schema.yaml` |
| proposal schema | `shared/schemas/semantic-glossary/1.0.0/proposal.schema.yaml` |
| change schema | `shared/schemas/semantic-glossary/1.0.0/change.schema.yaml` |
| validation report schema | `shared/schemas/semantic-glossary/1.0.0/validation-report.schema.yaml` |
| validator | `shared/scripts/glossary/validate-semantic-glossary.sh` および `.py` |
| requirements | `shared/scripts/glossary/requirements.txt` |
| fixtures/tests | `shared/scripts/glossary/fixtures/`、`shared/scripts/glossary/tests/` |
| skills | `.claude/skills/managing-semantic-glossary/`、`.claude/skills/maintaining-semantic-glossary/`、`.claude/skills/generating-glossary-for-reverse-docs/` |
| portal基準テンプレート | `shared/templates/detail-pages/detail-t2-dictionary.html` |
| portal projection CLI | `shared/scripts/detail-pages/project-semantic-glossary.py` |
| サンプル | `shared/samples/一覧/用語辞書/用語辞書.html` |

production registryは作らず、`--input`/`--registry` のpath引数で受ける。

## 3. 文書契約

- UTF-8 YAML単一documentとする。
- kind `glossary|proposal|change` はCLI引数で指定し、ファイル混在を禁止する。
- meaningful snake_case keyを用い、global logical registryで一意にする。意味のない連番、UUID、汎用語のみを禁止する。
- proposalの`proposal_operation`は後方互換のoptional列とする。registry付き検証では省略を`review_required`にし、`add`は既存keyをerror、`update`は対象key不存在をerrorとする。既存termをcollision比較から除外するのは`update`だけとする。
- `extracted_facts[].evidence_ref`は同proposalの一意な`evidence[].ref`へ結合する。
  `excerpt_hash`は`sha256:`と64桁の小文字16進数で構成する。
- YAML構造と意味制約は、`shared/schemas/semantic-glossary/1.0.0/`の正式schemaを基準にする。

## 4. CLI

```text
shared/scripts/glossary/validate-semantic-glossary.sh \\
  --kind <glossary|proposal|change> \\
  --input <file> \\
  [--registry <file-or-dir>] \\
  [--report <json>]
```

- stdoutは人向け要約、stderrは実行障害、reportはJSONとする。
- exit `0`: errorなし（warning/review_required許容）。
- exit `1`: validation error。
- exit `2`: usage/dependency/parse/internal/走査不能。
- 変更適用Skillは`review_required`もblockingとする。
- 依存はPython 3.13、`PyYAML>=6,<7`、`jsonschema[format]>=4.23,<5`。worktree venvへ導入し、グローバルinstallを禁止する。依存不足はexit `2`とする。

## 5. report

rootは`{contractVersion,status,sourceKind,sourceRef,counts,findings}`とする。

- statusは`valid|invalid|unavailable`。
- countsはerror/warning/review_required。
- findingは`{severity,code,path,message,relatedRefs}`。
- severityはerror、warning、review_requiredの3種。
- code prefixは次のとおり。

| prefix | 領域 |
| --- | --- |
| `SGS_` | schema（required/type/enum/pattern） |
| `SGK_` | key（duplicate/meaningless） |
| `SGR_` | ref（missing/cycle） |
| `SGL_` | lifecycle |
| `SGP_` | proposal state/approval/stale base |
| `SGV_` | version |
| `SGD_` | dependency/parse/internal |

codeは追加できるが、意味を変更してはならない。findingはseverity、code、path、messageの決定順とする。

## 6. 意味検証最小範囲

- key重複、無意味key。
- alias同士、aliasとlabel、forbidden termと許可表記の正規化衝突を検出し、自動統合しない。
- scope_catalog/term/relation/replacement参照切れ。
- relation/replacement循環。
- lifecycle必須組合せ。
- proposalの状態遷移、二者承認、stale base/target version。
- approval eventsの時刻単調性と、reviewer判断からapproval/mergeまでの時系列。
- actorとrequested_byはtrim後も空でない値とする。
- proposal statusがapprovedまたはmergedの場合、`approval.decision_reason`をtrim後も空でない値として必須にする。
- proposal_key付きchangeはregistryの定義proposalへ一意に結合する。
  `proposal_operation`は`add|update`のいずれかで、`change_type`と完全一致させる。
  `affected_term_keys`は`proposed_term.key`だけを持つ1要素配列とする。
  対象glossary、version、状態、監査snapshot、applied_atの時系列も検証する。
  `proposal_audit.decision_reason`は空でない値とし、canonical proposalの承認理由と一致させる。
- `proposal_content_hash`はproposalの意味内容に対するattestationである。
  key、operation、対象glossary、version、merge_key、proposed_term、根拠、推定、confidence、検出元を対象とする。
  対象をkey順JSON・空白なし・UTF-8でcanonical化し、SHA-256と完全一致させる。
  承認後の意味内容改変はerrorにする。承認判断metadataはこのhashへ混在させない。
  承認判断metadataは`proposal_audit`の完全一致snapshotとして検証する。
- changeが参照するcanonical proposalはschema検証と意味検証の両方を通す。
  confidence、evidence、状態遷移、時系列、理由、actor、role、適用状態を検証する。
  errorまたはblockingなreview_requiredがあればchangeを拒否する。
- `after_hash`はaffected term snapshotから算出する。
  除外列は`publication_status`、`decision_ref`、`change_ref`の3項目だけとする。
  `legacy_source_ref`はhash対象から除外しない。
  termをkey順配列にし、key順JSON・空白なし・UTF-8でcanonical化する。
  add/updateは承認済み`proposed_term`と適用後termを一致させる。
  retireは全termをretiredとする。mergeはactive survivorを1件だけ残す。
  retired sourceの`replaced_by`はsurvivorを参照する。addの`before_hash`はnullとする。
- `publication_status`は`candidate|approved|legacy_migrated`のいずれかとする。
  portalへ公開できるのは`approved`だけで、role-qualified approverを2件必須とする。
  `decision_ref`と`change_ref`はregistry内の実在文書へ一意に解決する。
  解決したchangeの`proposal_key`はnon-null文字列で、decision proposalの`proposal_key`と一致させる。
  manual/null changeによる迂回を認めず、proposal/changeの承認、operation、content hash、audit snapshot、term key、approver、version、適用後term/hashを照合する。
  自己申告文字列だけのrefはerrorとする。公開対象外の状態はreview_requiredとする。
  legacy_migratedは`legacy_source_ref`を必須にし、再承認まで公開しない。
  再承認してapprovedへ遷移する際は`legacy_source_ref`を除去し、approvedとの併存をerrorにする。
- schema/content version。
- 0件と走査不能を区別する。

## 7. portal projection v0.1

- 投影前にA CLIを次の形式で実行する。

  ```text
  shared/scripts/glossary/validate-semantic-glossary.sh \
    --kind glossary \
    --input <glossary.yaml> \
    --registry <canonical-registry> \
    --report <validation-report.json>
  ```

- exit `1`または`2`の場合は、出力fileを作らず停止する。
- `counts.error>0`または`counts.review_required>0`の場合も、出力fileを作らず停止する。
- warningだけの場合は投影できる。
- 入力のschema/content versionは正式schemaと一致しなければならない。
- projection CLIは次の形式とする。

  ```text
  python3 shared/scripts/detail-pages/project-semantic-glossary.py \
    --input <glossary.yaml> \
    --registry <canonical-registry> \
    --output <page-data.json>
  ```

- 入力は正式glossary、出力はprojection v0.2とする。
- status=`retired`も出力する。UI通常一覧はactive/deprecatedを表示し、履歴filter時だけretiredを表示する。
- 標準14フィールドは同名のまま投影し、用途の異なる名称を集約しない。
- `provenance.sources`を`sourceRefs`、`provenance.decision_ref`を`decisionRef`へ写像する。
- `provenance.change_ref`を`changeRef`、`stewardship.approvers`を`approvers`へ写像する。
- `lifecycle.status`を`status`へ写像する。
- aliases/forbidden_terms/relations/その他をcamelCase page-dataへ決定変換する。
- 未承認proposal/changeは入力を拒否する。source YAMLは変更しない。
- rootは既存keyに`projectionVersion`、`glossarySchemaVersion`、`glossaryContentVersion`を追加する。
- categories keyは`entity`、`attribute`、`value`、`process`、`event`、`role`、`rule`、`metric`。
- terms新形式には必須項目と任意項目がある。
- 先頭の必須14項目は次のとおり。
  - `key`、`term_ja`、`term_en`、`definition`、`scope`、`category`、`code_name`
  - `type_name`、`db_name`、`api_name`、`ui_label`、`allowed_values`、`status`、`notes`
- 追跡のため`representations`と`sourceRefs`も必須とするが、ポータル標準列には追加しない。
- 任意項目は`aliases`、`forbiddenTerms`、`relations`、`examples`を含む。
- `counterExamples`、`constraints`、`securityClassification`、`notes`も任意項目とする。
- representationはchannel/value/location。
- 一覧列は標準14項目を上記順序・上記列名で表示する。
- 詳細drawerは、aliases、禁止語、全representations、relations、例/反例、constraints、security、全根拠。
- 候補は混在表示しない。

## 8. legacy互換

- 旧`{term,definition,codeRefs,category,sourceRef}`を受理する。新旧の同一terms配列混在はerror。
- 表示時のみ`term`→`term_ja`へ写像し、値が存在しない標準列は空値として扱う。
- 欠落keyは生成せず`未移行`とする。
- 入力page-dataファイルは変更しない。
- HTMLの`application/json`へ埋め込むときは、script終端注入を防ぐため`<`をUnicode escapeする。
- JSON文字列にliteral U+2028またはU+2029が存在するとき、それぞれUnicode escapeする。
- 検証はbyte一致ではなく、埋込JSONと入力JSONをparseしてkey順を正規化した意味一致で行う。
- legacy受理はwarningとし、reverse adapter完了後の次majorで廃止候補とする。

## 9. 並行所有権

- Aはschemas/scripts/glossaryのみを担当する。
- Bは次の3 Skill dirだけを担当する。
  - `.claude/skills/managing-semantic-glossary/`。
  - `.claude/skills/maintaining-semantic-glossary/`。
  - `.claude/skills/generating-glossary-for-reverse-docs/`。
- Cは次の資産だけを担当する。
  - T2 template。
  - page-data-schema.md。
  - validate-page-data.sh。
  - build-detail-page.sh。
  - project-semantic-glossary.py。
  - sample。
  - C専用test。
- 契約fileは各担当が変更してはならない。統合担当だけが横断修正する。

## 10. publish境界

- 今回のmanagement Skillのpublish targetはportalのみとする。
- `ai_index` targetは`review_required`/`not_implemented`で停止し、成果物を出さない。
- AI indexは別タスクとする。

## 11. 完了条件

- Aは正常/異常fixture、stable report/exitを満たす。
- Bは未承認更新禁止/dry-run/error+review_required停止を満たす。
- Cはlegacy継続、新形式描画、混在拒否、XSS/keyboard/mobile/安全escape後の意味一致を満たす。
- 統合時にAのpath/codeとB参照、C page-data検証を照合する。

## 12. 変更管理

- 変更提案は契約versionを上げ、A/B/Cへの影響とmigrationを記録する。
- 破壊変更はmajor相当とする。
- contract frozen後に担当者が独自拡張してはならない。

## 13. 信頼境界と未決事項

- 現行hash/ref検証は、同じ検証時点のglossary・proposal・change間のdriftを検出する。
  可変filesystem上のartifactとhashが同時改変された場合、その集合だけでは改変前の定義を識別できない。
  「改変を必ず検知する」とは主張しない。
- 同時改変耐性には、保護されたGit履歴、署名付きtag/commit、透明性log、または署名済み外部anchorのいずれかを信頼境界として必須とする。外部anchorが固定する値は最低でもregistry revisionとcanonical root hashである。
- production registry、外部identity provider、署名済み外部anchorの実装・鍵管理・失効手順・検証可用性は現行scope外の未決事項とする。導入まではportalを「artifact間drift検証済み」と表現し、「耐改ざん」または「真正性保証済み」と表現しない。
