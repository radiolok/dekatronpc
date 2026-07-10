// ============================================================================
// Store integration tests — multi-block architecture
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
  useStore = createProjectStore();
});

describe('Store — Blocks', () => {
  it('addBlock creates an empty block', () => {
    getStore().addBlock('TestBlock');
    expect(getStore().blocks['TestBlock']).toBeDefined();
    expect(getStore().activeBlockId).toBe('TestBlock');
  });

  it('setBlockNetlist creates block and sets netlist', () => {
    const vlogPath = join(__dirname, '..', '..', '..', 'rtl', 'run', 'IpLine_synth.v');
    const source = readFileSync(vlogPath, 'utf-8');
    const netlist = parseVerilogNetlist(source);

    getStore().setBlockNetlist('IpLine', netlist);
    expect(getStore().blocks['IpLine'].netlist.instances.length).toBeGreaterThan(250);
    expect(getStore().blocks['IpLine'].netlist.nets.length).toBeGreaterThan(150);
    expect(getStore().activeBlockId).toBe('IpLine');
  });

  it('setActiveBlock switches blocks', () => {
    getStore().addBlock('BlockA');
    getStore().addBlock('BlockB');
    getStore().setActiveBlock('BlockA');
    expect(getStore().activeBlockId).toBe('BlockA');
    getStore().setActiveBlock('BlockB');
    expect(getStore().activeBlockId).toBe('BlockB');
  });

  it('removeBlock cleans up', () => {
    getStore().addBlock('Tmp');
    getStore().removeBlock('Tmp');
    expect(getStore().blocks['Tmp']).toBeUndefined();
  });
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
});

describe('Store — netlist in block + undo', () => {
  it('setBlockNetlist pushes history and undo works', async () => {
    const vlogPath = join(__dirname, '..', '..', '..', 'rtl', 'run', 'IpLine_synth.v');
    const source = readFileSync(vlogPath, 'utf-8');
    const netlist = parseVerilogNetlist(source);

    getStore().setBlockNetlist('IpLine', netlist);
    await flush();

    expect(getStore().blocks['IpLine'].netlist.instances.length).toBeGreaterThan(250);

    getStore().undo();
    // After undo, the block should not exist (or be empty)
    expect(getStore().blocks['IpLine']?.netlist.instances.length || 0).toBe(0);
  });
});

describe('Store — full pipeline with blocks', () => {
  it('liberty + block netlist → validateCellTypes reports missing', () => {
    const libPath = join(__dirname, '..', '..', '..', 'rtl', 'run', 'vtube_cells.lib');
    getStore().setLiberty(parseLiberty(readFileSync(libPath, 'utf-8')));

    const vlogPath = join(__dirname, '..', '..', '..', 'rtl', 'run', 'IpLine_synth.v');
    getStore().setBlockNetlist('IpLine', parseVerilogNetlist(readFileSync(vlogPath, 'utf-8')));

    const knownTypes = new Set(getAllCellTypes(getStore()).map(c => c.name));
    const missing = validateCellTypes(getStore().blocks['IpLine'].netlist, knownTypes);
    expect(missing.length).toBeGreaterThanOrEqual(4);
    expect(missing).toContain('Dekatron');
    expect(missing).toContain('InsnLoopDetector');
  });

  it('two blocks with same liberty', () => {
    const libPath = join(__dirname, '..', '..', '..', 'rtl', 'run', 'vtube_cells.lib');
    getStore().setLiberty(parseLiberty(readFileSync(libPath, 'utf-8')));

    const vlogPath = join(__dirname, '..', '..', '..', 'rtl', 'run', 'IpLine_synth.v');
    const netlist = parseVerilogNetlist(readFileSync(vlogPath, 'utf-8'));

    getStore().setBlockNetlist('IpLine', netlist);
    getStore().setBlockNetlist('ApLine', netlist); // same netlist for testing

    expect(Object.keys(getStore().blocks)).toHaveLength(2);
    expect(getStore().blocks['IpLine'].netlist.instances.length).toBe(getStore().blocks['ApLine'].netlist.instances.length);
    expect(getStore().activeBlockId).toBe('ApLine');
  });

  it('placement actions target active block', async () => {
    getStore().addBlock('Block1');
    getStore().addBlock('Block2');

    getStore().setActiveBlock('Block1');
    getStore().setModulePlacements([{ moduleId: 'mod1', row: 0, col: 0, locked: false }]);
    await flush();

    getStore().setActiveBlock('Block2');
    getStore().setModulePlacements([{ moduleId: 'mod2', row: 1, col: 1, locked: true }]);
    await flush();

    expect(getStore().blocks['Block1'].placement.modules).toHaveLength(1);
    expect(getStore().blocks['Block2'].placement.modules).toHaveLength(1);
    expect(getStore().blocks['Block1'].placement.modules[0].moduleId).toBe('mod1');
    expect(getStore().blocks['Block2'].placement.modules[0].moduleId).toBe('mod2');
  });
});
