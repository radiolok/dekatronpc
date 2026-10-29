# DFF_J2N16: master-slave D flip-flop on 6Zh2B + 6N16B

Cell page. The falling-edge D flip-flop built from two [RSLATCH_J2N16](../RSLATCH_J2N16/README.md) sub-sheets (master and slave) plus one 6N16B for the D and clock inverters. The latch design (structure, part values, levels, limits, sensitivity) is on the RSLATCH page; this page holds only what the flip-flop adds. To become a base cell of the liberty file (owner, 2026-10-27); the liberty entry below is only proposed.

- Requirements: REQ-MOD-005 (D flip-flop board), REQ-MOD-012 (logic levels), REQ-MOD-004 (delays, fan-out, power; simulated, not measured), REQ-MOD-008 (`DFF` → tube cell).
- Method: `doc/cell_design_method.md`.
- Source: the owner's drawing of 2026-10-27: two RS latches plus inverters for D and the clock.

| | DFF_J2N16 |
|---|---|
| Function | Q ← D at the **falling** edge of C |
| Tubes | 2 × RSLATCH + 1 × 6N16B (D and C inverters) = 7 |
| Inputs (LV) | D (g1 + triode grid), C (two g3 + triode grid) |
| Outputs (HV) | Q, QN |
| Heater 6.3 V | 2.0 A (12.6 W) |
| Output levels | 1: 141.8…143.9 V; 0: 36…55 V (as RSLATCH) |
| Speed, fanout 2 / 6 / 10 | C↓→Q 340 / 441 / 539 ns; register to register 1.11 / 1.05 / 0.93 MHz |
| Timing limits, fanout 2 / 6 / 10 | hold ≤ 0; race margin ≈ 90 ns at C↑ |
| Lowest grid | −31.9 V (D) |

A 16-tube board takes two DFF_J2N16, with two tubes spare (owner, 2026-10-27).

## Schematic

`DFF_J2N16.kicad_sch`. Master M: S = D, R = ~D, E = C. Slave S: S = QM, R = QNM, E = ~C. The master outputs reach the slave inputs through their own 2.7 pF dividers:

![DFF_J2N16](img/latch_dff_cell.png)

The master outputs go through separate dividers instead of reusing the feedback dividers, because KiCad keeps one value per sheet file for all instances (`doc/cell_design_method.md` §4): the master and the slave must be the same RSLATCH sheet, `../RSLATCH_J2N16/RSLATCH_J2N16.kicad_sch`.

## Results

### Delay against fanout

![delays and clock limit](../RSLATCH_J2N16/img/latch_fanout.png)

| Grids on each output | DFF C↓→Q | DFF reg→reg |
|---|---|---|
| 2 | 340 ns | 1.11 MHz |
| 4 | 391 ns | 1.10 MHz |
| 6 | 441 ns | 1.05 MHz |
| 8 | 490 ns | 0.99 MHz |
| 10 | 539 ns | 0.93 MHz |

- Register to register (`dff_sweep.py shift`): two DFFs in a row on one clock, D of the first changing a quarter period after the edge. A sampled level passes only if it is valid for the next stage ("1" > 118 V, "0" < 92 V).
- The latch delays, the shortest E pulse and the setup time are on the RSLATCH page.

### Testbench (1 MHz, fanout 6)

![DFF testbench](img/latch_dff_tb.png)

![DFF waveforms](img/latch_dff_tran.png)

`DFF_J2N16_tb.kicad_sch` runs a 16-bit pattern at 1 MHz, with D changing 0.25 µs after each falling edge of C. Every sampled bit is correct. The worst sampled levels, 30 ns before the next edge, are "1" ≥ 132 V and "0" ≤ 70 V, which leaves 22 V to the next stage's VIL. C↓→Q is 460 ns. KiCad and plain SPICE agree on all 45 values.

The waveforms show:

- the master following D while C is high;
- ES (= ~C after the inverter and its divider) opening the slave after C falls;
- Q settling within the period.

## The flip-flop: which edge

The owner's drawing puts the master on C and the slave on the inverted C, so Q changes at the falling edge of C. The liberty `DFF` cell says `clocked_on: C` (rising edge). Both variants were simulated (`dff_sweep.py --edge neg|pos`). They use the same parts; only the clock wires to the two latches swap.

| | Falling edge (drawing) | Rising edge (master on ~C) |
|---|---|---|
| Register to register, fanout 2 / 6 / 10 | **1.11 / 1.05 / 0.93 MHz** | 0.99 / 0.77 / 0.58 MHz |
| C→Q, fanout 2 / 10 | 340 / 539 ns | 192 / 400 ns |
| Hold (D changing at the capturing edge) | **≤ 0** (passes with D switching together with C) | > 0: fails at 0 ns, passes at 40 ns |
| Overlap of the two latches | at the non-capturing edge C↑: the master opens at once, the slave closes after the inverter | at the capturing edge C↑: the slave opens at once, the master closes after the inverter |

Why the falling edge is faster:

- The slave has to latch the external load while its enable is open, and needs an E pulse of 333 ns at fanout 6.
- A direct C net is high for less than half a period, because the LV net rises slowly (the driver's plate charges through Ra) and falls fast.
- The slave behind the inverter gets a wider window.
- With the master on ~C, the same narrowing hits the slave on the direct C, and it runs out of window first.

**Owner's decision (2026-10-27): falling edge, as drawn.** For the RTL's rising-edge flip-flops, invert the clock once at the generator.

### Race margin at C↑

When C rises, the master opens immediately while the slave closes only after the inverter:

- ES crosses −5 V 64 ns after C crosses −5 V;
- the master's output reaches the slave grids (−5 V crossing) after 153 ns.

The margin is about 90 ns. An extra 200 pF on the inverter plate (`dff_sweep.py --cskew 200`) makes the new D race through to Q. **The C inverter must stay inside the cell and lightly loaded.** A shared inverter in the clock tree would add exactly this skew.

## Options evaluated

| Option | Result | Verdict |
|---|---|---|
| Rising-edge DFF (master on ~C) | 0.58–0.99 MHz, hold > 0 | rejected (owner chose the falling edge) |
| Clock inverter shared by many flip-flops (6.5 tubes per bit) | eats the 90 ns race margin at C↑ | rejected |
| Dual-rail D (D and ~D from the driving cell, 6 tubes per DFF) | saves the D inverter, but the liberty function cannot ask synthesis for a complement | left for later (see Open points) |

On iverilog: the failure that decided the flip-flop design is analog. The clock window shrinks on a slow LV rise, and the race margin depends on how far a grid sits below its clamp. A logic simulator with delays does not see either, while a plain-SPICE run of the whole flip-flop takes a few seconds. iverilog becomes useful once the cells are in the liberty file: the cell models in `sch/logic/vtube_cells.v` and the SDF delays from `vtube_timing.json` can then check setup, hold and the 1 MHz budget on synthesized netlists (`synth_sim.sh -t`).

## Proposed liberty entry (not applied)

Waiting for the owner's review (owner, 2026-10-27: proposal only). "fanout_load" is in units of a triode grid (C1 3.9 pF).

```
cell(DFF)    -> rename DFF_J2N16: ff clocked_on: "C'" (falling edge), area 7, J2B 4 + N16B 3, heat 2000;
                D fanout_load 1.7, C fanout_load 4.5 (two g3 + triode grid), max_fanout 6.
```

Proposed `vtube_timing.json` values (fanout 6, simulated): DFF C↓→Q 0.44 µs, setup 0.31 µs (the master's setup before C falls), hold 0. With `max_fanout` 6 the flip-flop meets 1 MHz register to register without logic between the flops. Any logic between them needs a slower clock, or it has to be counted against the 1 µs period.

Changing DFF to the falling edge in the liberty also needs one clock inverter in the RTL flow (at the generator), and `sch/logic/vtube_cells.v` must change to match (AGENTS §6).

## Files and how to run

| File | What |
|---|---|
| `DFF_J2N16.kicad_sch` | cell sheet (two RSLATCH sub-sheets) |
| `DFF_J2N16_tb.kicad_sch/.kicad_pro` | testbench |
| `tools/kicad/gen_latch_j2n16.py` | generator of the sheets of all three latch cells |
| `tools/spice/dff_sweep.py` | DLATCH / DFF / shift register, `--edge`, `--period`, `--cskew` |
| `tools/spice/latch_tb.py` | testbench definitions shared with KiCad, plain-SPICE reference |
| `tools/spice/latch_plots.py` | every figure on this page, and the numbers of the tables |

```
python3 tools/spice/dff_sweep.py shift --edge neg --period 1.0 2 6 10
tools/spice/sim_kicad.sh sch/logic/DFF_J2N16/DFF_J2N16_tb.kicad_sch
python3 tools/spice/latch_tb.py dff                     # the same bench in plain SPICE
python3 tools/spice/latch_plots.py                      # figures into sch/logic/<CELL>/img
```

To embed the cell: the inputs come from HV nets through the usual divider. The D pin is a pentode g1 plus a triode grid (C1 6.6 pF); the C pin is two g3 plus a triode grid (17.5 pF).

## Open points

- **Liberty update** after the owner's review (above): the falling-edge DFF with one clock inverter at the generator.
- **Measure on hardware**: C↓→Q and the race margin at C↑ (REQ-MOD-004). The margin depends on the inverter and the 6Zh2B g3 cut-off, neither of which is calibrated.
- **Dual-rail data**: a DFF variant taking D and ~D (6 tubes) where the source is another flip-flop. This needs a synthesis-side rule; it is not in the liberty yet.
- **Reset/preset** (liberty `DFFSR`): not designed. A third input on each NOR (another triode on the plate) would set or clear the slave and the master; ask before adding tubes.
