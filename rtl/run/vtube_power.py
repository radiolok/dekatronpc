#!/usr/bin/env python3
"""Supply power of the tube machine from a netlist simulation (doc/vtube_power.md).

A tube cell draws its current while it conducts, so its power is a function of its pin states, and the
mean power is the time in each state times the static currents of sch/logic/vtube_power.json (SPICE
numbers of the cell pages); the heater current is heat_current of vtube_cells.lib. Edge currents
(C*V^2*f) are below 0.1 mW per net and left out. The currents are split by rail: heater 6.3 V,
plates +150 V, screens +150 V, bias -50 V and the dekatron anodes +350 V; and by block: the
first-level instances under the DUT (IpLine, ApLine, MachineCtrl), each split into its logic and its
DekatronModule boards.

  vtube_power.py plan   -n <top>_synth.v -t <top> -s <dut scope> -l vtube_cells.lib -m vtube_power.json
                        -o <dir>/power_plan [-w window_ns]
      writes power_plan.txt (input of vtube_power_vcd) and power_plan.json (cell list for the report)
  vtube_power.py report -p <dir>/power_plan -r <vtube_power_vcd output> [-o report.md] [--title T]

The <dut scope> is the instance path of the netlist top in the VCD, e.g. DekatronPC_tb.dekatronPC.
The state times come from vtube_power_vcd.c, which reads the VCD as a stream.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from collections import defaultdict

RAIL_ORDER = ["h", "a", "g2", "n50", "hv"]


def lib_heat(lib_path):
    """cell -> heater current, mA (heat_current of the liberty)"""
    text = open(lib_path).read()
    heat = {}
    for m in re.finditer(r'cell\s*\(\s*(\w+)\s*\)\s*\{', text):
        depth = 0
        for j in range(m.end() - 1, len(text)):
            if text[j] == '{':
                depth += 1
            elif text[j] == '}':
                depth -= 1
                if depth == 0:
                    break
        hm = re.search(r'heat_current\s*:\s*([\d.]+)', text[m.end():j])
        heat[m.group(1)] = float(hm.group(1)) if hm else 0.0
    return heat


def netlist_json(synth_v):
    """the netlist as Yosys JSON (read without hierarchy: black boxes stay unknown cells)"""
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "n.json")
        subprocess.run(["yosys", "-q", "-p", f"read_verilog {synth_v}; proc; write_json {out}"],
                       check=True, stdout=subprocess.DEVNULL)
        return json.load(open(out))


def base_name(module):
    """$paramod$hash\\IpLine, $paramod\\MachineCtrl\\P=1 -> IpLine, MachineCtrl"""
    parts = clean(module).split('\\')
    return parts[1] if parts[0].startswith('$paramod') and len(parts) > 1 else parts[0]


def clean(name):
    return name[1:] if name.startswith('\\') else name


def state_table(model, rails):
    """rows: one per pin state (pin i = bit i), then the x row (mean); columns: rails"""
    pins = model["pins"]
    rows = []
    for s in range(1 << len(pins)):
        env = {p: (s >> i) & 1 for i, p in enumerate(pins)}
        row = {r: 0.0 for r in rails}
        for cond, cur in model["states"]:
            if eval(str(cond), {"__builtins__": {}}, env):
                for r, v in cur.items():
                    row[r] = float(eval(str(v), {"__builtins__": {}}, env))
                break
        rows.append(row)
    rows.append({r: sum(x[r] for x in rows) / len(rows) for r in rails})
    return rows


def plan(args):
    model = json.load(open(args.model))
    rails = [r for r in RAIL_ORDER if r in model["rails"]]
    heat = lib_heat(args.lib)
    cells_m = model["cells"]
    pseudo = {m["module"]: c for c, m in cells_m.items() if "module" in m}
    nl = netlist_json(args.netlist)
    mods = nl["modules"]
    dut = args.scope.replace('.', '/')

    out_cells, blocks, unknown, nomodel = [], [], defaultdict(int), defaultdict(int)

    def walk(mod, path, block, group):
        for iname, c in mods[mod]["cells"].items():
            t = c["type"]
            name = clean(iname)
            if t in mods:
                b = block or base_name(t)
                g = group or ("dekatron" if base_name(t) == "DekatronModule" else None)
                walk(t, f"{path}/{name}", b, g)
                continue
            ctype = pseudo.get(t, t)
            if ctype not in cells_m and t not in heat:
                unknown[t] += 1         # black boxes of the netlist (RC elements, memory, time relay)
                continue
            if ctype not in cells_m:
                nomodel[ctype] += 1     # liberty cell with no current table: heater only
            m = cells_m.get(ctype, {"pins": [], "states": []})
            rows = state_table(m, [r for r in rails if r != "h"])
            h = m.get("heater_ma", heat.get(ctype, 0.0))
            for row in rows:
                row["h"] = h
            b = block or "DekatronPC"
            if b not in blocks:
                blocks.append(b)
            out_cells.append(dict(type=ctype, block=b, group=group or "logic", path=f"{path}/{name}",
                                  pins=[f"{path}/{name}/{p}" for p in m["pins"]],
                                  rows=[[row[r] for r in rails] for row in rows],
                                  status=m.get("status", "none")))

    walk(args.top, dut, None, None)
    window_ps = int(args.window * 1000)
    with open(args.out + ".txt", "w") as f:
        f.write(f"rails {len(rails)}\nblocks {len(blocks)}\nwindow {window_ps}\ncells {len(out_cells)}\n")
        for c in out_cells:
            f.write(f"{blocks.index(c['block'])} {len(c['pins'])} {' '.join(c['pins'])}\n")
            f.write(' '.join(f"{v:.6g}" for row in c["rows"] for v in row) + "\n")
    meta = dict(rails=rails, rail_info={r: model["rails"][r] for r in rails}, blocks=blocks,
                window_ns=args.window, cells=[{k: c[k] for k in ("type", "block", "group", "path", "rows", "status")}
                                              for c in out_cells])
    json.dump(meta, open(args.out + ".json", "w"))
    print(f"vtube_power: {len(out_cells)} cells in {len(blocks)} blocks ({', '.join(blocks)})")
    if unknown:
        print("  not counted (black boxes): " + ", ".join(f"{t} x{n}" for t, n in sorted(unknown.items())))
    if nomodel:
        print("  no current table, heater only: " + ", ".join(f"{t} x{n}" for t, n in sorted(nomodel.items())))


def fmt(v, nd=1):
    return f"{v:.{nd}f}".replace('.', ',')


def report(args):
    meta = json.load(open(args.plan + ".json"))
    rails, info, blocks = meta["rails"], meta["rail_info"], meta["blocks"]
    R = len(rails)
    total_ps, changes, peaks, hists = 0, 0, {}, {}
    for line in open(args.result):
        p = line.split()
        if p[0] == "time":
            total_ps = int(p[1])
        elif p[0] == "changes":
            changes = int(p[1])
        elif p[0] == "peak":
            peaks[int(p[1])] = [float(x) for x in p[2:]]
        elif p[0] == "hist":
            hists[int(p[1])] = [float(x) for x in p[2:]]
    if total_ps <= 0:
        sys.exit("vtube_power: empty run")

    # mean currents, mA: per (block, group), per cell type, per status
    mean = defaultdict(lambda: [0.0] * R)
    by_type = defaultdict(lambda: [0.0] * R)
    count = defaultdict(int)
    by_status = defaultdict(float)
    xtime = 0.0
    for i, c in enumerate(meta["cells"]):
        h = hists[i]
        rows = c["rows"]
        cur = [sum(h[s] * rows[s][r] for s in range(len(rows))) / total_ps for r in range(R)]
        xtime += h[-1] / total_ps
        for r in range(R):
            mean[(c["block"], c["group"])][r] += cur[r]
            by_type[c["type"]][r] += cur[r]
        count[c["type"]] += 1
        by_status[c["status"]] += sum(abs(info[rails[r]]["v"]) * cur[r] for r in range(R)) / 1000
    ncells = len(meta["cells"])

    def power(cur):
        return [abs(info[rails[r]]["v"]) * cur[r] / 1000 for r in range(R)]

    def block_mean(b):
        return [sum(mean[(b, g)][r] for g in ("logic", "dekatron")) for r in range(R)]

    L = []
    L.append(f"# {args.title}\n")
    L.append(f"Модельное время {total_ps / 1e12:.4f} с ({total_ps / 1e3 / meta['window_ns']:.0f} окон по "
             f"{meta['window_ns'] / 1000:g} мкс), {changes} изменений в VCD, {ncells} ячеек. "
             f"Пик — наибольший средний ток за окно (статическая нагрузка источника, без фронтов). "
             f"Доля времени ячеек с x/z на входах: {100 * xtime / ncells:.3f} %.\n")

    def table(title, cur, pk):
        L.append(f"### {title}\n")
        L.append("| Цепь | U, В | I ср., А | I пик, А | P ср., Вт | P пик, Вт |")
        L.append("|---|---:|---:|---:|---:|---:|")
        pm, pp = power(cur), power(pk)
        for r in range(R):
            L.append(f"| {info[rails[r]]['name']} | {fmt(info[rails[r]]['v'], 1 if rails[r] == 'h' else 0)} | "
                     f"{fmt(cur[r] / 1000, 3)} | {fmt(pk[r] / 1000, 3)} | {fmt(pm[r], 1)} | {fmt(pp[r], 1)} |")
        L.append(f"| **Всего** | | | | **{fmt(sum(pm), 1)}** | {fmt(sum(pp), 1)}* |")
        L.append("")

    L.append("## По блокам\n")
    tot = [0.0] * R
    for bi, b in enumerate(blocks):
        cur = block_mean(b)
        tot = [tot[r] + cur[r] for r in range(R)]
        table(b, cur, peaks[bi])
    table("Машина целиком", tot, peaks[-1])
    L.append("\\* Сумма пиков по цепям — оценка сверху: пики разных цепей приходятся на разные окна.\n")

    L.append("## Сводка по источникам\n")
    L.append("| Источник | " + " | ".join(blocks) + " | Всего |")
    L.append("|---|" + "---:|" * (len(blocks) + 1))
    supplies = []
    for r in rails:
        s = info[r]["supply"]
        if s not in supplies:
            supplies.append(s)
    for s in supplies:
        idx = [i for i, r in enumerate(rails) if info[r]["supply"] == s]
        v = abs(info[rails[idx[0]]]["v"])
        cells_ = []
        for b in blocks + [None]:
            cur = block_mean(b) if b else tot
            i_ = sum(cur[i] for i in idx)
            cells_.append(f"{fmt(i_ / 1000, 3)} А / {fmt(v * i_ / 1000, 1)} Вт")
        L.append(f"| {s} | " + " | ".join(cells_) + " |")
    L.append("")

    L.append("## Логика и модули декатронов, P ср., Вт\n")
    L.append("| Блок | Логика | Модули декатронов | Всего |")
    L.append("|---|---:|---:|---:|")
    for b in blocks:
        pl, pd = sum(power(mean[(b, 'logic')])), sum(power(mean[(b, 'dekatron')]))
        L.append(f"| {b} | {fmt(pl)} | {fmt(pd)} | {fmt(pl + pd)} |")
    L.append("")

    L.append("## По типам ячеек\n")
    L.append("| Ячейка | Шт. | Накал, Вт | Анод+сетки +150 В, Вт | −50 В, Вт | +350 В, Вт | Всего, Вт | Модель |")
    L.append("|---|---:|---:|---:|---:|---:|---:|---|")
    status = {c["type"]: c["status"] for c in meta["cells"]}
    for t in sorted(by_type, key=lambda t: -sum(power(by_type[t]))):
        p = dict(zip(rails, power(by_type[t])))
        L.append(f"| {t} | {count[t]} | {fmt(p.get('h', 0), 2)} | {fmt(p.get('a', 0) + p.get('g2', 0), 2)} | "
                 f"{fmt(p.get('n50', 0), 2)} | {fmt(p.get('hv', 0), 2)} | {fmt(sum(p.values()), 2)} | {status[t]} |")
    L.append("")
    allp = sum(by_status.values())
    L.append("Доля мощности по качеству модели: " + ", ".join(
        f"{k} {100 * v / allp:.0f} %" for k, v in sorted(by_status.items(), key=lambda kv: -kv[1])) + ".\n")

    text = "\n".join(L)
    if args.out:
        open(args.out, "w").write(text)
    print(text)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("plan")
    p.add_argument("-n", "--netlist", required=True)
    p.add_argument("-t", "--top", required=True)
    p.add_argument("-s", "--scope", required=True)
    p.add_argument("-l", "--lib", required=True)
    p.add_argument("-m", "--model", required=True)
    p.add_argument("-o", "--out", required=True)
    p.add_argument("-w", "--window", type=float, default=10000, help="peak window, ns (default 10000 = Clk)")
    r = sub.add_parser("report")
    r.add_argument("-p", "--plan", required=True)
    r.add_argument("-r", "--result", required=True)
    r.add_argument("-o", "--out")
    r.add_argument("--title", default="Потребление")
    a = ap.parse_args()
    plan(a) if a.cmd == "plan" else report(a)


if __name__ == "__main__":
    main()
