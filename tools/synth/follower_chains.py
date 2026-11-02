#!/usr/bin/env python3
"""Follower -> follower trees in the synthesized netlists (doc/follower_chains.md). Run in rtl/run after run_tests.sh -s:
   python3 ../../tools/synth/follower_chains.py
A tree: a follower (BUF/OR2/OR4) whose inputs come from other followers; leaves are the non-follower nets;
"shared" = an inner follower output also loads something outside the tree."""
import re, sys, collections
FOL = {"BUF_N16": (["A"], ["Y"]), "OR2_N16": (["A", "B"], ["Y"]), "OR4_N16": (["A", "B", "C", "D"], ["Y"])}
OUTPINS = {"Y", "Y1", "Y2", "Q", "QN", "C1", "C2", "H", "L"}
def parse(path):
    t = open(path).read()
    mods = {}
    for mod in re.findall(r"^module .*?^endmodule", t, re.S | re.M):
        name = re.match(r"module (\S+)\s*\(", mod).group(1)
        ports = set(re.findall(r"^\s*(?:input|output|inout)\s+(?:\[[^\]]*\]\s*)?(\S+);", mod, re.M))
        outs = set(re.findall(r"^\s*output\s+(?:\[[^\]]*\]\s*)?(\S+);", mod, re.M))
        insts = []
        for typ, inst, body in re.findall(r"^\s*(\\?\S+)\s+(\\?\S+)\s*\((.*?)\);", mod, re.S | re.M):
            if typ in ("module", "input", "output", "wire", "reg", "assign"): continue
            conns = {p: n.strip() for p, n in re.findall(r"\.(\w+)\(([^()]*(?:\([^()]*\))?[^()]*)\)", body)}
            insts.append((typ, inst, conns))
        mods[name] = (insts, ports, outs)
    return mods
def base(n):  # bit-level net name
    return n.strip()
tot = collections.Counter(); rows = []
for top in ("IpLine", "ApLine", "MachineCtrl"):
    mods = parse(f"{top}_synth.v")
    for mn, (insts, ports, outs) in mods.items():
        drv, loads = {}, collections.defaultdict(list)
        for typ, inst, c in insts:
            for p, n in c.items():
                if typ in FOL:
                    (loads[n].append((typ, inst, p)) if p in FOL[typ][0] else drv.__setitem__(n, (typ, inst, p)))
                elif p in OUTPINS and typ not in mods: drv[n] = (typ, inst, p)
                else: loads[n].append((typ, inst, p))
        fol = {inst: (typ, c) for typ, inst, c in insts if typ in FOL}
        # follower outputs that load a follower input
        bad = [(n, d) for n, d in drv.items() if d[0] in FOL and any(l[0] in FOL for l in loads[n])]
        cross = [n for n, d in drv.items() if d[0] in FOL and n in outs]
        if not bad and not cross: continue
        # roots: followers whose output is not consumed by another follower but which consume a follower output
        def leaves(inst, seen):
            typ, c = fol[inst]; out = []
            for p in FOL[typ][0]:
                n = c.get(p); d = drv.get(n)
                if d and d[0] in FOL and d[1] not in seen and len(FOL[d[0]][1]) == 1 and d[0] != "BUF_N16":
                    out += leaves(d[1], seen | {d[1]})
                elif d and d[0] == "BUF_N16":
                    # a BUF in front: its input is the leaf (a BUF only shifts the level)
                    bp = FOL["BUF_N16"][0][FOL["BUF_N16"][1].index(d[2])]
                    out.append(fol[d[1]][1].get(bp))
                else: out.append(n)
            return out
        consumers = set()
        for n, d in bad:
            for l in loads[n]:
                if l[0] in FOL: consumers.add(l[1])
        inner = {d[1] for n, d in bad}
        roots = [i for i in consumers if i not in inner or not all(l[0] in FOL for l in loads[[n for n, dd in drv.items() if dd[1] == i][0]])]
        for r in roots:
            lv = leaves(r, {r}); k = len(set(lv))
            shared = []
            def walk(i):
                typ, c = fol[i]
                for p in FOL[typ][0]:
                    d = drv.get(c.get(p))
                    if d and d[0] in FOL:
                        other = [l for l in loads[c.get(p)] if not (l[0] in FOL)] + [l for l in loads[c.get(p)] if l[0] in FOL and l[1] != i]
                        if other: shared.append(c.get(p))
                        if d[0] != "BUF_N16": walk(d[1])
            walk(r)
            cls = "<=8" if k <= 8 else ">8"
            rows.append((top, mn.lstrip("\\")[-35:], r[-25:], k, len(shared)))
            tot[(cls, "shared" if shared else "clean")] += 1
        if cross: tot[("cross-module outputs", "")] += len(cross)
for r in rows: print("%-12s %-36s root %-26s leaves %2d shared-inner %d" % r)
print(dict(tot)); print("roots:", len(rows), "follower->follower nets:", sum(1 for r in rows))
import collections as C
print("leaf count histogram:", sorted(C.Counter(r[3] for r in rows).items()))
