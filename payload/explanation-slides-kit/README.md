# explanation-slides-kit

与えたトピックを図解入り横1枚（16:9）のスライド風解説HTMLに変換する `generating-explanation-html-slides` スキルと、生成物の品質を担保する品質コンテキストの最小セットを同梱した自己完結型キット。

## 導入手順

`skills/generating-explanation-html-slides/` フォルダを `~/.claude/skills/` にコピーする。

```bash
cp -r skills/generating-explanation-html-slides ~/.claude/skills/
```

以降は Claude Code のスキル起動条件（SKILL.md の description）に従い、「解説スライドを作って」等の依頼で自動的に呼び出される。

## references/ 内の各ファイルの役割

| ファイル | 役割 |
|---|---|
| `slide-template.html` | デザイントークン・部品カタログ（生成の正本） |
| `slide-review-checklist.md` | 観点レビュー表（合格判定の正本） |
| `business-content-standards.md` | ビジネス提示資料の内容品質基準（メッセージ設計・論理構造・数値信頼性・読み手適合・提案の質・表現の品位の6カテゴリ23観点） |
| `html-output-standards.md` | 単一HTML成果物の合格基準（被覆・図解・自己完結等） |
| `text-dictionary.md` | 文章語彙の設計原則（prh 辞書の考え方） |
| `prh.yml` | 置き換え辞書本体（textlint の prh プラグイン向け設定） |
| `meaningful-key-naming.md` | 意味語キー命名の原則（スライドキーの連番禁止） |
| `customer-output-checklist.md` | 顧客提示前チェック（内部情報の混入防止） |

## 前提条件

- **Playwright MCP**（または同等のブラウザ自動操作ツール）: Phase 4 の実描画検証に必須。コードレビューのみでの合格判定は禁止されている（文字切れ・重なりは実描画でしか発見できない）
- **textlint**: 任意。導入済みなら `text-dictionary.md` の原則と `prh.yml` を使って蓄積簿更新時に自動検査できる

### textlint がない場合

`references/prh.yml` を目視で参照し、語彙（カタカナビジネス用語・英語バズワード等）が置き換え候補に該当していないかを手動で確認する。
