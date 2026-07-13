#!/usr/bin/env bash
# check-curl-egress.sh - PreToolUse(Bash) hook
#
# 役割: 外部ホストへの生 curl / wget を exit 2 で block する。
#       許可する経路は 2 つのみ:
#         1. localhost 系（localhost / 127.0.0.1 / ::1 / 0.0.0.0）への直書き URL
#         2. ~/agent-home/tools/call-api.sh（ホスト白リスト検証ラッパー）経由
# 仕様: ~/.claude/rules/scoped/tooling/shell/rule.md
#
# 設計:
#   - コマンドを && || ; | $( ` でセグメント分割し、各セグメントの command-word
#     （env/nohup 等のラッパーと変数代入を読み飛ばした先頭トークン）が curl/wget
#     の場合のみ検査する（`echo "curl"` 等の誤爆防止）
#   - URL 不検出（変数展開 `curl "$URL"` 等）は検証不能のため fail-closed で block
#   - 自動解除カウンタは持たない（N 回試行で外部送信が通る穴になるため決定論的 block）

set -uf

input=""
if [ ! -t 0 ]; then
  input="$(cat 2>/dev/null || true)"
fi

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0

# 高速ガード: curl / wget を含まないコマンドは即通過
case "$cmd" in
  *curl*|*wget*) : ;;
  *) exit 0 ;;
esac

block() {
  cat >&2 <<MSG
[CURL-EGRESS-BLOCK] 外部ホストへの生 curl / wget は禁止されています。
  検出セグメント: $1
  許可される経路:
    - localhost / 127.0.0.1 / ::1 / 0.0.0.0 への直書き URL（開発サーバーの疎通確認）
    - ~/agent-home/tools/call-api.sh <url>（外部 API の唯一の正規経路・ホスト白リスト検証付き）
  変数展開 URL（curl "\$URL" 等）は検証できないため URL を直書きすること。
  ルール詳細: ~/.claude/rules/scoped/tooling/shell/rule.md
MSG
  exit 2
}

segments="$(printf '%s\n' "$cmd" | perl -pe 's/&&|\|\||;|\||\$\(|`/\n/g')"

while IFS= read -r seg; do
  [ -z "${seg// /}" ] && continue

  # command-word の特定（変数代入・ラッパーコマンドを読み飛ばす）
  word=""
  for tok in $seg; do
    case "$tok" in
      [A-Za-z_]*=*) continue ;;
      env|nohup|time|command|xargs|sudo|exec) continue ;;
    esac
    word="$tok"
    break
  done
  [ -z "$word" ] && continue

  base="${word##*/}"
  case "$base" in
    curl|wget) : ;;
    *) continue ;;
  esac

  # 引数なしの裸 curl / wget は外部送信不能のため通過
  # （クォート内の | 分割で生じる `grep -E "curl|wget"` 由来の誤検知対策を兼ねる）
  rest="${seg#*"$word"}"
  if [ -z "${rest// /}" ]; then
    continue
  fi

  # --version / --help のみのセグメントは通過
  if printf '%s' "$rest" | grep -qE '^[[:space:]]*(--version|--help|-V)[[:space:]]*$'; then
    continue
  fi

  # 明示 URL（http/https）の抽出とホスト判定
  urls="$(printf '%s\n' "$seg" | grep -oE 'https?://[^ "'"'"'<>]+' || true)"
  if [ -n "$urls" ]; then
    external=""
    while IFS= read -r u; do
      [ -z "$u" ] && continue
      host="${u#*://}"
      host="${host%%[/?#]*}"
      case "$host" in *@*) host="${host#*@}" ;; esac
      case "$host" in
        \[*\]*) hostonly="${host%%]*}]" ;;
        *) hostonly="${host%%:*}" ;;
      esac
      case "$hostonly" in
        localhost|127.0.0.1|0.0.0.0|"[::1]"|::1) : ;;
        *) external="$u"; break ;;
      esac
    done <<EOF_URLS
$urls
EOF_URLS
    [ -n "$external" ] && block "$seg"
    continue
  fi

  # スキーム無しのローカル形（curl localhost:3000 等）は通過
  if printf '%s' "$seg" | grep -qE "(^|[[:space:]\"'=])(localhost|127\.0\.0\.1|\[::1\]|0\.0\.0\.0)(:[0-9]+)?"; then
    continue
  fi

  # URL 不検出 → fail-closed
  block "$seg"
done <<EOF_SEG
$segments
EOF_SEG

exit 0
