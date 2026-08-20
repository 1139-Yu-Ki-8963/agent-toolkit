#!/usr/bin/env bash
# check-routine-procedure-doc.sh — 繰り返す作業の手順書の決まりの linter
#
# timing: PreToolUse(Bash)
# 対象規約: 繰り返す作業の手順書の決まり
#
# 対象の規則（検査列に「静的解析:」を含む3件すべてを検査する）:
#   1. 手順を文書に固定する
#      — リポジトリ内に定型作業の手順書が実在するかを走査する
#   2. 実行の間隔と起点を書く
#      — 手順書に実行の間隔または起点を示す記述があるかを走査する
#   3. 失敗したときの扱いを書く
#      — 手順書に失敗時の扱いを述べた見出しまたは記述があるかを走査する
#
# 判定の設計:
#   手順書はファイル名に「手順書」を含む文書として cwd 配下（.git 配下を
#   除く）を走査して特定する（既知の慣行）。実行の間隔・起点、失敗時の
#   扱いは、いずれも手順書の中身に対する語彙の共起検査であり、3規則すべて
#   同じ手順書の集合を対象にするため、探索を1箇所に共通化する。
#
# 除外条件（誤検知回避）:
#   - tool_name が Bash 以外 → 対象外
#   - command に git と commit の両方を含まない → 対象外
#   - cwd が空・存在しない → 対象外
#   - 手順書が1件も見当たらない → 実行の間隔と起点、失敗したときの扱いの
#     2規則は対象外（判定できないため）
#
# 既知の限界:
#   - 手順書の実在はファイル名の一致のみで判定する。中身が実際に定型作業の
#     手順を記述しているかまでは確認しない
#   - 実行の間隔・起点、失敗時の扱いは語彙の出現有無でしか判定しない。
#     記述が実行者によらず一意に定まる内容かまでは判定しない（規約が定める
#     レビュー観点はレビュー担当に委ねる）
#
# このスクリプトは止めない。3規則とも通知・許可・対象外のみを返し、
# 判定の出力は標準エラーへ出す。停止すべき理由が無いため hook の
# additionalContext は使わない。
#
# 使い方:
#   フック本体として: PreToolUse(Bash) の入力 JSON を stdin から受け取る
#   単体実行: check-routine-procedure-doc.sh --self-test
set -uo pipefail

INTERVAL_RE='(毎日|毎週|毎月|日次|週次|月次|間隔|起点|ごとに)'
FAILURE_STATE_RE='(失敗|エラー|異常)'
FAILURE_ACTION_RE='(やり直|再開|再実行|リトライ)'

# cwd 配下（.git 配下を除く）からファイル名に「手順書」を含むファイルを
# すべて返す（1行1件）
find_procedure_docs() {
  local cwd="$1"
  find "$cwd" -type f -not -path '*/.git/*' -name '*手順書*' 2>/dev/null
}

judge() {
  # $1: cwd
  # 標準出力: 判定理由（1行1件、複数行）。戻り値は常に0。
  local cwd="$1"
  local docs_file count
  docs_file="$(mktemp "${TMPDIR:-/tmp}/check-routine-procedure-doc-docs.XXXXXX")"
  find_procedure_docs "$cwd" > "$docs_file"
  count="$(grep -c . "$docs_file" 2>/dev/null || true)"
  [ -z "$count" ] && count=0

  if [ "$count" -eq 0 ]; then
    echo "通知[手順を文書に固定する]: 定型作業の手順書が見当たりません。手順を文書へ書いてください"
    echo "対象外[実行の間隔と起点を書く]: 手順書が見当たらないため判定していません"
    echo "対象外[失敗したときの扱いを書く]: 手順書が見当たらないため判定していません"
    rm -f "$docs_file"
    return 0
  fi

  echo "許可[手順を文書に固定する]: 手順書が実在します（${count}件）"

  local interval_missing="" failure_missing="" doc relpath body
  while IFS= read -r doc; do
    [ -z "$doc" ] && continue
    body="$(cat "$doc" 2>/dev/null)"
    relpath="${doc#"$cwd"/}"

    if [ -z "$interval_missing" ] && ! printf '%s' "$body" | grep -qE "$INTERVAL_RE"; then
      interval_missing="$relpath"
    fi

    if [ -z "$failure_missing" ]; then
      if ! { printf '%s' "$body" | grep -qE "$FAILURE_STATE_RE" && printf '%s' "$body" | grep -qE "$FAILURE_ACTION_RE"; }; then
        failure_missing="$relpath"
      fi
    fi
  done < "$docs_file"
  rm -f "$docs_file"

  if [ -n "$interval_missing" ]; then
    echo "通知[実行の間隔と起点を書く]: 手順書（${interval_missing}）に実行の間隔または起点の記述がありません"
  else
    echo "許可[実行の間隔と起点を書く]: すべての手順書に実行の間隔または起点の記述があります"
  fi

  if [ -n "$failure_missing" ]; then
    echo "通知[失敗したときの扱いを書く]: 手順書（${failure_missing}）に失敗したときの扱いの記述がありません"
  else
    echo "許可[失敗したときの扱いを書く]: すべての手順書に失敗したときの扱いの記述があります"
  fi

  return 0
}

run_hook() {
  local input
  input="$(cat)"
  [ -z "$input" ] && exit 0

  local tool
  tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
  [ "$tool" != "Bash" ] && exit 0

  local cmd cwd
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
  if ! printf '%s' "$cmd" | grep -q 'git' || ! printf '%s' "$cmd" | grep -q 'commit'; then
    exit 0
  fi

  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
  [ -z "$cwd" ] && exit 0
  [ -d "$cwd" ] || exit 0

  judge "$cwd" >&2
  exit 0
}

self_test() {
  local rc=0 msg

  # 系1: 手順書が1件も無い → 通知（手順を文書に固定する）
  local tmp1
  tmp1="$(mktemp -d "${TMPDIR:-/tmp}/check-routine-procedure-doc-self-test.XXXXXX")"
  mkdir -p "$tmp1/docs"
  printf '# メモ\n' > "$tmp1/docs/メモ.md"
  msg="$(judge "$tmp1")"
  rm -rf "$tmp1"
  if printf '%s' "$msg" | grep -qF '通知[手順を文書に固定する]'; then
    echo "  [PASS] 系1: 手順書が無ければ通知される（${msg}）"
  else
    echo "  [FAIL] 系1: 手順書が無いのに通知されない（${msg})" >&2
    rc=1
  fi

  # 系2: 手順書が1件ある → 許可（手順を文書に固定する）
  local tmp2
  tmp2="$(mktemp -d "${TMPDIR:-/tmp}/check-routine-procedure-doc-self-test.XXXXXX")"
  mkdir -p "$tmp2/docs"
  printf '# 定例棚卸し手順書\n\n## 実行の間隔\n毎月1日を起点に実行する。\n\n## 失敗したとき\n失敗した場合は最初からやり直す。\n' > "$tmp2/docs/定例棚卸し手順書.md"
  msg="$(judge "$tmp2")"
  rm -rf "$tmp2"
  if printf '%s' "$msg" | grep -qF '許可[手順を文書に固定する]'; then
    echo "  [PASS] 系2: 手順書が実在すれば許可される（${msg}）"
  else
    echo "  [FAIL] 系2: 手順書があるのに許可されない（${msg})" >&2
    rc=1
  fi

  # 系3: 手順書が複数ある → 許可（手順を文書に固定する。件数を返す）
  local tmp3
  tmp3="$(mktemp -d "${TMPDIR:-/tmp}/check-routine-procedure-doc-self-test.XXXXXX")"
  mkdir -p "$tmp3/docs"
  printf '# 定例棚卸し手順書\n\n## 実行の間隔\n毎月1日を起点に実行する。\n\n## 失敗したとき\n失敗した場合は最初からやり直す。\n' > "$tmp3/docs/定例棚卸し手順書.md"
  printf '# 監査手順書\n\n## 実行の間隔\n毎週月曜を起点に実行する。\n\n## 失敗したとき\nエラーが出た場合は再開する。\n' > "$tmp3/docs/監査手順書.md"
  msg="$(judge "$tmp3")"
  rm -rf "$tmp3"
  if printf '%s' "$msg" | grep -qF '許可[手順を文書に固定する]: 手順書が実在します（2件）'; then
    echo "  [PASS] 系3: 手順書が複数あれば件数付きで許可される（${msg}）"
  else
    echo "  [FAIL] 系3: 複数件の件数表示が正しくない（${msg})" >&2
    rc=1
  fi

  # 系4（近傍事例）: 「手順書」を含まない文書は対象外（手順を文書に固定する。0件扱い）
  local tmp4
  tmp4="$(mktemp -d "${TMPDIR:-/tmp}/check-routine-procedure-doc-self-test.XXXXXX")"
  mkdir -p "$tmp4/docs"
  printf '# 定例棚卸しの手引き\n\n## 実行の間隔\n毎月実行する。\n' > "$tmp4/docs/定例棚卸しの手引き.md"
  msg="$(judge "$tmp4")"
  rm -rf "$tmp4"
  if printf '%s' "$msg" | grep -qF '通知[手順を文書に固定する]'; then
    echo "  [PASS] 系4: ファイル名に「手順書」が無ければ0件として通知される（${msg}）"
  else
    echo "  [FAIL] 系4: 「手順書」を含まない文書が誤って手順書とみなされた（${msg})" >&2
    rc=1
  fi

  # 系5: 手順書に実行の間隔・起点の記述が無い → 通知（実行の間隔と起点を書く）
  local tmp5
  tmp5="$(mktemp -d "${TMPDIR:-/tmp}/check-routine-procedure-doc-self-test.XXXXXX")"
  mkdir -p "$tmp5/docs"
  printf '# 定例棚卸し手順書\n\n## 手順\n棚卸しを行う。\n\n## 失敗したとき\n失敗した場合は最初からやり直す。\n' > "$tmp5/docs/定例棚卸し手順書.md"
  msg="$(judge "$tmp5")"
  rm -rf "$tmp5"
  if printf '%s' "$msg" | grep -qF '通知[実行の間隔と起点を書く]'; then
    echo "  [PASS] 系5: 間隔・起点の記述が無ければ通知される（${msg}）"
  else
    echo "  [FAIL] 系5: 記述が無いのに通知されない（${msg})" >&2
    rc=1
  fi

  # 系6: 手順書に実行の間隔・起点の記述がある（複数手順書ですべて揃う）→ 許可（実行の間隔と起点を書く）
  local tmp6
  tmp6="$(mktemp -d "${TMPDIR:-/tmp}/check-routine-procedure-doc-self-test.XXXXXX")"
  mkdir -p "$tmp6/docs"
  printf '# 定例棚卸し手順書\n\n## 実行の間隔\n毎月1日を起点に実行する。\n\n## 失敗したとき\nエラーが出た場合は再開する。\n' > "$tmp6/docs/定例棚卸し手順書.md"
  printf '# 監査手順書\n\n## 実行の間隔\n毎週ごとに実行する。\n\n## 失敗したとき\n失敗した場合はやり直す。\n' > "$tmp6/docs/監査手順書.md"
  msg="$(judge "$tmp6")"
  rm -rf "$tmp6"
  if printf '%s' "$msg" | grep -qF '許可[実行の間隔と起点を書く]'; then
    echo "  [PASS] 系6: すべての手順書に記述があれば許可される（${msg}）"
  else
    echo "  [FAIL] 系6: 記述があるのに許可されない（${msg})" >&2
    rc=1
  fi

  # 系7: 手順書に失敗したときの扱いの記述が無い（状態語のみで対応の動詞が無い）→ 通知（失敗したときの扱いを書く）
  local tmp7
  tmp7="$(mktemp -d "${TMPDIR:-/tmp}/check-routine-procedure-doc-self-test.XXXXXX")"
  mkdir -p "$tmp7/docs"
  printf '# 定例棚卸し手順書\n\n## 実行の間隔\n毎月1日を起点に実行する。\n\n## 注意\nエラーが起こることがある。\n' > "$tmp7/docs/定例棚卸し手順書.md"
  msg="$(judge "$tmp7")"
  rm -rf "$tmp7"
  if printf '%s' "$msg" | grep -qF '通知[失敗したときの扱いを書く]'; then
    echo "  [PASS] 系7: 失敗時の扱いの記述が無ければ通知される（${msg}）"
  else
    echo "  [FAIL] 系7: 記述が無いのに通知されない（${msg})" >&2
    rc=1
  fi

  # 系8: 手順書に失敗したときの扱いの記述がある → 許可（失敗したときの扱いを書く）
  local tmp8
  tmp8="$(mktemp -d "${TMPDIR:-/tmp}/check-routine-procedure-doc-self-test.XXXXXX")"
  mkdir -p "$tmp8/docs"
  printf '# 定例棚卸し手順書\n\n## 実行の間隔\n毎月1日を起点に実行する。\n\n## 失敗したとき\n異常を検知したら再実行する。\n' > "$tmp8/docs/定例棚卸し手順書.md"
  msg="$(judge "$tmp8")"
  rm -rf "$tmp8"
  if printf '%s' "$msg" | grep -qF '許可[失敗したときの扱いを書く]'; then
    echo "  [PASS] 系8: 失敗時の扱いの記述があれば許可される（${msg}）"
  else
    echo "  [FAIL] 系8: 記述があるのに許可されない（${msg})" >&2
    rc=1
  fi

  # 系9: cwd が空 → run_hook 経由で対象外（3規則とも判定しない）。judge は cwd 前提のため run_hook 経由で確認する
  local out rc9
  out="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":""}' | bash "$0" 2>&1 1>/dev/null)"
  rc9=$?
  if [ "$rc9" -eq 0 ] && [ -z "$out" ]; then
    echo "  [PASS] 系9: cwd が空なら何も出力せず対象外になる"
  else
    echo "  [FAIL] 系9: cwd が空なのに出力または異常終了した（rc=${rc9}, ${out})" >&2
    rc=1
  fi

  # 系10（近傍事例）: git commit 以外のコマンド → run_hook 経由で対象外
  local tmp10 out10 rc10
  tmp10="$(mktemp -d "${TMPDIR:-/tmp}/check-routine-procedure-doc-self-test.XXXXXX")"
  out10="$(printf '%s' "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npm test\"},\"cwd\":\"${tmp10}\"}" | bash "$0" 2>&1 1>/dev/null)"
  rc10=$?
  rm -rf "$tmp10"
  if [ "$rc10" -eq 0 ] && [ -z "$out10" ]; then
    echo "  [PASS] 系10: git commit 以外のコマンドは対象外になる"
  else
    echo "  [FAIL] 系10: git commit 以外なのに出力または異常終了した（rc=${rc10}, ${out10})" >&2
    rc=1
  fi

  # 系11: tool_name が Bash 以外 → run_hook 経由で対象外
  local out11 rc11
  out11="$(printf '%s' '{"tool_name":"Write","tool_input":{"command":"git commit -m x"},"cwd":"/tmp"}' | bash "$0" 2>&1 1>/dev/null)"
  rc11=$?
  if [ "$rc11" -eq 0 ] && [ -z "$out11" ]; then
    echo "  [PASS] 系11: tool_name が Bash 以外は対象外になる"
  else
    echo "  [FAIL] 系11: tool_name が Bash 以外なのに出力または異常終了した（rc=${rc11}, ${out11})" >&2
    rc=1
  fi

  # 系12: run_hook 経由で git commit + 実在する cwd → 3規則とも標準エラーへ判定が出て exit 0
  local tmp12 out12 rc12
  tmp12="$(mktemp -d "${TMPDIR:-/tmp}/check-routine-procedure-doc-self-test.XXXXXX")"
  mkdir -p "$tmp12/docs"
  printf '# 定例棚卸し手順書\n\n## 実行の間隔\n毎月1日を起点に実行する。\n\n## 失敗したとき\n異常を検知したら再実行する。\n' > "$tmp12/docs/定例棚卸し手順書.md"
  out12="$(printf '%s' "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m x\"},\"cwd\":\"${tmp12}\"}" | bash "$0" 2>&1 1>/dev/null)"
  rc12=$?
  rm -rf "$tmp12"
  if [ "$rc12" -eq 0 ] && printf '%s' "$out12" | grep -qF '許可[手順を文書に固定する]' && printf '%s' "$out12" | grep -qF '許可[実行の間隔と起点を書く]' && printf '%s' "$out12" | grep -qF '許可[失敗したときの扱いを書く]'; then
    echo "  [PASS] 系12: git commit 経由で3規則とも判定が出力され exit 0 になる"
  else
    echo "  [FAIL] 系12: git commit 経由の判定出力または終了コードが期待どおりでない（rc=${rc12}, ${out12})" >&2
    rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

case "${1:-}" in
  --self-test) self_test; exit $? ;;
  *) run_hook ;;
esac
