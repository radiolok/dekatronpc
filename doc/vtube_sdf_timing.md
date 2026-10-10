# Tube delays on the netlist: SDF annotation and setup/hold checks

Date: 2026-10-08. Related: REQ-VER-025 (netlist simulation), REQ-DEK-010
(delay model), OPEN-013/014 (timing calibration, is 1 MHz achievable).

## 1. What was built

Gate-level simulation (`synth_sim.sh -d`) used zero-delay cell models. A new
mode `-t` gives every vacuum-tube cell a real delay and checks the triggers
for setup and hold.

| File | Role |
|---|---|
| `rtl/vtube/vtube_cells.v` | each cell got a `specify` block with every input→output path at delay 0. Without `iverilog -gspecify` the blocks are ignored and the earlier flows behave exactly as before (checked: `-d` Dekatron, Counter, DekatronPC pass). |
| `rtl/vtube/vtube_timing.json` | **the only place for the numbers**: per cell, per arc (`A->Y`, `posedge C->Q`, `S->Q`, …), one value or `[rise, fall]` in ns; `setuphold` for the triggers. |
| `rtl/run/vtube_sdf.py` | reads the netlist, the specify paths and the table; writes one SDF per netlist module and `vtube_sdf.sv`, a second simulation root with the `$sdf_annotate` calls, the checkers and a summary line. |
| `rtl/vtube/vtube_timing_check.v` | `vtube_setuphold`, a behavioural setup/hold checker. Icarus parses `$setuphold` and SDF `TIMINGCHECK` but never checks them (tested on Icarus 13). |
| `rtl/run/synth_sim.sh` | `-t` (tube delays, implies `-d`, output in `synth_sim_timing/`), `-c NS` (Clk period). |
| `Dekatron_tb`, `Counter_tb`, `DekatronPC_tb` | under `DEKATRON_DELAY_MODEL` the Clk period is `` `CLK_NS `` (default 1000 ns). |

Current values (estimates, to be replaced by SPICE and hardware numbers):

* every logic cell, every arc: 150 ns;
* DFF / DFFSR / DFFSR_n: C→Q 150 ns, S/R→Q 150 ns, setup 150 ns, hold
  150 ns (a trigger is two latches in a row: the master needs 150 ns to
  take D, and D must stay 150 ns after the edge until the slave closes it off);
* RELAY_2CO contacts: 0 ns (metal contacts, coil only from panel switches);
* LATCH: D→Q, C→Q 150 ns, no setup/hold check (not used in the netlists).

Black boxes that come back from RTL keep their own timing: the dekatron
tube, OneShot, Impulse, RstTimeRelay, Ram, IpMemory.

```
cd rtl/run
./synth_sim.sh -t -c 10000                 # Dekatron Counter DekatronPC, Clk 10 us
./synth_sim.sh -n -t -c 2000 DekatronPC    # reuse the netlist, Clk 2 us
```

A run fails if the testbench fails, if Icarus reports any SDF ERROR/WARNING,
or if the summary line is not `VTUBE TIMING: 0 setup, 0 hold violations`.
Under `-t`, files written by the simulation are capped at 2 GB (`ulimit -f`).

## 2. Icarus limits found on the way

* Icarus cannot find an escaped instance name with `.` or `[` in an SDF
  path, with or without SDF escaping (`\dek\[0\]\.dModule`), and it has no
  `(INSTANCE *)`. Yosys writes such names for every generate block.
  Workaround: each SDF is relative to one netlist module and is applied to
  every instance of it with `$sdf_annotate(file, <hierarchical scope>)`;
  Verilog hierarchical names reach any scope. A cell that has such a name
  itself (the relays `\g_rel[0].g_one.rel`) gets `cell_<TYPE>.sdf` with an
  empty `(INSTANCE)`, applied to the cell's own scope.
* Module-path delays in Icarus are inertial: a 50 ns pulse on a 150 ns
  path is dropped, a 200 ns pulse passes. That matches a tube stage that
  cannot pass a pulse shorter than its own switching time.
* `$sdf_annotate` from a separate root (`-s vtube_sdf`) works, so the
  testbenches don't need to change.

DekatronPC netlist: 1047 cells, 48 annotated scopes, 81 triggers checked.

## 3. Results at Clk = 10 us

| Test | Result |
|---|---|
| Dekatron (DekatronModule alone) | PASS, 0 violations |
| Counter (DekatronCounter, 3 digits) | **FAIL**: `out` stays 000, 513 errors; 0 setup/hold violations |
| DekatronPC | not run: it has the same counters, see below |

At Clk = 1 us Counter also failed, and its VCD grew past 7.6 GB before the
run was stopped (at 10 us the same test writes 2 MB). Something rings at
1 us; not analysed, since the failure below comes first.

### 3.1 Why Counter never counts (wavepeek on `Counter_tb.vcd`)

Increment request, Clk edge at 22.05 us:

| time after the edge | event |
|---|---|
| 0 | Clk ↑, `phase1` ↑ (OneShot window, a black box, no delay) |
| 300 ns | `phase1` ↓ (end of the 3 × 100 ns window) |
| 300 ns | `step_f` ↑ = trigger C→Q 150 ns + one gate 150 ns |
| 450 ns | `phase2` ↑ |
| 900 ns | `phase2` ↓ |

The guide A pulse is `phase1 & step_f`, and the two never overlap: the
window has closed by the time the step command arrives. Only phase2 reaches
the tube, so it never moves. **A slower clock does not help**: the phase
windows are measured in absolute time from the Clk edge (PHASE1/PHASE2 ×
100 ns), while the command always arrives ≥ 300 ns after that edge. A
faster clock doesn't help either. So there is no frequency at which the
counter works; the problem is the alignment of the phases, not the period.

The Dekatron test passes only because its testbench drives `StepF` itself
at the clock edge, with no trigger and no gate in front of the tube.

### 3.2 Second finding: gap between the guide pulses

Inside DekatronPhaseGen, Phase1 comes straight from the OneShot, while
Phase2 = `Win12 & ~Win1` passes through two tube gates (NOT + AND). With
150 ns per gate, Phase2 begins 150 ns after Phase1 ends (single-dekatron
trace: guide A 2.35–2.65 us, guide B 2.80–3.25 us). In that gap no guide
holds the discharge, so it can fall back from guide A to the main cathode
(REQ-DEK-012). The delay tube model let it pass here, but physically it is a
missed count. The guide pulses also arrive 300 ns late (gates of
DekatronPulseSender), which is harmless as long as both paths are equal.

## 4. Fix options (owner decision; nothing changed in RTL yet)

For 3.1, the phases must start after the step command has settled:

* **A. Phases from the falling edge of Clk.** The command settles during
  Clk high (≥ C→Q + logic depth × 150 ns); DekatronPhaseGen starts on Clk ↓.
  Period ≥ 2 × max(command path, phase sequence 1000 ns). The simplest fix
  and easy to reason about; it halves the usable clock unless the duty
  cycle is skewed.
* **B. Fixed offset.** A third OneShot delays the phase start by T_cmd
  after Clk ↑ (T_cmd ≥ worst command path). Period ≥ T_cmd + 1000 ns.
* **C. Pipeline the command.** Register step_f/step_r and use them in the
  next cycle. This changes ready/valid timing in DekatronCounter (a step
  then takes two cycles).

For 3.2: make the phase generator a special pulse circuit like OneShot (a
black box, outside the ABC tube count), or derive Phase2 from its own
OneShot so that both phases pass the same number of gates.

Only after this is fixed does a frequency search make sense. The plan is
then: Counter and DekatronPC at 10 us, then shorter periods with `-c`,
until the first setup/hold violation or functional failure; the critical
path then comes from the checker messages and wavepeek.
