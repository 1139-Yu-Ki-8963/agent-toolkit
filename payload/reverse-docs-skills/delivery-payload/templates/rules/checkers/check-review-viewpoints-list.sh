#!/usr/bin/env bash
# check-review-viewpoints-list.sh — レビューの観点の決まりの linter
#
# timing: PreToolUse(Write)
# 対象規約: レビューの観点の決まり
#   - 規約が求めるレビューを観点とする
#   - 機械で見つかるものは機械へ任せる
#
# 判定:
#   （規約が求めるレビューを観点とする）
#   書き込み先が規約の定義ファイル（rule.md、または rules/tool-defined/ 配下）の
#   場合、本文の「## 規則」の表の各行（データ行のみ。見出し行・区切り行は除く）の
#   検査列（4列目）が「静的解析:」「テスト:」「レビュー:」「判定不能:」「不可:」の
#   いずれかで始まっているかを走査する。始まらない行が1つでもあれば違反とする。
#
#   （機械で見つかるものは機械へ任せる）
#   cwd 直下に静的解析の設定（.eslintrc 系・eslint.config 系・biome.json・
#   ruff.toml・.flake8・.rubocop.yml、または [tool.ruff]/[tool.black]/
#   [tool.flake8] のいずれかの節を含む pyproject.toml）が実在するかを走査する。
#
# 判定の設計:
#   「規約が求めるレビューを観点とする」は、レビューの観点を各規約の規則
#   そのものが持ち、別の一覧文書を持たないことを求める規則である。この規則が
#   成立する前提は、各規約の規則表が検査の手段（静的解析・テスト・レビュー・
#   判定不能・不可のいずれか）を明示していることにある。手段が明示されていない
#   行は、レビューの観点として何を見ればよいかが規則表から読み取れない。
#   よって検査は、手段の接頭辞の有無をファイルの内容だけで機械的に判定する。
#   検査列の中身が妥当かどうか（選んだ手段が適切か）までは判定せず、あくまで
#   手段が明示されているかどうかの形式確認にとどめる。
#
# 既知の限界:
#   - スクリプトの名前は check-review-viewpoints-list.sh のまま変更していない。
#     旧規則「観点の一覧を先に持つ」の検査として付けた名前であり、現在の
#     判定内容（規約が求めるレビューを観点とする・機械で見つかるものは機械へ
#     任せる）とは名前が一致しない。改名は別の指示書が扱う
#   - 規約が求めるレビューを観点とする: 検査列の接頭辞の有無だけを見る。選んだ
#     手段が妥当かどうかまでは判定しない
#   - 機械で見つかるものは機械へ任せる: 静的解析の設定の実在だけを見る。
#     レビューの観点から機械が見つけるものが実際に外れているかまでは判定
#     しない。規約が観点の一覧を別の文書として持たないと定めているため、
#     突き合わせる相手となる一覧文書が存在しない
#
# 除外条件（誤検知回避）:
#   - tool_name が Write 以外 → 対象外
#   - 規約が求めるレビューを観点とする: file_path が rule.md で終わらず、かつ
#     rules/tool-defined/ を含まない → 対象外。content に「## 規則」の見出しが
#     無い → 対象外
#   - 機械で見つかるものは機械へ任せる: cwd が空・存在しない → 対象外
#
# 使い方:
#   フック本体として: PreToolUse(Write) の入力 JSON を stdin から受け取る
#   単体実行: check-review-viewpoints-list.sh --self-test
#
# 止めるか知らせるか:
#   規約が求めるレビューを観点とする: 止める（検査手段が明示されない規則が資料として確定すると、後から見返しても何を機械が見て何を人が見るべきか復元できないため）
#   機械で見つかるものは機械へ任せる: 知らせる（静的解析の設定は導入が進めば自然に整うものであり、今すぐ止める必要はないため）
#
# 逃げ道:
#   REVIEW_VIEWPOINTS_LIST_SKIP_REASON に理由を書けば通る。理由が空の場合は通らない
set -uo pipefail

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${REVIEW_VIEWPOINTS_LIST_SKIP_REASON:-}" ]; then
    echo "[REVIEW-VIEWPOINTS-LIST-SKIP] 理由: ${REVIEW_VIEWPOINTS_LIST_SKIP_REASON}"
    return 0
  fi
  return 1
}

# 指定した rule.md 本文の「## 規則」表のデータ行から、検査列（4列目）が
# 定義済み接頭辞のいずれかで始まらない違反行の規則名を1行1件、標準出力へ列挙する。
scan_missing_means() {
  local content="$1"
  printf '%s\n' "$content" | awk '
    BEGIN { in_section = 0 }
    /^## 規則/ { in_section = 1; next }
    /^## / && in_section == 1 { in_section = 0 }
    in_section == 1 && /^\|/ {
      line = $0
      if (line ~ /^\| *規則 *\|/) next
      if (line ~ /^\|[-: ]+\|[-: ]+\|/) next
      n = split(line, cols, "|")
      name = cols[2]; gsub(/^[ \t]+|[ \t]+$/, "", name)
      check = cols[n-1]; gsub(/^[ \t]+|[ \t]+$/, "", check)
      # 検査の欄が空の行も、手段が明示されていない行である。
      # 空を見逃していたため、「目で見る」のように手段になっていない語を
      # 書いた行は止める一方、何も書かない行は通していた
      # （実測 2026-08-24: 空の欄を与えて分かった）。
      # 何も書かないほうが通るのでは、手段を書かせる目的が果たせない。
      if (check !~ /^(静的解析|テスト|レビュー|判定不能|不可):/) {
        print name
      }
    }
  '
}

# 「規約が求めるレビューを観点とする」規則の判定
judge_review_means_declared() {
  # $1: file_path, $2: content
  local file_path="$1" content="$2"

  case "$file_path" in
    *rule.md) : ;;
    *rules/tool-defined/*) : ;;
    *)
      echo "対象外[規約が求めるレビューを観点とする]: 規約の定義ファイルではありません（${file_path}）"
      return 0
      ;;
  esac

  if ! printf '%s' "$content" | grep -qE '^## 規則'; then
    echo "対象外[規約が求めるレビューを観点とする]: 規則の節がありません"
    return 0
  fi

  local missing names="" n
  missing="$(scan_missing_means "$content")"

  if [ -n "$missing" ]; then
    while IFS= read -r n; do
      [ -z "$n" ] && continue
      names="${names}${names:+、}${n}"
    done <<< "$missing"
    echo "拒否[規約が求めるレビューを観点とする]: 検査の手段が明示されていない規則があります（${names}）"
    return 2
  fi

  echo "許可[規約が求めるレビューを観点とする]: すべての規則に検査の手段が明示されています"
  return 0
}

# 「機械で見つかるものは機械へ任せる」規則の判定
judge_static_analysis_configured() {
  # $1: cwd
  local cwd="$1"

  if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
    echo "対象外[機械で見つかるものは機械へ任せる]: 作業ディレクトリが分からないため判定していません"
    return 0
  fi

  local found="" f
  for f in "$cwd"/.eslintrc*; do
    [ -e "$f" ] && { found="$(basename "$f")"; break; }
  done
  if [ -z "$found" ]; then
    for f in "$cwd"/eslint.config*; do
      [ -e "$f" ] && { found="$(basename "$f")"; break; }
    done
  fi
  [ -z "$found" ] && [ -f "$cwd/biome.json" ] && found="biome.json"
  [ -z "$found" ] && [ -f "$cwd/ruff.toml" ] && found="ruff.toml"
  [ -z "$found" ] && [ -f "$cwd/.flake8" ] && found=".flake8"
  [ -z "$found" ] && [ -f "$cwd/.rubocop.yml" ] && found=".rubocop.yml"
  if [ -z "$found" ] && [ -f "$cwd/pyproject.toml" ]; then
    if grep -qE '^\[tool\.(ruff|black|flake8)\]' "$cwd/pyproject.toml" 2>/dev/null; then
      found="pyproject.toml"
    fi
  fi

  if [ -z "$found" ]; then
    echo "通知[機械で見つかるものは機械へ任せる]: 静的解析の設定が見当たりません。機械が見つけるものを人が見ることになります"
    return 0
  fi

  echo "許可[機械で見つかるものは機械へ任せる]: 静的解析の設定が実在します（${found}）"
  return 0
}

judge() {
  # $1: file_path, $2: content, $3: cwd
  local file_path="$1" content="$2" cwd="${3:-}"
  local rc=0 msg code

  if msg="$(judge_review_means_declared "$file_path" "$content")"; then code=0; else code=$?; fi
  echo "$msg"
  [ "$code" -eq 2 ] && rc=2

  if msg="$(judge_static_analysis_configured "$cwd")"; then code=0; else code=$?; fi
  echo "$msg"
  [ "$code" -eq 2 ] && rc=2

  return "$rc"
}

run_hook() {
  local skip_msg
  if skip_msg="$(should_skip_with_reason)"; then
    printf '%s\n' "$skip_msg" >&2
    exit 0
  fi

  local input
  input="$(cat)"
  [ -z "$input" ] && exit 0

  local tool
  tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
  [ "$tool" != "Write" ] && exit 0

  local file_path content cwd
  file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
  [ -z "$file_path" ] && exit 0
  content=$(printf '%s' "$input" | jq -r '.tool_input.content // empty' 2>/dev/null)
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)

  local msg code
  if msg="$(judge "$file_path" "$content" "$cwd")"; then code=0; else code=$?; fi

  [ "$code" -eq 0 ] && exit 0

  ctx="[REVIEW-VIEWPOINTS-LIST-BLOCK] ${msg}"
  jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  printf '%s\n' "$ctx" >&2
  exit 2
}

self_test() {
  local rc=0 msg code

  # 系1: 規約が求めるレビューを観点とする - 規約の定義ファイルではない → 対象外
  if msg="$(judge_review_means_declared "docs/design/screens/画面A/README.md" "本文")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '対象外[規約が求めるレビューを観点とする]'; then
    echo "  [PASS] 系1: 規約の定義ファイルでなければ対象外になる（${msg}）"
  else
    echo "  [FAIL] 系1: 対象外のはずが判定された、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系2: 規約が求めるレビューを観点とする - 規則の節が無い → 対象外
  local content2='# 規約

## 概要

本文のみ'
  if msg="$(judge_review_means_declared "docs/rules/example/rule.md" "$content2")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '対象外[規約が求めるレビューを観点とする]'; then
    echo "  [PASS] 系2: 規則の節が無ければ対象外になる（${msg}）"
  else
    echo "  [FAIL] 系2: 対象外のはずが判定された、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系3: 規約が求めるレビューを観点とする - 検査の手段が明示されていない規則がある → 拒否
  local content3='# 規約

## 規則

| 規則 | 内容 | 検査 |
|---|---|---|
| 規則A | 内容A | 静的解析: 何かを走査する |
| 規則B | 内容B | 手段不明のまま書かれた検査列 |'
  if msg="$(judge_review_means_declared "docs/rules/example/rule.md" "$content3")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '拒否[規約が求めるレビューを観点とする]'; then
    echo "  [PASS] 系3: 検査の手段が明示されていない規則があれば拒否される（${msg}）"
  else
    echo "  [FAIL] 系3: 明示されていないのに許可、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系4: 規約が求めるレビューを観点とする - 全行に検査の手段がある → 許可
  local content4='# 規約

## 規則

| 規則 | 内容 | 検査 |
|---|---|---|
| 規則A | 内容A | 静的解析: 何かを走査する |
| 規則B | 内容B | テスト: 何かを確かめる ／ レビュー: 何かを読んで判断する |'
  if msg="$(judge_review_means_declared "docs/rules/example/rule.md" "$content4")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '許可[規約が求めるレビューを観点とする]'; then
    echo "  [PASS] 系4: 全行に検査の手段があれば許可される（${msg}）"
  else
    echo "  [FAIL] 系4: 全行にあるのに拒否された、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系5: 機械で見つかるものは機械へ任せる - cwd が空 → 対象外
  if msg="$(judge_static_analysis_configured "")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '対象外[機械で見つかるものは機械へ任せる]'; then
    echo "  [PASS] 系5: cwdが空なら対象外になる（${msg}）"
  else
    echo "  [FAIL] 系5: 対象外のはずが判定された、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系6: 機械で見つかるものは機械へ任せる - 設定ファイルが何も無い → 通知
  local tmp6
  tmp6="$(mktemp -d "${TMPDIR:-/tmp}/check-review-viewpoints-list-self-test.XXXXXX")"
  if msg="$(judge_static_analysis_configured "$tmp6")"; then code=0; else code=$?; fi
  rm -rf "$tmp6"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '通知[機械で見つかるものは機械へ任せる]'; then
    echo "  [PASS] 系6: 設定ファイルが何も無ければ通知になる（${msg}）"
  else
    echo "  [FAIL] 系6: 通知になるはずが判定された、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系7: 機械で見つかるものは機械へ任せる - pyproject.toml はあるが該当節が無い → 通知
  local tmp7
  tmp7="$(mktemp -d "${TMPDIR:-/tmp}/check-review-viewpoints-list-self-test.XXXXXX")"
  printf '[tool.poetry]\nname = "x"\n' > "$tmp7/pyproject.toml"
  if msg="$(judge_static_analysis_configured "$tmp7")"; then code=0; else code=$?; fi
  rm -rf "$tmp7"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '通知[機械で見つかるものは機械へ任せる]'; then
    echo "  [PASS] 系7: 該当節を持たないpyproject.tomlは通知になる（${msg}）"
  else
    echo "  [FAIL] 系7: 通知になるはずが判定された、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系8: 機械で見つかるものは機械へ任せる - 静的解析の設定が実在する → 許可
  local tmp8
  tmp8="$(mktemp -d "${TMPDIR:-/tmp}/check-review-viewpoints-list-self-test.XXXXXX")"
  printf '{}\n' > "$tmp8/.eslintrc.json"
  if msg="$(judge_static_analysis_configured "$tmp8")"; then code=0; else code=$?; fi
  rm -rf "$tmp8"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '許可[機械で見つかるものは機械へ任せる]'; then
    echo "  [PASS] 系8: 静的解析の設定が実在すれば許可される（${msg}）"
  else
    echo "  [FAIL] 系8: 実在するのに拒否された、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系9: 環境変数に理由を設定 → should_skip_with_reasonが戻り値0でタグと理由を返す
  local out9
  if out9="$(REVIEW_VIEWPOINTS_LIST_SKIP_REASON="テスト用の理由" should_skip_with_reason)"; then
    if printf '%s' "$out9" | grep -qF '[REVIEW-VIEWPOINTS-LIST-SKIP]' && printf '%s' "$out9" | grep -qF 'テスト用の理由'; then
      echo "  [PASS] 系9: 理由を設定するとタグと理由付きでskipされる（${out9}）"
    else
      echo "  [FAIL] 系9: skipされたがタグまたは理由が出力に含まれない（${out9}）" >&2
      rc=1
    fi
  else
    echo "  [FAIL] 系9: 理由を設定したのにskipされなかった" >&2
    rc=1
  fi

  # 系10: 環境変数が空文字 → should_skip_with_reasonが戻り値1を返す
  if REVIEW_VIEWPOINTS_LIST_SKIP_REASON="" should_skip_with_reason >/dev/null 2>&1; then
    echo "  [FAIL] 系10: 空文字なのにskipされた" >&2
    rc=1
  else
    echo "  [PASS] 系10: 環境変数が空文字ならskipされない"
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
