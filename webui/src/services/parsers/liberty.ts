// ============================================================================
// Liberty (.lib) file parser
// Handles nested brace blocks (tubes, ff, latch) and extended attributes
// ============================================================================

import type { LibertyCell, LibertyPin, PinDirection } from '@/types';

/** Find matching closing brace starting from `openBraceIndex` */
function findMatchingBrace(source: string, openBraceIndex: number): number {
  let depth = 0;
  for (let i = openBraceIndex; i < source.length; i++) {
    if (source[i] === '{') depth++;
    else if (source[i] === '}') {
      depth--;
      if (depth === 0) return i;
    }
  }
  return -1;
}

/** Extract blocks delimited by `keyword ( name ) { ... }` using brace counting */
function extractNamedBlocks(
  source: string,
  keyword: string,
): { name: string; body: string }[] {
  const results: { name: string; body: string }[] = [];
  const regex = new RegExp(
    `\\b${keyword}\\s*\\(\\s*(\\w+)\\s*\\)\\s*\\{`,
    'g',
  );
  let match: RegExpExecArray | null;
  while ((match = regex.exec(source)) !== null) {
    const name = match[1];
    const openIdx = match.index + match[0].length - 1; // index of '{'
    const closeIdx = findMatchingBrace(source, openIdx);
    if (closeIdx === -1) continue;
    const body = source.slice(openIdx + 1, closeIdx);
    results.push({ name, body });
  }
  return results;
}

/** Parse a simple key-value from liberty body:
 *  keyword : "value" ;   or   keyword : value ;
 */
function parseStringAttr(body: string, key: string): string | undefined {
  const m = body.match(new RegExp(`\\b${key}\\s*:\\s*"([^"]*)"`, 'i'));
  return m ? m[1] : undefined;
}

function parseNumAttr(body: string, key: string): number | undefined {
  const m = body.match(
    new RegExp(`\\b${key}\\s*:\\s*([\\d.]+)\\s*;`, 'i'),
  );
  return m ? parseFloat(m[1]) : undefined;
}

/** Parse `tubes(names) { N16B: 1; J2B: 2; }` */
function parseTubesBlock(body: string): Record<string, number> | undefined {
  const m = body.match(/\btubes\s*\(\s*\w+\s*\)\s*\{([^}]*)\}/);
  if (!m) return undefined;
  const tubes: Record<string, number> = {};
  const kvRegex = /(\w+)\s*:\s*([\d.]+)\s*;/g;
  let kv: RegExpExecArray | null;
  while ((kv = kvRegex.exec(m[1])) !== null) {
    tubes[kv[1]] = parseFloat(kv[2]);
  }
  return Object.keys(tubes).length > 0 ? tubes : undefined;
}

/** Parse pin attributes from a pin body block */
function parsePinBody(body: string): Partial<LibertyPin> {
  const attrs: Partial<LibertyPin> = {};

  const dirMatch = body.match(
    /\bdirection\s*:\s*"?(input|output|inout|internal)"?\s*;/,
  );
  if (dirMatch) attrs.direction = dirMatch[1] as PinDirection;

  const funcMatch = body.match(/\bfunction\s*:\s*"([^"]*)"/);
  if (funcMatch) attrs.function = funcMatch[1];

  const driverMatch = body.match(/\bdriver_type\s*:\s*(\w+)/);
  if (driverMatch) attrs.driverType = driverMatch[1];

  const fanoutMatch = body.match(/\bfanout_load\s*:\s*([\d.]+)\s*;/);
  if (fanoutMatch) attrs.fanoutLoad = parseFloat(fanoutMatch[1]);

  const maxFanoutMatch = body.match(/\bmax_fanout\s*:\s*([\d.]+)\s*;/);
  if (maxFanoutMatch) attrs.maxFanout = parseFloat(maxFanoutMatch[1]);

  const clockMatch = body.match(/\bclock\s*:\s*(true|false)/);
  if (clockMatch) attrs.isClock = clockMatch[1] === 'true';

  return attrs;
}

/**
 * Parse a Synopsys Liberty format file.
 * Handles nested brace blocks (tubes, ff, latch) inside cells.
 */
export function parseLiberty(source: string): Record<string, LibertyCell> {
  const cells: Record<string, LibertyCell> = {};

  // Remove comments
  const clean = source
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/\/\/.*$/gm, '');

  // Use brace counting to extract cell bodies (handles nested braces)
  const cellRegex = /\bcell\s*\(\s*(\w+)\s*\)\s*\{/g;
  let cellMatch: RegExpExecArray | null;
  while ((cellMatch = cellRegex.exec(clean)) !== null) {
    const cellName = cellMatch[1];
    const openIdx = cellMatch.index + cellMatch[0].length - 1; // index of '{'
    const closeIdx = findMatchingBrace(clean, openIdx);
    if (closeIdx === -1) continue;
    const cellBody = clean.slice(openIdx + 1, closeIdx);

    // Parse cell-level attributes
    const area = parseNumAttr(cellBody, 'area');
    const heatCurrent = parseNumAttr(cellBody, 'heat_current');
    const currentUnit = parseStringAttr(cellBody, 'current_unit');
    const tubes = parseTubesBlock(cellBody);
    const isFlipFlop = /\bff\s*\(/.test(cellBody);
    const isLatch = /\blatch\s*\(/.test(cellBody);

    // Extract pins using brace counting
    const pins: LibertyPin[] = [];
    const pinRegex = /\bpin\s*\(\s*(\w+)\s*\)\s*\{/g;
    let pinMatch: RegExpExecArray | null;
    while ((pinMatch = pinRegex.exec(cellBody)) !== null) {
      const pinName = pinMatch[1];
      const pinOpenIdx = pinMatch.index + pinMatch[0].length - 1;
      const pinCloseIdx = findMatchingBrace(cellBody, pinOpenIdx);
      if (pinCloseIdx === -1) continue;
      const pinBody = cellBody.slice(pinOpenIdx + 1, pinCloseIdx);

      const pinAttrs = parsePinBody(pinBody);
      pins.push({
        name: pinName,
        direction: pinAttrs.direction ?? 'inout',
        function: pinAttrs.function,
        driverType: pinAttrs.driverType,
        fanoutLoad: pinAttrs.fanoutLoad,
        maxFanout: pinAttrs.maxFanout,
        isClock: pinAttrs.isClock,
      });
    }

    cells[cellName] = {
      name: cellName,
      pins,
      area,
      heatCurrent,
      currentUnit,
      tubes,
      isFlipFlop,
      isLatch,
    };
  }

  return cells;
}

/**
 * Extract cell names without full parse.
 */
export function extractCellNames(source: string): string[] {
  const clean = source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '');
  const names: string[] = [];
  const regex = /\bcell\s*\(\s*(\w+)\s*\)/g;
  let match: RegExpExecArray | null;
  while ((match = regex.exec(clean)) !== null) {
    names.push(match[1]);
  }
  return names;
}

/**
 * Generate a skeleton Liberty file for a list of cell names.
 */
export function generateSkeletonLiberty(cellNames: string[]): string {
  const lines: string[] = ['library (DekatronPC) {'];
  for (const name of cellNames) {
    lines.push(`  cell (${name}) {`);
    lines.push(`    /* Add pin declarations here */`);
    lines.push(`    /* Example: pin (A) { direction : "input"; } */`);
    lines.push(`  }`);
  }
  lines.push('}');
  return lines.join('\n');
}
