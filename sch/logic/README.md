# Tube logic cells

This folder holds the logic cells of the tube machine (REQ-MOD-003/004/005), each in a folder of its own, and the cell library that synthesis and netlist simulation use. Every number below is from SPICE, not measured on tubes (REQ-MOD-004). The cell page has the details.

## Cells

| Cell | Function | Tubes | In → out | Delay, fanout 2 … 10 | Liberty | Page |
|---|---|---|---|---|---|---|
| [NOR2_N16](NOR2_N16/README.md) | Y = ~(A \| B) | one 6N16B | LV → HV | tpHL 73 … 90 ns, tpLH 105 … 290 ns | `NOR2_N16` | NOR gate; the HV/LV levels and the divider rule were set here |
| [NAND2_J2](NAND2_J2/README.md) | Y = ~(A · B) | one 6Zh2B (A on g1, B on g3) | LV → HV | tpHL 166 … 396 ns, tpLH 122 … 466 ns | `NAND2_J2` | NAND gate, the 6Zh2B model |
| [NOT_N16](NOT_N16/README.md) | Y1 = ~A1, Y2 = ~A2 | one 6N16B (½ per inverter) | LV → HV | tpHL 61 … 83 ns, tpLH 64 … 211 ns | `NOT_N16` | two inverters |
| [BUF_N16](BUF_N16/README.md) | Y1 = A1, Y2 = A2 | one 6N16B (½ per buffer) | LV → **LV** | Y up 24 … 69 ns, Y down 32 … 224 ns (to the load plate) | `BUF_N16` | cathode followers, the base of the follower family |
| [OR2_N16](OR2_N16/README.md) | Y = A \| B | one 6N16B | LV → **LV** | Y up 26 … 85 ns, Y down 41 … 241 ns (to the load plate) | `OR2_N16` | cathode followers on one cathode load; hazard |
| [A1OOI_N16J2](A1OOI_N16J2/README.md) | Y = ~((A · B) + C), AOI21 | 6Zh2B + ½ 6N16B | LV → HV | worst arc 194 … 420 ns; C↑ 53 … 82 ns | `A1OOI_N16J2` | SPICE only, KiCad sheet to do |
| [A2OOI_J2](A2OOI_J2/README.md) | Y = ~((A · B) + (C · D)), AOI22 | 2 × 6Zh2B | LV → HV | worst arc 209 … 418 ns | `A2OOI_J2` | SPICE only, KiCad sheet to do |
| [RSLATCH_J2N16](RSLATCH_J2N16/README.md) | gated RS latch | 2 × 6Zh2B + 1 × 6N16B | LV → HV | E→Q 172 … 380 ns, S→Q 138 … 392 ns | proposed | the base of the latch family |
| [DLATCH2_J2N16](DLATCH2_J2N16/README.md) | two D latches | 7 (2 × RSLATCH + 1 × 6N16B) | LV → HV | as RSLATCH, D falling + inverter | `LATCH_J2N16` (one latch) | |
| [DFF_J2N16](DFF_J2N16/README.md) | D flip-flop, **falling** edge of C | 7 (2 × RSLATCH + 1 × 6N16B) | LV → HV | C↓→Q 340 … 539 ns; 1.11 … 0.93 MHz register to register | `DFF_J2N16` | synthesis adds one clock inverter per clock net |

"Liberty" names the cell in `vtube_cells.lib`. "Proposed" means that the page proposes the entry and the owner has not reviewed it yet.

The library also has cells that are not designed yet: `BUF_6J2B`, `NOT_J2`, the `*_N16X7` gates, `NOR4_N16`, `OR10_X7`, `DFFSR`, `DFFSR_n`, `GUIDE_EN_J2`, and the non-tube `RELAY_2CO`, `DIV_HL`, `TIEHI`, `TIELO`.

## Common rules

- **Levels (REQ-MOD-012).** HV on plates: 1 = +150 V, 0 = +50 V. LV on grids: 1 = +10 V, 0 = −20 V. HV → LV is the divider 470k ‖ C1 / 200k to −50 V, one per HV net. C1 per grid: 3.9 pF triode grid, 3.9 pF pentode g1 of a gate (2.7 pF in the latch), 6.8 pF g3, 2.7 pF follower grid (`doc/cell_design_method.md` §2; `doc/hv_lv_dividers.md`).
- **Followers (BUF_N16, OR2_N16)** put out LV: their input gets a divider of its own, and the output drives only gate grids, never a divider, an HV input or another follower (BUF_N16 page).
- **Supplies:** +150 V, −50 V, heater 6.3 V.
- **How a cell is designed and documented:** `doc/cell_design_method.md`.

## Folder layout

Each cell folder `<CELL>/` holds:

| File | What |
|---|---|
| `<CELL>.kicad_sch` | the cell sheet; embed it as a hierarchical sheet |
| `<CELL>_tb.kicad_pro`, `<CELL>_tb.kicad_sch` | testbench project (KiCad simulator, or `tools/spice/sim_kicad.sh`) |
| `README.md` | the cell page |
| `img/` | figures of the page, rebuilt by `tools/spice/*_plots.py` |

- The sheets take the tube models from `sch/libs/` as `${KIPRJMOD}/../../libs/<tube>.sub`, so a cell project sits two levels below `sch/`.
- DLATCH2_J2N16 and DFF_J2N16 use `../RSLATCH_J2N16/RSLATCH_J2N16.kicad_sch` as their sub-sheet. A change to the RS latch changes all three cells.
- The scripts stay in `tools/`. `tools/kicad/gen_*.py OUT_DIR` writes the sheets to `OUT_DIR/<CELL>/` (run with `sch/logic`, and only to start over: the drawn sheets are edited in KiCad). `tools/spice/*_sweep.py`, `*_static.py` and `*_plots.py` run the simulations and draw the figures; with no argument, the plots go into `<CELL>/img/`.

## Cell library

These files are the interface of the cells to the RTL flow. Keep them in step with the cell pages.

| File | What | Used by |
|---|---|---|
| `vtube_cells.lib` | liberty: functions, tube counts (`tubes`), level attributes (`vtube_level`, `vtube_grid`, `vtube_c1`) | `rtl/run/synt_dpc.tcl`, `dpc_stat.py`, `qn_absorb.py`, `div_insert.py`, `synth_sim.sh` |
| `vtube_cells.v` | Verilog models of the cells, one to one with the liberty (AGENTS §6) | `rtl/run/synth_sim.sh` |
| `vtube_cells.sp` | behavioural SPICE models (0/1 V logic, ngspice + XSPICE) with the liberty names and pins | not used by a script now |
| `vtube_timing.json` | the only place for cell delays and setup/hold | `rtl/run/vtube_sdf.py` (`synth_sim.sh -t`, `doc/vtube_sdf_timing.md`) |
| `vtube_timing_check.v` | `vtube_setuphold`, the setup/hold checker of the trigger cells | `synth_sim.sh -t` |

## Other files

- `logic.kicad_pro/.kicad_sch/.kicad_pcb`: the old overview project. Its sub-sheets are in `legacy/`.
- `legacy/`: sketches from before the cell method (2NAND_6J2B, 2NOR, 2NOR_6N16B, 2OR, BUF_х2_6Н16Б, INV_6Ж2Б, INV_x2_6Н16Б, untitled). The BUF and OR2 pages compare the old follower sketch against the new cells.
