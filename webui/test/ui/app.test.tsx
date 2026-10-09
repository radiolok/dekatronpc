// @vitest-environment jsdom
// ============================================================================
// UI smoke test — every tab renders without throwing; autosave round-trip
// ============================================================================

import { describe, it, expect, afterEach } from 'vitest';
import { render, screen, fireEvent, cleanup } from '@testing-library/react';
import { App } from '@/components/App';
import { useProjectStore } from '@/store';
import { autosaveProject, loadAutosave, clearAutosave } from '@/services';

const TABS = ['Project', 'Netlist', 'Elements', 'Modules', 'Placement', 'Routing', 'Assembly'];

afterEach(() => {
  cleanup();
  clearAutosave();
  useProjectStore.getState().newProject('New Project');
});

describe('App', () => {
  it('renders the Project tab by default', () => {
    render(<App />);
    expect(screen.getByText('Project Info')).toBeTruthy();
    expect(screen.getByText('Block Configuration')).toBeTruthy();
  });

  it('renders every tab', () => {
    render(<App />);
    for (const tab of TABS) {
      fireEvent.click(screen.getByRole('button', { name: tab }));
    }
    expect(screen.getByText(/Assembly — in development/)).toBeTruthy();
  });

  it('renders a project with blocks and module types', () => {
    const s = useProjectStore.getState();
    s.addModuleType({ id: 'T', name: 'T', widthSteps: 2, slots: [] });
    s.addBlock('IpLine');
    s.addModuleInstance('T', 0, 0);
    render(<App />);
    const row = screen.getByText('Modules placed (total)').closest('tr');
    expect(row?.textContent).toContain('1');
  });
});

describe('autosave', () => {
  it('restores the project without undo history', () => {
    const s = useProjectStore.getState();
    s.setProjectName('Saved');
    s.addBlock('ApLine');
    autosaveProject(useProjectStore.getState());

    const stored = JSON.parse(localStorage.getItem('dekatronpc-project-autosave')!);
    expect(stored.past).toBeUndefined();

    useProjectStore.getState().newProject('Other');
    useProjectStore.getState().loadProject(loadAutosave()!);
    expect(useProjectStore.getState().meta.projectName).toBe('Saved');
    expect(useProjectStore.getState().activeBlockId).toBe('ApLine');
  });
});
