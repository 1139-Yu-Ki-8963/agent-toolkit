---
name: managing-hooks
description: |
  hooks の作成・レビュー・実機検証を一貫したライフサイクルで担うハブ。
  TRIGGER when: 「フックを作る/追加/設計」「PreToolUse/PostToolUse/SessionStart/Stop」「hooks をレビュー/監査/診断/点検」「hooks の複雑度/無限ループ」「フックをテスト/発火検証」「managing-hooks」と言われた時。
  SKIP: SKILL.md 系（→ managing-skills）、settings.json の permissions/env など hooks 以外（→ update-config）、命名のみ（→ naming-conventions）。
invocation: managing-hooks
type: orchestration
allowed-tools: [Bash, Read, Write, Edit, Grep, Glob, Agent, AskUserQuestion]
---

# Hooks ライフサイクル管理ハブ

settings.json hooks の **作成 → 静的レビュー → 実機検証** を 1 つの動線で担うオーケストレーター。create したら review → test まで自動連鎖する。`managing-skills` の hooks 版。

## 設計思想

- **作りっぱなしを許さない**: hook を書いた直後に、公式仕様準拠・配置規約・設計観点（複雑度／無限ループ／コンテキスト直書き）を静的監査し、サブエージェントの実機 bash 検証まで連鎖させる
- **共通規約の単一正本化**: JSON 出力スキーマ・TAG プレフィックス・event 別パターン・timeout 目安・配置 4 象限は `references/conventions.md` に集約し、create / review / test が同じ正本を参照する
- **diagnose を review に吸収**: 設計面の 5 観点（複雑度・無限ループ・解釈の曖昧さ・コンテキスト直書き・カテゴリ整合性）は review モードの拡張観点として統合。読み取り専用にしたい時は review モードを **dry-run** で起動する
- **段階的開示**: 本体ハブは振り分けのみ。各モードの詳細手順は `references/` に置き、必要時のみロードする

## モード判定

ユーザー発話のキーワードからモードを 1 つ選ぶ。複数候補がある場合は `AskUserQuestion` で確認する。

| 動詞・キーワード | モード | ロードする references | 自動連鎖 |
|---|---|---|---|
| 作る・追加・設計・新規 / PreToolUse / PostToolUse / SessionStart / Stop | **create** | `conventions.md` + `creating.md` | → review → test |
| レビュー・監査・点検・設定を見直す・公式仕様準拠 | **review**（full） | `conventions.md` + `reviewing.md` + `check-items.md` | → test |
| 診断・複雑度・無限ループ・読み取りのみ | **review**（dry-run） | `conventions.md` + `reviewing.md` の観点 I〜M のみ | （連鎖なし） |
| テスト・発火検証・実機 bash で確認 | **test** | `conventions.md` + `testing.md` | （連鎖なし） |

判定が曖昧な場合や「全部やって」の場合は **create フル連鎖** に倒す。

## 共通の前段（必ず最初に実行）

1. **進捗の可視化**: 各モードの主要 Phase（references ロード・静的解析・実体検証・修正承認・test 連鎖）を `TaskCreate` で登録し、開始時に `TaskUpdate` で `in_progress`、完了時に `completed` に切り替える。連鎖をまたぐ作業はタスクが切れがちになるため、ハブが入口で必ず作る
2. **規約のロード**: `references/conventions.md` を Read する。これが JSON 出力スキーマ・TAG プレフィックス・event 別パターン・timeout 目安・配置 4 象限の正本。これを読んでいないと作成・点検・検証のいずれも基準が定まらない。

## create モード

1. `references/conventions.md` を Read（規約をロード）
2. `references/creating.md` を Read（手順・チェックリスト）
3. 配置 4 象限から ownership × scope を判定し、配置先パスを決定
4. hook script を Write
5. ADR を `~/.claude/adr/` または `<repo>/docs/adr/` に作成
6. 自前の hook カタログがあれば登録（任意）
7. `settings.json` の対応イベントに command path を登録
8. **自動連鎖**: 続けて review モード（full）へ
9. **自動連鎖**: review 完了後、test モードへ

連鎖をスキップしたい場合は `AskUserQuestion` で「ここで終了する／レビューまでで止める／テストまで連鎖する」を確認する。デフォルトは **テストまで連鎖**。

## review モード

### full モード（修正あり）

1. `references/conventions.md` を Read
2. `references/reviewing.md` + `references/check-items.md` を Read（観点 A〜H・I〜M、jq / grep 検出式）
3. Phase 1〜5（対象 settings.json 発見・静的解析・実体検証・レポート・自動修正承認）を実行
4. **自動連鎖**: 続けて test モードへ

### dry-run モード（読み取り専用）

1. `references/conventions.md` を Read
2. `references/reviewing.md` の観点 I〜M（複雑度・無限ループ・解釈曖昧さ・コンテキスト直書き・カテゴリ整合性）のみ実行
3. レポート出力で終了。`Edit` は発行しない。連鎖もしない

dry-run は読み取り専用の診断モード。「修正は別途検討したい」「読み取りのみで安全に診断したい」場合に使う。

## test モード

1. `references/conventions.md` を Read
2. `references/testing.md` を Read（実機検証のワークフロー・サブエージェント呼び出し規約・失敗パターン台帳）
3. **新規サブエージェント** を `Agent` ツールでディスパッチし、bash 実機で command を叩かせる
4. 双方向評価レポート（JSON valid / スキーマ準拠 / TAG プレフィックス / 非マッチ動作 / timeout / 副作用）を集計
5. 必要に応じて反復（収束基準まで）

**重要**: test モードはセルフ再読で代替してはならない。シェル変数展開・パイプ・エスケープのバグは実機でしか出ない。サブエージェントをディスパッチできない環境では「empirical hook evaluation skipped: dispatch unavailable」と明示してスキップする。

## 連鎖の中断制御

各モード境界で自動連鎖する直前に、以下の条件のいずれかを満たす場合は `AskUserQuestion` を出す:

- 直前モードで CRITICAL 級の問題が検出されかつ修正未完了
- 直前モードがユーザー承認待ち（自動修正の承認・配置移動の承認）で止まった
- ユーザーが事前に「作るだけ」「レビューまで」「dry-run のみ」を明示している

それ以外は **連鎖を継続** が既定動作。

## 連鎖の終端報告

最終モードまで完了したら、以下を能動文・日本語で 1 報告にまとめる。

- 対象ファイル・対象モード（create / review-full / review-dry / test のどれを通ったか）
- create 結果: 配置先パス・登録した ADR / hooks.html / settings.json
- review 結果: CRITICAL / WARN / INFO 件数、修正件数、未対応件数
- test 結果: 全 critical 要件 PASS / FAIL 件数、失敗 hook ID、収束 / 発散 / リソース上限のいずれで停止したか
- 健全性判定（reviewing.md の健全性目安に従う）

## Gotchas

- モード判定は AI 任せにせず、ユーザー発話の動詞を直接見る。「診断」と言われたら review dry-run、「レビュー」と言われたら review full
- test モードは **必ず新規サブエージェント**。セルフ再読は禁止
- create 後の自動連鎖は既定 ON。OFF にするのはユーザーが明示的に止めた時のみ
- `if` 条件は bash 直接実行で検証不可。静的チェック（コロンなし・スペース区切り・`Bash(tool *)` 形式）が唯一の手段
- 配置 4 象限から外れた flat `hooks/` バケットへの新規作成は `hooks-architecture-check.sh` が PreToolUse で block する。create 時は最初に配置を決める

## 参照資料

### このスキルの詳細情報（必要時にロード）

- `references/conventions.md` — JSON 出力スキーマ・TAG プレフィックス・event 別パターン・timeout 目安・配置 4 象限（**全モードで最初に読む正本**）
- `references/creating.md` — 作成手順・配置決定・チェックリスト
- `references/reviewing.md` — 観点 A〜H（書式・配置・公式仕様）と I〜M（複雑度・無限ループ・曖昧さ・コンテキスト直書き・カテゴリ整合性）
- `references/check-items.md` — jq / grep 検出式と修正前後例
- `references/testing.md` — 実機検証・サブエージェント呼び出し規約・失敗パターン台帳
- `references/event-recipes.md` — event 別の入力 / 出力レシピ
- `references/examples.md` — settings.json 既存フックの実例カタログ
- `references/output-schema.md` — JSON 出力スキーマの完全リファレンス

### 関連スキル

- `update-config` — settings.json への書き込み・移動・権限管理（hooks 以外も含む）
- `naming-conventions` — フックが注入する命名ルールの正本
- `managing-skills` — SKILL.md 側の対応スキル（本スキルと構造は同型）
- `clarifying-ambiguity` / `writing-quality` — フックから呼び出されるサブエージェント側のスキル
