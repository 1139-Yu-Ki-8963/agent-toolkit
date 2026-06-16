---
name: managing-skills
description: |
  スキルの作成・レビュー・実機検証を一貫したライフサイクルで担うハブ。
  TRIGGER when: 「スキルを作る/追加/設計/改善」「SKILL.md を作成」「スキルをレビュー/監査/点検」「スキルをテスト/発火検証」「managing-skills」と言われた時。
  SKIP: hooks 全般（→ managing-hooks）、命名のみ（→ naming-conventions）。
invocation: managing-skills
type: orchestration
allowed-tools: [Bash, Read, Write, Edit, Grep, Glob, Agent, AskUserQuestion]
---

# スキルライフサイクル管理ハブ

スキルの **作成 → 静的レビュー → 実機検証** を 1 つの動線で担うオーケストレーター。create したら review → test まで自動連鎖する。

## 設計思想

- **作りっぱなしを許さない**: スキルを書いた直後に、観点ベースの静的監査と白紙状態サブエージェントの発火検証まで連鎖させる
- **共通規約の単一正本化**: フロントマター・Type 決定木・文字数予算は `references/conventions.md` に集約し、create / review / test が同じ正本を参照する
- **段階的開示**: 本体ハブは振り分けのみ。各モードの詳細手順は `references/` に置き、必要時のみロードする

## モード判定

ユーザー発話のキーワードからモードを 1 つ選ぶ。複数候補がある場合は `AskUserQuestion` で確認する。

| 動詞・キーワード | モード | ロードする references | 自動連鎖 |
|---|---|---|---|
| 作る・追加・設計・改善・新規・create / add a skill | **create** | `conventions.md` + `creating.md` | → review → test |
| レビュー・監査・点検・観点チェック・review | **review** | `conventions.md` + `reviewing.md` | → test |
| テスト・発火検証・経験的チューニング・test | **test** | `conventions.md` + `testing.md` | （連鎖なし） |

判定が曖昧な場合や「全部やって」の場合は **create フル連鎖** に倒す。

## 共通の前段（必ず最初に実行）

1. **進捗の可視化**: 各モードの主要 Phase（references ロード・解析・修正承認・連鎖）を `TaskCreate` で登録し、開始時に `TaskUpdate` で `in_progress`、完了時に `completed` に切り替える。連鎖をまたぐ作業はタスクが切れがちになるため、ハブが入口で必ず作る
2. **規約のロード**: `references/conventions.md` を Read する。これがフロントマター必須項目・Type 9 種決定木・文字数予算の正本。これを読んでいないと作成・点検・検証のいずれも基準が定まらない

## create モード

1. `references/conventions.md` を Read（規約をロード）
2. `references/creating.md` を Read（手順・チェックリスト）
3. 新規スキルの `SKILL.md` を Write
4. 作成チェックリスト（作成後）の README.md エントリ追加まで完了
5. **自動連鎖**: 続けて review モードへ
6. **自動連鎖**: review 完了後、test モードへ

連鎖をスキップしたい場合は `AskUserQuestion` で「ここで終了する／レビューまでで止める／テストまで連鎖する」を確認する。デフォルトは **テストまで連鎖** とする。

## review モード

1. `references/conventions.md` を Read（規約をロード）
2. `references/reviewing.md` を Read（観点 A〜G・Phase 1〜7）
3. 観点詳細が必要なら `references/check-items.md` も Read
4. Phase 1〜5（対象発見・静的解析・実体検証・レポート・自動修正承認）を実行
5. **自動連鎖**: 続けて test モードへ

連鎖の制御は create モードと同じ。デフォルトは **テスト連鎖あり**。

## test モード

1. `references/conventions.md` を Read（規約をロード）
2. `references/testing.md` を Read（経験的チューニングのワークフロー）
3. **新規サブエージェント** を `Agent` ツールでディスパッチして白紙状態の発火検証を実行
4. 双方向評価レポートを集計
5. 必要に応じて反復（収束基準まで）

**重要**: test モードはセルフ再読で代替してはならない。バイアスが入る。サブエージェントをディスパッチできない環境では「empirical evaluation skipped: dispatch unavailable」と明示してスキップする。

## 連鎖の中断制御

各モード境界で自動連鎖する直前に、以下の条件のいずれかを満たす場合は `AskUserQuestion` を出す:

- 直前モードで CRITICAL 級の問題が検出されかつ修正未完了
- 直前モードがユーザー承認待ち（自動修正の承認など）で止まった
- ユーザーが事前に「作るだけ」「レビューまで」を明示している

それ以外は **連鎖を継続** が既定動作。「作って → 検証なし」を許す既定はバグの温床。

## 連鎖の終端報告

最終モードまで完了したら、以下を能動文・日本語で 1 報告にまとめる。

- 対象スキル名・対象モード（create / review / test のどれを通ったか）
- create 結果: 作成したスキルのパス
- review 結果: CRITICAL / WARN / INFO 件数、修正件数、未対応件数
- test 結果: 発火 PASS / FAIL 件数、誤発火スキル名、収束 / 発散 / リソース上限のいずれで停止したか
- 健全性判定（reviewing.md の健全性目安に従う）

## Gotchas

- モード判定は AI 任せにせず、ユーザー発話の動詞を直接見る。「作る + レビュー」が両方含まれるなら create モード（連鎖でレビューを含む）
- test モードは **必ず新規サブエージェント**。セルフ再読は禁止
- create 後の自動連鎖は既定 ON。OFF にするのはユーザーが明示的に止めた時のみ
- references/ のロードは「必要になってから」。ハブ本体だけで判断できる時は Read しない（トークン節約）

## 参照資料

### このスキルの詳細情報（必要時にロード）

- `references/conventions.md` — フロントマター必須項目・Type 9 種決定木・文字数予算・フォルダ構成（**全モードで最初に読む正本**）
- `references/creating.md` — 作成手順・推奨事項・チェックリスト
- `references/reviewing.md` — 観点 A〜G・Phase 1〜7・健全性目安
- `references/check-items.md` — 観点別の grep / python 検出式と修正前後例
- `references/testing.md` — 経験的チューニング・サブエージェント呼び出し規約・失敗パターン台帳
- `references/folder-structure.md` — フォルダ構成の推奨手順
- `references/description-examples.md` — description の書き方詳細例
- `references/anti-patterns.md` — アンチパターン集
- `references/advanced-techniques.md` — 高度なテクニック

### 型別テンプレート

- 手順型（orchestration / action / gateway / transform） → `assets/template-手順型.md`
- 条件付き知識型（reference） → `assets/template-条件付き知識型.md`
- 強制型（reactive / gate / audit / verification） → `assets/template-強制型.md`

### 関連スキル

- `naming-conventions` — スキル命名規則の正本
- `managing-hooks` — hooks 系の対応スキル（本スキルと構造は同型・create→review→test 連鎖）
