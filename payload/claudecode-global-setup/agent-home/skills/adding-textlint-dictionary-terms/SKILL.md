---
name: adding-textlint-dictionary-terms
description: "textlint置き換え辞書（prh.yml）への新規語彙登録。 TRIGGER when: 「prh.yml登録」「辞書に登録」「置き換え語を追加」と言われた時、text-dictionary/rule.md の [TEXTLINT-BLOCK] 手順で辞書に該当エントリがない時。 SKIP: 既存エントリでの単純な置換修正（→rules側で完遂。text-dictionary/rule.md の違反時手順を直接実行）。"
invocation: adding-textlint-dictionary-terms
type: action
allowed-tools: ["Read", "Write", "Edit", "Bash", "Grep", "Glob"]
---

# textlint置き換え辞書への語彙登録

このスキルは「textlint 置き換え辞書（prh.yml）に新しい語彙を登録する」ワークフロー専用。
既存エントリでの置換修正・textlint エラーの読み方は `~/.claude/rules/always/review-checklist/text-dictionary/rule.md` の違反時手順が完結して担う（本スキルへの委任なし）。

## Step 1: 登録先の判断
- 全プロジェクト共通の語彙 → グローバル辞書 `~/.claude/rules/always/review-checklist/text-dictionary/prh.yml`
- 特定プロジェクト固有の語彙 → `<repo>/.claude/rules/always/review-checklist/text-dictionary/prh.yml`（プロジェクト委譲の受け口。グローバルと合成されて lint に使われる。追加のみ可・グローバル語彙の無効化は不可）

## Step 2: 重複チェック
`~/.claude/rules/always/review-checklist/text-dictionary/prh.yml` を Read し、`expected:` 値で衝突がないか確認する。重複時は以下を判断する。
- 既存エントリで十分なら追加しない。この場合、Step 3 以降は実行せず終了する
- 表記バリアントの追加が必要なら既存行を編集する

## Step 3: 推奨置き換えと誤検知注意の決定
- **推奨置き換え**: 2〜4 候補をスラッシュ区切りで併記する
- **誤検知注意**: 確立した訳語・固有 API 名・別文脈での意味が想定される場合に明記する。なければ「—」

## Step 4: 辞書への追加
`~/.claude/rules/always/review-checklist/text-dictionary/prh.yml` の `rules:` 末尾に YAML ブロックを追記する。
- `expected:` = 先頭の推奨置き換え
- `# 推奨:` コメント行 = 複数候補をスラッシュ区切りで列挙
- `# 誤検知注意:` コメント行 = 誤検知対象外の条件（なければ省略）
- `patterns:` = カタカナ形と英語形を正規表現で列挙

## Step 5: 既存使用箇所の調査と置換
```bash
grep -rn -iE "(<英語形>|<カタカナ形>)" ~/agent-home/skills/ --include="*.md"
```
各ヒット箇所について判断する:
- 「誤検知注意」に該当する文脈 → 置換しない
- それ以外 → 推奨置き換えから文脈に合う訳語を選び Edit で置換する
- 辞書自身のエントリ行（prh.yml 内）は残置する

## Step 6: 検証とコミット
再度 grep を実行し、残存が「辞書自身のエントリ行」または「誤検知注意で対象外と判断した箇所」のみであることを確認する。
`grouping-commits` スキルで辞書追加と既存置換を同一コミットにまとめる。

## 対象外パターン
技術略語（API・JSON・SDK 等）・ツール名（GitHub・Slack 等）・確立した訳語のない技術用語（コンテナ・リポジトリ等）は登録しない。

## 完了報告
`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（作業報告型）に従う。
固有の検証行: 追加した prh.yml エントリと再 grep 後の残存件数

## 予想を裏切る挙動
- prh.yml の YAML インデントが崩れると linter が全体をパースエラーにする — 追記後は必ずインデントを目視確認する

## 参照資料
- `~/.claude/rules/always/review-checklist/text-dictionary/prh.yml` — 置き換え辞書本体（追加先）
- `~/.claude/rules/always/review-checklist/text-dictionary/rule.md` — 辞書規約・違反時の自己完結修正手順
