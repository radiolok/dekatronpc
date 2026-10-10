#!/usr/bin/env python3
"""Cycle profile of a DekatronPC run from a waveform dump (REQ-PERF-002).

Reads one row per posedge Clk with wavepeek, then splits the cycles by
instruction and by the state of MachineCtrl/IpLine/ApLine.

    cycle_profile.py DekatronPC_tb.fst --from 2685100000ps --to 13764100000ps

The window should cover program execution only (after the EOT soft reset,
up to the HALT). Reports: doc/cycle_profile_helloworld.md,
doc/prefetch_p3.md (with prefetch; use --op machineCtrl.op_full for dumps
of the RTL before it).
"""
import argparse
import collections
import itertools
import json
import subprocess

# MachineCtrl state codes, as in rtl/DekatronPC/MachineCtrl.sv (T6 codes;
# dumps of the RTL before 2026-10-08 used 0,1,2,4,5,6,7,9,12,13)
S = {'HALT': 4, 'IDLE': 0, 'FETCH_W': 1, 'DECODE': 10, 'EXEC': 11, 'WAIT': 2,
     'COUT': 6, 'CIN_WAIT': 15, 'RST_REQ': 14, 'RST_WAIT': 7}
MS = {v: k for k, v in S.items()}
AS = {0: 'IDLE', 1: 'FLUSH', 2: 'READ', 3: 'AP', 4: 'DSET', 5: 'DOP'}
OPN = {0x12: '+', 0x13: '-', 0x14: '>', 0x15: '<', 0x16: '[', 0x17: ']',
       0x18: '.', 0x19: ',', 0x11: 'HALT', 0x0e: 'ISA0', 0x0f: 'ISA1',
       0x1e: 'ISA0', 0x1f: 'ISA1'}
PAYLOAD = ['machineCtrl.state', 'ipLine.state',
           'ipLine.scanning_q', 'apLine.state', 'ap_ready', 'ip_ready', 'IpAddress']


def rows(args):
    cmd = ['wavepeek', 'extract', 'generic', '--waves', args.waves,
           '--scope', args.scope, '--on', 'posedge Clk', '--when', "1'b1",
           '--from', args.t_from, '--to', args.t_to,
           '--payload', ','.join(PAYLOAD + [args.op]), '--max', 'unlimited', '--jsonl']
    out = subprocess.run(cmd, check=True, capture_output=True, text=True).stdout
    res, ended = [], False
    for line in out.splitlines():
        r = json.loads(line)
        if r['type'] == 'fatal':
            raise SystemExit(r['message'])
        if r['type'] == 'end':
            ended = r['summary']['complete']
        if r['type'] == 'data':
            row = {p['relative_path']: int(p['value'].split("'h")[1], 16)
                   for p in r['data']['payload']}
            row['op'] = row.pop(args.op)
            res.append(row)
    if not ended:
        raise SystemExit('wavepeek output incomplete')
    return res


def categories(R):
    c = collections.Counter()
    for i, r in enumerate(R):
        ms, a = r['machineCtrl.state'], r['apLine.state']
        if r['ipLine.scanning_q'] or (ms == S['FETCH_W'] and r['ipLine.state'] == 5):
            c['loop scan inside IpLine'] += 1
        elif ms == S['WAIT'] and a == 5 and not r['ap_ready'] and i > 0 \
                and R[i - 1]['apLine.state'] == 5:
            # DOP stuck after DSET: the Data counter write window
            c['WAIT: Data counter write window'] += 1
        elif ms == S['WAIT'] and a == 0 and not r['ip_ready']:
            c['WAIT: ApLine done, prefetch in flight'] += 1
        elif ms == S['WAIT'] and a == 0:
            c['WAIT: ApLine done, MachineCtrl sees go'] += 1
        elif ms == S['WAIT']:
            c['WAIT: ApLine ' + AS[a]] += 1
        else:
            c['MachineCtrl ' + MS.get(ms, str(ms))] += 1
    return c


def per_insn(R):
    # One instruction = from the IDLE that requests it to the next IDLE.
    # With prefetch (P3) an instruction also starts at a DECODE entered
    # straight from WAIT/COUT: its fetch overlapped the previous one,
    # which is charged for it. The loop scan that a taken ']' or '['
    # starts runs inside the next fetch, so it is charged to the bracket
    # that caused it.
    segs, cur = [], None
    for i, r in enumerate(R):
        s = r['machineCtrl.state']
        p = R[i - 1]['machineCtrl.state'] if i else None
        if (s == S['IDLE'] and p != S['IDLE']) or \
                (s == S['DECODE'] and p in (S['WAIT'], S['COUT'])):
            cur = {'states': collections.Counter(), 'op': None, 'scan': 0}
            segs.append(cur)
        if cur is None:
            continue
        cur['states'][MS.get(s, str(s))] += 1
        cur['scan'] += r['ipLine.scanning_q']
        if s == S['DECODE']:
            cur['op'] = r['op']
    segs = [s for s in segs if s['op'] is not None]
    for prev, s in zip(segs, segs[1:]):
        if s['scan']:
            prev['scan_moved'] = s['scan']
            s['states']['FETCH_W'] -= s['scan']
    per = collections.defaultdict(lambda: {'n': 0, 'cyc': 0, 'hist': collections.Counter()})
    for s in segs:
        n = sum(s['states'].values()) + s.get('scan_moved', 0)
        p = per[OPN.get(s['op'], hex(s['op']))]
        p['n'] += 1
        p['cyc'] += n
        p['hist'][n] += 1
    return segs, per


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('waves')
    ap.add_argument('--scope', default='DekatronPC_tb.dekatronPC')
    ap.add_argument('--from', dest='t_from', required=True)
    ap.add_argument('--to', dest='t_to', required=True)
    ap.add_argument('--op', default='machineCtrl.op_cur',
                    help='opcode valid in S_DECODE (machineCtrl.op_full before P3)')
    args = ap.parse_args()

    R = rows(args)
    T = len(R)
    print('cycles in window: %d' % T)
    for k, n in categories(R).most_common():
        print('  %-42s %6d  %5.1f%%' % (k, n, 100 * n / T))

    segs, per = per_insn(R)
    print('\ninstructions: %d, CPI %.2f' % (len(segs), T / len(segs)))
    print('  %-5s %6s %7s %6s  %s' % ('op', 'count', 'cycles', 'CPI', 'cycles per instance'))
    for k, p in sorted(per.items(), key=lambda x: -x[1]['cyc']):
        print('  %-5s %6d %7d %6.2f  %s' % (k, p['n'], p['cyc'], p['cyc'] / p['n'],
                                          dict(sorted(p['hist'].items()))))

    for name, st in (('DOP', 5), ('AP', 3)):
        runs = [len(list(g)) for k, g in itertools.groupby(r['apLine.state'] for r in R) if k == st]
        print('ApLine %s run lengths: %s' % (name, dict(collections.Counter(runs))))


if __name__ == '__main__':
    main()
