// ============================================================================
// Project file I/O — load/save/autosave
// ============================================================================

import type { ProjectState, ModuleType, ModuleInstance } from '@/types';
import {
  DEFAULT_BLOCK_CONFIG,
  PROJECT_FORMAT_VERSION,
  ROWS_MIN,
  ROWS_MAX,
  createDefaultProject,
  pickProjectState,
} from '@/types';
import { canPlaceModule } from '@/store/projectStore';
import { clamp } from '@/utils/helpers';

const AUTOSAVE_KEY = 'dekatronpc-project-autosave';
const AUTOSAVE_INTERVAL = 30_000; // 30 seconds

/**
 * Serialize project state to JSON string. Only the project data is written:
 * store actions, undo history and UI state are dropped.
 */
export function serializeProject(state: ProjectState): string {
  return JSON.stringify(pickProjectState(state), null, 2);
}

/**
 * Migrate an older project to the current format:
 * single-netlist (pre-0.2) → multi-block (0.2.0) → module types + instances (0.3.0).
 */
function migrateProject(state: any): ProjectState {
  // Pre-0.2: top-level 'netlist' field exists but 'blocks' doesn't
  if (state.netlist && !state.blocks) {
    const block: any = {
      name: 'Legacy',
      netlist: state.netlist,
      placement: state.placement || { modules: [], elements: [] },
      routing: state.routing || { nets: [] },
    };
    state.blocks = { Legacy: block };
    delete state.netlist;
    delete state.placement;
    delete state.routing;
    if (state.meta) state.meta.version = '0.2.0';
  }
  // 0.2.0: 'modules' holds hardware modules, each placed at most once
  if (!state.moduleTypes) migrateFrom02(state);
  return withDefaults(state);
}

/**
 * 0.2.0 → 0.3.0. A 0.2 HardwareModule was both a PCB design and its single
 * placed copy, so it becomes a ModuleType plus, where placed, a ModuleInstance
 * with the same id. The old chassis geometry (920 mm wide, maxCols) has no
 * counterpart, so the chassis is reset to the defaults (keeping `rows`) and
 * module placements that no longer fit are dropped, with whatever sat in them.
 */
function migrateFrom02(state: any): void {
  const moduleTypes: ModuleType[] = (state.modules ?? []).map((m: any) => ({
    id: m.id,
    name: m.name ?? m.id,
    widthSteps: m.widthSteps ?? 2,
    // 0.2 had one pin map per slot definition; it becomes the map of copy 0
    slots: (m.slots ?? []).map((sl: any) => ({
      cellType: sl.cellType,
      count: sl.count,
      pinMaps: Array.from({ length: sl.count }, (_, i) => (i === 0 ? sl.pinMapping ?? [] : [])),
    })),
  }));
  delete state.modules;
  state.moduleTypes = moduleTypes;

  const old = state.block ?? {};
  state.block = {
    ...DEFAULT_BLOCK_CONFIG,
    rows: clamp(Math.round(old.rows ?? DEFAULT_BLOCK_CONFIG.rows), ROWS_MIN, ROWS_MAX),
    obstructions: old.obstructions ?? [],
  };

  for (const b of Object.values<any>(state.blocks ?? {})) {
    const placed: ModuleInstance[] = [];
    for (const p of b.placement?.modules ?? []) {
      if (canPlaceModule(state, placed, p.moduleId, p.row, p.col)) {
        placed.push({ id: p.moduleId, typeId: p.moduleId, row: p.row, col: p.col, locked: !!p.locked });
      }
    }
    const ids = new Set(placed.map(m => m.id));
    b.placement = {
      modules: placed,
      elements: (b.placement?.elements ?? [])
        .filter((e: any) => ids.has(e.moduleId))
        .map((e: any) => ({
          instanceName: e.instanceName,
          moduleInstanceId: e.moduleId,
          slotIndex: e.slotIndex,
          locked: !!e.locked,
        })),
    };
    const point = (t: any) => ({ moduleInstanceId: t.moduleId, pin: t.pin });
    b.routing = {
      nets: (b.routing?.nets ?? [])
        .map((n: any) => ({
          ...n,
          segments: n.segments
            .filter((g: any) => ids.has(g.start.moduleId) && ids.has(g.end.moduleId))
            .map((g: any) => ({ ...g, start: point(g.start), end: point(g.end) })),
        }))
        .filter((n: any) => n.segments.length > 0),
    };
  }
  if (state.meta) state.meta.version = PROJECT_FORMAT_VERSION;
}

/** Fill fields missing from a hand-edited or partial file with defaults */
function withDefaults(state: any): ProjectState {
  const d = createDefaultProject();
  return {
    meta: { ...d.meta, ...state.meta },
    liberty: state.liberty ?? {},
    externalElements: state.externalElements ?? {},
    moduleTypes: state.moduleTypes ?? [],
    block: { ...d.block, ...state.block },
    blocks: state.blocks ?? {},
  };
}

/**
 * Deserialize JSON string to ProjectState.
 */
export function deserializeProject(json: string): ProjectState {
  const raw = JSON.parse(json);
  return migrateProject(raw);
}

/**
 * Save project state to a file via browser download.
 */
export function saveProjectToFile(state: ProjectState): void {
  const json = serializeProject(state);
  const blob = new Blob([json], { type: 'application/json' });
  const url = URL.createObjectURL(blob);

  const a = document.createElement('a');
  a.href = url;
  a.download = `${sanitizeFilename(state.meta.projectName)}.dpc.json`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

/**
 * Load project from a user-selected file.
 * Returns a Promise that resolves with the parsed ProjectState.
 */
export function loadProjectFromFile(): Promise<ProjectState> {
  return new Promise((resolve, reject) => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = '.json,.dpc.json';

    input.onchange = () => {
      const file = input.files?.[0];
      if (!file) {
        reject(new Error('No file selected'));
        return;
      }

      const reader = new FileReader();
      reader.onload = () => {
        try {
          const state = deserializeProject(reader.result as string);
          resolve(state);
        } catch (err) {
          reject(new Error(`Failed to parse project: ${(err as Error).message}`));
        }
      };
      reader.onerror = () => reject(new Error('Failed to read file'));
      reader.readAsText(file);
    };

    input.click();
  });
}

/**
 * Save project to localStorage for autosave recovery.
 */
export function autosaveProject(state: ProjectState): void {
  try {
    const json = serializeProject(state);
    localStorage.setItem(AUTOSAVE_KEY, json);
  } catch {
    // localStorage might be full or unavailable
  }
}

/**
 * Load autosaved project from localStorage.
 * Returns null if nothing is saved.
 */
export function loadAutosave(): ProjectState | null {
  try {
    const json = localStorage.getItem(AUTOSAVE_KEY);
    if (!json) return null;
    return deserializeProject(json);
  } catch {
    return null;
  }
}

/**
 * Clear autosaved data.
 */
export function clearAutosave(): void {
  try {
    localStorage.removeItem(AUTOSAVE_KEY);
  } catch {
    // localStorage might be unavailable
  }
}

/**
 * Start periodic autosave, plus a final save when the page is closed.
 * Returns a cleanup function.
 */
export function startAutosave(
  getState: () => ProjectState,
  interval: number = AUTOSAVE_INTERVAL,
): () => void {
  const save = () => autosaveProject(getState());
  const timer = setInterval(save, interval);
  window.addEventListener('pagehide', save);
  return () => {
    clearInterval(timer);
    window.removeEventListener('pagehide', save);
  };
}

function sanitizeFilename(name: string): string {
  return name.replace(/[^a-zA-Zа-яА-ЯёЁ0-9 _-]/g, '_').trim() || 'project';
}
