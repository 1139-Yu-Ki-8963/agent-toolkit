# 規約提案HTML生成スクリプトの設計判断

`shared/scripts/rule-proposal/` 配下のスクリプトの定義ドキュメント。設計の定義は
`shared/samples/規約提案/サンプルアプリAPI規約提案.html`（意匠の完成形）と
`shared/templates/rule-proposal/rule-proposal-template.html`（テンプレート）とする。
本ファイルは `~/.claude/rules/scoped/tooling/shell/rule.md` が新規 `.sh` 作成時に
要求する ADR（設計判断）の記載場所として、スクリプトと同じディレクトリに置く。

## 設計判断

### build-rule-proposal.sh

**必要性**: 規約提案HTML（対象リポジトリのコード調査から起こした規約の叩き台。
現場エンジニアが採用・保留・却下を判定するための文書）は、従来サンプル1枚が
手書きで存在するだけで、対象リポジトリごとに作り直す決定的な手段がなかった。
判定ボタン・進捗バー・TOC・章節構造という定型パターンをカテゴリ数十件ぶん
組み立てる作業は、手作業では列ズレ・属性欠落・判定ボタンのid不整合を
起こしやすく、`shared/scripts/unit-list/build-screen-list.sh` 等の既存ビルダーと
同様にJSONから決定的にHTMLを生成する必要がある。

**代替案を採用しなかった理由**:
- Bash ツール直叩き（Claudeが都度プレースホルダ置換）: 手作業組み立てによる
  属性欠落・判定ボタンのid不整合を根絶する目的で本スクリプトが必要
- 既存 Makefile ターゲット拡張: このリポジトリに Makefile は存在せず、新規導入は
  本チェック専用の依存を増やすだけになる
- package.json scripts 追加: 同様に、このリポジトリはビルド設定を持たない
- `shared/scripts/rules/build-derived-rules.sh` への統合: あちらは
  `docs/rules/` から `.claude/`・`.cursor/`・`AGENTS.md` 等の派生物を生成する
  「取り込み後」の変換であり、本スクリプトが担う「取り込み前の提案文書生成」
  とは入力・出力・関心がいずれも異なる

**保守責任者**: 人手（ユーザー）。入力JSONスキーマ（`proposalId`・`chapters[].categories[]`
の各鍵）を変更する場合は本スクリプトのコメント冒頭（スキーマ記載部）と
`shared/templates/rule-proposal/rule-proposal-template.html` を同時に更新する。

**廃棄条件**: 規約提案HTMLという成果物形式自体を廃止した時、またはHTML生成が
別基盤（テンプレートエンジン等）へ移行した時。

## 関連

- `shared/templates/rule-proposal/rule-proposal-template.html` — テンプレート本体
- `shared/samples/規約提案/サンプルアプリAPI規約提案.html` — 意匠の完成形サンプル
- `shared/samples/規約提案/サンプルアプリAPI規約提案-data.json` — 上記サンプルの入力データ
- `shared/references/規約定義と派生生成の設計.md` — 取り込み後（判定結果JSON以降）の変換設計
