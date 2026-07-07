# Rule レビュー手順（reviewing）

`managing-agent-configs`（種別: rules） の **review モード** が参照する手順書。`conventions.md` を前段で読んだ前提で、既存 rules の観点ベース静的レビューと自動修正を実行する。

review モードは 2 つの動作モードを持つ:

- **full モード**（既定）: 全観点 A〜G を評価、CRITICAL / WARN を `AskUserQuestion` 承認の上 `Edit` で自動修正、test 連鎖
- **dry-run モード**: 観点のみ実行、レポートのみで `Edit` は発行しない、連鎖もしない

## Phase 1: 対象 rules の全列挙

```bash
# グローバル（深さ 3 固定: <scope>/<topic>/<name>/）
find ~/.claude/rules/always ~/.claude/rules/scoped -mindepth 2 -maxdepth 2 -type d 2>/dev/null | sort

# プロジェクト（既存形式 <category>-rules/ が当面並存）
find ~/Projects/*/.claude/rules/ -type d -mindepth 1 -maxdepth 1 2>/dev/null | sort
```

各ディレクトリについて `rule.md` と `.sh` の有無を確認:

```bash
for d in ~/.claude/rules/always/*/*/ ~/.claude/rules/scoped/*/*/; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  has_rule=$( [ -f "$d/rule.md" ] && echo "Y" || echo "N" )
  sh_count=$(find "$d" -name "*.sh" -not -name "*.test.sh" | wc -l | tr -d ' ')
  echo "$name  rule.md=$has_rule  hooks=$sh_count"
done
```

### 緊急回避 / fail-closed 頻度の集計（優先レビュー対象の判定）

```bash
find ~/agent-home/sessions/.escape-log -name '*.jsonl' -mtime -30 -exec cat {} + 2>/dev/null \
  | jq -r '.hook' | sort | uniq -c | sort -rn
```

過去30日で3回以上の緊急回避・fail-closed発火があるhookは「優先レビュー対象」とし、後述のPhase 2.5（ロジックレビュー）を省略不可とする。

## Phase 2: 観点別検査

### 観点 A: フォルダ構造

| # | チェック | 重要度 | 検出方法 |
|---|---|---|---|
| A1 | ルート直下に `.md` が残存していないか | CRITICAL | `find ~/.claude/rules/ -maxdepth 1 -name "*.md"` |
| A2 | `always/` `scoped/` 配下に `-rules` suffix 付きディレクトリが残存していないか / rule.md が深さ 3 以外にないか | CRITICAL | check-items.md A2（新形式は suffix 禁止） |
| A3 | 全ディレクトリに `rule.md` が存在するか | CRITICAL | Phase 1 の `has_rule=N` |
| A4 | hook script が rule.md と同ディレクトリに同居しているか | WARN | settings.json の command path と rule.md の配置を突合 |

### 観点 B: scope 適合性

| # | チェック | 重要度 | 検出方法 |
|---|---|---|---|
| B1 | グローバル rule が特定プロジェクト固有の概念に依存していないか | CRITICAL | rule.md 内に `slot/wt` `owner cwd` `portal` `mock_awaiting` `spawn-child` `ledger` 等のプロジェクト固有キーワードを grep |
| B2 | プロジェクト rule が汎用的な規約を含んでいないか | WARN | rule.md の内容がプロジェクト非依存なら global に昇格 |

### 観点 C: hook 連携

| # | チェック | 重要度 | 検出方法 |
|---|---|---|---|
| C1 | hook script の additionalContext にプロンプト（対応手順）が埋め込まれていないか | CRITICAL | `.sh` 内の `ctx=` 変数が 300 文字を超えるか、手順的な記述を含むか |
| C2 | additionalContext が rule.md への参照を含んでいるか | WARN | `.sh` 内に `rule.md を参照` または `rule.md` パスが含まれるか |
| C3 | settings.json に登録された command path が実在するか | CRITICAL | `[ -f "$path" ]` |
| C4 | settings.json の command path と rule.md が同ディレクトリにあるか | WARN | パスのディレクトリ部分を比較 |
| C5 | hook script に shebang があるか | WARN | `head -1 <script>.sh` |
| C6 | hook script に実行ビットがあるか | WARN | `[ -x <script>.sh ]` |
| C7 | hook script が git/gh/kubectl/aws/docker 等の外部 CLI を暗黙のコンテキスト解決（cwd・単一 remote・カレント kubeconfig 等）に依存して呼んでいないか。コマンド文字列側に明示的なコンテキスト上書き引数（`--repo`/`-R`, `-C`/`--git-dir`/`--work-tree`, `--context`/`--namespace`/`-n`/`--kubeconfig`, `--profile`/`--region` 等）が現れうるのに、それを読み取って外部 CLI 呼び出しへ反映していないか | CRITICAL（既知パターン検出時）/ WARN（抽出コードはあるが反映範囲が静的検出不能） | check-items.md C7 |
| C8 | 上記の環境依存前提の限界が `design-notes.txt` に明記されているか（cwd 依存性の既知の限界として） | INFO | `grep '既知の限界\|cwd' design-notes.txt` |

### 観点 D: paths 戦略

| # | チェック | 重要度 | 検出方法 |
|---|---|---|---|
| D1 | 全タスクで違反しうる規約が lazy になっていないか | WARN | rule.md に paths frontmatter があるのに内容が汎用的 |
| D2 | 特定 path 限定の規約が eager になっていないか | INFO | rule.md に paths がないのに内容が path 依存 |

### 観点 E: ADR

| # | チェック | 重要度 | 検出方法 |
|---|---|---|---|
| E1 | 同ディレクトリに `design-notes.txt`（設計判断サイドカー）があるか。rule.md 内に長文の `## 設計判断` が残っていないか | CRITICAL | `[ -f design-notes.txt ]` と `grep "## 設計判断" rule.md`（後者はヒットしないのが正） |
| E2 | ADR 4 項目（必要性 / 代替案 / 保守責任者 / 廃棄条件）が design-notes.txt に揃っているか | WARN | grep で各項目を確認 |
| E3 | hook script ごとに設計判断があるか（`.sh` が存在する場合） | WARN | `.sh` の basename を design-notes.txt 内で grep |
| E4 | `## プロジェクト上書き` セクションがあるか（委譲可/一律適用/上書き禁止 の 3 択宣言） | WARN | `grep "## プロジェクト上書き" rule.md` |

### 観点 F: 注入タグの整合性

| # | チェック | 重要度 | 検出方法 |
|---|---|---|---|
| F1 | rule.md の見出しタグと hook script の出力タグが一致するか | CRITICAL | rule.md の `# <名前>（<TAG>）` と `.sh` の `[TAG]` を突合 |
| F2 | rule.md の「## 違反検知時の手順」に hook が出力する全タグの手順があるか | CRITICAL | `.sh` 内の全 `[TAG]` を抽出し、rule.md の `### \`[TAG]\`` 見出しと突合 |
| F3 | タグ名が UPPER-HYPHEN 形式か | WARN | `grep -oE '\[[A-Z][A-Z0-9-]+\]'` |

### 観点 G: 内容品質

| # | チェック | 重要度 | 検出方法 |
|---|---|---|---|
| G1 | rule.md が 200 行を超えていないか | INFO | `wc -l rule.md` |
| G2 | 1 つの rule.md に 3 つ以上の独立トピックが混在していないか | INFO | `## ` 見出し数を確認 |
| G3 | 他の rule.md と内容が重複していないか | INFO | 主題の類似性を人手で判定 |

## Phase 3: レポート出力

```
## managing-agent-configs（種別: rules） review レポート（full / dry-run）

### 対象: ~/.claude/rules/
- 検出 rule 数: N
- CRITICAL: X / WARN: Y / INFO: Z

#### A. フォルダ構造
- [CRITICAL] A1 ルート直下に `security.md` が残存
  修正案: `security-rules/rule.md` に移動

#### B. scope 適合性
- [CRITICAL] B1 `always/agent/role-boundary/` がグローバルに配置されているが
  特定プロジェクト固有の内部概念（例: 内部スロット識別子・所有者コンテキスト等）に依存
  修正案: `<project>/.claude/rules/` に移動
...
```

## Phase 4: 自動修正承認（full モードのみ）

CRITICAL / WARN の各件について:

1. 修正案を提示
2. `AskUserQuestion` で承認を求める（バッチ承認可）
3. 承認された修正を `Edit` / `mv` / `Write` で適用

## Phase 5: 健全性判定

| 判定 | 条件 |
|---|---|
| 健全 | CRITICAL 0 件、WARN 2 件以下 |
| 要注意 | CRITICAL 0 件、WARN 3 件以上 |
| 不健全 | CRITICAL 1 件以上 |

## Phase 6: 連鎖（full モードのみ）

全修正完了後、test モードへ自動連鎖する。
