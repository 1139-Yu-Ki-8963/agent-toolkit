# 拡張ポイント一覧

配備先・プロジェクトが追記できる受け口ファイルの索引。各規約ファイルの「プロジェクト上書き」節が定義元であり、本ファイルは索引のみを担当する。

| 受け口ファイル | 書式 | 記入例 | 未記入時の挙動 |
|---|---|---|---|
| `<repo>/.claude/rules/always/review-checklist/text-dictionary/prh.yml` | prh YAML | `- expected: 実行する\n  pattern: /エグゼキュート/` | グローバル辞書のみ適用 |
| `<repo>/.claude/rules/always/naming/commit-branch/naming-values.txt` | テキスト（prefix 対応表） | `feature: 【機能追加】` | グローバル命名規約を適用 |
| `<repo>/.claude/rules/always/project-context/flow-values.yml` | YAML（開発フロー設定） | `test_conventions: vitest` | orchestrating-dev-flow の Phase ゲートで block |
| `<repo>/.claude/rules/always/project-context/rule.md` | Markdown（プロジェクト概要） | 技術スタック・許可ディレクトリ | mkdir 時に許可リスト照合不可 |
