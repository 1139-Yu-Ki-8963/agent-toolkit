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
| checkHookRequires | スクリプトの `require` の相対パスが、すべて `hooks/` の下を指す | `hooks/` の下の `.js` | 規約 hook-writing-rule の規則「hooks/ の中のどこに置くか」 | なし | `violation` |
| requestRuleCheck | 変えたファイルに当たる規約のパスの一覧を作り、書く作業を終えたあとに、その一覧で別の照合者に照合させて直すことを AI に頼む | `.md` | 規約 thinking-rule の規則「AI は、規約に沿って文書を書く作業を、書いた AI とは別の照合が出したすべての指摘が直した状態か一覧に入った状態になったときに終える」 | request-rule-check.md | `prompt` |

検査 requestRuleCheck が作る規約のパスの一覧は、次の 2 つを持つ。

- `rules/text-writing/text-writing-rule.md`。すべての `.md` に当たる。
- `rules/` の下の `.md` のうち、ファイルの先頭の設定欄の `paths` に、変えたファイルのパスに当たる値を持つもの。フォルダの名前に `-completed-example` を含む完成例は、一覧に入れない。

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

確かめる人は、`echo '{"hook_event_name":"PostToolUse","tool_input":{"file_path":"<プロジェクトのパス>/rules/text-writing/text-writing-rule.md"}}' | node <プロジェクトのパス>/hooks/post-tool-use-write-file.js` を実行し、終了コードが 0 で、標準出力の JSON の `hookSpecificOutput.additionalContext` が、見出しの行「点検の依頼」と、検査 remindPinkElephants と requestRuleCheck の `source` の行と `text` の行を持ち、requestRuleCheck の `text` の規約のパスの一覧が `rules/text-writing/text-writing-rule.md` と `rules/rule-writing/rule-writing-rule.md` の 2 行であることを確かめる。

## 点検の依頼の文

| ファイル | そのファイルを渡す検査 |
|---|---|
| remind-pink-elephants.md | remindPinkElephants |
| request-rule-check.md | requestRuleCheck |
