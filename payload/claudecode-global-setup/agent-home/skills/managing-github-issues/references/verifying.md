# verify モード — 1 issue 範囲突合

managing-github-issues の verify モード本文（旧 verifying-issue-scope スキル。Type 性質: gate）。

`issue-N` ブランチで `git diff --cached --name-only` の結果を、対象 issue の body に書かれた
「変更ファイル」「影響範囲」一覧と突合する。無関係なファイルが混入していないかを機械的に検査する。

PR #125（seeds 他データを巻き込んだ実害）の再発を防ぐ。

---

## 基本ワークフロー

### Phase 1: 前提確認

```bash
# 1. ブランチ名から issue 番号を抽出
branch=$(git rev-parse --abbrev-ref HEAD)
issue_num=$(echo "$branch" | grep -oE '^issue-([0-9]+)$' | grep -oE '[0-9]+')

# 2. staged ファイル取得
staged=$(git diff --cached --name-only)
```

以下のいずれかなら **このスキルを skip して終了**:
- ブランチ名が `issue-<数字>` でない
- staged が空（突合する対象がない）

---

### Phase 2: issue body 取得

```bash
issue_body=$(gh issue view "$issue_num" --json body,title --jq '.title + "\n\n" + .body')
```

issue が見つからない場合は警告を出して終了する（突合不能）。

---

### Phase 3: 期待ファイル抽出

issue body から「変更ファイル」「影響範囲」「実装対象」のセクション、およびインラインで言及される
ファイルパスを抽出する。次のパターンで grep:

```bash
expected=$(echo "$issue_body" | grep -oE '(backend|frontend|supabase|docs_site|prompts|\.github)/[A-Za-z0-9_./-]+' | sort -u)
```

抽出ヒューリスティック:
- バッククォート囲みの ` `path/to/file` ` も拾う
- ディレクトリ参照（末尾 `/`）はパッケージ単位の許可とみなし、配下ファイルを許す
- 類似機能の言及があれば `frontend/src/<dir>/` 等の prefix も許可リストに加える

---

### Phase 4: 突合判定

```bash
unexpected=()
for f in $staged; do
  matched=0
  for e in $expected; do
    # 完全一致 or e がディレクトリ prefix
    if [ "$f" = "$e" ] || [[ "$f" == "$e/"* ]] || [[ "$f" == "$e"* ]]; then
      matched=1; break
    fi
  done
  if [ $matched -eq 0 ]; then
    unexpected+=("$f")
  fi
done
```

加えて以下のパスは **常にホワイトリスト**（issue body に出なくても許可）:
- `<同じ機能のテストファイル>`: `backend/tests/test_*.py` / `frontend/**/*.test.{ts,tsx}` （対応するソースが staged にあれば）
- `docs_site/<同じ機能の仕様書>`: ソースが `frontend/src/<dir>/` `backend/app/<dir>/` にあれば対応する `docs_site/機能仕様/<NN>_*.md` を許可

逆に以下のパスは **常にブラックリスト**（混入を必ず検出）:
- `supabase/seeds/03-battle-records.sql` / `04-battle-log-entries.sql`（マスタの大規模変更）
- `test-results/` 配下（テストキャッシュ）

---

### Phase 5: 報告

`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（調査報告型）に従う。

固有の検証行: ファイルごとの判定（OK / 要確認 / NG）と理由。「検証」テーブルの行として以下の形式で列挙する。

```
| 判定 | ファイル | 理由 |
|------|---------|------|
| ✅ OK | backend/app/routers/<file>.py | issue body に記載 |
| ✅ OK | backend/tests/test_<file>.py | テスト同梱（自動許可） |
| ⚠️ 要確認 | docs_site/機能仕様/<NN>_<name>.md | issue body に記載なし。仕様追記の意図か？ |
| 🔴 NG | supabase/seeds/03-battle-records.sql | ブラックリスト（マスタ大規模変更） |
```

🔴 NG が 1 件以上あれば、`git restore --staged <PATH>` の具体コマンドを併記して提示する:

```bash
# 推奨コマンド（コピーして実行）
git restore --staged supabase/seeds/03-battle-records.sql

# 再確認
git diff --cached --name-only
```

⚠️ 要確認のみで NG なしなら、ユーザーに AskUserQuestion で「このまま commit するか / 確認したパスを除外するか」を選ばせる。

✅ のみなら「範囲 OK」と報告して終了。

---

## 重要な注意事項

- このスキルは `git restore --staged` を **自動実行しない**。NG パスは候補としてユーザーに提示するのみ。
- issue body にファイル名がまったく記載されていない issue（自由記述スタイル）の場合は突合精度が落ちる。その場合はホワイトリスト・ブラックリスト判定のみを行い、グレーゾーンは ⚠️ にする。
- `issue-resolver-daily` / `coverage-improvement-daily` / `design-doc-sync-daily` / `pr-health-check` のいずれかのルーティン経由で呼ばれた場合は AskUserQuestion ではなく、🔴 NG を自動的に `git restore --staged` する判断を verify モード側で取らない。呼び出し元ルーティン（例: `prompts/routines/issue-resolver-daily.md`）の Phase 2-7a で `git restore --staged` を実行する。

---

## 関連スキル

| スキル | 役割分担 |
|--------|---------|
| `grouping-commits` | コミット単位で変更をグループ化（範囲突合の前段） |
| `formatting-pr` | 範囲確認後の PR 本文整形 |
| 命名規約（rules: always/naming/commit-branch） | コミット・ブランチ命名規則 |

---

## 完了条件

| Phase | 条件 |
|---|---|
| Phase 1 | ブランチ名から issue 番号が抽出され、staged ファイルが 1 件以上ある |
| Phase 2 | issue の本文（タイトル・ボディ）を取得済み |
| Phase 3 | staged ファイル一覧と issue スコープの突合が完了 |
| Phase 4 | 突合結果が NG 0 件または NG ファイルのリストアップ完了 |
| Phase 5 | 結果がユーザーに報告済み |
| **Goal** | NG 0 件かつ全 staged ファイルが issue スコープ内と判定 |

## 完了報告

Phase 5（本ファイル前掲）の形式で報告する。`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（調査報告型）に従う。

---

## 予想を裏切る挙動

- staged ファイルが issue の範囲外でも「意図的な変更」の場合がある — 自動 restore する前に必ず理由を確認する
