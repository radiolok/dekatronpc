#!/usr/bin/env python3
"""Static timing analysis of the tube netlist (doc/vtube_sta.md).

Reads a flat Yosys JSON netlist of DekatronPC (vtube_sta.sh makes it) and the
timing liberty vtube_cells_timing.lib (vtube_liberty.py). Each arc's delay is
read from its NLDM table at the load of the net it drives: the sum of the
capacitances (fanout_load, in grids) of the pins on that net. Times are in ns
from the rising edge of Clk at the Clk port. Late (max) and early (min)
arrivals are kept per edge and per signal class:

  clk   the Clk port and what is derived from it alone: the clock
        inverters and the phase generators (Impulse / OneShot chains,
        modelled from their parameters: OneShot = DELAY hsClk window from
        the rise of En, Impulse = one hsClk from the rise, or the fall if FALL)
  data  launched at a clock edge: a trigger (C active edge + C->Q), or the
        memory (Ram, IpMemory: ideal synchronous, outputs --mem-ns after the
        edge)
  tube  a dekatron's main cathodes: the end of the guide pulse plus
        FALL_STEP_HS, from the guide pins of the DekatronTubeDelay box. The
        reading is valid at the NEXT Clk edge (DekatronCounter: "after a step
        out is valid at the next clk edge"), so a tube path that reaches a
        step command is due before the phase of the next cycle.
  async not timed: OneShot / Impulse started by data (the write window), the
        reset relay, panel inputs, rst_n, relay coils.

Checks, for a Clk period T:
  setup   trigger D: late + setup <= T + clock at C (early);
          memory input: late <= T
  hold    trigger D: early >= clock at C (late) + hold
  gating  a cell where a clk pulse meets data (the step command meets a phase
          in DekatronPulseSender, the carry meets a guide in GUIDE_EN_J2):
            data settles before the pulse starts:  late(data) <= lead
            data holds until the pulse ends:       T + early(data) >= trail
            a cathode reading of cycle N is due at the pulse of cycle N+1:
                                                   late(tube) - T <= lead
The first condition sets the phase start delay (REQ-PULSE-009). Unless -p is
given, the report first shows the netlist as synthesized, then repeats the
analysis with the smallest DEKATRON_PHASE_DELAY_HS that meets it.

usage: vtube_sta.py -n flat.json [-l vtube_cells_timing.lib] [-p HS]
                    [-f KHZ ...] [--paths N] [--ideal-clock] [--mem-ns NS] [-o report.md]
"""
import argparse
import collections
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vtube_liberty import parse_liberty  # noqa: E402

HS_NS = 100.0
DATA = ('data', 'tube')


# --------------------------------------------------------------------------
# Library
# --------------------------------------------------------------------------
class Arc:
    def __init__(self, src, dst, kind, sense, rise, fall):
        self.src, self.dst, self.kind, self.sense = src, dst, kind, sense
        self.rise, self.fall = rise, fall   # values over the table index, or None


def interp(index, values, x):
    """Linear interpolation; below the table the first value (the sweeps start at
    fanout 2, so lighter nets are not taken faster than that), above it linear
    extrapolation."""
    if x <= index[0]:
        return values[0]
    i = 1
    while i < len(index) - 1 and x > index[i]:
        i += 1
    x0, x1, y0, y1 = index[i - 1], index[i], values[i - 1], values[i]
    return y0 + (y1 - y0) * (x - x0) / (x1 - x0)


def load_lib(path):
    lib = parse_liberty(path)
    index = [2.0, 6.0, 10.0]
    for t in lib.groups('lu_table_template'):
        idx = t.attr('index_1')
        if idx:
            index = [float(v) for v in idx[0].split(',')]
    cells = {}
    for cell in lib.groups('cell'):
        c = {'pins': {}, 'arcs': [], 'setup': {}, 'hold': {},
             'seq': bool(cell.groups('ff') or cell.groups('latch'))}
        for pin in cell.groups('pin'):
            pn = pin.args[0]
            c['pins'][pn] = {'dir': pin.attr('direction'), 'cap': float(pin.attr('capacitance', 1.0))}
            for tg in pin.groups('timing'):
                def tab(name):
                    g = tg.groups(name)
                    return [float(v) for v in g[0].attr('values')[0].split(',')] if g else None
                typ = tg.attr('timing_type', 'combinational')
                rel = tg.attr('related_pin')
                if typ.startswith('setup_') or typ.startswith('hold_'):
                    v = max(tab('rise_constraint')[0], tab('fall_constraint')[0])
                    c['setup' if typ.startswith('setup') else 'hold'][pn] = (rel, typ.endswith('falling'), v)
                    continue
                c['arcs'].append(Arc(rel, pn, typ, tg.attr('timing_sense', 'non_unate'),
                                     tab('cell_rise'), tab('cell_fall')))
        cells[cell.args[0]] = c
    return index, cells


# --------------------------------------------------------------------------
# Arrivals
# --------------------------------------------------------------------------
class Arr:
    __slots__ = ('late', 'early', 'pred', 'start', 'estart')

    def __init__(self):
        self.late = {'r': None, 'f': None}
        self.early = {'r': None, 'f': None}
        self.pred = {'r': None, 'f': None}   # (bit, class, edge, cell) or ('start', text)
        self.start = None
        self.estart = None

    def max_late(self):
        e = max((x for x in 'rf' if self.late[x] is not None), key=lambda x: self.late[x])
        return self.late[e], e

    def min_early(self):
        return min(v for v in self.early.values() if v is not None)


def bit_names(mod):
    best = {}
    for n, v in mod['netnames'].items():
        hidden = v.get('hide_name', 0)
        for i, b in enumerate(v['bits']):
            if isinstance(b, int):
                full = n + (f'[{i}]' if len(v['bits']) > 1 else '')
                key = (hidden, full.count('.'), len(full))
                if b not in best or key < best[b][0]:
                    best[b] = (key, full)
    return {b: v[1] for b, v in best.items()}


def short(s, n=70):
    s = str(s)
    return s if len(s) <= n else '…' + s[-(n - 1):]


class Sta:
    def __init__(self, mod, lib, phase_hs, ideal_clock, mem_ns, derate=1.0, phase_width_hs=None):
        self.index, self.lib = lib
        self.cells = mod['cells']
        self.names = bit_names(mod)
        self.phase_hs = phase_hs
        self.ideal_clock = ideal_clock
        self.mem_ns = mem_ns
        self.derate = derate
        self.phase_width_hs = phase_width_hs
        self.pulse_checks = []   # (cell, pin, source, pulse width in, delay of its leading edge)
        self.pulses = {}         # bit -> source -> (leading edge, width)
        self.drv, self.snk = {}, collections.defaultdict(list)
        for cn, c in self.cells.items():
            for p, bits in c['connections'].items():
                out = c['port_directions'].get(p) == 'output'
                for b in bits:
                    if isinstance(b, int):
                        if out:
                            self.drv[b] = (cn, p)
                        else:
                            self.snk[b].append((cn, p))
        self.load = {}
        for b, sinks in self.snk.items():
            cap = 0.0
            for cn, p in sinks:
                lc = self.lib.get(self.cells[cn]['type'])
                cap += lc['pins'][p]['cap'] if lc and p in lc['pins'] else 1.0
            self.load[b] = cap
        self.clk = mod['ports']['Clk']['bits'][0]
        self.arr = collections.defaultdict(dict)   # bit -> class -> Arr
        self.async_starts = []
        self.gating = []

    def name(self, b):
        return self.names.get(b, f'bit{b}')

    def param(self, cn, p, default):
        v = self.cells[cn]['parameters'].get(p)
        if v is None:
            return default
        return int(v, 2) if re.fullmatch(r'[01]+', v) else int(v)

    def get(self, b, cls):
        return self.arr.get(b, {}).get(cls) if isinstance(b, int) else None

    def put(self, b, cls, edge, late, early, pred, start, estart=None):
        a = self.arr[b].setdefault(cls, Arr())
        if a.late[edge] is None or late > a.late[edge]:
            a.late[edge] = late
            a.pred[edge] = pred
            if a.start is None or edge == a.max_late()[1]:
                a.start = start
        if a.early[edge] is None or early < a.early[edge]:
            if a.estart is None or early < a.min_early():
                a.estart = estart or start
            a.early[edge] = early

    def delay(self, arc, edge, b_out):
        tab = arc.rise if edge == 'r' else arc.fall
        return None if tab is None else self.derate * interp(self.index, tab, self.load.get(b_out, 0.0))

    # ---- cells
    def eval_seq(self, cn, conn, lc):
        for arc in lc['arcs']:
            if arc.kind not in ('falling_edge', 'rising_edge'):
                continue
            cb = conn[arc.src][0]
            ca = self.get(cb, 'clk')
            e_in = 'f' if arc.kind == 'falling_edge' else 'r'
            if ca is None or ca.late[e_in] is None:
                continue
            cl, ce = (0.0, 0.0) if self.ideal_clock else (ca.late[e_in], ca.early[e_in])
            ob = conn[arc.dst][0]
            for e in 'rf':
                d = self.delay(arc, e, ob)
                if d is not None:
                    self.put(ob, 'data', e, cl + d, ce + d, (cb, 'clk', e_in, cn), cn)

    def eval_comb(self, cn, conn, lc):
        classes = {}
        for arc in lc['arcs']:
            b = conn[arc.src][0]
            if isinstance(b, int) and self.arr.get(b):
                classes[arc.src] = set(self.arr[b])
        has_clk = any('clk' in s for s in classes.values())
        if has_clk and any(s & set(DATA) for s in classes.values()):
            self.gating.append((cn, {p: conn[p][0] for p in classes}))
        for arc in lc['arcs']:
            ib, ob = conn[arc.src][0], conn[arc.dst][0]
            if 'clk' in classes.get(arc.src, ()):
                self.check_pulse(cn, arc, ib, ob)
            for cls in classes.get(arc.src, ()):
                if has_clk and cls != 'clk':
                    continue     # a gate: the pulse passes, the data is checked
                a = self.arr[ib][cls]
                for e_out in 'rf':
                    d = self.delay(arc, e_out, ob)
                    if d is None:
                        continue
                    if arc.sense == 'positive_unate':
                        e_ins = [e_out]
                    elif arc.sense == 'negative_unate':
                        e_ins = ['f' if e_out == 'r' else 'r']
                    else:
                        e_ins = ['r', 'f']
                    for e_in in e_ins:
                        if a.late[e_in] is not None:
                            self.put(ob, cls, e_out, a.late[e_in] + d, a.early[e_in] + d,
                                     (ib, cls, e_in, cn), a.start, a.estart)

    def put_pulse(self, b, src, lead, width):
        """Keep the narrowest pulse of each source (a OneShot / Impulse) on net b."""
        cur = self.pulses.setdefault(b, {}).get(src)
        if cur is None or width < cur[1]:
            self.pulses[b][src] = (lead, width)

    def check_pulse(self, cn, arc, ib, ob):
        """A tube stage cannot pass a pulse shorter than its own switching time (the
        netlist simulation drops it: inertial delay). Each source pulse is followed on
        its own: the leading input edge makes the output edge the arc's sense gives,
        that delay must fit in the pulse, and the output width is the input width plus
        the trailing-edge delay minus the leading-edge delay."""
        if self.clock_tree(ob):
            return
        for src, (lead, width) in self.pulses.get(ib, {}).items():
            trail = 'f' if lead == 'r' else 'r'
            if arc.sense == 'negative_unate':
                o_lead, o_trail = trail, lead
            else:
                o_lead, o_trail = lead, trail
            d_lead = self.delay(arc, o_lead, ob)
            d_trail = self.delay(arc, o_trail, ob)
            if d_lead is None or d_trail is None:
                continue
            self.pulse_checks.append((cn, arc.src, src, width, d_lead))
            if width > d_lead:
                self.put_pulse(ob, src, o_lead, width + d_trail - d_lead)

    def clock_tree(self, b):
        """True for the clock inverter nets (only trigger C pins and the clock below)."""
        return all(p == 'C' for _, p in self.snk.get(b, [])) and bool(self.snk.get(b))

    def eval_macro(self, cn, c):
        t, conn = c['type'], c['connections']
        if t in ('OneShot', 'Impulse'):
            eb, ob = conn['En'][0], conn['Impulse'][0]
            a = self.get(eb, 'clk')
            if a is None:
                if self.arr.get(eb):
                    self.async_starts.append((cn, t, self.name(eb)))
                return
            if t == 'Impulse':
                e_in, width = ('f' if self.param(cn, 'FALL', 0) else 'r'), HS_NS
            else:
                e_in, width = 'r', self.param(cn, 'DELAY', 1) * HS_NS
                if cn.endswith('g_delay.osDelay') and self.phase_hs is not None:
                    width = self.phase_hs * HS_NS
                if re.search(r'osPhase[12]$', cn) and self.phase_width_hs is not None:
                    width = self.phase_width_hs * HS_NS
            if a.late[e_in] is None:
                return
            self.put(ob, 'clk', 'r', a.late[e_in], a.early[e_in], (eb, 'clk', e_in, cn), a.start)
            self.put(ob, 'clk', 'f', a.late[e_in] + width, a.early[e_in] + width, (eb, 'clk', e_in, cn), a.start)
            self.put_pulse(ob, cn, 'r', width)
        elif t == 'DekatronTubeDelay':
            guide = self.param(cn, 'GUIDE_STEP_HS', 2) * HS_NS
            fall = self.param(cn, 'FALL_STEP_HS', 3) * HS_NS
            best = None
            early = None
            for p in ('guide_a_i', 'guide_b_i'):
                b = conn[p][0]
                a = self.get(b, 'clk')
                if a is None:
                    continue
                for src, (lead, w) in self.pulses.get(b, {}).items():
                    self.pulse_checks.append((cn, p, src, w, guide))
                for e in 'rf':
                    if a.late[e] is None:
                        continue
                    # a released guide: the discharge lands on a main cathode FALL later;
                    # a taken guide: the main cathode goes dark GUIDE later
                    lv = a.late[e] + (fall if e == 'f' else guide)
                    if best is None or lv > best[0]:
                        best = (lv, (b, 'clk', e, cn))
                    ev = a.early[e] + guide
                    early = ev if early is None else min(early, ev)
            if best:
                for ob in conn['main_onehot_o']:
                    for e in 'rf':
                        self.put(ob, 'tube', e, best[0], early, best[1], cn)
        elif t in ('Ram', 'IpMemory'):
            for p, bits in conn.items():
                if c['port_directions'][p] == 'output':
                    for ob in bits:
                        if isinstance(ob, int):
                            for e in 'rf':
                                self.put(ob, 'data', e, self.mem_ns, self.mem_ns,
                                         ('start', f'{cn} (memory, ideal)'), cn)

    def deps(self, cn):
        c = self.cells[cn]
        t, conn = c['type'], c['connections']
        lc = self.lib.get(t)
        if lc:
            arcs = [a for a in lc['arcs'] if not lc['seq'] or a.kind in ('falling_edge', 'rising_edge')]
            return [conn[a.src][0] for a in arcs]
        if t in ('OneShot', 'Impulse'):
            return [conn['En'][0]]
        if t == 'DekatronTubeDelay':
            return [conn['guide_a_i'][0], conn['guide_b_i'][0]]
        return []

    def run(self):
        self.put(self.clk, 'clk', 'r', 0.0, 0.0, ('start', 'Clk port'), 'Clk')
        waits, users = {}, collections.defaultdict(list)
        for cn in self.cells:
            ds = {b for b in self.deps(cn) if isinstance(b, int) and b in self.drv}
            waits[cn] = len(ds)
            for b in ds:
                users[b].append(cn)
        ready = collections.deque(cn for cn, k in waits.items() if k == 0)
        while ready:
            cn = ready.popleft()
            c = self.cells[cn]
            lc = self.lib.get(c['type'])
            if lc and lc['seq']:
                self.eval_seq(cn, c['connections'], lc)
            elif lc:
                self.eval_comb(cn, c['connections'], lc)
            else:
                self.eval_macro(cn, c)
            for p, bits in c['connections'].items():
                if c['port_directions'].get(p) == 'output':
                    for b in bits:
                        for u in users.get(b, []):
                            waits[u] -= 1
                            if waits[u] == 0:
                                ready.append(u)
        self.loops = [cn for cn, k in waits.items() if k > 0]
        return self

    def trace(self, b, cls, e):
        steps, seen = [], set()
        while (b, cls, e) not in seen:
            seen.add((b, cls, e))
            a = self.get(b, cls)
            if a is None:
                break
            pred = a.pred[e]
            via = pred[3] if pred and pred[0] != 'start' else (pred[1] if pred else '?')
            steps.append((self.name(b), cls, e, a.late[e], via))
            if not pred or pred[0] == 'start':
                break
            b, cls, e = pred[0], pred[1], pred[2]
        return list(reversed(steps))

    # ---- checks
    def checks(self):
        setup, hold, gating = [], [], []
        for cn, c in self.cells.items():
            lc = self.lib.get(c['type'])
            conn = c['connections']
            if lc and lc['seq']:
                for pin, (rel, falling, su) in lc['setup'].items():
                    db = conn[pin][0]
                    ca = self.get(conn[rel][0], 'clk')
                    ce = 'f' if falling else 'r'
                    if ca is None or ca.late[ce] is None:
                        continue
                    cap_l, cap_e = (0.0, 0.0) if self.ideal_clock else (ca.late[ce], ca.early[ce])
                    su *= self.derate
                    ho = lc['hold'].get(pin, (None, None, 0.0))[2] * self.derate
                    for cls, a in self.arr.get(db, {}).items():
                        late, e = a.max_late()
                        setup.append({'need': late + su - cap_e, 'cell': cn, 'pin': pin, 'bit': db,
                                      'cls': cls, 'edge': e, 'start': a.start})
                        hold.append({'slack': a.min_early() - cap_l - ho, 'cell': cn, 'pin': pin,
                                     'cls': cls, 'start': a.estart})
            elif c['type'] in ('Ram', 'IpMemory'):
                for p, bits in conn.items():
                    if c['port_directions'][p] != 'input' or p == 'clk':
                        continue
                    for db in bits:
                        for cls, a in (self.arr.get(db, {}).items() if isinstance(db, int) else ()):
                            if cls in DATA:
                                late, e = a.max_late()
                                setup.append({'need': late, 'cell': cn, 'pin': p, 'bit': db,
                                              'cls': cls, 'edge': e, 'start': a.start})
        for cn, pins in self.gating:
            pulses = [self.arr[b]['clk'] for b in pins.values() if 'clk' in self.arr[b]]
            lead = min(p.min_early() for p in pulses)
            trail = max(p.max_late()[0] for p in pulses)
            for p, b in pins.items():
                for cls in DATA:
                    a = self.arr[b].get(cls)
                    if a is None:
                        continue
                    late, e = a.max_late()
                    g = {'cell': cn, 'type': self.cells[cn]['type'], 'pin': p, 'bit': b, 'cls': cls, 'edge': e,
                         'late': late, 'early': a.min_early(), 'lead': lead, 'trail': trail, 'start': a.start}
                    if cls == 'data':
                        g['slack'] = lead - late
                        g['need'] = trail - a.min_early()
                    else:
                        g['slack'] = None
                        g['need'] = late - lead
                    gating.append(g)
        return setup, hold, gating


# --------------------------------------------------------------------------
# Report
# --------------------------------------------------------------------------
def phase_delay_of(sta):
    if sta.phase_hs is not None:
        return sta.phase_hs
    for cn in sta.cells:
        if cn.endswith('g_delay.osDelay'):
            return sta.param(cn, 'DELAY', 0)
    return 0


def phase_width_of(sta):
    if sta.phase_width_hs is not None:
        return sta.phase_width_hs
    for cn in sta.cells:
        if cn.endswith('osPhase1'):
            return sta.param(cn, 'DELAY', 0)
    return 0


def summarize(sta):
    setup, hold, gating = sta.checks()
    gd = [g for g in gating if g['cls'] == 'data']
    gt = [g for g in gating if g['cls'] == 'tube']
    s = {
        'setup': sorted(setup, key=lambda x: -x['need']),
        'hold': sorted(hold, key=lambda x: x['slack']),
        'gd': sorted(gd, key=lambda x: x['slack']),
        'gt': sorted(gt, key=lambda x: -x['need']),
    }
    s['t_setup'] = s['setup'][0]['need'] if setup else 0.0
    s['t_setup_data'] = max((x['need'] for x in setup if x['cls'] == 'data'), default=0.0)
    s['t_setup_tube'] = max((x['need'] for x in setup if x['cls'] == 'tube'), default=0.0)
    s['t_hold_gate'] = max((g['need'] for g in gd), default=0.0)
    s['t_tube_gate'] = max((g['need'] for g in gt), default=0.0)
    s['gate_slack'] = s['gd'][0]['slack'] if gd else float('inf')
    s['hold_slack'] = s['hold'][0]['slack'] if hold else float('inf')
    s['t_min'] = max(s['t_setup'], s['t_hold_gate'], s['t_tube_gate'])
    s['pulse_margin'] = min((w - d for _, _, _, w, d in sta.pulse_checks), default=float('inf'))
    return s


def report(sta, freqs, npaths, title):
    s = summarize(sta)
    pd = phase_delay_of(sta)
    out = [f'## {title}', '',
           f'Phase start delay {pd} hsClk = {pd * HS_NS:.0f} ns, guide phases {phase_width_of(sta)} hsClk each; clock '
           f'{"ideal (0 ns at every trigger)" if sta.ideal_clock else "propagated through the clock inverters"}; '
           f'memory outputs {sta.mem_ns:.0f} ns after the edge'
           + (f'; cell delays × {sta.derate:g}' if sta.derate != 1.0 else '') + '.', '']
    if sta.loops:
        out += [f'Unresolved (loops): {len(sta.loops)}: {", ".join(sta.loops[:5])}', '']
    ok_gate = s['gate_slack'] >= 0
    out += ['| Constraint | Needs |', '|---|---|',
            f'| setup, trigger → trigger / memory | T ≥ {s["t_setup_data"]:.0f} ns |',
            f'| setup, dekatron cathodes → trigger | T ≥ {s["t_setup_tube"]:.0f} ns |',
            f'| cathodes → step command of the next cycle | T ≥ {s["t_tube_gate"]:.0f} ns |',
            f'| step command held to the end of its guide pulse | T ≥ {s["t_hold_gate"]:.0f} ns |',
            f'| step command settles before the phase starts | slack {s["gate_slack"]:.0f} ns'
            + ('' if ok_gate else ' **(phase delay too short)**') + ' |',
            f'| hold at the triggers | slack {s["hold_slack"]:.0f} ns |',
            f'| guide pulse width through the gates | margin {s["pulse_margin"]:.0f} ns'
            + ('' if s['pulse_margin'] > 0 else ' **(phases too short: the guide pulse is lost)**') + ' |',
            f'| **minimum Clk period** | **{s["t_min"]:.0f} ns, {1e6 / s["t_min"]:.0f} kHz**'
            + ('' if ok_gate else ' (only once the phase delay is fixed)') + ' |', '']
    out += ['Verdict on setup and gating; hold does not depend on T and is listed below.', '',
            '| Clk | T | slack | verdict |', '|---|---|---|---|']
    for f in freqs:
        T = 1e6 / f
        ok = T >= s['t_min'] and ok_gate and s['pulse_margin'] > 0
        out.append(f'| {f:g} kHz | {T:.0f} ns | {T - s["t_min"]:.0f} ns | {"meets" if ok else "**fails**"} |')
    out.append('')

    def path(b, cls, e, head):
        lines = [head, '', '```']
        for nm, c, ed, t, via in sta.trace(b, cls, e):
            lines.append(f'{t:7.0f} {"↑" if ed == "r" else "↓"} {c:4s} {short(nm, 56):56s} {short(via, 44)}')
        return lines + ['```', '']

    out += [f'### Setup, worst endpoints', '']
    seen, k = set(), 0
    for x in s['setup']:
        if x['cell'] in seen:
            continue
        seen.add(x['cell'])
        if k < npaths:
            out += path(x['bit'], x['cls'], x['edge'],
                        f'{k + 1}. `{short(x["cell"], 60)}.{x["pin"]}` ({sta.cells[x["cell"]]["type"]}, {x["cls"]}): '
                        f'T ≥ {x["need"]:.0f} ns')
        k += 1
    worst_data = next((x for x in s['setup'] if x['cls'] == 'data'), None)
    if worst_data and s['setup'][0]['cls'] != 'data':
        out += path(worst_data['bit'], 'data', worst_data['edge'],
                    f'Worst trigger → trigger path: `{short(worst_data["cell"], 60)}.{worst_data["pin"]}` '
                    f'({sta.cells[worst_data["cell"]]["type"]}): T ≥ {worst_data["need"]:.0f} ns')
    out += ['### Step command against its phase (data launched this cycle)', '',
            '| gate | pin | data settles | pulse | slack | needs T ≥ |', '|---|---|---|---|---|---|']
    for g in s['gd'][:npaths]:
        out.append(f'| `{short(g["cell"], 46)}` ({g["type"]}) | {g["pin"]} | {g["late"]:.0f} | '
                   f'{g["lead"]:.0f}–{g["trail"]:.0f} | {g["slack"]:.0f} | {g["need"]:.0f} |')
    out.append('')
    if s['gd']:
        g = s['gd'][0]
        out += path(g['bit'], 'data', g['edge'], f'Worst step command path, to `{short(g["cell"], 60)}.{g["pin"]}`:')
    if s['gt']:
        out += ['### Cathode readings into the next step command', '',
                '| gate | pin | reading settles | pulse | needs T ≥ |', '|---|---|---|---|---|']
        for g in s['gt'][:npaths]:
            out.append(f'| `{short(g["cell"], 46)}` ({g["type"]}) | {g["pin"]} | {g["late"]:.0f} | '
                       f'{g["lead"]:.0f}–{g["trail"]:.0f} | {g["need"]:.0f} |')
        out.append('')
    pc = sorted(sta.pulse_checks, key=lambda x: x[3] - x[4])
    if pc:
        bad = [x for x in pc if x[3] <= x[4]]
        out += [f'### Pulse width (guide pulses through the tube gates): {len(bad)} of {len(pc)} too short', '',
                '| cell | pin | pulse in | stage delay / guide min | margin |', '|---|---|---|---|---|']
        for cn, pin, src, w, d in pc[:npaths]:
            out.append(f'| `{short(cn, 50)}` | {pin} ({src.rsplit(".", 1)[-1]}) | {w:.0f} ns | {d:.0f} ns | {w - d:.0f} ns |')
        out.append('')
    out += ['### Hold, worst', '']
    for h in s['hold'][:3]:
        out.append(f'- `{short(h["cell"], 60)}.{h["pin"]}` ({h["cls"]}, from `{short(h["start"], 50)}`): '
                   f'slack {h["slack"]:.0f} ns')
    out.append('')
    return out, s


def clock_report(sta):
    out = ['### Clock nets', '', '| net | driver | triggers | load, grids | C↓ arrival |', '|---|---|---|---|---|']
    for b, sinks in sorted(sta.snk.items(), key=lambda kv: sta.name(kv[0])):
        ff = [cn for cn, p in sinks if p == 'C' and sta.cells[cn]['type'].startswith('DFF')]
        if not ff:
            continue
        a = sta.get(b, 'clk')
        drv = sta.drv.get(b, ('port', ''))[0]
        out.append(f'| `{short(sta.name(b), 40)}` | {sta.cells[drv]["type"] if drv in sta.cells else drv} | '
                   f'{len(ff)} | {sta.load[b]:.1f} | {a.late["f"]:.0f} ns |')
    return out + ['']


def fanout_report(sta):
    over = []
    for b, cap in sta.load.items():
        d = sta.drv.get(b)
        if d and d[0] in sta.cells and sta.cells[d[0]]['type'] in sta.lib and cap > 10.0:
            over.append((cap, sta.name(b), sta.cells[d[0]]['type']))
    over.sort(reverse=True)
    out = [f'### Nets over 10 grids (delay extrapolated past the table): {len(over)}', '']
    out += [f'- {cap:.1f}: `{short(nm, 60)}` ({t})' for cap, nm, t in over[:15]]
    return out + ['']


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('-n', required=True, help='flat Yosys JSON netlist')
    ap.add_argument('-l', default=os.path.join(here, '../../sch/logic/vtube_cells_timing.lib'))
    ap.add_argument('-t', default='DekatronPC', help='top module')
    ap.add_argument('-p', type=int, default=None, help='phase start delay, hsClk')
    ap.add_argument('-f', type=float, nargs='*', default=[100, 150, 200, 250, 1000], help='Clk to judge, kHz')
    ap.add_argument('-o', help='also write the report here')
    ap.add_argument('--paths', type=int, default=3)
    ap.add_argument('--ideal-clock', action='store_true', help='clock at 0 ns at every trigger')
    ap.add_argument('--mem-ns', type=float, default=0.0, help='memory output delay after the Clk edge')
    ap.add_argument('--phase-width', type=int, default=None, help='width of each guide phase, hsClk (RTL: 3)')
    ap.add_argument('--derate', type=float, default=1.0, help='scale every cell delay and setup/hold (tube spread)')
    a = ap.parse_args()
    lib = load_lib(a.l)
    mod = json.load(open(a.n))['modules'][a.t]

    def sta(pd):
        return Sta(mod, lib, pd, a.ideal_clock, a.mem_ns, a.derate, a.phase_width).run()

    out = ['# Tube STA', '']
    if a.p is None:
        st = sta(None)
        pd0 = phase_delay_of(st)
        lines, s = report(st, a.f, a.paths, f'As synthesized: phase delay {pd0} hsClk, '
                          f'phases {phase_width_of(st)} hsClk')
        out += lines
        if a.phase_width is None:
            # the narrowest phases every guide gate passes (doc/vtube_sta.md §6)
            w = phase_width_of(st)
            while summarize(st)['pulse_margin'] <= 0 and w < 50:
                w += 1
                a.phase_width = w
                st = sta(None)
        pd = max(1, math.ceil(pd0 - summarize(st)['gate_slack'] / HS_NS))
        st = sta(pd)
        lines, _ = report(st, a.f, a.paths, f'Fitted: phases {phase_width_of(st)} hsClk, '
                          f'phase delay {pd} hsClk')
    else:
        st = sta(a.p)
        lines, _ = report(st, a.f, a.paths, f'Phase delay {a.p} hsClk')
    out += lines + clock_report(st) + fanout_report(st)
    if st.async_starts:
        out += [f'### Not timed: {len(st.async_starts)} OneShot / Impulse started by data (write windows)', '']
        out += [f'- `{short(cn, 60)}` ({t}) from `{short(nm, 50)}`' for cn, t, nm in st.async_starts]
    text = '\n'.join(out) + '\n'
    if a.o:
        open(a.o, 'w').write(text)
    print(text, end='')


if __name__ == '__main__':
    main()
