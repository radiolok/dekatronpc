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

/**
 * `board`: an ordinary module, wired by hand.
 * `interconnect`: a small board that links a group of neighbouring modules
 * (dekatron + write + read circuits); its connections are not routed (Q10).
 */
export type ModuleKind = 'board' | 'interconnect';

/** A PCB design (140×140 mm, 2×36 connector). Shared by all blocks; placed as ModuleInstance. */
export interface ModuleType {
  id: string;
  name: string;
  kind: ModuleKind;
  /** Width in 12 mm grid steps: 2 = 24 mm (logic), 3 = 36 mm (dekatron) */
  widthSteps: number;
  slots: ModuleSlot[];
  /**
   * Base name of the Verilog module this board implements ("DekatronModule").
   * Such submodules are kept whole when a netlist is parsed (Q3, Q7).
   */
  verilogModule?: string;
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
 * Basket geometry shared by all blocks, seen from the top. Each block stacks
 * `Block.rows` rows vertically, each `rowHeight` mm (module depth) and
 * `rowWidth` mm wide. A transformer of `transformerWidth` mm sits in the middle
 * of every row. Block height = rowHeight × rows.
 */
export interface BlockConfig {
  rowHeight: number;         // mm, 140
  rowWidth: number;          // mm, 420 (19" class)
  gridStep: number;          // mm, horizontal grid (12)
  /** mm, 72 + gridStep·K (Q4), at most TRANSFORMER_WIDTH_MAX */
  transformerWidth: number;
  obstructions: Obstruction[];
}

export const ROWS_MIN = 3;
export const ROWS_MAX = 5;
export const ROWS_DEFAULT = 3;
export const TRANSFORMER_WIDTH_MIN = 72;
export const TRANSFORMER_WIDTH_MAX = 100;

// ---------------------------------------------------------------------------
// Block connectors and cables (Q1, Q9)
// ---------------------------------------------------------------------------

export type ConnectorType = 'HD68';

export const CONNECTOR_PINS: Record<ConnectorType, number> = { HD68: 68 };

/** Which block port bit sits on which connector pin */
export interface ConnectorPinAssignment {
  pin: number;    // 1..pins
  port: string;   // NetlistPort.name, e.g. "insn[3]"
}

/** A cable connector of a block, in the row above the baskets */
export interface BlockConnector {
  id: string;         // unique within the block, "J1"
  type: ConnectorType;
  pins: number;       // 68 for HD68
  /** 0-based place in the connector row, left to right */
  position: number;
  ports: ConnectorPinAssignment[];
}

export interface CableEnd {
  block: string;
  connector: string;
}

/** A straight-through cable: pin n of one end goes to pin n of the other */
export interface Cable {
  id: string;
  from: CableEnd;
  to: CableEnd;
}

// ---------------------------------------------------------------------------
// Netlist types (Verilog)
// ---------------------------------------------------------------------------

export interface NetlistInstance {
  /** Hierarchical path, '/'-separated: "ipCounter/dek[0].dModule/guideEnA" */
  name: string;
  /** Liberty cell or base module name ("NAND2_J2", "DekatronModule") */
  cellType: string;
  /** Full Verilog module name when it differs (Yosys "$paramod…" variants) */
  module?: string;
  /** Pin bit ("A", "In[2]") → net name, or a constant such as "1'b0" */
  connections: Record<string, string>;
}

export interface NetlistNet {
  name: string;
  /** Instance+port pairs connected to this net */
  terminals: { instance: string; port: string }[];
}

/** One bit of a top-level port of the block */
export interface NetlistPort {
  name: string;          // "insn[3]", "clk"
  direction: PinDirection;
  /** Net name, or a constant such as "1'b0" */
  net: string;
}

/**
 * Leaf instances and bit-level nets of one block. Submodules are expanded
 * unless they are black boxes or listed in `keep` (see services/parsers/verilog.ts).
 */
export interface ParsedNetlist {
  instances: NetlistInstance[];
  nets: NetlistNet[];
  /** Top module the netlist was elaborated from */
  top?: string;
  /** Module names kept as single instances when elaborating */
  keep?: string[];
  /** Top-level port bits */
  ports?: NetlistPort[];
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

/** End of a wire on a module contact */
export interface ModuleTerminal {
  moduleInstanceId: string;
  pin: string;          // connector contact id like "A12", "B5"
}

/** End of a wire on a pin of a block connector (HD-68) */
export interface ConnectorTerminal {
  connectorId: string;
  pin: number;          // 1..68
}

export type TerminalPoint = ModuleTerminal | ConnectorTerminal;

export function isConnectorTerminal(t: TerminalPoint): t is ConnectorTerminal {
  return 'connectorId' in t;
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
  /** Baskets in this block, ROWS_MIN..ROWS_MAX */
  rows: number;
  netlist: ParsedNetlist;
  /** Cable connectors above the baskets */
  connectors: BlockConnector[];
  /** Nets carried by the basket backplane, not wired by hand (Q10). Survives re-parsing. */
  powerNets: string[];
  placement: {
    modules: ModuleInstance[];
    elements: ElementPlacement[];
  };
  routing: {
    nets: RoutedNet[];
  };
}

export function createDefaultBlock(name: string, rows: number = ROWS_DEFAULT): Block {
  return {
    name,
    rows,
    netlist: { instances: [], nets: [] },
    connectors: [],
    powerNets: [],
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
  /** Cables between connectors of different blocks */
  cables: Cable[];
}

// ---------------------------------------------------------------------------
// Default values
// ---------------------------------------------------------------------------

export const PROJECT_FORMAT_VERSION = '0.4.0';

export const DEFAULT_BLOCK_CONFIG: BlockConfig = {
  rowHeight: 140,
  rowWidth: 420,
  gridStep: 12,
  transformerWidth: 84,
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
    cables: [],
  };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

export function getCellPins(
  state: Pick<ProjectState, 'liberty' | 'externalElements'>,
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

export function getAllCellTypes(state: Pick<ProjectState, 'liberty' | 'externalElements'>): CellType[] {
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
  const { meta, liberty, externalElements, moduleTypes, block, blocks, cables } = s;
  return { meta, liberty, externalElements, moduleTypes, block, blocks, cables };
}

// ---------------------------------------------------------------------------
// Geometry helpers
// ---------------------------------------------------------------------------

/** Height of a block's baskets in mm */
export function blockHeight(cfg: BlockConfig, rows: number): number {
  return cfg.rowHeight * rows;
}

/** Nearest allowed transformer width: 72 + gridStep·K mm, within the limits (Q4) */
export function snapTransformerWidth(mm: number, gridStep: number): number {
  const k = Math.max(0, Math.round((mm - TRANSFORMER_WIDTH_MIN) / gridStep));
  const maxK = Math.floor((TRANSFORMER_WIDTH_MAX - TRANSFORMER_WIDTH_MIN) / gridStep);
  return TRANSFORMER_WIDTH_MIN + Math.min(k, maxK) * gridStep;
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

/**
 * Is [col, col+width) in `row` free: inside the row, clear of the transformer
 * and of other module instances (except `ignoreId`)?
 */
export function canPlaceModule(
  state: Pick<ProjectState, 'block' | 'moduleTypes'>,
  rows: number,
  instances: ModuleInstance[],
  typeId: string,
  row: number,
  col: number,
  ignoreId?: string,
): boolean {
  const type = state.moduleTypes.find(t => t.id === typeId);
  if (!type) return false;
  if (!Number.isInteger(row) || !Number.isInteger(col)) return false;
  if (row < 0 || row >= rows) return false;
  if (!fitsInRow(state.block, col, type.widthSteps)) return false;
  const end = col + type.widthSteps;
  for (const other of instances) {
    if (other.id === ignoreId || other.row !== row) continue;
    const ot = state.moduleTypes.find(t => t.id === other.typeId);
    const oEnd = other.col + (ot?.widthSteps ?? 1);
    if (col < oEnd && other.col < end) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Module connector (2×36 edge connector)
// ---------------------------------------------------------------------------

export const CONTACTS_PER_SIDE = 36;

/** All edge-connector contacts in order: A1..A36, then B1..B36 */
export const CONTACT_IDS: string[] = (['A', 'B'] as const).flatMap(side =>
  Array.from({ length: CONTACTS_PER_SIDE }, (_, i) => `${side}${i + 1}`));

const CONTACT_SET = new Set(CONTACT_IDS);

export function isContactId(id: string): boolean {
  return CONTACT_SET.has(id);
}

/** One cell pin on a contact */
export interface ContactUse {
  slotDefIndex: number;
  copy: number;
  cellPin: string;
}

/** Contact id → the cell pins mapped onto it (more than one is a clash, unless meant) */
export function contactUsage(type: ModuleType): Map<string, ContactUse[]> {
  const usage = new Map<string, ContactUse[]>();
  type.slots.forEach((slot, slotDefIndex) => {
    slot.pinMaps.forEach((map, copy) => {
      for (const m of map) {
        const list = usage.get(m.contactId) ?? [];
        list.push({ slotDefIndex, copy, cellPin: m.cellPin });
        usage.set(m.contactId, list);
      }
    });
  });
  return usage;
}

/** Tubes a module type carries, from the liberty `tubes` groups: { N16B: 2, X7B: 4 } */
export function moduleTubes(
  type: ModuleType,
  liberty: Record<string, LibertyCell>,
): Record<string, number> {
  const out: Record<string, number> = {};
  for (const slot of type.slots) {
    for (const [tube, n] of Object.entries(liberty[slot.cellType]?.tubes ?? {})) {
      out[tube] = (out[tube] ?? 0) + n * slot.count;
    }
  }
  return out;
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
