# スキル共通規約（conventions）

`managing-agent-configs`（種別: skills） の create / review / test 全モードが参照する **規約の単一正本**。フロントマター必須項目・Type 決定木・文字数予算・フォルダ構成・Progressive Disclosure をここで定義する。旧 `creating-custom-skills` 本体に散在していた規約をここに集約した。

各モードは最初にこのファイルを Read してから役割別 references（`creating.md` / `reviewing.md` / `testing.md`）に進む。

## 1. フロントマター必須フィールド

| フィールド | 制限 | 説明 |
|-----------|------|------|
| `name` | kebab-case、15〜64 文字 | スキルの一意識別子。名前だけで What（何をするか）と How or Scope（どうやるか/何が対象か）が読み取れること |
| `description` | 説明文（TRIGGER 行より前）は **50 字以内**、複数行可 | **自動発動のトリガー**。`TRIGGER when:` と `SKIP:` を必ず含める |
| `invocation` | `name` と同値 | スキル呼び出し用キー（`/invocation名` で手動実行） |
| `type` | 後述 9 種類の中から 1 つ | スキルの振る舞い型 |
| `allowed-tools` | 型別の最小セット | スキルが触れるツールの allowlist |

### name の情報密度基準

スキル名には以下の 3 要素のうち少なくとも 2 つを含める。

| 要素 | 問い | 例（`reviewing-single-pr-with-inline-comments`）|
|---|---|---|
| **What**（何をするか） | 主動作は？ | reviewing |
| **How**（どうやるか） | 差別化ポイントは？ | with-inline-comments |
| **Scope**（何が対象か） | 対象範囲は？ | single-pr |

15 文字未満の例外: 固有名詞スキル（`supabase`、`render-*` 群）は description の説明文で What/How/Scope の不足分を補うこと。

## 2. description の書き方（最重要）

Claude は起動時に全スキルの description を読み込み、リクエストにマッチすると本体をロードする。

**必須要素:**
- 「何をするのか」の一行説明（50 字以内）
- `TRIGGER when:` に続けて発動条件を記述（**固定英語キーワード**）
- `SKIP:` に続けて非発動条件を記述（**固定英語キーワード**）

> **重要**: `TRIGGER when:` と `SKIP:` はシステムがスキルの発動条件を解析する固定英語キーワード。
> `Use when:` / `使用時:` など別の表記は非標準で解析されない。

**悪い例:**
```yaml
description: Git worktreeを管理するスキル
```

**良い例:**
```yaml
description: |
  ブランチ作成・worktree管理を行うスキル。
  TRIGGER when: ブランチ作成時、git checkout時、worktree作成時。
  SKIP: 既存ブランチの読み取り・確認のみの時。
```

詳細例は `description-examples.md` を参照。

## 3. 文字数予算

- **1 スキルあたり**: description の説明文（TRIGGER 行より前）は **50 字以内**
- **全スキル合計**: `~/.claude/skills/` 全体の description 合計を **2,000 文字以内** に維持する
- 超過すると Claude Code 起動時に「N skill descriptions dropped」が発生し、後ろのスキルが自動選択されなくなる

合計確認コマンド:

```bash
python3 -c "
import os, re
d = os.path.expanduser('<project>/skills')
t = 0
for s in os.listdir(d):
    p = os.path.join(d, s, 'SKILL.md')
    if os.path.isfile(p):
        m = re.search(r'^description:\s*(.*?)(?=\n\w|\n---)', open(p).read(), re.M|re.S)
        if m: t += len(m.group(1).strip())
print(f'合計 {t} 文字 / 予算 2000 文字')
"
```

## 4. Type 9 種類（決定木）

スキルの「振る舞い型」を以下の決定木で 1 つに絞る。これは Category（業務領域）とは独立した第 2 軸。

```
Q1: 親フロー（flow-feature 等）の Phase 内部から呼ばれ go/no-go を返すか?
  YES → gate（関門型）
  NO  → Q2

Q2: hook 注入タグ ([TEXTLINT] [AMBIGUITY-AUTO-FIX] [PUBLISH-*] 等) で
     ユーザー発話なしに自動起動するか?
  YES → reactive（反応型）
  NO  → Q3

Q3: Phase/Step で順序を強制し、下位スキルを 2 つ以上呼ぶか?
  YES → orchestration（フロー本体型）
  NO  → Q4

Q4: フロー本体の前段で素材・対象・環境を確定し、終わったらフロー起動を期待するか?
  YES → gateway（入口型）
  NO  → Q5

Q5: 実機シナリオでスキル・フックを動かして観察するか?
  YES → verification（実機検証型）
  NO  → Q6

Q6: 既存物を読み取り観点ベースで点検レポートを返すか?
  YES → audit（静的監査型）
  NO  → Q7

Q7: 入力 → 別形式の出力（生成・整形・変換）か?
  YES → transform（生成・変換型）
  NO  → Q8

Q8: 他スキル・直接編集の前に「ロードして従う」対象になる横串のルール集か?
  YES → reference（規範型）
  NO  → action（単発操作型）
```

| slug | 日本語 | 一文定義 | 典型例 |
|---|---|---|---|
| `orchestration` | フロー本体型 | Phase/Step で順序を強制し、複数下位スキルを束ねる | flow-feature, auto-ship, pr-review-workflow, **managing-agent-configs（種別: skills）** |
| `gateway` | 入口型 | フロー本体の前段で素材を確定し、確定後にフローへ橋渡し | preparing-manual-mockup, picking-issues, parallel-dev-worktree |
| `gate` | 関門型 | フロー内 Phase から呼ばれ go/no-go を返す | flow-reviewing-design-doc, flow-reviewing-impl-quality, verifying-issue-scope |
| `audit` | 静的監査型 | 既存物の読み取り中心の点検レポート | （hooks 系は `managing-agent-configs（種別: hooks）` の review モードに統合） |
| `verification` | 実機検証型 | 実機で動かして観察 | test-e2e（hooks 系は `managing-agent-configs（種別: hooks）` の test モードに統合） |
| `reactive` | 反応型 | hook タグ起動 | clarifying-ambiguity, reviewing-public-readiness, resolving-conflicts |
| `reference` | 規範型 | 他スキルからロードされる横串ルール集 | naming-conventions, frontend-design, render-* 群 |
| `transform` | 生成・変換型 | 入力 → 別形式の出力 | formatting-pr, formatting-issue, converting-html-to-design-md |
| `action` | 単発操作型 | 1 アクションで副作用ありの完了 | grouping-commits, registering-replacements, launching-dev-servers |

## 5. allowed-tools 型別最小セット

| Type | 最小セット |
|---|---|
| reference | `Read`, `Grep`, `Glob` |
| orchestration, action | `Bash`, `Read`, `Write`, `Edit` |
| reactive, gate, audit | `Agent`, `Read`, `Grep`, `Bash` |
| verification | `Agent`, `Bash`, `Read`, `Grep` |
| gateway, transform | 用途に応じて `Read`, `Write`, `Edit`, `Bash`, `AskUserQuestion` を選定 |

## 6. スキルフォルダ構成

```
my-skill/
├── SKILL.md          # 必須（500 行以下推奨）
├── scripts/          # 再利用可能な実行可能コード
├── references/       # そのスキル固有の詳細情報
└── assets/           # 出力用ファイル（テンプレート等）
```

**重要**: `references/` には **そのスキル固有** の詳細情報のみ配置。公式ドキュメントのコピーは禁止。詳細は `folder-structure.md` を参照。

## 7. Progressive Disclosure（段階的開示）

| 段階 | 内容 | ロードタイミング | トークン目安 |
|------|------|------------------|--------------|
| **Stage 1** | メタデータ（name, description） | 常にロード | 〜100 トークン |
| **Stage 2** | SKILL.md 本体 | トリガー時 | 500 行 / 5000 トークン以下推奨 |
| **Stage 3** | バンドルリソース | SKILL.md 本体に参照が記載されているファイルを読む場合 | 制限なし |

## 7.5. Phase / Step 番号規約

- Phase・Step 番号は **1 始まりの正整数** のみ許可する
- `Phase 0`・`Step 0` は禁止（準備工程も Phase 1 として採番する）
- 小数点付き番号（`Phase 1.5`・`Step 2.1`）は禁止（中間工程は既存 Phase 内の Step として追加する）

## 8. セクション構成（日本語統一）

- `## 使用タイミング` - いつ発動するか
- `## 基本ワークフロー` - 主要な処理フロー
- `## ツールリファレンス` - 使用するツール一覧
- `## 推奨手順` - 推奨事項
- `## 重要な注意事項` - 禁止事項・制約
- `## Gotchas` - 直感に反する罠（1 行でも可、必須）
- `## 参照資料` - references/ への参照

## 8.5. フロー系スキルの追加必須セクション

Type が `orchestration` または `gateway` のスキル、あるいは `## Phase` 見出しを 3 つ以上含むスキルには、以下のセクションが追加で必要になる。

### `## 完了条件`

各 Phase / Step の完了条件を一覧する。各 Phase 見出しの直後に `完了条件:` 行を 1 行で書く方式と、セクション末尾にまとめて書く方式のいずれでも可。最終行には **最終成功判定（Goal）** を記載する。

```markdown
## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 対象ファイルが 1 件以上特定されている |
| Phase 2 | 全観点の検査結果が記録されている |
| Phase 3 | レポートがユーザーに提示されている |
| **Goal** | CRITICAL 0 件かつ WARN 3 件以下で「健全」判定 |
```

### `## サブエージェント委任仕様`（サブエージェントを呼ぶ場合のみ）

サブエージェント呼び出しごとに以下の 4 列を仕様表で定義する。

| 列 | 内容 |
|---|---|
| 呼び出し箇所 | どの Phase/Step で呼ぶか |
| subagent_type | `worker-sonnet` / `worker-haiku` / `researcher` / `brain` / `general-purpose` 等 |
| prompt 骨格 | 渡すプロンプトの構造（シナリオ・要件チェックリスト・レポート構造） |
| 期待返却値 | サブエージェントが返すべき出力の形式 |

### `## ループ設計`（反復がある場合のみ）

反復を含むフローでは、以下の 3 要素を定義する。

| 要素 | 内容 | 例 |
|---|---|---|
| 反復条件 | 何を反復するか | 「不明瞭な点が新たに浮上したら修正→再評価」 |
| 上限回数 | 最大何回で打ち切るか | 5 回 |
| 停止条件 | 何をもって反復を止めるか（3 パターン推奨） | 全チェック通過 / 最大 N 回 / 同じエラー 2 連続 |

停止条件は loop-design.html の原則に従い、以下の 3 パターンのうち少なくとも 2 つを明記する:

- **収束停止**: 全チェック通過が N 連続（推奨: N=2）
- **リソース上限**: 最大反復回数に到達
- **発散検知**: 同じエラーが M 回連続で再発（推奨: M=2〜3）

検証役（評価役）は生成役と分離する。理想的には別の subagent_type / Read のみ権限を使う（loop-design.html §5「評価役の設計」参照）。

## 9. 配置ルール

- 配置先: `~/.claude/skills/<name>/SKILL.md`
- プロジェクト固有なら `<repo>/.claude/skills/<name>/SKILL.md`
- 本文内では絶対パス（`/Users/...`）禁止。`~/.claude/skills/<name>/` または相対参照を使う

## 10. Gotchas（規約レベル）

- description の文字数制限: 50 字は「何をするか」の説明文（TRIGGER 行より前）のみ。TRIGGER when / SKIP 行は別カウント
- 型宣言を省略すると review が検査できない: frontmatter の `type:` は必ず 9 種類のいずれかを書く（旧形式の `> Type:` blockquote は frontmatter `type:` に統合済み）
- references/ と assets/ は用途が違う: references/ はそのスキル固有の参照知識。assets/ は出力用テンプレート
- Type は Category と直交する独立軸: Category（業務領域）は変えずに Type だけ書き換えられる
