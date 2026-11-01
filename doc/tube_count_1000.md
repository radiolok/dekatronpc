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

## 6. Measured and not adopted

All on the flow of §5, means of four seeds unless noted.

| Idea | Measured | Decision |
|---|---|---|
| Counter-level Valid/Ready removed, kept only at IpLine/ApLine (owner, 2026-11-01) | IpLine + ApLine 847.6 against 843.6: **+4**, noise | no gain once the counters are flattened (§4): the counter's `ready = ¬(soft_rst \| hard_rst)` and `accept = valid & ready` merge with the block's `go`. The interface stays (AGENTS: Valid/Ready above the dekatron); it costs nothing |
| State codes of IpLine/ApLine (random search, as T6) | `binary`: 371–380 against 375 (seed 0, 24 tries); `none` with any codes ≥ 404 | no gain: Yosys' FSM optimization matters, the codes don't |
| Other ABC scripts | §5 | `amap -F 4 -A 20` adopted |
| One block instead of three boxes | 8 seeds: 1130.8 → 1123.9, **−7** (it was −21 before `amap`) | the three functional boxes stay; balancing them moves logic but not the count (the three-block flatten in §4 gave −4) |
| `insn_valid` dropped (redundant: MachineCtrl's `go` in `S_FETCH_W` already implies a finished fetch) | IpLine −6.1, MachineCtrl −1.7: **−8** | not done: IpLine_tb checks the flag in five places; small |
| Overflow halt from an IpLine strobe instead of MachineCtrl's edge trigger `overflow_q` | IpLine +15, MachineCtrl −10: **+5.7** | rejected |
| Asynchronous reset dropped from the 31 glue triggers (`DFFRN` 8 → `DFF` 7; the reset lines already reset the state synchronously, the time relay fires a hard reset at power-up) | **−31** | **TRS forbids**: REQ-REF-011, every FSM initialised by `rst_n`; it would also let random states write memory while `rst_n` is low |
| BinToBcd with inverted outputs (NOR without the output inverters) | −3 per decade before `amap`, −1.5 after: **−19.5** for 13 decades | not done: inverts the memory address and data buses and the display/terminal ports; the memory side takes either polarity for free, but every interface and test follows. Owner's call |
| CIN without the `rx ↔ memory` mux on the Data input (rx through the memory read bus, each source gated at its end) | the mux costs **25.4** | not done: REQ-UART-008 has ApLine load Data straight from `rx_data_bcd`; the gating would move into memory support |

### What the glue features cost (ablation: the feature tied off, everything else kept)

| Feature | Tubes |
|---|---|
| Program loading SOT/EOT (`insn_in` channel): IpLine 41.6 + MachineCtrl 37.6 | **79** |
| Halt in IpLine (step to the next instruction, `S_HALT`), with the ±IP keys | 35.5 |
| ±IP panel keys alone | 25 |
| CIN mux | 25.4 |
| Prefetch P3: `pf_q` 18 + `op_q` 8 | 26 |
| Overflow halt in MachineCtrl | 21 |
| Step key (`one_step`) | 19 |
| Halt key | 6 |
| Lazy zero test of `[` `]` from the memory register | 4.7 |
| Bell | 3 |
| Echo | 2.6 |

### Library: cells that tubes give naturally but the liberty doesn't have

A NOR is triodes on one plate (0.5 tube each), an AND term is a 6Zh2B pentode (g1, g3).
The liberty has NOR2, NOR4, NOT, NAND2, AOI21, AOI22, so a three-input NOR costs a NOR4
(2 tubes). Hypothetical cells added to a scratch liberty (`DPC_CELL_LIB`, new), with the
pin data of their family:

| Added | Total | Δ |
|---|---|---|
| — | 1128.8 | – |
| `NOR3_N16` (3 triodes, 1.5 tubes) | 1111.5 | **−17.3** |
| + `AOI211_J2N16` ((A·B)+C+D)', 6Zh2B + 6N16B, 2 tubes | 1105.3 | **−23.5** |
| + `AOI221_J2N16` (2.5), `AOI222_J2` (3) | 1100.1 | −28.7 |
| `AOI211` + `AOI221` without NOR3 | 1114.2 | −14.6 |

`NOR3_N16` is the cheapest to design (the NOR2/NOR4 family, `sch/logic/NOR4_N16`); it is
the one recommended. These are not in the flow: a cell enters the liberty only once it is
designed (REQ-MOD-004/005).

## 7. Where it stands, and the road below 1000

| Step | Total (mean of 4 seeds) | Δ |
|---|---|---|
| Start (9637e0c) | 1355.3 | – |
| §3 enable latches | 1234.9 | −120.4 |
| §4 counters flattened into their blocks | 1178 | −56.9 |
| §5 `amap` | **1128.9** | −49.1 |
| | | **−226.4 (−16.7 %)** |

The first goal (about 1200) is met with 71 tubes to spare; Clk stays 100 kHz (STA 8.0 µs),
IpLine and ApLine still work at the same time, the netlist simulations with tube delays pass.

The second goal (below 1000) needs about −130 more. What is left without changing a
requirement is small: the library cells (−17…−29, after design work) and one block
(−7) give ≈ 1095. The rest needs the owner:

| Option | Δ | Requirement touched |
|---|---|---|
| `NOR3_N16` (+ `AOI211`) designed | −17…−24 | none (REQ-MOD-003 library) |
| BinToBcd inverted, memory buses active-low | −19.5 | interface convention, not in the TRS |
| CIN through the memory read bus | −25 | REQ-UART-008 |
| Glue triggers without `rst_n` | −31 | REQ-REF-011 |
| ±IP panel keys dropped | −25 | Appendix B (`keyNextIp/keyPrevIp`) |
| Program loading by an external loader writing program memory directly | ≈ −79 | REQ-LOAD-001…003, OPEN-018 |
| No prefetch | −26 | REQ-PERF-003 (speed) |

For example, NOR3 + AOI211 (−24), inverted read-out (−19.5), CIN via the bus (−25) and
`rst_n` dropped (−31) give ≈ 1029; with the ±IP keys dropped as well ≈ 1004. Loading by an
external loader alone gives ≈ 1050; with the library cells, the inverted read-out and CIN
via the bus ≈ 981. The estimates add only roughly (ABC drift ±10, the options overlap).

## 8. Flow changes (for whoever runs synthesis next)

- `synt_dpc.tcl`: flattens everything but the boards and boxes (§4; `-hier`, `-oneblock`,
  `-keep`); `amap -F 4 -A 20` (§5); `DPC_ABC_SEED`, `DPC_ABC_SCRIPT`, `DPC_CELL_LIB` for
  experiments.
- `rtl/run/synth_seeds.sh`: blocks × seeds in parallel, per-seed totals and the mean
  (`-f` file list, `-a` synt_dpc options). Compare changes under ~10 tubes over four seeds.
- `vtube_sdf.py`: latch checkers (closing edge), inputs tied to one net.
- `vtube_sta.py`: latches (transparent window, setup to the closing edge, hold against the
  cathode readings).

## 9. Final verification (branch head)

- `run_tests.sh -d` (delay model: Dekatron, Counter ×2, IpLine, ApLine, MachineCtrl,
  DekatronPC hello / program / **pi.bfk**): all PASS; pi.bfk runs 27 452 710 µs = **2.745 M
  cycles**, the same as v0.24–v0.25, so the speed hasn't changed.
- cocotb `test_dek_counter` (9/9) and `test_pulse_sender` (4/4) PASS.
- `synth_sim.sh` 7/7, `synth_sim.sh -t` 4/4 with 0 setup / 0 hold violations; STA 8.0 µs.
- Verilator lint of DekatronPC and Emulator clean. Not run: `run_tests.sh -t` (the
  Verilator golden-model builds; the clocked model of the FPGA didn't change in behaviour).
