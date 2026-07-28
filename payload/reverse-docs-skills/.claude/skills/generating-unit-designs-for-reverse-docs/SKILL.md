---
name: generating-unit-designs-for-reverse-docs
description: |
  非画面ユニットの確認可能な設計構造を採録する。
  TRIGGER when: API・テーブル・バッチ・帳票・外部連携の設計書作成時。
  SKIP: 根拠となるunit factsがない時。
invocation: generating-unit-designs-for-reverse-docs
type: transform
allowed-tools: [Read, Write, Edit, Bash]
---

# ユニット設計リバース

## 入力とモード

- `mode=facts`: `target_repo_path`、`source_paths`、`unit_kind`、`unit_id`、`verification_dir`を受け取る。
- `mode=design`: `facts_path`、`output_dir`、`unit_kind`、`unit_id`を受け取る。

## 出力

- `mode=facts`: `<verification_dir>/<unit_kind>-<unit_id>/facts/unit-facts.json`
- `mode=design`: manifestに定義された8出力のうち、対象種別の成果物

設計出力とテンプレートの対応は次のとおり。

| 出力 | テンプレート |
|---|---|
| API詳細設計書 | `unit-design-api-detail.md` |
| テーブル定義書 | `unit-design-table-detail.md` |
| バッチ詳細設計書 | `unit-design-batch-detail.md` |
| バッチ基本設計書 | `unit-design-batch-basic.md` |
| 帳票詳細設計書 | `unit-design-report-detail.md` |
| 帳票基本設計書 | `unit-design-report-basic.md` |
| 外部連携の詳細設計 | `unit-design-external-detail.md` |
| 外部連携の基本設計 | `unit-design-external-basic.md` |

## 手順

1. `mode=facts`ではコードで確認できる構造を、原文の抜粋・行番号・SHA-256とともにJSONへ記録する。
2. factsを保存し、`generate-unit-designs.py --mode facts`で検証して成功したJSONだけを`facts_path`として返す。
3. `mode=design`では`generate-unit-designs.py --mode design`を呼び、検証済みfactsから対応する構造テンプレートを埋める。
4. 意味・意図は`未確定事項`に残す。
5. batch/report/externalの基本設計はD5完了後に生成する。

## 停止条件

`mode=facts`でunit evidenceがなければ、次の状態で停止する。

- `status=STOPPED`
- `source_paths=[]`
- `structure=[]`
- `uncertainties`へ根拠不足の種別と理由を1件以上記録
- `unit_kind`は非画面5種のいずれか
- `unit_id`は空でない対象ID

`STOPPED`へ根拠行を混在させない。`mode=design`で検証済みfactsがなければ、成果物を生成せず`STOPPED`にする。

## 根拠追跡と検証

factsの最上位フィールドは`status`、`source_paths`、`structure`、`uncertainties`、`unit_kind`、`unit_id`だけとする。`unit_id`は保存先の`<unit_kind>-<unit_id>`と一致させる。`status=DONE`の各`structure`行は次の6フィールドをすべて持つ。

- `field`: 設計構造上の項目名
- `observed_value`: 4文字以上の確認可能な値
- `source_path`: `source_paths`にも含めた相対パス
- `source_excerpt`: 原本の該当行と正規化一致する抜粋
- `source_line`: 1始まりの正確な行番号
- `source_sha256`: 原本ファイル全体のSHA-256

test・fixture・自己テストを根拠に使わない。`source_excerpt`、`source_line`、`source_sha256`のいずれかが原本と一致しなければ失敗とする。

検証コマンド:

```bash
python3 ../../../shared/scripts/generate-unit-designs.py \
  --mode <facts|design> --target-repo <target_repo_path> \
  --facts <facts_path> --output-dir <output_dir>
```

`exit 1` の場合は設計書を確定せず `status=STOPPED`、`hint=unit evidence検証に失敗` を返す。

## 差し戻し

facts不足は本スキルの`mode=facts`へ戻す。

## 完了報告

unit kind、生成文書、未確定事項を返す。

## 予想を裏切る挙動

コードに見える呼出順から業務上の意味を補完しない。

## 参照資料

- `../../../shared/references/delivery-reverse-manifest.yml`
- `../../../shared/scripts/check-unit-design-evidence.py`
- `../../../shared/scripts/generate-unit-designs.py`
- `../../../shared/templates/unit-design-api-detail.md`
- `../../../shared/templates/unit-design-table-detail.md`
- `../../../shared/templates/unit-design-batch-detail.md`
- `../../../shared/templates/unit-design-batch-basic.md`
- `../../../shared/templates/unit-design-report-detail.md`
- `../../../shared/templates/unit-design-report-basic.md`
- `../../../shared/templates/unit-design-external-detail.md`
- `../../../shared/templates/unit-design-external-basic.md`
- `../../../shared/references/gold-standard/stacks/python-api-batch/expected-deliverables.json`
- `../../../shared/references/gold-standard/stacks/sql-data/expected-deliverables.json`

<!-- delivery-owner-contracts:start -->
```json
[{"failure_return_to":"orchestrating-reverse-docs-flow","id":"unit-designs","inputs":["unit source","unit facts"],"outputs":["API/<id>/詳細設計/API詳細設計書.md","テーブル/<id>/詳細設計/テーブル定義書.md","バッチ/<id>/詳細設計/バッチ詳細設計書.md","バッチ/<id>/基本設計/バッチ基本設計書.md","帳票/<id>/詳細設計/帳票詳細設計書.md","帳票/<id>/基本設計/帳票基本設計書.md","外部連携/<id>/詳細設計/外部連携詳細設計書.md","外部連携/<id>/基本設計/外部連携基本設計書.md"],"stop_conditions":["unit evidenceなし"],"validator":"check-delivery-artifacts.sh"}]
```
<!-- delivery-owner-contracts:end -->
