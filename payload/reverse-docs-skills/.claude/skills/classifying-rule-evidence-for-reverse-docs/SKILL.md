---
name: classifying-rule-evidence-for-reverse-docs
description: |
  規約根拠を主カテゴリと層へ分類する。
  TRIGGER when: 規約台帳の分類、重複除去時。
  SKIP: 根拠探索が未完了の時。
invocation: classifying-rule-evidence-for-reverse-docs
type: transform
allowed-tools: [Read, Write, Edit, Bash]
---

# 規約根拠分類

## 入力

規約ソース台帳を受け取る。

## 出力

manifest の `rule_evidence_contract.classification_fields` と一致する `records[]` 分類表を出力する。

## 手順

1. manifestに定義された20カテゴリのいずれかへ一意に主分類する。
2. architecture/coding は layer、testing/review は kind を必須化する。
3. 同一 dedupe key は一件に統合し参照だけを残す。

## 停止条件

カテゴリ・層・種別を確定できない根拠は `STOPPED` にする。

## 根拠追跡と検証

分類表の各行は台帳のID、相対パス、excerpt、evidence kind、source SHA-256を変更せず保持する。

検証コマンド:

```bash
python3 ../../../shared/scripts/check-rule-reverse-evidence.py --mode classification --survey-ledger <survey-ledger-json> --target-repo <target_repo_path> < <classified-evidence-json>
```

`exit 1` の場合は分類結果を確定せず `status=STOPPED`、`hint=分類済み根拠が検証契約に不適合` を返す。

## 差し戻し

パス不在・種別不明は根拠調査へ戻す。

## 完了報告

分類件数、重複統合数、停止件数を返す。

## 予想を裏切る挙動

複数カテゴリに見える根拠でも主カテゴリは1つだけで、他は参照関係にする。

## 参照資料

- `../../../shared/references/delivery-reverse-manifest.yml`
- `../../../shared/scripts/check-rule-reverse-evidence.py`
- `../../../shared/scripts/evaluate-delivery-gold.py`
- `../../../shared/references/gold-standard/stacks/typescript-ui/expected-deliverables.json`
