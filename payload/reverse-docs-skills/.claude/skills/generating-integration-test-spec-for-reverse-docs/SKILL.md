---
name: generating-integration-test-spec-for-reverse-docs
日本語名: 結合テスト仕様書の生成
description: "複数の設計単位をまたぐ結合テスト仕様書を生成する。"
invocation: generating-integration-test-spec-for-reverse-docs
type: transform
allowed-tools: [Read, Bash, Write, Edit, Grep, Glob]
---

# 正本: reverse-docs-skills

# 結合テスト仕様書生成スキル

## 使用タイミング

設計単位ごとのテスト設計書が揃い、複数の画面・機能・API・テーブル・バッチ・帳票・外部連携をまたぐ試験をプロジェクト全体で定義するときに使う。

## 基本ワークフロー

1. `output_dir` とプロジェクト名を確定する。
2. `../../../generation-engine/scripts/generate-integration-test-spec.sh <output_dir> <project_name>` を実行する。
3. `<output_dir>/docs/test-cases/結合テスト仕様書.md` を読み、対象範囲へ2つ以上の設計単位、テストケース一覧へ操作手順と期待結果が記載されていることを確認する。
4. `portal_output_dir` が指定された場合は `../../../generation-engine/scripts/build-portal.sh` を再実行し、結合テスト仕様書のカードをポータルへ反映する。

生成後は、各単位のテスト設計書と設計書内の節を事実源として表を記入する。コードのファイルパスや行番号は記録しない。確定できない事項は要確認事項一覧へ記録する。

## 出力

`<output_dir>/docs/test-cases/結合テスト仕様書.md`

## 重要な注意事項

- 単一の設計単位で完結する試験を重複して記載しない。
- テンプレートを直接複製せず、生成スクリプトを使う。
- 生成後に実文書を読み、テンプレートの存在確認だけで完了にしない。

## 予想を裏切る挙動

本書は単位ごとの結合テスト文書ではなく、プロジェクト全体で1冊だけ生成する。

## 完了報告

`../../../delivery-payload/references/完了報告の書き方.md` の作業報告型に従い、生成先と対象にした設計単位を報告する。

## 参照資料

- `../../../delivery-payload/references/納品物フォルダ体系.md`
- `../../../delivery-payload/references/output-layout.json`
