---
name: surveying-local-environment
description: |
  OS・パッケージ管理・開発ツールを調査してJSON出力する。
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

## Phase 1: 出力先の確認

## Step 1-1: 出力先の確認

**使用ツール**: Read / Bash / Write

`output_dir` に `env-config.json` が既に存在する場合は「既存の env-config.json を検出。再生成する場合は削除してから再実行してください」と報告して終了する。存在しない場合は `mkdir -p "$output_dir"` で出力先を作成して Phase 2 に進む。

**完了**: 既存ファイルによる終了、または書き込み可能な出力先の作成のどちらかが確定済み

## Phase 2: 環境調査

## Step 2-1: 環境調査

以下のコマンドを Bash ツールで実行し、結果を収集する。

```bash
# OS 種別
os_name="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"

# Linux 互換環境かどうか（カーネル情報にホスト OS のベンダー名を含むかで判定）
linux_compat_env=false
if [ "$os_name" = "linux" ] && [ -r /proc/version ]; then
  grep -qiE 'microsoft|wsl' /proc/version && linux_compat_env=true
fi

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

# 5種のインストールコマンドを生成する（パッケージ管理ツール別の導出は共通関数に揃える）
install_cmd_for() {
  local tool="$1" pkgname="$1"
  case "$tool" in
    node)    if [ "$pkg_manager" = "brew" ]; then pkgname="node"; else pkgname="nodejs"; fi ;;
    python3) if [ "$pkg_manager" = "pacman" ]; then pkgname="python"; else pkgname="python3"; fi ;;
  esac
  case "$pkg_manager" in
    brew)    echo "brew install $pkgname" ;;
    apt-get) echo "sudo apt-get install -y $pkgname" ;;
    yum|dnf) echo "sudo $pkg_manager install -y $pkgname" ;;
    pacman)  echo "sudo pacman -S $pkgname" ;;
    apk)     echo "sudo apk add $pkgname" ;;
  esac
}

install_cloc="$(install_cmd_for cloc)"
install_node="$(install_cmd_for node)"
install_python3="$(install_cmd_for python3)"
install_jq="$(install_cmd_for jq)"
install_git="$(install_cmd_for git)"
```

**完了**: OS・アーキテクチャ・Linux 互換環境フラグ・パッケージ管理ツール・5開発ツールの有無・5開発ツール分のインストールコマンドが取得済み

## Phase 3: env-config.json の出力

## Step 3-1: env-config.json の出力

収集した結果を JSON 形式で `$output_dir/env-config.json` に Write する。

```json
{
  "os": "<os_name>",
  "arch": "<arch>",
  "linux_compat_env": <true|false>,
  "pkg_manager": "<pkg_manager>",
  "tools": {
    "cloc": <true|false>,
    "node": <true|false>,
    "python3": <true|false>,
    "jq": <true|false>,
    "git": <true|false>
  },
  "install_commands": {
    "cloc": "<install_cloc>",
    "node": "<install_node>",
    "python3": "<install_python3>",
    "jq": "<install_jq>",
    "git": "<install_git>"
  },
  "surveyed_at": "<ISO8601 タイムスタンプ>"
}
```

### 出力フィールドの消費経路

全トップレベルフィールドは「消費経路あり」であることを条件とする。消費経路を持たないフィールドをスキーマに残さない。

| フィールド | 消費経路 |
|---|---|
| os | generating-env-guide-for-reverse-docs の前提条件表へ実測値として転記される |
| arch | 同上 |
| linux_compat_env | 同上。互換環境上での実行であることを成果物に残す |
| pkg_manager | 本スキル内部で install_commands の導出に使う（成果物へは導出結果のみが載る） |
| tools | counting-code-lines が tools.cloc を読む。generating-env-guide-for-reverse-docs が前提ツール表へ転記する |
| install_commands | generating-env-guide-for-reverse-docs が未インストール時の注記へ転記する |
| surveyed_at | 調査時点の記録。成果物の鮮度判断に使う |

フィールドを追加する場合は本表に消費経路の行を足す。消費先が無いフィールドは追加しない。

**完了**: `$output_dir/env-config.json` が正しいJSONとして存在し、全調査キーが記録済み

## Step 3-2: env-config.json を機械検査する

**使用ツール**: Bash

出力直後に `shared/scripts/validate-env-config.sh "$output_dir/env-config.json"` を実行し、終了コードで合否を判定する。終了コード 0 は正しい JSON かつ必須キー（`os`・`arch`・`linux_compat_env`・`pkg_manager`・`tools`・`install_commands`・`surveyed_at`、および `tools` 配下の cloc/node/python3/jq/git の 5 キー）が揃っていることの機械的な合格判定であり、自然文の自己申告に代える。終了コード 1 の場合は標準エラーに列挙された不足キーを確認し、Phase 2〜3 の収集・出力をやり直す。

**完了**: `validate-env-config.sh` の終了コードが 0

## Phase 4: 未インストールツールの案内

## Step 4-1: 未インストールツールの案内

**使用ツール**: Read

`tools` 配下の5種（cloc/node/python3/jq/git）のうち `false` のものをすべて対象に、それぞれ以下の形式で報告する:

「<ツール名> が未インストールです。<用途>。インストールコマンド: `<install_commands.<ツール名>>`。インストール後に env-config.json を削除して再実行すると反映されます。」

用途の文言は以下を使う:

| ツール | 用途 |
|---|---|
| cloc | コード行数の計測精度が向上します |
| node | Node.js製スクリプトの実行に必要です |
| python3 | Python製抽出処理の実行に必要です |
| jq | JSON処理を伴うスクリプトの実行に必要です |
| git | バージョン管理操作に必要です |

5種すべてが既にインストール済みの場合はこの案内を省略する。

**完了**: 未導入ツールがあれば全種について実行可能な導入コマンドを報告済み、5種とも導入済み時は案内不要と記録済み

## 完了条件

| Phase | 条件 |
|---|---|
| Phase 1 | env-config.json の存在有無が確認済み |
| Phase 2 | OS・アーキテクチャ・Linux 互換環境フラグ・パッケージ管理ツール・ツール有無が収集済み |
| Phase 3 | `shared/scripts/validate-env-config.sh "$output_dir/env-config.json"` の終了コードが 0 であること。終了コード 0 は必須キー（os/arch/linux_compat_env/pkg_manager/tools/install_commands/surveyed_at・tools配下5キー）の値が妥当であることの機械的な合格判定であり、自然文の自己申告に代える |
| Phase 4 | 未インストールツール（5種のうちfalseのもの全て）の案内が完了している（該当時のみ） |
| **Goal** | `shared/scripts/validate-env-config.sh "$output_dir/env-config.json"` の終了コードが 0 であること |

## 使用タイミング

- リバース設計フローのglobal Step 16（ポータル生成）で env-config.json が不在の場合
- 新しい PC でリバース設計を初めて実行する場合
- ツールをインストール/削除した後に環境情報を更新したい場合（手動で env-config.json を削除してから再実行）

## 予想を裏切る挙動

- Linux 互換環境では `uname -s` が `Linux` を返すため、OS 種別だけでは素の Linux と区別できない。本スキルは `/proc/version` にホスト OS のベンダー名が含まれるかで判別し、`linux_compat_env` として記録する。ファイルシステムのマウント種別・性能特性は記録しない
- `command -v` はエイリアスも検出する。実際のバイナリが存在しない場合（エイリアスのみ）でも true を返す可能性がある

## 設計判断

### shared/scripts/validate-env-config.sh

- **必要性**: 改善課題 1-109 が指摘するとおり、本スキルは出力 JSON の構文検証・キー充足検証の手順を持たず完了判定が自己申告になっている。決定的な検査の exit code を完了判定に使うため、`validate-env-config.sh` を新設した
- **代替案を採用しなかった理由**: SKILL.md 本文への検査手順の直書きは、検査ロジックが自然文に埋もれて機械実行できない。他スキルの `validate-*.sh` と同様に独立スクリプト化し、終了コードで合否を判定できる形にした
- **保守責任者**: 人手（ユーザー）。env-config.json のスキーマ（必須キー・tools の内訳）を変更した場合は `validate-env-config.sh` の必須キー対応表を同時に更新する
- **廃棄条件**: 本スキル自体が廃止された時、またはスキーマ検証をビルド基盤が標準で提供するようになった時

詳細は `shared/scripts/validate-env-config.sh` 本体のヘッダコメントを参照する。

## 完了報告

`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（作業報告型）に従う。

固有の検証行:
- env-config.json が正しい JSON で出力されている
- `shared/scripts/validate-env-config.sh "$output_dir/env-config.json"` の終了コードが 0
