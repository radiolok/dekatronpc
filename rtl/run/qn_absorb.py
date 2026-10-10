"""Absorb inverters on trigger outputs into the free inverted output QN.

A tube trigger (Eccles-Jordan) has both anodes, so Q and QN cost the same.
ABC sees triggers as black boxes and builds ~Q with a NOT cell. This pass
takes the mapped Yosys JSON netlist, finds every inverter whose input is a
trigger's Q, moves its loads to the trigger's QN and drops the inverter.

Cell roles come from the liberty file: a cell with an ff()/latch() group and
a QN pin is a trigger, a cell whose only output function is "A'" is an
inverter.

usage: qn_absorb.py -l vtube_cells.lib -i in.json -o out.json
"""

import argparse
import json
import re


def lib_roles(lib_text):
    """Return (trigger cell names, inverter cell names) from the liberty text."""
    triggers, inverters = set(), set()
    for m in re.finditer(r'cell\s*\(\s*(\w+)\s*\)\s*\{', lib_text):
        name = m.group(1)
        nxt = lib_text.find('cell(', m.end())
        body = lib_text[m.end():nxt if nxt != -1 else len(lib_text)]
        if re.search(r'\b(ff|latch)\s*\(', body) and re.search(r'pin\s*\(\s*QN\s*\)', body):
            triggers.add(name)
        funcs = re.findall(r'function\s*:\s*"([^"]*)"', body)
        if funcs == ["A'"]:
            inverters.add(name)
    return triggers, inverters


def absorb(module, triggers, inverters):
    """Rewire one module in place; return the number of removed inverters."""
    cells = module.get('cells', {})
    q_of = {}      # bit -> trigger cell name whose Q drives it
    for name, cell in cells.items():
        if cell['type'] in triggers:
            q = cell['connections'].get('Q', [])
            if len(q) == 1 and isinstance(q[0], int):
                q_of[q[0]] = name

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
        trig = cells[q_of[a]]
        qn = trig['connections'].get('QN', [])
        if not qn or qn[0] in ('x', 'z') or not isinstance(qn[0], int):
            # QN still free: it drives the inverter's net directly
            trig['connections']['QN'] = [y]
            if 'port_directions' in trig:
                trig['port_directions']['QN'] = 'output'
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
        triggers, inverters = lib_roles(f.read())
    with open(args.input) as f:
        design = json.load(f)

    # Library cells come back as blackbox modules; the caller reads the
    # liberty again, so they are dropped to avoid a re-definition
    design['modules'] = {name: module for name, module in design['modules'].items()
                         if not module.get('attributes', {}).get('blackbox')}

    total = 0
    for mname, module in design['modules'].items():
        n = absorb(module, triggers, inverters)
        if n:
            print(f"qn_absorb: {mname}: {n} inverter(s) replaced by QN")
        total += n
    print(f"qn_absorb: total {total}")

    with open(args.output, 'w') as f:
        json.dump(design, f, indent=1)


if __name__ == '__main__':
    main()
