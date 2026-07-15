# 6 ドメイン診断委任定義（domain-briefs）

Phase 1（並列診断）・Phase 6（再診断）で `investigator` に委任する prompt の骨格。共通禁止ブロックを全ドメイン共通で prompt 先頭に前置し、続けて該当ドメイン節を連結する。

## 共通禁止ブロック（全ドメイン prompt に前置）

```
あなたは Claude Code プロジェクトの設定診断を行う読み取り専用の調査担当である。以下を厳守する。

1. 読み取り専用契約: 使用してよいコマンドは ls / find / grep / cat / head / wc / stat / git log / git ls-files のみ。
   ファイル・設定・git 状態を変更するコマンド（Write/Edit 相当の操作、mv/rm/mkdir/git add/git commit 等）は一切実行しない。
2. シークレット値の引用禁止: .env の中身・API キー・トークン・秘密鍵等の値そのものは報告に転記しない。
   該当ファイルのパスと存在有無のみを報告する。
3. 除外パス: 次のパス配下は調査対象から除外する: {EXCLUDED_PATHS}
4. 提案は記述するだけで実行しない: 修正案・fix プロンプトは findings JSON の recommendation / fix.prompt に
   文字列として記述するのみとし、実際にファイルを変更したり修正コマンドを実行したりしない。
5. 出力は指定された findings JSON スキーマのみ。調査の実況・思考過程は出力しない。
```

`{EXCLUDED_PATHS}` は呼び出し元（本スキルの Phase 1/6）が対象プロジェクトの `.claude/diagnosis/quarantine/`・`node_modules`・`.git`・`dist`・`build` 等で置換してから investigator へ渡す。

## ドメイン別診断定義

### claude-md

- **検査対象パス**: 対象プロジェクトルート直下の `CLAUDE.md`
- **基準の正本参照**: `managing-agent-configs` の reviewing.md 正本が存在しないため、`references/claude-md-checks.md`（本スキル固有）を正本とする
- **代表チェック観点**（意味語キー。連番禁止）:
  - 配置決定木-準拠: 記述内容が CLAUDE.md/Rules/Skills/Subagents/Hooks の 7 層決定木に沿った層に置かれているか
  - 本体行数-200行上限: CLAUDE.md 本体が 200 行を超えていないか
  - dead-code-重複記載: hooks/skills が既に機械強制している行動規約を重複記載していないか
  - 参照パス-実在確認: rules/skills への参照パスが実在するファイルを指しているか
  - 陳腐化記述-廃止参照: 廃止済みの hook 名・skill 名への言及が残っていないか

### rules

- **検査対象パス**: 対象プロジェクトの `.claude/rules/`（グローバル `~/.claude/rules/` は対象外。本スキルはプロジェクト診断のため対象プロジェクト配下のみを見る）
- **基準の正本参照**: `~/agent-home/skills/managing-agent-configs/references/rules/reviewing.md`
- **代表チェック観点**:
  - フォルダ構造-深さ3準拠: `<scope>/<topic>/<name>/rule.md` の深さ 3 構造を満たすか
  - hook連携-スクリプト実在: rule.md が参照する hook script が実在し実行ビットを持つか
  - 違反手順-全タグ網羅: hook が出力する全注入タグに対応する「違反検知時の手順」節があるか
  - scope適合性-固有概念依存: rule がプロジェクト固有の内部概念にグローバル定義として依存していないか
  - ADR併記-設計判断サイドカー: `design-notes.txt` に必要性・代替案・保守責任者・廃棄条件が揃っているか
  - タグ命名-派生一致: 注入タグが hook ファイル名の slug と派生一致しているか
  - 本体行数-200行目安: rule.md が 200 行を超えていないか
  - 標準構成-必須構成: `.claude/rules/`（実体ディレクトリ）+ `always/project-context/rule.md`（`## ルート直下許可ディレクトリ` 節必須）+ flow-values.yml（実装フロー対象のみ）が揃っているか（正本: `~/.claude/rules/scoped/agent-config/project-structure/rule.md`）
  - 標準構成-旧配置残骸: 旧 `.claude/skills/flow-config/`・旧形式 `<name>-rules/` ディレクトリ・専用 `always/placement/directory-structure/rule.md` が残っていないか
  - 標準構成-review-checklistドメイン限定: `scoped/review-checklist/` 配下が code / document / report の 3 ドメインのみか
  - 常時注入予算-project-context80行: `project-context/rule.md` の概要・技術スタック・索引部分が 80 行以内か（許可リスト節は予算対象外）

### skills

- **検査対象パス**: 対象プロジェクトの `.claude/skills/`（プロジェクトローカルスキルが存在する場合のみ。存在しなければ `present: false` で D）
- **基準の正本参照**: `~/agent-home/skills/managing-agent-configs/references/skills/reviewing.md`
- **代表チェック観点**:
  - frontmatter-3項目必須: `name` / `description`（TRIGGER when・SKIP） / `type` の 3 項目が揃っているか
  - Type判定-決定木整合: frontmatter の `type` が実際の挙動と一致しているか
  - 説明文-50字予算: description の説明文（TRIGGER 行より前）が 50 字以内か
  - 本体行数-500/200行予算: SKILL.md が 500 行以内、詳細は 200 行超で references 分離済みか
  - 単一責務-責務混在: 1 スキルに複数責務が詰め込まれていないか
  - 副作用安全性-危険操作オート発火: push/merge/deploy/`rm -rf` がオート発火可能になっていないか
  - フロー系Phase-完了条件明記: Phase/Step 構造を持つ場合、各 Step に完了判定文があるか

### hooks

- **検査対象パス**: 対象プロジェクトの `.claude/settings.json` / `.claude/settings.local.json`
- **基準の正本参照**: `~/agent-home/skills/managing-agent-configs/references/hooks/reviewing.md`
- **代表チェック観点**:
  - JSONスキーマ-type固定: `.type` が `"command"` で統一されているか
  - matcher-正規表現禁止: matcher に正規表現メタ文字を使わずリテラルかパイプ区切りか
  - タグ命名-派生一致: 注入タグが hook ファイル名の slug と UPPER 化で一致しているか
  - timeout-明示必須: `timeout` フィールドが 5〜15 秒で明示されているか
  - exit-code規約準拠: PostToolUse/UserPromptSubmit の末尾に `|| true` があるか
  - 再帰防止-ENVガード: 子プロセス起動時に `CLAUDE_HOOK_*_RUNNING` 等のガードがあるか
  - セキュリティ-ワンショットフラグ排除: `/tmp/.allow-*` 等のワンショットフラグでなく `permissions.deny` を使っているか

### subagents

- **検査対象パス**: 対象プロジェクトの `.claude/agents/`
- **基準の正本参照**: `~/agent-home/skills/managing-agent-configs/references/subagents/reviewing.md`
- **代表チェック観点**:
  - frontmatter-name一致: `name` が kebab-case かつディレクトリ名・ファイル名と一致しているか
  - description-TRIGGER/SKIP必須: description に TRIGGER when と SKIP が存在するか
  - model-明示ID必須: `model` がエイリアスでなく明示モデル ID か
  - tools-禁止ツール混入: `tools` に役割上禁止されるツール（計画者への Write 等）が含まれていないか
  - 単一責任-責務集中: 責務が 1 つに集中し、他 subagent との境界が明確か
  - 本体行数-100行以内: 本文が 100 行以内か
  - references健全性-可変データ排除: references に可変データ（設定値等）が置かれていないか

### hygiene（自動化・運用衛生）

- **検査対象パス**: 対象プロジェクトの `routines/`（存在する場合）+ プロジェクト全体の命名・配置慣行（ファイル名・ディレクトリ配置）
- **基準の正本参照**: `~/agent-home/skills/managing-agent-configs/references/routines/reviewing.md`（ルーティンが存在する場合の主正本） + `~/.claude/rules/always/naming/common-principles/rule.md`（命名） + `~/.claude/rules/always/placement/file-guard/rule.md`（配置）
- **代表チェック観点**:
  - Phase完了条件-網羅性: ルーティンの全 Phase に完了条件が定義されているか
  - ログ追跡性-JSONL出力: 実行結果が JSONL 形式で共通エンベロープに準拠して出力されるか
  - 冪等性-重複防止: issue/PR 作成前に同一対象の重複検索を行っているか
  - 品質ゲート-lint型チェック: コード変更を伴うルーティンで lint/型チェックがマージ前に実行されるか
  - マーカー衛生-配置規約準拠: hook のマーカー書き出し先が `marker_path` 規約（worktree 内 or `/tmp` フォールバック）に従っているか
  - 命名派生-タグ/マーカー一致: 注入タグ・マーカー名がスクリプト slug と派生一致しているか
  - スコープ制御-処理上限明示: 1 回あたりの処理上限（ファイル数・PR 数等）が設定されているか
  - ルーティン不在時の扱い: `routines/` が存在しないプロジェクトは、hooks・命名・配置の観点のみで判定し、ログ追跡性・品質ゲート等ルーティン固有観点は充足率の分母から除外する
