---
name: importing-rule-proposals
description: |
  規約提案の判定結果を docs/rules/ へ取り込む。
  TRIGGER when: 規約提案HTMLの判定結果JSONを受け取った時、「規約提案を取り込む」と言われた時。
  SKIP: 提案の作成そのもの、派生物の生成（→syncing-derived-artifacts）。
invocation: importing-rule-proposals
type: transform
allowed-tools: [Bash, Read, Write]
---

# 規約提案取り込みスキル

規約提案HTMLが出力した判定結果JSONを読み、決定が「採用」の項目だけを `docs/rules/` へ書き込む。定義は `docs/rules/` だけである。`.claude/`・`.cursor/`・`.codex/`・`AGENTS.md` は別スキル（syncing-derived-artifacts）がここから生成する派生物である。本スキルは定義の書き込みだけを担い、派生物には一切触れない。

## 引数

| 引数 | 必須 | 内容 |
|---|---|---|
| `decisions_path` | 必須 | 判定結果JSONのパス。リポジトリ外を指す |
| `rules_root` | 任意 | 既定は `docs/rules` |

`decisions_path` がリポジトリの外を指す理由は、規約提案がリバース工程の出力物であり `docs/rules/` へ取り込まれる前の一時的な成果物だからである。リポジトリ内を指す入力は、取り込み済みか誤って配置されたものであり、そのまま読み進めると重複取り込みを起こす。

## Phase 1: 入力の検証

`decisions_path` のJSONを読み、次を確認する。

- トップレベルに `proposalId`・`generatedAt`・`total`・`judged`・`decisions` の5鍵があること
- `decisions_path` がリポジトリの外を指していること
- `decisions` の各要素が13鍵（`parent`・`key`・`chapter`・`title`・`summary`・`decision`・`proposedRule`・`scope`・`globs`・`enforcement`・`checkable`・`checkMethod`・`sources`）を持つこと

1件でも満たさなければ、不足箇所を列挙して停止する。書き込みは行わない。

**完了**: JSONのスキーマと配置場所を確認済み。不合格なら不足箇所を報告して停止している

## Phase 2: 採用分の抽出

`decision` が `adopt` の要素だけを残す。`hold`・`reject`・`pending` は取り込まない。

抽出した件数と、取り込まない件数を `hold`・`reject`・`pending` の内訳付きで報告する。

採用が0件の場合はその旨を報告して正常に終える。これはエラーではなく、提案の大半が保留や却下だった通常の結果である。書き込みは行わない。

**完了**: 採用要素の一覧が確定済み。0件なら報告して正常終了している

## Phase 3: 定義の書き込み

採用した各要素について、`docs/rules/<parent>/<key>/rule.md` 一式を生成する。

### front matterの組み立て

13鍵の値の出所は以下のとおりとする。

| front matterの鍵 | 値の出所 |
|---|---|
| `key` | JSONの `key` |
| `title` | JSONの `title` |
| `parent` | JSONの `parent` |
| `summary` | JSONの `summary` |
| `scope` | JSONの `scope` |
| `globs` | JSONの `globs`（`jq -c` で1行のJSON配列として出力する。`scope: always` でも省略せず書く） |
| `enforcement` | JSONの `enforcement` |
| `checkable` | 下記「検査可否の判定」で確定した値 |
| `checker` | `checkable` が true なら `check-<key>.sh`。false なら `null` |
| `uncheckableReason` | `checkable` が false なら検査できない理由。true なら `null` |
| `formatter` | 既定 `none`。矯正で表現できる規約なら該当する種類 |
| `status` | 常に `draft` |
| `origin` | 常に `proposal` |

`status` を常に `draft` にするのは、取り込みの誤りを1段止めるためである。取り込み直後の規約は派生物の生成対象に含まれず、人が `approved` へ変えたものだけが各ツールへ写る。

`summary`・`title`・`uncheckableReason` の値には、コロンに続く半角スペース（`: `）を含めてはならない。`docs/rules-tooling/validate-rule-definitions.sh` のfront matter読み取りは1行1鍵の単純な分割方式である。値の中の `: ` を鍵の区切りと誤認するため、該当箇所は読点や別の言い回しに置き換える。

### 検査可否の判定

JSONの `checkable` は提案時点の見立てであり、そのまま採用しない。`checkMethod` の記述を読み、機械的な検査として実装できるかを判断する。

- 実装できる場合: `checkable: true` とする。`checkMethod` が述べる検査をそのまま実装した
  `check-<key>.sh` と、その回帰テスト `check-<key>.test.sh` を生成する
- 実装できない場合（人の判断を要する・静的解析では判定できない等）: `checkable: false` とする。
  `checker` を `null`、`uncheckableReason` に検査できない理由を書く

**動いているように見えるだけで実際には何も検査しないスクリプトを置いてはならない**。判断に迷う場合は `checkable: false` 側へ倒す。

`checkable: true` の場合、`rule.md` に `## 設計判断` 節を置き、linterの必要性・代替案を採らなかった理由・保守責任者・廃棄条件の4項目を書く。

### 本文

`# <title>` の下に `## 概要`・`## 規則`・`## 違反時の手順` の3節を置く。`## 規則` は表とし、JSONの `proposedRule` と `sources` から行を起こす。

`## 違反時の手順` は `enforcement` の値によらず常に置く。設計文書の3節は `enforcement: advisory` のときのみ必須としているが、本スキルは `enforcement: none` の場合も置く。理由は、取り込み直後は `status: draft` であり `enforcement` が後から `advisory` へ変わる余地があるため、その時点で手順が欠けている事態を避けるためである。

`checkable: false` の場合は `rule.md` に加えて `design-notes.md` を生成し、検査できない理由を書く。

### 親カテゴリの宣言

親フォルダに `parent.yml` が無ければ作る。`title` はJSONの `chapter` から章番号を取り除いた部分を使う。取り除く対象は、行頭の `第<数字>章`・`<数字>`・`<数字>.<数字>` のいずれかのパターンと、それに続く区切り記号（`:`・`：`・`-`・空白）である。取り除いた残りの文字列が `title` になる。

### 既存ファイルの扱い

`docs/rules/<parent>/<key>/rule.md` が既に存在する場合、`origin` の値で分岐する。

| 既存の `origin` | 既存の `status` | 動作 |
|---|---|---|
| `template`（空の雛形のまま） | 問わない | 上書きする |
| `proposal` | `draft` | 上書きする |
| `proposal` | `approved` | 上書きしない。承認済みの定義を提案で戻さないため、差分を報告して人の判断を仰ぐ |
| `manual` | 問わない | 上書きしない。人が直接書いた定義を機械が消さないため、差分を報告する |

**完了**: 採用した全要素について `rule.md`（`checkable: false` なら `design-notes.md` も）が書き込まれている。上書きしなかった要素は理由付きで報告している

## Phase 4: 整合の確認

`docs/rules-tooling/validate-rule-definitions.sh <rules_root>` を実行する。これは `docs/rules/` の全体を対象とする検査であり、今回書き込んだ分だけを見るわけではない。

不合格が出た場合、書き込んだ内容を先に報告したうえで、次の2種類に分けて示す。

- 今回の取り込みが原因のもの（今回書き込んだ `rule.md` を指す不合格）
- 取り込み前から存在したもの（今回変更していないファイルを指す不合格）

前者は取り込み内容を見直す。後者は取り込み自体の欠陥ではないため、そのまま報告して人の判断を仰ぐ。両者を区別せず「取り込みが失敗した」とだけ報告してはならない。

**完了**: `validate-rule-definitions.sh` を実行済み。不合格があれば原因の切り分け付きで報告している

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | JSONのスキーマと配置場所を確認済み。不合格なら不足箇所を報告して停止している |
| Phase 2 | 採用要素の一覧が確定済み。0件なら報告して正常終了している |
| Phase 3 | 採用した全要素について定義一式が書き込まれている。上書きしなかった要素は理由付きで報告している |
| Phase 4 | 整合検査を実行済み。不合格があれば原因の切り分け付きで報告している |
| **Goal** | 判定結果JSONの採用分だけが `docs/rules/` へ反映され、既存の承認済み定義・手書き定義を保持したまま整合検査を通過している（または不合格の原因が切り分けて報告されている） |

## 予想を裏切る挙動

- 採用が0件でもエラーにはならない。提案の大半が保留や却下だった通常の結果として正常終了する
- `decision: adopt` でも書き込まれないことがある。既存の `origin: proposal` かつ `status: approved`、または `origin: manual` の定義がある場合、上書きせず差分報告に留める
- 取り込み直後の定義は `status: draft` になる。この時点ではまだ `syncing-derived-artifacts` の生成対象に入らず、`.claude/` などのツール設定には反映されない。人が `approved` へ変えるまで待つ
- Phase 4の整合検査は `docs/rules/` 全体を対象とする。今回の取り込みと無関係な既存の不整合があっても、検査そのものは不合格として返る

## 関連

- `syncing-derived-artifacts`：本スキルが書き込んだ定義を `.claude/`・`.cursor/`・`.codex/`・`AGENTS.md` へ反映するもう一方のスキル
- `docs/rules/<parent>/<key>/rule.md`：本スキルが書き込む定義そのもの
- `docs/rules-tooling/validate-rule-definitions.sh`：Phase 4で呼ぶ整合検査
