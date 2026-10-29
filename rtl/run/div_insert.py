"""Insert the HV -> LV dividers into a mapped netlist and check the signal levels.

Every gate plate is HV (+150 / +50 V); every grid wants LV (+10 / -20 V). Between them sits a divider
R1 470k || C1 / R2 200k to -50 V (REQ-MOD-012). The divider is a cell of its own, DIV_HL, so P&R sees
it and can put it on the board of the source or of the receiver (doc/hv_lv_dividers.md).

The levels come from the liberty pin attributes (vtube_level, vtube_grid, vtube_c1; defaults: an output
is HV, an input is a triode grid with C1 3.9 pF). For each net of each module:
  HV net    -> one DIV_HL for its gate grids and a separate one for its cathode-follower grids
               (BUF_N16 / OR2_N16 need their own divider, sch/logic/BUF_N16/README.md); C1 = sum of vtube_c1.
               The divider sits in the module that holds the grids: a net entering a module through a
               port gets its divider inside that module, so ports carry HV.
  LV net    -> (a cathode follower output) no divider. A follower grid on it is an error; leaving the
               module through a port is a warning (LV over a connector).
  constant  -> grids tied to a constant are listed (they need a bias network, not a divider).
Relay contacts (vtube_level PASS) carry the level of what drives them.

usage: div_insert.py -l vtube_cells.lib -i in.json -o out.json [--top-inputs HV|LV] [--strict]
The input is a Yosys JSON netlist after mapping (synt_dpc.tcl -div runs it after qn_absorb.py).
"""

import argparse
import json
import re
import sys

DEFAULT_C1 = 3.9


def lib_pins(lib_text):
    """cell -> pin -> dict(dir, level, grid, c1) from the liberty text"""
    cells = {}
    for m in re.finditer(r'cell\s*\(\s*(\w+)\s*\)\s*\{', lib_text):
        name = m.group(1)
        depth, j = 0, m.end() - 1
        for j in range(m.end() - 1, len(lib_text)):
            if lib_text[j] == '{':
                depth += 1
            elif lib_text[j] == '}':
                depth -= 1
                if depth == 0:
                    break
        body = lib_text[m.end():j]
        pins = {}
        for pm in re.finditer(r'pin\s*\(\s*(\w+)\s*\)\s*\{([^}]*)\}', body):
            attrs = dict((k, v.strip().strip('"')) for k, v in re.findall(r'(\w+)\s*:\s*([^;]+);', pm.group(2)))
            d = attrs.get('direction', 'input')
            level = attrs.get('vtube_level', 'HV' if d == 'output' else 'GRID')
            pins[pm.group(1)] = dict(dir=d, level=level, grid=attrs.get('vtube_grid', 'triode'),
                                     c1=float(attrs.get('vtube_c1', DEFAULT_C1)),
                                     max_fanout=int(float(attrs.get('max_fanout', 10))))
        cells[name] = pins
    return cells


def bits32(v):
    return format(int(v), '032b')


class Netlist:
    def __init__(self, data, lib, top_inputs):
        self.mods = {n: m for n, m in data['modules'].items()
                     if not int(str(m.get('attributes', {}).get('blackbox', '0')) or '0', 2)}
        self.lib = lib
        self.top_inputs = top_inputs
        self.in_level = {}           # (module, port, index) -> level, from the instances
        self.unknown = {}            # cell types with no liberty entry and no module
        self.index()

    def index(self):
        self.drv, self.loads, self.unknown_bits = {}, {}, {}
        for mn, m in self.mods.items():
            drv, loads, unk = {}, {}, {}
            self.unknown_bits[mn] = unk
            for pn, p in m.get('ports', {}).items():
                for i, b in enumerate(p['bits']):
                    if not isinstance(b, int):
                        continue
                    if p['direction'] == 'input':
                        drv[b] = ('port', pn, i)
                    else:
                        loads.setdefault(b, []).append(('port', pn, i))
            for cn, c in m.get('cells', {}).items():
                t = c['type']
                known = t in self.lib or t in self.mods or 'port_directions' in c
                for pin, bits in c['connections'].items():
                    if not known:     # a black box with no liberty entry (Dekatron): it may drive any of its nets
                        for b in bits:
                            if isinstance(b, int):
                                unk.setdefault(b, set()).add(t)
                    dirn = self.pin_dir(t, pin, c)
                    for i, b in enumerate(bits):
                        if not isinstance(b, int):
                            continue
                        if dirn == 'output':
                            drv[b] = ('cell', cn, pin, i)
                        else:
                            loads.setdefault(b, []).append(('cell', cn, pin, i))
            self.drv[mn], self.loads[mn] = drv, loads

    def pin_dir(self, t, pin, c):
        if t in self.lib and pin in self.lib[t]:
            return self.lib[t][pin]['dir']
        if t in self.mods:
            return self.mods[t]['ports'][pin]['direction']
        return c.get('port_directions', {}).get(pin, 'input')

    def top(self):
        used = {c['type'] for m in self.mods.values() for c in m.get('cells', {}).values()}
        tops = [n for n in self.mods if n not in used]
        return tops

    # ---- levels
    def level(self, mn, b, seen=None):
        if not isinstance(b, int):
            return 'CONST' if b in ('0', '1') else 'UNDRIVEN'
        seen = seen or set()
        if (mn, b) in seen:
            return 'LOOP'
        seen = seen | {(mn, b)}
        d = self.drv[mn].get(b)
        if d is None:
            if b in self.unknown_bits[mn]:
                for t in self.unknown_bits[mn][b]:
                    self.unknown[t] = self.unknown.get(t, 0) + 1
                return 'UNKNOWN'
            return 'UNDRIVEN'
        if d[0] == 'port':
            return self.in_level.get((mn, d[1], d[2]), self.top_inputs if mn in self.tops else 'UNKNOWN')
        _, cn, pin, i = d
        c = self.mods[mn]['cells'][cn]
        t = c['type']
        if t in self.lib:
            lv = self.lib[t][pin]['level']
            if lv != 'PASS':
                return lv
            # a contact output (C1) carries the level of its own contacts (NC1, NO1): same trailing digits
            pole = re.sub(r'^\D*', '', pin)
            ins = {self.level(mn, bb, seen) for p, bits in c['connections'].items()
                   if self.lib[t].get(p, {}).get('level') == 'PASS' and self.lib[t][p]['dir'] == 'input'
                   and re.sub(r'^\D*', '', p) == pole for bb in bits}
            ins.discard('UNDRIVEN')
            if len(ins) > 1:
                ins.discard('CONST')      # a relay switching a signal against a constant: the signal's level
            return ins.pop() if len(ins) == 1 else ('MIXED' if ins else 'UNDRIVEN')
        if t in self.mods:
            sub = self.mods[t]
            if not sub.get('cells'):     # an empty stub of a black box (DekatronTubeV2 kept with -bb, OneShot)
                self.unknown[t] = self.unknown.get(t, 0) + 1
                return 'UNKNOWN'
            return self.level(t, sub['ports'][pin]['bits'][i], seen)
        self.unknown[t] = self.unknown.get(t, 0) + 1
        return 'UNKNOWN'

    def resolve(self):
        self.tops = set(self.top())
        for _ in range(20):
            new = {}
            for mn, m in self.mods.items():
                for cn, c in m.get('cells', {}).items():
                    if c['type'] not in self.mods:
                        continue
                    sub = self.mods[c['type']]
                    for pn, bits in c['connections'].items():
                        if sub['ports'][pn]['direction'] != 'input':
                            continue
                        for i, b in enumerate(bits):
                            lv = self.level(mn, b)
                            k = (c['type'], pn, i)
                            if k in new and new[k] != lv:
                                # instances differ: a constant on one of them takes the level of the others
                                lv = new[k] if lv == 'CONST' else lv if new[k] == 'CONST' else 'MIXED'
                            new[k] = lv
            if new == self.in_level:
                break
            self.in_level = new

    # ---- insertion
    def netname(self, mn, b):
        best = None
        for n, net in self.mods[mn].get('netnames', {}).items():
            if b in net['bits']:
                nm = n if len(net['bits']) == 1 else '%s[%d]' % (n, net['bits'].index(b))
                if best is None or (best.startswith('$') and not nm.startswith('$')):
                    best = nm
        return best or 'n%d' % b

    def run(self):
        rep = dict(divs=[], errors=[], warnings=[], ties=[], fanout=[])
        self.resolve()
        for mn, m in self.mods.items():
            nxt = max([b for net in m.get('netnames', {}).values() for b in net['bits'] if isinstance(b, int)] + [1]) + 1
            cells = m.setdefault('cells', {})
            for b, lds in sorted(self.loads[mn].items()):
                groups = {'gate': [], 'follower': []}
                ports_out = False
                for ld in lds:
                    if ld[0] == 'port':
                        ports_out = True
                        continue
                    _, cn, pin, i = ld
                    t = cells[cn]['type']
                    if t in self.lib:
                        p = self.lib[t].get(pin, {})
                        if p.get('level') == 'GRID':
                            groups['follower' if p['grid'] == 'follower' else 'gate'].append((cn, pin, i, p['c1']))
                if not groups['gate'] and not groups['follower'] and not ports_out:
                    continue
                lv = self.level(mn, b)
                name = self.netname(mn, b)
                ngrid = len(groups['gate']) + len(groups['follower'])
                d = self.drv[mn].get(b)
                if d and d[0] == 'cell':
                    t = cells[d[1]]['type']
                    mf = self.lib.get(t, {}).get(d[2], {}).get('max_fanout', 10)
                    if ngrid > mf:
                        rep['fanout'].append(f"{mn}: {name} ({t}) drives {ngrid} grids in this module, max_fanout {mf}")
                if lv == 'LV':
                    for cn, pin, i, _ in groups['follower']:
                        rep['errors'].append(f"{mn}: LV net {name} drives a cathode-follower grid {cn}.{pin}")
                    if ports_out:
                        rep['warnings'].append(f"{mn}: LV net {name} leaves the module through a port (LV over a connector)")
                    continue
                if lv == 'CONST':
                    n = len(groups['gate']) + len(groups['follower'])
                    if n:
                        rep['ties'].append(f"{mn}: {name} ({n} grids)")
                    continue
                if lv not in ('HV', 'UNKNOWN'):
                    if groups['gate'] or groups['follower']:
                        rep['warnings'].append(f"{mn}: net {name} level {lv}, grids left without a divider")
                    continue
                if lv == 'UNKNOWN' and (groups['gate'] or groups['follower']):
                    rep['warnings'].append(f"{mn}: net {name} has an unknown driver, treated as HV")
                for cls, g in groups.items():
                    if not g:
                        continue
                    c1 = sum(x[3] for x in g)
                    lvb = nxt; nxt += 1
                    suffix = '_lv' if cls == 'gate' else '_lvf'
                    for cn, pin, i, _ in g:
                        cells[cn]['connections'][pin][i] = lvb
                    dn = 'div_%s%s' % (re.sub(r'[^\w]', '_', name).strip('_'), suffix)
                    while dn in cells:
                        dn += '_'
                    cells[dn] = {'hide_name': 0, 'type': 'DIV_HL',
                                 'parameters': {'C1_DPF': bits32(round(c1 * 10)), 'GRIDS': bits32(len(g)),
                                                'CLASS': bits32(1 if cls == 'follower' else 0)},
                                 'attributes': {}, 'port_directions': {'HV': 'input', 'LV': 'output'},
                                 'connections': {'HV': [b], 'LV': [lvb]}}
                    m.setdefault('netnames', {})[name + suffix] = {'hide_name': 0, 'bits': [lvb], 'attributes': {}}
                    rep['divs'].append((mn, dn, cls, len(g), c1))
        for t, n in self.unknown.items():
            rep['warnings'].insert(0, f"{t.lstrip(chr(92))}: black box with no liberty entry, its outputs are UNKNOWN (treated as HV)")
        return rep


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('-l', '--lib', required=True)
    ap.add_argument('-i', '--input', required=True)
    ap.add_argument('-o', '--output', required=True)
    ap.add_argument('--top-inputs', default='HV', choices=['HV', 'LV'], help='level of the top module inputs')
    ap.add_argument('--strict', action='store_true', help='exit 1 on level errors')
    ap.add_argument('-v', '--verbose', action='store_true', help='list every divider and warning')
    a = ap.parse_args()
    data = json.load(open(a.input))
    # library cells come back as blackbox modules; the caller reads the liberty again (as qn_absorb.py)
    data['modules'] = {n: m for n, m in data['modules'].items()
                       if not int(str(m.get('attributes', {}).get('blackbox', '0')) or '0', 2)}
    nl = Netlist(data, lib_pins(open(a.lib).read()), a.top_inputs)
    rep = nl.run()
    json.dump(data, open(a.output, 'w'), indent=2)
    by = {}
    for mn, dn, cls, n, c1 in rep['divs']:
        s = by.setdefault((mn, cls), [0, 0, 0.0])
        s[0] += 1; s[1] += n; s[2] += c1
    print("div_insert: %d dividers" % len(rep['divs']))
    for (mn, cls), (k, n, c1) in sorted(by.items()):
        print("  %-28s %-8s %4d dividers, %5d grids, C1 total %.1f pF, largest net %d grids"
              % (mn.lstrip('\\'), cls, k, n, c1, max(x[3] for x in rep['divs'] if x[0] == mn and x[2] == cls)))
    for key in ('errors', 'fanout', 'warnings', 'ties'):
        if rep[key]:
            print("  %s: %d" % (key, len(rep[key])))
            for x in rep[key][: (None if a.verbose else 10)]:
                print("    " + x)
    if a.verbose:
        for d in rep['divs']:
            print("    %s %s %s grids=%d C1=%.1f pF" % d)
    if a.strict and rep['errors']:
        sys.exit(1)


if __name__ == '__main__':
    main()
