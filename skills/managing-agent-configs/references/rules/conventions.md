# Rules 共通規約（conventions）

`managing-agent-configs`（種別: rules） の create / review / test 全モードが参照する **規約の単一正本**。フォルダ構造・命名・eager/lazy 判定・hook 連携パターン・ADR 必須項目をここで定義する。

各モードは最初にこのファイルを Read してから役割別 references（`creating.md` / `reviewing.md` / `testing.md`）に進む。

外部正本: `docs/rules-design.html`（§1〜§11）

## 1. フォルダ構造

```
~/.claude/rules/                    … グローバル rules
  <category>-rules/                 … 必須形式（ルート直下 .md は禁止）
    rule.md                         … 規約本体（必須）
    <hook-name>.sh                  … 対になる hook script（任意）
    <hook-name>.test.sh             … hook のテスト（任意）

<repo>/.claude/rules/               … プロジェクト rules
  <category>-rules/                 … 同上
    rule.md
    <hook-name>.sh
```

**禁止**: ルート直下に `<name>.md` を置くこと。必ず `<name>-rules/rule.md` にする。

## 2. 命名規約

| 対象 | 命名規則 | 例 |
|---|---|---|
| カテゴリ（ディレクトリ名） | `<category>-rules/`（kebab-case） | `no-root-marker-rules/` |
| 規約本体 | `rule.md`（固定） | — |
| hook script | kebab-case + `.sh` | `no-root-marker-check.sh` |
| 注入タグ | UPPER-HYPHEN | `[NO-ROOT-MARKER-BLOCK]` |

## 3. eager / lazy 判定

| モード | 条件 | paths frontmatter |
|---|---|---|
| eager（常時注入） | 全タスクで違反しうる規約 | なし |
| lazy（条件注入） | 特定 path・拡張子の作業中だけ違反しうる規約 | あり |

判定フロー:

```
Q1. この規約は全タスクで違反しうるか？
    YES → paths 無し（eager）
    NO  → Q2

Q2. 特定の path・拡張子の作業中だけ違反しうるか？
    YES → paths 指定（lazy）
    NO  → Q3

Q3. 特定キーワード時だけ違反しうるか？
    YES → rules に置かず UserPromptSubmit hook で注入
    NO  → skill 化を検討
```

**「絶対に守らせたい」規約は paths 無しにする**。lazy だと Read 漏れで違反する。

## 4. 配置の scope 判定

| scope | 条件 | 配置先 |
|---|---|---|
| global | 全プロジェクトで効かせる | `~/.claude/rules/<category>-rules/` |
| project | 単一プロジェクトのみ | `<repo>/.claude/rules/<category>-rules/` |

判定基準:
- 規約が参照するファイル・概念が特定プロジェクト固有（自プロジェクトの内部語彙・独自ディレクトリ構成等）なら project
- 言語・文体・セキュリティ・エージェント行動規範など汎用なら global

## 5. hook 連携パターン

### 標準フロー

```
[1] hook script が違反を検知（PreToolUse / PostToolUse / Stop 等）
    ↓
[2] additionalContext にタグ + 検出事実 + rule.md への参照を出力
    ↓
[3] Claude が rule.md（eager なら既に context にロード済み）を参照
    ↓
[4] rule.md の「## 違反検知時の手順」に従い修正
```

### additionalContext の書き方

- **短文のみ**（300 字以内）。タグ + 検出事実 + rule.md のパス
- 対応手順（プロンプト）を hook に埋め込まない。rule.md に書く
- rule.md は eager ロード済みなので Claude が即参照できる

```
# ✗ 禁止（hook にプロンプトを埋め込む）
ctx="[NO-DELEGATION] 直前の出力にユーザーへのコマンド実行依頼を検出しました。
(1) Claude 自身のツールで完遂する応答に書き換える、または
(2) 代行不可なら [NO-DELEGATION-ABORT] 形式の中止報告に書き換えること。"

# ✓ 正解（タグ + 事実 + 参照のみ）
ctx="[NO-DELEGATION] 最終応答にユーザー操作依頼を検出。
~/.claude/rules/no-delegation-rules/rule.md を参照。"
```

### タグと rule.md の対応

1:1 対応。`[FOO-BLOCK]` なら `foo-rules/rule.md` に対応手順がある。

## 6. rule.md の必須構造

```markdown
# <カテゴリ名>（<TAG-NAME>）

<禁止 / 規約の宣言文（1 段落）>

## 禁止対象 / 機能概要

<箇条書き>

## 機械強制

| timing | スクリプト | 注入タグ | 挙動 |
|---|---|---|---|

## 違反検知時の手順

### `[TAG]` 受信

1. ...
2. ...

## 設計判断

### <script 名>

**必要性**: ...
**代替案を採用しなかった理由**: ...
**保守責任者**: ...
**廃棄条件**: ...
```

## 7. ADR 必須項目

rule.md 内の `## 設計判断` セクションに記載する 4 項目:

| 項目 | 内容 |
|---|---|
| 必要性 | なぜこの規約 / スクリプトが必要か |
| 代替案を採用しなかった理由 | Bash 直叩き / Makefile / permissions.deny 等がなぜ不可か |
| 保守責任者 | 人手（ユーザー）/ routine 名 |
| 廃棄条件 | いつ削除してよいか |

hook script（`.sh`）が存在する場合は、各 `.sh` ごとに設計判断を書く。

## 8. アンチパターン

| パターン | 問題 | 正解 |
|---|---|---|
| ルート直下に `<name>.md` を置く | フォルダ構造の一貫性が崩れる | `<name>-rules/rule.md` |
| hook script を別フォルダに分離 | 規約と機械強制の対応が見えなくなる | 同ディレクトリに同居 |
| additionalContext に rule.md 全文をコピペ | 毎発火で token を浪費 | タグ + 短い指示 + path のみ |
| 全 rule を eager にする | context を圧迫 | 該当 path 限定の規約は lazy 化 |
| 全 rule を lazy にする | Read 漏れで違反する | 常時必要な規約は eager |
| ADR なしで .sh を追加 | 削除判断ができなくなる | 追加時に ADR を書く |
| 特定プロジェクト固有の規約をグローバルに置く | 他プロジェクトでノイズ / 誤発火 | project scope に移動 |
| 1 つの rule.md に 5 カテゴリ詰め込む | 200 行超で attention が落ちる | カテゴリ分割 |
