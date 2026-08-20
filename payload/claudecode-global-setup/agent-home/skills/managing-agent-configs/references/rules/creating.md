# Rule 作成手順（creating）

`managing-agent-configs`（種別: rules） の **create モード** が参照する手順書。`conventions.md` を前段で読んだ前提で、新規 rule の作成を実行する。

## Phase 1: 要件確認

ユーザーの発話から以下を確認する。不足があれば `AskUserQuestion` で 1 問ずつ聞く。

| 項目 | 確認内容 |
|---|---|
| 規約の主題 | 何を禁止 / 強制するか |
| 違反パターン | どのような操作が違反になるか |
| 機械強制の要否 | hook で block / warn するか、rule.md のみか |

## Phase 2: カテゴリ判定

既存の rules ディレクトリを列挙し、新規カテゴリが必要か判定する。

```bash
find ~/.claude/rules/always ~/.claude/rules/scoped -mindepth 2 -maxdepth 2 -type d 2>/dev/null | sort
```

判定基準:
- 既存カテゴリと同じイベント（同じ hook タイミング）で発火するなら統合
- 注入タグが異なるなら別カテゴリ
- 既存 rule.md が 200 行を超えているなら分割

## Phase 3: scope / paths 判定

`conventions.md` §3〜§4 の判定フローに従う。

| 判定 | 結果 |
|---|---|
| 全プロジェクト共通か → YES | global（`~/.claude/rules/`） |
| 特定プロジェクト固有か → YES | project（`<repo>/.claude/rules/`） |
| 全タスクで違反しうるか → YES | eager（paths なし）→ `always/<topic>/<name>/` |
| 特定 path のみか → YES | lazy（paths あり）→ `scoped/<topic>/<name>/` |

## Phase 4: rule.md の作成

`conventions.md` §6 のテンプレートに従い、rule.md を Write する。

必須セクション:
1. `# <カテゴリ名>（<TAG-NAME>）` — 見出しとタグ名
2. 宣言文 — 1 段落で何を禁止 / 強制するか
3. `## 禁止対象` / `## 機能概要` — 箇条書き
4. `## 機械強制` — hook テーブル（hook がない場合は「機械強制なし」と明記）
5. `## 違反検知時の手順` — タグごとの Claude の対応手順
6. `## 設計判断` — ADR 4 項目

paths frontmatter が必要な場合は先頭に追加:

```markdown
---
paths:
  - "**/*.sh"
---
```

## Phase 5: hook script の作成（必要な場合）

hook が必要と判定された場合:

1. `.sh` を rule.md と同じディレクトリに Write
2. shebang は `#!/usr/bin/env bash`
3. `set -euo pipefail`（または `set -u`）
4. stdin から JSON を読み取り、検査対象を抽出
5. 違反検出時は additionalContext にタグ + 検出事実 + rule.md パスを出力
6. block する場合は `exit 2`、warn のみなら `exit 0`
7. `chmod +x` で実行ビットを付与

additionalContext の書き方は `conventions.md` §5 に従う（プロンプト埋め込み禁止）。

## Phase 6: settings.json への登録

hook script を作成した場合、settings.json に登録する。

```bash
# グローバル hook → ~/.claude/settings.json
# プロジェクト hook → <repo>/.claude/settings.json
```

登録の具体手順は `managing-agent-configs（種別: hooks）` の create モードに委任してよい。

## Phase 7: 作成後チェックリスト

| キー | チェック項目 | 確認方法 |
|---|---|---|
| 配置-深さ3 | `<scope>/<topic>/<name>/rule.md` が存在する（`<scope>` は `always`/`scoped`） | `ls` |
| 配置-ルート直下禁止 | ルート直下に `.md` を作っていない | `find ~/.claude/rules/ -maxdepth 1 -name "*.md"` |
| 本文-設計判断 | rule.md に `## 設計判断` がある | `grep "## 設計判断" rule.md` |
| 本文-上書き宣言 | `## プロジェクト上書き` で 3 択（委譲可/一律適用/上書き禁止）を宣言している | `grep "## プロジェクト上書き" rule.md` |
| hook-同居 | hook script があれば同ディレクトリに同居 | `ls <scope>/<topic>/<name>/*.sh` |
| hook-登録 | hook script があれば settings.json に登録済み | `grep "<script-name>" settings.json` |
| hook-短文注入 | additionalContext にプロンプトを埋め込んでいない | hook script を Read して確認 |
| frontmatter-整合 | paths frontmatter が妥当（eager/lazy） | `head -5 rule.md` |
| adr-4項目 | ADR 4 項目（必要性 / 代替案 / 保守責任者 / 廃棄条件）が揃っている | `grep` |

キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

全項目 PASS で create 完了。review モードへ自動連鎖する。
