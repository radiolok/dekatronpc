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
      .toEqual(['block', 'blocks', 'cables', 'externalElements', 'liberty', 'meta', 'moduleTypes']);
  });

  it('round-trips through deserializeProject', () => {
    const store = createProjectStore();
    store.getState().addBlock('A');
    const loaded = deserializeProject(serializeProject(store.getState()));
    expect(loaded.blocks.A.name).toBe('A');
    expect(loaded.meta.version).toBe(PROJECT_FORMAT_VERSION);
  });
});

describe('deserializeProject — 0.2.0 → 0.4.0', () => {
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

  it('resets the basket geometry to the defaults; rows go to each block', () => {
    expect(p.block).toEqual(DEFAULT_BLOCK_CONFIG);
    expect(b.rows).toBe(3);
    expect(b.connectors).toEqual([]);
    expect(b.powerNets).toEqual([]);
    expect(p.cables).toEqual([]);
    expect(p.moduleTypes.every(t => t.kind === 'board')).toBe(true);
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

/** A 0.3.0 project: rows and a free transformer width on the shared geometry */
function project03(transformerWidth: number) {
  return {
    meta: { projectName: 'P3', createdAt: 'x', updatedAt: 'x', version: '0.3.0' },
    liberty: {}, externalElements: {},
    moduleTypes: [{ id: 'L', name: 'L', widthSteps: 2, slots: [] }],
    block: { rows: 4, rowHeight: 140, rowWidth: 420, gridStep: 12, transformerWidth, obstructions: [] },
    blocks: {
      A: {
        name: 'A',
        netlist: { instances: [], nets: [] },
        placement: {
          modules: [
            { id: 'M1', typeId: 'L', row: 3, col: 0, locked: false },
            { id: 'M2', typeId: 'L', row: 0, col: 12, locked: false }, // x 144..168 mm
          ],
          elements: [],
        },
        routing: { nets: [{ netName: 'n', color: '#000', segments: [
          { id: 's', start: { moduleInstanceId: 'M1', pin: 'A1' }, end: { moduleInstanceId: 'M2', pin: 'A1' },
            path: [], assembled: false },
        ] }] },
      },
    },
  };
}

describe('deserializeProject — 0.3.0 → 0.4.0', () => {
  it('moves rows to each block and adds connectors, power nets, cables and kind', () => {
    const p = deserializeProject(JSON.stringify(project03(84)));
    expect(p.meta.version).toBe('0.4.0');
    expect((p.block as any).rows).toBeUndefined();
    expect(p.blocks.A.rows).toBe(4);
    expect(p.blocks.A.connectors).toEqual([]);
    expect(p.blocks.A.powerNets).toEqual([]);
    expect(p.cables).toEqual([]);
    expect(p.moduleTypes[0].kind).toBe('board');
    expect(p.blocks.A.placement.modules.map(m => m.id)).toEqual(['M1', 'M2']);
  });

  it('snaps the transformer to 72 + 12·K mm and drops modules it now covers', () => {
    // 85 → 84: span 168..252 mm, M2 (144..168 mm) still fits
    expect(deserializeProject(JSON.stringify(project03(85))).block.transformerWidth).toBe(84);
    // 100 → 96: span 162..258 mm covers M2 (144..168); its wire goes too
    const p = deserializeProject(JSON.stringify(project03(100)));
    expect(p.block.transformerWidth).toBe(96);
    expect(p.blocks.A.placement.modules.map(m => m.id)).toEqual(['M1']);
    expect(p.blocks.A.routing.nets).toEqual([]);
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
    expect(p.blocks.Legacy.rows).toBe(3);
  });
});
