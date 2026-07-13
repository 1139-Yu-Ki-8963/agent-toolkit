# 共通命名原則（COMMON-NAMING-PRINCIPLES）

全サーフェス（ファイル名・ディレクトリ名・hook名・スクリプト名・タグ名・マーカー名・環境変数名・シェル関数名・識別子全般）に適用される命名の意味論的原則。形式（casing・文字数）はサーフェス別の規約に委ね、本規約は「意味の質」を規定する。

## 原則

### 1. 名は体を表す

名前単独で対象と役割が復元できること。対象欠落語（gate / guard / check / marker / lock を単独で使用）を禁止する。semantic-key の「不透明トークン禁止」を識別子全般へ一般化したもの。

### 2. 正式名称主義

1 概念に 1 名。同義語の発明を禁止する（異名同義）。同名異義も禁止する。text-dictionary の思想をコード語彙・識別子へ拡張。

### 3. 多義語の意味固定

文脈によって意味が変わる語を単独で使用することを禁止し、複合語で一意に固定する。定義は同ディレクトリの `naming-values.txt`「多義語表」節を参照。

代表例: 単独 `main` 禁止 → `main-agent`（メインエージェント）/ `main-tree`（メインツリー）/ `main-branch`（main ブランチ）のみ許可。

### 4. 略語制限

不透明な略語を禁止する。業界標準略語は許可リスト方式（定義は `naming-values.txt`「許可略語リスト」節）。abbreviations 規約（ユーザー向け出力対象）の識別子版。

### 5. 語順規則

- 動作するもの（hook・スクリプト・シェル関数）: 動詞前置（check- / cleanup- / dispatch- / record- / delete- / validate- 等）
- 静的なもの（設定ファイル・データ・辞書・マーカー）: 名詞句

### 6. 派生一致

1 つの機構から派生する名前群（hook ファイル名 → 注入タグ → マーカー → 環境変数）は同一 slug から導出する。

派生パターン:
- hook ファイル名: `check-<slug>.sh`
- 注入タグ（advisory）: `[<SLUG>]`
- 注入タグ（block）: `[<SLUG>-BLOCK]`
- 注入タグ（skip）: `[<SLUG>-SKIP]`
- マーカー: `<slug>.<kind>`（kind = count / needed / test-passed 等）
- 環境変数: `CLAUDE_HOOK_<SLUG_UPPER>_RUNNING` / `<SLUG_UPPER>_SKIP_REASON`

### 7. 言語選択・casing・文字数

サーフェスごとの定義は `naming-values.txt`「casing 横断表」「言語選択マトリクス」節を参照。

### 8. 命名判定フロー

新しい名前を付ける前に以下の 3 手順を踏む:
1. 既存名の再利用可否を `grep -rn` で確認する
2. 当該サーフェスの定義規約を Read する
3. 本原則 1〜7 に照合する

## 機械強制

| timing | スクリプト | 注入タグ | 挙動 |
|---|---|---|---|
| PostToolUse(Write) | `check-identifier-naming.sh` | `[IDENTIFIER-NAMING-BLOCK]` | 監視パス（`~/.claude/rules/**` / `~/agent-home/skills/*/scripts/**` / `~/agent-home/tools/**`）への新規 `.sh` ファイル作成時、ファイル名の禁止動詞（`nuke-` / `scrub-` / `kill-`）または単独 `main`（`main-agent` / `main-tree` / `main-branch` は許可）を exit 2 で block |
| PostToolUse(Write) | `check-identifier-naming.sh` | `[IDENTIFIER-NAMING]` | ファイル名 slug と content 内の注入タグが派生一致（原則 6）していない場合に advisory 注入（exit 0） |

既存ファイルの編集は対象外（`was_created` または git untracked 判定で新規作成のみ検査）。

## 設計判断

### check-identifier-naming.sh / check-identifier-naming.test.sh

- **必要性**: 命名原則 3（多義語の意味固定）・5（語順規則）・6（派生一致）の違反は、ファイル作成の瞬間にしか安価に検知できない（作成後の rename は全参照追従を要する）。PostToolUse(Write) hook として自動発火させるにはスクリプト化が必須。禁止動詞・単独 main の判定と、content 内タグ抽出 → slug 照合という複数段の分岐を持ち、一行コマンドでは実装できない。`check-identifier-naming.test.sh` は hook の block / advisory / 素通り条件（8 ケース）を回帰検証するテストで、managing-agent-configs の rules テスト Phase から繰り返し実行される
- **代替案を採用しなかった理由**: Bash ツール直叩きは Write イベントに自動バインドできず、命名レビューが目視頼みに戻る。`~/.claude/rules/` 配下に Makefile / package.json は存在せず、新規導入は本チェック専用の依存を増やすだけになる
- **保守責任者**: 人手（ユーザー）。禁止動詞・許可複合語を変更する場合は本 rule.md・`naming-values.txt`・hook 本体・テストを同時に更新する
- **廃棄条件**: 本規約（common-principles）自体が廃止された時、または Claude Code 本体が命名 lint を標準機能として提供するようになった時

## 違反検知時の手順

本原則への違反を発見した場合:
1. 違反箇所の名前を特定する
2. 原則 1〜7 のどれに違反しているか判定する
3. 定義（naming-values.txt の該当節）を参照し、準拠する名前に変更する
4. `grep -rn "<旧名>"` で全参照を洗い出し追従する

## プロジェクト上書き

- 上書き可否: 一律適用
- 理由: 命名の意味論的品質はプロジェクトに依存しない普遍的な作業姿勢であり、受け口を設けない。サーフェス固有の形式値（casing・文字数）はサーフェス別規約が委譲受け口を持つ

## 関連

- `always/naming/commit-branch/rule.md` — コミット・ブランチ・ファイル名の命名規約
- `always/review-checklist/meaningful-key-naming/rule.md` — ドキュメント内の行識別子（本原則 1 の初出元）
- `always/review-checklist/text-dictionary/rule.md` — 文章語彙の置き換え辞書（本原則 2 の初出元）
- `always/review-checklist/term-explanation/rule.md` — ユーザー向け出力の略語制限（本原則 4 の初出元）
