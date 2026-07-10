// ============================================================================
// Verilog flat structural netlist parser
// Handles: wire/bus declarations, escaped identifiers, constants, bit-selects
// Supports Yosys-generated structural Verilog output
// ============================================================================

import type { ParsedNetlist, NetlistInstance, NetlistNet } from '@/types';

/** Check if a port connection value is a Verilog constant (not a net) */
function isVerilogConstant(value: string): boolean {
  // Matches: 1'h0, 1'b1, 4'0011, 12'h000, 1'd1, 32'd1, etc.
  return /^\d+'[bhod]\w+$/i.test(value);
}

/** Get the base net name from an expression that may include bit-select or part-select */
function extractBaseNetName(expr: string): string {
  const m = expr.match(/^(\w+)(?:\s*\[[^\]]*\])?\s*$/);
  return m ? m[1] : expr;
}

/**
 * Parse a flat structural Verilog netlist.
 * Supports:
 *   wire [WIDTH:0] name1, name2, ...;
 *   wire name1, name2, ...;
 *   CELL_TYPE instance_name (.port(expr), ...);
 *   \escaped$cell_type  instance_name (.port(expr), ...);
 */
export function parseVerilogNetlist(source: string): ParsedNetlist {
  const instances: NetlistInstance[] = [];
  const nets: Map<string, NetlistNet> = new Map();

  // Remove block comments and line comments
  const clean = source
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/\/\/.*$/gm, '');

  // Match wire/bus declarations:
  // wire [WIDTH:0] name1, name2, ...;
  // wire name1, name2, ...;
  const wireRegex = /\bwire\s+(?:\[[^\]]*\]\s*)?((?:\s*(?:\w+)\s*,?\s*)+)\s*;/g;
  let wireMatch: RegExpExecArray | null;
  while ((wireMatch = wireRegex.exec(clean)) !== null) {
    const names = wireMatch[1].split(',').map(s => s.trim()).filter(Boolean);
    for (const name of names) {
      if (!nets.has(name)) {
        nets.set(name, { name, terminals: [] });
      }
    }
  }

  // Match instance declarations.
  // Two patterns:
  //   1. \escaped\cell\type  instance_name ( ... );  — escaped cell type
  //   2. CELL_TYPE instance_name ( ... );             — regular cell type
  //
  // Escaped Verilog identifiers start with backslash and end at whitespace.
  // Yosys generates identifiers like: \$paramod\Module\PARAM=val
  // We match the entire escaped identifier (including internal backslashes)
  // up to the whitespace before the instance name.

  // First pass: find all instance start positions with \escaped or regular types
  const instanceStarts: { index: number; cellType: string; instName: string }[] = [];

  // Pattern for escaped cell type: \S+  identifier  (
  const escapedRegex = /\\([^\s\\]+(?:\s*\\[^\s\\]+)*)\s+(\w+)\s*\(/g;
  let escMatch: RegExpExecArray | null;
  while ((escMatch = escapedRegex.exec(clean)) !== null) {
    instanceStarts.push({
      index: escMatch.index,
      cellType: escMatch[0].slice(0, escMatch[0].lastIndexOf(escMatch[2])).trim(),
      instName: escMatch[2],
    });
  }

  // Pattern for regular cell type: WORD WORD (  but exclude keywords
  const keywords = new Set([
    'module', 'endmodule', 'input', 'output', 'inout', 'wire',
    'reg', 'assign', 'always', 'if', 'else', 'for', 'while',
    'begin', 'end', 'case', 'endcase', 'parameter', 'localparam',
    'function', 'endfunction', 'task', 'endtask', 'generate', 'endgenerate',
    'specify', 'endspecify', 'genvar', 'integer', 'real', 'time',
  ]);
  const regularRegex = /(\w+)\s+(\w+)\s*\(/g;
  let regMatch: RegExpExecArray | null;
  while ((regMatch = regularRegex.exec(clean)) !== null) {
    const type = regMatch[1];
    if (keywords.has(type)) continue;
    // Detect if we're inside an escaped Verilog identifier (\escaped...)
    // Escaped IDs start with backslash and end at whitespace
    const before = clean.slice(Math.max(0, regMatch.index - 200), regMatch.index);
    const lastNewline = before.lastIndexOf('\n');
    const chunk = before.slice(lastNewline + 1);
    const openEsc = chunk.lastIndexOf('\\');
    if (openEsc !== -1) {
      const afterEsc = chunk.slice(openEsc + 1);
      if (/^\S+$/.test(afterEsc)) continue; // still inside escaped identifier
    }
    instanceStarts.push({
      index: regMatch.index,
      cellType: type,
      instName: regMatch[2],
    });
  }

  // Sort by position, deduplicate
  instanceStarts.sort((a, b) => a.index - b.index);
  const seen = new Set<number>();
  const uniqueStarts = instanceStarts.filter(s => {
    if (seen.has(s.index)) return false;
    seen.add(s.index);
    return true;
  });

  // For each instance start, find the matching closing paren + semicolon
  for (const start of uniqueStarts) {
    const afterParen = clean.indexOf('(', start.index);
    if (afterParen === -1) continue;

    // Find matching ) using paren counting
    let depth = 0;
    let closeIdx = -1;
    for (let i = afterParen; i < clean.length; i++) {
      if (clean[i] === '(') depth++;
      else if (clean[i] === ')') {
        depth--;
        if (depth === 0) { closeIdx = i; break; }
      }
    }
    if (closeIdx === -1) continue;
    // Verify semicolon follows
    const afterClose = clean.slice(closeIdx + 1).search(/[^\s]/);
    if (afterClose === -1 || clean[closeIdx + 1 + afterClose] !== ';') continue;

    const portStr = clean.slice(afterParen + 1, closeIdx);

    const connections: Record<string, string> = {};
    const connRegex = /\.(\w+)\s*\(\s*([^)]+?)\s*\)/g;
    let connMatch: RegExpExecArray | null;
    while ((connMatch = connRegex.exec(portStr)) !== null) {
      const portName = connMatch[1];
      const netExpr = connMatch[2].trim();
      connections[portName] = netExpr;

      // Register terminal on the net — skip constants
      if (!isVerilogConstant(netExpr)) {
        const baseNet = extractBaseNetName(netExpr);
        if (!nets.has(baseNet)) {
          nets.set(baseNet, { name: baseNet, terminals: [] });
        }
        nets.get(baseNet)!.terminals.push({
          instance: start.instName,
          port: portName,
        });
      }
    }

    instances.push({
      name: start.instName,
      cellType: start.cellType,
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
 */
export function extractWireNames(source: string): string[] {
  const names = new Set<string>();
  const clean = source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '');
  const wireRegex = /\bwire\s+(?:\[[^\]]*\]\s*)?((?:\s*(?:\w+)\s*,?\s*)+)\s*;/g;
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
