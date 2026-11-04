# RELAY_HOLD_N16: self-holding relay that stops the clock on a loop overflow

Cell page (TC-N2, `doc/tube_count_below_1000.md` §13, TRS v0.46). The owner's proposal: the machine
gives the LoopOverflow lamp, and this signal latches a self-holding relay that stops the clock.
**Status: proposed, not simulated, not placed in the RTL.** The clock generator is outside the three
counted blocks (in the emulator, the FPGA supplies Clk), so the cell goes on the clock-generator
board of the real machine.

| | RELAY_HOLD_N16 |
|---|---|
| Function | S = 1 latches the relay; BRK = 1 releases it. C1 = held ? NO1 : NC1 |
| Parts | one relay with two changeover groups (one holds, one switches the clock) + ½ 6N16B coil driver |
| Tubes | 0.5 (the driver); the relay is not a tube (`relays: RELAY_2CO 1` in the count) |
| Inputs | S: LV (the LoopOverflow net through its divider); BRK: the reset line (soft_rst \| hard_rst) |
| Contacts | NC1, NO1, C1: pass any signal (`vtube_level PASS`), as in `RELAY_2CO` |
| Liberty | `RELAY_HOLD_N16`: area 0.5, no function (ABC never uses it) |

## Circuit (proposal)

```
 +Ucoil ── coil ──┬── plate of ½ 6N16B (grid = S, cathode to ground)
                  │
                  └── hold contact (group 2, NO) ── BRK contact (NC, opened by the reset line) ── ground
 Clk ── NC1 ──┬── C1 ── clock of the machine
              └── reset-relay contact (NO, closed while a reset line is high)
```

- **Latch.** S high opens the driver triode, and the coil pulls in. Group 2 closes the hold path
  through the BRK contact, so the relay stays in after S drops. One triode of a 6N16B carries the coil
  current of a small relay (≈ 10–20 mA at a few tens of volts, e.g. a 27 V relay with a 1.5–2.5 kΩ
  coil). The second triode is free (or drives the lamp).
- **Clock stop.** Group 1 (NC1 → C1) breaks Clk.
- **Release, and why the bypass is needed.** IpLine's `overflow_q` is cleared by the reset line
  **synchronously**, on a Clk edge (TC-O5: the glue has no asynchronous reset). If the reset only
  broke the hold, S would still be high, the coil would stay in, and the clock would stay stopped:
  `overflow_q` would never clear (deadlock). So a contact of the reset time relay (`RstTimeRelay`,
  closed while a reset line is high) is wired **in parallel** with NC1. During a reset the clock runs
  whatever the relay does. The first edge clears `overflow_q`, S drops, the open BRK contact lets the
  relay go, and NC1 carries the clock again before the reset line falls. The time relay holds the line
  for ≈ 10 Clk, which is more than enough.
- The relay contacts switch the 100 kHz clock: chatter on pull-in or release gives a few short clock
  pulses. Stopping is harmless (IpLine is already not ready, TC-N2: nothing moves on extra edges).
  Starting happens inside the reset window, where the reset lines force every trigger anyway.

Why a relay is acceptable here although relays were removed from the logic (TRS v0.43, REQ-MOD-011
rejected): it sits on the clock-generator board, outside the logic boxes. It replaces nothing in the
tube logic; it is the owner's way to stop the clock visibly on the hardware error.

## Liberty entry and model

`vtube_cells.lib` `RELAY_HOLD_N16`: pins S (LV), BRK (`vtube_level RESET`: driven only by the reset
line), NC1, NO1 (PASS), C1 (PASS out); `tubes N16B 0.5`, `relays RELAY_2CO 1`, no function.
`vtube_cells.v`: `held` is set by S and cleared by BRK (BRK wins), and `C1 = held ? NO1 : NC1`. The
bypass contact of the time relay is outside the cell. `vtube_timing.json`: zero delays (the relay
time, ≈ ms, is outside the logic timing).

## Open points

- Pick the relay (coil voltage and current against the 6N16B triode), and add a flyback element
  across the coil. It has to be a tube or a resistor + capacitor (REQ-AUTH: no silicon in the machine;
  the clock board is part of the machine).
- Place it on the clock-generator board when that board is drawn. Nothing in the RTL instantiates
  the cell: the clock comes from outside DekatronPC.
