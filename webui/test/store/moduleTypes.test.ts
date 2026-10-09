// ============================================================================
// Module types — validation, pin maps, auto-assign, connector helpers
// ============================================================================

import { describe, it, expect, beforeEach } from 'vitest';
import { createProjectStore } from '@/store/projectStore';
import type { ProjectStore } from '@/store/projectStore';
import { CONTACT_IDS, contactUsage, isContactId, moduleTubes } from '@/types';
import type { LibertyCell } from '@/types';

let useStore: ReturnType<typeof createProjectStore>;
const S = (): ProjectStore => useStore.getState();
const T = () => S().moduleTypes[0];

const NAND2: LibertyCell = {
  name: 'NAND2',
  pins: [{ name: 'A', direction: 'input' }, { name: 'B', direction: 'input' }, { name: 'Y', direction: 'output' }],
  tubes: { J2B: 1 },
};

beforeEach(() => {
  useStore = createProjectStore();
  S().setLiberty({ NAND2 });
  S().addExternalElement({
    name: 'DEK',
    pins: [
      { name: 'Clk', direction: 'input', type: 'clock' },
      { name: 'HV', direction: 'input', type: 'power' },
    ],
  });
  S().addModuleType({ id: 'T1', name: 'Logic', kind: 'board', widthSteps: 2, slots: [] });
});

describe('connector helpers', () => {
  it('lists 72 contacts A1..A36, B1..B36', () => {
    expect(CONTACT_IDS).toHaveLength(72);
    expect([CONTACT_IDS[0], CONTACT_IDS[35], CONTACT_IDS[36], CONTACT_IDS[71]]).toEqual(['A1', 'A36', 'B1', 'B36']);
    expect(isContactId('B36')).toBe(true);
    expect(isContactId('A37')).toBe(false);
    expect(isContactId('C1')).toBe(false);
  });

  it('counts tubes from the liberty', () => {
    S().addSlot('T1', 'NAND2', 4);
    S().addSlot('T1', 'DEK', 1);
    expect(moduleTubes(T(), S().liberty)).toEqual({ J2B: 4 });
  });
});

describe('updateModuleType', () => {
  it('keeps the name when given an empty one, and clears an empty Verilog module', () => {
    S().updateModuleType('T1', { name: '  ', verilogModule: 'DekatronModule' });
    expect(T().name).toBe('Logic');
    expect(T().verilogModule).toBe('DekatronModule');
    S().updateModuleType('T1', { verilogModule: ' ' });
    expect(T().verilogModule).toBeUndefined();
  });

  it('rejects a width that is not a positive integer', () => {
    S().updateModuleType('T1', { widthSteps: 0 });
    S().updateModuleType('T1', { widthSteps: 2.5 });
    expect(T().widthSteps).toBe(2);
  });

  it('refuses a width that a placed instance would not fit', () => {
    S().addBlock('B');
    S().addModuleInstance('T1', 0, 0); // cols 0..1
    S().addModuleInstance('T1', 0, 2); // cols 2..3
    S().updateModuleType('T1', { widthSteps: 3 }); // M1 would overlap M2
    expect(T().widthSteps).toBe(2);
    S().removeModuleInstance('M2');
    S().updateModuleType('T1', { widthSteps: 3 });
    expect(T().widthSteps).toBe(3);
  });
});

describe('pin maps', () => {
  beforeEach(() => S().addSlot('T1', 'NAND2', 2));

  it('drops unknown contacts and repeated cell pins', () => {
    S().setSlotPinMap('T1', 0, 0, [
      { cellPin: 'A', contactId: 'A1' },
      { cellPin: 'A', contactId: 'A2' },
      { cellPin: 'B', contactId: 'Z9' },
      { cellPin: 'Y', contactId: 'B36' },
    ]);
    expect(T().slots[0].pinMaps[0]).toEqual([
      { cellPin: 'A', contactId: 'A1' },
      { cellPin: 'Y', contactId: 'B36' },
    ]);
  });

  it('reports contacts used by more than one pin', () => {
    S().setSlotPinMap('T1', 0, 0, [{ cellPin: 'A', contactId: 'A1' }]);
    S().setSlotPinMap('T1', 0, 1, [{ cellPin: 'A', contactId: 'A1' }]);
    expect(contactUsage(T()).get('A1')).toEqual([
      { slotDefIndex: 0, copy: 0, cellPin: 'A' },
      { slotDefIndex: 0, copy: 1, cellPin: 'A' },
    ]);
  });

  it('auto-assigns free contacts in order, skipping mapped and power pins', () => {
    S().setSlotPinMap('T1', 0, 0, [{ cellPin: 'B', contactId: 'A1' }]);
    S().addSlot('T1', 'DEK', 1);
    S().autoAssignContacts('T1');
    const maps = T().slots.map(sl => sl.pinMaps);
    expect(maps[0][0]).toEqual([
      { cellPin: 'B', contactId: 'A1' },
      { cellPin: 'A', contactId: 'A2' },
      { cellPin: 'Y', contactId: 'A3' },
    ]);
    expect(maps[0][1].map(m => m.contactId)).toEqual(['A4', 'A5', 'A6']);
    expect(maps[1][0]).toEqual([{ cellPin: 'Clk', contactId: 'A7' }]); // HV is power
  });

  it('auto-assign is one undo step and a no-op when all pins are mapped', () => {
    S().autoAssignContacts('T1');
    const steps = S().past.length;
    S().autoAssignContacts('T1');
    expect(S().past.length).toBe(steps);
    S().undo();
    expect(T().slots[0].pinMaps).toEqual([[], []]);
  });

  it('auto-assign stops when the connector is full', () => {
    S().addSlot('T1', 'NAND2', 30); // 32 copies × 3 pins = 96 > 72
    S().autoAssignContacts('T1');
    expect(contactUsage(T()).size).toBe(72);
  });
});
