# DekatronPC Block Place & Route

**Interactive block placement and routing tool for the [DekatronPC](https://github.com/radiolok/dekatronpc) vacuum-tube computer.**

DekatronPC is a homebrew vacuum-tube computer built from Soviet-era miniature tubes (6N16B, 6J2B, 6X7B, A110 dekatrons). This web-based EDA tool assists the physical design stage: placing logic modules on the chassis grid and routing orthogonal wire connections between them.

## Overview

The tool takes synthesized structural Verilog netlists and a Liberty cell library as input, then guides the user through:

1. **Parsing** — import flat gate-level Verilog (Yosys output) and `.lib` cell definitions. **Multi-block:** 2-3 netlists per project, each creating its own block (IpLine, ApLine, MachineCtrl) sharing the same liberty/modules/chassis.
2. **Elements** — define custom elements not covered by the liberty file (submodules, power supplies, dekatrons)
3. **Modules** — configure hardware PCBs (140×140 mm, 2×36 pin connector) with slot assignments
4. **Placement** — drag-and-drop modules onto a 3-row chassis grid (920×420 mm, 12 mm pitch); auto-place with simulated annealing and Hungarian algorithm
5. **Routing** — orthogonal wire routing through channel graph using A* pathfinding; manual pencil tool
6. **Assembly** — track physically assembled connections; export CSV/JSON wiring tables and PNG/SVG schematics

### Physical parameters (from [DekatronPC wiki](https://github.com/radiolok/dekatronpc/wiki))

- **Chassis**: 4U server case 920×420×178 mm, 3 rows of modular PCBs
- **Module**: PCB 140×140 mm, 3×36 connector (1 key row, effective 2×36 = A1..A36, B1..B36)
- **Grid pitch**: 12 mm (logic modules: 2 steps = 24 mm; dekatron modules: 3 steps = 36 mm)
- **Tubes**: ~1244 total (6N16B, 6J2B, 6X7B, A110). Power consumption ~5 kW

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | React 19 + TypeScript 5.8 |
| Canvas | Konva.js 9 (react-konva) |
| State | Zustand 5 + Immer (undo/redo) |
| Build | Vite 6 |
| Testing | Vitest |

## Quick Start

```bash
cd webui
npm install
npm run dev        # dev server at http://localhost:5173
```

Or double-click `dev_server.bat` on Windows.

## Test Parsers

Run independently (no Node.js dependencies beyond the runtime):

```bash
node test_parsers.mjs ../rtl/run/vtube_cells.lib ../rtl/run/IpLine_synth.v
```

Or double-click `test_parsers.bat`.

## Project Structure

```
webui/
├── src/
│   ├── components/       # React UI: tabs for each workflow stage
│   │   ├── App.tsx
│   │   ├── Elements/     # Custom element editor
│   │   ├── Netlist/      # Verilog + Liberty import & inspection
│   │   └── ...
│   ├── services/
│   │   ├── parsers/      # Liberty (.lib) and Verilog netlist parsers
│   │   └── projectIO.ts  # JSON project load/save/autosave
│   ├── store/            # Zustand store with undo/redo history
│   ├── types/            # TypeScript data model (ProjectState, cells, modules, routing)
│   └── utils/
├── test_parsers.mjs      # Standalone parser test script
├── test_parsers.bat       # Windows launcher for parser tests
├── dev_server.bat         # Windows launcher for dev server
└── AGENTS.md             # Full technical specification (Russian)
```

## Development

This project was developed using **KiloCode** with the **DeepSeek V4 Pro** model (`deepseek/deepseek-v4-pro`).
