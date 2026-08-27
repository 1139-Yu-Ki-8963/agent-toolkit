#!/usr/bin/env bash
# check-release-changelog-entry.sh — 版付けと公開の決まりのうち静的解析を含む5規則の linter
#
# timing: PreToolUse(Bash)
# 対象規約: 版付けと公開の決まり
#   - 変更の履歴を版ごとに残す
#   - 版の付け方を決める
#   - 公開の手順を自動で実行する
#   - 検査を通った成果物だけを公開する
#   - 公開の記録を残す
#
# 判定:
#   実行しようとしているコマンドが公開・版付けの操作（npm version / npm publish /
#   yarn publish / pnpm publish / git tag のいずれか）に一致する場合、cwd を対象に
#   上記5規則をすべて走査する。1件でも違反があれば違反理由をすべて列挙して
#   block（exit 2）する。
#
# 値の上書き:
#   「版の付け方を決める」（既定形式 `<主>.<副>.<修正>`）は、cwd 配下の
#   docs/rules/**/rule.md にある「## このプロジェクトの規則」表から、規則名が
#   完全一致する行の内容列を上書きの手掛かりとして参照する。現状は形式の
#   厳密な差し替えまでは行わず、既定の semver 形式で判定する（既知の限界を参照）。
#
# 除外条件（誤検知回避）:
#   - tool_name が Bash 以外 → 対象外
#   - command が公開・版付けの操作に一致しない → 対象外（通常のコマンドは対象外）
#   - cwd が空・参照不能 → fail-open（判定不能を block しない）
#   - コマンドに明示の版番号が含まれない（例: `npm version patch`）→
#     版の付け方の規則は fail-open（バージョン文字列を抽出できないため）
#
# 既知の限界:
#   - 「変更の履歴を版ごとに残す」は、記載された版番号が実際にこれから公開する
#     版と一致するかまでは検査しない。変更履歴ファイルに版らしい項目が
#     最低1件存在するかどうかの検査にとどまる
#   - 変更履歴ファイルの名前は CHANGELOG / HISTORY の慣行に限定して探す
#   - 「公開の記録を残す」は、既存のタグの有無か継続的な配布の設定内の記述を
#     手掛かりにする簡易な判定であり、実際に記録が残る運用になっているかまでは
#     確認しない
#   - 「版の付け方を決める」のプロジェクト上書きは、値そのもの（区切り文字や
#     桁数）までは解釈せず、既定の semver 形式で判定する
#
# 使い方:
#   フック本体として: PreToolUse(Bash) の入力 JSON を stdin から受け取る
#   単体実行: check-release-changelog-entry.sh --self-test
#
# 止めるか知らせるか:
#   変更の履歴を版ごとに残す: 止める（変更履歴を残さないまま公開すると、後から何を配ったのかを遡って再現できないため）
#   版の付け方を決める: 止める（版番号の形式が乱れたまま公開されると、後から利用者側の依存解決を壊さずに訂正できないため）
#   公開の手順を自動で実行する: 止める（手作業の公開手順で行われた公開は、後から自動化しても既に配られたものの再現性を取り戻せないため）
#   検査を通った成果物だけを公開する: 止める（テストを経ずに公開された成果物は、公開後に不具合が見つかっても配布済みの版を取り消せないため）
#   公開の記録を残す: 止める（公開の記録が残らないまま配布すると、後から何を配ったかを遡って確認できないため）
#
# 逃げ道:
#   RELEASE_CHANGELOG_ENTRY_SKIP_REASON に理由を書けば通る。理由が空の場合は通らない
set -uo pipefail

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${RELEASE_CHANGELOG_ENTRY_SKIP_REASON:-}" ]; then
    echo "[RELEASE-CHANGELOG-ENTRY-SKIP] 理由: ${RELEASE_CHANGELOG_ENTRY_SKIP_REASON}"
    return 0
  fi
  return 1
}

RELEASE_CMD_RE='(npm[[:space:]]+(version|publish)|yarn[[:space:]]+publish|pnpm[[:space:]]+publish|git[[:space:]]+tag)'
VERSION_ENTRY_RE='[0-9]+\.[0-9]+\.[0-9]+'
CI_CONFIG_GLOBS=".github/workflows .gitlab-ci.yml .circleci/config.yml"

# 「変更の履歴を版ごとに残す」規則の判定（既存。変更なし）
judge_changelog_entry() {
  # $1: cwd, $2: command
  local cwd="$1" cmd="$2"

  if ! printf '%s' "$cmd" | grep -qE "$RELEASE_CMD_RE"; then
    echo "対象外[変更の履歴を版ごとに残す]: 公開・版付けの操作ではありません"
    return 0
  fi

  if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
    echo "対象外[変更の履歴を版ごとに残す]: 作業ディレクトリを参照できないため判定不能（fail-open）"
    return 0
  fi

  local changelog
  changelog=$(find "$cwd" -maxdepth 1 -type f 2>/dev/null | grep -iE '/(changelog|history)(\.md)?$' | head -1)

  if [ -z "$changelog" ]; then
    echo "拒否[変更の履歴を版ごとに残す]: 変更履歴のファイル（CHANGELOG.md 等）が見当たりません"
    return 2
  fi

  if ! grep -qE "$VERSION_ENTRY_RE" "$changelog" 2>/dev/null; then
    echo "拒否[変更の履歴を版ごとに残す]: ${changelog} に版らしい項目（例: 1.2.3）が見当たりません"
    return 2
  fi

  echo "許可[変更の履歴を版ごとに残す]: ${changelog} に版の項目があります"
  return 0
}

# コマンド文字列から明示の版番号を抽出する（npm version 1.2.3 / git tag v1.2 等、
# ドット区切りの数字列であれば桁数を問わず抽出する。桁数の妥当性は呼び出し側で判定する）
extract_version_arg() {
  local cmd="$1" ver
  ver="$(printf '%s' "$cmd" | grep -oE '(^|[[:space:]])v?[0-9]+(\.[0-9]+)+([[:space:]]|$)' | head -1 | sed -E 's/^[[:space:]]+|[[:space:]]+$//')"
  printf '%s' "$ver"
}

# 「版の付け方を決める」規則の判定
judge_version_format() {
  local cmd="$1"
  local ver
  ver="$(extract_version_arg "$cmd")"
  if [ -z "$ver" ]; then
    echo "対象外[版の付け方を決める]: コマンドに明示の版番号が含まれないため判定不能"
    return 0
  fi
  if printf '%s' "$ver" | grep -qE '^v?[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "許可[版の付け方を決める]: ${ver} は <主>.<副>.<修正> の形式です"
    return 0
  fi
  echo "拒否[版の付け方を決める]: ${ver} は <主>.<副>.<修正> の形式ではありません"
  return 2
}

# cwd 配下の CI 設定ファイルを1件見つける。無ければ空文字。
find_ci_config() {
  local cwd="$1" f
  for f in $CI_CONFIG_GLOBS; do
    if [ -d "$cwd/$f" ]; then
      local hit
      hit="$(find "$cwd/$f" -maxdepth 2 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | head -1)"
      [ -n "$hit" ] && { printf '%s' "$hit"; return 0; }
    elif [ -f "$cwd/$f" ]; then
      printf '%s' "$cwd/$f"
      return 0
    fi
  done
  return 0
}

# 「公開の手順を自動で実行する」規則の判定
judge_release_automated() {
  local cwd="$1"
  local ci
  ci="$(find_ci_config "$cwd")"
  if [ -z "$ci" ]; then
    echo "拒否[公開の手順を自動で実行する]: 継続的な配布の設定ファイルが見当たりません"
    return 2
  fi
  if ! grep -qiE 'publish|release' "$ci" 2>/dev/null; then
    echo "拒否[公開の手順を自動で実行する]: ${ci} に公開の手順が登録されていません"
    return 2
  fi
  echo "許可[公開の手順を自動で実行する]: ${ci} に公開の手順が登録されています"
  return 0
}

# 「検査を通った成果物だけを公開する」規則の判定
judge_publish_gated_by_test() {
  local cwd="$1"
  local ci
  ci="$(find_ci_config "$cwd")"
  if [ -z "$ci" ]; then
    echo "対象外[検査を通った成果物だけを公開する]: 継続的な配布の設定ファイルが見当たらないため判定不能"
    return 0
  fi
  if ! grep -qiE 'publish|release' "$ci" 2>/dev/null; then
    echo "対象外[検査を通った成果物だけを公開する]: ${ci} に公開の手順が見当たらないため判定不能"
    return 0
  fi
  if ! grep -qiE 'test' "$ci" 2>/dev/null; then
    echo "拒否[検査を通った成果物だけを公開する]: ${ci} に公開の前段としてのテストの実行が登録されていません"
    return 2
  fi
  echo "許可[検査を通った成果物だけを公開する]: ${ci} にテストの実行が登録されています"
  return 0
}

# 「公開の記録を残す」規則の判定
judge_release_recorded() {
  # $1: cwd, $2: command
  local cwd="$1" cmd="$2"
  if printf '%s' "$cmd" | grep -qE '(^|[^a-zA-Z])git[[:space:]]+tag([^a-zA-Z]|$)'; then
    echo "許可[公開の記録を残す]: git tag 自体が版管理へ残る記録です"
    return 0
  fi
  local tag_count
  tag_count="$(git -C "$cwd" tag --list 2>/dev/null | grep -c . || true)"
  if [ "$tag_count" -gt 0 ]; then
    echo "許可[公開の記録を残す]: 版管理に既存のタグが${tag_count}件あります"
    return 0
  fi
  local ci
  ci="$(find_ci_config "$cwd")"
  if [ -n "$ci" ] && grep -qiE 'release' "$ci" 2>/dev/null; then
    echo "許可[公開の記録を残す]: ${ci} に release の記述があります"
    return 0
  fi
  echo "拒否[公開の記録を残す]: 版管理のタグ、または配布の仕組みに公開の記録が残る設定が見当たりません"
  return 2
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
  [ "$tool" != "Bash" ] && exit 0

  local cmd cwd
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
  [ -z "$cmd" ] && exit 0
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)

  if ! printf '%s' "$cmd" | grep -qE "$RELEASE_CMD_RE"; then
    exit 0
  fi

  local violations="" rc=0 msg code
  for fn_call in \
    "judge_changelog_entry|$cwd|$cmd" \
    "judge_version_format||$cmd" \
    "judge_release_automated|$cwd|" \
    "judge_publish_gated_by_test|$cwd|" \
    "judge_release_recorded|$cwd|$cmd"
  do
    local fn="${fn_call%%|*}"
    case "$fn" in
      judge_changelog_entry) msg="$(judge_changelog_entry "$cwd" "$cmd")"; code=$? ;;
      judge_version_format) msg="$(judge_version_format "$cmd")"; code=$? ;;
      judge_release_automated) msg="$(judge_release_automated "$cwd")"; code=$? ;;
      judge_publish_gated_by_test) msg="$(judge_publish_gated_by_test "$cwd")"; code=$? ;;
      judge_release_recorded) msg="$(judge_release_recorded "$cwd" "$cmd")"; code=$? ;;
    esac
    if [ "$code" -eq 2 ]; then
      violations="${violations}${msg}"$'\n'
      rc=2
    fi
  done

  [ "$rc" -eq 0 ] && exit 0

  ctx="[RELEASE-CHANGELOG-ENTRY-BLOCK] 版付けと公開の決まりの違反があります:"$'\n'"${violations}"
  jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  printf '%s\n' "$ctx" >&2
  exit 2
}

self_test() {
  local rc=0 msg code tmp

  # 系1: 公開操作でないコマンド → 対象外として許可
  if msg="$(judge_changelog_entry "/tmp" "git status")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系1: 公開操作でないコマンドは許可される（${msg}）"
  else
    echo "  [FAIL] 系1: 公開操作でないのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系2: npm publish + CHANGELOG不在 → 拒否
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-release-changelog-entry-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  if msg="$(judge_changelog_entry "$tmp" "npm publish")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系2: CHANGELOG不在は拒否される（${msg}）"
  else
    echo "  [FAIL] 系2: CHANGELOGが無いのに許可された（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系3: npm version + CHANGELOG実在・版の項目あり → 許可
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-release-changelog-entry-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  printf '## [1.2.3] - 2026-01-01\n- 変更内容\n' > "$tmp/CHANGELOG.md"
  if msg="$(judge_changelog_entry "$tmp" "npm version patch")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系3: 版の項目があるCHANGELOGは許可される（${msg}）"
  else
    echo "  [FAIL] 系3: 版の項目があるのに拒否された（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系4: git tag + CHANGELOG実在だが版の項目なし → 拒否
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-release-changelog-entry-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  printf '# 変更履歴\n未整理\n' > "$tmp/CHANGELOG.md"
  if msg="$(judge_changelog_entry "$tmp" "git tag -a v1.0.0 -m release")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系4: 版の項目が無いCHANGELOGは拒否される（${msg}）"
  else
    echo "  [FAIL] 系4: 版の項目が無いのに許可された（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系5: 版番号が semver でない → 拒否（版の付け方）
  if msg="$(judge_version_format "npm version 1.2")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系5: 2桁の版番号は拒否される（${msg}）"
  else
    echo "  [FAIL] 系5: 2桁なのに拒否されなかった（exit=${code}）" >&2
    rc=1
  fi

  # 系6: 版番号が semver 形式 → 許可（版の付け方）
  if msg="$(judge_version_format "npm version 1.2.3")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系6: 3桁の版番号は許可される（${msg}）"
  else
    echo "  [FAIL] 系6: 3桁なのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系7: CI設定が無い → 拒否（公開の手順の自動化）
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-release-changelog-entry-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  if msg="$(judge_release_automated "$tmp")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系7: CI設定が無ければ拒否される（${msg}）"
  else
    echo "  [FAIL] 系7: CI設定が無いのに許可された（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系8: CI設定にpublishの手順がある → 許可（公開の手順の自動化）
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-release-changelog-entry-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  mkdir -p "$tmp/.github/workflows"
  printf 'jobs:\n  release:\n    steps:\n      - run: npm publish\n' > "$tmp/.github/workflows/release.yml"
  if msg="$(judge_release_automated "$tmp")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系8: publishの手順があれば許可される（${msg}）"
  else
    echo "  [FAIL] 系8: publishの手順があるのに拒否された（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系9: CI設定にpublishはあるがtestが無い → 拒否（検査を通った成果物だけを公開）
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-release-changelog-entry-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  mkdir -p "$tmp/.github/workflows"
  printf 'jobs:\n  release:\n    steps:\n      - run: npm publish\n' > "$tmp/.github/workflows/release.yml"
  if msg="$(judge_publish_gated_by_test "$tmp")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系9: テストの記述が無ければ拒否される（${msg}）"
  else
    echo "  [FAIL] 系9: テストが無いのに許可された（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系10: CI設定にpublishとtestの両方がある → 許可（検査を通った成果物だけを公開）
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-release-changelog-entry-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  mkdir -p "$tmp/.github/workflows"
  printf 'jobs:\n  release:\n    steps:\n      - run: npm test\n      - run: npm publish\n' > "$tmp/.github/workflows/release.yml"
  if msg="$(judge_publish_gated_by_test "$tmp")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系10: testとpublishの両方があれば許可される（${msg}）"
  else
    echo "  [FAIL] 系10: 両方あるのに拒否された（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系11: タグもrelease記述も無い → 拒否（公開の記録）
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-release-changelog-entry-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  git -C "$tmp" init -q
  if msg="$(judge_release_recorded "$tmp" "npm publish")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系11: 記録の手掛かりが無ければ拒否される（${msg}）"
  else
    echo "  [FAIL] 系11: 記録の手掛かりが無いのに許可された（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系12: git tag コマンド自体 → 許可（公開の記録）
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-release-changelog-entry-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  git -C "$tmp" init -q
  if msg="$(judge_release_recorded "$tmp" "git tag v1.0.0")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系12: git tagコマンド自体は記録として許可される（${msg}）"
  else
    echo "  [FAIL] 系12: git tagコマンドなのに拒否された（exit=${code}）" >&2
    rc=1
  fi
  rm -rf "$tmp"

  # 系13: 環境変数に理由を設定 → should_skip_with_reasonが戻り値0でタグと理由を返す
  local out13
  if out13="$(RELEASE_CHANGELOG_ENTRY_SKIP_REASON="テスト用の理由" should_skip_with_reason)"; then
    if printf '%s' "$out13" | grep -qF '[RELEASE-CHANGELOG-ENTRY-SKIP]' && printf '%s' "$out13" | grep -qF 'テスト用の理由'; then
      echo "  [PASS] 系13: 理由を設定するとタグと理由付きでskipされる（${out13}）"
    else
      echo "  [FAIL] 系13: skipされたがタグまたは理由が出力に含まれない（${out13}）" >&2
      rc=1
    fi
  else
    echo "  [FAIL] 系13: 理由を設定したのにskipされなかった" >&2
    rc=1
  fi

  # 系14: 環境変数が空文字 → should_skip_with_reasonが戻り値1を返す
  if RELEASE_CHANGELOG_ENTRY_SKIP_REASON="" should_skip_with_reason >/dev/null 2>&1; then
    echo "  [FAIL] 系14: 空文字なのにskipされた" >&2
    rc=1
  else
    echo "  [PASS] 系14: 環境変数が空文字ならskipされない"
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
