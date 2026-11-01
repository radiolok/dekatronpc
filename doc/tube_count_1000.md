# Tube count, third attempt: toward 1200 and below 1000 (2026-11-01)

Branch `tube_opt_1000` from `claude_nextGen` (9637e0c). Owner's task: review the old
proposals of `doc/tube_count_reduction.md`, pick the most promising ones, run the
experiments; first goal about 1200 tubes, second below 1000. Fixed: Clk 100 kHz
(REQ-CLK-005), IpLine and ApLine keep working at the same time (prefetch P3,
REQ-PERF-003). Allowed: repartition the machine into three blocks differently, or
synthesize it as one block if that is better.

Metric: the `run_tests.sh -s` set (IpLine + ApLine + MachineCtrl with their counters,
memory / reset relay / panel not counted), **mean of four `&deepsyn` seeds 0–3**
(`rtl/run/synth_seeds.sh`, new). ABC drifts by ±10 between seeds.

## 1. Starting point

| Block | Seed 0 | 1 | 2 | 3 | Mean |
|---|---|---|---|---|---|
| IpLine | 484.5 | 474.5 | 483.5 | 486.5 | 482.3 |
| ApLine | 533 | 538 | 536 | 540 | 536.8 |
| MachineCtrl | 339.5 | 330.5 | 333.5 | 342 | 336.4 |
| **Total** | 1357 | 1343 | 1353 | 1368.5 | **1355.3** |

Where the tubes are (seed 0):

| Part | Tubes | Note |
|---|---|---|
| Counter IP (5 decades) | 169.5 | 5 × (BinToBcd 12 + 2 J2 guide gates), pulse sender 6, 8 carry-flag DFF (56), FSM-free control |
| Counter Loop (2) | 41 | no read-out (READ = 0), 2 flag DFF |
| Counter AP (5) | 167.5 | as IP, 8 flag DFF |
| Counter Data (3) | 186 | 3 × (BinToBcd 12 + BcdToBinEn 22.5 + 2), 4 flag DFF + `zero_q`/`at_top_q` |
| IpLine glue (+ loop detector) | 274 | 12 reset triggers (96) |
| ApLine glue | 179.5 | 5 reset triggers (40) |
| MachineCtrl | 339.5 | 13 + 1 reset triggers (112) |

Triggers: 24 `DFF_J2N16` (counter flags, 168 tubes) + 31 `DFFRN/DFFSN` (glue, 248 tubes).

## 2. The old proposals, reviewed

| # | Idea (old report) | Then | Now |
|---|---|---|---|
| T2 | Diode codecs | rejected (REQ-AUTH-002) | stays rejected |
| T3 | Latches for the carry flags (−70…−84) | postponed until the delay netlist works | **the netlist works at 100 kHz since v0.23–v0.25; done in a stronger form, §3 (−120)** |
| T7 | P3 prefetch cheaper / `op_q` in latches | rejected (speed) | speed stays; latches for `op_q` keep it — to measure |
| T8 | Ripple carry (cathode 0/9 pulses the next decade) | postponed (slowdown) | superseded by §3: the carry costs now only one latch per decade |
| R5 | Panel edge detection once | open, ≈ −10 | small |
| R8 | Shared counter control | rejected (one phase generator per counter) | the counters have no FSM any more (v0.24); nothing left to share but the phase generator |
| R9 | One-hot memory address | rejected | stays rejected |
| R10 | Data counter as nesting counter | not recommended | stays |
| R11 | Flatten the three blocks | open | **to measure, together with a new partition (owner's hint)** |
| new | Counter-level Valid/Ready removed, kept only at IpLine/ApLine (owner, 2026-11-01) | – | to measure |

## 3. Done: one enable latch per decade instead of two carry-flag triggers (−120)

The counter kept `nines_q`/`zeroes_q` for every decade but the top one (22 `DFF_J2N16`,
154 tubes) only to hold the carry enables `en_chain` steady while the lower decades
leave 0/9 during the guide phases. Since v0.24 every operation fits in its own cycle,
and the phase generator delays the phases by `DEKATRON_PHASE_DELAY_NS` (3.3 µs) after
the Clk edge (REQ-PULSE-009). In that window the discharges stand still on the
cathodes of the previous operation (only a write can move them, and a write doesn't use
the enables), and `dec` is already set by the master (it is part of the step command,
which must settle in the same window).

So the tube machine (`DEKATRON_DELAY_MODEL`, i.e. synthesis and every delay simulation)
now computes the carry chain from the **live** cathodes and `dec` and holds it in one
`LATCH_J2N16` (3.5 tubes) per decade 1..D−1, transparent while `cmd_win` is high:

- `DekatronPhaseGen` exports `CmdWin` = the phase-delay `OneShot` window (Clk rise →
  phase start); no new timing element;
- the latch closes when the phases start and holds through both phases and the fall;
- 11 latches (IP 4, AP 4, Data 2, Loop 1) replace 22 triggers. Data keeps its two
  wrap triggers `zero_q`/`at_top_q`: a wrap is a write, which may start inside the
  window and would cut its own write line short through a latch.
- The clocked model (FPGA, RTL without delays, `PHASE_DELAY_HS` = 0) keeps the
  triggers: the behaviour is the same, only the storage differs.

Flow: `vtube_sdf.py` now puts a setup/hold checker on every `LATCH_J2N16` at its
closing edge (fall of C); the latch got its setup (307 ns at fanout 6, cell page) in
`vtube_timing.json`. `vtube_sta.py` handles latches: data passes D→Q while the window is
open; the setup is checked like the step command against its phase (D settles before
the window closes, next cycle's D changes after it), and the cathode readings after the
phases are the hold check.

| Block | Seed 0 | 1 | 2 | 3 | Mean | Δ |
|---|---|---|---|---|---|---|
| IpLine | 428.5 | 418.5 | 429 | 439.5 | 428.9 | −53.4 |
| ApLine | 473.5 | 465 | 471.5 | 476.5 | 471.6 | −65.2 |
| MachineCtrl | 338 | 335.5 | 332.5 | 331.5 | 334.4 | (unchanged RTL) |
| **Total** | 1240 | 1219 | 1233 | 1247.5 | **1234.9** | **−120.4** |

Verification:
- Delay-model Icarus: Counter, Counter with random power-up, IpLine (looptest), ApLine,
  DekatronPC helloworld — PASS. Clocked model: Counter, DekatronPC — PASS. Verilator lint
  of DekatronPC and Emulator clean.
- `synth_sim.sh -t Counter DekatronPC` (tube delays, 10 µs): Counter PASS; helloworld and
  program.bfk print correctly; the 11 new latch checkers report nothing; the one setup
  violation left is the known asynchronous `soft_rst` → ApLine trigger (§22 item 14), at
  the same simulation time as before the change.
- STA (`vtube_sta.sh`): minimum period **8.47 µs** (was 8.92), 100 kHz meets with 1.5 µs.
  The latches: D settles 1.07–1.69 µs before the window closes; the cathodes change
  1.0–1.4 µs after it closed.

## 4. Done: counters flattened into their blocks; partition experiments (−58)

The owner allowed a different partition, or one block if it synthesizes better. Four
variants of the same RTL (after §3), mean of seeds 0–3:

| Variant (`synt_dpc.tcl`) | Seeds 0 / 1 / 2 / 3 | Mean |
|---|---|---|
| `run_tests.sh -s` set, hierarchical (§3) | 1240 / 1219 / 1233 / 1247.5 | 1234.9 |
| DekatronPC as one run, hierarchical | 1250.5 / 1234.5 / 1234.5 / 1242.5 | 1240.5 |
| DekatronPC, the three blocks flattened together, counters kept | – | 1236.3 |
| **three blocks kept, counters flattened into them** | 1175.5 / 1186.5 / 1168 / 1176.5 | **1176.6** |
| DekatronPC, the same in one run | 1174 / 1190 / 1187 / 1170 | 1180.3 |
| DekatronPC as **one block** (everything but the boards flattened) | 1142 / 1171 / 1162.5 / 1159.5 | 1158.8 |

The gain is in the counter boundary, not in the block boundaries. A counter has no FSM
since v0.24: its control is a few gates on `accept`, `dec`, `set`, `set_zero`, and the
block computes the same terms from its own state; across the boundary ABC can merge
them. Merging the three blocks into one adds only −21 (two ABC spreads), so the
partition into three boxes stays: IpLine 393, ApLine 448, MachineCtrl 335 is uneven,
but moving logic between boxes doesn't change the count, and the boxes follow the
function (REQ-PR-012). The one-block variant is kept as an option (`-oneblock`).

REQ-PR-011 allows it: only a submodule with a board type is placed as one module, the
rest is expanded to base cells. `DekatronCounter` was never a board.

Flow: `synt_dpc.tcl` now keeps only the boards and boxes — `DekatronModule`, the relay
modules, IpLine / ApLine / MachineCtrl, the black boxes and the SYNTH stubs of the tube
and its RC elements (flattened, their constant outputs would fold the read-out away) —
and runs `synth -flatten` (an explicit `proc; flatten` before `synth` cost MachineCtrl
+12 for nothing). `-hier` gives the old flow, `-oneblock` the one-block variant.

Side effects:
- Internal strobes of the flattened counters are merged away in the netlist. The
  checker qualifier of the Data wrap triggers (`vtube_timing.json` "masked") now uses
  ApLine's `data_valid`, marked `(* keep *)` (cost within noise: +1.4); the IpLine_tb
  monitor of `ip_valid & loop_valid` runs on RTL only (`ifndef NETLIST_SIM`).
- The hierarchy report no longer shows counters as rows.

| Block | Seed 0 | 1 | 2 | 3 | Mean |
|---|---|---|---|---|---|
| IpLine | 391.5 | 402 | 387.5 | 395.5 | 394.1 |
| ApLine (with `keep`) | 447 | 451.5 | 450.5 | 449 | 449.5 |
| MachineCtrl | 338 | 335.5 | 332.5 | 331.5 | 334.4 |
| **Total** | 1176.5 | 1189 | 1170.5 | 1176 | **1178** |

Verification: `synth_sim.sh` (all default tests, netlists without delays) PASS;
`synth_sim.sh -t` (Dekatron, Counter, DekatronPC hello/program with tube delays at
10 µs) PASS with 0 setup / 0 hold violations (the known asynchronous `soft_rst` path is
not fixed, it just doesn't hit in this netlist). STA: 8.55 µs, 100 kHz with 1.45 µs.

## 5. Done: `amap` instead of `map -a` (−49)

Flattened blocks are larger, so the mapper was tried again. `DPC_ABC_SCRIPT` (new, in
`synt_dpc.tcl`) runs a whole ABC script for experiments. Means over two seeds (0, 1)
unless noted:

| ABC script after `&deepsyn -J 50 -T 30; &put; dch -f` | Total |
|---|---|
| `map -a` (as before) | ≈ 1178 |
| `&deepsyn -J 300 -T 120`, `map -a` | 1176.2 |
| `map -a`, then a second deepsyn + map pass | 1175.7 |
| `map -a; mfs` | breaks the mapping (330: `$lut` cells, rejected) |
| `dc2; resyn2` first | fails (`resyn2` is not an alias in Yosys' ABC) |
| **`amap`** | 1139.5; four seeds **1131.7** |
| `amap -s`, `dch -f -a` | fail on one seed (rejected) |
| `amap`, then `strash; dch -f; amap` again | 1135.7 |
| `&deepsyn -J 300 -T 120`, `amap` | 1128.2 (four times the run time) |
| **`amap -F 4 -A 20`** | 1135.7; four seeds **1128.8** — adopted |

In the 2026-10-06 library `amap` was worse than `map -a` (§3 of the old report); with the
designed cells, `dont_use` on the followers and the cheaper AOI21 it is the better mapper.
It uses only designed cells (more `NOT_N16`, fewer `NAND2_J2`), and `equiv_opt` proves
all three blocks. It maps for area only, yet the STA is better: **8.01 µs** (125 kHz),
100 kHz with 2.0 µs.

| Block | Seed 0 | 1 | 2 | 3 | Mean |
|---|---|---|---|---|---|
| IpLine | 375 | 386 | 370.5 | 378 | 377.4 |
| ApLine | 426.5 | 429 | 426 | 423.5 | 426.3 |
| MachineCtrl | 327.5 | 327.5 | 322.5 | 323.5 | 325.3 |
| **Total** | 1129 | 1142.5 | 1119 | 1125 | **1128.9** |

Found on the way: ABC now ties two inputs of one cell to the same net (`A2OOI_J2` with
A = D, i.e. A·(B + C)). That is fine for the tubes (one net drives two grids), but Icarus
then finds no module path for the second pin and `synth_sim.sh -t` failed on the SDF
warning. `vtube_sdf.py` leaves out the IOPATH of an input that shares its net with an
earlier input of the same cell.

Verification: `synth_sim.sh` (7 runs) PASS; `synth_sim.sh -t` (Dekatron, Counter,
DekatronPC hello / program) PASS, 0 setup / 0 hold violations; STA as above.
