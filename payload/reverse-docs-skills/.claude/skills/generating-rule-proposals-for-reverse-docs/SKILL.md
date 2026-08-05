---
name: generating-rule-proposals-for-reverse-docs
description: |
  対象コードの実装慣行を観測し、規約提案HTMLをリポジトリ外へ出力する。
  TRIGGER when: 規約提案の作成、実装慣行の観測、「規約提案を出して」と言われた時。
  SKIP: 規約本文の確定（→現場の判断）、提案の取り込み（→importing-rule-proposals）、一覧・設計書の生成（→対応する種別別スキル）。
invocation: generating-rule-proposals-for-reverse-docs
type: transform
allowed-tools: [Bash, Read, Write, Grep, Glob]
---

# 規約提案HTML生成スキル

工程全体は `orchestrating-reverse-docs-flow` が案内する。本スキルは規約提案（対象リポジトリの実装慣行から起こした叩き台）の生成のみを担い、単独起動できる。

対象リポジトリのコードを調査し、観測した実装慣行を規約提案HTMLとして出力する。規約そのものは書かない。提案を読んだ現場のエンジニアが採用・保留・却下を判定する。出力先はリポジトリ外に固定する。提案は観測であって規範ではないため、リポジトリの中に置くと確定した規約と見分けがつかなくなる。

## 使用タイミング

- 対象リポジトリの実装慣行を規約提案として起こしたいとき
- 起動引数は以下のとおり

| 引数 | 必須 | 内容 |
|---|---|---|
| `target_repo_path` | 必須 | 調査対象のリポジトリの場所 |
| `output_path` | 必須 | 提案HTMLの出力先。`target_repo_path` の外側を指すこと。既定値は持たない |
| `survey_doc_path` | 必須 | アーキテクチャ調査書のパス。調査範囲の前提になる |
| `proposal_id` | 任意 | 既定は `target_repo_path` の末尾ディレクトリ名をケバブケースへ変換した値とする |

`output_path` に既定値を持たせない理由は、提案が観測であって規範ではないことにある。リポジトリの中へ既定で書き出す設計にすると、まだ誰も判定していない叩き台と、現場が確定させた規約とが同じ置き場に混在し、読み手が両者を見分けられなくなる。`output_path` が `target_repo_path` の内側を指す場合、本スキルはHTMLを生成せず停止する。

## エンジンスクリプトの所在

生成スクリプトはスキルフォルダからの相対パスで参照する。

| スクリプト | パス（スキルフォルダ基点） |
|---|---|
| 規約提案HTML生成 | `../../../shared/scripts/rule-proposal/build-rule-proposal.sh` |

入力JSONのスキーマは同スクリプトの冒頭コメントに定義がある。生成後の静的検査（`verify-html-static.mjs` による構造検査）は同スクリプトが自動で実行する。ただし `node` または検査スクリプト自体が環境に無い場合は、警告を出したうえで検査を省略する。検査が必ず走るとは限らない点に注意する。

## 実行手順

## Phase 1: 前提の確認

## Step 1-1: 前提の確認

**使用ツール**: Read / Bash

- **Step 1** 対象リポジトリ（`target_repo_path`）の実在を確認する。不在なら理由を報告して停止する。完了条件: 実在確認済み、または不在を報告して停止している
- **Step 2** アーキテクチャ調査書（`survey_doc_path`）の実在を確認する。不在なら `surveying-architecture-for-reverse-docs` の先行実行を案内して停止する。完了条件: 実在確認済み、または不在を報告して停止している
- **Step 3** `output_path` を絶対パスへ解決し、`target_repo_path` の外側を指すことを確認する。内側を指す場合は生成せず、外側のパスへ変更するよう報告して停止する。完了条件: `output_path` が外側を指すことを確認済み、または内側だったため停止している

**完了**: 3項目すべての確認が済んでいる、または不備を報告して停止している

## Phase 2: 章とカテゴリの決定

## Step 2-1: 章とカテゴリの決定

**使用ツール**: Read / Grep / Glob

- **Step 1** 親7・子27の構成（下表）を対象リポジトリへ当てる。この構成は `docs/rules/<親>/<子>/` の階層と一致する契約値であり、章slugと子keyは変更しない。完了条件: 27カテゴリ全件に対応する行を用意済み
- **Step 2** 各カテゴリについて、対象リポジトリに観測できる材料があるかを判定し `state` を決める。値域は次の4つ。完了条件: 27カテゴリ全件に `state` が確定済み

| state | 意味 |
|---|---|
| `proposal` | 観測できる材料があり、規約提案文を起こせる |
| `proposal-limited` | 材料はあるが、調査範囲や事例数の制約で確信度が低い |
| `na` | 調査範囲内に対応する材料が見当たらない |
| `common` | 対象リポジトリ固有の観測を要さず、汎用の共通規約を参照すべき領域である |

材料が無いカテゴリを無理に `proposal` にしない。`na` として理由を書く。観測できないことを書けるのが、この工程の質である。

### 親7・子27の構成

| 章index | 章 | 章slug | 子key | 子カテゴリ |
|---|---|---|---|---|
| 1 | AIエージェント運用 | agent-operations | agent-behavior | AIエージェント行動規約 |
| 1 | AIエージェント運用 | agent-operations | destructive-safety | 破壊的操作の安全規約 |
| 1 | AIエージェント運用 | agent-operations | session-management | セッション管理規約 |
| 1 | AIエージェント運用 | agent-operations | ai-asset-management | AI設定資産の管理規約 |
| 1 | AIエージェント運用 | agent-operations | routine-operations | 定型運用の規約 |
| 2 | 開発プロセス | development-process | dev-flow | 開発フロー規約 |
| 2 | 開発プロセス | development-process | tooling-commands | ツールとコマンド実行の規約 |
| 2 | 開発プロセス | development-process | dev-environment | 開発環境規約 |
| 2 | 開発プロセス | development-process | git-operations | Git運用規約 |
| 2 | 開発プロセス | development-process | release-delivery | リリースとデリバリーの規約 |
| 3 | コード規約 | code-standards | coding-standards | コーディング規約 |
| 3 | コード規約 | code-standards | naming-convention | 命名規約 |
| 3 | コード規約 | code-standards | directory-structure | ディレクトリ構成規約 |
| 3 | コード規約 | code-standards | component-design | コンポーネント設計規約 |
| 4 | 品質保証 | quality-assurance | test-policy | テスト方針書 |
| 4 | 品質保証 | quality-assurance | review-checklist | レビュー観点表 |
| 5 | 文書化規約 | documentation-standards | documentation-standards | ドキュメント作成規約 |
| 5 | 文書化規約 | documentation-standards | portal-maintenance | ポータル保守規約 |
| 6 | 非機能要件 | non-functional-requirements | security-requirements | セキュリティ要件 |
| 6 | 非機能要件 | non-functional-requirements | performance-requirements | 性能要件 |
| 6 | 非機能要件 | non-functional-requirements | availability-requirements | 可用性要件 |
| 6 | 非機能要件 | non-functional-requirements | scalability-requirements | 拡張性要件 |
| 6 | 非機能要件 | non-functional-requirements | monitoring-requirements | 監視要件 |
| 7 | 業務ドメイン規約 | business-domain | terminology | 用語定義 |
| 7 | 業務ドメイン規約 | business-domain | business-rules | 業務規則 |
| 7 | 業務ドメイン規約 | business-domain | state-transition | 状態遷移の制約 |
| 7 | 業務ドメイン規約 | business-domain | calculation-rules | 計算規則 |

**完了**: 27カテゴリ全件に `state` が確定済み

## Phase 3: 観測の収集

## Step 3-1: 観測の収集

**使用ツール**: Read / Grep / Bash

- **Step 1** `state` が `proposal` か `proposal-limited` のカテゴリについて、実測値を伴う観測を集める。件数・割合・パスと行番号を必ず添える。完了条件: 対象カテゴリ全件に観測1件以上が付いている
- **Step 2** 断定できない事項は「未確認」と明示する。推測を事実のように書かない。完了条件: 未確認事項は「未確認」と明記済み
- **Step 3** 調査範囲を `survey_doc_path` から決め、範囲外は調査しない。悉皆調査はしない。完了条件: 調査範囲を確定し `meta.scope` へ記述する準備が済んでいる

サンプリングの方針は、調査範囲を明確にしたうえで範囲内を丁寧に見ることであり、リポジトリ全体を網羅することではない。調査範囲は提案HTMLのメタ情報（`meta.scope`）へ明記する。

**完了**: 対象カテゴリ全件に、根拠となるパスと行番号付きの観測が集まっている

## Phase 4: 提案文と検査方法の起草

## Step 4-1: 提案文と検査方法の起草

**使用ツール**: Read

- **Step 1** 各カテゴリの `proposedRule` を書く。観測を規範の文へ変える工程であり、ここが提案の中身になる。完了条件: 対象カテゴリ全件に `proposedRule` が付いている
- **Step 2** `scope`・`globs`・`enforcement`・`checkable`・`checkMethod` を決める。完了条件: 対象カテゴリ全件に5項目が確定済み

`checkable` を `true` にするのは、静的解析で判定できる場合だけとする。判定できないものを `true` にすると、取り込みスキルが動かない検査を作ることになる。

`enforcement` は `advisory` か `none` のみを選べる。`block` は選べない。規約提案から生成された検査がいきなり作業を止めると、誤検知のたびに現場が規約そのものを不信に感じるためである。

**完了**: 対象カテゴリ全件に `proposedRule`・`scope`・`globs`・`enforcement`・`checkable`・`checkMethod` が確定済み

## Phase 5: 生成と検査

## Step 5-1: 生成と検査

**使用ツール**: Bash / Write

- **Step 1** Phase 2〜4の結果から入力JSONを組み立てる。完了条件: 入力JSONが `jq -e .` で妥当と確認できる
- **Step 2** `output_path` が `target_repo_path` の外側であることを再確認する。完了条件: 外側であることを再確認済み
- **Step 3** 生成スクリプトを実行する。完了条件: 提案HTMLが生成され、静的検査を通過している（検査環境が無い場合は警告を確認している）

  ```
  ../../../shared/scripts/rule-proposal/build-rule-proposal.sh <入力JSON> <output_path>
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

本スキルは `orchestrating-reverse-docs-flow` の契約に準拠する。完了時に以下を返す。

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

`~/.claude/skills/managing-agent-configs/references/skills/completion-report-format.md` の作業報告型に従う。固有差分として「検証」テーブルに `build-rule-proposal.sh` の静的検査結果（pass/fail、スキップ時はその旨）を追加する。

## 参照資料

- `../../../shared/references/規約定義と派生生成の設計.md`: 提案・取り込み・適用の全体設計、判定結果JSONの形式
- `../../../shared/scripts/rule-proposal/build-rule-proposal.sh`: 入力JSONスキーマと生成エンジン本体
- `../../../shared/samples/規約提案/サンプルアプリAPI規約提案.html`: 記入済みの例（意匠の完成形）
- `references/generating-rule-proposals-for-reverse-docs-guide.html`: スキルガイド

## 関連

- `orchestrating-reverse-docs-flow`: 工程全体の案内役
- `surveying-architecture-for-reverse-docs`: 本スキルのデータ源（アーキテクチャ調査書）を確定する前工程
- `importing-rule-proposals`（未実装）: 判定結果JSONを読み `docs/rules/<親>/<子>/` へ書き込む取り込みスキル
- `syncing-derived-artifacts`（未実装）: `docs/rules/` から各ツール向け派生物を生成する適用スキル
