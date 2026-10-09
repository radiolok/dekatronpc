# DekatronPC Block Place & Route (Web UI)

A browser-based physical-design tool for the [DekatronPC](https://github.com/radiolok/dekatronpc)
vacuum-tube computer. It takes the gate-level netlist that Yosys produces against the
tube cell library and helps turn it into hardware: which logic cell goes into which
tube module, where each module sits in the chassis, and how the modules are wired
together. The end product is a wiring list you can build the machine from.

> **Status: early development (Stage 1 of 7).** Project management, netlist/liberty
> import, multi-block projects and the custom-element editor work. Modules, Placement,
> Routing and Assembly are placeholder tabs. See [Status](#status) and
> [Known issues](#known-issues) before using it.

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
separately into a flat structural netlist of tube cells (`NAND2_N16X7`, `DFF`, …).
The tool loads one netlist per block. All blocks share one cell library, one set of
module designs and one chassis geometry.

## Status

| Stage | Area | State |
|---|---|---|
| 1 | Vite + React + TypeScript skeleton, tab shell | ✅ Done |
| 1 | Zustand + Immer store with undo/redo (50 steps) | ✅ Done. Every edit is undoable |
| 1 | JSON project save / open | ✅ Done (see D1: saves extra state) |
| 1 | Autosave to `localStorage` every 30 s | ⚠️ Writes only. Never restored on start (D2) |
| 1 | Liberty parser (`vtube_cells.lib`, incl. `tubes`, `ff`, `latch`) | ✅ Done, unit-tested |
| 1 | Verilog parser (Yosys flat structural) | ✅ Done, unit-tested |
| 1 | Multi-block projects (2–3 netlists, shared library/modules/chassis) | ✅ Done |
| 2 | **Elements** tab: custom elements not in the library (e.g. dekatron) | ✅ Done |
| 2 | Data model v0.3.0: `ModuleType` + per-block `ModuleInstance`, per-copy pin maps, top-view chassis | ✅ In store and types. UI not migrated yet (N1, N2) |
| 2 | **Modules** tab: module-type editor, 2×36 connector, slot pin maps | ⏳ Store actions only |
| 2 | KiCad netlist import for module pin maps | ⏳ Not started |
| 3–4 | **Placement** canvas (Konva): rows, 12 mm grid, drag / lock | ⏳ Not started. `konva` is a dependency but unused |
| 3–4 | Auto-placement (simulated annealing, Hungarian assignment) | ⏳ Not started |
| 5 | **Routing**: channel graph, A*, manual pencil | ⏳ Store actions only |
| 6 | **Assembly**: mark wired segments, CSV/JSON/PNG/SVG export | ⏳ Store actions only |

The source is about 2.6 k lines of TS/TSX plus about 360 lines of tests.

## Quick start

Requirements: **Node.js 20+** (developed on 22) and npm.

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

The app runs entirely in the browser. There is no backend, and files are opened
through the browser's file picker.

## Workflow

The UI is a row of tabs, one per design stage. You can switch tabs at any time; they
all edit one shared project. **Undo** / **Redo** (`Ctrl+Z`, `Ctrl+Y` or
`Ctrl+Shift+Z`) work across all tabs.

1. **Project.** Name the project, create a new one, open or save a `.dpc.json`
   file, and see summary counters.
2. **Netlist.** Load the liberty file once, then one Verilog netlist per block. The
   block name comes from the file name (`IpLine_synth.v` → `IpLine`). A block selector
   switches between loaded blocks. The tab lists instances and nets, and flags
   cell types missing from both the library and the custom elements.
3. **Elements.** Define parts that aren't liberty cells (a dekatron with its
   drivers, a power module, a connector) with named pins. Each pin has a direction
   and a type: signal, power, ground or clock. Netlist instances of these types then
   count as known.
4. **Modules** *(planned).* Define PCB designs. Each is 140×140 mm with a 2×36
   edge connector (`A1..A36`, `B1..B36`) and a width in 12 mm steps. Its *slots* say
   which cells it carries and how many, and each copy of a cell maps its pins to its
   own connector contacts.
5. **Placement** *(planned).* Place module instances on the chassis grid, then
   place netlist instances into module slots. Manual drag and lock come first,
   auto-placement later.
6. **Routing** *(planned).* Orthogonal two-pin wire segments run along the
   channels between modules. Auto-routing will use A*, with a manual pencil tool
   for touch-ups.
7. **Assembly** *(planned).* Mark segments as physically wired, filter by
   progress, and export the wiring table.

## Input files

### Liberty (`.lib`)

One file per project, normally [`rtl/run/vtube_cells.lib`](../rtl/run/vtube_cells.lib)
(23 cells: `BUF_*`, `NOT_*`, `NAND*`, `NOR*`, `OR*`, `AND2`, `A*OOI`, `LATCH`, `DFF`,
`DFFSR*`, `TIEHI`, `TIELO`). The parser counts braces, so nested groups are fine. It
reads:

- `cell(NAME) { … }`, plus `area`, `heat_current` and `current_unit`
- `pin(NAME) { direction; function; … }`, along with driver type, fan-out and clock attributes
- the DekatronPC-specific `tubes(names) { N16B: 0.5; X7B: 1; }` group (tubes per cell, fractional for shared double tubes)
- `ff(…)` and `latch(…)`, which mark sequential cells

Timing tables are ignored.

### Verilog netlist (`.v`)

A flat structural netlist as Yosys writes it:

```verilog
wire [3:0] bus;  wire n1, n2;
NAND2_N16X7 U1 (.A(a), .B(b), .Y(n1));
\$paramod\Dekatron\WIDTH=10  dek0 (.Clk(clk), .Out(bus[0]));
```

It supports scalar and bus `wire` declarations, escaped identifiers (`\$paramod…`),
bit-selects and part-selects (folded to the base net name) and constants (`1'b0`,
`4'h3`, which are skipped as nets). Comments are stripped. Hierarchy and `assign`
statements are not supported, so flatten before export (`flatten; opt_clean`).

The netlists come from `rtl/run/synth` (Yosys + `vtube_cells.lib`). **They are not
checked in**, so you need to run synthesis locally to get `IpLine_synth.v` and the
others.

## Physical model

These figures follow the owner's 2026-09-27 decisions, recorded in `agents.md` §3.7 and
`doc/webui_status.md` §5.

**The chassis, seen from above.** It has 3–5 rows stacked vertically. Each row is
140 mm deep (one module) and 420 mm wide (19″ class), which gives 35 grid steps of
12 mm. In the middle of every row sits a transformer keep-out 70–100 mm wide (85 mm
by default). The chassis height is 140 mm × rows.

```
 0                     167.5     252.5                    420 mm
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
chassis can't be shrunk below it.

**Tubes.** The tube types are 6N16B (double triode), 6J2B (pentode) and 6X7B (double
diode), plus A110 dekatrons.

## Project file format

A project is saved as `<name>.dpc.json`. The current format is **0.3.0**:

```jsonc
{
  "meta": { "projectName": "DPC", "createdAt": "…", "updatedAt": "…", "version": "0.3.0" },
  "liberty":          { "NAND2_N16X7": { "name": "…", "pins": [ … ], "tubes": { "N16B": 0.5, "X7B": 1 } } },
  "externalElements": { "DEKATRON": { "name": "DEKATRON", "pins": [ { "name": "Clk", "direction": "input", "type": "clock" } ] } },
  "moduleTypes": [                       // PCB designs, shared by all blocks
    { "id": "LOGIC4", "name": "4×NAND2", "widthSteps": 2,
      "slots": [ { "cellType": "NAND2_N16X7", "count": 4,
                   "pinMaps": [ [ { "cellPin": "A", "contactId": "A1" } ], [], [], [] ] } ] }
  ],
  "block": { "rows": 3, "rowHeight": 140, "rowWidth": 420, "gridStep": 12,
             "transformerWidth": 85, "obstructions": [] },
  "blocks": {                            // one per netlist
    "IpLine": {
      "name": "IpLine",
      "netlist":   { "instances": [ … ], "nets": [ … ] },
      "placement": {
        "modules":  [ { "id": "M1", "typeId": "LOGIC4", "row": 0, "col": 0, "locked": false } ],
        "elements": [ { "instanceName": "U1", "moduleInstanceId": "M1", "slotIndex": 0, "locked": false } ]
      },
      "routing": { "nets": [ { "netName": "n1", "color": "#e6194b",
                               "segments": [ { "id": "s1", "start": { "moduleInstanceId": "M1", "pin": "A3" },
                                               "end": { "moduleInstanceId": "M2", "pin": "B7" },
                                               "path": [ { "x": 0, "y": 0 } ], "assembled": false } ] } ] }
    }
  }
}
```

- `slotIndex` is a flat index over a module type's slots: all copies of `slots[0]`
  first, then those of `slots[1]`, and so on. `resolveSlot()` maps it back to
  `(slot, copy)`.
- Editing slots or removing module types or instances automatically drops element
  placements and wire segments that no longer point at anything valid.
- Files in the pre-0.2 single-netlist format are migrated into a `Legacy` block when
  opened. **There is no migration from 0.2.0 to 0.3.0 yet** (N4).

## Tests

```bash
npm test
```

| File | Covers |
|---|---|
| `test/parsers/liberty.test.ts` | Parses `../rtl/run/vtube_cells.lib`: cells, pins, `tubes`, sequential flags |
| `test/parsers/verilog.test.ts` | Parses `../rtl/run/IpLine_synth.v`: instances, nets, escaped names |
| `test/store/projectStore.test.ts` | Blocks, multi-netlist, undo/redo, per-block placement |

CI: `.github/workflows/webui.yml` runs `npm ci && npm test` on Node 22 for pushes and
pull requests to `master` that touch `webui/` or `rtl/run/vtube_cells.lib`. It can
also be started by hand (*Run workflow*).

The tests read real files from `rtl/run/`. `IpLine_synth.v` is a synthesis output
that is **not in the repository**, so `verilog.test.ts` and the netlist-based store
tests fail on a fresh clone (N5).

`test/test_parsers.mjs` is a standalone smoke test that needs only Node:
`node test/test_parsers.mjs ../rtl/run/vtube_cells.lib <netlist.v>`. It contains its own
copy of the parser code (D6).

## Known issues

Status as of branch head `c51ecfa`. Items D1–D7 come from the review in
[`doc/webui_status.md`](../doc/webui_status.md). Items N1–N6 were introduced by the
0.3.0 model refactor, which changed `types/` and `store/` but not their consumers.

| # | Severity | Where | Problem |
|---|---|---|---|
| N2 | **Blocker** | `ProjectManager.tsx` | Reads `modules.length`, `block.maxCols` and `block.verticalPitch.toFixed()`, none of which exist in 0.3.0. The Project tab is the default tab, so the app throws on first render. |
| N1 | **Blocker** | `App.tsx` | Destructures `pushHistory`, which no longer exists. `tsc -b` fails, so `npm run build` fails. The dev server still runs. |
| N3 | High | `projectStore.test.ts` | Calls `setModulePlacements` and expects `moduleId`. Should use `addModuleInstance` and `typeId`. |
| N4 | High | `projectIO.ts` | No `0.2.0 → 0.3.0` migration. Opening an older project leaves `moduleTypes` undefined. |
| N5 | Medium | tests | Depend on the untracked `rtl/run/IpLine_synth.v`. They need small checked-in fixtures (`test/fixtures/`). |
| N6 | Low | `agents.md` §3.3, §4 | The JSON model and chassis description still show the old format (`modules`, `slotInstances`, `maxCols`, `verticalPitch`). |
| D1 | Medium | `App.tsx` save / autosave | Passes the whole store, so `past` and `future` (up to 50 snapshots) get written to disk and `localStorage`. It should use `pickProjectState()`. |
| D2 | Medium | `projectIO.loadAutosave` | Never called on start, so autosave can't be recovered. |
| D4 | Low | `NetlistPanel.tsx` | The `missingTypes` memo reads the library through `getState()` and doesn't re-run when the library or elements change. |
| D6 | Low | `test/test_parsers.mjs` | Has its own inline copy of the parsers, which will drift from `src/services/parsers`. |
| — | Low | `tsconfig.json` | `baseUrl` is deprecated in TypeScript 6. Harmless with the pinned `~5.8`. |

Fixed in `c51ecfa`: D3 (some edits weren't undoable) and D5 (stale `activeBlockId`
after undo). D7 (the README overstated features) is fixed by this README.

## Roadmap

The next stage, agreed 2026-09-27, doesn't depend on synthesized netlists:

1. Fix N1–N5 and D1, D2 and D4 so that `main` builds, runs and passes tests.
2. **Modules tab.** A module-type library editor: width in 12 mm steps, a 2×36
   connector view, and slots with per-copy contact assignment. Manual entry comes
   first (REQ-PR-006), then KiCad `.net` S-expression import (REQ-PR-004).
3. **Placement canvas** (Konva): rows, 12 mm grid, transformer keep-out, and
   placing, dragging and locking module instances (REQ-PR-007).
4. Then: element-to-slot placement, HPWL, auto-placement, routing, assembly and export.

Open questions: should the transformer be a placeable module type or a fixed
per-row keep-out? Does the inter-module wiring channel need a width of its own?

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

- [`src/README.md`](src/README.md): code architecture, store design and conventions
  for contributors.
- [`agents.md`](agents.md): the full specification (Russian), covering features, data
  model, algorithms and the staged plan.
- [`../doc/webui_status.md`](../doc/webui_status.md): the 2026-09-27 status review
  and owner decisions.
- [`../.kilo/plans/`](../.kilo/plans/): implementation and master plans written by
  KiloCode.
- TRS §17, REQ-PR-001..010: the P&R requirements in the project requirements document.

The first stages were written with KiloCode (DeepSeek V4 Pro). The 0.3.0 model
refactor and this documentation were done with Claude.
