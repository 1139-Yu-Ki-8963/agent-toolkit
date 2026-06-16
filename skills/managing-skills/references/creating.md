# スキル作成手順（creating）

`managing-skills` の **create モード** が参照する手順書。`conventions.md` を前段で読んだ前提で、実際の新規スキル作成の流れと作成後チェックリストを定義する。

このファイルを読み終えたら、新規スキルの SKILL.md を Write し、作成後チェックリストを実行する。完了したら **自動的に review モード → test モード** へ連鎖する（ハブ SKILL.md の指示に従う）。

## 使用タイミング

以下の場面で create モードが発動:
- 「スキルを作成」「新しいスキルを作る」と言われた時
- 「SKILL.md を作成」と指示された時
- スキルの設計・構成を相談された時
- 既存スキルの改善・リファクタリング時（改善でも全フローを通す）

## 推奨手順

### 0. 文字数予算を守る（最優先）

`conventions.md` の「3. 文字数予算」セクションを参照。description の説明文は 50 字以内、全スキル合計 2,000 文字以内。新規追加前に合計確認コマンドを実行する。

### 1. description を具体的に書く
- `TRIGGER when:` と `SKIP:` の固定キーワードを使う
- 発動条件は具体的なキーワード・操作名を列挙する
- 詳細例は `description-examples.md` を参照

### 2. 焦点を絞る
各スキルは 1 つの機能に特化（1 スキル = 1 機能）。複数責務を詰め込まない。

### 3. トークン制限を守る
- SKILL.md 本体は 500 行 / 5,000 トークン以下
- 詳細は `references/` に分離

### 4. 簡潔な例を優先
長い説明より、1 つの良い例が効果的。

### 5. 複数の小さなスキル
1 つの大きなスキルより効果的。

### 6. references/ の正しい使い方
- ✅ **置くべき**: そのスキル固有の詳細情報（パターン集、例、トラブルシューティング）
- ❌ **置いてはいけない**: 公式ドキュメントのコピー、汎用的な情報
- 公式ドキュメントは参照リンクで済ませる

### 7. 重複を避ける
- 公式ドキュメントはコピーせず参照
- 汎用的な情報は `/docs/` に配置
- スキル固有の情報のみ `references/` に配置

### 8. Type を決定木で 1 つに絞る
`conventions.md` の「4. Type 9 種類（決定木）」を参照。`type:` を frontmatter に明記。

### 9. allowed-tools を最小セットで宣言
`conventions.md` の「5. allowed-tools 型別最小セット」を参照。

## 作成前チェックリスト

- [ ] description の説明文（TRIGGER 行より前）が **50 字以内** か（超過時は TRIGGER when の例示を絞る）
- [ ] 追加後も全スキル合計が **2,000 文字以内** か（確認コマンドで計測）
- [ ] description に `TRIGGER when:` が含まれ、発動条件が具体的
- [ ] description に `SKIP:` が含まれ、非発動条件が明記されている
- [ ] `invocation` が `name` と同値になっている
- [ ] `type` を 9 種類（orchestration / gateway / gate / audit / verification / reactive / reference / transform / action）から 1 つ宣言したか
- [ ] `allowed-tools` を型の最小セットで記載したか
- [ ] `## Gotchas` セクションがあるか（1 行でも可）
- [ ] SKILL.md 本体が 500 行以下
- [ ] セクション名が日本語で統一
- [ ] フォルダ構成が適切（`folder-structure.md` 参照）
- [ ] `references/` に公式ドキュメントのコピーがない
- [ ] `references/` はスキル固有の内容のみ

## 作成後チェックリスト（必須）

- [ ] `~/.claude/skills/README.md` の「スキル一覧」に新スキルの `<details>` エントリを追加した
  - 適切なカテゴリセクションに配置（なければ新規セクションを作成）
  - summary: `<code>スキル名</code> — 一行説明`
  - 本文: 使用タイミング・主要機能を箇条書きで記載
- [ ] アンチパターンを踏んでいないか `anti-patterns.md` で確認した
- [ ] **review モードへ自動連鎖**（managing-skills ハブが制御）
- [ ] **test モードへ自動連鎖**（review 完了後）

## Gotchas

- 作成しただけで終わらせない: ハブが自動で review → test へ連鎖する。連鎖を止めるのはユーザー明示時のみ
- 文字数予算は「全合計」で見る: 新規追加で予算超過するなら、既存スキルの description 圧縮も同時に提案する
- Type は本文と整合させる: frontmatter で `reference` 宣言したのに Phase/Step で順序強制している、のような乖離は review の A9 で検出される

## 参照資料

### このスキルの詳細情報

- 共通規約: `conventions.md`
- フォルダ構成の推奨手順: `folder-structure.md`
- description の書き方詳細例: `description-examples.md`
- アンチパターン集: `anti-patterns.md`
- 高度なテクニック: `advanced-techniques.md`

### 型別テンプレート

テンプレートは 3 分類（手順型 / 条件付き知識型 / 強制型）を 9 Type 分類にマップして用意している:

- 手順型（`assets/template-手順型.md`）→ orchestration / action / gateway / transform
- 条件付き知識型（`assets/template-条件付き知識型.md`）→ reference
- 強制型（`assets/template-強制型.md`）→ reactive / gate / audit / verification

### 公式ドキュメント

- Claude Skills の全体仕様: `/docs/skills.md`
