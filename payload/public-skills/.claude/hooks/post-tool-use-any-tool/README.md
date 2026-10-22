# post-tool-use-any-tool

## 登録

| 項目 | 値 |
|---|---|
| 発火点 | PostToolUse |
| matcher | `*` |
| command | `node $CLAUDE_PROJECT_DIR/.claude/hooks/post-tool-use-any-tool.js` |
| timeout | 60 |

## 検査

| 検査の名前 | 確かめること | 対象のファイルの条件 | 根拠の規約と規則の観点 | 呼ぶもの | 返す kind |
|---|---|---|---|---|---|
| detectUnguidedSkillChange | ツールの後に、テスト計画書を持つスキルのファイルの中身の hash を、前の基準と比べ、変わったファイルごとに、会話の記録に、そのファイルを書き換えてよいスキルを使った跡がある | `skills/tests/<スキルの名前>/テスト計画書.md` を持つスキルの `skills/<スキルの名前>/` の下のファイルと、そのテスト計画書 | 規約 thinking-rule の規則「テストの不合格から、テスト対象のスキルとテスト計画書を直すときは、決まった手順の中でだけ直す」(承認待ち) | `tools/skill-guard/skill-guard.js` | `violation` |

基準は、一時フォルダの `skill-guard-<session_id>.json` に置く。セッションの最初の呼び出しで、そのときの hash を基準にする。跡のある変化は基準に入れ、跡のない変化は基準に入れずに、元に戻るまで毎回知らせる。

## 入力

| 標準入力の鍵 | 使い方 |
|---|---|
| `hook_event_name` | `PostToolUse` であることを確かめる |
| `session_id` | 基準のファイルの名前に使う |
| `transcript_path` | 親の会話の記録から、Skill のツールの呼び出しを探す |
| `agent_id` | サブエージェントの会話の記録のパスを作り、その中から SKILL.md を読んだ跡を探す |

## 出力

| スクリプトが終える場合 | 終了コード | 出力先 | 出力の形 |
|---|---|---|---|
| 標準入力が JSON として読めない | 0 | なし | なし |
| `hook_event_name` が `PostToolUse` 以外 | 0 | なし | なし |
| 結果が 0 件 | 0 | なし | なし |
| `violation` が 1 件以上 | 2 | 標準エラー | まとめた文章 |

## 確かめ方

確かめる人は、同じ `session_id` の見本の標準入力を 2 回流し、その間に守るファイルを 1 行変える。1 回目の終了コードが 0、2 回目の終了コードが 2 で、標準エラーが `detectUnguidedSkillChange` の行と変わったファイルのパスを持つことを確かめる。
