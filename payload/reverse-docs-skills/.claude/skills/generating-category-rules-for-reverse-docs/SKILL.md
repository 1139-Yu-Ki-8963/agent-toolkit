---
name: generating-category-rules-for-reverse-docs
description: |
  分類済み根拠からカテゴリ別規約を生成する。
  TRIGGER when: rulesカテゴリのリバース、明示規範の採録時。
  SKIP: 根拠分類が未完了の時。
invocation: generating-category-rules-for-reverse-docs
type: transform
allowed-tools: [Read, Write, Edit, Bash]
---

# カテゴリ規約生成

## 入力

分類済み根拠、`category`、architecture/coding の `layer`、testing/review の `kind` を受け取る。

`category`は次の20種から選ぶ。

- 運用系: `agent-operation`、`safety`、`development-flow`、`tool-execution`、`environment`
- 協働系: `communication`、`session`、`ai-configuration`、`git`
- 実装系: `placement`、`naming`、`architecture`、`coding`、`testing`、`review`
- 横断系: `security`、`delivery`、`documentation`、`portal`、`routines`

## 出力

観測慣行と承認済み規範を別形式で持つ記録、および明示規範がある場合だけ `docs/rules/<category>/.../rule.md` を出力する。

## 手順

1. 20カテゴリから `category` を選ぶ。
2. 観測値は事実として記録し、規範は明示根拠だけを採録する。
3. `check-rule-reverse-evidence.py` で記録を検証する。

## 停止条件

根拠0件または明示規範0件では `rule.md` を作らず `STOPPED` と未確定事項を出力する。

## 根拠追跡と検証

evidence_paths、observation_count、exceptions、confidence、uncertainties を必須にする。

検証コマンド:

```bash
python3 ../../../shared/scripts/check-rule-reverse-evidence.py --target-repo <target_repo_path> < <rule-evidence-json>
```

`exit 1` の場合は `rule.md` を公開せず `status=STOPPED`、`hint=規約根拠検証に失敗` を返す。

## 差し戻し

検証失敗は分類または調査へ戻す。

## 完了報告

category、layer/kind、生成可否、根拠件数を返す。

## 予想を裏切る挙動

多数のコード例があっても明示規範がなければ規範文書は生成しない。

## 参照資料

- `../../../shared/references/delivery-reverse-manifest.yml`
- `../../../shared/scripts/check-rule-reverse-evidence.py`
- `../../../shared/scripts/evaluate-delivery-gold.py`
- `../../../shared/references/gold-standard/stacks/typescript-ui/expected-deliverables.json`
