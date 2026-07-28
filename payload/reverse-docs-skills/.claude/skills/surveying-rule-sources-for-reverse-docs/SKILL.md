---
name: surveying-rule-sources-for-reverse-docs
description: |
  規約候補の一次根拠を台帳化する。
  TRIGGER when: 規約根拠の探索、rulesリバース開始時。
  SKIP: 既に分類済みの根拠を文書化する時。
invocation: surveying-rule-sources-for-reverse-docs
type: audit
allowed-tools: [Read, Grep, Glob, Bash]
---

# 規約ソース調査

## 入力

対象リポジトリ、README、文書、設定、lint/format、CI、hook、コメント、実例、Git履歴を読む。

## 出力

manifest の `rule_evidence_contract.survey_fields` と一致する `records[]` 台帳を返す。各行は `id`・`evidence_path`・原文と完全一致する `excerpt`・`evidence_kind`・`source_sha256` を持つ。

## 手順

1. 各根拠種別を探索し、未検出も台帳に記録する。
2. 規範と実装慣行を混在させず、分類スキルへ渡す。
3. 根拠パス実在を確認する。

## 停止条件

読取不能・根拠なしでは推測せず `STOPPED` と未確定事項を返す。

## 根拠追跡と検証

各行に相対パス・種別・観測位置を残し、存在しないパスは除外する。

検証コマンド:

```bash
python3 ../../../shared/scripts/check-rule-reverse-evidence.py --mode survey --target-repo <target_repo_path> < <evidence-json>
```

`exit 1` の場合は成果物を確定せず `status=STOPPED`、`hint=根拠記録の形式またはパスが不正` を返す。

## 差し戻し

分類不能な根拠は調査へ戻す。

## 完了報告

台帳パス、根拠件数、未確定事項、次の分類対象を報告する。

## 予想を裏切る挙動

コード例は規範ではない。明示文書・設定・CI等の規範根拠と区別する。

## 参照資料

- `../../../shared/references/delivery-reverse-manifest.yml`
- `../../../shared/scripts/check-rule-reverse-evidence.py`
- `../../../shared/scripts/evaluate-delivery-gold.py`
- `../../../shared/references/gold-standard/stacks/typescript-ui/expected-deliverables.json`
