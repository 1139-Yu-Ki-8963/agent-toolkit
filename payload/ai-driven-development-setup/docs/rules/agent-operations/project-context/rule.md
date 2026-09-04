---
key: project-context
title: プロジェクトコンテキスト
parent: agent-operations
summary: このリポジトリの概要・技術スタック・設定索引・ルート直下の許可リスト。
scope: always
paths: []
enforcement: advisory
checkable: false
checker: null
uncheckableReason: ルート直下の許可リストの照合は、このリポジトリの外にある共通の hook が行う
formatter: none
status: approved
origin: manual
workUnit: process
docType: context
derivedPath: .claude/rules/always/project-context/rule.md
---
# ai-driven-development-setup プロジェクトコンテキスト（PROJECT-CONTEXT）

## 概要

既存コードから AI駆動開発の基盤一式を作り、対象プロジェクトへ納品する支援ツールの定義リポジトリ。機能は `docs/skills/<単位>-<機能>/` に定義し、`.claude/skills/` へ派生させる。単位は setup / reverse / verify / portal / operate の5つ。

## 技術スタック

- Claude Code スキル定義（`SKILL.md` + `scripts/` + `templates/` + `tests/` + `samples/`）が本体。アプリケーションコードは持たない
- スクリプトは bash
- 設計文書と規約の定義は Markdown

## 設定索引

- 実装フロー設定: `.claude/rules/always/project-context/flow-values.yml`
- ルート直下許可リスト: 本ファイル末尾の「ルート直下許可ディレクトリ」節

## ルート直下許可ディレクトリ

| ディレクトリ名 | 用途 |
|---|---|
| docs | 定義（要件・設計・規約・機能の定義） |
| delivery-payload | 配布（納品先へ配る単位ごとの物。定義から機械で作る） |
| ai-work | 運用の記録（この体系を作り直す作業の計画・作業指示書・完了記録）。定義ではないため docs には置かない |
