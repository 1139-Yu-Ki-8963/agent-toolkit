---
name: managing-agent-configs
description: "エージェント構成管理。 TRIGGER when: スキル/ルール/ルーティン/エージェント/フック作成・レビュー・テスト。 SKIP: 命名/settings.json（→naming-conventions/update-config）。"
invocation: managing-agent-configs
type: orchestration
allowed-tools: [Bash, Read, Write, Edit, Grep, Glob, Agent, AskUserQuestion]
---

# アセットライフサイクル管理ハブ

スキル・hooks・rules・ルーティン・サブエージェントという 5 種のアセットについて、**作成 → 静的レビュー → 実機検証** を 1 つの動線で担うオーケストレーター。旧 `managing-skills` / `managing-hooks` / `managing-rules` / `managing-routines` / `managing-subagents` を統合し、対象種別を判定した上で種別ごとの `references/<type>/` を必要時のみロードする。

## 設計思想

- **作りっぱなしを許さない**: create したら review → test まで自動連鎖する
- **骨格の単一正本化**: モード判定・連鎖制御・マーカー機構・終端報告の骨格は本体（このファイル）に集約し、型別の手順・観点・チェック項目は `references/<type>/` に分離する
- **段階的開示**: 本体ハブは「種別判定 → モード判定 → 該当 references のロード指示」のみを行う。種別固有の詳細（規約・作成手順・観点・テスト手順）は各 `references/<type>/*.md` に置き、必要時のみロードする
- **5 種の統合であって画一化ではない**: 種別ごとに配置先・観点・完了条件は異なる。共通化するのは「フロー構造」であり「内容」ではない

## 対象種別判定

ユーザー発話・対象ファイルパスから種別を 1 つ判定する。複数候補がある場合は `AskUserQuestion` で確認する。

| キーワード・対象ファイル | 種別 (asset_type) | 配置先 |
|---|---|---|
| スキル・SKILL.md・create a skill | `skills` | `~/agent-home/skills/<name>/SKILL.md` |
| フック・hook・settings.json の hooks | `hooks` | 配置 4 象限（`references/hooks/conventions.md` 参照） |
| ルール・rule・`~/.claude/rules/` | `rules` | `<category>-rules/rule.md` |
| ルーティン・routine・/schedule・CronCreate | `routines` | `~/agent-home/routines/<project>/routines/<name>/` |
| サブエージェント・agent・`~/.claude/agents/` | `subagents` | `~/.claude/agents/<name>/<name>.md` |

判定が曖昧な場合はユーザーに確認する。誤判定のまま進めると誤った `references/<type>/` をロードしてしまう。

## モード判定

種別が決まったら、動詞・キーワードからモードを判定する。全 5 種とも create → review → test の自動連鎖を持つ。

| 動詞・キーワード | モード | ロードする references | 自動連鎖 |
|---|---|---|---|
| 作る・追加・設計・改善・新規・create | **create** | `references/<type>/conventions.md` + `references/<type>/creating.md` | → review → test |
| レビュー・監査・点検・観点チェック・review・診断 | **review** | `references/<type>/conventions.md` + `references/<type>/reviewing.md`（hooks/rules は必要に応じ `check-items.md` も） | → test |
| テスト・発火検証・実機検証・test | **test** | `references/<type>/conventions.md` + `references/<type>/testing.md` | （連鎖なし） |

`hooks` と `rules` の review モードには full（修正あり）と dry-run（読み取り専用）の 2 系統がある。「診断」「読み取りのみ」と言われたら dry-run、それ以外は full。判定基準は `references/hooks/reviewing.md` / `references/rules/reviewing.md` に従う。

判定が曖昧な場合や「全部やって」の場合は **create フル連鎖** に倒す。

## 共通の前段（必ず最初に実行）

1. **進捗の可視化**: 各モードの主要 Phase（references ロード・解析・修正承認・連鎖）を `TaskCreate` で登録し、開始時に `TaskUpdate` で `in_progress`、完了時に `completed` に切り替える
2. **種別判定**: 上記「対象種別判定」に従い `asset_type` を確定する
3. **規約のロード**: `references/<asset_type>/conventions.md` を Read する。これが型別のフロントマター必須項目・命名・配置判定・文字数予算等の正本。これを読んでいないと作成・点検・検証のいずれも基準が定まらない
4. **外部正本の参照**（種別による）: `hooks` は `~/agent-home/ai-management-portal/design/hooks.html`、`rules` は `~/agent-home/ai-management-portal/design/rules.html`、`subagents` は `~/agent-home/ai-management-portal/design/subagent.html` も併せて参照する

## create モード

1. `references/<asset_type>/conventions.md` を Read（規約をロード）
2. `references/<asset_type>/creating.md` を Read（手順・チェックリスト）
3. 新規アセットを Write（配置先は「対象種別判定」表を参照。`hooks` は配置 4 象限からの ownership × scope 判定が必要）
4. `skills` 種別のみ: フロー系判定（Type が `orchestration` / `gateway`、または `## Phase` 見出しが 3 つ以上）を行い、該当する場合は `## 完了条件` / `## サブエージェント委任仕様` / `## ループ設計` の各セクションを補完する
5. `hooks` / `rules` 種別: hook script を settings.json の対応イベントに登録する
6. **ポータル更新**（`~/agent-home/ai-management-portal/` が存在する場合のみ実行。存在しなければスキップ）: `skills` 種別は ①ガイド HTML を `references/<name>-guide.html` に作成・更新する（テンプレート: `references/skills/template-guide.html`、手順: `references/skills/creating.md` 手順 10）②`~/agent-home/ai-management-portal/data/skill-categories.js` にカテゴリを追記する ③`node ~/agent-home/skills/managing-agent-configs/scripts/manage-portal.mjs generate` でカタログと数値を再生成する ④同 `verify` が exit 0 になることを確認する（`catalog/skills.html` と `index.html` の数値は手動編集しない）。他種別は対応するカタログページ（`catalog/hooks.html` / `catalog/rules.html` / `routines/index.html` / `catalog/subagents.html`）にエントリを追加し、規模数値は `node ~/agent-home/skills/managing-agent-configs/scripts/manage-portal.mjs generate` で再生成する。新規カタログページを増設する場合は `ai-management-portal/templates/page-catalog.html` をコピーする
7. **エイリアス表の更新**（`skills` 種別のリネーム・統合・削除時は必須）: `~/agent-home/sessions/.skill-log/skill-aliases.yml` に旧名 → 現行名（削除は unresolved セクション）を追記する。発火ログは生値記録のため、この表がないと利用実態の集計が壊れ、多用中スキルの誤削除につながる
8. **自動連鎖** で review モードへ、review 完了後さらに test モードへ

連鎖をスキップしたい場合は `AskUserQuestion` で「ここで終了する／レビューまでで止める／テストまで連鎖する」を確認する。デフォルトは **テストまで連鎖**。

## review モード

### full モード（修正あり、既定）

1. `references/<asset_type>/conventions.md` を Read
2. `references/<asset_type>/reviewing.md` を Read（`hooks` / `rules` は `check-items.md` も）
3. 型別の Phase（対象発見・静的解析・実体検証・レポート・自動修正承認）を実行。Phase 数・観点は種別ごとに異なるため `reviewing.md` の定義に従う。**修正を伴う場合は実施前に `ExitPlanMode` または `AskUserQuestion` でプラン承認を取る**
4. **自動連鎖**: 続けて test モードへ

### dry-run モード（`hooks` / `rules` のみ、読み取り専用）

1. `references/<asset_type>/conventions.md` を Read
2. `references/<asset_type>/reviewing.md` の該当観点のみ実行。`Edit` は発行せず、連鎖もしない

## test モード

1. `references/<asset_type>/conventions.md` を Read
2. `references/<asset_type>/testing.md` を Read（種別ごとの実機検証・サブエージェント呼び出し規約・失敗パターン台帳。`routines` のみ `ScheduleWakeup` によるクラウド実行の動的ループ）
3. **新規サブエージェント**（`routines` はメインセッション自身）が実機検証を実行する
4. 検証レポートを集計し、必要に応じて反復（収束基準まで）

**重要**: test モードはセルフ再読で代替してはならない。バイアスや実機固有バグ（シェル変数展開・パイプ・エスケープ等）は新規コンテキストでしか検出できない。サブエージェントをディスパッチできない環境では「empirical evaluation skipped: dispatch unavailable」と明示してスキップする。

### テスト完了マーカー

テスト全項目 PASS の場合、以下の Bash コマンドを実行してコミットゲートのマーカーを書き出す（`<type>` は `skills` / `rules` / `routines` / `hooks` のいずれか）。`skills` 種別はマーカー書き出しの前提として `manage-portal.mjs verify` の exit 0 も必須（`testing.md` の「整合性ゲート」セクション参照）:

```bash
dir=$(ls -td ${TMPDIR:-/tmp}/claude-hooks/*/ 2>/dev/null | head -1)
[ -n "$dir" ] && touch "${dir}managing-agent-configs-<type>-test-passed"
```

`managing-commit-gate.sh`（PreToolUse(Bash)）がこのマーカーの有無で `git commit` の許可を判定する。マーカーはセッション終了時に `cleanup-session-markers.sh` で自動削除される。`subagents` 種別は commit gate の対象外のためマーカー書き出し不要。

## 連鎖の中断制御

各モード境界で自動連鎖する直前に、以下の条件のいずれかを満たす場合は `AskUserQuestion` を出す:

- 直前モードで CRITICAL 級の問題が検出されかつ修正未完了
- 直前モードがユーザー承認待ち（自動修正の承認・配置移動の承認など）で止まった
- ユーザーが事前に「作るだけ」「レビューまで」「dry-run のみ」を明示している

それ以外は **連鎖を継続** が既定動作。「作って → 検証なし」を許す既定はバグの温床。

## 連鎖の終端報告

最終モードまで完了したら、以下を能動文・日本語で 1 報告にまとめる。

- 対象種別（skills / hooks / rules / routines / subagents）・対象アセット名・通過モード
- create 結果: 作成したファイルのパス
- review 結果: CRITICAL / WARN / INFO 件数、修正件数、未対応件数
- test 結果: 発火 PASS / FAIL 件数、収束 / 発散 / リソース上限のいずれで停止したか
- 健全性判定（`references/<type>/reviewing.md` の健全性目安に従う）

## Gotchas

- 種別判定を誤ると誤った `references/<type>/` をロードしてしまう。ユーザー発話の対象語（スキル/フック/ルール/ルーティン/エージェント）を直接見る
- test モードは **必ず新規サブエージェント**（`routines` のみ例外でメインセッションが `ScheduleWakeup` で直接回す）。セルフ再読は禁止
- create 後の自動連鎖は既定 ON。OFF にするのはユーザーが明示的に止めた時のみ
- references/ のロードは「必要になってから」。ハブ本体だけで判断できる時は Read しない（トークン節約）
- 統合前の `managing-skills` / `managing-hooks` / `managing-rules` / `managing-routines` / `managing-subagents` を呼ぶ箇所が外部にある場合は本スキルへ参照置換すること

## 参照資料

### skills 種別

- `references/skills/conventions.md` — フロントマター必須項目・Type 9 種決定木・文字数予算・フォルダ構成（**skills の全モードで最初に読む正本**）
- `references/skills/creating.md` — 作成手順・推奨事項・チェックリスト
- `references/skills/reviewing.md` — 観点 A〜G・Phase 1〜7・健全性目安
- `references/skills/check-items.md` — 観点別の grep / python 検出式と修正前後例
- `references/skills/testing.md` — 経験的チューニング・サブエージェント呼び出し規約・失敗パターン台帳
- `references/skills/folder-structure.md` — フォルダ構成の推奨手順
- `references/skills/description-examples.md` — description の書き方詳細例
- `references/skills/anti-patterns.md` — アンチパターン集
- `references/skills/advanced-techniques.md` — 高度なテクニック
- `references/skills/template-guide.html` — スキルガイド HTML の正本テンプレート
- `references/skills/template-手順型.md` / `template-条件付き知識型.md` / `template-強制型.md` — 型別テンプレート

### hooks 種別

- `references/hooks/conventions.md` — JSON 出力スキーマ・TAG プレフィックス・event 別パターン・timeout 目安・配置 4 象限（**hooks の全モードで最初に読む正本**）
- `references/hooks/creating.md` — 作成手順・配置決定・チェックリスト
- `references/hooks/reviewing.md` — 観点 A〜H（書式・配置・公式仕様）と I〜M（複雑度・無限ループ・曖昧さ・コンテキスト直書き・カテゴリ整合性）
- `references/hooks/check-items.md` — jq / grep 検出式と修正前後例
- `references/hooks/testing.md` — 実機検証・サブエージェント呼び出し規約・失敗パターン台帳
- `references/hooks/event-recipes.md` — event 別の入力 / 出力レシピ
- `references/hooks/examples.md` — settings.json 既存フックの実例カタログ
- `references/hooks/output-schema.md` — JSON 出力スキーマの完全リファレンス

### rules 種別

- `references/rules/conventions.md` — フォルダ構造・命名・eager/lazy 判定・hook 連携・ADR 必須項目（**rules の全モードで最初に読む正本**）
- `references/rules/creating.md` — 作成手順・カテゴリ判定・paths 判定・チェックリスト
- `references/rules/reviewing.md` — 観点と Phase 1〜6 の詳細手順
- `references/rules/check-items.md` — 観点別の grep / find 検出式と修正前後例
- `references/rules/testing.md` — 実機検証・サブエージェント呼び出し規約・失敗パターン台帳

### routines 種別

- `references/routines/conventions.md` — ディレクトリ構造・プロンプト形式・実行環境判定基準・命名規則
- `references/routines/creating.md` — 作成手順・設計書テンプレ・実行プロンプトテンプレ・登録方法
- `references/routines/reviewing.md` — 12 観点（A〜L）の詳細・Phase 1〜6・チェック項目・検出パターン
- `references/routines/testing.md` — ScheduleWakeup 動的ループ・RemoteTrigger 即時実行・[critical] 要件・収束基準
- `references/routines/cloud-operations.md` — クラウド Routine の登録・確認・変更手順（7 項目チェックリスト・/schedule コマンド）・検証項目

### subagents 種別

- `references/subagents/conventions.md` — frontmatter 必須項目・4 役割判定フロー・ツール選択基準（**subagents の全モードで最初に読む正本**）
- `references/subagents/creating.md` — 作成手順・チェックリスト
- `references/subagents/reviewing.md` — 観点 A〜D・Phase 1〜5
- `references/subagents/testing.md` — 実機検証・サブエージェント呼び出し規約

### 外部正本・関連スキル

- `references/related-and-external.md` — 外部正本（hooks/rules/subagent/loop 設計ガイド等）・関連スキル一覧
