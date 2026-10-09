// ============================================================================
// Format 0.4.0 store actions — rows, geometry, connectors, cables, power nets —
// and the inter-block links derived from them (services/interconnect.ts)
// ============================================================================

import { describe, it, expect, beforeEach } from 'vitest';
import { createProjectStore } from '@/store/projectStore';
import type { ProjectStore } from '@/store/projectStore';
import { cableLinks, unassignedPorts, portLocation, boardModules } from '@/services/interconnect';
import type { ParsedNetlist, PinDirection } from '@/types';

let useStore: ReturnType<typeof createProjectStore>;
const S = (): ProjectStore => useStore.getState();

/** A netlist with only top-level ports */
function ports(...list: [string, PinDirection][]): ParsedNetlist {
  return { instances: [], nets: [], ports: list.map(([name, direction]) => ({ name, direction, net: name })) };
}

beforeEach(() => {
  useStore = createProjectStore();
  S().setBlockNetlist('IpLine', ports(['ip[0]', 'output'], ['ip[1]', 'output'], ['halt', 'input']));
  S().setBlockNetlist('MachineCtrl', ports(['ip[0]', 'input'], ['ip[1]', 'input'], ['halt', 'output']));
});

describe('rows and geometry', () => {
  it('sets rows per block within 3..5', () => {
    S().setBlockRows('IpLine', 5);
    S().setBlockRows('MachineCtrl', 9);
    expect(S().blocks.IpLine.rows).toBe(5);
    expect(S().blocks.MachineCtrl.rows).toBe(5);
    S().setBlockRows('IpLine', 1);
    expect(S().blocks.IpLine.rows).toBe(3);
  });

  it('never drops a row that holds a module', () => {
    S().addModuleType({ id: 'L', name: 'L', kind: 'board', widthSteps: 2, slots: [] });
    S().setActiveBlock('IpLine');
    S().setBlockRows('IpLine', 5);
    expect(S().addModuleInstance('L', 4, 0)).toBe('M1');
    S().setBlockRows('IpLine', 3);
    expect(S().blocks.IpLine.rows).toBe(5);
  });

  it('snaps the transformer width to 72 + 12·K mm', () => {
    S().setBlockConfig({ transformerWidth: 90 });
    expect(S().block.transformerWidth).toBe(96);
    S().setBlockConfig({ transformerWidth: 50 });
    expect(S().block.transformerWidth).toBe(72);
  });

  it('refuses a transformer width that would cover a placed module', () => {
    S().addModuleType({ id: 'L', name: 'L', kind: 'board', widthSteps: 2, slots: [] });
    S().setActiveBlock('IpLine');
    S().addModuleInstance('L', 0, 12); // 144..168 mm, clear of the 84 mm transformer (168..252)
    S().setBlockConfig({ transformerWidth: 96 }); // 162..258 would cover it
    expect(S().block.transformerWidth).toBe(84);
  });
});

describe('connectors', () => {
  beforeEach(() => S().setActiveBlock('IpLine'));

  it('adds HD-68 connectors in a row', () => {
    expect(S().addConnector()).toBe('J1');
    expect(S().addConnector()).toBe('J2');
    expect(S().blocks.IpLine.connectors.map(c => [c.id, c.pins, c.position])).toEqual([['J1', 68, 0], ['J2', 68, 1]]);
  });

  it('moves a connector by swapping places', () => {
    S().addConnector();
    S().addConnector();
    S().moveConnector('J2', 0);
    expect(S().blocks.IpLine.connectors.map(c => [c.id, c.position])).toEqual([['J1', 1], ['J2', 0]]);
  });

  it('puts a port on one pin only, and checks pin range and port name', () => {
    S().addConnector();
    S().addConnector();
    S().assignConnectorPin('J1', 5, 'ip[0]');
    S().assignConnectorPin('J2', 7, 'ip[0]'); // moves it
    S().assignConnectorPin('J1', 69, 'ip[1]'); // no pin 69
    S().assignConnectorPin('J1', 6, 'nope'); // no such port
    const b = S().blocks.IpLine;
    expect(portLocation(b, 'ip[0]')).toBe('J2:7');
    expect(b.connectors[0].ports).toEqual([]);
    expect(unassignedPorts(b)).toEqual(['ip[1]', 'halt']);
    S().assignConnectorPin('J2', 7, null);
    expect(portLocation(S().blocks.IpLine, 'ip[0]')).toBeUndefined();
  });

  it('removing a connector removes its cable and wires ending on it', () => {
    S().addConnector();
    S().setActiveBlock('MachineCtrl');
    S().addConnector();
    S().addCable({ block: 'IpLine', connector: 'J1' }, { block: 'MachineCtrl', connector: 'J1' });
    S().setActiveBlock('IpLine');
    S().addRouteSegment('ip[0]', {
      id: 's1', start: { connectorId: 'J1', pin: 1 }, end: { connectorId: 'J1', pin: 2 }, path: [], assembled: false,
    });
    S().removeConnector('J1');
    expect(S().cables).toEqual([]);
    expect(S().blocks.IpLine.routing.nets).toEqual([]);
  });
});

describe('cables and links', () => {
  beforeEach(() => {
    for (const b of ['IpLine', 'MachineCtrl']) {
      S().setActiveBlock(b);
      S().addConnector();
    }
  });
  const ip = { block: 'IpLine', connector: 'J1' };
  const mc = { block: 'MachineCtrl', connector: 'J1' };

  it('joins connectors of two blocks, one cable per connector', () => {
    expect(S().addCable(ip, mc)).toBe('C1');
    expect(S().addCable(mc, ip)).toBeNull();
    expect(S().addCable(ip, ip)).toBeNull();
    expect(S().addCable(ip, { block: 'MachineCtrl', connector: 'J9' })).toBeNull();
  });

  it('removing a block removes its cables', () => {
    S().addCable(ip, mc);
    S().removeBlock('MachineCtrl');
    expect(S().cables).toEqual([]);
  });

  it('links ports pin for pin and reports problems', () => {
    S().addCable(ip, mc);
    S().setActiveBlock('IpLine');
    S().assignConnectorPin('J1', 1, 'ip[0]');
    S().assignConnectorPin('J1', 2, 'ip[1]');
    S().assignConnectorPin('J1', 3, 'halt');
    S().setActiveBlock('MachineCtrl');
    S().assignConnectorPin('J1', 1, 'ip[0]');
    S().assignConnectorPin('J1', 3, 'ip[1]'); // input meets input
    const links = cableLinks(S());
    expect(links.map(l => [l.pin, l.from.port, l.to.port, l.problems])).toEqual([
      [1, 'ip[0]', 'ip[0]', []],
      [2, 'ip[1]', undefined, ['one-end']],
      [3, 'halt', 'ip[1]', ['no-driver']],
    ]);
  });

  it('flags ports that disappeared after re-parsing', () => {
    S().addCable(ip, mc);
    S().setActiveBlock('IpLine');
    S().assignConnectorPin('J1', 1, 'ip[0]');
    S().setActiveBlock('MachineCtrl');
    S().assignConnectorPin('J1', 1, 'halt');
    S().setBlockNetlist('IpLine', ports(['other', 'output']));
    expect(cableLinks(S())[0].problems).toEqual(['unknown-port']);
  });
});

describe('power nets', () => {
  it('marks and unmarks a net, and survives re-parsing', () => {
    S().setActiveBlock('IpLine');
    S().setPowerNet('vcc', true);
    S().setPowerNet('vcc', true);
    expect(S().blocks.IpLine.powerNets).toEqual(['vcc']);
    S().setBlockNetlist('IpLine', ports());
    expect(S().blocks.IpLine.powerNets).toEqual(['vcc']);
    S().setPowerNet('vcc', false);
    expect(S().blocks.IpLine.powerNets).toEqual([]);
  });
});

describe('board modules', () => {
  it('lists Verilog modules that board types implement', () => {
    S().addModuleType({ id: 'D', name: 'Dekatron', kind: 'board', widthSteps: 3, slots: [], verilogModule: 'DekatronModule' });
    S().addModuleType({ id: 'I', name: 'Link', kind: 'interconnect', widthSteps: 2, slots: [] });
    expect(boardModules(S())).toEqual(['DekatronModule']);
  });
});
