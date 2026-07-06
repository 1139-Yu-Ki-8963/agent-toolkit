#!/usr/bin/env bash
# PreToolUse(Bash) — managed ファイルを含む git commit を、
# managing-agent-configs スキルの該当種別のテスト完了マーカーがない場合に block する。
#
# T1: 複合コマンド検知。改行を ; に統一後 && / || / ; / | / & でセグメント分割し、
#     各セグメントを正規表現で判定する（cd 前置・-C 指定・heredoc 以外の複合形をすり抜けさせない）。
# T2: fail-loud。marker-path.sh が見つからない場合は判定不能として git commit 全体を block する。
# T3: ハッシュ照合。マーカーは shasum -a 256 の出力形式で、staged 内容と突合して stale 検知する。
set -euo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

GIT_COMMIT_RE='^[[:space:]]*(command[[:space:]]+)?git([[:space:]]+(-C|-c)[[:space:]]*[^[:space:]]+|[[:space:]]+--?[[:alnum:]=/._-]+)*[[:space:]]+commit([[:space:]]|$)'

# 改行を ; に統一してから && / || / ; / | / & でセグメント分割する。
# 順序重要: 2 文字演算子（&&, ||）を先に処理してから単独の |, & を処理する。
segments=$(printf '%s' "$cmd" | awk '{
  gsub(/\r?\n/, ";");
  gsub(/&&/, "\n");
  gsub(/\|\|/, "\n");
  gsub(/;/, "\n");
  gsub(/\|/, "\n");
  gsub(/&/, "\n");
  print
}')

matched_seg=""
while IFS= read -r seg; do
  if printf '%s' "$seg" | grep -qE "$GIT_COMMIT_RE"; then
    matched_seg="$seg"
    break
  fi
done <<< "$segments"

[ -z "$matched_seg" ] && exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"

# git -C <path> commit の場合は -C のパスを staged 検査対象にする
c_dir=$(printf '%s' "$matched_seg" | sed -E -n 's/.*git[[:space:]]+-C[[:space:]]*([^[:space:]]*).*commit.*/\1/p')
[ -n "$c_dir" ] && cwd="$c_dir"
session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session" ] && exit 0

staged=$(cd "$cwd" && git diff --cached --name-only 2>/dev/null) || exit 0
[ -z "$staged" ] && exit 0

# T2: fail-loud。lib 不在時は managed 判定自体が不能なため fail-closed で block する。
# env 上書き（MANAGING_MARKER_LIB）はテスト用に lib 不在を模擬するために使う。
MARKER_LIB="${MANAGING_MARKER_LIB:-$HOME/agent-home/tools/hooks/lib/marker-path.sh}"
if [ ! -f "$MARKER_LIB" ]; then
  echo "[MANAGING-GATE-DISABLED] $MARKER_LIB が見つからずゲート判定不能。agent-home の配置を確認してください。" >&2
  exit 2
fi
. "$MARKER_LIB"

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
  if [ ! -f "$passed_marker" ] || [ ! -s "$passed_marker" ]; then
    missing="${missing}${asset_type} "
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
