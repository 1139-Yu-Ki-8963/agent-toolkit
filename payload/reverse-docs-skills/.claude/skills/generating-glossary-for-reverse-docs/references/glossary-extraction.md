# 用語候補の抽出ガイダンス

`generating-glossary-for-reverse-docs` が、観測事実と推定を分離した未承認proposalを作るための抽出規則である。正式用語集、page-data、HTML、承認状態は扱わない。

## 採録層

文書層とコード層を独立に走査する。文書層は共通設計、データ設計、UI文言、メッセージ定義、アーキテクチャ調査を対象とする。コード層は調査書のディレクトリ責務マップを層として使い、層内を決定的順序で選ぶ。走査できなかった層や入力はdiagnosticsの `missingSources` と `unscannedLayers` に残す。

非テキストは `generation-engine/scripts/detect-encoding.sh encoding <file>` が復号不能とした場合に除外する。除外件数、全候補数、比率、警告をdiagnosticsへ記録し、0件抽出と走査不能を区別する。

## 識別子の復元

1. camelCase、PascalCase、snake_case、SCREAMING_SNAKE_CASEを構成語へ分ける。
2. 文書または使用文脈に根拠がある隣接2〜3語だけを意味のある複合語候補へ戻す。
3. 単独の `id` のような汎用語は除外するが、`customer_id` のように対象概念を特定する識別子は候補にできる。
4. 意味を一義的に説明できない候補は捨てず、diagnosticsの `unresolvedCandidates` に理由付きで残す。

## proposalへの写像

- 観測した表記、識別子、パス、行は `proposal.extracted_facts[]` に置く。抜粋hashは `proposal.evidence[]` に置く。
- 意味、分類、alias、推奨keyは `proposal.inferences` と `proposed_term` に置き、観測事実として扱わない。
- confidenceは根拠量の表示であり、承認判定に使わない。
- `proposal.approval.status` は常に `detected`、reviewersは空配列とする。
- 定義、scope、keyが確定できない場合も値を捏造せず、レビュー要求として残す。

## 除外既定

ドメイン概念を持たない一般英単語、フレームワーク標準API、機械的なgetter/setter接頭辞、局所的なループ変数を候補から除外する。複合語全体に業務上の意味がある場合は、構成語に除外語が含まれていても複合語を除外しない。

## 出力境界

抽出結果は、生成前に検証済みの対象repo外 `proposal_output_ref` と隣接diagnostics JSONだけへ書く。走査記録を対象repoや `<output_dir>` に残さない。headlessでも自動承認せず、正式validator通過後に `NEEDS_REVIEW` で停止する。
