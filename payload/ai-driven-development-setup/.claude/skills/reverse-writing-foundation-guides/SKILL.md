---
name: reverse-writing-foundation-guides
日本語名: 基盤文書を書く
description: "道標の節1と基盤設計書から技術スタックと環境構築手順書を書き、依存の定義への実在と様式を機械検査する。工程2-3。"
invocation: reverse-writing-foundation-guides
type: transform
allowed-tools: [Read, Bash, Write]
unit: reverse
category: setup
kind: none
inputs: [docs/design/common/道標.md, docs/design/common/基盤設計書.md]
outputs: [docs/design/common/技術スタック.md, docs/design/common/環境構築手順書.md]
requires: [reverse-listing-units]
acceptance: tests/
---
<!-- 生成物: 定義は支援ツールの正本リポジトリの docs/skills/reverse-writing-foundation-guides/ にある（この配布物には含まれない）。直接編集しないこと -->

## いつ使うか

一覧化（`reverse-listing-units`）が完了した後、技術スタックと環境構築手順書を書くときに使う。

## いつ使わないか

道標・基盤設計書が無い、または承認されていないとき。共通設計文書そのものを書き直したいとき（道標を描く機能の手順 4 をやり直す）。

## 前提

- 対象リポジトリの `docs/design/common/道標.md` と `docs/design/common/基盤設計書.md` があること
- 対象リポジトリの `ai-output` の `confirmations/` に承認の記録があること（無ければ止まる。確認は手順 1）
- 環境の値（接続先・秘密の値）は文書に書かず、出力の置き場の `confirmations/確認事項の記録.md` へ登録する

## 手順

1. `bash ../reverse-shared/scripts/check-entry.sh <出力の置き場> <対象リポジトリのルート>` を実行し、範囲の承認（可否・道標の同一性）を確かめる。終了コードが 0 でなければ止まり、道標を描く機能の範囲の承認をやり直す
2. `templates/技術スタック.md` を対象の `docs/design/common/技術スタック.md` へ複製する
3. `templates/環境構築手順書.md` を対象の `docs/design/common/環境構築手順書.md` へ複製する
4. 道標の節 1「調査」（特に依存の定義・ビルド・起動・テストの定義・環境の値の定義・テストの枠組みと場所・実行環境の前提）と基盤設計書、および依存の定義ファイル（package.json 等）を読む。2 文書の各行・各節を埋める。技術スタックの「名前」は依存の定義ファイルに実在する名前をそのまま書く
5. 環境の値（接続先・秘密の値）は書かず、要確認事項一覧と `confirmations/確認事項の記録.md` へ登録する
6. `bash scripts/check-foundation-guides.sh <対象リポジトリのルート>` を実行する
7. 終了コードを見る。0 なら完了。1 なら不合格の内容（依存-不在・節-欠落・位置づけ-欠落・未記入-残存・位置-禁止・秘密-混入）を読み、当該文書を直して手順 6 からやり直す（差し戻し表: 工程内-やり直し）。やり直しの回数に上限は設けない。同じ不合格が 2 回続いたら、書き方（依存の定義の読み方・節の埋め方）を変える

## 完了条件

- 技術スタックの各行の「名前」が道標の節 1「依存の定義」の場所に実在する
- 環境構築手順書の節が揃い、各 § の直後に位置づけの行があり、未記入・実装位置（file:line）・秘密の値らしき記述が無い
- `scripts/check-foundation-guides.sh` が終了コード 0
- `tests/` の全件が通る

## 設計判断

### check-foundation-guides.sh

**必要性**: 技術スタックに書いた依存の名前が実際の依存の定義に実在するか、環境構築手順書に環境の値そのものが紛れ込んでいないかは、目視では見落としやすい。依存の定義ファイルとの文字列一致・節構成・秘密の値らしき記述の検出は機械で確実に行える。

**代替案を採用しなかった理由**:
- AI の自己レビューだけに任せる: 秘密の値の混入は見落とすと影響が大きく、機械検査を欠かせない
- 依存の定義ファイルを構文解析して版まで突き合わせる: 依存の定義ファイルの形式は言語ごとに異なり、名前の文字列一致で十分な精度が得られる範囲を超える

**保守責任者**: 人手（ユーザー）。様式（`templates/技術スタック.md`・`templates/環境構築手順書.md`）の節構成を変えるときは、本スクリプトと自己テストを同時に直す。

**廃棄条件**: 基盤文書の機械で読む部分を構造化データとして別に出す形に変えた時。
