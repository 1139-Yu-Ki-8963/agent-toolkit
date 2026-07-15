---
paths:
  - "**/.claude/**"
  - "**/agent-home/skills/**"
  - "**/agent-home/tools/**"
  - "**/settings.json"
  - "**/settings.local.json"
---

# hook 配置アーキ規約（HOOKS-ARCHITECTURE）

Claude Code の hook script は規約 (rule) または skill と **同じフォルダ** に置く。flat な `hooks/` バケットに全 hook を投げ込む構造は禁止する。

定義ドキュメントは `~/agent-home/ai-management-portal/design/hooks.html`。本ファイルは規約の核と機械強制の挙動を SessionStart 時の自動ロード対象として示す。

## 配置 4 象限

| ownership × scope | 置き場 |
|---|---|
| skill × global | `~/agent-home/skills/<skill>/scripts/<hook>.sh` |
| skill × project | `<repo>/.claude/skills/<skill>/scripts/<hook>.sh` |
| 独立規約 × global | `~/.claude/rules/<scope>/<topic>/<rule>/<hook>.sh`（scope は always / scoped） |
| 独立規約 × project | `<repo>/.claude/rules/<rule>-rules/<hook>.sh` |

判定基準:

- **ownership**: 特定 skill の前提を強制するなら skill 延長。単一 skill に紐付かない system メタ規約なら独立規約
- **scope**: 全プロジェクトで効かせるなら global。単一プロジェクトのみなら project

## 命名規約

hook script と関連識別子（注入タグ・マーカー・環境変数・シェル関数）の命名は `~/.claude/rules/always/naming/common-principles/naming-values.txt`「識別子形式表」節を定義とする。

要約:
- hook ファイル名: 動詞前置 kebab-case（`check-<slug>.sh`）
- 注入タグ: `[<SLUG>-BLOCK]` / `[<SLUG>]`（slug は hook ファイル名と派生一致）
- マーカー: `<slug>.<kind>`（kind = count / needed / test-passed 等）
- 環境変数: `CLAUDE_HOOK_<SLUG_UPPER>_RUNNING`
- シェル関数: snake_case 動詞句

## 禁止配置

新規 hook script を以下のパスに作成することを禁止する。既存ファイルの編集は legacy として許可する。

- `~/agent-home/tools/hooks/`（移行完了済み。残存は共有ライブラリ `lib/marker-path.sh` 1 本のみ）
- `~/.claude/hooks/`
- `~/.claude/**/hooks/`（plugin 含む）
- `<repo>/.claude/hooks/`（既存プロジェクト等の 19 ファイルは legacy）
- `<repo>/.claude/**/hooks/`

## 誤ブロックしないパス

次のパスは判定対象外。`.claude/` も `agent-home/` も path に含まないため自動的に除外される。

- `<repo>/frontend/src/hooks/`（React カスタムフック）
- `<repo>/src/hooks/` 系
- `.husky/`
- `.git/hooks/`
- `node_modules/**/hooks/`

## 機械強制

| timing | スクリプト | 注入タグ | 挙動 |
|---|---|---|---|
| 事前 | `~/.claude/rules/scoped/agent-config/hooks/check-hooks-architecture.sh` | `[HOOKS-BUCKET-FORBIDDEN]` | PreToolUse(Write\|Edit\|MultiEdit\|NotebookEdit) で `(.claude\|agent-home)` 配下の `hooks/` セグメントに新規ファイル作成を検出すると `exit 2` で block。既存ファイルの編集は通す |

## 違反検知時の手順

`[HOOKS-BUCKET-FORBIDDEN]` が注入された場合の Claude の手順:

1. ブロックされた Write/Edit の対象パスから、hook の ownership（skill 延長 / 独立規約）と scope（global / project）を判定
2. 4 象限の対応する canonical 配置に書き換え:
   - skill × global → `~/agent-home/skills/<skill>/scripts/<hook>.sh`
   - skill × project → `<repo>/.claude/skills/<skill>/scripts/<hook>.sh`
   - 独立規約 × global → `~/.claude/rules/<scope>/<topic>/<rule>/<hook>.sh`（scope は always / scoped）
   - 独立規約 × project → `<repo>/.claude/rules/<rule>-rules/<hook>.sh`
3. 配置先フォルダが無ければ `mkdir -p` で作成
4. 配置先の rule.md 内に `## 設計判断` セクションを記載（4 項目: 必要性 / 代替案不採用理由 / 保守責任者 / 廃棄条件）
5. `~/agent-home/ai-management-portal/hooks.html` の `HOOKS` 配列に登録
6. `settings.json` に hook command を登録（path は canonical 配置に揃える）

## 命名規則

hook script のファイル名は、振る舞いに応じて語彙を固定する（2026-07-07 導入。実測で「検証してblockしうるhook」の前置check-が8件・後置-checkが10件・-gate/-guard後置が8件と分裂していたため統一した）。

| 振る舞い | 語彙 | 配置 |
|---|---|---|
| 検証してblockしうる（exit 2の可能性あり） | `check-` | 前置。例: `check-main-agent-direct-work.sh` |
| 検証だが絶対にblockしない（advisory のみ） | `suggest-` | 前置。例: `suggest-subagent.sh` |
| 何らかの処理を実行する（検査ではない） | 個別の動詞（`cleanup-` `record-` `update-` `scrub-` `nuke-` 等） | 前置。無理に1語へ統一しない |
| 他のhookへ振り分ける | 既存の `dispatch-pre-bash-checks.sh` `rules-bash-runner.sh` はこのまま維持 | — |
| 共有ライブラリ（hook本体ではなく他スクリプトからsourceされるだけ） | ファイル名接頭辞を使わず `shared/` サブディレクトリに配置 | 例: `guard/shared/no-deferral-detect.sh` |

**新規 hook 作成時は必ずこの表に従う。** 既存 hook を新設 hook の命名の手本にしない場合がある（統一前の名残が残っている可能性があるため、本表を正とする）。

## マーカーファイル禁止

hook スクリプトが状態追跡目的でファイルを作成する設計を全面禁止する。

### 禁止対象

hook がセッション内の状態（block 回数・完了フラグ・累積カウンタ）を追跡するためにファイルを touch / write する設計全般。Claude ツール呼び出し経由（Bash touch / Write）・hook プロセス内部の書き込みを問わない。

### 禁止の根拠

1. **autoモード拒否**: Claude のツール呼び出し経由のマーカー作成が autoモードの permission 判定に拒否される
2. **バグ多発**: marker-path.sh 自体のコミットの50%が修正だった
3. **不要性の実測**: advisory だけで十分という実測（commit gate は124回の advisory 発火に対し block 実績ゼロ）

### 適用除外

| 区分 | 例 | 理由 |
|---|---|---|
| 外部消費者向けファイル | `flow-status.json`（statusline.py が読む） | Claude のコンテキスト外のプロセスが消費するため transcript に移せない |
| 追記専用ログ | skill-log JSONL | 監査・導出元として機能。状態追跡ではなく記録 |

### transcript 走査とは

Claude Code は各セッションの全やりとり（ツール呼び出し・結果・hook の additionalContext 出力を含む）を transcript ファイルに記録している。hook は stdin JSON の `.transcript_path` フィールドでこのファイルのパスを受け取れる（PreToolUse / PostToolUse / Stop の全タイミングで利用可能。実機確認済み）。

マーカーファイルの代わりに、この transcript を `grep -c` で走査して「過去に自分のタグが何回出現したか」を数えることで、ファイルを一切作らずに状態を追跡できる。

```bash
# hook 内での使用例: 自分の block タグが3回以上出現していたら自動解除
tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
[ -n "$tp" ] && count=$(grep -c '\[MY-HOOK-BLOCK\]' "$tp" 2>/dev/null || echo 0)
[ "${count:-0}" -ge 3 ] && exit 0
```

transcript はセッション単位で生成されるため、セッションをまたぐ状態は保持しない（マーカーファイルも同じ性質だったため、等価な代替となる）。

### 代替手段

| 現行パターン | 代替 | 共有ヘルパー |
|---|---|---|
| livelock カウンタ（`*.count`） | transcript 内の block タグ出現回数が閾値以上なら自動解除 | `should_auto_release "$tp" "TAG" N && exit 0` |
| レビューゲート（`*.pass`） | skill-log JSONL 内のスキル発火記録を参照 | `check_skill_fired "$session" "skill-name"` |
| 累積カウンタ | transcript 内の特定パターン出現回数 | `count_tag_in_transcript` |
| 単発完了フラグ | advisory のみ（hard block 不要の実測済み） | — |

共有ヘルパー: `~/.claude/rules/scoped/agent-config/hooks/shared/transcript-query.sh`

### 機械強制

| timing | スクリプト | 注入タグ | 挙動 |
|---|---|---|---|
| PostToolUse(Write\|Edit\|MultiEdit) | `check-marker-antipattern.sh` | `[MARKER-ANTIPATTERN]` | `rules/` または `skills/*/scripts/` 配下の新規 `.sh` ファイルにマーカー作成パターンを検出したら advisory 注入（exit 0）。既存ファイルの編集は対象外 |

### 違反検知時の手順

#### `[MARKER-ANTIPATTERN]` 受信

1. 注入メッセージで検出されたパターンを確認する
2. 代替手段表を参照し、マーカーファイルを使わない設計に書き換える
3. livelock カウンタ → `count_tag_in_transcript`、ゲート → `check_skill_fired`、フラグ → advisory のみ

設計判断・経緯の記録は同ディレクトリの `design-notes.txt` を参照（非注入サイドカー）。

## 移行方針

本規約導入時点の legacy と移行状況:

- `~/agent-home/tools/hooks/*.sh` — 移行完了。`lib/marker-path.sh` のみ残存。これは legacy ではなく**共有ライブラリ（現役・削除禁止）**: `~/.claude/rules/` 配下の 6 hook（skill-log-recorder / check-claude-md-guard / check-evidence-checklist / check-main-agent-direct-work / no-deferral-stop / enforce-flow-gate）が source している
- `~/Projects/<project>/.claude/hooks/*.sh` — 移行完了
- `~/.claude/plugins/marketplaces/*/plugins/*/hooks/` plugin 内 — plugin maintainer の管轄。触らない

新規 hook は禁止配置へ作成しない。既存残存ファイル（marker-path.sh 等）の編集は legacy として許可する。

## プロジェクト上書き

- 上書き可否: 一律適用
- 理由: hook 配置 4 象限はアーキテクチャの定義であり、一律適用するため受け口を設けない

設計判断・経緯の記録は同ディレクトリの `design-notes.txt` を参照（非注入サイドカー）。

## 関連

- 設計思想の定義: `~/agent-home/ai-management-portal/design/hooks.html`
- hook 一覧: `~/agent-home/ai-management-portal/hooks.html`
- 配置時の skill: `~/agent-home/skills/creating-hooks/SKILL.md`
- レビュー時の skill: `~/agent-home/skills/reviewing-hooks-config/SKILL.md`
- テスト時の skill: `~/agent-home/skills/testing-hooks/SKILL.md`
