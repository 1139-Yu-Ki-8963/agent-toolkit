# post-tool-use-any-tool

## 設定のファイルへの登録

| 項目 | 値 |
|---|---|
| 発火点 | PostToolUse |
| matcher | `*` |
| command | `node "$CLAUDE_PROJECT_DIR/.claude/hooks/post-tool-use-any-tool.js"` |
| timeout | 60 |

## スクリプトがする検査

| 検査の名前 | 確かめること | 対象のファイルの条件 | 根拠の規約と規則の観点 | 使うコマンドとファイル | 返す結果の種類(`kind`) | テスト |
|---|---|---|---|---|---|---|
| detectUnguidedSkillChange | ツールの後に、テスト計画書を持つスキルのファイルの中身の hash を、基準(セッションの最初の呼び出しのときの hash に、跡のある変化を足したもの)と比べ、変わったファイルごとに、会話の記録に、そのファイルを書き換えてよいスキルを使った跡がある | `skills/tests/<スキルの名前>/テスト計画書.md` を持つスキルの `skills/<スキルの名前>/` の下のファイルと、そのテスト計画書。作業フォルダの `output/<スキルの名前>/tests/テスト計画書.md` を持つスキルの `output/<スキルの名前>/` の下のファイル(直下の `tests/`、`ui/`、`要件定義書.md`、`分割設計書.md`、`構成の案.md`、`依頼の一覧.md` を除く)と、そのテスト計画書 | 規約 thinking-rule の規則「テストの不合格から、テスト対象のスキルとテスト計画書を直すときは、決まった手順の中でだけ直す」 | `hooks/pre-tool-use-write-file/skill-guard.js` | `violation` | 「detectUnguidedSkillChange: 結果を返す」と「detectUnguidedSkillChange: 結果を返さない」 |
| checkStateContract | Write か Edit で書いた画面の状態のファイルが JSON として読め、その値の組が、画面の状態のファイルのインターフェース設計書の章 2 の 2 つの表(段階 1 の聞き取りの画面と、段階 2 から 8 の画面)と章 3 の聞き返しの形に合い、段階 2 から 8 で足すキーの値が型に合う | `ui/state.json` で終わるパス | 規約 skill-making-flow の規則「確認と承認の画面を使うときに AI が足す動作」 | `ui/tests/lib/state-contract.mjs`(プロジェクトのフォルダの下) | `violation` | 「checkStateContract: 結果を返す」と「checkStateContract: 結果を返さない」と「checkStateContract: 段階 2 から 8 の画面で結果を返す」と「checkStateContract: 段階 2 から 8 の画面で結果を返さない」 |

## 入力

| 標準入力の JSON の項目 | 使い方 |
|---|---|
| `hook_event_name` | `PostToolUse` であることを確かめる |
| `session_id` | 基準を置く一時フォルダのファイル `skill-guard-<session_id>.json` の名前に使う |
| `transcript_path` | 親の会話の記録から、Skill のツールの呼び出しを探す |
| `agent_id` | サブエージェントの会話の記録のパスを作り、その中から SKILL.md を読んだ跡を探す |
| `tool_name` | 検査 checkStateContract で、Write か Edit であることを確かめる |
| `tool_input.file_path` | 検査 checkStateContract で、対象のファイルの条件の判定と、全文の読み込みに使う |

## 出力

| スクリプトが終わる場合 | 終了コード | 出力先 | 出力の形 |
|---|---|---|---|
| 標準入力が JSON として読めない | 0 | なし | なし |
| `hook_event_name` が `PostToolUse` 以外 | 0 | なし | なし |
| 結果が 0 件 | 0 | なし | なし |
| `violation` が 1 件以上 | 2 | 標準エラー | まとめた文章 |

## スクリプトの動作の確かめ方

確かめる人は、`node --test hooks/post-tool-use-any-tool/post-tool-use-any-tool.test.js` を実行し、すべてのテストが合格することを確かめる。
