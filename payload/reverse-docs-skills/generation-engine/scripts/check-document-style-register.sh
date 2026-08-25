#!/usr/bin/env bash
# 文書の文体（敬体/常体）検査
#
# 顧客提示の文書（設計書・単位ごとの資料）は敬体（です・ます）で書く。
# 記入規則・検証の記録は常体でよい（delivery-payload/references/設計書様式.md §8）。
# 本スクリプトは、指定したMarkdownファイルの本文（HTMLコメント・表の行・見出し行を
# 除いた地の文）を文単位（「。」区切り）に分割し、常体の文末（である・だ）を検出する。
# 敬体の文末（です・ます・でしょう・ましょう・ください）は無視する。
#
# 除外（1-260）:
#   様式の定義（設計書様式.md §8）が「私たちの作業のための文書は常体でよい」と
#   認めた文書は、この検査の対象から除外する。除外の対象一覧は本スクリプトへ
#   直書きせず、delivery-payload/references/document-style-exclusions.json の
#   excludedBasenames をファイル名（basename）の完全一致で読む。一覧に無い
#   ファイル名は除外しない（1-266・1-267と同じく、走査条件そのものを
#   定義ファイル側に持たせる）。除外した件数は実行結果の末尾へ
#   「除外 N 件」の形で常に出す。
#
# 判定不能規約（.claude/rules/always/verification/indeterminate-result/rule.md）に従い、
# mktempの失敗は[UNKNOWN]・終了コード2で区別する（check-portal-catalog.shに倣う）。
set -uo pipefail

# 除外一覧の定義ファイルを持つこのリポジトリ自身のルートを、スクリプトの
# 設置場所から解決する。走査対象（run_checkの引数）が別プロジェクトの
# パスであっても、除外一覧は常にこのリポジトリの定義ファイルを読む
# （check-design-code-consistency.shのrepo_root解決と同じ考え方）。
_repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

# 除外の対象ファイル名（basename）を定義ファイルから1行1件で返す。
# 定義ファイルが無い・読めない場合は何も返さない（除外0件として扱う）。
_excluded_basenames() {
  local repo_root="$1"
  jq -r '.excludedBasenames[]?.basename // empty' \
    "$repo_root/delivery-payload/references/document-style-exclusions.json" 2>/dev/null
}

# 対象ファイルのbasenameが除外一覧に完全一致すれば除外対象と判定する。
# 一覧に無いファイル名は除外しない（1-260の完了の判定6）。
_is_excluded_file() {
  local repo_root="$1" f="$2"
  local base name
  base="$(basename "$f")"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if [ "$base" = "$name" ]; then
      return 0
    fi
  done < <(_excluded_basenames "$repo_root")
  return 1
}

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

  local repo_root
  repo_root="$(_repo_root)"

  local total_fail=0
  local clean=0
  local excluded=0
  for f in "${files[@]}"; do
    if _is_excluded_file "$repo_root" "$f"; then
      excluded=$((excluded + 1))
      continue
    fi
    local out
    out="$(scan_file "$f")"
    if [ -n "$out" ]; then
      echo "$out"
      total_fail=$((total_fail + 1))
    else
      clean=$((clean + 1))
    fi
  done

  local rc=0
  if [ "$total_fail" -gt 0 ]; then
    echo "FAIL: 常体の文末を持つ文書 ${total_fail} 件（CLEAN ${clean} 件）"
    rc=1
  else
    echo "CLEAN: ${clean} 件の文書に常体の文末はない"
  fi
  echo "除外 ${excluded} 件"
  return "$rc"
}

self_test() {
  local tmpdir
  # 置き場を明示するのは、引数なしの mktemp が既定の置き場へ書こうとして失敗する環境があるためである（実測 2026-08-24）。素直な mktemp へ戻さない。
  if ! tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/$(basename "${BASH_SOURCE[0]}" .sh).XXXXXX" 2>/dev/null)" || [ -z "$tmpdir" ]; then
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

  assert_output_contains() {
    local label="$1" needle="$2"
    shift 2
    local out
    out="$("$@" 2>/dev/null)"
    if grep -qF -- "$needle" <<< "$out"; then
      echo "  [PASS] $label"
      pass=$((pass + 1))
    else
      echo "  [FAIL] $label (出力に「$needle」が含まれない)" >&2
      echo "$out" >&2
      fail=$((fail + 1))
    fi
  }

  # ケース7〜9: 様式の定義（設計書様式.md §8）が常体でよいと認めた文書
  # （SKILL.md・design-notes.md・rule-reviewer.md）は、常体だけの本文でも
  # 除外され不合格にならない → CLEAN(0)。除外一覧は
  # delivery-payload/references/document-style-exclusions.json から読む
  # （本スクリプトへ直書きしない。完了の判定3）。
  mkdir -p "$tmpdir/excluded"
  cat > "$tmpdir/excluded/SKILL.md" <<'EOF'
# サンプルスキル

本書は対象の仕様を示す。この項目は未確定である。
EOF
  assert "ケース7(SKILL.mdは除外され不合格にならない)" 0 run_check "$tmpdir/excluded/SKILL.md"

  cat > "$tmpdir/excluded/design-notes.md" <<'EOF'
# 設計判断

この検査は環境依存のため判定できないだ。理由を記録する。
EOF
  assert "ケース8(design-notes.mdは除外され不合格にならない)" 0 run_check "$tmpdir/excluded/design-notes.md"

  cat > "$tmpdir/excluded/rule-reviewer.md" <<'EOF'
# レビュー担当の定義

この担当は規約の合否を判定する。差し戻しの基準は明確である。
EOF
  assert "ケース9(rule-reviewer.mdは除外され不合格にならない)" 0 run_check "$tmpdir/excluded/rule-reviewer.md"

  # ケース10: 除外一覧に完全一致しないファイル名（basenameが違う）は
  # 除外されず、顧客提示文書と同様に常体だけなら従来どおり不合格になる
  # （完了の判定4・6。定義の一覧に無い文書を誤って除外していないことの
  # 確認）。
  cat > "$tmpdir/excluded/design-notes-old.md" <<'EOF'
# 旧い記録

この文書は対象の仕様を示すものである。
EOF
  assert "ケース10(一覧に無い名前は除外されず不合格のまま)" 1 run_check "$tmpdir/excluded/design-notes-old.md"

  # ケース11: 除外対象と非除外対象が混在するディレクトリを検査すると、
  # 除外された件数が実行結果の末尾に「除外 N 件」として出る
  # （完了の判定5）。非除外の文書は敬体のみなのでCLEAN(0)のまま。
  mkdir -p "$tmpdir/mixed"
  cat > "$tmpdir/mixed/SKILL.md" <<'EOF'
# サンプルスキル

本書は対象の仕様を示す。
EOF
  cat > "$tmpdir/mixed/design.md" <<'EOF'
# 設計書

本書は対象の仕様を示します。
EOF
  assert "ケース11(除外と非除外の混在はCLEAN)" 0 run_check "$tmpdir/mixed"
  assert_output_contains "ケース11(除外件数が出力へ含まれる)" "除外 1 件" run_check "$tmpdir/mixed"

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
