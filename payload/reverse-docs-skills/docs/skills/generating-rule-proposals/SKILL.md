---
name: generating-rule-proposals
description: |
  このリポジトリの実装の慣行を観測し、規約の叩き台のページをリポジトリの外へ書き出す。
  TRIGGER when: 規約の提案を作りたい時、「規約提案を作る」と言われた時。
  SKIP: 判定結果の取り込み（→importing-rule-proposals）、派生物の生成（→syncing-derived-artifacts）。
invocation: generating-rule-proposals
type: transform
allowed-tools: [Bash, Read, Write, Grep, Glob]
---

# 規約提案の書き出し

本スキルは、配られた生成器（`reverse-docs-engine/`）だけで規約の提案を作るためのものである。提案の判定結果を定義へ取り込む `importing-rule-proposals`、定義から派生を作り直す `syncing-derived-artifacts` と合わせて一周をつくる。一周とは「実装の慣行を観測する→提案を作る→判定する→定義に取り込む→派生に反映する」であり、配られたものだけで回す（改善課題1-280）。

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

## エンジンスクリプトの所在

生成スクリプトは、配られた生成器一式（このリポジトリのルートの `reverse-docs-engine/`）の中にある。

| スクリプト | パス（リポジトリのルート基点） |
|---|---|
| 規約提案HTML生成 | `reverse-docs-engine/generation-engine/scripts/rule-proposal/build-rule-proposal.sh` |
| 規約の分類の宣言 | `reverse-docs-engine/delivery-payload/references/rule-taxonomy.json` |

入力JSONのスキーマは生成スクリプトの冒頭コメントに定義がある。生成後の静的検査は同スクリプトが自動で実行する。ただし `node` または検査スクリプト自体が環境に無い場合は、警告を出したうえで検査を省略する。検査が必ず走るとは限らない点に注意する。

## 実行手順

- **Step 3** `output_path` を絶対パスへ解決し、`target_repo_path` の外側を指すことを確認する。内側を指す場合は生成せず、外側のパスへ変更するよう報告して停止する。完了条件: `output_path` が外側を指すことを確認済み、または内側だったため停止している

**完了**: 3項目すべての確認が済んでいる、または不備を報告して停止している

## Phase 2: 章とカテゴリの決定

## Step 2-1: 章とカテゴリの決定

**使用ツール**: Read / Grep / Glob

- **Step 1** 親7・子27の構成を対象リポジトリへ当てる。この構成は `reverse-docs-engine/delivery-payload/references/rule-taxonomy.json` を定義とする。章の `slug` は親の `key`、カテゴリの `key` は子の `key` をそのまま使う。表示名も同宣言の `title` を使う。**この文書に構成の表を複製しない。** 複製すると宣言との食い違いが起き、取り込み時に既存の空雛形を埋めずに新しいフォルダが増える事故になる。完了条件: 27カテゴリ全件に対応する行を用意済み
- **Step 2** 各カテゴリについて、対象リポジトリに観測できる材料があるかを判定し `state` を決める。値域は次の4つ。完了条件: 27カテゴリ全件に `state` が確定済み

| state | 意味 |
|---|---|
| `proposal` | 観測できる材料があり、規約提案文を起こせる |
| `proposal-limited` | 材料はあるが、調査範囲や事例数の制約で確信度が低い |
| `na` | 調査範囲内に対応する材料が見当たらない |
| `common` | 対象リポジトリ固有の観測を要さず、汎用の共通規約を参照すべき領域である |

材料が無いカテゴリを無理に `proposal` にしない。`na` として理由を書く。観測できないことを書けるのが、この工程の質である。

### 親7・子27の構成の確認手順

構成を確認するときは次のコマンドで `reverse-docs-engine/delivery-payload/references/rule-taxonomy.json` を直接読む。

```
jq -r '.parents[] | "\(.key) / \(.title)", (.children[] | "  \(.key) / \(.title)")' reverse-docs-engine/delivery-payload/references/rule-taxonomy.json
```

`rule-taxonomy.json` で `toolDefined: true` を持つ子カテゴリは提案の対象外である。ツール側が本文を書いて納品するため、提案して採否を問う対象ではない。

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
- **Step 2** `scope`・`paths`・`enforcement`・`checkable`・`checkMethod` を決める。完了条件: 対象カテゴリ全件に5項目が確定済み

`checkable` を `true` にするのは、静的解析で判定できる場合だけとする。判定できないものを `true` にすると、取り込みスキルが動かない検査を作ることになる。

`enforcement` は `advisory` か `none` のみを選べる。`block` は選べない。規約提案から生成された検査がいきなり作業を止めると、誤検知のたびに現場が規約そのものを不信に感じるためである。

**完了**: 対象カテゴリ全件に `proposedRule`・`scope`・`paths`・`enforcement`・`checkable`・`checkMethod` が確定済み

## Phase 5: 生成と検査

## Step 5-1: 生成と検査

**使用ツール**: Bash / Write

- **Step 1** Phase 2〜4の結果から入力JSONを組み立てる。完了条件: 入力JSONが `jq -e .` で妥当と確認できる
- **Step 2** `output_path` が `target_repo_path` の外側であることを再確認する。完了条件: 外側であることを再確認済み
- **Step 3** 生成スクリプトを実行する。完了条件: 提案HTMLが生成され、静的検査を通過している（検査環境が無い場合は警告を確認している）

  ```
  reverse-docs-engine/generation-engine/scripts/rule-proposal/build-rule-proposal.sh <入力JSON> <output_path>
  ```

**手作業でのプレースホルダ置換は禁止する**。HTML生成は必ず `build-rule-proposal.sh` 経由の決定的処理で行う。

**完了**: `output_path` に提案HTMLが生成され、静的検査を通過している

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | `target_repo_path`・`survey_doc_path` の実在確認済み、`output_path` が外側であることを確認済み。または不備を報告して停止している |
| Phase 2 | 27カテゴリ全件に `state` が確定済み |
| Phase 3 | `proposal`・`proposal-limited` の全カテゴリに根拠付きの観測が集まっている |
| Phase 4 | 対象カテゴリ全件に `proposedRule` と検査条件（5項目）が確定済み |
| Phase 5 | `output_path` に提案HTMLが生成され、静的検査を通過している |
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
- `checkable: true` は静的解析で判定できる場合に限る。判定できないものを `true` にすると、取り込み側が動かない検査を作ることになる
- `observations[]` の各要素と `crossFindings[].body` は生HTMLとしてそのまま出力される（`<code>` タグを許容するための設計）。一方 `proposedRule`・`reason`・`checkMethod` はエスケープされたうえで出力される。この非対称があるため、`observations` へ任意のHTMLを混入させない
- 生成後の静的検査は `node` または検査スクリプトが環境に無い場合、警告のみでスキップされる。検査が必ず実行される保証ではない
- `state` に4値以外の値を渡しても生成スクリプトはエラーにせず `na` 相当（判定ボタンなし）として描画する。`state` の値は事前にPhase 2の4値へ厳密に揃える

## 完了報告

`reverse-docs-engine/delivery-payload/references/完了報告の書き方.md` の作業報告型に従う。固有差分として「検証」テーブルに `build-rule-proposal.sh` の静的検査結果（pass/fail、スキップ時はその旨）を追加する。

## 参照資料

- `reverse-docs-engine/delivery-payload/references/規約定義と派生生成の設計.md`: 提案・取り込み・適用の全体設計、判定結果JSONの形式
- `reverse-docs-engine/generation-engine/scripts/rule-proposal/build-rule-proposal.sh`: 生成エンジン本体。入力JSONスキーマも持つ

## 関連

- `orchestrating-ai-development-setup`: 工程全体の案内役
- `surveying-architecture-for-reverse-docs`: 本スキルのデータ源（アーキテクチャ調査書）を確定する前工程
- `importing-rule-proposals`: 判定結果JSONを読み `docs/rules/<親>/<子>/` へ書き込む取り込みスキル。実体は `delivery-payload/templates/delivered-skills/importing-rule-proposals/` にある。`scaffold-rule-definitions.sh --with-skills` が対象リポジトリへ配る
- `syncing-derived-artifacts`: `docs/rules/` から各ツール向け派生物を生成する適用スキル。実体は `delivery-payload/templates/delivered-skills/syncing-derived-artifacts/` にある。同じ経路で配る
