// ============================================================================
// Project file I/O — load/save/autosave
// ============================================================================

import type { ProjectState } from '@/types';
import { createDefaultProject } from '@/types';

const AUTOSAVE_KEY = 'dekatronpc-project-autosave';
const AUTOSAVE_INTERVAL = 30_000; // 30 seconds

/**
 * Serialize project state to JSON string.
 */
export function serializeProject(state: ProjectState): string {
  return JSON.stringify(state, null, 2);
}

/**
 * Migrate old single-netlist project to multi-block format.
 */
function migrateProject(state: any): ProjectState {
  // Detect old format: top-level 'netlist' field exists but 'blocks' doesn't
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
  return state as ProjectState;
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
  localStorage.removeItem(AUTOSAVE_KEY);
}

/**
 * Start periodic autosave. Returns a cleanup function.
 */
export function startAutosave(
  getState: () => ProjectState,
  interval: number = AUTOSAVE_INTERVAL,
): () => void {
  const timer = setInterval(() => {
    autosaveProject(getState());
  }, interval);
  return () => clearInterval(timer);
}

function sanitizeFilename(name: string): string {
  return name.replace(/[^a-zA-Zа-яА-ЯёЁ0-9 _-]/g, '_').trim() || 'project';
}
