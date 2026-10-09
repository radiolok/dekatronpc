// ============================================================================
// Verilog structural netlist parser (Yosys write_verilog output)
//
// Two stages:
//   parseVerilogSource()  source → modules (ports, wires, assigns, instances)
//   elaborateNetlist()    modules → one bit-level netlist of leaf instances
//
// The netlist is hierarchical (no `flatten`, agents.md §3.2). Elaboration starts
// at the top module and expands submodules down to leaves. A leaf is
//   - a cell type with no module definition (liberty cell),
//   - a module with no instances inside (a Yosys black box: DekatronTubeV2,
//     OneShot, Impulse — base elements, Q11),
//   - a module listed in `keep` (a submodule that is one board, e.g.
//     DekatronModule, Q3/Q7).
// Leaf instances get hierarchical paths joined with '/'. Nets are bit-level
// (a bus bit is its own wire) and merged across ports and `assign`s.
// ============================================================================

import type { ParsedNetlist, NetlistInstance, NetlistNet, NetlistPort, PinDirection } from '@/types';

export class VerilogParseError extends Error {
  constructor(message: string, public line?: number) {
    super(line !== undefined ? `line ${line}: ${message}` : message);
    this.name = 'VerilogParseError';
  }
}

// ---------------------------------------------------------------------------
// Tokenizer
// ---------------------------------------------------------------------------

interface Token {
  kind: 'id' | 'num' | 'const' | 'sym';
  value: string;
  line: number;
}

/** Blank out comments and (* attributes *), keeping newlines for line numbers */
function stripComments(source: string): string {
  const blank = (m: string) => m.replace(/[^\n]/g, ' ');
  return source
    .replace(/\/\*[\s\S]*?\*\//g, blank)
    .replace(/\/\/[^\n]*/g, blank)
    .replace(/\(\*[\s\S]*?\*\)/g, blank);
}

function tokenize(source: string): Token[] {
  const src = stripComments(source);
  const tokens: Token[] = [];
  const re = /(\s+)|\\(\S+)|([A-Za-z_][\w$]*)|((?:\d+)?\s*'[sS]?[bBoOdDhH]\s*[0-9a-fA-FxXzZ_?]+)|(\d+)|([()[\]{},;.:=#])|(.)/gy;
  let line = 1;
  let m: RegExpExecArray | null;
  while ((m = re.exec(src)) !== null) {
    if (m[1] !== undefined) {
      for (const c of m[1]) if (c === '\n') line++;
    } else if (m[2] !== undefined) {
      tokens.push({ kind: 'id', value: m[2], line });
    } else if (m[3] !== undefined) {
      tokens.push({ kind: 'id', value: m[3], line });
    } else if (m[4] !== undefined) {
      tokens.push({ kind: 'const', value: m[4].replace(/\s+/g, ''), line });
    } else if (m[5] !== undefined) {
      tokens.push({ kind: 'num', value: m[5], line });
    } else if (m[6] !== undefined) {
      tokens.push({ kind: 'sym', value: m[6], line });
    } else {
      // Left to the parser, which reports it in context ('always @', etc.)
      tokens.push({ kind: 'sym', value: m[7], line });
    }
  }
  return tokens;
}

// ---------------------------------------------------------------------------
// Source model
// ---------------------------------------------------------------------------

interface Range { msb: number; lsb: number }

/** One element of an expression; an expression is a list of these, MSB first */
type ExprPart =
  | { kind: 'ref'; name: string; range?: Range }
  | { kind: 'const'; bits: string[] };   // '0' | '1' | 'x' | 'z', MSB first

type Expr = ExprPart[];

export interface VerilogInstance {
  type: string;
  name: string;
  /** Named connections (port → expression, null for `.port()`) */
  named: Map<string, Expr | null> | null;
  /** Positional connections, when the instance uses them */
  positional: Expr[] | null;
  line: number;
}

export interface VerilogModule {
  name: string;
  /** Header port order */
  ports: string[];
  directions: Map<string, PinDirection>;
  /** Declared bus ranges; names absent here are scalar */
  ranges: Map<string, Range>;
  assigns: [Expr, Expr][];
  instances: VerilogInstance[];
  line: number;
}

export interface VerilogDesign {
  modules: Map<string, VerilogModule>;
}

const UNSUPPORTED = new Set([
  'always', 'always_ff', 'always_comb', 'initial', 'function', 'task',
  'generate', 'specify', 'defparam', 'primitive',
]);
const SKIPPED_DECLS = new Set(['parameter', 'localparam', 'genvar', 'integer', 'real', 'time']);

class Parser {
  private pos = 0;
  constructor(private tokens: Token[]) {}

  private peek(offset = 0): Token | undefined {
    return this.tokens[this.pos + offset];
  }

  private next(): Token {
    const t = this.tokens[this.pos++];
    if (!t) throw new VerilogParseError('unexpected end of file', this.tokens.at(-1)?.line);
    return t;
  }

  private isSym(v: string, offset = 0): boolean {
    const t = this.peek(offset);
    return t?.kind === 'sym' && t.value === v;
  }

  private expectSym(v: string): Token {
    const t = this.next();
    if (t.kind !== 'sym' || t.value !== v) {
      throw new VerilogParseError(`expected '${v}', found '${t.value}'`, t.line);
    }
    return t;
  }

  private expectId(): string {
    const t = this.next();
    if (t.kind !== 'id') throw new VerilogParseError(`expected identifier, found '${t.value}'`, t.line);
    return t.value;
  }

  private expectNum(): number {
    const t = this.next();
    if (t.kind !== 'num') throw new VerilogParseError(`expected number, found '${t.value}'`, t.line);
    return parseInt(t.value, 10);
  }

  /** Skip a balanced (...) group starting at the current '(' */
  private skipParens(): void {
    let depth = 0;
    do {
      const t = this.next();
      if (t.kind === 'sym' && t.value === '(') depth++;
      else if (t.kind === 'sym' && t.value === ')') depth--;
    } while (depth > 0);
  }

  private skipToSemicolon(): void {
    while (!this.isSym(';')) this.next();
    this.next();
  }

  parseDesign(): VerilogDesign {
    const modules = new Map<string, VerilogModule>();
    while (this.peek()) {
      const t = this.next();
      if (t.kind === 'id' && (t.value === 'module' || t.value === 'macromodule')) {
        const mod = this.parseModule(t.line);
        if (modules.has(mod.name)) throw new VerilogParseError(`module '${mod.name}' defined twice`, t.line);
        modules.set(mod.name, mod);
      } else {
        throw new VerilogParseError(`expected 'module', found '${t.value}'`, t.line);
      }
    }
    return { modules };
  }

  private parseRange(): Range {
    this.expectSym('[');
    const msb = this.expectNum();
    this.expectSym(':');
    const lsb = this.expectNum();
    this.expectSym(']');
    return { msb, lsb };
  }

  private parseModule(line: number): VerilogModule {
    const mod: VerilogModule = {
      name: this.expectId(),
      ports: [],
      directions: new Map(),
      ranges: new Map(),
      assigns: [],
      instances: [],
      line,
    };
    if (this.isSym('#')) {
      this.next();
      this.skipParens();
    }
    if (this.isSym('(')) {
      this.next();
      while (!this.isSym(')')) {
        // ANSI headers (input [3:0] a) are accepted as well as plain name lists
        const t = this.peek()!;
        if (t.kind === 'id' && (t.value === 'input' || t.value === 'output' || t.value === 'inout')) {
          this.parseDeclaration(mod, true);
        } else {
          mod.ports.push(this.expectId());
          if (this.isSym(',')) this.next();
        }
      }
      this.next();
    }
    this.expectSym(';');

    for (;;) {
      const t = this.next();
      if (t.kind !== 'id') throw new VerilogParseError(`unexpected '${t.value}'`, t.line);
      switch (t.value) {
        case 'endmodule':
          return mod;
        case 'input':
        case 'output':
        case 'inout':
          this.pos--;
          this.parseDeclaration(mod, false);
          break;
        case 'wire':
        case 'reg':
        case 'tri':
        case 'logic':
          this.parseNetDeclaration(mod);
          break;
        case 'assign':
          this.parseAssign(mod);
          break;
        default:
          if (UNSUPPORTED.has(t.value)) {
            throw new VerilogParseError(`'${t.value}' is not supported: the netlist must be structural`, t.line);
          }
          if (SKIPPED_DECLS.has(t.value)) {
            this.skipToSemicolon();
            break;
          }
          mod.instances.push(this.parseInstance(t.value, t.line));
      }
    }
  }

  /** input/output/inout [wire|reg] [range] names — inside a header stops at ',' before the next direction */
  private parseDeclaration(mod: VerilogModule, inHeader: boolean): void {
    const dir = this.next().value as PinDirection;
    if (this.peek()?.kind === 'id' && ['wire', 'reg', 'logic', 'tri'].includes(this.peek()!.value)) this.next();
    const range = this.isSym('[') ? this.parseRange() : undefined;
    for (;;) {
      const name = this.expectId();
      mod.directions.set(name, dir);
      if (range) mod.ranges.set(name, range);
      if (inHeader) mod.ports.push(name);
      if (!this.isSym(',')) break;
      // In an ANSI header a direction keyword after ',' starts a new declaration
      const after = this.peek(1);
      if (inHeader && after?.kind === 'id' && ['input', 'output', 'inout'].includes(after.value)) {
        this.next();
        return;
      }
      this.next();
    }
    if (!inHeader) this.expectSym(';');
  }

  private parseNetDeclaration(mod: VerilogModule): void {
    const range = this.isSym('[') ? this.parseRange() : undefined;
    for (;;) {
      const name = this.expectId();
      if (range) mod.ranges.set(name, range);
      if (this.isSym('=')) {
        this.next();
        mod.assigns.push([[{ kind: 'ref', name }], this.parseExpr()]);
      }
      if (!this.isSym(',')) break;
      this.next();
    }
    this.expectSym(';');
  }

  private parseAssign(mod: VerilogModule): void {
    for (;;) {
      const lhs = this.parseExpr();
      this.expectSym('=');
      mod.assigns.push([lhs, this.parseExpr()]);
      if (!this.isSym(',')) break;
      this.next();
    }
    this.expectSym(';');
  }

  private parseInstance(type: string, line: number): VerilogInstance {
    if (this.isSym('#')) {
      this.next();
      this.skipParens();
    }
    const name = this.expectId();
    if (this.isSym('[')) {
      throw new VerilogParseError(`instance arrays are not supported (${name})`, line);
    }
    this.expectSym('(');
    const inst: VerilogInstance = { type, name, named: null, positional: null, line };
    if (this.isSym('.')) {
      inst.named = new Map();
      while (this.isSym('.')) {
        this.next();
        const port = this.expectId();
        this.expectSym('(');
        const expr = this.isSym(')') ? null : this.parseExpr();
        this.expectSym(')');
        inst.named.set(port, expr);
        if (!this.isSym(',')) break;
        this.next();
      }
    } else if (!this.isSym(')')) {
      inst.positional = [];
      for (;;) {
        inst.positional.push(this.isSym(',') || this.isSym(')') ? [] : this.parseExpr());
        if (!this.isSym(',')) break;
        this.next();
      }
    }
    this.expectSym(')');
    this.expectSym(';');
    return inst;
  }

  private parseExpr(): Expr {
    const t = this.next();
    if (t.kind === 'const') return [{ kind: 'const', bits: constantBits(t.value, t.line) }];
    if (t.kind === 'num') return [{ kind: 'const', bits: toBits(BigInt(t.value), 32) }];
    if (t.kind === 'id') {
      if (!this.isSym('[')) return [{ kind: 'ref', name: t.value }];
      this.next();
      const msb = this.expectNum();
      let lsb = msb;
      if (this.isSym(':')) {
        this.next();
        lsb = this.expectNum();
      }
      this.expectSym(']');
      return [{ kind: 'ref', name: t.value, range: { msb, lsb } }];
    }
    if (t.kind === 'sym' && t.value === '{') {
      // Replication: { N { expr } }
      if (this.peek()?.kind === 'num' && this.isSym('{', 1)) {
        const n = this.expectNum();
        this.expectSym('{');
        const inner = this.parseExpr();
        this.expectSym('}');
        this.expectSym('}');
        return Array.from({ length: n }, () => inner).flat();
      }
      const parts: Expr = [];
      for (;;) {
        parts.push(...this.parseExpr());
        if (!this.isSym(',')) break;
        this.next();
      }
      this.expectSym('}');
      return parts;
    }
    throw new VerilogParseError(`unexpected '${t.value}' in expression`, t.line);
  }
}

function toBits(value: bigint, width: number): string[] {
  const bits: string[] = [];
  for (let i = width - 1; i >= 0; i--) bits.push(((value >> BigInt(i)) & 1n) ? '1' : '0');
  return bits;
}

/** 4'b01x0, 1'h0, 30'h00000000, 32'd1 → bits MSB first */
function constantBits(text: string, line: number): string[] {
  const m = text.match(/^(\d*)'[sS]?([bBoOdDhH])([0-9a-fA-FxXzZ_?]+)$/);
  if (!m) throw new VerilogParseError(`bad constant '${text}'`, line);
  const width = m[1] ? parseInt(m[1], 10) : 32;
  const base = m[2].toLowerCase();
  const digits = m[3].replace(/_/g, '').toLowerCase();
  let bits: string[];
  if (base === 'd') {
    bits = /[xz?]/.test(digits) ? Array(width).fill('x') : toBits(BigInt(digits), width);
  } else {
    const per = base === 'b' ? 1 : base === 'o' ? 3 : 4;
    bits = [];
    for (const d of digits) {
      if (d === 'x' || d === 'z' || d === '?') {
        for (let i = 0; i < per; i++) bits.push(d === '?' ? 'z' : d);
      } else {
        bits.push(...parseInt(d, 16).toString(2).padStart(per, '0').split(''));
      }
    }
  }
  // Fit to width: truncate MSBs or extend (x/z extend with themselves, else 0)
  if (bits.length > width) return bits.slice(bits.length - width);
  const fill = bits[0] === 'x' || bits[0] === 'z' ? bits[0] : '0';
  return [...Array(width - bits.length).fill(fill), ...bits];
}

/** Parse Verilog source into modules, without elaborating */
export function parseVerilogSource(source: string): VerilogDesign {
  return new Parser(tokenize(source)).parseDesign();
}

// ---------------------------------------------------------------------------
// Module names
// ---------------------------------------------------------------------------

/**
 * Module name without Yosys parameterization:
 *   $paramod$1e37…\DekatronTubeV2       → DekatronTubeV2
 *   $paramod\OneShot\DELAY=32'000…0110  → OneShot
 *   NAND2_N16X7                         → NAND2_N16X7
 */
export function baseModuleName(name: string): string {
  if (!name.startsWith('$paramod')) return name;
  return name.split('\\')[1] || name;
}

/** Bit names of a declared signal, MSB first: ["In[3]", …, "In[0]"] or ["En"] */
function declaredBits(mod: VerilogModule | undefined, name: string): string[] {
  const r = mod?.ranges.get(name);
  if (!r) return [name];
  const step = r.msb >= r.lsb ? -1 : 1;
  const out: string[] = [];
  for (let i = r.msb; ; i += step) {
    out.push(`${name}[${i}]`);
    if (i === r.lsb) break;
  }
  return out;
}

/** Bit names an expression part refers to, MSB first */
function partBitNames(mod: VerilogModule, part: Extract<ExprPart, { kind: 'ref' }>): string[] {
  if (!part.range) return declaredBits(mod, part.name);
  const { msb, lsb } = part.range;
  const step = msb >= lsb ? -1 : 1;
  const out: string[] = [];
  for (let i = msb; ; i += step) {
    out.push(`${part.name}[${i}]`);
    if (i === lsb) break;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Elaboration
// ---------------------------------------------------------------------------

export interface ElaborateOptions {
  /** Top module (full or base name). Default: the only module not instantiated by another */
  top?: string;
  /** Base (or full) module names kept as one leaf instance instead of being expanded */
  keep?: Iterable<string>;
}

/** Union-find over bit nodes */
class Nets {
  parent: number[] = [];
  keys: string[] = [];
  private ids = new Map<string, number>();

  id(key: string): number {
    let id = this.ids.get(key);
    if (id === undefined) {
      id = this.parent.length;
      this.ids.set(key, id);
      this.parent.push(id);
      this.keys.push(key);
    }
    return id;
  }

  find(a: number): number {
    while (this.parent[a] !== a) {
      this.parent[a] = this.parent[this.parent[a]];
      a = this.parent[a];
    }
    return a;
  }

  union(a: number, b: number): void {
    const ra = this.find(a);
    const rb = this.find(b);
    if (ra !== rb) this.parent[rb] = ra;
  }
}

/** Constant nodes have keys that cannot clash with a hierarchical bit name */
const CONST_KEY = (bit: string) => `\0${bit}`;
const CONST_VALUE: Record<string, string> = { '0': "1'b0", '1': "1'b1", x: "1'bx", z: "1'bz" };

/** Choose the top module */
function findTop(design: VerilogDesign, hint?: string): VerilogModule {
  const mods = [...design.modules.values()];
  if (mods.length === 0) throw new VerilogParseError('no module found');
  if (hint) {
    const exact = design.modules.get(hint) ?? mods.find(m => baseModuleName(m.name) === hint);
    if (exact) return exact;
  }
  const used = new Set(mods.flatMap(m => m.instances.map(i => i.type)));
  let roots = mods.filter(m => !used.has(m.name));
  // Unused black-box stubs are not top candidates
  if (roots.some(m => m.instances.length > 0)) roots = roots.filter(m => m.instances.length > 0);
  if (roots.length === 1) return roots[0];
  if (roots.length === 0) throw new VerilogParseError('no top module: every module is instantiated by another');
  throw new VerilogParseError(
    `several top-level modules (${roots.map(m => baseModuleName(m.name)).join(', ')}); choose one`,
  );
}

/** Lower is a better net name: shallow, user-named (not Yosys _123_ / $auto), short */
function nameScore(key: string): [number, number, number] {
  const depth = key.split('/').length - 1;
  const leaf = key.slice(key.lastIndexOf('/') + 1);
  const auto = /^_\d+_(\[\d+\])?$/.test(leaf) || leaf.includes('$') ? 1 : 0;
  return [depth, auto, key.length];
}

function better(a: string, b: string): boolean {
  const sa = nameScore(a);
  const sb = nameScore(b);
  for (let i = 0; i < 3; i++) if (sa[i] !== sb[i]) return sa[i] < sb[i];
  return a < b;
}

/**
 * Elaborate a parsed design into a bit-level netlist of leaf instances.
 */
export function elaborateNetlist(design: VerilogDesign, options: ElaborateOptions = {}): ParsedNetlist {
  const top = findTop(design, options.top);
  const keep = new Set(options.keep ?? []);
  const nets = new Nets();
  const leaves: { name: string; type: string; ports: [string, number][] }[] = [];

  const isLeaf = (type: string): boolean => {
    const mod = design.modules.get(type);
    return !mod || mod.instances.length === 0 || keep.has(type) || keep.has(baseModuleName(type));
  };

  /** Node ids of an expression in scope `prefix`, MSB first */
  const exprNodes = (mod: VerilogModule, prefix: string, expr: Expr): number[] =>
    expr.flatMap(part => part.kind === 'const'
      ? part.bits.map(b => nets.id(CONST_KEY(b)))
      : partBitNames(mod, part).map(n => nets.id(prefix + n)));

  /** Union two node lists aligned at the LSB (extra bits on either side stay unconnected) */
  const connect = (a: number[], b: number[]) => {
    const n = Math.min(a.length, b.length);
    for (let i = 1; i <= n; i++) nets.union(a[a.length - i], b[b.length - i]);
  };

  /** Connections of an instance as port → expression */
  const connectionsOf = (inst: VerilogInstance, child: VerilogModule | undefined): [string, Expr][] => {
    if (inst.named) {
      return [...inst.named].filter((c): c is [string, Expr] => c[1] !== null);
    }
    if (!inst.positional) return [];
    if (!child) {
      throw new VerilogParseError(`positional connections on '${inst.name}' need a definition of '${inst.type}'`, inst.line);
    }
    return inst.positional
      .map((e, i): [string, Expr] => [child.ports[i], e])
      .filter(([port, e]) => port !== undefined && e.length > 0);
  };

  const elaborate = (mod: VerilogModule, prefix: string, stack: string[]) => {
    for (const [lhs, rhs] of mod.assigns) {
      connect(exprNodes(mod, prefix, lhs), exprNodes(mod, prefix, rhs));
    }
    for (const inst of mod.instances) {
      const path = prefix + inst.name;
      const child = design.modules.get(inst.type);
      const conns = connectionsOf(inst, child);

      if (isLeaf(inst.type)) {
        const ports: [string, number][] = [];
        for (const [port, expr] of conns) {
          const nodes = exprNodes(mod, prefix, expr);
          // Pin names: declared bits for defined modules, else [w-1..0] by connection width
          const pins = child?.directions.has(port) || child?.ranges.has(port)
            ? declaredBits(child, port)
            : nodes.length === 1 ? [port] : nodes.map((_, i) => `${port}[${nodes.length - 1 - i}]`);
          // Align at the LSB; extra bits on either side stay unconnected
          const n = Math.min(pins.length, nodes.length);
          for (let i = n; i >= 1; i--) ports.push([pins[pins.length - i], nodes[nodes.length - i]]);
        }
        leaves.push({ name: path, type: inst.type, ports });
        continue;
      }

      if (stack.includes(inst.type)) {
        throw new VerilogParseError(`recursive instantiation of '${inst.type}'`, inst.line);
      }
      const childPrefix = `${path}/`;
      for (const [port, expr] of conns) {
        connect(
          declaredBits(child, port).map(n => nets.id(childPrefix + n)),
          exprNodes(mod, prefix, expr),
        );
      }
      elaborate(child!, childPrefix, [...stack, inst.type]);
    }
  };

  // Top-level ports exist as nodes even if nothing inside uses them
  const topPorts = top.ports.flatMap(p => declaredBits(top, p).map(bit => ({
    bit,
    direction: top.directions.get(p) ?? 'inout',
    node: nets.id(bit),
  })));
  elaborate(top, '', [top.name]);

  // Constant groups
  const constOf = new Map<number, string>();
  for (const bit of ['0', '1', 'x', 'z']) {
    const key = CONST_KEY(bit);
    const root = nets.find(nets.id(key));
    if (!constOf.has(root)) constOf.set(root, CONST_VALUE[bit]);
  }

  // Best name per group
  const nameOf = new Map<number, string>();
  for (let id = 0; id < nets.keys.length; id++) {
    const key = nets.keys[id];
    if (key.startsWith('\0')) continue;
    const root = nets.find(id);
    const cur = nameOf.get(root);
    if (cur === undefined || better(key, cur)) nameOf.set(root, key);
  }

  const netMap = new Map<number, NetlistNet>();
  const netFor = (root: number): NetlistNet => {
    let net = netMap.get(root);
    if (!net) {
      net = { name: nameOf.get(root)!, terminals: [] };
      netMap.set(root, net);
    }
    return net;
  };

  const instances: NetlistInstance[] = leaves.map(leaf => {
    const connections: Record<string, string> = {};
    for (const [pin, node] of leaf.ports) {
      const root = nets.find(node);
      const c = constOf.get(root);
      if (c) {
        connections[pin] = c;
      } else {
        const net = netFor(root);
        connections[pin] = net.name;
        net.terminals.push({ instance: leaf.name, port: pin });
      }
    }
    const cellType = design.modules.has(leaf.type) ? baseModuleName(leaf.type) : leaf.type;
    return cellType === leaf.type
      ? { name: leaf.name, cellType, connections }
      : { name: leaf.name, cellType, module: leaf.type, connections };
  });

  const ports: NetlistPort[] = topPorts.map(p => {
    const root = nets.find(p.node);
    return { name: p.bit, direction: p.direction, net: constOf.get(root) ?? netFor(root).name };
  });

  return {
    top: top.name,
    keep: [...keep].sort(),
    ports,
    instances,
    nets: [...netMap.values()],
  };
}

/**
 * Parse and elaborate a hierarchical structural Verilog netlist.
 * See the file header for what becomes a leaf instance.
 */
export function parseVerilogNetlist(source: string, options: ElaborateOptions = {}): ParsedNetlist {
  return elaborateNetlist(parseVerilogSource(source), options);
}

// ---------------------------------------------------------------------------
// Design summary (for choosing what to keep, and element pins)
// ---------------------------------------------------------------------------

export interface ModuleSummary {
  /** Name without Yosys parameterization */
  baseName: string;
  /** Full names of all parameterizations */
  variants: string[];
  /** No instances inside: a black box, always a leaf */
  blackBox: boolean;
  /** Instances of this module in the hierarchy below the top */
  uses: number;
  /** Port bits of the first variant, header order, MSB first within a bus */
  pins: { name: string; direction: PinDirection }[];
}

/**
 * Modules reachable from the top, grouped by base name, with how many times
 * each is used when the whole hierarchy is expanded.
 */
export function summarizeDesign(design: VerilogDesign, top?: string): { top: string; modules: ModuleSummary[] } {
  const topMod = findTop(design, top);
  const byBase = new Map<string, ModuleSummary>();
  const visit = (mod: VerilogModule, stack: string[]) => {
    for (const inst of mod.instances) {
      const child = design.modules.get(inst.type);
      if (!child || stack.includes(child.name)) continue;
      const base = baseModuleName(child.name);
      let s = byBase.get(base);
      if (!s) {
        s = {
          baseName: base,
          variants: [],
          blackBox: child.instances.length === 0,
          uses: 0,
          pins: child.ports.flatMap(p => declaredBits(child, p).map(name => ({
            name,
            direction: child.directions.get(p) ?? 'inout',
          }))),
        };
        byBase.set(base, s);
      }
      if (!s.variants.includes(child.name)) s.variants.push(child.name);
      s.uses++;
      visit(child, [...stack, child.name]);
    }
  };
  visit(topMod, [topMod.name]);
  return {
    top: topMod.name,
    modules: [...byBase.values()].sort((a, b) => a.baseName.localeCompare(b.baseName)),
  };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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
