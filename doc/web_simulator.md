---
title: Web simulator of DekatronPC
date: 2026-10-08
status: report
requirements: REQ-GM-001, REQ-LOAD-001..009, REQ-PANEL-001..006, REQ-BELL-007
---

# Web simulator of DekatronPC

`web/` holds a static page that runs the machine in a browser and shows it the way the console will: dekatrons, lamps, keys and switches, memory strips, the Consul printer. It is published on GitHub Pages by `.github/workflows/pages.yml` and runs from any static server (`web/README.md`).

## 1. Machine model

`web/dpc.js` is a line-by-line port of `bfutils/dpcrun` (`dpcrun.cpp` at bfutils 651cb62). The semantics are the golden model's, including the "RTL:" places of `doc/dpcrun_golden_model.md` §4. Differences are outside the instruction semantics:

| Item | dpcrun | web model | Why |
|---|---|---|---|
| Bootloader ROM | empty unless `-b` | `SIMPLEBOOT` of `bootloader.sv`: NOPs, ISA0 at 99998, SOT at 99999 | owner: no clear-memory routine in the simulator, memory is cleared with memset |
| AP limit | 29999 default, `-a` | 99999 | current RTL (ApLine has no top limit, OPEN-001), as `DekatronPC_tb.cpp` builds dpcrun |
| Panel keys | none | `haltKey()`, `loadingStop()`, `nextIp()`, `prevIp()` | keys of `DekatronPC.sv`; semantics from MachineCtrl/IpLine (S_HALT) |
| Loader | one table | two dialects, see §3 | owner decision |

**Check:** `web/test/test_dpc.js` runs the same programs as `dpcrun -f … -s -a 99999` and compares every trace line (IRET, IP, mnemonic, Loop, AP, Data counter, MemLock, status). All match: helloworld 400 steps, looptest 73, program 5 771, triangle 321 969, pi 221 386, fibonachi 400 000 (endless, cut). Plus assembler tests, a full SOT/EOT load of helloworld through the ROM (prints `Hello World!`) and a CIN test on rot13. 15 checks pass.

## 2. Loading: SOT/EOT only

LOAD AND BOOT clears program and data memory, puts the opcode stream on InsnIn and presses Hard Reset and Run. The ROM runs to SOT, the opcodes are written from address 0, EOT gives Soft Reset (SoftRstOnEOT) and the machine waits for RUN unless RunOnSoftRst is on.

The stream is `ISA1, program, HALT, ISA0, EOT`; HALT/ISA0/EOT are not appended when the program already ends with ISA0, EOT (the repo `.bfk` files end with `HDE`). ISA1 comes first for the same reason as in `DekatronPC_tb.sv`: loading starts in Debug ISA, where `>` (0x4) is EOT.

Memory is cleared only at power-on, on LOAD AND BOOT and by the MEM CLEAN key. Hard Reset keeps memory, like ferrite core.

The same load also works from the panel: with RunOnHardRst on, HARD RST starts the ROM, and when SOT puts the machine in load mode with InsnIn empty, the program reader puts the program from the text window on InsnIn (same stream, memory not cleared). With RunOnHardRst off, HARD RST then RUN does the same.

## 3. Program text: two dialects

- **DekatronPC ISA off (default for pasted text and Brainfuck-100):** only `+ - < > [ ] . ,` are commands, everything else is a comment.
- **DekatronPC ISA on (repo `.bfk` presets):** the full table of `generate_rom.py`/`dpc::assemble()`, with comments `//`, `;`, `#` to the end of the line and `/* … */`. `generate_rom.py` and `dpc::assemble()` don't know these comments yet; the page only strips them before assembling.

## 4. Panel

Keys (rectangles, label above): Hard rst, Soft rst, Halt, Step, Run, Load start, Load stop, Prev IP, Next IP, plus the simulator's Mem clean. Switches (rotary OFF/ON): EchoMode, RunOnHardRst, RunOnSoftRst, SoftRstOnEOT, BellOnCIN, BellOnHALT, BellOnError. Defaults are the Emulator's hard-wired values (OPEN-011) except BellOnHALT and BellOnError, which are on so a finished program rings. Speed: 1, 4, 16, 64, 256, 1k, 10k instructions/s or MAX. The page counts retired instructions only.

The printer has a column selector (40, 64, 72, 80, 132; default 80): lines longer than the width wrap like on a terminal, tabs stop every 8 columns, and the type is sized so the chosen width fills the paper.

`key_next_app_i` is replaced by the program selector. The bell sound plays on every Bell output and has an On/Off radio.

## 5. Finding: halt step skips a pending loop scan

dpcrun has no Step key. Its `enterHalt()` mirrors IpLine S_IDLE with `halt_rq`: when `ip_counted_q & ~ip_ahead`, IP steps once more without looking at `scan_req`. Brackets are never prefetched (`pf_q <= ~is_bracket & ~is_ip_op`), so `ip_ahead` is 0 after a bracket. If the machine halts right after a taken `]` (data ≠ 0) or `[` (data = 0), the scan is lost and IP lands after the bracket.

In the model, halting after every instruction (what MachineCtrl does in Step mode, `one_step` → S_HALT) turns helloworld into garbage output. Not checked on the RTL in a simulator.

By owner decision (2026-10-08) the page's STEP pauses the simulator clock after one `step()` and does not go through the halt path; HALT does, so the effect is visible there. The fix in IpLine/MachineCtrl (and dpcrun) is left for later.
