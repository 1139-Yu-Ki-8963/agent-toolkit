# post-tool-use-any-tool

## 登録

| 項目 | 値 |
|---|---|
| 発火点 | PostToolUse |
| matcher | `*` |
| command | `node $CLAUDE_PROJECT_DIR/.claude/hooks/post-tool-use-any-tool.js` |
| timeout | 60 |

## 検査

| 検査の名前 | 確かめること | 対象のファイルの条件 | 根拠の規約と規則の観点 | 呼ぶもの | 返す kind | テスト |
|---|---|---|---|---|---|---|
| detectUnguidedSkillChange | ツールの後に、テスト計画書を持つスキルのファイルの中身の hash を、前の基準と比べ、変わったファイルごとに、会話の記録に、そのファイルを書き換えてよいスキルを使った跡がある | `skills/tests/<スキルの名前>/テスト計画書.md` を持つスキルの `skills/<スキルの名前>/` の下のファイルと、そのテスト計画書。作業フォルダの `output/<スキルの名前>/tests/テスト計画書.md` を持つスキルの `output/<スキルの名前>/` の下のファイル(直下の `tests/`、`要件定義書.md`、`分割設計書.md`、`構成の案.md`、`依頼の一覧.md` を除く)と、そのテスト計画書 | 規約 thinking-rule の規則「テストの不合格から、テスト対象のスキルとテスト計画書を直すときは、決まった手順の中でだけ直す」 | `hooks/pre-tool-use-write-file/skill-guard.js` | `violation` | 「detectUnguidedSkillChange: 結果を返す」と「detectUnguidedSkillChange: 結果を返さない」 |

検査 detectUnguidedSkillChange は、基準を一時フォルダの `skill-guard-<session_id>.json` に置く。検査 detectUnguidedSkillChange は、セッションの最初の呼び出しで、そのときの hash を基準にする。検査 detectUnguidedSkillChange は、跡のある変化を基準に入れ、跡のない変化を、元に戻るまで毎回 AI に知らせる。

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

確かめる人は、`node --test hooks/post-tool-use-any-tool/post-tool-use-any-tool.test.js` を実行し、すべてのテストが合格することを確かめる。
