# netview: gate-level schematics of the netlists

Draws the Yosys netlists of IpLine, ApLine and MachineCtrl as readable schematics. It replaces `yosys show` + dot (see [doc/netview.md](../../doc/netview.md) for why).

```sh
cd tools/netview && npm install        # once: elkjs, the layout engine
cd rtl/run && ./run_tests.sh -p        # sch/*.svg + sch/index.html (runs -s first if a netlist is missing)
# or by hand, on any write_json netlist:
python3 tools/netview/netview.py rtl/run/IpLine_netlist.json -o rtl/run/sch
```

`synt_dpc.tcl` writes `<top>_netlist.json` next to `<top>_synth.v`. Every non-blackbox module in it becomes a sheet: the block itself and each DekatronModule variant (paramod hash in the file name, instances in the title).

index.html loads the sheets with XHR, which browsers block on `file://` (CORS, origin `null`). Under WSL, netview writes `open_chrome.bat` next to index.html: double-click it in Explorer (`\\wsl.localhost\Ubuntu\…\rtl\run\sch`). It starts Chrome with `--allow-file-access-from-files` and a separate profile (`%LocalAppData%\dpc-netview-chrome`), because a Chrome that is already running ignores the flag, and opens `file://wsl.localhost/…/index.html`. Elsewhere use a local server: `python3 -m http.server -d rtl/run/sch`. The SVGs open in any viewer by themselves.

## What it draws

- GOST 2.743 rectangular symbols built from the liberty `function`: "1"/"&" gates with an inversion circle, composite AND-OR-NOT (A1OOI, AOI211, A2OOI) with "&" sections, "TT" for a flip-flop (dynamic C input, with a circle for the falling edge), "T" for a latch, and boxes with pin names for cells that have no function (GUIDE_EN_J2, WRCH_N16, RDD_X7, KEYDB_N16, GLIFT_N16, relays).
- Fill colour by the tubes in the liberty `tubes(names)` group: 6Н16Б blue, 6Ж2Б amber, 6Х7Б green, several types violet, the A110 dekatron orange. The header shows the cell and tube count of the sheet.
- Net flags in place of wires for nets with ≥ `--fanout` sinks (default 7), for names matching `--global` (clk, reset lines), and for flip-flop/latch outputs with ≥ `--seq-cut` sinks (default 2; 0 routes them). Without this, the feedback from the registers runs back across the whole sheet.
- Constant inputs are a "0"/"1" at the pin. Unused port bits are dropped, and a port with none left is drawn dashed.
- Function frames (ELK compound nodes). ABC leaves no `src` on most cells, so the groups come from the structure. A cell named in a sub-scope (`ip_counter.enLatch[1]`) takes that scope. A cell that drives a public net takes the net's name, with `_q/_d/_nx/_s/_db/_r` and the bit index stripped (`state_d[1]`, `state[1]` → `state`). Other cells take the group of the cells they feed, by majority; logic that feeds several groups stays outside the frames. A group over `--group-max` cells gets sub-frames by the exact signal (`state[2]`, `ip_counter.phaseGen`). Groups under `--group-min` cells are not framed.
- Buses between frames. Everything going from one frame to another (the root, i.e. the shared logic, counts as a frame) leaves through a joiner (a bar with the net names or bit indices on its stubs), runs as one thick bus and is ripped back into bits in the destination frame. A bus carries a slash with its width and a label: `ip_addr[19:0]` when it is one vector, otherwise `src→dst · N` with the members in the tooltip. A bus that comes entirely from one multi-bit input port, or goes entirely to one multi-bit output port, attaches straight to the port header. Inside a frame, bits are wired individually. `--buses vectors` bundles only the bits of one vector; `--buses off` routes every net on its own.
- ABC net names are shortened (`$abc$3294$new_n79` → `n79`) where the short name stays unique on the sheet.
- Every cell has a tooltip with its instance name, type, tubes and RTL `src`. Public net names are written at the driver.

Viewer (index.html): wheel to zoom, drag to pan, click a wire or pin to light its net (a bus lights all its bits, and a bit lights its bus), click a cell to light all its nets, double-click a DekatronModule to open its sheet, search box for nets and cells, `0` to fit.

## Options

| Option | Default | |
|---|---|---|
| `-o DIR` | `sch` | output directory; index.html lists every sheet there, so separate runs add up |
| `-l LIB` | sch/logic/vtube_cells.lib | liberty |
| `--fanout N` | 7 | flag nets with ≥ N sinks |
| `--global RE` | `clk\|.*_rst\|rst_n` | always flag these nets |
| `--seq-cut N` | 2 | flag register outputs with ≥ N sinks |
| `--no-group` | | one flat layout, no frames |
| `--buses MODE` | frames | `frames`: one bus per frame pair; `vectors`: one per vector; `off` |
| `--group-max N` | 25 | larger groups get sub-frames |
| `--group-min N` | 3 | smaller groups get no frame |
| `--only RE` | | draw only the matching modules |
| `--placement` | NETWORK_SIMPLEX | ELK node placement (BRANDES_KOEPF gives straighter, wider sheets) |
| `--thoroughness`, `--node-gap`, `--layer-gap` | 20, 18, 36 | ELK tuning |

Files: `netview.py` (netlist, symbols, SVG, viewer, open_chrome.bat), `elk_layout.mjs` (stdin → elkjs → stdout), `package.json`. `node_modules/` is not committed.
