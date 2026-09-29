# {{REPOSITORY_NAME}} 作業案内

## 前半: リポジトリ索引

- 目的: {{REPOSITORY_PURPOSE_FROM_EVIDENCE}}
- 技術スタック: {{TECH_STACK_FROM_MANIFESTS_AND_CONFIG}}
- 実行コマンド: {{VERIFIED_COMMANDS_WITH_SOURCE_PATHS}}
- ディレクトリ構造: {{DIRECTORY_STRUCTURE_WITH_ROOTS}}
- リバース対象: {{REVERSE_TARGETS_FROM_IMPLEMENTATION}}
- 成果物の正本: {{CANONICAL_ARTIFACT_PATHS}}
- 派生物: {{DERIVED_ARTIFACT_PATHS_AND_GENERATORS}}
- 調査入口: {{INVESTIGATION_ENTRY_PATHS}}
- 検証出力先: {{VERIFICATION_OUTPUT_PATHS}}

### 不在の記録

除外・未受領など、対象リポジトリに**存在してはならない**資料は、バッククォート内で `不在: <相対パスまたは文言>` と書く。例: `不在: docs/legacy-spec.md`。この印付きの対象は、共通索引の検査で通常の実在確認から外れ、逆に実在していれば不合格になる。項目名を `/` で連ねた利用者向け文言など、パスではないものを明示的に除外するときにも同じ印を使う。

## 後半: 規約の読み込み

下のマーカーに挟まれた範囲が規約索引であり、直接編集しない。

<!-- RULES-INDEX:START -->
## 規約
規約は `docs/rules/<分類>/<規約>/rule.md` にある。適用範囲は各ファイルの front matter（`paths` / `alwaysApply`）が示す。
`.claude/rules` は `docs/rules` へのシンボリックリンク、`.cursor/rules/*.mdc` は同じファイルの拡張子違いのコピーであり、どちらも直接編集しない。
<!-- RULES-INDEX:END -->

### 未確定事項

規約ルートが見つからない・パスが解決できないといった構造的な未確定だけを書く。

- {{UNCONFIRMED_RULE_OR_MISSING_EVIDENCE}}
