---
name: generating-naming-rules-for-reverse-docs
description: |
  命名慣行と明示規範を分離採録する。
  TRIGGER when: 命名規約をリバースする時。
  SKIP: 根拠分類が未完了の時。
invocation: generating-naming-rules-for-reverse-docs
type: transform
allowed-tools: [Read, Write, Edit, Bash]
---

# 命名規約リバース

## 入力

分類済み naming 根拠と識別子実例を受け取る。

## 出力

ポータル向け命名規約と、明示規範がある場合だけ `docs/rules/naming/rule.md` を出力する。

## 停止条件

根拠0または明示規範0なら `STOPPED` とし規範 rule.md を作らない。

## 根拠追跡と検証

観測された実装慣行、承認済み規範、根拠パス、観測件数、例外、確信度、未確定事項を `check-rule-reverse-evidence.py` で検証する。

```bash
python3 ../../../shared/scripts/check-rule-reverse-evidence.py --target-repo <target_repo_path> < <rule-evidence-json>
```

`exit 1` の場合は `rule.md` を公開せず `status=STOPPED`、`hint=命名規約根拠検証に失敗` を返す。

## 差し戻し

重複パターンは分類へ、根拠不在は調査へ戻す。

## 完了報告

生成可否、識別子範囲、未確定事項を返す。

## 予想を裏切る挙動

1つの例外的な名前から禁止事項や推奨事項を捏造しない。

## 参照資料

- `../../../shared/references/delivery-reverse-manifest.yml`
- `../../../shared/scripts/check-rule-reverse-evidence.py`
- `../../../shared/scripts/evaluate-delivery-gold.py`
- `../../../shared/references/gold-standard/stacks/typescript-ui/expected-deliverables.json`

<!-- delivery-owner-contracts:start -->
```json
[{"failure_return_to":"orchestrating-reverse-docs-flow","id":"naming-rules","inputs":["rule evidence","identifiers"],"outputs":["プロジェクト共通/命名規約.html","docs/rules/naming/rule.md"],"stop_conditions":["明示規範0"],"validator":"check-delivery-artifacts.sh"}]
```
<!-- delivery-owner-contracts:end -->
