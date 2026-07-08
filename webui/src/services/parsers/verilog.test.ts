// ============================================================================
// Verilog parser unit tests — validates parseVerilogNetlist with IpLine_synth.v
// ============================================================================

import { describe, it, expect, beforeAll } from 'vitest';
import { readFileSync } from 'fs';
import { join } from 'path';
import { parseVerilogNetlist, extractWireNames, validateCellTypes } from './verilog';
import type { ParsedNetlist } from '@/types';

let netlist: ParsedNetlist;

beforeAll(() => {
  const vlogPath = join(__dirname, '..', '..', '..', '..', 'rtl', 'run', 'IpLine_synth.v');
  const source = readFileSync(vlogPath, 'utf-8');
  netlist = parseVerilogNetlist(source);
});

describe('parseVerilogNetlist', () => {
  it('parses 250+ instances', () => {
    expect(netlist.instances.length).toBeGreaterThan(250);
  });

  it('parses 150+ nets', () => {
    expect(netlist.nets.length).toBeGreaterThan(150);
  });

  it('parses gate-level instances', () => {
    const names = netlist.instances.map(i => i.name);
    // Yosys generates auto-named instances like _26_, _27_
    expect(names.some(n => n.startsWith('_'))).toBe(true);
  });

  it('detects all 11 gate cell types used in the netlist', () => {
    const gateTypes = new Set([
      'NOT_6N16B', 'NAND2_J2', 'NOR2_N16', 'AND2_N16X7',
      'OR2_N16', 'NOR4_N16', 'NAND4_N16X7', 'A1OOI_N16X7',
      'A2OOI_N16X7', 'OR4_N16X7', 'DFFSR_n',
    ]);
    const foundTypes = new Set(netlist.instances.map(i => i.cellType));
    for (const gt of gateTypes) {
      expect(foundTypes.has(gt), `Missing gate type: ${gt}`).toBe(true);
    }
  });

  it('counts NOT_6N16B instances correctly', () => {
    const nots = netlist.instances.filter(i => i.cellType === 'NOT_6N16B');
    expect(nots.length).toBeGreaterThan(30);
  });

  it('counts DFFSR_n instances correctly', () => {
    const dffs = netlist.instances.filter(i => i.cellType === 'DFFSR_n');
    expect(dffs.length).toBeGreaterThan(20);
  });

  it('parses submodule instances (not in liberty)', () => {
    const subNames = ['Dekatron', 'DekatronPulseSender', 'Impulse', 'InsnLoopDetector'];
    const foundTypes = new Set(netlist.instances.map(i => i.cellType));
    for (const sn of subNames) {
      expect(foundTypes.has(sn), `Missing submodule: ${sn}`).toBe(true);
    }
  });

  it('parses escaped identifier cell types (Yosys parameterized modules)', () => {
    const escaped = netlist.instances.filter(i => i.cellType.startsWith('\\'));
    expect(escaped.length).toBeGreaterThanOrEqual(2);
    // Both DekatronCounter variants should be found
    const hasIpCounter = escaped.some(i => i.cellType.includes('D_NUM=4\'0101'));
    const hasLoopCounter = escaped.some(i => i.cellType.includes('D_NUM=4\'0011'));
    expect(hasIpCounter).toBe(true);
    expect(hasLoopCounter).toBe(true);
  });

  it('correctly resolves net fanout', () => {
    // Find the net with highest fanout (should be a clock or reset)
    const maxFanout = Math.max(...netlist.nets.map(n => n.terminals.length));
    expect(maxFanout).toBeGreaterThan(30);
  });

  it('skips constant port connections (1\'h0, etc.) in net tracking', () => {
    // Nets should not include constant values as terminals
    for (const net of netlist.nets) {
      for (const term of net.terminals) {
        expect(term.instance).toBeTruthy();
        expect(term.port).toBeTruthy();
      }
    }
  });

  it('every instance has at least one connection', () => {
    for (const inst of netlist.instances) {
      expect(Object.keys(inst.connections).length, `${inst.name} has no connections`).toBeGreaterThan(0);
    }
  });
});

describe('extractWireNames', () => {
  it('extracts 150+ wire names', () => {
    const vlogPath = join(__dirname, '..', '..', '..', '..', 'rtl', 'run', 'IpLine_synth.v');
    const source = readFileSync(vlogPath, 'utf-8');
    const wires = extractWireNames(source);
    expect(wires.length).toBeGreaterThan(150);
  });
});

describe('validateCellTypes', () => {
  it('reports missing cell types for submodules', () => {
    const knownTypes = new Set([
      'NOT_6N16B', 'NAND2_J2', 'NOR2_N16', 'AND2_N16X7',
      'OR2_N16', 'NOR4_N16', 'NAND4_N16X7', 'A1OOI_N16X7',
      'A2OOI_N16X7', 'OR4_N16X7', 'DFFSR_n',
    ]);
    const missing = validateCellTypes(netlist, knownTypes);
    // Should report ~6 missing types (submodules + escaped identifiers)
    expect(missing.length).toBeGreaterThanOrEqual(4);
    expect(missing).toContain('Dekatron');
    expect(missing).toContain('InsnLoopDetector');
  });
});
