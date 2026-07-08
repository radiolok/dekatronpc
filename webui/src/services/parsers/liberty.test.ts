// ============================================================================
// Liberty parser unit tests — validates parseLiberty with real vtube_cells.lib
// ============================================================================

import { describe, it, expect, beforeAll } from 'vitest';
import { readFileSync } from 'fs';
import { join } from 'path';
import { parseLiberty, extractCellNames } from './liberty';

let cells: ReturnType<typeof parseLiberty>;

beforeAll(() => {
  const libPath = join(__dirname, '..', '..', '..', '..', 'rtl', 'run', 'vtube_cells.lib');
  const source = readFileSync(libPath, 'utf-8');
  cells = parseLiberty(source);
});

describe('parseLiberty', () => {
  it('parses all 23 cells', () => {
    expect(Object.keys(cells)).toHaveLength(23);
  });

  it('parses gate cells with correct pin directions', () => {
    const and2 = cells['AND2_N16X7'];
    expect(and2).toBeDefined();
    expect(and2.pins).toHaveLength(3);
    expect(and2.pins.find(p => p.name === 'A')?.direction).toBe('input');
    expect(and2.pins.find(p => p.name === 'B')?.direction).toBe('input');
    expect(and2.pins.find(p => p.name === 'Y')?.direction).toBe('output');
  });

  it('extracts logic function from pin', () => {
    const not = cells['NOT_6N16B'];
    const yPin = not.pins.find(p => p.name === 'Y');
    expect(yPin?.function).toBe("A'");
  });

  it('extracts area and heat_current', () => {
    const nand4 = cells['NAND4_N16X7'];
    expect(nand4.area).toBe(2.5);
    expect(nand4.heatCurrent).toBe(800);
  });

  it('extracts tubes', () => {
    const nand4 = cells['NAND4_N16X7'];
    expect(nand4.tubes).toEqual({ N16B: 0.5, X7B: 2 });
  });

  it('detects flip-flop cells', () => {
    expect(cells['DFF'].isFlipFlop).toBe(true);
    expect(cells['DFFSR'].isFlipFlop).toBe(true);
    expect(cells['DFFSR_n'].isFlipFlop).toBe(true);
  });

  it('detects latch cells', () => {
    expect(cells['LATCH'].isLatch).toBe(true);
  });

  it('handles TIEHI/TIELO with tie values', () => {
    expect(cells['TIEHI'].pins[0].function).toBe('1');
    expect(cells['TIELO'].pins[0].function).toBe('0');
  });

  it('parses every cell with at least one pin', () => {
    for (const [name, cell] of Object.entries(cells)) {
      expect(cell.pins.length, `${name} has no pins`).toBeGreaterThan(0);
    }
  });

  it('every pin has a valid direction', () => {
    const validDirs = new Set(['input', 'output', 'inout', 'internal']);
    for (const [name, cell] of Object.entries(cells)) {
      for (const pin of cell.pins) {
        expect(validDirs.has(pin.direction), `${name}.${pin.name} direction=${pin.direction}`).toBe(true);
      }
    }
  });
});

describe('extractCellNames', () => {
  it('returns all 23 cell names', () => {
    const libPath = join(__dirname, '..', '..', '..', '..', 'rtl', 'run', 'vtube_cells.lib');
    const source = readFileSync(libPath, 'utf-8');
    const names = extractCellNames(source);
    expect(names).toHaveLength(23);
    expect(names).toContain('AND2_N16X7');
    expect(names).toContain('DFFSR_n');
  });
});
