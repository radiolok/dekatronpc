# Overview schematics of the tube logic cells

The KiCad sheets in `sch/logic/<CELL>/` are wired with net labels, so the whole circuit is hard to see at a glance. These scripts redraw each cell as one picture (tubes, plate loads, screens, feedback dividers, supplies), taken from the netlist of the KiCad sheet (`kicad-cli sch export netlist`). Plain Python 3, no dependencies.

```sh
python3 tools/cellschem/build.py            # all cells -> sch/logic/<CELL>/img/<stem>.svg
python3 tools/cellschem/build.py NOR2_N16   # one cell
python3 tools/cellschem/build.py -o /tmp/p  # previews into /tmp/p/<CELL>/
```

The SVG files are generated: change the drawing function, not the file. Each cell README embeds its figure before the KiCad sheet image. `.gitignore` has an exception for `sch/logic/*/img/*_schematic.svg`.

| File | What |
|---|---|
| `lib.py` | `Sch`: tube symbols (triode, 6Zh2B pentode), R, C, L, diode, supply symbols, pins, wires with automatic hops over crossings, boxes; the plate load with its choke (`plate_load`), and the elements "Inverter" (`inverter`) and "Divider" (`divider`) that the trigger figures use instead of drawing every part (owner, 2026-11-08, TRS v0.58) |
| `cells_nor.py` | NOT_N16, NOR2_N16, NOR3_N16, NOR4_N16 |
| `cells_aoi.py` | NAND2_J2, A1OOI_N16J2, AOI211_J2N16, A2OOI_J2 |
| `cells_cf.py` | BUF_N16, OR2_N16, OR4_N16 (cathode followers) |
| `cells_latch.py` | RSLATCH_J2N16 and DFFP core in full; DLATCH2, DFF, DFFRN, DFFSN, DFFP2 with the RS latches drawn as blocks |
| `build.py` | the cell → file-name table (`CELLS`, `EXTRA`) |

Conventions: LV pins blue, HV pins red, the reset lines (RN, SN) violet. Heaters (H1/H2) are not drawn; each figure says so. Part references and values are those of the KiCad sheet. Where the netlist has one net at two places (E of the RS latch, G of the pulse flip-flop), the figure draws the pin twice.

When a KiCad sheet changes (parts, values, connections), redraw the matching function and rebuild. Cells without a KiCad sheet (KEYDB_N16, RELAY_HOLD_N16, DEKATRON_A110) have no figure here.
