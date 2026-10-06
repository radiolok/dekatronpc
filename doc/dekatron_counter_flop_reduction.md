# DekatronCounter: removing redundant flip-flops (plan)

Status: **implemented** 2026-10-06 (see §7 for the owner's decisions and §8
for what was done and verified). Date: 2026-10-06. Covers
`rtl/DekatronPC/Dekatron/DekatronCounter.sv` (TRS v0.10).

## 1. What we have now

On every `clk` edge the counter latches the readings of all decades:

| Flop | Width | Used for |
|---|---|---|
| `zeroes_q` | D_NUM | borrow chain (`step_r_chain`), output `zero`, `set_top_int` (TOP_LIMIT_MODE) |
| `nines_q` | D_NUM | carry chain (`step_f_chain`) |
| `tops_q` | D_NUM | output `at_top`, `set_zero_int` (TOP_LIMIT_MODE) |
| `primed_q` | 1 | keeps `ready` low for the first `clk` after `rst_n`, until the `_q` flags are valid |

Instances (from `IpLine.sv`, `ApLine.sv`):

| Counter | D_NUM | TOP_LIMIT_MODE | `zero` used | `at_top` used | Flops now |
|---|---|---|---|---|---|
| IP | 5 | 0 (HARD_RST_D_CNT) | no | no | 16 |
| Loop | 2 | 0 | yes (IpLine, S_LOOP_WAIT) | no | 7 |
| AP | 5 | 0 | yes (MachineCtrl loop_val_zero, Debug ISA) | no | 16 |
| Data | 3 | 1, TOP=255 | yes (ApLine data_zero) | no | 10 |
| **Total** | | | | | **49** |

Synthesis already drops some of these (for example unused `tops_q`), but the real
machine builds each one as a tube trigger. So the netlist must not contain them
in the first place.

## 2. Why the decade outputs can't simply replace the flops

`DekatronModule.Zero/Nine/TopPin` are `MainOneHot[0/9/N]`, which come
combinationally from the tube. During a step cycle the reading changes
**inside** the cycle:

```
clk edge ─┬─ phase1 (guide A) ─┬─ phase2 (guide B) ─┬─ fall ─┬─ clk edge
reading:  9 │ discharge leaves 9 after GUIDE_STEP_HS │ lands on 0 │
Nine:     1 ┘ 0 ...................................................  0
```

`DekatronPulseSender` is purely combinational (`guide = step & phase`), so every
decade's `step_*_chain[d]` has to stay constant for the whole cycle. If it were
fed straight from `dek_nine[d-1]`, then once decade d-1 leaves cathode 9 in
phase1, the step to decade d disappears: guide A gets cut short and guide B
never comes, so the discharge falls back from guide A and the carry is lost
(099 + 1 → 090). That is the physics from REQ-DEK-012/015, not a modelling
artifact. The chain needs **the value before the step**, and only a memory
element can keep it once the tube has moved.

The other ways to drop the flops don't fit the architecture either:

- **Classic carry from the arrival pulse on K0/K9.** Decade d+1 would only start
  after decade d lands, so the ripple would cost one `clk` per decade. That breaks
  "one step per `clk`" (REQ-CNT-V2-*, the fast path never lowers `ready`).
- **Transparent latch instead of an edge flop** (closed during phase1/phase2,
  open during fall). It's the same storage element in tube terms (one trigger
  per bit). It's FPGA-unfriendly, and it saves gates per bit, not bits. If you
  want to go this way, ask the owner first. Not part of this plan.

So the question is **which bits** are needed, not whether a register is needed.

## 3. Plan, flop by flop

### 3.1 `primed_q`: remove (zero cost)

Fold it into the FSM: the reset value of `state` becomes `ST_RST` instead of
`ST_IDLE`.

- `writeTimer`/`writeStart` are reset by `rst_n`, so `writing = 0` after reset.
- With `rst_active = 0` and `writing = 0`, `ST_RST` goes to `ST_IDLE` on the first edge.
- `ready = (state == ST_IDLE) & ~rst_active`: it stays low for exactly one `clk`
  after `rst_n`, the same as today, and on that edge the flags latch the real
  tube readings.

`ST_RST` already exists and the state is still 3 bits, so this costs no gates and saves 1 flop per counter.

### 3.2 `nines_q[D_NUM-1]`: remove

The carry out of the top decade isn't used (the `carry_f` after the last loop
iteration goes nowhere). Declare `nines_q` as `[D_NUM-2:0]` (with a guard
for D_NUM = 1). That saves 1 flop per counter.

### 3.3 `tops_q`: replace with one `at_top_q` and only in TOP_LIMIT_MODE

- `at_top` isn't connected in any of the 4 instances.
- Inside the counter it's only needed for `set_zero_int` in TOP_LIMIT_MODE (Data).
- There it **is** needed before the step: in an increment cycle 254→255 the
  discharge lands on TOP during fall, `at_top` would rise combinationally,
  `set_zero_int → set_any → write_req` would fire mid-cycle, and the FSM would
  take ST_ZERO at the edge, giving 254 + 1 = 0. So it stays a flop, but one bit
  instead of D_NUM: `at_top_q <= &dek_top`. AND first, then latch, because only
  the AND is used.
- For `TOP_LIMIT_MODE = 0` the flop isn't generated at all.

Savings: IP −5, AP −5, Loop −2, Data −2.

The **open question** is what to do with the `at_top` port. REQ-CNT-V2-009 marks
it "Done". Options:
  (a) keep the port, drive it from `at_top_q` in TOP_LIMIT_MODE and from
      `&dek_top` combinationally otherwise (valid only on edges with `ready`, like `out`);
  (b) remove the port and change REQ-CNT-V2-009 in the TRS.
  This is the owner's call.

### 3.4 `zeroes_q`: keep the borrow bits, make the `zero` output combinational where possible

- Bits `[D_NUM-2:0]` are needed for the borrow chain. Section 2 explains why.
  **They can't be removed.**
- Bit `[D_NUM-1]` is only used by `zero`.
- **Counters without TOP_LIMIT_MODE (IP, AP, Loop):** drive `zero = &dek_zero`
  combinationally from the tube. It's valid on `clk` edges under the same
  contract as `out` ("valid on clk edges while ready"). All consumers sample it
  in `always_ff` (IpLine `S_LOOP_WAIT`, MachineCtrl through `loop_val_zero`), so
  the mid-cycle glitch is invisible to them. That saves 1 flop per counter.
- **Data (TOP_LIMIT_MODE):** `set_top_int = zero & dec` uses `zero` inside the
  accept cycle. The same hazard as in 3.3 applies: decrementing 1→0 makes `zero`
  rise mid-cycle and the counter would go to 255 instead of 0. So the internal
  `zero` must come before the step. Keep `zero_q <= &dek_zero` as one flop, and
  the borrow bits stay. The Data counter keeps D_NUM zero-related flops (2 borrow
  bits + 1 `zero_q`).

There is a side effect to check in tests. Today, at the edge that closes a
step, `out` already shows the new value (combinational) while `zero` still
shows the old one (the flop). Combinational `zero` becomes consistent with
`out`. In the current consumers `zero` is read one edge after the step
(`S_LOOP_OP → S_LOOP_WAIT`), so both variants give the same result. Still,
this has to be confirmed by the tests in §5 and not assumed.

### 3.5 Optional: flops without asynchronous reset

After 3.1 nothing reads the flags before the first edge after `rst_n`, so
`zeroes_q/nines_q/at_top_q/zero_q` could drop the reset, which saves the reset
input of each trigger. The cost is X on `zero`/`at_top` in simulation for one
cycle after reset. That brushes against the "no X-masking tricks" rule, so
**the owner decides**. Not part of the main plan.

## 4. Result

| Counter | Now | After | What remains and why |
|---|---|---|---|
| IP (5) | 16 | 8 | zeroes[3:0] borrow, nines[3:0] carry |
| AP (5) | 16 | 8 | same |
| Loop (2) | 7 | 2 | zeroes[0], nines[0] |
| Data (3, TOP) | 10 | 6 | zeroes[1:0], nines[1:0], zero_q, at_top_q |
| **Total** | **49** | **24** | |

What can't be removed, and why:
- **`nines_q[D-2:0]`, `zeroes_q[D-2:0]`**: the carry/borrow chain needs the
  reading from before the step for the whole cycle, while the tube leaves the
  main cathode in phase1. The only way to avoid them is a one-`clk`-per-decade
  carry, which kills one step per `clk`.
- **`zero_q`, `at_top_q` (Data only)**: the rollover decision (`set_*_int`) is
  made inside the accept cycle. Read live, it would pick up the post-step value
  and trigger a false write (254+1→0, 1−1→255).

## 5. Implementation and verification steps

1. `DekatronCounter.sv`: 3.1, then 3.2, 3.3, 3.4 (generate on `TOP_LIMIT_MODE`).
   Update the header comment ("ЦЕПОЧКА ПЕРЕНОСА") and the comment on the latch block.
2. `verilator --lint-only` on DekatronCounter, with no new UNOPTFLAT. The combinational `zero` must not
   close a loop through `set_top_int`, and in TOP_LIMIT_MODE it comes from the flop.
3. cocotb single targets on Icarus: DekatronCounter (back-to-back inc/dec, carry
   099→100 and 100→099, rollover 255→0 and 0→255, the first cycle after `rst_n`),
   then the ApLine and IpLine targets (loop overflow, Debug-ISA `{ }` on `ap_zero`).
   No regression or full DekatronPC build without asking.
4. `tools/schemes/sheet3.py`: the sheet shows `primed_q`, `nines_q[*]`, `tops_q` and needs a redraw (`python3 tools/schemes/build.py`).
5. `DekatronCounter.md` (lines ~441–444), TRS: notes on REQ-REF-003/004/008,
   REQ-CNT-V2-009 (depends on the decision in 3.3) and the code fragment at TRS:164.

## 6. Questions for the owner (answered, see §7)

1. The `at_top` port: keep it (a) or remove it (b), see 3.3.
2. Is the combinational `zero` (valid only on edges) OK for IP/AP/Loop, see 3.4?
3. Flops without reset (3.5): yes or no.
4. Is the transparent latch worth looking at (§2), or do we stay with edge flops?

## 7. Owner's decisions (2026-10-06)

1. IP and AP don't need `at_top` at all. The Loop counter only needs it for
   overflow: a combinational `at_top` together with an increment is enough to
   raise the error. Overflow is detected **before** the step, not by the wrap
   99→0.
2. Combinational `zero` is fine, for all counters including Data (the
   internal Data rollover keeps its own `zero_q`).
3. A flag masked by valid (accept) may have no reset. A standalone signal must
   have a proper reset value.
4. Transparent latches are rejected, also for the tube machine.

## 8. What was done

`DekatronCounter.sv`:
- `primed_q` removed; `state` resets to `ST_RST`, `ready = (state == ST_IDLE) & ~rst_active`.
- `nines_q`/`zeroes_q` are `[D_NUM-2:0]` with no reset. The carry loop starts
  at decade 1 and reads `[i-1]`, so there's no out-of-range index.
- `zero = &dek_zero`, `at_top = TOP_LIMIT_MODE ? &dek_top : &dek_nine`,
  both combinational from the cathodes.
- `zero_q`, `at_top_q` (no reset) exist only inside `g_top_limit` and feed only
  `set_top_int`/`set_zero_int`, which are masked by `accept`.

`IpLine.sv` (REQ-CNT-007):
- `loop_at_top` is connected to the loop counter's `at_top`.
- `S_SCAN_EVAL`: if the bracket increments the nesting (`loop_inc_next`) and
  `loop_at_top`, then `overflow_q`, the scan ends and the step isn't issued.
- `S_IDLE`: scan start with `loop_at_top` (counter left at 99 by an earlier
  overflow) raises the overflow again instead of wrapping.
- The old post-step check `~loop_dec & loop_is_zero` in `S_LOOP_WAIT` is gone.
- Behaviour change: after an overflow the loop counter stays at **99**, it used
  to wrap to 0. `overflow_q` and the halt are unchanged.

Docs: `DekatronCounter.md` §10–11, `tools/schemes/sheet3.py` (SCHEMES
regenerated), TRS v0.10 (history, REQ-CNT-007, REQ-CNT-V2-009, REQ-REF-004).

Final flop count: IP 8, AP 8, Loop 2, Data 6, total **24** (was 49), as
planned in §4.

### Verification

- `verilator --lint-only -Wall` on DekatronCounter in four configs (default,
  TOP_LIMIT_MODE 255, D_NUM=2, D_NUM=5 + HARD_RST_D_CNT=3): no warnings in
  DekatronCounter, no UNOPTFLAT. IpLine/ApLine: only the existing
  PINCONNECTEMPTY style warnings.
- `rtl/tests/Counter.sv/Counter_tb.sv` on Icarus (TOP_LIMIT_MODE, 255; built
  by hand, its `counter.sh` is stale): **Counter Test Success** (0..255 and back,
  255+1→0, 0−1→255, set, set_zero, soft/hard reset, `zero` after reset).
- A scratch Icarus bench, D_NUM=2 without TOP (like Loop): back-to-back
  0→99 and 99→0 with valid held (ready never drops), 09↔10 carry/borrow, `zero` and
  `at_top` at every checkpoint, `ready` low before the first edge after
  `rst_n` and high after it: **PASS**.
- **Not run:** the cocotb `test_dek_counter` target (cocotb is broken in this
  environment: `cocotb-config` can't import `cocotb_tools`). The IpLine overflow
  path has no test: `tb/tests/test_ip_line.py` doesn't exist, and the full
  DekatronPC Verilator build is a heavy job that waits for the owner's go-ahead.

### Follow-ups

- ~~Golden model wraps `m_loop` to 0 on overflow.~~ Done: `dpcrun` now has
  `LOOP_SIZE = 100` (it was still 1000, i.e. 3 dekatrons) and catches the
  overflow before the increment, leaving the counter at 99.
- Write an IpLine overflow test (REQ-VER-*, TRS §22 item 2).
