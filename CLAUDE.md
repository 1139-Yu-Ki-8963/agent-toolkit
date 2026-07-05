# agent-toolkit / CLAUDE.md（リポジトリ作業手順書）

このファイルは **agent-toolkit リポジトリを clone して Claude Code を起動した AI 向けの手順書** です。
配布される CLAUDE.md の実体は `payload/claude-config/CLAUDE.md` にあります（二役分離）。

## 設置マッピング

| payload パス | 設置先 | 備考 |
|---|---|---|
| `payload/agent-home/` | `~/agent-home/` | ディレクトリ全体をミラー |
| `payload/claude-config/CLAUDE.md` | `~/.claude/CLAUDE.md` | 既存があれば上書きしない |
| `payload/claude-config/settings-hooks.json` | `~/.claude/settings.json` | 既存の hooks セクションへ merge |

設置・更新の実作業は `scripts/install.mjs` が担う。インターフェース:

```
node scripts/install.mjs --doctor    # 前提診断（Node.js / 必須コマンド / 既存設定の確認）
node scripts/install.mjs --diff      # 設置予定を差分で提示（書き込み禁止）
node scripts/install.mjs --apply     # 設置実行（settings.json はバックアップ後 merge）
node scripts/install.mjs --target <dir>   # テスト用: 設置先を <dir> に変更して実行
```

---

## 初回設定（新しい PC）

1. **前提診断**: `node scripts/install.mjs --doctor` を実行し、必須コマンドの不足や既存設定の競合を確認する
2. **差分確認**: `node scripts/install.mjs --diff` で設置予定の一覧をユーザーに提示し、承認を得る
3. **設置実行**: `node scripts/install.mjs --apply` を実行する
   - `~/.claude/settings.json` は自動バックアップ後に hooks セクションを merge する
   - `~/.claude/CLAUDE.md` が既存の場合は上書きせず、差分をユーザーに報告する
   - `--apply` の最後に `manage-portal.mjs generate` → `verify` を自動実行し、exit 0 を受け入れ判定とする
4. **hook 発火スモーク**: 設置後に `~/agent-home/skills/managing-agent-configs/SKILL.md` を 1 行編集し、`[MANAGING-REVIEW-REQUIRED]` advisory が注入されることを確認する

---

## 更新（2 回目以降）

1. `git pull` で最新を取得する
2. `node scripts/install.mjs --diff` で設置先との差分を提示する
   - **設置先にローカル改変がある場合は停止し、ユーザーに内容を報告する**（強制上書き禁止）
3. ユーザーの承認後に `node scripts/install.mjs --apply` を実行する
4. `manage-portal.mjs verify` が exit 0 で完了することを受け入れ判定とする

---

## このリポジトリで開発する人向け

リポジトリ直下の `.claude/settings.json` に gate hook 2 本が登録済みです。managed ファイル
（`payload/agent-home/skills/*/SKILL.md` 等）を編集すると `[MANAGING-REVIEW-REQUIRED]` が
advisory 注入され、テスト完了マーカーがない状態の `git commit` は exit 2 で block されます。

commit 前に `payload/agent-home/skills/managing-agent-configs/scripts/manage-portal.mjs verify`
を実行して 7 検査が全て PASS することを確認してから commit してください。

配布物の同期元は private リポジトリの agent-home です。AT への変更は agent-home 側の正本と
齟齬が生じないよう、design/ HTML と `references/` conventions.md の両方を更新してください。

---

## payload 同期機構（正本 → payload）

`payload/` 配下の一部ファイルは private 環境の正本（`~/agent-home/`・`~/.claude/`）のコピー
です。手動コピーによる二重管理を避けるため、`scripts/sync-manifest.json` に対応表を持ち、
`scripts/sync-payload.mjs` が乖離検知・同期を行います。

### インターフェース

```
node scripts/sync-payload.mjs --list    # manifest の全マッピングを表示
node scripts/sync-payload.mjs --check   # 乖離検知（書き込みなし）。乖離があれば exit 1
node scripts/sync-payload.mjs --apply   # 乖離を正本の内容で payload に反映（manual は書かない）
```

### manifest のモード

| mode | 意味 |
|---|---|
| `mirror` | ディレクトリ全体をミラー。src にのみ存在するファイルは追加、dst にのみ存在するファイルは削除対象 |
| `file` | 単一ファイルのバイト比較・コピー。mirror 配下を指す場合は overlay として扱われ、mirror 側の削除対象から除外される |
| `manual` | 意図的に正本と差分がある配布物（install 用テンプレート等）。`--check` は情報表示のみで失敗にせず、`--apply` は絶対に書き込まない |

### 運用ルール（重要）

**`sync-manifest.json` の mapping 追加（`mirror` / `file`）は public リポジトリへの公開判断
である。追加前に `~/agent-home/skills/reviewing-public-readiness/SKILL.md` に従って公開可否
レビューを行うこと。** manual mapping の追加は同梱物の存在を示すのみで公開判断を伴わないため
対象外。

### commit 時 block（`[PAYLOAD-SYNC-BLOCK]`）

`.claude/settings.json` に登録された `scripts/check-payload-sync.sh`（PreToolUse(Bash)）が
`git commit` 実行前に `sync-payload.mjs --check` を走らせ、乖離があれば exit 2 で block しま
す。受信した場合の対応:

1. stderr に出力された DRIFT 一覧を確認する
2. `node scripts/sync-payload.mjs --apply` で乖離を解消する
3. 差分を `git add` してから再度 `git commit` する
4. 緊急口（常用禁止）: `CLAUDE_PAYLOAD_SYNC_SKIP=1 git commit ...` で当該コマンドのみ検査を
   skip できる

新PC・`git clone` 直後など正本（`~/agent-home/`）が存在しない環境では hook・スクリプトとも
fail-safe で素通りします（乖離検知不能なため block しない）。

### 設計判断

**必要性**: payload/ は private リポジトリ agent-home の一部スキル・gate スクリプトのコピー
を同梱しているが、手動コピーの二重管理により `managing-review-gate.sh` /
`managing-commit-gate.sh` / `lib/marker-path.sh` の 3 ファイルが正本の更新に追従できず古いま
ま放置される事故が発生した。manifest 駆動の `--check` / `--apply` で同期状態を可視化し、
`git commit` 時の block（check-payload-sync）で乖離の commit を構造的に防止する。

**代替案を採用しなかった理由**:
- 手動コピーの継続: 今回の事故そのものであり再発が確実
- git submodule / subtree: private リポジトリを public リポジトリから参照する構成になり、
  意図しない private 情報の露出リスクが増す。payload は「公開可能と判断した範囲」を選択的に
  同梱する現行方式の利点を失う
- symlink: public リポジトリの clone 先（配布先の新 PC）には正本が存在しないため機能しない

**保守責任者**: 人手（ユーザー）。`sync-manifest.json` への mapping 追加時は公開可否レビュー
を実施し、正本側にファイルが増減した際は manifest を追従させる。

**廃棄条件**: payload の配布方式が別の仕組み（パッケージ配布・別リポジトリ分離等）に置き換
わった時。
