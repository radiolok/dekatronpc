// ============================================================================
// Module placement in a row — pure helpers (no React, no store)
//
// Columns count gridStep steps from the left edge of a row. The transformer
// splits every row into two halves; a module never straddles or jumps it.
// ============================================================================

import type { ModuleInstance, ProjectState } from './project';
import { canPlaceModule, columnsPerRow, transformerSpan } from './project';

type PlaceState = Pick<ProjectState, 'block' | 'moduleTypes'>;

/** Free column ranges of a row half: [first, end) in columns */
export function rowHalves(state: PlaceState): [number, number][] {
  const { gridStep } = state.block;
  const [t0, t1] = transformerSpan(state.block);
  return [
    [0, Math.floor(t0 / gridStep)],
    [Math.ceil(t1 / gridStep), columnsPerRow(state.block)],
  ];
}

const widthOf = (state: PlaceState, typeId: string) =>
  state.moduleTypes.find(t => t.id === typeId)?.widthSteps ?? 1;

/**
 * Plan moving (or, with a new id, adding) a module to (row, col), pushing the
 * unlocked modules of that row aside to make room (agents.md §3.4).
 * Like inserting: modules starting at or after `col` go right, modules starting
 * before it go left. Pushing stops at the transformer and the row ends.
 *
 * Returns the new positions of every module that changes (including the moved
 * one), or null if there is no room or a locked module is in the way.
 */
export function planModuleMove(
  state: PlaceState,
  rows: number,
  instances: ModuleInstance[],
  move: { id: string; typeId: string },
  row: number,
  col: number,
): Map<string, { row: number; col: number }> | null {
  const self = instances.find(m => m.id === move.id);
  if (self?.locked) return null;
  const others = instances.filter(m => m.id !== move.id);
  // Without collisions this is a plain move
  if (canPlaceModule(state, rows, others, move.typeId, row, col)) {
    return new Map([[move.id, { row, col }]]);
  }
  if (!canPlaceModule(state, rows, [], move.typeId, row, col)) return null;

  const w = widthOf(state, move.typeId);
  const half = rowHalves(state).find(([a, b]) => col >= a && col + w <= b)!;
  const inRow = others.filter(m => m.row === row);
  const plan = new Map<string, { row: number; col: number }>([[move.id, { row, col }]]);

  const right = inRow.filter(m => m.col >= col).sort((a, b) => a.col - b.col);
  let cursor = col + w;
  for (const m of right) {
    if (m.col >= cursor) break;
    if (m.locked) return null;
    const mw = widthOf(state, m.typeId);
    if (cursor + mw > half[1]) return null;
    plan.set(m.id, { row, col: cursor });
    cursor += mw;
  }

  const left = inRow.filter(m => m.col < col).sort((a, b) => b.col - a.col);
  cursor = col;
  for (const m of left) {
    const mw = widthOf(state, m.typeId);
    if (m.col + mw <= cursor) break;
    if (m.locked) return null;
    if (cursor - mw < half[0]) return null;
    plan.set(m.id, { row, col: cursor - mw });
    cursor -= mw;
  }
  return plan;
}

/** First free (row, col), scanning rows top to bottom and columns left to right */
export function firstFreeSpot(
  state: PlaceState,
  rows: number,
  instances: ModuleInstance[],
  typeId: string,
): { row: number; col: number } | null {
  const cols = columnsPerRow(state.block);
  for (let row = 0; row < rows; row++) {
    for (let col = 0; col < cols; col++) {
      if (canPlaceModule(state, rows, instances, typeId, row, col)) return { row, col };
    }
  }
  return null;
}
