# Verilator Code Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce merged line/branch/toggle coverage reports for cocotb and DekatronPC system tests using the installed Verilator toolchain.

**Architecture:** Tests emit native Verilator `.dat` databases into per-run files. A single Python report driver merges them with `verilator_coverage`, writes LCOV/HTML/text artifacts and returns nonzero on missing or malformed inputs. Makefiles and the system runner only select instrumentation and unique filenames.

**Tech Stack:** Python 3 standard library, Verilator 5.034, `verilator_coverage`, LCOV/`genhtml`, GNU Make, cocotb 2.x, C++17.

**Spec:** `doc/code_coverage.md`

## Global Constraints

- Do not add `cocotb-coverage` or other Python dependencies.
- Do not alter ordinary Icarus regression behavior or add coverage overhead to ordinary system tests.
- Preserve all current uncommitted user edits, especially the added `steptest.bfk` runs in `rtl/run/run_tests.sh`.
- Do not create Git commits or other Git mutations.
- Record validation in `doc/code_coverage.md` and add one bullet to `history.md`.

## Review Focus

- Empty, missing or malformed `.dat` inputs must fail instead of publishing a misleading 100% or 0% report (Task 1, steps 1–4).
- Repeated test names must not overwrite databases (Tasks 2 and 3, integration checks).
- System coverage must be written after execution and only for instrumented builds (Task 3, steps 1–4).
- Cleaning/rebuilding `tb/sim_build` must not erase accumulated coverage databases (Task 2, integration check).
- Missing Verilator/LCOV executables must name the failed tool and return nonzero (Task 1, steps 1–4).

---

### Task 1: Coverage report driver

**Files:**
- Modify: `tb/gen_coverage.py`
- Create: `tb/tests/test_gen_coverage.py`

**Interfaces:**
- CLI: `python3 tb/gen_coverage.py --output <directory> <input.dat> [<input.dat> ...]`
- Produces: `<directory>/merged.dat`, `<directory>/coverage.info`, `<directory>/coverage_summary.txt`, `<directory>/html/index.html`.

- [x] **Step 1: Write failing pure-Python tests** for LCOV aggregation, duplicate input rejection, missing input/tool errors, and command construction. Use temporary files and mocks; do not invoke a simulator.
- [x] **Step 2: Run `python3 -m pytest tb/tests/test_gen_coverage.py -q`** and confirm failures identify the old Covered implementation.
- [x] **Step 3: Replace `tb/gen_coverage.py`** with a small subprocess driver: expand/deduplicate inputs, run `verilator_coverage --write` and `--write-info`, parse LCOV per-file summaries, call `genhtml`, propagate failures, and never swallow subprocess errors.
- [x] **Step 4: Re-run the unit tests** and confirm all pass.

### Task 2: Cocotb coverage regression

**Files:**
- Modify: `tb/Makefile`
- Modify: `tb/.gitignore`
- Modify: `tb/README.md`

**Interfaces:**
- `make -C tb coverage` emits the Task 1 artifacts under `tb/coverage-report/` from per-target `tb/coverage-report/data/<target>.dat` files.
- `make -C tb test_<name> SIM=verilator HDL_COVERAGE=1` emits one named database for an individual target.

- [x] **Step 1: Add the failing integration check** by invoking one small target with Verilator coverage and confirm the current Makefile emits no `.dat`.
- [x] **Step 2: Add coverage flags and runtime coverage filename plumbing** to the Verilator branch, keeping artifacts outside `sim_build`. Factor only the regression target execution needed to reuse it under `SIM=verilator`; retain existing test order, groups, pass/fail accounting and ordinary defaults.
- [x] **Step 3: Run two small targets** (`compare`, `impulse`) with coverage, verify distinct nonempty databases, then merge them with Task 1 and inspect real LCOV counters.
- [x] **Step 4: Run ordinary `make -C tb regression SIM=icarus`** and confirm 34/34 still pass without instrumentation.

### Task 3: System-test coverage and documentation

**Files:**
- Modify: `rtl/run/run_tests.sh`
- Modify: `rtl/tests/DekatronPC.sv/DekatronPC_tb.cpp`
- Modify: `doc/code_coverage.md`
- Modify: `history.md`

**Interfaces:**
- `VDekatronPC ... [-c <output.dat>]` writes coverage after simulation when compiled with `VM_COVERAGE`.
- `./run_tests.sh -c` runs hello/program/pi with instrumentation and creates `rtl/run/coverage/` reports; `-t -c` combines normal tests with instrumented system tests.

- [x] **Step 1: Check the failing behavior**: instrument hello with the existing code and verify the current early write has no post-run hits; identify all early exits that need a single finalization path.
- [x] **Step 2: Implement explicit `-c` output and end-of-simulation coverage writing**, preserving pass/fail status and no-trace `-n`. Generate unique paths for hello/program/pi and invoke the Task 1 reporter; do not touch the existing steptest additions.
- [x] **Step 3: Run instrumented hello and program**, confirm distinct databases and nonzero post-simulation hit counts; merge them and check the HTML/text artifacts.
- [x] **Step 4: Run the required project validation** on this ≥24-thread/≥24-GB host: `cd tb && make regression`, `./run_tests.sh -t`, `./run_tests.sh -d`, `./run_tests.sh -s`, `./synth_sim.sh`, plus the coverage target/regression as practical. Fix only coverage-related failures; report unrelated pre-existing failures separately.
- [x] **Step 5: Update usage documentation and the report** with exact commands, measured coverage, runtime costs and limitations; append one `history.md` bullet. No new requirement or OPEN item is invented without owner direction.
