# Netlist schematics: netview instead of yosys show + dot

Date: 2026-11-04. Tool: [tools/netview/](../tools/netview/README.md). Flow: `run_tests.sh -p` after `-s`.

## Problem

`run_tests.sh -p` drew the netlists with `yosys show -format dot`, split them with gvpr and laid them out with dot. The result could not be read:

- every cell is a `record` with its pins in a row; there are no gate symbols, and NOR, AOI and DFF look the same;
- dot draws splines, and `splines=ortho` drops the ports, so wires end anywhere on a cell;
- every bit slice gets a `$split`/`$join` node, and every use of a constant gets a `1'0` node;
- the clock and the reset lines go to dozens of cells, so wires from one point cross the whole sheet;
- names are `$abc$…` and `_123_`, with no link to the RTL.

## Choice

| | Layout | Symbols | Dependency |
|---|---|---|---|
| dot + better styling | layered, splines; ports are lost with ortho | only via HTML tables | graphviz (have) |
| netlistsvg | ELK, orthogonal | its own skin, IEEE | npm package, its own JSON handling |
| **netview** | ELK layered, orthogonal, fixed pin positions | GOST 2.743 from the liberty `function` | node + elkjs (one npm package) |

netview keeps the netlist handling and drawing in Python (liberty parser, symbols, SVG, viewer) and uses node only for the layout (`elk_layout.mjs`, 15 lines). ELK knows the exact pin positions (`portConstraints FIXED_POS`), so wires end on the pins, and it returns the junction points of fanout nets.

Not routing some nets matters more than the layout engine:

- flags for nets with ≥ 7 sinks and for clk/reset lines;
- flags for register outputs with ≥ 2 sinks (`--seq-cut`). The feedback wires from the registers ran back across the whole sheet. With them cut, the sheet reads left to right: inputs → logic → registers → outputs. MachineCtrl went from 329 routed wires to 255, and the long backward wires are gone.

## Results (ISA16 branch, 2026-11-04, `run_tests.sh -p` on a scratch copy of the working tree)

| Sheet | Cells | Tubes | Wires | Flagged nets |
|---|---|---|---|---|
| IpLine (+3 DekatronModule) | 206 | 275.5 | 405 | 18 |
| ApLine (+3 DekatronModule) | 198 | 243 | 390 | 16 |
| MachineCtrl | 157 | 262.5 | 254 | 31 |
| DekatronModule (IP decade) | 22 | 16.5 | 44 | 0 |

The tube counts are the liberty `tubes` of the cells on the sheet, without the DekatronModule contents (they have their own sheets).

## Function frames

A flat sheet of 150–200 gates is one ABC cone with no visible structure. The cells are framed by function (ELK compound nodes with `hierarchyHandling INCLUDE_CHILDREN`).

- RTL `src` doesn't help: after ABC, 175 of 213 IpLine cells have none.
- Seeds: a cell named in a sub-scope (`ip_counter.*`, `loop_counter.*`) takes the scope. A cell that drives a public net takes the net name, normalized (`state_d[1]` → `state`).
- Each other cell takes the group of the cells it feeds, by majority over its sinks (output ports count too). Cells feeding several groups equally are shared and stay outside the frames, between them. Loops through unseeded cells are broken by deciding one cell from the votes known so far.
- A group over 25 cells gets sub-frames by the exact signal: `state` → `state[0..2]`, where the register `state[2]` and the cone of `state_d[2]` share a frame; `ip_counter` → `ip_counter.phaseGen`. Groups under 3 cells get no frame.

Groups on the 2026-11-04 netlists (cells; sub-frames in brackets):

| Block | Frames |
|---|---|
| IpLine (206) | state 60 (state[2] 18, state[1] 15, state[0] 10), ip_counter 38 (phaseGen 4), loop_counter 20, scanning 11, dir 9, overflow 6, eot 4, halt_pending 3 |
| ApLine (198) | data_counter 42 (g_top_limit 6, dek[0] 5, phaseGen 4), ap_counter 38 (phaseGen 4), state 36 (state[2] 13, state[0] 6, state[1] 3), data_in_n 27, data_zero 6, lock 5, ap_zero 3 |
| MachineCtrl (157) | state 67 (state[2] 26, state[1] 4, state[3] 3), op 15, pf 9, bell 7, rst_soft 4, tx_vld 3, one_step 3 |

With the frames the sheets read as blocks: IpLine has the loop counter bottom left, the state machine in the middle and the IP counter with its five dekatrons on the right; ApLine has the data_in_n column, the state block and the two counters. The wires between the frames still run in long bundles, but now they are visibly inter-block buses. Layout time fell (IpLine ≈ 2.5 s instead of 18 s) because ELK places the frames separately.

## Buses

Even with frames, IpLine had thick bundles of separate wires between the frames. Of 174 frame-crossing connections only 54 were vector bits (ip_addr, loop_count, insn). 99 were ABC-internal nets from the shared logic, and 21 were public scalars. Bundling only vectors (`--buses vectors`) gave just a few buses (ip_addr[19:0], loop_count[7:0], insn[2:1]) and left the bundles as they were. So by default everything going from frame A to frame B travels as one bus:

- a joiner in the source frame (a bar; its stubs carry the bit index for a single vector, otherwise the net name), one thick bus, and a ripper in the destination frame;
- the label is `name[hi:lo]` for one vector, otherwise `A→B · N`, with the member nets in the tooltip; the shared logic outside the frames has no name (`→state · 13`);
- a bus that comes entirely from one multi-bit input port, or goes entirely to one multi-bit output port, attaches straight to the port header. Without this, the 20 bits of ip_addr/mem_addr ran as 20 parallel wires from a ripper to the port across a third of the sheet;
- in the viewer, a click on a bus lights all its bits, and a click on a bit lights its bus.

IpLine has 20 buses, ApLine 28, MachineCtrl 15. The wire count goes up (IpLine 405 → 524 segments, counting the stubs into joiners and out of rippers), but the long runs between frames are now one line per frame pair. Layout of all three blocks with their DekatronModule sheets takes ≈ 9 s.

`run_tests.sh -p` runs `-s` itself when any of IpLine/ApLine/MachineCtrl `_netlist.json` is missing. The full `-p` from scratch (synthesis of the three blocks and all sheets) takes ≈ 19 s.

## Notes

- A behavioural blackbox (DekatronTubeDelay) comes into the JSON netlist without `port_directions`. netview takes the direction from the name (`_i`, `_o`, `_dbg`), or else from the nets: a pin is an input when something else drives its net. Without this, the dekatron's `main_onehot_o` was drawn as an input and the sheet fell apart into two pieces.
- librsvg (rsvg-convert) ignores CSS variables, so the SVG carries literal colours.
- `yosys show` and the gvpr script `rtl/run/split` are removed. `synt_dpc.tcl` writes `<top>_netlist.json` instead.
