# コンフリクト解消（Phase 2 詳細）

SKILL.md Phase 2 の手順。コード編集（Phase 4）の前に必ず完了する。

> **rebase 禁止**: PR ブランチで `git rebase` を使ってはならない。
> rebase はコミット SHA を書き換えるため force push が必要になり、deny ルールで詰まる。
> main の変更を取り込む場合は必ず `git merge origin/$BASE_BRANCH --no-edit` を使う。
> merge commit が追加されるだけで通常 push が可能。

> **スキップ禁止**: 形式A・形式Bを問わず、Phase 4 の前に必ず完了する。
> Phase 2 未完了なら Phase 4 を開始してはならない。

## 2-1. コンフリクト確認

```bash
cd "$WORKTREE_PATH"
git fetch origin "$BASE_BRANCH"
git merge "origin/$BASE_BRANCH" --no-commit --no-ff 2>&1
```

- コンフリクトなし → `git merge --abort` して Phase 3 へ
- コンフリクトあり → 2-2 へ

## 2-2. コンフリクトファイルの特定

```bash
git diff --name-only --diff-filter=U
```

## 2-3. 解消

各ファイルを Read し、conflict marker（`<<<<<<<` / `=======` / `>>>>>>>`）を Edit で解消する。

解消の原則:
- 両側の変更が独立 → 両方残す
- 同じ箇所を変更 → PR ブランチ側（HEAD）を優先
- ロジックが競合 → ユーザーに報告して中断

## 2-4. テスト確認

layers.yml の各レイヤーの lint / test / type_check（コマンドは SKILL.md Phase 5 と同じ）で解消が正しいか確認する。
失敗 → 解消内容を見直す。2 回試みても失敗 → ユーザーに報告して中断。

## 2-5. コンフリクト解消コミット・push

```bash
git add .
git commit -m "fix: $BASE_BRANCH との merge コンフリクトを解消"
git push origin HEAD:$HEADBRANCH

# push 後は行番号ずれ防止のため p1_list を再取得する
head_sha=$(git rev-parse HEAD)
# SKILL.md Phase 1-3 の手順で p1_list を再構築
```

解消できない場合（ロジック競合・テスト 2 回失敗）の報告フォーマット:

```
コンフリクト解消を中断します。

手動での確認が必要なファイル:
- {CONFLICT_FILE}

理由: {解消できなかった理由}
```

## テスト失敗が main の最新不足に起因する場合

Phase 5 のテスト失敗の原因が「PR ブランチに main の hotfix が含まれていない」と判明した場合:

```bash
cd "$WORKTREE_PATH"
git fetch origin "$BASE_BRANCH"
git merge "origin/$BASE_BRANCH" --no-edit   # merge commit が追加される（SHA 書き換えなし）
git push origin HEAD:$HEADBRANCH            # 通常 push で済む（force 不要）

# push 後は p1_list を再取得する
head_sha=$(git rev-parse HEAD)
# SKILL.md Phase 1-3 の手順で p1_list を再構築
```

`git rebase` は使ってはならない（理由は冒頭の rebase 禁止欄を参照）。

## worktree の detached HEAD 注意

worktree は detached HEAD で開始する（SKILL.md Phase 1-2）。
push 後にローカルブランチへ切り替えると、ローカル ref が push 前の古い HEAD を指していることがあり、
続く rebase で直近コミットが消失する。push 後にブランチ操作する場合は必ず:

```bash
git fetch origin "$HEADBRANCH"
git checkout "origin/$HEADBRANCH"   # 必要なら detached HEAD のまま続行
```

を経由してからブランチ ref を操作する。

## data/*.js 配列追加コンフリクトの自動解消

### 対象ファイル

project-portal の data/*.js（配列の先頭にエントリを追加する形式のファイル）:

- `data/release-notes.js`
- `data/mocks.js`
- `data/master-tables/metrics.js`
- `data/master-tables/coverage.js`
- `data/design-docs.js`
- `data/page-graph.js`

### コンフリクトの原因

複数セッションが並列で PR を作成し、同じ配列の先頭にエントリを追加した場合、2 本目以降の PR で `export default [` 直後の行が衝突する。

### 解消ルール（判断不要・機械的に実行）

1. **両方のエントリを残す**。どちらも正当な追加であり、片方を捨てる理由がない
2. **順序は問わない**。新しい日付が先でも後でもよい（描画側がソートする）
3. **コンフリクトマーカー（`<<<<<<<` / `=======` / `>>>>>>>`）を削除し、両方の内容を残すだけ**

### 具体的な手順

```bash
# コンフリクトが起きたファイルに対して:
# 1. コンフリクトマーカーを機械的に除去（両方の内容を残す）
sed -i '' '/^<<<<<<</d; /^=======/d; /^>>>>>>>/d' <file>

# 2. JS として有効か確認
node --input-type=module -e "import('./<file>').then(m => console.log('OK:', m.default.length))"

# 3. 有効なら git add
git add <file>
```

### この手順を使う条件

- コンフリクト箇所が `export default [` 直後の配列エントリ追加のみ
- 両方のエントリが独立した新規追加（既存エントリの編集ではない）

上記を満たさないコンフリクト（既存エントリの修正同士の衝突等）は、通常のコンフリクト解消手順に従う。
