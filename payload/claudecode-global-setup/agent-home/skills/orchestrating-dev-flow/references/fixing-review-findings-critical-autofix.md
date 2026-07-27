# critical 自動修正試行（Phase 4-C 詳細）

SKILL.md Phase 4-C の手順。

> **発火条件**: `critical_list` が 1 件以上ある時。Phase 4（warning 修正）完了後に同 worktree で続けて実行する。
> **目的**: AI が判断できる範囲の critical（セキュリティ・データ消失・既知バグ）を自動コミットして再レビューに乗せる。

`loop_critical`（初期値 0）で再試行回数を管理する。

## 4-C-1. critical を 1 件ずつ分類

各 `critical` について以下の自己判定を行う。

| 観点 | 自動修正 (apply) | skip → 設計級として保留 |
|------|----------------|------------------------|
| セキュリティ（`eval()` 直書き・テンプレ未エスケープ・秘密直書き等） | ✓ | — |
| データ消失（無条件 DELETE / DROP / `git reset --hard` 等） | ✓ | — |
| 既知バグ（null 参照・型不整合・例外握りつぶし） | ✓ | — |
| 公開 API シグネチャ破壊・スキーマ破壊（DB マイグレーション要件） | — | ✓ |
| アーキテクチャ刷新を要する | — | ✓ |
| 仕様議論を要する（要件解釈が分かれる） | — | ✓ |

判定不能な場合は安全側に倒して skip する（=設計級扱い）。

## 4-C-2. apply 対象の修正適用

```
各 critical（apply 対象）について:
  1. {worktree_path}/{file} を Read する
  2. 指摘の {line} 周辺のコードと前後文脈を確認する
  3. {fix} の内容を Edit ツールで適用する（最小差分・周辺保持）
  4. 修正できた場合は critical_applied_list に追加
  5. 適用できなかった場合（コードが変わっている・周辺破壊リスクなど）は critical_skipped_list に追加
```

設計判断が要るケースを発見した場合、その場で skip して `critical_skipped_list` に「skip 理由」付きで記録する。

## 4-C-3. 修正コミット作成と再 push

```bash
cd "$WORKTREE_PATH"
git add .
git commit -m "fix: critical 指摘を自動修正"
git push origin HEAD:$HEADBRANCH
head_sha=$(git rev-parse HEAD)
```

PreToolUse hook（`[NAMING]` `[PUBLISH-AUTHOR]` `[PUBLISH-SAFETY-FULL]`）は通常通り発火するため、命名規約に沿うコミット message を選ぶ。

## 4-C-4. skip 件数 0 件のチェック

- `len(critical_skipped_list) == 0` → Phase 5 へ進む（layers.yml の各レイヤーの lint / test / type_check 実行）
- `len(critical_skipped_list) > 0` かつ `loop_critical == 0` → `loop_critical++` → 次の Phase 8（再レビュー）で判定。設計級が混じった状態でも残り critical の再レビューを経て Phase 4-C へ戻れる
- `len(critical_skipped_list) > 0` かつ `loop_critical >= 1` → 断念フラグを立てて Phase 8 へ進む。Phase 8-2 で残存 critical の最終判定を行う
