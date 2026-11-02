# HV → LV dividers as netlist cells

REQ-MOD-012 (levels), REQ-PR-011..019 (hierarchical netlist, boards, connectors), REQ-MOD-003/004 (liberty). Owner, 2026-10-28: the HV → LV dividers become cells of their own so that P&R counts and places them. The liberty says whether each output is HV or LV, and a script walks the netlist and adds the dividers. A divider can go on the board of the source or of the receiver, so its placement is one more P&R coordinate.

## What is in the tree

| File | Change |
|---|---|
| `sch/logic/vtube_cells.lib` | `define(vtube_level / vtube_grid / vtube_c1, pin, …)`; attributes on the designed cells; the new cell `DIV_HL` |
| `sch/logic/vtube_cells.v` | `DIV_HL` model: a wire with parameters `C1_DPF`, `GRIDS`, `CLASS` |
| `sch/logic/vtube_timing.json` | `DIV_HL` HV→LV 0 ns (the divider is already inside the gate delays) |
| `rtl/run/div_insert.py` | the pass: places the dividers on the Yosys JSON netlist and checks the levels |
| `rtl/run/synt_dpc.tcl` | option `-div`: runs `div_insert.py` after `qn_absorb.py`. The default tube-count flow is unchanged. |

## Liberty attributes

Pin attributes; ABC, Yosys and the `liberty` Python package (`dpc_stat.py`) read the file unchanged, and ABC maps a test design to the same cells as before.

| Attribute | Pin | Values | Default |
|---|---|---|---|
| `vtube_level` | output | `"HV"` plate (+150 / +50 V); `"LV"` grid-level output (cathode follower, the LV side of `DIV_HL`); `"PASS"` relay contact, carries the level of what drives it; `"CONST"` tie cell | `"HV"` |
| `vtube_level` | input | `"HV"` takes HV directly (`DIV_HL.HV`); `"PASS"` relay contact; `"COIL"` relay coil (panel switch) | a grid |
| `vtube_grid` | input (grid) | `"triode"`, `"pentode_g1"`, `"pentode_g3"`, `"follower"` | `"triode"` |
| `vtube_c1` | input (grid) | divider C1 per grid, pF | 3.9 |

Annotated now: NOT_N16, NOR2_N16 (triode 3.9), NAND2_J2 (A pentode_g1 3.9, B pentode_g3 6.8, as on its page), BUF_N16 and OR2_N16 (inputs follower 2.7, output LV), RELAY_2CO, TIEHI/TIELO, DIV_HL. The other cells are not designed yet and run on the defaults: plate output, triode grids.

`DIV_HL` has 0 tubes and no output function, the same way as RELAY_2CO and GUIDE_EN_J2, so ABC never uses it. Its parameters:

| Parameter | Meaning |
|---|---|
| `C1_DPF` | C1 in 0.1 pF: the sum of `vtube_c1` over the grids it feeds |
| `GRIDS` | number of grids |
| `CLASS` | 0: gate grids; 1: cathode-follower grids, which need their own divider (`sch/logic/BUF_N16/README.md`) |

R1 470k and R2 200k are fixed (REQ-MOD-012) and not parameters.

## What `div_insert.py` does

1. **Levels.** Every net gets the level of its driver from the liberty. Through the hierarchy, a module input port takes the level of what drives it in the parent, and an output port takes the level of its driver inside. This is iterated until stable. Top-module inputs are HV (`--top-inputs`).
   - A relay contact output (C1) has the level of its own contacts (NC1, NO1). A constant on a contact or on one instance takes the level of the signal on the other side.
   - Black boxes with no liberty entry (DekatronTubeV2, OneShot, Impulse, empty stubs) make their nets `UNKNOWN`. These are treated as HV, with a warning.
2. **Dividers.** On every HV net, in every module that has grids on it:
   - one `DIV_HL` for the gate grids, `CLASS` 0;
   - a separate `DIV_HL` for the follower grids, `CLASS` 1.

   C1 is the sum over the grids, and the grids move to a new net `<net>_lv` / `<net>_lvf`. A net that enters a module through a port gets its divider inside that module, so ports and connectors carry HV by default.
3. **Checks:**

   | Report | Meaning |
   |---|---|
   | `errors` | an LV net (follower output) drives a follower grid. This is rule 2 of `sch/logic/BUF_N16/README.md`: it does not work. `--strict` stops the flow here. |
   | `fanout` | a driver with more grids in one module than its `max_fanout` |
   | `warnings` | LV leaving a module through a port (LV over a connector), unknown drivers, nets whose level cannot be resolved |
   | `ties` | grids on constants: they need a bias network, not a divider |

The result loads back into Yosys and `write_verilog` prints `DIV_HL #(.C1_DPF(78), .CLASS(0), .GRIDS(2)) div_<net>_lv (.HV(<net>), .LV(<net>_lv));`. Chip area does not change.

### Placement is a P&R coordinate

The pass puts each divider in the module that holds its grids, which in the hierarchical netlist is the receiving board (REQ-PR-011). P&R may then move a divider:

- to the source board, if that saves something;
- or split it per board, with C1 split by the grids on each board.

Each extra divider loads the driving plate by 0.15–0.3 mA. Over a connector HV is the safer signal: it comes from a 10 kΩ plate, while LV is a 140 kΩ node.

## First run on the existing netlists

`rtl/run/IpLine_synth.v` and `MachineCtrl_synth.v` (synthesized 2026-10-11 with the old liberty, converted to JSON by Yosys, no new synthesis):

| | IpLine (with counters) | MachineCtrl |
|---|---|---|
| Dividers | 314 (gate 254, follower 60) | 225 (gate 174, follower 51) |
| Grids behind them | 498 | 389 |
| Largest net | 13 grids (OR2_N16, over max_fanout 10) | 14 grids |
| errors: follower → follower | 5 | 14 |
| OR2_N16 / BUF_N16 in the netlist | 37 / 1 | 38 / 0 |
| LV leaving a module | 26 (DekatronModule / DekatronCounter outputs from OR2) | — |

Findings:
- **ABC uses OR2_N16 a lot** (about 40 per block), and in 19 places it chains them, which a follower cannot do. ABC knows nothing about levels.
- **Fanout over 10** also happens, because ABC ignores `max_fanout`.
- **Divider count:** about one divider per gate. Assuming 3 parts per divider, IpLine + MachineCtrl need about 1600 passives (539 dividers) for dividers alone.

## Open points (owner)

- **Follower chains:** what to do with them.
  - (a) `dont_use` on BUF_N16 / OR2_N16 for ABC. OR2 is then built from NOR2 + NOT, which costs tubes. **Chosen (owner, 2026-10-30)**, with OR4_N16 and the diode gates: 1464 tubes, no chains (`doc/follower_chains.md`).
  - (b) A legalisation pass after ABC that replaces an OR2 driving a follower with NOR2 + NOT or a different cell.
  - (c) Keep OR2 only where its output goes to gates.

  Before choosing, measure the tube cost of (a) with `run_tests.sh -s` (a heavy run: ask first).
- **Fanout:** split nets over `max_fanout` (a `BUF_N16` or a duplicated driver) in the same pass or in ABC settings.
- **LV over connectors:** allow it, or place a follower at the source board only when its loads are local.
- **Ties** (2 in DekatronCounter, `set`): which bias network the grids get.
- **Default on:** whether `synt_dpc.tcl` should run `-div` by default and `dpc_stat.py` report divider and passive counts.
- **Netlist simulation** (`synth_sim.sh`) of a `-div` netlist has not been run. The model is a wire, so it should pass unchanged.
