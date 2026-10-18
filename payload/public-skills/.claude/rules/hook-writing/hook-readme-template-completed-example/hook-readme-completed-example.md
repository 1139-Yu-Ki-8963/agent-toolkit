---
paths:
  - .claude/skills/**/*
  - .claude/rules/hook-writing/**/*
---

# post-tool-use-write-file

## 登録

| 項目 | 値 |
|---|---|
| 発火点 | PostToolUse |
| matcher | `Edit\|Write` |
| command | `node <プロジェクトのパス>/hooks/post-tool-use-write-file.js` |
| timeout | 60 |

## 検査

| 検査の名前 | 確かめること | 対象のファイルの条件 | 根拠の規約と規則の観点 | 呼ぶもの | 返す kind |
|---|---|---|---|---|---|
| remindPinkElephants | 変えた規約の文が、ピンクの象を除く書き直しとユーザーの承認を経ているかの点検を AI に頼む | `rules/` の下の `.md` | 規約 rule-writing-rule の規則「規約を足す、直す、消す、分ける、まとめるときに守ること」 | remind-pink-elephants.md | `prompt` |
| checkLinks | ファイルの中の相対パスのリンク先が存在する | `.md` | なし | なし | `violation` |
| remindTextWritingRule | 変えたファイルの文が、規約 text-writing-rule のすべての規則を満たすかの点検を AI に頼む | `.md` | 規約 text-writing-rule のすべての規則 | remind-text-writing-rule.md | `prompt` |

## 入力

| 標準入力の鍵 | 使い方 |
|---|---|
| `hook_event_name` | `PostToolUse` であることを確かめる |
| `tool_input.file_path` | 対象のファイルの条件の判定と、全文の読み込みに使う |

## 出力

| スクリプトが終える場合 | 終了コード | 出力先 | 出力の形 |
|---|---|---|---|
| 標準入力が JSON として読めない | 0 | なし | なし |
| `hook_event_name` が `PostToolUse` 以外 | 0 | なし | なし |
| 結果が 0 件 | 0 | なし | なし |
| `violation` が 1 件以上 | 2 | 標準エラー | まとめた文章 |
| `prompt` だけ | 0 | 標準出力 | `hookSpecificOutput.additionalContext` にまとめた文章を入れた JSON |

## 確かめ方

確かめる人は、`echo '{"hook_event_name":"PostToolUse","tool_input":{"file_path":"<プロジェクトのパス>/rules/text-writing/text-writing-rule.md"}}' | node <プロジェクトのパス>/hooks/post-tool-use-write-file.js` を実行し、終了コードが 0 で、標準出力の JSON の `hookSpecificOutput.additionalContext` が、見出しの行「点検の依頼」と、検査 remindPinkElephants と remindTextWritingRule の `source` の行と `text` の行を持つことを確かめる。

## 点検の依頼の文

| ファイル | そのファイルを渡す検査 |
|---|---|
| remind-pink-elephants.md | remindPinkElephants |
| remind-text-writing-rule.md | remindTextWritingRule |
