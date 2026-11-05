#!/usr/bin/env python3
"""Follower -> follower legalization on a mapped Yosys JSON netlist (doc/wired_anode.md part 2).

A cathode-follower cell (output vtube_level LV) can't drive a follower grid (div_insert.py reports it).
For every such edge A -> B one of the two cells is turned into its inverting plate cell (same tubes: NOR,
NAND, AOI, found in the liberty by the complemented function) followed by a NOT_N16: its output is then HV
and legal on any grid, and its own inputs become ordinary grids that accept LV. The cells to turn are a
minimum-cost vertex cover of the follower graph of each module (exact, branch and bound per component) with the cost of the conversion
(+0.5 tube for the NOT, BUF: two NOTs).

usage: legalize_followers.py -l lib -i in.json -o out.json
Prints the cells turned and the tube delta per module; the output JSON goes through div_insert.py to check.
"""
import argparse, json, re, sys, os, itertools, subprocess
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../rtl/run"))
from div_insert import lib_pins

def lib_cells(text):
    cells = {}
    for m in re.finditer(r'cell\s*\(\s*(\w+)\s*\)\s*\{', text):
        nxt = text.find('cell(', m.end()); nxt2 = text.find('cell (', m.end())
        ends = [x for x in (nxt, nxt2) if x != -1]
        body = text[m.end():min(ends) if ends else len(text)]
        a = re.search(r'\barea\s*:\s*([\d.]+)', body)
        f = re.findall(r'function\s*:\s*"([^"]*)"', body)
        cells[m.group(1)] = dict(area=float(a.group(1)) if a else 0.0, funcs=f,
                                 dont_use='dont_use : true' in body or 'dont_use: true' in body)
    return cells

def tt(expr, pins):
    """truth table of a liberty function: * and, + or, postfix ' not, parentheses"""
    toks = re.findall(r"[A-Z]+|[()*+']", expr)
    def parse_or(i):
        v, i = parse_and(i)
        while i < len(toks) and toks[i] == '+':
            w, i = parse_and(i + 1); v = (lambda a, b: lambda e: a(e) or b(e))(v, w)
        return v, i
    def parse_and(i):
        v, i = parse_not(i)
        while i < len(toks) and toks[i] == '*':
            w, i = parse_not(i + 1); v = (lambda a, b: lambda e: a(e) and b(e))(v, w)
        return v, i
    def parse_not(i):
        if toks[i] == '(':
            v, i = parse_or(i + 1); i += 1
        else:
            v = (lambda n: lambda e: e[n])(toks[i]); i += 1
        while i < len(toks) and toks[i] == "'":
            v = (lambda a: lambda e: not a(e))(v); i += 1
        return v, i
    f, _ = parse_or(0)
    return tuple(bool(f(dict(zip(pins, bits)))) for bits in itertools.product([False, True], repeat=len(pins)))

def components(names, edges):
    par = {n: n for n in names}
    def f(x):
        while par[x] != x: par[x] = par[par[x]]; x = par[x]
        return x
    for u, v in edges: par[f(u)] = f(v)
    g = {}
    for n in names: g.setdefault(f(n), set()).add(n)
    return list(g.values())

def min_cover(nodes, edges, w):
    """exact minimum-weight vertex cover: branch on the vertex of the highest degree, v in the cover or all
    its neighbours in it; a matching bound prunes"""
    best = [sum(w.values()), set(nodes)]
    def bound(es):                      # greedy matching: each matched edge needs its cheaper end
        used = set(); s = 0.0
        for u, v in es:
            if u not in used and v not in used:
                used |= {u, v}; s += min(w[u], w[v])
        return s
    def rec(es, chosen, c):
        if c + bound(es) >= best[0] - 1e-9: return
        if not es:
            best[0], best[1] = c, set(chosen); return
        deg = {}
        for u, v in es: deg[u] = deg.get(u, 0) + 1; deg[v] = deg.get(v, 0) + 1
        x = max(deg, key=lambda n: (deg[n] / w[n], n))
        nb = {v if u == x else u for u, v in es if x in (u, v)}
        rec([e for e in es if x not in e], chosen | {x}, c + w[x])
        rec([e for e in es if not (e[0] in nb or e[1] in nb)], chosen | nb, c + sum(w[n] for n in nb))
    rec(sorted(edges), frozenset(), 0.0)
    return sorted(best[1])

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-l', required=True); ap.add_argument('-i', required=True); ap.add_argument('-o', required=True)
    a = ap.parse_args()
    text = open(a.l).read()
    pins = lib_pins(text); cells = lib_cells(text)
    follower = {c for c, p in pins.items() if any(v['dir'] == 'output' and v['level'] == 'LV' for v in p.values())
                and len(cells[c]['funcs']) == 1}
    # HV cell with the complemented function, by truth table (cheapest, not dont_use)
    twin = {}
    for c in follower:
        ins = sorted(p for p, v in pins[c].items() if v['dir'] == 'input')
        want = tuple(not x for x in tt(cells[c]['funcs'][0], ins))
        best = None
        for h, hp in pins.items():
            if h in follower or cells[h]['dont_use'] or len(cells[h]['funcs']) != 1: continue
            hin = sorted(p for p, v in hp.items() if v['dir'] == 'input')
            if hin != ins or hp.get('Y', {}).get('level') != 'HV': continue
            if tt(cells[h]['funcs'][0], ins) == want and (best is None or cells[h]['area'] < cells[best]['area']):
                best = h
        if best is None: print("no twin for", c, file=sys.stderr); continue
        twin[c] = best
    follower &= set(twin)
    cost = {}
    for c in follower:
        # the plate cell plus a NOT; a BUF becomes NOT + NOT
        cost[c] = cells[twin[c]]['area'] + 0.5 - cells[c]['area']
    raw = open(a.i).read()
    force = {}
    for it in range(20):
        data = json.loads(raw)
        total, nconv = legalize(data, force, follower, twin, cost, pins)
        json.dump(data, open(a.o, 'w'))
        # LV nets from cells that are not followers (decoders, ports) can only be cured at the receiver
        r = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../rtl/run/div_insert.py"),
                            '-l', a.l, '-i', a.o, '-o', os.devnull], capture_output=True, text=True)
        bad = re.findall(r"^\s+(\S.*?): LV net .+? drives a cathode-follower grid (\S+)\.\w+$", r.stdout + r.stderr, re.M)
        new = {(m_, c_) for m_, c_ in bad if c_ not in force.get(m_, set()) and not c_.endswith('_leg')}
        print("pass %d: turned %d, +%.1f tubes, %d follower-grid errors left" % (it, nconv, total, len(bad)))
        if not bad: break
        if not new: print("cannot cure:", bad[:3]); break
        for m_, c_ in new: force.setdefault(m_, set()).add(c_)

def legalize(data, force, follower, twin, cost, pins):
    total = 0.0; nconv = 0
    for mn, m in data['modules'].items():
        cs = m.get('cells', {})
        fol = {n: c for n, c in cs.items() if c['type'] in follower}
        if not fol: continue
        out_bit = {}
        for n, c in fol.items():
            for p, v in pins[c['type']].items():
                if v['dir'] == 'output': out_bit[c['connections'][p][0]] = n
        edges = set()
        for n, c in fol.items():
            for p, v in pins[c['type']].items():
                if v['dir'] == 'input' and v['grid'] == 'follower':
                    for b in c['connections'][p]:
                        if b in out_bit: edges.add((out_bit[b], n))
        pre = force.get(mn, set())
        if not edges and not pre: continue
        names = sorted({x for e in edges for x in e}); idx = {n: i for i, n in enumerate(names)}
        edges = {e for e in edges if e[0] not in pre and e[1] not in pre}
        names = sorted({x for e in edges for x in e})
        pick = [n for n in sorted(pre) if n in fol]
        for comp in components(names, edges):
            pick += min_cover(comp, [e for e in edges if e[0] in comp], {n: cost[fol[n]['type']] for n in comp})
        nxt = max([b for c in cs.values() for v in c['connections'].values() for b in v if isinstance(b, int)] + [0]) + 1
        mt = 0.0
        for n in pick:
            c = cs[n]; old = c['type']; ypin = next(p for p, v in pins[old].items() if v['dir'] == 'output')
            yb = c['connections'][ypin][0]
            if twin[old] == 'NOT_N16':              # BUF: NOT, NOT
                mid = nxt; nxt += 1
                c['type'] = 'NOT_N16'; c['port_directions'] = {'A': 'input', 'Y': 'output'}
                c['connections'] = {'A': c['connections']['A'], 'Y': [mid]}
                cs[n + '_leg'] = dict(hide_name=1, type='NOT_N16', parameters={}, attributes={},
                                      port_directions={'A': 'input', 'Y': 'output'}, connections={'A': [mid], 'Y': [yb]})
            else:
                mid = nxt; nxt += 1
                c['type'] = twin[old]; c['connections'][ypin] = [mid]
                c['port_directions'] = {p: ('output' if p == ypin else 'input') for p in c['connections']}
                cs[n + '_leg'] = dict(hide_name=1, type='NOT_N16', parameters={}, attributes={},
                                      port_directions={'A': 'input', 'Y': 'output'}, connections={'A': [mid], 'Y': [yb]})
            mt += cost[old]
        if os.environ.get("LEG_VERBOSE"): print("%-28s followers %3d  edges %3d  turned %3d  +%.1f tubes" % (mn[-28:], len(fol), len(edges), len(pick), mt))
        total += mt; nconv += len(pick)
    return total, nconv

if __name__ == '__main__':
    main()
