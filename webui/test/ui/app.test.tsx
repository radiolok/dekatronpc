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
    expect(screen.getByText('Basket Geometry')).toBeTruthy();
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
    s.addModuleType({ id: 'T', name: 'T', kind: 'board', widthSteps: 2, slots: [] });
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

describe('Connectors and cables', () => {
  it('assigns a port to a connector pin, marks a power net and cables two blocks', () => {
    const s = useProjectStore.getState();
    const netlist = (dir: 'input' | 'output') => ({
      instances: [{ name: 'u', cellType: 'NOT', connections: { A: 'go' } }],
      nets: [{ name: 'go', terminals: [{ instance: 'u', port: 'A' }] }],
      ports: [{ name: 'go', direction: dir, net: 'go' }],
    });
    s.setBlockNetlist('MachineCtrl', netlist('output'));
    s.addConnector();
    s.setBlockNetlist('IpLine', netlist('input'));

    render(<App />);
    fireEvent.click(screen.getByRole('button', { name: 'Netlist' }));
    fireEvent.click(screen.getByRole('button', { name: /^Ports/ }));
    fireEvent.click(screen.getByRole('button', { name: '+ HD-68' }));
    const pin = screen.getByLabelText('Pin of go');
    fireEvent.change(pin, { target: { value: 'J1:5' } });
    fireEvent.blur(pin);
    expect(useProjectStore.getState().blocks.IpLine.connectors[0].ports).toEqual([{ pin: 5, port: 'go' }]);

    fireEvent.click(screen.getByRole('button', { name: /^Nets/ }));
    fireEvent.click(screen.getByLabelText('go is a power net'));
    expect(useProjectStore.getState().blocks.IpLine.powerNets).toEqual(['go']);

    fireEvent.click(screen.getByRole('button', { name: 'Project' }));
    const cables = screen.getByRole('heading', { name: 'Cables' }).closest('.panel') as HTMLElement;
    fireEvent.change(within(cables).getByLabelText('Cable From'), { target: { value: 'IpLine\u0000J1' } });
    fireEvent.change(within(cables).getByLabelText('Cable To'), { target: { value: 'MachineCtrl\u0000J1' } });
    fireEvent.click(within(cables).getByRole('button', { name: '+ Cable' }));
    expect(useProjectStore.getState().cables).toEqual([
      { id: 'C1', from: { block: 'IpLine', connector: 'J1' }, to: { block: 'MachineCtrl', connector: 'J1' } },
    ]);
    // MachineCtrl has no port on pin 5 yet: one problem pin
    expect(within(cables).getByText(/1 cable pin with a problem/)).toBeTruthy();
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
