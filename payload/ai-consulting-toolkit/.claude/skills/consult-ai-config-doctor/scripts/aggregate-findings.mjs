#!/usr/bin/env node
// aggregate-findings.mjs
//
// 入力ディレクトリ内の *.json（各ドメイン診断エージェントの findings JSON）を読み、
// グレード・星・処方箋・（任意で）前回比較 diff を含む集計 JSON を書き出す。
// Node.js 標準ライブラリのみで動作する（npm 依存なし）。
//
// Usage:
//   node aggregate-findings.mjs <入力ディレクトリ> <出力json> [--project <名>] [--root <パス>] [--prev <前回集計json>]
//
// 入力ディレクトリ内の各 *.json は次のスキーマを想定する（崩れていても normalize する）:
//   {
//     "domain": "claude-md|rules|skills|hooks|subagents|hygiene",
//     "present": true,
//     "coverage": 0.85,
//     "findings": [
//       {
//         "key": "意味語キー",
//         "severity": "CRITICAL|WARN|INFO",
//         "detail": "検証済み事実",
//         "evidence": "確認コマンドと出力抜粋",
//         "recommendation": "提案",
//         "fix": {"risk": "safe|careful|surgery", "time_min": 15, "expected": "C→B", "prompt": "適用プロンプト"}
//       }
//     ]
//   }
//
// 出力 JSON は仕様書のスキーマに加え、各 domain エントリに正規化済みの `findings`
// 配列も保持する（render-dashboard.mjs の「指摘一覧」セクション描画に必要なため）。

import fs from 'node:fs';
import path from 'node:path';

const SEVERITIES = new Set(['CRITICAL', 'WARN', 'INFO']);
const RISKS = new Set(['safe', 'careful', 'surgery']);
const DOMAIN_IDS = ['claude-md', 'rules', 'skills', 'hooks', 'subagents', 'hygiene'];
const DOMAIN_LABELS = {
  'claude-md': 'CLAUDE.md・設定層配置',
  rules: 'Rules',
  skills: 'Skills',
  hooks: 'Hooks',
  subagents: 'Subagents',
  hygiene: '自動化・運用衛生',
};
const GRADE_VALUE = { S: 5, A: 4, B: 3, C: 2, D: 1 };
const VALUE_GRADE = { 5: 'S', 4: 'A', 3: 'B', 2: 'C', 1: 'D' };
const LEVEL_LABEL = {
  5: '完全自動',
  4: '例外のみ人介入',
  3: '人が承認するAI実行',
  2: 'AI補助',
  1: '人手のみ',
};

function parseArgs(argv) {
  const positional = [];
  const opts = { project: '', root: '', prev: '' };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--project') {
      opts.project = argv[++i] ?? '';
    } else if (a === '--root') {
      opts.root = argv[++i] ?? '';
    } else if (a === '--prev') {
      opts.prev = argv[++i] ?? '';
    } else {
      positional.push(a);
    }
  }
  return { positional, opts };
}

function toNumber(value, fallback) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim() !== '') {
    const n = Number(value);
    if (Number.isFinite(n)) return n;
  }
  return fallback;
}

function toBoolean(value, fallback) {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') {
    const lower = value.trim().toLowerCase();
    if (lower === 'true') return true;
    if (lower === 'false') return false;
  }
  return fallback;
}

function normalizeFinding(raw, index) {
  const f = raw && typeof raw === 'object' ? raw : {};
  const severity =
    typeof f.severity === 'string' && SEVERITIES.has(f.severity.toUpperCase())
      ? f.severity.toUpperCase()
      : 'WARN';
  const key = typeof f.key === 'string' && f.key.trim() !== '' ? f.key : `finding-${index + 1}`;

  const normalized = {
    key,
    severity,
    detail: typeof f.detail === 'string' ? f.detail : '',
    evidence: typeof f.evidence === 'string' ? f.evidence : '',
    recommendation: typeof f.recommendation === 'string' ? f.recommendation : '',
  };

  if (f.fix && typeof f.fix === 'object') {
    const risk = typeof f.fix.risk === 'string' && RISKS.has(f.fix.risk) ? f.fix.risk : 'careful';
    normalized.fix = {
      risk,
      time_min: toNumber(f.fix.time_min, 15),
      expected: typeof f.fix.expected === 'string' ? f.fix.expected : '',
      prompt: typeof f.fix.prompt === 'string' ? f.fix.prompt : '',
    };
  }

  return normalized;
}

function normalizeDomainFile(raw, fallbackId) {
  const d = raw && typeof raw === 'object' ? raw : {};
  const domainId =
    typeof d.domain === 'string' && DOMAIN_IDS.includes(d.domain) ? d.domain : fallbackId;
  const present = toBoolean(d.present, true);

  let coverage = toNumber(d.coverage, 0);
  if (!Number.isFinite(coverage)) coverage = 0;
  if (coverage < 0) coverage = 0;
  if (coverage > 1) coverage = 1;

  const rawFindings = Array.isArray(d.findings) ? d.findings : [];
  const findings = rawFindings.map((f, i) => normalizeFinding(f, i));

  return { domain: domainId, present, coverage, findings };
}

function gradeDomain(normalized) {
  const critical = normalized.findings.filter((f) => f.severity === 'CRITICAL').length;
  const warn = normalized.findings.filter((f) => f.severity === 'WARN').length;
  const info = normalized.findings.filter((f) => f.severity === 'INFO').length;

  let grade;
  if (!normalized.present) {
    grade = 'D';
  } else if (critical >= 1) {
    grade = 'C';
  } else if (critical === 0 && warn === 0 && normalized.coverage >= 0.9) {
    grade = 'S';
  } else if (critical === 0 && warn <= 3) {
    grade = 'A';
  } else {
    grade = 'B';
  }

  const sevOrder = { CRITICAL: 0, WARN: 1, INFO: 2 };
  const sorted = [...normalized.findings].sort((a, b) => sevOrder[a.severity] - sevOrder[b.severity]);
  const topFinding = sorted.length > 0 ? sorted[0].detail : '';

  return {
    id: normalized.domain,
    label: DOMAIN_LABELS[normalized.domain] || normalized.domain,
    grade,
    stars: GRADE_VALUE[grade],
    critical,
    warn,
    info,
    coverage: normalized.coverage,
    top_finding: topFinding,
    findings: normalized.findings,
  };
}

function computeOverall(domains) {
  if (domains.length === 0) {
    return { grade: 'D', stars: 1, ai_level: 1, ai_level_label: LEVEL_LABEL[1] };
  }
  const values = domains.map((d) => GRADE_VALUE[d.grade]);
  const minValue = Math.min(...values);
  const others = values.filter((v) => v !== minValue);
  const avgOther = others.length > 0 ? others.reduce((a, b) => a + b, 0) / others.length : minValue;

  let overallValue = minValue;
  if (avgOther - minValue >= 2) {
    overallValue = Math.min(minValue + 1, 5);
  }

  return {
    grade: VALUE_GRADE[overallValue],
    stars: overallValue,
    ai_level: overallValue,
    ai_level_label: LEVEL_LABEL[overallValue],
  };
}

function parseExpectedDelta(expected) {
  if (typeof expected !== 'string') return 0;
  const m = expected.match(/([SABCD])\s*(?:→|->)\s*([SABCD])/);
  if (!m) return 0;
  const from = GRADE_VALUE[m[1]];
  const to = GRADE_VALUE[m[2]];
  if (from === undefined || to === undefined) return 0;
  return to - from;
}

function buildPrescriptions(domains) {
  const riskOrder = { safe: 0, careful: 1, surgery: 2 };
  const list = [];
  for (const domain of domains) {
    for (const finding of domain.findings) {
      if (!finding.fix) continue;
      list.push({
        key: finding.key,
        domain: domain.id,
        risk: finding.fix.risk,
        time_min: finding.fix.time_min,
        expected: finding.fix.expected,
        prompt: finding.fix.prompt,
      });
    }
  }
  list.sort((a, b) => {
    const riskDiff = riskOrder[a.risk] - riskOrder[b.risk];
    if (riskDiff !== 0) return riskDiff;
    return parseExpectedDelta(b.expected) - parseExpectedDelta(a.expected);
  });
  return list;
}

function computeDiff(prevData, currentDomains, currentOverall) {
  if (!prevData || typeof prevData !== 'object') return undefined;
  const prevDomains = Array.isArray(prevData.domains) ? prevData.domains : [];
  const prevMap = new Map(prevDomains.map((d) => [d.id, d.grade]));

  const changes = [];
  for (const d of currentDomains) {
    const prevGrade = prevMap.get(d.id);
    if (prevGrade && prevGrade !== d.grade) {
      changes.push({ domain: d.id, from: prevGrade, to: d.grade });
    }
  }

  const prevOverallGrade =
    prevData.overall && typeof prevData.overall.grade === 'string' ? prevData.overall.grade : '';

  return {
    prev_date: prevData.meta && typeof prevData.meta.date === 'string' ? prevData.meta.date : '',
    changes,
    overall_from: prevOverallGrade,
    overall_to: currentOverall.grade,
  };
}

function main() {
  const argv = process.argv.slice(2);
  const { positional, opts } = parseArgs(argv);
  if (positional.length < 2) {
    console.error(
      'Usage: aggregate-findings.mjs <入力ディレクトリ> <出力json> [--project <名>] [--root <パス>] [--prev <前回集計json>]'
    );
    process.exit(1);
  }
  const [inputDir, outputPath] = positional;

  let files;
  try {
    files = fs.readdirSync(inputDir).filter((f) => f.toLowerCase().endsWith('.json'));
  } catch (err) {
    console.error(`入力ディレクトリを読めません: ${inputDir} (${err.message})`);
    process.exit(1);
  }

  const domains = [];
  for (const file of files) {
    const fullPath = path.join(inputDir, file);
    let raw;
    try {
      raw = JSON.parse(fs.readFileSync(fullPath, 'utf8'));
    } catch (err) {
      console.error(`JSON解析に失敗（スキップ）: ${fullPath} (${err.message})`);
      continue;
    }
    const fallbackId = path.basename(file, path.extname(file));
    const normalized = normalizeDomainFile(raw, fallbackId);
    domains.push(gradeDomain(normalized));
  }

  const overall = computeOverall(domains);
  const prescriptions = buildPrescriptions(domains);

  let prevData;
  if (opts.prev) {
    try {
      prevData = JSON.parse(fs.readFileSync(opts.prev, 'utf8'));
    } catch (err) {
      console.error(`--prev の読み込みに失敗（diff なしで続行）: ${opts.prev} (${err.message})`);
    }
  }
  const diff = computeDiff(prevData, domains, overall);

  const output = {
    meta: {
      project: opts.project || '',
      date: new Date().toISOString().slice(0, 10),
      target_root: opts.root || '',
    },
    domains,
    overall,
    prescriptions,
  };
  if (diff) output.diff = diff;

  const resolvedOutput = path.resolve(outputPath);
  fs.mkdirSync(path.dirname(resolvedOutput), { recursive: true });
  fs.writeFileSync(resolvedOutput, JSON.stringify(output, null, 2), 'utf8');
  console.log(`集計結果を書き出しました: ${resolvedOutput}`);
}

main();
