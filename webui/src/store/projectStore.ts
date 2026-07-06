// ============================================================================
// Zustand store with undo/redo support via Immer
// ============================================================================

import { create, type StateCreator } from 'zustand';
import { immer } from 'zustand/middleware/immer';
import type {
  ProjectState,
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

// ---------------------------------------------------------------------------
// History / Undo-Redo
// ---------------------------------------------------------------------------

const MAX_HISTORY = 50;

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

  // Netlist
  setNetlist: (netlist: ParsedNetlist) => void;

  // Placement — modules
  setModulePlacements: (placements: ModulePlacement[]) => void;
  placeModule: (placement: ModulePlacement) => void;
  lockModule: (moduleId: string, locked: boolean) => void;
  removeModulePlacement: (moduleId: string) => void;

  // Placement — elements
  setElementPlacements: (placements: ElementPlacement[]) => void;
  placeElement: (placement: ElementPlacement) => void;
  lockElement: (instanceName: string, locked: boolean) => void;
  removeElementPlacement: (instanceName: string) => void;

  // Slot instances
  setSlotInstance: (moduleId: string, slotIndex: number, instanceName: string | null) => void;

  // Routing
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

export type ProjectStore = ProjectState & HistorySlice & ProjectActions;

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
        s.past = [];
        s.future = [];
        s.pushHistory('New project');
      });
    },

    loadProject: (state: ProjectState) => {
      set((s) => {
        Object.assign(s, state);
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
        // Also remove placements referencing this module
        s.placement.modules = s.placement.modules.filter(p => p.moduleId !== id);
        s.placement.elements = s.placement.elements.filter(p => p.moduleId !== id);
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

    // --- Netlist ---
    setNetlist: (netlist: ParsedNetlist) => {
      set((s) => {
        s.netlist = netlist;
        s.pushHistory('Set netlist');
      });
    },

    // --- Module placements ---
    setModulePlacements: (placements: ModulePlacement[]) => {
      set((s) => {
        s.placement.modules = placements;
        s.pushHistory('Set module placements');
      });
    },

    placeModule: (placement: ModulePlacement) => {
      set((s) => {
        const idx = s.placement.modules.findIndex(p => p.moduleId === placement.moduleId);
        if (idx !== -1) {
          s.placement.modules[idx] = placement;
        } else {
          s.placement.modules.push(placement);
        }
        s.pushHistory(`Place module: ${placement.moduleId}`);
      });
    },

    lockModule: (moduleId: string, locked: boolean) => {
      set((s) => {
        const p = s.placement.modules.find(m => m.moduleId === moduleId);
        if (p) p.locked = locked;
      });
    },

    removeModulePlacement: (moduleId: string) => {
      set((s) => {
        s.placement.modules = s.placement.modules.filter(p => p.moduleId !== moduleId);
        s.pushHistory(`Remove module placement: ${moduleId}`);
      });
    },

    // --- Element placements ---
    setElementPlacements: (placements: ElementPlacement[]) => {
      set((s) => {
        s.placement.elements = placements;
        s.pushHistory('Set element placements');
      });
    },

    placeElement: (placement: ElementPlacement) => {
      set((s) => {
        const idx = s.placement.elements.findIndex(
          p => p.instanceName === placement.instanceName,
        );
        if (idx !== -1) {
          s.placement.elements[idx] = placement;
        } else {
          s.placement.elements.push(placement);
        }
        s.pushHistory(`Place element: ${placement.instanceName}`);
      });
    },

    lockElement: (instanceName: string, locked: boolean) => {
      set((s) => {
        const p = s.placement.elements.find(e => e.instanceName === instanceName);
        if (p) p.locked = locked;
      });
    },

    removeElementPlacement: (instanceName: string) => {
      set((s) => {
        s.placement.elements = s.placement.elements.filter(
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
          // Determine which slot definition this belongs to
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

    // --- Routing ---
    setRoutedNets: (nets: RoutedNet[]) => {
      set((s) => {
        s.routing.nets = nets;
        s.pushHistory('Set routing');
      });
    },

    addRoutedNet: (net: RoutedNet) => {
      set((s) => {
        s.routing.nets.push(net);
        s.pushHistory(`Add routed net: ${net.netName}`);
      });
    },

    updateRoutedNet: (netName: string, updates: Partial<RoutedNet>) => {
      set((s) => {
        const net = s.routing.nets.find(n => n.netName === netName);
        if (net) Object.assign(net, updates);
      });
    },

    addRouteSegment: (netName: string, segment: RouteSegment) => {
      set((s) => {
        const net = s.routing.nets.find(n => n.netName === netName);
        if (net) {
          net.segments.push(segment);
        } else {
          s.routing.nets.push({ netName, color: '#3388ff', segments: [segment] });
        }
      });
    },

    updateRouteSegment: (netName: string, segmentId: string, updates: Partial<RouteSegment>) => {
      set((s) => {
        const net = s.routing.nets.find(n => n.netName === netName);
        if (!net) return;
        const seg = net.segments.find(s => s.id === segmentId);
        if (seg) Object.assign(seg, updates);
      });
    },

    removeRouteSegment: (netName: string, segmentId: string) => {
      set((s) => {
        const net = s.routing.nets.find(n => n.netName === netName);
        if (!net) return;
        net.segments = net.segments.filter(s => s.id !== segmentId);
        // Remove net if no segments left
        if (net.segments.length === 0) {
          s.routing.nets = s.routing.nets.filter(n => n.netName !== netName);
        }
      });
    },

    markSegmentAssembled: (netName: string, segmentId: string, assembled: boolean) => {
      set((s) => {
        const net = s.routing.nets.find(n => n.netName === netName);
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

    // History functions (these call get() internally)
    const historySlice: HistorySlice = {
      past: [],
      future: [],

      pushHistory: (label: string) => {
        const s = get();
        // Avoid pushing history during undo/redo or initial load
        if ((s as any)._suppressHistory) return;
        s.past.push({ state: structuredClone(s as unknown as ProjectState), label });
        if (s.past.length > MAX_HISTORY) s.past.shift();
        s.future = [];
      },

      undo: () => {
        const s = get();
        if (s.past.length === 0) return;
        const prev = s.past.pop()!;
        s.future.push({ state: structuredClone(s as unknown as ProjectState), label: prev.label });
        (s as any)._suppressHistory = true;
        Object.assign(s, prev.state, { past: s.past, future: s.future });
        (s as any)._suppressHistory = false;
      },

      redo: () => {
        const s = get();
        if (s.future.length === 0) return;
        const next = s.future.pop()!;
        s.past.push({ state: structuredClone(s as unknown as ProjectState), label: next.label });
        (s as any)._suppressHistory = true;
        Object.assign(s, next.state, { past: s.past, future: s.future });
        (s as any)._suppressHistory = false;
      },

      clearHistory: () => {
        set((s) => {
          s.past = [];
          s.future = [];
        });
      },
    };

    return { ...initialState, ...actions, ...historySlice };
  };

  return create<ProjectStore>()(immer(stateCreator));
}

// ---------------------------------------------------------------------------
// Singleton store instance
// ---------------------------------------------------------------------------

export const useProjectStore = createProjectStore();
