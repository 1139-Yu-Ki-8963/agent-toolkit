#!/usr/bin/env bash
# portal/data.js の整合性を検証する。
# 検査は4系統: ①構文 ②必須フィールド ③状態値(enum) ④参照整合
# 使い方: verify-portal-data.sh [data.jsのパス]（省略時はこのスクリプトから見た portal/data.js を解決）
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_DATA_PATH="$(cd "$SCRIPT_DIR/../../../.." && pwd)/portal/data.js"
DATA_PATH="${1:-$DEFAULT_DATA_PATH}"

if [ ! -f "$DATA_PATH" ]; then
  echo "FAIL: data.js が見つかりません: $DATA_PATH" >&2
  exit 1
fi

TMP_VALIDATOR="${TMPDIR:-/tmp}/verify-portal-data-$$.cjs"
trap 'rm -f "$TMP_VALIDATOR"' EXIT

cat > "$TMP_VALIDATOR" <<'NODE_EOF'
'use strict';
const path = require('path');
const dataPath = process.env.PORTAL_DATA_PATH;

// window オブジェクトをスタブして data.js を評価する
global.window = {};
require(path.resolve(dataPath));
const DATA = global.window.PORTAL_DATA;

let failed = false;
const results = [];
function report(name, ok, detail) {
  results.push({ name, ok, detail });
  if (!ok) failed = true;
}

// 検査1: 構文（require がエラーなく完了し PORTAL_DATA が定義されていること）
report('構文', !!DATA, DATA ? 'PORTAL_DATA を正常に読み込み' : 'PORTAL_DATA が定義されていない');

if (DATA) {
  // 検査2: 必須フィールド（各エンティティの必須キーが全行に存在）
  const REQUIRED = {
    projects: ['key', 'ini', 'name', 'sub', 'issues', 'alerts'],
    issues: ['id', 'name', 'title', 'prio', 'goal', 'crit', 'deliv', 'ms', 'tasks', 'notes', 'rels', 'aiLabel'],
    docs: ['group', 'name', 'ext', 'date', 'from', 'relIssue', 'status', 'ai'],
    people: ['group', 'ini', 'name', 'role', 'stance', 'isKey', 'note', 'links', 'lastContact', 'color', 'org'],
    meetings: ['group', 'title', 'type', 'attendees', 'summary', 'aiImpact', 'ingested'],
    decisions: ['id', 'text', 'date', 'venue', 'agreedBy', 'relIssueKey', 'relLabel', 'group'],
    access: ['member', 'ini', 'role', 'items'],
  };
  let fieldMissing = 0;
  const fieldDetails = [];
  for (const [entity, keys] of Object.entries(REQUIRED)) {
    const rows = DATA[entity] || [];
    rows.forEach((row, i) => {
      keys.forEach((k) => {
        if (!(k in row)) {
          fieldMissing++;
          fieldDetails.push(`${entity}[${i}].${k}`);
        }
      });
    });
  }
  report(
    '必須フィールド',
    fieldMissing === 0,
    fieldMissing === 0
      ? `${Object.keys(REQUIRED).length}エンティティ・全行OK`
      : `不足 ${fieldMissing}件: ${fieldDetails.slice(0, 10).join(', ')}`
  );

  // 検査3: 状態値（プロトタイプに出現する実値から定義した enum）
  const ENUMS = [
    ['issues', 'prio', ['高', '中', '低']],
    ['docs', 'status', ['未確認', '確認済', '差戻し']],
    ['docs', 'ai', ['解読済', '解読中', '旧版', '取込待ち']],
    ['people', 'stance', ['協力的', '多忙', '慎重', '中立', '当社']],
    ['people', 'org', ['cl', 'us']],
    ['meetings', 'type', ['r', 'i', 'e']],
  ];
  let enumViolations = 0;
  const enumDetails = [];
  for (const [entity, field, allowed] of ENUMS) {
    const rows = DATA[entity] || [];
    rows.forEach((row, i) => {
      if (!allowed.includes(row[field])) {
        enumViolations++;
        enumDetails.push(`${entity}[${i}].${field}=${JSON.stringify(row[field])}`);
      }
    });
  }
  const ACCESS_STATUS = ['d', 'p', 'a', 'n', 'x'];
  (DATA.access || []).forEach((row, i) => {
    Object.entries(row.items || {}).forEach(([label, v]) => {
      if (!ACCESS_STATUS.includes(v.status)) {
        enumViolations++;
        enumDetails.push(`access[${i}].items[${label}].status=${JSON.stringify(v.status)}`);
      }
    });
  });
  report(
    '状態値',
    enumViolations === 0,
    enumViolations === 0
      ? `${ENUMS.length + 1}系統 全値OK`
      : `違反 ${enumViolations}件: ${enumDetails.slice(0, 10).join(', ')}`
  );

  // 検査4: 参照整合（doc.relIssue・decision.relIssueKey・issue.rels が指すキーの実在）
  const issueIds = new Set((DATA.issues || []).map((i) => i.id));
  const docNames = new Set((DATA.docs || []).map((d) => d.name));
  const personNames = new Set((DATA.people || []).map((p) => p.name));
  const decisionIds = new Set((DATA.decisions || []).map((d) => d.id));
  const meetingTitles = new Set((DATA.meetings || []).map((m) => m.title));

  let refViolations = 0;
  const refDetails = [];

  (DATA.docs || []).forEach((d, i) => {
    if (d.relIssue !== null && d.relIssue !== undefined && !issueIds.has(d.relIssue)) {
      refViolations++;
      refDetails.push(`docs[${i}].relIssue=${d.relIssue}`);
    }
  });

  (DATA.decisions || []).forEach((d, i) => {
    if (d.relIssueKey !== null && d.relIssueKey !== undefined && !issueIds.has(d.relIssueKey)) {
      refViolations++;
      refDetails.push(`decisions[${i}].relIssueKey=${d.relIssueKey}`);
    }
  });

  (DATA.issues || []).forEach((issue, i) => {
    (issue.rels || []).forEach((r, j) => {
      const [kind, key] = r;
      let exists = true;
      if (kind === 'doc') exists = docNames.has(key);
      else if (kind === 'ppl') exists = personNames.has(key);
      else if (kind === 'dec') exists = decisionIds.has(key);
      else if (kind === 'mtg') exists = meetingTitles.has(key);
      if (!exists) {
        refViolations++;
        refDetails.push(`issues[${i}].rels[${j}]=${kind}:${key}`);
      }
    });
  });

  report(
    '参照整合',
    refViolations === 0,
    refViolations === 0 ? '全参照が実在' : `不整合 ${refViolations}件: ${refDetails.slice(0, 10).join(', ')}`
  );
}

for (const r of results) {
  console.log(`[${r.ok ? 'PASS' : 'FAIL'}] ${r.name}: ${r.detail}`);
}

process.exit(failed ? 1 : 0);
NODE_EOF

PORTAL_DATA_PATH="$DATA_PATH" node "$TMP_VALIDATOR"
