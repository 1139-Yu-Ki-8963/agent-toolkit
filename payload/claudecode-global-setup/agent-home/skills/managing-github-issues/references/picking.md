# pick モード — issue 選択から実装フロー起動

managing-github-issues の pick モード本文（旧 picking-issues スキル。Type 性質: gateway）。

GitHubイシューを取得・表示し、ユーザーが番号で選択した後に適切な実装フローを起動する。

---

## Phase 1: イシュー一覧取得

以下のコマンドでオープンなイシューを取得する。

```bash
gh issue list \
  --state open \
  --limit 50 \
  --json number,title,labels,assignees,createdAt
```

取得結果を以下の形式でユーザーに提示する（`No.` は 1 始まりの連番）:

```
| No. | Issue # | タイトル | ラベル | 担当者 | 作成日 |
|-----|---------|---------|--------|--------|--------|
| 1   | #42     | ログイン画面のバグ修正 | bug    | -     | 2026-05-01 |
| 2   | #38     | ダッシュボード実装     | feature | -    | 2026-04-28 |
```

- `No.` … ユーザーが選択に使う連番
- `Issue #` … GitHub 上の実際の番号（詳細取得に使う）
- ラベルが複数ある場合はカンマ区切りで表示
- 担当者なし・ラベルなしは `-` と表示

イシューが 0 件の場合は「オープンなイシューはありません」と伝えて終了する。

---

## Phase 2: ユーザー選択

AskUserQuestion で以下を問いかける:

- **question**: 「実装するイシューの No. を入力してください（複数の場合はカンマ区切り。例: 1,3）」
- **options**: 不要（自由入力）

入力の解析ルール:
- `1` → 1件選択
- `1,3` → 2件選択（バルクフロー）
- `all` → 全件選択（バルクフロー）
- 範囲外の番号が含まれる場合は「No.XX は存在しません」と伝えて再入力を促す

---

## Phase 3: 詳細取得

選択された各 Issue # に対してタイトルと本文を取得する:

```bash
gh issue view NUMBER \
  --json number,title,body,labels,assignees
```

---

## Phase 4: フロー起動

issue の `flow:*` ラベルを読んで対応スキルを Skill ツールで呼び出す。

### ラベル判定

| `flow:*` ラベル | 起動スキル |
|---|---|
| `flow:feature` | `flow-feature` |
| `flow:bulk` | `flow-feature` |
| `flow:fix` | `flow-maintenance` |
| なし | AskUserQuestion で3択を提示してから進む |

### `flow:*` ラベルがない場合

AskUserQuestion で以下3択を提示する:
- `flow:feature` — 単機能の新規追加・挙動変更
- `flow:bulk` — 複数画面・ドメイン横断の一括実装
- `flow:fix` — バグ修正・負債解消・メンテナンス

選択後、`gh issue edit NUMBER --add-label "flow:XXX" --repo REPO` でラベルを付与してからスキルを起動する。

### 複数 issue 選択時

- **同一ラベル**: そのスキルを1回呼び出してすべての issue を渡す
- **ラベル混在**: issue ごとに順番にスキルを呼び出す

### スキル起動時に渡す指示テンプレート

1件の場合:
```
Issue #NUMBER: TITLE
ラベル: LABELS

---

BODY
```

複数件の場合:
```
Issue #N1: TITLE1
Issue #N2: TITLE2
...

---

【Issue #N1 詳細】
BODY1

【Issue #N2 詳細】
BODY2
```

---

## Phase 5: ルーティンモード時の処理／スキップ一覧出力（必須）

呼び出し元が `issue-resolver-daily` / `coverage-improvement-daily` / `design-doc-sync-daily` /
`pr-health-check` のいずれかのルーティンの場合、Phase 1〜4 の通常処理に加え、
**ループ終了時に「処理した issue / スキップした issue」の一覧を必ず出力**する。

PR #122〜#125 のセッションで #114〜#117 を理由なくスキップしたまま処理結果が
不可視化された問題への対策。

### 出力フォーマット

```
## ルーティン実行結果 (YYYY-MM-DD)

### 処理結果
| # | タイトル | ラベル | 結果 | スキップ理由 / 補足 | PR |
|---|---------|--------|------|---------------------|-----|
| #N | ... | bug | 完了 | - | https://... |
| #M | ... | feature | スキップ（テスト失敗） | 修正 3 回後も pytest test_xxx が fail | - |
| #K | ... | enhancement | スキップ（ホットファイル衝突） | `backend/app/routers/battles.py` が PR #123 と競合 | - |
| #J | ... | enhancement | スキップ（重複 PR 既存） | PR #110 が同 issue で open | - |

### 要約
- Phase 1 取得 issue: X 件
- 完了（PR 作成）: A 件
- スキップ（テスト失敗）: B 件
- スキップ（ホットファイル衝突）: C 件
- スキップ（重複 PR / 既存 linked PR）: D 件
- スキップ（その他）: E 件 — 理由を個別に明示
```

### スキップ理由の必須カテゴリ

| カテゴリ | 補足の最低記載項目 |
|---------|---------------------|
| テスト失敗 | 失敗テスト名・最終 fail メッセージ要約 |
| ホットファイル衝突 | 衝突ファイル・競合 PR 番号 |
| 重複 PR 既存 | 既存 PR 番号と URL |
| rebase 不能 | 衝突ブランチ名・人手対応事項 |

カテゴリ外のスキップ（「複雑度が高い」等の暗黙判断）は **禁止**。
やむを得ず処理を保留する場合は `wontfix` または `blocked` ラベルを issue 側に付与し、
ラベルベースで除外されるようにしてからスキップする。

### 出力先

- 標準出力（ユーザーへの最終応答）

### Phase 1 取得 issue は 1 件残らず表に行を持つ

「処理対象だが何もしなかった issue」が表から消えることを禁止する。全件を表に
記載することで、人間が「どの issue が放置されたか」を一目で把握できる。

## 完了条件

| Phase | 条件 |
|---|---|
| Phase 1 | issue 一覧が 1 件以上取得されユーザーに表示済み |
| Phase 2 | ユーザーが issue 番号を選択済み |
| Phase 3 | 選択 issue の詳細（title, body）を取得済み |
| Phase 4 | 対応スキルが Skill ツールで起動済み |
| Phase 5 | 処理/スキップ一覧が出力済み |
| **Goal** | 選択された全 issue に対して対応スキルが起動され、ルーティンモード時は処理/スキップ一覧が出力されている |

## 完了報告

`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（作業報告型）に従う。ルーティンモード時は本ファイルの「Phase 5」出力フォーマットを併用する。

## 予想を裏切る挙動

- issue 番号が既に明示されている場合はこのスキルは不要 — 直接 parallel-dev-worktree を使う
