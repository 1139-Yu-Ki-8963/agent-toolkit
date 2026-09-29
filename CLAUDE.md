# agent-toolkit / CLAUDE.md(リポジトリ作業手順書)

このファイルは、agent-toolkit リポジトリを clone して Claude Code を起動した AI 向けの手順書である。配布物は `payload/` の下のスキル集で、利用者はフォルダを `~/.claude/skills/` へ複製するだけで使う。インストーラはない(2026-09-29 に bundle `claudecode-global-setup` とともに閉じた)。

## このリポジトリで開発する人向け

リポジトリ直下の `.claude/settings.json` に、`git commit` 前に走る hook が 2 本登録されている。

- `scripts/check-payload-sync.sh`: payload が正本と乖離していれば止める。
- `scripts/check-payload-artifacts.sh`: 配布してはいけない実行時生成物が payload にあれば止める。

payload を直接編集してはならない。正本(private な作業環境)を直し、`scripts/sync-payload.mjs --apply` で写す。

---

## payload 同期機構(正本 → payload)

`payload/` の中身は private 環境の正本(`~/agent-home/`、`~/Projects/` の各リポジトリ)のコピーである。手動コピーによる二重管理を避けるため、`scripts/sync-manifest.json` に対応表を持ち、`scripts/sync-payload.mjs` が乖離検知と同期を行う。

### インターフェース

```
node scripts/sync-payload.mjs --list             # manifest の全マッピングを表示
node scripts/sync-payload.mjs --check            # 乖離検知(書き込みなし)。乖離があれば exit 1
node scripts/sync-payload.mjs --check-artifacts  # payload/ 配下の禁止アーティファクトの残存を検知
node scripts/sync-payload.mjs --apply            # 乖離を正本の内容で payload に反映(manual は書かない)
node scripts/sync-payload.mjs --check --only payload/public-skills   # 1 つの配布物だけを対象にする
```

### manifest のモード

| mode | 意味 |
|---|---|
| `mirror` | ディレクトリ全体をミラー。src にのみ存在するファイルは追加、dst にのみ存在するファイルは削除対象 |
| `file` | 単一ファイルのバイト比較とコピー。mirror 配下を指す場合は overlay として扱い、mirror 側の削除対象から除外する |
| `manual` | 意図的に正本と差分がある配布物。`--check` は情報表示のみで失敗にせず、`--apply` は書き込まない |

### 運用ルール

`sync-manifest.json` の mapping 追加(`mirror` / `file`)は、public リポジトリへの公開判断である。追加する前に、対象に環境固有のパス、秘密情報、プロジェクト固有の名前が含まれないことを確かめ、`scripts/public-approval-ledger.md` に承認の記録を足すこと。承認なしの mapping 追加を禁止する。除外と判断した資産は manifest から mapping を削除し、payload からも除く。

### commit 時 block(`[PAYLOAD-SYNC-BLOCK]`)

`scripts/check-payload-sync.sh`(PreToolUse(Bash))が `git commit` の前に `sync-payload.mjs --check` を走らせ、乖離があれば exit 2 で止める。staged に `payload/<name>/` 配下のファイルがあるときは、その `<name>` の mapping だけを検査する。受けたときの対応は次のとおり。

1. stderr に出た DRIFT の一覧を確かめる。
2. `node scripts/sync-payload.mjs --apply` で乖離を解消する。
3. 差分を `git add` してから、もう一度 `git commit` する。
4. 緊急口(常用禁止): `CLAUDE_PAYLOAD_SYNC_SKIP=1 git commit ...` で、そのコマンドだけ検査を飛ばせる。

正本(`~/agent-home/`)が存在しない環境(clone 直後の別の PC など)では、hook もスクリプトも fail-safe で素通りする。

### 正本がなくなった mapping

正本の側でフォルダが削除された mapping は、`--check` で「source missing」として表示される。放置せず、次のどちらかを行う。配布を続けるなら manifest を `manual` に変えて理由を書く。配布をやめるなら mapping を削除し、payload からも除き、台帳に除外を記録する。

---

## payload 禁止アーティファクト機構(配布してはいけない実行時生成物の除外)

正本の側には正当に存在するが、payload には同梱してはいけないファイル(プロジェクトローカルな実行時生成物など)が mirror 経由で混入する事故があった。`scripts/payload-artifacts.json` に禁止パターンの枠を持ち、`sync-payload.mjs` の mirror コピーと独立スキャン(`--check-artifacts`)の両方でこれを弾く。

### 禁止パターンのデータファイル

| ファイル | 役割 |
|---|---|
| `scripts/payload-artifacts.json` | 公開側。キーの枠だけを持ち、値は空 |
| `~/agent-home/state/payload-forbidden-content.json` | 非公開側(リポジトリ外)。実際の値を持つ |

合成の対象は 3 キー。`names` はパスの各セグメントとの完全一致、`pathSuffixes` は相対パスの末尾一致、`forbiddenContent` はファイル内容の部分一致で判定する。新しい除外対象は非公開側へ追加し、公開側へ値を書き戻さない。

### 動き

- mirror コピー時: src 側の walk 結果からだけ禁止パターンを除く(dst 側は除かない)。新規の混入を防ぎつつ、すでに payload にあるものは "extra" の乖離として `--check` / `--apply` で検知、削除される。
- 独立スキャン: `--check-artifacts` は manifest と無関係に `payload/` 全体を走査し、一致があれば exit 1。manual mapping や手動コピーによる混入も捕まえる。
- commit 時 block(`[PAYLOAD-ARTIFACTS-BLOCK]`): `scripts/check-payload-artifacts.sh` が `git commit` の前に `--check-artifacts` を走らせ、該当があれば exit 2 で止める。該当ファイルを `git rm` し、構造的な混入源なら非公開側にパターンを足す。緊急口(常用禁止)は `CLAUDE_PAYLOAD_ARTIFACTS_SKIP=1`。
