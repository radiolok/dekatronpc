// ============================================================================
// Zustand store with undo/redo support via Immer
// ============================================================================

import { create, type StateCreator } from 'zustand';
import { immer } from 'zustand/middleware/immer';
import type {
  ProjectState,
  Block,
  HardwareModule,
  ModuleSlot,
  ModulePlacement,
  ElementPlacement,
  ExternalElement,
  LibertyCell,
  ParsedNetlist,
  RoutedNet,
  RouteSegment,
  SlotInstance,
} from '@/types';
import { createDefaultBlock } from '@/types';

// ---------------------------------------------------------------------------
// History / Undo-Redo
// ---------------------------------------------------------------------------

const MAX_HISTORY = 50;

/** Module-level flag — set during undo/redo to avoid re-recording history */
let _suppressHistory = false;

/** Extract a deep-cloned snapshot of only the ProjectState data fields */
function cloneProjectState(s: ProjectStore): ProjectState {
  const { meta, liberty, externalElements, modules, block, blocks } = s;
  return structuredClone({ meta, liberty, externalElements, modules, block, blocks });
}

interface HistoryEntry {
  state: ProjectState;
  label: string;
}

interface HistorySlice {
  past: HistoryEntry[];
  future: HistoryEntry[];
  pushHistory: (label: string) => void;
  undo: () => void;
  redo: () => void;
  clearHistory: () => void;
}

// ---------------------------------------------------------------------------
// Action types — all mutations to the project state
// ---------------------------------------------------------------------------

export interface ProjectActions {
  // Project management
  newProject: (name: string) => void;
  loadProject: (state: ProjectState) => void;
  setProjectName: (name: string) => void;

  // Blocks (multi-netlist support)
  addBlock: (name: string) => void;
  removeBlock: (blockId: string) => void;
  setActiveBlock: (blockId: string | null) => void;
  setBlockNetlist: (blockId: string, netlist: ParsedNetlist) => void;

  // Liberty
  setLiberty: (cells: Record<string, LibertyCell>) => void;
  addLibertyCell: (name: string, cell: LibertyCell) => void;

  // External elements
  addExternalElement: (el: ExternalElement) => void;
  updateExternalElement: (name: string, el: ExternalElement) => void;
  removeExternalElement: (name: string) => void;

  // Modules
  addModule: (mod: HardwareModule) => void;
  updateModule: (id: string, mod: Partial<HardwareModule>) => void;
  removeModule: (id: string) => void;
  addSlotToModule: (moduleId: string, slot: ModuleSlot) => void;
  updateSlotInModule: (moduleId: string, slotIndex: number, slot: Partial<ModuleSlot>) => void;
  removeSlotFromModule: (moduleId: string, slotIndex: number) => void;

  // Placement — modules (active block)
  setModulePlacements: (placements: ModulePlacement[]) => void;
  placeModule: (placement: ModulePlacement) => void;
  lockModule: (moduleId: string, locked: boolean) => void;
  removeModulePlacement: (moduleId: string) => void;

  // Placement — elements (active block)
  setElementPlacements: (placements: ElementPlacement[]) => void;
  placeElement: (placement: ElementPlacement) => void;
  lockElement: (instanceName: string, locked: boolean) => void;
  removeElementPlacement: (instanceName: string) => void;

  // Slot instances
  setSlotInstance: (moduleId: string, slotIndex: number, instanceName: string | null) => void;

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

// ---------------------------------------------------------------------------
// Store creator
// ---------------------------------------------------------------------------

import { createDefaultProject } from '@/types';

function createProjectSlice(
  set: (fn: (state: ProjectStore) => void) => void,
): ProjectActions {
  return {
    // --- Project management ---
    newProject: (name: string) => {
      set((s) => {
        const fresh = createDefaultProject(name);
        Object.assign(s, fresh);
        s.activeBlockId = null;
        s.past = [];
        s.future = [];
        s.pushHistory('New project');
      });
    },

    loadProject: (state: ProjectState) => {
      set((s) => {
        Object.assign(s, state);
        s.activeBlockId = null;
        s.past = [];
        s.future = [];
      });
    },

    setProjectName: (name: string) => {
      set((s) => {
        s.meta.projectName = name;
        s.meta.updatedAt = new Date().toISOString();
      });
    },

    // --- Blocks ---
    addBlock: (name: string) => {
      set((s) => {
        if (!s.blocks[name]) {
          s.blocks[name] = createDefaultBlock(name);
        }
        s.activeBlockId = name;
        s.pushHistory(`Add block: ${name}`);
      });
    },

    removeBlock: (blockId: string) => {
      set((s) => {
        delete s.blocks[blockId];
        if (s.activeBlockId === blockId) {
          s.activeBlockId = null;
        }
        s.pushHistory(`Remove block: ${blockId}`);
      });
    },

    setActiveBlock: (blockId: string | null) => {
      set((s) => { s.activeBlockId = blockId; });
    },

    setBlockNetlist: (blockId: string, netlist: ParsedNetlist) => {
      set((s) => {
        if (!s.blocks[blockId]) {
          s.blocks[blockId] = createDefaultBlock(blockId);
        }
        s.blocks[blockId].netlist = netlist;
        s.activeBlockId = blockId;
        s.pushHistory(`Set netlist for block: ${blockId}`);
      });
    },

    // --- Liberty ---
    setLiberty: (cells: Record<string, LibertyCell>) => {
      set((s) => {
        s.liberty = cells;
        s.pushHistory('Set liberty cells');
      });
    },

    addLibertyCell: (name: string, cell: LibertyCell) => {
      set((s) => {
        s.liberty[name] = cell;
        s.pushHistory(`Add liberty cell: ${name}`);
      });
    },

    // --- External elements ---
    addExternalElement: (el: ExternalElement) => {
      set((s) => {
        s.externalElements[el.name] = el;
        s.pushHistory(`Add element: ${el.name}`);
      });
    },

    updateExternalElement: (name: string, el: ExternalElement) => {
      set((s) => {
        s.externalElements[name] = el;
        s.pushHistory(`Update element: ${name}`);
      });
    },

    removeExternalElement: (name: string) => {
      set((s) => {
        delete s.externalElements[name];
        s.pushHistory(`Remove element: ${name}`);
      });
    },

    // --- Modules ---
    addModule: (mod: HardwareModule) => {
      set((s) => {
        s.modules.push(mod);
        s.pushHistory(`Add module: ${mod.name}`);
      });
    },

    updateModule: (id: string, mod: Partial<HardwareModule>) => {
      set((s) => {
        const idx = s.modules.findIndex(m => m.id === id);
        if (idx !== -1) {
          Object.assign(s.modules[idx], mod);
          s.pushHistory(`Update module: ${s.modules[idx].name}`);
        }
      });
    },

    removeModule: (id: string) => {
      set((s) => {
        const idx = s.modules.findIndex(m => m.id === id);
        if (idx !== -1) {
          s.pushHistory(`Remove module: ${s.modules[idx].name}`);
          s.modules.splice(idx, 1);
        }
        // Remove placements referencing this module from ALL blocks
        for (const b of Object.values(s.blocks)) {
          b.placement.modules = b.placement.modules.filter(p => p.moduleId !== id);
          b.placement.elements = b.placement.elements.filter(p => p.moduleId !== id);
        }
      });
    },

    addSlotToModule: (moduleId: string, slot: ModuleSlot) => {
      set((s) => {
        const mod = s.modules.find(m => m.id === moduleId);
        if (mod) {
          mod.slots.push(slot);
          s.pushHistory(`Add slot to ${mod.name}`);
        }
      });
    },

    updateSlotInModule: (moduleId: string, slotIndex: number, slot: Partial<ModuleSlot>) => {
      set((s) => {
        const mod = s.modules.find(m => m.id === moduleId);
        if (mod && mod.slots[slotIndex]) {
          Object.assign(mod.slots[slotIndex], slot);
        }
      });
    },

    removeSlotFromModule: (moduleId: string, slotIndex: number) => {
      set((s) => {
        const mod = s.modules.find(m => m.id === moduleId);
        if (mod && mod.slots[slotIndex]) {
          mod.slots.splice(slotIndex, 1);
        }
      });
    },

    // --- Placement — modules (active block) ---
    setModulePlacements: (placements: ModulePlacement[]) => {
      set((s) => {
        const b = s.activeBlockId ? s.blocks[s.activeBlockId] : null;
        if (!b) return;
        b.placement.modules = placements;
        s.pushHistory('Set module placements');
      });
    },

    placeModule: (placement: ModulePlacement) => {
      set((s) => {
        const b = s.activeBlockId ? s.blocks[s.activeBlockId] : null;
        if (!b) return;
        const idx = b.placement.modules.findIndex(p => p.moduleId === placement.moduleId);
        if (idx !== -1) {
          b.placement.modules[idx] = placement;
        } else {
          b.placement.modules.push(placement);
        }
        s.pushHistory(`Place module: ${placement.moduleId}`);
      });
    },

    lockModule: (moduleId: string, locked: boolean) => {
      set((s) => {
        const b = s.activeBlockId ? s.blocks[s.activeBlockId] : null;
        if (!b) return;
        const p = b.placement.modules.find(m => m.moduleId === moduleId);
        if (p) p.locked = locked;
      });
    },

    removeModulePlacement: (moduleId: string) => {
      set((s) => {
        const b = s.activeBlockId ? s.blocks[s.activeBlockId] : null;
        if (!b) return;
        b.placement.modules = b.placement.modules.filter(p => p.moduleId !== moduleId);
        s.pushHistory(`Remove module placement: ${moduleId}`);
      });
    },

    // --- Placement — elements (active block) ---
    setElementPlacements: (placements: ElementPlacement[]) => {
      set((s) => {
        const b = s.activeBlockId ? s.blocks[s.activeBlockId] : null;
        if (!b) return;
        b.placement.elements = placements;
        s.pushHistory('Set element placements');
      });
    },

    placeElement: (placement: ElementPlacement) => {
      set((s) => {
        const b = s.activeBlockId ? s.blocks[s.activeBlockId] : null;
        if (!b) return;
        const idx = b.placement.elements.findIndex(
          p => p.instanceName === placement.instanceName,
        );
        if (idx !== -1) {
          b.placement.elements[idx] = placement;
        } else {
          b.placement.elements.push(placement);
        }
        s.pushHistory(`Place element: ${placement.instanceName}`);
      });
    },

    lockElement: (instanceName: string, locked: boolean) => {
      set((s) => {
        const b = s.activeBlockId ? s.blocks[s.activeBlockId] : null;
        if (!b) return;
        const p = b.placement.elements.find(e => e.instanceName === instanceName);
        if (p) p.locked = locked;
      });
    },

    removeElementPlacement: (instanceName: string) => {
      set((s) => {
        const b = s.activeBlockId ? s.blocks[s.activeBlockId] : null;
        if (!b) return;
        b.placement.elements = b.placement.elements.filter(
          p => p.instanceName !== instanceName,
        );
        s.pushHistory(`Remove element placement: ${instanceName}`);
      });
    },

    // --- Slot instances ---
    setSlotInstance: (moduleId: string, slotIndex: number, instanceName: string | null) => {
      set((s) => {
        const mod = s.modules.find(m => m.id === moduleId);
        if (!mod) return;
        let si = mod.slotInstances.find(si => si.index === slotIndex);
        if (si) {
          si.instanceName = instanceName;
        } else {
          let count = 0;
          let slotDefIndex = 0;
          for (let i = 0; i < mod.slots.length; i++) {
            if (slotIndex < count + mod.slots[i].count) {
              slotDefIndex = i;
              break;
            }
            count += mod.slots[i].count;
          }
          mod.slotInstances.push({
            index: slotIndex,
            slotDefIndex,
            instanceName,
          });
        }
      });
    },

    // --- Routing (active block) ---
    setRoutedNets: (nets: RoutedNet[]) => {
      set((s) => {
        const b = s.activeBlockId ? s.blocks[s.activeBlockId] : null;
        if (!b) return;
        b.routing.nets = nets;
        s.pushHistory('Set routing');
      });
    },

    addRoutedNet: (net: RoutedNet) => {
      set((s) => {
        const b = s.activeBlockId ? s.blocks[s.activeBlockId] : null;
        if (!b) return;
        b.routing.nets.push(net);
        s.pushHistory(`Add routed net: ${net.netName}`);
      });
    },

    updateRoutedNet: (netName: string, updates: Partial<RoutedNet>) => {
      set((s) => {
        const b = s.activeBlockId ? s.blocks[s.activeBlockId] : null;
        if (!b) return;
        const net = b.routing.nets.find(n => n.netName === netName);
        if (net) Object.assign(net, updates);
      });
    },

    addRouteSegment: (netName: string, segment: RouteSegment) => {
      set((s) => {
        const b = s.activeBlockId ? s.blocks[s.activeBlockId] : null;
        if (!b) return;
        const net = b.routing.nets.find(n => n.netName === netName);
        if (net) {
          net.segments.push(segment);
        } else {
          b.routing.nets.push({ netName, color: '#3388ff', segments: [segment] });
        }
      });
    },

    updateRouteSegment: (netName: string, segmentId: string, updates: Partial<RouteSegment>) => {
      set((s) => {
        const b = s.activeBlockId ? s.blocks[s.activeBlockId] : null;
        if (!b) return;
        const net = b.routing.nets.find(n => n.netName === netName);
        if (!net) return;
        const seg = net.segments.find(s => s.id === segmentId);
        if (seg) Object.assign(seg, updates);
      });
    },

    removeRouteSegment: (netName: string, segmentId: string) => {
      set((s) => {
        const b = s.activeBlockId ? s.blocks[s.activeBlockId] : null;
        if (!b) return;
        const net = b.routing.nets.find(n => n.netName === netName);
        if (!net) return;
        net.segments = net.segments.filter(s => s.id !== segmentId);
        if (net.segments.length === 0) {
          b.routing.nets = b.routing.nets.filter(n => n.netName !== netName);
        }
      });
    },

    markSegmentAssembled: (netName: string, segmentId: string, assembled: boolean) => {
      set((s) => {
        const b = s.activeBlockId ? s.blocks[s.activeBlockId] : null;
        if (!b) return;
        const net = b.routing.nets.find(n => n.netName === netName);
        if (!net) return;
        const seg = net.segments.find(s => s.id === segmentId);
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
    // Build actions that close over the immer `set`
    const actions = createProjectSlice(set);

    // History functions (use set() for mutations — get() returns Immer-frozen state)
    const historySlice: HistorySlice = {
      past: [],
      future: [],

      // pushHistory uses deferred set() to avoid nested-set conflicts.
      // When called inside an action's set() callback, the history mutation
      // is deferred to a microtask — it runs after the outer set() commits,
      // so get() returns the fully-updated, Immer-frozen state and set()
      // executes standalone (no nesting).
      pushHistory: (label: string) => {
        if (_suppressHistory) return;
        // Capture snapshot synchronously — when called from inside a set()
        // callback, get() returns the pre-mutation state (not frozen yet).
        const snapshot = cloneProjectState(get());
        // Defer the actual history mutation so it runs after the outer
        // set() commits — avoids nested set() conflicts and frozen state.
        queueMicrotask(() => {
          if (_suppressHistory) return;
          set((draft) => {
            draft.past.push({ state: snapshot, label });
            if (draft.past.length > MAX_HISTORY) draft.past.shift();
            draft.future = [];
          });
        });
      },

      undo: () => {
        const s = get();
        if (s.past.length === 0) return;
        const prev = s.past[s.past.length - 1];
        const futureSnapshot = cloneProjectState(s);
        _suppressHistory = true;
        set((draft) => {
          if (draft.past.length === 0) return;
          const popped = draft.past.pop()!;
          draft.future.push({ state: futureSnapshot, label: popped.label });
          Object.assign(draft, popped.state);
        });
        _suppressHistory = false;
      },

      redo: () => {
        const s = get();
        if (s.future.length === 0) return;
        const next = s.future[s.future.length - 1];
        const pastSnapshot = cloneProjectState(s);
        _suppressHistory = true;
        set((draft) => {
          if (draft.future.length === 0) return;
          const popped = draft.future.pop()!;
          draft.past.push({ state: pastSnapshot, label: popped.label });
          Object.assign(draft, popped.state);
        });
        _suppressHistory = false;
      },

      clearHistory: () => {
        set((s) => {
          s.past = [];
          s.future = [];
        });
      },
    };

    return { ...initialState, ...actions, ...historySlice, activeBlockId: null };
  };

  return create<ProjectStore>()(immer(stateCreator));
}

// ---------------------------------------------------------------------------
// Singleton store instance
// ---------------------------------------------------------------------------

export const useProjectStore = createProjectStore();
