#!/usr/bin/env bash
# PreToolUse(Bash) — managed ファイルを含む git commit を、
# managing-agent-configs スキルの該当種別のテスト完了マーカーがない場合に block する。
#
# T1: 複合コマンド検知。改行を ; に統一後 && / || / ; / | / & でセグメント分割し、
#     各セグメントを正規表現で判定する（cd 前置・-C 指定・heredoc 以外の複合形をすり抜けさせない）。
# T2: fail-loud。marker-path.sh が見つからない場合は判定不能として git commit 全体を block する。
# T3: ハッシュ照合。マーカーは shasum -a 256 の出力形式で、staged 内容と突合して stale 検知する。
# T4: レポート必須化。review/test の実施内容を記した report ファイルの実在・内容・鮮度・マーカーとの紐付けを検証する。
set -euo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# T2: fail-loud。lib 不在時は managed 判定自体が不能なため fail-closed で block する。
# env 上書き（MANAGING_MARKER_LIB）はテスト用に lib 不在を模擬するために使う。
# resolve_git_ctx_dir（cd 前置対応のコンテキスト解決）を使うため、セグメント判定より先にsourceする。
MARKER_LIB="${MANAGING_MARKER_LIB:-$HOME/agent-home/tools/hooks/shared/marker-path.sh}"
if [ ! -f "$MARKER_LIB" ]; then
  echo "[MANAGING-GATE-DISABLED] $MARKER_LIB が見つからずゲート判定不能。agent-home の配置を確認してください。" >&2
  exit 2
fi
. "$MARKER_LIB"

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"

resolve_git_ctx_dir "$cmd" "$CMD_CTX_GIT_COMMIT_RE" "$cwd" || true
[ -z "$RGCD_MATCHED_SEG" ] && exit 0
cwd="$RGCD_CTX_DIR"

session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session" ] && exit 0

staged=$(cd "$cwd" && git diff --cached --name-only 2>/dev/null) || exit 0
[ -z "$staged" ] && exit 0

types_needed=""
managed_files=""
while IFS= read -r f; do
  # git status --porcelain のリネーム表記（old -> new）に備え念のため新パスのみ抽出
  f="${f##*-> }"
  t="$(managed_asset_type "$f")"
  [ -z "$t" ] && continue
  case " $types_needed " in
    *" $t "*) ;;
    *) types_needed="${types_needed}${t} " ;;
  esac
  managed_files="${managed_files}${f}"$'\n'
done <<< "$staged"

[ -z "$types_needed" ] && exit 0

missing=""
stale=""
for asset_type in $types_needed; do
  passed_marker="$(marker_path "$cwd" "$session" "managing-agent-configs-${asset_type}-test-passed")"
  report_marker="$(marker_path "$cwd" "$session" "managing-agent-configs-${asset_type}-report.md")"
  needed_marker="$(marker_path "$cwd" "$session" "managing-agent-configs-${asset_type}-needed")"

  if [ ! -f "$passed_marker" ] || [ ! -s "$passed_marker" ]; then
    missing="${missing}${asset_type} "
    continue
  fi

  # T4: レポート必須化。ハッシュ値だけでの自己申告合格を防ぐため、
  # review/testの実施内容を記した report ファイルの実在・内容・鮮度・マーカーとの紐付けを要求する。
  if [ ! -f "$report_marker" ] || [ ! -s "$report_marker" ]; then
    missing="${missing}${asset_type}(report欠落) "
    continue
  fi
  if ! grep -q "^REVIEW-TEST-VERDICT: PASS$" "$report_marker" 2>/dev/null; then
    missing="${missing}${asset_type}(reportにPASS宣言なし) "
    continue
  fi
  if [ -f "$needed_marker" ] && [ "$needed_marker" -nt "$report_marker" ]; then
    stale="${stale}${asset_type}(report作成後に再編集) "
    continue
  fi
  report_hash=$(shasum -a 256 "$report_marker" 2>/dev/null | awk '{print $1}')
  if [ -z "$report_hash" ] || ! grep -qF "REPORT_SHA256=${report_hash}" "$passed_marker" 2>/dev/null; then
    stale="${stale}${asset_type}(reportとマーカーのハッシュ不一致) "
    continue
  fi

  # T3: ハッシュ照合。マーカーに記録された staged 内容ハッシュと現在の staged 内容を突合する。
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ "$(managed_asset_type "$f")" = "$asset_type" ] || continue
    cur_hash=$(cd "$cwd" && git show ":$f" 2>/dev/null | shasum -a 256 | awk '{print $1}')
    [ -z "$cur_hash" ] && continue
    if ! grep -qF "${cur_hash}  ${f}" "$passed_marker" 2>/dev/null; then
      stale="${stale}${f} "
    fi
  done <<< "$managed_files"
done

missing=$(echo "$missing" | xargs)
stale=$(echo "$stale" | xargs)

[ -z "$missing" ] && [ -z "$stale" ] && exit 0

msg="[MANAGING-COMMIT-BLOCK] managed ファイルのテストが未完了です。"
[ -n "$missing" ] && msg="${msg}未完了種別: ${missing}。"
[ -n "$stale" ] && msg="${msg}stale: ${stale}（マーカー記録後に再編集されています）。"
msg="${msg}対応する種別で Skill(\"managing-agent-configs\") を実行し、テストまで完了させてください。テスト PASS 時にマーカーが書き出され、コミットが許可されます。"
echo "$msg" >&2
exit 2
