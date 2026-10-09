// @vitest-environment jsdom
// ============================================================================
// UI smoke test — every tab renders without throwing; autosave round-trip
// ============================================================================

import { describe, it, expect, afterEach } from 'vitest';
import { readFileSync } from 'fs';
import { join } from 'path';
import { render, screen, fireEvent, cleanup, within, act } from '@testing-library/react';
import { ROWS_TOP } from '@/components/Placement/layout';
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

describe('Modules tab', () => {
  it('creates a type, adds a slot, maps a pin and shows it on the connector', () => {
    useProjectStore.getState().setLiberty({
      NAND2: { name: 'NAND2', pins: [{ name: 'A', direction: 'input' }, { name: 'Y', direction: 'output' }], tubes: { J2B: 1 } },
    });
    render(<App />);
    fireEvent.click(screen.getByRole('button', { name: 'Modules' }));
    fireEvent.change(screen.getByPlaceholderText('New type name'), { target: { value: 'Logic' } });
    fireEvent.click(screen.getByRole('button', { name: '+ Type' }));
    expect(screen.getByText('Properties — T1')).toBeTruthy();

    fireEvent.change(screen.getByLabelText('New slot cell type'), { target: { value: 'NAND2' } });
    fireEvent.change(screen.getByLabelText('New slot count'), { target: { value: '2' } });
    fireEvent.click(screen.getByRole('button', { name: '+ Slot' }));
    expect(screen.getByDisplayValue('J2B×2')).toBeTruthy();

    fireEvent.change(screen.getByLabelText('Contact of Y'), { target: { value: 'B5' } });
    expect(screen.getByTestId('contact-B5').textContent).toBe('NAND2 #1.Y');

    fireEvent.click(screen.getByRole('button', { name: 'NAND2 #2' }));
    fireEvent.change(screen.getByLabelText('Contact of Y'), { target: { value: 'B5' } });
    expect(screen.getByText(/1 contact carry more than one pin/)).toBeTruthy();

    fireEvent.click(screen.getByRole('button', { name: 'Auto-assign free contacts' }));
    expect(useProjectStore.getState().moduleTypes[0].slots[0].pinMaps.map(m => m.length)).toEqual([2, 2]);

    fireEvent.change(screen.getByLabelText('Width'), { target: { value: '3' } });
    expect(useProjectStore.getState().moduleTypes[0].widthSteps).toBe(3);
  });
});

describe('Placement tab', () => {
  /** End a drag of a canvas shape at (x, y) mm, in rows coordinates */
  const dropAt = (name: string, x: number, y: number) => {
    const el = document.querySelector(`[data-name="${name}"]`)!;
    el.dispatchEvent(new CustomEvent('konva-dragend', { detail: { x, y } }));
  };

  it('places modules, drags one onto another to push it aside, and respects locks', () => {
    const s = useProjectStore.getState();
    s.addModuleType({ id: 'L', name: 'Logic', kind: 'board', widthSteps: 2, slots: [] });
    s.addBlock('IpLine');
    render(<App />);
    fireEvent.click(screen.getByRole('button', { name: 'Placement' }));

    fireEvent.click(screen.getByRole('button', { name: 'Place' }));
    fireEvent.click(screen.getByRole('button', { name: 'Place' }));
    expect(screen.getByText('Placed (2)')).toBeTruthy();
    const cols = () => useProjectStore.getState().blocks.IpLine.placement.modules.map(m => [m.id, m.col]);
    expect(cols()).toEqual([['M1', 0], ['M2', 2]]);

    // Drop M2 at column 0 (x = 0 mm, row 0): M1 starts there, so it shifts right
    act(() => dropAt('module-M2', 0, ROWS_TOP));
    expect(cols()).toEqual([['M1', 2], ['M2', 0]]);
    expect(screen.getByRole('status').textContent).toMatch(/shifted 1 module aside/);

    // Lock M1 (selected by clicking it), then try to push it
    fireEvent.click(document.querySelector('[data-name="module-M1"]')!);
    fireEvent.click(screen.getByRole('button', { name: 'Lock' }));
    act(() => dropAt('module-M2', 24, ROWS_TOP));
    expect(cols()).toEqual([['M1', 2], ['M2', 0]]);
    expect(screen.getByRole('status').textContent).toMatch(/locked module is in the way/);
  });

  it('reorders connectors by dragging', () => {
    const s = useProjectStore.getState();
    s.addBlock('IpLine');
    s.addConnector();
    s.addConnector();
    render(<App />);
    fireEvent.click(screen.getByRole('button', { name: 'Placement' }));
    act(() => dropAt('connector-J2', 0, 4));
    expect(useProjectStore.getState().blocks.IpLine.connectors.map(c => [c.id, c.position]))
      .toEqual([['J1', 1], ['J2', 0]]);
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
