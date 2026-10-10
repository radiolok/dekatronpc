# Netlist (gate-level) simulation of the RTL tests

Date: 2026-10-07. Scope: run the Icarus tests of `rtl/run/run_tests.sh -t`
against the Yosys netlists instead of the RTL. Requirement: REQ-VER-025
(first, zero-delay step). Script: `rtl/run/synth_sim.sh`, CI job `synth_sim`.

## 1. How to run

```
cd rtl/run
./synth_sim.sh                 # all tests: synthesize, then simulate
./synth_sim.sh IpLine ApLine   # chosen tests
./synth_sim.sh -n IpLine       # reuse the netlist, simulate only
./run_tests.sh -g              # the same, from run_tests.sh
```

Tests: `Dekatron` (DekatronModule), `Counter` (DekatronCounter), `IpLine`,
`ApLine`, `MachineCtrl`, `DekatronPC` (helloworld and program.bfk on one
netlist). Output goes to `rtl/run/synth_sim/<test>/` (git-ignored):
`<top>_synth.v`, `synth.log`, `<run>_compile.log`, `<run>_sim.log`, VCD.
The exit code is the number of failed runs, and a summary is printed at the end.
Only yosys, python3 and Icarus are needed. Synthesis takes seconds per
block; the whole suite takes about 2.5 min, most of it the two
DekatronPC runs, which hit the testbench timeout.

## 2. Flow

1. **Synthesis**: `synt_dpc.tcl`, the same flow as `run_tests.sh -s` (area
   ABC script, `equiv_opt`, `qn_absorb.py`). Two new options, both off by
   default, so the tube-count flow is unchanged (IpLine rerun: 657.5 tubes,
   415 cells, same as before):
   - `-p NAME VALUE`: `chparam` on the top. Each DUT is synthesized with the
     parameters its testbench uses (e.g. IpLine `LOOP_READ=1`, MachineCtrl
     `EN_EMULATOR=1`, Counter `TOP_VALUE=12'h255`).
   - `-bb MODULE`: the module stays a black box, so its instances stay in the
     netlist **with their parameters** (`DekatronTubeV2 #(...) dekatron`).
   The file list is now read relative to the list file itself, not the
   working directory (same files as before from `rtl/run`).
2. **Prep**: `synth_sim_prep.py` checks that every liberty cell has a model
   in `rtl/vtube/vtube_cells.v`. A synthesized top has no parameters, but the
   testbench passes them, so the script declares them again in the top with the
   synthesized values. An `initial` block calls `$fatal` if the testbench passes
   a different value than the netlist was built for. This guard caught a
   real mistake while setting up: DekatronPC_tb uses `EN_EMULATOR=0`.
3. **Simulation**: Icarus, `-g2012`, the testbench files unchanged:
   testbench + netlist + `vtube_cells.v` + RTL of the black boxes +
   `parameters.sv` + `ClockDivider` (testbench clocks). Run in
   `synth_sim/<test>/`; `../firmware.hex` resolves to `synth_sim/firmware.hex`.

### Black boxes

These are behavioural models of parts that are not tube logic. Under `SYNTH`
they are empty or stubbed, so they add nothing to the tube count, and the
simulation puts their RTL back:

| Module | What it models | Under SYNTH |
|---|---|---|
| `DekatronTubeV2` | the tube | empty body |
| `OneShot`, `Impulse` | hs_clk pulse timing: phase generator, `writeTimer` window; special tube circuits (owner) | empty body |
| `RstTimeRelay` | time relay in the reset lines | empty body; RTL is extracted from `DekatronPC.sv` with awk |
| `Ram`, `IpMemory` | memory (ferrite) | stub |

Without `OneShot`/`Impulse` the netlist has undriven pulse lines
(yosys: `Wire Impulse.\Impulse is used but has no driver`), the tube never
steps and every test fails. **Owner decision (2026-10-07):** `OneShot` and
`Impulse` are special tube circuits, not standard-cell logic, so they stay black
boxes here. Like the dekatron, they are outside the ABC tube count
(`run_tests.sh -s`) and must be added to the machine's budget separately.

### Cell models

`rtl/vtube/vtube_cells.v` had drifted from `vtube_cells.lib`: old names
(`BUF_6N16B`, `NOT_6N16B`, `A1OOI_N16X7`, `A2OOI_N16X7`), no `NOR10_N16X7`,
and triggers without `QN` (which `qn_absorb.py` uses). It is rewritten one to
one with the liberty file. The models have zero delay, and flops without reset
start at X.

## 3. Results (local, Icarus 13-devel, yosys 0.51)

| Run | Result |
|---|---|
| Dekatron | PASS |
| Counter | PASS |
| IpLine | PASS |
| ApLine | PASS |
| MachineCtrl | PASS |
| DekatronPC_hello | PASS ("Hello World!\n", 14332 us; RTL 14330 us) |
| DekatronPC_program | PASS ("Hello from program.bfk!", 179736 us; RTL 179734 us) |

Sanity check: one `NAND2_J2` in the IpLine netlist swapped for `NOR2_N16`
makes IpLine fail, so the netlist really is the DUT.

The netlist runs finish 2 clocks after RTL. TX and every check match; the
offset is not investigated yet.

## 4. DekatronPC failure: analysis and fix (2026-10-07)

Before the fix both DekatronPC runs timed out: after the bootloader the
testbench saw `halted` at `IP=00000 Insn=f`, and TX gave `(0)` every 11
clocks. Method: a probe module printing MachineCtrl/IpLine/ApLine handshakes
every clock after loading, run on RTL and on the netlist and diffed, then
a VCD of `ipLine` around the divergence and a backward walk from the first
X net through the netlist drivers. There were two independent causes. Neither
is a tube-logic bug: the netlist computes the same function as the RTL.

### 4.1 X from the memory read path (simulation model)

Traces match through loading, EOT and the soft reset. At the first IP step
in BF mode (`ISA1` at IP 0) the netlist IP stays at 0, and two clocks later
`ip_ready`, MachineCtrl's state and everything after it are X. Back-trace
from the first X net in `ipLine`:

```
_083_ <- OR2  _026_ <- NOR2(_023_, _025_)
  _023_ <- OR2(_022_, insn_loading=0)  _022_ <- NOR2(loop_val_zero=x, insn_loop_close=0)
  _025_ <- NOR2(_024_, insn_loop_open=0) _024_ <- NOT(loop_val_zero=x)
```

`loop_val_zero = insn_mode ? data_zero : ap_zero`, and in BF mode
`data_zero = lock_q ? data_ctr_zero : ~|mem_rd_data` (ApLine). Right after a
reset no cell has been read (`data_zero_valid = 0`), so `data_zero` follows
the memory output register, which was X: `RamBank.rd_q` is set to 0 at
power-up under `INIT_ZERO`, but `RamGroup.digit_q` (which child drives
`rd_data`, one clock behind) had no such initial value, so
`rd_data = child_rd[digit_q]` was X until the first access.

In RTL IpLine uses the signal only as `insn_loop_open & loop_val_zero`, so
`0 & X = 0`. ABC built the same function from `loop_val_zero` and
`~loop_val_zero` on reconvergent paths, which a 4-state simulator cannot
resolve (X pessimism). The X reached IpLine's state flops and the machine
was lost. With any 0/1 value on the memory output the netlist behaves like
RTL, so real hardware is not affected.

Fix: `rtl/DekatronPC/RAM.sv`, `RamGroup` sets `digit_q`/`dbg_digit_q` to 0
under `INIT_ZERO`, in the same way as `RamBank.rd_q`. This is part of the
behavioural memory model only (`RamGroup` is outside `SYNTH` and a black box
here), so tube count and synthesis are unchanged.

### 4.2 Zero-width IsHalted pulse (testbench)

With 4.1 fixed the netlist matches the RTL trace clock for clock, but the
testbench still printed `halted` on the first instruction. An event probe
shows `IsHalted` going 0 -> 1 -> 0 in one time step on every entry into
state 4: `is_halted = (state == S_HALT)` is a decoder of the state register,
and in the netlist the state bits update in different delta cycles, so the
decoder passes through `S_HALT` for zero time (a decode hazard; a real one
too, but harmless, since every consumer samples it on a clock edge).
`@(posedge IsHalted)` and `wait (IsHalted)` in `DekatronPC_tb.sv` catch the
pulse. A VCD does not show it, because it keeps only the settled value per
time step.

Fix: `DekatronPC_tb.sv` task `wait_halted()` samples `IsHalted` on the
falling edge of `Clk` (as `read_tx` already does for `tx_vld`) and replaces
all four asynchronous waits. The other async waits look at a flop output
(`InsnInLoading`) or at the RTL time relay (`rst_busy`), which do not glitch.
The RTL runs still pass (helloworld 14330 us, program.bfk 179734 us).

## 5. CI

Job `synth_sim` in `.github/workflows/docker-image.yml`: runs
`./synth_sim.sh` in the Docker image (Icarus 12) and uploads `synth_sim/**/*.log` and the netlists as the
`synth-sim-logs` artifact. All runs passed in CI on Icarus 12, so
`continue-on-error` was removed (2026-10-07): a failing netlist run now fails
the pipeline.

## 6. Next

- REQ-VER-025 asks for liberty delays. The flow is zero-delay, so it needs
  `specify` blocks or SDF from the liberty file.
- Look into the 2-clock offset between netlist and RTL run times.
- The netlist's reconvergent X handling will hit any signal read while
  invalid. A gate-level run with random 0/1 initial values for flops without
  reset (instead of X) would find such spots without masking real ones.
