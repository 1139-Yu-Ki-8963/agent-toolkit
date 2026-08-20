---
name: safe-commit
description: |
  確認つきコミット。混入チェック後に承認を得てから commit する。
  TRIGGER when: /safe-commit と入力された時
  SKIP: 自動実行しない（disable-model-invocation: true）
invocation: safe-commit
disable-model-invocation: true
argument-hint: "引数なしで実行"
---

# /safe-commit — 確認つきコミット

**push はしない。** commit のみを行う。

## Step 1: 現状確認

1. `git status` で変更状況を確認する
2. `git diff` と `git diff --staged` で差分を確認する
3. 無関係な変更の混入がある場合は以下を確認する:
   - 含める
   - 分けて後で commit する
   - 破棄する（勝手に破棄しない — 必ず確認を取る）

## Step 2: 混入チェック

以下の項目を確認する:

1. **秘密情報**: API キー・パスワード・トークンらしき値がないか確認する。見つけた場合は値を写さず、ファイル名と行番号のみを示す
2. **デバッグ残骸**: `console.log`・`debugger`・`TODO` 等の残骸がないか確認する
3. **巨大バイナリ**: 意図しない大きなバイナリファイルが含まれていないか確認する
4. **.env 系ファイル**: `.env`・`.env.local` 等が staging に含まれていないか確認する

## Step 3: メッセージ作成と実行

1. `git log --oneline -10` でリポジトリのコミットメッセージ規約を確認する
2. 規約に合わせたメッセージ案を作成する
3. 対象ファイル一覧とメッセージ案を提示し、承認を得る
4. 承認後に `git add`（対象ファイルを明示指定）と `git commit` を実行する
5. pre-commit hook が失敗した場合は原因を調査する。`--no-verify` は使わない
