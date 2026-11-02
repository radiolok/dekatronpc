#!/usr/bin/env python3
# What follows CIN (',') at run time on the Brainfuck-100 set (TC-O4,
# doc/tube_count_1000.md §6.1). For every executed ',' the first later
# executed op that decides where the value should live:
#   data/cout - + - . need the value in the Data counter
#   addr      - < > need the cell flushed to memory first
#   cin       - the next , overwrites it anyway
# [ ] are neutral (zero test from the counter or the memory register), and
# so is [-] (CLRD). Usage: tools/bf100/cin_next.py [cap]   (cap: steps, 2e7)
import os
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                      '../../bfutils/programs/bf100'))
import json, sys, collections, os
CAP = int(float(sys.argv[1])) if len(sys.argv) > 1 else 20_000_000
meta = json.load(open('metrics.json'))
tot = collections.Counter(); progwin = collections.Counter(); share = collections.defaultdict(float)
for m in meta:
    if not m.get('file'): continue
    src = open(m['file'], encoding='latin-1').read()
    code = [c for c in src if c in '+-<>[].,']
    if ',' not in code: continue
    jump = {}; st = []
    for i,c in enumerate(code):
        if c == '[': st.append(i)
        elif c == ']': j = st.pop(); jump[i] = j; jump[j] = i
    inp = open(m['input'], 'rb').read() if m.get('input') else b''
    eof = m.get('eof_mode', '0')
    tape = collections.defaultdict(int); ap = ip = k = steps = 0
    N = len(code); pending = False; first = collections.Counter()
    while ip < N and steps < CAP:
        c = code[ip]; steps += 1
        if pending:
            if c in '+-.':
                # [-] after CIN = CLRD: neutral (DOP set_zero in both variants)
                if c == '-' and ip>0 and code[ip-1]=='[' and ip+1<N and code[ip+1]==']': pass
                else: first['data' if c != '.' else 'cout'] += 1; pending = False
            elif c in '<>': first['addr'] += 1; pending = False
            elif c == ',': first['cin'] += 1; pending = False
        if c == '+': tape[ap] = (tape[ap]+1) & 255
        elif c == '-': tape[ap] = (tape[ap]-1) & 255
        elif c == '>': ap += 1
        elif c == '<': ap -= 1
        elif c == '[':
            if tape[ap] == 0: ip = jump[ip]
        elif c == ']':
            if tape[ap] != 0: ip = jump[ip]
        elif c == ',':
            pending = True
            if k < len(inp): tape[ap] = inp[k]; k += 1
            elif eof == '0': tape[ap] = 0
            elif eof == '255': tape[ap] = 255
        ip += 1
    if pending: first['end'] += 1
    n = sum(first.values())
    if not n: continue
    tot.update(first)
    for kk,v in first.items(): share[kk] += v/n
    dm = (first['data']+first['cout']); ad = first['addr']
    progwin['data' if dm>ad else 'addr' if ad>dm else 'tie'] += 1
    print(f"{m['file']:50s} cin={n:5d} " + ' '.join(f'{kk}={v}' for kk,v in sorted(first.items())))
print('TOTAL', dict(tot)); print('PROGRAMS majority', dict(progwin))
print('SUM OF PER-PROGRAM SHARES', {k: round(v,2) for k,v in share.items()})
