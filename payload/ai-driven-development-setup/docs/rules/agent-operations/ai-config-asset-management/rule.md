---
key: ai-config-asset-management
title: 定義と生成物の分け方の決まり
parent: agent-operations
summary: スキル・規約・フックなどAI設定資産の作成・変更・配置・レビューの手順。
scope: scoped
paths: ["docs/rules/**",".claude/**",".cursor/**",".codex/**","AGENTS.md"]
enforcement: advisory
checkable: true
checker: check-ai-config-derivative-manual-edit.sh
uncheckableReason: null
formatter: none
status: approved
origin: manual
workUnit: process
---

# 定義と生成物の分け方の決まり

## 概要

スキル・規約・フックの作成と変更の手順、および配置先の取り決め。

`docs/` が定義であり、`.claude/` と `.cursor/` と `.codex/` はそこから生成される派生である。変更は必ず定義側から行う。

### 規則表の様式

- 規則表は `規則 | 内容 | 検査` の3列とする

## 規則

| 規則 | 内容 | 検査 |
|---|---|---|
| 定義は docs に置く | AI エージェントが読む規約・手順・用語の定義は `docs/` 配下にだけ置く。ツール別のフォルダに定義の実体を作らない | 静的解析: `.claude/rules/`・`.cursor/rules/`・`.codex/` の配下に、`docs/rules/` に対応する定義を持たないファイルが無いかを検査する |
| 派生は生成物として扱う | `.claude/` と `.cursor/` と `.codex/` の内容は `docs/` から生成する。直接編集しない | 静的解析: 派生物の内容ハッシュを台帳と突合し、一致しないファイルを検出する |
| ずれは台帳で検知する | 各派生物の内容ハッシュを台帳へ記録し、突合で手作業の編集を検知する。判定に更新時刻は使わない | 静的解析: 台帳に登録された派生物の件数と、実在する派生物の件数が一致するかを検査する ／ 静的解析: 台帳に記録された内容ハッシュと各派生物の現在の内容ハッシュを突合し、一致しない項目が無いかを検査する |

## このプロジェクトの規則

<!-- リバース解析が対象リポジトリの観測から起こした規則を置く。規則表は上記様式の3列で書く。 -->

| 規則 | 内容 | 検査 |
|---|---|---|
| 未解析 | この規約に対応する実装の慣行は、まだ観測していない。リバース解析を実行して対象コードを分析すると、その結果からこの節へ規則が起こされる。解析を待たずに規則を決めたい場合は、この節へ直接書き足してよい | 未解析: リバース解析が未実行であり、対象コードの観測結果がない | 不可: 観測の有無は解析の実行結果に依存し、静的解析で判定できない |

## 違反時の手順

`.claude/rules/`・`.cursor/rules/`・`.codex/` の配下へ直接書き込もうとして止められた場合、書き込み先を `docs/` 配下の対応する定義ファイルへ切り替える。定義側を変更したうえで、派生物は生成し直す。派生物へ直接書き込む必要がある例外的な事情がある場合も、まず定義側の変更で対応できないかを確認してから判断する。

## 設計判断

### 配備される検査スクリプトの写し

`docs/rules/agent-operations/ai-config-asset-management/` には写しが4本ある。`build-derived-rules.sh`・`validate-rule-definitions.sh`である。`check-rule-drift.sh`・`resolve-applicable-rules.sh`もある。写しは`docs/skills/setup-deriving-rules/scripts/`の定義から作る。作成コマンドは`build-derived-rules.sh --deploy-rule-scripts <リポジトリのルート>`である。写しは配備した時点の定義の複製であり、1行目はシェバンのまま残し、2行目に生成物であることの注記を足す。定義をその後に直しても、配備し直すまで写しは古いままである。実測では`build-derived-rules.sh`の写しが定義より79行短い。定義が1645行、写しが1566行である。差分の行数で数えると87行になる。定義と派生のずれの検査（`check-rule-drift.sh`）はこの4本を対象にしないため、この遅れは検出されない。写しを直接編集せず、定義を直してから配備し直す。

2026-09-07、`validate-rule-definitions.sh` が本文 64KB を超える規約（`work-records/rule.md`）で `set -o pipefail` 下の `printf | grep -q` と途中で `exit` する awk により SIGPIPE を受け、終了コード 141 で落ちることが第1回改善指示書 1-35 追記の検査（全機能の手順書のコマンドを実際に走らせる）で実測された。定義側を最後まで読み切る awk に改め、長い本文の自己テストを足し、写しを配備し直した。写しの検査は定義の自己テストが担い、写し自身は自己テストを持たない。
