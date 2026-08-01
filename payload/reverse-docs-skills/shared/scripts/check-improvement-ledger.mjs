import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

function countPrecedingBackslashes(text, index) {
  let count = 0;
  for (let cursor = index - 1; cursor >= 0 && text[cursor] === '\\'; cursor -= 1) {
    count += 1;
  }
  return count;
}

export function splitMarkdownTableRow(line) {
  const cells = [];
  let cell = '';
  let unescapedPipeCount = 0;

  for (let index = 0; index < line.length; index += 1) {
    if (line[index] === '|' && countPrecedingBackslashes(line, index) % 2 === 0) {
      cells.push(cell);
      cell = '';
      unescapedPipeCount += 1;
    } else {
      cell += line[index];
    }
  }
  cells.push(cell);

  const hasLeadingPipe = line.trimStart().startsWith('|');
  const hasTrailingPipe = line.trimEnd().endsWith('|')
    && countPrecedingBackslashes(line, line.trimEnd().length - 1) % 2 === 0;
  const tableCells = cells.slice(hasLeadingPipe ? 1 : 0, hasTrailingPipe ? -1 : undefined)
    .map((cellValue) => cellValue.trim());

  return { cells: tableCells, unescapedPipeCount };
}

function isSeparatorRow(cells) {
  return cells.length >= 2 && cells.every((cell) => /^:?-{3,}:?$/.test(cell));
}

function rowReference(lineNumber, cells) {
  return { lineNumber, itemId: cells[0] ?? '' };
}

function isBlankOrAsciiHyphen(cell) {
  return cell === '' || /^-+$/.test(cell);
}

function parseFenceOpener(line) {
  let candidate = line;
  let container = { kind: 'top' };
  const quote = line.match(/^ {0,3}>[ \t]?(.*)$/);
  const list = line.match(/^( {0,3})(?:[-+*]|\d+[.)])([ \t]+)(.*)$/);
  if (quote) {
    candidate = quote[1];
    container = { kind: 'quote' };
  } else if (list) {
    candidate = list[3];
    container = {
      kind: 'list',
      contentIndent: line.length - list[3].length,
    };
  }

  const match = candidate.match(/^( {0,3})(`{3,}|~{3,})(.*)$/);
  if (!match) return null;
  const marker = match[2];
  const infoString = match[3];
  if (marker[0] === '`' && infoString.includes('`')) return null;
  return { character: marker[0], length: marker.length, container };
}

function isWithinFenceContainer(line, fence) {
  if (line.trim() === '' || fence.container.kind === 'top') return true;
  if (fence.container.kind === 'quote') return /^ {0,3}>/.test(line);
  const indentation = line.match(/^[ \t]*/)[0].replaceAll('\t', '    ').length;
  return indentation >= fence.container.contentIndent;
}

function isFenceCloser(line, fence) {
  const marker = fence.character === '`' ? '`' : '~';
  let candidate = line;
  if (fence.container.kind === 'quote') {
    candidate = line.replace(/^ {0,3}>[ \t]?/, '');
  } else if (fence.container.kind === 'list') {
    candidate = line.slice(fence.container.contentIndent);
  }
  return new RegExp(`^ {0,3}${marker}{${fence.length},}[\\t ]*$`)
    .test(candidate);
}

function isIndentedCodeLine(line) {
  return /^(?: {4}|\t)/.test(line);
}

export function parseImprovementLedger(markdown) {
  const lines = markdown.split(/\r?\n/);
  const parsedLines = [];
  let fence = null;

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    if (fence && !isWithinFenceContainer(line, fence)) {
      fence = null;
    }
    if (fence) {
      parsedLines.push({
        line,
        lineNumber: index + 1,
        parsed: splitMarkdownTableRow(line),
        isCodeFence: true,
      });
      if (isFenceCloser(line, fence)) {
        fence = null;
      }
      continue;
    }

    const opener = parseFenceOpener(line);
    parsedLines.push({
      line,
      lineNumber: index + 1,
      parsed: splitMarkdownTableRow(line),
      isCodeFence: Boolean(opener),
      isIndentedCode: isIndentedCodeLine(line),
    });
    if (opener) {
      fence = opener;
    } else {
      fence = null;
    }
  }

  const dataRows = [];

  for (let index = 0; index < parsedLines.length; index += 1) {
    const current = parsedLines[index];
    const next = parsedLines[index + 1];
    const isHeader = !current.isCodeFence
      && !current.isIndentedCode
      && !next?.isCodeFence
      && !next?.isIndentedCode
      && current.parsed.unescapedPipeCount > 0
      && next?.parsed.unescapedPipeCount > 0
      && current.parsed.cells.length === next.parsed.cells.length
      && isSeparatorRow(next.parsed.cells);
    if (!isHeader) continue;

    let dataIndex = index + 2;
    while (dataIndex < parsedLines.length) {
      const dataRow = parsedLines[dataIndex];
      if (dataRow.isCodeFence || dataRow.isIndentedCode || dataRow.line.trim() === '' || dataRow.parsed.unescapedPipeCount === 0) {
        break;
      }
      dataRows.push(dataRow);
      dataIndex += 1;
    }
    index = dataIndex - 1;
  }

  const columnCountHistogram = {};
  const nonSixColumnRows = [];
  const rawUnescapedPipeAnomalies = [];
  const fifthColumnBlankOrHyphen = [];
  const sixthColumnBlankOrHyphen = [];
  const unclassifiableRows = [];
  const multipleClassificationRows = [];
  let unverifiedExactCount = 0;
  let unverifiedContainsCount = 0;
  const verificationTypeCounts = {
    '実データ相当': 0,
    '自己テストのみ': 0,
    '未検証': 0,
  };

  for (const { lineNumber, parsed } of dataRows) {
    const { cells, unescapedPipeCount } = parsed;
    const reference = rowReference(lineNumber, cells);
    columnCountHistogram[cells.length] = (columnCountHistogram[cells.length] ?? 0) + 1;

    if (cells.length !== 6) nonSixColumnRows.push(reference);
    if (cells.length > 6) rawUnescapedPipeAnomalies.push(reference);
    if (isBlankOrAsciiHyphen(cells[4] ?? '')) fifthColumnBlankOrHyphen.push(reference);
    if (isBlankOrAsciiHyphen(cells[5] ?? '')) sixthColumnBlankOrHyphen.push(reference);

    const verification = cells[5] ?? '';
    if (verification === '未検証') unverifiedExactCount += 1;
    if (verification.includes('未検証')) unverifiedContainsCount += 1;

    const matches = [
      ['実データ相当', /^実データ相当(?::|：|・合成データでの検証あり:)/.test(verification)],
      ['自己テストのみ', /^自己テストのみ(?:$|[:：（])/.test(verification)],
      ['未検証', /^未検証(?:$|[:：（])/.test(verification)],
    ].filter(([, matched]) => matched).map(([type]) => type);

    for (const type of matches) verificationTypeCounts[type] += 1;
    if (matches.length === 0) unclassifiableRows.push(reference);
    if (matches.length > 1) multipleClassificationRows.push({ ...reference, types: matches });
  }

  return {
    totalDataRows: dataRows.length,
    hasDataRows: dataRows.length > 0,
    columnCountHistogram,
    nonSixColumnRows,
    rawUnescapedPipeAnomalies,
    fifthColumnBlankOrHyphen,
    sixthColumnBlankOrHyphen,
    unverifiedExactCount,
    unverifiedContainsCount,
    verificationTypeCounts,
    unclassifiableRows,
    multipleClassificationRows,
    passed: dataRows.length > 0
      && nonSixColumnRows.length === 0
      && rawUnescapedPipeAnomalies.length === 0
      && fifthColumnBlankOrHyphen.length === 0
      && sixthColumnBlankOrHyphen.length === 0
      && unclassifiableRows.length === 0
      && multipleClassificationRows.length === 0,
  };
}

function runCli() {
  const scriptDirectory = dirname(fileURLToPath(import.meta.url));
  const targetPath = process.argv[2]
    ? resolve(process.cwd(), process.argv[2])
    : resolve(scriptDirectory, '../../docs/ledgers/改善反映台帳.md');
  const result = parseImprovementLedger(readFileSync(targetPath, 'utf8'));
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  if (!result.passed) process.exitCode = 1;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runCli();
}
