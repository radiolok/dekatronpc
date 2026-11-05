# Wired anodes: letting ABC put plate outputs in parallel (experiment)

Every NOR, NAND and AOI cell of the library is a pull-down network on one anode resistor.
Two such outputs joined on one plate give the AND of the outputs, and the two pull-down
networks are in parallel, so the joined pair **is** one bigger AOI cell:
`(A·B)' · (C+D)' = (A·B + C + D)'`. Wired-AND needs no extra tube and no new kind of cell,
only AOI cells with more branches. ABC can't join nets by itself, so the experiment gives
it those cells.

## Method

- `doc/data/wired_cells_gen.py <max_inputs> <out.lib>` copies `vtube_cells.lib` and adds
  `WIRED_P<p>T<t>`: p pentode terms (6Zh2B, `A·B`, 1 tube each) and t triode terms
  (6N16B, 0.5 tube each) on one plate, `Y = (Σ A·B + Σ C)'`. Cells that already exist
  are skipped. Pin data are those of the family, the anode resistor is not modelled.
- Limit: ABC's `amap` takes 6 inputs per cell at most, so 6 here
  (`NOR5`, `NOR6`, `P1T3`, `P1T4`, `P2T1`, `P2T2`, `P3T0` are new).
- `DPC_CELL_LIB=<lib> rtl/run/synth_seeds.sh -s "0 1 2 3" IpLine ApLine MachineCtrl`.

## Result (HEAD liberty vs. with the wired cells)

| Seed | 0 | 1 | 2 | 3 | Mean |
|---|---|---|---|---|---|
| HEAD | 1066.0 | 1073.5 | 1070.5 | 1066.0 | 1069.0 |
| wired, ≤ 6 inputs | 1056.0 | 1062.0 | 1059.0 | 1058.0 | **1058.7 (−10.3, ≈ 1 %)** |

Seed 0 uses 26 of the new cells (P2T1 12, P2T2 6, P1T3 3, P3T0 2, P0T5 2, P1T4 1).

## Reading

- The gain is small: the existing NOR2/3/4, AOI21/211/22 already cover most single-fanout
  trees. It is about the size of the TC-O2 step (−6 for AOI211 over NOR3).
- Cells wider than 6 inputs can't be reached through ABC. A post-pass on the mapped
  netlist (AND of single-fanout cell outputs → merge the cells) could go further, but the
  anode load then decides, not tube count.
- **Not checked by hand yet, and it decides everything**: with more branches on one plate
  Ra, the plate current, the low level with many branches conducting, the plate
  capacitance (speed) and the fan-out all change. Each new cell needs its Ra and a level
  check before it can enter `vtube_cells.lib` (REQ-MOD-004/005). These cells are scratch
  only and not in the flow.

## Part 2: cathode followers, OR/AND and wired AO cells (2026-11-05)

A 6Zh2B with a cathode resistor is a non-inverting AND (`A·B`, g1 and g3), a 6N16B triode
follower an OR input, and tied cathodes on one Rk give the wired-OR of the terms. So a
follower cell is `Y = Σ A·B + Σ C`, LV output, p pentodes (1 tube each) + t triodes
(0.5 each). `AND2_J2K` (one 6Zh2B, `A·B`) is not in the liberty and not counted anywhere yet.

Libraries (`doc/data/wired_cells_gen.py` is the first generator; the follower one is
`gen2.py` in the session scratchpad, same cell model, `LV`, `vtube_grid : follower`):

- **F0**: HEAD liberty with the `dont_use` of `BUF_N16`/`OR2_N16`/`OR4_N16` lifted
  (the flow before the owner's 2026-10-30 decision, `doc/follower_chains.md`).
- **F1**: F0 + `AND2_J2K`. **F2**: F0 + all follower AO cells up to 6 inputs.
  **F3**: F2 + the wired AOI cells of Part 1.

`synth_seeds.sh -s "0 1 2 3" IpLine ApLine MachineCtrl` (a run takes about 6 s):

| Library | 0 | 1 | 2 | 3 | Mean | vs F0 |
|---|---|---|---|---|---|---|
| HEAD (followers `dont_use`) | 1066.0 | 1073.5 | 1070.5 | 1066.0 | 1069.0 | |
| F0 followers allowed | 1053.5 | 1060.5 | 1056.5 | 1052.5 | 1055.7 | |
| F1 + `AND2_J2K` | 1044.5 | 1048.0 | 1044.5 | 1040.0 | 1044.2 | −11.5 |
| F2 + follower AO ≤ 6 | 1011.0 | 1019.0 | 1016.5 | 1017.5 | 1016.0 | −39.7 |
| F3 + wired AOI ≤ 6 | 1008.5 | 1015.0 | 1010.0 | 1011.5 | **1011.2** | −44.5 (−57.8 vs HEAD) |

## Reading of Part 2

- Followers with AND/OR terms pay off far more than wired AOI (−40 vs −10), because a
  follower AO cell replaces an AOI plus a NOT, and the NOT is 0.5 tube.
- **None of this is legal yet.** The LV output of a follower can't drive another follower
  grid, ABC doesn't see levels, and F2 will have more follower→follower chains than the
  old 65 (`doc/follower_chains.md`). The numbers are an upper bound on what a
  legalization pass (or a level-aware mapping) could keep. The next step is
  `tools/synth/follower_chains.py` / `div_insert.py` on the F2/F3 netlists, and the
  mapping with the LV → HV rule as a constraint.
- Rk, the cathode current and the pentode AND behaviour (does g3 cut off cleanly with the
  follower load?) need SPICE before `AND2_J2K` can be a cell.

## Part 3: legalization of the follower cells (2026-11-05)

`tools/synth/legalize_followers.py -l <lib> -i <X_netlist.json> -o <out.json>` turns the
mapped netlist legal: for every follower→follower edge (`div_insert.py`: an LV net on a
follower grid is an error) it turns one end into its inverting plate cell found by the
complemented truth table (AO → AOI/NOR/NAND, same tubes) plus a `NOT_N16` (+0.5 tube; a
BUF becomes NOT + NOT). The cells to turn are a minimum-weight vertex cover of the follower
graph (exact branch and bound). LV nets from non-follower sources (decoders, ports) can only be
cured at the receiver, so `div_insert.py` is run on the result and its offenders are forced
in, until no follower-grid error is left. Result: **0 errors on all 48 netlists**
(4 libraries × 4 seeds × 3 blocks). The turned netlists are logically the same by
construction; no simulation, no `equiv_opt`, ABC does not re-map with the constraint.

| Library | synthesis | legalization | **legal total** | vs HEAD 1069.0 |
|---|---|---|---|---|
| HEAD (no followers) | 1069.0 | – | 1069.0 | – |
| wired AOI ≤ 6 (Part 1, no followers) | 1058.7 | – | **1058.7** | −10.3 |
| F0 followers | 1055.7 | +5.6 | 1061.3 | −7.7 |
| F1 + `AND2_J2K` | 1044.2 | +29.1 | 1073.3 | **+4.3** |
| F2 + follower AO | 1016.0 | +50.9 | 1066.9 | −2.1 |
| F3 + wired AOI | 1011.2 | +47.3 | 1058.4 | −10.6 |

Per seed legalization cost: F0 6.5 / 6 / 5.5 / 4.5, F1 28.5 / 32.5 / 28.5 / 27,
F2 51.5 / 52.5 / 50 / 49.5, F3 47 / 50 / 46.5 / 45.5.

**Reading.** Legalization eats nearly all of the follower gain (−44.5 → −10.6). The legal
optimum with followers (F3, 1058.4) equals the one without them (wired AOI, 1058.7), so
followers add nothing once the LV rule holds, and F1 (`AND2_J2K` alone) is worse than HEAD.
The wired AOI cells are the result that stands. A mapping that knows the levels (the LV rule
as a constraint inside ABC) could do better than "map, then turn"; not tried.

## The AO cells (mean per seed, three blocks, F3 after legalization)

Notation: P = a 6Zh2B pentode term `A·B` (1 tube), T = a triode input (0.5 tube).

| Cell | Function | Tubes | Used (synthesis → legal) | Status |
|---|---|---|---|---|
| `AND2_J2K` (P1T0, follower) | A·B | 1 | 111 → 57 | not designed, no Rk |
| `AO_P2T0` (AO22) | A·B + C·D | 2 | 32 → 22 | follower, not designed |
| `AO_P1T1` (AO21) | A·B + C | 1.5 | 24 → 11 | follower, not designed |
| `AO_P0T3` (OR3) | A+B+C | 1.5 | 12 → 8 | follower, not designed |
| `AO_P1T2` (AO211) | A·B + C + D | 2 | 6 → 3 | follower, not designed |
| `AO_P2T2` (AO2211) | A·B + C·D + E + F | 3 | 3 → 2 | follower, not designed |
| `AO_P1T3`, `AO_P2T1` (AO221), `AO_P3T0` (AO222), `AO_P0T6` | | 2.5 / 2.5 / 3 / 3 | ≈ 1–3 each | follower, not designed |
| `WIRED_P2T1` (AOI221) | (A·B + C·D + E)' | 2.5 | 12 → 13.5 | plate cell, not designed |
| `WIRED_P2T2` (AOI2211) | (A·B + C·D + E + F)' | 3 | 2.5 → 4 | plate cell, not designed |
| `WIRED_P1T3` (AOI2111) | (A·B + C + D + E)' | 2.5 | 2.5 → 2.8 | plate cell, not designed |
| `WIRED_P3T0` (AOI222) | (A·B + C·D + E·F)' | 3 | – → 1 | plate cell, not designed |
| `WIRED_P0T5` / `P0T6` / `P1T4` (NOR5, NOR6, AOI21111) | | 2.5 / 3 / 3 | ≈ 0.5–1.2 | plate cell, not designed |

Generators: `doc/data/wired_cells_gen.py` (plate cells), `doc/data/wired_followers_gen.py`
(follower flags `f a o i`).
