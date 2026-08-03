---
name: generating-glossary-for-reverse-docs
description: |
  コードと既存文書から意味用語の提案候補を生成する。
  TRIGGER when: リバース解析から用語候補を抽出する時、旧用語生成Skill名で呼ばれた時。
  SKIP: 承認済み用語の更新・公開・用語辞書HTML生成時。
invocation: generating-glossary-for-reverse-docs
type: transform
allowed-tools: [Bash, Read, Write, Grep, Glob]
---

# 意味用語の候補生成互換スキル

互換名を維持しながら、リバース解析で観測した語を正式proposal schemaの`detected`候補へ変換する。
正式glossary、承認状態、用語辞書HTMLは変更しない。

## 使用タイミング

- コード、既存文書、API、DB、画面から意味用語の候補を抽出する時。
- 旧`generating-glossary-for-reverse-docs`呼び出しをproposal-only経路へ移行する時。
- 承認済み用語の保守は`maintaining-semantic-glossary`、承認・適用・portal publishは`managing-semantic-glossary`を使う。

## 入出力契約

| 引数 | 必須 | 内容 |
|---|---|---|
| `target_repo_path` | 必須 | 解析対象リポジトリの実在する絶対path |
| `proposal_output_ref` | 必須 | 対象リポジトリ外にある`.yaml`または`.yml`の明示絶対path |
| `target_glossary_key` | 必須 | 審査時に照合する用語集key |
| `base_content_version` | 必須 | 観測時点の用語集version |
| `source_revision` | 必須 | 根拠を採取したrevision |

file出力は次の2点だけとする。加えてwriterは、作成transaction完了時点で確認した各fileの相対name、SHA-256、device、inodeをstdoutのJSON receiptとして返す。

1. `proposal_output_ref`: `proposal.schema.yaml`準拠、approval status=`detected`の提案YAML。
2. `<proposal_output_ref>.diagnostics.json`: 採録源の欠落、未走査層、未解決候補、抽出件数を記録する診断。

出力にglossary root、page-data、HTML、承認済み状態を含めない。

## 基本ワークフロー

## Phase 1: 出力境界の確定

## Step 1-1: 必須引数と外部pathを検証する

1. `target_repo_path`、`proposal_output_ref`、`target_glossary_key`、`base_content_version`、`source_revision`を解決する。
2. `proposal_output_ref`が未指定、相対path、対象リポジトリ自身または配下、symlinkを含む場合は、何も書かず`STOPPED`で終了する。出力先directoryはwriter実行user所有かつmode `0700`を必須とし、group/world権限があれば拒否する。
3. proposalとdiagnosticsはjob用一時領域で組み立てる。外部出力は次のwriterだけに任せ、Write/Editやredirectで`proposal_output_ref`へ直接書かない。

```bash
python3 scripts/write-glossary-proposal-output.py \
  --target-repo "<target_repo_path>" \
  --proposal-output "<proposal_output_ref>" \
  --proposal-input "<job_temp_proposal.yaml>" \
  --diagnostics-input "<job_temp_diagnostics.json>" \
  > "<job_temp_receipt.json>"

python3 scripts/verify-glossary-proposal-receipt.py \
  --receipt "<job_temp_receipt.json>" \
  --output-directory "<proposal_output_directory>" \
  > "<job_temp_verified_bundle.json>"
```

**完了**: 必須引数が揃い、提案出力が対象リポジトリ外だと実pathで証明されている。

## Phase 2: 観測と推定の分離

## Step 2-1: 層化して候補を抽出する

1. `references/glossary-extraction.md`に従い、文書、コード識別子、API、DB、画面を決定的に走査する。
2. 実在位置、`code_name`、`type_name`、`db_name`、`api_name`、`ui_label`、`allowed_values`などの観測事実を`proposal.extracted_facts[]`へ入れる。
3. `key`、`term_ja`、`term_en`、`definition`、`scope`、`category`、`notes`の推定を`proposal.inferences[]`へ入れる。観測事実とは分離する。
4. 根拠は`proposal.evidence[]`へ置き、ref、excerpt_hash、observed_at、source_revisionを保持する。
5. 正式用語は補完しない。根拠不足、採録源欠落、未走査層をdiagnosticsへ記録する。

**完了**: 観測事実、推定、根拠、診断が分離されている。

## Phase 3: detected proposalの生成

## Step 3-1: 正式schemaへ整形する

1. `../../../shared/schemas/semantic-glossary/1.0.0/proposal.schema.yaml`に沿って提案を組み立てる。
2. `proposal.approval.status`は`detected`、`reviewers`は空、`reviewed_at`と`decision_reason`はnullに固定する。
3. 最初のeventは`from: null`、`to: detected`、`actor_role: analyzer`にする。
4. confidenceは根拠量の表示であり、採否や承認へ読み替えない。
5. `write-glossary-proposal-output.py`で`proposal_output_ref`とdiagnostics sidecarを同時に新規作成する。既存file、symlink、hardlink、検査中の親directory差し替えはfail closedとし、`target_repo_path`、正式glossary、portal出力先へ書かない。
6. writerのreceiptを保持し、`verify-glossary-proposal-receipt.py`で各fileを1回だけopenする。
   open fdのSHA-256、device/inode、file種別、link count、read前後identityを検証する。
   同じfdから捕捉したbytesをbase64入りverified bundleとして受け取る。不一致なら`STOPPED`にする。
7. 以後は`proposal_output_ref`を再openしない。validatorや次Skillはverified bundleの捕捉bytesだけを使う。

**完了**: detected以外の承認状態を含まないproposalとdiagnosticsだけが外部pathへ生成されている。

## Phase 4: 機械検証と停止

## Step 4-1: validatorで提案を検証する

1. 正式validatorをproposal kindで実行する。registryが利用可能なら必ず渡す。

```bash
python3 scripts/validate-verified-glossary-proposal-bundle.py \
  --bundle "<job_temp_verified_bundle.json>" \
  --validator ../../../shared/scripts/glossary/validate-semantic-glossary.sh \
  --registry "<registry_path>" \
  --report "<external_report_path>"
```

2. exit 1/2、status=`invalid|unavailable`、error、review_requiredがあれば候補を修正するか`STOPPED`にする。
3. 検証が通ってもproposalをglossaryへ適用せず、`needs_review`として人へ引き渡して停止する。
4. headlessでも自動承認、自動昇格、自動公開をしない。

**完了**: schema検証結果を保持し、proposalは未承認候補のまま審査待ちで停止している。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 外部の明示絶対proposal_output_refが検証済み |
| Phase 2 | 観測、推定、根拠、diagnosticsが分離済み |
| Phase 3 | detected proposalとdiagnosticsだけを外部へ生成済み |
| Phase 4 | validator結果を保持し、needs_reviewで停止済み |
| **Goal** | リバース解析候補が正式用語や用語辞書HTMLへ直接流入せず、人の審査へ渡せる |

## 返却ブロック

| key | 値 |
|---|---|
| `status` | `NEEDS_REVIEW`、`STOPPED`、`ERROR` |
| `artifacts` | 安全に保持したwriter receiptとverified bundle。外部proposal/diagnostics pathは由来metadataでありconsumer入力に再利用しない。停止時は空 |
| `proposal_status` | 成功時は`detected`固定 |
| `glossary_modified` | `false`固定 |
| `portal_published` | `false`固定 |
| `hint` | 不足引数、境界違反、検証finding、未走査領域、次の審査先 |

## ループ設計

| 要素 | 内容 |
|---|---|
| 反復条件 | proposal schema errorまたは根拠参照不整合を修正して再検証する |
| 上限回数 | 3回 |
| 収束停止 | validator error/review_required 0件で`NEEDS_REVIEW`を返す |
| 発散検知 | 同じfindingが2回連続したら`STOPPED`にする |

## 重要な注意事項

- この互換Skillからglossary YAML、page-data、用語辞書HTMLを生成・変更しない。
- `approved`、`merged`、`rejected`、`deferred`へ遷移させない。
- output_dirやportal_output_dirをproposal_output_refの代用にしない。
- 対象リポジトリ外という条件を文字列prefix比較だけで判定せず、実pathとsymlinkを解決する。
- writer receiptは作成transactionで生成したbytesを証明する。receipt発行後に同じpathで読める現在値やpathの継続不変性は証明しない。
- consumerはreceiptを安全に引き渡し、verifierが1回のopenで捕捉したverified bundleのbytesだけを使う。検証後に元pathを再openしない。
- 長期保管が必要ならreceiptとverified bundleをprotected storageへ保存する。元pathの永続真正性へ読み替えない。
- 人向け用語辞書は承認済みglossary YAMLを`managing-semantic-glossary`のportal publishへ渡す別経路だけで生成する。

## 予想を裏切る挙動

- 旧名に`generating-glossary`を含むが、生成するのは正式用語集やHTMLではなく未承認proposalである。
- headlessは承認不要モードではない。対話不能でも`NEEDS_REVIEW`で終端する。

## ツールリファレンス

- Read/Grep/Glob: 観測事実と根拠を抽出する。
- Bash: 外部path検証と正式validatorだけを実行する。
- Write: job用一時入力とreceiptだけへ書く。外部proposalとdiagnosticsの作成はsafe writerだけが行う。

## 参照資料

- 抽出規則: `references/glossary-extraction.md`
- テスト観点: `references/test-cases.md`
- ガイド: `references/generating-glossary-for-reverse-docs-guide.html`
- proposal schema: `../../../shared/schemas/semantic-glossary/1.0.0/proposal.schema.yaml`
- 連携仕様: `../../../docs/design/リバース解析・関連Skill連携仕様.md`

## 完了報告

`~/agent-home/skills/managing-agent-configs/references/skills/completion-report-format.md`の作業報告型に従う。
検証欄へproposal外部path、proposal status、validator exit、glossary未変更、portal未公開を追加する。
