# Tube delays on the netlist: SDF annotation and setup/hold checks

Date: 2026-10-08. Related: REQ-VER-025 (netlist simulation), REQ-DEK-010
(delay model), OPEN-013/014 (timing calibration, is 1 MHz achievable).

## 1. What was built

Gate-level simulation (`synth_sim.sh -d`) used zero-delay cell models. A new
mode `-t` gives every vacuum-tube cell a real delay and checks the triggers
for setup and hold.

| File | Role |
|---|---|
| `sch/logic/vtube_cells.v` | each cell got a `specify` block with every input→output path at delay 0. Without `iverilog -gspecify` the blocks are ignored and the earlier flows behave exactly as before (checked: `-d` Dekatron, Counter, DekatronPC pass). |
| `sch/logic/vtube_timing.json` | **the only place for the numbers**: per cell, per arc (`A->Y`, `posedge C->Q`, `negedge C->Q` for the falling-edge `DFF_J2N16`, `S->Q`, …), one value or `[rise, fall]` in ns; `setuphold` for the triggers, around the edge the trigger captures on. |
| `rtl/run/vtube_sdf.py` | reads the netlist, the specify paths and the table; writes one SDF per netlist module and `vtube_sdf.sv`, a second simulation root with the `$sdf_annotate` calls, the checkers and a summary line. |
| `sch/logic/vtube_timing_check.v` | `vtube_setuphold`, a behavioural setup/hold checker (`NEGEDGE = 1` for `DFF_J2N16`, set by `vtube_sdf.py` from the specify edge). Icarus parses `$setuphold` and SDF `TIMINGCHECK` but never checks them (tested on Icarus 13). |
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
./synth_sim.sh -t -c 5000                  # Dekatron Counter DekatronPC, Clk 5 us
./synth_sim.sh -n -t -c 4500 DekatronPC    # reuse the netlist, Clk 4.5 us
./synth_sim.sh -t -o 5 -c 2500 Counter     # phase delay 500 ns (default 22 = 2.2 us)
```

A run fails if the testbench fails, if Icarus reports any SDF ERROR/WARNING,
or if the summary line does not start with `VTUBE TIMING: 0 setup, 0 hold`
(the masked count after it is information, §3.5).
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

## 3. Results at Clk = 10 us (2026-10-08, before the fixes below)

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
missed count.

**Resolved 2026-10-23 (TRS v0.11, REQ-PULSE-008).** The owner decided that the
guide pulses must touch or overlap, never leave a gap (doc/harwell_1951_review.md
§2). Phase2 is now its own OneShot started by an `Impulse` on the fall of
Phase1 (`FALL = 1`), so neither phase passes a gate inside DekatronPhaseGen and
the NOT + AND are gone. Both tube models accept the overlap while the discharge
is on a guide. Finding 3.1 (the step command arrives after Phase1) is still open. The guide pulses also arrive 300 ns late (gates of
DekatronPulseSender), which is harmless as long as both paths are equal.

### 3.3 Fix of 3.1: phase start delay, and the write window (2026-10-23)

The owner asked for the delay netlist to be fixed; option B below was taken
(REQ-PULSE-009). A gives the phases only half a period, which breaks 1 MHz in
the RTL (500 ns for 3+3+4 hsClk), and C alone doesn't help: a registered
command still settles C→Q after the edge, after the phases have started.

* `DekatronPhaseGen` got `PHASE_DELAY_HS`: one more `OneShot` from the Clk
  edge and an `Impulse` on its fall start Phase1. In hardware it is one more
  RC timing circuit. Its minimum is the worst path of the step command
  (`step_f`/`step_r`, `en_chain`) from the Clk edge, and it must also outlast
  the tail of the previous cycle's command. The RTL has zero-delay gates, so
  the default is 0 and the RTL timing is unchanged. `DekatronCounter`
  takes it from the macro `DEKATRON_PHASE_DELAY_HS`; `synth_sim.sh -o HS`
  passes it to synthesis (`synt_dpc.tcl -D NAME=VALUE` is new), and `-t`
  defaults to 22. `DekatronModule` counts it in its cycle-fit check.
* Measured paths (150 ns gates). In Counter_tb the testbench drives `valid`
  at the edge: `step_f` +450 ns. In DekatronPC the master is MachineCtrl:
  `valid` +450, `step_f` +900 ns. The longest is a step right after a
  write: the counter's `ready` returns +750 ns (C→Q + decode), ApLine raises
  `valid` only when every executor is ready (REQ-APV2-007), +1350, and
  `step_f` +1950 ns. Hence 22 hsClk = 2.2 µs.
* **Write window.** With the delay in place, Counter counted but every write
  (`set`, `set_zero`, wrap through the top) failed at Clk = 10 µs. The window
  `writeTimer` started at accept, while the write line rises only one Clk
  later, when the FSM enters ST_SET/ST_ZERO/ST_TOP: a whole period was eaten
  from the window (10 % at 1 MHz, everything at 10 µs). The window now starts
  from that state (`wr_state`, or `busy_q` in the ZERO_ONLY counters). A
  write now takes one Clk more: program.bfk in RTL 71362 → 72578 µs (+1.7 %).
  After `rst_n` the Loop and AP counters are busy for one window.

### 3.4 Timescale of the cell models

`DekatronPC_tb` has `` `timescale 100 ns / 100 ps``. The directive carries
over to the files compiled after it, and `vtube_cells.v` had none, so in the
DekatronPC run every 150 ns SDF delay became 15 µs (Counter_tb is at 1 ns and
was not affected). Symptoms: X on every control line for 15 µs after
`rst_n`, and guides held for microseconds. `vtube_cells.v` now has
`` `timescale 1ns/1ps``.

### 3.5 Triggers on asynchronous cathodes: qualified checks

`DekatronCounter` latches the cathode readings every Clk without an enable
(`zeroes_q`, `nines_q`, and `zero_q`/`at_top_q` in TOP_LIMIT_MODE; tubes
saved, see the RTL comment). A write or a reset line ends in absolute time,
and the reset relay raises its lines at any moment, so these triggers do see
D change inside their setup/hold window. Only the cycle that accepts an
operation reads them. The checker now has `QUALIFY`: a violation around edge
E is held until edge E+1 and counted only if the consumer expression is 1
there (`valid & ready` of that counter); otherwise it is counted as masked.
The list lives in `vtube_timing.json` (`"masked"`: module, regex on the Q
net, `used_when`, reason). The summary line reports
`<n> setup, <m> hold violations, <k> masked`. A real-hardware note: a tube
trigger that goes metastable here must settle within one period, which is
assumed, not measured (OPEN-013).

### 3.6 Results after the fixes (2026-10-23)

Phase delay 2.2 µs unless noted:

| Test | Clk | Result |
|---|---|---|
| Counter (`-o 5`) | 10 / 3 / 2.5 µs | PASS, 0 violations (3 masked at 3 µs) |
| Counter (`-o 5`) | 2 µs | setup violation on `nines_q` with the value used: the step no longer fits |
| Dekatron, Counter, DekatronPC hello + program | 5 µs | PASS, 0 violations, 2 masked |
| DekatronPC hello + program | 4.5 µs | PASS, 0 violations, 2 masked |
| DekatronPC hello + program | 4 µs | output correct, but 7–16 setup / 6 hold violations on used values: FAIL |

So with 150 ns per stage the machine works at a 4.5 µs period, about
220 kHz. The period is phase delay 2.2 + phases 0.6 + pulse sender and J2
0.45 + fall 0.3 µs + reading decode and setup. The phase delay is
dominated by ready → valid → step after a write, so that path is where to
shorten it. Target (owner, 2026-10-23): 250 kHz, a 4 µs period, the speed of
the ferrite memory, once the tube characteristics are measured (OPEN-014).
The zero-delay netlist runs (`synth_sim.sh`, `-d`) and all Icarus RTL tests
pass.

## 4. Fix options (as they were proposed; B taken, §3.3)

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
