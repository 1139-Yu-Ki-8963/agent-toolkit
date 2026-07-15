#!/usr/bin/env bash
# resolve-applicable-rules.sh — 対象ファイルに適用される scoped rule と担当専門家を解決する
#
# 使い方: resolve-applicable-rules.sh <file> [<file>...]
# 出力:   <file>\t<rule.md の絶対パス>\t<specialist>（マッチごとに 1 行、TSV）
#         specialist は rule の配置フォルダから導出する:
#           .../scoped/review-checklist/<domain>/... → "<domain>-reviewer"
#           review-checklist 外の scoped rule        → "(non-review)"（レビュー観点ではない）
#         適用 rule が 1 つもないファイルは <file>\t(none)\t(none) を出力する
#
# 解決対象:
#   - グローバル: ~/.claude/rules/scoped/ 配下の全 rule.md（深さ不問。review-checklist は深さ4）
#   - プロジェクト受け口: <カレント git リポジトリ>/.claude/rules/scoped/ 配下の全 rule.md
# 各 rule.md の frontmatter `paths:` の glob（例: "**/*.html"）と照合する。
# 1 ファイルに複数 rule（複数 specialist）が適用されることを前提とする
# （例: .tsx は review-checklist/code/common と review-checklist/code/ui の両方に一致しうる）。
#
# 設計判断（ADR）:
#   必要性: reviewing-against-rules スキルの手順 2（適用 rule の機械的解決）を担う。
#     scoped rule の paths frontmatter を唯一のルーティング表として使うことで、
#     「どのファイルにどの観点が適用されるか」の対応表を別途維持する二重管理を防ぐ。
#     担当専門家は review-checklist/<domain>/ のフォルダ名から導出する（<domain>-reviewer）。
#     旧方式の specialist frontmatter 宣言はフォルダ構造との二重管理で乖離リスクがあり、
#     フォルダ導出なら構造そのものが宣言になる（2026-07-10 再設計）。
#   代替案を採用しなかった理由: SKILL.md 側に拡張子→専門家の対応表を持つ方式は
#     rule 側の paths 拡張のたびに二重更新が必要で、icon 規約の tsx/css/vue が
#     未カバーになる欠陥の直接原因だった。frontmatter 宣言方式も同型の二重管理。
#   保守責任者: 人手（ユーザー）。review-checklist の階層構造を変えたら追従する。
#   廃棄条件: reviewing-against-rules スキル自体が廃止された時、または Claude Code
#     本体が scoped rule の適用解決 API を提供するようになった時。
set -u

if [ "$#" -eq 0 ]; then
  echo "usage: $(basename "$0") <file> [<file>...]" >&2
  exit 1
fi

# rule.md 候補を収集する（グローバル + カレントリポジトリ受け口。深さ不問）
rule_files=""
while IFS= read -r r; do
  [ -n "$r" ] && rule_files="${rule_files}${r}
"
done <<EOF
$(find "$HOME/.claude/rules/scoped" -name rule.md 2>/dev/null | sort)
EOF
repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$repo_root" ] && [ -d "$repo_root/.claude/rules/scoped" ]; then
  while IFS= read -r r; do
    [ -n "$r" ] && rule_files="${rule_files}${r}
"
  done <<EOF
$(find "$repo_root/.claude/rules/scoped" -name rule.md 2>/dev/null | sort)
EOF
fi

# frontmatter から paths glob を抽出する（--- と --- の間の "- \"...\"" 行）
extract_globs() {
  awk '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { exit }
    infm && /^[[:space:]]*-[[:space:]]*"/ {
      line=$0
      sub(/^[[:space:]]*-[[:space:]]*"/, "", line)
      sub(/"[[:space:]]*$/, "", line)
      print line
    }
  ' "$1"
}

# rule.md のパスから担当専門家を導出する
derive_specialist() {
  rp="$1"
  case "$rp" in
    */rules/scoped/review-checklist/*)
      rest="${rp#*/rules/scoped/review-checklist/}"
      domain="${rest%%/*}"
      printf '%s-reviewer' "$domain"
      ;;
    *)
      printf '(non-review)'
      ;;
  esac
}

# glob 1 つとファイルパス 1 つの照合。`**/` プレフィックスは任意階層を意味する
match_glob() {
  f="$1"; g="$2"
  tail="${g#\*\*/}"
  if [ "$tail" != "$g" ]; then
    # **/ 付き: basename 直マッチ or 任意ディレクトリ配下
    case "$f" in
      $tail|*/$tail) return 0 ;;
    esac
  else
    case "$f" in
      $g) return 0 ;;
    esac
  fi
  return 1
}

for target in "$@"; do
  found=0
  while IFS= read -r rule; do
    [ -z "$rule" ] && continue
    while IFS= read -r glob; do
      [ -z "$glob" ] && continue
      if match_glob "$target" "$glob"; then
        specialist=$(derive_specialist "$rule")
        printf '%s\t%s\t%s\n' "$target" "$rule" "$specialist"
        found=1
        break
      fi
    done <<EOF
$(extract_globs "$rule")
EOF
  done <<EOF
$rule_files
EOF
  if [ "$found" -eq 0 ]; then
    printf '%s\t(none)\t(none)\n' "$target"
  fi
done
exit 0
