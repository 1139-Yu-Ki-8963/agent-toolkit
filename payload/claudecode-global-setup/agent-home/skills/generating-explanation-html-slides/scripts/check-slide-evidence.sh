#!/usr/bin/env bash
# check-slide-evidence.sh - PreToolUse(Bash) hook
#
# スライド HTML の commit 時に、検証用スクリーンショット（1280×720）の存在と
# 独立レビューの実施を検査する。いずれか欠如で exit 2 block。
#
# 設計判断:
#   必要性: セッション f9f9a300 で生成者が自己採点で全観点 PASS と記載し、
#           フルサイズ描画を確認していなかった事故の再発防止。スキル本文の指示は
#           強制力ゼロのため、commit 時の機械検査が必須。
#   代替案不採用: Bash 直叩きは PreToolUse にバインド不可。advisory のみでは
#                同じ手抜きが再発する（実測済み）。
#   保守責任者: 人手（ユーザー）
#   廃棄条件: Claude Code 本体がスライド証跡検査を標準機能として提供した時
set -u

input="$(cat)"
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# git commit 以外は対象外
case "$cmd" in
  *git*commit*) ;;
  *) exit 0 ;;
esac

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"

# staged の全ファイルリスト
staged_all=$(cd "$cwd" && git -c core.quotepath=false diff --cached --name-only 2>/dev/null || true)
staged_slides=$(printf '%s\n' "$staged_all" | grep '解説スライド\.html$' || true)
[ -z "$staged_slides" ] && exit 0

# 自動解除（同セッション 3 回連続 block）
tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
if [ -n "$tp" ]; then
  block_count=$(grep -c '\[SLIDE-EVIDENCE-BLOCK\]' "$tp" 2>/dev/null || echo 0)
  [ "${block_count:-0}" -ge 3 ] && exit 0
fi

errors=""

while IFS= read -r slide_path; do
  [ -z "$slide_path" ] && continue
  slide_dir="$cwd/$(dirname "$slide_path")"
  evidence_file="$slide_dir/evidence/検証用スクリーンショット.png"

  if [ ! -f "$evidence_file" ]; then
    errors="${errors}${slide_path}: evidence/検証用スクリーンショット.png が存在しません。build-thumbs.mjs --evidence で生成してください\n"
    continue
  fi

  if command -v sips >/dev/null 2>&1; then
    w=$(sips -g pixelWidth "$evidence_file" 2>/dev/null | awk '/pixelWidth/{print $2}')
    h=$(sips -g pixelHeight "$evidence_file" 2>/dev/null | awk '/pixelHeight/{print $2}')
    if [ "$w" != "1280" ] || [ "$h" != "720" ]; then
      errors="${errors}${slide_path}: 検証用スクリーンショットの寸法が ${w:-?}x${h:-?} です（1280x720 必須）\n"
    fi
  fi
done <<< "$staged_slides"

# 検査記録.md の存在・内容による独立レビュー検証
while IFS= read -r slide_path2; do
  [ -z "$slide_path2" ] && continue
  slide_dir2=$(dirname "$slide_path2")
  record_path="${slide_dir2}/検査記録.md"

  if ! printf '%s\n' "$staged_all" | grep -qF "$record_path"; then
    errors="${errors}${slide_path2}: 検査記録.md が staged されていません。観点レビュー結果を記録してから commit してください\n"
    continue
  fi

  record_file="$cwd/$record_path"
  if [ -f "$record_file" ]; then
    if ! grep -q 'evidence/検証用スクリーンショット' "$record_file" 2>/dev/null; then
      errors="${errors}${slide_path2}: 検査記録.md に evidence/検証用スクリーンショット のパス引用がありません（パス引用なき PASS は無効）\n"
    fi
    if ! grep -q 'document-reviewer' "$record_file" 2>/dev/null; then
      errors="${errors}${slide_path2}: 検査記録.md に document-reviewer による独立判定の記録がありません\n"
    fi
  fi
done <<< "$staged_slides"

if [ -n "$errors" ]; then
  printf '{"additionalContext":"[SLIDE-EVIDENCE-BLOCK] スライド証跡検査に失敗:\\n%b"}' "$errors" >&2
  exit 2
fi

exit 0
