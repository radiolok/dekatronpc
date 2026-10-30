# Static timing analysis of the tube netlist

Date: 2026-10-30. Related: OPEN-014 (is the clock achievable), OPEN-013
(dekatron timing), REQ-PULSE-009 (phase start delay), REQ-VER-025 (timing of
the netlist), REQ-MOD-004 (cell delays).

The question was whether the designed cells can run the machine at 100 kHz
or faster. **Not as the RTL stands: the guide phases of 300 ns (3 hsClk) are
shorter than the switching time of the NAND2_J2 gates in
`DekatronPulseSender` (345–545 ns), so the guide pulse never reaches the
dekatron and the counters do not count at any clock** (§6, found by the
netlist simulation and then added to the STA). With phases of 600 ns
(6 hsClk) and the phase start delay raised to fit the step command:

| Load model | Phase delay | Minimum period | 100 kHz |
|---|---|---|---|
| fanout tables (real load of each net) | 33 hsClk | 8.54 µs, 117 kHz | meets, 1.5 µs slack |
| fanout 6 on every net (what the SDF of `synth_sim.sh -t` uses) | 48 hsClk | 12.5 µs, 80 kHz | fails |

So 100 kHz is reachable only if the real nets are as light as the netlist
says (median 1.7 grids) and the phases are widened (owner's decision,
OPEN-013). 250 kHz and 1 MHz are out of reach with this netlist: the limit is
the logic depth, two combinational chains of 13–16 stages each.

## 1. What was built

| File | Role |
|---|---|
| `sch/logic/vtube_timing.json` | new per-cell `fanout` ratios: each arc at fanout 2 / 6 / 10 grids against its fanout-6 value, rise and fall, from the fanout tables of the cell pages. The numbers still live only here. |
| `rtl/run/vtube_liberty.py` | builds `sch/logic/vtube_cells_timing.lib` from `vtube_cells.lib` + `vtube_timing.json`: NLDM tables (`cell_rise`/`cell_fall` over 2 / 6 / 10 grids), `timing_sense` from the pin function, `falling_edge` C→Q arcs, `setup_falling`/`hold_falling` on D, `clear`/`preset` arcs. Also the liberty parser for the STA. |
| `sch/logic/vtube_cells_timing.lib` | **generated**, do not edit. Readable by Yosys (checked) and meant for OpenSTA too. Synthesis still reads `vtube_cells.lib`, so the ABC mapping and the tube count do not change. |
| `rtl/run/vtube_sta.py` | the STA itself (§2). |
| `rtl/run/vtube_sta.sh` | synthesis as in `synth_sim.sh -t`, flatten through the board boundaries, liberty, STA; report in `rtl/run/sta/DekatronPC_sta.md`. About 20 s. |

```
cd rtl/run
./vtube_sta.sh                        # synthesize, analyse
./vtube_sta.sh -n -- -p 33            # reuse the netlist, phase delay 33 hsClk
./vtube_sta.sh -n -- --derate 1.3     # every cell 30 % slower than SPICE
```

OpenSTA is not installed here (the apt package needs root), so the analysis
is a small Python engine. The liberty is standard, so OpenSTA can be used on
it later; the phase generators and the dekatron then need SDC (generated
clocks for the phases, multicycle paths for the cathodes).

### 1.1 Load model

The load of a net is the sum of its sink pins in triode grids. A pin's weight
is its divider capacitance C1 over the triode's 3.9 pF (the C1 rule of
`doc/cell_design_method.md` §2): pentode g3 6.8 pF = 1.74, follower 2.7 pF =
0.69, DFF C 17.5 pF = 4.5, DFF D 1.7. That matches the SPICE sweeps, where
"fanout N" means N triode grids (`tools/spice/latch_sweep.py: loads`).

The liberty `fanout_load` of the 2.7 pF and 6.8 pF inputs (pentode g1 / g3 of
`NAND2_J2`, `A1OOI_N16J2`, `A2OOI_J2`, the follower grids) was the default 1.0;
the owner had it set by the same rule (2026-10-30): 14 pins, now 0.69 / 1.74.
`vtube_liberty.py` stops if `fanout_load` and `vtube_c1` disagree. ABC does not
read `fanout_load`: the netlist is identical bit for bit.

Below fanout 2 the table is not extrapolated: the fanout-2 value is used
(the median net drives 1.7 grids, so this matters). Above 10 it is
extrapolated linearly; 13 nets are there, 7 of them clock nets (§3.4).

Where a page gives only fanout 2 and 10, the fanout-6 point of the ratio is
their mean. The cells without data (the flip-flops) are flat.

## 2. How the analysis works

Times are from the rising edge of `Clk` at the port. Late and early arrivals
are kept per edge and per signal class:

| Class | What | Source |
|---|---|---|
| clk | the clock inverters, the phase generators | `Clk` port; `Impulse` (one hsClk from the rise of En, or the fall if `FALL`), `OneShot` (window of `DELAY` hsClk from the rise of En) |
| data | launched at a clock edge | trigger C↓ + C→Q; memory outputs at the edge (ideal) |
| tube | dekatron main cathodes | end of the guide pulse at the tube + `FALL_STEP_HS` |
| async (not timed) | reset relay, panel, `rst_n`, relay coils, the write window | `OneShot`/`Impulse` started by data |

Checks:

* **setup** at each trigger D: `late + setup ≤ T + clock at C`; at memory inputs `late ≤ T`.
* **hold** at each trigger D: `early ≥ clock at C + hold`.
* **gating**: a cell where a clk pulse meets data (the step command meets a
  phase in `DekatronPulseSender`, the carry meets a guide in `GUIDE_EN_J2`):
  data must settle before the pulse starts and hold until it ends.
* **tube class**: a reading is valid at the next Clk edge (DekatronCounter:
  "after a step `out` is valid at the next clk edge"). So a tube path that
  ends at a trigger is a normal setup check, and one that ends at a step
  command is due before the phase of the next cycle: `late − T ≤ phase start`.

The phase start delay is a parameter of the netlist (`OneShot` of
`g_delay`). The tool first reports the netlist as synthesized (22 hsClk),
then sets the delay to the smallest value at which every step command
settles before its phase and repeats the analysis.

## 3. Results (SPICE delays, fanout tables)

### 3.1 Summary

| Constraint | 22 hsClk (as now) | 33 hsClk (fitted) |
|---|---|---|
| trigger → trigger / memory | 5354 ns | 5354 ns |
| cathodes → trigger | 6843 ns | **7943 ns** |
| cathodes → step command of the next cycle | 3121 ns | 3121 ns |
| step command held to the end of its guide pulse | 2733 ns | 3833 ns |
| step command before the phase, slack | **−1041 ns** | +59 ns |
| **minimum period** | — (counters miss steps) | **7943 ns = 126 kHz** |

| Clk | 100 kHz | 125 kHz | 150 kHz | 250 kHz | 1 MHz |
|---|---|---|---|---|---|
| slack at 33 hsClk | +2057 ns | +57 ns | −1276 ns | −3943 ns | −6943 ns |

The netlist as synthesized, with the phase delay of 2.2 µs chosen for
150 ns gates (`doc/vtube_sdf_timing.md` §3.3), does not work at any clock:
the step command of the data counter arrives 1.0 µs after its phase starts,
the failure of §3.1 of that report again. **The phase delay must become
33 hsClk (3.3 µs)**; `synth_sim.sh -t` still defaults to 22.

Sensitivity (the delay is fitted each time):

| Cell delays | Phase delay | Minimum period |
|---|---|---|
| SPICE, fanout tables | 33 | 7.94 µs, 126 kHz |
| × 1.2 | 39 | 9.29 µs, 108 kHz |
| × 1.3 | 43 | 10.07 µs, 99 kHz |
| × 1.4 | 46 | 10.74 µs, 93 kHz |
| SPICE at fanout 6 everywhere, no tables | 48 | 11.9 µs, 84 kHz |

So 100 kHz holds while the real cells are no more than ~28 % slower than the
SPICE models. The last row shows why the load model matters: most nets drive
1–2 grids, and their arcs are 30–60 % faster than at fanout 6.

### 3.2 Where the period goes

The worst path, data counter step → `ipLine` trigger (in ns from the edge):

| Segment | ns |
|---|---|
| phase start delay | 3300 |
| guide A + guide B | 600 |
| `DekatronPulseSender` (NAND2_J2 + NOR) and `GUIDE_EN_J2` after guide B ends | 684 |
| discharge falls onto the main cathode (`FALL_STEP_HS`) | 300 |
| cathodes → `data_zero` (counter decode, ApLine) | 725 |
| `data_zero` → `loop_val_zero` (MachineCtrl) | 460 |
| `loop_val_zero` → IpLine trigger D, 9 stages | 1813 |
| setup 310 − clock at C 250 | 60 |
| **total** | **7943** |

And the step command path that sets the phase delay (data launched at the
edge, 14 stages):

`Clk` → data_counter clock inverter (204) → `state[0]` C→Q (796) → `timer_req`
→ counter `ready` (1736) → ApLine → `data_counter.valid` (2477) → step logic
→ `StepF` (3241 ns), against the phase at 3300.

The trigger-to-trigger paths alone need 5.35 µs (ApLine `ready` → MachineCtrl
→ `ipLine.valid` → IpLine, 24 stages). Every heavy path runs through the
handshake chain `ready → valid` between the blocks: REQ-APV2-007 makes
ApLine raise `valid` only when every executor is ready, combinationally.

### 3.3 Cathode readings into the next step

Cathodes of the loop counter reach the step command of the IP counter
combinationally (`loop_counter.zero` → `ip_counter.valid` → `StepF`). With
the reading valid only at the next edge, that path needs T ≥ 3.1 µs; it is not
the limit. The model cannot tell whether a cathode moving in cycle N also
reaches a step command of cycle N (the old reading during its own guide
pulse); that is a question for the handshake, not checked here.

### 3.4 Clock

`dfflibmap` gives each module one `NOT_N16` on its clock net. Those inverters
drive 3–14 triggers each, 13.5–63 grids, far past the 10 grids the cell was
designed for (max_fanout 10). The extrapolated C↓ arrives at 113–280 ns, so
the clock skew between modules is up to 170 ns. In the machine the clock is
inverted once at the generator (`synt_dpc.tcl`), so this needs a clock
distribution design (a driver per board, or the generator itself); the
present numbers for these nets are extrapolation. With an ideal clock
(`--ideal-clock`) the phase delay fits at 31 hsClk and the minimum period is
7.99 µs: the late capture clock of IpLine (250 ns) was helping setup, the
early launch of the counters was not hurting the step command much.

### 3.5 Hold

The only hold violation (−44 ns at MachineCtrl triggers) comes from
`IpMemory` modelled with its output at the clock edge (0 ns). Any memory
access of 50 ns or more removes it (`--mem-ns 300` gives +256 ns); the ferrite
memory takes microseconds. Trigger-to-trigger hold is met: C→Q alone is
592 ns against at most 170 ns of skew.

### 3.6 Not timed

* The write window: `writeStart`/`writeTimer` of each counter start from the
  FSM, and the FSM samples the timer every Clk. Those paths are asynchronous
  by design (as the masked checkers of `doc/vtube_sdf_timing.md` §3.5).
* Dekatron write and reset inputs (`write_en_i`, `reset0_i`) and the reset
  relay lines.
* The memory: ideal synchronous, no access time. Real ferrite memory timing
  (4 µs, OPEN-014) is not in the model.

## 4. What it means for the clock

* **100 kHz: achievable** with the designed cells, a 3.3 µs phase start
  delay, and up to ~28 % slower tubes than modelled.
* **250 kHz (4 µs, the ferrite memory) is not**: the step command path alone
  is 3.2 µs, and the period is phase delay + phases + guide gate + fall +
  reading decode. Getting there needs structural changes, not faster cells.
  Candidates, for the owner to choose (not done):
  1. Register the step command (issue in cycle N, step in N+1): the phase
     delay drops to C→Q + PulseSender, ~1 µs, at the cost of one cycle per
     operation.
  2. Register the cathode readings used by other blocks (`zero`, `data_zero`,
     `loop_val_zero`) instead of decoding them into the next block's logic;
     the counters already latch `zeroes_q`/`nines_q`.
  3. Break the combinational `ready → valid` chain between ApLine,
     MachineCtrl and IpLine (REQ-APV2-007) with a registered handshake.
* **Sim cross-check**: `doc/vtube_sdf_timing.md` §3.6 ran at 4.5 µs with
  150 ns per stage; the SPICE delays are 2–4 × that on the slow edges (NAND2
  545 ns, A1OOI 492 ns, DFF C→Q 665 ns). The STA has not yet been checked
  against `synth_sim.sh -t -o 33 -c 8000` on the same netlist.

## 6. Netlist simulation cross-check (2026-10-30)

`synth_sim.sh -t` on the same netlist, helloworld and program.bfk:

1. **Phase delay 33, Clk 8 µs: FAIL**, output all zeros. Cause: the testbench
   held `rst_n` 1.95 µs, while the netlist with SPICE delays needs ~2.1 µs to
   settle from X after start; the first Clk edge latched X into the
   MachineCtrl FSM. Testbench fix: `rst_n` held 10 µs under
   `DEKATRON_DELAY_MODEL` (the machine's reset is a time relay; Clk starts
   from `rst_n`, so the cycle counts do not change). The zero-delay netlist
   (`synth_sim.sh -d`) passes with it.
2. **Phase delay 33, Clk 8 µs, after the fix: FAIL**, IP stays at 99900. The
   step command of the IP counter settled 3.88 µs after the edge, after the
   phase at 3.3 µs. The SDF gives every arc its fanout-6 value
   (`vtube_sdf.py` does not know the load), so the simulation is slower than
   the STA with tables. The STA with the same fanout-6 values bounds it from
   above:

   | | `ip_counter.valid` | `StepF` |
   |---|---|---|
   | STA, fanout tables | 2243 ns | 3029 ns |
   | simulation (SDF, fanout 6) | 2509 ns | 3878 ns |
   | STA, fanout 6 | 2851 ns | 4220 ns |

3. **Phase delay 48, Clk 12 µs (fanout-6 STA: should pass): FAIL**, IP
   still at 99900. Now `StepF` is in time (1.0 µs before the phase), but
   `GuideA` never rises: `NAND(StepF, Phase1)` never switches. The 300 ns
   phase is shorter than the gate's own delay (B↑→Y↓ 345 ns), and a tube
   stage cannot pass a pulse shorter than its switching time (Icarus path
   delays are inertial and model exactly that). The first run failed the
   same way.

The STA now checks this (`--phase-width` to try other widths): each source
pulse (OneShot / Impulse) is followed through the gates on its own; a stage
passes it only if the pulse is longer than the delay of its leading output
edge, and the width changes by the difference of the trailing and leading
delays. At the dekatron the guide must last at least `GUIDE_STEP_HS`. With
3 hsClk all 16 first-stage gates fail, matching the simulation:

| Phase width | margin, tables | margin, fanout 6 |
|---|---|---|
| 3 hsClk (RTL) | −201 ns | −144 ns |
| 4 | −101 ns | −44 ns |
| 5 | −1 ns | +56 ns |
| 6 | +99 ns | +156 ns |

Each hsClk of phase width adds 200 ns to the period (two phases). Not done,
for the owner: widen `PHASE1_HS`/`PHASE2_HS` (the 3/3/4 split is checked
against `HS_PER_CLK` = 10 of the 1 MHz RTL, so the RTL clock changes too), or
redesign the guide path so the phase does not pass two NAND2_J2 stages; make
`vtube_sdf.py` load-aware so the simulation and the STA use the same delays.

## 5. Limits of the model

* Delays are the SPICE values to the next stage's thresholds at fanout 6,
  scaled by the page tables; no slew, no wire capacitance, no interconnect
  between boards (HD-68 cables will add capacitance).
* Rise and fall arcs are kept, but no false-path or mode analysis: Debug and
  BF modes, write and step paths are all taken together. The worst path may
  be functionally impossible; that would only make the answer better.
* `GUIDE_EN_J2` is still the 150 ns estimate; dekatron times are the
  `DekatronTubeDelay` parameters (`GUIDE_STEP_HS` 2, `FALL_STEP_HS` 3), not
  measured (OPEN-013).
* OneShot / Impulse are ideal (no tube delay of their own).
