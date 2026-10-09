# Web UI source: architecture guide

This guide is for contributors and coding agents working on `webui/src`. For what the
tool does and how to run it, see [`../README.md`](../README.md). The full functional
spec is [`../agents.md`](../agents.md) (in Russian).

## Layout

```
src/
├── main.tsx                     # React root
├── components/
│   ├── App.tsx / App.css        # Shell: header toolbar, tab bar, tab router, autosave timer
│   ├── ProjectManager/          # "Project" tab: name, new/open/save, geometry, blocks, cables
│   ├── Netlist/NetlistPanel.tsx # "Netlist" tab: liberty + per-block Verilog import, keep list,
│   │                            #   connectors and port pins, power nets
│   ├── Elements/ElementEditor.tsx  # "Elements" tab: custom (non-liberty) elements
│   └── Modules/ModuleEditor.tsx    # "Modules" tab: module types, slots, pin maps, connector view
├── hooks/useKeyboardShortcuts.ts   # Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z
├── services/
│   ├── parsers/liberty.ts       # .lib → Record<cell, LibertyCell>
│   ├── parsers/verilog.ts       # hierarchical structural .v → bit-level ParsedNetlist
│   ├── interconnect.ts          # cable links between blocks, port locations, board modules
│   └── projectIO.ts             # JSON (de)serialize, migration, file dialogs, localStorage autosave
├── store/projectStore.ts        # The single Zustand store (data + actions + history)
├── types/project.ts             # Data model, defaults, pure geometry/slot helpers
└── utils/helpers.ts             # clamp, uid, stringToColor, routing palette, distances
```

Each folder re-exports through an `index.ts`. Import with the `@/` alias, which
`vite.config.ts`, `vitest.config.ts` and `tsconfig.json` all map to `src/`:

```ts
import { useProjectStore } from '@/store';
import type { ModuleType } from '@/types';
```

## Layering rules

```
components ──► store ──► types
     │           │
     └──► services ──► types
```

- **`types/`** holds plain data and pure functions only (`fitsInRow`,
  `canPlaceModule`, `resolveSlot`, `snapTransformerWidth`, `contactUsage`,
  `moduleTubes`, `pickProjectState`, …). It has no React or Zustand imports, which lets
  it run in tests and later in Web Workers (placer and router).
- **`services/`** holds parsers, I/O and derived views (`interconnect.ts`). It has
  no store imports: a parser takes text and returns typed data.
- **`store/`** is the only place where project data changes.
- **`components/`** read from the store with selectors and call store actions. They
  never mutate data directly.

## Data model

All of it is in `types/project.ts`. `ProjectState` is what gets saved:

| Field | Scope | Notes |
|---|---|---|
| `meta` | project | name, timestamps, format `version` (`PROJECT_FORMAT_VERSION = '0.4.0'`) |
| `liberty` | shared | parsed `.lib` cells |
| `externalElements` | shared | user-defined parts with typed pins |
| `moduleTypes` | shared | PCB designs: `kind` (`board` / `interconnect`), `widthSteps`, `slots[{cellType, count, pinMaps[copy][]}]`, optional `verilogModule` |
| `block` | shared | basket geometry (`BlockConfig`): row size, grid step, transformer width, obstructions |
| `blocks[name]` | per block | `rows`, `netlist`, `connectors`, `powerNets`, `placement.modules` (`ModuleInstance[]`), `placement.elements`, `routing.nets` |
| `cables` | project | `{id, from: {block, connector}, to: {block, connector}}` |

**Type vs. instance.** A `ModuleType` describes one PCB design. A `ModuleInstance`
(`{id, typeId, row, col, locked}`) is one physical copy of it in one block. Instance
ids (`M1`, `M2`, …) are unique only within their block.

**Slots.** `ModuleSlot.count` copies of `cellType`, and `pinMaps[i]` maps copy `i`'s
cell pins to connector contacts (`CONTACT_IDS`: `A1..A36`, `B1..B36`).
`contactUsage(type)` gives contact → pins; more than one pin on a contact is
allowed but shown as a clash. An `ElementPlacement`
addresses a copy by its flat `slotIndex`. `resolveSlot(type, slotIndex)` turns that
back into `{slotDefIndex, copy}`.

**Geometry.** The chassis is seen from the top: x runs along a row (0…`rowWidth` mm)
and y runs across rows. `col` counts `gridStep` (12 mm) steps from the left edge.
`transformerSpan()` gives the keep-out in the middle of each row.

**Connectors and cables.** A block's `connectors` are HD-68 sockets in a row above
its baskets (`position` is the place in that row). `ports` puts block port bits
(`ParsedNetlist.ports[].name`) on pins 1…68. A cable joins two connectors of
different blocks pin for pin, so inter-block signals come from matching pin
numbers: `services/interconnect.ts` `cableLinks()` lists them and flags pins
assigned on one end only, ports missing after a re-parse, and two outputs or two
inputs on one wire. A wire end (`TerminalPoint`) is either a module contact
(`{moduleInstanceId, pin: "A12"}`) or a connector pin (`{connectorId, pin: 17}`);
tell them apart with `isConnectorTerminal()`.

**Power nets** are listed by name in `Block.powerNets`, not flagged on the net, so
the choice survives re-parsing the netlist. The router will skip them (Q10).

**Board modules.** A `ModuleType` with `verilogModule` implements that Verilog
module; the Netlist tab pre-ticks *Keep* for it (`boardModules()`).

`activeBlockId` is **UI state**. It lives in the store but isn't part of
`ProjectState`, isn't saved, and isn't snapshotted.

## Store

`store/projectStore.ts` builds a single Zustand store with the Immer middleware:

```
ProjectStore = ProjectState & HistorySlice & ProjectActions & { activeBlockId }
```

`createProjectStore(initial?)` is a factory. The app uses the singleton
`useProjectStore`, and tests call `createProjectStore()` in `beforeEach` to get a
fresh store.

### Undo / redo

Every mutating action goes through one of two wrappers:

```ts
edit(label, (s) => { /* mutate the Immer draft */ });         // project-wide
editBlock(label, (b, s) => { /* mutate the active block */ }); // no-op without an active block
```

`edit` takes a reference snapshot of the project fields before the change. Immer
state is frozen, so no deep copy is needed. It then applies the change and pushes
`{state, label}` onto `past` **only if a top-level project field changed by
reference**. As a result:

- rejected or no-op edits (an occupied position, a locked module) don't create
  empty undo steps
- `future` is cleared on every real edit
- history is capped at `MAX_HISTORY = 50`

`undo` and `redo` swap the current `pickProjectState()` with the stored snapshot,
then call `fixActiveBlock()` so the selection still points at a block that exists.

Some actions don't go through history, on purpose:

- `newProject` and `loadProject` reset history.
- `setProjectName` fires on every keystroke.
- `setActiveBlock` changes UI state only.

### Invariants the store maintains

Validation lives in the action. An invalid request is **ignored silently** rather
than throwing; `addModuleInstance` returns `null`.

- **Module positions** go through `canPlaceModule()`: integer row and column, the
  row exists in that block, the module fits inside it and clears the transformer,
  and it doesn't overlap another instance in the same row. A locked instance can't
  be moved.
- **Rows.** `setBlockRows` clamps to `[max(3, highest used row + 1), 5]`.
- **Geometry.** `setBlockConfig` snaps `transformerWidth` to 72 + 12·K mm (at most
  100) and is ignored if a placed module would no longer fit.
- **Connectors.** Pins are 1…`pins`; a port sits on one pin of one connector
  (assigning it elsewhere moves it); a port must exist in the netlist when the
  netlist has ports. `moveConnector` swaps with the connector already there.
- **Cables.** Both connectors exist, belong to different blocks and have the same
  type, and neither has a cable yet. Removing a block or connector removes its
  cables.
- **Module types.** `updateModuleType` ignores an empty name, stores an empty
  `verilogModule` as absent, and refuses a `widthSteps` that isn't a positive
  integer or that a placed instance would no longer fit. `setSlotPinMap` drops
  entries with an unknown contact or a cell pin already mapped in that copy.
  `autoAssignContacts` gives unmapped signal pins (not power or ground) the next
  free contacts in `CONTACT_IDS` order, until the connector is full.
- **Element placement.** The instance's cell type has to match the slot's
  `cellType`, the slot has to be free, and a locked element can't be moved.
- **Cascading cleanup.**
  - After a netlist, slot or module-type change, `pruneElementPlacements()` drops
    placements whose instance or slot no longer exists or no longer matches.
  - After an instance, type or connector is removed, `pruneRouting()` drops wire
    segments that end on a missing instance or connector pin, and then any net
    left with no segments.
  - `updateSlot` with a new `cellType` clears that slot's pin maps, because the
    pin names changed. A new `count` resizes `pinMaps` and keeps existing copies.

### Adding an action

1. Declare it in `ProjectActions`.
2. Implement it in `createProjectSlice` with `edit` or `editBlock`. Mutate the
   draft and don't return a value; read derived data from the draft `s`.
3. Validate inside the callback and `return` early when the request is invalid, so
   no history entry is recorded.
4. If it can invalidate references, call the prune helpers.
5. Add a case to `test/store/projectStore.test.ts` covering the effect, a rejected input, and
   undo/redo.

### Reading from components

Prefer a narrow selector over destructuring the whole store, so a component only
re-renders when its slice changes:

```ts
const moduleTypes = useProjectStore(s => s.moduleTypes);
const addModuleInstance = useProjectStore(s => s.addModuleInstance);
```

`useProjectStore.getState()` is fine inside event handlers. During render it gives a
value that doesn't update when the store changes.

## Persistence (`services/projectIO.ts`)

- `serializeProject` and `deserializeProject` convert to and from JSON.
  `serializeProject` writes only `pickProjectState(state)`, so you can pass it the
  whole store: actions, undo history and `activeBlockId` are dropped.
- `deserializeProject` runs `migrateProject()`, which chains the steps:
  - pre-0.2: a single `netlist` becomes a `Legacy` block;
  - 0.2.0 → 0.3.0 (`migrateFrom02`): each `HardwareModule` becomes a `ModuleType`
    plus, if it was placed, a `ModuleInstance` with the same id. The slot's single
    `pinMapping` becomes the map of copy 0. The old chassis fields have no
    counterpart, so the geometry is reset to `DEFAULT_BLOCK_CONFIG`, keeping `rows`.
  - 0.3.0 → 0.4.0 (`migrateFrom03`): `rows` moves from `block` to every block,
    `transformerWidth` snaps to 72 + 12·K mm (85 → 84), blocks get empty
    `connectors` and `powerNets`, the project gets `cables`, and module types get
    `kind: 'board'`.
  - Then `dropInvalidPlacements` removes module instances that no longer pass
    `canPlaceModule`, with their elements and the wires ending on them.

  Missing top-level fields are then filled with defaults (`withDefaults`).
- `saveProjectToFile` downloads `<name>.dpc.json`. `loadProjectFromFile` opens a
  file picker.
- `startAutosave` writes to `localStorage` (`dekatronpc-project-autosave`) every
  30 s and on `pagehide`. `main.tsx` restores it with `loadAutosave()` before the
  first render. `ProjectManager`'s *New Project* clears it.

## Parsers

Both parsers have no dependencies, so they can run under plain Node. The liberty
parser uses regex plus brace counting; the Verilog parser has a tokenizer and a
recursive-descent parser.

- `parseLiberty(src)`: cells, pins (direction, function, driver type, fan-out,
  clock), `area`, `heat_current`, `current_unit`, `tubes(names){…}`, and `ff`/`latch`
  flags. Also exports `extractCellNames` and `generateSkeletonLiberty`.
- Verilog, in two stages:
  - `parseVerilogSource(src)` → `VerilogDesign`: every `module` with its ports,
    ranges, `assign`s and instances. Throws `VerilogParseError` with a line number.
  - `elaborateNetlist(design, { top?, keep? })` → `ParsedNetlist`: expands from the
    top to leaves (undefined types, black boxes, modules in `keep`). Bits are nodes
    in a union-find; ports and `assign`s union them; each group is named after its
    best member (shallowest, not Yosys `_N_`, shortest) or becomes a constant.
  - `parseVerilogNetlist(src, options)` does both. `summarizeDesign(design, top?)`
    lists the submodules below the top by base name, with use counts and port bits,
    for the *Keep* list and *Add as element*. `baseModuleName()` strips `$paramod`.
  - Also exports `extractWireNames` and `validateCellTypes(netlist, knownTypes)`.
  - When changing elaboration, keep the Yosys comparison in
    `test/parsers/verilog.test.ts` passing. To regenerate the reference, run the
    command at the top of `test/fixtures/IpLine_flat.v`.

## Testing

- Use Vitest with `globals: true` (`npm test`). Tests live outside `src/`, in
  `webui/test/`, mirroring the source tree (`test/parsers/`, `test/store/`,
  `test/services/`), as `*.test.ts`. They import code through the `@/` alias. CI
  runs them from `.github/workflows/webui.yml`.
- Component tests go in `test/ui/` as `*.test.tsx`, starting with
  `// @vitest-environment jsdom`, and use `@testing-library/react`. `app.test.tsx`
  clicks through every tab, so a component that throws on render fails CI.
- Store tests create a fresh store per test with `createProjectStore()`.
- **Add fixtures, not paths into `rtl/`.** Put small hand-written `.lib`, `.v` and
  `.dpc.json` files in `test/fixtures/`. Synthesis outputs such as
  `IpLine_synth.v` aren't in git, so tests that depend on them fail on a fresh clone.

## Conventions

- Use TypeScript `strict`, React 19 function components and hooks, and CSS in
  `components/App.css`.
- Lengths are in **mm**, and grid positions are in **`gridStep` units**. State the
  unit in names or comments.
- Use 0-based `row` and `col`. Connector contacts are strings, `"A1"`…`"B36"`.
- Undo labels are short and imperative, because they will show up in the UI:
  `Place module M3`, `Edit pin map`.
- Bump `PROJECT_FORMAT_VERSION` **and** add a migration step whenever the saved
  shape changes.
