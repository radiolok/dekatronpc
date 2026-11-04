# Anode-gated cathode follower as an AND2 (6N16B): static study

Owner's idea (2026-11-04): one 6N16B triode used as a controlled switch. Input A (HV) goes to the plate, input B (LV) to the grid, and Y = A · B is taken from the cathode. Several such triodes on one cathode load would give AO terms for AOI cells. REQ-MOD-003 (cell library), REQ-MOD-012 (levels), method: `doc/cell_design_method.md` (§4d, cathode followers).

Script: `tools/spice/agf_static.py` (`.op` only, nominal model `sch/libs/6N16B.sub`). The stage is the BUF_N16 follower: cathode → Rs 2.2k → Y → Rk 12k → −50 V, B from its own 470k / 200k divider. The load is 10 grids (5 NOT-type tubes, Ra 10k). Levels: HV 1 = +150, 0 = +50 V; LV 1 = +10, 0 = −20 V; the next stage reads its HV net as "0" below 92 V and as "1" above 118 V.

## Result: it does not gate with HV levels

| A (plate) | B | Y | load plate | Ia | expected |
|---|---|---|---|---|---|
| +150 | 1 | +0.54 V | 53 V ("1") | 5.4 mA | 1 |
| +150 | 0 | −18.8 V | 150 V ("0") | 2.6 mA | 0 |
| **+50** | **1** | **−0.31 V** | **68 V ("1")** | 4.1 mA | **0: fails** |
| +50 | 0 | −22.2 V | 150 V | 2.3 mA | 0 |
| 0 | 1 | −22.2 V | 150 V ("0") | 2.1 mA | 0 |
| −20 | 1 | −33.1 V | 150 V | 1.1 mA | 0 |

A cathode follower needs only a few tens of volts across the tube. The cathode sits near +9 V (grid +8.8 V), so a plate at +50 V still has ≈ 40 V of Uak, and at Ugk ≈ 0 the 6N16B passes the 4 mA the cathode load asks for. The plate input switches Y only below the cathode level:

| A, B = 1 | +60 | +50 | +40 | +35 | +30 | +20 | 0 |
|---|---|---|---|---|---|---|---|
| load plate | 62 V | 68 V | 106 V | 135 V | 148 V | 150 V | 150 V |

The A threshold is ≈ +37 V, so A needs a "0" of about +25 V or lower, and a "1" of +60 V or higher. A "0" of +50 V (HV) lands on the "1" side with 13 V to spare.

## Driving A from a gate plate is worse still

The plate input carries the whole cathode current (2–5.4 mA), so it is a power input, not a grid:

| driver (Ra 10k) | A | Y | load plate |
|---|---|---|---|
| off (grid −20 V) | 103 V (instead of 150) | +0.38 V | 56 V |
| on (grid clamped +0.3 V) | 45 V | −0.61 V | 74 V ("1": fails) |

- The "1" sags by 47 V on one gated follower. Two A inputs on one net (≈ 10 mA through Ra 10k) bring the "1" down to about the threshold: an A net has a fanout of 1, and the net cannot feed grids at the same time, because its levels depend on Y's load.
- A plain gate with its cathode on 0 V cannot pull its plate below +40…50 V while it sinks 5 mA. An A driver would need its own level family (a "0" of 0 … −20 V at 5 mA): a cathode at −50 V or a follower driver, and so a level shift on its own input. That is at least one more half-tube per A net, and it removes the saving.

## Grid B with A low

With A below the cathode the grid is the most positive electrode, and the grid–cathode diode conducts. On B's own divider the grid falls from +8.8 V to −16 V at A = 0 (0.18 mA). That is harmless with a private divider (BUF_N16 rule 1 asks for one anyway), but the grid then starts from −16 V when A rises, which slows the A↑ edge. A B net shared with gate grids would be pulled down for all of them.

## AOI built this way

Several gated followers on one cathode load make Y = A1·B1 + A2·B2 + … (the OR2_N16 wiring). Static case A1 = 1, B1 = 0, A2 = +50 V ("0"), B2 = 1: Y = −0.31 V, load plate 68 V, so the AO22 reads "1" where it should read "0". The same plate-level fault, now in every term. Even with a suitable A driver, the AOI would need:

- an inverter behind the wired-OR (Y is LV, as with OR2_N16), so ½ 6N16B per term plus ½ for the NOT;
- one A driver per A net in the new level family, with fanout 1;
- the follower restrictions of §4d: a private divider on every B grid, Y onto gate grids only, and the wired-OR hazard of OR2_N16.

For comparison, A2OOI_J2 (AOI22) is 2 × 6Zh2B with ordinary LV inputs, and A1OOI_N16J2 (AOI21) is 6Zh2B + ½ 6N16B.

## Conclusion

In the current HV/LV level families the anode-gated follower is not an AND: an HV "0" of +50 V keeps the triode conducting, and the plate input loads its driver by 2–5 mA. It works only with a dedicated A level family ("0" ≤ +25 V, "1" ≥ +60 V, ≥ 5 mA per input), which needs a tube per A net and gives fanout 1. That is no cheaper than the existing pentode AND cells. No transient run: the static check already rejects the topology (method §2, step 1).

Not studied: changing the levels (REQ-MOD-012) or the HV "0" for the whole machine. Ask the owner before going there.
