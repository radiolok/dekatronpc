# Can the HV/LV levels go lower? (NOR2_N16 at Ea < 150 V)

REQ-MOD-012 (levels, owner 2026-10-23: HV 1 = +150 / 0 = +50 V, LV 1 = +10 / 0 = −20 V, rails +150 / −50 V). Owner's question, 2026-11-04: are the levels optimal, and can HV be lowered while LV stays? Quick SPICE check, not a full cell study.

## Method

`tools/spice/nor2_ea_sweep.py`: the `nor2_sweep.py` chain (ideal HV pulse → divider → driver NOR → divider → DUT → divider → N grids), every gate with La 0.68 mH ‖ 10k. For each (Ea, Ra):
- VOL1 from `.op` (one triode on, grid clamped at +0.3 V, plate loaded by 670k);
- the divider is re-solved so that HV (Ea − 3 V) / VOL1 map to LV +10 / −20 V with R1 + R2 = 670k; that fixes the ratio r and the negative rail Vn;
- C1 per grid is scaled by R2/R1 from the 3.9 pF reference (a rough rule; the grid undershoot below shows it over-compensates by a few volts, so the absolute delays are ±15 %, the trends hold).

## Results (fanout 2 / 10)

| Ea | Ra | VOL1 | I on | P on | r | Vn needed | tpHL | tpLH | grid min |
|---|---|---|---|---|---|---|---|---|---|
| 150 | 10k | 57 V | 9.3 mA | 1.39 W | 0.33 | −59 V | 45 / 59 ns | 98 / 290 ns | −46 V |
| 120 | 10k | 48 V | 7.2 mA | 0.86 W | 0.44 | −73 V | 48 / 67 ns | 118 / 344 ns | −49 V |
| 120 | 6.8k | 57 V | 9.3 mA | 1.11 W | 0.50 | −97 V | 31 / 45 ns | 84 / 241 ns | −54 V |
| 100 | 10k | 42 V | 5.8 mA | 0.58 W | 0.55 | −95 V | 54 / 77 ns | 133 / 418 ns | −51 V |
| 100 | 6.8k | 50 V | 7.4 mA | 0.74 W | 0.63 | −139 V | 34 / 51 ns | 100 / 304 ns | −56 V |
| 100 | 4.7k | 57 V | 9.2 mA | 0.92 W | 0.75 | −244 V | — (HV "0" 84 V, broken) | | −68 V |

## Findings

1. **HV cannot drop on its own while LV stays.** With one −50 V rail the divider maps HV to LV only if VOL = (VOH − 50)/2: 50 V at 150 V, 35 V at 120 V, 25 V at 100 V. A 6N16B triode with its grid at 0 V does not reach such plate voltages at a useful current. So the LV swing of 30 V needs a smaller attenuation (r 0.33 → 0.5…0.63) and a negative rail of −73…−139 V, and the HV swing (≈ 90 V now, 60 V at 120 V, 45–55 V at 100 V) loses noise margin.
2. **Speed is set by the plate current, not by Ea.** A delay is ≈ C·ΔU / I. With Ra kept at 10k the current falls as Ea falls, and tpLH at fanout 10 grows 290 → 344 → 418 ns (+19 % / +44 %). Restoring the speed means a smaller Ra and the same ≈ 9.3 mA, so the only gain is P = Ea·I: −20 % of plate power at 120 V.
3. **The gain is small for the machine.** Plate power of a gate is ≤ 1.4 W while on, ≈ 0.7 W on average; the heater is 2.5 W per 6N16B. −20 % of the plate power is ≈ 5 % of the total.
4. **+150 V is also anchored outside the gates:** the dekatron cathode pull-up Rп and the reset-by-cathode bus (100…150 V, Yablonsky p. 115–116; `sch/logic/DEKATRON_A110/README.md` §3.2), the 6Zh2B screens fed through Rg2 from +150 V (lower Ea → lower Ug2 → slower pentode cells), the guide keys.
5. **LV is about right.** The LV "1" (+10 V) is only the divider's open-circuit level; the grids clamp it at ≈ 0 V. The LV "0" (−20 V) has 12 V of margin to the triode cut-off (VIL −7.6 V at 150 V) and 10 V to the 6Zh2B g3 cut-off (Ia = 0 below ≈ −10 V); it is also the dekatron read level of an unlit cathode (REQ-DEK-016). −15 V would leave only 5 V on g3.

## Conclusion

The present levels are close to optimal for 6N16B at Ra 10k: the HV swing is what the triode gives at Ug ≈ 0, and the 0.3 divider maps it to LV with the one −50 V rail. Lowering HV with LV fixed is not recommended: it needs a new, more negative rail, costs HV noise margin, and gains speed only if Ra drops (same current, −20 % plate power, ≈ −5 % in total). If power ever matters, the option worth a study is a proportional scaling of both families together (e.g. 120 V with LV 0 ≈ −16 V, since the cut-off scales as Ua/μ), not done here.

**Follow-up (2026-11-04):** the owner chose 120 V (6S51N nuvistors, 6Zh2B screen); the LV levels for it are in `doc/lv_levels_120v.md`. The −50 V rail stays: with LV "0" ≈ −15 V the divider is 430k/220k, and NOR2/NAND2 keep or improve their speed.
