# Multi-Block Architecture — Refactoring Plan ✅ COMPLETED

**Status:** Implemented in commit `3a2e223`. All 34 tests pass.

## Motivation

DekatronPC has 2–3 computational blocks (IpLine, ApLine, MachineCtrl) sharing the same:
- Liberty cell library (`vtube_cells.lib`)
- Hardware modules (PCB definitions)
- Chassis geometry (4U, 920×420 mm)

Each block has its **own** netlist, placement, and routing. Currently `ProjectState` supports exactly one netlist — needs to become multi-block.

## Design

```
ProjectState
├── meta
├── liberty          ← shared
├── externalElements ← shared
├── modules          ← shared
├── block (chassis)  ← shared
└── blocks: Record<string, Block>
    ├── "IpLine"         { netlist, placement, routing }
    ├── "ApLine"         { netlist, placement, routing }
    └── "MachineCtrl"     { netlist, placement, routing }
```

Block name comes from the loaded Verilog filename (e.g., `IpLine_synth.v` → `IpLine`).

## Tasks

### 1. Types (`src/types/project.ts`)

- [ ] 1.1 Add `Block` interface with `name`, `netlist`, `placement`, `routing`
- [ ] 1.2 Change `ProjectState`: replace single `netlist`/`placement`/`routing` with `blocks: Record<string, Block>`
- [ ] 1.3 Update `createDefaultProject()` — empty `blocks: {}`
- [ ] 1.4 Update `cloneProjectState()` helper in store to include `blocks`
- [ ] 1.5 Add migration helper for old single-netlist projects

### 2. Store (`src/store/projectStore.ts`)

- [ ] 2.1 Replace `setNetlist(netlist)` with `setBlockNetlist(blockId, netlist)`
- [ ] 2.2 Add `removeBlock(blockId)` action
- [ ] 2.3 Update placement actions: `setModulePlacements` → `setBlockModulePlacements(blockId, ...)`, same for element placements
- [ ] 2.4 Update routing actions: `setRoutedNets` → `setBlockRoutedNets(blockId, ...)`, same for segments
- [ ] 2.5 Keep current action signatures as deprecated wrappers for active block (for gradual migration)

### 3. UI Changes

- [ ] 3.1 `NetlistPanel`: add block selector (dropdown of existing blocks + "New Block" button)
- [ ] 3.2 "Open File" button: auto-derives block name from filename (`IpLine_synth.v` → `IpLine`)
- [ ] 3.3 Tabs show data for currently selected block
- [ ] 3.4 `BlockCanvas` (future Placement/Routing tabs): receives `blockId` prop

### 4. Parser Tests Update

- [ ] 4.1 Update parser-triggering tests to use `setBlockNetlist`
- [ ] 4.2 Add multi-block test: two blocks with same liberty, different netlists

### 5. Backward Compatibility

- [ ] 5.1 `loadProject`: detect old format (`netlist` field present) → migrate to `blocks.default`
- [ ] 5.2 Bump project version to `0.2.0`
