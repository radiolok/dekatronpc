# ISA16: one 4-bit instruction set

Date: 2026-11-02. Branch `ISA16` (from `tube_opt_1000`, 73d16e2). TRS v0.42.
Follows doc/insn_cost.md (cost of each non-BF instruction).

## 1. Decision

The owner asked to fit the machine into 16 instructions: plain Brainfuck, SOT/EOT
in one code, `[-]`, HALT, `{ }` and a couple more. After an experiment behind a
define (§7) the owner decided (2026-11-02):

- HRST/SRST from a program: not needed.
- CLRA: useful, keep. CLRL: not needed.
- `{ }` are needed only by the bootloader and are never interleaved with `[ ]`,
  so the scan does not have to tell the bracket kinds apart.
- The bootloader is small enough for one decade: start at 99990 (9990 since TRS v0.63, IP = 4 dekatrons).
- MemLock control was there for copying through the data counter: after a move the
  counter still holds the old cell; "set MemLock at the new address and move on"
  is enough. Implemented as the MemLock instruction (0xD, first called STORE; the
  owner named it MemLock), see §2.

All `DPC_CUT_*` defines of the insn_cost experiment and the `DPC_ISA16` define were
removed; the RTL is ISA16 only. The experiment patch is not kept in the tree.

## 2. Opcode map

| Op | Symbol | Instruction | Semantics |
|---|---|---|---|
| 0x0 | `N` | NOP | |
| 0x1 | `H` | HALT | Run resumes at the next instruction |
| 0x2 / 0x3 | `+` `-` | INC / DEC | cell ± 1, MemLock taken first |
| 0x4 / 0x5 | `>` `<` | AINC / ADEC | a locked cell is written back first |
| 0x6 / 0x7 | `[` `]` | LBEG / LEND | test the cell (TEST before them if the zero flag is not valid) |
| 0x8 / 0x9 | `.` `,` | COUT / CIN | unchanged |
| 0xA | `0` | CLRD `[-]` | cell ← 0, sets MemLock |
| 0xB | `S` / `E` | LD | outside loading: start loading at the next address (SOT); in the load stream: end of loading (EOT), not stored |
| 0xC | `A` | CLRA | AP ← 0, a locked cell is written back first |
| 0xD | `P` | MemLock | sets the MemLock flag without a load: the cell takes the counter's value |
| 0xE / 0xF | `{` `}` | LABEG / LAEND | test AP; no TEST, no memory access |

Brackets are `x11x`: bit 0 open/close, bit 3 what is tested. IpLine's detector
is `insn[2] & insn[1]`; the scan counts both kinds together, so `[{]}` is illegal.
MachineCtrl: `loop_val_zero = op_q[3] ? ap_zero : data_zero`.

**MemLock copy.** `>` writes a locked cell A back and keeps A's value in the data
counter. The MemLock instruction at B sets the flag: the counter now owns B with A's value. The next
address change writes it into B. So `>P<` copies a cell to its right neighbour;
`P` on a locked cell changes nothing. MemLock never touches memory itself.

Gone: ISA0/ISA1 and the mode register, HRST/SRST opcodes (resets only from the
panel and SoftRstOnEOT), CLRL (the Loop overflow clears only on a reset), CLRI,
BELL opcode (the automatic bells on CIN/HALT/error stay), Debug CLRD (merged with
`[-]`), CLRML, LOAD, separate SOT/EOT.

## 3. Bootloader

Addresses below are for IP = 5; since TRS v0.63 (IP = 4, AP = 3) the ROM is 9990–9999, the first `<` wraps AP to 999 and the clear loop walks 1000 cells (`doc/width_ip4_ap3.md`).

```
99990: 0 < { 0 < }     AP = Data = 0 after Hard Reset; the first < wraps AP to the
                       top, { } walk down to AP = 0 clearing every cell
99996: N N N
99999: S               LD: loading starts, IP wraps to 0
```

`programs/bootloader.bfk` = `0<{0<}NNNS`; `IpMemory` `ROM_DIGITS = 1` (one decade,
`is_boot` = top four tetrads all 9); `IpLine`/`DekatronPC` `HARD_RST_D_CNT = 4`.
Program files end with `HE` (HALT, LD as EOT); with SoftRstOnEOT the machine
soft-resets and runs the program from 0.

## 4. What changed

- RTL: `MachineCtrl` (no `insn_mode`/`ip_clr` ports, 4-bit decode of `op_q`, `ap_op`
  4 bits), `IpLine` (no `clr`/`insn_mode`, states S_CLR_IP/S_CLR_LOOP removed,
  counters' `set_zero` tied off, EOT = `insn_in == 4'hB`), `ApLine` (4-bit `op`,
  MemLock only sets `lock_q`, S_FLUSH always ends in S_AP), `InsnLoopDetector` (x11x),
  `IpMemory` (one-decade ROM), `DekatronPC` (wiring, `HARD_RST_D_CNT = 4`),
  `bootloader.sv`, program files (`HDE` → `HE`).
- Emulator layer: `SymbolToOpcode`/`OpcodeToSymbol` 4-bit; `Keyboard` has no ISA
  switch (keys E/F are `{ }`); `KeyToSymbol` lost `BFISA`; `MS6205`,
  `KeyboardOpcodeInput`. The Emulator ↔ DekatronPC interface (Appendix B) did not
  change: `insn_mode` was internal.
- Tools: `generate_rom.py` (ISA16 table), `cycle_profile.py` (opcode names, `op_q`),
  `synth_sim.sh` (IpLine netlist built with `HARD_RST_D_CNT = 4`).
- Golden model `bfutils/dpcrun` (submodule, branch `ISA16`, fa057be): opcode enum,
  `isLoopOpen/Close`, `loopValZero` by bit 3, LD, MemLock, one-decade ROM; `mnemonic()`
  and `opcodeToSymbol()` lost the mode argument, `insnMode()` is gone.
- Tests: `IpLine_tb` (overflow and restart through a soft reset, `{ }` in the random
  scan program, LD as EOT, hard reset 99990), `ApLine_tb` (MemLock copy, MemLock with
  lock, COUT instead of LOAD), `MachineCtrl_tb` (16-code table, TEST only before
  `[ ]`, `loop_val_zero` by opcode, LD as SOT/EOT, panel resets, overflow cleared by
  reset), `DekatronPC_tb` (NOP prefix, 99990), cocotb (`test_conversions`,
  `test_key_symbol`, `test_keyboard`, `test_ip_memory`, `test_insn_loop_detect`),
  dpcrun unit tests (46).
- Documents: TRS v0.42 (§6.0 ISA16, old §6.2/§6.3 kept as history, removed codes
  Rejected, OPEN-003/004/009 closed), AGENTS.md, ISA.md, README.md, SCHEMES.md
  (sheets 4–7 redrawn).

## 5. Verification

| Check | Result |
|---|---|
| Verilator lint (DekatronPC, Emulator) | clean |
| `run_tests.sh -t` (Icarus blocks, DekatronPC helloworld/program; Verilator vs dpcrun on helloworld, program.bfk, pi.bfk) | pass |
| `run_tests.sh -d` (delay model, incl. pi.bfk) | pass, 9/9 |
| cocotb `make regression` | 34/34 (new codec tests checked to run, not skip) |
| dpcrun unit tests | 46/46 |
| `run_tests.sh -s` | pass, seed 0: 1111.0 tubes + 15 A110 |
| `synth_seeds.sh -s "0 1 2 3"` | §6 |
| `synth_sim.sh` (netlist) | 7/7 after the fix of its IpLine parameter (`HARD_RST_D_CNT = 4`) |
| `synth_sim.sh -t` (tube delays) | 4/4, 0 setup / 0 hold violations |
| Quartus | not run |

Not simulated in RTL: the full bootloader (clearing 100 000 cells is ≈ 2.5 M
cycles). It is covered on the golden model (`bootloader_clears_data_ram_and_loads`:
clears the data RAM, loads `++.HE`, the program runs), and the RTL testbenches cover
its pieces (`{0<}`, the AP wrap, LD at 99999 with SIMPLEBOOT).

## 6. Tube count

`synth_seeds.sh -s "0 1 2 3" IpLine ApLine MachineCtrl` (the AGENTS flow), base =
73d16e2 in a separate worktree:

| | IpLine | ApLine | MachineCtrl | Total |
|---|---|---|---|---|
| base 73d16e2 | 378.3 | 463.3 | 308.6 | 1150.1 |
| ISA16 | 388.3 | 459.5 | 262.5 | **1110.3** |
| Δ | +10.0 | −3.8 | −46.1 | **−39.8** |

Seed 0: 1111.0 (6N16B 652, 6Zh2B 376, 6Kh7B 67) + 15 dekatrons.

MachineCtrl gives the saving (no mode register, 4-bit decode, no ISA/reset/CLR
branches). ApLine saves little: MemLock is now a state-free lock set, CLRML/LOAD left
S_FLUSH/S_READ simpler, but the decoder was already shared.

**IpLine got worse (+10).** Removing S_CLR_IP/S_CLR_LOOP leaves 7 states; Yosys
`fsm_recode` (the RTL asks for `fsm_encoding = "binary"`) re-encodes them
sequentially, and that encoding is bad for this FSM (the effect noted in
insn_cost.md §2). IpLine alone, 5 autoidx perturbations × 8 seeds = 40 runs each:

| IpLine FSM | Tubes | ±SE |
|---|---|---|
| `"binary"` (as committed) | 385.2 | 0.6 |
| `"none"`, codes as written (0,1,2,4,5,6,10; 4 bits) | 377.1 | 0.8 |
| `"none"`, 3 bits, IDLE 0 · IP 6 · FETCH 1 · SCAN_EVAL 4 · LOOP 2 · INSN_IN 7 · HALT 3 | **374.1** | 1.0 |
| `"none"`, 3 bits, 7 other random assignments | 378.1 … 393.4 | |

(The base IpLine in the same method was 382.0, insn_cost.md §1.)

### 6.0. v0.43: MemLock rename and relays removed

`synth_seeds.sh -s "0 1 2 3"`: IpLine 389.1, ApLine 459.5, MachineCtrl 266.9, total
**1115.5** (+5.2 against v0.42). The five RELAY_2CO of MachineCtrl (bell switches,
run after reset) are now tube logic: MachineCtrl +4.4. Seed 0 in `run_tests.sh -s`:
1121.0 tubes + 15 A110. Checks on the final tree: `run_tests.sh -t` (pi.bfk etc.
match dpcrun), `-d` 9/9, `-s`, `synth_sim.sh` 7/7, `synth_sim.sh -t` 4/4 with 0
violations, dpcrun 46/46; cocotb 34/34 ran on the same tree before IpLine went back
to `"binary"` (cocotb has no IpLine test).

### 6.1. Encoding search (v0.43) and why it was not adopted

The owner allowed a search for a better IpLine encoding. With `fsm_encoding =
"none"` (Yosys keeps the RTL codes) and 3-bit codes:

- 96 random assignments × 8 runs, the best 12 × 40 runs: best IDLE 0 · IP 7 ·
  FETCH 6 · SCAN_EVAL 3 · LOOP 5 · INSN_IN 2 · HALT 4, **374.9 ± 0.7** against 385.2
  for `"binary"`.
- The 48 assignments with the fewest multi-bit transitions passing through a strobe
  state (6, the minimum for 3 bits) × 8 runs: best 377.3.

All `"none"` variants pass `run_tests.sh -t/-d/-s` and `synth_sim.sh` (netlist with
zero delays), but **fail `synth_sim.sh -t`** (netlist with tube delays): after `H`
the terminal gets garbage and the data counter sees write and reset at once
(`DekatronTubeDelay: illegal stimulus (conflict=1)`, 150 errors, TIMEOUT). Tried:
the chosen code, two others, the 4-bit RTL codes, two low-hazard codes, and **the
very codes Yosys picks for `"binary"`** (IDLE 0 · IP 5 · FETCH 2 · SCAN_EVAL 1 ·
LOOP 6 · INSN_IN 4 · HALT 3, read from its `fsm_recode` log) with `"none"`. All fail
identically, to the clock cycle, so the cause is not the codes or transition
hazards: the netlist Yosys builds without FSM extraction differs in some other way
that breaks timing under tube delays (0 setup/hold violations reported). Not
investigated further; IpLine stays on `"binary"`. TRS §22 carries it as an open
item; the zero-delay checks are not enough to accept an encoding change.

For comparison, the experiment in §7 measured −63.7 for ISA16 + CLRA with the
`DPC_CUT_*` harness (40-run method). The difference: MemLock is back (D), the hard
reset sets four decades instead of three, the IpLine FSM recode, and the method
(4 seeds versus 40 perturbed runs).

## 7. History: the experiment behind `DPC_ISA16`

Before the decision the same map (with C, D optional) was built behind a define on
top of the `DPC_CUT_*` harness and measured with 720 block syntheses (5 autoidx
perturbations × 8 seeds × 3 blocks × 6 configurations):

| Configuration | MachineCtrl | IpLine | ApLine | Δ total |
|---|---|---|---|---|
| ISA16, C and D = NOP | −42.0 | −6.1 | −18.4 | −66.5 |
| + CLRA | −42.1 | −6.5 | −15.2 | −63.7 |
| + BELL | −39.6 | −4.7 | −19.3 | −63.6 |
| + CLRL | −36.3 | +3.1 | −19.1 | −52.3 |
| + CLRA + CLRL | −36.4 | +2.4 | −15.2 | −49.2 |

## 8. Open points

1. IpLine FSM without extraction (§6.1): find why the `"none"` netlist fails under
   tube delays; then the searched code gives ≈ −10 tubes.
2. bfutils: the ISA16 commit lives on its `ISA16` branch (pushed with this work).
3. `rtl/DekatronPC/insnValues.sv` and `InsnDecoder.sv` still describe the old
   two-mode ISA (stale, only the old decoder and its cocotb test use them; TRS 19.4).
