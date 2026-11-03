# KEYDB_N16: panel key debouncer on one 6N16B

Cell page (TC-N3, `doc/tube_count_below_1000.md` §12, TRS v0.45). The cell sits between a physical
panel key and the logic. It turns a bouncing contact into one clean level. The synchronizer trigger
behind it (a `DFF_J2N16` in IpLine) aligns that level to Clk. **Status: proposed, not
simulated.** The values below are a starting point for SPICE, not results (REQ-MOD-004).

| | KEYDB_N16 |
|---|---|
| Function | Y = A \| B, the "pressed" level of up to two changeover keys wired in parallel |
| Tubes | one 6N16B (both triodes form a bistable) |
| Inputs | contacts, not logic levels: the NO and NC sets of a changeover (SPDT) key |
| Output | HV (as every gate: 1 = +150 V, 0 = +50 V), max_fanout 6 |
| Liberty | `KEYDB_N16`: area 1, no function (ABC never uses it), pins A, B (`vtube_level KEY`), Y |

## Why a bistable and not a one-shot

Bonch-Bruevich (`doc/bonch_bruevich_lamps_review.md` §4, ch. VI §2):

- a trigger should get a signal with **one** steep edge, because a pulse with two steep edges can
  flip it twice (p. 279);
- a one-shot (waiting multivibrator, fig. 264, p. 282) has a recovery time (formulas 313–314, p. 293).

A bouncing contact gives a burst of edges on closing **and** on opening. A one-shot fired by an edge
covers the closing burst only if its pulse is longer than the bounce. Then the opening burst fires it
again unless the key is held longer than the pulse, and the recovery time sets the shortest press.
That needs a time constant tuned against the key, plus a second element against the release bounce.

The Eccles–Jordan bistable (fig. 258, p. 273) on a changeover contact needs neither. The moving
contact touches either NO or NC, never both. On the way between them it touches nothing, and the
bistable holds its state. A bounce on NO repeats "set" while the bistable is already set, and a bounce
on NC repeats "reset" while it is already reset. The output changes once per press and once per
release. No RC timing is needed.

An RC + Schmitt variant (one 6N16B as a cathode-coupled Schmitt trigger) is the fallback for keys
without a changeover contact. It costs the same tube, but it needs τ ≈ 20 ms, which is longer than
the bounce.

## Circuit (proposal)

```
            +150 V                 +150 V
              │ Ra 10k               │ Ra 10k
    plate T1 ─┤                      ├─ plate T2 ─── Y (high while pressed)
              │                      │
    grid T1 ──┤◄── 470k‖3.9p ── plate T2      cross-coupled dividers as in RSLATCH,
    grid T2 ──┤◄── 470k‖3.9p ── plate T1      each grid 200k to −50 V
    grid T1 ── NC contacts (in series)   ── −50 V   released: T1 cut off, T2 open, Y low
    grid T2 ── NO contacts (in parallel) ── −50 V   pressed:  T2 cut off, Y high
```

- Each contact set **pulls a grid to −50 V**, which cuts that triode off. No current flows into the
  contacts beyond the divider current (≈ 0.2 mA), so the key needs no rating.
- Pressed (NO closed): T2 is cut off, so its plate is high, and the divider holds T1 open. Released
  (NC closed): the opposite. Y is taken from the plate that is high when the key is pressed.
- Two keys in one cell (A, B): NO sets in parallel (either key sets it), NC sets in series (only
  both released resets it). That makes "any key pressed" with no extra tube. IpLine doesn't use it:
  the direction has to be synchronized together with the step, so each key gets its own cell (B = 0).
- Ra, the divider and the grid clamp are those of the latch family (`RSLATCH_J2N16`). The output
  divider to the next grid is placed by `div_insert.py`, as for every HV net.

To check in SPICE: the switching time is set by the contact, not by the tube, so only the levels
matter. Check that the contact really cuts off at −50 V, check the output levels at fanout 6, and
check that a 1–5 ms bounce (a burst of 10–100 µs closures) changes Y exactly once.

## Where it is used, and what it costs

IpLine (TC-N3), one cell per key:

```systemverilog
KEYDB_N16 keyDbPrev (.A (key_prev_ip), .B (1'b0), .Y (key_prev_db));
KEYDB_N16 keyDbNext (.A (key_next_ip), .B (1'b0), .Y (key_next_db));
// synchronizers: +IP -> key_next_s; -IP -> dir_q itself, which takes key_prev_db
// every Clk while IpLine stands in S_HALT / S_INSN_IN (cleared on entry)
wire key_prev_s = dir_q & key_dir_mode;
always_ff @(posedge clk) begin
    key_next_s  <= key_next_db;
    key_moved_q <= key_prev_s | key_next_s;      // one Clk later: the edge
end
wire key_step = (key_prev_s | key_next_s) & ~key_moved_q;   // one Clk per press
// counter: .dec (dir_q)
```

Why it is built this way (each point came out of `synth_sim.sh -t`, the netlist with tube delays):

- **A synchronizer is necessary.** The counter's step command has to be steady from the Clk edge
  through the phases. An unsynchronized key can rise in the middle of a phase and give a truncated
  guide pulse. A one-shot driving the guides directly doesn't work either: the carry latches are
  open in every `CmdWin` (TC-D1), so an asynchronous step can drop an upper decade's enable halfway.
- **The step and its direction have to come from the same trigger.** A first version synchronized
  "any key" in one trigger and loaded the direction into `dir_q` through the FSM. The short path won
  the race: the step was caught one Clk before the direction, and −IP stepped forward.
- **`dec` has to stay a trigger output.** A mux `key_mode ? key : dir_q` in front of `dec` made the
  path from the Clk edge through the carry chain longer than the command window, and the carry latch
  of decade 4 failed its setup. So for −IP, `dir_q` itself is the synchronizer.
- `key_next_s` is listed in the "masked" section of `vtube_timing.json`: it samples an asynchronous
  level by design, so its setup check can't mean anything. `dir_q` is not masked: in the netlist runs
  the keys change right after the Clk edge, and the path through the FSM keeps its D clear of the
  setup window.
- Cost: 2 × KEYDB (2 tubes) + `key_next_s` (7) + `key_moved_q` (7, it was already there), plus the
  `dir_q` load in two states.

In the RTL model (and in `vtube_cells.v`), Y = A | B. The bounce is outside the model: the
testbenches and the emulator drive clean key levels.

## Open points

- SPICE of the cell (above), then a KiCad sheet by the method (`doc/cell_design_method.md`).
- A cheaper option for later: a clocked RS latch (`RSLATCH_J2N16`, E = ~Clk) on the contacts would
  debounce and synchronize at once (3 tubes per cell instead of 1 + 7). It needs latch handling of a
  new cell in `vtube_sdf.py` / `vtube_sta.py`. Not done.
- The other panel keys (Halt, Step, Run, loading start/stop, resets) go into MachineCtrl as levels.
  They have no debouncer yet. Step is edge-sensitive (`one_step`), so it needs this cell as well
  when the panel is built.
