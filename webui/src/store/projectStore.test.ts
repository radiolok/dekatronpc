// ============================================================================
// Store integration tests — validates setLiberty/setNetlist + undo/redo
// ============================================================================

import { describe, it, expect, beforeEach } from 'vitest';
import { readFileSync } from 'fs';
import { join } from 'path';
import { createProjectStore } from './projectStore';
import { parseLiberty } from '@/services/parsers/liberty';
import { parseVerilogNetlist, validateCellTypes } from '@/services/parsers/verilog';
import { getAllCellTypes } from '@/types';
import type { ProjectStore } from './projectStore';

let useStore: ReturnType<typeof createProjectStore>;

function getStore(): ProjectStore {
  return useStore.getState();
}

/** Flush queued microtasks so deferred pushHistory completes before assertions */
const flush = () => new Promise<void>(r => setTimeout(r, 0));

beforeEach(() => {
  // Fresh store for each test
  useStore = createProjectStore();
});

describe('Store — Liberty', () => {
  it('setLiberty stores parsed cells', () => {
    const libPath = join(__dirname, '..', '..', '..', 'rtl', 'run', 'vtube_cells.lib');
    const source = readFileSync(libPath, 'utf-8');
    const cells = parseLiberty(source);

    getStore().setLiberty(cells);
    expect(Object.keys(getStore().liberty)).toHaveLength(23);
    expect(getStore().liberty['AND2_N16X7']).toBeDefined();
  });

  it('setLiberty pushes history entry', async () => {
    const libPath = join(__dirname, '..', '..', '..', 'rtl', 'run', 'vtube_cells.lib');
    const source = readFileSync(libPath, 'utf-8');
    const cells = parseLiberty(source);

    getStore().setLiberty(cells);
    await flush();
    expect(getStore().past.length).toBeGreaterThanOrEqual(1);
    expect(getStore().past.some(e => e.label.includes('liberty'))).toBe(true);
  });

  it('undo after setLiberty restores empty liberty', async () => {
    const libPath = join(__dirname, '..', '..', '..', 'rtl', 'run', 'vtube_cells.lib');
    const source = readFileSync(libPath, 'utf-8');
    const cells = parseLiberty(source);

    getStore().setLiberty(cells);
    await flush();
    expect(Object.keys(getStore().liberty)).toHaveLength(23);

    getStore().undo();
    expect(Object.keys(getStore().liberty)).toHaveLength(0);
  });

  it('redo after undo restores liberty', async () => {
    const libPath = join(__dirname, '..', '..', '..', 'rtl', 'run', 'vtube_cells.lib');
    const source = readFileSync(libPath, 'utf-8');
    const cells = parseLiberty(source);

    getStore().setLiberty(cells);
    await flush();
    getStore().undo();
    expect(Object.keys(getStore().liberty)).toHaveLength(0);

    getStore().redo();
    expect(Object.keys(getStore().liberty)).toHaveLength(23);
  });
});

describe('Store — Netlist', () => {
  it('setNetlist stores parsed instances and nets', () => {
    const vlogPath = join(__dirname, '..', '..', '..', 'rtl', 'run', 'IpLine_synth.v');
    const source = readFileSync(vlogPath, 'utf-8');
    const netlist = parseVerilogNetlist(source);

    getStore().setNetlist(netlist);
    expect(getStore().netlist.instances.length).toBeGreaterThan(250);
    expect(getStore().netlist.nets.length).toBeGreaterThan(150);
  });
});

describe('Store — full pipeline', () => {
  it('liberty + netlist → validateCellTypes reports missing types', () => {
    // Load liberty
    const libPath = join(__dirname, '..', '..', '..', 'rtl', 'run', 'vtube_cells.lib');
    const libSource = readFileSync(libPath, 'utf-8');
    getStore().setLiberty(parseLiberty(libSource));

    // Load netlist
    const vlogPath = join(__dirname, '..', '..', '..', 'rtl', 'run', 'IpLine_synth.v');
    const vlogSource = readFileSync(vlogPath, 'utf-8');
    getStore().setNetlist(parseVerilogNetlist(vlogSource));

    // Validate
    const knownTypes = new Set(getAllCellTypes(getStore()).map(c => c.name));
    const missing = validateCellTypes(getStore().netlist, knownTypes);

    // Submodules + escaped identifiers should be missing
    expect(missing.length).toBeGreaterThanOrEqual(4);
    expect(missing).toContain('Dekatron');
    expect(missing).toContain('InsnLoopDetector');
  });

  it('does not throw when parsing the same file twice', () => {
    const libPath = join(__dirname, '..', '..', '..', 'rtl', 'run', 'vtube_cells.lib');
    const libSource = readFileSync(libPath, 'utf-8');
    const cells = parseLiberty(libSource);

    // First parse
    expect(() => getStore().setLiberty(cells)).not.toThrow();
    // Second parse (should update in place)
    expect(() => getStore().setLiberty(cells)).not.toThrow();
    expect(Object.keys(getStore().liberty)).toHaveLength(23);
  });

  it('undo across multiple actions', async () => {
    const libPath = join(__dirname, '..', '..', '..', 'rtl', 'run', 'vtube_cells.lib');
    const libSource = readFileSync(libPath, 'utf-8');
    getStore().setLiberty(parseLiberty(libSource));
    await flush();

    const vlogPath = join(__dirname, '..', '..', '..', 'rtl', 'run', 'IpLine_synth.v');
    const vlogSource = readFileSync(vlogPath, 'utf-8');
    getStore().setNetlist(parseVerilogNetlist(vlogSource));
    await flush();

    expect(Object.keys(getStore().liberty)).toHaveLength(23);
    expect(getStore().netlist.instances.length).toBeGreaterThan(250);

    // Undo netlist
    getStore().undo();
    expect(getStore().netlist.instances).toHaveLength(0);
    expect(Object.keys(getStore().liberty)).toHaveLength(23);

    // Undo liberty
    getStore().undo();
    expect(Object.keys(getStore().liberty)).toHaveLength(0);

    // Redo liberty
    getStore().redo();
    expect(Object.keys(getStore().liberty)).toHaveLength(23);
    expect(getStore().netlist.instances).toHaveLength(0);

    // Redo netlist
    getStore().redo();
    expect(getStore().netlist.instances.length).toBeGreaterThan(250);
  });
});
