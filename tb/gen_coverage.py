#!/usr/bin/env python3
"""Generate HDL code coverage reports using the `covered` tool.

Runs `covered score` on each VCD file plus all Verilog sources, merges the
resulting CDD files, then generates per-module HTML reports.

Requires: covered (apt-get install covered)
"""

import argparse
import glob
import os
import subprocess
import sys
from collections import defaultdict


def find_verilog_sources(source_root):
    """Find all Verilog source files under source_root."""
    sources = []
    for ext in ("*.sv", "*.v"):
        for path in glob.glob(os.path.join(source_root, "**", ext), recursive=True):
            sources.append(os.path.abspath(path))
    return sorted(sources)


def run_covered_score(vcd_path, source_paths, cdd_path):
    """Run `covered score` to generate a CDD from VCD + Verilog sources."""
    cmd = ["covered", "score", "-v", vcd_path, "-o", cdd_path] + source_paths
    try:
        subprocess.run(cmd, check=True, capture_output=True, text=True)
        return True
    except subprocess.CalledProcessError as e:
        print(f"  WARNING: covered score failed for {os.path.basename(vcd_path)}", file=sys.stderr)
        print(f"    {e.stderr.strip()[:200]}", file=sys.stderr)
        return False


def run_covered_merge(cdd_paths, merged_cdd):
    """Merge multiple CDD files into one."""
    if not cdd_paths:
        return None
    if len(cdd_paths) == 1:
        merged = cdd_paths[0]
        return merged
    cmd = ["covered", "merge", "-o", merged_cdd] + cdd_paths
    try:
        subprocess.run(cmd, check=True, capture_output=True, text=True)
        return merged_cdd
    except subprocess.CalledProcessError as e:
        print(f"  WARNING: covered merge failed: {e.stderr.strip()[:200]}", file=sys.stderr)
        return cdd_paths[0] if cdd_paths else None


def run_covered_report(merged_cdd, source_paths, output_dir):
    """Generate HTML coverage report from merged CDD."""
    os.makedirs(output_dir, exist_ok=True)
    cmd = ["covered", "report", "-d", "D", "-o", output_dir, merged_cdd] + source_paths
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"  WARNING: covered report had issues: {result.stderr.strip()[:200]}", file=sys.stderr)
        else:
            print(f"  HTML report generated: {output_dir}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"  ERROR: covered report failed: {e.stderr.strip()[:200]}", file=sys.stderr)
        return False


def run_covered_summary(merged_cdd, source_paths, output_file):
    """Generate text coverage summary from merged CDD."""
    cmd = ["covered", "report", "-d", "S", "-o", output_file, merged_cdd] + source_paths
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"  WARNING: covered summary had issues: {result.stderr.strip()[:200]}", file=sys.stderr)
        return True
    except subprocess.CalledProcessError as e:
        print(f"  ERROR: covered summary failed: {e.stderr.strip()[:200]}", file=sys.stderr)
        return False


def parse_module_coverage(summary_file):
    """Parse covered summary output to extract per-module stats."""
    modules = defaultdict(lambda: {"lines": 0, "covered": 0, "pct": 0.0})

    if not os.path.exists(summary_file):
        return modules

    with open(summary_file) as f:
        lines = f.readlines()

    current_module = None
    for line in lines:
        line = line.strip()
        if not line:
            continue

        # covered report -d S format varies; look for module names and stats
        if line.startswith("Module:") or line.startswith("Instance:"):
            current_module = line.split(":", 1)[1].strip()
        elif "Line Coverage:" in line and current_module:
            parts = line.split()
            for i, p in enumerate(parts):
                if p == "Covered:" and i + 1 < len(parts):
                    modules[current_module]["covered"] = int(parts[i + 1].rstrip(","))
                if p == "Lines:" and i + 1 < len(parts):
                    modules[current_module]["lines"] = int(parts[i + 1].rstrip(","))
            if modules[current_module]["lines"] > 0:
                modules[current_module]["pct"] = (
                    100.0
                    * modules[current_module]["covered"]
                    / modules[current_module]["lines"]
                )

    return modules


def main():
    parser = argparse.ArgumentParser(description="Generate HDL code coverage reports")
    parser.add_argument("--vcd-dir", required=True, help="Directory containing VCD files")
    parser.add_argument("--source-root", required=True, help="Root of Verilog source tree")
    parser.add_argument("--output", required=True, help="Output directory for reports")
    parser.add_argument("--cdd-dir", required=True, help="Directory for intermediate CDD files")
    args = parser.parse_args()

    source_paths = find_verilog_sources(args.source_root)
    if not source_paths:
        print("ERROR: No Verilog sources found", file=sys.stderr)
        sys.exit(1)

    print(f"  Found {len(source_paths)} Verilog source files")

    vcd_files = sorted(glob.glob(os.path.join(args.vcd_dir, "*.vcd")))
    if not vcd_files:
        print("WARNING: No VCD files found — run tests with COVERAGE=1 first", file=sys.stderr)
        sys.exit(1)

    print(f"  Found {len(vcd_files)} VCD files")

    # Phase A: Score each VCD → CDD
    os.makedirs(args.cdd_dir, exist_ok=True)
    cdd_files = []
    for vcd_path in vcd_files:
        name = os.path.splitext(os.path.basename(vcd_path))[0]
        cdd_path = os.path.join(args.cdd_dir, f"{name}.cdd")
        print(f"  Scoring {name} ...", end=" ", flush=True)
        if run_covered_score(vcd_path, source_paths, cdd_path):
            cdd_files.append(cdd_path)
            print("OK")
        else:
            print("SKIPPED")

    if not cdd_files:
        print("ERROR: No CDD files generated", file=sys.stderr)
        sys.exit(1)

    # Phase B: Merge CDDs
    merged_cdd = os.path.join(args.cdd_dir, "merged.cdd")
    print(f"\n  Merging {len(cdd_files)} CDD files ...", end=" ", flush=True)
    final_cdd = run_covered_merge(cdd_files, merged_cdd)
    print("OK" if final_cdd else "FAILED")

    if not final_cdd:
        sys.exit(1)

    # Phase C: Generate HTML report
    print(f"  Generating HTML report ...", end=" ", flush=True)
    run_covered_report(final_cdd, source_paths, args.output)
    print("OK")

    # Phase D: Generate text summary
    summary_file = os.path.join(args.output, "coverage_summary.txt")
    print(f"  Generating text summary ...", end=" ", flush=True)
    run_covered_summary(final_cdd, source_paths, summary_file)

    # Phase E: Print per-module coverage
    modules = parse_module_coverage(summary_file)
    if modules:
        print("\n  === Per-Module Line Coverage ===")
        print(f"  {'Module':<30} {'Lines':>8} {'Covered':>8} {'%':>7}")
        print(f"  {'-'*30} {'-'*8} {'-'*8} {'-'*7}")
        total_lines = sum(m["lines"] for m in modules.values())
        total_covered = sum(m["covered"] for m in modules.values())
        for mod, stats in sorted(modules.items()):
            print(f"  {mod:<30} {stats['lines']:>8} {stats['covered']:>8} {stats['pct']:>6.1f}%")
        print(f"  {'-'*30} {'-'*8} {'-'*8} {'-'*7}")
        pct = 100.0 * total_covered / total_lines if total_lines > 0 else 0
        print(f"  {'TOTAL':<30} {total_lines:>8} {total_covered:>8} {pct:>6.1f}%")
        print()

    print(f"  Report: file://{os.path.abspath(args.output)}/index.html")
    print("  OK" if final_cdd else "FAILED")


if __name__ == "__main__":
    main()
