# NAND2_J2: two-input NAND on one 6Zh2B

Cell page. REQ-MOD-005 (2И-НЕ board), REQ-MOD-012 (logic levels), REQ-MOD-004 (delays, fan-out, power; simulated, not yet measured). Method: `doc/cell_design_method.md`.

**Status: in progress.** The tube model is done; the circuit is being designed.

| | |
|---|---|
| Function | Y = ~(A · B) |
| Tubes | one 6Zh2B (6Ж2Б), the pentode with two control grids |
| Input A | LV level, grid 1 |
| Input B | LV level, grid 3 |
| Output Y | HV level, plate |
| Supplies | +150 V (plate; screen through Rg2); −50 V (dividers only); heater 6.3 V, 0.2 A |

The owner confirmed on 2026-10-24: A on g1, B on g3, both LV (+10 / −20 V), output HV (+150 / +50 V), one 6Zh2B, supplies +150 / −50 V, the screen fed through a dropping resistor Rg2 from +150 V (no new rail).

## Model

`sch/libs/6Zh2B.sub` is a behavioural model. `tools/spice/fit_6zh2b.py` fits it by least squares to all digitized points of Рис. 215 and 216 (`doc/data/6zh2b_datasheet.json`), weighting each point by 0.05 mA + 3 %, and writes the file (`--sub`). The comparison with the sheet is in `doc/6zh2b_datasheet.md`, section Model.

The pin order is `A G3 G2 K G1`, so the KiCad symbol `vacuum_tube:6Ж2Б` (handbook numbering) maps as `Sim.Pins "1=A 2=G3 3=G2 6=K 7=G1"`; the heater (4, 5) is not modelled.

Equations, with sp(x) = max(x, 0) + s·ln(1 + e^(−|x|/s)) a smooth max(x, 0):

- **Space current:** Ik = K · sp(Ug1 + Ug2/MU2 + Ug3/MU3 + Ua/MUA)^EX.
- **Plate share:** F = FM · tanh(sp(Ug3 + Ua/D − U0 − U1·Ik) / W3) · tanh(max(Ua, 0) / (VA0 + VA1·Ik)), Ik in mA. The first factor is the control by g3, the second the knee at low plate voltage; both depend on the current through space charge.
- **Currents:** Ia = Ik · F, Ig2 = Ik · (1 − F).

| Parameter | Value | Meaning |
|---|---|---|
| K, EX | 1.93e-4, 2.63 | power law of the space current |
| MU2 | 20.0 | g1–g2 amplification factor |
| MU3 | 49.3 | effect of g3 on the space current |
| MUA | 1104 | effect of the plate on the space current |
| FM | 0.806 | largest plate share |
| D, U0, U1, W3 | 95.8, −6.35 V, 0.100 V/mA, 5.88 V | current division by g3 |
| VA0, VA1 | 12.0 V, 0.85 V/mA | knee at low Ua |

Fit residuals: rms 0.1–0.45 mA on Рис. 215 and 0.2–0.6 mA on Рис. 216. The largest errors are 1.4 mA at Ug1 = −1 V on Рис. 216: there the sheet shows a dip of the total current at Ug3 = −4…−6 V (a virtual cathode in front of g3) that the model does not reproduce. The two figures of the sheet disagree with each other by up to 7 % at the point where they meet.

**Assumptions** (not on the sheets; to be measured, REQ-MOD-004):

- **Ug2 dependence.** The sheets give only Ug2 = 120 V. MU2 comes from the cut-off through the power law, with no contact potential. The cell feeds the screen through Rg2, so its operating point depends on this, and the cell is checked with MU2 ± 20 %.
- **Grid currents.** g1 and g3 conduct through a diode (IS = 1 nA) behind RG1 = 2 kΩ and RG3 = 5 kΩ, like the 6N16B model. The grid current is not taken from the space current.
- **Capacitances.** The sheet gives Cin = 4.9 pF, Cout = 4.1 pF and Cg1a ≤ 0.03 pF. The split is assumed: Cg1k 3.0, Cg1g2 1.9, Cg1a 0.03 pF; Cg3a 2.5, Cg3k 3.0 (g3 is not on the sheet), Cak 1.6 pF (Cout = Cg3a + Cak). The cell is checked with Cg3a varied.
