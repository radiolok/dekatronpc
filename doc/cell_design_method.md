# How to design a tube logic cell

The method is distilled from the first cell, NOR2_N16 (`doc/nor2_n16_6n16b.md`), and extended with the second, NAND2_J2 on a 6Zh2B pentode (`doc/nand2_j2_6zh2b.md`), and the third, NOT_N16 (`doc/not_n16_6n16b.md`). Use it for BUF_N16, OR2_N16 and the rest of REQ-MOD-003. Each step lists what to do, what to check, and the traps already hit once.

Requirements: REQ-MOD-012 (levels), REQ-MOD-004 (delays, fan-out, power), REQ-MOD-005 (boards), REQ-AUTH-* (no silicon).

## 0. Inputs to collect before drawing anything

| Input | Where | NOR2_N16 example |
|---|---|---|
| Logic function, tube count | liberty `rtl/vtube/vtube_cells.lib` (`function`, `tubes`) | Y = ~(A \| B), one 6N16B |
| Level families | TRS REQ-MOD-012 | HV on plates 1 = +150 V, 0 = +50 V; LV on grids 1 = +10 V, 0 = −20 V |
| Supplies | TRS REQ-MOD-012, REQ-PWR-* | +150 V, −50 V, heater 6.3 V |
| Input and output family of the cell | the cell's role | in LV (grids), out HV (plate) |
| Tube limits | datasheet, link it on the cell page | 6N16B: Ua ≤ 200 V, Pa ≤ 0.9 W, Ik ≤ 14 mA, Ug ≥ −50 V, Rg ≤ 1 MΩ, Pg ≤ 0.1 W |
| Fanout target | liberty `max_fanout` | 10 |
| Clock | TRS (1 MHz, OPEN-014) | 1 µs |

Ask the owner before deciding anything that changes levels, supplies or the tube count of a cell (AGENTS §1). The first NOR2 attempt was done on a wrong reading of the levels and had to be redone. Read the level spec back to the owner in one line before designing.

The level families and how cells join:

- An HV output drives grids through a divider R1 ‖ C1 / R2 to −50 V with ratio 0.3 (470k / 200k): +150 → +10, +50 → −20.
- One divider serves one HV net. All grids on that net share it, and C1 = 3.9 pF per grid.
- LV → HV conversion is always a tube stage. The cell is one.

## 1. The tube model

1. Redraw the tube's reference sheet as a page first, the way `doc/6n16b_datasheet.md` does for the 6N16B:
   - tables transcribed;
   - curves digitized into `doc/data/<tube>_datasheet.json`;
   - plots drawn by a script (`tools/spice/datasheet_6n16b_plots.py` as the template);
   - a model comparison.

   Digitizing: render the PDF at 300 dpi, calibrate the grid, separate curves from grid lines by thickness (curves ~5 px, grid 2–3 px), assign points to curves (by order along a row, or within a guided band), and always overlay the points on the scan before trusting them. Values read by eye without the overlay were off by 10 V on the first attempt.
2. Take the model from `sch/libs/<tube>.sub` and check it against the datasheet before trusting any result:
   - at least one operating point (Ia at the datasheet Ua and Ug);
   - transconductance S around that point;
   - one point on the Ia = f(Ua) curve at Ug = 0.

   The model has to land inside the datasheet spread. Use a short `.dc` deck run with `tools/spice/ngrun.py`.
3. Check the pinout three ways: datasheet drawing, KiCad symbol pin numbers, and the `Sim.Pins` map (`symbol_pin=subckt_pin`, e.g. `1=Pa 7=Ga 6=Ka 5=Pb 3=Gb 2=Kb`). Leave heater pins out of `Sim.Pins`. The old 6N16B map mixed the two triodes.
4. Write the model for ngspice:
   - No PSpice-only functions: `PWRS` → `PWR(MAX(x,0),EX)`.
   - `LOG` is the natural log.
   - Put 1 GΩ from each plate to its cathode, so no node floats.
5. The neon model in `sch/libs/neon.sub` uses LTspice-only `SW` parameters (`Vser`). For ngspice use a switch with hysteresis: strike voltage on, hold current off.
6. Library files under `sch/libs` use CRLF line endings. Keep them: `open(..., newline='')`, or `sed -i 's/$/\r/'` after a rewrite.

## 2. Find the circuit in plain SPICE first

Iterate in plain decks, not in KiCad. A deck run takes seconds and sweeps run in parallel.

- `tools/spice/ngrun.py deck.cir` runs any deck through KiCad's `libngspice.so.0`; no ngspice binary is needed.
- `tools/spice/nor2_sweep.py [cases.py]` is the transient sweep harness. Copy it for a new cell and change `nor()` to the new cell's netlist. A `cases.py` defines `CASES = [(name, params), ...]` and `GRIDS`.

Order of work:

1. **Static (`.op`) search over E-series values** with the real load: N input networks on real triodes. Score each candidate by the smallest margin to the level windows. This rejects whole topologies in a minute. A resistive level shifter showed ±8 V margin at best, so it was not worth a transient run.
2. **Transient** on the survivors, at fanout 2, 4, 6, 8, 10.
3. **Static transfer curve (`.dc`)**. Find:
   - VIL, the point where the slope is −1;
   - the switching point, where the output crosses the middle of its family (100 V for HV);
   - the clamp level.

   Map LV thresholds back to the HV net through the divider: Vp = (Vlv + 35.07) / 0.2985.

### Miller capacitance and divider C1: work them out per grid type before any run

This trap has come up on every cell so far: NOR2_N16 (kick on the falling edge), NAND2_J2 (g3 Miller integrator), RSLATCH_J2N16 (pentode g1 kicked to −43 V). Before the first transient, write down this table for every grid type the cell has as an input.

| Grid type | Grid-plate C | Node C seen by the divider | C1 per grid | What goes wrong |
|---|---|---|---|---|
| 6N16B triode grid | Cga 1.5 pF, gain ≈ 15 | ≈ 30 pF while active (Miller), ≈ 4 pF cut off | 3.9 pF | C1 cannot match both regions: too small and the edge crawls, too large and the falling edge kicks the grid below −50 V |
| 6Zh2B g1 | Cg1a 0.03 pF: **no Miller** | ≈ 5 pF (Cg1k 3 + Cg1g2 1.9) | 3.3 pF (2.7 with a fast driver) | 3.9 pF is over-compensated. A fast triode driver (NOT_N16) kicks g1 to −43 V on the falling edge |
| 6Zh2B g3 | Cg3a 1.8 pF (measured) | Cg3k 3 + Cb 15 pF in the cell | 6.8 pF | Held at "1" while another grid swings the plate: Miller integrator, the plate crawls at I_divider / Cg3a |

Rules:

- **Compensated divider:** C1 · R1 = C_node · R2, so C1 ≈ 0.43 · C_node for 470k / 200k. If C1 is above that, the cell kicks on the falling edge; if it is below, the edge crawls.
- **Kick estimate:** a clamped "1" grid sits near +0.5 V, not +10 V. On a falling driver edge of ΔV the grid first jumps by ΔV · C1 / (C1 + C_node), and only then recovers through the 140 kΩ divider. For a 92 V edge: 3.9 pF on a 5 pF node gives −40 V, while the same 3.9 pF on a 30 pF Miller node gives −11 V. **Compute this before simulating. A grid without Miller needs a smaller C1.**
- **Miller depends on what the plate is doing**, not just on the grid: gain × Cga applies only while that plate swings. A grid held at "1" while another input moves the shared plate (any AND-type or wired-plate cell) sees the whole swing through Cga. Check every arc with the other inputs held at "1".
- **The worst driver is the fastest one** (a triode with Ra 10k, i.e. NOT_N16 or NOR2_N16): it gives the largest kick. Check the lowest grid voltage with that driver even if the cell's own testbench uses a slower one.
- **The C1 rule goes into the liberty as fanout_load**, per grid type (g3 ≈ 1.7, pentode g1 ≈ 0.85 of a triode grid), and the C1 of a net is the sum over its grids.

### The stimulus must look like a real driver

| Do | Don't |
|---|---|
| Ideal HV pulse (50/150 V, 20 ns edges) → divider → a driver gate of the same cell (inputs tied) → divider → DUT grid | An ideal LV source through a resistor into a grid. The Miller input capacitance (~30 pF) makes τ ≈ 5 µs, and every measurement then shows the stimulus, not the cell. |
| Loads are real gates. Tie both inputs of a load gate, and count each load gate as 2 grids. | A resistor as the load, or counting load gates as fanout. |
| Put a full input sequence into one run, 2 µs per state (for 2 inputs: 00 10 01 11 00), so every transition is covered. | Separate runs per state. |

### What to measure

| Quantity | How |
|---|---|
| Output levels, each input combination | `FIND v(out) AT=` near the end of each 2 µs state |
| LV levels after the divider | same |
| Delays | `TRIG` input crossing the LV threshold (−5 V), `TARG` output crossing the HV middle (100 V); `TD=` puts both on the intended edge |
| Lowest grid voltage, transients included | `MIN v(grid)` over the whole run, on the DUT grids and on the output LV net |
| Pa, Ik | node voltages and the Ra current at each state |

Measurement traps already hit:

- Without `TD=`, a `RISE=`/`FALL=` count can pick the wrong edge or the start-up settling. Negative or 4 µs delays mean exactly this.
- Read a level only after it has settled. A value taken too early looks like a failing cell.
- The current through a voltage source is positive from + through the source to −. Print both min and max before judging a sign.
- Print the metric you think you print. A "grid min" that was in fact the output LV net minimum hid a −50 V grid kick until the KiCad run showed it.

## 3. Acceptance checks

A cell is accepted when all of these hold at every fanout from 2 to the target:

| Check | Criterion |
|---|---|
| Output levels | inside the family window with margin. Rough rule: a static margin of at least 25 V on HV and 10 V on LV against the transfer-curve thresholds |
| Fanout independence | static levels do not move with fanout (one divider per net) |
| Grid voltage | never below −50 V, transients included, with ≥ 10 V margin for C1 tolerance (±10 %) |
| Plate | Ua ≤ 200 V when on; Pa ≤ 0.9 W per triode in the worst on-state, which for a wired-plate gate is one triode on |
| Cathode current | Ik ≤ 14 mA |
| Grid circuit | resistance ≤ 1 MΩ; Pg ≤ 0.1 W even from a stiff +10 V source |
| Speed | delays tabulated against fanout; flag the fanout where one gate plus divider exceeds ~⅓ of the clock |
| Hazards | glitches when two inputs change together must stay below the next stage's VIL. Note them; don't hide them |

## 4. Design traps found on NOR2_N16

- **Speed-up capacitor and grid clamping.** A driven LV "1" grid sits at +0.3 V, not +10 V, so the divider capacitor holds about 10 V more than the compensated value. On the falling edge that surplus kicks the grid negative. It grows with C1 and with the driver swing; the worst case is a driver with tied inputs, 147 → 39 V. C1 is bounded:
  - too large: the kick crosses −50 V (4.7 pF per grid gave −49.8 V);
  - too small: the divider is under-compensated and the grid crawls (2.7 pF per grid gave a 2 µs fall).

  Pick C1 in the middle (3.9 pF per grid).
- **Miller.** The input capacitance is about Cgk + Cga·(1 + gain), roughly 30 pF in the on/active region, but only about 4 pF in cut-off. A divider cannot be compensated for both, so check both edges. See the per-grid-type table in §2 ("Miller capacitance and divider C1").
- **C1 scales with the fanout of the net.** A passive whose value depends on fanout belongs to the net, not to the cell sheet. KiCad keeps one value per sheet file for all instances, so put such parts in the parent sheet.
- **Peaking inductor in the anode.** It speeds up the edges but rings: 1 mH pushed the LV net to −56 V, and 2.2 mH or more made the stage oscillate. Don't use one without damping and a separate check.
- **Neon level shifter.** It cannot carry reverse current, so it goes out on every fast falling plate edge and waits for a re-strike at the strike voltage. Unusable for 1 MHz logic.
- **Cathode follower output.** Fast, with fanout-independent levels, but +0.5 tube per gate. Use it only where a cell really needs a low-impedance output, and only with the owner's agreement on the tube budget (REQ-MOD-009).
- **Ra.** Choose it so that VOL with one triode on is close to the HV "0" nominal (+50 V), then check Pa and Ik. A lower Ra is faster but raises VOL and Pa.
- **Unused inputs.** Tie them to another input of the same cell. An open grid is undefined, and a grid tied to −50 V sits right at the limit.

## 4a. Traps found on NAND2_J2 (pentode, AND-type cells)

- **No model, or a sheet with one screen voltage.** Fit a behavioural model to the digitized curves (`tools/spice/fit_6zh2b.py`) and let the script write the `.sub`. Anything the sheet does not cover (the Ug2 law, grid currents, the capacitances of g3) is an assumption: list it on the cell page and sweep the cell over it.
- **Held-high grid plus a plate swing = Miller integrator.** In an AND-type cell one input sits clamped at "1" while the other switches the plate by 95 V. A grid with real capacitance to the plate (g3 of a pentode: Cg3a ≈ 1.6 pF) is pulled out of its clamp, the 140 kΩ divider cannot pull it back, and the edge crawls at I_divider / Cg (0.5–1 µs). NOR cells never meet this, because a "1" on any input already holds the output low. Check every arc with the other input held at "1", and hold such a grid with capacitance: a fixed C in the cell and a larger divider C1 for that grid type.
- **C1 per grid type.** When grids of different types load a net, C1 = Σ (C1 per grid of that type). Bound each type separately: too small and that input crawls, too large and the kick on the falling edge grows and the driver rises slower.
- **The screen supply limits current, not only voltage.** A pentode whose g3 diverts the plate current to the screen dissipates it there. Size the screen resistor for Ik and Pg2 in the state where the plate is cut off by g3, and check both at the ends of the model spread (MU2 ± 20 %).
- **Plate current in the knee.** VOL ≈ +50 V puts a pentode into the knee, where the plate takes about half of the cathode current. Ra follows from the Ik limit, not from the speed: for the 6Zh2B Ra ≥ 15k.
- **A cathode resistor does not help** a cell whose speed is set by a held grid: the cathode rises with the current and takes that grid further below its clamp.
- **One measurement routine for the sweep and the KiCad sheet.** Generate the `.meas` lines from the input sequence in one function and use it in both (`nand2_sweep.meas_lines`); the KiCad result then compares line by line.

## 4b. Traps found on NOT_N16 (several gates in one envelope)

- **A multi-unit tube shared by independent gates goes on one sheet.** KiCad keeps one unit number per symbol in a sheet file for all its instances, so a one-triode sheet cannot place its second instance on unit B. NOT_N16 is one sheet with both inverters (A1→Y1, A2→Y2); the liberty cell stays half a tube.
- **Coupling between the sections.** When the plates are separate gates, the plate-to-plate capacitance (6N16B: Ca1a2 0.5 pF) couples them. Put it into the model (`CPP` in `6N16B.sub`), switch one half while the other is static, and measure the quiet output in both of its states. The worst case is a rising neighbour at light fanout (fastest edge) with the capacitance at its upper tolerance.
- **Recheck the C1 window with the new cell as the driver.** A driver with a smaller swing kicks the grid less, but a net may be driven by any cell, so C1 keeps the tightest bound.

## 4c. Traps found on the latches and the flip-flop (RSLATCH_J2N16, DLATCH2_J2N16, DFF_J2N16)

- **Pentode g1 needs a smaller divider C1** (2.7 pF, not 3.9): see the Miller table in §2.
- **Keep the feedback divider inside the cell.** The cross-coupled grids then see a fixed load, and the output pins stay HV like every other cell. If the output net's divider fed the feedback too, the cell would need an LV pin and would be 3–8 % slower.
- **A sequential cell needs timing numbers that a gate does not have:**
  - the shortest enable pulse;
  - setup and hold, found by bisection with pass/fail runs (`latch_timing.py`);
  - for a flip-flop, register to register: two cells in a row, each sampled level checked against the next stage's thresholds ("1" > 118 V, "0" < 92 V), not against 100 V. A check at 100 V passed a 1 MHz case whose "0" was at 94 V.
- **The LV clock window is shorter than half a period on the direct net.** The LV net rises slowly (the driver's plate charges through Ra) and falls fast. The latch that has to drive the external load needs the wider window, so in a master-slave flip-flop put the slave behind the inverter. That is the falling-edge flip-flop, which was 1.05 MHz at fanout 6 against 0.77 MHz for the rising-edge one.
- **Check the race at the non-overlap edge** by adding delay to the inverter until it fails (`dff_sweep.py --cskew`). The margin was only about 90 ns, so the clock inverter stays in the cell and must not be shared.
- **One sheet file, one value.** Two instances of a sub-sheet cannot have different C1 (§4), so signals between the instances go through their own dividers in the parent sheet.
- **Net labels at pin stubs** (`tools/kicad/gen_latch_j2n16.py`) keep a multi-tube cell generator short. Bottom tube pins are 1.27 mm apart, so route the heater pins bent at different heights. Verify the drawing with the KiCad netlist against the plain SPICE bench (`latch_tb.py`): they must agree to 0.01 %.

## 5. Draw the cell in KiCad

### Generate the sheets with a script

Generate the sheets with a script rather than by hand: `tools/kicad/gen_nor2_n16.py OUT_DIR` writes the cell and the testbench. For a new cell, copy the script and change:
- the cell section (symbols, wires, hierarchical labels, sheet notes);
- the testbench section (drivers, dividers, loads, `.tran`/`.meas` text).

The script embeds the stock symbols, so the files open without project library tables. After the first commit, edit the cell in KiCad. Every regeneration makes new UUIDs.

### Sheet conventions

- **Cell sheet** `sch/logic/<CELL>.kicad_sch`:
  - Hierarchical labels: inputs (`input`), output (`output`), heater H1/H2 (`passive`).
  - Power only through global power symbols (`+150V`, `-50V`, `GND`). No PWR_FLAG inside the cell.
  - A note on the sheet with function, levels, key figures, the divider rule and a link to the cell page.
- **Testbench project** `sch/logic/<CELL>_tb.kicad_pro` plus `<CELL>_tb.kicad_sch` (A3 sheet):
  - VDC supplies with PWR_FLAG; VPULSE stimulus with HV levels.
  - Driver and load instances of the cell sheet.
  - Dividers drawn at top level.
  - `.tran` and `.meas` as text directives. They use hierarchical net names, e.g. `v(/OUT)`, because KiCad prefixes root-sheet nets with `/`.
- **Projects one directory below `sch/`** (for example `sch/logic/`), because `Sim.Library` is `${KIPRJMOD}/../libs/<tube>.sub`.
- **Simulation properties on the tube instance:** `Sim.Library`, `Sim.Name`, `Sim.Device SUBCKT`, `Sim.Pins`. KiCad merges the units of a multi-unit tube into one `X` line.
- **Pin types:** plates `open_collector` (wired plates pass ERC), cathodes `passive`.

### KiCad 10 file-format notes

- Version `20260306`.
- Strings escape newlines as `\n`; a raw newline breaks loading.
- Property angles are relative to the symbol: use 90 on a symbol rotated 90° to get horizontal text.
- Every symbol in a sheet used several times carries one `(path "/<root>/<sheet-uuid>" (reference …))` per instance.
- A power symbol's net name is its Value.
- Custom power symbols (`+150V`, `-50V`, `+6.3V`) are copies of stock `+12V`/`-12V` with the name changed. The GUI warns that they are not in the stock `power` library. Moving them into `sch/libs/DecatronPC_symbols.kicad_sym` removes the warning.

## 6. Verify the drawn files

Run from the repo root:

```
kicad-cli sch upgrade <file>.kicad_sch           # parses the file; "not updated" = already current, i.e. OK
kicad-cli sch erc -o erc.rpt <CELL>_tb.kicad_sch # only lib_symbol_issues may remain (CLI has no lib tables)
tools/spice/sim_kicad.sh sch/logic/<CELL>_tb.kicad_sch   # KiCad's own netlist through ngspice, prints .meas
```

- `kicad-cli` needs the `.kicad_pro` next to the sheet. Without it the netlist export exits with code 2, and `sim_kicad.sh` now says so.
- The KiCad testbench results must match the plain-SPICE sweep at the same fanout to within a few percent. A larger gap means a wiring or pin-map error.
- Check the drawing by eye:
  1. `kicad-cli sch export svg -e -o DIR <CELL>_tb.kicad_sch`.
  2. `rsvg-convert -w <px> -b white` on the SVG.
  3. Crop to the coloured pixels and look at the PNG for overlapping text, labels off the page, and symbols overlapping wires.

## 7. Document the cell

The cell page is `doc/<cell>_<tube>.md`, with images in `doc/img/` (`.gitignore` lets `doc/img/*.png` through). Use the structure of `doc/nor2_n16_6n16b.md`:

1. Summary table: function, tubes, inputs and outputs with their families, supplies, parts, levels, delays, worst grid voltage.
2. Logic levels, and how the cell joins the HV/LV scheme.
3. Schematic image (exported from the cell sheet) and pin table.
4. Net-side parts (dividers) with the rule for sizing them, and the table that bounds C1.
5. Results:
   - testbench image and `.meas` table;
   - waveforms (one panel per signal, level and limit lines);
   - static transfer curve and noise margins;
   - delay against fanout as a chart and a table.
6. Datasheet limits against the worst case in the cell, and power per gate.
7. Options evaluated, with numbers, and why each was rejected.
8. Model notes and the datasheet cross-check.
9. Files and how to simulate and embed the cell.
10. Open points.

Build every figure with one script: `tools/spice/nor2_plots.py [OUT_DIR]` (default `doc/img`). It exports the schematics from KiCad and crops them, runs the KiCad testbench, the static transfer deck and the fanout sweep, and draws the charts. For a new cell, copy it and change the CELL block (testbench file, crop of the cell page, parameters, signals to plot, input states). Rerun it whenever the cell or the testbench changes, so the page never shows stale figures.

Charts follow the repo convention:
- one hue per panel;
- two series (tpHL/tpLH) with legend and end labels;
- reference lines dashed and muted;
- light surface.

## 8. Bookkeeping

- **TRS.md** under a new version tag:
  - REQ-MOD-005 status;
  - REQ-MOD-004 figures;
  - any new level or supply decision in REQ-MOD-012;
  - §19.6 checklist, §22 next actions;
  - a §1 history entry.
- **history.md:** one bullet.
- **Liberty** (`vtube_cells.lib`) and `vtube_timing.json`: update area, tubes and timing only when the owner agrees. Simulated delays are an input until hardware is measured.
- **Commit:** cell sheet, testbench project (not `.kicad_prl`), model and symbol changes, scripts, page and images.

## Checklist

- [ ] Level spec read back to the owner; supplies, families and tube count confirmed
- [ ] Model checked against the datasheet: operating point, S, pinout, `Sim.Pins`
- [ ] Static search and transient sweep in plain SPICE with real drivers and real loads
- [ ] All acceptance checks pass at fanout 2 … target, grid ≥ −50 V with margin
- [ ] Cell sheet and testbench generated; upgrade, ERC and `sim_kicad.sh` clean; drawing checked by eye
- [ ] KiCad results match the sweep
- [ ] Cell page with schematic, waveforms, transfer curve, fanout chart and rejected options
- [ ] TRS, history.md updated; commit
