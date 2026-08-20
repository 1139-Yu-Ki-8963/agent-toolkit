<!-- ADAPT:detect:project-name | プロジェクト名に書き換える -->
# [プロジェクト名]

<!-- 事実は CLAUDE.md に、規範は .claude/rules/ に書く -->

## 概要

<!-- ADAPT:detect:project-summary | プロジェクトの概要を 2〜3 文で記入する -->

（ここにプロジェクトの概要を書く）

## 技術スタックと構成

<!-- ADAPT:detect:project-stack | 使用技術・ディレクトリ構成を記入する。形式: 「言語: ..., FW: ..., DB: ..., 構成: ...」 -->

（ここに技術スタックと構成を書く）

## 開発環境の前提

<!-- ADAPT:ask:project-env | 開発に必要な環境変数・ツール・セットアップ手順があれば記入し、無ければこのセクションごと削除する -->

（ここに開発環境の前提を書く）

## Claude Code 設定について

このプロジェクトの Claude Code 設定は `.claude/` ディレクトリに格納されています。

- **規範（ルール）**: `.claude/rules/` — 作業規範はすべてここに集約
- **運用マニュアル**: `.claude/README.md` — コマンド一覧・セットアップ・トラブルシュート
- **個人設定**: `CLAUDE.local.md`（git 管理外）に個人の好みを書く。テンプレートは `CLAUDE.local.md.example`
- **git worktree 併用時**: ホーム側ファイルの import 方式を推奨

## Adapt 履歴

<!-- /adapt が実行時にここへ追記する。手で編集しない -->
- （未実施）
