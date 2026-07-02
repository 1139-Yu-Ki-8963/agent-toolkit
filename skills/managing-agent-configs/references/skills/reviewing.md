# スキルレビュー手順（reviewing）

`managing-agent-configs`（種別: skills） の **review モード** が参照する手順書。`conventions.md` を前段で読んだ前提で、既存 SKILL.md の観点ベース静的レビューと自動修正を実行する。

このファイルを読み終えたら、Phase 1〜5 を実行し、完了後 **自動的に test モード** へ連鎖する（ハブ SKILL.md の指示に従う）。

## 概要

既存の `SKILL.md` を **観点ベース** で静的レビューし、検出した問題をユーザー承認のうえ自動修正する。`managing-agent-configs（種別: hooks）` の review モードと構造は同型（SKILL.md 版）。

## フロー系スキルの判定基準

観点 **F（ツール活用）** は、次のいずれかを満たす **フロー系（オーケストレーター型）** スキルにのみ適用する。満たさないスキルは「F: 該当なし」と明示し A〜E のみ評価する。

- `## Phase` / `### Phase` 見出しを 3 つ以上含む
- 本文で他スキルを `Skill` ツール起動 / サブエージェント委譲している
- 複数 PR・issue・並列タスクを統制する
- description に「フロー」「一括」「統制」「オーケストレ」「ワークフロー」「まとめて」を含む

判定用の grep 式は `check-items.md` の F カテゴリに収録する。

## 実行 Phase

### Phase 1: 対象 SKILL.md の発見

引数でスキル名が指定されればそれを対象に、無ければ全スキルを列挙する。各スキルにつき上記基準でフロー系か否かを判定する。

```bash
ls ~/.claude/skills/*/SKILL.md
# 指定時のみ
ls ~/.claude/skills/<name>/SKILL.md
```

### Phase 2: 静的解析（観点チェック）

各 SKILL.md を観点表（後述）の ID ごとに **Bash ツールで** grep / python コマンドを実行して検査する。フロー系判定が真のスキルのみ F カテゴリを評価する。詳細な検出式・修正前後例は `check-items.md` を参照。

### Phase 3: 実体検証（行数・文字数予算・references）

```bash
# 本体行数（C1: 500 行 / C2: 200 行）
wc -l ~/.claude/skills/<name>/SKILL.md
# references 参照先の実在
ls ~/.claude/skills/<name>/references/ 2>/dev/null
```

description 文字数（A4: 説明文 50 字/件、A5: 全合計 2000 字）を測定する。A4 は TRIGGER 行より前の説明文のみを計上し、TRIGGER when / SKIP の本文は除外する（検出式は `check-items.md` の A4 参照）。

### Phase 4: レポート出力

スキル別 → カテゴリ別 → 項目別の階層で集計する。フロー系には F 評価を併記し、非フロー系は「F: 該当なし」と明示する。

```
## review レポート

### スキル: parallel-dev-worktree（フロー系）
- 行数: 179 / description: 152 字
- CRITICAL: 0 / WARN: 3 / INFO: 1

#### F. ツール活用（フロー系）
- [WARN] F4 ExitPlanMode 未使用 — 非自明な実装フローでプラン承認を取っていない
- [INFO] F6 他スキル呼び出しが手順記述のみ — Skill ツール明示を推奨
```

### Phase 5: 自動修正

検出された CRITICAL / WARN について `AskUserQuestion` で承認範囲を確認する。

| 選択肢 | 動作 |
|--------|------|
| 全件採用 | 検出された全 CRITICAL / WARN を自動修正 |
| 個別選択 | 項目 ID をリストで提示し、修正する項目だけ選ばせる |
| CRITICAL のみ | CRITICAL のみ修正、WARN は次回判断 |
| スキップ | 修正せず test モード連鎖へ進む（dry-run モード） |

承認分を `Edit` ツールで SKILL.md に適用する。本体肥大化（C2）の `references/` 分離が必要な場合でも新規 `.sh` ファイルは **作成しない**（`security.md` のスクリプトファイル作成禁止）。references の `.md` 分離は可。F 観点の指摘（ツール活用不足）は設計判断を伴うため、修正案を提示しユーザー承認を得てから本文へ反映する。

### Phase 6（自動連鎖）: test モードへ遷移

Phase 5 完了後、ハブ SKILL.md の指示に従い **test モードへ自動遷移** する。ユーザーが明示的に「レビューまでで止めて」と言った場合のみ連鎖を停止する。

連鎖時は `Agent` ツールで白紙状態の新規サブエージェントを起動し、`testing.md` の手順に従わせる:

```
Agent(
  description: "修正後スキルの発火検証",
  subagent_type: "general-purpose",
  prompt: "~/.claude/skills/managing-agent-configs/references/skills/testing.md の手順に従い、
           Phase 5 で修正された各 SKILL.md について以下を検証:
           ① description の TRIGGER 語を含む代表プロンプトで正しく発火するか
           ② SKIP 語を含むプロンプトで誤発火しないか
           ③ 隣接スキル（managing-agent-configs（種別: hooks） / managing-agent-configs（種別: skills） 自体 等）と発火が衝突しないか
           発火しなかった / 誤発火したスキル名と原因を箇条書きで報告。"
)
```

### Phase 7: 最終報告

以下を能動文・日本語で報告する。

- 対象スキル数（うちフロー系の件数）
- 修正前 CRITICAL / WARN / INFO 件数 → 修正後の差分
- test モード検証結果（発火 PASS / FAIL 件数、誤発火スキル名）
- 未対応項目（修正不能な指摘とその理由）
- 健全性判定（後述）

## 観点チェック表

詳細な検出式・修正前後サンプルは `check-items.md` を参照。

### A. frontmatter / メタデータ（9 項目）

| ID | 重大度 | 検出 | 修正方針 |
|----|--------|------|----------|
| A1 | CRITICAL | `name` が非 kebab-case / 64 字超 / invocation 設定時に name≠invocation | 規約準拠に修正 |
| A2 | WARN | `name` が gerund 形（verb+ing + 名詞）でない。**ただし公式スキル（プロバイダー提供で名前変更不可）は対象外** | naming-conventions に沿って改名提案（カスタムスキルのみ） |
| A3 | CRITICAL | description に `TRIGGER when:` か `SKIP:` が欠落 | 両キーワードを追記 |
| A4 | CRITICAL | 説明文（TRIGGER 行より前）が 50 字超 | 要約して 50 字以内に。TRIGGER / SKIP は計上しない |
| A5 | WARN | 全スキル合計 description が 2000 字超 | 長い description を圧縮 |
| A6 | CRITICAL | `invocation` フィールドが存在しないか `name` と不一致 | `invocation: <name と同値>` を追記・修正 |
| A7 | WARN | `allowed-tools` が未記載または型の最小セットを下回る | 型別最小セットを設定（`conventions.md` 参照） |
| A8 | CRITICAL | frontmatter に `type:` が無い、または 9 種類以外の値 | 振る舞いを再判定し正しい slug を追記。判定の決定木は `conventions.md` の Type 判定セクションを参照 |
| A9 | INFO | frontmatter の `type:` が本文中の挙動と乖離 | 振る舞いに合わせて type を修正、または振る舞いを type に揃える |

### B. description 品質（発火条件・3 項目）

| ID | 重大度 | 検出 | 修正方針 |
|----|--------|------|----------|
| B1 | WARN | 「〜用」等の抽象短文で具体キーワードがない | 反応すべき語を列挙 |
| B2 | WARN | TRIGGER 範囲が広すぎ誤発火リスク | 範囲を絞り SKIP を補強 |
| B3 | INFO | SKIP が他スキルへの誘導（→別スキル）を欠く | 境界スキルを明示 |

### C. 本体サイズ・段階的開示（6 項目）

| ID | 重大度 | 検出 | 修正方針 |
|----|--------|------|----------|
| C1 | CRITICAL | SKILL.md が 500 行超 | `references/` へ詳細分離 |
| C2 | WARN | 200 行超で詳細を本体に直書き | `references/` へ分離（目次＋最小手順を残す） |
| C3 | WARN | 公式ドキュメントを本文にコピー | 参照リンクに置換 |
| C4 | INFO | `references/` が汎用情報でスキル固有でない | スキル固有内容に限定 |
| C5 | INFO | 本文冒頭に旧形式の `> Category:` / `> Type:` blockquote が残っている | frontmatter `type:` に統合済みなので blockquote を削除 |
| C6 | WARN | `## Gotchas` セクションがない | 直感に反する罠を 1 行でも追記 |

### D. 単一責務（2 項目）

| ID | 重大度 | 検出 | 修正方針 |
|----|--------|------|----------|
| D1 | WARN | 1 スキルに複数責務を詰め込み | 責務単位に分割提案 |
| D2 | INFO | 共通手順を他スキルからコピペ | 参照元スキルへ一本化 |

### E. 副作用安全性（3 項目）

| ID | 重大度 | 検出 | 修正方針 |
|----|--------|------|----------|
| E1 | CRITICAL | push / merge / deploy / `rm -rf` がオート発火可能 | 承認要求 or 手動発火に限定 |
| E2 | WARN | スクリプトを SKILL.md に直書き | `scripts/` へ分離 |
| E3 | WARN | `!` 構文を使用（Cursor 非互換） | 通常記法に置換 |

### F. Claude ツール活用（★フロー系限定・13 項目）

| ID | 重大度 | 検出 | 修正方針 |
|----|--------|------|----------|
| F1 | WARN | 複数ステップが `## / ### Phase N` で段階化されていない | Phase 分割して明示 |
| F2 | WARN | 重い調査・並列処理を `Agent`（サブエージェント）に委譲していない | 委譲設計に書き換え |
| F3 | INFO | 多段・長時間タスクで `TaskCreate` / `TaskUpdate` 進捗可視化がない | 進捗管理を追加 |
| F4 | WARN | 非自明な実装フローで `ExitPlanMode`（プラン承認）を取っていない | プラン承認ステップを追加 |
| F5 | WARN | 取り消し困難な操作・分岐で `AskUserQuestion` を使っていない | 承認・選択を挿入 |
| F6 | INFO | 他スキル呼び出しが手順記述のみで `Skill` ツール明示がない | Skill ツール起動を明記 |
| F7 | WARN | 「AI の挙動頼み」でツール呼び出しによる仕組み化がない | ツール起動で仕組み化 |
| F8 | CRITICAL | 各 Phase/Step に完了条件（`完了条件:` 行 or 完了条件テーブル）が明記されていない | Phase ごとに完了条件を 1 行で追記 |
| F9 | WARN | サブエージェント呼び出し仕様表（subagent_type・prompt 骨格・期待返却値）が存在しない | `## サブエージェント委任仕様` セクションに仕様表を追加 |
| F10 | WARN | ループ構成（反復条件・上限回数・停止条件）が定義されていない | `## ループ設計` セクションに 3 要素を明記 |
| F11 | WARN | /goal（最終成功判定基準）が定義されていない | `## 完了条件` セクション末尾に Goal 行を追記 |
| F12 | INFO | 検証役（生成役と別のエージェント）が指定されていない | 検証役の分離を明記 |
| F13 | CRITICAL | `### Step` が `## Step` や `## <親見出し>` の下に h3 としてネストされている | 全 Step を `##`（h2）に昇格し、親の傘見出しを削除する。h3 ネストはエージェントが複数 Step を 1 タスクとして扱い、別成果物を統合してしまう原因になる |

### G. 登録・整合性（3 項目）

| ID | 重大度 | 検出 | 修正方針 |
|----|--------|------|----------|
| G1 | CRITICAL | 配置が `~/.claude/skills/<name>/SKILL.md` でない / 本文に絶対パス直書き | 規定パスへ移動・相対参照化 |
| G2 | WARN | `README.md` のスキル一覧にエントリがない | `<details>` エントリを追加 |
| G3 | INFO | セクション見出しが日本語で統一されていない | 日本語へ統一 |

**合計 32 項目（A〜E・G: 19 項目／F: 13 項目はフロー系のみ）**

## 健全性目安

- CRITICAL: 0 件
- WARN: 3 件以下
- INFO: 制限なし
- test モード連鎖検証: 全 PASS（誤発火 0 件）

上記すべてを満たした場合のみ「健全」と報告する。

## Gotchas

- 自動修正の前に必ずユーザー確認: `approved=true` を得るまで Edit を発行しない（Phase 5 の承認フロー）
- test モード連鎖を省略すると「静的レビューのみ」で終わる: Phase 6 を省略しない
- description の 50 字制限は説明文のみ: TRIGGER when / SKIP 行は別カウント（A4 の検出式を参照）

## 参照資料

- 共通規約: `conventions.md`
- 観点別の検出式と修正前後例: `check-items.md`
- 連鎖先の手順書: `testing.md`
