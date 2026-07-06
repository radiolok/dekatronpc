// ============================================================================
// Verilog flat structural netlist parser
// Handles: wire declarations, module instantiations with named port connections
// ============================================================================

import type { ParsedNetlist, NetlistInstance, NetlistNet } from '@/types';

/**
 * Parse a flat structural Verilog netlist.
 * Supports:
 *   wire net1, net2, ...;
 *   CELL_TYPE instance_name (.port1(net1), .port2(net2), ...);
 *   // comments
 */
export function parseVerilogNetlist(source: string): ParsedNetlist {
  const instances: NetlistInstance[] = [];
  const nets: Map<string, NetlistNet> = new Map();

  // Remove block comments and line comments
  const clean = source
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/\/\/.*$/gm, '');

  // Match wire declarations: wire name1, name2, ...;
  const wireRegex = /\bwire\s+((?:\s*(?:\w+)\s*,?\s*)+)\s*;/g;
  let match: RegExpExecArray | null;
  while ((match = wireRegex.exec(clean)) !== null) {
    const names = match[1].split(',').map(s => s.trim()).filter(Boolean);
    for (const name of names) {
      if (!nets.has(name)) {
        nets.set(name, { name, terminals: [] });
      }
    }
  }

  // Match instance declarations: CELL_TYPE INST_NAME (.PORT1(net1), .PORT2(net2));
  // Handles multi-line instances and both .port(net) and .port ( net ) spacing
  const instanceRegex = /\b(\w+)\s+(\w+)\s*\(([\s\S]*?)\)\s*;/g;
  while ((match = instanceRegex.exec(clean)) !== null) {
    const cellType = match[1];
    const instName = match[2];
    const portStr = match[3];

    const connections: Record<string, string> = {};
    const connRegex = /\.(\w+)\s*\(\s*(\w+)\s*\)/g;
    let connMatch: RegExpExecArray | null;
    while ((connMatch = connRegex.exec(portStr)) !== null) {
      const portName = connMatch[1];
      const netName = connMatch[2];
      connections[portName] = netName;

      // Register terminal on the net
      if (!nets.has(netName)) {
        nets.set(netName, { name: netName, terminals: [] });
      }
      nets.get(netName)!.terminals.push({
        instance: instName,
        port: portName,
      });
    }

    instances.push({
      name: instName,
      cellType,
      connections,
    });
  }

  return {
    instances,
    nets: Array.from(nets.values()),
  };
}

/**
 * Extract a list of unique wire names from the netlist.
 * Useful as a pre-pass before full parse.
 */
export function extractWireNames(source: string): string[] {
  const names = new Set<string>();
  const wireRegex = /\bwire\s+((?:\s*(?:\w+)\s*,?\s*)+)\s*;/g;
  const clean = source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '');
  let match: RegExpExecArray | null;
  while ((match = wireRegex.exec(clean)) !== null) {
    for (const name of match[1].split(',')) {
      const trimmed = name.trim();
      if (trimmed) names.add(trimmed);
    }
  }
  return Array.from(names);
}

/**
 * Validate that all cell types referenced by instances exist in the given set.
 * Returns list of missing cell types.
 */
export function validateCellTypes(
  netlist: ParsedNetlist,
  knownCellTypes: Set<string>,
): string[] {
  const missing = new Set<string>();
  for (const inst of netlist.instances) {
    if (!knownCellTypes.has(inst.cellType)) {
      missing.add(inst.cellType);
    }
  }
  return Array.from(missing);
}
