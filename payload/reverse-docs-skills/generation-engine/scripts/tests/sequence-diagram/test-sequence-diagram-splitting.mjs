// 改善課題 1-157: generating-sequence-diagram-for-reverse-docs の局面分割規則
// （operations[] への組み立てと分割）を純粋関数として符号化し、SKILL.md の3段の
// 優先順ルール（1: 機能単位 / 2: コメント境界 / 3: 機械的な15ステップ区切り）のうち、
// 2と3の併用・呼び出し0件ブロックの扱い・分断禁止の並びの扱いを検証する。
//
// 本ファイルは generation-engine/scripts/sequence-diagram/ 配下の既存パターン
// （test-sequence-diagram-lanes.mjs + fixtures/*.json、standalone node runner）を踏襲する。
// call_order → operations[] の実変換は Step 1-2 の narrative（AI エージェントの手作業）
// であり、このスクリプトはその分割規則そのものを再実装した検証専用ロジックである。

const LIMIT = 15;
const failures = [];
let checks = 0;

function fail(subject, message) {
  failures.push(`${subject}: ${message}`);
}

/**
 * splitBlock — 1つのコメント境界ブロック（rule 2 適用後の単位）を、必要なら
 * rule 3（機械的な15ステップ区切り）で追加分割する。
 *
 * @param {Array<{runId?: string}>} steps ブロック内のステップ列（ソース出現順）
 * @param {number} limit 1局面あたりの上限ステップ数
 * @returns {Array<Array<object>>} 局面ごとのステップ列の配列（0件ブロックは呼び出し元でスキップ）
 */
function splitBlock(steps, limit = LIMIT) {
  if (steps.length === 0) return [];
  if (steps.length <= limit) return [steps];

  const operations = [];
  let cursor = 0;
  while (cursor < steps.length) {
    let end = Math.min(cursor + limit, steps.length);
    // 分断してはならない呼び出しの並び（runId が同一の連続ステップ）の途中で
    // 境界が落ちる場合は、その並びの終端まで境界を後ろへ伸ばす。
    if (end < steps.length) {
      const boundaryRunId = steps[end - 1].runId;
      if (boundaryRunId && steps[end] && steps[end].runId === boundaryRunId) {
        let extended = end;
        while (extended < steps.length && steps[extended].runId === boundaryRunId) {
          extended++;
        }
        end = extended;
      }
    }
    operations.push(steps.slice(cursor, end));
    cursor = end;
  }
  return operations;
}

/**
 * splitOperations — 複数のコメント境界ブロック（rule 2 の出力）へ rule 3 を適用し、
 * 呼び出し0件ブロックは局面を生成しない（rule: 呼び出しが0件の区分の扱い）。
 */
function splitOperations(blocks, limit = LIMIT) {
  const operations = [];
  for (const block of blocks) {
    const parts = splitBlock(block.steps, limit);
    for (const part of parts) operations.push(part);
  }
  return operations;
}

function totalSteps(blocks) {
  return blocks.reduce((sum, b) => sum + b.steps.length, 0);
}

function makeSteps(count, runId) {
  return Array.from({ length: count }, () => (runId ? { runId } : {}));
}

// --- ケース1: コメント境界で分割してもなお上限を超える区分が2件（22件・52件）残る場合、
//     rule 3 を併用して全ブロックが上限以下へ収束すること ---
{
  checks++;
  const blocks = [
    { id: 'phase-a', steps: makeSteps(22) },
    { id: 'phase-b', steps: makeSteps(52) },
  ];
  const before = totalSteps(blocks);
  const operations = splitOperations(blocks);
  const after = operations.reduce((sum, op) => sum + op.length, 0);
  const overLimit = operations.filter((op) => op.length > LIMIT);
  if (overLimit.length > 0) {
    fail('ケース1', `上限15を超える局面が残存: ${overLimit.map((op) => op.length).join(',')}`);
  } else if (after !== before) {
    fail('ケース1', `ステップ総数が変化した: before=${before} after=${after}`);
  } else if (operations.length !== 6) {
    // 22 -> 15+7（2局面）, 52 -> 15+15+15+7（4局面） = 計6局面
    fail('ケース1', `局面数が想定と異なる: expected=6 actual=${operations.length}`);
  } else {
    console.log('PASS: ケース1（コメント境界後もなお上限超過の2ブロックがrule2+rule3併用で収束）');
  }
}

// --- ケース2: 呼び出しが0件のブロックは局面を生成せず、call_order由来ステップの
//     総数（前後ブロックの合計）は変わらないこと ---
{
  checks++;
  const blocks = [
    { id: 'phase-before', steps: makeSteps(5) },
    { id: 'phase-empty', steps: makeSteps(0) },
    { id: 'phase-after', steps: makeSteps(6) },
  ];
  const before = totalSteps(blocks);
  const operations = splitOperations(blocks);
  const after = operations.reduce((sum, op) => sum + op.length, 0);
  if (operations.length !== 2) {
    fail('ケース2', `0件ブロックが局面として生成された、または前後の局面数が想定と異なる: ${operations.length}`);
  } else if (after !== before) {
    fail('ケース2', `ステップ総数が変化した: before=${before} after=${after}`);
  } else {
    console.log('PASS: ケース2（呼び出し0件のブロックは局面を生成せず、総ステップ数は不変）');
  }
}

// --- ケース3: 単一のAPI呼び出しに対応する一連の呼び出し（例: データベース直接アクセスの
//     準備・実行・取得）が15ステップ境界と重なる場合、境界がその並びの内部に落ちず、
//     並びの直前・直後にのみ置かれること ---
{
  checks++;
  // 20ステップ中、index 12-16（5ステップ）が同一runId（"db-access"）の分断禁止の並び。
  // 機械的な15区切りだと本来 index 15 で切れ、runの12-14と15-16が分断されてしまう。
  const steps = makeSteps(20).map((s, i) => (i >= 12 && i <= 16 ? { runId: 'db-access' } : s));
  const blocks = [{ id: 'phase-db', steps }];
  const operations = splitOperations(blocks);

  const runIndicesByOperation = operations.map((op) =>
    op.reduce((acc, step, idx) => {
      if (step.runId === 'db-access') acc.push(idx);
      return acc;
    }, [])
  );
  const opsContainingRun = runIndicesByOperation.filter((idxs) => idxs.length > 0);
  const runFullyContained =
    opsContainingRun.length === 1 && opsContainingRun[0].length === 5;
  const totalAfter = operations.reduce((sum, op) => sum + op.length, 0);

  if (!runFullyContained) {
    fail(
      'ケース3',
      `分断禁止の並びが複数局面へ分断された: ${JSON.stringify(runIndicesByOperation)}`
    );
  } else if (totalAfter !== 20) {
    fail('ケース3', `ステップ総数が変化した: expected=20 actual=${totalAfter}`);
  } else if (operations.length !== 2) {
    fail('ケース3', `局面数が想定と異なる（境界は並びの直前・直後の1箇所のみのはず）: ${operations.length}`);
  } else if (operations[0].length !== 17) {
    // 境界が並びの終端（index 16）まで伸びるため、1局面目は0-16の17ステップになる
    fail('ケース3', `境界が並びの終端まで伸びていない: 1局面目=${operations[0].length}件`);
  } else {
    console.log('PASS: ケース3（分断禁止の並びの直前・直後にのみ境界が置かれ、並びは分断されない）');
  }
}

if (failures.length) {
  console.error(`FAIL sequence diagram splitting (${failures.length})`);
  for (const f of failures) console.error(`- ${f}`);
  console.error(`checked=${checks}`);
  process.exit(1);
}

console.log(`PASS all splitting rule cases (checked=${checks})`);
