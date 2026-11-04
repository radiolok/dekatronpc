# DekatronPC web simulator

A static web page that runs DekatronPC in the browser: 15 dekatrons (IP 5, Loop 2, AP 5, Data 3), the operator panel of `DekatronPC.sv`, program and data memory strips, the Consul printer with keyboard input, the repo test programs and the Brainfuck-100 set.

| File | What it is |
|---|---|
| `index.html` | the page: console, panel, program sheet, printer, RU/EN text |
| `dpc.js` | the machine: JavaScript port of the golden model `bfutils/dpcrun` |
| `build_bf100.py` | copies `rtl/programs/*.bfk` and `bfutils/programs/bf100` (with licenses) to `programs/` and writes `programs/index.json` |
| `test/test_dpc.js` | model tests: trace compare with `dpcrun`, assembler, SOT/EOT load |
| `programs/` | generated, not committed |

## Run locally

```bash
git submodule update --init bfutils
python3 web/build_bf100.py
cd web && python3 -m http.server 8000      # open http://localhost:8000
```

The page fetches `programs/`, so it needs an HTTP server: opening `index.html` as a file shows only the built-in Hello World.

## Deploy

- **GitHub Pages:** `.github/workflows/pages.yml` builds and publishes on every push to `master`, `claude_nextGen` or `web_simulator` that touches `web/`, `bfutils` or `rtl/programs/`, and on manual run. Repository settings: Pages, Source: GitHub Actions; Environments, `github-pages`, Deployment branches: allow the branch you deploy from.
- **Own server:** run `build_bf100.py`, then copy `index.html`, `dpc.js` and `programs/` to any static directory. All paths are relative.

## Tests

```bash
g++ -O2 -DEXEC -o /tmp/dpcrun bfutils/dpcrun/dpcrun.cpp
node web/test/test_dpc.js /tmp/dpcrun     # without the argument the trace compare is skipped
```

CI: `.github/workflows/web.yml`. Design notes and the halt finding: `doc/web_simulator.md`.
