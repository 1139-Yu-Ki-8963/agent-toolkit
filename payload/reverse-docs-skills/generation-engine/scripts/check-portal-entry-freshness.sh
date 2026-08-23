#!/usr/bin/env bash
# 入口のページがコードの現在地に追随しているかを通知する。
# 通常の鮮度判定は合否で開発を止めず、FRESH / STALE / SKIP を出して終了コード0を返す。
# 実行環境や宣言の不備で判定できない場合だけ UNKNOWN を出して終了コード2を返す。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_DECLARATION="$SCRIPT_DIR/../../delivery-payload/references/portal-entry-dependencies.json"

unknown() {
  echo "[UNKNOWN] $*" >&2
  return 2
}

find_display_commit() {
  local output_root="$1" declaration="$2" rel candidate commit portal_rel portal_file

  while IFS= read -r rel; do
    candidate="$output_root/$rel"
    [ -f "$candidate" ] || continue
    commit="$(jq -r '.commit // empty' "$candidate" 2>/dev/null)" || return 2
    if printf '%s' "$commit" | grep -qE '^[0-9a-fA-F]{7,40}$'; then
      printf '%s\n' "$commit"
      return 0
    fi
  done < <(jq -r '.displayCommitSources[]' "$declaration")

  while IFS= read -r portal_rel; do
    portal_file="$output_root/$portal_rel"
    [ -f "$portal_file" ] || continue
    commit="$(grep -Eo 'コミット(番号)?:? ?[0-9a-fA-F]{7,40}' "$portal_file" | head -1 | grep -Eo '[0-9a-fA-F]{7,40}' || true)"
    if [ -n "$commit" ]; then
      printf '%s\n' "$commit"
      return 0
    fi
  done < <(jq -r '.portalPaths[]' "$declaration")

  return 1
}

portal_exists() {
  local output_root="$1" declaration="$2" rel
  while IFS= read -r rel; do
    [ -f "$output_root/$rel" ] && return 0
  done < <(jq -r '.portalPaths[]' "$declaration")
  return 1
}

artifact_is_affected() {
  local declaration="$1" index="$2" changed_file="$3" prefix
  while IFS= read -r prefix; do
    case "$changed_file" in
      "$prefix"*) return 0 ;;
    esac
  done < <(jq -r ".artifacts[$index].inputPrefixes[]" "$declaration")
  return 1
}

detect_freshness() {
  local target_repo="$1" output_root="$2" declaration="$3" affected_file="$4"
  local display_commit head resolved_commit changed_file artifact_count index artifact_id artifact_name matched

  if ! portal_exists "$output_root" "$declaration"; then
    echo "[SKIP] 入口のページが無いため鮮度判定の対象外です"
    return 0
  fi

  if ! git -C "$target_repo" rev-parse --git-dir >/dev/null 2>&1; then
    unknown "対象がgitリポジトリではないため判定できません: $target_repo"
    return $?
  fi

  if display_commit="$(find_display_commit "$output_root" "$declaration")"; then
    :
  else
    echo "[STALE] 入口のページに比較できる表示コミットが無いため作り直しが必要です"
    jq -r '.artifacts[].id' "$declaration" > "$affected_file"
    return 0
  fi

  head="$(git -C "$target_repo" rev-parse HEAD)" || {
    unknown "HEADを取得できないため判定できません: $target_repo"
    return $?
  }
  if ! resolved_commit="$(git -C "$target_repo" rev-parse --verify "${display_commit}^{commit}" 2>/dev/null)"; then
    echo "[STALE] 表示コミット $display_commit が現在の履歴に無いため作り直しが必要です"
    jq -r '.artifacts[].id' "$declaration" > "$affected_file"
    return 0
  fi
  if [ "$resolved_commit" = "$head" ]; then
    echo "[FRESH] 入口のページの表示コミットはHEADと一致しています"
    return 0
  fi

  artifact_count="$(jq '.artifacts | length' "$declaration")"
  : > "$affected_file"
  while IFS= read -r changed_file; do
    index=0
    while [ "$index" -lt "$artifact_count" ]; do
      if artifact_is_affected "$declaration" "$index" "$changed_file"; then
        artifact_id="$(jq -r ".artifacts[$index].id" "$declaration")"
        if ! grep -qxF "$artifact_id" "$affected_file"; then
          printf '%s\n' "$artifact_id" >> "$affected_file"
        fi
      fi
      index=$((index + 1))
    done
  done < <(git -C "$target_repo" diff --name-only "$resolved_commit..$head")

  if [ ! -s "$affected_file" ]; then
    echo "[FRESH] 表示コミット以降に入口のページへ影響する変更はありません"
    return 0
  fi

  echo "[STALE] 表示コミット以降に入口のページへ影響する変更があります"
  while IFS= read -r artifact_id; do
    artifact_name="$(jq -r --arg id "$artifact_id" '.artifacts[] | select(.id == $id) | .artifact' "$declaration")"
    echo "  - $artifact_id: $artifact_name"
  done < "$affected_file"
  return 0
}

regenerate_affected() {
  local target_repo="$1" output_root="$2" declaration="$3" affected_file="$4"
  local artifact_id command required_input missing
  [ -s "$affected_file" ] || return 0
  while IFS= read -r artifact_id; do
    missing=0
    while IFS= read -r required_input; do
      if [ ! -e "$output_root/$required_input" ]; then
        echo "[REBUILD-SKIP] $artifact_id の入力が無いため対象外です: $required_input"
        missing=1
      fi
    done < <(jq -r --arg id "$artifact_id" '.artifacts[] | select(.id == $id) | .requiredInputs[]' "$declaration")
    [ "$missing" -eq 0 ] || continue
    command="$(jq -r --arg id "$artifact_id" '.artifacts[] | select(.id == $id) | .rebuildCommand' "$declaration")"
    echo "[REBUILD] $artifact_id"
    TARGET_REPO="$target_repo" OUTPUT_ROOT="$output_root" REVERSE_DOCS_ENGINE="${REVERSE_DOCS_ENGINE:-$(cd "$SCRIPT_DIR/../.." && pwd)}" sh -c "$command" || return $?
  done < "$affected_file"
}

self_test() {
  local tmp repo output declaration base affected rc
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-portal-entry-freshness.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    unknown "self-test用mktempが一時領域へ書き込めないため判定できません"
    return $?
  fi
  repo="$tmp/repo"
  output="$tmp/output"
  declaration="$DEFAULT_DECLARATION"
  affected="$tmp/affected"
  mkdir -p "$repo/src" "$output/project-portal"
  git -C "$repo" init -q
  git -C "$repo" config user.name self-test
  git -C "$repo" config user.email self-test@example.invalid
  echo 'const value = 1;' > "$repo/src/main.js"
  git -C "$repo" add src/main.js
  git -C "$repo" commit -qm base
  base="$(git -C "$repo" rev-parse HEAD)"
  printf '<div class="pm-hero-commit">コミット番号: %s</div>\n' "${base%?????????????????????????????????}" > "$output/project-portal/index.html"

  rc=0
  if detect_freshness "$repo" "$output" "$declaration" "$affected" | grep -q '^\[FRESH\]'; then
    echo "  [PASS] 表示コミットとHEADが同じならFRESH"
  else
    echo "  [FAIL] 表示コミットとHEADが同じ場合の判定" >&2
    rc=1
  fi

  mkdir -p "$repo/docs"
  echo '文書だけの変更' > "$repo/docs/note.md"
  git -C "$repo" add docs/note.md
  git -C "$repo" commit -qm docs-only
  if detect_freshness "$repo" "$output" "$declaration" "$affected" | grep -q '^\[FRESH\]'; then
    echo "  [PASS] 文書だけの変更はFRESH"
  else
    echo "  [FAIL] 文書だけの変更の判定" >&2
    rc=1
  fi

  echo 'const value = 2;' > "$repo/src/main.js"
  git -C "$repo" add src/main.js
  git -C "$repo" commit -qm source-change
  if detect_freshness "$repo" "$output" "$declaration" "$affected" | grep '^\[STALE\]' >/dev/null; then
    echo "  [PASS] 実装の変更はSTALE"
  else
    echo "  [FAIL] 実装の変更の判定" >&2
    rc=1
  fi

  rm -f "$output/project-portal/index.html"
  if detect_freshness "$repo" "$output" "$declaration" "$affected" | grep -q '^\[SKIP\]'; then
    echo "  [PASS] 入口のページが無い場合はSKIP"
  else
    echo "  [FAIL] 入口のページが無い場合の判定" >&2
    rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  fi
  rm -rf "$tmp"
  return "$rc"
}

main() {
  local mode="check" target_repo output_root declaration affected_file status
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    return $?
  fi
  if [ "${1:-}" = "--regenerate" ]; then
    mode="regenerate"
    shift
  fi
  if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Usage: $0 [--regenerate] <target_repo> <output_root> [dependency_file]" >&2
    return 2
  fi
  target_repo="$1"
  output_root="$2"
  declaration="${3:-$DEFAULT_DECLARATION}"
  if ! jq -e '.schemaVersion == 1 and (.portalPaths | length > 0) and (.artifacts | length >= 5) and all(.artifacts[]; (.id | length > 0) and (.inputPrefixes | length > 0) and (.requiredInputs | type == "array") and (.rebuildCommand | length > 0))' "$declaration" >/dev/null 2>&1; then
    unknown "依存関係の宣言が不正なため判定できません: $declaration"
    return $?
  fi
  if ! affected_file="$(mktemp "${TMPDIR:-/tmp}/portal-entry-affected.XXXXXX" 2>/dev/null)" || [ -z "$affected_file" ]; then
    unknown "mktempが一時領域へ書き込めないため判定できません"
    return $?
  fi
  trap "$(printf 'rm -f -- %q' "$affected_file")" EXIT
  detect_freshness "$target_repo" "$output_root" "$declaration" "$affected_file"
  status=$?
  [ "$status" -eq 0 ] || return "$status"
  if [ "$mode" = "regenerate" ]; then
    regenerate_affected "$target_repo" "$output_root" "$declaration" "$affected_file"
  fi
}

main "$@"
