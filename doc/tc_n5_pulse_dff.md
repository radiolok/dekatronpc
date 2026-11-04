# TC-N5: pulse-clocked D flip-flop on a Bonch-Bruevich bistable (SPICE study)

Status: **cell built** (2026-11-04): `sch/logic/DFFP2_J2N16` (KiCad sheets, testbench, page), liberty cell `DFFP_J2N16` (`dont_use`, placed by the RTL). Owner's answers to §7 (2026-11-04): plate chokes yes; two flip-flops per sheet (the tube count is odd); the clock tree is not designed yet, so either edge is fine, but one driver cannot carry every trigger; first use: the panel-key synchronizers. Still open: the D-pin load (§4.5, at most two per net).

- Requirements: REQ-MOD-005 (D flip-flop board), REQ-MOD-004 (delays, simulated, not measured), REQ-MOD-012 (levels), REQ-AUTH-* (no silicon: the steering is done by pentodes, not by diodes).
- Source: the owner, 2026-11-03: "make a new cell on the D LATCH base, using the Bonch-Bruevich trigger, that switches only on the clock edge"; `doc/tube_count_below_1000.md` §6 (TC-N5, −95…−108 tubes).
- Method: `doc/cell_design_method.md`. Scripts: `tools/spice/pff_sweep.py`, `tools/spice/pff_timing.py`.

## 0. Result in one table

| | `DFF_J2N16` (today) | Proposed pulse flip-flop |
|---|---|---|
| Structure | two RS latches (master-slave) + D and C inverters | **one** RS latch (Bonch-Bruevich bistable + two 6Zh2B steering gates) + D inverter; the clock reaches g3 as a pulse through a capacitor |
| Tubes | 7 | **3.5** (2 × 6Zh2B + 1.5 × 6N16B); 7 for a pair sheet sharing the inverter tube |
| Edge | falling C (synthesis adds a clock inverter per net) | **rising** edge of the HV clock line, no inverter |
| D pin | LV (net divider) | **HV**: the cell has its own dividers (the delay, §4) |
| C pin | LV, 17.5 pF of divider C1 | HV clock line, 3.9 pF in series with the g3 node |
| C→Q, fanout 2 / 6 | 340 / 441 ns (to 100 V) | **51…95 / 122…158 ns** (to 100 V) |
| Setup, fanout 2 / 6 (worst of four cases) | 310 ns (fanout 6) | 341 / 527 ns (D pin to clock line, both at 100 V) |
| Hold, fanout 2 / 6 | 0 | −150 / −3 ns |
| Race margin | ≈ 90 ns (inverter skew, `--cskew`) | ≈ 54 ns (fastest C→Q 51 ns − hold −3 ns, sink at fanout 6); a shift register at fanout 6 takes 120 ns of clock skew |
| Register to register, fanout 2 / 6 | 1.11 / 1.05 MHz | ≥ 1.0 / 0.83 MHz (passes 1.0 / 1.2 µs, §4.3) |
| Lowest grid | −31.9 V | −40.2 V (g3, on the falling clock edge) |
| Extra parts per cell | — | 2 × La 1 mH (plate chokes), Cc 3.9 pF, 4 resistors of the slow dividers, 2 of the g3 bias |

Machine-level gain from `doc/tube_count_below_1000.md` §6 (a scratch liberty with the flip-flop at 3.5): about −95 tubes on 27 triggers. The 32 triggers of today plus the key synchronizers of TRS v0.49 make it more.

## 1. The idea

The Bonch-Bruevich trigger (Eccles–Jordan) is the bistable already inside `RSLATCH_J2N16`: two triodes of one 6N16B with cross-coupled grids. In `RSLATCH_J2N16` two 6Zh2B pentodes steer it: g1 takes S or R, g3 takes the enable E, and the pentode conducts to its plate only when both are high. `DLATCH2_J2N16` makes it a D latch with S = D, R = ~D.

The pulse flip-flop keeps that D latch and changes only the enable: g3 gets a **short pulse** cut from the rising edge of the clock by a capacitor. The pentode chosen by D pulls its plate down for the length of the pulse; the bistable passes its point of no return and finishes the transition by regeneration after the pulse has gone. The cell is transparent only for the length of the pulse, so it acts as an edge-triggered flip-flop without a master latch.

## 2. Why the plain version does not work

First try: the D latch as it is (D on the pentode g1 through the usual net divider, ~D from the inverter), g3 on the RC pulse network. Two numbers decide:

| | fanout 2 | fanout 6 | fanout 10 |
|---|---|---|---|
| Shortest g3 pulse that flips the bistable (`pff_timing.py wmin`, no chokes) | 192 ns | 353 ns | 533 ns |
| Fastest C→Q of the cell (the falling output: the pentode pulls the plate at once) | 68 ns | | |

The pulse has to be longer than the flip (353 ns at fanout 6), but the new D of the next stage arrives after the source's C→Q (68 ns). The next stage then sees its new D while its gate is still open and takes it: race through. The shift-register runs failed both ways: short pulses did not flip the bistable (QN dropped only to 127 V), long ones raced. The flip time and C→Q are of the same order because both are set by Ra·C of the loaded plate. The tube machines of the 1950s had the same problem and solved it with a delay in the data path (delay lines, or a capacitor holding the gating potential). That is the only way here as well.

## 3. Options evaluated

All on the shift register (two cells on one clock line, the first Q drives the second D, `pff_sweep.py shift`) and by bisection (`pff_timing.py`). "Fanout" is the number of triode grids on each output net.

| Option | Result | Verdict |
|---|---|---|
| D latch, LV D pin, g3 pulse (§2) | flip 192 / 353 / 533 ns, race through at every pulse length | rejected |
| Rd / Cd (47k…150k, 2.2…4.7 pF) in series with each g1 | 47k / 2.2p passes at 4 µs; more delay fails: the g1 charges from the **clamped** "1" of the D pin (+0.3 V, the inverter grid draws grid current), so it creeps towards it and never opens the pentode fully | rejected |
| Clock on g1, D on g3, Rg2 3.3k (a cut-off pentode allows a stiff screen) | flip 194 / 301 ns: the flip is set by the plate Ra·C, not by the pentode current | not pursued |
| **HV D pin, in-cell dividers without C1** (the S-gate g1 and the R-gate g1 each behind an uncompensated divider; the inverter grid on a normal one) | 470k / 200k: hold −81 ns, setup 1.4 / 1.9 µs (too slow); 100k / 43k: hold +188 ns at fanout 6 (race) | the delay works: the divider charges the g1 towards +10 V and stops at the clamp, so there is no tail |
| + plate chokes La 1 mH and Rg2 12k (`RSLATCH_J2N16` page, "Speed-up options") | flip 93 / 211 ns instead of 197 / 360 ns | **taken**: halves the delay the D path needs |
| Slow dividers with the chokes: 470k / 235k / 180k / **150k** / 100k (pulse 430 ns) | setup at fanout 6: 1.30 / 0.63 / 0.83 / **0.47** µs; hold: < −100 / < −100 / −3 / **−23** ns (1.5 µs: race) | **150k / 62k** |
| Pulse length (Rth 15k / 22k / 33k) with 150k / 62k | 240 / 330 / 430 ns pulse: hold +25 / −13 / −23 ns, setup 755 / 593 / 473 ns at fanout 6 | **Rth 33k**: a pulse well above the flip time finishes it sooner, so both limits get better |
| Cc 4.7 pF → 3.9 pF | lowest g3 −43.7 → −39.8 V (−40.2 V with the E24 bias 43k / 130k); hold −23 → −3 ns, setup 473 → 527 ns | **3.9 pF** (10 V margin to −50 V) |

## 4. The proposed cell

### 4.1 Schematic

```
                +150 V                                    +150 V
                  │ Ra 10k + La 1 mH                        │ Ra 10k + La 1 mH
  QN ─────────────┼───────────────┐         Q ──────────────┼───────────────┐
        6Zh2B (Л1)          6N16B A                6Zh2B (Л2)          6N16B B
        g1 = S, g3 = G      grid = FQ              g1 = R, g3 = G      grid = FQN
        g2: Rg2 12k to +150 V                      g2: Rg2 12k to +150 V
  feedback: Q → 470k‖3.9p → FQ → 200k → −50 V;  QN → 470k‖3.9p → FQN → 200k → −50 V   (as RSLATCH_J2N16)

  D (HV pin) ──150k──┬──62k── −50 V       S: no C1, the g1 node (≈ 5 pF) makes the delay
                     └── S
  D ──470k‖3.9p──┬──200k── −50 V ── grid of the inverter (½ 6N16B, Ra 10k) ── DN
  DN ──150k──┬──62k── −50 V               R: no C1
             └── R
  CK (HV clock line) ──3.9p──┬── G (both g3)
                             ├── 43k ── GND
                             └── 130k ── −50 V        rest −12.4 V, Thevenin 32.3k
```

- The g3 node rests at −12.4 V: both pentodes are cut off to the plate, and a pentode with g1 high sends its current to the screen, as `RSLATCH_J2N16` with E low.
- The rising HV clock edge (100 V) lifts G through 3.9 pF into the g3 grid-current clamp (+12 V peak through the 5k of the model's g3 diode). G then decays to −12.4 V with τ ≈ 32k × (3.9 + ≈ 10) pF ≈ 450 ns: the pulse is 380…430 ns above −5 V. The falling clock edge throws G to −40.2 V, which cuts the pentodes harder and does nothing else.
- Tubes: 2 × 6Zh2B + 1 × 6N16B (bistable) + ½ 6N16B (D inverter) = **3.5**. Two cells on one sheet share the inverter tube (7 tubes per two flip-flops, as `DLATCH2_J2N16`).
- The bistable is `RSLATCH_J2N16` with the speed-up of its page (La 1 mH + Rg2 12k). The pulse network and the slow dividers are new.

### 4.2 Timing (`pff_timing.py`, chosen values)

Fanout = triode grids on Q and on QN (plus the cell's own feedback divider). Delays from the clock line crossing 100 V to an output crossing 100 V; setup and hold between the D pin crossing 100 V and the clock line crossing 100 V. Hold and setup are the worst of the four cases (state before the edge 0/1, value taken 0/1). The case that limits hold is "0 → 1": D falls early, and the S pentode loses its g1 before the flip has finished. The race case "0 → 0" (D rises early and opens the wrong gate) has 400…600 ns of margin.

| Fanout | Shortest pulse | C→Q set (Q↑ / QN↓) | C→Q reset (Q↓ / QN↑) | Setup | Hold |
|---|---|---|---|---|---|
| 2 | 103 ns | 95 / 52 ns | 51 / 95 ns | 341 ns | −150 ns |
| 4 | 160 ns | 126 / 83 ns | 81 / 126 ns | 420 ns | −91 ns |
| 6 | 226 ns | 158 / 125 ns | 122 / 158 ns | 527 ns | −3 ns |

The pulse (380…430 ns) is 1.7 times the shortest flip at fanout 6. Fanout 10 needs a 533 ns pulse without chokes; with them it was not checked, so the cell is proposed with **max_fanout 6**, as `DFF_J2N16`.

### 4.3 Shift register (`pff_sweep.py shift`)

Two cells on one clock line, the first Q drives the second D and N−2 more grids; D of the first changes a quarter period after the edge. A sampled level passes only if it is valid for the next stage ("1" > 118 V, "0" < 92 V).

| | fanout 2 | fanout 4 | fanout 6 |
|---|---|---|---|
| Period 4.0 / 1.5 / 1.2 µs | OK / OK / OK | OK / OK / OK | OK / OK / OK |
| Period 1.0 µs | OK | OK | **fails** |
| Second cell clocked 100 / 120 ns late (period 4 µs) | OK / OK | OK / OK | OK / OK |
| Second cell clocked 150 ns late | OK | OK | **fails** (race through) |
| g3 pulse above −5 V | 403 ns | 394 ns | 385 ns |
| Lowest g3 | −40.2 V | −40.2 V | −40.2 V |

Register to register is 0.83 MHz at fanout 6 and at least 1 MHz at fanout 2–4, without logic between the flip-flops. The skew limit agrees with the bisection: the source's fastest C→Q at fanout 6 is 122 ns and the sink's hold −3 ns, so the second cell may be clocked up to ≈ 125 ns late. With a source at fanout 2 (C→Q 51 ns) the same margin is 54 ns, which is the figure to use for clock distribution.

### 4.4 Tolerances

Shift register at 2 µs with the second cell clocked 50 ns late, fanout 2 and 6, around Rth 33k / rest −12 V (the values before rounding to E24 43k / 130k): every case passes.

| Case | Pulse (fanout 6) | Lowest g3 | Result |
|---|---|---|---|
| nominal (no skew) | 396 ns | −38.8 V | OK |
| 6Zh2B MU2 +20 % / −20 % | 393 / 400 ns | −39.1 / −39.2 V | OK |
| 6N16B MU −20 % | 394 ns | −39.1 V | OK (VOL 47 V) |
| La 0.8 / 1.2 mH | 396 / 397 ns | −39.2 / −38.9 V | OK |
| Cc 3.5 / 4.3 pF (±10 %) | 378 / 414 ns | −37.0 / −41.0 V | OK |
| Rth 30k / 36k (±10 %) | 367 / 426 ns | −39.2 / −39.0 V | OK |
| all divider C1 +10 % | 397 ns | −38.7 V | OK |
| clock line edge 100 / 200 / 300 ns (Cc 4.7 pF, Rth 33k, before the final values) | 468 / 531 / 596 ns | −41 / −39 / −36 V | OK: a slower edge gives a longer pulse |

### 4.5 Levels and loads

- Output levels as `RSLATCH_J2N16`: "1" 143.9 V, "0" 55.1 V.
- Lowest grids: g3 −40.2 V (falling clock edge), S/R g1 −22.4 / −19.2 V, feedback grids −25.4 V.
- Screen: Rg2 12k gives Pg2 0.47 W (limit 0.6 W) and Ik 12.0 mA static (limit 14 mA), as measured for the same latch on the `RSLATCH_J2N16` page. Transient Ik peaks to about 17 mA for < 100 ns.
- **The HV D pin is a DC load** on the net that drives it: the slow divider takes 0.9 mA, the inverter's divider 0.29 mA. A plate with Ra 10k, its own 470k/200k feedback divider and the net divider gives "1" = 144 V alone, 133 V with one D pin of this cell, 123 V with two, 115 V with three. The next stage needs "1" > 118 V, so **at most two D pins of this cell per net**. In the liberty: `fanout_load` 3 on D against `max_fanout` 6.
- The clock line sees 3.9 pF in series with ≈ 10 pF per cell (≈ 2.8 pF). Thirty cells are ≈ 85 pF, plus wiring. The cell works with edges up to 300 ns, so a cathode follower per clock net is enough. The clock skew between the cells of one clock net must stay below the race margin, about 50 ns.

## 5. What the cell changes in the flow (not done)

- **Liberty** (`sch/logic/vtube_cells.lib`): a new cell, `ff(IQ, IQN) { clocked_on: "C"; next_state: "D"; }`, area 3.5. The D pin needs a new level, e.g. `vtube_level: HV_IN` (the cell has its own dividers); `div_insert.py` must place no divider for it, count its DC load, and check that at most two such pins share a net. C is the HV clock line (no divider either).
- **Synthesis**: `dfflibmap` picks the rising-edge cell directly, so the clock inverters `opt_merge` keeps today (one `NOT_N16` per clock net and module) go away. The clock line driver belongs to the clock generator board.
- **Timing** (`vtube_timing.json`, `vtube_sdf.py`, `vtube_setuphold`): `posedge C->Q` [rise, fall] ≈ [158, 125] ns to 100 V at fanout 6 (to the next stage's thresholds 118 / 92 V, still to be measured with `threshold_delays.py`), setup 527 ns, hold 0 (−3 measured). STA today needs 8828 ns, set by the path from the dekatron cathodes to a trigger D (`rtl/run/sta/DekatronPC_sta.md`). With this cell that path gains about +200 ns of setup and loses the clock inverter, so it stays below 10 µs (100 kHz); trigger to trigger becomes shorter.
- **KiCad**: the cell sheet and testbench (generator in `tools/kicad/`, like `gen_latch_j2n16.py`), and the cell page `sch/logic/<CELL>/README.md` with the figures.

## 6. Open points

- Measure on hardware: the pulse length, the shortest flip and the C→Q of the falling output (the race margin is 54 ns in SPICE; REQ-MOD-004, OPEN-013).
- The g3 grid current of the 6Zh2B (the clamp that shapes the pulse) is a model assumption (`sch/libs/6Zh2B.sub`, RG3 5k).
- Fanout 10, and a sink at fanout 6 driven by a source at fanout 2 measured directly (the bisection covers it as hold vs C→Q, the shift register only for equal fanouts).
- An asymmetric S path (180k / 75k for S, 150k / 62k for R) moves hold at fanout 6 by about −30 ns for about +80 ns of setup, if the race margin has to grow.
- Asynchronous clear / preset: today's `DFFRN` / `DFFSN` put a 6Kh7B diode on the feedback grid; the same works here (TRS v0.33 left no asynchronous reset on the glue triggers, so it is not needed now).

## 7. Decisions for the owner

1. The **HV D pin** with the delay dividers inside the cell, and the rule "at most two such D pins per net".
2. **Plate chokes** 1 mH (2 per flip-flop) and Rg2 12k. Without them the D path needs about twice the delay, and setup grows to 1–2 µs.
3. The **clock as an HV line** (rising edge, per-cell Cc 3.9 pF and bias network), a follower per clock net on the generator board, skew within a net below about 50 ns.
4. Cell name and packaging: one cell of 3.5 tubes, or a two-flip-flop sheet of 7 tubes (one inverter tube for both), as `DLATCH2_J2N16`.
5. What it replaces: every `DFF_J2N16` in the synthesis, including the key synchronizers of TRS v0.49.

## 8. Files and how to run

| File | What |
|---|---|
| `tools/spice/pff_sweep.py` | the cell netlist `pff()` (chosen values in `P`, the options of §3 as keys), `single` and `shift` (register to register, `skew=`) |
| `tools/spice/pff_timing.py` | `wmin`, `tcq`, `hold`, `setup` by bisection; four cases for hold and setup |

```
python3 tools/spice/pff_timing.py wmin 2 4 6
python3 tools/spice/pff_timing.py tcq 2 4 6
python3 tools/spice/pff_timing.py hold 2 4 6
python3 tools/spice/pff_timing.py setup 2 4 6
python3 tools/spice/pff_sweep.py shift --period 1.2 2 4 6
python3 tools/spice/pff_sweep.py shift skew=100 2 4 6
python3 tools/spice/pff_sweep.py shift La=0 R1s=470k R2s=200k 2 6    # an option of §3
```

The decks use `.options method=gear`: with the plate chokes the default trapezoidal method stopped on "timestep too small" at the clock edge in some cases. A deck that still hangs is cut after 180 s and counted as a failure.
