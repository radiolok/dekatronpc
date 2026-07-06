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
}

export interface LibertyCell {
  name: string;
  pins: LibertyPin[];
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

/** A logical slot on a module: type + count + pin mappings */
export interface ModuleSlot {
  cellType: string;          // references CellType.name
  count: number;             // how many instances of this type fit
  pinMapping: PinMapping[];  // maps logical cell pins → connector contacts
}

/** A hardware module (PCB 140×140mm) */
export interface HardwareModule {
  id: string;
  name: string;
  /** Width in 12mm grid steps: 2 = 24mm (logic), 3 = 36mm (dekatron) */
  widthSteps: number;
  slots: ModuleSlot[];
  /** Filled during placement: one entry per instance */
  slotInstances: SlotInstance[];
}

// ---------------------------------------------------------------------------
// Block geometry
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

export interface BlockConfig {
  rows: number;              // 3 (per wiki: IpLine, ApLine, MachineCtrl)
  maxCols: number;           // max positions in a row (24)
  verticalPitch: number;     // mm, distance between module centers vertically
  gridStep: number;          // mm, horizontal grid (12)
  margin: number;            // mm, edge margin inside block
  /** Physical block dimensions in mm (4U chassis: 920×420×178) */
  chassisWidth: number;      // 920
  chassisHeight: number;     // 420 (effective)
  obstructions: Obstruction[];
}

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

/** Position of a module in the block grid */
export interface ModulePlacement {
  moduleId: string;
  row: number;          // 0-based row index
  col: number;          // 0-based column in 12mm steps
  locked: boolean;
}

/** Placement of a netlist instance into a module slot */
export interface ElementPlacement {
  instanceName: string;
  moduleId: string;
  slotIndex: number;    // index into module.slotInstances
  locked: boolean;
}

// ---------------------------------------------------------------------------
// Routing types
// ---------------------------------------------------------------------------

export interface TerminalPoint {
  moduleId: string;
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
// Sub-placement data — for elements inside module slots
// ---------------------------------------------------------------------------

export interface SlotInstance {
  /** Index into parent module's slotInstances array */
  index: number;
  /** Which slot definition this belongs to (index into module.slots) */
  slotDefIndex: number;
  /** The netlist instance occupying this slot (null = empty) */
  instanceName: string | null;
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
// Top-level Project State
// ---------------------------------------------------------------------------

export interface ProjectState {
  meta: ProjectMeta;
  liberty: Record<string, LibertyCell>;
  externalElements: Record<string, ExternalElement>;
  modules: HardwareModule[];
  block: BlockConfig;
  netlist: ParsedNetlist;
  placement: {
    modules: ModulePlacement[];
    elements: ElementPlacement[];
  };
  routing: {
    nets: RoutedNet[];
  };
}

// ---------------------------------------------------------------------------
// Default values
// ---------------------------------------------------------------------------

export const DEFAULT_BLOCK_CONFIG: BlockConfig = {
  rows: 3,
  maxCols: 24,
  verticalPitch: 178 / 3,   // ~59.3mm between module centers
  gridStep: 12,             // 12mm horizontal grid
  margin: 20,
  chassisWidth: 920,
  chassisHeight: 420,
  obstructions: [],
};

export function createDefaultProject(name: string = 'New Project'): ProjectState {
  const now = new Date().toISOString();
  return {
    meta: {
      projectName: name,
      createdAt: now,
      updatedAt: now,
      version: '0.1.0',
    },
    liberty: {},
    externalElements: {},
    modules: [],
    block: { ...DEFAULT_BLOCK_CONFIG },
    netlist: { instances: [], nets: [] },
    placement: {
      modules: [],
      elements: [],
    },
    routing: {
      nets: [],
    },
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
