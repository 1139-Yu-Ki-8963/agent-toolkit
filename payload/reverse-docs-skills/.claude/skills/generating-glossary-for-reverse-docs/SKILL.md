---
name: generating-glossary-for-reverse-docs
description: "用語辞書.html を層化サンプリングによる採録から機械生成する。 TRIGGER when: 用語辞書ページ生成、glossary HTML作成、用語集作成。 SKIP: プロジェクト共通文書自体の採録（→generating-reverse-common-docs）、他種別詳細ページ生成。"
invocation: generating-glossary-for-reverse-docs
type: transform
allowed-tools: [Bash, Read, Write, Grep, Glob, AskUserQuestion]
---

# 用語辞書ページ生成スキル

工程全体は orchestrating-reverse-docs-flow が案内する。本スキルはポータルの将来ページ受け口のうち用語辞書（T2）のみを担い、単独起動できる（起動引数を渡せば動く）。

用語辞書には他の detail-pages 系スキルのような構造化された一次情報（manifest・調査書表）が存在しない。そのため本スキルは **採録型** を取る。プロジェクト共通文書・アーキテクチャ調査書・対象リポジトリのコード識別子を層化サンプリングで調べ、実際に記載・出現した語だけを **用語辞書.html** として書き出す。**本スキルは語の意味を創作しない**。採録源に根拠が無い語は `unresolved[]` へ退避し、捏造しない。

## 使用タイミング

- プロジェクト共通文書（`generating-reverse-common-docs` の出力）とアーキテクチャ調査書が確定済みで、ポータルに用語辞書カードを追加したいとき
- 起動引数: `target_repo_path`（調査対象リポジトリの絶対パス）・`output_dir`（プロジェクト共通文書・調査書の所在かつ出力先）・`portal_output_dir`（任意）
- `portal_output_dir` を指定した場合、生成後に `build-portal.sh` を再実行してカードへ反映する

出力先は `<output_dir>/用語辞書.html` に固定する（`build-portal.sh` の `FUTURE_FILES` と同値）。

## 設計原則

- **採録のみ** — 語の要否・重要度は判定しない。採録源に実在する記述・識別子から用語候補を構築するのみ
- **根拠なき語は unresolved へ** — 分類軸に該当しそうでも採録源に定義の記述が無い語は `terms[]` に含めず `unresolved[]` へ退避する
- **決定的サンプリング** — コード識別子の抽出は層化サンプリング（層定義・抽出規則は `references/glossary-extraction.md`）に固定する。乱数・目視選定を禁止する
- **二段承認** — 採録方針（Phase 1）と採録済み候補一覧（Phase 3）の 2 箇所で人間の承認を挟む。他の detail-pages 系スキル（転記のみの techstack 等）は承認不要だが、用語辞書は「何を採るか」「採った結果をどう間引くか」の 2 つの意思決定を要するため二段構成にする
- **固定と可変の分離** — 整合検証（`validate-page-data.sh`）と HTML 生成（`build-detail-page.sh`）は決定的スクリプトに固定する。採録（文書からの用語抽出・コード識別子の層化サンプリング）は Claude 自身が Bash/Read/Grep で行う

## エンジンスクリプトの所在

検証・生成スクリプトはスキルフォルダからの相対パスで参照する。

| スクリプト | パス（スキルフォルダ基点） |
|---|---|
| 整合検証 | `../../../shared/scripts/detail-pages/validate-page-data.sh` |
| HTML生成 | `../../../shared/scripts/detail-pages/build-detail-page.sh` |
| ポータル再生成（任意） | `../../../shared/scripts/build-portal.sh` |

## Phase 手順

### Phase 1: 採録方針の承認（二段承認・1段目）

- **Step 1** — 分類軸を決定する。既定は「業務用語／技術用語／略語」の 3 軸。プロジェクトの実態に応じてユーザーが分類軸を追加・変更できる。完了条件: 分類軸（`categories[]` の `key`/`label` 候補）が確定済み
- **Step 2** — 採録源を確認する。採録源は 3 系統ある。`<output_dir>/プロジェクト共通/` 配下の共通文書一式（`generating-reverse-common-docs` の出力）。`<output_dir>/プロジェクト共通/アーキテクチャ調査書.md`。`target_repo_path` 配下のコード識別子（層化サンプリング対象）。この 3 系統の実在を確認する。共通文書・調査書がいずれも不在ならハード停止し、該当スキルの先行実行を案内する。完了条件: 3 系統の採録源の実在確認済み、または不在を報告して停止している
- **Step 3** — 除外パターンを確定する。既定は一般英単語・フレームワーク API 名（`references/glossary-extraction.md`「除外既定」節参照）。プロジェクト固有の除外語があればユーザーから追加を受ける。完了条件: 除外パターン一覧が確定済み
- **Step 4** — Step 1〜3 の採録方針を AskUserQuestion でまとめて提示し承認を取る。宣言内容（分類軸・採録源・除外パターン）は一時ファイルに保存する。完了条件: 採録方針が承認済み（ヘッドレス実行時の扱いは「無人実行時の扱い」節を参照）

### Phase 2: 採録

- **Step 1** — プロジェクト共通文書・アーキテクチャ調査書から、Phase 1 で承認した分類軸に該当する語を抽出する。各語について記述箇所を `sourceRef` として控える（文書参照形式 `<文書名>.md#<見出し>`）。サンプルに現れない語を発明しない。完了条件: 文書由来の用語候補が抽出済み
- **Step 2** — `target_repo_path` のコード識別子を層化サンプリングで抽出する。層定義・snake_case/camelCase 分解規則は `references/glossary-extraction.md` を参照する。除外パターンに一致する識別子は候補から外す。分解して得た語のうち、Step 1 の文書側記述と対応が取れたものだけを候補にする。または、コード上の使用文脈から定義を復元できたものも候補にする。完了条件: コード由来の用語候補が抽出済み（`codeRefs[]` に実ファイルパス:行番号を記録）
- **Step 3** — Step 1・Step 2 の候補を統合し、各語について `term`/`definition`/`codeRefs`/`category`/`sourceRef` を構築する。`category` は `categories[].key` のいずれかと一致させる。定義の根拠（記述または識別子の使用文脈）が採録源に無い語は `terms[]` に含めず、`unresolved[]`（`label`/`reason`/`sourceRef`〈任意〉）へ退避する。完了条件: `terms[]` と（該当があれば）`unresolved[]` が確定済み

候補一覧は一時ファイル `$CLAUDE_JOB_DIR/tmp/glossary-candidates.json` に保存する。未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下に置く。

### Phase 3: 候補一覧の承認（二段承認・2段目）

- **Step 1** — Phase 2 で確定した `terms[]` を HTML 化前にユーザーへ提示する（`term`/`definition`/`category`/`sourceRef` の一覧）。完了条件: 候補一覧が提示済み
- **Step 2** — AskUserQuestion で取捨（削除・言い換え）の指示を受ける。削除指示があった語は `terms[]` から除く。言い換え指示があった語は `definition` を指示内容へ置換する（採録源に無い新規事実の追加は禁止。既存記述の言い回し変更に限る）。完了条件: 取捨結果が確定済み（ヘッドレス実行時の扱いは「無人実行時の扱い」節を参照）
- **Step 3** — 確定した `categories[]`/`terms[]`/`unresolved[]` から page-data.json を組み立てる。`pageKind` は `"glossary"` 固定とし、`title`・`description` も併せて埋める。完了条件: page-data.json を一時ディレクトリへ保存済み

page-data.json の保存先は `$CLAUDE_JOB_DIR/tmp/glossary-page-data.json` とする。未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下に置く。

### Phase 4: 整合検証・用語辞書.html 生成

- **Step 1** — 整合検証スクリプトを実行する。完了条件: 全項目 PASS

  ```
  ../../../shared/scripts/detail-pages/validate-page-data.sh <page-data.json> --target-repo <target_repo_path>
  ```

- **Step 2** — FAIL 時は `sourceRef` を修正し Step 1 を再実行する。3 回失敗したら Phase 2 Step 3（候補統合）へ差し戻す。完了条件: exit 0
- **Step 3** — HTML 生成スクリプトを実行する。完了条件: `<output_dir>/用語辞書.html` が生成済み

  ```
  ../../../shared/scripts/detail-pages/build-detail-page.sh <page-data.json> <output_dir> --page glossary
  ```

- **Step 4** — `portal_output_dir` が指定されていればポータル再生成スクリプトを実行しカードへ反映する。未指定なら省略し完了報告に注記する。完了条件: 再実行済み、または省略を注記済み

  ```
  ../../../shared/scripts/build-portal.sh <target_repo_path> <output_dir> <portal_output_dir>
  ```

**手作業でのプレースホルダ置換は禁止する**。HTML 生成は必ず `build-detail-page.sh` 経由の決定的処理で行う。

## 無人実行（headless）時の扱い

対話環境が無い状態で本スキルを実行する場合、Phase 1 Step 4（採録方針の承認）・Phase 3 Step 2（候補一覧の承認）の両方を、以下の既定値で自動承認したものとして扱う。

| 承認対象 | 既定値 |
|---|---|
| Phase 1（採録方針） | 分類軸=業務用語/技術用語/略語の 3 軸、採録源=Step 2 で実在確認済みの 3 系統すべて、除外パターン=`glossary-extraction.md`「除外既定」節の値のみ |
| Phase 3（候補一覧） | Phase 2 で確定した `terms[]` をそのまま採用（削除・言い換えなし） |

両方とも、自動承認した旨と適用した既定値を実行記録（返却ブロックの `hint`）に明記する。呼び出し元（orchestrating-reverse-docs-flow）側の契約（`contract.md`）への置換規則の反映は本スキルの範囲外とし、別途行う。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 分類軸・採録源・除外パターンの採録方針が承認済み、または不在を報告して停止している |
| Phase 2 | `terms[]` と（該当があれば）`unresolved[]` が確定済み（採録源に根拠のある語のみ） |
| Phase 3 | 候補一覧の取捨結果を反映した page-data.json を保存済み |
| Phase 4 | `validate-page-data.sh --target-repo` が全項目 PASS し、`<output_dir>/用語辞書.html` が生成され、指定時は `build-portal.sh` の再実行が完了している |
| **Goal** | 採録源に実在する記述・識別子のみを根拠とする用語辞書.html が二段承認と機械検証を経て生成され、根拠の無い語は unresolved として可視化されている |

## 返却ブロック

本スキルは orchestrating-reverse-docs-flow の契約に準拠する。完了時に以下を返す。

| キー | 値 |
|---|---|
| status | `DONE`（生成完了）\| `STOPPED`（採録源不在）\| `ERROR` |
| artifacts | 生成した用語辞書.html のパス（`STOPPED`/`ERROR` 時は空） |
| page_kind | `glossary`（固定値） |
| portal_rebuilt | `true`（build-portal.sh 再実行済み）\| `false`（`portal_output_dir` 未指定のため省略） |
| hint | 停止理由（採録源不在パス）、ヘッドレス自動承認の既定値適用記録、または次工程への申し送り |

## ループ設計

| 要素 | 内容 |
|---|---|
| 反復対象 | Phase 4 Step 1 が FAIL → Step 2 で修正して再実行 |
| 上限回数 | 3 回 |
| 収束停止 | `validate-page-data.sh` が exit 0 |
| 発散検知 | 同一検査項目の同一 FAIL が 2 回連続で再発した場合は即座に Phase 2 Step 3（候補統合）へ差し戻す |
| リソース上限 | 3 回失敗で Phase 2 Step 3（候補統合）へ差し戻す |

## 重要な注意事項

- 語の意味を創作しない。採録源（プロジェクト共通文書・調査書・コード識別子の使用文脈）に根拠の無い定義は書かない
- Phase 3 の言い換え指示は既存記述の言い回し変更に限る。採録源に無い新規事実の追加指示は反映しない（該当指示があった場合は反映せず hint に記録する）
- 層化サンプリングの選定は決定的コマンド（`find`/`sort`/`head`）に固定する。乱数・目視選定を禁止する
- Phase 4 の HTML 手作業組み立てを禁止する。`build-detail-page.sh` を必ず経由する
- 対象リポジトリへの書き込み・変更は一切行わない。出力は `output_dir` 配下の用語辞書.html のみ

## 予想を裏切る挙動

- `terms[].sourceRef` はコード識別子由来の語なら実ファイルパス（`src/models/order.ts:3` 形式）を使う。文書由来の語なら文書参照形式（`共通設計書.md#業務用語` 形式）を使う。`validate-page-data.sh --target-repo` は文書参照形式（`.md#` を含む値）を実在検査の対象外とする
- 出力先は `<output_dir>` 直下（他種別と同様、種別専用フォルダは作らない）
- `categories[]` は既定 3 軸だが固定ではない。Phase 1 でユーザーが追加・変更した軸がそのまま `terms[].category` の許容値になる
- Phase 3 で全語が削除された場合でも `terms: []` として page-data.json を組み立てる。`validate-page-data.sh` は空配列を許容し、テンプレート側が「なし」を表示する
- `portal_output_dir` 未指定時は `build-portal.sh` を実行しない。生成済み用語辞書.html はそのまま残り、次回ポータル生成時に自動でカード化される

## 設計判断

### 二段承認（採録方針 + 候補一覧）

**必要性**: 用語辞書は他の detail-pages 系スキル（techstack 等の転記型）と異なり、一次情報が構造化されていない採録型のスキルである。「何を採るか」（分類軸・採録源・除外パターン）と「採った結果をどう間引くか」（候補一覧の取捨）は独立した意思決定であり、後者を欠くと採録漏れ・過剰採録がそのまま用語辞書.html に混入する。2 箇所の承認ポイントを分離することで、方針決定と結果確認の両方に人間の判断を挟む。

**代替案を採用しなかった理由**:
- 承認 1 回（方針のみ）: 採録結果を事前に見せずに確定させると、実行結果を見てからの間引き（誤検出した略語の除外・言い換え）ができない
- 承認 0 回（全自動）: 用語辞書は「語の候補選定」という主観の余地がある工程を含む。`generating-reverse-common-docs` の実装事実主義（サンプルに現れない規則を発明しない）とは事情が異なり、機械ゲートのみでの完全自動化は精度が担保できない

**保守責任者**: 人手（ユーザー）

**廃棄条件**: 用語辞書の採録方式が採録型から構造化データ突合型（他 4 スキルと同型）へ変更された時

### 層化サンプリングによるコード識別子の用語復元（glossary-extraction.md への分離）

**必要性**: コード識別子（`snake_case`/`camelCase`）から用語候補を復元する規則と、層化サンプリングの層定義を専用文書に分離する。姉妹スキルにも同型の設計がある。`generating-reverse-common-docs` は `sampling-rules.md` を持つ。`generating-table-list-for-reverse-docs` は `table-detection.md` を持つ。いずれも戦略文書を SKILL.md 本体から分離している。本スキルもこの踏襲元と同じ考え方に従う。SKILL.md 本体に埋め込むと Phase 手順の可読性が損なわれるため、専用の `references/glossary-extraction.md` に分離する。

**代替案を採用しなかった理由**:
- SKILL.md 本体への直接記載: 層定義・分解規則・除外既定の 3 要素は分量が多く、Phase 手順の一部として埋め込むと本体が肥大化する
- 汎用の識別子分解ライブラリの導入: 本リポジトリのスキルは bash + jq のみに依存する既定方針（依存ツールの前提）があり、新規言語依存を持ち込まない

**保守責任者**: 人手（ユーザー）

**廃棄条件**: 用語辞書の採録源からコード識別子が除外された時、または層化サンプリングの方式が別方式に置き換わった時

### 採録源なき語の unresolved 退避（捏造禁止）

**必要性**: `generating-reverse-common-docs` の実装事実主義（サンプルに現れない規則を発明しない）を用語辞書にも適用する。分類軸に該当しそうでも採録源に定義の記述・使用文脈が無い語を `terms[]` に含めると、読み手が「実在する定義」と誤認する。`unresolved[]` へ機械的に分離することで、根拠の有無を可視化する。

**代替案を採用しなかった理由**:
- 根拠が薄い語も推測定義で `terms[]` に含める: 姉妹スキル群が共有する実装事実主義に反し、誤った定義の流通リスクを生む
- 根拠が薄い語を黙って捨てる: 採録漏れが不可視化され、Phase 3 の候補一覧承認で「本来採るべきだった語」に気付く機会を失う

**保守責任者**: 人手（ユーザー）

**廃棄条件**: page-data.json スキーマから `unresolved[]` が廃止された時

### エンジンスクリプトの共用（validate-page-data.sh / build-detail-page.sh）

**必要性**: page-data.json の整合検証と HTML 生成は pageKind 非依存の決定的処理であり、5 種別に共通する。`shared/scripts/detail-pages/` の単一実装を全種別スキルが相対パスで共用することで、スキーマ変更時の同期漏れを防ぐ。

**代替案を採用しなかった理由**:
- スキルフォルダ内への複製: スキーマ変更時に種別数ぶんの同期漏れリスクが生じる
- Claude 手作業での HTML 組み立て: 検証なしのデータ混入（テーブル一覧系での `entryFile=None` 混入実害）が再発する

**保守責任者**: 人手（ユーザー）

**廃棄条件**: page-data.json のスキーマ、または用語辞書.html の形式が廃止された時

## 完了報告

`~/.claude/skills/managing-agent-configs/references/skills/completion-report-format.md` の作業報告型に従う。固有差分として「検証」テーブルに `validate-page-data.sh` の PASS/FAIL 行を追加する。

## 参照資料

- `../../../shared/scripts/detail-pages/page-data-schema.md` — page-data.json のスキーマ定義
- `references/glossary-extraction.md` — 層化サンプリングの層定義・識別子からの用語復元規則・除外既定
- `references/generating-glossary-for-reverse-docs-guide.html` — スキルガイド
- `.claude/skills/generating-reverse-common-docs/SKILL.md` — 層化サンプリング・実装事実主義の踏襲元
- `.claude/skills/generating-table-list-for-reverse-docs/SKILL.md` — 検出戦略の AskUserQuestion 承認パターンの踏襲元
