# Delay-based dekatron model (DekatronTubeDelay)

Date: 2026-10-08. Requirements: REQ-DEK-010, REQ-DEK-012/015/016, REQ-VER-025.

## 1. What and why

`DekatronTubeV2` counts `hsClk` cycles to time every discharge move. The real
A110 has no clock: it reacts to the level on its electrodes, and each move
takes a physical time. `rtl/DekatronPC/Dekatron/DekatronTubeDelay.sv` is the
same 30-electrode ring model with the clock taken out. It has **no `hsClk`
port**, and all durations are `#N` delays in absolute time.

The rest of the dekatron stack is unchanged. `hsClk` is still used by
`DekatronPhaseGen` (the three-phase split of a `Clk` cycle) and by the
`writeTimer` window in `DekatronCounter`. Those stand in for RC circuits and
the time relay, and replacing them is the next step of REQ-DEK-010.

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
helloworld finishes at 5809 µs.

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
The output and the test verdict are the same. The likely cause is a
one-cycle difference in when the netlist leaves power-up reset (the
`RstTimeRelay` black box against the synthesized `MachineCtrl`). It was not
investigated further.

## 6. CI

`.github/workflows/docker-image.yml` has two new jobs:

- `sim_delay`: `run_tests.sh -d` (RTL, all Icarus tests plus pi.bfk).
- `synth_sim_delay`: `synth_sim.sh -d Dekatron Counter IpLine ApLine
  MachineCtrl DekatronPC Pi` (netlists plus pi.bfk); logs and netlists are
  uploaded as `synth-sim-delay-logs`.

## 7. Next steps

- REQ-DEK-010 continued: give `DekatronPhaseGen` (`OneShot`/`Impulse`) and the
  `writeTimer` window the same treatment, so the `hsClk` wire disappears from
  the netlist completely.
- Once timing is calibrated on hardware (OPEN-013/014), feed the measured
  times into `HS_NS`/`*_HS`. Spread or jitter can be modelled the same way:
  the delays are plain parameters.
