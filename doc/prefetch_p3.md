# P3: prefetch of the next opcode while ApLine works

Date: 2026-10-07. Implements candidate P3 from `doc/cycle_profile_helloworld.md` §4
(owner decision). Requirement: REQ-PERF-003 (TRS v0.10). Touches REQ-APV2-008,
REQ-IPV2-008, REQ-CTLV2-010, REQ-MOD-009.

## 1. Summary

An operation on ApLine touches neither IP nor program memory. MachineCtrl therefore
issues the fetch of the next instruction in the same cycle as the ApLine operation. When
the operation ends, it goes straight to `S_DECODE` and skips `S_IDLE` and `S_FETCH_W`.

| | Before | After |
|---|---|---|
| helloworld, program window (cycles) | 5540 | **4184** (−24.5 %) |
| helloworld CPI | 13.8 | **10.4** |
| program.bfk, whole simulation incl. bootloader and loading | 179 734 µs | 142 722 µs (−20.6 %) |
| MachineCtrl tubes (mean of 3 `&deepsyn` seeds) | 248.3 | **318.7** (+70.4) |
| IpLine tubes (mean of 3 seeds) | 663.7 | 663.8 (unchanged) |

Both programs print the expected output. The Emulator ↔ DekatronPC interface
(TRS Appendix B) is unchanged.

## 2. Design

### MachineCtrl

- **Opcode latch `op_q` (4 flops).** Program memory's `rd_data` changes about two
  cycles after the prefetch is accepted, while ApLine is still working. So the current
  opcode is latched again, this time in MachineCtrl rather than IpLine (the old `insn_q`
  sat in IpLine). All decoding uses `op_cur = {insn_mode, op_q}`: the `S_DECODE` case,
  the bells, `is_cin`/`is_cout`/`is_ip_op`, and ApLine's operation. ApLine gets it
  through the new port `ap_op[4:0]`; ApLine itself is unchanged. `insn_mode` changes only
  in `S_DECODE` and on reset, so `{insn_mode, op_q}` holds until `ap_ready`.
- **When `op_q` loads** (`op_load`): in every cycle of `S_FETCH_W` (the last one carries
  the fetched opcode) and in the last cycle of an instruction that went through
  `S_WAIT`/`S_COUT` (`op_end`). At that moment `rd_data` already holds the prefetched
  instruction. If the next state is `S_IDLE` or `S_HALT` instead of `S_DECODE`, the load
  does no harm, because `S_FETCH_W` reloads `op_q` before the next decode.
- **Prefetch strobe.** `ip_valid = ((S_IDLE & ~halt_key) | (S_EXEC & ~is_bracket)) & go`.
  In `S_EXEC` this covers CLRL/CLRI (with `ip_clr`) and every ApLine operation except
  TEST (`[`/`]` in BF). Now `ip_clr = S_EXEC & is_ip_op`, no longer just `S_EXEC`.
- **`pf_q` (1 flop)** = "the next instruction is already fetched". It is set when `S_EXEC`
  hands over an ApLine operation other than TEST, and cleared in `S_DECODE`, in `S_IDLE`
  and on reset. It is the `ip_ahead` output to IpLine.
- **End of instruction.** `s_next = (halt_key | one_step) ? S_HALT : pf_q ? S_DECODE :
  S_IDLE`. `S_WAIT` still waits for `go` (both lines ready), so IpLine has finished the
  prefetch before `S_DECODE` or `S_HALT`.

### IpLine

- New input **`ip_ahead`**. When it halts (`halt_rq` in `S_IDLE`), IpLine normally steps
  IP from the executed instruction to the next one. With `ip_ahead`, IP is already
  there: there is no step, and only `ip_counted_q` is cleared, so after Run the same
  instruction is read again without a step.
- Otherwise unchanged. IpLine still has no opcode register (REQ-IPV2-008). It decides
  whether to scan in the accept cycle, while `insn` still holds the current instruction.
  A prefetch is never issued for a bracket, so a prefetch never starts a scan.

### Which instructions prefetch

| Instruction | Prefetch | Why |
|---|---|---|
| `+ - > < . [-]`, CLRML, LOAD, STORE (BF); CLRD, CLRA (Debug) | yes | operation on ApLine only |
| `[` `]` with `data_zero_valid` low (TEST) | no | the scan decision needs the result of TEST and the bracket on `insn` |
| `[` `]` otherwise, `{` `}` | no | no ApLine operation; IpLine scans on the next request |
| `,` CIN | no | waits for the terminal, no gain; `rx_rdy` stays tied to the end of CIN |
| CLRL, CLRI | no | IpLine operation; IpLine picks it from `insn[0]` at accept |
| NOP, BELL, ISA0/1, SOT, HALT, HRST, SRST | no | never reach `S_EXEC` |
| anything while loading | no | loading never reaches `S_EXEC` |

### Visible effects

- **Panel IP.** While a prefetching instruction executes, IP shows the next instruction,
  and so does `Insn` (it is `rd_data`). After a halt both show the next instruction to
  execute. Before P3, `Insn` still showed the executed one at that point.
- **Step mode.** Each step executes exactly one instruction. If that instruction
  prefetched, the next one is fetched twice: once as the prefetch, and again after the
  step key, because a halt clears `ip_counted_q`. Reads of program memory have no side
  effects, so this costs only time.
- **Halt right after a bracket** still steps IP without a scan (the existing defect,
  `doc/dpcrun_golden_model.md`, SCHEMES sheet 4). Brackets don't prefetch, so P3 neither
  fixes nor worsens it.

### Testbench retire point

`rtl/tests/DekatronPC.sv/DekatronPC_tb.cpp` used to retire an instruction when
MachineCtrl came back to `S_IDLE`/`S_HALT` after `S_DECODE`. Now an `S_DECODE` entered
from `S_WAIT`/`S_COUT` also retires one. At that point RTL IP = model IP + 1: the model
keeps IP on the executed instruction, as the RTL did before P3. The golden model is
unchanged.

## 3. Cycles on helloworld

Same setup as `doc/cycle_profile_helloworld.md` §1 (Icarus, `MEM_READ_CYCLES = 1`,
`WRITE_MIN_HS = 100`). Window: end of the EOT soft reset to HALT.
`rtl/run/cycle_profile.py` now reads `machineCtrl.op_cur`; pass `--op machineCtrl.op_full`
for dumps of the RTL before P3. It also starts an instruction at a `S_DECODE` entered from
`S_WAIT`/`S_COUT`, and reports a new category, "WAIT: ApLine done, prefetch in flight".

| Where the cycle goes | Before | After |
|---|---|---|
| MachineCtrl FETCH_W | 1576 | 60 |
| Loop scan inside IpLine | 1143 | 1143 |
| WAIT: Data counter write window | 570 | 570 |
| WAIT: ApLine done, prefetch in flight | – | 537 |
| MachineCtrl IDLE | 401 | 22 |
| MachineCtrl DECODE | 401 | 401 |
| WAIT: ApLine done, MachineCtrl sees go | 399 | 399 |
| MachineCtrl EXEC | 379 | 379 |
| WAIT: ApLine DOP / AP / DSET / READ / FLUSH | 655 | 655 |
| COUT, RST_WAIT | 16 | 18 |
| **Total** | **5540** | **4184** |

| Op | Count | Cycles before → after | Cycles per instance after |
|---|---|---|---|
| `+` | 254 | 2895 → 2044 | 6 ×207, 17 ×45, 15 ×1, 22 ×1 |
| `]` | 10 | 1203 → 1153 | 128 ×9 (taken), 1 ×1 |
| `>` | 46 | 506 → 331 | 6 ×35, 11 ×11 |
| `<` | 42 | 400 → 252 | 6 ×42 |
| `-` | 24 | 346 → 254 | 6 ×14, 17 ×10 |
| `.` | 13 | 145 → 115 | 7 ×10, 17 ×2, 11 ×1 |
| `[` | 10 | 33 → 28 | 3 ×9, 1 ×1 |

A plain `+` now takes 6 cycles: `S_DECODE`, `S_EXEC` (both lines accept), then 4 cycles
of the fetch (IP step, memory accept, memory busy, ready). The Data step is one of them.
**The fetch is now the critical path** of a simple instruction. A `+` after an address
step (lazy read) takes 17: ApLine's 10-cycle write window is longer than the fetch, so the
fetch is fully hidden. A `>` takes 11 instead of 6 when the cell is dirty (flush first).

The original estimate in the profile report was `+` → ~5 and up to ~1500 cycles saved.
The measured saving is 1356 cycles, and `+` takes 6. The fetch takes one cycle more than
ApLine's Data step, and nothing hides that cycle.

## 4. What could come next

- **P1** (Mealy `ip_valid`/`ap_valid`) now matters less: `S_IDLE` is almost gone
  (22 cycles). Dropping `S_EXEC` would still save one cycle per ApLine instruction
  (379 here).
- **P2** (3-cycle scan step) is unaffected. Loop scans are now 27 % of the run.
- **IpLine fetch in 3 cycles.** `S_IP` and `S_FETCH` are separate states. Issuing the
  memory read in the cycle the IP step ends, the same idea as P2, would shorten both the
  prefetch and the scan step.

## 5. Tube cost

Per-block synthesis with `synt_dpc.tcl` (same flow as `run_tests.sh -s`), with the old
RTL (git HEAD) and the new RTL side by side. Seeds were set with `&deepsyn -S n` on
scratch copies of `abc_area.abc`. `equiv_opt` was proven in every run.

| Seed | MachineCtrl before | MachineCtrl after | IpLine before | IpLine after |
|---|---|---|---|---|
| 1 | 246.5 | 320.5 | 666 | 668.5 |
| 2 | 250 | 317 | 660.5 | 658.5 |
| 3 | 248.5 | 318.5 | 664.5 | 664.5 |
| **mean** | **248.3** | **318.7** | **663.7** | **663.8** |

The MachineCtrl increase is +70.4 tubes:

- 5 flops (`op_q`, `pf_q`), 7 tubes each: 35 tubes;
- the `op_q` load enable and the input muxes on `op_q`;
- `s_next` grows from two-way to three-way, and `ip_valid`/`ip_clr` now depend on the
  opcode.

A first version latched `op_q` only in `S_DECODE` and decoded `S_DECODE` from the live
`insn`. That meant two decoders, one on `insn` and one on `op_q`, and cost +78.7 (mean
of 320/330/331). Decoding everything from `op_q` saves about 8 tubes.

This moves the three synthesized blocks from 1595.5 to about 1666 tubes. The whole
machine has a budget of 1200 (REQ-MOD-009, already exceeded), so the speedup costs
about 4 % of that budget.

## 6. Verification

Run in this session:

- Verilator `--lint-only -Wall` with `rules.vlt`: clean for `DekatronPC` and `Emulator`.
- `MachineCtrl_tb` (Icarus), extended. The ApLine model checks `ap_op` instead of
  `{insn_mode, insn}`. The IpLine model changes `insn` as soon as the prefetch is done,
  and re-reads the same opcode after a halt with `ip_ahead`. The monitor allows
  `ip_valid` with `ap_valid` only for prefetch: `ip_clr` low, and neither TEST nor CIN.
  The ISA table checks that exactly the ApLine operations other than TEST prefetch. The
  step test checks `ip_ahead` after each step, that every instruction executes exactly
  once although it is fetched twice, and that the prefetched NOP runs after Run. Passes.
- `IpLine_tb`: new case 5a, halt with `ip_ahead`. IP stays, the instruction is re-read
  at the same address after release, and the next fetch steps normally. Passes.
- `ApLine_tb`: unchanged, passes.
- `DekatronPC_tb` (Icarus): helloworld ("Hello World!\n", bootloader halt at IP 00112,
  `check_ip_moving`) and program.bfk pass.
- Testbench changes avoid `break`/`continue` (CI Icarus 12).

Not run in this session (heavy jobs, need the owner's go-ahead):

- `DekatronPC_tb.cpp -s` in Verilator, the step-by-step compare against dpcrun with the
  new retire rule.
- `synth_sim.sh`, the netlist simulation (a required CI check).
- `pi.bfk`: `DekatronPC_tb_cfg_pi.svh` has no `TRY_PROGRAM`, so the Icarus test doesn't
  run the program.
