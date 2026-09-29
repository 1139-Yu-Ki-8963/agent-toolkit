---
name: generating-rule-proposals
description: |
  このリポジトリの実装の慣行を観測し、規約の叩き台のページをリポジトリの外へ書き出す。
  TRIGGER when: 規約の提案を作りたい時、「規約提案を作る」と言われた時。
  SKIP: 判定結果の取り込み（→importing-rule-proposals）。
invocation: generating-rule-proposals
type: transform
allowed-tools: [Bash, Read, Write, Grep, Glob]
---

# 規約提案の書き出し

本スキルは、AIエージェント自身の観測と執筆だけで規約の提案を作るためのものである。提案の判定結果を正本へ取り込む `importing-rule-proposals` と合わせて、「実装の慣行を観測する → 提案を作る → 判定する → 正本へ取り込む」の一周を、配られた文書とスキルだけで回す（改善課題1-280）。取り込んだ定義は `.claude/rules`・`.claude/skills`・`.cursor/rules/*.mdc` へのシンボリックリンクを通じてそのまま各ツールから参照されるため、派生への反映という別工程は無い。

このリポジトリのコードを調査し、観測した実装慣行を規約提案HTMLとして出力する。規約そのものは書かない。提案を読んだ現場のエンジニアが採用・保留・却下を判定する。出力先はリポジトリ外に固定する。提案は観測であって規範ではないため、リポジトリの中に置くと確定した規約と見分けがつかなくなる。

## 使用タイミング

- このリポジトリの実装慣行を規約提案として起こしたいとき
- 起動引数は以下のとおり

| 引数 | 必須 | 内容 |
|---|---|---|
| `target_repo_path` | 必須 | 調査対象のリポジトリの場所（通常はこのリポジトリのルート） |
| `output_path` | 必須 | 提案HTMLの出力先。`target_repo_path` の外側を指すこと。既定値は持たない |
| `survey_doc_path` | 必須 | アーキテクチャ調査書のパス（`docs/design/common/アーキテクチャ調査書.md` 等）。調査範囲の前提になる |
| `proposal_id` | 任意 | 既定は `target_repo_path` の末尾ディレクトリ名をケバブケースへ変換した値とする |

`output_path` に既定値を持たせない理由は、提案が観測であって規範ではないことにある。リポジトリの中へ既定で書き出す設計にすると、まだ誰も判定していない叩き台と、現場が確定させた規約とが同じ置き場に混在し、読み手が両者を見分けられなくなる。`output_path` が `target_repo_path` の内側を指す場合、本スキルはHTMLを生成せず停止する。

## 参照する資産

生成器は配らないため、次の資産を読んで手作業で提案HTMLを書く。

| 資産 | 役割 |
|---|---|
| 対象プロジェクトの `docs/rules/` | 親7・子27の構成の定義そのもの（納品時に配置済み） |
| `docs/rules/agent-operations/ai-config-asset-management/rule.md` | 定義と派生の関係、front matter の鍵の意味 |
| 既存の `docs/rules/<親>/<子>/rule.md` | 1件のカテゴリの本文の書き方の手本 |

入力JSONのスキーマは `importing-rule-proposals` の「実行手順」節が読む形式（`decisions[]` の13鍵）と同じである。同スキルの説明を参照する。

## 実行手順

- **Step 3** `output_path` を絶対パスへ解決し、`target_repo_path` の外側を指すことを確認する。内側を指す場合は生成せず、外側のパスへ変更するよう報告して停止する。完了条件: `output_path` が外側を指すことを確認済み、または内側だったため停止している

**完了**: 3項目すべての確認が済んでいる、または不備を報告して停止している

## Phase 2: 章とカテゴリの決定

## Step 2-1: 章とカテゴリの決定

**使用ツール**: Read / Grep / Glob

- **Step 1** 親7・子27の構成を対象リポジトリへ当てる。この構成は対象プロジェクトの `docs/rules/` の親フォルダ（`parent.yml`）・子フォルダ（`rule.md`）を定義とする（納品時に配置済みの構成であり、生成器から読み直す必要はない）。章の `slug` は親フォルダ名、カテゴリの `key` は子フォルダ名をそのまま使う。表示名は `parent.yml` の `title` および各 `rule.md` の front matter `title` を使う。**この文書に構成の表を複製しない。** 複製すると宣言との食い違いが起き、取り込み時に既存の空雛形を埋めずに新しいフォルダが増える事故になる。完了条件: 27カテゴリ全件に対応する行を用意済み
- **Step 2** 各カテゴリについて、対象リポジトリに観測できる材料があるかを判定し `state` を決める。値域は次の4つ。完了条件: 27カテゴリ全件に `state` が確定済み

| state | 意味 |
|---|---|
| `proposal` | 観測できる材料があり、規約提案文を起こせる |
| `proposal-limited` | 材料はあるが、調査範囲や事例数の制約で確信度が低い |
| `na` | 調査範囲内に対応する材料が見当たらない |
| `common` | 対象リポジトリ固有の観測を要さず、汎用の共通規約を参照すべき領域である |

材料が無いカテゴリを無理に `proposal` にしない。`na` として理由を書く。観測できないことを書けるのが、この工程の質である。

### 親7・子27の構成の確認手順

構成を確認するときは次のコマンドで対象プロジェクトの `docs/rules/` を直接読む。

```
for p in docs/rules/*/; do
  echo "$(basename "$p") / $(sed -n 's/^title: *//p' "${p}parent.yml")"
  for c in "$p"*/; do
    echo "  $(basename "$c") / $(sed -n 's/^title: "\(.*\)"$/\1/p' "${c}rule.md" | head -1)"
  done
done
```

現行の27カテゴリはいずれもツール側が本文を確定済みであり、提案の対象外である。対象リポジトリ固有の観測は各 `rule.md` の「このプロジェクトの規則」節への追記として別途行う。

**完了**: 27カテゴリ全件に `state` が確定済み

## Phase 3: 観測の収集

## Step 3-1: 観測の収集

**使用ツール**: Read / Grep / Bash

- **Step 1** `state` が `proposal` か `proposal-limited` のカテゴリについて、実測値を伴う観測を集める。件数・割合・パスを必ず添える。完了条件: 対象カテゴリ全件に観測1件以上が付いている
- **Step 2** 断定できない事項は「未確認」と明示する。推測を事実のように書かない。完了条件: 未確認事項は「未確認」と明記済み
- **Step 3** 調査範囲を `survey_doc_path` から決め、範囲外は調査しない。悉皆調査はしない。完了条件: 調査範囲を確定し `meta.scope` へ記述する準備が済んでいる

サンプリングの方針は、調査範囲を明確にしたうえで範囲内を丁寧に見ることであり、リポジトリ全体を網羅することではない。調査範囲は提案HTMLのメタ情報（`meta.scope`）へ明記する。

**完了**: 対象カテゴリ全件に、根拠となるパスと件数・割合付きの観測が集まっている

## Phase 4: 提案文と検査方法の起草

## Step 4-1: 提案文と検査方法の起草

**使用ツール**: Read

- **Step 1** 各カテゴリの `proposedRule` を書く。観測を規範の文へ変える工程であり、ここが提案の中身になる。完了条件: 対象カテゴリ全件に `proposedRule` が付いている
- **Step 2** `alwaysApply`・`paths`・`checkMethod` を決める。完了条件: 対象カテゴリ全件に3項目が確定済み

`checkMethod` には、その規約の違反を見つける手段を「静的解析: <方法>」「テスト: <方法>」「レビュー: <観点>」「判定不能: <理由>」のいずれかの書き出しで書く。機械検査の実装（linterの追加）は本スキル・`importing-rule-proposals` のどちらの範囲でもなく、検査列には手段を文章として記すにとどめる。

**完了**: 対象カテゴリ全件に `proposedRule`・`alwaysApply`・`paths`・`checkMethod` が確定済み

## Phase 5: 生成と検査

## Step 5-1: 生成と検査

**使用ツール**: Bash / Write

- **Step 1** Phase 2〜4の結果から入力JSONを組み立てる。完了条件: 入力JSONが `jq -e .` で妥当と確認できる
- **Step 2** `output_path` が `target_repo_path` の外側であることを再確認する。完了条件: 外側であることを再確認済み
- **Step 3** `output_path` へ提案HTMLを直接書く。生成器を持たないため、AIエージェント自身が入力JSONの内容をHTMLへ起こす。ページ構成は次のとおり。
  1. 冒頭に、入力JSONを `<script type="application/json" id="rule-proposal-data">` としてそのまま埋め込む（後から機械で再解析できるようにするため）
  2. `decisions[]` の各要素を、章（`parent`）ごとにまとめた表として描画する。列は `key`・`title`・`state`（`decision` 欄。既定値 `pending`）・`summary`・`proposedRule`・`checkMethod`・`sources` とする
  3. `state` が `na`・`common` の要素は、理由（`summary`）だけを示す簡略行にする
  4. 判定用の選択肢（`adopt`・`hold`・`reject`・`pending`）を各行の隣にテキストで示す。押せるボタンや自動集計のスクリプトは持たなくてよい。現場のエンジニアは、この表を見ながら別途 `decisions_path` のJSON（`importing-rule-proposals` が読む形式）へ判定を書き込む
  完了条件: `output_path` にHTMLが実在し、`decisions` の全件が表に現れている
- **Step 4** 書いたHTMLを読み直し、埋め込みJSONの `decisions` の件数と、表に現れる行数が一致することを確かめる。完了条件: 件数が一致している

**完了**: `output_path` に提案HTMLが生成され、埋め込みJSONと表の件数が一致することを確認済み

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | `target_repo_path`・`survey_doc_path` の実在確認済み、`output_path` が外側であることを確認済み。または不備を報告して停止している |
| Phase 2 | 27カテゴリ全件に `state` が確定済み |
| Phase 3 | `proposal`・`proposal-limited` の全カテゴリに根拠付きの観測が集まっている |
| Phase 4 | 対象カテゴリ全件に `proposedRule` と検査条件（3項目）が確定済み |
| Phase 5 | `output_path` に提案HTMLが生成され、埋め込みJSONと表の件数が一致している |
| **Goal** | 対象リポジトリの実装慣行が、観測と根拠付きで規約提案HTMLとしてリポジトリ外へ出力されている |

## 返却ブロック

本スキルは `orchestrating-ai-development-setup` の契約に準拠する。完了時に以下を返す。

| キー | 値 |
|---|---|
| `status` | `DONE`（生成完了）または `STOPPED`（前提不備・出力先違反）または `ERROR` |
| `output_path` | 生成した提案HTMLのパス（`STOPPED`/`ERROR` 時は空） |
| `total` | 判定対象の件数（`state` が `proposal` または `proposal-limited` のカテゴリ数） |
| `proposalCounts` | `state` 別の内訳（`proposal`・`proposal-limited`・`na`・`common` それぞれの件数） |

## 予想を裏切る挙動

- 提案は規約ではない。`docs/rules/` へ直接書き込まない。取り込みは現場の判断と `importing-rule-proposals` が担う
- `na` が多いことは失敗ではない。材料が無いカテゴリを無理に埋めるほうが害が大きい
- 提案HTMLへ埋め込む値のうち、対象リポジトリのコードから引用した断片をそのまま貼り付けない。要約した文で書く
- `state` に4値以外の値を書かない。Phase 2 の4値へ厳密に揃える

## 完了報告

作業報告の型に従う。固有差分として「検証」テーブルに、埋め込みJSONの件数と表の件数が一致することを確認した旨を追加する。

## 参照資料

- `importing-rule-proposals`: 判定結果JSONの形式（`decisions[]` の13鍵）

## 関連

- `orchestrating-ai-development-setup`: 工程全体の案内役
- `surveying-architecture-for-reverse-docs`: 本スキルのデータ源（アーキテクチャ調査書）を確定する前工程
- `importing-rule-proposals`: 判定結果JSONを読み `docs/rules/<親>/<子>/` へ書き込む取り込みスキル。実体は `delivery-payload/templates/delivered-skills/importing-rule-proposals/` にある。同じ経路で配る
