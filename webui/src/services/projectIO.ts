// ============================================================================
// Project file I/O — load/save/autosave
// ============================================================================

import type { ProjectState, Block, ModuleType, ModuleInstance } from '@/types';
import {
  DEFAULT_BLOCK_CONFIG,
  PROJECT_FORMAT_VERSION,
  ROWS_MIN,
  ROWS_MAX,
  ROWS_DEFAULT,
  canPlaceModule,
  createDefaultBlock,
  createDefaultProject,
  isConnectorTerminal,
  pickProjectState,
  snapTransformerWidth,
} from '@/types';
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
 * single netlist (pre-0.2) → multi-block (0.2.0) → module types + instances (0.3.0)
 * → per-block rows, connectors, cables, power nets (0.4.0).
 * Each step converts fields; placements that no longer fit are dropped at the end.
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
  const from = state.meta?.version ?? '0.0.0';
  // 0.2.0: 'modules' holds hardware modules, each placed at most once
  if (!state.moduleTypes) migrateFrom02(state);
  if (!state.moduleTypes || versionLess(from, '0.4.0')) migrateFrom03(state);
  if (versionLess(from, PROJECT_FORMAT_VERSION)) dropInvalidPlacements(state);
  if (state.meta) state.meta.version = PROJECT_FORMAT_VERSION;
  return withDefaults(state);
}

function versionLess(a: string, b: string): boolean {
  const pa = a.split('.').map(Number);
  const pb = b.split('.').map(Number);
  for (let i = 0; i < 3; i++) {
    if ((pa[i] || 0) !== (pb[i] || 0)) return (pa[i] || 0) < (pb[i] || 0);
  }
  return false;
}

/**
 * 0.2.0 → 0.3.0. A 0.2 HardwareModule was both a PCB design and its single
 * placed copy, so it becomes a ModuleType plus, where placed, a ModuleInstance
 * with the same id. The old chassis geometry (920 mm wide, maxCols) has no
 * counterpart, so the chassis is reset to the defaults, keeping `rows`.
 */
function migrateFrom02(state: any): void {
  const moduleTypes: ModuleType[] = (state.modules ?? []).map((m: any) => ({
    id: m.id,
    name: m.name ?? m.id,
    kind: 'board',
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
  state.block = { ...DEFAULT_BLOCK_CONFIG, rows: old.rows, obstructions: old.obstructions ?? [] };

  const point = (t: any) => ({ moduleInstanceId: t.moduleId, pin: t.pin });
  for (const b of Object.values<any>(state.blocks ?? {})) {
    b.placement = {
      modules: (b.placement?.modules ?? []).map((p: any) => ({
        id: p.moduleId, typeId: p.moduleId, row: p.row, col: p.col, locked: !!p.locked,
      })),
      elements: (b.placement?.elements ?? []).map((e: any) => ({
        instanceName: e.instanceName,
        moduleInstanceId: e.moduleId,
        slotIndex: e.slotIndex,
        locked: !!e.locked,
      })),
    };
    b.routing = {
      nets: (b.routing?.nets ?? []).map((n: any) => ({
        ...n,
        segments: n.segments.map((g: any) => ({ ...g, start: point(g.start), end: point(g.end) })),
      })),
    };
  }
}

/**
 * 0.3.0 → 0.4.0. `rows` moves from the shared geometry to each block; the
 * transformer width snaps to 72 + 12·K mm (Q4); blocks get connectors and power
 * nets, the project gets cables, and module types become ordinary boards.
 */
function migrateFrom03(state: any): void {
  const block = state.block ?? {};
  const rows = clamp(Math.round(block.rows ?? ROWS_DEFAULT), ROWS_MIN, ROWS_MAX);
  delete block.rows;
  block.gridStep = block.gridStep ?? DEFAULT_BLOCK_CONFIG.gridStep;
  block.transformerWidth = snapTransformerWidth(
    block.transformerWidth ?? DEFAULT_BLOCK_CONFIG.transformerWidth, block.gridStep);
  state.block = block;
  for (const b of Object.values<any>(state.blocks ?? {})) {
    b.rows = rows;
    b.connectors = b.connectors ?? [];
    b.powerNets = b.powerNets ?? [];
  }
  state.cables = state.cables ?? [];
  for (const t of state.moduleTypes ?? []) t.kind = t.kind ?? 'board';
}

/**
 * Drop module instances that don't fit the (new) geometry, in file order,
 * along with the elements placed in them and wires ending on them.
 */
function dropInvalidPlacements(state: any): void {
  for (const b of Object.values<any>(state.blocks ?? {})) {
    const placed: ModuleInstance[] = [];
    for (const m of b.placement?.modules ?? []) {
      if (canPlaceModule(state, b.rows, placed, m.typeId, m.row, m.col)) placed.push(m);
    }
    const ids = new Set(placed.map(m => m.id));
    const ok = (t: any) => isConnectorTerminal(t) || ids.has(t.moduleInstanceId);
    b.placement = {
      modules: placed,
      elements: (b.placement?.elements ?? []).filter((e: any) => ids.has(e.moduleInstanceId)),
    };
    b.routing = {
      nets: (b.routing?.nets ?? [])
        .map((n: any) => ({ ...n, segments: n.segments.filter((g: any) => ok(g.start) && ok(g.end)) }))
        .filter((n: any) => n.segments.length > 0),
    };
  }
}

/** Fill fields missing from a hand-edited or partial file with defaults */
function withDefaults(state: any): ProjectState {
  const d = createDefaultProject();
  const blocks: Record<string, Block> = {};
  for (const [id, b] of Object.entries<any>(state.blocks ?? {})) {
    blocks[id] = { ...createDefaultBlock(id), ...b };
  }
  return {
    meta: { ...d.meta, ...state.meta },
    liberty: state.liberty ?? {},
    externalElements: state.externalElements ?? {},
    moduleTypes: state.moduleTypes ?? [],
    block: { ...d.block, ...state.block },
    blocks,
    cables: state.cables ?? [],
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
