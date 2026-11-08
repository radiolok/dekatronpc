"""Absorb inverters on trigger outputs into the free inverted output QN, and
inverters on trigger D inputs into a swap of Q and QN.

A tube trigger (Eccles-Jordan) has both anodes, so Q and QN cost the same.
ABC sees triggers as black boxes and builds ~Q with a NOT cell. This pass
takes the mapped Yosys JSON netlist, finds every inverter whose input is a
trigger's Q (or QN), moves its loads to the other output and drops the
inverter.

The same symmetry works on the input (doc/dinv_trigger_board.md): a trigger
that stores ~D is the trigger that stores D with Q and QN swapped (on the
board: the D inverter wired to the other pentode). An inverter whose loads are
only D pins of triggers is dropped, each of those triggers takes the
inverter's input on D and swaps Q and QN. With an asynchronous clear the swap
turns it into a preset (DFFRN_J2N16X7 <-> DFFSN_J2N16X7, same tubes).
dont_use triggers (placed by the RTL, e.g. DFFP_J2N16) are left alone, and so
is an inverter with the output of one of them at most FAST_DEPTH gates before
its input: a DFFP switches on the rising Clk edge, shortly before a DFF_J2N16
behind the clock inverter captures, and the inverter is the hold margin of
that short path (IpLine key_moved_q from key_next_s through one NOR3:
synth_sim.sh -t, 10 setup violations without it). After the swap the path
keeps at least as many gates as the shortest one the netlist had.
DPC_NO_D_ABSORB=1 in the environment turns the input part off (comparisons).
It was opt-in in TRS v0.58: with the plate chokes the swap changed the loads
of the MachineCtrl state bits, their skew walked the state through
S_RST_REQ and the combinational soft_rst_req fired the reset relay. Since
TRS v0.59 the request comes from a DFFP_J2N16 (OPEN-019).

Cell roles come from the liberty file: a cell with an ff()/latch() group and
a QN pin is a trigger, a cell whose only output function is "A'" is an
inverter.

usage: qn_absorb.py -l vtube_cells.lib -i in.json -o out.json
"""

import argparse
import json
import os
import re


def lib_roles(lib_text):
    """Return (trigger cell names, inverter cell names, D-swap map) from the liberty text.
    The D-swap map: trigger -> (trigger after a Q/QN swap, {old pin: new pin}); a trigger
    without clear/preset maps to itself, one with clear "X'" to the cell with preset "Y'"
    and the same clock and data (and back)."""
    triggers, inverters, ffs = set(), set(), {}
    for m in re.finditer(r'cell\s*\(\s*(\w+)\s*\)\s*\{', lib_text):
        name = m.group(1)
        nxt = lib_text.find('cell(', m.end())
        body = lib_text[m.end():nxt if nxt != -1 else len(lib_text)]
        g = re.search(r'\b(ff|latch)\s*\([^)]*\)\s*\{([^}]*)\}', body)
        if g and re.search(r'pin\s*\(\s*QN\s*\)', body):
            triggers.add(name)
            attr = dict(re.findall(r'(\w+)\s*:\s*"?([^";]*)"?\s*;', g.group(2)))
            if not re.search(r'dont_use\s*:\s*true', body):
                ffs[name] = attr
        funcs = re.findall(r'function\s*:\s*"([^"]*)"', body)
        if funcs == ["A'"]:
            inverters.add(name)
    dswap = {}
    for name, a in ffs.items():
        key = (a.get('clocked_on'), a.get('next_state'), a.get('enable'), a.get('data_in'))
        if 'clear' not in a and 'preset' not in a:
            dswap[name] = (name, {})
            continue
        mine, other = ('clear', 'preset') if 'clear' in a else ('preset', 'clear')
        for n2, b in ffs.items():
            if (other in b and mine not in b and (b.get('clocked_on'), b.get('next_state'), b.get('enable'),
                                                  b.get('data_in')) == key
                    and a[mine].endswith("'") == b[other].endswith("'")):
                dswap[name] = (n2, {a[mine].rstrip("'"): b[other].rstrip("'")})
    return triggers, inverters, dswap


FAST_DEPTH = 2     # DFFP -> gate -> inverter -> D is kept (one gate after the swap would race)


def d_absorb(module, inverters, dswap, triggers):
    """Drop inverters that only feed D pins of triggers: each trigger takes the inverter's
    input on D and swaps Q / QN. Return the number of removed inverters."""
    cells = module.get('cells', {})
    drv = {}       # bit -> driving cell name
    for name, cell in cells.items():
        dirs = cell.get('port_directions', {})
        for pin, bits in cell['connections'].items():
            if dirs.get(pin) == 'output':
                for b in bits:
                    if isinstance(b, int): drv[b] = name
    fast = {n for n, c in cells.items() if c['type'] in triggers and c['type'] not in dswap}

    def from_fast(bit, depth=FAST_DEPTH):
        """a trigger left alone (DFFP_J2N16) drives bit through fewer than `depth` gates"""
        c = drv.get(bit)
        if c is None or depth == 0: return False
        if c in fast: return True
        if cells[c]['type'] in triggers: return False
        dirs = cells[c].get('port_directions', {})
        return any(from_fast(b, depth - 1) for p, bits in cells[c]['connections'].items()
                   if dirs.get(p) != 'output' for b in bits if isinstance(b, int))

    port_bits = set()
    for port in module.get('ports', {}).values():
        port_bits.update(b for b in port['bits'] if isinstance(b, int))
    loads = {}
    for name, cell in cells.items():
        dirs = cell.get('port_directions', {})
        for pin, bits in cell['connections'].items():
            if dirs.get(pin, 'input') != 'output':
                for b in bits:
                    if isinstance(b, int):
                        loads.setdefault(b, []).append((name, pin))
    removed = 0
    for name in list(cells):
        cell = cells[name]
        if cell['type'] not in inverters:
            continue
        a = cell['connections']['A'][0]
        y = cell['connections']['Y'][0]
        ld = loads.get(y, [])
        if (not isinstance(y, int) or y in port_bits or not ld
                or any(pin != 'D' or cells[c]['type'] not in dswap for c, pin in ld)
                or from_fast(a)):
            continue
        for c, _ in ld:
            trig = cells[c]
            new_type, ren = dswap[trig['type']]
            conn, dirs = trig['connections'], trig.get('port_directions', {})
            conn['D'] = [a]
            q, qn = conn.pop('Q', None), conn.pop('QN', None)
            if qn is not None: conn['Q'] = qn
            if q is not None: conn['QN'] = q
            for p in ('Q', 'QN'):
                if p in conn: dirs[p] = 'output'
                else: dirs.pop(p, None)
            for old, new in ren.items():
                if old in conn: conn[new] = conn.pop(old)
                if old in dirs: dirs[new] = dirs.pop(old)
            trig['type'] = new_type
        del cells[name]
        removed += 1
    return removed


def absorb(module, triggers, inverters):
    """Rewire one module in place; return the number of removed inverters."""
    cells = module.get('cells', {})
    q_of = {}      # bit -> (trigger cell name, output pin Q or QN driving it)
    for name, cell in cells.items():
        if cell['type'] in triggers:
            for pin in ('Q', 'QN'):
                q = cell['connections'].get(pin, [])
                if len(q) == 1 and isinstance(q[0], int):
                    q_of[q[0]] = (name, pin)

    port_bits = set()
    for port in module.get('ports', {}).values():
        port_bits.update(b for b in port['bits'] if isinstance(b, int))

    removed = 0
    for name in list(cells):
        cell = cells[name]
        if cell['type'] not in inverters:
            continue
        a = cell['connections']['A'][0]
        y = cell['connections']['Y'][0]
        if a not in q_of or not isinstance(y, int):
            continue
        tname, tpin = q_of[a]
        trig = cells[tname]
        opin = 'QN' if tpin == 'Q' else 'Q'
        qn = trig['connections'].get(opin, [])
        if not qn or qn[0] in ('x', 'z') or not isinstance(qn[0], int):
            # the other output still free: it drives the inverter's net directly
            trig['connections'][opin] = [y]
            q_of[y] = (tname, opin)
            if 'port_directions' in trig:
                trig['port_directions'][opin] = 'output'
        else:
            # QN already used by another inverter's net: move the loads.
            # A module port bit can't be merged here, keep that inverter.
            if y in port_bits:
                continue
            src = qn[0]
            for other in cells.values():
                for pin, bits in other['connections'].items():
                    other['connections'][pin] = [src if b == y else b for b in bits]
            for net in module.get('netnames', {}).values():
                net['bits'] = [src if b == y else b for b in net['bits']]
        del cells[name]
        removed += 1
    return removed


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('-l', '--lib', required=True)
    ap.add_argument('-i', '--input', required=True)
    ap.add_argument('-o', '--output', required=True)
    args = ap.parse_args()

    with open(args.lib) as f:
        triggers, inverters, dswap = lib_roles(f.read())
    with open(args.input) as f:
        design = json.load(f)

    # Library cells come back as blackbox modules; the caller reads the
    # liberty again, so they are dropped to avoid a re-definition
    design['modules'] = {name: module for name, module in design['modules'].items()
                         if not module.get('attributes', {}).get('blackbox')}

    total = dtotal = 0
    for mname, module in design['modules'].items():
        if os.environ.get('DPC_NO_D_ABSORB') != '1':
            n = d_absorb(module, inverters, dswap, triggers)
            if n:
                print(f"qn_absorb: {mname}: {n} inverter(s) on D replaced by a Q/QN swap")
            dtotal += n
        n = absorb(module, triggers, inverters)
        if n:
            print(f"qn_absorb: {mname}: {n} inverter(s) replaced by QN")
        total += n
    print(f"qn_absorb: total {total} on Q, {dtotal} on D")

    with open(args.output, 'w') as f:
        json.dump(design, f, indent=1)


if __name__ == '__main__':
    main()
