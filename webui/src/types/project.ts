// ============================================================================
// DekatronPC Block Place & Route — Core Data Types
// Based on AGENTS.md Section 4 JSON model + DekatronPC wiki physical constraints
// ============================================================================

// ---------------------------------------------------------------------------
// Liberty (.lib) types
// ---------------------------------------------------------------------------

export type PinDirection = 'input' | 'output' | 'inout' | 'internal';

export interface LibertyPin {
  name: string;
  direction: PinDirection;
  function?: string;
  driverType?: string;
  fanoutLoad?: number;
  maxFanout?: number;
  isClock?: boolean;
}

export interface LibertyCell {
  name: string;
  pins: LibertyPin[];
  area?: number;
  heatCurrent?: number;
  currentUnit?: string;
  tubes?: Record<string, number>;
  isFlipFlop?: boolean;
  isLatch?: boolean;
}

// ---------------------------------------------------------------------------
// User-defined elements (not in Liberty)
// ---------------------------------------------------------------------------

export type ElementPinType = 'signal' | 'power' | 'ground' | 'clock';

export interface ElementPin {
  name: string;
  direction: PinDirection;
  type: ElementPinType;
}

export interface ExternalElement {
  name: string;
  description?: string;
  pins: ElementPin[];
}

// ---------------------------------------------------------------------------
// Unified cell type registry entry
// ---------------------------------------------------------------------------

export type CellSource = 'liberty' | 'external';

export interface CellType {
  name: string;
  source: CellSource;
  pins: ElementPin[];
}

// ---------------------------------------------------------------------------
// Connector / Module types
// ---------------------------------------------------------------------------

/** Physical connector contact: A1..A36 on left, B1..B36 on right */
export interface ConnectorContact {
  id: string;          // e.g. "A1", "B12"
  side: 'A' | 'B';
  index: number;       // 1-36
}

/** Mapping from a slot pin name to a physical connector contact */
export interface PinMapping {
  cellPin: string;
  contactId: string;   // "A1" .. "A36", "B1" .. "B36"
}

/**
 * A logical slot on a module type: `count` copies of one cell type.
 * Every copy has its own contacts, so `pinMaps[i]` is the mapping of copy i
 * (length == count; a copy without contacts yet has an empty array).
 */
export interface ModuleSlot {
  cellType: string;          // references CellType.name
  count: number;
  pinMaps: PinMapping[][];
}

/** A PCB design (140×140 mm, 2×36 connector). Shared by all blocks; placed as ModuleInstance. */
export interface ModuleType {
  id: string;
  name: string;
  /** Width in 12 mm grid steps: 2 = 24 mm (logic), 3 = 36 mm (dekatron) */
  widthSteps: number;
  slots: ModuleSlot[];
  powerW?: number;
}

// ---------------------------------------------------------------------------
// Block geometry (top view of the chassis)
// ---------------------------------------------------------------------------

export interface Obstruction {
  type: 'rect' | 'polygon';
  // For rect:
  x?: number;
  y?: number;
  w?: number;
  h?: number;
  // For polygon:
  points?: { x: number; y: number }[];
}

/**
 * Chassis seen from the top: `rows` rows stacked vertically, each `rowHeight` mm
 * (module depth) and `rowWidth` mm wide. A transformer of `transformerWidth` mm
 * sits in the middle of every row. Overall height = rowHeight × rows.
 */
export interface BlockConfig {
  rows: number;              // 3..5
  rowHeight: number;         // mm, 140
  rowWidth: number;          // mm, 420 (19" class)
  gridStep: number;          // mm, horizontal grid (12)
  transformerWidth: number;  // mm, 70..100
  obstructions: Obstruction[];
}

export const ROWS_MIN = 3;
export const ROWS_MAX = 5;
export const TRANSFORMER_WIDTH_MIN = 70;
export const TRANSFORMER_WIDTH_MAX = 100;

// ---------------------------------------------------------------------------
// Netlist types (Verilog)
// ---------------------------------------------------------------------------

export interface NetlistInstance {
  name: string;         // e.g. "U1", "U2"
  cellType: string;     // e.g. "AND2", "DECATRON_CELL"
  connections: Record<string, string>; // port → net name
}

export interface NetlistNet {
  name: string;
  /** Instance+port pairs connected to this net */
  terminals: { instance: string; port: string }[];
}

export interface ParsedNetlist {
  instances: NetlistInstance[];
  nets: NetlistNet[];
}

// ---------------------------------------------------------------------------
// Placement types
// ---------------------------------------------------------------------------

/** A placed copy of a ModuleType in one block */
export interface ModuleInstance {
  id: string;           // unique within the block, e.g. "M3"
  typeId: string;       // ModuleType.id
  row: number;          // 0-based row index
  col: number;          // 0-based column in 12 mm steps
  locked: boolean;
}

/** Placement of a netlist instance into a slot of a placed module */
export interface ElementPlacement {
  instanceName: string;
  moduleInstanceId: string;
  /** Flat slot index over the type's slots: copies of slots[0], then slots[1], ... */
  slotIndex: number;
  locked: boolean;
}

// ---------------------------------------------------------------------------
// Routing types
// ---------------------------------------------------------------------------

export interface TerminalPoint {
  moduleInstanceId: string;
  pin: string;          // connector contact id like "A12", "B5"
}

export interface RouteSegment {
  id: string;
  start: TerminalPoint;
  end: TerminalPoint;
  /** Ordered waypoints (x,y in mm) including start and end */
  path: { x: number; y: number }[];
  assembled: boolean;   // marked as physically wired
}

export interface RoutedNet {
  netName: string;
  color: string;        // hex color
  segments: RouteSegment[];
}

// ---------------------------------------------------------------------------
// Verilog Parse Result
// ---------------------------------------------------------------------------

export interface VerilogModule {
  name: string;
  wires: string[];
  instances: NetlistInstance[];
}

// ---------------------------------------------------------------------------
// Project meta
// ---------------------------------------------------------------------------

export interface ProjectMeta {
  projectName: string;
  createdAt: string;
  updatedAt: string;
  version: string;      // project format version
}

// ---------------------------------------------------------------------------
// Block — a computational unit with its own netlist, placement and routing
// ---------------------------------------------------------------------------

export interface Block {
  name: string;
  netlist: ParsedNetlist;
  placement: {
    modules: ModuleInstance[];
    elements: ElementPlacement[];
  };
  routing: {
    nets: RoutedNet[];
  };
}

export function createDefaultBlock(name: string): Block {
  return {
    name,
    netlist: { instances: [], nets: [] },
    placement: { modules: [], elements: [] },
    routing: { nets: [] },
  };
}

// ---------------------------------------------------------------------------
// Top-level Project State
// ---------------------------------------------------------------------------

export interface ProjectState {
  meta: ProjectMeta;
  liberty: Record<string, LibertyCell>;
  externalElements: Record<string, ExternalElement>;
  moduleTypes: ModuleType[];
  block: BlockConfig;
  /** Multiple computational blocks sharing the same liberty/modules/chassis */
  blocks: Record<string, Block>;
}

// ---------------------------------------------------------------------------
// Default values
// ---------------------------------------------------------------------------

export const PROJECT_FORMAT_VERSION = '0.3.0';

export const DEFAULT_BLOCK_CONFIG: BlockConfig = {
  rows: 3,
  rowHeight: 140,
  rowWidth: 420,
  gridStep: 12,
  transformerWidth: 85,
  obstructions: [],
};

export function createDefaultProject(name: string = 'New Project'): ProjectState {
  const now = new Date().toISOString();
  return {
    meta: {
      projectName: name,
      createdAt: now,
      updatedAt: now,
      version: PROJECT_FORMAT_VERSION,
    },
    liberty: {},
    externalElements: {},
    moduleTypes: [],
    block: { ...DEFAULT_BLOCK_CONFIG, obstructions: [] },
    blocks: {},
  };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

export function getCellPins(
  state: ProjectState,
  cellType: string,
): ElementPin[] | null {
  const lib = state.liberty[cellType];
  if (lib) {
    return lib.pins.map(p => ({
      name: p.name,
      direction: p.direction,
      type: 'signal' as const,
    }));
  }
  const ext = state.externalElements[cellType];
  if (ext) {
    return ext.pins;
  }
  return null;
}

export function getAllCellTypes(state: ProjectState): CellType[] {
  const result: CellType[] = [];
  for (const [name, cell] of Object.entries(state.liberty)) {
    result.push({
      name,
      source: 'liberty',
      pins: cell.pins.map(p => ({ name: p.name, direction: p.direction, type: 'signal' as const })),
    });
  }
  for (const [name, el] of Object.entries(state.externalElements)) {
    result.push({ name, source: 'external', pins: el.pins });
  }
  return result;
}

/** The data fields of a ProjectState — use to strip UI/history state from a store. */
export function pickProjectState(s: ProjectState): ProjectState {
  const { meta, liberty, externalElements, moduleTypes, block, blocks } = s;
  return { meta, liberty, externalElements, moduleTypes, block, blocks };
}

// ---------------------------------------------------------------------------
// Geometry helpers
// ---------------------------------------------------------------------------

/** Overall chassis height in mm */
export function blockHeight(cfg: BlockConfig): number {
  return cfg.rowHeight * cfg.rows;
}

/** Number of 12 mm columns in a row */
export function columnsPerRow(cfg: BlockConfig): number {
  return Math.floor(cfg.rowWidth / cfg.gridStep);
}

/** Transformer keep-out of every row, [x0, x1) in mm, centred */
export function transformerSpan(cfg: BlockConfig): [number, number] {
  const x0 = (cfg.rowWidth - cfg.transformerWidth) / 2;
  return [x0, x0 + cfg.transformerWidth];
}

/**
 * Can a module of `widthSteps` sit at `col` without leaving the row or
 * overlapping the transformer? (Overlap with other modules is checked by the caller.)
 */
export function fitsInRow(cfg: BlockConfig, col: number, widthSteps: number): boolean {
  if (col < 0 || widthSteps < 1) return false;
  const x0 = col * cfg.gridStep;
  const x1 = x0 + widthSteps * cfg.gridStep;
  if (x1 > cfg.rowWidth) return false;
  const [t0, t1] = transformerSpan(cfg);
  return x1 <= t0 || x0 >= t1;
}

/** Total number of cell slots on a module type */
export function slotCount(type: ModuleType): number {
  return type.slots.reduce((n, s) => n + s.count, 0);
}

/** Map a flat slot index to (slot definition, copy); null when out of range */
export function resolveSlot(
  type: ModuleType,
  slotIndex: number,
): { slotDefIndex: number; copy: number } | null {
  if (slotIndex < 0) return null;
  let base = 0;
  for (let i = 0; i < type.slots.length; i++) {
    const n = type.slots[i].count;
    if (slotIndex < base + n) return { slotDefIndex: i, copy: slotIndex - base };
    base += n;
  }
  return null;
}
