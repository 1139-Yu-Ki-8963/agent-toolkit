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

無人モード（headless=true）では工程の開始・完了のたびに `<verification_dir>/progress.jsonl` へ JSON 行を追記する（形式: `{"ts":"<ISO8601>","screen_id":"<画面ID>","phase":"<工程名>","status":"started|completed|failed"}`）。呼び出し元セッションや人間はこのファイルの監視で現在工程を把握できる。

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
| model | 任意 | claude -p に渡すモデル名。既定: claude-sonnet-5（事実封印・往復検証は分析・判断を伴い Haiku では精度不足のため） |
| wait_seconds | 任意 | limit検知時の待機秒数。既定: 3600 |
| fail_limit_k | 任意 | 同一画面の連続失敗上限。既定: 3 |
| log_path | 任意 | 実行ログ出力先。既定: `<verification_dir>/バッチ運転記録/batch-log.txt` |
| lane_id | 任意 | レーン識別子。複数レーン並列起動時に指定。未指定なら単一レーン運転。ログは `<verification_dir>/バッチ運転記録/batch-log-<lane_id>.txt`、failed リストは `<verification_dir>/バッチ運転記録/failed-screens-<lane_id>.txt`、conflict-skip リストは `<verification_dir>/バッチ運転記録/conflict-skip-screens-<lane_id>.txt` にレーン別分離 |
| deadline | 任意 | 時限（ISO 8601日時）。指定時はこの時刻以降に新規画面への着手を停止する（ソフト停止）。未指定なら従来どおり残ゼロまで継続 |

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

screen_ids が "all" の場合は画面一覧HTML（`<docs_root>/一覧/画面一覧.html`）のマニフェストJSONから全画面IDを抽出する。指定リストの場合はそのまま使う。1行1画面IDのテキストファイル（`<docs_root>/batch-targets.txt`）に書き出す。既検証画面（レジストリで status=baseline-established）をカウントし、未検証件数を確認する。

**完了**: 対象画面一覧ファイルが生成され、総数と既検証数が確認済み。

## Phase 2: 単発ドライラン

### Step 2-1: 1画面実行し成否判定を検証する

Bash ツール（dangerouslyDisableSandbox: true）で対象一覧の先頭1画面だけをフォアグラウンド実行する。前半 per-item prompt（後述）を使い claude -p を1回実行し、画面レジストリの当該エントリ status が `authored` になったことを確認する。続けて後半 per-item prompt で claude -p をもう1回実行し、status が `baseline-established` になったことを確認する（前半・後半は別プロセスで、盲検分離を満たす）。

**合格するまで Phase 3 に進むことを禁止する。**

失敗時の切り分け手順:
1. limit 文言が出力に含まれる → 時間帯を変えて再試行
2. マーカー未付与だが途中まで進んでいる → per-item prompt（前半/後半どちらか）の工程指示を確認・修正
3. 起動自体が失敗 → sandbox 設定・モデル名・allowedTools を確認

**完了**: ドライラン1画面で前半（status=authored）・後半（status=baseline-established）の両工程完走とマーカー付与を確認済み。

## Phase 3: 無人ループ起動

### Step 3-1: ループスクリプトにパラメータを反映する

Read ツールで `references/loop-design.md` の雛形を読み込み、確定値（TARGETS_FILE・MARKER_REGISTRY・CHECK_CMD・LOG・WAIT_SECONDS・FAIL_LIMIT_K・MODEL・ALLOWED_TOOLS・PER_ITEM_PROMPT_FIRST・PER_ITEM_PROMPT_SECOND・FAILED_LIST・FAIL_COUNTS）を埋める。埋めた内容はディスクに保存せず、次 Step の Bash コマンド文字列にそのまま展開する。

**完了**: 全プレースホルダが実値に置換され、実行可能なコマンド文字列が組み上がっている。

### Step 3-2: バックグラウンド起動しPID生存を確認する

Bash ツール（dangerouslyDisableSandbox: true）で `nohup bash -c '...' >> ログ 2>&1 & disown` 構造で起動する。起動直後にPIDを取得し、10秒後に `kill -0 $PID` で生存確認する。

**完了**: PIDの生存確認が取れ、監視コマンド（`tail -f <ログ>`）が報告済み。

## Phase 4: 監視と完了確認

### Step 4-1: 残件カウントと完了判定

Bash ツールで残件カウントコマンドを実行する。マーカー未付与かつfailedリスト・conflict-skipリスト外の画面数を計算する。残ゼロ、またはfailedリスト・conflict-skipリストへの退避で全画面確定していれば完了とする。

**完了**: 全画面が検証完了またはfailedリスト・conflict-skipリスト退避で確定している。

## Phase 5: 完了報告

### Step 5-1: 完了報告を提示する

最終の残件数・failed件数・conflict-skip件数・実周回数を再カウントし報告する。failedリストがある場合は画面ID一覧と失敗理由（ログ末尾から抽出）を添える。conflict-skipリストがある場合は画面ID一覧を添える（競合スキップは失敗ではないため理由欄は「他プロセス使用中」の定型文とする）。

時限終了時の完了報告には「締切時刻・処理完了画面数・仕掛り画面（前半のみ完了＝authored 等の中間状態）・未着手残数」を必ず記載する。マーカー冪等性により、翌回の起動で仕掛りから自然再開できる。

**完了**: 完了報告提示済み。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 引数検証済み・対象画面一覧生成済み |
| Phase 2 | ドライラン1画面で全工程完走確認済み。合格前はPhase 3に進まない |
| Phase 3 | PID生存確認済み・監視コマンド報告済み |
| Phase 4 | 全画面が検証完了・failed退避・conflict-skip退避のいずれかで確定 |
| Phase 5 | 完了報告提示済み |
| **Goal** | **全対象画面が検証完了（failedリスト・conflict-skipリスト分を除く）かつ完了報告提示済み** |

## ループ設計

| 層 | 反復条件 | 上限・停止条件 |
|---|---|---|
| 周回ループ | 未検証残（マーカー未付与かつfailedリスト・conflict-skipリスト外）> 0 | 周回数に上限なし（意図的）。停止は (1) 収束: 全画面マーカー付与済みで remaining=0 (2) 発散検知: 各画面がK回連続失敗でfailed退避。対象数有限なら必ず終了する |
| 対象ループ | 画面一覧を先頭から1件ずつ処理。前半・後半の計2回 `claude -p` を呼び出す | `status: baseline-established` ならスキップ。前半は `status: authored` の実在、後半は `status: baseline-established` の実在で成否判定する（終了コードは使わない）。未達なら失敗カウント加算、K回でfailed退避 |
| 環境スロット解放 | 対象画面が `baseline-established` に到達（後半完了）した直後に実施 | syncing-reverse-env の mode=teardown の軽量版（ポート・プロセスのみ解放し、baseline_tag・成果物は保持）を実行し、次画面のためにスロットを確保する |
| スロット枯渇時の自動回収 | 前半 claude -p の画面開通で syncing-reverse-env がスロット不足 ERROR を返した場合 | headless_approved_ops に `環境撤去` が含まれていれば、基準確立済みで最も古い環境を軽量解放して再試行する。含まれていなければ failed リストへ退避する |
| 開通競合検知 | unlocking-reverse-target-screens が `status=CONFLICT-SKIPPED`（他プロセスが同一画面の作業コピー・devサーバー等を使用中）を返した場合 | 当該画面を競合スキップとして conflict-skip リストへ記録し、他プロセスの環境には一切触れず次の画面へ続行する。競合スキップは failed とは別区分とし、失敗カウント（fail_limit_k）には加算しない |
| limit待機 | 出力にlimit文言パターンを検知 | 検知したらWAIT_SECONDS秒sleepして再開。当該画面は未完のまま次周回で再試行 |
| 時限到達 | deadline 指定時のみ。次の claude -p 呼び出しに着手する前に現在時刻と deadline を比較し、超過していれば新規着手せず終了する。limit 待機中も deadline を再評価し、超過なら再開せず終了する。実行中の呼び出しは中断しない（ソフト停止） |

### 並列レーン運用

横展開（400画面超）では複数レーンを並列起動する。以下の排他制御を適用する:

- **ファイルロック**: 画面レジストリ（reverse-screen-registry.yml）・一覧配下・progress.jsonl への書き込みは `flock <ロックファイル>` で排他する。ロック取得失敗時は 1 秒待機 × 最大 30 回リトライ
- **worktree ロック**: 同一リポジトリへの `git worktree add/remove` は `flock -w 120 <リポジトリルート>/.reverse-worktree-ops.lock` で直列化する（最大120秒待機。正本は contract.md の「worktree 排他」節）
- **担当画面の事前分割**: 統括スキルまたは呼び出し元が画面リストをレーン数で分割し、各レーンの `screen_ids` に重複なく配分する。同一画面の複数レーン処理を禁止する
- **ログ・failed リスト・conflict-skip リストの分離**: レーン別に `<verification_dir>/バッチ運転記録/batch-log-<lane_id>.txt` / `<verification_dir>/バッチ運転記録/failed-screens-<lane_id>.txt` / `<verification_dir>/バッチ運転記録/conflict-skip-screens-<lane_id>.txt` を使用。完了報告時にレーン別結果を統合する

## 画面1件の処理パイプライン

盲検分離（原本コードを読む工程と設計書のみで判定する工程を別プロセスに分離する要件。正本は `orchestrating-reverse-docs-flow` の `references/contract.md` の「無人モード仕様」の「盲検分離の必須要件」）を満たすため、1画面につき claude -p を前半・後半の2回に分けて呼び出す。前半と後半は別プロセスで実行されるため、前半で読んだ原本コードの情報が後半のコンテキストに混入しない。

### 前半（1回目 claude -p）: 著述

1. **画面開通**: 画面ディレクトリ作成・基準ファイル配置・レジストリ記帳（unlocking-reverse-target-screens）
2. **事実封印**: 対象ファイルの facts 抽出と封印（extracting-unit-facts-from-code）
3. **基本設計著述**: 画面基本設計書の生成（generating-reverse-basic-design）
4. **詳細設計著述**: 画面詳細設計書の生成（generating-reverse-detailed-design）

前半完了時、画面レジストリの当該エントリ `status` を `authored` に更新する（=中間マーカー付与）。

### 後半（2回目 claude -p）: ファイル単位盲検検証・往復検証

前半完了（`status: authored`）を前提条件として開始する。原本コードは一切読まない（盲検）。

1. **ファイル単位盲検検証**: rebuilding-screen-unit-from-docs で対象ファイルを白紙化し設計書のみから再現する（無人モードでは任意工程ではなく必須工程）
2. **基準確立**: syncing-reverse-env mode=sync で baseline tag を確立
3. **往復検証（implement）**: rebuilding-code-from-docs mode=implement で設計書のみからコード再生成し比較要求を得る
4. **往復検証（judge）**: syncing-reverse-env mode=sync,dry-run の比較結果ブロックを rebuilding-code-from-docs mode=judge に渡して判定する

後半完了時、画面レジストリの当該エントリ `status` を `baseline-established` に更新する（=検証完了マーカー付与）。

各工程は既存の子スキルと同じロジックを Skill ツールで順次起動する形で、前半用・後半用の2種の per-item prompt にそれぞれ記述する。

**per-item prompt の必須文言**: 無人モードではいかなる工程・用途でも Agent ツールのバックグラウンド起動を使用してはならない（正本は `orchestrating-reverse-docs-flow` の `references/contract.md` の「無人モード仕様」）。前半・後半それぞれの per-item prompt（`references/loop-design.md` §4 のテンプレート）は、この禁止文言をプロンプト本文へ逐語で含めることを必須とする。プロンプト内で Skill ツール起動を指示する記述と併記し、claude -p が起動する側のサブエージェントにも同じ制約を確実に伝播させる。

## マーカー仕様

- **中間マーカー判定（前半完了）**: 画面レジストリ（`<docs_root>/一覧/reverse-screen-registry.yml`）内の当該画面エントリで `status` が `authored`
- **完了マーカー判定（後半完了）**: 同エントリで `status` が `baseline-established`
- **CHECK_CMD**: 画面レジストリファイルを読み、当該 screen_id のブロック内に `status: baseline-established` が存在するかを grep で判定する（`verification-pass` は廃止済み。旧値が残る台帳の読み替え手順は `orchestrating-reverse-docs-flow` の `references/contract.md` の「レジストリ移行手順」を参照）

## 予想を裏切る挙動

- `--worktree` フラグは存在しない。worktree が必要なら事前に `git worktree` を用意する
- バックグラウンドシェルの寿命が短いため `nohup` + `disown` + 起動10秒後の生存確認が必須
- サンドボックスが外向き接続を制限するため dangerouslyDisableSandbox: true が必須
- 終了コードは信用しない。成否はマーカー実在の grep で判定する
- 周回ループに上限はない（意図的。`references/gotchas.md` 参照）
- 1画面あたりの処理時間は実測ベースで前半・後半合わせて60分程度を見込む（事実封印・往復検証は分析・判断を伴い時間を要するため、初期見積りの5〜15分から実測値へ改めた）

## 参照資料

- `references/loop-design.md` — ループ雛形・プレースホルダ定義・limit検知パターン
- `references/gotchas.md` — 落とし穴集

## 設計判断

`scripts/` ディレクトリを置かない。ループ本体をディスク保存しない方針と整合させるため、雛形からその都度インライン展開する。これにより生成されたループがスキルディレクトリの存在に依存しない自己完結構造になり、スキル呼び出し元のセッションが終了した後もバックグラウンドプロセス単体で完走できる。

元スキル（running-headless-batch）から本スキルへの主な変更点:
- AskUserQuestion を全面撤廃し args 全量指定の対話ゼロ契約に変更
- per-item の対象を汎用ファイルから「画面」に特化
- per-item prompt を orchestrating-reverse-docs-flow の画面処理パイプライン（前半: 開通→事実→基本設計→詳細設計／後半: ファイル単位盲検検証→基準確立→往復検証）に特化。前半・後半を別 claude -p 呼び出しに分離し盲検分離を満たす
- sandbox 無効化を args ではなく常時有効として設計（claude -p の API 到達に必須のため）
