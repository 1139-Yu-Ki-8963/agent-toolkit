# 自動再レビュー・マージ判定（Phase 8 詳細）

SKILL.md Phase 8 の手順。Phase 7 のコメント投稿完了後に実行する。
`loop_count`（初期値 0）で無限ループを防止する。

## 8-1. reviewing-prs サブエージェントを起動

```
Task(worker-sonnet,
  "reviewing-prs スキルを使って PR #NUMBER を再レビューせよ。
   Phase 1（PR選択）はスキップし、PR番号 NUMBER を直接使うこと。
   worktree が $WORKTREE_PATH に存在するので再利用すること
   （削除・再作成しない）。Phase 9（worktree削除）は実行しないこと。
   結果を {critical_list, warning_list, suggestion_list, tests_passed} の形式で返せ。")
```

## 8-2. 結果判定

| 条件 | 処理 |
|------|------|
| 重大な問題・警告なし（提案のみ含む） | Phase 8-3（自動マージ）へ。提案は任意改善のため承認扱い |
| 警告あり かつ `loop_count < 2` かつ critical なし | `loop_count++` → Phase 3 に戻る |
| 警告あり かつ `loop_count == 2` かつ critical なし | 断念を報告 → Phase 9 へ |
| critical あり かつ `loop_critical < 2` | `loop_critical++` → Phase 4-C に戻り再修正試行 |
| critical あり かつ `loop_critical == 2` | 断念を報告 → Phase 9 へ |
| critical あり かつ 全件 `critical_skipped_list`（設計級のみ） | 断念を報告 → Phase 9 へ。`fixing-review-findings-splitting-commits.md` の手順案内も含める |

断念時の報告フォーマット:
```
2 回の追加修正を試みましたが、以下の指摘が残存しています。
手動での対応をお願いします。

残存 critical:
- {指摘1}（skip 理由: {設計判断要件 等}）
- {指摘2}

残存警告:
- {指摘1}
- {指摘2}
```

## 8-3. 自動マージ（ユーザー承認なし）

警告がすべて解消された後は、ユーザーへの確認を挟まず自動でマージする。

> **重要**: `--admin` は **branch protection を bypass** するフラグであり、CI 失敗を強制マージするフラグではない。保護ルールが無いリポジトリでは `--admin` は no-op なので、デフォルトで付けてはならない。

> **中断条件（マージしない）**: 以下のいずれかなら自動マージを中断し、ユーザーに報告して Phase 9 へ進む。
> - required check が **code 起因 fail**（テスト失敗・型エラー・layers.yml の各レイヤーの lint エラー等）
> - PR がコンフリクト状態（base との merge ができない）
> - 上記以外のマージエラー（権限不足・タイムアウト等）
>
> **critical 残存時の扱い**: `critical_skipped_list` のみが残った場合は Phase 8-2 で「断念を報告 → Phase 9 へ」分岐に倒れるため、本 Phase に到達することはない。安全側設計として Phase 8-3 開始時に `len(remaining_critical) == 0` を assertion 的に確認する。

### 8-3-1. CI ステータスと保護ルール確認

```bash
# 保護ルール存在チェック（HTTP ステータスで判定）
PROTECTION_HTTP=$(gh api -i "repos/OWNER/REPO/branches/$BASE_BRANCH/protection" 2>/dev/null \
  | head -1 | awk '{print $2}')
# 200            → 保護ルールあり
# 403 / 404      → 保護ルールなし（GitHub Free private や未設定）

# CI ステータス確認
gh pr checks NUMBER 2>&1
```

判定マトリクス:

| 保護ルール | CI 状況 | マージ方法 |
|----------|---------|----------|
| なし（403/404） | 任意（pass / fail / pending / 未実行） | 通常 `--merge`（`--admin` 不要） |
| あり（200） | 全 pass | 通常 `--merge` |
| あり（200） | required check が課金停止 / pending / 未実行 | `--admin` を初手から使用（保護ルールが block するため） |
| あり（200） | required check が code 起因 fail | **マージ不可** → ユーザーに報告して Phase 9 へ |

### 8-3-2. マージ実行（自動・フォールバック型）

判定マトリクスに従い、AskUserQuestion を挟まず即座にマージを実行する。

```bash
LOG=/tmp/merge_NUMBER.log

# 判定マトリクスにより初手のフラグを決定
if [ "$PROTECTION_HTTP" = "200" ] && \
   gh pr checks NUMBER 2>&1 | grep -qiE 'pending|queued|skipping|no checks|expected'; then
  # 保護ルールあり + 必須 check が pending/未実行 → 初手から --admin
  MERGE_FLAGS="--merge --admin"
else
  # それ以外 → 通常マージ
  MERGE_FLAGS="--merge"
fi

# プロジェクト固有のプレマージスクリプト（layers.yml の pre_merge_script で定義している場合のみ実行）
# 例: DB マイグレーションを本番環境に適用するスクリプト等
if [ -f "layers.yml" ]; then
  pre_merge_script=$(yq '.pre_merge_script // empty' layers.yml 2>/dev/null)
  if [ -n "$pre_merge_script" ] && [ -f "$pre_merge_script" ]; then
    bash "$pre_merge_script" 2>&1 | tee -a "$LOG"
    apply_rc=${PIPESTATUS[0]}
    if [ "$apply_rc" -ne 0 ]; then
      echo "プレマージスクリプトで失敗（exit=$apply_rc）。マージを中止します" >&2
      # → エラー内容をユーザーに報告して Phase 9 へ
      exit 2
    fi
  fi
fi

# マージ実行
if gh pr merge NUMBER $MERGE_FLAGS 2>&1 | tee "$LOG"; then
  echo "マージ成功"
else
  # 失敗内容を判別
  if grep -qiE 'required (status check|review|signature)|branch protection|protected branch' "$LOG"; then
    # 保護ルール起因の block → admin で再試行（初手が --admin なしの場合の保険）
    gh pr merge NUMBER --merge --admin 2>&1 | tee "$LOG" || {
      # admin でも失敗した場合は中断
      echo "マージ失敗（admin でも block）" >&2
      # → エラー内容をユーザーに報告して Phase 9 へ
    }
  else
    # 別の理由（コンフリクト・権限不足・タイムアウト・code 起因 CI 失敗等）
    # → エラー内容をユーザーに報告して Phase 9 へ
    echo "マージ失敗" >&2
  fi
fi

# マージ後確認
gh pr view NUMBER --json state,mergedAt
```

`state == MERGED` を確認してから Phase 9 へ進む。
マージ失敗時はエラー内容を chat に 1〜2 行で報告し、Phase 9 で worktree を削除して終了する。
