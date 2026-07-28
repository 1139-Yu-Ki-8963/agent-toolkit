---
name: generating-test-case-list-for-reverse-docs
description: |
  画面別テスト仕様書をテストケース一覧へ集約する。
  TRIGGER when: テストケース一覧のリバース、画面別仕様の集約時。
  SKIP: テスト方針書を推測生成する時。
invocation: generating-test-case-list-for-reverse-docs
type: transform
allowed-tools: [Read, Write, Edit, Bash]
---

# テストケース一覧リバース

## 入力

既存の画面別 Markdown テスト仕様書を受け取る。

## 出力

manifest の `test_case_contract` に従う根拠付きテストケース一覧、または専用の0件テンプレートを出力する。

## 手順

1. 単体・結合・操作シナリオの既存仕様書を画面単位で集約する。
2. ケース本文と元ファイル相対パスを併記する。
3. 各行へケースID・画面ID・レベル・事前条件・手順・期待結果・元仕様書パス・原文抜粋を記録する。
4. JSONを`generate-test-case-list.py`へ渡して一覧HTMLを生成する。
5. 仕様書がない画面を推測で補完しない。

## 停止条件

既存仕様書が0件なら `shared/templates/test-case-list.html` を出力して `STOPPED` にする。

## 根拠追跡と検証

一覧の各行に元仕様書パスを残す。

検証コマンド:

```bash
python3 ../../../shared/scripts/generate-test-case-list.py \
  --template ../../../shared/templates/test-case-list.html \
  --output <output_dir>/一覧/テストケース一覧/テストケース一覧.html \
  < <test-case-evidence-json>
python3 ../../../shared/scripts/check-test-case-list-evidence.py \
  --target-repo <target_repo_path> \
  --template ../../../shared/templates/test-case-list.html \
  --output <output_dir>/一覧/テストケース一覧/テストケース一覧.html \
  < <test-case-evidence-json>
```

`--output`はテンプレート原型と別パスの実在生成物を指定する。0件時は生成物の構造hashが専用テンプレートと一致し、`records=[]`かつ`status=STOPPED`であることを検証する。

`exit 1` の場合は一覧を公開せず `status=STOPPED`、`hint=ケース本文・根拠または0件テンプレートの検証に失敗` を返す。

## 差し戻し

画面一覧がなければ generating-screen-list-for-reverse-docs へ戻す。

## 完了報告

集約件数、未確認画面、テンプレート出力の有無を返す。

## 予想を裏切る挙動

テストコードがあっても画面別MD仕様書がなければケースとして再構成しない。

## 参照資料

- `../../../shared/references/delivery-reverse-manifest.yml`
- `../../../shared/scripts/check-test-case-list-evidence.py`
- `../../../shared/scripts/generate-test-case-list.py`
- `../../../shared/templates/test-case-list.html`
- `../../../shared/references/gold-standard/docs/テスト仕様書.md`
- `../../../shared/references/gold-standard/stacks/typescript-ui/expected-deliverables.json`

<!-- delivery-owner-contracts:start -->
```json
[{"failure_return_to":"orchestrating-reverse-docs-flow","id":"test-cases","inputs":["screen test specifications"],"outputs":["一覧/テストケース一覧/テストケース一覧.html"],"stop_conditions":["仕様書なし"],"validator":"check-delivery-artifacts.sh"}]
```
<!-- delivery-owner-contracts:end -->
