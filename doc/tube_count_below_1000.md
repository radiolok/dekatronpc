# Tube count, fourth pass: what is left on the way below 1000 (2026-11-03)

Branch `ISA16` at b148221 (TRS v0.43). Owner's task: study the code and the two earlier
passes (`doc/tube_count_reduction.md`, `doc/tube_count_1000.md`) and recommend new
places to save tubes. The owner's own hint: the ±IP panel keys are expensive, and the
counter could take the key pulses more directly.

This pass is a **recommendation only**. Nothing here is in the RTL. Each option was
measured with a quick patch in a scratch copy of the RTL (`doc/data/tube_count_n_experiments.patch`
holds the combined patch N1–N4 + TC-O4 + TC-O9). The patches were synthesized but **not
simulated**. Before adopting one, it has to go through the full flow (tests, dpcrun,
`synth_sim.sh -t`).

Metric: the same as in `doc/tube_count_1000.md`, i.e. IpLine + ApLine + MachineCtrl with the
dekatron module cells (WRCH, RDD, GLIFT, GUIDE_EN), without the 15 A110. Here it is the mean
of **eight** `&deepsyn` seeds (0–7, `synth_seeds.sh -s "0 1 2 3 4 5 6 7"`), because some
steps are close to the ABC noise.

## Owner's decisions (2026-11-03) and progress

| ID | Decision | Done |
|---|---|---|
| TC-N1 | take | **done** (TRS v0.44): 1115.5 → **1085.0** over seeds 0–3 (§11) |
| TC-N3 | take, and count the key debouncer and the synchronizer; a liberty cell between the key and the counter input | |
| TC-N2 | take: the overflow lamp latches a self-holding relay that stops the clock; a liberty cell for it is welcome | |
| TC-O9 | take, if the other lines already carry the validity | |
| TC-O4 | take, if the memory interface doesn't change | |
| TC-N4 | **rejected on purpose**: no NOP at the start of a program | – |
| TC-N5 | later, as a separate large piece of work | – |
| TC-N6 | doubtful, needs a study first | – |
| TC-N7 | technically possible, later | – |

## 0. Option index

| ID | Option | Δ, tubes (8 seeds) | Requirement touched | Section |
|---|---|---|---|---|
| TC-N1 | Data counter's hundreds decade reads and writes only cathodes 0–2 | **−12** | none (the values stay 0…255) | §2 |
| TC-N2 | Loop overflow freezes IpLine (`ready` low); MachineCtrl drops its overflow halt | **−25** | REQ-CNT-007 wording ("halt" → "stop until reset") | §3 |
| TC-N3 | ±IP keys step the IP counter directly, without FSM transitions | **−24** | none (the keys stay, Appendix B unchanged) | §4 |
| TC-N4 | "Step, then fetch" always: no `ip_counted_q` / `halt_pending_q` | **−34** | bootloader layout, IP after a soft reset or a halt | §5 |
| | N1 + N2 + N3 + N4 together | **−94: 1116.5 → 1022.7** | | §7 |
| TC-O9 | (old) `insn_valid` dropped | −13 on top | IpLine_tb | §7 |
| TC-O4 | (old) CIN through the memory read bus | −31 on top | REQ-UART-008 | §7 |
| TC-N5 | Edge-triggered flip-flop on 3–3.5 tubes (capacitor-coupled clock) instead of `DFF_J2N16` (7) | **−95…−108** | new cell (REQ-MOD-005), clock-pulse discipline | §6 |
| TC-N6 | Write decoder of the Data counter as a coincidence matrix in the write channels | ≈ −20…−30 (estimate) | write-channel cell (REQ-MOD-007), SPICE | §8 |
| TC-N7 | `NOR5_N16` cell (for bit 0 of BinToBcdN) | −4 | none | §8 |

Path below 1000 without new cells: N1–N4 + TC-O9 + TC-O4 = **978.3**. With TC-N5 on top: **≈ 884**.

## 1. Starting point

`synth_seeds.sh`, HEAD b148221, eight seeds: **1116.5** (IpLine 390.4, ApLine 460.4,
MachineCtrl 265.8). Seed 0 in `run_tests.sh -s`: 1121.0 tubes + 15 A110.

Where the tubes are now (seed 0):

| Cells | Count | Tubes | Share |
|---|---|---|---|
| `DFF_J2N16` (7 tubes each) | 31 | **217** | 20 % |
| Gates (NOR2/3/4, NOT, NAND2, AOI, OAI) | ~700 | ≈ 720 | 64 % |
| `RDD_X7` read diodes | 134 | 67 | 6 % |
| `LATCH_J2N16` carry enables | 11 | 38.5 | 3 % |
| `GUIDE_EN_J2` + `WRCH_N16` + `GLIFT_N16` | 30 + 58 + 4 | 63 | 6 % |

The 31 triggers: IpLine 11 (`state[2:0]`, `dir_q`, `key_moved_q`, `ip_counted_q`, `scanning_q`,
`halt_pending_q`, `insn_valid_q`, `eot_q`, `overflow_q`), ApLine 7 (`state[2:0]`, `lock_q`,
`mem_here_q`, Data `zero_q`/`at_top_q`), MachineCtrl 13 (`state[3:0]`, `op_q[3:0]`, `pf_q`,
`one_step`, `overflow_q`, `rst_soft`, `insn_loading`). One trigger costs as much as seven
two-input gates, so the cheapest options remove triggers (N2, N4, O9) or make them cheaper (N5).

A side note on the metric: the `OneShot` / `Impulse` elements of the four phase generators
are black boxes and count as 0. In the machine each is a tube monostable. This doesn't
change the comparisons here, but a key one-shot (the owner's hint, §4) adds real tubes
that the count won't show.

## 2. TC-N1: the hundreds decade of Data reads only 0–2 (−12)

The Data counter wraps at 255 (`TOP_LIMIT_MODE`), so its hundreds dekatron only ever stands
on cathodes 0, 1, 2. After a reset it is at 0, and the terminal sends 7-bit characters
(≤ 127). Synthesis doesn't know this. The module still has:

- 10 read diodes (`RDD_X7`), of which 7 are useless: −3.5 tubes;
- 10 write channels (`WRCH_N16`, `keep`), of which 7 are never driven: −3.5;
- a full `BinToBcdN` (NOR5 + NOR4 + NOR4 + NOR2, ≈ 8 tubes), where `Out_n[1:0]` = `~c2`, `~c1`
  and `Out_n[3:2]` are always 1: ≈ −6.

Patch: a parameter `MAX_DIGIT` of `DekatronModule` (default 9). `DekatronCounter` passes the
top digit of `TOP_VALUE` to the top decade in `TOP_LIMIT_MODE`. The read and write channels
above `MAX_DIGIT` are left out, and those cathode lines go to 0 in front of the encoder.

| | IpLine | ApLine | MachineCtrl | Total |
|---|---|---|---|---|
| HEAD | 390.4 | 460.4 | 265.8 | 1116.5 |
| TC-N1 | 390.4 | 446.4 | 267.7 | **1104.5 (−12.0)** |

What follows from it: `tx_data_bcd[11:10]` are constant 1 (they already are in normal
operation). Appendix B doesn't change. The data memory stores only `hundreds[1:0]` anyway.
If a discharge lands on cathodes 3–9 at power-up, it reads as 0 until the reset, the same as
any random power-up state. The dekatron itself stays a 10-cathode A110: wrap 255 → 0 is a
`set_zero`, and 0 → 255 writes through `resetN` on cathode 2.

The same trick fits the top AP decade only if AP is limited to 29999 (OPEN-001). It would
also need a wrap circuit at 29999, and the bootloader's `0<` would have to land on 29999.
Not recommended until OPEN-001 is decided.

## 3. TC-N2: loop overflow stops IpLine instead of halting MachineCtrl (−25)

Today an overflow sets IpLine's `overflow_q`. MachineCtrl then catches its edge
(`overflow_q`, a second trigger) and jumps to `S_HALT` from any state. That branch has the
highest priority after the reset, so it goes into the next-state logic of all four state
bits (21 tubes by the ablation in `doc/tube_count_1000.md` §6).

The alternative uses what IpLine already holds:

- IpLine: `ready = (state == S_IDLE) & ~halt_rq & go & ~overflow_q`. After an overflow,
  IpLine never accepts again, so MachineCtrl waits in `S_FETCH_W` / `S_WAIT` with nothing
  moving. Only a reset clears `overflow_q` (as now, REQ-CNT-007).
- MachineCtrl: no `overflow_q`, no `overflow_hit` branch. The error bell is
  `bell_on_error & loop_overflow`, a level, so the bell's own one-shot (outside the count)
  has to make a single ring of it.

Measured: **1116.5 → 1091.5 (−25.0)**, almost all in MachineCtrl.

What the owner has to accept:
- The machine "stops" rather than halts. The LoopOverflow lamp is lit and the `IsHalted`
  lamp is not.
- The Halt key doesn't take it into `S_HALT`. Step/Run do nothing, and only Soft/Hard Reset
  get out of it. Since the overflow is already cleared only by a reset, the operator loses
  nothing.
- REQ-CNT-007 says "abort the scan and halt the machine". The scan is aborted (IpLine clears
  `scanning_q`) and the machine stands still. The wording should say "stops until reset".

## 4. TC-N3: ±IP keys step the counter directly (−24)

The owner's hint. The keys are expensive not because of the edge detector but because of
the FSM. A key press goes `S_HALT/S_INSN_IN → S_IP → S_HALT/S_INSN_IN`, `dir_q` is loaded
from `key_prev_ip`, `halt_pending_q` is set, and every transition widens the next-state
logic of `state`, `dir_q`, `halt_pending_q` and `insn_valid_q`.

But the IP counter needs only one accepted Clk with the right `dec`. While IpLine stands in
`S_HALT` (or in `S_INSN_IN` waiting for a character), the counter is idle, so:

```systemverilog
assign key_mode = ((state == S_HALT) & halt_rq) |
                  ((state == S_INSN_IN) & insn_loading & ~insn_in_valid);
assign ip_valid = ((in_ip & ~scan_done) | (key_mode & key_step)) & go;
// counter: .dec (key_mode ? key_prev_ip : dir_q)
// S_HALT / S_INSN_IN: on key_step & go only key_moved_q <= 1 (and insn_valid_q <= 0 in S_HALT);
// the state does not change
```

Measured (IpLine alone): **390.4 → 366.5 (−23.9)**, nearly the whole cost of the keys
(TC-O6, −25), and the keys stay. The panel and Appendix B don't change.

Why `key_moved_q` (one trigger) stays, and why a key one-shot doesn't replace it:
- An accepted step must cover exactly one Clk edge. An asynchronous one-shot from the key
  covers either 0 or 1 edges (if shorter than the period), or 1 or 2 edges (if longer).
  Some trigger has to synchronize it, and `key_moved_q` already is that trigger.
- Pulsing the guides straight from a key one-shot, bypassing Clk, doesn't work either. The
  carry latches (`enLatch`, TC-D1) are transparent in every `CmdWin`, even when the machine
  is halted. A guide pulse that isn't aligned to the window lets an upper decade lose its
  enable in the middle of a step. A separate phase generator for the keys would cost more
  than it saves.
- A one-shot is still useful **in front of** the trigger, as a key debouncer, on the panel
  side (outside the count). It doesn't replace the trigger.

## 5. TC-N4: "step, then fetch" always (−34)

IpLine keeps two triggers for the convention that IP points at the **next** instruction
after a reset or a halt:

- `ip_counted_q`: the first fetch after a reset or a halt doesn't step IP;
- `halt_pending_q`: a halt in the middle of the program first steps IP to the next
  instruction, so that the panel shows it (with prefetch, `ip_ahead` suppresses that step).

If IP always points at the **last fetched** instruction and every request is "step, then
fetch", both triggers and their branches go away. The prefetched case is handled by
MachineCtrl: it keeps `pf_q` through the halt, and resumes with `S_HALT → (pf_q ? S_DECODE :
S_IDLE)`, decoding `op_q` without a new fetch.

Measured on top of TC-N3 (IpLine + MachineCtrl): **633.8 → 600.2 (−33.6)**. This is close to
an upper bound: the patch doesn't yet clear `pf_q` when a ±IP key moves IP during a halt
(MachineCtrl would need the two key lines, ≈ +1…2 tubes).

What changes (the owner's decision, since it touches several conventions):

1. **Bootloader**: after a hard reset (IP = 99990) the first instruction runs at 99991. The
   bootloader moves one cell up: `99991: 0<{0<}NNS` (9 cells, LD stays at 99999). It still
   fits the decade, and `HARD_RST_D_CNT` stays 4.
2. **After a soft reset** (IP = 0) the first instruction would run at 1, but the loader writes
   the program from 0 (LD at 99999, step → 0, write). There are two ways out:
   - a) program files start with `N` (NOP at address 0, like the `HE` ending); no hardware cost;
   - b) Soft Reset sets IP to 99999 (all five decades to 9, like the hard reset, plus one
     `WRCH` on decade 0, +0.5 tube). Programs stay at 0, but "Soft Reset: all counters 0"
     changes.
3. **Panel**: in a halt, IP shows the **last executed** instruction, not the next one. The ±IP
   keys move from it. During loading, the keys position IP **before** the cell to be written.
4. dpcrun, IpLine_tb, DekatronPC_tb and the bootloader tests follow.

## 6. TC-N5: a cheaper edge-triggered flip-flop (−95…−108)

The biggest single item. `DFF_J2N16` is two DC-gated RS latches plus a 6N16B for the D and
clock inverters, 3 + 3 + 1 = **7 tubes**. With a scratch liberty where `DFF_J2N16` costs 3.5,
on today's RTL: **1116.5 → 1008.0 (−108.5)**. After N1–N4 + O9 + O4 (27 triggers left):
978.3 → **883.8 (−94.5)**.

How to get there: the classic potential-pulse flip-flop of 1950s tube machines. It has one
bistable (6N16B, Eccles–Jordan) and two 6Zh2B steering gates (g1 = D or ~D, g3 = clock),
the same tubes as `RSLATCH_J2N16`. The difference is that the clock reaches g3 as a **short
pulse through a coupling capacitor**, made by differentiating the Clk edge (one shaper per
clock net, as the inverted clock line already is). The bistable finishes the transition by
regeneration after the pulse has gone, so the cell behaves like an edge-triggered one with
no master latch:

- tubes: 2 × 6Zh2B + 1 × 6N16B = 3. Add 0.5 for ~D when the source isn't another flip-flop
  (a trigger's QN is free, see `doc/tube_count_reduction.md` §2.4);
- hold condition: the clock pulse must end before the earliest new D reaches g1. The
  shortest path is C→Q of the cell itself (RSLATCH: 170–195 ns at fanout 2) plus one gate
  and a divider. So the pulse has to be ≲ 150 ns and still enough to tip the bistable;
- setup: D settled before the pulse, as for the latch (≈ 300 ns at fanout 6).

What has to be done before this can be counted (REQ-MOD-004/005, `doc/cell_design_method.md`):
1. SPICE of the cell (tools/spice, as `dff_sweep.py`): the shortest clock pulse that flips the
   bistable reliably at fanout 2/6/10, and the hold margin against the fastest Q→D path.
2. The pulse shaper: one per clock net (Clk is one net per block). Its skew against the
   cells is the same risk as the shared clock inverter that was rejected for `DFF_J2N16`
   (90 ns race margin).
3. Liberty and SDF: a `DFF` with a real hold time; `vtube_sta.py` checks hold against the
   shortest path; `synth_sim.sh -t` with a negative-margin test.
4. The carry triggers of Data (`zero_q`, `at_top_q`) and the four `op_q` take the same cell.

Risk: medium to high (analog). But the payoff is about the size of everything else in this
report put together, and a cell with this structure (bistable + pentode coincidence gates)
was the standard flip-flop in tube computers.

## 7. Combined

All in a scratch copy, eight seeds:

| Step | IpLine | ApLine | MachineCtrl | Total | Δ |
|---|---|---|---|---|---|
| HEAD | 390.4 | 460.4 | 265.8 | 1116.5 | – |
| + N2 (overflow) | | | | 1091.5 | −25.0 |
| N1 + N2 + N3 + N4 | 330.0 | 446.9 | 245.9 | **1022.7** | −93.8 |
| + TC-O9 (`insn_valid` dropped) | | | | 1009.6 | −13.1 |
| + TC-O4 (CIN through the read bus) | | | | **978.3** | −31.3 |
| + TC-N5 (DFF at 3.5, scratch liberty) | | | | **883.8** | −94.5 |
| N1–N4 + TC-N5, without O9/O4 | | | | 924.7 | |

So **below 1000 is reachable without a new cell**, with only the requirement changes of
N2, N4, TC-O4 and TC-O9. TC-N5 then gives a margin of about 100.

## 8. Smaller ideas and dead ends

| ID | Idea | Result |
|---|---|---|
| TC-N6 | **Coincidence write matrix.** The Data write decoder (`BcdToBinEn` + enable) costs ≈ 22 tubes per decade, i.e. ten 4–5-input ANDs. If each write channel did a 2-input AND itself (a triode whose cathode returns to a "column" line, or a 6Zh2B with g1/g3), the decoder would shrink to 5 "row" lines from b3 b2 b1 and 2 "column" drivers (En·~b0, En·b0): ≈ 8–10 tubes per decade. With N1 only tens and ones are full decades | ≈ −20…−30, **not measured**. It needs a new write-channel cell and SPICE inside the narrow Uсм window (12…13 V, TRS v0.38). This is the next analog item after N5 |
| TC-N7 | `NOR5_N16` (a 5-triode NOR, 2.5 tubes) for bit 0 of `BinToBcdN` | −4 (8 seeds): ABC already maps NOR5 well enough. Not worth a cell |
| – | Vacuum-diode (6Kh7B) OR matrix as the BCD encoder, merged with the read diodes | ≈ −2 per decade once the output stage is added (15–17 diodes + 4 triodes against 10 diodes + 15 triodes). Small, and REQ-AUTH-002 bans diode codecs (the ban was written for germanium, but it says codecs). Not recommended |
| – | Drop the `GUIDE_EN_J2` key of decade 0 (`En` = 1) | It is also the guide driver of that decade, so a driver stays. No gain |
| – | Data `zero_q`/`at_top_q` as latches transparent while Clk is low | ≈ −7. The step plus fall ends ≈ 5.5 µs after the edge, so it would need a 60/40 Clk duty. TC-N5 covers it more cheaply |
| – | `op_q` as latches (T7) | The latch would be open while `op_end` is high, and `op_end` depends on `op_q` (`cout_echo`), so it forms a loop. It needs an extra trigger, and TC-N5 covers it |
| – | One-hot memory address (R9), external loader (TC-O7) | rejected by the owner earlier |

## 9. Recommended order

1. **TC-N1** (no requirement change, −12): do it now.
2. **TC-N3** (keys stay, −24): do it now; the IpLine_tb key tests have to follow.
3. **TC-N2** (−25): needs the REQ-CNT-007 wording; owner's decision.
4. **TC-O9** (−13 in this combination): IpLine_tb rework only.
5. **TC-N4** (−34): owner's decision on the bootloader shift and option a) or b) of §5.
6. **TC-O4** (−31 here): REQ-UART-008, as recommended in `doc/tube_count_1000.md` §6.1.
7. **TC-N5**: start the SPICE work on the capacitor-clocked flip-flop. Highest payoff, longest road.

Steps 1–6 give ≈ 978 (eight seeds, synthesis only).

## 10. How it was measured

- Scratch copy of `rtl/{parameters.sv,DekatronPC,Functions,Logic,programs/bootloader}`; one
  patch per option; `rtl/run/synth_seeds.sh -f <copy>/DekatronPC/DPC.files -s "0 1 2 3 4 5 6 7"`.
- Cell what-ifs with `DPC_CELL_LIB` = a copy of `vtube_cells.lib` (`NOR5_N16` added, or
  `DFF_J2N16` area 7 → 3.5).
- The combined patch (N1–N4 + O9 + O4) is `doc/data/tube_count_n_experiments.patch`. It is a
  measurement aid, not a finished change: no simulation, no tests, no dpcrun.

## 11. TC-N1 done (TRS v0.44)

`DekatronModule` has a parameter `MAX_DIGIT` (default 9). `DekatronCounter` gives the top decade of
a counter with a limit (`TOP_LIMIT_MODE`) the top digit of `TOP_VALUE`, so the hundreds of Data get 2.
Above `MAX_DIGIT`, the module places no read diode and no write channel, and the decoder outputs
are masked (`WritePos & DIG_MASK`). The dekatron model gets no write position there either, as in
the hardware, and those lines go into the encoder as 0.

The full change saves more than the experiment of §2 (−12). There, the decoder outputs 3–9 still
fed the dekatron model's `write_pos_i` (a black box in synthesis), which kept them alive. With the
mask they go away, as the write channels do.

`synth_seeds.sh -s "0 1 2 3"`:

| Seed | IpLine | ApLine | MachineCtrl | Total |
|---|---|---|---|---|
| 0 | 384.5 | 430.5 | 268.0 | 1083.0 |
| 1 | 389.0 | 430.0 | 270.0 | 1089.0 |
| 2 | 386.5 | 431.5 | 268.5 | 1086.5 |
| 3 | 384.0 | 431.5 | 266.0 | 1081.5 |
| mean | | | | **1085.0** (was 1115.5, −30.5) |

Seed 0 in `run_tests.sh -s`: 1083.0 tubes (6N16B 624.5, 6Zh2B 379, 6Kh7B 63.5) + 15 A110.

Checks: `run_tests.sh -t` (Icarus, Verilator against dpcrun on helloworld, program.bfk, pi.bfk),
`-d` (delay model, incl. pi.bfk), `-s`, `synth_sim.sh` 7/7, `synth_sim.sh -t` 4/4 with 0 setup and
0 hold violations, cocotb `make regression` 34/34; STA 8.10 µs (100 kHz meets, 1.9 µs slack).
SCHEMES sheet 2 notes the channels and diodes up to `MAX_DIGIT`.
