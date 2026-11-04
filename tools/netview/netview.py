#!/usr/bin/env python3
"""Readable gate-level schematics of the synthesized DekatronPC netlists.

    python3 tools/netview/netview.py rtl/run/IpLine_netlist.json -o rtl/run/sch
    python3 tools/netview/netview.py a.json b.json -o out --fanout 6 --global 'clk|rst'

Input: Yosys write_json netlists (synt_dpc.tcl writes <top>_netlist.json next to
<top>_synth.v). Cell pins, functions and tube counts come from the liberty
(sch/logic/vtube_cells.lib). Every module of a netlist that isn't a liberty cell
or a blackbox becomes a sheet: the top and each DekatronModule variant.

Layout: ELK layered with orthogonal routing and fixed pin positions
(tools/netview/elk_layout.mjs; run `npm install` in tools/netview once).
Drawing: GOST 2.743 rectangular symbols ("1", "&", composite AND-OR-NOT, "TT"
flip-flop, "T" latch), cells tinted by the tubes they use. High-fanout nets
(clock, reset lines) are not routed: each pin gets a net flag instead.

Output: <sheet>.svg per sheet and index.html, a viewer with pan/zoom, net
highlighting on click and a search box.
"""
import argparse
import html
import json
import math
import os
import re
import shutil
import subprocess
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
DEFAULT_LIB = os.path.join(REPO, 'sch', 'logic', 'vtube_cells.lib')

G = 10          # grid step: pin pitch is 2G
STUB = 10       # pin stub outside the body
PAD = 10        # room above and below a body for the instance and type labels
FONT = 'DejaVu Sans Mono, Consolas, monospace'

# Tube kinds in the liberty tubes(names) groups -> legend name, colour class
TUBES = {
    'N16B': ('6Н16Б', 'n16'),
    'J2B': ('6Ж2Б', 'j2'),
    'J2P': ('6Ж2П', 'j2'),
    'X7B': ('6Х7Б', 'x7'),
    'KH7B': ('6Х7Б', 'x7'),
    'A110': ('A110', 'dek'),
}


# ----------------------------------------------------------------- liberty

def _blocks(text, kw):
    """(name, body) for each `kw(name) { ... }` group at any depth."""
    for m in re.finditer(r'\b' + kw + r'\s*\(\s*([^)]*?)\s*\)\s*\{', text):
        i, d = m.end(), 1
        while d and i < len(text):
            c = text[i]
            d += (c == '{') - (c == '}')
            i += 1
        yield m.group(1), text[m.end():i - 1]


def read_liberty(path):
    text = re.sub(r'/\*.*?\*/', '', open(path).read(), flags=re.S)
    text = re.sub(r'//[^\n]*', '', text)
    cells = {}
    for name, body in _blocks(text, 'cell'):
        pins, func = [], {}
        for pname, pbody in _blocks(body, 'pin'):
            d = re.search(r'direction\s*:\s*(\w+)', pbody)
            pins.append((pname, d.group(1) if d else 'input'))
            f = re.search(r'function\s*:\s*"([^"]*)"', pbody)
            if f:
                func[pname] = f.group(1).replace(' ', '')
        seq = None
        for kind in ('ff', 'latch'):
            for _, sbody in _blocks(body, kind):
                clk = re.search(r'(?:clocked_on|enable)\s*:\s*"?([^";]+)"?', sbody)
                clr = re.search(r'clear\s*:\s*"?([^";]+)"?', sbody)
                pre = re.search(r'preset\s*:\s*"?([^";]+)"?', sbody)
                seq = {'kind': kind, 'clk': clk.group(1).strip() if clk else 'C',
                       'clear': clr.group(1).strip() if clr else '',
                       'preset': pre.group(1).strip() if pre else ''}
        tubes = {}
        for _, tbody in _blocks(body, 'tubes'):
            for k, v in re.findall(r'(\w+)\s*:\s*([\d.]+)', tbody):
                tubes[k] = float(v)
        area = re.search(r'\barea\s*:\s*([\d.]+)', body)
        cells[name] = {'pins': pins, 'func': func, 'seq': seq, 'tubes': tubes,
                       'area': float(area.group(1)) if area else 0.0}
    return cells


def sop(expr):
    """'((A*B)+C)'' -> (True, [['A','B'], ['C']]); None if it isn't a plain SOP."""
    inv = expr.endswith("'")
    if inv:
        expr = expr[:-1]
    while expr.startswith('(') and expr.endswith(')') and _balanced(expr[1:-1]):
        expr = expr[1:-1]
    terms = []
    for t in _split_top(expr, '+'):
        while t.startswith('(') and t.endswith(')') and _balanced(t[1:-1]):
            t = t[1:-1]
        lits = _split_top(t, '*')
        if not all(re.fullmatch(r'\w+', x) for x in lits):
            return None
        terms.append(lits)
    return inv, terms


def _balanced(s):
    d = 0
    for c in s:
        d += (c == '(') - (c == ')')
        if d < 0:
            return False
    return d == 0


def _split_top(s, op):
    out, d, cur = [], 0, ''
    for c in s:
        d += (c == '(') - (c == ')')
        if c == op and d == 0:
            out.append(cur)
            cur = ''
        else:
            cur += c
    out.append(cur)
    return out


# ----------------------------------------------------------------- symbols

class Sym:
    """A symbol in its own coordinates: body at (0,0)-(w,h), pins at the stub ends.

    pins: name -> dict(x, y, side 'L'/'R', inv, dyn, label)
    """

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.pins = {}
        self.svg = []      # body drawing, relative to (0,0)

    def pin(self, name, side, y, inv=False, dyn=False, label=''):
        self.pins[name] = dict(x=-STUB if side == 'L' else self.w + STUB, y=y,
                               side=side, inv=inv, dyn=dyn, label=label)


def _text(x, y, s, cls, anchor='middle'):
    return f'<text x="{x:g}" y="{y:g}" class="{cls}" text-anchor="{anchor}">{html.escape(s)}</text>'


def _tw(s, size=7.0):
    return len(s) * size * 0.62


def sym_gate(ins, out, inv, terms, fam):
    """Simple gate or composite AND-OR(-NOT)."""
    composite = any(len(t) > 1 for t in terms) and len(terms) > 1
    if not composite:
        op = '&' if len(terms) == 1 and len(terms[0]) > 1 else '1'
        n = len(ins)
        h = max(n, 1) * 2 * G
        w = 3 * G if n == 1 else 4 * G
        s = Sym(w, h)
        s.svg.append(f'<rect class="body {fam}" x="0" y="0" width="{w}" height="{h}"/>')
        s.svg.append(_text(w / 2, 13, op, 'op'))
        for i, p in enumerate(ins):
            s.pin(p, 'L', G + 2 * G * i)
        s.pin(out, 'R', _snap(h / 2), inv=inv)
        return s
    # composite: left column of AND sections, right section "1"
    rows = sum(len(t) for t in terms)
    h = rows * 2 * G
    wl, wr = 3 * G, 3 * G
    s = Sym(wl + wr, h)
    s.svg.append(f'<rect class="body {fam}" x="0" y="0" width="{wl + wr}" height="{h}"/>')
    s.svg.append(f'<line class="div" x1="{wl}" y1="0" x2="{wl}" y2="{h}"/>')
    s.svg.append(_text(wl + wr / 2, 13, '1', 'op'))
    y = 0
    for k, t in enumerate(terms):
        th = len(t) * 2 * G
        if k:
            s.svg.append(f'<line class="div" x1="0" y1="{y}" x2="{wl}" y2="{y}"/>')
        if len(t) > 1:
            s.svg.append(_text(wl / 2, y + 13, '&', 'op'))
        for j, p in enumerate(t):
            s.pin(p, 'L', y + G + 2 * G * j)
        y += th
    s.pin(out, 'R', _snap(h / 2), inv=inv)
    return s


def sym_seq(lib, fam):
    seq = lib['seq']
    ins = [p for p, d in lib['pins'] if d == 'input']
    outs = [p for p, d in lib['pins'] if d != 'input']
    clk = seq['clk'].rstrip("'")
    order = [p for p in ('S', 'SN', 'D', clk, 'R', 'RN') if p in ins] + \
            [p for p in ins if p not in ('S', 'SN', 'D', clk, 'R', 'RN')]
    n = max(len(order), len(outs), 2)
    h = n * 2 * G + 2 * G
    w = 6 * G
    s = Sym(w, h)
    s.svg.append(f'<rect class="body {fam}" x="0" y="0" width="{w}" height="{h}"/>')
    s.svg.append(f'<line class="div" x1="{2 * G}" y1="0" x2="{2 * G}" y2="{h}"/>')
    s.svg.append(f'<line class="div" x1="{w - 2 * G}" y1="0" x2="{w - 2 * G}" y2="{h}"/>')
    s.svg.append(_text(w / 2, 13, 'TT' if seq['kind'] == 'ff' else 'T', 'op'))
    for i, p in enumerate(order):
        y = 2 * G + G + 2 * G * i
        dyn = p == clk and seq['kind'] == 'ff'
        inv = (p == clk and seq['clk'].endswith("'")) or p in ('RN', 'SN')
        lab = {'RN': 'R', 'SN': 'S'}.get(p, p)
        s.pin(p, 'L', y, inv=inv, dyn=dyn)
        s.svg.append(_text(3 if not dyn else 7, y + 3, lab, 'pl', 'start'))
        if dyn:
            s.svg.append(f'<path class="dyn" d="M0,{y - 4} L5,{y} L0,{y + 4}"/>')
    for i, p in enumerate(sorted(outs, key=lambda x: (x.endswith('N'), x))):
        y = 2 * G + G + 2 * G * i
        s.pin(p, 'R', y, inv=p.endswith('N'))
        s.svg.append(_text(w - 3, y + 3, 'Q', 'pl', 'end'))
    return s


def sym_box(title, ins, outs, fam, sub='', dek=False, inst=False):
    """Generic box: pin labels inside, title in the middle column."""
    li = max([_tw(p) for p in ins] + [0])
    lo = max([_tw(p) for p in outs] + [0])
    tw = max(_tw(title, 8), _tw(sub, 7), 3 * G)
    w = _snap(li + lo + tw + 2 * G, up=True)
    n = max(len(ins), len(outs), 2 if not dek else 3)
    h = n * 2 * G + 2 * G
    s = Sym(w, h)
    cls = f'body {fam}' + (' subinst' if inst else '')
    s.svg.append(f'<rect class="{cls}" x="0" y="0" width="{w}" height="{h}"/>')
    if inst:
        s.svg.append(f'<rect class="inst2" x="2.5" y="2.5" width="{w - 5}" height="{h - 5}"/>')
    cx = (li + 4 + w - lo - 4) / 2
    s.svg.append(_text(cx, 13, title, 'bt'))
    if sub:
        s.svg.append(_text(cx, 23, sub, 'pl'))
    if dek:
        cy, r = h / 2 + 6, min(h / 2 - 14, 16)
        if r > 6:
            s.svg.append(f'<circle class="dekring" cx="{cx}" cy="{cy}" r="{r}"/>')
            for k in range(10):
                a = -math.pi / 2 + 2 * math.pi * k / 10
                s.svg.append(f'<circle class="dekcat{" on" if k == 0 else ""}" '
                             f'cx="{cx + 0.7 * r * math.cos(a):.1f}" cy="{cy + 0.7 * r * math.sin(a):.1f}" r="1.8"/>')
    for i, p in enumerate(ins):
        y = G + 2 * G * i + G
        s.pin(p, 'L', y)
        s.svg.append(_text(3, y + 3, p, 'pl', 'start'))
    for i, p in enumerate(outs):
        y = G + 2 * G * i + G
        s.pin(p, 'R', y)
        s.svg.append(_text(w - 3, y + 3, p, 'pl', 'end'))
    return s


def _snap(v, up=False):
    return (math.ceil(v / G) if up else round(v / G)) * G


def family(lib):
    if not lib:
        return 'gen'
    kinds = []
    for k in lib['tubes']:
        c = TUBES.get(k, (k, 'gen'))[1]
        if c not in kinds:
            kinds.append(c)
    if not kinds:
        return 'gen'
    return kinds[0] if len(kinds) == 1 else 'mix'


def tube_text(lib):
    if not lib or not lib['tubes']:
        return ''
    return ', '.join(f'{v:g}×{TUBES.get(k, (k,))[0]}' for k, v in lib['tubes'].items())


def lib_symbol(name, lib):
    fam = family(lib)
    ins = [p for p, d in lib['pins'] if d == 'input']
    outs = [p for p, d in lib['pins'] if d != 'input']
    if lib['seq']:
        return sym_seq(lib, fam)
    if len(outs) == 1 and outs[0] in lib['func'] and ins:
        r = sop(lib['func'][outs[0]])
        if r and sorted(sum(r[1], [])) == sorted(ins):
            return sym_gate(ins, outs[0], r[0], r[1], fam)
    return sym_box(short_type(name), ins, outs, fam)


def short_type(t):
    t = t.lstrip('\\')
    m = re.match(r'\$paramod\$[0-9a-f]+\\(.*)', t)
    return m.group(1) if m else t


# ----------------------------------------------------------------- netlist

def is_auto(name):
    return name.startswith('$') or re.fullmatch(r'_\d+_', name) is not None


def bit_label(name, width, i, offset=0):
    return name if width == 1 else f'{name}[{i + offset}]'


class Sheet:
    def __init__(self, mname, mod, libcells, modules, args, titles):
        self.name = mname
        self.title = titles.get(mname, short_type(mname))
        self.mod = mod
        self.lib = libcells
        self.modules = modules
        self.args = args
        self.nodes = {}       # id -> dict(sym, kind, label, type, tip, flags)
        self.edges = []       # (eid, bit, (n, p), (n, p))
        self.netname = {}
        self.build()

    # bits ---------------------------------------------------------------
    def build(self):
        mod, args = self.mod, self.args
        names = {}
        for nn, nd in mod.get('netnames', {}).items():
            bits = nd['bits']
            off = nd.get('offset', 0)
            hidden = nd.get('hide_name', 0) or is_auto(nn)
            for i, b in enumerate(bits):
                if isinstance(b, str):
                    continue
                lab = bit_label(nn, len(bits), i, off)
                score = (hidden, len(bits) > 1, len(lab))
                if b not in names or score < names[b][0]:
                    names[b] = (score, lab, hidden)
        self.netname = {b: v[1] for b, v in names.items()}
        # ABC names ($abc$3294$new_n79) shortened to n79 where that stays unique on the sheet
        short = {b: re.sub(r'^new_', '', re.sub(r'.*\$', '', n)) for b, n in self.netname.items()
                 if n.startswith('$')}
        taken = defaultdict(int)
        for n in list(short.values()) + [n for n in self.netname.values() if not n.startswith('$')]:
            taken[n] += 1
        for b, n in short.items():
            if n and taken[n] == 1:
                self.netname[b] = n
        self.public = {b for b, v in names.items() if not v[2]}

        drivers = {}
        sinks = defaultdict(list)
        cells = {}            # nid -> list of (pin, dir, bit or const)

        # module ports
        for pn, pd in mod['ports'].items():
            bits = pd['bits']
            d = pd['direction']
            nid = 'p:' + pn
            pins = [(bit_label(pn, len(bits), i, pd.get('offset', 0)) if len(bits) > 1 else pn,
                     'output' if d == 'input' else 'input', b) for i, b in enumerate(bits)]
            cells[nid] = pins
            self.nodes[nid] = dict(kind='in' if d == 'input' else 'out', name=pn,
                                   width=len(bits), type='port')

        for cn, cd in mod['cells'].items():
            t = cd['type']
            if t.startswith('$scopeinfo'):
                continue
            nid = 'c:' + cn
            dirs = cd.get('port_directions', {})
            pins = []
            for pn, bits in cd['connections'].items():
                d = dirs.get(pn)
                if d is None and t in self.lib:
                    d = dict(self.lib[t]['pins']).get(pn, 'input')
                if d is None and t in self.modules:
                    d = self.modules[t]['ports'].get(pn, {}).get('direction')
                if d is None:
                    # a behavioural blackbox read from JSON has no directions:
                    # the name suffix, else resolved from the nets below
                    d = 'output' if re.search(r'_o$|_dbg', pn) else 'input' if re.search(r'_i$', pn) else '?'
                for i, b in enumerate(bits):
                    pins.append((bit_label(pn, len(bits), i), d, b))
            cells[nid] = pins
            self.nodes[nid] = dict(kind='cell', name=cn, type=t, hide=cd.get('hide_name', 0) or is_auto(cn),
                                   src=cd.get('attributes', {}).get('src', ''))

        known = {b for pins in cells.values() for p, d, b in pins if d == 'output' and not isinstance(b, str)}
        for nid, pins in cells.items():
            # unknown direction: an output unless something else drives the net
            pins[:] = [(p, ('input' if isinstance(b, str) or b in known else 'output') if d == '?' else d, b)
                       for p, d, b in pins]
            for p, d, b in pins:
                if isinstance(b, str):
                    continue
                if d == 'output':
                    drivers[b] = (nid, p)
                else:
                    sinks[b].append((nid, p))
        self.cells, self.drivers, self.sinks = cells, drivers, sinks

        glob_re = re.compile(args.global_re) if args.global_re else None
        self.glob = set()
        for b, ss in sinks.items():
            nm = self.netname.get(b, '')
            base = re.sub(r'\[\d+\]$', '', nm)
            if len(ss) >= args.fanout or (glob_re and nm and b in self.public and glob_re.fullmatch(base)):
                self.glob.add(b)
        self.glob_by_fanout = set(self.glob)
        # register outputs: flags instead of the long feedback wires back across the sheet
        if args.seq_cut:
            for cn, cd in mod['cells'].items():
                lc = self.lib.get(cd['type'])
                if not lc or not lc['seq']:
                    continue
                for pn, bits in cd['connections'].items():
                    if dict(lc['pins']).get(pn) == 'output':
                        for b in bits:
                            if not isinstance(b, str) and len(sinks.get(b, [])) >= args.seq_cut:
                                self.glob.add(b)

        # symbols ---------------------------------------------------------
        for nid, nd in self.nodes.items():
            pins = cells[nid]
            if nd['kind'] in ('in', 'out'):
                used = [(p, d, b) for p, d, b in pins if not isinstance(b, str) and
                        (b in sinks if nd['kind'] == 'in' else b in drivers)]
                nd['sym'] = self.port_symbol(nd, used)
                continue
            t = nd['type']
            if t in self.lib:
                nd['sym'] = lib_symbol(t, self.lib[t])
                nd['lib'] = self.lib[t]
            else:
                # non-liberty: submodule instance or behavioural blackbox (the dekatron)
                shown = [(p, d, b) for p, d, b in pins if self.pin_shown(p, d, b)]
                ins = [p for p, d, b in shown if d != 'output']
                outs = [p for p, d, b in shown if d == 'output']
                inst = t in self.modules
                dek = 'Dekatron' in t
                fam = 'dek' if dek else 'sub'
                nd['sym'] = sym_box(short_type(t), ins, outs, fam,
                                    sub='A110' if dek else '', dek=dek, inst=inst)
                nd['inst'] = inst
            nd['pinmap'] = {p: b for p, d, b in pins}

    def pin_shown(self, p, d, b):
        if isinstance(b, str):
            return d != 'output' and b in '01' and not p.startswith('sim_')
        if d == 'output':
            return b in self.sinks
        return True

    def port_symbol(self, nd, pins):
        name = nd['name']
        n = len(pins)
        w0 = nd['width']
        lab = name if w0 == 1 else f'{name}[{w0 - 1}:0]'
        if n == 1 and w0 > 1:
            lab = pins[0][0]
        if n == 0:
            # nothing on this sheet uses the port (or a constant drives it)
            note = f'{lab}: не исп.' if nd['kind'] == 'in' else f'{lab}: константа'
            tw = _snap(_tw(note, 8) + 12, up=True)
            s = Sym(tw, 2 * G)
            s.svg.append(f'<rect class="port unused" x="0" y="0" width="{tw}" height="{2 * G}" rx="3"/>')
            s.svg.append(_text(tw / 2, 13.5, note, 'pl'))
            return s
        tw = _snap(_tw(lab, 8) + 14, up=True)
        if n == 1:
            s = Sym(tw, 2 * G)
            side = 'R' if nd['kind'] == 'in' else 'L'
            if side == 'R':
                pts = f'0,0 {tw - 8},0 {tw},{G} {tw - 8},{2 * G} 0,{2 * G}'
            else:
                pts = f'8,0 {tw},0 {tw},{2 * G} 8,{2 * G} 0,{G}'
            s.svg.append(f'<polygon class="port" points="{pts}"/>')
            s.svg.append(_text(tw / 2 + (-3 if side == 'R' else 3), 13.5, lab, 'pn'))
            s.pin(pins[0][0], side, G)
            return s
        # bus connector: header with the name, one pin per bit
        w = max(tw, 6 * G)
        h = 2 * G + n * 2 * G
        s = Sym(w, h)
        side = 'R' if nd['kind'] == 'in' else 'L'
        s.svg.append(f'<rect class="port" x="0" y="0" width="{w}" height="{h}" rx="3"/>')
        s.svg.append(f'<line class="div" x1="0" y1="{2 * G}" x2="{w}" y2="{2 * G}"/>')
        s.svg.append(_text(w / 2, 14, lab, 'pn'))
        for i, (p, d, b) in enumerate(pins):
            y = 2 * G + G + 2 * G * i
            s.pin(p, side, y)
            idx = re.search(r'\[(\d+)\]$', p).group(1)
            if side == 'R':
                s.svg.append(_text(w - 4, y + 3, idx, 'pl', 'end'))
            else:
                s.svg.append(_text(4, y + 3, idx, 'pl', 'start'))
        return s

    # layout -------------------------------------------------------------
    def flag_text(self, b):
        if isinstance(b, str):
            return {'0': '0', '1': '1'}.get(b, b)
        return self.netname.get(b, f'n{b}')

    def elk_graph(self):
        children, edges = [], []
        for nid, nd in self.nodes.items():
            s = nd['sym']
            pm = nd.get('pinmap') or {p: b for p, d, b in self.cells[nid]}
            # flags (constants, global nets) widen the node on that side
            lext = rext = 0
            nd['flags'] = {}
            for p, pd in s.pins.items():
                b = pm.get(p)
                if b is None:
                    continue
                if isinstance(b, str) or b in self.glob:
                    t = self.flag_text(b)
                    fw = _snap(_tw(t, 7) + 12, up=True) if not isinstance(b, str) else 2 * G
                    nd['flags'][p] = (t, fw, isinstance(b, str))
                    if pd['side'] == 'L':
                        lext = max(lext, fw)
                    else:
                        rext = max(rext, fw)
            nd['lext'], nd['rext'] = lext, rext
            ox = STUB + lext          # body origin inside the node
            nd['ox'] = ox
            W = s.w + 2 * STUB + lext + rext
            ports = []
            for p, pd in s.pins.items():
                b = pm.get(p)
                if b is None or isinstance(b, str) or b in self.glob:
                    continue
                if pd['side'] == 'L' and b not in self.drivers:
                    continue
                if pd['side'] == 'R' and b not in self.sinks:
                    continue
                ports.append({'id': f'{nid}|{p}', 'x': 0 if pd['side'] == 'L' else W, 'y': pd['y'] + PAD,
                              'width': 0, 'height': 0,
                              'layoutOptions': {'port.side': 'WEST' if pd['side'] == 'L' else 'EAST'}})
            lo = {'portConstraints': 'FIXED_POS'}
            if nd['kind'] == 'in':
                lo['layering.layerConstraint'] = 'FIRST'
            elif nd['kind'] == 'out':
                lo['layering.layerConstraint'] = 'LAST'
            children.append({'id': nid, 'width': W, 'height': s.h + 2 * PAD, 'ports': ports, 'layoutOptions': lo})
            nd['elk'] = children[-1]
        # function groups become compound nodes (frames); ports and shared logic stay at the root
        self.group = self.assign_groups()
        frames = {(): {'children': []}}

        def frame(path):
            if path not in frames:
                frames[path] = {'id': 'g:' + '/'.join(path), 'children': [],
                                'layoutOptions': {'padding': '[top=26,left=14,bottom=14,right=14]'}}
                frame(path[:-1])['children'].append(frames[path])
            return frames[path]
        for ch in children:
            frame(self.group.get(ch['id'], ()))['children'].append(ch)
        children = frames[()]['children']

        def cont(nid):
            return self.group.get(nid, ())

        def edge(key, src, dst):
            eid = f'e{len(self.edges)}'
            self.edges.append((eid, key))
            edges.append({'id': eid, 'sources': [src], 'targets': [dst]})

        # buses: the nets that leave a frame are joined into one bus per (source frame,
        # destination frame), or per vector with --buses vectors, and ripped back into
        # bits on arrival
        mode = self.args.buses
        conns = defaultdict(lambda: defaultdict(list))     # (name, src, dst) -> bit -> sinks
        plain = []
        for b, (dn, dp) in self.drivers.items():
            if b in self.glob:
                continue
            v = self.vector(b)
            for sn, sp in self.sinks.get(b, []):
                if sp not in self.nodes[sn]['sym'].pins:
                    continue
                sc, dc = cont(dn), cont(sn)
                # a multi-bit module port is an end of its own: its bus runs to the port header
                if self.nodes[dn]['kind'] == 'in' and self.nodes[dn]['width'] > 1:
                    sc = ('@' + dn,)
                if self.nodes[sn]['kind'] == 'out' and self.nodes[sn]['width'] > 1:
                    dc = ('@' + sn,)
                if sc != dc and mode == 'frames':
                    conns[('', sc, dc)][b].append((sn, sp))
                elif sc != dc and mode == 'vectors' and v:
                    conns[(v[0], sc, dc)][b].append((sn, sp))
                else:
                    plain.append((b, dn, dp, sn, sp))
        for key, bits in list(conns.items()):
            if len(bits) < 2:
                for b, ss in bits.items():
                    dn, dp = self.drivers[b]
                    plain += [(b, dn, dp, sn, sp) for sn, sp in ss]
                del conns[key]
        for b, dn, dp, sn, sp in plain:
            edge(b, f'{dn}|{dp}', f'{sn}|{sp}')
        self.rippers = {}
        def bus_port(nid):
            # a multi-bit module port takes the bus on its header row
            nd = self.nodes[nid]
            if 'busport' not in nd:
                e = nd['elk']
                nd['busport'] = True
                e['ports'].append({'id': f'{nid}|bus', 'x': e['width'] if nd['kind'] == 'in' else 0,
                                   'y': PAD + G, 'width': 0, 'height': 0,
                                   'layoutOptions': {'port.side': 'EAST' if nd['kind'] == 'in' else 'WEST'}})
            return f'{nid}|bus'

        for (v, sc, dc), bits in conns.items():
            name = v or self.bus_name(bits, sc, dc)
            tag = f'{v}:{"/".join(sc)}>{"/".join(dc)}'
            jid, sid = 'j:' + tag, 's:' + tag
            srcs = {self.drivers[b][0] for b in bits}
            dsts = {sn for ss in bits.values() for sn, sp in ss}
            sp1 = srcs.pop() if len(srcs) == 1 else None
            dp1 = dsts.pop() if len(dsts) == 1 else None
            if sp1 and self.nodes[sp1]['kind'] == 'in' and self.nodes[sp1]['width'] > 1:
                src = bus_port(sp1)
            else:
                self.rippers[jid] = self.ripper('join', name, bits, jid)
                frame(() if sc[:1] and sc[0].startswith('@') else sc)['children'].append(self.rippers[jid]['elk'])
                for b in bits:
                    dn, dp = self.drivers[b]
                    edge(b, f'{dn}|{dp}', f'{jid}|{b}')
                src = f'{jid}|bus'
            if dp1 and self.nodes[dp1]['kind'] == 'out' and self.nodes[dp1]['width'] > 1:
                dst = bus_port(dp1)
            else:
                self.rippers[sid] = self.ripper('split', name, bits, sid)
                frame(() if dc[:1] and dc[0].startswith('@') else dc)['children'].append(self.rippers[sid]['elk'])
                for b, ss in bits.items():
                    for sn, sp in ss:
                        edge(b, f'{sid}|{b}', f'{sn}|{sp}')
                dst = f'{sid}|bus'
            edge(('bus', name, tuple(self.bit_order(bits))), src, dst)
        a = self.args
        return {
            'id': 'root',
            'layoutOptions': {
                'algorithm': 'layered',
                'direction': 'RIGHT',
                'edgeRouting': 'ORTHOGONAL',
                'spacing.nodeNode': str(a.node_gap),
                'layered.spacing.nodeNodeBetweenLayers': str(a.layer_gap),
                'layered.spacing.edgeNodeBetweenLayers': '12',
                'layered.spacing.edgeEdgeBetweenLayers': '7',
                'spacing.edgeEdge': '7',
                'spacing.edgeNode': '10',
                'layered.nodePlacement.strategy': a.placement,
                'layered.crossingMinimization.thoroughness': str(a.thoroughness),
                'layered.considerModelOrder.strategy': 'NODES_AND_EDGES',
                'separateConnectedComponents': 'true',
                'spacing.componentComponent': '40',
                'layered.mergeEdges': 'true',
                'hierarchyHandling': 'INCLUDE_CHILDREN',
            },
            'children': children,
            'edges': edges,
        }

    def vector(self, b):
        """(vector name, bit index) for a bit of a public multi-bit net, else None."""
        if b not in self.public:
            return None
        m = re.fullmatch(r'(.+)\[(\d+)\]', self.netname[b])
        return (m.group(1), int(m.group(2))) if m else None

    def bit_order(self, bits):
        """Vector bits by index, then the rest by name (n79 < n100)."""
        def key(b):
            v = self.vector(b)
            if v:
                return (0, v[0], v[1])
            n = self.netname.get(b, '')
            return (1, re.sub(r'\d+', lambda m: m.group().zfill(6), n), 0)
        return sorted(bits, key=key)

    def bit_tag(self, b, single):
        """Stub label on a ripper: the index inside a one-vector bus, else a short net name."""
        v = self.vector(b)
        if v and single:
            return str(v[1])
        return self.netname.get(b, '').split('.')[-1]

    def bus_name(self, bits, sc, dc):
        vs = {(self.vector(b) or (None,))[0] for b in bits}
        if len(vs) == 1 and None not in vs:
            return vs.pop()
        # the root (logic shared by several frames) has no name
        a = (sc[-1] if sc else '').lstrip('@').replace('p:', '')
        z = (dc[-1] if dc else '').lstrip('@').replace('p:', '')
        return f'{a}→{z}'

    def ripper(self, kind, v, bits, rid):
        """Bus joiner (bits in, bus out) or ripper (bus in, bits out): a bar with indexed stubs."""
        bits = self.bit_order(bits)
        single = len({(self.vector(b) or (None,))[0] for b in bits}) == 1 and self.vector(bits[0]) is not None
        tags = [self.bit_tag(b, single) for b in bits]
        n = len(bits)
        W, H = _snap(max(_tw(x, 5.5) for x in tags) + 14, up=True), (n + 1) * G
        ports, svg = [], []
        bx = W - 6 if kind == 'join' else 3       # the bar
        svg.append(f'<rect class="bar" x="{bx}" y="2" width="3" height="{H - 4}"/>')
        for i, b in enumerate(bits):
            y = (i + 1) * G
            x0, x1 = (0, bx) if kind == 'join' else (bx + 3, W)
            svg.append(f'<line class="pin" data-net="{html.escape(self.netname[b])}" '
                       f'x1="{x0}" y1="{y}" x2="{x1}" y2="{y}"/>')
            tx = (x0 + x1) / 2
            svg.append(_text(tx, y - 2, tags[i], 'bi'))
            ports.append((b, 0 if kind == 'join' else W, y, 'WEST' if kind == 'join' else 'EAST'))
        ports.append(('bus', W if kind == 'join' else 0, _snap(H / 2), 'EAST' if kind == 'join' else 'WEST'))
        elk = {'id': rid, 'width': W, 'height': H, 'layoutOptions': {'portConstraints': 'FIXED_POS'},
               'ports': [{'id': f'{rid}|{p}', 'x': x, 'y': y, 'width': 0, 'height': 0,
                          'layoutOptions': {'port.side': side}} for p, x, y, side in ports]}
        return {'kind': kind, 'v': v, 'bits': bits, 'svg': svg, 'elk': elk}

    def assign_groups(self):
        """Cell -> group key: the named signal, register or hierarchy scope its logic ends in.

        ABC leaves no src on most cells, so the groups come from the structure. Seeds: a cell
        named in a sub-scope (ip_counter.enLatch[1]...) takes the scope; a cell driving a public
        net takes that net's name (state_d, scanning_q -> state, scanning). The others take the
        group of the cells they feed, by majority; logic feeding several groups stays shared.
        """
        if not self.args.group:
            return {}

        def coarse(n):
            n = re.sub(r'\[\d+\]$', '', n.lstrip('\\'))
            if '.' in n:
                return n.split('.')[0]
            return re.sub(r'(_q|_d|_nx|_next|_s|_db|_r)$', '', n) or n

        def fine(n):
            n = n.lstrip('\\')
            if '.' in n:
                parts = n.split('.')
                return '.'.join(parts[:2]) if len(parts) > 2 else parts[0]
            # state_d[2] and the register state[2] share a frame
            m = re.match(r'(.*?)(\[\d+\])?$', n)
            return (re.sub(r'(_q|_d|_nx|_next|_s|_db|_r)$', '', m.group(1)) or m.group(1)) + (m.group(2) or '')

        big = self.args.group_max
        g1 = self.vote_groups(coarse)
        size = defaultdict(int)
        for k in g1.values():
            size[k] += 1
        out = {nid: (k,) for nid, k in g1.items() if k and size[k] >= self.args.group_min}
        if big:
            g2 = self.vote_groups(fine)
            sub = defaultdict(int)
            for nid, k in out.items():
                if size[k[0]] > big and g2.get(nid):
                    sub[(k[0], g2[nid])] += 1
            for nid, k in list(out.items()):
                f = g2.get(nid)
                if size[k[0]] > big and f and f != k[0] and sub[(k[0], f)] >= self.args.group_min:
                    out[nid] = (k[0], f)
        return out

    def vote_groups(self, norm):
        cells = [nid for nid, nd in self.nodes.items() if nd['kind'] == 'cell']
        outs = {nid: [b for p, d, b in self.cells[nid] if d == 'output' and not isinstance(b, str)]
                for nid in cells}
        grp = {}
        for nid in cells:
            nd = self.nodes[nid]
            if not nd['hide'] and '.' in nd['name'].lstrip('\\'):
                grp[nid] = norm(nd['name'])
                continue
            for b in outs[nid]:
                if b in self.public and b not in self.glob_by_fanout:
                    grp[nid] = norm(self.netname[b])
                    break

        def vote(nid, final):
            votes, pending = defaultdict(int), False
            for b in outs[nid]:
                for sn, sp in self.sinks.get(b, []):
                    snd = self.nodes[sn]
                    if snd['kind'] == 'out':
                        votes[norm(snd['name'])] += 1
                    elif snd['kind'] == 'cell':
                        if sn not in grp:
                            pending = True
                        elif grp[sn]:
                            votes[grp[sn]] += 1
            if pending and not final:
                return False
            if not votes:
                grp[nid] = ''
                return True
            k, n = max(votes.items(), key=lambda kv: kv[1])
            grp[nid] = k if n * 2 > sum(votes.values()) else ''
            return True

        todo = [nid for nid in cells if nid not in grp]
        while todo:
            left = [nid for nid in todo if not vote(nid, False)]
            if len(left) == len(todo):
                # a loop through unseeded cells: decide one by the votes known so far
                vote(left[0], True)
                left = left[1:]
            todo = left
        return grp

    # render -------------------------------------------------------------
    def render(self, lay):
        pos = {}
        frames = []

        def walk(node, ox, oy):
            for c in node.get('children', []):
                ax, ay = ox + c['x'], oy + c['y']
                pos[c['id']] = dict(c, x=ax, y=ay)
                if c['id'].startswith('g:'):
                    frames.append(pos[c['id']])
                walk(c, ax, ay)
        walk(lay, 0, 0)
        net_of = dict(self.edges)
        W, H = lay['width'], lay['height']
        M = 30
        out = []
        gsize = defaultdict(int)
        for path in self.group.values():
            for i in range(1, len(path) + 1):
                gsize['/'.join(path[:i])] += 1
        for f in frames:
            k = f['id'][2:]
            sub = '/' in k
            out.append(f'<g class="frame{" sub2" if sub else ""}"><rect x="{f["x"]:.1f}" y="{f["y"]:.1f}" width="{f["width"]:.1f}" '
                       f'height="{f["height"]:.1f}" rx="6"/>'
                       + _text(f['x'] + 8, f['y'] + 15, f'{k.split("/")[-1]} · {gsize[k]}', 'fl', 'start')
                       + '</g>')
        tubes = defaultdict(float)
        ncell = 0
        # wires, grouped per net
        wires = defaultdict(list)
        juncs = defaultdict(set)
        buses = []
        for e in lay.get('edges', []):
            # edge coordinates are relative to the edge's container node
            cont = pos.get(e.get('container', 'root'), {'x': 0, 'y': 0})
            e['_dx'], e['_dy'] = cont['x'], cont['y']
            dx, dy = e['_dx'], e['_dy']
            b = net_of[e['id']]
            if isinstance(b, tuple):
                buses.append((b, e, dx, dy))
                continue
            for sec in e.get('sections', []):
                pts = [sec['startPoint']] + sec.get('bendPoints', []) + [sec['endPoint']]
                wires[b].append('M' + ' L'.join(f'{p["x"] + dx:.1f},{p["y"] + dy:.1f}' for p in pts))
            for j in e.get('junctionPoints', []) or []:
                juncs[b].add((round(j['x'] + dx, 1), round(j['y'] + dy, 1)))
        for b in sorted(wires):
            nm = self.flag_text(b)
            out.append(f'<g class="net" data-net="{html.escape(nm)}"><title>{html.escape(nm)}</title>'
                       f'<path class="wire" d="{" ".join(wires[b])}"/>'
                       + ''.join(f'<circle class="jn" cx="{x}" cy="{y}" r="2.6"/>' for x, y in sorted(juncs[b]))
                       + '</g>')
        for (_, v, bits), e, dx, dy in buses:
            vs = [self.vector(b) for b in bits]
            if all(vs) and len({x[0] for x in vs}) == 1:
                idx = [x[1] for x in vs]
                span = (f'[{idx[-1]}:{idx[0]}]' if idx == list(range(idx[0], idx[-1] + 1))
                        else '{' + ','.join(map(str, idx)) + '}')
                tip = v + span
            else:
                span = f' · {len(bits)}'
                tip = f'{v}: ' + ', '.join(self.netname.get(b, '') for b in bits)
            names = ' '.join(self.netname.get(b, '') for b in bits)
            d, lab = [], ''
            for sec in e.get('sections', []):
                pts = [sec['startPoint']] + sec.get('bendPoints', []) + [sec['endPoint']]
                d.append('M' + ' L'.join(f'{p["x"] + dx:.1f},{p["y"] + dy:.1f}' for p in pts))
                if not lab:
                    x0, y0 = pts[0]['x'] + dx, pts[0]['y'] + dy
                    # width slash and the vector name next to the joiner
                    lab = (f'<line class="slash" x1="{x0 + 6}" y1="{y0 + 4}" x2="{x0 + 12}" y2="{y0 - 4}"/>'
                           + _text(x0 + 9, y0 + 11, str(len(bits)), 'bw')
                           + _text(x0 + 15, y0 - 3, f'{v}{span}', 'bl', 'start'))
            out.append(f'<g class="net bus" data-net="{html.escape(v)}" data-bits="{html.escape(names)}">'
                       f'<title>{html.escape(tip)}</title><path class="buswire" d="{" ".join(d)}"/>{lab}</g>')
        for rid, r in self.rippers.items():
            c = pos[rid]
            out.append(f'<g class="ripper" transform="translate({c["x"]:.1f},{c["y"]:.1f})">'
                       f'<title>{html.escape(r["v"])}</title>' + ''.join(r['svg']) + '</g>')
        # cells
        for nid, nd in self.nodes.items():
            c = pos[nid]
            s = nd['sym']
            x0 = c['x'] + nd['ox']
            y0 = c['y'] + PAD
            pm = nd.get('pinmap') or {p: b for p, d, b in self.cells[nid]}
            g = []
            tip = []
            if nd['kind'] == 'cell':
                ncell += 1
                lib = nd.get('lib')
                if lib:
                    for k, v in lib['tubes'].items():
                        tubes[k] += v
                tip = [nd['name'], nd['type']]
                if lib and lib['tubes']:
                    tip.append(tube_text(lib))
                if nd['src']:
                    tip.append(nd['src'])
            else:
                tip = [f'{nd["kind"]}put {nd["name"]}' + (f' [{nd["width"] - 1}:0]' if nd['width'] > 1 else '')]
            for p, pd in s.pins.items():
                b = pm.get(p)
                px = pd['x']
                body_x = 0 if pd['side'] == 'L' else s.w
                inv = pd['inv']
                y = pd['y']
                cls = 'pin'
                attrs = ''
                if b is not None and not isinstance(b, str):
                    attrs = f' data-net="{html.escape(self.flag_text(b))}"'
                # stub, extended to the node edge when the node is widened
                end = px - (nd['lext'] if pd['side'] == 'L' else -nd['rext'])
                fl = nd['flags'].get(p)
                if fl:
                    end = px
                if inv:
                    cx = body_x - 3 if pd['side'] == 'L' else body_x + 3
                    sx = body_x - 6 if pd['side'] == 'L' else body_x + 6
                    g.append(f'<circle class="bub" cx="{cx}" cy="{y}" r="3"/>')
                    if b is not None:
                        g.append(f'<line class="{cls}"{attrs} x1="{sx}" y1="{y}" x2="{end}" y2="{y}"/>')
                elif b is not None or nd['kind'] != 'cell':
                    g.append(f'<line class="{cls}"{attrs} x1="{body_x}" y1="{y}" x2="{end}" y2="{y}"/>')
                if fl:
                    t, fw, const = fl
                    if const:
                        tx = px - 2 if pd['side'] == 'L' else px + 2
                        g.append(_text(tx, y + 3, t, 'cst', 'end' if pd['side'] == 'L' else 'start'))
                    else:
                        g.append(self.flag_svg(px, y, t, fw, pd['side']))
            if nd.get('busport'):
                bx0, bx1 = (s.w, s.w + STUB + nd['rext']) if nd['kind'] == 'in' else (-STUB - nd['lext'], 0)
                g.append(f'<line class="busstub" x1="{bx0}" y1="{G}" x2="{bx1}" y2="{G}"/>')
            label = ''
            if nd['kind'] == 'cell':
                tname = short_type(nd['type'])
                if nd.get('inst') or not nd['hide']:
                    label = _text(s.w / 2, -4, short_inst(nd['name']), 'inst', 'middle')
                label += _text(s.w / 2, s.h + 9, tname, 'ty', 'middle')
            extra = ''
            if nd.get('inst'):
                extra = f' data-sheet="{html.escape(sheet_id(nd["type"]))}"'
            out.append(f'<g class="cell" data-name="{html.escape(nd["name"])}"{extra} '
                       f'transform="translate({x0:.1f},{y0:.1f})"><title>{html.escape(chr(10).join(tip))}</title>'
                       + ''.join(s.svg) + ''.join(g) + label + '</g>')
        # public net names at the driver end
        named = set()
        for e in lay.get('edges', []):
            b = net_of[e['id']]
            if isinstance(b, tuple) or b in named or b not in self.public:
                continue
            dn, dp = self.drivers[b]
            if self.nodes[dn]['kind'] == 'in':
                continue
            named.add(b)
            sec = e['sections'][0]
            p0 = {'x': sec['startPoint']['x'] + e['_dx'], 'y': sec['startPoint']['y'] + e['_dy']}
            out.append(f'<text class="nl" data-net="{html.escape(self.netname[b])}" x="{p0["x"] + 4:.1f}" '
                       f'y="{p0["y"] - 3:.1f}">{html.escape(self.netname[b])}</text>')
        total = sum(tubes.values())
        self.stats = dict(cells=ncell, tubes=total, by=dict(tubes))
        legend = self.legend(tubes, W + 2 * M)
        LH = 46
        vb = f'{-M} {-M - LH} {W + 2 * M} {H + 2 * M + LH}'
        head = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}" width="{W + 2 * M:.0f}" '
                f'height="{H + 2 * M + LH:.0f}" class="netview" data-title="{html.escape(self.title)}" '
                f'data-cells="{ncell}" data-tubes="{total:g}" data-top="{int(self.top)}">'
                f'<style>{CSS}</style><rect class="paper" x="{-M}" y="{-M - LH}" width="{W + 2 * M}" '
                f'height="{H + 2 * M + LH}"/>')
        return head + f'<g transform="translate({-M},{-M - LH})">{legend}</g>' + ''.join(out) + '</svg>'

    def flag_svg(self, px, y, t, fw, side):
        h = 12
        if side == 'L':
            x1, x0 = px, px - fw
            pts = f'{x0 + 5},{y - h / 2} {x1},{y - h / 2} {x1},{y + h / 2} {x0 + 5},{y + h / 2} {x0},{y}'
            tx = (x0 + 5 + x1) / 2
        else:
            x0, x1 = px, px + fw
            pts = f'{x0},{y - h / 2} {x1 - 5},{y - h / 2} {x1},{y} {x1 - 5},{y + h / 2} {x0},{y + h / 2}'
            tx = (x0 + x1 - 5) / 2
        return (f'<g class="flag" data-net="{html.escape(t)}"><polygon points="{pts}"/>'
                f'{_text(tx, y + 2.6, t, "ft")}</g>')

    def legend(self, tubes, width):
        items = []
        seen = set()
        for k in tubes:
            nm, cls = TUBES.get(k, (k, 'gen'))
            if cls in seen:
                continue
            seen.add(cls)
            items.append((cls, nm))
        if any(nd.get('type', '').startswith('DekatronTube') for nd in self.nodes.values()):
            items.append(('dek', 'A110'))
        items.append(('mix', 'несколько типов'))
        x = 12
        s = [_text(12, 20, f'{self.title}', 'title', 'start')]
        stat = f'{self.stats["cells"]} ячеек · {self.stats["tubes"]:g} ламп'
        if self.stats['by']:
            stat += ' (' + ', '.join(f'{v:g}×{TUBES.get(k, (k,))[0]}' for k, v in self.stats['by'].items()) + ')'
        s.append(_text(12, 36, stat, 'leg', 'start'))
        x = _tw(stat, 9) + 40
        for cls, nm in items:
            s.append(f'<rect class="body {cls}" x="{x:.0f}" y="28" width="14" height="10"/>')
            s.append(_text(x + 20, 36.5, nm, 'leg', 'start'))
            x += 26 + _tw(nm, 9)
        return ''.join(s)


def short_inst(n):
    n = n.lstrip('\\')
    return n if len(n) <= 28 else '…' + n[-27:]


def sheet_id(mname):
    t = mname.lstrip('\\')
    m = re.match(r'\$paramod\$([0-9a-f]+)\\(.*)', t)
    return f'{m.group(2)}_{m.group(1)[:6]}' if m else re.sub(r'[^\w.-]', '_', t)


_CSS = '''
.netview{font-family:DejaVu Sans Mono,Consolas,monospace}
.paper{fill:var(--paper)}
.body{stroke:var(--ink);stroke-width:1.3}
.n16{fill:var(--n16)}.j2{fill:var(--j2)}.x7{fill:var(--x7)}.mix{fill:var(--mix)}
.dek{fill:var(--dek)}.sub{fill:var(--sub)}.gen{fill:var(--gen)}
.inst2{fill:none;stroke:var(--ink);stroke-width:.6}
.div{stroke:var(--ink);stroke-width:.8}
.op{font-size:12px;font-weight:bold;fill:var(--ink)}
.bt{font-size:8px;font-weight:bold;fill:var(--ink)}
.pl{font-size:7px;fill:var(--ink)}
.pn{font-size:8px;font-weight:bold;fill:var(--ink)}
.ty{font-size:6.5px;fill:var(--muted)}
.inst{font-size:6.5px;fill:var(--muted)}
.cst{font-size:8px;font-weight:bold;fill:var(--muted)}
.nl{font-size:6.5px;fill:var(--wire);opacity:.85}
.title{font-size:16px;font-weight:bold;fill:var(--ink)}
.leg{font-size:9px;fill:var(--muted)}
.wire{fill:none;stroke:var(--wire);stroke-width:1.1;stroke-linejoin:round}
.pin{stroke:var(--ink);stroke-width:1.1}
.bub{fill:var(--paper);stroke:var(--ink);stroke-width:1.1}
.dyn{fill:none;stroke:var(--ink);stroke-width:1}
.jn{fill:var(--wire)}
.buswire{fill:none;stroke:var(--wire);stroke-width:3.2;stroke-linejoin:round;opacity:.9}
.bar{fill:var(--wire)}
.busstub{stroke:var(--wire);stroke-width:3.2}
.slash{stroke:var(--wire);stroke-width:1.2}
.bw{font-size:6.5px;fill:var(--wire)}
.bl{font-size:7.5px;font-weight:bold;fill:var(--wire)}
.bi{font-size:5.5px;fill:var(--muted)}
.bus.hl .buswire,.bus:hover .buswire{stroke:var(--hl);stroke-width:4.5}
.port{fill:var(--port);stroke:var(--ink);stroke-width:1.2}
.frame rect{fill:#f3efe4;stroke:#b9b09a;stroke-width:1;stroke-dasharray:5 3}
.frame.sub2 rect{fill:#ebe5d4;stroke:#a89c7e}
.fl{font-size:9px;font-weight:bold;fill:#7a6f55}
.port.unused{fill:none;stroke-dasharray:3 2;stroke:var(--muted)}
.flag polygon{fill:#fff6d8;stroke:#b08a2e;stroke-width:.8}
.ft{font-size:6.5px;fill:#6b5310}
.dekring{fill:none;stroke:#8a3b1c;stroke-width:1}
.dekcat{fill:#8a3b1c;opacity:.35}.dekcat.on{fill:#ff6a1a;opacity:1}
.net:hover .wire,.hl .wire,.wire.hl{stroke:var(--hl);stroke-width:2.2}
.net.hl .jn,.net:hover .jn{fill:var(--hl)}
.pin.hl{stroke:var(--hl);stroke-width:2.2}
.flag.hl polygon{fill:#ffd1e0;stroke:var(--hl)}
.nl.hl{fill:var(--hl);opacity:1;font-weight:bold}
.cell.sel .body{stroke:var(--hl);stroke-width:2.2}
[data-sheet]{cursor:pointer}
'''

# Colours are substituted as literals: librsvg and Inkscape ignore CSS variables
PALETTE = {'paper': '#fbfaf6', 'ink': '#1d2329', 'wire': '#2a4a6b', 'muted': '#6b7480', 'port': '#e9eef3',
           'n16': '#dfe9f7', 'j2': '#f8e7c8', 'x7': '#dcefdc', 'mix': '#ece0f3', 'dek': '#fbd9c9',
           'sub': '#eceae2', 'gen': '#f1f1f1', 'hl': '#d6336c'}
CSS = re.sub(r'var\(--(\w+)\)', lambda m: PALETTE[m.group(1)], _CSS)


# ----------------------------------------------------------------- driver

def run_elk(graph):
    node = shutil.which('node')
    if not node:
        sys.exit('netview: node.js is needed for the ELK layout')
    if not os.path.isdir(os.path.join(HERE, 'node_modules', 'elkjs')):
        sys.exit(f'netview: elkjs missing; run `npm install` in {HERE}')
    r = subprocess.run([node, os.path.join(HERE, 'elk_layout.mjs')], input=json.dumps(graph),
                       capture_output=True, text=True, cwd=HERE)
    if r.returncode:
        sys.exit('netview: ELK failed\n' + r.stderr)
    return json.loads(r.stdout)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('json', nargs='+', help='Yosys write_json netlists')
    ap.add_argument('-o', '--out', default='sch', help='output directory (default: sch)')
    ap.add_argument('-l', '--lib', default=DEFAULT_LIB, help='liberty with the cell pins and tubes')
    ap.add_argument('--fanout', type=int, default=7,
                    help='nets with at least this many sinks get flags instead of wires (default 7)')
    ap.add_argument('--global', dest='global_re', default=r'clk|.*_rst|rst_n',
                    help='regex of net names that always get flags (default: clocks and reset lines)')
    ap.add_argument('--seq-cut', type=int, default=2,
                    help='flip-flop/latch outputs with at least this many sinks get flags (0: route them)')
    ap.add_argument('--no-group', dest='group', action='store_false',
                    help='no function frames: one flat layout per sheet')
    ap.add_argument('--group-max', type=int, default=25,
                    help='a group larger than this gets sub-frames by the exact signal (0: never)')
    ap.add_argument('--buses', default='frames', choices=['frames', 'vectors', 'off'],
                    help='between frames: one bus per frame pair (frames), per vector (vectors), '
                         'or every net on its own (off)')
    ap.add_argument('--group-min', type=int, default=3,
                    help='smallest group that gets a frame (default 3 cells)')
    ap.add_argument('--only', default='', help='regex: draw only the sheets whose module name matches')
    ap.add_argument('--placement', default='NETWORK_SIMPLEX',
                    choices=['NETWORK_SIMPLEX', 'BRANDES_KOEPF', 'LINEAR_SEGMENTS', 'SIMPLE'])
    ap.add_argument('--thoroughness', type=int, default=20)
    ap.add_argument('--node-gap', type=int, default=18)
    ap.add_argument('--layer-gap', type=int, default=36)
    args = ap.parse_args()

    lib = read_liberty(args.lib)
    os.makedirs(args.out, exist_ok=True)
    done = set()
    for path in args.json:
        d = json.load(open(path))
        mods = d['modules']
        real = {k: v for k, v in mods.items()
                if k not in lib and not int(str(v.get('attributes', {}).get('blackbox', '0')), 2)
                and v.get('cells')}
        # sheet titles: a submodule variant is named after the instances that use it
        titles = {}
        users = defaultdict(list)
        for mn, m in real.items():
            for cn, c in m['cells'].items():
                if c['type'] in real:
                    users[c['type']].append(cn.lstrip('\\'))
        for mn in real:
            if mn in users:
                u = users[mn]
                titles[mn] = f'{short_type(mn)} — {", ".join(u[:2])}{f" и ещё {len(u) - 2}" if len(u) > 2 else ""}'
        for mn, m in real.items():
            sid = sheet_id(mn)
            if sid in done or (args.only and not re.search(args.only, mn)):
                continue
            done.add(sid)
            sh = Sheet(mn, m, lib, real, args, titles)
            sh.top = mn not in users
            lay = run_elk(sh.elk_graph())
            svg = sh.render(lay)
            open(os.path.join(args.out, sid + '.svg'), 'w').write(svg)
            print(f'{sid}.svg: {sh.stats["cells"]} cells, {sh.stats["tubes"]:g} tubes, '
                  f'{len(sh.edges)} wires, {len(sh.glob)} flagged nets')
    write_index(args.out)
    write_bat(args.out)


def write_bat(out):
    """open_chrome.bat next to index.html: Chrome with file:// reads allowed (WSL only).

    index.html loads the sheets with XHR, which Chrome blocks on file:// (CORS, origin null)
    unless it runs with --allow-file-access-from-files. The flag is ignored by a Chrome that is
    already running, so the bat starts a separate profile.
    """
    wslpath = shutil.which('wslpath')
    if not wslpath:
        return
    r = subprocess.run([wslpath, '-w', os.path.abspath(os.path.join(out, 'index.html'))],
                       capture_output=True, text=True)
    if r.returncode or not r.stdout.strip():
        return
    page = r.stdout.strip()
    lines = [
        '@echo off',
        'rem DekatronPC netlist viewer (tools/netview/netview.py writes this file).',
        'rem index.html loads the sheets from file://, which Chrome allows only with',
        'rem --allow-file-access-from-files; a running Chrome ignores the flag, hence the own profile.',
        f'set "PAGE={page}"',
        'set "CHROME=%ProgramFiles%\\Google\\Chrome\\Application\\chrome.exe"',
        'if not exist "%CHROME%" set "CHROME=%ProgramFiles(x86)%\\Google\\Chrome\\Application\\chrome.exe"',
        'if not exist "%CHROME%" set "CHROME=%LocalAppData%\\Google\\Chrome\\Application\\chrome.exe"',
        'if not exist "%CHROME%" (echo Chrome not found & pause & exit /b 1)',
        'start "" "%CHROME%" --allow-file-access-from-files --user-data-dir="%LocalAppData%\\dpc-netview-chrome" '
        '--no-first-run "file:%PAGE:\\=/%"',
    ]
    with open(os.path.join(out, 'open_chrome.bat'), 'w', newline='\r\n') as f:
        f.write('\n'.join(lines) + '\n')


def write_index(out):
    """index.html over every sheet in the directory, so separate runs add up."""
    sheets = []
    for f in sorted(os.listdir(out)):
        if not f.endswith('.svg'):
            continue
        head = open(os.path.join(out, f)).read(2000)
        a = dict(re.findall(r'data-(title|cells|tubes|top)="([^"]*)"', head))
        if 'title' not in a:
            continue
        st = {'cells': int(a['cells']), 'tubes': float(a['tubes'])}
        sheets.append((f[:-4], html.unescape(a['title']), st, a['top'] == '1', ''))
    sheets.sort(key=lambda s: (not s[3], s[0]))
    items = ''.join(
        f'<li data-id="{html.escape(s)}"{" class=top" if top else ""}><b>{html.escape(t)}</b>'
        f'<span>{st["cells"]} ячеек · {st["tubes"]:g} ламп</span></li>'
        for s, t, st, top, _ in sheets)
    page = INDEX.replace('%ITEMS%', items)
    open(os.path.join(out, 'index.html'), 'w').write(page)


INDEX = r'''<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>DekatronPC netlists</title>
<style>
:root{--bg:#f3f1ea;--panel:#fffdf8;--ink:#1d2329;--muted:#6b7480;--line:#d9d4c7;--acc:#d6336c}
@media (prefers-color-scheme:dark){:root{--bg:#16191d;--panel:#1f2328;--ink:#e6e3da;--muted:#9aa3ad;--line:#353b42}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:13px/1.4 system-ui,sans-serif;display:flex;height:100vh}
nav{width:260px;flex:none;background:var(--panel);border-right:1px solid var(--line);display:flex;flex-direction:column}
nav h1{font-size:14px;margin:14px 14px 8px}
nav input{margin:0 12px 10px;padding:6px 8px;border:1px solid var(--line);border-radius:6px;background:var(--bg);color:var(--ink)}
nav ul{list-style:none;margin:0;padding:0;overflow:auto;flex:1}
nav li{padding:7px 14px;cursor:pointer;border-left:3px solid transparent}
nav li span{display:block;color:var(--muted);font-size:11px}
nav li.top b::before{content:"▣ ";color:var(--acc)}
nav li.on{background:var(--bg);border-left-color:var(--acc)}
nav .help{padding:10px 14px;color:var(--muted);font-size:11px;border-top:1px solid var(--line)}
main{flex:1;position:relative;overflow:hidden;cursor:grab}
main.drag{cursor:grabbing}
#view{position:absolute;left:0;top:0;transform-origin:0 0}
#info{position:absolute;right:12px;bottom:12px;background:var(--panel);border:1px solid var(--line);border-radius:6px;
padding:6px 10px;font:12px monospace;max-width:50%;white-space:pre-wrap;display:none}
@media (max-width:700px){body{flex-direction:column}nav{width:auto;height:35vh}}
</style></head><body>
<nav><h1>Нетлисты DekatronPC</h1>
<input id="q" placeholder="поиск: цепь или ячейка" autocomplete="off">
<ul id="list">%ITEMS%</ul>
<div class="help">колесо — масштаб, перетаскивание — сдвиг, клик по проводу/выводу — подсветка цепи,
клик по ячейке — её цепи, двойной клик по модулю — его лист, 0 — вписать</div></nav>
<main id="main"><div id="view"></div><div id="info"></div></main>
<script>
const view=document.getElementById('view'),main=document.getElementById('main'),info=document.getElementById('info');
let s=1,tx=0,ty=0,cur=null;
const apply=()=>view.style.transform=`translate(${tx}px,${ty}px) scale(${s})`;
function fit(){const svg=view.querySelector('svg');if(!svg)return;const w=svg.width.baseVal.value,h=svg.height.baseVal.value;
s=Math.min(main.clientWidth/w,main.clientHeight/h)*0.97;tx=(main.clientWidth-w*s)/2;ty=(main.clientHeight-h*s)/2;apply();}
// XHR, not fetch: Chrome reads file:// with --allow-file-access-from-files only through XHR (open_chrome.bat)
function get(url){return new Promise((ok,no)=>{const x=new XMLHttpRequest();x.open('GET',url);
x.onload=()=>(x.status===200||x.status===0)&&x.responseText?ok(x.responseText):no(x.status);x.onerror=()=>no('blocked');x.send()})}
async function load(id){cur=id;let s;try{s=await get(id+'.svg')}catch(e){view.innerHTML='<p style="padding:20px;font:14px sans-serif">'+
'Браузер не дал прочитать '+id+'.svg с file://. Откройте через open_chrome.bat рядом с index.html '+
'или через сервер: python3 -m http.server -d &lt;папка&gt;</p>';return}view.innerHTML=s;
document.querySelectorAll('#list li').forEach(li=>li.classList.toggle('on',li.dataset.id===id));
try{location.hash=id}catch(e){}fit();}
function clear(){view.querySelectorAll('.hl,.sel').forEach(e=>e.classList.remove('hl','sel'));info.style.display='none';}
function hl(nets){clear();const set=new Set(nets);
view.querySelectorAll('.bus').forEach(b=>{if(set.has(b.dataset.net))b.dataset.bits.split(' ').forEach(x=>set.add(x))});
view.querySelectorAll('[data-net]').forEach(e=>{if(set.has(e.dataset.net)||(e.dataset.bits&&e.dataset.bits.split(' ').some(x=>set.has(x))))e.classList.add('hl')});
info.textContent=[...set].join('\n');info.style.display=set.size?'block':'none';}
document.getElementById('list').onclick=e=>{const li=e.target.closest('li');if(li)load(li.dataset.id)};
let drag=null,moved=false;
main.onmousedown=e=>{drag=[e.clientX-tx,e.clientY-ty];moved=false;main.classList.add('drag')};
window.onmousemove=e=>{if(!drag)return;moved=true;tx=e.clientX-drag[0];ty=e.clientY-drag[1];apply()};
window.onmouseup=()=>{drag=null;main.classList.remove('drag')};
main.onwheel=e=>{e.preventDefault();const k=Math.exp(-e.deltaY*0.0015),r=main.getBoundingClientRect(),
x=e.clientX-r.left,y=e.clientY-r.top;tx=x-(x-tx)*k;ty=y-(y-ty)*k;s*=k;apply()};
view.onclick=e=>{if(moved)return;const n=e.target.closest('[data-net]');if(n){hl([n.dataset.net]);return}
const c=e.target.closest('.cell');if(c){const nets=[...c.querySelectorAll('[data-net]')].map(x=>x.dataset.net);hl(nets);
c.classList.add('sel');info.textContent=c.querySelector('title').textContent+'\n—\n'+info.textContent;return}clear()};
view.ondblclick=e=>{const c=e.target.closest('[data-sheet]');if(c)load(c.dataset.sheet)};
window.onkeydown=e=>{if(e.target.tagName==='INPUT')return;if(e.key==='0')fit();if(e.key==='Escape')clear()};
document.getElementById('q').onkeydown=e=>{if(e.key!=='Enter')return;const q=e.target.value.trim().toLowerCase();if(!q)return clear();
const nets=new Set();view.querySelectorAll('[data-net]').forEach(x=>{if(x.dataset.net.toLowerCase().includes(q))nets.add(x.dataset.net)});
if(nets.size){hl([...nets]);return}const c=[...view.querySelectorAll('.cell')].find(x=>x.dataset.name.toLowerCase().includes(q));
if(c){clear();c.classList.add('sel');const b=c.getBBox(),m=c.getCTM();
const vb=view.querySelector('svg').viewBox.baseVal;const sx=(m.e-vb.x),sy=(m.f-vb.y);
s=2;tx=main.clientWidth/2-sx*s;ty=main.clientHeight/2-sy*s;apply();}};
window.onresize=fit;
const first=(location.hash||'').slice(1)||document.querySelector('#list li')?.dataset.id;if(first)load(first);
</script></body></html>
'''

if __name__ == '__main__':
    main()
