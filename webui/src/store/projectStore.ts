// ============================================================================
// Zustand store with undo/redo support via Immer
// ============================================================================

import { create, type StateCreator } from 'zustand';
import { immer } from 'zustand/middleware/immer';
import type {
  ProjectState,
  Block,
  BlockConfig,
  ModuleType,
  ModuleSlot,
  ModuleInstance,
  ElementPlacement,
  ExternalElement,
  LibertyCell,
  ParsedNetlist,
  PinMapping,
  RoutedNet,
  RouteSegment,
} from '@/types';
import {
  createDefaultBlock,
  createDefaultProject,
  pickProjectState,
  resolveSlot,
  fitsInRow,
  ROWS_MIN,
  ROWS_MAX,
  TRANSFORMER_WIDTH_MIN,
  TRANSFORMER_WIDTH_MAX,
} from '@/types';
import { clamp, stringToColor } from '@/utils/helpers';

// ---------------------------------------------------------------------------
// History / Undo-Redo
// ---------------------------------------------------------------------------

const MAX_HISTORY = 50;

/**
 * A snapshot holds references to the (Immer-frozen) project fields as they were
 * before an edit. Frozen objects are never mutated, so no deep copy is needed.
 */
interface HistoryEntry {
  state: ProjectState;
  label: string;
}

interface HistorySlice {
  past: HistoryEntry[];
  future: HistoryEntry[];
  undo: () => void;
  redo: () => void;
  clearHistory: () => void;
}

// ---------------------------------------------------------------------------
// Action types — all mutations to the project state
// ---------------------------------------------------------------------------

export interface ProjectActions {
  // Project management (not undoable: they reset history)
  newProject: (name: string) => void;
  loadProject: (state: ProjectState) => void;
  /** Not recorded in history: it fires on every keystroke */
  setProjectName: (name: string) => void;

  // Blocks (multi-netlist support)
  addBlock: (name: string) => void;
  removeBlock: (blockId: string) => void;
  setActiveBlock: (blockId: string | null) => void;
  setBlockNetlist: (blockId: string, netlist: ParsedNetlist) => void;

  // Chassis geometry
  setBlockConfig: (cfg: Partial<BlockConfig>) => void;

  // Liberty
  setLiberty: (cells: Record<string, LibertyCell>) => void;
  addLibertyCell: (name: string, cell: LibertyCell) => void;

  // External elements
  addExternalElement: (el: ExternalElement) => void;
  updateExternalElement: (name: string, el: ExternalElement) => void;
  removeExternalElement: (name: string) => void;

  // Module types (shared by all blocks)
  addModuleType: (type: ModuleType) => void;
  updateModuleType: (id: string, patch: Partial<Omit<ModuleType, 'id' | 'slots'>>) => void;
  removeModuleType: (id: string) => void;
  addSlot: (typeId: string, cellType: string, count: number) => void;
  updateSlot: (typeId: string, slotDefIndex: number, patch: { cellType?: string; count?: number }) => void;
  removeSlot: (typeId: string, slotDefIndex: number) => void;
  setSlotPinMap: (typeId: string, slotDefIndex: number, copy: number, map: PinMapping[]) => void;

  // Module instances (active block). Invalid positions are ignored.
  /** Returns the new instance id, or null if the position is not free */
  addModuleInstance: (typeId: string, row: number, col: number) => string | null;
  moveModuleInstance: (id: string, row: number, col: number) => void;
  lockModuleInstance: (id: string, locked: boolean) => void;
  removeModuleInstance: (id: string) => void;

  // Element placement (active block). Invalid placements are ignored.
  placeElement: (placement: ElementPlacement) => void;
  lockElement: (instanceName: string, locked: boolean) => void;
  removeElementPlacement: (instanceName: string) => void;

  // Routing (active block)
  setRoutedNets: (nets: RoutedNet[]) => void;
  addRoutedNet: (net: RoutedNet) => void;
  updateRoutedNet: (netName: string, updates: Partial<RoutedNet>) => void;
  addRouteSegment: (netName: string, segment: RouteSegment) => void;
  updateRouteSegment: (netName: string, segmentId: string, updates: Partial<RouteSegment>) => void;
  removeRouteSegment: (netName: string, segmentId: string) => void;
  markSegmentAssembled: (netName: string, segmentId: string, assembled: boolean) => void;
}

// ---------------------------------------------------------------------------
// Combined store type
// ---------------------------------------------------------------------------

export type ProjectStore = ProjectState & HistorySlice & ProjectActions & {
  /** Currently selected block — UI state, not part of history snapshots */
  activeBlockId: string | null;
};

type SetFn = (fn: (state: ProjectStore) => void) => void;
type GetFn = () => ProjectStore;

// ---------------------------------------------------------------------------
// Pure helpers (operate on drafts or plain state)
// ---------------------------------------------------------------------------

function projectChanged(a: ProjectState, b: ProjectState): boolean {
  return a.meta !== b.meta || a.liberty !== b.liberty
    || a.externalElements !== b.externalElements || a.moduleTypes !== b.moduleTypes
    || a.block !== b.block || a.blocks !== b.blocks;
}

/** Keep activeBlockId pointing at an existing block */
function fixActiveBlock(s: ProjectStore): void {
  if (s.activeBlockId && s.blocks[s.activeBlockId]) return;
  s.activeBlockId = Object.keys(s.blocks).sort()[0] ?? null;
}

/** Cell type of every netlist instance of a block */
function instanceCellType(b: Block, instanceName: string): string | undefined {
  return b.netlist.instances.find(i => i.name === instanceName)?.cellType;
}

/**
 * Is [col, col+width) in `row` free: inside the row, clear of the transformer
 * and of other module instances (except `ignoreId`)?
 */
export function canPlaceModule(
  state: Pick<ProjectState, 'block' | 'moduleTypes'>,
  instances: ModuleInstance[],
  typeId: string,
  row: number,
  col: number,
  ignoreId?: string,
): boolean {
  const type = state.moduleTypes.find(t => t.id === typeId);
  if (!type) return false;
  if (!Number.isInteger(row) || !Number.isInteger(col)) return false;
  if (row < 0 || row >= state.block.rows) return false;
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

/**
 * Drop element placements that no longer point at a matching slot:
 * missing module instance, slot index out of range, or cell type mismatch.
 * Needed after slot definitions or module types change.
 */
function pruneElementPlacements(s: ProjectStore): void {
  for (const b of Object.values(s.blocks)) {
    b.placement.elements = b.placement.elements.filter(e => {
      const inst = b.placement.modules.find(m => m.id === e.moduleInstanceId);
      const type = inst && s.moduleTypes.find(t => t.id === inst.typeId);
      const ref = type && resolveSlot(type, e.slotIndex);
      if (!type || !ref) return false;
      return type.slots[ref.slotDefIndex].cellType === instanceCellType(b, e.instanceName);
    });
  }
}

/** Drop route segments that end on a module instance that no longer exists */
function pruneRouting(b: Block): void {
  const ids = new Set(b.placement.modules.map(m => m.id));
  for (const net of b.routing.nets) {
    net.segments = net.segments.filter(
      g => ids.has(g.start.moduleInstanceId) && ids.has(g.end.moduleInstanceId),
    );
  }
  b.routing.nets = b.routing.nets.filter(n => n.segments.length > 0);
}

function nextInstanceId(b: Block): string {
  let n = 1;
  const used = new Set(b.placement.modules.map(m => m.id));
  while (used.has(`M${n}`)) n++;
  return `M${n}`;
}

function resizePinMaps(slot: ModuleSlot, count: number): void {
  slot.pinMaps = Array.from({ length: count }, (_, i) => slot.pinMaps[i] ?? []);
}

// ---------------------------------------------------------------------------
// Store creator
// ---------------------------------------------------------------------------

function createProjectSlice(set: SetFn, get: GetFn): ProjectActions {
  /**
   * Apply an undoable edit. A history entry is recorded only if the project
   * data actually changed, so rejected or no-op edits leave history intact.
   */
  const edit = (label: string, fn: (s: ProjectStore) => void): void => {
    const before = get();
    set(fn);
    if (!projectChanged(before, get())) return;
    const snapshot = pickProjectState(before);
    set((s) => {
      s.past.push({ state: snapshot, label });
      if (s.past.length > MAX_HISTORY) s.past.shift();
      s.future = [];
    });
  };

  /** Undoable edit of the active block; no-op without one */
  const editBlock = (label: string, fn: (b: Block, s: ProjectStore) => void): void => {
    edit(label, (s) => {
      const b = s.activeBlockId ? s.blocks[s.activeBlockId] : undefined;
      if (b) fn(b, s);
    });
  };

  const findSegment = (b: Block, netName: string, segmentId: string) =>
    b.routing.nets.find(n => n.netName === netName)?.segments.find(g => g.id === segmentId);

  return {
    // --- Project management ---
    newProject: (name) => {
      set((s) => {
        Object.assign(s, createDefaultProject(name));
        s.activeBlockId = null;
        s.past = [];
        s.future = [];
      });
    },

    loadProject: (state) => {
      set((s) => {
        Object.assign(s, pickProjectState(state));
        s.activeBlockId = null;
        fixActiveBlock(s);
        s.past = [];
        s.future = [];
      });
    },

    setProjectName: (name) => {
      set((s) => { s.meta.projectName = name; });
    },

    // --- Blocks ---
    addBlock: (name) => {
      edit(`Add block: ${name}`, (s) => {
        if (!s.blocks[name]) s.blocks[name] = createDefaultBlock(name);
        s.activeBlockId = name;
      });
    },

    removeBlock: (blockId) => {
      edit(`Remove block: ${blockId}`, (s) => {
        delete s.blocks[blockId];
        fixActiveBlock(s);
      });
    },

    setActiveBlock: (blockId) => {
      set((s) => { s.activeBlockId = blockId && s.blocks[blockId] ? blockId : null; });
    },

    setBlockNetlist: (blockId, netlist) => {
      edit(`Set netlist for block: ${blockId}`, (s) => {
        if (!s.blocks[blockId]) s.blocks[blockId] = createDefaultBlock(blockId);
        s.blocks[blockId].netlist = netlist;
        s.activeBlockId = blockId;
        pruneElementPlacements(s);
      });
    },

    // --- Chassis geometry ---
    setBlockConfig: (cfg) => {
      edit('Change chassis geometry', (s) => {
        const next = { ...s.block, ...cfg };
        // Never drop a row that still holds modules
        const usedRows = Math.max(0, ...Object.values(s.blocks)
          .flatMap(b => b.placement.modules.map(m => m.row + 1)));
        next.rows = clamp(Math.round(next.rows), Math.max(ROWS_MIN, usedRows), ROWS_MAX);
        next.transformerWidth = clamp(next.transformerWidth, TRANSFORMER_WIDTH_MIN, TRANSFORMER_WIDTH_MAX);
        Object.assign(s.block, next);
      });
    },

    // --- Liberty ---
    setLiberty: (cells) => {
      edit('Set liberty cells', (s) => { s.liberty = cells; });
    },

    addLibertyCell: (name, cell) => {
      edit(`Add liberty cell: ${name}`, (s) => { s.liberty[name] = cell; });
    },

    // --- External elements ---
    addExternalElement: (el) => {
      edit(`Add element: ${el.name}`, (s) => { s.externalElements[el.name] = el; });
    },

    updateExternalElement: (name, el) => {
      edit(`Update element: ${name}`, (s) => {
        if (name !== el.name) delete s.externalElements[name];
        s.externalElements[el.name] = el;
      });
    },

    removeExternalElement: (name) => {
      edit(`Remove element: ${name}`, (s) => { delete s.externalElements[name]; });
    },

    // --- Module types ---
    addModuleType: (type) => {
      edit(`Add module type: ${type.name}`, (s) => {
        if (s.moduleTypes.some(t => t.id === type.id)) return;
        s.moduleTypes.push(type);
      });
    },

    updateModuleType: (id, patch) => {
      edit('Update module type', (s) => {
        const t = s.moduleTypes.find(m => m.id === id);
        if (t) Object.assign(t, patch);
      });
    },

    removeModuleType: (id) => {
      edit('Remove module type', (s) => {
        s.moduleTypes = s.moduleTypes.filter(t => t.id !== id);
        for (const b of Object.values(s.blocks)) {
          b.placement.modules = b.placement.modules.filter(m => m.typeId !== id);
          pruneRouting(b);
        }
        pruneElementPlacements(s);
      });
    },

    addSlot: (typeId, cellType, count) => {
      edit('Add slot', (s) => {
        const t = s.moduleTypes.find(m => m.id === typeId);
        if (!t || count < 1) return;
        t.slots.push({ cellType, count, pinMaps: Array.from({ length: count }, () => []) });
      });
    },

    updateSlot: (typeId, slotDefIndex, patch) => {
      edit('Update slot', (s) => {
        const slot = s.moduleTypes.find(m => m.id === typeId)?.slots[slotDefIndex];
        if (!slot) return;
        if (patch.cellType !== undefined && patch.cellType !== slot.cellType) {
          slot.cellType = patch.cellType;
          slot.pinMaps = slot.pinMaps.map(() => []); // pin names changed
        }
        if (patch.count !== undefined && patch.count >= 1 && patch.count !== slot.count) {
          slot.count = patch.count;
          resizePinMaps(slot, patch.count);
        }
        pruneElementPlacements(s);
      });
    },

    removeSlot: (typeId, slotDefIndex) => {
      edit('Remove slot', (s) => {
        const t = s.moduleTypes.find(m => m.id === typeId);
        if (!t || !t.slots[slotDefIndex]) return;
        t.slots.splice(slotDefIndex, 1);
        pruneElementPlacements(s);
      });
    },

    setSlotPinMap: (typeId, slotDefIndex, copy, map) => {
      edit('Edit pin map', (s) => {
        const slot = s.moduleTypes.find(m => m.id === typeId)?.slots[slotDefIndex];
        if (slot && copy >= 0 && copy < slot.count) slot.pinMaps[copy] = map;
      });
    },

    // --- Module instances (active block) ---
    addModuleInstance: (typeId, row, col) => {
      const s0 = get();
      const b0 = s0.activeBlockId ? s0.blocks[s0.activeBlockId] : undefined;
      if (!b0 || !canPlaceModule(s0, b0.placement.modules, typeId, row, col)) return null;
      const id = nextInstanceId(b0);
      editBlock(`Place module ${id}`, (b) => {
        b.placement.modules.push({ id, typeId, row, col, locked: false });
      });
      return id;
    },

    moveModuleInstance: (id, row, col) => {
      editBlock(`Move module ${id}`, (b, s) => {
        const m = b.placement.modules.find(x => x.id === id);
        if (!m || m.locked || (m.row === row && m.col === col)) return;
        if (!canPlaceModule(s, b.placement.modules, m.typeId, row, col, id)) return;
        m.row = row;
        m.col = col;
      });
    },

    lockModuleInstance: (id, locked) => {
      editBlock(`${locked ? 'Lock' : 'Unlock'} module ${id}`, (b) => {
        const m = b.placement.modules.find(x => x.id === id);
        if (m) m.locked = locked;
      });
    },

    removeModuleInstance: (id) => {
      editBlock(`Remove module ${id}`, (b) => {
        b.placement.modules = b.placement.modules.filter(m => m.id !== id);
        b.placement.elements = b.placement.elements.filter(e => e.moduleInstanceId !== id);
        pruneRouting(b);
      });
    },

    // --- Element placement (active block) ---
    placeElement: (placement) => {
      editBlock(`Place element: ${placement.instanceName}`, (b, s) => {
        const cellType = instanceCellType(b, placement.instanceName);
        const inst = b.placement.modules.find(m => m.id === placement.moduleInstanceId);
        const type = inst && s.moduleTypes.find(t => t.id === inst.typeId);
        const ref = type && resolveSlot(type, placement.slotIndex);
        if (!cellType || !type || !ref || type.slots[ref.slotDefIndex].cellType !== cellType) return;
        const occupant = b.placement.elements.find(e =>
          e.moduleInstanceId === placement.moduleInstanceId
          && e.slotIndex === placement.slotIndex
          && e.instanceName !== placement.instanceName);
        if (occupant) return;
        const idx = b.placement.elements.findIndex(e => e.instanceName === placement.instanceName);
        if (idx !== -1) {
          if (b.placement.elements[idx].locked) return;
          b.placement.elements[idx] = placement;
        } else {
          b.placement.elements.push(placement);
        }
      });
    },

    lockElement: (instanceName, locked) => {
      editBlock(`${locked ? 'Lock' : 'Unlock'} element: ${instanceName}`, (b) => {
        const e = b.placement.elements.find(x => x.instanceName === instanceName);
        if (e) e.locked = locked;
      });
    },

    removeElementPlacement: (instanceName) => {
      editBlock(`Unplace element: ${instanceName}`, (b) => {
        b.placement.elements = b.placement.elements.filter(e => e.instanceName !== instanceName);
      });
    },

    // --- Routing (active block) ---
    setRoutedNets: (nets) => {
      editBlock('Set routing', (b) => { b.routing.nets = nets; });
    },

    addRoutedNet: (net) => {
      editBlock(`Add routed net: ${net.netName}`, (b) => {
        if (!b.routing.nets.some(n => n.netName === net.netName)) b.routing.nets.push(net);
      });
    },

    updateRoutedNet: (netName, updates) => {
      editBlock(`Update net: ${netName}`, (b) => {
        const net = b.routing.nets.find(n => n.netName === netName);
        if (net) Object.assign(net, updates);
      });
    },

    addRouteSegment: (netName, segment) => {
      editBlock(`Add wire: ${netName}`, (b) => {
        const net = b.routing.nets.find(n => n.netName === netName);
        if (net) net.segments.push(segment);
        else b.routing.nets.push({ netName, color: stringToColor(netName), segments: [segment] });
      });
    },

    updateRouteSegment: (netName, segmentId, updates) => {
      editBlock(`Edit wire: ${netName}`, (b) => {
        const seg = findSegment(b, netName, segmentId);
        if (seg) Object.assign(seg, updates);
      });
    },

    removeRouteSegment: (netName, segmentId) => {
      editBlock(`Remove wire: ${netName}`, (b) => {
        const net = b.routing.nets.find(n => n.netName === netName);
        if (!net) return;
        net.segments = net.segments.filter(g => g.id !== segmentId);
        if (net.segments.length === 0) {
          b.routing.nets = b.routing.nets.filter(n => n.netName !== netName);
        }
      });
    },

    markSegmentAssembled: (netName, segmentId, assembled) => {
      editBlock(`${assembled ? 'Mark' : 'Unmark'} assembled: ${netName}`, (b) => {
        const seg = findSegment(b, netName, segmentId);
        if (seg) seg.assembled = assembled;
      });
    },
  };
}

// ---------------------------------------------------------------------------
// Store factory with Immer + history
// ---------------------------------------------------------------------------

export function createProjectStore(
  initialState: ProjectState = createDefaultProject(),
) {
  const stateCreator: StateCreator<ProjectStore, [['zustand/immer', never]], []> = (set, get) => {
    const actions = createProjectSlice(set, get);

    /** Move one entry from `from` to `to`, restoring its project snapshot */
    const travel = (from: 'past' | 'future', to: 'past' | 'future') => {
      const s0 = get();
      const entry = s0[from][s0[from].length - 1];
      if (!entry) return;
      const current = pickProjectState(s0);
      set((s) => {
        s[from].pop();
        s[to].push({ state: current, label: entry.label });
        Object.assign(s, entry.state);
        fixActiveBlock(s);
      });
    };

    const historySlice: HistorySlice = {
      past: [],
      future: [],
      undo: () => travel('past', 'future'),
      redo: () => travel('future', 'past'),
      clearHistory: () => {
        set((s) => {
          s.past = [];
          s.future = [];
        });
      },
    };

    return {
      ...pickProjectState(initialState),
      ...actions,
      ...historySlice,
      activeBlockId: null,
    };
  };

  return create<ProjectStore>()(immer(stateCreator));
}

// ---------------------------------------------------------------------------
// Singleton store instance
// ---------------------------------------------------------------------------

export const useProjectStore = createProjectStore();
