#!/usr/bin/env python3
"""Merge native Verilator coverage databases and generate LCOV/HTML reports."""

import argparse
import glob
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


class CoverageError(RuntimeError):
    """An input, tool, or output error that must stop report generation."""


@dataclass
class CoverageCounts:
    lines_hit: int = 0
    lines_found: int = 0
    branches_hit: int = 0
    branches_found: int = 0
    toggles_hit: int = 0
    toggles_found: int = 0

    def add(self, other):
        self.lines_hit += other.lines_hit
        self.lines_found += other.lines_found
        self.branches_hit += other.branches_hit
        self.branches_found += other.branches_found
        self.toggles_hit += other.toggles_hit
        self.toggles_found += other.toggles_found


@dataclass
class FileCoverage(CoverageCounts):
    source: str = ""


def percentage(hit, found):
    return f"{100.0 * hit / found:.1f}%" if found else "n/a"


def parse_lcov_info(text):
    """Return per-file and total counters from an LCOV tracefile."""
    files = []
    current = None
    da_records = []
    branch_records = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if line.startswith("SF:"):
            if current is not None:
                raise CoverageError("LCOV record has no end_of_record")
            current = FileCoverage(source=line[3:])
            da_records = []
            branch_records = []
        elif line == "end_of_record":
            if current is None:
                raise CoverageError("LCOV end_of_record has no SF record")
            # Verilator 5.034 emits DA/BRDA but no LF/LH. LCOV summaries
            # use those raw records, so do the same instead of reporting 0/0.
            if da_records:
                current.lines_found = len(da_records)
                current.lines_hit = sum(hit > 0 for hit in da_records)
            if branch_records:
                current.branches_found = len(branch_records)
                current.branches_hit = sum(hit > 0 for hit in branch_records)
            files.append(current)
            current = None
        elif current is not None and ":" in line:
            key, value = line.split(":", 1)
            try:
                if key == "DA":
                    source_line, hit = value.split(",", 1)
                    if int(source_line) < 0:
                        raise ValueError
                    da_records.append(0 if hit == "-" else int(hit))
                elif key == "BRDA":
                    fields = value.split(",")
                    if len(fields) != 4 or any(int(field) < 0 for field in fields[:3]):
                        raise ValueError
                    branch_records.append(0 if fields[3] == "-" else int(fields[3]))
                elif key in {"LF", "LH", "BRF", "BRH"}:
                    count = int(value)
                    if count < 0:
                        raise ValueError
                    attribute = {
                        "LF": "lines_found",
                        "LH": "lines_hit",
                        "BRF": "branches_found",
                        "BRH": "branches_hit",
                    }[key]
                    setattr(current, attribute, count)
            except ValueError as error:
                raise CoverageError(f"Invalid LCOV counter: {line}") from error
    if current is not None:
        raise CoverageError("LCOV record has no end_of_record")
    if not files:
        raise CoverageError("LCOV report contains no source records")
    total = CoverageCounts()
    for item in files:
        total.add(item)
    return files, total


def parse_lcov(path):
    return parse_lcov_info(Path(path).read_text(encoding="utf-8"))


def parse_verilator_dat(path):
    """Group native v_toggle/v_branch point counts by source file.

    Verilator 5.034 stores each point as ``C '<binary key>' <count>``. The
    key contains 0x01-separated tag records; 0x02 separates a tag from its
    ASCII value. LCOV coalesces these points into source lines, so the native
    database is needed for independent branch and toggle metrics.
    """
    counts = {}
    for raw_record in Path(path).read_bytes().splitlines():
        if not raw_record or raw_record.startswith(b"#"):
            continue
        payload, separator, raw_count = raw_record.rpartition(b"' ")
        if not separator or not payload.startswith(b"C '"):
            raise CoverageError(f"Invalid Verilator coverage record in {path}")
        try:
            count = int(raw_count)
            if count < 0:
                raise ValueError
            fields = {}
            for raw_field in payload[3:].split(b"\x01"):
                if not raw_field:
                    continue
                tag, delimiter, value = raw_field.partition(b"\x02")
                if not delimiter or not tag:
                    raise ValueError
                fields[tag] = value
            page = fields[b"page"].decode("ascii")
            source = fields[b"f"].decode("utf-8")
        except (KeyError, UnicodeError, ValueError) as error:
            raise CoverageError(f"Invalid Verilator coverage record in {path}") from error
        if not page.startswith(("v_toggle", "v_branch")):
            continue
        item = counts.setdefault(source, CoverageCounts())
        if page.startswith("v_toggle"):
            item.toggles_found += 1
            if count > 0:
                item.toggles_hit += 1
        else:
            item.branches_found += 1
            if count > 0:
                item.branches_hit += 1
    if not counts:
        raise CoverageError(f"Coverage database has no coverage points: {path}")
    return counts


def resolve_databases(patterns):
    """Expand file/glob arguments into a validated, ordered unique list."""
    resolved = []
    seen = set()
    for pattern in patterns:
        matches = glob.glob(str(pattern))
        if not matches and Path(pattern).is_file():
            matches = [str(pattern)]
        if not matches:
            raise CoverageError(f"Coverage input did not match any file: {pattern}")
        for match in sorted(matches):
            database = Path(match).resolve()
            if not database.is_file() or database.stat().st_size == 0:
                raise CoverageError(f"Coverage database is missing or empty: {database}")
            if database in seen:
                raise CoverageError(f"Duplicate coverage input: {database}")
            seen.add(database)
            resolved.append(database)
    if not resolved:
        raise CoverageError("No coverage databases matched the input paths")
    return resolved


def run_command(command):
    """Run one external tool without hiding diagnostics or failures."""
    print("+", " ".join(str(part) for part in command), flush=True)
    try:
        result = subprocess.run(
            [str(part) for part in command],
            check=True,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as error:
        raise CoverageError(f"Required tool not found: {command[0]}") from error
    except subprocess.CalledProcessError as error:
        diagnostic = (error.stderr or error.stdout or str(error)).strip()
        raise CoverageError(f"{command[0]} failed: {diagnostic}") from error
    return result


def write_summary(info_path, merged_path, output_path, database_count):
    files, total = parse_lcov(info_path)
    toggle_counts = parse_verilator_dat(merged_path)
    for item in files:
        native = toggle_counts.get(item.source, CoverageCounts())
        item.toggles_hit = native.toggles_hit
        item.toggles_found = native.toggles_found
        # BRDA also contains toggle/expression records in Verilator 5.034.
        item.branches_hit = native.branches_hit
        item.branches_found = native.branches_found
    total.branches_hit = total.branches_found = 0
    for native in toggle_counts.values():
        total.toggles_hit += native.toggles_hit
        total.toggles_found += native.toggles_found
        total.branches_hit += native.branches_hit
        total.branches_found += native.branches_found

    lines = [
        f"Coverage databases: {database_count}",
        "",
        f"{'Source':<60} {'Lines':>17} {'Branches':>17} {'Toggles':>17}",
        "-" * 115,
    ]
    for item in files:
        line_stats = f"{item.lines_hit}/{item.lines_found} ({percentage(item.lines_hit, item.lines_found)})"
        branch_stats = (
            f"{item.branches_hit}/{item.branches_found} "
            f"({percentage(item.branches_hit, item.branches_found)})"
        )
        toggle_stats = (
            f"{item.toggles_hit}/{item.toggles_found} "
            f"({percentage(item.toggles_hit, item.toggles_found)})"
        )
        lines.append(f"{item.source:<60} {line_stats:>17} {branch_stats:>17} {toggle_stats:>17}")
    lines.extend(
        [
            "-" * 115,
            f"Overall line coverage: {total.lines_hit}/{total.lines_found} "
            f"({percentage(total.lines_hit, total.lines_found)})",
            f"Overall branch coverage: {total.branches_hit}/{total.branches_found} "
            f"({percentage(total.branches_hit, total.branches_found)})",
            f"Overall toggle coverage: {total.toggles_hit}/{total.toggles_found} "
            f"({percentage(total.toggles_hit, total.toggles_found)})",
        ]
    )
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return total


def generate_report(inputs, output_dir):
    databases = resolve_databases(inputs)
    # Validate every input before any tool runs: verilator_coverage itself
    # silently accepts truncated records and would publish fabricated data.
    for database in databases:
        parse_verilator_dat(database)

    output_dir = Path(output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    merged = output_dir / "merged.dat"
    info = output_dir / "coverage.info"
    html = output_dir / "html"

    run_command(["verilator_coverage", "--write", merged, *databases])
    if not merged.is_file() or merged.stat().st_size == 0:
        raise CoverageError(f"verilator_coverage did not create {merged}")
    run_command(["verilator_coverage", "--write-info", info, merged])
    if not info.is_file() or info.stat().st_size == 0:
        raise CoverageError(f"verilator_coverage did not create {info}")

    files, _ = parse_lcov(info)
    native = parse_verilator_dat(merged)
    missing = set(native) - {item.source for item in files}
    if missing:
        raise CoverageError(
            "Native coverage sources are absent from LCOV: " + ", ".join(sorted(missing))
        )

    run_command(["genhtml", info, "--output-directory", html])
    total = write_summary(info, merged, output_dir / "coverage_summary.txt", len(databases))
    return total


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, help="Directory for merged data and reports")
    parser.add_argument("databases", nargs="+", help="Verilator .dat files or glob patterns")
    args = parser.parse_args(argv)
    try:
        total = generate_report(args.databases, args.output)
    except CoverageError as error:
        parser.exit(1, f"error: {error}\n")
    summary = Path(args.output).resolve() / "coverage_summary.txt"
    print(summary.read_text(encoding="utf-8"), end="")
    print(f"HTML report: {Path(args.output).resolve() / 'html' / 'index.html'}")
    return 0 if total.lines_found else 1


if __name__ == "__main__":
    sys.exit(main())
