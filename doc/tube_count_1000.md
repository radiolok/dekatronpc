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

## 0. Option index

Stable IDs for later sessions: cite them as `doc/tube_count_1000.md` TC-xx. Δ is the
total tube count of IpLine + ApLine + MachineCtrl, mean of four `&deepsyn` seeds.

| ID | Option | Δ, tubes | Status | Section |
|---|---|---|---|---|
| TC-D1 | One `LATCH_J2N16` per decade, open in `CmdWin`, instead of the carry-flag triggers `nines_q`/`zeroes_q` | −120.4 | **done** (90d63d9) | §3 |
| TC-D2 | Counters flattened into their blocks; only boards and boxes kept in the netlist | −56.9 | **done** (712ddfb) | §4 |
| TC-D3 | ABC `amap -F 4 -A 20` instead of `map -a` | −49.1 | **done** (2ef6eea) | §5 |
| TC-X1 | Counter-level Valid/Ready removed (owner's proposal) | +4 | no gain, not done | §6 |
| TC-X2 | State-code search for IpLine/ApLine | ±5 | no gain | §6 |
| TC-X3 | Other ABC scripts (`&deepsyn` longer, `mfs`, `&nf`, second pass) | ±5 or broken | no gain | §5 |
| TC-X4 | Whole machine as one block (repartition) | −7 | not done, three boxes stay | §4, §6 |
| TC-X5 | Overflow halt from an IpLine strobe | +5.7 | rejected | §6 |
| TC-O1 | Cell `NOR3_N16` (3 triodes, 1.5 tubes) | −17.3 | **done** (`sch/logic/NOR3_N16`, TRS v0.27): measured 1128.8 → 1111.5 | §6 |
| TC-O2 | Cells `AOI211_J2N16` (+ `AOI221`, `AOI222`), on top of TC-O1 | −6.2 (−11.4) | `AOI211_J2N16` **done** (`sch/logic/AOI211_J2N16`, TRS v0.28): measured 1111.5 → 1105.3; `AOI221`/`AOI222` open | §6 |
| TC-O3 | BinToBcd with inverted outputs, memory buses active-low | −19.5 | open: owner (interface) | §6 |
| TC-O4 | CIN through the memory read bus, no rx/memory mux | −25 | open: REQ-UART-008; bf100: speed neutral, variant A recommended | §6, §6.1 |
| TC-O5 | No `rst_n` on the 31 glue triggers | −31 | blocked by REQ-REF-011 | §6 |
| TC-O6 | ±IP panel keys dropped | −25 | open: Appendix B | §6 |
| TC-O7 | Program loading by an external loader writing program memory | ≈ −79 | open: REQ-LOAD-001…003, OPEN-018 | §6 |
| TC-O8 | No prefetch P3 | −26 | open: REQ-PERF-003 (speed) | §6 |
| TC-O9 | `insn_valid` dropped (redundant for MachineCtrl) | −8 | open: small, IpLine_tb rework | §6 |

Combinations toward 1000 are in §7; the feature costs (ablation) behind TC-O4…O8 in §6.

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

| ID | Idea | Measured | Decision |
|---|---|---|---|
| TC-X1 | Counter-level Valid/Ready removed, kept only at IpLine/ApLine (owner, 2026-11-01) | IpLine + ApLine 847.6 against 843.6: **+4**, noise | no gain once the counters are flattened (§4): the counter's `ready = ¬(soft_rst \| hard_rst)` and `accept = valid & ready` merge with the block's `go`. The interface stays (AGENTS: Valid/Ready above the dekatron); it costs nothing |
| TC-X2 | State codes of IpLine/ApLine (random search, as T6) | `binary`: 371–380 against 375 (seed 0, 24 tries); `none` with any codes ≥ 404 | no gain: Yosys' FSM optimization matters, the codes don't |
| TC-X3 | Other ABC scripts | §5 | `amap -F 4 -A 20` adopted |
| TC-X4 | One block instead of three boxes | 8 seeds: 1130.8 → 1123.9, **−7** (it was −21 before `amap`) | the three functional boxes stay; balancing them moves logic but not the count (the three-block flatten in §4 gave −4) |
| TC-O9 | `insn_valid` dropped (redundant: MachineCtrl's `go` in `S_FETCH_W` already implies a finished fetch) | IpLine −6.1, MachineCtrl −1.7: **−8** | not done: IpLine_tb checks the flag in five places; small |
| TC-X5 | Overflow halt from an IpLine strobe instead of MachineCtrl's edge trigger `overflow_q` | IpLine +15, MachineCtrl −10: **+5.7** | rejected |
| TC-O5 | Asynchronous reset dropped from the 31 glue triggers (`DFFRN` 8 → `DFF` 7; the reset lines already reset the state synchronously, the time relay fires a hard reset at power-up) | **−31** | **TRS forbids**: REQ-REF-011, every FSM initialised by `rst_n`; it would also let random states write memory while `rst_n` is low |
| TC-O3 | BinToBcd with inverted outputs (NOR without the output inverters) | −3 per decade before `amap`, −1.5 after: **−19.5** for 13 decades | not done: inverts the memory address and data buses and the display/terminal ports; the memory side takes either polarity for free, but every interface and test follows. Owner's call |
| TC-O4 | CIN without the `rx ↔ memory` mux on the Data input (rx through the memory read bus, each source gated at its end) | the mux costs **25.4** | not done: REQ-UART-008 has ApLine load Data straight from `rx_data_bcd`; the gating would move into memory support |

### 6.1. TC-O4: where CIN puts the character (Brainfuck-100)

Two ways to drop the `rx ↔ memory` mux on the Data counter input:

- **A, into the counter (as now)**: CIN loads the counter and sets MemLock.
  The rx bits reach the counter over the memory read bus.
- **B, into memory**: CIN writes the cell directly. MemLock is cleared (the
  cell is overwritten, so nothing is flushed), and the write-through register
  holds the character (`mem_here_q = 1`).

Per CIN they differ by one operation, and only through the first later op that
needs a decision. `+ - .` need the value in the counter: B pays a counter load
(`S_DSET`), A pays nothing. `< >` need the cell in memory: A pays a flush, B
pays nothing. `[ ]` are neutral (the zero test comes from the counter or the
memory register), and so are `[-]` (CLRD, `set_zero` either way) and another `,`.

`tools/bf100/cin_next.py` runs the 53 Brainfuck-100 programs that execute a `,`
on their `.in` (20 M steps max; 98 `long.b` has no file) and counts that first
op after each executed `,`:

| First deciding op after `,` | Executed | Programs where it is the majority |
|---|---|---|
| `+ -` (data) | 8666 (756 without `awib`) | 23 |
| `.` (COUT) | 40 | 1 (`primality-by-trial-division`) |
| `< >` (address) | 1762 | 29 |
| end of program | 3 | – |

The total is skewed by `awib-0.4.b` (`,+`: 7910 of the reads are its EOF
normalisation). Counted by program, the address move wins slightly, 29 against 24:
reading into an array (`,>`, `,<`: sorts, interpreters, `cat2`, `reverse`, `utm`,
`Collatz`). The data ops come from `,----------` (subtracting `'\n'` or `'0'`:
`atoi`, `luhn`, `caesar`, `primes`) and `,+` (EOF −1 → 0: `rot13`, `head`,
`mac2unix`, `bfc`). In the program text the commonest successor is `[`/`]`
(read loops `,[` … `,]`), which is neutral. Text counts are polluted by commas in
comments (`utm.b`, `Zozotez.b`), so only executed reads are used.

**Speed does not decide it.** At 110 baud one character takes ≈ 91 ms ≈ 9100
Clk at 100 kHz. One operation more or less per character is ≈ 0.01 %. The
choice rests on tubes and on how much the semantics move:

- **A** keeps the behaviour (CIN → counter, MemLock set), so dpcrun, `ApLine_tb`
  and the rx_rdy timing (REQ-UART-008, Appendix B) stay as they are. The mux
  leaves ApLine only if the read bus is shared: the sender (external, may be
  non-tube, REQ-AUTH) drives `rx_data_bcd` onto it only during CIN, and the
  memory output register is off the bus or cleared then. A clear is safe: after
  CIN, MemLock is set and the register's content is not used until the next
  flush, which refills it. In RTL the selection moves from ApLine into the
  memory support/top level (`RAM.sv` already selects `ovl_hit ? ovl_data : bank_rd`).
- **B** changes the MemLock rules (CIN clears lock instead of setting it), so
  dpcrun, the TRS (REQ-UART-008, the MemLock paragraph) and the tests follow. It
  does not remove the mux by itself: `mem_wr_data` becomes `cin ? rx : data_out`
  (10 bits instead of 12) unless the write bus is shared too. Sharing the write
  bus is harder, because the counter's cathode read lines cannot be switched off
  without clearing the counter.

Recommendation: A, with the rx bits on the memory read bus. Not done yet: it
moves the selection out of the counted blocks, so the memory support has to show
that the gating is really free (owner's decision, REQ-UART-008).

### What the glue features cost (ablation: the feature tied off, everything else kept)

| Feature | Tubes | Option |
|---|---|---|
| Program loading SOT/EOT (`insn_in` channel): IpLine 41.6 + MachineCtrl 37.6 | **79** | TC-O7 |
| Halt in IpLine (step to the next instruction, `S_HALT`), with the ±IP keys | 35.5 | – |
| ±IP panel keys alone | 25 | TC-O6 |
| CIN mux | 25.4 | TC-O4 |
| Prefetch P3: `pf_q` 18 + `op_q` 8 | 26 | TC-O8 |
| Overflow halt in MachineCtrl | 21 | (TC-X5) |
| Step key (`one_step`) | 19 | – |
| Halt key | 6 | – |
| Lazy zero test of `[` `]` from the memory register | 4.7 | – |
| Bell | 3 | – |
| Echo | 2.6 | – |

### Library: cells that tubes give naturally but the liberty doesn't have

A NOR is triodes on one plate (0.5 tube each), an AND term is a 6Zh2B pentode (g1, g3).
The liberty has NOR2, NOR4, NOT, NAND2, AOI21, AOI22, so a three-input NOR costs a NOR4
(2 tubes). Hypothetical cells added to a scratch liberty (`DPC_CELL_LIB`, new), with the
pin data of their family:

| ID | Added | Total | Δ |
|---|---|---|---|
| | — | 1128.8 | – |
| TC-O1 | `NOR3_N16` (3 triodes, 1.5 tubes) | 1111.5 | **−17.3** |
| TC-O2 | + `AOI211_J2N16` ((A·B)+C+D)', 6Zh2B + 6N16B, 2 tubes | 1105.3 | **−23.5** |
| TC-O2 | + `AOI221_J2N16` (2.5), `AOI222_J2` (3) | 1100.1 | −28.7 |
| | `AOI211` + `AOI221` without NOR3 | 1114.2 | −14.6 |

`NOR3_N16` is the cheapest to design (the NOR2/NOR4 family, `sch/logic/NOR4_N16`); it is
the one recommended. These are not in the flow: a cell enters the liberty only once it is
designed (REQ-MOD-004/005). TC-O1 is now designed (`sch/logic/NOR3_N16/README.md`, two cells on
three 6N16B) and in `vtube_cells.lib` with the same pin data as the scratch entry. Measured
2026-11-01, `synth_seeds.sh -s "0 1 2 3" IpLine ApLine MachineCtrl`, HEAD liberty against the new one:

| Seed | 0 | 1 | 2 | 3 | Mean |
|---|---|---|---|---|---|
| without NOR3_N16 | 1129.0 | 1142.5 | 1119.0 | 1125.0 | 1128.8 |
| with NOR3_N16 | 1114.0 | 1122.5 | 1105.5 | 1104.0 | **1111.5 (−17.3)** |

`run_tests.sh -s` (seed 0): IpLine 370.5, ApLine 417.0, MachineCtrl 326.5, 96 `NOR3_N16` (144 tubes),
`NOR4_N16` down to 48. With the cell, `run_tests.sh -t`, `-d`, `synth_sim.sh` (7/7) and the cocotb
regression (34/34) pass.

TC-O2, first cell: `AOI211_J2N16` is designed (`sch/logic/AOI211_J2N16/README.md`: A1OOI_N16J2 with
the second triode of the 6N16B as input D, one cell on two tubes) and in `vtube_cells.lib` with the pin
data of the scratch entry. Measured 2026-11-01 the same way, the NOR3_N16 liberty against the new one:

| Seed | 0 | 1 | 2 | 3 | Mean |
|---|---|---|---|---|---|
| without AOI211_J2N16 | 1114.0 | 1122.5 | 1105.5 | 1104.0 | 1111.5 |
| with AOI211_J2N16 | 1110.5 | 1115.0 | 1095.5 | 1100.5 | **1105.3 (−6.2)** |

`run_tests.sh -s` (seed 0): IpLine 368.5, ApLine 417.5, MachineCtrl 324.5, 28 `AOI211_J2N16` (56 tubes),
`NOR3_N16` down to 85. `AOI221_J2N16` / `AOI222_J2` (another −5.2 by the estimate) are not designed. With the cell,
`run_tests.sh -t`, `-d`, `synth_sim.sh` (7/7) and the cocotb regression (34/34) pass; STA 8.18 µs (100 kHz, 1.8 µs slack).

## 7. Where it stands, and the road below 1000

| ID | Step | Total (mean of 4 seeds) | Δ |
|---|---|---|---|
| | Start (9637e0c) | 1355.3 | – |
| TC-D1 | §3 enable latches | 1234.9 | −120.4 |
| TC-D2 | §4 counters flattened into their blocks | 1178 | −56.9 |
| TC-D3 | §5 `amap` | **1128.9** | −49.1 |
| | | | **−226.4 (−16.7 %)** |

The first goal (about 1200) is met with 71 tubes to spare; Clk stays 100 kHz (STA 8.0 µs),
IpLine and ApLine still work at the same time, the netlist simulations with tube delays pass.

The second goal (below 1000) needs about −130 more. What is left without changing a
requirement is small: the library cells (−17…−29, after design work) and one block
(−7) give ≈ 1095. The rest needs the owner:

| ID | Option | Δ | Requirement touched |
|---|---|---|---|
| TC-O1, TC-O2 | `NOR3_N16` + `AOI211` designed (done: 1105.3) | −23.5 | none (REQ-MOD-003 library) |
| TC-O3 | BinToBcd inverted, memory buses active-low | −19.5 | interface convention, not in the TRS |
| TC-O4 | CIN through the memory read bus | −25 | REQ-UART-008 |
| TC-O5 | Glue triggers without `rst_n` | −31 | REQ-REF-011 |
| TC-O6 | ±IP panel keys dropped | −25 | Appendix B (`keyNextIp/keyPrevIp`) |
| TC-O7 | Program loading by an external loader writing program memory directly | ≈ −79 | REQ-LOAD-001…003, OPEN-018 |
| TC-O8 | No prefetch | −26 | REQ-PERF-003 (speed) |

For example, TC-O1 + O2 (−24), TC-O3 (−19.5), TC-O4 (−25) and TC-O5 (−31) give ≈ 1029;
with TC-O6 as well ≈ 1004. TC-O7 alone gives ≈ 1050; TC-O7 + O1 + O2 + O3 + O4 ≈ 981. The estimates add only roughly (ABC drift ±10, the options overlap).

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
