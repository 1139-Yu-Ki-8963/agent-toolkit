#!/usr/bin/env bash
# check-playwright-filename.sh - PreToolUse(mcp__playwright__browser_take_screenshot) hook
#
# 役割: Playwright MCP の filename 引数を検査し、CWD 直下や許可外の絶対パスに
#       スクリーンショットを書き出そうとする呼び出しを exit 2 でブロックする。
# 仕様: ~/.claude/rules/always/placement/file-guard/rule.md
#
# 違反判定:
#   - filename が絶対パスでない（CWD 相対 = リポジトリ root 直書きになる）
#   - 絶対パスだが下記いずれの許可ロケーションにも入っていない:
#       * $CLAUDE_JOB_DIR/tmp/**
#       * $HOME/agent-home/tools/MCP/playwright/**
#       * <repo>/docs/**                          ※ 明示的 commit 対象の screenshots
#
# 例外: filename 引数が無い呼び出し（screenshot を返り値のみで受け取るケース）は通す。

set +e

input=""
if [ ! -t 0 ]; then
  input="$(cat 2>/dev/null || true)"
fi

[ -z "$input" ] && exit 0

# tool_input.filename を抽出（jq があれば優先、無ければ素朴な grep フォールバック）
if command -v jq >/dev/null 2>&1; then
  filename="$(printf '%s' "$input" | jq -r '.tool_input.filename // empty' 2>/dev/null)"
else
  filename="$(printf '%s' "$input" | grep -o '"filename"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/^"filename"[[:space:]]*:[[:space:]]*"//; s/"$//')"
fi

# filename が無い呼び出しは通す
[ -z "$filename" ] && exit 0

# 違反判定
violation_reason=""

case "$filename" in
  /*)
    # 絶対パス: 許可ロケーション判定
    case "$filename" in
      "$HOME/.claude/jobs/"*/tmp/*)
        # $CLAUDE_JOB_DIR/tmp/ 配下（典型展開後）
        exit 0
        ;;
      "$HOME"/agent-home/tools/MCP/playwright/*)
        # Playwright MCP 集約出力先
        exit 0
        ;;
      */docs/*)
        # docs 配下の明示パス（手動で commit するスクショ）
        exit 0
        ;;
      *)
        # $CLAUDE_JOB_DIR が展開済みの可能性: 環境変数を見て同等チェック
        if [ -n "${CLAUDE_JOB_DIR:-}" ]; then
          case "$filename" in
            "$CLAUDE_JOB_DIR/tmp/"*)
              exit 0
              ;;
          esac
        fi
        violation_reason="絶対パスだが許可ロケーション外: $filename"
        ;;
    esac
    ;;
  *)
    violation_reason="相対パスは CWD（リポジトリ root）に書かれる: $filename"
    ;;
esac

[ -z "$violation_reason" ] && exit 0

cat >&2 <<MSG
[FILE-PLACEMENT-BLOCK] Playwright MCP の filename 引数が file-placement 規約に違反しています。
  違反内容: ${violation_reason}

  正しい呼び出し例（絶対パス必須）:
    filename: "\$CLAUDE_JOB_DIR/tmp/<name>.png"     (展開後の絶対パス)
    filename: "$HOME/agent-home/tools/MCP/playwright/<name>.png"
    filename: "<repo>/docs/<feature>/screenshots/<name>.png"

  禁止例:
    filename: "foo.png"               ← CWD 相対 = リポジトリ root 直書き
    filename: "screenshots/foo.png"   ← 同上
    filename: "/tmp/foo.png"          ← 許可ロケーション外の絶対パス

  ルール詳細: ~/.claude/rules/always/placement/file-guard/rule.md
MSG

exit 2
