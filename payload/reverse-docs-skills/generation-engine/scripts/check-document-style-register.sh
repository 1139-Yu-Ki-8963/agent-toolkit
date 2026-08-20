#!/usr/bin/env bash
# 文書の文体（敬体/常体）検査
#
# 顧客提示の文書（設計書・単位ごとの資料）は敬体（です・ます）で書く。
# 記入規則・検証の記録は常体でよい（delivery-payload/references/設計書様式.md §8）。
# 本スクリプトは、指定したMarkdownファイルの本文（HTMLコメント・表の行・見出し行を
# 除いた地の文）を文単位（「。」区切り）に分割し、常体の文末（である・だ）を検出する。
# 敬体の文末（です・ます・でしょう・ましょう・ください）は無視する。
#
# 判定不能規約（.claude/rules/always/verification/indeterminate-result/rule.md）に従い、
# mktempの失敗は[UNKNOWN]・終了コード2で区別する（check-portal-catalog.shに倣う）。
set -uo pipefail

scan_file() {
  local f="$1"
  node -e '
    const fs = require("fs");
    const path = process.argv[1];
    const text = fs.readFileSync(path, "utf8");
    const noComments = text.replace(/<!--[\s\S]*?-->/g, "");
    const lines = noComments.split("\n");
    const jodoRe = /(である|だ)$/;
    const keitaiRe = /(です|ます|でしょう|ましょう|ください)$/;
    let failed = false;
    let inFence = false;
    lines.forEach((line, idx) => {
      const lineNo = idx + 1;
      const trimmed = line.trim();
      if (/^```/.test(trimmed)) { inFence = !inFence; return; }
      if (inFence) return;
      if (trimmed === "" || /^\s*\|/.test(trimmed) || /^#/.test(trimmed)) return;
      // 文単位に分割して文末を判定する
      trimmed.split("。").forEach((sentence) => {
        const s = sentence.trim();
        if (!s) return;
        if (keitaiRe.test(s)) return;
        if (jodoRe.test(s)) {
          console.log(`FAIL ${path}:${lineNo} 常体の文末を検出: ${s}。`);
          failed = true;
        }
      });
    });
    process.exit(failed ? 1 : 0);
  ' "$f"
}

run_check() {
  local targets=("$@")
  local files=()
  local t
  for t in "${targets[@]}"; do
    if [ -d "$t" ]; then
      while IFS= read -r -d '' f; do
        files+=("$f")
      done < <(find "$t" -type f -name "*.md" -print0 2>/dev/null)
    elif [ -f "$t" ]; then
      files+=("$t")
    fi
  done

  if [ "${#files[@]}" -eq 0 ]; then
    echo "対象のMarkdownファイルが見つかりません: ${targets[*]}" >&2
    return 2
  fi

  local total_fail=0
  local clean=0
  for f in "${files[@]}"; do
    local out
    out="$(scan_file "$f")"
    if [ -n "$out" ]; then
      echo "$out"
      total_fail=$((total_fail + 1))
    else
      clean=$((clean + 1))
    fi
  done

  if [ "$total_fail" -gt 0 ]; then
    echo "FAIL: 常体の文末を持つ文書 ${total_fail} 件（CLEAN ${clean} 件）"
    return 1
  fi
  echo "CLEAN: ${clean} 件の文書に常体の文末はない"
  return 0
}

self_test() {
  local tmpdir
  if ! tmpdir="$(mktemp -d 2>/dev/null)" || [ -z "$tmpdir" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）"
    return 2
  fi
  trap 'rm -rf "$tmpdir"' RETURN

  local pass=0
  local fail=0

  assert() {
    local label="$1"
    local expect_rc="$2"
    shift 2
    local actual_rc
    "$@" >/dev/null 2>&1
    actual_rc=$?
    if [ "$actual_rc" -eq "$expect_rc" ]; then
      echo "  [PASS] $label"
      pass=$((pass + 1))
    else
      echo "  [FAIL] $label (期待=$expect_rc 実際=$actual_rc)" >&2
      fail=$((fail + 1))
    fi
  }

  # ケース1: 敬体のみ → CLEAN(0)
  cat > "$tmpdir/case1.md" <<'EOF'
# 案件詳細

本書は対象の仕様を示します。読み手は本文を確認してください。
EOF
  assert "ケース1(敬体のみ)" 0 run_check "$tmpdir/case1.md"

  # ケース2: 常体が混入 → FAIL(1)
  cat > "$tmpdir/case2.md" <<'EOF'
# 案件詳細

本書は対象の仕様を示します。この項目は未確定である。
EOF
  assert "ケース2(常体混入)" 1 run_check "$tmpdir/case2.md"

  # ケース3: 常体のみ → FAIL(1)
  cat > "$tmpdir/case3.md" <<'EOF'
# 案件詳細

本書は対象の仕様を示す。この文書は常体で書かれただ。
EOF
  assert "ケース3(常体のみ)" 1 run_check "$tmpdir/case3.md"

  # ケース4: HTMLコメント内の常体は無視 → CLEAN(0)
  cat > "$tmpdir/case4.md" <<'EOF'
# 案件詳細

<!-- 記入規則: この節には対象の仕様を書く。常体でよい。 -->

本書は対象の仕様を示します。
EOF
  assert "ケース4(コメント内常体は無視)" 0 run_check "$tmpdir/case4.md"

  # ケース5: 表の行の中の常体は無視 → CLEAN(0)
  cat > "$tmpdir/case5.md" <<'EOF'
# 案件詳細

| 項目 | 説明 |
|---|---|
| 例 | 未確定である |

本書は対象の仕様を示します。
EOF
  assert "ケース5(表の行は無視)" 0 run_check "$tmpdir/case5.md"

  # ケース6: 存在しないパス → 終了コード2
  assert "ケース6(対象なし)" 2 run_check "$tmpdir/no-such-file.md"

  echo "self-test: ${pass} PASS, ${fail} FAIL"
  [ "$fail" -eq 0 ]
}

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi
  if [ "$#" -eq 0 ]; then
    echo "使い方: $0 <ファイルまたはディレクトリ...> | --self-test" >&2
    exit 2
  fi
  run_check "$@"
  exit $?
}

main "$@"
