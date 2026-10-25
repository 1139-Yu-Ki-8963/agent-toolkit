# pre-tool-use-write-file

## 登録

| 項目 | 値 |
|---|---|
| 発火点 | PreToolUse |
| matcher | `Edit\|Write\|NotebookEdit` |
| command | `node $CLAUDE_PROJECT_DIR/.claude/hooks/pre-tool-use-write-file.js` |
| timeout | 60 |

## 検査

| 検査の名前 | 確かめること | 対象のファイルの条件 | 根拠の規約と規則の観点 | 呼ぶもの | 返す kind | テスト |
|---|---|---|---|---|---|---|
| blockUnguidedSkillWrite | 書き込む先がテスト計画書を持つスキルのファイルのとき、会話の記録に、そのファイルを書き換えてよいスキルを使った跡がある | `skills/tests/<スキルの名前>/テスト計画書.md` を持つスキルの `skills/<スキルの名前>/` の下のファイルと、そのテスト計画書 | 規約 thinking-rule の規則「テストの不合格から、テスト対象のスキルとテスト計画書を直すときは、決まった手順の中でだけ直す」 | `hooks/pre-tool-use-write-file/skill-guard.js` | `violation` | 「blockUnguidedSkillWrite: 結果を返す」と「blockUnguidedSkillWrite: 結果を返さない」 |

## 入力

| 標準入力の鍵 | 使い方 |
|---|---|
| `hook_event_name` | `PreToolUse` であることを確かめる |
| `tool_input.file_path` | 書き込む先のファイルの判定に使う |
| `tool_input.notebook_path` | NotebookEdit の書き込む先のファイルの判定に使う |
| `transcript_path` | 親の会話の記録から、Skill のツールの呼び出しを探す |
| `agent_id` | サブエージェントの会話の記録のパスを作り、その中から SKILL.md を読んだ跡を探す |

## 出力

| スクリプトが終える場合 | 終了コード | 出力先 | 出力の形 |
|---|---|---|---|
| 標準入力が JSON として読めない | 0 | なし | なし |
| `hook_event_name` が `PreToolUse` 以外 | 0 | なし | なし |
| 結果が 0 件 | 0 | なし | なし |
| `violation` が 1 件以上 | 2 | 標準エラー | まとめた文章 |

## 確かめ方

確かめる人は、`node --test hooks/pre-tool-use-write-file/pre-tool-use-write-file.test.js` を実行し、すべてのテストが合格することを確かめる。
