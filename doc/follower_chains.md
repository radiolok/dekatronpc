# Follower → follower chains: wider OR cells, legalization, or no followers (2026-10-29)

A cathode follower (BUF_N16, OR2_N16, OR4_N16) puts out LV. Its "1" is too low to drive another follower (`sch/logic/BUF_N16/README.md`, rule 2). ABC does not know the levels, and `div_insert.py` reports every follower grid fed by an LV net. After OR4_N16 (TRS v0.21) there are 65 such grids in IpLine + ApLine + MachineCtrl. The owner asked whether an OR6 would change anything, and then for the count below.

## OR6 / OR8 in the liberty: no effect

OR6_N16 / OR8_N16 cells (3 / 4 tubes, followers with tied cathodes) were added to a copy of the liberty, and the three blocks were synthesized with `-div`. The result was the same to the tube: 1379.5 tubes, 65 chain errors, no OR6 or OR8 in the netlist. A bare 6-input OR synthesized alone becomes OR4 + 2 × OR2 (4 tubes, itself a follower chain) instead of OR6 (3 tubes); an 8-input OR becomes 2 × OR4 + OR2 instead of OR8. ABC's mapper does not use these wide cells, most likely its input limit for library gates (about five). The same is why `OR10_X7` never appears.

## The chains in the current netlists

`tools/synth/follower_chains.py`, on the `run_tests.sh -s` netlists:

- **48 trees** inside modules, plus 3 follower outputs that leave a module through a port. The 65 errors of `div_insert.py` count follower grids, not trees.
- **Leaves per tree:** 3 (25 trees), 4 (10), 5 (5), 6 (5), 7 (1), 8 (1), 11 (1). So 35 trees would fit one OR4, and 46 one OR8.
- **76 inner followers, 60 of them shared:** their output also goes somewhere outside the tree, usually to gate grids. Such an inner cell cannot be removed by merging. A merge only widens the root and keeps the inner cell.

## What legalization would cost

Per tree, the cheaper of:
- **G:** after each inner follower, make the chain legal with a gate. OR → NOR + NOT and BUF → NOT + NOT, HV output; +0.5 tube per inner follower.
- **M:** turn the root into one OR of all the leaves, as wide as the library allows (OR4 / OR6 / OR8). Inner followers that are not shared are removed, shared ones stay.

| Library for the merge | Legalization, best of G and M per tree | Total |
|---|---|---|
| G only | +38 | ≈ 1418 |
| OR2 / OR4 (today) | **+32** | ≈ 1412 |
| + OR6 | **+29** | ≈ 1409 |
| + OR6 + OR8 | +29 | ≈ 1409 |

OR6 saves 3 tubes over today's cells, and OR8 saves nothing more. Merging beats G in only 12 trees.

## No followers at all

The same flow with `dont_use` on the followers:

| Run | Tubes | Chain errors | Notes |
|---|---|---|---|
| today (followers, chains illegal) | 1379.5 | 65 | |
| `dont_use` BUF/OR2/OR4 | 1465.5 | 0 | ABC falls back on the undesigned diode cells: 35 `OR2_N16X7`, 27 `NAND4_N16X7`, 27 `AND2_N16X7` |
| `dont_use` followers and all `*_X7` diode gates | **1464** | 0 | **only designed cells** (plus `GUIDE_EN_J2`): NAND2 277, NOR2 339, NOT 259, NOR4 44, A1OOI 67, A2OOI 10, the flops |

## Conclusion

- **Followers with a legalization pass:** ≈ 1409–1418 tubes.
- **No followers:** 1464 tubes, a netlist of designed cells only, legal by construction, with no new tool.

The followers stay worth about 46–55 tubes even after legalization, but only if the pass is written. Wider OR cells do not matter: OR6 saves 3 tubes, and ABC will not pick them by itself. Owner's call: write the legalization pass, or `dont_use` the followers (and the diode gates, until they are designed).
