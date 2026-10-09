// ============================================================================
// Verilog parser tests — hierarchical elaboration
//   hier.v           hand-written: exact nets, constants, keep, black boxes
//   IpLine_synth.v   real Yosys output; checked against IpLine_flat.v, the
//                    same design flattened by Yosys itself
// ============================================================================

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { join } from 'path';
import {
  parseVerilogNetlist,
  parseVerilogSource,
  summarizeDesign,
  baseModuleName,
  extractWireNames,
  validateCellTypes,
  VerilogParseError,
} from '@/services/parsers/verilog';
import type { ParsedNetlist } from '@/types';

const fixture = (name: string) => readFileSync(join(__dirname, '..', 'fixtures', name), 'utf-8');

const HIER = fixture('hier.v');
const PAIR = "$paramod\\Pair\\W=32'00000000000000000000000000000010";

/** Net name and sorted terminals of the net on `instance.port` */
function netOf(n: ParsedNetlist, instance: string, port: string) {
  const net = n.nets.find(x => x.terminals.some(t => t.instance === instance && t.port === port));
  return net && { name: net.name, terminals: net.terminals.map(t => `${t.instance}.${t.port}`).sort() };
}

describe('parseVerilogNetlist — hand-written hierarchy', () => {
  const n = parseVerilogNetlist(HIER);

  it('picks the top module, ignoring unused black boxes', () => {
    expect(n.top).toBe('Top');
  });

  it('expands submodules into leaves with /-separated paths', () => {
    expect(n.instances.map(i => i.name).sort()).toEqual([
      'p0/g[0].u', 'p0/g[1].u', 'p0/inv0', 'p0/s',
      'p1/g[0].u', 'p1/g[1].u', 'p1/inv0', 'p1/s',
      'r',
    ]);
  });

  it('keeps black-box modules as leaves', () => {
    expect(n.instances.find(i => i.name === 'p0/s')?.cellType).toBe('Stub');
  });

  it('connects nets across module ports', () => {
    expect(netOf(n, 'r', 'C')).toEqual({
      name: 'clk',
      terminals: ['p0/g[0].u.B', 'p0/g[1].u.B', 'r.C'],
    });
    expect(netOf(n, 'p0/inv0', 'Y')).toEqual({ name: 'w[0]', terminals: ['p0/inv0.Y', 'r.D[0]'] });
  });

  it('merges nets through assign and prefers user names over Yosys _N_', () => {
    expect(netOf(n, 'p0/s', 'a')).toEqual({ name: 'p0/mid[1]', terminals: ['p0/g[1].u.Y', 'p0/s.a'] });
  });

  it('keeps same-named nets of different instances apart', () => {
    expect(netOf(n, 'p0/inv0', 'A')?.name).toBe('p0/mid[0]');
    expect(netOf(n, 'p1/inv0', 'A')?.name).toBe('p1/mid[0]');
  });

  it('binds bus bits through part-selects and concatenations', () => {
    expect(netOf(n, 'p1/g[1].u', 'A')?.name).toBe('d[3]');
    expect(netOf(n, 'p1/g[0].u', 'A')?.name).toBe('d[2]');
    expect(netOf(n, 'p1/s', 'y')).toEqual({ name: 'w[3]', terminals: ['p1/s.y', 'r.D[3]'] });
  });

  it('names pins of undefined multi-bit cells by connection width', () => {
    expect(Object.keys(n.instances.find(i => i.name === 'r')!.connections))
      .toEqual(['D[3]', 'D[2]', 'D[1]', 'D[0]', 'C', 'Q[3]', 'Q[2]', 'Q[1]', 'Q[0]']);
  });

  it('records constants instead of nets', () => {
    expect(n.instances.find(i => i.name === 'p1/g[0].u')?.connections.B).toBe("1'b1");
    expect(n.nets.some(x => x.terminals.some(t => t.instance === 'p1/g[0].u' && t.port === 'B'))).toBe(false);
  });

  it('lists top-level port bits with their nets', () => {
    expect(n.ports).toContainEqual({ name: 'tie', direction: 'output', net: "1'b0" });
    expect(n.ports).toContainEqual({ name: 'q[3]', direction: 'output', net: 'q[3]' });
    expect(n.ports).toHaveLength(1 + 4 + 4 + 1);
  });
});

describe('parseVerilogNetlist — keep', () => {
  const n = parseVerilogNetlist(HIER, { keep: ['Pair'] });

  it('keeps a submodule as one instance with its base name and full module name', () => {
    expect(n.instances.map(i => i.name)).toEqual(['p0', 'p1', 'r']);
    expect(n.instances[0]).toMatchObject({ cellType: 'Pair', module: PAIR });
    expect(n.keep).toEqual(['Pair']);
  });

  it('names kept-module pins by their declared bits', () => {
    expect(n.instances[1].connections).toEqual({
      'in[1]': 'd[3]', 'in[0]': 'd[2]', 'out[1]': 'w[3]', 'out[0]': 'w[2]', en: "1'b1",
    });
  });
});

describe('parseVerilogNetlist — errors', () => {
  it('rejects behavioral code with a line number', () => {
    expect(() => parseVerilogNetlist('module m(a);\n  input a;\n  always @(a) begin end\nendmodule'))
      .toThrow(/line 3: 'always' is not supported/);
  });

  it('asks for a top when several modules qualify', () => {
    const src = 'module a(); X u(); endmodule\nmodule b(); X u(); endmodule';
    expect(() => parseVerilogNetlist(src)).toThrow(VerilogParseError);
    expect(parseVerilogNetlist(src, { top: 'b' }).top).toBe('b');
  });
});

describe('summarizeDesign', () => {
  const s = summarizeDesign(parseVerilogSource(HIER));

  it('lists modules used below the top, by base name', () => {
    expect(s.modules.map(m => [m.baseName, m.uses, m.blackBox])).toEqual([
      ['Pair', 2, false],
      ['Stub', 2, true],
    ]);
  });

  it('gives port bits for element pins', () => {
    expect(s.modules[0].pins.map(p => p.name)).toEqual(['in[1]', 'in[0]', 'out[1]', 'out[0]', 'en']);
    expect(s.modules[1].pins).toEqual([
      { name: 'a', direction: 'input' },
      { name: 'y', direction: 'output' },
    ]);
  });
});

describe('baseModuleName', () => {
  it('strips Yosys parameterization', () => {
    expect(baseModuleName('$paramod$1e37\\DekatronTubeV2')).toBe('DekatronTubeV2');
    expect(baseModuleName("$paramod\\OneShot\\DELAY=32'0110")).toBe('OneShot');
    expect(baseModuleName('NAND2_J2')).toBe('NAND2_J2');
  });
});

// ---------------------------------------------------------------------------
// Real netlist
// ---------------------------------------------------------------------------

describe('parseVerilogNetlist — IpLine_synth.v', () => {
  const n = parseVerilogNetlist(fixture('IpLine_synth.v'), { top: 'IpLine' });

  it('expands to the same leaf cells as Yosys flatten', () => {
    const count = (type: string) => n.instances.filter(i => i.cellType === type).length;
    expect(n.instances).toHaveLength(414);
    expect(count('NOR2_N16')).toBe(74);
    expect(count('DFFSR_n')).toBe(35);
    expect(count('Dekatron')).toBe(7);
    expect(count('OneShot')).toBe(30);
  });

  it('has exactly the connectivity of the Yosys-flattened netlist', () => {
    const flat = parseVerilogNetlist(fixture('IpLine_flat.v'));
    /** pin → sorted pins of its net (or the constant it is tied to) */
    const partition = (x: ParsedNetlist, norm: (s: string) => string) => {
      const sig = new Map<string, string>();
      for (const net of x.nets) {
        const pins = net.terminals.map(t => `${norm(t.instance)}:${t.port}`).sort();
        for (const p of pins) sig.set(p, pins.join(' '));
      }
      for (const i of x.instances) {
        for (const [pin, v] of Object.entries(i.connections)) {
          if (v.startsWith("1'")) sig.set(`${norm(i.name)}:${pin}`, v);
        }
      }
      return sig;
    };
    // Yosys joins hierarchy levels with '.', the parser with '/'
    const ours = partition(n, s => s.replace(/\//g, '.'));
    const ref = partition(flat, s => s);
    expect(ours.size).toBe(ref.size);
    for (const [pin, sig] of ref) expect(ours.get(pin), pin).toBe(sig);
  });

  it('keeps DekatronModule as one board when asked', () => {
    const k = parseVerilogNetlist(fixture('IpLine_synth.v'), { keep: ['DekatronModule'] });
    expect(k.instances.filter(i => i.cellType === 'DekatronModule')).toHaveLength(7);
    expect(k.instances.some(i => i.name.includes('/') && i.cellType === 'Dekatron')).toBe(false);
  });
});

describe('extractWireNames', () => {
  it('extracts 150+ wire names', () => {
    expect(extractWireNames(fixture('IpLine_synth.v')).length).toBeGreaterThan(150);
  });
});

describe('validateCellTypes', () => {
  it('reports leaf types missing from the known set', () => {
    const n = parseVerilogNetlist(HIER);
    expect(validateCellTypes(n, new Set(['NAND2', 'NOT'])).sort()).toEqual(['REG4', 'Stub']);
  });
});
