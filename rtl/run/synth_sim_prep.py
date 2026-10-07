"""Prepare a Yosys netlist for gate-level simulation with the RTL testbench.

1. Checks that every cell of the liberty file has a Verilog model in
   vtube_cells.v (the models are written by hand and may drift).
2. A synthesized top module has no parameters, but the testbench instantiates
   it with the same overrides that were given to synt_dpc.tcl (-p). The
   parameters are declared again in the top module with the synthesized
   values, and an initial block stops the simulation if the testbench passes
   a different value than the netlist was built for.

usage: synth_sim_prep.py -l vtube_cells.lib -c vtube_cells.v -n top_synth.v
                         -t top [-p NAME=VALUE ...]
"""

import argparse
import re
import sys


def check_cells(lib_path, cells_path):
    lib_cells = set(re.findall(r"\bcell\s*\(\s*(\w+)\s*\)", open(lib_path).read()))
    models = set(re.findall(r"^\s*module\s+(\w+)", open(cells_path).read(), re.M))
    missing = sorted(lib_cells - models)
    if missing:
        sys.exit(f"{cells_path}: no model for liberty cells: {', '.join(missing)}")


def add_params(netlist_path, top, params):
    text = open(netlist_path).read()
    header = re.search(rf"^module {re.escape(top)}\s*\(.*?\);\n", text, re.M | re.S)
    if not header:
        sys.exit(f"{netlist_path}: top module {top} not found")
    decl = "".join(f"  parameter {n} = {v};\n" for n, v in params)
    checks = "".join(
        f"    if ({n} !== {v}) $fatal(1, \"{top} netlist built with {n}={v}, "
        f"testbench passes %0d\", {n});\n" for n, v in params)
    block = (f"  // Added by synth_sim_prep.py: overrides given to synt_dpc.tcl\n"
             f"{decl}  initial begin\n{checks}  end\n")
    text = text[:header.end()] + block + text[header.end():]
    open(netlist_path, "w").write(text)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("-l", "--lib", required=True)
    ap.add_argument("-c", "--cells", required=True)
    ap.add_argument("-n", "--netlist", required=True)
    ap.add_argument("-t", "--top", required=True)
    ap.add_argument("-p", "--param", action="append", default=[],
                    help="NAME=VALUE, as passed to synt_dpc.tcl")
    args = ap.parse_args()

    check_cells(args.lib, args.cells)
    params = [p.split("=", 1) for p in args.param]
    if params:
        add_params(args.netlist, args.top, params)


if __name__ == "__main__":
    main()
