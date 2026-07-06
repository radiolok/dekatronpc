// ============================================================================
// Liberty (.lib) file parser — simplified
// Extracts cell names and pin directions
// ============================================================================

import type { LibertyCell, LibertyPin, PinDirection } from '@/types';

/**
 * Parse a subset of Synopsys Liberty format.
 * Focuses on cell/pin declarations, ignoring timing, power, etc.
 *
 * Expected structure:
 *   library (name) {
 *     cell (CELL_NAME) {
 *       pin (PIN_NAME) {
 *         direction : "input" | "output" | "inout" | "internal";
 *       }
 *     }
 *   }
 */
export function parseLiberty(source: string): Record<string, LibertyCell> {
  const cells: Record<string, LibertyCell> = {};

  // Remove comments
  const clean = source
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/\/\/.*$/gm, '');

  // Match cell blocks: cell (NAME) { ... }
  const cellRegex = /\bcell\s*\(\s*(\w+)\s*\)\s*\{([\s\S]*?)\n\}/g;
  let cellMatch: RegExpExecArray | null;
  while ((cellMatch = cellRegex.exec(clean)) !== null) {
    const cellName = cellMatch[1];
    const cellBody = cellMatch[2];

    const pins: LibertyPin[] = [];
    // Match pin blocks inside cell: pin (NAME) { ... }
    const pinRegex = /\bpin\s*\(\s*(\w+)\s*\)\s*\{([\s\S]*?)\n\s*\}/g;
    let pinMatch: RegExpExecArray | null;
    while ((pinMatch = pinRegex.exec(cellBody)) !== null) {
      const pinName = pinMatch[1];
      const pinBody = pinMatch[2];

      // Extract direction
      const dirMatch = pinBody.match(
        /\bdirection\s*:\s*"(input|output|inout|internal)"/,
      );
      const direction: PinDirection = dirMatch ? dirMatch[1] as PinDirection : 'inout';

      pins.push({ name: pinName, direction });
    }

    cells[cellName] = { name: cellName, pins };
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
 * Useful for bootstrapping when no .lib file exists yet.
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
