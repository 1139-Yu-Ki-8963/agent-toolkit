# flow-values.yml 配置ガード（FLOW-CONTEXT-GUARD）

`~/Projects/` 配下の git リポジトリで `.claude/rules/always/project-context/flow-values.yml`（orchestrating-dev-flow が Phase 1 以降の前提として読む設定ファイル）が未配置の場合を検知し、デフォルト内容での自動生成を案内する規約。

## 背景

`orchestrating-dev-flow` スキルの Phase ゲート（`~/.claude/rules/scoped/dev-flow/gate/rule.md`）は、`~/Projects/` 配下のコードファイル編集時に `flow-values.yml` の不在を検出すると Write/Edit を block する。ただしこの block は「コードファイルへの書き込み」が発生した瞬間にしか発火せず、`.claude/` 配下のみを編集するリポジトリ（`.claude/skills` や `shared/` のみを管理するリポジトリ等）では該当編集がコードゲートの対象外になる場合があり、`flow-values.yml` の不在に途中まで気付けないことがある。本規約は `git commit` の時点で一律に不在を検知し、より早い段階で気付けるようにする補完的な advisory である。

（旧配置（廃止済み）: `.claude/skills/flow-config/flow-context.yml`。互換レイヤは設けていない）

## 機械強制

| timing | スクリプト | 注入タグ | 挙動 |
|---|---|---|---|
| PreToolUse(Bash) | `check-flow-context-guard.sh`（`rules-bash-runner.sh` 経由） | `[FLOW-CONTEXT-GUARD]` | `git commit` コマンドかつ cwd が `~/Projects/` 配下の git リポジトリの場合、`.claude/rules/always/project-context/flow-values.yml` の不在を advisory 注入（exit 0）。block しない |
| PostToolUse(Bash) | `generate-flow-context.sh` | `[FLOW-CONTEXT-GENERATED]` | `git clone`/`git init`/`git worktree add`の完了後、対象パスが`~/Projects/`配下かつ`flow-values.yml`不在なら、`.claude/rules/`（実体ディレクトリ。未配置なら作成）配下にデフォルト内容を自動生成しadvisory通知。既存・対象外は何もしない |

判定フロー:

1. コマンドに `git` と `commit` が両方含まれない場合は対象外（exit 0）
2. cwd が `~/Projects/` 配下でない場合は対象外（exit 0）
3. cwd から `git rev-parse --show-toplevel` でリポジトリルートを解決できない場合は対象外（exit 0）
4. リポジトリルート配下に `.claude/rules/always/project-context/flow-values.yml` が存在すれば通過（exit 0）
5. 存在しなければ `[FLOW-CONTEXT-GUARD]` を advisory 注入

## 違反検知時の手順

### `[FLOW-CONTEXT-GUARD]` 受信

1. 当該リポジトリがアプリケーションコードを持つ通常のプロジェクトかどうかを確認する
2. 通常のプロジェクトの場合: `Skill(creating-new-project)` を実行し、`flow-values.yml` を含む標準構成を生成させる
3. アプリケーションコードを持たないリポジトリ（`.claude/skills` 等のみを管理するリポジトリ）の場合: 下記のデフォルト内容テンプレートで手動作成してよい
4. `git commit` は block されないため、上記対応は当該 commit の後でもよい。ただし次に `orchestrating-dev-flow` の Phase ゲートに触れる前には対応する

## デフォルト内容テンプレート

`.claude/rules` が未配置の場合は実体ディレクトリとして作成する。既存であればそのまま使う。

`.claude/rules/always/project-context/flow-values.yml` が存在しない場合、以下の内容で作成する（値は個別プロジェクトの実態に応じて後から埋める）。

```yaml
# プロジェクト実装フロー設定（スキーマ定義: ~/.claude/rules/scoped/agent-config/project-structure/rule.md）
domain_glossary: null
design_system: null
test_conventions: null
adr_dir: null
design_docs: null
portal_dir: null
review_gates: {}
review_agents: {}
pr: {}
classify: {}
preflight: {}
```

`.claude/rules/always/project-context/rule.md` が存在しない場合は、概要・技術スタック・設定索引に加えて `## ルート直下許可ディレクトリ` 節（ルート直下の実在ディレクトリを列挙し、用途欄は「（記入）」）を含む雛形を生成する。

## プロジェクト上書き

- 上書き可否: 一律適用
- 理由: `flow-values.yml` の配置要否は `orchestrating-dev-flow` の前提条件そのものであり、プロジェクト側で緩和する正当な事由が存在しないため受け口を設けない

## 設計判断

### check-flow-context-guard

**必要性**: `flow-values.yml` の不在は `orchestrating-dev-flow` の Phase ゲート（`check-dev-flow-phase-gate.sh`）が Write/Edit 時に block する形で既に検知しているが、この block は「コードファイルへの書き込み」が発生した時点でしか発火しない。`.claude/` 配下（`.claude/skills` 等）のみを編集するリポジトリでは Phase ゲートの対象外パス（`.claude/*` は通過扱い）に該当するため、コード書き込みが一度も発生しないまま作業が進み、後になって別のリポジトリでコードを書く段になって初めて不在に気付く、という実測済みの事故パターンがあった。`git commit` という単一のタイミングで一律に検知することで、より早い段階での気付きを提供する。既存の Phase ゲートを置き換えるものではなく、block しない advisory として補完する。

**代替案を採用しなかった理由**:
- Bash ツール直叩きで commit の都度手動確認: 確認を忘れる・確認自体を省略するインセンティブが働き、恒常的な検知にならない
- 既存 Makefile ターゲット拡張: `~/.claude/rules/` 配下に Makefile は存在せず、新規導入は本チェック専用の依存を増やすだけになる
- package.json scripts 追加: 対象がリポジトリ横断（`~/Projects/` 配下全体）であり、単一プロジェクトの `package.json` に依存させると他リポジトリで機能しない
- `check-dev-flow-phase-gate.sh` の block 条件を拡張して `.claude/*` も対象に含める: Phase ゲート側の「`.claude/` 配下は自由に編集できる」という既存の設計判断（rules/skills 自体の編集を妨げない）を壊すため不適切。検知タイミングを分離した別 hook として実装する方が影響範囲が小さい

**保守責任者**: 人手（ユーザー）。`flow-values.yml` のデフォルトスキーマを変更する場合は本ファイルのテンプレートと `~/agent-home/skills/orchestrating-dev-flow/assets/flow-values.example.yml` を同時に更新する。

**廃棄条件**: `orchestrating-dev-flow` 自体が廃止された時、または Claude Code 本体が `flow-values.yml` の自動生成を標準機能として提供するようになった時。

### generate-flow-context.sh

**必要性**: 2026-07-09 のセッションで、`flow-values.yml`（当時は旧配置の `flow-context.yml`）が未配置のリポジトリでサブエージェントが `[DEV-FLOW-PHASE-GATE-BLOCK]` を受け、その解消のために手動作成しようとしたところ自動モード判定機構に繰り返し拒否された。`git clone`/`git init`/`git worktree add` の完了後に自動生成することで、このギャップを構造的に埋める。既存の `check-flow-context-guard.sh`（`git commit` 時 advisory）はすり抜けた場合の最後の気づき手段としてそのまま残す。

**代替案を採用しなかった理由**:
- `check-flow-context-guard.sh`（既存、PreToolUse git commit 時 advisory）のみに任せる: フォルダ作成タイミングでは発火せず、`git commit` まで気付けない
- `creating-new-project` スキルの手順内での生成: スキルを経由しない `git clone`/`git init` を捕捉できない

**保守責任者**: 人手（ユーザー）。`flow-values.yml` のデフォルトスキーマを変更する場合は本ファイルのテンプレートと `generate-flow-context.sh` 内のヒアドキュメント、および `~/agent-home/skills/orchestrating-dev-flow/assets/flow-values.example.yml` を同時に更新する。

**廃棄条件**: `orchestrating-dev-flow` 自体が廃止された時、または Claude Code 本体が `flow-values.yml` の自動生成を標準機能として提供するようになった時。

## 関連

- `~/.claude/rules/scoped/dev-flow/gate/rule.md` — 実装フローゲート（`check-dev-flow-phase-gate.sh`。Write/Edit 時に flow-values.yml 不在を block）
- `~/agent-home/skills/orchestrating-dev-flow/scripts/check-flow-context-load.sh` — Phase 3 以降の flow-values.yml 読み込みマーカーチェック（`[FLOW-CONTEXT-MISSING]` advisory。本規約とは検知対象が異なる: あちらは「存在するが未読み込み」、本規約は「そもそも存在しない」）
- `~/agent-home/skills/orchestrating-dev-flow/assets/flow-values.example.yml` — flow-values.yml のサンプル
- `~/agent-home/skills/orchestrating-dev-flow/SKILL.md` — 統合開発フローの全体設計
- `~/agent-home/skills/creating-new-project/` — 新規プロジェクトセットアップ時に flow-values.yml を生成するスキル
- `~/.claude/rules/scoped/agent-config/hooks/rules-bash-runner.sh` — 本 hook の起動元（集約ランナー）
