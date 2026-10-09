// ============================================================================
// Inter-block connections through HD-68 cables (Q1, Q9)
//
// A block port bit is put on a pin of one of the block's connectors. A cable
// joins two connectors of different blocks pin for pin, so pin n of one end
// carries the port on pin n of the other.
// ============================================================================

import type { Block, PinDirection, ProjectState } from '@/types';

export interface CableLinkEnd {
  block: string;
  connector: string;
  /** Port bit on this pin, if one is assigned */
  port?: string;
  direction?: PinDirection;
  /** Net of the port inside the block, or a constant */
  net?: string;
}

export type CableLinkProblem =
  | 'one-end'        // a port on one end only
  | 'unknown-port'   // the assigned port is not in the block's netlist (re-parsed?)
  | 'two-drivers'    // output on both ends
  | 'no-driver';     // input on both ends

export interface CableLink {
  cable: string;
  pin: number;
  from: CableLinkEnd;
  to: CableLinkEnd;
  problems: CableLinkProblem[];
}

function linkEnd(state: ProjectState, end: { block: string; connector: string }, pin: number): CableLinkEnd {
  const block = state.blocks[end.block];
  const port = block?.connectors.find(c => c.id === end.connector)?.ports.find(a => a.pin === pin)?.port;
  const info = port ? block.netlist.ports?.find(p => p.name === port) : undefined;
  return { ...end, port, direction: info?.direction, net: info?.net };
}

/** Every cable pin that carries a port on at least one end, with what is wrong with it */
export function cableLinks(state: ProjectState): CableLink[] {
  const links: CableLink[] = [];
  for (const cable of state.cables) {
    const pins = state.blocks[cable.from.block]?.connectors.find(c => c.id === cable.from.connector)?.pins ?? 0;
    for (let pin = 1; pin <= pins; pin++) {
      const from = linkEnd(state, cable.from, pin);
      const to = linkEnd(state, cable.to, pin);
      if (!from.port && !to.port) continue;
      const problems: CableLinkProblem[] = [];
      if (!from.port || !to.port) problems.push('one-end');
      if ((from.port && !from.direction) || (to.port && !to.direction)) problems.push('unknown-port');
      if (from.direction === 'output' && to.direction === 'output') problems.push('two-drivers');
      if (from.direction === 'input' && to.direction === 'input') problems.push('no-driver');
      links.push({ cable: cable.id, pin, from, to, problems });
    }
  }
  return links;
}

/** Port bits of a block that are on no connector pin */
export function unassignedPorts(block: Block): string[] {
  const assigned = new Set(block.connectors.flatMap(c => c.ports.map(a => a.port)));
  return (block.netlist.ports ?? []).map(p => p.name).filter(p => !assigned.has(p));
}

/** Where a port bit sits: "J1:17", or undefined */
export function portLocation(block: Block, port: string): string | undefined {
  for (const c of block.connectors) {
    const a = c.ports.find(x => x.port === port);
    if (a) return `${c.id}:${a.pin}`;
  }
  return undefined;
}

/** Verilog modules that board types implement: keep them whole when parsing */
export function boardModules(state: Pick<ProjectState, 'moduleTypes'>): string[] {
  return [...new Set(state.moduleTypes.flatMap(t => (t.verilogModule ? [t.verilogModule] : [])))].sort();
}
