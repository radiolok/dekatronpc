# OR-AND-INVERT cells: NAND2_J2 with follower ORs on its grids

Investigation, 2026-11-13. Question from the owner: would OAI cells save tubes in synthesis? The cell is a `NAND2_J2` (one 6Zh2B) whose grids are driven by cathode-follower ORs (`OR2_N16`, one 6N16B with the cathodes tied):

- OAI21: Y = ~((A | B) & C)
- OAI22: Y = ~((A | B) & (C | D))

REQ-MOD-003 (cell library), REQ-MOD-012 (levels). Result: **no useful gain; the cell is not proposed for the library and no SPICE model was built.**

## 1. Cells as tried

The follower drives the pentode grid straight (LV out onto a gate grid, the `BUF_N16` rule 2), so the internal follower never chains into another follower, the problem that made `OR2_N16` `dont_use` (doc/follower_chains.md). In OAI21 the follower drives g3 (a stiff driver for the g3 Cb and Miller load), C goes onto g1. The follower "0" is −18.2 V, below the g3 cut-off of the 6Zh2B (Ia = 0 below Ug3 ≈ −10 V, NAND2_J2 page), so the levels fit on paper.

| Cell | Tubes | Liberty (experiment only) |
|---|---|---|
| OAI21_N16J2 | 6Zh2B + 6N16B = 2 | A, B follower grid 2.7 pF; C pentode g1 3.9 pF |
| OAI22_N16J2 | 6Zh2B + 2 × 6N16B = 3 | A–D follower grid 2.7 pF |

A two-input follower OR takes both triodes of a 6N16B, so the OR part cannot be half a tube.

## 2. Measurement

Out of tree: liberty copies with the cells added before `OR2_N16`, `DPC_CELL_LIB=<copy> rtl/run/synth_seeds.sh -s "0 1 2 3" IpLine ApLine MachineCtrl` on master b92acb2 (IP = 4 / AP = 3). Tubes without dekatrons, IpLine + ApLine + MachineCtrl.

| Liberty | seed 0 | 1 | 2 | 3 | mean | Δ | OAI21 / OAI22 placed (all blocks, per seed) |
|---|---|---|---|---|---|---|---|
| base | 905.0 | 902.0 | 895.0 | 888.5 | 897.6 | — | — |
| + OAI21 (2 tubes) | 903.5 | 901.5 | 893.5 | 887.0 | 896.3 | −1.3 | 7–11 / — |
| + OAI22 (3 tubes) | 905.0 | 902.0 | 895.0 | 888.5 | 897.6 | 0 | — / 0 |
| + both | 903.5 | 901.5 | 893.5 | 887.0 | 896.3 | −1.3 | as + OAI21 |
| hypothetical: OAI21 1.5, OAI22 2 tubes | 892.0 | 894.5 | 885.5 | 877.5 | 887.3 | −10.3 | 22–31 / 25–28 |

The last line is a ceiling only: it would need an OR stage at half the price of a 6N16B, which a two-triode follower is not.

## 3. Why there is nothing to gain

- **OAI22 at 3 tubes = NOR2(NOR2(A, B), NOR2(C, D)).** ~((A | B) & (C | D)) is exactly the NOR of two NORs: three `NOR2_N16`, three tubes, all HV, no follower rules. ABC already builds it that way, so the OAI22 cell is never chosen.
- **OAI21 at 2 tubes = A2OOI_J2(A, C, B, C).** ~((A | B) & C) = ~(A·C + B·C), an AOI22 with C on both pentodes, also two tubes. ABC does not duplicate an input when it matches the library, so the OAI21 pattern catches a few more places, but each saves at most a fraction of a tube against NOR2 + NOT + NAND2 (2.5) or a NOR-based cover. −1.3 tubes over 4 seeds is the same sign on every seed but 0.15 % of the total, inside the ±10-tube ABC drift.
- The follower costs a whole 6N16B, the same as a `NOR2_N16` that already gives a restored HV output. The follower only buys an OR without an inversion; in this library the inversion is free in most places (NOR-NOR, AOI with a duplicated input, QN of the triggers).

A costed board would add the dividers too: a follower grid needs its own divider on the driving net (BUF_N16 rule 1), so an OAI21 adds two dividers where the NOR cover shares them with the gate grids of the net.

## 4. Conclusion

OAI21 / OAI22 on NAND2_J2 + OR2_N16 do not pay: −1.3 tubes (OAI21), 0 (OAI22) on ≈ 898. No SPICE model was built (the owner asked for one only if the synthesis showed a gain). The idea would come back only with an OR stage cheaper than a full 6N16B; the half-price ceiling is −10 tubes (≈ 1 %).

Artefacts (scratchpad, not in the tree): the liberty copies and per-seed netlists.
