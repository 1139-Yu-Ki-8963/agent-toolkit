# Claude Code 設定 — 運用マニュアル

## やりたいこと → 使うもの

| やりたいこと | 使うもの |
|---|---|
| コードレビュー | `/code-review`（Claude Code 標準） |
| セキュリティレビュー | `/security-review`（Claude Code 標準） |
| PR レビュー | `/review`（Claude Code 標準） |
| プロジェクト適応 | `/adapt`（テンプレ独自） |
| 確認つきコミット | `/safe-commit`（テンプレ独自） |
| 普段の依頼 | 日本語でそのまま |

## セットアップ

### チーム（代表者 1 回）

1. テンプレート導入済みのファイルを commit する
2. `/adapt` を実行してプロジェクトに適応させる
3. 適応結果を commit する

### 個人

1. `cp .claude/settings.local.json.example .claude/settings.local.json` — 個人設定
2. `cp CLAUDE.local.md.example CLAUDE.local.md` — 個人用 Agent Guidelines
3. hooks は個人設定に書かない（加算マージで二重実行になる）

## 導入後チェックリスト

- [ ] hook エラーなし確認（Claude Code 起動時にエラーが出ないこと）
- [ ] `/hooks` で 2 本が Project ソースで見えること
- [ ] `node --test .claude/hooks/tests/guard.test.mjs` が通ること
- [ ] カナリアテスト: `.env` の読み取りを依頼して拒否されること
- [ ] session-start のスモークテスト: `echo '{"source":"startup"}' | node .claude/hooks/session-start.mjs` — 適応前は JSON 1 行出力、適応後は無出力

## hooks の構成と限界

- **fail-open**: エラー時は素通しする。hook が壊れてもツール実行は止まらない
- **主は permissions.deny**: hook は Bash/PowerShell 経由のアクセスを補完する従の層
- **文字列マッチの限界**: 意図的なバイパスは防げない。事故防止装置として機能する
- **project 設定は紳士協定**: プロジェクトメンバーは自分で無効化できる。強制は managed settings で
- **PreToolUse の遅延**: ツール呼び出しごとに node を起動するため 50〜150ms の遅延がある

## トラブルシュート

| 症状 | 対処 |
|---|---|
| hook error | Node.js 18 以上を確認。起動場所がプロジェクトルートか確認 |
| 一時的に切りたい | `disableAllHooks` は全ガードが消えることを理解した上で使う |
| 二重実行 | `~/.claude/settings.json` に同種の hook がないか確認（加算マージ） |
| rules が効かない | frontmatter の `paths` glob がマッチするか確認 |
| /adapt が止まった | ヘッドレス不可。対話セッションで再開する |
| settings.json を壊した | `node -e "JSON.parse(...)"` で位置特定。壊れている間は deny も無効なので最優先で直す |

## 運用上の推奨

- CODEOWNERS で `hooks/` と `settings.json` をレビュー必須にする
- 常時適用の rules は 50 行以内に収める
- `.mcp.json` のトークンは `${ENV_VAR}` 展開を使い、直書きしない
- `enableAllProjectMcpServers` は使わない
