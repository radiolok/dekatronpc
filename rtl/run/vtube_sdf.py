"""SDF delays and setup/hold checks for a Yosys netlist of vacuum-tube cells.

Writes into OUT_DIR:
  <module>.sdf  one per netlist module that holds library cells: an IOPATH
                entry for every specify path of the cell in vtube_cells.v,
                with the value from vtube_timing.json, and SETUPHOLD for the
                triggers (Icarus parses it but does not check it)
  vtube_sdf.sv  module vtube_sdf, a second simulation root (iverilog
                -s vtube_sdf): one $sdf_annotate per module instance of
                the netlist under SCOPE, a vtube_setuphold checker on every
                trigger, and a final summary line
                "VTUBE TIMING: <n> setup, <m> hold violations, <k> masked"
                (masked: triggers listed in the "masked" section of the
                timing file, whose violations count only when the next
                edge consumes the value, see vtube_timing_check.v)

Icarus cannot find escaped instance names with '.' or '[' in an SDF path
(Yosys writes \\dek[0].dModule for generate blocks), and it has no
INSTANCE * wildcard. So each SDF is relative to one module and is applied
to every instance of that module separately; Verilog hierarchical names
reach any scope. A cell with such a name itself gets cell_<type>.sdf
(empty INSTANCE), applied to the cell's own scope.

Load-aware mode (-l vtube_cells_timing.lib -j top_flat.json): every cell
instance gets the delays of the liberty tables at the load of the net its
output drives (sum of the sink pins' capacitance in grids, from the netlist
flattened by synt_dpc.tcl -flat), the same delays vtube_sta.py uses. The SDF
is then written per module instance (s<k>.sdf), not per module, because two
instances of one module drive different loads. Without -l/-j every arc has
its fanout-6 value from vtube_timing.json.

usage: vtube_sdf.py -c vtube_cells.v -T vtube_timing.json -n top_synth.v
                    -t top -s tb.dut_instance -o OUT_DIR
                    [-l vtube_cells_timing.lib -j top_flat.json]
"""

import argparse
import json
import os
import re
import sys

ID = r"(?:\\\S+|[A-Za-z_][\w$]*)"
KEYWORDS = {"module", "input", "output", "inout", "wire", "reg", "assign",
            "parameter", "localparam", "initial", "always", "endmodule",
            "if", "begin", "end"}
# trigger cell -> (vtube_setuphold ASYNC mode, set pin, reset pin); 3: clear while RN = 0, 4: preset while SN = 0
ASYNC = {"DFF_J2N16": (0, None, None), "DFFRN_J2N16X7": (3, None, "RN"), "DFFSN_J2N16X7": (4, "SN", None)}


def vname(name):
    """Name as it is written in a hierarchical reference."""
    return name + " " if name.startswith("\\") else name


def plain(name):
    return name[1:] if name.startswith("\\") else name


def cell_paths(cells_path):
    """{cell: [(edge, in, out)]} from the specify blocks."""
    text = open(cells_path).read()
    paths = {}
    for name, body in re.findall(r"^module (\w+)\(.*?\n(.*?)^endmodule", text, re.M | re.S):
        spec = re.search(r"specify(.*?)endspecify", body, re.S)
        paths[name] = [] if not spec else [
            (m.group(1) or "", m.group(2), m.group(3)) for m in re.finditer(
                r"\(((?:pos|neg)edge\s+)?(\w+)\s*=>\s*\(?\s*(\w+)", spec.group(1))]
    return paths


def parse_netlist(path, qnets=None):
    """{module: [(type, instance)]} in file order (Yosys write_verilog layout:
    one instance header "type name (" per line). If qnets is a dict, it gets
    {(module, instance): net on the .Q pin}."""
    mods, cur, cur_mod, last = {}, None, None, None
    head = re.compile(rf"^module ({ID})\s*\(")
    inst = re.compile(rf"^\s*({ID})\s+({ID})\s*\(\s*$")
    qpin = re.compile(r"^\s*\.Q\((.*)\),?\s*$")
    for line in open(path):
        if cur is None:
            m = head.match(line)
            if m:
                cur_mod = m.group(1)
                cur = mods.setdefault(cur_mod, [])
        elif line.startswith("endmodule"):
            cur = None
        else:
            m = inst.match(line)
            if m and m.group(1) not in KEYWORDS:
                cur.append((m.group(1), m.group(2)))
                last = m.group(2)
                continue
            m = qpin.match(line)
            if m and qnets is not None and last is not None:
                qnets[(cur_mod, last)] = m.group(1).strip()
    return mods


def masked_rule(rules, mod, qnet):
    """The "masked" rule of vtube_timing.json that covers this trigger."""
    for rule in rules:
        if plain(mod).endswith(rule["module"]) and re.search(rule["q"], plain(qnet)):
            return rule
    return None


def scoped(expr, scope):
    """Prefix the signal names of a used_when expression with the scope."""
    return re.sub(r"\b([A-Za-z_]\w*)\b", lambda m: f"{scope}.{m.group(1)}", expr)


def delay(v):
    return f"({v[0]}) ({v[1]})" if isinstance(v, list) else f"({v})"


def bad_name(inst):
    """Icarus splits SDF instance paths at '.', even escaped ones."""
    return re.search(r"[.\[\]]", inst) is not None


def clock_edge(cpaths):
    """posedge, or negedge for a falling-edge trigger (DFF_J2N16)."""
    return "negedge" if any(e.strip() == "negedge" for e, _, _ in cpaths) else "posedge"


def cell_entry(ctype, inst, paths, timing, loads=None, flat=None):
    t = timing["cells"][ctype]
    io = []
    for edge, a, y in paths[ctype]:
        key = f"{edge}{a}->{y}"
        if key not in t["iopath"]:
            sys.exit(f"vtube_timing.json: {ctype} has no value for {key}")
        v = t["iopath"][key]
        if loads is not None:
            v = loads.value(ctype, flat, edge, a, y, v)
        src = f"({edge.strip()} {a})" if edge else a
        io.append(f"(IOPATH {src} {y} {delay(v)})")
    ent = (f' (CELL (CELLTYPE "{ctype}") (INSTANCE {inst})\n'
           f'  (DELAY (ABSOLUTE {" ".join(io)}))')
    for d, (su, ho) in t.get("setuphold", {}).items():
        ent += f"\n  (TIMINGCHECK (SETUPHOLD {d} ({clock_edge(paths[ctype])} C) ({su}) ({ho})))"
    return ent + ")"


class Loads:
    """Arc delays at the load of each flat cell instance (load-aware mode)."""

    def __init__(self, lib_path, flat_path, top):
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from vtube_sta import load_lib, interp
        self.interp = interp
        self.index, self.lib = load_lib(lib_path)
        mod = json.load(open(flat_path))["modules"][top]
        load = {}
        for c in mod["cells"].values():
            lc = self.lib.get(c["type"])
            for p, bits in c["connections"].items():
                if c["port_directions"].get(p) == "input":
                    cap = lc["pins"][p]["cap"] if lc and p in lc["pins"] else 1.0
                    for b in bits:
                        if isinstance(b, int):
                            load[b] = load.get(b, 0.0) + cap
        self.out_load = {name: {p: max((load.get(b, 0.0) for b in bits if isinstance(b, int)), default=0.0)
                                for p, bits in c["connections"].items()
                                if c["port_directions"].get(p) == "output"}
                         for name, c in mod["cells"].items()}
        self.missing = 0

    def value(self, ctype, flat, edge, a, y, fallback):
        """[rise, fall] of arc a->y of the instance, fallback where the liberty has none."""
        lc = self.lib.get(ctype)
        loads = self.out_load.get(flat)
        if lc is None or loads is None:
            self.missing += loads is None
            return fallback
        kind = {"negedge": "falling_edge", "posedge": "rising_edge"}.get(edge.strip())
        for arc in lc["arcs"]:
            if arc.src != a or arc.dst != y:
                continue
            if kind and arc.kind != kind or not kind and arc.kind in ("falling_edge", "rising_edge"):
                continue
            fb = fallback if isinstance(fallback, list) else [fallback, fallback]
            x = loads.get(y, 0.0)
            r = round(self.interp(self.index, arc.rise, x), 1) if arc.rise else fb[0]
            f = round(self.interp(self.index, arc.fall, x), 1) if arc.fall else fb[1]
            return [r, f]
        return fallback


def write_sdf(path, design, entries, timing):
    head = (f'(DELAYFILE\n (SDFVERSION "3.0")\n (DESIGN "{design}")\n'
            f' (PROGRAM "vtube_sdf.py")\n (DIVIDER .)\n (TIMESCALE {timing["timescale"]})')
    open(path, "w").write("\n".join([head, *entries, ")"]) + "\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("-c", "--cells", required=True)
    ap.add_argument("-T", "--timing", required=True)
    ap.add_argument("-n", "--netlist", required=True)
    ap.add_argument("-t", "--top", required=True)
    ap.add_argument("-s", "--scope", required=True, help="hierarchical name of the top instance")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("-l", "--lib", help="timing liberty (vtube_cells_timing.lib): load-aware delays")
    ap.add_argument("-j", "--flat", help="flat netlist JSON (synt_dpc.tcl -flat): the loads")
    args = ap.parse_args()
    loads = Loads(args.lib, args.flat, args.top) if args.lib and args.flat else None

    paths = cell_paths(args.cells)
    timing = json.load(open(args.timing))
    qnets = {}
    mods = parse_netlist(args.netlist, qnets)
    rules = timing.get("masked", [])
    if args.top not in mods:
        sys.exit(f"{args.netlist}: top module {args.top} not found")
    missing = sorted({t for insts in mods.values() for t, _ in insts
                      if t in paths and paths[t] and t not in timing["cells"]})
    if missing:
        sys.exit(f"{args.timing}: no timing for cells {', '.join(missing)}")
    os.makedirs(args.out, exist_ok=True)

    out = os.path.abspath(args.out)
    # Cells named like \\g_lvl[0].rel get an SDF of their own type with an
    # empty INSTANCE, applied to the cell's own scope
    sdf_of, cell_sdf = {}, {}
    for i, (mod, insts) in enumerate(mods.items()):
        cells = [(t, n) for t, n in insts if t in paths and paths[t]]
        for t, n in cells:
            if bad_name(n) and t not in cell_sdf:
                cell_sdf[t] = os.path.join(out, f"cell_{t}.sdf")
                write_sdf(cell_sdf[t], t, [cell_entry(t, "", paths, timing)], timing)
        entries = [cell_entry(t, plain(n), paths, timing) for t, n in cells if not bad_name(n)]
        if entries:
            base = re.sub(r"\W", "_", plain(mod))[-40:]
            sdf_of[mod] = os.path.join(out, f"m{i}_{base}.sdf")
            write_sdf(sdf_of[mod], plain(mod), entries, timing)

    annotate, checks, n_cells, n_masked = [], [], 0, 0

    def flat_name(rel, inst):
        return ".".join(rel + [plain(inst)])

    def walk(mod, scope, rel):
        nonlocal n_cells, n_masked
        if loads is not None:
            cells = [(t, n) for t, n in mods[mod] if t in paths and paths[t]]
            entries = [cell_entry(t, plain(n), paths, timing, loads, flat_name(rel, n))
                       for t, n in cells if not bad_name(n)]
            if entries:
                f = os.path.join(out, f"s{len(annotate)}.sdf")
                write_sdf(f, plain(mod), entries, timing)
                annotate.append(f'\t$sdf_annotate("{f}", {scope});')
        elif mod in sdf_of:
            annotate.append(f'\t$sdf_annotate("{sdf_of[mod]}", {scope});')
        for t, inst in mods[mod]:
            ref = f"{scope}.{vname(inst)}"
            if t in mods:
                walk(t, ref, rel + [plain(inst)])
            elif t in paths and paths[t]:
                n_cells += 1
                if bad_name(inst) and loads is not None:
                    f = os.path.join(out, f"s{len(annotate)}.sdf")
                    write_sdf(f, t, [cell_entry(t, "", paths, timing, loads, flat_name(rel, inst))], timing)
                    annotate.append(f'\t$sdf_annotate("{f}", {ref});')
                elif bad_name(inst):
                    annotate.append(f'\t$sdf_annotate("{cell_sdf[t]}", {ref});')
                sh = timing["cells"][t].get("setuphold", {}).get("D")
                if sh and t in ASYNC:
                    mode, sp, rp = ASYNC[t]
                    s = f"{ref}.{sp}" if sp else "1'b1"
                    r = f"{ref}.{rp}" if rp else "1'b1"
                    rule = masked_rule(rules, mod, qnets.get((mod, inst), ""))
                    q, en = (1, scoped(rule["used_when"], scope)) if rule else (0, "1'b1")
                    n_masked += q
                    checks.append(
                        f"vtube_setuphold #(.SETUP({sh[0]}), .HOLD({sh[1]}), .ASYNC({mode}),"
                        f" .NEGEDGE({int(clock_edge(paths[t]) == 'negedge')}),"
                        f" .QUALIFY({q})) c{len(checks)} (.C({ref}.C), .D({ref}.D),"
                        f" .S({s}), .R({r}), .EN({en}));")

    walk(args.top, args.scope, [])

    total = lambda f: " + ".join(f"c{i}.{f}" for i in range(len(checks))) or "0"
    sv = [f"// Generated by rtl/run/vtube_sdf.py from {os.path.basename(args.netlist)}"
          f" and {os.path.basename(args.timing)}; do not edit.",
          f"// {n_cells} cells, {len(annotate)} annotated scopes, {len(checks)} triggers checked"
          f" ({n_masked} of them qualified by their consumer).",
          "module vtube_sdf;", "timeunit 1ns;", "timeprecision 1ps;",
          "initial begin", *annotate, "end", "", *checks, "",
          "final", f'\t$display("VTUBE TIMING: %0d setup, %0d hold violations, %0d masked",',
          f"\t         {total('setup_cnt')},", f"\t         {total('hold_cnt')},",
          f"\t         {total('masked_cnt')});",
          "endmodule"]
    open(os.path.join(args.out, "vtube_sdf.sv"), "w").write("\n".join(sv) + "\n")
    print(f"  sdf   {n_cells} cells, {len(annotate)} annotated scopes, {len(checks)} triggers checked"
          f" ({n_masked} qualified)"
          + (f", delays at each net load ({loads.missing} dead cells, removed by the flattening:"
             " fanout-6 values)" if loads else ""))


if __name__ == "__main__":
    main()
