---
title: Web simulator of DekatronPC
date: 2026-10-08
status: report
requirements: REQ-GM-001, REQ-LOAD-001..009, REQ-PANEL-001..006, REQ-BELL-007
---

# Web simulator of DekatronPC

`web/` holds a static page that runs the machine in a browser and shows it the way the console will: dekatrons, lamps, keys and switches, memory strips, the Consul printer. It is published on GitHub Pages by `.github/workflows/pages.yml` and runs from any static server (`web/README.md`).

## 1. Machine model

**[TRS v0.63, 2026-11-11]** The page follows the release machine: 12 dekatrons (IP 4: 0–9999, Loop 2, AP 3: 0–999 with wrap, Data 3) and ISA16, one 4-bit instruction set without modes (`doc/isa16.md`). The earlier version of this page (IP 5, AP 5, ISA0/ISA1 modes) is in git history.

`web/dpc.js` is a line-by-line port of `bfutils/dpcrun` (`dpcrun.cpp` of bfutils branch `ISA16`, with `IP_SIZE = 10000`, `BOOT_BASE = 9990`, `AP_TOP = 999`). The semantics are the golden model's, including the "RTL:" places of `doc/dpcrun_golden_model.md` §4. Differences are outside the instruction semantics:

| Item | dpcrun | web model | Why |
|---|---|---|---|
| Bootloader ROM | empty unless `-b` | `rtl/programs/bootloader.bfk` (`0<{0<}NNNS`) from power-on | the ROM of the machine: clears 1000 data cells, LD at 9999 loads from 0 |
| Panel keys | none | `haltKey()`, `loadingStop()`, `nextIp()`, `prevIp()`, `manualStep()` | keys of `DekatronPC.sv`; semantics from MachineCtrl/IpLine (S_HALT) |
| Loader | one table | two dialects, see §3 | owner decision |

A loop overflow stops the machine without a halt (TC-N2): `step()` returns `Halted`, the Overflow lamp is lit, RUN does not restart it, only a reset clears it.

**Check:** `web/test/test_dpc.js` runs the same programs as `dpcrun -f … -s` and compares every trace line (IRET, IP, mnemonic, Loop, AP, Data counter, MemLock, status). All match: helloworld 400 steps, looptest 73, program 5 771, triangle 321 969, pi 221 386, fibonachi 400 000 (endless, cut). Plus assembler tests (full ISA16 table, symbol round trip), a full SOT/EOT load of helloworld through the ROM (the ROM clears all 1000 cells and is not overwritten, prints `Hello World!`), AP wrap 0 → 999 → 0, a loop overflow without halt and a CIN test on rot13: 21 checks pass.

## 2. Loading: SOT/EOT only

LOAD AND BOOT clears program memory, puts the opcode stream on InsnIn and presses Hard Reset and Run. The ROM clears the data memory (`0<{0<}`, three instructions per cell), runs to LD at 9999, the opcodes are written from address 0, EOT gives Soft Reset (SoftRstOnEOT) and the machine waits for RUN unless RunOnSoftRst is on. The page no longer clears data memory itself (it did with the old SIMPLEBOOT ROM): the HARD RST key only resets, like the machine.

The stream is `program, HALT, LD (EOT)`; HALT and EOT are not appended when the program already ends with LD (the repo `.bfk` files end with `HE`). A program fits when it plus HALT take at most 9990 cells. For Brainfuck-100 the page marks programs that don't fit 4-2-3-3 with ✕: `web/build_bf100.py` computes `fits` from `metrics.json` (commands + HALT ≤ 9990, AP span < 1000, loop scan ≤ 99): 78 of 100 fit.

The same load also works from the panel: with RunOnHardRst on, HARD RST starts the ROM, and when LD puts the machine in load mode with InsnIn empty, the program reader puts the program from the text window on InsnIn (same stream, memory not cleared). With RunOnHardRst off, HARD RST then RUN does the same.

## 3. Program text: two dialects

- **DekatronPC ISA off (default for pasted text and Brainfuck-100):** only `+ - < > [ ] . ,` are commands, everything else is a comment.
- **DekatronPC ISA on (repo `.bfk` presets):** the full ISA16 table of `generate_rom.py`/`dpc::assemble()` (`N H + - > < [ ] . , 0 S E A P { }`; S and E are both LD), with comments `//`, `;`, `#` to the end of the line and `/* … */`. `generate_rom.py` and `dpc::assemble()` don't know these comments yet; the page only strips them before assembling.

## 4. Panel

Keys (rectangles, label above): Hard rst, Soft rst, Halt, Step, Run, Load start, Load stop, Dec, Inc. Dec/Inc change the counter picked by the rotary Counter selector (IP, Loop, AP, Data) while the simulator clock is stopped. The RTL has only keyPrevIp/keyNextIp; the other three are a simulator extension (`Machine.manualStep()`): Loop wraps 0–99 without touching the overflow flag, AP moves like `>`/`<` (a locked Data counter is flushed first, which releases MemLock), Data steps like `+`/`-` (MemLock set). Switches (rotary OFF/ON): EchoMode, RunOnHardRst, RunOnSoftRst, SoftRstOnEOT, BellOnCIN, BellOnHALT, BellOnError. Defaults are the Emulator's hard-wired values (OPEN-011) except BellOnHALT and BellOnError, which are on so a finished program rings. Speed: 1, 4, 16, 64, 256, 1k, 10k instructions/s or MAX. The page counts retired instructions only.

The printer has a column selector (40, 64, 72, 80, 132; default 80): lines longer than the width wrap like on a terminal, tabs stop every 8 columns, and the type is sized so the chosen width fills the paper.

`key_next_app_i` is replaced by the program selector. The bell sound plays on every Bell output and has an On/Off radio.

## 5. Finding: halt step skips a pending loop scan

dpcrun has no Step key. Its `enterHalt()` mirrors IpLine S_IDLE with `halt_rq`: when `ip_counted_q & ~ip_ahead`, IP steps once more without looking at `scan_req`. Brackets are never prefetched (`pf_q <= ~is_bracket & ~is_ip_op`), so `ip_ahead` is 0 after a bracket. If the machine halts right after a taken `]` (data ≠ 0) or `[` (data = 0), the scan is lost and IP lands after the bracket.

In the model, halting after every instruction (what MachineCtrl does in Step mode, `one_step` → S_HALT) turns helloworld into garbage output. Not checked on the RTL in a simulator.

By owner decision (2026-10-08) the page's STEP pauses the simulator clock after one `step()` and does not go through the halt path; HALT does, so the effect is visible there. The fix in IpLine/MachineCtrl (and dpcrun) is left for later.
