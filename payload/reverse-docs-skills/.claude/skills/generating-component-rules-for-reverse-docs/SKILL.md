---
name: generating-component-rules-for-reverse-docs
description: |
  コンポーネント慣行と明示規範を分離採録する。
  TRIGGER when: コンポーネント設計規約をリバースする時。
  SKIP: layerが未指定の時。
invocation: generating-component-rules-for-reverse-docs
type: transform
allowed-tools: [Read, Write, Edit, Bash]
---

# コンポーネント規約リバース

## 入力

分類済み architecture 根拠と必須の `layer` を受け取る。

## 出力

ポータル向けコンポーネント設計規約と、明示規範がある場合だけ `docs/rules/architecture/<layer>/rule.md` を出力する。

## 停止条件

根拠0または明示規範0なら `STOPPED` とし規範 rule.md を作らない。

## 根拠追跡と検証

観測された実装慣行、承認済み規範、根拠パス、観測件数、例外、確信度、未確定事項を `check-rule-reverse-evidence.py` で検証する。

```bash
python3 ../../../shared/scripts/check-rule-reverse-evidence.py --target-repo <target_repo_path> < <rule-evidence-json>
```

`exit 1` の場合は `rule.md` を公開せず `status=STOPPED`、`hint=コンポーネント規約根拠検証に失敗` を返す。

## 差し戻し

layer不明は分類へ戻す。

## 完了報告

layer、生成可否、未確定事項を返す。

## 予想を裏切る挙動

コンポーネントの分割理由や意図を実装だけから断定しない。

## 参照資料

- `../../../shared/references/delivery-reverse-manifest.yml`
- `../../../shared/scripts/check-rule-reverse-evidence.py`
- `../../../shared/scripts/evaluate-delivery-gold.py`
- `../../../shared/references/gold-standard/stacks/typescript-ui/expected-deliverables.json`

<!-- delivery-owner-contracts:start -->
```json
[{"failure_return_to":"orchestrating-reverse-docs-flow","id":"component-rules","inputs":["rule evidence","component code"],"outputs":["プロジェクト共通/コンポーネント設計規約.html","docs/rules/architecture/<layer>/rule.md"],"stop_conditions":["明示規範0"],"validator":"check-delivery-artifacts.sh"}]
```
<!-- delivery-owner-contracts:end -->
