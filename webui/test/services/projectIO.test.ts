// ============================================================================
// Project file I/O — serialization and format migration
// ============================================================================

import { describe, it, expect } from 'vitest';
import { serializeProject, deserializeProject } from '@/services/projectIO';
import { createProjectStore } from '@/store/projectStore';
import { DEFAULT_BLOCK_CONFIG, PROJECT_FORMAT_VERSION } from '@/types';

/** A 0.2.0 project: modules are placed directly, chassis is the old 920 mm one */
const PROJECT_02 = {
  meta: { projectName: 'Old', createdAt: 'x', updatedAt: 'x', version: '0.2.0' },
  liberty: {},
  externalElements: {},
  modules: [
    { id: 'L1', name: 'Logic', widthSteps: 2, slotInstances: [],
      slots: [{ cellType: 'NAND2', count: 2, pinMapping: [{ cellPin: 'A', contactId: 'A1' }] }] },
    { id: 'L2', name: 'Logic', widthSteps: 2, slotInstances: [], slots: [] },
  ],
  block: { rows: 3, maxCols: 24, verticalPitch: 59.3, gridStep: 12, margin: 20,
           chassisWidth: 920, chassisHeight: 420, obstructions: [] },
  blocks: {
    IpLine: {
      name: 'IpLine',
      netlist: { instances: [{ name: 'U1', cellType: 'NAND2', connections: {} }], nets: [] },
      placement: {
        modules: [
          { moduleId: 'L1', row: 0, col: 0, locked: true },
          { moduleId: 'L2', row: 0, col: 15, locked: false }, // inside the transformer keep-out
        ],
        elements: [
          { instanceName: 'U1', moduleId: 'L1', slotIndex: 1, locked: false },
          { instanceName: 'U2', moduleId: 'L2', slotIndex: 0, locked: false },
        ],
      },
      routing: {
        nets: [
          { netName: 'n1', color: '#fff', segments: [
            { id: 's1', start: { moduleId: 'L1', pin: 'A1' }, end: { moduleId: 'L1', pin: 'B1' },
              path: [], assembled: true },
          ] },
          { netName: 'n2', color: '#000', segments: [
            { id: 's2', start: { moduleId: 'L1', pin: 'A2' }, end: { moduleId: 'L2', pin: 'B2' },
              path: [], assembled: false },
          ] },
        ],
      },
    },
  },
};

describe('serializeProject', () => {
  it('writes project data only, not history, actions or UI state', () => {
    const store = createProjectStore();
    store.getState().addBlock('A');
    store.getState().addBlock('B');
    expect(store.getState().past.length).toBe(2);

    const json = JSON.parse(serializeProject(store.getState()));
    expect(Object.keys(json).sort())
      .toEqual(['block', 'blocks', 'externalElements', 'liberty', 'meta', 'moduleTypes']);
  });

  it('round-trips through deserializeProject', () => {
    const store = createProjectStore();
    store.getState().addBlock('A');
    const loaded = deserializeProject(serializeProject(store.getState()));
    expect(loaded.blocks.A.name).toBe('A');
    expect(loaded.meta.version).toBe(PROJECT_FORMAT_VERSION);
  });
});

describe('deserializeProject — 0.2.0 → 0.3.0', () => {
  const p = deserializeProject(JSON.stringify(PROJECT_02));
  const b = p.blocks.IpLine;

  it('bumps the version and drops the old fields', () => {
    expect(p.meta.version).toBe(PROJECT_FORMAT_VERSION);
    expect((p as any).modules).toBeUndefined();
  });

  it('turns hardware modules into module types; the slot pin map goes to copy 0', () => {
    expect(p.moduleTypes.map(t => t.id)).toEqual(['L1', 'L2']);
    expect(p.moduleTypes[0].slots[0].pinMaps).toEqual([[{ cellPin: 'A', contactId: 'A1' }], []]);
  });

  it('resets the chassis to the 0.3 geometry, keeping rows', () => {
    expect(p.block).toEqual({ ...DEFAULT_BLOCK_CONFIG, rows: 3 });
  });

  it('keeps placements that fit and drops the rest with their elements and wires', () => {
    expect(b.placement.modules).toEqual([{ id: 'L1', typeId: 'L1', row: 0, col: 0, locked: true }]);
    expect(b.placement.elements).toEqual([
      { instanceName: 'U1', moduleInstanceId: 'L1', slotIndex: 1, locked: false },
    ]);
    expect(b.routing.nets.map(n => n.netName)).toEqual(['n1']);
    expect(b.routing.nets[0].segments[0].start).toEqual({ moduleInstanceId: 'L1', pin: 'A1' });
  });

  it('loads into a store', () => {
    const store = createProjectStore();
    store.getState().loadProject(p);
    expect(store.getState().activeBlockId).toBe('IpLine');
    expect(store.getState().moduleTypes.length).toBe(2);
  });
});

describe('deserializeProject — pre-0.2 single netlist', () => {
  it('wraps the netlist into a Legacy block and migrates on to 0.3.0', () => {
    const p = deserializeProject(JSON.stringify({
      meta: { projectName: 'Older', createdAt: 'x', updatedAt: 'x', version: '0.1.0' },
      liberty: {}, externalElements: {}, modules: [],
      block: { rows: 3 },
      netlist: { instances: [], nets: [] },
    }));
    expect(Object.keys(p.blocks)).toEqual(['Legacy']);
    expect(p.moduleTypes).toEqual([]);
    expect(p.meta.version).toBe(PROJECT_FORMAT_VERSION);
  });
});
