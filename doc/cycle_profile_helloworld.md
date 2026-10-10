# Cycle profile of helloworld.bfk on the RTL

Date: 2026-10-07. Scope: where the clock cycles go when the RTL runs
`rtl/programs/helloworld.bfk`, and which changes would cut them.
Requirements: REQ-PERF-001 (loop scan step), REQ-PERF-002 (measurement).
Tool: `rtl/run/cycle_profile.py` (wavepeek over the simulation dump).

Nothing in the RTL was changed. The section 4 numbers are estimates read off
the waveform, not measured on modified RTL.
Later the same day P3 was implemented; measured results are in
`doc/prefetch_p3.md`. `cycle_profile.py` now defaults to the post-P3 RTL:
pass `--op machineCtrl.op_full` to profile a dump of the RTL described here.

## 1. How to run

The DekatronPC Icarus test from `run_tests.sh -t`, built in a scratch
directory so the tracked `DekatronPC_tb.svh` isn't overwritten, with FST
output:

```
cd rtl/run
python3 generate_rom.py -f ../programs/helloworld.bfk -o $W/hello.hex --hex
iverilog -g2012 -o $W/DPC_UT -DIPMEMFILE -DSIMPLEBOOT \
  "-DADDINCLUDE=\"$PWD/../tests/DekatronPC.sv/DekatronPC_tb_cfg_hello.svh\"" \
  "-DPROGRAM_PATH=\"$W/hello.hex\"" -s DekatronPC_tb \
  ../tests/DekatronPC.sv/DekatronPC_tb.sv $(cat ../DekatronPC/DPC.files) \
  $(cat ../tests/DekatronPC.sv/DekatronPC_tb.files)
cd $W && vvp -n DPC_UT -fst && mv DekatronPC_tb.vcd hello.fst   # 2.5 s
python3 .../rtl/run/cycle_profile.py hello.fst --from 2685100000ps --to 13764100000ps
```

The test passes ("Hello World!\n"). In this testbench Clk = hsClk/10 and
has a 2 µs period. The machine is specified at 1 MHz (1 µs), so the profile
below counts cycles, not time. Memory runs with `MEM_READ_CYCLES = 1`,
`MEM_WRITE_CYCLES = 1` (the DekatronPC defaults), so a read takes two
cycles from accept to data. The Data counter write window is
`WRITE_MIN_HS = 100` hs, which is 10 Clk.

Window boundaries were found with
`wavepeek change ... --signals insn_loading,is_halted,rst_line`:

| Phase | Cycles |
|---|---|
| Bootloader (99900…) up to SOT | 600 |
| Loading 114 opcodes over InsnIn (about 6 per opcode) | 689 |
| EOT soft reset | 10 |
| **Program execution, ISA1 to HALT** | **5540** |

## 2. Result: 401 instructions in 5540 cycles, CPI 13.8

Every cycle of the execution window, classified by the states of
MachineCtrl, IpLine and ApLine:

| Where the cycle goes | Cycles | % |
|---|---|---|
| MachineCtrl FETCH_W (IP step, memory read, insn valid) | 1576 | 28.4 |
| Loop scan inside IpLine (backward search for `[`) | 1143 | 20.6 |
| Data counter write window after DSET (lazy read) | 570 | 10.3 |
| MachineCtrl IDLE (requests the next insn) | 401 | 7.2 |
| MachineCtrl DECODE | 401 | 7.2 |
| MachineCtrl WAIT, ApLine already idle (MachineCtrl sees go) | 399 | 7.2 |
| MachineCtrl EXEC (issues ap_valid) | 379 | 6.8 |
| ApLine DOP (the +/- step itself) | 278 | 5.0 |
| ApLine AP (address step) | 145 | 2.6 |
| ApLine DSET / READ / FLUSH | 117 / 58 / 57 | 2.1 / 1.0 / 1.0 |
| COUT, RST_WAIT | 16 | 0.3 |

By instruction. The scan started by a taken `]` is charged to that `]`.

| Op | Count | Cycles | CPI | Cycles per instance |
|---|---|---|---|---|
| `+` | 254 | 2895 | 11.4 | 9 ×207, 22 ×46, 20 ×1 |
| `]` | 10 | 1203 | 120.3 | 133 ×9 (taken), 6 ×1 (exit) |
| `>` | 46 | 506 | 11.0 | 11 ×46 |
| `<` | 42 | 400 | 9.5 | 9 ×31, 11 ×11 |
| `-` | 24 | 346 | 14.4 | 9 ×14, 22 ×10 |
| `.` | 13 | 145 | 11.2 | 9 ×10, 11 ×1, 22 ×2 |
| `[` | 10 | 33 | 3.3 | 3 when landed on by a scan, 6 on first entry |

## 3. Anatomy (from the waveform)

**A plain `+` takes 9 cycles.** Only 4 of them are physics: the IP step,
the two-cycle memory read and the Data step.

```
IDLE      MachineCtrl raises ip_valid
FETCH_W   IpLine S_IP: IP counter steps
FETCH_W   IpLine S_FETCH: memory accepts the read
FETCH_W   memory busy
FETCH_W   memory ready -> IpLine ready, MachineCtrl samples insn_valid
DECODE
EXEC      ap_valid
WAIT      ApLine S_DOP: Data counter steps
WAIT      ApLine idle again -> MachineCtrl samples go
```

Every layer is a Moore FSM that hands over through valid/ready, so each
handover costs one cycle. IDLE, DECODE, EXEC and the last WAIT cycle add
up to 1580 cycles (28.5%), and none of them does work on a counter.

**A `+` after an address step takes 22 cycles** (46 of the `+`, 10 of the
`-`, 2 of the `.`). This is the lazy read: the cell isn't in the Data
counter, so ApLine runs S_READ (1), then S_DSET (2, the first cycle waits
for the memory), then S_DOP for 11 cycles. After `data_set`, `data_ready`
stays low for the 10 Clk write window (`WRITE_MIN_HS = 100` hs), and only
then is the step accepted. 57 loads × 10 = 570 cycles.

**A `>` takes 11 cycles** when the cell is dirty: S_FLUSH (1), then S_AP for
2 cycles. The first S_AP cycle only waits for the memory write to finish
(`go` includes `mem_ready`), although the address step doesn't use memory.
That's 57 cycles.

**A taken `]` scans backwards at 4 cycles per opcode.** It walks 31 opcodes
back (IP 42 → 11) in 127 cycles:

```
S_IP        IP counter steps back
S_FETCH     memory accepts the read
S_SCAN_EVAL memory busy
S_SCAN_EVAL memory ready, opcode evaluated -> S_IP (or S_LOOP on a bracket)
```

The same 4 cycles apply to forward scans. With 1.7 scan steps per executed
instruction on Brainfuck-100 (TRS v0.9, REQ-PERF-001), the scan step costs
as much as an instruction on average.

## 4. Where cycles can be saved

The estimates are for this run (5540 cycles). The candidates overlap, so
their savings don't simply add up.

| # | Change | Est. saving | Cost and risks |
|---|---|---|---|
| P1 | **Shorten the MachineCtrl chain.** Raise ip_valid as soon as the previous op finishes (in the WAIT/DECODE cycle where go rises), dropping S_IDLE, and raise ap_valid from S_DECODE, dropping S_EXEC. ready still doesn't depend on valid. | ~780 (14%), `+` 9 → 7 | Mealy outputs on state & go. Tube count needs checking (fewer states, wider decode). Small change, local to MachineCtrl. |
| P2 | **Scan step in 3 cycles.** In S_SCAN_EVAL, when go and the opcode isn't a bracket, issue the IP step in the same cycle (Mealy ip_valid) instead of passing through S_IP. | ~285 (5%), more on scan-heavy programs | Local to IpLine. Keep scan_done/overflow ordering. Directly serves REQ-PERF-001. |
| P3 | **Done (2026-10-07, `doc/prefetch_p3.md`): 5540 → 4184 cycles, `+` 9 → 6, MachineCtrl +70 tubes.** **Fetch the next opcode while ApLine works.** IpLine steps IP and reads during S_WAIT of `+ - < > .`; the read hides the 10-cycle write window. | up to ~1500 (27%); `+` → ~5, lazy `+` → ~14 | `insn` is the memory's `rd_data`, so ApLine would lose its opcode. It needs an op latch again (insn_q was removed for tubes, decode once §14). Brackets, HALT, step mode and the panel IP display (IP runs one ahead) need rules. **Architecture decision.** |
| P4 | **Loop-start register.** Remember the IP of the `[` on entry; a taken `]` loads it instead of scanning. | ~1000 (19%) here, much more on pi.bfk | 5 more dekatrons plus write circuitry, and each jump is a counter write (10 Clk window). Nesting needs a stack or falls back to scanning. **Architecture decision; affects the tube budget.** |
| P5 | **Calibrate WRITE_MIN_HS** (OPEN-013/014). 100 hs is an estimate. | 570 × (1 − real/100) | Hardware measurement, no RTL change. |
| P6 | **AP step without waiting for the memory write** (drop `mem_ready` from `go` in S_AP). | 57 (1%) | Only valid if the memory latches the address at accept. The FPGA `Ram` does ("адрес берётся живой", bank captures on the accept edge); ferrite memory probably holds the address for the whole cycle. Low value. |

Without architecture changes, P1 + P2 bring the run from about 5540 to
4480 cycles (CPI about 11). P3 and P4 are the large items. Each changes
the datapath and the tube count, so the owner has to decide on them.

## 5. Notes

- A cycle-level profile only means anything once the dekatron timing is
  calibrated (OPEN-013/014). The ratios between the categories hold as long
  as a counter step stays at one Clk and a write stays much longer than a
  step.
- REQ-PERF-002 asks for the same profile over Brainfuck-100 in Verilator.
  `cycle_profile.py` works on any dump that has the `DekatronPC_tb.dekatronPC`
  hierarchy. The full set needs the Verilator build of DekatronPC_tb.cpp
  with tracing, which is a heavy job, so it hasn't been run yet.
