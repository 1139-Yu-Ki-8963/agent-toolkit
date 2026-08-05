#!/usr/bin/env bash
# check-rule-drift.sh — 規約派生物（rule.md / *.mdc）のずれ検知（フィンガープリント台帳との突合）
#
# 目的:
#   build-derived-rules.sh --apply が丸ごと生成する派生ファイル（.claude/rules/**/rule.md・
#   .cursor/rules/*.mdc）のハッシュを台帳へ記録し、以後の手作業編集による
#   「定義と派生物のずれ」をハッシュ突合で検知する。判定に更新時刻は使わない
#   （git checkout や別ツールでも時刻は動くため）。設計の定義は
#   shared/references/規約定義と派生生成の設計.md の6節。
#
# 対象（丸ごと生成されるファイルだけ）:
#   <root>/.claude/rules/**/rule.md
#   <root>/.cursor/rules/*.mdc
#   AGENTS.md と各ツールのhooks登録ファイルは、既存内容の一部だけを差し替える
#   方式のため対象外（ファイル全体のハッシュでは人の手による他の編集と区別できない）。
#
# 使い方:
#   check-rule-drift.sh record <root> [--ledger <path>]   # 台帳を記録する
#   check-rule-drift.sh status <root> [--ledger <path>]   # 台帳と突合する
#   check-rule-drift.sh --self-test
#
# 台帳の既定パス: <root>/docs/rules-tooling/derived-rule-fingerprints.json
#
# 台帳の形式:
#   {
#     "specVersion": 1,
#     "recordedAt": "<ISO8601>",
#     "entries": [ { "path": "...", "sha256": "..." }, ... ]  // path昇順
#   }
#
# recordedAt は既定で record 実行時刻（UTC）を使う。self-testの決定性検査のため
# 環境変数 RULE_DRIFT_RECORDED_AT で固定値を指定できる。
#
# 終了コード: status はずれなし0 / ずれあり1 / 台帳なし等の前提不足2
#
# 保守責任者: 人手（ユーザー）。台帳の対象パターンを増減する場合は本スクリプトの
#   list_targets と shared/references/規約定義と派生生成の設計.md の6節を同時に更新する。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。
set -euo pipefail

usage() {
  echo "usage: $0 record|status <root> [--ledger <path>] | --self-test" >&2
  exit 2
}

hash_file() { shasum -a 256 "$1" | cut -d' ' -f1; }

# root からの相対パスで、対象2種類（丸ごと生成されるファイルだけ）を
# 決定的な順序（path昇順）で列挙する（bash 3.2互換のためmapfileは使わない）。
list_targets() {
  local root="$1"
  (
    cd "$root" 2>/dev/null || exit 0
    if [ -d ".claude/rules" ]; then
      find ".claude/rules" -type f -name 'rule.md' 2>/dev/null
    fi
    if [ -d ".cursor/rules" ]; then
      find ".cursor/rules" -type f -name '*.mdc' 2>/dev/null
    fi
  ) | LC_ALL=C sort || true
}

cmd_record() {
  local root="$1" ledger="$2"
  local recorded_at
  recorded_at="${RULE_DRIFT_RECORDED_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

  local entries_json="[]"
  local rel h
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    h="$(hash_file "$root/$rel")"
    entries_json="$(jq -c --arg p "$rel" --arg h "$h" '. + [{path: $p, sha256: $h}]' <<<"$entries_json")"
  done <<LIST
$(list_targets "$root")
LIST

  mkdir -p "$(dirname "$ledger")"
  jq -n --argjson v 1 --arg ts "$recorded_at" --argjson entries "$entries_json" \
    '{specVersion: $v, recordedAt: $ts, entries: $entries}' > "$ledger"
  echo "RECORDED: $(jq '.entries | length' "$ledger") 件を台帳へ記録した ($ledger)"
}

cmd_status() {
  local root="$1" ledger="$2"
  if [ ! -f "$ledger" ]; then
    echo "NO-LEDGER: 台帳が存在しない ($ledger)。record を先に実行する" >&2
    return 2
  fi
  local drift=0 rel expected actual
  # 変更と削除の検知
  while IFS=$'\t' read -r rel expected; do
    [ -n "$rel" ] || continue
    if [ ! -f "$root/$rel" ]; then
      echo "DELETED: $rel"
      drift=1
      continue
    fi
    actual="$(hash_file "$root/$rel")"
    if [ "$actual" != "$expected" ]; then
      echo "MODIFIED: $rel"
      drift=1
    fi
  done <<LEDGER
$(jq -r '.entries[] | "\(.path)\t\(.sha256)"' "$ledger")
LEDGER
  # 追加の検知
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if [ "$(jq --arg p "$rel" '.entries | map(.path == $p) | any' "$ledger")" != "true" ]; then
      echo "ADDED: $rel"
      drift=1
    fi
  done <<LIST
$(list_targets "$root")
LIST
  if [ "$drift" -eq 0 ]; then
    echo "CLEAN: 台帳と一致（ずれなし）"
    return 0
  fi
  echo "DRIFT: 生成物に台帳と不一致の変更がある。定義を直して再生成するか、意図した変更なら record で台帳を更新する" >&2
  return 1
}

self_test() {
  local t pass=0 fail=0 rc out ledger
  t="$(mktemp -d "${TMPDIR:-/tmp}/check-rule-drift-self-test.XXXXXX")"
  trap "rm -rf '$t'" EXIT
  mkdir -p "$t/root/.claude/rules/always/foo"
  mkdir -p "$t/root/.claude/rules/scoped/bar"
  mkdir -p "$t/root/.cursor/rules"
  printf 'a content' > "$t/root/.claude/rules/always/foo/rule.md"
  printf 'b content' > "$t/root/.claude/rules/scoped/bar/rule.md"
  printf 'c content' > "$t/root/.cursor/rules/foo-bar.mdc"
  printf '# AGENTS' > "$t/root/AGENTS.md"
  ledger="$t/root/docs/rules-tooling/derived-rule-fingerprints.json"

  export RULE_DRIFT_RECORDED_AT="2020-01-01T00:00:00Z"

  "$0" record "$t/root" --ledger "$ledger" >/dev/null
  if [ "$(jq '.entries | length' "$ledger")" = "3" ]; then
    pass=$((pass+1)); echo "  PASS: record が対象2種類の3件を記録"
  else
    fail=$((fail+1)); echo "  FAIL: record の件数" >&2
  fi

  local paths sorted_paths
  paths="$(jq -r '.entries[].path' "$ledger")"
  sorted_paths="$(printf '%s\n' "$paths" | LC_ALL=C sort)"
  if [ "$paths" = "$sorted_paths" ]; then
    pass=$((pass+1)); echo "  PASS: entries が path 昇順"
  else
    fail=$((fail+1)); echo "  FAIL: entries の並び順" >&2
  fi

  local ledger2="$t/root/docs/rules-tooling/derived-rule-fingerprints2.json"
  "$0" record "$t/root" --ledger "$ledger2" >/dev/null
  if diff -q "$ledger" "$ledger2" >/dev/null 2>&1; then
    pass=$((pass+1)); echo "  PASS: 同じ入力で2回recordした結果がbyte一致"
  else
    fail=$((fail+1)); echo "  FAIL: record の決定性" >&2
  fi
  rm -f "$ledger2"

  rc=0; "$0" status "$t/root" --ledger "$ledger" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    pass=$((pass+1)); echo "  PASS: ずれなしは exit 0"
  else
    fail=$((fail+1)); echo "  FAIL: CLEAN 判定（exit $rc）" >&2
  fi

  printf 'a content changed' > "$t/root/.claude/rules/always/foo/rule.md"
  rm "$t/root/.claude/rules/scoped/bar/rule.md"
  mkdir -p "$t/root/.claude/rules/always/newone"
  printf 'new' > "$t/root/.claude/rules/always/newone/rule.md"
  rc=0; out="$("$0" status "$t/root" --ledger "$ledger" 2>/dev/null)" || rc=$?
  if [ "$rc" -eq 1 ]; then
    pass=$((pass+1)); echo "  PASS: ずれありは exit 1"
  else
    fail=$((fail+1)); echo "  FAIL: ずれありの終了コード（exit $rc）" >&2
  fi
  if printf '%s\n' "$out" | grep -q '^MODIFIED: \.claude/rules/always/foo/rule\.md$'; then
    pass=$((pass+1)); echo "  PASS: 編集を MODIFIED として検知"
  else
    fail=$((fail+1)); echo "  FAIL: MODIFIED 検知" >&2
  fi
  if printf '%s\n' "$out" | grep -q '^DELETED: \.claude/rules/scoped/bar/rule\.md$'; then
    pass=$((pass+1)); echo "  PASS: 削除を DELETED として検知"
  else
    fail=$((fail+1)); echo "  FAIL: DELETED 検知" >&2
  fi
  if printf '%s\n' "$out" | grep -q '^ADDED: \.claude/rules/always/newone/rule\.md$'; then
    pass=$((pass+1)); echo "  PASS: 追加を ADDED として検知"
  else
    fail=$((fail+1)); echo "  FAIL: ADDED 検知" >&2
  fi

  "$0" record "$t/root" --ledger "$ledger" >/dev/null
  rc=0; "$0" status "$t/root" --ledger "$ledger" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    pass=$((pass+1)); echo "  PASS: record のやり直しで CLEAN に戻る"
  else
    fail=$((fail+1)); echo "  FAIL: 再 record 後の CLEAN（exit $rc）" >&2
  fi

  printf '# AGENTS changed' > "$t/root/AGENTS.md"
  rc=0; out="$("$0" status "$t/root" --ledger "$ledger" 2>/dev/null)" || rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" -o "$out" = "CLEAN: 台帳と一致（ずれなし）" ]; then
    pass=$((pass+1)); echo "  PASS: AGENTS.md の書き換えは検知対象外（対象外の確認）"
  else
    fail=$((fail+1)); echo "  FAIL: AGENTS.md が誤って検知対象になっている（exit $rc, out=$out）" >&2
  fi

  rc=0; "$0" status "$t/root" --ledger "$t/root/missing.json" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 2 ]; then
    pass=$((pass+1)); echo "  PASS: 台帳なしは exit 2"
  else
    fail=$((fail+1)); echo "  FAIL: 台帳なしの終了コード（exit $rc）" >&2
  fi

  echo "self-test: PASS=$pass FAIL=$fail"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
  --self-test) self_test; exit $? ;;
  record|status) MODE="$1"; shift ;;
  *) usage ;;
esac

ROOT="${1:-}"
[ -n "$ROOT" ] && [ -d "$ROOT" ] || { echo "ERROR: root が存在しない: ${ROOT:-（未指定）}" >&2; exit 2; }
shift
LEDGER="$ROOT/docs/rules-tooling/derived-rule-fingerprints.json"
while [ $# -gt 0 ]; do
  case "$1" in
    --ledger) LEDGER="${2:?--ledger に値が必要}"; shift 2 ;;
    *) usage ;;
  esac
done

case "$MODE" in
  record) cmd_record "$ROOT" "$LEDGER" ;;
  status) cmd_status "$ROOT" "$LEDGER" ;;
esac
