# Rules 共通規約（conventions）

`managing-agent-configs`（種別: rules） の create / review / test 全モードが参照する **規約の単一正本**。フォルダ構造・命名・eager/lazy 判定・hook 連携パターン・ADR 必須項目をここで定義する。

各モードは最初にこのファイルを Read してから役割別 references（`creating.md` / `reviewing.md` / `testing.md`）に進む。

外部正本: `~/agent-home/ai-management-portal/design/rules.html`（§1〜§11）

## 1. フォルダ構造

グローバル rules は **深さ 3 固定** `<scope>/<topic>/<name>/rule.md`。第 1 階層は注入方式（`always/` = 常時注入、`scoped/` = paths 条件付き注入）、第 2 階層は内容トピック、第 3 階層は規約名（`-rules` suffix なし）。

```
~/.claude/rules/                    … グローバル rules（深さ 3 固定）
  always/                           … 常時注入（frontmatter なし）
    <topic>/                        … 内容トピック（naming / agent / git / gate / placement / session / response / ui / infra）
      <name>/
        rule.md                     … 規約本体（必須）
        <hook-name>.sh              … 対になる hook script（任意・同居）
        <hook-name>.test.sh         … hook のテスト（任意）
        <sidecar>.txt               … 非注入サイドカー（任意。※ .md 禁止、下記参照）
  scoped/                           … paths: frontmatter 付き（条件付き注入）
    <topic>/                        … 内容トピック（config / security 等）
      <name>/
        rule.md

<repo>/.claude/rules/               … プロジェクト rules
  <category>-rules/                 … 既存形式（深さ 1）。移行は任意
  <scope>/<topic>/<name>/           … 委譲可規約の受け口はグローバルと同一相対パスを推奨
```

**禁止**: ルート直下に `<name>.md` を置くこと。グローバルで深さ 3 以外に rule.md を置くこと。

**サイドカーは `.txt`**: `~/.claude/rules/` 配下の `.md` は深さ・ファイル名を問わず**全て常時注入される**（2026-07-03 実測。`references/` サブディレクトリ配下も注入される）。注入したくない規約値・長文資料は `.txt` 拡張子でサイドカー化する。

## 2. 命名規約

| 対象 | 命名規則 | 例 |
|---|---|---|
| scope（第 1 階層） | `always` / `scoped` の 2 値固定 | — |
| topic（第 2 階層） | kebab-case・内容カテゴリ | `naming/` `placement/` |
| 規約名（第 3 階層） | kebab-case・`-rules` suffix 禁止 | `semantic-key/` `commit-branch/` |
| 規約本体 | `rule.md`（固定） | — |
| hook script | kebab-case + `.sh` | `no-root-marker-check.sh` |
| サイドカー | kebab-case + `.txt` | `naming-values.txt` |
| 注入タグ | UPPER-HYPHEN | `[NO-ROOT-MARKER-BLOCK]` |

## 3. eager / lazy 判定（= always / scoped 配置判定）

| モード | 条件 | paths frontmatter | 配置先 |
|---|---|---|---|
| eager（常時注入） | 全タスクで違反しうる規約 | なし | `always/<topic>/<name>/` |
| lazy（条件注入） | 特定 path・拡張子の作業中だけ違反しうる規約 | あり | `scoped/<topic>/<name>/` |

判定フロー:

```
Q1. この規約は全タスクで違反しうるか？
    YES → paths 無し（eager）→ always/
    NO  → Q2

Q2. 特定の path・拡張子の作業中だけ違反しうるか？
    YES → paths 指定（lazy）→ scoped/
    NO  → Q3

Q3. 特定コマンド・イベント時だけ違反しうるか？
    YES → always/ に置き、rule.md は「タグ + 参照先」の薄い索引に留めて
          詳細（規約値・長文手順）は .txt サイドカーへ。hook がイベント時に参照を注入する
    NO  → Q4

Q4. 特定キーワード時だけ違反しうるか？
    YES → rules に置かず UserPromptSubmit hook で注入
    NO  → skill 化を検討
```

**「絶対に守らせたい」規約は paths 無しにする**。lazy だと Read 漏れで違反する。

## 4. 配置の scope 判定

| scope | 条件 | 配置先 |
|---|---|---|
| global | 全プロジェクトで効かせる | `~/.claude/rules/<scope>/<topic>/<name>/` |
| project | 単一プロジェクトのみ | `<repo>/.claude/rules/<category>-rules/`（既存形式） |

判定基準:
- 規約が参照するファイル・概念が特定プロジェクト固有（oradora の slot/mock/portal 等）なら project
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

1:1 対応。`[FOO-BLOCK]` なら規約名 `foo` の rule.md（`<scope>/<topic>/foo/rule.md`）に対応手順がある。

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

## プロジェクト上書き

- 上書き可否: <委譲可（値のみ） / 一律適用 / 上書き禁止> のいずれかを必ず宣言
- 受け口: <repo>/.claude/rules/<本規約と同一相対パス>（委譲可の場合のみ）
- 優先順位: 受け口が存在すれば値はプロジェクト側を優先。
  枠組み（何を守るか・違反時手順）はグローバルが常に正

## 設計判断

### <script 名>

**必要性**: ...
**代替案を採用しなかった理由**: ...
**保守責任者**: ...
**廃棄条件**: ...
```

## 6b. プロジェクト上書き宣言（必須セクション）

全ての新規 rule.md は `## プロジェクト上書き` セクションで次の 3 択を必ず宣言する:

| 宣言 | 意味 | 例 |
|---|---|---|
| 委譲可（値のみ） | プロジェクト側受け口があれば規約値をそちら優先で読む。hook は `lib-rule-resolver.sh` の `resolve_rule_file` で解決する | directory-structure の許可リスト、commit-branch の naming-values |
| 一律適用 | 全プロジェクト共通。上書き実例を作らない | semantic-key |
| 上書き禁止 | プロジェクト側での迂回を例外なく禁止する | security 系 |

宣言がない rule.md はレビューで WARN とする。デフォルトを「委譲可」に倒さない（セキュリティ系規約の迂回口になるため、規約ごとの明示宣言が必須）。

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
| ルート直下に `<name>.md` を置く | フォルダ構造の一貫性が崩れる | `<scope>/<topic>/<name>/rule.md` |
| ディレクトリ名に `-rules` suffix を付ける | `rules/` 配下で冗長。旧形式の残骸 | suffix なしの規約名 |
| 規約値の長文サイドカーを `.md` で置く | rules 配下の .md は全て常時注入され context を浪費 | `.txt` 化（例: `naming-values.txt`） |
| `## プロジェクト上書き` 宣言の欠落 | グローバル/プロジェクトの優先関係が規約ごとに不明のまま残る | 3 択（委譲可/一律適用/上書き禁止）を必ず宣言 |
| hook script を別フォルダに分離 | 規約と機械強制の対応が見えなくなる | 同ディレクトリに同居 |
| additionalContext に rule.md 全文をコピペ | 毎発火で token を浪費 | タグ + 短い指示 + path のみ |
| 全 rule を eager にする | context を圧迫 | 該当 path 限定の規約は lazy 化 |
| 全 rule を lazy にする | Read 漏れで違反する | 常時必要な規約は eager |
| ADR なしで .sh を追加 | 削除判断ができなくなる | 追加時に ADR を書く |
| oradora 固有の規約をグローバルに置く | 他プロジェクトでノイズ / 誤発火 | project scope に移動 |
| 1 つの rule.md に 5 カテゴリ詰め込む | 200 行超で attention が落ちる | カテゴリ分割 |
