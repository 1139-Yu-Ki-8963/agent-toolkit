---
name: running-reverse-screen-batch
description: |
  画面単位のリバース設計検証を claude -p 無人バッチで実行する。
  TRIGGER when: orchestrating-reverse-docs-flow から起動される時、画面数が多く一括無人処理が適切な時。
  SKIP: 画面が3件以下（通常セッションで逐次処理の方が速い）、個別画面の手動検証。
invocation: running-reverse-screen-batch
type: execution
allowed-tools: [Read, Write, Bash, Grep, Glob]
---

# 画面単位リバース検証バッチスキル

claude CLI のヘッドレスモード（`claude -p`、対話画面を介さず1回の呼び出しで完結する実行方式）で、対象画面を1画面=1呼び出しの無人バッチループで検証する。マーカー冪等性（同じ画面を再実行しても安全に再開できる性質）・limit耐性（API利用上限に達しても待機して再開する性質）・残ゼロまで継続の3要件を満たす。

本スキルは orchestrating-reverse-docs-flow から args 全量指定で起動される。AskUserQuestion を発行しない（対話ゼロ契約）。

## 使用タイミング

- TRIGGER: orchestrating-reverse-docs-flow の画面バッチ Phase から起動される時。画面数が4件以上で一括無人処理が適切な時
- SKIP: 画面が3件以下（通常セッションで逐次処理の方が速い）、個別画面の手動検証、ドライランのみ実施したい場合

## 起動引数

| 引数 | 必須 | 内容 |
|---|---|---|
| target_repo_path | 必須 | 対象プロジェクトのリポジトリルートパス |
| docs_root | 必須 | 設計書の書き出し先ルートパス |
| screen_ids | 必須 | 対象画面IDリスト（配列）。"all" で画面一覧HTMLから全画面を対象にする |
| template_root | 必須 | テンプレートディレクトリパス（shared/templates/リバース検証/画面/） |
| common_docs_root | 必須 | プロジェクト共通設計書ディレクトリパス |
| survey_doc_path | 必須 | アーキテクチャ調査書のファイルパス |
| model | 任意 | claude -p に渡すモデル名。既定: claude-haiku-4-5-20251001 |
| wait_seconds | 任意 | limit検知時の待機秒数。既定: 3600 |
| fail_limit_k | 任意 | 同一画面の連続失敗上限。既定: 3 |
| log_path | 任意 | 実行ログ出力先。既定: docs_root/batch-log.txt |

## 前提（実機確認済み CLI 仕様）

claude CLI 2.1.206 で実機確認済みの仕様。

- `-p/--print`・`--allowedTools`・`--permission-mode`（acceptEdits/auto/bypassPermissions/manual/dontAsk/plan）・`--output-format`（text/json/stream-json）・`--no-session-persistence` が存在する
- `--worktree` フラグは存在しない。worktree が必要なら呼び出し側で `git worktree` を事前に用意する
- ヘッドレス実行中の対話承認は不可能。無人化には `--allowedTools` と `--permission-mode` が必須
- 大量呼び出し時は `--no-session-persistence` で `~/.claude/projects/` の肥大化を防ぐ
- `claude -p` はローカル実行。Mac 本体のスリープで停止する
- サンドボックスの外向き接続制限に当たるため、起動コマンドは dangerouslyDisableSandbox: true で実行する

## Phase 1: 引数検証と対象一覧生成

### Step 1-1: 引数を検証する

全必須引数（target_repo_path・docs_root・screen_ids・template_root・common_docs_root・survey_doc_path）の存在と、参照先パスの実在を確認する。不足があればエラーメッセージを返して即終了する。

**完了**: 全必須引数が検証済みで、参照先パスが実在する。

### Step 1-2: 画面一覧を生成する

screen_ids が "all" の場合は画面一覧HTML（`<docs_root>/一覧/画面一覧.html`）のマニフェストJSONから全画面IDを抽出する。指定リストの場合はそのまま使う。1行1画面IDのテキストファイル（`<docs_root>/batch-targets.txt`）に書き出す。既検証画面（レジストリで status=baseline-established または verification-pass）をカウントし、未検証件数を確認する。

**完了**: 対象画面一覧ファイルが生成され、総数と既検証数が確認済み。

## Phase 2: 単発ドライラン

### Step 2-1: 1画面実行し成否判定を検証する

Bash ツール（dangerouslyDisableSandbox: true）で対象一覧の先頭1画面だけをフォアグラウンド実行する。per-item prompt（後述）を使い、claude -p で1画面の全工程（開通→事実→基本設計→詳細設計→基準確立→往復検証）を通す。実行後、検証完了マーカーの実在を確認する。

**合格するまで Phase 3 に進むことを禁止する。**

失敗時の切り分け手順:
1. limit 文言が出力に含まれる → 時間帯を変えて再試行
2. マーカー未付与だが途中まで進んでいる → per-item prompt の工程指示を確認・修正
3. 起動自体が失敗 → sandbox 設定・モデル名・allowedTools を確認

**完了**: ドライラン1画面で検証パイプライン全工程の完走とマーカー付与を確認済み。

## Phase 3: 無人ループ起動

### Step 3-1: ループスクリプトにパラメータを反映する

Read ツールで `references/loop-design.md` の雛形を読み込み、確定値（TARGETS_FILE・MARKER・CHECK_CMD・LOG・WAIT_SECONDS・FAIL_LIMIT_K・MODEL・ALLOWED_TOOLS・PER_ITEM_PROMPT・FAILED_LIST・FAIL_COUNTS）を埋める。埋めた内容はディスクに保存せず、次 Step の Bash コマンド文字列にそのまま展開する。

**完了**: 全プレースホルダが実値に置換され、実行可能なコマンド文字列が組み上がっている。

### Step 3-2: バックグラウンド起動しPID生存を確認する

Bash ツール（dangerouslyDisableSandbox: true）で `nohup bash -c '...' >> ログ 2>&1 & disown` 構造で起動する。起動直後にPIDを取得し、10秒後に `kill -0 $PID` で生存確認する。

**完了**: PIDの生存確認が取れ、監視コマンド（`tail -f <ログ>`）が報告済み。

## Phase 4: 監視と完了確認

### Step 4-1: 残件カウントと完了判定

Bash ツールで残件カウントコマンドを実行する。マーカー未付与かつfailedリスト外の画面数を計算する。残ゼロ、またはfailedリストへの退避で全画面確定していれば完了とする。

**完了**: 全画面が検証完了またはfailedリスト退避で確定している。

## Phase 5: 完了報告

### Step 5-1: 完了報告を提示する

最終の残件数・failed件数・実周回数を再カウントし報告する。failedリストがある場合は画面ID一覧と失敗理由（ログ末尾から抽出）を添える。

**完了**: 完了報告提示済み。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 引数検証済み・対象画面一覧生成済み |
| Phase 2 | ドライラン1画面で全工程完走確認済み。合格前はPhase 3に進まない |
| Phase 3 | PID生存確認済み・監視コマンド報告済み |
| Phase 4 | 全画面が検証完了またはfailed退避で確定 |
| Phase 5 | 完了報告提示済み |
| **Goal** | **全対象画面が検証完了（failedリスト分を除く）かつ完了報告提示済み** |

## ループ設計

| 層 | 反復条件 | 上限・停止条件 |
|---|---|---|
| 周回ループ | 未検証残（マーカー未付与かつfailedリスト外）> 0 | 周回数に上限なし（意図的）。停止は (1) 収束: 全画面マーカー付与済みで remaining=0 (2) 発散検知: 各画面がK回連続失敗でfailed退避。対象数有限なら必ず終了する |
| 対象ループ | 画面一覧を先頭から1件ずつ処理 | マーカー既存ならスキップ。`claude -p` 実行後マーカー実在で成否判定(終了コードは使わない)。未付与なら失敗カウント加算、K回でfailed退避 |
| limit待機 | 出力にlimit文言パターンを検知 | 検知したらWAIT_SECONDS秒sleepして再開。当該画面は未完のまま次周回で再試行 |

## 画面1件の処理パイプライン

claude -p 1回の呼び出しで、1画面に対して以下の工程を順に実行する（per-item prompt が指示する）:

1. **画面開通**: 画面ディレクトリ作成・基準ファイル配置・レジストリ記帳
2. **事実封印**: 対象ファイルの facts 抽出と封印
3. **基本設計著述**: 画面基本設計書の生成
4. **詳細設計著述**: 画面詳細設計書の生成
5. **基準確立**: baseline tag の確立
6. **往復検証**: 設計書のみからコード再生成 → 原本との突合

各工程は既存の子スキルと同じロジックを Skill ツールで順次起動する形で per-item prompt に記述する。全工程完了で画面レジストリの status を更新する（=マーカー付与）。

## マーカー仕様

- **マーカー判定**: 画面レジストリ（`<docs_root>/一覧/reverse-screen-registry.yml`）内の当該画面エントリで `status` が `baseline-established` または `verification-pass`
- **CHECK_CMD**: 画面レジストリファイルを読み、当該 screen_id のブロック内に上記 status が存在するかを grep で判定

## 予想を裏切る挙動

- `--worktree` フラグは存在しない。worktree が必要なら事前に `git worktree` を用意する
- バックグラウンドシェルの寿命が短いため `nohup` + `disown` + 起動10秒後の生存確認が必須
- サンドボックスが外向き接続を制限するため dangerouslyDisableSandbox: true が必須
- 終了コードは信用しない。成否はマーカー実在の grep で判定する
- 周回ループに上限はない（意図的。`references/gotchas.md` 参照）
- 1画面あたりの処理時間は工程数が多いため 5〜15 分を見込む

## 参照資料

- `references/loop-design.md` — ループ雛形・プレースホルダ定義・limit検知パターン
- `references/gotchas.md` — 落とし穴集

## 設計判断

`scripts/` ディレクトリを置かない。ループ本体をディスク保存しない方針と整合させるため、雛形からその都度インライン展開する。これにより生成されたループがスキルディレクトリの存在に依存しない自己完結構造になり、スキル呼び出し元のセッションが終了した後もバックグラウンドプロセス単体で完走できる。

元スキル（running-headless-batch）から本スキルへの主な変更点:
- AskUserQuestion を全面撤廃し args 全量指定の対話ゼロ契約に変更
- per-item の対象を汎用ファイルから「画面」に特化
- per-item prompt を orchestrating-reverse-docs-flow の画面処理パイプライン（開通→事実→基本設計→詳細設計→基準確立→往復検証）に特化
- sandbox 無効化を args ではなく常時有効として設計（claude -p の API 到達に必須のため）
