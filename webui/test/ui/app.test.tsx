// @vitest-environment jsdom
// ============================================================================
// UI smoke test — every tab renders without throwing; autosave round-trip
// ============================================================================

import { describe, it, expect, afterEach } from 'vitest';
import { readFileSync } from 'fs';
import { join } from 'path';
import { render, screen, fireEvent, cleanup, within } from '@testing-library/react';
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

describe('Netlist tab', () => {
  it('parses a hierarchical netlist, keeping a chosen submodule whole', () => {
    render(<App />);
    fireEvent.click(screen.getByRole('button', { name: 'Netlist' }));
    const source = readFileSync(join(__dirname, '..', 'fixtures', 'hier.v'), 'utf-8');
    fireEvent.change(screen.getByPlaceholderText(/AND2 U1/), { target: { value: source } });

    const hierarchy = screen.getByText('Hierarchy').closest('.panel') as HTMLElement;
    expect(within(hierarchy).getByText('Top')).toBeTruthy();
    const pairRow = within(hierarchy).getByText('Pair').closest('tr')!;
    fireEvent.click(within(pairRow).getByRole('checkbox'));
    fireEvent.click(screen.getByRole('button', { name: 'Parse Verilog' }));

    const s = useProjectStore.getState();
    const block = s.blocks[s.activeBlockId!];
    expect(block.netlist.instances.map(i => i.cellType).sort()).toEqual(['Pair', 'Pair', 'REG4']);
    expect(block.netlist.keep).toEqual(['Pair']);

    // Pair is now a missing type that the file defines: add it as an element
    const missing = screen.getByText('Missing Cell Types').closest('.panel') as HTMLElement;
    const pairItem = within(missing).getByText('Pair').closest('li')!;
    fireEvent.click(within(pairItem).getByRole('button', { name: 'Add as element' }));
    expect(useProjectStore.getState().externalElements.Pair.pins.map(p => p.name))
      .toEqual(['in[1]', 'in[0]', 'out[1]', 'out[0]', 'en']);
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
