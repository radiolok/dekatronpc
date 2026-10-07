# FPGA bitstream build from the command line

Tool: `rtl/run/build_fpga.sh`. Target: the Emulator top (`rtl/Emulator/Emulator.sv`) on DE0-Nano-SoC, Cyclone V 5CSEMA4U23C6 (REQ-RTL-001, REQ-RTL-004).

## 1. Why a separate build project

The GUI project `rtl/quartus/Emulator.qsf` has a hand-kept file list that has fallen behind the RTL. It still lists `Dekatron.sv`, `DekatronPulseAllow`, `InsnDecoder` and `RsLatch`, and it lacks `MachineCtrl.sv`, `DekatronTubeV2.sv`, `DekatronPhaseGen.sv`, `FirmwareLoader.sv` and the UART. The script builds a fresh project in `rtl/quartus_build/` (gitignored) on every run:

- device, pins, partitions and other settings come from `rtl/quartus/Emulator.qsf`; its file, SDC and macro lines are dropped;
- sources come from `rtl/DekatronPC/DPC.files` and `rtl/Emulator/Emul.files`, the same lists Verilator uses in `run_emul.sh`, so simulation and FPGA build one file set. `*_assertions.sv` files are skipped because they are bound only under `ASSERTIONS`;
- the SDC is `rtl/quartus/Emulator.sdc`, and `EMULATOR=True` is always defined;
- `VERILOG_CONSTANT_LOOP_LIMIT` is raised to 100000. `RamBank`'s zero-init `for` loop runs over a whole bank (10⁴ cells in IpMemory with `BANK_DIGITS = 4`), and Quartus stops at its default of 5000 iterations (`Error (10106) ... RAM.sv(147)`).

The build directory has to sit directly under `rtl/`. The file lists use `../X` paths, and `FirmwareLoader`/`MS6205` call `$readmemh("../….hex")`, which Quartus resolves relative to the project directory. Before each build the script regenerates the firmware images (`rtl/firmware.hex`, `rtl/load_firmware*.hex`) from `rtl/programs/*.bfk` with `generate_rom.py`, the same way `run_emul.sh` does.

The GUI project is left untouched.

## 2. Usage

```
cd rtl/run
./build_fpga.sh                 # syn + fit + asm + sta -> rtl/quartus_build/output_files/Emulator.sof
./build_fpga.sh elab            # analysis & elaboration only (about 1 min)
./build_fpga.sh syn             # analysis & synthesis only
./build_fpga.sh -p              # compile, then program the FPGA over JTAG
./build_fpga.sh program         # program the existing .sof, no rebuild
./build_fpga.sh --rbf           # also write Emulator.rbf (compressed, for loading from HPS Linux)
./build_fpga.sh --list-cables   # JTAG cables seen by quartus_pgm
./build_fpga.sh -n              # write the project, print the Quartus commands, run nothing
./build_fpga.sh -D CONSUL=1     # extra Verilog macro (repeatable)
```

The exit code is the verdict. After a run the script prints the `map`/`fit`/`sta` summaries.

Programming uses JTAG device index 2: on DE0-Nano-SoC the chain is HPS (1) then FPGA (2). Override it with `-i`, and pick the cable with `-c`.

## 3. Finding Quartus

The script checks, in order: `--quartus DIR`, `$QUARTUS_BIN`, `quartus_sh` on `PATH`, then `~/intelFPGA_lite/*/quartus/bin`, `/opt/intelFPGA*/…` and, under WSL, `/mnt/c/intelFPGA_lite/*/quartus/bin64` (newest version first). The Windows install (`quartus_*.exe`) works from WSL with the project on the WSL filesystem (`\\wsl.localhost\…`): relative paths and `$readmemh` resolve correctly. This was checked on Quartus Prime Lite 23.1std.0 Build 991. `quartus_pgm.exe` uses the Windows USB-Blaster driver, so no USB passthrough into WSL is needed.

## 4. Results so far (2026-10-07)

| Stage | Result |
|---|---|
| `-n` (dry run) | Project generated, 51 pin assignments carried over. |
| `elab` before the loop limit | `Error (10106)`: loop in `RamBank` (RAM.sv:147) exceeds 5000 iterations. |
| `elab` | Successful, 0 errors, 212 warnings, 58 s, peak about 4.8 GB virtual memory. |
| `syn` / `compile` before the RamBank fix | `Error (276003)` in Analysis & Synthesis (35 s, peak 4.96 GB), see §5. |
| `syn` / `compile` after the fix | Not run yet. This is a heavy job; per AGENTS.md §0 it waits for the owner's go-ahead. |

Memory is expected to fit: OPEN-015 was closed in TRS v0.8 by `BANK_DIGITS = 4` (about 80 memory blocks instead of 1300). With the debug read port (`EN_EMULATOR = 1`) Quartus may duplicate each bank for the second read address; even then the two memories need about 1.4 Mbit of the device's 2.7 Mbit (270 M10K blocks).

## 5. RamBank was not mapped to block RAM (Error 276003)

Symptom in `output_files/Emulator.map.rpt`:

```
Info (276007): RAM logic "...|RamBank:g_bank.bank|mem" is uninferred due to asynchronous read logic  (RAM.sv:99, all 20 banks)
Error (276003): Cannot convert all sets of registers into RAM megafunctions when creating nodes.
                The resulting number of registers remaining in design exceeds the number of registers in the device ...
```

Cause: the RTL read was synchronous, but both read registers in `RamBank` had logic between the array and the flop: the write-through multiplexer (`rd_q <= wr ? wr_data : mem[idx]`) on the main port and the invalid-address mask (`dbg_q <= dbg_ok ? mem[dbg_idx] : 0`) on the debug port. Quartus absorbs a read register into an M10K block only when the register is fed directly from `mem[...]`. Otherwise it treats the read as asynchronous and builds the memory from flip-flops: about 1.4 million of them, against about 30 000 ALMs in the 5CSEMA4.

Fix in `rtl/DekatronPC/RAM.sv` (`RamBank`), behaviour unchanged:

- main port: `rd_q <= mem[idx]` only on reads; a write stores the value in `wr_q` and sets `byp_q`, and the output is `byp_q ? wr_q : rd_q`. The output still holds the last touched cell, write-through included;
- debug port: `dbg_q <= mem[dbg_idx]` and `dbg_ok_q <= dbg_ok`, with the mask applied after the register.

Checked: Verilator `--lint-only -Wall` on DekatronPC and Emulator (clean), Icarus `ApLine`, `IpLine` (looptest.bfk), `DekatronPC` on helloworld.bfk and program.bfk, all pass. The Quartus rerun is still to be done.

The `Critical Warning (127005)` about `FirmwareLoader` (memory depth 1024 vs 650 words in the init file) is harmless: the rest of the ROM is filled with zeros.

## 6. CI (`.github/workflows/fpga.yml`)

| Trigger | What runs | Artifacts |
|---|---|---|
| pull request to `master` | `build_fpga.sh elab`: syntax, hierarchy, parameters | reports |
| push to `master`, manual run (`workflow_dispatch`) | `build_fpga.sh --rbf compile` | `Emulator.sof`, `Emulator.rbf`, reports and summaries (14 days) |

The workflow is separate from `docker-image.yml` and not a required check.

**Quartus source: community Docker image (owner decision, 2026-10-07).** The job uses `chriz2600/quartus-lite:23.1.1-1`: Ubuntu 22.04 with the full Quartus Prime Lite 23.1std.1 tar installed (all device families, about 6.3 GB compressed). It is pinned by digest (`sha256:50eac410…`), so a re-pushed tag cannot change the toolchain silently. Quartus is on `PATH` only in a login shell, so the job runs `bash -lc`. The image has no Python, so the runner generates the firmware hex files and the container runs `build_fpga.sh --no-fw`. The job frees disk space on the runner before pulling the image.

Why not the official installers: Quartus is not in any distro repository, and since the Intel/Altera split, scripted downloads fail. `downloads.intel.com` redirects to a 404 page, and `download.altera.com` answers `403 Access Denied` (checked 2026-10-07). A mirror would have to be non-public, because Intel's EULA does not allow redistribution.

Fallback if the image disappears or breaks: a self-hosted runner on the owner's server with Quartus installed (the owner's choice; to be decided again then). On a public repository a self-hosted runner must not run pull requests from forks.

The local Windows install is 23.1std.0; the CI image is 23.1std.1, which gives the same results for this flow as far as is known.

Status: written, not yet run on GitHub.
