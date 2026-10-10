# Delay-based dekatron model (DekatronTubeDelay)

Date: 2026-10-08. Requirements: REQ-DEK-010, REQ-DEK-012/015/016, REQ-VER-025.

## 1. What and why

`DekatronTubeV2` counts `hsClk` cycles to time every discharge move. The real
A110 has no clock: it reacts to the level on its electrodes, and each move
takes a physical time. `rtl/DekatronPC/Dekatron/DekatronTubeDelay.sv` is the
same 30-electrode ring model with the clock taken out. It has **no `hsClk`
port**, and all durations are `#N` delays in absolute time.

In the first step only the tube changed, and `hsClk` was still used by
`DekatronPhaseGen` (the three-phase split of a `Clk` cycle) and by the
`writeTimer` window in `DekatronCounter`. In the second step (§8) the same
define also switches `Impulse`, `OneShot`, `DekatronPhaseGen` and
`DekatronPulseSender` to delays, so **`DekatronCounter` works without
`hsClk`**. In the third step (§9) `RstTimeRelay` follows, and **the whole
`DekatronPC` runs with `hsClk` held at 0**.

## 2. How the model works

Every stimulus is a *request* for one discharge move. Each request type goes
through a continuous assignment with a delay:

| Channel | Request vector | Delay |
|---|---|---|
| guide  | `{guide_dir, cathodes_q}` | `GUIDE_STEP_HS * HS_NS` |
| fall   | `{fall_dir, cathodes_q}`  | `FALL_STEP_HS * HS_NS` |
| write  | `{write_en_i, write_pos_i}` | `(WRITE_MIN_HS - WR_SYNC_HS) * HS_NS` |
| reset  | `{resetN, reset0}`        | `(RESET_MIN_HS - WR_SYNC_HS) * HS_NS` |

Verilog continuous-assignment delays are **inertial**: a change of the right
side cancels the update that is still pending. So the delayed copy equals
the request only if the request held steady for the whole delay. When it
arrives and still matches, the move is applied. A pulse shorter than the
delay does nothing, which is the same rule as the timer restart in
`DekatronTubeV2`. The move table (guide A/B attraction, falling back from
guide A and forward from guide B, REQ-DEK-015) is copied unchanged.

Two details matter:

- **Discharge position is part of a move request.** Without it, the request
  "move forward" can drop for one step and come back within the delay (main
  → guide A → guide B are both forward moves). The inertial assignment would
  then cancel the pending 0 and never produce a new edge, and the second move
  would be lost. With `cathodes_q` in the vector, every step changes the
  request, so each move gets its own delay.
- **Zero-width glitches are filtered for free.** In the netlist, gates switch
  in different delta cycles, so the guide lines can glitch for zero time.
  The inertial delay ignores those glitches.

Time base: `HS_NS = 100` ns, so the existing `*_HS` estimates (OPEN-013/014)
mean the same thing at 10 MHz. The module sets `timeunit 1ns` inside its
body, so it doesn't depend on the testbench `timescale`. That block is
hidden from Yosys by `ifndef SYNTH`.

Diagnostics: conflicting write/reset lines, both guides active, and a guide
active during write/reset all raise `$error`. These checks only fire after
the condition has lasted 1 ns, so delta glitches in the netlist don't
trigger them. A guide pulse longer than `GUIDE_MAX_HS` raises `$error` too.

## 3. Selecting the model

- `` `define DEKATRON_DELAY_MODEL `` makes `DekatronModule` instantiate
  `DekatronTubeDelay` without the `hsClk` pin, in place of `DekatronTubeV2`.
  The parameters are identical, so the instance is otherwise the same.
- `DekatronTubeDelay.sv` is **not** in `DPC.files`. Verilator, Quartus and
  the tube-count synthesis never see it, and their default flow is unchanged
  (the Verilator lint of DPC.files is clean).
- `rtl/run/emul`: `DEKATRON_MODEL=delay` adds the define and the file.
  `EMUL_DEFINES` passes extra flags (e.g. `-DNO_VCD`).
- `rtl/run/run_tests.sh -d`: all Icarus tests (Dekatron, Counter, IpLine,
  ApLine, MachineCtrl, DekatronPC helloworld and program.bfk) plus **pi.bfk**
  on DekatronPC, with the delay model. Binaries and VCDs go to
  `rtl/run/delay/`.
- `rtl/run/synth_sim.sh -d`: the netlist flow with the delay model.
  `synt_dpc.tcl` has a new `-D <macro>` option. Synthesis reads DPC.files
  plus `DekatronTubeDelay.sv`, so the netlist instantiates `DekatronTubeDelay`
  as a black box, with no `hsClk` on it. Output goes to
  `rtl/run/synth_sim_delay/`.
- New `synth_sim.sh` test `Pi`: pi.bfk on the DekatronPC netlist, shared with
  the `DekatronPC` test (synthesized once per invocation). It works with or
  without `-d`, and is not in the default set because it is long.
- `DekatronPC_tb_cfg_pi.svh` now enables `TRY_PROGRAM` and sets
  `TIMEOUT 4000000` (pi takes about 3.17 M clk cycles).

## 4. Testbench change

`DekatronPC_tb.sv` ran `hsClk` at 5 MHz (`#1` with a 100 ns time unit), so
`Clk` was 500 kHz. A clocked tube doesn't care. A model in absolute time
does: at 5 MHz it would see every phase twice as long as the hardware would.
The clock is now `#0.5`: 10 MHz `hsClk`, 1 MHz `Clk`, as in every other
testbench. Simulated time is now real time. With either tube model,
helloworld finishes at 5809 µs (5810 µs after the testbench race fix, §9.1).

## 5. Results

### 5.1 RTL, Icarus

| Test | Clocked V2 | Delay model |
|---|---|---|
| Dekatron, Counter, IpLine, ApLine, MachineCtrl | pass | pass |
| DekatronPC helloworld | pass, 1.89 s | pass, 0.91 s (same 5809 µs simulated) |
| DekatronPC program.bfk | pass | pass |
| DekatronPC pi.bfk | — (Verilator only, `-t`) | pass: `3.141\n`, 3 172 830 µs simulated, 502 s wall, 15 MB |

Checked with Icarus 13 (devel) and Icarus 12.0 built from `v12_0` (the CI
image version).

Waveform check (wavepeek on `dekatron_tb.vcd`). One forward step from 0,
with `Clk` rising at 2050 ns:

```
2050 ns  guide A on                 cathodes 0x001 (main 0)
2250 ns  discharge on guide A       +200 ns = GUIDE_STEP
2350 ns  guide A off, guide B on
2550 ns  discharge on guide B       +200 ns
2650 ns  guide B off
2950 ns  discharge on main 1        +300 ns = FALL_STEP, Out = 1
3050 ns  next Clk edge              100 ns margin (3/3/4 split)
```

Write and reset inside `DekatronCounter`: each line is held 9.4 µs (window
104 hs minus one `Clk` of qualification). The discharge moves after
9.0 µs, the same 400 ns margin the clocked model has.

### 5.2 Netlist (synth_sim.sh -d)

Dekatron, Counter, IpLine, ApLine, MachineCtrl, DekatronPC_hello and
DekatronPC_program all pass. The whole set takes 50 s, synthesis included.
The DekatronPC netlist contains 5 `DekatronTubeDelay` instances (one per
`DekatronModule` parameter set), no `DekatronTubeV2`, and no `hsClk` pin on
the tube.

pi.bfk on the netlist (`synth_sim.sh -d -n Pi`): **pass**, output `3.141\n`,
3 172 831 µs simulated, 485 s wall, 32 MB: about as fast as the RTL run
(502 s; the two ran in parallel on the same machine).

The netlist run ends 1 µs (one `Clk`) after the RTL run (3 172 830 µs).
The output and the test verdict are the same. *Corrected in §9:* the cause
was a race in `DekatronPC_tb`, not the netlist. The panel keys were driven by
blocking assignments right after `@(posedge Clk)`. Since that fix, RTL and
netlist give identical cycle counts.

## 6. CI

`.github/workflows/docker-image.yml` has two new jobs:

- `sim_delay`: `run_tests.sh -d` (RTL, all Icarus tests plus pi.bfk).
- `synth_sim_delay`: `synth_sim.sh -d Dekatron Counter IpLine ApLine
  MachineCtrl DekatronPC Pi` (netlists plus pi.bfk); logs and netlists are
  uploaded as `synth-sim-delay-logs`.

## 7. Next steps

- REQ-DEK-010: done for everything inside DekatronPC (§9). The `hsClk` ports
  stay because the Emulator interface is frozen (TRS Appendix B). Under the
  define they drive nothing. The Emulator itself still runs on its own
  clocks, and its `Impulse` instances would need `HS_NS = 1000` (§8) if it
  were ever simulated with the define.
- Once timing is calibrated on hardware (OPEN-013/014), feed the measured
  times into `HS_NS`/`*_HS`. Spread or jitter can be modelled the same way:
  the delays are plain parameters.

## 8. Step 2: timing cells and phase generator without hsClk

Owner's request: no new modules. The existing ones choose their logic with
`` `ifdef DEKATRON_DELAY_MODEL `` / `` `else ``, the same define as the tube.
No port changes anywhere: the `hsClk`/`hs_clk` ports stay. The Emulator
interface is frozen, and the netlist keeps its structure. Under the define,
those ports just aren't connected to anything inside.

| Module | Clocked (default) | `DEKATRON_DELAY_MODEL` |
|---|---|---|
| `Impulse` (`rtl/Logic/Impulse.sv`) | `En & ~D_state`, `D_state <= En` on `Clk` | `D_state` is `En` through an inertial `#HS_NS` (100 ns): a pulse of one hs from the rising edge of `En`; `Clk` unused |
| `OneShot` (`rtl/Logic/OneShot.sv`) | counts `DELAY` `Clk` cycles | window of `DELAY * HS_NS` ns from the rising edge of `En`; restarts if `En` is still high at the end, as the counter does; `Rst_n` cancels it (`disable`); `Clk` unused |
| `DekatronPhaseGen` | `Impulse`/`OneShot` on `hsClk` | same `Impulse` + 2×`OneShot` + gates, their `Clk` tied to `1'b0`; overlap check on phase edges instead of `hsClk` |
| `DekatronPulseSender` | StepF&StepR check on `hsClk` | same check on `negedge Clk` |
| `DekatronCounter` | `writeStart`/`writeTimer`/`phaseGen`/modules on `hs_clk` | all of them get `tclk = 1'b0` |
| `DekatronModule` | `pulseSender.hsClk = hsClk` | `1'b0` |

`DekatronPhaseGen` stays a structure of the same cells instead of getting its
own `#` delays. That's deliberate: it is synthesized logic around black-box
timing cells, and Yosys ignores `#` delays. The netlist under the define is
the same gates, with `.Clk(1'h0)` on every `Impulse`/`OneShot`.

New parameter `HS_NS` (default 100) on `Impulse` and `OneShot`: the period
of the clock the delay model replaces. Inside DekatronPC every instance runs
on 10 MHz `hsClk`, so the default fits. The Emulator also uses `Impulse` on
its 1 µs clock (`Sequencer`, `MS6205`). Those would need `HS_NS = 1000`
under the define, but the Emulator is never simulated with it.

**Glitch filter.** In the clocked `OneShot` a zero-width glitch on `En`
(signals at a `clk` edge settling in different delta cycles, e.g.
`accept & set_any`) is never seen, because the counter samples only on `Clk`.
An edge-triggered delay model would start a spurious window from such a
glitch. The window isn't retriggerable, so a real write arriving within the
next 10.4 µs would get a shorter window, and the write would fail. `En`
therefore goes through an inertial `#0.001` (1 ps) before it can start the
window. This is a precaution: no run was made without the filter to see
such a glitch happen. The output still includes the raw `En`, as in the clocked model. All
timings shift by 1 ps.

### 8.1 Testbenches

Under the define, `Counter_tb` and `Dekatron_tb` hold `hsClk` at 0 and
generate the 1 MHz `Clk` themselves, with the phase the `ClockDivider` would
give: first rising edge 50 ns after `Rst_n`, 500/500 ns. If anything inside
`DekatronCounter`/`DekatronModule` still needed `hsClk`, these tests would
fail. IpLine/ApLine/MachineCtrl/DekatronPC testbenches still toggle `hsClk`
(DekatronPC needs it for `RstTimeRelay`). The counters inside them no longer
use it.

### 8.2 Results

| Run | Result |
|---|---|
| Dekatron, Counter (RTL, `hsClk` = 0) | pass, 257 µs / 3181 µs, the same as with `hsClk` |
| IpLine, ApLine, MachineCtrl, DekatronPC hello/program (RTL) | pass, the same simulated times as before |
| Default clocked flow: Dekatron, Counter; Verilator lint of DekatronPC and Emulator | pass, lint clean |
| `synth_sim.sh -d`, all 7 runs | pass |
| pi.bfk, RTL (`run_tests.sh -d`, Icarus 12) | pass, `3.141\n`, 3 172 830 µs simulated; whole `-d` flow 385 s (pi alone was 502 s in step 1) |
| pi.bfk, netlist (`synth_sim.sh -d -n Pi`) | pass, `3.141\n`, 3 172 831 µs simulated, 423 s (was 485 s) |

The two pi runs ran in parallel. Simulation got faster, most likely because nothing
inside the counters is evaluated on every hsClk edge any more (not profiled).

Waveforms (wavepeek on `Counter_tb.vcd`; `hsClk` has no transitions at all):

```
step of decade 0, clk rises at 12050 ns
12050.000  guide A on
12250.000  discharge on guide A           +200 ns
12350.001  guide A off, guide B on        phase 1 = 300 ns (+1 ps filter)
12550.001  discharge on guide B           +200 ns
12650.001  guide B off                    phase 2 = 300 ns
12950.001  discharge on main cathode      +300 ns fall
13050.000  next clk edge                  100 ns margin, as before

write window (set), clk rises at 3096050 ns
3096050.000  write_start 1, writing 1
3096150.000  write_start 0                Impulse = 100 ns
3106450.001  writing 0                    OneShot = 104 hs = 10.4 us
3107050.000  state ST_SET -> ST_IDLE      same edge as with hsClk
```

In the counter netlist, `hs_clk` survives only as an input port of
`DekatronCounter`/`DekatronModule`/`DekatronPhaseGen` that drives nothing.
Every `Impulse`/`OneShot` instance has `.Clk(1'h0)`.

## 9. Step 3: RstTimeRelay, whole DekatronPC without hsClk

`RstTimeRelay` (in `DekatronPC.sv`) is the time relay on the reset lines. It
holds `soft_rst`/`hard_rst` for `HOLD_HS` = 104 hsClk cycles and fires a
hard reset once at power-up. It gets the same kind of branch:

| | Clocked (default) | `DEKATRON_DELAY_MODEL` |
|---|---|---|
| start | first `hs_clk` edge with a trigger | rising edge of the trigger, through a 1 ps inertial filter |
| hold | `HOLD_HS` `hs_clk` cycles | `HOLD_HS * HS_NS` ns (10.4 µs) |
| trigger still high at the end | fires again on the next `hs_clk` edge | fires again after `HS_NS` |
| hard vs soft | latched at start, hard has priority | same |
| `rst_n` | asynchronous clear | `disable` of the hold process, clear |

New parameter `HS_NS` (default 100). `DekatronPC` has a local `tclk`: it is
`hsClk` by default and `1'b0` under the define. It feeds the relay, `IpLine`
and `ApLine`, so the `hsClk` port of DekatronPC drives nothing.
`DekatronPC_tb` under the define holds `hsClk` at 0 and generates `Clk`
itself, with the divider's phase (`rst_n` is released on an hsClk edge, and
the first `Clk` edge comes 100 ns later). The 20 hsClk edges before reset
release become `#19.5`.

### 9.1 A testbench race found on the way

With `hsClk` gone, helloworld first finished 1 µs later than before (5810
vs 5809 µs). A wavepeek comparison showed the machine leaving halt one `Clk`
later after `press_run`. `Run` (like the other panel keys and switches in
`DekatronPC_tb`) was set with a blocking assignment right after
`@(posedge Clk)`. Whether `MachineCtrl` saw it on that edge depended on
event order:

```
clocked:  43050 ns  Run=1, state 0 -> 1 in the same timestep
delay:    43000 ns  Run=1            44000 ns  state 0 -> 1
```

The keys and switches in `DekatronPC_tb` now use non-blocking assignments.
The DUT always sees them on the next edge, and both models give the same
cycle counts. The same race explains the one-cycle RTL-vs-netlist offset
in §5.2.

### 9.2 Results

| Run | Clocked | Delay, no hsClk |
|---|---|---|
| DekatronPC helloworld, RTL | 5810 µs, pass | 5810 µs, pass |
| DekatronPC program.bfk, RTL | 71362 µs, pass | 71362 µs, pass |
| DekatronPC hello/program, netlist | 5810 / 71362 µs, pass | 5810 / 71362 µs, pass |
| `synth_sim.sh -d`, all 7 runs | | pass |
| pi.bfk, RTL (`run_tests.sh -d`, Icarus 12) | | pass, `3.141\n`, 3 172 831 µs; whole `-d` flow 358 s |
| pi.bfk, netlist | | pass, `3.141\n`, 3 172 831 µs (same cycle as RTL), 393 s |
| Verilator lint, DekatronPC and Emulator | clean | |

In the delay-mode DekatronPC netlist, the `hsClk` input of `DekatronPC` is
declared and drives nothing, and `rstRelay` has `.hs_clk(1'h0)`.
