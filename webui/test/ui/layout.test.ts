// ============================================================================
// Block canvas layout math (mm ↔ grid cells, connector slots)
// ============================================================================

import { describe, it, expect } from 'vitest';
import { DEFAULT_BLOCK_CONFIG as cfg } from '@/types';
import {
  ROWS_TOP, MARGIN, canvasSize, cellAt, connectorPitch, rowTop, snapConnector, snapToCell,
} from '@/components/Placement/layout';

describe('canvas layout', () => {
  it('stacks rows under the connector strip', () => {
    expect(rowTop(0, cfg)).toBe(ROWS_TOP);
    expect(rowTop(2, cfg)).toBe(ROWS_TOP + 280);
    expect(canvasSize(cfg, 3, 0)).toEqual({ width: 420 + 2 * MARGIN, height: ROWS_TOP + 420 + 2 * MARGIN });
    expect(canvasSize(cfg, 3, 8).width).toBe(8 * connectorPitch + 2 * MARGIN);
  });

  it('snaps a dragged module to the nearest cell, inside the rows', () => {
    expect(snapToCell(29, ROWS_TOP + 150, cfg, 3, 2)).toEqual({ row: 1, col: 2 });
    expect(snapToCell(-40, -500, cfg, 3, 2)).toEqual({ row: 0, col: 0 });
    expect(snapToCell(1000, 9999, cfg, 3, 2)).toEqual({ row: 2, col: 33 });
  });

  it('finds the cell under a point, or none outside the rows', () => {
    expect(cellAt(25, ROWS_TOP + 1, cfg, 3)).toEqual({ row: 0, col: 2 });
    expect(cellAt(25, 10, cfg, 3)).toBeNull();
    expect(cellAt(425, ROWS_TOP + 1, cfg, 3)).toBeNull();
  });

  it('snaps connectors to slots', () => {
    expect(snapConnector(connectorPitch * 1.4, 3)).toBe(1);
    expect(snapConnector(9999, 3)).toBe(2);
    expect(snapConnector(-50, 3)).toBe(0);
  });
});
