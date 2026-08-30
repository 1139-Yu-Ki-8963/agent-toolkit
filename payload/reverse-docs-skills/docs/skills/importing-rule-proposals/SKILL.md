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
- `decisions` の各要素が13鍵を持つこと。鍵は `parent`・`key`・`chapter`・`title`・`summary`・`decision`・`proposedRule` の7個。加えて `scope`・`paths`・`enforcement`・`checkable`・`checkMethod`・`sources` の6個である
- 各要素は任意で14鍵目 `projectRule` を持ってよい。持つ場合は `null`、または `内容`・`根拠`・`検査` の3鍵を持つオブジェクトのいずれかであること。3鍵の意味は「## このプロジェクトの規則」節の表の列（規則列は下記「`projectRule` の書き込み」で `key` から起こす）と対応する

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
| `paths` | JSONの `paths`（`jq -c` で1行のJSON配列として出力する。`scope: always` でも省略せず書く） |
| `enforcement` | JSONの `enforcement` |
| `checkable` | 下記「検査可否の判定」で確定した値 |
| `checker` | `checkable` が true なら `check-<key>.sh`。false なら `null` |
| `uncheckableReason` | `checkable` が false なら検査できない理由。true なら `null` |
| `formatter` | 既定 `none`。矯正で表現できる規約なら該当する種類 |
| `status` | 常に `draft` |
| `origin` | 常に `proposal` |

`status` を常に `draft` にするのは、取り込みの誤りを1段止めるためである。取り込み直後の規約は派生物の生成対象に含まれず、人が `approved` へ変えたものだけが各ツールへ写る。

`summary`・`title`・`uncheckableReason` の値には、コロンに続く半角スペース（`: `）を含めてはならない。`validate-rule-definitions.sh` のfront matter読み取りは1行1鍵の単純な分割方式である。値の中の `: ` を鍵の区切りと誤認するため、該当箇所は読点や別の言い回しに置き換える。

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

対象コードのファイルパス・行番号は、規約定義の本文と根拠欄のどちらにも書かない。参照が必要な場合は関数名までとし、`sources` と `projectRule.根拠` に `<ファイル名>:<行番号>` 形式が含まれる入力は書き込まず不合格として報告する。

`## 違反時の手順` は `enforcement` の値によらず常に置く。設計文書の3節は `enforcement: advisory` のときのみ必須としているが、本スキルは `enforcement: none` の場合も置く。理由は、取り込み直後は `status: draft` であり `enforcement` が後から `advisory` へ変わる余地があるため、その時点で手順が欠けている事態を避けるためである。

`checkable: false` の場合は `rule.md` に加えて `design-notes.md` を生成する。`design-notes.md` は `checkable: false` のとき置く雛形であり、`rule.md` の `uncheckableReason`（1文の要約）を、ここで長文として補う場所である。理由の記述を一言で終えず、判断の根拠まで具体的に書く。

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

この表はファイル全体の上書き可否だけを決める。`projectRule` を持つ要素は、上の表で
「上書きしない」と判定された場合でも、次の「`projectRule` の書き込み」の対象になる
（節単位の書き込みはファイル単位の保護と独立している）。

**完了**: 採用した全要素について `rule.md`（`checkable: false` なら `design-notes.md` も）が書き込まれている。上書きしなかった要素は理由付きで報告している

### `projectRule` の書き込み（対象プロジェクトの観測から起こした規則）

`decision` が `adopt` の要素が `projectRule`（非 `null`）を持つ場合、「## このプロジェクトの規則」節へ以下の手順で書き込む。この手順は上の「既存ファイルの扱い」の判定（origin/status によるファイル全体の上書き可否）とは**独立**に動く。`origin: manual` や `origin: proposal` かつ `status: approved` でファイル全体の上書きを見送った要素でも、この節だけは書き込む対象になる。

1. `docs/rules/<parent>/<key>/rule.md` が存在しない場合: 上の「本文」の手順で新規に `rule.md` を作る。「## このプロジェクトの規則」節の表は、空のプレースホルダ行（`| （未記入） | （未記入） | （未記入） | （未記入） |`）にしない。かわりに `projectRule` の内容から起こした行にして作る。行の形式は `| <keyから起こした短い規則名> | <projectRule.内容> | <projectRule.根拠> | <projectRule.検査> |` である
2. `docs/rules/<parent>/<key>/rule.md` が既に存在する場合: 「## このプロジェクトの規則」節だけを読み、次のいずれかを行う
   - 節の表がプレースホルダ1行だけ（1列目が `未解析`・`対象なし`・`（未記入）` のいずれか）の場合: その1行を `projectRule` から起こした行で置き換える
   - 節の表がプレースホルダ以外の行を1行以上持つ場合（現場が既に観測した規則を書き足している場合）: 既存の行を保ったまま、`projectRule` から起こした行を表の末尾へ追加する。既存行の削除・書き換えはしない
   - いずれの場合も「## このプロジェクトの規則」節以外（front matter・`## 概要`・`## 規則`・`## 違反時の手順`）には一切触れない

`projectRule` が `null`、またはキー自体が無い要素については、この節への書き込みを行わない。「本文」の手順どおり、新規作成時は空のプレースホルダ行のまま、既存ファイルは触れないままにする。

書き込んだ結果は、要素ごとに「`<parent>/<key>`: このプロジェクトの規則へ1行追加（新規作成 / プレースホルダ置換 / 追記）」の形で報告する。

**完了**: `projectRule` を持つ全要素について「## このプロジェクトの規則」節へ書き込んでいる（`null` の要素は対象外として報告済み）

## Phase 4: 整合の確認

`validate-rule-definitions.sh <rules_root>` を実行する。これは `docs/rules/` の全体を対象とする検査であり、今回書き込んだ分だけを見るわけではない。

加えて、書き込む前の採用要素について `sources` と `projectRule.根拠` を走査し、拡張子付きファイル名にコロンと数字が続く対象コードの行番号が0件であることを機械検査する。1件でもあれば、その要素を不合格として書き込まない。

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
| Phase 3 | 採用した全要素について定義一式が書き込まれている。上書きしなかった要素は理由付きで報告している。`projectRule` を持つ要素は「## このプロジェクトの規則」節への書き込みも行われている |
| Phase 4 | 整合検査と根拠欄の対象コード行番号検査を実行済み。不合格があれば原因の切り分け付きで報告している |
| **Goal** | 判定結果JSONの採用分だけが `docs/rules/` へ反映され、既存の承認済み定義・手書き定義を保持したまま整合検査を通過している（または不合格の原因が切り分けて報告されている） |

## 予想を裏切る挙動

- 採用が0件でもエラーにはならない。提案の大半が保留や却下だった通常の結果として正常終了する
- `decision: adopt` でも書き込まれないことがある。既存の `origin: proposal` かつ `status: approved`、または `origin: manual` の定義がある場合、上書きせず差分報告に留める。ただし `projectRule` を持つ要素は、この場合でも「## このプロジェクトの規則」節だけは書き込まれる（ファイル単位の保護と節単位の書き込みは独立している）
- 取り込み直後の定義は `status: draft` になる。この時点ではまだ `syncing-derived-artifacts` の生成対象に入らず、`.claude/` などのツール設定には反映されない。人が `approved` へ変えるまで待つ
- Phase 4の整合検査は `docs/rules/` 全体を対象とする。今回の取り込みと無関係な既存の不整合があっても、検査そのものは不合格として返る

## 関連

- `syncing-derived-artifacts`：本スキルが書き込んだ定義を `.claude/`・`.cursor/`・`.codex/`・`AGENTS.md` へ反映するもう一方のスキル
- `docs/rules/<parent>/<key>/rule.md`：本スキルが書き込む定義そのもの
- `docs/rules/agent-operations/ai-config-asset-management/validate-rule-definitions.sh`：Phase 4で呼ぶ整合検査
