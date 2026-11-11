# FPGA bitstream build from the command line

Tool: `rtl/run/build_fpga.sh`. Target: the Emulator top (`rtl/Emulator/Emulator.sv`) on DE0-Nano-SoC, Cyclone V 5CSEMA4U23C6 (REQ-RTL-001, REQ-RTL-004).

## 1. Why a separate build project

The GUI project `rtl/quartus/Emulator.qsf` used to have a hand-kept file list that fell behind the RTL (it listed `Dekatron.sv`, `DekatronPulseAllow`, `InsnDecoder`, `RsLatch` and lacked `MachineCtrl.sv`, `ClkTree.sv`, the TubeV2 stack, `FirmwareLoader.sv` and the UART). Since 2026-11-11 `./build_fpga.sh sync-qsf` writes the same list into it (see below). The script builds a fresh project in `rtl/quartus_build/` (gitignored) on every run:

- device, pins, partitions and other settings come from `rtl/quartus/Emulator.qsf`; its file, SDC and macro lines are dropped;
- sources come from `rtl/DekatronPC/DPC.files` and `rtl/Emulator/Emul.files`, the same lists Verilator uses in `run_emul.sh`, so simulation and FPGA build one file set. `*_assertions.sv` files are skipped because they are bound only under `ASSERTIONS`;
- the SDC is `rtl/quartus/Emulator.sdc`, and `EMULATOR=True` is always defined;
- `VERILOG_CONSTANT_LOOP_LIMIT` is raised to 100000. `RamBank`'s zero-init `for` loop runs over a whole bank (10⁴ cells in IpMemory with `BANK_DIGITS = 4`), and Quartus stops at its default of 5000 iterations (`Error (10106) ... RAM.sv(147)`).

The build directory has to sit directly under `rtl/`. The file lists use `../X` paths, and `FirmwareLoader`/`MS6205` call `$readmemh("../….hex")`, which Quartus resolves relative to the project directory. Before each build the script regenerates the firmware images (`rtl/firmware.hex`, `rtl/load_firmware*.hex`) from `rtl/programs/*.bfk` with `generate_rom.py`, the same way `run_emul.sh` does.

The compile stages leave the GUI project untouched. `./build_fpga.sh sync-qsf` (no Quartus needed) replaces the file, SDC and loop-limit lines of `rtl/quartus/Emulator.qsf` in place with the list the build uses, keeping all other settings and the CRLF format Quartus writes; run it after adding or removing an RTL file so the GUI project opens the current design.

## 2. Usage

```
cd rtl/run
./build_fpga.sh                 # syn + fit + asm + sta -> rtl/quartus_build/output_files/Emulator.sof
./build_fpga.sh elab            # analysis & elaboration only (about 1 min)
./build_fpga.sh syn             # analysis & synthesis only
./build_fpga.sh -p              # compile, then program the FPGA over JTAG
./build_fpga.sh program         # program the existing .sof, no rebuild
./build_fpga.sh sync-qsf        # put the build's file list into rtl/quartus/Emulator.qsf (no Quartus run)
./build_fpga.sh --rbf           # also write Emulator.rbf (compressed, for loading from HPS Linux)
./build_fpga.sh --list-cables   # JTAG cables seen by quartus_pgm
./build_fpga.sh -n              # write the project, print the Quartus commands, run nothing
./build_fpga.sh -D CONSUL=1     # extra Verilog macro (repeatable)
```

The exit code is the verdict. After a run the script prints the `map`/`fit`/`sta` summaries of that run only (a failed stage no longer shows the previous build's reports).

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
| `syn` / `compile` after the fix | Successful (2026-11-04): 0 errors, Flow Status Successful (see §6.1 for the struct-literal fix that unblocked it). |
| `compile` after the cathode-line write (TRS v0.56) | `Error (10170)` in `DekatronCounter.sv`: Quartus 23.1 does not parse `for (genvar k …)` inside a nested generate block. Fixed 2026-11-11 with a separate `genvar k;` (no logic change, Yosys count the same). |
| `compile` 2026-11-11 | Successful: 0 errors in map/fit/asm/sta, slack positive on every clock (setup `Clk_50MHz` +15.8 ns, hold ≥ +0.3 ns). |
| GUI project after `sync-qsf` | `quartus_map --analysis_and_elaboration` in `rtl/quartus/`: successful, 0 errors. |

Full compile (`map`+`fit`+`asm`+`sta`) on the Windows Quartus 23.1std.0: 0 errors in every stage, `Emulator.sof` written, STA meets timing (worst slack positive). The only Critical Warnings are the harmless memory-depth mismatches (127005, §5) and 19 pins without exact locations (169085, carried over from `Emulator.qsf`).

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

### 6.1 Struct literal in a continuous assignment (Error 10734)

First real CI run (pull request to `master`, 2026-11-04) failed elaboration with three errors:

```
Error (10734): Verilog HDL error at Emulator.sv(310): rx_data_bcd is not a constant
Error (10734): Verilog HDL error at Emulator.sv(311): rx_vld is not a constant
Error (10734): Verilog HDL error at Emulator.sv(312): tx_rdy is not a constant
```

The lines were the `assign dpc_in = '{ insn: …, rx_data_bcd: rx_data_bcd, … };` named-field assignment pattern that packs the Emu→DPC inputs into `dpc_in_t`. Quartus elaboration refuses non-constant expressions inside an assignment pattern in a continuous assignment (error 10734), on both 23.1std.0 and 23.1std.1.

Fix in `rtl/Emulator/Emulator.sv`: replace the pattern with a plain concatenation in declaration order. `dpc_in_t` is a `packed` struct, so its first-declared field is the most-significant bits — a `{insn, insn_vld, rx_data_bcd, …}` concatenation in field order is bit-for-bit identical to the pattern. Behaviour is unchanged.

Checked (2026-11-04): `elab` 0 errors on the local Windows Quartus 23.1std.0 and on the CI image 23.1std.1; full `compile` on 23.1std.0 is 0 errors, Flow Status Successful, `Emulator.sof` written, STA met.

Status: CI now runs on GitHub; the job has `continue-on-error: true`, so a failure does not fail the workflow — check the job log, not the green tick.
