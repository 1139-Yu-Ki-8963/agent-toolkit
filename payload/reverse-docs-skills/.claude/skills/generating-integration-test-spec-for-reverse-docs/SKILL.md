---
name: generating-integration-test-spec-for-reverse-docs
日本語名: 結合テスト仕様書の生成
description: "複数の設計単位をまたぐ結合テスト仕様書を生成する。"
invocation: generating-integration-test-spec-for-reverse-docs
type: transform
allowed-tools: [Read, Bash, Edit, Grep, Glob]
---

# 正本: reverse-docs-skills

本スキルが生成する納品物は顧客提示の文書である。自由記述の本文（要約・説明文）は敬体（です・ます）で書く。記入規則・検証記録・作業記録は常体でもよい（`delivery-payload/references/設計書様式.md` §8）。

# 結合テスト仕様書生成スキル

## 使用タイミング

設計単位ごとのテスト設計書が揃い、複数の画面・機能・API・テーブル・バッチ・帳票・外部連携をまたぐ試験をプロジェクト全体で定義するときに使う。
単一の設計単位で完結するテスト設計は対象外とする。

## Phase 1: 対象の確定

## Step 1-1: 出力先と対象を確定する

`output_dir` とプロジェクト名を確定し、対象に2つ以上の設計単位があることを確認する。

使用ツール: Read, Glob

**完了**: 出力先、プロジェクト名、対象の設計単位が確定している。

## Phase 2: 仕様書の生成

## Step 2-1: 生成スクリプトを実行する

`../../../generation-engine/scripts/generate-integration-test-spec.sh <output_dir> <project_name>` を実行する。

使用ツール: Bash

**完了**: `<output_dir>/docs/test-cases/結合テスト仕様書.md` が生成されている。

## Step 2-2: 設計書の事実を記入する

各単位のテスト設計書と設計書内の節を事実源として表を記入する。コードのファイルパスや行番号は記録しない。確定できない事項は関連資料の要確認事項一覧へ記録する。

使用ツール: Read, Edit

**完了**: 対象範囲に2つ以上の設計単位があり、各ケースに操作手順と期待結果が記入されている。

## Phase 3: 検証とポータル反映

## Step 3-1: 生成結果を検証する

生成した仕様書を読み、対象範囲、操作手順、期待結果、回復方法が記入されていることを確認する。

使用ツール: Read, Grep

**完了**: 必須項目の欠落がない。

## Step 3-2: ポータルへ反映する

`portal_output_dir` が指定された場合は `../../../generation-engine/scripts/build-portal.sh` を再実行し、結合テスト仕様書のカードをポータルへ反映する。指定がない場合は対象外として完了する。

使用ツール: Bash

**完了**: 指定時はカードが反映され、未指定時は対象外であることが確認されている。

## 出力

`<output_dir>/docs/test-cases/結合テスト仕様書.md`

## 重要な注意事項

- 単一の設計単位で完結する試験を重複して記載しない。
- テンプレートを直接複製せず、生成スクリプトを使う。
- 生成後に実文書を読み、テンプレートの存在確認だけで完了にしない。

## 予想を裏切る挙動

本書は単位ごとの結合テスト文書ではなく、プロジェクト全体で1冊だけ生成する。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 出力先と2つ以上の対象設計単位が確定している。 |
| Phase 2 | 結合テスト仕様書を生成し、設計書の事実を記入している。 |
| Phase 3 | 必須項目を検証し、指定時はポータルへ反映している。 |
| Goal | プロジェクト全体で1冊の結合テスト仕様書が検証済みである。 |

## 完了報告

`../../../delivery-payload/references/完了報告の書き方.md` の作業報告型に従い、生成先と対象にした設計単位を報告する。

## 参照資料

- `../../../delivery-payload/references/納品物フォルダ体系.md`
- `../../../delivery-payload/references/output-layout.json`
## テンプレート記入規則の実行

<!-- TEMPLATE_GUIDANCE_EXECUTION -->

使用する各 Markdown テンプレートを Read する。`<!-- 記入規則: ... -->` と `<!-- INTRODUCTION_GUIDANCE ... -->` の指示を本文生成の手順として実行する。冒頭案内は `delivery-payload/references/設計書様式.md` の §9 に従う。複数節では「節｜内容｜読み手へのお願い」の3列表を本文の節ごとに1行ずつ作る。作る側の判断理由・保管方法・作業経緯・文書作成方針・件数内訳は冒頭案内へ書かない。自由記述は敬体で書く。指示を反映した後、記入規則の HTML コメントは生成文書から除去する。
