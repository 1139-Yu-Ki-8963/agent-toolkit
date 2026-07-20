---
name: parallel-dev-worktree
description: "worktreeブランチ作成/管理/復旧。 TRIGGER when: wt1-wt3不在、MISSING/FAIL。 SKIP: 既存ブランチ継続（→orchestrating-dev-flow）。"
invocation: parallel-dev-worktree
execution: main-session
type: gateway
allowed-tools: ["Bash", "Read", "Write", "Edit"]
---

# 並列開発ワークフロー（git worktree ベース）

## 適用方針

**「実装」「修正」「直して」「対応」「issue 解決」と指示された時は、規模を問わず必ず Phase 1 から実行する。** SKILL.md の 1 行修正・typo fix 等の軽微変更も対象。例外は以下のみ:

- ユーザーが明示的に「main で直接」「main で OK」「worktree 不要」と指定した時
- 既に対応する worktree 内にいて、その作業の追加コミットを行う時
- 読み取りツール（Read/Grep/Glob/Bash の参照系）しか使わない調査タスク
- 対象が `~/.claude/` または `~/agent-home/` のグローバル設定リポジトリの時（`check-worktree-required.sh` 行20 で除外済み。main 直接編集が許可されている）

**fail-safe**: PreToolUse フックが Write/Edit/NotebookEdit 時に worktree 不在を検出すると `[WORKTREE-REQUIRED]` を注入してブロックする。本スキル（`parallel-dev-worktree/SKILL.md`）と連携する設計。例外マーカーは `/tmp/.allow-main-edit`（ワンショット消費）。これは人間がターミナルから手動 touch する専用であり、エージェントによる touch は `permissions.deny` で自動拒否される。エージェントは worktree を作成して作業すること。

このスキルはリポジトリ非依存。メイン作業ツリーのパスもデフォルトブランチ名もスキル内で動的取得する。プロジェクト固有のルール（コンフリクトしたファイル一覧・コンフリクト解消プロトコル・実装フロー等）は各リポジトリの CLAUDE.md にあるものとして参照誘導するだけで、本スキルには転記しない。

## 配置・命名規約

| 項目 | ルール |
|------|------|
| worktree パス | `~/Projects/worktrees/<repo>/<branch-name>/`（`<repo>` 階層でリポジトリ間のブランチ名衝突を防ぐ。スラッシュはディレクトリ階層） |
| ブランチ名 | 命名規約（rules: always/naming/commit-branch）の「ブランチ名」に従う（`feature/` `fix/` `docs/` `chore/` `refactor/` `release/` のいずれか + `<slug>`） |

ブランチ命名の詳細は `~/.claude/rules/always/naming/commit-branch/naming-values.txt` を Read する（本スキルでは再列挙しない）。

## 共通変数

各 Phase で使う変数は最初に決定する:

```bash
REPO=$(git rev-parse --show-toplevel)
DEFAULT_BRANCH=$(git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's@^origin/@@')
[ -z "$DEFAULT_BRANCH" ] && DEFAULT_BRANCH=main
REPO_NAME=$(basename "$REPO")
WORKTREE_ROOT="$HOME/Projects/worktrees/$REPO_NAME"
HAS_GH=$(gh repo view --json url 2>/dev/null && echo yes || echo no)
```

## Phase 1: 着手前チェック

メイン作業ツリーで以下を並列実行する:

1. `git -C "$REPO" status --short` — 作業ツリーの汚れを確認。汚れていた場合、**ユーザー確認なしに stash しない**。汚れの内容を提示して指示を仰ぐ
2. `git -C "$REPO" branch --show-current` — `$DEFAULT_BRANCH` 以外にいる場合は理由を確認
3. `[ "$HAS_GH" = yes ]` のとき `gh pr list --state open --json number,title,headRefName,files --limit 30` で OPEN PR の対象ファイルを把握
4. `git -C "$REPO" fetch origin "$DEFAULT_BRANCH" --prune` — `origin/$DEFAULT_BRANCH` を最新化（**ローカルのデフォルトブランチ作業ツリーには checkout・pull しない**）
5. ポートスロット割当（ポート管理規約: `~/.claude/rules/always/local-environment/port-management/rule.md`）: `git worktree list` で既存 worktree の `.port-slot` を確認し、空いている最小のスロット番号（1〜5）を新 worktree 用に確保する。全体で 5 本が上限であり、空きがなければエラーとしてユーザーに報告する（この時点では書き込みは行わず、番号のみ確定する。書き込みは Phase 3 で行う）

## Phase 2: コンフリクトしたファイル衝突予測

プロジェクト側 CLAUDE.md に「コンフリクトしたファイル」見出しがある場合のみ実施する。検出方法:

```bash
grep -nE '^#{1,3}\s*コンフリクトしたファイル' "$REPO/CLAUDE.md" 2>/dev/null
```

ヒットした場合:
- これから触る予定のファイルを Phase 1-3 で取得した OPEN PR のファイル一覧と突合する
- 衝突がある場合、**ユーザーに「先方 PR のマージ待ち / 並走 / 統合」のどれを取るか確認**してから Phase 3 に進む
- プロジェクト側の詳細手順は `CLAUDE.md「コンフリクトしたファイル」セクション` を参照

ヒットしないリポジトリでは:
- 衝突 PR の有無のみチェックし、衝突 PR があれば情報提示してユーザー判断を仰ぐ。無ければそのまま Phase 3 へ

## Phase 3: worktree 作成

```bash
BRANCH="feature/profile-cache-headers"   # 命名規約（rules: always/naming/commit-branch）に従って決定
WT="$WORKTREE_ROOT/$BRANCH"
git -C "$REPO" worktree add -b "$BRANCH" "$WT" "origin/$DEFAULT_BRANCH"
echo "$SLOT" > "$WT/.port-slot"   # Phase 1 で確定したスロット番号（1〜5）を書き込む
grep -qxF '.port-slot' "$REPO/.gitignore" 2>/dev/null || echo '.port-slot' >> "$REPO/.gitignore"
git -C "$REPO" add .gitignore
git -C "$REPO" commit -m "$(cat <<'EOF'
【設定】.gitignore に .port-slot を追加

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

- `-b` で新規ブランチ作成と worktree 生成を同時に行う
- 親ディレクトリは `git worktree add` が自動作成する
- 既に同名ブランチや同名パスがある場合は失敗する。エラーをユーザーに提示して判断を仰ぐ（**強制削除しない**）。復旧手順は `references/detailed-procedures.md` を参照
- `.port-slot` はポート管理規約（`~/.claude/rules/always/local-environment/port-management/rule.md`）のスロット割当方式に従う。1 行・数字のみ。`.gitignore` に未登録なら追加する

## Phase 4: 作業

以後の作業は `cd "$WT"` で worktree 内に閉じる:

```bash
cd "$WT"
```

- プロジェクト側 CLAUDE.md に「単機能フロー」「バルクフロー」「メンテナンスフロー」のいずれかが定義されている場合、ユーザー指示の内容に該当するフローを選んでそのフローの手順に従う
- 3 種ともに定義が無いリポジトリでは、TDD の 3 ステップ（テストを先に書く → 最小実装で通す → リファクタリングする）で進める
- pre-commit / pre-push フックは worktree でも自動的に効く（`.git` がリンク参照されるため）
- E2E テスト・launching-<project>-dev-servers 等のプロジェクト固有スキルが必要な場合は CWD を `$WT` に向ける
- rebase 競合が発生した場合、プロジェクト側 CLAUDE.md に「コンフリクト解消プロトコル」見出しがあればそちらを参照する。無い場合は `git status` で競合ファイルを特定し編集 → `git add` → `git rebase --continue` の標準手順を実行する
- 反復はプロジェクト側コンフリクト解消プロトコルに委譲。
- コミットは Skill ツールで `grouping-commits` を起動して行う

## Phase 5: PR 作成

push と PR 作成は外部リモートに影響する副作用を伴う。実行前に `AskUserQuestion` でユーザーの承認を得てから push する。

**⚠️ 実行前に必ずユーザー承認を取ること:**

`AskUserQuestion` ツールで以下を確認してから実行する:
- 「`git push -u origin <branch>` を実行してよいか？（リモートリポジトリに変更が反映される）」
- 選択肢: 「実行する」「キャンセル」

```bash
cd "$WT"
git push -u origin "$BRANCH"
```

その後、`$HAS_GH` の値で分岐する:

- `yes`（GitHub リモートあり）: Skill ツールで `formatting-pr` を起動して本文を整形し、`gh pr create` を実行する（該当スキルが利用可能でない場合は、基本的な手動操作で代替する）。戻り値の PR 番号と URL をユーザーへの完了報告に含める
- `no`（GitHub 以外）: ユーザーに「このリポジトリは GitHub に紐付いていません。push のみ完了しました」と通知して停止する

**自動マージまで一気に通したい場合（任意）**

PR 作成までで止めずに「警告/critical の自動修正 → 自動マージ」まで委譲したい時は、本 Phase の `formatting-pr` の代わりに `auto-ship` スキルを Skill ツールで起動する（該当スキルが利用可能でない場合は、基本的な手動操作で代替する）。auto-ship は内部で grouping-commits / formatting-pr / fixing-review-findings を Phase 1〜5 で順に呼び、PR 作成からマージまで自走する。手動実装フローの最終工程をワンショット化したい時に有効。本フローと auto-ship のどちらを選ぶかは「PR 作成後に手動レビューを挟みたい」かどうかで判断する。

## Phase 6: 後片付け（PR 作成完了時点）

worktree 専用のポート・コンテナ・ボリュームを起動していた場合、`git worktree remove` の前に後始末する（ポート管理規約: `~/.claude/rules/always/local-environment/port-management/rule.md`）。ポート kill・コンテナ/ボリューム停止の具体手順は `references/cleanup-procedures.md` の「Phase 6: 後片付け詳細」を参照する。

後始末が完了してから `git worktree remove` する:

```bash
cd "$REPO"
git -C "$REPO" worktree remove "$WT"
git -C "$REPO" worktree prune
```

- ローカルブランチ自体は `origin` に push 済みなので残しても消してもよい。**残す**を既定にする（Phase 7 の再 checkout で再利用できる）
- `git -C "$REPO" branch --show-current` でメイン作業ツリーが `$DEFAULT_BRANCH` にいることを確認してユーザーに報告
- `git worktree remove` が拒否した場合は、未コミット差分の有無を確認する。push 済みなら `--force` で再試行する。push 漏れがある時はユーザーに提示して指示を仰ぐ。復旧手順は `references/detailed-procedures.md` を参照する。

## Phase 7: レビュー指摘で再作業が必要になった時

PR 作成済みで worktree を畳んだ後にレビュー指摘が来た場合、既に push 済みのブランチを再 checkout してから修正 → push → Phase 6 を再実行する。具体的な再 checkout 手順は `references/cleanup-procedures.md` の「Phase 7: 再 checkout 手順」を参照する。

## 必ず実施する段階・条件付き段階

| Phase | 必ず実施 / 条件付き | 条件 |
|------|------------------|------|
| Phase 1 | 必ず | — |
| Phase 2 | 条件付き | プロジェクト側 CLAUDE.md に「コンフリクトしたファイル」見出しがある場合のみ実施。それ以外は OPEN PR の存在チェックのみ |
| Phase 3 | 必ず | — |
| Phase 4 | 必ず | — |
| Phase 5 | 必ず（GitHub 以外は push まで） | — |
| Phase 6 | 必ず | — |
| Phase 7 | 必要時のみ | レビュー指摘の修正タスク発生時 |
| **Goal** | worktree が作成され、PR が作成（または push）され、worktree が正常に後片付けされている | — |

## 他スキルとの連携

| スキル | 役割 |
|------|------|
| 命名規約（rules: always/naming/commit-branch） | ブランチ名の prefix・slug 規約。本スキルから Phase 3 で参照 |
| `grouping-commits` | Phase 4 のコミット段階で呼び出す |
| `orchestrating-dev-flow` | PR 整形は同スキルの `references/module-formatting-pr.md`、レビュー指摘修正は `references/module-fixing-review-findings.md` に従う（旧 formatting-pr / fixing-review-findings スキルは 2026-07-02 統合で吸収） |
| `reviewing-single-pr-with-inline-comments` | `/tmp/pr-<N>-...` で PR レビュー用 worktree を切る別目的スキル。本スキルとは併存（同時に動く場面なし） |
| `managing-github-issues`（verify モード） | issue ベースのブランチ（`issue-<N>` 形式）作業時に併用される。本スキルの `<prefix>/<slug>` 形式とは別系統 |
| `launching-<project>-dev-servers` / `test-e2e` | Phase 4 でアプリ起動・E2E テストを行うタスク（UI 変更・画面追加・E2E テスト追加）の時のみ呼び出す。CWD を `$WT` に向ける |

## 並行委任時の事前準備

複数のサブエージェントが同一リポジトリで並行作業する場合は、メインセッション（呼び出し元）が本スキルで worktree を 1 本だけ作成し、そのパスを全サブエージェントの委任プロンプトにベタ書きで渡す。各サブエージェントが個別に worktree を作成することを禁止する（変更が複数の worktree に分散し、統合・マーカー生成・コミットが複雑化するため）。ファイル重複がない並行編集のみ許可する。同一ファイルを複数エージェントが編集する場合は worktree を分けず直列で委任する。

---

## 復旧モード（撤去済み・歴史的記述）

`<repo>/.claude/worktrees/wtN` + `.slot-pool.json` による slot 運用は 2026-06-28 に撤去済み。全リポジトリの worktree は `~/Projects/worktrees/<repo>/<branch>/` の中央規約（本 SKILL.md）に一本化されており、本節に記載していた wt1〜wt3 台帳復旧手順（Phase R1〜R4）は現存する基盤に対応しない。異常発生時は Phase 6・`references/detailed-procedures.md` の通常復旧手順に従う。

---

## 完了報告

`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（作業報告型）に従う。
固有の検証行: worktree パス・PR URL

## 完了条件

| Phase | 条件 |
|---|---|
| Phase 1 | 作業ツリーの汚れ・OPEN PR・ポートスロットを確認し、着手可否が確定している |
| Phase 2 | コンフリクトしたファイルの衝突有無を確認し、必要ならユーザー判断を得ている |
| Phase 3 | worktree が作成され `.port-slot` が書き込まれている |
| Phase 4 | 実装が完了しコミットが作成されている |
| Phase 5 | push 済みで、PR が作成されている（GitHub 以外は push 完了） |
| Phase 6 | ポート・コンテナ等の後始末を終え worktree が後片付けされている |
| Phase 7 | レビュー指摘が解消され、再度 push・後片付けが完了している（発生時のみ） |
| **Goal** | worktree が作成され、PR が作成（または push）され、worktree が正常に後片付けされている |

## 予想を裏切る挙動

- `git worktree remove` は `--force` なしだと未コミット変更があれば失敗する — 削除前に変更を commit または stash する
- リポジトリの `.claude/skills`・`.claude/hooks`・`.claude/settings.json`・`.mcp.json`・`.git/config` 等は Claude Code CLI 組み込みの sandbox 保護対象であり、メイン作業ツリーへの書き込みは常に拒否される（`dangerouslyDisableSandbox: true` でのみ回避可能。プロジェクト設定での恒久的な除外は不可能）。git remote が存在せず PR を作れないリポジトリで worktree ブランチを main へ直接 merge する場合、この保護パスへの書き込みが発生すると Bash ツールの `dangerouslyDisableSandbox: true` と対話セッションでのユーザー承認が必須になる。サブエージェント経由でも Auto Mode の自動拒否は回避できない（`.claude/agents/*.md` の `permissionMode` frontmatter は Auto Mode 下では無視され、親セッションと同じ classifier ルールで評価されるため）。この種の merge 作業は対話セッションで実行し、Auto Mode では実行しないこと。
- `remind-worktree-cleanup.sh`（Stop hook）は「ブランチ先端が main と一致 & クリーン」を後片付け対象と判定するため、作成直後でコミットが載る前の作業中 worktree にも偽陽性で発火する（2026-07-17 実測・同一セッションで5回）。実装コミットが載れば解消する。作業中 worktree はこの案内で削除しないこと

## 設計判断

### check-worktree-required.sh

**必要性**: worktree 外でのコード編集を PreToolUse(Write|Edit|MultiEdit|NotebookEdit) で機械的に block するには、hook スクリプトとして常駐させる必要がある。worktree 判定ロジック（git rev-parse --show-toplevel と .git ファイルの実在確認）は複数の条件分岐を持ち、settings.json のインラインには収まらない。

**代替案を採用しなかった理由**:
- Bash ツール直叩き: PreToolUse イベントにバインドできない
- 既存 Makefile 拡張: リポジトリ横断で適用するため単一プロジェクトのビルド設定には依存させない

**保守責任者**: 人手（ユーザー）

**廃棄条件**: Claude Code 本体が worktree 強制を標準機能として提供した時

### remind-worktree-cleanup.sh

**必要性**: マージ済み worktree の放置を UserPromptSubmit hook で検知し、クリーンアップを促す。worktree 一覧の走査・マージ判定・差分計算の複合ロジックを持ち、settings.json のインラインには収まらない。

**代替案を採用しなかった理由**:
- Bash ツール直叩き: UserPromptSubmit イベントにバインドできない
- advisory のみ（block なし）の設計のため、permissions.deny は不適切

**保守責任者**: 人手（ユーザー）

**廃棄条件**: worktree のライフサイクル管理が自動化され、手動クリーンアップが不要になった時

## 参照資料

| ファイル | 内容 |
|------|------|
| `references/detailed-procedures.md` | 各 Phase の Bash 完全版・worktree remove 失敗時の復旧手順・非 GitHub リモートのフォールバック |
| `references/cleanup-procedures.md` | Phase 6 のポート kill・コンテナ/ボリューム停止の具体手順、Phase 7 の再 checkout 手順 |

## チェックリスト（実装着手前）

- [ ] `$REPO` `$DEFAULT_BRANCH` `$WORKTREE_ROOT` `$HAS_GH` を取得した
- [ ] Phase 1 の 4 項目を並列実行した
- [ ] ブランチ名は命名規約（rules: always/naming/commit-branch）の prefix（`feature/` 等）に従った
- [ ] `git worktree add -b "$BRANCH" "$WT" "origin/$DEFAULT_BRANCH"` で `-b` を付けた（Phase 7 のみ `-b` なし）
- [ ] PR 作成後、`git worktree remove` で worktree を畳んだ
- [ ] メイン作業ツリーが `$DEFAULT_BRANCH` に戻っていることを確認した
