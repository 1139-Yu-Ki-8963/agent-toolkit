# Rule テスト手順（testing）

`managing-agent-configs`（種別: rules） の **test モード** が参照する手順書。`conventions.md` を前段で読んだ前提で、hook script の実機発火検証を実行する。

## 原則

- テストは **必ず新規サブエージェント** で実行する。セルフ再読は禁止（バイアスが入る）
- hook script がないルール（rule.md のみ）はテスト対象外。「機械強制なし」と報告して終了
- 破壊的操作（rm / git push --force 等）を block する hook のテストでは、**安全なダミーコマンド** を使う

## Phase 1: テスト対象の特定

```bash
# hook script を持つ rules を列挙
for d in ~/.claude/rules/always/*/*/ ~/.claude/rules/scoped/*/*/; do
  [ -d "$d" ] || continue
  sh_count=$(find "$d" -name "*.sh" -not -name "*.test.sh" | wc -l | tr -d ' ')
  [ "$sh_count" -gt 0 ] && echo "$(basename $d)  hooks=$sh_count"
done
```

## Phase 2: テストケースの設計

各 hook script について以下の 2 種類のテストケースを設計する。

### 正ケース（発火すべき）

hook が検出すべきパターンを含む入力を作成する。

| hook のタイミング | テスト方法 |
|---|---|
| PreToolUse(Bash) | 違反パターンを含むコマンドを Bash ツールで実行 |
| PreToolUse(Write\|Edit) | 違反パターンを含むファイルパスで Write を試行 |
| PostToolUse(Write\|Edit) | 違反パターンを含むファイルを Write し、hook の出力を確認 |
| Stop | 違反パターンを含む応答を生成し、hook の出力を確認 |
| UserPromptSubmit | テスト不可（ユーザー入力が必要）。スキップ |

### 負ケース（発火しないべき）

hook が検出しないはずのパターンを含む入力を作成する。

例:
- `no-root-marker-check.sh` が `/tmp/claude-hooks/` への touch を block しないこと
- `hooks-architecture-check.sh` が既存ファイルの Edit を block しないこと

## Phase 3: サブエージェントによる実機検証

```
Agent(subagent_type: "worker-haiku", prompt: """
以下の hook script のテストを実行する。

テスト対象: <script path>
正ケース: <違反パターンのコマンド>
負ケース: <正常パターンのコマンド>

1. 正ケースを実行し、hook が発火して block / warn することを確認
2. 負ケースを実行し、hook が発火しないことを確認
3. 結果を以下のフォーマットで報告:

正ケース: PASS / FAIL（発火した / しなかった）
負ケース: PASS / FAIL（発火しなかった / した）
hook 出力: <additionalContext の内容>
""")
```

既存の `.test.sh` がある場合はそれを実行する:

```bash
for test_sh in ~/.claude/rules/{always,scoped}/*/*/*.test.sh; do
  [ -f "$test_sh" ] || continue
  echo "=== $(basename $test_sh) ==="
  bash "$test_sh" 2>&1
done
```

## Phase 4: 検証レポート

```
## managing-agent-configs（種別: rules） test レポート

### 対象: <scope>/<topic>/<name>/
| テスト | 種類 | 結果 | hook 出力 |
|---|---|---|---|
| 違反コマンド実行 | 正ケース | PASS | [TAG] ... |
| 正常コマンド実行 | 負ケース | PASS | （発火なし） |

### 判定: 全 PASS / N 件 FAIL
```

## 失敗パターン台帳

| 失敗パターン | 原因 | 対処 |
|---|---|---|
| 正ケースで発火しない | 正規表現パターンの不一致 | `.sh` の PATTERN を修正 |
| 負ケースで発火する | パターンが広すぎる | 例外条件を追加 |
| hook が JSON parse error | jq への入力が不正 | stdin の読み取り方を修正 |
| hook が timeout | 処理が重い / 無限ループ | timeout 値を確認 / ロジック簡素化 |
| exit code が期待と異なる | block すべきなのに exit 0 | exit 2 に修正 |
| additionalContext が空 | jq の出力組み立てエラー | jq 式を修正 |
