"""Unit tests for the native-Verilator coverage report driver."""

import subprocess

import pytest

import gen_coverage


SAMPLE_LCOV = """TN:
SF:/rtl/A.sv
DA:10,1
DA:11,0
LF:2
LH:1
BRDA:10,0,0,3
BRDA:10,0,1,0
BRF:2
BRH:1
end_of_record
TN:
SF:/rtl/B.sv
LF:4
LH:3
end_of_record
"""

SAMPLE_VERILATOR_DAT = (
    b"# SystemC::Coverage-3\n"
    b"C '\x01f\x02/rtl/A.sv\x01l\x021\x01page\x02v_toggle/A' 2\n"
    b"C '\x01f\x02/rtl/A.sv\x01l\x022\x01page\x02v_toggle/A' 0\n"
    b"C '\x01f\x02/rtl/A.sv\x01l\x023\x01page\x02v_line/A' 7\n"
    b"C '\x01f\x02/rtl/A.sv\x01l\x024\x01page\x02v_branch/A' 3\n"
    b"C '\x01f\x02/rtl/A.sv\x01l\x024\x01page\x02v_branch/A' 0\n"
)


def test_parse_lcov_reports_per_file_and_total_counts(tmp_path):
    info = tmp_path / "coverage.info"
    info.write_text(SAMPLE_LCOV)

    files, total = gen_coverage.parse_lcov(info)

    assert [(item.source, item.lines_hit, item.lines_found) for item in files] == [
        ("/rtl/A.sv", 1, 2),
        ("/rtl/B.sv", 3, 4),
    ]
    assert (total.lines_hit, total.lines_found) == (4, 6)
    assert (total.branches_hit, total.branches_found) == (1, 2)


@pytest.mark.parametrize(
    "text,message",
    [
        ("SF:/rtl/A.sv\nDA:10,1\n", "no end_of_record"),
        ("end_of_record\n", "no SF record"),
        ("SF:/rtl/A.sv\nDA:ten,1\nend_of_record\n", "Invalid LCOV counter"),
        ("SF:/rtl/A.sv\nBRDA:10,0,0,1,extra\nend_of_record\n", "Invalid LCOV counter"),
        ("TN:\n", "no source records"),
    ],
)
def test_parse_lcov_rejects_malformed_tracefiles(tmp_path, text, message):
    info = tmp_path / "bad.info"
    info.write_text(text)

    with pytest.raises(gen_coverage.CoverageError, match=message):
        gen_coverage.parse_lcov(info)


def test_parse_lcov_derives_counts_from_da_records(tmp_path):
    info = tmp_path / "native.info"
    native_text = SAMPLE_LCOV.replace("LF:2\n", "").replace("LH:1\n", "")
    native_text = native_text.replace("LF:4\n", "").replace("LH:3\n", "")
    info.write_text(native_text)

    files, total = gen_coverage.parse_lcov(info)

    assert [(item.lines_hit, item.lines_found) for item in files] == [(1, 2), (0, 0)]
    assert (total.lines_hit, total.lines_found) == (1, 2)


def test_parse_verilator_dat_separates_branch_and_toggle_points(tmp_path):
    database = tmp_path / "merged.dat"
    database.write_bytes(SAMPLE_VERILATOR_DAT)

    counts = gen_coverage.parse_verilator_dat(database)

    assert (counts["/rtl/A.sv"].toggles_hit, counts["/rtl/A.sv"].toggles_found) == (1, 2)
    assert (counts["/rtl/A.sv"].branches_hit, counts["/rtl/A.sv"].branches_found) == (1, 2)


def test_resolve_databases_rejects_duplicate_paths(tmp_path):
    database = tmp_path / "one.dat"
    database.write_text("coverage")

    with pytest.raises(gen_coverage.CoverageError, match="Duplicate coverage input"):
        gen_coverage.resolve_databases([str(database), str(database.resolve())])


def test_resolve_databases_rejects_empty_and_unmatched_patterns(tmp_path):
    database = tmp_path / "one.dat"
    database.write_bytes(SAMPLE_VERILATOR_DAT)

    with pytest.raises(gen_coverage.CoverageError, match="No coverage databases"):
        gen_coverage.resolve_databases([])

    with pytest.raises(gen_coverage.CoverageError, match="did not match"):
        gen_coverage.resolve_databases([str(tmp_path / "missing-*.dat")])

    with pytest.raises(gen_coverage.CoverageError, match="did not match"):
        gen_coverage.resolve_databases([str(database), str(tmp_path / "missing.dat")])

    empty = tmp_path / "empty.dat"
    empty.touch()
    with pytest.raises(gen_coverage.CoverageError, match="missing or empty"):
        gen_coverage.resolve_databases([str(empty)])


def test_parse_verilator_dat_rejects_garbage_truncated_and_empty_points(tmp_path):
    database = tmp_path / "bad.dat"
    database.write_bytes(SAMPLE_VERILATOR_DAT + b"GARBAGE\n")
    with pytest.raises(gen_coverage.CoverageError, match="Invalid Verilator coverage record"):
        gen_coverage.parse_verilator_dat(database)

    database.write_bytes(SAMPLE_VERILATOR_DAT + b"C 'truncated")
    with pytest.raises(gen_coverage.CoverageError, match="Invalid Verilator coverage record"):
        gen_coverage.parse_verilator_dat(database)

    database.write_bytes(b"# SystemC::Coverage-3\n")
    with pytest.raises(gen_coverage.CoverageError, match="no coverage points"):
        gen_coverage.parse_verilator_dat(database)


def test_generate_report_validates_native_inputs_before_tools(tmp_path, monkeypatch):
    database = tmp_path / "bad.dat"
    database.write_bytes(b"C 'truncated")
    output = tmp_path / "report"

    def unexpected_run(*args, **kwargs):
        raise AssertionError("external tool ran before input validation")

    monkeypatch.setattr(gen_coverage.subprocess, "run", unexpected_run)

    with pytest.raises(gen_coverage.CoverageError, match="Invalid Verilator coverage record"):
        gen_coverage.generate_report([database], output)
    assert not (output / "merged.dat").exists()


def test_generate_report_rejects_tool_success_without_artifact(tmp_path, monkeypatch):
    database = tmp_path / "one.dat"
    database.write_bytes(SAMPLE_VERILATOR_DAT)
    output = tmp_path / "report"

    def fake_run(command, check, capture_output, text):
        return subprocess.CompletedProcess(command, 0, "", "")

    monkeypatch.setattr(gen_coverage.subprocess, "run", fake_run)

    with pytest.raises(gen_coverage.CoverageError, match="did not create"):
        gen_coverage.generate_report([database], output)


def test_missing_tool_has_actionable_error():
    with pytest.raises(gen_coverage.CoverageError, match="tool not found: definitely-no-such-tool"):
        gen_coverage.run_command(["definitely-no-such-tool"])


def test_failed_tool_reports_stderr():
    with pytest.raises(gen_coverage.CoverageError, match="bad coverage input"):
        gen_coverage.run_command(
            ["python3", "-c", "import sys; sys.stderr.write('bad coverage input\\n'); sys.exit(3)"]
        )


def test_generate_report_runs_merge_info_and_html_tools(tmp_path, monkeypatch):
    database = tmp_path / "one.dat"
    database.write_bytes(SAMPLE_VERILATOR_DAT)
    output = tmp_path / "report"
    commands = []

    def fake_run(command, check, capture_output, text):
        commands.append(command)
        if "--write" in command:
            (output / "merged.dat").write_bytes(SAMPLE_VERILATOR_DAT)
        if "--write-info" in command:
            (output / "coverage.info").write_text(SAMPLE_LCOV)
        if command[0] == "genhtml":
            html = output / "html"
            html.mkdir(parents=True, exist_ok=True)
            (html / "index.html").write_text("report")
        return subprocess.CompletedProcess(command, 0, "", "")

    monkeypatch.setattr(gen_coverage.subprocess, "run", fake_run)

    total = gen_coverage.generate_report([database], output)

    assert commands[0] == [
        "verilator_coverage",
        "--write",
        str(output / "merged.dat"),
        str(database.resolve()),
    ]
    assert commands[1][:2] == ["verilator_coverage", "--write-info"]
    assert commands[2] == [
        "genhtml",
        str(output / "coverage.info"),
        "--output-directory",
        str(output / "html"),
    ]
    assert (total.lines_hit, total.lines_found) == (4, 6)
    assert (total.toggles_hit, total.toggles_found) == (1, 2)
    assert "Overall line coverage: 4/6 (66.7%)" in (output / "coverage_summary.txt").read_text()
    assert "Overall toggle coverage: 1/2 (50.0%)" in (output / "coverage_summary.txt").read_text()
    assert (output / "html" / "index.html").is_file()
