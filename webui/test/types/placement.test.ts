// ============================================================================
// Placement helpers — push-aside planning and free-spot search
// Default geometry: 420 mm row, 12 mm grid, 84 mm transformer at 168..252 mm,
// so the row halves are columns [0, 14) and [21, 35).
// ============================================================================

import { describe, it, expect } from 'vitest';
import { createDefaultProject, firstFreeSpot, planModuleMove, rowHalves } from '@/types';
import type { ModuleInstance } from '@/types';

const state = {
  ...createDefaultProject(),
  moduleTypes: [
    { id: 'L', name: 'Logic', kind: 'board' as const, widthSteps: 2, slots: [] },
    { id: 'D', name: 'Dekatron', kind: 'board' as const, widthSteps: 3, slots: [] },
  ],
};
const mod = (id: string, col: number, typeId = 'L', row = 0, locked = false): ModuleInstance =>
  ({ id, typeId, row, col, locked });
const plan = (insts: ModuleInstance[], id: string, typeId: string, row: number, col: number) => {
  const p = planModuleMove(state, 3, insts, { id, typeId }, row, col);
  return p && Object.fromEntries([...p].map(([k, v]) => [k, v.col]));
};

describe('rowHalves', () => {
  it('splits the row at the transformer', () => {
    expect(rowHalves(state)).toEqual([[0, 14], [21, 35]]);
  });
});

describe('planModuleMove', () => {
  it('moves without pushing into free space', () => {
    expect(plan([mod('M1', 0)], 'M1', 'L', 1, 4)).toEqual({ M1: 4 });
  });

  it('pushes right-hand neighbours right', () => {
    // M1 0..1, M2 2..3; a new D at 2..4 shifts M2 (starts at 2) right; M1 is clear
    const insts = [mod('M1', 0), mod('M2', 2)];
    expect(plan(insts, 'NEW', 'D', 0, 2)).toEqual({ NEW: 2, M2: 5 });
  });

  it('pushes left-hand neighbours left', () => {
    const insts = [mod('M1', 4), mod('M2', 6)];
    expect(plan(insts, 'NEW', 'L', 0, 5)).toEqual({ NEW: 5, M1: 3, M2: 7 });
  });

  it('cascades through a chain of modules', () => {
    const insts = [mod('M1', 2), mod('M2', 4), mod('M3', 6)];
    expect(plan(insts, 'NEW', 'L', 0, 2)).toEqual({ NEW: 2, M1: 4, M2: 6, M3: 8 });
  });

  it('refuses when a locked module is in the way', () => {
    expect(plan([mod('M1', 2, 'L', 0, true)], 'NEW', 'L', 0, 2)).toBeNull();
  });

  it('refuses to push past the transformer', () => {
    // 12..13 is the last place of the left half: M1 can't go right
    expect(plan([mod('M1', 12)], 'NEW', 'L', 0, 12)).toBeNull();
    // M1 at 11..12 starts before the drop column, so it goes left instead
    expect(plan([mod('M1', 11)], 'NEW', 'L', 0, 12)).toEqual({ NEW: 12, M1: 10 });
    // Pushing left stops at the row start
    expect(plan([mod('M1', 0)], 'NEW', 'L', 0, 1)).toBeNull();
  });

  it('refuses a target on the transformer, outside the row or the rows', () => {
    expect(plan([], 'NEW', 'L', 0, 14)).toBeNull();
    expect(plan([], 'NEW', 'L', 0, 34)).toBeNull();
    expect(plan([], 'NEW', 'L', 3, 0)).toBeNull();
  });

  it('frees the moved module’s own place first', () => {
    const insts = [mod('M1', 0), mod('M2', 2)];
    expect(plan(insts, 'M1', 'L', 0, 1)).toEqual({ M1: 1, M2: 3 });
  });

  it('never moves a locked module itself', () => {
    expect(plan([mod('M1', 0, 'L', 0, true)], 'M1', 'L', 0, 4)).toBeNull();
  });
});

describe('firstFreeSpot', () => {
  it('scans rows and columns in order, skipping the transformer', () => {
    expect(firstFreeSpot(state, 3, [], 'L')).toEqual({ row: 0, col: 0 });
    const full = Array.from({ length: 7 }, (_, i) => mod(`L${i}`, i * 2));
    expect(firstFreeSpot(state, 3, full, 'L')).toEqual({ row: 0, col: 21 });
  });

  it('returns null when nothing fits', () => {
    const insts = [0, 1, 2].flatMap(row => [
      ...Array.from({ length: 7 }, (_, i) => mod(`a${row}${i}`, i * 2, 'L', row)),
      ...Array.from({ length: 7 }, (_, i) => mod(`b${row}${i}`, 21 + i * 2, 'L', row)),
    ]);
    expect(firstFreeSpot(state, 3, insts, 'L')).toBeNull();
  });
});
