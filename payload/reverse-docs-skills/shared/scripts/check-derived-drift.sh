#!/usr/bin/env bash
# check-derived-drift.sh — 生成済み派生物のずれ検知（フィンガープリント台帳との突合）
#
# 目的:
#   生成時に派生物（HTML）のハッシュを台帳へ記録し、以後の手作業編集による
#   「定義と派生物のずれ」をハッシュ突合で検知する。判定に更新時刻は使わない
#   （git checkout や別ツールでも時刻は動くため）。設計判断は
#   .claude/rules/scoped/portal/page-conventions/rule.md の「設計判断」節を参照。
#
# 使い方:
#   check-derived-drift.sh record <root> [--ledger <path>]   # 台帳を記録する
#   check-derived-drift.sh status <root> [--ledger <path>]   # 台帳と突合する
#   check-derived-drift.sh --self-test
#
# 終了コード: status はずれなし 0 / ずれあり 1 / 台帳なし等の前提不足 2
# 対象: <root> 配下の *.html（verification/ 配下を除く）
# 台帳: 既定 <root>/derived-fingerprints.json
set -euo pipefail

usage() {
  echo "usage: $0 record|status <root> [--ledger <path>] | --self-test" >&2
  exit 2
}

hash_file() { shasum -a 256 "$1" | cut -d' ' -f1; }

# root からの相対パスで決定的な順序で列挙する（bash 3.2 互換のため mapfile は使わない）
list_targets() {
  local root="$1"
  ( cd "$root" && find . -type f -name '*.html' ! -path './verification/*' -print \
    | sed 's|^\./||' | LC_ALL=C sort ) || true
}

cmd_record() {
  local root="$1" ledger="$2"
  local tmp
  tmp="$(mktemp)"
  echo '{}' > "$tmp"
  local rel h
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    h="$(hash_file "$root/$rel")"
    jq --arg p "$rel" --arg h "$h" '. + {($p): $h}' "$tmp" > "$tmp.next" && mv "$tmp.next" "$tmp"
  done <<LIST
$(list_targets "$root")
LIST
  jq -n --slurpfile f "$tmp" '{schemaVersion: 1, files: $f[0]}' > "$ledger"
  rm -f "$tmp"
  echo "RECORDED: $(jq '.files | length' "$ledger") 件を台帳へ記録した ($ledger)"
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
$(jq -r '.files | to_entries[] | "\(.key)\t\(.value)"' "$ledger")
LEDGER
  # 追加の検知
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if [ "$(jq --arg p "$rel" '.files | has($p)' "$ledger")" != "true" ]; then
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
  t="$(mktemp -d)"
  # 登録時に値を展開する（EXIT 発火時は関数スコープ外で $t が未定義のため）
  trap "rm -rf '$t'" EXIT
  mkdir -p "$t/root/画面" "$t/root/verification"
  printf '<html>a</html>' > "$t/root/画面/a.html"
  printf '<html>b</html>' > "$t/root/b.html"
  printf '<html>v</html>' > "$t/root/verification/skip.html"
  ledger="$t/root/derived-fingerprints.json"

  "$0" record "$t/root" --ledger "$ledger" >/dev/null
  if [ "$(jq '.files | length' "$ledger")" = "2" ]; then
    pass=$((pass+1)); echo "  PASS: record が verification/ を除く 2 件を記録"
  else
    fail=$((fail+1)); echo "  FAIL: record の件数" >&2
  fi

  rc=0; "$0" status "$t/root" --ledger "$ledger" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    pass=$((pass+1)); echo "  PASS: 変更なしは CLEAN（exit 0）"
  else
    fail=$((fail+1)); echo "  FAIL: CLEAN 判定（exit $rc）" >&2
  fi

  printf '<html>a2</html>' > "$t/root/画面/a.html"
  rm "$t/root/b.html"
  printf '<html>c</html>' > "$t/root/c.html"
  rc=0; out="$("$0" status "$t/root" --ledger "$ledger" 2>/dev/null)" || rc=$?
  if [ "$rc" -eq 1 ]; then
    pass=$((pass+1)); echo "  PASS: ずれありは exit 1"
  else
    fail=$((fail+1)); echo "  FAIL: ずれありの終了コード（exit $rc）" >&2
  fi
  if printf '%s\n' "$out" | grep -q '^MODIFIED: 画面/a.html$'; then
    pass=$((pass+1)); echo "  PASS: 編集を MODIFIED として検知"
  else
    fail=$((fail+1)); echo "  FAIL: MODIFIED 検知" >&2
  fi
  if printf '%s\n' "$out" | grep -q '^DELETED: b.html$'; then
    pass=$((pass+1)); echo "  PASS: 削除を DELETED として検知"
  else
    fail=$((fail+1)); echo "  FAIL: DELETED 検知" >&2
  fi
  if printf '%s\n' "$out" | grep -q '^ADDED: c.html$'; then
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
LEDGER="$ROOT/derived-fingerprints.json"
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
