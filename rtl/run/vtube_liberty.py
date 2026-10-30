#!/usr/bin/env python3
"""Timing liberty of the vacuum-tube cells (doc/vtube_sta.md).

vtube_cells.lib carries the functions, areas and tube counts that synthesis
uses; the delays live only in vtube_timing.json. This script joins the two
into vtube_cells_timing.lib, a liberty with NLDM timing that an STA tool can
read (rtl/run/vtube_sta.py, or OpenSTA). It is generated: edit the sources.

  * load unit: one triode grid (capacitive_load_unit 1 pf stands for it);
    an input pin's capacitance is its fanout_load, which must equal
    vtube_c1 / 3.9 pF (the C1 rule of doc/cell_design_method.md: a pentode
    g3 = 1.74, a 2.7 pF grid = 0.69); the script stops on a mismatch;
  * every arc is a 3-point table over 2 / 6 / 10 grids: the fanout-6 value
    of vtube_timing.json times its "fanout" ratios (flat if none);
  * timing_sense comes from the pin function; GUIDE_EN_J2 and RELAY_2CO
    have none and get non_unate;
  * flip-flops: "negedge C->Q" is a falling_edge arc, "setuphold" gives
    setup_falling / hold_falling on D, RN / SN arcs are clear / preset.

usage: vtube_liberty.py [-l vtube_cells.lib] [-T vtube_timing.json] [-o vtube_cells_timing.lib]
The module also holds the liberty parser and the function evaluator used by
vtube_sta.py.
"""
import argparse
import itertools
import json
import os
import re
import sys

GRIDS = [2.0, 6.0, 10.0]
C1_TRIODE = 3.9   # pF of divider C1 per triode grid: one load unit


# --------------------------------------------------------------------------
# Liberty parser: groups as (name, args, items), attributes as (name, value)
# --------------------------------------------------------------------------
class QStr(str):
    """A value that was quoted in the source."""


class Group:
    def __init__(self, name, args):
        self.name, self.args, self.items = name, args, []

    def groups(self, name=None):
        return [i for i in self.items if isinstance(i, Group) and (name is None or i.name == name)]

    def attr(self, name, default=None):
        for i in self.items:
            if isinstance(i, tuple) and i[0] == name:
                return i[1]
        return default


_TOK = re.compile(r'\s+|//[^\n]*|/\*.*?\*/|\\\n|("(?:[^"\\]|\\.)*")|([(){}:;,])|([^\s(){}:;,"]+)', re.S)


def _tokens(text):
    for m in _TOK.finditer(text):
        if m.group(1) is not None:
            yield QStr(m.group(1)[1:-1])
        elif m.group(2) is not None:
            yield m.group(2)
        elif m.group(3) is not None:
            yield m.group(3)


def parse_liberty(path):
    toks = list(_tokens(open(path).read()))
    pos = 0

    def body(group):
        nonlocal pos
        while pos < len(toks) and toks[pos] != '}':
            name = toks[pos]
            pos += 1
            if toks[pos] == ':':
                group.items.append((name, toks[pos + 1]))
                pos += 2
                if pos < len(toks) and toks[pos] == ';':
                    pos += 1
            elif toks[pos] == '(':
                pos += 1
                args = []
                while toks[pos] != ')':
                    if toks[pos] != ',':
                        args.append(toks[pos])
                    pos += 1
                pos += 1
                if pos < len(toks) and toks[pos] == '{':
                    pos += 1
                    g = Group(name, args)
                    body(g)
                    pos += 1
                    group.items.append(g)
                else:
                    group.items.append((name, args))
                    if pos < len(toks) and toks[pos] == ';':
                        pos += 1
            else:
                sys.exit(f'{path}: cannot parse near {toks[pos - 1:pos + 3]}')

    top = Group('top', [])
    body(top)
    return top.groups('library')[0]


# --------------------------------------------------------------------------
# Liberty boolean functions: ' and ! (not), * & and juxtaposition (and),
# + | (or), ^ (xor), parentheses, 0 / 1
# --------------------------------------------------------------------------
def parse_function(text):
    toks = re.findall(r"[A-Za-z_][A-Za-z0-9_]*|[01]|[()'!*&+|^]", text)
    pos = 0

    def peek():
        return toks[pos] if pos < len(toks) else None

    def primary():
        nonlocal pos
        t = peek()
        if t == '!':
            pos += 1
            node = ('not', primary())
        elif t == '(':
            pos += 1
            node = expr()
            pos += 1
        else:
            pos += 1
            node = ('const', t == '1') if t in ('0', '1') else ('var', t)
        while peek() == "'":
            pos += 1
            node = ('not', node)
        return node

    def term():
        nonlocal pos
        node = primary()
        while peek() in ('*', '&', '!', '(') or (peek() and re.match(r'[A-Za-z_01]', peek())):
            if peek() in ('*', '&'):
                pos += 1
            node = ('and', node, primary())
        return node

    def expr():
        nonlocal pos
        node = term()
        while peek() in ('+', '|', '^'):
            op = 'xor' if toks[pos] == '^' else 'or'
            pos += 1
            node = (op, node, term())
        return node

    return expr()


def eval_function(node, env):
    k = node[0]
    if k == 'var':
        return env[node[1]]
    if k == 'const':
        return node[1]
    if k == 'not':
        return not eval_function(node[1], env)
    a, b = eval_function(node[1], env), eval_function(node[2], env)
    return (a and b) if k == 'and' else (a or b) if k == 'or' else (a != b)


def timing_sense(function, pin, inputs):
    """positive_unate / negative_unate / non_unate of pin in function."""
    tree = parse_function(function)
    others = [p for p in inputs if p != pin]
    pos = neg = False
    for vals in itertools.product([False, True], repeat=len(others)):
        env = dict(zip(others, vals))
        lo = eval_function(tree, dict(env, **{pin: False}))
        hi = eval_function(tree, dict(env, **{pin: True}))
        pos |= (not lo) and hi
        neg |= lo and not hi
    return 'non_unate' if pos and neg else 'negative_unate' if neg else 'positive_unate'


# --------------------------------------------------------------------------
# Generator
# --------------------------------------------------------------------------
def fmt_values(vals):
    return '"' + ', '.join(f'{v:.4g}' for v in vals) + '"'


def arc_values(value, ratios):
    """value at fanout 6 -> list over GRIDS"""
    return [value * r for r in ratios]


def emit(group, out, indent=0, skip_attrs=()):
    pad = '  ' * indent
    for item in group.items:
        if isinstance(item, Group):
            out.append(f'{pad}{item.name}({", ".join(item.args)}) {{')
            emit(item, out, indent + 1, skip_attrs)
            out.append(f'{pad}}}')
        else:
            name, value = item
            if name in skip_attrs:
                continue
            if isinstance(value, list):
                out.append(f'{pad}{name}({", ".join(value)});')
            elif isinstance(value, QStr):
                out.append(f'{pad}{name} : "{value}";')
            else:
                out.append(f'{pad}{name} : {value};')


def table(kind, vals):
    return f'{kind}(fanout3) {{ values({fmt_values(vals)}); }}'


def build(lib_path, timing_path):
    lib = parse_liberty(lib_path)
    timing = json.load(open(timing_path))['cells']
    out = ['// GENERATED by rtl/run/vtube_liberty.py from vtube_cells.lib and vtube_timing.json.',
           '// Do not edit: change the sources and rerun (doc/vtube_sta.md).',
           '// Load unit: one grid (fanout_load); capacitive_load_unit says pf only because liberty needs a unit.',
           f'library({lib.args[0]}_timing) {{',
           '  delay_model : table_lookup;',
           '  time_unit : "1ns";',
           '  capacitive_load_unit(1, pf);',
           '  voltage_unit : "1V";',
           '  current_unit : "1mA";',
           '  default_max_transition : 1000;',
           '  lu_table_template(fanout3) {',
           '    variable_1 : total_output_net_capacitance;',
           f'    index_1({fmt_values(GRIDS)});',
           '  }']
    for item in lib.items:
        if isinstance(item, tuple):
            if item[0] == 'define':
                out.append(f'  define({", ".join(item[1])});')
            continue
    missing = []
    for cell in lib.groups('cell'):
        name = cell.args[0]
        t = timing.get(name, {})
        if not t and name not in ('TIEHI', 'TIELO'):
            missing.append(name)
        iop = t.get('iopath', {})
        sh = t.get('setuphold', {})
        fo = t.get('fanout', {})
        rr = fo.get('rise', [1, 1, 1])
        fr = fo.get('fall', [1, 1, 1])
        pins = cell.groups('pin')
        inputs = [p.args[0] for p in pins if p.attr('direction') == 'input']
        ff = cell.groups('ff')
        clear_pins = {}
        if ff:
            for k, kind in (('clear', 'clear'), ('preset', 'preset')):
                f = ff[0].attr(k)
                if f:
                    clear_pins[re.sub(r"[^A-Za-z0-9_]", '', f)] = kind
        out.append(f'  cell({name}) {{')
        sub = Group(cell.name, cell.args)
        sub.items = [i for i in cell.items if not (isinstance(i, Group) and i.name == 'pin')]
        emit(sub, out, 2)
        for pin in pins:
            pname = pin.args[0]
            out.append(f'    pin({pname}) {{')
            emit(pin, out, 3)
            if pin.attr('direction') == 'input':
                # load in triode grids: fanout_load = vtube_c1 / 3.9 pF (cell_design_method §2)
                cap = float(pin.attr('fanout_load', 1.0))
                c1 = pin.attr('vtube_c1')
                if c1 and abs(cap - float(c1) / C1_TRIODE) > 0.02:
                    sys.exit(f'{lib_path}: {name}.{pname} fanout_load {cap:g} != vtube_c1 / {C1_TRIODE:g}')
                out.append(f'      capacitance : {cap:g};')
                if pname in sh:
                    su, ho = sh[pname]
                    for typ, v in (('setup_falling', su), ('hold_falling', ho)):
                        out.append('      timing() {')
                        out.append('        related_pin : "C";')
                        out.append(f'        timing_type : {typ};')
                        out.append(f'        {table("rise_constraint", [v] * 3)}')
                        out.append(f'        {table("fall_constraint", [v] * 3)}')
                        out.append('      }')
            else:
                func = pin.attr('function')
                for key, val in iop.items():
                    m = re.fullmatch(r'(posedge |negedge )?(\w+)->(\w+)', key)
                    edge, src, dst = m.groups()
                    if dst != pname:
                        continue
                    rise, fall = (val, val) if not isinstance(val, list) else val
                    lines = [f'related_pin : "{src}";']
                    if edge:
                        lines.append(f'timing_type : {"falling_edge" if edge == "negedge " else "rising_edge"};')
                        rv, fv = arc_values(rise, rr), arc_values(fall, fr)
                    elif src in clear_pins:
                        kind = clear_pins[src]
                        # clear: Q falls (positive_unate on RN), QN rises; preset the other way
                        q_rises = (kind == 'preset') == (pname == 'Q')
                        lines.append(f'timing_type : {kind};')
                        lines.append(f'timing_sense : {"negative_unate" if q_rises else "positive_unate"};')
                        if q_rises:
                            rv, fv = [rise] * 3, None
                        else:
                            rv, fv = None, [fall] * 3
                    else:
                        if func and src in inputs and func not in ('IQ', 'IQN'):
                            sense = timing_sense(func, src, inputs)
                        else:
                            sense = 'non_unate'
                        lines.append(f'timing_sense : {sense};')
                        rv, fv = arc_values(rise, rr), arc_values(fall, fr)
                    if rv:
                        lines.append(table('cell_rise', rv))
                        lines.append(table('rise_transition', [0] * 3))
                    if fv:
                        lines.append(table('cell_fall', fv))
                        lines.append(table('fall_transition', [0] * 3))
                    out.append('      timing() {')
                    out += ['        ' + ln for ln in lines]
                    out.append('      }')
            out.append('    }')
        out.append('  }')
    out.append('}')
    return '\n'.join(out) + '\n', missing


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    cells = os.path.normpath(os.path.join(here, '../../sch/logic'))
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('-l', default=os.path.join(cells, 'vtube_cells.lib'))
    ap.add_argument('-T', default=os.path.join(cells, 'vtube_timing.json'))
    ap.add_argument('-o', default=os.path.join(cells, 'vtube_cells_timing.lib'))
    a = ap.parse_args()
    text, missing = build(a.l, a.T)
    open(a.o, 'w').write(text)
    print(f'{a.o}: written' + (f'; no timing for {", ".join(missing)}' if missing else ''))


if __name__ == '__main__':
    main()
