# DekatronPC Block Place & Route (Web UI)

A browser-based physical-design tool for the [DekatronPC](https://github.com/radiolok/dekatronpc)
vacuum-tube computer. It takes the gate-level netlist that Yosys produces against the
tube cell library and helps turn it into hardware: which logic cell goes into which
tube module, where each module sits in the chassis, and how the modules are wired
together. The end product is a wiring list you can build the machine from.

> **Status: early development (stages 1–5 of 10 done).** Project management, netlist/liberty
> import (hierarchical, bit-level), multi-block projects, the custom-element editor,
> the module-type editor and module placement on the block canvas work. Element
> placement, Routing and Assembly are not built yet. See [Status](#status),
> [Known issues](#known-issues) and the progress report
> [`doc/webui_progress.md`](../doc/webui_progress.md) before using it.

---

## Contents

- [Where it fits](#where-it-fits)
- [Status](#status)
- [Quick start](#quick-start)
- [Workflow](#workflow)
- [Input files](#input-files)
- [Physical model](#physical-model)
- [Project file format](#project-file-format)
- [Tests](#tests)
- [Known issues](#known-issues)
- [Roadmap](#roadmap)
- [Repository layout](#repository-layout)
- [Related documents](#related-documents)

---

## Where it fits

```
rtl/*.sv ──Yosys (rtl/run/synth)──► <Block>_synth.v ─┐
                                                      ├─► Web UI ─► placement + wiring list
rtl/run/vtube_cells.lib ──────────────────────────────┤
KiCad module schematics (planned) ────────────────────┘
```

DekatronPC is split into computational **blocks**: `IpLine` (instruction pointer
line), `ApLine` (address pointer line) and `MachineCtrl`. Each block is synthesized
separately into a hierarchical structural netlist of tube cells (`NAND2_N16X7`,
`DFF`, …). The tool loads one netlist per block and expands it to leaf cells. All blocks share one cell library, one set of
module designs and one chassis geometry.

## Status

| Stage | Area | State |
|---|---|---|
| 1 | Vite + React + TypeScript skeleton, tab shell | ✅ Done |
| 1 | Zustand + Immer store with undo/redo (50 steps) | ✅ Done. Every edit is undoable |
| 1 | JSON project save / open, migration from older formats | ✅ Done |
| 1 | Autosave to `localStorage` every 30 s and on page close | ✅ Restored on start |
| 1 | Liberty parser (`vtube_cells.lib`, incl. `tubes`, `ff`, `latch`) | ✅ Done, unit-tested |
| 1 | Verilog parser (Yosys hierarchical structural): bit-level nets, keep submodules whole | ✅ Done; connectivity matches Yosys `flatten` |
| 1 | Multi-block projects (2–3 netlists, shared library/modules/basket geometry) | ✅ Done |
| 2 | Format 0.4.0: rows per block, HD-68 connectors with port pins, cables between blocks, power nets, interconnect boards, Verilog module → board link | ✅ In store, types and the Project / Netlist tabs |
| 2 | **Elements** tab: custom elements not in the library (e.g. dekatron) | ✅ Done |
| 2 | `ModuleType` + per-block `ModuleInstance`, per-copy pin maps, top-view chassis | ✅ In store and types |
| 2 | **Modules** tab: module-type editor, slots, per-copy pin maps, 2×36 connector view, auto-assign | ✅ Done (manual entry, REQ-PR-006) |
| 2 | KiCad netlist import for module pin maps (REQ-PR-004) | ⏳ Waiting for a module board design to import |
| 3–4 | **Placement** canvas (Konva): baskets, 12 mm grid, transformer, connector strip; place, drag with push-aside, lock, zoom / pan | ✅ Module instances done (REQ-PR-007); elements into slots not yet |
| 3–4 | Auto-placement (simulated annealing, Hungarian assignment) | ⏳ Not started |
| 5 | **Routing**: channel graph, A*, manual pencil | ⏳ Store actions only |
| 6 | **Assembly**: mark wired segments, CSV/JSON/PNG/SVG export | ⏳ Store actions only |

The source is about 5 k lines of TS/TSX plus about 1.3 k lines of tests.

## Quick start

Requirements: **Node.js 22.22+** and npm. The app itself builds on Node 20, but the
jsdom-based UI tests need 22.22 or later.

```bash
cd webui
npm ci            # install exact versions from package-lock.json
npm run dev       # dev server on http://localhost:5173 (opens a browser)
```

| Script | What it does |
|---|---|
| `npm run dev` | Vite dev server with hot reload |
| `npm run build` | Type-check (`tsc -b`), then production build into `dist/` |
| `npm run preview` | Serve the built `dist/` |
| `npm test` | Run the Vitest suite once |
| `npm run test:watch` | Vitest in watch mode |

On Windows, `dev_server.bat` and `test/test_parsers.bat` do the same without a shell.
Both expect Node at `C:\Program Files\nodejs\node.exe`, and `dev_server.bat` needs
`npm ci` to have been run first.

**WSL:** use a Linux Node (for example `nvm install 22`), not the Windows one that
WSL puts on `PATH`. Windows Node can't run Vitest from a `\\wsl.localhost\…` path.
`node_modules` holds platform-specific binaries (Rollup), so run `npm ci` again
when you switch between Windows and WSL.

The app runs entirely in the browser. There is no backend, and files are opened
through the browser's file picker.

## Workflow

The UI is a row of tabs, one per design stage. You can switch tabs at any time; they
all edit one shared project. **Undo** / **Redo** (`Ctrl+Z`, `Ctrl+Y` or
`Ctrl+Shift+Z`) work across all tabs.

1. **Project.** Name the project, create a new one, open or save a `.dpc.json`
   file, and see summary counters. Set the transformer width (72, 84 or 96 mm) and
   the number of baskets of each block (3–5), and join connectors of two blocks
   with an HD-68 **cable**. The panel warns about cable pins with a problem: a port
   on one end only, a port no longer in the netlist, or two outputs or two inputs
   on one wire.
2. **Netlist.** Load the liberty file once, then one Verilog netlist per block. The
   block name comes from the file name (`IpLine_synth.v` → `IpLine`) and is also
   used to find the top module. The **Hierarchy** panel lists the submodules: tick
   *Keep* for one that is a single board (`DekatronModule`), and the rest are
   expanded to cells. A block selector switches between loaded blocks. The tab lists
   instances, nets and block ports, and flags cell types missing from both the
   library and the custom elements. A missing type that the netlist defines as a
   module (`DekatronTubeV2`, `OneShot`, or a kept board) gets an **Add as element**
   button that creates it with pins from its Verilog ports. On **Ports**, add HD-68
   connectors to the block and type a pin such as `J1:17` next to each port bit. On
   **Nets**, tick *Power* for nets that the basket backplane carries; they won't be
   routed.
3. **Elements.** Define parts that aren't liberty cells (a dekatron with its
   drivers, a power module, a connector) with named pins. Each pin has a direction
   and a type: signal, power, ground or clock. Netlist instances of these types then
   count as known.
4. **Modules.** Define PCB designs. Each is 140×140 mm with a 2×36 edge connector
   (`A1..A36`, `B1..B36`) and a width in 12 mm steps. Set the kind (*board*, or a
   small *interconnect* board whose links aren't routed), the Verilog module the
   board replaces (then the Netlist tab keeps it whole), and a power figure for
   reference. *Slots* say which cells the board carries and how many; the tube count
   follows from the liberty. Pick a copy of a cell (`NAND2_J2 #2`) and choose a
   contact for each of its pins. The connector view shows every contact's pins and
   highlights contacts with more than one. **Auto-assign free contacts** fills the
   unmapped signal pins of every copy with the next free contacts in order
   (power and ground pins are skipped). A width that would push a placed module out
   of its row or into a neighbour is refused.
5. **Placement.** The canvas shows the active block from above: the HD-68
   connector strip on top (each connector with its cable), then the baskets with
   the 12 mm grid and the transformer. **Place** puts a module type at the first
   free position; **✚** arms it, then a click on an empty cell places it there.
   Drag a module to move it: it snaps to the grid, a dashed outline shows the drop
   (green if it fits, red if not), and unlocked modules in the way shift aside if
   their half of the row has room. Locked modules (🔒) don't move and block the
   push. Select a module to lock, unlock or remove it. Drag connectors to reorder
   them. The wheel zooms around the pointer; dragging the background pans.
   *Planned:* netlist instances into module slots, HPWL, auto-placement.
6. **Routing** *(planned).* Orthogonal two-pin wire segments run along the
   channels between modules. Auto-routing will use A*, with a manual pencil tool
   for touch-ups.
7. **Assembly** *(planned).* Mark segments as physically wired, filter by
   progress, and export the wiring table.

## Input files

### Liberty (`.lib`)

One file per project. On this branch it is
[`rtl/run/vtube_cells.lib`](../rtl/run/vtube_cells.lib), which has 23 cells. On
`claude_nextGen` it moved to `rtl/vtube/vtube_cells.lib`, which has 27 cells and adds
`NOT_J2`, `OR10_X7`, `NOR10_N16X7`, `RELAY_2CO`, `GUIDE_EN_J2` and a `QN` pin on the
triggers. **Netlists synthesized from the current RTL need the 27-cell file**: they
use `NOT_N16`, `A1OOI_N16J2`, `A2OOI_J2`, `BUF_N16` and `RELAY_2CO`, which the
23-cell file lacks, so with it those cells show as missing and tubes are
undercounted. The parser reads all 27 cells; the `relays(names)` group is ignored.
The parser counts braces, so nested groups are fine. It
reads:

- `cell(NAME) { … }`, plus `area`, `heat_current` and `current_unit`
- `pin(NAME) { direction; function; … }`, along with driver type, fan-out and clock attributes
- the DekatronPC-specific `tubes(names) { N16B: 0.5; X7B: 1; }` group (tubes per cell, fractional for shared double tubes)
- `ff(…)` and `latch(…)`, which mark sequential cells

Timing tables are ignored.

### Verilog netlist (`.v`)

A structural netlist as Yosys writes it. **The project's netlists are hierarchical**,
and they stay that way on purpose: a submodule such as `DekatronModule` becomes one
physical board (owner decision, 2026-10-09, `agents.md` §3.8).

The parser (`services/parsers/verilog.ts`) tokenizes the file, reads every `module`
and then elaborates from the top module down. The top is the block name if a module
has it, otherwise the only module no other module instantiates. An instance is a
**leaf** if:

- its type has no module definition (a liberty cell);
- its module has no instances inside: a Yosys black box such as `DekatronTubeV2`,
  `OneShot` or `Impulse`, which are base elements (Q11);
- its module is in the *keep* list (a whole board, e.g. `DekatronModule`, Q3/Q7).

Every other submodule is expanded. Leaf names are hierarchical paths joined with `/`
(`ipCounter/dek[0].dModule/guideEnA`). Yosys's `$paramod…` names are reduced to the
base module name for `cellType`; the full name is kept in `module`.

**Nets are bit-level.** Each bus bit is its own wire (`MainOneHot[3]`). Nets are
merged across module ports and `assign` statements, and same-named nets in different
instances stay apart. A merged net takes its shallowest user-given name, so `w[0]`
wins over `p0/out[0]` and over Yosys's `_005_`. Pins tied to a constant record it
(`1'b0`, `1'b1`) instead of a net. Pins of a liberty cell that connect to more than
one bit are named `D[3]`…`D[0]` by connection width; pins of defined modules use
their declared bits.

Supported: non-ANSI and ANSI port lists, `wire`/`reg` declarations with ranges,
`assign` (including concatenations on the left), named and positional connections,
part-selects, concatenations and replications, sized constants with `x`/`z`, escaped
identifiers, `(* attributes *)` and comments. Behavioral code (`always`, `initial`,
`function`, `generate`) is rejected with a line number.

Checked against Yosys: for IpLine, ApLine and MachineCtrl the leaf cell counts and
the net of every pin match `hierarchy; setattr -mod -unset keep_hierarchy *; flatten`
exactly. `test/parsers/verilog.test.ts` repeats that check on the checked-in fixture.

The netlists come from `rtl/run/run_tests.sh -s`, which runs `./synth` for IpLine,
ApLine and MachineCtrl (Yosys, `synt_dpc.tcl`, no `-flatten`). **They are not
checked in**, so you need to run synthesis locally to get `IpLine_synth.v` and the
others.

## Physical model

These figures follow the owner's decisions of 2026-09-27 and 2026-10-09, recorded in
`agents.md` §3.7–3.8. A **block** is one functional block (IpLine, ApLine or
MachineCtrl) and one cabinet of the machine. A **row** is one basket (корзина). The
basket backplane carries power only; signals go by wire. HD-68 connectors to other
blocks sit along the top of the block page.

**The chassis, seen from above.** Each block has its own number of rows, 3–5,
stacked vertically. Each row is 140 mm deep (one module) and 420 mm wide (19″
class), which gives 35 grid steps of 12 mm. In the middle of every row sits a
transformer keep-out of 72 + 12·K mm (Q4): 72, 84 (default) or 96 mm, since the
code keeps the old 100 mm limit. The block height is 140 mm × rows.

```
 0                      168       252                     420 mm
 ├──────────────────────┬─────────┬────────────────────────┤
 │ M1 │ M2 │ M3 │ …     │  TRAFO  │  … │ Mk │ Mk+1 │       │  row 0  (140 mm)
 ├──────────────────────┼─────────┼────────────────────────┤
 │                      │  TRAFO  │                        │  row 1
 ├──────────────────────┼─────────┼────────────────────────┤
 │                      │  TRAFO  │                        │  row 2
 └──────────────────────┴─────────┴────────────────────────┘
```

**Modules.** Each module is a 140×140 mm PCB with a 2×36 edge connector. Its width
is a multiple of the 12 mm step: 2 steps (24 mm) for a logic module, 3 steps (36 mm)
for a dekatron module.

**Placement rules** (enforced by `canPlaceModule`). A module must lie inside its
row, must not overlap the transformer span, and must not overlap other modules in
the same row. Moving a locked module is ignored. If a row still holds modules, the
block can't be shrunk below it, and a transformer width that would cover a placed
module is refused.

**Connectors and cables** (Q1, Q9). A block has HD-68 connectors in a row above its
baskets. Each block port bit is put on one connector pin. A cable joins two
connectors of different blocks pin for pin, so the port on pin 17 of one end
connects to the port on pin 17 of the other. One project can hold all three blocks
and the cables between them. Wire segments can end on a connector pin.

**Power** (Q10). Nets marked as power ride on the basket backplane and are not
routed. Small **interconnect boards** (`kind: "interconnect"`) link neighbouring
modules, for example a dekatron with its write and read circuits; their links are
not routed either.

**Tubes.** The tube types are 6N16B (double triode), 6J2B (pentode) and 6X7B (double
diode), plus A110 dekatrons.

## Project file format

A project is saved as `<name>.dpc.json`. The current format is **0.4.0**:

```jsonc
{
  "meta": { "projectName": "DPC", "createdAt": "…", "updatedAt": "…", "version": "0.4.0" },
  "liberty":          { "NAND2_N16X7": { "name": "…", "pins": [ … ], "tubes": { "N16B": 0.5, "X7B": 1 } } },
  "externalElements": { "DEKATRON": { "name": "DEKATRON", "pins": [ { "name": "Clk", "direction": "input", "type": "clock" } ] } },
  "moduleTypes": [                       // PCB designs, shared by all blocks
    { "id": "LOGIC4", "name": "4×NAND2", "kind": "board", "widthSteps": 2,
      "slots": [ { "cellType": "NAND2_N16X7", "count": 4,
                   "pinMaps": [ [ { "cellPin": "A", "contactId": "A1" } ], [], [], [] ] } ] },
    { "id": "DEK", "name": "Dekatron", "kind": "board", "widthSteps": 3, "slots": [ … ],
      "verilogModule": "DekatronModule" }  // kept whole when parsing
  ],
  "block": { "rowHeight": 140, "rowWidth": 420, "gridStep": 12,   // basket geometry, all blocks
             "transformerWidth": 84, "obstructions": [] },
  "blocks": {                            // one per netlist
    "IpLine": {
      "name": "IpLine",
      "rows": 4,
      "netlist":   { "top": "IpLine", "keep": [ "DekatronModule" ],
                     "ports": [ { "name": "insn[3]", "direction": "input", "net": "insn[3]" } ],
                     "instances": [ … ], "nets": [ … ] },
      "connectors": [ { "id": "J1", "type": "HD68", "pins": 68, "position": 0,
                        "ports": [ { "pin": 17, "port": "insn[3]" } ] } ],
      "powerNets": [ "hs_clk" ],
      "placement": {
        "modules":  [ { "id": "M1", "typeId": "LOGIC4", "row": 0, "col": 0, "locked": false } ],
        "elements": [ { "instanceName": "U1", "moduleInstanceId": "M1", "slotIndex": 0, "locked": false } ]
      },
      "routing": { "nets": [ { "netName": "n1", "color": "#e6194b",
                               "segments": [ { "id": "s1", "start": { "moduleInstanceId": "M1", "pin": "A3" },
                                               "end": { "moduleInstanceId": "M2", "pin": "B7" },
                                               "path": [ { "x": 0, "y": 0 } ], "assembled": false },
                                             { "id": "s2", "start": { "moduleInstanceId": "M1", "pin": "A4" },
                                               "end": { "connectorId": "J1", "pin": 17 },
                                               "path": [], "assembled": false } ] } ] }
    }
  },
  "cables": [ { "id": "C1", "from": { "block": "IpLine", "connector": "J1" },
                            "to":   { "block": "MachineCtrl", "connector": "J2" } } ]
}
```

- `slotIndex` is a flat index over a module type's slots: all copies of `slots[0]`
  first, then those of `slots[1]`, and so on. `resolveSlot()` maps it back to
  `(slot, copy)`.
- Editing slots or removing module types or instances automatically drops element
  placements and wire segments that no longer point at anything valid.
- Older files are migrated when opened:
  - pre-0.2: the single netlist becomes a `Legacy` block;
  - 0.2.0: each hardware module becomes a module type plus, where it was placed, an
    instance with the same id. The old chassis geometry has no equivalent, so it is
    reset to the defaults, keeping `rows`;
  - 0.3.0: `rows` moves into every block, the transformer width snaps to 72 + 12·K
    mm (85 → 84), and blocks get empty `connectors` and `powerNets`, the project
    empty `cables`, module types `kind: "board"`.

  Then module instances that no longer fit are dropped, with their elements and
  wires.
- Saved files and the autosave hold project data only, never the undo history.
- `netlist` may also hold `top` (the top module), `keep` (submodules kept whole) and
  `ports` (top-level port bits: `{ "name": "insn[3]", "direction": "input", "net": "insn[3]" }`).
  Instance names are hierarchical paths, connection keys are pin bits, and an
  instance of a kept or black-box module has `"module": "<full Yosys name>"`.
  These fields are optional. Projects saved before 2026-10-09 hold netlists from the
  old flat parser, which merged nets across modules: open the `.v` again and parse
  it. Connector pins and power nets refer to port and net names, so they survive a
  re-parse as long as the names stay.

## Tests

```bash
npm test
```

| File | Covers |
|---|---|
| `test/parsers/liberty.test.ts` | Parses `../rtl/run/vtube_cells.lib`: cells, pins, `tubes`, sequential flags |
| `test/parsers/verilog.test.ts` | `test/fixtures/hier.v`: exact nets, buses, constants, `keep`, black boxes, errors. `IpLine_synth.v`: leaf counts and every pin's net equal to `IpLine_flat.v`, the Yosys-flattened reference |
| `test/store/projectStore.test.ts` | Blocks, multi-netlist, undo/redo, per-block placement |
| `test/store/moduleTypes.test.ts` | Contact ids, tube count, module-type validation, pin-map cleanup, clashes, auto-assign |
| `test/store/interconnect.test.ts` | Rows, transformer snapping, connectors, port pins, cables, cable links and their problems, power nets |
| `test/services/projectIO.test.ts` | Save writes project data only; pre-0.2, 0.2.0 and 0.3.0 → 0.4.0 migration |
| `test/types/placement.test.ts` | Push-aside planning (insert rule, cascades, locks, transformer and row ends), first free spot |
| `test/ui/layout.test.ts` | Canvas layout: row positions, size, grid snapping, cell under the pointer, connector slots |
| `test/ui/app.test.tsx` | jsdom: every tab renders; Netlist tab parses `hier.v` with *Keep* and *Add as element*; connector pin, power net and cable through the UI; Modules tab: type, slot, pin map, clash, auto-assign, width; Placement: place, drag with push-aside, lock refusal, connector reorder; autosave round-trip |

CI: `.github/workflows/webui.yml` runs `npm ci && npm test` on Node 22 for pushes and
pull requests to `master` that touch `webui/` or `rtl/run/vtube_cells.lib`. It can
also be started by hand (*Run workflow*).

Konva needs the native `canvas` package under Node, so `vitest.config.ts` aliases
`react-konva` to `test/mocks/react-konva.tsx`, which renders plain `<div>`s. A test
ends a drag by dispatching a `konva-dragend` event with the drop position. The real
canvas was checked in Chrome (drag, push-aside, lock refusal, click-to-place, zoom).

The liberty test reads `rtl/run/vtube_cells.lib`, which is in git. The netlist tests
use `test/fixtures/IpLine_synth.v`, a checked-in synthesis output, so they pass on a
fresh clone. Regenerate it when the IpLine RTL changes.

`test/test_parsers.mjs` is a standalone smoke test that needs only Node:
`node test/test_parsers.mjs ../rtl/run/vtube_cells.lib <netlist.v>`. It contains its own
copy of the old flat parser (D6), so it no longer matches the app.

## Known issues

Item D6 comes from the review in [`doc/webui_status.md`](../doc/webui_status.md).

| # | Severity | Where | Problem |
|---|---|---|---|
| D6 | Low | `test/test_parsers.mjs` | Has its own inline copy of the old flat parser; it should import `src/services/parsers` or be removed. |
| — | Medium | Modules tab | No KiCad `.net` import yet (REQ-PR-004). `sch/logic` holds cell sketches, not a module board with the 2×36 connector, so there is nothing real to match against. |
| — | Low | Modules tab | A contact can carry several pins on purpose (a shared input or clock), so clashes are only highlighted, never refused. |
| — | Low | Netlist tab | Port bits go on connector pins one at a time. Once the RTL groups inter-block ports into one wire struct per connector (`doc/webui_review.md` §6), a bulk assignment would help. |
| — | Low | `tsconfig.json` | `baseUrl` is deprecated in TypeScript 6. Harmless with the pinned `~5.8`. |

Fixed in `c51ecfa`: D3 (some edits weren't undoable) and D5 (stale `activeBlockId`
after undo). D7 (the README overstated features) is fixed by this README. N6 (`agents.md`
described the 0.2 format) was fixed on 2026-10-09. Fixed on 2026-10-09: N1 and N2 (the
build failed and the Project tab threw on render), N3 and N5 (tests used a removed
store action and an untracked netlist), N4 (no 0.2.0 migration), D1 (undo history
written to files), D2 (autosave never restored) and D4 (stale missing-types check).
H1 (the parser ignored `module` boundaries) was fixed on 2026-10-09 by the
hierarchical parser. H2 (no block connectors, cables, power nets or interconnect
boards) was fixed on 2026-10-09 by format 0.4.0.

## Roadmap

Steps 1–5 follow the 2026-10-09 review ([`doc/webui_review.md`](../doc/webui_review.md) §6–7)
and are done; see [`doc/webui_progress.md`](../doc/webui_progress.md) for what each
delivered and how it was checked. Next, from the same report (§7):

| Step | Scope | Done when |
|---|---|---|
| ~~1–5~~ | Build fixes, hierarchical parser, format 0.4.0, Modules tab, Placement canvas | ✅ `3f49d98` … |
| 6 | Netlist cells into module slots: drag from an unplaced list, displacement, capacity check per cell type, tube summary per block and basket | every leaf of a block can be placed by hand; capacity matches the netlist |
| 7 | Live HPWL: contact positions from pin maps, per-net and total, clock weighting, net highlight | HPWL behaves on a hand-made example |
| 8 | Auto-placement in a Web Worker: Hungarian assignment of cells to slots, simulated annealing of modules, locks honoured | beats random placement on IpLine, repeatable with a seed |
| 9 | Routing: channel graph, A* per two-pin link (MST for multi-pin nets), connector pins as ends, power and interconnect skipped, pencil tool, colours | every non-power net routed or listed as failed |
| 10 | Assembly and export: mark built wires, CSV/JSON wiring table, PNG/SVG | — |

Alongside: the nextGen liberty and a current-RTL netlist as fixtures, KiCad `.net`
import once a module board exists, bulk port-to-pin assignment once the RTL groups
the ports, load the Placement tab on demand (bundle > 500 kB), retire
`test/test_parsers.mjs` (D6).

Open questions:

- Does the inter-module wiring channel need a width of its own?
- The transformer is centred in the 420 mm row. At 84 mm its edges (168 and 252 mm)
  fall on the 12 mm grid; at 72 or 96 mm they fall half a step off it. Should it be
  centred, or aligned to the grid?
- Should the transformer be allowed wider than 96 mm? The old 70–100 mm limit is
  kept for now.

## Repository layout

```
webui/
├── index.html, vite.config.ts, vitest.config.ts, tsconfig.json
├── package.json, package-lock.json
├── agents.md              # Full functional spec (Russian), written for AI coding agents
├── dev_server.bat         # Windows: start the dev server
├── src/                   # Application code: see src/README.md
└── test/                  # Vitest suites (parsers/, store/) + standalone test_parsers.mjs/.bat
```

## Related documents

- [`../doc/webui_progress.md`](../doc/webui_progress.md): the 2026-10-09 progress
  report: steps 1–5, verification, what the netlists show (cells, tubes, space),
  decisions to confirm, open questions and the plan for steps 6–10.
- [`src/README.md`](src/README.md): code architecture, store design and conventions
  for contributors.
- [`agents.md`](agents.md): the full specification (Russian), covering features, data
  model, algorithms and the staged plan.
- [`../doc/webui_review.md`](../doc/webui_review.md): the 2026-10-09 review against
  the computer project (`claude_nextGen`). It covers inputs, the physical model,
  findings F1–F13, owner decisions Q1–Q11 and the TODO list.
- [`../doc/webui_status.md`](../doc/webui_status.md): the 2026-09-27 status review
  and owner decisions.
- [`../.kilo/plans/`](../.kilo/plans/): implementation and master plans written by
  KiloCode.
- TRS §17, REQ-PR-001..010: the P&R requirements in the project requirements document.

The first stages were written with KiloCode (DeepSeek V4 Pro). The 0.3.0 model
refactor and this documentation were done with Claude.
