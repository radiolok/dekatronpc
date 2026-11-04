# LV levels for a 120 V plate supply (NOR2_N16, NAND2_J2)

REQ-MOD-012 (levels), REQ-MOD-004/005 (cells). Owner, 2026-11-04: 120 V looks like a good optimum, because the 6S51N (6С51Н) nuvistors are rated 120 V at most and the 6Zh2B gets an easier life; tune the LV levels and keep the speed; check NOR2 and NAND2. Follows `doc/hv_supply_reduction.md`. SPICE only: the cells' schematics, liberty and TRS are not changed.

## Method

`tools/spice/lv120_sweep.py` (`static` | `tran [cases.py]`) reuses the decks of `nor2_sweep.py` and `nand2_sweep.py` and patches in the supply, the divider rail, the HV stimulus levels and the thresholds.
- **Static:** `.op` of the cell (on-grids held at +0.4 V, off-grids at −20 V, plate loaded by 670k) gives VOH / VOL; the divider is solved for a target LV "0" or fixed; a DC sweep with the output loaded by its divider and 4 grids gives VIL (first point where the LV → LV gain reaches −1) for the triode/g1 and for g3.
- **Transient:** the reference chains (ideal HV pulse → divider → driver gate → divider → DUT → divider → N grids), fanout 2…10. All cases, the 150 V references included, use the same thresholds: LV −3 V (near the switching point at 120 V) and HV at the middle of the case's own levels. So the 150 V figures here differ from the cell pages (−5 V / 100 V there); compare within this report only. The best speed figure is **LV → LV** (gate plus divider, same threshold on both sides).
- Scanned: Ra 10k / 8.2k / 6.8k (NOR); Ra/Rg2 15k/15k, 12k/12k, 12k/10k, 10k/10k, 10k/8.2k (NAND); rail −50 / −40 V; LV "0" −12 / −15 / −18 V. Then a common divider was checked with C1 ±15 % and the 6Zh2B MU2 ±20 %.

## What changes at 120 V

- Cut-off moves closer to 0 V: VIL of the 6N16B grid and the 6Zh2B g1 is −5.0…−5.3 V (−6.5 V at 150 V), of g3 −7.0…−7.2 V (−7.5 V). So the LV "0" can rise from −20 V to about −15 V with a similar margin in volts per cut-off.
- **The −50 V rail stays.** With LV "0" −15…−18 V the divider ratio is 0.33–0.36 and the open-circuit LV "1" is +5…+14 V, enough for the grid clamp. A −40 V rail gives an LV "1" of −3.5…+8 V at LV "0" −15…−18 V (mostly below +5 V): too weak (the clamp needs current), rejected.
- The LV "0" −12 V leaves only ≈ 7 V (g1) and ≈ 5 V (g3) of margin; −18 V needs a small ratio and leaves the LV "1" at +1…+4 V on most cells. −15…−16 V is the middle.

## Chosen point: one divider 430k / 220k for both cells

| | 150 V reference | 120 V proposed |
|---|---|---|
| HV levels | 147 / 55 V (NOR), 146 / 46 V (NAND) | 118 / 51…55 V (NOR), 117 / 44…49 V (NAND) |
| Divider | 470k ‖ C1 / 200k to −50 V, r = 0.30 | **430k ‖ C1 / 220k to −50 V, r = 0.34** |
| C1 per grid | 3.9 pF triode/g1, 6.8 pF g3 | **4.7 pF triode/g1, 8.2 pF g3** (both E12) |
| LV "1" open / clamped | +8.8 / +0.4 V | +6.5…7.0 / +0.36 V |
| LV "0", static | −18.6 V (NOR), −21.4 V (NAND) | −14.3 (NOR 6.8k), −15.8 (NOR 8.2k), −18.2 V (NAND 12k/10k) |

Cell parts at 120 V: **NOR2_N16 Ra 8.2k** (or 6.8k for speed), La ‖ Rd unchanged; **NAND2_J2 Ra 12k, Rg2 10k**, Cb 15 pF unchanged.

### NOR2_N16 (fanout 2 / 6 / 10)

| Case | tpHL | tpLH | LV → LV fall / rise | LV "0" margin (static) | Lowest grid | Supply power, chain |
|---|---|---|---|---|---|---|
| 150 V, Ra 10k | 38 / 48 / 55 | 90 / 174 / 261 | 14/111, 24/233, 29/366 | 12.1 V | −39.8 V | 3.5…5.3 W |
| 120 V, Ra 8.2k | 35 / 44 / 52 | 79 / 155 / 234 | 17/82, 25/180, 32/284 | 10.7 V | −34.2 V | 2.5…3.9 W (−27 %) |
| 120 V, Ra 6.8k | 29 / 36 / 42 | 66 / 127 / 193 | 12/65, 20/144, 27/223 | 9.3 V | −34.3 V | 2.7…4.6 W (−14 %) |

- Faster at 120 V although the current is the same or lower: the HV swing is 63–67 V instead of 92 V, and the delay is ≈ C·ΔU / I.
- C1 ±15 % (4.0 / 5.4 pF): the lowest grid is −27…−40 V, within −50 V; LV → LV rise at fanout 10 is 220–249 ns (6.8k) and 284–315 ns (8.2k). The ripple of ±15 % works.
- Pa per triode on: 0.42 W (8.2k), 0.52 W (6.8k, the same as now); limit 0.9 W.

### NAND2_J2 (fanout 2 / 6 / 10)

| Case | tpHL A | tpLH A | LV → LV fall / rise | Ik (MU2 −20 %) | Pg2 max | LV "0" at the input, dynamic (MU2 +20 %) |
|---|---|---|---|---|---|---|
| 150 V, 15k/15k | 188 / 357 / 457 | 121 / 272 / 406 | 40/201, 124/491, 159/767 | 11.2 (12.6) mA | 0.37 W | −21.1 V |
| 120 V, 12k/10k | 137 / 286 / 401 | 105 / 242 / 367 | 50/163, 123/415, 173/657 | 10.1 (11.9) mA | 0.36 W | −17.7 (−14.3) V |
| 120 V, 10k/8.2k | 113 / 239 / 352 | 87 / 203 / 312 | 44/129, 106/335, 165/537 | 11.2 (13.5) mA | 0.44 W | −15.9 (−12.4) V |
| 120 V, 15k/15k (LV "0" −15) | 137 / 293 / 384 | 150 / 352 / 530 | 42/212, 122/610, 141/985 | 8.2 mA | 0.24 W | −15.0 V |

- 12k/10k keeps the speed (every arc as fast or faster, LV → LV rise −14…−19 %, fall within +10 %) with less current than now. 10k/8.2k is 20–30 % faster, but at MU2 +20 % its LV "0" sits at −12.4 V, 5.4 V from the g3 VIL; Ik reaches 13.5 mA of 14 at MU2 −20 %.
- Keeping Ra/Rg2 at 15k is slower (rise +30 %): the plate current drops with Ea.
- **Weak point:** the g3 margin. At 150 V the LV "0" was 13.6 V below the g3 VIL; with 12k/10k it is 10.5 V nominal and 7.1 V at MU2 +20 %. A NAND output drives a weaker "0" than a NOR, so a net that feeds g3 inputs gets the smaller margin.
- C1 ±15 % (4.0/7.0 and 5.4/9.4 pF): the lowest grid is −20…−29 V; at −15 % the output LV "0" crawls (−14.2 V at fanout 10 after 2 µs), at +15 % the rise slows (776 ns at fanout 10). The nominal 4.7 / 8.2 pF is the middle; the window is as narrow as at 150 V.
- **Screen:** at 120 V the screen of a cut-off 6Zh2B is 120 V, within the handbook's 125 V, which closes the 150 V open point of the cell page.

## Proposal (pending the owner)

- Plate supply **+120 V**, divider rail **−50 V** unchanged.
- HV: "1" ≈ +117 V, "0" ≈ +45…55 V. LV: "1" = +7 V open circuit (clamped ≈ 0 V), "0" ≈ **−15 V** (−14…−18 V by cell). Divider **430k ‖ C1 / 220k**, r = 0.34; C1 = 4.7 pF per triode/g1 grid, 8.2 pF per g3 grid.
- NOR2_N16: Ra 8.2k (−27 % power, 10–20 % faster) or 6.8k (25–40 % faster, −14 % power). NAND2_J2: Ra 12k, Rg2 10k.
- Noise margin of the LV "0": 9–11 V (triode, g1), 7–11 V (g3); now 12–14 V.

## Not checked yet

- Other cells at 120 V: the followers BUF/OR2/OR4_N16 (Rk to −50 V, LV output straight to grids), NOR3/NOR4, NOT, the AOI cells, RSLATCH/DLATCH2/DFF/DFFRN, KEYDB, the TC-N5 pulse flip-flop (uncompensated 150k/62k dividers), the dekatron module (Rп pull-up: 120 V is inside the 100…150 V of Yablonsky; guide pulse amplitude from Ra to +120 V), RELAY_HOLD.
- `div_insert.py` and the liberty carry C1 3.9 / 6.8 pF and the HV/LV thresholds; `vtube_timing.json` has the 150 V delays.
- The 6S51N itself: no model in `sch/libs/` yet.
