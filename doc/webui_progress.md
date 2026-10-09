# Web UI (Block Place & Route) — progress report, 2026-10-09

Branch `webui`, commits `3f49d98` … this one. It follows
[`webui_status.md`](webui_status.md) (2026-09-27) and
[`webui_review.md`](webui_review.md) (2026-10-09, owner decisions Q1–Q11), and
carries out steps 1–5 of the order agreed in the review.

## 1. Summary

The tool now builds, runs and passes 102 tests. It reads the real hierarchical
netlists of IpLine, ApLine and MachineCtrl with exactly the connectivity of Yosys
`flatten`. It holds all three blocks in one project with HD-68 connectors and
cables between them. It edits module types with per-copy pin maps, and places
module instances on a block canvas with drag, push-aside and locks.

Not built yet: putting netlist cells into module slots, the wiring-length metric
(HPWL), automatic placement, routing, assembly and export (§5).

## 2. What was done

| Step | Commit | Result |
|---|---|---|
| 1. Build, render, persistence | `3f49d98` | The build (`tsc -b`) and the Project tab work again after the 0.3.0 model change. Old 0.2.0 files are migrated. Saves no longer contain the undo history. The autosave is restored on start and also written when the page closes. |
| 2. Hierarchical netlist parser (H1) | `07c5752` | Replaces the regex parser, which merged nets of different modules. Every bus bit is its own net, and nets are joined through module ports and `assign`. A submodule is kept whole when it is a black box (`DekatronTubeV2`, `OneShot`, `Impulse`) or chosen as a board (`DekatronModule`); everything else is expanded to cells. |
| 3. Format 0.4.0 (H2) | `13b724e` | Rows per block (3–5). Transformer width 72 + 12·K mm. HD-68 connectors per block, with block ports assigned to pins. Cables between blocks, pin *n* to pin *n*, with checks for one-ended pins, unknown ports and driver clashes. Power nets excluded from routing. Interconnect boards. A board type can name the Verilog module it replaces. |
| 4. Modules tab (REQ-PR-006) | `f69206e` | Module-type editor: kind, width, Verilog module, slots, a pin map for each copy of a cell, a 2×36 connector view that highlights clashes, and auto-assign of free contacts. Tube count per type. |
| 5. Placement canvas (REQ-PR-007) | this commit | A Konva view of a block from above: connector strip, baskets, 12 mm grid, transformer. Modules can be placed, dragged with grid snapping and a drop preview, pushed aside, locked and removed. Connectors can be reordered. Zoom and pan. |

Size: about 5.1 k lines of TS/TSX in `webui/src`, 1.3 k lines of tests, and three netlist fixtures.

## 3. Verification

- **Tests:** 102 Vitest cases in 9 files. CI runs them on Node 22. They cover the
  parsers, store actions and their limits, the migrations from pre-0.2, 0.2.0 and
  0.3.0, the placement maths, and the UI flow of each tab under jsdom.
- **Parser against Yosys.** Each block was flattened with
  `hierarchy; setattr -mod -unset keep_hierarchy *; flatten`. The parser's leaf cell
  counts and the net on every pin match Yosys exactly, constant ties included:
  IpLine 1444 pins, ApLine 1752, MachineCtrl 720, with no differences. A permanent
  test repeats this on the checked-in `IpLine_synth.v` fixture.
- **Real browser.** The Placement canvas was driven in Chrome with Playwright:
  drag with push-aside, a drop refused because of a locked module, click-to-place
  and zoom. This found and fixed two bugs: the canvas rescaled during a drag, and
  the drop preview was hidden under the modules.
- **Not verified:** a long editing session in a browser by a person, and files
  saved by the old app (only synthetic 0.2.0 and 0.3.0 files were migrated).

## 4. What the netlists show

From the local `rtl/run/*_synth.v` (newer RTL) and the `claude_nextGen` liberty.
"Kept" means `DekatronModule` stays one board.

| Block | Leaf instances (kept) | Signal nets | Port bits | Tubes, all expanded | Tubes, `DekatronModule` kept |
|---|---|---|---|---|---|
| IpLine | 280 | 373 | 89 | 485.5 | 426.5 + 7 dekatron boards |
| ApLine | 282 | 389 | 85 | 564.5 | 412 + 8 dekatron boards |
| MachineCtrl | 201 | 252 | 86 | 319.5 | 319.5 |

- The tube totals agree with `doc/tube_count_reduction.md` §17.7 (≈ 496 / 577 / 319).
  The small gap comes from base elements, which the liberty doesn't count.
- **The liberty on this branch is out of date.** `rtl/run/vtube_cells.lib` (23 cells)
  lacks `NOT_N16`, `A1OOI_N16J2`, `A2OOI_J2`, `BUF_N16` and `RELAY_2CO`, which the
  current netlists use. With it the tool reports these as missing and counts too
  few tubes. Load `rtl/vtube/vtube_cells.lib` from `claude_nextGen` (27 cells)
  instead.
- **Space.** At an 84 mm transformer a basket has 28 free columns of 12 mm; five
  baskets have 140. ApLine with its 8 dekatron boards (24 columns) leaves 116
  columns for about 412 tubes, which is roughly 3.6 tubes per 12 mm, or 7 per 24 mm
  logic board. Whether that is feasible depends on the module boards, which don't
  exist yet; the tool will check it once module types are defined.

## 5. Decisions to confirm

These were made during the work and are written down in the READMEs. Each can be changed.

| # | Decision | Why |
|---|---|---|
| D-a | Power nets are a list of names on the block (`powerNets`), not a flag on the net. | The choice survives re-parsing the netlist. |
| D-b | Each connector has a list of port-to-pin assignments. | The spec had no way to say which port goes on which pin, and without it the links between blocks can't be worked out. |
| D-c | Transformer width is 72, 84 or 96 mm. The old 100 mm limit is kept, and 0.3.0 files are rounded (85 → 84). | Q4 says 72 + 12·K with no upper limit given. |
| D-d | Push-aside works like inserting: modules at or after the drop column move right, those before it move left. The transformer is a wall, and a locked module blocks the move. | It's predictable, and a module never jumps to the other half of the row. |
| D-e | In a 0.2.0 file, the single pin map of a slot goes to copy 0. | Giving it to every copy would put all copies on the same contacts. |
| D-f | The KiCad `.net` import is postponed. | `sch/logic` holds cell sketches with no 2×36 connector and with duplicate references, so there is no real board to match pins against. |

## 6. Open questions for the owner

1. Is the transformer centred in the row, or aligned to the 12 mm grid? Centred,
   only 84 mm puts its edges on the grid.
2. Can the transformer be wider than 96 mm?
3. Does the wiring channel between modules need a width of its own (spec §9)?
4. Module boards: which board types exist, how many tubes fit on a 24 mm board,
   and what is the contact order on the 2×36 connector? That decides whether
   ApLine fits in 5 baskets (§4).
5. RTL: when are the ports between blocks grouped into one wire bundle per connector
   (review §6)? Until then, ports go on connector pins one at a time.

## 7. Plan

Steps 6–10 finish the tool. Each ends in a commit with tests, like steps 1–5.

**6. Cells into module slots** (REQ-PR-007, §3.4).
- A list of unplaced netlist instances. Drag one onto a slot of a placed module.
  An unlocked cell already in that slot moves to the nearest free slot of the same
  type. Locked cells stay put.
- Capacity check per block: cells of each type against the slots of the placed
  modules, with "N more modules of type X needed".
- Tube summary per block and per basket.
- Done when every leaf of a block can be placed by hand, and the capacity table
  matches the netlist counts.

**7. Wiring length (HPWL), live.**
- The position of each module contact in mm, from the module's position and its
  pin map. Each net then runs between the contacts of its cells, plus connector
  pins.
- HPWL per net and in total, clock nets weighted. It updates while dragging;
  clicking a net highlights its pins.
- Done when HPWL changes as expected on a hand-made example.

**8. Automatic placement.**
- Cells to slots: an assignment problem solved with the Hungarian algorithm by
  type, then improved by swaps.
- Modules to positions: simulated annealing on HPWL that honours locks, rows and
  the transformer.
- It runs in a Web Worker with progress and a cancel button.
- Done when the result is better than a random placement on IpLine and repeats
  with a fixed seed.

**9. Routing** (§3.5, Q10).
- A channel graph between modules and rows; A* per two-pin connection.
  Multi-pin nets are split along a minimum spanning tree.
- Power nets and interconnect-board links are skipped. Connector pins are end
  points. Both kinds of wire are supported: a straight pin-to-pin link and a
  routed horizontal/vertical wire.
- A manual pencil tool, and a colour per net.
- Done when every non-power net of a block is either routed or listed as failed.

**10. Assembly and export** (REQ-PR-008).
- Mark wires as built, and filter by progress.
- Export the wiring table to CSV and JSON, and the canvas to PNG and SVG.

**Alongside these steps:**
- Add the nextGen liberty as a test fixture, and a fixture netlist from the
  current RTL (ApLine) next to the old one.
- KiCad `.net` import once the first module board exists in KiCad (REQ-PR-004).
- Bulk port-to-pin assignment once the RTL groups the ports.
- Load the Placement tab on demand: Konva pushes the bundle past 500 kB.
- Delete or rewrite `test/test_parsers.mjs` (D6), which still has the old parser.
- Add a favicon (the only 404 in the browser console).

## 8. Known issues

From the README: D6 (`test_parsers.mjs`, see above). The KiCad import waits for a
board. Port pins are assigned one at a time. On a 12 mm board, the module id
slightly overflows its box on the canvas.
