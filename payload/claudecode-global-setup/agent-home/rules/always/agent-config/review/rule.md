# managing スキル実行ゲート（MANAGING-REVIEW-GATE）

managed ディレクトリ（skills/、rules/、routines/、tools/hooks/）のファイル編集時に、統合スキル `managing-agent-configs` の該当種別でのレビュー・テスト実行を機械強制する規約。

## 対象ディレクトリと種別の対応

`managing-agent-configs` は種別（asset_type）を引数に取る統合ハブ。旧 `managing-skills` / `managing-hooks` / `managing-rules` / `managing-routines` / `managing-subagents` を吸収した。

監視パスの定義は `~/agent-home/tools/hooks/shared/marker-path.sh` の `managed_asset_type()`。下表と乖離した場合は関数側を正とする。

| ファイルパターン | 対応する asset_type | 実行コマンド |
|---|---|---|
| `skills/*/SKILL.md` | skills | `Skill("managing-agent-configs")` を種別 skills で実行 |
| `skills/*/scripts/*.sh` | skills | 同上 |
| `skills/*/references/**` | skills | 同上 |
| `.claude/rules/*/rule.md` | rules | `Skill("managing-agent-configs")` を種別 rules で実行 |
| `.claude/rules/*/*.sh` | rules | 同上 |
| `.claude/rules/**/prh.yml`（グローバル・プロジェクト両方） | rules | 同上 |
| `routines/*/ルーティン設計書.md` | routines | `Skill("managing-agent-configs")` を種別 routines で実行 |
| `tools/hooks/*.sh` | hooks | `Skill("managing-agent-configs")` を種別 hooks で実行 |

## 機械強制

| timing | スクリプト | 注入タグ | 挙動 |
|---|---|---|---|
| PostToolUse(Write\|Edit\|MultiEdit) | `check-managing-configs-review-needed.sh` | `[MANAGING-REVIEW-REQUIRED]` | managed ファイル編集を検知し advisory 注入。同一セッション内で対応する managing スキルが発火済みならスキップ（exit 0） |
| PostToolUse(Write\|Edit\|MultiEdit) | `check-managing-configs-review-needed.sh` | `[MANAGING-GATE-DISABLED]` | `marker-path.sh` が見つからない場合、マーカー処理をスキップした旨を自己申告して exit 0（fail-open） |
| PreToolUse(Bash) | `check-managing-configs-commit-gate.sh`（rules-bash-runner 経由） | `[MANAGING-COMMIT-BLOCK]` | `git commit` 時に staged ファイルを検査し、managed ファイルのテスト完了マーカーがない、または stale（マーカー記録後に再編集）なら exit 2 で block。report欠落・PASS宣言なし・report鮮度不一致・reportハッシュ不一致も検知対象 |
| PreToolUse(Bash) | `check-managing-configs-commit-gate.sh`（rules-bash-runner 経由） | `[MANAGING-GATE-DISABLED]` | `marker-path.sh` が見つからない場合、判定不能として git commit 全体を exit 2 で block（fail-closed） |

## 再帰防止

PostToolUse hook は `~/agent-home/sessions/.skill-log/${session}.jsonl` を参照し、`"skill":"managing-agent-configs"` が当該セッション内で既に発火済みであれば advisory を抑制する。managing-agent-configs 実行中の自身のファイル編集で advisory が繰り返し注入されることを防ぐ。

## マーカー機構

### needed マーカー

PostToolUse hook が managed ファイル編集を検知した時点で `managing-agent-configs-${asset_type}-needed` マーカーを書き出す（空 touch）。

### test-passed マーカー（レポート必須・ハッシュ照合方式）

`managing-agent-configs` のテスト全項目 PASS 時に、スキル実行者は次の2ファイルを書き出す。

1. **report ファイル**（`managing-agent-configs-${asset_type}-report.md`）: review Phase のレポート（CRITICAL/WARN/INFO件数）と test Phase の実行検証結果を実際の内容で記載する。末尾に `REVIEW-TEST-VERDICT: PASS` の1行を含める（CRITICAL 0件かつtest実行検証で要件達成の場合のみ）。この行が無い・reportが無い場合はcommitできない
2. **test-passed マーカー**（`managing-agent-configs-${asset_type}-test-passed`）: 当該種別の managed ファイルそれぞれの staged 内容ハッシュ（`shasum -a 256` 形式）に加え、report ファイル自体のハッシュを `REPORT_SHA256=<sha256>` の形式で先頭行に記録する

commit gate は次の条件がすべて満たされた場合にのみ commit を許可する。

1. test-passed マーカーが存在し、かつ空でない
2. report ファイルが存在し、かつ空でない
3. report ファイル内に `REVIEW-TEST-VERDICT: PASS` の行が存在する
4. report ファイルの mtime が needed マーカーの mtime より新しい（needed マーカーは編集の都度 touch で更新されるため、report 作成後に対象ファイルが再編集されると needed の方が新しくなり stale 判定される）
5. report ファイルの現在のハッシュが test-passed マーカー内の `REPORT_SHA256=` 行と一致する
6. staged の managed ファイルごとに、現在の staged 内容のハッシュがマーカー記録と一致する（`git show ":$f" | shasum -a 256` で再計算）

**この設計の意図**: 旧方式（ハッシュ列挙のみ）は、エージェントが実際に review/test を実行したかどうかを区別できず、同一の bash コマンドを叩くだけで commit ゲートを通過できてしまう欠陥があった。report ファイルの実在・内容・鮮度・ハッシュ紐付けを要求することで、「何を検証し、どう判定したか」を文章として書き残すことを強制し、単純なコマンド一発でのなりすまし合格を防ぐ。report の内容そのものが虚偽である可能性は排除できないが、監査可能な記録を残すことで検証の実体化を図る。

マーカーに記録があるが staged に存在しないファイルは無視する（部分 commit を許容する）。旧方式（report無し・ハッシュ列挙のみ）のマーカーは `report欠落` として block される（互換レイヤは設けない）。

review-gate は編集検知時に以前の test-passed / report マーカーを削除しない（削除すると新しいハッシュ・reportで再テストしても照合対象が消えるため）。stale 判定は commit-gate 側の各種チェックが担う。

### マーカーのライフサイクル

- 書き出し先: `marker_path` ヘルパーに従い、worktree 内または `/tmp/claude-hooks/${session}/` に配置
- セッション終了時に `cleanup-session-markers.sh`（SessionEnd hook）が自動削除

## 違反検知時の手順

### `[MANAGING-REVIEW-REQUIRED]` 受信

1. 注入メッセージ内の種別（asset_type）を確認する
2. `Skill("managing-agent-configs")` を該当種別で実行する（create → review → test の 3 モード連鎖がデフォルトで走る）
3. テスト PASS 後にハッシュ記録マーカーが書き出される

### `[MANAGING-COMMIT-BLOCK]` 受信

1. block メッセージ内の未完了種別・stale ファイル（複数の場合あり）を確認する
2. 各種別で `Skill("managing-agent-configs")` を実行する
3. テスト PASS 後にマーカーが書き出され、再度 `git commit` を実行する

### `[MANAGING-GATE-DISABLED]` 受信

1. `~/agent-home/tools/hooks/shared/marker-path.sh` が存在するか確認する（agent-home の配置崩れの可能性）
2. review-gate（PostToolUse）からの場合は fail-open のため作業は継続できるが、マーカー処理がスキップされている旨を認識する
3. commit-gate（PreToolUse）からの場合は fail-closed で commit 自体が block される。lib を復旧してから再実行する

## 設計判断

### check-managing-configs-commit-gate.test.sh

**必要性**: `check-managing-configs-commit-gate.sh`（旧 `managing-commit-gate.sh`）は managed ファイルの commit を fail-closed で制御する PreToolUse hook であり、C1〜C18 の 18 ケース（stale 検知・report 欠落・ハッシュ不一致・fail-loud 等）を網羅する回帰テストが既に存在する。hook 本体のリネームに追従してテストファイルもリネームし、内部の `SCRIPT=` パス参照とヘッダコメントを更新した。この hook は commit gate として fail-closed で動作するため、ロジック変更時に回帰テストを経ずに commit すると、正当な commit が誤って block される、または managed ファイルが無審査で commit される事故につながる。

**代替案を採用しなかった理由**:
- Bash ツール直叩き: 18 ケース（複合コマンド分割・stale 判定・ハッシュ照合を含む）を毎回手動で組み立てて実行するのは非現実的で、hook 修正のたびに同じ検証作業を繰り返すことになる
- 既存 Makefile ターゲット拡張: `~/.claude/rules/` 配下に Makefile は存在せず、新規導入は本テスト専用の依存を増やすだけになる
- package.json scripts 追加: 同様に本ディレクトリはビルド設定を持たない

**保守責任者**: 人手（ユーザー）。`check-managing-configs-commit-gate.sh` のロジックを変更するたびに本テストのケースを追従させる。

**廃棄条件**: `check-managing-configs-commit-gate.sh` 自体が廃止された時。

## プロジェクト上書き

- 上書き可否: 一律適用
- 理由: managed ディレクトリのレビュー強制は agent-home / グローバル設定資産に対する枠組みであり、受け口の対象外

設計判断・経緯の記録は同ディレクトリの `design-notes.txt` を参照（非注入サイドカー）。

## 関連

- `~/agent-home/skills/managing-agent-configs/SKILL.md` — スキル/hooks/rules/ルーティン/サブエージェント統合管理ハブ（旧 managing-skills / managing-hooks / managing-rules / managing-routines / managing-subagents を統合）
- `~/.claude/rules/always/placement/file-guard/rule.md` — マーカー書き出し先規約
- `~/.claude/rules/always/session/infra/rule.md` — スキル発火ログ記録
