---
name: counting-code-lines
description: |
  対象ディレクトリのコード行数・ファイル数を FE/BE 別に計測し code-metrics.json に出力する。
  TRIGGER when: 「コード行数」「LOC計測」「コード計測」「code-metrics」と言われた時、リバース設計ポータル生成で計測結果が必要な時。
  SKIP: code-metrics.json が既に存在し再計測が不要な時。
invocation: counting-code-lines
type: transform
allowed-tools: [Bash, Read, Write]
---

# コード行数計測スキル

対象ディレクトリのコード行数とファイル数を計測し、FE/BE 別の内訳つきで `code-metrics.json` に出力する。env-config.json を参照して cloc（正確）と find + wc -l（フォールバック）を使い分ける。

## 起動引数

| 引数 | 必須 | 内容 | 既定値 |
|---|---|---|---|
| target_dir | 必須 | 計測対象のディレクトリパス | なし |
| output_dir | 任意 | code-metrics.json の出力先 | カレントディレクトリ |
| env_config | 任意 | env-config.json のパス | `$output_dir/env-config.json` |

## 実行手順

### Phase 1: 前提確認

1. `target_dir` が存在するか確認する。存在しなければエラー終了
2. `env_config` が存在するか確認する。存在しなければ `tools.cloc = false` として扱う（surveying-local-environment の未実行を許容し、フォールバック計測で進める）
3. `mkdir -p "$output_dir"` で出力先を作成する

### Phase 2: 計測方式の決定

`env_config` が存在する場合、`jq -r '.tools.cloc' "$env_config"` で cloc の有無を確認する。

- `true` → cloc 方式
- `false` または env_config 不在 → wc -l 方式

### Phase 3: コード行数の計測

#### cloc 方式

```bash
cloc "$target_dir" --json \
  --exclude-dir=node_modules,.git,dist,build,__pycache__,.next,coverage \
  --include-lang=TypeScript,JavaScript,Python,SQL,Vue,Svelte \
  2>/dev/null
```

cloc の JSON 出力から `SUM.code`（コード行）を total とする。言語別の内訳は出力に含まれるが、FE/BE 分離は cloc 単体ではできないため、ファイルリスト方式で補完する。

#### wc -l 方式

```bash
find "$target_dir" \
  -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
            -o -name '*.py' -o -name '*.sql' -o -name '*.vue' -o -name '*.svelte' \) \
  -not -path '*/node_modules/*' \
  -not -path '*/.git/*' \
  -not -path '*/dist/*' \
  -not -path '*/build/*' \
  -not -path '*/__pycache__/*' \
  -not -path '*/.next/*' \
  -not -path '*/coverage/*' \
  2>/dev/null
```

列挙されたファイルに対して `xargs wc -l` で行数を合計する。

### Phase 4: FE/BE 分離

計測対象ファイルのパスに以下のパターンが含まれるかで判定する。BE を先に判定し、一致しなければ FE を判定する。どちらにも一致しないファイルは未分類（total にのみ計上）。

| 判定 | パスに含まれる文字列 |
|---|---|
| BE | `backend/` `api/` `server/` |
| FE | `frontend/` `src/pages/` `src/components/` `src/app/` |
| 未分類 | 上記いずれにも該当しない |

ファイル数も同じパターンで分類する。

### Phase 5: code-metrics.json の出力

計測結果を JSON 形式で `$output_dir/code-metrics.json` に Write する。

```json
{
  "total": 67738,
  "fe": 52230,
  "be": 15508,
  "file_count": 512,
  "fe_files": 371,
  "be_files": 141,
  "method": "cloc",
  "measured_at": "<ISO8601 タイムスタンプ>"
}
```

`method` は `"cloc"` または `"wc"` を記録する。

## 完了条件

| Phase | 条件 |
|---|---|
| Phase 1 | target_dir の存在確認済み、出力先が準備済み |
| Phase 2 | 計測方式（cloc/wc）が決定済み |
| Phase 3 | コード行数の計測が完了 |
| Phase 4 | FE/BE の分離が完了 |
| Phase 5 | code-metrics.json が出力先に存在する |
| **Goal** | code-metrics.json が正しい JSON で出力され、total/fe/be/file_count の値が妥当である |

## 使用タイミング

- リバース設計フローの Phase 4.2（ポータル生成）でポータルの解析サマリに表示するコード行数を計測する時
- 任意のプロジェクトのコード規模を概算したい時

## 予想を裏切る挙動

- cloc と wc -l で同じコードベースを計測すると 20〜40% の差が出る。cloc はコメント行・空行を除外するため小さい値になる。`method` フィールドで計測方式を記録しているので、消費側は方式を考慮して表示できる
- FE/BE のパターンに一致しないファイル（設定ファイル・テストファイル等）は total にのみ計上される。そのため `total ≠ fe + be` になりうる
- 大規模リポジトリ（10万行超）では cloc の実行に数十秒かかる場合がある
