# MemLock as the only ApLine flag (dirty removed)

Date: 2026-10-08. Requirements: REQ-APV2-002, REQ-APV2-003, REQ-ML-005/007 (TRS v0.10).
Decision: project owner.

## 1. Question

ApLine had two ownership bits, `lock_q` (MemLock) and `dirty_q`. Do they mean the same thing?

## 2. Analysis

Reachable (lock, dirty) states before the change:

| lock | dirty | How it is reached |
|---|---|---|
| 0 | 0 | reset, AP step after a flush, CLRML |
| 1 | 1 | `+ - CLRD CIN` (S_DOP, op_cin) — the only places that set either bit, and they always set both |
| 1 | 0 | **STORE only**: S_FLUSH clears `dirty`, and STORE keeps MemLock |
| 0 | 1 | impossible (it had an assertion) |

The two bits differ only after STORE. `dirty` saved one write: `>`/`<`/CLRA/CLRML after STORE
skipped a second write of the same value. The price was a defect. An AP step with `lock = 1, dirty = 0`
went straight to S_AP. `lock_q` is cleared only in S_FLUSH, so MemLock survived the move, and the
counter then stood for the new cell (TRS v0.9 item "reset lock on any address step";
`doc/dpcrun_golden_model.md` divergences 2 and 3).

## 3. Rule after the change (owner)

One flag is enough:

- To change data without MemLock: the counter doesn't hold the cell, so load it first.
- To change the address (`>`, `<`, CLRA) or run CLRML with MemLock set: flush the counter first. The flush
  clears MemLock.
- STORE writes and keeps MemLock (REQ-ML-004). The next AP step or CLRML writes the same value again.

## 4. Changes

- `rtl/DekatronPC/ApLine.sv`: `dirty_q` and its assertion are removed. S_IDLE goes to S_FLUSH on
  `op_ap_step | op_ap_zero` and on `op_clrml` when `lock_q` is set. S_FLUSH clears `lock_q` for
  everything except STORE, as before. State is now two bits (`lock_q`, `mem_here_q`).
- `bfutils/dpcrun` (submodule): `m_dirty` and `dirty()` are removed, and `apMove`/CLRML flush when `m_lock` is set.
  Unit tests: `store_keeps_lock_across_move` became `store_keeps_lock_until_move`, and
  `clra_after_store_keeps_lock` became `clra_after_store_unlocks`. `clrml_flushes_and_unlocks` now expects 2 writes after `+PM`.
- `rtl/tests/ApLine.sv/ApLine_tb.sv`: STORE then AP step now expects a second write and MemLock = 0.
- TRS (REQ-APV2-002/003, REQ-GM-004, §1 v0.10, §22), `SCHEMES.md` sheets 5 and 7 (the dashed
  defect edge is gone), `doc/dpcrun_golden_model.md`, `AGENTS.md`.

## 5. Results

| Check | Result |
|---|---|
| `ApLine_tb`, Icarus, DekatronTubeV2 | pass |
| `ApLine_tb`, Icarus, `DEKATRON_DELAY_MODEL` | pass |
| `dpcrun` unit tests (ctest) | pass |
| `dpcrun` memory accesses, `helloworld.bfk` | 58 reads / 57 writes, same as before |
| `dpcrun` memory accesses, `pi.bfk` (AP top 99999) | 55 723 reads / 43 354 writes = 99 077, same as before |

bfpp never emits STORE, so real BF programs don't see the extra write. Not yet run: the full
DekatronPC step compare in Verilator (`run_tests.sh -t`, heavy), netlist simulation and the tube count
(`run_tests.sh -s`). One fewer flip-flop and its set/clear logic should come out of ApLine.

`-DASSERTIONS` doesn't compile under Icarus because of
`rtl/DekatronPC/Dekatron/DekatronTubeV2_assertions.sv`. That defect was already there; this change didn't cause it.
