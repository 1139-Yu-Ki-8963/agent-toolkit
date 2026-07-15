# 文章置き換え辞書規約（TEXT-DICTIONARY）

prh 辞書（textlint の置き換え語彙定義。カタカナビジネス用語・英語バズワードを平易な日本語へ置き換えるルール集）を定義する規約である。

## 規約の要点

- prh 辞書の定義は同ディレクトリの `prh.yml`（非注入サイドカー）に置く
- 語彙の登録フロー（重複チェック → 追記 → 既存箇所への置換適用）・対象外パターンは `~/agent-home/skills/adding-textlint-dictionary-terms/SKILL.md`（辞書への新規語彙登録専用スキル）を参照する。既存エントリでの修正はスキルを介さず本ファイルの違反時手順で完結する
- 実行エンジン（textlint 本体・各種 `.textlintrc*`）は `~/agent-home/tools/linter/` に置く。本規約は語彙の定義のみを担当し、実行エンジンの配置・依存パッケージ管理は担当しない

## 辞書の設計原則

辞書は以下 4 原則の検出網であり、原則自体が正。新しい語の可否は原則で判定し、頻出・再発するものだけを辞書に追加する。

1. **読み手第一**: 初見の読み手が意味を取れない語（カタカナ音写・英字略語）を説明なしで使わない
2. **比喩の借用禁止**: 分野外の比喩・借用語で機能を命名しない（例: ゲート・プリフライト・ロスター）
3. **番号に意味を負わせない**: 優先度は日本語で明示し、ステップ番号は 1 始まりの整数とする
4. **正式名称主義**: ドメインの正式名称だけを使い、同義語を発明しない。プロジェクト固有名はプロジェクト辞書（委譲受け口）に登録する

### 併用する textlint ルール（docs 向け・`.textlintrc.json`）

prh（本辞書）は語彙の置き換えを担当し、以下の textlint ルールが文体・構造面を補完する。PR/issue/コメントには適用しない（prh のみ）。

| ルール名 | 意味 |
|---|---|
| `sentence-length` | 1 文は 100 字以内 |
| `max-ten` | 1 文の読点「、」は 3 個まで |
| `max-kanji-continuous-len` | 漢字の連続は 7 文字以内 |
| `ja-no-successive-word` | 同じ単語を連続させない |
| `ja-no-redundant-expression` | 冗長表現（「〜することができます」等）を簡潔にする |
| `ja-hiragana-keishikimeishi` | 形式名詞はひらがな（「〜する事」→「〜すること」） |
| `ja-no-abusage` | よくある誤用パターンの自動検出 |
| `no-doubled-joshi` | 同じ助詞の近距離重複を禁止（「は」のみ許可） |

`no-mix-dearu-desumasu`（文体統一）・`ja-no-mixed-period`（句点統一）・`@textlint-ja/preset-ai-writing` は誤検知が多いため無効化している。設定ファイルの定義は `~/agent-home/tools/linter/.textlintrc.json`。

## 機械強制

| timing | スクリプト | 注入タグ | 挙動 |
|---|---|---|---|
| PreToolUse(Bash) | `always/infra/pre-bash-dispatch/dispatch-pre-bash-checks.sh` | `[TEXTLINT-BLOCK]` | docs 追加行・PR/issue 本文の辞書違反を exit 2 で block |
| PreToolUse(Bash) | 同上 | `[TEXTLINT-ADVISORY]` | コメント本文（`gh pr comment` / `gh issue comment`）の違反を通知のみ（block なし） |
| PostToolUse(Write\|Edit\|MultiEdit) | `always/agent-config/review/check-managing-configs-review-needed.sh` | `[MANAGING-REVIEW-REQUIRED]` | `prh.yml` 編集を検知し、種別 rules での `managing-agent-configs` レビュー・テストを促す |

## 違反検知時の手順

### `[TEXTLINT-BLOCK]` 受信

1. additionalContext に列挙された指摘語・ルール名を確認し、`~/.claude/rules/always/review-checklist/text-dictionary/prh.yml` の該当エントリの `expected:` 値（推奨置き換え語）へ直接置換する。この修正はルール側で完結し、スキル呼び出しは不要
2. 辞書に該当エントリが存在しない新規違反の場合のみ `Skill("adding-textlint-dictionary-terms")` の登録フロー（重複チェック → `prh.yml` への追記 → 既存箇所への置換適用）で辞書へ追加してから置換する

### `[MANAGING-REVIEW-REQUIRED]` 受信

`~/.claude/rules/always/agent-config/review/rule.md` の手順に従い、種別 `rules` で `managing-agent-configs` を実行してテスト完了する。

## プロジェクト上書き

- 上書き可否: 委譲可（値のみ・**追加のみ**）
- 受け口: `<repo>/.claude/rules/always/review-checklist/text-dictionary/prh.yml`
- 優先順位: 受け口が存在すれば、hook はグローバル辞書と受け口の語彙を**合成**して lint する。グローバル語彙の無効化・上書きは不可。枠組み（プリセット構成・block/advisory の区別・違反時手順）はグローバルが常に正

設計判断・経緯の記録は同ディレクトリの `design-notes.txt` を参照（非注入サイドカー）。

## 関連

- `~/agent-home/skills/adding-textlint-dictionary-terms/SKILL.md` — prh.yml への新規語彙登録フロー専用（既存エントリでの修正は本ファイルが完結し、スキルへの委任なし）
- `~/.claude/rules/always/infra/pre-bash-dispatch/rule.md` — `[TEXTLINT-BLOCK]` / `[TEXTLINT-ADVISORY]` の発火元
- `~/.claude/rules/always/agent-config/review/rule.md` — `prh.yml` 編集時のレビュー・テスト強制
