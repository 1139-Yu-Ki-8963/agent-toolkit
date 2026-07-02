# agent-toolkit

Claude Code のスキルを「ライフサイクル」として管理する meta スキル集。詳細は [README.md](README.md) を参照。

## 本リポジトリ内で作業する時の hook 設定

`skills/managing-agent-configs/scripts/` に、managed ファイル（`skills/*/SKILL.md` 等）の編集を検知して
自動的にレビュー・テストへ誘導し、未テストの `git commit` を block する hook 2 本が同梱されている。

本リポジトリ直下の `.claude/settings.json` に、この 2 本を **登録済み** で同梱している。
clone してこのリポジトリ自体を編集する分には追加設定は不要（`$CLAUDE_PROJECT_DIR` でパス解決するため、
clone 先のパスによらずそのまま動く）。

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          { "type": "command", "command": "$CLAUDE_PROJECT_DIR/skills/managing-agent-configs/scripts/managing-review-gate.sh" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "$CLAUDE_PROJECT_DIR/skills/managing-agent-configs/scripts/managing-commit-gate.sh" }
        ]
      }
    ]
  }
}
```

## 他プロジェクトへ managing-agent-configs だけをインストールする場合

`.claude/settings.json` はこのリポジトリ専用（`$CLAUDE_PROJECT_DIR` がこのリポジトリのルートを指す前提）なので、
スキルだけを別プロジェクトや `~/.claude/skills/` へコピーする場合はそのまま流用できない。
インストール先の `~/.claude/settings.json`（グローバル）または `<repo>/.claude/settings.json`（プロジェクト）に、
スキルを配置したパスへ書き換えたうえで同じ2本を登録する。手順は README.md の「機械強制フック（任意）」節を参照。

## 設計判断

**必要性**: hook script（`scripts/managing-review-gate.sh` / `managing-commit-gate.sh`）を同梱しても、
`settings.json` への登録手順がリポジトリ内に実体として無いと「同梱されているが動かない」状態になる。
`$CLAUDE_PROJECT_DIR` を使った settings.json をこのリポジトリ自体に同梱することで、clone した時点で
このリポジトリ内の作業に対しては即座に機械強制が有効になる（動作確認済みの設定を配布物として持たせる）。

**代替案を採用しなかった理由**:
- README にコピペ用 JSON だけ書く（settings.json 実体は同梱しない）: 「このリポジトリ自身の開発」に対して
  機械強制が効かず、動作未検証のスニペットをコピペさせるだけになる
- 絶対パスで settings.json を書く: clone 先のディレクトリ名・場所に依存し、他人の環境で壊れる

**保守責任者**: 人手（ユーザー）。`scripts/` 配下の hook ファイル名・配置を変更した場合は本ファイルと
`.claude/settings.json` を同時に更新する。

**廃棄条件**: `managing-agent-configs` の hook 連携方式が変わった時、または本リポジトリ自体の開発を
別リポジトリ・別ツールに移行した時。
