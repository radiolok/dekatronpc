# Tube count: analysis of the synthesis report and how to reach the budget (now ≤ 1200)

Date: 2026-10-06. Covers the Yosys netlists of `IpLine`, `ApLine` and `MachineCtrl`
(`rtl/run/run_tests.sh -s`, `rtl/run/synt_dpc.tcl`, `rtl/vtube/vtube_cells.lib`
with the uncommitted renames `NOT_N16`, `A1OOI_N16J2`, `A2OOI_J2`).
§1–§7 are the original analysis (no RTL or flow file was changed then; all experiments
ran on scratch copies). §8–§14 record what was implemented afterwards.

## Status (updated 2026-10-07)

Library with 7-tube triggers, `synt_dpc.tcl` with the area ABC script (`-J 50`),
`equiv_opt` and `qn_absorb.py`; `run_tests.sh -s` set (IpLine + ApLine + MachineCtrl,
counters included, memory/reset relay/panel excluded):

| Step | Section | IpLine | ApLine | MachineCtrl | Total | Δ |
|---|---|---|---|---|---|---|
| Old flow, new library (baseline) | §8 | 998.5 | 1065.5 | 572 | 2636 | – |
| Area ABC script + `QN` pins (R6) | §8 | 876 | 989 | 471.5 | 2336.5 | −299.5 |
| RX handshake, `rx_q` removed | §9 | 874.5 | 874 | 493.5 | 2242 | −94.5 |
| ApLine FSM rewrite | §10 | 874.5 | 719 | 493.5 | 2087 | −155 |
| IpLine FSM rewrite (R1) | §11 | 722 | 714 | 512 | 1948 | −139 * |
| MachineCtrl FSM rewrite (R2) | §12 | 722 | 714 | 284.5 | 1720.5 | −227.5 |
| COUT from the Data counter (R7) | §13 | 711 | 679.5 | 282 | 1672.5 | −48 * |
| Decode once (R3), no `insn_q` (R4) | §14 | 652 | 676 | 250 | 1578 | −94.5 * |
| Relays for panel switches, + 5 relays (REQ-MOD-011) | §15 | 661.5 | 684 | 250 | 1595.5 | +17.5 † |
| Prefetch P3, opcode latch back in MachineCtrl (REQ-PERF-003) | §16 | **663.8** | **684** ‡ | **318.7** | **≈ 1666.5** | +71 |
| Binary FSM encoding in DekatronCounter, IpLine, ApLine (T1) | §17.6 | **517.5** | **599** | **334** | **1450.5** (mean of 3 seeds ≈ 1437) | −219 § |

Δ is the change of the total. Each step re-ran ABC, which moves a block whose RTL
didn't change by up to ±30 tubes, so the RTL effect alone (old and new RTL synthesized
in the same run) differs for the rows marked \*: IpLine rewrite −180, R7 −37, R3+R4 −97.
† IpLine and ApLine didn't change in §15; today's run of the same RTL gives 661.5–662.5 /
681.5–684, with or without the relay cell in the library, so +17.5 is ABC drift, not the
relays. The relays' own effect on MachineCtrl is about −4.5 tubes on average over 7 ABC
seeds (§15); the default seed happens to give 250 both ways. Relays are counted separately
and are not tubes: the three blocks are now **1595.5 tubes + 5 relays (2CO)**.
‡ ApLine wasn't resynthesized for §16 (its RTL didn't change). IpLine and MachineCtrl are
means over 3 `&deepsyn` seeds (§16). After P3 the three blocks are about **1666.5 tubes +
5 relays**.
§ T1 row: default seed; Δ is the mean over 3 seeds against HEAD before T1 (≈ 1656 → ≈ 1437, §17.2).
After T1 the three blocks are **1450.5 tubes + 5 relays** (default seed), 64 triggers.

Overall: **2636 → 1578 (−1058, −40 %)** for the three blocks. Of the §5 ideas, R1, R2,
R3, R4, R6 and R7 are done, R8 and R9 were rejected by the owner, R5 and R11 are open,
R10 is not recommended. The open items are worth about 10–30 tubes.

**New goal (2026-10-07, owner):** the whole machine must fit in **1200 tubes**
(REQ-MOD-009, was 1500). The three blocks alone are 1578, 378 (24 %) over that,
before memory support, the reset relay and the panel are counted. FSM cleanup is
used up; see §6 for what's next.

**Second attempt (2026-10-08, §17):** binary state encoding (measured −219, **done**, §17.6), diode codecs under REQ-AUTH-002 (≈ −150…−170) and latches for the counter
carry flags (≈ −70…−84) would take the three blocks from ≈ 1656 to ≈ 1170–1200.
T1 is in the RTL; T2–T9 are open, the questions for the owner are in §17.5.

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
scope (see §7, Q1; answered in §8: the whole machine).

## 2. Findings in the flow and the library

All four are resolved (§8).

1. **Fixed (§8).** **`fsm -encoding onehot` in `synt_dpc.tcl` is a no-op.** It runs after `synth`,
   which has already done FSM extraction. Measured: an explicit binary pass gives the
   same 2138.5, and `synth -nofsm` gives 2165 (+27). FSM encoding is not a lever.
   The pass was removed.
   **Correction (2026-10-08, §17):** the binary pass also ran after `synth`, so it was a
   no-op too and the encoding was never measured. Set through the `fsm_encoding`
   attribute *before* `synth`, binary encoding saves about 219 tubes (§17.2).
2. **Fixed (§8).** **ABC maps for delay, not area.** `abc -liberty` with the default script is
   delay-oriented. In tubes only area matters (1 MHz is slow for a gate).
   `rtl/run/abc_area.abc` is now used.
3. **Fixed by the owner (§8).** **`DFF` has `heat_current: 8500`**, ten times `DFFSR`/`DFFSR_n` (850). This
   looks like a typo. It adds 204 A of the 813 A in the heat-current total (about
   1.3 kW of the 5.1 kW estimate). It does not affect the tube count.
   All three trigger cells now have area 7 and `heat_current: 2000`.
4. **Fixed (§8, R6).** 51 of the 161 inverters (25 tubes) only invert a flop output. A tube trigger
   (Eccles–Jordan) has both anodes, so Q̄ is free physically. The library DFF cells
   expose only `Q`. The cells now have `QN`, and `qn_absorb.py` moves the inverters to it.

## 3. Measured: synthesis-only changes (no RTL change)

**Adopted in §8** as `rtl/run/abc_area.abc`: script G with `&deepsyn -J 50 -T 30`, which
runs in seconds instead of minutes, plus the `equiv_opt` check asked for below.

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

**Implemented in §9 (`rx_q`) and §10 (FSM, Moore strobes).** The held-level `mem_valid`
question below is answered in §10.

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

| # | Idea | Est. Δ | Changes a rule or requirement? | Status, measured Δ |
|---|---|---|---|---|
| R1 | Same FSM cleanup in **IpLine**: merge `IP_OP/IP_WAIT`, `LOOP_OP/LOOP_WAIT`, `CLR_OP/CLR_WAIT`; decode `ip_valid`, `loop_valid`, `ip_set_zero`, `loop_set_zero`, `mem_valid`, `mem_wr` from state; `clr_is_loop_q` becomes two states | −100 … −130 | no | **Done, §11** (REQ-IPV2-007). IpLine 902 → 722, **−180**; triggers 51 → 40 |
| R2 | Same in **MachineCtrl**: merge `FETCH/FETCH_W`, `IP_OP/IP_OP_W`, `AP_OP/AP_OP_W`, `COUT`/`ECHO`; decode `ip_valid`, `ap_valid`, `tx_vld`, `*_rst_req` from state; remove the unreachable `S_BELL` (nothing enters it) | −80 … −110 | no | **Done, §12** (REQ-CTLV2-010). MachineCtrl 512 → 284.5, **−227.5**; triggers 25 → 9. Includes the register-free op decode (first half of R3) and the bell/echo/reset-type cleanup |
| R3 | **Decode once.** Pass `{insn_mode, insn}` to ApLine and IpLine as the op, instead of re-encoding it to `ap_op[3:0]`/`ap_dec`/`ip_op[1:0]`. This drops 7 registers and the encoder in MachineCtrl. CIN/TEST become ApLine's own sub-ops | −30 … −50 | internal interface only (ApLine/IpLine op codes) | **Done, §12 + §14** (REQ-APV2-008). The 7 registers went in §12; the encoder and op ports in §14: MachineCtrl 282 → 250 (−32), ApLine +0.5 |
| R4 | Drop `insn_q` in IpLine: the program memory's output register already holds the last opcode (same as the data memory's write-through register). Loading mode can take `insn_in` straight away | −15 … −20 | check IpMemory rd_data hold semantics | **Done, §14** (REQ-IPV2-008). `Ram` hold semantics checked; EOT reported by a 1-bit `insn_eot` (owner). IpLine 717.5 → 652, **−65.5** (two states removed as well) |
| R5 | Panel edge detection (`key_moved_q`, the `one_step` release logic) done once, in the panel or MachineCtrl, not duplicated in IpLine | −10 … −20 | no | **Open.** After R1/R2 there is one flop on each side: `key_moved_q` (±IP keys) in IpLine and `one_step` (Step key) in MachineCtrl. They watch different keys, so merging them saves at most one trigger plus its logic (≈ −10) |
| R6 | `QN` pin on `DFF`/`DFFSR_n` in the liberty, plus a post-map pass that replaces `NOT(Q)` with `QN` | −20 … −25 | library only; confirm the tube trigger really gives Q̄ for free | **Done, §8** (REQ-MOD-010). The owner confirmed `QN` is free. `qn_absorb.py` replaced 19 inverters in IpLine and 8 in ApLine (2026-10-06 logs, counters included), ≈ −13.5 tubes at 0.5 per `NOT_N16`. Not measured on its own: §8 reports it together with the ABC script |
| R7 | COUT always from the Data counter: if the cell isn't locked, LOAD it first. That removes the 10-bit `tx_data_bcd` mux. It costs one write window per `.`, which is negligible at 110 baud | −20 … −30 | changes the ApLine COUT path (lazy read stays for TEST) | **Done, §13** (OPEN-017 closed). ApLine −34.5, MachineCtrl −2.5, **−37**. Also fixed `Hello WWrld!!` |
| R8 | Shared counter control: only one counter steps at a time (asserted in IpLine and MachineCtrl), so the four `writeTimer`/`Impulse`/`DekatronPhaseGen`/3-bit FSM sets can become one or two | −40 … −80 | yes: §5 "one phase generator per counter", counter as a self-contained Valid/Ready unit | **Rejected** by the owner (§8, decision 4) |
| R9 | Address memories with dekatron cathodes one-hot (10 lines per decade) instead of BCD: drops BinToBcd on IP and AP (exactly −90) **and** the BCD→1-of-10 decoders on the memory side, which aren't counted today | −90 (+ memory) | yes: §3 "addresses are raw BCD tetrads"; 50 address wires instead of 20 | **Rejected** by the owner (§8, decision 4) |
| R10 | Use the Data counter as the nesting counter during a scan (flush first): removes the Loop counter (74.5 tubes + 2 dekatrons) | −75 | yes: REQ-CNT-002/007 overflow semantics, IpLine/ApLine coupling | **Not recommended**, not pursued |
| R11 | Flatten MachineCtrl+IpLine+ApLine for synthesis (keep counters and DekatronModule as instances) so constant ops propagate across the boundary | unknown | no | **Open.** The first attempt failed to set up: SYNTH stubs of RstTimeRelay/memories fold the netlist to constants. After R3 the ops cross the boundary as raw `{insn_mode, insn}`, so little is left to propagate |

Also done, outside this list: the area ABC script with `equiv_opt` (§8), `rx_q` removed
with the RX handshake (§9, REQ-UART-008) and the ApLine FSM rewrite (§10, REQ-APV2-007).

## 6. Path to ≤ 1500

### Original plan (2026-10-06, old library with 3.5-tube triggers)

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

That plan assumed the 1500 budget covered only these three blocks, and 3.5-tube
triggers. Both assumptions changed in §8: the budget is for the whole machine
(REQ-MOD-009) and a trigger costs 7 tubes.

Order of work as planned, all done:
1. ~~ABC script G in `synt_dpc.tcl` + an equivalence check step.~~ §8.
2. ~~ApLine rewrite, new ApLine test.~~ §9, §10 (Icarus `ApLine_tb`; there is still no
   cocotb ApLine target).
3. ~~IpLine, then MachineCtrl, each with its own test first.~~ §11, §12.
4. ~~R3, then R6.~~ R6 in §8, R3 in §12/§14, plus R4 (§14) and R7 (§13).

### Where it stands (2026-10-07, 7-tube triggers)

| | Planned (old library) | Done (new library) |
|---|---|---|
| Start | 2138.5 | 2636 |
| After R1–R3, R6 (+ R4, R7 done) | ≈ 1375 | **1578** |
| Reduction | ≈ −36 % | **−40 %** |

The relative reduction beat the plan, but the three blocks alone are still 78 over a
budget that must also cover memory support, `RstTimeRelay` and the panel (and possibly
the dekatrons, still to be clarified in REQ-MOD-009). The ideas left in §5 (R5, R11)
are worth about 10–30 tubes.

What remains in the three blocks: 35 glue triggers (IpLine 17, ApLine 9, MachineCtrl 9,
§14), about 245 tubes, plus the four counters with their codecs and phase generators.
Further reduction therefore needs a new direction, not more FSM hygiene. §8 named one:
move state and flags into dekatron-driven sequencing. R8/R9 would have touched the
counters, but the owner rejected them.

### Next goal: 1200 for the whole machine (owner, 2026-10-07)

REQ-MOD-009 is lowered from 1500 to 1200. Against that target:
- the three blocks must lose at least 378 tubes even if nothing else counted;
- memory support, `RstTimeRelay` and the panel aren't in the synthesis count yet, so
  the real gap is larger. Counting them is the first step (TRS §22 item 10);
- whether the dekatrons count toward the budget is still open (REQ-MOD-009).

## 7. Questions for the owner

All six were answered on 2026-10-06; the decisions are in §8.

1. What does the 1500 budget cover: only the logic counted today (IpLine/ApLine/
   MachineCtrl incl. counter glue), or also memory support, reset relay and panel?
   Should it become a REQ in the TRS?
   → **The whole machine**, REQ-MOD-009. Whether the dekatrons count is still open (TRS).
2. OK to switch `synt_dpc.tcl` to the deepsyn ABC script (2.5 min instead of 3 s)
   and add an equivalence check?
   → Yes. Done in §8 with `-J 50` (about 25 s for the three blocks) and `equiv_opt`.
3. Can the terminal side hold `rx_data_bcd` until CIN completes, so ApLine drops
   `rx_q`? The signal stays, but its timing contract (TRS Appendix B) changes.
   → Yes, through a Valid/Ready handshake with a new `rx_rdy` port. Done in §9 (REQ-UART-008).
4. R8 (shared counter control) and R9 (one-hot memory address): worth pursuing, or
   do the §3/§5 rules stand?
   → Not applicable; the rules stand.
5. Does the tube trigger really give Q̄ without extra tubes (R6)?
   → Yes (REQ-MOD-010). Done in §8.
6. Is `DFF heat_current: 8500` a typo for 850?
   → The owner revised all trigger cells: area 7, `heat_current: 2000`.

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

Projection to 1500 for the whole machine (written before §9–§14; the actual result,
1578 for the three blocks, is in §6 and the status table at the top): the measured ApLine cleanup removes 13
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

## 10. Done: ApLine FSM rewrite (§4, REQ-APV2-007)

The §4 prototype, now in `rtl/DekatronPC/ApLine.sv` (`rx_q` was already removed in §9).

Changes:
- 9 states → 6: `S_IDLE, S_FLUSH, S_READ, S_AP, S_DSET, S_DOP`. The WAIT states
  (`S_AP_WAIT`, `S_DATA_SET_W`, `S_DATA_WAIT`) are gone.
- The 7 registered strobes are decoded from `state` (Moore):
  `ap_valid = S_AP & go`, `data_valid = (S_DSET | S_DOP) & go`,
  `mem_valid = (S_FLUSH | S_READ) & go`, `mem_wr = S_FLUSH`, `data_set = S_DSET`,
  `ap_set_zero = op==AP_ZERO`, `data_set_zero = op==DATA_ZERO`,
  where `go = ap_ready & data_ready & mem_ready`.
- Each non-IDLE state issues one operation when all three slaves are idle and leaves in
  the same cycle (the handshake happens in that cycle, because the slave's own ready is
  part of `go`). The next state, or IDLE's `ready`, waits for `go` again, so it also
  waits for the previous operation to finish. Slaves' `ready` never depends on `valid`,
  so `valid & go` makes no loop.
- End of a memory access = `mem_ready` returning. `Ram` drops `busy` on the same edge
  that `rd_data` becomes valid, and the data then holds until the next access. So
  `mem_rd_valid` is no longer used by ApLine (the port stays).
- `lock`/`dirty` after `+ - CLRD` are set when `S_DOP` hands the operation to the
  counter (the old code set them one state later). Nothing can observe the
  difference: `ready` stays low until the counter is done.
- External behaviour is unchanged, including the known v0.9 divergence (a clean AP
  step does not clear `lock`, TRS §22 item 8; the fix is not applied).

The held-level `mem_valid` question from §4 is settled by the design: `mem_valid` only rises
together with `mem_ready`, so a held request can't be accepted twice. The old FSM had
two flaws here. On the first access after reset it re-raised `mem_valid` while the
memory was busy (the RAM ignored it). On every later access it took the **stale**
`rd_valid` of the previous access, which stays 1 until the next accept, as the end
of the read in the accept cycle. It worked only because IDLE's `ready` also waits
for `mem_ready`, and the counter write window outlasts the one-cycle read.

Verification (Icarus, `rtl/run/emul ApLine`):
- `ApLine_tb` was extended with STORE, CLRML (twice: dirty and clean), CLRA with a
  dirty cell, the 255 ↔ 0 wrap, memory access counts (20 AP steps → 0 accesses,
  STORE → 1 write, a clean AP step → no write, CLRML → 1 write, TEST/COUT after a
  flush → no read), and a monitor that flags `mem_valid` without `mem_ready`.
- New ApLine: PASS, 485 µs (the old FSM with the extended test: 575 µs and 1 error,
  the monitor on the first access after reset; every functional check passes on
  both).
- `DekatronPC` hello test passes (it only checks IP moving). Verilator `--lint-only -Wall`
  is clean for DekatronPC.
- `-DASSERTIONS` does not build on Icarus (syntax in `DekatronTubeV2_assertions.sv`,
  unrelated), so the ApLine assertions did not run. The tb monitor covers the
  handshake part.
- Not run: the full `run_tests.sh -t`, the Verilator DekatronPC builds and the cocotb
  regression (heavy, AGENTS §0). The cocotb regression has no ApLine target.

Synthesis (`./synth ApLine`, `-J 50`; `equiv_opt` found no problems):

| Block | before (§9) | now | Δ |
|---|---|---|---|
| ApLine | 874 | **719** | **−155** |
| Total (IpLine + ApLine + MachineCtrl) | 2242 | **2087** | −155 |

The ApLine netlist has 32 triggers (18 `DFFSR_n` + 14 `DFF`, counters included).
Block diagram: sheet 5 (`05_2_apline_fsm.svg`) was redrawn with the new states.

## 11. Done: IpLine FSM rewrite (R1, REQ-IPV2-007)

The §4 method applied to `rtl/DekatronPC/IpLine.sv` (item R1 of §5).

Changes:
- 12 states → 11: `S_IDLE, S_IP, S_FETCH, S_FETCH_W, S_SCAN_EVAL, S_LOOP, S_INSN_IN,
  S_WRITE, S_CLR_IP, S_CLR_LOOP, S_HALT`. The pairs `IP_OP/IP_WAIT`, `LOOP_OP/LOOP_WAIT`
  and `CLR_OP/CLR_WAIT` are gone. `clr_is_loop_q` became two states. `S_FETCH_W` is new
  and is the only waiting state: `insn_q` has to latch `rd_data`, and that is valid only
  when the read ends.
- The 8 registered strobes are decoded from `state` (Moore), with
  `go = ip_ready & loop_ready & mem_ready`:
  `ip_valid = (S_IP & ~scan_done | S_CLR_IP) & go`, `loop_valid = (S_LOOP | S_CLR_LOOP) & go`,
  `mem_valid = (S_FETCH | S_WRITE) & go`, `mem_wr = S_WRITE`, `ip_set_zero = S_CLR_IP`,
  `loop_set_zero = S_CLR_LOOP`.
- `ip_dec` and `scan_dec_q` are merged into one `dir_q` (direction of the next IP step:
  scan direction or the ±IP key). `loop_dec = dir_q ? insn_loop_open : insn_loop_close`,
  taken from `insn_q`. `loop_init_q` is gone: on the starting bracket the opposite
  bracket detector is 0, so the first step is an increment by itself.
- End of scan: `S_LOOP` leaves on issue, so the zero check moved to `S_IP`. When
  `scanning_q & loop_is_zero` holds there (after `go`, so the loop step is done), the
  pair is found and the FSM returns to `S_IDLE` without stepping. During a scan the
  nesting counter is 0 only at that moment: the start and own brackets increment it,
  and overflow is caught before the step.
- `mem_wr_data = insn_q` instead of the live `insn_in`. The loader may change `insn_in`
  right after the `insn_in_valid & insn_in_ready` handshake, and `DekatronPC_tb` does.
  The old FSM wrote one cycle after the handshake and took the next opcode. That was found
  by reading the code; it wasn't simulated on the old RTL.
- `halt_pending_q` is now cleared by `soft_rst | hard_rst` too. Before, a reset during
  the halt step left it set, and the next IP step went to `S_HALT` with `halt_rq` low.
- `mem_rd_valid` is no longer used (the port stays, as in ApLine).

Defect of the old FSM, found by the new testbench: it latched `insn_q` in the cycle the
memory **accepted** the read, using the stale `rd_valid` of the previous access (the
same flaw §10 describes for the old ApLine, but here it loses data). With a memory that
follows the `Ram` discipline, every fetch returned the opcode of the previous fetch
(the first one after `rst_n` returned the reset value 0). The old `IpLine_tb` didn't see
this because its memory was combinational and always ready. The DekatronPC test checks
only that IP moves (TRS §22 item 5), so it didn't see it either.

Verification (Icarus, `rtl/run/emul IpLine ../programs/looptest.bfk`):
- `IpLine_tb` rewritten. The test memory now follows `Ram`: `ready = ~busy`, 2 busy
  cycles, `rd_data` is X until `ready` returns, write-through. The test has six parts:
  1. looptest (back scan);
  2. loading a 23-opcode program with nesting depth 3 over `insn_in` (EOT is shown on
     `insn` and not written; `insn_in` changes right after each handshake). Then 400
     fetches with random `loop_val_zero` (131 scans, forward and back), each compared to
     a reference model (address and opcode), with the nesting counter 0 after each
     fetch (REQ-IPV2-003);
  3. overflow: 120 × `[`, the scan stops at IP 99 with the counter at 99, a repeated
     NEXT doesn't move, CLRL clears both (REQ-CNT-007, REQ-IPV2-004);
  4. CLRI: `insn_valid` drops, and the next fetch reads address 0 without a step;
  5. halt: IP+1, `ready` and `insn_valid` low, ±IP keys, after release the fetch reads
     in place;
  6. hard reset: IP = 99900.

  Monitors: `mem_valid` without `mem_ready`, `ip_valid & loop_valid`, X on `insn` at ready.
- New IpLine: PASS, 9259 µs simulated, 1.6 s wall time. Old IpLine on the same test:
  hangs in part 1 (stale opcodes).
- Verilator `--lint-only -Wall` is clean for DekatronPC. The DekatronPC hello test
  (Icarus) passes, but it checks only that IP moves.
- Not run: the full `run_tests.sh -t`, the Verilator DekatronPC builds and the cocotb
  regression (heavy, AGENTS §0).

Synthesis (`./synth IpLine`, `-J 50`; `equiv_opt`: 129/129 `$equiv` cells proven). The
old IpLine was synthesized with the same flow from a scratch copy:

| | old | new | Δ |
|---|---|---|---|
| IpLine, tubes | 902 | **722** | **−180** |
| Triggers (counters included) | 51 | 40 | −11 |

The `−180` compares two runs made today with the same flow. Against the §9 figure
(874.5, same RTL as "old") it is −152.5; the 27.5 gap is ABC variance.

The three blocks from today's netlists: IpLine 722 + ApLine 714 + MachineCtrl 512 =
**1948**. ApLine and MachineCtrl RTL didn't change since §10; their figures (719 and
493.5 then) moved with ABC variance.

Block diagram: sheet 4 (`04_1_ipline.svg`, `04_2_ipline_fsm.svg`) redrawn. No SVG
renderer was available, so the layout was checked by coordinates only.

## 12. Done: MachineCtrl FSM rewrite (R2, REQ-CTLV2-010)

The §4 method applied to `rtl/DekatronPC/MachineCtrl.sv` (item R2 of §5). The external
interface and the op codes sent to IpLine/ApLine are unchanged.

Changes:
- 15 states → 10: `S_HALT, S_IDLE, S_FETCH_W, S_DECODE, S_EXEC, S_WAIT, S_COUT, S_CIN_WAIT,
  S_RST_REQ, S_RST_WAIT`. `S_IDLE` issues the fetch itself (old `S_IDLE` + `S_FETCH`).
  `S_IP_OP`/`S_AP_OP` became one `S_EXEC`, and the two `_W` states one `S_WAIT`. `S_ECHO` is
  gone (echo goes through `S_COUT`), and so is the unreachable `S_BELL`. The codes of `S_HALT`,
  `S_IDLE`, `S_DECODE` and `S_CIN_WAIT` are kept, because `DekatronPC_tb.cpp` uses them.
- Moore strobes, with `go = ip_ready & ap_ready & ~(soft_rst | hard_rst)`:
  `ip_valid = (S_IDLE & ~halt_key | S_EXEC & is_ip_op) & go`,
  `ap_valid = (S_EXEC & ~is_ip_op | S_CIN_WAIT & ~halt_key & rx_vld) & go`,
  `tx_vld = S_COUT`, `rx_rdy = S_WAIT & is_cin & go`, `*_rst_req = S_RST_REQ & type`.
- **Decode once, without registers.** `ip_op`, `ap_op` and `ap_dec` are combinational from
  `{insn_mode, insn}`. IpLine holds `insn` in `insn_q` until the next fetch, and the next fetch
  waits for `go`, so the op codes stay stable until the slave's `ready`, as Valid/Ready
  requires. This removes 7 registers while keeping ApLine's and IpLine's op encoding (the
  rest of R3 is still open). `ap_dec = insn[0]` also feeds non-step ops; `DekatronCounter`
  ignores `dec` when `set`/`set_zero` is active.
- `echo_pending` removed: `S_WAIT` goes to `S_COUT` when the finished op was CIN (`is_cin`
  from `insn`) and `echo_mode` is on.
- `bell` is a pulse in the cycle of the event (HALT opcode, BELL, CIN, `halt_key` in
  `S_IDLE`, overflow). `bell_pending` and the `bell` register are gone. `Bell` isn't connected
  in `Emulator.sv`.
- `rst_type` (2 bits) → `rst_soft` (1 bit). `RunOnHardRst`/`RunOnSoftRst` act when
  `S_RST_WAIT` ends: it goes straight to `S_IDLE`, not through `S_HALT`, so `RST_NONE` isn't
  needed. On power-up the relay always gives a hard reset, so `run_on_hard_rst` still works
  after `rst_n`.
- **Overflow halts (REQ-CTLV2-005).** `overflow_hit = loop_overflow & ~overflow_q`
  (`overflow_q` is last cycle's `loop_overflow`) takes priority over the whole `case`. The old
  code had two defects. `state <= S_HALT` came before `case (state)`, and the `S_FETCH_W` branch
  overrode it (`doc/dpcrun_golden_model.md` §5.2). Also, CLRL cleared `error_flag` in
  `S_DECODE`, but IpLine drops `overflow_q` only when it accepts CLR_LOOP. In between,
  `error_flag` was set again, and the next overflow didn't halt either. The edge detector has
  no clear, so neither problem can occur.
- Flops: 25 → 9 (`state` 4, `insn_mode`, `insn_loading`, `one_step`, `overflow_q`, `rst_soft`;
  `iret` only with `EN_EMULATOR`).
- One clock less per instruction (the old `S_FETCH`): a NOP takes 7 clocks instead of 8.

Not changed, by owner decision: COUT. `.` still raises `tx_vld` without `AP_COUT` (OPEN-017).
The simulation below printed `Hello WWrld!!` with **both** FSMs, as
`doc/dpcrun_golden_model.md` §5.1 predicts. The cause is the stale memory register after `>`:
ApLine's `S_AP` clears `mem_here_q` without reading, and `Ram` updates `rd_q` only when it
accepts an access (`RAM.sv:109-121`). So, with `lock_q = 0`, `tx_data_bcd = cell_from_mem` is the
previous cell. The owner then chose to print always from the Data counter; see §13.

Verification:
- New `rtl/tests/MachineCtrl.sv/MachineCtrl_tb.sv` (`rtl/run/emul MachineCtrl`, added to
  `run_tests.sh -t`). It uses models of IpLine (opcodes from a queue), ApLine (busy 1–4 random
  cycles, checks that `ap_op`/`ap_dec` stay stable until `ready`), the time relay and the terminal.
  Parts:
  1. all 32 `{insn_mode, insn}`: which op goes to which slave, `dec`, bell, ISA switch, HALT
     with `bell_on_halt`; `loop_val_zero` source;
  2. TEST before a bracket only in BF and only when `data_zero_valid` is low;
  3. CIN with and without echo, `bell_on_cin`, `halt_key` while waiting;
  4. loading: nothing runs, ISA1 inside makes 0x4 a `>`, EOT with and without `SoftRstOnEOT` +
     `RunOnSoftRst`, panel load start/stop keys;
  5. HRST/SRST with `RunOn*` 0/1, panel hard reset during CIN, panel soft reset during loading;
  6. overflow: halt, bell, the bracket is not decoded, Run does not halt again, after CLRL a new
     overflow halts again;
  7. halt key, step: one instruction per press while the key is held.

  Monitors: `ip_valid`/`ap_valid` without `ready`, both at once, `rx_rdy` before CIN ends or
  without `rx_vld`, both reset requests at once.
  New FSM: PASS. Old FSM, same tb (it doesn't depend on state codes): 6 errors, all in part 6
  (the two overflow defects above). Every other check passes on both.
- `DekatronPC_tb` (Icarus) with the existing `TRY_PROGRAM` scenario, in a scratch copy: the
  bootloader starts, helloworld is loaded over `InsnIn`, EOT gives a soft reset, `RunOnSoftRst`
  runs the program. TX characters and IP at each character are identical for the old and new
  FSM (`Hello WWrld!!`). Both halt at IP 113. The new FSM is about 8 % faster between the first
  and last character (14.06 ms vs 15.36 ms of simulated time).
  The scenario isn't usable as checked in, and that was the case before this change:
  - `generate_rom.py` output has no leading ISA1, so in Debug ISA the first `>` (0x4) is EOT
    and only `++++++++++[` is loaded;
  - `@(posedge IsHalted)` caught the old FSM's one-cycle pass through `S_HALT` after the soft
    reset, before the program ran;
  - the tb's final TX compare never completes (it isn't enabled by any cfg).

  For the run, the scratch copy prepended `0xF` and waited for the TX count before waiting
  for HALT.
- Verilator `--lint-only -Wall` is clean for DekatronPC. `./emul DekatronPC` (hello cfg) passes.
- Not run: the Verilator golden-model builds (`run_tests.sh -s`, heavy) and the cocotb
  regression (it has no MachineCtrl target).

Synthesis (`./synth MachineCtrl`, `-J 50`, 6 s; `equiv_opt`: 62/62 `$equiv` cells proven):

| | old (§11 netlist) | new | Δ |
|---|---|---|---|
| MachineCtrl, tubes | 512 | **284.5** | **−227.5** |
| Triggers | 25 | 9 | −16 |

R2 was estimated at −80…−110 (§5). The extra came from decoding the op codes from `insn`
(part of R3) and from the cleanup of the bell, echo and reset-type flags.

The three blocks: IpLine 722 + ApLine 714 + MachineCtrl 284.5 = **1720.5** (the
2026-10-06 baseline was 2636 with the same library).

Block diagram: sheet 6 (`06_*`) redrawn.

## 13. Done: COUT always from the Data counter (R7, OPEN-017)

Owner's decision after §12: drop the `tx_data_bcd = lock ? data_out : cell_from_mem` mux
and always print the Data counter. If MemLock is off, load the cell into the counter first.

Changes:
- `ApLine`: `tx_data_bcd = data_out`. `OP_COUT` in `S_IDLE`: with `lock_q` nothing to do.
  Otherwise go to `S_DSET` if `mem_here_q`, else `S_READ` → `S_DSET`. `S_READ` now
  goes to `S_DSET` for everything except `OP_TEST`. MemLock and `dirty` don't change, as with
  LOAD. Setting `lock` here would hit the known v0.9 divergence (a clean AP step doesn't
  clear `lock`), and the next `.` after `>` would print the old cell again.
- `MachineCtrl`: `.` (`5'h18`) goes to `S_EXEC` with `ap_op = AP_COUT`. `S_WAIT` goes
  to `S_COUT` for COUT, or for CIN with echo. `tx_vld` therefore rises only when ApLine is
  done, and the counter doesn't change while `tx_vld` is high.
- Cost: one counter write window per `.` when MemLock is off. At 110 baud it doesn't matter.
  Memory reads are the same as before: a read only when the register isn't on the
  current cell.

Verification:
- `ApLine_tb`: new part "COUT after an AP step without MemLock". A `<` with the counter holding
  cell 1 must make COUT read cell 0 (1 read, value 124). Back to cell 1: 1 read, value 1. A
  second COUT: no read. MemLock stays off. New ApLine: PASS. The old ApLine also passes this
  part: its `OP_COUT` already read the cell. The defect was only that MachineCtrl never
  issued it.
- `MachineCtrl_tb`: `.` must issue exactly one `AP_COUT` and one TX. A new monitor fails on
  `tx_vld` while ApLine is busy. PASS.
- `DekatronPC_tb` (`TRY_PROGRAM`, the scratch copy from §12): helloworld through the
  bootloader now prints **`Hello World!\n`** (13 characters), and halts at IP 113.
- Verilator `--lint-only -Wall` is clean for DekatronPC.
- Not run: `run_tests.sh -s` (golden-model comparison). The dpcrun golden model was changed to
  match: COUT without MemLock loads the cell into the counter, and `txData()` is the counter
  (`doc/dpcrun_golden_model.md` §5.1). bfutils unit tests: 55 tests, 482 checks pass.

Synthesis (`-J 50`, `equiv_opt` proven: ApLine 127/127, MachineCtrl 62/62):

| Block | §12 | now | Δ |
|---|---|---|---|
| ApLine | 714 | **679.5** | −34.5 |
| MachineCtrl | 284.5 | 282 | −2.5 |
| IpLine (RTL unchanged, netlist on disk) | 722 | 711 | ABC variance |
| Total | 1720.5 | **1672.5** | |

R7 was estimated at −20…−30.

Block diagrams: sheets 5 and 6 redrawn. The dashed "COUT: immediately tx_vld" edge and the
OPEN-017 note are gone.

## 14. Done: decode once (R3) and the opcode held by memory (R4)

Items R3 and R4 of §5. §12 had already decoded the op codes from `insn` without
registers. This step removes the op codes themselves, and the opcode register in
IpLine.

### R3: the instruction is the op code (REQ-APV2-008)

- `ApLine.op` is now `{insn_mode, insn}` (5 bits), wired in `DekatronPC` straight from
  `insn_mode` and `Insn`. ApLine decodes it itself: `0x0A`/`0x1A` zero data, `0x0B` zero
  AP, `0x12`/`0x13` step data, `0x14`/`0x15` step AP, `0x16`/`0x17` TEST, `0x18` COUT,
  `0x19` CIN, `0x1B` CLRML, `0x1C` LOAD, `0x1D` STORE. Other codes are NOP (MachineCtrl
  doesn't issue them). The step direction is `op[0]`, so the `dec` port is gone.
- The `ap_op` encoder, `ap_op[3:0]` and `ap_dec` are gone from MachineCtrl.
- IpLine gets one bit, `clr` (MachineCtrl's `ip_clr = S_EXEC`), instead of `ip_op[1:0]`.
  With `clr`, IpLine picks CLRI or CLRL from `insn[0]` of its own opcode.
- The decode is exact (no don't-cares on unused codes), per the "no X-masking" rule.

### R4: no `insn_q` in IpLine (REQ-IPV2-008)

The precondition from §5 was checked in `RAM.sv`. `Ram.rd_data` changes only when an
access is accepted: the bank's `rd_q` and the group's `digit_q` load on `bank_en`, and
`ovl_hit_q`/`ovl_data_q` load on `accept`. IP steps, CLRI and halt don't touch memory, and
IpLine starts the next access only after MachineCtrl has finished with the current
instruction (`ready` needs `go`). So `insn = mem_rd_data` holds while MachineCtrl
decodes and ApLine executes. The ferrite memory behaves the same way: the value stays in
the sense amplifiers until the next access.

EOT isn't stored in memory (neither RTL nor `dpcrun` writes it), so the register can't
show it. Two options were put to the owner: a 1-bit flag, or writing EOT to memory as well
(which changes the loaded image and `dpcrun`). **The owner chose the flag.** `eot_q` is set
when S_INSN_IN accepts EOT, cleared by the next accepted operation and by the reset lines.
It goes to MachineCtrl as `insn_eot`. In loading mode MachineCtrl checks `insn_eot` first,
then ISA0/ISA1 from `insn`. After write-through, `insn` holds the opcode that was just
written.

Loading writes the opcode in the handshake cycle. `insn_in_ready = S_INSN_IN & insn_loading & go`
(free memory, doesn't depend on `insn_in_valid`). `mem_valid` also covers
`insn_in_valid & insn_in_ready & ~EOT`, and `mem_wr_data = insn_in`. This is the one Mealy
strobe in IpLine: valid follows the loader's valid, while ready still doesn't depend on
valid. The loader already holds `insn_in` until the handshake.

States 11 → 9:
- `S_WRITE` is gone. S_INSN_IN goes to S_IDLE on the handshake, and S_IDLE's `ready`
  waits for the write to finish.
- `S_FETCH_W` only existed to latch `insn_q`, so it is gone too. S_FETCH goes to S_IDLE
  (or S_SCAN_EVAL while scanning) when the read is issued. S_SCAN_EVAL now waits for
  `go` before it looks at the opcode.

Edge case: a write into the bootloader area is rejected by `Ram` (`err`), and `rd_data`
then shows the ROM opcode, not the one sent. Before, MachineCtrl decoded the opcode as
sent. This only matters for a write that is already an error.

### Verification

- `IpLine_tb`:
  - `clr` replaces `op`. For CLRI/CLRL the tb puts the opcode into the memory model's
    register.
  - `insn` must equal the opcode just written after every load.
  - After EOT, `insn_eot` and `insn_valid` must be set, and the next request must clear
    `insn_eot`.
  - A monitor checks that `insn` doesn't change while the memory is idle. This checks the
    memory model's discipline, the precondition R4 relies on.
  - The loader raises `insn_in_valid` before `insn_in_ready`.
  - PASS. `looptest` part 1 runs about 13 % faster (8038 µs vs 9259 µs for the whole tb).
- `ApLine_tb`: op names map to opcodes. Added: Debug CLRD `0x0A` next to BF `[-]` `0x1A`,
  and `]` as TEST. PASS.
- `MachineCtrl_tb`:
  - The IpLine model now behaves like the RTL. EOT during loading doesn't change `insn`
    and raises `insn_eot`.
  - The ApLine model checks that `{insn_mode, insn}` stays stable until `ap_ready` and
    that only data ops reach ApLine.
  - A new monitor fails on `ip_clr` with anything but CLRL/CLRI.
  - PASS.
- Mutations:
  - IpLine never sets `eot_q`: `IpLine_tb` fails ("EOT not reported").
  - MachineCtrl decodes EOT from `insn` the old way: `MachineCtrl_tb` fails 5 checks.
- `DekatronPC_tb` (Icarus, `run_tests.sh -t` configs): helloworld through the bootloader
  prints `Hello World!\n`, halts at IP 112; `program.bfk` passes.
- Verilator `--lint-only -Wall`: clean for `DekatronPC` and `Emulator`.
- Not run: the Verilator golden-model comparison (`veremul`, full DekatronPC build) and the
  cocotb regression (it has no targets for these blocks).

### Synthesis

HEAD and the new RTL were synthesized the same day with the same flow (`./synth`,
`-J 50`). `equiv_opt` is proven on all six runs (new RTL: IpLine 125/125, ApLine 130/130,
MachineCtrl 57/57).

| Block | HEAD | R3 + R4 | Δ |
|---|---|---|---|
| IpLine | 717.5 | **652** | −65.5 |
| ApLine | 675.5 | 676 | +0.5 |
| MachineCtrl | 282 | **250** | −32 |
| Total | 1675 | **1578** | **−97** |

Triggers in the IpLine glue (counters excluded): 22 → 17. `insn_q` costs −4 and `eot_q`
+1. The other −2 come from the state register, which Yosys extracts and encodes one-hot,
so 11 → 9 states. The MachineCtrl and ApLine glue triggers don't change (9 and 9).

The estimates were R3 −30…−50 and R4 −15…−20. As expected, ApLine pays for the 5-bit
decode about what MachineCtrl's encoder cost. The extra gain comes from the two removed
IpLine states.

Block diagrams: sheets 4, 5, 6 and 7 redrawn (no SVG renderer available; layout checked
by coordinates).

## 15. Done: relays for the panel switches (REQ-MOD-011)

Owner's request (2026-10-07): logic that only a panel switch controls (EN or MUX on a
switch) doesn't need tubes. A relay does the same with no filament. Only 2CO relays
(one coil, two changeover contacts) are used. A relay may only be driven by a user
switch, never by fast or clocked logic. Where a relay saves no tube, the tubes stay.

### Library and modules

- `rtl/vtube/vtube_cells.lib`: cell `RELAY_2CO` (pins `COIL`, `NC1/NO1/C1`, `NC2/NO2/C2`;
  `Cn = COIL ? NOn : NCn`), area 0, `heat_current` 0, group `relays(names) { RELAY_2CO: 1; }`.
  The output pins have **no function**, so ABC never uses the relay as a general mux;
  it only appears where RTL instantiates it. Model in `rtl/vtube/vtube_cells.v`.
- `rtl/Logic/Relay.sv` (added to `DPC.files` and `Emulator.qsf`):
  - `RELAY_2CO` behavioral model under `ifndef SYNTH` (in synthesis the liberty cell is used);
  - `RelayMux #(W, S)`: 2^S words of W bits, selected by S switches. A tree of changeover
    contacts, select bit l switches 2^(S−1−l)·W contacts, two per relay:
    relays = Σ_l ⌈2^(S−1−l)·W / 2⌉;
  - `RelayEn #(W)`: `y = en ? a : 0`, NC contacts tied to 0; relays = ⌈W / 2⌉.
  - Both have `(* keep_hierarchy = "yes" *)`, so `synth -top` doesn't flatten them.
  - Each tree level is its own vector. One array for all levels was a false loop for
    Verilator (UNOPTFLAT), fixed structurally (AGENTS.md §5).
- `rtl/run/dpc_stat.py`: prints a `Relays` column per block and the total. The cell
  table now multiplies by instance counts (before, it summed cells per module
  *definition* and undercounted repeated submodules: its tube column added up to ~1528 of 1595.5).

### Where relays went, and where they didn't

Switch-controlled logic in RTL lives only in `MachineCtrl` (IpLine/ApLine have no
switch inputs). Each site was measured: MachineCtrl synthesized in all 8 combinations
(bell / run / echo relays on or off) × 7 ABC seeds (`&deepsyn -S 0…6`), then each bell
site separately (8 × 7). Main effect = mean tubes with the relay − mean without it.

| Site | RTL | Relays | Effect, tubes | Decision |
|---|---|---|---|---|
| `BellOnHALT` | `RelayEn` on the HALT bell term | 1 | −1.8 | relay |
| `BellOnCIN` | `RelayEn` on `decode_run & is_cin` | 1 | −3.0 | relay |
| `BellOnError` | `RelayEn` on `overflow_hit` | 1 | −1.6 | relay |
| `RunOnSoftRst` / `RunOnHardRst` | `RelayMux #(1,2)`: `{soft, hard}` selects `{1, rst_soft, ~rst_soft, 0}` | 2 | −1.3 (no mux cell in the library: a 2:1 mux costs gates) | relay |
| `EchoMode` | `is_cin & echo_mode` | – | −0.3 (noise: the AND merges into the next-state term) | **tubes** |
| `SoftRstOnEOT` | FSM branch in `S_DECODE` | – | not a MUX/EN: the switch picks the next state, the gate stays either way | **tubes** |

`run_on_rst` was `rst_soft ? run_on_soft_rst : run_on_hard_rst`, so the select was the
`rst_soft` trigger, not a switch. To keep the rule "coils only from switches" it was turned
around: the two switches drive the coils and `rst_soft`/`~rst_soft` (`QN`, free) pass
through the contacts. Behaviour is unchanged.

Total: **5 RELAY_2CO**. One contact is spare in each `RelayEn #(1)` and in the second
level of the `RelayMux`.

| MachineCtrl variant (bell/run/echo) | mean of 7 seeds | min | max |
|---|---|---|---|
| none (before) | 254.3 | 250 | 259 |
| bell + run (chosen) | 249.8 | 246.5 | 252.5 |
| bell + run + echo | 248.3 | 245.5 | 254 |

bell + run + echo is 1.5 lower on average, but echo's main effect over all 8 combinations
is −0.3, within noise, so echo stays on tubes per the owner's rule.

### Verification

- Exhaustive Icarus check of `RelayMux`/`RelayEn` against `d[sel*W +: W]` and `en ? a : 0`
  for (W,S) = (1,1), (1,2), (3,2), (4,3), (5,1), (2,4), 200 random vectors each: 0 errors.
- `MachineCtrl_tb` (all checks, including bell, echo, run on hard/soft reset, SoftRstOnEOT)
  and `DekatronPC_tb` (helloworld, program.bfk) pass on Icarus.
- Verilator `--lint-only -Wall`: clean for `DekatronPC` and `Emulator`.
- Synthesis `run_tests.sh -s`: `equiv_opt` proven on all three blocks (relays are black
  boxes on both sides).

| Block | Tubes | Relays |
|---|---|---|
| IpLine | 661.5 | 0 |
| ApLine | 684 | 0 |
| MachineCtrl | 250 | 5 |
| Total | **1595.5** | **5** |

Note: today's IpLine/ApLine (661.5 / 684) differ from §14 (652 / 676) although their RTL
didn't change in this step. Synthesizing them without the relay cell in the library gave
662.5 / 681.5, so ABC results move by ±10 tubes between runs. Comparisons below ~5 tubes
need several seeds (as above), not one run.

Block diagram: sheet 6 marks which switches go through relays.

## 16. Speed over tubes: prefetch P3 (REQ-PERF-003)

The owner chose P3 from `doc/cycle_profile_helloworld.md`: the next opcode is fetched while
ApLine works. That brings back an opcode register, removed in §14 (R4) to save tubes,
this time as `op_q` in MachineCtrl. Over 3 seeds, MachineCtrl goes from 248.3 to 318.7
tubes (+70.4). The 5 new flops cost 35 tubes; the rest is the load enable and decoding.
IpLine is unchanged (663.7 → 663.8). In exchange, helloworld runs in 4184 cycles instead
of 5540. Details, per-seed numbers and the 8-tube cheaper of the two variants:
`doc/prefetch_p3.md` §5.

## 17. Second attempt toward 1200 (2026-10-08)

The goal is still REQ-MOD-009, 1200 tubes for the whole machine. This round looked for
levers outside FSM cleanup. All experiments ran on scratch copies of the RTL, and nothing
in the repo was changed except this report. Flow: `synt_dpc.tcl` as committed (Yosys 0.51,
`&deepsyn -J 50`, `equiv_opt`, `qn_absorb.py`). "Seed" means `&deepsyn -S`.

### 17.1 Where the tubes are now

HEAD (4f3f4ad), three seeds: **1669.5 / 1644 / 1653.5, mean ≈ 1656** for IpLine + ApLine +
MachineCtrl (§16 had ≈ 1666.5; the `dirty_q` removal is within noise). There are 80 triggers
(560 tubes, 34 %):

| Where | Triggers | What they are |
|---|---|---|
| 4 counters | 41 | carry flags `nines_q`/`zeroes_q` (+ `zero_q`/`at_top_q` in Data): 24; state register, **one-hot** after Yosys FSM extraction: 4–5 per counter, 17 |
| IpLine glue | 17 | state one-hot (9), `dir_q`, `ip_counted_q`, `insn_valid`, `scanning_q`, `loop_overflow`, `key_moved_q`, `halt_pending_q`, `insn_eot`, `mem_wr` |
| ApLine glue | 8 | state one-hot (5), `mem_here_q`, `mem_lock`, `mem_wr` |
| MachineCtrl | 14 | state (4, binary: it is an output port, so it isn't extracted), `op_q` (5), `ip_ahead`, `insn_loading`, `rst_soft`, `one_step`, `overflow_q` |

### 17.2 Measured: binary state encoding (−219)

§2.1 concluded that the encoding doesn't matter, but both passes it compared ran after
`synth` and were no-ops. Setting the encoding through the attribute before synthesis:

```systemverilog
(* fsm_encoding = "binary" *) logic [2:0] state;   // DekatronCounter (next split off)
(* fsm_encoding = "binary" *) logic [2:0] state;   // ApLine
(* fsm_encoding = "binary" *) logic [3:0] state;   // IpLine
```

IpLine + ApLine (MachineCtrl isn't affected):

| Variant | Seed 0 | Seed 1 | Seed 2 | Mean | Δ |
|---|---|---|---|---|---|
| HEAD (one-hot from Yosys) | 1335.5 | 1329 | 1327 | 1330.5 | – |
| counters binary only | 1249 | | | | −86.5 |
| IpLine/ApLine binary only | 1189.5 | | | | −146 |
| all `fsm_encoding = "none"` (keep the RTL codes) | 1187 | | | | −148.5 |
| **all binary** | **1116.5** | **1108** | **1111** | **1111.8** | **−218.7** |

The three blocks: ≈ 1656 → **≈ 1437** (1450.5 / 1423 / 1437.5). Triggers 80 → 64 (counters
41 → 33, IpLine 17 → 12, ApLine 8 → 5). The logic shrinks as well, because one-hot
next-state logic on 7-tube triggers isn't cheaper than binary decoding in this library.
`equiv_opt` passes. `synth_sim.sh Counter IpLine ApLine` on the binary netlists: all PASS.
DekatronPC and the delay/SDF runs weren't repeated.

MachineCtrl keeps its hand-written codes because `state` is an output port (it only goes
to the panel display, `DPC_currentState`). 24 random code assignments (seed 0) gave
320.5…355 tubes, and today's codes gave 334. A search would gain about −10…−15, which is
close to the ±10 drift. The panel decode would have to follow the new codes.

### 17.3 Breakdown after binary encoding (seed 1, 1423)

| Part | Tubes | Note |
|---|---|---|
| `DekatronPulseSender`, 15 decades × 6 | 90 | AND-OR of StepF/StepR with Phase1/Phase2 |
| `BinToBcd`, 13 decades × 9 | 117 | Loop has READ = 0 in the real machine |
| `BcdToBinEn`, 3 decades (Data) × 20.5 | 61.5 | |
| `DekatronPhaseGen`, 4 × 2.5 | 10 | |
| Counter control (FSM, carry chain, 33 triggers = 231) | 407 | Loop 58, IP 116, Data 118, AP 115 |
| IpLine glue (+ InsnLoopDetector 5.5) | 243 | 12 triggers |
| ApLine glue | 179.5 | 5 triggers |
| MachineCtrl | 315 | 14 triggers |

The counters are still 685.5 tubes (48 %).

### 17.4 Ideas, with estimates

| # | Idea | Δ, tubes | Status of the estimate | Changes a rule? |
|---|---|---|---|---|
| T1 | Binary `fsm_encoding` in DekatronCounter, IpLine, ApLine (§17.2) | **−219** | **Done, §17.6** | no |
| T2 | **Diode codecs.** REQ-AUTH-002 already allows germanium diodes in BCD encoders/decoders. `BinToBcd` becomes a diode OR matrix on the cathode outputs (0–2 tubes per decade for buffers), and `BcdToBinEn` a diode AND matrix (true/complement inputs: `QN` is free on triggers, otherwise 4 × NOT = 2 tubes) | **−150…−170** (BinToBcd 117 → 0…26, BcdToBinEn 61.5 → ≈ 6) | cell costs only | no (REQ-AUTH-002); needs a library model: a codec cell with an explicit area, or the codec modules counted as black boxes like the relays |
| T3 | **Latches for the carry flags** (24 bits). A flag only has to hold during the step. A `LATCH` (3.5) transparent in the fall window, closed while Phase1/Phase2 are active (`Win12` of the counter's own `DekatronPhaseGen`), replaces a 7-tube DFF | **−70…−84** | flops removed in synthesis: −152.5 (seed 1); +24 × 3.5 for the latches gives ≈ −68.5, ideal −84 | no rule, but a timing argument: the latch must close before the discharge leaves the main cathode (GUIDE_STEP_HS); check it with `synth_sim.sh -t` |
| T4 | Counter FSM: IP, Loop and AP only use IDLE / ZERO / RST. A single `busy_q`, plus a way to keep IP's hard reset from being overwritten by `set0`, saves one trigger per counter | −20…−40 | estimate | no |
| T5 | `DekatronPulseSender`: move the direction swap to the counter (PhA = dec ? Ph2 : Ph1, PhB likewise, once per counter), so each decade only ANDs its step with PhA and PhB | −15…−35 | estimate | the DekatronModule ports change (StepF/StepR → Step) |
| T6 | MachineCtrl state codes chosen by search (§17.2) | −10…−15 | measured spread | the panel decode of `state` follows |
| T7 | P3 prefetch costs ≈ +70 (§16): the cheaper variant (−8, `doc/prefetch_p3.md` §5), or `op_q` in latches (5 × 3.5 = −17.5) | −8…−70 | measured / estimate | the owner chose speed (REQ-PERF-003) |
| T8 | **Ripple carry as in classic dekatron counters**: the next decade steps when this one's discharge arrives at 0 (forward) or 9 (backward), via a pulse from cathode 0/9. This drops the carry flags (T3) and the AND chains. A carry then costs one step time per decade, so the counter holds ready longer after a carry (IP: 1 in 10 steps) | −80…−110 (instead of T3) | estimate | yes: one step per clk (REQ-DEK), ready timing; owner decision |
| T9 | Dekatron as an FSM state register (owner's idea in §6): cathode outputs give the one-hot decode for free | not recommended | – | reading is valid only on a main cathode with no stimulus (REQ-DEK-015), so the Moore outputs would need latches during each step, and jumps need a write window (10 clk). This loses what it saves |

Not counted at all yet: memory support, `RstTimeRelay`, the panel (TRS §22 item 10). They
still have to fit in the same 1200.

**Projection** (means, three blocks): 1656 → T1 1437 → T2 ≈ 1275 → T3 ≈ 1195 → T4–T6
≈ 1130–1170. T1–T3 bring the three blocks to the budget. Room for the uncounted parts
needs T4–T7, or T8 (owner) in place of T3.

### 17.5 Questions for the owner

1. ~~T1: apply binary encoding?~~ Yes (owner, 2026-10-08); done in §17.6.
2. T2: how should a diode codec be counted? Zero tubes, or a buffer per output bit
   (cathode follower)? Can a dekatron cathode output drive the diode matrix and the
   memory address lines directly?
3. T3: OK to use latches with a phase-window enable in DekatronCounter? The flow also
   needs a latch mapping step: Yosys 0.51 `dfflibmap` leaves `$dlatch` unmapped, so
   `dpc_stat.py` counts it as 0 (that's why the measurement in T3 was corrected by hand).
4. T8: is a ripple carry (slower after a carry, no flags) acceptable for any of the counters?
5. T6: may the panel decode of `state` change?

### 17.6 Done: T1, binary state encoding (2026-10-08)

Owner's decision: apply T1. Changes:
- `DekatronCounter.sv`, `IpLine.sv`, `ApLine.sv`: `(* fsm_encoding = "binary" *)` on the
  state register (in DekatronCounter, `next` is now declared separately, because the
  attribute must sit on `state` alone). Behaviour and state codes are unchanged; only the
  encoding Yosys picks after FSM extraction changes.
- `rtl/run/synt_dpc.tcl`: the comment that said the encoding had been measured is corrected.

Verification:
- `run_tests.sh -t`: Verilator lint of DekatronPC and Emulator clean; all Icarus tests;
  Verilator step compare with dpcrun on helloworld, program.bfk and pi.bfk — PASS.
- `run_tests.sh -s`: IpLine 517.5, ApLine 599, MachineCtrl 334, **total 1450.5 tubes + 5
  relays** (was 1669.5 on the default seed); `equiv_opt` proven on all three blocks.
- `synth_sim.sh` (all default tests, DekatronPC included): PASS. `run_tests.sh -d` and
  `synth_sim.sh -d`: PASS.
- `synth_sim.sh -t` (default Clk 1 µs): Dekatron, Counter, DekatronPC fail, as on HEAD
  before T1 (checked: HEAD's Dekatron fails the same way at 1 µs; the known phase-window
  problem of doc/vtube_sdf_timing.md). At `-c 10000` Dekatron passes, as documented.

No block diagram changes (encoding is not drawn in SCHEMES.md).
