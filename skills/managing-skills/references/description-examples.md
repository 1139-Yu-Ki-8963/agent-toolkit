# description の書き方詳細例

スキルの `description` フィールドは自動発動のトリガーとなる最重要項目です。
ここでは、効果的な description の書き方を詳細な例とともに解説します。

---

## 基本原則

**必須要素**: 「何をするのか」+「いつ使うのか」の両方を含める

```yaml
# 構造
description: [何をするのか] + [いつ使うのか/トリガー条件]
```

---

## description の構造（固定フォーマット）

`description` は以下の3要素で構成する。`TRIGGER when:` と `SKIP:` は
**システムが解析する固定英語キーワード**であり、表記を変えてはならない。

```yaml
description: |
  [何をするのか（1行）]
  TRIGGER when: [発動する状況・キーワード群]
  SKIP: [発動しない状況]
```

| キーワード | 役割 | 変更可否 |
|-----------|------|---------|
| `TRIGGER when:` | スキルを自動発動する条件 | **変更不可** |
| `SKIP:` | 発動しない条件（誤検知防止） | **変更不可** |

**NG 表記**: `Use when:` / `使用時:` / `発動条件:` → システムに解析されない

---

## 具体例集

### 良い例

#### 例1: Git Worktree 管理

```yaml
# ❌ 悪い例
description: Git worktreeを管理するスキル

# ✅ 良い例
description: |
  Git worktree とセットでブランチを管理するスキル。
  TRIGGER when: ブランチ作成時（git checkout -b）、worktree 作成時、git checkout 時。
  SKIP: 既存ブランチの読み取り・ログ確認のみの時。
```

**改善ポイント**:
- `TRIGGER when:` で具体的な操作を列挙
- `SKIP:` で誤検知を防ぐ条件を明記

#### 例2: スキル作成ガイド

```yaml
# ❌ 悪い例
description: スキルを作成するためのガイド

# ✅ 良い例
description: |
  スキルの新規作成・追加・設計を行う時に必ず使用するガイド。
  TRIGGER when: 「スキルを作る/作成/追加」「SKILL.mdを作成」「新しいスキル」と言われた時、既存スキルを改善・リファクタリングする時。
  SKIP: 既存スキルを実行・呼び出す時。スキルの説明や一覧を確認するだけの時。
```

**改善ポイント**:
- `TRIGGER when:` に具体的なキーワードを列挙
- `SKIP:` で「見るだけ」の操作を除外

#### 例3: デバッグスキル

```yaml
# ❌ 悪い例
description: デバッグを支援するスキル

# ✅ 良い例
description: |
  バグを体系的に調査・修正する6段階ワークフロー。
  TRIGGER when: バグ報告・バグ修正・障害調査・不具合調査・「なぜ動かない」「エラーが出る」「テストが通らない」といった問題解決時。
  SKIP: バグではない設計相談・コードレビュー・リファクタリング依頼のみの場合。
```

**改善ポイント**:
- `TRIGGER when:` に日本語キーワードを含めて検知精度を上げる
- `SKIP:` でバグではない類似ケースを除外

#### 例4: TDD スキル

```yaml
# ❌ 悪い例
description: テスト駆動開発のスキル

# ✅ 良い例
description: |
  テスト駆動開発（TDD）のRed-Green-Refactorサイクルを適用するスキル。
  TRIGGER when: 機能・バグ修正を実装する際、実装コードを書く前。「テストを先に書く」「TDDで」と指示された時。
  SKIP: テストを書かずに既存コードを修正・リファクタリングするだけの時。
```

**改善ポイント**:
- `TRIGGER when:` に「実装コードを書く前」というタイミングを明記
- `SKIP:` で「テストなし修正」ケースを除外

#### 例5: AWS 知識ガイド

```yaml
# ❌ 悪い例
description: AWSに関するスキル

# ✅ 良い例
description: |
  AWS全般の質問・設定・トラブルシューティングを支援するスキル。
  TRIGGER when: IAM・Lambda・S3・EC2・RDS・DynamoDB・CloudFormationなどAWSサービスの設定方法、エラー解決、CLI操作、アーキテクチャ設計について質問された時。
  SKIP: AWS以外のクラウド（GCP・Azure等）の質問時。
```

**改善ポイント**:
- `TRIGGER when:` に対応サービス名を列挙して検知精度を上げる
- `SKIP:` で他クラウドとの混同を防ぐ

#### 例6: コードレビュースキル

```yaml
# ❌ 悪い例
description: コードレビューを行うスキル

# ✅ 良い例
description: |
  元の計画とコーディング標準に対してコードをレビューするスキル。
  TRIGGER when: 主要な実装ステップが完了した時、「レビューして」「確認して」と言われた時。
  SKIP: まだ実装が完了していない途中の状態の時。
```

**改善ポイント**:
- `TRIGGER when:` で「完了後」という発動タイミングを明確に
- `SKIP:` で「未完了コード」への誤発動を防ぐ

---

## 悪い例の共通点

1. **抽象的すぎる**: 「〜を管理する」「〜を支援する」
2. **トリガー条件がない**: 「いつ使うか」が不明
3. **具体的な操作がない**: 何をするか曖昧
4. **強制力がない**: 「必ず」「禁止」などの言葉がない

---

## description 作成チェックリスト

- [ ] `TRIGGER when:` が含まれ、発動条件が具体的か
- [ ] `SKIP:` が含まれ、誤検知を防ぐ条件が書かれているか
- [ ] `Use when:` など非標準キーワードを使っていないか
- [ ] 説明文（TRIGGER 行より前）が **50字以内**か（全スキル合計 2,000 文字予算を維持するため）
- [ ] 曖昧な表現（「支援する」「管理する」等）を避けているか

---

## 補足: description の長さ

- **上限**: 説明文（TRIGGER 行より前）は **50字以内**（Claude Code の description 予算制約による）
- **全体予算**: `~/.claude/skills/` 全スキルの description 合計を **2,000文字以内** に維持する

全体予算の確認コマンド:

```bash
python3 -c "
import os, re
d = os.path.expanduser('<project>/skills')
t = 0
for s in os.listdir(d):
    p = os.path.join(d, s, 'SKILL.md')
    if os.path.isfile(p):
        m = re.search(r'^description:\s*(.*?)(?=\n\w|\n---)', open(p).read(), re.M|re.S)
        if m: t += len(m.group(1).strip())
print(f'合計 {t} 文字 / 予算 8000 文字')
"
```
