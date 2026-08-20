#!/usr/bin/env bash
# 疑似コードへのコード混入検査
#
# 目的:
#   `delivery-payload/templates/リバース検証/` 配下の詳細設計書テンプレートが
#   持つ「疑似コード」の節は、分岐と繰り返しの入れ子だけを日本語で書く場所で
#   あり、実際のコード（言語の構文・変数名・API 名）を貼ることを禁じる
#   （`docs/tasks/設計書へ疑似コードと戻り値を足す指示書.md` の「決めた線引き」）。
#   この禁止は文章の意味を読む必要があり機械では完全には判定できないが、
#   言語の構文らしい記号・キーワードの出現は機械的に検出できる。
#
# 使い方:
#   check-pseudocode-code-mixing.sh [<リポジトリルート>]
#   check-pseudocode-code-mixing.sh --self-test
#
# 判定:
#   `## ... 疑似コード` 見出しから次の `## ` 見出し（または EOF）までの本文を
#   節の中身として抽出する。HTML コメント行（`<!--` で始まる行、複数行コメントの
#   継続行を含む）は指示文であり検査対象から除く。中身の各行が次のいずれかの
#   パターンに一致すれば不合格とする。
#     - 中括弧 `{` `}`
#     - アロー関数 `=>`
#     - メソッドチェーンの矢印 `->`（1-239）
#     - 厳密等価 `===`
#     - 文末セミコロン `;`
#     - `if (` `for (` `function ` の並び
#     - 実装の変数名（`$` シジルの直後に英字・アンダースコアが続く識別子。
#       `$_::U` の類。1-239）。`::` 単独では検出しない。バッチ・帳票・
#       外部連携・テーブルの実装契約が想定する正当な関数名（`Page::Bid::
#       pageMain` の類）と衝突するため、`$` シジルを必須にする複合条件と
#       した
#
#   1-239 以前は「言語の構文・変数名・API 名は使わない」という記入規則
#   だったが、関数名（§8/§12/§18 実装契約が定めるもの）は設計が決める
#   事項であり禁止対象ではない。本検査は関数名を許容し、実装言語の記法と
#   実装の変数名だけを検出する（`Page::Bid::pageMain` のような関数名は
#   `$` シジルを伴わないため誤検知しない）。
#
# 終了コード:
#   0 = 混入なし（または疑似コードの節を持つファイルが 0 件）
#   1 = 1 件以上のコード混入を検出
set -uo pipefail

CODE_RE='[{}]|=>|->|===|;|if \(|for \(|function |\$[A-Za-z_]'

# 疑似コードの節の中身（見出し行・HTML コメント行を除く）を1行ずつ返す。
# 出力は "<元のファイル内行番号>:<内容>" 形式。
extract_pseudocode_body() {
  local f="$1"
  awk '
    /^## .*疑似コード/ { insec=1; next }
    /^## / { insec=0 }
    insec && /^[[:space:]]*<!--/ { incomment=1 }
    insec && !incomment { print NR ":" $0 }
    incomment && /-->[[:space:]]*$/ { incomment=0; next }
  ' "$f"
}

scan_file() {
  local f="$1" rc=0
  local line lineno content
  while IFS= read -r line; do
    lineno="${line%%:*}"
    content="${line#*:}"
    [ -z "$content" ] && continue
    if printf '%s' "$content" | grep -qE "$CODE_RE"; then
      printf 'FAIL %s:%s コードらしい記法が疑似コードの節に混入: %s\n' "$f" "$lineno" "$content"
      rc=1
    fi
  done < <(extract_pseudocode_body "$f")
  return "$rc"
}

run_check() {
  local root="$1" rc=0 files=0 hits=0 f
  while IFS= read -r f; do
    grep -q '疑似コード' "$f" 2>/dev/null || continue
    hits=$((hits + 1))
    scan_file "$f" || rc=1
  done < <(find "$root/delivery-payload/templates/リバース検証" -type f -name '*.md' 2>/dev/null | sort)
  files="$hits"
  if [ "$files" -eq 0 ]; then
    echo "SKIP: 疑似コードの節を持つテンプレートが無い"
    return 0
  fi
  if [ "$rc" -eq 0 ]; then
    echo "CLEAN: $files 件のテンプレートの疑似コードにコード混入はない"
  fi
  return "$rc"
}

self_test() {
  local tmp pass=0 fail=0 got
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-pseudocode-code-mixing-self-test.XXXXXX")" || {
    echo "self-test: 一時ディレクトリを作成できない" >&2
    return 1
  }
  mkdir -p "$tmp/delivery-payload/templates/リバース検証/API"

  assert() {
    local name="$1" want="$2" actual="$3"
    if [ "$want" = "$actual" ]; then
      echo "  [PASS] $name"
      pass=$((pass + 1))
    else
      echo "  [FAIL] ${name}（期待 ${want}・実際 ${actual}）"
      fail=$((fail + 1))
    fi
  }

  local target="$tmp/delivery-payload/templates/リバース検証/API/API詳細設計書.md"

  printf '## §5 疑似コード\n\n利用者の権限が管理者なら、締め日を過ぎた明細も対象へ含める\n\n## §6 データアクセス\n' > "$target"
  run_check "$tmp" >/dev/null 2>&1; got=$?
  assert "日本語だけの疑似コードは合格" 0 "$got"

  printf '## §5 疑似コード\n\nif (user.role === %sadmin%s) { includeClosedItems() }\n\n## §6 データアクセス\n' "'" "'" > "$target"
  run_check "$tmp" >/dev/null 2>&1; got=$?
  assert "if と === と中括弧を含むコードは不合格" 1 "$got"

  printf '## §5 疑似コード\n\nconst x = 1;\n\n## §6 データアクセス\n' > "$target"
  run_check "$tmp" >/dev/null 2>&1; got=$?
  assert "セミコロンを含む行は不合格" 1 "$got"

  printf '## §5 疑似コード\n\n<!-- 分岐と繰り返しの入れ子だけを日本語で書く。if (x) は使わない -->\n\n利用者が管理者なら含める\n\n## §6 データアクセス\n' > "$target"
  run_check "$tmp" >/dev/null 2>&1; got=$?
  assert "コメント内の例示コードは検査対象外" 0 "$got"

  printf '## §1 概要\n\n本文には疑似コードという語を含まない節\n' > "$target"
  run_check "$tmp" >/dev/null 2>&1; got=$?
  assert "疑似コードの節を持たないファイルはスキップ" 0 "$got"

  printf '## §5 疑似コード\n\n利用者が管理者なら対象へ含める\n\n## §6 戻り値の一覧（=>を含む見出しの次節）\n\nconst y = () => 1;\n' > "$target"
  run_check "$tmp" >/dev/null 2>&1; got=$?
  assert "次の見出し以降の本文は検査対象外" 0 "$got"

  # 1-239: メソッドチェーンの矢印 -> を含む行は不合格。
  printf '## §5 疑似コード\n\nresult = builder->build();\n\n## §6 データアクセス\n' > "$target"
  run_check "$tmp" >/dev/null 2>&1; got=$?
  assert "1-239: メソッドチェーンの矢印(->)を含む行は不合格" 1 "$got"

  # 1-239: 実装の変数名（$シジル）を含む行は不合格。
  printf '## §5 疑似コード\n\n%s_::U を利用者情報として扱う\n\n## §6 データアクセス\n' '$' > "$target"
  run_check "$tmp" >/dev/null 2>&1; got=$?
  assert '1-239: $シジルの実装変数名を含む行は不合格' 1 "$got"

  # 1-239: 関数名(§8/§12/§18実装契約が定めるもの)は許容する。::単独では
  # 検出しない（$シジルを伴わない関数名は誤検知しない）。
  printf '## §5 疑似コード\n\nPage::Bid::pageMain を呼び出し、入札額を検証する\n\n## §6 データアクセス\n' > "$target"
  run_check "$tmp" >/dev/null 2>&1; got=$?
  assert "1-239: 関数名(Page::Bid::pageMainの類)は合格" 0 "$got"

  # 1-239: 変数の役割を日本語で述べる記述は合格する。
  printf '## §5 疑似コード\n\n実行コンテキストの利用者情報を取得する\n\n## §6 データアクセス\n' > "$target"
  run_check "$tmp" >/dev/null 2>&1; got=$?
  assert "1-239: 役割を表す日本語の記述は合格" 0 "$got"

  rm -rf "$tmp"
  echo "self-test: $pass PASS, $fail FAIL"
  [ "$fail" -eq 0 ]
}

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi
  local root="${1:-}"
  if [ -z "$root" ]; then
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  fi
  run_check "$root"
  exit $?
}

main "$@"
