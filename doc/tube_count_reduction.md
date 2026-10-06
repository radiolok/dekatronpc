# Tube count: analysis of the synthesis report and how to reach ≤ 1500

Date: 2026-10-06. Covers the Yosys netlists of `IpLine`, `ApLine` and `MachineCtrl`
(`rtl/run/run_tests.sh -s`, `rtl/run/synt_dpc.tcl`, `rtl/vtube/vtube_cells.lib`
with the uncommitted renames `NOT_N16`, `A1OOI_N16J2`, `A2OOI_J2`).
No RTL or flow file was changed. All experiments ran on scratch copies.

## 1. Baseline

`python3 dpc_stat.py -j IpLine.json,ApLine.json,MachineCtrl.json` on the netlists
from 2026-10-06 22:38, after commit fb4fff7:

| Block | Tubes | of which counters | glue (FSM + muxes) |
|---|---|---|---|
| IpLine | 784.5 | IP 188, Loop 77, InsnLoopDetector 5.5 | **514** |
| ApLine | 871.5 | Data 213, AP 185 | **473.5** |
| MachineCtrl | 482.5 | – | **482.5** |
| **Total** | **2138.5** | 668.5 | **1470** |

The glue between the dekatrons takes 69 % of all tubes, while the four counters
take 31 % (their codecs: BinToBcd 13 × 9, BcdToBinEn 3 × 23, PulseSender 15 × 6).

By cell type, flops are the largest single item: 106 `DFFSR_n` + 24 `DFF` =
130 triggers × 3.5 = **455 tubes (21 %)**. The IpLine and ApLine flop counts
(33 and 31) include one-hot state registers (12 and 9 bits): Yosys `synth` extracts
those FSMs and recodes them to one-hot. MachineCtrl's `state` is an output port,
so its FSM is not extracted.

What the count does **not** include: `Ram`/`IpMemory` (stubbed under `SYNTH`),
`RstTimeRelay`, the panel and the dekatrons themselves. The 1500 target needs a
scope (see §6, Q1).

## 2. Findings in the flow and the library

1. **`fsm -encoding onehot` in `synt_dpc.tcl` is a no-op.** It runs after `synth`,
   which has already done FSM extraction. Measured: an explicit binary pass gives the
   same 2138.5, and `synth -nofsm` gives 2165 (+27). FSM encoding is not a lever.
2. **ABC maps for delay, not area.** `abc -liberty` with the default script is
   delay-oriented. In tubes only area matters (1 MHz is slow for a gate).
3. **`DFF` has `heat_current: 8500`**, ten times `DFFSR`/`DFFSR_n` (850). This
   looks like a typo. It adds 204 A of the 813 A in the heat-current total (about
   1.3 kW of the 5.1 kW estimate). It does not affect the tube count.
4. 51 of the 161 inverters (25 tubes) only invert a flop output. A tube trigger
   (Eccles–Jordan) has both anodes, so Q̄ is free physically. The library DFF cells
   expose only `Q`.

## 3. Measured: synthesis-only changes (no RTL change)

Only the `abc` line in `synt_dpc.tcl` was changed to `abc -liberty $cell_lib -script <file>`:

| Variant | ABC script | Total | Δ | Time for 3 modules |
|---|---|---|---|---|
| baseline | default (delay) | 2138.5 | – | ~3 s |
| A | `strash; dch; map -a; topo` | 2059 | −79.5 | ~2 s |
| B | `strash; ifraig; scorr; dc2; strash; dch -f; map -a; topo` | 2023 | −115.5 | ~2 s |
| E | B + 2× resyn2 + a second `dch -f; map -a` pass | 1992 | −146.5 | ~3 s |
| **G** | `strash; &get -n; &deepsyn -T 10; &put; dch -f; map -a; topo` | **1817.5** | **−321** | ~2.5 min |

G by block: IpLine 665, ApLine 781.5, MachineCtrl 371. `&deepsyn` is SAT-based
exact resynthesis, so its gain grows with `-T`, but so does runtime (this is the
heavy part on a small node).

Things that do not work: `mfs2` turns the result into `$lut` cells (no library
mapping), and `resyn2`/`amap` are either missing aliases in Yosys' ABC or worse
(`amap`: 2072).

**Required before adopting G:** an equivalence check of the mapped netlist
against RTL (`equiv_make`/`equiv_induct` in Yosys, or the cocotb tests on the
`*_synth.v` gate netlist). ABC is trusted, but this flow then feeds the tube
build, so it must be checked.

## 4. Measured: RTL prototype of ApLine

A scratch rewrite of ApLine for area estimation only. It passes Verilator lint but
has **not** been simulated. Changes:

- `rx_q` (12 flops plus their enable muxes) removed: `data_in` takes `rx_data_bcd`
  directly. This needs the terminal side to hold RX data stable until CIN is done.
- OP/WAIT state pairs merged: 9 states → 6 (`IDLE, FLUSH, READ, AP, DSET, DOP`). The
  WAIT states are redundant because `ready` in IDLE already ANDs `ap_ready & data_ready & mem_ready`.
- The 7 registered strobes (`ap_valid`, `ap_set_zero`, `data_valid`, `data_set`,
  `data_set_zero`, `mem_valid`, `mem_wr`) are decoded from `state` (Moore outputs).
  This is allowed by the handshake rule: `valid` may depend on state, and only
  `ready` must not depend on `valid`.

| | Script B | Script G |
|---|---|---|
| ApLine now | 835.5 | 781.5 |
| `rx_q` removed only | 769.5 (−66) | – |
| Prototype (all three) | 640.5 (−195) | **607.5 (−174)** |
| Flops in ApLine glue | 31 → 18 | 31 → 18 |

The ApLine glue goes from 406.5 to 232.5 tubes (−43 %). Before this can be used,
check that a held-level `mem_valid` matches the RAM handshake (now it is a pulse
re-raised while `mem_ready & ~mem_rd_valid`).

Negative result: making MachineCtrl's `state` internal (so Yosys extracts and
one-hot encodes it) gives 444 → 482.5 under B, which is worse.

## 5. Estimated: further RTL ideas

The estimates come from the ApLine result and from cell costs (flop with enable ≈ 5
tubes, 2:1 mux bit ≈ 1.5–2, NOT 0.5).

| # | Idea | Est. Δ | Changes a rule or requirement? |
|---|---|---|---|
| R1 | Same FSM cleanup in **IpLine**: merge `IP_OP/IP_WAIT`, `LOOP_OP/LOOP_WAIT`, `CLR_OP/CLR_WAIT`; decode `ip_valid`, `loop_valid`, `ip_set_zero`, `loop_set_zero`, `mem_valid`, `mem_wr` from state; `clr_is_loop_q` becomes two states | −100 … −130 | no |
| R2 | Same in **MachineCtrl**: merge `FETCH/FETCH_W`, `IP_OP/IP_OP_W`, `AP_OP/AP_OP_W`, `COUT`/`ECHO`; decode `ip_valid`, `ap_valid`, `tx_vld`, `*_rst_req` from state; remove the unreachable `S_BELL` (nothing enters it) | −80 … −110 | no |
| R3 | **Decode once.** Pass `{insn_mode, insn}` (already stable in IpLine's `insn_q`) to ApLine and IpLine as the op, instead of re-encoding it to `ap_op[3:0]`/`ap_dec`/`ip_op[1:0]`. This drops 7 registers and the encoder in MachineCtrl. CIN/TEST become ApLine's own sub-ops | −30 … −50 | internal interface only (ApLine/IpLine op codes) |
| R4 | Drop `insn_q` in IpLine: the program memory's output register already holds the last opcode (same as the data memory's write-through register). Loading mode can take `insn_in` straight away | −15 … −20 | check IpMemory rd_data hold semantics |
| R5 | Panel edge detection (`key_moved_q`, the `one_step` release logic) done once, in the panel or MachineCtrl, not duplicated in IpLine | −10 … −20 | no |
| R6 | `QN` pin on `DFF`/`DFFSR_n` in the liberty, plus a post-map pass that replaces `NOT(Q)` with `QN` | −20 … −25 | library only; confirm the tube trigger really gives Q̄ for free |
| R7 | COUT always from the Data counter: if the cell isn't locked, LOAD it first. That removes the 10-bit `tx_data_bcd` mux. It costs one write window per `.`, which is negligible at 110 baud | −20 … −30 | changes the ApLine COUT path (lazy read stays for TEST) |
| R8 | Shared counter control: only one counter steps at a time (asserted in IpLine and MachineCtrl), so the four `writeTimer`/`Impulse`/`DekatronPhaseGen`/3-bit FSM sets can become one or two | −40 … −80 | yes: §5 "one phase generator per counter", counter as a self-contained Valid/Ready unit |
| R9 | Address memories with dekatron cathodes one-hot (10 lines per decade) instead of BCD: drops BinToBcd on IP and AP (exactly −90) **and** the BCD→1-of-10 decoders on the memory side, which aren't counted today | −90 (+ memory) | yes: §3 "addresses are raw BCD tetrads"; 50 address wires instead of 20 |
| R10 | Use the Data counter as the nesting counter during a scan (flush first): removes the Loop counter (74.5 tubes + 2 dekatrons) | −75 | yes: REQ-CNT-002/007 overflow semantics, IpLine/ApLine coupling. Listed for completeness and **not recommended** |
| R11 | Flatten MachineCtrl+IpLine+ApLine for synthesis (keep counters and DekatronModule as instances) so constant ops propagate across the boundary | unknown | no. The experiment failed to set up: SYNTH stubs of RstTimeRelay/memories fold the netlist to constants |

## 6. Path to ≤ 1500

| Step | Total |
|---|---|
| Baseline | 2138.5 |
| §3 ABC script G (measured) | 1817.5 |
| §4 ApLine cleanup + no `rx_q` (measured, G) | 1643.5 |
| R1 IpLine cleanup (≈ −115) | ≈ 1530 |
| R2 MachineCtrl cleanup (≈ −95) | ≈ 1435 |
| R3 decode once (≈ −40) | ≈ 1395 |
| R6 QN pins (≈ −22) | ≈ 1375 |
| optional R7/R8/R9 | ≈ 1170 … 1290 |

So **≤ 1500 is reachable without architectural changes**: the area ABC script
plus FSM hygiene in the three control blocks (Moore strobes, merged OP/WAIT pairs)
and dropping `rx_q`. The margin is about 100–125 tubes. R1–R3 are estimates.
R7–R9 add margin, but R8/R9 touch rules the owner set.

Order of work (light tools first, per AGENTS §0):
1. ABC script G in `synt_dpc.tcl` + an equivalence check step.
2. ApLine rewrite (prototype exists), new ApLine cocotb test (TRS §22 already asks for one).
3. IpLine, then MachineCtrl, each with its own test first.
4. R3, then R6.

## 7. Questions for the owner

1. What does the 1500 budget cover: only the logic counted today (IpLine/ApLine/
   MachineCtrl incl. counter glue), or also memory support, reset relay and panel?
   Should it become a REQ in the TRS?
2. OK to switch `synt_dpc.tcl` to the deepsyn ABC script (2.5 min instead of 3 s)
   and add an equivalence check?
3. Can the terminal side hold `rx_data_bcd` until CIN completes, so ApLine drops
   `rx_q`? The signal stays, but its timing contract (TRS Appendix B) changes.
4. R8 (shared counter control) and R9 (one-hot memory address): worth pursuing, or
   do the §3/§5 rules stand?
5. Does the tube trigger really give Q̄ without extra tubes (R6)?
6. Is `DFF heat_current: 8500` a typo for 850?

## 8. Owner's decisions and what was done (2026-10-06, later the same day)

Decisions:
1. The budget is **1500 tubes for the whole machine** (REQ-MOD-009). No further
   investigation in this step.
2. Fix `synt_dpc.tcl` (done, see below).
3. RX uses a Valid/Ready handshake. The sending side holds `rx_data_bcd` until the
   handshake, so ApLine needs no input register (REQ-UART-008). Today `DekatronPC`
   has only `rx_vld`; an `rx_rdy` port is needed, which is a change to TRS Appendix B.
4. R8/R9 (shared counter control, one-hot memory address) are not applicable.
5. The tube trigger has `QN` for free (REQ-MOD-010).
6. The owner updated the library: a trigger (`DFF`, `DFFSR`, `DFFSR_n`) costs
   **7 tubes** (3 × N16B + 4 × J2B) with 2 A of heater current at 6.3 V.

With 7-tube triggers, the 130 triggers cost 910 tubes, **39 %** of the three
blocks. Every flop removed now saves about 7–9 tubes (with its enable mux), so
§4/§5 (Moore strobes, merged states, no `rx_q`, decode once) matter even more.

### Flow changes

- `rtl/vtube/vtube_cells.lib`: `QN` pin (`function: "IQN"`) on `LATCH`, `DFF`,
  `DFFSR`, `DFFSR_n`.
- `rtl/run/abc_area.abc`: `strash; &get -n; &deepsyn -J 50 -T 30; &put; dch -f; map -a; topo`.
  `-J` (stop after 50 steps without improvement) keeps the result reproducible.
  `-T 30` only caps the runtime.
- `rtl/run/synt_dpc.tcl`:
  - The no-op `fsm -encoding onehot` is removed.
  - The library path is resolved from the script's directory.
  - `equiv_opt -assert -async2sync -map <cell models>` proves the ABC mapping before
    it runs for real. `equiv_opt` restores the pre-ABC design, so `abc` runs a second
    time. The proof covers the **top module only** (the glue), not the counter
    submodules.
  - The mapped netlist is passed through `rtl/run/qn_absorb.py` (via JSON), which
    moves every inverter on a trigger's `Q` to its `QN`.

### Results (new library, `run_tests.sh -s` set: IpLine, ApLine, MachineCtrl)

| Flow | IpLine | ApLine | MachineCtrl | Total |
|---|---|---|---|---|
| old `synt_dpc.tcl` | 998.5 | 1065.5 | 572 | 2636 |
| new, `-J 50` (25 s for the three) | 876 | 989 | 471.5 | **2336.5** |
| new, `-J 200` (80 s) | 873 | 989 | 468.5 | 2330.5 |
| new, `-J 1000` (246 s) | 873 | 989.5 | 466.5 | 2329 |

`-J 50` was kept: larger values cost minutes for 0.3 %.

Projection to 1500 for the whole machine: the measured ApLine cleanup removes 13
triggers (−91 tubes from flops alone), and R1–R3 should remove about 25 more in
IpLine/MachineCtrl. Even so, the three blocks would stay around 1900–2000 before
memory, reset and panel are counted. Reaching 1500 will need more flop reduction
than §5 lists, for example state and flags moved into dekatron-driven sequencing.
That is the next step's question.

## 9. Done: RX handshake, `rx_q` removed (REQ-UART-008)

Changes:
- `ApLine`: the 12-bit `rx_q` register is gone. For CIN, `data_in` comes straight from
  `rx_data_bcd`, and the Data counter loads it during the write window.
- `MachineCtrl`: new output `rx_rdy = (state == S_AP_OP_W) & (ap_op == AP_CIN) &
  ap_ready & ~(soft_rst | hard_rst)`. It is combinational, needs no extra flop, and
  doesn't depend on `rx_vld`. The handshake `rx_vld & rx_rdy` happens in the cycle
  ApLine finishes CIN, so `rx_data_bcd` is stable for the whole write.
- `DekatronPC`: new output port `rx_rdy` (TRS Appendix B, breaking change).
- `Emulator.sv`: a receive buffer (8-bit `rx_data` + `rx_vld`) catches the UART/consul
  byte on the rising edge of its `vld` and holds it until `rx_vld & rx_rdy`. The
  rising edge matters because the consul's `kb_data_vld` lasts many 1 MHz cycles. A
  byte that arrives while the buffer is full is dropped, the same as before.
- Testbenches: `DekatronPC_tb.sv` connects `rx_rdy`. `DekatronPC_tb.cpp` holds
  `rx_vld` until the handshake. `ApLine_tb` gained a CIN check (CIN 65, flush on an
  AP step, LOAD reads back 65).

Verification:
- Verilator `--lint-only -Wall` is clean for DekatronPC and Emulator.
- `run_tests.sh -t`: all Icarus tests pass (Dekatron, Counter, IpLine, ApLine,
  DekatronPC ×2). The Verilator golden-model runs build and exit 0, but they check
  nothing: without `-s`, the core halts after 12 clocks (IRET=0). This was already
  the case before this change and is TRS §22 item 5. Neither of their programs
  runs CIN.
- `tb make regression`: 34/34 PASS. It has no ApLine/MachineCtrl/DekatronPC targets.
- The Emulator receive buffer is checked by lint only.
- Housekeeping: a stale `rtl/run/obj_dir/DekatronPC_tb.d` still pointed to the old
  `tests/DekatronPC.sv/dpcrun.h` and broke the Verilator build. It was deleted.

Synthesis (`run_tests.sh -s`, `-J 50`). `dpc_stat.py` needs the `liberty` module from
`rtl/run/.venv`; with the system python the script ends with exit 1.

| Block | before (§8) | now | Δ |
|---|---|---|---|
| IpLine | 876 | 874.5 | −1.5 (ABC noise, RTL unchanged) |
| ApLine | 989 | 874 | **−115** |
| MachineCtrl | 471.5 | 493.5 | +22 (`rx_rdy` decode, plus ABC variance) |
| Total | 2336.5 | **2242** | −94.5 |
