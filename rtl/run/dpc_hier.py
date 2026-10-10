#!/usr/bin/env python3
"""Hierarchy area report from Yosys `stat -liberty -json` output.

Prints a Synopsys/Cadence-style hierarchy report: a tree of modules with
instance counts and cumulative (subtree) cell count, area and one column per
base cell type. Cumulative values mean a module row already includes its
submodules, so the top row equals the design total. Only the standard library
is required.
"""

import argparse
import json
import re


def short_name(full):
    """Return a readable module name from a Yosys internal name."""
    s = full.lstrip("\\")
    if s.startswith("$paramod"):
        parts = [p for p in s.split("\\") if p]
        if len(parts) > 1:
            mod = parts[1]
            params = "\\".join(parts[2:])
            if params:
                params = re.sub(
                    r"(\w+=)([sd]?\d+'[01]+)",
                    lambda m: m.group(1)
                    + str(int(re.sub(r"[^01]", "", m.group(2)), 2)),
                    params,
                )
                return f"{mod}<{params}>"
            return mod
        return s
    return s


def analyze(modules):
    """Split cell references into child modules and leaf cells."""
    norm_to_full = {name.lstrip("\\"): name for name in modules}
    children = {name: [] for name in modules}
    leaves = {name: {} for name in modules}
    for name in modules:
        for ctype, cnt in modules[name].get("num_cells_by_type", {}).items():
            full = norm_to_full.get(ctype.lstrip("\\"))
            if full is not None and full != name:
                children[name].append((full, cnt))
            else:
                leaves[name][ctype] = leaves[name].get(ctype, 0) + cnt
    return children, leaves


def subtree(name, modules, children, leaves, memo):
    """Cumulative (cells, area, type_counts) for one instance of `name`."""
    if name in memo:
        return memo[name]
    cells = sum(leaves[name].values())
    area = modules[name].get("area", 0.0)
    types = dict(leaves[name])
    for child, cnt in children[name]:
        c_cells, c_area, c_types = subtree(child, modules, children, leaves, memo)
        cells += cnt * c_cells
        area += cnt * c_area
        for t, v in c_types.items():
            types[t] = types.get(t, 0) + cnt * v
    memo[name] = (cells, area, types)
    return memo[name]


def instance_totals(children):
    """Total number of instances of each module across the whole design."""
    counts = {}
    for kids in children.values():
        for child, cnt in kids:
            counts[child] = counts.get(child, 0) + cnt
    return counts


def find_root(modules, top):
    for name in modules:
        if name == "\\" + top:
            return name
    for name in modules:
        if short_name(name) == top:
            return name
    return next(iter(modules))


def build_rows(modules, children, leaves, root):
    instances = instance_totals(children)
    memo = {}
    rows = []
    visited = set()

    def walk(name, depth):
        if name in visited:
            return
        visited.add(name)
        cells, area, types = subtree(name, modules, children, leaves, memo)
        rows.append(
            {
                "depth": depth,
                "name": short_name(name),
                "inst": 1 if name == root else instances.get(name, 0),
                "cells": cells,
                "area": area,
                "cell_counts": types,
            }
        )
        for child, _cnt in children[name]:
            walk(child, depth + 1)

    walk(root, 0)
    return rows, memo[root]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", "-j", required=True, help="Yosys stat -json file")
    parser.add_argument("--top", "-t", required=True, help="Top module name")
    args = parser.parse_args()

    with open(args.json, "r") as f:
        data = json.load(f)

    modules = data.get("modules", {})
    if not modules:
        print(f"No modules found in {args.json}")
        return

    children, leaves = analyze(modules)
    root = find_root(modules, args.top)
    rows, total = build_rows(modules, children, leaves, root)

    cell_cols = sorted(total[2], key=lambda c: (-total[2][c], c))
    headers = ["Module", "Instances", "Cells", "Area"] + cell_cols
    widths = [len(h) for h in headers]

    for r in rows:
        widths[0] = max(widths[0], len(r["name"]) + 2 * r["depth"])
        widths[1] = max(widths[1], len(str(r["inst"])))
        widths[2] = max(widths[2], len(str(r["cells"])))
        widths[3] = max(widths[3], len(f"{r['area']:.2f}"))
    for i, ct in enumerate(cell_cols):
        widths[4 + i] = max(len(ct), len(str(total[2][ct])))

    width = sum(widths) + 2 * (len(headers) - 1)

    def line(name_col, inst, cells, area, counts):
        out = (
            name_col.ljust(widths[0])
            + "  "
            + f"{inst:>{widths[1]}}"
            + "  "
            + f"{cells:>{widths[2]}}"
            + "  "
            + f"{area:>{widths[3]}.2f}"
        )
        for i, ct in enumerate(cell_cols):
            out += "  " + f"{counts.get(ct, 0):>{widths[4 + i]}}"
        return out

    print("=" * (width + 2))
    print(f"Module hierarchy area report: {root}  (top: {args.top})")
    print("=" * (width + 2))

    hdr = (
        headers[0].ljust(widths[0])
        + "  "
        + f"{headers[1]:>{widths[1]}}"
        + "  "
        + f"{headers[2]:>{widths[2]}}"
        + "  "
        + f"{headers[3]:>{widths[3]}}"
    )
    for i, ct in enumerate(cell_cols):
        hdr += "  " + f"{ct:>{widths[4 + i]}}"
    print(hdr)
    print("-" * (width + 2))

    for r in rows:
        print(
            line(
                "  " * r["depth"] + r["name"],
                r["inst"],
                r["cells"],
                r["area"],
                r["cell_counts"],
            )
        )

    print("-" * (width + 2))
    print(line("Total", "", total[0], total[1], total[2]))
    print("=" * (width + 2))


if __name__ == "__main__":
    main()
