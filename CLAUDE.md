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
node scripts/sync-payload.mjs --list             # manifest の全マッピングを表示
node scripts/sync-payload.mjs --check            # 乖離検知（書き込みなし）。乖離があれば exit 1
node scripts/sync-payload.mjs --check-artifacts  # payload/ 配下の禁止アーティファクト残存を検知
node scripts/sync-payload.mjs --apply            # 乖離を正本の内容で payload に反映（manual は書かない）
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

---

## payload禁止アーティファクト機構（配布してはいけない実行時生成物の除外）

正本側には正当に存在するが payload には決して同梱してはいけないファイル種別
（`orchestrating-dev-flow` の `flow-context.yml` 等、プロジェクトローカルな実行時生成物）
が mirror 経由で payload に混入する事故が発生した。`scripts/payload-artifacts.json`
に禁止パターンの正本を持ち、`sync-payload.mjs` の mirror コピーと独立スキャン
（`--check-artifacts`）の両方でこれを弾く。

### 禁止パターンデータファイル

`scripts/payload-artifacts.json` の `names`（パスの各セグメントとの完全一致）/
`pathSuffixes`（相対パス末尾一致）に追加することで、今後同種の事故パターンを
機械的に除外できる。

### mirror コピー時の除外（予防）

`sync-payload.mjs` は mirror の src 側 walk 結果からのみ禁止パターンを除外する
（dst 側は除外しない非対称設計）。これにより新規混入を防ぎつつ、既に payload に
紛れ込んでいるファイルは "extra" drift として `--check`/`--apply` の通常経路で
検知・削除される。

### 独立スキャン（是正・保険）

`node scripts/sync-payload.mjs --check-artifacts` は manifest と無関係に
`payload/` 配下全体を走査し、禁止パターンへの一致を検出する（exit 1）。
manual mapping 経由や手動コピーでの混入も捕捉する。

### commit 時 block（`[PAYLOAD-ARTIFACTS-BLOCK]`）

`scripts/check-payload-artifacts.sh`（PreToolUse(Bash)）が `git commit` 実行前に
`--check-artifacts` を走らせ、該当があれば exit 2 で block する。

1. stderr の FOUND 一覧を確認する
2. 該当ファイルを payload/ から削除する（`git rm`）
3. 正本側の mirror mapping が構造的に混入源になっている場合は
   `scripts/payload-artifacts.json` にパターンを追加する
4. 緊急口（常用禁止）: `CLAUDE_PAYLOAD_ARTIFACTS_SKIP=1 git commit ...`

### 設計判断

**必要性**: `flow-context.yml` は「元プロジェクトには正当に存在するが配布物としては
不適切」というファイル種別であり、`sync-payload.mjs --check` の乖離検知（正本と
一致しているか）では原理的に検知できない（正本側にも存在するため乖離ではない）。
種別そのものを禁止する別レイヤーが必要であり、`scripts/check-payload-artifacts.sh`
（commit 時 block）と `sync-payload.mjs --check-artifacts`（独立スキャン）を新設した。

**代替案を採用しなかった理由**:
- `EXCLUDE_NAMES`/`EXCLUDE_SUFFIXES` への追記（既存の対称除外の流用）:
  対称除外だと dst に既に存在する漏洩ファイルを検知・削除できない
  （比較対象から両側とも外れて黙って放置される）ため不採用
- `--check` への統合: 「正本との乖離」と「配布可否の種別判定」は原因・対処が異なり、
  統合すると block メッセージの意味が曖昧になるため独立コマンドに分離
- `sync-manifest.json` の mapping 側で個別に除外設定を持たせる:
  mapping ごとに除外リストが分散し、新しい禁止パターンを見つけるたびに全 mapping
  を確認する必要が生じる。単一の正本データファイルに集約する方が保守しやすい

**保守責任者**: 人手（ユーザー）。新しいプロジェクトローカル実行時生成物のパターンを
発見した場合は `scripts/payload-artifacts.json` に追加する。

**廃棄条件**: payload の配布方式が別の仕組みに置き換わった時、または
`orchestrating-dev-flow` 等の実行時生成物がプロジェクト固有 gitignore で完全に
隔離され mirror 元に一切出現しなくなった時。
