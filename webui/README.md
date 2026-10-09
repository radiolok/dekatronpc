# DekatronPC Block Place & Route (Web UI)

A browser-based physical-design tool for the [DekatronPC](https://github.com/radiolok/dekatronpc)
vacuum-tube computer. It takes the gate-level netlist that Yosys produces against the
tube cell library and helps turn it into hardware: which logic cell goes into which
tube module, where each module sits in the chassis, and how the modules are wired
together. The end product is a wiring list you can build the machine from.

> **Status: early development (Stage 1 of 7).** Project management, netlist/liberty
> import (hierarchical, bit-level), multi-block projects and the custom-element
> editor work. Modules, Placement,
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
| 1 | Multi-block projects (2–3 netlists, shared library/modules/chassis) | ✅ Done |
| 2 | **Elements** tab: custom elements not in the library (e.g. dekatron) | ✅ Done |
| 2 | Data model v0.3.0: `ModuleType` + per-block `ModuleInstance`, per-copy pin maps, top-view chassis | ✅ In store, types and the Project tab |
| 2 | **Modules** tab: module-type editor, 2×36 connector, slot pin maps | ⏳ Store actions only |
| 2 | KiCad netlist import for module pin maps | ⏳ Not started |
| 3–4 | **Placement** canvas (Konva): rows, 12 mm grid, drag / lock | ⏳ Not started. `konva` is a dependency but unused |
| 3–4 | Auto-placement (simulated annealing, Hungarian assignment) | ⏳ Not started |
| 5 | **Routing**: channel graph, A*, manual pencil | ⏳ Store actions only |
| 6 | **Assembly**: mark wired segments, CSV/JSON/PNG/SVG export | ⏳ Store actions only |

The source is about 3.4 k lines of TS/TSX plus about 650 lines of tests.

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
   file, and see summary counters.
2. **Netlist.** Load the liberty file once, then one Verilog netlist per block. The
   block name comes from the file name (`IpLine_synth.v` → `IpLine`) and is also
   used to find the top module. The **Hierarchy** panel lists the submodules: tick
   *Keep* for one that is a single board (`DekatronModule`), and the rest are
   expanded to cells. A block selector switches between loaded blocks. The tab lists
   instances, nets and block ports, and flags cell types missing from both the
   library and the custom elements. A missing type that the netlist defines as a
   module (`DekatronTubeV2`, `OneShot`, or a kept board) gets an **Add as element**
   button that creates it with pins from its Verilog ports.
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

One file per project. On this branch it is
[`rtl/run/vtube_cells.lib`](../rtl/run/vtube_cells.lib), which has 23 cells. On
`claude_nextGen` it moved to `rtl/vtube/vtube_cells.lib`, which has 27 cells and adds
`NOT_J2`, `OR10_X7`, `NOR10_N16X7`, `RELAY_2CO`, `GUIDE_EN_J2` and a `QN` pin on the
triggers. The parser reads all 27 cells; the `relays(names)` group is ignored. The parser counts braces, so nested groups are fine. It
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

**The chassis, seen from above.** It has 3–5 rows stacked vertically. Each row is
140 mm deep (one module) and 420 mm wide (19″ class), which gives 35 grid steps of
12 mm. In the middle of every row sits a transformer keep-out. The code currently
allows 70–100 mm (85 mm by default); the decision is 72 + 12·K mm, a whole number of
grid steps. The chassis height is 140 mm × rows.

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
- Older files are migrated when opened. A pre-0.2 single-netlist file becomes a
  `Legacy` block. In a 0.2.0 file each hardware module becomes a module type plus,
  where it was placed, an instance with the same id. The old chassis geometry has no
  0.3.0 equivalent, so the chassis is reset to the defaults (keeping `rows`).
  Placements that don't fit the new rows are dropped, with their elements and wires.
- Saved files and the autosave hold project data only, never the undo history.
- `netlist` may also hold `top` (the top module), `keep` (submodules kept whole) and
  `ports` (top-level port bits: `{ "name": "insn[3]", "direction": "input", "net": "insn[3]" }`).
  Instance names are hierarchical paths, connection keys are pin bits, and an
  instance of a kept or black-box module has `"module": "<full Yosys name>"`.
  These fields are optional, so the format stays 0.3.0. Projects saved before
  2026-10-09 hold netlists from the old flat parser, which merged nets across
  modules: open the `.v` again and parse it.

## Tests

```bash
npm test
```

| File | Covers |
|---|---|
| `test/parsers/liberty.test.ts` | Parses `../rtl/run/vtube_cells.lib`: cells, pins, `tubes`, sequential flags |
| `test/parsers/verilog.test.ts` | `test/fixtures/hier.v`: exact nets, buses, constants, `keep`, black boxes, errors. `IpLine_synth.v`: leaf counts and every pin's net equal to `IpLine_flat.v`, the Yosys-flattened reference |
| `test/store/projectStore.test.ts` | Blocks, multi-netlist, undo/redo, per-block placement |
| `test/services/projectIO.test.ts` | Save writes project data only; pre-0.2 and 0.2.0 → 0.3.0 migration |
| `test/ui/app.test.tsx` | jsdom: every tab renders; Netlist tab parses `hier.v` with *Keep* and *Add as element*; autosave round-trip |

CI: `.github/workflows/webui.yml` runs `npm ci && npm test` on Node 22 for pushes and
pull requests to `master` that touch `webui/` or `rtl/run/vtube_cells.lib`. It can
also be started by hand (*Run workflow*).

The liberty test reads `rtl/run/vtube_cells.lib`, which is in git. The netlist tests
use `test/fixtures/IpLine_synth.v`, a checked-in synthesis output, so they pass on a
fresh clone. Regenerate it when the IpLine RTL changes.

`test/test_parsers.mjs` is a standalone smoke test that needs only Node:
`node test/test_parsers.mjs ../rtl/run/vtube_cells.lib <netlist.v>`. It contains its own
copy of the old flat parser (D6), so it no longer matches the app.

## Known issues

Item D6 comes from the review in [`doc/webui_status.md`](../doc/webui_status.md).
H2 comes from the review against the computer project on 2026-10-09
([`doc/webui_review.md`](../doc/webui_review.md), where it is F2/F4).

| # | Severity | Where | Problem |
|---|---|---|---|
| H2 | High | model | A block has no HD-68 connectors to other blocks, and block netlists aren't linked, so the whole computer can't be routed in one project. Power-net flag and small interconnect boards are missing too. Planned for format 0.4.0 (`agents.md` §4). |
| D6 | Low | `test/test_parsers.mjs` | Has its own inline copy of the old flat parser; it should import `src/services/parsers` or be removed. |
| — | Medium | Netlist tab | The *keep* list is per parse, not linked to a `ModuleType`. Linking a Verilog module to a board type is part of format 0.4.0. |
| — | Low | `tsconfig.json` | `baseUrl` is deprecated in TypeScript 6. Harmless with the pinned `~5.8`. |

Fixed in `c51ecfa`: D3 (some edits weren't undoable) and D5 (stale `activeBlockId`
after undo). D7 (the README overstated features) is fixed by this README. N6 (`agents.md`
described the 0.2 format) was fixed on 2026-10-09. Fixed on 2026-10-09: N1 and N2 (the
build failed and the Project tab threw on render), N3 and N5 (tests used a removed
store action and an untracked netlist), N4 (no 0.2.0 migration), D1 (undo history
written to files), D2 (autosave never restored) and D4 (stale missing-types check).
H1 (the parser ignored `module` boundaries) was fixed on 2026-10-09 by the
hierarchical parser.

## Roadmap

The order below follows the 2026-10-09 review ([`doc/webui_review.md`](../doc/webui_review.md) §6–7):

1. ~~Fix N1–N5 and D1, D2 and D4 so that `main` builds, runs and passes tests.~~ Done.
2. ~~**Hierarchical netlist parser** (H1). A submodule mapped to a module type becomes
   one module instance; other submodules expand to base elements.~~ Done: kept
   submodules stay whole; the link from a kept module to a `ModuleType` moves to step 3.
3. **Format 0.4.0** (H2). Add HD-68 block connectors, cables between blocks, a power
   flag on nets, small interconnect boards and the Verilog module → `ModuleType`
   link, so all three blocks can be routed in one project.
4. **Modules tab.** A module-type library editor: width in 12 mm steps, a 2×36
   connector view, and slots with per-copy contact assignment. Manual entry comes
   first (REQ-PR-006), then KiCad `.net` S-expression import (REQ-PR-004).
5. **Placement canvas** (Konva): rows, 12 mm grid, transformer keep-out, and
   placing, dragging and locking module instances (REQ-PR-007).
6. Then: element-to-slot placement, HPWL, auto-placement, routing, assembly and export.

Open question: does the inter-module wiring channel need a width of its own?

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
