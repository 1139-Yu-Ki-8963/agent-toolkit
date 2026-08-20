# fixing-review-findings（orchestrating-dev-flow 内部モジュール）

PR 番号または `reviewing-prs` スキルが出力した構造化結果を受け取り、警告指摘と重大な問題（critical）を worktree 内で自動修正して PR ブランチへ push するモジュール。
修正後は `reviewing-prs` で自動再レビューを実施し、警告と critical の双方が解消されれば自動マージまで完結させる（ユーザー承認なし）。

> **flow-values.yml 参照キー**:
> `loop_count_max`（既定 1）、`loop_critical_max`（既定 2）、
> `worktree.postcreate_script`（`git worktree add` 後の自動セットアップスクリプト）、
> `layers_file`（既定 `layers.yml`）

> **references/ ディレクトリ**: 本モジュールの詳細手順は `~/agent-home/skills/orchestrating-dev-flow/references/` に分離されている。
> - `fixing-review-findings-conflict-resolution.md` — コンフリクト解消プロトコル全文
> - `fixing-review-findings-critical-autofix.md` — critical 分類マトリクス・適用ループ詳細
> - `fixing-review-findings-merge-decision.md` — 再レビュー Task プロンプト・マージ判定マトリクス・フォールバック型マージ
> - `fixing-review-findings-splitting-commits.md` — コミット分割手順

**critical 自動修正の責務範囲**

- 修正対象: セキュリティ（例: `eval()` 直書き・SQL injection・XSS）・データ消失（例: 無条件 DELETE / DROP）・既知バグ（NULL 参照・型不整合）など、コード差分だけで解消できる critical
- skip 対象（設計判断級・1 件単位で skip → 全件 skip された場合は断念+報告）:
  - 公開 API シグネチャ破壊・スキーマ破壊（DB マイグレーション要件含む）
  - アーキテクチャ刷新を要する critical（A-01〜A-03 級）
  - 仕様議論を要する critical（要件解釈が分かれるもの）

## 前提条件

以下のいずれかの入力形式で動作する:

**形式A: PR 番号のみ（自律動作モード）**
- `pr_number` のみ渡す。Phase 1 で残りを自律取得する。

**形式A': 引数なし（直前 PR 自動取得モード）**
- `pr_number` を渡さずに起動する。Phase 1-0 で自動取得してから Phase 1-1 以降に進む。

**形式B: reviewing-prs 経由（引き継ぎモード）**
- `worktree_path` — `<PROJECT_ROOT>/.claude/worktrees/pr-NUMBER` の形式（`git rev-parse --show-toplevel` で解決）
- `p1_list` — 警告指摘の配列（各要素: `{id, file, line, description, fix}`）
- `pr_number` — GitHub PR 番号
- `head_sha` — PR ブランチの HEAD commit SHA
- この場合 Phase 1 をスキップして Phase 2 へ進む。

---

## Phase 1: PR 情報の自律取得（形式A・形式A'）

形式B（reviewing-prs 経由）の場合はこの Phase をスキップして Phase 2 へ進む。

### 1-0. PR 番号の自律取得（形式A' のみ）

`pr_number` が引数で渡されない場合、以下の優先順位で取得する。

```bash
# 優先1: 現在のブランチに紐づく PR
pr_number=$(gh pr view --json number --jq .number 2>/dev/null)

# 優先2: 自分の最新オープン PR（直前で作成した PR を想定）
if [ -z "$pr_number" ]; then
  pr_number=$(gh pr list --author @me --state open \
    --json number,createdAt \
    --jq 'sort_by(.createdAt) | reverse | .[0].number')
fi
```

- 両方とも空 → `AskUserQuestion` で「対象 PR 番号」をユーザーに問い合わせる
- 直近 24h に 2 件以上自分が作成した場合は `AskUserQuestion` で対象を確認する

### 1-1. PR メタ情報取得

```bash
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
gh pr view NUMBER --repo "$REPO" \
  --json headRefName,headRefOid,baseRefName
# → HEADBRANCH / head_sha / BASE_BRANCH を取得
```

### 1-2. worktree 準備

```bash
PROJECT=$(git rev-parse --show-toplevel)
WORKTREE="$PROJECT/.claude/worktrees/pr-NUMBER"

# 既存 worktree があれば再利用、なければ作成
if git -C "$PROJECT" worktree list | grep -q "$WORKTREE"; then
  git -C "$WORKTREE" fetch origin "$HEADBRANCH"
  git -C "$WORKTREE" checkout --detach "origin/$HEADBRANCH"
else
  git -C "$PROJECT" fetch origin "$HEADBRANCH"
  git -C "$PROJECT" worktree add "$WORKTREE" --checkout "origin/$HEADBRANCH"
fi

# flow-values.yml の worktree.postcreate_script が存在する場合は自動実行される
# （.venv symlink / node_modules / .env 等のセットアップ）
```

> **detached HEAD 注意**: この worktree 作成コマンドは detached HEAD で開始する。
> push 後にローカルブランチへ切り替えると ref が古い HEAD を指したままになり、直近コミットが消失する。
> push 後のブランチ操作は必ず:
> ```bash
> git fetch origin "$HEADBRANCH"
> git checkout "origin/$HEADBRANCH"
> ```
> を経由してから行うこと。

### 1-3. p1_list の構築

GitHub API でレビューコメントを取得し、`[警告]` を含むものを抽出する。

```bash
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)

# インラインコメント（コード行指定）
gh api "repos/$REPO/pulls/NUMBER/comments" \
  --jq '.[] | {id, path, line, body, in_reply_to_id}'

# 全体コメント
gh api "repos/$REPO/issues/NUMBER/comments" \
  --jq '.[] | {id, body}'
```

パース規則:
- `[警告]` を含む → warning_list に追加（返信コメント `in_reply_to_id` が非 null のものはスキップ）
- `[重大な問題]` を含む → critical_list に分離

**コメント 0 件の場合（レビュー未実施 PR）**:
`reviewing-prs` スキルをサブエージェント経由で起動して指摘を生成する。

```
Task(worker-sonnet,
  "reviewing-prs スキルで PR #NUMBER をレビューせよ。
   worktree は <PROJECT_ROOT>/.claude/worktrees/pr-NUMBER を再利用（削除禁止）。
   結果を {critical_list, warning_list, suggestion_list, tests_passed} で返せ。
   PR コメントの投稿は禁止（このスキルが Phase 7 で投稿するため）。")
```

**critical_list が 1 件以上ある場合**:
原則として AskUserQuestion を出さず、Phase 4-C「critical 自動修正試行」へ流す。warning_list と suggestion_list はそのまま Phase 3-7 の通常ルートに乗せる。

AskUserQuestion を出すのは次の例外時のみ:
- コミット分割など構造的対応が必要と判明している場合（`fixing-review-findings-splitting-commits.md` の手順を提示する）
- 同 PR で `loop_critical == loop_critical_max` まで進んだ後、なお解消不能 critical が残った場合（Phase 8-2 で判定）

---

## Phase 2: コンフリクト検出・解消

> **スキップ禁止**: 形式A・形式Bを問わず、コード編集（Phase 4）の前に必ず完了する。
> **rebase 禁止**: PR ブランチで `git rebase` を使わない（SHA 書き換えで force push が必要になる）。main 取り込みは `git merge origin/$BASE_BRANCH --no-edit` を使う。

最小手順:

1. `git fetch origin "$BASE_BRANCH"` → `git merge "origin/$BASE_BRANCH" --no-commit --no-ff`
2. コンフリクトなし → `git merge --abort` して Phase 3 へ
3. コンフリクトあり → `git diff --name-only --diff-filter=U` で特定し、Edit で解消
4. lint + ユニットテストで確認後、解消コミット → push → p1_list 再取得

詳細手順・解消の原則・中断報告フォーマットは `fixing-review-findings-conflict-resolution.md` を参照する。

---

## Phase 3: 警告指摘リストの読み込み

渡された `p1_list` を確認し、修正可能な指摘を選別する。

**自動修正できるもの（対象）**:
- null / undefined 返却を throw に変換（P-05）
- フォールバック値（`||` `??`）の除去（P-06）
- 不要な try-catch の除去（P-04）
- Input/Output 型の除去（P-01）
- 早期 return によるネスト平坦化（P-07）

**自動修正しないもの**:
- アーキテクチャ変更を伴う指摘（A-01〜A-03）
- ファイル分割・関数分割が必要な指摘（Q-01・Q-02）
- 判断が必要なもの（「改善を検討」レベル）

修正しない指摘はリストから除外し、Phase 7 のコメントに「手動対応が必要な警告」として別途記載する。

---

## Phase 4: コードの自動修正

**開始前チェック（Phase 2 の完了確認）**
以下のいずれかを確認してから編集を開始すること:
- [ ] `git merge --abort` を実行済み（コンフリクトなしの場合）
- [ ] コンフリクト解消コミットの SHA を確認済み

**一括 apply 方式**: `worktree_path` 内の対象ファイルを Read し、Edit ツールで **warning_list 全件を 1 トランザクションで一括適用** する。1 件ずつ apply→commit→push のループは禁止する。

```
1. p1_list を file ごとにグルーピング
2. 各ファイルを 1 度だけ Read（最大 N=10 ファイル並列）
3. 該当ファイル内の全指摘を 1 回の Edit セッションで適用する
4. 1 ファイルでも適用エラーが出たら、そのファイルだけ skipped_list へロールバック
5. 全ファイル処理完了後、Phase 5（テスト）→ Phase 6（1 commit + 1 push）でまとめてコミット
```

**修正の原則**:
- 最小差分で修正する（周辺コードを変えない）
- 型エラーが発生する可能性がある修正は skipped_list に回す

---

## Phase 4-C: critical 自動修正試行

> **発火条件**: `critical_list` が 1 件以上ある時。Phase 4 完了後に同 worktree で続けて実行する。

最小手順:

1. critical を 1 件ずつ apply / skip に分類（設計級＝API/スキーマ破壊・アーキ刷新・仕様議論は skip）
2. apply 対象を Read → Edit（最小差分）→ `critical_applied_list` / `critical_skipped_list` へ振り分け
3. 修正コミット → `git push origin HEAD:$HEADBRANCH` → `head_sha` 更新
4. skip 0 件 → Phase 5 へ / skip ありで `loop_critical < loop_critical_max` → `loop_critical++` して Phase 8 / それ以外 → 断念フラグを立て Phase 8

分類マトリクス・適用ループ詳細は `fixing-review-findings-critical-autofix.md` を参照する。`loop_critical`（初期値 0）で再試行回数を管理する。

---

## Phase 5: テスト再実行

修正後にテストを実行して、修正が既存の挙動を壊していないことを確認する。

```bash
cd "$WORKTREE_PATH"

# flow-values.yml の layers_file（既定 layers.yml）を読み込み
# 各レイヤーの lint / test / type_check コマンドを順次実行する
LAYERS_FILE=$(yq '.layers_file // "layers.yml"' flow-values.yml 2>/dev/null || echo "layers.yml")

for layer in $(yq '.layers | keys | .[]' "$LAYERS_FILE" 2>/dev/null); do
  for key in lint test type_check; do
    cmd=$(yq ".layers.$layer.$key // empty" "$LAYERS_FILE" 2>/dev/null)
    [ -n "$cmd" ] && (echo "[$layer] $key: $cmd" && eval "$cmd")
  done
done
```

**E2E テスト（必須）**: lint・ユニットテストが通過した後、必ず `module-running-e2e.md` の手順で E2E を実行する。CI と同等の検証をローカルで完了してから Phase 6 に進む。

テストが失敗した場合:
1. 失敗の原因を特定する
2. 自分の修正が原因か確認する
3. 修正が原因の場合: その修正を revert して skipped_list に移動する
4. 修正と無関係の場合: Phase 7 のコメントに記録する
5. revert 後に再度テストを実行して通過を確認する
6. **2 回 revert しても解消しない場合は Phase 6 に進まず Phase 7 で断念を報告する**

---

## Phase 6: commit & push

テストが全て通過した場合のみ実行する。

```bash
cd "$WORKTREE_PATH"

git add -p   # 変更を確認しながら add（自動修正ファイルのみ）

git commit -m "$(cat <<'EOF'
【バグ修正】警告を自動修正 (PR #NUMBER)
EOF
)"

git push origin HEAD:$HEADBRANCH
```

push が失敗した場合（権限なし等）:
- `git format-patch HEAD~1` でパッチファイルを生成する
- Phase 7 のコメントにパッチ内容を添付して記録する

---

## Phase 7: PR へコメント投稿

```bash
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
gh pr comment NUMBER --repo "$REPO" --body "$(cat <<'EOF'
## 警告 自動修正 完了

以下の警告を自動修正しました。

### 修正済み
<applied_list: 各指摘を [rule-id] file:line 形式で列挙>

### 手動対応が必要な警告
<skipped_list: 各指摘と理由を列挙。なければ「なし」>

テストはすべて通過しています。
EOF
)"
```

---

## Phase 8: 自動再レビュー・自動マージ

Phase 7 のコメント投稿完了後に実行する。`loop_count`（初期値 0）で無限ループを防止する。
上限値は `flow-values.yml の loop_count_max`（既定 1）、critical 上限は `loop_critical_max`（既定 2）。

最小手順:

1. **8-1 再レビュー**: `reviewing-prs` サブエージェントを起動し、worktree 再利用・削除禁止で `{critical_list, warning_list, suggestion_list, tests_passed}` を取得
2. **8-2 結果判定**: 重大・警告なし → 8-3 へ。警告あり（critical なし）かつ `loop_count < loop_count_max` → `loop_count++` で Phase 3 へ（1 回の修正サイクルで解消しなければ手動対応へ）。critical あり かつ `loop_critical < loop_critical_max` → `loop_critical++` で Phase 4-C へ。上限到達・設計級のみ残存 → 断念を報告して Phase 9 へ。
3. **8-3 自動マージ（承認なし）**: 保護ルール／CI 状況の判定マトリクスに従い `--merge`（必要時のみ `--admin`）でマージ。code 起因 fail・コンフリクト・権限不足は中断して Phase 9 へ。

再レビュー Task プロンプト全文・結果判定マトリクス（全条件）・断念報告フォーマット・保護ルール判定マトリクスは `fixing-review-findings-merge-decision.md` を参照する。

設計級 critical のみ残存して断念する場合は、`fixing-review-findings-splitting-commits.md` の手順案内を報告に含める。

---

## Phase 9: worktree の削除

> **必須**: `git worktree remove` の前に **`ExitWorktree` ツール（action: keep）** を呼ぶこと。
> セッションの仮想 cwd が削除済みパスを指したまま Stop hook が発火すると全 Stop hook が失敗する。

1. `ExitWorktree` ツールを呼ぶ（action: keep）
2. worktree を削除する:

```bash
PROJECT=$(git rev-parse --show-toplevel)
git -C "$PROJECT" worktree remove "$WORKTREE_PATH" --force
```

---

## 内部出力スキーマ（Task return value、chat には絶対に出さない）

```json
{
  "pr_number": "NUMBER",
  "applied_count": "N",
  "skipped_count": "N",
  "critical_applied_count": "N",
  "critical_skipped_count": "N",
  "tests_passed": "true/false",
  "pushed": "true/false",
  "loop_count": "N",
  "loop_critical": "N",
  "conflict_resolved": "true/false",
  "merged": "true/false"
}
```

上位オーケストレータが Task ツール経由で呼んだ場合の return value 専用。単発起動では「人間向け最終要約」だけを出力すること。

---

## 人間向け最終要約（chat に出す唯一の最終応答）

```markdown
## 完了

**PR #NUMBER**: <マージ済 / 残存指摘あり / 断念> （merge commit: SHA / なし）

### 反映した指摘
- <id>: <一言要約>

### 残った指摘・手動対応事項
- なし / または箇条書き

### 検証結果
- 各レイヤー lint / test / type_check: <pass / fail と件数>
- 追加確認: <あれば>
```

---

## 予想を裏切る挙動

- worktree を `detached HEAD` で作成するため、push 後にローカルブランチへ切り替えると ref が古い HEAD を指したままになり直近コミットが消失する。push 後のブランチ操作は必ず `git fetch origin` 経由で行うこと
- `loop_count` の上限は `flow-values.yml の loop_count_max`（既定 **1**）。警告が 1 サイクルで解消しなければ即座に手動対応報告に移る
- 内部出力スキーマ JSON は **chat に絶対に貼らない**。単発起動時は「人間向け最終要約」だけを出力する
- `layers.yml` が存在しない場合は Phase 5 のテストコマンドをスキップし、代わりにプロジェクト固有の CI 設定を確認してユーザーに報告する

各 Phase の出力先まとめ:

| Phase | 出力先 |
|---|---|
| Phase 1（PR 情報取得） | 内部状態。chat には進捗を 1 行のみ。生 JSON 禁止 |
| Phase 1-0（PR 番号自動取得） | 取得した PR 番号を chat に 1 行で通知 |
| Phase 2（コンフリクト解消） | 失敗時のみ chat に中断報告 |
| Phase 3（指摘リスト読込） | 内部 |
| Phase 4（コード修正） | chat に「N 件修正中」など簡潔な進捗のみ |
| Phase 5（テスト） | 失敗時のみ chat に詳細。成功時は件数のみ |
| Phase 6（commit & push） | chat にコミット SHA・push 結果を 1 行 |
| Phase 7（PR コメント） | PR コメントには定型本文。chat には URL のみ |
| Phase 8（再レビュー） | 内部。マージ実行直前で結果要約を chat に 1〜2 行 |
| Phase 8-3（自動マージ） | chat にマージ結果を 1 行 |
| Phase 9（worktree 削除） | chat に完了 1 行 |
| 内部出力スキーマ | Task return value のみ。chat 禁止 |
| 人間向け最終要約 | chat の最終応答 |
