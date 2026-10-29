# OR4: cathode followers against a diode OR (2026-10-29)

The owner asked to compare the two ways of building a four-input OR before choosing (TRS v0.21). The liberty cell `OR4_N16X7` (0.5 × 6N16B + 2 × 6Kh7B, 2.5 tubes) is used 29 times in synthesis (72.5 tubes). Script: `tools/spice/or4_compare.py`.

Common chain: each input from a NOT driver (6N16B, Ra 10k) fed by an ideal HV pulse. Y (LV) goes onto N load grids (NOT_N16 loads); their plate shows what Y means on the next HV net. The delays run from the driver plate crossing 100 V to the load plate crossing 100 V, so they include the cell's input network and one load stage. Diode model: `sch/libs/6Kh7B.sub` at the sheet's leakage bound.

| Variant | Circuit | Tubes |
|---|---|---|
| A | OR2_N16 widened: each input through its own divider (2.7 pF) onto a follower grid; four triodes (2 × 6N16B), cathodes tied, Rs 2.2k ‖ 100 pF → Y → Rk 12k → −50 V | 2 |
| B-HV | four diodes, anodes on the driver plates, cathodes on node N; Rd from N to −50 V; N → one divider (2.7 pF) → one follower (half a 6N16B) | 2.5 |
| B-LV | each input through its own divider (3.9 pF) → diode → N = the follower grid; Rd from N to −50 V | 2.5 |

## Results

| | Fanout | A, Rk 12k | A, Rk 10k | B-HV, Rd 470k | B-HV, Rd 150k | B-HV, Rd 47k | B-LV, Rd 470k |
|---|---|---|---|---|---|---|---|
| input ↑ → load plate | 2 / 6 / 10 | 14–18 / 38–46 / 65–86 ns | 17–20 / 42–50 / 72–92 | 11–105 / 86–200 / 162–297 | 10–34 / 97–136 / 189–249 | fails from fanout 6 | 63–141 ns / µs / µs |
| input ↓ → load plate | 2 / 6 / 10 | 53 / 161 / 262 ns | 34 / 121 / 204 | 55 / 155 / 258 | 44 / 136 / 227 | 3.2–4.1 µs | 2.6–6.6 µs |
| driver "1" (diode load) | | 146.9 V | 146.9 | 141.7 | 133.9 | 112.7 | 146.6 |
| Y "0", worst | 10 | −17.7 V | −18.8 | −15.6 | −18.7 | −19.0 | −13.8 |
| load plate with Y = 1 | 10 | ≤ 53.3 V | ≤ 56.3 | ≤ 54.7 | ≤ 59.8 | ≤ 138 (fails) | ≤ 149 (fails) |
| hazard (A↓ B↑): load plate peak | 2 / 10 | 106 / 70 V | 123 / 77 | 89 / 66 | 108 / 75 | — | — |

### Why the diode OR works only on the plates, and only with a high Rd

- **A diode can only pull its node up.** When the last high input falls, the node comes down only through Rd and the divider. That would be τ = 276 kΩ × ~26 pF ≈ 7 µs. B-HV still falls in 155 ns at fanout 6 because the falling plate drags the node down through its own diode capacitance (≤ 5.8 pF) against the capacitance of the three diodes on static plates. The last 2 V settle slowly: the worst Y "0" is −15.6 V against −17.7 V for A.
- **Rd loads the driver's "1".** With 470k the high plate sags 5 V. With 150k it sags 13 V and the load plate on a "1" rises to 60 V. With 47k the driver falls to 113 V and the cell no longer works.
- **B-LV fails.** Behind a divider (140 kΩ Thevenin) an input cannot lift Rd and the follower grid. Y "1" stays at −8 V and below, and the loads never switch.

## Summary

| | A (OR4_N16) | B-HV, Rd 470k (OR4_N16X7) |
|---|---|---|
| Tubes | **2** | 2.5 |
| Rising edge | **2–3 × faster** (65–86 ns at fanout 10) | 162–297 ns |
| Falling edge | the same (~260 ns at fanout 10; Rk 10k: 204 ns) | the same |
| Load on the drivers | one divider per input, as any follower | the diode current: the "1" sags 5 V |
| "0" margin | 10.1 V | 8.0 V |
| Hazard | worse at fanout 2 (106 V, over the 92 V threshold for ~0.1 µs, as OR2_N16) | better (89 V) |
| Parts | 4 dividers on the inputs | 1 divider, 4 diodes, Rd |

Recommendation: **A, as a new cell OR4_N16** (2 × 6N16B), designed like OR2_N16, with `OR4_N16X7` dropped from the liberty. It saves 14.5 tubes at today's 29 cells and is faster. The diode OR on the plates is workable, but only in a narrow window of Rd and with the 6Kh7B's capacitance doing the falling edge. The same limit applies to the other `*_N16X7` diode cells (`AND2_N16X7`, `NAND4_N16X7`, `NOR*_N16X7`): a diode gate needs stiff drivers. **Owner's call.**
