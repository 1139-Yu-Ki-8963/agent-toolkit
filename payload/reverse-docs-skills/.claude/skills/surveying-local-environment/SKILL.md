---
name: surveying-local-environment
description: |
  PC の OS・パッケージ管理ツール・開発ツール有無を調査し env-config.json に出力する。
  TRIGGER when: 「環境調査」「PC環境」「env-config」「ツール確認」と言われた時、env-config.json が不在でリバース設計ポータル生成が必要な時。
  SKIP: env-config.json が既に存在する時（手動削除で再生成）。
invocation: surveying-local-environment
type: transform
allowed-tools: [Bash, Read, Write]
---

# ローカル環境調査スキル

対象 PC の OS 種別・パッケージ管理ツール・インストール済み開発ツールを調査し、結果を `env-config.json` に出力する。他のスキル（counting-code-lines 等）がこのファイルを読んでツールの有無に応じた処理を分岐する。

## 起動引数

| 引数 | 必須 | 内容 | 既定値 |
|---|---|---|---|
| output_dir | 任意 | env-config.json の出力先ディレクトリ | カレントディレクトリ |

## 実行手順

### Phase 1: 出力先の確認

`output_dir` に `env-config.json` が既に存在する場合は「既存の env-config.json を検出。再生成する場合は削除してから再実行してください」と報告して終了する。存在しない場合は `mkdir -p "$output_dir"` で出力先を作成して Phase 2 に進む。

### Phase 2: 環境調査

以下のコマンドを Bash ツールで実行し、結果を収集する。

```bash
# OS 種別
os_name="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"

# パッケージ管理ツール（最初に見つかったものを採用）
pkg_manager=""
for cmd in brew apt-get yum dnf pacman apk; do
  if command -v "$cmd" &>/dev/null; then
    pkg_manager="$cmd"
    break
  fi
done

# 開発ツールの有無
tools_cloc=$(command -v cloc &>/dev/null && echo true || echo false)
tools_node=$(command -v node &>/dev/null && echo true || echo false)
tools_python3=$(command -v python3 &>/dev/null && echo true || echo false)
tools_jq=$(command -v jq &>/dev/null && echo true || echo false)
tools_git=$(command -v git &>/dev/null && echo true || echo false)

# cloc のインストールコマンドを生成
install_cloc=""
case "$pkg_manager" in
  brew)    install_cloc="brew install cloc" ;;
  apt-get) install_cloc="sudo apt-get install -y cloc" ;;
  yum|dnf) install_cloc="sudo $pkg_manager install -y cloc" ;;
  pacman)  install_cloc="sudo pacman -S cloc" ;;
  apk)     install_cloc="sudo apk add cloc" ;;
esac
```

### Phase 3: env-config.json の出力

収集した結果を JSON 形式で `$output_dir/env-config.json` に Write する。

```json
{
  "os": "<os_name>",
  "arch": "<arch>",
  "pkg_manager": "<pkg_manager>",
  "tools": {
    "cloc": <true|false>,
    "node": <true|false>,
    "python3": <true|false>,
    "jq": <true|false>,
    "git": <true|false>
  },
  "install_commands": {
    "cloc": "<install_cloc>"
  },
  "surveyed_at": "<ISO8601 タイムスタンプ>"
}
```

### Phase 4: cloc 未インストール時の案内

`tools.cloc` が false の場合、以下を報告する:

「cloc が未インストールです。コード行数の計測精度が向上します。インストールコマンド: `<install_commands.cloc>`。インストール後に env-config.json を削除して再実行すると反映されます。」

cloc が既にインストール済みの場合はこの案内を省略する。

## 完了条件

| Phase | 条件 |
|---|---|
| Phase 1 | env-config.json の存在有無が確認済み |
| Phase 2 | OS・パッケージ管理ツール・ツール有無が収集済み |
| Phase 3 | env-config.json が出力先に存在する |
| Phase 4 | cloc 未インストール時の案内が完了している（該当時のみ） |
| **Goal** | env-config.json が正しい JSON で出力されている |

## 使用タイミング

- リバース設計フローの Phase 4A（ポータル生成）で env-config.json が不在の場合
- 新しい PC でリバース設計を初めて実行する場合
- ツールをインストール/削除した後に環境情報を更新したい場合（手動で env-config.json を削除してから再実行）

## 予想を裏切る挙動

- WSL 環境では `uname -s` が `Linux` を返す。WSL 固有の判定が必要な場合は `/proc/version` に `microsoft` が含まれるかで判別できるが、本スキルでは区別しない
- `command -v` はエイリアスも検出する。実際のバイナリが存在しない場合（エイリアスのみ）でも true を返す可能性がある

## 設計判断

本スキルは独自スクリプトを持たないため省略する。

## 完了報告

`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（作業報告型）に従う。

固有の検証行:
- env-config.json が正しい JSON で出力されている
