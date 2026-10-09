# Web UI (Block Place & Route) — status review, 2026-09-27

> Superseded in part by [`webui_review.md`](webui_review.md) (2026-10-09). That review covers
> the inputs from the computer project, the physical model and owner decisions Q1–Q11.

Scope: `webui/` on branch `webui` (head `d1e41da`), measured against `webui/agents.md`
(the P&R spec) and TRS §17 (REQ-PR-001..010). Static review only: Node.js is not
installed on the review node, so `npm test` / `vite build` were **not** run.

## 1. What exists

| Stage (agents.md §8) | State |
|---|---|
| 1. Foundation: Vite + React 19 + TS, Zustand + Immer store, undo/redo, JSON load/save, autosave | Done, with defects (§3) |
| 1. Parsers: Verilog (Yosys flat structural), Liberty (`vtube_cells.lib`, incl. `tubes`, ff/latch) | Done, unit-tested (vitest) |
| Multi-block (IpLine / ApLine / MachineCtrl share liberty, modules, chassis) | Done in model and Netlist tab |
| 2. Elements tab (custom elements, e.g. DEKATRON stub, REQ-PR-003) | Done |
| 2. Modules tab, KiCad netlist parser (REQ-PR-004) | **Not started** — placeholder tab; store actions exist |
| 3–4. Placement canvas, drag, lock, HPWL | **Not started** — Konva is a dependency, but nothing uses it |
| 5. Routing (channel graph, A*, pencil) | **Not started** — only store actions |
| 6. Assembly / export (REQ-PR-008) | **Not started** |

About 2.9k lines of TS/TSX. Tests: `liberty.test.ts`, `verilog.test.ts`, `projectStore.test.ts` (10 store cases).

## 2. Data-model problems that block the next stages

These must be settled before Modules/Placement are built on top of the model.

1. **Module type and module instance are the same object.** `HardwareModule` is a PCB
   *design* (slots, pin map), but `ModulePlacement` is keyed by `moduleId`, so each design
   can be placed only once per block. A chassis needs dozens of copies of the same logic
   PCB. Needed: `ModuleType` (shared library) + `ModuleInstance {id, typeId, row, col, locked}` per block.
2. **`slotInstances` lives on the shared module**, while placement is per block, so
   two blocks overwrite each other's slot occupancy. It also duplicates
   `ElementPlacement.slotIndex`. Occupancy should be derived from the per-block placement only.
3. **One pin mapping per slot, not per instance.** `ModuleSlot {cellType, count, pinMapping[]}`
   maps cell pins to connector contacts once, but `count` instances need `count`
   different contact sets (e.g. 4× NAND2 → 12 contacts).
4. **Chassis geometry is inconsistent.** `verticalPitch = 178/3 ≈ 59 mm` against a
   140 mm module; 3 × 140 = 420 matches the chassis depth, not its height. `maxCols = 24`
   is described as "positions" but `col` is in 12 mm steps (920 mm ≈ 76 steps).
   "3 rows = IpLine, ApLine, MachineCtrl" mixes chassis rows with computational blocks.
   The view (top vs. front) and the real pitch need to come from the owner.

## 3. Defects in existing code

| # | Where | Defect |
|---|---|---|
| D1 | `App.tsx` autosave, `saveProjectToFile` | The whole store is serialized, including `past`/`future` (up to 50 full snapshots) → oversized files, localStorage quota errors swallowed silently. Only `ProjectState` fields should be saved. |
| D2 | `projectIO.loadAutosave` | Never called: autosave is written but never restored on start. |
| D3 | `projectStore.ts` | No undo entry for `lockModule`, `lockElement`, `updateSlotInModule`, `removeSlotFromModule`, `setSlotInstance`, `updateRoutedNet`, all segment ops, `markSegmentAssembled`. Undo skips these edits or folds them into the previous step. |
| D4 | `NetlistPanel.tsx` `missingTypes` | `useMemo` depends only on `activeNetlist` and reads liberty via `getState()` → the "missing cell types" list goes stale after liberty or elements are loaded. |
| D5 | `undo`/`redo` | `activeBlockId` is not validated after restore; can point to a block that the undo removed. |
| D6 | `test_parsers.mjs` | Inline copy of the parser logic; will drift from `src/services/parsers`. |
| D7 | `README.md` | States SA / Hungarian / A* as features; none are implemented. |

## 4. Proposed next stage — independent of logic-module artifacts

Goal: move to Modules → Placement without depending on synthesis output of
IpLine/ApLine/MachineCtrl (no `*_synth.v` in the repo; `rtl/run/synth` needs Yosys).
All tests use small hand-written fixtures in `webui/src/**/__fixtures__`.

1. Fix D1–D5 (small, isolated).
2. Model refactor per §2 (ModuleType / ModuleInstance, per-instance pin map,
   per-block occupancy), with a project-format migration `0.2.0 → 0.3.0`.
3. Modules tab: module-type library editor (width in 12 mm steps, 2×36 connector
   view A1..A36/B1..B36, slots with per-instance contact assignment). Manual first
   (REQ-PR-006); KiCad `.net` import after.
4. Chassis/Placement canvas (Konva): rows, 12 mm grid, place/drag/lock module
   instances, obstruction rectangles. No element auto-placement yet (REQ-PR-007).
5. KiCad netlist parser (S-expression) with a fixture file.

Routing, HPWL and export depend on a netlist and stay after this stage.

## 5. Owner decisions (2026-09-27)

- **Scope.** The next stage must not need synthesized netlists of the logic modules
  (IpLine/ApLine/MachineCtrl). Modules tab and chassis/placement canvas are built and
  tested on hand-written fixtures.
- **Model.** Split `HardwareModule` into a shared `ModuleType` (PCB design) and a
  per-block `ModuleInstance {id, typeId, row, col, locked}`; per-instance pin map;
  project format migration `0.2.0 → 0.3.0`.
- **Chassis geometry (top view).** 3–5 rows; each row is 140 mm tall (module depth);
  row width 420 mm (19" rack class) → 35 steps of 12 mm; overall height =
  140 mm × rows. Each row has a thick transformer module in the middle, width
  70–100 mm, editable. The current defaults (`verticalPitch = 178/3`, `chassisWidth = 920`,
  `maxCols = 24`) are wrong and will be replaced.

Open: whether the transformer is a placeable (lockable) module type or a fixed
per-row keep-out; whether the inter-module wiring channel has a width of its own.
