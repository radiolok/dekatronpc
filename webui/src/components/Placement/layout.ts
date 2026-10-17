// ============================================================================
// Block canvas layout, in mm. The canvas shows one block from the top:
//   y = 0 .. STRIP_HEIGHT        connector strip (HD-68 sockets, Q9)
//   y = ROWS_TOP + r·rowHeight   basket r
// x = 0 is the left edge of the rows. Konva draws in these units; the stage
// scale turns them into pixels.
// ============================================================================

import type { BlockConfig } from '@/types';
import { clamp } from '@/utils/helpers';

export const STRIP_HEIGHT = 36;
export const ROWS_TOP = STRIP_HEIGHT + 12;
export const CONNECTOR_WIDTH = 60;   // an HD-68 socket with its shell, roughly
export const CONNECTOR_GAP = 8;
export const MARGIN = 24;            // left gutter for row labels, and padding

export const connectorPitch = CONNECTOR_WIDTH + CONNECTOR_GAP;

export function rowTop(row: number, cfg: BlockConfig): number {
  return ROWS_TOP + row * cfg.rowHeight;
}

/** Whole drawing size in mm, including margins */
export function canvasSize(cfg: BlockConfig, rows: number, connectors: number): { width: number; height: number } {
  const strip = connectors * connectorPitch;
  return {
    width: MARGIN * 2 + Math.max(cfg.rowWidth, strip),
    height: MARGIN * 2 + ROWS_TOP + rows * cfg.rowHeight,
  };
}

/**
 * Nearest grid cell for a module whose top-left corner is at (x, y) mm,
 * clamped to the rows and to columns where a module of `widthSteps` starts.
 */
export function snapToCell(
  x: number,
  y: number,
  cfg: BlockConfig,
  rows: number,
  widthSteps: number,
): { row: number; col: number } {
  const cols = Math.floor(cfg.rowWidth / cfg.gridStep);
  return {
    row: clamp(Math.round((y - ROWS_TOP) / cfg.rowHeight), 0, rows - 1),
    col: clamp(Math.round(x / cfg.gridStep), 0, cols - widthSteps),
  };
}

/** Grid cell under a point (for click-to-place) */
export function cellAt(
  x: number,
  y: number,
  cfg: BlockConfig,
  rows: number,
): { row: number; col: number } | null {
  const row = Math.floor((y - ROWS_TOP) / cfg.rowHeight);
  const col = Math.floor(x / cfg.gridStep);
  if (row < 0 || row >= rows || col < 0 || col >= Math.floor(cfg.rowWidth / cfg.gridStep)) return null;
  return { row, col };
}

/** Connector slot nearest to x, within [0, count) */
export function snapConnector(x: number, count: number): number {
  return clamp(Math.round(x / connectorPitch), 0, Math.max(0, count - 1));
}
