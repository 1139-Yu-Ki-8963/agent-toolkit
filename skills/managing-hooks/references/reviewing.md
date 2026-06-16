# Hook レビュー手順（reviewing）

`managing-hooks` の **review モード** が参照する手順書。`conventions.md` を前段で読んだ前提で、settings.json hooks の観点ベース静的レビューと自動修正を実行する。

このファイルを読み終えたら、Phase 1〜5 を実行し、完了後 **自動的に test モード** へ連鎖する（ハブ SKILL.md の指示に従う）。

review モードは 2 つの動作モードを持つ:

- **full モード**（既定）: 全観点 A〜M を評価、CRITICAL / WARN を `AskUserQuestion` 承認の上 `Edit` で自動修正、Phase 6 で test 連鎖
- **dry-run モード**: 読み取り専用診断モード。観点 I〜M（設計面の 5 観点）のみ実行、レポートのみで `Edit` は発行しない、連鎖もしない

dry-run は「修正は別途検討したい」「読み取りのみで安全に診断したい」場合に使う。

## 概要

Claude Code の `settings.json` に登録された hooks を **公式仕様準拠**・**配置アーキ規約準拠**・**設計健全性** の観点で静的レビューし、検出した問題をユーザー承認のうえ自動修正し、最後に test モードへ連鎖して全 hook の実機発火を検証する。`managing-skills` の review モードの hooks 版。

## 実行 Phase

### Phase 1: 対象 settings.json の発見

グローバルとプロジェクトの settings.json を全列挙する。

```bash
# グローバル
ls ~/.claude/settings.json ~/.claude/settings.local.json 2>/dev/null

# プロジェクト（自分のプロジェクトルートを列挙）
find ~/Projects ~/ghq -maxdepth 5 -type f \
  \( -name 'settings.json' -o -name 'settings.local.json' \) \
  -path '*/.claude/*' \
  -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null
```

除外パス: `node_modules` / `.git` / `dist` / `build` / `coverage`

### Phase 2: 静的解析

#### full モード: 全観点 A〜M

各ファイルを `jq` でパースし、`hooks` セクションを観点表（後述）で検査する。詳細な jq 式・grep パターンは `check-items.md` を参照。

```bash
jq -r '.hooks | to_entries[] | .key as $event |
  .value[] | (.matcher // "*") as $matcher |
  .hooks[] | "\($event)\t\($matcher)\t\(.type)\t\(.timeout // 0)\t\(.command | length)\t\(.command)"' \
  <settings.json>
```

#### dry-run モード: 観点 I〜M のみ

設計面の 5 観点に絞って評価する。CLAUDE.md §7〜§15 と `~/.claude/skills/<name>/scripts/`・`~/.claude/rules/<name>-rules/` 配下の hook script も読み込む。

### Phase 3: 参照スクリプト実体検証

command 内から外部 script path を抽出し、

- 存在: `[ -f "$path" ]`
- shebang: 先頭行が `#!/usr/bin/env bash` か `#!/bin/bash` か
- 実行ビット: `[ -x "$path" ]`

### Phase 4: レポート出力

ファイル別 → カテゴリ別 → 項目別の階層で集計する。

#### full モードのレポート例

```
## managing-hooks review レポート（full）

### ファイル: ~/.claude/settings.json
- 検出 hook 数: 14
- CRITICAL: 2 / WARN: 5 / INFO: 3

#### A. command 書式
- [CRITICAL] A1 PostToolUse/Write (line 142) — command 1820 文字
  引用: `"command": "input=$(cat); file=..."`
  修正案: `<skill>/scripts/textlint-postwrite.sh` へ切り出し
  修正後: `"command": "<skill>/scripts/textlint-postwrite.sh"`

#### H. 配置アーキ準拠
- [CRITICAL] H1 PostToolUse (line 87) — command path が `<legacy-flat-hooks-bucket>/` flat バケット
  修正案: 配置 4 象限を判定して `<skill>/scripts/` か `<rule>-rules/` に `git mv`
```

#### dry-run モードのレポート例

```
## managing-hooks review レポート（dry-run = diagnose）

### Section 1: カテゴリ別フック一覧
[A ガード系] 危険な操作を強制停止する
- PreToolUse/Bash git add → issue-scope-check.sh ブロック

[B 規約系] 命名・テンプレートの一貫性を維持する
...

### Section 2: 観点別診断結果
#### I. 複雑度
[MEDIUM] I1 git commit フックに 4 機能集約（NAMING + PUBLISH 系 3 種）
[MEDIUM] I2 SessionEnd に 3 責務集約

#### J. 無限ループリスク
[HIGH] J3 ENV ガード未設定: <フック名>
...
```

### Phase 5: 自動修正（full モードのみ）

検出された CRITICAL / WARN について `AskUserQuestion` で承認範囲を確認する。

| 選択肢 | 動作 |
|--------|------|
| 全件採用 | 検出された全 CRITICAL / WARN を自動修正 |
| 個別選択 | 項目 ID をリストで提示し、修正する項目だけ選ばせる |
| CRITICAL のみ | CRITICAL のみ修正、WARN は次回判断 |
| スキップ | 修正せず Phase 6 へ進む |

承認分を `Edit` ツールで settings.json または外部スクリプトに適用する。インラインシェル → 外部スクリプト切り出しの場合、新規 `.sh` ファイルの作成は ADR 必須（`security.md` のスクリプトファイル作成方針）。

**dry-run モードは Phase 5 をスキップ**。レポート出力で終了する。

### Phase 6（full モードのみ・自動連鎖）: test モードへ遷移

Phase 5 完了後、ハブ SKILL.md の指示に従い **test モードへ自動遷移** する。ユーザーが明示的に「レビューまでで止めて」と言った場合のみ連鎖を停止する。

連鎖時は `Agent` ツールで白紙状態の新規サブエージェントを起動し、`testing.md` の手順に従わせる:

```
Agent(
  description: "全 hook の実機検証",
  subagent_type: "general-purpose",
  prompt: "~/.claude/skills/managing-hooks/references/testing.md の手順に従い、
           Phase 5 で修正された settings.json 全ファイルの全 hook を
           サンプル stdin で実機実行し、以下を全件チェック:
           ① JSON 構文エラー無し
           ② スキーマ準拠（systemMessage / hookSpecificOutput）
           ③ timeout 内完了
           ④ 副作用無し
           失敗した hook ID と原因を箇条書きで報告。"
)
```

### Phase 7: 最終報告

以下を能動文・日本語で報告する。

- モード（full / dry-run）
- 対象ファイル数と検出 hook 総数
- 修正前 CRITICAL / WARN / INFO（または HIGH / MEDIUM / LOW）件数 → 修正後の差分
- test モード検証結果（full モードのみ、PASS / FAIL 件数、失敗 hook ID）
- 未対応項目（修正不能な指摘とその理由）
- 健全性判定（後述）

## 観点チェック表

詳細な jq 式・grep パターン・修正前後サンプルは `check-items.md` を参照。

### 公式仕様準拠系（A〜G）— full モード

#### A. command 書式（5 項目）

| ID | 重大度 | 検出 | 修正方針 |
|----|--------|------|----------|
| A1 | CRITICAL | command 500 文字超 | 外部 `.sh` に切り出し 1 行呼び出し |
| A2 | WARN | command 200 文字超 | 同上、または `jq -n` で整理 |
| A3 | WARN | command に改行混入 | `.sh` ファイルへ移動 |
| A4 | WARN | `echo "$(cat)"` パターン | `printf '%s' "$input" \| jq -r` に置換 |
| A5 | INFO | `printf '{...}'` で動的部分をハードコード | `jq -n --arg k "$v" '{...}'` |

#### B. 配置場所（3 項目・公式仕様準拠のみ）

| ID | 重大度 | 検出 | 修正方針 |
|----|--------|------|----------|
| B1 | CRITICAL | command 中の相対パス `./` `../` | 絶対パスか `${CLAUDE_PROJECT_DIR}` |
| B2 | INFO | 参照スクリプトが実在しない | path 修正または再配置 |
| B3 | INFO | スクリプトに実行ビットなし | `chmod +x` |

#### C. type / matcher（4 項目）

| ID | 重大度 | 検出 | 修正方針 |
|----|--------|------|----------|
| C1 | CRITICAL | `.type` が `"command"` 以外 | `"type":"command"` 固定 |
| C2 | CRITICAL | matcher に正規表現メタ文字 `[ ( ) . * + ]` | リテラルまたは `Write\|Edit` パイプ区切り |
| C3 | CRITICAL | `if` フィールドがコロン区切り | スペース区切り `Bash(git commit *)` |
| C4 | WARN | PreToolUse/PostToolUse で matcher 未指定 | 対象ツール名で絞る |

#### D. event 種別（3 項目）

| ID | 重大度 | 検出 | 修正方針 |
|----|--------|------|----------|
| D1 | CRITICAL | EventName が標準 8 種（PreToolUse / PostToolUse / UserPromptSubmit / SessionStart / Stop / SessionEnd / PermissionRequest / PostToolUseFailure）外 | typo 修正 |
| D2 | CRITICAL | `decision:"block"` を PreToolUse 以外で使用 | PreToolUse へ移動または `exit 2` 化 |
| D3 | WARN | `hookSpecificOutput.hookEventName` が親と不一致 | 親 EventName と揃える |

#### E. exit code（3 項目）

| ID | 重大度 | 検出 | 修正方針 |
|----|--------|------|----------|
| E1 | CRITICAL | PostToolUse/UserPromptSubmit で末尾 `\|\| true` なし | 末尾に `\|\| true` 追加 |
| E2 | WARN | `exit 2` 使用箇所が 3 件以上 | 本当に止める必要か再評価 |
| E3 | INFO | `exit 1` 使用箇所 | ログ目的か明示 |

#### F. timeout / 性能（5 項目）

| ID | 重大度 | 検出 | 修正方針 |
|----|--------|------|----------|
| F1 | CRITICAL | `timeout` フィールド不在 | 5〜15 秒で明示 |
| F2 | WARN | `timeout > 30` 秒 | 必要性を再確認 |
| F3 | WARN | 同一 matcher 配下に複数 hook（stdin 競合） | 1 hook に統合 |
| F4 | WARN | Node 実行前に `exec 0</dev/null` なし | 挿入 |
| F5 | WARN | `claude -p` 起動時に再帰防止 env なし | `CLAUDE_HOOK_*_RUNNING` ガード追加 |

#### G. セキュリティ（4 項目）

| ID | 重大度 | 検出 | 修正方針 |
|----|--------|------|----------|
| G1 | CRITICAL | `/tmp/.allow-*` 等のワンショットフラグ | `permissions.deny` に置換 |
| G2 | CRITICAL | `nohup ... & disown` で監視不可起動 | foreground 化または routines へ |
| G3 | WARN | 機密 glob を hook で守っている | `permissions.deny` へ移行 |
| G4 | WARN | TAG 名が既存と重複 | `conventions.md` の重複禁止リスト参照 |

### 配置アーキ準拠（H）— full モード

#### H. 配置アーキ準拠（4 項目）

| ID | 重大度 | 検出 | 修正方針 |
|----|--------|------|----------|
| H1 | CRITICAL | command path が flat `hooks/` バケット | `conventions.md` §4 の 4 象限に従い `<skill>/scripts/` または `<rule>-rules/` へ移動 |
| H2 | WARN | 配置先フォルダに `rule.md` / `SKILL.md` が同居していない | 規約定義ファイルを新規作成 |
| H3 | WARN | ADR が `~/.claude/adr/` または `<repo>/docs/adr/` に存在しない | ADR テンプレで新規作成 |
| H4 | INFO | `hooks.html` の `HOOKS` 配列に未登録 | file / group / matcher / role を追記 |

**自動修正（H1）の例外**: ファイル移動はユーザー承認必須。`AskUserQuestion` で「移動する / legacy として残す」を必ず問う。

### 設計健全性系（I〜M）— full / dry-run 共通

設計面 5 観点。dry-run モードではこのカテゴリ I〜M のみを評価する。

#### I. 複雑度（3 項目）

| ID | 重大度 | 検出 | 修正方針 |
|----|--------|------|----------|
| I1 | MEDIUM | 単一フックの case 分岐数が 3 以上 | 機能ごとにフック分割を検討 |
| I2 | MEDIUM | SessionEnd が独立 3 責務以上を持つ | 責務単位に分離 |
| I3 | LOW | 外部スクリプトに固定値リスト（ファイルパス・リポジトリ名）がハードコード | 設定ファイル化または引数化 |

#### J. 無限ループリスク（3 項目）

| ID | 重大度 | 検出 | 修正方針 |
|----|--------|------|----------|
| J1 | MEDIUM | TEXTLINT 連鎖の再帰防止判定が Claude の会話記憶のみに依存 | コンテキスト圧縮後も判定が残る機械的ガードに変更 |
| J2 | LOW | AUTO-COMMIT 30 秒ガードが前提条件付きで機能 | 前提条件を明示文書化 |
| J3 | HIGH | SessionEnd 子プロセスに `CLAUDE_HOOK_*_RUNNING` ENV ガード未設定 | 起動時に ENV ガード追加 |

#### K. 解釈の曖昧さ（3 項目）

| ID | 重大度 | 検出 | 修正方針 |
|----|--------|------|----------|
| K1 | HIGH | 再帰判定が自然言語記述（「直前のターン」「N 回連続」）のみに依存 | 機械的判定（マーカーファイル・session ID 比較）に置換 |
| K2 | MEDIUM | 同一 matcher に複数 hooks エントリ（stdin 競合） | 1 hook に統合 |
| K3 | LOW | additionalContext に「〜してください」形式の質問形指示 | 命令形に書き換え |

#### L. コンテキスト直書き（3 項目）

| ID | 重大度 | 検出 | 修正方針 |
|----|--------|------|----------|
| L1 | MEDIUM | additionalContext の文字数が 100 字超 | SKILL.md 参照に置換 |
| L2 | MEDIUM | SKILL.md に定義済みの手順を additionalContext に重複直書き | SKILL.md 参照に置換 |
| L3 | INFO | `[NAMING]` 等の TAG の additionalContext 文字数測定 | 100 字超なら L1 と同じ修正方針 |

#### M. カテゴリ整合性（3 項目）

| ID | 重大度 | 検出 | 修正方針 |
|----|--------|------|----------|
| M1 | MEDIUM | A 分類だが `exit 2` / `decision:block` が無く実際に停止しない | 停止手段を追加、または分類を変更 |
| M2 | LOW | 複数カテゴリをまたぐフック | 分割可能なら分離 |
| M3 | MEDIUM | 同一 TAG が PreToolUse と PostToolUse の両方から発火しうる | 経路を 1 つに統一 |

**合計 43 項目（A〜H: 28 項目／I〜M: 15 項目）**

カテゴリ分類は `conventions.md` の「9. フックカテゴリ定義（A〜H）」を参照。

## 健全性目安

### full モード

- CRITICAL: 0 件
- WARN: 3 件以下
- INFO: 制限なし
- test モード連鎖検証: 全 PASS

### dry-run モード

- HIGH: 0 件
- MEDIUM: 5 件以下
- LOW: 制限なし

上記すべてを満たした場合のみ「健全」と報告する。

## Gotchas

- 自動修正の前に必ずユーザー確認: `approved=true` を得るまで Edit を発行しない（full モード Phase 5 の承認フロー）
- dry-run モードは Edit を発行しない・連鎖もしない: 「修正まで進めて」と言われたら full モードに切り替える
- test モード連鎖を省略すると「静的レビューのみ」で終わる: full モードでは Phase 6 を省略しない
- `if` のコロン区切りは fail-open の原因: C3 は CRITICAL 最優先

## 参照資料

- 共通規約: `conventions.md`
- 観点別の jq / grep 検出式と修正前後例: `check-items.md`
- 連鎖先の手順書: `testing.md`
