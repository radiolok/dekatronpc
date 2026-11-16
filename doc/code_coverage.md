# Code coverage for cocotb and DekatronPC system tests

Date: 2026-11-15. Status: implemented; project-wide validation recorded below.

## 1. Intent and existing state

The owner needs an aggregate RTL code-coverage metric for the cocotb/“UVM” tests and the C++/Verilator system tests. The existing `tb/gen_coverage.py` expects the unavailable Covered tool and a `COVERAGE=1` flow that `tb/Makefile` does not implement. `rtl/run/run_tests.sh` has Verilator instrumentation commented out; `DekatronPC_tb.cpp` attempts to write the database before simulation, when its counters are empty.

An FST/VCD can provide netlist toggle activity, but does not retain a reliable mapping from executed behavior to SystemVerilog source lines and branches. Native simulator instrumentation is therefore the primary metric.

## 2. Approved design

- `make -C tb coverage` runs the existing regression under Verilator with coverage instrumentation. Each target writes `tb/coverage-report/data/<test>.dat`; ordinary regression remains Icarus and has no coverage overhead.
- `cd rtl/run && ./run_tests.sh -c` runs the three system programs with instrumentation and writes one database per program. `-t -c` uses the same instrumented system-test path. Ordinary tests remain unchanged.
- `tb/gen_coverage.py` replaces the non-working Covered frontend with a report driver around `verilator_coverage`, `lcov` and `genhtml`, all already installed. It merges databases, produces LCOV and HTML reports and prints a text summary. No new Python packages are required.
- Line/branch coverage measures execution of instrumented RTL. Toggle coverage measures instrumented signal transitions; the report keeps these metrics distinct where the installed Verilator/LCOV format exposes them.
- The system-test C++ wrapper writes coverage only after simulation. Each run has an explicit output path, so programs cannot overwrite one another.

## 3. Approaches considered

1. **Native Verilator coverage — chosen.** Source-linked line/branch and toggle reports, no waveform files, uses the existing system-test simulator.
2. Python FST/VCD analysis — useful later as a separate gate-level toggle metric, but cannot replace RTL line/branch coverage and large system traces are costly.
3. Covered — would add an unmaintained integration and another SystemVerilog parser without a demonstrated benefit.

## 4. Usage

From the repository root:

```bash
source ~/.venvs/dekatronpc/bin/activate
make -C tb coverage
cd rtl/run && ./run_tests.sh -c
make -C tb coverage-all
```

The first command runs the existing cocotb targets under Verilator and merges `tb/coverage-report/data/*.dat` into `tb/coverage-report/{merged.dat,coverage.info,coverage_summary.txt,html/index.html}`. The second runs hello/program/pi with instrumentation and produces the same artifact set under `rtl/run/coverage/`. `-t -c` instruments the system runs already made by `-t` instead of running them twice. `-d -c` is rejected because the delay-model flow has no Verilator coverage instrumentation.

Use `make -C tb coverage-all` instead of running the first two commands separately when one aggregate report is wanted; it re-runs both suites and merges their databases into the root `coverage-all/` directory. Four tests are skipped in the Verilator coverage run only. `test_insn_decoder` exercises the deprecated `InsnDecoder` with Icarus delta-cycle assumptions and fails 31/35 tests on Verilator independently of coverage. `test_ms6205` is the known soft emulator test whose HEX images are not found from the cocotb working directory; Verilator 5.034 then segfaults in its second test. `test_keyboard` and `test_sequencer` complete their checks, but Verilator 5.034 segfaults after `$finish`; cocotb ignores that post-test status and would report PASS. All four remain part of ordinary Icarus regression.

One cocotb target can be run directly:

```bash
cd tb
make test_compare SIM=verilator VLT_MIN=5.034 HDL_COVERAGE=1
python3 gen_coverage.py --output coverage-report 'coverage-report/data/*.dat'
```

`VLT_MIN=5.034` is required because cocotb 2.1 nominally declares 5.036, while the project and CI use 5.034. The complete coverage regression is the compatibility check. `HDL_COVERAGE`, not `COVERAGE`, selects RTL instrumentation: cocotb reserves `COVERAGE` for Python code coverage. No new Python package, `cocotb-coverage`, Covered, or waveform database is needed.

## 5. Implementation

| File | Role |
|---|---|
| `tb/gen_coverage.py` | Validates/expands `.dat` inputs, rejects duplicates and empty inputs, invokes `verilator_coverage --write/--write-info` and `genhtml`, parses LCOV and native records, writes the text summary. |
| `tb/tests/test_gen_coverage.py` | Sixteen unit tests for aggregation, malformed/native `.dat` and LCOV inputs, missing/unmatched/empty/duplicate paths, tool failures and absent artifacts, command wiring, native DA counts and native branch/toggle classification. |
| `tb/Makefile` | Adds per-target databases outside `sim_build`, propagates `SIM_ARGS`, and provides `make coverage` / `make coverage-all`; the pre-existing test-pass table is now labelled “Pass rate” rather than “Coverage”. |
| `rtl/tests/DekatronPC.sv/DekatronPC_tb.cpp` | Adds `-c <file>` and writes coverage after simulation on every post-start exit; removes the old pre-simulation `SIM_COV` write. |
| `rtl/run/run_tests.sh` | Enables `--coverage` only for `-c`, names databases by program, runs hello/program/pi when `-c` is used alone, then invokes the shared report driver. |

Verilator 5.034 LCOV has two non-obvious properties, both covered by tests. It emits `DA` records but no `LF/LH`, so line counts are derived from `DA`. Its `BRDA` records also include toggle and expression points, so the text report takes branch and toggle counters independently from the merged native `.dat` pages `v_branch` and `v_toggle`. HTML/LCOV line data retains Verilator's own definition (every source line with a hit coverage point, including toggle/expression points), which is broader than a pure executable-statement count.

## 6. Measured results

Report-driver fixture test and real merge:

- Two real target databases (`compare`, `impulse`) merge to 17/17 lines, 2/2 branches, 18/18 toggles.
- Separate runs retain different values, and rebuilding `sim_build` does not erase the accumulated databases.
- The full cocotb coverage regression reports 30/30 executed targets passing after the four documented skips and merges all 30 databases: **line 1306/1395 (93.6%), branch 140/172 (81.4%), toggle 1771/3297 (53.7%)**.
- Full UVM coverage is not simply the ordinary Icarus result: the first run exposed Icarus-only multi-root flags on `dek_counter` (now conditional on `SIM=icarus`) and the four test-incompatibility skips described above. Every executed target produced native Verilator data.

System programs, each measured alone and then merged:

| Run | Line | Branch | Toggle |
|---|---:|---:|---:|
| `helloworld.bfk` | 887/1028 (86.3%) | 142/184 (77.2%) | 1838/2881 (63.8%) |
| `program.bfk` | 894/1028 (87.0%) | 143/184 (77.7%) | 1890/2881 (65.6%) |
| `pi.bfk` | 891/1028 (86.7%) | 143/184 (77.7%) | 1933/2881 (67.1%) |
| **merged** | **894/1028 (87.0%)** | **143/184 (77.7%)** | **1938/2881 (67.3%)** |

`pi.bfk` itself takes 170.5 s with coverage (6.2x simulated-time slowdown in the run report), versus about 22 s without instrumentation. All three programs still match the golden model; program output remains correct. The weakest covered system blocks by category include `DekatronTubeV2.sv` toggle 184/624 (29.5%) and `RAM.sv` toggle 472/702 (67.2%). `ApLine.sv` reaches 93/106 lines and 139/158 toggles; `IpLine.sv` 154/179 and 148/165; `MachineCtrl.sv` 128/160 and 98/135.

The aggregate `coverage-all` merge of 33 databases (30 nonempty cocotb targets plus three system programs) gives **line 1796/1960 (91.6%), branch 283/356 (79.5%), toggle 3709/6178 (60.0%)**. Source paths are canonical absolute paths; the RTL shared by both suites appears once (`DekatronTubeV2.sv`, for example, combines to 304/936 toggles rather than two separate entries). `tb/tests/*_wrapper.sv` and generated `firmware.sv` remain in the per-source denominator and are visible in the report.

## 7. Limits

- This is structural RTL coverage, not functional scenario coverage. It does not satisfy REQ-VER-026's functional test plan or replace assertions/scoreboards.
- Coverage is only as strong as the tests. The known missing cocotb ApLine/IpLine/MachineCtrl tests remain test gaps; a high percentage does not make untested behavior verified.
- Analog-delay netlist coverage, SPICE models, and FPGA-only emulator layers are outside the flow. FST toggle analysis may later complement gate-level runs, but it cannot provide source-linked line/branch coverage.
- LCOV “line” percentages are Verilator's source-line view and include non-statement points; compare line, branch and toggle trends rather than treating one percentage as a universal quality score.
- The native `.dat` format is Verilator-version-specific. The parser validates records and fails on unknown/malformed input; revisiting it is required after a Verilator format change.
- UVM reports include any test wrapper RTL supplied to Verilator, with those paths visible in the per-source table.
- `keyboard`, `sequencer`, `ms6205` and the obsolete `insn_decoder` have no Verilator coverage data and are excluded from that run; their ordinary Icarus tests still execute. The Verilator 5.034 post-test segfaults are a simulator/test integration issue, not a coverage parser failure.

## 8. Validation (2026-11-15)

- Report driver: `16 passed` (`cd tb && python -m pytest tests/test_gen_coverage.py -q`).
- Ordinary cocotb regression: **34/34 PASS** under Icarus, including the four targets skipped only by Verilator coverage.
- Coverage regression: **30/30 executed PASS**, 30 nonempty databases, merged HTML/LCOV/text artifacts created.
- System coverage: hello, program and pi all PASS golden-model comparison; three databases and a merged report created. `-c` alone and the `-t`/`-d` runs were exercised.
- Required project suite after the change: `./run_tests.sh -t` PASS, `./run_tests.sh -d` PASS, `./run_tests.sh -s` PASS (**921 tubes + 12 A110 = 933**), `./synth_sim.sh` **8/8 PASS**.
- The final ordinary regression was re-run after the last Makefile changes; all 34 targets passed. Shell syntax, `py_compile`, unit tests and `git diff --check` also pass.
